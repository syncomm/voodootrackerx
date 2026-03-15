// Owns main-window composition and the top-level view hierarchy for the logo, controls, and tracker region.
// It does not own module-loading decisions, tracker state mutations, or parsing behavior.
import AppKit

final class TrackerWindowController: NSWindowController, NSWindowDelegate {
    let theme: TrackerTheme
    let defaultWindowSize: NSSize

    let controlPanelView: ControlPanelView
    let patternInfoLabel: NSTextField
    let patternHeaderTextView: PatternTextView
    let patternHeaderScrollView: NSScrollView
    let metadataTextView: PatternTextView
    let gridScrollView: NSScrollView
    let trackerDividerUnderlayView: TrackerDividerUnderlayView
    let trackerChromeOverlayView: TrackerChromeOverlayView

    var onWillStartLiveResize: (() -> Void)?
    var onDidEndLiveResize: (() -> Void)?

    init(theme: TrackerTheme = .legacyDark, defaultWindowSize: NSSize = NSSize(width: 1120, height: 900)) {
        self.theme = theme
        self.defaultWindowSize = defaultWindowSize

        let trackerBackground = NSColor.black
        let contentView = NSView(frame: NSRect(origin: .zero, size: defaultWindowSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = TrackerChromePalette.windowBackground.cgColor

        let windowLayout = TrackerThemeMetrics.WindowLayout.self
        let contentWidth = defaultWindowSize.width - (windowLayout.rootPadding * 2)
        let logoPanelY = defaultWindowSize.height - windowLayout.rootPadding - windowLayout.logoPanelHeight
        let controlBarY = logoPanelY - windowLayout.sectionSpacing - windowLayout.controlPanelHeight
        let trackerPanelY = windowLayout.rootPadding
        let trackerPanelHeight = max(220, controlBarY - windowLayout.sectionSpacing - trackerPanelY)

        let logoPanel = LogoPanelView(
            frame: NSRect(
                x: windowLayout.rootPadding,
                y: logoPanelY,
                width: contentWidth,
                height: windowLayout.logoPanelHeight
            ),
            theme: theme
        )
        logoPanel.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(logoPanel)

        controlPanelView = ControlPanelView(
            frame: NSRect(
                x: windowLayout.rootPadding,
                y: controlBarY,
                width: contentWidth,
                height: windowLayout.controlPanelHeight
            ),
            theme: theme
        )
        controlPanelView.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(controlPanelView)

        let trackerPanel = NSBox(
            frame: NSRect(
                x: windowLayout.rootPadding,
                y: trackerPanelY,
                width: contentWidth,
                height: trackerPanelHeight
            )
        )
        trackerPanel.autoresizingMask = [.width, .height]
        trackerPanel.boxType = .custom
        trackerPanel.borderWidth = 0
        trackerPanel.fillColor = trackerBackground
        trackerPanel.contentViewMargins = .zero
        contentView.addSubview(trackerPanel)

        patternInfoLabel = NSTextField(labelWithString: "")
        patternInfoLabel.frame = NSRect(x: 0, y: trackerPanel.bounds.height - 24, width: trackerPanel.bounds.width, height: 20)
        patternInfoLabel.autoresizingMask = [.width, .minYMargin]
        patternInfoLabel.font = TrackerThemeFonts.trackerBody
        patternInfoLabel.textColor = theme.text
        patternInfoLabel.lineBreakMode = .byTruncatingTail
        patternInfoLabel.backgroundColor = .clear
        patternInfoLabel.isHidden = true
        trackerPanel.addSubview(patternInfoLabel)

        patternHeaderScrollView = NSScrollView(
            frame: NSRect(
                x: 0,
                y: trackerPanel.bounds.height - windowLayout.trackerHeaderHeight,
                width: trackerPanel.bounds.width,
                height: windowLayout.channelHeaderHeight
            )
        )
        patternHeaderScrollView.autoresizingMask = [.width, .minYMargin]
        patternHeaderScrollView.hasVerticalScroller = false
        patternHeaderScrollView.hasHorizontalScroller = false
        patternHeaderScrollView.verticalScrollElasticity = .none
        patternHeaderScrollView.horizontalScrollElasticity = .none
        patternHeaderScrollView.borderType = .noBorder
        patternHeaderScrollView.drawsBackground = true
        patternHeaderScrollView.backgroundColor = trackerBackground

        patternHeaderTextView = PatternTextView(frame: patternHeaderScrollView.bounds)
        patternHeaderTextView.autoresizingMask = []
        patternHeaderTextView.isEditable = false
        patternHeaderTextView.isRichText = false
        patternHeaderTextView.isSelectable = false
        patternHeaderTextView.isHorizontallyResizable = true
        patternHeaderTextView.isVerticallyResizable = false
        patternHeaderTextView.minSize = NSSize(width: 0, height: 0)
        patternHeaderTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: windowLayout.trackerHeaderHeight)
        patternHeaderTextView.font = TrackerThemeFonts.trackerHeader
        patternHeaderTextView.textContainerInset = NSSize(width: 4, height: 2)
        patternHeaderTextView.drawsBackground = true
        patternHeaderTextView.backgroundColor = trackerBackground
        patternHeaderTextView.textColor = theme.accent
        patternHeaderTextView.textContainer?.lineFragmentPadding = 0
        patternHeaderTextView.textContainer?.widthTracksTextView = false
        patternHeaderTextView.textContainer?.heightTracksTextView = true
        patternHeaderTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: windowLayout.trackerHeaderHeight)
        patternHeaderTextView.textContainer?.lineBreakMode = .byClipping
        patternHeaderTextView.theme = theme
        patternHeaderTextView.drawsDividers = false
        patternHeaderScrollView.documentView = patternHeaderTextView
        patternHeaderScrollView.isHidden = true
        trackerPanel.addSubview(patternHeaderScrollView)

        let bodyHeight = trackerPanel.bounds.height - windowLayout.trackerHeaderHeight - 8
        gridScrollView = NSScrollView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: trackerPanel.bounds.width,
                height: bodyHeight
            )
        )
        gridScrollView.autoresizingMask = [.width, .height]
        gridScrollView.hasVerticalScroller = false
        gridScrollView.hasHorizontalScroller = true
        gridScrollView.verticalScrollElasticity = .none
        gridScrollView.horizontalScrollElasticity = .none
        gridScrollView.borderType = .bezelBorder
        gridScrollView.drawsBackground = true
        gridScrollView.backgroundColor = trackerBackground

        metadataTextView = PatternTextView(frame: gridScrollView.bounds)
        metadataTextView.autoresizingMask = []
        metadataTextView.isEditable = false
        metadataTextView.isRichText = false
        metadataTextView.isSelectable = true
        metadataTextView.isHorizontallyResizable = true
        metadataTextView.isVerticallyResizable = true
        metadataTextView.minSize = NSSize(width: 0, height: 0)
        metadataTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        metadataTextView.font = TrackerThemeFonts.trackerBody
        metadataTextView.drawsBackground = true
        metadataTextView.backgroundColor = trackerBackground
        metadataTextView.textColor = theme.text
        metadataTextView.theme = theme
        metadataTextView.drawsDividers = false
        metadataTextView.textContainerInset = NSSize(width: 4, height: 2)
        metadataTextView.textContainer?.lineFragmentPadding = 0
        metadataTextView.textContainer?.widthTracksTextView = false
        metadataTextView.textContainer?.heightTracksTextView = false
        metadataTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        metadataTextView.textContainer?.lineBreakMode = .byClipping
        metadataTextView.textStorage?.setAttributedString(
            NSAttributedString(
                string: """
                VoodooTracker X

                File > Open… to load a .mod or .xm file and inspect parsed header metadata.
                """,
                attributes: [
                    .font: TrackerThemeFonts.trackerBody,
                    .foregroundColor: theme.text
                ]
            )
        )
        gridScrollView.documentView = metadataTextView
        gridScrollView.contentView.postsBoundsChangedNotifications = true

        trackerDividerUnderlayView = TrackerDividerUnderlayView(frame: trackerPanel.bounds)
        trackerDividerUnderlayView.autoresizingMask = [.width, .height]
        trackerDividerUnderlayView.theme = theme
        trackerDividerUnderlayView.headerScrollView = patternHeaderScrollView
        trackerDividerUnderlayView.bodyTextView = metadataTextView
        trackerDividerUnderlayView.bodyScrollView = gridScrollView
        trackerDividerUnderlayView.isHidden = true

        trackerChromeOverlayView = TrackerChromeOverlayView(frame: trackerPanel.bounds)
        trackerChromeOverlayView.autoresizingMask = [.width, .height]
        trackerChromeOverlayView.theme = theme
        trackerChromeOverlayView.chromeBackgroundColor = trackerBackground
        trackerChromeOverlayView.headerScrollView = patternHeaderScrollView
        trackerChromeOverlayView.bodyTextView = metadataTextView
        trackerChromeOverlayView.bodyScrollView = gridScrollView
        trackerChromeOverlayView.isHidden = true

        trackerPanel.addSubview(gridScrollView)
        trackerPanel.addSubview(trackerChromeOverlayView)
        trackerPanel.addSubview(trackerDividerUnderlayView, positioned: .below, relativeTo: trackerChromeOverlayView)

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoodooTracker X"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = TrackerChromePalette.windowBackground
        window.titlebarAppearsTransparent = true
        window.contentView = contentView
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndActivate() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        onWillStartLiveResize?()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onDidEndLiveResize?()
    }
}
