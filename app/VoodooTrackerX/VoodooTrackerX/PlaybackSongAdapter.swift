import Foundation

struct PlaybackSongSyntheticPlan: Equatable {
    let timingConfig: SyntheticTrackerTimingConfig
    let pattern: SyntheticPattern
    let diagnostics: PlaybackSongSyntheticDiagnostics
}

enum PlaybackSongSyntheticAdapter {
    static let maxMixerEnvelopePointCount = 12
    static let xmLinearPeriodBase = 7_680.0
    static let xmLinearC4Period = 4_608.0
    static let xmLinearPeriodUnitsPerSemitone = 64.0
    static let xmLinearPeriodUnitsPerOctave = 768.0
    static let xmLinearMaximumRealNoteIndex = 118
    static let xmLinearMaximumEffectiveNoteValue = xmLinearMaximumRealNoteIndex + 1
    static let xmLinearMinimumSafePeriod = xmLinearPeriodBase
        - (Double(xmLinearMaximumRealNoteIndex) * xmLinearPeriodUnitsPerSemitone)
        - (127.0 / 2.0)
    static let xmLinearMaximumSafePeriod = xmLinearPeriodBase + 64.0
    static let xmAmigaC4Period = 6_848.0
    static let xmAmigaPitchUnitsPerOctave = 3_072.0
    static let xmAmigaPortamentoUnitsPerParam = 16.0
    static let xmAmigaMinimumSafePeriod = 107.0
    static let xmAmigaMaximumSafePeriod = 438_272.0

    struct ChannelState: Equatable {
        var volumeValue = 64
        var volumeValueZeroedByAxy = false
        var panningValue = 127.5
        var activeEventIndex: Int?
        var activeEventMappingIndex: Int?
        var activeInstrumentIndex: Int?
        var activeSampleIndex: Int?
        var activeSampleVolume: Float?
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
        var volumeSlideMemory: VolumeSlideMemory?
        var vibratoSpeed: Int?
        var vibratoDepth: Int?
        var vibratoSpeedMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoDepthMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoControl: VibratoControlState?
        var vibratoPhase: Double = 0

        var pan: Float {
            PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: panningValue)
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
        let slide: VolumeSlideAmounts
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
        case random = 3

        var name: String {
            switch self {
            case .sine:
                return "sine"
            case .rampDown:
                return "ramp_down"
            case .square:
                return "square"
            case .random:
                return "random"
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
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var volumeColumnMappings = [PlaybackSongSyntheticVolumeColumnMapping]()
        var voiceStateUpdates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
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
        var channelStates = [Int: ChannelState]()
        var mixerSampleBuffers = [MixerSampleBufferCacheKey: MixerSampleBuffer]()
        var globalVolumeState = GlobalVolumeState()
        var traversalEffectStatuses = [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()
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
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount
        )
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            traversalPlan: traversalPlan,
            sampleRate: sampleRate
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
        context.mixerSampleBuffers.reserveCapacity(song.instrumentsByIndex.values.reduce(0) { $0 + $1.samples.count })
        context.traversalEffectStatuses = traversalEffectStatuses(from: traversalPlan.traversalDiagnostics)

        for traversalRow in traversalPlan.rows {
            rowMappings.append(PlaybackSongSyntheticRowMapping(
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow
            ))
            let rowDiagnostic = appendEvents(
                from: traversalRow.row,
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow,
                song: song,
                timingConfig: timingPlan.timingConfig(forSyntheticRow: traversalRow.syntheticRow),
                timingPlan: timingPlan,
                scheduledStartFrame: timingPlan.frameFor(row: traversalRow.syntheticRow, tick: 0),
                context: &context
            )
            context.rowDiagnostics.append(rowDiagnostic)
        }

        return PlaybackSongSyntheticPlan(
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
        context: inout AdapterRowContext
    ) -> PlaybackSongSyntheticRowDiagnostic {
        let eventStartCount = context.events.count
        let ignoredStartCount = context.ignoredCells.count
        for (channelIndex, cell) in row.cells.enumerated() {
            context.eventCoverage.visit(cell)
            if let effectCommandDiagnostic = effectCommandDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                traversalEffectStatuses: context.traversalEffectStatuses,
                timingConfig: timingConfig
            ) {
                context.effectCommandDiagnostics.append(effectCommandDiagnostic)
            }
            var channelState = context.channelStates[channelIndex] ?? ChannelState()
            defer {
                let axyUpdates = applyEffectColumnVolumeSlide(
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
            let hasVibrato = isVibratoEffect(cell)
            let hasVibratoVolumeSlide = isVibratoVolumeSlideEffect(cell)
            let hasKxxKeyOff = isKxxKeyOffEffect(cell)
            let hasLxxSetEnvelopePosition = isLxxSetEnvelopePositionEffect(cell)
            var volumeColumn = PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn)
            let hasVolumeColumnTonePortamento = isTonePortamentoVolumeColumn(volumeColumn)
            let handlesTonePortamento = hasTonePortamento || hasVolumeColumnTonePortamento
            let hasValidImmediateNoteInstrument = (1...96).contains(cell.note) &&
                cell.instrument > 0 &&
                !hasNoteDelayEffect
            let resetsInstrumentVolumeBeforeTrigger = hasValidImmediateNoteInstrument &&
                !handlesTonePortamento &&
                cell.effectType == 0 &&
                cell.effectParam == 0 &&
                cell.volumeColumn == 0 &&
                channelState.volumeValueZeroedByAxy
            if resetsInstrumentVolumeBeforeTrigger {
                channelState.volumeValue = 64
                channelState.volumeValueZeroedByAxy = false
            }
            let delaysInstrumentVolumeState = hasValidImmediateNoteInstrument && handlesTonePortamento
            let channelStateBeforeVolumeColumn = channelState
            if !delaysInstrumentVolumeState {
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState)
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
            if cell.effectType == 0x11 {
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
            if hasVibrato, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibratoVolumeSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
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
                    eventMappings: &context.eventMappings,
                    ignoredCells: &context.ignoredCells,
                    deferredCellFields: &context.deferredCellFields,
                    eventCoverage: &context.eventCoverage
                )
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
                        eventMappings: &context.eventMappings,
                        ignoredCells: &context.ignoredCells,
                        deferredCellFields: &context.deferredCellFields,
                        eventCoverage: &context.eventCoverage
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

            let instrumentIndex = Int(cell.instrument)
            guard instrumentIndex > 0 else {
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
            let sampleSelection = selectSample(forNote: cell.note, from: instrument)
            guard let sample = sampleSelection.sample else {
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
                        activeEventMappingIndex: nil,
                        sampleFinetune: sampleSelection.diagnosticSample?.finetune
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
                channelState.volumeValue = 64
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
                let instrumentGainBefore = instrumentStateBefore.activeSampleVolume.map {
                    adaptedGain(sampleVolume: $0, channelVolume: instrumentStateBefore.volumeValue)
                }
                let instrumentGainAfter = channelState.activeSampleVolume.map {
                    adaptedGain(sampleVolume: $0, channelVolume: channelState.volumeValue)
                }
                tonePortamentoInstrumentDefaultVolumeApplied = instrumentStateBefore.volumeValue != channelState.volumeValue ||
                    instrumentStateBefore.activeSampleVolume != channelState.activeSampleVolume
                if handlesTonePortamento {
                    context.voiceStateUpdates.append(voiceStateUpdateDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        cell: cell,
                        commandSource: .instrumentState,
                        command: .instrumentDefaultVolume(value: channelState.volumeValue),
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
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState)
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
            let gain = adaptedGain(
                sampleVolume: sample.volume,
                channelVolume: channelState.volumeValue,
                globalVolume: context.globalVolumeState.volumeValue
            )
            let pan = channelState.pan
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
                volumeEnvelope: envelopeMapping.envelope
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
            channelState.activeSampleVolume = sample.volume
            channelState.activePlaybackStep = pitchMapping.playbackStep
            channelState.activeLinearPeriod = pitchMapping.linearPeriod
            channelState.activeAmigaPeriod = pitchMapping.amigaPeriod
            channelState.activeSampleBaseSampleRate = sample.baseSampleRate
            channelState.activeSampleRelativeNote = sample.relativeNote
            channelState.activeSampleFinetune = pitchMapping.effectiveFinetune ?? sample.finetune
            channelState.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
            applyActiveVolumeEnvelopeMapping(envelopeMapping, to: &channelState)
            channelState.tonePortamentoTargetNote = nil
            channelState.tonePortamentoTargetLinearPeriod = nil
            channelState.tonePortamentoTargetAmigaPeriod = nil
            channelState.tonePortamentoTargetPlaybackStep = nil
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
                effectiveVolumeValue: channelState.volumeValue,
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
            if hasVibrato {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibratoVolumeSlide {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
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
                    eventMappings: &context.eventMappings,
                    ignoredCells: &context.ignoredCells,
                    deferredCellFields: &context.deferredCellFields,
                    eventCoverage: &context.eventCoverage
                )
            }
            context.channelStates[channelIndex] = channelState
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
