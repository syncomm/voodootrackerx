import Foundation

extension PlaybackSongSyntheticAdapter {
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
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(value)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideDown(amount),
             let .fineVolumeSlideDown(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before - amount)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideUp(amount),
             let .fineVolumeSlideUp(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before + amount)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .setPanning(value):
            let before = state.pan
            state.panningValue = clampedPanningValue(Double(value))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideLeft(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue - Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideRight(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue + Double(amount))
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
