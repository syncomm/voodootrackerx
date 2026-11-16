import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Exercises the real row dispatcher and shared finish with fresh scratch per batch.
/// It deliberately excludes arp/vibrato pending exits; their semantic seed tests own those.
final class LoopScratchCompactionTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    typealias Scratch = PlaybackSongLoopContinuation
    typealias Renderer = PlaybackSongOfflineRenderer

    func testAThousandActualLoopBatchesKeepSourceBindingsAndStorageBounded() throws {
        let input = song([[c(1, 1)], [c()], [c(note: 49, instrument: 1)], [c()]])
        let order = [2, 3, 0, 1]
        let expandedRows = (0..<1_000).flatMap { _ in order.map { input.patternsByIndex[0]!.rows[$0] } }
        let expanded = PlaybackSong(title: input.title, orders: input.orders,
            patternsByIndex: [0: .init(index: 0, rows: expandedRows)], instrumentsByIndex: input.instrumentsByIndex,
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: input.initialTiming,
            usesLinearFrequencyTable: true)
        let whole = Adapter.adapt(expanded, orderIndex: 0, sampleRate: 44_100)
        let expectedPitch = Renderer.PitchSourceHistory(plan: whole)
        var timing = PlaybackSongFxxTimingPlanner.State(speed: 3, bpm: 125, nextExactFrame: 0)
        var previous: Batch?
        for index in 0..<1_000 {
            let current = try execute(input, rows: order, timing: &timing, predecessor: previous, sequence: UInt64(index + 1))
            XCTAssertEqual(current.export.checkpoint.sourceCount, 1)
            XCTAssertEqual(current.export.checkpoint.channelCount, 1)
            XCTAssertEqual(current.export.checkpoint.selectionInputCount, 1)
            XCTAssertLessThanOrEqual(current.export.checkpoint.selectionOriginCount, 5)
            XCTAssertLessThanOrEqual(current.scratchEventCount, 2)
            XCTAssertLessThanOrEqual(current.scratchSelectionCount, 2)
            XCTAssertEqual(current.rowCaptureCount, 4)
            XCTAssertEqual(current.emittedBirthIndices, [current.importedSourceCount])
            XCTAssertEqual(current.export.checkpoint.sources[0].birth.birthSequence, UInt64(index + 1))
            XCTAssertEqual(current.export.checkpoint.sources[0].birth.birthEventIndex, current.importedSourceCount)
            var expected = whole.xmChannelRows[(index + 1) * 4 - 1].controls
            expected.activeEventIndex = 0; expected.activeEventMappingIndex = 0
            XCTAssertEqual(current.export.checkpoint.channels[0], expected, "batch \(index)")
            XCTAssertEqual(current.export.checkpoint.sources[0].pitch,
                expectedPitch.checkpoint(for: index, before: Int(timing.nextExactFrame.rounded(.down))))
            if let previous {
                XCTAssertEqual(current.importedIdentities[0], previous.export.checkpoint.sources[0].birth)
                XCTAssertEqual(current.export.sourceMap[current.importedSourceCount], 0)
            }
            XCTAssertTrue(current.rows.allSatisfy { $0.value == nil })
            previous = current
        }
    }

    func testBlankAndSlideImportsKeepTheOriginalBirthAndActualWriterAnchor() throws {
        let input = song([[c(note: 49, instrument: 1)], [c()], [c(1, 1)]])
        var timing = PlaybackSongFxxTimingPlanner.State(speed: 3, bpm: 125, nextExactFrame: 0)
        var previous = try execute(input, rows: [0], timing: &timing, sequence: 1)
        let birth = previous.export.checkpoint.sources[0].birth
        let birthFrame = previous.export.checkpoint.sources[0].birthAbsoluteFrame
        for index in 2...101 {
            let prior = previous.export.checkpoint.sources[0].pitch
            let current = try execute(input, rows: [index.isMultiple(of: 2) ? 1 : 2], timing: &timing,
                predecessor: previous, sequence: UInt64(index))
            XCTAssertTrue(current.emittedBirthIndices.isEmpty)
            XCTAssertEqual(current.export.checkpoint.sources[0].birth, birth)
            XCTAssertEqual(current.export.checkpoint.sources[0].birthAbsoluteFrame, birthFrame)
            XCTAssertEqual(current.importedIdentities[0], birth)
            XCTAssertEqual(current.export.checkpoint.sources[0].event.scheduledStartFrame, birthFrame)
            if index.isMultiple(of: 2) { XCTAssertEqual(current.export.checkpoint.sources[0].pitch, prior) }
            else { XCTAssertGreaterThan(current.export.checkpoint.sources[0].pitch.lastWriterFrame, prior.lastWriterFrame) }
            XCTAssertTrue(current.rows.allSatisfy { $0.value == nil })
            previous = current
        }
    }

    func testActualEmptyRouteDropsSourceZeroAndRemapsSourceOneWithoutNewBirth() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/empty-slot-playback-state.xm")
        let input = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        var timing = PlaybackSongFxxTimingPlanner.State(speed: 6, bpm: 125, nextExactFrame: 0)
        let first = try execute(input, rows: [0, 1, 2, 3], timing: &timing, sequence: 1)
        XCTAssertEqual(first.export.sourceMap, [1: 0])
        XCTAssertEqual(first.export.checkpoint.sourceCount, 1)
        XCTAssertNil(first.export.checkpoint.channels[0].activeEventIndex)
        XCTAssertEqual(first.export.checkpoint.channels[1].activeEventIndex, 0)
        XCTAssertEqual(first.export.checkpoint.channels[1].activeEventMappingIndex, 0)
        XCTAssertEqual(first.export.checkpoint.sources[0].birth.birthEventIndex, 1)
        let before = first.export.checkpoint.channels[0]
        var context = Adapter.AdapterRowContext()
        let imported = try first.export.checkpoint.restore(into: &context,
            source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 4),
            batchStartFrame: Int(timing.nextExactFrame.rounded(.down)), linear: true)
        XCTAssertEqual(context.channelStates[0], before)
        XCTAssertEqual(context.globalVolumeState, first.export.checkpoint.globalVolume)
        XCTAssertEqual(context.importedSourceCount, 1)
        XCTAssertTrue(context.initialHeldPitchEventIndices.isEmpty)
        XCTAssertEqual(context.selectionFacts[0].role, .continuationInput)
        XCTAssertEqual(context.selectionFacts[0].baseRateOrigin,
            before.activeSampleBaseSampleRate == nil ? .absent : .continuationInput)
        XCTAssertEqual(context.selectionFacts[0].semanticSample, before.semanticSampleIndex)
        XCTAssertEqual(context.selectionFacts[0].associatedGeneration, nil)
        XCTAssertEqual(imported.sourceIdentities[0], first.export.checkpoint.sources[0].birth)
        XCTAssertTrue(context.xmChannelRows.isEmpty)
        let next = try execute(input, rows: [4], timing: &timing, predecessor: first, sequence: 2)
        XCTAssertTrue(next.emittedBirthIndices.isEmpty)
        XCTAssertEqual(next.export.checkpoint.sources[0].birth, first.export.checkpoint.sources[0].birth)
        XCTAssertNil(next.export.checkpoint.channels[0].activeEventIndex)
        XCTAssertTrue(next.rows.allSatisfy { $0.value == nil })
    }

    func testHeldKnownMissingAndUnestablishedRemainDistinctAndOwnerOverrideDoesNotRebindHeld() throws {
        let input = song([[c()], [c(note: 49, instrument: 1)], [c(12, 32)]])
        var timing = PlaybackSongFxxTimingPlanner.State(speed: 3, bpm: 125, nextExactFrame: 0)
        let cold = try execute(input, rows: [0], timing: &timing, sequence: 1)
        XCTAssertEqual(cold.export.checkpoint.heldInputs, [.notEstablished])
        let selected = try execute(input, rows: [1], timing: &timing, predecessor: cold, sequence: 2,
            ownerOverrides: [0: .init(instrument: 2, sample: 0, carriedInstrument: 2, sourceEventIndex: 0)])
        XCTAssertEqual(selected.export.checkpoint.selectionInputCount, 2)
        var context = Adapter.AdapterRowContext()
        let imported = try selected.export.checkpoint.restore(into: &context,
            source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2),
            batchStartFrame: Int(timing.nextExactFrame.rounded(.down)), linear: true)
        XCTAssertEqual(context.selectionFacts.count, 2)
        XCTAssertEqual(context.selectionFacts[0].semanticInstrument, 2)
        XCTAssertEqual(context.selectionFacts[1].semanticInstrument, 1)
        XCTAssertEqual(context.selectionFacts[0].associatedGeneration, 0)
        XCTAssertEqual(context.selectionFacts[1].associatedGeneration, 0)
        guard case let .known(known) = context.heldPitchObserver.channels[0] else { return XCTFail("lost known held value") }
        XCTAssertEqual(known.producer, .continuationInput)
        XCTAssertEqual(known.selectionFactIndex, 1)
        XCTAssertEqual(imported.ownerFactIndices, [0])
        XCTAssertNotNil(selected.export.checkpoint.selectionOrigins[0].heldProducer)
        let unmodeled = try execute(input, rows: [2], timing: &timing, predecessor: selected, sequence: 3)
        XCTAssertEqual(unmodeled.export.checkpoint.heldInputs, [.notCaptured])
        XCTAssertEqual(unmodeled.export.checkpoint.selectionInputCount, 1)
    }

    private final class WeakRow {
        weak var value: PlaybackXMChannelRow?
        init(_ row: PlaybackXMChannelRow) { value = row }
    }

    private struct Batch {
        let export: Scratch.Export
        let fold: Adapter.ContinuationFoldInput
        let importedIdentities: [Int: RuntimeLoopNativeSourceIdentity]
        let importedSourceCount: Int
        let emittedBirthIndices: [Int]
        let scratchEventCount: Int
        let scratchSelectionCount: Int
        let rowCaptureCount: Int
        let rows: [WeakRow]
    }

    private func execute(_ input: PlaybackSong, rows indices: [Int],
        timing state: inout PlaybackSongFxxTimingPlanner.State, predecessor: Batch? = nil,
        sequence: UInt64, ownerOverrides: [Int: Scratch.OwnerObservation] = [:]) throws -> Batch {
        let pattern = try XCTUnwrap(input.patternsByIndex[0])
        let visits = indices.enumerated().map { local, index in
            PlaybackSongTraversalRow(source: .init(orderIndex: 0, patternIndex: 0, rowIndex: pattern.rows[index].index),
                orderIndex: 0, pattern: pattern, row: pattern.rows[index], rowArrayIndex: index, syntheticRow: local)
        }
        let traversal = PlaybackSongTraversalPlan(rows: visits, adaptedOrders: [], traversalDiagnostics: [],
            pathLength: visits.count, stopReason: .selectedRangeEnd, guardHit: false)
        let timing = PlaybackSongFxxTimingPlanner.plan(input, traversalPlan: traversal, sampleRate: 44_100, initialState: state)
        let start = timing.frameFor(row: 0), end = timing.frameFor(row: visits.count)
        var context = Adapter.AdapterRowContext()
        let imported = try predecessor?.export.checkpoint.restore(into: &context, source: visits[0].source,
            batchStartFrame: start, linear: input.usesLinearFrequencyTable) ?? Scratch.Import()
        let importedCount = context.importedSourceCount
        for visit in visits {
            let diagnostic = Adapter.appendEvents(from: visit.row, source: visit.source, syntheticRow: visit.syntheticRow,
                song: input, timingConfig: timing.timingConfig(forSyntheticRow: visit.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: visit.syntheticRow), context: &context)
            context.rowDiagnostics.append(diagnostic)
        }
        // No second semantics implementation: all effect/state histories came from appendEvents.
        let continuation = Adapter.ContinuationFoldInput(batchStartFrame: start,
            importedEventIndices: Set(0..<importedCount), envelope: predecessor?.fold.envelope,
            audible: predecessor?.fold.audible, pitch: imported.pitchSeed)
        var output: Adapter.ContinuationFoldOutput?
        let plan = try XCTUnwrap(Adapter.finishAdaptation(song: input, startOrderIndex: 0, orderCount: 1,
            timingPlan: timing, traversalPlan: traversal, timingConfig: timing.timingConfig(forSyntheticRow: 0),
            rowMappings: visits.map { .init(source: $0.source, syntheticRow: $0.syntheticRow) },
            clockRuns: [], canonicalTickCount: 0, context: &context,
            automaticPitchBuilder: .init(), profileSession: nil, totalStart: nil,
            eligibilityOracle: nil, isCancelled: nil, continuation: continuation, terminalCheckpoint: { output = $0 }))
        let terminal = try XCTUnwrap(output)
        let exported = try Scratch.export(scope: .init(sourceGeneration: 17, transportEpoch: 23, sequence: sequence),
            song: input, context: context, plan: plan, boundaryFrame: end,
            sourceIdentities: imported.sourceIdentities, pitch: terminal.pitch,
            importedSelectionOrigins: imported.selectionOrigins, ownerOverrides: ownerOverrides)
        var envelope = terminal.envelope
        for channel in envelope.keys {
            if let old = envelope[channel]?.route?.sourceEventIndex {
                envelope[channel]?.route?.sourceEventIndex = exported.sourceMap[old]
            }
        }
        let audible = terminal.audible.reduce(into: [Int: PlaybackXMAudibleTimeline.SourceCheckpoint]()) { result, entry in
            if let index = exported.sourceMap[entry.key] { result[index] = entry.value }
        }
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 44_100,
            preparedPlan: plan, lookupOnlySourceCount: importedCount)
        let births = runtime.events.compactMap { event -> Int? in
            if case .noteTrigger = event.action { return event.activeEventIndex }; return nil
        }
        state = timing.terminalState
        return .init(export: exported, fold: .init(batchStartFrame: end,
            importedEventIndices: Set(exported.checkpoint.sources.indices), envelope: envelope,
            audible: audible, pitch: [:]), importedIdentities: imported.sourceIdentities,
            importedSourceCount: importedCount, emittedBirthIndices: births,
            scratchEventCount: context.events.count, scratchSelectionCount: context.selectionFacts.count,
            rowCaptureCount: context.xmChannelRows.count, rows: context.xmChannelRows.map(WeakRow.init))
    }

    private func c(_ effect: UInt8 = 0, _ param: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: param)
    }

    private func song(_ rows: [[PlaybackCell]]) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        return .init(title: "Bounded scratch", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: true)
    }
}
