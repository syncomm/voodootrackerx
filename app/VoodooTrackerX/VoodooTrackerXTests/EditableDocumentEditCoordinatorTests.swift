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

    func testNewInstrumentIsOneApplyEditActionWithExactSelectionUndoRedo() throws {
        let before = BlankTrackerDocument.makeDefault()
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertTrue(harness.coordinator.canCreateInstrument)
        XCTAssertTrue(harness.coordinator.createInstrument())

        let created = try XCTUnwrap(harness.editableDocument)
        XCTAssertEqual(created.instrumentPalette.keys.sorted(), [1, 2])
        XCTAssertNil(created.instrumentPalette[2]?.name)
        XCTAssertEqual(created.instrumentPalette[2]?.samples, [])
        XCTAssertEqual(created.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(created.patterns, before.patterns)
        XCTAssertEqual(harness.appliedDocuments, [created])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo New Instrument")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo New Instrument")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, created)
        XCTAssertEqual(harness.appliedDocuments, [created, before, created])
    }

    func testNewInstrumentIsUnavailableWithoutStoppedEditableCapacityAndCreatesNoHistory() {
        let base = BlankTrackerDocument.makeDefault()
        let atLimit = BlankTrackerDocument(
            title: base.title,
            songLength: base.songLength,
            currentPosition: base.currentPosition,
            restartPosition: base.restartPosition,
            currentPatternIndex: base.currentPatternIndex,
            tempo: base.tempo,
            speed: base.speed,
            orderTable: base.orderTable,
            selection: TrackerEditorSelection(selectedInstrument: 255, selectedSample: 1),
            instrumentPalette: [255: PlaybackInstrument(index: 255, samples: [])],
            patterns: base.patterns
        )
        let contexts: [EditableDocumentEditContext] = [
            .none,
            .loadedReadOnly,
            .editable(document: base, isPlaybackActive: true),
            .editable(document: atLimit, isPlaybackActive: false),
        ]

        for context in contexts {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.canCreateInstrument)
            XCTAssertFalse(harness.coordinator.createInstrument())
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testGenerateSineIsOneApplyEditActionWithExactUndoRedo() throws {
        let before = BlankTrackerDocument.makeDefault()
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        XCTAssertTrue(harness.coordinator.canGenerateSineSample)
        XCTAssertTrue(harness.coordinator.generateSineSample())
        let generated = try XCTUnwrap(harness.editableDocument)
        XCTAssertEqual(harness.appliedDocuments, [generated])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Generate Sine Sample")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Generate Sine Sample")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, generated)
    }

    func testGenerateSineRejectsUnavailableContextsWithoutMutationOrHistory() {
        let base = BlankTrackerDocument.makeDefault()
        var wrongDestination = base
        wrongDestination.selectSample(2)
        var occupied = base
        XCTAssertTrue(occupied.generateSineInSelectedEmptySample())
        let contexts: [EditableDocumentEditContext] = [
            .none,
            .loadedReadOnly,
            .editable(document: base, isPlaybackActive: true),
            .editable(document: wrongDestination, isPlaybackActive: false),
            .editable(document: occupied, isPlaybackActive: false),
        ]

        for context in contexts {
            let harness = EditHarness(context: context)
            XCTAssertEqual([harness.coordinator.canGenerateSineSample, harness.coordinator.generateSineSample()], [false, false])
            XCTAssertTrue(harness.appliedDocuments.isEmpty && !harness.undoManager.canUndo)
        }
    }

    func testAudioImportAndReplacementUseFormatNeutralApplyEditLabelsWithExactUndoRedo() throws {
        let empty = BlankTrackerDocument.makeDefault()
        let candidate = try normalizedImportCandidate(name: "Kick.wav", pcm: [-0.75, 0.75])
        let instrumentController = InstrumentEditorWindowController(displayState: .editableDocument(empty))
        let sampleController = SampleEditorWindowController(displayState: .editableDocument(empty))
        let instrumentView = try XCTUnwrap(instrumentController.window?.contentView as? InstrumentEditorView)
        let sampleView = try XCTUnwrap(sampleController.window?.contentView as? SampleEditorView)
        let emptyHarness = EditHarness(
            context: .editable(document: empty, isPlaybackActive: false),
            onApply: {
                instrumentController.apply(displayState: .editableDocument($0))
                sampleController.apply(displayState: .editableDocument($0))
            }
        )
        let emptyDestination = try XCTUnwrap(empty.selectedSampleImportDestination)

        XCTAssertTrue(emptyHarness.coordinator.canImportAudioSample)
        XCTAssertTrue(emptyHarness.coordinator.importAudioSample(candidate, destination: emptyDestination))
        let imported = try XCTUnwrap(emptyHarness.editableDocument)
        XCTAssertEqual(emptyHarness.appliedDocuments, [imported])
        XCTAssertEqual(emptyHarness.coordinator.undoMenuItemTitle, "Undo Import Audio Sample")
        XCTAssertEqual(imported.controlPanelMetadata.selectedSampleDisplay, "S01 Kick")
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Kick")
        XCTAssertEqual(sampleView.displayState.sampleName, "Kick")
        XCTAssertTrue(emptyHarness.coordinator.undo())
        XCTAssertEqual(emptyHarness.editableDocument, empty)
        XCTAssertEqual(sampleView.displayState.sampleName, "No represented sample")
        XCTAssertTrue(emptyHarness.coordinator.redo())
        XCTAssertEqual(emptyHarness.editableDocument, imported)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Kick")
        XCTAssertEqual(sampleView.displayState.sampleName, "Kick")

        let oldSample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, name: "Old", pcm: [0.25])
        let oldInstrument = PlaybackInstrument(
            index: 1, name: "Preserved", samples: [oldSample], noteSampleMap: Array(repeating: 0, count: 96)
        )
        let occupied = BlankTrackerDocument(
            title: empty.title, songLength: empty.songLength, currentPosition: empty.currentPosition,
            restartPosition: empty.restartPosition, currentPatternIndex: empty.currentPatternIndex,
            tempo: empty.tempo, speed: empty.speed, orderTable: empty.orderTable,
            selection: .default, instrumentPalette: [1: oldInstrument], patterns: empty.patterns
        )
        let replacementHarness = EditHarness(context: .editable(document: occupied, isPlaybackActive: false))
        let replacementDestination = try XCTUnwrap(occupied.selectedSampleImportDestination)

        XCTAssertTrue(replacementHarness.coordinator.importAudioSample(candidate, destination: replacementDestination))
        let replaced = try XCTUnwrap(replacementHarness.editableDocument)
        XCTAssertEqual(replaced.instrumentPalette[1]?.samples.first?.name, "Kick")
        XCTAssertEqual(replaced.instrumentPalette[1]?.noteSampleMap, oldInstrument.noteSampleMap)
        XCTAssertEqual(replacementHarness.coordinator.undoMenuItemTitle, "Undo Replace Audio Sample")
        XCTAssertTrue(replacementHarness.coordinator.undo())
        XCTAssertEqual(replacementHarness.editableDocument, occupied)
        XCTAssertTrue(replacementHarness.coordinator.redo())
        XCTAssertEqual(replacementHarness.editableDocument, replaced)
    }

    func testAddAudioSampleIsOneApplyEditActionWithExactSelectionUndoRedo() throws {
        var before = BlankTrackerDocument.makeDefault()
        let first = try normalizedImportCandidate(name: "First.wav", pcm: [-0.25, 0.25])
        XCTAssertTrue(before.importAudioSample(first, destination: try XCTUnwrap(before.selectedSampleImportDestination)))
        let preservedMap = before.instrumentPalette[1]?.noteSampleMap
        let candidate = try normalizedImportCandidate(name: "Second.wav", pcm: [-0.75, 0, 0.75])
        let instrumentController = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let sampleController = SampleEditorWindowController(displayState: .editableDocument(before))
        let instrumentView = try XCTUnwrap(instrumentController.window?.contentView as? InstrumentEditorView)
        let sampleView = try XCTUnwrap(sampleController.window?.contentView as? SampleEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: {
                instrumentController.apply(displayState: .editableDocument($0))
                sampleController.apply(displayState: .editableDocument($0))
            }
        )

        XCTAssertTrue(harness.coordinator.addAudioSample(candidate, instrumentIndex: 1, originalSampleCount: 1))
        let added = try XCTUnwrap(harness.editableDocument)
        XCTAssertEqual(added.instrumentPalette[1]?.samples.count, 2)
        XCTAssertEqual(added.instrumentPalette[1]?.samples[1], candidate.playbackSample(instrumentIndex: 1, sampleIndex: 1))
        XCTAssertEqual(added.instrumentPalette[1]?.noteSampleMap, preservedMap)
        XCTAssertEqual(added.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(added.controlPanelMetadata.selectedSampleDisplay, "S02 Second")
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Second")
        XCTAssertEqual(sampleView.displayState.sampleName, "Second")
        let sampleRequest = SampleEditorAuditionRequestFactory.request(selection: added.selection, sourceContext: .blankDocument)
        let instrumentRequest = try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
            noteValue: UInt8(PlaybackPitchCalculator.c4NoteValue),
            selection: added.selection, instrument: added.instrumentPalette[1], sourceContext: .blankDocument
        ))
        XCTAssertEqual(sampleRequest.selectedSampleIndex, 2)
        XCTAssertEqual(instrumentRequest.selectedSampleIndex, 1)
        XCTAssertEqual(harness.appliedDocuments, [added])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Add Audio Sample")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "First")
        XCTAssertEqual(sampleView.displayState.sampleName, "First")
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Add Audio Sample")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, added)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Second")
        XCTAssertEqual(sampleView.displayState.sampleName, "Second")
        XCTAssertEqual(harness.appliedDocuments, [added, before, added])
    }

    func testAddAudioSampleRejectsReadOnlyPlaybackStaleCountAndMaximumWithoutHistory() throws {
        let candidate = try normalizedImportCandidate()
        var oneSample = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(oneSample.importAudioSample(candidate, destination: try XCTUnwrap(oneSample.selectedSampleImportDestination)))
        let maximumSamples = (0..<BlankTrackerDocument.maximumSampleCountPerInstrument).map {
            candidate.playbackSample(instrumentIndex: 1, sampleIndex: $0)
        }
        let atLimit = documentWithInstrumentName("At Limit", samples: maximumSamples)
        let cases: [(EditableDocumentEditContext, Int)] = [
            (.loadedReadOnly, 1),
            (.editable(document: oneSample, isPlaybackActive: true), 1),
            (.editable(document: oneSample, isPlaybackActive: false), 0),
            (.editable(document: atLimit, isPlaybackActive: false), maximumSamples.count),
        ]

        for (context, originalSampleCount) in cases {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.addAudioSample(candidate, instrumentIndex: 1, originalSampleCount: originalSampleCount))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testAudioImportRejectsLoadedPlayingInvalidAndStaleDestinationsWithoutHistory() throws {
        let base = BlankTrackerDocument.makeDefault()
        var invalid = base
        invalid.selectSample(2)
        let candidate = try normalizedImportCandidate()
        let destination = try XCTUnwrap(base.selectedSampleImportDestination)
        let contexts: [EditableDocumentEditContext] = [
            .none, .loadedReadOnly,
            .editable(document: base, isPlaybackActive: true),
            .editable(document: invalid, isPlaybackActive: false),
        ]

        for context in contexts {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.canImportAudioSample)
            XCTAssertFalse(harness.coordinator.importAudioSample(candidate, destination: destination))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
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

    func testSampleMetadataMutationRequiresStoppedEditableRepresentedSelection() {
        let represented = documentWithInstrumentName("Represented", panning: 37)
        var wrongSelection = represented
        wrongSelection.selectSample(2)
        let blockedContexts: [EditableDocumentEditContext] = [
            .none,
            .loadedReadOnly,
            .editable(document: represented, isPlaybackActive: true),
            .editable(document: .makeDefault(), isPlaybackActive: false),
            .editable(document: documentWithInstrumentName("Empty", samples: []), isPlaybackActive: false),
            .editable(document: wrongSelection, isPlaybackActive: false),
        ]

        for context in blockedContexts {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
            XCTAssertFalse(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
            XCTAssertFalse(harness.coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: -12))
            XCTAssertFalse(harness.coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: -64))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testSampleKeymapRangeEditIsOneUndoActionWithExactSelectionUndoRedo() throws {
        let before = makeSampleKeymapEditableDocument()
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        let originalExport = try EditableXMWriter().data(from: before)

        let outcome = try harness.coordinator.mapSampleToNoteRange(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 48, upperNote: 59
        ).get()
        let edited = try XCTUnwrap(harness.editableDocument)

        XCTAssertEqual(outcome.changedNoteCount, 12)
        XCTAssertEqual(outcome.noteRange, 48...59)
        XCTAssertEqual(edited.selection, before.selection)
        XCTAssertEqual(harness.appliedDocuments, [edited])
        XCTAssertEqual(harness.revision, 1)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Map Sample to Note Range")
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(
            try EditableXMWriter().data(from: XCTUnwrap(harness.editableDocument)),
            originalExport
        )
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Map Sample to Note Range")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, edited)
        XCTAssertEqual(harness.appliedDocuments, [edited, before, edited])
    }

    func testSampleKeymapRangeNoOpAndRejectedContextsCreateNoHistoryOrRevision() throws {
        var alreadyMapped = makeSampleKeymapEditableDocument()
        _ = try alreadyMapped.assignSample(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 48, upperNote: 59
        ).get()
        let noOpHarness = EditHarness(context: .editable(document: alreadyMapped, isPlaybackActive: false))
        let noOp = try noOpHarness.coordinator.mapSampleToNoteRange(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 48, upperNote: 59
        ).get()
        XCTAssertTrue(noOp.isNoOp)
        XCTAssertTrue(noOpHarness.appliedDocuments.isEmpty)
        XCTAssertEqual(noOpHarness.revision, 0)
        XCTAssertFalse(noOpHarness.undoManager.canUndo)

        let source = makeSampleKeymapEditableDocument()
        let cases: [(EditableDocumentEditContext, SampleKeymapRangeEditFailure)] = [
            (.none, .noEditableDocument),
            (.loadedReadOnly, .readOnlyDocument),
            (.editable(document: source, isPlaybackActive: true), .playbackActive),
        ]
        for (context, failure) in cases {
            let harness = EditHarness(context: context)
            let result = harness.coordinator.mapSampleToNoteRange(
                instrumentIndex: 0, sampleIndex: 1, lowerNote: 48, upperNote: 59
            )
            XCTAssertEqual(result, .failure(failure))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertEqual(harness.revision, 0)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testSampleRelativeNoteMutationPreservesSignedByteRangeAndNeighboringValues() throws {
        let before = documentWithInstrumentName(
            "Snapshot",
            volume: 48,
            panning: 37,
            relativeNote: 5,
            finetune: 12,
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

        for relativeNote in [-128, -37, 0, 42, 127] {
            let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
            XCTAssertTrue(harness.coordinator.setSampleRelativeNote(
                instrumentAt: 0,
                sampleAt: 0,
                relativeNote: relativeNote
            ))
            let after = try XCTUnwrap(harness.editableDocument)
            let editedInstrument = try XCTUnwrap(after.instrumentPalette[1])
            let editedSample = try XCTUnwrap(editedInstrument.samples.first)

            XCTAssertEqual(editedSample.relativeNote, relativeNote)
            XCTAssertEqual(editedSample.withRelativeNote(originalSample.relativeNote), originalSample)
            XCTAssertEqual(editedInstrument.name, originalInstrument.name)
            XCTAssertEqual(editedInstrument.volumeEnvelope, originalInstrument.volumeEnvelope)
            XCTAssertEqual(editedInstrument.panningEnvelope, originalInstrument.panningEnvelope)
            XCTAssertEqual(editedInstrument.autoVibrato, originalInstrument.autoVibrato)
            XCTAssertEqual(editedInstrument.noteSampleMap, originalInstrument.noteSampleMap)
            XCTAssertEqual(after.selection, before.selection)
            XCTAssertEqual(after.patterns, before.patterns)
        }
    }

    func testSampleRelativeNoteUsesOneUndoActionAndOnlyExistingPitchPaths() throws {
        var before = documentWithInstrumentName("Playback", panning: 37, relativeNote: 0, finetune: 64)
        XCTAssertTrue(before.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: { controller.apply(displayState: .editableDocument($0)) }
        )

        func plan(for document: BlankTrackerDocument) -> PlaybackSongSyntheticPlan {
            PlaybackSongSyntheticAdapter.adapt(
                EditablePlaybackSongBuilder.build(from: document),
                orderIndex: 0,
                sampleRate: 8_363
            )
        }

        func amigaTarget(for document: BlankTrackerDocument) throws -> PlaybackSongSyntheticAdapter.AmigaPitchTarget {
            let sample = try XCTUnwrap(document.instrumentPalette[1]?.samples.first)
            return try XCTUnwrap(PlaybackSongSyntheticAdapter.amigaPitchTarget(
                note: 49,
                relativeNote: sample.relativeNote,
                finetune: sample.finetune,
                baseSampleRate: sample.baseSampleRate,
                outputSampleRate: 8_363
            ))
        }

        XCTAssertFalse(harness.coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: 0))
        XCTAssertFalse(harness.coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: -129))
        XCTAssertFalse(harness.coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: 128))
        XCTAssertFalse(harness.undoManager.canUndo)

        let originalPlan = plan(for: before)
        let originalAmiga = try amigaTarget(for: before)
        XCTAssertTrue(harness.coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: 12))
        let editedDocument = try XCTUnwrap(harness.editableDocument)
        let editedPlan = plan(for: editedDocument)
        let editedAmiga = try amigaTarget(for: editedDocument)
        let originalEvent = try XCTUnwrap(originalPlan.pattern.events.first)
        let editedEvent = try XCTUnwrap(editedPlan.pattern.events.first)

        XCTAssertEqual(view.displayState.selectedSample?.relativeNoteDisplay, "+12")
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Change Sample Relative Note")
        XCTAssertEqual(harness.appliedDocuments.count, 1)
        XCTAssertEqual(editedEvent.playbackStep, originalEvent.playbackStep * 2, accuracy: 0.000_001)
        XCTAssertEqual(editedAmiga.playbackStep, originalAmiga.playbackStep * 2, accuracy: 0.000_001)
        XCTAssertEqual(originalPlan.pattern.events.count, editedPlan.pattern.events.count)
        XCTAssertEqual(originalPlan.pattern.rowCount, editedPlan.pattern.rowCount)
        XCTAssertEqual(originalPlan.timingConfig, editedPlan.timingConfig)
        XCTAssertEqual(originalEvent.row, editedEvent.row)
        XCTAssertEqual(originalEvent.tick, editedEvent.tick)
        XCTAssertEqual(originalEvent.scheduledStartFrame, editedEvent.scheduledStartFrame)
        XCTAssertEqual(originalEvent.sample, editedEvent.sample)
        XCTAssertEqual(originalEvent.gain, editedEvent.gain)
        XCTAssertEqual(originalEvent.pan, editedEvent.pan)
        XCTAssertEqual(originalEvent.loop, editedEvent.loop)
        XCTAssertEqual(originalEvent.initialSourceFrame, editedEvent.initialSourceFrame)
        XCTAssertEqual(originalEvent.volumeEnvelope, editedEvent.volumeEnvelope)
        XCTAssertEqual(originalEvent.panEnvelope, editedEvent.panEnvelope)
        XCTAssertEqual(originalPlan.diagnostics.eventMappings.first?.sampleRelativeNote, 0)
        XCTAssertEqual(editedPlan.diagnostics.eventMappings.first?.sampleRelativeNote, 12)
        XCTAssertEqual(originalPlan.diagnostics.eventMappings.first?.sampleFinetune, 64)
        XCTAssertEqual(editedPlan.diagnostics.eventMappings.first?.sampleFinetune, 64)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(view.displayState.selectedSample?.relativeNoteDisplay, "0")
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Change Sample Relative Note")
        XCTAssertEqual(try XCTUnwrap(plan(for: try XCTUnwrap(harness.editableDocument)).pattern.events.first).playbackStep, originalEvent.playbackStep, accuracy: 0.000_001)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(view.displayState.selectedSample?.relativeNoteDisplay, "+12")
        XCTAssertEqual(try XCTUnwrap(plan(for: try XCTUnwrap(harness.editableDocument)).pattern.events.first).playbackStep, editedEvent.playbackStep, accuracy: 0.000_001)
        XCTAssertEqual(harness.appliedDocuments.count, 3)
    }

    func testSampleFinetuneMutationPreservesSignedByteRangeAndNeighboringValues() throws {
        let before = documentWithInstrumentName(
            "Snapshot",
            volume: 48,
            panning: 37,
            finetune: 12,
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

        for finetune in [-128, -37, 0, 42, 127] {
            let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
            XCTAssertTrue(harness.coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: finetune))
            let after = try XCTUnwrap(harness.editableDocument)
            let editedInstrument = try XCTUnwrap(after.instrumentPalette[1])
            let editedSample = try XCTUnwrap(editedInstrument.samples.first)

            XCTAssertEqual(editedSample.finetune, finetune)
            XCTAssertEqual(editedSample.withFinetune(originalSample.finetune), originalSample)
            XCTAssertEqual(editedInstrument.name, originalInstrument.name)
            XCTAssertEqual(editedInstrument.volumeEnvelope, originalInstrument.volumeEnvelope)
            XCTAssertEqual(editedInstrument.panningEnvelope, originalInstrument.panningEnvelope)
            XCTAssertEqual(editedInstrument.autoVibrato, originalInstrument.autoVibrato)
            XCTAssertEqual(editedInstrument.noteSampleMap, originalInstrument.noteSampleMap)
            XCTAssertEqual(after.selection, before.selection)
            XCTAssertEqual(after.patterns, before.patterns)
        }
    }

    func testSampleFinetuneUsesOneUndoActionAndChangesOnlyExistingAdaptedPitch() throws {
        var before = documentWithInstrumentName("Playback", panning: 37, finetune: 0)
        XCTAssertTrue(before.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: { controller.apply(displayState: .editableDocument($0)) }
        )

        func plan(for document: BlankTrackerDocument) -> PlaybackSongSyntheticPlan {
            PlaybackSongSyntheticAdapter.adapt(
                EditablePlaybackSongBuilder.build(from: document),
                orderIndex: 0,
                sampleRate: 8_363
            )
        }

        XCTAssertFalse(harness.coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: 0))
        XCTAssertFalse(harness.coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: -129))
        XCTAssertFalse(harness.coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: 128))
        XCTAssertFalse(harness.undoManager.canUndo)

        let originalPlan = plan(for: before)
        XCTAssertTrue(harness.coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: 64))
        let editedPlan = plan(for: try XCTUnwrap(harness.editableDocument))
        let originalEvent = try XCTUnwrap(originalPlan.pattern.events.first)
        let editedEvent = try XCTUnwrap(editedPlan.pattern.events.first)

        XCTAssertEqual(view.displayState.selectedSample?.finetuneDisplay, "+64")
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Change Sample Finetune")
        XCTAssertEqual(harness.appliedDocuments.count, 1)
        XCTAssertEqual(originalEvent.playbackStep, 1, accuracy: 0.000_001)
        XCTAssertEqual(editedEvent.playbackStep, pow(2.0, 0.5 / 12.0), accuracy: 0.000_001)
        XCTAssertEqual(originalPlan.pattern.events.count, editedPlan.pattern.events.count)
        XCTAssertEqual(originalPlan.pattern.rowCount, editedPlan.pattern.rowCount)
        XCTAssertEqual(originalPlan.timingConfig, editedPlan.timingConfig)
        XCTAssertEqual(originalEvent.row, editedEvent.row)
        XCTAssertEqual(originalEvent.tick, editedEvent.tick)
        XCTAssertEqual(originalEvent.scheduledStartFrame, editedEvent.scheduledStartFrame)
        XCTAssertEqual(originalEvent.sample, editedEvent.sample)
        XCTAssertEqual(originalEvent.gain, editedEvent.gain)
        XCTAssertEqual(originalEvent.pan, editedEvent.pan)
        XCTAssertEqual(originalEvent.loop, editedEvent.loop)
        XCTAssertEqual(originalEvent.initialSourceFrame, editedEvent.initialSourceFrame)
        XCTAssertEqual(originalEvent.volumeEnvelope, editedEvent.volumeEnvelope)
        XCTAssertEqual(originalEvent.panEnvelope, editedEvent.panEnvelope)
        XCTAssertEqual(originalPlan.diagnostics.eventMappings.first?.sampleIndex, editedPlan.diagnostics.eventMappings.first?.sampleIndex)
        XCTAssertEqual(originalPlan.diagnostics.eventMappings.first?.sampleFinetune, 0)
        XCTAssertEqual(editedPlan.diagnostics.eventMappings.first?.sampleFinetune, 64)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(view.displayState.selectedSample?.finetuneDisplay, "0")
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Change Sample Finetune")
        XCTAssertEqual(try XCTUnwrap(plan(for: try XCTUnwrap(harness.editableDocument)).pattern.events.first).playbackStep, 1, accuracy: 0.000_001)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(view.displayState.selectedSample?.finetuneDisplay, "+64")
        XCTAssertEqual(try XCTUnwrap(plan(for: try XCTUnwrap(harness.editableDocument)).pattern.events.first).playbackStep, editedEvent.playbackStep, accuracy: 0.000_001)
        XCTAssertEqual(harness.appliedDocuments.count, 3)
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
            guard case let .potentiallyAvailable(descriptor) = after.noteAuditionAvailability else {
                return XCTFail("expected edited sample to remain previewable")
            }
            XCTAssertEqual(descriptor.previewPanning, panning)
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

    func testSampleVolumeMutationPreservesExactXMRangeAndNeighboringValues() throws {
        let before = documentWithInstrumentName(
            "Snapshot",
            volume: 48,
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

        for volume in [UInt8(0), 16, 37, 64] {
            let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
            XCTAssertTrue(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: volume))
            let after = try XCTUnwrap(harness.editableDocument)
            let editedInstrument = try XCTUnwrap(after.instrumentPalette[1])
            let editedSample = try XCTUnwrap(editedInstrument.samples.first)

            XCTAssertEqual(editedSample.xmVolume, volume)
            XCTAssertEqual(editedSample.withVolume(originalSample.xmVolume), originalSample)
            XCTAssertEqual(editedInstrument.name, originalInstrument.name)
            XCTAssertEqual(editedInstrument.volumeEnvelope, originalInstrument.volumeEnvelope)
            XCTAssertEqual(editedInstrument.panningEnvelope, originalInstrument.panningEnvelope)
            XCTAssertEqual(editedInstrument.autoVibrato, originalInstrument.autoVibrato)
            XCTAssertEqual(editedInstrument.noteSampleMap, originalInstrument.noteSampleMap)
            XCTAssertEqual(after.selection, before.selection)
            XCTAssertEqual(after.patterns, before.patterns)
        }
    }

    func testSampleVolumeUsesOneUndoActionRefreshesReadoutAndRejectsNoOpAndOutOfRange() throws {
        let before = documentWithInstrumentName("Snapshot", volume: 48)
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: { controller.apply(displayState: .editableDocument($0)) }
        )

        XCTAssertFalse(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 48))
        XCTAssertFalse(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 65))
        XCTAssertFalse(harness.undoManager.canUndo)
        XCTAssertTrue(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
        XCTAssertEqual(view.displayState.selectedSample?.volumeLevel, 17)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Change Sample Volume")
        XCTAssertEqual(harness.appliedDocuments.count, 1)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(view.displayState.selectedSample?.volumeLevel, 48)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Change Sample Volume")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(view.displayState.selectedSample?.volumeLevel, 17)
        XCTAssertEqual(harness.appliedDocuments.count, 3)
    }

    func testSampleVolumeEditUndoRedoChangesOnlyExistingAdaptedGain() throws {
        var before = documentWithInstrumentName("Playback", volume: 64, panning: 37)
        XCTAssertTrue(before.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        func plan(for document: BlankTrackerDocument) -> PlaybackSongSyntheticPlan {
            PlaybackSongSyntheticAdapter.adapt(
                EditablePlaybackSongBuilder.build(from: document),
                orderIndex: 0,
                sampleRate: 100
            )
        }

        let originalPlan = plan(for: before)
        XCTAssertTrue(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 16))
        let editedPlan = plan(for: try XCTUnwrap(harness.editableDocument))
        let originalEvent = try XCTUnwrap(originalPlan.pattern.events.first)
        let editedEvent = try XCTUnwrap(editedPlan.pattern.events.first)

        XCTAssertEqual(originalEvent.gain, 1, accuracy: 0.000_001)
        XCTAssertEqual(editedEvent.gain, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(originalPlan.pattern.events.count, editedPlan.pattern.events.count)
        XCTAssertEqual(originalPlan.pattern.rowCount, editedPlan.pattern.rowCount)
        XCTAssertEqual(originalPlan.timingConfig, editedPlan.timingConfig)
        XCTAssertEqual(originalEvent.row, editedEvent.row)
        XCTAssertEqual(originalEvent.tick, editedEvent.tick)
        XCTAssertEqual(originalEvent.scheduledStartFrame, editedEvent.scheduledStartFrame)
        XCTAssertEqual(originalEvent.sample, editedEvent.sample)
        XCTAssertEqual(originalEvent.pan, editedEvent.pan)
        XCTAssertEqual(originalEvent.playbackStep, editedEvent.playbackStep)
        XCTAssertEqual(originalEvent.loop, editedEvent.loop)
        XCTAssertEqual(originalEvent.initialSourceFrame, editedEvent.initialSourceFrame)
        XCTAssertEqual(originalEvent.volumeEnvelope, editedEvent.volumeEnvelope)
        XCTAssertEqual(originalEvent.panEnvelope, editedEvent.panEnvelope)
        XCTAssertEqual(originalPlan.diagnostics.eventMappings.first?.sampleIndex, editedPlan.diagnostics.eventMappings.first?.sampleIndex)
        XCTAssertEqual(originalPlan.diagnostics.eventMappings.first?.sampleVolumeRawEstimate, 64)
        XCTAssertEqual(editedPlan.diagnostics.eventMappings.first?.sampleVolumeRawEstimate, 16)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(try XCTUnwrap(plan(for: try XCTUnwrap(harness.editableDocument)).pattern.events.first).gain, 1, accuracy: 0.000_001)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(try XCTUnwrap(plan(for: try XCTUnwrap(harness.editableDocument)).pattern.events.first).gain, 0.25, accuracy: 0.000_001)
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
    private(set) var revision = 0
    let undoManager = UndoManager()
    private let onApply: (BlankTrackerDocument) -> Void

    lazy var coordinator = EditableDocumentEditCoordinator(
        undoManager: undoManager,
        contextProvider: { [unowned self] in context },
        documentApplyHandler: { [unowned self] document in
            context = .editable(document: document, isPlaybackActive: false)
            appliedDocuments.append(document)
            revision += 1
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
    volume: UInt8 = 64,
    panning: UInt8 = 128,
    relativeNote: Int = 0,
    finetune: Int = 0,
    panningEnvelope: PlaybackPanningEnvelope = .disabled,
    autoVibrato: PlaybackInstrumentAutoVibrato = .disabled,
    samples: [PlaybackSample]? = nil
) -> BlankTrackerDocument {
    let base = BlankTrackerDocument.makeDefault()
    let sample = PlaybackSample(
        instrumentIndex: 1,
        sampleIndex: 0,
        pcm: [0, 0.5, -0.5],
        volume: Float(volume) / 64.0,
        panning: panning,
        relativeNote: relativeNote,
        finetune: finetune,
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
