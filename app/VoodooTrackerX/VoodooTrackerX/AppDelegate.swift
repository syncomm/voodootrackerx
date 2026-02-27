import AppKit
import UniformTypeIdentifiers

enum PatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
}

enum PatternCursorField: Int, CaseIterable {
    case note
    case instrument
    case volume
    case effectType
    case effectParam

    var textOffset: Int {
        switch self {
        case .note:
            return 0
        case .instrument:
            return 4
        case .volume:
            return 7
        case .effectType:
            return 10
        case .effectParam:
            return 11
        }
    }

    var textLength: Int {
        switch self {
        case .note:
            return 3
        case .instrument, .volume, .effectParam:
            return 2
        case .effectType:
            return 1
        }
    }
}

struct PatternCursor: Equatable {
    var row: Int
    var channel: Int
    var field: PatternCursorField

    mutating func clamp(rowCount: Int, channelCount: Int) {
        row = min(max(0, row), max(0, rowCount - 1))
        channel = min(max(0, channel), max(0, channelCount - 1))
    }

    mutating func move(_ command: PatternNavigationCommand, rowCount: Int, channelCount: Int, pageStep: Int = 16) {
        clamp(rowCount: rowCount, channelCount: channelCount)
        switch command {
        case .up:
            row = max(0, row - 1)
        case .down:
            row = min(max(0, rowCount - 1), row + 1)
        case .pageUp:
            row = max(0, row - pageStep)
        case .pageDown:
            row = min(max(0, rowCount - 1), row + pageStep)
        case .home:
            row = 0
        case .end:
            row = max(0, rowCount - 1)
        case .left:
            moveLeft(channelCount: channelCount)
        case .right:
            moveRight(channelCount: channelCount)
        }
    }

    private mutating func moveLeft(channelCount: Int) {
        if let previousField = PatternCursorField(rawValue: field.rawValue - 1) {
            field = previousField
            return
        }
        guard channelCount > 0, channel > 0 else { return }
        channel -= 1
        field = .effectParam
    }

    private mutating func moveRight(channelCount: Int) {
        if let nextField = PatternCursorField(rawValue: field.rawValue + 1) {
            field = nextField
            return
        }
        guard channelCount > 0, channel < channelCount - 1 else { return }
        channel += 1
        field = .note
    }
}

private final class PatternTextView: NSTextView {
    var navigationHandler: ((PatternNavigationCommand) -> Void)?
    var activeFieldRange: NSRange? {
        didSet {
            needsDisplay = true
        }
    }

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let activeFieldRange,
              activeFieldRange.location != NSNotFound,
              let layoutManager,
              let textContainer else {
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: activeFieldRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        let strokeRect = rect.insetBy(dx: -1, dy: -1)
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: strokeRect)
        path.lineWidth = 2
        path.stroke()
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
    private var cursor = PatternCursor(row: 0, channel: 0, field: .note)
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
            cursor = PatternCursor(row: 0, channel: 0, field: .note)

            if metadata.type == "XM", !metadata.xmPatterns.isEmpty {
                showAllPatternsCheckbox?.isHidden = false
                updatePatternSelector(for: metadata, keepPattern: nil)
                renderCurrentPattern(metadata: metadata)
            } else {
                (metadataTextView as? PatternTextView)?.activeFieldRange = nil
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
        cursor = PatternCursor(row: 0, channel: 0, field: .note)
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

        cursor.clamp(rowCount: pattern.rowCount, channelCount: pattern.channels)
        let rendered = ModuleMetadataLoader.renderXMPattern(
            pattern,
            highlightedRow: cursor.row,
            focusedChannel: cursor.channel
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
        if rowRanges.indices.contains(cursor.row) {
            let range = rowRanges[cursor.row]
            let shifted = NSRange(location: range.location + rowRangeOffset, length: range.length)
            attributed.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35), range: shifted)
        }
        metadataTextView?.textStorage?.setAttributedString(attributed)
        updateActiveFieldRange(rowRangeOffset: rowRangeOffset)
        updateMetadataTextViewDocumentSize()
        if let textView = metadataTextView {
            mainWindow?.makeFirstResponder(textView)
        }
        scrollCursorIntoView(offset: rowRangeOffset)
    }

    private func handlePatternNavigation(_ command: PatternNavigationCommand) {
        guard let metadata = loadedMetadata, metadata.type == "XM",
              metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }

        let pattern = metadata.xmPatterns[currentPatternIndex]
        cursor.move(command, rowCount: pattern.rowCount, channelCount: pattern.channels)
        renderCurrentPattern(metadata: metadata)
    }

    private func scrollCursorIntoView(offset: Int) {
        guard rowRanges.indices.contains(cursor.row),
              let textView = metadataTextView else {
            return
        }
        let rowRange = rowRanges[cursor.row]
        let clampedChannel = max(0, cursor.channel)
        let channelOffset = ModuleMetadataLoader.xmRenderedRowPrefixWidth +
            clampedChannel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let fieldOffset = cursor.field.textOffset
        let fieldLength = cursor.field.textLength
        let maxLocation = rowRange.location + max(0, rowRange.length - 1)
        let targetLocation = min(maxLocation, rowRange.location + channelOffset + fieldOffset)
        let range = NSRange(location: targetLocation + offset, length: max(1, fieldLength))
        textView.scrollRangeToVisible(range)
    }

    private func updateActiveFieldRange(rowRangeOffset: Int) {
        guard rowRanges.indices.contains(cursor.row),
              let textView = metadataTextView as? PatternTextView else {
            return
        }

        let rowRange = rowRanges[cursor.row]
        let channelOffset = ModuleMetadataLoader.xmRenderedRowPrefixWidth +
            cursor.channel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let fieldOffset = cursor.field.textOffset
        let location = rowRange.location + channelOffset + fieldOffset + rowRangeOffset
        let maxLocation = rowRange.location + rowRangeOffset + max(0, rowRange.length - 1)
        let clampedLocation = min(location, maxLocation)
        textView.activeFieldRange = NSRange(location: clampedLocation, length: max(1, cursor.field.textLength))
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
