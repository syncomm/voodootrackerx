// Owns main-window composition and the top-level view hierarchy for the logo, controls, and tracker region.
// It does not own module-loading decisions, tracker state mutations, or parsing behavior.
import AppKit

final class TrackerWindowController: NSWindowController, NSWindowDelegate {
    private typealias WindowLayout = TrackerThemeMetrics.WindowLayout

    let theme: TrackerTheme
    let defaultWindowSize: NSSize

    let controlPanelView: ControlPanelView
    let trackerEditorView: TrackerEditorView

    var liveResizeWillStartHandler: (() -> Void)?
    var liveResizeDidEndHandler: (() -> Void)?

    init(theme: TrackerTheme = .legacyDark, defaultWindowSize: NSSize = NSSize(width: 1120, height: 900)) {
        self.theme = theme
        self.defaultWindowSize = defaultWindowSize

        let contentView = NSView(frame: NSRect(origin: .zero, size: defaultWindowSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = TrackerChromePalette.windowBackground.cgColor

        let contentWidth = defaultWindowSize.width - (WindowLayout.rootPadding * 2)
        let logoPanelY = defaultWindowSize.height - WindowLayout.rootPadding - WindowLayout.logoPanelHeight
        let controlPanelY = logoPanelY - WindowLayout.sectionSpacing - WindowLayout.controlPanelHeight
        let trackerPanelY = WindowLayout.rootPadding
        let trackerPanelHeight = max(220, controlPanelY - WindowLayout.sectionSpacing - trackerPanelY)

        let logoPanel = LogoPanelView(
            frame: NSRect(
                x: WindowLayout.rootPadding,
                y: logoPanelY,
                width: contentWidth,
                height: WindowLayout.logoPanelHeight
            ),
            theme: theme
        )
        logoPanel.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(logoPanel)

        controlPanelView = ControlPanelView(
            frame: NSRect(
                x: WindowLayout.rootPadding,
                y: controlPanelY,
                width: contentWidth,
                height: WindowLayout.controlPanelHeight
            ),
            theme: theme
        )
        controlPanelView.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(controlPanelView)

        trackerEditorView = TrackerEditorView(
            frame: NSRect(
                x: WindowLayout.rootPadding,
                y: trackerPanelY,
                width: contentWidth,
                height: trackerPanelHeight
            ),
            theme: theme
        )
        trackerEditorView.autoresizingMask = [.width, .height]
        contentView.addSubview(trackerEditorView)

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

    func showWindowAndActivate() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeWillStartHandler?()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeDidEndHandler?()
    }
}
