import Foundation

/// Bounded scalar reset inputs. Original execution coordinates and birth identities
/// remain flat provenance; imported rows never claim a new canonical execution.
struct PlaybackSongLoopResetContinuation: Equatable {
    typealias Adapter = PlaybackSongSyntheticAdapter
    typealias Seed = PlaybackSongSemanticPitchProjection.ContinuationSeed
    typealias Scope = PlaybackSongLoopContinuation.Scope
    typealias Identity = PlaybackSongLoopContinuation.FactIdentity
    typealias Birth = RuntimeLoopNativeSourceIdentity
    typealias RowFact = PlaybackSongRowEntryTriggerResetFacts.Fact
    typealias DelayedFact = PlaybackSongDelayedInstrumentResetFacts.Fact

    struct RowOrigin: Equatable {
        let identity: Identity
        let fact: RowFact
        let priorBirth: Birth?
    }
    struct DelayedOrigin: Equatable {
        let identity: Identity
        let fact: DelayedFact
        let priorBirth: Birth?
        let newBirth: Birth?
    }
    struct RowInput: Equatable {
        let oldIndex: Int
        let origin: RowOrigin
        let priorSourceIndex: Int?
    }
    struct DelayedInput: Equatable {
        let oldIndex: Int
        let origin: DelayedOrigin
        let priorSourceIndex: Int?
        let newSourceIndex: Int?
    }
    struct Import {
        let rowResetMap: [Int: Int]
        let delayedResetMap: [Int: Int]
        let rowOrigins: [Int: RowOrigin]
        let delayedOrigins: [Int: DelayedOrigin]
    }
    let rows: [RowInput]
    let delayed: [DelayedInput]
    var factCount: Int { rows.count + delayed.count }

    /// Supplies the source compactor's bounded extra roots before indices are rebased.
    /// Nil rejects a malformed last-reset reference rather than dropping its evidence.
    static func requiredSourceIndices(plan: borrowing PlaybackSongSyntheticPlan,
                                     seed: borrowing Seed) -> Set<Int>? {
        guard let selected = Self.references(plan: plan, seed: seed) else { return nil }
        var result = Set<Int>()
        for index in selected.rows {
            if let old = plan.rowEntryTriggerResetFacts.facts[index].priorSourceEventIndex {
                guard plan.pattern.events.indices.contains(old) else { return nil }
                result.insert(old)
            }
        }
        for index in selected.delayed {
            let fact = plan.delayedInstrumentResetFacts.facts[index]
            for old in [fact.priorSourceEventIndex, fact.newSourceEventIndex].compactMap({ $0 }) {
                guard plan.pattern.events.indices.contains(old) else { return nil }
                result.insert(old)
            }
        }
        return result
    }

    /// Copies only the last reset references used by the terminal semantic seed.
    /// Imported origins retain their first scope and fact; they never form a chain.
    static func capture(scope: Scope, plan: borrowing PlaybackSongSyntheticPlan,
        seed: borrowing Seed, sourceMap: [Int: Int], sourceIdentities: [Int: Birth],
        importedSourceCount: Int, importedRows: [Int: RowOrigin] = [:],
        importedDelayed: [Int: DelayedOrigin] = [:],
        trustedCarriedBirths: Set<Birth> = [], trustedOriginScopes: Set<Scope> = []) -> Self? {
        guard scope.sequence > 0, importedSourceCount >= 0,
              importedSourceCount <= plan.pattern.events.count,
              let selected = Self.references(plan: plan, seed: seed) else { return nil }
        func mapped(_ old: Int?) -> Int?? {
            guard let old else { return .some(nil) }
            guard let value = sourceMap[old], value >= 0, value < sourceMap.count else { return nil }
            return .some(value)
        }
        func birth(_ old: Int?) -> Birth?? {
            guard let old else { return .some(nil) }
            guard plan.pattern.events.indices.contains(old) else { return nil }
            let value: Birth
            if let existing = sourceIdentities[old] { value = existing }
            else {
                guard old >= importedSourceCount else { return nil }
                value = .init(sourceGeneration: scope.sourceGeneration, transportEpoch: scope.transportEpoch,
                    birthSequence: scope.sequence, birthEventIndex: old)
            }
            let trustedImport = old < importedSourceCount && sourceIdentities[old] == value && trustedCarriedBirths.contains(value)
            guard (value.sourceGeneration == scope.sourceGeneration || trustedImport),
                  value.transportEpoch == scope.transportEpoch else { return nil }
            return .some(value)
        }
        var rows = [RowInput](), delayed = [DelayedInput]()
        for index in selected.rows {
            let fact = plan.rowEntryTriggerResetFacts.facts[index]
            guard let prior = mapped(fact.priorSourceEventIndex),
                  let priorBirth = birth(fact.priorSourceEventIndex) else { return nil }
            let origin: RowOrigin
            if fact.syntheticRow == -1 {
                guard let imported = importedRows[index],
                      (imported.identity.scope.sourceGeneration == scope.sourceGeneration || trustedOriginScopes.contains(imported.identity.scope)),
                      imported.identity.scope.transportEpoch == scope.transportEpoch,
                      imported.priorBirth == priorBirth,
                      copy(imported.fact, prior: fact.priorSourceEventIndex) == fact else { return nil }
                origin = imported
            } else {
                guard plan.rowEntryTriggerReset(at: index) == fact else { return nil }
                origin = .init(identity: .init(scope: scope, originalFactIndex: index),
                    fact: fact, priorBirth: priorBirth)
            }
            rows.append(.init(oldIndex: index, origin: origin, priorSourceIndex: prior))
        }
        for index in selected.delayed {
            let fact = plan.delayedInstrumentResetFacts.facts[index]
            guard let prior = mapped(fact.priorSourceEventIndex), let new = mapped(fact.newSourceEventIndex),
                  let priorBirth = birth(fact.priorSourceEventIndex),
                  let newBirth = birth(fact.newSourceEventIndex) else { return nil }
            let origin: DelayedOrigin
            if fact.syntheticRow == -1 {
                guard let imported = importedDelayed[index],
                      (imported.identity.scope.sourceGeneration == scope.sourceGeneration || trustedOriginScopes.contains(imported.identity.scope)),
                      imported.identity.scope.transportEpoch == scope.transportEpoch,
                      imported.priorBirth == priorBirth,
                      imported.newBirth == newBirth,
                      copy(imported.fact, prior: fact.priorSourceEventIndex, new: fact.newSourceEventIndex) == fact else { return nil }
                origin = imported
            } else {
                guard plan.delayedInstrumentReset(at: index) == fact else { return nil }
                origin = .init(identity: .init(scope: scope, originalFactIndex: index),
                    fact: fact, priorBirth: priorBirth, newBirth: newBirth)
            }
            delayed.append(.init(oldIndex: index, origin: origin, priorSourceIndex: prior, newSourceIndex: new))
        }
        return .init(rows: rows, delayed: delayed)
    }

    /// Adds lookup-only scalar inputs before the first real local row zero.
    /// Existing firstRowReset/firstDelayedReset offsets exclude this prefix from execution.
    func restore(into context: inout Adapter.AdapterRowContext) -> Import? {
        guard context.rowEntryTriggerResetObserver.facts.isEmpty,
              context.delayedInstrumentResetObserver.facts.isEmpty else { return nil }
        func valid(_ index: Int?) -> Bool { index.map { context.events.indices.contains($0) } ?? true }
        guard rows.allSatisfy({ valid($0.priorSourceIndex) }),
              delayed.allSatisfy({ valid($0.priorSourceIndex) && valid($0.newSourceIndex) }) else { return nil }
        var rowMap = [Int: Int](), delayedMap = [Int: Int]()
        var rowOrigins = [Int: RowOrigin](), delayedOrigins = [Int: DelayedOrigin]()
        for (index, input) in rows.enumerated() {
            guard rowMap.updateValue(index, forKey: input.oldIndex) == nil else { return nil }
            rowOrigins[index] = input.origin
        }
        for (index, input) in delayed.enumerated() {
            guard delayedMap.updateValue(index, forKey: input.oldIndex) == nil else { return nil }
            delayedOrigins[index] = input.origin
        }
        // Assign only after every bound and identity check; no imported record is
        // recorded as another reset invocation or promoted to a canonical tick.
        context.rowEntryTriggerResetObserver.facts = rows.map { Self.copy($0.origin.fact, prior: $0.priorSourceIndex) }
        context.delayedInstrumentResetObserver.facts = delayed.map {
            Self.copy($0.origin.fact, prior: $0.priorSourceIndex, new: $0.newSourceIndex)
        }
        return .init(rowResetMap: rowMap, delayedResetMap: delayedMap,
            rowOrigins: rowOrigins, delayedOrigins: delayedOrigins)
    }

    private static func references(plan: borrowing PlaybackSongSyntheticPlan,
                                   seed: borrowing Seed) -> (rows: [Int], delayed: [Int])? {
        var rows = Set<Int>(), delayed = Set<Int>()
        for (channel, input) in seed.channels.enumerated() {
            guard let reset = input.lastReset else { continue }
            if reset.rowReset >= 0 {
                guard plan.rowEntryTriggerResetFacts.facts.indices.contains(reset.rowReset),
                      plan.rowEntryTriggerResetFacts.facts[reset.rowReset].channelIndex == channel else { return nil }
                rows.insert(reset.rowReset)
            }
            if reset.delayedReset >= 0 {
                guard plan.delayedInstrumentResetFacts.facts.indices.contains(reset.delayedReset),
                      plan.delayedInstrumentResetFacts.facts[reset.delayedReset].channelIndex == channel else { return nil }
                delayed.insert(reset.delayedReset)
            }
        }
        return (rows.sorted(), delayed.sorted())
    }

    private static func copy(_ fact: RowFact, prior: Int?) -> RowFact {
        .init(source: fact.source, syntheticRow: -1, channelIndex: fact.channelIndex,
            scheduledFrame: fact.scheduledFrame, priorSourceEventIndex: prior,
            before: fact.before, after: fact.after, rowCell: fact.rowCell)
    }
    private static func copy(_ fact: DelayedFact, prior: Int?, new: Int?) -> DelayedFact {
        .init(source: fact.source, syntheticRow: -1, syntheticTick: fact.syntheticTick,
            channelIndex: fact.channelIndex, scheduledFrame: fact.scheduledFrame,
            requestedInstrumentIndex: fact.requestedInstrumentIndex,
            priorSourceEventIndex: prior, newSourceEventIndex: new,
            before: fact.before, after: fact.after)
    }
}
