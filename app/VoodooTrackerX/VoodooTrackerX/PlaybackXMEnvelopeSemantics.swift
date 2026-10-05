import Foundation

/// One immutable, value-captured snapshot shared by row grouping and history views.
/// Channel controls survive source absence; no cursor or PCM is stored here.
final class PlaybackXMChannelRow: Equatable, Sendable {
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let scheduledFrame: Int
    let controls: PlaybackSongSyntheticAdapter.ChannelState
    let instrumentOnlyReset: MixerPlaybackStateChange?

    init(source: PlaybackPosition, channelIndex: Int, syntheticRow: Int, scheduledFrame: Int,
         controls: PlaybackSongSyntheticAdapter.ChannelState, instrumentOnlyReset: MixerPlaybackStateChange?) {
        self.source = source
        self.channelIndex = channelIndex
        self.syntheticRow = syntheticRow
        self.scheduledFrame = scheduledFrame
        self.controls = controls
        self.instrumentOnlyReset = instrumentOnlyReset
    }

    static func == (lhs: PlaybackXMChannelRow, rhs: PlaybackXMChannelRow) -> Bool {
        lhs === rhs || (lhs.source == rhs.source && lhs.channelIndex == rhs.channelIndex &&
            lhs.syntheticRow == rhs.syntheticRow && lhs.scheduledFrame == rhs.scheduledFrame &&
            lhs.controls == rhs.controls && lhs.instrumentOnlyReset == rhs.instrumentOnlyReset)
    }
}

/// Projects only the per-tick carried identity; complete controls remain in the snapshots.
struct PlaybackXMCarriedInstrumentProjection {
    struct Work: Equatable {
        let snapshotCount: Int
        let projectedValueCount: Int
        let fullControlsValueCopyCount = 0
        let snapshotReferenceStride = MemoryLayout<PlaybackXMChannelRow>.stride
        let projectedValueStride = MemoryLayout<Int?>.stride
    }

    let byRow: [Int: Int?]
    let lastCarriedInstrument: Int?
    let work: Work

    init(rows: [PlaybackXMChannelRow]) {
        // A present nil carry differs from a missing row: keep the outer optional
        // of dictionary lookup so only missing rows use final-row tail controls.
        byRow = Dictionary(uniqueKeysWithValues: rows.map { ($0.syntheticRow, $0.controls.carriedInstrumentIndex) })
        lastCarriedInstrument = rows.last?.controls.carriedInstrumentIndex
        work = Work(snapshotCount: rows.count, projectedValueCount: byRow.count)
    }
}

/// Deterministic work counts for one immutable history-index construction and its queries.
struct PlaybackXMHistoryLookupDiagnostics: Equatable {
    var indexBuildCount = 0
    var entriesIndexed = 0
    var resetEntriesIndexed = 0
    var lookupCount = 0
    var entriesVisited = 0
    var fallbackFullScanCount = 0
    var estimatedIndexBytes = 0
}

/// A channel-local read-only view; ordinals preserve source writer order at equal frames.
struct PlaybackXMChannelHistoryIndex {
    private let rows: [PlaybackXMChannelRow]
    private let ordered: [Int]
    private let resets: [Int]
    private let lastSourceOrdinal: [Int]
    let chronological: Bool

    var resetEntryCount: Int { resets.count }
    var estimatedIndexBytes: Int {
        (ordered.count + resets.count + lastSourceOrdinal.count) * MemoryLayout<Int>.stride
    }

    init(rows: [PlaybackXMChannelRow]) {
        self.rows = rows
        chronological = zip(rows, rows.dropFirst()).allSatisfy { $0.scheduledFrame <= $1.scheduledFrame }
        var ordered = Array(rows.indices)
        if !chronological {
            ordered.sort { rows[$0].scheduledFrame == rows[$1].scheduledFrame ? $0 < $1 :
                rows[$0].scheduledFrame < rows[$1].scheduledFrame }
        }
        self.ordered = ordered
        resets = ordered.filter { rows[$0].controls.activeEventIndex == nil && rows[$0].instrumentOnlyReset != nil }
        var latest = -1
        lastSourceOrdinal = chronological ? [] : ordered.map { latest = max(latest, $0); return latest }
    }

    /// Returns the same last collection-order match as `last(where:)`, inclusive of the frame.
    func controls(atOrBefore frame: Int, work: inout PlaybackXMHistoryLookupDiagnostics) -> PlaybackSongSyntheticAdapter.ChannelState? {
        work.lookupCount += 1
        let end = bound(frame, in: ordered, inclusive: true, work: &work)
        guard end > 0 else { return nil }
        work.entriesVisited += 1
        return rows[chronological ? ordered[end - 1] : lastSourceOrdinal[end - 1]].controls
    }

    /// Restricts silent resets to the half-open route lifetime, retaining original writer order.
    func silentResets(start: Int, stop: Int, work: inout PlaybackXMHistoryLookupDiagnostics) -> [PlaybackXMChannelRow] {
        work.lookupCount += 1
        let lower = bound(start, in: resets, inclusive: false, work: &work)
        let upper = bound(stop, in: resets, inclusive: false, work: &work)
        guard lower < upper else { return [] }
        let matches = chronological ? Array(resets[lower..<upper]) : resets[lower..<upper].sorted()
        work.entriesVisited += matches.count
        return matches.map { rows[$0] }
    }

    private func bound(_ frame: Int, in indices: [Int], inclusive: Bool,
                       work: inout PlaybackXMHistoryLookupDiagnostics) -> Int {
        var lower = 0, upper = indices.count
        while lower < upper {
            let middle = (lower + upper) / 2
            work.entriesVisited += 1
            let candidate = rows[indices[middle]].scheduledFrame
            if candidate < frame || (inclusive && candidate == frame) { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }
}

/// An exact mapped route with no represented audio source. Undeclared headers add no defaults.
struct PlaybackXMEmptyRoute: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let scheduledFrame: Int
    let instrumentIndex: Int
    let sampleIndex: Int
    let stoppedEventIndex: Int?
    var preservesChannelState = false
    var tick = 0
}

/// One channel's canonical tick state. A nil source generation requires no mixer voice.
struct PlaybackXMChannelUpdate: Equatable {
    let channelIndex: Int
    let instrumentIndex: Int
    let sampleIndex: Int
    let sourceEventIndex: Int?
    let source: PlaybackPosition
    let tick: Int
    let scheduledFrame: Int
    let bpm: Int
    let speed: Int
    let state: MixerEnvelopeSemanticState
    var carriedInstrumentIndex: Int? = nil
    var cachedDefaultVolume: Int? = nil
    var cachedDefaultPan: UInt8? = nil
    var selectionFrame = 0
}

extension PlaybackSongSyntheticAdapter {
    /// Retires source identity while keeping the channel's period and instrument controls.
    static func clearSourceAssociation(_ state: inout ChannelState) {
        state.activeEventIndex = nil
        state.activeEventMappingIndex = nil
        state.activeInstrumentIndex = nil
        state.activeSampleIndex = nil
        state.activeSampleVolume = nil
    }

    /// Selects immutable header state without resolving or fabricating a PlaybackSample.
    static func selectEmptyHeader(_ header: XMSourceSampleSlotProvenance, cell: PlaybackCell,
        instrumentIndex: Int, initializesDefaults: Bool = true,
        song: PlaybackSong, timingConfig: SyntheticTrackerTimingConfig, state: inout ChannelState) -> PlaybackStepMapping {
        clearSourceAssociation(&state)
        state.semanticInstrumentIndex = instrumentIndex
        state.semanticSampleIndex = header.sampleIndex
        state.triggeredSampleDefaultVolume = clampedVolumeValue(Int(header.volume))
        state.triggeredSampleDefaultPan = header.panning
        if initializesDefaults {
            state.baseChannelVolume = state.triggeredSampleDefaultVolume
            state.initializePanning(fromSampleHeader: header.panning)
        }
        state.volumeValueZeroedByAxy = false
        let instrument = song.instrumentsByIndex[instrumentIndex]!
        state.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
        applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope, timingConfig: timingConfig), to: &state)
        let finetune = cell.effectType == 0x0E && cell.effectParam >> 4 == 5 && song.usesLinearFrequencyTable
            ? setFinetuneValue(from: cell) : header.finetune
        // These are period-domain controls, not a source cursor or a mixer step event.
        state.activeSampleBaseSampleRate = PlaybackSample.xmNeutralSampleRate
        state.activeSampleRelativeNote = header.relativeNote
        state.activeSampleFinetune = finetune
        state.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
        let pitch = playbackStepMapping(note: cell.note, relativeNote: header.relativeNote, finetune: finetune,
            baseSampleRate: PlaybackSample.xmNeutralSampleRate, usesLinearFrequencyTable: song.usesLinearFrequencyTable,
            timingConfig: timingConfig)
        state.activeLinearPeriod = pitch.linearPeriod
        state.activeAmigaPeriod = pitch.amigaPeriod
        state.activePlaybackStep = pitch.playbackStep
        state.vibratoOutputLinearPeriod = nil
        state.vibratoOutputAmigaPeriod = nil
        return pitch
    }
}

/// A held semantic target. Source playback and audible ramps have separate ownership.
struct MixerEnvelopeSemanticState: Equatable {
    var volumeTick = 0
    var panTick = 0
    var keyOn = true
    var fadeoutAccumulator = 32_768
    var volumeValue: Float = 1
    var panValue: Float = 0.5

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
    var channelPanningValue: Double = 128
}

/// Derives all envelope/release targets from the already traversed Fxx timeline.
/// Neither renderer advances this state from elapsed samples or a cached BPM.
struct PlaybackXMEnvelopeTimeline: Equatable {
    struct Instrument: Equatable {
        let volume: PlaybackVolumeEnvelope
        let pan: PlaybackPanningEnvelope
    }

    /// A source restart carries the pending segment, not just a position on the new curve.
    private struct Segment: Equatable {
        var value: Float = 0
        var slope: Float = 0
        var pendingPoint = 0
        var followsCurve = false
        var positionedPastLoop = false

        /// Positions this segment; a jump past its loop runs through the tail until reset.
        mutating func position(_ requested: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool) -> Int {
            guard envelope.loopEnabled, let start = envelope.loopStartPoint?.tick,
                  let end = envelope.loopEndPoint?.tick, start <= end else {
                positionedPastLoop = false
                return requested
            }
            positionedPastLoop = requested > end
            let releasedSustainEnd = envelope.sustainEnabled && envelope.sustainPoint?.tick == end && !keyOn
            return requested == end && !releasedSustainEnd ? start : requested
        }

        mutating func nextPosition(_ position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool, releasing: Bool) -> Int {
            if !followsCurve {
                guard envelope.points.indices.contains(pendingPoint),
                      envelope.points[pendingPoint].tick == position + 1 else { return position + 1 }
                followsCurve = true
            }
            return PlaybackXMEnvelopeTimeline.advance(position, envelope: envelope, keyOn: keyOn,
                releasing: releasing, allowsLoop: !positionedPastLoop)
        }

        mutating func sample(_ position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool) {
            value = envelope.value(at: position)
            let points = envelope.points
            guard !points.isEmpty else { return }
            if keyOn && envelope.sustainEnabled, let index = envelope.sustainPointIndex,
               points.indices.contains(index), points[index].tick == position {
                pendingPoint = index
                slope = 0
            } else if let next = points.firstIndex(where: { $0.tick > position }), next > 0 {
                pendingPoint = next
                slope = Float(points[next].value - points[next - 1].value) /
                    Float(64 * max(1, points[next].tick - points[next - 1].tick))
            } else {
                pendingPoint = points.count - 1
                slope = 0
            }
            followsCurve = true
        }

        mutating func advance(from previous: Int, to position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool) {
            if followsCurve || (envelope.points.indices.contains(pendingPoint) &&
                envelope.points[pendingPoint].tick == position) {
                sample(position, envelope: envelope, keyOn: keyOn)
            } else if previous != position {
                value = min(1, max(0, value + slope))
            }
        }
    }

    private struct CarriedState {
        var semantic = MixerEnvelopeSemanticState()
        var volume = Segment()
        var pan = Segment()
        var fadeoutDecrement = 0
        var instrument: Instrument?
    }

    let timing: PlaybackSongFxxTimingPlan
    let instruments: [Int: Instrument]
    let instrumentsByIdentity: [Int: Instrument]
    private(set) var endFrame: Int
    private(set) var updates: [PlaybackXMEnvelopeUpdate] = []
    private(set) var updatesByEvent: [Int: [PlaybackXMEnvelopeUpdate]] = [:]
    private(set) var channelUpdates: [PlaybackXMChannelUpdate] = []
    private(set) var planningHistoryDiagnostics = PlaybackXMHistoryLookupDiagnostics()

    init(song: PlaybackSong, timing: PlaybackSongFxxTimingPlan, plan: PlaybackSongSyntheticPlan) {
        self.timing = timing
        endFrame = timing.frameFor(row: timing.rowTimings.count)
        instrumentsByIdentity = song.instrumentsByIndex.mapValues {
            Instrument(volume: $0.volumeEnvelope, pan: $0.panningEnvelope)
        }
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
        channelUpdates = []
        planningHistoryDiagnostics = PlaybackXMHistoryLookupDiagnostics()
        guard !plan.xmEmptyRoutes.isEmpty ||
                plan.pattern.events.contains(where: { $0.volumeEnvelope != nil || $0.panEnvelope != nil }) ||
                plan.diagnostics.keyOffEvents.contains(where: \.applied) || !plan.playbackStateEvents.isEmpty ||
                !plan.noteOnlyEventIndices.isEmpty else { return }
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
        struct Route {
            let eventIndex: Int?
            let channelIndex: Int
            let instrumentIndex: Int
            let sampleIndex: Int
            let frame: Int
            let preservesChannelState: Bool
        }
        var routes = mappings.map { mapping in
            Route(eventIndex: mapping.eventIndex, channelIndex: mapping.channelIndex,
                instrumentIndex: mapping.instrumentIndex, sampleIndex: mapping.sampleIndex,
                frame: scheduler.frame(for: plan.pattern.events[mapping.eventIndex]),
                preservesChannelState: plan.noteOnlyEventIndices.contains(mapping.eventIndex))
        }
        routes += plan.xmEmptyRoutes.map { Route(eventIndex: nil, channelIndex: $0.channelIndex,
            instrumentIndex: $0.instrumentIndex, sampleIndex: $0.sampleIndex, frame: $0.scheduledFrame,
            preservesChannelState: $0.preservesChannelState) }
        routes.sort { $0.frame == $1.frame ? ($0.eventIndex ?? -1) < ($1.eventIndex ?? -1) : $0.frame < $1.frame }
        let changes = PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan)
        let routesByChannel = Dictionary(grouping: routes, by: \.channelIndex)
        let rowsByChannel = Dictionary(grouping: plan.xmChannelRows, by: \.channelIndex)
        // Build the complete channel index set once, before any route queries.
        let rowHistories = rowsByChannel.mapValues { PlaybackXMChannelHistoryIndex(rows: $0) }
        planningHistoryDiagnostics.indexBuildCount = 1
        planningHistoryDiagnostics.entriesIndexed = plan.xmChannelRows.count
        planningHistoryDiagnostics.resetEntriesIndexed = rowHistories.values.reduce(0) { $0 + $1.resetEntryCount }
        planningHistoryDiagnostics.estimatedIndexBytes = rowHistories.values.reduce(0) { $0 + $1.estimatedIndexBytes }
        let changesByEvent = Dictionary(grouping: changes, by: \.activeEventIndex)
        let releasesByChannel = Dictionary(grouping: plan.diagnostics.keyOffEvents.filter(\.applied), by: \.channelIndex)
        let positionsByChannel = Dictionary(grouping: plan.diagnostics.envelopePositionEffects, by: \.channelIndex)
        let cutsByChannel = Dictionary(grouping: plan.diagnostics.noteCutEffects.filter(\.applied), by: \.channelIndex)
        let panSlidesByChannel = Dictionary(grouping: plan.diagnostics.voiceStateUpdates.filter {
            $0.applied && (0xD0...0xEF).contains($0.rawVolumeColumn ?? 0)
        }, by: \.channelIndex)
        struct Change {
            let scheduledFrame: Int
            let change: MixerPlaybackStateChange
        }
        for (channel, channelRoutes) in routesByChannel {
            var previous = CarriedState()
            var hasPrevious = false
            let channelRows = rowsByChannel[channel] ?? []
            let carriedInstruments = PlaybackXMCarriedInstrumentProjection(rows: channelRows)
            let channelPans = Dictionary(uniqueKeysWithValues: channelRows.map { ($0.syntheticRow, $0.controls.panningValue) })
            let panSlides = (panSlidesByChannel[channel] ?? []).reduce(into: [Int: Double]()) {
                if let value = $1.channelPanningValueAfter { $0[$1.scheduledFrame] = value }
            }
            for (routeIndex, route) in channelRoutes.enumerated() {
                guard let instrument = route.eventIndex.flatMap({ instruments[$0] }) ?? instrumentsByIdentity[route.instrumentIndex] else { continue }
                let index = route.eventIndex
                let start = route.frame
                let stop = routeIndex + 1 < channelRoutes.count ? channelRoutes[routeIndex + 1].frame : Int.max
                let cuts = (cutsByChannel[channel] ?? []).filter {
                    $0.activeEventIndex == index }.compactMap(\.scheduledFrame).filter { $0 >= start }
                let sourceEnd = cuts.min() ?? Int.max
                let releases = Set((releasesByChannel[channel] ?? []).filter {
                    ($0.activeEventIndex == index || $0.activeEventIndex == nil) &&
                        $0.scheduledFrame.map { $0 >= start && $0 < stop } == true
                }.compactMap(\.scheduledFrame))
                let positions = (positionsByChannel[channel] ?? []).filter {
                    ($0.activeEventIndex == index || $0.activeEventIndex == nil) &&
                        $0.scheduledFrame >= start && $0.scheduledFrame < stop
                }
                var resets = (index.flatMap { changesByEvent[$0] } ?? []).map {
                    Change(scheduledFrame: $0.scheduledFrame, change: $0.change)
                }
                // The existing instrument-only dispatch owns default restoration. Its silent
                // reset belongs to this channel clock, never to a fabricated source event.
                resets += (rowHistories[channel]?.silentResets(start: start, stop: stop,
                    work: &planningHistoryDiagnostics) ?? []).map { row in
                    Change(scheduledFrame: row.scheduledFrame, change: row.instrumentOnlyReset!)
                }
                let volumeEnabled = index.map { plan.pattern.events[$0].volumeEnvelope != nil }
                    ?? (instrument.volume.enabled && !instrument.volume.points.isEmpty)
                let panEnabled = index.map { plan.pattern.events[$0].panEnvelope != nil }
                    ?? (instrument.pan.enabled && !instrument.pan.points.isEmpty)
                let publishesToVoice = volumeEnabled || panEnabled || releases.contains { $0 < sourceEnd } ||
                    resets.contains { $0.scheduledFrame < sourceEnd } || !plan.noteOnlyEventIndices.isEmpty
                guard publishesToVoice || plan.xmEmptyRoutes.contains(where: { $0.channelIndex == channel }) else { continue }
                let routeControls = rowHistories[channel]?.controls(atOrBefore: start, work: &planningHistoryDiagnostics)
                var channelPanning = routeControls?.panningValue ?? 128
                let carries = route.preservesChannelState
                var carried = carries ? previous : CarriedState()
                if carries && !hasPrevious && (index.map { plan.coldReleasedEventIndices.contains($0) }
                    ?? (routeControls?.keyOffWithoutVoice == true)) {
                    carried.semantic.keyOn = false
                    carried.semantic.panTick = -1
                }
                if carries {
                    if carried.instrument?.volume != instrument.volume { carried.volume.followsCurve = false }
                    if carried.instrument?.pan != instrument.pan { carried.pan.followsCurve = false }
                } else {
                    carried.fadeoutDecrement = instrument.volume.fadeout
                }
                carried.instrument = instrument
                var state = carried.semantic
                let pan = instrument.pan
                let panClock = PlaybackVolumeEnvelope(enabled: pan.enabled, points: pan.points,
                    sustainPointIndex: pan.sustainPointIndex, loopStartPointIndex: pan.loopStartPointIndex,
                    loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags, fadeout: 0)
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
                    // Tick-zero writers keep their row authority; slides supply the exact
                    // stored pan for later publications, carrying the final value into tails.
                    if tick.tick == 0, let value = channelPans[tick.row] { channelPanning = value }
                    if let value = panSlides[frame] { channelPanning = value }
                    var resetVolume = first && !carries
                    var resetPan = first && !carries
                    let wasKeyOn = state.keyOn
                    for reset in resets where reset.scheduledFrame == frame {
                        switch reset.change {
                        case let .reset(dimensions):
                            if dimensions.volumeEnvelope { state.volumeTick = 0; resetVolume = true }
                            if dimensions.panEnvelope { state.panTick = 0; resetPan = true }
                            if dimensions.keyOn { state.keyOn = true }
                            if dimensions.fadeout {
                                state.fadeoutAccumulator = 32_768
                                carried.fadeoutDecrement = instrument.volume.fadeout
                            }
                        case .keyOff:
                            // XM uses the instrument's tick fadeout; per-frame rates belong to generic synthetic voices.
                            state.keyOn = false
                        }
                    }
                    if releases.contains(frame) { state.keyOn = false }
                    let releasing = wasKeyOn && !state.keyOn
                    let position = positions.last { $0.scheduledFrame == frame }
                    if volumeEnabled {
                        let previous = state.volumeTick
                        if let position, position.applied {
                            state.volumeTick = Int(position.effectParam)
                            resetVolume = true
                        } else if !resetVolume && tick.advances {
                            if carries && releasing && instrument.volume.points.indices.contains(carried.volume.pendingPoint),
                               state.volumeTick >= instrument.volume.points[carried.volume.pendingPoint].tick {
                                state.volumeTick = instrument.volume.points[carried.volume.pendingPoint].tick - 1
                            }
                            state.volumeTick = carried.volume.nextPosition(state.volumeTick, envelope: instrument.volume,
                                keyOn: state.keyOn, releasing: releasing)
                        }
                        if resetVolume {
                            carried.volume.sample(state.volumeTick, envelope: instrument.volume, keyOn: state.keyOn)
                        } else {
                            carried.volume.advance(from: previous, to: state.volumeTick, envelope: instrument.volume, keyOn: state.keyOn)
                        }
                        state.volumeValue = carried.volume.value
                    } else {
                        state.volumeValue = 1
                    }
                    if panEnabled {
                        let previous = state.panTick
                        if resetPan { carried.pan.positionedPastLoop = false }
                        // The raw volume sustain bit gates pan Lxx, including disabled volume envelopes.
                        if let position, instrument.volume.typeFlags & 0x02 != 0 {
                            state.panTick = carried.pan.position(Int(position.effectParam), envelope: panClock, keyOn: state.keyOn)
                            resetPan = true
                        } else if !resetPan && tick.advances {
                            state.panTick = carried.pan.nextPosition(state.panTick, envelope: panClock, keyOn: state.keyOn, releasing: releasing)
                        }
                        if resetPan { carried.pan.sample(state.panTick, envelope: panClock, keyOn: state.keyOn) }
                        else { carried.pan.advance(from: previous, to: state.panTick, envelope: panClock, keyOn: state.keyOn) }
                    }
                    state.panValue = panEnabled ? carried.pan.value : 0.5
                    if !state.keyOn && tick.advances {
                        state.fadeoutAccumulator = max(0, state.fadeoutAccumulator - max(0, carried.fadeoutDecrement))
                    }
                    let sourceIndex = frame < sourceEnd ? index : nil
                    channelUpdates.append(.init(channelIndex: channel, instrumentIndex: route.instrumentIndex,
                        sampleIndex: route.sampleIndex, sourceEventIndex: sourceIndex, source: tick.source,
                        tick: tick.tick, scheduledFrame: frame, bpm: tick.bpm, speed: tick.speed, state: state,
                        carriedInstrumentIndex: carriedInstruments.byRow[tick.row] ?? carriedInstruments.lastCarriedInstrument,
                        cachedDefaultVolume: routeControls?.triggeredSampleDefaultVolume,
                        cachedDefaultPan: routeControls?.triggeredSampleDefaultPan, selectionFrame: start))
                    if let index = sourceIndex, publishesToVoice {
                        history.append(PlaybackXMEnvelopeUpdate(eventIndex: index, channelIndex: channel,
                            source: tick.source, tick: tick.tick, scheduledFrame: frame, bpm: tick.bpm,
                            speed: tick.speed, state: state,
                            channelPanningValue: channelPanning))
                    }
                    first = false
                }
                carried.semantic = state
                previous = carried
                hasPrevious = true
                if let index, !history.isEmpty { updatesByEvent[index] = history }
                updates.append(contentsOf: history)
            }
        }
        channelUpdates.sort { $0.scheduledFrame == $1.scheduledFrame ? $0.channelIndex < $1.channelIndex : $0.scheduledFrame < $1.scheduledFrame }
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

    /// Includes the boundary tick. Silent state is available without consulting any C voice.
    func channelState(channelIndex: Int, atOrBefore frame: Int) -> PlaybackXMChannelUpdate? {
        channelUpdates.last { $0.channelIndex == channelIndex && $0.scheduledFrame <= frame }
    }

    private static func advance(_ position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool,
                                releasing: Bool, allowsLoop: Bool) -> Int {
        let held = envelope.sustainEnabled && position == envelope.sustainPoint?.tick
        // Release publishes the held sustain point once, then advances on the next tick.
        if held && (keyOn || releasing) { return position }
        let next = position + 1
        if allowsLoop, envelope.loopEnabled, let start = envelope.loopStartPoint?.tick, let end = envelope.loopEndPoint?.tick,
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
