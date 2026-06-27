// Owns the two-row control panel UI and its local chrome/layout rules.
// It does not own app state, module loading, or tracker rendering behavior.
import AppKit

final class TrackerCenteredTextFieldCell: NSTextFieldCell {
    var horizontalInset: CGFloat = 6

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let insetRect = rect.insetBy(dx: horizontalInset, dy: 0)
        var baselineRect = super.drawingRect(forBounds: insetRect)
        let textSize = cellSize(forBounds: rect)
        baselineRect.origin.y = rect.origin.y + floor((rect.height - textSize.height) * 0.5)
        baselineRect.size.height = textSize.height
        return baselineRect
    }
}

final class TrackerStepper: NSStepper {
    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawArrowButton(isUpper: true)
        drawArrowButton(isUpper: false)
    }

    private func drawArrowButton(isUpper: Bool) {
        let buttonWidth = min(CGFloat(15), bounds.width - 2)
        let buttonHeight: CGFloat = 11
        let rect = NSRect(
            x: floor((bounds.width - buttonWidth) * 0.5),
            y: isUpper ? bounds.maxY - buttonHeight - 1 : 1,
            width: buttonWidth,
            height: buttonHeight
        )
        let enabledAlpha: CGFloat = isEnabled ? 1 : 0.38
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        TrackerControlPalette.interactiveFieldBackground.withAlphaComponent(enabledAlpha).setFill()
        path.fill()
        TrackerControlPalette.groupSeparator.withAlphaComponent(isEnabled ? 1 : 0.45).setStroke()
        path.lineWidth = 1
        path.stroke()

        TrackerTheme.legacyDark.accent.withAlphaComponent(isEnabled ? 0.68 : 0.30).setFill()
        let centerX = rect.midX
        let centerY = rect.midY
        let arrow = NSBezierPath()
        if isUpper {
            arrow.move(to: NSPoint(x: centerX, y: centerY + 2.5))
            arrow.line(to: NSPoint(x: centerX - 3, y: centerY - 1.5))
            arrow.line(to: NSPoint(x: centerX + 3, y: centerY - 1.5))
        } else {
            arrow.move(to: NSPoint(x: centerX, y: centerY - 2.5))
            arrow.line(to: NSPoint(x: centerX - 3, y: centerY + 1.5))
            arrow.line(to: NSPoint(x: centerX + 3, y: centerY + 1.5))
        }
        arrow.close()
        arrow.fill()
    }
}

final class ControlPanelView: NSView {
    private typealias Layout = TrackerThemeMetrics.ControlPanelLayout
    private typealias Sizing = TrackerThemeMetrics.ControlPanelSizing

    let playButton = ControlPanelView.makeButton(title: "PLAY", symbolName: "play.fill")
    let stopButton = ControlPanelView.makeButton(title: "STOP", symbolName: "stop.fill")
    let loopButton = ControlPanelView.makeToggleButton(title: "LOOP", symbolName: "repeat")
    let editModeButton = ControlPanelView.makeToggleButton(title: "EDIT", symbolName: "record.circle")
    let topAccentLine = NSView()
    let bottomEdgeLine = NSView()
    private(set) var groupSeparatorViews = [NSView]()
    let songTitleField = ControlPanelView.makeReadoutField(width: nil, minimumWidth: Sizing.songTitleMinimumWidth, alignment: .center)
    let songTimeField = ControlPanelView.makeReadoutField(width: Sizing.songTimeWidth, alignment: .center)
    let songLengthField = ControlPanelView.makeReadoutField(width: Sizing.songLengthWidth, alignment: .center)
    let songPositionField = ControlPanelView.makeReadoutField(width: Sizing.songPositionWidth, alignment: .center, role: .interactive)
    let songPositionStepper = ControlPanelView.makeStepper()
    let restartPositionField = ControlPanelView.makeReadoutField(width: Sizing.restartPositionWidth, alignment: .center)
    let patternSelector = ControlPanelView.makePopupButton(width: Sizing.patternSelectorWidth)
    let patternRowCountField = ControlPanelView.makeReadoutField(width: Sizing.rowCountWidth, alignment: .center)
    let instrumentSelector = ControlPanelView.makePopupButton(minimumWidth: Sizing.instrumentSelectorMinimumWidth)
    let sampleSelector = ControlPanelView.makePopupButton(minimumWidth: Sizing.sampleSelectorMinimumWidth)
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
        layer?.borderWidth = 0

        buildHierarchy()
        configureDefaults()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ content: ControlPanelContent) {
        songTitleField.stringValue = content.songTitle
        songTimeField.stringValue = content.songTime
        songLengthField.stringValue = content.songLength
        songPositionField.stringValue = content.songPosition
        restartPositionField.stringValue = content.restartPosition
        patternRowCountField.stringValue = content.patternRowCount
        channelCountField.stringValue = content.channelCount
        selectOrReplaceSinglePopupItem(
            instrumentSelector,
            title: content.selectedInstrumentDisplay,
            tooltip: content.selectedInstrumentTooltip
        )
        selectOrReplaceSinglePopupItem(
            sampleSelector,
            title: content.selectedSampleDisplay,
            tooltip: content.selectedSampleTooltip
        )
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
        applyTransportStyles(content)
    }

    private func selectOrReplaceSinglePopupItem(_ popup: NSPopUpButton, title: String, tooltip: String) {
        popup.toolTip = tooltip
        if let item = popup.item(withTitle: title) {
            item.toolTip = tooltip
            popup.selectItem(withTitle: title)
            return
        }

        if let slot = Self.controlSlot(from: title),
           let itemIndex = popup.itemArray.firstIndex(where: { $0.representedObject as? Int == slot }) {
            let item = popup.itemArray[itemIndex]
            item.title = title
            item.toolTip = tooltip
            popup.selectItem(at: itemIndex)
            return
        }

        guard popup.numberOfItems <= 1 else {
            return
        }

        popup.removeAllItems()
        popup.addItem(withTitle: title)
        popup.lastItem?.toolTip = tooltip
        popup.selectItem(at: 0)
    }

    private static func controlSlot(from title: String) -> Int? {
        guard title.count >= 3 else {
            return nil
        }
        let code = title.prefix(3)
        guard code.first == "I" || code.first == "S" else {
            return nil
        }
        return Int(code.dropFirst(), radix: 16)
    }

    private func buildHierarchy() {
        configureTopAccentLine()
        configureBottomEdgeLine()
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
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: Sizing.accentLineHeight + Layout.contentInsets.top),
            rootStack.heightAnchor.constraint(equalToConstant: (Layout.rowHeight * 2) + Layout.interRowSpacing)
        ])

        let topRow = makeTopRow()
        let bottomRow = makeBottomRow()
        rootStack.addArrangedSubview(topRow)
        rootStack.addArrangedSubview(bottomRow)
        NSLayoutConstraint.activate([
            topRow.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            bottomRow.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor)
        ])
    }

    private func configureTopAccentLine() {
        topAccentLine.translatesAutoresizingMaskIntoConstraints = false
        topAccentLine.wantsLayer = true
        topAccentLine.layer?.backgroundColor = TrackerControlPalette.panelTopAccent.cgColor
        addSubview(topAccentLine)
        NSLayoutConstraint.activate([
            topAccentLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topAccentLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topAccentLine.topAnchor.constraint(equalTo: topAnchor),
            topAccentLine.heightAnchor.constraint(equalToConstant: Sizing.accentLineHeight)
        ])
    }

    private func configureBottomEdgeLine() {
        bottomEdgeLine.translatesAutoresizingMaskIntoConstraints = false
        bottomEdgeLine.wantsLayer = true
        bottomEdgeLine.layer?.backgroundColor = TrackerControlPalette.panelBottomEdge.cgColor
        addSubview(bottomEdgeLine)
        NSLayoutConstraint.activate([
            bottomEdgeLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomEdgeLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomEdgeLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomEdgeLine.heightAnchor.constraint(equalToConstant: Sizing.panelEdgeLineHeight)
        ])
    }

    private func configureDefaults() {
        octaveSelector.addItems(withTitles: (0...8).map(String.init))
        octaveSelector.selectItem(withTitle: "4")
        patternSelector.addItem(withTitle: ControlPanelDisplayState.patternDisplayTitle(patternIndex: 0))
        instrumentSelector.addItem(withTitle: "No Inst")
        sampleSelector.addItem(withTitle: "No Sample")
        tempoField.stringValue = "125"
        speedField.stringValue = "06"
        songTitleField.stringValue = BlankTrackerDocument.defaultTitle
        songTimeField.stringValue = "--:--"
        songLengthField.stringValue = "01"
        songPositionField.stringValue = "00"
        restartPositionField.stringValue = "00"
        patternRowCountField.stringValue = "64"
        channelCountField.stringValue = "8"
        playButton.toolTip = "Play"
        stopButton.toolTip = "Stop playback"
        loopButton.toolTip = "Loop current pattern on next Play"
        editModeButton.toolTip = "Toggle edit mode"
        songTitleField.toolTip = "Module title"
        songTimeField.toolTip = "Song time"
        songLengthField.toolTip = "Song length in orders"
        songPositionField.toolTip = "Current song position"
        songPositionStepper.toolTip = "Change song position"
        restartPositionField.toolTip = "Restart order"
        patternSelector.toolTip = "Current pattern"
        patternRowCountField.toolTip = "Rows in current pattern"
        instrumentSelector.toolTip = "Current instrument"
        sampleSelector.toolTip = "Current sample"
        tempoField.toolTip = "Initial BPM"
        speedField.toolTip = "Initial ticks per row"
        octaveSelector.toolTip = "Selected editor octave"
        channelCountField.toolTip = "Tracker channels"
        applyTransportStyles(ControlPanelContent())
    }

    private func makeTopRow() -> NSView {
        let transportButtons = NSStackView(views: [playButton, stopButton, loopButton, editModeButton])
        transportButtons.translatesAutoresizingMaskIntoConstraints = false
        transportButtons.orientation = .horizontal
        transportButtons.alignment = .centerY
        transportButtons.spacing = Layout.controlStackSpacing
        lockHorizontalSize(transportButtons)

        let songMetaControls = NSStackView(views: [
            makeInlineGroup(label: "LEN", content: songLengthField),
            makeInlineGroup(label: "POS", content: makeStepperFieldPair(field: songPositionField, stepper: songPositionStepper)),
            makeInlineGroup(label: "RST", content: restartPositionField)
        ])
        songMetaControls.translatesAutoresizingMaskIntoConstraints = false
        songMetaControls.orientation = .horizontal
        songMetaControls.alignment = .centerY
        songMetaControls.spacing = Layout.controlStackSpacing
        lockHorizontalSize(songMetaControls)

        let titleGroup = makeInlineGroup(label: "TITLE", content: songTitleField)
        titleGroup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        songTitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        songTitleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let songGroup = NSStackView(views: [
            titleGroup,
            makeInlineGroup(label: "TIME", content: songTimeField)
        ])
        songGroup.translatesAutoresizingMaskIntoConstraints = false
        songGroup.orientation = .horizontal
        songGroup.alignment = .centerY
        songGroup.distribution = .fill
        songGroup.spacing = Layout.controlStackSpacing
        songGroup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        songGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let separatorAfterTransport = makeGroupSeparator()
        let separatorBeforeMeta = makeGroupSeparator()
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        [transportButtons, separatorAfterTransport, songGroup, separatorBeforeMeta, songMetaControls].forEach(row.addSubview)
        row.heightAnchor.constraint(equalToConstant: Layout.rowHeight).isActive = true
        NSLayoutConstraint.activate([
            transportButtons.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            transportButtons.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            separatorAfterTransport.leadingAnchor.constraint(equalTo: transportButtons.trailingAnchor),
            separatorAfterTransport.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            songGroup.leadingAnchor.constraint(equalTo: separatorAfterTransport.trailingAnchor),
            songGroup.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            separatorBeforeMeta.leadingAnchor.constraint(equalTo: songGroup.trailingAnchor),
            separatorBeforeMeta.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            songMetaControls.leadingAnchor.constraint(equalTo: separatorBeforeMeta.trailingAnchor),
            songMetaControls.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            songMetaControls.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeBottomRow() -> NSView {
        songTitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        songTitleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let patternControls = NSStackView(views: [
            makeInlineGroup(label: "PTN", content: patternSelector),
            makeInlineGroup(label: "ROWS", content: patternRowCountField)
        ])
        patternControls.translatesAutoresizingMaskIntoConstraints = false
        patternControls.orientation = .horizontal
        patternControls.alignment = .centerY
        patternControls.spacing = Layout.controlStackSpacing
        lockHorizontalSize(patternControls)

        let sourceControls = makeSourceControls()
        sourceControls.translatesAutoresizingMaskIntoConstraints = false
        sourceControls.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sourceControls.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        instrumentSelector.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sampleSelector.setContentHuggingPriority(.defaultLow, for: .horizontal)
        instrumentSelector.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sampleSelector.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let timingControls = NSStackView(views: [
            makeInlineGroup(label: "TEMPO", content: tempoField),
            makeInlineGroup(label: "SPEED", content: speedField)
        ])
        timingControls.translatesAutoresizingMaskIntoConstraints = false
        timingControls.orientation = .horizontal
        timingControls.alignment = .centerY
        timingControls.spacing = Layout.controlStackSpacing
        lockHorizontalSize(timingControls)

        let editControls = NSStackView(views: [
            makeInlineGroup(label: "OCT", content: octaveSelector),
            makeInlineGroup(label: "CHN", content: channelCountField)
        ])
        editControls.translatesAutoresizingMaskIntoConstraints = false
        editControls.orientation = .horizontal
        editControls.alignment = .centerY
        editControls.spacing = Layout.controlStackSpacing
        lockHorizontalSize(editControls)

        let separatorAfterPattern = makeGroupSeparator()
        let timingSeparator = makeGroupSeparator(isTiming: true)
        let separatorBeforeEdit = makeGroupSeparator()
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        [
            patternControls,
            separatorAfterPattern,
            sourceControls,
            timingSeparator,
            timingControls,
            separatorBeforeEdit,
            editControls
        ].forEach(row.addSubview)
        row.heightAnchor.constraint(equalToConstant: Layout.rowHeight).isActive = true
        NSLayoutConstraint.activate([
            patternControls.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            patternControls.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            separatorAfterPattern.leadingAnchor.constraint(equalTo: patternControls.trailingAnchor),
            separatorAfterPattern.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            sourceControls.leadingAnchor.constraint(equalTo: separatorAfterPattern.trailingAnchor),
            sourceControls.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            timingSeparator.leadingAnchor.constraint(equalTo: sourceControls.trailingAnchor),
            timingSeparator.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            timingControls.leadingAnchor.constraint(equalTo: timingSeparator.trailingAnchor),
            timingControls.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            separatorBeforeEdit.leadingAnchor.constraint(equalTo: timingControls.trailingAnchor),
            separatorBeforeEdit.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            editControls.leadingAnchor.constraint(equalTo: separatorBeforeEdit.trailingAnchor),
            editControls.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            editControls.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeSourceControls() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: Layout.rowHeight).isActive = true
        let instrumentLabel = TrackerThemeStyling.makeControlLabel(title: "INST", theme: theme)
        let sampleLabel = TrackerThemeStyling.makeControlLabel(title: "SMP", theme: theme)
        [instrumentLabel, instrumentSelector, sampleLabel, sampleSelector].forEach(container.addSubview)

        NSLayoutConstraint.activate([
            instrumentLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            instrumentLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            instrumentSelector.leadingAnchor.constraint(equalTo: instrumentLabel.trailingAnchor, constant: Layout.labelSpacing),
            instrumentSelector.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            sampleLabel.leadingAnchor.constraint(equalTo: instrumentSelector.trailingAnchor, constant: Layout.controlStackSpacing),
            sampleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            sampleSelector.leadingAnchor.constraint(equalTo: sampleLabel.trailingAnchor, constant: Layout.labelSpacing),
            sampleSelector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sampleSelector.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            instrumentSelector.widthAnchor.constraint(equalTo: sampleSelector.widthAnchor)
        ])
        return container
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

    private func lockHorizontalSize(_ view: NSView) {
        let fittingWidth = ceil(view.fittingSize.width)
        if fittingWidth > 0 {
            view.widthAnchor.constraint(equalToConstant: fittingWidth).isActive = true
        }
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
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

    private func makeGroupSeparator(isTiming: Bool = false) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: isTiming ? Sizing.timingGroupSeparatorFootprint : Sizing.groupSeparatorFootprint).isActive = true
        container.heightAnchor.constraint(equalToConstant: Layout.rowHeight).isActive = true
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = (isTiming ? TrackerControlPalette.timingGroupSeparator : TrackerControlPalette.groupSeparator).cgColor
        container.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            separator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: Sizing.groupSeparatorWidth),
            separator.heightAnchor.constraint(equalToConstant: isTiming ? Sizing.timingGroupSeparatorHeight : Sizing.groupSeparatorHeight)
        ])
        groupSeparatorViews.append(separator)
        return container
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
        button.widthAnchor.constraint(equalToConstant: Sizing.primaryButtonMinimumWidth).isActive = true
        return button
    }

    private static func makeToggleButton(title: String, symbolName: String? = nil, compact: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        TrackerThemeStyling.applyButtonChrome(button, accentColor: TrackerTheme.legacyDark.accent)
        applySymbol(symbolName, to: button)
        button.widthAnchor.constraint(equalToConstant: compact ? Sizing.compactToggleButtonMinimumWidth : Sizing.toggleButtonMinimumWidth).isActive = true
        return button
    }

    private static func makePopupButton(width: CGFloat? = nil, minimumWidth: CGFloat? = nil) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        TrackerThemeStyling.applyPopupChrome(button, width: width, minimumWidth: minimumWidth, theme: .legacyDark)
        return button
    }

    private static func makeReadoutField(
        width: CGFloat?,
        minimumWidth: CGFloat? = nil,
        alignment: NSTextAlignment,
        role: TrackerControlFieldRole = .readout
    ) -> NSTextField {
        let field = NSTextField(string: "")
        field.cell = TrackerCenteredTextFieldCell(textCell: "")
        TrackerThemeStyling.applyReadoutChrome(
            field,
            width: width,
            minimumWidth: minimumWidth,
            alignment: alignment,
            theme: .legacyDark,
            role: role
        )
        return field
    }

    private static func makeStepper() -> NSStepper {
        let stepper = TrackerStepper()
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

    private func applyTransportStyles(_ content: ControlPanelContent) {
        TrackerThemeStyling.applyTransportButtonStyle(
            playButton,
            style: content.isPlaybackActive ? .playActive : .playIdle
        )
        TrackerThemeStyling.applyTransportButtonStyle(
            stopButton,
            style: content.isPlaybackActive ? .stopActive : .stopInactive
        )
        TrackerThemeStyling.applyTransportButtonStyle(
            loopButton,
            style: content.isLoopEnabled ? .toggleActive : .toggleInactive
        )
        TrackerThemeStyling.applyTransportButtonStyle(
            editModeButton,
            style: content.isEditModeEnabled ? .toggleActive : .toggleInactive
        )
    }
}
