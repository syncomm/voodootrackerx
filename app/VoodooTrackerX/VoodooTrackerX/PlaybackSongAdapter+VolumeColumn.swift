import Foundation

extension PlaybackSongSyntheticAdapter {
    /// A resolved trigger starts from its sample header, then the already-supported row commands
    /// keep their existing order: volume-column panning first, effect-column `8xx` second.
    static func applyTriggeredSamplePanning(
        _ samplePanning: UInt8,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        cell: PlaybackCell,
        to state: inout ChannelState
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        state.initializePanning(fromSampleHeader: samplePanning)
        let appliedVolumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
        switch volumeColumn.command {
        case .setPanning, .panningSlideLeft, .panningSlideRight:
            appliedVolumeColumn = applyVolumeColumn(volumeColumn, to: &state)
        default:
            appliedVolumeColumn = volumeColumn
        }
        if cell.effectType == 0x08 {
            state.applyChannelPanningValue(Double(cell.effectParam))
        }
        return appliedVolumeColumn
    }

    static func isTonePortamentoVolumeColumn(
        _ volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    ) -> Bool {
        if case .tonePortamento = volumeColumn.command {
            return true
        }
        return false
    }

    static func applyVolumeColumn(
        _ volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        to state: inout ChannelState
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        switch volumeColumn.command {
        case let .setVolume(value):
            let before = state
            state.baseChannelVolume = clampedVolumeValue(value)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.outputChannelVolume,
                appliedGainMultiplier: volumeMultiplier(for: state.outputChannelVolume),
                effectiveVolumeBefore: before.outputChannelVolume,
                effectiveVolumeAfter: state.outputChannelVolume,
                behavior: .rowLevelApproximation
            )
        case .volumeSlideDown, .volumeSlideUp:
            return volumeColumn.withAppliedState(
                effectiveVolumeBefore: state.outputChannelVolume,
                effectiveVolumeAfter: state.outputChannelVolume,
                behavior: .tickLevelAfterTick0
            )
        case let .fineVolumeSlideDown(amount):
            let before = state
            state.baseChannelVolume = clampedVolumeValue(before.baseChannelVolume - amount)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.outputChannelVolume,
                appliedGainMultiplier: volumeMultiplier(for: state.outputChannelVolume),
                effectiveVolumeBefore: before.outputChannelVolume,
                effectiveVolumeAfter: state.outputChannelVolume,
                behavior: .rowLevelApproximation
            )
        case let .fineVolumeSlideUp(amount):
            let before = state
            state.baseChannelVolume = clampedVolumeValue(before.baseChannelVolume + amount)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.outputChannelVolume,
                appliedGainMultiplier: volumeMultiplier(for: state.outputChannelVolume),
                effectiveVolumeBefore: before.outputChannelVolume,
                effectiveVolumeAfter: state.outputChannelVolume,
                behavior: .rowLevelApproximation
            )
        case let .setPanning(value):
            let before = state.pan
            state.applyChannelPanningValue(Double(value))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideLeft(amount):
            let before = state.pan
            state.applyChannelPanningValue(state.panningValue - Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideRight(amount):
            let before = state.pan
            state.applyChannelPanningValue(state.panningValue + Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case .none,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return volumeColumn
        }
    }

    /// Publish an ordinary column slide before the effect-column writer at this tick.
    /// Channel state advances even without a source; zero amounts restore held output.
    static func applyVolumeColumnSlideTick(
        _ column: PlaybackSongSyntheticVolumeColumnDiagnostic?,
        cell: PlaybackCell, source: PlaybackPosition, channelIndex: Int, syntheticRow: Int,
        tick: Int, rowSpeed: Int, timingPlan: PlaybackSongFxxTimingPlan,
        state: inout ChannelState, globalVolume: Int
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard let column, tick > 0, tick < rowSpeed else { return [] }
        let delta: Int
        switch column.command {
        case let .volumeSlideDown(amount): delta = -amount
        case let .volumeSlideUp(amount): delta = amount
        default: return []
        }
        let before = state
        let unclamped = before.baseChannelVolume + delta
        state.baseChannelVolume = clampedVolumeValue(unclamped)
        state.volumeValueZeroedByAxy = false
        return [voiceStateUpdateDiagnostic(
            source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, syntheticTick: tick,
            scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick), cell: cell,
            commandSource: .volumeColumn, command: .volumeColumn(column.command), rawVolumeColumn: cell.volumeColumn,
            effectType: nil, effectParam: nil, status: .applied, behavior: .tickLevelAfterTick0,
            channelStateBefore: before, channelStateAfter: state,
            globalVolumeBefore: globalVolume, globalVolumeAfter: globalVolume,
            volumeSlideClamped: unclamped != state.baseChannelVolume,
            volumeSlideTick0Suppressed: true, volumeSlideRowSpeed: rowSpeed,
            activeVoiceUpdatedOverride: before.activeEventIndex != nil && before.activeSampleVolume != nil
        )]
    }

    static func appendDeferredFields(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        includeKeyOff: Bool,
        hasDeferredEffectOverride: Bool? = nil,
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) {
        if volumeColumn.deferred {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .volumeColumn
            ))
        }
        if hasDeferredEffectOverride ?? hasDeferredEffect(cell) {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .effect
            ))
        }
        if includeKeyOff, cell.note == 97 {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .keyOff
            ))
        }
    }

}
