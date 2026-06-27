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
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let segmentValues = contentView.allDescendants
            .compactMap { ($0 as? VTXEditorSegmentReadout)?.stringValue }

        XCTAssertTrue(segmentValues.contains("BANK 1/4"))
        XCTAssertGreaterThanOrEqual(contentView.allDescendants.compactMap { $0 as? VTXEditorIndicatorLEDView }.count, 2)
        XCTAssertGreaterThanOrEqual(contentView.allDescendants.compactMap { $0 as? VTXEditorButton }.count, 10)
    }

    func testShellControlsAreVisuallyBrightButActionless() throws {
        let controller = SongOrderEditorWindowController()
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let buttons = contentView.allDescendants.compactMap { $0 as? VTXEditorButton }

        XCTAssertGreaterThanOrEqual(buttons.count, 10)
        XCTAssertTrue(buttons.allSatisfy(\.isEnabled))
        XCTAssertTrue(buttons.allSatisfy { $0.target == nil })
        XCTAssertTrue(buttons.allSatisfy { $0.action == nil })
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

        XCTAssertTrue(fieldValues.contains("BANK 1/4"))
        XCTAssertTrue(fieldValues.contains("— the song sequence"))
        XCTAssertTrue(fieldValues.contains("— act on selected slot (ORD 010)"))
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
}

private extension NSView {
    var allDescendants: [NSView] {
        [self] + subviews.flatMap(\.allDescendants)
    }
}
