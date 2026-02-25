import AppKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var metadataTextView: NSTextView?
    private let metadataLoader = ModuleMetadataLoader()
    private let initialWindowSize = NSSize(width: 1000, height: 700)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        createMainWindow()
        showAndActivateMainWindow()
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
        let contentView = NSView(frame: NSRect(origin: .zero, size: initialWindowSize))

        let titleLabel = NSTextField(labelWithString: "VoodooTracker X")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.frame = NSRect(x: 20, y: initialWindowSize.height - 42, width: 400, height: 24)
        titleLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(titleLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: initialWindowSize.width - 40, height: initialWindowSize.height - 74))
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

        self.window = window
    }

    private func showAndActivateMainWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
