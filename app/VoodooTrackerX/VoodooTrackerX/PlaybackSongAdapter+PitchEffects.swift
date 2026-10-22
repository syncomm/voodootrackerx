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
            // A complete row is planned here. Project the first nonzero tick's
            // store only when that invocation exists; later stores are identical.
            if timingConfig.speed > 1 {
                let memory = PortamentoSlideMemory(amount: requestedSlideAmount, source: targetMemorySource)
                if direction == .up {
                    channelState.portamentoUpMemory = memory
                } else {
                    channelState.portamentoDownMemory = memory
                }
            }
            memorySource = nil
            effectMemoryReused = false
            effectMemoryMissing = false
        } else if let rememberedMemory {
            slideAmount = rememberedMemory.amount
            memorySource = rememberedMemory.source
            effectMemoryReused = true
            effectMemoryMissing = false
        } else if !usesLinearFrequencyTable, channelState.activeUsesLinearFrequencyTable == false,
                  direction == .up, let period = currentAmigaPeriodBefore, period.isFinite, period > 0,
                  Int16(bitPattern: UInt16(truncatingIfNeeded: Int(period / 4))) < 1 {
            // Cold 100 still executes the owned signed clamp on a nonzero tick;
            // execution does not establish directional memory provenance.
            slideAmount = 0
            memorySource = nil
            effectMemoryReused = false
            effectMemoryMissing = true
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

        guard hasActiveVoice || channelState.semanticInstrumentIndex != nil else {
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
           var currentAmigaPeriod = channelState.activeAmigaPeriod,
           var currentPlaybackStep = channelState.activePlaybackStep,
           let baseSampleRate = channelState.activeSampleBaseSampleRate {
            var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
            var clamped = false
            let rowSpeed = max(1, timingConfig.speed)
            let slideUnits = Double(slideAmount) * xmAmigaPortamentoUnitsPerParam * (direction == .up ? -1.0 : 1)
            for tick in 1..<rowSpeed {
                let beforePeriod = currentAmigaPeriod
                let beforeStep = currentPlaybackStep
                let rawAfter = currentAmigaPeriod + slideUnits
                let afterPeriod = pitchSlidePeriod(currentAmigaPeriod, nativeDelta: Int(slideUnits / 4),
                    linear: false, upward: direction == .up)
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
                        activeVoiceFound: hasActiveVoice,
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
                        policy: direction == .up ? "amiga_portamento_up_pitch_out_of_range" : "amiga_portamento_down_pitch_out_of_range"
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
                if didClamp && direction == .up {
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
                activeVoiceFound: hasActiveVoice,
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
                policy: rowSpeed == 1 ? "regular_portamento_no_nonzero_ticks_no_memory_admission" : effectMemoryReused
                    ? (direction == .up ? "amiga_zero_param_reuses_prior_1xx_portamento_up_memory" : "amiga_zero_param_reuses_prior_2xx_portamento_down_memory")
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
                activeVoiceFound: hasActiveVoice,
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
                ? currentLinearPeriod - Double(slideAmount) * xmLinearPortamentoUnitsPerParam
                : currentLinearPeriod + Double(slideAmount) * xmLinearPortamentoUnitsPerParam
            let afterPeriod = pitchSlidePeriod(currentLinearPeriod,
                nativeDelta: Int(rawAfter - currentLinearPeriod), linear: true)
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
                    activeVoiceFound: hasActiveVoice,
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
            if didClamp && direction == .up {
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
            activeVoiceFound: hasActiveVoice,
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
            policy: rowSpeed == 1 ? "regular_portamento_no_nonzero_ticks_no_memory_admission" : effectMemoryReused
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
        let effectMemoryDeferred = (effectMemoryMissing && !applied) || status == .zeroParamEffectMemoryDeferred
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

    /// Publishes the incoming row after its same-source outgoing restoration.
    static func appendArpeggio(_ command: PlaybackSongSyntheticArpeggioDiagnostic, to context: inout AdapterRowContext) {
        subsumeArpeggioExit(updates: command.stepUpdates, eventIndex: command.activeEventIndex,
            syntheticRow: command.syntheticRow, context: &context)
        context.arpeggioEffects.append(command)
    }

    static func appendFinePitch(_ command: PlaybackSongSyntheticFinePortamentoUpDiagnostic, to context: inout AdapterRowContext) {
        var command = command
        command.execution.coalescedVibratoExit = coalesceVibratoExit(updates: command.stepUpdates,
            eventIndex: command.activeEventIndex, syntheticRow: command.syntheticRow, context: &context)
        subsumeArpeggioExit(updates: command.stepUpdates, eventIndex: command.activeEventIndex,
            syntheticRow: command.syntheticRow, context: &context)
        context.finePortamentoUpEffects.append(command)
    }

    static func appendFinePitch(_ command: PlaybackSongSyntheticFinePortamentoDownDiagnostic, to context: inout AdapterRowContext) {
        var command = command
        command.execution.coalescedVibratoExit = coalesceVibratoExit(updates: command.stepUpdates,
            eventIndex: command.activeEventIndex, syntheticRow: command.syntheticRow, context: &context)
        subsumeArpeggioExit(updates: command.stepUpdates, eventIndex: command.activeEventIndex,
            syntheticRow: command.syntheticRow, context: &context)
        context.finePortamentoDownEffects.append(command)
    }

    static func appendFinePitch(_ command: PlaybackSongSyntheticExtraFinePortamentoDiagnostic, to context: inout AdapterRowContext) {
        var command = command
        command.execution.coalescedVibratoExit = coalesceVibratoExit(updates: command.stepUpdates,
            eventIndex: command.activeEventIndex, syntheticRow: command.syntheticRow, context: &context)
        subsumeArpeggioExit(updates: command.stepUpdates, eventIndex: command.activeEventIndex,
            syntheticRow: command.syntheticRow, context: &context)
        context.extraFinePortamentoEffects.append(command)
    }

    /// Row entry restores outgoing arpeggio before the incoming tick-zero writer.
    /// Keep its raw evidence, but deliver only the later writer to every consumer;
    /// a previous row's synthetic end tick must never win a same-frame tie.
    private static func subsumeArpeggioExit(updates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        eventIndex: Int?, syntheticRow: Int, context: inout AdapterRowContext) {
        guard let update = updates.first, update.syntheticTick == 0, let eventIndex else { return }
        for index in context.arpeggioEffects.indices.reversed() {
            let command = context.arpeggioEffects[index]
            if command.syntheticRow < syntheticRow - 1 { break }
            guard command.syntheticRow == syntheticRow - 1, command.activeEventIndex == eventIndex,
                  let exit = command.stepUpdates.last, exit.syntheticTick == command.rowSpeed,
                  exit.reachedTarget, exit.scheduledFrame == update.scheduledFrame else { continue }
            context.arpeggioEffects[index].subsumedRowExit = context.arpeggioEffects[index].stepUpdates.removeLast()
            return
        }
    }

    /// A later fine writer subsumes the prior row's same-frame vibrato exit.
    /// Search only the current/preceding row; trigger folds and converged cold
    /// commands keep the existing exit publication and source-start ordering.
    private static func coalesceVibratoExit(updates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        eventIndex: Int?, syntheticRow: Int, context: inout AdapterRowContext) -> Bool {
        guard let update = updates.first, let eventIndex else { return false }
        for index in context.vibratoEffects.indices.reversed() {
            let vibrato = context.vibratoEffects[index]
            if vibrato.syntheticRow < syntheticRow - 1 { break }
            guard vibrato.syntheticRow == syntheticRow - 1,
                  vibrato.activeEventIndex == eventIndex, let exit = vibrato.stepUpdates.last,
                  exit.syntheticTick == vibrato.rowSpeed, exit.reachedTarget,
                  exit.scheduledFrame == update.scheduledFrame else { continue }
            context.vibratoEffects[index].stepUpdates.removeLast()
            return true
        }
        return false
    }

    /// Uses the existing canonical period and conversion for each pitch mode.
    /// Legacy fine diagnostic period fields carry these same mode-specific units.
    private static func finePitchPeriod(_ state: ChannelState, linear: Bool) -> Double? {
        linear ? state.activeLinearPeriod : state.activeAmigaPeriod
    }

    private static func finePitchStep(_ period: Double, linear: Bool,
        baseSampleRate: Double, outputSampleRate: Double) -> Double? {
        linear ? playbackStep(linearPeriod: period, baseSampleRate: baseSampleRate, outputSampleRate: outputSampleRate)
            : playbackStep(amigaPeriod: period, baseSampleRate: baseSampleRate, outputSampleRate: outputSampleRate)
    }

    /// Resolves one directional memory independently of pitch mode and source lifetime.
    private static func resolveFinePitch(
        from cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        up: Bool, extraFine: Bool = false, usesLinearFrequencyTable: Bool, sampleRate: Double,
        channelState: inout ChannelState
    ) -> (amount: Int, execution: PlaybackSongSyntheticFinePitchExecution) {
        let raw = Int(cell.effectParam & 15)
        if raw > 0 {
            let memory = FinePitchMemory(amount: raw, source: effectMemorySource(
                source: source, channelIndex: channelIndex, cell: cell))
            if extraFine {
                if up { channelState.extraFinePitchUpMemory = memory }
                else { channelState.extraFinePitchDownMemory = memory }
            } else {
                if up { channelState.finePitchUpMemory = memory }
                else { channelState.finePitchDownMemory = memory }
            }
        }
        // Fine and extra-fine share qualification, never memory storage or units.
        let memory = extraFine
            ? (up ? channelState.extraFinePitchUpMemory : channelState.extraFinePitchDownMemory)
            : (up ? channelState.finePitchUpMemory : channelState.finePitchDownMemory)
        let valid = channelState.activeUsesLinearFrequencyTable == usesLinearFrequencyTable &&
            (channelState.activeEventIndex != nil || channelState.semanticInstrumentIndex != nil) &&
            finePitchPeriod(channelState, linear: usesLinearFrequencyTable).map { $0.isFinite && $0 > 0 } == true &&
            channelState.activePlaybackStep.map { $0.isFinite && $0 > 0 } == true &&
            channelState.activeSampleBaseSampleRate.map { $0.isFinite && $0 > 0 } == true
        var output = finePitchPeriod(channelState, linear: usesLinearFrequencyTable)
        // The held step is authoritative: another writer may have superseded the
        // vibrato cache without changing its phase or memory.
        if let period = usesLinearFrequencyTable ? channelState.vibratoOutputLinearPeriod : channelState.vibratoOutputAmigaPeriod,
           let rate = channelState.activeSampleBaseSampleRate,
           finePitchStep(period, linear: usesLinearFrequencyTable, baseSampleRate: rate, outputSampleRate: sampleRate) == channelState.activePlaybackStep {
            output = period
        }
        return (raw > 0 ? raw : memory?.amount ?? 0, .init(
            memoryValue: memory?.amount, memoryOrigin: memory?.source,
            effectMemoryReused: raw == 0 && memory != nil, cold: raw == 0 && memory == nil,
            usesLinearFrequencyTable: usesLinearFrequencyTable, canonicalPitchValid: valid,
            outputLinearPeriodBefore: output, outputLinearPeriodAfter: output,
            sourceEligible: valid && channelState.activeEventIndex != nil))
    }

    static func handleFinePortamentoUp(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        usesLinearFrequencyTable: Bool,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticFinePortamentoUpDiagnostic {
        let resolved = resolveFinePitch(from: cell, source: source, channelIndex: channelIndex,
            up: true, usesLinearFrequencyTable: usesLinearFrequencyTable, sampleRate: timingConfig.sampleRate,
            channelState: &channelState)
        let amount = resolved.amount
        var execution = resolved.execution
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = finePitchPeriod(channelState, linear: usesLinearFrequencyTable)
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard amount > 0 || execution.canonicalPitchValid else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "cold_fine_pitch_no_meaningful_canonical_state",
                execution: execution
            )
        }

        guard hasActiveVoice || channelState.semanticInstrumentIndex != nil else {
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
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented",
                execution: execution
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == usesLinearFrequencyTable,
              let currentLinearPeriod = finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass",
                execution: execution
            )
        }

        let rawAfter = currentLinearPeriod - Double(amount) * (usesLinearFrequencyTable ? xmLinearPortamentoUnitsPerParam : xmAmigaPortamentoUnitsPerParam)
        let afterPeriod = amount == 0 && usesLinearFrequencyTable ? currentLinearPeriod : pitchSlidePeriod(currentLinearPeriod,
            nativeDelta: Int((rawAfter - currentLinearPeriod) / (usesLinearFrequencyTable ? 1 : 4)),
            linear: usesLinearFrequencyTable, upward: !usesLinearFrequencyTable)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = finePitchStep(
            afterPeriod, linear: usesLinearFrequencyTable,
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
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_up_pitch_out_of_range",
                execution: execution
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            amigaPeriodBefore: usesLinearFrequencyTable ? nil : currentLinearPeriod,
            amigaPeriodAfter: usesLinearFrequencyTable ? nil : afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        if usesLinearFrequencyTable { channelState.activeLinearPeriod = afterPeriod }
        else { channelState.activeAmigaPeriod = afterPeriod }
        channelState.activePlaybackStep = nextStep
        if usesLinearFrequencyTable { channelState.vibratoOutputLinearPeriod = nil }
        else { channelState.vibratoOutputAmigaPeriod = nil }
        execution.outputLinearPeriodAfter = afterPeriod
        execution.publicationRequested = true
        execution.publicationSuppressionReason = nextStep == currentPlaybackStep ? "held_pitch_converged" : nil

        return finePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: hasActiveVoice,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: hasActiveVoice && nextStep != currentPlaybackStep ? [update] : [],
            clamped: clamped,
            policy: (usesLinearFrequencyTable ? "row_start_fine_linear_period_up_first_pass" : "row_start_fine_amiga_period_up_first_pass"),
            execution: execution
        )
    }

    static func finePortamentoUpAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        usesLinearFrequencyTable: Bool,
        channelState: inout ChannelState,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticFinePortamentoUpDiagnostic) {
        let resolved = resolveFinePitch(from: cell, source: source, channelIndex: channelIndex,
            up: true, usesLinearFrequencyTable: usesLinearFrequencyTable, sampleRate: timingConfig.sampleRate,
            channelState: &channelState)
        let amount = resolved.amount
        var execution = resolved.execution
        let currentLinearPeriodBefore = usesLinearFrequencyTable ? basePitchMapping.linearPeriod : basePitchMapping.amigaPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        execution.outputLinearPeriodBefore = currentLinearPeriodBefore
        execution.outputLinearPeriodAfter = currentLinearPeriodBefore

        guard basePitchMapping.applied,
              let linearPeriod = currentLinearPeriodBefore,
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
                    : "fine_portamento_up_pitch_out_of_range",
                execution: execution
            ))
        }

        let rawAfter = linearPeriod - Double(amount) * (usesLinearFrequencyTable ? xmLinearPortamentoUnitsPerParam : xmAmigaPortamentoUnitsPerParam)
        let afterPeriod = amount == 0 && usesLinearFrequencyTable ? linearPeriod : pitchSlidePeriod(linearPeriod,
            nativeDelta: Int((rawAfter - linearPeriod) / (usesLinearFrequencyTable ? 1 : 4)),
            linear: usesLinearFrequencyTable, upward: !usesLinearFrequencyTable)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = finePitchStep(
            afterPeriod, linear: usesLinearFrequencyTable,
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
                policy: "fine_portamento_up_pitch_out_of_range",
                execution: execution
            ))
        }

        execution.canonicalPitchValid = true
        execution.outputLinearPeriodAfter = afterPeriod
        execution.publicationRequested = true
        execution.sourceEligible = true
        execution.publicationSuppressionReason = "folded_into_trigger"

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: usesLinearFrequencyTable ? afterPeriod : nil,
            linearFrequency: usesLinearFrequencyTable ? nextStep * basePitchMapping.outputSampleRate : nil,
            amigaPeriod: usesLinearFrequencyTable ? nil : afterPeriod,
            amigaFrequency: usesLinearFrequencyTable ? nil : nextStep * basePitchMapping.outputSampleRate,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: usesLinearFrequencyTable,
            amigaFrequencyApplied: !usesLinearFrequencyTable,
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
            policy: (usesLinearFrequencyTable ? "same_cell_note_initial_playback_step_fine_linear_period_up_first_pass" : "same_cell_note_initial_playback_step_fine_amiga_period_up_first_pass"),
            execution: execution
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
        policy: String,
        execution: PlaybackSongSyntheticFinePitchExecution = .init()
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
            fineAmountNibble: Int(cell.effectParam & 15),
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
            policy: policy,
            execution: execution
        )
    }

    static func handleFinePortamentoDown(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        usesLinearFrequencyTable: Bool,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticFinePortamentoDownDiagnostic {
        let resolved = resolveFinePitch(from: cell, source: source, channelIndex: channelIndex,
            up: false, usesLinearFrequencyTable: usesLinearFrequencyTable, sampleRate: timingConfig.sampleRate,
            channelState: &channelState)
        let amount = resolved.amount
        var execution = resolved.execution
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = finePitchPeriod(channelState, linear: usesLinearFrequencyTable)
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard amount > 0 || execution.canonicalPitchValid else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "cold_fine_pitch_no_meaningful_canonical_state",
                execution: execution
            )
        }

        guard hasActiveVoice || channelState.semanticInstrumentIndex != nil else {
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
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented",
                execution: execution
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == usesLinearFrequencyTable,
              let currentLinearPeriod = finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass",
                execution: execution
            )
        }

        let rawAfter = currentLinearPeriod + Double(amount) * (usesLinearFrequencyTable ? xmLinearPortamentoUnitsPerParam : xmAmigaPortamentoUnitsPerParam)
        let afterPeriod = amount == 0 ? currentLinearPeriod : pitchSlidePeriod(currentLinearPeriod,
            nativeDelta: Int((rawAfter - currentLinearPeriod) / (usesLinearFrequencyTable ? 1 : 4)), linear: usesLinearFrequencyTable)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = finePitchStep(
            afterPeriod, linear: usesLinearFrequencyTable,
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
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_down_pitch_out_of_range",
                execution: execution
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            amigaPeriodBefore: usesLinearFrequencyTable ? nil : currentLinearPeriod,
            amigaPeriodAfter: usesLinearFrequencyTable ? nil : afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        if usesLinearFrequencyTable { channelState.activeLinearPeriod = afterPeriod }
        else { channelState.activeAmigaPeriod = afterPeriod }
        channelState.activePlaybackStep = nextStep
        if usesLinearFrequencyTable { channelState.vibratoOutputLinearPeriod = nil }
        else { channelState.vibratoOutputAmigaPeriod = nil }
        execution.outputLinearPeriodAfter = afterPeriod
        execution.publicationRequested = true
        execution.publicationSuppressionReason = nextStep == currentPlaybackStep ? "held_pitch_converged" : nil

        return finePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: hasActiveVoice,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: hasActiveVoice && nextStep != currentPlaybackStep ? [update] : [],
            clamped: clamped,
            policy: (usesLinearFrequencyTable ? "row_start_fine_linear_period_down_first_pass" : "row_start_fine_amiga_period_down_first_pass"),
            execution: execution
        )
    }

    static func finePortamentoDownAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        usesLinearFrequencyTable: Bool,
        channelState: inout ChannelState,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticFinePortamentoDownDiagnostic) {
        let resolved = resolveFinePitch(from: cell, source: source, channelIndex: channelIndex,
            up: false, usesLinearFrequencyTable: usesLinearFrequencyTable, sampleRate: timingConfig.sampleRate,
            channelState: &channelState)
        let amount = resolved.amount
        var execution = resolved.execution
        let currentLinearPeriodBefore = usesLinearFrequencyTable ? basePitchMapping.linearPeriod : basePitchMapping.amigaPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        execution.outputLinearPeriodBefore = currentLinearPeriodBefore
        execution.outputLinearPeriodAfter = currentLinearPeriodBefore

        guard basePitchMapping.applied,
              let linearPeriod = currentLinearPeriodBefore,
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
                    : "fine_portamento_down_pitch_out_of_range",
                execution: execution
            ))
        }

        let rawAfter = linearPeriod + Double(amount) * (usesLinearFrequencyTable ? xmLinearPortamentoUnitsPerParam : xmAmigaPortamentoUnitsPerParam)
        let afterPeriod = amount == 0 ? linearPeriod : pitchSlidePeriod(linearPeriod,
            nativeDelta: Int((rawAfter - linearPeriod) / (usesLinearFrequencyTable ? 1 : 4)), linear: usesLinearFrequencyTable)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = finePitchStep(
            afterPeriod, linear: usesLinearFrequencyTable,
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
                policy: "fine_portamento_down_pitch_out_of_range",
                execution: execution
            ))
        }

        execution.canonicalPitchValid = true
        execution.outputLinearPeriodAfter = afterPeriod
        execution.publicationRequested = true
        execution.sourceEligible = true
        execution.publicationSuppressionReason = "folded_into_trigger"

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: usesLinearFrequencyTable ? afterPeriod : nil,
            linearFrequency: usesLinearFrequencyTable ? nextStep * basePitchMapping.outputSampleRate : nil,
            amigaPeriod: usesLinearFrequencyTable ? nil : afterPeriod,
            amigaFrequency: usesLinearFrequencyTable ? nil : nextStep * basePitchMapping.outputSampleRate,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: usesLinearFrequencyTable,
            amigaFrequencyApplied: !usesLinearFrequencyTable,
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
            policy: (usesLinearFrequencyTable ? "same_cell_note_initial_playback_step_fine_linear_period_down_first_pass" : "same_cell_note_initial_playback_step_fine_amiga_period_down_first_pass"),
            execution: execution
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
        policy: String,
        execution: PlaybackSongSyntheticFinePitchExecution = .init()
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
            fineAmountNibble: Int(cell.effectParam & 15),
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
            policy: policy,
            execution: execution
        )
    }

    static func handleExtraFinePortamento(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        usesLinearFrequencyTable: Bool,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticExtraFinePortamentoDiagnostic {
        let subcommand = xxySubcommand(from: cell)
        let direction = xxyDirection(from: cell)
        let resolved = direction == nil
            ? (amount: xxyAmount(from: cell), execution: PlaybackSongSyntheticFinePitchExecution(usesLinearFrequencyTable: usesLinearFrequencyTable))
            : resolveFinePitch(from: cell, source: source, channelIndex: channelIndex,
                up: direction == .up, extraFine: true, usesLinearFrequencyTable: usesLinearFrequencyTable,
                sampleRate: timingConfig.sampleRate, channelState: &channelState)
        let amount = resolved.amount
        var execution = resolved.execution
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = finePitchPeriod(channelState, linear: usesLinearFrequencyTable)
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
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "xxy_unsupported_subcommand_deferred",
                execution: execution
            )
        }

        guard amount > 0 || execution.canonicalPitchValid else {
            return extraFinePortamentoDiagnostic(
                source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                timingConfig: timingConfig, cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: hasActiveVoice, activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand, direction: direction, amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore, currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore, currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame, appliedToInitialPlaybackStep: false, stepUpdates: [], clamped: false,
                policy: "cold_extra_fine_pitch_no_meaningful_canonical_state", execution: execution
            )
        }

        guard hasActiveVoice || channelState.semanticInstrumentIndex != nil else {
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
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented",
                execution: execution
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == usesLinearFrequencyTable,
              let currentLinearPeriod = finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return extraFinePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass",
                execution: execution
            )
        }

        let rawAfter = direction == .up
            ? currentLinearPeriod - Double(amount) * (usesLinearFrequencyTable ? 1 : xmAmigaPeriodLookupScale)
            : currentLinearPeriod + Double(amount) * (usesLinearFrequencyTable ? 1 : xmAmigaPeriodLookupScale)
        let afterPeriod = amount == 0 && (usesLinearFrequencyTable || direction == .down) ? currentLinearPeriod : pitchSlidePeriod(currentLinearPeriod,
            nativeDelta: Int((rawAfter - currentLinearPeriod) / (usesLinearFrequencyTable ? 1 : 4)),
            linear: usesLinearFrequencyTable, upward: !usesLinearFrequencyTable && direction == .up)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = finePitchStep(
            afterPeriod, linear: usesLinearFrequencyTable,
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
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                subcommand: subcommand,
                direction: direction,
                amount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "xxy_extra_fine_portamento_pitch_out_of_range",
                execution: execution
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            amigaPeriodBefore: usesLinearFrequencyTable ? nil : currentLinearPeriod,
            amigaPeriodAfter: usesLinearFrequencyTable ? nil : afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        if usesLinearFrequencyTable { channelState.activeLinearPeriod = afterPeriod }
        else { channelState.activeAmigaPeriod = afterPeriod }
        channelState.activePlaybackStep = nextStep
        if usesLinearFrequencyTable { channelState.vibratoOutputLinearPeriod = nil }
        else { channelState.vibratoOutputAmigaPeriod = nil }
        execution.outputLinearPeriodAfter = afterPeriod
        execution.publicationRequested = true
        execution.publicationSuppressionReason = nextStep == currentPlaybackStep ? "held_pitch_converged" : nil

        return extraFinePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: hasActiveVoice,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            subcommand: subcommand,
            direction: direction,
            amount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: finePitchPeriod(channelState, linear: usesLinearFrequencyTable),
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: hasActiveVoice && nextStep != currentPlaybackStep ? [update] : [],
            clamped: clamped,
            policy: direction == .up
                ? (usesLinearFrequencyTable ? "row_start_x1x_extra_fine_linear_period_up_first_pass" : "row_start_x1x_extra_fine_amiga_period_up_first_pass")
                : (usesLinearFrequencyTable ? "row_start_x2x_extra_fine_linear_period_down_first_pass" : "row_start_x2x_extra_fine_amiga_period_down_first_pass"),
            execution: execution
        )
    }

    static func extraFinePortamentoAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        usesLinearFrequencyTable: Bool,
        channelState: inout ChannelState,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticExtraFinePortamentoDiagnostic) {
        let subcommand = xxySubcommand(from: cell)
        let direction = xxyDirection(from: cell)
        let resolved = direction == nil
            ? (amount: xxyAmount(from: cell), execution: PlaybackSongSyntheticFinePitchExecution(usesLinearFrequencyTable: usesLinearFrequencyTable))
            : resolveFinePitch(from: cell, source: source, channelIndex: channelIndex,
                up: direction == .up, extraFine: true, usesLinearFrequencyTable: usesLinearFrequencyTable,
                sampleRate: timingConfig.sampleRate, channelState: &channelState)
        let amount = resolved.amount
        var execution = resolved.execution
        let currentLinearPeriodBefore = usesLinearFrequencyTable ? basePitchMapping.linearPeriod : basePitchMapping.amigaPeriod
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
                policy: "xxy_unsupported_subcommand_deferred",
                execution: execution
            ))
        }

        execution.outputLinearPeriodBefore = currentLinearPeriodBefore
        guard basePitchMapping.applied,
              let linearPeriod = currentLinearPeriodBefore,
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
                    : "xxy_extra_fine_portamento_pitch_out_of_range",
                execution: execution
            ))
        }

        let rawAfter = direction == .up
            ? linearPeriod - Double(amount) * (usesLinearFrequencyTable ? 1 : xmAmigaPeriodLookupScale)
            : linearPeriod + Double(amount) * (usesLinearFrequencyTable ? 1 : xmAmigaPeriodLookupScale)
        let afterPeriod = amount == 0 && (usesLinearFrequencyTable || direction == .down) ? linearPeriod : pitchSlidePeriod(linearPeriod,
            nativeDelta: Int((rawAfter - linearPeriod) / (usesLinearFrequencyTable ? 1 : 4)),
            linear: usesLinearFrequencyTable, upward: !usesLinearFrequencyTable && direction == .up)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = finePitchStep(
            afterPeriod, linear: usesLinearFrequencyTable,
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
                policy: "xxy_extra_fine_portamento_pitch_out_of_range",
                execution: execution
            ))
        }

        execution.canonicalPitchValid = true
        execution.outputLinearPeriodAfter = afterPeriod
        execution.publicationRequested = true
        execution.sourceEligible = true
        execution.publicationSuppressionReason = "folded_into_trigger"

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: usesLinearFrequencyTable ? afterPeriod : nil,
            linearFrequency: usesLinearFrequencyTable ? nextStep * basePitchMapping.outputSampleRate : nil,
            amigaPeriod: usesLinearFrequencyTable ? nil : afterPeriod,
            amigaFrequency: usesLinearFrequencyTable ? nil : nextStep * basePitchMapping.outputSampleRate,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: usesLinearFrequencyTable,
            amigaFrequencyApplied: !usesLinearFrequencyTable,
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
                ? (usesLinearFrequencyTable ? "same_cell_note_initial_playback_step_x1x_extra_fine_linear_period_up_first_pass" : "same_cell_note_initial_playback_step_x1x_extra_fine_amiga_period_up_first_pass")
                : (usesLinearFrequencyTable ? "same_cell_note_initial_playback_step_x2x_extra_fine_linear_period_down_first_pass" : "same_cell_note_initial_playback_step_x2x_extra_fine_amiga_period_down_first_pass"),
            execution: execution
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
        policy: String,
        execution: PlaybackSongSyntheticFinePitchExecution = .init()
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
            amountNibble: xxyAmount(from: cell),
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
            policy: policy,
            execution: execution
        )
    }

    /// Selects 0xy's remaining-tick phase without owning pitch conversion or source state.
    static func arpeggioSemitoneOffset(effectiveSpeed: Int, tick: Int, x: Int, y: Int) -> Int {
        guard tick > 0, tick < effectiveSpeed else { return 0 }
        switch (effectiveSpeed - tick) % 3 {
        case 1: return x
        case 2: return y
        default: return 0
        }
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
        let currentAmigaPeriodBefore = channelState.activeAmigaPeriod
        let isLinear = channelState.activeUsesLinearFrequencyTable == true
        let currentPlaybackStepBefore = channelState.activePlaybackStep

        guard hasActiveVoice || channelState.semanticInstrumentIndex != nil else {
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
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard let basePeriod = isLinear ? channelState.activeLinearPeriod : channelState.activeAmigaPeriod,
              isLinear || (channelState.activeUsesLinearFrequencyTable == false &&
                  channelState.carriedNote > 0 && channelState.activeSampleRelativeNote != nil &&
                  channelState.activeSampleFinetune != nil),
              let incomingPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate,
              let basePlaybackStep = finePitchStep(basePeriod, linear: isLinear,
                  baseSampleRate: baseSampleRate, outputSampleRate: timingConfig.sampleRate) else {
            return arpeggioDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                xSemitoneOffset: xSemitoneOffset,
                ySemitoneOffset: ySemitoneOffset,
                currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "pitch_owner_or_sample_tuning_unavailable"
            )
        }

        // Pure column Bx leaves its output held at row entry. Effect-column 4/6
        // exits already restore/clear this cache; an earlier arpeggio exit has
        // likewise restored canonical pitch. Never invert a quantized step.
        let heldPeriod = isLinear ? channelState.vibratoOutputLinearPeriod : channelState.vibratoOutputAmigaPeriod
        let incomingPeriod = heldPeriod.flatMap { period in
            finePitchStep(period, linear: isLinear, baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate) == incomingPlaybackStep ? period : nil
        } ?? basePeriod
        var currentPeriod = incomingPeriod
        var currentPlaybackStep = incomingPlaybackStep
        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        let firstTick = includeTickZeroUpdate ? 0 : 1
        for tick in firstTick..<rowSpeed {
            let beforePeriod = currentPeriod
            let beforeStep = currentPlaybackStep
            let semitoneOffset = arpeggioSemitoneOffset(
                effectiveSpeed: rowSpeed, tick: tick, x: xSemitoneOffset, y: ySemitoneOffset
            )
            // G25's base phase holds canonical pitch. X/Y phases project even
            // a zero nibble; projection neither admits a note nor mutates base state.
            let modulatedPeriod: Double? = tick == 0 ? incomingPeriod : (rowSpeed - tick) % 3 == 0 ? basePeriod
                : arpeggioPeriod(basePeriod, finetune: channelState.activeSampleFinetune ?? 0,
                    offset: semitoneOffset, linear: isLinear)
            guard let modulatedPeriod,
                  let nextStep = isLinear
                    ? playbackStep(linearPeriod: modulatedPeriod, baseSampleRate: baseSampleRate,
                        outputSampleRate: timingConfig.sampleRate)
                    : playbackStep(amigaPeriod: modulatedPeriod, baseSampleRate: baseSampleRate,
                        outputSampleRate: timingConfig.sampleRate) else {
                return arpeggioDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: hasActiveVoice,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    xSemitoneOffset: xSemitoneOffset,
                    ySemitoneOffset: ySemitoneOffset,
                    currentAmigaPeriodBefore: currentAmigaPeriodBefore,
                    currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    policy: "arpeggio_pitch_out_of_range"
                )
            }
            currentPeriod = modulatedPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: isLinear ? beforePeriod : 0,
                linearPeriodAfter: isLinear ? currentPeriod : 0,
                amigaPeriodBefore: isLinear ? nil : beforePeriod,
                amigaPeriodAfter: isLinear ? nil : currentPeriod,
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
                linearPeriodBefore: isLinear ? currentPeriod : 0,
                linearPeriodAfter: isLinear ? basePeriod : 0,
                amigaPeriodBefore: isLinear ? nil : currentPeriod,
                amigaPeriodAfter: isLinear ? nil : basePeriod,
                playbackStepBefore: currentPlaybackStep,
                playbackStepAfter: basePlaybackStep,
                reachedTarget: true
            ))
            currentPeriod = basePeriod
            currentPlaybackStep = basePlaybackStep
        }

        // The row effect owns output only; canonical note/slide pitch survives.
        if isLinear { channelState.activeLinearPeriod = basePeriod; channelState.vibratoOutputLinearPeriod = nil }
        else { channelState.activeAmigaPeriod = basePeriod; channelState.vibratoOutputAmigaPeriod = nil }
        channelState.activePlaybackStep = currentPlaybackStep

        return arpeggioDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: hasActiveVoice,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            xSemitoneOffset: xSemitoneOffset,
            ySemitoneOffset: ySemitoneOffset,
            currentAmigaPeriodBefore: currentAmigaPeriodBefore,
            currentAmigaPeriodAfter: channelState.activeAmigaPeriod,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            policy: isLinear ? "linear_0xy_remaining_tick_order_no_effect_memory"
                : "amiga_0xy_quantized_note_remaining_tick_order_no_effect_memory"
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
        currentAmigaPeriodBefore: Double? = nil,
        currentAmigaPeriodAfter: Double? = nil,
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
            currentAmigaPeriodBefore: currentAmigaPeriodBefore,
            currentAmigaPeriodAfter: currentAmigaPeriodAfter,
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

    /// Executes one ordinary EDx/Bx span with its current semantic/source owner.
    static func appendOrdinaryDelayedVibrato(cell: PlaybackCell, source: PlaybackPosition,
        channelIndex: Int, syntheticRow: Int, ticks: Range<Int>, timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan, state: inout ChannelState, context: inout AdapterRowContext) {
        var diagnostic = handleVibrato(from: cell, source: source, channelIndex: channelIndex,
            syntheticRow: syntheticRow, timingConfig: timingConfig, timingPlan: timingPlan,
            channelState: &state, executionTicks: ticks, executeSemanticPitch: true)
        diagnostic.ordinaryDelayedExecution = true
        if diagnostic.activeEventIndex == nil {
            diagnostic.inactiveSourceStepUpdates = diagnostic.stepUpdates
            diagnostic.stepUpdates = []
        }
        context.ordinaryDelayedVibratoIndices.append(context.vibratoEffects.count)
        context.vibratoEffects.append(diagnostic)
    }

    /// The real trigger owns this mixed frame; retain the raw calculation as evidence.
    static func supersedeDelayedVibratoBirth(_ index: Int?, tick: Int, context: inout AdapterRowContext) {
        guard let index, context.vibratoEffects[index].stepUpdates.last?.syntheticTick == tick else { return }
        context.vibratoEffects[index].supersededDelayedBirth = context.vibratoEffects[index].stepUpdates.removeLast()
    }

    static func handleVibrato(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        restoreAtRowEnd: Bool = false,
        channelState: inout ChannelState,
        executionTicks: Range<Int>? = nil,
        executeSemanticPitch: Bool = false
    ) -> PlaybackSongSyntheticVibratoDiagnostic {
        let combined = isVibratoVolumeSlideEffect(cell)
        let effectVibrato = isVibratoEffect(cell) || combined
        let columnVibrato = (0xB0...0xBF).contains(cell.volumeColumn)
        let columnDepth = Int(cell.volumeColumn & 15)
        // Leaving Bx alone holds output; only the existing effect-column family restores it.
        let restoreAtRowEnd = restoreAtRowEnd && effectVibrato
        let targetSource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let writesSpeed = isVibratoEffect(cell) && cell.effectParam >> 4 > 0 && timingConfig.speed > 1
        let writesDepth = isVibratoEffect(cell) && cell.effectParam & 15 > 0 && timingConfig.speed > 1
        let columnWritesDepth = columnVibrato && columnDepth > 0 && timingConfig.speed > 1
        let speedMemorySource = writesSpeed ? nil : channelState.vibratoSpeedMemorySource
        let depthMemorySource = writesDepth || columnWritesDepth ? nil : channelState.vibratoDepthMemorySource
        let control = channelState.vibratoControl ?? VibratoControlState(
            controlValue: 0, waveform: .sine, retriggerSuppressed: false, source: nil
        )
        let phaseBefore = channelState.vibratoPhase
        let linear = channelState.activeUsesLinearFrequencyTable == true
        let basePeriod = linear ? channelState.activeLinearPeriod : channelState.activeAmigaPeriod
        let outputPeriodBefore = (linear ? channelState.vibratoOutputLinearPeriod : channelState.vibratoOutputAmigaPeriod) ?? basePeriod
        let stepBefore = channelState.activePlaybackStep
        let semanticPitch = executeSemanticPitch && basePeriod != nil && stepBefore != nil && channelState.activeSampleBaseSampleRate != nil
        var updates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        var status: PlaybackSongSyntheticVibratoDiagnostic.Status = .applied
        var policy = combined ? "6xy_ft2_vibrato_plus_tick_volume_slide" : "ft2_integer_vibrato_linear_period"
        if !linear && !combined { policy = "ft2_integer_vibrato_wrapped_amiga_period" }
        if columnVibrato { policy = effectVibrato ? "bx_then_effect_column_shared_vibrato" : "bx_shared_ft2_vibrato" }

        if channelState.activeEventIndex == nil {
            status = .noActiveVoice
            policy = "no_active_voice_no_playback_invented"
        } else if channelState.activeUsesLinearFrequencyTable == nil || basePeriod == nil ||
                    stepBefore == nil || channelState.activeSampleBaseSampleRate == nil {
            status = .unsupportedFrequencyTable
            policy = "missing_active_pitch_state"
        }
        func step(for period: Double) -> Double? {
            guard let rate = channelState.activeSampleBaseSampleRate else { return nil }
            return linear ? playbackStep(linearPeriod: period, baseSampleRate: rate, outputSampleRate: timingConfig.sampleRate)
                : playbackStep(amigaPeriod: period, baseSampleRate: rate, outputSampleRate: timingConfig.sampleRate)
        }
        var currentPeriod = outputPeriodBefore ?? basePeriod
        var currentStep = stepBefore
        let executionCount = (columnVibrato ? 1 : 0) + (effectVibrato ? 1 : 0)
        for tick in executionTicks ?? (1..<max(1, timingConfig.speed)) {
            // Each tick runs Bx first. Effect nibbles then overwrite shared memory
            // before a second execution, including the first tick's old Bx speed.
            for writer in 0..<executionCount {
                if columnVibrato && writer == 0 {
                    if columnWritesDepth {
                        channelState.vibratoDepth = columnDepth
                        channelState.vibratoDepthMemorySource = targetSource
                    }
                } else {
                    if writesSpeed {
                        channelState.vibratoSpeed = Int(cell.effectParam >> 4)
                        channelState.vibratoSpeedMemorySource = targetSource
                    }
                    if writesDepth {
                        channelState.vibratoDepth = Int(cell.effectParam & 15)
                        channelState.vibratoDepthMemorySource = targetSource
                    }
                }
                guard status == .applied || status == .noActiveVoice else { continue }
                let modulation = vibratoTick(phase: channelState.vibratoPhase, speed: channelState.vibratoSpeed,
                    depth: channelState.vibratoDepth, control: control.controlValue)
                if status == .noActiveVoice && !semanticPitch {
                    channelState.vibratoPhase = modulation.phaseAfter
                    continue
                }
                guard let basePeriod, let beforePeriod = currentPeriod, let beforeStep = currentStep else { continue }
                // FT2 and VTX Linear periods have identical sign and units (C-4=4608).
                let modulatedPeriod = linear
                    ? clampedLinearPeriod(basePeriod + Double(modulation.signedReferenceDelta))
                    : vibratoAmigaPeriod(basePeriod: basePeriod, signedReferenceDelta: modulation.signedReferenceDelta)
                guard let step = step(for: modulatedPeriod) else {
                    status = .outOfRange
                    policy = "vibrato_pitch_out_of_range"
                    break
                }
                updates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                    syntheticTick: tick, scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                    linearPeriodBefore: linear ? beforePeriod : 0, linearPeriodAfter: linear ? modulatedPeriod : 0,
                    amigaPeriodBefore: linear ? nil : beforePeriod, amigaPeriodAfter: linear ? nil : modulatedPeriod,
                    playbackStepBefore: beforeStep, playbackStepAfter: step, reachedTarget: false,
                    vibrato: modulation
                ))
                channelState.vibratoPhase = modulation.phaseAfter
                currentPeriod = modulatedPeriod
                currentStep = step
            }
        }
        if status == .applied || (status == .noActiveVoice && semanticPitch),
           let basePeriod, let period = currentPeriod, let previousStep = currentStep {
            // getNewNote restores only on leaving 4/6, not between consecutive rows.
            // Lookahead uses the traversed next row, so jumps and loops share this rule.
            if restoreAtRowEnd, period != basePeriod,
               let step = step(for: basePeriod) {
                updates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                    syntheticTick: timingConfig.speed,
                    scheduledFrame: timingPlan.frameFor(row: syntheticRow + 1, tick: 0),
                    linearPeriodBefore: linear ? period : 0, linearPeriodAfter: linear ? basePeriod : 0,
                    amigaPeriodBefore: linear ? nil : period, amigaPeriodAfter: linear ? nil : basePeriod,
                    playbackStepBefore: previousStep, playbackStepAfter: step, reachedTarget: true
                ))
                currentPeriod = basePeriod
                currentStep = step
            }
            // Modulation never accumulates into the note/portamento base period.
            if linear { channelState.vibratoOutputLinearPeriod = restoreAtRowEnd ? nil : currentPeriod }
            else { channelState.vibratoOutputAmigaPeriod = restoreAtRowEnd ? nil : currentPeriod }
            channelState.activePlaybackStep = currentStep
        }
        return vibratoDiagnostic(
            source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
            timingConfig: timingConfig, cell: cell, status: status,
            activeVoiceFound: channelState.activeEventIndex != nil,
            activeEventIndex: channelState.activeEventIndex, activeEventMappingIndex: channelState.activeEventMappingIndex,
            speed: channelState.vibratoSpeed, depth: channelState.vibratoDepth,
            speedSource: writesSpeed ? "effect_param" : (speedMemorySource == nil ? "initial_zero_state" : "4xy_channel_state"),
            depthSource: writesDepth ? "effect_param" : (columnWritesDepth ? "volume_column" : (depthMemorySource == nil ? "initial_zero_state" : "4xy_channel_state")),
            controlValue: control.controlValue, waveform: control.waveform,
            waveformSource: control.source == nil ? "default_sine" : "e4x_channel_state",
            effectMemoryReused: speedMemorySource != nil || depthMemorySource != nil,
            effectMemoryMissing: false, effectMemoryDeferred: false,
            speedMemorySource: speedMemorySource, depthMemorySource: depthMemorySource,
            memoryUnavailableReason: nil,
            volumeSlide: combined ? resolved6xyVolumeSlide(from: cell, rowSpeed: timingConfig.speed, channelState: channelState) : nil,
            phaseBefore: Double(phaseBefore), phaseAfter: Double(channelState.vibratoPhase),
            currentLinearPeriodBefore: linear ? outputPeriodBefore : nil,
            currentLinearPeriodAfter: linear ? (channelState.vibratoOutputLinearPeriod ?? basePeriod) : nil,
            currentPlaybackStepBefore: stepBefore, currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: updates, policy: policy
        )
    }

    /// Wraps in FT2's unsigned 16-bit period domain before returning to VTX's 4x domain.
    static func vibratoAmigaPeriod(basePeriod: Double, signedReferenceDelta: Int) -> Double {
        let referencePeriod = Int(basePeriod / xmAmigaPeriodLookupScale)
        return Double(UInt16(truncatingIfNeeded: referencePeriod + signedReferenceDelta)) * xmAmigaPeriodLookupScale
    }

    /// Samples FT2's integer waveform, scales depth, then advances the byte phase.
    static func vibratoTick(phase: Int, speed: Int, depth: Int, control: Int) -> PlaybackSongSyntheticVibratoTick {
        let phase = phase & 255
        let index = (phase >> 2) & 31
        let sign = phase & 128 == 0 ? 1 : -1
        let magnitude: Int
        switch control & 3 {
        case 0: magnitude = tremoloSine[index] // FT2 shares this integer table with tremolo.
        case 1: magnitude = sign > 0 ? index * 8 : 255 - index * 8
        default: magnitude = 255 // Both 2 and 3 are square; bit 3 is an alias.
        }
        return PlaybackSongSyntheticVibratoTick(
            phaseBefore: phase, waveformMagnitude: magnitude, waveformSign: sign, depth: depth,
            signedReferenceDelta: sign * ((magnitude * depth) >> 5), phaseAfter: (phase + speed * 4) & 255
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
            waveformID: waveformID,
            waveformName: waveform.name,
            retriggerSuppressed: retriggerSuppressed,
            unsupportedWaveform: false,
            affectsLaterVibrato: true,
            policy: "e4x_stores_deterministic_vibrato_waveform_for_later_4xy_6xy"
        )
    }

    static func supportedVibratoWaveform(controlValue: Int) -> VibratoWaveform? {
        guard (0...15).contains(controlValue) else { return nil }
        return VibratoWaveform(rawValue: min(controlValue & 3, 2))
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
        targetPitchSample: PlaybackSample? = nil,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic? = nil,
        executionTicks: Range<Int>? = nil
    ) -> PlaybackSongSyntheticTonePortamentoDiagnostic {
        let volumeColumnTonePortamentoAmount: Int?
        if case let .tonePortamento(amount) = volumeColumn?.command {
            volumeColumnTonePortamentoAmount = amount
        } else {
            volumeColumnTonePortamentoAmount = nil
        }
        let commandSource: PlaybackSongSyntheticTonePortamentoCommandSource =
            volumeColumnTonePortamentoAmount == nil ? .effectColumn : .volumeColumn
        let directionBefore = channelState.tonePortamentoDirection
        var directionAtExecution: PlaybackSongSyntheticTonePortamentoDirection?
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
        let channelVolumeBefore = instrumentStateBefore?.baseChannelVolume
        let channelVolumeAfter = instrumentStateAfter?.baseChannelVolume
        let gainBefore = instrumentStateBefore?.activeSampleVolume.map { _ in
            songGain(
                outputChannelVolume: instrumentStateBefore?.outputChannelVolume ?? 64
            )
        }
        let gainAfter = instrumentStateAfter?.activeSampleVolume.map { _ in
            songGain(
                outputChannelVolume: instrumentStateAfter?.outputChannelVolume ?? 64
            )
        }

        if cell.effectType == 0x03, cell.effectParam > 0 {
            channelState.tonePortamentoSpeed = Int(cell.effectParam)
        }
        if cell.effectType != 0x03,
           let volumeColumnTonePortamentoAmount,
           volumeColumnTonePortamentoAmount > 0 {
            // Fx stores x << 4 in shared raw-3xx memory in either mode;
            // the existing mode-specific scheduler converts it to period units.
            channelState.tonePortamentoSpeed = volumeColumnTonePortamentoAmount * 16
        }

        guard hasActiveVoice || channelState.semanticInstrumentIndex != nil else {
            // No sounding header has supplied tuning yet. FT2 admits the target
            // against neutral cold tuning, independently of the newly carried map.
            // Keep current/source pitch absent; only a later real note starts PCM.
            if let note = targetNoteFromCell {
                if usesLinearFrequencyTable, let target = linearTonePitchTarget(note: note, relativeNote: 0, finetune: 0,
                    baseSampleRate: PlaybackSample.xmNeutralSampleRate, outputSampleRate: timingConfig.sampleRate) {
                    channelState.tonePortamentoTargetNote = note
                    channelState.tonePortamentoTargetLinearPeriod = target.linearPeriod
                    channelState.tonePortamentoTargetAmigaPeriod = nil
                    channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
                    channelState.tonePortamentoDirection = .init(
                        currentPeriod: channelState.activeLinearPeriod ?? 0, targetPeriod: target.linearPeriod)
                } else if !usesLinearFrequencyTable, let target = amigaTonePitchTarget(note: note, relativeNote: 0, finetune: 0,
                    baseSampleRate: PlaybackSample.xmNeutralSampleRate, outputSampleRate: timingConfig.sampleRate) {
                    channelState.tonePortamentoTargetNote = note
                    channelState.tonePortamentoTargetLinearPeriod = nil
                    channelState.tonePortamentoTargetAmigaPeriod = target.amigaPeriod
                    channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
                    channelState.tonePortamentoDirection = .init(
                        currentPeriod: channelState.activeAmigaPeriod ?? 0, targetPeriod: target.amigaPeriod)
                }
            }
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
                sameCellNote: sameCellNote,
                instrumentStateUpdated: instrumentStateUpdated,
                instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
                channelVolumeBefore: channelVolumeBefore,
                channelVolumeAfter: channelVolumeAfter,
                noteTargetBefore: noteTargetBefore,
                noteTargetAfter: channelState.tonePortamentoTargetNote,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: channelState.tonePortamentoTargetPlaybackStep != nil,
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
                directionBefore: directionBefore,
                directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                directionAfter: channelState.tonePortamentoDirection,
                stepUpdates: [],
                policy: instrumentStateUpdated
                    ? "same_cell_tone_portamento_cold_initialization_no_source"
                    : "no_active_voice_no_retrigger"
            )
        }

        if let targetNote = targetNoteFromCell,
           toneTargetPeriod(note: targetNote, relativeNote: targetPitchSample?.relativeNote ?? channelState.activeSampleRelativeNote ?? 0,
               finetune: targetPitchSample?.finetune ?? channelState.activeSampleFinetune ?? 0,
               linear: !activeUsesAmigaFrequencyTable) != nil {
            guard let baseSampleRate = targetPitchSample?.baseSampleRate ?? channelState.activeSampleBaseSampleRate,
                  let relativeNote = targetPitchSample?.relativeNote ?? channelState.activeSampleRelativeNote,
                  let finetune = targetPitchSample?.finetune ?? channelState.activeSampleFinetune else {
                return tonePortamentoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    commandSource: commandSource,
                    rawVolumeColumn: volumeColumn?.rawValue,
                    status: .unsupportedFrequencyTable,
                    activeVoiceFound: hasActiveVoice,
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
                    directionBefore: directionBefore,
                    directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                    directionAfter: channelState.tonePortamentoDirection,
                    stepUpdates: [],
                    policy: "missing_active_pitch_sample_state"
                )
            }

            if channelState.activeUsesLinearFrequencyTable == true {
                guard let target = linearTonePitchTarget(
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
                        activeVoiceFound: hasActiveVoice,
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
                        directionBefore: directionBefore,
                        directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                        directionAfter: channelState.tonePortamentoDirection,
                        stepUpdates: [],
                        policy: "target_pitch_out_of_range"
                    )
                }
                channelState.tonePortamentoTargetNote = targetNote
                channelState.tonePortamentoTargetLinearPeriod = target.linearPeriod
                channelState.tonePortamentoTargetAmigaPeriod = nil
                channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
                channelState.tonePortamentoDirection = .init(
                    currentPeriod: channelState.activeLinearPeriod ?? 0, targetPeriod: target.linearPeriod)
            } else if channelState.activeUsesLinearFrequencyTable == false {
                guard let target = amigaTonePitchTarget(
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
                        activeVoiceFound: hasActiveVoice,
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
                        directionBefore: directionBefore,
                        directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                        directionAfter: channelState.tonePortamentoDirection,
                        stepUpdates: [],
                        policy: "amiga_target_pitch_out_of_range"
                    )
                }
                channelState.tonePortamentoTargetNote = targetNote
                channelState.tonePortamentoTargetLinearPeriod = nil
                channelState.tonePortamentoTargetAmigaPeriod = target.amigaPeriod
                channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
                channelState.tonePortamentoDirection = .init(
                    currentPeriod: channelState.activeAmigaPeriod ?? 0, targetPeriod: target.amigaPeriod)
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
                    activeVoiceFound: hasActiveVoice,
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
                    directionBefore: directionBefore,
                    directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                    directionAfter: channelState.tonePortamentoDirection,
                    stepUpdates: [],
                    policy: "missing_active_pitch_mode"
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
                activeVoiceFound: hasActiveVoice,
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
                directionBefore: directionBefore,
                directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                directionAfter: channelState.tonePortamentoDirection,
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
        let speed = channelState.tonePortamentoSpeed ?? 0
        let currentPeriod = activeUsesAmigaFrequencyTable ? channelState.activeAmigaPeriod : channelState.activeLinearPeriod
        let targetPeriod = activeUsesAmigaFrequencyTable ? targetAmigaPeriod : targetLinearPeriod
        // A zero-speed invocation can still clamp an already-crossed target;
        // it does not create speed memory or move an uncrossed period.
        let zeroSpeedClamp = currentPeriod.flatMap { current in targetPeriod.map { target in
            channelState.tonePortamentoDirection != .none &&
                pitchTonePeriod(current, target: target, nativeSpeed: 0,
                    direction: channelState.tonePortamentoDirection, linear: !activeUsesAmigaFrequencyTable) == target
        } } ?? false
        guard speed > 0 || speed == 0 && zeroSpeedClamp else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                commandSource: commandSource,
                rawVolumeColumn: volumeColumn?.rawValue,
                status: .noSpeed,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                sameCellNote: sameCellNote,
                instrumentStateUpdated: instrumentStateUpdated,
                instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
                envelopeReset: targetPitchSample != nil,
                envelopeResetModeled: targetPitchSample != nil,
                channelVolumeBefore: channelVolumeBefore,
                channelVolumeAfter: channelVolumeAfter,
                gainBefore: gainBefore,
                gainAfter: gainAfter,
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
                directionBefore: directionBefore,
                directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                directionAfter: channelState.tonePortamentoDirection,
                stepUpdates: [],
                policy: targetPitchSample != nil ? "same_cell_tone_portamento_retained_source_reset_no_speed" : commandSource == .volumeColumn
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
                activeVoiceFound: hasActiveVoice,
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
                directionBefore: directionBefore,
                directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                directionAfter: channelState.tonePortamentoDirection,
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
                    activeVoiceFound: hasActiveVoice,
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
                    directionBefore: directionBefore,
                    directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                    directionAfter: channelState.tonePortamentoDirection,
                    stepUpdates: [],
                    policy: "missing_active_amiga_pitch_state"
                )
            }

            var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
            let rowSpeed = max(1, timingConfig.speed)
            directionAtExecution = channelState.tonePortamentoDirection
            for tick in executionTicks ?? (1..<rowSpeed) {
                guard channelState.tonePortamentoDirection != .none else { break }
                if abs(currentAmigaPeriod - targetAmigaPeriod) <= 0.000000001 {
                    channelState.tonePortamentoDirection = .towardHigherPeriod
                    currentAmigaPeriod = targetAmigaPeriod
                    currentPlaybackStep = targetPlaybackStep
                    break
                }
                let beforePeriod = currentAmigaPeriod
                let beforeStep = currentPlaybackStep
                currentAmigaPeriod = amigaTonePeriod(currentAmigaPeriod, target: targetAmigaPeriod,
                    nativeSpeed: speed * 4, direction: channelState.tonePortamentoDirection)
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
                    // FT2 leaves the higher-period direction latched after either clamp.
                    channelState.tonePortamentoDirection = .towardHigherPeriod
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
                activeVoiceFound: hasActiveVoice,
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
                envelopeReset: targetPitchSample != nil,
                envelopeResetModeled: targetPitchSample != nil,
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
                directionBefore: directionBefore,
                directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                directionAfter: channelState.tonePortamentoDirection,
                stepUpdates: stepUpdates,
                policy: targetPitchSample != nil ? "same_cell_tone_portamento_retained_source_reset" :
                    "amiga_period_units_per_tick_row_level_first_pass"
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
                activeVoiceFound: hasActiveVoice,
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
                directionBefore: directionBefore,
                directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
                directionAfter: channelState.tonePortamentoDirection,
                stepUpdates: [],
                policy: "missing_active_linear_pitch_state"
            )
        }

        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        directionAtExecution = channelState.tonePortamentoDirection
        for tick in executionTicks ?? (1..<rowSpeed) {
            guard channelState.tonePortamentoDirection != .none else { break }
            if abs(currentLinearPeriod - targetLinearPeriod) <= 0.000000001 {
                channelState.tonePortamentoDirection = .towardHigherPeriod
                currentLinearPeriod = targetLinearPeriod
                currentPlaybackStep = targetPlaybackStep
                break
            }
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            currentLinearPeriod = pitchTonePeriod(currentLinearPeriod, target: targetLinearPeriod,
                nativeSpeed: speed * 4, direction: channelState.tonePortamentoDirection, linear: true)
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
                // FT2 leaves the higher-period direction latched after either clamp.
                channelState.tonePortamentoDirection = .towardHigherPeriod
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
            activeVoiceFound: hasActiveVoice,
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
            envelopeReset: targetPitchSample != nil,
            envelopeResetModeled: targetPitchSample != nil,
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
            directionBefore: directionBefore,
            directionAtExecution: directionAtExecution ?? channelState.tonePortamentoDirection,
            directionAfter: channelState.tonePortamentoDirection,
            stepUpdates: stepUpdates,
            policy: targetPitchSample != nil ? "same_cell_tone_portamento_retained_source_reset" : commandSource == .volumeColumn
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
        directionBefore: PlaybackSongSyntheticTonePortamentoDirection = .none,
        directionAtExecution: PlaybackSongSyntheticTonePortamentoDirection = .none,
        directionAfter: PlaybackSongSyntheticTonePortamentoDirection = .none,
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
            directionBefore: directionBefore,
            directionAtExecution: directionAtExecution,
            directionAfter: directionAfter,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

}
