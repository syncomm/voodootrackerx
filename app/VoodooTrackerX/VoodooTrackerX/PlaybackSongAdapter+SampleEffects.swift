import Foundation

extension PlaybackSongSyntheticAdapter {
    struct RetriggerVolumeAdjustment: Equatable {
        let modeNibble: Int
        let volumeBefore: Int
        let volumeAfter: Int
        let changed: Bool
    }

    static let rxyVolumeChangePolicy = "xm_common_multi_retrigger_volume_table_first_pass"

    static func handleKeyOff(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int,
        scheduledFrame: Int,
        rowSpeed: Int,
        rowBPM: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        cell: PlaybackCell,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField],
        eventCoverage: inout EventCoverageBuilder,
        effectType: UInt8? = nil,
        effectParam: UInt8? = nil
    ) {
        let activeEventIndexBefore = channelState.activeEventIndex
        guard let activeEventIndex = channelState.activeEventIndex,
              let activeEventMappingIndex = channelState.activeEventMappingIndex,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeEventMappingIndex),
              scheduledFrame >= (events[activeEventIndex].scheduledStartFrame ?? 0) else {
            keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: syntheticTick,
                effectType: effectType,
                effectParam: effectParam,
                detected: true,
                releaseFrame: nil,
                scheduledFrame: scheduledFrame,
                applied: false,
                deferred: true,
                reason: .noActiveVoice,
                requestedTick: syntheticTick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                activeVoiceFound: activeEventIndexBefore != nil,
                activeVoiceReleased: false,
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
            scheduledFrame,
            fadeoutFrameDecrement: fadeoutDecrement
        )
        eventMappings[activeEventMappingIndex] = eventMapping(
            previousMapping,
            applying: previousMapping.volumeEnvelopeSemantics.applyingKeyOff(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: syntheticTick,
                releaseFrame: scheduledFrame
            )
        )
        keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: syntheticTick,
            effectType: effectType,
            effectParam: effectParam,
            detected: true,
            releaseFrame: scheduledFrame,
            scheduledFrame: scheduledFrame,
            applied: true,
            deferred: false,
            reason: .releasedActiveVoice,
            requestedTick: syntheticTick,
            rowSpeed: rowSpeed,
            rowBPM: rowBPM,
            activeVoiceFound: true,
            activeVoiceReleased: true,
            activeEventIndex: activeEventIndex
        ))
        if hasDeferredEffect(cell) || volumeColumn.deferred {
            eventCoverage.recordDeferredCellWithoutSkip()
        }
        clearActiveVoiceState(&channelState)
    }

    static func handleKxxKeyOff(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField],
        eventCoverage: inout EventCoverageBuilder
    ) {
        guard isKxxKeyOffEffect(cell) else {
            return
        }
        let requestedTick = Int(cell.effectParam)
        guard requestedTick < timingConfig.speed else {
            keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: requestedTick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                detected: true,
                releaseFrame: nil,
                scheduledFrame: nil,
                applied: false,
                deferred: false,
                reason: .outOfRowNoOp,
                requestedTick: requestedTick,
                rowSpeed: timingConfig.speed,
                rowBPM: timingConfig.bpm,
                activeVoiceFound: channelState.activeEventIndex != nil,
                activeVoiceReleased: false,
                activeEventIndex: channelState.activeEventIndex
            ))
            return
        }
        let keyOffFrame = timingPlan.frameFor(row: syntheticRow, tick: requestedTick)
        handleKeyOff(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: requestedTick,
            scheduledFrame: keyOffFrame,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            volumeColumn: volumeColumn,
            cell: cell,
            channelState: &channelState,
            events: &events,
            keyOffEvents: &keyOffEvents,
            eventMappings: &eventMappings,
            ignoredCells: &ignoredCells,
            deferredCellFields: &deferredCellFields,
            eventCoverage: &eventCoverage,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
    }

    @discardableResult
    static func handleRetrigger(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        globalVolumeState: GlobalVolumeState,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        retriggerEffects: inout [PlaybackSongSyntheticRetriggerDiagnostic],
        eventCoverage: inout EventCoverageBuilder
    ) -> PlaybackSongSyntheticRetriggerDiagnostic? {
        guard isRetriggerEffect(cell) else {
            return nil
        }

        let interval = retriggerIntervalNibble(from: cell)
        let volumeModeNibble = retriggerVolumeModeNibble(from: cell)
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
            replacedEventIndices: [Int] = [],
            volumeValuesBefore: [Int] = [],
            volumeValuesAfter: [Int] = [],
            retriggerGains: [Float] = []
        ) -> PlaybackSongSyntheticRetriggerDiagnostic {
            let applied = status == .applied
            let deferred = status == .ignoredE90NoEffectMemory ||
                status == .ignoredRxyZeroIntervalNoEffectMemory
            let ignoredAsNoOp = status == .ignoredE90NoEffectMemory ||
                status == .ignoredRxyZeroIntervalNoEffectMemory ||
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
                volumeModeNibble: volumeModeNibble,
                intervalNibble: interval,
                volumeChangePolicy: isRxyMultiRetriggerEffect(cell) ? Self.rxyVolumeChangePolicy : nil,
                volumeChangeCount: zip(volumeValuesBefore, volumeValuesAfter).filter { $0.0 != $0.1 }.count,
                volumeValuesBefore: volumeValuesBefore,
                volumeValuesAfter: volumeValuesAfter,
                retriggerGains: retriggerGains,
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
            let result = diagnostic(
                status: isRxyMultiRetriggerEffect(cell) ? .ignoredRxyZeroIntervalNoEffectMemory : .ignoredE90NoEffectMemory
            )
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
        let pan = channelState.pan
        var currentVolumeValue = channelState.volumeValue
        var ticks = [Int]()
        var frames = [Int]()
        var eventIndices = [Int]()
        var replacedEventIndices = [Int]()
        var volumeValuesBefore = [Int]()
        var volumeValuesAfter = [Int]()
        var retriggerGains = [Float]()
        var previousEventIndex = activeEventIndex

        var tick = interval
        while tick < rowSpeed {
            let frame = timingPlan.frameFor(row: syntheticRow, tick: tick)
            let volumeBefore = currentVolumeValue
            if isRxyMultiRetriggerEffect(cell) {
                currentVolumeValue = retriggerVolumeAdjustment(
                    modeNibble: volumeModeNibble,
                    currentVolume: currentVolumeValue
                ).volumeAfter
            }
            let gain = adaptedGain(
                sampleVolume: activeSampleVolume,
                channelVolume: currentVolumeValue,
                globalVolume: globalVolumeState.volumeValue
            )
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
                effectiveVolumeValue: currentVolumeValue,
                effectiveGlobalVolumeValue: globalVolumeState.volumeValue,
                effectiveGlobalVolumeMultiplier: globalVolumeState.multiplier,
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
            volumeValuesBefore.append(volumeBefore)
            volumeValuesAfter.append(currentVolumeValue)
            retriggerGains.append(gain)
            previousEventIndex = eventIndex
            tick += interval
        }

        channelState.activeEventIndex = previousEventIndex
        channelState.activeEventMappingIndex = eventMappings.count - 1
        channelState.activeSampleVolume = activeSampleVolume
        channelState.volumeValue = currentVolumeValue
        channelState.volumeValueZeroedByAxy = currentVolumeValue == 0

        let result = diagnostic(
            status: .applied,
            ticks: ticks,
            frames: frames,
            eventIndices: eventIndices,
            replacedEventIndices: replacedEventIndices,
            volumeValuesBefore: volumeValuesBefore,
            volumeValuesAfter: volumeValuesAfter,
            retriggerGains: retriggerGains
        )
        retriggerEffects.append(result)
        return result
    }

    static func retriggerVolumeAdjustment(
        modeNibble: Int,
        currentVolume: Int
    ) -> RetriggerVolumeAdjustment {
        let mode = min(15, max(0, modeNibble))
        let before = clampedVolumeValue(currentVolume)
        let unclampedAfter: Int
        switch mode {
        case 1:
            unclampedAfter = before - 1
        case 2:
            unclampedAfter = before - 2
        case 3:
            unclampedAfter = before - 4
        case 4:
            unclampedAfter = before - 8
        case 5:
            unclampedAfter = before - 16
        case 6:
            unclampedAfter = (before * 2) / 3
        case 7:
            unclampedAfter = before / 2
        case 9:
            unclampedAfter = before + 1
        case 10:
            unclampedAfter = before + 2
        case 11:
            unclampedAfter = before + 4
        case 12:
            unclampedAfter = before + 8
        case 13:
            unclampedAfter = before + 16
        case 14:
            unclampedAfter = (before * 3) / 2
        case 15:
            unclampedAfter = before * 2
        default:
            unclampedAfter = before
        }
        let after = clampedVolumeValue(unclampedAfter)
        return RetriggerVolumeAdjustment(
            modeNibble: mode,
            volumeBefore: before,
            volumeAfter: after,
            changed: before != after
        )
    }

    static func handleNoteCut(
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
        clearActiveVoiceState(&channelState)
    }

    static func noteCutDiagnostic(
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

    static func noteDelayDiagnostic(
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

}
