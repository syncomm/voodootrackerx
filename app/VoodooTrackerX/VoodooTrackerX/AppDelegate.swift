// Owns app lifecycle, menu/setup, module loading, and top-level coordination between state and the main window.
// It intentionally does not build the window hierarchy directly, but it still owns tracker state/render coordination for now.
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

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private var windowController: TrackerWindowController?
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

    private var mainWindow: NSWindow? { windowController?.window }
    private var controlPanelView: ControlPanelView? { windowController?.controlPanelView }
    private var metadataTextView: PatternTextView? { windowController?.metadataTextView }
    private var patternInfoLabel: NSTextField? { windowController?.patternInfoLabel }
    private var patternHeaderTextView: PatternTextView? { windowController?.patternHeaderTextView }
    private var patternHeaderScrollView: NSScrollView? { windowController?.patternHeaderScrollView }
    private var gridScrollView: NSScrollView? { windowController?.gridScrollView }
    private var trackerDividerUnderlayView: TrackerDividerUnderlayView? { windowController?.trackerDividerUnderlayView }
    private var trackerChromeOverlayView: TrackerChromeOverlayView? { windowController?.trackerChromeOverlayView }
    private var patternSelector: NSPopUpButton? { controlPanelView?.patternSelector }
    private var editModeCheckbox: NSButton? { controlPanelView?.editModeButton }

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
        if windowController == nil {
            let controller = TrackerWindowController(theme: theme)
            controller.metadataTextView.navigationHandler = { [weak self] command in
                self?.handlePatternNavigation(command)
            }
            controller.metadataTextView.editInputHandler = { [weak self] input in
                self?.handlePatternEditInput(input) ?? false
            }
            controller.metadataTextView.wheelNavigationHandler = { [weak self] deltaY in
                self?.handlePatternWheel(deltaY: deltaY)
            }
            controller.controlPanelView.playButton.target = self
            controller.controlPanelView.playButton.action = #selector(playPressed(_:))
            controller.controlPanelView.stopButton.target = self
            controller.controlPanelView.stopButton.action = #selector(stopPressed(_:))
            controller.controlPanelView.loopButton.target = self
            controller.controlPanelView.loopButton.action = #selector(loopToggled(_:))
            controller.controlPanelView.editModeButton.target = self
            controller.controlPanelView.editModeButton.action = #selector(editModeToggled(_:))
            controller.controlPanelView.patternSelector.target = self
            controller.controlPanelView.patternSelector.action = #selector(patternSelectionChanged(_:))
            controller.controlPanelView.currentPositionStepper.target = self
            controller.controlPanelView.currentPositionStepper.action = #selector(currentSongPositionStepperChanged(_:))
            controller.controlPanelView.octaveSelector.target = self
            controller.controlPanelView.octaveSelector.action = #selector(octaveSelectionChanged(_:))
            controller.onWillStartLiveResize = { [weak self] in
                self?.trackerWindowWillStartLiveResize()
            }
            controller.onDidEndLiveResize = { [weak self] in
                self?.trackerWindowDidEndLiveResize()
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(gridClipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: controller.gridScrollView.contentView
            )
            windowController = controller
            lastGridViewportSize = controller.gridScrollView.contentView.bounds.size
            refreshControlPanel()
        }
        windowController?.showAndActivate()
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

    @objc
    private func openModuleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
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
                metadataTextView?.activeFieldRange = nil
                metadataTextView?.dividerCharacterIndices = []
                metadataTextView?.dividerTopCharacterIndex = nil
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
              let textView = metadataTextView else {
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
        guard let textView = metadataTextView,
              channels > 0,
              let firstVisibleRowRange = layout.slotGridRanges.first else {
            metadataTextView?.dividerCharacterIndices = []
            metadataTextView?.dividerTopCharacterIndex = nil
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

    private func trackerWindowWillStartLiveResize() {
        guard let scrollView = gridScrollView else { return }
        isLiveResizingTrackerViewport = true
        liveResizeHorizontalOrigin = scrollView.contentView.bounds.origin.x
        pendingHorizontalViewportOrigin = liveResizeHorizontalOrigin
    }

    private func trackerWindowDidEndLiveResize() {
        isLiveResizingTrackerViewport = false
        if let scrollView = gridScrollView {
            lastGridViewportSize = scrollView.contentView.bounds.size
            lastStableGridHorizontalOrigin = scrollView.contentView.bounds.origin.x
        }
        liveResizeHorizontalOrigin = nil
    }

    private func updateTrackerChromeOverlay(layout: PatternViewportTextLayout, viewportState: PatternViewportState) {
        guard let trackerChromeOverlayView,
              let textView = metadataTextView,
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
        var content = ControlPanelContent()
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
