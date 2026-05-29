import Foundation

extension PlaybackSongSyntheticAdapter {
    static func eventMapping(
        _ mapping: PlaybackSongSyntheticEventMapping,
        applying semantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: mapping.source,
            channelIndex: mapping.channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            sampleVolume: mapping.sampleVolume,
            sampleVolumeRawEstimate: mapping.sampleVolumeRawEstimate,
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
            effectiveGlobalVolumeValue: mapping.effectiveGlobalVolumeValue,
            effectiveGlobalVolumeMultiplier: mapping.effectiveGlobalVolumeMultiplier,
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
            amigaPeriod: mapping.amigaPeriod,
            amigaFrequency: mapping.amigaFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyApplied: mapping.amigaFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    static func retriggeredEventMapping(
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
        effectiveGlobalVolumeValue: Int,
        effectiveGlobalVolumeMultiplier: Float,
        effectivePan: Float
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: source,
            channelIndex: channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            sampleVolume: mapping.sampleVolume,
            sampleVolumeRawEstimate: mapping.sampleVolumeRawEstimate,
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
            effectiveGlobalVolumeValue: effectiveGlobalVolumeValue,
            effectiveGlobalVolumeMultiplier: effectiveGlobalVolumeMultiplier,
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
            amigaPeriod: mapping.amigaPeriod,
            amigaFrequency: mapping.amigaFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyApplied: mapping.amigaFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    struct VolumeEnvelopeMapping: Equatable {
        let envelope: MixerEnvelope?
        let status: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus
        let sourcePointCount: Int
        let mappedPointCount: Int
        let sustainFrame: Int?
        let loopStartFrame: Int?
        let loopEndFrame: Int?
    }

    struct PlaybackStepMapping: Equatable {
        let playbackStep: Double
        let outputSampleRate: Double
        let effectiveNoteValue: Int?
        let effectiveNoteIndex: Int?
        let effectiveFinetune: Int?
        let linearPeriod: Double?
        let linearFrequency: Double?
        let amigaPeriod: Double?
        let amigaFrequency: Double?
        let finetuneStatus: PlaybackSongSyntheticEventMapping.FinetuneStatus
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus
        let linearFrequencyApplied: Bool
        let amigaFrequencyApplied: Bool
        let amigaFrequencyDeferred: Bool
        let applied: Bool
        let usedNeutralStep: Bool
    }

    struct LinearPitchTarget: Equatable {
        let linearPeriod: Double
        let playbackStep: Double
        let linearFrequency: Double
        let effectiveNoteValue: Int
        let effectiveNoteIndex: Int
        let effectiveFinetune: Int
    }

    struct AmigaPitchTarget: Equatable {
        let amigaPeriod: Double
        let playbackStep: Double
        let amigaFrequency: Double
        let effectiveNoteValue: Int
        let effectiveNoteIndex: Int
        let effectiveFinetune: Int
    }

    static func adaptedGain(
        sampleVolume: Float,
        channelVolume: Int,
        globalVolume: Int = GlobalVolumeState.defaultValue
    ) -> Float {
        let baseGain = sampleVolume.isFinite ? sampleVolume : 0
        let volumeMultiplier = volumeMultiplier(for: channelVolume)
        let globalMultiplier = globalVolumeMultiplier(for: globalVolume)
        // The bounded adapter treats supported XM volume-column volume commands as row-level
        // channel-volume updates: final event gain = sample volume * (channel volume / 64).
        // Hxy global-volume slides are another Swift-side row-level multiplier.
        // Parsed volume envelopes remain separate C mixer envelopes and multiply this gain at render time.
        return clampedGain(baseGain * volumeMultiplier * globalMultiplier)
    }

    static func sampleVolumeRawEstimate(for sampleVolume: Float) -> Int {
        guard sampleVolume.isFinite else {
            return 0
        }
        return clampedVolumeValue(Int((sampleVolume * 64.0).rounded()))
    }

    static func volumeMultiplier(for volumeValue: Int) -> Float {
        Float(clampedVolumeValue(volumeValue)) / 64.0
    }

    static func clampedVolumeValue(_ value: Int) -> Int {
        min(64, max(0, value))
    }

    static func clampedGlobalVolumeValue(_ value: Int) -> Int {
        min(64, max(0, value))
    }

    static func globalVolumeMultiplier(for volumeValue: Int) -> Float {
        Float(clampedGlobalVolumeValue(volumeValue)) / 64.0
    }

    static func clampedPanningValue(_ value: Double) -> Double {
        min(255.0, max(0.0, value.isFinite ? value : 127.5))
    }

    static func clampedGain(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }

    static func playbackStepMapping(
        note: UInt8,
        sample: PlaybackSample,
        usesLinearFrequencyTable: Bool,
        timingConfig: SyntheticTrackerTimingConfig,
        finetuneOverride: Int? = nil
    ) -> PlaybackStepMapping {
        let outputSampleRate = timingConfig.sampleRate
        guard usesLinearFrequencyTable else {
            guard let target = amigaPitchTarget(
                note: note,
                relativeNote: sample.relativeNote,
                finetune: finetuneOverride ?? sample.finetune,
                baseSampleRate: sample.baseSampleRate,
                outputSampleRate: outputSampleRate
            ) else {
                let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: sample.relativeNote)
                let effectiveNoteIndex = effectiveNoteValue - 1
                return PlaybackStepMapping(
                    playbackStep: 1,
                    outputSampleRate: outputSampleRate,
                    effectiveNoteValue: effectiveNoteValue,
                    effectiveNoteIndex: effectiveNoteIndex,
                    effectiveFinetune: clampedFinetune(finetuneOverride ?? sample.finetune),
                    linearPeriod: nil,
                    linearFrequency: nil,
                    amigaPeriod: nil,
                    amigaFrequency: nil,
                    finetuneStatus: .deferred,
                    frequencyTableStatus: .amigaTableDeferredNeutralFallback,
                    linearFrequencyApplied: false,
                    amigaFrequencyApplied: false,
                    amigaFrequencyDeferred: true,
                    applied: false,
                    usedNeutralStep: true
                )
            }
            return PlaybackStepMapping(
                playbackStep: target.playbackStep,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: target.effectiveNoteValue,
                effectiveNoteIndex: target.effectiveNoteIndex,
                effectiveFinetune: target.effectiveFinetune,
                linearPeriod: nil,
                linearFrequency: nil,
                amigaPeriod: target.amigaPeriod,
                amigaFrequency: target.amigaFrequency,
                finetuneStatus: .applied,
                frequencyTableStatus: .amigaApplied,
                linearFrequencyApplied: false,
                amigaFrequencyApplied: true,
                amigaFrequencyDeferred: false,
                applied: true,
                usedNeutralStep: abs(target.playbackStep - 1.0) <= 0.000000001
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
                amigaPeriod: nil,
                amigaFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        guard let target = linearPitchTarget(
            note: note,
            relativeNote: sample.relativeNote,
            finetune: finetuneOverride ?? sample.finetune,
            baseSampleRate: baseSampleRate,
            outputSampleRate: outputSampleRate
        ) else {
            let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: sample.relativeNote)
            let effectiveNoteIndex = effectiveNoteValue - 1
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: effectiveNoteValue,
                effectiveNoteIndex: effectiveNoteIndex,
                effectiveFinetune: clampedFinetune(finetuneOverride ?? sample.finetune),
                linearPeriod: nil,
                linearFrequency: nil,
                amigaPeriod: nil,
                amigaFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        return PlaybackStepMapping(
            playbackStep: target.playbackStep,
            outputSampleRate: outputSampleRate,
            effectiveNoteValue: target.effectiveNoteValue,
            effectiveNoteIndex: target.effectiveNoteIndex,
            effectiveFinetune: target.effectiveFinetune,
            linearPeriod: target.linearPeriod,
            linearFrequency: target.linearFrequency,
            amigaPeriod: nil,
            amigaFrequency: nil,
            finetuneStatus: .applied,
            frequencyTableStatus: .linearApplied,
            linearFrequencyApplied: true,
            amigaFrequencyApplied: false,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(target.playbackStep - 1.0) <= 0.000000001
        )
    }

    static func linearPitchTarget(
        note: UInt8,
        relativeNote: Int,
        finetune: Int,
        baseSampleRate: Double,
        outputSampleRate: Double
    ) -> LinearPitchTarget? {
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return nil
        }
        let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: relativeNote)
        let effectiveNoteIndex = effectiveNoteValue - 1
        let effectiveFinetune = clampedFinetune(finetune)

        // XM linear frequency mode is period based even though the C mixer consumes a source-sample step.
        // FT2 applies sample relative note to the pattern note and clamps the zero-based real note to 0...118.
        // FT2's linear period formula is:
        // period = 7680 - (zeroBasedNote * 64) - (finetune / 2)
        // C-4 is note value 49, zero-based note 48, period 4608, so it maps to the sample base rate.
        let linearPeriod = xmLinearPeriodBase
            - (Double(effectiveNoteIndex) * xmLinearPeriodUnitsPerSemitone)
            - (Double(effectiveFinetune) / 2.0)
        guard let step = playbackStep(
            linearPeriod: linearPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: outputSampleRate
        ) else {
            return nil
        }
        let linearFrequency = step * outputSampleRate
        guard linearPeriod.isFinite,
              linearFrequency.isFinite,
              linearFrequency > 0 else {
            return nil
        }
        return LinearPitchTarget(
            linearPeriod: linearPeriod,
            playbackStep: step,
            linearFrequency: linearFrequency,
            effectiveNoteValue: effectiveNoteValue,
            effectiveNoteIndex: effectiveNoteIndex,
            effectiveFinetune: effectiveFinetune
        )
    }

    static func playbackStep(
        linearPeriod: Double,
        baseSampleRate: Double,
        outputSampleRate: Double
    ) -> Double? {
        guard linearPeriod.isFinite,
              outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return nil
        }
        let linearFrequency = baseSampleRate * pow(
            2.0,
            (xmLinearC4Period - linearPeriod) / xmLinearPeriodUnitsPerOctave
        )
        let step = linearFrequency / outputSampleRate
        guard linearFrequency.isFinite,
              linearFrequency > 0,
              step.isFinite,
              step > 0,
              step <= Double(UInt32.max) else {
            return nil
        }
        return step
    }

    static func amigaPitchTarget(
        note: UInt8,
        relativeNote: Int,
        finetune: Int,
        baseSampleRate: Double,
        outputSampleRate: Double
    ) -> AmigaPitchTarget? {
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return nil
        }
        let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: relativeNote)
        let effectiveNoteIndex = effectiveNoteValue - 1
        let effectiveFinetune = clampedFinetune(finetune)
        let amigaPeriod = clampedAmigaPeriod(amigaPeriodFromLookup(
            effectiveNoteValue: effectiveNoteValue,
            finetune: effectiveFinetune
        ))
        guard let step = playbackStep(
            amigaPeriod: amigaPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: outputSampleRate
        ) else {
            return nil
        }
        let amigaFrequency = step * outputSampleRate
        return AmigaPitchTarget(
            amigaPeriod: amigaPeriod,
            playbackStep: step,
            amigaFrequency: amigaFrequency,
            effectiveNoteValue: effectiveNoteValue,
            effectiveNoteIndex: effectiveNoteIndex,
            effectiveFinetune: effectiveFinetune
        )
    }

    static let xmAmigaPeriodLookupScale = 4.0

    // First 1,920 reachable entries from FastTracker II's Amiga period lookup.
    // VTX keeps periods at 4x scale so C-4 remains 6848.
    static let xmAmigaPeriodLookup: [UInt16] = [
        29_024, 28_912, 28_800, 28_704, 28_608, 28_496, 28_384, 28_288, 28_192, 28_096, 28_000, 27_888, 27_776, 27_680, 27_584, 27_488,
        27_392, 27_296, 27_200, 27_104, 27_008, 26_912, 26_816, 26_720, 26_624, 26_528, 26_432, 26_336, 26_240, 26_144, 26_048, 25_952,
        25_856, 25_760, 25_664, 25_568, 25_472, 25_392, 25_312, 25_216, 25_120, 25_024, 24_928, 24_848, 24_768, 24_672, 24_576, 24_480,
        24_384, 24_304, 24_224, 24_144, 24_064, 23_968, 23_872, 23_792, 23_712, 23_632, 23_552, 23_456, 23_360, 23_280, 23_200, 23_120,
        23_040, 22_960, 22_880, 22_784, 22_688, 22_608, 22_528, 22_448, 22_368, 22_288, 22_208, 22_128, 22_048, 21_968, 21_888, 21_792,
        21_696, 21_648, 21_600, 21_520, 21_440, 21_360, 21_280, 21_200, 21_120, 21_040, 20_960, 20_896, 20_832, 20_752, 20_672, 20_576,
        20_480, 20_416, 20_352, 20_288, 20_224, 20_160, 20_096, 20_016, 19_936, 19_872, 19_808, 19_728, 19_648, 19_584, 19_520, 19_424,
        19_328, 19_280, 19_232, 19_168, 19_104, 19_024, 18_944, 18_880, 18_816, 18_752, 18_688, 18_624, 18_560, 18_480, 18_400, 18_320,
        18_240, 18_192, 18_144, 18_080, 18_016, 17_952, 17_888, 17_824, 17_760, 17_696, 17_632, 17_568, 17_504, 17_440, 17_376, 17_296,
        17_216, 17_168, 17_120, 17_072, 17_024, 16_960, 16_896, 16_832, 16_768, 16_704, 16_640, 16_576, 16_512, 16_464, 16_416, 16_336,
        16_256, 16_208, 16_160, 16_112, 16_064, 16_000, 15_936, 15_872, 15_808, 15_760, 15_712, 15_648, 15_584, 15_536, 15_488, 15_424,
        15_360, 15_312, 15_264, 15_216, 15_168, 15_104, 15_040, 14_992, 14_944, 14_880, 14_816, 14_768, 14_720, 14_672, 14_624, 14_568,
        14_512, 14_456, 14_400, 14_352, 14_304, 14_248, 14_192, 14_144, 14_096, 14_048, 14_000, 13_944, 13_888, 13_840, 13_792, 13_744,
        13_696, 13_648, 13_600, 13_552, 13_504, 13_456, 13_408, 13_360, 13_312, 13_264, 13_216, 13_168, 13_120, 13_072, 13_024, 12_976,
        12_928, 12_880, 12_832, 12_784, 12_736, 12_696, 12_656, 12_608, 12_560, 12_512, 12_464, 12_424, 12_384, 12_336, 12_288, 12_240,
        12_192, 12_152, 12_112, 12_072, 12_032, 11_984, 11_936, 11_896, 11_856, 11_816, 11_776, 11_728, 11_680, 11_640, 11_600, 11_560,
        11_520, 11_480, 11_440, 11_392, 11_344, 11_304, 11_264, 11_224, 11_184, 11_144, 11_104, 11_064, 11_024, 10_984, 10_944, 10_896,
        10_848, 10_824, 10_800, 10_760, 10_720, 10_680, 10_640, 10_600, 10_560, 10_520, 10_480, 10_448, 10_416, 10_376, 10_336, 10_288,
        10_240, 10_208, 10_176, 10_144, 10_112, 10_080, 10_048, 10_008, 9_968, 9_936, 9_904, 9_864, 9_824, 9_792, 9_760, 9_712,
        9_664, 9_640, 9_616, 9_584, 9_552, 9_512, 9_472, 9_440, 9_408, 9_376, 9_344, 9_312, 9_280, 9_240, 9_200, 9_160,
        9_120, 9_096, 9_072, 9_040, 9_008, 8_976, 8_944, 8_912, 8_880, 8_848, 8_816, 8_784, 8_752, 8_720, 8_688, 8_648,
        8_608, 8_584, 8_560, 8_536, 8_512, 8_480, 8_448, 8_416, 8_384, 8_352, 8_320, 8_288, 8_256, 8_232, 8_208, 8_168,
        8_128, 8_104, 8_080, 8_056, 8_032, 8_000, 7_968, 7_936, 7_904, 7_880, 7_856, 7_824, 7_792, 7_768, 7_744, 7_712,
        7_680, 7_656, 7_632, 7_608, 7_584, 7_552, 7_520, 7_496, 7_472, 7_440, 7_408, 7_384, 7_360, 7_336, 7_312, 7_284,
        7_256, 7_228, 7_200, 7_176, 7_152, 7_124, 7_096, 7_072, 7_048, 7_024, 7_000, 6_972, 6_944, 6_920, 6_896, 6_872,
        6_848, 6_824, 6_800, 6_776, 6_752, 6_728, 6_704, 6_680, 6_656, 6_632, 6_608, 6_584, 6_560, 6_536, 6_512, 6_488,
        6_464, 6_440, 6_416, 6_392, 6_368, 6_348, 6_328, 6_304, 6_280, 6_256, 6_232, 6_212, 6_192, 6_168, 6_144, 6_120,
        6_096, 6_076, 6_056, 6_036, 6_016, 5_992, 5_968, 5_948, 5_928, 5_908, 5_888, 5_864, 5_840, 5_820, 5_800, 5_780,
        5_760, 5_740, 5_720, 5_696, 5_672, 5_652, 5_632, 5_612, 5_592, 5_572, 5_552, 5_532, 5_512, 5_492, 5_472, 5_448,
        5_424, 5_412, 5_400, 5_380, 5_360, 5_340, 5_320, 5_300, 5_280, 5_260, 5_240, 5_224, 5_208, 5_188, 5_168, 5_144,
        5_120, 5_104, 5_088, 5_072, 5_056, 5_040, 5_024, 5_004, 4_984, 4_968, 4_952, 4_932, 4_912, 4_896, 4_880, 4_856,
        4_832, 4_820, 4_808, 4_792, 4_776, 4_756, 4_736, 4_720, 4_704, 4_688, 4_672, 4_656, 4_640, 4_620, 4_600, 4_580,
        4_560, 4_548, 4_536, 4_520, 4_504, 4_488, 4_472, 4_456, 4_440, 4_424, 4_408, 4_392, 4_376, 4_360, 4_344, 4_324,
        4_304, 4_292, 4_280, 4_268, 4_256, 4_240, 4_224, 4_208, 4_192, 4_176, 4_160, 4_144, 4_128, 4_116, 4_104, 4_084,
        4_064, 4_052, 4_040, 4_028, 4_016, 4_000, 3_984, 3_968, 3_952, 3_940, 3_928, 3_912, 3_896, 3_884, 3_872, 3_856,
        3_840, 3_828, 3_816, 3_804, 3_792, 3_776, 3_760, 3_748, 3_736, 3_720, 3_704, 3_692, 3_680, 3_668, 3_656, 3_642,
        3_628, 3_614, 3_600, 3_588, 3_576, 3_562, 3_548, 3_536, 3_524, 3_512, 3_500, 3_486, 3_472, 3_460, 3_448, 3_436,
        3_424, 3_412, 3_400, 3_388, 3_376, 3_364, 3_352, 3_340, 3_328, 3_316, 3_304, 3_292, 3_280, 3_268, 3_256, 3_244,
        3_232, 3_220, 3_208, 3_196, 3_184, 3_174, 3_164, 3_152, 3_140, 3_128, 3_116, 3_106, 3_096, 3_084, 3_072, 3_060,
        3_048, 3_038, 3_028, 3_018, 3_008, 2_996, 2_984, 2_974, 2_964, 2_954, 2_944, 2_932, 2_920, 2_910, 2_900, 2_890,
        2_880, 2_870, 2_860, 2_848, 2_836, 2_826, 2_816, 2_806, 2_796, 2_786, 2_776, 2_766, 2_756, 2_746, 2_736, 2_724,
        2_712, 2_706, 2_700, 2_690, 2_680, 2_670, 2_660, 2_650, 2_640, 2_630, 2_620, 2_612, 2_604, 2_594, 2_584, 2_572,
        2_560, 2_552, 2_544, 2_536, 2_528, 2_520, 2_512, 2_502, 2_492, 2_484, 2_476, 2_466, 2_456, 2_448, 2_440, 2_428,
        2_416, 2_410, 2_404, 2_396, 2_388, 2_378, 2_368, 2_360, 2_352, 2_344, 2_336, 2_328, 2_320, 2_310, 2_300, 2_290,
        2_280, 2_274, 2_268, 2_260, 2_252, 2_244, 2_236, 2_228, 2_220, 2_212, 2_204, 2_196, 2_188, 2_180, 2_172, 2_162,
        2_152, 2_146, 2_140, 2_134, 2_128, 2_120, 2_112, 2_104, 2_096, 2_088, 2_080, 2_072, 2_064, 2_058, 2_052, 2_042,
        2_032, 2_026, 2_020, 2_014, 2_008, 2_000, 1_992, 1_984, 1_976, 1_970, 1_964, 1_956, 1_948, 1_942, 1_936, 1_928,
        1_920, 1_914, 1_908, 1_902, 1_896, 1_888, 1_880, 1_874, 1_868, 1_860, 1_852, 1_846, 1_840, 1_834, 1_828, 1_821,
        1_814, 1_807, 1_800, 1_794, 1_788, 1_781, 1_774, 1_768, 1_762, 1_756, 1_750, 1_743, 1_736, 1_730, 1_724, 1_718,
        1_712, 1_706, 1_700, 1_694, 1_688, 1_682, 1_676, 1_670, 1_664, 1_658, 1_652, 1_646, 1_640, 1_634, 1_628, 1_622,
        1_616, 1_610, 1_604, 1_598, 1_592, 1_587, 1_582, 1_576, 1_570, 1_564, 1_558, 1_553, 1_548, 1_542, 1_536, 1_530,
        1_524, 1_519, 1_514, 1_509, 1_504, 1_498, 1_492, 1_487, 1_482, 1_477, 1_472, 1_466, 1_460, 1_455, 1_450, 1_445,
        1_440, 1_435, 1_430, 1_424, 1_418, 1_413, 1_408, 1_403, 1_398, 1_393, 1_388, 1_383, 1_378, 1_373, 1_368, 1_362,
        1_356, 1_353, 1_350, 1_345, 1_340, 1_335, 1_330, 1_325, 1_320, 1_315, 1_310, 1_306, 1_302, 1_297, 1_292, 1_286,
        1_280, 1_276, 1_272, 1_268, 1_264, 1_260, 1_256, 1_251, 1_246, 1_242, 1_238, 1_233, 1_228, 1_224, 1_220, 1_214,
        1_208, 1_205, 1_202, 1_198, 1_194, 1_189, 1_184, 1_180, 1_176, 1_172, 1_168, 1_164, 1_160, 1_155, 1_150, 1_145,
        1_140, 1_137, 1_134, 1_130, 1_126, 1_122, 1_118, 1_114, 1_110, 1_106, 1_102, 1_098, 1_094, 1_090, 1_086, 1_081,
        1_076, 1_073, 1_070, 1_067, 1_064, 1_060, 1_056, 1_052, 1_048, 1_044, 1_040, 1_036, 1_032, 1_029, 1_026, 1_021,
        1_016, 1_013, 1_010, 1_007, 1_004, 1_000, 996, 992, 988, 985, 982, 978, 974, 971, 968, 964,
        960, 957, 954, 951, 948, 944, 940, 937, 934, 930, 926, 923, 920, 917, 914, 910,
        907, 903, 900, 897, 894, 890, 887, 884, 881, 878, 875, 871, 868, 865, 862, 859,
        856, 853, 850, 847, 844, 841, 838, 835, 832, 829, 826, 823, 820, 817, 814, 811,
        808, 805, 802, 799, 796, 793, 791, 788, 785, 782, 779, 776, 774, 771, 768, 765,
        762, 759, 757, 754, 752, 749, 746, 743, 741, 738, 736, 733, 730, 727, 725, 722,
        720, 717, 715, 712, 709, 706, 704, 701, 699, 696, 694, 691, 689, 686, 684, 681,
        678, 676, 675, 672, 670, 667, 665, 662, 660, 657, 655, 653, 651, 648, 646, 643,
        640, 638, 636, 634, 632, 630, 628, 625, 623, 621, 619, 616, 614, 612, 610, 607,
        604, 602, 601, 599, 597, 594, 592, 590, 588, 586, 584, 582, 580, 577, 575, 572,
        570, 568, 567, 565, 563, 561, 559, 557, 555, 553, 551, 549, 547, 545, 543, 540,
        538, 536, 535, 533, 532, 530, 528, 526, 524, 522, 520, 518, 516, 514, 513, 510,
        508, 506, 505, 503, 502, 500, 498, 496, 494, 492, 491, 489, 487, 485, 484, 482,
        480, 478, 477, 475, 474, 472, 470, 468, 467, 465, 463, 461, 460, 458, 457, 455,
        453, 451, 450, 448, 447, 445, 443, 441, 440, 438, 437, 435, 434, 432, 431, 429,
        428, 426, 425, 423, 422, 420, 419, 417, 416, 414, 413, 411, 410, 408, 407, 405,
        404, 402, 401, 399, 398, 396, 395, 393, 392, 390, 389, 388, 387, 385, 384, 382,
        381, 379, 378, 377, 376, 374, 373, 371, 370, 369, 368, 366, 365, 363, 362, 361,
        360, 358, 357, 355, 354, 353, 352, 350, 349, 348, 347, 345, 344, 343, 342, 340,
        339, 338, 337, 336, 335, 333, 332, 331, 330, 328, 327, 326, 325, 324, 323, 321,
        320, 319, 318, 317, 316, 315, 314, 312, 311, 310, 309, 308, 307, 306, 305, 303,
        302, 301, 300, 299, 298, 297, 296, 295, 294, 293, 292, 291, 290, 288, 287, 286,
        285, 284, 283, 282, 281, 280, 279, 278, 277, 276, 275, 274, 273, 272, 271, 270,
        269, 268, 267, 266, 266, 265, 264, 263, 262, 261, 260, 259, 258, 257, 256, 255,
        254, 253, 252, 251, 251, 250, 249, 248, 247, 246, 245, 244, 243, 242, 242, 241,
        240, 239, 238, 237, 237, 236, 235, 234, 233, 232, 231, 230, 230, 229, 228, 227,
        227, 226, 225, 224, 223, 222, 222, 221, 220, 219, 219, 218, 217, 216, 215, 214,
        214, 213, 212, 211, 211, 210, 209, 208, 208, 207, 206, 205, 205, 204, 203, 202,
        202, 201, 200, 199, 199, 198, 198, 197, 196, 195, 195, 194, 193, 192, 192, 191,
        190, 189, 189, 188, 188, 187, 186, 185, 185, 184, 184, 183, 182, 181, 181, 180,
        180, 179, 179, 178, 177, 176, 176, 175, 175, 174, 173, 172, 172, 171, 171, 170,
        169, 169, 169, 168, 167, 166, 166, 165, 165, 164, 164, 163, 163, 162, 161, 160,
        160, 159, 159, 158, 158, 157, 157, 156, 156, 155, 155, 154, 153, 152, 152, 151,
        151, 150, 150, 149, 149, 148, 148, 147, 147, 146, 146, 145, 145, 144, 144, 143,
        142, 142, 142, 141, 141, 140, 140, 139, 139, 138, 138, 137, 137, 136, 136, 135,
        134, 134, 134, 133, 133, 132, 132, 131, 131, 130, 130, 129, 129, 128, 128, 127,
        127, 126, 126, 125, 125, 124, 124, 123, 123, 123, 123, 122, 122, 121, 121, 120,
        120, 119, 119, 118, 118, 117, 117, 117, 117, 116, 116, 115, 115, 114, 114, 113,
        113, 112, 112, 112, 112, 111, 111, 110, 110, 109, 109, 108, 108, 108, 108, 107,
        107, 106, 106, 105, 105, 105, 105, 104, 104, 103, 103, 102, 102, 102, 102, 101,
        101, 100, 100, 99, 99, 99, 99, 98, 98, 97, 97, 97, 97, 96, 96, 95,
        95, 95, 95, 94, 94, 93, 93, 93, 93, 92, 92, 91, 91, 91, 91, 90,
        90, 89, 89, 89, 89, 88, 88, 87, 87, 87, 87, 86, 86, 85, 85, 85,
        85, 84, 84, 84, 84, 83, 83, 82, 82, 82, 82, 81, 81, 81, 81, 80,
        80, 79, 79, 79, 79, 78, 78, 78, 78, 77, 77, 77, 77, 76, 76, 75,
        75, 75, 75, 75, 75, 74, 74, 73, 73, 73, 73, 72, 72, 72, 72, 71,
        71, 71, 71, 70, 70, 70, 70, 69, 69, 69, 69, 68, 68, 68, 68, 67,
        67, 67, 67, 66, 66, 66, 66, 65, 65, 65, 65, 64, 64, 64, 64, 63,
        63, 63, 63, 63, 63, 62, 62, 62, 62, 61, 61, 61, 61, 60, 60, 60,
        60, 60, 60, 59, 59, 59, 59, 58, 58, 58, 58, 57, 57, 57, 57, 57,
        57, 56, 56, 56, 56, 55, 55, 55, 55, 55, 55, 54, 54, 54, 54, 53,
        53, 53, 53, 53, 53, 52, 52, 52, 52, 52, 52, 51, 51, 51, 51, 50,
        50, 50, 50, 50, 50, 49, 49, 49, 49, 49, 49, 48, 48, 48, 48, 48,
        48, 47, 47, 47, 47, 47, 47, 46, 46, 46, 46, 46, 46, 45, 45, 45,
        45, 45, 45, 44, 44, 44, 44, 44, 44, 43, 43, 43, 43, 43, 43, 42,
        42, 42, 42, 42, 42, 42, 42, 41, 41, 41, 41, 41, 41, 40, 40, 40,
        40, 40, 40, 39, 39, 39, 39, 39, 39, 39, 39, 38, 38, 38, 38, 38,
        38, 38, 38, 37, 37, 37, 37, 37, 37, 36, 36, 36, 36, 36, 36, 36,
        36, 35, 35, 35, 35, 35, 35, 35, 35, 34, 34, 34, 34, 34, 34, 34,
        34, 33, 33, 33, 33, 33, 33, 33, 33, 32, 32, 32, 32, 32, 32, 32,
        32, 32, 32, 31, 31, 31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30,
        30, 30, 30, 30, 30, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 22,
    ]

    static func amigaPeriodFromLookup(effectiveNoteValue: Int, finetune: Int) -> Double {
        let quantizedFinetune = (finetune >> 3) + 16
        let lookupIndex = ((effectiveNoteValue - 1) * 16) + quantizedFinetune
        guard xmAmigaPeriodLookup.indices.contains(lookupIndex) else {
            return xmAmigaC4Period
        }
        return Double(xmAmigaPeriodLookup[lookupIndex]) * xmAmigaPeriodLookupScale
    }

    static func playbackStep(
        amigaPeriod: Double,
        baseSampleRate: Double,
        outputSampleRate: Double
    ) -> Double? {
        guard amigaPeriod.isFinite,
              amigaPeriod > 0,
              outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return nil
        }
        let amigaFrequency = baseSampleRate * xmAmigaC4Period / amigaPeriod
        let step = amigaFrequency / outputSampleRate
        guard amigaFrequency.isFinite,
              amigaFrequency > 0,
              step.isFinite,
              step > 0,
              step <= Double(UInt32.max) else {
            return nil
        }
        return step
    }

    static func clampedLinearPeriod(_ linearPeriod: Double) -> Double {
        guard linearPeriod.isFinite else {
            return xmLinearC4Period
        }
        return min(xmLinearMaximumSafePeriod, max(xmLinearMinimumSafePeriod, linearPeriod))
    }

    static func clampedAmigaPeriod(_ amigaPeriod: Double) -> Double {
        guard amigaPeriod.isFinite else {
            return xmAmigaC4Period
        }
        return min(
            xmAmigaMaximumSafePeriod,
            max(xmAmigaMinimumSafePeriod, amigaPeriod.rounded())
        )
    }

    static func clampedEffectiveNoteValue(note: UInt8, relativeNote: Int) -> Int {
        min(xmLinearMaximumEffectiveNoteValue, max(1, Int(note) + relativeNote))
    }

    static func clampedFinetune(_ finetune: Int) -> Int {
        min(127, max(-128, finetune))
    }

    static func mixerVolumeEnvelope(
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

    static func mappedFrame(
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

    static func hasVolumeEnvelopeMetadata(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        envelope.enabled ||
            !envelope.points.isEmpty ||
            envelope.typeFlags != 0 ||
            envelope.sustainPointIndex != nil ||
            envelope.loopStartPointIndex != nil ||
            envelope.loopEndPointIndex != nil ||
            envelope.fadeout > 0
    }

    static func volumeEnvelopeSemantics(
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

    static func envelopeSustainFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x02) != 0
    }

    static func envelopeLoopFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x04) != 0
    }

    static func fadeoutFrameDecrement(fadeoutValue: Int, sampleRate: Double) -> Float {
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

}
