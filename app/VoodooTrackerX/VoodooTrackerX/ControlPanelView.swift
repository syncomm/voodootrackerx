// Owns the two-row control panel UI and its local chrome/layout rules.
// It does not own app state, module loading, or tracker rendering behavior.
import AppKit

final class TrackerCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let baselineRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let delta = max(0, floor((rect.height - textSize.height) * 0.5) - 1)
        return baselineRect.offsetBy(dx: 0, dy: delta)
    }
}

struct ControlPanelContent: Equatable {
    var songTitle = "No Module Loaded"
    var songLength = "--"
    var songPosition = "--"
    var restartPosition = "--"
    var patternRowCount = "--"
    var channelCount = "--"
    var tempo = "125"
    var speed = "06"
    var selectedOctave = 4
    var songPositionValue = 0
    var maximumSongPosition = 0
    var isLoopEnabled = false
    var isEditModeEnabled = false
    var isPlaybackActive = false
    var isSongPositionEnabled = false
    var isPatternControlsEnabled = false
    var areInstrumentPlaceholdersEnabled = false
}

final class ControlPanelView: NSView {
    private typealias Layout = TrackerThemeMetrics.ControlPanelLayout
    private typealias Sizing = TrackerThemeMetrics.ControlPanelSizing

    let playButton = ControlPanelView.makeButton(title: "PLAY", symbolName: "play.fill")
    let stopButton = ControlPanelView.makeButton(title: "STOP", symbolName: "stop.fill")
    let loopButton = ControlPanelView.makeToggleButton(title: "LOOP", symbolName: "repeat")
    let editModeButton = ControlPanelView.makeToggleButton(title: "EDIT", symbolName: "record.circle")
    let songTitleField = ControlPanelView.makeReadoutField(width: nil, minimumWidth: Sizing.songTitleMinimumWidth, alignment: .center)
    let songLengthField = ControlPanelView.makeReadoutField(width: Sizing.songLengthWidth, alignment: .center)
    let songPositionField = ControlPanelView.makeReadoutField(width: Sizing.songPositionWidth, alignment: .center)
    let songPositionStepper = ControlPanelView.makeStepper()
    let restartPositionField = ControlPanelView.makeReadoutField(width: Sizing.restartPositionWidth, alignment: .center)
    let patternSelector = ControlPanelView.makePopupButton(width: Sizing.patternSelectorWidth)
    let patternRowCountField = ControlPanelView.makeReadoutField(width: Sizing.rowCountWidth, alignment: .center)
    let instrumentSelector = ControlPanelView.makePopupButton(width: Sizing.instrumentSelectorWidth)
    let sampleSelector = ControlPanelView.makePopupButton(width: Sizing.sampleSelectorWidth)
    let tempoField = ControlPanelView.makeReadoutField(width: Sizing.tempoWidth, alignment: .center)
    let speedField = ControlPanelView.makeReadoutField(width: Sizing.speedWidth, alignment: .center)
    let octaveSelector = ControlPanelView.makePopupButton(width: Sizing.octaveSelectorWidth)
    let channelCountField = ControlPanelView.makeReadoutField(width: Sizing.channelCountWidth, alignment: .center)

    private let theme: TrackerTheme

    init(frame frameRect: NSRect, theme: TrackerTheme = .legacyDark) {
        self.theme = theme
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = TrackerChromePalette.controlPanelBackground.cgColor
        layer?.borderWidth = Sizing.borderWidth
        layer?.borderColor = TrackerChromePalette.subtleBorder.cgColor

        buildHierarchy()
        configureDefaults()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ content: ControlPanelContent) {
        songTitleField.stringValue = content.songTitle
        songLengthField.stringValue = content.songLength
        songPositionField.stringValue = content.songPosition
        restartPositionField.stringValue = content.restartPosition
        patternRowCountField.stringValue = content.patternRowCount
        channelCountField.stringValue = content.channelCount
        tempoField.stringValue = content.tempo
        speedField.stringValue = content.speed
        octaveSelector.selectItem(withTitle: String(content.selectedOctave))
        loopButton.state = content.isLoopEnabled ? .on : .off
        editModeButton.state = content.isEditModeEnabled ? .on : .off
        playButton.isEnabled = !content.isPlaybackActive
        stopButton.isEnabled = content.isPlaybackActive
        songPositionStepper.integerValue = content.songPositionValue
        songPositionStepper.maxValue = Double(content.maximumSongPosition)
        songPositionStepper.isEnabled = content.isSongPositionEnabled
        patternSelector.isEnabled = content.isPatternControlsEnabled
        instrumentSelector.isEnabled = content.areInstrumentPlaceholdersEnabled
        sampleSelector.isEnabled = content.areInstrumentPlaceholdersEnabled
    }

    private func buildHierarchy() {
        let rootStack = NSStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.distribution = .fill
        rootStack.spacing = Layout.interRowSpacing
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.contentInsets.left),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.contentInsets.right),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: Layout.contentInsets.top),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.contentInsets.bottom)
        ])

        rootStack.addArrangedSubview(makeTopRow())
        rootStack.addArrangedSubview(makeBottomRow())
    }

    private func configureDefaults() {
        octaveSelector.addItems(withTitles: (0...8).map(String.init))
        octaveSelector.selectItem(withTitle: "4")
        instrumentSelector.addItem(withTitle: "No Inst")
        sampleSelector.addItem(withTitle: "No Sample")
        tempoField.stringValue = "125"
        speedField.stringValue = "06"
        songTitleField.stringValue = "No Module Loaded"
        songLengthField.stringValue = "--"
        songPositionField.stringValue = "--"
        restartPositionField.stringValue = "--"
        patternRowCountField.stringValue = "--"
        channelCountField.stringValue = "--"
        playButton.toolTip = "Playback UI placeholder"
        stopButton.toolTip = "Playback UI placeholder"
        loopButton.toolTip = "Loop toggle placeholder"
        restartPositionField.toolTip = "Restart position placeholder until playback state exists"
        tempoField.toolTip = "Tempo placeholder until audio engine integration"
        speedField.toolTip = "Speed placeholder until audio engine integration"
        songTitleField.toolTip = "Song title metadata"
        instrumentSelector.toolTip = "Instrument selector placeholder until instrument editor exists"
        sampleSelector.toolTip = "Sample selector placeholder until sample editor exists"
    }

    private func makeTopRow() -> NSStackView {
        let transportButtons = NSStackView(views: [playButton, stopButton, loopButton, editModeButton])
        transportButtons.translatesAutoresizingMaskIntoConstraints = false
        transportButtons.orientation = .horizontal
        transportButtons.alignment = .centerY
        transportButtons.spacing = Layout.controlStackSpacing

        let songMetaControls = NSStackView(views: [
            makeInlineGroup(label: "LEN", content: songLengthField),
            makeInlineGroup(label: "POS", content: makeStepperFieldPair(field: songPositionField, stepper: songPositionStepper)),
            makeInlineGroup(label: "RST", content: restartPositionField)
        ])
        songMetaControls.translatesAutoresizingMaskIntoConstraints = false
        songMetaControls.orientation = .horizontal
        songMetaControls.alignment = .centerY
        songMetaControls.spacing = Layout.controlStackSpacing

        let titleGroup = makeInlineGroup(label: "TITLE", content: songTitleField)
        titleGroup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            transportButtons,
            makeFixedSpacer(width: Layout.titleLeadSpacing),
            titleGroup,
            makeFixedSpacer(width: Layout.titleTrailSpacing),
            songMetaControls,
            makeFlexibleSpacer()
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = Layout.interGroupSpacing
        return row
    }

    private func makeBottomRow() -> NSStackView {
        songTitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        songTitleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let patternControls = NSStackView(views: [
            makeInlineGroup(label: "PATTERN", content: patternSelector),
            makeInlineGroup(label: "ROWS", content: patternRowCountField)
        ])
        patternControls.translatesAutoresizingMaskIntoConstraints = false
        patternControls.orientation = .horizontal
        patternControls.alignment = .centerY
        patternControls.spacing = Layout.controlStackSpacing

        let sourceControls = NSStackView(views: [
            makeInlineGroup(label: "INST", content: instrumentSelector),
            makeInlineGroup(label: "SMP", content: sampleSelector)
        ])
        sourceControls.translatesAutoresizingMaskIntoConstraints = false
        sourceControls.orientation = .horizontal
        sourceControls.alignment = .centerY
        sourceControls.spacing = Layout.controlStackSpacing

        let editControls = NSStackView(views: [
            makeInlineGroup(label: "TEMPO", content: tempoField),
            makeInlineGroup(label: "SPEED", content: speedField),
            makeInlineGroup(label: "OCT", content: octaveSelector),
            makeInlineGroup(label: "CHN", content: channelCountField)
        ])
        editControls.translatesAutoresizingMaskIntoConstraints = false
        editControls.orientation = .horizontal
        editControls.alignment = .centerY
        editControls.spacing = Layout.controlStackSpacing

        let row = NSStackView(views: [
            patternControls,
            sourceControls,
            editControls,
            makeFlexibleSpacer()
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = Layout.interGroupSpacing
        return row
    }

    private func makeInlineGroup(label title: String, content: NSView) -> NSStackView {
        let label = TrackerThemeStyling.makeControlLabel(title: title, theme: theme)
        let stack = NSStackView(views: [label, content])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = Layout.labelSpacing
        return stack
    }

    private func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func makeFixedSpacer(width: CGFloat) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: width).isActive = true
        spacer.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.required, for: .horizontal)
        return spacer
    }

    private func makeStepperFieldPair(field: NSTextField, stepper: NSStepper) -> NSView {
        let pair = NSStackView(views: [field, stepper])
        pair.translatesAutoresizingMaskIntoConstraints = false
        pair.orientation = .horizontal
        pair.alignment = .centerY
        pair.spacing = Layout.stepperSpacing
        return pair
    }

    private static func makeButton(title: String, symbolName: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.momentaryPushIn)
        TrackerThemeStyling.applyButtonChrome(button, accentColor: TrackerTheme.legacyDark.text)
        applySymbol(symbolName, to: button)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Sizing.primaryButtonMinimumWidth).isActive = true
        return button
    }

    private static func makeToggleButton(title: String, symbolName: String? = nil, compact: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        TrackerThemeStyling.applyButtonChrome(button, accentColor: TrackerTheme.legacyDark.accent)
        applySymbol(symbolName, to: button)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: compact ? Sizing.compactToggleButtonMinimumWidth : Sizing.toggleButtonMinimumWidth).isActive = true
        return button
    }

    private static func makePopupButton(width: CGFloat) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        TrackerThemeStyling.applyPopupChrome(button, width: width, theme: .legacyDark)
        return button
    }

    private static func makeReadoutField(width: CGFloat?, minimumWidth: CGFloat? = nil, alignment: NSTextAlignment) -> NSTextField {
        let field = NSTextField(string: "")
        field.cell = TrackerCenteredTextFieldCell(textCell: "")
        TrackerThemeStyling.applyReadoutChrome(field, width: width, minimumWidth: minimumWidth, alignment: alignment, theme: .legacyDark)
        return field
    }

    private static func makeStepper() -> NSStepper {
        let stepper = NSStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.controlSize = .small
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.maxValue = 0
        stepper.minValue = 0
        stepper.heightAnchor.constraint(equalToConstant: Sizing.controlHeight).isActive = true
        stepper.widthAnchor.constraint(equalToConstant: Sizing.stepperWidth).isActive = true
        return stepper
    }

    private static func applySymbol(_ symbolName: String?, to button: NSButton) {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.image = image.withSymbolConfiguration(configuration)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
    }
}
