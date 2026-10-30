import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original cells/PCM pin G37A; inherited anchors deliberately retain unresolved G38 behavior.
final class ImplicitPatternLoopTests: XCTestCase {
    func testInitialE61AndE62ExactVisitsTicksSourcesAndExhaustion() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for count: UInt8 in [1, 2] {
            let input = song([rows(count)], linear: linear)
            let expected = Array(repeating: [0, 1, 2], count: Int(count) + 1).flatMap { $0 } + [3]
            let plan = adapt(input, rate)
            try assertTimeline(plan, rows: expected, orders: Array(repeating: 0, count: expected.count), rate: rate)
            if count == 1 {
                XCTAssertEqual(plan.diagnostics.rowTiming.map(\.rowStartFrame), rate == 48_000
                    ? [0, 5760, 11520, 17280, 23040, 28800, 34560]
                    : [0, 5292, 10584, 15876, 21168, 26460, 31752])
            }
            let loops = plan.diagnostics.traversalDiagnostics
            XCTAssertEqual(loops.filter(\.loopTaken).map(\.loopRemaining), count == 1 ? [0] : [1, 0])
            XCTAssertEqual(loops.last?.policy, "e6x_loop_count_exhausted_continue")
            XCTAssertEqual(loops.last?.syntheticRow, expected.count - 2)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            XCTAssertEqual(runtime.plan, plan)
            let births = runtime.events.filter { if case .noteTrigger = $0.action { return true }; return false }
            XCTAssertEqual(births.map(\.activeEventIndex), Array(expected.indices).map(Optional.some))
            XCTAssertEqual(births.map(\.scheduledFrame), plan.diagnostics.rowTiming.map(\.rowStartFrame))
            XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count)
        } } }
    }

    func testColdLaterOrdersResetCountersAndExplicitLocalAnchorStillWins() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let cold = adapt(song([rows()], orders: [0, 0], linear: linear), rate)
            let visits = [0, 1, 2, 0, 1, 2, 3]
            try assertTimeline(cold, rows: visits + visits,
                orders: Array(repeating: 0, count: 7) + Array(repeating: 1, count: 7), rate: rate,
                patterns: Array(repeating: 0, count: 14))
            XCTAssertEqual(cold.diagnostics.traversalDiagnostics.filter(\.loopTaken).map(\.loopRemaining), [0, 0])
            let local = adapt(song([rows(1, anchor: 1)], linear: linear), rate)
            try assertTimeline(local, rows: [0, 1, 2, 1, 2, 3], orders: Array(repeating: 0, count: 6), rate: rate)
            XCTAssertEqual(local.diagnostics.traversalDiagnostics.filter(\.loopTaken).map(\.loopStartRowIndex), [1])
            let negative = adapt(song([rows(nil), rows(nil, anchor: 1)], linear: linear), rate)
            try assertTimeline(negative, rows: [0, 1, 2, 3, 0, 1, 2, 3],
                orders: [0, 0, 0, 0, 1, 1, 1, 1], rate: rate)
            XCTAssertFalse(negative.diagnostics.traversalDiagnostics.contains(where: \.loopTaken))
        } }
    }

    func testInheritedAnchorsStayHeldAndHistoryBelongsOnlyToItsExecutedChannel() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for completedLoop in [false, true] {
                let first = rows(completedLoop ? 1 : nil, anchor: 1)
                let plan = adapt(song([first, rows()], linear: linear), rate)
                let prefix = completedLoop ? [0, 1, 2, 1, 2, 3] : [0, 1, 2, 3]
                // FT2 carries row 1, and after a completed loop can even enter the next order at 1.
                // G37A preserves VTX's row-zero entry and missing-start refusal for both G38 witnesses.
                try assertTimeline(plan, rows: prefix + [0, 1, 2, 3],
                    orders: Array(repeating: 0, count: prefix.count) + [1, 1, 1, 1], rate: rate)
                let held = try XCTUnwrap(plan.diagnostics.traversalDiagnostics.first(where: \.missingLoopStart))
                XCTAssertEqual(held.source.orderIndex, 1)
                XCTAssertNil(held.loopStartRowIndex)
                XCTAssertEqual(held.policy, "missing_e60_loop_start_diagnosed_no_loop")
            }
            let mixed = adapt(song([rows(nil, anchor: 1), rows(1, owner: 1), rows()], linear: linear), rate)
            try assertTimeline(mixed, rows: [0, 1, 2, 3] + [0, 1, 2, 0, 1, 2, 3] + [0, 1, 2, 3],
                orders: [0, 0, 0, 0] + Array(repeating: 1, count: 7) + [2, 2, 2, 2], rate: rate)
            XCTAssertEqual(mixed.diagnostics.traversalDiagnostics.filter(\.loopTaken).map(\.channelIndex), [1])
            XCTAssertEqual(mixed.diagnostics.traversalDiagnostics.filter(\.missingLoopStart).map(\.channelIndex), [0])
            let selected = PlaybackSongSyntheticAdapter.adapt(song([rows(nil, anchor: 1), rows()], linear: linear),
                startOrderIndex: 1, orderCount: 1, sampleRate: rate)
            try assertTimeline(selected, rows: [0, 1, 2, 0, 1, 2, 3], orders: Array(repeating: 1, count: 7), rate: rate)
        } }
    }

    func testUnexecutedE60DoesNotCreateHistoryAndDefaultIsArrayIndexZero() throws {
        var skipped = rows(nil, anchor: 1)
        skipped[0][0] = cell(11, 1)
        let jumped = adapt(song([skipped, rows()]), 48_000)
        XCTAssertEqual(jumped.diagnostics.rowMappings.map(\.source.rowIndex), [0, 0, 1, 2, 0, 1, 2, 3])
        XCTAssertFalse(jumped.diagnostics.traversalDiagnostics.contains(where: \.missingLoopStart))
        let future = adapt(song([rows(1, anchor: 3)]), 48_000)
        XCTAssertEqual(future.diagnostics.rowMappings.map(\.source.rowIndex), [0, 1, 2, 0, 1, 2, 3])
        let labeled = adapt(song([rows()], rowLabels: [10, 20, 30, 40]), 48_000)
        XCTAssertEqual(labeled.diagnostics.rowMappings.map(\.source.rowIndex), [10, 20, 30, 10, 20, 30, 40])
        XCTAssertEqual(labeled.diagnostics.traversalDiagnostics.first?.targetRowIndex, 10)
    }

    func testSpeedOneAndExecutedFxxKeepActualTickZeroChronology() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let visits = [0, 1, 2, 0, 1, 2, 3]
            let slow = adapt(song([rows()], linear: linear, speed: 1), rate)
            try assertTimeline(slow, rows: visits, orders: Array(repeating: 0, count: 7), rate: rate, speeds: Array(repeating: 1, count: 7))
            var changing = rows()
            changing[0][0] = cell(15, 1, note: 49)
            changing[1][0] = cell(15, 3, note: 51)
            let plan = adapt(song([changing], linear: linear), rate)
            try assertTimeline(plan, rows: visits, orders: Array(repeating: 0, count: 7), rate: rate, speeds: [1, 3, 3, 1, 3, 3, 3])
            XCTAssertEqual(plan.diagnostics.rowTiming.map(\.rowStartFrame), rate == 48_000
                ? [0, 960, 3840, 6720, 7680, 10560, 13440] : [0, 882, 3528, 6174, 7056, 9702, 12348])
        } }
    }

    func testWholeSplitWindowAndBothStreamingPathsKeepExactRepeatedPCM() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([rows()], linear: linear), plan = adapt(input, rate)
            let frames = 42 * Int(rate / 50)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), frames: frames)
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), full = renderer.render(request)
            XCTAssertEqual(full.block.frameCount, frames)
            XCTAssertTrue(full.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
            for window in [1, 2, 4] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, full.block.interleavedPCM)
            }
            let session = renderer.prepare(request)
            var split = [Float]()
            while split.count / 2 < frames {
                split += session.render(frames: min(257, frames - split.count / 2)).interleavedPCM
            }
            XCTAssertEqual(split, full.block.interleavedPCM)
            var streamed = [Float](), windowed = [Float]()
            let stream = renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in streamed += block.interleavedPCM }
            let windows = renderer.renderWindowedStreaming(request, windowRows: 2) { _, _, _, block in windowed += block.interleavedPCM }
            XCTAssertEqual(stream.renderedFrameCount, frames); XCTAssertEqual(windows.renderedFrameCount, frames)
            XCTAssertEqual(streamed, full.block.interleavedPCM); XCTAssertEqual(windowed, full.block.interleavedPCM)
            #if DEBUG
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [1, 18 * Int(rate / 50), 18 * Int(rate / 50) + 1, 36 * Int(rate / 50) + 17]).block.interleavedPCM,
                full.block.interleavedPCM)
            #endif
        } }
    }

    func testFiniteRepeatGrowthAndPathologicalTraversalKeepExistingCeiling() {
        var finite = Array(repeating: [cell()], count: 64)
        finite[63] = [cell(14, 0x6F)]
        let bounded = PlaybackSongTraversalPlanner.plan(song([finite]), startOrderIndex: 0, orderCount: 1)
        XCTAssertEqual(bounded.pathLength, 1024); XCTAssertFalse(bounded.guardHit)
        XCTAssertEqual(bounded.stopReason, .songEnd)
        XCTAssertEqual(bounded.rows.map(\.rowArrayIndex), Array(repeating: Array(0..<64), count: 16).flatMap { $0 })
        // This is a guard witness only, not a nested-loop/precedence compatibility claim.
        let pathological = PlaybackSongTraversalPlanner.plan(song([Array(repeating: [cell(14, 0x6F)], count: 128)]),
            startOrderIndex: 0, orderCount: 1)
        XCTAssertEqual(pathological.pathLength, 3072); XCTAssertTrue(pathological.guardHit)
        XCTAssertEqual(pathological.stopReason, .traversalGuardHit)
        XCTAssertEqual(pathological.traversalDiagnostics.last?.policy, "max_traversal_row_guard")
        XCTAssertEqual(pathological.traversalDiagnostics.last?.loopLimit, 3072)
    }

    private func assertTimeline(_ plan: PlaybackSongSyntheticPlan, rows: [Int], orders: [Int], rate: Double,
                                speeds: [Int]? = nil, patterns: [Int]? = nil,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let timings = plan.diagnostics.rowTiming, ticks = speeds ?? Array(repeating: 6, count: rows.count)
        XCTAssertEqual(timings.map(\.source.rowIndex), rows, file: file, line: line)
        XCTAssertEqual(timings.map(\.source.orderIndex), orders, file: file, line: line)
        XCTAssertEqual(timings.map(\.source.patternIndex), patterns ?? orders, file: file, line: line)
        XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.rowIndex), rows, file: file, line: line)
        XCTAssertEqual(timings.map(\.syntheticRow), Array(rows.indices), file: file, line: line)
        XCTAssertEqual(timings.map(\.effectiveSpeed), ticks, file: file, line: line)
        XCTAssertEqual(plan.pattern.events.map(\.row), Array(rows.indices), file: file, line: line)
        XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), Array(repeating: 0, count: rows.count), file: file, line: line)
        var frame = 0
        for (i, row) in timings.enumerated() {
            XCTAssertEqual(row.rowStartFrame, frame, file: file, line: line)
            XCTAssertEqual(plan.pattern.events[i].scheduledStartFrame, frame, file: file, line: line)
            for tick in 0..<ticks[i] {
                XCTAssertEqual(plan.canonicalTickClock.coordinate(syntheticRow: i, tick: tick, channel: 0)?.absoluteFrame,
                    frame + tick * Int(rate / 50), file: file, line: line)
            }
            frame += ticks[i] * Int(rate / 50)
            XCTAssertEqual(row.rowEndExactFrame, Double(frame), file: file, line: line)
        }
        XCTAssertFalse(plan.diagnostics.traversalGuardHit, file: file, line: line)
        XCTAssertEqual(plan.diagnostics.traversalStopReason, .songEnd, file: file, line: line)
    }

    private func adapt(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 0, orderCount: input.orders.count, sampleRate: rate)
    }

    private func rows(_ count: UInt8? = 1, anchor: Int? = nil, owner: Int = 0) -> [[PlaybackCell]] {
        var result = (0..<4).map { [cell(note: UInt8(49 + 2 * $0)), cell()] }
        if let count { result[2][owner] = cell(14, 0x60 | count, note: owner == 0 ? 53 : 0) }
        if let anchor { result[anchor][0] = cell(14, 0x60, note: UInt8(49 + 2 * anchor)) }
        return result
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: note == 0 ? 0 : 1, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func song(_ patterns: [[[PlaybackCell]]], orders: [Int]? = nil, linear: Bool = true,
                      speed: Int = 6, rowLabels: [Int]? = nil) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<256).map { Float(($0 * 37 + 29) % 127 - 63) / 256 }, volume: 0.75,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        return PlaybackSong(title: "Original G37A control", orders: (orders ?? Array(patterns.indices)).enumerated().map {
                .init(orderIndex: $0.offset, patternIndex: $0.element)
            }, patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.enumerated().map { index, rows in
                (index, PlaybackPattern(index: index, rows: rows.enumerated().map {
                    .init(index: rowLabels?[$0.offset] ?? $0.offset, cells: $0.element)
                }))
            }), instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
