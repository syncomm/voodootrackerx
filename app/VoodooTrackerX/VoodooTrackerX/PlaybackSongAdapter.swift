import Foundation

struct PlaybackSongSyntheticPlan: Equatable {
    let timingConfig: SyntheticTrackerTimingConfig
    let pattern: SyntheticPattern
    let diagnostics: PlaybackSongSyntheticDiagnostics
    var noteOnlyEventIndices: Set<Int> = []
    var coldReleasedEventIndices: Set<Int> = []
    var playbackStateEvents: [PlaybackVoiceStateEvent] = [] {
        didSet {
            var timeline = xmEnvelopeTimeline
            timeline?.rebuild(plan: self)
            xmEnvelopeTimeline = timeline
        }
    }
    var xmEnvelopeTimeline: PlaybackXMEnvelopeTimeline? = nil {
        didSet { xmAudibleTimeline = xmEnvelopeTimeline == nil ? nil : PlaybackXMAudibleTimeline(plan: self) }
    }
    var xmAudibleTimeline: PlaybackXMAudibleTimeline? = nil
    var xmChannelRows: [PlaybackXMChannelRow] = []
    var xmEmptyRoutes: [PlaybackXMEmptyRoute] = []
}

/// Targets the existing trigger event identity, never a reusable mixer slot.
struct PlaybackVoiceStateEvent: Equatable {
    let activeEventIndex: Int
    let channelIndex: Int
    let scheduledFrame: Int
    let change: MixerPlaybackStateChange
}

enum PlaybackSongSyntheticAdapter {
    static let maxMixerEnvelopePointCount = 12
    static let xmLinearPeriodBase = 7_680.0
    static let xmLinearC4Period = 4_608.0
    static let xmLinearPeriodUnitsPerSemitone = 64.0
    static let xmLinearPeriodUnitsPerOctave = 768.0
    // FT2 regular/tone slides and E1x/E2x use param << 2; X1x/X2x use param.
    static let xmLinearPortamentoUnitsPerParam = 4.0
    static let xmLinearMaximumRealNoteIndex = 118
    static let xmLinearMaximumEffectiveNoteValue = xmLinearMaximumRealNoteIndex + 1
    static let xmLinearMinimumSafePeriod = xmLinearPeriodBase
        - (Double(xmLinearMaximumRealNoteIndex) * xmLinearPeriodUnitsPerSemitone)
        - (127.0 / 2.0)
    static let xmLinearMaximumSafePeriod = xmLinearPeriodBase + 64.0
    static let xmAmigaC4Period = 6_848.0
    // Amiga state and its frequency numerator are both 4x the FT2 table domain.
    static let xmAmigaPortamentoUnitsPerParam = 4.0 * xmAmigaPeriodLookupScale
    static let xmAmigaMinimumSafePeriod = 107.0
    static let xmAmigaMaximumSafePeriod = 438_272.0

    struct ChannelState: Equatable {
        // Existing tracker-volume writers change base and output together. There is no
        // row-boundary reset: a later transient effect may retain output independently.
        var baseChannelVolume = 64 {
            didSet { outputChannelVolume = baseChannelVolume }
        }
        var outputChannelVolume = 64
        // Carried instrument memory is independent of the sounding generation.
        // A declared empty header also refreshes defaults, without an audio source.
        var carriedInstrumentIndex: Int?
        var semanticInstrumentIndex: Int?
        var semanticSampleIndex: Int?
        var semanticVolumeEnvelopeEnabled = false
        var triggeredSampleDefaultVolume = 0
        var triggeredSampleDefaultPan: UInt8 = 128
        var keyOffWithoutVoice = false
        var volumeValueZeroedByAxy = false
        var panningValue = 127.5
        var pan: Float = 0
        var activeEventIndex: Int?
        var activeEventMappingIndex: Int?
        var activeInstrumentIndex: Int?
        var activeSampleIndex: Int?
        // Represented header metadata/availability, never an additional song-gain factor.
        var activeSampleVolume: Float?
        // Period/envelope controls can belong to a silent channel. Only the event
        // association and represented sample availability authorize source-voice updates.
        var activePlaybackStep: Double?
        var activeLinearPeriod: Double?
        var activeAmigaPeriod: Double?
        var activeSampleBaseSampleRate: Double?
        var activeSampleRelativeNote: Int?
        var activeSampleFinetune: Int?
        var activeUsesLinearFrequencyTable: Bool?
        var activeVolumeEnvelopeStatus: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus?
        var activeVolumeEnvelopeMaxFrame: Int?
        var activeVolumeEnvelopeSourcePointCount = 0
        var activeVolumeEnvelopeMappedPointCount = 0
        var tonePortamentoTargetNote: UInt8?
        var tonePortamentoTargetLinearPeriod: Double?
        var tonePortamentoTargetAmigaPeriod: Double?
        var tonePortamentoTargetPlaybackStep: Double?
        var tonePortamentoSpeed: Int?
        var sampleOffsetMemory: SampleOffsetMemory?
        var portamentoUpMemory: PortamentoSlideMemory?
        var portamentoDownMemory: PortamentoSlideMemory?
        var volumeSlideMemory: VolumeSlideMemory? // Shared Axy/5xy/6xy full parameter and origin.
        var globalVolumeSlideMemory: GlobalVolumeSlideMemory? // Hxy only; global volume itself is song-owned.
        var vibratoSpeed = 0
        var vibratoDepth = 0
        var vibratoSpeedMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoDepthMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoControl: VibratoControlState?
        var vibratoPhase = 0
        var vibratoOutputLinearPeriod: Double?
        var vibratoOutputAmigaPeriod: Double?
        var tremolo = TremoloState()
        // FT2's ramp tremolo reads the sign of the vibrato phase. This observer
        // serves that quirk only; it does not change the existing pitch planner.
        var tremoloVibratoPhase = 0
        var tremoloVibratoSpeed = 0
        var tremoloVibratoControl = 0

        mutating func initializePanning(fromSampleHeader value: UInt8) {
            panningValue = Double(value)
            pan = PlaybackSamplePanningPolicy.plannedPan(value)
        }

        mutating func applyChannelPanningValue(_ value: Double) {
            panningValue = PlaybackSongSyntheticAdapter.clampedPanningValue(value)
            pan = PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: panningValue)
        }
    }

    struct SampleOffsetMemory: Equatable {
        let offsetFrames: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct PortamentoSlideMemory: Equatable {
        let amount: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct VolumeSlideMemory: Equatable {
        let parameter: UInt8
        let source: PlaybackSongSyntheticEffectMemorySource

        var slide: VolumeSlideAmounts {
            PlaybackSongSyntheticAdapter.axyVolumeSlideAmounts(effectParam: parameter)
        }
    }

    struct GlobalVolumeSlideMemory: Equatable {
        let parameter: UInt8
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct VibratoControlState: Equatable {
        let controlValue: Int
        let waveform: VibratoWaveform
        let retriggerSuppressed: Bool
        let source: PlaybackSongSyntheticEffectMemorySource?
    }

    enum VibratoWaveform: Int, Equatable {
        case sine = 0
        case rampDown = 1
        case square = 2

        var name: String {
            switch self {
            case .sine:
                return "sine"
            case .rampDown:
                return "ramp_down"
            case .square:
                return "square"
            }
        }
    }

    struct GlobalVolumeState: Equatable {
        static let defaultValue = 64

        var volumeValue = defaultValue

        var multiplier: Float {
            globalVolumeMultiplier(for: volumeValue)
        }
    }

    struct GlobalVolumeSlidePlan: Equatable {
        let up: Int
        let down: Int
        let direction: PlaybackSongSyntheticGlobalVolumeSlideDirection
        let amount: Int
        let bothNibblesNonzero: Bool
        let policy: String?
    }

    struct VolumeSlideAmounts: Equatable {
        let up: Int
        let down: Int
        let direction: String
        let amount: Int
        let rawUpNibble: Int
        let rawDownNibble: Int
        let bothNibblesNonzero: Bool
        let policy: String
    }

    struct SampleSelection: Equatable {
        let sample: PlaybackSample?
        let diagnosticSample: PlaybackSample?
        let skippedReason: PlaybackSongSyntheticIgnoredCell.Reason?
        let sampleMapKeymapPresent: Bool
        let mappedSampleIndex: Int?
        let mappedSampleValid: Bool
        let method: PlaybackSongSyntheticSampleSelectionMethod
        let firstPlayableSampleFallbackUsed: Bool
        let sampleMapKeymapBehaviorDeferred: Bool
        let sampleMapKeymapMissingOrDeferred: Bool
    }

    struct MixerSampleBufferCacheKey: Hashable {
        let storageAddress: UInt
        let frameCount: Int
    }

    static func clearActiveVoiceState(_ state: inout ChannelState) {
        state.activeEventIndex = nil
        state.activeEventMappingIndex = nil
        state.activeInstrumentIndex = nil
        state.activeSampleIndex = nil
        state.activeSampleVolume = nil
        state.activePlaybackStep = nil
        state.activeLinearPeriod = nil
        state.vibratoOutputLinearPeriod = nil
        state.vibratoOutputAmigaPeriod = nil
        state.activeAmigaPeriod = nil
        state.activeSampleBaseSampleRate = nil
        state.activeSampleRelativeNote = nil
        state.activeSampleFinetune = nil
        state.activeUsesLinearFrequencyTable = nil
        state.activeVolumeEnvelopeStatus = nil
        state.activeVolumeEnvelopeMaxFrame = nil
        state.activeVolumeEnvelopeSourcePointCount = 0
        state.activeVolumeEnvelopeMappedPointCount = 0
        state.tonePortamentoTargetNote = nil
        state.tonePortamentoTargetLinearPeriod = nil
        state.tonePortamentoTargetAmigaPeriod = nil
        state.tonePortamentoTargetPlaybackStep = nil
    }

    static func effectMemorySource(
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell
    ) -> PlaybackSongSyntheticEffectMemorySource {
        PlaybackSongSyntheticEffectMemorySource(
            source: source,
            channelIndex: channelIndex,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
    }

    static func memoryUnavailableReason(from reasons: [String]) -> String? {
        let uniqueReasons = Set(reasons)
        if uniqueReasons.contains("missing_vibrato_speed_memory"),
           uniqueReasons.contains("missing_vibrato_depth_memory") {
            return "missing_vibrato_speed_depth_memory"
        }
        return reasons.first
    }

    struct EventCoverageBuilder: Equatable {
        var totalCellsVisited = 0
        var emptyCells = 0
        var normalNoteCells = 0
        var noteOffCells = 0
        var invalidNoteCells = 0
        var instrumentOnlyCells = 0
        var noteWithInstrumentCells = 0
        var noteWithMissingOrZeroInstrumentCells = 0
        var scheduledNoteEvents = 0
        var skippedNoteEvents = 0
        var skippedNoteOffEventsNoActiveVoice = 0
        var ignoredOrDeferredCells = 0
        var sampleMapSelectionEvents = 0
        var firstPlayableSampleFallbackEvents = 0
        var fallbackAfterInvalidSampleMapEvents = 0
        var skippedNoValidSampleEvents = 0
        var sampleMapKeymapDeferredEvents = 0
        var eventOutsideBoundedRowRangeCount = 0
        var eventCapacityLimitCount = 0
        var cMixerVoiceCapacityLimitCount = 0
        var skipReasonCounts = [PlaybackSongSyntheticSkipReason: Int]()

        /// Records coverage and returns the existing classification of completely empty cells.
        mutating func visit(_ cell: PlaybackCell) -> Bool {
            totalCellsVisited += 1
            if isCompletelyEmpty(cell) {
                emptyCells += 1
                return true
            }
            if (1...96).contains(cell.note) {
                normalNoteCells += 1
                if cell.instrument > 0 {
                    noteWithInstrumentCells += 1
                } else {
                    noteWithMissingOrZeroInstrumentCells += 1
                }
            } else if cell.note == 97 {
                noteOffCells += 1
            } else if cell.note > 97 {
                invalidNoteCells += 1
            } else if cell.note == 0, cell.instrument > 0, cell.volumeColumn == 0, cell.effectType == 0, cell.effectParam == 0 {
                instrumentOnlyCells += 1
            }
            return false
        }

        mutating func recordScheduledNote(
            method: PlaybackSongSyntheticSampleSelectionMethod,
            firstPlayableSampleFallbackUsed: Bool,
            sampleMapKeymapBehaviorDeferred: Bool
        ) {
            scheduledNoteEvents += 1
            if method == .sampleMap {
                sampleMapSelectionEvents += 1
            }
            if firstPlayableSampleFallbackUsed {
                firstPlayableSampleFallbackEvents += 1
            }
            if method == .fallbackAfterInvalidMap {
                fallbackAfterInvalidSampleMapEvents += 1
            }
            if sampleMapKeymapBehaviorDeferred {
                sampleMapKeymapDeferredEvents += 1
            }
        }

        mutating func recordSkippedSampleSelection(
            method: PlaybackSongSyntheticSampleSelectionMethod,
            sampleMapKeymapBehaviorDeferred: Bool
        ) {
            if method == .skippedNoValidSample {
                skippedNoValidSampleEvents += 1
            }
            if sampleMapKeymapBehaviorDeferred {
                sampleMapKeymapDeferredEvents += 1
            }
        }

        mutating func recordIgnoredCell(
            reason: PlaybackSongSyntheticSkipReason,
            isNormalNote: Bool,
            isNoteOffWithoutActiveVoice: Bool = false
        ) {
            ignoredOrDeferredCells += 1
            skipReasonCounts[reason, default: 0] += 1
            if isNormalNote {
                skippedNoteEvents += 1
            }
            if isNoteOffWithoutActiveVoice {
                skippedNoteOffEventsNoActiveVoice += 1
            }
        }

        mutating func recordDeferredCellWithoutSkip() {
            ignoredOrDeferredCells += 1
            skipReasonCounts[.unsupportedDeferredEffectInteraction, default: 0] += 1
        }

        var summary: PlaybackSongSyntheticEventCoverageSummary {
            PlaybackSongSyntheticEventCoverageSummary(
                totalCellsVisited: totalCellsVisited,
                emptyCells: emptyCells,
                normalNoteCells: normalNoteCells,
                noteOffCells: noteOffCells,
                invalidNoteCells: invalidNoteCells,
                instrumentOnlyCells: instrumentOnlyCells,
                noteWithInstrumentCells: noteWithInstrumentCells,
                noteWithMissingOrZeroInstrumentCells: noteWithMissingOrZeroInstrumentCells,
                scheduledNoteEvents: scheduledNoteEvents,
                skippedNoteEvents: skippedNoteEvents,
                skippedNoteOffEventsNoActiveVoice: skippedNoteOffEventsNoActiveVoice,
                ignoredOrDeferredCells: ignoredOrDeferredCells,
                sampleMapSelectionEvents: sampleMapSelectionEvents,
                firstPlayableSampleFallbackEvents: firstPlayableSampleFallbackEvents,
                fallbackAfterInvalidSampleMapEvents: fallbackAfterInvalidSampleMapEvents,
                skippedNoValidSampleEvents: skippedNoValidSampleEvents,
                sampleMapKeymapDeferredEvents: sampleMapKeymapDeferredEvents,
                eventOutsideBoundedRowRangeCount: eventOutsideBoundedRowRangeCount,
                eventCapacityLimitCount: eventCapacityLimitCount,
                cMixerVoiceCapacityLimitCount: cMixerVoiceCapacityLimitCount,
                skipReasonCounts: skipReasonCounts
                    .map { PlaybackSongSyntheticSkipReasonCount(reason: $0.key, count: $0.value) }
                    .sorted { lhs, rhs in
                        if lhs.count != rhs.count {
                            return lhs.count > rhs.count
                        }
                        return lhs.reason.rawValue < rhs.reason.rawValue
                    }
            )
        }

        private func isCompletelyEmpty(_ cell: PlaybackCell) -> Bool {
            cell.note == 0 &&
                cell.instrument == 0 &&
                cell.volumeColumn == 0 &&
                cell.effectType == 0 &&
                cell.effectParam == 0
        }
    }

    struct TraversalEffectKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let rowIndex: Int
        let channelIndex: Int
        let syntheticRow: Int
        let effectType: UInt8
        let effectParam: UInt8
    }

    struct AdapterRowContext {
        let emptyVolumeColumn = PlaybackSongVolumeColumnDecoder.decode(0)
        var emptyCellFastPathCount = 0
        var fullCellDispatchCount = 0
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var volumeColumnMappings = [PlaybackSongSyntheticVolumeColumnMapping]()
        var voiceStateUpdates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        var playbackStateEvents = [PlaybackVoiceStateEvent]()
        var noteOnlyEventIndices = Set<Int>()
        var coldReleasedEventIndices = Set<Int>()
        var xmChannelRows = [PlaybackXMChannelRow]()
        var xmEmptyRoutes = [PlaybackXMEmptyRoute]()
        var sampleOffsetEffects = [PlaybackSongSyntheticSampleOffsetDiagnostic]()
        var setFinetuneEffects = [PlaybackSongSyntheticSetFinetuneDiagnostic]()
        var envelopePositionEffects = [PlaybackSongSyntheticEnvelopePositionDiagnostic]()
        var noteCutEffects = [PlaybackSongSyntheticNoteCutDiagnostic]()
        var noteDelayEffects = [PlaybackSongSyntheticNoteDelayDiagnostic]()
        var retriggerEffects = [PlaybackSongSyntheticRetriggerDiagnostic]()
        var tonePortamentoEffects = [PlaybackSongSyntheticTonePortamentoDiagnostic]()
        var portamentoSlideEffects = [PlaybackSongSyntheticPortamentoSlideDiagnostic]()
        var finePortamentoUpEffects = [PlaybackSongSyntheticFinePortamentoUpDiagnostic]()
        var finePortamentoDownEffects = [PlaybackSongSyntheticFinePortamentoDownDiagnostic]()
        var extraFinePortamentoEffects = [PlaybackSongSyntheticExtraFinePortamentoDiagnostic]()
        var arpeggioEffects = [PlaybackSongSyntheticArpeggioDiagnostic]()
        var vibratoControlEffects = [PlaybackSongSyntheticVibratoControlDiagnostic]()
        var vibratoEffects = [PlaybackSongSyntheticVibratoDiagnostic]()
        var keyOffEvents = [PlaybackSongSyntheticKeyOffDiagnostic]()
        var effectCommandDiagnostics = [PlaybackSongSyntheticEffectCommandDiagnostic]()
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
        var deferredCellFields = [PlaybackSongSyntheticDeferredCellField]()
        var eventCoverage = EventCoverageBuilder()
        var events = [SyntheticTrackerEvent]()
        var channelStates = [ChannelState]()
        var mixerSampleBuffers = [MixerSampleBufferCacheKey: MixerSampleBuffer]()
        var globalVolumeState = GlobalVolumeState()
        var traversalEffectStatuses = [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()
    }

    static func adapt(
        _ song: PlaybackSong,
        orderIndex: Int,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil
    ) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: orderIndex, orderCount: 1, sampleRate: sampleRate, profileSession: profileSession)
    }

    static func adapt(
        _ song: PlaybackSong,
        orderRange: Range<Int>,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil
    ) -> PlaybackSongSyntheticPlan {
        adapt(
            song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: max(0, orderRange.count),
            sampleRate: sampleRate,
            profileSession: profileSession
        )
    }

    static func adapt(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil
    ) -> PlaybackSongSyntheticPlan {
        let totalStart = profileSession?.beginPhase()
        let traversalStart = profileSession?.beginPhase()
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount
        )
        profileSession?.recordPhase(
            "order_traversal",
            startedAt: traversalStart,
            fields: AdapterPlanProfileFields.playbackSong(song) + [
                AdapterPlanProfileField("requested_start_order_index", startOrderIndex),
                AdapterPlanProfileField("requested_order_count", max(0, orderCount)),
                AdapterPlanProfileField("row_count", traversalPlan.pathLength),
                AdapterPlanProfileField("adapted_order_count", traversalPlan.adaptedOrders.count),
                AdapterPlanProfileField("traversal_diagnostic_count", traversalPlan.traversalDiagnostics.count),
                AdapterPlanProfileField("traversal_guard_hit", traversalPlan.guardHit),
                AdapterPlanProfileField("traversal_stop_reason", traversalPlan.stopReason.rawValue),
            ]
        )
        let timingStart = profileSession?.beginPhase()
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            traversalPlan: traversalPlan,
            sampleRate: sampleRate
        )
        profileSession?.recordPhase(
            "timing_frame_calculation",
            startedAt: timingStart,
            fields: [
                AdapterPlanProfileField("row_count", timingPlan.rowTimings.count),
                AdapterPlanProfileField("timing_change_count", timingPlan.timingChanges.count),
                AdapterPlanProfileField("initial_speed", timingPlan.initialSpeed),
                AdapterPlanProfileField("initial_bpm", timingPlan.initialBPM),
                AdapterPlanProfileField("final_speed", timingPlan.finalSpeed),
                AdapterPlanProfileField("final_bpm", timingPlan.finalBPM),
            ]
        )
        let timingConfig = SyntheticTrackerTimingConfig(
            speed: timingPlan.initialSpeed,
            bpm: timingPlan.initialBPM,
            sampleRate: timingPlan.sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var rowMappings = [PlaybackSongSyntheticRowMapping]()
        var context = AdapterRowContext()
        let estimatedRows = timingPlan.rowTimings.count

        rowMappings.reserveCapacity(estimatedRows)
        context.rowDiagnostics.reserveCapacity(estimatedRows)
        context.events.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.eventMappings.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.ignoredCells.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.deferredCellFields.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.effectCommandDiagnostics.reserveCapacity(min(estimatedRows, 65_536))
        context.volumeColumnMappings.reserveCapacity(min(estimatedRows, 65_536))
        context.voiceStateUpdates.reserveCapacity(min(estimatedRows * 2, 65_536))
        context.channelStates.reserveCapacity(traversalPlan.rows.reduce(0) { max($0, $1.row.cells.count) })
        context.mixerSampleBuffers.reserveCapacity(song.instrumentsByIndex.values.reduce(0) { $0 + $1.samples.count })
        let traversalStatusStart = profileSession?.beginPhase()
        context.traversalEffectStatuses = traversalEffectStatuses(from: traversalPlan.traversalDiagnostics)
        profileSession?.recordPhase(
            "traversal_effect_status_indexing",
            startedAt: traversalStatusStart,
            fields: [
                AdapterPlanProfileField("traversal_diagnostic_count", traversalPlan.traversalDiagnostics.count),
                AdapterPlanProfileField("traversal_effect_status_count", context.traversalEffectStatuses.count),
            ]
        )

        let rowIterationStart = profileSession?.beginPhase()
        var eventGenerationNanoseconds: UInt64 = 0
        for (rowIndex, traversalRow) in traversalPlan.rows.enumerated() {
            rowMappings.append(PlaybackSongSyntheticRowMapping(
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow
            ))
            let rowTiming = timingPlan.rowTimings.indices.contains(traversalRow.syntheticRow)
                ? timingPlan.rowTimings[traversalRow.syntheticRow]
                : nil
            let rowTimingConfig = rowTiming.map { timing in
                SyntheticTrackerTimingConfig(
                    speed: timing.effectiveSpeed,
                    bpm: timing.effectiveBPM,
                    sampleRate: timingPlan.sampleRate
                )
            } ?? timingPlan.timingConfig(forSyntheticRow: traversalRow.syntheticRow)
            let eventGenerationStart = profileSession == nil ? nil : DispatchTime.now().uptimeNanoseconds
            let rowDiagnostic = appendEvents(
                from: traversalRow.row,
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow,
                song: song,
                timingConfig: rowTimingConfig,
                timingPlan: timingPlan,
                scheduledStartFrame: rowTiming?.rowStartFrame ?? timingPlan.frameFor(row: traversalRow.syntheticRow, tick: 0),
                nextRow: traversalPlan.rows.indices.contains(rowIndex + 1) ? traversalPlan.rows[rowIndex + 1].row : nil,
                context: &context
            )
            if let eventGenerationStart {
                let eventGenerationEnd = DispatchTime.now().uptimeNanoseconds
                if eventGenerationEnd >= eventGenerationStart {
                    eventGenerationNanoseconds += eventGenerationEnd - eventGenerationStart
                }
            }
            context.rowDiagnostics.append(rowDiagnostic)
        }
        profileSession?.recordMeasuredPhase(
            "event_generation",
            elapsedMS: Double(eventGenerationNanoseconds) / 1_000_000.0,
            fields: [
                AdapterPlanProfileField("row_count", traversalPlan.pathLength),
                AdapterPlanProfileField("synthetic_event_count", context.events.count),
                AdapterPlanProfileField("event_mapping_count", context.eventMappings.count),
                AdapterPlanProfileField("ignored_cell_count", context.ignoredCells.count),
                AdapterPlanProfileField("voice_state_update_count", context.voiceStateUpdates.count),
                AdapterPlanProfileField("empty_cell_bypass_count", context.emptyCellFastPathCount),
                AdapterPlanProfileField("full_cell_dispatch_count", context.fullCellDispatchCount),
            ]
        )
        profileSession?.recordPhase(
            "pattern_row_iteration",
            startedAt: rowIterationStart,
            fields: [
                AdapterPlanProfileField("row_count", traversalPlan.pathLength),
                AdapterPlanProfileField("row_diagnostic_count", context.rowDiagnostics.count),
                AdapterPlanProfileField("synthetic_event_count", context.events.count),
            ]
        )

        planHxyChannelTargets(timingPlan: timingPlan, context: &context)
        var plan = PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: SyntheticPattern(rowCount: traversalPlan.pathLength, events: context.events),
            diagnostics: PlaybackSongSyntheticDiagnostics(
                requestedStartOrderIndex: startOrderIndex,
                requestedOrderCount: safeOrderCount,
                sampleRate: timingConfig.sampleRate,
                initialSpeed: timingConfig.speed,
                initialBPM: timingConfig.bpm,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                syntheticRowCount: traversalPlan.pathLength,
                adaptedOrders: traversalPlan.adaptedOrders,
                rowMappings: rowMappings,
                rowTiming: timingPlan.rowTimingDiagnostics,
                timingChanges: timingPlan.timingChanges,
                traversalDiagnostics: traversalPlan.traversalDiagnostics,
                traversalPathLength: traversalPlan.pathLength,
                traversalStopReason: traversalPlan.stopReason,
                traversalGuardHit: traversalPlan.guardHit,
                effectCommandDiagnostics: context.effectCommandDiagnostics,
                rowDiagnostics: context.rowDiagnostics,
                volumeColumnMappings: context.volumeColumnMappings,
                voiceStateUpdates: context.voiceStateUpdates,
                sampleOffsetEffects: context.sampleOffsetEffects,
                setFinetuneEffects: context.setFinetuneEffects,
                envelopePositionEffects: context.envelopePositionEffects,
                noteCutEffects: context.noteCutEffects,
                noteDelayEffects: context.noteDelayEffects,
                retriggerEffects: context.retriggerEffects,
                tonePortamentoEffects: context.tonePortamentoEffects,
                portamentoSlideEffects: context.portamentoSlideEffects,
                finePortamentoUpEffects: context.finePortamentoUpEffects,
                finePortamentoDownEffects: context.finePortamentoDownEffects,
                extraFinePortamentoEffects: context.extraFinePortamentoEffects,
                arpeggioEffects: context.arpeggioEffects,
                vibratoControlEffects: context.vibratoControlEffects,
                vibratoEffects: context.vibratoEffects,
                keyOffEvents: context.keyOffEvents,
                eventMappings: context.eventMappings,
                ignoredCells: context.ignoredCells,
                deferredCellFields: context.deferredCellFields,
                eventCoverage: context.eventCoverage.summary
            )
        )
        plan.noteOnlyEventIndices = context.noteOnlyEventIndices
        plan.coldReleasedEventIndices = context.coldReleasedEventIndices
        plan.playbackStateEvents = context.playbackStateEvents
        plan.xmChannelRows = context.xmChannelRows
        plan.xmEmptyRoutes = context.xmEmptyRoutes
        plan.xmEnvelopeTimeline = PlaybackXMEnvelopeTimeline(song: song, timing: timingPlan, plan: plan)
        profileSession?.recordPhase(
            "playback_song_synthetic_adapter_adapt_total",
            startedAt: totalStart,
            fields: AdapterPlanProfileFields.playbackSong(song) + AdapterPlanProfileFields.syntheticPlan(plan)
        )
        return plan
    }

    static func traversalEffectStatuses(
        from diagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
    ) -> [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status] {
        diagnostics.reduce(into: [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()) { result, diagnostic in
            let key = TraversalEffectKey(
                orderIndex: diagnostic.source.orderIndex,
                patternIndex: diagnostic.source.patternIndex,
                rowIndex: diagnostic.source.rowIndex,
                channelIndex: diagnostic.channelIndex,
                syntheticRow: diagnostic.syntheticRow,
                effectType: diagnostic.effectType,
                effectParam: diagnostic.effectParam
            )
            result[key] = effectCommandStatus(for: diagnostic.status)
        }
    }

    static func effectCommandStatus(
        for traversalStatus: PlaybackSongSyntheticTraversalDiagnostic.Status
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic.Status {
        switch traversalStatus {
        case .applied, .loopStartMarked, .loopTaken:
            return .applied
        case .deferred:
            return .deferredUnsupported
        case .invalidTarget:
            return .invalidTarget
        case .outOfRange:
            return .outOfRange
        case .missingLoopStart:
            return .missingLoopStart
        case .loopLimitHit:
            return .loopLimitHit
        }
    }

    static func appendEvents(
        from row: PlaybackRow,
        source: PlaybackPosition,
        syntheticRow: Int,
        song: PlaybackSong,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        scheduledStartFrame: Int,
        nextRow: PlaybackRow? = nil,
        context: inout AdapterRowContext
    ) -> PlaybackSongSyntheticRowDiagnostic {
        let eventStartCount = context.events.count
        let ignoredStartCount = context.ignoredCells.count
        if context.channelStates.count < row.cells.count {
            context.channelStates.append(contentsOf: repeatElement(
                ChannelState(),
                count: row.cells.count - context.channelStates.count
            ))
        }
        for channelIndex in row.cells.indices {
            let cell = row.cells[channelIndex]
            if context.eventCoverage.visit(cell) {
                // Empty cells have no row writers. Capture the unchanged controls once,
                // retaining every occurrence and diagnostic without copying a working
                // channel state or dispatching no-op decoding/effect helpers. The later
                // nonzero-tick pass stays in its established row-wide order below.
                context.emptyCellFastPathCount += 1
                context.xmChannelRows.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                    controls: context.channelStates[channelIndex], instrumentOnlyReset: nil))
                context.ignoredCells.append(ignoredCell(
                    source: source, channelIndex: channelIndex, cell: cell, reason: .emptyNote,
                    volumeColumn: context.emptyVolumeColumn, hasIgnoredVolumeColumn: false, hasIgnoredEffect: false
                ))
                context.eventCoverage.recordIgnoredCell(reason: .emptyCell, isNormalNote: false)
                continue
            }
            context.fullCellDispatchCount += 1
            let nextCell = nextRow.flatMap { $0.cells.indices.contains(channelIndex) ? $0.cells[channelIndex] : nil }
            let restoreVibratoAtRowEnd = nextCell.map { $0.effectType != 4 && $0.effectType != 6 } ?? false
            if let effectCommandDiagnostic = effectCommandDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                traversalEffectStatuses: context.traversalEffectStatuses,
                timingConfig: timingConfig,
                channelState: context.channelStates[channelIndex]
            ) {
                context.effectCommandDiagnostics.append(effectCommandDiagnostic)
            }
            var channelState = context.channelStates[channelIndex]
            // A row establishes H memory only when its nonzero-tick handler runs.
            // Planning knows the effective speed, so F01 neither seeds nor replaces it.
            if cell.effectType == 0x11, cell.effectParam != 0, timingConfig.speed > 1 {
                channelState.globalVolumeSlideMemory = .init(parameter: cell.effectParam,
                    source: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell))
            }
            let isNoteOnly = cell.instrument == 0
            let routedInstrumentIndex = isNoteOnly ? channelState.carriedInstrumentIndex ?? 0 : Int(cell.instrument)
            var instrumentOnlyReset: MixerPlaybackStateChange?
            defer {
                context.xmChannelRows.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame, controls: channelState,
                    instrumentOnlyReset: instrumentOnlyReset))
                let axyUpdates = isOrdinaryVolumeColumnSlide(cell.volumeColumn) ? [] : applyEffectColumnVolumeSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    globalVolumeValue: context.globalVolumeState.volumeValue
                )
                if !axyUpdates.isEmpty {
                    context.voiceStateUpdates.append(contentsOf: axyUpdates)
                }
                context.channelStates[channelIndex] = channelState
            }
            let extendedSubcommand = cell.effectType == 0x0E ? ((cell.effectParam >> 4) & 0x0F) : nil
            let hasNoteCutEffect = extendedSubcommand == 0x0C
            let hasNoteDelayEffect = extendedSubcommand == 0x0D
            let hasRetriggerEffect = isRetriggerEffect(cell)
            let hasSetFinetuneEffect = extendedSubcommand == 0x05
            let hasFinePortamentoUpEffect = extendedSubcommand == 0x01
            let hasFinePortamentoDownEffect = extendedSubcommand == 0x02
            let hasXxyExtraFinePortamentoEffect = isXxyExtraFinePortamentoEffect(cell)
            let hasVibratoControlEffect = extendedSubcommand == 0x04
            let hasArpeggio = isArpeggioEffect(cell)
            let hasPortamentoSlide = isPortamentoSlideEffect(cell)
            let hasTonePortamento = isTonePortamentoEffect(cell)
            let hasVibrato = isVibratoEffect(cell) || (0xB0...0xBF).contains(cell.volumeColumn)
            let hasVibratoVolumeSlide = isVibratoVolumeSlideEffect(cell)
            let hasKxxKeyOff = isKxxKeyOffEffect(cell)
            let hasLxxSetEnvelopePosition = isLxxSetEnvelopePositionEffect(cell)
            var volumeColumn = PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn)
            let hasVolumeColumnTonePortamento = isTonePortamentoVolumeColumn(volumeColumn)
            let handlesTonePortamento = hasTonePortamento || hasVolumeColumnTonePortamento
            let hasValidImmediateNoteInstrument = (1...96).contains(cell.note) &&
                cell.instrument > 0 &&
                !hasNoteDelayEffect
            // Resolve once through the existing keymap authority. Ordinary triggers
            // load the new sample's default before same-cell volume writers; delayed,
            // retrigger, key-off, and portamento paths retain their own contracts.
            let explicitTriggerSelection: SampleSelection?
            if hasValidImmediateNoteInstrument, !handlesTonePortamento, !hasRetriggerEffect,
               !(hasKxxKeyOff && cell.effectParam == 0),
               let instrument = song.instrumentsByIndex[Int(cell.instrument)] {
                explicitTriggerSelection = selectSample(forNote: cell.note, from: instrument)
            } else {
                explicitTriggerSelection = nil
            }
            var selectedEmptyPitch: PlaybackStepMapping?
            if let selection = explicitTriggerSelection, selection.sample == nil,
               let slot = selection.mappedSampleIndex,
               let header = song.xmSampleSlotProvenanceByInstrument[Int(cell.instrument)]?.first(where: {
                   $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
               }) {
                context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                    scheduledFrame: scheduledStartFrame, instrumentIndex: Int(cell.instrument), sampleIndex: slot,
                    stoppedEventIndex: channelState.activeEventIndex))
                selectedEmptyPitch = selectEmptyHeader(header, cell: cell, instrumentIndex: Int(cell.instrument),
                    song: song, timingConfig: timingConfig, state: &channelState)
            }
            // Note-only selects a source/header but does not reload tracker volume/pan
            // or restart instrument clocks. Resolve before the same-cell writers.
            if isNoteOnly, (1...96).contains(cell.note), !handlesTonePortamento,
               !(hasKxxKeyOff && cell.effectParam == 0),
               !hasNoteDelayEffect || cell.effectParam == 0xD0,
               let instrument = song.instrumentsByIndex[routedInstrumentIndex] {
                let selection = selectSample(forNote: cell.note, from: instrument, missingKeymapPolicy: .fail)
                if selection.sample == nil, let slot = selection.mappedSampleIndex {
                    context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                        scheduledFrame: scheduledStartFrame, instrumentIndex: routedInstrumentIndex, sampleIndex: slot,
                        stoppedEventIndex: channelState.activeEventIndex, preservesChannelState: true))
                    if let header = song.xmSampleSlotProvenanceByInstrument[routedInstrumentIndex]?.first(where: {
                        $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
                    }) {
                        selectedEmptyPitch = selectEmptyHeader(header, cell: cell, instrumentIndex: routedInstrumentIndex,
                            initializesDefaults: false, song: song, timingConfig: timingConfig, state: &channelState)
                    } else {
                        // An undeclared slot has no header defaults to invent.
                        clearSourceAssociation(&channelState)
                        channelState.semanticInstrumentIndex = routedInstrumentIndex
                        channelState.semanticSampleIndex = slot
                        channelState.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
                        applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope,
                            timingConfig: timingConfig), to: &channelState)
                    }
                }
            }
            if cell.instrument > 0, song.instrumentsByIndex[Int(cell.instrument)] != nil {
                channelState.carriedInstrumentIndex = Int(cell.instrument)
            }
            let restoresInstrumentOnlyDefaults = cell.note == 0 && cell.instrument > 0 &&
                song.instrumentsByIndex[Int(cell.instrument)] != nil &&
                !(hasNoteDelayEffect && cell.effectParam & 15 != 0)
            if restoresInstrumentOnlyDefaults {
                if channelState.activeEventIndex == nil {
                    channelState.keyOffWithoutVoice = hasKxxKeyOff && cell.effectParam == 0 && !hasVolumeColumnTonePortamento
                }
                instrumentOnlyReset = restoreInstrumentOnlyDefaults(cell: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                    globalVolume: context.globalVolumeState.volumeValue, channelState: &channelState,
                    updates: &context.voiceStateUpdates, resets: &context.playbackStateEvents)
            }
            if channelState.activeEventIndex == nil && !handlesTonePortamento &&
                (cell.note == 97 || (hasKxxKeyOff && cell.effectParam == 0)) {
                channelState.keyOffWithoutVoice = true
            }
            prepareTremoloRow(
                cell: cell, song: song, source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                globalVolume: context.globalVolumeState.volumeValue,
                initializesInstrumentVolume: explicitTriggerSelection?.sample != nil || selectedEmptyPitch != nil || restoresInstrumentOnlyDefaults,
                channelState: &channelState, updates: &context.voiceStateUpdates
            )
            if let sample = explicitTriggerSelection?.sample {
                channelState.baseChannelVolume = sampleVolumeRawEstimate(for: sample.volume)
                channelState.volumeValueZeroedByAxy = false
            }
            let delaysInstrumentVolumeState = hasValidImmediateNoteInstrument && handlesTonePortamento
            let channelStateBeforeVolumeColumn = channelState
            if !delaysInstrumentVolumeState {
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState,
                    memorySource: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell))
            }
            let hasDeferredEffectCell = hasDeferredEffect(cell, channelState: channelState)
            if !delaysInstrumentVolumeState, let update = voiceStateUpdate(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                cell: cell,
                volumeColumn: volumeColumn,
                channelStateBefore: channelStateBeforeVolumeColumn,
                channelStateAfter: channelState,
                globalVolumeValue: context.globalVolumeState.volumeValue
            ) {
                context.voiceStateUpdates.append(update)
            }
            if let update = applyEffectColumnState(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                rowSpeed: timingConfig.speed,
                channelState: &channelState,
                globalVolumeValue: context.globalVolumeState.volumeValue
            ) {
                context.voiceStateUpdates.append(update)
            }
            if hasVibratoControlEffect {
                let diagnostic = handleVibratoControl(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    channelState: &channelState
                )
                context.vibratoControlEffects.append(diagnostic)
            }
            context.channelStates[channelIndex] = channelState
            if cell.effectType == 0x10 {
                context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSet(
                    from: cell,
                    source: source,
                    sourceChannelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    channelStates: context.channelStates,
                    globalVolumeState: &context.globalVolumeState
                ))
            }
            if cell.effectType == 0x11 && cell.effectParam == 0 && channelState.globalVolumeSlideMemory == nil {
                context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSlide(
                    from: cell,
                    source: source,
                    sourceChannelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    channelStates: context.channelStates,
                    globalVolumeState: &context.globalVolumeState
                ))
            }
            if !delaysInstrumentVolumeState, cell.volumeColumn != 0 {
                context.volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    volumeColumn: volumeColumn
                ))
            }
            if !delaysInstrumentVolumeState {
                appendDeferredFields(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    volumeColumn: volumeColumn,
                    includeKeyOff: false,
                    hasDeferredEffectOverride: hasDeferredEffectCell,
                    deferredCellFields: &context.deferredCellFields
                )
            }
            let noteDelay = hasNoteDelayEffect
                ? noteDelayDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    originalFrame: scheduledStartFrame,
                    eventIndex: nil
                )
                : nil
            if hasArpeggio, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleArpeggio(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.arpeggioEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasPortamentoSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handlePortamentoSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState
                )
                context.portamentoSlideEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasFinePortamentoUpEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleFinePortamentoUp(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.finePortamentoUpEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasFinePortamentoDownEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleFinePortamentoDown(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.finePortamentoDownEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasXxyExtraFinePortamentoEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleExtraFinePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.extraFinePortamentoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibrato || hasVibratoVolumeSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    restoreAtRowEnd: restoreVibratoAtRowEnd,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if handlesTonePortamento, cell.note != 97, !delaysInstrumentVolumeState {
                let diagnostic = handleTonePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    volumeColumn: hasVolumeColumnTonePortamento ? volumeColumn : nil
                )
                context.tonePortamentoEffects.append(diagnostic)
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                context.channelStates[channelIndex] = channelState
                continue
            }
            if cell.note == 97 || ((1...96).contains(cell.note) && isNoteOnly && hasKxxKeyOff && cell.effectParam == 0) {
                if cell.note == 97 {
                    handleKeyOff(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        syntheticTick: 0,
                        scheduledFrame: scheduledStartFrame,
                        rowSpeed: timingConfig.speed,
                        rowBPM: timingConfig.bpm,
                        volumeColumn: volumeColumn,
                        cell: cell,
                        channelState: &channelState,
                        events: &context.events,
                        keyOffEvents: &context.keyOffEvents,
                        voiceStateUpdates: &context.voiceStateUpdates,
                        globalVolume: context.globalVolumeState.volumeValue,
                        eventMappings: &context.eventMappings,
                        ignoredCells: &context.ignoredCells,
                        deferredCellFields: &context.deferredCellFields,
                        eventCoverage: &context.eventCoverage
                    )
                }
                if hasKxxKeyOff {
                    handleKxxKeyOff(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        volumeColumn: volumeColumn,
                        channelState: &channelState,
                        events: &context.events,
                        keyOffEvents: &context.keyOffEvents,
                        voiceStateUpdates: &context.voiceStateUpdates,
                        globalVolume: context.globalVolumeState.volumeValue,
                        eventMappings: &context.eventMappings,
                        ignoredCells: &context.ignoredCells,
                        deferredCellFields: &context.deferredCellFields,
                        eventCoverage: &context.eventCoverage
                    )
                }
                if hasRetriggerEffect {
                    _ = handleRetrigger(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        volumeColumn: volumeColumn,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        globalVolumeState: context.globalVolumeState,
                        channelState: &channelState,
                        events: &context.events,
                        eventMappings: &context.eventMappings,
                        retriggerEffects: &context.retriggerEffects,
                        eventCoverage: &context.eventCoverage
                    )
                }
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noNoteDeferred,
                        activeVoiceFound: channelState.activeEventIndex != nil,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex
                    ))
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                context.channelStates[channelIndex] = channelState
                continue
            }
            guard (1...96).contains(cell.note) else {
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                let retrigger = hasRetriggerEffect
                    ? handleRetrigger(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        volumeColumn: volumeColumn,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        globalVolumeState: context.globalVolumeState,
                        channelState: &channelState,
                        events: &context.events,
                        eventMappings: &context.eventMappings,
                        retriggerEffects: &context.retriggerEffects,
                        eventCoverage: &context.eventCoverage
                    )
                    : nil
                if retrigger?.applied == true {
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noNoteDeferred,
                        activeVoiceFound: channelState.activeEventIndex != nil,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex
                    ))
                }
                if hasKxxKeyOff {
                    handleKxxKeyOff(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        volumeColumn: volumeColumn,
                        channelState: &channelState,
                        events: &context.events,
                        keyOffEvents: &context.keyOffEvents,
                        voiceStateUpdates: &context.voiceStateUpdates,
                        globalVolume: context.globalVolumeState.volumeValue,
                        eventMappings: &context.eventMappings,
                        ignoredCells: &context.ignoredCells,
                        deferredCellFields: &context.deferredCellFields,
                        eventCoverage: &context.eventCoverage,
                        instrumentOnlyVolumeRestored: restoresInstrumentOnlyDefaults
                    )
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: noteDelay?.status == .noNoteDeferred
                        ? .noteDelayWithoutNote
                        : ignoredNoteReason(cell, volumeColumn: volumeColumn),
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: noteDelay != nil || hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: false)
                context.channelStates[channelIndex] = channelState
                continue
            }
            if let noteDelay, noteDelay.outOfRow {
                context.noteDelayEffects.append(noteDelay)
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .noteDelayOutOfRow,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: true
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }

            let instrumentIndex = routedInstrumentIndex
            guard instrumentIndex > 0 else {
                if hasVibrato || hasVibratoVolumeSlide {
                    // No owning instrument means no sample trigger or fallback.
                    context.vibratoEffects.append(handleVibrato(
                        from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        timingConfig: timingConfig, timingPlan: timingPlan,
                        restoreAtRowEnd: restoreVibratoAtRowEnd, channelState: &channelState
                    ))
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.extraFinePortamentoEffects.append(diagnostic)
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .missingInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }
            guard let instrument = song.instrument(forInstrument: instrumentIndex) else {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.extraFinePortamentoEffects.append(diagnostic)
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .unknownInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }
            let sampleSelection = explicitTriggerSelection ?? selectSample(forNote: cell.note, from: instrument,
                missingKeymapPolicy: isNoteOnly ? .fail : .firstPlayableSample)
            guard let sample = sampleSelection.sample else {
                if hasVibrato || hasVibratoVolumeSlide {
                    // Empty routing retires the source, not channel-local effect execution.
                    // The existing instrument gate has already applied the prior E4 reset policy.
                    context.vibratoEffects.append(handleVibrato(
                        from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        timingConfig: timingConfig, timingPlan: timingPlan,
                        restoreAtRowEnd: restoreVibratoAtRowEnd, channelState: &channelState
                    ))
                }
                if isNoteOnly, let slot = sampleSelection.mappedSampleIndex {
                    if let delay = noteDelay, delay.applied, delay.requestedTick > 0 {
                        context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                            scheduledFrame: delay.delayedFrame ?? scheduledStartFrame, instrumentIndex: instrumentIndex,
                            sampleIndex: slot, stoppedEventIndex: channelState.activeEventIndex, tick: delay.requestedTick))
                        if let header = song.xmSampleSlotProvenanceByInstrument[instrumentIndex]?.first(where: {
                            $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
                        }) {
                            selectedEmptyPitch = selectEmptyHeader(header, cell: cell, instrumentIndex: instrumentIndex,
                                initializesDefaults: false, song: song, timingConfig: timingConfig, state: &channelState)
                        } else {
                            clearSourceAssociation(&channelState)
                            channelState.semanticInstrumentIndex = instrumentIndex
                            channelState.semanticSampleIndex = slot
                            channelState.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
                            applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope,
                                timingConfig: timingConfig), to: &channelState)
                        }
                        resetTremoloTriggerPhases(state: &channelState)
                    }
                    // E9x repeats the selected empty route at the existing tick cadence.
                    // Its instrument reset belongs to the channel, with no source event.
                    let repeatInterval = retriggerIntervalNibble(from: cell)
                    if extendedSubcommand == 9, repeatInterval > 0, repeatInterval < timingConfig.speed {
                        resetTremoloTriggerPhases(state: &channelState)
                        for tick in stride(from: repeatInterval, to: timingConfig.speed, by: repeatInterval) {
                            context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                                instrumentIndex: instrumentIndex, sampleIndex: slot, stoppedEventIndex: nil, tick: tick))
                        }
                    }
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: selectedEmptyPitch.map { song.usesLinearFrequencyTable ? setFinetuneStatus(for: $0) : .unsupportedFrequencyTable } ?? .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil,
                        sampleFinetune: sampleSelection.diagnosticSample?.finetune,
                        pitchMapping: selectedEmptyPitch
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.extraFinePortamentoEffects.append(diagnostic)
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: sampleSelection.skippedReason ?? .unknown,
                    diagnosticSample: sampleSelection.diagnosticSample,
                    sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                    mappedSampleIndex: sampleSelection.mappedSampleIndex,
                    mappedSampleValid: sampleSelection.mappedSampleValid,
                    sampleSelectionMethod: sampleSelection.method,
                    firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                    sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.eventCoverage.recordSkippedSampleSelection(
                    method: sampleSelection.method,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
                )
                context.channelStates[channelIndex] = channelState
                continue
            }

            let sampleLength = selectedSampleLength(sample)
            var tonePortamentoInstrumentStateBefore: ChannelState?
            var tonePortamentoInstrumentStateAfter: ChannelState?
            var tonePortamentoInstrumentDefaultVolumeApplied = false
            if delaysInstrumentVolumeState {
                let instrumentStateBefore = channelState
                channelState.baseChannelVolume = 64
                channelState.volumeValueZeroedByAxy = false
                if handlesTonePortamento {
                    channelState.activeInstrumentIndex = instrumentIndex
                    channelState.activeSampleIndex = sample.sampleIndex
                    channelState.activeSampleVolume = sample.volume
                    channelState.activeSampleBaseSampleRate = sample.baseSampleRate
                    channelState.activeSampleRelativeNote = sample.relativeNote
                    channelState.activeSampleFinetune = sample.finetune
                    channelState.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
                }
                tonePortamentoInstrumentStateBefore = instrumentStateBefore
                tonePortamentoInstrumentStateAfter = channelState
                let instrumentGainBefore = instrumentStateBefore.activeSampleVolume.map { _ in
                    songGain(outputChannelVolume: instrumentStateBefore.outputChannelVolume)
                }
                let instrumentGainAfter = channelState.activeSampleVolume.map { _ in
                    songGain(outputChannelVolume: channelState.outputChannelVolume)
                }
                tonePortamentoInstrumentDefaultVolumeApplied = instrumentStateBefore.baseChannelVolume != channelState.baseChannelVolume ||
                    instrumentStateBefore.activeSampleVolume != channelState.activeSampleVolume
                if handlesTonePortamento {
                    context.voiceStateUpdates.append(voiceStateUpdateDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        cell: cell,
                        commandSource: .instrumentState,
                        command: .instrumentDefaultVolume(value: channelState.baseChannelVolume),
                        rawVolumeColumn: nil,
                        effectType: cell.effectType,
                        effectParam: cell.effectParam,
                        status: .applied,
                        behavior: nil,
                        channelStateBefore: instrumentStateBefore,
                        channelStateAfter: channelState,
                        globalVolumeBefore: context.globalVolumeState.volumeValue,
                        globalVolumeAfter: context.globalVolumeState.volumeValue,
                        activeVoiceUpdatedOverride: instrumentStateBefore.activeEventIndex != nil &&
                            instrumentStateBefore.activeSampleVolume != nil &&
                            instrumentGainBefore != instrumentGainAfter
                    ))
                }
                let beforeVolumeColumn = channelState
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState,
                    memorySource: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell))
                if handlesTonePortamento {
                    tonePortamentoInstrumentStateAfter = channelState
                }
                if let update = voiceStateUpdate(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    cell: cell,
                    volumeColumn: volumeColumn,
                    channelStateBefore: beforeVolumeColumn,
                    channelStateAfter: channelState,
                    globalVolumeValue: context.globalVolumeState.volumeValue
                ) {
                    context.voiceStateUpdates.append(update)
                }
                if cell.volumeColumn != 0 {
                    context.volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        syntheticTick: 0,
                        volumeColumn: volumeColumn
                    ))
                }
                appendDeferredFields(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    volumeColumn: volumeColumn,
                    includeKeyOff: false,
                    hasDeferredEffectOverride: hasDeferredEffectCell,
                    deferredCellFields: &context.deferredCellFields
                )
            }
            let sampleOffset = sampleOffsetDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                selectedSampleLength: sampleLength,
                channelState: &channelState
            )
            if sampleOffset.detected {
                context.sampleOffsetEffects.append(sampleOffset)
            }
            if sampleOffset.skipped {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.extraFinePortamentoEffects.append(diagnostic)
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .sampleOffsetOutOfRange,
                    diagnosticSample: sample,
                    sampleOffsetFrames: sampleOffset.computedOffsetFrames,
                    sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                    mappedSampleIndex: sampleSelection.mappedSampleIndex,
                    mappedSampleValid: sampleSelection.mappedSampleValid,
                    sampleSelectionMethod: sampleSelection.method,
                    firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                    sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }

            if !handlesTonePortamento && !isNoteOnly {
                volumeColumn = applyTriggeredSamplePanning(
                    sample.panning,
                    volumeColumn: volumeColumn,
                    cell: cell,
                    to: &channelState
                )
            }

            if handlesTonePortamento {
                let diagnostic = handleTonePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    instrumentStateBefore: tonePortamentoInstrumentStateBefore,
                    instrumentStateAfter: tonePortamentoInstrumentStateAfter,
                    instrumentDefaultVolumeApplied: tonePortamentoInstrumentDefaultVolumeApplied,
                    sampleSelectedBefore: tonePortamentoInstrumentStateBefore?.activeSampleIndex,
                    sampleSelectedAfter: sample.sampleIndex,
                    volumeColumn: hasVolumeColumnTonePortamento ? volumeColumn : nil
                )
                context.tonePortamentoEffects.append(diagnostic)
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                context.channelStates[channelIndex] = channelState
                continue
            }

            let eventIndex = context.events.count
            let loop = mixerLoop(from: sample)
            let envelopeMapping = mixerVolumeEnvelope(
                from: instrument.volumeEnvelope,
                timingConfig: timingConfig
            )
            let envelopeSemantics = volumeEnvelopeSemantics(
                from: instrument.volumeEnvelope,
                mapping: envelopeMapping
            )
            let scheduledNoteFrame = noteDelay?.delayedFrame ?? scheduledStartFrame
            let scheduledNoteTick = noteDelay?.applied == true ? noteDelay?.requestedTick ?? 0 : 0
            if scheduledNoteTick > 0 {
                // Column writes precede the existing delayed trigger/reset on its tick.
                if isOrdinaryVolumeColumnSlide(cell.volumeColumn) {
                    for tick in 1...scheduledNoteTick {
                        context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumn, cell: cell, source: source,
                            channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: timingConfig.speed,
                            timingPlan: timingPlan, state: &channelState, globalVolume: context.globalVolumeState.volumeValue))
                    }
                }
                // The established EDx path has resolved a real delayed trigger.
                // Reset at that trigger, rather than on an out-of-row delay.
                resetTremoloTriggerPhases(state: &channelState)
                if channelState.tremolo.activated, cell.instrument > 0 {
                    channelState.baseChannelVolume = 64
                    // FT2's delayed trigger replays an explicit volume value,
                    // not slide commands already handled by the column path.
                    if case .setVolume = volumeColumn.command {
                        _ = applyVolumeColumn(volumeColumn, to: &channelState)
                    }
                }
            }
            let setFinetuneOverride = hasSetFinetuneEffect && song.usesLinearFrequencyTable
                ? setFinetuneValue(from: cell)
                : nil
            var pitchMapping = playbackStepMapping(
                note: cell.note,
                sample: sample,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                timingConfig: timingConfig,
                finetuneOverride: setFinetuneOverride
            )
            if hasSetFinetuneEffect {
                context.setFinetuneEffects.append(setFinetuneDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    status: song.usesLinearFrequencyTable
                        ? setFinetuneStatus(for: pitchMapping)
                        : .unsupportedFrequencyTable,
                    activeVoiceFound: true,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    sampleFinetune: sample.finetune,
                    pitchMapping: pitchMapping
                ))
            }
            if hasFinePortamentoUpEffect {
                let result = finePortamentoUpAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                context.finePortamentoUpEffects.append(result.diagnostic)
            }
            if hasFinePortamentoDownEffect {
                let result = finePortamentoDownAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                context.finePortamentoDownEffects.append(result.diagnostic)
            }
            if hasXxyExtraFinePortamentoEffect {
                let result = extraFinePortamentoAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                context.extraFinePortamentoEffects.append(result.diagnostic)
            }
            let gain = songGain(
                outputChannelVolume: channelState.outputChannelVolume,
                globalVolume: context.globalVolumeState.volumeValue
            )
            let pan = channelState.pan
            if isNoteOnly && scheduledNoteTick == 0 {
                context.noteOnlyEventIndices.insert(eventIndex)
                if channelState.activeEventIndex == nil && channelState.keyOffWithoutVoice {
                    context.coldReleasedEventIndices.insert(eventIndex)
                }
            }
            context.events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: scheduledNoteTick,
                scheduledStartFrame: scheduledNoteFrame,
                sample: mixerSampleBuffer(for: sample, cache: &context.mixerSampleBuffers),
                gain: gain,
                pan: pan,
                playbackStep: pitchMapping.playbackStep,
                loop: loop,
                initialSourceFrame: sampleOffset.appliedOffsetFrames ?? 0,
                volumeEnvelope: envelopeMapping.envelope,
                panEnvelope: inertPanningEnvelopeClock(from: instrument.panningEnvelope, timingConfig: timingConfig)
            ))
            context.eventCoverage.recordScheduledNote(
                method: sampleSelection.method,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
            )
            if hasDeferredEffectCell || volumeColumn.deferred {
                context.eventCoverage.recordDeferredCellWithoutSkip()
            }
            channelState.activeEventIndex = eventIndex
            channelState.activeEventMappingIndex = context.eventMappings.count
            channelState.activeInstrumentIndex = instrumentIndex
            channelState.activeSampleIndex = sample.sampleIndex
            channelState.semanticInstrumentIndex = instrumentIndex
            channelState.semanticSampleIndex = sample.sampleIndex
            channelState.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
            channelState.activeSampleVolume = sample.volume
            channelState.triggeredSampleDefaultVolume = sampleVolumeRawEstimate(for: sample.volume)
            channelState.triggeredSampleDefaultPan = sample.panning
            channelState.activePlaybackStep = pitchMapping.playbackStep
            channelState.activeLinearPeriod = pitchMapping.linearPeriod
            channelState.vibratoOutputLinearPeriod = nil
            channelState.vibratoOutputAmigaPeriod = nil
            channelState.activeAmigaPeriod = pitchMapping.amigaPeriod
            channelState.activeSampleBaseSampleRate = sample.baseSampleRate
            channelState.activeSampleRelativeNote = sample.relativeNote
            channelState.activeSampleFinetune = pitchMapping.effectiveFinetune ?? sample.finetune
            channelState.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
            applyActiveVolumeEnvelopeMapping(envelopeMapping, to: &channelState)
            if !isNoteOnly {
                channelState.tonePortamentoTargetNote = nil
                channelState.tonePortamentoTargetLinearPeriod = nil
                channelState.tonePortamentoTargetAmigaPeriod = nil
                channelState.tonePortamentoTargetPlaybackStep = nil
            }
            channelState.volumeValueZeroedByAxy = false
            context.channelStates[channelIndex] = channelState
            context.eventMappings.append(PlaybackSongSyntheticEventMapping(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                sampleVolume: sample.volume,
                sampleVolumeRawEstimate: sampleVolumeRawEstimate(for: sample.volume),
                selectedSampleLength: sampleLength,
                sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                mappedSampleIndex: sampleSelection.mappedSampleIndex,
                mappedSampleValid: sampleSelection.mappedSampleValid,
                sampleSelectionMethod: sampleSelection.method,
                sampleSelectionStrategy: sampleSelection.method.rawValue,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                syntheticRow: syntheticRow,
                syntheticTick: scheduledNoteTick,
                eventIndex: eventIndex,
                loopMode: loop.mode,
                volumeColumn: volumeColumn,
                sampleOffset: sampleOffset,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffectCell,
                effectiveVolumeValue: channelState.outputChannelVolume,
                effectiveGlobalVolumeValue: context.globalVolumeState.volumeValue,
                effectiveGlobalVolumeMultiplier: context.globalVolumeState.multiplier,
                effectivePan: pan,
                volumeEnvelopeStatus: envelopeMapping.status,
                sourceVolumeEnvelopePointCount: envelopeMapping.sourcePointCount,
                mappedVolumeEnvelopePointCount: envelopeMapping.mappedPointCount,
                hasDeferredVolumeEnvelopeSustain: envelopeSemantics.sustainDeferred,
                hasDeferredVolumeEnvelopeLoop: envelopeSemantics.loopDeferred,
                hasDeferredVolumeEnvelopeFadeout: envelopeSemantics.fadeoutDeferred,
                volumeEnvelopeSemantics: envelopeSemantics,
                sampleBaseSampleRate: sample.baseSampleRate,
                sampleRelativeNote: sample.relativeNote,
                sampleFinetune: sample.finetune,
                outputSampleRate: pitchMapping.outputSampleRate,
                effectiveNoteValue: pitchMapping.effectiveNoteValue,
                effectiveNoteIndex: pitchMapping.effectiveNoteIndex,
                effectiveFinetune: pitchMapping.effectiveFinetune,
                linearPeriod: pitchMapping.linearPeriod,
                linearFrequency: pitchMapping.linearFrequency,
                amigaPeriod: pitchMapping.amigaPeriod,
                amigaFrequency: pitchMapping.amigaFrequency,
                finetuneStatus: pitchMapping.finetuneStatus,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                frequencyTableStatus: pitchMapping.frequencyTableStatus,
                linearFrequencyApplied: pitchMapping.linearFrequencyApplied,
                amigaFrequencyApplied: pitchMapping.amigaFrequencyApplied,
                amigaFrequencyDeferred: pitchMapping.amigaFrequencyDeferred,
                playbackStep: pitchMapping.playbackStep,
                pitchMappingApplied: pitchMapping.applied,
                pitchMappingUsedNeutralStep: pitchMapping.usedNeutralStep
            ))
            if hasLxxSetEnvelopePosition {
                context.envelopePositionEffects.append(envelopePositionDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledNoteFrame,
                    timingConfig: timingConfig,
                    channelState: channelState
                ))
            }
            if hasArpeggio {
                let diagnostic = handleArpeggio(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    includeTickZeroUpdate: false
                )
                context.arpeggioEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasPortamentoSlide {
                let diagnostic = handlePortamentoSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState
                )
                context.portamentoSlideEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibrato || hasVibratoVolumeSlide {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    restoreAtRowEnd: restoreVibratoAtRowEnd,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if let noteDelay, noteDelay.applied {
                context.noteDelayEffects.append(noteDelayDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    originalFrame: scheduledStartFrame,
                    eventIndex: eventIndex
                ) ?? noteDelay)
            }
            if hasRetriggerEffect {
                _ = handleRetrigger(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    volumeColumn: volumeColumn,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    globalVolumeState: context.globalVolumeState,
                    channelState: &channelState,
                    events: &context.events,
                    eventMappings: &context.eventMappings,
                    retriggerEffects: &context.retriggerEffects,
                    eventCoverage: &context.eventCoverage
                )
            }
            if hasNoteCutEffect {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &context.noteCutEffects
                )
            }
            if hasKxxKeyOff {
                handleKxxKeyOff(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    volumeColumn: volumeColumn,
                    channelState: &channelState,
                    events: &context.events,
                    keyOffEvents: &context.keyOffEvents,
                    voiceStateUpdates: &context.voiceStateUpdates,
                    globalVolume: context.globalVolumeState.volumeValue,
                    eventMappings: &context.eventMappings,
                    ignoredCells: &context.ignoredCells,
                    deferredCellFields: &context.deferredCellFields,
                    eventCoverage: &context.eventCoverage
                )
            }
            context.channelStates[channelIndex] = channelState
        }
        // Plan ordinary column slides and 6xy/tremolo after all tick-zero writers.
        // A later channel's Gxx must not see a future slide or tremolo value.
        for channelIndex in row.cells.indices {
            let cell = row.cells[channelIndex]
            let columnSlide = isOrdinaryVolumeColumnSlide(cell.volumeColumn)
                ? PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn) : nil
            if columnSlide != nil {
                if cell.effectType == 0x0A || cell.effectType == 0x05 {
                    context.voiceStateUpdates.append(contentsOf: applyEffectColumnVolumeSlide(
                        from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        timingConfig: timingConfig, timingPlan: timingPlan,
                        channelState: &context.channelStates[channelIndex], globalVolumeValue: context.globalVolumeState.volumeValue,
                        volumeColumnSlide: columnSlide))
                } else if cell.effectType != 0x06 && cell.effectType != 0x07 && timingConfig.speed > 1 {
                    var firstTick = 1
                    if cell.effectType == 0x0E && cell.effectParam >> 4 == 0x0D,
                       let eventIndex = context.channelStates[channelIndex].activeEventIndex,
                       context.events[eventIndex].row == syntheticRow {
                        firstTick = max(1, context.events[eventIndex].tick + 1)
                    }
                    for tick in firstTick..<timingConfig.speed {
                        context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(columnSlide, cell: cell, source: source,
                            channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: timingConfig.speed,
                            timingPlan: timingPlan, state: &context.channelStates[channelIndex],
                            globalVolume: context.globalVolumeState.volumeValue))
                    }
                }
            }
            context.voiceStateUpdates.append(contentsOf: apply6xyVolumeSlide(
                from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                timingConfig: timingConfig, timingPlan: timingPlan,
                channelState: &context.channelStates[channelIndex], globalVolumeValue: context.globalVolumeState.volumeValue,
                volumeColumnSlide: columnSlide
            ))
            advanceTremoloVibratoObserver(cell: cell, rowSpeed: timingConfig.speed,
                                         state: &context.channelStates[channelIndex])
            context.voiceStateUpdates.append(contentsOf: applyTremolo(
                cell: cell, source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, timingConfig: timingConfig,
                timingPlan: timingPlan, globalVolume: context.globalVolumeState.volumeValue,
                state: &context.channelStates[channelIndex], volumeColumnSlide: columnSlide
            ))
        }
        if timingConfig.speed > 1 {
            for tick in 1..<timingConfig.speed {
                for channelIndex in row.cells.indices where row.cells[channelIndex].effectType == 0x11 {
                    // Cold H00 has no publication. Seeded replay enters G12 unchanged.
                    guard row.cells[channelIndex].effectParam != 0 || context.channelStates[channelIndex].globalVolumeSlideMemory != nil else { continue }
                    context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSlide(
                        from: row.cells[channelIndex], source: source, sourceChannelIndex: channelIndex,
                        syntheticRow: syntheticRow, syntheticTick: tick,
                        scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                        channelStates: context.channelStates, globalVolumeState: &context.globalVolumeState))
                }
            }
        }
        return PlaybackSongSyntheticRowDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            cellCount: row.cells.count,
            emittedEventCount: context.events.count - eventStartCount,
            ignoredCellCount: context.ignoredCells.count - ignoredStartCount
        )
    }

}
