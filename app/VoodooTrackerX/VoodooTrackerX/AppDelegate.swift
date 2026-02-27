import AppKit
import UniformTypeIdentifiers

private enum PatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
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
        case 115:
            navigationHandler?(.home)
        case 119:
            navigationHandler?(.end)
        case 123:
            navigationHandler?(.left)
        case 124:
            navigationHandler?(.right)
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
    private var showAllPatternsCheckbox: NSButton?
    private var loadedMetadata: ParsedModuleMetadata?
    private var displayedPatternEntries = [ModuleMetadataLoader.PatternSelectionEntry]()
    private var invalidReferencedPatternIndices = [Int]()
    private var selectedDropdownIndex = 0
    private var currentPatternIndex = 0
    private var highlightedRowIndex = 0
    private var currentChannelIndex = 0
    private var rowRanges = [NSRange]()
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
        if let metadataTextView {
            mainWindow?.makeFirstResponder(metadataTextView)
        }
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

        let selector = NSPopUpButton(frame: NSRect(x: 20, y: initialWindowSize.height - 68, width: 220, height: 28))
        selector.autoresizingMask = [.maxXMargin, .minYMargin]
        selector.target = self
        selector.action = #selector(patternSelectionChanged(_:))
        selector.isHidden = true
        contentView.addSubview(selector)
        patternSelector = selector

        let showAllCheckbox = NSButton(checkboxWithTitle: "Show all patterns", target: self, action: #selector(showAllPatternsToggled(_:)))
        showAllCheckbox.frame = NSRect(x: 250, y: initialWindowSize.height - 68, width: 180, height: 28)
        showAllCheckbox.autoresizingMask = [.maxXMargin, .minYMargin]
        showAllCheckbox.state = .off
        showAllCheckbox.isHidden = true
        contentView.addSubview(showAllCheckbox)
        showAllPatternsCheckbox = showAllCheckbox

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: initialWindowSize.width - 40, height: initialWindowSize.height - 96))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = PatternTextView(frame: scrollView.bounds)
        textView.autoresizingMask = []
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byClipping
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
            selectedDropdownIndex = 0
            currentPatternIndex = 0
            highlightedRowIndex = 0
            currentChannelIndex = 0

            if metadata.type == "XM", !metadata.xmPatterns.isEmpty {
                showAllPatternsCheckbox?.isHidden = false
                updatePatternSelector(for: metadata, keepPattern: nil)
                renderCurrentPattern(metadata: metadata)
            } else {
                patternSelector?.removeAllItems()
                patternSelector?.isHidden = true
                showAllPatternsCheckbox?.isHidden = true
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
        selectedDropdownIndex = max(0, sender.indexOfSelectedItem)
        guard displayedPatternEntries.indices.contains(selectedDropdownIndex) else {
            return
        }
        currentPatternIndex = displayedPatternEntries[selectedDropdownIndex].patternIndex
        highlightedRowIndex = 0
        currentChannelIndex = 0
        renderCurrentPattern(metadata: metadata)
    }

    @objc
    private func showAllPatternsToggled(_ sender: NSButton) {
        guard let metadata = loadedMetadata else {
            return
        }
        updatePatternSelector(for: metadata, keepPattern: currentPatternIndex)
        renderCurrentPattern(metadata: metadata)
    }

    private func updatePatternSelector(for metadata: ParsedModuleMetadata, keepPattern: Int?) {
        guard let selector = patternSelector else {
            return
        }
        let rowCounts = metadata.xmPatterns.map(\.rowCount)
        let selection = ModuleMetadataLoader.buildPatternSelection(
            orderTable: metadata.orderTable,
            patternCount: metadata.xmPatterns.count,
            rowCounts: rowCounts,
            showAllPatterns: showAllPatternsCheckbox?.state == .on
        )
        displayedPatternEntries = selection.entries
        invalidReferencedPatternIndices = selection.invalidReferencedPatterns

        selector.removeAllItems()
        for entry in displayedPatternEntries {
            let status = entry.isUsed ? "used" : "all"
            selector.addItem(withTitle: String(format: "P%02d (%@, %d rows)", entry.patternIndex, status, entry.rowCount))
        }
        guard !displayedPatternEntries.isEmpty else {
            selector.isHidden = true
            return
        }

        if let keepPattern, let index = displayedPatternEntries.firstIndex(where: { $0.patternIndex == keepPattern }) {
            selectedDropdownIndex = index
        } else {
            selectedDropdownIndex = 0
        }
        currentPatternIndex = displayedPatternEntries[selectedDropdownIndex].patternIndex
        selector.selectItem(at: selectedDropdownIndex)
        selector.isHidden = false
    }

    private func renderCurrentPattern(metadata: ParsedModuleMetadata) {
        guard metadata.type == "XM", metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }
        let pattern = metadata.xmPatterns[currentPatternIndex]
        if pattern.rowCount == 0 {
            metadataTextView?.string = "Pattern \(pattern.index) is empty."
            return
        }

        highlightedRowIndex = min(max(0, highlightedRowIndex), pattern.rowCount - 1)
        currentChannelIndex = min(max(0, currentChannelIndex), pattern.channels - 1)
        let rendered = ModuleMetadataLoader.renderXMPattern(
            pattern,
            highlightedRow: highlightedRowIndex,
            focusedChannel: currentChannelIndex
        )
        rowRanges = rendered.rowRanges

        let fullText: String
        let rowRangeOffset: Int
        if invalidReferencedPatternIndices.isEmpty {
            fullText = rendered.text
            rowRangeOffset = 0
        } else {
            let invalidList = invalidReferencedPatternIndices.map(String.init).joined(separator: ", ")
            let warning = "Warning: Ignored out-of-range order entries: \(invalidList)\n\n"
            fullText = warning + rendered.text
            rowRangeOffset = warning.utf16.count
        }

        let attributed = NSMutableAttributedString(string: fullText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .ligature: 0,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        if rowRanges.indices.contains(highlightedRowIndex) {
            let range = rowRanges[highlightedRowIndex]
            let shifted = NSRange(location: range.location + rowRangeOffset, length: range.length)
            attributed.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35), range: shifted)
        }
        metadataTextView?.textStorage?.setAttributedString(attributed)
        updateMetadataTextViewDocumentSize()
        if let textView = metadataTextView {
            mainWindow?.makeFirstResponder(textView)
        }
        scrollHighlightedRowIntoView(offset: rowRangeOffset)
    }

    private func handlePatternNavigation(_ command: PatternNavigationCommand) {
        guard let metadata = loadedMetadata, metadata.type == "XM",
              metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }

        let pattern = metadata.xmPatterns[currentPatternIndex]
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
        case .home:
            highlightedRowIndex = 0
        case .end:
            highlightedRowIndex = pattern.rowCount - 1
        case .left:
            currentChannelIndex = max(0, currentChannelIndex - 1)
        case .right:
            currentChannelIndex = min(pattern.channels - 1, currentChannelIndex + 1)
        }

        renderCurrentPattern(metadata: metadata)
    }

    private func scrollHighlightedRowIntoView(offset: Int) {
        guard rowRanges.indices.contains(highlightedRowIndex),
              let textView = metadataTextView else {
            return
        }
        let rowRange = rowRanges[highlightedRowIndex]
        let clampedChannel = max(0, currentChannelIndex)
        let channelOffset = ModuleMetadataLoader.xmRenderedRowPrefixWidth +
            clampedChannel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let maxLocation = rowRange.location + max(0, rowRange.length - 1)
        let targetLocation = min(maxLocation, rowRange.location + channelOffset)
        let range = NSRange(location: targetLocation + offset, length: max(1, ModuleMetadataLoader.xmRenderedCellWidth))
        textView.scrollRangeToVisible(range)
    }

    private func updateMetadataTextViewDocumentSize() {
        guard let textView = metadataTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer).integral
        let inset = textView.textContainerInset
        let contentWidth = usedRect.width + inset.width * 2 + 8
        let contentHeight = usedRect.height + inset.height * 2 + 8
        let viewport = textView.enclosingScrollView?.contentView.bounds.size ?? .zero

        let targetSize = NSSize(
            width: max(viewport.width, contentWidth),
            height: max(viewport.height, contentHeight)
        )
        textView.setFrameSize(targetSize)
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
