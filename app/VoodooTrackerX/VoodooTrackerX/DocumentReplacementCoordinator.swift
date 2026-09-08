import AppKit

extension BlankTrackerDocument {
    /// Compares authored song content with the canonical File-New baseline.
    /// Navigation and editor selection are session/view state and are intentionally ignored.
    var hasDiscardableEditableContent: Bool {
        let pristine = Self.makeDefault()
        return title != pristine.title ||
            songLength != pristine.songLength ||
            restartPosition != pristine.restartPosition ||
            tempo != pristine.tempo ||
            speed != pristine.speed ||
            orderTable != pristine.orderTable ||
            instrumentPalette != pristine.instrumentPalette ||
            patterns != pristine.patterns
    }
}

enum DocumentReplacementAction: Equatable {
    case newDocument
    case openModule
}

enum DocumentReplacementSource: Equatable {
    case none
    case editable(
        documentIdentity: UUID?,
        documentRevision: UInt64,
        document: BlankTrackerDocument
    )
    case loadedReadOnly
}

struct DocumentReplacementContext: Equatable {
    let source: DocumentReplacementSource
    let hasConflictingDocumentPresentation: Bool

    fileprivate func decision(for action: DocumentReplacementAction) -> DocumentReplacementDecision {
        guard !hasConflictingDocumentPresentation else { return .reject }
        guard case let .editable(documentIdentity, documentRevision, document) = source,
              document.hasDiscardableEditableContent else {
            return .proceedWithoutConfirmation
        }
        guard let documentIdentity else { return .reject }
        return .requireConfirmation(DocumentReplacementTarget(
            action: action,
            documentIdentity: documentIdentity,
            documentRevision: documentRevision,
            document: document
        ))
    }
}

private enum DocumentReplacementDecision: Equatable {
    case proceedWithoutConfirmation
    case requireConfirmation(DocumentReplacementTarget)
    case reject
}

private struct DocumentReplacementTarget: Equatable {
    let action: DocumentReplacementAction
    let documentIdentity: UUID
    let documentRevision: UInt64
    let document: BlankTrackerDocument

    func isCurrent(in context: DocumentReplacementContext) -> Bool {
        context.decision(for: action) == .requireConfirmation(self)
    }
}

struct DocumentReplacementRequest: Equatable {
    let operationToken: UUID
    let action: DocumentReplacementAction
}

enum DocumentReplacementBeginResult: Equatable {
    case performedWithoutConfirmation
    case confirmationRequired(DocumentReplacementRequest)
    case rejected
}

/// Guards only File-New and File-Open replacement of meaningful editable content.
@MainActor
final class DocumentReplacementCoordinator {
    private let contextProvider: () -> DocumentReplacementContext
    private let replacementHandler: (DocumentReplacementAction) -> Void
    private var activeOperation: (
        token: UUID,
        target: DocumentReplacementTarget
    )?

    init(
        contextProvider: @escaping () -> DocumentReplacementContext,
        replacementHandler: @escaping (DocumentReplacementAction) -> Void
    ) {
        self.contextProvider = contextProvider
        self.replacementHandler = replacementHandler
    }

    var isConfirmationActive: Bool { activeOperation != nil }

    @discardableResult
    func begin(_ action: DocumentReplacementAction) -> DocumentReplacementBeginResult {
        guard activeOperation == nil else { return .rejected }
        switch contextProvider().decision(for: action) {
        case .proceedWithoutConfirmation:
            replacementHandler(action)
            return .performedWithoutConfirmation
        case let .requireConfirmation(target):
            let token = UUID()
            activeOperation = (token, target)
            return .confirmationRequired(DocumentReplacementRequest(
                operationToken: token,
                action: action
            ))
        case .reject:
            return .rejected
        }
    }

    @discardableResult
    func cancel(operationToken: UUID) -> Bool {
        guard activeOperation?.token == operationToken else { return false }
        activeOperation = nil
        return true
    }

    @discardableResult
    func confirm(operationToken: UUID) -> Bool {
        guard let activeOperation,
              activeOperation.token == operationToken else { return false }
        defer { self.activeOperation = nil }
        guard activeOperation.target.isCurrent(in: contextProvider()) else { return false }
        replacementHandler(activeOperation.target.action)
        return true
    }
}

@MainActor
enum DocumentReplacementAlert {
    static func make(request: DocumentReplacementRequest) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch request.action {
        case .newDocument:
            alert.messageText = "Start a New Song?"
            alert.informativeText = """
            This will replace the current editable song, including its patterns, instruments, samples, and undo history. This cannot be undone.

            Export XM first if you want to keep a copy.
            """
            alert.addButton(withTitle: "New Song")
            alert.buttons[0].setAccessibilityLabel("Replace the current editable song")
        case .openModule:
            alert.messageText = "Open Another Module?"
            alert.informativeText = """
            Opening another module will replace the current editable song, including its patterns, instruments, samples, and undo history. This cannot be undone.

            Export XM first if you want to keep a copy.
            """
            alert.addButton(withTitle: "Open…")
            alert.buttons[0].setAccessibilityLabel("Choose another module to open")
        }
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert
    }

    static func isConfirmed(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }
}
