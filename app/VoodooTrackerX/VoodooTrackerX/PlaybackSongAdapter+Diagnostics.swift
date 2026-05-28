import Foundation

extension PlaybackSongSyntheticAdapter {
    static func extendedEffectSubcommand(_ cell: PlaybackCell) -> UInt8? {
        guard cell.effectType == 0x0E else {
            return nil
        }
        return (cell.effectParam >> 4) & 0x0F
    }

    static func extendedEffectTick(_ cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    static func isNoteCutEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0C
    }

    static func isNoteDelayEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0D
    }

    static func isE9xRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x09
    }

    static func isRxyMultiRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x1B
    }

    static func isRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        isE9xRetriggerEffect(cell) || isRxyMultiRetriggerEffect(cell)
    }

    static func retriggerVolumeModeNibble(from cell: PlaybackCell) -> Int {
        isRxyMultiRetriggerEffect(cell) ? Int((cell.effectParam & 0xF0) >> 4) : 0
    }

    static func retriggerIntervalNibble(from cell: PlaybackCell) -> Int {
        isRxyMultiRetriggerEffect(cell) ? Int(cell.effectParam & 0x0F) : extendedEffectTick(cell)
    }

    static func isSetFinetuneEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x05
    }

    static func isFinePortamentoUpEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x01
    }

    static func finePortamentoUpAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    static func isFinePortamentoDownEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x02
    }

    static func finePortamentoDownAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    static func isXxyExtraFinePortamentoEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x21
    }

    static func xxySubcommand(from cell: PlaybackCell) -> Int {
        Int((cell.effectParam >> 4) & 0x0F)
    }

    static func xxyAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    static func isXxyExtraFinePortamentoUpEffect(_ cell: PlaybackCell) -> Bool {
        isXxyExtraFinePortamentoEffect(cell) && xxySubcommand(from: cell) == 0x01
    }

    static func isXxyExtraFinePortamentoDownEffect(_ cell: PlaybackCell) -> Bool {
        isXxyExtraFinePortamentoEffect(cell) && xxySubcommand(from: cell) == 0x02
    }

    static func xxyDirection(from cell: PlaybackCell) -> PlaybackSongSyntheticPortamentoSlideDirection? {
        if isXxyExtraFinePortamentoUpEffect(cell) {
            return .up
        }
        if isXxyExtraFinePortamentoDownEffect(cell) {
            return .down
        }
        return nil
    }

    static func isSupportedXxyExtraFinePortamentoEffect(_ cell: PlaybackCell) -> Bool {
        isXxyExtraFinePortamentoUpEffect(cell) || isXxyExtraFinePortamentoDownEffect(cell)
    }

    static func isFineVolumeSlideUpEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0A
    }

    static func isFineVolumeSlideDownEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0B
    }

    static func isFineVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        isFineVolumeSlideUpEffect(cell) || isFineVolumeSlideDownEffect(cell)
    }

    static func fineVolumeSlideAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    static func setFinetuneNibble(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    static func setFinetuneValue(from cell: PlaybackCell) -> Int {
        (setFinetuneNibble(from: cell) * 16) - 128
    }

    static func setFinetuneStatus(
        for pitchMapping: PlaybackStepMapping
    ) -> PlaybackSongSyntheticSetFinetuneDiagnostic.Status {
        if pitchMapping.applied {
            return .applied
        }
        if pitchMapping.amigaFrequencyDeferred {
            return .unsupportedFrequencyTable
        }
        return .outOfRange
    }

    static func setFinetuneDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        status: PlaybackSongSyntheticSetFinetuneDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        sampleFinetune: Int? = nil,
        pitchMapping: PlaybackStepMapping? = nil
    ) -> PlaybackSongSyntheticSetFinetuneDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .noNoteDeferred
        let deferred = effectMemoryDeferred ||
            status == .unsupportedFrequencyTable ||
            status == .outOfRange
        let ignoredAsNoOp = status == .noActiveVoice
        let policy: String
        switch status {
        case .applied:
            policy = "same_cell_note_overrides_sample_finetune_no_memory"
        case .noNoteDeferred:
            policy = "no_same_cell_note_effect_memory_deferred"
        case .noActiveVoice:
            policy = "no_playable_same_cell_note"
        case .unsupportedFrequencyTable:
            policy = "linear_frequency_only_first_pass"
        case .outOfRange:
            policy = "pitch_mapping_out_of_range"
        }
        return PlaybackSongSyntheticSetFinetuneDiagnostic(
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
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            finetuneNibble: setFinetuneNibble(from: cell),
            sampleFinetune: sampleFinetune,
            effectiveFinetune: pitchMapping?.effectiveFinetune,
            linearPeriod: pitchMapping?.linearPeriod,
            linearFrequency: pitchMapping?.linearFrequency,
            playbackStep: pitchMapping?.playbackStep,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            policy: policy
        )
    }

    static func sampleOffsetDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        selectedSampleLength: Int?,
        channelState: inout ChannelState
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
                selectedSampleLength: sampleLength,
                effectMemoryReused: false,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                memorySource: nil,
                memoryUnavailableReason: nil
            )
        }

        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let computedOffsetFrames: Int
        let memorySource: PlaybackSongSyntheticEffectMemorySource?
        let effectMemoryReused: Bool
        if cell.effectParam == 0 {
            if let memory = channelState.sampleOffsetMemory {
                computedOffsetFrames = memory.offsetFrames
                memorySource = memory.source
                effectMemoryReused = true
            } else {
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
                    computedOffsetFrames: 0,
                    appliedOffsetFrames: 0,
                    selectedSampleLength: sampleLength,
                    effectMemoryReused: false,
                    effectMemoryMissing: true,
                    effectMemoryDeferred: true,
                    memorySource: nil,
                    memoryUnavailableReason: "missing_9xx_sample_offset_memory"
                )
            }
        } else {
            computedOffsetFrames = Int(cell.effectParam) * 256
            channelState.sampleOffsetMemory = SampleOffsetMemory(
                offsetFrames: computedOffsetFrames,
                source: targetMemorySource
            )
            memorySource = nil
            effectMemoryReused = false
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
                selectedSampleLength: sampleLength,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                memorySource: memorySource,
                memoryUnavailableReason: nil
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
            selectedSampleLength: sampleLength,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: false,
            effectMemoryDeferred: false,
            memorySource: memorySource,
            memoryUnavailableReason: nil
        )
    }

    static func effectCommandDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        traversalEffectStatuses: [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status],
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic? {
        guard shouldReportEffectCommand(cell) else {
            return nil
        }
        let traversalKey = TraversalEffectKey(
            orderIndex: source.orderIndex,
            patternIndex: source.patternIndex,
            rowIndex: source.rowIndex,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
        return PlaybackSongSyntheticEffectCommandDiagnostic(
            source: source,
            channelIndex: channelIndex,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            decodedLabel: effectCommandLabel(effectType: cell.effectType, effectParam: cell.effectParam),
            status: traversalEffectStatuses[traversalKey] ?? effectCommandStatus(cell, timingConfig: timingConfig),
            isTraversalHazard: isTraversalHazard(cell)
        )
    }

    static func shouldReportEffectCommand(_ cell: PlaybackCell) -> Bool {
        switch cell.effectType {
        case 0x00:
            return cell.effectParam != 0
        case 0x01...0x08, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x15, 0x1B, 0x21:
            return true
        default:
            return false
        }
    }

    static func effectCommandStatus(
        _ cell: PlaybackCell,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic.Status {
        switch cell.effectType {
        case 0x00 where cell.effectParam != 0:
            return .applied
        case 0x07:
            return .deferredUnsupported
        case 0x05:
            return .applied
        case 0x04:
            let speed = Int((cell.effectParam & 0xF0) >> 4)
            let depth = Int(cell.effectParam & 0x0F)
            return cell.effectParam == 0 || speed == 0 || depth == 0 ? .ignoredNoOp : .applied
        case 0x06:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x01...0x02:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x03:
            return .applied
        case 0x08, 0x0C:
            return .applied
        case 0x0A:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x0F:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x10:
            return .applied
        case 0x11:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x15:
            return .applied
        case 0x1B:
            let interval = retriggerIntervalNibble(from: cell)
            guard interval > 0 else {
                return .ignoredNoOp
            }
            return interval < timingConfig.speed ? .applied : .ignoredNoOp
        case 0x21:
            guard isSupportedXxyExtraFinePortamentoEffect(cell) else {
                return .deferredUnsupported
            }
            return xxyAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isRetriggerEffect(cell):
            let interval = retriggerIntervalNibble(from: cell)
            guard interval > 0 else {
                return .ignoredNoOp
            }
            return interval < timingConfig.speed ? .applied : .ignoredNoOp
        case 0x0E where isSetFinetuneEffect(cell):
            return (1...96).contains(cell.note) ? .applied : .deferredUnsupported
        case 0x0E where isFinePortamentoUpEffect(cell):
            return finePortamentoUpAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isFinePortamentoDownEffect(cell):
            return finePortamentoDownAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isFineVolumeSlideEffect(cell):
            return fineVolumeSlideAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isVibratoControlEffect(cell):
            return supportedVibratoWaveform(controlValue: Int(cell.effectParam & 0x0F)) == nil
                ? .deferredUnsupported
                : .applied
        case 0x0E where isNoteCutEffect(cell) || isNoteDelayEffect(cell):
            guard extendedEffectTick(cell) < timingConfig.speed else {
                return .ignoredNoOp
            }
            if isNoteDelayEffect(cell), !(1...96).contains(cell.note) {
                return .deferredUnsupported
            }
            return .applied
        case 0x0E where isE6xPatternLoopEffect(cell):
            return .deferredUnsupported
        case 0x0B, 0x0D, 0x0E:
            return .deferredUnsupported
        default:
            return .unknown
        }
    }

    static func isTraversalHazard(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0B ||
            cell.effectType == 0x0D ||
            isE6xPatternLoopEffect(cell) ||
            (cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x0E)
    }

    static func isE6xPatternLoopEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x06
    }

    static func effectCommandLabel(effectType: UInt8, effectParam: UInt8) -> String {
        switch effectType {
        case 0x00:
            return effectParam != 0 ? "0xy arpeggio" : "none"
        case 0x01:
            return "1xx portamento up"
        case 0x02:
            return "2xx portamento down"
        case 0x03:
            return "3xx tone portamento"
        case 0x04:
            return "4xy vibrato"
        case 0x05:
            return "5xy tone portamento + volume slide"
        case 0x06:
            return "6xy vibrato + volume slide"
        case 0x07:
            return "7xy tremolo"
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
        case 0x10:
            return "Gxx set global volume"
        case 0x11:
            return "Hxy global volume slide"
        case 0x14:
            return "Kxx key off"
        case 0x15:
            return "Lxx set envelope position"
        case 0x1B:
            return "Rxy multi retrigger"
        case 0x21:
            return "Xxy extra fine portamento"
        default:
            return "unknown/unsupported"
        }
    }

    static func extendedEffectCommandLabel(effectParam: UInt8) -> String {
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

    static func selectedSampleLength(_ sample: PlaybackSample) -> Int {
        min(max(0, sample.sampleLength), sample.pcm.count)
    }

    static func hasEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType != 0 || cell.effectParam != 0
    }

    static func hasDeferredEffect(_ cell: PlaybackCell) -> Bool {
        guard hasEffect(cell) else {
            return false
        }
        if PlaybackSongFxxTimingPlanner.isFxxTimingEffect(cell) ||
            isNonzeroSampleOffsetEffect(cell) ||
            isArpeggioEffect(cell) ||
            isPortamentoSlideEffect(cell) ||
            isTonePortamentoEffect(cell) ||
            isVibratoEffect(cell) ||
            isVibratoVolumeSlideEffect(cell) ||
            isSetFinetuneEffect(cell) ||
            isFinePortamentoUpEffect(cell) ||
            isFinePortamentoDownEffect(cell) ||
            isSupportedXxyExtraFinePortamentoEffect(cell) ||
            isFineVolumeSlideEffect(cell) ||
            (isVibratoControlEffect(cell) && supportedVibratoWaveform(controlValue: Int(cell.effectParam & 0x0F)) != nil) ||
            isSupportedRetriggerEffect(cell) ||
            isNoteCutEffect(cell) ||
            isNoteDelayEffect(cell) ||
            isKxxKeyOffEffect(cell) ||
            isLxxSetEnvelopePositionEffect(cell) ||
            isGlobalVolumeSetEffect(cell) ||
            isGlobalVolumeSlideEffect(cell) ||
            isTraversalPlanningEffect(cell) {
            return false
        }
        switch cell.effectType {
        case 0x08, 0x0A, 0x0C:
            return false
        default:
            return true
        }
    }

    static func hasDeferredEffect(_ cell: PlaybackCell, channelState: ChannelState) -> Bool {
        if cell.effectType == 0x09, cell.effectParam == 0 {
            return channelState.sampleOffsetMemory == nil
        }
        if cell.effectType == 0x01, cell.effectParam == 0 {
            return channelState.portamentoUpMemory == nil
        }
        if cell.effectType == 0x02, cell.effectParam == 0 {
            return channelState.portamentoDownMemory == nil
        }
        if cell.effectType == 0x04 {
            let speed = Int((cell.effectParam & 0xF0) >> 4)
            let depth = Int(cell.effectParam & 0x0F)
            return (speed == 0 && channelState.vibratoSpeed == nil) ||
                (depth == 0 && channelState.vibratoDepth == nil)
        }
        if cell.effectType == 0x06 {
            return channelState.vibratoSpeed == nil || channelState.vibratoDepth == nil
        }
        if (cell.effectType == 0x0A || cell.effectType == 0x05),
           cell.effectParam == 0 {
            return channelState.volumeSlideMemory == nil
        }
        return hasDeferredEffect(cell)
    }

    static func isNonzeroSampleOffsetEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x09 && cell.effectParam != 0
    }

    static func isArpeggioEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x00 && cell.effectParam != 0
    }

    static func isPortamentoSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x01 || cell.effectType == 0x02
    }

    static func isTonePortamentoEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x03 || cell.effectType == 0x05
    }

    static func isTonePortamentoVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x05
    }

    static func isVibratoEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x04
    }

    static func isVibratoVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x06
    }

    static func isVibratoControlEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x04
    }

    static func isSupportedRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        isRetriggerEffect(cell) && retriggerIntervalNibble(from: cell) > 0
    }

    static func isGlobalVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x11
    }

    static func isGlobalVolumeSetEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x10
    }

    static func isKxxKeyOffEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x14
    }

    static func isLxxSetEnvelopePositionEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x15
    }

    static func isTraversalPlanningEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0B ||
            cell.effectType == 0x0D ||
            isE6xPatternLoopEffect(cell)
    }

    static func selectSample(forNote note: UInt8, from instrument: PlaybackInstrument) -> SampleSelection {
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

    static func skippedReasonForInvalidMappedSample(
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

    static func ignoredCell(
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

    static func ignoredNoteReason(
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

    static func skipReason(for reason: PlaybackSongSyntheticIgnoredCell.Reason) -> PlaybackSongSyntheticSkipReason {
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

    static func mixerLoop(from sample: PlaybackSample) -> MixerSampleLoop {
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
