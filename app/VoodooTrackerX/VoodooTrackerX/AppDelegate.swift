import AppKit
import UniformTypeIdentifiers

private enum PatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
}

private final class PatternTextView: NSTextView {
    var navigationHandler: ((PatternNavigationCommand) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            navigationHandler?(.up)
        case 125:
            navigationHandler?(.down)
        case 116:
            navigationHandler?(.pageUp)
        case 121:
            navigationHandler?(.pageDown)
        default:
            super.keyDown(with: event)
        }
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private var mainWindow: NSWindow?
    private var metadataTextView: NSTextView?
    private var patternSelector: NSPopUpButton?
    private var loadedMetadata: ParsedModuleMetadata?
    private var selectedPatternIndex = 0
    private var highlightedRowIndex = 0
    private var rowTextOffsets = [Int]()
    private let metadataLoader = ModuleMetadataLoader()
    private let initialWindowSize = NSSize(width: 1000, height: 700)

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    override init() {
        super.init()
        debugLog("AppDelegate initialized")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching entered")
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        if mainWindow == nil {
            createMainWindow()
        }
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
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
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
        debugLog("createMainWindow called")
        let contentView = NSView(frame: NSRect(origin: .zero, size: initialWindowSize))

        let titleLabel = NSTextField(labelWithString: "VoodooTracker X")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.frame = NSRect(x: 20, y: initialWindowSize.height - 42, width: 400, height: 24)
        titleLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(titleLabel)

        let selector = NSPopUpButton(frame: NSRect(x: 20, y: initialWindowSize.height - 68, width: 180, height: 28))
        selector.autoresizingMask = [.maxXMargin, .minYMargin]
        selector.target = self
        selector.action = #selector(patternSelectionChanged(_:))
        selector.isHidden = true
        contentView.addSubview(selector)
        patternSelector = selector

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: initialWindowSize.width - 40, height: initialWindowSize.height - 96))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        let textView = PatternTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.navigationHandler = { [weak self] command in
            self?.handlePatternNavigation(command)
        }
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

        self.mainWindow = window
        debugLog("window created object=\(String(describing: mainWindow)) frame=\(window.frame) isVisible=\(window.isVisible)")
    }

    private func showAndActivateMainWindow() {
        guard let mainWindow else { return }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        debugLog("window shown frame=\(mainWindow.frame) isVisible=\(mainWindow.isVisible)")
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
            loadedMetadata = metadata
            selectedPatternIndex = 0
            highlightedRowIndex = 0

            if metadata.type == "XM", !metadata.xmPatterns.isEmpty {
                updatePatternSelector(for: metadata)
                renderPattern(metadata: metadata, selectedPattern: selectedPatternIndex)
            } else {
                patternSelector?.removeAllItems()
                patternSelector?.isHidden = true
                metadataTextView?.string = """
                File: \(url.lastPathComponent)
                Path: \(url.path)

                \(metadata.displayText)
                """
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to Open Module"
            alert.informativeText = error.localizedDescription
            if let mainWindow {
                alert.beginSheetModal(for: mainWindow)
            } else {
                alert.runModal()
            }
        }
    }

    @objc
    private func patternSelectionChanged(_ sender: NSPopUpButton) {
        guard let metadata = loadedMetadata else {
            return
        }
        selectedPatternIndex = max(0, sender.indexOfSelectedItem)
        highlightedRowIndex = 0
        renderPattern(metadata: metadata, selectedPattern: selectedPatternIndex)
    }

    private func updatePatternSelector(for metadata: ParsedModuleMetadata) {
        guard let selector = patternSelector else {
            return
        }
        selector.removeAllItems()
        for pattern in metadata.xmPatterns {
            selector.addItem(withTitle: "Pattern \(pattern.index)")
        }
        selector.selectItem(at: selectedPatternIndex)
        selector.isHidden = false
    }

    private func renderPattern(
        metadata: ParsedModuleMetadata,
        selectedPattern: Int
    ) {
        guard metadata.type == "XM", metadata.xmPatterns.indices.contains(selectedPattern) else {
            return
        }
        let pattern = metadata.xmPatterns[selectedPattern]
        if pattern.rowCount == 0 {
            metadataTextView?.string = "Pattern \(pattern.index) is empty."
            return
        }

        highlightedRowIndex = min(max(0, highlightedRowIndex), pattern.rowCount - 1)
        let rendered = ModuleMetadataLoader.renderXMPattern(pattern, highlightedRow: highlightedRowIndex)
        rowTextOffsets = rendered.rowOffsets
        metadataTextView?.string = rendered.text
        if let textView = metadataTextView {
            mainWindow?.makeFirstResponder(textView)
        }
        scrollHighlightedRowIntoView()
    }

    private func handlePatternNavigation(_ command: PatternNavigationCommand) {
        guard let metadata = loadedMetadata, metadata.type == "XM",
              metadata.xmPatterns.indices.contains(selectedPatternIndex) else {
            return
        }

        let pattern = metadata.xmPatterns[selectedPatternIndex]
        let pageStep = 16
        switch command {
        case .up:
            highlightedRowIndex = max(0, highlightedRowIndex - 1)
        case .down:
            highlightedRowIndex = min(pattern.rowCount - 1, highlightedRowIndex + 1)
        case .pageUp:
            highlightedRowIndex = max(0, highlightedRowIndex - pageStep)
        case .pageDown:
            highlightedRowIndex = min(pattern.rowCount - 1, highlightedRowIndex + pageStep)
        }

        renderPattern(metadata: metadata, selectedPattern: selectedPatternIndex)
    }

    private func scrollHighlightedRowIntoView() {
        guard rowTextOffsets.indices.contains(highlightedRowIndex),
              let textView = metadataTextView else {
            return
        }
        let start = rowTextOffsets[highlightedRowIndex]
        let range = NSRange(location: start, length: 1)
        textView.scrollRangeToVisible(range)
    }

    private func debugLog(_ message: String) {
#if DEBUG
        guard let data = "[VTX DEBUG] \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
        let logURL = URL(fileURLWithPath: "/tmp/vtx-debug-runtime.log")
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
#endif
    }
}
