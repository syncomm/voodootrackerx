import Foundation

extension PlaybackSongSyntheticAdapter {
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
        if !activeVoiceFound {
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

    static func applyEffectColumnState(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        channelState: inout ChannelState,
        globalVolumeValue: Int
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? {
        switch cell.effectType {
        case 0x0C:
            let before = channelState
            channelState.volumeValue = clampedVolumeValue(Int(cell.effectParam))
            channelState.volumeValueZeroedByAxy = false
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
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
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
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x06:
            let before = channelState
            let slide = volumeSlideAmounts(effectParam: cell.effectParam)
            guard slide.up > 0 || slide.down > 0 else {
                return voiceStateUpdateDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    commandSource: .effectColumn,
                    command: .effect6xyVolumeSlide(up: 0, down: 0),
                    rawVolumeColumn: nil,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignoredNoOp,
                    behavior: .rowLevelApproximation,
                    channelStateBefore: before,
                    channelStateAfter: before,
                    globalVolumeBefore: globalVolumeValue,
                    globalVolumeAfter: globalVolumeValue
                )
            }
            if slide.up > 0 {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue + slide.up)
            } else {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue - slide.down)
            }
            channelState.volumeValueZeroedByAxy = false
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .effect6xyVolumeSlide(up: slide.up, down: slide.down),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .rowLevelApproximation,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x0E where isFineVolumeSlideEffect(cell):
            let before = channelState
            let amount = fineVolumeSlideAmount(from: cell)
            let isSlideUp = isFineVolumeSlideUpEffect(cell)
            let command: PlaybackSongSyntheticVoiceStateUpdateCommand = isSlideUp
                ? .eaxFineVolumeSlideUp(amount: amount)
                : .ebxFineVolumeSlideDown(amount: amount)
            guard amount > 0 else {
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
                    status: .ignoredNoOp,
                    behavior: .rowLevelApproximation,
                    channelStateBefore: before,
                    channelStateAfter: before,
                    globalVolumeBefore: globalVolumeValue,
                    globalVolumeAfter: globalVolumeValue
                )
            }
            if isSlideUp {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue + amount)
            } else {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue - amount)
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
                globalVolumeAfter: globalVolumeValue
            )
        default:
            return nil
        }
    }

    static func applyEffectColumnVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        globalVolumeValue: Int
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x0A || cell.effectType == 0x05 else {
            return []
        }

        let requestedSlide = axyVolumeSlideAmounts(effectParam: cell.effectParam)
        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let slide: VolumeSlideAmounts
        let memorySource: PlaybackSongSyntheticEffectMemorySource?
        let effectMemoryReused: Bool
        let effectMemoryMissing: Bool
        let effectMemoryDeferred: Bool
        let memoryUnavailableReason: String?

        if requestedSlide.amount > 0 {
            slide = requestedSlide
            channelState.volumeSlideMemory = VolumeSlideMemory(
                slide: requestedSlide,
                source: targetMemorySource
            )
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
            effectMemoryMissing = true
            effectMemoryDeferred = true
            memoryUnavailableReason = volumeSlideMemoryUnavailableReason(for: cell)
        }
        let rowSpeed = max(1, timingConfig.speed)
        let command = volumeSlideCommand(for: cell, up: slide.up, down: slide.down)
        guard slide.amount > 0 else {
            let before = channelState
            return [
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
                    volumeSlidePolicyOverride: zeroVolumeSlidePolicy(for: cell),
                    effectMemoryReused: effectMemoryReused,
                    effectMemoryMissing: effectMemoryMissing,
                    effectMemoryDeferred: effectMemoryDeferred,
                    memorySource: memorySource,
                    memoryUnavailableReason: memoryUnavailableReason,
                    activeVoiceUpdatedOverride: false
                ),
            ]
        }

        guard rowSpeed > 1 else {
            return []
        }

        var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        updates.reserveCapacity(rowSpeed - 1)
        for tick in 1..<rowSpeed {
            let before = channelState
            let unclampedAfter = before.volumeValue + slide.up - slide.down
            channelState.volumeValue = clampedVolumeValue(unclampedAfter)
            channelState.volumeValueZeroedByAxy = channelState.volumeValue == 0
            let clamped = channelState.volumeValue != unclampedAfter
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

    static func applyAxyVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
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
        channelStates: [Int: ChannelState],
        globalVolumeState: inout GlobalVolumeState
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x10 else {
            return []
        }

        let beforeGlobalVolume = globalVolumeState.volumeValue
        let afterGlobalVolume = clampedGlobalVolumeValue(Int(cell.effectParam))
        globalVolumeState.volumeValue = afterGlobalVolume
        let diagnostics = channelStates.keys.sorted().compactMap { targetChannelIndex -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? in
            guard let targetState = channelStates[targetChannelIndex],
                  targetState.activeEventIndex != nil,
                  targetState.activeSampleVolume != nil else {
                return nil
            }
            let gainBefore = targetState.activeSampleVolume.map {
                adaptedGain(
                    sampleVolume: $0,
                    channelVolume: targetState.volumeValue,
                    globalVolume: beforeGlobalVolume
                )
            }
            let gainAfter = targetState.activeSampleVolume.map {
                adaptedGain(
                    sampleVolume: $0,
                    channelVolume: targetState.volumeValue,
                    globalVolume: afterGlobalVolume
                )
            }
            guard gainBefore != gainAfter else {
                return nil
            }
            return globalVolumeSetDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: targetChannelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                channelState: targetState,
                globalVolumeBefore: beforeGlobalVolume,
                globalVolumeAfter: afterGlobalVolume,
                activeVoiceUpdatedOverride: true
            )
        }
        if !diagnostics.isEmpty {
            return diagnostics
        }

        return [
            globalVolumeSetDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: nil,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                channelState: channelStates[sourceChannelIndex] ?? ChannelState(),
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
        scheduledFrame: Int,
        channelStates: [Int: ChannelState],
        globalVolumeState: inout GlobalVolumeState
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x11 else {
            return []
        }

        let beforeGlobalVolume = globalVolumeState.volumeValue
        let slide = globalVolumeSlidePlan(effectParam: cell.effectParam)
        guard slide.amount > 0 else {
            return [
                globalVolumeSlideDiagnostic(
                    source: source,
                    sourceChannelIndex: sourceChannelIndex,
                    targetChannelIndex: nil,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    status: .ignoredNoOp,
                    slide: slide,
                    channelState: channelStates[sourceChannelIndex] ?? ChannelState(),
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
        let diagnostics = channelStates.keys.sorted().compactMap { targetChannelIndex -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? in
            guard let targetState = channelStates[targetChannelIndex],
                  targetState.activeEventIndex != nil,
                  targetState.activeSampleVolume != nil else {
                return nil
            }
            let gainBefore = targetState.activeSampleVolume.map {
                adaptedGain(
                    sampleVolume: $0,
                    channelVolume: targetState.volumeValue,
                    globalVolume: beforeGlobalVolume
                )
            }
            let gainAfter = targetState.activeSampleVolume.map {
                adaptedGain(
                    sampleVolume: $0,
                    channelVolume: targetState.volumeValue,
                    globalVolume: afterGlobalVolume
                )
            }
            let changed = gainBefore != gainAfter
            guard changed else {
                return nil
            }
            return globalVolumeSlideDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: targetChannelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                slide: slide,
                channelState: targetState,
                globalVolumeBefore: beforeGlobalVolume,
                globalVolumeAfter: afterGlobalVolume,
                clamped: clamped,
                activeVoiceUpdatedOverride: true
            )
        }
        if !diagnostics.isEmpty {
            return diagnostics
        }

        return [
            globalVolumeSlideDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: nil,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                slide: slide,
                channelState: channelStates[sourceChannelIndex] ?? ChannelState(),
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
            scheduledFrame: scheduledFrame,
            cell: cell,
            commandSource: .effectColumn,
            command: .hxyGlobalVolumeSlide(up: slide.up, down: slide.down),
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
            globalVolumeSlideDirection: slide.direction,
            globalVolumeSlideAmount: slide.amount,
            globalVolumeSlideClamped: clamped,
            globalVolumeSlideBothNibblesNonzero: slide.bothNibblesNonzero,
            globalVolumeSlidePolicy: slide.policy,
            activeVoiceUpdatedOverride: activeVoiceUpdatedOverride
        )
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
        activeVoiceUpdatedOverride: Bool? = nil
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        let activeSampleVolumeBefore = channelStateBefore.activeSampleVolume
        let activeSampleVolumeAfter = channelStateAfter.activeSampleVolume ?? activeSampleVolumeBefore
        let gainBefore = activeSampleVolumeBefore.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: channelStateBefore.volumeValue,
                globalVolume: globalVolumeBefore
            )
        }
        let gainAfter = activeSampleVolumeAfter.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: channelStateAfter.volumeValue,
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
            effectiveVolumeBefore: channelStateBefore.volumeValue,
            effectiveVolumeAfter: channelStateAfter.volumeValue,
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
            panAfter: channelStateAfter.pan
        )
    }

}
