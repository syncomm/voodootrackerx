import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original synthetic cells pin the independently observed bounded G38A rules.
final class TraversalPrecedenceTests: XCTestCase {
    func testOrderedJumpBreakWritersChooseBothOrderAndPendingRow() throws {
        let cases: [([PlaybackCell], Int, Int)] = [
            ([c(11, 2)], 2, 0), ([c(13, 2)], 1, 2),
            ([c(11, 2), c(13, 2)], 2, 2), ([c(13, 2), c(11, 2)], 2, 0),
            ([c(11, 1), c(11, 2)], 2, 0), ([c(13, 1), c(13, 2)], 1, 2),
            ([c(11, 2), c(13, 2), c(11, 1)], 1, 0),
            ([c(11, 1), c(11, 2), c(13, 3), c(13, 2)], 2, 2)
        ]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (commands, order, row) in cases {
                let input = song([rows(1, commands: commands), rows(4), rows(4)], linear: linear)
                let plan = adapt(input, rate)
                XCTAssertEqual(plan.diagnostics.rowMappings[1].source,
                    .init(orderIndex: order, patternIndex: order, rowIndex: row))
                let lastB = commands.lastIndex(where: { $0.effectType == 11 })
                let lastD = commands.lastIndex(where: { $0.effectType == 13 })
                if let lastB {
                    XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first { $0.kind == .bxxPositionJump }?.channelIndex, lastB + 1)
                }
                if let lastD {
                    XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first { $0.kind == .dxxPatternBreak }?.channelIndex, lastD + 1)
                }
                try assertBirthsAndClock(input, plan: plan, rate: rate)
            }
        } }
    }

    func testDelayCommitsJumpBreakAfterHeldTicksAndAdvancesPendingRowOnce() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay: UInt8 in [0, 1, 2] {
            for (commands, order, target): ([PlaybackCell], Int, Int) in [
                ([c(11, 2)], 2, 0), ([c(13, 2)], 1, 2),
                ([c(11, 2), c(13, 2)], 2, 2), ([c(13, 2), c(11, 2)], 2, 0)
            ] {
                let input = song([rows(1, commands: commands + [c(14, 0xE0 | delay), c(15, 3), c(15, 150)]),
                    rows(5), rows(5)], linear: linear)
                let plan = adapt(input, rate), first = plan.diagnostics.rowTiming[0]
                XCTAssertEqual(first.actualTickCount, 3 * (Int(delay) + 1))
                XCTAssertEqual(first.effectiveSpeed, 3); XCTAssertEqual(first.effectiveBPM, 150)
                XCTAssertEqual(plan.diagnostics.rowMappings[1].source,
                    .init(orderIndex: order, patternIndex: order, rowIndex: target + (delay > 0 ? 1 : 0)))
                XCTAssertEqual(plan.diagnostics.rowTiming[1].rowStartFrame,
                    Int(rate * 0.05 * Double(Int(delay) + 1)))
                try assertBirthsAndClock(input, plan: plan, rate: rate)
            }
        } } }
    }

    func testLoopAndJumpBreakShareOrderedPendingRowButOrderCommitStillWins() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (commands, owner, order, target): ([PlaybackCell], Int, Int, Int) in [
                ([c(11, 2), c(14, 0x61)], 2, 2, 1), ([c(14, 0x61), c(11, 2)], 1, 2, 0),
                ([c(13, 2), c(14, 0x61)], 2, 1, 1), ([c(14, 0x61), c(13, 2)], 1, 1, 2)
            ] {
                var first = rows(4)
                first[1][owner] = c(14, 0x60)
                for (i, command) in commands.enumerated() { first[2][i + 1] = command }
                let input = song([first, rows(4), rows(4)], linear: linear), plan = adapt(input, rate)
                XCTAssertEqual(Array(plan.diagnostics.rowMappings.prefix(3)).map(\.source.rowIndex), [0, 1, 2])
                XCTAssertEqual(plan.diagnostics.rowMappings[3].source,
                    .init(orderIndex: order, patternIndex: order, rowIndex: target))
                XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first(where: \.loopTaken)?.channelIndex, owner)
                try assertBirthsAndClock(input, plan: plan, rate: rate)
            }
        } }
    }

    func testHeldLoopSkipsPendingAnchorOnlyOnceAndPreservesFreshEntryDispatch() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay: UInt8 in [0, 1, 2] {
            for count: UInt8 in [1, 2] { for anchor in [0, 1] {
                var cells = rows(4)
                if anchor == 1 { cells[1][1] = c(14, 0x60) }
                cells[2][1] = c(14, 0x60 | count); cells[2][2] = c(14, 0xE0 | delay)
                let input = song([cells], linear: linear), plan = adapt(input, rate)
                let start = anchor + (delay > 0 ? 1 : 0)
                let expected = [0, 1, 2] + Array(repeating: Array(start...2), count: Int(count)).flatMap { $0 } + [3]
                XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.rowIndex), expected)
                if anchor == 0 && count == 1 {
                    let ticks = delay == 0 ? [0, 6, 12, 18, 24, 30, 36]
                        : delay == 1 ? [0, 6, 12, 24, 30, 42] : [0, 6, 12, 30, 36, 54]
                    XCTAssertEqual(plan.diagnostics.rowTiming.map(\.rowStartFrame), ticks.map { $0 * Int(rate / 50) })
                }
                try assertBirthsAndClock(input, plan: plan, rate: rate)
            } }
        } } }
    }

    func testValidBreakBoundsColdSelectionAndFinitePositionGuardRemainExplicit() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let bounded = adapt(song([rows(1, commands: [c(13, 0x12)]), rows(4)], linear: linear), rate)
            XCTAssertEqual(bounded.diagnostics.rowMappings[1].source.rowIndex, 0)
            XCTAssertEqual(bounded.diagnostics.traversalDiagnostics.first?.status, .outOfRange)
            let unavailable = adapt(song([rows(1, commands: [c(11, 127)]), rows(4)], linear: linear), rate)
            XCTAssertEqual(unavailable.diagnostics.traversalStopReason, .outOfRange)
            XCTAssertEqual(unavailable.diagnostics.rowMappings.count, 1)
            var first = rows(4), second = rows(4)
            first[1][1] = c(14, 0x60); second[2][1] = c(14, 0x61); second[2][2] = c(14, 0xE1)
            let input = song([first, second], linear: linear)
            let cold = PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 1, orderCount: 1, sampleRate: rate)
            XCTAssertEqual(cold.diagnostics.rowMappings.map(\.source.rowIndex), [0, 1, 2, 1, 2, 3])
            XCTAssertTrue(cold.diagnostics.rowMappings.allSatisfy { $0.source.orderIndex == 1 })
            XCTAssertEqual(cold.pattern.events.first?.scheduledStartFrame, 0)
            XCTAssertFalse(cold.diagnostics.traversalDiagnostics.contains(where: \.missingLoopStart))
            let cycle = adapt(song([rows(1, commands: [c(11), c(14, 0xE1)])], linear: linear), rate)
            XCTAssertTrue(cycle.diagnostics.traversalGuardHit)
            XCTAssertEqual(cycle.diagnostics.rowMappings.count, 1)
            XCTAssertEqual(cycle.diagnostics.rowTiming[0].actualTickCount, 12)
        } }
    }

    func testExtendedAndMalformedBreaksRetainTheirExistingSafePolicy() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (parameter, length, destination): (UInt8, Int, Int) in [
                (0x1A, 100, 0), (0xA1, 100, 0), (0xFF, 100, 0),
                (0x64, 100, 64), (0x70, 100, 70), (0x99, 100, 99),
                (0x64, 4, 3), (0x99, 4, 3), (0x63, 4, 0)
            ] {
                let target = Array(repeating: [c(note: 56)], count: length)
                let input = song([rows(1, commands: [c(13, parameter)]), target], linear: linear)
                let plan = adapt(input, rate)
                XCTAssertEqual(plan.diagnostics.rowMappings[1].source.rowIndex, destination)
                XCTAssertEqual(plan.diagnostics.rowMappings.count, 1 + length - destination)
                XCTAssertFalse(plan.diagnostics.traversalGuardHit)
                XCTAssertEqual(plan.diagnostics.traversalStopReason, .songEnd)
                XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first?.status,
                    parameter == 0x1A || parameter >= 0xA0 ? .invalidTarget : (length == 4 ? .outOfRange : .applied))
            }
        } }
    }

    func testHeldPatternEdgeAndLastEEZeroClearOnlyThePendingHold() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for delay: UInt8 in [1, 2] {
                let input = song([rows(1, commands: [c(13, 3), c(14, 0xE0 | delay)]), rows(4), rows(4)], linear: linear)
                let plan = adapt(input, rate)
                XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.orderIndex), [0, 2, 2, 2, 2])
                XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.rowIndex), [0, 0, 1, 2, 3])
                try assertBirthsAndClock(input, plan: plan, rate: rate)
            }
            let commands = [c(11, 2), c(13, 2), c(14, 0xE1), c(14, 0xE0)]
            let jump = adapt(song([rows(1, commands: commands), rows(4), rows(4)], linear: linear), rate)
            XCTAssertEqual(jump.diagnostics.rowMappings[1].source, .init(orderIndex: 2, patternIndex: 2, rowIndex: 2))
            XCTAssertEqual(jump.diagnostics.rowTiming[0].actualTickCount, 6)
            var loop = rows(4)
            loop[2][1] = c(14, 0x61); loop[2][2] = c(14, 0xE1); loop[2][3] = c(14, 0xE0)
            let input = song([loop], linear: linear), cancelled = adapt(input, rate)
            XCTAssertEqual(cancelled.diagnostics.rowMappings.map(\.source.rowIndex), [0, 1, 2, 0, 1, 2, 3])
            XCTAssertTrue(cancelled.diagnostics.rowTiming.allSatisfy { $0.actualTickCount == 6 })
            try assertBirthsAndClock(input, plan: cancelled, rate: rate)
        } }
    }

    func testChannelCountersExecuteTogetherRearmNestedLoopsAndKeepFiniteBudget() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            var together = rows(4)
            together[0][1] = c(14, 0x60); together[1][2] = c(14, 0x60)
            together[2][1] = c(14, 0x61); together[2][2] = c(14, 0x61)
            let multi = adapt(song([together], linear: linear), rate)
            XCTAssertEqual(multi.diagnostics.rowMappings.map(\.source.rowIndex), [0, 1, 2, 1, 2, 3])
            XCTAssertEqual(multi.diagnostics.traversalDiagnostics.filter(\.loopTaken).map(\.channelIndex), [1, 2])
            var nested = rows(4)
            nested[0][1] = c(14, 0x60); nested[3][1] = c(14, 0x61)
            nested[1][2] = c(14, 0x60); nested[2][2] = c(14, 0x61)
            let finite = adapt(song([nested], linear: linear), rate)
            XCTAssertEqual(finite.diagnostics.rowMappings.map(\.source.rowIndex), [0, 1, 2, 1, 2, 3, 0, 1, 2, 1, 2, 3])
            XCTAssertFalse(finite.diagnostics.traversalGuardHit)
            XCTAssertEqual(finite.diagnostics.traversalStopReason, .songEnd)
            // FT2 repeats this channel-shared-counter case indefinitely; VTX retains its finite budget.
            var repeating = rows(4)
            repeating[0][1] = c(14, 0x60); repeating[1][1] = c(14, 0x61); repeating[2][1] = c(14, 0x61)
            let guarded = PlaybackSongTraversalPlanner.plan(song([repeating], linear: linear), startOrderIndex: 0, orderCount: 1)
            XCTAssertEqual(guarded.rows.prefix(8).map(\.source.rowIndex), [0, 1, 0, 1, 2, 0, 1, 2])
            XCTAssertEqual(guarded.pathLength, 1088)
            XCTAssertTrue(guarded.guardHit); XCTAssertEqual(guarded.stopReason, .traversalGuardHit)
            XCTAssertEqual(guarded.traversalDiagnostics.last?.policy, "max_traversal_row_guard")
        } }
    }

    func testTraversalSourcesKeepExactWholeSplitWindowAndStreamingPCM() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            var first = rows(4)
            first[2][1] = c(14, 0x61); first[2][2] = c(14, 0xE1)
            first[3][1] = c(13, 2); first[3][2] = c(11, 2); first[3][3] = c(14, 0xE2)
            let input = song([first, rows(4), rows(4)], linear: linear), plan = adapt(input, rate)
            XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.rowIndex), [0, 1, 2, 1, 2, 3, 1, 2, 3])
            XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.orderIndex), [0, 0, 0, 0, 0, 0, 2, 2, 2])
            let end = Int(plan.diagnostics.rowTiming.last!.rowEndExactFrame)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), frames: end)
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), whole = renderer.render(request)
            try whole.controlAdmission.requireSuccess()
            XCTAssertTrue(whole.block.interleavedPCM.contains { $0 != 0 })
            for window in [1, 2, 4] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, whole.block.interleavedPCM)
            }
            let session = renderer.prepare(request)
            var split = [Float]()
            while split.count / 2 < end {
                split += session.render(frames: min(257, end - split.count / 2)).interleavedPCM
            }
            XCTAssertEqual(split, whole.block.interleavedPCM)
            var streamed = [Float](), windowed = [Float]()
            XCTAssertEqual(renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in streamed += block.interleavedPCM }.renderedFrameCount, end)
            XCTAssertEqual(renderer.renderWindowedStreaming(request, windowRows: 2) { _, _, _, block in windowed += block.interleavedPCM }.renderedFrameCount, end)
            XCTAssertEqual(streamed, whole.block.interleavedPCM); XCTAssertEqual(windowed, whole.block.interleavedPCM)
            #if DEBUG
            let edge = plan.diagnostics.rowTiming[3].rowStartFrame
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [1, edge - 1, edge, edge + 1, end - 1]).block.interleavedPCM, whole.block.interleavedPCM)
            #endif
        } }
    }

    private func assertBirthsAndClock(_ input: PlaybackSong, plan: PlaybackSongSyntheticPlan, rate: Double,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
        XCTAssertEqual(runtime.plan, plan, file: file, line: line)
        let births = runtime.events.filter { if case .noteTrigger = $0.action { return true }; return false }
        XCTAssertEqual(births.map(\.scheduledFrame), plan.diagnostics.rowTiming.map(\.rowStartFrame), file: file, line: line)
        XCTAssertEqual(births.compactMap(\.activeEventIndex), Array(births.indices), file: file, line: line)
        XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), Array(repeating: 0, count: births.count), file: file, line: line)
        XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count, file: file, line: line)
        for timing in plan.diagnostics.rowTiming {
            for tick in 0..<timing.actualTickCount {
                let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: timing.syntheticRow, tick: tick, channel: 0), file: file, line: line)
                XCTAssertEqual(coordinate.absoluteFrame, Int((timing.rowStartExactFrame + Double(tick) * rate * 2.5 / Double(timing.effectiveBPM)).rounded(.down)), file: file, line: line)
                XCTAssertEqual(coordinate.isFreshEntry, tick == 0, file: file, line: line)
                XCTAssertEqual(coordinate.localEffectPhase, tick % timing.effectiveSpeed, file: file, line: line)
            }
        }
    }

    private func adapt(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 0, orderCount: input.orders.count, sampleRate: rate)
    }
    private func rows(_ count: Int, commands: [PlaybackCell] = []) -> [[PlaybackCell]] {
        var result = [[PlaybackCell]]()
        for row in 0..<count {
            var cells = [c(note: UInt8(49 + row * 2))]
            if row == 0 { cells += commands }
            cells += Array(repeating: c(), count: 8 - cells.count)
            result.append(cells)
        }
        return result
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: note == 0 ? 0 : 1, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }
    private func song(_ patterns: [[[PlaybackCell]]], linear: Bool) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<256).map { Float(($0 * 37 + 29) % 127 - 63) / 256 }, volume: 0.75,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        return PlaybackSong(title: "Original bounded traversal-precedence controls",
            orders: patterns.indices.map { .init(orderIndex: $0, patternIndex: $0) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.enumerated().map { index, cells in
                (index, .init(index: index, rows: cells.enumerated().map { .init(index: $0.offset, cells: $0.element) }))
            }), instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
