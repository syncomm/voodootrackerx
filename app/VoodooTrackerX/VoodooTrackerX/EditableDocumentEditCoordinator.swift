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
    var canCreateInstrument: Bool {
        contextProvider().documentAvailableForMutation?.canAddEmptyInstrument == true
    }
    var canGenerateSineSample: Bool {
        contextProvider().documentAvailableForMutation?.canGenerateSineInSelectedEmptySample == true
    }
    var canImportAudioSample: Bool {
        contextProvider().documentAvailableForMutation?.selectedSampleImportDestination != nil
    }
    var canClearSelectedSample: Bool {
        guard let document = contextProvider().documentAvailableForMutation else { return false }
        return document.representedSampleForClear(
            instrumentAt: document.selection.selectedInstrument - 1,
            sampleAt: document.selection.selectedSample - 1
        ) != nil
    }
    var canDuplicateSelectedSample: Bool {
        contextProvider().documentAvailableForMutation?.canDuplicateSelectedSample == true
    }

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
    func createInstrument() -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.addEmptyInstrument() != nil else {
            return false
        }
        return applyEdit(label: "New Instrument", updatedDocument: document)
    }

    @discardableResult
    func generateSineSample() -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.generateSineInSelectedEmptySample() else {
            return false
        }
        return applyEdit(label: "Generate Sine Sample", updatedDocument: document)
    }

    @discardableResult
    func importAudioSample(
        _ candidate: NormalizedSampleImport,
        destination: SampleImportDestination
    ) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.importAudioSample(candidate, destination: destination) else { return false }
        let label = destination.requiresReplacementConfirmation
            ? "Replace Audio Sample"
            : "Import Audio Sample"
        return applyEdit(label: label, updatedDocument: document)
    }

    @discardableResult
    func addAudioSample(
        _ candidate: NormalizedSampleImport,
        instrumentIndex: Int,
        originalSampleCount: Int
    ) -> Bool {
        guard candidate.isValidDocumentSample,
              var document = contextProvider().documentAvailableForMutation,
              case let .represented(selectedInstrumentIndex, _) = document.selectedSampleImportDestination,
              selectedInstrumentIndex == instrumentIndex,
              document.instrument(forInstrument: instrumentIndex)?.samples.count == originalSampleCount,
              let sampleIndex = document.nextAppendSampleIndex(forInstrument: instrumentIndex),
              document.appendSample(
                  instrumentIndex: instrumentIndex,
                  sample: candidate.playbackSample(instrumentIndex: instrumentIndex, sampleIndex: sampleIndex)
              ) == sampleIndex else { return false }
        return applyEdit(label: "Add Audio Sample", updatedDocument: document)
    }

    /// Clears one exact selected stable sample identity as a single undoable edit.
    @discardableResult
    func clearSample(
        instrumentAt zeroBasedInstrumentIndex: Int,
        sampleAt zeroBasedSampleIndex: Int
    ) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.clearSample(
                  instrumentAt: zeroBasedInstrumentIndex,
                  sampleAt: zeroBasedSampleIndex
              ) else {
            return false
        }
        return applyEdit(label: "Clear Sample", updatedDocument: document)
    }

    /// Clears the editable song/order state as one whole-document undoable edit.
    @discardableResult
    func clearSongData() -> Bool {
        guard var document = contextProvider().documentAvailableForMutation else {
            return false
        }
        document.clearSongData()
        return applyEdit(label: "Clear Song Data", updatedDocument: document)
    }

    /// Duplicates one exact selected sample as a single undoable tail append.
    @discardableResult
    func duplicateSample(
        instrumentAt zeroBasedInstrumentIndex: Int,
        sampleAt zeroBasedSampleIndex: Int
    ) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.duplicateSample(
                  instrumentAt: zeroBasedInstrumentIndex,
                  sampleAt: zeroBasedSampleIndex
              ) != nil else {
            return false
        }
        return applyEdit(label: "Duplicate Sample", updatedDocument: document)
    }

    /// Applies one canonical sample-slot identity permutation as a whole-document edit.
    @discardableResult
    func applySampleSlotPermutation(
        _ permutation: SampleSlotPermutation,
        instrumentAt zeroBasedInstrumentIndex: Int
    ) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.applySampleSlotPermutation(
                  permutation,
                  instrumentAt: zeroBasedInstrumentIndex
              ) else {
            return false
        }
        return applyEdit(label: "Reorder Samples", updatedDocument: document)
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
    func setSampleVolume(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, volume: UInt8) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.selection.selectedInstrument == zeroBasedInstrumentIndex + 1,
              document.selection.selectedSample == zeroBasedSampleIndex + 1,
              document.setSampleVolume(
                  instrumentAt: zeroBasedInstrumentIndex,
                  sampleAt: zeroBasedSampleIndex,
                  volume: volume
              ) else {
            return false
        }
        return applyEdit(label: "Change Sample Volume", updatedDocument: document)
    }

    @discardableResult
    func setSampleRelativeNote(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, relativeNote: Int) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.selection.selectedInstrument == zeroBasedInstrumentIndex + 1,
              document.selection.selectedSample == zeroBasedSampleIndex + 1,
              document.setSampleRelativeNote(
                  instrumentAt: zeroBasedInstrumentIndex,
                  sampleAt: zeroBasedSampleIndex,
                  relativeNote: relativeNote
              ) else {
            return false
        }
        return applyEdit(label: "Change Sample Relative Note", updatedDocument: document)
    }

    @discardableResult
    func setSampleFinetune(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, finetune: Int) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.selection.selectedInstrument == zeroBasedInstrumentIndex + 1,
              document.selection.selectedSample == zeroBasedSampleIndex + 1,
              document.setSampleFinetune(
                  instrumentAt: zeroBasedInstrumentIndex,
                  sampleAt: zeroBasedSampleIndex,
                  finetune: finetune
              ) else {
            return false
        }
        return applyEdit(label: "Change Sample Finetune", updatedDocument: document)
    }

    @discardableResult
    func setSamplePanning(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, panning: UInt8) -> Bool {
        guard var document = contextProvider().documentAvailableForMutation,
              document.selection.selectedInstrument == zeroBasedInstrumentIndex + 1,
              document.selection.selectedSample == zeroBasedSampleIndex + 1,
              document.setSamplePanning(
                  instrumentAt: zeroBasedInstrumentIndex,
                  sampleAt: zeroBasedSampleIndex,
                  panning: panning
              ) else {
            return false
        }
        return applyEdit(label: "Change Sample Panning", updatedDocument: document)
    }

    /// Maps one represented sample to an inclusive zero-based XM note range in one undoable edit.
    @discardableResult
    func mapSampleToNoteRange(
        instrumentIndex: Int,
        sampleIndex: Int,
        lowerNote: Int,
        upperNote: Int
    ) -> Result<SampleKeymapRangeAssignmentOutcome, SampleKeymapRangeEditFailure> {
        let context = contextProvider()
        switch context {
        case .none:
            return .failure(.noEditableDocument)
        case .loadedReadOnly:
            return .failure(.readOnlyDocument)
        case .editable(_, true):
            return .failure(.playbackActive)
        case var .editable(document, false):
            let result = document.assignSample(
                instrumentIndex: instrumentIndex,
                sampleIndex: sampleIndex,
                lowerNote: lowerNote,
                upperNote: upperNote
            )
            guard case let .success(outcome) = result else { return result }
            guard !outcome.isNoOp else { return result }
            guard applyEdit(
                label: "Map Sample to Note Range",
                updatedDocument: document
            ) else {
                return .failure(.editApplicationRejected)
            }
            return result
        }
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
