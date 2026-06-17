// Owns shared main-window UI colors, sizing, fonts, and small AppKit styling helpers.
// It does not own window composition, control wiring, or tracker viewport behavior.
import AppKit

struct TrackerTheme {
    let background: NSColor
    let text: NSColor
    let accent: NSColor
    let beatAccent: NSColor
    let cursorOutline: NSColor
    let rowHighlight: NSColor
    let separator: NSColor

    static let legacyDark = TrackerTheme(
        background: NSColor(srgbRed: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1C / 255.0, alpha: 1.0),
        text: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.93, alpha: 1.0),
        accent: NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 1.0),
        beatAccent: NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.22),
        cursorOutline: NSColor(calibratedRed: 1.0, green: 0.26, blue: 0.18, alpha: 1.0),
        rowHighlight: NSColor(calibratedRed: 0.27, green: 0.31, blue: 0.41, alpha: 0.95),
        separator: NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.74)
    )
}

enum TrackerChromePalette {
    static let windowBackground = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1.0)
    static let controlPanelBackground = NSColor(srgbRed: 0x25 / 255.0, green: 0x25 / 255.0, blue: 0x26 / 255.0, alpha: 1.0)
    static let recessedFieldBackground = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1.0)
    static let subtleBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.22)
    static let separatorLine = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.38)
}

enum TrackerControlPalette {
    static let panelTopAccent = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.60)
    static let panelBottomEdge = NSColor(calibratedWhite: 0.0, alpha: 0.60)
    static let readoutFieldBackground = NSColor(srgbRed: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1B / 255.0, alpha: 1.0)
    static let interactiveFieldBackground = NSColor(srgbRed: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1D / 255.0, alpha: 1.0)
    static let readoutBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.22)
    static let interactiveBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.55)
    static let groupSeparator = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.38)
    static let timingGroupSeparator = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.55)
    static let valueText = NSColor(srgbRed: 0xE8 / 255.0, green: 0xD8 / 255.0, blue: 0xA0 / 255.0, alpha: 1.0)
    static let inactiveButtonBackground = NSColor(srgbRed: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x20 / 255.0, alpha: 1.0)
    static let inactiveButtonText = NSColor(srgbRed: 0xE8 / 255.0, green: 0xD8 / 255.0, blue: 0xA0 / 255.0, alpha: 0.55)
    static let inactiveButtonBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.25)
    static let playIdleBackground = NSColor(srgbRed: 0x15 / 255.0, green: 0x2A / 255.0, blue: 0x1A / 255.0, alpha: 1.0)
    static let playIdleText = NSColor(srgbRed: 0x4D / 255.0, green: 0xB8 / 255.0, blue: 0x68 / 255.0, alpha: 1.0)
    static let playIdleBorder = NSColor(srgbRed: 0x4D / 255.0, green: 0xB8 / 255.0, blue: 0x68 / 255.0, alpha: 0.55)
    static let playActiveBackground = NSColor(srgbRed: 0x1A / 255.0, green: 0x3A / 255.0, blue: 0x22 / 255.0, alpha: 1.0)
    static let playActiveText = NSColor(srgbRed: 0x4D / 255.0, green: 0xB8 / 255.0, blue: 0x68 / 255.0, alpha: 1.0)
    static let playActiveBorder = NSColor(srgbRed: 0x4D / 255.0, green: 0xB8 / 255.0, blue: 0x68 / 255.0, alpha: 0.80)
    static let stopActiveBackground = NSColor(srgbRed: 0x3A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0, alpha: 1.0)
    static let stopActiveText = NSColor(srgbRed: 0xCC / 255.0, green: 0x5A / 255.0, blue: 0x50 / 255.0, alpha: 0.70)
    static let stopActiveBorder = NSColor(srgbRed: 0xCC / 255.0, green: 0x5A / 255.0, blue: 0x50 / 255.0, alpha: 0.50)
    static let stopInactiveText = NSColor(srgbRed: 0xCC / 255.0, green: 0x5A / 255.0, blue: 0x50 / 255.0, alpha: 0.42)
    static let stopInactiveBorder = NSColor(srgbRed: 0xCC / 255.0, green: 0x5A / 255.0, blue: 0x50 / 255.0, alpha: 0.24)
    static let toggleInactiveText = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.72)
    static let toggleInactiveBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.38)
    static let toggleActiveBackground = NSColor(srgbRed: 0x2B / 255.0, green: 0x25 / 255.0, blue: 0x14 / 255.0, alpha: 1.0)
    static let toggleActiveBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.80)
}

enum TrackerControlFieldRole {
    case readout
    case interactive
}

enum TrackerThemeMetrics {
    enum WindowLayout {
        static let rootPadding: CGFloat = 24
        static let topContentPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 12
        static let logoControlSpacing: CGFloat = 0
        static let controlTrackerSpacing: CGFloat = 0
        static let logoPanelHeight: CGFloat = 260
        static let controlPanelHeight: CGFloat = 84
        static let trackerHeaderHeight: CGFloat = 24
        static let channelHeaderHeight: CGFloat = 24
    }

    enum ControlPanelLayout {
        static let contentInsets = NSEdgeInsets(top: 8, left: 14, bottom: 10, right: 14)
        static let rowHeight: CGFloat = 28
        static let interRowSpacing: CGFloat = 8
        static let interGroupSpacing: CGFloat = 0
        static let controlStackSpacing: CGFloat = 8
        static let labelSpacing: CGFloat = 8
        static let stepperSpacing: CGFloat = 2
        static let popupTitleVerticalOffset: CGFloat = 2
        static let timingSeparatorExtraSpacing: CGFloat = 3
    }

    enum ControlPanelSizing {
        static let controlHeight: CGFloat = 26
        static let borderWidth: CGFloat = 1
        static let accentLineHeight: CGFloat = 1
        static let panelEdgeLineHeight: CGFloat = 1
        static let groupSeparatorWidth: CGFloat = 1
        static let groupSeparatorFootprint: CGFloat = 21
        static let timingGroupSeparatorFootprint: CGFloat = 27
        static let groupSeparatorHeight: CGFloat = 18
        static let timingGroupSeparatorHeight: CGFloat = 20
        static let primaryButtonMinimumWidth: CGFloat = 55
        static let toggleButtonMinimumWidth: CGFloat = 55
        static let compactToggleButtonMinimumWidth: CGFloat = 42
        static let songTitleMinimumWidth: CGFloat = 220
        static let songTimeWidth: CGFloat = 50
        static let songLengthWidth: CGFloat = 38
        static let songPositionWidth: CGFloat = 38
        static let restartPositionWidth: CGFloat = 38
        static let patternSelectorWidth: CGFloat = 78
        static let rowCountWidth: CGFloat = 46
        static let instrumentSelectorMinimumWidth: CGFloat = 130
        static let sampleSelectorMinimumWidth: CGFloat = 134
        static let tempoWidth: CGFloat = 44
        static let speedWidth: CGFloat = 38
        static let octaveSelectorWidth: CGFloat = 44
        static let channelCountWidth: CGFloat = 38
        static let stepperWidth: CGFloat = 18
    }

    enum LogoLayout {
        static let horizontalPadding: CGFloat = 48
        static let verticalPadding: CGFloat = 24
        static let maximumWidth: CGFloat = 800
    }

}

@MainActor
enum TrackerThemeFonts {
    static let controlLabel = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
    static let controlText = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    static let controlButton = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
    static let popup = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
    static let trackerBody = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let trackerHeader = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let fallbackLogo = NSFont.systemFont(ofSize: 16, weight: .semibold)
}

@MainActor
enum TrackerThemeStyling {
    static func applyButtonChrome(_ button: NSButton, accentColor: NSColor) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.controlSize = .small
        button.font = TrackerThemeFonts.controlButton
        button.contentTintColor = accentColor
        button.appearance = NSAppearance(named: .darkAqua)
        button.bezelColor = TrackerControlPalette.inactiveButtonBackground
        button.wantsLayer = true
        button.layer?.backgroundColor = TrackerControlPalette.inactiveButtonBackground.cgColor
        button.layer?.borderWidth = TrackerThemeMetrics.ControlPanelSizing.borderWidth
        button.layer?.borderColor = TrackerControlPalette.inactiveButtonBorder.cgColor
        button.layer?.cornerRadius = 2
        button.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.ControlPanelSizing.controlHeight).isActive = true
    }

    static func applyPopupChrome(
        _ button: NSPopUpButton,
        width: CGFloat?,
        minimumWidth: CGFloat?,
        theme: TrackerTheme
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.appearance = NSAppearance(named: .darkAqua)
        button.isBordered = false
        button.controlSize = .small
        button.contentTintColor = TrackerControlPalette.valueText
        button.font = TrackerThemeFonts.popup
        button.bezelColor = TrackerControlPalette.interactiveFieldBackground
        button.wantsLayer = true
        button.layer?.backgroundColor = TrackerControlPalette.interactiveFieldBackground.cgColor
        button.layer?.borderWidth = TrackerThemeMetrics.ControlPanelSizing.borderWidth
        button.layer?.borderColor = TrackerControlPalette.interactiveBorder.cgColor
        button.layer?.cornerRadius = 2
        button.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.ControlPanelSizing.controlHeight).isActive = true
        if let width {
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else if let minimumWidth {
            let minimumWidthConstraint = button.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth)
            minimumWidthConstraint.priority = .defaultHigh
            minimumWidthConstraint.isActive = true
        }
    }

    static func applyReadoutChrome(
        _ field: NSTextField,
        width: CGFloat?,
        minimumWidth: CGFloat?,
        alignment: NSTextAlignment,
        theme: TrackerTheme,
        role: TrackerControlFieldRole = .readout
    ) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = false
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = TrackerThemeFonts.controlText
        field.textColor = TrackerControlPalette.valueText
        field.alignment = alignment
        field.cell?.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.wantsLayer = true
        field.layer?.backgroundColor = fieldBackgroundColor(for: role).cgColor
        field.layer?.borderWidth = TrackerThemeMetrics.ControlPanelSizing.borderWidth
        field.layer?.borderColor = fieldBorderColor(for: role).cgColor
        field.layer?.cornerRadius = 2
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.ControlPanelSizing.controlHeight).isActive = true
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else if let minimumWidth {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
        } else {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        }
    }

    static func applyTransportButtonStyle(_ button: NSButton, style: TrackerControlButtonStyle) {
        button.contentTintColor = style.textColor
        button.bezelColor = style.backgroundColor
        button.alphaValue = 1
        button.attributedTitle = transportButtonTitle(button.title, color: style.textColor)
        button.attributedAlternateTitle = transportButtonTitle(button.title, color: style.textColor)
        button.layer?.backgroundColor = style.backgroundColor.cgColor
        button.layer?.borderColor = style.borderColor.cgColor
        button.layer?.borderWidth = TrackerThemeMetrics.ControlPanelSizing.borderWidth
        button.layer?.cornerRadius = 2
    }

    static func makeControlLabel(title: String, theme: TrackerTheme) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = TrackerThemeFonts.controlLabel
        label.textColor = theme.accent
        label.alignment = .left
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: ceil(label.intrinsicContentSize.width)).isActive = true
        return label
    }

    private static func transportButtonTitle(_ title: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: TrackerThemeFonts.controlButton,
                .foregroundColor: color,
                .kern: 0.7
            ]
        )
    }

    private static func fieldBackgroundColor(for role: TrackerControlFieldRole) -> NSColor {
        switch role {
        case .readout:
            return TrackerControlPalette.readoutFieldBackground
        case .interactive:
            return TrackerControlPalette.interactiveFieldBackground
        }
    }

    private static func fieldBorderColor(for role: TrackerControlFieldRole) -> NSColor {
        switch role {
        case .readout:
            return TrackerControlPalette.readoutBorder
        case .interactive:
            return TrackerControlPalette.interactiveBorder
        }
    }
}

enum TrackerControlButtonStyle {
    case inactive
    case playIdle
    case playActive
    case stopInactive
    case stopActive
    case toggleInactive
    case toggleActive

    var backgroundColor: NSColor {
        switch self {
        case .inactive:
            return TrackerControlPalette.inactiveButtonBackground
        case .playIdle:
            return TrackerControlPalette.playIdleBackground
        case .playActive:
            return TrackerControlPalette.playActiveBackground
        case .stopInactive:
            return TrackerControlPalette.readoutFieldBackground
        case .stopActive:
            return TrackerControlPalette.stopActiveBackground
        case .toggleInactive:
            return TrackerControlPalette.inactiveButtonBackground
        case .toggleActive:
            return TrackerControlPalette.toggleActiveBackground
        }
    }

    var textColor: NSColor {
        switch self {
        case .inactive:
            return TrackerControlPalette.inactiveButtonText
        case .playIdle:
            return TrackerControlPalette.playIdleText
        case .playActive:
            return TrackerControlPalette.playActiveText
        case .stopInactive:
            return TrackerControlPalette.stopInactiveText
        case .stopActive:
            return TrackerControlPalette.stopActiveText
        case .toggleInactive:
            return TrackerControlPalette.toggleInactiveText
        case .toggleActive:
            return TrackerTheme.legacyDark.accent
        }
    }

    var borderColor: NSColor {
        switch self {
        case .inactive:
            return TrackerControlPalette.inactiveButtonBorder
        case .playIdle:
            return TrackerControlPalette.playIdleBorder
        case .playActive:
            return TrackerControlPalette.playActiveBorder
        case .stopInactive:
            return TrackerControlPalette.stopInactiveBorder
        case .stopActive:
            return TrackerControlPalette.stopActiveBorder
        case .toggleInactive:
            return TrackerControlPalette.toggleInactiveBorder
        case .toggleActive:
            return TrackerControlPalette.toggleActiveBorder
        }
    }
}
