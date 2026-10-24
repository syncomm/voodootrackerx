import Foundation

/// Explicitly partial evidence of the actual effect-phase reset in prepareTremoloRow.
/// This is neither complete instrument-reset coverage nor an autovibrato reset policy.
struct PlaybackSongRowEntryTriggerResetFacts: Equatable {
    enum Coverage { case notAdapterProduced, partialOrdinaryRowEntryV1 }
    enum Cause { case existingOrdinaryRowEntryInstrumentTriggerEffectPhaseGate }

    struct Scalars: Equatable {
        let vibratoPhase: Int
        let tremoloPhase: Int
        let tremoloVibratoPhase: Int
        let vibratoRetriggerSuppressed: Bool?
        let tremoloRetriggerSuppressed: Bool
        let tremoloVibratoRetriggerSuppressed: Bool
        let rRetriggerCounter: UInt8

        init(_ state: borrowing PlaybackSongSyntheticAdapter.ChannelState) {
            vibratoPhase = state.vibratoPhase
            tremoloPhase = state.tremolo.phase
            tremoloVibratoPhase = state.tremoloVibratoPhase
            vibratoRetriggerSuppressed = state.vibratoControl?.retriggerSuppressed
            tremoloRetriggerSuppressed = state.tremolo.control & 4 != 0
            tremoloVibratoRetriggerSuppressed = state.tremoloVibratoControl & 4 != 0
            rRetriggerCounter = state.rRetriggerCounter
        }
    }

    struct Fact: Equatable {
        let source: PlaybackPosition
        let syntheticRow: Int
        let channelIndex: Int
        let scheduledFrame: Int
        let priorSourceEventIndex: Int?
        let before: Scalars
        let after: Scalars
        let rowCell: PlaybackCell
        var requestedInstrumentIndex: Int { Int(rowCell.instrument) }
        var syntheticTick: Int { 0 }
        var cause: Cause { .existingOrdinaryRowEntryInstrumentTriggerEffectPhaseGate }
    }

    let coverage: Coverage
    let facts: [Fact]
    let storageGrowthCount: Int
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, facts: [], storageGrowthCount: 0)

    /// Owns only small scalar records, never ChannelState or diagnostic-child backing storage.
    struct Observer {
        var facts = [Fact]()
        var storageGrowthCount = 0

        mutating func record(_ fact: Fact) {
            let capacity = facts.capacity
            facts.append(fact)
            if facts.capacity != capacity { storageGrowthCount += 1 }
        }

        var evidence: PlaybackSongRowEntryTriggerResetFacts {
            .init(coverage: .partialOrdinaryRowEntryV1, facts: facts, storageGrowthCount: storageGrowthCount)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Nil means no captured invocation; an observed zero or absent source remains a fact.
    func rowEntryTriggerReset(at index: Int) -> PlaybackSongRowEntryTriggerResetFacts.Fact? {
        let evidence = rowEntryTriggerResetFacts
        guard evidence.coverage == .partialOrdinaryRowEntryV1,
              evidence.facts.indices.contains(index) else { return nil }
        let fact = evidence.facts[index]
        guard let coordinate = canonicalTickClock.coordinate(syntheticRow: fact.syntheticRow,
                tick: fact.syntheticTick, channel: fact.channelIndex),
              coordinate.absoluteFrame == fact.scheduledFrame,
              canonicalTickClock.rowDiagnostics[fact.syntheticRow].source == fact.source else { return nil }
        return fact
    }
}
