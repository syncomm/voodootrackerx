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
        let finetuneStatus: PlaybackSongSyntheticEventMapping.FinetuneStatus
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus
        let linearFrequencyApplied: Bool
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
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
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
            finetuneStatus: .applied,
            frequencyTableStatus: .linearApplied,
            linearFrequencyApplied: true,
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

    static func clampedLinearPeriod(_ linearPeriod: Double) -> Double {
        guard linearPeriod.isFinite else {
            return xmLinearC4Period
        }
        return min(xmLinearMaximumSafePeriod, max(xmLinearMinimumSafePeriod, linearPeriod))
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
