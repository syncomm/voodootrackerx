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

    func testFileMenuWiresNewOpenEditableCopyExportXMAndExportAudioWhileKeepingSaveDisabled() throws {
        let target = NSObject()
        let fileMenu = try XCTUnwrap(ApplicationMenuBuilder.build(target: target).mainMenu.submenu(titled: "File"))

        XCTAssertEqual(
            fileMenu.items.map(\.title),
            ["New", "Open...", "Make Editable Copy", "", "Save", "Save As...", "Export XM...", "Export Audio", "", "Close"]
        )
        XCTAssertTrue(fileMenu.items[3].isSeparatorItem)
        XCTAssertTrue(fileMenu.items[8].isSeparatorItem)

        XCTAssertEqual(fileMenu.item(withTitle: "New")?.action, ApplicationMenuBuilder.Actions.newTrackerDocument)
        XCTAssertEqual(fileMenu.item(withTitle: "Open...")?.action, ApplicationMenuBuilder.Actions.openModuleFile)
        XCTAssertEqual(fileMenu.item(withTitle: "Make Editable Copy")?.action, ApplicationMenuBuilder.Actions.makeEditableCopy)
        XCTAssertTrue(fileMenu.item(withTitle: "Make Editable Copy")?.target === target)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save As...")).isEnabled)

        let exportXM = try XCTUnwrap(fileMenu.item(withTitle: "Export XM..."))
        XCTAssertEqual(exportXM.action, ApplicationMenuBuilder.Actions.exportXM)
        XCTAssertTrue(exportXM.target === target)
        XCTAssertEqual(exportXM.keyEquivalent, "")
        XCTAssertNil(fileMenu.item(withTitle: "Export"))
        XCTAssertNil(fileMenu.item(withTitle: "Export..."))

        let exportAudio = try XCTUnwrap(fileMenu.item(withTitle: "Export Audio")?.submenu)
        let exportWAV = try XCTUnwrap(exportAudio.item(withTitle: "WAV..."))
        XCTAssertEqual(exportWAV.action, ApplicationMenuBuilder.Actions.exportWAV)
        XCTAssertTrue(exportWAV.target === target)
        XCTAssertEqual(exportWAV.keyEquivalent, "")
        let exportM4A = try XCTUnwrap(exportAudio.item(withTitle: "M4A..."))
        XCTAssertEqual(exportM4A.action, ApplicationMenuBuilder.Actions.exportM4A)
        XCTAssertTrue(exportM4A.target === target)
        XCTAssertEqual(exportM4A.keyEquivalent, "")
    }

    func testFileMenuKeepsSaveAndSaveAsDisabledWithNilTarget() throws {
        let fileMenu = try XCTUnwrap(ApplicationMenuBuilder.build(target: nil).mainMenu.submenu(titled: "File"))

        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save As...")).isEnabled)
    }

    func testEditMenuWiresUndoRedoWhileKeepingOtherFutureCommandsDisabled() throws {
        let target = NSObject()
        let editMenu = try XCTUnwrap(ApplicationMenuBuilder.build(target: target).mainMenu.submenu(titled: "Edit"))

        let undo = try XCTUnwrap(editMenu.item(withTitle: "Undo"))
        XCTAssertEqual(undo.action, ApplicationMenuBuilder.Actions.undoDocumentEdit)
        XCTAssertTrue(undo.target === target)
        XCTAssertEqual(undo.keyEquivalent, "z")
        XCTAssertFalse(undo.isEnabled)

        let redo = try XCTUnwrap(editMenu.item(withTitle: "Redo"))
        XCTAssertEqual(redo.action, ApplicationMenuBuilder.Actions.redoDocumentEdit)
        XCTAssertTrue(redo.target === target)
        XCTAssertEqual(redo.keyEquivalent, "Z")
        XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertFalse(redo.isEnabled)

        let newInstrument = try XCTUnwrap(editMenu.item(withTitle: "New Instrument"))
        XCTAssertEqual(newInstrument.action, ApplicationMenuBuilder.Actions.newInstrument)
        XCTAssertTrue(newInstrument.target === target)
        XCTAssertEqual(newInstrument.keyEquivalent, "")
        XCTAssertFalse(newInstrument.isEnabled)

        let duplicateSample = try XCTUnwrap(editMenu.item(withTitle: "Duplicate Sample"))
        XCTAssertEqual(duplicateSample.action, ApplicationMenuBuilder.Actions.duplicateSample)
        XCTAssertTrue(duplicateSample.target === target)
        XCTAssertEqual(duplicateSample.keyEquivalent, "")
        XCTAssertFalse(duplicateSample.isEnabled)

        let moveSample = try XCTUnwrap(editMenu.item(withTitle: "Move Sample…"))
        XCTAssertEqual(moveSample.action, ApplicationMenuBuilder.Actions.moveSample)
        XCTAssertTrue(moveSample.target === target)
        XCTAssertEqual(moveSample.keyEquivalent, "")
        XCTAssertFalse(moveSample.isEnabled)

        for title in ["Cut", "Copy", "Paste", "Delete", "Select All"] {
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
        XCTAssertEqual(transportMenu.item(withTitle: "Play Current Pattern")?.action, ApplicationMenuBuilder.Actions.playCurrentPattern)
        XCTAssertEqual(transportMenu.item(withTitle: "Stop")?.action, ApplicationMenuBuilder.Actions.stop)
        XCTAssertEqual(transportMenu.item(withTitle: "Loop")?.action, ApplicationMenuBuilder.Actions.toggleLoop)
        XCTAssertEqual(transportMenu.item(withTitle: "Edit Mode")?.action, ApplicationMenuBuilder.Actions.toggleEditMode)

        for title in ["Play", "Play Current Pattern", "Stop", "Loop", "Edit Mode"] {
            XCTAssertEqual(transportMenu.item(withTitle: title)?.keyEquivalent, "")
        }
    }

    func testWindowMenuWiresEditorWindowsWithoutKeyboardShortcuts() throws {
        let target = NSObject()
        let windowMenu = ApplicationMenuBuilder.build(target: target).windowMenu

        let songOrder = try XCTUnwrap(windowMenu.item(withTitle: "Song / Order Editor"))
        XCTAssertEqual(songOrder.action, ApplicationMenuBuilder.Actions.showSongOrderEditor)
        XCTAssertTrue(songOrder.target === target)
        XCTAssertEqual(songOrder.keyEquivalent, "")
        XCTAssertTrue(songOrder.isEnabled)

        let instrument = try XCTUnwrap(windowMenu.item(withTitle: "Instrument Editor"))
        XCTAssertEqual(instrument.action, ApplicationMenuBuilder.Actions.showInstrumentEditor)
        XCTAssertTrue(instrument.target === target)
        XCTAssertEqual(instrument.keyEquivalent, "")
        XCTAssertTrue(instrument.isEnabled)

        let sample = try XCTUnwrap(windowMenu.item(withTitle: "Sample Editor"))
        XCTAssertEqual(sample.action, ApplicationMenuBuilder.Actions.showSampleEditor)
        XCTAssertTrue(sample.target === target)
        XCTAssertEqual(sample.keyEquivalent, "")
        XCTAssertTrue(sample.isEnabled)
    }
}

private extension NSMenu {
    func submenu(titled title: String) -> NSMenu? {
        item(withTitle: title)?.submenu
    }
}
