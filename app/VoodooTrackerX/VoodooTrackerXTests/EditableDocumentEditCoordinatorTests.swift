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
        XCTAssertTrue(view.selectEnvelopeDisplayMode(.panning))
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: { controller.apply(displayState: .editableDocument($0)) }
        )

        XCTAssertTrue(harness.coordinator.renameInstrument(at: 0, name: "Renamed"))
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Renamed")
        XCTAssertEqual(harness.editableDocument?.controlPanelMetadata.selectedInstrumentDisplay, "I01 Renamed")
        XCTAssertEqual(view.displayState.instrumentName, "Renamed")
        XCTAssertTrue(view.displayState.isInstrumentNameEditable)
        XCTAssertEqual(view.envelopeDisplayMode, .panning)
        XCTAssertEqual(samplePCMBaseAddress(in: before), samplePCMBaseAddress(in: try XCTUnwrap(harness.editableDocument)))
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Rename Instrument")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Snapshot")
        XCTAssertEqual(harness.editableDocument?.controlPanelMetadata.selectedInstrumentDisplay, "I01 Snapshot")
        XCTAssertEqual(view.displayState.instrumentName, "Snapshot")
        XCTAssertEqual(view.envelopeDisplayMode, .panning)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Rename Instrument")

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.name, "Renamed")
        XCTAssertEqual(harness.editableDocument?.controlPanelMetadata.selectedInstrumentDisplay, "I01 Renamed")
        XCTAssertEqual(view.displayState.instrumentName, "Renamed")
        XCTAssertEqual(view.envelopeDisplayMode, .panning)
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

    func testSamplePanningMutationRequiresStoppedEditableRepresentedSelection() {
        let represented = documentWithInstrumentName("Represented", panning: 37)
        let blockedContexts: [EditableDocumentEditContext] = [
            .none,
            .loadedReadOnly,
            .editable(document: represented, isPlaybackActive: true),
            .editable(document: .makeDefault(), isPlaybackActive: false),
            .editable(document: documentWithInstrumentName("Empty", samples: []), isPlaybackActive: false),
        ]

        for context in blockedContexts {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testSamplePanningMutationPreservesExactRangeAndAllNeighboringValues() throws {
        let before = documentWithInstrumentName(
            "Snapshot",
            panning: 37,
            panningEnvelope: PlaybackPanningEnvelope(
                enabled: true,
                points: [PlaybackEnvelopePoint(tick: 0, value: 32)],
                sustainPointIndex: nil,
                loopStartPointIndex: nil,
                loopEndPointIndex: nil,
                typeFlags: 1
            ),
            autoVibrato: PlaybackInstrumentAutoVibrato(waveformType: 3, sweep: 17, depth: 42, rate: 199)
        )
        let originalInstrument = try XCTUnwrap(before.instrumentPalette[1])
        let originalSample = try XCTUnwrap(originalInstrument.samples.first)

        for panning in [UInt8(0), 128, 255, 201] {
            let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
            XCTAssertTrue(harness.coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: panning))
            let after = try XCTUnwrap(harness.editableDocument)
            let editedInstrument = try XCTUnwrap(after.instrumentPalette[1])
            let editedSample = try XCTUnwrap(editedInstrument.samples.first)

            XCTAssertEqual(editedSample.panning, panning)
            XCTAssertEqual(editedSample.withPanning(originalSample.panning), originalSample)
            XCTAssertEqual(editedInstrument.name, originalInstrument.name)
            XCTAssertEqual(editedInstrument.volumeEnvelope, originalInstrument.volumeEnvelope)
            XCTAssertEqual(editedInstrument.panningEnvelope, originalInstrument.panningEnvelope)
            XCTAssertEqual(editedInstrument.autoVibrato, originalInstrument.autoVibrato)
            XCTAssertEqual(editedInstrument.noteSampleMap, originalInstrument.noteSampleMap)
            XCTAssertEqual(after.selection, before.selection)
            XCTAssertEqual(after.patterns, before.patterns)
            XCTAssertEqual(after.noteAuditionAvailability, before.noteAuditionAvailability)
        }
    }

    func testSamplePanningUsesOneUndoActionRefreshesReadoutAndRejectsNoOp() throws {
        let before = documentWithInstrumentName("Snapshot", panning: 37)
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: { controller.apply(displayState: .editableDocument($0)) }
        )

        XCTAssertFalse(harness.coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 37))
        XCTAssertFalse(harness.undoManager.canUndo)
        XCTAssertTrue(harness.coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
        XCTAssertEqual(view.displayState.selectedSample?.panningDisplay, "201 / 255")
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Change Sample Panning")
        XCTAssertEqual(harness.appliedDocuments.count, 1)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(view.displayState.selectedSample?.panning, 37)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Change Sample Panning")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(view.displayState.selectedSample?.panning, 201)
        XCTAssertEqual(harness.appliedDocuments.count, 3)
    }

    func testWholeDocumentUndoRedoSnapshotsPreserveExactSamplePanning() {
        let before = documentWithInstrumentName("Snapshot", panning: 17)
        let after = documentWithInstrumentName("Snapshot", panning: 241)
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertTrue(harness.coordinator.applyEdit(label: "Snapshot Test", updatedDocument: after))
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.samples.first?.panning, 241)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.samples.first?.panning, 17)

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.samples.first?.panning, 241)
    }

    func testWholeDocumentUndoRedoSnapshotsPreserveExactInstrumentEnvelopeMetadataAndAuditionBehavior() {
        let beforePanningEnvelope = PlaybackPanningEnvelope(
            enabled: false,
            points: [PlaybackEnvelopePoint(tick: 0, value: 32)],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0
        )
        let afterPanningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 32),
                PlaybackEnvelopePoint(tick: 8, value: 48),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 1,
            typeFlags: 0x07
        )
        let beforeAutoVibrato = PlaybackInstrumentAutoVibrato(
            waveformType: 1,
            sweep: 2,
            depth: 3,
            rate: 4
        )
        let afterAutoVibrato = PlaybackInstrumentAutoVibrato(
            waveformType: 255,
            sweep: 254,
            depth: 253,
            rate: 252
        )
        let before = documentWithInstrumentName(
            "Snapshot",
            panning: 37,
            panningEnvelope: beforePanningEnvelope,
            autoVibrato: beforeAutoVibrato
        )
        let after = documentWithInstrumentName(
            "Snapshot",
            panning: 37,
            panningEnvelope: afterPanningEnvelope,
            autoVibrato: afterAutoVibrato
        )
        let beforeAudition = before.noteAuditionAvailability
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertEqual(after.noteAuditionAvailability, beforeAudition)
        XCTAssertTrue(harness.coordinator.applyEdit(label: "Snapshot Test", updatedDocument: after))
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.panningEnvelope, afterPanningEnvelope)
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.autoVibrato, afterAutoVibrato)
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.samples.first?.panning, 37)
        XCTAssertEqual(harness.editableDocument?.noteAuditionAvailability, beforeAudition)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.panningEnvelope, beforePanningEnvelope)
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.autoVibrato, beforeAutoVibrato)
        XCTAssertEqual(harness.editableDocument?.noteAuditionAvailability, beforeAudition)

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.panningEnvelope, afterPanningEnvelope)
        XCTAssertEqual(harness.editableDocument?.instrumentPalette[1]?.autoVibrato, afterAutoVibrato)
        XCTAssertEqual(harness.editableDocument?.noteAuditionAvailability, beforeAudition)
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

private func documentWithInstrumentName(
    _ name: String,
    panning: UInt8 = 128,
    panningEnvelope: PlaybackPanningEnvelope = .disabled,
    autoVibrato: PlaybackInstrumentAutoVibrato = .disabled,
    samples: [PlaybackSample]? = nil
) -> BlankTrackerDocument {
    let base = BlankTrackerDocument.makeDefault()
    let sample = PlaybackSample(
        instrumentIndex: 1,
        sampleIndex: 0,
        pcm: [0, 0.5, -0.5],
        volume: 1,
        panning: panning,
        relativeNote: 0,
        finetune: 0,
        baseSampleRate: 8_363
    )
    let instrument = PlaybackInstrument(
        index: 1,
        name: name,
        samples: samples ?? [sample],
        panningEnvelope: panningEnvelope,
        autoVibrato: autoVibrato
    )
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
