import AppKit
import XCTest

@MainActor
final class EditableDocumentEditCoordinatorTests: XCTestCase {
    func testLoadedReadOnlyContextCannotApplyOrUseStaleUndoHistory() {
        let before = BlankTrackerDocument.makeDefault()
        var edited = before
        XCTAssertTrue(edited.enterNote(trackerKey: "q", octave: 4, row: 0, channel: 0))
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        XCTAssertTrue(harness.coordinator.applyEdit(label: "Enter Note", updatedDocument: edited))
        harness.context = .loadedReadOnly
        XCTAssertFalse(harness.coordinator.applyEdit(label: "Blocked Edit", updatedDocument: .makeDefault()))
        XCTAssertFalse(harness.coordinator.canUndo)
        XCTAssertFalse(harness.coordinator.undo())
        XCTAssertEqual(harness.appliedDocuments, [edited])
    }

    func testPlaybackActiveEditableContextKeepsMutationPolicyBlocked() {
        let before = documentWithInstrumentName("Before")
        var edited = before
        XCTAssertTrue(edited.enterNote(trackerKey: "q", octave: 4, row: 0, channel: 0))
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: true))
        XCTAssertFalse(harness.coordinator.applyEdit(label: "Enter Note", updatedDocument: edited))
        XCTAssertFalse(harness.coordinator.renameInstrument(at: 0, name: "Blocked Rename"))
        XCTAssertTrue(harness.appliedDocuments.isEmpty)
    }

    func testEditContextCannotCarryOrClaimSourcePathOwnership() {
        let editable = EditableDocumentEditContext.editable(document: .makeDefault(), isPlaybackActive: false)
        let loadedReadOnly = EditableDocumentEditContext.loadedReadOnly
        XCTAssertFalse(containsURL(in: editable))
        XCTAssertEqual(Mirror(reflecting: loadedReadOnly).children.count, 0)
    }

    func testClearCurrentPatternBehaviorIsUnchangedAndRoundTripsThroughUndo() {
        var before = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(before.enterNote(trackerKey: "q", octave: 4, row: 0, channel: 0))
        let preservedPalette = before.instrumentPalette
        var cleared = before
        XCTAssertTrue(cleared.clearCurrentPattern())
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        XCTAssertTrue(harness.coordinator.applyEdit(label: "Clear Current Pattern", updatedDocument: cleared))
        XCTAssertEqual(harness.editableDocument?.pattern.rows[0][0], .empty)
        XCTAssertEqual(harness.editableDocument?.instrumentPalette, preservedPalette)
        XCTAssertEqual(harness.appliedDocuments, [cleared])
        XCTAssertEqual(harness.undoManager.levelsOfUndo, EditableDocumentEditCoordinator.defaultLevelsOfUndo)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Clear Current Pattern")
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Clear Current Pattern")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, cleared)
        XCTAssertEqual(harness.appliedDocuments, [cleared, before, cleared])
    }

    func testInstrumentRenameAppliesThroughUndoRedoAndRefreshesExistingDisplays() throws {
        let before = documentWithInstrumentName("Snapshot")
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: { controller.apply(displayState: .editableDocument($0)) }
        )

        XCTAssertTrue(harness.coordinator.renameInstrument(at: 0, name: "Renamed"))
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Renamed")
        XCTAssertEqual(harness.editableDocument?.controlPanelMetadata.selectedInstrumentDisplay, "I01 Renamed")
        XCTAssertEqual(view.displayState.instrumentName, "Renamed")
        XCTAssertTrue(view.displayState.isInstrumentNameEditable)
        XCTAssertEqual(samplePCMBaseAddress(in: before), samplePCMBaseAddress(in: try XCTUnwrap(harness.editableDocument)))
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Rename Instrument")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Snapshot")
        XCTAssertEqual(harness.editableDocument?.controlPanelMetadata.selectedInstrumentDisplay, "I01 Snapshot")
        XCTAssertEqual(view.displayState.instrumentName, "Snapshot")
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Rename Instrument")

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Renamed")
        XCTAssertEqual(harness.editableDocument?.controlPanelMetadata.selectedInstrumentDisplay, "I01 Renamed")
        XCTAssertEqual(view.displayState.instrumentName, "Renamed")
        XCTAssertEqual(harness.appliedDocuments.count, 3)
    }

    func testInstrumentRenameSanitizesToXMNameConstraintsAndRejectsMissingInstrument() {
        let before = documentWithInstrumentName("Before")
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertTrue(harness.coordinator.renameInstrument(at: 0, name: "  Long\nNámé 12345678901234567890  "))
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Long N?m? 123456789012")
        XCTAssertFalse(harness.coordinator.renameInstrument(at: 1, name: "Missing"))
        XCTAssertEqual(harness.appliedDocuments.count, 1)
    }

    func testLoadedReadOnlyContextCannotRenameInstrumentOrMutateSourceMetadata() {
        let sourceMetadata = PlaybackInstrument(
            index: 1,
            name: "Loaded Source",
            samples: []
        )
        let sourceBefore = sourceMetadata
        let harness = EditHarness(context: .loadedReadOnly)

        XCTAssertFalse(harness.coordinator.renameInstrument(at: 0, name: "Blocked Rename"))
        XCTAssertEqual(sourceMetadata, sourceBefore)
        XCTAssertEqual(sourceMetadata.name, "Loaded Source")
        XCTAssertTrue(harness.appliedDocuments.isEmpty)
        XCTAssertFalse(containsURL(in: harness.context))
    }
}

@MainActor
private final class EditHarness {
    var context: EditableDocumentEditContext
    private(set) var appliedDocuments: [BlankTrackerDocument] = []
    let undoManager = UndoManager()
    private let onApply: (BlankTrackerDocument) -> Void

    lazy var coordinator = EditableDocumentEditCoordinator(
        undoManager: undoManager,
        contextProvider: { [unowned self] in context },
        documentApplyHandler: { [unowned self] document in
            context = .editable(document: document, isPlaybackActive: false)
            appliedDocuments.append(document)
            onApply(document)
        }
    )

    init(context: EditableDocumentEditContext, onApply: @escaping (BlankTrackerDocument) -> Void = { _ in }) {
        self.context = context
        self.onApply = onApply
    }

    var editableDocument: BlankTrackerDocument? { context.editableDocument }
}

private func containsURL(in value: Any, remainingDepth: Int = 16) -> Bool {
    if value is URL { return true }
    guard remainingDepth > 0 else { return false }
    return Mirror(reflecting: value).children.contains {
        containsURL(in: $0.value, remainingDepth: remainingDepth - 1)
    }
}

private func documentWithInstrumentName(_ name: String) -> BlankTrackerDocument {
    let base = BlankTrackerDocument.makeDefault()
    let sample = PlaybackSample(
        instrumentIndex: 1,
        sampleIndex: 0,
        pcm: [0, 0.5, -0.5],
        volume: 1,
        relativeNote: 0,
        finetune: 0,
        baseSampleRate: 8_363
    )
    let instrument = PlaybackInstrument(index: 1, name: name, samples: [sample])
    return BlankTrackerDocument(
        title: base.title,
        songLength: base.songLength,
        currentPosition: base.currentPosition,
        restartPosition: base.restartPosition,
        currentPatternIndex: base.currentPatternIndex,
        tempo: base.tempo,
        speed: base.speed,
        orderTable: base.orderTable,
        selection: base.selection,
        instrumentPalette: [1: instrument],
        patterns: base.patterns
    )
}

private func samplePCMBaseAddress(in document: BlankTrackerDocument) -> UInt? {
    guard let pcm = document.instrumentPalette[1]?.samples.first?.pcm else { return nil }
    return pcm.withUnsafeBufferPointer { buffer in
        buffer.baseAddress.map { UInt(bitPattern: $0) }
    }
}
