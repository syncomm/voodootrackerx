import Foundation

/// Full inspection captures or ordinal-stable runtime owners, never an empty stand-in.
@propertyWrapper
struct PlaybackXMRowCaptureStorage: Equatable {
    enum Retention { case full, runtimeFinalized }
    struct Owner: Equatable {
        let semanticInstrument: Int?, semanticSample: Int?, carriedInstrument: Int?
        init(_ row: PlaybackXMChannelRow) {
            semanticInstrument = row.controls.semanticInstrumentIndex
            semanticSample = row.controls.semanticSampleIndex
            carriedInstrument = row.controls.carriedInstrumentIndex
        }
    }
    private enum Storage: Equatable { case full([PlaybackXMChannelRow]), runtimeFinalized([Owner]) }
    private var storage: Storage

    init(wrappedValue: [PlaybackXMChannelRow]) { storage = .full(wrappedValue) }
    var projectedValue: Self { get { self } set { self = newValue } }
    var isFullCapture: Bool { if case .full = storage { return true }; return false }
    var count: Int {
        switch storage { case let .full(rows): return rows.count; case let .runtimeFinalized(owners): return owners.count }
    }
    var runtimeOwnerCapacity: Int { if case let .runtimeFinalized(owners) = storage { return owners.capacity }; return 0 }
    var wrappedValue: [PlaybackXMChannelRow] {
        get {
            guard case let .full(rows) = storage else { preconditionFailure("Runtime-finalized rows have no full captures") }
            return rows
        }
        set {
            precondition(isFullCapture, "Cannot mutate runtime-finalized row captures")
            storage = .full(newValue)
        }
    }
    func owner(at ordinal: Int) -> Owner? {
        switch storage {
        case let .full(rows): return rows.indices.contains(ordinal) ? Owner(rows[ordinal]) : nil
        case let .runtimeFinalized(owners): return owners.indices.contains(ordinal) ? owners[ordinal] : nil
        }
    }
    /// Called off the render callback after semantic construction, before event assembly.
    mutating func finalizeForRuntime() {
        guard case let .full(rows) = storage else { return }
        storage = .runtimeFinalized(rows.map(Owner.init))
    }
}

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
        row(atOrBefore: frame, work: &work)?.controls
    }

    /// Includes the row-owned reset decision without building another history index.
    func row(atOrBefore frame: Int, work: inout PlaybackXMHistoryLookupDiagnostics) -> PlaybackXMChannelRow? {
        work.lookupCount += 1
        let end = bound(frame, in: ordered, inclusive: true, work: &work)
        guard end > 0 else { return nil }
        work.entriesVisited += 1
        return rows[chronological ? ordered[end - 1] : lastSourceOrdinal[end - 1]]
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

/// A source-less route; absent maps retain nil sample identity and invent no defaults.
struct PlaybackXMEmptyRoute: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let scheduledFrame: Int
    let instrumentIndex: Int
    let sampleIndex: Int?
    let stoppedEventIndex: Int?
    var preservesChannelState = false
    var tick = 0
    // A refused offset replaces the main source without admitting new PCM.
    var retiresSource = false
}

/// Channel control ownership can change while its sounding PCM generation is retained.
/// Only source-less resets need the returned reset decision here; live-source resets
/// already use PlaybackVoiceStateEvent and the existing envelope fold.
struct PlaybackXMInstrumentSelection: Equatable {
    let channelIndex: Int
    let scheduledFrame: Int
    let instrumentIndex: Int
    let sampleIndex: Int
    let reset: MixerPlaybackStateChange?
    let channelPanningValue: Double?
}

/// One channel's canonical tick state. A nil source generation requires no mixer voice.
struct PlaybackXMChannelUpdate: Equatable {
    let channelIndex: Int
    let instrumentIndex: Int
    // XM map entries are bytes. Preserve absence without widening every runtime event.
    let sampleIndex: UInt8?
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
        let finetune = cell.effectType == 0x0E && cell.effectParam >> 4 == 5
            ? setFinetuneValue(from: cell) : header.finetune
        // These are period-domain controls, not a source cursor or a mixer step event.
        state.activeSampleBaseSampleRate = PlaybackSample.xmNeutralSampleRate
        state.activeSampleRelativeNote = header.relativeNote
        state.activeSampleFinetune = finetune
        state.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
        let pitch = ordinaryPitchAdmission(note: cell.note, relativeNote: header.relativeNote) == .retained
            ? retainedPitchMapping(baseSampleRate: PlaybackSample.xmNeutralSampleRate, state: state,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable, timingConfig: timingConfig, finetune: finetune)
            : playbackStepMapping(note: cell.note, relativeNote: header.relativeNote, finetune: finetune,
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
    struct Segment: Equatable {
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

        mutating func sample(_ position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool, volumeQ8: Bool = false) {
            value = volumeQ8 ? envelope.value(at: position) : PlaybackPanningEnvelopeQ8.value(at: position, envelope: envelope)
            let points = envelope.points
            guard !points.isEmpty else { return }
            if keyOn && envelope.sustainEnabled, let index = envelope.sustainPointIndex,
               points.indices.contains(index), points[index].tick == position {
                pendingPoint = index
                slope = 0
            } else if let next = points.firstIndex(where: { $0.tick > position }), next > 0 {
                pendingPoint = next
                slope = volumeQ8 ? PlaybackVolumeEnvelopeQ8.factor(PlaybackVolumeEnvelopeQ8.slope(
                    from: points[next - 1], to: points[next])) : PlaybackPanningEnvelopeQ8.slope(
                    from: points[next - 1], to: points[next])
            } else {
                pendingPoint = points.count - 1
                slope = 0
            }
            followsCurve = true
        }

        mutating func advance(from previous: Int, to position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool, volumeQ8: Bool = false) {
            if followsCurve || (envelope.points.indices.contains(pendingPoint) &&
                envelope.points[pendingPoint].tick == position) {
                sample(position, envelope: envelope, keyOn: keyOn, volumeQ8: volumeQ8)
            } else if previous != position {
                // Q8 factors/slopes are binary-exact in these existing Float slots;
                // carrying their bounded sum needs no wider state or second clock.
                value = min(1, max(0, value + slope))
            }
        }
    }

    struct CarriedState: Equatable {
        var semantic = MixerEnvelopeSemanticState()
        var volume = Segment()
        var pan = Segment()
        var fadeoutDecrement = 0
        var instrument: Instrument?
    }

    /// Value-only row-boundary state; the caller remaps scratch source indices on import.
    struct ChannelCheckpoint: Equatable {
        var carried: CarriedState
        var hasPrevious: Bool
        var hasVolumeHistory: Bool
        var route: RouteCheckpoint?
    }

    struct RouteCheckpoint: Equatable {
        var sourceEventIndex: Int?
        var semanticInstrumentIndex: Int
        var semanticSampleIndex: Int?
        var volumeEnabled: Bool
        var panEnabled: Bool
        var publishesToVoice: Bool
        var preservesChannelState = false
        var channelPanning: Double
        var selectionFrame: Int
        var cachedDefaultVolume: Int?
        var cachedDefaultPan: UInt8?
        var first: Bool
    }

    let timing: PlaybackSongFxxTimingPlan
    let instruments: [Int: Instrument]
    let instrumentsByIdentity: [Int: Instrument]
    private(set) var endFrame: Int
    private(set) var updates: [PlaybackXMEnvelopeUpdate] = []
    private(set) var updatesByEvent: [Int: [PlaybackXMEnvelopeUpdate]] = [:]
    private(set) var channelUpdates: [PlaybackXMChannelUpdate] = []
    private(set) var planningHistoryDiagnostics = PlaybackXMHistoryLookupDiagnostics()

    init(song: PlaybackSong, timing: PlaybackSongFxxTimingPlan, plan: PlaybackSongSyntheticPlan,
         isCancelled: (() -> Bool)? = nil,
         continuationSeed: [Int: ChannelCheckpoint]? = nil,
         importedEventIndices: Set<Int> = [], batchStartFrame: Int = 0,
         terminalCheckpoint: (([Int: ChannelCheckpoint]) -> Void)? = nil) {
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
        rebuild(plan: plan, isCancelled: isCancelled, continuationSeed: continuationSeed,
            importedEventIndices: importedEventIndices, batchStartFrame: batchStartFrame,
            terminalCheckpoint: terminalCheckpoint)
    }

    /// Re-fold explicit reset history while retaining the canonical tick frames.
    mutating func rebuild(plan: PlaybackSongSyntheticPlan, isCancelled: (() -> Bool)? = nil,
        continuationSeed: [Int: ChannelCheckpoint]? = nil,
        importedEventIndices: Set<Int> = [], batchStartFrame: Int = 0,
        terminalCheckpoint: (([Int: ChannelCheckpoint]) -> Void)? = nil) {
        precondition(plan.$xmChannelRows.isFullCapture, "Envelope rebuild requires full row captures")
        updates = []
        updatesByEvent = [:]
        channelUpdates = []
        planningHistoryDiagnostics = PlaybackXMHistoryLookupDiagnostics()
        guard !plan.xmEmptyRoutes.isEmpty || !plan.xmInstrumentSelections.isEmpty ||
                plan.pattern.events.contains(where: { $0.volumeEnvelope != nil || $0.panEnvelope != nil }) ||
                plan.diagnostics.keyOffEvents.contains(where: \.applied) || !plan.playbackStateEvents.isEmpty ||
                !plan.noteOnlyEventIndices.isEmpty || plan.diagnostics.noteCutEffects.contains(where: \.applied) ||
                continuationSeed?.isEmpty == false || terminalCheckpoint != nil else {
            terminalCheckpoint?(continuationSeed ?? [:])
            return
        }
        // The optional output is not retained in this timeline or its reflected value.
        var checkpoints: [Int: ChannelCheckpoint]? = terminalCheckpoint == nil ? nil : (continuationSeed ?? [:])
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
            for tick in 0..<config.actualTickCount {
                ticks.append(Tick(row: rowIndex, source: source, tick: tick,
                    frame: timing.frameFor(row: rowIndex, tick: tick), bpm: config.bpm, speed: config.speed))
            }
            rowIndex += 1
        }
        let tickFrames = Set(ticks.map(\.frame))
        let canonicalOrder = zip(ticks, ticks.dropFirst()).allSatisfy {
            if $0.frame != $1.frame { return $0.frame < $1.frame }
            return $0.row == $1.row ? $0.tick <= $1.tick : $0.row < $1.row
        }
        struct Route {
            let eventIndex: Int?
            let channelIndex: Int
            let instrumentIndex: Int
            let sampleIndex: Int?
            let frame: Int
            let preservesChannelState: Bool
            var isRxy = false
            var resumesCheckpoint = false
        }
        var routes = mappings.compactMap { mapping -> Route? in
            let imported = importedEventIndices.contains(mapping.eventIndex)
            // Imported retiring-source records are lookup state, not channel routes.
            if imported && continuationSeed?[mapping.channelIndex]?.route?.sourceEventIndex != mapping.eventIndex {
                return nil
            }
            return Route(eventIndex: mapping.eventIndex, channelIndex: mapping.channelIndex,
                instrumentIndex: mapping.instrumentIndex, sampleIndex: mapping.sampleIndex,
                frame: scheduler.frame(for: plan.pattern.events[mapping.eventIndex]),
                preservesChannelState: plan.noteOnlyEventIndices.contains(mapping.eventIndex),
                isRxy: mapping.effectType == 27, resumesCheckpoint: imported)
        }
        routes += plan.xmEmptyRoutes.map { Route(eventIndex: nil, channelIndex: $0.channelIndex,
            instrumentIndex: $0.instrumentIndex, sampleIndex: $0.sampleIndex, frame: $0.scheduledFrame,
            preservesChannelState: $0.preservesChannelState) }
        let selectionsByChannel = Dictionary(grouping: plan.xmInstrumentSelections, by: \.channelIndex)
        routes.sort { $0.frame == $1.frame ? ($0.eventIndex ?? -1) < ($1.eventIndex ?? -1) : $0.frame < $1.frame }
        let changes = PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan)
        var routesByChannel = Dictionary(grouping: routes, by: \.channelIndex)
        for (channel, selections) in selectionsByChannel {
            if let first = selections.min(by: { $0.scheduledFrame < $1.scheduledFrame }),
               first.scheduledFrame < (routesByChannel[channel]?.first?.frame ?? Int.max) {
                // Reuse the existing route grouping; no additional song-wide pass.
                routesByChannel[channel, default: []].insert(Route(eventIndex: nil, channelIndex: channel,
                    instrumentIndex: first.instrumentIndex, sampleIndex: first.sampleIndex,
                    frame: first.scheduledFrame, preservesChannelState: true), at: 0)
            }
        }
        // A source-less channel still has an executed envelope owner/clock. Add one
        // lookup-only route; an actual boundary selection remains a separate route.
        for (channel, seed) in continuationSeed ?? [:] {
            if let route = seed.route, route.sourceEventIndex == nil {
                routesByChannel[channel, default: []].insert(Route(eventIndex: nil,
                    channelIndex: channel, instrumentIndex: route.semanticInstrumentIndex,
                    sampleIndex: route.semanticSampleIndex, frame: batchStartFrame,
                    preservesChannelState: true, resumesCheckpoint: true), at: 0)
            }
        }
        let rowsByChannel = Dictionary(grouping: plan.xmChannelRows, by: \.channelIndex)
        let instrumentDelays = Dictionary(grouping: plan.diagnostics.noteDelayEffects.filter {
            ($0.rowEntryInstrumentSelected || $0.delayedPanningValue != nil) && $0.requestedTick > 0 && $0.applied
        }, by: \.channelIndex)
        // Build the complete channel index set once, before any route queries.
        let rowHistories = rowsByChannel.mapValues { PlaybackXMChannelHistoryIndex(rows: $0) }
        planningHistoryDiagnostics.indexBuildCount = 1
        planningHistoryDiagnostics.entriesIndexed = plan.xmChannelRows.count
        planningHistoryDiagnostics.resetEntriesIndexed = rowHistories.values.reduce(0) { $0 + $1.resetEntryCount }
        planningHistoryDiagnostics.estimatedIndexBytes = rowHistories.values.reduce(0) { $0 + $1.estimatedIndexBytes }
        let changesByEvent = Dictionary(grouping: changes, by: \.activeEventIndex)
        // Cold release history also owns inactive clock bookkeeping. It never
        // authorizes a source event, including after a subsequent cold tone reset.
        let releasesByChannel = Dictionary(grouping: plan.diagnostics.keyOffEvents.filter {
            $0.applied || $0.reason == .noActiveVoice
        }, by: \.channelIndex)
        let positionsByChannel = Dictionary(grouping: plan.diagnostics.envelopePositionEffects, by: \.channelIndex)
        let cutsBySource = Dictionary(grouping: plan.diagnostics.noteCutEffects.filter(\.applied), by: { $0.activeEventIndex ?? -1 })
        let panSlidesByChannel = Dictionary(grouping: plan.diagnostics.voiceStateUpdates.filter {
            $0.applied && $0.channelPanningValueAfter != nil
        }, by: \.channelIndex)
        struct Change {
            let scheduledFrame: Int
            let change: MixerPlaybackStateChange
        }
        for (channel, channelRoutes) in routesByChannel {
            let selections = Dictionary((selectionsByChannel[channel] ?? []).map { ($0.scheduledFrame, $0) },
                uniquingKeysWith: { _, last in last })
            let delayedSelections = Dictionary(uniqueKeysWithValues: (instrumentDelays[channel] ?? []).compactMap {
                delay in delay.delayedFrame.map { ($0, delay) }
            })
            let channelSeed = continuationSeed?[channel]
            var previous = channelSeed?.carried ?? CarriedState()
            var hasPrevious = channelSeed?.hasPrevious ?? false
            var hasVolumeHistory = channelSeed?.hasVolumeHistory ?? false
            let channelRows = rowsByChannel[channel] ?? []
            let carriedInstruments = PlaybackXMCarriedInstrumentProjection(rows: channelRows)
            let channelPans = Dictionary(uniqueKeysWithValues: channelRows.map { ($0.syntheticRow, $0.controls.panningValue) })
            let panSlides = (panSlidesByChannel[channel] ?? []).reduce(into: [Int: Double]()) {
                if let value = $1.channelPanningValueAfter { $0[$1.scheduledFrame] = value }
            }
            for (routeIndex, route) in channelRoutes.enumerated() {
                if isCancelled?() == true { return }
                guard var instrument = route.eventIndex.flatMap({ instruments[$0] }) ?? instrumentsByIdentity[route.instrumentIndex] else { continue }
                let restored = route.resumesCheckpoint ? channelSeed?.route : nil
                if route.resumesCheckpoint {
                    precondition(restored != nil, "Imported route requires its terminal checkpoint")
                    if let current = channelSeed?.carried.instrument { instrument = current }
                }
                var semanticInstrumentIndex = restored?.semanticInstrumentIndex ?? route.instrumentIndex
                var semanticSampleIndex = restored == nil ? route.sampleIndex : restored!.semanticSampleIndex
                let index = route.eventIndex
                let start = restored == nil ? route.frame : batchStartFrame
                let selectionFrame = restored?.selectionFrame ?? start
                let stop = routeIndex + 1 < channelRoutes.count ? channelRoutes[routeIndex + 1].frame : Int.max
                let hasAudibleCut = index.map { !(cutsBySource[$0] ?? []).isEmpty } ?? false
                let rxyParent = restored == nil && route.isRxy && route.preservesChannelState && routeIndex > 0
                    ? channelRoutes[routeIndex - 1].eventIndex : nil
                let releases = Set((releasesByChannel[channel] ?? []).filter {
                    ($0.activeEventIndex == index || $0.activeEventIndex == nil ||
                        (rxyParent != nil && $0.activeEventIndex == rxyParent && $0.scheduledFrame == start)) &&
                        $0.scheduledFrame.map { $0 >= start && $0 < stop } == true
                }.compactMap(\.scheduledFrame))
                let positions = (positionsByChannel[channel] ?? []).filter {
                    ($0.activeEventIndex == index || $0.activeEventIndex == nil) &&
                        $0.scheduledFrame >= start && $0.scheduledFrame < stop
                }
                var resets = (index.flatMap { changesByEvent[$0] } ?? []).map {
                    Change(scheduledFrame: $0.scheduledFrame, change: $0.change)
                }
                let routeRow = rowHistories[channel]?.row(atOrBefore: start, work: &planningHistoryDiagnostics)
                // A row-entry reset/release precedes R's sample restart at the same
                // frame. It belongs to the carried channel, although its source retires.
                let hasRxyBoundaryReset = restored == nil && route.isRxy && route.preservesChannelState && index != nil &&
                    routeRow?.scheduledFrame == start && routeRow?.instrumentOnlyReset != nil
                if hasRxyBoundaryReset {
                    resets.append(Change(scheduledFrame: start, change: routeRow!.instrumentOnlyReset!))
                }
                // The existing instrument-only dispatch owns default restoration. Its silent
                // reset belongs to this channel clock, never to a fabricated source event.
                resets += (rowHistories[channel]?.silentResets(start: start, stop: stop,
                    work: &planningHistoryDiagnostics) ?? []).map { row in
                    Change(scheduledFrame: row.scheduledFrame, change: row.instrumentOnlyReset!)
                }
                resets += selections.values.compactMap {
                    guard let reset = $0.reset, $0.scheduledFrame >= start, $0.scheduledFrame < stop else { return nil }
                    return Change(scheduledFrame: $0.scheduledFrame, change: reset)
                }
                var volumeEnabled = restored?.volumeEnabled ?? index.map { plan.pattern.events[$0].volumeEnvelope != nil }
                    ?? (instrument.volume.enabled && !instrument.volume.points.isEmpty)
                var panEnabled = restored?.panEnabled ?? index.map { plan.pattern.events[$0].panEnvelope != nil }
                    ?? (instrument.pan.enabled && !instrument.pan.points.isEmpty)
                let publishesToVoice = restored?.publishesToVoice == true || volumeEnabled || panEnabled || !releases.isEmpty ||
                    !resets.isEmpty || hasAudibleCut || !plan.noteOnlyEventIndices.isEmpty
                guard publishesToVoice || restored != nil || terminalCheckpoint != nil || !selections.isEmpty || plan.xmEmptyRoutes.contains(where: { $0.channelIndex == channel }) else { continue }
                let routeControls = routeRow?.controls
                let delayedSelection = restored == nil ? delayedSelections[start] : nil
                let cachedDefaultVolume = restored == nil ? (delayedSelection?.cachedDefaultVolume ?? routeControls?.triggeredSampleDefaultVolume) : restored!.cachedDefaultVolume
                let cachedDefaultPan = restored == nil ? (delayedSelection?.cachedDefaultPan ?? routeControls?.triggeredSampleDefaultPan) : restored!.cachedDefaultPan
                var channelPanning = restored?.channelPanning ?? delayedSelection?.delayedPanningValue ?? routeControls?.panningValue ?? 128
                // Importing an existing route carries its storage, but does not turn an
                // ordinary birth into the distinct note-only/retrigger release policy.
                let preservesChannelState = restored?.preservesChannelState ?? route.preservesChannelState
                let carries = restored != nil || route.preservesChannelState
                var carried = carries ? previous : CarriedState()
                if carries && !hasPrevious {
                    let coldRelease = (releasesByChannel[channel] ?? []).last { ($0.scheduledFrame ?? Int.max) < start }
                    if coldRelease != nil || (index.map { plan.coldReleasedEventIndices.contains($0) }
                        ?? (routeControls?.keyOffWithoutVoice == true)) {
                        // Before any route there is no initialized curve/decrement. Fold the
                        // existing reset/release history; K00 must not fabricate unity fadeout.
                        let immediateReset = rowHistories[channel]?.silentResets(start: 0, stop: start,
                            work: &planningHistoryDiagnostics).last
                        let delayedReset = (instrumentDelays[channel] ?? []).last {
                            $0.status == .instrumentOnlyNoRetainedNote && ($0.delayedFrame ?? Int.max) < start
                        }?.delayedFrame ?? -1
                        let resetFrame = max(immediateReset?.scheduledFrame ?? -1, delayedReset)
                        carried.semantic.fadeoutAccumulator = resetFrame < 0 ? 0 : 32_768
                        carried.semantic.keyOn = resetFrame > (coldRelease?.scheduledFrame ?? -1)
                        carried.semantic.panTick = carried.semantic.keyOn ? 0 : -1
                        if let reset = immediateReset,
                           case let .reset(dimensions) = reset.instrumentOnlyReset,
                           !dimensions.panEnvelope {
                            // A cold tone reset restores key/fadeout, but the dummy
                            // instrument's disabled pan clock retains the release's -1.
                            carried.semantic.panTick = -1
                        }
                    }
                }
                if carries {
                    if carried.instrument?.volume != instrument.volume { carried.volume.followsCurve = false }
                    if carried.instrument?.pan != instrument.pan { carried.pan.followsCurve = false }
                } else {
                    carried.fadeoutDecrement = instrument.volume.fadeout
                }
                carried.instrument = instrument
                var state = carried.semantic
                var pan = instrument.pan
                var panClock = PlaybackVolumeEnvelope(enabled: pan.enabled, points: pan.points,
                    sustainPointIndex: pan.sustainPointIndex, loopStartPointIndex: pan.loopStartPointIndex,
                    loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags, fadeout: 0)
                var first = restored?.first ?? true
                var history = [PlaybackXMEnvelopeUpdate]()
                var low = 0
                var high = ticks.count
                while low < high {
                    let middle = (low + high) / 2
                    if ticks[middle].frame < start { low = middle + 1 } else { high = middle }
                }
                let missingFrames = Set(resets.map(\.scheduledFrame)).subtracting(tickFrames).filter {
                    $0 >= start && $0 < stop
                }
                var clock = ticks[low...].prefix { $0.frame < stop }
                if !canonicalOrder || !missingFrames.isEmpty {
                    // Off-tick resets and manually supplied clocks retain the exact
                    // legacy insertion/order path. Normal routes borrow immutable ticks.
                    var expanded = Array(clock)
                    for frame in missingFrames {
                        if let context = ticks.last(where: { $0.frame <= frame }) {
                            expanded.append(Tick(row: context.row, source: context.source, tick: context.tick,
                                frame: frame, bpm: context.bpm, speed: context.speed, advances: false))
                        }
                    }
                    expanded.sort {
                        if $0.frame != $1.frame { return $0.frame < $1.frame }
                        return $0.row == $1.row ? $0.tick < $1.tick : $0.row < $1.row
                    }
                    clock = expanded[...]
                }
                for (clockIndex, tick) in clock.enumerated() {
                    if clockIndex & 63 == 0, isCancelled?() == true { return }
                    let frame = tick.frame
                    guard frame >= start && frame < stop else { continue }
                    if let selection = selections[frame], let next = instrumentsByIdentity[selection.instrumentIndex] {
                        if instrument.volume != next.volume { carried.volume.followsCurve = false }
                        if instrument.pan != next.pan { carried.pan.followsCurve = false }
                        instrument = next
                        carried.instrument = next
                        semanticInstrumentIndex = selection.instrumentIndex
                        semanticSampleIndex = selection.sampleIndex
                        volumeEnabled = next.volume.enabled && !next.volume.points.isEmpty
                        panEnabled = next.pan.enabled && !next.pan.points.isEmpty
                        pan = next.pan
                        panClock = PlaybackVolumeEnvelope(enabled: pan.enabled, points: pan.points,
                            sustainPointIndex: pan.sustainPointIndex, loopStartPointIndex: pan.loopStartPointIndex,
                            loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags, fadeout: 0)
                    }
                    // Tick-zero writers keep their row authority; slides supply the exact
                    // stored pan for later publications, carrying the final value into tails.
                    if tick.tick == 0, let value = channelPans[tick.row] { channelPanning = value }
                    // A delayed source reset follows this tick's column slide.
                    if let value = panSlides[frame], !(first && delayedSelection != nil) { channelPanning = value }
                    if let value = selections[frame]?.channelPanningValue { channelPanning = value }
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
                                carried.fadeoutDecrement = first && hasRxyBoundaryReset
                                    ? previous.instrument?.volume.fadeout ?? instrument.volume.fadeout : instrument.volume.fadeout
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
                        if resetVolume { carried.volume.positionedPastLoop = false }
                        if let position, position.applied {
                            state.volumeTick = carried.volume.position(Int(position.effectParam),
                                envelope: instrument.volume, keyOn: state.keyOn)
                            resetVolume = true
                        } else if !resetVolume && tick.advances {
                            if preservesChannelState && releasing && instrument.volume.points.indices.contains(carried.volume.pendingPoint),
                               state.volumeTick >= instrument.volume.points[carried.volume.pendingPoint].tick {
                                state.volumeTick = instrument.volume.points[carried.volume.pendingPoint].tick - 1
                            }
                            state.volumeTick = carried.volume.nextPosition(state.volumeTick, envelope: instrument.volume,
                                keyOn: state.keyOn, releasing: releasing)
                        }
                        if resetVolume {
                            // Only the first enabled-volume reset retains the cold zero seed
                            // until point arrival. Pan/disabled-volume history is not volume
                            // history; warm resets and explicit positioning keep their policy.
                            let waitsForFirstPoint = !hasVolumeHistory && state.keyOn && position?.applied != true &&
                                (instrument.volume.points.first.map { state.volumeTick < $0.tick } ?? false)
                            if !waitsForFirstPoint {
                                carried.volume.sample(state.volumeTick, envelope: instrument.volume, keyOn: state.keyOn, volumeQ8: true)
                            }
                        } else {
                            carried.volume.advance(from: previous, to: state.volumeTick, envelope: instrument.volume, keyOn: state.keyOn, volumeQ8: true)
                        }
                        hasVolumeHistory = true
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
                    let sourceIndex = index
                    channelUpdates.append(.init(channelIndex: channel, instrumentIndex: semanticInstrumentIndex,
                        sampleIndex: semanticSampleIndex.flatMap(UInt8.init(exactly:)), sourceEventIndex: sourceIndex, source: tick.source,
                        tick: tick.tick, scheduledFrame: frame, bpm: tick.bpm, speed: tick.speed, state: state,
                        carriedInstrumentIndex: carriedInstruments.byRow[tick.row] ?? carriedInstruments.lastCarriedInstrument,
                        cachedDefaultVolume: cachedDefaultVolume,
                        cachedDefaultPan: cachedDefaultPan, selectionFrame: selectionFrame))
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
                if checkpoints != nil {
                    checkpoints![channel] = .init(carried: carried, hasPrevious: hasPrevious,
                        hasVolumeHistory: hasVolumeHistory, route: .init(sourceEventIndex: index,
                            semanticInstrumentIndex: semanticInstrumentIndex, semanticSampleIndex: semanticSampleIndex,
                            volumeEnabled: volumeEnabled, panEnabled: panEnabled,
                            publishesToVoice: publishesToVoice, preservesChannelState: preservesChannelState,
                            channelPanning: channelPanning,
                            selectionFrame: selectionFrame, cachedDefaultVolume: cachedDefaultVolume,
                            cachedDefaultPan: cachedDefaultPan, first: first))
                }
                if let index, !history.isEmpty { updatesByEvent[index] = history }
                updates.append(contentsOf: history)
            }
        }
        channelUpdates.sort { $0.scheduledFrame == $1.scheduledFrame ? $0.channelIndex < $1.channelIndex : $0.scheduledFrame < $1.scheduledFrame }
        updates.sort { $0.scheduledFrame == $1.scheduledFrame ? $0.eventIndex < $1.eventIndex : $0.scheduledFrame < $1.scheduledFrame }
        if let checkpoints { terminalCheckpoint?(checkpoints) }
    }

    /// Bounded offline tails use the timing plan's existing final-tempo extrapolation.
    /// Tail coordinates retain the last source row; no additional song rows or Fxx commands are invented.
    mutating func extend(throughFrame frame: Int, plan: PlaybackSongSyntheticPlan) {
        precondition(plan.$xmChannelRows.isFullCapture, "Envelope extension requires full row captures")
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
        precondition($xmChannelRows.isFullCapture, "Envelope tail extension requires full row captures")
        var plan = self
        var timeline = xmEnvelopeTimeline
        timeline?.extend(throughFrame: frame, plan: self)
        plan.xmEnvelopeTimeline = timeline
        return plan
    }
}
