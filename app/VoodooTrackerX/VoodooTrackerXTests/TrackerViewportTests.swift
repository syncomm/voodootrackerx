import AppKit
import AudioToolbox
import XCTest

final class TrackerViewportTests: XCTestCase {
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

    func testCursorVerticalNavigationWrapsAtPatternBounds() {
        var cursor = TestPatternCursor(row: 0, channel: 1, field: .note)
        cursor.move(.up, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor.row, 63)

        cursor.move(.down, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor.row, 0)
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

    func testEditableBlankDocumentTabMovesToNextChannelNoteField() {
        let document = BlankTrackerDocument.makeDefault()
        let beforeDocument = document
        var cursor = PatternCursor(row: 12, channel: 0, field: .note)

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)

        XCTAssertEqual(cursor, PatternCursor(row: 12, channel: 1, field: .note))
        XCTAssertEqual(document.currentPosition, beforeDocument.currentPosition)
        XCTAssertEqual(document.currentPatternIndex, beforeDocument.currentPatternIndex)
        XCTAssertEqual(document.orderTable, beforeDocument.orderTable)
        XCTAssertEqual(document, beforeDocument)
    }

    func testTabFromFinalChannelWrapsToFirstChannelNoteField() {
        let document = BlankTrackerDocument.makeDefault()
        let finalChannel = document.pattern.channels - 1
        var cursor = PatternCursor(row: 37, channel: finalChannel, field: .effectParam)

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)

        XCTAssertEqual(cursor, PatternCursor(row: 37, channel: 0, field: .note))
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.orderTable, [0])
    }

    func testShiftTabMovesToPreviousChannelNoteFieldAndWraps() {
        let document = BlankTrackerDocument.makeDefault()
        var cursor = PatternCursor(row: 8, channel: 0, field: .volume)

        cursor.move(.previousChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)
        XCTAssertEqual(cursor, PatternCursor(row: 8, channel: document.pattern.channels - 1, field: .note))

        cursor.move(.previousChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)
        XCTAssertEqual(cursor, PatternCursor(row: 8, channel: document.pattern.channels - 2, field: .note))
    }

    @MainActor
    func testTabKeyDownRoutesNavigationWithoutEditInputOrTextInsertion() {
        let textView = PatternTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        textView.string = "    ... .. .. ..."
        var commands = [PatternNavigationCommand]()
        var editInputCount = 0
        textView.navigationHandler = { commands.append($0) }
        textView.editInputHandler = { _ in
            editInputCount += 1
            return true
        }

        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 48, characters: "\t"))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 48, characters: "\t", modifierFlags: .shift))

        XCTAssertEqual(commands, [.nextChannelNote, .previousChannelNote])
        XCTAssertEqual(editInputCount, 0)
        XCTAssertEqual(textView.string, "    ... .. .. ...")
    }

    @MainActor
    func testMutationKeyDownRoutesRepeatAwareEditInputsWithoutTextInsertion() {
        let textView = PatternTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        textView.string = "    ... .. .. ..."
        var inputs = [PatternEditInput]()
        textView.editInputHandler = { input in
            inputs.append(input)
            return true
        }

        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 6, characters: "z"))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 6, characters: "z", isARepeat: true))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 50, characters: "`"))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 50, characters: "`", isARepeat: true))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 51, characters: "\u{8}"))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 51, characters: "\u{8}", isARepeat: true))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 117, characters: "\u{7F}"))
        textView.keyDown(with: makeTrackerKeyDownEvent(keyCode: 117, characters: "\u{7F}", isARepeat: true))

        XCTAssertEqual(inputs, [
            .noteKey("z", isRepeat: false),
            .noteKey("z", isRepeat: true),
            .keyOff,
            .repeatedKeyOff,
            .clearField,
            .repeatedClearField,
            .clearField,
            .repeatedClearField,
        ])
        XCTAssertEqual(textView.string, "    ... .. .. ...")
    }

    func testViewportDefinesStaticAnchorRowNearViewportMiddle() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)

        XCTAssertEqual(metrics.visibleRowCount, 19)
        XCTAssertEqual(state.anchorRowIndex, 9)
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 0)
    }

    func testViewportUsesOneSharedSlotListForGutterAndPatternBody() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 12, rowCount: 64, metrics: metrics)
        let layout = TestPatternViewportTextLayout(state: state)

        XCTAssertEqual(layout.slotRows, state.slotRows)
        XCTAssertEqual(layout.slotRows[state.anchorRowIndex], 12)
    }

    func testViewportLeavesBlankSlotsAboveRowZeroOnInitialLoad() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)

        XCTAssertEqual(Array(state.slotRows.prefix(state.anchorRowIndex)), Array(repeating: nil, count: state.anchorRowIndex))
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 0)
    }

    func testViewportContentHeightUsesVisibleSlotCount() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)

        XCTAssertEqual(state.visibleRowCount, 19)
        XCTAssertEqual(metrics.contentHeight(forRenderedRowCount: state.visibleRowCount, insetHeight: 2), 329)
    }

    func testDownFromLastRowWrapsRowZeroIntoAnchorSlot() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        var cursor = TestPatternCursor(row: 63, channel: 0, field: .note)

        cursor.move(.down, rowCount: 64, channelCount: 4)
        let state = TestPatternViewportState(currentRow: cursor.row, rowCount: 64, metrics: metrics)

        XCTAssertEqual(cursor.row, 0)
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 0)
        XCTAssertEqual(Array(state.slotRows.prefix(state.anchorRowIndex)), Array(repeating: nil, count: state.anchorRowIndex))
    }

    func testUpFromRowZeroWrapsLastRowIntoAnchorSlot() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        var cursor = TestPatternCursor(row: 0, channel: 0, field: .note)

        cursor.move(.up, rowCount: 64, channelCount: 4)
        let state = TestPatternViewportState(currentRow: cursor.row, rowCount: 64, metrics: metrics)

        XCTAssertEqual(cursor.row, 63)
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 63)
        XCTAssertEqual(Array(state.slotRows.suffix(state.visibleRowCount - state.anchorRowIndex - 1)), Array(repeating: nil, count: state.visibleRowCount - state.anchorRowIndex - 1))
    }

    func testBlankSlotsRemainBlankInBothGutterAndBodyAtPatternBottom() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 63, rowCount: 64, metrics: metrics)
        let layout = TestPatternViewportTextLayout(state: state)

        let blankTailCount = state.visibleRowCount - state.anchorRowIndex - 1
        XCTAssertEqual(Array(layout.slotRows.suffix(blankTailCount)), Array(repeating: nil, count: blankTailCount))
    }

    func testRenderedTextReservesBlankRowPrefixForPinnedGutter() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)
        let layout = TestPatternViewportTextLayout(state: state)

        XCTAssertEqual(layout.renderedLines[state.anchorRowIndex], "    CELL")
        XCTAssertEqual(layout.renderedLines[state.anchorRowIndex - 1], "    CELL")
    }

    func testPinnedGutterUsesSameSlotYAsBodyRows() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 12, rowCount: 64, metrics: metrics)
        let anchorSlot = state.anchorRowIndex

        let gutterY = TestTrackerChromeGeometry.pinnedGutterRowMinY(bodyMinY: 0, insetHeight: 2, slotIndex: anchorSlot, rowHeight: state.rowHeight)
        let bodyY = TestTrackerChromeGeometry.bodyRowMinY(bodyMinY: 0, insetHeight: 2, slotIndex: anchorSlot, rowHeight: state.rowHeight)

        XCTAssertEqual(state.slotRows[anchorSlot], 12)
        XCTAssertEqual(gutterY, bodyY)
    }

    func testPinnedGutterLeavesClearanceBeforeGridBoundary() {
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 36, rowNumberWidth: 16), 18)
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 4, rowNumberWidth: 16), 0)
    }

    func testPinnedGutterPrefersTwoDigitColumnWidthOverHiddenRowPrefixWidth() {
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 80, rowNumberWidth: 16), 18)
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 12, rowNumberWidth: 16), 8)
    }

    func testHorizontalCursorVisibilityAccountsForPinnedGutterObstruction() {
        let targetOriginX = TestTrackerChromeGeometry.targetOriginXForCursorVisibility(
            visibleMinX: 40,
            visibleMaxX: 240,
            leftObstructionWidth: 18,
            targetMinX: 50,
            targetMaxX: 70,
            maxOriginX: 400
        )

        XCTAssertEqual(targetOriginX, 32)
    }

    func testResizeKeepsLastStableHorizontalViewportOriginWhenPossible() {
        let originX = TestTrackerViewportScrollGeometry.clampedHorizontalOrigin(
            preferredOriginX: 120,
            contentWidth: 480,
            viewportWidth: 240
        )

        XCTAssertEqual(originX, 120)
    }

    func testResizeClampsLastStableHorizontalViewportOriginWhenViewportWidens() {
        let originX = TestTrackerViewportScrollGeometry.clampedHorizontalOrigin(
            preferredOriginX: 300,
            contentWidth: 480,
            viewportWidth: 320
        )

        XCTAssertEqual(originX, 160)
    }

    func testResizeDoesNotReplaceStableHorizontalOriginDuringLiveResize() {
        XCTAssertFalse(TestTrackerViewportResizeBehavior.shouldCaptureStableHorizontalOrigin(isLiveResize: true))
        XCTAssertTrue(TestTrackerViewportResizeBehavior.shouldCaptureStableHorizontalOrigin(isLiveResize: false))
    }

    func testResizeRerenderDoesNotRevealCursorHorizontally() {
        XCTAssertFalse(TestTrackerViewportResizeBehavior.shouldRevealCursorHorizontally(isViewportResizeRerender: true))
        XCTAssertTrue(TestTrackerViewportResizeBehavior.shouldRevealCursorHorizontally(isViewportResizeRerender: false))
    }

    func testFieldCursorSurvivesRowNavigation() {
        var cursor = TestPatternCursor(row: 10, channel: 2, field: .effectParam)

        cursor.move(.down, rowCount: 64, channelCount: 8)
        XCTAssertEqual(cursor, TestPatternCursor(row: 11, channel: 2, field: .effectParam))

        cursor.move(.up, rowCount: 64, channelCount: 8)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 2, field: .effectParam))
    }

    func testEditStepAdvanceClampsAtFinalRowWithoutNavigationWrap() {
        XCTAssertEqual(TrackerEditStep.advancedRow(after: 62, rowCount: 64), 63)
        XCTAssertEqual(TrackerEditStep.advancedRow(after: 63, rowCount: 64), 63)
        XCTAssertEqual(TrackerEditStep.advancedRow(after: -1, rowCount: 64), 1)
        XCTAssertEqual(TrackerEditStep.advancedRow(after: 12, rowCount: 0), 0)
    }

    func testCursorOutlineGeometryExpandsFieldRectAndReservesVisibleBounds() {
        let fieldRect = CGRect(x: 100, y: 8, width: 18, height: 15)
        let strokeRect = PatternCursorOutlineGeometry.strokeRect(for: fieldRect)
        let clipRect = PatternCursorOutlineGeometry.minimumVisibleBounds(for: CGRect(x: 0, y: 0, width: 320, height: 200))

        XCTAssertEqual(strokeRect, CGRect(x: 98, y: 6, width: 22, height: 19))
        XCTAssertEqual(clipRect, CGRect(x: 0, y: 2, width: 318, height: 196))
        XCTAssertTrue(clipRect.contains(CGPoint(x: strokeRect.minX, y: strokeRect.minY)))
    }

    func testEditEngineClearFieldByCursorField() {
        let source = TestXMPatternEventCell(note: 24, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)

        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .note, editModeEnabled: true),
            TestXMPatternEventCell(note: 0, instrument: 0x00, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)
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

    func testEditEngineKeyOffAppliesOnlyToNoteField() {
        let source = TestXMPatternEventCell(note: 24, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)

        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .keyOff, to: source, field: .note, editModeEnabled: true),
            TestXMPatternEventCell(note: TrackerNoteKeyMap.keyOffNoteValue, instrument: 0x00, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)
        )
        XCTAssertNil(TestPatternEditEngine.apply(input: .keyOff, to: source, field: .instrument, editModeEnabled: true))
        XCTAssertNil(TestPatternEditEngine.apply(input: .keyOff, to: source, field: .note, editModeEnabled: false))
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

    func testXMEffectDisplayKeepsClassicLowCommandLetters() {
        XCTAssertEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0x00, effectParam: 0x01), "001")
        XCTAssertEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0x0F, effectParam: 0x00), "F00")
        XCTAssertEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0x0E, effectParam: 0x9C), "E9C")
    }

    func testXMEffectDisplayMapsRecognizedHighCommandBytesToClassicLetters() {
        XCTAssertEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0x10, effectParam: 0x40), "G40")
        XCTAssertEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0x11, effectParam: 0x01), "H01")
        XCTAssertNotEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0x11, effectParam: 0x01), "1101")
    }

    func testXMEffectDisplayFieldWidthStaysStableForHighAndUnknownCommands() {
        let fields = [
            XMEffectCommandDisplay.formatEffectField(effectType: 0x00, effectParam: 0x00),
            XMEffectCommandDisplay.formatEffectField(effectType: 0x0F, effectParam: 0x00),
            XMEffectCommandDisplay.formatEffectField(effectType: 0x11, effectParam: 0x01),
            XMEffectCommandDisplay.formatEffectField(effectType: 0xFE, effectParam: 0x7A),
        ]

        XCTAssertEqual(XMEffectCommandDisplay.formatEffectField(effectType: 0xFE, effectParam: 0x7A), "?7A")
        for field in fields {
            XCTAssertEqual(field.utf16.count, XMEffectCommandDisplay.fieldWidth, field)
        }
    }

    func testSpacebarShortcutDoesNotMapToPatternEditInput() {
        XCTAssertTrue(TrackerTransportShortcut.isPlainSpacebarToggle(
            keyCode: TrackerTransportShortcut.spacebarKeyCode,
            charactersIgnoringModifiers: " ",
            hasCommandModifier: false,
            hasOptionModifier: false,
            hasControlModifier: false
        ))
        XCTAssertNil(TestPatternEditEngine.hexNibble(from: " "))
    }

    func testTrackerNoteKeyMappingUsesXMNoteValues() {
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("z"))
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("C"))
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("s"))
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("J"))
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("q"))
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("2"))
        XCTAssertTrue(TrackerNoteKeyMap.isTrackerNoteKey("U"))
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "z", octave: 4), 49)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "s", octave: 4), 50)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "x", octave: 4), 51)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "j", octave: 4), 59)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "m", octave: 7), 96)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "q", octave: 4), 61)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "2", octave: 4), 62)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "u", octave: 4), 72)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "q", octave: 7), 85)
        XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: "u", octave: 7), 96)
        XCTAssertNil(TrackerNoteKeyMap.noteValue(forTrackerKey: "z", octave: 8))
    }

    func testTrackerNoteKeyMappingDoesNotIncludeHighCKeys() {
        XCTAssertFalse(TrackerNoteKeyMap.isTrackerNoteKey("i"))
        XCTAssertFalse(TrackerNoteKeyMap.isTrackerNoteKey(","))
        XCTAssertFalse(TrackerNoteKeyMap.isTrackerNoteKey("."))
        XCTAssertFalse(TrackerNoteKeyMap.isTrackerNoteKey("/"))
        XCTAssertNil(TrackerNoteKeyMap.noteValue(forTrackerKey: "i", octave: 4))
        XCTAssertNil(TrackerNoteKeyMap.noteValue(forTrackerKey: ",", octave: 4))
        XCTAssertNil(TrackerNoteKeyMap.noteValue(forTrackerKey: ".", octave: 4))
        XCTAssertNil(TrackerNoteKeyMap.noteValue(forTrackerKey: "/", octave: 4))
    }

    func testTrackerKeyOffBindingUsesBacktickAndDoesNotOverlapNoteKeys() {
        XCTAssertEqual(TrackerNoteKeyMap.keyOffKey, "`")
        XCTAssertTrue(TrackerNoteKeyMap.isKeyOffKey("`"))
        XCTAssertFalse(TrackerNoteKeyMap.isTrackerNoteKey("`"))
    }

    func testTrackerTransportShortcutMatchesPlainSpacebarOnly() {
        XCTAssertTrue(TrackerTransportShortcut.isPlainSpacebarToggle(
            keyCode: 49,
            charactersIgnoringModifiers: " ",
            hasCommandModifier: false,
            hasOptionModifier: false,
            hasControlModifier: false
        ))
        XCTAssertFalse(TrackerTransportShortcut.isPlainSpacebarToggle(
            keyCode: 49,
            charactersIgnoringModifiers: " ",
            hasCommandModifier: true,
            hasOptionModifier: false,
            hasControlModifier: false
        ))
        XCTAssertFalse(TrackerTransportShortcut.isPlainSpacebarToggle(
            keyCode: 36,
            charactersIgnoringModifiers: "\r",
            hasCommandModifier: false,
            hasOptionModifier: false,
            hasControlModifier: false
        ))
    }

    func testSongPositionDrivesDisplayedPatternSelection() {
        XCTAssertEqual(displayedPatternIndex(orderTable: [3, 7, 3, 9], songLength: 4, songPosition: 0), 3)
        XCTAssertEqual(displayedPatternIndex(orderTable: [3, 7, 3, 9], songLength: 4, songPosition: 1), 7)
        XCTAssertEqual(displayedPatternIndex(orderTable: [3, 7, 3, 9], songLength: 4, songPosition: 3), 9)
    }

    func testSongPositionClampsToSongLengthBounds() {
        XCTAssertEqual(displayedPatternIndex(orderTable: [1, 4, 6], songLength: 3, songPosition: -1), 1)
        XCTAssertEqual(displayedPatternIndex(orderTable: [1, 4, 6], songLength: 3, songPosition: 99), 6)
    }

}

private func makeTrackerKeyDownEvent(
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags = [],
    isARepeat: Bool = false
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: isARepeat,
        keyCode: keyCode
    )!
}
