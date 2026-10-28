import Foundation

extension PlaybackSongSyntheticAdapter {
    struct RetriggerVolumeAdjustment: Equatable {
        let modeNibble: Int
        let volumeBefore: Int
        let volumeAfter: Int
        let changed: Bool
    }

    static let rxyVolumeChangePolicy = "ft2_exact_integer_multi_retrigger_volume"

    /// One bounded, immutable decision at the release frame; no earlier objects are mutated here.
    struct CausalReleaseResult: Equatable {
        struct SourceAnnotation: Equatable {
            let eventIndex: Int
            let mappingIndex: Int
            let releaseFrame: Int
            let fadeoutFrameDecrement: Float
            let volumeEnvelopeSemantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
            let zeroOnsetGain: Bool
            let volumeUpdate: PlaybackSongSyntheticVoiceStateUpdateDiagnostic?
        }

        let diagnostic: PlaybackSongSyntheticKeyOffDiagnostic
        let channelVolumeAfter: Int?
        let sourceAnnotation: SourceAnnotation?
    }

    /// Decides release ownership, fadeout and output-volume effects once from current planning state.
    static func decideKeyOff(
        source: PlaybackPosition, channelIndex: Int, syntheticRow: Int, syntheticTick: Int,
        scheduledFrame: Int, rowSpeed: Int, rowBPM: Int, cell: PlaybackCell,
        channelState: ChannelState, events: [SyntheticTrackerEvent], eventMappings: [PlaybackSongSyntheticEventMapping],
        globalVolume: Int, effectType: UInt8? = nil, effectParam: UInt8? = nil,
        instrumentOnlyVolumeRestored: Bool = false
    ) -> CausalReleaseResult {
        let activeEventIndexBefore = channelState.activeEventIndex
        func diagnostic(_ reason: PlaybackSongSyntheticKeyOffDiagnostic.Reason,
                        applied: Bool, eventIndex: Int?) -> PlaybackSongSyntheticKeyOffDiagnostic {
            .init(source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, syntheticTick: syntheticTick,
                effectType: effectType, effectParam: effectParam, detected: true,
                releaseFrame: applied ? scheduledFrame : nil, scheduledFrame: scheduledFrame,
                applied: applied, deferred: !applied, reason: reason, requestedTick: syntheticTick,
                rowSpeed: rowSpeed, rowBPM: rowBPM, activeVoiceFound: activeEventIndexBefore != nil,
                activeVoiceReleased: eventIndex != nil, activeEventIndex: eventIndex)
        }
        if activeEventIndexBefore == nil, (channelState.semanticInstrumentIndex != nil || channelState.carriedInstrumentIndex != nil) {
            let zeroVolume = !channelState.semanticVolumeEnvelopeEnabled && !instrumentOnlyVolumeRestored
            return .init(diagnostic: diagnostic(.releasedSilentChannel, applied: true, eventIndex: nil),
                channelVolumeAfter: zeroVolume ? 0 : nil, sourceAnnotation: nil)
        }
        guard let activeEventIndex = channelState.activeEventIndex,
              let activeEventMappingIndex = channelState.activeEventMappingIndex,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeEventMappingIndex),
              scheduledFrame >= (events[activeEventIndex].scheduledStartFrame ?? 0) else {
            return .init(diagnostic: diagnostic(.noActiveVoice, applied: false, eventIndex: nil),
                channelVolumeAfter: nil, sourceAnnotation: nil)
        }

        let event = events[activeEventIndex]
        let mapping = eventMappings[activeEventMappingIndex]
        let decrement = fadeoutFrameDecrement(
            fadeoutValue: mapping.volumeEnvelopeSemantics.fadeoutValue, sampleRate: mapping.outputSampleRate)
        // An admitted release-row restoration overwrites the transient zero before publication.
        let zeroVolume = event.volumeEnvelope == nil && !instrumentOnlyVolumeRestored
        var volumeUpdate: PlaybackSongSyntheticVoiceStateUpdateDiagnostic?
        if zeroVolume {
            var after = channelState
            after.baseChannelVolume = 0
            volumeUpdate = voiceStateUpdateDiagnostic(source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, syntheticTick: syntheticTick, scheduledFrame: scheduledFrame, cell: cell,
                commandSource: .effectColumn, command: .keyOffWithoutEnvelope, rawVolumeColumn: nil,
                effectType: effectType, effectParam: effectParam, status: .applied, behavior: nil,
                channelStateBefore: channelState, channelStateAfter: after,
                globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume,
                activeVoiceUpdatedOverride: event.scheduledStartFrame != scheduledFrame)
        }
        return .init(diagnostic: diagnostic(.releasedActiveVoice, applied: true, eventIndex: activeEventIndex),
            channelVolumeAfter: zeroVolume ? 0 : nil,
            sourceAnnotation: .init(eventIndex: activeEventIndex, mappingIndex: activeEventMappingIndex,
                releaseFrame: scheduledFrame, fadeoutFrameDecrement: decrement,
                volumeEnvelopeSemantics: mapping.volumeEnvelopeSemantics.applyingKeyOff(
                    source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                    syntheticTick: syntheticTick, releaseFrame: scheduledFrame),
                zeroOnsetGain: zeroVolume && event.scheduledStartFrame == scheduledFrame, volumeUpdate: volumeUpdate))
    }

    /// Copies decided values: first trigger release, latest mapping annotation, ordered diagnostics.
    static func applyLegacyReleaseProjection(
        _ result: CausalReleaseResult, events: inout [SyntheticTrackerEvent],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        voiceStateUpdates: inout [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    ) {
        if let annotation = result.sourceAnnotation {
            if events[annotation.eventIndex].keyOffFrame == nil {
                events[annotation.eventIndex] = events[annotation.eventIndex].withKeyOffFrame(
                    annotation.releaseFrame, fadeoutFrameDecrement: annotation.fadeoutFrameDecrement)
            }
            if annotation.zeroOnsetGain {
                // Runtime controls precede triggers at a shared frame; the decided onset must carry zero gain.
                events[annotation.eventIndex] = events[annotation.eventIndex].withGainPan(gain: 0)
            }
            if let update = annotation.volumeUpdate { voiceStateUpdates.append(update) }
            eventMappings[annotation.mappingIndex] = eventMapping(eventMappings[annotation.mappingIndex],
                applying: annotation.volumeEnvelopeSemantics)
        }
        // Existing assembly selects the first associated diagnostic for onset categories/Kxx bytes.
        keyOffEvents.append(result.diagnostic)
        // E9 continues to copy this mapping at creation time, even when its new trigger has no release.
    }

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
        voiceStateUpdates: inout [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        globalVolume: Int,
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField],
        eventCoverage: inout EventCoverageBuilder,
        effectType: UInt8? = nil,
        effectParam: UInt8? = nil,
        instrumentOnlyVolumeRestored: Bool = false
    ) {
        let result = decideKeyOff(
            source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, syntheticTick: syntheticTick,
            scheduledFrame: scheduledFrame, rowSpeed: rowSpeed, rowBPM: rowBPM, cell: cell,
            channelState: channelState, events: events, eventMappings: eventMappings, globalVolume: globalVolume,
            effectType: effectType, effectParam: effectParam, instrumentOnlyVolumeRestored: instrumentOnlyVolumeRestored)
        if channelState.activeEventIndex == nil && result.diagnostic.applied { channelState.keyOffWithoutVoice = true }
        if let volume = result.channelVolumeAfter {
            channelState.baseChannelVolume = volume
        }
        applyLegacyReleaseProjection(result, events: &events, eventMappings: &eventMappings,
            keyOffEvents: &keyOffEvents, voiceStateUpdates: &voiceStateUpdates)
        if result.diagnostic.reason == .noActiveVoice {
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
        } else if result.diagnostic.reason == .releasedActiveVoice && (hasDeferredEffect(cell) || volumeColumn.deferred) {
            eventCoverage.recordDeferredCellWithoutSkip()
        }
        // Release does not end source lifetime. Later volume commands still address this generation.
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
        context: inout AdapterRowContext
    ) {
        guard isKxxKeyOffEffect(cell) else {
            return
        }
        let requestedTick = Int(cell.effectParam & 31)
        guard (cell.effectParam == 0 || requestedTick > 0), requestedTick < timingConfig.speed else {
            context.keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
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
                reason: cell.effectParam != 0 && requestedTick == 0 ? .maskedZeroNoOp : .outOfRowNoOp,
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
            events: &context.events,
            keyOffEvents: &context.keyOffEvents,
            voiceStateUpdates: &context.voiceStateUpdates,
            globalVolume: context.globalVolumeState.volumeValue,
            eventMappings: &context.eventMappings,
            ignoredCells: &context.ignoredCells,
            deferredCellFields: &context.deferredCellFields,
            eventCoverage: &context.eventCoverage,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            instrumentOnlyVolumeRestored: false
        )
    }

    /// Reports the row-entry trigger already resolved through ordinary note routing.
    static func e90Diagnostic(cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, timingConfig: SyntheticTrackerTimingConfig, previousEventIndex: Int?,
        firstRowEvent: Int, context: AdapterRowContext) -> PlaybackSongSyntheticRetriggerDiagnostic {
        let mapping = context.eventMappings.last.flatMap {
            $0.eventIndex >= firstRowEvent && $0.channelIndex == channelIndex ? $0 : nil
        }
        let event = mapping.map { context.events[$0.eventIndex] }
        let applied = event != nil
        return .init(source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, syntheticTick: 0,
            effectType: cell.effectType, effectParam: cell.effectParam,
            status: applied ? .applied : (cell.note == 97 ? .e90NoteOff : .e90NoRoute),
            detected: true, applied: applied, deferred: false, ignoredAsNoOp: !applied, outOfRow: false,
            activeVoiceFound: previousEventIndex != nil, retriggerIntervalTicks: 0,
            rowSpeed: timingConfig.speed, rowBPM: timingConfig.bpm,
            retriggerTicks: applied ? [0] : [], retriggerFrames: event.flatMap { $0.scheduledStartFrame }.map { [$0] } ?? [],
            retriggerEventIndices: mapping.map { [$0.eventIndex] } ?? [],
            // These indices authorize legacy interval cuts. E90 uses ordinary
            // same-channel replacement retirement, with the parent reported above.
            replacedEventIndices: [],
            volumeModeNibble: 0, intervalNibble: 0, volumeChangePolicy: nil, volumeChangeCount: 0,
            volumeValuesBefore: [], volumeValuesAfter: [], retriggerGains: event.map { [$0.gain] } ?? [],
            activeEventIndexBefore: previousEventIndex, selectedSampleIndex: mapping?.sampleIndex,
            selectedSampleLength: mapping?.selectedSampleLength, initialSourceFrame: event?.initialSourceFrame,
            playbackStep: event?.playbackStep, gain: event?.gain, pan: event?.pan,
            envelopePolicy: cell.instrument == 0 ? "row_entry_carries_channel_state" : "row_entry_resets_instrument")
    }

    /// FT2 gates tick zero with the byte left by its volume-column routine.
    static func rxyTickZeroGated(_ raw: UInt8, state: ChannelState) -> Bool {
        switch raw >> 4 {
        case 1...5: return raw != 0x10
        case 8, 9: return state.baseChannelVolume != 0
        case 10: return raw & 15 != 0
        case 12: return raw & 15 != 0
        default: return raw != 0
        }
    }

    /// Runs one invocation after the ordinary row/column semantics, without an instrument reset.
    static func handleRxyTick(cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, tick: Int, song: PlaybackSong, timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan, state: inout ChannelState,
        context: inout AdapterRowContext, diagnosticIndex: Int? = nil) {
        let index: Int
        if let diagnosticIndex { index = diagnosticIndex } else {
            index = context.retriggerEffects.count
            let parent = state.activeEventMappingIndex.map { context.eventMappings[$0] }
            context.retriggerEffects.append(.init(source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, syntheticTick: 0, effectType: cell.effectType, effectParam: cell.effectParam,
                status: .counterPending, detected: true, applied: false, deferred: false,
                ignoredAsNoOp: false, outOfRow: false, activeVoiceFound: state.activeEventIndex != nil,
                retriggerIntervalTicks: Int(state.rRetriggerSpeedMemory), rowSpeed: timingConfig.speed, rowBPM: timingConfig.bpm,
                retriggerTicks: [], retriggerFrames: [], retriggerEventIndices: [], replacedEventIndices: [],
                volumeModeNibble: Int(state.rVolumeModeMemory), intervalNibble: Int(cell.effectParam & 15),
                volumeChangePolicy: rxyVolumeChangePolicy, volumeChangeCount: 0, volumeValuesBefore: [],
                volumeValuesAfter: [], retriggerGains: [], activeEventIndexBefore: state.activeEventIndex,
                selectedSampleIndex: parent?.sampleIndex, selectedSampleLength: parent?.selectedSampleLength,
                initialSourceFrame: 0, playbackStep: state.activePlaybackStep, gain: nil, pan: state.pan,
                envelopePolicy: "sample_restart_carries_channel_state", replacementFrames: []))
        }
        let frame = timingPlan.frameFor(row: syntheticRow, tick: tick)
        let counterBefore = state.rRetriggerCounter
        let volumeBefore = state.baseChannelVolume
        let outputBefore = state.outputChannelVolume
        let panningBefore = state.panningValue
        let previous = state.activeEventIndex
        let gated = tick == 0 && rxyTickZeroGated(cell.volumeColumn, state: state)
        let initialized = state.carriedInstrumentIndex != nil || state.semanticInstrumentIndex != nil || state.carriedNote != 0
        var fired = false, restarted = false, coalesced = false
        if !gated {
            state.rRetriggerCounter += 1
            fired = state.rRetriggerCounter >= state.rRetriggerSpeedMemory
            if fired {
                state.rRetriggerCounter = 0
                // Only the manager-approved fully uninitialized mutation is excluded.
                // Instrument-only, empty, completed and released state remain eligible.
                if initialized {
                    state.baseChannelVolume = retriggerVolumeAdjustment(modeNibble: Int(state.rVolumeModeMemory),
                        currentVolume: state.baseChannelVolume).volumeAfter
                    if (0x10...0x50).contains(cell.volumeColumn) { state.baseChannelVolume = Int(cell.volumeColumn - 16) }
                    if (0xC0...0xCF).contains(cell.volumeColumn) { state.applyChannelPanningValue(Double(cell.volumeColumn & 15) * 16) }
                    (restarted, coalesced) = restartRetainedSource(cell: cell, source: source, channelIndex: channelIndex,
                        syntheticRow: syntheticRow, tick: tick, frame: frame, song: song,
                        timingConfig: timingConfig, state: &state, context: &context)
                }
            }
        }
        let arithmetic = fired && initialized
        let excluded = fired && !initialized && state.rVolumeModeMemory != 0 && state.rVolumeModeMemory != 8
        var diagnostic = context.retriggerEffects[index]
        diagnostic.invocations.append(.init(tick: tick, frame: frame, counterBefore: counterBefore,
            counterAfter: state.rRetriggerCounter, gated: gated, fired: fired, arithmeticApplied: arithmetic,
            restartAttempted: arithmetic, restartApplied: restarted, coalescedWithRowTrigger: coalesced,
            semanticOnlyVolumeChange: arithmetic && !restarted && volumeBefore != state.baseChannelVolume,
            uninitializedMutationExcluded: excluded, eventIndexBefore: previous,
            eventIndexAfter: restarted ? state.activeEventIndex : nil,
            instrumentIndex: state.carriedInstrumentIndex, sampleIndex: state.activeSampleIndex,
            volumeBefore: volumeBefore, volumeAfter: state.baseChannelVolume,
            outputVolumeBefore: outputBefore, outputVolumeAfter: state.outputChannelVolume,
            panningBefore: panningBefore, panningAfter: state.panningValue))
        if arithmetic {
            diagnostic.volumeValuesBefore.append(volumeBefore)
            diagnostic.volumeValuesAfter.append(state.baseChannelVolume)
            if volumeBefore != state.baseChannelVolume { diagnostic.volumeChangeCount += 1 }
        }
        if restarted, let event = state.activeEventIndex {
            diagnostic.retriggerTicks.append(tick); diagnostic.retriggerFrames.append(frame)
            diagnostic.retriggerEventIndices.append(event); diagnostic.retriggerGains.append(context.events[event].gain)
            if let previous, !coalesced {
                diagnostic.replacedEventIndices.append(previous); diagnostic.replacementFrames?.append(frame)
            }
        }
        diagnostic.applied = diagnostic.applied || arithmetic || restarted
        diagnostic.status = diagnostic.applied ? .applied : excluded ? .uninitializedRxyExcluded : gated ? .invocationGated : .counterPending
        diagnostic.ignoredAsNoOp = diagnostic.status == .uninitializedRxyExcluded
        context.retriggerEffects[index] = diagnostic
    }

    /// Classifies only ordinary explicit ED destinations with an exact map and a declared empty header.
    static func ordinaryDelayedEmptyHeader(cell: PlaybackCell, song: PlaybackSong) -> XMSourceSampleSlotProvenance? {
        guard (1...96).contains(cell.note), cell.instrument > 0,
              cell.effectType == 14, cell.effectParam >> 4 == 13, cell.volumeColumn >> 4 != 15,
              let instrument = song.instrumentsByIndex[Int(cell.instrument)], instrument.noteSampleMap?.count == 96 else { return nil }
        let selection = selectSample(forNote: cell.note, from: instrument, missingKeymapPolicy: .fail)
        guard selection.sample == nil, let slot = selection.mappedSampleIndex,
              let header = song.xmSampleSlotProvenanceByInstrument[Int(cell.instrument)]?.first(where: {
                  $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
              }), ordinaryPitchAdmission(note: cell.note, relativeNote: header.relativeNote) != .refused else { return nil }
        return header
    }

    /// Uses the existing generation cut and immutable header authority at the ordinary dispatch frame.
    static func dispatchOrdinaryEmptyHeader(_ header: XMSourceSampleSlotProvenance, cell: PlaybackCell,
        source: PlaybackPosition, syntheticRow: Int, channelIndex: Int, frame: Int, tick: Int = 0,
        selection: SampleSelection, song: PlaybackSong,
        timingConfig: SyntheticTrackerTimingConfig, state: inout ChannelState,
        context: inout AdapterRowContext) -> PlaybackStepMapping {
        context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
            scheduledFrame: frame, instrumentIndex: Int(cell.instrument), sampleIndex: header.sampleIndex,
            stoppedEventIndex: state.activeEventIndex, tick: tick))
        state.carriedNote = cell.note
        let pitch = selectEmptyHeader(header, cell: cell, instrumentIndex: Int(cell.instrument),
            song: song, timingConfig: timingConfig, state: &state)
        captureSelection(source: source, row: syntheticRow, tick: tick, channel: channelIndex,
            frame: frame, role: .emptySelection, linear: song.usesLinearFrequencyTable,
            tuning: .declaredEmptyHeader, finetuneCommand: cell.effectType == 14 && cell.effectParam >> 4 == 5,
            routedInstrument: Int(cell.instrument), selection: selection, state: state, context: &context)
        return pitch
    }

    /// Resolves the retained note through the selected instrument's exact route; cursor restarts at zero.
    static func restartRetainedSource(cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, tick: Int, frame: Int, song: PlaybackSong, timingConfig: SyntheticTrackerTimingConfig,
        resetsInstrument: Bool = false, state: inout ChannelState, context: inout AdapterRowContext,
        didResetEffectPhases: ((PlaybackSongRowEntryTriggerResetFacts.Scalars,
            PlaybackSongRowEntryTriggerResetFacts.Scalars) -> Void)? = nil) -> (Bool, Bool) {
        guard (1...96).contains(state.carriedNote), let instrumentIndex = state.carriedInstrumentIndex,
              let instrument = song.instrumentsByIndex[instrumentIndex] else { return (false, false) }
        let selection = selectSample(forNote: state.carriedNote, from: instrument, missingKeymapPolicy: .fail)
        guard let sample = selection.sample else {
            var selectedHeader = false
            context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                scheduledFrame: frame, instrumentIndex: instrumentIndex, sampleIndex: selection.mappedSampleIndex,
                stoppedEventIndex: state.activeEventIndex, preservesChannelState: !resetsInstrument,
                tick: resetsInstrument ? tick : 0))
            if let header = song.xmSampleSlotProvenanceByInstrument[instrumentIndex]?.first(where: {
                $0.sampleIndex == selection.mappedSampleIndex && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
            }) {
                _ = selectEmptyHeader(header, cell: .init(note: state.carriedNote, instrument: 0,
                    volumeColumn: 0, effectType: cell.effectType, effectParam: cell.effectParam), instrumentIndex: instrumentIndex,
                    initializesDefaults: false, song: song, timingConfig: timingConfig, state: &state)
                selectedHeader = true
            } else {
                clearSourceAssociation(&state)
                if resetsInstrument {
                    // An unavailable route has no header to synthesize. FT2 clears
                    // channel defaults through its empty-instrument dispatch.
                    state.triggeredSampleDefaultVolume = 0
                    state.triggeredSampleDefaultPan = 0
                }
            }
            state.semanticInstrumentIndex = instrumentIndex
            state.semanticSampleIndex = selection.mappedSampleIndex
            if resetsInstrument {
                state.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
                applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope,
                    timingConfig: timingConfig), to: &state)
                resetDelayedInstrument(cell: cell, state: &state, didResetEffectPhases: didResetEffectPhases)
            }
            captureSelection(source: source, row: syntheticRow, tick: tick, channel: channelIndex,
                frame: frame, role: selectedHeader ? .emptySelection : .unavailableRoute, linear: song.usesLinearFrequencyTable,
                noteOnly: cell.instrument == 0, tuning: selectedHeader ? .declaredEmptyHeader : nil, routedInstrument: instrumentIndex,
                selection: selection, state: state, context: &context)
            return (false, false)
        }
        if resetsInstrument {
            state.triggeredSampleDefaultVolume = sampleVolumeRawEstimate(for: sample.volume)
            state.triggeredSampleDefaultPan = sample.panning
            resetDelayedInstrument(cell: cell, state: &state, didResetEffectPhases: didResetEffectPhases)
        }
        let pitch = playbackStepMapping(note: state.carriedNote, sample: sample,
            usesLinearFrequencyTable: song.usesLinearFrequencyTable, timingConfig: timingConfig)
        let envelope = mixerVolumeEnvelope(from: instrument.volumeEnvelope, timingConfig: timingConfig)
        let gain = songGain(outputChannelVolume: state.outputChannelVolume, globalVolume: context.globalVolumeState.volumeValue)
        let existing = state.activeEventIndex.flatMap { context.events[$0].scheduledStartFrame == frame ? $0 : nil }
        let eventIndex = existing ?? context.events.count
        let event = SyntheticTrackerEvent(row: syntheticRow, tick: tick, scheduledStartFrame: frame,
            sample: mixerSampleBuffer(for: sample, cache: &context.mixerSampleBuffers), gain: gain, pan: state.pan,
            playbackStep: pitch.playbackStep, loop: mixerLoop(from: sample), initialSourceFrame: 0,
            volumeEnvelope: envelope.envelope,
            panEnvelope: inertPanningEnvelopeClock(from: instrument.panningEnvelope, timingConfig: timingConfig))
        let mapping = PlaybackSongSyntheticEventMapping(source: source, channelIndex: channelIndex,
            note: state.carriedNote, instrumentIndex: instrumentIndex, sampleIndex: sample.sampleIndex,
            sampleVolume: sample.volume, sampleVolumeRawEstimate: sampleVolumeRawEstimate(for: sample.volume),
            selectedSampleLength: sample.pcm.count, sampleMapKeymapPresent: selection.sampleMapKeymapPresent,
            mappedSampleIndex: selection.mappedSampleIndex, mappedSampleValid: selection.mappedSampleValid,
            sampleSelectionMethod: selection.method, sampleSelectionStrategy: selection.method.rawValue,
            firstPlayableSampleFallbackUsed: selection.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: selection.sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: selection.sampleMapKeymapMissingOrDeferred,
            effectType: cell.effectType, effectParam: cell.effectParam, syntheticRow: syntheticRow,
            syntheticTick: tick, eventIndex: eventIndex, loopMode: sample.loopType == 1 ? .forward : sample.loopType == 2 ? .pingPong : .none,
            volumeColumn: PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
            sampleOffset: sampleOffsetDiagnostic(from: cell, source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, selectedSampleLength: sample.pcm.count, channelState: &state),
            hasIgnoredVolumeColumn: false, hasIgnoredEffect: false,
            effectiveVolumeValue: state.outputChannelVolume, effectiveGlobalVolumeValue: context.globalVolumeState.volumeValue,
            effectiveGlobalVolumeMultiplier: context.globalVolumeState.multiplier, effectivePan: state.pan,
            volumeEnvelopeStatus: envelope.status, sourceVolumeEnvelopePointCount: envelope.sourcePointCount,
            mappedVolumeEnvelopePointCount: envelope.mappedPointCount,
            hasDeferredVolumeEnvelopeSustain: false, hasDeferredVolumeEnvelopeLoop: false, hasDeferredVolumeEnvelopeFadeout: false,
            volumeEnvelopeSemantics: volumeEnvelopeSemantics(from: instrument.volumeEnvelope, mapping: envelope),
            sampleBaseSampleRate: sample.baseSampleRate, sampleRelativeNote: sample.relativeNote, sampleFinetune: sample.finetune,
            outputSampleRate: pitch.outputSampleRate, effectiveNoteValue: pitch.effectiveNoteValue,
            effectiveNoteIndex: pitch.effectiveNoteIndex, effectiveFinetune: pitch.effectiveFinetune,
            linearPeriod: pitch.linearPeriod, linearFrequency: pitch.linearFrequency,
            amigaPeriod: pitch.amigaPeriod, amigaFrequency: pitch.amigaFrequency, finetuneStatus: pitch.finetuneStatus,
            usesLinearFrequencyTable: song.usesLinearFrequencyTable, frequencyTableStatus: pitch.frequencyTableStatus,
            linearFrequencyApplied: pitch.linearFrequencyApplied, amigaFrequencyApplied: pitch.amigaFrequencyApplied,
            amigaFrequencyDeferred: pitch.amigaFrequencyDeferred, playbackStep: pitch.playbackStep,
            pitchMappingApplied: pitch.applied, pitchMappingUsedNeutralStep: pitch.usedNeutralStep)
        if let existing {
            // FT2 coalesces ordinary-note and R trigger requests before updateVoices.
            context.events[existing] = event
            context.eventMappings[state.activeEventMappingIndex!] = mapping
        } else {
            if !resetsInstrument { context.noteOnlyEventIndices.insert(eventIndex) }
            if state.activeEventIndex == nil && state.keyOffWithoutVoice { context.coldReleasedEventIndices.insert(eventIndex) }
            context.events.append(event)
            state.activeEventMappingIndex = context.eventMappings.count
            context.eventMappings.append(mapping)
            context.eventCoverage.recordScheduledNote(method: selection.method,
                firstPlayableSampleFallbackUsed: selection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: selection.sampleMapKeymapBehaviorDeferred)
        }
        state.activeEventIndex = eventIndex
        state.activeInstrumentIndex = instrumentIndex; state.activeSampleIndex = sample.sampleIndex
        state.semanticInstrumentIndex = instrumentIndex; state.semanticSampleIndex = sample.sampleIndex
        state.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
        state.activeSampleVolume = sample.volume
        state.triggeredSampleDefaultVolume = sampleVolumeRawEstimate(for: sample.volume)
        state.triggeredSampleDefaultPan = sample.panning
        state.activePlaybackStep = pitch.playbackStep
        state.activeLinearPeriod = pitch.linearPeriod; state.activeAmigaPeriod = pitch.amigaPeriod
        state.vibratoOutputLinearPeriod = nil; state.vibratoOutputAmigaPeriod = nil
        state.activeSampleBaseSampleRate = sample.baseSampleRate
        state.activeSampleRelativeNote = sample.relativeNote; state.activeSampleFinetune = sample.finetune
        state.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
        applyActiveVolumeEnvelopeMapping(envelope, to: &state)
        captureSelection(source: source, row: syntheticRow, tick: tick, channel: channelIndex,
            frame: frame, role: .retainedNoteRestart, linear: song.usesLinearFrequencyTable,
            noteOnly: cell.instrument == 0, tuning: .representedHeader, routedInstrument: instrumentIndex, selection: selection, state: state, context: &context)
        return (true, existing != nil)
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
        guard isE9xRetriggerEffect(cell) else {
            return nil
        }

        let intervalNibble = retriggerIntervalNibble(from: cell)
        let interval = intervalNibble
        let volumeModeNibble = 0
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
            let deferred = false
            let ignoredAsNoOp = status == .noActiveVoice || status == .outOfRowNoOp || status == .rowEntryNotScheduled
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
                intervalNibble: intervalNibble,
                volumeChangePolicy: nil,
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
                status: .outOfRowNoOp
            )
            retriggerEffects.append(result)
            return result
        }
        guard interval < rowSpeed else {
            let result = diagnostic(status: .outOfRowNoOp)
            retriggerEffects.append(result)
            return result
        }
        // A dispatched E9 calls triggerInstrument even when triggerNote has no source.
        channelState.tremorPhase = 0
        channelState.rRetriggerCounter = 0
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
        let retriggerState = channelState
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
            let volumeBefore = retriggerState.baseChannelVolume
            let gain = songGain(
                outputChannelVolume: retriggerState.outputChannelVolume,
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
                effectiveVolumeValue: retriggerState.outputChannelVolume,
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
            volumeValuesAfter.append(retriggerState.baseChannelVolume)
            retriggerGains.append(gain)
            previousEventIndex = eventIndex
            tick += interval
        }

        channelState.activeEventIndex = previousEventIndex
        channelState.activeEventMappingIndex = eventMappings.count - 1
        channelState.activeSampleVolume = activeSampleVolume
        channelState.baseChannelVolume = retriggerState.baseChannelVolume
        // E9 retriggers the sample/envelopes without replacing FT2's held outVol.
        channelState.outputChannelVolume = retriggerState.outputChannelVolume
        if !ticks.isEmpty {
            resetTremoloTriggerPhases(state: &channelState)
        }
        channelState.volumeValueZeroedByAxy = retriggerState.baseChannelVolume == 0

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

    /// Applies the observed FT2 integer volume rule, independently of R memory or dispatch.
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
            // The exhaustive 0...64 oracle grid requires three separately truncated terms.
            unclampedAfter = before / 2 + before / 8 + before / 16
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
        // ECx is an output writer. Its actual tick executes in the row's volume pass;
        // retaining this association also retains pitch, key and source identity.
    }

    static func applyNoteCutVolume(cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, tick: Int, timingPlan: PlaybackSongFxxTimingPlan, globalVolume: Int,
        state: inout ChannelState, updates: inout [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]) {
        let before = state
        state.baseChannelVolume = 0
        updates.append(voiceStateUpdateDiagnostic(source: source, channelIndex: channelIndex,
            syntheticRow: syntheticRow, syntheticTick: tick,
            scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick), cell: cell,
            commandSource: .effectColumn, command: .ecxNoteCut, rawVolumeColumn: nil,
            effectType: cell.effectType, effectParam: cell.effectParam, status: .applied,
            behavior: tick == 0 ? .rowLevelApproximation : .tickLevelAfterTick0,
            channelStateBefore: before, channelStateAfter: state,
            globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume,
            activeVoiceUpdatedOverride: state.activeEventIndex != nil))
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

    /// Nonzero instrument-only delay is a retained-note dispatch; ED0 stays ordinary.
    static func isDelayedInstrumentOnly(_ cell: PlaybackCell) -> Bool {
        cell.note == 0 && cell.instrument > 0 && cell.effectType == 0x0E && (0xD1...0xDF).contains(cell.effectParam)
    }

    /// Plans only this row's nonzero ticks, sharing source routing and instrument reset authority.
    static func handleDelayedInstrumentOnly(cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int,
        syntheticRow: Int, song: PlaybackSong, timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan, context: inout AdapterRowContext) {
        var state = context.channelStates[channelIndex]
        let selected = song.instrumentsByIndex[Int(cell.instrument)] != nil
        let requested = extendedEffectTick(cell), outOfRow = requested >= timingConfig.speed
        let column = PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn)
        let slide = isOrdinaryVolumeColumnSlide(cell.volumeColumn) ? column : nil
        var status: PlaybackSongSyntheticNoteDelayDiagnostic.Status = !selected ? .instrumentOnlyInvalidInstrument :
            outOfRow ? .instrumentOnlyOutOfRow : .instrumentOnlyNoRetainedNote
        var eventIndex: Int?, defaultVolume: Int?, defaultPan: UInt8?, pan: Double?
        for tick in 1..<max(1, timingConfig.speed) {
            context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(slide, cell: cell, source: source,
                channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: timingConfig.speed,
                timingPlan: timingPlan, state: &state, globalVolume: context.globalVolumeState.volumeValue))
            if (0xB0...0xBF).contains(cell.volumeColumn) {
                appendPitchWriter(handleVibrato(from: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, timingConfig: timingConfig, timingPlan: timingPlan,
                    channelState: &state, executionTicks: tick..<(tick + 1)), to: &context)
            }
            if cell.volumeColumn >> 4 == 0x0F {
                // Tick zero was skipped, so Fx cannot seed a new portamento speed.
                let continuation = PlaybackCell(note: 0, instrument: 0, volumeColumn: 0xF0,
                    effectType: cell.effectType, effectParam: cell.effectParam)
                let diagnostic = handleTonePortamento(from: continuation, source: source,
                    channelIndex: channelIndex, syntheticRow: syntheticRow, timingConfig: timingConfig,
                    timingPlan: timingPlan, usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &state, volumeColumn: PlaybackSongVolumeColumnDecoder.decode(0xF0),
                    executionTicks: tick..<(tick + 1))
                let diagnosticIndex = context.tonePortamentoEffects.count
                appendPitchWriter(diagnostic, to: &context, invocationTick: tick)
                context.g23ChildlessPitchInvocationObserver.record(rowCell: cell, tick: tick,
                    diagnosticIndex: diagnosticIndex, diagnostics: context.tonePortamentoEffects)
            }
            guard selected, tick == requested else { continue }
            let frame = timingPlan.frameFor(row: syntheticRow, tick: tick)
            let priorSourceEventIndex = state.activeEventIndex
            // This token is filled only by the real phase-reset call, never by dispatch admission.
            var reset: (PlaybackSongRowEntryTriggerResetFacts.Scalars, PlaybackSongRowEntryTriggerResetFacts.Scalars)?
            let observe: (PlaybackSongRowEntryTriggerResetFacts.Scalars, PlaybackSongRowEntryTriggerResetFacts.Scalars) -> Void = {
                reset = ($0, $1)
            }
            if (1...96).contains(state.carriedNote) {
                let (started, _) = restartRetainedSource(cell: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, tick: tick, frame: frame, song: song, timingConfig: timingConfig,
                    resetsInstrument: true, state: &state, context: &context, didResetEffectPhases: observe)
                status = started ? .instrumentOnlyStarted : .instrumentOnlyUnavailable
                eventIndex = started ? state.activeEventIndex : nil
            } else {
                // No retained note means no resolver invocation or fabricated route.
                resetDelayedInstrument(cell: cell, state: &state, didResetEffectPhases: observe)
                captureSelection(source: source, row: syntheticRow, tick: tick, channel: channelIndex,
                    frame: frame, role: .coldDispatch, linear: song.usesLinearFrequencyTable, state: state, context: &context)
            }
            if let reset {
                context.delayedInstrumentResetObserver.record(.init(source: source, syntheticRow: syntheticRow,
                    syntheticTick: tick, channelIndex: channelIndex, scheduledFrame: frame,
                    requestedInstrumentIndex: Int(cell.instrument), priorSourceEventIndex: priorSourceEventIndex,
                    newSourceEventIndex: eventIndex, before: reset.0, after: reset.1))
            }
            defaultVolume = state.triggeredSampleDefaultVolume
            defaultPan = state.triggeredSampleDefaultPan
            pan = state.panningValue
            if cell.volumeColumn != 0 {
                context.volumeColumnMappings.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, syntheticTick: tick, volumeColumn: column))
            }
        }
        var diagnostic = PlaybackSongSyntheticNoteDelayDiagnostic(source: source, channelIndex: channelIndex,
            syntheticRow: syntheticRow, syntheticTick: requested, effectType: cell.effectType, effectParam: cell.effectParam,
            status: status, detected: true, applied: selected && !outOfRow, deferred: false,
            ignoredAsNoOp: !selected || outOfRow, outOfRow: outOfRow, requestedTick: requested,
            rowSpeed: timingConfig.speed, rowBPM: timingConfig.bpm, originalFrame: timingPlan.frameFor(row: syntheticRow),
            delayedFrame: selected && !outOfRow ? timingPlan.frameFor(row: syntheticRow, tick: requested) : nil,
            eventIndex: eventIndex)
        diagnostic.rowEntryInstrumentSelected = selected
        diagnostic.retainedNote = (1...96).contains(state.carriedNote) ? state.carriedNote : nil
        diagnostic.cachedDefaultVolume = defaultVolume
        diagnostic.cachedDefaultPan = defaultPan
        diagnostic.delayedPanningValue = pan
        context.noteDelayEffects.append(diagnostic)
        context.channelStates[channelIndex] = state
    }

    static func noteDelayDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        originalFrame: Int,
        eventIndex: Int?,
        instrumentOnlyImmediate: Bool = false
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
                status: instrumentOnlyImmediate ? .instrumentOnlyImmediate : .noNoteDeferred,
                detected: true,
                applied: instrumentOnlyImmediate,
                deferred: !instrumentOnlyImmediate,
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
