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

    func testShellControlsWireOnlyBankAndEditableMutationActions() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        let buttons = contentView.allDescendants.compactMap { $0 as? VTXEditorButton }
        let bankNavigationTitles = Set(["◀", "▶"])
        let patternMutationTitles = Set(["+ NEW", "⧉ DUP", "⌫ CLEAR"])
        let orderMutationTitles = Set(["+ INSERT", "⌫ DELETE", "⧉ DUP", "▲ MOVE UP", "▼ MOVE DOWN"])
        let orderPatternStepTitles = Set(["-", "+"])
        let bankNavigationButtons = buttons.filter { bankNavigationTitles.contains($0.title) }
        let patternOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.patternOpsPanel, in: contentView)
        let orderOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.orderOpsPanel, in: contentView)
        let dangerPanel = try identifiedView(SongOrderEditorViewIdentifier.dangerPanel, in: contentView)
        let unavailablePatternMutationButtons = patternOpsPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { patternMutationTitles.contains($0.title) }
        let unavailableOrderMutationButtons = orderOpsPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { orderMutationTitles.contains($0.title) }
        let unavailableOrderPatternStepButtons = orderOpsPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { orderPatternStepTitles.contains($0.title) }
        let unavailableClearSongButtons = dangerPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { $0.title == "⌫ CLEAR SONG" }

        XCTAssertGreaterThanOrEqual(buttons.count, 10)
        XCTAssertEqual(bankNavigationButtons.count, 2)
        XCTAssertTrue(bankNavigationButtons.allSatisfy { ($0.target as? SongOrderEditorContentView) === contentView })
        XCTAssertTrue(bankNavigationButtons.allSatisfy { $0.action != nil })
        XCTAssertEqual(unavailablePatternMutationButtons.count, 3)
        XCTAssertTrue(unavailablePatternMutationButtons.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(unavailablePatternMutationButtons.allSatisfy { $0.target == nil })
        XCTAssertTrue(unavailablePatternMutationButtons.allSatisfy { $0.action == nil })
        XCTAssertEqual(unavailableOrderMutationButtons.count, 5)
        XCTAssertTrue(unavailableOrderMutationButtons.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(unavailableOrderMutationButtons.allSatisfy { $0.target == nil })
        XCTAssertTrue(unavailableOrderMutationButtons.allSatisfy { $0.action == nil })
        XCTAssertEqual(unavailableOrderPatternStepButtons.count, 2)
        XCTAssertTrue(unavailableOrderPatternStepButtons.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(unavailableOrderPatternStepButtons.allSatisfy { $0.target == nil })
        XCTAssertTrue(unavailableOrderPatternStepButtons.allSatisfy { $0.action == nil })
        XCTAssertEqual(unavailableClearSongButtons.count, 1)
        XCTAssertTrue(unavailableClearSongButtons.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(unavailableClearSongButtons.allSatisfy { $0.target == nil })
        XCTAssertTrue(unavailableClearSongButtons.allSatisfy { $0.action == nil })

        let editableDocument = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 1,
            orderTable: [0, 1, 2],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 16),
                makePattern(index: 2, rowCount: 16),
            ]
        )
        let editableState = SongOrderEditorDisplayState.editableDocument(editableDocument)
        controller.apply(displayState: editableState)
        let editablePatternOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.patternOpsPanel, in: contentView)
        let editableOrderOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.orderOpsPanel, in: contentView)
        let editableDangerPanel = try identifiedView(SongOrderEditorViewIdentifier.dangerPanel, in: contentView)
        let editablePatternMutationButtons = editablePatternOpsPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { patternMutationTitles.contains($0.title) }
        let editableOrderMutationButtons = editableOrderOpsPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { orderMutationTitles.contains($0.title) }
        let editableOrderPatternStepButtons = editableOrderOpsPanel.allDescendants
            .compactMap { $0 as? VTXEditorButton }
            .filter { orderPatternStepTitles.contains($0.title) }
        let editableClearSongButton = try button(titled: "⌫ CLEAR SONG", in: editableDangerPanel)

        XCTAssertEqual(editablePatternMutationButtons.count, 3)
        XCTAssertTrue(editablePatternMutationButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(editablePatternMutationButtons.allSatisfy { ($0.target as? SongOrderEditorContentView) === contentView })
        XCTAssertTrue(editablePatternMutationButtons.allSatisfy { $0.action != nil })
        XCTAssertEqual(editableOrderMutationButtons.count, 5)
        XCTAssertTrue(editableOrderMutationButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(editableOrderMutationButtons.allSatisfy { ($0.target as? SongOrderEditorContentView) === contentView })
        XCTAssertTrue(editableOrderMutationButtons.allSatisfy { $0.action != nil })
        XCTAssertEqual(editableOrderPatternStepButtons.count, 2)
        XCTAssertTrue(editableOrderPatternStepButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(editableOrderPatternStepButtons.allSatisfy { ($0.target as? SongOrderEditorContentView) === contentView })
        XCTAssertTrue(editableOrderPatternStepButtons.allSatisfy { $0.action != nil })
        XCTAssertTrue(editableClearSongButton.isEnabled)
        XCTAssertTrue((editableClearSongButton.target as? SongOrderEditorContentView) === contentView)
        XCTAssertNotNil(editableClearSongButton.action)
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

    func testOrderListLegendUsesMockupTokenColors() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let orderLegend = try textField("ORD = order position", in: contentView)
        let patternLegend = try textField("PTN = pattern number", in: contentView)
        let dimDescriptionColor = VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40)

        assertAttributedForegroundColor(orderLegend, at: 0, matches: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55))
        assertAttributedForegroundColor(orderLegend, at: 4, matches: dimDescriptionColor)
        assertAttributedForegroundColor(patternLegend, at: 0, matches: VTXEditorControlTheme.warmValueText)
        assertAttributedForegroundColor(patternLegend, at: 4, matches: dimDescriptionColor)
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

    func testLoadedModuleSelectedOrderNavigationUpdatesCurrentOrderAndPatternWithoutMutation() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 2, 64],
            patterns: makeContiguousPatterns(through: 64),
            patternCount: 65
        )
        let beforeOrderTable = metadata.orderTable
        let beforePatterns = metadata.xmPatterns

        let result = try XCTUnwrap(SongOrderEditorNavigation.loadedModuleSelection(
            selectingOrderPosition: 2,
            metadata: metadata,
            currentOrderPosition: 0,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: result.selectedOrderPosition,
            currentPatternIndex: result.currentPatternIndex
        )
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 64 })
        let controlPanelContent = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selectedSongPositionIndex: result.selectedOrderPosition,
            currentPatternIndex: result.currentPatternIndex,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(result, SongOrderEditorNavigationResult(selectedOrderPosition: 2, currentPatternIndex: 64))
        XCTAssertEqual(controlPanelContent.songPosition, "02")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: result.currentPatternIndex), "064")
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, false, true])
        XCTAssertEqual(state.bankIndex, 1)
        XCTAssertEqual(state.bankDisplayLabel, "BANK 2/2")
        XCTAssertTrue(currentCell.isCurrent)
        XCTAssertEqual(metadata.orderTable, beforeOrderTable)
        XCTAssertEqual(metadata.xmPatterns, beforePatterns)
    }

    func testEditableDocumentSelectedOrderNavigationUpdatesStateWithoutMutatingOrderOrPatterns() throws {
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0, 2, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 32),
                makePattern(index: 2, rowCount: 48),
            ]
        )
        let beforeOrderTable = document.orderTable
        let beforePatterns = document.patterns

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocument(
            document,
            selectingOrderPosition: 1,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 2 })

        XCTAssertEqual(updated.currentPosition, 1)
        XCTAssertEqual(updated.currentPatternIndex, 2)
        XCTAssertEqual(updated.orderTable, beforeOrderTable)
        XCTAssertEqual(updated.patterns, beforePatterns)
        XCTAssertEqual(document.orderTable, beforeOrderTable)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, true, false])
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testLoadedModulePatternBankNavigationUpdatesCurrentPatternWithoutOrderMutation() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 2],
            patterns: makeContiguousPatterns(through: 64),
            patternCount: 65
        )
        let beforeOrderTable = metadata.orderTable
        let beforePatterns = metadata.xmPatterns

        let selectedPatternIndex = try XCTUnwrap(SongOrderEditorNavigation.loadedModulePatternSelection(
            selectingPatternIndex: 64,
            metadata: metadata,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: selectedPatternIndex
        )
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 64 })

        XCTAssertEqual(selectedPatternIndex, 64)
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: selectedPatternIndex), "064")
        XCTAssertEqual(state.selectedOrderPosition, 0)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 2])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [true, false])
        XCTAssertEqual(state.bankIndex, 1)
        XCTAssertEqual(state.bankDisplayLabel, "BANK 2/2")
        XCTAssertTrue(currentCell.exists)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
        XCTAssertEqual(metadata.orderTable, beforeOrderTable)
        XCTAssertEqual(metadata.xmPatterns, beforePatterns)
    }

    func testUnreferencedPatternBankNavigationPreservesSelectedOrderForNormalPlay() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [3, 7],
            patterns: [
                makePattern(index: 3, rowCount: 16),
                makePattern(index: 7, rowCount: 16),
                makePattern(index: 42, rowCount: 16),
            ],
            patternCount: 43
        )
        let before = metadata
        let engine = PlaybackEngine(
            audioEngine: TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100),
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [3, 7],
            patternRowCounts: [3: 16, 7: 16, 42: 16]
        ))

        let selectedPatternIndex = try XCTUnwrap(SongOrderEditorNavigation.loadedModulePatternSelection(
            selectingPatternIndex: 42,
            metadata: metadata,
            currentPatternIndex: 7,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: selectedPatternIndex
        )
        let context = TrackerPlaybackStartContextResolver.normalPlayContext(
            metadata: metadata,
            selectedSongPositionIndex: 1,
            displayedPatternIndex: selectedPatternIndex,
            row: 0
        )
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 42 })

        XCTAssertEqual(selectedPatternIndex, 42)
        XCTAssertEqual(state.selectedOrderPosition, 1)
        XCTAssertEqual(state.selectedPatternIndex, 42)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
        XCTAssertEqual(metadata, before)
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(context.songPosition, 1)
        XCTAssertEqual(context.patternIndex, 7)

        engine.play(from: context, loopEnabled: false, timingSession: nil)

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 7, rowIndex: 0))
        XCTAssertEqual(engine.state.context, context)
    }

    func testPlayCurrentPatternContextTargetsDisplayedPatternFromRowZeroWithoutResettingSelectedOrder() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [3, 7],
            patterns: [
                makePattern(index: 3, rowCount: 16),
                makePattern(index: 7, rowCount: 16),
                makePattern(index: 42, rowCount: 16),
            ],
            patternCount: 43
        )

        let context = try XCTUnwrap(TrackerPlaybackStartContextResolver.currentPatternLoopContext(
            metadata: metadata,
            selectedSongPositionIndex: 1,
            displayedPatternIndex: 42
        ))

        XCTAssertEqual(context.songPosition, 1)
        XCTAssertEqual(context.patternIndex, 42)
        XCTAssertEqual(context.row, 0)
    }

    func testPlayCurrentPatternAvailabilityRequiresCurrentPatternAndIdlePlayback() {
        let metadata = makeLoadedMetadata(
            orderTable: [0],
            patterns: [makePattern(index: 0, rowCount: 16)]
        )

        XCTAssertTrue(TrackerTransportCommandAvailability.canPlayCurrentPattern(
            metadata: metadata,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        XCTAssertFalse(TrackerTransportCommandAvailability.canPlayCurrentPattern(
            metadata: metadata,
            currentPatternIndex: 9,
            isPlaybackActive: false
        ))
        XCTAssertFalse(TrackerTransportCommandAvailability.canPlayCurrentPattern(
            metadata: metadata,
            currentPatternIndex: 0,
            isPlaybackActive: true
        ))
        XCTAssertFalse(TrackerTransportCommandAvailability.canPlayCurrentPattern(
            metadata: nil,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
    }

    func testEditableDocumentPatternBankNavigationUpdatesCurrentPatternWithoutMutatingOrderOrPatterns() throws {
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 32),
                makePattern(index: 2, rowCount: 48),
            ]
        )
        let beforeOrderTable = document.orderTable
        let beforePatterns = document.patterns

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocument(
            document,
            selectingPatternIndex: 2,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 2 })

        XCTAssertEqual(updated.currentPosition, 0)
        XCTAssertEqual(updated.currentPatternIndex, 2)
        XCTAssertEqual(updated.orderTable, beforeOrderTable)
        XCTAssertEqual(updated.patterns, beforePatterns)
        XCTAssertEqual(document.orderTable, beforeOrderTable)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 1])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [true, false])
        XCTAssertTrue(currentCell.exists)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testEditableDocumentPatternBankDoubleClickAssignsExistingPatternToSelectedOrder() throws {
        var assignedPattern = makePattern(index: 66, rowCount: 48)
        assignedPattern.rows[7][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 0,
            orderTable: [0, 0],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                assignedPattern,
            ]
        )
        let beforePatterns = document.patterns

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocument(
            document,
            assigningPatternIndexToSelectedOrder: 66,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 66 })

        XCTAssertEqual(updated.orderTable, [0, 66])
        XCTAssertEqual(updated.currentPosition, 1)
        XCTAssertEqual(updated.currentPatternIndex, 66)
        XCTAssertEqual(updated.patterns, beforePatterns)
        XCTAssertEqual(document.orderTable, [0, 0])
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 66])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, true])
        XCTAssertEqual(state.bankIndex, 1)
        XCTAssertEqual(state.bankDisplayLabel, "BANK 2/2")
        XCTAssertTrue(currentCell.exists)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testEditableSelectedOrderPatternStepperAssignsNextAndPreviousAllocatedPattern() throws {
        var middlePattern = makePattern(index: 1, rowCount: 32, channels: 2)
        middlePattern.rows[3][1] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 0,
            orderTable: [0, 0],
            patterns: [
                makePattern(index: 0, rowCount: 16, channels: 2),
                middlePattern,
                makePattern(index: 2, rowCount: 48, channels: 2),
            ]
        )
        let beforePatterns = document.patterns

        let incremented = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            document,
            delta: 1,
            isPlaybackActive: false
        ))
        let incrementedState = SongOrderEditorDisplayState.editableDocument(incremented)
        let incrementedCell = try XCTUnwrap(incrementedState.patternBankCells.first { $0.patternIndex == 1 })
        let incrementedContent = ControlPanelDisplayState.blankDocumentContent(
            for: incremented,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(incremented.orderTable, [0, 1])
        XCTAssertEqual(incremented.currentPosition, 1)
        XCTAssertEqual(incremented.currentPatternIndex, 1)
        XCTAssertEqual(incremented.patterns, beforePatterns)
        XCTAssertEqual(incremented.instrumentPalette, document.instrumentPalette)
        XCTAssertEqual(incremented.pattern(for: 1)?.rows[3][1], middlePattern.rows[3][1])
        XCTAssertEqual(incrementedState.orderRows.map(\.patternIndex), [0, 1])
        XCTAssertEqual(incrementedState.orderRows.map(\.isSelected), [false, true])
        XCTAssertTrue(incrementedCell.isUsed)
        XCTAssertTrue(incrementedCell.isCurrent)
        XCTAssertEqual(incrementedContent.songPosition, "01")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: incremented.currentPatternIndex), "001")

        let decremented = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            incremented,
            delta: -1,
            isPlaybackActive: false
        ))
        let decrementedState = SongOrderEditorDisplayState.editableDocument(decremented)
        let decrementedCell = try XCTUnwrap(decrementedState.patternBankCells.first { $0.patternIndex == 0 })

        XCTAssertEqual(decremented.orderTable, [0, 0])
        XCTAssertEqual(decremented.currentPosition, 1)
        XCTAssertEqual(decremented.currentPatternIndex, 0)
        XCTAssertEqual(decremented.patterns, beforePatterns)
        XCTAssertEqual(decrementedState.orderRows.map(\.patternIndex), [0, 0])
        XCTAssertEqual(decrementedState.orderRows.map(\.isSelected), [false, true])
        XCTAssertTrue(decrementedCell.isUsed)
        XCTAssertTrue(decrementedCell.isCurrent)
    }

    func testEditableSelectedOrderPatternStepperSkipsSparseAllocatedPatternGapsWithoutAllocation() throws {
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 2,
            orderTable: [2],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 2, rowCount: 24),
                makePattern(index: 66, rowCount: 32),
            ]
        )
        let beforePatterns = document.patterns

        let steppedUp = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            document,
            delta: 1,
            isPlaybackActive: false
        ))
        let steppedUpState = SongOrderEditorDisplayState.editableDocument(steppedUp)
        let currentCell = try XCTUnwrap(steppedUpState.patternBankCells.first { $0.patternIndex == 66 })

        XCTAssertEqual(steppedUp.orderTable, [66])
        XCTAssertEqual(steppedUp.currentPosition, 0)
        XCTAssertEqual(steppedUp.currentPatternIndex, 66)
        XCTAssertEqual(steppedUp.patterns, beforePatterns)
        XCTAssertNil(steppedUp.pattern(for: 3))
        XCTAssertNil(steppedUp.pattern(for: 65))
        XCTAssertEqual(steppedUpState.bankIndex, 1)
        XCTAssertTrue(currentCell.exists)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)

        let steppedDown = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            steppedUp,
            delta: -1,
            isPlaybackActive: false
        ))

        XCTAssertEqual(steppedDown.orderTable, [2])
        XCTAssertEqual(steppedDown.currentPatternIndex, 2)
        XCTAssertEqual(steppedDown.patterns, beforePatterns)
    }

    func testEditableSelectedOrderPatternStepperNoOpsAtBoundariesAndInvalidReferences() throws {
        let lowestDocument = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 2, rowCount: 32),
            ]
        )
        let lowestState = SongOrderEditorDisplayState.editableDocument(lowestDocument)

        XCTAssertFalse(lowestState.isStepSelectedOrderPatternDownEnabled)
        XCTAssertTrue(lowestState.isStepSelectedOrderPatternUpEnabled)
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            lowestDocument,
            delta: -1,
            isPlaybackActive: false
        ))

        let highestDocument = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 2,
            orderTable: [2],
            patterns: lowestDocument.patterns
        )
        let highestState = SongOrderEditorDisplayState.editableDocument(highestDocument)

        XCTAssertTrue(highestState.isStepSelectedOrderPatternDownEnabled)
        XCTAssertFalse(highestState.isStepSelectedOrderPatternUpEnabled)
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            highestDocument,
            delta: 1,
            isPlaybackActive: false
        ))

        let invalidReferenceDocument = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [9],
            patterns: lowestDocument.patterns
        )
        let invalidState = SongOrderEditorDisplayState.editableDocument(invalidReferenceDocument)

        XCTAssertFalse(invalidState.isStepSelectedOrderPatternDownEnabled)
        XCTAssertFalse(invalidState.isStepSelectedOrderPatternUpEnabled)
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            invalidReferenceDocument,
            delta: 1,
            isPlaybackActive: false
        ))
        XCTAssertNil(invalidReferenceDocument.pattern(for: 9))
    }

    func testEditableNewPatternHelperCreatesViewsAndHighlightsUnassignedBlankPattern() throws {
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [makePattern(index: 0, rowCount: 16, channels: 2)]
        )

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentCreatingBlankPatternForEditing(
            document,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let newPattern = try XCTUnwrap(updated.pattern(for: 1))
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 1 })

        XCTAssertEqual(updated.orderTable, [0])
        XCTAssertEqual(updated.currentPosition, 0)
        XCTAssertEqual(updated.currentPatternIndex, 1)
        XCTAssertEqual(updated.patterns.map(\.index), [0, 1])
        XCTAssertEqual(newPattern.rowCount, 16)
        XCTAssertEqual(newPattern.channels, 2)
        XCTAssertTrue(newPattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0])
        XCTAssertTrue(currentCell.exists)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testEditableNewPatternAutoPagesPatternBankAcrossBoundary() throws {
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 63,
            orderTable: [63],
            patterns: makeContiguousPatterns(through: 63)
        )

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentCreatingBlankPatternForEditing(
            document,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 64 })

        XCTAssertEqual(updated.orderTable, [63])
        XCTAssertEqual(updated.currentPatternIndex, 64)
        XCTAssertEqual(state.bankIndex, 1)
        XCTAssertEqual(state.bankRangeLabel, "064-127")
        XCTAssertEqual(state.bankDisplayLabel, "BANK 2/2")
        XCTAssertTrue(currentCell.exists)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testEditableDuplicateCurrentPatternFromUnassignedPatternKeepsOrderUnchanged() throws {
        var hiddenPattern = makePattern(index: 2, rowCount: 24, channels: 1)
        hiddenPattern.rows[6][0] = XMPatternEventCell(
            note: 52,
            instrument: 2,
            volumeColumn: 0x20,
            effectType: 0x0A,
            effectParam: 0x10
        )
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 2,
            orderTable: [0],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                hiddenPattern,
            ]
        )

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentDuplicatingCurrentPatternForEditing(
            document,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let duplicatedPattern = try XCTUnwrap(updated.pattern(for: 3))
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 3 })

        XCTAssertEqual(updated.orderTable, [0])
        XCTAssertEqual(updated.currentPosition, 0)
        XCTAssertEqual(updated.currentPatternIndex, 3)
        XCTAssertEqual(updated.pattern(for: 2), hiddenPattern)
        XCTAssertEqual(duplicatedPattern.rows, hiddenPattern.rows)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0])
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testEditableClearCurrentPatternHelperClearsDisplayedPatternOnlyAndPreservesOrderReferences() throws {
        var firstPattern = makePattern(index: 0, rowCount: 16, channels: 2)
        var secondPattern = makePattern(index: 1, rowCount: 32, channels: 2)
        firstPattern.rows[1][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        secondPattern.rows[2][1] = XMPatternEventCell(
            note: 52,
            instrument: 2,
            volumeColumn: 0x20,
            effectType: 0x0A,
            effectParam: 0x10
        )
        let document = makeBlankDocument(
            currentPosition: 2,
            currentPatternIndex: 0,
            orderTable: [0, 1, 0],
            patterns: [firstPattern, secondPattern]
        )

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentClearingCurrentPatternForEditing(
            document,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let currentCell = try XCTUnwrap(state.patternBankCells.first { $0.patternIndex == 0 })

        XCTAssertEqual(updated.orderTable, [0, 1, 0])
        XCTAssertEqual(updated.currentPosition, 2)
        XCTAssertEqual(updated.currentPatternIndex, 0)
        XCTAssertTrue(updated.pattern(for: 0)?.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        } == true)
        XCTAssertEqual(updated.pattern(for: 1), secondPattern)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 1, 0])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, false, true])
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternOpsDuplicateAndClearButtonsRequestEditableMutationAndRefreshDisplayState() throws {
        var sourcePattern = makePattern(index: 0, rowCount: 16, channels: 2)
        sourcePattern.rows[2][1] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        sourcePattern.rows[3][0] = XMPatternEventCell(
            note: TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 0x02,
            volumeColumn: 0x30,
            effectType: 0x0E,
            effectParam: 0x9C
        )
        var document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [sourcePattern]
        )
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var duplicateRequestCount = 0
        var clearRequestCount = 0
        controller.onDuplicateCurrentPattern = {
            duplicateRequestCount += 1
            guard let updated = SongOrderEditorNavigation.editableDocumentDuplicatingCurrentPatternForEditing(
                document,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }
        controller.onClearCurrentPattern = {
            clearRequestCount += 1
            guard let updated = SongOrderEditorNavigation.editableDocumentClearingCurrentPatternForEditing(
                document,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }

        let initialPatternOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.patternOpsPanel, in: contentView)
        try button(titled: "⧉ DUP", in: initialPatternOpsPanel).performClick(nil)
        let duplicatedPattern = try XCTUnwrap(document.pattern(for: 1))
        let duplicatedCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 1 })

        XCTAssertEqual(duplicateRequestCount, 1)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(duplicatedPattern.rows, sourcePattern.rows)
        XCTAssertFalse(duplicatedCell.isUsed)
        XCTAssertTrue(duplicatedCell.isCurrent)

        let refreshedPatternOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.patternOpsPanel, in: contentView)
        try button(titled: "⌫ CLEAR", in: refreshedPatternOpsPanel).performClick(nil)

        XCTAssertEqual(clearRequestCount, 1)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.pattern(for: 0), sourcePattern)
        XCTAssertTrue(document.pattern(for: 1)?.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        } == true)
        XCTAssertEqual(contentView.displayState.selectedPatternIndex, 1)
    }

    func testClearSongButtonRequestsEditableResetAndRefreshesDisplayState() throws {
        let sample = makePlaybackSample(
            instrumentIndex: 2,
            sampleIndex: 0,
            name: "Lead Sample",
            pcm: [0.25, -0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let instrument = PlaybackInstrument(index: 2, name: "Lead", samples: [sample])
        var firstPattern = makePattern(index: 0, rowCount: 16, channels: 2)
        var secondPattern = makePattern(index: 1, rowCount: 32, channels: 3)
        firstPattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 2,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        secondPattern.rows[2][1] = XMPatternEventCell(
            note: TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 0x02,
            volumeColumn: 0x30,
            effectType: 0x0E,
            effectParam: 0x9C
        )
        var document = makeBlankDocument(
            currentPosition: 2,
            currentPatternIndex: 1,
            orderTable: [0, 1, 0],
            patterns: [firstPattern, secondPattern],
            tempo: 144,
            speed: 3,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            instrumentPalette: [2: instrument]
        )
        let beforePalette = document.instrumentPalette
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var clearRequestCount = 0
        controller.onClearSongRequested = {
            clearRequestCount += 1
            guard let updated = SongOrderEditorNavigation.editableDocumentClearingSongDataForEditing(
                document,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }

        try button(titled: "⌫ CLEAR SONG", in: contentView).performClick(nil)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 0 })
        let content = ControlPanelDisplayState.blankDocumentContent(
            for: document,
            selectedOctave: 6,
            isLoopEnabled: true,
            isEditModeEnabled: true,
            isPlaybackActive: false
        )

        XCTAssertEqual(clearRequestCount, 1)
        XCTAssertEqual(document.songLength, 1)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.patterns.map(\.index), [0])
        XCTAssertNil(document.pattern(for: 1))
        XCTAssertEqual(document.pattern.rowCount, 32)
        XCTAssertEqual(document.pattern.channels, 3)
        XCTAssertTrue(document.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[2][1]), "... .. .. ...")
        XCTAssertEqual(document.instrumentPalette, beforePalette)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(document.tempo, 144)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(content.songPosition, "00")
        XCTAssertEqual(content.songLength, "01")
        XCTAssertEqual(content.patternRowCount, "32")
        XCTAssertEqual(content.channelCount, "3")
        XCTAssertEqual(content.selectedInstrumentDisplay, "I02 Lead")
        XCTAssertEqual(content.selectedSampleDisplay, "S01 Lead Sample")
        XCTAssertEqual(content.selectedOctave, 6)
        XCTAssertTrue(content.isEditModeEnabled)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.patternIndex), [0])
        XCTAssertEqual(contentView.displayState.orderRows.map(\.isSelected), [true])
        XCTAssertEqual(contentView.displayState.selectedOrderPosition, 0)
        XCTAssertEqual(contentView.displayState.selectedPatternIndex, 0)
        XCTAssertTrue(currentCell.exists)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testEditableDuplicateSelectedOrderInsertsAfterSelectionAndMiddlePreservesReferences() throws {
        let instrument = PlaybackInstrument(
            index: 1,
            name: "Lead",
            samples: [
                PlaybackSample(
                    instrumentIndex: 1,
                    sampleIndex: 0,
                    name: "Lead Sample",
                    pcm: [0.25],
                    volume: 1,
                    relativeNote: 0,
                    finetune: 0,
                    baseSampleRate: 8_363
                )
            ]
        )
        var pattern = makePattern(index: 0, rowCount: 16, channels: 2)
        pattern.rows[3][1] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [1: instrument]
        )
        let beforePatterns = document.patterns
        let beforePalette = document.instrumentPalette

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentDuplicatingSelectedOrder(
            document,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)
        let content = ControlPanelDisplayState.blankDocumentContent(
            for: updated,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(updated.orderTable, [0, 0])
        XCTAssertEqual(updated.songLength, 2)
        XCTAssertEqual(updated.currentPosition, 1)
        XCTAssertEqual(updated.currentPatternIndex, 0)
        XCTAssertEqual(updated.patterns, beforePatterns)
        XCTAssertEqual(updated.instrumentPalette, beforePalette)
        XCTAssertEqual(updated.pattern(for: 0)?.rows[3][1], pattern.rows[3][1])
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [0, 0])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [false, true])
        XCTAssertEqual(content.songPosition, "01")
        XCTAssertEqual(content.songLength, "02")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: updated.currentPatternIndex), "000")

        let middleDocument = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 1,
            orderTable: [0, 1, 2, 3],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 24),
                makePattern(index: 2, rowCount: 32),
                makePattern(index: 3, rowCount: 48),
            ]
        )
        let beforeMiddlePatterns = middleDocument.patterns

        let middleUpdated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentDuplicatingSelectedOrder(
            middleDocument,
            isPlaybackActive: false
        ))
        let middleState = SongOrderEditorDisplayState.editableDocument(middleUpdated)

        XCTAssertEqual(middleUpdated.orderTable, [0, 1, 1, 2, 3])
        XCTAssertEqual(middleUpdated.songLength, 5)
        XCTAssertEqual(middleUpdated.currentPosition, 2)
        XCTAssertEqual(middleUpdated.currentPatternIndex, 1)
        XCTAssertEqual(middleUpdated.patterns, beforeMiddlePatterns)
        XCTAssertEqual(middleState.orderRows.map(\.patternIndex), [0, 1, 1, 2, 3])
        XCTAssertEqual(middleState.orderRows.map(\.isSelected), [false, false, true, false, false])
    }

    func testEditableMoveSelectedOrderUpAndDownPreserveReferencesAndNoOpAtBoundaries() throws {
        let document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 1,
            orderTable: [0, 1, 2],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 32),
                makePattern(index: 2, rowCount: 48),
            ]
        )
        let beforePatterns = document.patterns

        let updated = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentMovingSelectedOrderUp(
            document,
            isPlaybackActive: false
        ))
        let state = SongOrderEditorDisplayState.editableDocument(updated)

        XCTAssertEqual(updated.orderTable, [1, 0, 2])
        XCTAssertEqual(updated.songLength, 3)
        XCTAssertEqual(updated.currentPosition, 0)
        XCTAssertEqual(updated.currentPatternIndex, 1)
        XCTAssertEqual(updated.patterns, beforePatterns)
        XCTAssertEqual(state.orderRows.map(\.patternIndex), [1, 0, 2])
        XCTAssertEqual(state.orderRows.map(\.isSelected), [true, false, false])
        XCTAssertEqual(updated.controlPanelMetadata.songPosition, "00")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: updated.currentPatternIndex), "001")
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentMovingSelectedOrderUp(
            updated,
            isPlaybackActive: false
        ))

        let movedDown = try XCTUnwrap(SongOrderEditorNavigation.editableDocumentMovingSelectedOrderDown(
            document,
            isPlaybackActive: false
        ))
        let movedDownState = SongOrderEditorDisplayState.editableDocument(movedDown)

        XCTAssertEqual(movedDown.orderTable, [0, 2, 1])
        XCTAssertEqual(movedDown.songLength, 3)
        XCTAssertEqual(movedDown.currentPosition, 2)
        XCTAssertEqual(movedDown.currentPatternIndex, 1)
        XCTAssertEqual(movedDown.patterns, beforePatterns)
        XCTAssertEqual(movedDownState.orderRows.map(\.patternIndex), [0, 2, 1])
        XCTAssertEqual(movedDownState.orderRows.map(\.isSelected), [false, false, true])
        XCTAssertEqual(movedDown.controlPanelMetadata.songPosition, "02")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: movedDown.currentPatternIndex), "001")
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentMovingSelectedOrderDown(
            movedDown,
            isPlaybackActive: false
        ))
    }

    func testOrderPatternStepperButtonsRequestEditableMutationAndRefreshDisplayState() throws {
        var document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 1,
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 24),
                makePattern(index: 64, rowCount: 32),
            ]
        )
        let beforePatterns = document.patterns
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var requestedDeltas = [Int]()
        controller.onStepSelectedOrderPattern = { delta in
            requestedDeltas.append(delta)
            guard let updated = SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
                document,
                delta: delta,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }

        let initialOrderOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.orderOpsPanel, in: contentView)
        XCTAssertTrue(try button(titled: "-", in: initialOrderOpsPanel).isEnabled)
        XCTAssertTrue(try button(titled: "+", in: initialOrderOpsPanel).isEnabled)
        try button(titled: "+", in: initialOrderOpsPanel).performClick(nil)
        let steppedUpCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 64 })

        XCTAssertEqual(requestedDeltas, [1])
        XCTAssertEqual(document.orderTable, [0, 64])
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 64)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(contentView.displayState.bankIndex, 1)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.patternIndex), [0, 64])
        XCTAssertEqual(contentView.displayState.orderRows.map(\.isSelected), [false, true])
        XCTAssertTrue(steppedUpCell.isUsed)
        XCTAssertTrue(steppedUpCell.isCurrent)

        let refreshedOrderOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.orderOpsPanel, in: contentView)
        XCTAssertTrue(try button(titled: "-", in: refreshedOrderOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "+", in: refreshedOrderOpsPanel).isEnabled)
        try button(titled: "-", in: refreshedOrderOpsPanel).performClick(nil)
        let steppedDownCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 1 })

        XCTAssertEqual(requestedDeltas, [1, -1])
        XCTAssertEqual(document.orderTable, [0, 1])
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(contentView.displayState.bankIndex, 0)
        XCTAssertTrue(steppedDownCell.isUsed)
        XCTAssertTrue(steppedDownCell.isCurrent)
    }

    func testNewPatternButtonRequestsEditableCreationAndRefreshesDisplayState() throws {
        var document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [makePattern(index: 0, rowCount: 16)]
        )
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var requestCount = 0
        controller.onNewPatternRequested = {
            requestCount += 1
            guard let updated = SongOrderEditorNavigation.editableDocumentCreatingBlankPatternForEditing(
                document,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }

        try button(titled: "+ NEW", in: contentView).performClick(nil)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 1 })

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.patternIndex), [0])
        XCTAssertTrue(currentCell.exists)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternBankAssignmentIgnoresEmptyCellsAndActivePlaybackWithoutAllocation() throws {
        let document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 1,
            orderTable: [0, 1, 2],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 16),
                makePattern(index: 2, rowCount: 16),
            ]
        )
        let before = document

        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            assigningPatternIndexToSelectedOrder: 12,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            assigningPatternIndexToSelectedOrder: 1,
            isPlaybackActive: true
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentCreatingBlankPatternForEditing(
            document,
            isPlaybackActive: true
        ))
        XCTAssertEqual(document, before)
        XCTAssertNil(document.pattern(for: 12))
    }

    func testPatternBankNavigationIgnoresEmptyCurrentAndPlaybackActiveCellsWithoutAllocation() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 16),
            ],
            patternCount: 2
        )
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 16),
            ]
        )
        let beforePatterns = document.patterns

        XCTAssertNil(SongOrderEditorNavigation.loadedModulePatternSelection(
            selectingPatternIndex: 12,
            metadata: metadata,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.loadedModulePatternSelection(
            selectingPatternIndex: 0,
            metadata: metadata,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.loadedModulePatternSelection(
            selectingPatternIndex: 1,
            metadata: metadata,
            currentPatternIndex: 0,
            isPlaybackActive: true
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            selectingPatternIndex: 12,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            selectingPatternIndex: 0,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            selectingPatternIndex: 1,
            isPlaybackActive: true
        ))
        XCTAssertEqual(document.patterns, beforePatterns)
    }

    func testLoadedModuleOrderButtonsDoNotRequestMutation() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 32),
            ]
        )
        let loadedController = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        ))
        let loadedContentView = try XCTUnwrap(loadedController.window?.contentView as? SongOrderEditorContentView)
        let orderOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.orderOpsPanel, in: loadedContentView)
        var loadedMutationRequestCount = 0
        loadedController.onInsertOrderAfterSelected = { loadedMutationRequestCount += 1 }
        loadedController.onDeleteSelectedOrder = { loadedMutationRequestCount += 1 }
        loadedController.onDuplicateSelectedOrder = { loadedMutationRequestCount += 1 }
        loadedController.onMoveSelectedOrderUp = { loadedMutationRequestCount += 1 }
        loadedController.onMoveSelectedOrderDown = { loadedMutationRequestCount += 1 }
        loadedController.onStepSelectedOrderPattern = { _ in loadedMutationRequestCount += 1 }

        XCTAssertFalse(try button(titled: "+ INSERT", in: orderOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "⌫ DELETE", in: orderOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "▲ MOVE UP", in: orderOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "▼ MOVE DOWN", in: orderOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "-", in: orderOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "+", in: orderOpsPanel).isEnabled)
        XCTAssertEqual(try buttons(titled: "⧉ DUP", in: orderOpsPanel).filter { $0.target != nil }.count, 0)
        try button(titled: "+ INSERT", in: orderOpsPanel).performClick(nil)
        try button(titled: "⌫ DELETE", in: orderOpsPanel).performClick(nil)
        try button(titled: "▲ MOVE UP", in: orderOpsPanel).performClick(nil)
        try button(titled: "▼ MOVE DOWN", in: orderOpsPanel).performClick(nil)
        try button(titled: "-", in: orderOpsPanel).performClick(nil)
        try button(titled: "+", in: orderOpsPanel).performClick(nil)
        for duplicateButton in try buttons(titled: "⧉ DUP", in: orderOpsPanel) {
            duplicateButton.performClick(nil)
        }
        XCTAssertEqual(loadedMutationRequestCount, 0)
        XCTAssertEqual(metadata.orderTable, [0, 1])
        XCTAssertEqual(metadata.xmPatterns.map(\.index), [0, 1])
    }

    func testLoadedModulePatternOpsButtonsDoNotRequestMutation() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0],
            patterns: [makePattern(index: 0, rowCount: 16)]
        )
        let loadedController = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        ))
        let loadedContentView = try XCTUnwrap(loadedController.window?.contentView as? SongOrderEditorContentView)
        let patternOpsPanel = try identifiedView(SongOrderEditorViewIdentifier.patternOpsPanel, in: loadedContentView)
        var patternMutationRequestCount = 0
        loadedController.onNewPatternRequested = { patternMutationRequestCount += 1 }
        loadedController.onDuplicateCurrentPattern = { patternMutationRequestCount += 1 }
        loadedController.onClearCurrentPattern = { patternMutationRequestCount += 1 }

        XCTAssertFalse(try button(titled: "+ NEW", in: patternOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "⧉ DUP", in: patternOpsPanel).isEnabled)
        XCTAssertFalse(try button(titled: "⌫ CLEAR", in: patternOpsPanel).isEnabled)
        try button(titled: "+ NEW", in: patternOpsPanel).performClick(nil)
        try button(titled: "⧉ DUP", in: patternOpsPanel).performClick(nil)
        try button(titled: "⌫ CLEAR", in: patternOpsPanel).performClick(nil)
        XCTAssertEqual(patternMutationRequestCount, 0)
        XCTAssertEqual(metadata.orderTable, [0])
        XCTAssertEqual(metadata.xmPatterns.map(\.index), [0])
    }

    func testLoadedModuleClearSongButtonDoesNotRequestMutationOrEditableCopy() throws {
        var loadedPattern = makePattern(index: 0, rowCount: 16)
        loadedPattern.rows[3][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let metadata = makeLoadedMetadata(
            orderTable: [0],
            patterns: [loadedPattern]
        )
        let before = metadata
        let loadedController = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        ))
        let loadedContentView = try XCTUnwrap(loadedController.window?.contentView as? SongOrderEditorContentView)
        let dangerPanel = try identifiedView(SongOrderEditorViewIdentifier.dangerPanel, in: loadedContentView)
        var clearRequestCount = 0
        var editableCopyCreated = false
        loadedController.onClearSongRequested = {
            clearRequestCount += 1
            editableCopyCreated = true
        }

        let clearButton = try button(titled: "⌫ CLEAR SONG", in: dangerPanel)
        XCTAssertFalse(loadedContentView.displayState.isClearSongEnabled)
        XCTAssertFalse(clearButton.isEnabled)
        XCTAssertNil(clearButton.target)
        XCTAssertNil(clearButton.action)

        clearButton.performClick(nil)

        XCTAssertEqual(clearRequestCount, 0)
        XCTAssertFalse(editableCopyCreated)
        XCTAssertEqual(metadata, before)
        XCTAssertEqual(metadata.orderTable, [0])
        XCTAssertEqual(metadata.xmPatterns[0].rows[3][0], loadedPattern.rows[3][0])
    }

    @MainActor
    func testActivePlaybackOrderAndPatternMutationHelpersAreNoOpsWithoutSeekingPlayback() {
        var firstPattern = makePattern(index: 0, rowCount: 16)
        firstPattern.rows[1][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0, 1],
            patterns: [
                firstPattern,
                makePattern(index: 1, rowCount: 16),
            ]
        )
        let before = document
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 1, patternIndex: 1, row: 0)

        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: false, timingSession: nil)
        let positionBeforeMutation = engine.currentPosition
        let configuredPlanCountBeforeMutation = audioOutput.configuredPlans.count

        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentInsertingOrderAfterSelected(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentDeletingSelectedOrder(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentDuplicatingSelectedOrder(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentMovingSelectedOrderUp(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentMovingSelectedOrderDown(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentSteppingSelectedOrderPattern(
            document,
            delta: 1,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentCreatingBlankPatternForEditing(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentDuplicatingCurrentPatternForEditing(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentClearingCurrentPatternForEditing(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocumentClearingSongDataForEditing(
            document,
            isPlaybackActive: engine.state.isPlaying
        ))
        XCTAssertFalse(SongOrderEditorDisplayState.editableDocument(
            document,
            isOrderMutationEnabled: false
        ).isClearSongEnabled)
        XCTAssertEqual(document, before)
        XCTAssertEqual(document.pattern(for: 0), firstPattern)
        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertEqual(engine.currentPosition, positionBeforeMutation)
        XCTAssertEqual(audioOutput.configuredPlans.count, configuredPlanCountBeforeMutation)
    }

    func testOrderNavigationIgnoresCurrentOrderAndActivePlayback() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 16),
            ]
        )
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0, 1],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 16),
            ]
        )

        XCTAssertNil(SongOrderEditorNavigation.loadedModuleSelection(
            selectingOrderPosition: 0,
            metadata: metadata,
            currentOrderPosition: 0,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.loadedModuleSelection(
            selectingOrderPosition: 1,
            metadata: metadata,
            currentOrderPosition: 0,
            isPlaybackActive: true
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            selectingOrderPosition: 0,
            isPlaybackActive: false
        ))
        XCTAssertNil(SongOrderEditorNavigation.editableDocument(
            document,
            selectingOrderPosition: 1,
            isPlaybackActive: true
        ))
    }

    func testOrderRowClickRequestsNavigationAndCanRefreshSelectionAndPatternBank() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 64],
            patterns: makeContiguousPatterns(through: 64),
            patternCount: 65
        )
        let controller = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var selectedOrders = [Int]()
        controller.onOrderSelected = { orderPosition in
            selectedOrders.append(orderPosition)
            controller.apply(displayState: .loadedModule(
                metadata: metadata,
                selectedOrderPosition: orderPosition,
                currentPatternIndex: metadata.orderTable[orderPosition]
            ))
        }

        try clickOrderRow("000", in: contentView)
        XCTAssertEqual(selectedOrders, [])

        try clickOrderRow("001", in: contentView)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 64 })

        XCTAssertEqual(selectedOrders, [1])
        XCTAssertEqual(contentView.displayState.selectedOrderPosition, 1)
        XCTAssertEqual(contentView.displayState.selectedPatternIndex, 64)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.isSelected), [false, true])
        XCTAssertEqual(contentView.displayState.bankIndex, 1)
        XCTAssertEqual(contentView.displayState.bankDisplayLabel, "BANK 2/2")
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternCellClickRequestsNavigationAndRefreshesCurrentHighlightWithoutChangingOrderRows() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 2],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 1, rowCount: 24),
                makePattern(index: 2, rowCount: 32),
            ],
            patternCount: 3
        )
        let before = metadata
        let controller = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 0,
            currentPatternIndex: 0
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var selectedPatterns = [Int]()
        controller.onPatternSelected = { patternIndex in
            selectedPatterns.append(patternIndex)
            controller.apply(displayState: .loadedModule(
                metadata: metadata,
                selectedOrderPosition: 0,
                currentPatternIndex: patternIndex
            ))
        }

        try clickPatternCell("010", in: contentView)
        XCTAssertEqual(selectedPatterns, [])

        try clickPatternCell("001", in: contentView)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 1 })

        XCTAssertEqual(selectedPatterns, [1])
        XCTAssertEqual(contentView.displayState.selectedOrderPosition, 0)
        XCTAssertEqual(contentView.displayState.selectedPatternIndex, 1)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.patternIndex), [0, 2])
        XCTAssertEqual(contentView.displayState.orderRows.map(\.isSelected), [true, false])
        XCTAssertTrue(currentCell.exists)
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
        XCTAssertEqual(metadata, before)
    }

    func testPatternCellDoubleClickRequestsEditableAssignmentAndRefreshesSelectedOrder() throws {
        var document = makeBlankDocument(
            currentPosition: 1,
            currentPatternIndex: 0,
            orderTable: [0, 0],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 2, rowCount: 32),
            ]
        )
        let beforePatterns = document.patterns
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var selectedPatterns = [Int]()
        var assignedPatterns = [Int]()
        controller.onPatternSelected = { patternIndex in
            selectedPatterns.append(patternIndex)
        }
        controller.onPatternDoubleClickedForAssignment = { patternIndex in
            assignedPatterns.append(patternIndex)
            guard let updated = SongOrderEditorNavigation.editableDocument(
                document,
                assigningPatternIndexToSelectedOrder: patternIndex,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }

        try clickPatternCell("002", in: contentView)
        XCTAssertEqual(selectedPatterns, [2])
        XCTAssertEqual(assignedPatterns, [])
        XCTAssertEqual(document.orderTable, [0, 0])

        try doubleClickPatternCell("002", in: contentView)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 2 })

        XCTAssertEqual(selectedPatterns, [2])
        XCTAssertEqual(assignedPatterns, [2])
        XCTAssertEqual(document.orderTable, [0, 2])
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 2)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.patternIndex), [0, 2])
        XCTAssertEqual(contentView.displayState.orderRows.map(\.isSelected), [false, true])
        XCTAssertTrue(currentCell.exists)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternCellDoubleClickAssignmentStillWorksAfterCreatingNewPatterns() throws {
        var document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [makePattern(index: 0, rowCount: 16)]
        )
        XCTAssertTrue(document.createBlankPatternAndSelectForEditing())
        XCTAssertTrue(document.createBlankPatternAndSelectForEditing())
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPatternIndex, 2)
        var selectedPatterns = [Int]()
        var assignedPatterns = [Int]()
        controller.onPatternSelected = { patternIndex in
            selectedPatterns.append(patternIndex)
            guard let updated = SongOrderEditorNavigation.editableDocument(
                document,
                selectingPatternIndex: patternIndex,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }
        controller.onPatternDoubleClickedForAssignment = { patternIndex in
            assignedPatterns.append(patternIndex)
            guard let updated = SongOrderEditorNavigation.editableDocument(
                document,
                assigningPatternIndexToSelectedOrder: patternIndex,
                isPlaybackActive: false
            ) else {
                return
            }
            document = updated
            controller.apply(displayState: .editableDocument(updated))
        }

        try clickPatternCell("001", in: contentView)
        XCTAssertEqual(selectedPatterns, [1])
        XCTAssertEqual(assignedPatterns, [])
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPatternIndex, 1)

        try doubleClickPatternCell("001", in: contentView)
        XCTAssertEqual(document.orderTable, [1])

        try doubleClickPatternCell("002", in: contentView)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 2 })

        XCTAssertEqual(selectedPatterns, [1])
        XCTAssertEqual(assignedPatterns, [1, 2])
        XCTAssertEqual(document.orderTable, [2])
        XCTAssertEqual(document.currentPatternIndex, 2)
        XCTAssertTrue(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternCellDoubleClickLoadedModuleCanNavigateButDoesNotMutateOrderTable() throws {
        let metadata = makeLoadedMetadata(
            orderTable: [0, 7],
            patterns: [
                makePattern(index: 0, rowCount: 16),
                makePattern(index: 7, rowCount: 32),
                makePattern(index: 42, rowCount: 48),
            ],
            patternCount: 43
        )
        let before = metadata
        let controller = SongOrderEditorWindowController(displayState: .loadedModule(
            metadata: metadata,
            selectedOrderPosition: 1,
            currentPatternIndex: 7
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var assignedPatterns = [Int]()
        controller.onPatternDoubleClickedForAssignment = { patternIndex in
            assignedPatterns.append(patternIndex)
            guard let selectedPatternIndex = SongOrderEditorNavigation.loadedModulePatternSelection(
                selectingPatternIndex: patternIndex,
                metadata: metadata,
                currentPatternIndex: 7,
                isPlaybackActive: false
            ) else {
                return
            }
            controller.apply(displayState: .loadedModule(
                metadata: metadata,
                selectedOrderPosition: 1,
                currentPatternIndex: selectedPatternIndex
            ))
        }

        try doubleClickPatternCell("042", in: contentView)
        let currentCell = try XCTUnwrap(contentView.displayState.patternBankCells.first { $0.patternIndex == 42 })

        XCTAssertEqual(assignedPatterns, [42])
        XCTAssertEqual(metadata, before)
        XCTAssertEqual(contentView.displayState.selectedOrderPosition, 1)
        XCTAssertEqual(contentView.displayState.orderRows.map(\.patternIndex), [0, 7])
        XCTAssertEqual(contentView.displayState.orderRows.map(\.isSelected), [false, true])
        XCTAssertFalse(currentCell.isUsed)
        XCTAssertTrue(currentCell.isCurrent)
    }

    func testPatternCellDoubleClickEmptyCellIsNoOp() throws {
        let document = makeBlankDocument(
            currentPosition: 0,
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: [makePattern(index: 0, rowCount: 16)]
        )
        let controller = SongOrderEditorWindowController(displayState: .editableDocument(document))
        let contentView = try XCTUnwrap(controller.window?.contentView as? SongOrderEditorContentView)
        var selectedPatterns = [Int]()
        var assignedPatterns = [Int]()
        controller.onPatternSelected = { selectedPatterns.append($0) }
        controller.onPatternDoubleClickedForAssignment = { assignedPatterns.append($0) }

        try doubleClickPatternCell("012", in: contentView)

        XCTAssertEqual(selectedPatterns, [])
        XCTAssertEqual(assignedPatterns, [])
        XCTAssertEqual(contentView.displayState, .editableDocument(document))
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

private func makeContiguousPatterns(through lastIndex: Int) -> [XMPatternData] {
    (0...max(0, lastIndex)).map { patternIndex in
        makePattern(index: patternIndex, rowCount: patternIndex == lastIndex ? 32 : 16)
    }
}

private func makeBlankDocument(
    currentPosition: Int = BlankTrackerDocument.defaultCurrentPosition,
    currentPatternIndex: Int = BlankTrackerDocument.defaultPatternIndex,
    orderTable: [Int] = [BlankTrackerDocument.defaultPatternIndex],
    patterns: [XMPatternData] = [BlankTrackerDocument.makeEmptyPattern(index: BlankTrackerDocument.defaultPatternIndex)],
    tempo: Int = BlankTrackerDocument.defaultTempo,
    speed: Int = BlankTrackerDocument.defaultSpeed,
    selection: TrackerEditorSelection = .default,
    instrumentPalette: [Int: PlaybackInstrument] = [:]
) -> BlankTrackerDocument {
    BlankTrackerDocument(
        title: BlankTrackerDocument.defaultTitle,
        songLength: orderTable.count,
        currentPosition: currentPosition,
        restartPosition: BlankTrackerDocument.defaultRestartPosition,
        currentPatternIndex: currentPatternIndex,
        tempo: tempo,
        speed: speed,
        orderTable: orderTable,
        selection: selection,
        instrumentPalette: instrumentPalette,
        patterns: patterns
    )
}

@MainActor
private func identifiedView(_ identifier: String, in view: NSView) throws -> NSView {
    let matchingView = view.allDescendants
        .first { $0.identifier?.rawValue == identifier }
    return try XCTUnwrap(matchingView)
}

@MainActor
private func button(titled title: String, in view: NSView) throws -> VTXEditorButton {
    let matchingButton = view.allDescendants
        .compactMap { $0 as? VTXEditorButton }
        .first { $0.title == title }
    return try XCTUnwrap(matchingButton)
}

@MainActor
private func buttons(titled title: String, in view: NSView) throws -> [VTXEditorButton] {
    let matchingButtons = view.allDescendants
        .compactMap { $0 as? VTXEditorButton }
        .filter { $0.title == title }
    XCTAssertFalse(matchingButtons.isEmpty, "Missing \(title)")
    return matchingButtons
}

@MainActor
private func textField(_ value: String, in view: NSView) throws -> NSTextField {
    let matchingField = view.allDescendants
        .compactMap { $0 as? NSTextField }
        .first { $0.stringValue == value }
    return try XCTUnwrap(matchingField)
}

@MainActor
private func orderListScrollView(in view: NSView) throws -> NSScrollView {
    let scrollView = view.allDescendants.compactMap { $0 as? NSScrollView }.first
    return try XCTUnwrap(scrollView)
}

@MainActor
private func clickOrderRow(_ orderDisplay: String, in view: NSView) throws {
    let row = try XCTUnwrap(view.allDescendants
        .compactMap { $0 as? SongOrderEditorOrderRowView }
        .first { $0.identifier?.rawValue == SongOrderEditorViewIdentifier.orderRowPrefix + orderDisplay })
    let event = try XCTUnwrap(NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: NSPoint(x: row.bounds.midX, y: row.bounds.midY),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: row.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    ))
    row.mouseDown(with: event)
}

@MainActor
private func clickPatternCell(_ patternDisplay: String, in view: NSView) throws {
    try mouseDownPatternCell(patternDisplay, in: view, clickCount: 1)
}

@MainActor
private func doubleClickPatternCell(_ patternDisplay: String, in view: NSView) throws {
    try mouseDownPatternCell(patternDisplay, in: view, clickCount: 2)
}

@MainActor
private func mouseDownPatternCell(_ patternDisplay: String, in view: NSView, clickCount: Int) throws {
    let cell = try XCTUnwrap(view.allDescendants
        .compactMap { $0 as? SongOrderEditorPatternCellView }
        .first { $0.identifier?.rawValue == SongOrderEditorViewIdentifier.patternCellPrefix + patternDisplay })
    let event = try XCTUnwrap(NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: NSPoint(x: cell.bounds.midX, y: cell.bounds.midY),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: cell.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    ))
    cell.mouseDown(with: event)
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

@MainActor
private func assertAttributedForegroundColor(
    _ textField: NSTextField,
    at index: Int,
    matches expected: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actual = textField.attributedStringValue.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor else {
        XCTFail("Missing foreground color", file: file, line: line)
        return
    }

    assertColor(actual, matches: expected, file: file, line: line)
}

private func assertColor(
    _ actual: NSColor,
    matches expected: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actualColor = actual.usingColorSpace(.sRGB),
          let expectedColor = expected.usingColorSpace(.sRGB) else {
        XCTFail("Missing sRGB color", file: file, line: line)
        return
    }

    XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actualColor.alphaComponent, expectedColor.alphaComponent, accuracy: 0.001, file: file, line: line)
}
