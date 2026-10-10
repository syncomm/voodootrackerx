import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class PitchSourceHistoryTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    typealias Renderer = PlaybackSongOfflineRenderer

    func testIndexedPredicateMatchesScanAcrossSourceAndWriterBoundaries() {
        for rate in [44_100.0, 48_000] {
            for loop in [0, 1, 2] {
                let plan = Adapter.adapt(song(lifecycleRows(), loop: loop, sampleFrames: loop == 0 ? 4096 : 64),
                                         startOrderIndex: 0, orderCount: 2, sampleRate: rate)
                let history = Renderer.PitchSourceHistory(plan: plan)
                let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
                var frames = Set([0, 1, Int.max])
                for event in plan.pattern.events { frames.insert(scheduler.frame(for: event)) }
                for row in plan.diagnostics.rowTiming { frames.insert(row.rowStartFrame) }
                for cut in plan.diagnostics.noteCutEffects { if let frame = cut.scheduledFrame { frames.insert(frame) } }
                for retrigger in plan.diagnostics.retriggerEffects { frames.formUnion(retrigger.retriggerFrames) }
                for update in plan.diagnostics.vibratoEffects.flatMap(\.stepUpdates) { frames.insert(update.scheduledFrame) }
                for frame in Array(frames) where frame > 0 && frame < Int.max {
                    frames.insert(frame - 1); frames.insert(frame + 1)
                }
                for source in -1...plan.pattern.events.count {
                    for frame in frames {
                        XCTAssertEqual(Renderer.hasActiveSource(eventIndex: source, at: frame, plan: plan, pitchHistory: history),
                                       Renderer.hasActiveSource(eventIndex: source, at: frame, plan: plan),
                                       "source=\(source), frame=\(frame), loop=\(loop)")
                    }
                }
            }
        }
    }

    func testEmptyRouteCutIsInclusiveAndDoesNotRetireTheNextGeneration() throws {
        let plan = Adapter.adapt(song([[c(note: 49, instrument: 1)], [c(note: 50)],
                                       [c(14, 0x10)], [c(note: 49)], [c(33, 0x10)]]),
                                 startOrderIndex: 0, orderCount: 2, sampleRate: 48_000)
        let route = try XCTUnwrap(plan.xmEmptyRoutes.first)
        let source = try XCTUnwrap(route.stoppedEventIndex)
        let history = Renderer.PitchSourceHistory(plan: plan)
        XCTAssertEqual(history.cutFrame(for: source), route.scheduledFrame)
        XCTAssertTrue(Renderer.hasActiveSource(eventIndex: source, at: route.scheduledFrame - 1, plan: plan, pitchHistory: history))
        XCTAssertFalse(Renderer.hasActiveSource(eventIndex: source, at: route.scheduledFrame, plan: plan, pitchHistory: history))
        let last = plan.pattern.events.count - 1
        let start = SyntheticTrackerScheduler(config: plan.timingConfig).frame(for: plan.pattern.events[last])
        XCTAssertNotEqual(last, source)
        XCTAssertTrue(Renderer.hasActiveSource(eventIndex: last, at: start, plan: plan, pitchHistory: history))
        XCTAssertNotNil(plan.xmChannelRows.first { $0.controls.activeEventIndex == nil && $0.controls.activeLinearPeriod != nil })
        XCTAssertTrue(plan.diagnostics.finePortamentoUpEffects.contains { $0.execution.canonicalPitchValid && !$0.execution.sourceEligible })
    }

    func testCompletedAndUninitializedPitchDoNotGainAPlaybackSource() {
        let completed = Adapter.adapt(song([[c(note: 49, instrument: 1)], [c(14, 0x13)], [c(33, 0x12)]], loop: 0),
                                      startOrderIndex: 0, orderCount: 2, sampleRate: 48_000)
        XCTAssertTrue(completed.diagnostics.finePortamentoUpEffects.allSatisfy { !$0.execution.sourceEligible && $0.stepUpdates.isEmpty })
        XCTAssertTrue(completed.diagnostics.extraFinePortamentoEffects.allSatisfy { !$0.execution.sourceEligible && $0.stepUpdates.isEmpty })
        let empty = Adapter.adapt(song([[c(14, 0x10)], [c(33, 0x10)]]), startOrderIndex: 0, orderCount: 2, sampleRate: 48_000)
        XCTAssertTrue(empty.pattern.events.isEmpty)
        XCTAssertTrue(empty.diagnostics.finePortamentoUpEffects.allSatisfy { !$0.execution.canonicalPitchValid && !$0.execution.sourceEligible })
        XCTAssertTrue(empty.diagnostics.extraFinePortamentoEffects.allSatisfy { !$0.execution.canonicalPitchValid && !$0.execution.sourceEligible })
    }

    #if DEBUG
    func testG17G18ExactPlanPayloadOrderingAndWindowEquivalence() throws {
        for rate in [44_100.0, 48_000] {
            for module in [song(lifecycleRows()), song(lifecycleRows(), loop: 0),
                           song(lifecycleRows(), loop: 0, sampleFrames: 4096), song(lifecycleRows(), envelope: true)] {
                for start in [0, 1] {
                    let count = module.orders.count - start
                    let indexed = Adapter.adapt(module, startOrderIndex: start, orderCount: count, sampleRate: rate)
                    let scanned = Adapter.adaptUsingScanEligibility(module, startOrderIndex: start, orderCount: count, sampleRate: rate)
                    XCTAssertEqual(indexed, scanned) // All identities, diagnostics, eligibility, payloads and writer order.
                    let actual = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate, preparedPlan: indexed)
                    let expected = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate, preparedPlan: scanned)
                    XCTAssertEqual(actual.events, expected.events)
                    XCTAssertEqual(actual.categories, expected.categories)
                    let request = PlaybackSongOfflineRenderRequest(song: module, startOrderIndex: start, orderCount: count,
                        config: .init(sampleRate: rate), frames: try XCTUnwrap(actual.plannedSongEndFrame))
                    let a = Renderer(preparedPlan: indexed), b = Renderer(preparedPlan: scanned)
                    XCTAssertEqual(a.render(request).block.interleavedPCM, b.render(request).block.interleavedPCM)
                    for window in [1, 5] {
                        XCTAssertEqual(a.renderWindowed(request, windowRows: window).block.interleavedPCM,
                                       b.renderWindowed(request, windowRows: window).block.interleavedPCM)
                    }
                    let range = try XCTUnwrap(module.patternLoopRange(containing: .init(orderIndex: start, patternIndex: start, rowIndex: 0)))
                    XCTAssertEqual(actual.events(in: range), expected.events(in: range))
                }
            }
        }
    }

    func testPublicDirectionalFixturesAndIndependentRebuildsMatchTheScanOracle() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated")
        var previous: PlaybackSongSyntheticPlan?
        for name in ["fine-pitch-directional-memory.xm", "extra-fine-pitch-directional-memory.xm"] {
            let path = directory.appendingPathComponent(name).path
            let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
            for _ in 0..<2 {
                let plan = Adapter.adapt(module, startOrderIndex: 0, orderCount: module.orders.count, sampleRate: 48_000)
                XCTAssertEqual(plan, Adapter.adaptUsingScanEligibility(module, orderCount: module.orders.count, sampleRate: 48_000))
                let history = Renderer.PitchSourceHistory(plan: plan)
                XCTAssertEqual(history.sourceCount, plan.pattern.events.count)
                if name.hasPrefix("extra"), let previous { XCTAssertNotEqual(plan, previous) }
                if name.hasPrefix("fine") { previous = plan }
            }
        }
    }
    #endif

    func testScalingBuildsOnceAndBoundsQueriesBySourceLocalBinarySearch() throws {
        for rows in [16, 32, 64] {
            let sink = Sink()
            let profile = AdapterPlanProfileSession(lifecycle: "test", clock: MonotonicAdapterPlanProfileClock(), sink: sink)
            let module = song((0..<rows).map { row in
                Array(repeating: row % 8 == 0 ? c(note: 49, instrument: 1) :
                    c(row % 8 < 5 ? 14 : 33, [0, 0x11, 0x10, 0x21, 0x20, 0x11, 0x10, 0x20][row % 8]), count: 2)
            })
            let plan = Adapter.adapt(module, startOrderIndex: 0, orderCount: 2, sampleRate: 48_000, profileSession: profile)
            let fields = try XCTUnwrap(sink.fields(for: "fine_pitch_source_eligibility"))
            let queries = rows / 8 * 7 * 2
            XCTAssertEqual(fields["index_build_count"], 1)
            XCTAssertEqual(fields["eligibility_query_count"], queries)
            XCTAssertEqual(fields["pitch_diagnostics_visited"], queries)
            XCTAssertEqual(fields["position_lookup_count"], queries)
            XCTAssertLessThanOrEqual(try XCTUnwrap(fields["position_entries_visited"]), queries * 3)
            XCTAssertEqual(sink.lines.filter { $0.contains("phase=fine_pitch_source_history_build ") }.count, 1)
            let history = Renderer.PitchSourceHistory(plan: plan)
            XCTAssertEqual(history.recordStride, 24)
            XCTAssertEqual(history.sourceStride, 32)
            XCTAssertEqual(history.logicalBytes, history.recordCount * 24 + history.sourceCount * 32)
        }
    }

    private final class Sink: AdapterPlanProfileSinking {
        var lines = [String]()
        func writeAdapterPlanProfileLine(_ line: String) { lines.append(line) }
        func fields(for phase: String) -> [String: Int]? {
            guard let line = lines.first(where: { $0.contains("phase=\(phase) ") }) else { return nil }
            return line.split(separator: " ").reduce(into: [:]) { result, item in
                let parts = item.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let value = Int(parts[1]) { result[String(parts[0])] = value }
            }
        }
    }

    private func lifecycleRows() -> [[PlaybackCell]] {
        [[c(14, 0x13, note: 49, instrument: 1), c(33, 0x24, note: 49, instrument: 1)],
         [c(4, 0x48), c(volume: 0xB8)], [c(14, 0x10), c(33, 0x20)], [c(1, 4), c(2, 3)],
         [c(3, 5, note: 53), c(5, 1)], [c(6), c(14, 0x21)], [c(14, 0x20), c(33, 0x11)],
         [c(33, 0x10), c(14, 0x11)], [c(33, 0x21), c(14, 0x10)], [c(33, 0x20), c(14, 0x20)],
         [c(instrument: 1)], [c(note: 50)], [c(14, 0x10), c(33, 0x10)], [c(note: 49), c(note: 49)],
         [c(note: 97)], [c(14, 0x24), c(33, 0x13)], [c(14, 0xC1)], [c(14, 0x10), c(33, 0x20)],
         [c(note: 49)], [c(14, 0x93)], [c(33, 0x10)], [c(14, 0x20)]]
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ rows: [[PlaybackCell]], loop: Int = 1, envelope: Bool = false, sampleFrames: Int = 64) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: Float(1) / 32, count: sampleFrames),
            volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: loop == 0 ? 0 : 64, loopType: loop)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: 0, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 48), .init(tick: 8, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 4096 : 0)
        let split = max(1, rows.count / 2)
        let chunks = [Array(rows[..<split]), Array(rows[split...])]
        let patterns = chunks.enumerated().map { index, chunk in
            PlaybackPattern(index: index, rows: chunk.enumerated().map {
                .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count))
            })
        }
        return .init(title: "Public pitch-history equivalence", orders: patterns.map { .init(orderIndex: $0.index, patternIndex: $0.index) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { ($0.index, $0) }),
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true,
                volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }
}
