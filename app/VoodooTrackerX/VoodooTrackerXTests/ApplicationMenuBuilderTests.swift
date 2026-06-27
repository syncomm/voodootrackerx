import AppKit
import XCTest

@MainActor
final class ApplicationMenuBuilderTests: XCTestCase {
    func testBuildsExpectedTopLevelMenus() {
        let builtMenu = ApplicationMenuBuilder.build(target: nil)

        XCTAssertEqual(
            builtMenu.mainMenu.items.map(\.title),
            ["VoodooTracker X", "File", "Edit", "View", "Transport", "Window", "Help"]
        )
        XCTAssertEqual(builtMenu.windowMenu.title, "Window")
    }

    func testFileMenuWiresNewAndOpenWithoutSaveOrExportBehavior() throws {
        let fileMenu = try XCTUnwrap(ApplicationMenuBuilder.build(target: nil).mainMenu.submenu(titled: "File"))

        XCTAssertEqual(fileMenu.item(withTitle: "New")?.action, ApplicationMenuBuilder.Actions.newTrackerDocument)
        XCTAssertEqual(fileMenu.item(withTitle: "Open...")?.action, ApplicationMenuBuilder.Actions.openModuleFile)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save As...")).isEnabled)
        XCTAssertNil(fileMenu.item(withTitle: "Export"))
        XCTAssertNil(fileMenu.item(withTitle: "Export..."))
    }

    func testEditMenuFutureCommandsAreDisabledPlaceholdersAndEditorUtilitiesAreWired() throws {
        let editMenu = try XCTUnwrap(ApplicationMenuBuilder.build(target: nil).mainMenu.submenu(titled: "Edit"))

        for title in ["Undo", "Redo", "Cut", "Copy", "Paste", "Delete", "Select All"] {
            let item = try XCTUnwrap(editMenu.item(withTitle: title))
            XCTAssertFalse(item.isEnabled, "\(title) should stay disabled until editor behavior exists")
            XCTAssertNil(item.action, "\(title) should not introduce editor behavior")
        }

        let clearCurrentPattern = try XCTUnwrap(editMenu.item(withTitle: "Clear Current Pattern"))
        XCTAssertEqual(clearCurrentPattern.action, ApplicationMenuBuilder.Actions.clearCurrentPattern)
        XCTAssertEqual(clearCurrentPattern.keyEquivalent, "")
        XCTAssertFalse(clearCurrentPattern.isEnabled)

        let clearSongData = try XCTUnwrap(editMenu.item(withTitle: "Clear Song Data"))
        XCTAssertEqual(clearSongData.action, ApplicationMenuBuilder.Actions.clearSongData)
        XCTAssertEqual(clearSongData.keyEquivalent, "")
        XCTAssertFalse(clearSongData.isEnabled)
    }

    func testTransportMenuUsesExistingActionsWithoutKeyboardShortcuts() throws {
        let transportMenu = try XCTUnwrap(ApplicationMenuBuilder.build(target: nil).mainMenu.submenu(titled: "Transport"))

        XCTAssertEqual(transportMenu.item(withTitle: "Play")?.action, ApplicationMenuBuilder.Actions.play)
        XCTAssertEqual(transportMenu.item(withTitle: "Stop")?.action, ApplicationMenuBuilder.Actions.stop)
        XCTAssertEqual(transportMenu.item(withTitle: "Loop")?.action, ApplicationMenuBuilder.Actions.toggleLoop)
        XCTAssertEqual(transportMenu.item(withTitle: "Edit Mode")?.action, ApplicationMenuBuilder.Actions.toggleEditMode)

        for title in ["Play", "Stop", "Loop", "Edit Mode"] {
            XCTAssertEqual(transportMenu.item(withTitle: title)?.keyEquivalent, "")
        }
    }

    func testWindowMenuWiresSongOrderEditorWithoutKeyboardShortcut() throws {
        let target = NSObject()
        let windowMenu = ApplicationMenuBuilder.build(target: target).windowMenu

        let item = try XCTUnwrap(windowMenu.item(withTitle: "Song / Order Editor"))
        XCTAssertEqual(item.action, ApplicationMenuBuilder.Actions.showSongOrderEditor)
        XCTAssertTrue(item.target === target)
        XCTAssertEqual(item.keyEquivalent, "")
        XCTAssertTrue(item.isEnabled)
    }
}

private extension NSMenu {
    func submenu(titled title: String) -> NSMenu? {
        item(withTitle: title)?.submenu
    }
}
