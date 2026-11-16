import Foundation

struct PlaybackSongTraversalRow: Equatable {
    let source: PlaybackPosition
    let orderIndex: Int
    let pattern: PlaybackPattern
    let row: PlaybackRow
    let rowArrayIndex: Int
    let syntheticRow: Int
}

struct PlaybackSongTraversalPlan: Equatable {
    let rows: [PlaybackSongTraversalRow]
    let adaptedOrders: [PlaybackSongSyntheticOrderDiagnostic]
    let traversalDiagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
    let pathLength: Int
    let stopReason: PlaybackSongSyntheticTraversalStopReason
    let guardHit: Bool
}

enum PlaybackSongTraversalPlanner {
    struct LoopKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let channelIndex: Int
    }

    struct TraversalPositionKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let rowArrayIndex: Int
    }

    private struct TraversalCommand {
        let channelIndex: Int
        let cell: PlaybackCell
    }

    private struct DxxTarget {
        let decodedRow: Int
        let targetRow: Int
        let invalidBCD: Bool
        let outOfRange: Bool
    }

    /// Bounded executed traversal state. Ordinary song playback may revisit an
    /// authored position; each production invocation is bounded by its row cap.
    struct UserLoopState: Equatable {
        enum Mode: Equatable { case explicitLoop, finiteSong, songPlayback }
        var orderIndex: Int
        var patternIndex: Int
        var rowLimit: Int
        fileprivate var mode: Mode = .explicitLoop
        fileprivate(set) var terminalStopReason: PlaybackSongSyntheticTraversalStopReason?
        fileprivate(set) var nextRowArrayIndex: Int
        fileprivate(set) var iteration: UInt64 = 0
        fileprivate(set) var rowsInIteration = 0
        fileprivate(set) var pendingBoundary: UserLoopBoundary?
        fileprivate var loopStarts = [LoopKey: Int]()
        fileprivate var loopRemaining = [LoopKey: Int]()
        fileprivate var visitedPositions = Set<TraversalPositionKey>()
    }

    /// Keeps the underlying traversal refusal/guard distinct from transport wrap.
    struct UserLoopBoundary: Equatable {
        enum Cause: Equatable { case naturalEnd, positionExit, cycleGuard, rowGuard }
        let cause: Cause
        let targetOrderIndex: Int
        let targetRowArrayIndex: Int
        let traversalStopReason: PlaybackSongSyntheticTraversalStopReason?
    }

    enum UserLoopTransition: Equatable {
        case next
        case iterationBoundary(UserLoopBoundary)
    }

    struct UserLoopStep: Equatable {
        // Nil only for a row guard detected before execution. Never interpret it.
        let row: PlaybackSongTraversalRow?
        let diagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
        let transition: UserLoopTransition
    }

    /// One bounded semantic-production interval. No state is acknowledged by planning it.
    struct UserLoopBatch: Equatable {
        let traversal: PlaybackSongTraversalPlan
        let timing: PlaybackSongFxxTimingPlan
        let terminalTraversal: UserLoopState
        let iterationByRow: [UInt64]
        let nextRow: PlaybackRow?
    }

    /// Uses the same traversal and Fxx reducers as full planning. The explicit row
    /// cap bounds work even when a caller requests an excessive time horizon.
    static func planUserLoopBatch(_ song: PlaybackSong, state initialState: UserLoopState,
        timing initialTiming: PlaybackSongFxxTimingPlanner.State, sampleRate: Double,
        minimumHorizonFrames: Int, maximumRows: Int,
        untilFrame: Int? = nil, minimumNaturalBoundaryTailFrames: Int = 0,
        isCancelled: (() -> Bool)? = nil) -> UserLoopBatch? {
        precondition(minimumHorizonFrames > 0 && maximumRows > 0 && maximumRows <= 512 && minimumNaturalBoundaryTailFrames >= 0)
        guard initialTiming.nextExactFrame.isFinite, initialTiming.nextExactFrame >= 0,
              initialTiming.nextExactFrame < Double(Int.max), sampleRate.isFinite, sampleRate > 0 else { return nil }
        var state = initialState, timing = initialTiming
        var rows = [PlaybackSongTraversalRow](), timings = [PlaybackSongFxxRowTiming]()
        var diagnostics = [PlaybackSongSyntheticTraversalDiagnostic]()
        var changes = [PlaybackSongSyntheticTimingChangeDiagnostic](), iterations = [UInt64]()
        var orders = [PlaybackSongSyntheticOrderDiagnostic]()
        rows.reserveCapacity(min(maximumRows, 64)); timings.reserveCapacity(min(maximumRows, 64))
        let firstFrame = Int(initialTiming.nextExactFrame.rounded(.down))
        if let untilFrame, untilFrame <= firstFrame { return nil }
        var firstNaturalFrame: Int?
        var capInput: (UserLoopState, PlaybackSongFxxTimingPlanner.State, Int, Int, [PlaybackSongSyntheticOrderDiagnostic])?
        while rows.count < maximumRows {
            if state.terminalStopReason != nil { break }
            if untilFrame == nil, minimumNaturalBoundaryTailFrames > 0, rows.count == maximumRows - 1, !rows.isEmpty {
                capInput = (state, timing, diagnostics.count, changes.count, orders)
            }
            if isCancelled?() == true { return nil }
            if state.pendingBoundary != nil, !finishUserLoopIteration(song, state: &state) { return nil }
            let iteration = state.iteration
            guard let step = nextUserLoopRow(song, state: &state, syntheticRow: rows.count) else { return nil }
            diagnostics.append(contentsOf: step.diagnostics)
            guard let row = step.row else {
                if state.terminalStopReason != nil { break }
                // A pre-execution guard has no row/tick. Its explicit iteration
                // transition is retained and the next entry starts at row zero.
                guard state.pendingBoundary != nil else { return nil }
                continue
            }
            if rows.isEmpty || iterations.last != iteration || orders.last?.requestedOrderIndex != row.orderIndex {
                orders.append(.init(requestedOrderIndex: row.orderIndex, patternIndex: row.pattern.index,
                    syntheticStartRow: rows.count, rowCount: 0, status: .adapted))
            }
            let last = orders.removeLast()
            orders.append(.init(requestedOrderIndex: last.requestedOrderIndex, patternIndex: last.patternIndex,
                syntheticStartRow: last.syntheticStartRow, rowCount: last.rowCount + 1, status: last.status))
            if firstNaturalFrame == nil, let previous = iterations.last, previous != iteration {
                firstNaturalFrame = timings.last?.rowEndFrame
            }
            rows.append(row); iterations.append(iteration)
            let rowTiming = PlaybackSongFxxTimingPlanner.advance(row: row.row, source: row.source,
                syntheticRow: row.syntheticRow, sampleRate: sampleRate, state: &timing, timingChanges: &changes)
            timings.append(rowTiming)
            if firstNaturalFrame == nil, state.pendingBoundary != nil { firstNaturalFrame = rowTiming.rowEndFrame }
            if let untilFrame {
                guard rowTiming.rowEndFrame <= untilFrame else { return nil }
                if rowTiming.rowEndFrame == untilFrame { break }
            } else if rowTiming.rowEndFrame - firstFrame >= minimumHorizonFrames {
                if let natural = firstNaturalFrame, rowTiming.rowEndFrame - natural < minimumNaturalBoundaryTailFrames,
                   rows.count < maximumRows { continue }
                break
            }
        }
        // At the hard cap, leave a sole natural endpoint for the next bounded batch
        // rather than creating an optional-edit deadline identical to mandatory E.
        if untilFrame == nil, minimumNaturalBoundaryTailFrames > 0, rows.count == maximumRows,
           firstNaturalFrame == timings.last?.rowEndFrame, let capInput {
            state = capInput.0; timing = capInput.1
            diagnostics.removeSubrange(capInput.2..<diagnostics.count)
            changes.removeSubrange(capInput.3..<changes.count); orders = capInput.4
            rows.removeLast(); timings.removeLast(); iterations.removeLast()
        }
        if state.mode == .finiteSong, state.terminalStopReason == nil,
           state.rowsInIteration >= state.rowLimit, !rows.isEmpty {
            // The full planner reports its row guard before the next row. Seal
            // it here so a capped batch carries the terminal diagnostic.
            if let guardStep = nextUserLoopRow(song, state: &state, syntheticRow: rows.count) {
                diagnostics.append(contentsOf: guardStep.diagnostics)
            }
        }
        guard !rows.isEmpty else { return nil }
        if let untilFrame, timings.last?.rowEndFrame != untilFrame { return nil }
        let traversal = PlaybackSongTraversalPlan(rows: rows, adaptedOrders: orders,
            traversalDiagnostics: diagnostics, pathLength: rows.count,
            stopReason: state.terminalStopReason ?? .selectedRangeEnd,
            guardHit: diagnostics.contains { $0.status == .loopLimitHit })
        return .init(traversal: traversal,
            timing: .init(sampleRate: sampleRate, initialSpeed: initialTiming.speed, initialBPM: initialTiming.bpm,
                rowTimings: timings, timingChanges: changes, finalSpeed: timing.speed, finalBPM: timing.bpm,
                endExactFrame: timing.nextExactFrame), terminalTraversal: state,
            iterationByRow: iterations, nextRow: peekUserLoopRow(song, state: state))
    }

    /// Creates fresh loop state, including only the accepted structural E60 seam.
    /// No skipped row is executed; source row labels remain separate from indices.
    static func makeUserLoopState(_ song: PlaybackSong, initialPosition: PlaybackPosition) -> UserLoopState? {
        guard song.orders.indices.contains(initialPosition.orderIndex),
              let pattern = song.pattern(for: initialPosition.orderIndex),
              pattern.index == initialPosition.patternIndex,
              pattern.rows.indices.contains(initialPosition.rowIndex) else { return nil }
        var state = UserLoopState(orderIndex: initialPosition.orderIndex,
            patternIndex: pattern.index,
            rowLimit: traversalRowLimit(song: song, startOrderIndex: initialPosition.orderIndex,
                selectedEndOrderIndex: initialPosition.orderIndex + 1),
            nextRowArrayIndex: initialPosition.rowIndex)
        state.loopStarts = coldLoopStarts(pattern: pattern, orderIndex: state.orderIndex,
            beforeRow: state.nextRowArrayIndex)
        return state
    }

    /// Finite analysis from a cold origin, including position and total-row guards.
    static func makeFiniteSongState(_ song: PlaybackSong, initialPosition: PlaybackPosition) -> UserLoopState? {
        guard var state = makeUserLoopState(song, initialPosition: initialPosition) else { return nil }
        state.mode = .finiteSong
        state.rowLimit = traversalRowLimit(song: song, startOrderIndex: 0,
            selectedEndOrderIndex: song.orders.count)
        return state
    }

    /// Live work is bounded per invocation, independently of finite duration analysis.
    static func makeSongPlaybackState(_ song: PlaybackSong, initialPosition: PlaybackPosition) -> UserLoopState? {
        guard var state = makeFiniteSongState(song, initialPosition: initialPosition) else { return nil }
        state.mode = .songPlayback
        return state
    }

    /// A new editable revision enters naturally at its verified old iteration
    /// boundary. Only traversal entry state resets; musical channel/timing state
    /// belongs to the existing continuation checkpoint.
    static func resumeUserLoopAtNaturalEntry(_ song: PlaybackSong, previous: UserLoopState) -> UserLoopState? {
        guard previous.mode == .explicitLoop, previous.pendingBoundary != nil, previous.iteration < .max,
              var state = makeUserLoopState(song, initialPosition: .init(orderIndex: previous.orderIndex,
                patternIndex: previous.patternIndex, rowIndex: 0)) else { return nil }
        state.iteration = previous.iteration + 1
        return state
    }

    /// Executes the existing traversal reducer once and retains only bounded state.
    /// Outgoing order/cycle decisions seal an explicit user-loop iteration while
    /// retaining their exact existing diagnostics; they do not become accepted B/D.
    static func nextUserLoopRow(_ song: PlaybackSong, state: inout UserLoopState,
                               syntheticRow: Int) -> UserLoopStep? {
        guard syntheticRow >= 0, state.pendingBoundary == nil, state.terminalStopReason == nil,
              let pattern = song.pattern(for: state.orderIndex), pattern.index == state.patternIndex,
              pattern.rows.indices.contains(state.nextRowArrayIndex) else { return nil }
        let rowArrayIndex = state.nextRowArrayIndex
        let row = pattern.rows[rowArrayIndex]
        let source = PlaybackPosition(orderIndex: state.orderIndex,
            patternIndex: pattern.index, rowIndex: row.index)
        if state.mode != .songPlayback && state.rowsInIteration >= state.rowLimit {
            let boundary = UserLoopBoundary(cause: .rowGuard,
                targetOrderIndex: state.orderIndex, targetRowArrayIndex: rowArrayIndex,
                traversalStopReason: .traversalGuardHit)
            if state.mode == .finiteSong { state.terminalStopReason = .traversalGuardHit }
            else { state.pendingBoundary = boundary }
            return UserLoopStep(row: nil, diagnostics: [loopLimitDiagnostic(
                source: source, syntheticRow: syntheticRow, loopLimit: state.rowLimit)],
                transition: .iterationBoundary(boundary))
        }
        let traversalRow = PlaybackSongTraversalRow(source: source, orderIndex: state.orderIndex,
            pattern: pattern, row: row, rowArrayIndex: rowArrayIndex, syntheticRow: syntheticRow)
        if state.mode != .songPlayback {
            state.rowsInIteration += 1
            state.visitedPositions.insert(.init(orderIndex: state.orderIndex,
                patternIndex: pattern.index, rowArrayIndex: rowArrayIndex))
        }
        var diagnostics = [PlaybackSongSyntheticTraversalDiagnostic]()
        let decision = nextPosition(after: row, source: source, currentRowIndex: rowArrayIndex,
            pattern: pattern, song: song, startOrderIndex: 0,
            selectedEndOrderIndex: song.orders.count, syntheticRow: syntheticRow,
            maxTraversalRows: state.rowLimit, loopStarts: &state.loopStarts,
            loopRemaining: &state.loopRemaining, visitedPositions: state.visitedPositions,
            diagnostics: &diagnostics)
        if state.mode != .explicitLoop {
            // Live playback leaves visitedPositions empty. A bounded batch yields
            // a checkpoint instead of converting an authored Bxx to song end.
            // A new pattern occurrence owns fresh E6 anchors/counters (G38B).
            if state.mode == .songPlayback && (decision.orderIndex != state.orderIndex ||
                (decision.rowIndex == 0 && row.cells.contains { $0.effectType == 0x0B || $0.effectType == 0x0D })) {
                state.loopStarts.removeAll(keepingCapacity: true)
                state.loopRemaining.removeAll(keepingCapacity: true)
            }
            if let reason = decision.stopReason {
                state.terminalStopReason = reason == .selectedRangeEnd ? .songEnd : reason
            } else if decision.orderIndex == state.orderIndex {
                state.nextRowArrayIndex = decision.rowIndex
            } else {
                var orderIndex = decision.orderIndex
                var rowIndex = decision.rowIndex
                // The full traversal skips natural empty orders; B/D refusals
                // have already been reported by the shared position reducer.
                while song.orders.indices.contains(orderIndex) {
                    guard let next = song.pattern(for: orderIndex) else {
                        state.terminalStopReason = .missingPattern
                        break
                    }
                    if !next.rows.isEmpty {
                        state.orderIndex = orderIndex
                        state.patternIndex = next.index
                        state.nextRowArrayIndex = rowIndex
                        break
                    }
                    orderIndex += 1
                    rowIndex = 0
                }
                if orderIndex >= song.orders.count { state.terminalStopReason = .songEnd }
            }
            return UserLoopStep(row: traversalRow, diagnostics: diagnostics, transition: .next)
        }
        let hasPositionCommand = row.cells.contains { $0.effectType == 0x0B || $0.effectType == 0x0D }
        if decision.stopReason == .traversalGuardHit || decision.orderIndex != state.orderIndex {
            let boundary = UserLoopBoundary(cause: decision.stopReason == .traversalGuardHit
                ? .cycleGuard : hasPositionCommand ? .positionExit : .naturalEnd,
                targetOrderIndex: decision.orderIndex, targetRowArrayIndex: decision.rowIndex,
                traversalStopReason: decision.stopReason)
            state.pendingBoundary = boundary
            return UserLoopStep(row: traversalRow, diagnostics: diagnostics,
                transition: .iterationBoundary(boundary))
        }
        // A valid same-order forward Bxx retains the reducer's target. E6 and
        // combined held-row transitions likewise keep their existing pending row.
        guard decision.stopReason == nil, pattern.rows.indices.contains(decision.rowIndex) else {
            let boundary = UserLoopBoundary(cause: .positionExit,
                targetOrderIndex: decision.orderIndex, targetRowArrayIndex: decision.rowIndex,
                traversalStopReason: decision.stopReason ?? .outOfRange)
            state.pendingBoundary = boundary
            return UserLoopStep(row: traversalRow, diagnostics: diagnostics,
                transition: .iterationBoundary(boundary))
        }
        state.nextRowArrayIndex = decision.rowIndex
        return UserLoopStep(row: traversalRow, diagnostics: diagnostics, transition: .next)
    }

    /// Peeks without executing effects. A sealed explicit-loop template's next
    /// raw row is zero, while a mere batch boundary preserves the current row.
    static func peekUserLoopRow(_ song: PlaybackSong, state: borrowing UserLoopState) -> PlaybackRow? {
        guard state.terminalStopReason == nil else { return nil }
        guard let pattern = song.pattern(for: state.orderIndex), pattern.index == state.patternIndex else { return nil }
        let row = state.pendingBoundary == nil ? state.nextRowArrayIndex : 0
        guard pattern.rows.indices.contains(row) else { return nil }
        return pattern.rows[row]
    }

    /// Applies natural pattern entry only at a completed user-loop iteration.
    /// G38B keeps repeated order occurrences independent; batch splits must not
    /// call this method. Source/channel/effect memories are owned elsewhere.
    static func finishUserLoopIteration(_ song: PlaybackSong, state: inout UserLoopState) -> Bool {
        guard state.mode == .explicitLoop, state.pendingBoundary != nil,
              let pattern = song.pattern(for: state.orderIndex), pattern.index == state.patternIndex,
              !pattern.rows.isEmpty else { return false }
        let next = state.iteration.addingReportingOverflow(1)
        guard !next.overflow else { return false }
        state.iteration = next.partialValue
        state.nextRowArrayIndex = 0
        state.rowsInIteration = 0
        state.visitedPositions.removeAll(keepingCapacity: true)
        state.loopStarts.removeAll(keepingCapacity: true)
        state.loopRemaining.removeAll(keepingCapacity: true)
        state.pendingBoundary = nil
        return true
    }

    private static func coldLoopStarts(pattern: PlaybackPattern, orderIndex: Int,
                                       beforeRow: Int) -> [LoopKey: Int] {
        var starts = [LoopKey: Int]()
        for rowIndex in 0..<beforeRow {
            for (channelIndex, cell) in pattern.rows[rowIndex].cells.enumerated()
                where cell.effectType == 0x0E && cell.effectParam == 0x60 {
                starts[LoopKey(orderIndex: orderIndex, patternIndex: pattern.index,
                    channelIndex: channelIndex)] = rowIndex
            }
        }
        return starts
    }

    static func plan(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        initialPosition: PlaybackPosition? = nil
    ) -> PlaybackSongTraversalPlan {
        let safeOrderCount = max(0, orderCount)
        guard safeOrderCount > 0 else {
            return PlaybackSongTraversalPlan(
                rows: [],
                adaptedOrders: [],
                traversalDiagnostics: [],
                pathLength: 0,
                stopReason: .notStarted,
                guardHit: false
            )
        }

        let selectedEndOrderIndex = startOrderIndex + safeOrderCount
        guard selectedEndOrderIndex > startOrderIndex else {
            return PlaybackSongTraversalPlan(
                rows: [],
                adaptedOrders: [],
                traversalDiagnostics: [],
                pathLength: 0,
                stopReason: .outOfRange,
                guardHit: false
            )
        }

        guard song.orders.indices.contains(startOrderIndex) else {
            return PlaybackSongTraversalPlan(
                rows: [],
                adaptedOrders: [
                    PlaybackSongSyntheticOrderDiagnostic(
                        requestedOrderIndex: startOrderIndex,
                        patternIndex: nil,
                        syntheticStartRow: 0,
                        rowCount: 0,
                        status: .invalidOrder
                    ),
                ],
                traversalDiagnostics: [],
                pathLength: 0,
                stopReason: .invalidOrder,
                guardHit: false
            )
        }

        let maxTraversalRows = traversalRowLimit(
            song: song,
            startOrderIndex: startOrderIndex,
            selectedEndOrderIndex: selectedEndOrderIndex
        )
        var rows = [PlaybackSongTraversalRow]()
        var adaptedOrders = [PlaybackSongSyntheticOrderDiagnostic]()
        var diagnostics = [PlaybackSongSyntheticTraversalDiagnostic]()
        var loopStarts = [LoopKey: Int]()
        var loopRemaining = [LoopKey: Int]()
        var visitedPositions = Set<TraversalPositionKey>()
        var currentOrderIndex = initialPosition?.orderIndex ?? startOrderIndex
        var currentRowIndex = initialPosition?.rowIndex ?? 0
        if let initialPosition {
            guard (startOrderIndex..<selectedEndOrderIndex).contains(currentOrderIndex),
                  let pattern = song.pattern(for: currentOrderIndex),
                  pattern.index == initialPosition.patternIndex,
                  pattern.rows.indices.contains(currentRowIndex) else {
                return PlaybackSongTraversalPlan(rows: [], adaptedOrders: [], traversalDiagnostics: [],
                    pathLength: 0, stopReason: .outOfRange, guardHit: false)
            }
            // Cold entry may read structural anchors, but must not execute skipped
            // cells or seed musical state, loop counters, or execution diagnostics.
            loopStarts = coldLoopStarts(pattern: pattern, orderIndex: currentOrderIndex,
                beforeRow: currentRowIndex)
        }
        var stopReason: PlaybackSongSyntheticTraversalStopReason = .selectedRangeEnd
        var guardHit = false

        while currentOrderIndex >= startOrderIndex,
              currentOrderIndex < selectedEndOrderIndex {
            guard song.orders.indices.contains(currentOrderIndex) else {
                stopReason = .invalidOrder
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: currentOrderIndex,
                    patternIndex: nil,
                    syntheticStartRow: rows.count,
                    rowCount: 0,
                    status: .invalidOrder
                ))
                break
            }
            let order = song.orders[currentOrderIndex]
            guard let pattern = song.patternsByIndex[order.patternIndex] else {
                stopReason = .missingPattern
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: currentOrderIndex,
                    patternIndex: order.patternIndex,
                    syntheticStartRow: rows.count,
                    rowCount: 0,
                    status: .missingPattern
                ))
                break
            }
            guard !pattern.rows.isEmpty else {
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: currentOrderIndex,
                    patternIndex: pattern.index,
                    syntheticStartRow: rows.count,
                    rowCount: 0,
                    status: .adapted
                ))
                currentOrderIndex += 1
                currentRowIndex = 0
                continue
            }
            currentRowIndex = min(max(0, currentRowIndex), pattern.rows.count - 1)
            let visitStartRow = rows.count
            var visitedRowsInOrder = 0

            while currentOrderIndex >= startOrderIndex,
                  currentOrderIndex < selectedEndOrderIndex,
                  song.orders.indices.contains(currentOrderIndex),
                  currentOrderIndex == order.orderIndex,
                  currentRowIndex < pattern.rows.count {
                if rows.count >= maxTraversalRows {
                    guardHit = true
                    stopReason = .traversalGuardHit
                    diagnostics.append(loopLimitDiagnostic(
                        source: PlaybackPosition(
                            orderIndex: currentOrderIndex,
                            patternIndex: pattern.index,
                            rowIndex: pattern.rows[currentRowIndex].index
                        ),
                        syntheticRow: rows.count,
                        loopLimit: maxTraversalRows
                    ))
                    break
                }

                let row = pattern.rows[currentRowIndex]
                let syntheticRow = rows.count
                let source = PlaybackPosition(
                    orderIndex: currentOrderIndex,
                    patternIndex: pattern.index,
                    rowIndex: row.index
                )
                visitedPositions.insert(TraversalPositionKey(
                    orderIndex: currentOrderIndex,
                    patternIndex: pattern.index,
                    rowArrayIndex: currentRowIndex
                ))
                rows.append(PlaybackSongTraversalRow(
                    source: source,
                    orderIndex: currentOrderIndex,
                    pattern: pattern,
                    row: row,
                    rowArrayIndex: currentRowIndex,
                    syntheticRow: syntheticRow
                ))
                visitedRowsInOrder += 1

                let decision = nextPosition(
                    after: row,
                    source: source,
                    currentRowIndex: currentRowIndex,
                    pattern: pattern,
                    song: song,
                    startOrderIndex: startOrderIndex,
                    selectedEndOrderIndex: selectedEndOrderIndex,
                    syntheticRow: syntheticRow,
                    maxTraversalRows: maxTraversalRows,
                    loopStarts: &loopStarts,
                    loopRemaining: &loopRemaining,
                    visitedPositions: visitedPositions,
                    diagnostics: &diagnostics
                )
                currentOrderIndex = decision.orderIndex
                currentRowIndex = decision.rowIndex
                if let reason = decision.stopReason {
                    if reason == .traversalGuardHit {
                        guardHit = true
                    }
                    stopReason = reason
                    break
                }
            }

            adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                requestedOrderIndex: order.orderIndex,
                patternIndex: pattern.index,
                syntheticStartRow: visitStartRow,
                rowCount: visitedRowsInOrder,
                status: .adapted
            ))
            if guardHit || stopReason != .selectedRangeEnd {
                break
            }
        }

        if rows.isEmpty, adaptedOrders.isEmpty {
            stopReason = .notStarted
        } else if currentOrderIndex >= selectedEndOrderIndex, stopReason == .selectedRangeEnd {
            stopReason = selectedEndOrderIndex >= song.orders.count ? .songEnd : .selectedRangeEnd
        }

        return PlaybackSongTraversalPlan(
            rows: rows,
            adaptedOrders: adaptedOrders,
            traversalDiagnostics: diagnostics,
            pathLength: rows.count,
            stopReason: stopReason,
            guardHit: guardHit
        )
    }

    private struct NextPositionDecision {
        let orderIndex: Int
        let rowIndex: Int
        let stopReason: PlaybackSongSyntheticTraversalStopReason?
    }

    private static func nextPosition(
        after row: PlaybackRow,
        source: PlaybackPosition,
        currentRowIndex: Int,
        pattern: PlaybackPattern,
        song: PlaybackSong,
        startOrderIndex: Int,
        selectedEndOrderIndex: Int,
        syntheticRow: Int,
        maxTraversalRows: Int,
        loopStarts: inout [LoopKey: Int],
        loopRemaining: inout [LoopKey: Int],
        visitedPositions: Set<TraversalPositionKey>,
        diagnostics: inout [PlaybackSongSyntheticTraversalDiagnostic]
    ) -> NextPositionDecision {
        let bxx = lastCommand(in: row, effectType: 0x0B)
        let dxx = lastCommand(in: row, effectType: 0x0D)
        var e6xCommands = [TraversalCommand]()
        for (channelIndex, cell) in row.cells.enumerated() where isE6x(cell) {
            e6xCommands.append(TraversalCommand(channelIndex: channelIndex, cell: cell))
        }
        let hasBxx = bxx != nil
        let hasDxx = dxx != nil

        for command in e6xCommands {
            let value = Int(command.cell.effectParam & 0x0F)
            let loopKey = LoopKey(orderIndex: source.orderIndex, patternIndex: source.patternIndex, channelIndex: command.channelIndex)
            if value == 0 {
                loopStarts[loopKey] = currentRowIndex
                diagnostics.append(PlaybackSongSyntheticTraversalDiagnostic(
                    kind: .e6xPatternLoop,
                    status: .loopStartMarked,
                    source: source,
                    channelIndex: command.channelIndex,
                    syntheticRow: syntheticRow,
                    effectType: command.cell.effectType,
                    effectParam: command.cell.effectParam,
                    targetOrderIndex: source.orderIndex,
                    targetPatternIndex: source.patternIndex,
                    targetRowIndex: row.index,
                    nextOrderIndex: nil,
                    loopStartRowIndex: row.index,
                    loopRemaining: nil,
                    loopLimit: nil,
                    combinedWithBxx: hasBxx,
                    combinedWithDxx: hasDxx,
                    policy: "e60_marks_per_channel_order_pattern_loop_start"
                ))
            }
        }

        // Tick-zero writers share a pending row, in channel order. B resets it,
        // D replaces it, and every taken E6 writes it even alongside an order jump.
        let positionOrder = bxx.map { Int($0.cell.effectParam) } ?? (source.orderIndex + 1)
        let positionPattern = dxx == nil ? nil : patternForOrder(positionOrder, in: song)
        var pendingRow = 0
        var pendingRowChannel = bxx?.channelIndex ?? -1
        if let dxx, dxx.channelIndex > pendingRowChannel {
            pendingRow = resolvedDxxTarget(effectParam: dxx.cell.effectParam, targetPattern: positionPattern).targetRow
            pendingRowChannel = dxx.channelIndex
        }
        var loopRequested = false
        let heldTransition = (hasBxx || hasDxx || !e6xCommands.isEmpty) && (row.cells.last(where: {
            $0.effectType == 0x0E && $0.effectParam >> 4 == 0x0E
        })?.effectParam ?? 0) & 15 > 0

        for command in e6xCommands {
            let value = Int(command.cell.effectParam & 0x0F)
            guard value > 0 else {
                continue
            }
            let loopKey = LoopKey(orderIndex: source.orderIndex, patternIndex: source.patternIndex, channelIndex: command.channelIndex)
            // Composable patterns own their anchors. Earlier patterns cannot
            // suppress this pattern's implicit first-slot origin (G38B policy).
            let loopStart = loopStarts[loopKey] ?? 0
            // One counter per channel within the existing local anchor scope.
            // A completed invocation rearms subsequent loop sites on that channel.
            let countKey = loopKey
            let remainingBefore = loopRemaining[countKey] ?? value
            guard remainingBefore > 0 else {
                loopRemaining.removeValue(forKey: countKey)
                diagnostics.append(PlaybackSongSyntheticTraversalDiagnostic(
                    kind: .e6xPatternLoop,
                    status: .applied,
                    source: source,
                    channelIndex: command.channelIndex,
                    syntheticRow: syntheticRow,
                    effectType: command.cell.effectType,
                    effectParam: command.cell.effectParam,
                    targetOrderIndex: source.orderIndex,
                    targetPatternIndex: source.patternIndex,
                    targetRowIndex: nil,
                    nextOrderIndex: nil,
                    loopStartRowIndex: pattern.rows[min(max(0, loopStart), pattern.rows.count - 1)].index,
                    loopRemaining: 0,
                    loopLimit: nil,
                    combinedWithBxx: hasBxx,
                    combinedWithDxx: hasDxx,
                    policy: "e6x_loop_count_exhausted_continue"
                ))
                continue
            }
            let remainingAfter = remainingBefore - 1
            loopRemaining[countKey] = remainingAfter
            let targetRow = min(max(0, loopStart), pattern.rows.count - 1)
            diagnostics.append(PlaybackSongSyntheticTraversalDiagnostic(
                kind: .e6xPatternLoop,
                status: .loopTaken,
                source: source,
                channelIndex: command.channelIndex,
                syntheticRow: syntheticRow,
                effectType: command.cell.effectType,
                effectParam: command.cell.effectParam,
                targetOrderIndex: source.orderIndex,
                targetPatternIndex: source.patternIndex,
                targetRowIndex: pattern.rows[targetRow].index,
                nextOrderIndex: nil,
                loopStartRowIndex: pattern.rows[targetRow].index,
                loopRemaining: remainingAfter,
                loopLimit: nil,
                combinedWithBxx: hasBxx,
                combinedWithDxx: hasDxx,
                policy: "e6x_per_channel_order_pattern_loop_count"
            ))
            loopRequested = true
            if command.channelIndex > pendingRowChannel {
                pendingRow = targetRow
                pendingRowChannel = command.channelIndex
            }
        }

        if let bxx {
            let targetOrder = Int(bxx.cell.effectParam)
            let targetPatternForSelectedRange = targetOrder >= startOrderIndex && targetOrder < selectedEndOrderIndex
                ? patternForOrder(targetOrder, in: song)
                : nil
            let target = dxx.flatMap {
                resolvedDxxTarget(
                    effectParam: $0.cell.effectParam,
                    targetPattern: targetPatternForSelectedRange
                )
            }
            if let dxx {
                diagnostics.append(dxxDiagnostic(
                    command: dxx,
                    source: source,
                    syntheticRow: syntheticRow,
                    targetOrder: targetOrder,
                    targetPattern: targetPatternForSelectedRange,
                    target: target,
                    combinedWithBxx: true
                ))
            }
            guard targetOrder >= startOrderIndex,
                  targetOrder < selectedEndOrderIndex,
                  song.orders.indices.contains(targetOrder),
                  let targetPattern = patternForOrder(targetOrder, in: song),
                  !targetPattern.rows.isEmpty else {
                diagnostics.append(PlaybackSongSyntheticTraversalDiagnostic(
                    kind: .bxxPositionJump,
                    status: .outOfRange,
                    source: source,
                    channelIndex: bxx.channelIndex,
                    syntheticRow: syntheticRow,
                    effectType: bxx.cell.effectType,
                    effectParam: bxx.cell.effectParam,
                    targetOrderIndex: targetOrder,
                    targetPatternIndex: nil,
                    targetRowIndex: target?.targetRow ?? 0,
                    nextOrderIndex: nil,
                    loopStartRowIndex: nil,
                    loopRemaining: nil,
                    loopLimit: nil,
                    combinedWithBxx: false,
                    combinedWithDxx: dxx != nil,
                    policy: pendingRowChannel == bxx.channelIndex
                        ? (dxx == nil ? "bxx_jumps_to_order_row_zero" : "bxx_resets_earlier_dxx_pending_row")
                        : (pendingRowChannel == dxx?.channelIndex
                            ? "bxx_uses_dxx_row_target_when_same_row" : "bxx_uses_later_e6x_pending_row")
                ))
                return NextPositionDecision(orderIndex: targetOrder, rowIndex: 0, stopReason: .outOfRange)
            }
            let targetRow = pendingRow < targetPattern.rows.count ? max(0, pendingRow) : 0
            if visitedPositions.contains(TraversalPositionKey(
                orderIndex: targetOrder,
                patternIndex: targetPattern.index,
                rowArrayIndex: targetRow
            )) {
                diagnostics.append(positionCycleGuardDiagnostic(
                    kind: .bxxPositionJump,
                    command: bxx,
                    source: source,
                    syntheticRow: syntheticRow,
                    targetOrderIndex: targetOrder,
                    targetPatternIndex: targetPattern.index,
                    targetRowIndex: targetPattern.rows[targetRow].index,
                    loopLimit: maxTraversalRows,
                    combinedWithBxx: false,
                    combinedWithDxx: dxx != nil,
                    policy: dxx == nil
                        ? "bxx_position_cycle_guard"
                        : "bxx_dxx_position_cycle_guard"
                ))
                return NextPositionDecision(orderIndex: targetOrder, rowIndex: targetRow, stopReason: .traversalGuardHit)
            }
            diagnostics.append(PlaybackSongSyntheticTraversalDiagnostic(
                kind: .bxxPositionJump,
                status: .applied,
                source: source,
                channelIndex: bxx.channelIndex,
                syntheticRow: syntheticRow,
                effectType: bxx.cell.effectType,
                effectParam: bxx.cell.effectParam,
                targetOrderIndex: targetOrder,
                targetPatternIndex: targetPattern.index,
                targetRowIndex: targetPattern.rows[targetRow].index,
                nextOrderIndex: nil,
                loopStartRowIndex: nil,
                loopRemaining: nil,
                loopLimit: nil,
                combinedWithBxx: false,
                combinedWithDxx: dxx != nil,
                policy: pendingRowChannel == bxx.channelIndex
                        ? (dxx == nil ? "bxx_jumps_to_order_row_zero" : "bxx_resets_earlier_dxx_pending_row")
                        : (pendingRowChannel == dxx?.channelIndex
                            ? "bxx_uses_dxx_row_target_when_same_row" : "bxx_uses_later_e6x_pending_row")
            ))
            return freshPosition(afterCommitTo: targetOrder, row: targetRow, pattern: targetPattern,
                held: heldTransition)
        }

        if let dxx {
            let targetOrder = source.orderIndex + 1
            let targetPattern = targetOrder >= startOrderIndex && targetOrder < selectedEndOrderIndex
                ? patternForOrder(targetOrder, in: song)
                : nil
            let target = resolvedDxxTarget(effectParam: dxx.cell.effectParam, targetPattern: targetPattern)
            diagnostics.append(dxxDiagnostic(
                command: dxx,
                source: source,
                syntheticRow: syntheticRow,
                targetOrder: targetOrder,
                targetPattern: targetPattern,
                target: target,
                combinedWithBxx: false
            ))
            guard targetOrder >= startOrderIndex,
                  targetOrder < selectedEndOrderIndex,
                  song.orders.indices.contains(targetOrder),
                  let targetPattern,
                  !targetPattern.rows.isEmpty else {
                return NextPositionDecision(orderIndex: targetOrder, rowIndex: target.targetRow, stopReason: .outOfRange)
            }
            let targetRow = pendingRow < targetPattern.rows.count ? max(0, pendingRow) : 0
            if visitedPositions.contains(TraversalPositionKey(
                orderIndex: targetOrder,
                patternIndex: targetPattern.index,
                rowArrayIndex: targetRow
            )) {
                diagnostics.append(positionCycleGuardDiagnostic(
                    kind: .dxxPatternBreak,
                    command: dxx,
                    source: source,
                    syntheticRow: syntheticRow,
                    targetOrderIndex: targetOrder,
                    targetPatternIndex: targetPattern.index,
                    targetRowIndex: targetPattern.rows[targetRow].index,
                    loopLimit: maxTraversalRows,
                    combinedWithBxx: false,
                    combinedWithDxx: false,
                    policy: "dxx_position_cycle_guard"
                ))
                return NextPositionDecision(orderIndex: targetOrder, rowIndex: targetRow, stopReason: .traversalGuardHit)
            }
            return freshPosition(afterCommitTo: targetOrder, row: targetRow, pattern: targetPattern,
                held: heldTransition)
        }

        if loopRequested {
            return freshPosition(afterCommitTo: source.orderIndex, row: pendingRow, pattern: pattern,
                held: heldTransition)
        }

        let nextRow = currentRowIndex + 1
        if nextRow < pattern.rows.count {
            return NextPositionDecision(orderIndex: source.orderIndex, rowIndex: nextRow, stopReason: nil)
        }
        let nextOrder = source.orderIndex + 1
        if nextOrder >= selectedEndOrderIndex {
            return NextPositionDecision(orderIndex: nextOrder, rowIndex: 0, stopReason: .selectedRangeEnd)
        }
        if nextOrder >= song.orders.count {
            return NextPositionDecision(orderIndex: nextOrder, rowIndex: 0, stopReason: .songEnd)
        }
        return NextPositionDecision(orderIndex: nextOrder, rowIndex: 0, stopReason: nil)
    }

    private static func freshPosition(afterCommitTo order: Int, row: Int, pattern: PlaybackPattern,
                                      held: Bool) -> NextPositionDecision {
        // FT2 consumes the loop/jump flag at the first cycle boundary while EE
        // suppresses cell reads. The final held cycle advances once before reading.
        let freshRow = row + (held ? 1 : 0)
        if freshRow >= pattern.rows.count {
            return NextPositionDecision(orderIndex: order + 1, rowIndex: 0, stopReason: nil)
        }
        return NextPositionDecision(orderIndex: order, rowIndex: freshRow, stopReason: nil)
    }

    private static func lastCommand(in row: PlaybackRow, effectType: UInt8) -> TraversalCommand? {
        for (channelIndex, cell) in row.cells.enumerated().reversed() where cell.effectType == effectType {
            return TraversalCommand(channelIndex: channelIndex, cell: cell)
        }
        return nil
    }

    private static func patternForOrder(_ orderIndex: Int, in song: PlaybackSong) -> PlaybackPattern? {
        guard song.orders.indices.contains(orderIndex) else {
            return nil
        }
        return song.patternsByIndex[song.orders[orderIndex].patternIndex]
    }

    private static func positionCycleGuardDiagnostic(
        kind: PlaybackSongSyntheticTraversalDiagnostic.Kind,
        command: TraversalCommand,
        source: PlaybackPosition,
        syntheticRow: Int,
        targetOrderIndex: Int,
        targetPatternIndex: Int,
        targetRowIndex: Int,
        loopLimit: Int,
        combinedWithBxx: Bool,
        combinedWithDxx: Bool,
        policy: String
    ) -> PlaybackSongSyntheticTraversalDiagnostic {
        PlaybackSongSyntheticTraversalDiagnostic(
            kind: kind,
            status: .loopLimitHit,
            source: source,
            channelIndex: command.channelIndex,
            syntheticRow: syntheticRow,
            effectType: command.cell.effectType,
            effectParam: command.cell.effectParam,
            targetOrderIndex: targetOrderIndex,
            targetPatternIndex: targetPatternIndex,
            targetRowIndex: targetRowIndex,
            nextOrderIndex: nil,
            loopStartRowIndex: nil,
            loopRemaining: nil,
            loopLimit: loopLimit,
            combinedWithBxx: combinedWithBxx,
            combinedWithDxx: combinedWithDxx,
            policy: policy
        )
    }

    private static func resolvedDxxTarget(
        effectParam: UInt8,
        targetPattern: PlaybackPattern?
    ) -> DxxTarget {
        let tens = Int((effectParam & 0xF0) >> 4)
        let ones = Int(effectParam & 0x0F)
        let invalidBCD = tens > 9 || ones > 9
        let decodedRow = invalidBCD ? 0 : (tens * 10) + ones
        let maxRow = max(0, (targetPattern?.rows.count ?? 1) - 1)
        return DxxTarget(
            decodedRow: decodedRow,
            // FT2's qualified break domain ends at 63. Preserve VTX's existing
            // extended long-pattern clamp and diagnosed invalid-BCD fallback.
            targetRow: decodedRow > maxRow ? (decodedRow <= 63 ? 0 : maxRow) : max(0, decodedRow),
            invalidBCD: invalidBCD,
            outOfRange: !invalidBCD && decodedRow > maxRow
        )
    }

    private static func dxxDiagnostic(
        command: TraversalCommand,
        source: PlaybackPosition,
        syntheticRow: Int,
        targetOrder: Int,
        targetPattern: PlaybackPattern?,
        target: DxxTarget?,
        combinedWithBxx: Bool
    ) -> PlaybackSongSyntheticTraversalDiagnostic {
        let target = target ?? resolvedDxxTarget(effectParam: command.cell.effectParam, targetPattern: targetPattern)
        let status: PlaybackSongSyntheticTraversalDiagnostic.Status
        if target.invalidBCD {
            status = .invalidTarget
        } else if targetPattern == nil || targetPattern?.rows.isEmpty == true || target.outOfRange {
            status = .outOfRange
        } else {
            status = .applied
        }
        let targetRowIndex: Int?
        if let targetPattern, !targetPattern.rows.isEmpty {
            targetRowIndex = targetPattern.rows[min(max(0, target.targetRow), targetPattern.rows.count - 1)].index
        } else {
            targetRowIndex = target.targetRow
        }
        return PlaybackSongSyntheticTraversalDiagnostic(
            kind: .dxxPatternBreak,
            status: status,
            source: source,
            channelIndex: command.channelIndex,
            syntheticRow: syntheticRow,
            effectType: command.cell.effectType,
            effectParam: command.cell.effectParam,
            targetOrderIndex: targetOrder,
            targetPatternIndex: targetPattern?.index,
            targetRowIndex: targetRowIndex,
            nextOrderIndex: combinedWithBxx ? nil : targetOrder,
            loopStartRowIndex: nil,
            loopRemaining: nil,
            loopLimit: nil,
            combinedWithBxx: combinedWithBxx,
            combinedWithDxx: false,
            policy: target.invalidBCD
                ? "invalid_bcd_clamped_to_row_zero"
                : "dxx_uses_xm_bcd_row_target"
        )
    }

    private static func loopLimitDiagnostic(
        source: PlaybackPosition,
        syntheticRow: Int,
        loopLimit: Int
    ) -> PlaybackSongSyntheticTraversalDiagnostic {
        PlaybackSongSyntheticTraversalDiagnostic(
            kind: .e6xPatternLoop,
            status: .loopLimitHit,
            source: source,
            channelIndex: 0,
            syntheticRow: syntheticRow,
            effectType: 0x0E,
            effectParam: 0x60,
            targetOrderIndex: nil,
            targetPatternIndex: nil,
            targetRowIndex: nil,
            nextOrderIndex: nil,
            loopStartRowIndex: nil,
            loopRemaining: nil,
            loopLimit: loopLimit,
            combinedWithBxx: false,
            combinedWithDxx: false,
            policy: "max_traversal_row_guard"
        )
    }

    private static func isE6x(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x06
    }

    private static func traversalRowLimit(
        song: PlaybackSong,
        startOrderIndex: Int,
        selectedEndOrderIndex: Int
    ) -> Int {
        let selectedRowCount = (startOrderIndex..<selectedEndOrderIndex).reduce(0) { count, orderIndex in
            guard song.orders.indices.contains(orderIndex),
                  let pattern = song.patternsByIndex[song.orders[orderIndex].patternIndex] else {
                return count
            }
            return count + pattern.rows.count
        }
        return min(max(1_024, (selectedRowCount * 16) + 1_024), 1_000_000)
    }
}

