import AppKit

enum SongOrderEditorViewIdentifier {
    static let contentView = "songOrderEditor.contentView"
    static let orderListPanel = "songOrderEditor.orderListPanel"
    static let patternBankPanel = "songOrderEditor.patternBankPanel"
    static let patternOpsPanel = "songOrderEditor.patternOpsPanel"
    static let orderOpsPanel = "songOrderEditor.orderOpsPanel"
    static let dangerPanel = "songOrderEditor.dangerPanel"
    static let orderRowPrefix = "songOrderEditor.orderRow."
    static let patternCellPrefix = "songOrderEditor.patternCell."
}

struct SongOrderEditorDisplayState: Equatable {
    struct OrderRow: Equatable {
        let orderPosition: Int
        let patternIndex: Int
        let rowCount: Int?
        let isSelected: Bool

        var orderDisplay: String {
            Self.decimal3(orderPosition)
        }

        var patternDisplay: String {
            Self.decimal3(patternIndex)
        }

        var rowCountDisplay: String {
            guard let rowCount else {
                return "--"
            }
            return Self.decimal3(rowCount)
        }

        private static func decimal3(_ value: Int) -> String {
            String(format: "%03d", max(0, value))
        }
    }

    struct PatternBankCell: Equatable {
        let patternIndex: Int
        let exists: Bool
        let isUsed: Bool
        let isCurrent: Bool

        var display: String {
            String(format: "%03d", max(0, patternIndex))
        }
    }

    static let bankSize = 64
    static let empty = SongOrderEditorDisplayState(
        orderRows: [],
        patternBankCells: makeBankCells(
            bankIndex: 0,
            existingPatternIndices: [],
            usedPatternIndices: [],
            currentPatternIndex: nil
        ),
        bankRangeLabel: "000-063",
        bankDisplayLabel: "BANK 1/1",
        bankIndex: 0,
        totalBankCount: 1,
        existingPatternIndices: [],
        usedPatternIndices: [],
        selectedOrderPosition: nil,
        selectedPatternIndex: nil,
        hasDocumentState: false
    )

    let orderRows: [OrderRow]
    let patternBankCells: [PatternBankCell]
    let bankRangeLabel: String
    let bankDisplayLabel: String
    let bankIndex: Int
    let totalBankCount: Int
    let existingPatternIndices: Set<Int>
    let usedPatternIndices: Set<Int>
    let selectedOrderPosition: Int?
    let selectedPatternIndex: Int?
    let hasDocumentState: Bool

    static func loadedModule(
        metadata: ParsedModuleMetadata,
        selectedOrderPosition: Int,
        currentPatternIndex: Int,
        requestedBankIndex: Int? = nil
    ) -> SongOrderEditorDisplayState {
        let rowCounts = metadata.xmPatterns.reduce(into: [Int: Int]()) { partialResult, pattern in
            partialResult[pattern.index] = pattern.rowCount
        }
        var existingPatternIndices = Set(metadata.xmPatterns.map(\.index))
        if metadata.patterns > 0 {
            existingPatternIndices.formUnion(0..<metadata.patterns)
        }
        let orderPatternIndices = effectiveOrderPatternIndices(
            orderTable: metadata.orderTable,
            songLength: metadata.songLength
        )
        return make(
            orderPatternIndices: orderPatternIndices,
            rowCountsByPatternIndex: rowCounts,
            existingPatternIndices: existingPatternIndices,
            selectedOrderPosition: selectedOrderPosition,
            currentPatternIndex: currentPatternIndex,
            requestedBankIndex: requestedBankIndex,
            hasDocumentState: true
        )
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        requestedBankIndex: Int? = nil
    ) -> SongOrderEditorDisplayState {
        let rowCounts = document.patterns.reduce(into: [Int: Int]()) { partialResult, pattern in
            partialResult[pattern.index] = pattern.rowCount
        }
        let existingPatternIndices = Set(document.patterns.map(\.index))
        return make(
            orderPatternIndices: effectiveOrderPatternIndices(
                orderTable: document.orderTable,
                songLength: document.songLength
            ),
            rowCountsByPatternIndex: rowCounts,
            existingPatternIndices: existingPatternIndices,
            selectedOrderPosition: document.currentPosition,
            currentPatternIndex: document.currentPatternIndex,
            requestedBankIndex: requestedBankIndex,
            hasDocumentState: true
        )
    }

    func showingBank(_ requestedBankIndex: Int) -> SongOrderEditorDisplayState {
        let bank = Self.resolvedBankIndex(
            requestedBankIndex: requestedBankIndex,
            currentPatternIndex: selectedPatternIndex,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices
        )
        let range = Self.bankRange(for: bank)
        return SongOrderEditorDisplayState(
            orderRows: orderRows,
            patternBankCells: Self.makeBankCells(
                bankIndex: bank,
                existingPatternIndices: existingPatternIndices,
                usedPatternIndices: usedPatternIndices,
                currentPatternIndex: selectedPatternIndex
            ),
            bankRangeLabel: Self.bankRangeLabel(for: range),
            bankDisplayLabel: "BANK \(bank + 1)/\(totalBankCount)",
            bankIndex: bank,
            totalBankCount: totalBankCount,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices,
            selectedOrderPosition: selectedOrderPosition,
            selectedPatternIndex: selectedPatternIndex,
            hasDocumentState: hasDocumentState
        )
    }

    private static func make(
        orderPatternIndices: [Int],
        rowCountsByPatternIndex: [Int: Int],
        existingPatternIndices: Set<Int>,
        selectedOrderPosition: Int,
        currentPatternIndex: Int?,
        requestedBankIndex: Int? = nil,
        hasDocumentState: Bool
    ) -> SongOrderEditorDisplayState {
        let selected = normalizedSelectedOrderPosition(selectedOrderPosition, orderCount: orderPatternIndices.count)
        let usedPatternIndices = Set(orderPatternIndices.filter { $0 >= 0 })
        let orderRows = orderPatternIndices.enumerated().map { orderPosition, patternIndex in
            OrderRow(
                orderPosition: orderPosition,
                patternIndex: patternIndex,
                rowCount: rowCountsByPatternIndex[patternIndex],
                isSelected: selected == orderPosition
            )
        }
        let bank = resolvedBankIndex(
            requestedBankIndex: requestedBankIndex,
            currentPatternIndex: currentPatternIndex,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices
        )
        let bankCells = makeBankCells(
            bankIndex: bank,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices,
            currentPatternIndex: currentPatternIndex
        )
        let range = bankRange(for: bank)
        let totalBanks = totalBankCount(
            currentPatternIndex: currentPatternIndex,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices
        )
        return SongOrderEditorDisplayState(
            orderRows: orderRows,
            patternBankCells: bankCells,
            bankRangeLabel: bankRangeLabel(for: range),
            bankDisplayLabel: "BANK \(bank + 1)/\(totalBanks)",
            bankIndex: bank,
            totalBankCount: totalBanks,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices,
            selectedOrderPosition: selected,
            selectedPatternIndex: currentPatternIndex,
            hasDocumentState: hasDocumentState
        )
    }

    private static func makeBankCells(
        bankIndex: Int,
        existingPatternIndices: Set<Int>,
        usedPatternIndices: Set<Int>,
        currentPatternIndex: Int?
    ) -> [PatternBankCell] {
        let startIndex = max(0, bankIndex) * bankSize
        return (startIndex..<(startIndex + bankSize)).map { patternIndex in
            PatternBankCell(
                patternIndex: patternIndex,
                exists: existingPatternIndices.contains(patternIndex),
                isUsed: usedPatternIndices.contains(patternIndex),
                isCurrent: currentPatternIndex == patternIndex
            )
        }
    }

    private static func resolvedBankIndex(
        requestedBankIndex: Int?,
        currentPatternIndex: Int?,
        existingPatternIndices: Set<Int>,
        usedPatternIndices: Set<Int>
    ) -> Int {
        let totalBanks = totalBankCount(
            currentPatternIndex: currentPatternIndex,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices
        )
        let autoBankIndex = max(0, currentPatternIndex ?? 0) / bankSize
        return min(max(0, requestedBankIndex ?? autoBankIndex), totalBanks - 1)
    }

    private static func totalBankCount(
        currentPatternIndex: Int?,
        existingPatternIndices: Set<Int>,
        usedPatternIndices: Set<Int>
    ) -> Int {
        let highestPatternIndex = max(
            existingPatternIndices.max() ?? 0,
            usedPatternIndices.max() ?? 0,
            currentPatternIndex ?? 0
        )
        return max(1, (highestPatternIndex / bankSize) + 1)
    }

    private static func bankRange(for bankIndex: Int) -> ClosedRange<Int> {
        let startIndex = max(0, bankIndex) * bankSize
        return startIndex...(startIndex + bankSize - 1)
    }

    private static func bankRangeLabel(for range: ClosedRange<Int>) -> String {
        String(format: "%03d-%03d", range.lowerBound, range.upperBound)
    }

    private static func effectiveOrderPatternIndices(orderTable: [Int], songLength: Int) -> [Int] {
        Array(orderTable.prefix(max(0, min(songLength, orderTable.count))))
    }

    private static func normalizedSelectedOrderPosition(_ value: Int, orderCount: Int) -> Int? {
        guard orderCount > 0 else {
            return nil
        }
        return min(max(0, value), orderCount - 1)
    }
}

struct SongOrderEditorNavigationResult: Equatable {
    let selectedOrderPosition: Int
    let currentPatternIndex: Int
}

enum SongOrderEditorNavigation {
    static func loadedModulePatternSelection(
        selectingPatternIndex patternIndex: Int,
        metadata: ParsedModuleMetadata,
        currentPatternIndex: Int,
        isPlaybackActive: Bool
    ) -> Int? {
        guard !isPlaybackActive,
              patternIndex != currentPatternIndex,
              metadata.xmPattern(index: patternIndex) != nil else {
            return nil
        }
        return patternIndex
    }

    static func loadedModuleSelection(
        selectingOrderPosition orderPosition: Int,
        metadata: ParsedModuleMetadata,
        currentOrderPosition: Int,
        isPlaybackActive: Bool
    ) -> SongOrderEditorNavigationResult? {
        guard !isPlaybackActive,
              orderPosition != currentOrderPosition,
              let patternIndex = referencedPatternIndex(
                  orderPosition: orderPosition,
                  orderTable: metadata.orderTable,
                  songLength: metadata.songLength
              ),
              metadata.xmPattern(index: patternIndex) != nil else {
            return nil
        }
        return SongOrderEditorNavigationResult(
            selectedOrderPosition: orderPosition,
            currentPatternIndex: patternIndex
        )
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        selectingPatternIndex patternIndex: Int,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive,
              patternIndex != document.currentPatternIndex,
              document.pattern(for: patternIndex) != nil else {
            return nil
        }
        return BlankTrackerDocument(
            title: document.title,
            songLength: document.songLength,
            currentPosition: document.currentPosition,
            restartPosition: document.restartPosition,
            currentPatternIndex: patternIndex,
            tempo: document.tempo,
            speed: document.speed,
            orderTable: document.orderTable,
            selection: document.selection,
            instrumentPalette: document.instrumentPalette,
            patterns: document.patterns
        )
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        selectingOrderPosition orderPosition: Int,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive,
              orderPosition != document.currentPosition,
              let patternIndex = referencedPatternIndex(
                  orderPosition: orderPosition,
                  orderTable: document.orderTable,
                  songLength: document.songLength
              ),
              document.pattern(for: patternIndex) != nil else {
            return nil
        }
        return BlankTrackerDocument(
            title: document.title,
            songLength: document.songLength,
            currentPosition: orderPosition,
            restartPosition: document.restartPosition,
            currentPatternIndex: patternIndex,
            tempo: document.tempo,
            speed: document.speed,
            orderTable: document.orderTable,
            selection: document.selection,
            instrumentPalette: document.instrumentPalette,
            patterns: document.patterns
        )
    }

    private static func referencedPatternIndex(orderPosition: Int, orderTable: [Int], songLength: Int) -> Int? {
        let effectiveOrderCount = min(max(0, songLength), orderTable.count)
        guard orderPosition >= 0,
              orderPosition < effectiveOrderCount else {
            return nil
        }
        return orderTable[orderPosition]
    }
}

enum TrackerPlaybackStartContextResolver {
    static func normalPlayContext(
        metadata: ParsedModuleMetadata,
        selectedSongPositionIndex: Int,
        displayedPatternIndex: Int,
        row: Int
    ) -> PlaybackStartContext {
        let orderCount = min(max(0, metadata.songLength), metadata.orderTable.count)
        let orderPosition = orderCount > 0
            ? min(max(0, selectedSongPositionIndex), orderCount - 1)
            : max(0, selectedSongPositionIndex)
        let referencedPattern = metadata.orderTable.indices.contains(orderPosition)
            ? metadata.orderTable[orderPosition]
            : nil
        let playbackPatternIndex = referencedPattern.flatMap { patternIndex -> Int? in
            if metadata.type == "XM" {
                return metadata.xmPattern(index: patternIndex)?.index
            }
            return patternIndex >= 0 && patternIndex < metadata.patterns ? patternIndex : nil
        } ?? displayedPatternIndex

        return PlaybackStartContext(
            moduleTitle: metadata.title.isEmpty ? nil : metadata.title,
            songPosition: orderPosition,
            patternIndex: playbackPatternIndex,
            row: row
        )
    }
}

@MainActor
enum SongOrderEditorRefreshPolicy {
    static func shouldRefresh(isWindowVisible: Bool, isPlaybackActive: Bool) -> Bool {
        isWindowVisible && !isPlaybackActive
    }
}

@MainActor
final class SongOrderEditorWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 660, height: 480)
    var closeHandler: (() -> Void)?
    var onOrderSelected: ((Int) -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onOrderSelected = onOrderSelected
        }
    }
    var onPatternSelected: ((Int) -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onPatternSelected = onPatternSelected
        }
    }

    init(displayState: SongOrderEditorDisplayState = .empty) {
        let contentView = SongOrderEditorContentView(
            frame: NSRect(origin: .zero, size: Self.contentSize),
            displayState: displayState
        )
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
        panel.delegate = self
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

    var isVisibleForRefresh: Bool {
        guard let window else {
            return false
        }
        return window.isVisible && !window.isMiniaturized
    }

    @discardableResult
    func apply(displayState: SongOrderEditorDisplayState) -> Bool {
        guard let contentView = window?.contentView as? SongOrderEditorContentView else {
            return false
        }
        contentView.onOrderSelected = onOrderSelected
        contentView.onPatternSelected = onPatternSelected
        return contentView.apply(displayState: displayState)
    }

    @discardableResult
    func applyIfVisible(displayState: SongOrderEditorDisplayState) -> Bool {
        guard isVisibleForRefresh else {
            return false
        }
        return apply(displayState: displayState)
    }

    func windowWillClose(_ notification: Notification) {
        closeHandler?()
    }
}

@MainActor
final class SongOrderEditorContentView: FlippedEditorView {
    var onOrderSelected: ((Int) -> Void)?
    var onPatternSelected: ((Int) -> Void)?
    private(set) var displayState: SongOrderEditorDisplayState
    private(set) var rebuildCount = 0
    private(set) var selectedOrderScrollCount = 0
    private let usedPatternFill = NSColor(srgbRed: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x10 / 255.0, alpha: 1.0)
    private var lastScrolledSelectedOrderPosition: Int?

    init(frame frameRect: NSRect, displayState: SongOrderEditorDisplayState = .empty) {
        self.displayState = displayState
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(SongOrderEditorViewIdentifier.contentView)
        style(background: VTXEditorControlTheme.windowBackground)
        buildShell()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func apply(displayState: SongOrderEditorDisplayState) -> Bool {
        guard self.displayState != displayState else {
            return false
        }
        self.displayState = displayState
        rebuildShell()
        return true
    }

    @objc
    private func showPreviousBank(_ sender: Any?) {
        showBank(displayState.bankIndex - 1)
    }

    @objc
    private func showNextBank(_ sender: Any?) {
        showBank(displayState.bankIndex + 1)
    }

    private func showBank(_ bankIndex: Int) {
        apply(displayState: displayState.showingBank(bankIndex))
    }

    private func rebuildShell() {
        rebuildCount += 1
        subviews.forEach { $0.removeFromSuperview() }
        buildShell()
    }

    private func buildShell() {
        addSurface(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.60))
        buildOrderListPanel(panel(SongOrderEditorViewIdentifier.orderListPanel, "Order list", "— the song sequence", NSRect(x: 12, y: 13, width: 296, height: 320)))
        buildPatternBankPanel(panel(SongOrderEditorViewIdentifier.patternBankPanel, "Pattern bank", nil, NSRect(x: 318, y: 13, width: 330, height: 250)))
        buildPatternOpsPanel(panel(SongOrderEditorViewIdentifier.patternOpsPanel, "Pattern ops", nil, NSRect(x: 318, y: 273, width: 330, height: 60)))
        buildOrderOpsPanel(panel(SongOrderEditorViewIdentifier.orderOpsPanel, "Order ops", orderOpsHint, NSRect(x: 12, y: 343, width: 636, height: 66)))
        buildDangerPanel(plainPanel(SongOrderEditorViewIdentifier.dangerPanel, NSRect(x: 12, y: 419, width: 636, height: 49), border: VTXEditorControlTheme.dangerRed.withAlphaComponent(0.35)))
    }

    private var orderOpsHint: String {
        guard let selectedOrderPosition = displayState.selectedOrderPosition else {
            return "— no selected slot"
        }
        return String(format: "— selected slot (ORD %03d)", selectedOrderPosition)
    }

    private func buildOrderListPanel(_ panel: NSView) {
        let list = addSurface(in: panel, frame: NSRect(x: 10, y: 32, width: 276, height: 242), background: VTXEditorControlTheme.recessedReadoutBackground, border: VTXEditorControlTheme.mutedGoldBorderSubtle, radius: 3)
        addOrderHeader(to: list)
        addOrderRowsScrollView(to: list)
        addLegendLabel("ORD", suffix: " = order position", to: panel, frame: NSRect(x: 10, y: 286, width: 124, height: 14), tokenColor: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55))
        addLegendLabel("PTN", suffix: " = pattern number", to: panel, frame: NSRect(x: 146, y: 286, width: 130, height: 14), tokenColor: VTXEditorControlTheme.warmValueText)
    }

    private func addOrderHeader(to parent: NSView) {
        addLabel("ORD", to: parent, frame: NSRect(x: 10, y: 4, width: 52, height: 12), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addLabel("PTN", to: parent, frame: NSRect(x: 70, y: 4, width: 70, height: 12), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold, alignment: .center)
        addLabel("ROWS", to: parent, frame: NSRect(x: 148, y: 4, width: 64, height: 12), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addHorizontalRule(to: parent, y: 19, width: 276, alpha: 0.12)
    }

    private func addOrderRowsScrollView(to parent: NSView) {
        let rowHeight: CGFloat = 18
        let scrollFrame = NSRect(x: 0, y: 20, width: 276, height: 222)
        let contentHeight = max(scrollFrame.height, CGFloat(max(1, displayState.orderRows.count)) * rowHeight)
        let documentView = FlippedEditorView(frame: NSRect(x: 0, y: 0, width: scrollFrame.width, height: contentHeight))
        documentView.style(background: VTXEditorControlTheme.recessedReadoutBackground)

        if displayState.orderRows.isEmpty {
            let message = displayState.hasDocumentState ? "NO ORDERS" : "NO DOCUMENT"
            addCenteredLabel(
                message,
                to: documentView,
                frame: NSRect(x: 0, y: 18, width: scrollFrame.width, height: 18),
                color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28),
                size: 10,
                weight: .semibold,
                alignment: .center
            )
        } else {
            for (index, row) in displayState.orderRows.enumerated() {
                addOrderRow(to: documentView, y: CGFloat(index) * rowHeight, row: row, width: scrollFrame.width)
            }
        }

        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = displayState.orderRows.count > Int(scrollFrame.height / rowHeight)
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        parent.addSubview(scrollView)
        scrollSelectedOrderRowIfNeeded(in: scrollView, rowHeight: rowHeight, contentHeight: contentHeight)
    }

    private func scrollSelectedOrderRowIfNeeded(in scrollView: NSScrollView, rowHeight: CGFloat, contentHeight: CGFloat) {
        guard let selectedOrderPosition = displayState.selectedOrderPosition,
              let selectedIndex = displayState.orderRows.firstIndex(where: \.isSelected) else {
            lastScrolledSelectedOrderPosition = nil
            return
        }
        guard selectedOrderPosition != lastScrolledSelectedOrderPosition else {
            return
        }
        let visibleHeight = scrollView.contentView.bounds.height
        let selectedY = CGFloat(selectedIndex) * rowHeight
        let centeredOriginY = selectedY - ((visibleHeight - rowHeight) / 2)
        let maxOriginY = max(0, contentHeight - visibleHeight)
        let originY = min(max(0, centeredOriginY), maxOriginY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: originY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        selectedOrderScrollCount += 1
        lastScrolledSelectedOrderPosition = selectedOrderPosition
    }

    private func addOrderRow(to parent: NSView, y: CGFloat, row rowState: SongOrderEditorDisplayState.OrderRow, width: CGFloat) {
        let row = SongOrderEditorOrderRowView(
            orderPosition: rowState.orderPosition,
            isSelectedOrder: rowState.isSelected
        ) { [weak self] orderPosition in
            self?.onOrderSelected?(orderPosition)
        }
        row.frame = NSRect(x: 0, y: y, width: width, height: 18)
        row.style(background: rowState.isSelected ? VTXEditorControlTheme.indigoSelection : VTXEditorControlTheme.recessedReadoutBackground)
        parent.addSubview(row)
        row.identifier = NSUserInterfaceItemIdentifier(SongOrderEditorViewIdentifier.orderRowPrefix + rowState.orderDisplay)
        row.toolTip = "Navigate to order \(rowState.orderDisplay)"
        addLabel(rowState.orderDisplay, to: row, frame: NSRect(x: 10, y: 2, width: 52, height: 13), color: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55), size: 10)
        addLabel(rowState.patternDisplay, to: row, frame: NSRect(x: 70, y: 1, width: 70, height: 14), color: VTXEditorControlTheme.warmValueText, size: 10.5, weight: .bold, alignment: .center)
        addLabel(rowState.rowCountDisplay, to: row, frame: NSRect(x: 148, y: 2, width: 64, height: 13), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.48), size: 10, alignment: .left)
        addHorizontalRule(to: parent, y: y + 17, width: width, alpha: 0.05)
    }

    private func buildPatternBankPanel(_ panel: NSView) {
        addCenteredLabel(displayState.bankRangeLabel, to: panel, frame: NSRect(x: 96, y: 5, width: 72, height: 22), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.50), size: 9)
        addButton(
            "◀",
            to: panel,
            frame: NSRect(x: 174, y: 5, width: 22, height: 22),
            target: self,
            action: #selector(showPreviousBank(_:)),
            toolTip: "Show previous pattern bank"
        )
        addButton(
            "▶",
            to: panel,
            frame: NSRect(x: 201, y: 5, width: 22, height: 22),
            target: self,
            action: #selector(showNextBank(_:)),
            toolTip: "Show next pattern bank"
        )
        addSegment(displayState.bankDisplayLabel, to: panel, frame: NSRect(x: 228, y: 5, width: 90, height: 22), fontSize: 9)

        for row in 0..<8 {
            for column in 0..<8 {
                let index = (row * 8) + column
                if displayState.patternBankCells.indices.contains(index) {
                    addPatternCell(displayState.patternBankCells[index], to: panel, frame: NSRect(x: 10 + CGFloat(column * 38), y: 35 + CGFloat(row * 25), width: 31, height: 23))
                }
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

    private func addPatternCell(_ cellState: SongOrderEditorDisplayState.PatternBankCell, to parent: NSView, frame: NSRect) {
        let used = cellState.isUsed
        let exists = cellState.exists
        let current = cellState.isCurrent
        let cell = SongOrderEditorPatternCellView(
            patternIndex: cellState.patternIndex,
            isClickable: exists
        ) { [weak self] patternIndex in
            self?.onPatternSelected?(patternIndex)
        }
        cell.frame = frame
        cell.style(
            background: used ? usedPatternFill : VTXEditorControlTheme.recessedReadoutBackground,
            border: current ? VTXEditorControlTheme.accentGold : ((used || exists) ? VTXEditorControlTheme.mutedGoldBorderMedium : VTXEditorControlTheme.mutedGoldBorderSubtle),
            radius: 2
        )
        parent.addSubview(cell)
        cell.identifier = NSUserInterfaceItemIdentifier(SongOrderEditorViewIdentifier.patternCellPrefix + cellState.display)
        cell.toolTip = exists ? "Navigate to pattern \(cellState.display)" : "Empty pattern slot"
        if used {
            addSurface(in: cell, frame: NSRect(x: 0, y: 0, width: 2, height: frame.height), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.55))
        } else if exists {
            addSurface(in: cell, frame: NSRect(x: 0, y: frame.height - 2, width: frame.width, height: 2), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.22))
        }
        let textAlpha: CGFloat = (used || current) ? 1.0 : (exists ? 0.64 : 0.30)
        addCenteredLabel(cellState.display, to: cell, frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(textAlpha), size: 8.8, weight: (used || exists) ? .semibold : .regular, alignment: .center)
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

    private func addButton(
        _ title: String,
        to parent: NSView,
        frame: NSRect,
        role: VTXEditorButtonRole = .normal,
        target: AnyObject? = nil,
        action: Selector? = nil,
        isEnabled: Bool = true,
        toolTip: String = "Inactive shell control"
    ) {
        let button = VTXEditorControlFactory.makeButton(title: title, role: role, fixedWidth: frame.width)
        button.isEnabled = isEnabled
        button.target = target
        button.action = action
        if action == nil {
            button.sendAction(on: [])
        }
        button.toolTip = toolTip
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

    private func addLegendLabel(
        _ token: String,
        suffix: String,
        to parent: NSView,
        frame: NSRect,
        tokenColor: NSColor
    ) {
        let text = token + suffix
        let descriptionColor = VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40)
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: descriptionColor,
            ]
        )
        attributedText.addAttribute(
            .foregroundColor,
            value: tokenColor,
            range: NSRange(location: 0, length: token.utf16.count)
        )

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = descriptionColor
        label.attributedStringValue = attributedText
        label.alignment = .left
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

final class SongOrderEditorOrderRowView: FlippedEditorView {
    private let orderPosition: Int
    private let isSelectedOrder: Bool
    private let selectHandler: (Int) -> Void

    init(orderPosition: Int, isSelectedOrder: Bool, selectHandler: @escaping (Int) -> Void) {
        self.orderPosition = orderPosition
        self.isSelectedOrder = isSelectedOrder
        self.selectHandler = selectHandler
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard !isSelectedOrder else {
            return
        }
        selectHandler(orderPosition)
    }
}

final class SongOrderEditorPatternCellView: FlippedEditorView {
    private let patternIndex: Int
    private let isClickable: Bool
    private let selectHandler: (Int) -> Void

    init(patternIndex: Int, isClickable: Bool, selectHandler: @escaping (Int) -> Void) {
        self.patternIndex = patternIndex
        self.isClickable = isClickable
        self.selectHandler = selectHandler
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isClickable else {
            return
        }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isClickable, bounds.contains(point) else {
            return super.hitTest(point)
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard isClickable else {
            return
        }
        selectHandler(patternIndex)
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
