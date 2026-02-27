import XCTest

private enum PatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
}

private enum PatternCursorField: Int {
    case note
    case instrument
    case volume
    case effectType
    case effectParam
}

private struct PatternCursor: Equatable {
    var row: Int
    var channel: Int
    var field: PatternCursorField

    mutating func move(_ command: PatternNavigationCommand, rowCount: Int, channelCount: Int, pageStep: Int = 16) {
        row = min(max(0, row), max(0, rowCount - 1))
        channel = min(max(0, channel), max(0, channelCount - 1))

        switch command {
        case .up:
            row = max(0, row - 1)
        case .down:
            row = min(max(0, rowCount - 1), row + 1)
        case .pageUp:
            row = max(0, row - pageStep)
        case .pageDown:
            row = min(max(0, rowCount - 1), row + pageStep)
        case .home:
            row = 0
        case .end:
            row = max(0, rowCount - 1)
        case .left:
            if let previousField = PatternCursorField(rawValue: field.rawValue - 1) {
                field = previousField
            } else if channel > 0 {
                channel -= 1
                field = .effectParam
            }
        case .right:
            if let nextField = PatternCursorField(rawValue: field.rawValue + 1) {
                field = nextField
            } else if channel < channelCount - 1 {
                channel += 1
                field = .note
            }
        }
    }
}

private struct PatternSelectionEntry: Equatable {
    let patternIndex: Int
    let isUsed: Bool
    let rowCount: Int
}

private func buildPatternSelection(
    orderTable: [Int],
    patternCount: Int,
    rowCounts: [Int],
    showAllPatterns: Bool
) -> (entries: [PatternSelectionEntry], invalidReferencedPatterns: [Int]) {
    let safePatternCount = max(0, patternCount)
    var usedUnique = [Int]()
    var usedSeen = Set<Int>()
    var invalidReferenced = [Int]()

    for patternIndex in orderTable {
        if patternIndex >= 0 && patternIndex < safePatternCount {
            if !usedSeen.contains(patternIndex) {
                usedSeen.insert(patternIndex)
                usedUnique.append(patternIndex)
            }
        } else {
            invalidReferenced.append(patternIndex)
        }
    }

    var entries = [PatternSelectionEntry]()
    if showAllPatterns {
        for patternIndex in 0..<safePatternCount {
            let rowCount = patternIndex < rowCounts.count ? max(1, rowCounts[patternIndex]) : 64
            entries.append(
                PatternSelectionEntry(
                    patternIndex: patternIndex,
                    isUsed: usedSeen.contains(patternIndex),
                    rowCount: rowCount
                )
            )
        }
    } else {
        for patternIndex in usedUnique.sorted() {
            let rowCount = patternIndex < rowCounts.count ? max(1, rowCounts[patternIndex]) : 64
            entries.append(
                PatternSelectionEntry(
                    patternIndex: patternIndex,
                    isUsed: true,
                    rowCount: rowCount
                )
            )
        }
        if entries.isEmpty && safePatternCount > 0 {
            let rowCount = rowCounts.isEmpty ? 64 : max(1, rowCounts[0])
            entries.append(PatternSelectionEntry(patternIndex: 0, isUsed: false, rowCount: rowCount))
        }
    }
    return (entries, invalidReferenced)
}

final class VoodooTrackerXTests: XCTestCase {
    func testExamplePasses() {
        XCTAssertTrue(true)
    }

    func testUsedPatternsSelectionDeduplicatesByOrderAndTracksInvalidReferences() {
        let result = buildPatternSelection(
            orderTable: [0, 2, 2, 5, 1, 0],
            patternCount: 4,
            rowCounts: [64, 32, 48, 16],
            showAllPatterns: false
        )

        XCTAssertEqual(result.entries.map(\.patternIndex), [0, 1, 2])
        XCTAssertEqual(result.entries.map(\.isUsed), [true, true, true])
        XCTAssertEqual(result.invalidReferencedPatterns, [5])
    }

    func testShowAllPatternsIncludesUnusedPatterns() {
        let result = buildPatternSelection(
            orderTable: [2, 2, 0],
            patternCount: 4,
            rowCounts: [64, 32, 48, 16],
            showAllPatterns: true
        )

        XCTAssertEqual(result.entries.map(\.patternIndex), [0, 1, 2, 3])
        XCTAssertEqual(result.entries.map(\.isUsed), [true, false, true, false])
    }

    func testCursorHorizontalFieldWrappingAcrossChannelsAndBounds() {
        var cursor = PatternCursor(row: 10, channel: 0, field: .note)
        cursor.move(.left, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, PatternCursor(row: 10, channel: 0, field: .note))

        cursor = PatternCursor(row: 10, channel: 0, field: .effectParam)
        cursor.move(.right, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, PatternCursor(row: 10, channel: 1, field: .note))

        cursor = PatternCursor(row: 10, channel: 3, field: .note)
        cursor.move(.left, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, PatternCursor(row: 10, channel: 2, field: .effectParam))

        cursor = PatternCursor(row: 10, channel: 3, field: .effectParam)
        cursor.move(.right, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, PatternCursor(row: 10, channel: 3, field: .effectParam))
    }
}
