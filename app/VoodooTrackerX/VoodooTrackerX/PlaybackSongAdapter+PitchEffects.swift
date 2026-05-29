import Foundation

extension PlaybackSongSyntheticAdapter {
    static func handlePortamentoSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        usesLinearFrequencyTable: Bool,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticPortamentoSlideDiagnostic {
        let direction: PlaybackSongSyntheticPortamentoSlideDirection = cell.effectType == 0x01 ? .up : .down
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentAmigaPeriodBefore = channelState.activeAmigaPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let activeFrequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus =
            (channelState.activeUsesLinearFrequencyTable ?? usesLinearFrequencyTable)
                ? .linearApplied
                : .amigaApplied
        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let requestedSlideAmount = Int(cell.effectParam)
        let rememberedMemory = direction == .up ? channelState.portamentoUpMemory : channelState.portamentoDownMemory
        let slideAmount: Int
        let memorySource: PlaybackSongSyntheticEffectMemorySource?
        let effectMemoryReused: Bool
        let effectMemoryMissing: Bool

        if requestedSlideAmount > 0 {
            slideAmount = requestedSlideAmount
            let memory = PortamentoSlideMemory(amount: requestedSlideAmount, source: targetMemorySource)
            if direction == .up {
                channelState.portamentoUpMemory = memory
            } else {
                channelState.portamentoDownMemory = memory
            }
            memorySource = nil
            effectMemoryReused = false
            effectMemoryMissing = false
        } else if let rememberedMemory {
            slideAmount = rememberedMemory.amount
            memorySource = rememberedMemory.source
            effectMemoryReused = true
            effectMemoryMissing = false
        } else {
            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroParamEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: 0,
                frequencyTableStatus: activeFrequencyTableStatus,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                clamped: false,
                effectMemoryReused: false,
                effectMemoryMissing: true,
                memorySource: nil,
                memoryUnavailableReason: direction == .up
                    ? "missing_1xx_portamento_memory"
                    : "missing_2xx_portamento_memory",
                policy: "zero_param_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: slideAmount,
                frequencyTableStatus: activeFrequencyTableStatus,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                clamped: false,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: effectMemoryMissing,
                memorySource: memorySource,
                memoryUnavailableReason: nil,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        if channelState.activeUsesLinearFrequencyTable == false,
           direction == .down,
           var currentAmigaPeriod = channelState.activeAmigaPeriod,
           var currentPlaybackStep = channelState.activePlaybackStep,
           let baseSampleRate = channelState.activeSampleBaseSampleRate {
            var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
            var clamped = false
            let rowSpeed = max(1, timingConfig.speed)
            let slideUnits = Double(slideAmount) * xmAmigaPortamentoUnitsPerParam
            for tick in 1..<rowSpeed {
                let beforePeriod = currentAmigaPeriod
                let beforeStep = currentPlaybackStep
                let rawAfter = currentAmigaPeriod + slideUnits
                let afterPeriod = clampedAmigaPeriod(rawAfter)
                let didClamp = abs(afterPeriod - rawAfter) > 0.000000001
                clamped = clamped || didClamp
                guard let nextStep = playbackStep(
                    amigaPeriod: afterPeriod,
                    baseSampleRate: baseSampleRate,
                    outputSampleRate: timingConfig.sampleRate
                ) else {
                    return portamentoSlideDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        cell: cell,
                        status: .outOfRange,
                        activeVoiceFound: true,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex,
                        direction: direction,
                        slideAmount: slideAmount,
                        frequencyTableStatus: .amigaApplied,
                        currentLinearPeriodBefore: nil,
                        currentLinearPeriodAfter: nil,
                        currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                        currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                        currentPlaybackStepBefore: currentPlaybackStepBefore,
                        currentPlaybackStepAfter: channelState.activePlaybackStep,
                        stepUpdates: stepUpdates,
                        clamped: clamped,
                        effectMemoryReused: effectMemoryReused,
                        effectMemoryMissing: effectMemoryMissing,
                        memorySource: memorySource,
                        memoryUnavailableReason: nil,
                        policy: "amiga_portamento_down_pitch_out_of_range"
                    )
                }
                currentAmigaPeriod = afterPeriod
                currentPlaybackStep = nextStep
                stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                    syntheticTick: tick,
                    scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                    linearPeriodBefore: beforePeriod,
                    linearPeriodAfter: currentAmigaPeriod,
                    amigaPeriodBefore: beforePeriod,
                    amigaPeriodAfter: currentAmigaPeriod,
                    playbackStepBefore: beforeStep,
                    playbackStepAfter: currentPlaybackStep,
                    reachedTarget: false,
                    clamped: didClamp
                ))
                if didClamp {
                    break
                }
            }

            channelState.activeAmigaPeriod = currentAmigaPeriod
            channelState.activePlaybackStep = currentPlaybackStep

            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .applied,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: slideAmount,
                frequencyTableStatus: .amigaApplied,
                currentLinearPeriodBefore: nil,
                currentLinearPeriodAfter: nil,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: stepUpdates,
                clamped: clamped,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: effectMemoryMissing,
                memorySource: memorySource,
                memoryUnavailableReason: nil,
                policy: effectMemoryReused
                    ? "amiga_zero_param_reuses_prior_2xx_portamento_down_memory"
                    : "amiga_period_units_per_tick_first_pass"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              var currentLinearPeriod = channelState.activeLinearPeriod,
              var currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: slideAmount,
                frequencyTableStatus: activeFrequencyTableStatus,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                clamped: false,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: effectMemoryMissing,
                memorySource: memorySource,
                memoryUnavailableReason: nil,
                policy: "linear_frequency_only_first_pass"
            )
        }

        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        var clamped = false
        let rowSpeed = max(1, timingConfig.speed)
        for tick in 1..<rowSpeed {
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            let rawAfter = direction == .up
                ? currentLinearPeriod - Double(slideAmount)
                : currentLinearPeriod + Double(slideAmount)
            let afterPeriod = clampedLinearPeriod(rawAfter)
            let didClamp = abs(afterPeriod - rawAfter) > 0.000000001
            clamped = clamped || didClamp
            guard let nextStep = playbackStep(
                linearPeriod: afterPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                return portamentoSlideDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    direction: direction,
                    slideAmount: slideAmount,
                    frequencyTableStatus: .linearApplied,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentAmigaPeriodBefore: nil,
                    currentAmigaPeriodAfter: nil,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    clamped: clamped,
                    effectMemoryReused: effectMemoryReused,
                    effectMemoryMissing: effectMemoryMissing,
                    memorySource: memorySource,
                    memoryUnavailableReason: nil,
                    policy: "slide_pitch_out_of_range"
                )
            }
            currentLinearPeriod = afterPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: false,
                clamped: didClamp
            ))
            if didClamp {
                break
            }
        }

        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return portamentoSlideDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            direction: direction,
            slideAmount: slideAmount,
            frequencyTableStatus: .linearApplied,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentAmigaPeriodBefore: nil,
            currentAmigaPeriodAfter: nil,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            memorySource: memorySource,
            memoryUnavailableReason: nil,
            policy: effectMemoryReused
                ? "zero_param_reuses_prior_portamento_slide_memory"
                : "linear_period_units_per_tick_first_pass"
        )
    }

    static func portamentoSlideDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticPortamentoSlideDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        direction: PlaybackSongSyntheticPortamentoSlideDirection,
        slideAmount: Int,
        frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentAmigaPeriodBefore: Double?,
        currentAmigaPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        effectMemoryReused: Bool,
        effectMemoryMissing: Bool,
        memorySource: PlaybackSongSyntheticEffectMemorySource?,
        memoryUnavailableReason: String?,
        policy: String
    ) -> PlaybackSongSyntheticPortamentoSlideDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = effectMemoryMissing || status == .zeroParamEffectMemoryDeferred
        return PlaybackSongSyntheticPortamentoSlideDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .zeroParamEffectMemoryDeferred || status == .unsupportedFrequencyTable,
            ignoredAsNoOp: !applied && status != .unsupportedFrequencyTable,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            effectMemoryDeferred: effectMemoryDeferred,
            memorySource: memorySource,
            memoryUnavailableReason: memoryUnavailableReason,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            direction: direction,
            slideAmount: slideAmount,
            frequencyTableStatus: frequencyTableStatus,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentAmigaPeriodBefore: currentAmigaPeriodBefore,
            currentAmigaPeriodAfter: currentAmigaPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    static func handleFinePortamentoUp(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticFinePortamentoUpDiagnostic {
        let amount = finePortamentoUpAmount(from: cell)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard amount > 0 else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e10_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let currentLinearPeriod = channelState.activeLinearPeriod,
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass"
            )
        }

        let rawAfter = currentLinearPeriod - Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_up_pitch_out_of_range"
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        channelState.activeLinearPeriod = afterPeriod
        channelState.activePlaybackStep = nextStep

        return finePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: [update],
            clamped: clamped,
            policy: "row_start_fine_linear_period_up_first_pass"
        )
    }

    static func finePortamentoUpAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticFinePortamentoUpDiagnostic) {
        let amount = finePortamentoUpAmount(from: cell)
        let currentLinearPeriodBefore = basePitchMapping.linearPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        guard amount > 0 else {
            return (basePitchMapping, finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e10_effect_memory_deferred_no_op"
            ))
        }

        guard basePitchMapping.applied,
              let linearPeriod = basePitchMapping.linearPeriod,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            let status: PlaybackSongSyntheticFinePortamentoUpDiagnostic.Status =
                basePitchMapping.amigaFrequencyDeferred ? .unsupportedFrequencyTable : .outOfRange
            return (basePitchMapping, finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: status,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: status == .unsupportedFrequencyTable
                    ? "linear_frequency_only_first_pass"
                    : "fine_portamento_up_pitch_out_of_range"
            ))
        }

        let rawAfter = linearPeriod - Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return (basePitchMapping, finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_up_pitch_out_of_range"
            ))
        }

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: afterPeriod,
            linearFrequency: nextStep * basePitchMapping.outputSampleRate,
            amigaPeriod: nil,
            amigaFrequency: nil,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: true,
            amigaFrequencyApplied: false,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(nextStep - 1.0) <= 0.000000001
        )
        return (adjustedMapping, finePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: afterPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: nextStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: true,
            stepUpdates: [],
            clamped: clamped,
            policy: "same_cell_note_initial_playback_step_fine_linear_period_up_first_pass"
        ))
    }

    static func finePortamentoUpDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticFinePortamentoUpDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        fineAmount: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        scheduledFrame: Int?,
        appliedToInitialPlaybackStep: Bool,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        policy: String
    ) -> PlaybackSongSyntheticFinePortamentoUpDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .zeroAmountEffectMemoryDeferred
        return PlaybackSongSyntheticFinePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: effectMemoryDeferred ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice || effectMemoryDeferred,
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: fineAmount,
            fineAmountNibble: fineAmount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: appliedToInitialPlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    static func handleFinePortamentoDown(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticFinePortamentoDownDiagnostic {
        let amount = finePortamentoDownAmount(from: cell)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard amount > 0 else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e20_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let currentLinearPeriod = channelState.activeLinearPeriod,
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass"
            )
        }

        let rawAfter = currentLinearPeriod + Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_down_pitch_out_of_range"
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        channelState.activeLinearPeriod = afterPeriod
        channelState.activePlaybackStep = nextStep

        return finePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: [update],
            clamped: clamped,
            policy: "row_start_fine_linear_period_down_first_pass"
        )
    }

    static func finePortamentoDownAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticFinePortamentoDownDiagnostic) {
        let amount = finePortamentoDownAmount(from: cell)
        let currentLinearPeriodBefore = basePitchMapping.linearPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        guard amount > 0 else {
            return (basePitchMapping, finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e20_effect_memory_deferred_no_op"
            ))
        }

        guard basePitchMapping.applied,
              let linearPeriod = basePitchMapping.linearPeriod,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            let status: PlaybackSongSyntheticFinePortamentoDownDiagnostic.Status =
                basePitchMapping.amigaFrequencyDeferred ? .unsupportedFrequencyTable : .outOfRange
            return (basePitchMapping, finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: status,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: status == .unsupportedFrequencyTable
                    ? "linear_frequency_only_first_pass"
                    : "fine_portamento_down_pitch_out_of_range"
            ))
        }

        let rawAfter = linearPeriod + Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return (basePitchMapping, finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_down_pitch_out_of_range"
            ))
        }

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: afterPeriod,
            linearFrequency: nextStep * basePitchMapping.outputSampleRate,
            amigaPeriod: nil,
            amigaFrequency: nil,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: true,
            amigaFrequencyApplied: false,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(nextStep - 1.0) <= 0.000000001
        )
        return (adjustedMapping, finePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: afterPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: nextStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: true,
            stepUpdates: [],
            clamped: clamped,
            policy: "same_cell_note_initial_playback_step_fine_linear_period_down_first_pass"
        ))
    }

    static func finePortamentoDownDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticFinePortamentoDownDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        fineAmount: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        scheduledFrame: Int?,
        appliedToInitialPlaybackStep: Bool,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        policy: String
    ) -> PlaybackSongSyntheticFinePortamentoDownDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .zeroAmountEffectMemoryDeferred
        return PlaybackSongSyntheticFinePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: effectMemoryDeferred ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice || effectMemoryDeferred,
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: fineAmount,
            fineAmountNibble: fineAmount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: appliedToInitialPlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    static func handleExtraFinePortamento(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticExtraFinePortamentoDiagnostic {
        let subcommand = xxySubcommand(from: cell)
        let amount = xxyAmount(from: cell)
        let direction = xxyDirection(from: cell)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard let direction else {
            return extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedSubcommand,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: nil,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "xxy_unsupported_subcommand_deferred"
            )
        }

        guard amount > 0 else {
            return extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: direction == .up
                    ? "x10_effect_memory_deferred_no_op"
                    : "x20_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let currentLinearPeriod = channelState.activeLinearPeriod,
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass"
            )
        }

        let rawAfter = direction == .up
            ? currentLinearPeriod - Double(amount)
            : currentLinearPeriod + Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "xxy_extra_fine_portamento_pitch_out_of_range"
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        channelState.activeLinearPeriod = afterPeriod
        channelState.activePlaybackStep = nextStep

        return extraFinePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            subcommand: subcommand,
            direction: direction,
            amount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: [update],
            clamped: clamped,
            policy: direction == .up
                ? "row_start_x1x_extra_fine_linear_period_up_first_pass"
                : "row_start_x2x_extra_fine_linear_period_down_first_pass"
        )
    }

    static func extraFinePortamentoAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticExtraFinePortamentoDiagnostic) {
        let subcommand = xxySubcommand(from: cell)
        let amount = xxyAmount(from: cell)
        let direction = xxyDirection(from: cell)
        let currentLinearPeriodBefore = basePitchMapping.linearPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        guard let direction else {
            return (basePitchMapping, extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedSubcommand,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                subcommand: subcommand,
                direction: nil,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "xxy_unsupported_subcommand_deferred"
            ))
        }

        guard amount > 0 else {
            return (basePitchMapping, extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: direction == .up
                    ? "x10_effect_memory_deferred_no_op"
                    : "x20_effect_memory_deferred_no_op"
            ))
        }

        guard basePitchMapping.applied,
              let linearPeriod = basePitchMapping.linearPeriod,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            let status: PlaybackSongSyntheticExtraFinePortamentoDiagnostic.Status =
                basePitchMapping.amigaFrequencyDeferred ? .unsupportedFrequencyTable : .outOfRange
            return (basePitchMapping, extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: status,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: status == .unsupportedFrequencyTable
                    ? "linear_frequency_only_first_pass"
                    : "xxy_extra_fine_portamento_pitch_out_of_range"
            ))
        }

        let rawAfter = direction == .up
            ? linearPeriod - Double(amount)
            : linearPeriod + Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return (basePitchMapping, extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "xxy_extra_fine_portamento_pitch_out_of_range"
            ))
        }

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: afterPeriod,
            linearFrequency: nextStep * basePitchMapping.outputSampleRate,
            amigaPeriod: nil,
            amigaFrequency: nil,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: true,
            amigaFrequencyApplied: false,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(nextStep - 1.0) <= 0.000000001
        )
        return (adjustedMapping, extraFinePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            subcommand: subcommand,
            direction: direction,
            amount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: afterPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: nextStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: true,
            stepUpdates: [],
            clamped: clamped,
            policy: direction == .up
                ? "same_cell_note_initial_playback_step_x1x_extra_fine_linear_period_up_first_pass"
                : "same_cell_note_initial_playback_step_x2x_extra_fine_linear_period_down_first_pass"
        ))
    }

    static func extraFinePortamentoDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticExtraFinePortamentoDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        subcommand: Int,
        direction: PlaybackSongSyntheticPortamentoSlideDirection?,
        amount: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        scheduledFrame: Int?,
        appliedToInitialPlaybackStep: Bool,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        policy: String
    ) -> PlaybackSongSyntheticExtraFinePortamentoDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .zeroAmountEffectMemoryDeferred
        return PlaybackSongSyntheticExtraFinePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: effectMemoryDeferred ||
                status == .unsupportedSubcommand ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice || effectMemoryDeferred,
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            subcommand: subcommand,
            direction: direction,
            amount: amount,
            amountNibble: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: appliedToInitialPlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    static func handleArpeggio(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        includeTickZeroUpdate: Bool = true
    ) -> PlaybackSongSyntheticArpeggioDiagnostic {
        let xSemitoneOffset = Int((cell.effectParam & 0xF0) >> 4)
        let ySemitoneOffset = Int(cell.effectParam & 0x0F)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep

        guard hasActiveVoice else {
            return arpeggioDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                xSemitoneOffset: xSemitoneOffset,
                ySemitoneOffset: ySemitoneOffset,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let baseLinearPeriod = channelState.activeLinearPeriod,
              let basePlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return arpeggioDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                xSemitoneOffset: xSemitoneOffset,
                ySemitoneOffset: ySemitoneOffset,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "linear_frequency_only_first_pass"
            )
        }

        var currentLinearPeriod = baseLinearPeriod
        var currentPlaybackStep = basePlaybackStep
        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        let firstTick = includeTickZeroUpdate ? 0 : 1
        for tick in firstTick..<rowSpeed {
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            let semitoneOffset: Int
            switch tick % 3 {
            case 1:
                semitoneOffset = xSemitoneOffset
            case 2:
                semitoneOffset = ySemitoneOffset
            default:
                semitoneOffset = 0
            }
            let modulatedPeriod = clampedLinearPeriod(
                baseLinearPeriod - (Double(semitoneOffset) * xmLinearPeriodUnitsPerSemitone)
            )
            guard let nextStep = playbackStep(
                linearPeriod: modulatedPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                return arpeggioDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    xSemitoneOffset: xSemitoneOffset,
                    ySemitoneOffset: ySemitoneOffset,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    policy: "arpeggio_pitch_out_of_range"
                )
            }
            currentLinearPeriod = modulatedPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: semitoneOffset == 0
            ))
        }

        if !stepUpdates.isEmpty,
           abs(currentPlaybackStep - basePlaybackStep) > 0.000000001 {
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: rowSpeed,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow + 1, tick: 0),
                linearPeriodBefore: currentLinearPeriod,
                linearPeriodAfter: baseLinearPeriod,
                playbackStepBefore: currentPlaybackStep,
                playbackStepAfter: basePlaybackStep,
                reachedTarget: true
            ))
            currentLinearPeriod = baseLinearPeriod
            currentPlaybackStep = basePlaybackStep
        }

        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return arpeggioDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            xSemitoneOffset: xSemitoneOffset,
            ySemitoneOffset: ySemitoneOffset,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            policy: "deterministic_0xy_tick_cycle_no_effect_memory"
        )
    }

    static func arpeggioDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticArpeggioDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        xSemitoneOffset: Int,
        ySemitoneOffset: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        policy: String
    ) -> PlaybackSongSyntheticArpeggioDiagnostic {
        let applied = status == .applied
        return PlaybackSongSyntheticArpeggioDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .unsupportedFrequencyTable || status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice,
            effectMemoryDeferred: false,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            xSemitoneOffset: xSemitoneOffset,
            ySemitoneOffset: ySemitoneOffset,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

    static func handleVibrato(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticVibratoDiagnostic {
        let isVibratoVolumeSlide = isVibratoVolumeSlideEffect(cell)
        let paramSpeed = Int((cell.effectParam & 0xF0) >> 4)
        let paramDepth = Int(cell.effectParam & 0x0F)
        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let rememberedSpeed = channelState.vibratoSpeed
        let rememberedDepth = channelState.vibratoDepth
        let rememberedSpeedSource = channelState.vibratoSpeedMemorySource
        let rememberedDepthSource = channelState.vibratoDepthMemorySource
        let speed: Int
        let depth: Int
        let speedSource: String?
        let depthSource: String?
        let speedMemorySource: PlaybackSongSyntheticEffectMemorySource?
        let depthMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var missingMemoryReasons = [String]()

        if isVibratoVolumeSlide {
            if let rememberedSpeed {
                speed = rememberedSpeed
                speedSource = "4xy_channel_state"
                speedMemorySource = rememberedSpeedSource
            } else {
                speed = 0
                speedSource = "missing_4xy_channel_state"
                speedMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_speed_memory")
            }
            if let rememberedDepth {
                depth = rememberedDepth
                depthSource = "4xy_channel_state"
                depthMemorySource = rememberedDepthSource
            } else {
                depth = 0
                depthSource = "missing_4xy_channel_state"
                depthMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_depth_memory")
            }
        } else {
            if paramSpeed > 0 {
                speed = paramSpeed
                speedSource = "effect_param"
                speedMemorySource = nil
                channelState.vibratoSpeed = paramSpeed
                channelState.vibratoSpeedMemorySource = targetMemorySource
            } else if let rememberedSpeed {
                speed = rememberedSpeed
                speedSource = "4xy_channel_state"
                speedMemorySource = rememberedSpeedSource
            } else {
                speed = 0
                speedSource = "missing_4xy_channel_state"
                speedMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_speed_memory")
            }

            if paramDepth > 0 {
                depth = paramDepth
                depthSource = "effect_param"
                depthMemorySource = nil
                channelState.vibratoDepth = paramDepth
                channelState.vibratoDepthMemorySource = targetMemorySource
            } else if let rememberedDepth {
                depth = rememberedDepth
                depthSource = "4xy_channel_state"
                depthMemorySource = rememberedDepthSource
            } else {
                depth = 0
                depthSource = "missing_4xy_channel_state"
                depthMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_depth_memory")
            }
        }

        let effectMemoryReused = speedMemorySource != nil || depthMemorySource != nil
        let effectMemoryMissing = !missingMemoryReasons.isEmpty
        let memoryUnavailableReason = memoryUnavailableReason(from: missingMemoryReasons)
        let volumeSlide = isVibratoVolumeSlide ? volumeSlideAmounts(effectParam: cell.effectParam) : nil
        let hasActiveVoice = channelState.activeEventIndex != nil
        let phaseBefore = channelState.vibratoPhase
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let vibratoControl = channelState.vibratoControl ?? VibratoControlState(
            controlValue: 0,
            waveform: .sine,
            retriggerSuppressed: false,
            source: nil
        )
        let waveformSource = vibratoControl.source == nil ? "default_sine" : "e4x_channel_state"

        guard !effectMemoryMissing else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: cell.effectParam == 0 ? .zeroParamEffectMemoryDeferred : .zeroSpeedOrDepthEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: true,
                effectMemoryDeferred: true,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: memoryUnavailableReason,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: isVibratoVolumeSlide
                    ? "6xy_missing_vibrato_memory_deferred_no_op"
                    : "4xy_missing_vibrato_memory_deferred_no_op"
            )
        }

        if isVibratoVolumeSlide, !hasActiveVoice {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard speed > 0, depth > 0 else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroSpeedOrDepthEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: true,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: isVibratoVolumeSlide
                    ? "6xy_missing_4xy_vibrato_memory_deferred_no_op"
                    : "zero_speed_or_depth_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let baseLinearPeriod = channelState.activeLinearPeriod,
              let basePlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "linear_frequency_only_first_pass"
            )
        }

        var phase = channelState.vibratoPhase
        var currentLinearPeriod = baseLinearPeriod
        var currentPlaybackStep = basePlaybackStep
        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        let periodDepth = Double(depth) * 4.0
        for tick in 1..<rowSpeed {
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            phase += Double(speed) * (.pi / 32.0)
            let modulatedPeriod = clampedLinearPeriod(
                baseLinearPeriod - (vibratoWaveformValue(vibratoControl.waveform, phase: phase) * periodDepth)
            )
            guard let nextStep = playbackStep(
                linearPeriod: modulatedPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                channelState.vibratoPhase = phase
                return vibratoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    speed: speed,
                    depth: depth,
                    speedSource: speedSource,
                    depthSource: depthSource,
                    controlValue: vibratoControl.controlValue,
                    waveform: vibratoControl.waveform,
                    waveformSource: waveformSource,
                    effectMemoryReused: effectMemoryReused,
                    effectMemoryMissing: false,
                    effectMemoryDeferred: false,
                    speedMemorySource: speedMemorySource,
                    depthMemorySource: depthMemorySource,
                    memoryUnavailableReason: nil,
                    volumeSlide: volumeSlide,
                    phaseBefore: phaseBefore,
                    phaseAfter: channelState.vibratoPhase,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    policy: "vibrato_pitch_out_of_range"
                )
            }
            currentLinearPeriod = modulatedPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: false
            ))
        }

        if !stepUpdates.isEmpty,
           abs(currentPlaybackStep - basePlaybackStep) > 0.000000001 {
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: rowSpeed,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow + 1, tick: 0),
                linearPeriodBefore: currentLinearPeriod,
                linearPeriodAfter: baseLinearPeriod,
                playbackStepBefore: currentPlaybackStep,
                playbackStepAfter: basePlaybackStep,
                reachedTarget: true
            ))
            currentLinearPeriod = baseLinearPeriod
            currentPlaybackStep = basePlaybackStep
        }

        channelState.vibratoPhase = phase
        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return vibratoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            speed: speed,
            depth: depth,
            speedSource: speedSource,
            depthSource: depthSource,
            controlValue: vibratoControl.controlValue,
            waveform: vibratoControl.waveform,
            waveformSource: waveformSource,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: false,
            effectMemoryDeferred: false,
            speedMemorySource: speedMemorySource,
            depthMemorySource: depthMemorySource,
            memoryUnavailableReason: nil,
            volumeSlide: volumeSlide,
            phaseBefore: phaseBefore,
            phaseAfter: channelState.vibratoPhase,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            policy: isVibratoVolumeSlide
                ? "6xy_reuses_4xy_vibrato_state_plus_row_level_volume_slide"
                : "deterministic_vibrato_waveform_linear_period_first_pass"
        )
    }

    static func handleVibratoControl(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticVibratoControlDiagnostic {
        let controlValue = Int(cell.effectParam & 0x0F)
        let waveformID = controlValue & 0x03
        let retriggerSuppressed = (controlValue & 0x04) != 0
        let activeEventIndex = channelState.activeEventIndex
        let activeEventMappingIndex = channelState.activeEventMappingIndex
        guard let waveform = supportedVibratoWaveform(controlValue: controlValue) else {
            return PlaybackSongSyntheticVibratoControlDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .unsupportedWaveform,
                detected: true,
                applied: false,
                stored: false,
                deferred: true,
                ignoredAsNoOp: false,
                activeVoiceFound: activeEventIndex != nil,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                controlValue: controlValue,
                waveformID: waveformID,
                waveformName: "unsupported",
                retriggerSuppressed: retriggerSuppressed,
                unsupportedWaveform: true,
                affectsLaterVibrato: false,
                policy: "unsupported_e4x_vibrato_control_deferred"
            )
        }

        channelState.vibratoControl = VibratoControlState(
            controlValue: controlValue,
            waveform: waveform,
            retriggerSuppressed: retriggerSuppressed,
            source: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        )
        return PlaybackSongSyntheticVibratoControlDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .stored,
            detected: true,
            applied: true,
            stored: true,
            deferred: false,
            ignoredAsNoOp: false,
            activeVoiceFound: activeEventIndex != nil,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            controlValue: controlValue,
            waveformID: waveform.rawValue,
            waveformName: waveform.name,
            retriggerSuppressed: retriggerSuppressed,
            unsupportedWaveform: false,
            affectsLaterVibrato: true,
            policy: "e4x_stores_deterministic_vibrato_waveform_for_later_4xy_6xy"
        )
    }

    static func supportedVibratoWaveform(controlValue: Int) -> VibratoWaveform? {
        guard (0...3).contains(controlValue) else {
            return nil
        }
        return VibratoWaveform(rawValue: controlValue)
    }

    static func vibratoWaveformValue(_ waveform: VibratoWaveform, phase: Double) -> Double {
        switch waveform {
        case .sine:
            return sin(phase)
        case .rampDown:
            let cycle = normalizedCycle(phase)
            return 1.0 - (cycle * 2.0)
        case .square:
            return normalizedCycle(phase) < 0.5 ? 1.0 : -1.0
        case .random:
            return deterministicRandomVibratoValue(phase: phase)
        }
    }

    static func normalizedCycle(_ phase: Double) -> Double {
        let period = Double.pi * 2.0
        let remainder = phase.truncatingRemainder(dividingBy: period)
        return (remainder < 0 ? remainder + period : remainder) / period
    }

    static func deterministicRandomVibratoValue(phase: Double) -> Double {
        let phaseStep = Int((phase / (.pi / 32.0)).rounded(.down))
        let hashed = UInt32(truncatingIfNeeded: phaseStep &* 1_103_515_245 &+ 12_345)
        return (Double((hashed >> 16) & 0x7FFF) / 16_383.5) - 1.0
    }

    static func vibratoDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticVibratoDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        speed: Int,
        depth: Int,
        speedSource: String?,
        depthSource: String?,
        controlValue: Int,
        waveform: VibratoWaveform,
        waveformSource: String,
        effectMemoryReused: Bool,
        effectMemoryMissing: Bool,
        effectMemoryDeferred: Bool,
        speedMemorySource: PlaybackSongSyntheticEffectMemorySource?,
        depthMemorySource: PlaybackSongSyntheticEffectMemorySource?,
        memoryUnavailableReason: String?,
        volumeSlide: VolumeSlideAmounts?,
        phaseBefore: Double,
        phaseAfter: Double,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        policy: String
    ) -> PlaybackSongSyntheticVibratoDiagnostic {
        let applied = status == .applied
        return PlaybackSongSyntheticVibratoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .zeroParamEffectMemoryDeferred ||
                status == .zeroSpeedOrDepthEffectMemoryDeferred ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice ||
                status == .zeroParamEffectMemoryDeferred ||
                status == .zeroSpeedOrDepthEffectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            vibratoSpeed: speed,
            vibratoDepth: depth,
            vibratoSpeedSource: speedSource,
            vibratoDepthSource: depthSource,
            vibratoControlValue: controlValue,
            vibratoWaveform: waveform.name,
            vibratoWaveformSource: waveformSource,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            effectMemoryDeferred: effectMemoryDeferred,
            vibratoSpeedMemorySource: speedMemorySource,
            vibratoDepthMemorySource: depthMemorySource,
            memoryUnavailableReason: memoryUnavailableReason,
            volumeSlideUp: volumeSlide?.up,
            volumeSlideDown: volumeSlide?.down,
            volumeSlideAmount: volumeSlide?.amount,
            volumeSlideDirection: volumeSlide?.direction,
            phaseBefore: phaseBefore,
            phaseAfter: phaseAfter,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

    static func handleTonePortamento(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        usesLinearFrequencyTable: Bool,
        channelState: inout ChannelState,
        instrumentStateBefore: ChannelState? = nil,
        instrumentStateAfter: ChannelState? = nil,
        instrumentDefaultVolumeApplied: Bool = false,
        sampleSelectedBefore: Int? = nil,
        sampleSelectedAfter: Int? = nil,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic? = nil
    ) -> PlaybackSongSyntheticTonePortamentoDiagnostic {
        let volumeColumnTonePortamentoAmount: Int?
        if case let .tonePortamento(amount) = volumeColumn?.command {
            volumeColumnTonePortamentoAmount = amount
        } else {
            volumeColumnTonePortamentoAmount = nil
        }
        let commandSource: PlaybackSongSyntheticTonePortamentoCommandSource =
            volumeColumnTonePortamentoAmount == nil ? .effectColumn : .volumeColumn
        let hasActiveVoice = channelState.activeEventIndex != nil
        let activeUsesAmigaFrequencyTable = !(channelState.activeUsesLinearFrequencyTable ?? usesLinearFrequencyTable)
        let activeFrequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus =
            activeUsesAmigaFrequencyTable ? .amigaApplied : .linearApplied
        let targetExistsBefore = channelState.tonePortamentoTargetPlaybackStep != nil &&
            (activeUsesAmigaFrequencyTable
                ? channelState.tonePortamentoTargetAmigaPeriod != nil
                : channelState.tonePortamentoTargetLinearPeriod != nil)
        let noteTargetBefore = channelState.tonePortamentoTargetNote
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentAmigaPeriodBefore = channelState.activeAmigaPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let targetNoteFromCell = (1...96).contains(cell.note) ? cell.note : nil
        let sameCellNote = targetNoteFromCell != nil
        let instrumentStateUpdated = instrumentStateAfter != nil
        let channelVolumeBefore = instrumentStateBefore?.volumeValue
        let channelVolumeAfter = instrumentStateAfter?.volumeValue
        let gainBefore = instrumentStateBefore?.activeSampleVolume.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: instrumentStateBefore?.volumeValue ?? 64
            )
        }
        let gainAfter = instrumentStateAfter?.activeSampleVolume.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: instrumentStateAfter?.volumeValue ?? 64
            )
        }

        if cell.effectType == 0x03, cell.effectParam > 0 {
            channelState.tonePortamentoSpeed = Int(cell.effectParam)
        }
        if cell.effectType != 0x03,
           let volumeColumnTonePortamentoAmount,
           volumeColumnTonePortamentoAmount > 0 {
            channelState.tonePortamentoSpeed = volumeColumnTonePortamentoAmount
        }

        guard hasActiveVoice else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsBefore,
                frequencyTableStatus: activeFrequencyTableStatus,
                targetNote: targetNoteFromCell ?? channelState.tonePortamentoTargetNote,
                targetLinearPeriod: channelState.tonePortamentoTargetLinearPeriod,
                targetAmigaPeriod: channelState.tonePortamentoTargetAmigaPeriod,
                targetPlaybackStep: channelState.tonePortamentoTargetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                stepUpdates: [],
                policy: "no_active_voice_no_retrigger"
            )
        }

        if let targetNote = targetNoteFromCell {
            guard let baseSampleRate = channelState.activeSampleBaseSampleRate,
                  let relativeNote = channelState.activeSampleRelativeNote,
                  let finetune = channelState.activeSampleFinetune else {
                return tonePortamentoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    commandSource: commandSource,
                    rawVolumeColumn: volumeColumn?.rawValue,
                    status: .unsupportedFrequencyTable,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    targetExistsBefore: targetExistsBefore,
                    targetExistsAfter: targetExistsBefore,
                    frequencyTableStatus: activeFrequencyTableStatus,
                    targetNote: targetNote,
                    targetLinearPeriod: channelState.tonePortamentoTargetLinearPeriod,
                    targetAmigaPeriod: channelState.tonePortamentoTargetAmigaPeriod,
                    targetPlaybackStep: channelState.tonePortamentoTargetPlaybackStep,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                    currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                    stepUpdates: [],
                    policy: "missing_active_pitch_sample_state"
                )
            }

            if channelState.activeUsesLinearFrequencyTable == true {
                guard let target = linearPitchTarget(
                    note: targetNote,
                    relativeNote: relativeNote,
                    finetune: finetune,
                    baseSampleRate: baseSampleRate,
                    outputSampleRate: timingConfig.sampleRate
                ) else {
                    return tonePortamentoDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        cell: cell,
                        commandSource: commandSource,
                        rawVolumeColumn: volumeColumn?.rawValue,
                        status: .outOfRange,
                        activeVoiceFound: true,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex,
                        targetExistsBefore: targetExistsBefore,
                        targetExistsAfter: targetExistsBefore,
                        frequencyTableStatus: .linearApplied,
                        targetNote: targetNote,
                        targetLinearPeriod: nil,
                        targetAmigaPeriod: nil,
                        targetPlaybackStep: nil,
                        currentLinearPeriodBefore: currentLinearPeriodBefore,
                        currentLinearPeriodAfter: channelState.activeLinearPeriod,
                        currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                        currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                        currentPlaybackStepBefore: currentPlaybackStepBefore,
                        currentPlaybackStepAfter: channelState.activePlaybackStep,
                        portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                        stepUpdates: [],
                        policy: "target_pitch_out_of_range"
                    )
                }
                channelState.tonePortamentoTargetNote = targetNote
                channelState.tonePortamentoTargetLinearPeriod = target.linearPeriod
                channelState.tonePortamentoTargetAmigaPeriod = nil
                channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
            } else if channelState.activeUsesLinearFrequencyTable == false,
                      commandSource == .effectColumn,
                      cell.effectType == 0x03 {
                guard let target = amigaPitchTarget(
                    note: targetNote,
                    relativeNote: relativeNote,
                    finetune: finetune,
                    baseSampleRate: baseSampleRate,
                    outputSampleRate: timingConfig.sampleRate
                ) else {
                    return tonePortamentoDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        cell: cell,
                        commandSource: commandSource,
                        rawVolumeColumn: volumeColumn?.rawValue,
                        status: .outOfRange,
                        activeVoiceFound: true,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex,
                        targetExistsBefore: targetExistsBefore,
                        targetExistsAfter: targetExistsBefore,
                        frequencyTableStatus: .amigaApplied,
                        targetNote: targetNote,
                        targetLinearPeriod: nil,
                        targetAmigaPeriod: nil,
                        targetPlaybackStep: nil,
                        currentLinearPeriodBefore: currentLinearPeriodBefore,
                        currentLinearPeriodAfter: channelState.activeLinearPeriod,
                        currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                        currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                        currentPlaybackStepBefore: currentPlaybackStepBefore,
                        currentPlaybackStepAfter: channelState.activePlaybackStep,
                        portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                        stepUpdates: [],
                        policy: "amiga_target_pitch_out_of_range"
                    )
                }
                channelState.tonePortamentoTargetNote = targetNote
                channelState.tonePortamentoTargetLinearPeriod = nil
                channelState.tonePortamentoTargetAmigaPeriod = target.amigaPeriod
                channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
            } else {
                return tonePortamentoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    commandSource: commandSource,
                    rawVolumeColumn: volumeColumn?.rawValue,
                    status: .unsupportedFrequencyTable,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    targetExistsBefore: targetExistsBefore,
                    targetExistsAfter: targetExistsBefore,
                    frequencyTableStatus: activeFrequencyTableStatus,
                    targetNote: targetNote,
                    targetLinearPeriod: channelState.tonePortamentoTargetLinearPeriod,
                    targetAmigaPeriod: channelState.tonePortamentoTargetAmigaPeriod,
                    targetPlaybackStep: channelState.tonePortamentoTargetPlaybackStep,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                    currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                    stepUpdates: [],
                    policy: "amiga_tone_portamento_limited_to_3xx_first_pass"
                )
            }
        }

        let targetExistsAfter = channelState.tonePortamentoTargetPlaybackStep != nil &&
            (activeUsesAmigaFrequencyTable
                ? channelState.tonePortamentoTargetAmigaPeriod != nil
                : channelState.tonePortamentoTargetLinearPeriod != nil)
        guard targetExistsAfter,
              let targetPlaybackStep = channelState.tonePortamentoTargetPlaybackStep else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .noTarget,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: false,
                frequencyTableStatus: activeFrequencyTableStatus,
                targetNote: targetNoteFromCell,
                targetLinearPeriod: nil,
                targetAmigaPeriod: nil,
                targetPlaybackStep: nil,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                stepUpdates: [],
                policy: commandSource == .volumeColumn
                    ? "volume_column_tone_portamento_no_existing_target"
                    : cell.effectType == 0x05
                        ? "5xy_no_existing_tone_portamento_target"
                        : "no_existing_target"
            )
        }
        let targetLinearPeriod = channelState.tonePortamentoTargetLinearPeriod
        let targetAmigaPeriod = channelState.tonePortamentoTargetAmigaPeriod
        guard let speed = channelState.tonePortamentoSpeed,
              speed > 0 else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .noSpeed,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsAfter,
                frequencyTableStatus: activeFrequencyTableStatus,
                targetNote: channelState.tonePortamentoTargetNote,
                targetLinearPeriod: targetLinearPeriod,
                targetAmigaPeriod: targetAmigaPeriod,
                targetPlaybackStep: targetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                stepUpdates: [],
                policy: commandSource == .volumeColumn
                    ? "volume_column_tone_portamento_no_speed"
                    : cell.effectType == 0x05
                        ? "5xy_no_existing_3xx_speed_memory"
                        : "no_3xx_speed_memory"
            )
        }
        guard var currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsAfter,
                frequencyTableStatus: activeFrequencyTableStatus,
                targetNote: channelState.tonePortamentoTargetNote,
                targetLinearPeriod: targetLinearPeriod,
                targetAmigaPeriod: targetAmigaPeriod,
                targetPlaybackStep: targetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: speed,
                stepUpdates: [],
                policy: "missing_active_pitch_state"
            )
        }

        if activeUsesAmigaFrequencyTable {
            guard var currentAmigaPeriod = channelState.activeAmigaPeriod,
                  let targetAmigaPeriod else {
                return tonePortamentoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    commandSource: commandSource,
                    rawVolumeColumn: volumeColumn?.rawValue,
                    status: .unsupportedFrequencyTable,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    targetExistsBefore: targetExistsBefore,
                    targetExistsAfter: targetExistsAfter,
                    frequencyTableStatus: .amigaApplied,
                    targetNote: channelState.tonePortamentoTargetNote,
                    targetLinearPeriod: nil,
                    targetAmigaPeriod: targetAmigaPeriod,
                    targetPlaybackStep: targetPlaybackStep,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                    currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    portamentoSpeed: speed,
                    stepUpdates: [],
                    policy: "missing_active_amiga_pitch_state"
                )
            }

            var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
            let rowSpeed = max(1, timingConfig.speed)
            let slideUnits = Double(speed) * xmAmigaPortamentoUnitsPerParam
            for tick in 1..<rowSpeed {
                if abs(currentAmigaPeriod - targetAmigaPeriod) <= 0.000000001 {
                    currentAmigaPeriod = targetAmigaPeriod
                    currentPlaybackStep = targetPlaybackStep
                    break
                }
                let beforePeriod = currentAmigaPeriod
                let beforeStep = currentPlaybackStep
                if targetAmigaPeriod < currentAmigaPeriod {
                    currentAmigaPeriod = max(targetAmigaPeriod, currentAmigaPeriod - slideUnits)
                } else {
                    currentAmigaPeriod = min(targetAmigaPeriod, currentAmigaPeriod + slideUnits)
                }
                guard let nextStep = playbackStep(
                    amigaPeriod: currentAmigaPeriod,
                    baseSampleRate: baseSampleRate,
                    outputSampleRate: timingConfig.sampleRate
                ) else {
                    break
                }
                currentPlaybackStep = nextStep
                let reachedTarget = abs(currentAmigaPeriod - targetAmigaPeriod) <= 0.000000001
                stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                    syntheticTick: tick,
                    scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                    linearPeriodBefore: beforePeriod,
                    linearPeriodAfter: currentAmigaPeriod,
                    amigaPeriodBefore: beforePeriod,
                    amigaPeriodAfter: currentAmigaPeriod,
                    playbackStepBefore: beforeStep,
                    playbackStepAfter: currentPlaybackStep,
                    reachedTarget: reachedTarget
                ))
                if reachedTarget {
                    currentAmigaPeriod = targetAmigaPeriod
                    currentPlaybackStep = targetPlaybackStep
                    break
                }
            }
            channelState.activeAmigaPeriod = currentAmigaPeriod
            channelState.activePlaybackStep = currentPlaybackStep

            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .applied,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                sameCellNote: sameCellNote,
                noteTriggerEventCreated: false,
                voiceReplacement: false,
                samplePositionReset: false,
                instrumentStateUpdated: instrumentStateUpdated,
                instrumentIndexBefore: instrumentStateBefore?.activeInstrumentIndex,
                instrumentIndexAfter: instrumentStateAfter?.activeInstrumentIndex,
                sampleSelectedBefore: sampleSelectedBefore,
                sampleSelectedAfter: sampleSelectedAfter,
                instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
                envelopeReset: false,
                envelopeResetModeled: false,
                channelVolumeBefore: channelVolumeBefore,
                channelVolumeAfter: channelVolumeAfter,
                gainBefore: gainBefore,
                gainAfter: gainAfter,
                noteTargetBefore: noteTargetBefore,
                noteTargetAfter: channelState.tonePortamentoTargetNote,
                audibleTransientExpected: instrumentDefaultVolumeApplied &&
                    ((gainBefore ?? 0) < (gainAfter ?? 0)),
                cMixerReceivesNewVoice: false,
                cMixerReceivesOnlyStateUpdates: sameCellNote,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsAfter,
                frequencyTableStatus: .amigaApplied,
                targetNote: channelState.tonePortamentoTargetNote,
                targetLinearPeriod: nil,
                targetAmigaPeriod: targetAmigaPeriod,
                targetPlaybackStep: targetPlaybackStep,
                currentLinearPeriodBefore: nil,
                currentLinearPeriodAfter: nil,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: speed,
                stepUpdates: stepUpdates,
                policy: "amiga_period_units_per_tick_row_level_first_pass"
            )
        }

        guard var currentLinearPeriod = channelState.activeLinearPeriod,
              let targetLinearPeriod else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsAfter,
                frequencyTableStatus: .linearApplied,
                targetNote: channelState.tonePortamentoTargetNote,
                targetLinearPeriod: targetLinearPeriod,
                targetAmigaPeriod: nil,
                targetPlaybackStep: targetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: speed,
                stepUpdates: [],
                policy: "missing_active_linear_pitch_state"
            )
        }

        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        for tick in 1..<rowSpeed {
            if abs(currentLinearPeriod - targetLinearPeriod) <= 0.000000001 {
                currentLinearPeriod = targetLinearPeriod
                currentPlaybackStep = targetPlaybackStep
                break
            }
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            if targetLinearPeriod < currentLinearPeriod {
                currentLinearPeriod = max(targetLinearPeriod, currentLinearPeriod - Double(speed))
            } else {
                currentLinearPeriod = min(targetLinearPeriod, currentLinearPeriod + Double(speed))
            }
            guard let nextStep = playbackStep(
                linearPeriod: currentLinearPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                break
            }
            currentPlaybackStep = nextStep
            let reachedTarget = abs(currentLinearPeriod - targetLinearPeriod) <= 0.000000001
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: reachedTarget
            ))
            if reachedTarget {
                currentLinearPeriod = targetLinearPeriod
                currentPlaybackStep = targetPlaybackStep
                break
            }
        }
        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return tonePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            commandSource: commandSource,
            rawVolumeColumn: volumeColumn?.rawValue,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            sameCellNote: sameCellNote,
            noteTriggerEventCreated: false,
            voiceReplacement: false,
            samplePositionReset: false,
            instrumentStateUpdated: instrumentStateUpdated,
            instrumentIndexBefore: instrumentStateBefore?.activeInstrumentIndex,
            instrumentIndexAfter: instrumentStateAfter?.activeInstrumentIndex,
            sampleSelectedBefore: sampleSelectedBefore,
            sampleSelectedAfter: sampleSelectedAfter,
            instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
            envelopeReset: false,
            envelopeResetModeled: false,
            channelVolumeBefore: channelVolumeBefore,
            channelVolumeAfter: channelVolumeAfter,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            noteTargetBefore: noteTargetBefore,
            noteTargetAfter: channelState.tonePortamentoTargetNote,
            audibleTransientExpected: instrumentDefaultVolumeApplied &&
                ((gainBefore ?? 0) < (gainAfter ?? 0)),
            cMixerReceivesNewVoice: false,
            cMixerReceivesOnlyStateUpdates: sameCellNote,
            targetExistsBefore: targetExistsBefore,
            targetExistsAfter: targetExistsAfter,
            frequencyTableStatus: .linearApplied,
            targetNote: channelState.tonePortamentoTargetNote,
            targetLinearPeriod: targetLinearPeriod,
            targetAmigaPeriod: nil,
            targetPlaybackStep: targetPlaybackStep,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentAmigaPeriodBefore: currentAmigaPeriodBefore,
            currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            portamentoSpeed: speed,
            stepUpdates: stepUpdates,
            policy: commandSource == .volumeColumn
                ? "volume_column_tone_portamento_reuses_3xx_target_and_sample_step_path_first_pass"
                : cell.effectType == 0x05
                    ? "5xy_reuses_existing_3xx_tone_portamento_target_and_speed_plus_axy_volume_slide"
                    : "linear_period_units_per_tick_row_level_first_pass"
        )
    }

    static func tonePortamentoDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        commandSource: PlaybackSongSyntheticTonePortamentoCommandSource = .effectColumn,
        rawVolumeColumn: UInt8? = nil,
        status: PlaybackSongSyntheticTonePortamentoDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        sameCellNote: Bool = false,
        noteTriggerEventCreated: Bool = false,
        voiceReplacement: Bool = false,
        samplePositionReset: Bool = false,
        instrumentStateUpdated: Bool = false,
        instrumentIndexBefore: Int? = nil,
        instrumentIndexAfter: Int? = nil,
        sampleSelectedBefore: Int? = nil,
        sampleSelectedAfter: Int? = nil,
        instrumentDefaultVolumeApplied: Bool = false,
        envelopeReset: Bool = false,
        envelopeResetModeled: Bool = false,
        channelVolumeBefore: Int? = nil,
        channelVolumeAfter: Int? = nil,
        gainBefore: Float? = nil,
        gainAfter: Float? = nil,
        noteTargetBefore: UInt8? = nil,
        noteTargetAfter: UInt8? = nil,
        audibleTransientExpected: Bool = false,
        cMixerReceivesNewVoice: Bool = false,
        cMixerReceivesOnlyStateUpdates: Bool = false,
        targetExistsBefore: Bool,
        targetExistsAfter: Bool,
        frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus = .linearApplied,
        targetNote: UInt8?,
        targetLinearPeriod: Double?,
        targetAmigaPeriod: Double? = nil,
        targetPlaybackStep: Double?,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentAmigaPeriodBefore: Double? = nil,
        currentAmigaPeriodAfter: Double? = nil,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        portamentoSpeed: Int,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        policy: String
    ) -> PlaybackSongSyntheticTonePortamentoDiagnostic {
        let applied = status == .applied
        return PlaybackSongSyntheticTonePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            commandSource: commandSource,
            rawVolumeColumn: rawVolumeColumn,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .unsupportedFrequencyTable,
            ignoredAsNoOp: !applied && status != .unsupportedFrequencyTable,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            sameCellNote: sameCellNote,
            noteTriggerEventCreated: noteTriggerEventCreated,
            voiceReplacement: voiceReplacement,
            samplePositionReset: samplePositionReset,
            instrumentStateUpdated: instrumentStateUpdated,
            instrumentIndexBefore: instrumentIndexBefore,
            instrumentIndexAfter: instrumentIndexAfter,
            sampleSelectedBefore: sampleSelectedBefore,
            sampleSelectedAfter: sampleSelectedAfter,
            instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
            envelopeReset: envelopeReset,
            envelopeResetModeled: envelopeResetModeled,
            channelVolumeBefore: channelVolumeBefore,
            channelVolumeAfter: channelVolumeAfter,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            noteTargetBefore: noteTargetBefore,
            noteTargetAfter: noteTargetAfter,
            audibleTransientExpected: audibleTransientExpected,
            cMixerReceivesNewVoice: cMixerReceivesNewVoice,
            cMixerReceivesOnlyStateUpdates: cMixerReceivesOnlyStateUpdates,
            targetExistsBefore: targetExistsBefore,
            targetExistsAfter: targetExistsAfter,
            frequencyTableStatus: frequencyTableStatus,
            targetNote: targetNote,
            targetLinearPeriod: targetLinearPeriod,
            targetAmigaPeriod: targetAmigaPeriod,
            targetPlaybackStep: targetPlaybackStep,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentAmigaPeriodBefore: currentAmigaPeriodBefore,
            currentAmigaPeriodAfter: currentAmigaPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            portamentoSpeed: portamentoSpeed,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

}
