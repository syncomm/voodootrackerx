import Foundation

/// Loaded modules carry no editable value or source-path ownership into this boundary.
enum EditableDocumentEditContext: Equatable {
    case none
    case loadedReadOnly
    case editable(document: BlankTrackerDocument, isPlaybackActive: Bool)

    var editableDocument: BlankTrackerDocument? {
        if case let .editable(document, _) = self { return document }
        return nil
    }

    fileprivate var documentAvailableForMutation: BlankTrackerDocument? {
        if case let .editable(document, false) = self { return document }
        return nil
    }
}

/// Applies whole editable-document values and registers reciprocal snapshot undo operations.
@MainActor
final class EditableDocumentEditCoordinator {
    static let defaultLevelsOfUndo = 20

    let undoManager: UndoManager
    private let contextProvider: () -> EditableDocumentEditContext
    private let documentApplyHandler: (BlankTrackerDocument) -> Void

    init(
        undoManager: UndoManager = UndoManager(),
        levelsOfUndo: Int = defaultLevelsOfUndo,
        contextProvider: @escaping () -> EditableDocumentEditContext,
        documentApplyHandler: @escaping (BlankTrackerDocument) -> Void
    ) {
        self.undoManager = undoManager
        self.contextProvider = contextProvider
        self.documentApplyHandler = documentApplyHandler
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = max(1, levelsOfUndo)
    }

    var canUndo: Bool { contextProvider().documentAvailableForMutation != nil && undoManager.canUndo }
    var canRedo: Bool { contextProvider().documentAvailableForMutation != nil && undoManager.canRedo }
    var undoMenuItemTitle: String { undoManager.undoMenuItemTitle }
    var redoMenuItemTitle: String { undoManager.redoMenuItemTitle }

    @discardableResult
    func applyEdit(label: String, updatedDocument: BlankTrackerDocument) -> Bool {
        let actionName = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actionName.isEmpty,
              let before = contextProvider().documentAvailableForMutation,
              before != updatedDocument else {
            return false
        }
        return replaceDocument(with: updatedDocument, replacing: before, actionName: actionName)
    }

    @discardableResult
    func renameInstrument(at zeroBasedIndex: Int, name: String) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.renameInstrument(at: zeroBasedIndex, name: name) else {
            return false
        }
        return applyEdit(label: "Rename Instrument", updatedDocument: document)
    }

    @discardableResult
    func undo() -> Bool {
        guard canUndo else { return false }
        let before = contextProvider().editableDocument
        undoManager.undo()
        return contextProvider().editableDocument != before
    }

    @discardableResult
    func redo() -> Bool {
        guard canRedo else { return false }
        let before = contextProvider().editableDocument
        undoManager.redo()
        return contextProvider().editableDocument != before
    }

    func discardUndoHistory() { undoManager.removeAllActions() }

    @discardableResult
    private func replaceDocument(
        with snapshot: BlankTrackerDocument,
        replacing expectedCurrentDocument: BlankTrackerDocument,
        actionName: String
    ) -> Bool {
        guard contextProvider().documentAvailableForMutation != nil else { return false }

        let opensUndoGroup = !undoManager.isUndoing &&
            !undoManager.isRedoing &&
            undoManager.groupingLevel == 0
        if opensUndoGroup {
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.replaceDocument(
                with: expectedCurrentDocument,
                replacing: snapshot,
                actionName: actionName
            )
        }
        undoManager.setActionName(actionName)
        documentApplyHandler(snapshot)
        if opensUndoGroup {
            undoManager.endUndoGrouping()
        }
        return true
    }
}
