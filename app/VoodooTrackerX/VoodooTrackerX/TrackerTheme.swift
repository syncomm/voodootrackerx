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

enum TrackerThemeMetrics {
    enum WindowLayout {
        static let rootPadding: CGFloat = 24
        static let sectionSpacing: CGFloat = 12
        static let logoPanelHeight: CGFloat = 260
        static let controlPanelHeight: CGFloat = 112
        static let trackerHeaderHeight: CGFloat = 24
        static let channelHeaderHeight: CGFloat = 24
    }

    enum ControlPanelLayout {
        static let contentInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        static let interRowSpacing: CGFloat = 10
        static let interGroupSpacing: CGFloat = 14
        static let controlStackSpacing: CGFloat = 8
        static let titleLeadSpacing: CGFloat = 18
        static let titleTrailSpacing: CGFloat = 20
        static let labelSpacing: CGFloat = 7
        static let stepperSpacing: CGFloat = 4
    }

    enum ControlPanelSizing {
        static let controlHeight: CGFloat = 28
        static let borderWidth: CGFloat = 1
        static let primaryButtonMinimumWidth: CGFloat = 58
        static let toggleButtonMinimumWidth: CGFloat = 56
        static let compactToggleButtonMinimumWidth: CGFloat = 42
        static let songTitleMinimumWidth: CGFloat = 340
        static let songLengthWidth: CGFloat = 50
        static let songPositionWidth: CGFloat = 40
        static let restartPositionWidth: CGFloat = 50
        static let patternSelectorWidth: CGFloat = 88
        static let rowCountWidth: CGFloat = 58
        static let instrumentSelectorWidth: CGFloat = 118
        static let sampleSelectorWidth: CGFloat = 122
        static let tempoWidth: CGFloat = 48
        static let speedWidth: CGFloat = 48
        static let octaveSelectorWidth: CGFloat = 68
        static let channelCountWidth: CGFloat = 46
        static let stepperWidth: CGFloat = 20
    }

    enum LogoLayout {
        static let horizontalPadding: CGFloat = 48
        static let verticalPadding: CGFloat = 24
        static let maximumWidth: CGFloat = 800
    }

}

@MainActor
enum TrackerThemeFonts {
    static let controlLabel = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    static let controlText = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    static let controlButton = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    static let popup = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    static let trackerBody = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let trackerHeader = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let fallbackLogo = NSFont.systemFont(ofSize: 16, weight: .semibold)
}

@MainActor
enum TrackerThemeStyling {
    static func applyButtonChrome(_ button: NSButton, accentColor: NSColor) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.font = TrackerThemeFonts.controlButton
        button.contentTintColor = accentColor
        button.appearance = NSAppearance(named: .darkAqua)
        button.bezelColor = TrackerChromePalette.recessedFieldBackground
        button.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.ControlPanelSizing.controlHeight).isActive = true
    }

    static func applyPopupChrome(_ button: NSPopUpButton, width: CGFloat, theme: TrackerTheme) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.appearance = NSAppearance(named: .darkAqua)
        button.contentTintColor = theme.text
        button.font = TrackerThemeFonts.popup
        button.bezelColor = TrackerChromePalette.recessedFieldBackground
        button.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.ControlPanelSizing.controlHeight).isActive = true
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    static func applyReadoutChrome(
        _ field: NSTextField,
        width: CGFloat?,
        minimumWidth: CGFloat?,
        alignment: NSTextAlignment,
        theme: TrackerTheme
    ) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isEditable = false
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = TrackerThemeFonts.controlText
        field.textColor = theme.text
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.wantsLayer = true
        field.layer?.backgroundColor = TrackerChromePalette.recessedFieldBackground.cgColor
        field.layer?.borderWidth = TrackerThemeMetrics.ControlPanelSizing.borderWidth
        field.layer?.borderColor = TrackerChromePalette.subtleBorder.cgColor
        field.layer?.cornerRadius = 0
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.ControlPanelSizing.controlHeight).isActive = true
        if let minimumWidth {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
        }
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            field.widthAnchor.constraint(equalToConstant: minimumWidth ?? 220).isActive = true
        }
    }

    static func makeControlLabel(title: String, theme: TrackerTheme) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = TrackerThemeFonts.controlLabel
        label.textColor = theme.accent
        label.alignment = .left
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }
}
