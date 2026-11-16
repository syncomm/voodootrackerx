import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class LoopResetContinuationTests: XCTestCase {
    private typealias R = PlaybackSongLoopResetContinuation
    private typealias P = PlaybackSongSemanticPitchProjection

    func testLastResetInputsKeepExactOriginalCoordinatesAndRemapOnlyScratchSources() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let plan = PlaybackSongSyntheticAdapter.adapt(song(linear: linear), orderIndex: 0, sampleRate: rate)
            let rowIndex = try XCTUnwrap(plan.rowEntryTriggerResetFacts.facts.indices.last)
            let delayedIndex = try XCTUnwrap(plan.delayedInstrumentResetFacts.facts.indices.last)
            let input = seed(row: rowIndex, delayed: delayedIndex)
            let roots = try XCTUnwrap(R.requiredSourceIndices(plan: plan, seed: input)).sorted()
            let map = Dictionary(uniqueKeysWithValues: roots.reversed().enumerated().map { ($0.element, $0.offset) })
            let scope = R.Scope(sourceGeneration: 11, transportEpoch: 17, sequence: 1)
            let snapshot = try XCTUnwrap(R.capture(scope: scope, plan: plan, seed: input,
                sourceMap: map, sourceIdentities: [:], importedSourceCount: 0))
            XCTAssertEqual(snapshot.factCount, 2)
            XCTAssertEqual(snapshot.rows[0].origin.fact, plan.rowEntryTriggerResetFacts.facts[rowIndex])
            XCTAssertEqual(snapshot.delayed[0].origin.fact, plan.delayedInstrumentResetFacts.facts[delayedIndex])
            var context = PlaybackSongSyntheticAdapter.AdapterRowContext()
            context.events = roots.reversed().map { plan.pattern.events[$0] }
            let imported = try XCTUnwrap(snapshot.restore(into: &context))
            XCTAssertEqual(imported.rowResetMap, [rowIndex: 0])
            XCTAssertEqual(imported.delayedResetMap, [delayedIndex: 0])
            let row = try XCTUnwrap(context.rowEntryTriggerResetObserver.facts.first)
            let delayed = try XCTUnwrap(context.delayedInstrumentResetObserver.facts.first)
            XCTAssertEqual(row.syntheticRow, -1); XCTAssertEqual(delayed.syntheticRow, -1)
            XCTAssertEqual(row.source, snapshot.rows[0].origin.fact.source)
            XCTAssertEqual(row.scheduledFrame, snapshot.rows[0].origin.fact.scheduledFrame)
            XCTAssertEqual(row.before, snapshot.rows[0].origin.fact.before)
            XCTAssertEqual(row.after, snapshot.rows[0].origin.fact.after)
            XCTAssertEqual(delayed.syntheticTick, 2)
            XCTAssertEqual(delayed.scheduledFrame, snapshot.delayed[0].origin.fact.scheduledFrame)
            XCTAssertEqual(row.priorSourceEventIndex, snapshot.rows[0].origin.fact.priorSourceEventIndex.flatMap { map[$0] })
            XCTAssertEqual(delayed.priorSourceEventIndex, snapshot.delayed[0].origin.fact.priorSourceEventIndex.flatMap { map[$0] })
            XCTAssertEqual(delayed.newSourceEventIndex, snapshot.delayed[0].origin.fact.newSourceEventIndex.flatMap { map[$0] })
            let scratch = scratchPlan(from: plan, context: context)
            XCTAssertNil(scratch.rowEntryTriggerReset(at: 0))
            XCTAssertNil(scratch.delayedInstrumentReset(at: 0))
            XCTAssertEqual(context.rowEntryTriggerResetObserver.storageGrowthCount, 0)
            XCTAssertEqual(context.delayedInstrumentResetObserver.storageGrowthCount, 0)
        } }
    }

    func testThousandCarriesKeepFlatFirstScopeAndTwoFactsWithoutParentHistory() throws {
        let original = PlaybackSongSyntheticAdapter.adapt(song(linear: true), orderIndex: 0, sampleRate: 48_000)
        let row = try XCTUnwrap(original.rowEntryTriggerResetFacts.facts.indices.last)
        let delayed = try XCTUnwrap(original.delayedInstrumentResetFacts.facts.indices.last)
        let roots = try XCTUnwrap(R.requiredSourceIndices(plan: original, seed: seed(row: row, delayed: delayed))).sorted()
        let map = Dictionary(uniqueKeysWithValues: roots.enumerated().map { ($0.element, $0.offset) })
        let firstScope = R.Scope(sourceGeneration: 11, transportEpoch: 17, sequence: 1)
        var snapshot = try XCTUnwrap(R.capture(scope: firstScope, plan: original,
            seed: seed(row: row, delayed: delayed), sourceMap: map,
            sourceIdentities: [:], importedSourceCount: 0))
        let first = snapshot
        var plan = original
        var events = roots.map { original.pattern.events[$0] }
        let births = Dictionary(uniqueKeysWithValues: roots.enumerated().map { compact, old in
            (compact, R.Birth(sourceGeneration: 11, transportEpoch: 17, birthSequence: 1, birthEventIndex: old))
        })
        let identity = Dictionary(uniqueKeysWithValues: events.indices.map { ($0, $0) })
        for sequence in 2...1_001 {
            var context = PlaybackSongSyntheticAdapter.AdapterRowContext()
            context.events = events
            let imported = try XCTUnwrap(snapshot.restore(into: &context))
            plan = scratchPlan(from: original, context: context)
            snapshot = try XCTUnwrap(R.capture(scope: .init(sourceGeneration: 11, transportEpoch: 17,
                sequence: UInt64(sequence)), plan: plan, seed: seed(row: 0, delayed: 0),
                sourceMap: identity, sourceIdentities: births, importedSourceCount: events.count,
                importedRows: imported.rowOrigins, importedDelayed: imported.delayedOrigins))
            XCTAssertEqual(snapshot.factCount, 2)
            XCTAssertEqual(snapshot.rows[0].origin, first.rows[0].origin)
            XCTAssertEqual(snapshot.delayed[0].origin, first.delayed[0].origin)
            XCTAssertEqual(snapshot.rows[0].origin.identity.scope, firstScope)
            events = context.events
        }
    }

    func testMissingSourceMissingOriginAndNonfreshImportRejectTransactionally() throws {
        let plan = PlaybackSongSyntheticAdapter.adapt(song(linear: true), orderIndex: 0, sampleRate: 48_000)
        let row = try XCTUnwrap(plan.rowEntryTriggerResetFacts.facts.indices.last)
        let delayed = try XCTUnwrap(plan.delayedInstrumentResetFacts.facts.indices.last)
        let input = seed(row: row, delayed: delayed)
        let roots = try XCTUnwrap(R.requiredSourceIndices(plan: plan, seed: input)).sorted()
        let map = Dictionary(uniqueKeysWithValues: roots.enumerated().map { ($0.element, $0.offset) })
        let scope = R.Scope(sourceGeneration: 11, transportEpoch: 17, sequence: 1)
        XCTAssertNil(R.capture(scope: scope, plan: plan, seed: input,
            sourceMap: [:], sourceIdentities: [:], importedSourceCount: 0))
        let snapshot = try XCTUnwrap(R.capture(scope: scope, plan: plan, seed: input,
            sourceMap: map, sourceIdentities: [:], importedSourceCount: 0))
        var context = PlaybackSongSyntheticAdapter.AdapterRowContext()
        XCTAssertNil(snapshot.restore(into: &context))
        XCTAssertTrue(context.rowEntryTriggerResetObserver.facts.isEmpty)
        XCTAssertTrue(context.delayedInstrumentResetObserver.facts.isEmpty)
        context.events = roots.map { plan.pattern.events[$0] }
        _ = try XCTUnwrap(snapshot.restore(into: &context))
        let oldRows = context.rowEntryTriggerResetObserver.facts
        let oldDelayed = context.delayedInstrumentResetObserver.facts
        XCTAssertNil(snapshot.restore(into: &context))
        XCTAssertEqual(context.rowEntryTriggerResetObserver.facts, oldRows)
        XCTAssertEqual(context.delayedInstrumentResetObserver.facts, oldDelayed)
        XCTAssertNil(R.capture(scope: scope, plan: scratchPlan(from: plan, context: context),
            seed: seed(row: 0, delayed: 0), sourceMap: map,
            sourceIdentities: [:], importedSourceCount: context.events.count))
        XCTAssertNil(R.requiredSourceIndices(plan: plan, seed: seed(row: Int.max, delayed: delayed)))
    }

    private func seed(row: Int, delayed: Int) -> P.ContinuationSeed {
        .init(nextOrdinal: 18, channels: [.init(base: .notEstablished, output: .notEstablished,
            incoming: .notEstablished, baseProducer: .init(.cold), outputProducer: .init(.cold),
            incomingProducer: .init(.cold), owner: .init(instrument: nil, sample: nil, carriedInstrument: nil),
            generation: -1, rawBase: nil, lastReset: .init(ordinal: 12, rowReset: row, delayedReset: delayed))],
            pending: [], automatic: .init(runs: [.init()], valid: true))
    }

    private func scratchPlan(from plan: PlaybackSongSyntheticPlan,
                             context: PlaybackSongSyntheticAdapter.AdapterRowContext) -> PlaybackSongSyntheticPlan {
        var result = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig,
            pattern: .init(rowCount: 0, events: context.events), diagnostics: plan.diagnostics)
        result.rowEntryTriggerResetFacts = context.rowEntryTriggerResetObserver.evidence
        result.delayedInstrumentResetFacts = context.delayedInstrumentResetObserver.evidence
        return result
    }

    private func song(linear: Bool) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: [0.25, -0.25, 0.125, -0.125], volume: 0.5,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 4, loopType: 1)
        let cells = [PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 0, instrument: 1, volumeColumn: 0, effectType: 14, effectParam: 0xD2),
            PlaybackCell(note: 53, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)]
        let pattern = PlaybackPattern(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })
        return PlaybackSong(title: "Public bounded reset inputs", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: pattern], instrumentsByIndex: [1: .init(index: 1,
                samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125),
            usesLinearFrequencyTable: linear)
    }
}
