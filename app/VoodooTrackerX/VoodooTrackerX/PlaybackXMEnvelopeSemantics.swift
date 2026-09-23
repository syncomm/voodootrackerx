import Foundation

/// A held semantic target. Source playback and audible ramps have separate ownership.
struct MixerEnvelopeSemanticState: Equatable {
    var volumeTick = 0
    var panTick = 0
    var keyOn = true
    var fadeoutAccumulator = 32_768
    var volumeValue: Float = 1

    var fadeoutValue: Float { Float(fadeoutAccumulator) / 32_768 }
}

struct PlaybackXMEnvelopeUpdate: Equatable {
    let eventIndex: Int
    let channelIndex: Int
    let source: PlaybackPosition
    let tick: Int
    let scheduledFrame: Int
    let bpm: Int
    let speed: Int
    let state: MixerEnvelopeSemanticState
}

/// Derives all envelope/release targets from the already traversed Fxx timeline.
/// Neither renderer advances this state from elapsed samples or a cached BPM.
struct PlaybackXMEnvelopeTimeline: Equatable {
    struct Instrument: Equatable {
        let volume: PlaybackVolumeEnvelope
        let pan: PlaybackPanningEnvelope
    }

    let timing: PlaybackSongFxxTimingPlan
    let instruments: [Int: Instrument]
    private(set) var endFrame: Int
    private(set) var updates: [PlaybackXMEnvelopeUpdate] = []
    private(set) var updatesByEvent: [Int: [PlaybackXMEnvelopeUpdate]] = [:]

    init(song: PlaybackSong, timing: PlaybackSongFxxTimingPlan, plan: PlaybackSongSyntheticPlan) {
        self.timing = timing
        endFrame = timing.frameFor(row: timing.rowTimings.count)
        instruments = Dictionary(uniqueKeysWithValues: plan.diagnostics.eventMappings.compactMap { mapping in
            guard let instrument = song.instrumentsByIndex[mapping.instrumentIndex] else { return nil }
            let volume = instrument.volumeEnvelope
            let pan = instrument.panningEnvelope
            return (mapping.eventIndex, Instrument(volume: PlaybackVolumeEnvelope(enabled: volume.enabled,
                points: Array(volume.points.prefix(12)), sustainPointIndex: volume.sustainPointIndex,
                loopStartPointIndex: volume.loopStartPointIndex, loopEndPointIndex: volume.loopEndPointIndex,
                typeFlags: volume.typeFlags, fadeout: volume.fadeout), pan: PlaybackPanningEnvelope(enabled: pan.enabled,
                points: Array(pan.points.prefix(12)), sustainPointIndex: pan.sustainPointIndex,
                loopStartPointIndex: pan.loopStartPointIndex, loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags)))
        })
        rebuild(plan: plan)
    }

    /// Re-fold explicit reset history while retaining the canonical tick frames.
    mutating func rebuild(plan: PlaybackSongSyntheticPlan) {
        updates = []
        updatesByEvent = [:]
        guard plan.pattern.events.contains(where: { $0.volumeEnvelope != nil || $0.panEnvelope != nil }) ||
                plan.diagnostics.keyOffEvents.contains(where: \.applied) || !plan.playbackStateEvents.isEmpty else { return }
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        let mappings = plan.diagnostics.eventMappings.sorted { $0.eventIndex < $1.eventIndex }
        struct Tick {
            let row: Int
            let source: PlaybackPosition
            let tick: Int
            let frame: Int
            let bpm: Int
            let speed: Int
            var advances = true
        }
        var ticks = [Tick]()
        var rowIndex = 0
        while rowIndex < timing.rowTimings.count || timing.frameFor(row: rowIndex) < endFrame {
            guard let source = timing.rowTimings.indices.contains(rowIndex)
                ? timing.rowTimings[rowIndex].source : timing.rowTimings.last?.source else { break }
            let config = timing.timingConfig(forSyntheticRow: rowIndex)
            for tick in 0..<config.speed {
                ticks.append(Tick(row: rowIndex, source: source, tick: tick,
                    frame: timing.frameFor(row: rowIndex, tick: tick), bpm: config.bpm, speed: config.speed))
            }
            rowIndex += 1
        }
        let tickFrames = Set(ticks.map(\.frame))
        var nextByEvent = [Int: Int]()
        var lastByChannel = [Int: Int]()
        for mapping in mappings.reversed() {
            nextByEvent[mapping.eventIndex] = lastByChannel[mapping.channelIndex]
            lastByChannel[mapping.channelIndex] = mapping.eventIndex
        }
        let changes = PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan)
        let cutsByEvent = Dictionary(grouping: plan.diagnostics.noteCutEffects.filter(\.applied), by: { $0.activeEventIndex ?? -1 })
        let releasesByEvent = Dictionary(grouping: plan.diagnostics.keyOffEvents.filter(\.applied), by: { $0.activeEventIndex ?? -1 })
        let positionsByEvent = Dictionary(grouping: plan.diagnostics.envelopePositionEffects.filter(\.applied), by: { $0.activeEventIndex ?? -1 })
        let changesByEvent = Dictionary(grouping: changes, by: \.activeEventIndex)
        for mapping in mappings {
            let index = mapping.eventIndex
            guard let instrument = instruments[index], plan.pattern.events.indices.contains(index) else { continue }
            let event = plan.pattern.events[index]
            let start = scheduler.frame(for: event)
            let end = nextByEvent[index].map { scheduler.frame(for: plan.pattern.events[$0]) } ?? Int.max
            let cuts = (cutsByEvent[index] ?? []).compactMap(\.scheduledFrame)
            let stop = min(end, cuts.min() ?? Int.max)
            let releases = Set((releasesByEvent[index] ?? []).compactMap(\.scheduledFrame))
            let positions = positionsByEvent[index] ?? []
            let resets = changesByEvent[index] ?? []
            // Plain voices need no envelope stream until release or an explicit state operation.
            guard event.volumeEnvelope != nil || event.panEnvelope != nil || !releases.isEmpty || !resets.isEmpty else { continue }
            var state = MixerEnvelopeSemanticState()
            var first = true
            var history = [PlaybackXMEnvelopeUpdate]()
            var low = 0
            var high = ticks.count
            while low < high {
                let middle = (low + high) / 2
                if ticks[middle].frame < start { low = middle + 1 } else { high = middle }
            }
            var clock = Array(ticks[low...].prefix { $0.frame < stop })
            for frame in Set(resets.map(\.scheduledFrame)).subtracting(tickFrames) where frame >= start && frame < stop {
                if let context = ticks.last(where: { $0.frame <= frame }) {
                    clock.append(Tick(row: context.row, source: context.source, tick: context.tick,
                        frame: frame, bpm: context.bpm, speed: context.speed, advances: false))
                }
            }
            clock.sort {
                if $0.frame != $1.frame { return $0.frame < $1.frame }
                return $0.row == $1.row ? $0.tick < $1.tick : $0.row < $1.row
            }
            for tick in clock {
                let frame = tick.frame
                guard frame >= start && frame < stop else { continue }
                var resetVolume = first
                var resetPan = first
                let wasKeyOn = state.keyOn
                for reset in resets where reset.scheduledFrame == frame {
                    switch reset.change {
                    case let .reset(dimensions):
                        if dimensions.volumeEnvelope { state.volumeTick = 0; resetVolume = true }
                        if dimensions.panEnvelope { state.panTick = 0; resetPan = true }
                        if dimensions.keyOn { state.keyOn = true }
                        if dimensions.fadeout { state.fadeoutAccumulator = 32_768 }
                    case .keyOff:
                        // XM uses the instrument's tick fadeout; per-frame rates belong to generic synthetic voices.
                        state.keyOn = false
                    }
                }
                if releases.contains(frame) { state.keyOn = false }
                let releasing = wasKeyOn && !state.keyOn
                if event.volumeEnvelope != nil {
                    if let position = positions.last(where: { $0.scheduledFrame == frame }) {
                        state.volumeTick = Int(position.effectParam)
                    } else if !resetVolume && tick.advances {
                        state.volumeTick = Self.advance(state.volumeTick, envelope: instrument.volume,
                            keyOn: state.keyOn, releasing: releasing)
                    }
                    state.volumeValue = instrument.volume.value(at: state.volumeTick)
                }
                if event.panEnvelope != nil && !resetPan && tick.advances {
                    let pan = instrument.pan
                    let clock = PlaybackVolumeEnvelope(enabled: pan.enabled, points: pan.points,
                        sustainPointIndex: pan.sustainPointIndex, loopStartPointIndex: pan.loopStartPointIndex,
                        loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags, fadeout: 0)
                    state.panTick = Self.advance(state.panTick, envelope: clock, keyOn: state.keyOn, releasing: releasing)
                }
                if !state.keyOn && tick.advances {
                    state.fadeoutAccumulator = max(0, state.fadeoutAccumulator - max(0, instrument.volume.fadeout))
                }
                history.append(PlaybackXMEnvelopeUpdate(eventIndex: index, channelIndex: mapping.channelIndex,
                    source: tick.source, tick: tick.tick, scheduledFrame: frame, bpm: tick.bpm,
                    speed: tick.speed, state: state))
                first = false
            }
            updatesByEvent[index] = history
            updates.append(contentsOf: history)
        }
        updates.sort { $0.scheduledFrame == $1.scheduledFrame ? $0.eventIndex < $1.eventIndex : $0.scheduledFrame < $1.scheduledFrame }
    }

    /// Bounded offline tails use the timing plan's existing final-tempo extrapolation.
    /// Tail coordinates retain the last source row; no additional song rows or Fxx commands are invented.
    mutating func extend(throughFrame frame: Int, plan: PlaybackSongSyntheticPlan) {
        guard frame > endFrame else { return }
        endFrame = frame
        rebuild(plan: plan)
    }

    /// Returns state immediately before a window; the boundary tick remains scheduled.
    func state(eventIndex: Int, before frame: Int) -> MixerEnvelopeSemanticState? {
        guard let history = updatesByEvent[eventIndex] else { return nil }
        var low = 0
        var high = history.count
        while low < high {
            let middle = (low + high) / 2
            if history[middle].scheduledFrame < frame { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? history[low - 1].state : nil
    }

    private static func advance(_ position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool, releasing: Bool) -> Int {
        let held = envelope.sustainEnabled && position == envelope.sustainPoint?.tick
        // Release publishes the held sustain point once, then advances on the next tick.
        if held && (keyOn || releasing) { return position }
        let next = position + 1
        if envelope.loopEnabled, let start = envelope.loopStartPoint?.tick, let end = envelope.loopEndPoint?.tick,
           start <= end, next >= end, !(envelope.sustainEnabled && envelope.sustainPoint?.tick == end && !keyOn) {
            return start
        }
        return next
    }
}

extension PlaybackSongSyntheticPlan {
    func extendingEnvelopeTail(throughFrame frame: Int) -> PlaybackSongSyntheticPlan {
        var plan = self
        var timeline = xmEnvelopeTimeline
        timeline?.extend(throughFrame: frame, plan: self)
        plan.xmEnvelopeTimeline = timeline
        return plan
    }
}
