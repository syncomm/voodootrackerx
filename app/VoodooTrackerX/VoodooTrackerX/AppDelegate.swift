import AppKit
import UniformTypeIdentifiers

private enum PatternGridPreferences {
    static let beatAccentIntervalKey = "PatternGridBeatAccentInterval"
    static let defaultBeatAccentInterval = 4

    static var beatAccentInterval: Int {
        let stored = UserDefaults.standard.integer(forKey: beatAccentIntervalKey)
        return stored > 0 ? stored : defaultBeatAccentInterval
    }
}

private struct TrackerTheme {
    let background: NSColor
    let text: NSColor
    let accent: NSColor
    let beatAccent: NSColor
    let cursorOutline: NSColor
    let rowHighlight: NSColor
    let separator: NSColor

    static let legacyDark = TrackerTheme(
        background: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0),
        text: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.93, alpha: 1.0),
        accent: NSColor(calibratedRed: 1.0, green: 0.90, blue: 0.35, alpha: 1.0),
        beatAccent: NSColor(calibratedRed: 1.0, green: 0.90, blue: 0.28, alpha: 0.24),
        cursorOutline: NSColor(calibratedRed: 1.0, green: 0.26, blue: 0.18, alpha: 1.0),
        rowHighlight: NSColor(calibratedRed: 0.27, green: 0.31, blue: 0.41, alpha: 0.95),
        separator: NSColor(calibratedRed: 0.97, green: 0.84, blue: 0.42, alpha: 0.72)
    )
}

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
    var theme = TrackerTheme.legacyDark
    var dividerCharacterIndices = [Int]() {
        didSet {
            needsDisplay = true
        }
    }
    var dividerTopCharacterIndex: Int? {
        didSet {
            needsDisplay = true
        }
    }
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

        drawChannelDividers()

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
        theme.cursorOutline.setStroke()
        let path = NSBezierPath(rect: strokeRect)
        path.lineWidth = 2
        path.stroke()
    }

    private func drawChannelDividers() {
        guard !dividerCharacterIndices.isEmpty,
              let layoutManager else {
            return
        }

        let textLength = (string as NSString).length
        guard textLength > 0 else { return }

        let visibleRect = self.visibleRect
        var dividerMinY = visibleRect.minY
        if let dividerTopCharacterIndex {
            let clampedTop = min(max(0, dividerTopCharacterIndex), textLength - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedTop)
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            dividerMinY = max(visibleRect.minY, textContainerOrigin.y + lineRect.minY)
        }
        guard dividerMinY < visibleRect.maxY else { return }
        let path = NSBezierPath()
        path.lineWidth = 1

        for characterIndex in dividerCharacterIndices {
            let clampedIndex = min(max(0, characterIndex), textLength - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedIndex)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let x = textContainerOrigin.x + location.x + 0.5
            path.move(to: NSPoint(x: x, y: dividerMinY))
            path.line(to: NSPoint(x: x, y: visibleRect.maxY))
        }

        theme.separator.setStroke()
        path.stroke()
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private var mainWindow: NSWindow?
    private var metadataTextView: NSTextView?
    private var rowNumberTextView: NSTextView?
    private var patternInfoLabel: NSTextField?
    private var patternHeaderTextView: PatternTextView?
    private var patternHeaderScrollView: NSScrollView?
    private var topLeftHeaderSpacer: NSBox?
    private var gridScrollView: NSScrollView?
    private var rowNumberScrollView: NSScrollView?
    private var patternSelector: NSPopUpButton?
    private var showAllPatternsCheckbox: NSButton?
    private var loadedMetadata: ParsedModuleMetadata?
    private var displayedPatternEntries = [ModuleMetadataLoader.PatternSelectionEntry]()
    private var invalidReferencedPatternIndices = [Int]()
    private var selectedDropdownIndex = 0
    private var currentPatternIndex = 0
    private var cursor = PatternCursor(row: 0, channel: 0, field: .note)
    private var rowRanges = [NSRange]()
    private let theme = TrackerTheme.legacyDark
    private let metadataLoader = ModuleMetadataLoader()
    private let initialWindowSize = NSSize(width: 1000, height: 700)
    private let rowNumberColumnWidth: CGFloat = 54
    private var isSyncingScroll = false

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
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = theme.background.cgColor

        let titleLabel = NSTextField(labelWithString: "VoodooTracker X")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = theme.text
        titleLabel.frame = NSRect(x: 20, y: initialWindowSize.height - 42, width: 400, height: 24)
        titleLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(titleLabel)

        let selector = NSPopUpButton(frame: NSRect(x: 20, y: initialWindowSize.height - 68, width: 220, height: 28))
        selector.autoresizingMask = [.maxXMargin, .minYMargin]
        selector.appearance = NSAppearance(named: .darkAqua)
        selector.contentTintColor = theme.text
        selector.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        selector.target = self
        selector.action = #selector(patternSelectionChanged(_:))
        selector.isHidden = true
        contentView.addSubview(selector)
        patternSelector = selector

        let showAllCheckbox = NSButton(checkboxWithTitle: "Show all patterns", target: self, action: #selector(showAllPatternsToggled(_:)))
        showAllCheckbox.frame = NSRect(x: 250, y: initialWindowSize.height - 68, width: 180, height: 28)
        showAllCheckbox.autoresizingMask = [.maxXMargin, .minYMargin]
        showAllCheckbox.appearance = NSAppearance(named: .darkAqua)
        showAllCheckbox.contentTintColor = theme.accent
        showAllCheckbox.attributedTitle = NSAttributedString(
            string: "Show all patterns",
            attributes: [
                .foregroundColor: theme.text,
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
        showAllCheckbox.state = .off
        showAllCheckbox.isHidden = true
        contentView.addSubview(showAllCheckbox)
        showAllPatternsCheckbox = showAllCheckbox

        let infoLabel = NSTextField(labelWithString: "")
        infoLabel.frame = NSRect(x: 20, y: initialWindowSize.height - 98, width: initialWindowSize.width - 40, height: 20)
        infoLabel.autoresizingMask = [.width, .minYMargin]
        infoLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        infoLabel.textColor = theme.text
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.isHidden = true
        contentView.addSubview(infoLabel)
        patternInfoLabel = infoLabel

        let headerY = initialWindowSize.height - 126
        let topLeftSpacer = NSBox(frame: NSRect(x: 20, y: headerY, width: rowNumberColumnWidth, height: 24))
        topLeftSpacer.autoresizingMask = [.minYMargin]
        topLeftSpacer.boxType = .custom
        topLeftSpacer.borderType = .lineBorder
        topLeftSpacer.borderColor = NSColor(calibratedWhite: 0.22, alpha: 1.0)
        topLeftSpacer.fillColor = theme.background
        topLeftSpacer.contentViewMargins = .zero
        topLeftSpacer.isHidden = true
        contentView.addSubview(topLeftSpacer)
        topLeftHeaderSpacer = topLeftSpacer

        let headerScrollView = NSScrollView(
            frame: NSRect(
                x: 20 + rowNumberColumnWidth,
                y: headerY,
                width: initialWindowSize.width - 40 - rowNumberColumnWidth,
                height: 24
            )
        )
        headerScrollView.autoresizingMask = [.width, .minYMargin]
        headerScrollView.hasVerticalScroller = false
        headerScrollView.hasHorizontalScroller = false
        headerScrollView.verticalScrollElasticity = .none
        headerScrollView.horizontalScrollElasticity = .none
        headerScrollView.borderType = .bezelBorder
        headerScrollView.drawsBackground = true
        headerScrollView.backgroundColor = theme.background

        let headerTextView = PatternTextView(frame: headerScrollView.bounds)
        headerTextView.autoresizingMask = []
        headerTextView.isEditable = false
        headerTextView.isRichText = false
        headerTextView.isSelectable = false
        headerTextView.isHorizontallyResizable = true
        headerTextView.isVerticallyResizable = false
        headerTextView.minSize = NSSize(width: 0, height: 0)
        headerTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        headerTextView.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        headerTextView.textContainerInset = NSSize(width: 4, height: 2)
        headerTextView.drawsBackground = true
        headerTextView.backgroundColor = theme.background
        headerTextView.textColor = theme.accent
        headerTextView.textContainer?.lineFragmentPadding = 0
        headerTextView.textContainer?.widthTracksTextView = false
        headerTextView.textContainer?.heightTracksTextView = true
        headerTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        headerTextView.textContainer?.lineBreakMode = .byClipping
        headerTextView.theme = theme
        headerScrollView.documentView = headerTextView
        headerScrollView.isHidden = true
        contentView.addSubview(headerScrollView)
        patternHeaderScrollView = headerScrollView
        patternHeaderTextView = headerTextView

        let bodyY: CGFloat = 20
        let bodyHeight = initialWindowSize.height - 152

        let rowScrollView = NSScrollView(frame: NSRect(x: 20, y: bodyY, width: rowNumberColumnWidth, height: bodyHeight))
        rowScrollView.autoresizingMask = [.height]
        rowScrollView.hasVerticalScroller = false
        rowScrollView.hasHorizontalScroller = false
        rowScrollView.verticalScrollElasticity = .none
        rowScrollView.horizontalScrollElasticity = .none
        rowScrollView.borderType = .bezelBorder
        rowScrollView.drawsBackground = true
        rowScrollView.backgroundColor = theme.background

        let rowTextView = NSTextView(frame: rowScrollView.bounds)
        rowTextView.autoresizingMask = []
        rowTextView.isEditable = false
        rowTextView.isRichText = false
        rowTextView.isSelectable = false
        rowTextView.isHorizontallyResizable = false
        rowTextView.isVerticallyResizable = true
        rowTextView.minSize = NSSize(width: rowNumberColumnWidth, height: 0)
        rowTextView.maxSize = NSSize(width: rowNumberColumnWidth, height: CGFloat.greatestFiniteMagnitude)
        rowTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        rowTextView.alignment = .right
        rowTextView.drawsBackground = true
        rowTextView.backgroundColor = theme.background
        rowTextView.textColor = theme.text
        rowTextView.textContainerInset = NSSize(width: 4, height: 0)
        rowTextView.textContainer?.lineFragmentPadding = 0
        rowTextView.textContainer?.widthTracksTextView = true
        rowTextView.textContainer?.heightTracksTextView = false
        rowTextView.textContainer?.containerSize = NSSize(width: rowNumberColumnWidth, height: CGFloat.greatestFiniteMagnitude)
        rowTextView.textContainer?.lineBreakMode = .byClipping
        rowScrollView.documentView = rowTextView
        rowScrollView.isHidden = true
        contentView.addSubview(rowScrollView)
        rowNumberTextView = rowTextView
        rowNumberScrollView = rowScrollView

        let scrollView = NSScrollView(
            frame: NSRect(
                x: 20 + rowNumberColumnWidth,
                y: bodyY,
                width: initialWindowSize.width - 40 - rowNumberColumnWidth,
                height: bodyHeight
            )
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background

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
        textView.drawsBackground = true
        textView.backgroundColor = theme.background
        textView.textColor = theme.text
        textView.theme = theme
        textView.textContainerInset = NSSize(width: 4, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byClipping
        textView.navigationHandler = { [weak self] command in
            self?.handlePatternNavigation(command)
        }
        let introText = """
        VoodooTracker X

        File > Open… to load a .mod or .xm file and inspect parsed header metadata.
        """
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: introText,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: theme.text
                ]
            )
        )
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        rowScrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gridClipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rowNumberClipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: rowScrollView.contentView
        )
        contentView.addSubview(scrollView)
        metadataTextView = textView
        gridScrollView = scrollView

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoodooTracker X"
        window.appearance = NSAppearance(named: .darkAqua)
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
                patternInfoLabel?.isHidden = false
                patternHeaderScrollView?.isHidden = false
                rowNumberScrollView?.isHidden = false
                topLeftHeaderSpacer?.isHidden = false
                updatePatternSelector(for: metadata, keepPattern: nil)
                renderCurrentPattern(metadata: metadata)
            } else {
                (metadataTextView as? PatternTextView)?.activeFieldRange = nil
                (metadataTextView as? PatternTextView)?.dividerCharacterIndices = []
                (metadataTextView as? PatternTextView)?.dividerTopCharacterIndex = nil
                patternInfoLabel?.stringValue = ""
                patternInfoLabel?.isHidden = true
                patternHeaderTextView?.string = ""
                patternHeaderTextView?.dividerCharacterIndices = []
                rowNumberTextView?.string = ""
                patternSelector?.removeAllItems()
                patternSelector?.isHidden = true
                showAllPatternsCheckbox?.isHidden = true
                patternHeaderScrollView?.isHidden = true
                rowNumberScrollView?.isHidden = true
                topLeftHeaderSpacer?.isHidden = true
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
        updatePatternSelector(for: metadata, keepPattern: currentPatternIndex, showAllPatterns: sender.state == .on)
        renderCurrentPattern(metadata: metadata)
    }

    private func updatePatternSelector(for metadata: ParsedModuleMetadata, keepPattern: Int?, showAllPatterns: Bool? = nil) {
        guard let selector = patternSelector else {
            return
        }
        let shouldShowAllPatterns = showAllPatterns ?? (showAllPatternsCheckbox?.state == .on)
        let referencedPatterns = Set(
            metadata.orderTable.filter { $0 >= 0 && $0 < metadata.xmPatterns.count }
        )
        let nonEmptyPatterns = Set(
            metadata.xmPatterns.compactMap { pattern in
                let hasData = pattern.rows.contains { row in
                    row.contains { $0 != .empty }
                }
                return hasData ? pattern.index : nil
            }
        )
        let intersectedUsed = referencedPatterns.intersection(nonEmptyPatterns)
        let effectiveUsedPatterns: Set<Int> = intersectedUsed.isEmpty ? referencedPatterns : intersectedUsed
        let rowCounts = metadata.xmPatterns.map(\.rowCount)
        let selection = ModuleMetadataLoader.buildPatternSelection(
            orderTable: metadata.orderTable,
            patternCount: metadata.xmPatterns.count,
            rowCounts: rowCounts,
            showAllPatterns: shouldShowAllPatterns,
            usedPatternIndices: effectiveUsedPatterns
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
        patternInfoLabel?.stringValue = ModuleMetadataLoader.renderXMPatternInfoLine(pattern, focusedChannel: cursor.channel)
        let channelHeader = ModuleMetadataLoader.renderXMChannelHeader(channels: pattern.channels)
        let rendered = ModuleMetadataLoader.renderXMPatternRows(pattern)
        rowRanges = rendered.rowRanges

        updatePatternHeader(channelHeader, channels: pattern.channels)
        updatePatternDividerIndices(
            channels: pattern.channels,
            rowRangeOffset: 0
        )

        let attributed = NSMutableAttributedString(string: rendered.gridText)
        let rowAttributed = NSMutableAttributedString(string: rendered.rowNumberText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .ligature: 0,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.text
        ]
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        rowAttributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: rowAttributed.length))
        applyBeatAccentStyling(attributed, rowRangeOffset: 0)
        applyBeatAccentStyling(rowAttributed, rowRanges: rendered.rowNumberRanges, rowRangeOffset: 0)
        if rowRanges.indices.contains(cursor.row) {
            let range = rowRanges[cursor.row]
            attributed.addAttribute(.backgroundColor, value: theme.rowHighlight, range: range)
            let rowNumberRange = rendered.rowNumberRanges[cursor.row]
            rowAttributed.addAttribute(.backgroundColor, value: theme.rowHighlight, range: rowNumberRange)
        }
        metadataTextView?.textStorage?.setAttributedString(attributed)
        rowNumberTextView?.textStorage?.setAttributedString(rowAttributed)
        updateActiveFieldRange(rowRangeOffset: 0)
        updateMetadataTextViewDocumentSize()
        updateRowNumberTextViewDocumentSize()
        syncStickyPanesToGrid()
        if let textView = metadataTextView {
            mainWindow?.makeFirstResponder(textView)
        }
        scrollCursorIntoView(offset: 0)
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
        let channelOffset = clampedChannel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
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
        let channelOffset = cursor.channel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
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
        let contentWidth = usedRect.width + inset.width * 2 + 2
        let contentHeight = usedRect.height + inset.height * 2 + 2
        let viewport = textView.enclosingScrollView?.contentView.bounds.size ?? .zero

        let targetSize = NSSize(
            width: max(viewport.width, contentWidth),
            height: max(viewport.height, contentHeight)
        )
        textView.setFrameSize(targetSize)
    }

    private func updateRowNumberTextViewDocumentSize() {
        guard let rowTextView = rowNumberTextView,
              let layoutManager = rowTextView.layoutManager,
              let textContainer = rowTextView.textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer).integral
        let inset = rowTextView.textContainerInset
        let contentHeight = usedRect.height + inset.height * 2 + 2
        let viewportHeight = rowTextView.enclosingScrollView?.contentView.bounds.height ?? .zero
        rowTextView.setFrameSize(NSSize(width: rowNumberColumnWidth, height: max(viewportHeight, contentHeight)))
    }

    private func syncStickyPanesToGrid() {
        guard let gridClipView = gridScrollView?.contentView else { return }
        let origin = gridClipView.bounds.origin
        if let rowNumberScrollView {
            let baselineAdjustedY = adjustedRowNumberOriginY(forGridOriginY: origin.y)
            rowNumberScrollView.contentView.scroll(to: NSPoint(x: 0, y: baselineAdjustedY))
            rowNumberScrollView.reflectScrolledClipView(rowNumberScrollView.contentView)
        }
        if let patternHeaderScrollView {
            patternHeaderScrollView.contentView.scroll(to: NSPoint(x: origin.x, y: 0))
            patternHeaderScrollView.reflectScrolledClipView(patternHeaderScrollView.contentView)
        }
    }

    private func adjustedRowNumberOriginY(forGridOriginY gridOriginY: CGFloat) -> CGFloat {
        guard let gridTextView = metadataTextView,
              let rowTextView = rowNumberTextView,
              let gridLayoutManager = gridTextView.layoutManager,
              let rowLayoutManager = rowTextView.layoutManager else {
            return gridOriginY
        }
        let gridLength = (gridTextView.string as NSString).length
        let rowLength = (rowTextView.string as NSString).length
        guard gridLength > 0, rowLength > 0 else {
            return gridOriginY
        }

        let gridGlyph = gridLayoutManager.glyphIndexForCharacter(at: 0)
        let rowGlyph = rowLayoutManager.glyphIndexForCharacter(at: 0)
        let gridLineRect = gridLayoutManager.lineFragmentUsedRect(forGlyphAt: gridGlyph, effectiveRange: nil, withoutAdditionalLayout: true)
        let rowLineRect = rowLayoutManager.lineFragmentUsedRect(forGlyphAt: rowGlyph, effectiveRange: nil, withoutAdditionalLayout: true)
        let gridBaselineY = gridLineRect.minY + gridTextView.textContainerOrigin.y
        let rowBaselineY = rowLineRect.minY + rowTextView.textContainerOrigin.y
        let delta = rowBaselineY - gridBaselineY
        return max(0, gridOriginY + delta)
    }

    private func updatePatternDividerIndices(channels: Int, rowRangeOffset: Int) {
        guard let textView = metadataTextView as? PatternTextView,
              channels > 0,
              let firstRowRange = rowRanges.first else {
            (metadataTextView as? PatternTextView)?.dividerCharacterIndices = []
            (metadataTextView as? PatternTextView)?.dividerTopCharacterIndex = nil
            return
        }

        let rowStart = firstRowRange.location + rowRangeOffset
        let separatorMidOffset = ModuleMetadataLoader.xmRenderedCellSeparatorWidth / 2
        var indices = [Int]()
        indices.reserveCapacity(max(0, channels - 1))

        for divider in 1..<channels {
            let separatorStart = rowStart + (divider * ModuleMetadataLoader.xmRenderedCellWidth) +
                ((divider - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
            indices.append(separatorStart + separatorMidOffset)
        }
        textView.dividerCharacterIndices = indices
        textView.dividerTopCharacterIndex = rowRanges.first?.location
    }

    private func updatePatternHeader(_ headerText: String, channels: Int) {
        guard let headerTextView = patternHeaderTextView else {
            return
        }
        let attributed = NSMutableAttributedString(string: headerText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        attributed.addAttributes(
            [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .ligature: 0,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.accent
            ],
            range: NSRange(location: 0, length: attributed.length)
        )
        headerTextView.textStorage?.setAttributedString(attributed)
        let viewportWidth = patternHeaderScrollView?.contentView.bounds.width ?? 0
        headerTextView.setFrameSize(NSSize(width: max(viewportWidth, attributed.size().width + 16), height: 24))
        let separatorMidOffset = ModuleMetadataLoader.xmRenderedCellSeparatorWidth / 2
        var indices = [Int]()
        indices.reserveCapacity(max(0, channels - 1))
        for divider in 1..<channels {
            let separatorStart = (divider * ModuleMetadataLoader.xmRenderedCellWidth) +
                ((divider - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
            indices.append(separatorStart + separatorMidOffset)
        }
        headerTextView.dividerCharacterIndices = indices
        headerTextView.dividerTopCharacterIndex = nil
    }

    private func applyBeatAccentStyling(_ attributed: NSMutableAttributedString, rowRangeOffset: Int) {
        let interval = PatternGridPreferences.beatAccentInterval
        guard interval > 0 else { return }

        for (rowIndex, rowRange) in rowRanges.enumerated() where rowIndex % interval == 0 {
            let shifted = NSRange(location: rowRange.location + rowRangeOffset, length: rowRange.length)
            guard shifted.location + shifted.length <= attributed.length else {
                continue
            }
            attributed.addAttribute(
                .backgroundColor,
                value: theme.beatAccent,
                range: shifted
            )
            attributed.addAttribute(
                .foregroundColor,
                value: theme.text,
                range: shifted
            )
        }
    }

    private func applyBeatAccentStyling(_ attributed: NSMutableAttributedString, rowRanges: [NSRange], rowRangeOffset: Int) {
        let interval = PatternGridPreferences.beatAccentInterval
        guard interval > 0 else { return }

        for (rowIndex, rowRange) in rowRanges.enumerated() where rowIndex % interval == 0 {
            let shifted = NSRange(location: rowRange.location + rowRangeOffset, length: rowRange.length)
            guard shifted.location + shifted.length <= attributed.length else {
                continue
            }
            attributed.addAttribute(.backgroundColor, value: theme.beatAccent, range: shifted)
            attributed.addAttribute(.foregroundColor, value: theme.text, range: shifted)
        }
    }

    @objc
    private func gridClipViewBoundsDidChange(_ notification: Notification) {
        guard !isSyncingScroll,
              let clipView = notification.object as? NSClipView,
              clipView === gridScrollView?.contentView else {
            return
        }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        syncStickyPanesToGrid()
    }

    @objc
    private func rowNumberClipViewBoundsDidChange(_ notification: Notification) {
        guard !isSyncingScroll,
              let clipView = notification.object as? NSClipView,
              clipView === rowNumberScrollView?.contentView else {
            return
        }
        isSyncingScroll = true
        defer { isSyncingScroll = false }

        let origin = clipView.bounds.origin
        guard let gridClipView = gridScrollView?.contentView else { return }
        gridClipView.scroll(to: NSPoint(x: gridClipView.bounds.origin.x, y: origin.y))
        gridScrollView?.reflectScrolledClipView(gridClipView)
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
