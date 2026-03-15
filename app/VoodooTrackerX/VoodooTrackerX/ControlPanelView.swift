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
    var currentPosition = "--"
    var restartPosition = "--"
    var patternLength = "--"
    var channelCount = "--"
    var tempo = "125"
    var speed = "06"
    var selectedOctave = 4
    var currentSongPosition = 0
    var maxSongPosition = 0
    var isLoopEnabled = false
    var isEditModeEnabled = false
    var isPlaybackActive = false
    var isSongPositionEnabled = false
    var isPatternControlsEnabled = false
    var instrumentPlaceholder = "No Inst"
    var samplePlaceholder = "No Sample"
    var areInstrumentPlaceholdersEnabled = false
}

final class ControlPanelView: NSView {
    let playButton = ControlPanelView.makeButton(title: "PLAY", symbolName: "play.fill")
    let stopButton = ControlPanelView.makeButton(title: "STOP", symbolName: "stop.fill")
    let loopButton = ControlPanelView.makeToggleButton(title: "LOOP", symbolName: "repeat")
    let editModeButton = ControlPanelView.makeToggleButton(title: "EDIT", symbolName: "record.circle")
    let songTitleField = ControlPanelView.makeReadoutField(width: nil, minimumWidth: 340, alignment: .center)
    let songLengthField = ControlPanelView.makeReadoutField(width: 50, alignment: .center)
    let currentPositionField = ControlPanelView.makeReadoutField(width: 40, alignment: .center)
    let currentPositionStepper = ControlPanelView.makeStepper()
    let restartPositionField = ControlPanelView.makeReadoutField(width: 50, alignment: .center)
    let patternSelector = ControlPanelView.makePopupButton(width: 88)
    let patternLengthField = ControlPanelView.makeReadoutField(width: 58, alignment: .center)
    let instrumentSelector = ControlPanelView.makePopupButton(width: 118)
    let sampleSelector = ControlPanelView.makePopupButton(width: 122)
    let tempoField = ControlPanelView.makeReadoutField(width: 48, alignment: .center)
    let speedField = ControlPanelView.makeReadoutField(width: 48, alignment: .center)
    let octaveSelector = ControlPanelView.makePopupButton(width: 68)
    let channelsField = ControlPanelView.makeReadoutField(width: 46, alignment: .center)

    private let theme: TrackerTheme

    init(frame frameRect: NSRect, theme: TrackerTheme = .legacyDark) {
        self.theme = theme
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = TrackerChromePalette.controlPanelBackground.cgColor
        layer?.borderWidth = TrackerThemeMetrics.controlBorderWidth
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
        currentPositionField.stringValue = content.currentPosition
        restartPositionField.stringValue = content.restartPosition
        patternLengthField.stringValue = content.patternLength
        channelsField.stringValue = content.channelCount
        tempoField.stringValue = content.tempo
        speedField.stringValue = content.speed
        octaveSelector.selectItem(withTitle: String(content.selectedOctave))
        loopButton.state = content.isLoopEnabled ? .on : .off
        editModeButton.state = content.isEditModeEnabled ? .on : .off
        playButton.isEnabled = !content.isPlaybackActive
        stopButton.isEnabled = content.isPlaybackActive
        currentPositionStepper.integerValue = content.currentSongPosition
        currentPositionStepper.maxValue = Double(content.maxSongPosition)
        currentPositionStepper.isEnabled = content.isSongPositionEnabled
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
        rootStack.spacing = TrackerThemeMetrics.interRowSpacing
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TrackerThemeMetrics.contentInsets.left),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TrackerThemeMetrics.contentInsets.right),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: TrackerThemeMetrics.contentInsets.top),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -TrackerThemeMetrics.contentInsets.bottom)
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
        currentPositionField.stringValue = "--"
        restartPositionField.stringValue = "--"
        patternLengthField.stringValue = "--"
        channelsField.stringValue = "--"
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
        transportButtons.spacing = TrackerThemeMetrics.controlStackSpacing

        let songMetaControls = NSStackView(views: [
            makeInlineGroup(label: "LEN", content: songLengthField),
            makeInlineGroup(label: "POS", content: makeStepperFieldPair(field: currentPositionField, stepper: currentPositionStepper)),
            makeInlineGroup(label: "RST", content: restartPositionField)
        ])
        songMetaControls.translatesAutoresizingMaskIntoConstraints = false
        songMetaControls.orientation = .horizontal
        songMetaControls.alignment = .centerY
        songMetaControls.spacing = TrackerThemeMetrics.controlStackSpacing

        let titleGroup = makeInlineGroup(label: "TITLE", content: songTitleField)
        titleGroup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            transportButtons,
            makeFixedSpacer(width: TrackerThemeMetrics.titleLeadSpacing),
            titleGroup,
            makeFixedSpacer(width: TrackerThemeMetrics.titleTrailSpacing),
            songMetaControls,
            makeFlexibleSpacer()
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = TrackerThemeMetrics.interGroupSpacing
        return row
    }

    private func makeBottomRow() -> NSStackView {
        songTitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        songTitleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let patternControls = NSStackView(views: [
            makeInlineGroup(label: "PATTERN", content: patternSelector),
            makeInlineGroup(label: "ROWS", content: patternLengthField)
        ])
        patternControls.translatesAutoresizingMaskIntoConstraints = false
        patternControls.orientation = .horizontal
        patternControls.alignment = .centerY
        patternControls.spacing = TrackerThemeMetrics.controlStackSpacing

        let sourceControls = NSStackView(views: [
            makeInlineGroup(label: "INST", content: instrumentSelector),
            makeInlineGroup(label: "SMP", content: sampleSelector)
        ])
        sourceControls.translatesAutoresizingMaskIntoConstraints = false
        sourceControls.orientation = .horizontal
        sourceControls.alignment = .centerY
        sourceControls.spacing = TrackerThemeMetrics.controlStackSpacing

        let editControls = NSStackView(views: [
            makeInlineGroup(label: "TEMPO", content: tempoField),
            makeInlineGroup(label: "SPEED", content: speedField),
            makeInlineGroup(label: "OCT", content: octaveSelector),
            makeInlineGroup(label: "CHN", content: channelsField)
        ])
        editControls.translatesAutoresizingMaskIntoConstraints = false
        editControls.orientation = .horizontal
        editControls.alignment = .centerY
        editControls.spacing = TrackerThemeMetrics.controlStackSpacing

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
        row.spacing = TrackerThemeMetrics.interGroupSpacing
        return row
    }

    private func makeInlineGroup(label title: String, content: NSView) -> NSStackView {
        let label = TrackerThemeStyling.makeControlLabel(title: title, theme: theme)
        let stack = NSStackView(views: [label, content])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = TrackerThemeMetrics.labelSpacing
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
        pair.spacing = TrackerThemeMetrics.stepperSpacing
        return pair
    }

    private static func makeButton(title: String, symbolName: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.momentaryPushIn)
        TrackerThemeStyling.applyButtonChrome(button, accentColor: TrackerTheme.legacyDark.text)
        applySymbol(symbolName, to: button)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        return button
    }

    private static func makeToggleButton(title: String, symbolName: String? = nil, compact: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        TrackerThemeStyling.applyButtonChrome(button, accentColor: TrackerTheme.legacyDark.accent)
        applySymbol(symbolName, to: button)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: compact ? 42 : 56).isActive = true
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
        stepper.heightAnchor.constraint(equalToConstant: TrackerThemeMetrics.controlHeight).isActive = true
        stepper.widthAnchor.constraint(equalToConstant: 20).isActive = true
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
