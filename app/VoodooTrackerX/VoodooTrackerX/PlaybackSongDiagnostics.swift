import Foundation

struct PlaybackSongSyntheticDiagnostics: Equatable {
    let requestedStartOrderIndex: Int
    let requestedOrderCount: Int
    let sampleRate: Double
    let initialSpeed: Int
    let initialBPM: Int
    let usesLinearFrequencyTable: Bool
    let syntheticRowCount: Int
    let adaptedOrders: [PlaybackSongSyntheticOrderDiagnostic]
    let rowMappings: [PlaybackSongSyntheticRowMapping]
    let rowTiming: [PlaybackSongSyntheticRowTimingDiagnostic]
    let timingChanges: [PlaybackSongSyntheticTimingChangeDiagnostic]
    let traversalDiagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
    let traversalPathLength: Int
    let traversalStopReason: PlaybackSongSyntheticTraversalStopReason
    let traversalGuardHit: Bool
    let effectCommandDiagnostics: [PlaybackSongSyntheticEffectCommandDiagnostic]
    let rowDiagnostics: [PlaybackSongSyntheticRowDiagnostic]
    let volumeColumnMappings: [PlaybackSongSyntheticVolumeColumnMapping]
    let voiceStateUpdates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    let sampleOffsetEffects: [PlaybackSongSyntheticSampleOffsetDiagnostic]
    let setFinetuneEffects: [PlaybackSongSyntheticSetFinetuneDiagnostic]
    let noteCutEffects: [PlaybackSongSyntheticNoteCutDiagnostic]
    let noteDelayEffects: [PlaybackSongSyntheticNoteDelayDiagnostic]
    let retriggerEffects: [PlaybackSongSyntheticRetriggerDiagnostic]
    let tonePortamentoEffects: [PlaybackSongSyntheticTonePortamentoDiagnostic]
    let portamentoSlideEffects: [PlaybackSongSyntheticPortamentoSlideDiagnostic]
    let finePortamentoUpEffects: [PlaybackSongSyntheticFinePortamentoUpDiagnostic]
    let finePortamentoDownEffects: [PlaybackSongSyntheticFinePortamentoDownDiagnostic]
    let arpeggioEffects: [PlaybackSongSyntheticArpeggioDiagnostic]
    let vibratoControlEffects: [PlaybackSongSyntheticVibratoControlDiagnostic]
    let vibratoEffects: [PlaybackSongSyntheticVibratoDiagnostic]
    let keyOffEvents: [PlaybackSongSyntheticKeyOffDiagnostic]
    let eventMappings: [PlaybackSongSyntheticEventMapping]
    let ignoredCells: [PlaybackSongSyntheticIgnoredCell]
    let deferredCellFields: [PlaybackSongSyntheticDeferredCellField]
    let eventCoverage: PlaybackSongSyntheticEventCoverageSummary

    var emittedRowCount: Int {
        rowMappings.count
    }

    var emittedEventCount: Int {
        eventMappings.count
    }

    var ignoredCellCount: Int {
        ignoredCells.count
    }

    var emptyOrSkippedRowCount: Int {
        rowDiagnostics.filter { $0.emittedEventCount == 0 }.count
    }

    var ignoredEffectFieldCount: Int {
        deferredCellFields.filter { $0.field == .effect }.count
    }

    var ignoredVolumeColumnFieldCount: Int {
        deferredCellFields.filter { $0.field == .volumeColumn }.count
    }

    var sampleOffsetEffectCount: Int {
        sampleOffsetEffects.count
    }

    var setFinetuneEffectCount: Int {
        setFinetuneEffects.count
    }

    var noteCutEffectCount: Int {
        noteCutEffects.count
    }

    var noteDelayEffectCount: Int {
        noteDelayEffects.count
    }

    var retriggerEffectCount: Int {
        retriggerEffects.count
    }

    var tonePortamentoEffectCount: Int {
        tonePortamentoEffects.count
    }

    var portamentoSlideEffectCount: Int {
        portamentoSlideEffects.count
    }

    var finePortamentoUpEffectCount: Int {
        finePortamentoUpEffects.count
    }

    var finePortamentoDownEffectCount: Int {
        finePortamentoDownEffects.count
    }

    var arpeggioEffectCount: Int {
        arpeggioEffects.count
    }

    var vibratoEffectCount: Int {
        vibratoEffects.count
    }

    var vibratoControlEffectCount: Int {
        vibratoControlEffects.count
    }

    var traversalHazardSummary: PlaybackSongSyntheticTraversalHazardSummary {
        PlaybackSongSyntheticTraversalHazardSummary(effectCommandDiagnostics: effectCommandDiagnostics)
    }

    var traversalSummary: PlaybackSongSyntheticTraversalSummary {
        PlaybackSongSyntheticTraversalSummary(
            pathLength: traversalPathLength,
            stopReason: traversalStopReason,
            guardHit: traversalGuardHit,
            diagnostics: traversalDiagnostics
        )
    }
}

enum PlaybackSongSyntheticSkipReason: String, Equatable, Hashable {
    case emptyCell = "empty_cell"
    case noteOffKeyOffOnly = "note_off_key_off_only"
    case invalidNote = "invalid_note"
    case missingInstrument = "missing_instrument"
    case unknownInstrument = "unknown_instrument"
    case instrumentHasNoPlayableSample = "instrument_has_no_playable_sample"
    case samplePCMEmpty = "sample_pcm_empty"
    case sampleOffsetOutOfRange = "sample_offset_out_of_range"
    case unsupportedSampleMapKeymapBehavior = "unsupported_sample_map_keymap_behavior"
    case noSelectedSampleForNote = "no_selected_sample_for_note"
    case eventOutsideBoundedRowRange = "event_outside_bounded_row_range"
    case eventCapacityLimit = "event_capacity_limit"
    case cMixerVoiceCapacityLimit = "c_mixer_voice_capacity_limit"
    case unsupportedDeferredEffectInteraction = "unsupported_deferred_effect_interaction"
    case instrumentOnly = "instrument_only"
    case unknown = "unknown"
}

enum PlaybackSongSyntheticSampleSelectionMethod: String, Equatable {
    case sampleMap = "sample_map"
    case firstPlayableFallback = "first_playable_fallback"
    case fallbackAfterInvalidMap = "fallback_after_invalid_map"
    case skippedNoValidSample = "skipped_no_valid_sample"
}

struct PlaybackSongSyntheticSkipReasonCount: Equatable {
    let reason: PlaybackSongSyntheticSkipReason
    let count: Int
}

struct PlaybackSongSyntheticEventCoverageSummary: Equatable {
    let totalCellsVisited: Int
    let emptyCells: Int
    let normalNoteCells: Int
    let noteOffCells: Int
    let invalidNoteCells: Int
    let instrumentOnlyCells: Int
    let noteWithInstrumentCells: Int
    let noteWithMissingOrZeroInstrumentCells: Int
    let scheduledNoteEvents: Int
    let skippedNoteEvents: Int
    let skippedNoteOffEventsNoActiveVoice: Int
    let ignoredOrDeferredCells: Int
    let sampleMapSelectionEvents: Int
    let firstPlayableSampleFallbackEvents: Int
    let fallbackAfterInvalidSampleMapEvents: Int
    let skippedNoValidSampleEvents: Int
    let sampleMapKeymapDeferredEvents: Int
    let eventOutsideBoundedRowRangeCount: Int
    let eventCapacityLimitCount: Int
    let cMixerVoiceCapacityLimitCount: Int
    let skipReasonCounts: [PlaybackSongSyntheticSkipReasonCount]
}

extension PlaybackSongSyntheticEventCoverageSummary {
    func reportingCMixerVoiceCapacityRejections(_ rejectedCount: Int) -> PlaybackSongSyntheticEventCoverageSummary {
        let safeRejectedCount = max(0, rejectedCount)
        guard safeRejectedCount > 0 else {
            return self
        }
        return PlaybackSongSyntheticEventCoverageSummary(
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
            cMixerVoiceCapacityLimitCount: cMixerVoiceCapacityLimitCount + safeRejectedCount,
            skipReasonCounts: mergingSkipReason(.cMixerVoiceCapacityLimit, count: safeRejectedCount)
        )
    }

    private func mergingSkipReason(
        _ reason: PlaybackSongSyntheticSkipReason,
        count: Int
    ) -> [PlaybackSongSyntheticSkipReasonCount] {
        var merged = skipReasonCounts.reduce(into: [PlaybackSongSyntheticSkipReason: Int]()) { partialResult, item in
            partialResult[item.reason, default: 0] += item.count
        }
        merged[reason, default: 0] += count
        return merged
            .map { PlaybackSongSyntheticSkipReasonCount(reason: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.reason.rawValue < rhs.reason.rawValue
            }
    }
}

extension PlaybackSongSyntheticDiagnostics {
    func replacingEventCoverage(
        _ eventCoverage: PlaybackSongSyntheticEventCoverageSummary
    ) -> PlaybackSongSyntheticDiagnostics {
        PlaybackSongSyntheticDiagnostics(
            requestedStartOrderIndex: requestedStartOrderIndex,
            requestedOrderCount: requestedOrderCount,
            sampleRate: sampleRate,
            initialSpeed: initialSpeed,
            initialBPM: initialBPM,
            usesLinearFrequencyTable: usesLinearFrequencyTable,
            syntheticRowCount: syntheticRowCount,
            adaptedOrders: adaptedOrders,
            rowMappings: rowMappings,
            rowTiming: rowTiming,
            timingChanges: timingChanges,
            traversalDiagnostics: traversalDiagnostics,
            traversalPathLength: traversalPathLength,
            traversalStopReason: traversalStopReason,
            traversalGuardHit: traversalGuardHit,
            effectCommandDiagnostics: effectCommandDiagnostics,
            rowDiagnostics: rowDiagnostics,
            volumeColumnMappings: volumeColumnMappings,
            voiceStateUpdates: voiceStateUpdates,
            sampleOffsetEffects: sampleOffsetEffects,
            setFinetuneEffects: setFinetuneEffects,
            noteCutEffects: noteCutEffects,
            noteDelayEffects: noteDelayEffects,
            retriggerEffects: retriggerEffects,
            tonePortamentoEffects: tonePortamentoEffects,
            portamentoSlideEffects: portamentoSlideEffects,
            finePortamentoUpEffects: finePortamentoUpEffects,
            finePortamentoDownEffects: finePortamentoDownEffects,
            arpeggioEffects: arpeggioEffects,
            vibratoControlEffects: vibratoControlEffects,
            vibratoEffects: vibratoEffects,
            keyOffEvents: keyOffEvents,
            eventMappings: eventMappings,
            ignoredCells: ignoredCells,
            deferredCellFields: deferredCellFields,
            eventCoverage: eventCoverage
        )
    }
}

extension PlaybackSongSyntheticPlan {
    func replacingEventCoverage(_ eventCoverage: PlaybackSongSyntheticEventCoverageSummary) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: pattern,
            diagnostics: diagnostics.replacingEventCoverage(eventCoverage)
        )
    }
}

struct PlaybackSongSyntheticOrderDiagnostic: Equatable {
    enum Status: Equatable {
        case adapted
        case invalidOrder
        case missingPattern
    }

    let requestedOrderIndex: Int
    let patternIndex: Int?
    let syntheticStartRow: Int
    let rowCount: Int
    let status: Status
}

struct PlaybackSongSyntheticRowMapping: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
}

struct PlaybackSongSyntheticRowDiagnostic: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let cellCount: Int
    let emittedEventCount: Int
    let ignoredCellCount: Int
}

struct PlaybackSongSyntheticRowTimingDiagnostic: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowEndExactFrame: Double
    let rowStartFrame: Int
    let rowDurationFrames: Int
    let effectiveSpeed: Int
    let effectiveBPM: Int
}

struct PlaybackSongSyntheticKeyOffDiagnostic: Equatable {
    enum Reason: Equatable {
        case releasedActiveVoice
        case noActiveVoice
        case outOfRowNoOp
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8?
    let effectParam: UInt8?
    let detected: Bool
    let releaseFrame: Int?
    let scheduledFrame: Int?
    let applied: Bool
    let deferred: Bool
    let reason: Reason
    let requestedTick: Int
    let rowSpeed: Int
    let rowBPM: Int
    let activeVoiceFound: Bool
    let activeVoiceReleased: Bool
    let activeEventIndex: Int?
}

struct PlaybackSongSyntheticTimingChangeDiagnostic: Equatable {
    enum Kind: Equatable {
        case speed
        case bpm
        case ignoredF00
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let effectType: UInt8
    let effectParam: UInt8
    let rowStartFrame: Int
    let appliesToSyntheticRowAfter: Int
    let kind: Kind
    let applied: Bool
    let speedBefore: Int
    let bpmBefore: Int
    let speedAfter: Int
    let bpmAfter: Int
}

enum PlaybackSongSyntheticTraversalStopReason: String, Equatable {
    case notStarted = "not_started"
    case selectedRangeEnd = "selected_range_end"
    case songEnd = "song_end"
    case invalidOrder = "invalid_order"
    case missingPattern = "missing_pattern"
    case outOfRange = "out_of_range"
    case traversalGuardHit = "traversal_guard_hit"
}

struct PlaybackSongSyntheticTraversalDiagnostic: Equatable {
    enum Kind: String, Equatable {
        case dxxPatternBreak = "traversal_dxx"
        case bxxPositionJump = "traversal_bxx"
        case e6xPatternLoop = "traversal_e6x"
    }

    enum Status: String, Equatable {
        case applied
        case deferred
        case invalidTarget = "invalid_target"
        case outOfRange = "out_of_range"
        case loopStartMarked = "loop_start_marked"
        case loopTaken = "loop_taken"
        case missingLoopStart = "missing_loop_start"
        case loopLimitHit = "loop_limit_hit"
    }

    let kind: Kind
    let status: Status
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let effectType: UInt8
    let effectParam: UInt8
    let targetOrderIndex: Int?
    let targetPatternIndex: Int?
    let targetRowIndex: Int?
    let nextOrderIndex: Int?
    let loopStartRowIndex: Int?
    let loopRemaining: Int?
    let loopLimit: Int?
    let combinedWithBxx: Bool
    let combinedWithDxx: Bool
    let policy: String

    var detected: Bool {
        true
    }

    var applied: Bool {
        switch status {
        case .applied, .loopStartMarked, .loopTaken:
            return true
        case .deferred, .invalidTarget, .outOfRange, .missingLoopStart, .loopLimitHit:
            return false
        }
    }

    var invalidTarget: Bool {
        status == .invalidTarget
    }

    var outOfRange: Bool {
        status == .outOfRange
    }

    var loopStartMarked: Bool {
        status == .loopStartMarked
    }

    var loopTaken: Bool {
        status == .loopTaken
    }

    var missingLoopStart: Bool {
        status == .missingLoopStart
    }

    var loopLimitHit: Bool {
        status == .loopLimitHit
    }
}

struct PlaybackSongSyntheticTraversalSummary: Equatable {
    static let firstDiagnosticLimit = 10

    let pathLength: Int
    let stopReason: PlaybackSongSyntheticTraversalStopReason
    let guardHit: Bool
    let appliedTraversalCount: Int
    let dxxDetectedCount: Int
    let dxxAppliedCount: Int
    let dxxInvalidTargetCount: Int
    let dxxOutOfRangeCount: Int
    let bxxDetectedCount: Int
    let bxxAppliedCount: Int
    let bxxOutOfRangeCount: Int
    let e6xDetectedCount: Int
    let e6xLoopStartCount: Int
    let e6xLoopTakenCount: Int
    let e6xMissingStartCount: Int
    let e6xLoopLimitHitCount: Int
    let firstDiagnostics: [PlaybackSongSyntheticTraversalDiagnostic]

    init(
        pathLength: Int,
        stopReason: PlaybackSongSyntheticTraversalStopReason,
        guardHit: Bool,
        diagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
    ) {
        self.pathLength = pathLength
        self.stopReason = stopReason
        self.guardHit = guardHit
        appliedTraversalCount = diagnostics.filter(\.applied).count
        dxxDetectedCount = diagnostics.filter { $0.kind == .dxxPatternBreak }.count
        dxxAppliedCount = diagnostics.filter { $0.kind == .dxxPatternBreak && $0.applied }.count
        dxxInvalidTargetCount = diagnostics.filter { $0.kind == .dxxPatternBreak && $0.invalidTarget }.count
        dxxOutOfRangeCount = diagnostics.filter { $0.kind == .dxxPatternBreak && $0.outOfRange }.count
        bxxDetectedCount = diagnostics.filter { $0.kind == .bxxPositionJump }.count
        bxxAppliedCount = diagnostics.filter { $0.kind == .bxxPositionJump && $0.applied }.count
        bxxOutOfRangeCount = diagnostics.filter { $0.kind == .bxxPositionJump && $0.outOfRange }.count
        e6xDetectedCount = diagnostics.filter { $0.kind == .e6xPatternLoop }.count
        e6xLoopStartCount = diagnostics.filter { $0.kind == .e6xPatternLoop && $0.loopStartMarked }.count
        e6xLoopTakenCount = diagnostics.filter { $0.kind == .e6xPatternLoop && $0.loopTaken }.count
        e6xMissingStartCount = diagnostics.filter { $0.kind == .e6xPatternLoop && $0.missingLoopStart }.count
        e6xLoopLimitHitCount = diagnostics.filter { $0.kind == .e6xPatternLoop && $0.loopLimitHit }.count
        firstDiagnostics = Array(diagnostics.prefix(Self.firstDiagnosticLimit))
    }
}

struct PlaybackSongSyntheticEffectCommandDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case ignoredNoOp
        case deferredUnsupported
        case invalidTarget
        case outOfRange
        case missingLoopStart
        case loopLimitHit
        case unknown
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let effectType: UInt8
    let effectParam: UInt8
    let decodedLabel: String
    let status: Status
    let isTraversalHazard: Bool

    var isBxxPositionJump: Bool {
        effectType == 0x0B
    }

    var isDxxPatternBreak: Bool {
        effectType == 0x0D
    }

    var isEExPatternDelay: Bool {
        effectType == 0x0E && ((effectParam >> 4) & 0x0F) == 0x0E
    }

    var isE6xPatternLoop: Bool {
        effectType == 0x0E && ((effectParam >> 4) & 0x0F) == 0x06
    }

    var isE9xRetrigger: Bool {
        effectType == 0x0E && ((effectParam >> 4) & 0x0F) == 0x09
    }

    var isECxNoteCut: Bool {
        effectType == 0x0E && ((effectParam >> 4) & 0x0F) == 0x0C
    }

    var isEDxNoteDelay: Bool {
        effectType == 0x0E && ((effectParam >> 4) & 0x0F) == 0x0D
    }

    var isFxxTimingChange: Bool {
        effectType == 0x0F
    }

    var isCxxSetVolume: Bool {
        effectType == 0x0C
    }

    var is8xxSetPanning: Bool {
        effectType == 0x08
    }

    var isAxyVolumeSlide: Bool {
        effectType == 0x0A
    }

    var isHxyGlobalVolumeSlide: Bool {
        effectType == 0x11
    }

    var isGxxSetGlobalVolume: Bool {
        effectType == 0x10
    }

    var isPitchModulationDiagnostic: Bool {
        switch effectType {
        case 0x00:
            return effectParam != 0
        case 0x01...0x07:
            return true
        default:
            return false
        }
    }
}

enum PlaybackSongSyntheticVoiceStateUpdateSource: Equatable {
    case volumeColumn
    case effectColumn
    case instrumentState
}

enum PlaybackSongSyntheticVoiceStateUpdateStatus: Equatable {
    case applied
    case ignoredNoOp
    case deferredUnsupported
}

enum PlaybackSongSyntheticVoiceStateUpdateCommand: Equatable {
    case volumeColumn(PlaybackSongSyntheticVolumeColumnCommand)
    case instrumentDefaultVolume(value: Int)
    case cxxSetVolume(value: Int)
    case effect8xxSetPanning(value: Int)
    case axyVolumeSlide(up: Int, down: Int)
    case gxxSetGlobalVolume(value: Int)
    case hxyGlobalVolumeSlide(up: Int, down: Int)
    case eaxFineVolumeSlideUp(amount: Int)
    case ebxFineVolumeSlideDown(amount: Int)
    case effect6xyVolumeSlide(up: Int, down: Int)

    var label: String {
        switch self {
        case let .volumeColumn(command):
            return command.name
        case .instrumentDefaultVolume:
            return "instrument default volume"
        case .cxxSetVolume:
            return "Cxx set volume"
        case .effect8xxSetPanning:
            return "8xx set panning"
        case .axyVolumeSlide:
            return "Axy volume slide"
        case .gxxSetGlobalVolume:
            return "Gxx set global volume"
        case .hxyGlobalVolumeSlide:
            return "Hxy global volume slide"
        case .eaxFineVolumeSlideUp:
            return "EAx fine volume slide up"
        case .ebxFineVolumeSlideDown:
            return "EBx fine volume slide down"
        case .effect6xyVolumeSlide:
            return "6xy vibrato + volume slide"
        }
    }
}

enum PlaybackSongSyntheticGlobalVolumeSlideDirection: String, Equatable {
    case up
    case down
    case none
}

struct PlaybackSongSyntheticVoiceStateUpdateDiagnostic: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let scheduledFrame: Int
    let cellNote: UInt8
    let instrumentIndex: Int
    let commandSource: PlaybackSongSyntheticVoiceStateUpdateSource
    let command: PlaybackSongSyntheticVoiceStateUpdateCommand
    let rawVolumeColumn: UInt8?
    let effectType: UInt8?
    let effectParam: UInt8?
    let status: PlaybackSongSyntheticVoiceStateUpdateStatus
    let behavior: PlaybackSongSyntheticVolumeColumnBehavior?
    let targetChannelIndex: Int?
    let activeVoiceUpdated: Bool
    let activeEventIndex: Int?
    let effectiveVolumeBefore: Int?
    let effectiveVolumeAfter: Int?
    let effectivePanBefore: Float?
    let effectivePanAfter: Float?
    let globalVolumeBefore: Int?
    let globalVolumeAfter: Int?
    let globalVolumeMultiplierBefore: Float?
    let globalVolumeMultiplierAfter: Float?
    let globalVolumeSlideDirection: PlaybackSongSyntheticGlobalVolumeSlideDirection?
    let globalVolumeSlideAmount: Int?
    let globalVolumeSlideClamped: Bool?
    let globalVolumeSlideBothNibblesNonzero: Bool?
    let globalVolumeSlidePolicy: String?
    let volumeSlideRawUpNibble: Int?
    let volumeSlideRawDownNibble: Int?
    let volumeSlideBothNibblesNonzero: Bool?
    let volumeSlidePolicy: String?
    let volumeSlideClamped: Bool?
    let volumeSlideTick0Suppressed: Bool?
    let volumeSlideRowSpeed: Int?
    let gainBefore: Float?
    let gainAfter: Float?
    let panBefore: Float?
    let panAfter: Float?

    var applied: Bool {
        status == .applied
    }

    var deferred: Bool {
        status == .deferredUnsupported
    }

    var ignoredAsNoOp: Bool {
        status == .ignoredNoOp
    }

    var hasEmptyNote: Bool {
        cellNote == 0
    }
}

struct PlaybackSongSyntheticTraversalHazardSummary: Equatable {
    static let firstHazardLimit = 10

    let totalBxxPositionJump: Int
    let totalDxxPatternBreak: Int
    let totalE6xPatternLoop: Int
    let totalEExPatternDelay: Int
    let totalFxxSpeedBPM: Int
    let totalE9xRetrigger: Int
    let totalECxNoteCut: Int
    let totalEDxNoteDelay: Int
    let totalOtherECommands: Int
    let totalTraversalHazards: Int
    let likelyIgnoresStructureChangingBehavior: Bool
    let firstTraversalHazards: [PlaybackSongSyntheticEffectCommandDiagnostic]
    let eCommandSubtypeCounts: [PlaybackSongSyntheticECommandSubtypeCount]

    init(effectCommandDiagnostics: [PlaybackSongSyntheticEffectCommandDiagnostic]) {
        totalBxxPositionJump = effectCommandDiagnostics.filter { $0.isBxxPositionJump }.count
        totalDxxPatternBreak = effectCommandDiagnostics.filter { $0.isDxxPatternBreak }.count
        totalE6xPatternLoop = effectCommandDiagnostics.filter { $0.isE6xPatternLoop }.count
        totalEExPatternDelay = effectCommandDiagnostics.filter { $0.isEExPatternDelay }.count
        totalFxxSpeedBPM = effectCommandDiagnostics.filter { $0.isFxxTimingChange }.count
        totalE9xRetrigger = effectCommandDiagnostics.filter { $0.isE9xRetrigger }.count
        totalECxNoteCut = effectCommandDiagnostics.filter { $0.isECxNoteCut }.count
        totalEDxNoteDelay = effectCommandDiagnostics.filter { $0.isEDxNoteDelay }.count
        totalOtherECommands = effectCommandDiagnostics.filter {
            $0.effectType == 0x0E && !$0.isE6xPatternLoop && !$0.isE9xRetrigger && !$0.isEExPatternDelay && !$0.isECxNoteCut && !$0.isEDxNoteDelay
        }.count
        totalTraversalHazards = totalBxxPositionJump + totalDxxPatternBreak + totalE6xPatternLoop + totalEExPatternDelay
        likelyIgnoresStructureChangingBehavior = effectCommandDiagnostics.contains {
            $0.isTraversalHazard && $0.status == .deferredUnsupported
        }
        firstTraversalHazards = Array(effectCommandDiagnostics.filter { $0.isTraversalHazard }.prefix(Self.firstHazardLimit))
        eCommandSubtypeCounts = Self.eCommandSubtypeCounts(from: effectCommandDiagnostics)
    }

    private static func eCommandSubtypeCounts(
        from diagnostics: [PlaybackSongSyntheticEffectCommandDiagnostic]
    ) -> [PlaybackSongSyntheticECommandSubtypeCount] {
        var counts = [String: Int]()
        for diagnostic in diagnostics where diagnostic.effectType == 0x0E {
            counts[diagnostic.decodedLabel, default: 0] += 1
        }
        return counts
            .map { PlaybackSongSyntheticECommandSubtypeCount(label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.label < rhs.label
            }
    }
}

struct PlaybackSongSyntheticECommandSubtypeCount: Equatable {
    let label: String
    let count: Int
}

struct PlaybackSongSyntheticEffectMemorySource: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let effectType: UInt8
    let effectParam: UInt8
}

struct PlaybackSongSyntheticSampleOffsetDiagnostic: Equatable {
    enum Status: Equatable {
        case notPresent
        case applied
        case ignored900NoOp
        case outOfRangeSkipped
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let skipped: Bool
    let outOfRange: Bool
    let computedOffsetFrames: Int
    let appliedOffsetFrames: Int?
    let selectedSampleLength: Int?
    let effectMemoryReused: Bool
    let effectMemoryMissing: Bool
    let effectMemoryDeferred: Bool
    let memorySource: PlaybackSongSyntheticEffectMemorySource?
    let memoryUnavailableReason: String?
}

struct PlaybackSongSyntheticSetFinetuneDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noNoteDeferred
        case noActiveVoice
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let effectMemoryDeferred: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let finetuneNibble: Int
    let sampleFinetune: Int?
    let effectiveFinetune: Int?
    let linearPeriod: Double?
    let linearFrequency: Double?
    let playbackStep: Double?
    let rowSpeed: Int
    let rowBPM: Int
    let policy: String
}

struct PlaybackSongSyntheticNoteCutDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case outOfRowNoOp
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let outOfRow: Bool
    let requestedTick: Int
    let rowSpeed: Int
    let rowBPM: Int
    let scheduledFrame: Int?
    let activeEventIndex: Int?
}

struct PlaybackSongSyntheticNoteDelayDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noNoteDeferred
        case outOfRowNoOp
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let outOfRow: Bool
    let requestedTick: Int
    let rowSpeed: Int
    let rowBPM: Int
    let originalFrame: Int
    let delayedFrame: Int?
    let eventIndex: Int?
}

struct PlaybackSongSyntheticRetriggerDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case ignoredE90NoEffectMemory
        case noActiveVoice
        case outOfRowNoOp
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let outOfRow: Bool
    let activeVoiceFound: Bool
    let retriggerIntervalTicks: Int
    let rowSpeed: Int
    let rowBPM: Int
    let retriggerTicks: [Int]
    let retriggerFrames: [Int]
    let retriggerEventIndices: [Int]
    let replacedEventIndices: [Int]
    let activeEventIndexBefore: Int?
    let selectedSampleIndex: Int?
    let selectedSampleLength: Int?
    let initialSourceFrame: Int?
    let playbackStep: Double?
    let gain: Float?
    let pan: Float?
    let envelopePolicy: String
}

struct PlaybackSongSyntheticTonePortamentoStepUpdate: Equatable {
    let syntheticTick: Int
    let scheduledFrame: Int
    let linearPeriodBefore: Double
    let linearPeriodAfter: Double
    let playbackStepBefore: Double
    let playbackStepAfter: Double
    let reachedTarget: Bool
    let clamped: Bool

    init(
        syntheticTick: Int,
        scheduledFrame: Int,
        linearPeriodBefore: Double,
        linearPeriodAfter: Double,
        playbackStepBefore: Double,
        playbackStepAfter: Double,
        reachedTarget: Bool,
        clamped: Bool = false
    ) {
        self.syntheticTick = syntheticTick
        self.scheduledFrame = scheduledFrame
        self.linearPeriodBefore = linearPeriodBefore
        self.linearPeriodAfter = linearPeriodAfter
        self.playbackStepBefore = playbackStepBefore
        self.playbackStepAfter = playbackStepAfter
        self.reachedTarget = reachedTarget
        self.clamped = clamped
    }
}

struct PlaybackSongSyntheticTonePortamentoDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case noTarget
        case noSpeed
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let sameCellNote: Bool
    let noteTriggerEventCreated: Bool
    let voiceReplacement: Bool
    let samplePositionReset: Bool
    let instrumentStateUpdated: Bool
    let instrumentIndexBefore: Int?
    let instrumentIndexAfter: Int?
    let sampleSelectedBefore: Int?
    let sampleSelectedAfter: Int?
    let instrumentDefaultVolumeApplied: Bool
    let envelopeReset: Bool
    let envelopeResetModeled: Bool
    let channelVolumeBefore: Int?
    let channelVolumeAfter: Int?
    let gainBefore: Float?
    let gainAfter: Float?
    let noteTargetBefore: UInt8?
    let noteTargetAfter: UInt8?
    let audibleTransientExpected: Bool
    let cMixerReceivesNewVoice: Bool
    let cMixerReceivesOnlyStateUpdates: Bool
    let targetExistsBefore: Bool
    let targetExistsAfter: Bool
    let targetNote: UInt8?
    let targetLinearPeriod: Double?
    let targetPlaybackStep: Double?
    let currentLinearPeriodBefore: Double?
    let currentLinearPeriodAfter: Double?
    let currentPlaybackStepBefore: Double?
    let currentPlaybackStepAfter: Double?
    let portamentoSpeed: Int
    let rowSpeed: Int
    let rowBPM: Int
    let stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
    let policy: String
}

enum PlaybackSongSyntheticPortamentoSlideDirection: String, Equatable {
    case up
    case down
}

struct PlaybackSongSyntheticPortamentoSlideDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case zeroParamEffectMemoryDeferred
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let effectMemoryReused: Bool
    let effectMemoryMissing: Bool
    let effectMemoryDeferred: Bool
    let memorySource: PlaybackSongSyntheticEffectMemorySource?
    let memoryUnavailableReason: String?
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let direction: PlaybackSongSyntheticPortamentoSlideDirection
    let slideAmount: Int
    let currentLinearPeriodBefore: Double?
    let currentLinearPeriodAfter: Double?
    let currentPlaybackStepBefore: Double?
    let currentPlaybackStepAfter: Double?
    let rowSpeed: Int
    let rowBPM: Int
    let stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
    let clamped: Bool
    let policy: String
}

struct PlaybackSongSyntheticFinePortamentoUpDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case zeroAmountEffectMemoryDeferred
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let effectMemoryDeferred: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let fineAmount: Int
    let fineAmountNibble: Int
    let currentLinearPeriodBefore: Double?
    let currentLinearPeriodAfter: Double?
    let currentPlaybackStepBefore: Double?
    let currentPlaybackStepAfter: Double?
    let rowSpeed: Int
    let rowBPM: Int
    let scheduledFrame: Int?
    let appliedToInitialPlaybackStep: Bool
    let stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
    let clamped: Bool
    let policy: String
}

struct PlaybackSongSyntheticFinePortamentoDownDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case zeroAmountEffectMemoryDeferred
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let effectMemoryDeferred: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let fineAmount: Int
    let fineAmountNibble: Int
    let currentLinearPeriodBefore: Double?
    let currentLinearPeriodAfter: Double?
    let currentPlaybackStepBefore: Double?
    let currentPlaybackStepAfter: Double?
    let rowSpeed: Int
    let rowBPM: Int
    let scheduledFrame: Int?
    let appliedToInitialPlaybackStep: Bool
    let stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
    let clamped: Bool
    let policy: String
}

struct PlaybackSongSyntheticArpeggioDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let effectMemoryDeferred: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let xSemitoneOffset: Int
    let ySemitoneOffset: Int
    let currentLinearPeriodBefore: Double?
    let currentLinearPeriodAfter: Double?
    let currentPlaybackStepBefore: Double?
    let currentPlaybackStepAfter: Double?
    let rowSpeed: Int
    let rowBPM: Int
    let stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
    let policy: String
}

struct PlaybackSongSyntheticVibratoDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case noActiveVoice
        case zeroParamEffectMemoryDeferred
        case zeroSpeedOrDepthEffectMemoryDeferred
        case unsupportedFrequencyTable
        case outOfRange
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let vibratoSpeed: Int
    let vibratoDepth: Int
    let vibratoSpeedSource: String?
    let vibratoDepthSource: String?
    let vibratoControlValue: Int
    let vibratoWaveform: String
    let vibratoWaveformSource: String
    let effectMemoryReused: Bool
    let effectMemoryMissing: Bool
    let effectMemoryDeferred: Bool
    let vibratoSpeedMemorySource: PlaybackSongSyntheticEffectMemorySource?
    let vibratoDepthMemorySource: PlaybackSongSyntheticEffectMemorySource?
    let memoryUnavailableReason: String?
    let volumeSlideUp: Int?
    let volumeSlideDown: Int?
    let volumeSlideAmount: Int?
    let volumeSlideDirection: String?
    let phaseBefore: Double
    let phaseAfter: Double
    let currentLinearPeriodBefore: Double?
    let currentLinearPeriodAfter: Double?
    let currentPlaybackStepBefore: Double?
    let currentPlaybackStepAfter: Double?
    let rowSpeed: Int
    let rowBPM: Int
    let stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
    let policy: String
}

struct PlaybackSongSyntheticVibratoControlDiagnostic: Equatable {
    enum Status: Equatable {
        case stored
        case unsupportedWaveform
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let effectType: UInt8
    let effectParam: UInt8
    let status: Status
    let detected: Bool
    let applied: Bool
    let stored: Bool
    let deferred: Bool
    let ignoredAsNoOp: Bool
    let activeVoiceFound: Bool
    let activeEventIndex: Int?
    let activeEventMappingIndex: Int?
    let controlValue: Int
    let waveformID: Int
    let waveformName: String
    let retriggerSuppressed: Bool
    let unsupportedWaveform: Bool
    let affectsLaterVibrato: Bool
    let policy: String
}

struct PlaybackSongSyntheticEnvelopeSemanticsDiagnostic: Equatable {
    let envelopeEnabled: Bool
    let sourcePointCount: Int
    let mappedPointCount: Int
    let sustainEnabled: Bool
    let sustainApplied: Bool
    let sustainDeferred: Bool
    let sustainPointIndex: Int?
    let sustainTick: Int?
    let sustainFrame: Int?
    let loopEnabled: Bool
    let loopApplied: Bool
    let loopDeferred: Bool
    let loopStartPointIndex: Int?
    let loopEndPointIndex: Int?
    let loopStartTick: Int?
    let loopEndTick: Int?
    let loopStartFrame: Int?
    let loopEndFrame: Int?
    let keyOffEncountered: Bool
    let keyOffApplied: Bool
    let keyOffDeferred: Bool
    let keyOffSource: PlaybackPosition?
    let keyOffChannelIndex: Int?
    let keyOffSyntheticRow: Int?
    let keyOffSyntheticTick: Int?
    let releaseFrame: Int?
    let fadeoutValue: Int
    let fadeoutApplied: Bool
    let fadeoutDeferred: Bool
    let limitations: [String]

    func applyingKeyOff(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int,
        releaseFrame: Int
    ) -> PlaybackSongSyntheticEnvelopeSemanticsDiagnostic {
        PlaybackSongSyntheticEnvelopeSemanticsDiagnostic(
            envelopeEnabled: envelopeEnabled,
            sourcePointCount: sourcePointCount,
            mappedPointCount: mappedPointCount,
            sustainEnabled: sustainEnabled,
            sustainApplied: sustainApplied,
            sustainDeferred: sustainDeferred,
            sustainPointIndex: sustainPointIndex,
            sustainTick: sustainTick,
            sustainFrame: sustainFrame,
            loopEnabled: loopEnabled,
            loopApplied: loopApplied,
            loopDeferred: loopDeferred,
            loopStartPointIndex: loopStartPointIndex,
            loopEndPointIndex: loopEndPointIndex,
            loopStartTick: loopStartTick,
            loopEndTick: loopEndTick,
            loopStartFrame: loopStartFrame,
            loopEndFrame: loopEndFrame,
            keyOffEncountered: true,
            keyOffApplied: true,
            keyOffDeferred: false,
            keyOffSource: source,
            keyOffChannelIndex: channelIndex,
            keyOffSyntheticRow: syntheticRow,
            keyOffSyntheticTick: syntheticTick,
            releaseFrame: releaseFrame,
            fadeoutValue: fadeoutValue,
            fadeoutApplied: fadeoutValue > 0,
            fadeoutDeferred: false,
            limitations: limitations
        )
    }
}

struct PlaybackSongSyntheticEventMapping: Equatable {
    enum VolumeEnvelopeStatus: Equatable {
        case absent
        case disabled
        case invalidOrEmptyIgnored
        case mapped
    }

    enum FinetuneStatus: Equatable {
        case applied
        case deferred
    }

    enum FrequencyTableStatus: Equatable {
        case linearApplied
        case amigaTableDeferredNeutralFallback
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let sampleIndex: Int
    let sampleVolume: Float
    let sampleVolumeRawEstimate: Int
    let selectedSampleLength: Int
    let sampleMapKeymapPresent: Bool
    let mappedSampleIndex: Int?
    let mappedSampleValid: Bool
    let sampleSelectionMethod: PlaybackSongSyntheticSampleSelectionMethod
    let sampleSelectionStrategy: String
    let firstPlayableSampleFallbackUsed: Bool
    let sampleMapKeymapBehaviorDeferred: Bool
    let sampleMapKeymapMissingOrDeferred: Bool
    let effectType: UInt8
    let effectParam: UInt8
    let syntheticRow: Int
    let syntheticTick: Int
    let eventIndex: Int
    let loopMode: MixerSampleLoopMode
    let volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    let sampleOffset: PlaybackSongSyntheticSampleOffsetDiagnostic
    let hasIgnoredVolumeColumn: Bool
    let hasIgnoredEffect: Bool
    let effectiveVolumeValue: Int
    let effectiveGlobalVolumeValue: Int
    let effectiveGlobalVolumeMultiplier: Float
    let effectivePan: Float
    let volumeEnvelopeStatus: VolumeEnvelopeStatus
    let sourceVolumeEnvelopePointCount: Int
    let mappedVolumeEnvelopePointCount: Int
    let hasDeferredVolumeEnvelopeSustain: Bool
    let hasDeferredVolumeEnvelopeLoop: Bool
    let hasDeferredVolumeEnvelopeFadeout: Bool
    let volumeEnvelopeSemantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
    let sampleBaseSampleRate: Double
    let sampleRelativeNote: Int
    let sampleFinetune: Int
    let outputSampleRate: Double
    let effectiveNoteValue: Int?
    let effectiveNoteIndex: Int?
    let effectiveFinetune: Int?
    let linearPeriod: Double?
    let linearFrequency: Double?
    let finetuneStatus: FinetuneStatus
    let usesLinearFrequencyTable: Bool
    let frequencyTableStatus: FrequencyTableStatus
    let linearFrequencyApplied: Bool
    let amigaFrequencyDeferred: Bool
    let playbackStep: Double
    let pitchMappingApplied: Bool
    let pitchMappingUsedNeutralStep: Bool
}

struct PlaybackSongSyntheticIgnoredCell: Equatable {
    enum Reason: Equatable {
        case emptyNote
        case instrumentOnly
        case keyOff
        case invalidNote
        case missingInstrument
        case unknownInstrument
        case instrumentHasNoPlayableSample
        case samplePCMEmpty
        case sampleOffsetOutOfRange
        case noteDelayOutOfRow
        case noteDelayWithoutNote
        case noSelectedSampleForNote
        case unsupportedDeferredEffectInteraction
        case unknown
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let reason: Reason
    let skipReason: PlaybackSongSyntheticSkipReason
    let selectedSampleIndex: Int?
    let selectedSampleLength: Int?
    let selectedSampleLoopMode: MixerSampleLoopMode?
    let sampleMapKeymapPresent: Bool
    let mappedSampleIndex: Int?
    let mappedSampleValid: Bool
    let sampleSelectionMethod: PlaybackSongSyntheticSampleSelectionMethod
    let firstPlayableSampleFallbackUsed: Bool
    let sampleMapKeymapBehaviorDeferred: Bool
    let sampleMapKeymapMissingOrDeferred: Bool
    let sampleRelativeNote: Int?
    let sampleFinetune: Int?
    let sampleBaseSampleRate: Double?
    let sampleOffsetFrames: Int?
    let volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    let hasIgnoredVolumeColumn: Bool
    let hasIgnoredEffect: Bool
}

struct PlaybackSongSyntheticDeferredCellField: Equatable {
    enum Field: Equatable {
        case volumeColumn
        case effect
        case keyOff
        case volumeEnvelopeSustain
        case volumeEnvelopeLoop
        case volumeEnvelopeFadeout
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let volumeColumn: UInt8
    let volumeColumnDiagnostic: PlaybackSongSyntheticVolumeColumnDiagnostic
    let effectType: UInt8
    let effectParam: UInt8
    let field: Field
}
