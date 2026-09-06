import AppKit

enum ClearSongDataSourceContext: Equatable {
    case none
    case editable(
        documentIdentity: UUID?,
        documentRevision: UInt64,
        document: BlankTrackerDocument
    )
    case loadedReadOnly(
        moduleIdentity: UUID?,
        metadata: ParsedModuleMetadata,
        playbackSong: PlaybackSong,
        selection: TrackerEditorSelection,
        sourcePatternIndex: Int,
        bridgeEligible: Bool
    )
}

struct ClearSongDataContext: Equatable {
    let source: ClearSongDataSourceContext
    let isPlaybackActive: Bool
    let hasConflictingDocumentPresentation: Bool

    static let unavailable = Self(
        source: .none,
        isPlaybackActive: false,
        hasConflictingDocumentPresentation: false
    )

    fileprivate var commitTarget: ClearSongDataCommitTarget? {
        switch source {
        case .none:
            return nil
        case let .editable(documentIdentity, documentRevision, document):
            guard let documentIdentity,
                  EditorCommandAvailability.canClearSongData(
                      hasBlankDocument: true,
                      sourceContext: document.noteAuditionSourceContext,
                      isPlaybackActive: isPlaybackActive,
                      hasConflictingDocumentPresentation: hasConflictingDocumentPresentation,
                      isConfirmationActive: false
                  ) else { return nil }
            return .editable(
                documentIdentity: documentIdentity,
                documentRevision: documentRevision,
                document: document
            )
        case let .loadedReadOnly(
            moduleIdentity,
            metadata,
            playbackSong,
            selection,
            sourcePatternIndex,
            bridgeEligible
        ):
            guard let moduleIdentity,
                  EditorCommandAvailability.canClearSongData(
                      hasBlankDocument: false,
                      sourceContext: .loadedModule(patternIndex: sourcePatternIndex),
                      loadedModuleCanMakeEditableCopy: bridgeEligible,
                      isPlaybackActive: isPlaybackActive,
                      hasConflictingDocumentPresentation: hasConflictingDocumentPresentation,
                      isConfirmationActive: false
                  ) else { return nil }
            return .loadedReadOnly(
                moduleIdentity: moduleIdentity,
                metadata: metadata,
                playbackSong: playbackSong,
                selection: selection,
                sourcePatternIndex: sourcePatternIndex
            )
        }
    }
}

enum ClearSongDataConfirmationKind: Equatable {
    case editableDocument
    case loadedReadOnlyModule
}

struct ClearSongDataRequest: Equatable {
    let operationToken: UUID
    let kind: ClearSongDataConfirmationKind
}

enum ClearSongDataCommitTarget: Equatable {
    case editable(
        documentIdentity: UUID,
        documentRevision: UInt64,
        document: BlankTrackerDocument
    )
    case loadedReadOnly(
        moduleIdentity: UUID,
        metadata: ParsedModuleMetadata,
        playbackSong: PlaybackSong,
        selection: TrackerEditorSelection,
        sourcePatternIndex: Int
    )

    fileprivate var confirmationKind: ClearSongDataConfirmationKind {
        switch self {
        case .editable:
            return .editableDocument
        case .loadedReadOnly:
            return .loadedReadOnlyModule
        }
    }

    func isCurrent(in context: ClearSongDataContext) -> Bool {
        context.commitTarget == self
    }
}

@MainActor
final class ClearSongDataCoordinator {
    private let contextProvider: () -> ClearSongDataContext
    private let commitHandler: (ClearSongDataCommitTarget) -> Bool
    private let stateChangeHandler: () -> Void
    private var activeOperation: (
        token: UUID,
        target: ClearSongDataCommitTarget,
        didObservePlayback: Bool
    )?

    init(
        contextProvider: @escaping () -> ClearSongDataContext,
        commitHandler: @escaping (ClearSongDataCommitTarget) -> Bool,
        stateChangeHandler: @escaping () -> Void = {}
    ) {
        self.contextProvider = contextProvider
        self.commitHandler = commitHandler
        self.stateChangeHandler = stateChangeHandler
    }

    var isActive: Bool { activeOperation != nil }
    var canBegin: Bool {
        activeOperation == nil && contextProvider().commitTarget != nil
    }

    func begin() -> ClearSongDataRequest? {
        guard activeOperation == nil,
              let target = contextProvider().commitTarget else { return nil }
        let token = UUID()
        activeOperation = (token, target, false)
        stateChangeHandler()
        return ClearSongDataRequest(operationToken: token, kind: target.confirmationKind)
    }

    func invalidateActiveConfirmationForPlaybackStart() {
        guard var activeOperation else { return }
        activeOperation.didObservePlayback = true
        self.activeOperation = activeOperation
    }

    @discardableResult
    func cancel(operationToken: UUID) -> Bool {
        guard activeOperation?.token == operationToken else { return false }
        finish()
        return true
    }

    @discardableResult
    func confirm(operationToken: UUID) -> Bool {
        guard let activeOperation,
              activeOperation.token == operationToken else { return false }
        defer { finish() }
        guard !activeOperation.didObservePlayback,
              activeOperation.target.isCurrent(in: contextProvider()) else { return false }
        return commitHandler(activeOperation.target)
    }

    private func finish() {
        activeOperation = nil
        stateChangeHandler()
    }
}

@MainActor
enum ClearSongDataAlert {
    static func make(request: ClearSongDataRequest) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch request.kind {
        case .editableDocument:
            alert.messageText = "Clear Song Data?"
            alert.informativeText = """
            This will remove all pattern and order data from the current editable document.
            Instruments and samples will be preserved.

            You can undo this change immediately with Edit > Undo.
            """
            alert.addButton(withTitle: "Clear Song Data")
            alert.buttons[0].setAccessibilityLabel("Clear song pattern and order data")
        case .loadedReadOnlyModule:
            alert.messageText = "Create Editable Copy with Song Data Cleared?"
            alert.informativeText = """
            The loaded module will remain unchanged.
            VTX will create an editable document with pattern/order data cleared and the supported instrument/sample palette preserved.
            """
            alert.addButton(withTitle: "Create Editable Copy")
            alert.buttons[0].setAccessibilityLabel("Create editable copy with song data cleared")
        }
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert
    }

    static func isConfirmed(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }
}

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

struct EditableMainPatternSelectorProjection: Equatable {
    let entries: [ModuleMetadataLoader.PatternSelectionEntry]
    let invalidReferencedPatterns: [Int]
    let selectedEntryIndex: Int?

    init(document: BlankTrackerDocument) {
        let effectiveOrderCount = min(max(0, document.songLength), document.orderTable.count)
        let effectiveOrder = Array(document.orderTable.prefix(effectiveOrderCount))
        var representedPatternsByIndex = [Int: XMPatternData]()
        for pattern in document.patterns where representedPatternsByIndex[pattern.index] == nil {
            representedPatternsByIndex[pattern.index] = pattern
        }
        let representedPatternIndices = Set(representedPatternsByIndex.keys)
        let usedPatternIndices = Set(effectiveOrder.filter { representedPatternIndices.contains($0) })

        // Editable pattern existence is document structure, independent of whether cells are empty.
        entries = representedPatternsByIndex.keys.sorted().compactMap { patternIndex in
            guard let pattern = representedPatternsByIndex[patternIndex] else {
                return nil
            }
            return ModuleMetadataLoader.PatternSelectionEntry(
                patternIndex: patternIndex,
                isUsed: usedPatternIndices.contains(patternIndex),
                rowCount: max(1, pattern.rowCount)
            )
        }
        invalidReferencedPatterns = effectiveOrder.filter { !representedPatternIndices.contains($0) }
        selectedEntryIndex = entries.firstIndex {
            $0.patternIndex == document.currentPatternIndex
        }
    }
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
        hasDocumentState: false,
        isOrderMutationEnabled: false,
        isPatternMutationEnabled: false,
        isClearSongEnabled: false
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
    let isOrderMutationEnabled: Bool
    let isPatternMutationEnabled: Bool
    let isClearSongEnabled: Bool

    var isDuplicateSelectedOrderEnabled: Bool {
        isOrderMutationEnabled && selectedOrderPosition != nil
    }

    var isDuplicateCurrentPatternEnabled: Bool {
        isPatternMutationEnabled && selectedPatternIndex != nil
    }

    var isClearCurrentPatternEnabled: Bool {
        isPatternMutationEnabled && selectedPatternIndex != nil
    }

    var isMoveSelectedOrderUpEnabled: Bool {
        guard isOrderMutationEnabled,
              let selectedOrderPosition else {
            return false
        }
        return selectedOrderPosition > 0
    }

    var isMoveSelectedOrderDownEnabled: Bool {
        guard isOrderMutationEnabled,
              let selectedOrderPosition else {
            return false
        }
        return selectedOrderPosition < orderRows.count - 1
    }

    var isStepSelectedOrderPatternDownEnabled: Bool {
        isSelectedOrderPatternStepEnabled(direction: -1)
    }

    var isStepSelectedOrderPatternUpEnabled: Bool {
        isSelectedOrderPatternStepEnabled(direction: 1)
    }

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
            hasDocumentState: true,
            isOrderMutationEnabled: false
        )
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        requestedBankIndex: Int? = nil,
        isOrderMutationEnabled: Bool = true,
        isClearSongEnabled: Bool? = nil
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
            hasDocumentState: true,
            isOrderMutationEnabled: isOrderMutationEnabled,
            isClearSongEnabled: isClearSongEnabled ?? isOrderMutationEnabled
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
            hasDocumentState: hasDocumentState,
            isOrderMutationEnabled: isOrderMutationEnabled,
            isPatternMutationEnabled: isPatternMutationEnabled,
            isClearSongEnabled: isClearSongEnabled
        )
    }

    func withClearSongEnabled(_ isEnabled: Bool) -> SongOrderEditorDisplayState {
        SongOrderEditorDisplayState(
            orderRows: orderRows,
            patternBankCells: patternBankCells,
            bankRangeLabel: bankRangeLabel,
            bankDisplayLabel: bankDisplayLabel,
            bankIndex: bankIndex,
            totalBankCount: totalBankCount,
            existingPatternIndices: existingPatternIndices,
            usedPatternIndices: usedPatternIndices,
            selectedOrderPosition: selectedOrderPosition,
            selectedPatternIndex: selectedPatternIndex,
            hasDocumentState: hasDocumentState,
            isOrderMutationEnabled: isOrderMutationEnabled,
            isPatternMutationEnabled: isPatternMutationEnabled,
            isClearSongEnabled: isEnabled
        )
    }

    private static func make(
        orderPatternIndices: [Int],
        rowCountsByPatternIndex: [Int: Int],
        existingPatternIndices: Set<Int>,
        selectedOrderPosition: Int,
        currentPatternIndex: Int?,
        requestedBankIndex: Int? = nil,
        hasDocumentState: Bool,
        isOrderMutationEnabled: Bool,
        isClearSongEnabled: Bool = false
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
        let currentPatternExists = currentPatternIndex.map { existingPatternIndices.contains($0) } ?? false
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
            hasDocumentState: hasDocumentState,
            isOrderMutationEnabled: isOrderMutationEnabled && selected != nil,
            isPatternMutationEnabled: isOrderMutationEnabled && currentPatternExists,
            isClearSongEnabled: isClearSongEnabled
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

    private func isSelectedOrderPatternStepEnabled(direction: Int) -> Bool {
        guard isOrderMutationEnabled,
              direction != 0,
              let selectedOrderPatternIndex = orderRows.first(where: \.isSelected)?.patternIndex,
              existingPatternIndices.contains(selectedOrderPatternIndex) else {
            return false
        }
        if direction < 0 {
            return existingPatternIndices.contains { $0 < selectedOrderPatternIndex }
        }
        return existingPatternIndices.contains { $0 > selectedOrderPatternIndex }
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
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.selectPatternForViewing(patternIndex) else { return nil }
        return updatedDocument
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        assigningPatternIndexToSelectedOrder patternIndex: Int,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.assignPatternToSelectedOrder(patternIndex) else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentCreatingBlankPatternForEditing(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.createBlankPatternAndSelectForEditing() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentDuplicatingCurrentPatternForEditing(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.duplicateCurrentPatternForEditing() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentClearingCurrentPatternForEditing(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.clearCurrentPattern() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentInsertingOrderAfterSelected(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.insertOrderAfterSelected() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentDeletingSelectedOrder(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.deleteSelectedOrder() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentDuplicatingSelectedOrder(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.duplicateSelectedOrder() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentMovingSelectedOrderUp(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.moveSelectedOrderUp() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentMovingSelectedOrderDown(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.moveSelectedOrderDown() else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocumentSteppingSelectedOrderPattern(
        _ document: BlankTrackerDocument,
        delta: Int,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.stepSelectedOrderPattern(delta: delta) else {
            return nil
        }
        return updatedDocument
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        selectingOrderPosition orderPosition: Int,
        isPlaybackActive: Bool
    ) -> BlankTrackerDocument? {
        guard !isPlaybackActive else {
            return nil
        }
        var updatedDocument = document
        guard updatedDocument.selectOrderPositionForNavigation(orderPosition) else { return nil }
        return updatedDocument
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
    static func currentPatternLoopContext(
        editableDocument document: BlankTrackerDocument
    ) -> PlaybackStartContext? {
        currentPatternLoopContext(
            metadata: document.metadata,
            selectedSongPositionIndex: document.currentPosition,
            displayedPatternIndex: document.currentPatternIndex
        )
    }

    static func currentPatternLoopContext(
        metadata: ParsedModuleMetadata,
        selectedSongPositionIndex: Int,
        displayedPatternIndex: Int
    ) -> PlaybackStartContext? {
        guard metadata.xmPattern(index: displayedPatternIndex) != nil else {
            return nil
        }
        let orderCount = min(max(0, metadata.songLength), metadata.orderTable.count)
        let orderPosition = orderCount > 0
            ? min(max(0, selectedSongPositionIndex), orderCount - 1)
            : max(0, selectedSongPositionIndex)
        return PlaybackStartContext(
            moduleTitle: metadata.title.isEmpty ? nil : metadata.title,
            songPosition: orderPosition,
            patternIndex: displayedPatternIndex,
            row: 0
        )
    }

    static func normalPlayContext(
        editableDocument document: BlankTrackerDocument,
        row: Int
    ) -> PlaybackStartContext {
        normalPlayContext(
            metadata: document.metadata,
            selectedSongPositionIndex: document.currentPosition,
            displayedPatternIndex: document.currentPatternIndex,
            row: row
        )
    }

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

enum TrackerTransportCommandAvailability {
    static func canPlayCurrentPattern(
        metadata: ParsedModuleMetadata?,
        currentPatternIndex: Int,
        isPlaybackActive: Bool
    ) -> Bool {
        guard !isPlaybackActive,
              let metadata else {
            return false
        }
        return metadata.xmPattern(index: currentPatternIndex) != nil
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
    var onPatternDoubleClickedForAssignment: ((Int) -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onPatternDoubleClickedForAssignment = onPatternDoubleClickedForAssignment
        }
    }
    var onNewPatternRequested: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onNewPatternRequested = onNewPatternRequested
        }
    }
    var onDuplicateCurrentPattern: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onDuplicateCurrentPattern = onDuplicateCurrentPattern
        }
    }
    var onClearCurrentPattern: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onClearCurrentPattern = onClearCurrentPattern
        }
    }
    var onInsertOrderAfterSelected: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onInsertOrderAfterSelected = onInsertOrderAfterSelected
        }
    }
    var onDeleteSelectedOrder: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onDeleteSelectedOrder = onDeleteSelectedOrder
        }
    }
    var onDuplicateSelectedOrder: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onDuplicateSelectedOrder = onDuplicateSelectedOrder
        }
    }
    var onMoveSelectedOrderUp: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onMoveSelectedOrderUp = onMoveSelectedOrderUp
        }
    }
    var onMoveSelectedOrderDown: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onMoveSelectedOrderDown = onMoveSelectedOrderDown
        }
    }
    var onStepSelectedOrderPattern: ((Int) -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onStepSelectedOrderPattern = onStepSelectedOrderPattern
        }
    }
    var onClearSongRequested: (() -> Void)? {
        didSet {
            (window?.contentView as? SongOrderEditorContentView)?.onClearSongRequested = onClearSongRequested
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
        contentView.onPatternDoubleClickedForAssignment = onPatternDoubleClickedForAssignment
        contentView.onNewPatternRequested = onNewPatternRequested
        contentView.onDuplicateCurrentPattern = onDuplicateCurrentPattern
        contentView.onClearCurrentPattern = onClearCurrentPattern
        contentView.onInsertOrderAfterSelected = onInsertOrderAfterSelected
        contentView.onDeleteSelectedOrder = onDeleteSelectedOrder
        contentView.onDuplicateSelectedOrder = onDuplicateSelectedOrder
        contentView.onMoveSelectedOrderUp = onMoveSelectedOrderUp
        contentView.onMoveSelectedOrderDown = onMoveSelectedOrderDown
        contentView.onStepSelectedOrderPattern = onStepSelectedOrderPattern
        contentView.onClearSongRequested = onClearSongRequested
        return contentView.apply(displayState: displayState)
    }

    @discardableResult
    func applyIfVisible(displayState: SongOrderEditorDisplayState) -> Bool {
        guard isVisibleForRefresh else {
            return false
        }
        return apply(displayState: displayState)
    }

    @discardableResult
    func applyClearSongAvailability(_ isEnabled: Bool) -> Bool {
        guard isVisibleForRefresh,
              let contentView = window?.contentView as? SongOrderEditorContentView else { return false }
        return contentView.applyClearSongAvailability(isEnabled)
    }

    func windowWillClose(_ notification: Notification) {
        closeHandler?()
    }
}

@MainActor
final class SongOrderEditorContentView: FlippedEditorView {
    var onOrderSelected: ((Int) -> Void)?
    var onPatternSelected: ((Int) -> Void)?
    var onPatternDoubleClickedForAssignment: ((Int) -> Void)?
    var onNewPatternRequested: (() -> Void)?
    var onDuplicateCurrentPattern: (() -> Void)?
    var onClearCurrentPattern: (() -> Void)?
    var onInsertOrderAfterSelected: (() -> Void)?
    var onDeleteSelectedOrder: (() -> Void)?
    var onDuplicateSelectedOrder: (() -> Void)?
    var onMoveSelectedOrderUp: (() -> Void)?
    var onMoveSelectedOrderDown: (() -> Void)?
    var onStepSelectedOrderPattern: ((Int) -> Void)?
    var onClearSongRequested: (() -> Void)?
    private(set) var displayState: SongOrderEditorDisplayState
    private(set) var rebuildCount = 0
    private(set) var selectedOrderScrollCount = 0
    private let usedPatternFill = NSColor(srgbRed: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x10 / 255.0, alpha: 1.0)
    private var lastScrolledSelectedOrderPosition: Int?
    private weak var clearSongButton: NSButton?

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

    @discardableResult
    func applyClearSongAvailability(_ isEnabled: Bool) -> Bool {
        guard displayState.isClearSongEnabled != isEnabled else { return false }
        displayState = displayState.withClearSongEnabled(isEnabled)
        clearSongButton?.isEnabled = isEnabled
        clearSongButton?.target = isEnabled ? self : nil
        clearSongButton?.action = isEnabled ? #selector(clearSong(_:)) : nil
        clearSongButton?.sendAction(on: isEnabled ? .leftMouseUp : [])
        clearSongButton?.toolTip = isEnabled ? "Clear song/order/pattern data" : "Clear song unavailable"
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

    @objc
    private func insertOrderAfterSelected(_ sender: Any?) {
        guard displayState.isOrderMutationEnabled else {
            return
        }
        onInsertOrderAfterSelected?()
    }

    @objc
    private func deleteSelectedOrder(_ sender: Any?) {
        guard displayState.isOrderMutationEnabled else {
            return
        }
        onDeleteSelectedOrder?()
    }

    @objc
    private func duplicateSelectedOrder(_ sender: Any?) {
        guard displayState.isDuplicateSelectedOrderEnabled else {
            return
        }
        onDuplicateSelectedOrder?()
    }

    @objc
    private func moveSelectedOrderUp(_ sender: Any?) {
        guard displayState.isMoveSelectedOrderUpEnabled else {
            return
        }
        onMoveSelectedOrderUp?()
    }

    @objc
    private func moveSelectedOrderDown(_ sender: Any?) {
        guard displayState.isMoveSelectedOrderDownEnabled else {
            return
        }
        onMoveSelectedOrderDown?()
    }

    @objc
    private func stepSelectedOrderPatternDown(_ sender: Any?) {
        guard displayState.isStepSelectedOrderPatternDownEnabled else {
            return
        }
        onStepSelectedOrderPattern?(-1)
    }

    @objc
    private func stepSelectedOrderPatternUp(_ sender: Any?) {
        guard displayState.isStepSelectedOrderPatternUpEnabled else {
            return
        }
        onStepSelectedOrderPattern?(1)
    }

    @objc
    private func createNewPattern(_ sender: Any?) {
        guard displayState.isPatternMutationEnabled else {
            return
        }
        onNewPatternRequested?()
    }

    @objc
    private func duplicateCurrentPattern(_ sender: Any?) {
        guard displayState.isDuplicateCurrentPatternEnabled else {
            return
        }
        onDuplicateCurrentPattern?()
    }

    @objc
    private func clearCurrentPattern(_ sender: Any?) {
        guard displayState.isClearCurrentPatternEnabled else {
            return
        }
        onClearCurrentPattern?()
    }

    @objc
    private func clearSong(_ sender: Any?) {
        guard displayState.isClearSongEnabled else {
            return
        }
        onClearSongRequested?()
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
        let requestsNavigation = !rowState.isSelected ||
            (displayState.isOrderMutationEnabled && rowState.patternIndex != displayState.selectedPatternIndex)
        let row = SongOrderEditorOrderRowView(
            orderPosition: rowState.orderPosition,
            requestsNavigation: requestsNavigation
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
        } assignmentHandler: { [weak self] patternIndex in
            self?.onPatternDoubleClickedForAssignment?(patternIndex)
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
        addButton(
            "+ NEW",
            to: panel,
            frame: NSRect(x: 10, y: 29, width: 68, height: 25),
            target: displayState.isPatternMutationEnabled ? self : nil,
            action: displayState.isPatternMutationEnabled ? #selector(createNewPattern(_:)) : nil,
            isEnabled: displayState.isPatternMutationEnabled,
            toolTip: displayState.isPatternMutationEnabled ? "Create blank pattern for editing" : "New pattern unavailable"
        )
        addButton(
            "⧉ DUP",
            to: panel,
            frame: NSRect(x: 84, y: 29, width: 68, height: 25),
            target: displayState.isDuplicateCurrentPatternEnabled ? self : nil,
            action: displayState.isDuplicateCurrentPatternEnabled ? #selector(duplicateCurrentPattern(_:)) : nil,
            isEnabled: displayState.isDuplicateCurrentPatternEnabled,
            toolTip: displayState.isDuplicateCurrentPatternEnabled ? "Duplicate current pattern without assigning it to the song" : "Pattern duplicate unavailable"
        )
        addButton(
            "⌫ CLEAR",
            to: panel,
            frame: NSRect(x: 158, y: 29, width: 84, height: 25),
            target: displayState.isClearCurrentPatternEnabled ? self : nil,
            action: displayState.isClearCurrentPatternEnabled ? #selector(clearCurrentPattern(_:)) : nil,
            isEnabled: displayState.isClearCurrentPatternEnabled,
            toolTip: displayState.isClearCurrentPatternEnabled ? "Clear current pattern data" : "Pattern clear unavailable"
        )
    }

    private func buildOrderOpsPanel(_ panel: NSView) {
        var x: CGFloat = 10
        addButton(
            "+ INSERT",
            to: panel,
            frame: NSRect(x: x, y: 31, width: 84, height: 25),
            target: displayState.isOrderMutationEnabled ? self : nil,
            action: displayState.isOrderMutationEnabled ? #selector(insertOrderAfterSelected(_:)) : nil,
            isEnabled: displayState.isOrderMutationEnabled,
            toolTip: displayState.isOrderMutationEnabled ? "Insert order slot after selected slot" : "Order insert unavailable"
        )
        x += 90
        addButton(
            "⌫ DELETE",
            to: panel,
            frame: NSRect(x: x, y: 31, width: 84, height: 25),
            target: displayState.isOrderMutationEnabled ? self : nil,
            action: displayState.isOrderMutationEnabled ? #selector(deleteSelectedOrder(_:)) : nil,
            isEnabled: displayState.isOrderMutationEnabled,
            toolTip: displayState.isOrderMutationEnabled ? "Delete selected order slot" : "Order delete unavailable"
        )
        x += 90
        addButton(
            "⧉ DUP",
            to: panel,
            frame: NSRect(x: x, y: 31, width: 66, height: 25),
            target: displayState.isDuplicateSelectedOrderEnabled ? self : nil,
            action: displayState.isDuplicateSelectedOrderEnabled ? #selector(duplicateSelectedOrder(_:)) : nil,
            isEnabled: displayState.isDuplicateSelectedOrderEnabled,
            toolTip: displayState.isDuplicateSelectedOrderEnabled ? "Duplicate selected order slot" : "Order duplicate unavailable"
        )
        x += 72
        x += 10
        addSeparator(to: panel, x: x, y: 34)
        x += 18
        let moveUpEnabled = displayState.isMoveSelectedOrderUpEnabled
        addButton(
            "▲ MOVE UP",
            to: panel,
            frame: NSRect(x: x, y: 31, width: 94, height: 25),
            target: moveUpEnabled ? self : nil,
            action: moveUpEnabled ? #selector(moveSelectedOrderUp(_:)) : nil,
            isEnabled: moveUpEnabled,
            toolTip: moveUpEnabled ? "Move selected order slot up" : "Order move up unavailable"
        )
        x += 100
        let moveDownEnabled = displayState.isMoveSelectedOrderDownEnabled
        addButton(
            "▼ MOVE DOWN",
            to: panel,
            frame: NSRect(x: x, y: 31, width: 108, height: 25),
            target: moveDownEnabled ? self : nil,
            action: moveDownEnabled ? #selector(moveSelectedOrderDown(_:)) : nil,
            isEnabled: moveDownEnabled,
            toolTip: moveDownEnabled ? "Move selected order slot down" : "Order move down unavailable"
        )
        x += 114
        x += 12
        addSeparator(to: panel, x: x, y: 34)
        x += 24
        addLabel("PTN", to: panel, frame: NSRect(x: x, y: 37, width: 24, height: 14), color: VTXEditorControlTheme.accentGold, size: 9, weight: .bold)
        let stepDownEnabled = displayState.isStepSelectedOrderPatternDownEnabled
        addButton(
            "-",
            to: panel,
            frame: NSRect(x: x + 25, y: 31, width: 28, height: 25),
            target: stepDownEnabled ? self : nil,
            action: stepDownEnabled ? #selector(stepSelectedOrderPatternDown(_:)) : nil,
            isEnabled: stepDownEnabled,
            toolTip: stepDownEnabled ? "Assign previous allocated pattern to selected order slot" : "Previous allocated pattern unavailable"
        )
        let stepUpEnabled = displayState.isStepSelectedOrderPatternUpEnabled
        addButton(
            "+",
            to: panel,
            frame: NSRect(x: x + 57, y: 31, width: 28, height: 25),
            target: stepUpEnabled ? self : nil,
            action: stepUpEnabled ? #selector(stepSelectedOrderPatternUp(_:)) : nil,
            isEnabled: stepUpEnabled,
            toolTip: stepUpEnabled ? "Assign next allocated pattern to selected order slot" : "Next allocated pattern unavailable"
        )
    }

    private func buildDangerPanel(_ panel: NSView) {
        clearSongButton = addButton(
            "⌫ CLEAR SONG",
            to: panel,
            frame: NSRect(x: 10, y: 12, width: 124, height: 25),
            role: .danger,
            target: displayState.isClearSongEnabled ? self : nil,
            action: displayState.isClearSongEnabled ? #selector(clearSong(_:)) : nil,
            isEnabled: displayState.isClearSongEnabled,
            toolTip: displayState.isClearSongEnabled ? "Clear song/order/pattern data" : "Clear song unavailable"
        )
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

    @discardableResult
    private func addButton(
        _ title: String,
        to parent: NSView,
        frame: NSRect,
        role: VTXEditorButtonRole = .normal,
        target: AnyObject? = nil,
        action: Selector? = nil,
        isEnabled: Bool = true,
        toolTip: String = "Inactive shell control"
    ) -> VTXEditorButton {
        let button = VTXEditorControlFactory.makeButton(title: title, role: role, fixedWidth: frame.width)
        button.isEnabled = isEnabled
        button.target = target
        button.action = action
        if action == nil {
            button.sendAction(on: [])
        }
        button.toolTip = toolTip
        addControl(button, to: parent, frame: frame)
        return button
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
    private let requestsNavigation: Bool
    private let selectHandler: (Int) -> Void

    init(orderPosition: Int, requestsNavigation: Bool, selectHandler: @escaping (Int) -> Void) {
        self.orderPosition = orderPosition
        self.requestsNavigation = requestsNavigation
        self.selectHandler = selectHandler
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard requestsNavigation else {
            return
        }
        selectHandler(orderPosition)
    }
}

final class SongOrderEditorPatternCellView: FlippedEditorView {
    private let patternIndex: Int
    private let isClickable: Bool
    private let selectHandler: (Int) -> Void
    private let assignmentHandler: (Int) -> Void

    init(
        patternIndex: Int,
        isClickable: Bool,
        selectHandler: @escaping (Int) -> Void,
        assignmentHandler: @escaping (Int) -> Void
    ) {
        self.patternIndex = patternIndex
        self.isClickable = isClickable
        self.selectHandler = selectHandler
        self.assignmentHandler = assignmentHandler
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
        guard event.clickCount < 2 else {
            assignmentHandler(patternIndex)
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
