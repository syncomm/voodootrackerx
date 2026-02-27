import XCTest

private enum TestPatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
}

private enum TestPatternCursorField: Int {
    case note
    case instrument
    case volume
    case effectType
    case effectParam
}

private struct TestPatternCursor: Equatable {
    var row: Int
    var channel: Int
    var field: TestPatternCursorField

    mutating func move(_ command: TestPatternNavigationCommand, rowCount: Int, channelCount: Int, pageStep: Int = 16) {
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
            if let previousField = TestPatternCursorField(rawValue: field.rawValue - 1) {
                field = previousField
            } else if channel > 0 {
                channel -= 1
                field = .effectParam
            }
        case .right:
            if let nextField = TestPatternCursorField(rawValue: field.rawValue + 1) {
                field = nextField
            } else if channel < channelCount - 1 {
                channel += 1
                field = .note
            }
        }
    }
}

private enum TestPatternEditInput {
    case clearField
    case hexDigit(UInt8)
}

private struct TestXMPatternEventCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

private enum TestPatternEditEngine {
    static func hexNibble(from character: Character) -> UInt8? {
        guard let scalar = String(character).unicodeScalars.first else {
            return nil
        }
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...70:
            return UInt8(scalar.value - 55)
        case 97...102:
            return UInt8(scalar.value - 87)
        default:
            return nil
        }
    }

    static func apply(
        input: TestPatternEditInput,
        to cell: TestXMPatternEventCell,
        field: TestPatternCursorField,
        editModeEnabled: Bool
    ) -> TestXMPatternEventCell? {
        guard editModeEnabled else {
            return nil
        }
        switch input {
        case .clearField:
            switch field {
            case .note:
                return TestXMPatternEventCell(note: 0, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            case .instrument:
                return TestXMPatternEventCell(note: cell.note, instrument: 0, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            case .volume:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: 0, effectType: cell.effectType, effectParam: cell.effectParam)
            case .effectType:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: 0, effectParam: cell.effectParam)
            case .effectParam:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: 0)
            }
        case let .hexDigit(nibble):
            guard nibble <= 0x0F else {
                return nil
            }
            switch field {
            case .note:
                return nil
            case .instrument:
                let value = ((cell.instrument & 0x0F) << 4) | nibble
                return TestXMPatternEventCell(note: cell.note, instrument: value, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            case .volume:
                let value = ((cell.volumeColumn & 0x0F) << 4) | nibble
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: value, effectType: cell.effectType, effectParam: cell.effectParam)
            case .effectType:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: nibble, effectParam: cell.effectParam)
            case .effectParam:
                let value = ((cell.effectParam & 0x0F) << 4) | nibble
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: value)
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
        var cursor = TestPatternCursor(row: 10, channel: 0, field: .note)
        cursor.move(.left, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 0, field: .note))

        cursor = TestPatternCursor(row: 10, channel: 0, field: .effectParam)
        cursor.move(.right, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 1, field: .note))

        cursor = TestPatternCursor(row: 10, channel: 3, field: .note)
        cursor.move(.left, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 2, field: .effectParam))

        cursor = TestPatternCursor(row: 10, channel: 3, field: .effectParam)
        cursor.move(.right, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 3, field: .effectParam))
    }

    func testEditEngineClearFieldByCursorField() {
        let source = TestXMPatternEventCell(note: 24, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)

        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .note, editModeEnabled: true),
            TestXMPatternEventCell(note: 0, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)
        )
        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .instrument, editModeEnabled: true),
            TestXMPatternEventCell(note: 24, instrument: 0x00, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)
        )
        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .effectParam, editModeEnabled: true),
            TestXMPatternEventCell(note: 24, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x00)
        )
    }

    func testEditEngineHexEntryRulesAndBounds() {
        var cell = TestXMPatternEventCell(note: 0, instrument: 0x00, volumeColumn: 0x00, effectType: 0x00, effectParam: 0x00)
        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0A), to: cell, field: .instrument, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.instrument, 0x0A)
        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0B), to: cell, field: .instrument, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.instrument, 0xAB)

        cell = TestPatternEditEngine.apply(input: .hexDigit(0x05), to: cell, field: .effectType, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.effectType, 0x05)

        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0C), to: cell, field: .effectParam, editModeEnabled: true) ?? cell
        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0D), to: cell, field: .effectParam, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.effectParam, 0xCD)

        XCTAssertNil(TestPatternEditEngine.apply(input: .hexDigit(0x0A), to: cell, field: .note, editModeEnabled: true))
        XCTAssertNil(TestPatternEditEngine.apply(input: .hexDigit(0x1F), to: cell, field: .effectParam, editModeEnabled: true))
        XCTAssertEqual(TestPatternEditEngine.hexNibble(from: "A"), 0x0A)
        XCTAssertEqual(TestPatternEditEngine.hexNibble(from: "f"), 0x0F)
        XCTAssertNil(TestPatternEditEngine.hexNibble(from: "G"))
    }

    func testEditEngineRespectsEditModeGating() {
        let source = TestXMPatternEventCell(note: 10, instrument: 0x12, volumeColumn: 0x34, effectType: 0x05, effectParam: 0x67)
        XCTAssertNil(TestPatternEditEngine.apply(input: .clearField, to: source, field: .instrument, editModeEnabled: false))
        XCTAssertNil(TestPatternEditEngine.apply(input: .hexDigit(0x0A), to: source, field: .effectParam, editModeEnabled: false))
    }
}
