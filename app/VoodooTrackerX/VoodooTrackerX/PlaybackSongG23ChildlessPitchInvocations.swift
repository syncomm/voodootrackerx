import Foundation

/// Partial evidence of actual childless F0 calls on instrument-only nonzero EDx rows.
/// Neither a pitch value nor a claim about semantic ownership, source lifetime or C delivery.
struct PlaybackSongG23ChildlessPitchInvocations: Equatable {
    enum Coverage { case notAdapterProduced, partialG23F0InvocationsV1 }
    enum Classification { case executedNoNumericPitchChild }
    struct Run: Equatable {
        let firstToneDiagnosticIndex: Int
        let firstTick: Int
        var invocationCount: Int
        // The original row command differs from the instrumentless continuation passed to the handler.
        let rowCell: PlaybackCell
    }
    struct Observation: Equatable {
        let diagnosticIndex: Int
        let source: PlaybackPosition
        let syntheticRow: Int
        let channelIndex: Int
        let syntheticTick: Int
        let scheduledFrame: Int
        let rowCell: PlaybackCell
        let status: PlaybackSongSyntheticTonePortamentoDiagnostic.Status
        let policy: String
        let associatedGeneration: Int?
        let classification: Classification
    }
    let coverage: Coverage
    let runs: [Run]
    let storageGrowthCount: Int
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, runs: [], storageGrowthCount: 0)

    private static func matches(_ command: borrowing PlaybackSongSyntheticTonePortamentoDiagnostic,
        rowCell: PlaybackCell) -> Bool {
        rowCell.note == 0 && rowCell.instrument != 0 && rowCell.volumeColumn == 0xF0 &&
            rowCell.effectType == 0x0E && rowCell.effectParam >> 4 == 0x0D && rowCell.effectParam & 15 != 0 &&
            command.commandSource == .volumeColumn && command.rawVolumeColumn == 0xF0 &&
            command.effectType == rowCell.effectType && command.effectParam == rowCell.effectParam &&
            command.stepUpdates.isEmpty
    }

    /// Called only after the real handler and its unchanged diagnostic append have completed.
    struct Observer {
        var runs = [Run]()
        var storageGrowthCount = 0

        mutating func record(rowCell: PlaybackCell, tick: Int, diagnosticIndex: Int,
            diagnostics: borrowing [PlaybackSongSyntheticTonePortamentoDiagnostic]) {
            guard diagnostics.indices.contains(diagnosticIndex), tick > 0,
                  tick < diagnostics[diagnosticIndex].rowSpeed,
                  PlaybackSongG23ChildlessPitchInvocations.matches(diagnostics[diagnosticIndex], rowCell: rowCell) else { return }
            if let last = runs.last,
               diagnosticIndex - last.firstToneDiagnosticIndex == last.invocationCount,
               tick - last.firstTick == last.invocationCount, last.rowCell == rowCell,
               diagnostics.indices.contains(last.firstToneDiagnosticIndex),
               diagnostics[last.firstToneDiagnosticIndex].source == diagnostics[diagnosticIndex].source,
               diagnostics[last.firstToneDiagnosticIndex].syntheticRow == diagnostics[diagnosticIndex].syntheticRow,
               diagnostics[last.firstToneDiagnosticIndex].channelIndex == diagnostics[diagnosticIndex].channelIndex {
                runs[runs.count - 1].invocationCount += 1
            } else {
                // No expansion from rowSpeed: every element has individually passed this hook.
                let capacity = runs.capacity
                runs.append(.init(firstToneDiagnosticIndex: diagnosticIndex, firstTick: tick,
                    invocationCount: 1, rowCell: rowCell))
                if runs.capacity != capacity { storageGrowthCount += 1 }
            }
        }

        var evidence: PlaybackSongG23ChildlessPitchInvocations {
            .init(coverage: .partialG23F0InvocationsV1, runs: runs, storageGrowthCount: storageGrowthCount)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Nil is unobserved coverage, never native zero, absent PCM or a rejected physical request.
    func g23ChildlessPitchInvocation(run runIndex: Int, invocation: Int) -> PlaybackSongG23ChildlessPitchInvocations.Observation? {
        let evidence = g23ChildlessPitchInvocations
        guard evidence.coverage == .partialG23F0InvocationsV1, evidence.runs.indices.contains(runIndex) else { return nil }
        let run = evidence.runs[runIndex]
        guard invocation >= 0, invocation < run.invocationCount else { return nil }
        let index = run.firstToneDiagnosticIndex.addingReportingOverflow(invocation)
        let tick = run.firstTick.addingReportingOverflow(invocation)
        guard !index.overflow, !tick.overflow, diagnostics.tonePortamentoEffects.indices.contains(index.partialValue),
              diagnostics.tonePortamentoEffects.indices.contains(run.firstToneDiagnosticIndex) else { return nil }
        let command = diagnostics.tonePortamentoEffects[index.partialValue]
        let first = diagnostics.tonePortamentoEffects[run.firstToneDiagnosticIndex]
        guard command.source == first.source, command.syntheticRow == first.syntheticRow,
              command.channelIndex == first.channelIndex, command.stepUpdates.isEmpty,
              let coordinate = canonicalTickClock.coordinate(syntheticRow: command.syntheticRow,
                  tick: tick.partialValue, channel: command.channelIndex) else { return nil }
        return .init(diagnosticIndex: index.partialValue, source: command.source, syntheticRow: command.syntheticRow,
            channelIndex: command.channelIndex, syntheticTick: tick.partialValue, scheduledFrame: coordinate.absoluteFrame,
            rowCell: run.rowCell, status: command.status, policy: command.policy,
            associatedGeneration: command.activeEventIndex, classification: .executedNoNumericPitchChild)
    }
}
