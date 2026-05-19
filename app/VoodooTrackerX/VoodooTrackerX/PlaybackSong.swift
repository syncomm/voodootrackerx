import Foundation

struct PlaybackCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

struct PlaybackSample: Equatable {
    let instrumentIndex: Int
    let sampleIndex: Int
    let pcm: [Float]
    let volume: Float
    let relativeNote: Int
    let finetune: Int
    let baseSampleRate: Double
    let sampleLength: Int
    let loopStart: Int
    let loopLength: Int
    let loopType: Int

    init(
        instrumentIndex: Int,
        sampleIndex: Int,
        pcm: [Float],
        volume: Float,
        relativeNote: Int,
        finetune: Int,
        baseSampleRate: Double,
        sampleLength: Int? = nil,
        loopStart: Int = 0,
        loopLength: Int = 0,
        loopType: Int = 0
    ) {
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
        self.pcm = pcm
        self.volume = volume
        self.relativeNote = relativeNote
        self.finetune = finetune
        self.baseSampleRate = baseSampleRate
        self.sampleLength = sampleLength ?? pcm.count
        self.loopStart = loopStart
        self.loopLength = loopLength
        self.loopType = loopType
    }

    var isPlayable: Bool {
        !pcm.isEmpty && volume > 0
    }

    var loopRegion: PlaybackSampleLoopRegion {
        PlaybackSampleLoopRegion.clamped(
            sampleFrameCount: min(sampleLength, pcm.count),
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType
        )
    }
}

struct PlaybackEnvelopePoint: Equatable {
    let tick: Int
    let value: Int

    init(tick: Int, value: Int) {
        self.tick = max(0, tick)
        self.value = min(64, max(0, value))
    }

    var normalizedValue: Float {
        Float(value) / 64.0
    }
}

struct PlaybackVolumeEnvelope: Equatable {
    static let disabled = PlaybackVolumeEnvelope(
        enabled: false,
        points: [],
        sustainPointIndex: nil,
        loopStartPointIndex: nil,
        loopEndPointIndex: nil,
        typeFlags: 0,
        fadeout: 0
    )

    let enabled: Bool
    let points: [PlaybackEnvelopePoint]
    let sustainPointIndex: Int?
    let loopStartPointIndex: Int?
    let loopEndPointIndex: Int?
    let typeFlags: UInt8
    let fadeout: Int

    var sustainEnabled: Bool {
        (typeFlags & 0x02) != 0 && sustainPoint != nil
    }

    var loopEnabled: Bool {
        (typeFlags & 0x04) != 0 && loopStartPoint != nil && loopEndPoint != nil
    }

    var sustainPoint: PlaybackEnvelopePoint? {
        guard let sustainPointIndex,
              points.indices.contains(sustainPointIndex) else {
            return nil
        }
        return points[sustainPointIndex]
    }

    var loopStartPoint: PlaybackEnvelopePoint? {
        guard let loopStartPointIndex,
              points.indices.contains(loopStartPointIndex) else {
            return nil
        }
        return points[loopStartPointIndex]
    }

    var loopEndPoint: PlaybackEnvelopePoint? {
        guard let loopEndPointIndex,
              points.indices.contains(loopEndPointIndex) else {
            return nil
        }
        return points[loopEndPointIndex]
    }

    func value(at tick: Int) -> Float {
        guard enabled, !points.isEmpty else {
            return 1
        }
        let safeTick = max(0, tick)
        guard let first = points.first else {
            return 1
        }
        if safeTick <= first.tick {
            return first.normalizedValue
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]
            guard safeTick <= next.tick else {
                continue
            }
            let distance = max(1, next.tick - previous.tick)
            let progress = Float(safeTick - previous.tick) / Float(distance)
            return previous.normalizedValue + ((next.normalizedValue - previous.normalizedValue) * progress)
        }
        return points.last?.normalizedValue ?? 1
    }
}

struct PlaybackInstrument: Equatable {
    let index: Int
    let samples: [PlaybackSample]
    let volumeEnvelope: PlaybackVolumeEnvelope
    let noteSampleMap: [Int]?

    init(
        index: Int,
        samples: [PlaybackSample],
        volumeEnvelope: PlaybackVolumeEnvelope = .disabled,
        noteSampleMap: [Int]? = nil
    ) {
        self.index = index
        self.samples = samples
        self.volumeEnvelope = volumeEnvelope
        self.noteSampleMap = noteSampleMap?.count == 96 ? noteSampleMap : nil
    }

    var firstPlayableSample: PlaybackSample? {
        samples.first { $0.isPlayable }
    }

    var hasNoteSampleMap: Bool {
        noteSampleMap != nil
    }

    func mappedSampleIndex(forNote note: UInt8) -> Int? {
        guard (1...96).contains(note),
              let noteSampleMap else {
            return nil
        }
        return noteSampleMap[Int(note) - 1]
    }

    func sample(mappedSampleIndex: Int) -> PlaybackSample? {
        samples.first { $0.sampleIndex == mappedSampleIndex }
    }
}

struct PlaybackRow: Equatable {
    let index: Int
    let cells: [PlaybackCell]
}

struct PlaybackPattern: Equatable {
    let index: Int
    let rows: [PlaybackRow]

    var rowCount: Int {
        rows.count
    }
}

struct PlaybackOrderEntry: Equatable {
    let orderIndex: Int
    let patternIndex: Int
}

struct PlaybackPosition: Equatable {
    let orderIndex: Int
    let patternIndex: Int
    let rowIndex: Int
}

enum PlaybackEndBehavior: Equatable {
    case stopAtEnd
    case restartFromBeginning
}

enum PlaybackStepResult: Equatable {
    case advanced(PlaybackPosition)
    case ended(restartPosition: PlaybackPosition?)
}

struct PlaybackSong: Equatable {
    let title: String
    let orders: [PlaybackOrderEntry]
    let patternsByIndex: [Int: PlaybackPattern]
    let instrumentsByIndex: [Int: PlaybackInstrument]
    let restartOrderIndex: Int
    let endBehavior: PlaybackEndBehavior
    let initialTiming: PlaybackTiming
    let usesLinearFrequencyTable: Bool

    init(
        title: String,
        orders: [PlaybackOrderEntry],
        patternsByIndex: [Int: PlaybackPattern],
        instrumentsByIndex: [Int: PlaybackInstrument],
        restartOrderIndex: Int,
        endBehavior: PlaybackEndBehavior,
        initialTiming: PlaybackTiming = .xmDefault,
        usesLinearFrequencyTable: Bool = true
    ) {
        self.title = title
        self.orders = orders
        self.patternsByIndex = patternsByIndex
        self.instrumentsByIndex = instrumentsByIndex
        self.restartOrderIndex = restartOrderIndex
        self.endBehavior = endBehavior
        self.initialTiming = initialTiming
        self.usesLinearFrequencyTable = usesLinearFrequencyTable
    }

    var startPosition: PlaybackPosition? {
        position(orderIndex: 0, rowIndex: 0)
    }

    func pattern(for orderIndex: Int) -> PlaybackPattern? {
        guard orders.indices.contains(orderIndex) else {
            return nil
        }
        return patternsByIndex[orders[orderIndex].patternIndex]
    }

    func row(at position: PlaybackPosition) -> PlaybackRow? {
        guard let pattern = pattern(for: position.orderIndex),
              pattern.index == position.patternIndex,
              pattern.rows.indices.contains(position.rowIndex) else {
            return nil
        }
        return pattern.rows[position.rowIndex]
    }

    func sample(forInstrument instrumentIndex: Int) -> PlaybackSample? {
        guard instrumentIndex > 0 else {
            return nil
        }
        return instrumentsByIndex[instrumentIndex]?.firstPlayableSample
    }

    func instrument(forInstrument instrumentIndex: Int) -> PlaybackInstrument? {
        guard instrumentIndex > 0 else {
            return nil
        }
        return instrumentsByIndex[instrumentIndex]
    }

    func position(orderIndex: Int, rowIndex: Int) -> PlaybackPosition? {
        guard let pattern = pattern(for: orderIndex), !pattern.rows.isEmpty else {
            return nil
        }
        let safeRowIndex = min(max(0, rowIndex), pattern.rows.count - 1)
        return PlaybackPosition(orderIndex: orderIndex, patternIndex: pattern.index, rowIndex: safeRowIndex)
    }

    func position(patternIndex: Int, rowIndex: Int) -> PlaybackPosition? {
        guard let order = orders.first(where: { $0.patternIndex == patternIndex }) else {
            return nil
        }
        return position(orderIndex: order.orderIndex, rowIndex: rowIndex)
    }

    func position(after position: PlaybackPosition) -> PlaybackStepResult {
        guard let pattern = pattern(for: position.orderIndex),
              pattern.index == position.patternIndex else {
            return endResult()
        }

        let nextRowIndex = position.rowIndex + 1
        if nextRowIndex < pattern.rows.count {
            return .advanced(PlaybackPosition(orderIndex: position.orderIndex, patternIndex: pattern.index, rowIndex: nextRowIndex))
        }

        let nextOrderIndex = position.orderIndex + 1
        if let nextPosition = self.position(orderIndex: nextOrderIndex, rowIndex: 0) {
            return .advanced(nextPosition)
        }

        return endResult()
    }

    private func endResult() -> PlaybackStepResult {
        switch endBehavior {
        case .stopAtEnd:
            return .ended(restartPosition: nil)
        case .restartFromBeginning:
            return .ended(restartPosition: position(orderIndex: restartOrderIndex, rowIndex: 0) ?? startPosition)
        }
    }
}

struct PlaybackSongSyntheticPlan: Equatable {
    let timingConfig: SyntheticTrackerTimingConfig
    let pattern: SyntheticPattern
    let diagnostics: PlaybackSongSyntheticDiagnostics
}

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
    let effectCommandDiagnostics: [PlaybackSongSyntheticEffectCommandDiagnostic]
    let rowDiagnostics: [PlaybackSongSyntheticRowDiagnostic]
    let volumeColumnMappings: [PlaybackSongSyntheticVolumeColumnMapping]
    let voiceStateUpdates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    let sampleOffsetEffects: [PlaybackSongSyntheticSampleOffsetDiagnostic]
    let noteCutEffects: [PlaybackSongSyntheticNoteCutDiagnostic]
    let noteDelayEffects: [PlaybackSongSyntheticNoteDelayDiagnostic]
    let retriggerEffects: [PlaybackSongSyntheticRetriggerDiagnostic]
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

    var noteCutEffectCount: Int {
        noteCutEffects.count
    }

    var noteDelayEffectCount: Int {
        noteDelayEffects.count
    }

    var retriggerEffectCount: Int {
        retriggerEffects.count
    }

    var traversalHazardSummary: PlaybackSongSyntheticTraversalHazardSummary {
        PlaybackSongSyntheticTraversalHazardSummary(effectCommandDiagnostics: effectCommandDiagnostics)
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
            effectCommandDiagnostics: effectCommandDiagnostics,
            rowDiagnostics: rowDiagnostics,
            volumeColumnMappings: volumeColumnMappings,
            voiceStateUpdates: voiceStateUpdates,
            sampleOffsetEffects: sampleOffsetEffects,
            noteCutEffects: noteCutEffects,
            noteDelayEffects: noteDelayEffects,
            retriggerEffects: retriggerEffects,
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
    let rowStartFrame: Int
    let rowDurationFrames: Int
    let effectiveSpeed: Int
    let effectiveBPM: Int
}

struct PlaybackSongSyntheticKeyOffDiagnostic: Equatable {
    enum Reason: Equatable {
        case releasedActiveVoice
        case noActiveVoice
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let releaseFrame: Int?
    let applied: Bool
    let deferred: Bool
    let reason: Reason
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

struct PlaybackSongSyntheticEffectCommandDiagnostic: Equatable {
    enum Status: Equatable {
        case applied
        case ignoredNoOp
        case deferredUnsupported
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
}

enum PlaybackSongSyntheticVoiceStateUpdateSource: Equatable {
    case volumeColumn
    case effectColumn
}

enum PlaybackSongSyntheticVoiceStateUpdateStatus: Equatable {
    case applied
    case ignoredNoOp
    case deferredUnsupported
}

enum PlaybackSongSyntheticVoiceStateUpdateCommand: Equatable {
    case volumeColumn(PlaybackSongSyntheticVolumeColumnCommand)
    case cxxSetVolume(value: Int)
    case effect8xxSetPanning(value: Int)
    case axyVolumeSlide(up: Int, down: Int)
    case hxyGlobalVolumeSlide

    var label: String {
        switch self {
        case let .volumeColumn(command):
            return command.name
        case .cxxSetVolume:
            return "Cxx set volume"
        case .effect8xxSetPanning:
            return "8xx set panning"
        case .axyVolumeSlide:
            return "Axy volume slide"
        case .hxyGlobalVolumeSlide:
            return "Hxy global volume slide"
        }
    }
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
    let activeVoiceUpdated: Bool
    let activeEventIndex: Int?
    let effectiveVolumeBefore: Int?
    let effectiveVolumeAfter: Int?
    let effectivePanBefore: Float?
    let effectivePanAfter: Float?
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
        totalEExPatternDelay = effectCommandDiagnostics.filter { $0.isEExPatternDelay }.count
        totalFxxSpeedBPM = effectCommandDiagnostics.filter { $0.isFxxTimingChange }.count
        totalE9xRetrigger = effectCommandDiagnostics.filter { $0.isE9xRetrigger }.count
        totalECxNoteCut = effectCommandDiagnostics.filter { $0.isECxNoteCut }.count
        totalEDxNoteDelay = effectCommandDiagnostics.filter { $0.isEDxNoteDelay }.count
        totalOtherECommands = effectCommandDiagnostics.filter {
            $0.effectType == 0x0E && !$0.isE9xRetrigger && !$0.isEExPatternDelay && !$0.isECxNoteCut && !$0.isEDxNoteDelay
        }.count
        totalTraversalHazards = totalBxxPositionJump + totalDxxPatternBreak + totalEExPatternDelay
        likelyIgnoresStructureChangingBehavior = totalTraversalHazards > 0
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

enum PlaybackSongSyntheticVolumeColumnCommand: Equatable {
    case none
    case setVolume(value: Int)
    case volumeSlideDown(amount: Int)
    case volumeSlideUp(amount: Int)
    case fineVolumeSlideDown(amount: Int)
    case fineVolumeSlideUp(amount: Int)
    case setVibratoSpeed(amount: Int)
    case vibrato(amount: Int)
    case setPanning(value: Int)
    case panningSlideLeft(amount: Int)
    case panningSlideRight(amount: Int)
    case tonePortamento(amount: Int)
    case unsupported(rawValue: UInt8)

    var name: String {
        switch self {
        case .none:
            return "none"
        case .setVolume:
            return "setVolume"
        case .volumeSlideDown:
            return "volumeSlideDown"
        case .volumeSlideUp:
            return "volumeSlideUp"
        case .fineVolumeSlideDown:
            return "fineVolumeSlideDown"
        case .fineVolumeSlideUp:
            return "fineVolumeSlideUp"
        case .setVibratoSpeed:
            return "setVibratoSpeed"
        case .vibrato:
            return "vibrato"
        case .setPanning:
            return "setPanning"
        case .panningSlideLeft:
            return "panningSlideLeft"
        case .panningSlideRight:
            return "panningSlideRight"
        case .tonePortamento:
            return "tonePortamento"
        case .unsupported:
            return "unsupported"
        }
    }
}

enum PlaybackSongSyntheticVolumeColumnClassification: Equatable {
    case ignoredNoOp
    case supported
    case deferred
}

enum PlaybackSongSyntheticVolumeColumnSlideDirection: Equatable {
    case volumeDown
    case volumeUp
    case panningLeft
    case panningRight
}

enum PlaybackSongSyntheticVolumeColumnBehavior: Equatable {
    case rowLevelApproximation
}

struct PlaybackSongSyntheticVolumeColumnDiagnostic: Equatable {
    let rawValue: UInt8
    let command: PlaybackSongSyntheticVolumeColumnCommand
    let classification: PlaybackSongSyntheticVolumeColumnClassification
    let applied: Bool
    let ignoredAsEmptyOrNoOp: Bool
    let deferred: Bool
    let appliedVolumeValue: Int?
    let appliedGainMultiplier: Float?
    let appliedPanningValue: Int?
    let appliedPan: Float?
    let slideAmount: Int?
    let slideDirection: PlaybackSongSyntheticVolumeColumnSlideDirection?
    let effectiveVolumeBefore: Int?
    let effectiveVolumeAfter: Int?
    let effectivePanBefore: Float?
    let effectivePanAfter: Float?
    let behavior: PlaybackSongSyntheticVolumeColumnBehavior?

    func withAppliedState(
        appliedVolumeValue: Int? = nil,
        appliedGainMultiplier: Float? = nil,
        appliedPanningValue: Int? = nil,
        appliedPan: Float? = nil,
        effectiveVolumeBefore: Int? = nil,
        effectiveVolumeAfter: Int? = nil,
        effectivePanBefore: Float? = nil,
        effectivePanAfter: Float? = nil,
        behavior: PlaybackSongSyntheticVolumeColumnBehavior? = nil
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        PlaybackSongSyntheticVolumeColumnDiagnostic(
            rawValue: rawValue,
            command: command,
            classification: classification,
            applied: applied,
            ignoredAsEmptyOrNoOp: ignoredAsEmptyOrNoOp,
            deferred: deferred,
            appliedVolumeValue: appliedVolumeValue ?? self.appliedVolumeValue,
            appliedGainMultiplier: appliedGainMultiplier ?? self.appliedGainMultiplier,
            appliedPanningValue: appliedPanningValue ?? self.appliedPanningValue,
            appliedPan: appliedPan ?? self.appliedPan,
            slideAmount: slideAmount,
            slideDirection: slideDirection,
            effectiveVolumeBefore: effectiveVolumeBefore ?? self.effectiveVolumeBefore,
            effectiveVolumeAfter: effectiveVolumeAfter ?? self.effectiveVolumeAfter,
            effectivePanBefore: effectivePanBefore ?? self.effectivePanBefore,
            effectivePanAfter: effectivePanAfter ?? self.effectivePanAfter,
            behavior: behavior ?? self.behavior
        )
    }
}

enum PlaybackSongVolumeColumnDecoder {
    static func decode(_ rawValue: UInt8) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        switch rawValue {
        case 0:
            return diagnostic(rawValue: rawValue, command: .none, classification: .ignoredNoOp)
        case 0x10...0x50:
            let value = Int(rawValue - 0x10)
            return diagnostic(
                rawValue: rawValue,
                command: .setVolume(value: value),
                classification: .supported,
                appliedVolumeValue: value,
                appliedGainMultiplier: Float(value) / 64.0
            )
        case 0x60...0x6F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .volumeSlideDown(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeDown,
                behavior: .rowLevelApproximation
            )
        case 0x70...0x7F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .volumeSlideUp(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeUp,
                behavior: .rowLevelApproximation
            )
        case 0x80...0x8F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .fineVolumeSlideDown(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeDown,
                behavior: .rowLevelApproximation
            )
        case 0x90...0x9F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .fineVolumeSlideUp(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeUp,
                behavior: .rowLevelApproximation
            )
        case 0xA0...0xAF:
            return diagnostic(rawValue: rawValue, command: .setVibratoSpeed(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0xB0...0xBF:
            return diagnostic(rawValue: rawValue, command: .vibrato(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0xC0...0xCF:
            let panning = Int(rawValue & 0x0F) * 17
            return diagnostic(
                rawValue: rawValue,
                command: .setPanning(value: panning),
                classification: .supported,
                appliedPanningValue: panning,
                appliedPan: audioPan(forXMValue: panning)
            )
        case 0xD0...0xDF:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .panningSlideLeft(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .panningLeft,
                behavior: .rowLevelApproximation
            )
        case 0xE0...0xEF:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .panningSlideRight(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .panningRight,
                behavior: .rowLevelApproximation
            )
        case 0xF0...0xFF:
            return diagnostic(rawValue: rawValue, command: .tonePortamento(amount: Int(rawValue & 0x0F)), classification: .deferred)
        default:
            return diagnostic(rawValue: rawValue, command: .unsupported(rawValue: rawValue), classification: .deferred)
        }
    }

    private static func diagnostic(
        rawValue: UInt8,
        command: PlaybackSongSyntheticVolumeColumnCommand,
        classification: PlaybackSongSyntheticVolumeColumnClassification,
        appliedVolumeValue: Int? = nil,
        appliedGainMultiplier: Float? = nil,
        appliedPanningValue: Int? = nil,
        appliedPan: Float? = nil,
        slideAmount: Int? = nil,
        slideDirection: PlaybackSongSyntheticVolumeColumnSlideDirection? = nil,
        behavior: PlaybackSongSyntheticVolumeColumnBehavior? = nil
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        PlaybackSongSyntheticVolumeColumnDiagnostic(
            rawValue: rawValue,
            command: command,
            classification: classification,
            applied: classification == .supported,
            ignoredAsEmptyOrNoOp: classification == .ignoredNoOp,
            deferred: classification == .deferred,
            appliedVolumeValue: appliedVolumeValue,
            appliedGainMultiplier: appliedGainMultiplier,
            appliedPanningValue: appliedPanningValue,
            appliedPan: appliedPan,
            slideAmount: slideAmount,
            slideDirection: slideDirection,
            effectiveVolumeBefore: nil,
            effectiveVolumeAfter: nil,
            effectivePanBefore: nil,
            effectivePanAfter: nil,
            behavior: behavior
        )
    }

    static func audioPan(forXMValue value: Int) -> Float {
        audioPan(forXMValue: Double(value))
    }

    static func audioPan(forXMValue value: Double) -> Float {
        (Float(min(255.0, max(0.0, value))) / 127.5) - 1.0
    }
}

struct PlaybackSongSyntheticVolumeColumnMapping: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
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

struct PlaybackSongFxxRowTiming: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowEndExactFrame: Double
    let effectiveSpeed: Int
    let effectiveBPM: Int

    var rowStartFrame: Int {
        Self.floorFrame(rowStartExactFrame)
    }

    var rowEndFrame: Int {
        Self.floorFrame(rowEndExactFrame)
    }

    var rowDurationFrames: Int {
        max(0, rowEndFrame - rowStartFrame)
    }

    var diagnostic: PlaybackSongSyntheticRowTimingDiagnostic {
        PlaybackSongSyntheticRowTimingDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            rowStartFrame: rowStartFrame,
            rowDurationFrames: rowDurationFrames,
            effectiveSpeed: effectiveSpeed,
            effectiveBPM: effectiveBPM
        )
    }

    private static func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

struct PlaybackSongFxxTimingPlan: Equatable {
    let sampleRate: Double
    let initialSpeed: Int
    let initialBPM: Int
    let rowTimings: [PlaybackSongFxxRowTiming]
    let timingChanges: [PlaybackSongSyntheticTimingChangeDiagnostic]
    let finalSpeed: Int
    let finalBPM: Int
    let endExactFrame: Double

    var rowTimingDiagnostics: [PlaybackSongSyntheticRowTimingDiagnostic] {
        rowTimings.map(\.diagnostic)
    }

    func timingConfig(forSyntheticRow syntheticRow: Int) -> SyntheticTrackerTimingConfig {
        let timing = timingFor(syntheticRow: syntheticRow)
        return SyntheticTrackerTimingConfig(
            speed: timing.speed,
            bpm: timing.bpm,
            sampleRate: sampleRate
        )
    }

    func frameFor(row: Int, tick: Int = 0) -> Int {
        let safeRow = max(0, row)
        let timing = timingFor(syntheticRow: safeRow)
        let safeTick = min(max(0, tick), timing.speed - 1)
        let exactFrame = timing.rowStartExactFrame + (Double(safeTick) * framesPerTick(bpm: timing.bpm))
        return floorFrame(exactFrame)
    }

    private func timingFor(syntheticRow: Int) -> (rowStartExactFrame: Double, speed: Int, bpm: Int) {
        if rowTimings.indices.contains(syntheticRow),
           rowTimings[syntheticRow].syntheticRow == syntheticRow {
            let rowTiming = rowTimings[syntheticRow]
            return (
                rowStartExactFrame: rowTiming.rowStartExactFrame,
                speed: rowTiming.effectiveSpeed,
                bpm: rowTiming.effectiveBPM
            )
        }

        let extraRows = max(0, syntheticRow - rowTimings.count)
        let rowStart = endExactFrame + (Double(extraRows) * rowDuration(speed: finalSpeed, bpm: finalBPM))
        return (rowStartExactFrame: rowStart, speed: finalSpeed, bpm: finalBPM)
    }

    private func framesPerTick(bpm: Int) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm))
    }

    private func rowDuration(speed: Int, bpm: Int) -> Double {
        framesPerTick(bpm: bpm) * Double(max(1, speed))
    }

    private func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

enum PlaybackSongFxxTimingPlanner {
    static func plan(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongFxxTimingPlan {
        let initialConfig = SyntheticTrackerTimingConfig(
            speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm,
            sampleRate: sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var currentSpeed = initialConfig.speed
        var currentBPM = initialConfig.bpm
        var currentExactFrame = 0.0
        var nextSyntheticRow = 0
        var rowTimings = [PlaybackSongFxxRowTiming]()
        var timingChanges = [PlaybackSongSyntheticTimingChangeDiagnostic]()

        for orderOffset in 0..<safeOrderCount {
            let orderIndex = startOrderIndex + orderOffset
            guard song.orders.indices.contains(orderIndex) else {
                continue
            }
            let order = song.orders[orderIndex]
            guard let pattern = song.patternsByIndex[order.patternIndex] else {
                continue
            }

            for (rowOffset, row) in pattern.rows.enumerated() {
                let syntheticRow = nextSyntheticRow + rowOffset
                let source = PlaybackPosition(
                    orderIndex: orderIndex,
                    patternIndex: pattern.index,
                    rowIndex: row.index
                )
                let rowStartExactFrame = currentExactFrame
                let rowEndExactFrame = currentExactFrame + rowDuration(
                    speed: currentSpeed,
                    bpm: currentBPM,
                    sampleRate: initialConfig.sampleRate
                )
                let rowTiming = PlaybackSongFxxRowTiming(
                    source: source,
                    syntheticRow: syntheticRow,
                    rowStartExactFrame: rowStartExactFrame,
                    rowEndExactFrame: rowEndExactFrame,
                    effectiveSpeed: currentSpeed,
                    effectiveBPM: currentBPM
                )
                rowTimings.append(rowTiming)

                var nextSpeed = currentSpeed
                var nextBPM = currentBPM
                for (channelIndex, cell) in row.cells.enumerated() where isFxxTimingEffect(cell) {
                    let speedBefore = nextSpeed
                    let bpmBefore = nextBPM
                    let kind: PlaybackSongSyntheticTimingChangeDiagnostic.Kind
                    let applied: Bool
                    switch cell.effectParam {
                    case 0:
                        kind = .ignoredF00
                        applied = false
                    case 0x01...0x1F:
                        kind = .speed
                        applied = true
                        nextSpeed = Int(cell.effectParam)
                    default:
                        kind = .bpm
                        applied = true
                        nextBPM = Int(cell.effectParam)
                    }
                    timingChanges.append(PlaybackSongSyntheticTimingChangeDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        effectType: cell.effectType,
                        effectParam: cell.effectParam,
                        rowStartFrame: rowTiming.rowStartFrame,
                        appliesToSyntheticRowAfter: syntheticRow + 1,
                        kind: kind,
                        applied: applied,
                        speedBefore: speedBefore,
                        bpmBefore: bpmBefore,
                        speedAfter: nextSpeed,
                        bpmAfter: nextBPM
                    ))
                }

                currentExactFrame = rowEndExactFrame
                currentSpeed = nextSpeed
                currentBPM = nextBPM
            }

            nextSyntheticRow += pattern.rowCount
        }

        return PlaybackSongFxxTimingPlan(
            sampleRate: initialConfig.sampleRate,
            initialSpeed: initialConfig.speed,
            initialBPM: initialConfig.bpm,
            rowTimings: rowTimings,
            timingChanges: timingChanges,
            finalSpeed: currentSpeed,
            finalBPM: currentBPM,
            endExactFrame: currentExactFrame
        )
    }

    static func isFxxTimingEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0F
    }

    private static func rowDuration(speed: Int, bpm: Int, sampleRate: Double) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm)) * Double(max(1, speed))
    }
}

enum PlaybackSongSyntheticAdapter {
    private static let maxMixerEnvelopePointCount = 12
    private static let xmLinearPeriodBase = 7_680.0
    private static let xmLinearC4Period = 4_608.0
    private static let xmLinearPeriodUnitsPerSemitone = 64.0
    private static let xmLinearPeriodUnitsPerOctave = 768.0

    private struct ChannelState: Equatable {
        var volumeValue = 64
        var panningValue = 127.5
        var activeEventIndex: Int?
        var activeEventMappingIndex: Int?
        var activeSampleVolume: Float?

        var pan: Float {
            PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: panningValue)
        }
    }

    private struct SampleSelection: Equatable {
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

    private struct EventCoverageBuilder: Equatable {
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

        mutating func visit(_ cell: PlaybackCell) {
            totalCellsVisited += 1
            if isCompletelyEmpty(cell) {
                emptyCells += 1
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

    static func adapt(
        _ song: PlaybackSong,
        orderIndex: Int,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: orderIndex, orderCount: 1, sampleRate: sampleRate)
    }

    static func adapt(
        _ song: PlaybackSong,
        orderRange: Range<Int>,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        adapt(
            song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: max(0, orderRange.count),
            sampleRate: sampleRate
        )
    }

    static func adapt(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            sampleRate: sampleRate
        )
        let timingConfig = SyntheticTrackerTimingConfig(
            speed: timingPlan.initialSpeed,
            bpm: timingPlan.initialBPM,
            sampleRate: timingPlan.sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var adaptedOrders = [PlaybackSongSyntheticOrderDiagnostic]()
        var rowMappings = [PlaybackSongSyntheticRowMapping]()
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var volumeColumnMappings = [PlaybackSongSyntheticVolumeColumnMapping]()
        var voiceStateUpdates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        var sampleOffsetEffects = [PlaybackSongSyntheticSampleOffsetDiagnostic]()
        var noteCutEffects = [PlaybackSongSyntheticNoteCutDiagnostic]()
        var noteDelayEffects = [PlaybackSongSyntheticNoteDelayDiagnostic]()
        var retriggerEffects = [PlaybackSongSyntheticRetriggerDiagnostic]()
        var keyOffEvents = [PlaybackSongSyntheticKeyOffDiagnostic]()
        var effectCommandDiagnostics = [PlaybackSongSyntheticEffectCommandDiagnostic]()
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
        var deferredCellFields = [PlaybackSongSyntheticDeferredCellField]()
        var eventCoverage = EventCoverageBuilder()
        var events = [SyntheticTrackerEvent]()
        var channelStates = [Int: ChannelState]()
        var nextSyntheticRow = 0

        for orderOffset in 0..<safeOrderCount {
            let orderIndex = startOrderIndex + orderOffset
            guard song.orders.indices.contains(orderIndex) else {
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: orderIndex,
                    patternIndex: nil,
                    syntheticStartRow: nextSyntheticRow,
                    rowCount: 0,
                    status: .invalidOrder
                ))
                continue
            }

            let order = song.orders[orderIndex]
            guard let pattern = song.patternsByIndex[order.patternIndex] else {
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: orderIndex,
                    patternIndex: order.patternIndex,
                    syntheticStartRow: nextSyntheticRow,
                    rowCount: 0,
                    status: .missingPattern
                ))
                continue
            }

            adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                requestedOrderIndex: orderIndex,
                patternIndex: pattern.index,
                syntheticStartRow: nextSyntheticRow,
                rowCount: pattern.rowCount,
                status: .adapted
            ))

            for (rowOffset, row) in pattern.rows.enumerated() {
                let syntheticRow = nextSyntheticRow + rowOffset
                let source = PlaybackPosition(
                    orderIndex: orderIndex,
                    patternIndex: pattern.index,
                    rowIndex: row.index
                )
                rowMappings.append(PlaybackSongSyntheticRowMapping(source: source, syntheticRow: syntheticRow))
                rowDiagnostics.append(appendEvents(
                    from: row,
                    source: source,
                    syntheticRow: syntheticRow,
                    song: song,
                    timingConfig: timingPlan.timingConfig(forSyntheticRow: syntheticRow),
                    timingPlan: timingPlan,
                    scheduledStartFrame: timingPlan.frameFor(row: syntheticRow, tick: 0),
                    channelStates: &channelStates,
                    events: &events,
                    volumeColumnMappings: &volumeColumnMappings,
                    voiceStateUpdates: &voiceStateUpdates,
                    sampleOffsetEffects: &sampleOffsetEffects,
                    noteCutEffects: &noteCutEffects,
                    noteDelayEffects: &noteDelayEffects,
                    retriggerEffects: &retriggerEffects,
                    keyOffEvents: &keyOffEvents,
                    effectCommandDiagnostics: &effectCommandDiagnostics,
                    eventMappings: &eventMappings,
                    ignoredCells: &ignoredCells,
                    deferredCellFields: &deferredCellFields,
                    eventCoverage: &eventCoverage
                ))
            }

            nextSyntheticRow += pattern.rowCount
        }

        return PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: SyntheticPattern(rowCount: nextSyntheticRow, events: events),
            diagnostics: PlaybackSongSyntheticDiagnostics(
                requestedStartOrderIndex: startOrderIndex,
                requestedOrderCount: safeOrderCount,
                sampleRate: timingConfig.sampleRate,
                initialSpeed: timingConfig.speed,
                initialBPM: timingConfig.bpm,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                syntheticRowCount: nextSyntheticRow,
                adaptedOrders: adaptedOrders,
                rowMappings: rowMappings,
                rowTiming: timingPlan.rowTimingDiagnostics,
                timingChanges: timingPlan.timingChanges,
                effectCommandDiagnostics: effectCommandDiagnostics,
                rowDiagnostics: rowDiagnostics,
                volumeColumnMappings: volumeColumnMappings,
                voiceStateUpdates: voiceStateUpdates,
                sampleOffsetEffects: sampleOffsetEffects,
                noteCutEffects: noteCutEffects,
                noteDelayEffects: noteDelayEffects,
                retriggerEffects: retriggerEffects,
                keyOffEvents: keyOffEvents,
                eventMappings: eventMappings,
                ignoredCells: ignoredCells,
                deferredCellFields: deferredCellFields,
                eventCoverage: eventCoverage.summary
            )
        )
    }

    private static func appendEvents(
        from row: PlaybackRow,
        source: PlaybackPosition,
        syntheticRow: Int,
        song: PlaybackSong,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        scheduledStartFrame: Int,
        channelStates: inout [Int: ChannelState],
        events: inout [SyntheticTrackerEvent],
        volumeColumnMappings: inout [PlaybackSongSyntheticVolumeColumnMapping],
        voiceStateUpdates: inout [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        sampleOffsetEffects: inout [PlaybackSongSyntheticSampleOffsetDiagnostic],
        noteCutEffects: inout [PlaybackSongSyntheticNoteCutDiagnostic],
        noteDelayEffects: inout [PlaybackSongSyntheticNoteDelayDiagnostic],
        retriggerEffects: inout [PlaybackSongSyntheticRetriggerDiagnostic],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        effectCommandDiagnostics: inout [PlaybackSongSyntheticEffectCommandDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField],
        eventCoverage: inout EventCoverageBuilder
    ) -> PlaybackSongSyntheticRowDiagnostic {
        let eventStartCount = events.count
        let ignoredStartCount = ignoredCells.count
        for (channelIndex, cell) in row.cells.enumerated() {
            eventCoverage.visit(cell)
            if let effectCommandDiagnostic = effectCommandDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                timingConfig: timingConfig
            ) {
                effectCommandDiagnostics.append(effectCommandDiagnostic)
            }
            var channelState = channelStates[channelIndex] ?? ChannelState()
            let channelStateBeforeVolumeColumn = channelState
            let volumeColumn = applyVolumeColumn(
                PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
                to: &channelState
            )
            if let update = voiceStateUpdate(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                cell: cell,
                volumeColumn: volumeColumn,
                channelStateBefore: channelStateBeforeVolumeColumn,
                channelStateAfter: channelState
            ) {
                voiceStateUpdates.append(update)
            }
            if let update = applyEffectColumnState(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                channelState: &channelState
            ) {
                voiceStateUpdates.append(update)
            }
            channelStates[channelIndex] = channelState
            if cell.volumeColumn != 0 {
                volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
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
                deferredCellFields: &deferredCellFields
            )
            let noteDelay = noteDelayDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                timingPlan: timingPlan,
                originalFrame: scheduledStartFrame,
                eventIndex: nil
            )
            if cell.note == 97 {
                handleKeyOff(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledStartFrame: scheduledStartFrame,
                    volumeColumn: volumeColumn,
                    cell: cell,
                    channelState: &channelState,
                    events: &events,
                    keyOffEvents: &keyOffEvents,
                    eventMappings: &eventMappings,
                    ignoredCells: &ignoredCells,
                    deferredCellFields: &deferredCellFields,
                    eventCoverage: &eventCoverage
                )
                _ = handleRetrigger(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    volumeColumn: volumeColumn,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    events: &events,
                    eventMappings: &eventMappings,
                    retriggerEffects: &retriggerEffects,
                    eventCoverage: &eventCoverage
                )
                if let noteDelay {
                    noteDelayEffects.append(noteDelay)
                }
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &noteCutEffects
                )
                channelStates[channelIndex] = channelState
                continue
            }
            guard (1...96).contains(cell.note) else {
                if let noteDelay {
                    noteDelayEffects.append(noteDelay)
                }
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &noteCutEffects
                )
                let retrigger = handleRetrigger(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    volumeColumn: volumeColumn,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    events: &events,
                    eventMappings: &eventMappings,
                    retriggerEffects: &retriggerEffects,
                    eventCoverage: &eventCoverage
                )
                if retrigger?.applied == true {
                    channelStates[channelIndex] = channelState
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
                    hasIgnoredEffect: noteDelay != nil || hasDeferredEffect(cell)
                )
                ignoredCells.append(ignored)
                eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: false)
                channelStates[channelIndex] = channelState
                continue
            }
            if let noteDelay, noteDelay.outOfRow {
                noteDelayEffects.append(noteDelay)
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .noteDelayOutOfRow,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: true
                )
                ignoredCells.append(ignored)
                eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                channelStates[channelIndex] = channelState
                continue
            }

            let instrumentIndex = Int(cell.instrument)
            guard instrumentIndex > 0 else {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &noteCutEffects
                )
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .missingInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffect(cell)
                )
                ignoredCells.append(ignored)
                eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                channelStates[channelIndex] = channelState
                continue
            }
            guard let instrument = song.instrument(forInstrument: instrumentIndex) else {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &noteCutEffects
                )
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .unknownInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffect(cell)
                )
                ignoredCells.append(ignored)
                eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                channelStates[channelIndex] = channelState
                continue
            }
            let sampleSelection = selectSample(forNote: cell.note, from: instrument)
            guard let sample = sampleSelection.sample else {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &noteCutEffects
                )
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
                    hasIgnoredEffect: hasDeferredEffect(cell)
                )
                ignoredCells.append(ignored)
                eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                eventCoverage.recordSkippedSampleSelection(
                    method: sampleSelection.method,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
                )
                channelStates[channelIndex] = channelState
                continue
            }

            let sampleLength = selectedSampleLength(sample)
            let sampleOffset = sampleOffsetDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                selectedSampleLength: sampleLength
            )
            if sampleOffset.detected {
                sampleOffsetEffects.append(sampleOffset)
            }
            if sampleOffset.skipped {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &noteCutEffects
                )
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
                    hasIgnoredEffect: hasDeferredEffect(cell)
                )
                ignoredCells.append(ignored)
                eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                channelStates[channelIndex] = channelState
                continue
            }

            let eventIndex = events.count
            let loop = mixerLoop(from: sample)
            let envelopeMapping = mixerVolumeEnvelope(
                from: instrument.volumeEnvelope,
                timingConfig: timingConfig
            )
            let envelopeSemantics = volumeEnvelopeSemantics(
                from: instrument.volumeEnvelope,
                mapping: envelopeMapping
            )
            let pitchMapping = playbackStepMapping(
                note: cell.note,
                sample: sample,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                timingConfig: timingConfig
            )
            let gain = adaptedGain(sampleVolume: sample.volume, channelVolume: channelState.volumeValue)
            let pan = channelState.pan
            let scheduledNoteFrame = noteDelay?.delayedFrame ?? scheduledStartFrame
            let scheduledNoteTick = noteDelay?.applied == true ? noteDelay?.requestedTick ?? 0 : 0
            events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: scheduledNoteTick,
                scheduledStartFrame: scheduledNoteFrame,
                sample: MixerSampleBuffer(monoPCM: sample.pcm),
                gain: gain,
                pan: pan,
                playbackStep: pitchMapping.playbackStep,
                loop: loop,
                initialSourceFrame: sampleOffset.appliedOffsetFrames ?? 0,
                volumeEnvelope: envelopeMapping.envelope
            ))
            eventCoverage.recordScheduledNote(
                method: sampleSelection.method,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
            )
            if hasDeferredEffect(cell) || volumeColumn.deferred {
                eventCoverage.recordDeferredCellWithoutSkip()
            }
            channelState.activeEventIndex = eventIndex
            channelState.activeEventMappingIndex = eventMappings.count
            channelState.activeSampleVolume = sample.volume
            channelStates[channelIndex] = channelState
            eventMappings.append(PlaybackSongSyntheticEventMapping(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
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
                hasIgnoredEffect: hasDeferredEffect(cell),
                effectiveVolumeValue: channelState.volumeValue,
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
                finetuneStatus: pitchMapping.finetuneStatus,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                frequencyTableStatus: pitchMapping.frequencyTableStatus,
                linearFrequencyApplied: pitchMapping.linearFrequencyApplied,
                amigaFrequencyDeferred: pitchMapping.amigaFrequencyDeferred,
                playbackStep: pitchMapping.playbackStep,
                pitchMappingApplied: pitchMapping.applied,
                pitchMappingUsedNeutralStep: pitchMapping.usedNeutralStep
            ))
            if let noteDelay, noteDelay.applied {
                noteDelayEffects.append(noteDelayDiagnostic(
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
            _ = handleRetrigger(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                volumeColumn: volumeColumn,
                timingConfig: timingConfig,
                timingPlan: timingPlan,
                channelState: &channelState,
                events: &events,
                eventMappings: &eventMappings,
                retriggerEffects: &retriggerEffects,
                eventCoverage: &eventCoverage
            )
            handleNoteCut(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                timingPlan: timingPlan,
                channelState: &channelState,
                noteCutEffects: &noteCutEffects
            )
            channelStates[channelIndex] = channelState
        }
        return PlaybackSongSyntheticRowDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            cellCount: row.cells.count,
            emittedEventCount: events.count - eventStartCount,
            ignoredCellCount: ignoredCells.count - ignoredStartCount
        )
    }

    private static func voiceStateUpdate(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        cell: PlaybackCell,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        channelStateBefore: ChannelState,
        channelStateAfter: ChannelState
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? {
        guard cell.volumeColumn != 0 else {
            return nil
        }
        if volumeColumn.deferred {
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .volumeColumn,
                command: .volumeColumn(volumeColumn.command),
                rawVolumeColumn: cell.volumeColumn,
                effectType: nil,
                effectParam: nil,
                status: .deferredUnsupported,
                behavior: volumeColumn.behavior,
                channelStateBefore: channelStateBefore,
                channelStateAfter: channelStateBefore
            )
        }
        guard volumeColumn.applied,
              reportsVolumeColumnStateUpdate(volumeColumn.command) else {
            return nil
        }
        return voiceStateUpdateDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            scheduledFrame: scheduledFrame,
            cell: cell,
            commandSource: .volumeColumn,
            command: .volumeColumn(volumeColumn.command),
            rawVolumeColumn: cell.volumeColumn,
            effectType: nil,
            effectParam: nil,
            status: .applied,
            behavior: volumeColumn.behavior,
            channelStateBefore: channelStateBefore,
            channelStateAfter: channelStateAfter
        )
    }

    private static func reportsVolumeColumnStateUpdate(
        _ command: PlaybackSongSyntheticVolumeColumnCommand
    ) -> Bool {
        switch command {
        case .setVolume,
             .volumeSlideDown,
             .volumeSlideUp,
             .fineVolumeSlideDown,
             .fineVolumeSlideUp,
             .setPanning,
             .panningSlideLeft,
             .panningSlideRight:
            return true
        case .none,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return false
        }
    }

    private static func applyEffectColumnState(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? {
        switch cell.effectType {
        case 0x0C:
            let before = channelState
            channelState.volumeValue = clampedVolumeValue(Int(cell.effectParam))
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .cxxSetVolume(value: channelState.volumeValue),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: nil,
                channelStateBefore: before,
                channelStateAfter: channelState
            )
        case 0x08:
            let before = channelState
            let panningValue = clampedPanningValue(Double(Int(cell.effectParam)))
            channelState.panningValue = panningValue
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .effect8xxSetPanning(value: Int(panningValue.rounded())),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: nil,
                channelStateBefore: before,
                channelStateAfter: channelState
            )
        case 0x0A:
            let before = channelState
            guard cell.effectParam != 0 else {
                return voiceStateUpdateDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    commandSource: .effectColumn,
                    command: .axyVolumeSlide(up: 0, down: 0),
                    rawVolumeColumn: nil,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignoredNoOp,
                    behavior: .rowLevelApproximation,
                    channelStateBefore: before,
                    channelStateAfter: before
                )
            }
            let up = Int((cell.effectParam & 0xF0) >> 4)
            let down = Int(cell.effectParam & 0x0F)
            if up > 0 {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue + up)
            } else {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue - down)
            }
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .axyVolumeSlide(up: up, down: up > 0 ? 0 : down),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .rowLevelApproximation,
                channelStateBefore: before,
                channelStateAfter: channelState
            )
        case 0x11:
            let before = channelState
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .hxyGlobalVolumeSlide,
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .deferredUnsupported,
                behavior: nil,
                channelStateBefore: before,
                channelStateAfter: before
            )
        default:
            return nil
        }
    }

    private static func voiceStateUpdateDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        cell: PlaybackCell,
        commandSource: PlaybackSongSyntheticVoiceStateUpdateSource,
        command: PlaybackSongSyntheticVoiceStateUpdateCommand,
        rawVolumeColumn: UInt8?,
        effectType: UInt8?,
        effectParam: UInt8?,
        status: PlaybackSongSyntheticVoiceStateUpdateStatus,
        behavior: PlaybackSongSyntheticVolumeColumnBehavior?,
        channelStateBefore: ChannelState,
        channelStateAfter: ChannelState
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        let activeSampleVolume = channelStateBefore.activeSampleVolume
        let gainBefore = activeSampleVolume.map {
            adaptedGain(sampleVolume: $0, channelVolume: channelStateBefore.volumeValue)
        }
        let gainAfter = activeSampleVolume.map {
            adaptedGain(sampleVolume: $0, channelVolume: channelStateAfter.volumeValue)
        }
        let canUpdateActiveVoice = status == .applied &&
            cell.note == 0 &&
            channelStateBefore.activeEventIndex != nil &&
            activeSampleVolume != nil
        return PlaybackSongSyntheticVoiceStateUpdateDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            cellNote: cell.note,
            instrumentIndex: Int(cell.instrument),
            commandSource: commandSource,
            command: command,
            rawVolumeColumn: rawVolumeColumn,
            effectType: effectType,
            effectParam: effectParam,
            status: status,
            behavior: behavior,
            activeVoiceUpdated: canUpdateActiveVoice,
            activeEventIndex: canUpdateActiveVoice ? channelStateBefore.activeEventIndex : nil,
            effectiveVolumeBefore: channelStateBefore.volumeValue,
            effectiveVolumeAfter: channelStateAfter.volumeValue,
            effectivePanBefore: channelStateBefore.pan,
            effectivePanAfter: channelStateAfter.pan,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            panBefore: channelStateBefore.pan,
            panAfter: channelStateAfter.pan
        )
    }

    private static func applyVolumeColumn(
        _ volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        to state: inout ChannelState
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        switch volumeColumn.command {
        case let .setVolume(value):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(value)
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideDown(amount),
             let .fineVolumeSlideDown(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before - amount)
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideUp(amount),
             let .fineVolumeSlideUp(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before + amount)
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .setPanning(value):
            let before = state.pan
            state.panningValue = clampedPanningValue(Double(value))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideLeft(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue - Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideRight(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue + Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case .none,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return volumeColumn
        }
    }

    private static func appendDeferredFields(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        includeKeyOff: Bool,
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) {
        if volumeColumn.deferred {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .volumeColumn
            ))
        }
        if hasDeferredEffect(cell) {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .effect
            ))
        }
        if includeKeyOff, cell.note == 97 {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .keyOff
            ))
        }
    }

    private static func handleKeyOff(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledStartFrame: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        cell: PlaybackCell,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField],
        eventCoverage: inout EventCoverageBuilder
    ) {
        guard let activeEventIndex = channelState.activeEventIndex,
              let activeEventMappingIndex = channelState.activeEventMappingIndex,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeEventMappingIndex),
              scheduledStartFrame >= (events[activeEventIndex].scheduledStartFrame ?? 0) else {
            keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                releaseFrame: nil,
                applied: false,
                deferred: true,
                reason: .noActiveVoice,
                activeEventIndex: nil
            ))
            let ignored = ignoredCell(
                source: source,
                channelIndex: channelIndex,
                cell: cell,
                reason: .keyOff,
                volumeColumn: volumeColumn,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffect(cell)
            )
            ignoredCells.append(ignored)
            eventCoverage.recordIgnoredCell(
                reason: ignored.skipReason,
                isNormalNote: false,
                isNoteOffWithoutActiveVoice: true
            )
            appendDeferredFields(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                volumeColumn: volumeColumn,
                includeKeyOff: true,
                deferredCellFields: &deferredCellFields
            )
            return
        }

        let previousMapping = eventMappings[activeEventMappingIndex]
        let fadeoutDecrement = fadeoutFrameDecrement(
            fadeoutValue: previousMapping.volumeEnvelopeSemantics.fadeoutValue,
            sampleRate: previousMapping.outputSampleRate
        )
        events[activeEventIndex] = events[activeEventIndex].withKeyOffFrame(
            scheduledStartFrame,
            fadeoutFrameDecrement: fadeoutDecrement
        )
        eventMappings[activeEventMappingIndex] = eventMapping(
            previousMapping,
            applying: previousMapping.volumeEnvelopeSemantics.applyingKeyOff(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                releaseFrame: scheduledStartFrame
            )
        )
        keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            releaseFrame: scheduledStartFrame,
            applied: true,
            deferred: false,
            reason: .releasedActiveVoice,
            activeEventIndex: activeEventIndex
        ))
        if hasDeferredEffect(cell) || volumeColumn.deferred {
            eventCoverage.recordDeferredCellWithoutSkip()
        }
        channelState.activeEventIndex = nil
        channelState.activeEventMappingIndex = nil
        channelState.activeSampleVolume = nil
    }

    @discardableResult
    private static func handleRetrigger(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        retriggerEffects: inout [PlaybackSongSyntheticRetriggerDiagnostic],
        eventCoverage: inout EventCoverageBuilder
    ) -> PlaybackSongSyntheticRetriggerDiagnostic? {
        guard isRetriggerEffect(cell) else {
            return nil
        }

        let interval = extendedEffectTick(cell)
        let rowSpeed = timingConfig.speed
        let rowBPM = timingConfig.bpm
        let activeEventIndexBefore = channelState.activeEventIndex
        let activeMappingIndexBefore = channelState.activeEventMappingIndex
        let activeVoiceFound = activeEventIndexBefore.map { events.indices.contains($0) } == true &&
            activeMappingIndexBefore.map { eventMappings.indices.contains($0) } == true &&
            channelState.activeSampleVolume != nil

        func diagnostic(
            status: PlaybackSongSyntheticRetriggerDiagnostic.Status,
            ticks: [Int] = [],
            frames: [Int] = [],
            eventIndices: [Int] = [],
            replacedEventIndices: [Int] = []
        ) -> PlaybackSongSyntheticRetriggerDiagnostic {
            let applied = status == .applied
            let deferred = status == .ignoredE90NoEffectMemory
            let ignoredAsNoOp = status == .ignoredE90NoEffectMemory ||
                status == .noActiveVoice ||
                status == .outOfRowNoOp
            let outOfRow = status == .outOfRowNoOp
            let activeMapping = activeMappingIndexBefore.flatMap {
                eventMappings.indices.contains($0) ? eventMappings[$0] : nil
            }
            let activeEvent = activeEventIndexBefore.flatMap {
                events.indices.contains($0) ? events[$0] : nil
            }
            return PlaybackSongSyntheticRetriggerDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: status,
                detected: true,
                applied: applied,
                deferred: deferred,
                ignoredAsNoOp: ignoredAsNoOp,
                outOfRow: outOfRow,
                activeVoiceFound: activeVoiceFound,
                retriggerIntervalTicks: interval,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                retriggerTicks: ticks,
                retriggerFrames: frames,
                retriggerEventIndices: eventIndices,
                replacedEventIndices: replacedEventIndices,
                activeEventIndexBefore: activeEventIndexBefore,
                selectedSampleIndex: activeMapping?.sampleIndex,
                selectedSampleLength: activeMapping?.selectedSampleLength,
                initialSourceFrame: activeEvent?.initialSourceFrame,
                playbackStep: activeEvent?.playbackStep,
                gain: activeEvent?.gain,
                pan: activeEvent?.pan,
                envelopePolicy: "fresh_event_restarts_envelope"
            )
        }

        guard interval > 0 else {
            let result = diagnostic(status: .ignoredE90NoEffectMemory)
            retriggerEffects.append(result)
            return result
        }
        guard interval < rowSpeed else {
            let result = diagnostic(status: .outOfRowNoOp)
            retriggerEffects.append(result)
            return result
        }
        guard let activeEventIndex = activeEventIndexBefore,
              let activeMappingIndex = activeMappingIndexBefore,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeMappingIndex),
              let activeSampleVolume = channelState.activeSampleVolume else {
            let result = diagnostic(status: .noActiveVoice)
            retriggerEffects.append(result)
            return result
        }

        let sourceEvent = events[activeEventIndex]
        let sourceMapping = eventMappings[activeMappingIndex]
        let gain = adaptedGain(sampleVolume: activeSampleVolume, channelVolume: channelState.volumeValue)
        let pan = channelState.pan
        var ticks = [Int]()
        var frames = [Int]()
        var eventIndices = [Int]()
        var replacedEventIndices = [Int]()
        var previousEventIndex = activeEventIndex

        var tick = interval
        while tick < rowSpeed {
            let frame = timingPlan.frameFor(row: syntheticRow, tick: tick)
            let eventIndex = events.count
            events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: tick,
                scheduledStartFrame: frame,
                sample: sourceEvent.sample,
                gain: gain,
                pan: pan,
                playbackStep: sourceEvent.playbackStep,
                loop: sourceEvent.loop,
                initialSourceFrame: sourceEvent.initialSourceFrame,
                volumeEnvelope: sourceEvent.volumeEnvelope,
                panEnvelope: sourceEvent.panEnvelope
            ))
            eventMappings.append(retriggeredEventMapping(
                from: sourceMapping,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                eventIndex: eventIndex,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                volumeColumn: volumeColumn,
                effectiveVolumeValue: channelState.volumeValue,
                effectivePan: pan
            ))
            eventCoverage.recordScheduledNote(
                method: sourceMapping.sampleSelectionMethod,
                firstPlayableSampleFallbackUsed: sourceMapping.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sourceMapping.sampleMapKeymapBehaviorDeferred
            )
            ticks.append(tick)
            frames.append(frame)
            eventIndices.append(eventIndex)
            replacedEventIndices.append(previousEventIndex)
            previousEventIndex = eventIndex
            tick += interval
        }

        channelState.activeEventIndex = previousEventIndex
        channelState.activeEventMappingIndex = eventMappings.count - 1
        channelState.activeSampleVolume = activeSampleVolume

        let result = diagnostic(
            status: .applied,
            ticks: ticks,
            frames: frames,
            eventIndices: eventIndices,
            replacedEventIndices: replacedEventIndices
        )
        retriggerEffects.append(result)
        return result
    }

    private static func handleNoteCut(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        noteCutEffects: inout [PlaybackSongSyntheticNoteCutDiagnostic]
    ) {
        guard let diagnostic = noteCutDiagnostic(
            from: cell,
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            timingPlan: timingPlan,
            activeEventIndex: channelState.activeEventIndex
        ) else {
            return
        }
        noteCutEffects.append(diagnostic)
        guard diagnostic.applied else {
            return
        }
        channelState.activeEventIndex = nil
        channelState.activeEventMappingIndex = nil
        channelState.activeSampleVolume = nil
    }

    private static func noteCutDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        activeEventIndex: Int?
    ) -> PlaybackSongSyntheticNoteCutDiagnostic? {
        guard isNoteCutEffect(cell) else {
            return nil
        }
        let tick = extendedEffectTick(cell)
        let rowSpeed = timingConfig.speed
        let rowBPM = timingConfig.bpm
        guard tick < rowSpeed else {
            return PlaybackSongSyntheticNoteCutDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .outOfRowNoOp,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: true,
                outOfRow: true,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                scheduledFrame: nil,
                activeEventIndex: activeEventIndex
            )
        }
        let cutFrame = timingPlan.frameFor(row: syntheticRow, tick: tick)
        guard let activeEventIndex else {
            return PlaybackSongSyntheticNoteCutDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .noActiveVoice,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: true,
                outOfRow: false,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                scheduledFrame: cutFrame,
                activeEventIndex: nil
            )
        }
        return PlaybackSongSyntheticNoteCutDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: tick,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .applied,
            detected: true,
            applied: true,
            deferred: false,
            ignoredAsNoOp: false,
            outOfRow: false,
            requestedTick: tick,
            rowSpeed: rowSpeed,
            rowBPM: rowBPM,
            scheduledFrame: cutFrame,
            activeEventIndex: activeEventIndex
        )
    }

    private static func noteDelayDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        originalFrame: Int,
        eventIndex: Int?
    ) -> PlaybackSongSyntheticNoteDelayDiagnostic? {
        guard isNoteDelayEffect(cell) else {
            return nil
        }
        let tick = extendedEffectTick(cell)
        let rowSpeed = timingConfig.speed
        let rowBPM = timingConfig.bpm
        guard tick < rowSpeed else {
            return PlaybackSongSyntheticNoteDelayDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .outOfRowNoOp,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: true,
                outOfRow: true,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                originalFrame: originalFrame,
                delayedFrame: nil,
                eventIndex: eventIndex
            )
        }
        let delayedFrame = timingPlan.frameFor(row: syntheticRow, tick: tick)
        guard (1...96).contains(cell.note) else {
            return PlaybackSongSyntheticNoteDelayDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .noNoteDeferred,
                detected: true,
                applied: false,
                deferred: true,
                ignoredAsNoOp: false,
                outOfRow: false,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                originalFrame: originalFrame,
                delayedFrame: nil,
                eventIndex: eventIndex
            )
        }
        return PlaybackSongSyntheticNoteDelayDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: tick,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .applied,
            detected: true,
            applied: true,
            deferred: false,
            ignoredAsNoOp: false,
            outOfRow: false,
            requestedTick: tick,
            rowSpeed: rowSpeed,
            rowBPM: rowBPM,
            originalFrame: originalFrame,
            delayedFrame: delayedFrame,
            eventIndex: eventIndex
        )
    }

    private static func eventMapping(
        _ mapping: PlaybackSongSyntheticEventMapping,
        applying semantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: mapping.source,
            channelIndex: mapping.channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            selectedSampleLength: mapping.selectedSampleLength,
            sampleMapKeymapPresent: mapping.sampleMapKeymapPresent,
            mappedSampleIndex: mapping.mappedSampleIndex,
            mappedSampleValid: mapping.mappedSampleValid,
            sampleSelectionMethod: mapping.sampleSelectionMethod,
            sampleSelectionStrategy: mapping.sampleSelectionStrategy,
            firstPlayableSampleFallbackUsed: mapping.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: mapping.sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: mapping.sampleMapKeymapMissingOrDeferred,
            effectType: mapping.effectType,
            effectParam: mapping.effectParam,
            syntheticRow: mapping.syntheticRow,
            syntheticTick: mapping.syntheticTick,
            eventIndex: mapping.eventIndex,
            loopMode: mapping.loopMode,
            volumeColumn: mapping.volumeColumn,
            sampleOffset: mapping.sampleOffset,
            hasIgnoredVolumeColumn: mapping.hasIgnoredVolumeColumn,
            hasIgnoredEffect: mapping.hasIgnoredEffect,
            effectiveVolumeValue: mapping.effectiveVolumeValue,
            effectivePan: mapping.effectivePan,
            volumeEnvelopeStatus: mapping.volumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: mapping.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: mapping.mappedVolumeEnvelopePointCount,
            hasDeferredVolumeEnvelopeSustain: semantics.sustainDeferred,
            hasDeferredVolumeEnvelopeLoop: semantics.loopDeferred,
            hasDeferredVolumeEnvelopeFadeout: semantics.fadeoutDeferred,
            volumeEnvelopeSemantics: semantics,
            sampleBaseSampleRate: mapping.sampleBaseSampleRate,
            sampleRelativeNote: mapping.sampleRelativeNote,
            sampleFinetune: mapping.sampleFinetune,
            outputSampleRate: mapping.outputSampleRate,
            effectiveNoteValue: mapping.effectiveNoteValue,
            effectiveNoteIndex: mapping.effectiveNoteIndex,
            effectiveFinetune: mapping.effectiveFinetune,
            linearPeriod: mapping.linearPeriod,
            linearFrequency: mapping.linearFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    private static func retriggeredEventMapping(
        from mapping: PlaybackSongSyntheticEventMapping,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int,
        eventIndex: Int,
        effectType: UInt8,
        effectParam: UInt8,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        effectiveVolumeValue: Int,
        effectivePan: Float
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: source,
            channelIndex: channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            selectedSampleLength: mapping.selectedSampleLength,
            sampleMapKeymapPresent: mapping.sampleMapKeymapPresent,
            mappedSampleIndex: mapping.mappedSampleIndex,
            mappedSampleValid: mapping.mappedSampleValid,
            sampleSelectionMethod: mapping.sampleSelectionMethod,
            sampleSelectionStrategy: mapping.sampleSelectionStrategy,
            firstPlayableSampleFallbackUsed: mapping.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: mapping.sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: mapping.sampleMapKeymapMissingOrDeferred,
            effectType: effectType,
            effectParam: effectParam,
            syntheticRow: syntheticRow,
            syntheticTick: syntheticTick,
            eventIndex: eventIndex,
            loopMode: mapping.loopMode,
            volumeColumn: volumeColumn,
            sampleOffset: mapping.sampleOffset,
            hasIgnoredVolumeColumn: volumeColumn.rawValue != 0 && !volumeColumn.applied,
            hasIgnoredEffect: false,
            effectiveVolumeValue: effectiveVolumeValue,
            effectivePan: effectivePan,
            volumeEnvelopeStatus: mapping.volumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: mapping.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: mapping.mappedVolumeEnvelopePointCount,
            hasDeferredVolumeEnvelopeSustain: mapping.hasDeferredVolumeEnvelopeSustain,
            hasDeferredVolumeEnvelopeLoop: mapping.hasDeferredVolumeEnvelopeLoop,
            hasDeferredVolumeEnvelopeFadeout: mapping.hasDeferredVolumeEnvelopeFadeout,
            volumeEnvelopeSemantics: mapping.volumeEnvelopeSemantics,
            sampleBaseSampleRate: mapping.sampleBaseSampleRate,
            sampleRelativeNote: mapping.sampleRelativeNote,
            sampleFinetune: mapping.sampleFinetune,
            outputSampleRate: mapping.outputSampleRate,
            effectiveNoteValue: mapping.effectiveNoteValue,
            effectiveNoteIndex: mapping.effectiveNoteIndex,
            effectiveFinetune: mapping.effectiveFinetune,
            linearPeriod: mapping.linearPeriod,
            linearFrequency: mapping.linearFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    private struct VolumeEnvelopeMapping: Equatable {
        let envelope: MixerEnvelope?
        let status: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus
        let sourcePointCount: Int
        let mappedPointCount: Int
        let sustainFrame: Int?
        let loopStartFrame: Int?
        let loopEndFrame: Int?
    }

    private struct PlaybackStepMapping: Equatable {
        let playbackStep: Double
        let outputSampleRate: Double
        let effectiveNoteValue: Int?
        let effectiveNoteIndex: Int?
        let effectiveFinetune: Int?
        let linearPeriod: Double?
        let linearFrequency: Double?
        let finetuneStatus: PlaybackSongSyntheticEventMapping.FinetuneStatus
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus
        let linearFrequencyApplied: Bool
        let amigaFrequencyDeferred: Bool
        let applied: Bool
        let usedNeutralStep: Bool
    }

    private static func adaptedGain(
        sampleVolume: Float,
        channelVolume: Int
    ) -> Float {
        let baseGain = sampleVolume.isFinite ? sampleVolume : 0
        let volumeMultiplier = volumeMultiplier(for: channelVolume)
        // The bounded adapter treats supported XM volume-column volume commands as row-level
        // channel-volume updates: final event gain = sample volume * (channel volume / 64).
        // Parsed volume envelopes remain separate C mixer envelopes and multiply this gain at render time.
        return clampedGain(baseGain * volumeMultiplier)
    }

    private static func volumeMultiplier(for volumeValue: Int) -> Float {
        Float(clampedVolumeValue(volumeValue)) / 64.0
    }

    private static func clampedVolumeValue(_ value: Int) -> Int {
        min(64, max(0, value))
    }

    private static func clampedPanningValue(_ value: Double) -> Double {
        min(255.0, max(0.0, value.isFinite ? value : 127.5))
    }

    private static func clampedGain(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }

    private static func playbackStepMapping(
        note: UInt8,
        sample: PlaybackSample,
        usesLinearFrequencyTable: Bool,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackStepMapping {
        let outputSampleRate = timingConfig.sampleRate
        guard usesLinearFrequencyTable else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: nil,
                effectiveNoteIndex: nil,
                effectiveFinetune: nil,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .amigaTableDeferredNeutralFallback,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: true,
                applied: false,
                usedNeutralStep: true
            )
        }

        let baseSampleRate = sample.baseSampleRate
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: nil,
                effectiveNoteIndex: nil,
                effectiveFinetune: nil,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: sample.relativeNote)
        let effectiveNoteIndex = effectiveNoteValue - 1
        let effectiveFinetune = clampedFinetune(sample.finetune)

        // XM linear frequency mode is period based even though the C mixer consumes a source-sample step.
        // FT2's linear period formula is:
        // period = 7680 - (zeroBasedNote * 64) - (finetune / 2)
        // C-4 is note value 49, zero-based note 48, period 4608, so it maps to the sample base rate.
        let linearPeriod = xmLinearPeriodBase
            - (Double(effectiveNoteIndex) * xmLinearPeriodUnitsPerSemitone)
            - (Double(effectiveFinetune) / 2.0)
        let linearFrequency = baseSampleRate * pow(
            2.0,
            (xmLinearC4Period - linearPeriod) / xmLinearPeriodUnitsPerOctave
        )
        let step = linearFrequency / outputSampleRate
        guard linearPeriod.isFinite,
              linearFrequency.isFinite,
              linearFrequency > 0,
              step.isFinite,
              step > 0,
              step <= Double(UInt32.max) else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: effectiveNoteValue,
                effectiveNoteIndex: effectiveNoteIndex,
                effectiveFinetune: effectiveFinetune,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        return PlaybackStepMapping(
            playbackStep: step,
            outputSampleRate: outputSampleRate,
            effectiveNoteValue: effectiveNoteValue,
            effectiveNoteIndex: effectiveNoteIndex,
            effectiveFinetune: effectiveFinetune,
            linearPeriod: linearPeriod,
            linearFrequency: linearFrequency,
            finetuneStatus: .applied,
            frequencyTableStatus: .linearApplied,
            linearFrequencyApplied: true,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(step - 1.0) <= 0.000000001
        )
    }

    private static func clampedEffectiveNoteValue(note: UInt8, relativeNote: Int) -> Int {
        min(96, max(1, Int(note) + relativeNote))
    }

    private static func clampedFinetune(_ finetune: Int) -> Int {
        min(127, max(-128, finetune))
    }

    private static func mixerVolumeEnvelope(
        from envelope: PlaybackVolumeEnvelope,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> VolumeEnvelopeMapping {
        guard hasVolumeEnvelopeMetadata(envelope) else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .absent,
                sourcePointCount: 0,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }
        guard envelope.enabled else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .disabled,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        let sourcePoints = Array(envelope.points.prefix(maxMixerEnvelopePointCount))
        guard !sourcePoints.isEmpty else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: 0,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        let timing = SyntheticTrackerTiming(config: timingConfig)
        guard timing.framesPerTick.isFinite, timing.framesPerTick > 0 else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        var mappedPoints = [MixerEnvelopePoint]()
        mappedPoints.reserveCapacity(sourcePoints.count)
        for point in sourcePoints {
            let exactFrame = Double(point.tick) * timing.framesPerTick
            guard exactFrame.isFinite, exactFrame >= 0, exactFrame < Double(Int.max) else {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0,
                    sustainFrame: nil,
                    loopStartFrame: nil,
                    loopEndFrame: nil
                )
            }
            let frame = Int(exactFrame.rounded(.down))
            if let previous = mappedPoints.last, frame <= previous.positionFrame {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0,
                    sustainFrame: nil,
                    loopStartFrame: nil,
                    loopEndFrame: nil
                )
            }
            mappedPoints.append(MixerEnvelopePoint(positionFrame: frame, value: point.normalizedValue))
        }
        let sustainFrame = mappedFrame(
            forSourcePointIndex: envelope.sustainPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let loopStartFrame = mappedFrame(
            forSourcePointIndex: envelope.loopStartPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let loopEndFrame = mappedFrame(
            forSourcePointIndex: envelope.loopEndPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let appliedSustainFrame = envelopeSustainFlagSet(envelope) ? sustainFrame : nil
        let appliedLoopStartFrame: Int?
        let appliedLoopEndFrame: Int?
        if envelopeLoopFlagSet(envelope),
           let loopStartFrame,
           let loopEndFrame,
           loopEndFrame >= loopStartFrame {
            appliedLoopStartFrame = loopStartFrame
            appliedLoopEndFrame = loopEndFrame
        } else {
            appliedLoopStartFrame = nil
            appliedLoopEndFrame = nil
        }

        return VolumeEnvelopeMapping(
            envelope: MixerEnvelope(
                points: mappedPoints,
                sustainFrame: appliedSustainFrame,
                loopStartFrame: appliedLoopStartFrame,
                loopEndFrame: appliedLoopEndFrame
            ),
            status: .mapped,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mappedPoints.count,
            sustainFrame: appliedSustainFrame,
            loopStartFrame: appliedLoopStartFrame,
            loopEndFrame: appliedLoopEndFrame
        )
    }

    private static func mappedFrame(
        forSourcePointIndex pointIndex: Int?,
        sourcePoints: [PlaybackEnvelopePoint],
        mappedPoints: [MixerEnvelopePoint]
    ) -> Int? {
        guard let pointIndex,
              sourcePoints.indices.contains(pointIndex),
              mappedPoints.indices.contains(pointIndex) else {
            return nil
        }
        return mappedPoints[pointIndex].positionFrame
    }

    private static func hasVolumeEnvelopeMetadata(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        envelope.enabled ||
            !envelope.points.isEmpty ||
            envelope.typeFlags != 0 ||
            envelope.sustainPointIndex != nil ||
            envelope.loopStartPointIndex != nil ||
            envelope.loopEndPointIndex != nil ||
            envelope.fadeout > 0
    }

    private static func volumeEnvelopeSemantics(
        from envelope: PlaybackVolumeEnvelope,
        mapping: VolumeEnvelopeMapping
    ) -> PlaybackSongSyntheticEnvelopeSemanticsDiagnostic {
        let sustainEnabled = envelopeSustainFlagSet(envelope)
        let loopEnabled = envelopeLoopFlagSet(envelope)
        let sustainApplied = mapping.status == .mapped && sustainEnabled && mapping.sustainFrame != nil
        let loopApplied = mapping.status == .mapped && loopEnabled && mapping.loopStartFrame != nil && mapping.loopEndFrame != nil
        var limitations = [String]()
        if sustainApplied || loopApplied || envelope.fadeout > 0 {
            limitations.append("first_pass_bounded_offline_envelope_approximation")
        }
        if sustainApplied {
            limitations.append("sustain_holds_at_mapped_frame_while_keyed_on")
        }
        if loopApplied {
            limitations.append("envelope_loop_is_frame_based_while_keyed_on")
        }
        if envelope.fadeout > 0 {
            limitations.append("fadeout_uses_linear_per_frame_decrement_after_key_off")
        }

        return PlaybackSongSyntheticEnvelopeSemanticsDiagnostic(
            envelopeEnabled: envelope.enabled,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mapping.mappedPointCount,
            sustainEnabled: sustainEnabled,
            sustainApplied: sustainApplied,
            sustainDeferred: sustainEnabled && !sustainApplied,
            sustainPointIndex: envelope.sustainPointIndex,
            sustainTick: envelope.sustainPoint?.tick,
            sustainFrame: mapping.sustainFrame,
            loopEnabled: loopEnabled,
            loopApplied: loopApplied,
            loopDeferred: loopEnabled && !loopApplied,
            loopStartPointIndex: envelope.loopStartPointIndex,
            loopEndPointIndex: envelope.loopEndPointIndex,
            loopStartTick: envelope.loopStartPoint?.tick,
            loopEndTick: envelope.loopEndPoint?.tick,
            loopStartFrame: mapping.loopStartFrame,
            loopEndFrame: mapping.loopEndFrame,
            keyOffEncountered: false,
            keyOffApplied: false,
            keyOffDeferred: false,
            keyOffSource: nil,
            keyOffChannelIndex: nil,
            keyOffSyntheticRow: nil,
            keyOffSyntheticTick: nil,
            releaseFrame: nil,
            fadeoutValue: envelope.fadeout,
            fadeoutApplied: false,
            fadeoutDeferred: envelope.fadeout > 0,
            limitations: limitations
        )
    }

    private static func envelopeSustainFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x02) != 0
    }

    private static func envelopeLoopFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x04) != 0
    }

    private static func fadeoutFrameDecrement(fadeoutValue: Int, sampleRate: Double) -> Float {
        guard fadeoutValue > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        // First-pass offline approximation: spread the XM tick-domain fadeout decrement
        // smoothly across one default-speed tick worth of output frames.
        let framesPerDefaultTick = sampleRate * PlaybackTiming.xmDefault.tickDuration
        guard framesPerDefaultTick.isFinite, framesPerDefaultTick > 0 else {
            return 0
        }
        return Float((Double(fadeoutValue) / 65_536.0) / framesPerDefaultTick)
    }

    private static func extendedEffectSubcommand(_ cell: PlaybackCell) -> UInt8? {
        guard cell.effectType == 0x0E else {
            return nil
        }
        return (cell.effectParam >> 4) & 0x0F
    }

    private static func extendedEffectTick(_ cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    private static func isNoteCutEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0C
    }

    private static func isNoteDelayEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0D
    }

    private static func isRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x09
    }

    private static func sampleOffsetDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        selectedSampleLength: Int?
    ) -> PlaybackSongSyntheticSampleOffsetDiagnostic {
        let sampleLength = selectedSampleLength.map { max(0, $0) }
        guard cell.effectType == 0x09 else {
            return PlaybackSongSyntheticSampleOffsetDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .notPresent,
                detected: false,
                applied: false,
                deferred: false,
                ignoredAsNoOp: false,
                skipped: false,
                outOfRange: false,
                computedOffsetFrames: 0,
                appliedOffsetFrames: 0,
                selectedSampleLength: sampleLength
            )
        }

        let computedOffsetFrames = Int(cell.effectParam) * 256
        guard cell.effectParam != 0 else {
            return PlaybackSongSyntheticSampleOffsetDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .ignored900NoOp,
                detected: true,
                applied: false,
                deferred: true,
                ignoredAsNoOp: true,
                skipped: false,
                outOfRange: false,
                computedOffsetFrames: computedOffsetFrames,
                appliedOffsetFrames: 0,
                selectedSampleLength: sampleLength
            )
        }

        if let sampleLength, computedOffsetFrames >= sampleLength {
            return PlaybackSongSyntheticSampleOffsetDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .outOfRangeSkipped,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: false,
                skipped: true,
                outOfRange: true,
                computedOffsetFrames: computedOffsetFrames,
                appliedOffsetFrames: nil,
                selectedSampleLength: sampleLength
            )
        }

        return PlaybackSongSyntheticSampleOffsetDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .applied,
            detected: true,
            applied: true,
            deferred: false,
            ignoredAsNoOp: false,
            skipped: false,
            outOfRange: false,
            computedOffsetFrames: computedOffsetFrames,
            appliedOffsetFrames: computedOffsetFrames,
            selectedSampleLength: sampleLength
        )
    }

    private static func effectCommandDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic? {
        guard shouldReportEffectCommand(cell) else {
            return nil
        }
        return PlaybackSongSyntheticEffectCommandDiagnostic(
            source: source,
            channelIndex: channelIndex,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            decodedLabel: effectCommandLabel(effectType: cell.effectType, effectParam: cell.effectParam),
            status: effectCommandStatus(cell, timingConfig: timingConfig),
            isTraversalHazard: isTraversalHazard(cell)
        )
    }

    private static func shouldReportEffectCommand(_ cell: PlaybackCell) -> Bool {
        switch cell.effectType {
        case 0x08, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x11:
            return true
        default:
            return false
        }
    }

    private static func effectCommandStatus(
        _ cell: PlaybackCell,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic.Status {
        switch cell.effectType {
        case 0x08, 0x0C:
            return .applied
        case 0x0A:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x0F:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x11:
            return .deferredUnsupported
        case 0x0E where isRetriggerEffect(cell):
            let interval = extendedEffectTick(cell)
            guard interval > 0 else {
                return .ignoredNoOp
            }
            return interval < timingConfig.speed ? .applied : .ignoredNoOp
        case 0x0E where isNoteCutEffect(cell) || isNoteDelayEffect(cell):
            guard extendedEffectTick(cell) < timingConfig.speed else {
                return .ignoredNoOp
            }
            if isNoteDelayEffect(cell), !(1...96).contains(cell.note) {
                return .deferredUnsupported
            }
            return .applied
        case 0x0B, 0x0D, 0x0E:
            return .deferredUnsupported
        default:
            return .unknown
        }
    }

    private static func isTraversalHazard(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0B ||
            cell.effectType == 0x0D ||
            (cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x0E)
    }

    private static func effectCommandLabel(effectType: UInt8, effectParam: UInt8) -> String {
        switch effectType {
        case 0x08:
            return "8xx set panning"
        case 0x0A:
            return "Axy volume slide"
        case 0x0B:
            return "Bxx position jump"
        case 0x0C:
            return "Cxx set volume"
        case 0x0D:
            return "Dxx pattern break"
        case 0x0E:
            return extendedEffectCommandLabel(effectParam: effectParam)
        case 0x0F:
            return "Fxx speed/BPM"
        case 0x11:
            return "Hxy global volume slide"
        default:
            return "unknown/unsupported"
        }
    }

    private static func extendedEffectCommandLabel(effectParam: UInt8) -> String {
        switch (effectParam >> 4) & 0x0F {
        case 0x00:
            return "E0x filter toggle"
        case 0x01:
            return "E1x fine portamento up"
        case 0x02:
            return "E2x fine portamento down"
        case 0x03:
            return "E3x glissando control"
        case 0x04:
            return "E4x vibrato control"
        case 0x05:
            return "E5x set finetune"
        case 0x06:
            return "E6x pattern loop"
        case 0x07:
            return "E7x tremolo control"
        case 0x08:
            return "E8x set panning"
        case 0x09:
            return "E9x retrigger"
        case 0x0A:
            return "EAx fine volume slide up"
        case 0x0B:
            return "EBx fine volume slide down"
        case 0x0C:
            return "ECx note cut"
        case 0x0D:
            return "EDx note delay"
        case 0x0E:
            return "EEx pattern delay"
        case 0x0F:
            return "EFx invert loop"
        default:
            return "unknown/unsupported"
        }
    }

    private static func selectedSampleLength(_ sample: PlaybackSample) -> Int {
        min(max(0, sample.sampleLength), sample.pcm.count)
    }

    private static func hasEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType != 0 || cell.effectParam != 0
    }

    private static func hasDeferredEffect(_ cell: PlaybackCell) -> Bool {
        guard hasEffect(cell) else {
            return false
        }
        if PlaybackSongFxxTimingPlanner.isFxxTimingEffect(cell) ||
            isNonzeroSampleOffsetEffect(cell) ||
            isSupportedRetriggerEffect(cell) ||
            isNoteCutEffect(cell) ||
            isNoteDelayEffect(cell) {
            return false
        }
        switch cell.effectType {
        case 0x08, 0x0A, 0x0C:
            return false
        default:
            return true
        }
    }

    private static func isNonzeroSampleOffsetEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x09 && cell.effectParam != 0
    }

    private static func isSupportedRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        isRetriggerEffect(cell) && extendedEffectTick(cell) > 0
    }

    private static func selectSample(forNote note: UInt8, from instrument: PlaybackInstrument) -> SampleSelection {
        let mapPresent = instrument.hasNoteSampleMap
        let mappedSampleIndex = instrument.mappedSampleIndex(forNote: note)
        let mappedSample = mappedSampleIndex.flatMap { instrument.sample(mappedSampleIndex: $0) }
        let mappedSampleValid = mappedSample?.isPlayable == true
        let shouldUseMap = mapPresent && instrument.samples.count > 1
        let mapMissingOrDeferred = !mapPresent && instrument.samples.count > 1

        if shouldUseMap {
            if let mappedSample, mappedSample.isPlayable {
                return SampleSelection(
                    sample: mappedSample,
                    diagnosticSample: mappedSample,
                    skippedReason: nil,
                    sampleMapKeymapPresent: true,
                    mappedSampleIndex: mappedSampleIndex,
                    mappedSampleValid: true,
                    method: .sampleMap,
                    firstPlayableSampleFallbackUsed: false,
                    sampleMapKeymapBehaviorDeferred: false,
                    sampleMapKeymapMissingOrDeferred: false
                )
            }
            if let fallback = instrument.firstPlayableSample {
                return SampleSelection(
                    sample: fallback,
                    diagnosticSample: mappedSample ?? fallback,
                    skippedReason: nil,
                    sampleMapKeymapPresent: true,
                    mappedSampleIndex: mappedSampleIndex,
                    mappedSampleValid: mappedSampleValid,
                    method: .fallbackAfterInvalidMap,
                    firstPlayableSampleFallbackUsed: true,
                    sampleMapKeymapBehaviorDeferred: false,
                    sampleMapKeymapMissingOrDeferred: false
                )
            }
            return SampleSelection(
                sample: nil,
                diagnosticSample: mappedSample ?? instrument.samples.first,
                skippedReason: skippedReasonForInvalidMappedSample(mappedSample),
                sampleMapKeymapPresent: true,
                mappedSampleIndex: mappedSampleIndex,
                mappedSampleValid: false,
                method: .skippedNoValidSample,
                firstPlayableSampleFallbackUsed: false,
                sampleMapKeymapBehaviorDeferred: false,
                sampleMapKeymapMissingOrDeferred: false
            )
        }

        if let sample = instrument.firstPlayableSample {
            return SampleSelection(
                sample: sample,
                diagnosticSample: sample,
                skippedReason: nil,
                sampleMapKeymapPresent: mapPresent,
                mappedSampleIndex: mappedSampleIndex,
                mappedSampleValid: mappedSampleValid,
                method: .firstPlayableFallback,
                firstPlayableSampleFallbackUsed: true,
                sampleMapKeymapBehaviorDeferred: mapMissingOrDeferred,
                sampleMapKeymapMissingOrDeferred: mapMissingOrDeferred
            )
        }
        if let emptySample = instrument.samples.first(where: { $0.pcm.isEmpty }) {
            return SampleSelection(
                sample: nil,
                diagnosticSample: emptySample,
                skippedReason: .samplePCMEmpty,
                sampleMapKeymapPresent: mapPresent,
                mappedSampleIndex: mappedSampleIndex,
                mappedSampleValid: mappedSampleValid,
                method: .skippedNoValidSample,
                firstPlayableSampleFallbackUsed: false,
                sampleMapKeymapBehaviorDeferred: mapMissingOrDeferred,
                sampleMapKeymapMissingOrDeferred: mapMissingOrDeferred
            )
        }
        return SampleSelection(
            sample: nil,
            diagnosticSample: instrument.samples.first,
            skippedReason: .instrumentHasNoPlayableSample,
            sampleMapKeymapPresent: mapPresent,
            mappedSampleIndex: mappedSampleIndex,
            mappedSampleValid: mappedSampleValid,
            method: .skippedNoValidSample,
            firstPlayableSampleFallbackUsed: false,
            sampleMapKeymapBehaviorDeferred: mapMissingOrDeferred,
            sampleMapKeymapMissingOrDeferred: mapMissingOrDeferred
        )
    }

    private static func skippedReasonForInvalidMappedSample(
        _ sample: PlaybackSample?
    ) -> PlaybackSongSyntheticIgnoredCell.Reason {
        guard let sample else {
            return .noSelectedSampleForNote
        }
        if sample.pcm.isEmpty {
            return .samplePCMEmpty
        }
        return .instrumentHasNoPlayableSample
    }

    private static func ignoredCell(
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell,
        reason: PlaybackSongSyntheticIgnoredCell.Reason,
        diagnosticSample: PlaybackSample? = nil,
        sampleOffsetFrames: Int? = nil,
        sampleMapKeymapPresent: Bool = false,
        mappedSampleIndex: Int? = nil,
        mappedSampleValid: Bool = false,
        sampleSelectionMethod: PlaybackSongSyntheticSampleSelectionMethod = .skippedNoValidSample,
        firstPlayableSampleFallbackUsed: Bool = false,
        sampleMapKeymapBehaviorDeferred: Bool = false,
        sampleMapKeymapMissingOrDeferred: Bool = false,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        hasIgnoredVolumeColumn: Bool,
        hasIgnoredEffect: Bool
    ) -> PlaybackSongSyntheticIgnoredCell {
        PlaybackSongSyntheticIgnoredCell(
            source: source,
            channelIndex: channelIndex,
            note: cell.note,
            instrumentIndex: Int(cell.instrument),
            reason: reason,
            skipReason: skipReason(for: reason),
            selectedSampleIndex: diagnosticSample?.sampleIndex,
            selectedSampleLength: diagnosticSample.map(selectedSampleLength),
            selectedSampleLoopMode: diagnosticSample.map { mixerLoop(from: $0).mode },
            sampleMapKeymapPresent: sampleMapKeymapPresent,
            mappedSampleIndex: mappedSampleIndex,
            mappedSampleValid: mappedSampleValid,
            sampleSelectionMethod: sampleSelectionMethod,
            firstPlayableSampleFallbackUsed: firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: sampleMapKeymapMissingOrDeferred,
            sampleRelativeNote: diagnosticSample?.relativeNote,
            sampleFinetune: diagnosticSample?.finetune,
            sampleBaseSampleRate: diagnosticSample?.baseSampleRate,
            sampleOffsetFrames: sampleOffsetFrames,
            volumeColumn: volumeColumn,
            hasIgnoredVolumeColumn: hasIgnoredVolumeColumn,
            hasIgnoredEffect: hasIgnoredEffect
        )
    }

    private static func ignoredNoteReason(
        _ cell: PlaybackCell,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    ) -> PlaybackSongSyntheticIgnoredCell.Reason {
        switch cell.note {
        case 0:
            if cell.instrument > 0, cell.volumeColumn == 0, cell.effectType == 0, cell.effectParam == 0 {
                return .instrumentOnly
            }
            if hasDeferredEffect(cell) || volumeColumn.deferred {
                return .unsupportedDeferredEffectInteraction
            }
            return .emptyNote
        case 97:
            return .keyOff
        default:
            return .invalidNote
        }
    }

    private static func skipReason(for reason: PlaybackSongSyntheticIgnoredCell.Reason) -> PlaybackSongSyntheticSkipReason {
        switch reason {
        case .emptyNote:
            return .emptyCell
        case .instrumentOnly:
            return .instrumentOnly
        case .keyOff:
            return .noteOffKeyOffOnly
        case .invalidNote:
            return .invalidNote
        case .missingInstrument:
            return .missingInstrument
        case .unknownInstrument:
            return .unknownInstrument
        case .instrumentHasNoPlayableSample:
            return .instrumentHasNoPlayableSample
        case .samplePCMEmpty:
            return .samplePCMEmpty
        case .sampleOffsetOutOfRange:
            return .sampleOffsetOutOfRange
        case .noteDelayOutOfRow,
             .noteDelayWithoutNote:
            return .unsupportedDeferredEffectInteraction
        case .noSelectedSampleForNote:
            return .noSelectedSampleForNote
        case .unsupportedDeferredEffectInteraction:
            return .unsupportedDeferredEffectInteraction
        case .unknown:
            return .unknown
        }
    }

    private static func mixerLoop(from sample: PlaybackSample) -> MixerSampleLoop {
        let region = sample.loopRegion
        guard region.isEnabled else {
            return .none
        }
        switch region.loopType {
        case 1:
            return MixerSampleLoop(mode: .forward, startFrame: region.startFrame, endFrame: region.endFrame)
        case 2:
            return MixerSampleLoop(mode: .pingPong, startFrame: region.startFrame, endFrame: region.endFrame)
        default:
            return .none
        }
    }
}

/// Bounded offline render request for adapted `PlaybackSong` segments.
///
/// Oversized requests are clamped to `maximumFrameCount`, matching the existing software mixer offline
/// harness. This helper is offline-only and does not affect live `AVAudioPlayerNode` playback.
struct PlaybackSongOfflineRenderRequest: Equatable {
    static let defaultMaximumFrameCount = OfflineRenderRequest.defaultMaximumFrameCount

    let song: PlaybackSong
    let startOrderIndex: Int
    let orderCount: Int
    let config: MixerRenderConfig
    let requestedFrameCount: Int
    let maximumFrameCount: Int

    var boundedFrameCount: Int {
        min(requestedFrameCount, maximumFrameCount)
    }

    var wasFrameCountBounded: Bool {
        requestedFrameCount > maximumFrameCount
    }

    init(
        song: PlaybackSong,
        startOrderIndex: Int = 0,
        orderCount: Int = 1,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.song = song
        self.startOrderIndex = startOrderIndex
        self.orderCount = max(0, orderCount)
        self.config = config
        requestedFrameCount = max(0, frames)
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    init(
        song: PlaybackSong,
        orderIndex: Int,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.init(
            song: song,
            startOrderIndex: orderIndex,
            orderCount: 1,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        )
    }

    init(
        song: PlaybackSong,
        orderRange: Range<Int>,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.init(
            song: song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: orderRange.count,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        )
    }

    init(
        song: PlaybackSong,
        startOrderIndex: Int = 0,
        orderCount: Int = 1,
        config: MixerRenderConfig = MixerRenderConfig(),
        rows: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        let timing = PlaybackSongFxxTimingPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            sampleRate: config.sampleRate
        )
        self.init(
            song: song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            config: config,
            frames: timing.frameFor(row: max(0, rows), tick: 0),
            maximumFrameCount: maximumFrameCount
        )
    }

    func replacingFrameCount(_ frameCount: Int, maximumFrameCount: Int? = nil) -> PlaybackSongOfflineRenderRequest {
        PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            config: config,
            frames: frameCount,
            maximumFrameCount: maximumFrameCount ?? self.maximumFrameCount
        )
    }
}

/// Result from rendering an adapted `PlaybackSong` segment through the C-backed offline mixer.
struct PlaybackSongScheduledVoiceAttempt: Equatable {
    let eventIndex: Int
    let voiceIndex: Int?
    let rejectionReason: CSoftwareMixerScheduledVoiceRejectionReason?
    let windowIndex: Int?
}

struct PlaybackSongWindowedRenderWindowDiagnostic: Equatable {
    let windowIndex: Int
    let startRow: Int
    let endRowExclusive: Int
    let startFrame: Int
    let endFrame: Int
    let renderedFrames: Int
    let carriedVoiceCount: Int
    let releasedVoiceCarryoverCount: Int
    let boundaryContinuationCount: Int
    let droppedAtWindowBoundaryCount: Int
    let mayContainBoundaryCuts: Bool
    let unsupportedCarryoverReasons: [String]
    let scheduledEventCount: Int
    let acceptedScheduledEventCount: Int
    let rejectedScheduledEventCount: Int
    let scheduledCapacityRejectedCount: Int
    let invalidScheduledVoiceRejectedCount: Int
}

struct PlaybackSongWindowedRenderSummary: Equatable {
    static let firstRejectingWindowLimit = 10
    static let stateCarryoverLimitations = [
        "Windowed offline renders now carry practical active voice state across fresh C mixer windows.",
        "Carryover is computed from the bounded adapter plan and includes sample position, forward/ping-pong loop state, envelope position, key-off/release, fadeout, gain, and pan.",
        "Unsupported/deferred XM effects and full FT2/OpenMPT parity remain out of scope, so effect-driven continuity can still be approximate.",
    ]

    let windowRows: Int
    let windows: [PlaybackSongWindowedRenderWindowDiagnostic]
    let totalRenderedFrames: Int
    let totalCarriedVoices: Int
    let totalReleasedVoiceCarryovers: Int
    let totalBoundaryContinuations: Int
    let totalDroppedAtWindowBoundaries: Int
    let mayContainBoundaryCuts: Bool
    let totalScheduledEvents: Int
    let totalAcceptedScheduledEvents: Int
    let totalRejectedScheduledEvents: Int
    let totalScheduledCapacityRejects: Int
    let totalInvalidScheduledVoiceRejects: Int
    let knownUnsupportedCarryoverReasons: [String]
    let knownStateCarryoverLimitations: [String]

    var windowCount: Int {
        windows.count
    }

    var firstWindowsWithRejects: [PlaybackSongWindowedRenderWindowDiagnostic] {
        Array(windows.filter { $0.rejectedScheduledEventCount > 0 }.prefix(Self.firstRejectingWindowLimit))
    }
}

struct PlaybackSongOfflineRenderResult: Equatable {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let block: MixerRenderBlock
    let scheduledVoiceIndices: [Int?]
    let scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]
    let scheduledVoiceAttempts: [PlaybackSongScheduledVoiceAttempt]
    let windowedRenderSummary: PlaybackSongWindowedRenderSummary?
    let exportDiagnostics: MixerWAVExportDiagnostics?

    init(
        request: PlaybackSongOfflineRenderRequest,
        plan: PlaybackSongSyntheticPlan,
        block: MixerRenderBlock,
        scheduledVoiceIndices: [Int?],
        scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?] = [],
        scheduledVoiceAttempts: [PlaybackSongScheduledVoiceAttempt]? = nil,
        windowedRenderSummary: PlaybackSongWindowedRenderSummary? = nil,
        exportDiagnostics: MixerWAVExportDiagnostics? = nil
    ) {
        self.request = request
        self.plan = plan
        self.block = block
        self.scheduledVoiceIndices = scheduledVoiceIndices
        let normalizedRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]
        if scheduledVoiceRejectionReasons.count == scheduledVoiceIndices.count {
            normalizedRejectionReasons = scheduledVoiceRejectionReasons
        } else {
            normalizedRejectionReasons = scheduledVoiceIndices.map { $0 == nil ? .invalidScheduledVoice : nil }
        }
        self.scheduledVoiceRejectionReasons = normalizedRejectionReasons
        self.scheduledVoiceAttempts = scheduledVoiceAttempts ?? scheduledVoiceIndices.enumerated().map { eventIndex, voiceIndex in
            PlaybackSongScheduledVoiceAttempt(
                eventIndex: eventIndex,
                voiceIndex: voiceIndex,
                rejectionReason: normalizedRejectionReasons.indices.contains(eventIndex) ? normalizedRejectionReasons[eventIndex] : nil,
                windowIndex: nil
            )
        }
        self.windowedRenderSummary = windowedRenderSummary
        self.exportDiagnostics = exportDiagnostics
    }

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    var requestedFrameCount: Int {
        request.requestedFrameCount
    }

    var renderedFrameCount: Int {
        block.frameCount
    }

    var maximumFrameCount: Int {
        request.maximumFrameCount
    }

    var wasFrameCountBounded: Bool {
        request.wasFrameCountBounded
    }

    func replacingExportDiagnostics(
        _ diagnostics: MixerWAVExportDiagnostics?
    ) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderResult(
            request: request,
            plan: plan,
            block: block,
            scheduledVoiceIndices: scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: scheduledVoiceRejectionReasons,
            scheduledVoiceAttempts: scheduledVoiceAttempts,
            windowedRenderSummary: windowedRenderSummary,
            exportDiagnostics: diagnostics
        )
    }
}

/// Prepared offline render session for split renders and reset determinism checks.
final class PlaybackSongOfflineRenderSession {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let scheduledVoiceIndices: [Int?]
    let scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]

    private let mixer: CSoftwareMixer
    private var renderedFrameCount = 0

    var config: MixerRenderConfig {
        mixer.config
    }

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    init(request: PlaybackSongOfflineRenderRequest) {
        self.request = request
        let adaptedPlan = PlaybackSongSyntheticAdapter.adapt(
            request.song,
            startOrderIndex: request.startOrderIndex,
            orderCount: request.orderCount,
            sampleRate: request.config.sampleRate
        )
        let preparedMixer = CSoftwareMixer(config: request.config)
        let scheduledResults = SyntheticPatternScheduler(config: adaptedPlan.timingConfig).scheduleWithResults(adaptedPlan.pattern, on: preparedMixer)
        let voiceIndices = scheduledResults.map(\.voiceIndex)
        PlaybackSongOfflineRenderer.scheduleVoiceStateUpdates(
            adaptedPlan.diagnostics.voiceStateUpdates,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer
        )
        PlaybackSongOfflineRenderer.scheduleNoteCuts(
            adaptedPlan.diagnostics.noteCutEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer
        )
        PlaybackSongOfflineRenderer.scheduleRetriggerCuts(
            adaptedPlan.diagnostics.retriggerEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer
        )
        let rejectionReasons = scheduledResults.map(\.rejectionReason)
        let scheduledCapacityRejectedCount = rejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count
        let eventCoverage = adaptedPlan.diagnostics.eventCoverage
            .reportingCMixerVoiceCapacityRejections(scheduledCapacityRejectedCount)
        plan = adaptedPlan.replacingEventCoverage(eventCoverage)
        mixer = preparedMixer
        scheduledVoiceIndices = voiceIndices
        scheduledVoiceRejectionReasons = rejectionReasons
    }

    func render(frames: Int) -> MixerRenderBlock {
        let requestedFrames = max(0, frames)
        let remainingFrames = max(0, request.boundedFrameCount - renderedFrameCount)
        let frameCount = min(requestedFrames, remainingFrames)
        let block = mixer.render(frames: frameCount)
        renderedFrameCount += block.frameCount
        return block
    }

    func reset() {
        mixer.reset()
        renderedFrameCount = 0
    }

    private static func voiceIndexByEventIndex(from voiceIndices: [Int?]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: voiceIndices.enumerated().compactMap { eventIndex, voiceIndex in
            voiceIndex.map { (eventIndex, $0) }
        })
    }
}

/// Offline renderer for tiny bounded `PlaybackSong` adapter segments.
///
/// This renderer adapts a bounded playback-model order selection, schedules the resulting synthetic pattern
/// through `CSoftwareMixer`, and returns the in-memory PCM block with adapter diagnostics. It intentionally
/// does not implement full XM playback, FT2/OpenMPT resampler parity, effect-column commands beyond minimal
/// `Fxx`, full volume-column semantics, full FT2/OpenMPT envelope parity, runtime backend switching,
/// or app Play button wiring.
final class PlaybackSongOfflineRenderer {
    let maximumFrameCount: Int

    init(maximumFrameCount: Int = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount) {
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    func prepare(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderSession {
        PlaybackSongOfflineRenderSession(request: effectiveRequest(from: request, frames: request.requestedFrameCount))
    }

    func render(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: session.render(frames: effectiveRequest.boundedFrameCount),
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons
        )
    }

    func renderWindowed(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic) -> Void)? = nil
    ) -> PlaybackSongOfflineRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let safeWindowRows = max(1, windowRows)
        let adaptedPlan = PlaybackSongSyntheticAdapter.adapt(
            effectiveRequest.song,
            startOrderIndex: effectiveRequest.startOrderIndex,
            orderCount: effectiveRequest.orderCount,
            sampleRate: effectiveRequest.config.sampleRate
        )
        let totalFrames = effectiveRequest.boundedFrameCount
        let windows = Self.windowSpecs(
            for: adaptedPlan,
            totalFrames: totalFrames,
            windowRows: safeWindowRows
        )
        let scheduler = SyntheticTrackerScheduler(config: adaptedPlan.timingConfig)
        var renderedFrames = 0
        var interleavedPCM = [Float]()
        interleavedPCM.reserveCapacity(totalFrames * effectiveRequest.config.channelCount)
        var attempts = [PlaybackSongScheduledVoiceAttempt]()
        var windowDiagnostics = [PlaybackSongWindowedRenderWindowDiagnostic]()
        var outputConfig = CSoftwareMixer(config: effectiveRequest.config).config
        let knownUnsupportedCarryoverReasons = Self.knownUnsupportedCarryoverReasons(for: adaptedPlan)

        for spec in windows {
            let mixer = CSoftwareMixer(config: effectiveRequest.config)
            outputConfig = mixer.config
            let eventPairs = Self.eventPairs(
                in: spec,
                plan: adaptedPlan,
                scheduler: scheduler
            )
            let continuations = Self.continuations(
                for: spec,
                plan: adaptedPlan,
                scheduler: scheduler
            )
            var continuationResults = [CSoftwareMixerScheduledVoiceResult]()
            continuationResults.reserveCapacity(continuations.count)
            for continuation in continuations {
                let result = Self.scheduleContinuation(continuation, on: mixer)
                continuationResults.append(result)
                attempts.append(PlaybackSongScheduledVoiceAttempt(
                    eventIndex: continuation.eventIndex,
                    voiceIndex: result.voiceIndex,
                    rejectionReason: result.rejectionReason,
                    windowIndex: spec.index
                ))
            }
            let localEvents = eventPairs.map { _, event in
                Self.localEvent(from: event, windowStartFrame: spec.startFrame, scheduler: scheduler)
            }
            let scheduledResults = scheduler.scheduleWithResults(localEvents, on: mixer)
            var voiceIndexByEventIndex = [Int: Int]()
            for (continuation, result) in zip(continuations, continuationResults) {
                if let voiceIndex = result.voiceIndex {
                    voiceIndexByEventIndex[continuation.eventIndex] = voiceIndex
                }
            }
            for (pair, result) in zip(eventPairs, scheduledResults) {
                if let voiceIndex = result.voiceIndex {
                    voiceIndexByEventIndex[pair.offset] = voiceIndex
                }
            }
            Self.scheduleVoiceStateUpdates(
                adaptedPlan.diagnostics.voiceStateUpdates,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame
            )
            Self.scheduleNoteCuts(
                adaptedPlan.diagnostics.noteCutEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame
            )
            Self.scheduleRetriggerCuts(
                adaptedPlan.diagnostics.retriggerEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame
            )
            attempts.append(contentsOf: zip(eventPairs, scheduledResults).map { pair, result in
                PlaybackSongScheduledVoiceAttempt(
                    eventIndex: pair.offset,
                    voiceIndex: result.voiceIndex,
                    rejectionReason: result.rejectionReason,
                    windowIndex: spec.index
                )
            })

            let block = mixer.render(frames: spec.frameCount)
            renderedFrames += block.frameCount
            interleavedPCM.append(contentsOf: block.interleavedPCM)

            let droppedContinuations = continuationResults.filter { $0.rejectionReason != nil }.count
            let diagnostic = PlaybackSongWindowedRenderWindowDiagnostic(
                windowIndex: spec.index,
                startRow: spec.startRow,
                endRowExclusive: spec.endRowExclusive,
                startFrame: spec.startFrame,
                endFrame: spec.endFrame,
                renderedFrames: block.frameCount,
                carriedVoiceCount: continuationResults.filter(\.wasAccepted).count,
                releasedVoiceCarryoverCount: continuations.filter { !$0.runtimeState.keyOn }.count,
                boundaryContinuationCount: continuations.count,
                droppedAtWindowBoundaryCount: droppedContinuations,
                mayContainBoundaryCuts: droppedContinuations > 0,
                unsupportedCarryoverReasons: spec.index == 0 ? [] : knownUnsupportedCarryoverReasons,
                scheduledEventCount: scheduledResults.count + continuationResults.count,
                acceptedScheduledEventCount: scheduledResults.filter(\.wasAccepted).count + continuationResults.filter(\.wasAccepted).count,
                rejectedScheduledEventCount: scheduledResults.filter { $0.rejectionReason != nil }.count + continuationResults.filter { $0.rejectionReason != nil }.count,
                scheduledCapacityRejectedCount: scheduledResults.filter { $0.rejectionReason == .scheduledVoiceCapacity }.count + continuationResults.filter { $0.rejectionReason == .scheduledVoiceCapacity }.count,
                invalidScheduledVoiceRejectedCount: scheduledResults.filter { $0.rejectionReason == .invalidScheduledVoice }.count + continuationResults.filter { $0.rejectionReason == .invalidScheduledVoice }.count
            )
            windowDiagnostics.append(diagnostic)
            progress?(spec.index + 1, windows.count, diagnostic)
        }

        let scheduledCapacityRejectedCount = attempts.filter { $0.rejectionReason == .scheduledVoiceCapacity }.count
        let eventCoverage = adaptedPlan.diagnostics.eventCoverage
            .reportingCMixerVoiceCapacityRejections(scheduledCapacityRejectedCount)
        let finalPlan = adaptedPlan.replacingEventCoverage(eventCoverage)
        let block = MixerRenderBlock(
            config: outputConfig,
            frameCount: renderedFrames,
            interleavedPCM: interleavedPCM
        )
        let summary = PlaybackSongWindowedRenderSummary(
            windowRows: safeWindowRows,
            windows: windowDiagnostics,
            totalRenderedFrames: renderedFrames,
            totalCarriedVoices: windowDiagnostics.map(\.carriedVoiceCount).reduce(0, +),
            totalReleasedVoiceCarryovers: windowDiagnostics.map(\.releasedVoiceCarryoverCount).reduce(0, +),
            totalBoundaryContinuations: windowDiagnostics.map(\.boundaryContinuationCount).reduce(0, +),
            totalDroppedAtWindowBoundaries: windowDiagnostics.map(\.droppedAtWindowBoundaryCount).reduce(0, +),
            mayContainBoundaryCuts: windowDiagnostics.contains { $0.mayContainBoundaryCuts },
            totalScheduledEvents: attempts.count,
            totalAcceptedScheduledEvents: attempts.filter { $0.voiceIndex != nil }.count,
            totalRejectedScheduledEvents: attempts.filter { $0.rejectionReason != nil }.count,
            totalScheduledCapacityRejects: scheduledCapacityRejectedCount,
            totalInvalidScheduledVoiceRejects: attempts.filter { $0.rejectionReason == .invalidScheduledVoice }.count,
            knownUnsupportedCarryoverReasons: knownUnsupportedCarryoverReasons,
            knownStateCarryoverLimitations: PlaybackSongWindowedRenderSummary.stateCarryoverLimitations
        )
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: finalPlan,
            block: block,
            scheduledVoiceIndices: attempts.map(\.voiceIndex),
            scheduledVoiceRejectionReasons: attempts.map(\.rejectionReason),
            scheduledVoiceAttempts: attempts,
            windowedRenderSummary: summary
        )
    }

    func render(_ request: PlaybackSongOfflineRenderRequest, splitFrameCounts: [Int]) -> PlaybackSongOfflineRenderResult {
        let requestedFrames = splitFrameCounts.reduce(0) { partialResult, frames in
            let safeFrames = max(0, frames)
            guard partialResult <= Int.max - safeFrames else {
                return Int.max
            }
            return partialResult + safeFrames
        }
        let effectiveRequest = effectiveRequest(from: request, frames: requestedFrames)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
        var remainingFrames = effectiveRequest.boundedFrameCount
        var interleavedPCM = [Float]()
        for requestedChunkFrames in splitFrameCounts where remainingFrames > 0 {
            let chunkFrames = min(max(0, requestedChunkFrames), remainingFrames)
            let chunk = session.render(frames: chunkFrames)
            interleavedPCM.append(contentsOf: chunk.interleavedPCM)
            remainingFrames -= chunk.frameCount
        }
        let block = MixerRenderBlock(
            config: session.config,
            frameCount: effectiveRequest.boundedFrameCount - remainingFrames,
            interleavedPCM: interleavedPCM
        )
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: block,
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons
        )
    }

    fileprivate static func scheduleVoiceStateUpdates(
        _ updates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil
    ) {
        for update in updates where update.activeVoiceUpdated {
            guard let activeEventIndex = update.activeEventIndex,
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            guard update.scheduledFrame >= windowStartFrame else {
                continue
            }
            if let windowEndFrame,
               update.scheduledFrame >= windowEndFrame {
                continue
            }
            let gain = changedGain(from: update)
            let pan = changedPan(from: update)
            guard gain != nil || pan != nil else {
                continue
            }
            _ = mixer.scheduleVoiceGainPanUpdate(
                voiceIndex: voiceIndex,
                scheduledFrame: update.scheduledFrame - windowStartFrame,
                gain: gain,
                pan: pan
            )
        }
    }

    fileprivate static func scheduleNoteCuts(
        _ cuts: [PlaybackSongSyntheticNoteCutDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil
    ) {
        for cut in cuts where cut.applied {
            guard let activeEventIndex = cut.activeEventIndex,
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex],
                  let scheduledFrame = cut.scheduledFrame else {
                continue
            }
            guard scheduledFrame >= windowStartFrame else {
                continue
            }
            if let windowEndFrame,
               scheduledFrame >= windowEndFrame {
                continue
            }
            _ = mixer.scheduleVoiceGainPanImmediateUpdate(
                voiceIndex: voiceIndex,
                scheduledFrame: scheduledFrame - windowStartFrame,
                gain: 0,
                pan: nil
            )
        }
    }

    fileprivate static func scheduleRetriggerCuts(
        _ retriggers: [PlaybackSongSyntheticRetriggerDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil
    ) {
        for retrigger in retriggers where retrigger.applied {
            for (eventIndex, scheduledFrame) in zip(retrigger.replacedEventIndices, retrigger.retriggerFrames) {
                guard let voiceIndex = voiceIndexByEventIndex[eventIndex] else {
                    continue
                }
                guard scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoiceGainPanImmediateUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: scheduledFrame - windowStartFrame,
                    gain: 0,
                    pan: nil
                )
            }
        }
    }

    private static func changedGain(
        from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Float? {
        guard let before = update.gainBefore,
              let after = update.gainAfter,
              before != after else {
            return nil
        }
        return after
    }

    private static func changedPan(
        from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Float? {
        guard let before = update.panBefore,
              let after = update.panAfter,
              before != after else {
            return nil
        }
        return after
    }

    /// Renders a bounded adapted `PlaybackSong` segment through the offline C-backed mixer and writes PCM16 WAV.
    ///
    /// This is a local comparison helper only. It reuses the existing bounded render path and does not parse
    /// modules, traverse full songs, compare against reference renderers, or change live playback.
    @discardableResult
    func exportWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to url: URL,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> PlaybackSongOfflineRenderResult {
        let result = render(request)
        let diagnostics = try MixerWAVExporter.writePCM16WAV(from: result.block, to: url, exportPolicy: exportPolicy)
        return result.replacingExportDiagnostics(diagnostics)
    }

    @discardableResult
    func exportWindowedWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to url: URL,
        windowRows: Int,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> PlaybackSongOfflineRenderResult {
        let result = renderWindowed(request, windowRows: windowRows)
        let diagnostics = try MixerWAVExporter.writePCM16WAV(from: result.block, to: url, exportPolicy: exportPolicy)
        return result.replacingExportDiagnostics(diagnostics)
    }

    private func effectiveRequest(
        from request: PlaybackSongOfflineRenderRequest,
        frames: Int
    ) -> PlaybackSongOfflineRenderRequest {
        request.replacingFrameCount(
            frames,
            maximumFrameCount: min(request.maximumFrameCount, maximumFrameCount)
        )
    }

    private struct RenderWindowSpec: Equatable {
        let index: Int
        let startRow: Int
        let endRowExclusive: Int
        let startFrame: Int
        let endFrame: Int

        var frameCount: Int {
            max(0, endFrame - startFrame)
        }
    }

    private struct WindowContinuation: Equatable {
        let eventIndex: Int
        let event: SyntheticTrackerEvent
        let runtimeState: CSoftwareMixerVoiceRuntimeState
        let keyOffFrame: Int?
    }

    private struct SourcePositionState: Equatable {
        let samplePosition: Double
        let pingPongDirection: Int
    }

    private struct GainPanRampSimulation: Equatable {
        let start: Float
        let target: Float
        let scheduledFrame: Int
        let totalFrames: Int

        func value(at frame: Int) -> Float {
            let elapsedFrames = max(0, frame - scheduledFrame)
            let progressFrame = min(totalFrames, elapsedFrames + 1)
            let progress = Float(progressFrame) / Float(totalFrames)
            return start + ((target - start) * progress)
        }

        func runtimeState(at boundaryFrame: Int) -> CSoftwareMixerValueRampRuntimeState? {
            let elapsedFrames = boundaryFrame - scheduledFrame
            guard elapsedFrames >= 0,
                  elapsedFrames < totalFrames else {
                return nil
            }
            return CSoftwareMixerValueRampRuntimeState(
                start: start,
                target: target,
                totalFrames: totalFrames,
                positionFrame: elapsedFrames
            )
        }
    }

    private struct GainPanStateAtBoundary: Equatable {
        let gain: Float
        let pan: Float
        let gainRamp: CSoftwareMixerValueRampRuntimeState?
        let panRamp: CSoftwareMixerValueRampRuntimeState?
    }

    private static func windowSpecs(
        for plan: PlaybackSongSyntheticPlan,
        totalFrames: Int,
        windowRows: Int
    ) -> [RenderWindowSpec] {
        guard totalFrames > 0 else {
            return []
        }
        let safeWindowRows = max(1, windowRows)
        let syntheticRowCount = max(0, plan.diagnostics.syntheticRowCount)
        guard syntheticRowCount > 0 else {
            return [
                RenderWindowSpec(
                    index: 0,
                    startRow: 0,
                    endRowExclusive: 0,
                    startFrame: 0,
                    endFrame: totalFrames
                )
            ]
        }

        let rowStartFrames = Dictionary(
            uniqueKeysWithValues: plan.diagnostics.rowTiming.map { ($0.syntheticRow, $0.rowStartFrame) }
        )
        var specs = [RenderWindowSpec]()
        var startRow = 0
        while startRow < syntheticRowCount {
            let endRow = min(syntheticRowCount, startRow + safeWindowRows)
            let startFrame = min(totalFrames, max(0, rowStartFrames[startRow] ?? specs.last?.endFrame ?? 0))
            let plannedEndFrame = endRow < syntheticRowCount
                ? (rowStartFrames[endRow] ?? totalFrames)
                : totalFrames
            let endFrame = min(totalFrames, max(startFrame, plannedEndFrame))
            if startFrame < totalFrames, endFrame > startFrame {
                specs.append(RenderWindowSpec(
                    index: specs.count,
                    startRow: startRow,
                    endRowExclusive: endRow,
                    startFrame: startFrame,
                    endFrame: endFrame
                ))
            }
            startRow = endRow
        }
        if specs.isEmpty {
            return [
                RenderWindowSpec(
                    index: 0,
                    startRow: 0,
                    endRowExclusive: 0,
                    startFrame: 0,
                    endFrame: totalFrames
                )
            ]
        }
        return specs
    }

    private static func continuations(
        for window: RenderWindowSpec,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler
    ) -> [WindowContinuation] {
        let windowStartFrame = window.startFrame
        guard windowStartFrame > 0 else {
            return []
        }
        let latestEventIndexByChannel = latestEventIndicesByChannel(
            atOrBefore: windowStartFrame,
            plan: plan,
            scheduler: scheduler
        )
        let mappingsByEventIndex = Dictionary(uniqueKeysWithValues: plan.diagnostics.eventMappings.map { ($0.eventIndex, $0) })
        return plan.pattern.events.enumerated().compactMap { eventIndex, event in
            let eventStartFrame = scheduler.frame(for: event)
            guard eventStartFrame < windowStartFrame else {
                return nil
            }
            if let mapping = mappingsByEventIndex[eventIndex],
               let latestEventIndex = latestEventIndexByChannel[mapping.channelIndex],
               latestEventIndex != eventIndex {
                return nil
            }
            if hasAppliedNoteCut(
                eventIndex: eventIndex,
                before: windowStartFrame,
                plan: plan
            ) {
                return nil
            }
            let gainPanState = gainPanStateAtBoundary(
                for: event,
                eventIndex: eventIndex,
                plan: plan,
                before: windowStartFrame
            )
            let carriedEvent = event.withGainPan(gain: gainPanState.gain, pan: gainPanState.pan)
            return continuation(
                eventIndex: eventIndex,
                event: carriedEvent,
                eventStartFrame: eventStartFrame,
                boundaryFrame: windowStartFrame,
                gainRamp: gainPanState.gainRamp,
                panRamp: gainPanState.panRamp
            )
        }
    }

    private static func gainPanStateAtBoundary(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        before boundaryFrame: Int
    ) -> GainPanStateAtBoundary {
        var gain = event.gain
        var pan = event.pan
        var gainRamp: GainPanRampSimulation?
        var panRamp: GainPanRampSimulation?
        let rampFrames = CSoftwareMixer.gainPanUpdateRampFrameCount

        for update in plan.diagnostics.voiceStateUpdates {
            guard update.activeVoiceUpdated,
                  update.activeEventIndex == eventIndex,
                  update.scheduledFrame < boundaryFrame else {
                continue
            }
            if let target = changedGain(from: update) {
                let start = effectiveValue(
                    fallback: gain,
                    ramp: gainRamp,
                    at: update.scheduledFrame
                )
                gainRamp = GainPanRampSimulation(
                    start: start,
                    target: target,
                    scheduledFrame: update.scheduledFrame,
                    totalFrames: rampFrames
                )
                gain = target
            }
            if let target = changedPan(from: update) {
                let start = effectiveValue(
                    fallback: pan,
                    ramp: panRamp,
                    at: update.scheduledFrame
                )
                panRamp = GainPanRampSimulation(
                    start: start,
                    target: target,
                    scheduledFrame: update.scheduledFrame,
                    totalFrames: rampFrames
                )
                pan = target
            }
        }
        let effectiveGain = effectiveValue(fallback: gain, ramp: gainRamp, at: boundaryFrame)
        let effectivePan = effectiveValue(fallback: pan, ramp: panRamp, at: boundaryFrame)
        return GainPanStateAtBoundary(
            gain: gainRamp?.runtimeState(at: boundaryFrame)?.target ?? effectiveGain,
            pan: panRamp?.runtimeState(at: boundaryFrame)?.target ?? effectivePan,
            gainRamp: gainRamp?.runtimeState(at: boundaryFrame),
            panRamp: panRamp?.runtimeState(at: boundaryFrame)
        )
    }

    private static func effectiveValue(
        fallback: Float,
        ramp: GainPanRampSimulation?,
        at frame: Int
    ) -> Float {
        guard let ramp else {
            return fallback
        }
        if frame - ramp.scheduledFrame >= ramp.totalFrames {
            return ramp.target
        }
        return ramp.value(at: frame)
    }

    private static func hasAppliedNoteCut(
        eventIndex: Int,
        before boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.diagnostics.noteCutEffects.contains { cut in
            cut.applied &&
                cut.activeEventIndex == eventIndex &&
                (cut.scheduledFrame ?? Int.max) < boundaryFrame
        }
    }

    private static func latestEventIndicesByChannel(
        atOrBefore boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler
    ) -> [Int: Int] {
        var latestByChannel = [Int: (frame: Int, eventIndex: Int)]()
        for mapping in plan.diagnostics.eventMappings {
            guard plan.pattern.events.indices.contains(mapping.eventIndex) else {
                continue
            }
            let frame = scheduler.frame(for: plan.pattern.events[mapping.eventIndex])
            guard frame <= boundaryFrame else {
                continue
            }
            if let existing = latestByChannel[mapping.channelIndex] {
                if frame > existing.frame ||
                    (frame == existing.frame && mapping.eventIndex > existing.eventIndex) {
                    latestByChannel[mapping.channelIndex] = (frame, mapping.eventIndex)
                }
            } else {
                latestByChannel[mapping.channelIndex] = (frame, mapping.eventIndex)
            }
        }
        return latestByChannel.mapValues(\.eventIndex)
    }

    private static func continuation(
        eventIndex: Int,
        event: SyntheticTrackerEvent,
        eventStartFrame: Int,
        boundaryFrame: Int,
        gainRamp: CSoftwareMixerValueRampRuntimeState?,
        panRamp: CSoftwareMixerValueRampRuntimeState?
    ) -> WindowContinuation? {
        let elapsedFrames = max(0, boundaryFrame - eventStartFrame)
        guard elapsedFrames > 0,
              let sourceState = sourcePositionState(for: event, elapsedFrames: elapsedFrames) else {
            return nil
        }
        let keyOffFrame = event.keyOffFrame
        let keyOn = keyOffFrame.map { boundaryFrame <= $0 } ?? true
        let keyedFrames = keyedFrameCount(
            elapsedFrames: elapsedFrames,
            eventStartFrame: eventStartFrame,
            keyOffFrame: keyOffFrame
        )
        let releasedFrames = releasedFrameCount(
            boundaryFrame: boundaryFrame,
            keyOffFrame: keyOffFrame
        )
        let fadeoutValue = fadeoutValue(
            releasedFrames: releasedFrames,
            decrementPerFrame: event.fadeoutFrameDecrement
        )
        guard fadeoutValue > 0 else {
            return nil
        }
        let volumeEnvelopePosition = envelopePosition(
            for: event.volumeEnvelope,
            keyedFrames: keyedFrames,
            releasedFrames: releasedFrames
        )
        let panEnvelopePosition = envelopePosition(
            for: event.panEnvelope,
            keyedFrames: keyedFrames,
            releasedFrames: releasedFrames
        )
        let localKeyOffFrame: Int?
        if let keyOffFrame {
            localKeyOffFrame = max(0, keyOffFrame - boundaryFrame)
        } else {
            localKeyOffFrame = nil
        }
        return WindowContinuation(
            eventIndex: eventIndex,
            event: event,
            runtimeState: CSoftwareMixerVoiceRuntimeState(
                samplePosition: sourceState.samplePosition,
                pingPongDirection: sourceState.pingPongDirection,
                volumeEnvelopePositionFrame: volumeEnvelopePosition,
                panEnvelopePositionFrame: panEnvelopePosition,
                keyOn: keyOn,
                fadeoutValue: fadeoutValue,
                gainRamp: gainRamp,
                panRamp: panRamp
            ),
            keyOffFrame: localKeyOffFrame
        )
    }

    private static func scheduleContinuation(
        _ continuation: WindowContinuation,
        on mixer: CSoftwareMixer
    ) -> CSoftwareMixerScheduledVoiceResult {
        let event = continuation.event
        let result = mixer.addScheduledVoiceWithResult(
            sample: event.sample,
            scheduledStartFrame: 0,
            gain: event.gain,
            pan: event.pan,
            playbackStep: event.playbackStep,
            loop: event.loop,
            initialSourceFrame: Int(continuation.runtimeState.samplePosition.rounded(.down)),
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: continuation.keyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
        if let voiceIndex = result.voiceIndex {
            mixer.setRuntimeState(continuation.runtimeState, forVoiceAt: voiceIndex)
        }
        return result
    }

    private static func sourcePositionState(
        for event: SyntheticTrackerEvent,
        elapsedFrames: Int
    ) -> SourcePositionState? {
        let sampleFrameCount = event.sample.frameCount
        guard sampleFrameCount > 0,
              event.playbackStep.isFinite,
              event.playbackStep > 0 else {
            return nil
        }
        let sanitizedLoop = event.loop.sanitized(sampleFrameCount: sampleFrameCount)
        let initialPosition = Double(max(0, event.initialSourceFrame))
        guard initialPosition < Double(sampleFrameCount) else {
            return nil
        }
        let advancedPosition = initialPosition + (Double(elapsedFrames) * event.playbackStep)
        guard advancedPosition.isFinite,
              advancedPosition >= 0,
              advancedPosition <= Double(UInt32.max) else {
            return nil
        }

        switch sanitizedLoop.mode {
        case .none:
            guard advancedPosition < Double(sampleFrameCount) else {
                return nil
            }
            return SourcePositionState(samplePosition: advancedPosition, pingPongDirection: 1)
        case .forward:
            let start = Double(sanitizedLoop.startFrame)
            let end = Double(sanitizedLoop.endFrame)
            let length = max(0, end - start)
            guard length > 0 else {
                return nil
            }
            if advancedPosition < end {
                return SourcePositionState(samplePosition: advancedPosition, pingPongDirection: 1)
            }
            let overflow = advancedPosition - end
            return SourcePositionState(
                samplePosition: start + overflow.truncatingRemainder(dividingBy: length),
                pingPongDirection: 1
            )
        case .pingPong:
            return pingPongSourcePositionState(advancedPosition: advancedPosition, loop: sanitizedLoop)
        }
    }

    private static func pingPongSourcePositionState(
        advancedPosition: Double,
        loop: MixerSampleLoop
    ) -> SourcePositionState? {
        let firstLoopFrame = Double(loop.startFrame)
        let lastLoopFrame = Double(loop.endFrame - 1)
        let span = lastLoopFrame - firstLoopFrame
        guard span > 0 else {
            return nil
        }
        if advancedPosition <= lastLoopFrame {
            return SourcePositionState(samplePosition: advancedPosition, pingPongDirection: 1)
        }
        let period = span * 2.0
        guard period > 0 else {
            return nil
        }
        let overshoot = (advancedPosition - lastLoopFrame).truncatingRemainder(dividingBy: period)
        if overshoot == 0 {
            return SourcePositionState(samplePosition: lastLoopFrame, pingPongDirection: 1)
        }
        if overshoot <= span {
            return SourcePositionState(samplePosition: lastLoopFrame - overshoot, pingPongDirection: -1)
        }
        return SourcePositionState(
            samplePosition: firstLoopFrame + (overshoot - span),
            pingPongDirection: 1
        )
    }

    private static func keyedFrameCount(
        elapsedFrames: Int,
        eventStartFrame: Int,
        keyOffFrame: Int?
    ) -> Int {
        guard let keyOffFrame else {
            return elapsedFrames
        }
        return min(elapsedFrames, max(0, keyOffFrame - eventStartFrame))
    }

    private static func releasedFrameCount(
        boundaryFrame: Int,
        keyOffFrame: Int?
    ) -> Int {
        guard let keyOffFrame,
              boundaryFrame > keyOffFrame else {
            return 0
        }
        return boundaryFrame - keyOffFrame
    }

    private static func fadeoutValue(
        releasedFrames: Int,
        decrementPerFrame: Float
    ) -> Float {
        guard releasedFrames > 0,
              decrementPerFrame.isFinite,
              decrementPerFrame > 0 else {
            return 1
        }
        return max(0, 1 - (Float(releasedFrames) * decrementPerFrame))
    }

    private static func envelopePosition(
        for envelope: MixerEnvelope?,
        keyedFrames: Int,
        releasedFrames: Int
    ) -> Int {
        guard let envelope,
              !envelope.points.isEmpty else {
            return 0
        }
        var position = 0
        position = advanceEnvelopePosition(position, frames: keyedFrames, keyOn: true, envelope: envelope)
        position = advanceEnvelopePosition(position, frames: releasedFrames, keyOn: false, envelope: envelope)
        return position
    }

    private static func advanceEnvelopePosition(
        _ position: Int,
        frames: Int,
        keyOn: Bool,
        envelope: MixerEnvelope
    ) -> Int {
        guard frames > 0 else {
            return position
        }
        if !keyOn {
            return clampedEnvelopePosition(position + frames)
        }
        if let sustainFrame = envelope.sustainFrame,
           position >= sustainFrame {
            return sustainFrame
        }

        let loopStart = envelope.loopStartFrame
        let loopEnd = envelope.loopEndFrame
        if let sustainFrame = envelope.sustainFrame,
           canReachSustainBeforeLoop(
               position: position,
               frames: frames,
               sustainFrame: sustainFrame,
               loopEndFrame: loopEnd
           ) {
            return sustainFrame
        }
        guard let loopStart,
              let loopEnd,
              loopEnd >= loopStart else {
            return clampedEnvelopePosition(position + frames)
        }

        let target = position + frames
        guard target > loopEnd else {
            return clampedEnvelopePosition(target)
        }
        let loopLength = loopEnd - loopStart + 1
        guard loopLength > 0 else {
            return clampedEnvelopePosition(target)
        }
        return loopStart + ((target - loopEnd - 1) % loopLength)
    }

    private static func canReachSustainBeforeLoop(
        position: Int,
        frames: Int,
        sustainFrame: Int,
        loopEndFrame: Int?
    ) -> Bool {
        guard position < sustainFrame,
              position + frames >= sustainFrame else {
            return false
        }
        if let loopEndFrame,
           loopEndFrame < sustainFrame,
           position + frames > loopEndFrame {
            return false
        }
        return true
    }

    private static func clampedEnvelopePosition(_ position: Int) -> Int {
        min(Int(UInt32.max), max(0, position))
    }

    private static func knownUnsupportedCarryoverReasons(
        for plan: PlaybackSongSyntheticPlan
    ) -> [String] {
        var reasons = [String]()
        if plan.diagnostics.deferredCellFields.contains(where: { $0.field == .effect }) {
            reasons.append("deferred_effect_commands_not_interpreted_for_window_carryover")
        }
        if plan.diagnostics.deferredCellFields.contains(where: { $0.field == .volumeColumn }) {
            reasons.append("deferred_volume_column_commands_not_interpreted_for_window_carryover")
        }
        if plan.diagnostics.traversalHazardSummary.totalTraversalHazards > 0 {
            reasons.append("deferred_pattern_traversal_effects_not_applied")
        }
        return reasons
    }

    private static func eventPairs(
        in window: RenderWindowSpec,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler
    ) -> [(offset: Int, element: SyntheticTrackerEvent)] {
        plan.pattern.events.enumerated().filter { _, event in
            let startFrame = scheduler.frame(for: event)
            return event.row >= window.startRow &&
                event.row < window.endRowExclusive &&
                startFrame >= window.startFrame &&
                startFrame < window.endFrame
        }
    }

    private static func localEvent(
        from event: SyntheticTrackerEvent,
        windowStartFrame: Int,
        scheduler: SyntheticTrackerScheduler
    ) -> SyntheticTrackerEvent {
        let absoluteStartFrame = scheduler.frame(for: event)
        let localStartFrame = max(0, absoluteStartFrame - windowStartFrame)
        let localKeyOffFrame = event.keyOffFrame.map { max(localStartFrame, $0 - windowStartFrame) }
        return SyntheticTrackerEvent(
            row: event.row,
            tick: event.tick,
            scheduledStartFrame: localStartFrame,
            sample: event.sample,
            gain: event.gain,
            pan: event.pan,
            playbackStep: event.playbackStep,
            loop: event.loop,
            initialSourceFrame: event.initialSourceFrame,
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: localKeyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
    }
}
