import AppKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var metadataTextView: NSTextView?
    private let metadataLoader = ModuleMetadataLoader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        createMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        appMenuItem.title = "VoodooTracker X"
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "About VoodooTracker X",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit VoodooTracker X",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "File"
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(
            withTitle: "Open…",
            action: #selector(openModuleFile(_:)),
            keyEquivalent: "o"
        )

        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "Window"
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func createMainWindow() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 640))
        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = """
        VoodooTracker X

        File > Open… to load a .mod or .xm file and inspect parsed header metadata.
        """
        scrollView.documentView = textView
        contentView.addSubview(scrollView)
        metadataTextView = textView

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoodooTracker X"
        window.center()
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    @objc
    private func openModuleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.allowedFileTypes = ["mod", "xm"]
        panel.message = "Choose a MOD or XM module file"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let metadata = try metadataLoader.load(fromPath: url.path)
            metadataTextView?.string = """
            File: \(url.lastPathComponent)
            Path: \(url.path)

            \(metadata.displayText)
            """
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to Open Module"
            alert.informativeText = error.localizedDescription
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }
}
