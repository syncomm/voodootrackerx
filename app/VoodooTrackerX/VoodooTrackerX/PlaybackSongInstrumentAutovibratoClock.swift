import Foundation

/// Inert natural clock facts. No waveform ordinate, amplitude or period is produced.
struct PlaybackSongInstrumentAutovibratoClock: Equatable {
    enum Coverage { case notAdapterProduced, depthOffV1 }
    enum Waveform: UInt8 { case sine, square, rampDown, rampUp }
    enum Status { case unowned, ordinary, policyPending }
    // Retrigger is an automatic lifecycle anchor at real E9 dispatch, not a legacy reset observation.
    enum ResetCause: UInt8 { case rowEntry, delayedInstrument, delayedNote, refused, retrigger }
    struct Result: Equatable {
        let phaseBefore: UInt8?, phaseAfter: UInt8?
        let elapsedTicks: Int, sweepElapsed: Int
        // Nominal duration completion only, never rounded integer amplitude completion.
        let sweepReached: Bool?
        let released: Bool
        let raw: PlaybackInstrumentAutoVibrato?
        let waveform: Waveform?
        let status: Status
        let lastResetOrdinal: Int?
        let resetCause: ResetCause?
    }
    /// State immediately before ordinal. Owner/reset/release transitions alone retain runs.
    struct Run: Equatable {
        var ordinal = 0, elapsed = 0, sweepElapsed = 0, owner = -1, resetOrdinal = -1
        var raw = PlaybackInstrumentAutoVibrato.disabled
        var phase: UInt8? = nil
        var resetCause: ResetCause? = nil
        // Release and legacy visibility share one byte, preserving the compact
        // anchor while the same numeric phase supports safe playback interpretation.
        private var lifecycleFlags: UInt8 = 0
        var released: Bool {
            get { lifecycleFlags & 1 != 0 }
            set { lifecycleFlags = newValue ? lifecycleFlags | 1 : lifecycleFlags & ~1 }
        }
        var rawPhaseAvailable: Bool {
            get { lifecycleFlags & 2 != 0 }
            set { lifecycleFlags = newValue ? lifecycleFlags | 2 : lifecycleFlags & ~2 }
        }
        var wellFormed: Bool { raw.waveformType < 4 && raw.depth <= 15 && raw.rate <= 63 }

        func advancing(to ordinal: Int) -> Self {
            var result = self
            let ticks = ordinal - self.ordinal
            precondition(ticks >= 0, "Clock transitions must follow canonical traversal")
            if owner >= 0 {
                result.elapsed += ticks
                if !released { result.sweepElapsed += ticks }
                if let phase {
                    // One existing phase follows playback-only capped rate. Public raw
                    // foundation queries still expose malformed phase as unavailable.
                    result.phase = phase &+ UInt8((ticks & 255) * Int(min(63, raw.rate)) & 255)
                } else { result.phase = nil }
            }
            result.ordinal = ordinal
            return result
        }

        func result(at ordinal: Int, interpreted: Bool = false) -> Result {
            let before = advancing(to: ordinal), after = before.advancing(to: ordinal + 1)
            let owned = owner >= 0
            let reached: Bool? = owned && (interpreted || wellFormed) && (interpreted || raw.sweep != 255)
                ? after.sweepElapsed >= Int(raw.sweep) : nil
            let pending = !wellFormed || !rawPhaseAvailable || raw.sweep == 255 ||
                (raw.depth > 0 && raw.rate == 0 && raw.waveformType == 1) ||
                (released && raw.depth > 0 && reached != true)
            return .init(phaseBefore: interpreted || (wellFormed && rawPhaseAvailable) ? before.phase : nil,
                phaseAfter: interpreted || (wellFormed && rawPhaseAvailable) ? after.phase : nil,
                elapsedTicks: after.elapsed, sweepElapsed: after.sweepElapsed, sweepReached: reached,
                released: released, raw: owned ? raw : nil, waveform: owned ? Waveform(rawValue: raw.waveformType) : nil,
                status: owned ? (pending && !interpreted ? .policyPending : .ordinary) : .unowned,
                lastResetOrdinal: resetOrdinal >= 0 ? resetOrdinal : nil, resetCause: resetCause)
        }
    }
    let coverage: Coverage
    let channels: [[Run]]
    let storageGrowthCount: Int
    let workspaceCapacity: Int
    var runCount: Int { channels.reduce(0) { $0 + $1.count } }
    var runCapacity: Int { channels.reduce(0) { $0 + $1.capacity } }
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, channels: [], storageGrowthCount: 0, workspaceCapacity: 0)

    struct Builder {
        var channels = [[Run]](), resets = [ResetCause?](), releases = [Bool]()
        var growths = 0
        var valid = true
        mutating func ensureChannels(_ count: Int) {
            while channels.count < count {
                let capacities = (channels.capacity, resets.capacity, releases.capacity)
                channels.append([]); resets.append(nil); releases.append(false)
                growths += (capacities.0 != channels.capacity ? 1 : 0) +
                    (capacities.1 != resets.capacity ? 1 : 0) + (capacities.2 != releases.capacity ? 1 : 0)
            }
        }
        mutating func publish(channel: Int, ordinal: Int, instrument: Int?, song: borrowing PlaybackSong) {
            guard valid else { return }
            let prior = channels[channel].last ?? Run()
            let owner = instrument ?? -1, reset = resets[channel], release = releases[channel]
            resets[channel] = nil; releases[channel] = false
            guard prior.owner != owner || reset != nil || (release && !prior.released) else { return }
            var run = prior.advancing(to: ordinal)
            run.owner = owner; run.raw = song.instrumentsByIndex[owner]?.autoVibrato ?? .disabled
            if reset != nil {
                run.phase = 0; run.rawPhaseAvailable = true; run.elapsed = 0; run.sweepElapsed = 0; run.released = false
                run.resetOrdinal = ordinal; run.resetCause = reset
            } else if prior.owner < 0 && owner >= 0 { run.phase = 0; run.rawPhaseAvailable = true }
            if owner < 0 { run.phase = nil }
            if owner < 0 || !run.wellFormed { run.rawPhaseAvailable = false }
            if release { run.released = true }
            let capacity = channels[channel].capacity
            channels[channel].append(run)
            if capacity != channels[channel].capacity { growths += 1 }
        }
        var evidence: PlaybackSongInstrumentAutovibratoClock {
            guard valid else { return .notAdapterProduced }
            return .init(coverage: .depthOffV1, channels: channels, storageGrowthCount: growths,
                workspaceCapacity: resets.capacity + releases.capacity)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Queries the canonical song clock; envelope tails and window continuation cannot extend it.
    func instrumentAutovibrato(row: Int, tick: Int, channel: Int) -> PlaybackSongInstrumentAutovibratoClock.Result? {
        let clock = instrumentAutovibratoClock
        guard clock.coverage == .depthOffV1,
              let coordinate = canonicalTickClock.coordinate(syntheticRow: row, tick: tick, channel: channel),
              clock.channels.indices.contains(channel) else { return nil }
        let runs = clock.channels[channel], ordinal = coordinate.canonicalTickOrdinal
        var low = 0, high = runs.count
        while low < high {
            let middle = low + (high - low) / 2
            if runs[middle].ordinal <= ordinal { low = middle + 1 } else { high = middle }
        }
        return (low == 0 ? PlaybackSongInstrumentAutovibratoClock.Run() : runs[low - 1]).result(at: ordinal)
    }
}
