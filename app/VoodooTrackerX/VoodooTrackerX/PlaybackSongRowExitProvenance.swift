import Foundation

/// Sparse evidence of existing synthetic restorations removed by a same-frame writer.
/// A restoration marker is neither a canonical tick nor a claim of physical admission.
struct PlaybackSongRowExitProvenance: Equatable {
    enum Coverage { case notAdapterProduced, suppressedRowExitsV1 }
    enum Cause { case arpeggioExitSubsumed, vibratoExitCoalesced }
    enum IncomingFamily: UInt8 {
        case arpeggio, finePortamentoUp, finePortamentoDown
        case extraFinePortamentoUp, extraFinePortamentoDown
    }
    enum Witness: UInt8 { case arpeggioDiagnostic, nativeWriterSpan, exceptionalScalar }
    struct Reference: Equatable {
        let outgoingDiagnosticIndex: Int
        let incomingDiagnosticIndex: Int
        let witnessIndex: Int
        let witness: Witness
        let incomingFamily: IncomingFamily
    }
    struct ScalarWitness: Equatable {
        let nativePeriodBefore: Double
        let nativePeriodAfter: Double
        let scheduledFrame: Int
        let syntheticTick: Int
    }
    struct Observation: Equatable {
        let cause: Cause
        let outgoingDiagnosticIndex: Int
        let incomingFamily: IncomingFamily
        let incomingDiagnosticIndex: Int
        let source: PlaybackPosition
        let syntheticRow: Int
        let channelIndex: Int
        let associatedGeneration: Int
        let syntheticTick: Int
        let scheduledFrame: Int
        let domain: PlaybackSongSelectionDispatchFacts.Domain
        let nativePeriodBefore: Double
        let nativePeriodAfter: Double
        let witness: Witness
    }
    let coverage: Coverage
    let domain: PlaybackSongSelectionDispatchFacts.Domain?
    let references: [Reference]
    let exceptionalScalars: [ScalarWitness]
    let referenceStorageGrowthCount: Int
    let scalarStorageGrowthCount: Int
    // Planning-only two-row lookup buffers are released with the adapter context.
    let lookupCapacityHighWatermark: Int
    let lookupStorageGrowthCount: Int
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, domain: nil,
        references: [], exceptionalScalars: [], referenceStorageGrowthCount: 0,
        scalarStorageGrowthCount: 0, lookupCapacityHighWatermark: 0, lookupStorageGrowthCount: 0)

    fileprivate static func scalar(_ child: borrowing PlaybackSongSyntheticTonePortamentoStepUpdate,
        domain: PlaybackSongSelectionDispatchFacts.Domain) -> ScalarWitness? {
        let before = domain == .linear ? child.linearPeriodBefore : child.amigaPeriodBefore
        let after = domain == .linear ? child.linearPeriodAfter : child.amigaPeriodAfter
        guard let before, let after else { return nil }
        return .init(nativePeriodBefore: before, nativePeriodAfter: after,
            scheduledFrame: child.scheduledFrame, syntheticTick: child.syntheticTick)
    }

    /// Keeps one scalar span index per vibrato diagnostic in only the current/previous row.
    /// A recorded -1 proves that the existing numeric observer retained no span.
    struct Observer {
        var references = [Reference]()
        var exceptionalScalars = [ScalarWitness]()
        var referenceStorageGrowthCount = 0
        var scalarStorageGrowthCount = 0
        var lookupCapacityHighWatermark = 0
        var lookupStorageGrowthCount = 0
        private var domain: PlaybackSongSelectionDispatchFacts.Domain?
        private var currentRow = -1
        private var currentFirstDiagnosticIndex = 0
        private var previousFirstDiagnosticIndex = 0
        private var currentSpanIndices = [Int]()
        private var previousSpanIndices = [Int]()

        mutating func beginRow(_ row: Int, firstVibratoDiagnosticIndex: Int,
            domain: PlaybackSongSelectionDispatchFacts.Domain) {
            precondition(row >= 0 && (currentRow < 0 || row > currentRow))
            swap(&currentSpanIndices, &previousSpanIndices)
            currentSpanIndices.removeAll(keepingCapacity: true)
            previousFirstDiagnosticIndex = currentFirstDiagnosticIndex
            currentFirstDiagnosticIndex = firstVibratoDiagnosticIndex
            currentRow = row
            self.domain = domain
        }

        mutating func registerVibrato(diagnosticIndex: Int, spanIndex: Int?) {
            precondition(diagnosticIndex >= currentFirstDiagnosticIndex &&
                diagnosticIndex - currentFirstDiagnosticIndex == currentSpanIndices.count)
            let capacity = currentSpanIndices.capacity
            currentSpanIndices.append(spanIndex ?? -1)
            if capacity != currentSpanIndices.capacity { lookupStorageGrowthCount += 1 }
            lookupCapacityHighWatermark = max(lookupCapacityHighWatermark,
                currentSpanIndices.capacity + previousSpanIndices.capacity)
        }

        mutating func recordArpeggio(outgoing: Int, incoming: IncomingFamily, incomingIndex: Int) {
            append(.init(outgoingDiagnosticIndex: outgoing, incomingDiagnosticIndex: incomingIndex,
                witnessIndex: outgoing, witness: .arpeggioDiagnostic, incomingFamily: incoming))
        }

        mutating func recordVibrato(outgoing: Int, outgoingRow: Int,
            exit: borrowing PlaybackSongSyntheticTonePortamentoStepUpdate,
            incoming: IncomingFamily, incomingIndex: Int,
            spans: borrowing [PlaybackSongNativePitchWriterSpans.Span]) {
            // The established coalescence searches exactly the previous synthetic row.
            precondition(currentRow > 0 && outgoingRow == currentRow - 1 &&
                outgoing >= previousFirstDiagnosticIndex)
            let ordinal = outgoing - previousFirstDiagnosticIndex
            precondition(previousSpanIndices.indices.contains(ordinal))
            let spanIndex = previousSpanIndices[ordinal]
            let witness: Witness
            let witnessIndex: Int
            if spanIndex >= 0 {
                precondition(spans.indices.contains(spanIndex))
                let span = spans[spanIndex]
                // Validate the actual removed raw child, outside the old public prefix.
                precondition(span.family == .vibrato && span.diagnosticIndex == outgoing &&
                    span.originalChildren.indices.contains(span.capturedChildCount) &&
                    span.capturedChildCount == span.originalChildren.count - 1)
                let rawMatches = span.originalChildren[span.capturedChildCount] == exit
                precondition(rawMatches)
                witness = .nativeWriterSpan
                witnessIndex = spanIndex
            } else {
                // Only a proved missing span may retain these four exact producer scalars.
                guard let domain, let scalar = PlaybackSongRowExitProvenance.scalar(exit, domain: domain) else {
                    preconditionFailure("Suppressed vibrato exit has no native producer values")
                }
                let capacity = exceptionalScalars.capacity
                witnessIndex = exceptionalScalars.count
                exceptionalScalars.append(scalar)
                if capacity != exceptionalScalars.capacity { scalarStorageGrowthCount += 1 }
                witness = .exceptionalScalar
            }
            append(.init(outgoingDiagnosticIndex: outgoing, incomingDiagnosticIndex: incomingIndex,
                witnessIndex: witnessIndex, witness: witness, incomingFamily: incoming))
        }

        private mutating func append(_ reference: Reference) {
            let capacity = references.capacity
            references.append(reference)
            if capacity != references.capacity { referenceStorageGrowthCount += 1 }
        }

        var evidence: PlaybackSongRowExitProvenance {
            .init(coverage: .suppressedRowExitsV1, domain: domain, references: references,
                exceptionalScalars: exceptionalScalars, referenceStorageGrowthCount: referenceStorageGrowthCount,
                scalarStorageGrowthCount: scalarStorageGrowthCount,
                lookupCapacityHighWatermark: lookupCapacityHighWatermark,
                lookupStorageGrowthCount: lookupStorageGrowthCount)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Returns one genuine removed restoration. Nil is missing evidence, never numeric zero.
    func suppressedRowExit(at index: Int) -> PlaybackSongRowExitProvenance.Observation? {
        let evidence = rowExitProvenance
        guard evidence.coverage == .suppressedRowExitsV1, let domain = evidence.domain,
              evidence.references.indices.contains(index) else { return nil }
        let reference = evidence.references[index]
        let outgoing = reference.outgoingDiagnosticIndex
        let source: PlaybackPosition
        let row: Int, channel: Int, rowSpeed: Int
        let generation: Int?
        let scalar: PlaybackSongRowExitProvenance.ScalarWitness
        let cause: PlaybackSongRowExitProvenance.Cause
        if reference.witness == .arpeggioDiagnostic {
            guard diagnostics.arpeggioEffects.indices.contains(outgoing), reference.witnessIndex == outgoing else { return nil }
            let command = diagnostics.arpeggioEffects[outgoing]
            guard let child = command.subsumedRowExit,
                  let raw = PlaybackSongRowExitProvenance.scalar(child, domain: domain) else { return nil }
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            rowSpeed = command.rowSpeed; generation = command.activeEventIndex; scalar = raw
            cause = .arpeggioExitSubsumed
        } else {
            guard diagnostics.vibratoEffects.indices.contains(outgoing) else { return nil }
            let command = diagnostics.vibratoEffects[outgoing]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            rowSpeed = command.rowSpeed; generation = command.activeEventIndex
            cause = .vibratoExitCoalesced
            switch reference.witness {
            case .nativeWriterSpan:
                guard nativePitchWriterSpans.coverage == .partialChildBearingProducersV1,
                      nativePitchWriterSpans.domain == domain,
                      nativePitchWriterSpans.spans.indices.contains(reference.witnessIndex) else { return nil }
                let span = nativePitchWriterSpans.spans[reference.witnessIndex]
                guard span.family == .vibrato, span.diagnosticIndex == outgoing,
                      span.originalChildren.indices.contains(span.capturedChildCount),
                      span.capturedChildCount == span.originalChildren.count - 1,
                      let raw = PlaybackSongRowExitProvenance.scalar(span.originalChildren[span.capturedChildCount],
                        domain: domain) else { return nil }
                scalar = raw
            case .exceptionalScalar:
                guard evidence.exceptionalScalars.indices.contains(reference.witnessIndex) else { return nil }
                scalar = evidence.exceptionalScalars[reference.witnessIndex]
            case .arpeggioDiagnostic: return nil
            }
        }
        guard let generation, row >= 0, scalar.syntheticTick == rowSpeed,
              matchesIncomingRowExit(reference, outgoingRow: row, channel: channel,
                generation: generation, frame: scalar.scheduledFrame) else { return nil }
        return .init(cause: cause, outgoingDiagnosticIndex: outgoing, incomingFamily: reference.incomingFamily,
            incomingDiagnosticIndex: reference.incomingDiagnosticIndex, source: source,
            syntheticRow: row, channelIndex: channel, associatedGeneration: generation,
            syntheticTick: scalar.syntheticTick, scheduledFrame: scalar.scheduledFrame, domain: domain,
            nativePeriodBefore: scalar.nativePeriodBefore, nativePeriodAfter: scalar.nativePeriodAfter,
            witness: reference.witness)
    }

    private func matchesIncomingRowExit(_ reference: PlaybackSongRowExitProvenance.Reference,
        outgoingRow: Int, channel: Int, generation: Int, frame: Int) -> Bool {
        let index = reference.incomingDiagnosticIndex
        let row: Int, incomingChannel: Int, tick: Int
        let incomingGeneration: Int?, incomingFrame: Int?
        switch reference.incomingFamily {
        case .arpeggio:
            guard diagnostics.arpeggioEffects.indices.contains(index) else { return false }
            let command = diagnostics.arpeggioEffects[index]
            row = command.syntheticRow; incomingChannel = command.channelIndex
            tick = command.stepUpdates.first?.syntheticTick ?? -1
            incomingFrame = command.stepUpdates.first?.scheduledFrame
            incomingGeneration = command.activeEventIndex
        case .finePortamentoUp:
            guard diagnostics.finePortamentoUpEffects.indices.contains(index) else { return false }
            let command = diagnostics.finePortamentoUpEffects[index]
            row = command.syntheticRow; incomingChannel = command.channelIndex; tick = command.syntheticTick
            incomingFrame = command.scheduledFrame; incomingGeneration = command.activeEventIndex
        case .finePortamentoDown:
            guard diagnostics.finePortamentoDownEffects.indices.contains(index) else { return false }
            let command = diagnostics.finePortamentoDownEffects[index]
            row = command.syntheticRow; incomingChannel = command.channelIndex; tick = command.syntheticTick
            incomingFrame = command.scheduledFrame; incomingGeneration = command.activeEventIndex
        case .extraFinePortamentoUp, .extraFinePortamentoDown:
            guard diagnostics.extraFinePortamentoEffects.indices.contains(index) else { return false }
            let command = diagnostics.extraFinePortamentoEffects[index]
            guard command.direction == (reference.incomingFamily == .extraFinePortamentoUp ? .up : .down) else { return false }
            row = command.syntheticRow; incomingChannel = command.channelIndex; tick = command.syntheticTick
            incomingFrame = command.scheduledFrame; incomingGeneration = command.activeEventIndex
        }
        return row > 0 && row - 1 == outgoingRow && incomingChannel == channel && tick == 0 &&
            incomingGeneration == generation && incomingFrame == frame
    }

}
