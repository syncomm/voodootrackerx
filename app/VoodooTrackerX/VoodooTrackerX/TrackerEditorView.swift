// Owns the tracker editor viewport UI, including the header, body, pinned gutter overlay, and editor-specific helpers.
// It does not own module loading, tracker state decisions, or control-panel behavior.
import AppKit

enum PatternGridPreferences {
    static let beatAccentIntervalKey = "PatternGridBeatAccentInterval"
    static let defaultBeatAccentInterval = 4

    static var beatAccentInterval: Int {
        let stored = UserDefaults.standard.integer(forKey: beatAccentIntervalKey)
        return stored > 0 ? stored : defaultBeatAccentInterval
    }
}

enum TrackerPinnedGutterGeometry {
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

enum TrackerViewportScrollGeometry {
    static func clampedHorizontalOrigin(
        preferredOriginX: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let maxOriginX = max(0, contentWidth - viewportWidth)
        return min(max(0, preferredOriginX), maxOriginX)
    }
}

enum TrackerViewportResizeBehavior {
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

    init(pattern: XMPatternData, state: PatternViewportState) {
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

final class TrackerChromeOverlayView: NSView {
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

final class TrackerDividerUnderlayView: NSView {
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

final class PatternTextView: NSTextView {
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

final class TrackerEditorView: NSView {
    let patternInfoLabel: NSTextField
    let patternHeaderTextView: PatternTextView
    let patternHeaderScrollView: NSScrollView
    let metadataTextView: PatternTextView
    let gridScrollView: NSScrollView
    let trackerDividerUnderlayView: TrackerDividerUnderlayView
    let trackerChromeOverlayView: TrackerChromeOverlayView

    private let theme: TrackerTheme
    private let trackerBackground = NSColor.black

    init(frame frameRect: NSRect, theme: TrackerTheme = .legacyDark) {
        self.theme = theme

        patternInfoLabel = NSTextField(labelWithString: "")
        patternHeaderScrollView = NSScrollView(
            frame: NSRect(
                x: 0,
                y: frameRect.height - TrackerThemeMetrics.WindowLayout.trackerHeaderHeight,
                width: frameRect.width,
                height: TrackerThemeMetrics.WindowLayout.channelHeaderHeight
            )
        )
        patternHeaderTextView = PatternTextView(frame: patternHeaderScrollView.bounds)
        let bodyHeight = frameRect.height - TrackerThemeMetrics.WindowLayout.trackerHeaderHeight - 8
        gridScrollView = NSScrollView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: frameRect.width,
                height: bodyHeight
            )
        )
        metadataTextView = PatternTextView(frame: gridScrollView.bounds)
        trackerDividerUnderlayView = TrackerDividerUnderlayView(frame: NSRect(origin: .zero, size: frameRect.size))
        trackerChromeOverlayView = TrackerChromeOverlayView(frame: NSRect(origin: .zero, size: frameRect.size))

        super.init(frame: frameRect)

        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = trackerBackground.cgColor

        configurePatternInfoLabel()
        configurePatternHeader()
        configureGridScrollView()
        configureMetadataTextView()
        configureOverlayViews()
        buildHierarchy()
        applyEmptyStateMessage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configurePatternInfoLabel() {
        patternInfoLabel.frame = NSRect(x: 0, y: bounds.height - 24, width: bounds.width, height: 20)
        patternInfoLabel.autoresizingMask = [.width, .minYMargin]
        patternInfoLabel.font = TrackerThemeFonts.trackerBody
        patternInfoLabel.textColor = theme.text
        patternInfoLabel.lineBreakMode = .byTruncatingTail
        patternInfoLabel.backgroundColor = .clear
        patternInfoLabel.isHidden = true
    }

    private func configurePatternHeader() {
        patternHeaderScrollView.autoresizingMask = [.width, .minYMargin]
        patternHeaderScrollView.hasVerticalScroller = false
        patternHeaderScrollView.hasHorizontalScroller = false
        patternHeaderScrollView.verticalScrollElasticity = .none
        patternHeaderScrollView.horizontalScrollElasticity = .none
        patternHeaderScrollView.borderType = .noBorder
        patternHeaderScrollView.drawsBackground = true
        patternHeaderScrollView.backgroundColor = trackerBackground
        patternHeaderScrollView.isHidden = true

        patternHeaderTextView.autoresizingMask = []
        patternHeaderTextView.isEditable = false
        patternHeaderTextView.isRichText = false
        patternHeaderTextView.isSelectable = false
        patternHeaderTextView.isHorizontallyResizable = true
        patternHeaderTextView.isVerticallyResizable = false
        patternHeaderTextView.minSize = NSSize(width: 0, height: 0)
        patternHeaderTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: TrackerThemeMetrics.WindowLayout.trackerHeaderHeight)
        patternHeaderTextView.font = TrackerThemeFonts.trackerHeader
        patternHeaderTextView.textContainerInset = NSSize(width: 4, height: 2)
        patternHeaderTextView.drawsBackground = true
        patternHeaderTextView.backgroundColor = trackerBackground
        patternHeaderTextView.textColor = theme.accent
        patternHeaderTextView.textContainer?.lineFragmentPadding = 0
        patternHeaderTextView.textContainer?.widthTracksTextView = false
        patternHeaderTextView.textContainer?.heightTracksTextView = true
        patternHeaderTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: TrackerThemeMetrics.WindowLayout.trackerHeaderHeight)
        patternHeaderTextView.textContainer?.lineBreakMode = .byClipping
        patternHeaderTextView.theme = theme
        patternHeaderTextView.drawsDividers = false
        patternHeaderScrollView.documentView = patternHeaderTextView
    }

    private func configureGridScrollView() {
        gridScrollView.autoresizingMask = [.width, .height]
        gridScrollView.hasVerticalScroller = false
        gridScrollView.hasHorizontalScroller = true
        gridScrollView.verticalScrollElasticity = .none
        gridScrollView.horizontalScrollElasticity = .none
        gridScrollView.borderType = .bezelBorder
        gridScrollView.drawsBackground = true
        gridScrollView.backgroundColor = trackerBackground
        gridScrollView.contentView.postsBoundsChangedNotifications = true
    }

    private func configureMetadataTextView() {
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
        gridScrollView.documentView = metadataTextView
    }

    private func configureOverlayViews() {
        trackerDividerUnderlayView.autoresizingMask = [.width, .height]
        trackerDividerUnderlayView.theme = theme
        trackerDividerUnderlayView.headerScrollView = patternHeaderScrollView
        trackerDividerUnderlayView.bodyTextView = metadataTextView
        trackerDividerUnderlayView.bodyScrollView = gridScrollView
        trackerDividerUnderlayView.isHidden = true

        trackerChromeOverlayView.autoresizingMask = [.width, .height]
        trackerChromeOverlayView.theme = theme
        trackerChromeOverlayView.chromeBackgroundColor = trackerBackground
        trackerChromeOverlayView.headerScrollView = patternHeaderScrollView
        trackerChromeOverlayView.bodyTextView = metadataTextView
        trackerChromeOverlayView.bodyScrollView = gridScrollView
        trackerChromeOverlayView.isHidden = true
    }

    private func buildHierarchy() {
        addSubview(patternInfoLabel)
        addSubview(patternHeaderScrollView)
        addSubview(gridScrollView)
        addSubview(trackerChromeOverlayView)
        addSubview(trackerDividerUnderlayView, positioned: .below, relativeTo: trackerChromeOverlayView)
    }

    private func applyEmptyStateMessage() {
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
    }
}
