import AppKit

enum ApplicationMenuBuilder {
    enum Actions {
        static let newTrackerDocument = NSSelectorFromString("newTrackerDocument:")
        static let openModuleFile = NSSelectorFromString("openModuleFile:")
        static let play = NSSelectorFromString("playPressed:")
        static let stop = NSSelectorFromString("stopPressed:")
        static let toggleLoop = NSSelectorFromString("loopToggled:")
        static let toggleEditMode = NSSelectorFromString("editModeToggled:")
        static let clearCurrentPattern = NSSelectorFromString("clearCurrentPattern:")
        static let clearSongData = NSSelectorFromString("clearSongData:")
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
        let windowMenu = Self.windowMenu()
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledItem(title: "Save", keyEquivalent: "s"))
        let saveAs = disabledItem(title: "Save As...", keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(saveAs)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func editMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(disabledItem(title: "Undo", keyEquivalent: "z"))
        let redo = disabledItem(title: "Redo", keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
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
        menu.addItem(menuItem(title: "Stop", action: Actions.stop, keyEquivalent: "", target: target))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Loop", action: Actions.toggleLoop, keyEquivalent: "", target: target))
        menu.addItem(menuItem(title: "Edit Mode", action: Actions.toggleEditMode, keyEquivalent: "", target: target))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
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
