import AppKit
import XCTest

@MainActor
final class SongOrderEditorWindowControllerTests: XCTestCase {
    func testWindowControllerCreatesFloatingFixedSizeUtilityPanel() throws {
        let controller = SongOrderEditorWindowController()
        let window = try XCTUnwrap(controller.window)
        let panel = try XCTUnwrap(window as? NSPanel)
        let contentView = try XCTUnwrap(window.contentView)

        XCTAssertEqual(window.title, "Song / Order")
        XCTAssertTrue(window.styleMask.contains(.utilityWindow))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, SongOrderEditorWindowController.contentSize)
        XCTAssertEqual(window.contentMaxSize, SongOrderEditorWindowController.contentSize)
        XCTAssertEqual(contentView.frame.size.width, SongOrderEditorWindowController.contentSize.width, accuracy: 0.001)
        XCTAssertEqual(contentView.frame.size.height, SongOrderEditorWindowController.contentSize.height, accuracy: 0.001)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testShellContainsExpectedMajorPanelGroups() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let identifiers = Set(contentView.allDescendants.compactMap { $0.identifier?.rawValue })

        XCTAssertTrue(identifiers.contains(SongOrderEditorViewIdentifier.contentView))
        XCTAssertTrue(identifiers.contains(SongOrderEditorViewIdentifier.orderListPanel))
        XCTAssertTrue(identifiers.contains(SongOrderEditorViewIdentifier.patternBankPanel))
        XCTAssertTrue(identifiers.contains(SongOrderEditorViewIdentifier.patternOpsPanel))
        XCTAssertTrue(identifiers.contains(SongOrderEditorViewIdentifier.orderOpsPanel))
        XCTAssertTrue(identifiers.contains(SongOrderEditorViewIdentifier.dangerPanel))
    }

    func testShellUsesEditorPrimitivesForReadoutsLEDsAndButtons() throws {
        let controller = SongOrderEditorWindowController(
            displayState: SongOrderEditorDisplayState.editableDocument(BlankTrackerDocument.makeDefault())
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let segmentValues = contentView.allDescendants
            .compactMap { ($0 as? VTXEditorSegmentReadout)?.stringValue }

        XCTAssertTrue(segmentValues.contains("BANK 1/1"))
        XCTAssertGreaterThanOrEqual(contentView.allDescendants.compactMap { $0 as? VTXEditorIndicatorLEDView }.count, 2)
        XCTAssertGreaterThanOrEqual(contentView.allDescendants.compactMap { $0 as? VTXEditorButton }.count, 10)
    }

    func testShellControlsAreVisuallyBrightButActionless() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        let buttons = contentView.allDescendants.compactMap { $0 as? VTXEditorButton }
        let bankNavigationTitles = Set(["◀", "▶"])
        let bankNavigationButtons = buttons.filter { bankNavigationTitles.contains($0.title) }
        let mutationButtons = buttons.filter { !bankNavigationTitles.contains($0.title) }

        XCTAssertGreaterThanOrEqual(buttons.count, 10)
        XCTAssertTrue(buttons.allSatisfy(\.isEnabled))
        XCTAssertEqual(bankNavigationButtons.count, 2)
        XCTAssertTrue(bankNavigationButtons.allSatisfy { ($0.target as? SongOrderEditorContentView) === contentView })
        XCTAssertTrue(bankNavigationButtons.allSatisfy { $0.action != nil })
        XCTAssertTrue(mutationButtons.allSatisfy { $0.target == nil })
        XCTAssertTrue(mutationButtons.allSatisfy { $0.action == nil })
    }

    func testShellIncludesMockupButtonTitlesAndClarifiedStaticText() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let buttonTitles = Set(contentView.allDescendants.compactMap { ($0 as? NSButton)?.title })
        let fieldValues = Set(contentView.allDescendants.compactMap { ($0 as? NSTextField)?.stringValue })

        for title in [
            "+ NEW",
            "⧉ DUP",
            "⌫ CLEAR",
            "+ INSERT",
            "⌫ DELETE",
            "▲ MOVE UP",
            "▼ MOVE DOWN",
            "⌫ CLEAR SONG",
        ] {
            XCTAssertTrue(buttonTitles.contains(title), "Missing \(title)")
        }

        XCTAssertTrue(fieldValues.contains("BANK 1/1"))
        XCTAssertTrue(fieldValues.contains("— the song sequence"))
        XCTAssertTrue(fieldValues.contains("— no selected slot"))
        XCTAssertTrue(fieldValues.contains("Clears arrangement / order data. Instruments and samples are preserved."))
        XCTAssertFalse(fieldValues.contains("DANGER"))
    }

    func testShellDoesNotAddDuplicateTransportControls() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let buttonTitles = contentView.allDescendants
            .compactMap { ($0 as? NSButton)?.title.uppercased() }

        XCTAssertFalse(buttonTitles.contains("PLAY"))
        XCTAssertFalse(buttonTitles.contains("STOP"))
        XCTAssertFalse(buttonTitles.contains("LOOP"))
        XCTAssertFalse(buttonTitles.contains("PLAY PATTERN"))
        XCTAssertFalse(buttonTitles.contains("PLAY SONG"))
    }

    func testShowingClosingAndReopeningShellDoesNotMutateBlankDocumentState() throws {
        let document = BlankTrackerDocument.makeDefault()
        let before = document
        let controller = SongOrderEditorWindowController()
        let window = try XCTUnwrap(controller.window)

        controller.showWindowAndActivate()
        XCTAssertEqual(document, before)
        XCTAssertTrue(window.isVisible)

        window.close()
        XCTAssertFalse(window.isVisible)
        XCTAssertNotNil(controller.window)

        controller.showWindowAndActivate()
        XCTAssertEqual(document, before)
        XCTAssertTrue(window.isVisible)

        window.close()
    }

    func testRefreshPolicyAllowsOnlyVisibleIdleEditorRefresh() {
        XCTAssertTrue(SongOrderEditorRefreshPolicy.shouldRefresh(isWindowVisible: true, isPlaybackActive: false))
        XCTAssertFalse(SongOrderEditorRefreshPolicy.shouldRefresh(isWindowVisible: false, isPlaybackActive: false))
        XCTAssertFalse(SongOrderEditorRefreshPolicy.shouldRefresh(isWindowVisible: true, isPlaybackActive: true))
        XCTAssertFalse(SongOrderEditorRefreshPolicy.shouldRefresh(isWindowVisible: false, isPlaybackActive: true))
    }

    func testClosedControllerSkipsDocumentAndPlaybackLikeRefreshWork() throws {
        let metadata = makeLoadedMetadata(
            orderTable: (0..<96).map { min($0, 64) },
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
            ],
            patternCount: 65
        )
        let initialState = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        )
        let documentState = SongOrderEditorDisplayState.editableDocument(BlankTrackerDocument.makeDefault())
        let playbackPositionState = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 64,
            currentPatternIndex: 64
        )
        let controller = SongOrderEditorWindowController(displayState: initialState)
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var closeCount = 0
        controller.closeHandler = {
            closeCount += 1
        }

        controller.showWindowAndActivate()
        XCTAssertTrue(controller.isVisibleForRefresh)

        controller.window?.close()
        XCTAssertFalse(controller.isVisibleForRefresh)
        XCTAssertEqual(closeCount, 1)

        let rebuildCount = contentView.rebuildCount
        let scrollCount = contentView.selectedOrderScrollCount

        XCTAssertFalse(controller.applyIfVisible(displayState: documentState))
        XCTAssertFalse(controller.applyIfVisible(displayState: playbackPositionState))
        XCTAssertEqual(contentView.displayState, initialState)
        XCTAssertEqual(contentView.rebuildCount, rebuildCount)
        XCTAssertEqual(contentView.selectedOrderScrollCount, scrollCount)
    }

    func testLoadedModuleDisplayStateUsesRealOrderRowsAndRowCounts() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 2, 5, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 64),
                makePattern(index: 2, rowCount: 32),
            ]
        )

        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: 2
        )

        XCTAssertEqual(state.orderRows.map(\.orderPosition), [0, 1, 2, 3])
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 2, 5, 1])
        XCTAssertEqual(state.orderRows.map(\.rowCount), [16, 32, nil, 64])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, true, false, false])
        XCTAssertEqual(state.orderRows[2].rowCountDisplay, "--")
    }

    func testBlankDocumentDisplayStateShowsSingleBlankOrderAndPattern() throws {
        let document = BlankTrackerDocument.makeDefault()
        let state = SongOrderEditorDisplayState.editableDocument(document)

        XCTAssertEqual(state.orderRows.count, 1)
        XCTAssertEqual(state.orderRows[0].orderDisplay, "000")
        XCTAssertEqual(state.orderRows[0].patternDisplay, "000")
        XCTAssertEqual(state.orderRows[0].rowCountDisplay, "064")
        XCTAssertTrue(state.orderRows[0].isSelected)

        let firstCell = try XCTUnwrap(state.patternBankCells.first)
        XCTAssertEqual(firstCell.patternIndex, 0)
        XCTAssertTrue(firstCell.exists)
        XCTAssertTrue(firstCell.isUsed)
        XCTAssertTrue(firstCell.isCurrent)
    }

    func testLoadedModuleDerivedEditableDisplayStateShowsClearedEditableSongAndPreservesPalette() throws {
        let loadedPattern = makePattern(index: 2, rowCount: 32, channels: 3)
        let metadata = makeLoadedMetadata(orderTable: [2], patterns: [loadedPattern], channels: 3)
        let instrument = PlaybackInstrument(
            index: 1,
            name: "Public Test Instrument",
            samples: [
                PlaybackSample(
                    instrumentIndex: 1,
                    sampleIndex: 0,
                    name: "Public Test Sample",
                    pcm: [0, 0.25, -0.25],
                    volume: 1,
                    relativeNote: 0,
                    finetune: 0,
                    baseSampleRate: 8_363
                )
            ]
        )
        let playbackSong = PlaybackSong(
            title: "Synthetic",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: (0..<32).map { PlaybackRow(index: $0, cells: []) })],
            instrumentsByIndex: [1: instrument],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )

        let editable = try XCTUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: playbackSong,
            selection: .default,
            sourcePatternIndex: 2
        ))
        let state = SongOrderEditorDisplayState.editableDocument(editable)

        XCTAssertEqual(editable.instrumentPalette, playbackSong.instrumentsByIndex)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0])
        XCTAssertEqual(state.orderRows.map(\.rowCount), [32])
        XCTAssertEqual(state.patternBankCells[0].exists, true)
        XCTAssertEqual(state.patternBankCells[0].isUsed, true)
        XCTAssertEqual(state.patternBankCells[0].isCurrent, true)
    }

    func testPatternBankStateMarksUsedCurrentExistingAndEmptyPatterns() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [2, 7, 2],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 2, rowCount: 32),
                makePattern(index: 7, rowCount: 64),
                makePattern(index: 9, rowCount: 8),
            ],
            patternCount: 10
        )

        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 2
        )

        XCTAssertTrue(state.patternBankCells[2].exists)
        XCTAssertTrue(state.patternBankCells[2].isUsed)
        XCTAssertTrue(state.patternBankCells[2].isCurrent)
        XCTAssertTrue(state.patternBankCells[7].exists)
        XCTAssertTrue(state.patternBankCells[7].isUsed)
        XCTAssertFalse(state.patternBankCells[7].isCurrent)
        XCTAssertTrue(state.patternBankCells[9].exists)
        XCTAssertFalse(state.patternBankCells[9].isUsed)
        XCTAssertFalse(state.patternBankCells[10].exists)
        XCTAssertFalse(state.patternBankCells[10].isUsed)
        XCTAssertFalse(state.patternBankCells[10].isCurrent)
    }

    func testPatternBankDisplayStateDerivesSixtyFourSlotBankPages() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 64, 130],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
                makePattern(index: 130, rowCount: 64),
            ],
            patternCount: 131
        )

        let firstBank = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        )
        let secondBank = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: 64
        )

        XCTAssertEqual(firstBank.totalBankCount, 3)
        XCTAssertEqual(firstBank.bankIndex, 0)
        XCTAssertEqual(firstBank.bankRangeLabel, "000-063")
        XCTAssertEqual(firstBank.bankDisplayLabel, "BANK 1/3")
        XCTAssertEqual(firstBank.patternBankCells.first?.patternIndex, 0)
        XCTAssertEqual(firstBank.patternBankCells.last?.patternIndex, 63)

        XCTAssertEqual(secondBank.totalBankCount, 3)
        XCTAssertEqual(secondBank.bankIndex, 1)
        XCTAssertEqual(secondBank.bankRangeLabel, "064-127")
        XCTAssertEqual(secondBank.bankDisplayLabel, "BANK 2/3")
        XCTAssertEqual(secondBank.patternBankCells.first?.patternIndex, 64)
        XCTAssertEqual(secondBank.patternBankCells.last?.patternIndex, 127)
    }

    func testPatternBankAutoPagesToCurrentLoadedModulePattern() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 64, 130],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
                makePattern(index: 130, rowCount: 64),
            ],
            patternCount: 131
        )

        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 2,
            currentPatternIndex: 130
        )
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 130 })

        XCTAssertEqual(state.bankIndex, 2)
        XCTAssertEqual(state.bankRangeLabel, "128-191")
        XCTAssertEqual(state.bankDisplayLabel, "BANK 3/3")
        XCTAssertTrue(currentCell.exists)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternBankAutoPagesToCurrentEditableDocumentPattern() throws {
        let document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 64,
            orderTable: [0, 64],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 48),
            ]
        )

        let state = SongOrderEditorDisplayState.editableDocument(document)
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 64 })

        XCTAssertEqual(state.bankIndex, 1)
        XCTAssertEqual(state.totalBankCount, 2)
        XCTAssertEqual(state.bankRangeLabel, "064-127")
        XCTAssertEqual(state.bankDisplayLabel, "BANK 2/2")
        XCTAssertTrue(currentCell.exists)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 64])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, true])
    }

    func testPatternBankPreviousNextNavigationChangesOnlyVisibleReadOnlyPageAndClamps() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 64, 130],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
                makePattern(index: 130, rowCount: 64),
            ],
            patternCount: 131
        )
        let before = metadata
        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: 64
        )
        let controller = SongOrderEditorWindowController(displayState: state)
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)

        try button(titled: "▶", in: contentView).performClick(nil)
        XCTAssertEqual(contentView.displayState.bankIndex, 2)
        XCTAssertEqual(contentView.displayState.bankRangeLabel, "128-191")
        XCTAssertEqual(contentView.displayState.selectedOrderPosition, state.selectedOrderPosition)
        XCTAssertEqual(contentView.displayState.selectedPatternIndex, state.selectedPatternIndex)
        XCTAssertEqual(contentView.displayState.orderRows, state.orderRows)

        try button(titled: "▶", in: contentView).performClick(nil)
        XCTAssertEqual(contentView.displayState.bankIndex, 2)

        try button(titled: "◀", in: contentView).performClick(nil)
        try button(titled: "◀", in: contentView).performClick(nil)
        XCTAssertEqual(contentView.displayState.bankIndex, 0)
        XCTAssertEqual(contentView.displayState.bankRangeLabel, "000-063")
        XCTAssertFalse(contentView.displayState.patternBankCells.contains { $0.isCurrent })

        try button(titled: "◀", in: contentView).performClick(nil)
        XCTAssertEqual(contentView.displayState.bankIndex, 0)
        XCTAssertEqual(metadata, before)
    }

    func testControllerApplyAutoPagesBackToCurrentPatternAfterManualBankNavigation() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 64],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
            ],
            patternCount: 65
        )
        let selectedPatternState = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: 64
        )
        let controller = SongOrderEditorWindowController(displayState: selectedPatternState)
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)

        try button(titled: "◀", in: contentView).performClick(nil)
        XCTAssertEqual(contentView.displayState.bankIndex, 0)
        XCTAssertFalse(contentView.displayState.patternBankCells.contains { $0.isCurrent })

        controller.apply(displayState: selectedPatternState)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 64 })

        XCTAssertEqual(contentView.displayState.bankIndex, 1)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testOrderListScrollsSelectedOrderIntoViewOnRefresh() throws {
        let metadata = makeLoadedMetadata(
            orderTable: (0..<144).map { min($0, 126) },
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
                makePattern(index: 126, rowCount: 64),
            ],
            patternCount: 127
        )
        let controller = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        let initialScrollView = try orderListScrollView(in: contentView)

        XCTAssertEqual(initialScrollView.contentView.bounds.origin.y, 0, accuracy: 0.001)

        controller.apply(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 64,
            currentPatternIndex: 64
        ))
        let refreshedScrollView = try orderListScrollView(in: contentView)

        XCTAssertGreaterThan(refreshedScrollView.contentView.bounds.origin.y, 900)
        XCTAssertLessThan(refreshedScrollView.contentView.bounds.origin.y, 1_200)
        XCTAssertEqual(contentView.displayState.bankRangeLabel, "064-127")
        XCTAssertEqual(contentView.displayState.selectedOrderPosition, 64)
    }

    func testVisibleRefreshNoOpsUnchangedStateAndScrollsOnlyOnSelectedOrderChange() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 64, 130],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 64, rowCount: 32),
                makePattern(index: 130, rowCount: 64),
            ],
            patternCount: 131
        )
        let selectedOrderState = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: 64
        )
        let controller = SongOrderEditorWindowController(displayState: selectedOrderState)
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)

        controller.showWindowAndActivate()
        XCTAssertTrue(controller.isVisibleForRefresh)

        let initialRebuildCount = contentView.rebuildCount
        let initialScrollCount = contentView.selectedOrderScrollCount

        XCTAssertFalse(controller.applyIfVisible(displayState: selectedOrderState))
        XCTAssertEqual(contentView.rebuildCount, initialRebuildCount)
        XCTAssertEqual(contentView.selectedOrderScrollCount, initialScrollCount)

        XCTAssertTrue(controller.applyIfVisible(displayState: selectedOrderState.showingBank(2)))
        XCTAssertEqual(contentView.rebuildCount, initialRebuildCount + 1)
        XCTAssertEqual(contentView.selectedOrderScrollCount, initialScrollCount)

        let nextOrderState = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 2,
            currentPatternIndex: 130
        )
        XCTAssertTrue(controller.applyIfVisible(displayState: nextOrderState))
        XCTAssertEqual(contentView.rebuildCount, initialRebuildCount + 2)
        XCTAssertEqual(contentView.selectedOrderScrollCount, initialScrollCount + 1)

        controller.window?.close()
    }

    func testControllerApplyRefreshesFromCurrentDisplayState() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        XCTAssertEqual(contentView.displayState, .empty)

        let documentState = SongOrderEditorDisplayState.editableDocument(BlankTrackerDocument.makeDefault())
        controller.apply(displayState: documentState)

        XCTAssertEqual(contentView.displayState, documentState)
        let fieldValues = Set(contentView.allDescendants.compactMap { ($0 as? NSTextField)?.stringValue })
        XCTAssertTrue(fieldValues.contains("— selected slot (ORD 000)"))
        XCTAssertTrue(fieldValues.contains("064"))
    }

    func testRenderedOrderRowsAndPatternCellsAreReadOnlyViews() throws {
        let document = BlankTrackerDocument.makeDefault()
        let before = document
        let controller = SongOrderEditorWindowController(
            displayState: SongOrderEditorDisplayState.editableDocument(document)
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)

        let orderRows = contentView.allDescendants.filter {
            $0.identifier?.rawValue.hasPrefix(SongOrderEditorViewIdentifier.orderRowPrefix) == true
        }
        let patternCells = contentView.allDescendants.filter {
            $0.identifier?.rawValue.hasPrefix(SongOrderEditorViewIdentifier.patternCellPrefix) == true
        }

        XCTAssertEqual(orderRows.count, 1)
        XCTAssertEqual(patternCells.count, SongOrderEditorDisplayState.bankSize)
        XCTAssertTrue(orderRows.allSatisfy { !($0 is NSControl) })
        XCTAssertTrue(patternCells.allSatisfy { !($0 is NSControl) })
        XCTAssertEqual(document, before)
    }
}

private extension NSView {
    var allDescendants: [NSView] {
        [self] + subviews.flatMap(\.allDescendants)
    }
}

private func makePattern(index: Int, rowCount: Int, channels: Int = 1) -> XMPatternData {
    BlankTrackerDocument.makeEmptyPattern(index: index, rowCount: rowCount, channels: channels)
}

private func makeBlankDocument(
    currentPosition: Int = BlankTrackerDocument.defaultCurrentPosition,
    currentPatternIndex: Int = BlankTrackerDocument.defaultPatternIndex,
    orderTable: [Int] = [BlankTrackerDocument.defaultPatternIndex],
    patterns: [XMPatternData] = [BlankTrackerDocument.makeEmptyPattern(index: BlankTrackerDocument.defaultPatternIndex)]
) -> BlankTrackerDocument {
    BlankTrackerDocument(
        title: BlankTrackerDocument.defaultTitle,
        songLength: orderTable.count,
        currentPosition: currentPosition,
        restartPosition: BlankTrackerDocument.defaultRestartPosition,
        currentPatternIndex: currentPatternIndex,
        tempo: BlankTrackerDocument.defaultTempo,
        speed: BlankTrackerDocument.defaultSpeed,
        orderTable: orderTable,
        selection: .default,
        instrumentPalette: [:],
        patterns: patterns
    )
}

@MainActor
private func button(titled title: String, in view: NSView) throws -> VTXEditorButton {
    let matchingButton = view.allDescendants
        .compactMap { $0 as? VTXEditorButton }
        .first { $0.title == title }
    return try XCTUnwrap(matchingButton)
}

@MainActor
private func orderListScrollView(in view: NSView) throws -> NSScrollView {
    let scrollView = view.allDescendants.compactMap { $0 as? NSScrollView }.first
    return try XCTUnwrap(scrollView)
}

private func makeLoadedMetadata(
    orderTable: [Int],
    patterns: [XMPatternData],
    channels: Int = 1,
    patternCount: Int? = nil
) -> ParsedModuleMetadata {
    ParsedModuleMetadata(
        type: "XM",
        title: "Synthetic Loaded Module",
        version: "1.04",
        channels: channels,
        patterns: patternCount ?? patterns.count,
        instruments: 1,
        xmFlags: 0x0001,
        defaultTempo: 6,
        defaultBPM: 125,
        songLength: orderTable.count,
        restartPosition: 0,
        orderTable: orderTable,
        xmPatterns: patterns
    )
}
