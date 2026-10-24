import Foundation

/// Explicitly partial observations of actual in-row instrument-only ED1...EDF phase resets.
/// These facts grant no autovibrato, source-eligibility or physical-publication authority.
struct PlaybackSongDelayedInstrumentResetFacts: Equatable {
    enum Coverage { case notAdapterProduced, partialInRowInstrumentOnlyEDxV1 }
    enum Cause { case existingInRowInstrumentOnlyEDxEffectPhaseResetGate }
    typealias Scalars = PlaybackSongRowEntryTriggerResetFacts.Scalars

    struct Fact: Equatable {
        let source: PlaybackPosition
        let syntheticRow: Int
        let syntheticTick: Int
        let channelIndex: Int
        let scheduledFrame: Int
        let requestedInstrumentIndex: Int
        // Prior dispatch association can name a completed/released source; it is not eligibility.
        let priorSourceEventIndex: Int?
        // Only an actual newly started outcome; nil includes source-less reset execution.
        let newSourceEventIndex: Int?
        let before: Scalars
        let after: Scalars
        var cause: Cause { .existingInRowInstrumentOnlyEDxEffectPhaseResetGate }
    }

    let coverage: Coverage
    let facts: [Fact]
    let storageGrowthCount: Int
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, facts: [], storageGrowthCount: 0)

    /// Retains only sparse scalar records, without ChannelState or numeric-child buffers.
    struct Observer {
        var facts = [Fact]()
        var storageGrowthCount = 0

        mutating func record(_ fact: Fact) {
            let capacity = facts.capacity
            facts.append(fact)
            if facts.capacity != capacity { storageGrowthCount += 1 }
        }

        var evidence: PlaybackSongDelayedInstrumentResetFacts {
            .init(coverage: .partialInRowInstrumentOnlyEDxV1, facts: facts, storageGrowthCount: storageGrowthCount)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Nil distinguishes uncaptured/skipped execution from an observed zero or source-less reset.
    func delayedInstrumentReset(at index: Int) -> PlaybackSongDelayedInstrumentResetFacts.Fact? {
        let evidence = delayedInstrumentResetFacts
        guard evidence.coverage == .partialInRowInstrumentOnlyEDxV1,
              evidence.facts.indices.contains(index) else { return nil }
        let fact = evidence.facts[index]
        guard let coordinate = canonicalTickClock.coordinate(syntheticRow: fact.syntheticRow,
                tick: fact.syntheticTick, channel: fact.channelIndex),
              fact.syntheticTick > 0, coordinate.absoluteFrame == fact.scheduledFrame,
              canonicalTickClock.rowDiagnostics[fact.syntheticRow].source == fact.source else { return nil }
        return fact
    }
}
