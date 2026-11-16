import Foundation
import XCTest
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif

/// Explicit-loop traversal shares the accepted row and timing reducers.
final class UserLoopTraversalContinuationTests: XCTestCase {
    private typealias Planner = PlaybackSongTraversalPlanner

    func testBoundedBatchPartitionsKeepExactExecutedRowsAndFractionalTiming() throws {
        let pattern = [[cell(15, 3), cell(15, 151)], [cell(14, 0x60), cell()],
            [cell(14, 0x62), cell(14, 0xE1)], [cell(), cell(15, 143)]]
        for rate in [44_100.0, 48_000] { for orderCount in [1, 64, 256] {
            let input = song([0: pattern, 1: [[cell()]]], orders: [0] + Array(repeating: 1, count: orderCount - 1))
            let initial = try XCTUnwrap(Planner.makeUserLoopState(input,
                initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2)))
            let timing = PlaybackSongFxxTimingPlanner.State(speed: input.initialTiming.speed,
                bpm: input.initialTiming.bpm, nextExactFrame: 0)
            let whole = try XCTUnwrap(Planner.planUserLoopBatch(input, state: initial, timing: timing,
                sampleRate: rate, minimumHorizonFrames: Int.max, maximumRows: 512))
            XCTAssertEqual(whole.traversal.rows.count, 512)
            for cap in [1, 7, 64] {
                var state = initial, clock = timing, offset = 0
                while offset < 512 {
                    let batch = try XCTUnwrap(Planner.planUserLoopBatch(input, state: state, timing: clock,
                        sampleRate: rate, minimumHorizonFrames: Int.max, maximumRows: min(cap, 512 - offset)))
                    for local in batch.traversal.rows.indices {
                        let expected = whole.traversal.rows[offset + local], actual = batch.traversal.rows[local]
                        XCTAssertEqual(actual.source, expected.source)
                        XCTAssertEqual(actual.rowArrayIndex, expected.rowArrayIndex)
                        let a = batch.timing.rowTimings[local], b = whole.timing.rowTimings[offset + local]
                        XCTAssertEqual(a.rowStartExactFrame, b.rowStartExactFrame)
                        XCTAssertEqual(a.rowEndExactFrame, b.rowEndExactFrame)
                        XCTAssertEqual(a.effectiveSpeed, b.effectiveSpeed)
                        XCTAssertEqual(a.effectiveBPM, b.effectiveBPM)
                        XCTAssertEqual(a.patternDelayCycles, b.patternDelayCycles)
                        XCTAssertEqual(batch.iterationByRow[local], whole.iterationByRow[offset + local])
                    }
                    offset += batch.traversal.rows.count
                    state = batch.terminalTraversal; clock = batch.timing.terminalState
                }
                XCTAssertEqual(state, whole.terminalTraversal)
                XCTAssertEqual(clock, whole.timing.terminalState)
            }
            let horizon = try XCTUnwrap(Planner.planUserLoopBatch(input, state: initial, timing: timing,
                sampleRate: rate, minimumHorizonFrames: Int(rate / 2), maximumRows: 64))
            XCTAssertLessThanOrEqual(horizon.traversal.rows.count, 64)
            XCTAssertTrue(horizon.traversal.rows.count == 64 || horizon.timing.endExactFrame >= rate / 2)
        } }
    }

    func testNaturalTailShapingAndHardCapRollbackPreserveExactExecution() throws {
        let input = song([0: Array(repeating: [cell()], count: 4)], orders: [0])
        for rate in [44_100.0, 48_000] {
            let start = try XCTUnwrap(Planner.makeUserLoopState(input,
                initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0)))
            let clock = PlaybackSongFxxTimingPlanner.State(speed: input.initialTiming.speed,
                bpm: input.initialTiming.bpm, nextExactFrame: 0)
            let whole = try XCTUnwrap(Planner.planUserLoopBatch(input, state: start, timing: clock,
                sampleRate: rate, minimumHorizonFrames: Int.max, maximumRows: 32))
            let end = whole.timing.rowTimings[3].rowEndFrame
            let extended = try XCTUnwrap(Planner.planUserLoopBatch(input, state: start, timing: clock,
                sampleRate: rate, minimumHorizonFrames: end, maximumRows: 8,
                minimumNaturalBoundaryTailFrames: 512))
            XCTAssertEqual(extended.traversal.rows.map(\.rowArrayIndex), [0, 1, 2, 3, 0])
            let capped = try XCTUnwrap(Planner.planUserLoopBatch(input, state: start, timing: clock,
                sampleRate: rate, minimumHorizonFrames: end, maximumRows: 4,
                minimumNaturalBoundaryTailFrames: 512))
            XCTAssertEqual(capped.traversal.rows.map(\.rowArrayIndex), [0, 1, 2])
            let continued = try XCTUnwrap(Planner.planUserLoopBatch(input, state: capped.terminalTraversal,
                timing: capped.timing.terminalState, sampleRate: rate, minimumHorizonFrames: end, maximumRows: 8,
                minimumNaturalBoundaryTailFrames: 512))
            let timings = capped.timing.rowTimings + continued.timing.rowTimings
            XCTAssertEqual(capped.traversal.rows.map(\.rowArrayIndex) + continued.traversal.rows.map(\.rowArrayIndex),
                Array(whole.traversal.rows.prefix(timings.count)).map(\.rowArrayIndex))
            XCTAssertEqual(timings.map(\.rowStartExactFrame), Array(whole.timing.rowTimings.prefix(timings.count)).map(\.rowStartExactFrame))
            XCTAssertEqual(timings.map(\.rowEndExactFrame), Array(whole.timing.rowTimings.prefix(timings.count)).map(\.rowEndExactFrame))
        }
    }

    func testColdSuffixThenWholeIterationsMatchesExpandedOrderOccurrences() throws {
        let pattern = Array(repeating: [cell()], count: 4)
        let input = song([0: pattern], orders: [0])
        let actual = try collect(input, row: 2, iterations: 4)
        let expanded = song([0: pattern], orders: [0, 0, 0, 0])
        let expected = Planner.plan(expanded, startOrderIndex: 0, orderCount: 4,
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2))
        XCTAssertEqual(actual.rows.map(\.rowArrayIndex), [2, 3] + (0..<3).flatMap { _ in [0, 1, 2, 3] })
        XCTAssertEqual(actual.rows.map(\.rowArrayIndex), expected.rows.map(\.rowArrayIndex))
        XCTAssertEqual(actual.boundaries.map(\.cause), Array(repeating: .naturalEnd, count: 4))
        XCTAssertEqual(actual.state.iteration, 4)
    }

    func testStructuralColdAnchorAndE6StateSurviveArbitraryBatchSplits() throws {
        let pattern = [[cell()], [cell(14, 0x60)], [cell(14, 0x62)], [cell()]]
        let input = song([0: pattern], orders: [0])
        let uninterrupted = try collect(input, row: 2, iterations: 3)
        let split = try collect(input, row: 2, iterations: 3, copyCheckpointEvery: 2)
        XCTAssertEqual(split.rows, uninterrupted.rows)
        XCTAssertEqual(split.diagnostics, uninterrupted.diagnostics)
        XCTAssertEqual(split.state, uninterrupted.state)
        let expanded = song([0: pattern], orders: [0, 0, 0])
        let expected = Planner.plan(expanded, startOrderIndex: 0, orderCount: 3,
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2))
        XCTAssertEqual(split.rows.map(\.rowArrayIndex), expected.rows.map(\.rowArrayIndex))
        XCTAssertEqual(split.diagnostics.filter(\.loopTaken).map(\.loopStartRowIndex),
            expected.traversalDiagnostics.filter(\.loopTaken).map(\.loopStartRowIndex))
        XCTAssertEqual(split.diagnostics.filter(\.loopTaken).map(\.loopRemaining),
            expected.traversalDiagnostics.filter(\.loopTaken).map(\.loopRemaining))
    }

    func testNaturalEntryDropsEarlierOccurrenceAnchorWithoutColdRescan() throws {
        // Cold row 3 may discover structural row-2 E60. The next natural entry
        // must execute row-0 E61 with a fresh implicit row-0 anchor.
        let pattern = [[cell(14, 0x61)], [cell()], [cell(14, 0x60)], [cell()]]
        let actual = try collect(song([0: pattern], orders: [0]), row: 3, iterations: 3)
        XCTAssertEqual(actual.rows.map(\.rowArrayIndex), [3, 0, 0, 1, 2, 3, 0, 0, 1, 2, 3])
        XCTAssertEqual(actual.diagnostics.filter(\.loopTaken).map(\.loopStartRowIndex), [0, 0])
        XCTAssertEqual(actual.diagnostics.filter(\.loopTaken).map(\.loopRemaining), [0, 0])
    }

    func testHeldE6AndSameRowFxxTimingMatchExpandedExecution() throws {
        let pattern = [[cell(15, 3), cell(15, 150), cell()],
            [cell(14, 0x60), cell(), cell()],
            [cell(14, 0x62), cell(14, 0xE1), cell(15, 1)],
            [cell(), cell(), cell()]]
        let input = song([0: pattern], orders: [0])
        let actual = try collect(input, row: 2, iterations: 3, copyCheckpointEvery: 1)
        let expanded = song([0: pattern], orders: [0, 0, 0])
        let expected = Planner.plan(expanded, startOrderIndex: 0, orderCount: 3,
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2))
        XCTAssertEqual(actual.rows.map(\.rowArrayIndex), expected.rows.map(\.rowArrayIndex))
        let stream = PlaybackSongTraversalPlan(rows: actual.rows, adaptedOrders: [],
            traversalDiagnostics: actual.diagnostics, pathLength: actual.rows.count,
            stopReason: .songEnd, guardHit: false)
        for rate in [44_100.0, 48_000] {
            let lhs = PlaybackSongFxxTimingPlanner.plan(input, traversalPlan: stream, sampleRate: rate)
            let rhs = PlaybackSongFxxTimingPlanner.plan(expanded, traversalPlan: expected, sampleRate: rate)
            XCTAssertEqual(lhs.rowTimings.map(\.rowStartExactFrame), rhs.rowTimings.map(\.rowStartExactFrame))
            XCTAssertEqual(lhs.rowTimings.map(\.rowEndExactFrame), rhs.rowTimings.map(\.rowEndExactFrame))
            XCTAssertEqual(lhs.rowTimings.map(\.effectiveSpeed), rhs.rowTimings.map(\.effectiveSpeed))
            XCTAssertEqual(lhs.rowTimings.map(\.effectiveBPM), rhs.rowTimings.map(\.effectiveBPM))
            XCTAssertEqual(lhs.rowTimings.map(\.patternDelayCycles), rhs.rowTimings.map(\.patternDelayCycles))
            XCTAssertEqual(lhs.timingChanges.map(\.effectParam), rhs.timingChanges.map(\.effectParam))
            XCTAssertEqual(lhs.endExactFrame, rhs.endExactFrame)
        }
    }

    func testOutgoingJumpBreakLoopWritersKeepAcceptedPrecedenceAndDiagnostics() throws {
        let cases: [([PlaybackCell], Int)] = [
            ([cell(11, 2), cell(13, 2), cell(14, 0x61)], 2),
            ([cell(14, 0x61), cell(13, 2), cell(11, 2)], 0),
            ([cell(11, 2), cell(14, 0x61), cell(13, 2)], 1)
        ]
        for (commands, anchorOwner) in cases { for delay: UInt8 in [0, 1, 2] {
            var pattern = Array(repeating: Array(repeating: cell(), count: 4), count: 4)
            pattern[1][anchorOwner] = cell(14, 0x60)
            for (channel, command) in commands.enumerated() { pattern[2][channel] = command }
            pattern[2][3] = cell(14, 0xE0 | delay)
            let input = song([0: pattern, 1: Array(repeating: [cell()], count: 4),
                2: Array(repeating: [cell()], count: 4)], orders: [0, 1, 2])
            let actual = try collect(input, row: 0, iterations: 1)
            let expected = Planner.plan(input, startOrderIndex: 0, orderCount: 3)
            XCTAssertEqual(actual.rows.map(\.rowArrayIndex), [0, 1, 2])
            XCTAssertEqual(actual.diagnostics, expected.traversalDiagnostics.filter { $0.source.orderIndex == 0 })
            let boundary = try XCTUnwrap(actual.boundaries.first)
            XCTAssertEqual(boundary.cause, .positionExit)
            XCTAssertEqual(boundary.targetOrderIndex, expected.rows[3].orderIndex)
            XCTAssertEqual(boundary.targetRowArrayIndex, expected.rows[3].rowArrayIndex)
            XCTAssertEqual(actual.state.nextRowArrayIndex, 0)
        } }
    }

    func testSameOrderForwardJumpRetainsRowAndInvalidOrCycleExitDoesNotBecomeAccepted() throws {
        let forward = [[cell(11, 0), cell(13, 2)], [cell()], [cell()], [cell()]]
        XCTAssertEqual(try collect(song([0: forward], orders: [0]), row: 0, iterations: 2)
            .rows.map(\.rowArrayIndex), [0, 2, 3, 0, 2, 3])
        for parameter: UInt8 in [0, 127] {
            let input = song([0: [[cell(11, parameter)]]], orders: [0])
            let actual = try collect(input, row: 0, iterations: 2)
            let expected = Planner.plan(input, startOrderIndex: 0, orderCount: 1)
            XCTAssertEqual(actual.rows.count, 2)
            XCTAssertEqual(Array(actual.diagnostics.prefix(expected.traversalDiagnostics.count)), expected.traversalDiagnostics)
            XCTAssertEqual(actual.boundaries.first?.traversalStopReason, expected.stopReason)
            XCTAssertEqual(actual.boundaries.first?.cause, parameter == 0 ? .cycleGuard : .positionExit)
        }
    }

    func testRowGuardDoesNotExecutePhantomRowAndUnrelatedOrdersDoNotChangeState() throws {
        let pathological = Array(repeating: [cell(14, 0x6F)], count: 128)
        let input = song([0: pathological], orders: [0])
        let actual = try collect(input, row: 0, iterations: 1)
        let expected = Planner.plan(input, startOrderIndex: 0, orderCount: 1)
        XCTAssertEqual(actual.rows.count, expected.pathLength)
        XCTAssertEqual(actual.diagnostics, expected.traversalDiagnostics)
        XCTAssertEqual(actual.boundaries.first?.cause, .rowGuard)

        let pattern = [[cell()], [cell(14, 0x60)], [cell(14, 0x61)], [cell()]]
        let baseline = try collect(song([0: pattern], orders: [0]), row: 2, iterations: 5)
        for count in [64, 256] {
            let candidate = try collect(song([0: pattern], orders: Array(repeating: 0, count: count)),
                row: 2, iterations: 5)
            XCTAssertEqual(candidate.rows, baseline.rows)
            XCTAssertEqual(candidate.diagnostics, baseline.diagnostics)
            XCTAssertEqual(candidate.state, baseline.state)
            XCTAssertEqual(candidate.state.rowLimit, baseline.state.rowLimit)
        }
    }

    func testArrayIndicesStaySeparateFromSourceLabelsAndInvalidOriginsAreRefused() throws {
        let input = song([0: Array(repeating: [cell()], count: 4)], orders: [0], labels: [10, 20, 30, 40])
        let actual = try collect(input, row: 2, iterations: 2)
        XCTAssertEqual(actual.rows.map(\.rowArrayIndex), [2, 3, 0, 1, 2, 3])
        XCTAssertEqual(actual.rows.map { $0.source.rowIndex }, [30, 40, 10, 20, 30, 40])
        for position in [PlaybackPosition(orderIndex: -1, patternIndex: 0, rowIndex: 0),
                         .init(orderIndex: 0, patternIndex: 1, rowIndex: 0),
                         .init(orderIndex: 0, patternIndex: 0, rowIndex: 4)] {
            XCTAssertNil(Planner.makeUserLoopState(input, initialPosition: position))
        }
    }

    func testFiniteSongColdBatchesMatchFullTwoOrderTraversalAndTiming() throws {
        let first = [[cell()], [cell(14, 0x60)],
            [cell(14, 0x61), cell(15, 0xE1)], [cell(11, 1), cell(13, 2)]]
        let second = [[cell()], [cell()], [cell(15, 3)], [cell()], [cell()]]
        let input = song([0: first, 1: second], orders: [0, 1])
        let origin = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 2)
        let whole = Planner.plan(input, startOrderIndex: 0, orderCount: input.orders.count,
            initialPosition: origin)
        XCTAssertEqual(whole.rows.map { "\($0.orderIndex):\($0.rowArrayIndex)" },
            ["0:2", "0:1", "0:2", "0:3", "1:2", "1:3", "1:4"])
        XCTAssertEqual(whole.stopReason, .songEnd)
        for rate in [44_100.0, 48_000] {
            let expectedTiming = PlaybackSongFxxTimingPlanner.plan(input, traversalPlan: whole,
                sampleRate: rate)
            for cap in [1, 2, 3] {
                let actual = try collectFinite(input, origin: origin, rate: rate, cap: cap)
                assertFiniteEquivalent(actual, to: whole, timing: expectedTiming)
                XCTAssertEqual(actual.state.terminalStopReason, .songEnd)
                XCTAssertNil(Planner.peekUserLoopRow(input, state: actual.state))
            }
        }
        // The explicit Loop factory still seals its outgoing B/D as a wrap.
        var loop = try XCTUnwrap(Planner.makeUserLoopState(input, initialPosition: origin))
        for row in 0..<4 {
            let step = try XCTUnwrap(Planner.nextUserLoopRow(input, state: &loop, syntheticRow: row))
            if row == 3 { XCTAssertNotNil(loop.pendingBoundary); XCTAssertNotNil(step.row) }
        }
        XCTAssertNil(loop.terminalStopReason)
    }

    func testFiniteSongCycleAndRowGuardsMatchFullPlanner() throws {
        let cycle = song([0: [[cell(11, 0)]]], orders: [0])
        let pathological = song([0: Array(repeating: [cell(14, 0x6F)], count: 128)], orders: [0])
        for (input, cap) in [(cycle, 1), (pathological, 512)] {
            let origin = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)
            let whole = Planner.plan(input, startOrderIndex: 0, orderCount: 1,
                initialPosition: origin)
            let expectedTiming = PlaybackSongFxxTimingPlanner.plan(input,
                traversalPlan: whole, sampleRate: 48_000)
            let actual = try collectFinite(input, origin: origin, rate: 48_000, cap: cap)
            assertFiniteEquivalent(actual, to: whole, timing: expectedTiming)
            XCTAssertTrue(whole.guardHit)
            XCTAssertEqual(actual.state.terminalStopReason, .traversalGuardHit)
            XCTAssertNil(Planner.peekUserLoopRow(input, state: actual.state))
        }
    }

    private struct FiniteCollected {
        var rows = [PlaybackSongTraversalRow]()
        var diagnostics = [PlaybackSongSyntheticTraversalDiagnostic]()
        var diagnosticOffsets = [Int]()
        var timings = [PlaybackSongFxxRowTiming]()
        var state: Planner.UserLoopState
    }

    private func collectFinite(_ input: PlaybackSong, origin: PlaybackPosition,
                               rate: Double, cap: Int) throws -> FiniteCollected {
        var state = try XCTUnwrap(Planner.makeFiniteSongState(input, initialPosition: origin))
        var clock = PlaybackSongFxxTimingPlanner.State(speed: input.initialTiming.speed,
            bpm: input.initialTiming.bpm, nextExactFrame: 0)
        var result = FiniteCollected(state: state)
        for _ in 0..<16 {
            let batch = try XCTUnwrap(Planner.planUserLoopBatch(input, state: state, timing: clock,
                sampleRate: rate, minimumHorizonFrames: Int.max, maximumRows: cap))
            let offset = result.rows.count
            result.diagnosticOffsets += Array(repeating: offset, count: batch.traversal.traversalDiagnostics.count)
            result.diagnostics += batch.traversal.traversalDiagnostics
            result.rows += batch.traversal.rows
            result.timings += batch.timing.rowTimings
            XCTAssertEqual(batch.iterationByRow, Array(repeating: 0, count: batch.traversal.rows.count))
            state = batch.terminalTraversal; clock = batch.timing.terminalState
            if state.terminalStopReason != nil {
                result.state = state
                return result
            }
        }
        XCTFail("Finite song did not terminate within the bounded fixture")
        result.state = state
        return result
    }

    private func assertFiniteEquivalent(_ actual: FiniteCollected, to whole: PlaybackSongTraversalPlan,
                                        timing: PlaybackSongFxxTimingPlan,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.rows.count, whole.rows.count, file: file, line: line)
        for (index, pair) in zip(actual.rows, whole.rows).enumerated() {
            XCTAssertEqual(pair.0.source, pair.1.source, "row \(index)", file: file, line: line)
            XCTAssertEqual(pair.0.rowArrayIndex, pair.1.rowArrayIndex, "row \(index)", file: file, line: line)
        }
        XCTAssertEqual(actual.timings.count, timing.rowTimings.count, file: file, line: line)
        for (a, b) in zip(actual.timings, timing.rowTimings) {
            XCTAssertEqual(a.rowStartExactFrame, b.rowStartExactFrame, file: file, line: line)
            XCTAssertEqual(a.rowEndExactFrame, b.rowEndExactFrame, file: file, line: line)
            XCTAssertEqual(a.effectiveSpeed, b.effectiveSpeed, file: file, line: line)
            XCTAssertEqual(a.effectiveBPM, b.effectiveBPM, file: file, line: line)
            XCTAssertEqual(a.patternDelayCycles, b.patternDelayCycles, file: file, line: line)
        }
        XCTAssertEqual(actual.diagnostics.count, whole.traversalDiagnostics.count, file: file, line: line)
        for (index, pair) in zip(actual.diagnostics, whole.traversalDiagnostics).enumerated() {
            let (a, b) = pair
            XCTAssertEqual(a.syntheticRow + actual.diagnosticOffsets[index], b.syntheticRow, file: file, line: line)
            XCTAssertEqual(a.kind, b.kind, file: file, line: line)
            XCTAssertEqual(a.status, b.status, file: file, line: line)
            XCTAssertEqual(a.source, b.source, file: file, line: line)
            XCTAssertEqual(a.channelIndex, b.channelIndex, file: file, line: line)
            XCTAssertEqual(a.effectType, b.effectType, file: file, line: line)
            XCTAssertEqual(a.effectParam, b.effectParam, file: file, line: line)
            XCTAssertEqual(a.targetOrderIndex, b.targetOrderIndex, file: file, line: line)
            XCTAssertEqual(a.targetPatternIndex, b.targetPatternIndex, file: file, line: line)
            XCTAssertEqual(a.targetRowIndex, b.targetRowIndex, file: file, line: line)
            XCTAssertEqual(a.nextOrderIndex, b.nextOrderIndex, file: file, line: line)
            XCTAssertEqual(a.loopStartRowIndex, b.loopStartRowIndex, file: file, line: line)
            XCTAssertEqual(a.loopRemaining, b.loopRemaining, file: file, line: line)
            XCTAssertEqual(a.loopLimit, b.loopLimit, file: file, line: line)
            XCTAssertEqual(a.combinedWithBxx, b.combinedWithBxx, file: file, line: line)
            XCTAssertEqual(a.combinedWithDxx, b.combinedWithDxx, file: file, line: line)
            XCTAssertEqual(a.policy, b.policy, file: file, line: line)
        }
    }

    private struct Collected {
        var rows = [PlaybackSongTraversalRow]()
        var diagnostics = [PlaybackSongSyntheticTraversalDiagnostic]()
        var boundaries = [Planner.UserLoopBoundary]()
        var state: Planner.UserLoopState
    }

    private func collect(_ input: PlaybackSong, row: Int, iterations: Int,
                         copyCheckpointEvery: Int = 0) throws -> Collected {
        var state = try XCTUnwrap(Planner.makeUserLoopState(input,
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: row)))
        var result = Collected(state: state)
        var steps = 0
        while result.boundaries.count < iterations && steps < state.rowLimit * max(1, iterations) + iterations {
            steps += 1
            let step = try XCTUnwrap(Planner.nextUserLoopRow(input, state: &state, syntheticRow: result.rows.count))
            if let row = step.row { result.rows.append(row) }
            result.diagnostics += step.diagnostics
            switch step.transition {
            case .next:
                XCTAssertNotNil(Planner.peekUserLoopRow(input, state: state))
            case .iterationBoundary(let boundary):
                result.boundaries.append(boundary)
                XCTAssertEqual(Planner.peekUserLoopRow(input, state: state)?.index, input.pattern(for: 0)?.rows.first?.index)
                XCTAssertNil(Planner.nextUserLoopRow(input, state: &state, syntheticRow: result.rows.count))
                XCTAssertTrue(Planner.finishUserLoopIteration(input, state: &state))
            }
            if copyCheckpointEvery > 0 && steps % copyCheckpointEvery == 0 {
                let exported = state
                state = exported
            }
        }
        XCTAssertEqual(result.boundaries.count, iterations)
        result.state = state
        return result
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func song(_ patterns: [Int: [[PlaybackCell]]], orders: [Int], labels: [Int]? = nil) -> PlaybackSong {
        .init(title: "Public user-loop traversal control", orders: orders.enumerated().map {
            .init(orderIndex: $0.offset, patternIndex: $0.element)
        }, patternsByIndex: patterns.mapValues { cells in
            // The key is installed by the separate dictionary construction below.
            PlaybackPattern(index: 0, rows: cells.enumerated().map {
                PlaybackRow(index: labels?[$0.offset] ?? $0.offset, cells: $0.element)
            })
        }.reduce(into: [Int: PlaybackPattern]()) { result, item in
            result[item.key] = PlaybackPattern(index: item.key, rows: item.value.rows)
        }, instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
