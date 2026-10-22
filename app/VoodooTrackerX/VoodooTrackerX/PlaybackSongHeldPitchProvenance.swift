import Foundation

/// Partial producer evidence for ordinary selection, pure Bx, 1xx and targetless 300.
/// A row hold is neither a tick calculation nor a physical/C-accepted pitch request.
struct PlaybackSongHeldPitchProvenance: Equatable {
    enum Coverage { case notAdapterProduced, partialBxUpSlideTargetlessRows }
    enum Producer: Equatable {
        case selectionFact(Int)
        case volumeColumnVibrato(diagnostic: Int, child: Int)
        case portamentoUp(diagnostic: Int, child: Int)
    }
    struct Known: Equatable {
        let domain: PlaybackSongSelectionDispatchFacts.Domain
        let nativePeriod: Double
        let producer: Producer
        // Actual selection ownership/generation, not a channel ID or eligibility decision.
        let selectionFactIndex: Int
    }
    enum Held: Equatable { case notEstablished, notCaptured, known(Known) }
    struct RowHold: Equatable {
        // Coordinates/source are the existing command's row scope, never synthetic tick invocations.
        let toneDiagnosticIndex: Int
        let held: Held
    }
    let coverage: Coverage
    let rowHolds: [RowHold]
    let storageGrowthCount: Int
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, rowHolds: [], storageGrowthCount: 0)

    /// Planning-only sidecar. No musical decision or consumer reads its latches.
    struct Observer {
        enum RowKind { case continuation, selection, vibrato, slide, targetless, unmodeled }
        struct Checkpoint {
            let kind: RowKind
            let firstFact: Int
            let firstDiagnostic: Int
        }
        var channels = [Held]()
        var rowHolds = [RowHold]()
        var storageGrowthCount = 0
        var channelStorageGrowthCount = 0

        mutating func ensureChannels(_ count: Int) {
            guard channels.count < count else { return }
            let capacity = channels.capacity
            channels.append(contentsOf: repeatElement(.notEstablished, count: count - channels.count))
            if channels.capacity != capacity { channelStorageGrowthCount += 1 }
        }

        /// Unproven writers/lifecycles invalidate before any later deferred execution.
        mutating func begin(_ cell: PlaybackCell, channel: Int, firstFact: Int,
            vibratoCount: Int, slideCount: Int, toneCount: Int) -> Checkpoint {
            let kind: RowKind
            let diagnostic: Int
            if cell.effectType == 0 && cell.effectParam == 0 {
                if (1...96).contains(cell.note) && (cell.volumeColumn == 0 || cell.volumeColumn >> 4 == 0xA) {
                    kind = .selection
                } else if cell.note == 0 && cell.instrument == 0 && cell.volumeColumn == 0 {
                    kind = .continuation
                } else if cell.note == 0 && cell.instrument == 0 && cell.volumeColumn >> 4 == 0xB {
                    kind = .vibrato
                } else { kind = .unmodeled }
                diagnostic = vibratoCount
            } else if cell.note == 0 && cell.instrument == 0 && cell.volumeColumn == 0 && cell.effectType == 1 {
                kind = .slide; diagnostic = slideCount
            } else if cell.note == 0 && cell.instrument == 0 && cell.volumeColumn == 0 &&
                        cell.effectType == 3 && cell.effectParam == 0 {
                kind = .targetless; diagnostic = toneCount
            } else { kind = .unmodeled; diagnostic = 0 }
            if kind == .selection || kind == .unmodeled { channels[channel] = .notCaptured }
            return .init(kind: kind, firstFact: firstFact, firstDiagnostic: diagnostic)
        }

        mutating func seed(_ fact: borrowing PlaybackSongSelectionDispatchFacts.Fact, index: Int, channel: Int) {
            let role = fact.role, method = fact.selectionMethod, mappedSample = fact.mappedSample
            guard role == .trigger && method == .sampleMap || role == .emptySelection && mappedSample != nil,
                  case let .known(domain, period) = fact.pitch else { return }
            channels[channel] = .known(.init(domain: domain, nativePeriod: period,
                producer: .selectionFact(index), selectionFactIndex: index))
        }

        mutating func calculated(_ update: borrowing PlaybackSongSyntheticTonePortamentoStepUpdate,
            producer: Producer, generation: Int?, selectionGeneration: Int?, channel: Int) {
            guard case let .known(previous) = channels[channel], generation == selectionGeneration else {
                channels[channel] = .notCaptured; return
            }
            let period = previous.domain == .linear ? update.linearPeriodAfter : update.amigaPeriodAfter
            guard let period else { channels[channel] = .notCaptured; return }
            // Capture native output even when two outputs quantize to the same step.
            channels[channel] = .known(.init(domain: previous.domain, nativePeriod: period,
                producer: producer, selectionFactIndex: previous.selectionFactIndex))
        }

        mutating func hold(toneDiagnosticIndex: Int, channel: Int) {
            let capacity = rowHolds.capacity
            rowHolds.append(.init(toneDiagnosticIndex: toneDiagnosticIndex, held: channels[channel]))
            if rowHolds.capacity != capacity { storageGrowthCount += 1 }
        }

        var evidence: PlaybackSongHeldPitchProvenance {
            .init(coverage: .partialBxUpSlideTargetlessRows, rowHolds: rowHolds, storageGrowthCount: storageGrowthCount)
        }
    }
}

extension PlaybackSongSyntheticAdapter {
    /// Completes this cell's observer after existing row-entry defers, without another row/song pass.
    static func captureHeldPitchRow(_ checkpoint: PlaybackSongHeldPitchProvenance.Observer.Checkpoint,
        channel: Int, context: inout AdapterRowContext) {
        let first = checkpoint.firstDiagnostic
        switch checkpoint.kind {
        case .continuation, .unmodeled: return
        case .selection:
            // Visit only facts just captured for this ordinary selection, never a history scan.
            for index in checkpoint.firstFact..<context.selectionFacts.count {
                context.heldPitchObserver.seed(context.selectionFacts[index], index: index, channel: channel)
            }
        case .targetless:
            guard context.tonePortamentoEffects.count == first + 1,
                  !context.tonePortamentoEffects[first].targetExistsAfter,
                  context.tonePortamentoEffects[first].stepUpdates.isEmpty,
                  context.tonePortamentoEffects[first].status == .noTarget ||
                    context.tonePortamentoEffects[first].status == .noActiveVoice else {
                context.heldPitchObserver.channels[channel] = .notCaptured; return
            }
            context.heldPitchObserver.hold(toneDiagnosticIndex: first, channel: channel)
        case .vibrato, .slide:
            guard case let .known(previous) = context.heldPitchObserver.channels[channel] else {
                context.heldPitchObserver.channels[channel] = .notCaptured; return
            }
            let generation = context.selectionFacts[previous.selectionFactIndex].associatedGeneration
            if checkpoint.kind == .vibrato {
                guard context.vibratoEffects.count == first + 1,
                      context.vibratoEffects[first].status == .applied ||
                        context.vibratoEffects[first].status == .noActiveVoice else {
                    context.heldPitchObserver.channels[channel] = .notCaptured; return
                }
                // Pure Bx has no row exit, delayed-birth split or eligibility-filtered children.
                let count = context.vibratoEffects[first].stepUpdates.count
                if count > 0 {
                    context.heldPitchObserver.calculated(context.vibratoEffects[first].stepUpdates[count - 1],
                        producer: .volumeColumnVibrato(diagnostic: first, child: count - 1),
                        generation: context.vibratoEffects[first].activeEventIndex,
                        selectionGeneration: generation, channel: channel)
                }
                // A source-less phase-only or speed-1 command establishes no new period.
            } else {
                guard context.portamentoSlideEffects.count == first + 1,
                      context.portamentoSlideEffects[first].status == .applied ||
                        context.portamentoSlideEffects[first].status == .zeroParamEffectMemoryDeferred else {
                    context.heldPitchObserver.channels[channel] = .notCaptured; return
                }
                let count = context.portamentoSlideEffects[first].stepUpdates.count
                if count > 0 {
                    context.heldPitchObserver.calculated(context.portamentoSlideEffects[first].stepUpdates[count - 1],
                        producer: .portamentoUp(diagnostic: first, child: count - 1),
                        generation: context.portamentoSlideEffects[first].activeEventIndex,
                        selectionGeneration: generation, channel: channel)
                }
            }
        }
    }
}
