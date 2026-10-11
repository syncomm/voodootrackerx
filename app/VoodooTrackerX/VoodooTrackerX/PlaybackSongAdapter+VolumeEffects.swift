import Foundation

extension PlaybackSongSyntheticAdapter {
    struct TremoloState: Equatable {
        var speed = 0
        var depth = 0
        var control = 0
        var phase = 0
        var activated = false
    }

    static let tremoloSine = [
        0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
        255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24,
    ]

    static func tremoloDelta(phase: Int, depth: Int, control: Int, vibratoPhase: Int) -> Int {
        let index = (phase >> 2) & 31
        let magnitude: Int
        switch control & 3 {
        case 0: magnitude = tremoloSine[index]
        // FT2 intentionally reproduced: ramp complement uses vibrato's sign.
        case 1: magnitude = vibratoPhase & 128 != 0 ? 255 - index * 8 : index * 8
        default: magnitude = 255 // Waveforms 2 and 3 are both square in FT2.
        }
        let delta = (magnitude * depth) >> 6
        return phase & 128 == 0 ? delta : -delta
    }

    static func restoreInstrumentOnlyDefaults(
        cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, scheduledFrame: Int, globalVolume: Int,
        channelState: inout ChannelState,
        updates: inout [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        resets: inout [PlaybackVoiceStateEvent]
    ) -> MixerPlaybackStateChange? {
        let before = channelState
        channelState.baseChannelVolume = channelState.triggeredSampleDefaultVolume
        channelState.volumeValueZeroedByAxy = false
        channelState.initializePanning(fromSampleHeader: channelState.triggeredSampleDefaultPan)
        updates.append(voiceStateUpdateDiagnostic(
            source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
            scheduledFrame: scheduledFrame, cell: cell, commandSource: .instrumentState,
            command: .instrumentDefaultVolume(value: channelState.baseChannelVolume), rawVolumeColumn: nil,
            effectType: cell.effectType, effectParam: cell.effectParam, status: .applied,
            behavior: nil, channelStateBefore: before, channelStateAfter: channelState,
            globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume
        ))
        // K00 releases without restarting envelopes. Volume-column portamento
        // takes precedence over K00; phase reset uses the same existing gate.
        let releasesImmediately = cell.effectType == 0x14 && cell.effectParam == 0 && cell.volumeColumn >> 4 != 0x0F
        guard !releasesImmediately else { return nil }
        let reset = MixerPlaybackStateChange.reset(.init(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true))
        if let event = channelState.activeEventIndex {
            resets.append(.init(activeEventIndex: event, channelIndex: channelIndex,
                scheduledFrame: scheduledFrame, change: reset))
        }
        // The channel timeline consumes this same decision when no source exists.
        return reset
    }

    static func prepareTremoloRow(
        cell: PlaybackCell, song: PlaybackSong, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, scheduledFrame: Int, globalVolume: Int,
        initializesInstrumentVolume: Bool,
        channelState: inout ChannelState,
        updates: inout [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    ) {
        // Instrument triggers reset phases before a same-cell control write. A
        // note alone does not. Keep unsupported/delayed trigger routing unchanged.
        let instrumentTrigger = cell.instrument > 0 && cell.note < 97 &&
            song.instrumentsByIndex[Int(cell.instrument)] != nil &&
            !(cell.effectType == 0x0E && (0xD1...0xDF).contains(cell.effectParam))
        if instrumentTrigger {
            // K00 bypasses triggerInstrument; volume-column portamento takes
            // precedence over K00 in FT2 and still performs that trigger.
            if !(cell.effectType == 0x14 && cell.effectParam == 0) || cell.volumeColumn >> 4 == 0x0F {
                resetTremoloTriggerPhases(state: &channelState)
            }
            if !initializesInstrumentVolume && (channelState.tremolo.activated || cell.effectType == 0x07) {
                let before = channelState
                // In this adapter, the sample default remains an independent
                // factor. Restore its neutral tracker multiplier, then let the
                // ordinary same-cell volume writers override it below.
                channelState.baseChannelVolume = 64
                updates.append(voiceStateUpdateDiagnostic(
                    source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame, cell: cell, commandSource: .instrumentState,
                    command: .instrumentDefaultVolume(value: 64), rawVolumeColumn: nil,
                    effectType: cell.effectType, effectParam: cell.effectParam, status: .applied,
                    behavior: nil, channelStateBefore: before, channelStateAfter: channelState,
                    globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume
                ))
            }
        }
        if cell.effectType == 0x0E && cell.effectParam >> 4 == 0x04 {
            channelState.tremoloVibratoControl = Int(cell.effectParam & 15)
        }
        if cell.effectType == 0x0E && cell.effectParam >> 4 == 0x07 {
            channelState.tremolo.control = Int(cell.effectParam & 15)
            updates.append(voiceStateUpdateDiagnostic(
                source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame, cell: cell, commandSource: .effectColumn,
                command: .tremoloControl(value: channelState.tremolo.control), rawVolumeColumn: nil,
                effectType: cell.effectType, effectParam: cell.effectParam, status: .applied,
                behavior: nil, channelStateBefore: channelState, channelStateAfter: channelState,
                globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume,
                activeVoiceUpdatedOverride: false
            ))
        }
    }

    static func resetTremoloTriggerPhases(state: inout ChannelState) {
        if state.tremolo.control & 4 == 0 { state.tremolo.phase = 0 }
        if state.tremoloVibratoControl & 4 == 0 { state.tremoloVibratoPhase = 0 }
        // The same existing instrument-trigger gate owns pitch-phase resets.
        if state.vibratoControl?.retriggerSuppressed != true { state.vibratoPhase = 0 }
    }

    static func advanceTremoloVibratoObserver(cell: PlaybackCell, rowSpeed: Int, state: inout ChannelState) {
        guard rowSpeed > 1, cell.effectType == 0x04 || cell.effectType == 0x06 else { return }
        let speed = Int(cell.effectParam >> 4)
        if cell.effectType == 0x04 && speed > 0 { state.tremoloVibratoSpeed = speed }
        state.tremoloVibratoPhase = (state.tremoloVibratoPhase + (rowSpeed - 1) * state.tremoloVibratoSpeed * 4) & 255
    }

    static func applyTremolo(
        cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int, syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig, timingPlan: PlaybackSongFxxTimingPlan,
        globalVolume: Int, state: inout ChannelState,
        volumeColumnSlide: PlaybackSongSyntheticVolumeColumnDiagnostic? = nil
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x07, timingConfig.speed > 1 else { return [] }
        let speed = Int(cell.effectParam >> 4)
        let depth = Int(cell.effectParam & 15)
        if speed > 0 { state.tremolo.speed = speed }
        if depth > 0 { state.tremolo.depth = depth }
        state.tremolo.activated = true
        var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        updates.reserveCapacity((timingConfig.speed - 1) * (volumeColumnSlide == nil ? 1 : 2))
        for tick in 1..<timingConfig.speed {
            updates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumnSlide, cell: cell, source: source,
                channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: timingConfig.speed,
                timingPlan: timingPlan, state: &state, globalVolume: globalVolume))
            let before = state
            let delta = tremoloDelta(phase: state.tremolo.phase, depth: state.tremolo.depth,
                                     control: state.tremolo.control, vibratoPhase: state.tremoloVibratoPhase)
            let unclamped = state.baseChannelVolume + delta
            state.outputChannelVolume = clampedVolumeValue(unclamped)
            state.tremolo.phase = (state.tremolo.phase + state.tremolo.speed * 4) & 255
            let semantic = PlaybackSongSyntheticTremoloTick(
                baseVolume: state.baseChannelVolume, outputVolume: state.outputChannelVolume,
                sampleVolume: state.activeSampleVolume, speed: state.tremolo.speed, depth: state.tremolo.depth,
                control: state.tremolo.control, phaseBefore: before.tremolo.phase, phaseAfter: state.tremolo.phase,
                vibratoPhase: state.tremoloVibratoPhase, delta: delta, clamped: unclamped != state.outputChannelVolume
            )
            updates.append(voiceStateUpdateDiagnostic(
                source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick), cell: cell,
                commandSource: .effectColumn, command: .tremolo(semantic), rawVolumeColumn: nil,
                effectType: cell.effectType, effectParam: cell.effectParam, status: .applied,
                behavior: .tickLevelAfterTick0, channelStateBefore: before, channelStateAfter: state,
                globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume,
                effectMemoryReused: speed == 0 || depth == 0,
                activeVoiceUpdatedOverride: state.activeEventIndex != nil && state.activeSampleVolume != nil
            ))
        }
        return updates
    }

    static let lxxSetEnvelopePositionPolicy = "first_pass_volume_envelope_position_only"

    static func mixerSampleBuffer(
        for sample: PlaybackSample,
        cache: inout [MixerSampleBufferCacheKey: MixerSampleBuffer]
    ) -> MixerSampleBuffer {
        let key = sample.pcm.withUnsafeBufferPointer { buffer in
            MixerSampleBufferCacheKey(
                storageAddress: UInt(bitPattern: buffer.baseAddress),
                frameCount: buffer.count
            )
        }
        if let cached = cache[key] {
            return cached
        }
        let buffer = MixerSampleBuffer(monoPCM: sample.pcm)
        cache[key] = buffer
        return buffer
    }

    static func envelopePositionDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        channelState: ChannelState
    ) -> PlaybackSongSyntheticEnvelopePositionDiagnostic {
        let requestedPosition = Int(cell.effectParam)
        let requestedPositionFrame = envelopePositionFrame(
            requestedPosition: requestedPosition,
            timingConfig: timingConfig
        )
        let activeVoiceFound = channelState.activeEventIndex != nil
        let status: PlaybackSongSyntheticEnvelopePositionDiagnostic.Status
        let appliedPositionFrame: Int?
        let clamped: Bool
        if !activeVoiceFound && channelState.semanticInstrumentIndex == nil {
            status = .noActiveVoice
            appliedPositionFrame = nil
            clamped = false
        } else if channelState.activeVolumeEnvelopeStatus == .mapped,
                  let maxFrame = channelState.activeVolumeEnvelopeMaxFrame {
            let clampedFrame = min(max(0, requestedPositionFrame), maxFrame)
            status = .applied
            appliedPositionFrame = clampedFrame
            clamped = clampedFrame != requestedPositionFrame
        } else {
            status = .noEnvelope
            appliedPositionFrame = nil
            clamped = false
        }
        return PlaybackSongSyntheticEnvelopePositionDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            detected: true,
            applied: status == .applied,
            deferred: false,
            ignoredAsNoOp: status != .applied,
            status: status,
            requestedPosition: requestedPosition,
            requestedPositionFrame: requestedPositionFrame,
            appliedPositionFrame: appliedPositionFrame,
            clamped: clamped,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            volumeEnvelopeStatus: channelState.activeVolumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: channelState.activeVolumeEnvelopeSourcePointCount,
            mappedVolumeEnvelopePointCount: channelState.activeVolumeEnvelopeMappedPointCount,
            policy: lxxSetEnvelopePositionPolicy
        )
    }

    static func envelopePositionFrame(
        requestedPosition: Int,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> Int {
        let timing = SyntheticTrackerTiming(config: timingConfig)
        guard timing.framesPerTick.isFinite,
              timing.framesPerTick > 0 else {
            return 0
        }
        let exactFrame = Double(max(0, requestedPosition)) * timing.framesPerTick
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        if exactFrame >= Double(Int(UInt32.max)) {
            return Int(UInt32.max)
        }
        return Int(exactFrame.rounded(.down))
    }

    static func applyActiveVolumeEnvelopeMapping(
        _ mapping: VolumeEnvelopeMapping,
        to channelState: inout ChannelState
    ) {
        channelState.activeVolumeEnvelopeStatus = mapping.status
        channelState.activeVolumeEnvelopeMaxFrame = mapping.envelope?.points.last?.positionFrame
        channelState.activeVolumeEnvelopeSourcePointCount = mapping.sourcePointCount
        channelState.activeVolumeEnvelopeMappedPointCount = mapping.mappedPointCount
    }

    static func voiceStateUpdate(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        cell: PlaybackCell,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        channelStateBefore: ChannelState,
        channelStateAfter: ChannelState,
        globalVolumeValue: Int
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
                channelStateAfter: channelStateBefore,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
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
            channelStateAfter: channelStateAfter,
            globalVolumeBefore: globalVolumeValue,
            globalVolumeAfter: globalVolumeValue
        )
    }

    static func reportsVolumeColumnStateUpdate(
        _ command: PlaybackSongSyntheticVolumeColumnCommand
    ) -> Bool {
        switch command {
        case .setVolume,
             .fineVolumeSlideDown,
             .fineVolumeSlideUp,
             .setPanning:
            return true
        case .none,
             .volumeSlideDown,
             .volumeSlideUp,
             .panningSlideLeft,
             .panningSlideRight,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return false
        }
    }

    static func applyEffectColumnState(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        rowSpeed: Int,
        channelState: inout ChannelState,
        globalVolumeValue: Int
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? {
        switch cell.effectType {
        case 0x0C:
            let before = channelState
            channelState.baseChannelVolume = clampedVolumeValue(Int(cell.effectParam))
            channelState.volumeValueZeroedByAxy = false
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .cxxSetVolume(value: channelState.baseChannelVolume),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: nil,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x08:
            let before = channelState
            let panningValue = clampedPanningValue(Double(Int(cell.effectParam)))
            channelState.applyChannelPanningValue(panningValue)
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
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x0E where isFineVolumeSlideEffect(cell):
            let before = channelState
            let rawAmount = fineVolumeSlideAmount(from: cell)
            let isSlideUp = isFineVolumeSlideUpEffect(cell)
            let remembered = isSlideUp ? before.fineVolumeUpMemory : before.fineVolumeDownMemory
            if rawAmount > 0 {
                let memory = FineVolumeSlideMemory(amount: rawAmount, source: .init(
                    source: source, channelIndex: channelIndex, effectType: cell.effectType, effectParam: cell.effectParam))
                if isSlideUp { channelState.fineVolumeUpMemory = memory }
                else { channelState.fineVolumeDownMemory = memory }
            }
            let reused = rawAmount == 0 ? remembered : nil
            let amount = rawAmount > 0 ? rawAmount : reused?.amount ?? 0
            let command: PlaybackSongSyntheticVoiceStateUpdateCommand = isSlideUp
                ? .eaxFineVolumeSlideUp(amount: amount)
                : .ebxFineVolumeSlideDown(amount: amount)
            // Even cold zero writes base to output at tick 0. Applied writer intent
            // lets the existing causal projection repair a stale held target.
            if isSlideUp {
                channelState.baseChannelVolume = clampedVolumeValue(before.baseChannelVolume + amount)
            } else {
                channelState.baseChannelVolume = clampedVolumeValue(before.baseChannelVolume - amount)
            }
            channelState.volumeValueZeroedByAxy = false
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: command,
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .rowLevelApproximation,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue,
                effectMemoryReused: reused != nil,
                effectMemoryMissing: rawAmount == 0 && reused == nil,
                memorySource: reused?.source
            )
        default:
            return nil
        }
    }

    static func apply6xyVolumeSlide(
        from cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int, syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig, timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState, globalVolumeValue: Int,
        volumeColumnSlide: PlaybackSongSyntheticVolumeColumnDiagnostic? = nil
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        let rowSpeed = timingConfig.speed
        guard cell.effectType == 0x06, rowSpeed > 1 else { return [] }
        rememberVolumeSlide(from: cell, source: source, channelIndex: channelIndex,
                            rowSpeed: rowSpeed, channelState: &channelState)
        let remembered = cell.effectParam == 0 ? channelState.volumeSlideMemory : nil
        let slide = resolved6xyVolumeSlide(from: cell, rowSpeed: rowSpeed, channelState: channelState)
        // FT2 runs doVibrato then volSlide on ticks 1..<speed. Initial zero
        // memory still restores output from base on those ticks, never tick 0.
        var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        updates.reserveCapacity((rowSpeed - 1) * (volumeColumnSlide == nil ? 1 : 2))
        for tick in 1..<rowSpeed {
            updates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumnSlide, cell: cell, source: source,
                channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: rowSpeed,
                timingPlan: timingPlan, state: &channelState, globalVolume: globalVolumeValue))
            let before = channelState
            let unclamped = before.baseChannelVolume + slide.up - slide.down
            channelState.baseChannelVolume = clampedVolumeValue(unclamped)
            if slide.amount > 0 { channelState.volumeValueZeroedByAxy = false }
            // Zero slide still writes local output; publication must compare the
            // composed target with this generation's held gain, not local arithmetic.
            updates.append(voiceStateUpdateDiagnostic(
                source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick), cell: cell,
                commandSource: .effectColumn, command: .effect6xyVolumeSlide(up: slide.up, down: slide.down),
                rawVolumeColumn: nil, effectType: cell.effectType, effectParam: cell.effectParam,
                status: .applied, behavior: .tickLevelAfterTick0,
                channelStateBefore: before, channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue, globalVolumeAfter: globalVolumeValue,
                volumeSlide: slide, volumeSlideClamped: unclamped != channelState.baseChannelVolume,
                volumeSlideTick0Suppressed: true, volumeSlideRowSpeed: rowSpeed,
                effectMemoryReused: remembered != nil, memorySource: remembered?.source,
                activeVoiceUpdatedOverride: before.activeEventIndex != nil && before.activeSampleVolume != nil
            ))
        }
        return updates
    }

    static func applyEffectColumnVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        usesLinearFrequencyTable: Bool,
        globalVolumeValue: Int,
        volumeColumnSlide: PlaybackSongSyntheticVolumeColumnDiagnostic? = nil
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x0A || cell.effectType == 0x05 else {
            return []
        }

        let requestedSlide = axyVolumeSlideAmounts(effectParam: cell.effectParam)
        rememberVolumeSlide(from: cell, source: source, channelIndex: channelIndex,
                            rowSpeed: timingConfig.speed, channelState: &channelState)
        // Cold A00 and supported Linear 500 execute zero independently of tone
        // admission, without inventing A/5/6 history or broadening Amiga 5xy.
        let coldA00 = cell.effectType == 0x0A && cell.effectParam == 0 && channelState.volumeSlideMemory == nil
        let cold500 = usesLinearFrequencyTable && cell.effectType == 0x05 && cell.effectParam == 0 && channelState.volumeSlideMemory == nil
        let coldZeroSlide = coldA00 || cold500
        let coldPolicy = coldA00 ? "a00_cold_zero_slide" : "500_cold_zero_slide"
        let slide: VolumeSlideAmounts
        let memorySource: PlaybackSongSyntheticEffectMemorySource?
        let effectMemoryReused: Bool
        let effectMemoryMissing: Bool
        let effectMemoryDeferred: Bool
        let memoryUnavailableReason: String?

        if requestedSlide.amount > 0 {
            slide = requestedSlide
            memorySource = nil
            effectMemoryReused = false
            effectMemoryMissing = false
            effectMemoryDeferred = false
            memoryUnavailableReason = nil
        } else if let remembered = channelState.volumeSlideMemory {
            slide = remembered.slide
            memorySource = remembered.source
            effectMemoryReused = true
            effectMemoryMissing = false
            effectMemoryDeferred = false
            memoryUnavailableReason = nil
        } else {
            slide = requestedSlide
            memorySource = nil
            effectMemoryReused = false
            effectMemoryMissing = !coldZeroSlide
            effectMemoryDeferred = !coldZeroSlide
            memoryUnavailableReason = coldZeroSlide ? nil : volumeSlideMemoryUnavailableReason(for: cell)
        }
        let rowSpeed = max(1, timingConfig.speed)
        let command = volumeSlideCommand(for: cell, up: slide.up, down: slide.down)
        guard slide.amount > 0 || (coldZeroSlide && rowSpeed > 1) else {
            let before = channelState
            var updates = [
                voiceStateUpdateDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: 0),
                    cell: cell,
                    commandSource: .effectColumn,
                    command: command,
                    rawVolumeColumn: nil,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignoredNoOp,
                    behavior: .tickLevelAfterTick0,
                    channelStateBefore: before,
                    channelStateAfter: before,
                    globalVolumeBefore: globalVolumeValue,
                    globalVolumeAfter: globalVolumeValue,
                    volumeSlide: slide,
                    volumeSlideClamped: false,
                    volumeSlideTick0Suppressed: true,
                    volumeSlideRowSpeed: rowSpeed,
                    volumeSlidePolicyOverride: coldZeroSlide ? coldPolicy + "_no_nonzero_ticks" : zeroVolumeSlidePolicy(for: cell),
                    effectMemoryReused: effectMemoryReused,
                    effectMemoryMissing: effectMemoryMissing,
                    effectMemoryDeferred: effectMemoryDeferred,
                    memorySource: memorySource,
                    memoryUnavailableReason: memoryUnavailableReason,
                    activeVoiceUpdatedOverride: false
                ),
            ]
            if volumeColumnSlide != nil && rowSpeed > 1 {
                for tick in 1..<rowSpeed {
                    updates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumnSlide, cell: cell, source: source,
                        channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: rowSpeed,
                        timingPlan: timingPlan, state: &channelState, globalVolume: globalVolumeValue))
                }
            }
            return updates
        }

        guard rowSpeed > 1 else {
            return []
        }

        var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        updates.reserveCapacity(rowSpeed - 1)
        for tick in 1..<rowSpeed {
            updates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumnSlide, cell: cell, source: source,
                channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: rowSpeed,
                timingPlan: timingPlan, state: &channelState, globalVolume: globalVolumeValue))
            let before = channelState
            let unclampedAfter = before.baseChannelVolume + slide.up - slide.down
            // The base setter restores output even for zero arithmetic. Applied
            // Cold zero-slide ticks remain local writers for held-target publication.
            channelState.baseChannelVolume = clampedVolumeValue(unclampedAfter)
            if slide.amount > 0 { channelState.volumeValueZeroedByAxy = channelState.baseChannelVolume == 0 }
            let clamped = channelState.baseChannelVolume != unclampedAfter
            let activeVoiceAvailable = before.activeEventIndex != nil && before.activeSampleVolume != nil
            updates.append(voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                cell: cell,
                commandSource: .effectColumn,
                command: command,
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .tickLevelAfterTick0,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue,
                volumeSlide: slide,
                volumeSlideClamped: clamped,
                volumeSlideTick0Suppressed: true,
                volumeSlideRowSpeed: rowSpeed,
                volumeSlidePolicyOverride: coldZeroSlide ? coldPolicy + "_output_restoration" : nil,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: effectMemoryMissing,
                effectMemoryDeferred: effectMemoryDeferred,
                memorySource: memorySource,
                memoryUnavailableReason: memoryUnavailableReason,
                activeVoiceUpdatedOverride: activeVoiceAvailable
            ))
        }
        return updates
    }

    // FT2 A/5/6 share one full-byte memory, written only on nonzero ticks.
    static func rememberVolumeSlide(
        from cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        rowSpeed: Int, channelState: inout ChannelState
    ) {
        guard rowSpeed > 1, cell.effectParam != 0 else { return }
        channelState.volumeSlideMemory = VolumeSlideMemory(
            parameter: cell.effectParam,
            source: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        )
    }

    static func resolved6xyVolumeSlide(from cell: PlaybackCell, rowSpeed: Int, channelState: ChannelState) -> VolumeSlideAmounts {
        let parameter = cell.effectParam != 0 ? cell.effectParam :
            (rowSpeed > 1 ? channelState.volumeSlideMemory?.parameter ?? 0 : 0)
        return volumeSlideAmounts(effectParam: parameter, mixedNibblePolicy: "up_nibble_precedence_current_policy",
                                  zeroPolicy: rowSpeed > 1 ? "600_initial_zero_memory" : "600_no_nonzero_ticks")
    }

    static func applyAxyVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        usesLinearFrequencyTable: Bool,
        globalVolumeValue: Int
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        applyEffectColumnVolumeSlide(
            from: cell,
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            timingPlan: timingPlan,
            channelState: &channelState,
            usesLinearFrequencyTable: usesLinearFrequencyTable,
            globalVolumeValue: globalVolumeValue
        )
    }

    static func volumeSlideCommand(
        for cell: PlaybackCell,
        up: Int,
        down: Int
    ) -> PlaybackSongSyntheticVoiceStateUpdateCommand {
        if cell.effectType == 0x05 {
            return .effect5xyVolumeSlide(up: up, down: down)
        }
        return .axyVolumeSlide(up: up, down: down)
    }

    static func zeroVolumeSlidePolicy(for cell: PlaybackCell) -> String? {
        switch cell.effectType {
        case 0x05:
            return "500_no_volume_slide_memory_no_op"
        case 0x0A:
            return "a00_no_volume_slide_memory_no_op"
        default:
            return nil
        }
    }

    static func volumeSlideMemoryUnavailableReason(for cell: PlaybackCell) -> String {
        cell.effectType == 0x05
            ? "missing_5xy_volume_slide_memory"
            : "missing_axy_volume_slide_memory"
    }

    static func applyGlobalVolumeSet(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        sourceChannelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        channelStates: [ChannelState],
        globalVolumeState: inout GlobalVolumeState
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x10 else {
            return []
        }

        let beforeGlobalVolume = globalVolumeState.volumeValue
        let afterGlobalVolume = clampedGlobalVolumeValue(Int(cell.effectParam))
        globalVolumeState.volumeValue = afterGlobalVolume
        // Mutation is song-global; delivery is projected once per channel turn,
        // after trigger identities and all writers at this frame are known.
        return [
            globalVolumeSetDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: nil,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                channelState: channelStates.indices.contains(sourceChannelIndex) ? channelStates[sourceChannelIndex] : ChannelState(),
                globalVolumeBefore: beforeGlobalVolume,
                globalVolumeAfter: afterGlobalVolume,
                activeVoiceUpdatedOverride: false
            ),
        ]
    }

    static func globalVolumeSetDiagnostic(
        source: PlaybackPosition,
        sourceChannelIndex: Int,
        targetChannelIndex: Int?,
        syntheticRow: Int,
        scheduledFrame: Int,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticVoiceStateUpdateStatus,
        channelState: ChannelState,
        globalVolumeBefore: Int,
        globalVolumeAfter: Int,
        activeVoiceUpdatedOverride: Bool
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        voiceStateUpdateDiagnostic(
            source: source,
            channelIndex: sourceChannelIndex,
            syntheticRow: syntheticRow,
            scheduledFrame: scheduledFrame,
            cell: cell,
            commandSource: .effectColumn,
            command: .gxxSetGlobalVolume(value: globalVolumeAfter),
            rawVolumeColumn: nil,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            behavior: .rowLevelApproximation,
            channelStateBefore: channelState,
            channelStateAfter: channelState,
            globalVolumeBefore: globalVolumeBefore,
            globalVolumeAfter: globalVolumeAfter,
            includeGlobalVolumeFields: true,
            targetChannelIndex: targetChannelIndex,
            activeVoiceUpdatedOverride: activeVoiceUpdatedOverride
        )
    }

    static func applyGlobalVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        sourceChannelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int = 0,
        scheduledFrame: Int,
        channelStates: [ChannelState],
        globalVolumeState: inout GlobalVolumeState
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x11 else {
            return []
        }

        let beforeGlobalVolume = globalVolumeState.volumeValue
        let channelState = channelStates.indices.contains(sourceChannelIndex) ? channelStates[sourceChannelIndex] : ChannelState()
        let resolvedParameter = cell.effectParam != 0 ? cell.effectParam : channelState.globalVolumeSlideMemory?.parameter ?? 0
        let slide = globalVolumeSlidePlan(effectParam: resolvedParameter)
        guard slide.amount > 0 else {
            return [
                globalVolumeSlideDiagnostic(
                    source: source,
                    sourceChannelIndex: sourceChannelIndex,
                    targetChannelIndex: nil,
                    syntheticRow: syntheticRow,
                    syntheticTick: syntheticTick,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    status: .ignoredNoOp,
                    slide: slide,
                    channelState: channelState,
                    globalVolumeBefore: beforeGlobalVolume,
                    globalVolumeAfter: beforeGlobalVolume,
                    clamped: false,
                    activeVoiceUpdatedOverride: false
                ),
            ]
        }

        let unclampedAfter = beforeGlobalVolume + slide.up - slide.down
        let afterGlobalVolume = clampedGlobalVolumeValue(unclampedAfter)
        globalVolumeState.volumeValue = afterGlobalVolume
        let clamped = unclampedAfter != afterGlobalVolume
        return [
            globalVolumeSlideDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: nil,
                syntheticRow: syntheticRow,
                syntheticTick: syntheticTick,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                slide: slide,
                channelState: channelState,
                globalVolumeBefore: beforeGlobalVolume,
                globalVolumeAfter: afterGlobalVolume,
                clamped: clamped,
                activeVoiceUpdatedOverride: false
            ),
        ]
    }

    static func globalVolumeSlideDiagnostic(
        source: PlaybackPosition,
        sourceChannelIndex: Int,
        targetChannelIndex: Int?,
        syntheticRow: Int,
        syntheticTick: Int = 0,
        scheduledFrame: Int,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticVoiceStateUpdateStatus,
        slide: GlobalVolumeSlidePlan,
        channelState: ChannelState,
        globalVolumeBefore: Int,
        globalVolumeAfter: Int,
        clamped: Bool,
        activeVoiceUpdatedOverride: Bool
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        voiceStateUpdateDiagnostic(
            source: source,
            channelIndex: sourceChannelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: syntheticTick,
            scheduledFrame: scheduledFrame,
            cell: cell,
            commandSource: .effectColumn,
            command: .hxyGlobalVolumeSlide(up: slide.up, down: slide.down),
            rawVolumeColumn: nil,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            behavior: syntheticTick == 0 ? .rowLevelApproximation : .tickLevelAfterTick0,
            channelStateBefore: channelState,
            channelStateAfter: channelState,
            globalVolumeBefore: globalVolumeBefore,
            globalVolumeAfter: globalVolumeAfter,
            includeGlobalVolumeFields: true,
            targetChannelIndex: targetChannelIndex,
            globalVolumeSlideDirection: slide.direction,
            globalVolumeSlideAmount: slide.amount,
            globalVolumeSlideClamped: clamped,
            globalVolumeSlideBothNibblesNonzero: slide.bothNibblesNonzero,
            globalVolumeSlidePolicy: slide.policy,
            globalVolumeSlideResolvedParameter: cell.effectParam != 0 ? cell.effectParam : channelState.globalVolumeSlideMemory?.parameter ?? 0,
            effectMemoryReused: cell.effectParam == 0 && channelState.globalVolumeSlideMemory != nil,
            effectMemoryMissing: cell.effectParam == 0 && channelState.globalVolumeSlideMemory == nil,
            memorySource: channelState.globalVolumeSlideMemory?.source,
            memoryUnavailableReason: cell.effectParam == 0 && channelState.globalVolumeSlideMemory == nil ? "h00_unseeded_channel_true_no_op" : nil,
            activeVoiceUpdatedOverride: activeVoiceUpdatedOverride
        )
    }

    /// Plan-local output carry; all other controls remain in the immutable row snapshot.
    struct GlobalVolumeChannelProjection {
        let snapshot: PlaybackXMChannelRow
        var outputVolume: Int

        init(_ snapshot: PlaybackXMChannelRow) {
            self.snapshot = snapshot
            outputVolume = snapshot.controls.outputChannelVolume
        }

        func targetState(event: Int, sampleVolume: Float?) -> ChannelState {
            var state = snapshot.controls
            state.outputChannelVolume = outputVolume
            state.activeEventIndex = event
            state.activeSampleVolume = sampleVolume
            return state
        }
    }

    /// Projects Gxx/Hxy canonical transitions into existing immutable gain publications.
    /// Held values are output targets by trigger identity, never channel-local global-volume state.
    static func planGlobalVolumeChannelTargets(timingPlan: PlaybackSongFxxTimingPlan, context: inout AdapterRowContext,
                                               profileSession: AdapterPlanProfileSession? = nil) {
        let start = profileSession?.beginPhase()
        var records = 0, channelTurns = 0, targetStates = 0, peakRecords = 0
        defer {
            profileSession?.recordPhase("global_volume_channel_projection", startedAt: start, fields: [
                .init("projection_record_count", records),
                .init("projection_record_stride", MemoryLayout<GlobalVolumeChannelProjection>.stride),
                .init("projection_logical_bytes", records * MemoryLayout<GlobalVolumeChannelProjection>.stride),
                .init("peak_projection_record_count", peakRecords), .init("channel_turn_count", channelTurns),
                .init("full_controls_turn_copy_count", 0), .init("target_state_materialization_count", targetStates),
                .init("channel_state_stride", MemoryLayout<ChannelState>.stride)
            ])
        }
        let original = context.voiceStateUpdates
        guard let firstRow = original.first(where: { $0.effectType == 0x10 || ($0.effectType == 0x11 && $0.syntheticTick > 0) })?.syntheticRow else { return }
        let updatesByRow = Dictionary(grouping: original.indices, by: { original[$0].syntheticRow })
        let controlsByRow = Dictionary(grouping: context.xmChannelRows, by: \.syntheticRow)
        struct Route { let frame: Int; let channel: Int; let event: Int? }
        var routes = context.eventMappings.map { mapping in
            let event = context.events[mapping.eventIndex]
            return Route(frame: event.scheduledStartFrame ?? timingPlan.frameFor(row: event.row, tick: event.tick),
                  channel: mapping.channelIndex, event: mapping.eventIndex)
        }
        routes += context.xmEmptyRoutes.map { Route(frame: $0.scheduledFrame, channel: $0.channelIndex, event: nil) }
        routes.sort { $0.frame == $1.frame ? $0.channel < $1.channel : $0.frame < $1.frame }
        let sampleVolumes = Dictionary(uniqueKeysWithValues: context.eventMappings.map { ($0.eventIndex, $0.sampleVolume) })
        let resets = Dictionary(grouping: context.playbackStateEvents, by: \.scheduledFrame)
        let releases = Dictionary(grouping: context.keyOffEvents.filter(\.applied), by: { $0.scheduledFrame ?? -1 })
        let cuts = Dictionary(grouping: context.noteCutEffects.filter(\.applied), by: { $0.scheduledFrame ?? -1 })
        var active = [Int: Int](), heldGains = [Int: Float](), affected = Set<Int>(), released = Set<Int>()
        var gxxAffected = Set<Int>()
        var routeCursor = 0
        // This is a read-only projection of canonical mutations, not a second arithmetic authority.
        var visibleGlobal = GlobalVolumeState.defaultValue
        var result = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        result.reserveCapacity(original.count)
        var lastControls = [GlobalVolumeChannelProjection]()
        for timing in timingPlan.rowTimings {
            let row = timing.syntheticRow
            let rowControls = (controlsByRow[row] ?? []).sorted { $0.channelIndex < $1.channelIndex }
            let byTick = Dictionary(grouping: updatesByRow[row] ?? [], by: { original[$0].syntheticTick })
            let rowHasH = (updatesByRow[row] ?? []).contains { original[$0].effectType == 0x11 && original[$0].syntheticTick > 0 }
            var controls = rowControls.map(GlobalVolumeChannelProjection.init)
            records += controls.count
            channelTurns += controls.count * timing.effectiveSpeed
            peakRecords = max(peakRecords, controls.count)
            if row < firstRow { result.append(contentsOf: (updatesByRow[row] ?? []).map { original[$0] }) }
            for tick in 0..<timing.effectiveSpeed {
                let frame = timingPlan.frameFor(row: row, tick: tick)
                while routeCursor < routes.count && routes[routeCursor].frame <= frame {
                    let route = routes[routeCursor]
                    active[route.channel] = route.event
                    if let event = route.event { heldGains[event] = context.events[event].gain }
                    routeCursor += 1
                }
                for reset in resets[frame] ?? [] {
                    if case let .reset(dimensions) = reset.change, dimensions.keyOn { released.remove(reset.activeEventIndex) }
                    if case .keyOff = reset.change { released.insert(reset.activeEventIndex) }
                }
                for release in releases[frame] ?? [] {
                    if let event = release.activeEventIndex { released.insert(event) }
                }
                for cut in cuts[frame] ?? [] {
                    if active[cut.channelIndex] == cut.activeEventIndex { active[cut.channelIndex] = nil }
                }
                let indices = byTick[tick] ?? []
                let turns = Dictionary(grouping: indices, by: { original[$0].channelIndex })
                let hasH = indices.contains { if case .hxyGlobalVolumeSlide = original[$0].command { return original[$0].applied }; return false }
                let hasG = indices.contains { if case .gxxSetGlobalVolume = original[$0].command { return original[$0].applied }; return false }
                // Keep G12/H00 target ownership, extending the same held-state
                // contract to G-only generations without creating another global.
                if hasH || (tick == 0 && rowHasH) { affected.formUnion(active.values) }
                if hasG { gxxAffected.formUnion(active.values) }
                for projectionIndex in controls.indices {
                    let rowControl = controls[projectionIndex].snapshot
                    let channel = rowControl.channelIndex
                    var outputVolume = controls[projectionIndex].outputVolume
                    var localVolumePublication = false
                    for ordinal in turns[channel] ?? [] {
                        let update = original[ordinal]
                        switch update.command {
                        case .gxxSetGlobalVolume, .hxyGlobalVolumeSlide:
                            if update.applied, let value = update.globalVolumeAfter { visibleGlobal = value }
                        default:
                            if update.applied, isVolumePublicationWriter(update.command) {
                                if let output = update.effectiveVolumeAfter { outputVolume = output }
                                localVolumePublication = true
                            }
                        }
                        var retained = update
                        if let event = update.activeEventIndex {
                            if affected.contains(event) || gxxAffected.contains(event) {
                                // Keep typed writer/quick-volume intent and pan metadata, but let
                                // the channel-turn snapshot own this frame's scalar gain once.
                                retained.gainBefore = nil; retained.gainAfter = nil
                            } else if let after = update.gainAfter, update.gainBefore != after {
                                heldGains[event] = after
                            }
                        }
                        if row >= firstRow { result.append(retained) }
                    }
                    controls[projectionIndex].outputVolume = outputVolume
                    guard let event = active[channel], affected.contains(event) || gxxAffected.contains(event),
                          hasH || hasG || localVolumePublication || context.events[event].volumeEnvelope != nil || released.contains(event) else { continue }
                    // Materialize full controls only for a published diagnostic, never a plain turn.
                    let state = controls[projectionIndex].targetState(event: event, sampleVolume: sampleVolumes[event])
                    targetStates += 1
                    var target = globalVolumeChannelTarget(source: timing.source, channel: channel, row: row, tick: tick,
                        frame: frame, state: state, globalVolume: visibleGlobal,
                        gxxReason: affected.contains(event) ? nil : hasG ? "global_volume_set" :
                            localVolumePublication ? "local_volume_writer" : "envelope_or_release_tick")
                    target.gainBefore = heldGains[event] ?? context.events[event].gain
                    heldGains[event] = target.gainAfter
                    result.append(target)
                }
            }
            lastControls = controls
        }
        // A forced envelope/release publication at the first tail tick observes the final
        // canonical state. Plain voices retain their held target until another writer.
        if let last = timingPlan.rowTimings.last {
            let row = last.syntheticRow + 1
            // Row projections already have ascending, unique channel identities.
            for projection in lastControls {
                let channel = projection.snapshot.channelIndex
                guard let event = active[channel], affected.contains(event) || gxxAffected.contains(event),
                      context.events[event].volumeEnvelope != nil || released.contains(event) else { continue }
                let state = projection.targetState(event: event, sampleVolume: sampleVolumes[event])
                targetStates += 1
                var target = globalVolumeChannelTarget(source: last.source, channel: channel, row: row, tick: 0,
                    frame: timingPlan.frameFor(row: row), state: state, globalVolume: visibleGlobal,
                    gxxReason: affected.contains(event) ? nil : "envelope_or_release_tick")
                target.gainBefore = heldGains[event] ?? context.events[event].gain
                result.append(target)
            }
        }
        context.voiceStateUpdates = result
    }

    private static func isVolumePublicationWriter(_ command: PlaybackSongSyntheticVoiceStateUpdateCommand) -> Bool {
        switch command {
        case .instrumentDefaultVolume, .cxxSetVolume, .keyOffWithoutEnvelope, .axyVolumeSlide,
             .eaxFineVolumeSlideUp, .ebxFineVolumeSlideDown, .effect5xyVolumeSlide, .effect6xyVolumeSlide, .tremolo:
            return true
        case let .volumeColumn(column):
            switch column {
            case .setVolume, .volumeSlideDown, .volumeSlideUp, .fineVolumeSlideDown, .fineVolumeSlideUp: return true
            default: return false
            }
        default: return false
        }
    }

    private static func globalVolumeChannelTarget(source: PlaybackPosition, channel: Int, row: Int, tick: Int,
        frame: Int, state: ChannelState, globalVolume: Int, gxxReason: String? = nil) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        voiceStateUpdateDiagnostic(source: source, channelIndex: channel, syntheticRow: row, syntheticTick: tick,
            scheduledFrame: frame, cell: PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            commandSource: .effectColumn, command: gxxReason.map { .gxxChannelTarget(globalVolume: globalVolume, reason: $0) } ?? .hxyChannelTarget(globalVolume: globalVolume),
            // Snapshots also refresh at tick zero; their explicit frame owns timing.
            rawVolumeColumn: nil, effectType: nil, effectParam: nil, status: .applied, behavior: nil,
            channelStateBefore: state, channelStateAfter: state, globalVolumeBefore: globalVolume,
            globalVolumeAfter: globalVolume, includeGlobalVolumeFields: true, targetChannelIndex: channel,
            activeVoiceUpdatedOverride: true)
    }

    static func globalVolumeSlidePlan(effectParam: UInt8) -> GlobalVolumeSlidePlan {
        let upNibble = Int((effectParam & 0xF0) >> 4)
        let downNibble = Int(effectParam & 0x0F)
        let bothNibblesNonzero = upNibble > 0 && downNibble > 0
        if upNibble > 0 {
            return GlobalVolumeSlidePlan(
                up: upNibble,
                down: 0,
                direction: .up,
                amount: upNibble,
                bothNibblesNonzero: bothNibblesNonzero,
                policy: bothNibblesNonzero ? "up_nibble_precedence_matches_runtime" : nil
            )
        }
        if downNibble > 0 {
            return GlobalVolumeSlidePlan(
                up: 0,
                down: downNibble,
                direction: .down,
                amount: downNibble,
                bothNibblesNonzero: false,
                policy: nil
            )
        }
        return GlobalVolumeSlidePlan(
            up: 0,
            down: 0,
            direction: .none,
            amount: 0,
            bothNibblesNonzero: false,
            policy: "h00_no_effect_memory_no_op"
        )
    }

    static func volumeSlideAmounts(effectParam: UInt8) -> VolumeSlideAmounts {
        volumeSlideAmounts(
            effectParam: effectParam,
            mixedNibblePolicy: "up_nibble_precedence_current_policy",
            zeroPolicy: "zero_param_effect_memory_deferred"
        )
    }

    static func axyVolumeSlideAmounts(effectParam: UInt8) -> VolumeSlideAmounts {
        volumeSlideAmounts(
            effectParam: effectParam,
            mixedNibblePolicy: "up_nibble_precedence_mikmod_observed",
            zeroPolicy: "a00_no_effect_memory_no_op"
        )
    }

    static func volumeSlideAmounts(
        effectParam: UInt8,
        mixedNibblePolicy: String,
        zeroPolicy: String
    ) -> VolumeSlideAmounts {
        let rawUp = Int((effectParam & 0xF0) >> 4)
        let rawDown = Int(effectParam & 0x0F)
        let bothNibblesNonzero = rawUp > 0 && rawDown > 0
        if rawUp > 0 {
            return VolumeSlideAmounts(
                up: rawUp,
                down: 0,
                direction: "up",
                amount: rawUp,
                rawUpNibble: rawUp,
                rawDownNibble: rawDown,
                bothNibblesNonzero: bothNibblesNonzero,
                policy: bothNibblesNonzero ? mixedNibblePolicy : "single_nonzero_nibble"
            )
        }
        if rawDown > 0 {
            return VolumeSlideAmounts(
                up: 0,
                down: rawDown,
                direction: "down",
                amount: rawDown,
                rawUpNibble: rawUp,
                rawDownNibble: rawDown,
                bothNibblesNonzero: false,
                policy: "single_nonzero_nibble"
            )
        }
        return VolumeSlideAmounts(
            up: 0,
            down: 0,
            direction: "none",
            amount: 0,
            rawUpNibble: rawUp,
            rawDownNibble: rawDown,
            bothNibblesNonzero: false,
            policy: zeroPolicy
        )
    }

    static func voiceStateUpdateDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int = 0,
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
        channelStateAfter: ChannelState,
        globalVolumeBefore: Int,
        globalVolumeAfter: Int,
        includeGlobalVolumeFields: Bool = false,
        targetChannelIndex: Int? = nil,
        globalVolumeSlideDirection: PlaybackSongSyntheticGlobalVolumeSlideDirection? = nil,
        globalVolumeSlideAmount: Int? = nil,
        globalVolumeSlideClamped: Bool? = nil,
        globalVolumeSlideBothNibblesNonzero: Bool? = nil,
        globalVolumeSlidePolicy: String? = nil,
        globalVolumeSlideResolvedParameter: UInt8? = nil,
        volumeSlide: VolumeSlideAmounts? = nil,
        volumeSlideClamped: Bool? = nil,
        volumeSlideTick0Suppressed: Bool? = nil,
        volumeSlideRowSpeed: Int? = nil,
        volumeSlidePolicyOverride: String? = nil,
        effectMemoryReused: Bool = false,
        effectMemoryMissing: Bool = false,
        effectMemoryDeferred: Bool = false,
        memorySource: PlaybackSongSyntheticEffectMemorySource? = nil,
        memoryUnavailableReason: String? = nil,
        activeVoiceUpdatedOverride: Bool? = nil,
        channelPanningValueAfter: Double? = nil
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        let activeSampleVolumeBefore = channelStateBefore.activeSampleVolume
        let activeSampleVolumeAfter = channelStateAfter.activeSampleVolume ?? activeSampleVolumeBefore
        let gainBefore = activeSampleVolumeBefore.map { _ in
            songGain(
                outputChannelVolume: channelStateBefore.outputChannelVolume,
                globalVolume: globalVolumeBefore
            )
        }
        let gainAfter = activeSampleVolumeAfter.map { _ in
            songGain(
                outputChannelVolume: channelStateAfter.outputChannelVolume,
                globalVolume: globalVolumeAfter
            )
        }
        let sameCellTonePortamentoNoRetrigger =
            (1...96).contains(cell.note) &&
            isTonePortamentoEffect(cell) &&
            channelStateBefore.activeEventIndex != nil
        let canUpdateActiveVoice = activeVoiceUpdatedOverride ?? (
            status == .applied &&
                (cell.note == 0 || sameCellTonePortamentoNoRetrigger) &&
                channelStateBefore.activeEventIndex != nil &&
                activeSampleVolumeBefore != nil
        )
        return PlaybackSongSyntheticVoiceStateUpdateDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: syntheticTick,
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
            targetChannelIndex: targetChannelIndex,
            activeVoiceUpdated: canUpdateActiveVoice,
            activeEventIndex: canUpdateActiveVoice ? channelStateBefore.activeEventIndex : nil,
            effectiveVolumeBefore: channelStateBefore.outputChannelVolume,
            effectiveVolumeAfter: channelStateAfter.outputChannelVolume,
            effectivePanBefore: channelStateBefore.pan,
            effectivePanAfter: channelStateAfter.pan,
            globalVolumeBefore: includeGlobalVolumeFields ? globalVolumeBefore : nil,
            globalVolumeAfter: includeGlobalVolumeFields ? globalVolumeAfter : nil,
            globalVolumeMultiplierBefore: includeGlobalVolumeFields ? globalVolumeMultiplier(for: globalVolumeBefore) : nil,
            globalVolumeMultiplierAfter: includeGlobalVolumeFields ? globalVolumeMultiplier(for: globalVolumeAfter) : nil,
            globalVolumeSlideDirection: globalVolumeSlideDirection,
            globalVolumeSlideAmount: globalVolumeSlideAmount,
            globalVolumeSlideClamped: globalVolumeSlideClamped,
            globalVolumeSlideBothNibblesNonzero: globalVolumeSlideBothNibblesNonzero,
            globalVolumeSlidePolicy: globalVolumeSlidePolicy,
            globalVolumeSlideResolvedParameter: globalVolumeSlideResolvedParameter,
            volumeSlideRawUpNibble: volumeSlide?.rawUpNibble,
            volumeSlideRawDownNibble: volumeSlide?.rawDownNibble,
            volumeSlideBothNibblesNonzero: volumeSlide?.bothNibblesNonzero,
            volumeSlidePolicy: volumeSlidePolicyOverride ?? volumeSlide?.policy,
            volumeSlideClamped: volumeSlideClamped,
            volumeSlideTick0Suppressed: volumeSlideTick0Suppressed,
            volumeSlideRowSpeed: volumeSlideRowSpeed,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            effectMemoryDeferred: effectMemoryDeferred,
            memorySource: memorySource,
            memoryUnavailableReason: memoryUnavailableReason,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            panBefore: channelStateBefore.pan,
            panAfter: channelStateAfter.pan,
            channelPanningValueAfter: channelPanningValueAfter
        )
    }

}
