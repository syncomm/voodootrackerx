// Owns app lifecycle, menu/setup, module loading, and top-level coordination between state and the main window.
// It intentionally does not build the window hierarchy directly, but it still owns tracker state/render coordination for now.
import AppKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private var windowController: TrackerWindowController?
    private var loadedMetadata: ParsedModuleMetadata?
    private var displayedPatternEntries = [ModuleMetadataLoader.PatternSelectionEntry]()
    private var invalidReferencedPatternIndices = [Int]()
    private var selectedPatternSelectionIndex = 0
    private var selectedSongPositionIndex = 0
    private var currentPatternIndex = 0
    private var cursor = PatternCursor(row: 0, channel: 0, field: .note)
    private var visibleGridRangesByRow = [Int: NSRange]()
    private var currentViewportState: PatternViewportState?
    private var currentViewportLayout: PatternViewportTextLayout?
    private let theme = TrackerTheme.legacyDark
    private let metadataLoader = ModuleMetadataLoader()
    private var isSyncingScroll = false
    private var isEditModeEnabled = false
    private var isPlaybackModeActive = false
    private var isLoopPlaybackEnabled = false
    private var selectedOctave = 4
    private var lastGridViewportSize = NSSize.zero
    private var lastStableGridHorizontalOrigin: CGFloat = 0
    private var pendingHorizontalViewportOrigin: CGFloat?
    private var isLiveResizingTrackerViewport = false
    private var liveResizeHorizontalOrigin: CGFloat?

    private var mainWindow: NSWindow? { windowController?.window }
    private var controlPanelView: ControlPanelView? { windowController?.controlPanelView }
    private var trackerEditorView: TrackerEditorView? { windowController?.trackerEditorView }
    private var metadataTextView: PatternTextView? { trackerEditorView?.metadataTextView }
    private var patternInfoLabel: NSTextField? { trackerEditorView?.patternInfoLabel }
    private var patternHeaderTextView: PatternTextView? { trackerEditorView?.patternHeaderTextView }
    private var patternHeaderScrollView: NSScrollView? { trackerEditorView?.patternHeaderScrollView }
    private var gridScrollView: NSScrollView? { trackerEditorView?.gridScrollView }
    private var trackerDividerUnderlayView: TrackerDividerUnderlayView? { trackerEditorView?.trackerDividerUnderlayView }
    private var trackerChromeOverlayView: TrackerChromeOverlayView? { trackerEditorView?.trackerChromeOverlayView }
    private var patternSelector: NSPopUpButton? { controlPanelView?.patternSelector }
    private var editModeCheckbox: NSButton? { controlPanelView?.editModeButton }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        if windowController == nil {
            let controller = TrackerWindowController(theme: theme)
            wireTrackerWindowController(controller)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(gridClipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: controller.trackerEditorView.gridScrollView.contentView
            )
            windowController = controller
            lastGridViewportSize = controller.trackerEditorView.gridScrollView.contentView.bounds.size
            syncControlPanelView()
        }
        windowController?.showWindowAndActivate()
        if let metadataTextView {
            mainWindow?.makeFirstResponder(metadataTextView)
        }
        let debugOpenPath = ProcessInfo.processInfo.environment["VTX_OPEN_PATH"] ?? ""
        if !debugOpenPath.isEmpty {
            loadModule(from: URL(fileURLWithPath: debugOpenPath))
            return
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // AppDelegate owns mutable tracker/module state and pushes view updates into the window-controller tree.
    private func wireTrackerWindowController(_ controller: TrackerWindowController) {
        controller.trackerEditorView.metadataTextView.navigationHandler = { [weak self] command in
            self?.handlePatternNavigation(command)
        }
        controller.trackerEditorView.metadataTextView.editInputHandler = { [weak self] input in
            self?.handlePatternEditInput(input) ?? false
        }
        controller.trackerEditorView.metadataTextView.wheelNavigationHandler = { [weak self] deltaY in
            self?.handlePatternWheel(deltaY: deltaY)
        }

        controller.controlPanelView.playButton.target = self
        controller.controlPanelView.playButton.action = #selector(playPressed(_:))
        controller.controlPanelView.stopButton.target = self
        controller.controlPanelView.stopButton.action = #selector(stopPressed(_:))
        controller.controlPanelView.loopButton.target = self
        controller.controlPanelView.loopButton.action = #selector(loopToggled(_:))
        controller.controlPanelView.editModeButton.target = self
        controller.controlPanelView.editModeButton.action = #selector(editModeToggled(_:))
        controller.controlPanelView.patternSelector.target = self
        controller.controlPanelView.patternSelector.action = #selector(patternSelectionChanged(_:))
        controller.controlPanelView.songPositionStepper.target = self
        controller.controlPanelView.songPositionStepper.action = #selector(currentSongPositionStepperChanged(_:))
        controller.controlPanelView.octaveSelector.target = self
        controller.controlPanelView.octaveSelector.action = #selector(octaveSelectionChanged(_:))

        controller.liveResizeWillStartHandler = { [weak self] in
            self?.trackerWindowWillStartLiveResize()
        }
        controller.liveResizeDidEndHandler = { [weak self] in
            self?.trackerWindowDidEndLiveResize()
        }
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

    @objc
    private func openModuleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.message = "Choose a MOD or XM module file"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadModule(from: url)
    }

    private func loadModule(from url: URL) {
        do {
            let metadata = try metadataLoader.load(fromPath: url.path)
            loadedMetadata = metadata
            selectedPatternSelectionIndex = 0
            selectedSongPositionIndex = 0
            currentPatternIndex = 0
            cursor = PatternCursor(row: 0, channel: 0, field: .note)
            isEditModeEnabled = false
            isPlaybackModeActive = false
            isLoopPlaybackEnabled = false
            editModeCheckbox?.state = .off

            if metadata.type == "XM", !metadata.xmPatterns.isEmpty {
                patternInfoLabel?.isHidden = true
                patternHeaderScrollView?.isHidden = false
                trackerDividerUnderlayView?.isHidden = false
                trackerChromeOverlayView?.isHidden = false
                updatePatternSelector(for: metadata, keepPattern: nil)
                applySongPosition(selectedSongPositionIndex, in: metadata, resetCursor: false)
                renderCurrentPattern(metadata: metadata)
            } else {
                metadataTextView?.activeFieldRange = nil
                metadataTextView?.dividerCharacterIndices = []
                metadataTextView?.dividerTopCharacterIndex = nil
                visibleGridRangesByRow = [:]
                currentViewportState = nil
                currentViewportLayout = nil
                trackerDividerUnderlayView?.isHidden = true
                trackerChromeOverlayView?.viewportState = nil
                trackerChromeOverlayView?.isHidden = true
                patternInfoLabel?.stringValue = ""
                patternInfoLabel?.isHidden = true
                patternHeaderTextView?.string = ""
                patternHeaderTextView?.dividerCharacterIndices = []
                patternSelector?.removeAllItems()
                patternHeaderScrollView?.isHidden = true
                metadataTextView?.string = """
                File: \(url.lastPathComponent)
                Path: \(url.path)

                \(metadata.displayText)
                """
            }
            syncControlPanelView()
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
        selectedPatternSelectionIndex = max(0, sender.indexOfSelectedItem)
        guard displayedPatternEntries.indices.contains(selectedPatternSelectionIndex) else {
            return
        }
        currentPatternIndex = displayedPatternEntries[selectedPatternSelectionIndex].patternIndex
        cursor = PatternCursor(row: 0, channel: 0, field: .note)
        renderCurrentPattern(metadata: metadata)
        syncControlPanelView()
    }

    @objc
    private func currentSongPositionStepperChanged(_ sender: NSStepper) {
        guard let metadata = loadedMetadata else {
            return
        }
        applySongPosition(sender.integerValue, in: metadata)
        renderCurrentPattern(metadata: metadata)
        syncControlPanelView()
    }

    @objc
    private func editModeToggled(_ sender: NSButton) {
        isEditModeEnabled = sender.state == .on
        syncControlPanelView()
    }

    @objc
    private func playPressed(_ sender: NSButton) {
        isPlaybackModeActive = true
        syncControlPanelView()
    }

    @objc
    private func stopPressed(_ sender: NSButton) {
        isPlaybackModeActive = false
        syncControlPanelView()
    }

    @objc
    private func loopToggled(_ sender: NSButton) {
        isLoopPlaybackEnabled = sender.state == .on
        syncControlPanelView()
    }

    @objc
    private func octaveSelectionChanged(_ sender: NSPopUpButton) {
        selectedOctave = max(0, sender.indexOfSelectedItem)
        syncControlPanelView()
    }

    private var interactionMode: TrackerInteractionMode {
        if isEditModeEnabled {
            return .edit
        }
        if isPlaybackModeActive {
            return .playOnly
        }
        return .navigation
    }

    private func updatePatternSelector(for metadata: ParsedModuleMetadata, keepPattern: Int?) {
        guard let selector = patternSelector else {
            return
        }
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
            showAllPatterns: false,
            usedPatternIndices: effectiveUsedPatterns
        )
        displayedPatternEntries = selection.entries
        invalidReferencedPatternIndices = selection.invalidReferencedPatterns

        selector.removeAllItems()
        for entry in displayedPatternEntries {
            selector.addItem(withTitle: formattedPatternSelectorTitle(patternIndex: entry.patternIndex, rowCount: entry.rowCount))
        }
        guard !displayedPatternEntries.isEmpty else {
            selector.isEnabled = false
            return
        }

        if let keepPattern, let index = displayedPatternEntries.firstIndex(where: { $0.patternIndex == keepPattern }) {
            selectedPatternSelectionIndex = index
        } else {
            selectedPatternSelectionIndex = 0
        }
        currentPatternIndex = displayedPatternEntries[selectedPatternSelectionIndex].patternIndex
        selector.selectItem(at: selectedPatternSelectionIndex)
        selector.isEnabled = true
    }

    private func applySongPosition(_ proposedPosition: Int, in metadata: ParsedModuleMetadata, resetCursor: Bool = true) {
        let clampedPosition = clampedSongPosition(proposedPosition, songLength: metadata.songLength)
        selectedSongPositionIndex = clampedPosition
        if let patternIndex = displayedPatternIndex(in: metadata, songPosition: clampedPosition) {
            currentPatternIndex = patternIndex
            if let selectorIndex = displayedPatternEntries.firstIndex(where: { $0.patternIndex == patternIndex }) {
                selectedPatternSelectionIndex = selectorIndex
                patternSelector?.selectItem(at: selectorIndex)
            }
        }
        if resetCursor {
            cursor = PatternCursor(row: 0, channel: 0, field: .note)
        }
    }

    private func displayedPatternIndex(in metadata: ParsedModuleMetadata, songPosition: Int) -> Int? {
        let safeSongLength = min(metadata.songLength, metadata.orderTable.count)
        guard safeSongLength > 0 else { return nil }
        let clampedPosition = min(max(0, songPosition), safeSongLength - 1)
        let patternIndex = metadata.orderTable[clampedPosition]
        guard metadata.xmPatterns.indices.contains(patternIndex) else {
            return nil
        }
        return patternIndex
    }

    private func formattedPatternSelectorTitle(patternIndex: Int, rowCount: Int) -> String {
        String(format: "P%02X", patternIndex)
    }

    private func clampedSongPosition(_ proposedPosition: Int, songLength: Int) -> Int {
        guard songLength > 0 else { return 0 }
        return min(max(0, proposedPosition), songLength - 1)
    }

    private func renderCurrentPattern(metadata: ParsedModuleMetadata, isViewportResizeRerender: Bool = false) {
        guard metadata.type == "XM", metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }
        let pattern = metadata.xmPatterns[currentPatternIndex]
        if pattern.rowCount == 0 {
            metadataTextView?.string = "Pattern \(pattern.index) is empty."
            return
        }

        cursor.clamp(rowCount: pattern.rowCount, channelCount: pattern.channels)
        patternInfoLabel?.stringValue = ""
        patternInfoLabel?.isHidden = true
        let channelHeader = ModuleMetadataLoader.renderXMChannelHeader(channels: pattern.channels)
        let metrics = viewportMetrics()
        let viewportState = PatternViewportState(currentRow: cursor.row, rowCount: pattern.rowCount, metrics: metrics)
        let viewportLayout = PatternViewportTextLayout(pattern: pattern, state: viewportState)
        currentViewportState = viewportState
        currentViewportLayout = viewportLayout
        visibleGridRangesByRow = viewportLayout.gridRangesByRow

        updatePatternHeader(channelHeader, channels: pattern.channels)
        updatePatternDividerIndices(channels: pattern.channels, layout: viewportLayout)

        let attributed = NSMutableAttributedString(string: viewportLayout.renderedText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .ligature: 0,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.text
        ]
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        applyBeatAccentStyling(attributed, layout: viewportLayout)
        if let range = viewportLayout.fullRangesByRow[cursor.row] {
            attributed.addAttribute(.backgroundColor, value: theme.rowHighlight, range: range)
        }
        metadataTextView?.textStorage?.setAttributedString(attributed)
        updateActiveFieldRange()
        updateMetadataTextViewDocumentSize(renderedRowCount: viewportState.visibleRowCount)
        syncTrackerViewport()
        if let textView = metadataTextView {
            mainWindow?.makeFirstResponder(textView)
        }
        if TrackerViewportResizeBehavior.shouldRevealCursorHorizontally(
            isViewportResizeRerender: isViewportResizeRerender
        ) {
            scrollCursorFieldHorizontallyIntoView(offset: 0)
        }
        refreshTrackerChromeOverlay()
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

    private func handlePatternEditInput(_ input: PatternEditInput) -> Bool {
        guard interactionMode == .edit,
              var metadata = loadedMetadata,
              metadata.type == "XM",
              metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return false
        }

        var pattern = metadata.xmPatterns[currentPatternIndex]
        guard pattern.rows.indices.contains(cursor.row),
              pattern.rows[cursor.row].indices.contains(cursor.channel) else {
            return false
        }

        let currentCell = pattern.rows[cursor.row][cursor.channel]
        guard let updatedCell = PatternEditEngine.apply(
            input: input,
            to: currentCell,
            field: cursor.field,
            editModeEnabled: isEditModeEnabled
        ) else {
            return false
        }

        pattern.rows[cursor.row][cursor.channel] = updatedCell
        metadata.xmPatterns[currentPatternIndex] = pattern
        loadedMetadata = metadata
        renderCurrentPattern(metadata: metadata)
        return true
    }

    private func handlePatternWheel(deltaY: CGFloat) {
        guard let metadata = loadedMetadata,
              metadata.type == "XM",
              metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }

        let command: PatternNavigationCommand = deltaY < 0 ? .down : .up
        handlePatternNavigation(command)
    }

    private func scrollCursorFieldHorizontallyIntoView(offset: Int) {
        guard let rowRange = visibleGridRangesByRow[cursor.row],
              let textView = metadataTextView,
              let scrollView = gridScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        let clampedChannel = max(0, cursor.channel)
        let channelOffset = clampedChannel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let fieldOffset = cursor.field.textOffset
        let fieldLength = cursor.field.textLength
        let maxLocation = rowRange.location + max(0, rowRange.length - 1)
        let targetLocation = min(maxLocation, rowRange.location + channelOffset + fieldOffset)
        let range = NSRange(location: targetLocation + offset, length: max(1, fieldLength))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return
        }
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textView.textContainerOrigin.x
        cursorRect.origin.y += textView.textContainerOrigin.y
        let visibleRect = scrollView.contentView.bounds
        let horizontalMargin = PatternCursorOutlineGeometry.scrollMargin.width
        let targetMinX = cursorRect.minX - horizontalMargin
        let targetMaxX = cursorRect.maxX + horizontalMargin
        let leftObstructionWidth = trackerChromeOverlayView?.dividerX ?? 0
        var targetOrigin = visibleRect.origin
        let visibleMinX = visibleRect.minX + leftObstructionWidth
        if targetMinX < visibleMinX {
            targetOrigin.x = max(0, targetMinX - leftObstructionWidth)
        } else if targetMaxX > visibleRect.maxX {
            let maxOriginX = max(0, textView.frame.width - visibleRect.width)
            targetOrigin.x = min(maxOriginX, targetMaxX - visibleRect.width)
        }
        scrollView.contentView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncStickyPanesToGrid()
    }

    private func updateActiveFieldRange() {
        guard let rowRange = visibleGridRangesByRow[cursor.row],
              let textView = metadataTextView else {
            return
        }

        let channelOffset = cursor.channel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let fieldOffset = cursor.field.textOffset
        let location = rowRange.location + channelOffset + fieldOffset
        let maxLocation = rowRange.location + max(0, rowRange.length - 1)
        let clampedLocation = min(location, maxLocation)
        textView.activeFieldRange = NSRange(location: clampedLocation, length: max(1, cursor.field.textLength))
    }

    private func updateMetadataTextViewDocumentSize(renderedRowCount: Int) {
        guard let textView = metadataTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer).integral
        let inset = textView.textContainerInset
        let contentWidth = usedRect.width + inset.width * 2 + 2 + PatternViewportMetrics.trailingContentPadding
        let viewport = textView.enclosingScrollView?.contentView.bounds.size ?? .zero
        let metrics = viewportMetrics()
        let contentHeight = metrics.contentHeight(forRenderedRowCount: renderedRowCount, insetHeight: inset.height)

        let targetSize = NSSize(
            width: max(viewport.width, contentWidth),
            height: max(viewport.height, contentHeight)
        )
        textView.setFrameSize(targetSize)
    }

    private func viewportMetrics() -> PatternViewportMetrics {
        PatternViewportMetrics(
            rowHeight: max(1, measuredPatternRowHeight()),
            viewportHeight: gridScrollView?.contentView.bounds.height ?? 0
        )
    }

    private func measuredPatternRowHeight() -> CGFloat {
        guard let firstRange = visibleGridRangesByRow.keys.sorted().first.flatMap({ visibleGridRangesByRow[$0] }),
              let textView = metadataTextView,
              let layoutManager = textView.layoutManager else {
            return 17
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: firstRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return 17
        }
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
        return max(1, lineRect.height)
    }

    private func syncTrackerViewport() {
        guard let scrollView = gridScrollView,
              let documentView = scrollView.documentView else { return }
        let currentOrigin = scrollView.contentView.bounds.origin
        let preferredOriginX = pendingHorizontalViewportOrigin ?? currentOrigin.x
        let clampedOriginX = TrackerViewportScrollGeometry.clampedHorizontalOrigin(
            preferredOriginX: preferredOriginX,
            contentWidth: documentView.frame.width,
            viewportWidth: scrollView.contentView.bounds.width
        )
        pendingHorizontalViewportOrigin = nil
        scrollView.contentView.scroll(to: NSPoint(x: clampedOriginX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncStickyPanesToGrid()
    }

    private func syncStickyPanesToGrid() {
        guard let gridClipView = gridScrollView?.contentView else { return }
        let origin = gridClipView.bounds.origin
        let isLiveResize = isLiveResizingTrackerViewport || (mainWindow?.inLiveResize ?? false)
        if TrackerViewportResizeBehavior.shouldCaptureStableHorizontalOrigin(isLiveResize: isLiveResize) {
            lastStableGridHorizontalOrigin = origin.x
        }
        if let patternHeaderScrollView {
            patternHeaderScrollView.contentView.scroll(to: NSPoint(x: origin.x, y: 0))
            patternHeaderScrollView.reflectScrolledClipView(patternHeaderScrollView.contentView)
        }
        refreshTrackerChromeOverlay()
        trackerChromeOverlayView?.needsDisplay = true
    }

    private func updatePatternDividerIndices(channels: Int, layout: PatternViewportTextLayout) {
        guard let textView = metadataTextView,
              channels > 0,
              let firstVisibleRowRange = layout.slotGridRanges.first else {
            metadataTextView?.dividerCharacterIndices = []
            metadataTextView?.dividerTopCharacterIndex = nil
            return
        }

        let rowStart = firstVisibleRowRange.location
        let separatorMidOffset = ModuleMetadataLoader.xmRenderedCellSeparatorWidth / 2
        var indices = [Int]()
        indices.reserveCapacity(max(0, channels - 1))

        for divider in 1..<channels {
            let separatorStart = rowStart + (divider * ModuleMetadataLoader.xmRenderedCellWidth) +
                ((divider - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
            indices.append(separatorStart + separatorMidOffset)
        }
        textView.dividerCharacterIndices = indices
        textView.dividerTopCharacterIndex = nil
    }

    private func updatePatternHeader(_ headerText: String, channels: Int) {
        guard let headerTextView = patternHeaderTextView else {
            return
        }
        let headerPrefixLength = PatternViewportTextLayout.rowNumberPrefixLength
        let headerLeadingPadding = String(repeating: " ", count: PatternViewportTextLayout.leadingChannelPaddingLength)
        let attributed = NSMutableAttributedString(
            string: String(repeating: " ", count: headerPrefixLength) + headerLeadingPadding + headerText
        )
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
            let separatorStart = headerPrefixLength + PatternViewportTextLayout.leadingChannelPaddingLength +
                (divider * ModuleMetadataLoader.xmRenderedCellWidth) +
                ((divider - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
            indices.append(separatorStart + separatorMidOffset)
        }
        headerTextView.dividerCharacterIndices = indices
        headerTextView.dividerTopCharacterIndex = nil
    }

    private func applyBeatAccentStyling(_ attributed: NSMutableAttributedString, layout: PatternViewportTextLayout) {
        let interval = PatternGridPreferences.beatAccentInterval
        guard interval > 0 else { return }

        for rowIndex in layout.slotRows.compactMap({ $0 }) where rowIndex % interval == 0 {
            guard let rowRange = layout.fullRangesByRow[rowIndex] else { continue }
            guard rowRange.location + rowRange.length <= attributed.length else {
                continue
            }
            attributed.addAttribute(.backgroundColor, value: theme.beatAccent, range: rowRange)
            attributed.addAttribute(.foregroundColor, value: theme.text, range: rowRange)
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
        let viewportSize = clipView.bounds.size
        if viewportSize != lastGridViewportSize,
           let metadata = loadedMetadata,
           metadata.type == "XM",
           metadata.xmPatterns.indices.contains(currentPatternIndex) {
            pendingHorizontalViewportOrigin = liveResizeHorizontalOrigin ?? lastStableGridHorizontalOrigin
            lastGridViewportSize = viewportSize
            renderCurrentPattern(metadata: metadata, isViewportResizeRerender: true)
            return
        }
        syncStickyPanesToGrid()
    }

    private func trackerWindowWillStartLiveResize() {
        guard let scrollView = gridScrollView else { return }
        isLiveResizingTrackerViewport = true
        liveResizeHorizontalOrigin = scrollView.contentView.bounds.origin.x
        pendingHorizontalViewportOrigin = liveResizeHorizontalOrigin
    }

    private func trackerWindowDidEndLiveResize() {
        isLiveResizingTrackerViewport = false
        if let scrollView = gridScrollView {
            lastGridViewportSize = scrollView.contentView.bounds.size
            lastStableGridHorizontalOrigin = scrollView.contentView.bounds.origin.x
        }
        liveResizeHorizontalOrigin = nil
    }

    private func updateTrackerChromeOverlay(layout: PatternViewportTextLayout, viewportState: PatternViewportState) {
        guard let trackerChromeOverlayView,
              let textView = metadataTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let firstGridRange = layout.slotGridRanges.first else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        textView.layoutSubtreeIfNeeded()
        let gridGlyphRange = layoutManager.glyphRange(forCharacterRange: firstGridRange, actualCharacterRange: nil)
        let firstGridGlyphIndex = gridGlyphRange.location
        let firstGridGlyphLocation = layoutManager.location(forGlyphAt: firstGridGlyphIndex)
        let leadingChannelPaddingWidth = NSString(
            string: String(repeating: " ", count: PatternViewportTextLayout.leadingChannelPaddingLength)
        ).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
        let gutterBoundaryX = floor(textView.textContainerOrigin.x + firstGridGlyphLocation.x - leadingChannelPaddingWidth)
        let rowNumberWidth = NSString(string: "00").size(
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        ).width
        let visibleDividerX = TrackerPinnedGutterGeometry.visibleWidth(for: gutterBoundaryX, rowNumberWidth: rowNumberWidth)

        trackerChromeOverlayView.viewportState = viewportState
        trackerChromeOverlayView.currentRow = cursor.row
        trackerChromeOverlayView.gutterWidth = visibleDividerX
        trackerChromeOverlayView.dividerX = gutterBoundaryX
        trackerDividerUnderlayView?.gutterWidth = visibleDividerX
        trackerDividerUnderlayView?.dividerX = gutterBoundaryX
        trackerChromeOverlayView.beatInterval = PatternGridPreferences.beatAccentInterval
        trackerChromeOverlayView.rowEntries = layout.slotRows.enumerated().compactMap { slotIndex, rowIndex in
            let characterRange = layout.slotFullRanges[slotIndex]
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }

            var lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            lineRect.origin.x += textView.textContainerOrigin.x
            lineRect.origin.y += textView.textContainerOrigin.y
            let overlayRect = trackerChromeOverlayView.convert(lineRect, from: textView)
            return TrackerChromeOverlayView.RowEntry(rowIndex: rowIndex, rect: overlayRect)
        }
        trackerChromeOverlayView.isHidden = false
        trackerChromeOverlayView.needsDisplay = true
    }

    private func refreshTrackerChromeOverlay() {
        guard let layout = currentViewportLayout,
              let viewportState = currentViewportState else {
            return
        }
        updateTrackerChromeOverlay(layout: layout, viewportState: viewportState)
    }

    private func syncControlPanelView() {
        var content = ControlPanelContent()
        content.selectedOctave = selectedOctave
        content.isLoopEnabled = isLoopPlaybackEnabled
        content.isEditModeEnabled = isEditModeEnabled
        content.isPlaybackActive = isPlaybackModeActive

        if let metadata = loadedMetadata {
            content.songTitle = metadata.title.isEmpty ? "(empty title)" : metadata.title
            content.songLength = String(format: "%02d", metadata.songLength)
            content.songPosition = String(format: "%02d", selectedSongPositionIndex)
            content.songPositionValue = selectedSongPositionIndex
            content.maximumSongPosition = max(0, metadata.songLength - 1)
            content.isSongPositionEnabled = metadata.songLength > 0
            if metadata.type == "XM",
               metadata.xmPatterns.indices.contains(currentPatternIndex) {
                let pattern = metadata.xmPatterns[currentPatternIndex]
                content.patternRowCount = "\(pattern.rowCount)"
                content.channelCount = "\(pattern.channels)"
                content.isPatternControlsEnabled = true
                content.areInstrumentPlaceholdersEnabled = metadata.instruments > 0
            } else {
                content.patternRowCount = "--"
                content.channelCount = String(format: "%02d", metadata.channels)
                content.isPatternControlsEnabled = false
                content.areInstrumentPlaceholdersEnabled = false
            }
            reloadInstrumentPlaceholders(for: metadata)
        } else {
            reloadInstrumentPlaceholders(for: nil)
        }

        controlPanelView?.apply(content)
    }

    // These selectors remain placeholder-driven until instrument/sample editors own real state.
    private func reloadInstrumentPlaceholders(for metadata: ParsedModuleMetadata?) {
        guard let controlPanelView else {
            return
        }
        controlPanelView.instrumentSelector.removeAllItems()
        controlPanelView.sampleSelector.removeAllItems()

        guard let metadata, metadata.type == "XM", metadata.instruments > 0 else {
            controlPanelView.instrumentSelector.addItem(withTitle: "No Inst")
            controlPanelView.sampleSelector.addItem(withTitle: "No Sample")
            return
        }

        let visibleInstrumentCount = min(metadata.instruments, 32)
        let instrumentTitles = (0..<visibleInstrumentCount).map { index in
            String(format: "I%02X", index + 1)
        }
        controlPanelView.instrumentSelector.addItems(withTitles: instrumentTitles)
        controlPanelView.instrumentSelector.selectItem(at: 0)
        controlPanelView.sampleSelector.addItem(withTitle: "Sample Map")
    }

}
