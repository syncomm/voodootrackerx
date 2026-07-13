// Shared AppKit primitives for future editor utility windows.
// These controls are additive and are not wired into the main tracker window.
import AppKit

enum VTXEditorControlTheme {
    static let windowBackground = TrackerChromePalette.windowBackground
    static let panelSurface = TrackerChromePalette.controlPanelBackground
    static let recessedReadoutBackground = NSColor(srgbRed: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x19 / 255.0, alpha: 1.0)
    static let interactiveFieldBackground = TrackerControlPalette.interactiveFieldBackground
    static let accentGold = TrackerTheme.legacyDark.accent
    static let mutedGoldBorderStrong = TrackerControlPalette.interactiveBorder
    static let mutedGoldBorderMedium = TrackerControlPalette.groupSeparator
    static let mutedGoldBorderSubtle = TrackerControlPalette.readoutBorder
    static let mutedGoldBorderFaint = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.12)
    static let warmValueText = TrackerControlPalette.valueText
    static let playActiveGreen = TrackerControlPalette.playIdleText
    static let indigoSelection = NSColor(srgbRed: 0x46 / 255.0, green: 0x54 / 255.0, blue: 0x7D / 255.0, alpha: 0.55)
    static let indicatorLEDRed = NSColor(srgbRed: 0xE0 / 255.0, green: 0x47 / 255.0, blue: 0x3A / 255.0, alpha: 1.0)
    static let dangerRed = NSColor(srgbRed: 0xCC / 255.0, green: 0x5A / 255.0, blue: 0x50 / 255.0, alpha: 1.0)
    static let panelLabelText = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.60)
    static let ledOffFill = NSColor(srgbRed: 0x2A / 255.0, green: 0x18 / 255.0, blue: 0x16 / 255.0, alpha: 1.0)
    static let amberLED = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 1.0)
}

@MainActor
enum VTXEditorControlFonts {
    static let panelLabel = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold)
    static let segmentReadout = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    static let button = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
}

enum VTXEditorControlMetrics {
    static let borderWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 2
    static let segmentReadoutHeight: CGFloat = 23
    static let editorButtonHeight: CGFloat = 25
    static let defaultLEDSize: CGFloat = 8
    static let knobControlSize = NSSize(width: 72, height: 72)
    static let panSliderControlSize = NSSize(width: 170, height: 32)
}

enum VTXEditorIndicatorLEDState: Equatable {
    case off
    case redActive
    case amberActive
}

final class VTXEditorIndicatorLEDView: NSView {
    var state: VTXEditorIndicatorLEDState {
        didSet {
            needsDisplay = true
        }
    }

    let diameter: CGFloat

    var fillColor: NSColor {
        switch state {
        case .off:
            return VTXEditorControlTheme.ledOffFill
        case .redActive:
            return VTXEditorControlTheme.indicatorLEDRed
        case .amberActive:
            return VTXEditorControlTheme.amberLED
        }
    }

    private var glowColor: NSColor {
        switch state {
        case .off:
            return .black.withAlphaComponent(0.0)
        case .redActive:
            return VTXEditorControlTheme.indicatorLEDRed.withAlphaComponent(0.85)
        case .amberActive:
            return VTXEditorControlTheme.amberLED.withAlphaComponent(0.80)
        }
    }

    init(state: VTXEditorIndicatorLEDState = .off, diameter: CGFloat = VTXEditorControlMetrics.defaultLEDSize) {
        self.state = state
        self.diameter = diameter
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: diameter, height: diameter)))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: diameter).isActive = true
        heightAnchor.constraint(equalToConstant: diameter).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let inset = max(CGFloat(1), min(bounds.width, bounds.height) * 0.12)
        let lampRect = bounds.insetBy(dx: inset, dy: inset)
        context.saveGState()
        context.setShadow(offset: .zero, blur: state == .off ? 0 : 6, color: glowColor.cgColor)
        context.setFillColor(fillColor.cgColor)
        context.fillEllipse(in: lampRect)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: lampRect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }
}

final class VTXEditorSegmentReadout: NSTextField {
    let fixedWidth: CGFloat?
    let minimumWidth: CGFloat?

    init(
        value: String,
        fixedWidth: CGFloat? = nil,
        minimumWidth: CGFloat? = nil,
        alignment: NSTextAlignment = .center
    ) {
        self.fixedWidth = fixedWidth
        self.minimumWidth = minimumWidth
        super.init(frame: .zero)
        cell = TrackerCenteredTextFieldCell(textCell: value)
        stringValue = value
        applySegmentReadoutStyle(alignment: alignment)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applySegmentReadoutStyle(alignment: NSTextAlignment) {
        translatesAutoresizingMaskIntoConstraints = false
        isEditable = false
        isSelectable = true
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = VTXEditorControlFonts.segmentReadout
        textColor = VTXEditorControlTheme.warmValueText
        self.alignment = alignment
        cell?.alignment = alignment
        cell?.usesSingleLineMode = true
        cell?.isScrollable = true
        lineBreakMode = .byTruncatingTail
        wantsLayer = true
        layer?.backgroundColor = VTXEditorControlTheme.recessedReadoutBackground.cgColor
        layer?.borderWidth = VTXEditorControlMetrics.borderWidth
        layer?.borderColor = VTXEditorControlTheme.mutedGoldBorderSubtle.cgColor
        layer?.cornerRadius = VTXEditorControlMetrics.cornerRadius
        heightAnchor.constraint(equalToConstant: VTXEditorControlMetrics.segmentReadoutHeight).isActive = true
        if let fixedWidth {
            widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        } else if let minimumWidth {
            widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
        }
    }
}

enum VTXEditorButtonRole: Equatable {
    case normal
    case selected
    case activePlay
    case danger

    var backgroundColor: NSColor {
        switch self {
        case .normal:
            return VTXEditorControlTheme.interactiveFieldBackground
        case .selected:
            return VTXEditorControlTheme.indigoSelection
        case .activePlay:
            return NSColor(srgbRed: 0x15 / 255.0, green: 0x2A / 255.0, blue: 0x1A / 255.0, alpha: 1.0)
        case .danger:
            return NSColor(srgbRed: 0x2A / 255.0, green: 0x18 / 255.0, blue: 0x16 / 255.0, alpha: 1.0)
        }
    }

    var textColor: NSColor {
        switch self {
        case .normal:
            return VTXEditorControlTheme.warmValueText
        case .selected:
            return VTXEditorControlTheme.accentGold
        case .activePlay:
            return VTXEditorControlTheme.playActiveGreen
        case .danger:
            return VTXEditorControlTheme.dangerRed
        }
    }

    var borderColor: NSColor {
        switch self {
        case .normal:
            return VTXEditorControlTheme.mutedGoldBorderMedium
        case .selected:
            return VTXEditorControlTheme.accentGold.withAlphaComponent(0.60)
        case .activePlay:
            return VTXEditorControlTheme.playActiveGreen.withAlphaComponent(0.55)
        case .danger:
            return VTXEditorControlTheme.dangerRed.withAlphaComponent(0.55)
        }
    }
}

final class VTXEditorButton: NSButton {
    private(set) var editorRole: VTXEditorButtonRole

    init(
        title: String,
        role: VTXEditorButtonRole = .normal,
        fixedWidth: CGFloat? = nil
    ) {
        editorRole = role
        super.init(frame: .zero)
        self.title = title.uppercased()
        setButtonType(.momentaryPushIn)
        configureBaseChrome(fixedWidth: fixedWidth)
        apply(role: role)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(role: VTXEditorButtonRole) {
        editorRole = role
        contentTintColor = role.textColor
        bezelColor = role.backgroundColor
        attributedTitle = attributedButtonTitle(title, color: role.textColor)
        attributedAlternateTitle = attributedButtonTitle(title, color: role.textColor)
        layer?.backgroundColor = role.backgroundColor.cgColor
        layer?.borderColor = role.borderColor.cgColor
    }

    private func configureBaseChrome(fixedWidth: CGFloat?) {
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .shadowlessSquare
        isBordered = false
        controlSize = .small
        font = VTXEditorControlFonts.button
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.borderWidth = VTXEditorControlMetrics.borderWidth
        layer?.cornerRadius = VTXEditorControlMetrics.cornerRadius
        heightAnchor.constraint(equalToConstant: VTXEditorControlMetrics.editorButtonHeight).isActive = true
        if let fixedWidth {
            widthAnchor.constraint(equalToConstant: fixedWidth).isActive = true
        }
    }

    private func attributedButtonTitle(_ title: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: VTXEditorControlFonts.button,
                .foregroundColor: color,
                .kern: 0.5
            ]
        )
    }
}

@MainActor
enum VTXEditorControlFactory {
    static func makePanelLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = VTXEditorControlFonts.panelLabel
        label.textColor = VTXEditorControlTheme.panelLabelText
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    static func makeSegmentReadout(
        value: String,
        fixedWidth: CGFloat? = nil,
        minimumWidth: CGFloat? = nil,
        alignment: NSTextAlignment = .center
    ) -> VTXEditorSegmentReadout {
        VTXEditorSegmentReadout(
            value: value,
            fixedWidth: fixedWidth,
            minimumWidth: minimumWidth,
            alignment: alignment
        )
    }

    static func makeIndicatorLED(
        state: VTXEditorIndicatorLEDState = .off,
        diameter: CGFloat = VTXEditorControlMetrics.defaultLEDSize
    ) -> VTXEditorIndicatorLEDView {
        VTXEditorIndicatorLEDView(state: state, diameter: diameter)
    }

    static func makeButton(
        title: String,
        role: VTXEditorButtonRole = .normal,
        fixedWidth: CGFloat? = nil
    ) -> VTXEditorButton {
        VTXEditorButton(
            title: title,
            role: role,
            fixedWidth: fixedWidth
        )
    }

    static func makeKnobControl(
        value: Double = 0,
        minimumValue: Double = 0,
        maximumValue: Double = 1,
        isEmphasized: Bool = false
    ) -> VTXEditorKnobControl {
        VTXEditorKnobControl(
            value: value,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            isEmphasized: isEmphasized
        )
    }

    static func makePanSliderControl(
        value: Double = 0,
        centerDetentThreshold: Double = 0.05,
        snapsToCenter: Bool = true,
        showsCenteredIndicator: Bool = true
    ) -> VTXEditorPanSliderControl {
        VTXEditorPanSliderControl(
            value: value,
            centerDetentThreshold: centerDetentThreshold,
            snapsToCenter: snapsToCenter,
            showsCenteredIndicator: showsCenteredIndicator
        )
    }
}
