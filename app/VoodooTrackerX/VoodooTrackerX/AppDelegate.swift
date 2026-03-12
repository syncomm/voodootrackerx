import AppKit
import UniformTypeIdentifiers

private enum PatternGridPreferences {
    static let beatAccentIntervalKey = "PatternGridBeatAccentInterval"
    static let defaultBeatAccentInterval = 4

    static var beatAccentInterval: Int {
        let stored = UserDefaults.standard.integer(forKey: beatAccentIntervalKey)
        return stored > 0 ? stored : defaultBeatAccentInterval
    }
}

private struct TrackerTheme {
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

private enum TrackerChromePalette {
    static let windowBackground = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1.0)
    static let controlPanelBackground = NSColor(srgbRed: 0x25 / 255.0, green: 0x25 / 255.0, blue: 0x26 / 255.0, alpha: 1.0)
    static let recessedFieldBackground = NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1.0)
    static let subtleBorder = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.22)
    static let separatorLine = NSColor(srgbRed: 0xC9 / 255.0, green: 0xA7 / 255.0, blue: 0x4A / 255.0, alpha: 0.38)
}

private final class TrackerCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let baselineRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let delta = max(0, floor((rect.height - textSize.height) * 0.5) - 1)
        return baselineRect.offsetBy(dx: 0, dy: delta)
    }
}

private struct TrackerControlPanelContent: Equatable {
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

private final class TrackerControlPanelView: NSView {
    let playButton = TrackerControlPanelView.makeButton(title: "PLAY", symbolName: "play.fill")
    let stopButton = TrackerControlPanelView.makeButton(title: "STOP", symbolName: "stop.fill")
    let loopButton = TrackerControlPanelView.makeToggleButton(title: "LOOP", symbolName: "repeat")
    let editModeButton = TrackerControlPanelView.makeToggleButton(title: "EDIT", symbolName: "record.circle")
    let songTitleField = TrackerControlPanelView.makeReadoutField(width: nil, minimumWidth: 340, alignment: .center)
    let songLengthField = TrackerControlPanelView.makeReadoutField(width: 50, alignment: .center)
    let currentPositionField = TrackerControlPanelView.makeReadoutField(width: 40, alignment: .center)
    let currentPositionStepper = TrackerControlPanelView.makeStepper()
    let restartPositionField = TrackerControlPanelView.makeReadoutField(width: 50, alignment: .center)
    let patternSelector = TrackerControlPanelView.makePopupButton(width: 88)
    let patternLengthField = TrackerControlPanelView.makeReadoutField(width: 58, alignment: .center)
    let instrumentSelector = TrackerControlPanelView.makePopupButton(width: 118)
    let sampleSelector = TrackerControlPanelView.makePopupButton(width: 122)
    let tempoField = TrackerControlPanelView.makeReadoutField(width: 48, alignment: .center)
    let speedField = TrackerControlPanelView.makeReadoutField(width: 48, alignment: .center)
    let octaveSelector = TrackerControlPanelView.makePopupButton(width: 68)
    let channelsField = TrackerControlPanelView.makeReadoutField(width: 46, alignment: .center)

    private let contentInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    private let interRowSpacing: CGFloat = 10
    private let interGroupSpacing: CGFloat = 14
    private let controlStackSpacing: CGFloat = 8
    private let titleLeadSpacing: CGFloat = 18
    private let titleTrailSpacing: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = TrackerChromePalette.controlPanelBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = TrackerChromePalette.subtleBorder.cgColor

        buildHierarchy()
        configureDefaults()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ content: TrackerControlPanelContent) {
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
        rootStack.spacing = interRowSpacing
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom)
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
        transportButtons.spacing = controlStackSpacing

        let songMetaControls = NSStackView(views: [
            makeInlineGroup(label: "LEN", content: songLengthField),
            makeInlineGroup(label: "POS", content: makeStepperFieldPair(field: currentPositionField, stepper: currentPositionStepper)),
            makeInlineGroup(label: "RST", content: restartPositionField)
        ])
        songMetaControls.translatesAutoresizingMaskIntoConstraints = false
        songMetaControls.orientation = .horizontal
        songMetaControls.alignment = .centerY
        songMetaControls.spacing = controlStackSpacing

        let titleGroup = makeInlineGroup(label: "TITLE", content: songTitleField)
        titleGroup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleGroup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            transportButtons,
            makeFixedSpacer(width: titleLeadSpacing),
            titleGroup,
            makeFixedSpacer(width: titleTrailSpacing),
            songMetaControls,
            makeFlexibleSpacer()
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = interGroupSpacing
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
        patternControls.spacing = controlStackSpacing

        let sourceControls = NSStackView(views: [
            makeInlineGroup(label: "INST", content: instrumentSelector),
            makeInlineGroup(label: "SMP", content: sampleSelector)
        ])
        sourceControls.translatesAutoresizingMaskIntoConstraints = false
        sourceControls.orientation = .horizontal
        sourceControls.alignment = .centerY
        sourceControls.spacing = controlStackSpacing

        let editControls = NSStackView(views: [
            makeInlineGroup(label: "TEMPO", content: tempoField),
            makeInlineGroup(label: "SPEED", content: speedField),
            makeInlineGroup(label: "OCT", content: octaveSelector),
            makeInlineGroup(label: "CHN", content: channelsField)
        ])
        editControls.translatesAutoresizingMaskIntoConstraints = false
        editControls.orientation = .horizontal
        editControls.alignment = .centerY
        editControls.spacing = controlStackSpacing

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
        row.spacing = interGroupSpacing
        return row
    }

    private func makeInlineGroup(label title: String, content: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = TrackerTheme.legacyDark.accent
        label.alignment = .left
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [label, content])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 7
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
        pair.spacing = 4
        return pair
    }

    private static func makeButton(title: String, symbolName: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .shadowlessSquare
        button.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = TrackerTheme.legacyDark.text
        button.appearance = NSAppearance(named: .darkAqua)
        button.bezelColor = TrackerChromePalette.recessedFieldBackground
        applySymbol(symbolName, to: button)
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        return button
    }

    private static func makeToggleButton(title: String, symbolName: String? = nil, compact: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .shadowlessSquare
        button.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = TrackerTheme.legacyDark.accent
        button.appearance = NSAppearance(named: .darkAqua)
        button.bezelColor = TrackerChromePalette.recessedFieldBackground
        applySymbol(symbolName, to: button)
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: compact ? 42 : 56).isActive = true
        return button
    }

    private static func makePopupButton(width: CGFloat) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.appearance = NSAppearance(named: .darkAqua)
        button.contentTintColor = TrackerTheme.legacyDark.text
        button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        button.bezelColor = TrackerChromePalette.recessedFieldBackground
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        return button
    }

    private static func makeReadoutField(width: CGFloat?, minimumWidth: CGFloat? = nil, alignment: NSTextAlignment) -> NSTextField {
        let field = NSTextField(string: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.cell = TrackerCenteredTextFieldCell(textCell: "")
        field.isEditable = false
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        field.textColor = TrackerTheme.legacyDark.text
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.wantsLayer = true
        field.layer?.backgroundColor = TrackerChromePalette.recessedFieldBackground.cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = TrackerChromePalette.subtleBorder.cgColor
        field.layer?.cornerRadius = 0
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        if let minimumWidth {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
        }
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth ?? 220).isActive = true
        }
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
        stepper.heightAnchor.constraint(equalToConstant: 28).isActive = true
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

private enum TrackerPinnedGutterGeometry {
    static let dividerClearance: CGFloat = PatternCursorOutlineGeometry.outwardPadding + 2
    static let rowNumberPadding: CGFloat = 2

    static func visibleWidth(for dividerX: CGFloat, rowNumberWidth: CGFloat) -> CGFloat {
        let maxWidthBeforeDivider = max(0, floor(dividerX - dividerClearance))
        let preferredWidth = ceil(rowNumberWidth) + rowNumberPadding
        return min(maxWidthBeforeDivider, preferredWidth)
    }
}

enum TrackerInteractionMode: Equatable {
    case navigation
    case playOnly
    case edit
}

struct PatternCursorOutlineGeometry {
    static let strokeWidth: CGFloat = 2
    static let outwardPadding: CGFloat = 2
    static let scrollMargin = NSSize(width: 10, height: 4)

    static func strokeRect(for fieldRect: NSRect) -> NSRect {
        fieldRect.insetBy(dx: -outwardPadding, dy: -outwardPadding)
    }

    static func minimumVisibleBounds(for bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.minX,
            y: bounds.minY + outwardPadding,
            width: max(0, bounds.width - outwardPadding),
            height: max(0, bounds.height - (outwardPadding * 2))
        )
    }
}

struct PatternViewportMetrics: Equatable {
    static let trailingContentPadding: CGFloat = 12

    let rowHeight: CGFloat
    let viewportHeight: CGFloat

    var visibleRowCount: Int {
        guard rowHeight > 0 else { return 1 }
        let rows = max(1, Int(ceil(viewportHeight / rowHeight)) + 2)
        if rows % 2 == 0 {
            return rows + 1
        }
        return rows
    }

    var anchorRowIndex: Int {
        visibleRowCount / 2
    }

    func contentHeight(forRenderedRowCount renderedRowCount: Int, insetHeight: CGFloat) -> CGFloat {
        let renderedHeight = CGFloat(max(0, renderedRowCount)) * rowHeight
        return renderedHeight + insetHeight * 2 + 2
    }
}

private enum TrackerViewportScrollGeometry {
    static func clampedHorizontalOrigin(
        preferredOriginX: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let maxOriginX = max(0, contentWidth - viewportWidth)
        return min(max(0, preferredOriginX), maxOriginX)
    }
}

private enum TrackerViewportResizeBehavior {
    static func shouldCaptureStableHorizontalOrigin(isLiveResize: Bool) -> Bool {
        !isLiveResize
    }

    static func shouldRevealCursorHorizontally(isViewportResizeRerender: Bool) -> Bool {
        !isViewportResizeRerender
    }
}

struct PatternViewportState: Equatable {
    let currentRow: Int
    let anchorRowIndex: Int
    let visibleTopRow: Int
    let visibleBottomRow: Int
    let rowHeight: CGFloat
    let visibleRowCount: Int
    let rowCount: Int

    init(currentRow: Int, rowCount: Int, metrics: PatternViewportMetrics) {
        let safeRowCount = max(0, rowCount)
        let clampedRow = safeRowCount > 0 ? min(max(0, currentRow), safeRowCount - 1) : 0
        let visibleRowCount = max(1, metrics.visibleRowCount)
        let anchorRowIndex = min(metrics.anchorRowIndex, visibleRowCount - 1)
        let visibleTopRow = clampedRow - anchorRowIndex

        self.currentRow = clampedRow
        self.anchorRowIndex = anchorRowIndex
        self.visibleTopRow = visibleTopRow
        self.visibleBottomRow = visibleTopRow + visibleRowCount - 1
        self.rowHeight = metrics.rowHeight
        self.visibleRowCount = visibleRowCount
        self.rowCount = safeRowCount
    }

    func rowIndex(forSlot slotIndex: Int) -> Int? {
        guard (0..<visibleRowCount).contains(slotIndex) else { return nil }
        let rowIndex = visibleTopRow + slotIndex
        guard (0..<rowCount).contains(rowIndex) else { return nil }
        return rowIndex
    }

    var slotRows: [Int?] {
        (0..<visibleRowCount).map(rowIndex(forSlot:))
    }
}

struct PatternViewportTextLayout: Equatable {
    static let rowNumberPrefixLength = 4
    static let leadingChannelPaddingLength = 0

    let renderedText: String
    let slotRows: [Int?]
    let slotFullRanges: [NSRange]
    let slotGridRanges: [NSRange]
    let gridRangesByRow: [Int: NSRange]
    let fullRangesByRow: [Int: NSRange]

    init(
        pattern: XMPatternData,
        state: PatternViewportState
    ) {
        let separator = String(repeating: " ", count: ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let leadingChannelPadding = String(repeating: " ", count: Self.leadingChannelPaddingLength)
        let gridWidth = max(0, pattern.channels) * ModuleMetadataLoader.xmRenderedCellWidth +
            max(0, pattern.channels - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth
        let gridBlank = String(repeating: " ", count: gridWidth)

        var renderedLines = [String]()
        var slotFullRanges = [NSRange]()
        var slotGridRanges = [NSRange]()
        var gridRangesByRow = [Int: NSRange]()
        var fullRangesByRow = [Int: NSRange]()
        var gridOffset = 0

        for slotIndex in 0..<state.visibleRowCount {
            let rowIndex = state.rowIndex(forSlot: slotIndex)
            let gridLine: String
            let rowPrefix = String(repeating: " ", count: Self.rowNumberPrefixLength)

            if let rowIndex {
                gridLine = pattern.rows[rowIndex].map(ModuleMetadataLoader.formatXMCell).joined(separator: separator)
            } else {
                gridLine = gridBlank
            }

            let renderedLine = rowPrefix + leadingChannelPadding + gridLine
            let fullRange = NSRange(location: gridOffset, length: renderedLine.utf16.count)
            slotFullRanges.append(fullRange)
            let gridRange = NSRange(
                location: gridOffset + Self.rowNumberPrefixLength + Self.leadingChannelPaddingLength,
                length: gridLine.utf16.count
            )
            slotGridRanges.append(gridRange)

            if let rowIndex {
                gridRangesByRow[rowIndex] = gridRange
                fullRangesByRow[rowIndex] = fullRange
            }

            renderedLines.append(renderedLine)
            gridOffset += renderedLine.utf16.count + 1
        }

        self.renderedText = renderedLines.joined(separator: "\n")
        self.slotRows = state.slotRows
        self.slotFullRanges = slotFullRanges
        self.slotGridRanges = slotGridRanges
        self.gridRangesByRow = gridRangesByRow
        self.fullRangesByRow = fullRangesByRow
    }
}

private final class TrackerChromeOverlayView: NSView {
    struct RowEntry {
        let rowIndex: Int?
        let rect: NSRect
    }

    weak var headerScrollView: NSScrollView? {
        didSet { needsDisplay = true }
    }
    weak var bodyTextView: PatternTextView? {
        didSet { needsDisplay = true }
    }
    weak var bodyScrollView: NSScrollView? {
        didSet { needsDisplay = true }
    }
    var theme = TrackerTheme.legacyDark {
        didSet { needsDisplay = true }
    }
    var chromeBackgroundColor = NSColor.black {
        didSet { needsDisplay = true }
    }
    var viewportState: PatternViewportState? {
        didSet { needsDisplay = true }
    }
    var currentRow: Int = 0 {
        didSet { needsDisplay = true }
    }
    var gutterWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var dividerX: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var beatInterval: Int = PatternGridPreferences.defaultBeatAccentInterval {
        didSet { needsDisplay = true }
    }
    var rowEntries = [RowEntry]() {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let viewportState,
              let bodyScrollView,
              let headerScrollView,
              gutterWidth > 0 else {
            return
        }

        drawPinnedGutter(in: bodyScrollView.frame, headerFrame: headerScrollView.frame, viewportState: viewportState)
    }

    private func drawPinnedGutter(in bodyFrame: NSRect, headerFrame: NSRect, viewportState: PatternViewportState) {
        let gutterRect = NSRect(x: bodyFrame.minX, y: bodyFrame.minY, width: gutterWidth, height: bodyFrame.height)
        chromeBackgroundColor.setFill()
        gutterRect.fill()

        let headerCornerRect = NSRect(x: headerFrame.minX, y: headerFrame.minY, width: gutterWidth, height: headerFrame.height)
        chromeBackgroundColor.setFill()
        headerCornerRect.fill()

        let boundaryPath = NSBezierPath()
        boundaryPath.lineWidth = 1
        let boundaryX = gutterRect.maxX + 0.5
        boundaryPath.move(to: NSPoint(x: boundaryX, y: bodyFrame.minY))
        boundaryPath.line(to: NSPoint(x: boundaryX, y: headerFrame.maxY))
        theme.separator.setStroke()
        boundaryPath.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: gutterRect).addClip()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: theme.text,
            .paragraphStyle: paragraphStyle
        ]

        for entry in rowEntries where gutterRect.intersects(entry.rect) {
            let rowRect = NSRect(x: gutterRect.minX, y: entry.rect.minY, width: gutterRect.width, height: entry.rect.height)
            let rowIndex = entry.rowIndex
            if let rowIndex, beatInterval > 0, rowIndex % beatInterval == 0 {
                theme.beatAccent.setFill()
                rowRect.fill()
            }
            if rowIndex == currentRow {
                theme.rowHighlight.setFill()
                rowRect.fill()
            }
            guard let rowIndex else { continue }

            let string = NSString(string: String(format: "%02X", rowIndex))
            let textSize = string.size(withAttributes: textAttributes)
            let textRect = NSRect(
                x: rowRect.minX,
                y: rowRect.minY + floor((rowRect.height - textSize.height) * 0.5),
                width: max(0, rowRect.width - 1),
                height: textSize.height
            )
            string.draw(in: textRect, withAttributes: textAttributes)
        }
    }
}

private final class TrackerDividerUnderlayView: NSView {
    weak var headerScrollView: NSScrollView? {
        didSet { needsDisplay = true }
    }
    weak var bodyTextView: PatternTextView? {
        didSet { needsDisplay = true }
    }
    weak var bodyScrollView: NSScrollView? {
        didSet { needsDisplay = true }
    }
    var theme = TrackerTheme.legacyDark {
        didSet { needsDisplay = true }
    }
    var gutterWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var dividerX: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let bodyTextView,
              let bodyScrollView,
              let headerScrollView,
              let layoutManager = bodyTextView.layoutManager else {
            return
        }

        let textLength = (bodyTextView.string as NSString).length
        guard textLength > 0 else { return }

        let headerFrame = headerScrollView.frame
        let bodyFrame = bodyScrollView.frame
        let minimumDividerX = bodyFrame.minX + max(dividerX, gutterWidth) + 0.5

        let visibleBodyX = bodyScrollView.contentView.bounds.origin.x
        let path = NSBezierPath()
        path.lineWidth = 1

        NSGraphicsContext.current?.saveGraphicsState()
        let clipRect = NSRect(
            x: minimumDividerX,
            y: bodyFrame.minY,
            width: max(0, bodyFrame.maxX - minimumDividerX),
            height: headerFrame.maxY - bodyFrame.minY
        )
        NSBezierPath(rect: clipRect).addClip()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        for characterIndex in bodyTextView.dividerCharacterIndices {
            let clampedIndex = min(max(0, characterIndex), textLength - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedIndex)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let x = bodyFrame.minX + bodyTextView.textContainerOrigin.x + location.x - visibleBodyX + 0.5
            guard x >= minimumDividerX else { continue }
            path.move(to: NSPoint(x: x, y: bodyFrame.minY))
            path.line(to: NSPoint(x: x, y: headerFrame.maxY))
        }

        theme.separator.setStroke()
        path.stroke()
    }
}

enum PatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
}

enum PatternEditInput {
    case clearField
    case hexDigit(UInt8)
}

enum PatternEditEngine {
    static func hexNibble(from character: Character) -> UInt8? {
        guard let scalar = String(character).unicodeScalars.first else {
            return nil
        }
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...70:
            return UInt8(scalar.value - 55)
        case 97...102:
            return UInt8(scalar.value - 87)
        default:
            return nil
        }
    }

    static func apply(
        input: PatternEditInput,
        to cell: XMPatternEventCell,
        field: PatternCursorField,
        editModeEnabled: Bool
    ) -> XMPatternEventCell? {
        guard editModeEnabled else {
            return nil
        }

        switch input {
        case .clearField:
            return cleared(cell: cell, field: field)
        case let .hexDigit(nibble):
            guard nibble <= 0x0F else {
                return nil
            }
            return applyingHexNibble(nibble, to: cell, field: field)
        }
    }

    private static func cleared(cell: XMPatternEventCell, field: PatternCursorField) -> XMPatternEventCell {
        switch field {
        case .note:
            return XMPatternEventCell(note: 0, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
        case .instrument:
            return XMPatternEventCell(note: cell.note, instrument: 0, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
        case .volume:
            return XMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: 0, effectType: cell.effectType, effectParam: cell.effectParam)
        case .effectType:
            return XMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: 0, effectParam: cell.effectParam)
        case .effectParam:
            return XMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: 0)
        }
    }

    private static func applyingHexNibble(_ nibble: UInt8, to cell: XMPatternEventCell, field: PatternCursorField) -> XMPatternEventCell? {
        switch field {
        case .note:
            return nil
        case .instrument:
            let value = ((cell.instrument & 0x0F) << 4) | nibble
            return XMPatternEventCell(note: cell.note, instrument: value, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
        case .volume:
            let value = ((cell.volumeColumn & 0x0F) << 4) | nibble
            return XMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: value, effectType: cell.effectType, effectParam: cell.effectParam)
        case .effectType:
            return XMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: nibble, effectParam: cell.effectParam)
        case .effectParam:
            let value = ((cell.effectParam & 0x0F) << 4) | nibble
            return XMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: value)
        }
    }
}

enum PatternCursorField: Int, CaseIterable {
    case note
    case instrument
    case volume
    case effectType
    case effectParam

    var textOffset: Int {
        switch self {
        case .note:
            return 0
        case .instrument:
            return 4
        case .volume:
            return 7
        case .effectType:
            return 10
        case .effectParam:
            return 11
        }
    }

    var textLength: Int {
        switch self {
        case .note:
            return 3
        case .instrument, .volume, .effectParam:
            return 2
        case .effectType:
            return 1
        }
    }
}

struct PatternCursor: Equatable {
    var row: Int
    var channel: Int
    var field: PatternCursorField

    mutating func clamp(rowCount: Int, channelCount: Int) {
        row = min(max(0, row), max(0, rowCount - 1))
        channel = min(max(0, channel), max(0, channelCount - 1))
    }

    mutating func move(_ command: PatternNavigationCommand, rowCount: Int, channelCount: Int, pageStep: Int = 16) {
        clamp(rowCount: rowCount, channelCount: channelCount)
        switch command {
        case .up:
            moveUp(rowCount: rowCount)
        case .down:
            moveDown(rowCount: rowCount)
        case .pageUp:
            row = max(0, row - pageStep)
        case .pageDown:
            row = min(max(0, rowCount - 1), row + pageStep)
        case .home:
            row = 0
        case .end:
            row = max(0, rowCount - 1)
        case .left:
            moveLeft(channelCount: channelCount)
        case .right:
            moveRight(channelCount: channelCount)
        }
    }

    private mutating func moveUp(rowCount: Int) {
        guard rowCount > 0 else {
            row = 0
            return
        }
        row = row == 0 ? rowCount - 1 : row - 1
    }

    private mutating func moveDown(rowCount: Int) {
        guard rowCount > 0 else {
            row = 0
            return
        }
        row = row == rowCount - 1 ? 0 : row + 1
    }

    private mutating func moveLeft(channelCount: Int) {
        if let previousField = PatternCursorField(rawValue: field.rawValue - 1) {
            field = previousField
            return
        }
        guard channelCount > 0, channel > 0 else { return }
        channel -= 1
        field = .effectParam
    }

    private mutating func moveRight(channelCount: Int) {
        if let nextField = PatternCursorField(rawValue: field.rawValue + 1) {
            field = nextField
            return
        }
        guard channelCount > 0, channel < channelCount - 1 else { return }
        channel += 1
        field = .note
    }
}

private final class PatternTextView: NSTextView {
    var navigationHandler: ((PatternNavigationCommand) -> Void)?
    var editInputHandler: ((PatternEditInput) -> Bool)?
    var wheelNavigationHandler: ((CGFloat) -> Void)?
    private var preciseVerticalWheelAccumulator: CGFloat = 0
    var theme = TrackerTheme.legacyDark
    var dividerCharacterIndices = [Int]() {
        didSet {
            needsDisplay = true
        }
    }
    var drawsDividers = true {
        didSet {
            needsDisplay = true
        }
    }
    var dividerTopCharacterIndex: Int? {
        didSet {
            needsDisplay = true
        }
    }
    var activeFieldRange: NSRange? {
        didSet {
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            navigationHandler?(.up)
        case 125:
            navigationHandler?(.down)
        case 116:
            navigationHandler?(.pageUp)
        case 121:
            navigationHandler?(.pageDown)
        case 115:
            navigationHandler?(.home)
        case 119:
            navigationHandler?(.end)
        case 123:
            navigationHandler?(.left)
        case 124:
            navigationHandler?(.right)
        case 51, 117:
            if editInputHandler?(.clearField) == true {
                return
            }
            super.keyDown(with: event)
        default:
            if let characters = event.charactersIgnoringModifiers, let character = characters.first {
                if character == "." {
                    if editInputHandler?(.clearField) == true {
                        return
                    }
                } else if let nibble = PatternEditEngine.hexNibble(from: character),
                          editInputHandler?(.hexDigit(nibble)) == true {
                    return
                }
            }
            super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let wheelNavigationHandler else {
            super.scrollWheel(with: event)
            return
        }

        if event.phase == .ended || event.momentumPhase == .ended || event.momentumPhase == .cancelled {
            preciseVerticalWheelAccumulator = 0
        }

        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        guard abs(deltaY) > 0.01, abs(deltaY) >= abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }

        if event.hasPreciseScrollingDeltas {
            preciseVerticalWheelAccumulator += deltaY
            let stepThreshold: CGFloat = 18

            while preciseVerticalWheelAccumulator <= -stepThreshold {
                wheelNavigationHandler(-stepThreshold)
                preciseVerticalWheelAccumulator += stepThreshold
            }

            while preciseVerticalWheelAccumulator >= stepThreshold {
                wheelNavigationHandler(stepThreshold)
                preciseVerticalWheelAccumulator -= stepThreshold
            }
            return
        }

        wheelNavigationHandler(deltaY)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawChannelDividers()

        guard let activeFieldRange,
              activeFieldRange.location != NSNotFound,
              let layoutManager,
              let textContainer else {
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: activeFieldRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        let strokeRect = PatternCursorOutlineGeometry.strokeRect(for: rect)
        let clipRect = PatternCursorOutlineGeometry.minimumVisibleBounds(for: bounds)
        guard !strokeRect.isNull else { return }
        guard clipRect.intersects(strokeRect) else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }
        NSBezierPath(rect: clipRect).addClip()
        theme.cursorOutline.setStroke()
        let path = NSBezierPath(rect: strokeRect)
        path.lineWidth = PatternCursorOutlineGeometry.strokeWidth
        path.stroke()
    }

    private func drawChannelDividers() {
        guard drawsDividers,
              !dividerCharacterIndices.isEmpty,
              let layoutManager else {
            return
        }

        let textLength = (string as NSString).length
        guard textLength > 0 else { return }

        let visibleRect = self.visibleRect
        var dividerMinY = visibleRect.minY
        if let dividerTopCharacterIndex {
            let clampedTop = min(max(0, dividerTopCharacterIndex), textLength - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedTop)
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            dividerMinY = max(visibleRect.minY, textContainerOrigin.y + lineRect.minY)
        }
        guard dividerMinY < visibleRect.maxY else { return }
        let path = NSBezierPath()
        path.lineWidth = 1

        for characterIndex in dividerCharacterIndices {
            let clampedIndex = min(max(0, characterIndex), textLength - 1)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedIndex)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let x = textContainerOrigin.x + location.x + 0.5
            path.move(to: NSPoint(x: x, y: dividerMinY))
            path.line(to: NSPoint(x: x, y: visibleRect.maxY))
        }

        theme.separator.setStroke()
        path.stroke()
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var retainedDelegate: AppDelegate?
    private var mainWindow: NSWindow?
    private var controlPanelView: TrackerControlPanelView?
    private var metadataTextView: NSTextView?
    private var patternInfoLabel: NSTextField?
    private var patternHeaderTextView: PatternTextView?
    private var patternHeaderScrollView: NSScrollView?
    private var gridScrollView: NSScrollView?
    private var trackerDividerUnderlayView: TrackerDividerUnderlayView?
    private var trackerChromeOverlayView: TrackerChromeOverlayView?
    private var patternSelector: NSPopUpButton?
    private var editModeCheckbox: NSButton?
    private var loadedMetadata: ParsedModuleMetadata?
    private var displayedPatternEntries = [ModuleMetadataLoader.PatternSelectionEntry]()
    private var invalidReferencedPatternIndices = [Int]()
    private var selectedDropdownIndex = 0
    private var currentSongPositionIndex = 0
    private var currentPatternIndex = 0
    private var cursor = PatternCursor(row: 0, channel: 0, field: .note)
    private var visibleGridRangesByRow = [Int: NSRange]()
    private var currentViewportState: PatternViewportState?
    private var currentViewportLayout: PatternViewportTextLayout?
    private let theme = TrackerTheme.legacyDark
    private let metadataLoader = ModuleMetadataLoader()
    private let initialWindowSize = NSSize(width: 1120, height: 900)
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
        if mainWindow == nil {
            createMainWindow()
        }
        showAndActivateMainWindow()
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

    private func createMainWindow() {
        let contentView = NSView(frame: NSRect(origin: .zero, size: initialWindowSize))
        contentView.wantsLayer = true
        let trackerBackground = NSColor.black
        contentView.layer?.backgroundColor = TrackerChromePalette.windowBackground.cgColor

        let rootPadding: CGFloat = 24
        let sectionSpacing: CGFloat = 12
        let logoPanelHeight: CGFloat = 260
        let controlBarHeight: CGFloat = 112
        let trackerHeaderHeight: CGFloat = 24
        let channelHeaderHeight: CGFloat = 24
        let contentWidth = initialWindowSize.width - (rootPadding * 2)

        let logoPanelY = initialWindowSize.height - rootPadding - logoPanelHeight
        let controlBarY = logoPanelY - sectionSpacing - controlBarHeight
        let trackerPanelY = rootPadding
        let trackerPanelHeight = max(220, controlBarY - sectionSpacing - trackerPanelY)

        let headerBar = NSBox(
            frame: NSRect(
                x: rootPadding,
                y: logoPanelY,
                width: contentWidth,
                height: logoPanelHeight
            )
        )
        headerBar.autoresizingMask = [.width, .minYMargin]
        headerBar.boxType = .custom
        headerBar.borderWidth = 0
        headerBar.fillColor = .white
        headerBar.contentViewMargins = .zero
        contentView.addSubview(headerBar)

        if let logoImage = trackerLogoImage() {
            let maxLogoWidth = min(headerBar.bounds.width - 48, 800)
            let logoAspect = logoImage.size.width > 0 ? (logoImage.size.height / logoImage.size.width) : 0.15
            var logoWidth = maxLogoWidth
            var logoHeight = logoWidth * logoAspect
            let maxLogoHeight = headerBar.bounds.height - 24
            if logoHeight > maxLogoHeight, logoAspect > 0 {
                logoHeight = maxLogoHeight
                logoWidth = logoHeight / logoAspect
            }

            let imageView = NSImageView(frame: NSRect(
                x: (headerBar.bounds.width - logoWidth) * 0.5,
                y: (headerBar.bounds.height - logoHeight) * 0.5,
                width: logoWidth,
                height: logoHeight
            ))
            imageView.autoresizingMask = [.minXMargin, .maxXMargin]
            imageView.image = logoImage
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.magnificationFilter = .nearest
            imageView.layer?.minificationFilter = .nearest
            headerBar.addSubview(imageView)
        } else {
            let fallbackTitle = NSTextField(labelWithString: "VoodooTracker X")
            fallbackTitle.frame = headerBar.bounds.insetBy(dx: 8, dy: 4)
            fallbackTitle.autoresizingMask = [.width, .height]
            fallbackTitle.alignment = .center
            fallbackTitle.font = .systemFont(ofSize: 16, weight: .semibold)
            fallbackTitle.textColor = theme.text
            headerBar.addSubview(fallbackTitle)
        }

        let controlBar = TrackerControlPanelView(
            frame: NSRect(
                x: rootPadding,
                y: controlBarY,
                width: contentWidth,
                height: controlBarHeight
            )
        )
        controlBar.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(controlBar)
        controlPanelView = controlBar
        controlBar.playButton.target = self
        controlBar.playButton.action = #selector(playPressed(_:))
        controlBar.stopButton.target = self
        controlBar.stopButton.action = #selector(stopPressed(_:))
        controlBar.loopButton.target = self
        controlBar.loopButton.action = #selector(loopToggled(_:))
        controlBar.editModeButton.target = self
        controlBar.editModeButton.action = #selector(editModeToggled(_:))
        controlBar.patternSelector.target = self
        controlBar.patternSelector.action = #selector(patternSelectionChanged(_:))
        controlBar.currentPositionStepper.target = self
        controlBar.currentPositionStepper.action = #selector(currentSongPositionStepperChanged(_:))
        controlBar.octaveSelector.target = self
        controlBar.octaveSelector.action = #selector(octaveSelectionChanged(_:))
        patternSelector = controlBar.patternSelector
        editModeCheckbox = controlBar.editModeButton

        let trackerPanel = NSBox(
            frame: NSRect(
                x: rootPadding,
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

        let infoLabel = NSTextField(labelWithString: "")
        infoLabel.frame = NSRect(x: 0, y: trackerPanel.bounds.height - 24, width: trackerPanel.bounds.width, height: 20)
        infoLabel.autoresizingMask = [.width, .minYMargin]
        infoLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        infoLabel.textColor = theme.text
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.backgroundColor = .clear
        infoLabel.isHidden = true
        trackerPanel.addSubview(infoLabel)
        patternInfoLabel = infoLabel

        let headerScrollView = NSScrollView(
            frame: NSRect(
                x: 0,
                y: trackerPanel.bounds.height - trackerHeaderHeight,
                width: trackerPanel.bounds.width,
                height: channelHeaderHeight
            )
        )
        headerScrollView.autoresizingMask = [.width, .minYMargin]
        headerScrollView.hasVerticalScroller = false
        headerScrollView.hasHorizontalScroller = false
        headerScrollView.verticalScrollElasticity = .none
        headerScrollView.horizontalScrollElasticity = .none
        headerScrollView.borderType = .noBorder
        headerScrollView.drawsBackground = true
        headerScrollView.backgroundColor = trackerBackground

        let headerTextView = PatternTextView(frame: headerScrollView.bounds)
        headerTextView.autoresizingMask = []
        headerTextView.isEditable = false
        headerTextView.isRichText = false
        headerTextView.isSelectable = false
        headerTextView.isHorizontallyResizable = true
        headerTextView.isVerticallyResizable = false
        headerTextView.minSize = NSSize(width: 0, height: 0)
        headerTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        headerTextView.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        headerTextView.textContainerInset = NSSize(width: 4, height: 2)
        headerTextView.drawsBackground = true
        headerTextView.backgroundColor = trackerBackground
        headerTextView.textColor = theme.accent
        headerTextView.textContainer?.lineFragmentPadding = 0
        headerTextView.textContainer?.widthTracksTextView = false
        headerTextView.textContainer?.heightTracksTextView = true
        headerTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        headerTextView.textContainer?.lineBreakMode = .byClipping
        headerTextView.theme = theme
        headerTextView.drawsDividers = false
        headerScrollView.documentView = headerTextView
        headerScrollView.isHidden = true
        trackerPanel.addSubview(headerScrollView)
        patternHeaderScrollView = headerScrollView
        patternHeaderTextView = headerTextView

        let bodyY: CGFloat = 0
        let bodyHeight = trackerPanel.bounds.height - trackerHeaderHeight - 8

        let scrollView = NSScrollView(
            frame: NSRect(
                x: 0,
                y: bodyY,
                width: trackerPanel.bounds.width,
                height: bodyHeight
            )
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = trackerBackground

        let textView = PatternTextView(frame: scrollView.bounds)
        textView.autoresizingMask = []
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.drawsBackground = true
        textView.backgroundColor = trackerBackground
        textView.textColor = theme.text
        textView.theme = theme
        textView.drawsDividers = false
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byClipping
        textView.navigationHandler = { [weak self] command in
            self?.handlePatternNavigation(command)
        }
        textView.editInputHandler = { [weak self] input in
            self?.handlePatternEditInput(input) ?? false
        }
        textView.wheelNavigationHandler = { [weak self] deltaY in
            self?.handlePatternWheel(deltaY: deltaY)
        }
        let introText = """
        VoodooTracker X

        File > Open… to load a .mod or .xm file and inspect parsed header metadata.
        """
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: introText,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: theme.text
                ]
            )
        )
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gridClipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        let dividerUnderlay = TrackerDividerUnderlayView(frame: trackerPanel.bounds)
        dividerUnderlay.autoresizingMask = [.width, .height]
        dividerUnderlay.theme = theme
        dividerUnderlay.headerScrollView = headerScrollView
        dividerUnderlay.bodyTextView = textView
        dividerUnderlay.bodyScrollView = scrollView
        dividerUnderlay.isHidden = true
        trackerPanel.addSubview(scrollView)
        metadataTextView = textView
        gridScrollView = scrollView
        lastGridViewportSize = scrollView.contentView.bounds.size

        let chromeOverlay = TrackerChromeOverlayView(frame: trackerPanel.bounds)
        chromeOverlay.autoresizingMask = [.width, .height]
        chromeOverlay.theme = theme
        chromeOverlay.chromeBackgroundColor = trackerBackground
        chromeOverlay.headerScrollView = headerScrollView
        chromeOverlay.bodyTextView = textView
        chromeOverlay.bodyScrollView = scrollView
        chromeOverlay.isHidden = true
        trackerPanel.addSubview(chromeOverlay)
        trackerChromeOverlayView = chromeOverlay
        trackerPanel.addSubview(dividerUnderlay, positioned: .below, relativeTo: chromeOverlay)
        trackerDividerUnderlayView = dividerUnderlay

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
        window.delegate = self
        window.center()
        window.contentView = contentView

        self.mainWindow = window
        refreshControlPanel()
    }

    private func trackerLogoImage() -> NSImage? {
        if let svg = Bundle.main.url(forResource: "vtx-logo", withExtension: "svg"),
           let image = NSImage(contentsOf: svg) {
            return image
        }
        if let fallback = Bundle.main.url(forResource: "vtx-logo", withExtension: "png"),
           let image = NSImage(contentsOf: fallback) {
            return image
        }
        return nil
    }

    private func showAndActivateMainWindow() {
        guard let mainWindow else { return }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    @objc
    private func openModuleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.allowedFileTypes = ["mod", "xm"]
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
            selectedDropdownIndex = 0
            currentSongPositionIndex = 0
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
                applySongPosition(currentSongPositionIndex, in: metadata, resetCursor: false)
                renderCurrentPattern(metadata: metadata)
            } else {
                (metadataTextView as? PatternTextView)?.activeFieldRange = nil
                (metadataTextView as? PatternTextView)?.dividerCharacterIndices = []
                (metadataTextView as? PatternTextView)?.dividerTopCharacterIndex = nil
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
            refreshControlPanel()
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
        selectedDropdownIndex = max(0, sender.indexOfSelectedItem)
        guard displayedPatternEntries.indices.contains(selectedDropdownIndex) else {
            return
        }
        currentPatternIndex = displayedPatternEntries[selectedDropdownIndex].patternIndex
        cursor = PatternCursor(row: 0, channel: 0, field: .note)
        renderCurrentPattern(metadata: metadata)
        refreshControlPanel()
    }

    @objc
    private func currentSongPositionStepperChanged(_ sender: NSStepper) {
        guard let metadata = loadedMetadata else {
            return
        }
        applySongPosition(sender.integerValue, in: metadata)
        renderCurrentPattern(metadata: metadata)
        refreshControlPanel()
    }

    @objc
    private func editModeToggled(_ sender: NSButton) {
        isEditModeEnabled = sender.state == .on
        refreshControlPanel()
    }

    @objc
    private func playPressed(_ sender: NSButton) {
        isPlaybackModeActive = true
        refreshControlPanel()
    }

    @objc
    private func stopPressed(_ sender: NSButton) {
        isPlaybackModeActive = false
        refreshControlPanel()
    }

    @objc
    private func loopToggled(_ sender: NSButton) {
        isLoopPlaybackEnabled = sender.state == .on
        refreshControlPanel()
    }

    @objc
    private func octaveSelectionChanged(_ sender: NSPopUpButton) {
        selectedOctave = max(0, sender.indexOfSelectedItem)
        refreshControlPanel()
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
            selectedDropdownIndex = index
        } else {
            selectedDropdownIndex = 0
        }
        currentPatternIndex = displayedPatternEntries[selectedDropdownIndex].patternIndex
        selector.selectItem(at: selectedDropdownIndex)
        selector.isEnabled = true
    }

    private func applySongPosition(_ proposedPosition: Int, in metadata: ParsedModuleMetadata, resetCursor: Bool = true) {
        let clampedPosition = clampedSongPosition(proposedPosition, songLength: metadata.songLength)
        currentSongPositionIndex = clampedPosition
        if let patternIndex = displayedPatternIndex(in: metadata, songPosition: clampedPosition) {
            currentPatternIndex = patternIndex
            if let selectorIndex = displayedPatternEntries.firstIndex(where: { $0.patternIndex == patternIndex }) {
                selectedDropdownIndex = selectorIndex
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
              let textView = metadataTextView as? PatternTextView else {
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
        guard let textView = metadataTextView as? PatternTextView,
              channels > 0,
              let firstVisibleRowRange = layout.slotGridRanges.first else {
            (metadataTextView as? PatternTextView)?.dividerCharacterIndices = []
            (metadataTextView as? PatternTextView)?.dividerTopCharacterIndex = nil
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

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let scrollView = gridScrollView else { return }
        isLiveResizingTrackerViewport = true
        liveResizeHorizontalOrigin = scrollView.contentView.bounds.origin.x
        pendingHorizontalViewportOrigin = liveResizeHorizontalOrigin
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isLiveResizingTrackerViewport = false
        if let scrollView = gridScrollView {
            lastGridViewportSize = scrollView.contentView.bounds.size
            lastStableGridHorizontalOrigin = scrollView.contentView.bounds.origin.x
        }
        liveResizeHorizontalOrigin = nil
    }

    private func updateTrackerChromeOverlay(layout: PatternViewportTextLayout, viewportState: PatternViewportState) {
        guard let trackerChromeOverlayView,
              let textView = metadataTextView as? PatternTextView,
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

    private func refreshControlPanel() {
        var content = TrackerControlPanelContent()
        content.selectedOctave = selectedOctave
        content.isLoopEnabled = isLoopPlaybackEnabled
        content.isEditModeEnabled = isEditModeEnabled
        content.isPlaybackActive = isPlaybackModeActive

        if let metadata = loadedMetadata {
            content.songTitle = metadata.title.isEmpty ? "(empty title)" : metadata.title
            content.songLength = String(format: "%02d", metadata.songLength)
            content.currentPosition = String(format: "%02d", currentSongPositionIndex)
            content.currentSongPosition = currentSongPositionIndex
            content.maxSongPosition = max(0, metadata.songLength - 1)
            content.isSongPositionEnabled = metadata.songLength > 0
            if metadata.type == "XM",
               metadata.xmPatterns.indices.contains(currentPatternIndex) {
                let pattern = metadata.xmPatterns[currentPatternIndex]
                content.patternLength = "\(pattern.rowCount)"
                content.channelCount = "\(pattern.channels)"
                content.isPatternControlsEnabled = true
                content.areInstrumentPlaceholdersEnabled = metadata.instruments > 0
            } else {
                content.patternLength = "--"
                content.channelCount = String(format: "%02d", metadata.channels)
                content.isPatternControlsEnabled = false
                content.areInstrumentPlaceholdersEnabled = false
            }
            updateInstrumentPlaceholders(for: metadata)
        } else {
            updateInstrumentPlaceholders(for: nil)
        }

        controlPanelView?.apply(content)
    }

    private func updateInstrumentPlaceholders(for metadata: ParsedModuleMetadata?) {
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
