import Foundation

/// Bounded pending physical writers at one real row boundary. This owns copied
/// scalar metadata and boundary children, never a row context or parent plan.
struct PlaybackSongPendingRowPitch {
    typealias Child = PlaybackSongSyntheticTonePortamentoStepUpdate
    struct Arpeggio {
        let originalDiagnosticIndex: Int
        let originalPublishedChildIndex: Int?
        let command: PlaybackSongSyntheticArpeggioDiagnostic
    }
    struct Vibrato {
        let originalDiagnosticIndex: Int
        let originalPublishedChildIndex: Int?
        let originalInactiveChildIndex: Int?
        let needsEligibilityCheck: Bool
        let command: PlaybackSongSyntheticVibratoDiagnostic
    }
    struct Imported {
        let arpeggioIndices: [Int: Int]
        let vibratoIndices: [Int: Int]
    }
    let boundaryFrame: Int
    let arpeggios: [Arpeggio]
    let vibratos: [Vibrato]
    var childCount: Int {
        arpeggios.reduce(0) { $0 + $1.command.stepUpdates.count + ($1.command.subsumedRowExit == nil ? 0 : 1) } +
            vibratos.reduce(0) { $0 + $1.command.stepUpdates.count + $1.command.inactiveSourceStepUpdates.count +
                ($1.command.supersededDelayedBirth == nil ? 0 : 1) }
    }

    /// Capture finalized delivery/admission lists, not stale pre-admission context
    /// diagnostics. Original numeric producer/ID scope belongs to the outer batch.
    static func capture(plan: borrowing PlaybackSongSyntheticPlan, lastSyntheticRow: Int,
        boundaryFrame: Int, ordinaryDelayedVibratoIndices: [Int] = []) -> Self {
        let delayed = Set(ordinaryDelayedVibratoIndices)
        func atBoundary(_ child: Child) -> Bool { child.scheduledFrame == boundaryFrame }
        var arpeggios = [Arpeggio](), vibratos = [Vibrato]()
        for (index, input) in plan.diagnostics.arpeggioEffects.enumerated()
            where input.syntheticRow == lastSyntheticRow && input.applied {
            let children = input.stepUpdates.filter(atBoundary)
            let subsumed = input.subsumedRowExit.flatMap { atBoundary($0) ? $0 : nil }
            guard !children.isEmpty || subsumed != nil else { continue }
            arpeggios.append(.init(originalDiagnosticIndex: index,
                originalPublishedChildIndex: input.stepUpdates.firstIndex(where: atBoundary),
                command: copyArpeggio(input, row: input.syntheticRow,
                    event: input.activeEventIndex, mapping: input.activeEventMappingIndex,
                    children: children, subsumed: subsumed)))
        }
        for (index, input) in plan.diagnostics.vibratoEffects.enumerated()
            where input.syntheticRow == lastSyntheticRow && input.applied {
            let children = input.stepUpdates.filter(atBoundary)
            let inactive = input.inactiveSourceStepUpdates.filter(atBoundary)
            let superseded = input.supersededDelayedBirth.flatMap { atBoundary($0) ? $0 : nil }
            guard !children.isEmpty || !inactive.isEmpty || superseded != nil else { continue }
            vibratos.append(.init(originalDiagnosticIndex: index,
                originalPublishedChildIndex: input.stepUpdates.firstIndex(where: atBoundary),
                originalInactiveChildIndex: input.inactiveSourceStepUpdates.firstIndex(where: atBoundary),
                needsEligibilityCheck: delayed.contains(index) || input.ordinaryDelayedExecution,
                command: copyVibrato(input, row: input.syntheticRow,
                    event: input.activeEventIndex, mapping: input.activeEventMappingIndex,
                    children: children, inactive: inactive, superseded: superseded)))
        }
        return .init(boundaryFrame: boundaryFrame, arpeggios: arpeggios, vibratos: vibratos)
    }

    /// Imports lookup-bound diagnostics before the first real local row zero.
    /// Missing mappings reject transactionally; no source is rebound by channel.
    @discardableResult
    func restore(into context: inout PlaybackSongSyntheticAdapter.AdapterRowContext,
                 sourceMap: [Int: Int], mappingMap: [Int: Int]) -> Imported? {
        guard context.arpeggioEffects.isEmpty, context.vibratoEffects.isEmpty,
              context.ordinaryDelayedVibratoIndices.isEmpty,
              context.nativePitchWriterObserver.spans.isEmpty else { return nil }
        func mapped(_ old: Int?, through map: [Int: Int]) -> Int?? {
            guard let old else { return .some(nil) }
            guard let value = map[old], value >= 0 else { return nil }
            return .some(value)
        }
        var arps = [PlaybackSongSyntheticArpeggioDiagnostic]()
        var vibs = [PlaybackSongSyntheticVibratoDiagnostic]()
        var arpMap = [Int: Int](), vibMap = [Int: Int](), delayed = [Int]()
        for input in arpeggios {
            guard let event = mapped(input.command.activeEventIndex, through: sourceMap),
                  let mapping = mapped(input.command.activeEventMappingIndex, through: mappingMap) else { return nil }
            arpMap[input.originalDiagnosticIndex] = arps.count
            arps.append(Self.copyArpeggio(input.command, row: -1, event: event, mapping: mapping,
                children: input.command.stepUpdates, subsumed: input.command.subsumedRowExit))
        }
        for input in vibratos {
            guard let event = mapped(input.command.activeEventIndex, through: sourceMap),
                  let mapping = mapped(input.command.activeEventMappingIndex, through: mappingMap) else { return nil }
            vibMap[input.originalDiagnosticIndex] = vibs.count
            if input.needsEligibilityCheck { delayed.append(vibs.count) }
            vibs.append(Self.copyVibrato(input.command, row: -1, event: event, mapping: mapping,
                children: input.command.stepUpdates, inactive: input.command.inactiveSourceStepUpdates,
                superseded: input.command.supersededDelayedBirth))
        }
        context.arpeggioEffects = arps
        context.vibratoEffects = vibs
        context.ordinaryDelayedVibratoIndices = delayed
        // Exit-only imports contain no ordinary prefix child to capture in a
        // native span. The existing observer retains its exact scalar witness.
        context.rowExitObserver.seedPreviousRow(firstDiagnosticIndex: 0,
            spanIndices: Array(repeating: -1, count: vibs.count))
        return .init(arpeggioIndices: arpMap, vibratoIndices: vibMap)
    }

    @inline(never)
    private static func copyArpeggio(_ input: PlaybackSongSyntheticArpeggioDiagnostic, row: Int, event: Int?, mapping: Int?,
        children: [Child], subsumed: Child?) -> PlaybackSongSyntheticArpeggioDiagnostic {
        .init(
            source: input.source,
            channelIndex: input.channelIndex,
            syntheticRow: row,
            syntheticTick: input.syntheticTick,
            effectType: input.effectType,
            effectParam: input.effectParam,
            status: input.status,
            detected: input.detected,
            applied: input.applied,
            deferred: input.deferred,
            ignoredAsNoOp: input.ignoredAsNoOp,
            effectMemoryDeferred: input.effectMemoryDeferred,
            activeVoiceFound: input.activeVoiceFound,
            activeEventIndex: event,
            activeEventMappingIndex: mapping,
            xSemitoneOffset: input.xSemitoneOffset,
            ySemitoneOffset: input.ySemitoneOffset,
            currentAmigaPeriodBefore: input.currentAmigaPeriodBefore,
            currentAmigaPeriodAfter: input.currentAmigaPeriodAfter,
            currentLinearPeriodBefore: input.currentLinearPeriodBefore,
            currentLinearPeriodAfter: input.currentLinearPeriodAfter,
            currentPlaybackStepBefore: input.currentPlaybackStepBefore,
            currentPlaybackStepAfter: input.currentPlaybackStepAfter,
            rowSpeed: input.rowSpeed,
            rowBPM: input.rowBPM,
            stepUpdates: children,
            policy: input.policy,
            subsumedRowExit: subsumed
        )
    }

    @inline(never)
    private static func copyVibrato(_ input: PlaybackSongSyntheticVibratoDiagnostic, row: Int, event: Int?, mapping: Int?,
        children: [Child], inactive: [Child], superseded: Child?) -> PlaybackSongSyntheticVibratoDiagnostic {
        .init(
            source: input.source,
            channelIndex: input.channelIndex,
            syntheticRow: row,
            syntheticTick: input.syntheticTick,
            effectType: input.effectType,
            effectParam: input.effectParam,
            status: input.status,
            detected: input.detected,
            applied: input.applied,
            deferred: input.deferred,
            ignoredAsNoOp: input.ignoredAsNoOp,
            activeVoiceFound: input.activeVoiceFound,
            activeEventIndex: event,
            activeEventMappingIndex: mapping,
            vibratoSpeed: input.vibratoSpeed,
            vibratoDepth: input.vibratoDepth,
            vibratoSpeedSource: input.vibratoSpeedSource,
            vibratoDepthSource: input.vibratoDepthSource,
            vibratoControlValue: input.vibratoControlValue,
            vibratoWaveform: input.vibratoWaveform,
            vibratoWaveformSource: input.vibratoWaveformSource,
            effectMemoryReused: input.effectMemoryReused,
            effectMemoryMissing: input.effectMemoryMissing,
            effectMemoryDeferred: input.effectMemoryDeferred,
            vibratoSpeedMemorySource: input.vibratoSpeedMemorySource,
            vibratoDepthMemorySource: input.vibratoDepthMemorySource,
            memoryUnavailableReason: input.memoryUnavailableReason,
            volumeSlideUp: input.volumeSlideUp,
            volumeSlideDown: input.volumeSlideDown,
            volumeSlideAmount: input.volumeSlideAmount,
            volumeSlideDirection: input.volumeSlideDirection,
            phaseBefore: input.phaseBefore,
            phaseAfter: input.phaseAfter,
            currentLinearPeriodBefore: input.currentLinearPeriodBefore,
            currentLinearPeriodAfter: input.currentLinearPeriodAfter,
            currentPlaybackStepBefore: input.currentPlaybackStepBefore,
            currentPlaybackStepAfter: input.currentPlaybackStepAfter,
            rowSpeed: input.rowSpeed,
            rowBPM: input.rowBPM,
            stepUpdates: children,
            policy: input.policy,
            ordinaryDelayedExecution: input.ordinaryDelayedExecution,
            supersededDelayedBirth: superseded,
            inactiveSourceStepUpdates: inactive
        )
    }
}
