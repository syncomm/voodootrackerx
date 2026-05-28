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

