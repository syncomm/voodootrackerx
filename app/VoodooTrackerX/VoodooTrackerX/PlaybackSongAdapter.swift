import Foundation

struct PlaybackSongSyntheticPlan: Equatable {
    let timingConfig: SyntheticTrackerTimingConfig
    let pattern: SyntheticPattern
    let diagnostics: PlaybackSongSyntheticDiagnostics
}

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
    private struct LoopKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let channelIndex: Int
    }

    private struct LoopCountKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let rowIndex: Int
        let channelIndex: Int
    }

    private struct TraversalPositionKey: Hashable {
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

    static func plan(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int
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
        var loopRemaining = [LoopCountKey: Int]()
        var visitedPositions = Set<TraversalPositionKey>()
        var currentOrderIndex = startOrderIndex
        var currentRowIndex = 0
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
        loopRemaining: inout [LoopCountKey: Int],
        visitedPositions: Set<TraversalPositionKey>,
        diagnostics: inout [PlaybackSongSyntheticTraversalDiagnostic]
    ) -> NextPositionDecision {
        let bxx = firstCommand(in: row, effectType: 0x0B)
        let dxx = firstCommand(in: row, effectType: 0x0D)
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
                    policy: dxx == nil ? "bxx_jumps_to_order_row_zero" : "bxx_uses_dxx_row_target_when_same_row"
                ))
                return NextPositionDecision(orderIndex: targetOrder, rowIndex: 0, stopReason: .outOfRange)
            }
            let targetRow = min(max(0, target?.targetRow ?? 0), targetPattern.rows.count - 1)
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
                policy: dxx == nil ? "bxx_jumps_to_order_row_zero" : "bxx_uses_dxx_row_target_when_same_row"
            ))
            return NextPositionDecision(orderIndex: targetOrder, rowIndex: targetRow, stopReason: nil)
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
            let targetRow = min(max(0, target.targetRow), targetPattern.rows.count - 1)
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
            return NextPositionDecision(orderIndex: targetOrder, rowIndex: targetRow, stopReason: nil)
        }

        for command in e6xCommands {
            let value = Int(command.cell.effectParam & 0x0F)
            guard value > 0 else {
                continue
            }
            let loopKey = LoopKey(orderIndex: source.orderIndex, patternIndex: source.patternIndex, channelIndex: command.channelIndex)
            guard let loopStart = loopStarts[loopKey] else {
                diagnostics.append(PlaybackSongSyntheticTraversalDiagnostic(
                    kind: .e6xPatternLoop,
                    status: .missingLoopStart,
                    source: source,
                    channelIndex: command.channelIndex,
                    syntheticRow: syntheticRow,
                    effectType: command.cell.effectType,
                    effectParam: command.cell.effectParam,
                    targetOrderIndex: source.orderIndex,
                    targetPatternIndex: source.patternIndex,
                    targetRowIndex: nil,
                    nextOrderIndex: nil,
                    loopStartRowIndex: nil,
                    loopRemaining: nil,
                    loopLimit: nil,
                    combinedWithBxx: false,
                    combinedWithDxx: false,
                    policy: "missing_e60_loop_start_diagnosed_no_loop"
                ))
                continue
            }
            let countKey = LoopCountKey(
                orderIndex: source.orderIndex,
                patternIndex: source.patternIndex,
                rowIndex: row.index,
                channelIndex: command.channelIndex
            )
            let remainingBefore = loopRemaining[countKey] ?? value
            guard remainingBefore > 0 else {
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
                    combinedWithBxx: false,
                    combinedWithDxx: false,
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
                combinedWithBxx: false,
                combinedWithDxx: false,
                policy: "e6x_per_channel_order_pattern_loop_count"
            ))
            return NextPositionDecision(orderIndex: source.orderIndex, rowIndex: targetRow, stopReason: nil)
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

    private static func firstCommand(in row: PlaybackRow, effectType: UInt8) -> TraversalCommand? {
        for (channelIndex, cell) in row.cells.enumerated() where cell.effectType == effectType {
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
            targetRow: min(max(0, decodedRow), maxRow),
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

struct PlaybackSongFxxRowTiming: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowEndExactFrame: Double
    let effectiveSpeed: Int
    let effectiveBPM: Int

    var rowStartFrame: Int {
        Self.floorFrame(rowStartExactFrame)
    }

    var rowEndFrame: Int {
        Self.floorFrame(rowEndExactFrame)
    }

    var rowDurationFrames: Int {
        max(0, rowEndFrame - rowStartFrame)
    }

    var diagnostic: PlaybackSongSyntheticRowTimingDiagnostic {
        PlaybackSongSyntheticRowTimingDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            rowStartFrame: rowStartFrame,
            rowDurationFrames: rowDurationFrames,
            effectiveSpeed: effectiveSpeed,
            effectiveBPM: effectiveBPM
        )
    }

    private static func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

struct PlaybackSongFxxTimingPlan: Equatable {
    let sampleRate: Double
    let initialSpeed: Int
    let initialBPM: Int
    let rowTimings: [PlaybackSongFxxRowTiming]
    let timingChanges: [PlaybackSongSyntheticTimingChangeDiagnostic]
    let finalSpeed: Int
    let finalBPM: Int
    let endExactFrame: Double

    var rowTimingDiagnostics: [PlaybackSongSyntheticRowTimingDiagnostic] {
        rowTimings.map(\.diagnostic)
    }

    func timingConfig(forSyntheticRow syntheticRow: Int) -> SyntheticTrackerTimingConfig {
        let timing = timingFor(syntheticRow: syntheticRow)
        return SyntheticTrackerTimingConfig(
            speed: timing.speed,
            bpm: timing.bpm,
            sampleRate: sampleRate
        )
    }

    func frameFor(row: Int, tick: Int = 0) -> Int {
        let safeRow = max(0, row)
        let timing = timingFor(syntheticRow: safeRow)
        let safeTick = min(max(0, tick), timing.speed - 1)
        let exactFrame = timing.rowStartExactFrame + (Double(safeTick) * framesPerTick(bpm: timing.bpm))
        return floorFrame(exactFrame)
    }

    private func timingFor(syntheticRow: Int) -> (rowStartExactFrame: Double, speed: Int, bpm: Int) {
        if rowTimings.indices.contains(syntheticRow),
           rowTimings[syntheticRow].syntheticRow == syntheticRow {
            let rowTiming = rowTimings[syntheticRow]
            return (
                rowStartExactFrame: rowTiming.rowStartExactFrame,
                speed: rowTiming.effectiveSpeed,
                bpm: rowTiming.effectiveBPM
            )
        }

        let extraRows = max(0, syntheticRow - rowTimings.count)
        let rowStart = endExactFrame + (Double(extraRows) * rowDuration(speed: finalSpeed, bpm: finalBPM))
        return (rowStartExactFrame: rowStart, speed: finalSpeed, bpm: finalBPM)
    }

    private func framesPerTick(bpm: Int) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm))
    }

    private func rowDuration(speed: Int, bpm: Int) -> Double {
        framesPerTick(bpm: bpm) * Double(max(1, speed))
    }

    private func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

enum PlaybackSongFxxTimingPlanner {
    static func plan(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongFxxTimingPlan {
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount
        )
        return plan(song, traversalPlan: traversalPlan, sampleRate: sampleRate)
    }

    static func plan(
        _ song: PlaybackSong,
        traversalPlan: PlaybackSongTraversalPlan,
        sampleRate: Double
    ) -> PlaybackSongFxxTimingPlan {
        let initialConfig = SyntheticTrackerTimingConfig(
            speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm,
            sampleRate: sampleRate
        )
        var currentSpeed = initialConfig.speed
        var currentBPM = initialConfig.bpm
        var currentExactFrame = 0.0
        var rowTimings = [PlaybackSongFxxRowTiming]()
        var timingChanges = [PlaybackSongSyntheticTimingChangeDiagnostic]()

        for traversalRow in traversalPlan.rows {
            let row = traversalRow.row
            let syntheticRow = traversalRow.syntheticRow
            let source = traversalRow.source
            let rowStartExactFrame = currentExactFrame
            let rowEndExactFrame = currentExactFrame + rowDuration(
                speed: currentSpeed,
                bpm: currentBPM,
                sampleRate: initialConfig.sampleRate
            )
            let rowTiming = PlaybackSongFxxRowTiming(
                source: source,
                syntheticRow: syntheticRow,
                rowStartExactFrame: rowStartExactFrame,
                rowEndExactFrame: rowEndExactFrame,
                effectiveSpeed: currentSpeed,
                effectiveBPM: currentBPM
            )
            rowTimings.append(rowTiming)

            var nextSpeed = currentSpeed
            var nextBPM = currentBPM
            for (channelIndex, cell) in row.cells.enumerated() where isFxxTimingEffect(cell) {
                let speedBefore = nextSpeed
                let bpmBefore = nextBPM
                let kind: PlaybackSongSyntheticTimingChangeDiagnostic.Kind
                let applied: Bool
                switch cell.effectParam {
                case 0:
                    kind = .ignoredF00
                    applied = false
                case 0x01...0x1F:
                    kind = .speed
                    applied = true
                    nextSpeed = Int(cell.effectParam)
                default:
                    kind = .bpm
                    applied = true
                    nextBPM = Int(cell.effectParam)
                }
                timingChanges.append(PlaybackSongSyntheticTimingChangeDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    rowStartFrame: rowTiming.rowStartFrame,
                    appliesToSyntheticRowAfter: syntheticRow + 1,
                    kind: kind,
                    applied: applied,
                    speedBefore: speedBefore,
                    bpmBefore: bpmBefore,
                    speedAfter: nextSpeed,
                    bpmAfter: nextBPM
                ))
            }

            currentExactFrame = rowEndExactFrame
            currentSpeed = nextSpeed
            currentBPM = nextBPM
        }

        return PlaybackSongFxxTimingPlan(
            sampleRate: initialConfig.sampleRate,
            initialSpeed: initialConfig.speed,
            initialBPM: initialConfig.bpm,
            rowTimings: rowTimings,
            timingChanges: timingChanges,
            finalSpeed: currentSpeed,
            finalBPM: currentBPM,
            endExactFrame: currentExactFrame
        )
    }

    static func isFxxTimingEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0F
    }

    private static func rowDuration(speed: Int, bpm: Int, sampleRate: Double) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm)) * Double(max(1, speed))
    }
}

enum PlaybackSongSyntheticAdapter {
    private static let maxMixerEnvelopePointCount = 12
    private static let xmLinearPeriodBase = 7_680.0
    private static let xmLinearC4Period = 4_608.0
    private static let xmLinearPeriodUnitsPerSemitone = 64.0
    private static let xmLinearPeriodUnitsPerOctave = 768.0
    private static let xmLinearMaximumRealNoteIndex = 118
    private static let xmLinearMaximumEffectiveNoteValue = xmLinearMaximumRealNoteIndex + 1
    private static let xmLinearMinimumSafePeriod = xmLinearPeriodBase
        - (Double(xmLinearMaximumRealNoteIndex) * xmLinearPeriodUnitsPerSemitone)
        - (127.0 / 2.0)
    private static let xmLinearMaximumSafePeriod = xmLinearPeriodBase + 64.0

    private struct ChannelState: Equatable {
        var volumeValue = 64
        var volumeValueZeroedByAxy = false
        var panningValue = 127.5
        var activeEventIndex: Int?
        var activeEventMappingIndex: Int?
        var activeInstrumentIndex: Int?
        var activeSampleIndex: Int?
        var activeSampleVolume: Float?
        var activePlaybackStep: Double?
        var activeLinearPeriod: Double?
        var activeSampleBaseSampleRate: Double?
        var activeSampleRelativeNote: Int?
        var activeSampleFinetune: Int?
        var activeUsesLinearFrequencyTable: Bool?
        var tonePortamentoTargetNote: UInt8?
        var tonePortamentoTargetLinearPeriod: Double?
        var tonePortamentoTargetPlaybackStep: Double?
        var tonePortamentoSpeed: Int?
        var sampleOffsetMemory: SampleOffsetMemory?
        var portamentoUpMemory: PortamentoSlideMemory?
        var portamentoDownMemory: PortamentoSlideMemory?
        var vibratoSpeed: Int?
        var vibratoDepth: Int?
        var vibratoSpeedMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoDepthMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoControl: VibratoControlState?
        var vibratoPhase: Double = 0

        var pan: Float {
            PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: panningValue)
        }
    }

    private struct SampleOffsetMemory: Equatable {
        let offsetFrames: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    private struct PortamentoSlideMemory: Equatable {
        let amount: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    private struct VibratoControlState: Equatable {
        let controlValue: Int
        let waveform: VibratoWaveform
        let retriggerSuppressed: Bool
        let source: PlaybackSongSyntheticEffectMemorySource?
    }

    private enum VibratoWaveform: Int, Equatable {
        case sine = 0
        case rampDown = 1
        case square = 2
        case random = 3

        var name: String {
            switch self {
            case .sine:
                return "sine"
            case .rampDown:
                return "ramp_down"
            case .square:
                return "square"
            case .random:
                return "random"
            }
        }
    }

    private struct GlobalVolumeState: Equatable {
        static let defaultValue = 64

        var volumeValue = defaultValue

        var multiplier: Float {
            globalVolumeMultiplier(for: volumeValue)
        }
    }

    private struct GlobalVolumeSlidePlan: Equatable {
        let up: Int
        let down: Int
        let direction: PlaybackSongSyntheticGlobalVolumeSlideDirection
        let amount: Int
        let bothNibblesNonzero: Bool
        let policy: String?
    }

    private struct VolumeSlideAmounts: Equatable {
        let up: Int
        let down: Int
        let direction: String
        let amount: Int
        let rawUpNibble: Int
        let rawDownNibble: Int
        let bothNibblesNonzero: Bool
        let policy: String
    }

    private struct SampleSelection: Equatable {
        let sample: PlaybackSample?
        let diagnosticSample: PlaybackSample?
        let skippedReason: PlaybackSongSyntheticIgnoredCell.Reason?
        let sampleMapKeymapPresent: Bool
        let mappedSampleIndex: Int?
        let mappedSampleValid: Bool
        let method: PlaybackSongSyntheticSampleSelectionMethod
        let firstPlayableSampleFallbackUsed: Bool
        let sampleMapKeymapBehaviorDeferred: Bool
        let sampleMapKeymapMissingOrDeferred: Bool
    }

    private struct MixerSampleBufferCacheKey: Hashable {
        let storageAddress: UInt
        let frameCount: Int
    }

    private static func clearActiveVoiceState(_ state: inout ChannelState) {
        state.activeEventIndex = nil
        state.activeEventMappingIndex = nil
        state.activeInstrumentIndex = nil
        state.activeSampleIndex = nil
        state.activeSampleVolume = nil
        state.activePlaybackStep = nil
        state.activeLinearPeriod = nil
        state.activeSampleBaseSampleRate = nil
        state.activeSampleRelativeNote = nil
        state.activeSampleFinetune = nil
        state.activeUsesLinearFrequencyTable = nil
        state.tonePortamentoTargetNote = nil
        state.tonePortamentoTargetLinearPeriod = nil
        state.tonePortamentoTargetPlaybackStep = nil
    }

    private static func effectMemorySource(
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell
    ) -> PlaybackSongSyntheticEffectMemorySource {
        PlaybackSongSyntheticEffectMemorySource(
            source: source,
            channelIndex: channelIndex,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
    }

    private static func memoryUnavailableReason(from reasons: [String]) -> String? {
        let uniqueReasons = Set(reasons)
        if uniqueReasons.contains("missing_vibrato_speed_memory"),
           uniqueReasons.contains("missing_vibrato_depth_memory") {
            return "missing_vibrato_speed_depth_memory"
        }
        return reasons.first
    }

    private struct EventCoverageBuilder: Equatable {
        var totalCellsVisited = 0
        var emptyCells = 0
        var normalNoteCells = 0
        var noteOffCells = 0
        var invalidNoteCells = 0
        var instrumentOnlyCells = 0
        var noteWithInstrumentCells = 0
        var noteWithMissingOrZeroInstrumentCells = 0
        var scheduledNoteEvents = 0
        var skippedNoteEvents = 0
        var skippedNoteOffEventsNoActiveVoice = 0
        var ignoredOrDeferredCells = 0
        var sampleMapSelectionEvents = 0
        var firstPlayableSampleFallbackEvents = 0
        var fallbackAfterInvalidSampleMapEvents = 0
        var skippedNoValidSampleEvents = 0
        var sampleMapKeymapDeferredEvents = 0
        var eventOutsideBoundedRowRangeCount = 0
        var eventCapacityLimitCount = 0
        var cMixerVoiceCapacityLimitCount = 0
        var skipReasonCounts = [PlaybackSongSyntheticSkipReason: Int]()

        mutating func visit(_ cell: PlaybackCell) {
            totalCellsVisited += 1
            if isCompletelyEmpty(cell) {
                emptyCells += 1
            }
            if (1...96).contains(cell.note) {
                normalNoteCells += 1
                if cell.instrument > 0 {
                    noteWithInstrumentCells += 1
                } else {
                    noteWithMissingOrZeroInstrumentCells += 1
                }
            } else if cell.note == 97 {
                noteOffCells += 1
            } else if cell.note > 97 {
                invalidNoteCells += 1
            } else if cell.note == 0, cell.instrument > 0, cell.volumeColumn == 0, cell.effectType == 0, cell.effectParam == 0 {
                instrumentOnlyCells += 1
            }
        }

        mutating func recordScheduledNote(
            method: PlaybackSongSyntheticSampleSelectionMethod,
            firstPlayableSampleFallbackUsed: Bool,
            sampleMapKeymapBehaviorDeferred: Bool
        ) {
            scheduledNoteEvents += 1
            if method == .sampleMap {
                sampleMapSelectionEvents += 1
            }
            if firstPlayableSampleFallbackUsed {
                firstPlayableSampleFallbackEvents += 1
            }
            if method == .fallbackAfterInvalidMap {
                fallbackAfterInvalidSampleMapEvents += 1
            }
            if sampleMapKeymapBehaviorDeferred {
                sampleMapKeymapDeferredEvents += 1
            }
        }

        mutating func recordSkippedSampleSelection(
            method: PlaybackSongSyntheticSampleSelectionMethod,
            sampleMapKeymapBehaviorDeferred: Bool
        ) {
            if method == .skippedNoValidSample {
                skippedNoValidSampleEvents += 1
            }
            if sampleMapKeymapBehaviorDeferred {
                sampleMapKeymapDeferredEvents += 1
            }
        }

        mutating func recordIgnoredCell(
            reason: PlaybackSongSyntheticSkipReason,
            isNormalNote: Bool,
            isNoteOffWithoutActiveVoice: Bool = false
        ) {
            ignoredOrDeferredCells += 1
            skipReasonCounts[reason, default: 0] += 1
            if isNormalNote {
                skippedNoteEvents += 1
            }
            if isNoteOffWithoutActiveVoice {
                skippedNoteOffEventsNoActiveVoice += 1
            }
        }

        mutating func recordDeferredCellWithoutSkip() {
            ignoredOrDeferredCells += 1
            skipReasonCounts[.unsupportedDeferredEffectInteraction, default: 0] += 1
        }

        var summary: PlaybackSongSyntheticEventCoverageSummary {
            PlaybackSongSyntheticEventCoverageSummary(
                totalCellsVisited: totalCellsVisited,
                emptyCells: emptyCells,
                normalNoteCells: normalNoteCells,
                noteOffCells: noteOffCells,
                invalidNoteCells: invalidNoteCells,
                instrumentOnlyCells: instrumentOnlyCells,
                noteWithInstrumentCells: noteWithInstrumentCells,
                noteWithMissingOrZeroInstrumentCells: noteWithMissingOrZeroInstrumentCells,
                scheduledNoteEvents: scheduledNoteEvents,
                skippedNoteEvents: skippedNoteEvents,
                skippedNoteOffEventsNoActiveVoice: skippedNoteOffEventsNoActiveVoice,
                ignoredOrDeferredCells: ignoredOrDeferredCells,
                sampleMapSelectionEvents: sampleMapSelectionEvents,
                firstPlayableSampleFallbackEvents: firstPlayableSampleFallbackEvents,
                fallbackAfterInvalidSampleMapEvents: fallbackAfterInvalidSampleMapEvents,
                skippedNoValidSampleEvents: skippedNoValidSampleEvents,
                sampleMapKeymapDeferredEvents: sampleMapKeymapDeferredEvents,
                eventOutsideBoundedRowRangeCount: eventOutsideBoundedRowRangeCount,
                eventCapacityLimitCount: eventCapacityLimitCount,
                cMixerVoiceCapacityLimitCount: cMixerVoiceCapacityLimitCount,
                skipReasonCounts: skipReasonCounts
                    .map { PlaybackSongSyntheticSkipReasonCount(reason: $0.key, count: $0.value) }
                    .sorted { lhs, rhs in
                        if lhs.count != rhs.count {
                            return lhs.count > rhs.count
                        }
                        return lhs.reason.rawValue < rhs.reason.rawValue
                    }
            )
        }

        private func isCompletelyEmpty(_ cell: PlaybackCell) -> Bool {
            cell.note == 0 &&
                cell.instrument == 0 &&
                cell.volumeColumn == 0 &&
                cell.effectType == 0 &&
                cell.effectParam == 0
        }
    }

    private struct TraversalEffectKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let rowIndex: Int
        let channelIndex: Int
        let syntheticRow: Int
        let effectType: UInt8
        let effectParam: UInt8
    }

    private struct AdapterRowContext {
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var volumeColumnMappings = [PlaybackSongSyntheticVolumeColumnMapping]()
        var voiceStateUpdates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        var sampleOffsetEffects = [PlaybackSongSyntheticSampleOffsetDiagnostic]()
        var setFinetuneEffects = [PlaybackSongSyntheticSetFinetuneDiagnostic]()
        var noteCutEffects = [PlaybackSongSyntheticNoteCutDiagnostic]()
        var noteDelayEffects = [PlaybackSongSyntheticNoteDelayDiagnostic]()
        var retriggerEffects = [PlaybackSongSyntheticRetriggerDiagnostic]()
        var tonePortamentoEffects = [PlaybackSongSyntheticTonePortamentoDiagnostic]()
        var portamentoSlideEffects = [PlaybackSongSyntheticPortamentoSlideDiagnostic]()
        var finePortamentoUpEffects = [PlaybackSongSyntheticFinePortamentoUpDiagnostic]()
        var finePortamentoDownEffects = [PlaybackSongSyntheticFinePortamentoDownDiagnostic]()
        var arpeggioEffects = [PlaybackSongSyntheticArpeggioDiagnostic]()
        var vibratoControlEffects = [PlaybackSongSyntheticVibratoControlDiagnostic]()
        var vibratoEffects = [PlaybackSongSyntheticVibratoDiagnostic]()
        var keyOffEvents = [PlaybackSongSyntheticKeyOffDiagnostic]()
        var effectCommandDiagnostics = [PlaybackSongSyntheticEffectCommandDiagnostic]()
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
        var deferredCellFields = [PlaybackSongSyntheticDeferredCellField]()
        var eventCoverage = EventCoverageBuilder()
        var events = [SyntheticTrackerEvent]()
        var channelStates = [Int: ChannelState]()
        var mixerSampleBuffers = [MixerSampleBufferCacheKey: MixerSampleBuffer]()
        var globalVolumeState = GlobalVolumeState()
        var traversalEffectStatuses = [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()
    }

    static func adapt(
        _ song: PlaybackSong,
        orderIndex: Int,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: orderIndex, orderCount: 1, sampleRate: sampleRate)
    }

    static func adapt(
        _ song: PlaybackSong,
        orderRange: Range<Int>,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        adapt(
            song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: max(0, orderRange.count),
            sampleRate: sampleRate
        )
    }

    static func adapt(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount
        )
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            traversalPlan: traversalPlan,
            sampleRate: sampleRate
        )
        let timingConfig = SyntheticTrackerTimingConfig(
            speed: timingPlan.initialSpeed,
            bpm: timingPlan.initialBPM,
            sampleRate: timingPlan.sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var rowMappings = [PlaybackSongSyntheticRowMapping]()
        var context = AdapterRowContext()
        let estimatedRows = timingPlan.rowTimings.count

        rowMappings.reserveCapacity(estimatedRows)
        context.rowDiagnostics.reserveCapacity(estimatedRows)
        context.events.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.eventMappings.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.mixerSampleBuffers.reserveCapacity(song.instrumentsByIndex.values.reduce(0) { $0 + $1.samples.count })
        context.traversalEffectStatuses = traversalEffectStatuses(from: traversalPlan.traversalDiagnostics)

        for traversalRow in traversalPlan.rows {
            rowMappings.append(PlaybackSongSyntheticRowMapping(
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow
            ))
            let rowDiagnostic = appendEvents(
                from: traversalRow.row,
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow,
                song: song,
                timingConfig: timingPlan.timingConfig(forSyntheticRow: traversalRow.syntheticRow),
                timingPlan: timingPlan,
                scheduledStartFrame: timingPlan.frameFor(row: traversalRow.syntheticRow, tick: 0),
                context: &context
            )
            context.rowDiagnostics.append(rowDiagnostic)
        }

        return PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: SyntheticPattern(rowCount: traversalPlan.pathLength, events: context.events),
            diagnostics: PlaybackSongSyntheticDiagnostics(
                requestedStartOrderIndex: startOrderIndex,
                requestedOrderCount: safeOrderCount,
                sampleRate: timingConfig.sampleRate,
                initialSpeed: timingConfig.speed,
                initialBPM: timingConfig.bpm,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                syntheticRowCount: traversalPlan.pathLength,
                adaptedOrders: traversalPlan.adaptedOrders,
                rowMappings: rowMappings,
                rowTiming: timingPlan.rowTimingDiagnostics,
                timingChanges: timingPlan.timingChanges,
                traversalDiagnostics: traversalPlan.traversalDiagnostics,
                traversalPathLength: traversalPlan.pathLength,
                traversalStopReason: traversalPlan.stopReason,
                traversalGuardHit: traversalPlan.guardHit,
                effectCommandDiagnostics: context.effectCommandDiagnostics,
                rowDiagnostics: context.rowDiagnostics,
                volumeColumnMappings: context.volumeColumnMappings,
                voiceStateUpdates: context.voiceStateUpdates,
                sampleOffsetEffects: context.sampleOffsetEffects,
                setFinetuneEffects: context.setFinetuneEffects,
                noteCutEffects: context.noteCutEffects,
                noteDelayEffects: context.noteDelayEffects,
                retriggerEffects: context.retriggerEffects,
                tonePortamentoEffects: context.tonePortamentoEffects,
                portamentoSlideEffects: context.portamentoSlideEffects,
                finePortamentoUpEffects: context.finePortamentoUpEffects,
                finePortamentoDownEffects: context.finePortamentoDownEffects,
                arpeggioEffects: context.arpeggioEffects,
                vibratoControlEffects: context.vibratoControlEffects,
                vibratoEffects: context.vibratoEffects,
                keyOffEvents: context.keyOffEvents,
                eventMappings: context.eventMappings,
                ignoredCells: context.ignoredCells,
                deferredCellFields: context.deferredCellFields,
                eventCoverage: context.eventCoverage.summary
            )
        )
    }

    private static func traversalEffectStatuses(
        from diagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
    ) -> [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status] {
        diagnostics.reduce(into: [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()) { result, diagnostic in
            let key = TraversalEffectKey(
                orderIndex: diagnostic.source.orderIndex,
                patternIndex: diagnostic.source.patternIndex,
                rowIndex: diagnostic.source.rowIndex,
                channelIndex: diagnostic.channelIndex,
                syntheticRow: diagnostic.syntheticRow,
                effectType: diagnostic.effectType,
                effectParam: diagnostic.effectParam
            )
            result[key] = effectCommandStatus(for: diagnostic.status)
        }
    }

    private static func effectCommandStatus(
        for traversalStatus: PlaybackSongSyntheticTraversalDiagnostic.Status
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic.Status {
        switch traversalStatus {
        case .applied, .loopStartMarked, .loopTaken:
            return .applied
        case .deferred:
            return .deferredUnsupported
        case .invalidTarget:
            return .invalidTarget
        case .outOfRange:
            return .outOfRange
        case .missingLoopStart:
            return .missingLoopStart
        case .loopLimitHit:
            return .loopLimitHit
        }
    }

    private static func appendEvents(
        from row: PlaybackRow,
        source: PlaybackPosition,
        syntheticRow: Int,
        song: PlaybackSong,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        scheduledStartFrame: Int,
        context: inout AdapterRowContext
    ) -> PlaybackSongSyntheticRowDiagnostic {
        let eventStartCount = context.events.count
        let ignoredStartCount = context.ignoredCells.count
        for (channelIndex, cell) in row.cells.enumerated() {
            context.eventCoverage.visit(cell)
            if let effectCommandDiagnostic = effectCommandDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                traversalEffectStatuses: context.traversalEffectStatuses,
                timingConfig: timingConfig
            ) {
                context.effectCommandDiagnostics.append(effectCommandDiagnostic)
            }
            var channelState = context.channelStates[channelIndex] ?? ChannelState()
            defer {
                let axyUpdates = applyAxyVolumeSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    globalVolumeValue: context.globalVolumeState.volumeValue
                )
                if !axyUpdates.isEmpty {
                    context.voiceStateUpdates.append(contentsOf: axyUpdates)
                }
                context.channelStates[channelIndex] = channelState
            }
            let extendedSubcommand = cell.effectType == 0x0E ? ((cell.effectParam >> 4) & 0x0F) : nil
            let hasNoteCutEffect = extendedSubcommand == 0x0C
            let hasNoteDelayEffect = extendedSubcommand == 0x0D
            let hasRetriggerEffect = extendedSubcommand == 0x09
            let hasSetFinetuneEffect = extendedSubcommand == 0x05
            let hasFinePortamentoUpEffect = extendedSubcommand == 0x01
            let hasFinePortamentoDownEffect = extendedSubcommand == 0x02
            let hasVibratoControlEffect = extendedSubcommand == 0x04
            let hasArpeggio = isArpeggioEffect(cell)
            let hasPortamentoSlide = isPortamentoSlideEffect(cell)
            let hasTonePortamento = isTonePortamentoEffect(cell)
            let hasVibrato = isVibratoEffect(cell)
            let hasVibratoVolumeSlide = isVibratoVolumeSlideEffect(cell)
            let hasValidImmediateNoteInstrument = (1...96).contains(cell.note) &&
                cell.instrument > 0 &&
                !hasNoteDelayEffect
            let resetsInstrumentVolumeBeforeTrigger = hasValidImmediateNoteInstrument &&
                !hasTonePortamento &&
                cell.effectType == 0 &&
                cell.effectParam == 0 &&
                cell.volumeColumn == 0 &&
                channelState.volumeValueZeroedByAxy
            if resetsInstrumentVolumeBeforeTrigger {
                channelState.volumeValue = 64
                channelState.volumeValueZeroedByAxy = false
            }
            let delaysInstrumentVolumeState = hasValidImmediateNoteInstrument && hasTonePortamento
            let channelStateBeforeVolumeColumn = channelState
            var volumeColumn = PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn)
            if !delaysInstrumentVolumeState {
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState)
            }
            let hasDeferredEffectCell = hasDeferredEffect(cell, channelState: channelState)
            if !delaysInstrumentVolumeState, let update = voiceStateUpdate(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                cell: cell,
                volumeColumn: volumeColumn,
                channelStateBefore: channelStateBeforeVolumeColumn,
                channelStateAfter: channelState,
                globalVolumeValue: context.globalVolumeState.volumeValue
            ) {
                context.voiceStateUpdates.append(update)
            }
            if let update = applyEffectColumnState(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                channelState: &channelState,
                globalVolumeValue: context.globalVolumeState.volumeValue
            ) {
                context.voiceStateUpdates.append(update)
            }
            if hasVibratoControlEffect {
                let diagnostic = handleVibratoControl(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    channelState: &channelState
                )
                context.vibratoControlEffects.append(diagnostic)
            }
            context.channelStates[channelIndex] = channelState
            if cell.effectType == 0x11 {
                context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSlide(
                    from: cell,
                    source: source,
                    sourceChannelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    channelStates: context.channelStates,
                    globalVolumeState: &context.globalVolumeState
                ))
            }
            if !delaysInstrumentVolumeState, cell.volumeColumn != 0 {
                context.volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    volumeColumn: volumeColumn
                ))
            }
            if !delaysInstrumentVolumeState {
                appendDeferredFields(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    volumeColumn: volumeColumn,
                    includeKeyOff: false,
                    hasDeferredEffectOverride: hasDeferredEffectCell,
                    deferredCellFields: &context.deferredCellFields
                )
            }
            let noteDelay = hasNoteDelayEffect
                ? noteDelayDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    originalFrame: scheduledStartFrame,
                    eventIndex: nil
                )
                : nil
            if hasArpeggio, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleArpeggio(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.arpeggioEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasPortamentoSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handlePortamentoSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.portamentoSlideEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasFinePortamentoUpEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleFinePortamentoUp(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.finePortamentoUpEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasFinePortamentoDownEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleFinePortamentoDown(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.finePortamentoDownEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibrato, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibratoVolumeSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasTonePortamento, cell.note != 97, !delaysInstrumentVolumeState {
                let diagnostic = handleTonePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.tonePortamentoEffects.append(diagnostic)
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                context.channelStates[channelIndex] = channelState
                continue
            }
            if cell.note == 97 {
                handleKeyOff(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledStartFrame: scheduledStartFrame,
                    volumeColumn: volumeColumn,
                    cell: cell,
                    channelState: &channelState,
                    events: &context.events,
                    keyOffEvents: &context.keyOffEvents,
                    eventMappings: &context.eventMappings,
                    ignoredCells: &context.ignoredCells,
                    deferredCellFields: &context.deferredCellFields,
                    eventCoverage: &context.eventCoverage
                )
                if hasRetriggerEffect {
                    _ = handleRetrigger(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        volumeColumn: volumeColumn,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        globalVolumeState: context.globalVolumeState,
                        channelState: &channelState,
                        events: &context.events,
                        eventMappings: &context.eventMappings,
                        retriggerEffects: &context.retriggerEffects,
                        eventCoverage: &context.eventCoverage
                    )
                }
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noNoteDeferred,
                        activeVoiceFound: channelState.activeEventIndex != nil,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex
                    ))
                }
                context.channelStates[channelIndex] = channelState
                continue
            }
            guard (1...96).contains(cell.note) else {
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                let retrigger = hasRetriggerEffect
                    ? handleRetrigger(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        volumeColumn: volumeColumn,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        globalVolumeState: context.globalVolumeState,
                        channelState: &channelState,
                        events: &context.events,
                        eventMappings: &context.eventMappings,
                        retriggerEffects: &context.retriggerEffects,
                        eventCoverage: &context.eventCoverage
                    )
                    : nil
                if retrigger?.applied == true {
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noNoteDeferred,
                        activeVoiceFound: channelState.activeEventIndex != nil,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: noteDelay?.status == .noNoteDeferred
                        ? .noteDelayWithoutNote
                        : ignoredNoteReason(cell, volumeColumn: volumeColumn),
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: noteDelay != nil || hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: false)
                context.channelStates[channelIndex] = channelState
                continue
            }
            if let noteDelay, noteDelay.outOfRow {
                context.noteDelayEffects.append(noteDelay)
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .noteDelayOutOfRow,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: true
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }

            let instrumentIndex = Int(cell.instrument)
            guard instrumentIndex > 0 else {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .missingInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }
            guard let instrument = song.instrument(forInstrument: instrumentIndex) else {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .unknownInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }
            let sampleSelection = selectSample(forNote: cell.note, from: instrument)
            guard let sample = sampleSelection.sample else {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil,
                        sampleFinetune: sampleSelection.diagnosticSample?.finetune
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: sampleSelection.skippedReason ?? .unknown,
                    diagnosticSample: sampleSelection.diagnosticSample,
                    sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                    mappedSampleIndex: sampleSelection.mappedSampleIndex,
                    mappedSampleValid: sampleSelection.mappedSampleValid,
                    sampleSelectionMethod: sampleSelection.method,
                    firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                    sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.eventCoverage.recordSkippedSampleSelection(
                    method: sampleSelection.method,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
                )
                context.channelStates[channelIndex] = channelState
                continue
            }

            let sampleLength = selectedSampleLength(sample)
            var tonePortamentoInstrumentStateBefore: ChannelState?
            var tonePortamentoInstrumentStateAfter: ChannelState?
            var tonePortamentoInstrumentDefaultVolumeApplied = false
            if delaysInstrumentVolumeState {
                let instrumentStateBefore = channelState
                channelState.volumeValue = 64
                channelState.volumeValueZeroedByAxy = false
                if hasTonePortamento {
                    channelState.activeInstrumentIndex = instrumentIndex
                    channelState.activeSampleIndex = sample.sampleIndex
                    channelState.activeSampleVolume = sample.volume
                    channelState.activeSampleBaseSampleRate = sample.baseSampleRate
                    channelState.activeSampleRelativeNote = sample.relativeNote
                    channelState.activeSampleFinetune = sample.finetune
                    channelState.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
                }
                tonePortamentoInstrumentStateBefore = instrumentStateBefore
                tonePortamentoInstrumentStateAfter = channelState
                let instrumentGainBefore = instrumentStateBefore.activeSampleVolume.map {
                    adaptedGain(sampleVolume: $0, channelVolume: instrumentStateBefore.volumeValue)
                }
                let instrumentGainAfter = channelState.activeSampleVolume.map {
                    adaptedGain(sampleVolume: $0, channelVolume: channelState.volumeValue)
                }
                tonePortamentoInstrumentDefaultVolumeApplied = instrumentStateBefore.volumeValue != channelState.volumeValue ||
                    instrumentStateBefore.activeSampleVolume != channelState.activeSampleVolume
                if hasTonePortamento {
                    context.voiceStateUpdates.append(voiceStateUpdateDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        cell: cell,
                        commandSource: .instrumentState,
                        command: .instrumentDefaultVolume(value: channelState.volumeValue),
                        rawVolumeColumn: nil,
                        effectType: cell.effectType,
                        effectParam: cell.effectParam,
                        status: .applied,
                        behavior: nil,
                        channelStateBefore: instrumentStateBefore,
                        channelStateAfter: channelState,
                        globalVolumeBefore: context.globalVolumeState.volumeValue,
                        globalVolumeAfter: context.globalVolumeState.volumeValue,
                        activeVoiceUpdatedOverride: instrumentStateBefore.activeEventIndex != nil &&
                            instrumentStateBefore.activeSampleVolume != nil &&
                            instrumentGainBefore != instrumentGainAfter
                    ))
                }
                let beforeVolumeColumn = channelState
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState)
                if hasTonePortamento {
                    tonePortamentoInstrumentStateAfter = channelState
                }
                if let update = voiceStateUpdate(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    cell: cell,
                    volumeColumn: volumeColumn,
                    channelStateBefore: beforeVolumeColumn,
                    channelStateAfter: channelState,
                    globalVolumeValue: context.globalVolumeState.volumeValue
                ) {
                    context.voiceStateUpdates.append(update)
                }
                if cell.volumeColumn != 0 {
                    context.volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        syntheticTick: 0,
                        volumeColumn: volumeColumn
                    ))
                }
                appendDeferredFields(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    volumeColumn: volumeColumn,
                    includeKeyOff: false,
                    hasDeferredEffectOverride: hasDeferredEffectCell,
                    deferredCellFields: &context.deferredCellFields
                )
            }
            let sampleOffset = sampleOffsetDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                selectedSampleLength: sampleLength,
                channelState: &channelState
            )
            if sampleOffset.detected {
                context.sampleOffsetEffects.append(sampleOffset)
            }
            if sampleOffset.skipped {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoUpEffects.append(diagnostic)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    context.finePortamentoDownEffects.append(diagnostic)
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .sampleOffsetOutOfRange,
                    diagnosticSample: sample,
                    sampleOffsetFrames: sampleOffset.computedOffsetFrames,
                    sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                    mappedSampleIndex: sampleSelection.mappedSampleIndex,
                    mappedSampleValid: sampleSelection.mappedSampleValid,
                    sampleSelectionMethod: sampleSelection.method,
                    firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                    sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }

            if hasTonePortamento {
                let diagnostic = handleTonePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    instrumentStateBefore: tonePortamentoInstrumentStateBefore,
                    instrumentStateAfter: tonePortamentoInstrumentStateAfter,
                    instrumentDefaultVolumeApplied: tonePortamentoInstrumentDefaultVolumeApplied,
                    sampleSelectedBefore: tonePortamentoInstrumentStateBefore?.activeSampleIndex,
                    sampleSelectedAfter: sample.sampleIndex
                )
                context.tonePortamentoEffects.append(diagnostic)
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                context.channelStates[channelIndex] = channelState
                continue
            }

            let eventIndex = context.events.count
            let loop = mixerLoop(from: sample)
            let envelopeMapping = mixerVolumeEnvelope(
                from: instrument.volumeEnvelope,
                timingConfig: timingConfig
            )
            let envelopeSemantics = volumeEnvelopeSemantics(
                from: instrument.volumeEnvelope,
                mapping: envelopeMapping
            )
            let scheduledNoteFrame = noteDelay?.delayedFrame ?? scheduledStartFrame
            let scheduledNoteTick = noteDelay?.applied == true ? noteDelay?.requestedTick ?? 0 : 0
            let setFinetuneOverride = hasSetFinetuneEffect ? setFinetuneValue(from: cell) : nil
            var pitchMapping = playbackStepMapping(
                note: cell.note,
                sample: sample,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                timingConfig: timingConfig,
                finetuneOverride: setFinetuneOverride
            )
            if hasSetFinetuneEffect {
                context.setFinetuneEffects.append(setFinetuneDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    status: setFinetuneStatus(for: pitchMapping),
                    activeVoiceFound: true,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    sampleFinetune: sample.finetune,
                    pitchMapping: pitchMapping
                ))
            }
            if hasFinePortamentoUpEffect {
                let result = finePortamentoUpAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                context.finePortamentoUpEffects.append(result.diagnostic)
            }
            if hasFinePortamentoDownEffect {
                let result = finePortamentoDownAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                context.finePortamentoDownEffects.append(result.diagnostic)
            }
            let gain = adaptedGain(
                sampleVolume: sample.volume,
                channelVolume: channelState.volumeValue,
                globalVolume: context.globalVolumeState.volumeValue
            )
            let pan = channelState.pan
            context.events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: scheduledNoteTick,
                scheduledStartFrame: scheduledNoteFrame,
                sample: mixerSampleBuffer(for: sample, cache: &context.mixerSampleBuffers),
                gain: gain,
                pan: pan,
                playbackStep: pitchMapping.playbackStep,
                loop: loop,
                initialSourceFrame: sampleOffset.appliedOffsetFrames ?? 0,
                volumeEnvelope: envelopeMapping.envelope
            ))
            context.eventCoverage.recordScheduledNote(
                method: sampleSelection.method,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
            )
            if hasDeferredEffectCell || volumeColumn.deferred {
                context.eventCoverage.recordDeferredCellWithoutSkip()
            }
            channelState.activeEventIndex = eventIndex
            channelState.activeEventMappingIndex = context.eventMappings.count
            channelState.activeInstrumentIndex = instrumentIndex
            channelState.activeSampleIndex = sample.sampleIndex
            channelState.activeSampleVolume = sample.volume
            channelState.activePlaybackStep = pitchMapping.playbackStep
            channelState.activeLinearPeriod = pitchMapping.linearPeriod
            channelState.activeSampleBaseSampleRate = sample.baseSampleRate
            channelState.activeSampleRelativeNote = sample.relativeNote
            channelState.activeSampleFinetune = pitchMapping.effectiveFinetune ?? sample.finetune
            channelState.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
            channelState.tonePortamentoTargetNote = nil
            channelState.tonePortamentoTargetLinearPeriod = nil
            channelState.tonePortamentoTargetPlaybackStep = nil
            channelState.volumeValueZeroedByAxy = false
            context.channelStates[channelIndex] = channelState
            context.eventMappings.append(PlaybackSongSyntheticEventMapping(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                selectedSampleLength: sampleLength,
                sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                mappedSampleIndex: sampleSelection.mappedSampleIndex,
                mappedSampleValid: sampleSelection.mappedSampleValid,
                sampleSelectionMethod: sampleSelection.method,
                sampleSelectionStrategy: sampleSelection.method.rawValue,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                syntheticRow: syntheticRow,
                syntheticTick: scheduledNoteTick,
                eventIndex: eventIndex,
                loopMode: loop.mode,
                volumeColumn: volumeColumn,
                sampleOffset: sampleOffset,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffectCell,
                effectiveVolumeValue: channelState.volumeValue,
                effectiveGlobalVolumeValue: context.globalVolumeState.volumeValue,
                effectiveGlobalVolumeMultiplier: context.globalVolumeState.multiplier,
                effectivePan: pan,
                volumeEnvelopeStatus: envelopeMapping.status,
                sourceVolumeEnvelopePointCount: envelopeMapping.sourcePointCount,
                mappedVolumeEnvelopePointCount: envelopeMapping.mappedPointCount,
                hasDeferredVolumeEnvelopeSustain: envelopeSemantics.sustainDeferred,
                hasDeferredVolumeEnvelopeLoop: envelopeSemantics.loopDeferred,
                hasDeferredVolumeEnvelopeFadeout: envelopeSemantics.fadeoutDeferred,
                volumeEnvelopeSemantics: envelopeSemantics,
                sampleBaseSampleRate: sample.baseSampleRate,
                sampleRelativeNote: sample.relativeNote,
                sampleFinetune: sample.finetune,
                outputSampleRate: pitchMapping.outputSampleRate,
                effectiveNoteValue: pitchMapping.effectiveNoteValue,
                effectiveNoteIndex: pitchMapping.effectiveNoteIndex,
                effectiveFinetune: pitchMapping.effectiveFinetune,
                linearPeriod: pitchMapping.linearPeriod,
                linearFrequency: pitchMapping.linearFrequency,
                finetuneStatus: pitchMapping.finetuneStatus,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                frequencyTableStatus: pitchMapping.frequencyTableStatus,
                linearFrequencyApplied: pitchMapping.linearFrequencyApplied,
                amigaFrequencyDeferred: pitchMapping.amigaFrequencyDeferred,
                playbackStep: pitchMapping.playbackStep,
                pitchMappingApplied: pitchMapping.applied,
                pitchMappingUsedNeutralStep: pitchMapping.usedNeutralStep
            ))
            if hasArpeggio {
                let diagnostic = handleArpeggio(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    includeTickZeroUpdate: false
                )
                context.arpeggioEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasPortamentoSlide {
                let diagnostic = handlePortamentoSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.portamentoSlideEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibrato {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibratoVolumeSlide {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                context.vibratoEffects.append(diagnostic)
                context.channelStates[channelIndex] = channelState
            }
            if let noteDelay, noteDelay.applied {
                context.noteDelayEffects.append(noteDelayDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    originalFrame: scheduledStartFrame,
                    eventIndex: eventIndex
                ) ?? noteDelay)
            }
            if hasRetriggerEffect {
                _ = handleRetrigger(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    volumeColumn: volumeColumn,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    globalVolumeState: context.globalVolumeState,
                    channelState: &channelState,
                    events: &context.events,
                    eventMappings: &context.eventMappings,
                    retriggerEffects: &context.retriggerEffects,
                    eventCoverage: &context.eventCoverage
                )
            }
            if hasNoteCutEffect {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &context.noteCutEffects
                )
            }
            context.channelStates[channelIndex] = channelState
        }
        return PlaybackSongSyntheticRowDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            cellCount: row.cells.count,
            emittedEventCount: context.events.count - eventStartCount,
            ignoredCellCount: context.ignoredCells.count - ignoredStartCount
        )
    }

    private static func mixerSampleBuffer(
        for sample: PlaybackSample,
        cache: inout [MixerSampleBufferCacheKey: MixerSampleBuffer]
    ) -> MixerSampleBuffer {
        let key = sample.pcm.withUnsafeBufferPointer { buffer in
            MixerSampleBufferCacheKey(
                storageAddress: UInt(bitPattern: buffer.baseAddress),
                frameCount: buffer.count
            )
        }
        if let cached = cache[key] {
            return cached
        }
        let buffer = MixerSampleBuffer(monoPCM: sample.pcm)
        cache[key] = buffer
        return buffer
    }

    private static func voiceStateUpdate(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        cell: PlaybackCell,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        channelStateBefore: ChannelState,
        channelStateAfter: ChannelState,
        globalVolumeValue: Int
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? {
        guard cell.volumeColumn != 0 else {
            return nil
        }
        if volumeColumn.deferred {
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .volumeColumn,
                command: .volumeColumn(volumeColumn.command),
                rawVolumeColumn: cell.volumeColumn,
                effectType: nil,
                effectParam: nil,
                status: .deferredUnsupported,
                behavior: volumeColumn.behavior,
                channelStateBefore: channelStateBefore,
                channelStateAfter: channelStateBefore,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        }
        guard volumeColumn.applied,
              reportsVolumeColumnStateUpdate(volumeColumn.command) else {
            return nil
        }
        return voiceStateUpdateDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            scheduledFrame: scheduledFrame,
            cell: cell,
            commandSource: .volumeColumn,
            command: .volumeColumn(volumeColumn.command),
            rawVolumeColumn: cell.volumeColumn,
            effectType: nil,
            effectParam: nil,
            status: .applied,
            behavior: volumeColumn.behavior,
            channelStateBefore: channelStateBefore,
            channelStateAfter: channelStateAfter,
            globalVolumeBefore: globalVolumeValue,
            globalVolumeAfter: globalVolumeValue
        )
    }

    private static func reportsVolumeColumnStateUpdate(
        _ command: PlaybackSongSyntheticVolumeColumnCommand
    ) -> Bool {
        switch command {
        case .setVolume,
             .volumeSlideDown,
             .volumeSlideUp,
             .fineVolumeSlideDown,
             .fineVolumeSlideUp,
             .setPanning,
             .panningSlideLeft,
             .panningSlideRight:
            return true
        case .none,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return false
        }
    }

    private static func applyEffectColumnState(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        channelState: inout ChannelState,
        globalVolumeValue: Int
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? {
        switch cell.effectType {
        case 0x0C:
            let before = channelState
            channelState.volumeValue = clampedVolumeValue(Int(cell.effectParam))
            channelState.volumeValueZeroedByAxy = false
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .cxxSetVolume(value: channelState.volumeValue),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: nil,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x08:
            let before = channelState
            let panningValue = clampedPanningValue(Double(Int(cell.effectParam)))
            channelState.panningValue = panningValue
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .effect8xxSetPanning(value: Int(panningValue.rounded())),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: nil,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x06:
            let before = channelState
            let slide = volumeSlideAmounts(effectParam: cell.effectParam)
            guard slide.up > 0 || slide.down > 0 else {
                return voiceStateUpdateDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    commandSource: .effectColumn,
                    command: .effect6xyVolumeSlide(up: 0, down: 0),
                    rawVolumeColumn: nil,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignoredNoOp,
                    behavior: .rowLevelApproximation,
                    channelStateBefore: before,
                    channelStateAfter: before,
                    globalVolumeBefore: globalVolumeValue,
                    globalVolumeAfter: globalVolumeValue
                )
            }
            if slide.up > 0 {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue + slide.up)
            } else {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue - slide.down)
            }
            channelState.volumeValueZeroedByAxy = false
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: .effect6xyVolumeSlide(up: slide.up, down: slide.down),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .rowLevelApproximation,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        case 0x0E where isFineVolumeSlideEffect(cell):
            let before = channelState
            let amount = fineVolumeSlideAmount(from: cell)
            let isSlideUp = isFineVolumeSlideUpEffect(cell)
            let command: PlaybackSongSyntheticVoiceStateUpdateCommand = isSlideUp
                ? .eaxFineVolumeSlideUp(amount: amount)
                : .ebxFineVolumeSlideDown(amount: amount)
            guard amount > 0 else {
                return voiceStateUpdateDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    commandSource: .effectColumn,
                    command: command,
                    rawVolumeColumn: nil,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignoredNoOp,
                    behavior: .rowLevelApproximation,
                    channelStateBefore: before,
                    channelStateAfter: before,
                    globalVolumeBefore: globalVolumeValue,
                    globalVolumeAfter: globalVolumeValue
                )
            }
            if isSlideUp {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue + amount)
            } else {
                channelState.volumeValue = clampedVolumeValue(before.volumeValue - amount)
            }
            channelState.volumeValueZeroedByAxy = false
            return voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                commandSource: .effectColumn,
                command: command,
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .rowLevelApproximation,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue
            )
        default:
            return nil
        }
    }

    private static func applyAxyVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        globalVolumeValue: Int
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x0A else {
            return []
        }

        let slide = axyVolumeSlideAmounts(effectParam: cell.effectParam)
        let rowSpeed = max(1, timingConfig.speed)
        guard slide.amount > 0 else {
            let before = channelState
            return [
                voiceStateUpdateDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: 0),
                    cell: cell,
                    commandSource: .effectColumn,
                    command: .axyVolumeSlide(up: 0, down: 0),
                    rawVolumeColumn: nil,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignoredNoOp,
                    behavior: .tickLevelAfterTick0,
                    channelStateBefore: before,
                    channelStateAfter: before,
                    globalVolumeBefore: globalVolumeValue,
                    globalVolumeAfter: globalVolumeValue,
                    volumeSlide: slide,
                    volumeSlideClamped: false,
                    volumeSlideTick0Suppressed: true,
                    volumeSlideRowSpeed: rowSpeed,
                    activeVoiceUpdatedOverride: false
                ),
            ]
        }

        guard rowSpeed > 1 else {
            return []
        }

        var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        updates.reserveCapacity(rowSpeed - 1)
        for tick in 1..<rowSpeed {
            let before = channelState
            let unclampedAfter = before.volumeValue + slide.up - slide.down
            channelState.volumeValue = clampedVolumeValue(unclampedAfter)
            channelState.volumeValueZeroedByAxy = channelState.volumeValue == 0
            let clamped = channelState.volumeValue != unclampedAfter
            let activeVoiceAvailable = before.activeEventIndex != nil && before.activeSampleVolume != nil
            updates.append(voiceStateUpdateDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                cell: cell,
                commandSource: .effectColumn,
                command: .axyVolumeSlide(up: slide.up, down: slide.down),
                rawVolumeColumn: nil,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .applied,
                behavior: .tickLevelAfterTick0,
                channelStateBefore: before,
                channelStateAfter: channelState,
                globalVolumeBefore: globalVolumeValue,
                globalVolumeAfter: globalVolumeValue,
                volumeSlide: slide,
                volumeSlideClamped: clamped,
                volumeSlideTick0Suppressed: true,
                volumeSlideRowSpeed: rowSpeed,
                activeVoiceUpdatedOverride: activeVoiceAvailable
            ))
        }
        return updates
    }

    private static func applyGlobalVolumeSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        sourceChannelIndex: Int,
        syntheticRow: Int,
        scheduledFrame: Int,
        channelStates: [Int: ChannelState],
        globalVolumeState: inout GlobalVolumeState
    ) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        guard cell.effectType == 0x11 else {
            return []
        }

        let beforeGlobalVolume = globalVolumeState.volumeValue
        let slide = globalVolumeSlidePlan(effectParam: cell.effectParam)
        guard slide.amount > 0 else {
            return [
                globalVolumeSlideDiagnostic(
                    source: source,
                    sourceChannelIndex: sourceChannelIndex,
                    targetChannelIndex: nil,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledFrame,
                    cell: cell,
                    status: .ignoredNoOp,
                    slide: slide,
                    channelState: channelStates[sourceChannelIndex] ?? ChannelState(),
                    globalVolumeBefore: beforeGlobalVolume,
                    globalVolumeAfter: beforeGlobalVolume,
                    clamped: false,
                    activeVoiceUpdatedOverride: false
                ),
            ]
        }

        let unclampedAfter = beforeGlobalVolume + slide.up - slide.down
        let afterGlobalVolume = clampedGlobalVolumeValue(unclampedAfter)
        globalVolumeState.volumeValue = afterGlobalVolume
        let clamped = unclampedAfter != afterGlobalVolume
        let diagnostics = channelStates.keys.sorted().compactMap { targetChannelIndex -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic? in
            guard let targetState = channelStates[targetChannelIndex],
                  targetState.activeEventIndex != nil,
                  targetState.activeSampleVolume != nil else {
                return nil
            }
            let gainBefore = targetState.activeSampleVolume.map {
                adaptedGain(
                    sampleVolume: $0,
                    channelVolume: targetState.volumeValue,
                    globalVolume: beforeGlobalVolume
                )
            }
            let gainAfter = targetState.activeSampleVolume.map {
                adaptedGain(
                    sampleVolume: $0,
                    channelVolume: targetState.volumeValue,
                    globalVolume: afterGlobalVolume
                )
            }
            let changed = gainBefore != gainAfter
            guard changed else {
                return nil
            }
            return globalVolumeSlideDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: targetChannelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                slide: slide,
                channelState: targetState,
                globalVolumeBefore: beforeGlobalVolume,
                globalVolumeAfter: afterGlobalVolume,
                clamped: clamped,
                activeVoiceUpdatedOverride: true
            )
        }
        if !diagnostics.isEmpty {
            return diagnostics
        }

        return [
            globalVolumeSlideDiagnostic(
                source: source,
                sourceChannelIndex: sourceChannelIndex,
                targetChannelIndex: nil,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledFrame,
                cell: cell,
                status: .applied,
                slide: slide,
                channelState: channelStates[sourceChannelIndex] ?? ChannelState(),
                globalVolumeBefore: beforeGlobalVolume,
                globalVolumeAfter: afterGlobalVolume,
                clamped: clamped,
                activeVoiceUpdatedOverride: false
            ),
        ]
    }

    private static func globalVolumeSlideDiagnostic(
        source: PlaybackPosition,
        sourceChannelIndex: Int,
        targetChannelIndex: Int?,
        syntheticRow: Int,
        scheduledFrame: Int,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticVoiceStateUpdateStatus,
        slide: GlobalVolumeSlidePlan,
        channelState: ChannelState,
        globalVolumeBefore: Int,
        globalVolumeAfter: Int,
        clamped: Bool,
        activeVoiceUpdatedOverride: Bool
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        voiceStateUpdateDiagnostic(
            source: source,
            channelIndex: sourceChannelIndex,
            syntheticRow: syntheticRow,
            scheduledFrame: scheduledFrame,
            cell: cell,
            commandSource: .effectColumn,
            command: .hxyGlobalVolumeSlide(up: slide.up, down: slide.down),
            rawVolumeColumn: nil,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            behavior: .rowLevelApproximation,
            channelStateBefore: channelState,
            channelStateAfter: channelState,
            globalVolumeBefore: globalVolumeBefore,
            globalVolumeAfter: globalVolumeAfter,
            includeGlobalVolumeFields: true,
            targetChannelIndex: targetChannelIndex,
            globalVolumeSlideDirection: slide.direction,
            globalVolumeSlideAmount: slide.amount,
            globalVolumeSlideClamped: clamped,
            globalVolumeSlideBothNibblesNonzero: slide.bothNibblesNonzero,
            globalVolumeSlidePolicy: slide.policy,
            activeVoiceUpdatedOverride: activeVoiceUpdatedOverride
        )
    }

    private static func globalVolumeSlidePlan(effectParam: UInt8) -> GlobalVolumeSlidePlan {
        let upNibble = Int((effectParam & 0xF0) >> 4)
        let downNibble = Int(effectParam & 0x0F)
        let bothNibblesNonzero = upNibble > 0 && downNibble > 0
        if upNibble > 0 {
            return GlobalVolumeSlidePlan(
                up: upNibble,
                down: 0,
                direction: .up,
                amount: upNibble,
                bothNibblesNonzero: bothNibblesNonzero,
                policy: bothNibblesNonzero ? "up_nibble_precedence_matches_runtime" : nil
            )
        }
        if downNibble > 0 {
            return GlobalVolumeSlidePlan(
                up: 0,
                down: downNibble,
                direction: .down,
                amount: downNibble,
                bothNibblesNonzero: false,
                policy: nil
            )
        }
        return GlobalVolumeSlidePlan(
            up: 0,
            down: 0,
            direction: .none,
            amount: 0,
            bothNibblesNonzero: false,
            policy: "h00_no_effect_memory_no_op"
        )
    }

    private static func volumeSlideAmounts(effectParam: UInt8) -> VolumeSlideAmounts {
        volumeSlideAmounts(
            effectParam: effectParam,
            mixedNibblePolicy: "up_nibble_precedence_current_policy",
            zeroPolicy: "zero_param_effect_memory_deferred"
        )
    }

    private static func axyVolumeSlideAmounts(effectParam: UInt8) -> VolumeSlideAmounts {
        volumeSlideAmounts(
            effectParam: effectParam,
            mixedNibblePolicy: "up_nibble_precedence_mikmod_observed",
            zeroPolicy: "a00_no_effect_memory_no_op"
        )
    }

    private static func volumeSlideAmounts(
        effectParam: UInt8,
        mixedNibblePolicy: String,
        zeroPolicy: String
    ) -> VolumeSlideAmounts {
        let rawUp = Int((effectParam & 0xF0) >> 4)
        let rawDown = Int(effectParam & 0x0F)
        let bothNibblesNonzero = rawUp > 0 && rawDown > 0
        if rawUp > 0 {
            return VolumeSlideAmounts(
                up: rawUp,
                down: 0,
                direction: "up",
                amount: rawUp,
                rawUpNibble: rawUp,
                rawDownNibble: rawDown,
                bothNibblesNonzero: bothNibblesNonzero,
                policy: bothNibblesNonzero ? mixedNibblePolicy : "single_nonzero_nibble"
            )
        }
        if rawDown > 0 {
            return VolumeSlideAmounts(
                up: 0,
                down: rawDown,
                direction: "down",
                amount: rawDown,
                rawUpNibble: rawUp,
                rawDownNibble: rawDown,
                bothNibblesNonzero: false,
                policy: "single_nonzero_nibble"
            )
        }
        return VolumeSlideAmounts(
            up: 0,
            down: 0,
            direction: "none",
            amount: 0,
            rawUpNibble: rawUp,
            rawDownNibble: rawDown,
            bothNibblesNonzero: false,
            policy: zeroPolicy
        )
    }

    private static func voiceStateUpdateDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int = 0,
        scheduledFrame: Int,
        cell: PlaybackCell,
        commandSource: PlaybackSongSyntheticVoiceStateUpdateSource,
        command: PlaybackSongSyntheticVoiceStateUpdateCommand,
        rawVolumeColumn: UInt8?,
        effectType: UInt8?,
        effectParam: UInt8?,
        status: PlaybackSongSyntheticVoiceStateUpdateStatus,
        behavior: PlaybackSongSyntheticVolumeColumnBehavior?,
        channelStateBefore: ChannelState,
        channelStateAfter: ChannelState,
        globalVolumeBefore: Int,
        globalVolumeAfter: Int,
        includeGlobalVolumeFields: Bool = false,
        targetChannelIndex: Int? = nil,
        globalVolumeSlideDirection: PlaybackSongSyntheticGlobalVolumeSlideDirection? = nil,
        globalVolumeSlideAmount: Int? = nil,
        globalVolumeSlideClamped: Bool? = nil,
        globalVolumeSlideBothNibblesNonzero: Bool? = nil,
        globalVolumeSlidePolicy: String? = nil,
        volumeSlide: VolumeSlideAmounts? = nil,
        volumeSlideClamped: Bool? = nil,
        volumeSlideTick0Suppressed: Bool? = nil,
        volumeSlideRowSpeed: Int? = nil,
        activeVoiceUpdatedOverride: Bool? = nil
    ) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        let activeSampleVolumeBefore = channelStateBefore.activeSampleVolume
        let activeSampleVolumeAfter = channelStateAfter.activeSampleVolume ?? activeSampleVolumeBefore
        let gainBefore = activeSampleVolumeBefore.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: channelStateBefore.volumeValue,
                globalVolume: globalVolumeBefore
            )
        }
        let gainAfter = activeSampleVolumeAfter.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: channelStateAfter.volumeValue,
                globalVolume: globalVolumeAfter
            )
        }
        let sameCellTonePortamentoNoRetrigger =
            (1...96).contains(cell.note) &&
            isTonePortamentoEffect(cell) &&
            channelStateBefore.activeEventIndex != nil
        let canUpdateActiveVoice = activeVoiceUpdatedOverride ?? (
            status == .applied &&
                (cell.note == 0 || sameCellTonePortamentoNoRetrigger) &&
                channelStateBefore.activeEventIndex != nil &&
                activeSampleVolumeBefore != nil
        )
        return PlaybackSongSyntheticVoiceStateUpdateDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: syntheticTick,
            scheduledFrame: scheduledFrame,
            cellNote: cell.note,
            instrumentIndex: Int(cell.instrument),
            commandSource: commandSource,
            command: command,
            rawVolumeColumn: rawVolumeColumn,
            effectType: effectType,
            effectParam: effectParam,
            status: status,
            behavior: behavior,
            targetChannelIndex: targetChannelIndex,
            activeVoiceUpdated: canUpdateActiveVoice,
            activeEventIndex: canUpdateActiveVoice ? channelStateBefore.activeEventIndex : nil,
            effectiveVolumeBefore: channelStateBefore.volumeValue,
            effectiveVolumeAfter: channelStateAfter.volumeValue,
            effectivePanBefore: channelStateBefore.pan,
            effectivePanAfter: channelStateAfter.pan,
            globalVolumeBefore: includeGlobalVolumeFields ? globalVolumeBefore : nil,
            globalVolumeAfter: includeGlobalVolumeFields ? globalVolumeAfter : nil,
            globalVolumeMultiplierBefore: includeGlobalVolumeFields ? globalVolumeMultiplier(for: globalVolumeBefore) : nil,
            globalVolumeMultiplierAfter: includeGlobalVolumeFields ? globalVolumeMultiplier(for: globalVolumeAfter) : nil,
            globalVolumeSlideDirection: globalVolumeSlideDirection,
            globalVolumeSlideAmount: globalVolumeSlideAmount,
            globalVolumeSlideClamped: globalVolumeSlideClamped,
            globalVolumeSlideBothNibblesNonzero: globalVolumeSlideBothNibblesNonzero,
            globalVolumeSlidePolicy: globalVolumeSlidePolicy,
            volumeSlideRawUpNibble: volumeSlide?.rawUpNibble,
            volumeSlideRawDownNibble: volumeSlide?.rawDownNibble,
            volumeSlideBothNibblesNonzero: volumeSlide?.bothNibblesNonzero,
            volumeSlidePolicy: volumeSlide?.policy,
            volumeSlideClamped: volumeSlideClamped,
            volumeSlideTick0Suppressed: volumeSlideTick0Suppressed,
            volumeSlideRowSpeed: volumeSlideRowSpeed,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            panBefore: channelStateBefore.pan,
            panAfter: channelStateAfter.pan
        )
    }

    private static func applyVolumeColumn(
        _ volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        to state: inout ChannelState
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        switch volumeColumn.command {
        case let .setVolume(value):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(value)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideDown(amount),
             let .fineVolumeSlideDown(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before - amount)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideUp(amount),
             let .fineVolumeSlideUp(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before + amount)
            state.volumeValueZeroedByAxy = false
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .setPanning(value):
            let before = state.pan
            state.panningValue = clampedPanningValue(Double(value))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideLeft(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue - Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideRight(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue + Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case .none,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return volumeColumn
        }
    }

    private static func appendDeferredFields(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        includeKeyOff: Bool,
        hasDeferredEffectOverride: Bool? = nil,
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) {
        if volumeColumn.deferred {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .volumeColumn
            ))
        }
        if hasDeferredEffectOverride ?? hasDeferredEffect(cell) {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .effect
            ))
        }
        if includeKeyOff, cell.note == 97 {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .keyOff
            ))
        }
    }

    private static func handlePortamentoSlide(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticPortamentoSlideDiagnostic {
        let direction: PlaybackSongSyntheticPortamentoSlideDirection = cell.effectType == 0x01 ? .up : .down
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let requestedSlideAmount = Int(cell.effectParam)
        let rememberedMemory = direction == .up ? channelState.portamentoUpMemory : channelState.portamentoDownMemory
        let slideAmount: Int
        let memorySource: PlaybackSongSyntheticEffectMemorySource?
        let effectMemoryReused: Bool
        let effectMemoryMissing: Bool

        if requestedSlideAmount > 0 {
            slideAmount = requestedSlideAmount
            let memory = PortamentoSlideMemory(amount: requestedSlideAmount, source: targetMemorySource)
            if direction == .up {
                channelState.portamentoUpMemory = memory
            } else {
                channelState.portamentoDownMemory = memory
            }
            memorySource = nil
            effectMemoryReused = false
            effectMemoryMissing = false
        } else if let rememberedMemory {
            slideAmount = rememberedMemory.amount
            memorySource = rememberedMemory.source
            effectMemoryReused = true
            effectMemoryMissing = false
        } else {
            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroParamEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: 0,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                clamped: false,
                effectMemoryReused: false,
                effectMemoryMissing: true,
                memorySource: nil,
                memoryUnavailableReason: direction == .up
                    ? "missing_1xx_portamento_memory"
                    : "missing_2xx_portamento_memory",
                policy: "zero_param_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: slideAmount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                clamped: false,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: effectMemoryMissing,
                memorySource: memorySource,
                memoryUnavailableReason: nil,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              var currentLinearPeriod = channelState.activeLinearPeriod,
              var currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return portamentoSlideDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                direction: direction,
                slideAmount: slideAmount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                clamped: false,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: effectMemoryMissing,
                memorySource: memorySource,
                memoryUnavailableReason: nil,
                policy: "linear_frequency_only_first_pass"
            )
        }

        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        var clamped = false
        let rowSpeed = max(1, timingConfig.speed)
        for tick in 1..<rowSpeed {
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            let rawAfter = direction == .up
                ? currentLinearPeriod - Double(slideAmount)
                : currentLinearPeriod + Double(slideAmount)
            let afterPeriod = clampedLinearPeriod(rawAfter)
            let didClamp = abs(afterPeriod - rawAfter) > 0.000000001
            clamped = clamped || didClamp
            guard let nextStep = playbackStep(
                linearPeriod: afterPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                return portamentoSlideDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    direction: direction,
                    slideAmount: slideAmount,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    clamped: clamped,
                    effectMemoryReused: effectMemoryReused,
                    effectMemoryMissing: effectMemoryMissing,
                    memorySource: memorySource,
                    memoryUnavailableReason: nil,
                    policy: "slide_pitch_out_of_range"
                )
            }
            currentLinearPeriod = afterPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: false,
                clamped: didClamp
            ))
            if didClamp {
                break
            }
        }

        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return portamentoSlideDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            direction: direction,
            slideAmount: slideAmount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            memorySource: memorySource,
            memoryUnavailableReason: nil,
            policy: effectMemoryReused
                ? "zero_param_reuses_prior_portamento_slide_memory"
                : "linear_period_units_per_tick_first_pass"
        )
    }

    private static func portamentoSlideDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticPortamentoSlideDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        direction: PlaybackSongSyntheticPortamentoSlideDirection,
        slideAmount: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        effectMemoryReused: Bool,
        effectMemoryMissing: Bool,
        memorySource: PlaybackSongSyntheticEffectMemorySource?,
        memoryUnavailableReason: String?,
        policy: String
    ) -> PlaybackSongSyntheticPortamentoSlideDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = effectMemoryMissing || status == .zeroParamEffectMemoryDeferred
        return PlaybackSongSyntheticPortamentoSlideDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .zeroParamEffectMemoryDeferred || status == .unsupportedFrequencyTable,
            ignoredAsNoOp: !applied && status != .unsupportedFrequencyTable,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            effectMemoryDeferred: effectMemoryDeferred,
            memorySource: memorySource,
            memoryUnavailableReason: memoryUnavailableReason,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            direction: direction,
            slideAmount: slideAmount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    private static func handleFinePortamentoUp(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticFinePortamentoUpDiagnostic {
        let amount = finePortamentoUpAmount(from: cell)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard amount > 0 else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e10_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let currentLinearPeriod = channelState.activeLinearPeriod,
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass"
            )
        }

        let rawAfter = currentLinearPeriod - Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_up_pitch_out_of_range"
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        channelState.activeLinearPeriod = afterPeriod
        channelState.activePlaybackStep = nextStep

        return finePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: [update],
            clamped: clamped,
            policy: "row_start_fine_linear_period_up_first_pass"
        )
    }

    private static func finePortamentoUpAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticFinePortamentoUpDiagnostic) {
        let amount = finePortamentoUpAmount(from: cell)
        let currentLinearPeriodBefore = basePitchMapping.linearPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        guard amount > 0 else {
            return (basePitchMapping, finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e10_effect_memory_deferred_no_op"
            ))
        }

        guard basePitchMapping.applied,
              let linearPeriod = basePitchMapping.linearPeriod,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            let status: PlaybackSongSyntheticFinePortamentoUpDiagnostic.Status =
                basePitchMapping.amigaFrequencyDeferred ? .unsupportedFrequencyTable : .outOfRange
            return (basePitchMapping, finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: status,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: status == .unsupportedFrequencyTable
                    ? "linear_frequency_only_first_pass"
                    : "fine_portamento_up_pitch_out_of_range"
            ))
        }

        let rawAfter = linearPeriod - Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return (basePitchMapping, finePortamentoUpDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_up_pitch_out_of_range"
            ))
        }

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: afterPeriod,
            linearFrequency: nextStep * basePitchMapping.outputSampleRate,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: true,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(nextStep - 1.0) <= 0.000000001
        )
        return (adjustedMapping, finePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: afterPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: nextStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: true,
            stepUpdates: [],
            clamped: clamped,
            policy: "same_cell_note_initial_playback_step_fine_linear_period_up_first_pass"
        ))
    }

    private static func finePortamentoUpDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticFinePortamentoUpDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        fineAmount: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        scheduledFrame: Int?,
        appliedToInitialPlaybackStep: Bool,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        policy: String
    ) -> PlaybackSongSyntheticFinePortamentoUpDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .zeroAmountEffectMemoryDeferred
        return PlaybackSongSyntheticFinePortamentoUpDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: effectMemoryDeferred ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice || effectMemoryDeferred,
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: fineAmount,
            fineAmountNibble: fineAmount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: appliedToInitialPlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    private static func handleFinePortamentoDown(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticFinePortamentoDownDiagnostic {
        let amount = finePortamentoDownAmount(from: cell)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let scheduledFrame = timingPlan.frameFor(row: syntheticRow, tick: 0)

        guard amount > 0 else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e20_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let currentLinearPeriod = channelState.activeLinearPeriod,
              let currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "linear_frequency_only_first_pass"
            )
        }

        let rawAfter = currentLinearPeriod + Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_down_pitch_out_of_range"
            )
        }

        let update = PlaybackSongSyntheticTonePortamentoStepUpdate(
            syntheticTick: 0,
            scheduledFrame: scheduledFrame,
            linearPeriodBefore: currentLinearPeriod,
            linearPeriodAfter: afterPeriod,
            playbackStepBefore: currentPlaybackStep,
            playbackStepAfter: nextStep,
            reachedTarget: false,
            clamped: clamped
        )
        channelState.activeLinearPeriod = afterPeriod
        channelState.activePlaybackStep = nextStep

        return finePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: false,
            stepUpdates: [update],
            clamped: clamped,
            policy: "row_start_fine_linear_period_down_first_pass"
        )
    }

    private static func finePortamentoDownAdjustedPitchMapping(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        basePitchMapping: PlaybackStepMapping,
        baseSampleRate: Double,
        activeEventIndex: Int,
        activeEventMappingIndex: Int,
        scheduledFrame: Int
    ) -> (pitchMapping: PlaybackStepMapping, diagnostic: PlaybackSongSyntheticFinePortamentoDownDiagnostic) {
        let amount = finePortamentoDownAmount(from: cell)
        let currentLinearPeriodBefore = basePitchMapping.linearPeriod
        let currentPlaybackStepBefore = basePitchMapping.applied ? basePitchMapping.playbackStep : nil

        guard amount > 0 else {
            return (basePitchMapping, finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroAmountEffectMemoryDeferred,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: "e20_effect_memory_deferred_no_op"
            ))
        }

        guard basePitchMapping.applied,
              let linearPeriod = basePitchMapping.linearPeriod,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            let status: PlaybackSongSyntheticFinePortamentoDownDiagnostic.Status =
                basePitchMapping.amigaFrequencyDeferred ? .unsupportedFrequencyTable : .outOfRange
            return (basePitchMapping, finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: status,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: false,
                policy: status == .unsupportedFrequencyTable
                    ? "linear_frequency_only_first_pass"
                    : "fine_portamento_down_pitch_out_of_range"
            ))
        }

        let rawAfter = linearPeriod + Double(amount)
        let afterPeriod = clampedLinearPeriod(rawAfter)
        let clamped = abs(afterPeriod - rawAfter) > 0.000000001
        guard let nextStep = playbackStep(
            linearPeriod: afterPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: timingConfig.sampleRate
        ) else {
            return (basePitchMapping, finePortamentoDownDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .outOfRange,
                activeVoiceFound: true,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                fineAmount: amount,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: currentLinearPeriodBefore,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: currentPlaybackStepBefore,
                scheduledFrame: scheduledFrame,
                appliedToInitialPlaybackStep: false,
                stepUpdates: [],
                clamped: clamped,
                policy: "fine_portamento_down_pitch_out_of_range"
            ))
        }

        let adjustedMapping = PlaybackStepMapping(
            playbackStep: nextStep,
            outputSampleRate: basePitchMapping.outputSampleRate,
            effectiveNoteValue: basePitchMapping.effectiveNoteValue,
            effectiveNoteIndex: basePitchMapping.effectiveNoteIndex,
            effectiveFinetune: basePitchMapping.effectiveFinetune,
            linearPeriod: afterPeriod,
            linearFrequency: nextStep * basePitchMapping.outputSampleRate,
            finetuneStatus: basePitchMapping.finetuneStatus,
            frequencyTableStatus: basePitchMapping.frequencyTableStatus,
            linearFrequencyApplied: true,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(nextStep - 1.0) <= 0.000000001
        )
        return (adjustedMapping, finePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: amount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: afterPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: nextStep,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: true,
            stepUpdates: [],
            clamped: clamped,
            policy: "same_cell_note_initial_playback_step_fine_linear_period_down_first_pass"
        ))
    }

    private static func finePortamentoDownDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticFinePortamentoDownDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        fineAmount: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        scheduledFrame: Int?,
        appliedToInitialPlaybackStep: Bool,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        clamped: Bool,
        policy: String
    ) -> PlaybackSongSyntheticFinePortamentoDownDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .zeroAmountEffectMemoryDeferred
        return PlaybackSongSyntheticFinePortamentoDownDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: effectMemoryDeferred ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice || effectMemoryDeferred,
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            fineAmount: fineAmount,
            fineAmountNibble: fineAmount,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            scheduledFrame: scheduledFrame,
            appliedToInitialPlaybackStep: appliedToInitialPlaybackStep,
            stepUpdates: stepUpdates,
            clamped: clamped,
            policy: policy
        )
    }

    private static func handleArpeggio(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        includeTickZeroUpdate: Bool = true
    ) -> PlaybackSongSyntheticArpeggioDiagnostic {
        let xSemitoneOffset = Int((cell.effectParam & 0xF0) >> 4)
        let ySemitoneOffset = Int(cell.effectParam & 0x0F)
        let hasActiveVoice = channelState.activeEventIndex != nil
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep

        guard hasActiveVoice else {
            return arpeggioDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                xSemitoneOffset: xSemitoneOffset,
                ySemitoneOffset: ySemitoneOffset,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let baseLinearPeriod = channelState.activeLinearPeriod,
              let basePlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return arpeggioDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                xSemitoneOffset: xSemitoneOffset,
                ySemitoneOffset: ySemitoneOffset,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "linear_frequency_only_first_pass"
            )
        }

        var currentLinearPeriod = baseLinearPeriod
        var currentPlaybackStep = basePlaybackStep
        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        let firstTick = includeTickZeroUpdate ? 0 : 1
        for tick in firstTick..<rowSpeed {
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            let semitoneOffset: Int
            switch tick % 3 {
            case 1:
                semitoneOffset = xSemitoneOffset
            case 2:
                semitoneOffset = ySemitoneOffset
            default:
                semitoneOffset = 0
            }
            let modulatedPeriod = clampedLinearPeriod(
                baseLinearPeriod - (Double(semitoneOffset) * xmLinearPeriodUnitsPerSemitone)
            )
            guard let nextStep = playbackStep(
                linearPeriod: modulatedPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                return arpeggioDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    xSemitoneOffset: xSemitoneOffset,
                    ySemitoneOffset: ySemitoneOffset,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    policy: "arpeggio_pitch_out_of_range"
                )
            }
            currentLinearPeriod = modulatedPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: semitoneOffset == 0
            ))
        }

        if !stepUpdates.isEmpty,
           abs(currentPlaybackStep - basePlaybackStep) > 0.000000001 {
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: rowSpeed,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow + 1, tick: 0),
                linearPeriodBefore: currentLinearPeriod,
                linearPeriodAfter: baseLinearPeriod,
                playbackStepBefore: currentPlaybackStep,
                playbackStepAfter: basePlaybackStep,
                reachedTarget: true
            ))
            currentLinearPeriod = baseLinearPeriod
            currentPlaybackStep = basePlaybackStep
        }

        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return arpeggioDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            xSemitoneOffset: xSemitoneOffset,
            ySemitoneOffset: ySemitoneOffset,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            policy: "deterministic_0xy_tick_cycle_no_effect_memory"
        )
    }

    private static func arpeggioDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticArpeggioDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        xSemitoneOffset: Int,
        ySemitoneOffset: Int,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        policy: String
    ) -> PlaybackSongSyntheticArpeggioDiagnostic {
        let applied = status == .applied
        return PlaybackSongSyntheticArpeggioDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .unsupportedFrequencyTable || status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice,
            effectMemoryDeferred: false,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            xSemitoneOffset: xSemitoneOffset,
            ySemitoneOffset: ySemitoneOffset,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

    private static func handleVibrato(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticVibratoDiagnostic {
        let isVibratoVolumeSlide = isVibratoVolumeSlideEffect(cell)
        let paramSpeed = Int((cell.effectParam & 0xF0) >> 4)
        let paramDepth = Int(cell.effectParam & 0x0F)
        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let rememberedSpeed = channelState.vibratoSpeed
        let rememberedDepth = channelState.vibratoDepth
        let rememberedSpeedSource = channelState.vibratoSpeedMemorySource
        let rememberedDepthSource = channelState.vibratoDepthMemorySource
        let speed: Int
        let depth: Int
        let speedSource: String?
        let depthSource: String?
        let speedMemorySource: PlaybackSongSyntheticEffectMemorySource?
        let depthMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var missingMemoryReasons = [String]()

        if isVibratoVolumeSlide {
            if let rememberedSpeed {
                speed = rememberedSpeed
                speedSource = "4xy_channel_state"
                speedMemorySource = rememberedSpeedSource
            } else {
                speed = 0
                speedSource = "missing_4xy_channel_state"
                speedMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_speed_memory")
            }
            if let rememberedDepth {
                depth = rememberedDepth
                depthSource = "4xy_channel_state"
                depthMemorySource = rememberedDepthSource
            } else {
                depth = 0
                depthSource = "missing_4xy_channel_state"
                depthMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_depth_memory")
            }
        } else {
            if paramSpeed > 0 {
                speed = paramSpeed
                speedSource = "effect_param"
                speedMemorySource = nil
                channelState.vibratoSpeed = paramSpeed
                channelState.vibratoSpeedMemorySource = targetMemorySource
            } else if let rememberedSpeed {
                speed = rememberedSpeed
                speedSource = "4xy_channel_state"
                speedMemorySource = rememberedSpeedSource
            } else {
                speed = 0
                speedSource = "missing_4xy_channel_state"
                speedMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_speed_memory")
            }

            if paramDepth > 0 {
                depth = paramDepth
                depthSource = "effect_param"
                depthMemorySource = nil
                channelState.vibratoDepth = paramDepth
                channelState.vibratoDepthMemorySource = targetMemorySource
            } else if let rememberedDepth {
                depth = rememberedDepth
                depthSource = "4xy_channel_state"
                depthMemorySource = rememberedDepthSource
            } else {
                depth = 0
                depthSource = "missing_4xy_channel_state"
                depthMemorySource = nil
                missingMemoryReasons.append("missing_vibrato_depth_memory")
            }
        }

        let effectMemoryReused = speedMemorySource != nil || depthMemorySource != nil
        let effectMemoryMissing = !missingMemoryReasons.isEmpty
        let memoryUnavailableReason = memoryUnavailableReason(from: missingMemoryReasons)
        let volumeSlide = isVibratoVolumeSlide ? volumeSlideAmounts(effectParam: cell.effectParam) : nil
        let hasActiveVoice = channelState.activeEventIndex != nil
        let phaseBefore = channelState.vibratoPhase
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let vibratoControl = channelState.vibratoControl ?? VibratoControlState(
            controlValue: 0,
            waveform: .sine,
            retriggerSuppressed: false,
            source: nil
        )
        let waveformSource = vibratoControl.source == nil ? "default_sine" : "e4x_channel_state"

        guard !effectMemoryMissing else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: cell.effectParam == 0 ? .zeroParamEffectMemoryDeferred : .zeroSpeedOrDepthEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: true,
                effectMemoryDeferred: true,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: memoryUnavailableReason,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: isVibratoVolumeSlide
                    ? "6xy_missing_vibrato_memory_deferred_no_op"
                    : "4xy_missing_vibrato_memory_deferred_no_op"
            )
        }

        if isVibratoVolumeSlide, !hasActiveVoice {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard speed > 0, depth > 0 else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .zeroSpeedOrDepthEffectMemoryDeferred,
                activeVoiceFound: hasActiveVoice,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: true,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: isVibratoVolumeSlide
                    ? "6xy_missing_4xy_vibrato_memory_deferred_no_op"
                    : "zero_speed_or_depth_effect_memory_deferred_no_op"
            )
        }

        guard hasActiveVoice else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "no_active_voice_no_playback_invented"
            )
        }

        guard channelState.activeUsesLinearFrequencyTable == true,
              let baseLinearPeriod = channelState.activeLinearPeriod,
              let basePlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return vibratoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                speed: speed,
                depth: depth,
                speedSource: speedSource,
                depthSource: depthSource,
                controlValue: vibratoControl.controlValue,
                waveform: vibratoControl.waveform,
                waveformSource: waveformSource,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                speedMemorySource: speedMemorySource,
                depthMemorySource: depthMemorySource,
                memoryUnavailableReason: nil,
                volumeSlide: volumeSlide,
                phaseBefore: phaseBefore,
                phaseAfter: channelState.vibratoPhase,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                stepUpdates: [],
                policy: "linear_frequency_only_first_pass"
            )
        }

        var phase = channelState.vibratoPhase
        var currentLinearPeriod = baseLinearPeriod
        var currentPlaybackStep = basePlaybackStep
        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        let periodDepth = Double(depth) * 4.0
        for tick in 1..<rowSpeed {
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            phase += Double(speed) * (.pi / 32.0)
            let modulatedPeriod = clampedLinearPeriod(
                baseLinearPeriod - (vibratoWaveformValue(vibratoControl.waveform, phase: phase) * periodDepth)
            )
            guard let nextStep = playbackStep(
                linearPeriod: modulatedPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                channelState.vibratoPhase = phase
                return vibratoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    speed: speed,
                    depth: depth,
                    speedSource: speedSource,
                    depthSource: depthSource,
                    controlValue: vibratoControl.controlValue,
                    waveform: vibratoControl.waveform,
                    waveformSource: waveformSource,
                    effectMemoryReused: effectMemoryReused,
                    effectMemoryMissing: false,
                    effectMemoryDeferred: false,
                    speedMemorySource: speedMemorySource,
                    depthMemorySource: depthMemorySource,
                    memoryUnavailableReason: nil,
                    volumeSlide: volumeSlide,
                    phaseBefore: phaseBefore,
                    phaseAfter: channelState.vibratoPhase,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    stepUpdates: stepUpdates,
                    policy: "vibrato_pitch_out_of_range"
                )
            }
            currentLinearPeriod = modulatedPeriod
            currentPlaybackStep = nextStep
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: false
            ))
        }

        if !stepUpdates.isEmpty,
           abs(currentPlaybackStep - basePlaybackStep) > 0.000000001 {
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: rowSpeed,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow + 1, tick: 0),
                linearPeriodBefore: currentLinearPeriod,
                linearPeriodAfter: baseLinearPeriod,
                playbackStepBefore: currentPlaybackStep,
                playbackStepAfter: basePlaybackStep,
                reachedTarget: true
            ))
            currentLinearPeriod = baseLinearPeriod
            currentPlaybackStep = basePlaybackStep
        }

        channelState.vibratoPhase = phase
        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return vibratoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            speed: speed,
            depth: depth,
            speedSource: speedSource,
            depthSource: depthSource,
            controlValue: vibratoControl.controlValue,
            waveform: vibratoControl.waveform,
            waveformSource: waveformSource,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: false,
            effectMemoryDeferred: false,
            speedMemorySource: speedMemorySource,
            depthMemorySource: depthMemorySource,
            memoryUnavailableReason: nil,
            volumeSlide: volumeSlide,
            phaseBefore: phaseBefore,
            phaseAfter: channelState.vibratoPhase,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            stepUpdates: stepUpdates,
            policy: isVibratoVolumeSlide
                ? "6xy_reuses_4xy_vibrato_state_plus_row_level_volume_slide"
                : "deterministic_vibrato_waveform_linear_period_first_pass"
        )
    }

    private static func handleVibratoControl(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticVibratoControlDiagnostic {
        let controlValue = Int(cell.effectParam & 0x0F)
        let waveformID = controlValue & 0x03
        let retriggerSuppressed = (controlValue & 0x04) != 0
        let activeEventIndex = channelState.activeEventIndex
        let activeEventMappingIndex = channelState.activeEventMappingIndex
        guard let waveform = supportedVibratoWaveform(controlValue: controlValue) else {
            return PlaybackSongSyntheticVibratoControlDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .unsupportedWaveform,
                detected: true,
                applied: false,
                stored: false,
                deferred: true,
                ignoredAsNoOp: false,
                activeVoiceFound: activeEventIndex != nil,
                activeEventIndex: activeEventIndex,
                activeEventMappingIndex: activeEventMappingIndex,
                controlValue: controlValue,
                waveformID: waveformID,
                waveformName: "unsupported",
                retriggerSuppressed: retriggerSuppressed,
                unsupportedWaveform: true,
                affectsLaterVibrato: false,
                policy: "unsupported_e4x_vibrato_control_deferred"
            )
        }

        channelState.vibratoControl = VibratoControlState(
            controlValue: controlValue,
            waveform: waveform,
            retriggerSuppressed: retriggerSuppressed,
            source: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        )
        return PlaybackSongSyntheticVibratoControlDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .stored,
            detected: true,
            applied: true,
            stored: true,
            deferred: false,
            ignoredAsNoOp: false,
            activeVoiceFound: activeEventIndex != nil,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            controlValue: controlValue,
            waveformID: waveform.rawValue,
            waveformName: waveform.name,
            retriggerSuppressed: retriggerSuppressed,
            unsupportedWaveform: false,
            affectsLaterVibrato: true,
            policy: "e4x_stores_deterministic_vibrato_waveform_for_later_4xy_6xy"
        )
    }

    private static func supportedVibratoWaveform(controlValue: Int) -> VibratoWaveform? {
        guard (0...3).contains(controlValue) else {
            return nil
        }
        return VibratoWaveform(rawValue: controlValue)
    }

    private static func vibratoWaveformValue(_ waveform: VibratoWaveform, phase: Double) -> Double {
        switch waveform {
        case .sine:
            return sin(phase)
        case .rampDown:
            let cycle = normalizedCycle(phase)
            return 1.0 - (cycle * 2.0)
        case .square:
            return normalizedCycle(phase) < 0.5 ? 1.0 : -1.0
        case .random:
            return deterministicRandomVibratoValue(phase: phase)
        }
    }

    private static func normalizedCycle(_ phase: Double) -> Double {
        let period = Double.pi * 2.0
        let remainder = phase.truncatingRemainder(dividingBy: period)
        return (remainder < 0 ? remainder + period : remainder) / period
    }

    private static func deterministicRandomVibratoValue(phase: Double) -> Double {
        let phaseStep = Int((phase / (.pi / 32.0)).rounded(.down))
        let hashed = UInt32(truncatingIfNeeded: phaseStep &* 1_103_515_245 &+ 12_345)
        return (Double((hashed >> 16) & 0x7FFF) / 16_383.5) - 1.0
    }

    private static func vibratoDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticVibratoDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        speed: Int,
        depth: Int,
        speedSource: String?,
        depthSource: String?,
        controlValue: Int,
        waveform: VibratoWaveform,
        waveformSource: String,
        effectMemoryReused: Bool,
        effectMemoryMissing: Bool,
        effectMemoryDeferred: Bool,
        speedMemorySource: PlaybackSongSyntheticEffectMemorySource?,
        depthMemorySource: PlaybackSongSyntheticEffectMemorySource?,
        memoryUnavailableReason: String?,
        volumeSlide: VolumeSlideAmounts?,
        phaseBefore: Double,
        phaseAfter: Double,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        policy: String
    ) -> PlaybackSongSyntheticVibratoDiagnostic {
        let applied = status == .applied
        return PlaybackSongSyntheticVibratoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .zeroParamEffectMemoryDeferred ||
                status == .zeroSpeedOrDepthEffectMemoryDeferred ||
                status == .unsupportedFrequencyTable ||
                status == .outOfRange,
            ignoredAsNoOp: status == .noActiveVoice ||
                status == .zeroParamEffectMemoryDeferred ||
                status == .zeroSpeedOrDepthEffectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            vibratoSpeed: speed,
            vibratoDepth: depth,
            vibratoSpeedSource: speedSource,
            vibratoDepthSource: depthSource,
            vibratoControlValue: controlValue,
            vibratoWaveform: waveform.name,
            vibratoWaveformSource: waveformSource,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: effectMemoryMissing,
            effectMemoryDeferred: effectMemoryDeferred,
            vibratoSpeedMemorySource: speedMemorySource,
            vibratoDepthMemorySource: depthMemorySource,
            memoryUnavailableReason: memoryUnavailableReason,
            volumeSlideUp: volumeSlide?.up,
            volumeSlideDown: volumeSlide?.down,
            volumeSlideAmount: volumeSlide?.amount,
            volumeSlideDirection: volumeSlide?.direction,
            phaseBefore: phaseBefore,
            phaseAfter: phaseAfter,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

    private static func handleTonePortamento(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        instrumentStateBefore: ChannelState? = nil,
        instrumentStateAfter: ChannelState? = nil,
        instrumentDefaultVolumeApplied: Bool = false,
        sampleSelectedBefore: Int? = nil,
        sampleSelectedAfter: Int? = nil
    ) -> PlaybackSongSyntheticTonePortamentoDiagnostic {
        let hasActiveVoice = channelState.activeEventIndex != nil
        let targetExistsBefore = channelState.tonePortamentoTargetPlaybackStep != nil &&
            channelState.tonePortamentoTargetLinearPeriod != nil
        let noteTargetBefore = channelState.tonePortamentoTargetNote
        let currentLinearPeriodBefore = channelState.activeLinearPeriod
        let currentPlaybackStepBefore = channelState.activePlaybackStep
        let targetNoteFromCell = (1...96).contains(cell.note) ? cell.note : nil
        let sameCellNote = targetNoteFromCell != nil
        let instrumentStateUpdated = instrumentStateAfter != nil
        let channelVolumeBefore = instrumentStateBefore?.volumeValue
        let channelVolumeAfter = instrumentStateAfter?.volumeValue
        let gainBefore = instrumentStateBefore?.activeSampleVolume.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: instrumentStateBefore?.volumeValue ?? 64
            )
        }
        let gainAfter = instrumentStateAfter?.activeSampleVolume.map {
            adaptedGain(
                sampleVolume: $0,
                channelVolume: instrumentStateAfter?.volumeValue ?? 64
            )
        }

        if cell.effectParam > 0 {
            channelState.tonePortamentoSpeed = Int(cell.effectParam)
        }

        guard hasActiveVoice else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noActiveVoice,
                activeVoiceFound: false,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsBefore,
                targetNote: targetNoteFromCell ?? channelState.tonePortamentoTargetNote,
                targetLinearPeriod: channelState.tonePortamentoTargetLinearPeriod,
                targetPlaybackStep: channelState.tonePortamentoTargetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                stepUpdates: [],
                policy: "no_active_voice_no_retrigger"
            )
        }

        if let targetNote = targetNoteFromCell {
            guard channelState.activeUsesLinearFrequencyTable == true,
                  let baseSampleRate = channelState.activeSampleBaseSampleRate,
                  let relativeNote = channelState.activeSampleRelativeNote,
                  let finetune = channelState.activeSampleFinetune else {
                return tonePortamentoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .unsupportedFrequencyTable,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    targetExistsBefore: targetExistsBefore,
                    targetExistsAfter: targetExistsBefore,
                    targetNote: targetNote,
                    targetLinearPeriod: channelState.tonePortamentoTargetLinearPeriod,
                    targetPlaybackStep: channelState.tonePortamentoTargetPlaybackStep,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                    stepUpdates: [],
                    policy: "linear_frequency_only_first_pass"
                )
            }
            guard let target = linearPitchTarget(
                note: targetNote,
                relativeNote: relativeNote,
                finetune: finetune,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                return tonePortamentoDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    cell: cell,
                    status: .outOfRange,
                    activeVoiceFound: true,
                    activeEventIndex: channelState.activeEventIndex,
                    activeEventMappingIndex: channelState.activeEventMappingIndex,
                    targetExistsBefore: targetExistsBefore,
                    targetExistsAfter: targetExistsBefore,
                    targetNote: targetNote,
                    targetLinearPeriod: nil,
                    targetPlaybackStep: nil,
                    currentLinearPeriodBefore: currentLinearPeriodBefore,
                    currentLinearPeriodAfter: channelState.activeLinearPeriod,
                    currentPlaybackStepBefore: currentPlaybackStepBefore,
                    currentPlaybackStepAfter: channelState.activePlaybackStep,
                    portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                    stepUpdates: [],
                    policy: "target_pitch_out_of_range"
                )
            }
            channelState.tonePortamentoTargetNote = targetNote
            channelState.tonePortamentoTargetLinearPeriod = target.linearPeriod
            channelState.tonePortamentoTargetPlaybackStep = target.playbackStep
        }

        let targetExistsAfter = channelState.tonePortamentoTargetPlaybackStep != nil &&
            channelState.tonePortamentoTargetLinearPeriod != nil
        guard targetExistsAfter,
              let targetLinearPeriod = channelState.tonePortamentoTargetLinearPeriod,
              let targetPlaybackStep = channelState.tonePortamentoTargetPlaybackStep else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noTarget,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: false,
                targetNote: targetNoteFromCell,
                targetLinearPeriod: nil,
                targetPlaybackStep: nil,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                stepUpdates: [],
                policy: "no_existing_target"
            )
        }
        guard let speed = channelState.tonePortamentoSpeed,
              speed > 0 else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .noSpeed,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsAfter,
                targetNote: channelState.tonePortamentoTargetNote,
                targetLinearPeriod: targetLinearPeriod,
                targetPlaybackStep: targetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: channelState.tonePortamentoSpeed ?? 0,
                stepUpdates: [],
                policy: "no_3xx_speed_memory"
            )
        }
        guard var currentLinearPeriod = channelState.activeLinearPeriod,
              var currentPlaybackStep = channelState.activePlaybackStep,
              let baseSampleRate = channelState.activeSampleBaseSampleRate else {
            return tonePortamentoDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                timingConfig: timingConfig,
                cell: cell,
                status: .unsupportedFrequencyTable,
                activeVoiceFound: true,
                activeEventIndex: channelState.activeEventIndex,
                activeEventMappingIndex: channelState.activeEventMappingIndex,
                targetExistsBefore: targetExistsBefore,
                targetExistsAfter: targetExistsAfter,
                targetNote: channelState.tonePortamentoTargetNote,
                targetLinearPeriod: targetLinearPeriod,
                targetPlaybackStep: targetPlaybackStep,
                currentLinearPeriodBefore: currentLinearPeriodBefore,
                currentLinearPeriodAfter: channelState.activeLinearPeriod,
                currentPlaybackStepBefore: currentPlaybackStepBefore,
                currentPlaybackStepAfter: channelState.activePlaybackStep,
                portamentoSpeed: speed,
                stepUpdates: [],
                policy: "missing_active_linear_pitch_state"
            )
        }

        var stepUpdates = [PlaybackSongSyntheticTonePortamentoStepUpdate]()
        let rowSpeed = max(1, timingConfig.speed)
        for tick in 1..<rowSpeed {
            if abs(currentLinearPeriod - targetLinearPeriod) <= 0.000000001 {
                currentLinearPeriod = targetLinearPeriod
                currentPlaybackStep = targetPlaybackStep
                break
            }
            let beforePeriod = currentLinearPeriod
            let beforeStep = currentPlaybackStep
            if targetLinearPeriod < currentLinearPeriod {
                currentLinearPeriod = max(targetLinearPeriod, currentLinearPeriod - Double(speed))
            } else {
                currentLinearPeriod = min(targetLinearPeriod, currentLinearPeriod + Double(speed))
            }
            guard let nextStep = playbackStep(
                linearPeriod: currentLinearPeriod,
                baseSampleRate: baseSampleRate,
                outputSampleRate: timingConfig.sampleRate
            ) else {
                break
            }
            currentPlaybackStep = nextStep
            let reachedTarget = abs(currentLinearPeriod - targetLinearPeriod) <= 0.000000001
            stepUpdates.append(PlaybackSongSyntheticTonePortamentoStepUpdate(
                syntheticTick: tick,
                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                linearPeriodBefore: beforePeriod,
                linearPeriodAfter: currentLinearPeriod,
                playbackStepBefore: beforeStep,
                playbackStepAfter: currentPlaybackStep,
                reachedTarget: reachedTarget
            ))
            if reachedTarget {
                currentLinearPeriod = targetLinearPeriod
                currentPlaybackStep = targetPlaybackStep
                break
            }
        }
        channelState.activeLinearPeriod = currentLinearPeriod
        channelState.activePlaybackStep = currentPlaybackStep

        return tonePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            cell: cell,
            status: .applied,
            activeVoiceFound: true,
            activeEventIndex: channelState.activeEventIndex,
            activeEventMappingIndex: channelState.activeEventMappingIndex,
            sameCellNote: sameCellNote,
            noteTriggerEventCreated: false,
            voiceReplacement: false,
            samplePositionReset: false,
            instrumentStateUpdated: instrumentStateUpdated,
            instrumentIndexBefore: instrumentStateBefore?.activeInstrumentIndex,
            instrumentIndexAfter: instrumentStateAfter?.activeInstrumentIndex,
            sampleSelectedBefore: sampleSelectedBefore,
            sampleSelectedAfter: sampleSelectedAfter,
            instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
            envelopeReset: false,
            envelopeResetModeled: false,
            channelVolumeBefore: channelVolumeBefore,
            channelVolumeAfter: channelVolumeAfter,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            noteTargetBefore: noteTargetBefore,
            noteTargetAfter: channelState.tonePortamentoTargetNote,
            audibleTransientExpected: instrumentDefaultVolumeApplied &&
                ((gainBefore ?? 0) < (gainAfter ?? 0)),
            cMixerReceivesNewVoice: false,
            cMixerReceivesOnlyStateUpdates: sameCellNote,
            targetExistsBefore: targetExistsBefore,
            targetExistsAfter: targetExistsAfter,
            targetNote: channelState.tonePortamentoTargetNote,
            targetLinearPeriod: targetLinearPeriod,
            targetPlaybackStep: targetPlaybackStep,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: channelState.activeLinearPeriod,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: channelState.activePlaybackStep,
            portamentoSpeed: speed,
            stepUpdates: stepUpdates,
            policy: "linear_period_units_per_tick_row_level_first_pass"
        )
    }

    private static func tonePortamentoDiagnostic(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        cell: PlaybackCell,
        status: PlaybackSongSyntheticTonePortamentoDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        sameCellNote: Bool = false,
        noteTriggerEventCreated: Bool = false,
        voiceReplacement: Bool = false,
        samplePositionReset: Bool = false,
        instrumentStateUpdated: Bool = false,
        instrumentIndexBefore: Int? = nil,
        instrumentIndexAfter: Int? = nil,
        sampleSelectedBefore: Int? = nil,
        sampleSelectedAfter: Int? = nil,
        instrumentDefaultVolumeApplied: Bool = false,
        envelopeReset: Bool = false,
        envelopeResetModeled: Bool = false,
        channelVolumeBefore: Int? = nil,
        channelVolumeAfter: Int? = nil,
        gainBefore: Float? = nil,
        gainAfter: Float? = nil,
        noteTargetBefore: UInt8? = nil,
        noteTargetAfter: UInt8? = nil,
        audibleTransientExpected: Bool = false,
        cMixerReceivesNewVoice: Bool = false,
        cMixerReceivesOnlyStateUpdates: Bool = false,
        targetExistsBefore: Bool,
        targetExistsAfter: Bool,
        targetNote: UInt8?,
        targetLinearPeriod: Double?,
        targetPlaybackStep: Double?,
        currentLinearPeriodBefore: Double?,
        currentLinearPeriodAfter: Double?,
        currentPlaybackStepBefore: Double?,
        currentPlaybackStepAfter: Double?,
        portamentoSpeed: Int,
        stepUpdates: [PlaybackSongSyntheticTonePortamentoStepUpdate],
        policy: String
    ) -> PlaybackSongSyntheticTonePortamentoDiagnostic {
        let applied = status == .applied
        return PlaybackSongSyntheticTonePortamentoDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: status == .unsupportedFrequencyTable,
            ignoredAsNoOp: !applied && status != .unsupportedFrequencyTable,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            sameCellNote: sameCellNote,
            noteTriggerEventCreated: noteTriggerEventCreated,
            voiceReplacement: voiceReplacement,
            samplePositionReset: samplePositionReset,
            instrumentStateUpdated: instrumentStateUpdated,
            instrumentIndexBefore: instrumentIndexBefore,
            instrumentIndexAfter: instrumentIndexAfter,
            sampleSelectedBefore: sampleSelectedBefore,
            sampleSelectedAfter: sampleSelectedAfter,
            instrumentDefaultVolumeApplied: instrumentDefaultVolumeApplied,
            envelopeReset: envelopeReset,
            envelopeResetModeled: envelopeResetModeled,
            channelVolumeBefore: channelVolumeBefore,
            channelVolumeAfter: channelVolumeAfter,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            noteTargetBefore: noteTargetBefore,
            noteTargetAfter: noteTargetAfter,
            audibleTransientExpected: audibleTransientExpected,
            cMixerReceivesNewVoice: cMixerReceivesNewVoice,
            cMixerReceivesOnlyStateUpdates: cMixerReceivesOnlyStateUpdates,
            targetExistsBefore: targetExistsBefore,
            targetExistsAfter: targetExistsAfter,
            targetNote: targetNote,
            targetLinearPeriod: targetLinearPeriod,
            targetPlaybackStep: targetPlaybackStep,
            currentLinearPeriodBefore: currentLinearPeriodBefore,
            currentLinearPeriodAfter: currentLinearPeriodAfter,
            currentPlaybackStepBefore: currentPlaybackStepBefore,
            currentPlaybackStepAfter: currentPlaybackStepAfter,
            portamentoSpeed: portamentoSpeed,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            stepUpdates: stepUpdates,
            policy: policy
        )
    }

    private static func handleKeyOff(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledStartFrame: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        cell: PlaybackCell,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField],
        eventCoverage: inout EventCoverageBuilder
    ) {
        guard let activeEventIndex = channelState.activeEventIndex,
              let activeEventMappingIndex = channelState.activeEventMappingIndex,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeEventMappingIndex),
              scheduledStartFrame >= (events[activeEventIndex].scheduledStartFrame ?? 0) else {
            keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                releaseFrame: nil,
                applied: false,
                deferred: true,
                reason: .noActiveVoice,
                activeEventIndex: nil
            ))
            let ignored = ignoredCell(
                source: source,
                channelIndex: channelIndex,
                cell: cell,
                reason: .keyOff,
                volumeColumn: volumeColumn,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffect(cell)
            )
            ignoredCells.append(ignored)
            eventCoverage.recordIgnoredCell(
                reason: ignored.skipReason,
                isNormalNote: false,
                isNoteOffWithoutActiveVoice: true
            )
            appendDeferredFields(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                volumeColumn: volumeColumn,
                includeKeyOff: true,
                deferredCellFields: &deferredCellFields
            )
            return
        }

        let previousMapping = eventMappings[activeEventMappingIndex]
        let fadeoutDecrement = fadeoutFrameDecrement(
            fadeoutValue: previousMapping.volumeEnvelopeSemantics.fadeoutValue,
            sampleRate: previousMapping.outputSampleRate
        )
        events[activeEventIndex] = events[activeEventIndex].withKeyOffFrame(
            scheduledStartFrame,
            fadeoutFrameDecrement: fadeoutDecrement
        )
        eventMappings[activeEventMappingIndex] = eventMapping(
            previousMapping,
            applying: previousMapping.volumeEnvelopeSemantics.applyingKeyOff(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                releaseFrame: scheduledStartFrame
            )
        )
        keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            releaseFrame: scheduledStartFrame,
            applied: true,
            deferred: false,
            reason: .releasedActiveVoice,
            activeEventIndex: activeEventIndex
        ))
        if hasDeferredEffect(cell) || volumeColumn.deferred {
            eventCoverage.recordDeferredCellWithoutSkip()
        }
        clearActiveVoiceState(&channelState)
    }

    @discardableResult
    private static func handleRetrigger(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        globalVolumeState: GlobalVolumeState,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        retriggerEffects: inout [PlaybackSongSyntheticRetriggerDiagnostic],
        eventCoverage: inout EventCoverageBuilder
    ) -> PlaybackSongSyntheticRetriggerDiagnostic? {
        guard isRetriggerEffect(cell) else {
            return nil
        }

        let interval = extendedEffectTick(cell)
        let rowSpeed = timingConfig.speed
        let rowBPM = timingConfig.bpm
        let activeEventIndexBefore = channelState.activeEventIndex
        let activeMappingIndexBefore = channelState.activeEventMappingIndex
        let activeVoiceFound = activeEventIndexBefore.map { events.indices.contains($0) } == true &&
            activeMappingIndexBefore.map { eventMappings.indices.contains($0) } == true &&
            channelState.activeSampleVolume != nil

        func diagnostic(
            status: PlaybackSongSyntheticRetriggerDiagnostic.Status,
            ticks: [Int] = [],
            frames: [Int] = [],
            eventIndices: [Int] = [],
            replacedEventIndices: [Int] = []
        ) -> PlaybackSongSyntheticRetriggerDiagnostic {
            let applied = status == .applied
            let deferred = status == .ignoredE90NoEffectMemory
            let ignoredAsNoOp = status == .ignoredE90NoEffectMemory ||
                status == .noActiveVoice ||
                status == .outOfRowNoOp
            let outOfRow = status == .outOfRowNoOp
            let activeMapping = activeMappingIndexBefore.flatMap {
                eventMappings.indices.contains($0) ? eventMappings[$0] : nil
            }
            let activeEvent = activeEventIndexBefore.flatMap {
                events.indices.contains($0) ? events[$0] : nil
            }
            return PlaybackSongSyntheticRetriggerDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: status,
                detected: true,
                applied: applied,
                deferred: deferred,
                ignoredAsNoOp: ignoredAsNoOp,
                outOfRow: outOfRow,
                activeVoiceFound: activeVoiceFound,
                retriggerIntervalTicks: interval,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                retriggerTicks: ticks,
                retriggerFrames: frames,
                retriggerEventIndices: eventIndices,
                replacedEventIndices: replacedEventIndices,
                activeEventIndexBefore: activeEventIndexBefore,
                selectedSampleIndex: activeMapping?.sampleIndex,
                selectedSampleLength: activeMapping?.selectedSampleLength,
                initialSourceFrame: activeEvent?.initialSourceFrame,
                playbackStep: activeEvent?.playbackStep,
                gain: activeEvent?.gain,
                pan: activeEvent?.pan,
                envelopePolicy: "fresh_event_restarts_envelope"
            )
        }

        guard interval > 0 else {
            let result = diagnostic(status: .ignoredE90NoEffectMemory)
            retriggerEffects.append(result)
            return result
        }
        guard interval < rowSpeed else {
            let result = diagnostic(status: .outOfRowNoOp)
            retriggerEffects.append(result)
            return result
        }
        guard let activeEventIndex = activeEventIndexBefore,
              let activeMappingIndex = activeMappingIndexBefore,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeMappingIndex),
              let activeSampleVolume = channelState.activeSampleVolume else {
            let result = diagnostic(status: .noActiveVoice)
            retriggerEffects.append(result)
            return result
        }

        let sourceEvent = events[activeEventIndex]
        let sourceMapping = eventMappings[activeMappingIndex]
        let gain = adaptedGain(
            sampleVolume: activeSampleVolume,
            channelVolume: channelState.volumeValue,
            globalVolume: globalVolumeState.volumeValue
        )
        let pan = channelState.pan
        var ticks = [Int]()
        var frames = [Int]()
        var eventIndices = [Int]()
        var replacedEventIndices = [Int]()
        var previousEventIndex = activeEventIndex

        var tick = interval
        while tick < rowSpeed {
            let frame = timingPlan.frameFor(row: syntheticRow, tick: tick)
            let eventIndex = events.count
            events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: tick,
                scheduledStartFrame: frame,
                sample: sourceEvent.sample,
                gain: gain,
                pan: pan,
                playbackStep: sourceEvent.playbackStep,
                loop: sourceEvent.loop,
                initialSourceFrame: sourceEvent.initialSourceFrame,
                volumeEnvelope: sourceEvent.volumeEnvelope,
                panEnvelope: sourceEvent.panEnvelope
            ))
            eventMappings.append(retriggeredEventMapping(
                from: sourceMapping,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                eventIndex: eventIndex,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                volumeColumn: volumeColumn,
                effectiveVolumeValue: channelState.volumeValue,
                effectiveGlobalVolumeValue: globalVolumeState.volumeValue,
                effectiveGlobalVolumeMultiplier: globalVolumeState.multiplier,
                effectivePan: pan
            ))
            eventCoverage.recordScheduledNote(
                method: sourceMapping.sampleSelectionMethod,
                firstPlayableSampleFallbackUsed: sourceMapping.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sourceMapping.sampleMapKeymapBehaviorDeferred
            )
            ticks.append(tick)
            frames.append(frame)
            eventIndices.append(eventIndex)
            replacedEventIndices.append(previousEventIndex)
            previousEventIndex = eventIndex
            tick += interval
        }

        channelState.activeEventIndex = previousEventIndex
        channelState.activeEventMappingIndex = eventMappings.count - 1
        channelState.activeSampleVolume = activeSampleVolume

        let result = diagnostic(
            status: .applied,
            ticks: ticks,
            frames: frames,
            eventIndices: eventIndices,
            replacedEventIndices: replacedEventIndices
        )
        retriggerEffects.append(result)
        return result
    }

    private static func handleNoteCut(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        channelState: inout ChannelState,
        noteCutEffects: inout [PlaybackSongSyntheticNoteCutDiagnostic]
    ) {
        guard let diagnostic = noteCutDiagnostic(
            from: cell,
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            timingConfig: timingConfig,
            timingPlan: timingPlan,
            activeEventIndex: channelState.activeEventIndex
        ) else {
            return
        }
        noteCutEffects.append(diagnostic)
        guard diagnostic.applied else {
            return
        }
        clearActiveVoiceState(&channelState)
    }

    private static func noteCutDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        activeEventIndex: Int?
    ) -> PlaybackSongSyntheticNoteCutDiagnostic? {
        guard isNoteCutEffect(cell) else {
            return nil
        }
        let tick = extendedEffectTick(cell)
        let rowSpeed = timingConfig.speed
        let rowBPM = timingConfig.bpm
        guard tick < rowSpeed else {
            return PlaybackSongSyntheticNoteCutDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .outOfRowNoOp,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: true,
                outOfRow: true,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                scheduledFrame: nil,
                activeEventIndex: activeEventIndex
            )
        }
        let cutFrame = timingPlan.frameFor(row: syntheticRow, tick: tick)
        guard let activeEventIndex else {
            return PlaybackSongSyntheticNoteCutDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .noActiveVoice,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: true,
                outOfRow: false,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                scheduledFrame: cutFrame,
                activeEventIndex: nil
            )
        }
        return PlaybackSongSyntheticNoteCutDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: tick,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .applied,
            detected: true,
            applied: true,
            deferred: false,
            ignoredAsNoOp: false,
            outOfRow: false,
            requestedTick: tick,
            rowSpeed: rowSpeed,
            rowBPM: rowBPM,
            scheduledFrame: cutFrame,
            activeEventIndex: activeEventIndex
        )
    }

    private static func noteDelayDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        originalFrame: Int,
        eventIndex: Int?
    ) -> PlaybackSongSyntheticNoteDelayDiagnostic? {
        guard isNoteDelayEffect(cell) else {
            return nil
        }
        let tick = extendedEffectTick(cell)
        let rowSpeed = timingConfig.speed
        let rowBPM = timingConfig.bpm
        guard tick < rowSpeed else {
            return PlaybackSongSyntheticNoteDelayDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .outOfRowNoOp,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: true,
                outOfRow: true,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                originalFrame: originalFrame,
                delayedFrame: nil,
                eventIndex: eventIndex
            )
        }
        let delayedFrame = timingPlan.frameFor(row: syntheticRow, tick: tick)
        guard (1...96).contains(cell.note) else {
            return PlaybackSongSyntheticNoteDelayDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: tick,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .noNoteDeferred,
                detected: true,
                applied: false,
                deferred: true,
                ignoredAsNoOp: false,
                outOfRow: false,
                requestedTick: tick,
                rowSpeed: rowSpeed,
                rowBPM: rowBPM,
                originalFrame: originalFrame,
                delayedFrame: nil,
                eventIndex: eventIndex
            )
        }
        return PlaybackSongSyntheticNoteDelayDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: tick,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .applied,
            detected: true,
            applied: true,
            deferred: false,
            ignoredAsNoOp: false,
            outOfRow: false,
            requestedTick: tick,
            rowSpeed: rowSpeed,
            rowBPM: rowBPM,
            originalFrame: originalFrame,
            delayedFrame: delayedFrame,
            eventIndex: eventIndex
        )
    }

    private static func eventMapping(
        _ mapping: PlaybackSongSyntheticEventMapping,
        applying semantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: mapping.source,
            channelIndex: mapping.channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            selectedSampleLength: mapping.selectedSampleLength,
            sampleMapKeymapPresent: mapping.sampleMapKeymapPresent,
            mappedSampleIndex: mapping.mappedSampleIndex,
            mappedSampleValid: mapping.mappedSampleValid,
            sampleSelectionMethod: mapping.sampleSelectionMethod,
            sampleSelectionStrategy: mapping.sampleSelectionStrategy,
            firstPlayableSampleFallbackUsed: mapping.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: mapping.sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: mapping.sampleMapKeymapMissingOrDeferred,
            effectType: mapping.effectType,
            effectParam: mapping.effectParam,
            syntheticRow: mapping.syntheticRow,
            syntheticTick: mapping.syntheticTick,
            eventIndex: mapping.eventIndex,
            loopMode: mapping.loopMode,
            volumeColumn: mapping.volumeColumn,
            sampleOffset: mapping.sampleOffset,
            hasIgnoredVolumeColumn: mapping.hasIgnoredVolumeColumn,
            hasIgnoredEffect: mapping.hasIgnoredEffect,
            effectiveVolumeValue: mapping.effectiveVolumeValue,
            effectiveGlobalVolumeValue: mapping.effectiveGlobalVolumeValue,
            effectiveGlobalVolumeMultiplier: mapping.effectiveGlobalVolumeMultiplier,
            effectivePan: mapping.effectivePan,
            volumeEnvelopeStatus: mapping.volumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: mapping.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: mapping.mappedVolumeEnvelopePointCount,
            hasDeferredVolumeEnvelopeSustain: semantics.sustainDeferred,
            hasDeferredVolumeEnvelopeLoop: semantics.loopDeferred,
            hasDeferredVolumeEnvelopeFadeout: semantics.fadeoutDeferred,
            volumeEnvelopeSemantics: semantics,
            sampleBaseSampleRate: mapping.sampleBaseSampleRate,
            sampleRelativeNote: mapping.sampleRelativeNote,
            sampleFinetune: mapping.sampleFinetune,
            outputSampleRate: mapping.outputSampleRate,
            effectiveNoteValue: mapping.effectiveNoteValue,
            effectiveNoteIndex: mapping.effectiveNoteIndex,
            effectiveFinetune: mapping.effectiveFinetune,
            linearPeriod: mapping.linearPeriod,
            linearFrequency: mapping.linearFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    private static func retriggeredEventMapping(
        from mapping: PlaybackSongSyntheticEventMapping,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int,
        eventIndex: Int,
        effectType: UInt8,
        effectParam: UInt8,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        effectiveVolumeValue: Int,
        effectiveGlobalVolumeValue: Int,
        effectiveGlobalVolumeMultiplier: Float,
        effectivePan: Float
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: source,
            channelIndex: channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            selectedSampleLength: mapping.selectedSampleLength,
            sampleMapKeymapPresent: mapping.sampleMapKeymapPresent,
            mappedSampleIndex: mapping.mappedSampleIndex,
            mappedSampleValid: mapping.mappedSampleValid,
            sampleSelectionMethod: mapping.sampleSelectionMethod,
            sampleSelectionStrategy: mapping.sampleSelectionStrategy,
            firstPlayableSampleFallbackUsed: mapping.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: mapping.sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: mapping.sampleMapKeymapMissingOrDeferred,
            effectType: effectType,
            effectParam: effectParam,
            syntheticRow: syntheticRow,
            syntheticTick: syntheticTick,
            eventIndex: eventIndex,
            loopMode: mapping.loopMode,
            volumeColumn: volumeColumn,
            sampleOffset: mapping.sampleOffset,
            hasIgnoredVolumeColumn: volumeColumn.rawValue != 0 && !volumeColumn.applied,
            hasIgnoredEffect: false,
            effectiveVolumeValue: effectiveVolumeValue,
            effectiveGlobalVolumeValue: effectiveGlobalVolumeValue,
            effectiveGlobalVolumeMultiplier: effectiveGlobalVolumeMultiplier,
            effectivePan: effectivePan,
            volumeEnvelopeStatus: mapping.volumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: mapping.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: mapping.mappedVolumeEnvelopePointCount,
            hasDeferredVolumeEnvelopeSustain: mapping.hasDeferredVolumeEnvelopeSustain,
            hasDeferredVolumeEnvelopeLoop: mapping.hasDeferredVolumeEnvelopeLoop,
            hasDeferredVolumeEnvelopeFadeout: mapping.hasDeferredVolumeEnvelopeFadeout,
            volumeEnvelopeSemantics: mapping.volumeEnvelopeSemantics,
            sampleBaseSampleRate: mapping.sampleBaseSampleRate,
            sampleRelativeNote: mapping.sampleRelativeNote,
            sampleFinetune: mapping.sampleFinetune,
            outputSampleRate: mapping.outputSampleRate,
            effectiveNoteValue: mapping.effectiveNoteValue,
            effectiveNoteIndex: mapping.effectiveNoteIndex,
            effectiveFinetune: mapping.effectiveFinetune,
            linearPeriod: mapping.linearPeriod,
            linearFrequency: mapping.linearFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    private struct VolumeEnvelopeMapping: Equatable {
        let envelope: MixerEnvelope?
        let status: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus
        let sourcePointCount: Int
        let mappedPointCount: Int
        let sustainFrame: Int?
        let loopStartFrame: Int?
        let loopEndFrame: Int?
    }

    private struct PlaybackStepMapping: Equatable {
        let playbackStep: Double
        let outputSampleRate: Double
        let effectiveNoteValue: Int?
        let effectiveNoteIndex: Int?
        let effectiveFinetune: Int?
        let linearPeriod: Double?
        let linearFrequency: Double?
        let finetuneStatus: PlaybackSongSyntheticEventMapping.FinetuneStatus
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus
        let linearFrequencyApplied: Bool
        let amigaFrequencyDeferred: Bool
        let applied: Bool
        let usedNeutralStep: Bool
    }

    private struct LinearPitchTarget: Equatable {
        let linearPeriod: Double
        let playbackStep: Double
        let linearFrequency: Double
        let effectiveNoteValue: Int
        let effectiveNoteIndex: Int
        let effectiveFinetune: Int
    }

    private static func adaptedGain(
        sampleVolume: Float,
        channelVolume: Int,
        globalVolume: Int = GlobalVolumeState.defaultValue
    ) -> Float {
        let baseGain = sampleVolume.isFinite ? sampleVolume : 0
        let volumeMultiplier = volumeMultiplier(for: channelVolume)
        let globalMultiplier = globalVolumeMultiplier(for: globalVolume)
        // The bounded adapter treats supported XM volume-column volume commands as row-level
        // channel-volume updates: final event gain = sample volume * (channel volume / 64).
        // Hxy global-volume slides are another Swift-side row-level multiplier.
        // Parsed volume envelopes remain separate C mixer envelopes and multiply this gain at render time.
        return clampedGain(baseGain * volumeMultiplier * globalMultiplier)
    }

    private static func volumeMultiplier(for volumeValue: Int) -> Float {
        Float(clampedVolumeValue(volumeValue)) / 64.0
    }

    private static func clampedVolumeValue(_ value: Int) -> Int {
        min(64, max(0, value))
    }

    private static func clampedGlobalVolumeValue(_ value: Int) -> Int {
        min(64, max(0, value))
    }

    private static func globalVolumeMultiplier(for volumeValue: Int) -> Float {
        Float(clampedGlobalVolumeValue(volumeValue)) / 64.0
    }

    private static func clampedPanningValue(_ value: Double) -> Double {
        min(255.0, max(0.0, value.isFinite ? value : 127.5))
    }

    private static func clampedGain(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }

    private static func playbackStepMapping(
        note: UInt8,
        sample: PlaybackSample,
        usesLinearFrequencyTable: Bool,
        timingConfig: SyntheticTrackerTimingConfig,
        finetuneOverride: Int? = nil
    ) -> PlaybackStepMapping {
        let outputSampleRate = timingConfig.sampleRate
        guard usesLinearFrequencyTable else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: nil,
                effectiveNoteIndex: nil,
                effectiveFinetune: nil,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .amigaTableDeferredNeutralFallback,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: true,
                applied: false,
                usedNeutralStep: true
            )
        }

        let baseSampleRate = sample.baseSampleRate
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: nil,
                effectiveNoteIndex: nil,
                effectiveFinetune: nil,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        guard let target = linearPitchTarget(
            note: note,
            relativeNote: sample.relativeNote,
            finetune: finetuneOverride ?? sample.finetune,
            baseSampleRate: baseSampleRate,
            outputSampleRate: outputSampleRate
        ) else {
            let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: sample.relativeNote)
            let effectiveNoteIndex = effectiveNoteValue - 1
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: effectiveNoteValue,
                effectiveNoteIndex: effectiveNoteIndex,
                effectiveFinetune: clampedFinetune(finetuneOverride ?? sample.finetune),
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        return PlaybackStepMapping(
            playbackStep: target.playbackStep,
            outputSampleRate: outputSampleRate,
            effectiveNoteValue: target.effectiveNoteValue,
            effectiveNoteIndex: target.effectiveNoteIndex,
            effectiveFinetune: target.effectiveFinetune,
            linearPeriod: target.linearPeriod,
            linearFrequency: target.linearFrequency,
            finetuneStatus: .applied,
            frequencyTableStatus: .linearApplied,
            linearFrequencyApplied: true,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(target.playbackStep - 1.0) <= 0.000000001
        )
    }

    private static func linearPitchTarget(
        note: UInt8,
        relativeNote: Int,
        finetune: Int,
        baseSampleRate: Double,
        outputSampleRate: Double
    ) -> LinearPitchTarget? {
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return nil
        }
        let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: relativeNote)
        let effectiveNoteIndex = effectiveNoteValue - 1
        let effectiveFinetune = clampedFinetune(finetune)

        // XM linear frequency mode is period based even though the C mixer consumes a source-sample step.
        // FT2 applies sample relative note to the pattern note and clamps the zero-based real note to 0...118.
        // FT2's linear period formula is:
        // period = 7680 - (zeroBasedNote * 64) - (finetune / 2)
        // C-4 is note value 49, zero-based note 48, period 4608, so it maps to the sample base rate.
        let linearPeriod = xmLinearPeriodBase
            - (Double(effectiveNoteIndex) * xmLinearPeriodUnitsPerSemitone)
            - (Double(effectiveFinetune) / 2.0)
        guard let step = playbackStep(
            linearPeriod: linearPeriod,
            baseSampleRate: baseSampleRate,
            outputSampleRate: outputSampleRate
        ) else {
            return nil
        }
        let linearFrequency = step * outputSampleRate
        guard linearPeriod.isFinite,
              linearFrequency.isFinite,
              linearFrequency > 0 else {
            return nil
        }
        return LinearPitchTarget(
            linearPeriod: linearPeriod,
            playbackStep: step,
            linearFrequency: linearFrequency,
            effectiveNoteValue: effectiveNoteValue,
            effectiveNoteIndex: effectiveNoteIndex,
            effectiveFinetune: effectiveFinetune
        )
    }

    private static func playbackStep(
        linearPeriod: Double,
        baseSampleRate: Double,
        outputSampleRate: Double
    ) -> Double? {
        guard linearPeriod.isFinite,
              outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return nil
        }
        let linearFrequency = baseSampleRate * pow(
            2.0,
            (xmLinearC4Period - linearPeriod) / xmLinearPeriodUnitsPerOctave
        )
        let step = linearFrequency / outputSampleRate
        guard linearFrequency.isFinite,
              linearFrequency > 0,
              step.isFinite,
              step > 0,
              step <= Double(UInt32.max) else {
            return nil
        }
        return step
    }

    private static func clampedLinearPeriod(_ linearPeriod: Double) -> Double {
        guard linearPeriod.isFinite else {
            return xmLinearC4Period
        }
        return min(xmLinearMaximumSafePeriod, max(xmLinearMinimumSafePeriod, linearPeriod))
    }

    private static func clampedEffectiveNoteValue(note: UInt8, relativeNote: Int) -> Int {
        min(xmLinearMaximumEffectiveNoteValue, max(1, Int(note) + relativeNote))
    }

    private static func clampedFinetune(_ finetune: Int) -> Int {
        min(127, max(-128, finetune))
    }

    private static func mixerVolumeEnvelope(
        from envelope: PlaybackVolumeEnvelope,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> VolumeEnvelopeMapping {
        guard hasVolumeEnvelopeMetadata(envelope) else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .absent,
                sourcePointCount: 0,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }
        guard envelope.enabled else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .disabled,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        let sourcePoints = Array(envelope.points.prefix(maxMixerEnvelopePointCount))
        guard !sourcePoints.isEmpty else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: 0,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        let timing = SyntheticTrackerTiming(config: timingConfig)
        guard timing.framesPerTick.isFinite, timing.framesPerTick > 0 else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        var mappedPoints = [MixerEnvelopePoint]()
        mappedPoints.reserveCapacity(sourcePoints.count)
        for point in sourcePoints {
            let exactFrame = Double(point.tick) * timing.framesPerTick
            guard exactFrame.isFinite, exactFrame >= 0, exactFrame < Double(Int.max) else {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0,
                    sustainFrame: nil,
                    loopStartFrame: nil,
                    loopEndFrame: nil
                )
            }
            let frame = Int(exactFrame.rounded(.down))
            if let previous = mappedPoints.last, frame <= previous.positionFrame {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0,
                    sustainFrame: nil,
                    loopStartFrame: nil,
                    loopEndFrame: nil
                )
            }
            mappedPoints.append(MixerEnvelopePoint(positionFrame: frame, value: point.normalizedValue))
        }
        let sustainFrame = mappedFrame(
            forSourcePointIndex: envelope.sustainPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let loopStartFrame = mappedFrame(
            forSourcePointIndex: envelope.loopStartPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let loopEndFrame = mappedFrame(
            forSourcePointIndex: envelope.loopEndPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let appliedSustainFrame = envelopeSustainFlagSet(envelope) ? sustainFrame : nil
        let appliedLoopStartFrame: Int?
        let appliedLoopEndFrame: Int?
        if envelopeLoopFlagSet(envelope),
           let loopStartFrame,
           let loopEndFrame,
           loopEndFrame >= loopStartFrame {
            appliedLoopStartFrame = loopStartFrame
            appliedLoopEndFrame = loopEndFrame
        } else {
            appliedLoopStartFrame = nil
            appliedLoopEndFrame = nil
        }

        return VolumeEnvelopeMapping(
            envelope: MixerEnvelope(
                points: mappedPoints,
                sustainFrame: appliedSustainFrame,
                loopStartFrame: appliedLoopStartFrame,
                loopEndFrame: appliedLoopEndFrame
            ),
            status: .mapped,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mappedPoints.count,
            sustainFrame: appliedSustainFrame,
            loopStartFrame: appliedLoopStartFrame,
            loopEndFrame: appliedLoopEndFrame
        )
    }

    private static func mappedFrame(
        forSourcePointIndex pointIndex: Int?,
        sourcePoints: [PlaybackEnvelopePoint],
        mappedPoints: [MixerEnvelopePoint]
    ) -> Int? {
        guard let pointIndex,
              sourcePoints.indices.contains(pointIndex),
              mappedPoints.indices.contains(pointIndex) else {
            return nil
        }
        return mappedPoints[pointIndex].positionFrame
    }

    private static func hasVolumeEnvelopeMetadata(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        envelope.enabled ||
            !envelope.points.isEmpty ||
            envelope.typeFlags != 0 ||
            envelope.sustainPointIndex != nil ||
            envelope.loopStartPointIndex != nil ||
            envelope.loopEndPointIndex != nil ||
            envelope.fadeout > 0
    }

    private static func volumeEnvelopeSemantics(
        from envelope: PlaybackVolumeEnvelope,
        mapping: VolumeEnvelopeMapping
    ) -> PlaybackSongSyntheticEnvelopeSemanticsDiagnostic {
        let sustainEnabled = envelopeSustainFlagSet(envelope)
        let loopEnabled = envelopeLoopFlagSet(envelope)
        let sustainApplied = mapping.status == .mapped && sustainEnabled && mapping.sustainFrame != nil
        let loopApplied = mapping.status == .mapped && loopEnabled && mapping.loopStartFrame != nil && mapping.loopEndFrame != nil
        var limitations = [String]()
        if sustainApplied || loopApplied || envelope.fadeout > 0 {
            limitations.append("first_pass_bounded_offline_envelope_approximation")
        }
        if sustainApplied {
            limitations.append("sustain_holds_at_mapped_frame_while_keyed_on")
        }
        if loopApplied {
            limitations.append("envelope_loop_is_frame_based_while_keyed_on")
        }
        if envelope.fadeout > 0 {
            limitations.append("fadeout_uses_linear_per_frame_decrement_after_key_off")
        }

        return PlaybackSongSyntheticEnvelopeSemanticsDiagnostic(
            envelopeEnabled: envelope.enabled,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mapping.mappedPointCount,
            sustainEnabled: sustainEnabled,
            sustainApplied: sustainApplied,
            sustainDeferred: sustainEnabled && !sustainApplied,
            sustainPointIndex: envelope.sustainPointIndex,
            sustainTick: envelope.sustainPoint?.tick,
            sustainFrame: mapping.sustainFrame,
            loopEnabled: loopEnabled,
            loopApplied: loopApplied,
            loopDeferred: loopEnabled && !loopApplied,
            loopStartPointIndex: envelope.loopStartPointIndex,
            loopEndPointIndex: envelope.loopEndPointIndex,
            loopStartTick: envelope.loopStartPoint?.tick,
            loopEndTick: envelope.loopEndPoint?.tick,
            loopStartFrame: mapping.loopStartFrame,
            loopEndFrame: mapping.loopEndFrame,
            keyOffEncountered: false,
            keyOffApplied: false,
            keyOffDeferred: false,
            keyOffSource: nil,
            keyOffChannelIndex: nil,
            keyOffSyntheticRow: nil,
            keyOffSyntheticTick: nil,
            releaseFrame: nil,
            fadeoutValue: envelope.fadeout,
            fadeoutApplied: false,
            fadeoutDeferred: envelope.fadeout > 0,
            limitations: limitations
        )
    }

    private static func envelopeSustainFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x02) != 0
    }

    private static func envelopeLoopFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x04) != 0
    }

    private static func fadeoutFrameDecrement(fadeoutValue: Int, sampleRate: Double) -> Float {
        guard fadeoutValue > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        // First-pass offline approximation: spread the XM tick-domain fadeout decrement
        // smoothly across one default-speed tick worth of output frames.
        let framesPerDefaultTick = sampleRate * PlaybackTiming.xmDefault.tickDuration
        guard framesPerDefaultTick.isFinite, framesPerDefaultTick > 0 else {
            return 0
        }
        return Float((Double(fadeoutValue) / 65_536.0) / framesPerDefaultTick)
    }

    private static func extendedEffectSubcommand(_ cell: PlaybackCell) -> UInt8? {
        guard cell.effectType == 0x0E else {
            return nil
        }
        return (cell.effectParam >> 4) & 0x0F
    }

    private static func extendedEffectTick(_ cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    private static func isNoteCutEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0C
    }

    private static func isNoteDelayEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0D
    }

    private static func isRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x09
    }

    private static func isSetFinetuneEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x05
    }

    private static func isFinePortamentoUpEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x01
    }

    private static func finePortamentoUpAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    private static func isFinePortamentoDownEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x02
    }

    private static func finePortamentoDownAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    private static func isFineVolumeSlideUpEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0A
    }

    private static func isFineVolumeSlideDownEffect(_ cell: PlaybackCell) -> Bool {
        extendedEffectSubcommand(cell) == 0x0B
    }

    private static func isFineVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        isFineVolumeSlideUpEffect(cell) || isFineVolumeSlideDownEffect(cell)
    }

    private static func fineVolumeSlideAmount(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    private static func setFinetuneNibble(from cell: PlaybackCell) -> Int {
        Int(cell.effectParam & 0x0F)
    }

    private static func setFinetuneValue(from cell: PlaybackCell) -> Int {
        (setFinetuneNibble(from: cell) * 16) - 128
    }

    private static func setFinetuneStatus(
        for pitchMapping: PlaybackStepMapping
    ) -> PlaybackSongSyntheticSetFinetuneDiagnostic.Status {
        if pitchMapping.applied {
            return .applied
        }
        if pitchMapping.amigaFrequencyDeferred {
            return .unsupportedFrequencyTable
        }
        return .outOfRange
    }

    private static func setFinetuneDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        timingConfig: SyntheticTrackerTimingConfig,
        status: PlaybackSongSyntheticSetFinetuneDiagnostic.Status,
        activeVoiceFound: Bool,
        activeEventIndex: Int?,
        activeEventMappingIndex: Int?,
        sampleFinetune: Int? = nil,
        pitchMapping: PlaybackStepMapping? = nil
    ) -> PlaybackSongSyntheticSetFinetuneDiagnostic {
        let applied = status == .applied
        let effectMemoryDeferred = status == .noNoteDeferred
        let deferred = effectMemoryDeferred ||
            status == .unsupportedFrequencyTable ||
            status == .outOfRange
        let ignoredAsNoOp = status == .noActiveVoice
        let policy: String
        switch status {
        case .applied:
            policy = "same_cell_note_overrides_sample_finetune_no_memory"
        case .noNoteDeferred:
            policy = "no_same_cell_note_effect_memory_deferred"
        case .noActiveVoice:
            policy = "no_playable_same_cell_note"
        case .unsupportedFrequencyTable:
            policy = "linear_frequency_only_first_pass"
        case .outOfRange:
            policy = "pitch_mapping_out_of_range"
        }
        return PlaybackSongSyntheticSetFinetuneDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: status,
            detected: true,
            applied: applied,
            deferred: deferred,
            ignoredAsNoOp: ignoredAsNoOp,
            effectMemoryDeferred: effectMemoryDeferred,
            activeVoiceFound: activeVoiceFound,
            activeEventIndex: activeEventIndex,
            activeEventMappingIndex: activeEventMappingIndex,
            finetuneNibble: setFinetuneNibble(from: cell),
            sampleFinetune: sampleFinetune,
            effectiveFinetune: pitchMapping?.effectiveFinetune,
            linearPeriod: pitchMapping?.linearPeriod,
            linearFrequency: pitchMapping?.linearFrequency,
            playbackStep: pitchMapping?.playbackStep,
            rowSpeed: timingConfig.speed,
            rowBPM: timingConfig.bpm,
            policy: policy
        )
    }

    private static func sampleOffsetDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        selectedSampleLength: Int?,
        channelState: inout ChannelState
    ) -> PlaybackSongSyntheticSampleOffsetDiagnostic {
        let sampleLength = selectedSampleLength.map { max(0, $0) }
        guard cell.effectType == 0x09 else {
            return PlaybackSongSyntheticSampleOffsetDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .notPresent,
                detected: false,
                applied: false,
                deferred: false,
                ignoredAsNoOp: false,
                skipped: false,
                outOfRange: false,
                computedOffsetFrames: 0,
                appliedOffsetFrames: 0,
                selectedSampleLength: sampleLength,
                effectMemoryReused: false,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                memorySource: nil,
                memoryUnavailableReason: nil
            )
        }

        let targetMemorySource = effectMemorySource(source: source, channelIndex: channelIndex, cell: cell)
        let computedOffsetFrames: Int
        let memorySource: PlaybackSongSyntheticEffectMemorySource?
        let effectMemoryReused: Bool
        if cell.effectParam == 0 {
            if let memory = channelState.sampleOffsetMemory {
                computedOffsetFrames = memory.offsetFrames
                memorySource = memory.source
                effectMemoryReused = true
            } else {
                return PlaybackSongSyntheticSampleOffsetDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    status: .ignored900NoOp,
                    detected: true,
                    applied: false,
                    deferred: true,
                    ignoredAsNoOp: true,
                    skipped: false,
                    outOfRange: false,
                    computedOffsetFrames: 0,
                    appliedOffsetFrames: 0,
                    selectedSampleLength: sampleLength,
                    effectMemoryReused: false,
                    effectMemoryMissing: true,
                    effectMemoryDeferred: true,
                    memorySource: nil,
                    memoryUnavailableReason: "missing_9xx_sample_offset_memory"
                )
            }
        } else {
            computedOffsetFrames = Int(cell.effectParam) * 256
            channelState.sampleOffsetMemory = SampleOffsetMemory(
                offsetFrames: computedOffsetFrames,
                source: targetMemorySource
            )
            memorySource = nil
            effectMemoryReused = false
        }

        if let sampleLength, computedOffsetFrames >= sampleLength {
            return PlaybackSongSyntheticSampleOffsetDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                status: .outOfRangeSkipped,
                detected: true,
                applied: false,
                deferred: false,
                ignoredAsNoOp: false,
                skipped: true,
                outOfRange: true,
                computedOffsetFrames: computedOffsetFrames,
                appliedOffsetFrames: nil,
                selectedSampleLength: sampleLength,
                effectMemoryReused: effectMemoryReused,
                effectMemoryMissing: false,
                effectMemoryDeferred: false,
                memorySource: memorySource,
                memoryUnavailableReason: nil
            )
        }

        return PlaybackSongSyntheticSampleOffsetDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            status: .applied,
            detected: true,
            applied: true,
            deferred: false,
            ignoredAsNoOp: false,
            skipped: false,
            outOfRange: false,
            computedOffsetFrames: computedOffsetFrames,
            appliedOffsetFrames: computedOffsetFrames,
            selectedSampleLength: sampleLength,
            effectMemoryReused: effectMemoryReused,
            effectMemoryMissing: false,
            effectMemoryDeferred: false,
            memorySource: memorySource,
            memoryUnavailableReason: nil
        )
    }

    private static func effectCommandDiagnostic(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        traversalEffectStatuses: [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status],
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic? {
        guard shouldReportEffectCommand(cell) else {
            return nil
        }
        let traversalKey = TraversalEffectKey(
            orderIndex: source.orderIndex,
            patternIndex: source.patternIndex,
            rowIndex: source.rowIndex,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
        return PlaybackSongSyntheticEffectCommandDiagnostic(
            source: source,
            channelIndex: channelIndex,
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            decodedLabel: effectCommandLabel(effectType: cell.effectType, effectParam: cell.effectParam),
            status: traversalEffectStatuses[traversalKey] ?? effectCommandStatus(cell, timingConfig: timingConfig),
            isTraversalHazard: isTraversalHazard(cell)
        )
    }

    private static func shouldReportEffectCommand(_ cell: PlaybackCell) -> Bool {
        switch cell.effectType {
        case 0x00:
            return cell.effectParam != 0
        case 0x01...0x08, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x11:
            return true
        default:
            return false
        }
    }

    private static func effectCommandStatus(
        _ cell: PlaybackCell,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic.Status {
        switch cell.effectType {
        case 0x00 where cell.effectParam != 0:
            return .applied
        case 0x05,
             0x07:
            return .deferredUnsupported
        case 0x04:
            let speed = Int((cell.effectParam & 0xF0) >> 4)
            let depth = Int(cell.effectParam & 0x0F)
            return cell.effectParam == 0 || speed == 0 || depth == 0 ? .ignoredNoOp : .applied
        case 0x06:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x01...0x02:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x03:
            return .applied
        case 0x08, 0x0C:
            return .applied
        case 0x0A:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x0F:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x11:
            return cell.effectParam == 0 ? .ignoredNoOp : .applied
        case 0x0E where isRetriggerEffect(cell):
            let interval = extendedEffectTick(cell)
            guard interval > 0 else {
                return .ignoredNoOp
            }
            return interval < timingConfig.speed ? .applied : .ignoredNoOp
        case 0x0E where isSetFinetuneEffect(cell):
            return (1...96).contains(cell.note) ? .applied : .deferredUnsupported
        case 0x0E where isFinePortamentoUpEffect(cell):
            return finePortamentoUpAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isFinePortamentoDownEffect(cell):
            return finePortamentoDownAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isFineVolumeSlideEffect(cell):
            return fineVolumeSlideAmount(from: cell) == 0 ? .ignoredNoOp : .applied
        case 0x0E where isVibratoControlEffect(cell):
            return supportedVibratoWaveform(controlValue: Int(cell.effectParam & 0x0F)) == nil
                ? .deferredUnsupported
                : .applied
        case 0x0E where isNoteCutEffect(cell) || isNoteDelayEffect(cell):
            guard extendedEffectTick(cell) < timingConfig.speed else {
                return .ignoredNoOp
            }
            if isNoteDelayEffect(cell), !(1...96).contains(cell.note) {
                return .deferredUnsupported
            }
            return .applied
        case 0x0E where isE6xPatternLoopEffect(cell):
            return .deferredUnsupported
        case 0x0B, 0x0D, 0x0E:
            return .deferredUnsupported
        default:
            return .unknown
        }
    }

    private static func isTraversalHazard(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0B ||
            cell.effectType == 0x0D ||
            isE6xPatternLoopEffect(cell) ||
            (cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x0E)
    }

    private static func isE6xPatternLoopEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x06
    }

    private static func effectCommandLabel(effectType: UInt8, effectParam: UInt8) -> String {
        switch effectType {
        case 0x00:
            return effectParam != 0 ? "0xy arpeggio" : "none"
        case 0x01:
            return "1xx portamento up"
        case 0x02:
            return "2xx portamento down"
        case 0x03:
            return "3xx tone portamento"
        case 0x04:
            return "4xy vibrato"
        case 0x05:
            return "5xy tone portamento + volume slide"
        case 0x06:
            return "6xy vibrato + volume slide"
        case 0x07:
            return "7xy tremolo"
        case 0x08:
            return "8xx set panning"
        case 0x0A:
            return "Axy volume slide"
        case 0x0B:
            return "Bxx position jump"
        case 0x0C:
            return "Cxx set volume"
        case 0x0D:
            return "Dxx pattern break"
        case 0x0E:
            return extendedEffectCommandLabel(effectParam: effectParam)
        case 0x0F:
            return "Fxx speed/BPM"
        case 0x11:
            return "Hxy global volume slide"
        default:
            return "unknown/unsupported"
        }
    }

    private static func extendedEffectCommandLabel(effectParam: UInt8) -> String {
        switch (effectParam >> 4) & 0x0F {
        case 0x00:
            return "E0x filter toggle"
        case 0x01:
            return "E1x fine portamento up"
        case 0x02:
            return "E2x fine portamento down"
        case 0x03:
            return "E3x glissando control"
        case 0x04:
            return "E4x vibrato control"
        case 0x05:
            return "E5x set finetune"
        case 0x06:
            return "E6x pattern loop"
        case 0x07:
            return "E7x tremolo control"
        case 0x08:
            return "E8x set panning"
        case 0x09:
            return "E9x retrigger"
        case 0x0A:
            return "EAx fine volume slide up"
        case 0x0B:
            return "EBx fine volume slide down"
        case 0x0C:
            return "ECx note cut"
        case 0x0D:
            return "EDx note delay"
        case 0x0E:
            return "EEx pattern delay"
        case 0x0F:
            return "EFx invert loop"
        default:
            return "unknown/unsupported"
        }
    }

    private static func selectedSampleLength(_ sample: PlaybackSample) -> Int {
        min(max(0, sample.sampleLength), sample.pcm.count)
    }

    private static func hasEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType != 0 || cell.effectParam != 0
    }

    private static func hasDeferredEffect(_ cell: PlaybackCell) -> Bool {
        guard hasEffect(cell) else {
            return false
        }
        if PlaybackSongFxxTimingPlanner.isFxxTimingEffect(cell) ||
            isNonzeroSampleOffsetEffect(cell) ||
            isArpeggioEffect(cell) ||
            isPortamentoSlideEffect(cell) ||
            isTonePortamentoEffect(cell) ||
            isVibratoEffect(cell) ||
            isVibratoVolumeSlideEffect(cell) ||
            isSetFinetuneEffect(cell) ||
            isFinePortamentoUpEffect(cell) ||
            isFinePortamentoDownEffect(cell) ||
            isFineVolumeSlideEffect(cell) ||
            (isVibratoControlEffect(cell) && supportedVibratoWaveform(controlValue: Int(cell.effectParam & 0x0F)) != nil) ||
            isSupportedRetriggerEffect(cell) ||
            isNoteCutEffect(cell) ||
            isNoteDelayEffect(cell) ||
            isGlobalVolumeSlideEffect(cell) ||
            isTraversalPlanningEffect(cell) {
            return false
        }
        switch cell.effectType {
        case 0x08, 0x0A, 0x0C:
            return false
        default:
            return true
        }
    }

    private static func hasDeferredEffect(_ cell: PlaybackCell, channelState: ChannelState) -> Bool {
        if cell.effectType == 0x09, cell.effectParam == 0 {
            return channelState.sampleOffsetMemory == nil
        }
        if cell.effectType == 0x01, cell.effectParam == 0 {
            return channelState.portamentoUpMemory == nil
        }
        if cell.effectType == 0x02, cell.effectParam == 0 {
            return channelState.portamentoDownMemory == nil
        }
        if cell.effectType == 0x04 {
            let speed = Int((cell.effectParam & 0xF0) >> 4)
            let depth = Int(cell.effectParam & 0x0F)
            return (speed == 0 && channelState.vibratoSpeed == nil) ||
                (depth == 0 && channelState.vibratoDepth == nil)
        }
        if cell.effectType == 0x06 {
            return channelState.vibratoSpeed == nil || channelState.vibratoDepth == nil
        }
        return hasDeferredEffect(cell)
    }

    private static func isNonzeroSampleOffsetEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x09 && cell.effectParam != 0
    }

    private static func isArpeggioEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x00 && cell.effectParam != 0
    }

    private static func isPortamentoSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x01 || cell.effectType == 0x02
    }

    private static func isTonePortamentoEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x03
    }

    private static func isVibratoEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x04
    }

    private static func isVibratoVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x06
    }

    private static func isVibratoControlEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0E && ((cell.effectParam >> 4) & 0x0F) == 0x04
    }

    private static func isSupportedRetriggerEffect(_ cell: PlaybackCell) -> Bool {
        isRetriggerEffect(cell) && extendedEffectTick(cell) > 0
    }

    private static func isGlobalVolumeSlideEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x11
    }

    private static func isTraversalPlanningEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0B ||
            cell.effectType == 0x0D ||
            isE6xPatternLoopEffect(cell)
    }

    private static func selectSample(forNote note: UInt8, from instrument: PlaybackInstrument) -> SampleSelection {
        let mapPresent = instrument.hasNoteSampleMap
        let mappedSampleIndex = instrument.mappedSampleIndex(forNote: note)
        let mappedSample = mappedSampleIndex.flatMap { instrument.sample(mappedSampleIndex: $0) }
        let mappedSampleValid = mappedSample?.isPlayable == true
        let shouldUseMap = mapPresent && instrument.samples.count > 1
        let mapMissingOrDeferred = !mapPresent && instrument.samples.count > 1

        if shouldUseMap {
            if let mappedSample, mappedSample.isPlayable {
                return SampleSelection(
                    sample: mappedSample,
                    diagnosticSample: mappedSample,
                    skippedReason: nil,
                    sampleMapKeymapPresent: true,
                    mappedSampleIndex: mappedSampleIndex,
                    mappedSampleValid: true,
                    method: .sampleMap,
                    firstPlayableSampleFallbackUsed: false,
                    sampleMapKeymapBehaviorDeferred: false,
                    sampleMapKeymapMissingOrDeferred: false
                )
            }
            if let fallback = instrument.firstPlayableSample {
                return SampleSelection(
                    sample: fallback,
                    diagnosticSample: mappedSample ?? fallback,
                    skippedReason: nil,
                    sampleMapKeymapPresent: true,
                    mappedSampleIndex: mappedSampleIndex,
                    mappedSampleValid: mappedSampleValid,
                    method: .fallbackAfterInvalidMap,
                    firstPlayableSampleFallbackUsed: true,
                    sampleMapKeymapBehaviorDeferred: false,
                    sampleMapKeymapMissingOrDeferred: false
                )
            }
            return SampleSelection(
                sample: nil,
                diagnosticSample: mappedSample ?? instrument.samples.first,
                skippedReason: skippedReasonForInvalidMappedSample(mappedSample),
                sampleMapKeymapPresent: true,
                mappedSampleIndex: mappedSampleIndex,
                mappedSampleValid: false,
                method: .skippedNoValidSample,
                firstPlayableSampleFallbackUsed: false,
                sampleMapKeymapBehaviorDeferred: false,
                sampleMapKeymapMissingOrDeferred: false
            )
        }

        if let sample = instrument.firstPlayableSample {
            return SampleSelection(
                sample: sample,
                diagnosticSample: sample,
                skippedReason: nil,
                sampleMapKeymapPresent: mapPresent,
                mappedSampleIndex: mappedSampleIndex,
                mappedSampleValid: mappedSampleValid,
                method: .firstPlayableFallback,
                firstPlayableSampleFallbackUsed: true,
                sampleMapKeymapBehaviorDeferred: mapMissingOrDeferred,
                sampleMapKeymapMissingOrDeferred: mapMissingOrDeferred
            )
        }
        if let emptySample = instrument.samples.first(where: { $0.pcm.isEmpty }) {
            return SampleSelection(
                sample: nil,
                diagnosticSample: emptySample,
                skippedReason: .samplePCMEmpty,
                sampleMapKeymapPresent: mapPresent,
                mappedSampleIndex: mappedSampleIndex,
                mappedSampleValid: mappedSampleValid,
                method: .skippedNoValidSample,
                firstPlayableSampleFallbackUsed: false,
                sampleMapKeymapBehaviorDeferred: mapMissingOrDeferred,
                sampleMapKeymapMissingOrDeferred: mapMissingOrDeferred
            )
        }
        return SampleSelection(
            sample: nil,
            diagnosticSample: instrument.samples.first,
            skippedReason: .instrumentHasNoPlayableSample,
            sampleMapKeymapPresent: mapPresent,
            mappedSampleIndex: mappedSampleIndex,
            mappedSampleValid: mappedSampleValid,
            method: .skippedNoValidSample,
            firstPlayableSampleFallbackUsed: false,
            sampleMapKeymapBehaviorDeferred: mapMissingOrDeferred,
            sampleMapKeymapMissingOrDeferred: mapMissingOrDeferred
        )
    }

    private static func skippedReasonForInvalidMappedSample(
        _ sample: PlaybackSample?
    ) -> PlaybackSongSyntheticIgnoredCell.Reason {
        guard let sample else {
            return .noSelectedSampleForNote
        }
        if sample.pcm.isEmpty {
            return .samplePCMEmpty
        }
        return .instrumentHasNoPlayableSample
    }

    private static func ignoredCell(
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell,
        reason: PlaybackSongSyntheticIgnoredCell.Reason,
        diagnosticSample: PlaybackSample? = nil,
        sampleOffsetFrames: Int? = nil,
        sampleMapKeymapPresent: Bool = false,
        mappedSampleIndex: Int? = nil,
        mappedSampleValid: Bool = false,
        sampleSelectionMethod: PlaybackSongSyntheticSampleSelectionMethod = .skippedNoValidSample,
        firstPlayableSampleFallbackUsed: Bool = false,
        sampleMapKeymapBehaviorDeferred: Bool = false,
        sampleMapKeymapMissingOrDeferred: Bool = false,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        hasIgnoredVolumeColumn: Bool,
        hasIgnoredEffect: Bool
    ) -> PlaybackSongSyntheticIgnoredCell {
        PlaybackSongSyntheticIgnoredCell(
            source: source,
            channelIndex: channelIndex,
            note: cell.note,
            instrumentIndex: Int(cell.instrument),
            reason: reason,
            skipReason: skipReason(for: reason),
            selectedSampleIndex: diagnosticSample?.sampleIndex,
            selectedSampleLength: diagnosticSample.map(selectedSampleLength),
            selectedSampleLoopMode: diagnosticSample.map { mixerLoop(from: $0).mode },
            sampleMapKeymapPresent: sampleMapKeymapPresent,
            mappedSampleIndex: mappedSampleIndex,
            mappedSampleValid: mappedSampleValid,
            sampleSelectionMethod: sampleSelectionMethod,
            firstPlayableSampleFallbackUsed: firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: sampleMapKeymapMissingOrDeferred,
            sampleRelativeNote: diagnosticSample?.relativeNote,
            sampleFinetune: diagnosticSample?.finetune,
            sampleBaseSampleRate: diagnosticSample?.baseSampleRate,
            sampleOffsetFrames: sampleOffsetFrames,
            volumeColumn: volumeColumn,
            hasIgnoredVolumeColumn: hasIgnoredVolumeColumn,
            hasIgnoredEffect: hasIgnoredEffect
        )
    }

    private static func ignoredNoteReason(
        _ cell: PlaybackCell,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    ) -> PlaybackSongSyntheticIgnoredCell.Reason {
        switch cell.note {
        case 0:
            if cell.instrument > 0, cell.volumeColumn == 0, cell.effectType == 0, cell.effectParam == 0 {
                return .instrumentOnly
            }
            if hasDeferredEffect(cell) || volumeColumn.deferred {
                return .unsupportedDeferredEffectInteraction
            }
            return .emptyNote
        case 97:
            return .keyOff
        default:
            return .invalidNote
        }
    }

    private static func skipReason(for reason: PlaybackSongSyntheticIgnoredCell.Reason) -> PlaybackSongSyntheticSkipReason {
        switch reason {
        case .emptyNote:
            return .emptyCell
        case .instrumentOnly:
            return .instrumentOnly
        case .keyOff:
            return .noteOffKeyOffOnly
        case .invalidNote:
            return .invalidNote
        case .missingInstrument:
            return .missingInstrument
        case .unknownInstrument:
            return .unknownInstrument
        case .instrumentHasNoPlayableSample:
            return .instrumentHasNoPlayableSample
        case .samplePCMEmpty:
            return .samplePCMEmpty
        case .sampleOffsetOutOfRange:
            return .sampleOffsetOutOfRange
        case .noteDelayOutOfRow,
             .noteDelayWithoutNote:
            return .unsupportedDeferredEffectInteraction
        case .noSelectedSampleForNote:
            return .noSelectedSampleForNote
        case .unsupportedDeferredEffectInteraction:
            return .unsupportedDeferredEffectInteraction
        case .unknown:
            return .unknown
        }
    }

    private static func mixerLoop(from sample: PlaybackSample) -> MixerSampleLoop {
        let region = sample.loopRegion
        guard region.isEnabled else {
            return .none
        }
        switch region.loopType {
        case 1:
            return MixerSampleLoop(mode: .forward, startFrame: region.startFrame, endFrame: region.endFrame)
        case 2:
            return MixerSampleLoop(mode: .pingPong, startFrame: region.startFrame, endFrame: region.endFrame)
        default:
            return .none
        }
    }
}
