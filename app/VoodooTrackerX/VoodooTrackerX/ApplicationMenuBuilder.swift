import AppKit

enum ApplicationMenuBuilder {
    enum Actions {
        static let newTrackerDocument = NSSelectorFromString("newTrackerDocument:")
        static let openModuleFile = NSSelectorFromString("openModuleFile:")
        static let makeEditableCopy = NSSelectorFromString("makeEditableCopy:")
        static let exportXM = NSSelectorFromString("exportXM:")
        static let exportWAV = NSSelectorFromString("exportWAV:")
        static let exportM4A = NSSelectorFromString("exportM4A:")
        static let play = NSSelectorFromString("playPressed:")
        static let playCurrentPattern = NSSelectorFromString("playCurrentPatternPressed:")
        static let stop = NSSelectorFromString("stopPressed:")
        static let toggleLoop = NSSelectorFromString("loopToggled:")
        static let toggleEditMode = NSSelectorFromString("editModeToggled:")
        static let undoDocumentEdit = NSSelectorFromString("undoDocumentEdit:")
        static let redoDocumentEdit = NSSelectorFromString("redoDocumentEdit:")
        static let newInstrument = NSSelectorFromString("newInstrument:")
        static let duplicateSample = NSSelectorFromString("duplicateSample:")
        static let moveSample = NSSelectorFromString("moveSample:")
        static let clearCurrentPattern = NSSelectorFromString("clearCurrentPattern:")
        static let clearSongData = NSSelectorFromString("clearSongData:")
        static let showSongOrderEditor = NSSelectorFromString("showSongOrderEditor:")
        static let showInstrumentEditor = NSSelectorFromString("showInstrumentEditor:")
        static let showSampleEditor = NSSelectorFromString("showSampleEditor:")
    }

    struct BuiltMenu {
        let mainMenu: NSMenu
        let windowMenu: NSMenu
    }

    static func build(target: AnyObject?) -> BuiltMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(topLevelItem(title: "VoodooTracker X", submenu: appMenu()))
        mainMenu.addItem(topLevelItem(title: "File", submenu: fileMenu(target: target)))
        mainMenu.addItem(topLevelItem(title: "Edit", submenu: editMenu(target: target)))
        mainMenu.addItem(topLevelItem(title: "View", submenu: viewMenu()))
        mainMenu.addItem(topLevelItem(title: "Transport", submenu: transportMenu(target: target)))
        let windowMenu = Self.windowMenu(target: target)
        mainMenu.addItem(topLevelItem(title: "Window", submenu: windowMenu))
        mainMenu.addItem(topLevelItem(title: "Help", submenu: helpMenu()))

        return BuiltMenu(mainMenu: mainMenu, windowMenu: windowMenu)
    }

    private static func topLevelItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        item.submenu = submenu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About VoodooTracker X", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Hide VoodooTracker X", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit VoodooTracker X", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(menuItem(title: "New", action: Actions.newTrackerDocument, keyEquivalent: "n", target: target))
        menu.addItem(menuItem(title: "Open...", action: Actions.openModuleFile, keyEquivalent: "o", target: target))
        menu.addItem(menuItem(title: "Make Editable Copy", action: Actions.makeEditableCopy, keyEquivalent: "", target: target))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledItem(title: "Save", keyEquivalent: "s"))
        let saveAs = disabledItem(title: "Save As...", keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)
        menu.addItem(menuItem(title: "Export XM...", action: Actions.exportXM, keyEquivalent: "", target: target))
        menu.addItem(exportAudioMenu(target: target))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func exportAudioMenu(target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: "Export Audio", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Export Audio")
        submenu.addItem(menuItem(title: "WAV...", action: Actions.exportWAV, keyEquivalent: "", target: target))
        submenu.addItem(menuItem(title: "M4A...", action: Actions.exportM4A, keyEquivalent: "", target: target))
        item.submenu = submenu
        return item
    }

    private static func editMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "Edit")

        let undo = menuItem(
            title: "Undo",
            action: Actions.undoDocumentEdit,
            keyEquivalent: "z",
            target: target
        )
        undo.isEnabled = false
        menu.addItem(undo)
        let redo = menuItem(
            title: "Redo",
            action: Actions.redoDocumentEdit,
            keyEquivalent: "Z",
            target: target
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.isEnabled = false
        menu.addItem(redo)
        menu.addItem(NSMenuItem.separator())
        let newInstrument = menuItem(
            title: "New Instrument",
            action: Actions.newInstrument,
            keyEquivalent: "",
            target: target
        )
        newInstrument.isEnabled = false
        menu.addItem(newInstrument)
        let duplicateSample = menuItem(
            title: "Duplicate Sample",
            action: Actions.duplicateSample,
            keyEquivalent: "",
            target: target
        )
        duplicateSample.isEnabled = false
        menu.addItem(duplicateSample)
        let moveSample = menuItem(
            title: "Move Sample…",
            action: Actions.moveSample,
            keyEquivalent: "",
            target: target
        )
        moveSample.isEnabled = false
        menu.addItem(moveSample)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledItem(title: "Cut", keyEquivalent: "x"))
        menu.addItem(disabledItem(title: "Copy", keyEquivalent: "c"))
        menu.addItem(disabledItem(title: "Paste", keyEquivalent: "v"))
        menu.addItem(disabledItem(title: "Delete", keyEquivalent: "\u{8}"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledItem(title: "Select All", keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        let clearCurrentPattern = menuItem(
            title: "Clear Current Pattern",
            action: Actions.clearCurrentPattern,
            keyEquivalent: "",
            target: target
        )
        clearCurrentPattern.isEnabled = false
        menu.addItem(clearCurrentPattern)
        let clearSongData = menuItem(
            title: "Clear Song Data",
            action: Actions.clearSongData,
            keyEquivalent: "",
            target: target
        )
        clearSongData.isEnabled = false
        menu.addItem(clearSongData)

        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private static func transportMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "Transport")
        menu.addItem(menuItem(title: "Play", action: Actions.play, keyEquivalent: "", target: target))
        menu.addItem(menuItem(title: "Play Current Pattern", action: Actions.playCurrentPattern, keyEquivalent: "", target: target))
        menu.addItem(menuItem(title: "Stop", action: Actions.stop, keyEquivalent: "", target: target))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Loop", action: Actions.toggleLoop, keyEquivalent: "", target: target))
        menu.addItem(menuItem(title: "Edit Mode", action: Actions.toggleEditMode, keyEquivalent: "", target: target))
        return menu
    }

    private static func windowMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(
            title: "Song / Order Editor",
            action: Actions.showSongOrderEditor,
            keyEquivalent: "",
            target: target
        ))
        menu.addItem(menuItem(
            title: "Instrument Editor",
            action: Actions.showInstrumentEditor,
            keyEquivalent: "",
            target: target
        ))
        menu.addItem(menuItem(
            title: "Sample Editor",
            action: Actions.showSampleEditor,
            keyEquivalent: "",
            target: target
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(disabledItem(title: "VoodooTracker X Help", keyEquivalent: "?"))
        return menu
    }

    private static func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    private static func disabledItem(title: String, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
        item.isEnabled = false
        return item
    }
}
