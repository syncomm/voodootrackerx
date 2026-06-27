import AppKit

enum SongOrderEditorViewIdentifier {
    static let contentView = "songOrderEditor.contentView"
    static let orderListPanel = "songOrderEditor.orderListPanel"
    static let patternBankPanel = "songOrderEditor.patternBankPanel"
    static let patternOpsPanel = "songOrderEditor.patternOpsPanel"
    static let orderOpsPanel = "songOrderEditor.orderOpsPanel"
    static let dangerPanel = "songOrderEditor.dangerPanel"
}

@MainActor
final class SongOrderEditorWindowController: NSWindowController {
    static let contentSize = NSSize(width: 660, height: 480)

    init() {
        let contentView = SongOrderEditorContentView(frame: NSRect(origin: .zero, size: Self.contentSize))
        let panel = NSPanel(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Song / Order"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = VTXEditorControlTheme.windowBackground
        panel.contentView = contentView
        panel.contentMinSize = Self.contentSize
        panel.contentMaxSize = Self.contentSize
        panel.setContentSize(Self.contentSize)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.center()

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}

@MainActor
final class SongOrderEditorContentView: FlippedEditorView {
    private let usedPatterns: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15]
    private let currentPattern = 12
    private let usedPatternFill = NSColor(srgbRed: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x10 / 255.0, alpha: 1.0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(SongOrderEditorViewIdentifier.contentView)
        style(background: VTXEditorControlTheme.windowBackground)
        buildShell()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildShell() {
        addSurface(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.60))
        buildOrderListPanel(panel(SongOrderEditorViewIdentifier.orderListPanel, "Order list", "— the song sequence", NSRect(x: 12, y: 13, width: 296, height: 320)))
        buildPatternBankPanel(panel(SongOrderEditorViewIdentifier.patternBankPanel, "Pattern bank", nil, NSRect(x: 318, y: 13, width: 330, height: 250)))
        buildPatternOpsPanel(panel(SongOrderEditorViewIdentifier.patternOpsPanel, "Pattern ops", nil, NSRect(x: 318, y: 273, width: 330, height: 60)))
        buildOrderOpsPanel(panel(SongOrderEditorViewIdentifier.orderOpsPanel, "Order ops", "— act on selected slot (ORD 010)", NSRect(x: 12, y: 343, width: 636, height: 66)))
        buildDangerPanel(plainPanel(SongOrderEditorViewIdentifier.dangerPanel, NSRect(x: 12, y: 419, width: 636, height: 49), border: VTXEditorControlTheme.dangerRed.withAlphaComponent(0.35)))
    }

    private func buildOrderListPanel(_ panel: NSView) {
        let list = addSurface(in: panel, frame: NSRect(x: 10, y: 32, width: 276, height: 242), background: VTXEditorControlTheme.recessedReadoutBackground, border: VTXEditorControlTheme.mutedGoldBorderSubtle, radius: 3)
        addOrderHeader(to: list)
        let rows = [
            ("007", "004", "064", false), ("008", "004", "064", false),
            ("009", "012", "064", false), ("010", "012", "064", true),
            ("011", "007", "128", false), ("012", "008", "064", false),
            ("013", "008", "064", false), ("014", "015", "032", false),
            ("015", "003", "064", false), ("016", "003", "064", false),
            ("017", "009", "064", false),
        ]
        for (index, row) in rows.enumerated() {
            addOrderRow(to: list, y: 20 + CGFloat(index * 18), order: row.0, pattern: row.1, rows: row.2, selected: row.3)
        }
        addLabel("ORD = order position", to: panel, frame: NSRect(x: 10, y: 286, width: 124, height: 14), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40), size: 9)
        addLabel("PTN = pattern number", to: panel, frame: NSRect(x: 146, y: 286, width: 130, height: 14), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40), size: 9)
    }

    private func addOrderHeader(to parent: NSView) {
        addLabel("ORD", to: parent, frame: NSRect(x: 10, y: 4, width: 52, height: 12), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addLabel("PTN", to: parent, frame: NSRect(x: 70, y: 4, width: 70, height: 12), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold, alignment: .center)
        addLabel("ROWS", to: parent, frame: NSRect(x: 148, y: 4, width: 64, height: 12), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addHorizontalRule(to: parent, y: 19, width: 276, alpha: 0.12)
    }

    private func addOrderRow(to parent: NSView, y: CGFloat, order: String, pattern: String, rows: String, selected: Bool) {
        let row = addSurface(in: parent, frame: NSRect(x: 0, y: y, width: 276, height: 18), background: selected ? VTXEditorControlTheme.indigoSelection : VTXEditorControlTheme.recessedReadoutBackground)
        addLabel(order, to: row, frame: NSRect(x: 10, y: 2, width: 52, height: 13), color: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55), size: 10)
        addLabel(pattern, to: row, frame: NSRect(x: 70, y: 1, width: 70, height: 14), color: VTXEditorControlTheme.warmValueText, size: 10.5, weight: .bold, alignment: .center)
        addLabel(rows, to: row, frame: NSRect(x: 148, y: 2, width: 64, height: 13), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.48), size: 10, alignment: .left)
        addHorizontalRule(to: parent, y: y + 17, width: 276, alpha: 0.05)
    }

    private func buildPatternBankPanel(_ panel: NSView) {
        addCenteredLabel("000-063", to: panel, frame: NSRect(x: 126, y: 5, width: 50, height: 22), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.50), size: 9)
        addButton("◀", to: panel, frame: NSRect(x: 180, y: 5, width: 22, height: 22))
        addButton("▶", to: panel, frame: NSRect(x: 207, y: 5, width: 22, height: 22))
        addSegment("BANK 1/4", to: panel, frame: NSRect(x: 234, y: 5, width: 73, height: 22), fontSize: 9)

        for row in 0..<8 {
            for column in 0..<8 {
                let index = (row * 8) + column
                addPatternCell(index, to: panel, frame: NSRect(x: 10 + CGFloat(column * 38), y: 35 + CGFloat(row * 25), width: 31, height: 23))
            }
        }

        addSwatch(to: panel, frame: NSRect(x: 10, y: 237, width: 9, height: 9), color: usedPatternFill)
        addSurface(in: panel, frame: NSRect(x: 10, y: 237, width: 2, height: 9), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55))
        addLabel("used in song", to: panel, frame: NSRect(x: 24, y: 234, width: 78, height: 14), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40), size: 9)
        addLED(to: panel, frame: NSRect(x: 116, y: 237, width: 8, height: 8))
        addLabel("current pattern", to: panel, frame: NSRect(x: 129, y: 234, width: 96, height: 14), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40), size: 9)
        addSwatch(to: panel, frame: NSRect(x: 242, y: 237, width: 9, height: 9), color: VTXEditorControlTheme.recessedReadoutBackground)
        addLabel("empty", to: panel, frame: NSRect(x: 256, y: 234, width: 48, height: 14), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40), size: 9)
    }

    private func addPatternCell(_ index: Int, to parent: NSView, frame: NSRect) {
        let used = usedPatterns.contains(index)
        let current = index == currentPattern
        let cell = addSurface(
            in: parent,
            frame: frame,
            background: used ? usedPatternFill : VTXEditorControlTheme.recessedReadoutBackground,
            border: current ? VTXEditorControlTheme.accentGold : (used ? VTXEditorControlTheme.mutedGoldBorderMedium : VTXEditorControlTheme.mutedGoldBorderSubtle),
            radius: 2
        )
        if used {
            addSurface(in: cell, frame: NSRect(x: 0, y: 0, width: 2, height: frame.height), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55))
        }
        addCenteredLabel(String(format: "%02d", index), to: cell, frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height), color: used ? VTXEditorControlTheme.warmValueText : VTXEditorControlTheme.warmValueText.withAlphaComponent(0.42), size: 9.5, weight: used ? .semibold : .regular, alignment: .center)
        if current {
            addLED(to: cell, frame: NSRect(x: frame.width - 9, y: 3, width: 7, height: 7))
        }
    }

    private func buildPatternOpsPanel(_ panel: NSView) {
        addButton("+ NEW", to: panel, frame: NSRect(x: 10, y: 29, width: 68, height: 25))
        addButton("⧉ DUP", to: panel, frame: NSRect(x: 84, y: 29, width: 68, height: 25))
        addButton("⌫ CLEAR", to: panel, frame: NSRect(x: 158, y: 29, width: 84, height: 25))
    }

    private func buildOrderOpsPanel(_ panel: NSView) {
        var x: CGFloat = 10
        for (title, width) in [("+ INSERT", 84), ("⌫ DELETE", 84), ("⧉ DUP", 66)] {
            addButton(title, to: panel, frame: NSRect(x: x, y: 31, width: CGFloat(width), height: 25))
            x += CGFloat(width + 6)
        }
        x += 10
        addSeparator(to: panel, x: x, y: 34)
        x += 18
        for (title, width) in [("▲ MOVE UP", 94), ("▼ MOVE DOWN", 108)] {
            addButton(title, to: panel, frame: NSRect(x: x, y: 31, width: CGFloat(width), height: 25))
            x += CGFloat(width + 6)
        }
        x += 12
        addSeparator(to: panel, x: x, y: 34)
        x += 24
        addLabel("PTN", to: panel, frame: NSRect(x: x, y: 37, width: 24, height: 14), color: VTXEditorControlTheme.accentGold, size: 9, weight: .bold)
        addButton("-", to: panel, frame: NSRect(x: x + 25, y: 31, width: 28, height: 25))
        addButton("+", to: panel, frame: NSRect(x: x + 57, y: 31, width: 28, height: 25))
    }

    private func buildDangerPanel(_ panel: NSView) {
        addButton("⌫ CLEAR SONG", to: panel, frame: NSRect(x: 10, y: 12, width: 124, height: 25), role: .danger)
        addLabel(
            "Clears arrangement / order data. Instruments and samples are preserved.",
            to: panel,
            frame: NSRect(x: 146, y: 17, width: 472, height: 16),
            color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.46),
            size: 9
        )
    }

    @discardableResult
    private func panel(_ identifier: String, _ title: String, _ hint: String?, _ frame: NSRect, border: NSColor = VTXEditorControlTheme.mutedGoldBorderFaint) -> NSView {
        let panel = addSurface(frame: frame, background: VTXEditorControlTheme.panelSurface, border: border, radius: 4)
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        let titleWidth = min(frame.width - 20, max(58, CGFloat(title.count) * 6.2 + 2))
        addControl(VTXEditorControlFactory.makePanelLabel(title), to: panel, frame: NSRect(x: 10, y: 10, width: titleWidth, height: 12))
        if let hint {
            addLabel(hint, to: panel, frame: NSRect(x: 10 + titleWidth + 6, y: 10, width: frame.width - titleWidth - 26, height: 12), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.32), size: 8.5)
        }
        return panel
    }

    @discardableResult
    private func plainPanel(_ identifier: String, _ frame: NSRect, border: NSColor) -> NSView {
        let panel = addSurface(frame: frame, background: VTXEditorControlTheme.panelSurface, border: border, radius: 4)
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        return panel
    }

    private func addSegment(_ value: String, to parent: NSView, frame: NSRect, fontSize: CGFloat? = nil) {
        let readout = VTXEditorControlFactory.makeSegmentReadout(value: value, fixedWidth: frame.width)
        if let fontSize {
            readout.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        }
        addControl(readout, to: parent, frame: frame)
    }

    private func addButton(_ title: String, to parent: NSView, frame: NSRect, role: VTXEditorButtonRole = .normal) {
        let button = VTXEditorControlFactory.makeButton(title: title, role: role, fixedWidth: frame.width)
        button.isEnabled = true
        button.target = nil
        button.action = nil
        button.sendAction(on: [])
        button.toolTip = "Inactive shell control"
        addControl(button, to: parent, frame: frame)
    }

    private func addLED(to parent: NSView, frame: NSRect) {
        addControl(VTXEditorControlFactory.makeIndicatorLED(state: .redActive, diameter: frame.width), to: parent, frame: frame)
    }

    private func addSwatch(to parent: NSView, frame: NSRect, color: NSColor) {
        _ = addSurface(in: parent, frame: frame, background: color, border: VTXEditorControlTheme.mutedGoldBorderSubtle, radius: 2)
    }

    private func addSeparator(to parent: NSView, x: CGFloat, y: CGFloat) {
        _ = addSurface(in: parent, frame: NSRect(x: x, y: y, width: 1, height: 18), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.38))
    }

    private func addHorizontalRule(to parent: NSView, y: CGFloat, width: CGFloat, alpha: CGFloat) {
        _ = addSurface(in: parent, frame: NSRect(x: 0, y: y, width: width, height: 1), background: VTXEditorControlTheme.accentGold.withAlphaComponent(alpha))
    }

    private func addLabel(
        _ text: String,
        to parent: NSView,
        frame: NSRect,
        color: NSColor,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        alignment: NSTextAlignment = .left
    ) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        addControl(label, to: parent, frame: frame)
    }

    private func addCenteredLabel(
        _ text: String,
        to parent: NSView,
        frame: NSRect,
        color: NSColor,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        alignment: NSTextAlignment = .left
    ) {
        let label = NSTextField(frame: .zero)
        let cell = TrackerCenteredTextFieldCell(textCell: text)
        cell.horizontalInset = 0
        label.cell = cell
        label.stringValue = text
        label.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.cell?.alignment = alignment
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.focusRingType = .none
        label.lineBreakMode = .byTruncatingTail
        addControl(label, to: parent, frame: frame)
    }

    @discardableResult
    private func addSurface(
        frame: NSRect,
        background: NSColor,
        border: NSColor? = nil,
        radius: CGFloat = 0
    ) -> FlippedEditorView {
        addSurface(in: self, frame: frame, background: background, border: border, radius: radius)
    }

    @discardableResult
    private func addSurface(
        in parent: NSView,
        frame: NSRect,
        background: NSColor,
        border: NSColor? = nil,
        radius: CGFloat = 0
    ) -> FlippedEditorView {
        let view = FlippedEditorView(frame: frame)
        view.style(background: background, border: border, radius: radius)
        parent.addSubview(view)
        return view
    }

    private func addControl(_ view: NSView, to parent: NSView, frame: NSRect) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = frame
        parent.addSubview(view)
    }
}

class FlippedEditorView: NSView {
    override var isFlipped: Bool { true }

    func style(background: NSColor, border: NSColor? = nil, radius: CGFloat = 0) {
        wantsLayer = true
        layer?.backgroundColor = background.cgColor
        layer?.cornerRadius = radius
        if let border {
            layer?.borderWidth = VTXEditorControlMetrics.borderWidth
            layer?.borderColor = border.cgColor
        }
    }
}
