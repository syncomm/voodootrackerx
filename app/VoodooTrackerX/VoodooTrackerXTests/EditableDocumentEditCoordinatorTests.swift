import AppKit
import XCTest

@MainActor
final class EditableDocumentEditCoordinatorTests: XCTestCase {
    func testEditableNavigationCreatesNoUndoAndContentUndoRedoKeepsCanonicalPositionAndView() throws {
        let initial = documentWithArrangedSongDataAndPalette()
        let harness = EditHarness(context: .editable(document: initial, isPlaybackActive: false))
        XCTAssertTrue(harness.navigationCoordinator.selectPatternForViewing(0))

        XCTAssertFalse(harness.coordinator.canUndo)
        XCTAssertFalse(harness.coordinator.canRedo)
        XCTAssertEqual(harness.revision, 1)
        XCTAssertEqual(harness.appliedDocuments.count, 1)
        XCTAssertTrue(harness.coordinator.setSampleVolume(
            instrumentAt: 0,
            sampleAt: 1,
            volume: 31
        ))
        XCTAssertEqual(harness.editableDocument?.currentPosition, 1)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 0)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 1)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 0)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 1)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 0)
        XCTAssertEqual(TrackerPlaybackStartContextResolver.normalPlayContext(
            editableDocument: try XCTUnwrap(harness.editableDocument), row: 0
        ).patternIndex, 7)
        XCTAssertEqual(TrackerPlaybackStartContextResolver.currentPatternLoopContext(
            editableDocument: try XCTUnwrap(harness.editableDocument)
        )?.patternIndex, 0)

        let undoTitle = harness.coordinator.undoMenuItemTitle
        XCTAssertTrue(harness.navigationCoordinator.selectOrderPosition(0))
        XCTAssertTrue(harness.coordinator.canUndo)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, undoTitle)
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 0)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 0)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 0)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 0)
        XCTAssertTrue(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 1, volume: 30))
        XCTAssertEqual(harness.editableDocument?.currentPosition, 0)
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 0)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 0)
        XCTAssertEqual(harness.revision, 10)
        XCTAssertEqual(harness.appliedDocuments.count, 10)
    }

    func testPlaybackStopNavigationBumpsRevisionWithoutUndoAndSurvivesContentUndoRedo() throws {
        let initial = documentWithArrangedSongDataAndPalette()
        let harness = EditHarness(context: .editable(document: initial, isPlaybackActive: false))
        XCTAssertTrue(harness.coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 1, volume: 31))
        let undoTitle = harness.coordinator.undoMenuItemTitle

        let update = try XCTUnwrap(harness.navigationCoordinator.reconcilePlaybackStop(
            at: PlaybackPosition(orderIndex: 2, patternIndex: 7, rowIndex: 5)
        ))
        guard case let .canonicalDocument(stoppedDocument, didChange) = update else {
            return XCTFail("Stop must produce canonical editable navigation")
        }
        XCTAssertTrue(didChange)
        XCTAssertEqual(stoppedDocument.currentPosition, 2)
        XCTAssertEqual(stoppedDocument.currentPatternIndex, 7)
        XCTAssertEqual(harness.revision, 2)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, undoTitle)

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 2)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 7)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument?.currentPosition, 2)
        XCTAssertEqual(harness.editableDocument?.currentPatternIndex, 7)
    }

    func testEditableNavigationCoordinatorRejectsUnavailableReadOnlyAndPlaybackContexts() {
        let document = documentWithArrangedSongDataAndPalette()
        for context in [
            EditableDocumentEditContext.none,
            .loadedReadOnly,
            .editable(document: document, isPlaybackActive: true),
        ] {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.navigationCoordinator.selectOrderPosition(0))
            XCTAssertFalse(harness.navigationCoordinator.selectPatternForViewing(0))
            XCTAssertEqual(harness.revision, 0)
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.coordinator.canUndo)
        }
    }

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

    func testClearSongDataIsOneApplyEditActionWithExactUndoRedoAndPreservedPalette() {
        let before = documentWithArrangedSongDataAndPalette()
        var cleared = before
        cleared.clearSongData()
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertTrue(harness.coordinator.clearSongData())
        XCTAssertEqual(harness.editableDocument, cleared)
        XCTAssertEqual(harness.editableDocument?.instrumentPalette, before.instrumentPalette)
        XCTAssertEqual(harness.appliedDocuments, [cleared])
        XCTAssertEqual(harness.revision, 1)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Clear Song Data")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(harness.revision, 2)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Clear Song Data")

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, cleared)
        XCTAssertEqual(harness.appliedDocuments, [cleared, before, cleared])
        XCTAssertEqual(harness.revision, 3)
    }

    func testClearSongDataRejectsUnavailablePlaybackAndNoOpContextsWithoutHistory() {
        let populated = documentWithArrangedSongDataAndPalette()
        let contexts: [EditableDocumentEditContext] = [
            .none,
            .loadedReadOnly,
            .editable(document: populated, isPlaybackActive: true),
            .editable(document: .makeDefault(), isPlaybackActive: false),
        ]

        for context in contexts {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.clearSongData())
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertEqual(harness.revision, 0)
            XCTAssertFalse(harness.undoManager.canUndo)
            XCTAssertFalse(harness.undoManager.canRedo)
        }
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
        XCTAssertNil(created.instrumentPalette[2]?.noteSampleMap)
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
        let before = documentWithSelectedInteriorEmptySample()
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        XCTAssertTrue(harness.coordinator.canGenerateSineSample)
        XCTAssertTrue(harness.coordinator.generateSineSample())
        let generated = try XCTUnwrap(harness.editableDocument)
        XCTAssertEqual(generated.instrumentPalette[1]?.samples.map(\.sampleIndex), [0, 1, 2])
        XCTAssertEqual(generated.selection, before.selection)
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
        let wrongDestination = documentWithInvalidSelectedSampleDestination()
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
        XCTAssertEqual(sampleView.displayState.sampleName, "Empty sample destination")
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
        XCTAssertEqual(before.sampleSlotPresentationRows(forInstrument: 1).map(\.sampleSlot), [1])
        XCTAssertEqual(instrumentView.displayState.sampleSlots.map(\.slot), [1])
        XCTAssertEqual(sampleView.displayState.sampleSlots.map(\.slot), [1])
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
        XCTAssertEqual(added.sampleSlotPresentationRows(forInstrument: 1).map(\.sampleSlot), [1, 2])
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Second")
        XCTAssertEqual(instrumentView.displayState.sampleSlots.map(\.slot), [1, 2])
        XCTAssertEqual(sampleView.displayState.sampleName, "Second")
        XCTAssertEqual(sampleView.displayState.sampleSlots.map(\.slot), [1, 2])
        let sampleRequest = SampleEditorAuditionRequestFactory.request(selection: added.selection, sourceContext: .blankDocument)
        let instrumentRequest = try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
            noteValue: UInt8(PlaybackPitchCalculator.c4NoteValue),
            selection: added.selection, sourceContext: .blankDocument
        ))
        XCTAssertEqual(sampleRequest.selectedSampleIndex, 2)
        XCTAssertEqual(sampleRequest.sampleResolution, .directSelectedSample)
        XCTAssertEqual(instrumentRequest.sampleResolution, .instrumentKeymap)
        XCTAssertEqual(instrumentRequest.selectedSampleIndex, 2)
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

    func testDuplicateSampleIsOneEditWithExactSelectionSharedRefreshRoutingAndUndoRedo() throws {
        var before = documentWithThreeDistinctSamplesSelectedS02()
        before.selectSample(1)
        let token = EditorNoteAuditionPreviewToken(
            generation: 1,
            keyIdentity: .sampleEditorAudition,
            noteValue: SampleEditorAuditionRequestFactory.noteValue,
            selectedOctave: SampleEditorAuditionRequestFactory.octave
        )
        var stoppedTokens: [EditorNoteAuditionPreviewToken] = []
        let instrumentController = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let sampleController = SampleEditorWindowController(
            displayState: .editableDocument(before),
            auditionHandlers: .init(start: { token }, stop: { stoppedTokens.append($0); return true })
        )
        sampleController.synchronizeActivePreviewToken(token)
        let instrumentView = try XCTUnwrap(instrumentController.window?.contentView as? InstrumentEditorView)
        let sampleView = try XCTUnwrap(sampleController.window?.contentView as? SampleEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: {
                instrumentController.apply(displayState: .editableDocument($0))
                sampleController.apply(displayState: .editableDocument($0))
            }
        )

        XCTAssertTrue(harness.coordinator.canDuplicateSelectedSample)
        XCTAssertTrue(harness.coordinator.duplicateSample(instrumentAt: 0, sampleAt: 0))

        let duplicated = try XCTUnwrap(harness.editableDocument)
        let duplicatedInstrument = try XCTUnwrap(duplicated.instrumentPalette[1])
        let copiedSample = try XCTUnwrap(duplicatedInstrument.sample(mappedSampleIndex: 3))
        XCTAssertEqual(duplicated.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 4))
        XCTAssertEqual(duplicated.controlPanelMetadata.selectedSampleDisplay, "S04 Pulse S01")
        XCTAssertEqual(instrumentView.displayState.selectedSampleSlot, 4)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.representedSample, copiedSample)
        XCTAssertTrue(instrumentView.displayState.isKeymapRangeAssignmentEnabled)
        XCTAssertEqual(sampleView.displayState.selectedSampleSlot, 4)
        XCTAssertEqual(sampleView.displayState.selectedSample, copiedSample)
        XCTAssertTrue(sampleView.displayState.isAuditionEnabled && sampleView.displayState.isClearEnabled &&
            sampleView.displayState.isWAVLoadEnabled)
        XCTAssertEqual(stoppedTokens, [token])
        XCTAssertNil(sampleView.activeAuditionToken)

        let instrumentRequest = try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
            noteValue: 1, selection: duplicated.selection, sourceContext: .blankDocument
        ))
        guard case let .potentiallyAvailable(instrumentDescriptor) = duplicated.noteAuditionAvailability(
            for: instrumentRequest
        ) else {
            return XCTFail("Instrument audition should continue to follow the unchanged keymap")
        }
        XCTAssertEqual(instrumentDescriptor.sampleIndex, 0)

        XCTAssertEqual(harness.appliedDocuments, [duplicated])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Duplicate Sample")
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual([instrumentView.displayState.selectedSampleSlot, sampleView.displayState.selectedSampleSlot], [1, 1])
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, duplicated)
        XCTAssertEqual(harness.appliedDocuments, [duplicated, before, duplicated])
    }

    func testDuplicateSampleRejectsReadOnlyPlayingEmptyStaleAndTailCapacityWithoutHistory() {
        var represented = documentWithThreeDistinctSamplesSelectedS02()
        represented.selectSample(1)
        let selectedEmpty = documentWithSelectedInteriorEmptySample()
        let source = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, name: "Source")
        let atS16 = documentWithInstrumentName(
            "At S16",
            samples: [source, makePlaybackSample(instrumentIndex: 1, sampleIndex: 15, name: "S16")],
            noteSampleMap: Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
        )
        let cases: [(EditableDocumentEditContext, Int)] = [
            (.loadedReadOnly, 0),
            (.editable(document: represented, isPlaybackActive: true), 0),
            (.editable(document: selectedEmpty, isPlaybackActive: false), 1),
            (.editable(document: atS16, isPlaybackActive: false), 0),
            (.editable(document: represented, isPlaybackActive: false), 1),
        ]

        for (context, sampleIndex) in cases {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.duplicateSample(instrumentAt: 0, sampleAt: sampleIndex))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testClearSampleIsOneEditWithExactSelectionSharedRefreshAndUndoRedo() throws {
        let before = documentWithThreeDistinctSamplesSelectedS02()
        let beforeInstrument = try XCTUnwrap(before.instrumentPalette[1])
        let first = beforeInstrument.samples[0]
        let second = beforeInstrument.samples[1]
        let third = beforeInstrument.samples[2]
        let keymap = try XCTUnwrap(beforeInstrument.noteSampleMap)
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

        XCTAssertTrue(harness.coordinator.canClearSelectedSample)
        XCTAssertTrue(harness.coordinator.clearSample(instrumentAt: 0, sampleAt: 1))

        let cleared = try XCTUnwrap(harness.editableDocument)
        let clearedInstrument = try XCTUnwrap(cleared.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [first, third])
        XCTAssertFalse(clearedInstrument.samples.contains(second))
        XCTAssertEqual(clearedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(clearedInstrument.noteSampleMap, keymap)
        XCTAssertEqual(clearedInstrument.name, beforeInstrument.name)
        XCTAssertEqual(cleared.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(cleared.controlPanelMetadata.selectedSampleDisplay, "S02 Empty des...")
        XCTAssertEqual(instrumentView.displayState.selectedSampleSlot, 2)
        XCTAssertNil(instrumentView.displayState.selectedSample)
        XCTAssertEqual(instrumentView.displayState.sampleSlots.map(\.slot), [1, 2, 3])
        XCTAssertTrue(instrumentView.displayState.sampleSlots[1].isEmptyDestination)
        XCTAssertFalse(instrumentView.displayState.isSampleVolumeEditable)
        XCTAssertFalse(instrumentView.displayState.isKeymapRangeAssignmentEnabled)
        XCTAssertEqual(sampleView.displayState.selectedSampleSlot, 2)
        XCTAssertEqual(sampleView.displayState.sampleName, "Empty sample destination")
        XCTAssertEqual(sampleView.displayState.sampleSlots.map(\.slot), [1, 2, 3])
        XCTAssertFalse(sampleView.displayState.isAuditionEnabled)
        XCTAssertTrue(sampleView.displayState.isWAVLoadEnabled)
        XCTAssertTrue(sampleView.displayState.isSineGenerationEnabled)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 1, instrument: clearedInstrument
        )?.sampleIndex, 0)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 33, instrument: clearedInstrument
        ))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 65, instrument: clearedInstrument
        )?.sampleIndex, 2)
        XCTAssertEqual(harness.appliedDocuments, [cleared])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Clear Sample")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.representedSample, second)
        XCTAssertEqual(sampleView.displayState.selectedSample, second)
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Clear Sample")

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, cleared)
        XCTAssertEqual(instrumentView.displayState.selectedSampleSlot, 2)
        XCTAssertNil(instrumentView.displayState.selectedSample)
        XCTAssertEqual(sampleView.displayState.selectedSampleSlot, 2)
        XCTAssertNil(sampleView.displayState.selectedSample)
        XCTAssertEqual(harness.appliedDocuments, [cleared, before, cleared])
    }

    func testPopulateClearedS02IsOneEditWithExactSharedRefreshRoutingAndUndoRedo() throws {
        var cleared = documentWithThreeDistinctSamplesSelectedS02()
        XCTAssertTrue(cleared.clearSample(instrumentAt: 0, sampleAt: 1))
        let clearedInstrument = try XCTUnwrap(cleared.instrumentPalette[1])
        let preservedMap = try XCTUnwrap(clearedInstrument.noteSampleMap)
        let candidate = try normalizedImportCandidate(name: "Recovered.wav", pcm: [-0.625, 0, 0.625])
        let instrumentController = InstrumentEditorWindowController(displayState: .editableDocument(cleared))
        let sampleController = SampleEditorWindowController(displayState: .editableDocument(cleared))
        let instrumentView = try XCTUnwrap(instrumentController.window?.contentView as? InstrumentEditorView)
        let sampleView = try XCTUnwrap(sampleController.window?.contentView as? SampleEditorView)
        let harness = EditHarness(
            context: .editable(document: cleared, isPlaybackActive: false),
            onApply: {
                instrumentController.apply(displayState: .editableDocument($0))
                sampleController.apply(displayState: .editableDocument($0))
            }
        )
        let destination = try XCTUnwrap(cleared.selectedSampleImportDestination)

        XCTAssertEqual(destination, .emptyDestination(instrumentIndex: 1, sampleIndex: 1))
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 33, instrument: clearedInstrument
        ))
        XCTAssertTrue(harness.coordinator.canImportAudioSample)
        XCTAssertTrue(harness.coordinator.canGenerateSineSample)
        XCTAssertTrue(harness.coordinator.importAudioSample(candidate, destination: destination))

        let populated = try XCTUnwrap(harness.editableDocument)
        let populatedInstrument = try XCTUnwrap(populated.instrumentPalette[1])
        XCTAssertEqual(populatedInstrument.samples.map(\.sampleIndex), [0, 1, 2])
        XCTAssertEqual(populatedInstrument.noteSampleMap, preservedMap)
        XCTAssertEqual(populated.selection, cleared.selection)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 33, instrument: populatedInstrument
        )?.sampleIndex, 1)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Recovered")
        XCTAssertTrue(instrumentView.displayState.isKeymapRangeAssignmentEnabled)
        XCTAssertEqual(sampleView.displayState.sampleName, "Recovered")
        XCTAssertTrue(sampleView.displayState.isAuditionEnabled)
        XCTAssertTrue(sampleView.displayState.isClearEnabled)
        XCTAssertFalse(sampleView.displayState.isSineGenerationEnabled)
        XCTAssertEqual(harness.appliedDocuments, [populated])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Import Audio Sample")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, cleared)
        XCTAssertNil(instrumentView.displayState.selectedSample)
        XCTAssertEqual(sampleView.displayState.sampleName, "Empty sample destination")
        XCTAssertFalse(sampleView.displayState.isAuditionEnabled)
        XCTAssertTrue(sampleView.displayState.isWAVLoadEnabled)
        XCTAssertTrue(sampleView.displayState.isSineGenerationEnabled)

        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, populated)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.representedSample?.sampleIndex, 1)
        XCTAssertEqual(sampleView.displayState.selectedSample?.sampleIndex, 1)
    }

    func testClearSampleRejectsReadOnlyPlayingWrongSelectionAndEmptyTargetWithoutHistory() throws {
        let represented = documentWithThreeDistinctSamplesSelectedS02()
        var wrongSelection = represented
        wrongSelection.selectSample(1)
        var emptyTarget = represented
        XCTAssertTrue(emptyTarget.clearSample(instrumentAt: 0, sampleAt: 1))
        let cases: [(EditableDocumentEditContext, Int, Int, Bool)] = [
            (.none, 0, 1, false),
            (.loadedReadOnly, 0, 1, false),
            (.editable(document: represented, isPlaybackActive: true), 0, 1, false),
            (.editable(document: wrongSelection, isPlaybackActive: false), 0, 1, true),
            (.editable(document: represented, isPlaybackActive: false), 0, 0, true),
            (.editable(document: emptyTarget, isPlaybackActive: false), 0, 1, false),
        ]

        for (context, instrumentIndex, sampleIndex, canClearSelectedSample) in cases {
            let harness = EditHarness(context: context)
            XCTAssertEqual(harness.coordinator.canClearSelectedSample, canClearSelectedSample)
            XCTAssertFalse(harness.coordinator.clearSample(
                instrumentAt: instrumentIndex,
                sampleAt: sampleIndex
            ))
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testSampleSlotPermutationTransactionPreservesDenseSparseMoveAndSwapSemantics() throws {
        let scenarios: [(
            name: String,
            sampleIndices: [Int],
            mapReferences: [Int],
            selectedSampleIndex: Int,
            permutation: SampleSlotPermutation
        )] = [
            ("dense move lower", [0, 1, 2], [0, 1, 2], 2, try .move(from: 2, to: 0)),
            ("dense move higher", [0, 1, 2], [0, 1, 2], 0, try .move(from: 0, to: 2)),
            ("sparse move into hole", [0, 2], [0, 1, 2], 1, try .move(from: 2, to: 1)),
            ("sparse multi-slot move", [0, 2, 4], [0, 1, 2, 3, 4], 3, try .move(from: 4, to: 1)),
            ("represented swap", [0, 1, 2], [0, 1, 2], 0, try .swap(0, 2)),
            ("represented-empty swap", [0, 2], [0, 1, 2], 0, try .swap(0, 1)),
            ("move to S16", [0], [0, 15], 0, try .move(from: 0, to: 15)),
        ]

        for scenario in scenarios {
            let map = (0..<TrackerNoteKeyMap.maximumNoteValue).map {
                scenario.mapReferences[$0 % scenario.mapReferences.count]
            }
            var before = makeSampleKeymapEditableDocument(
                sampleIndices: scenario.sampleIndices,
                noteSampleMap: map,
                selection: TrackerEditorSelection(
                    selectedInstrument: 1,
                    selectedSample: scenario.selectedSampleIndex + 1
                )
            )
            before.pattern.rows[0][0] = XMPatternEventCell(
                note: 48, instrument: 1, volumeColumn: 0x30, effectType: 0x0F, effectParam: 0x06
            )
            let expected = try expectedDocument(
                afterApplying: scenario.permutation,
                instrumentAt: 0,
                to: before
            )
            let semanticIdentityByNote = resolvedSampleContentIdentities(in: before)
            let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

            XCTAssertTrue(
                harness.coordinator.applySampleSlotPermutation(scenario.permutation, instrumentAt: 0),
                scenario.name
            )
            let after = try XCTUnwrap(harness.editableDocument, scenario.name)
            let afterInstrument = try XCTUnwrap(after.instrumentPalette[1], scenario.name)
            XCTAssertEqual(after, expected, scenario.name)
            XCTAssertEqual(afterInstrument.samples.map(\.sampleIndex), afterInstrument.samples.map(\.sampleIndex).sorted(), scenario.name)
            XCTAssertEqual(afterInstrument.samples.count, scenario.sampleIndices.count, scenario.name)
            XCTAssertEqual(afterInstrument.noteSampleMap?.count, TrackerNoteKeyMap.maximumNoteValue, scenario.name)
            XCTAssertEqual(resolvedSampleContentIdentities(in: after), semanticIdentityByNote, scenario.name)
            XCTAssertEqual(harness.appliedDocuments, [after], scenario.name)
            XCTAssertEqual(harness.revision, 1, scenario.name)
            XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Reorder Samples", scenario.name)

            XCTAssertTrue(harness.coordinator.undo(), scenario.name)
            XCTAssertEqual(harness.editableDocument, before, scenario.name)
            XCTAssertEqual(resolvedSampleContentIdentities(in: harness.editableDocument), semanticIdentityByNote, scenario.name)
            XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Reorder Samples", scenario.name)

            XCTAssertTrue(harness.coordinator.redo(), scenario.name)
            XCTAssertEqual(harness.editableDocument, after, scenario.name)
            XCTAssertEqual(resolvedSampleContentIdentities(in: harness.editableDocument), semanticIdentityByNote, scenario.name)
            XCTAssertEqual(harness.appliedDocuments, [after, before, after], scenario.name)
        }
    }

    func testMoveSampleUIUsesCanonicalTransactionAndRefreshesSharedSelectionAndPreview() throws {
        let before = makeSampleKeymapEditableDocument(
            sampleIndices: [0, 1, 2],
            noteSampleMap: (0..<TrackerNoteKeyMap.maximumNoteValue).map { $0 / 32 },
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3)
        )
        let routingBefore = resolvedSampleContentIdentities(in: before)
        let patternBefore = before.patterns
        let token = EditorNoteAuditionPreviewToken(
            generation: 1,
            keyIdentity: .sampleEditorAudition,
            noteValue: SampleEditorAuditionRequestFactory.noteValue,
            selectedOctave: SampleEditorAuditionRequestFactory.octave
        )
        var stoppedTokens: [EditorNoteAuditionPreviewToken] = []
        let instrumentController = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let sampleController = SampleEditorWindowController(
            displayState: .editableDocument(before),
            auditionHandlers: .init(start: { token }, stop: { stoppedTokens.append($0); return true })
        )
        sampleController.synchronizeActivePreviewToken(token)
        let instrumentView = try XCTUnwrap(instrumentController.window?.contentView as? InstrumentEditorView)
        let sampleView = try XCTUnwrap(sampleController.window?.contentView as? SampleEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: {
                instrumentController.apply(displayState: .editableDocument($0))
                sampleController.apply(displayState: .editableDocument($0))
            }
        )
        let identity = UUID()
        let moveCoordinator = SampleEditorMoveCoordinator(
            contextProvider: {
                SampleEditorMoveContext(
                    documentIdentity: identity,
                    documentRevision: UInt64(harness.revision),
                    editContext: harness.context
                )
            },
            commitHandler: {
                harness.coordinator.applySampleSlotPermutation($0, instrumentAt: $1)
            }
        )

        let request = try XCTUnwrap(moveCoordinator.begin())
        XCTAssertEqual(request.sourceDisplay, "S03")
        XCTAssertTrue(moveCoordinator.confirm(
            operationToken: request.operationToken,
            destinationSampleIndex: 0
        ))

        let moved = try XCTUnwrap(harness.editableDocument)
        let movedInstrument = try XCTUnwrap(moved.instrumentPalette[1])
        XCTAssertEqual(movedInstrument.samples.map(\.name), ["Sample 3", "Sample 1", "Sample 2"])
        XCTAssertEqual(movedInstrument.samples.map(\.sampleIndex), [0, 1, 2])
        XCTAssertEqual(moved.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1))
        XCTAssertEqual(moved.patterns, patternBefore)
        XCTAssertEqual(resolvedSampleContentIdentities(in: moved), routingBefore)
        XCTAssertTrue(moved.controlPanelMetadata.selectedSampleDisplay.hasPrefix("S01 Sample 3"))
        XCTAssertEqual(instrumentView.displayState.selectedSampleSlot, 1)
        XCTAssertEqual(instrumentView.displayState.selectedSample?.name, "Sample 3")
        XCTAssertEqual(sampleView.displayState.selectedSampleSlot, 1)
        XCTAssertEqual(sampleView.displayState.selectedSample?.name, "Sample 3")
        XCTAssertEqual(sampleView.displayState.sampleSlots.map(\.slot), [1, 2, 3])
        XCTAssertTrue(sampleView.displayState.isClearEnabled)
        XCTAssertTrue(sampleView.displayState.isWAVLoadEnabled)
        XCTAssertTrue(sampleView.displayState.isMoveEnabled)
        XCTAssertEqual(stoppedTokens, [token])
        XCTAssertNil(sampleView.activeAuditionToken)
        XCTAssertEqual(harness.appliedDocuments, [moved])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Reorder Samples")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual([instrumentView.displayState.selectedSampleSlot, sampleView.displayState.selectedSampleSlot], [3, 3])
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Reorder Samples")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, moved)
        XCTAssertEqual([instrumentView.displayState.selectedSampleSlot, sampleView.displayState.selectedSampleSlot], [1, 1])
        XCTAssertEqual(harness.appliedDocuments, [moved, before, moved])
    }

    func testMoveSampleUISparseMoveIntoEmptyPreservesUnavailableRouteAndUndoRedo() throws {
        let mapReferences = [0, 1, 2]
        let map = (0..<TrackerNoteKeyMap.maximumNoteValue).map {
            mapReferences[$0 % mapReferences.count]
        }
        let before = makeSampleKeymapEditableDocument(
            sampleIndices: [0, 2],
            noteSampleMap: map,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3)
        )
        let routingBefore = resolvedSampleContentIdentities(in: before)
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        let identity = UUID()
        let moveCoordinator = SampleEditorMoveCoordinator(
            contextProvider: {
                SampleEditorMoveContext(
                    documentIdentity: identity,
                    documentRevision: UInt64(harness.revision),
                    editContext: harness.context
                )
            },
            commitHandler: {
                harness.coordinator.applySampleSlotPermutation($0, instrumentAt: $1)
            }
        )

        let request = try XCTUnwrap(moveCoordinator.begin())
        XCTAssertEqual(request.sourceDisplay, "S03")
        XCTAssertTrue(moveCoordinator.confirm(
            operationToken: request.operationToken,
            destinationSampleIndex: 1
        ))

        let moved = try XCTUnwrap(harness.editableDocument)
        let instrument = try XCTUnwrap(moved.instrumentPalette[1])
        XCTAssertEqual(instrument.samples.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(instrument.noteSampleMap?[0...2].map { $0 }, [0, 2, 1])
        XCTAssertEqual(moved.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(moved.sampleSlotPresentationRows(forInstrument: 1).map(\.sampleSlot), [1, 2, 3])
        XCTAssertTrue(moved.sampleSlotPresentationRows(forInstrument: 1)[2].isEmptyDestination)
        XCTAssertEqual(resolvedSampleContentIdentities(in: moved), routingBefore)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 2, instrument: instrument
        ))
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Reorder Samples")
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, moved)
        XCTAssertEqual(harness.appliedDocuments, [moved, before, moved])
    }

    func testSwapSampleUIRefreshesSharedSelectionMetadataOwnershipAndPreview() throws {
        let map = (0..<TrackerNoteKeyMap.maximumNoteValue).map { $0 / 32 }
        let before = makeSampleKeymapEditableDocument(
            sampleIndices: [0, 1, 2], noteSampleMap: map,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3)
        )
        let source = try XCTUnwrap(before.instrumentPalette[1]?.sample(mappedSampleIndex: 2))
        let routingBefore = resolvedSampleContentIdentities(in: before)
        let token = EditorNoteAuditionPreviewToken(
            generation: 1, keyIdentity: .sampleEditorAudition,
            noteValue: SampleEditorAuditionRequestFactory.noteValue,
            selectedOctave: SampleEditorAuditionRequestFactory.octave
        )
        var stoppedTokens: [EditorNoteAuditionPreviewToken] = []
        let instrumentController = InstrumentEditorWindowController(displayState: .editableDocument(before))
        let sampleController = SampleEditorWindowController(
            displayState: .editableDocument(before),
            auditionHandlers: .init(start: { token }, stop: { stoppedTokens.append($0); return true })
        )
        sampleController.synchronizeActivePreviewToken(token)
        let instrumentView = try XCTUnwrap(instrumentController.window?.contentView as? InstrumentEditorView)
        let sampleView = try XCTUnwrap(sampleController.window?.contentView as? SampleEditorView)
        let harness = EditHarness(
            context: .editable(document: before, isPlaybackActive: false),
            onApply: {
                instrumentController.apply(displayState: .editableDocument($0))
                sampleController.apply(displayState: .editableDocument($0))
            }
        )
        let identity = UUID()
        let coordinator = SampleEditorSwapCoordinator(
            contextProvider: {
                SampleEditorSwapContext(
                    documentIdentity: identity, documentRevision: UInt64(harness.revision),
                    editContext: harness.context
                )
            },
            commitHandler: { harness.coordinator.applySampleSlotPermutation($0, instrumentAt: $1) }
        )

        let request = try XCTUnwrap(coordinator.begin())
        XCTAssertTrue(coordinator.confirm(operationToken: request.operationToken, destinationSampleIndex: 0))

        let swapped = try XCTUnwrap(harness.editableDocument)
        let instrument = try XCTUnwrap(swapped.instrumentPalette[1])
        let selectedSample = source.reidentified(sampleIndex: 0)
        XCTAssertEqual(instrument.samples.map(\.name), ["Sample 3", "Sample 2", "Sample 1"])
        XCTAssertEqual(instrument.noteSampleMap, map.map { [2, 1, 0][$0] })
        XCTAssertEqual(swapped.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1))
        XCTAssertEqual(swapped.patterns, before.patterns)
        XCTAssertEqual(resolvedSampleContentIdentities(in: swapped), routingBefore)
        XCTAssertTrue(swapped.controlPanelMetadata.selectedSampleDisplay.hasPrefix("S01 Sample 3"))
        XCTAssertEqual(instrumentView.displayState.selectedSample?.representedSample, selectedSample)
        XCTAssertEqual(instrumentView.displayState.keymapRanges.map(\.sampleSlot), [3, 2, 1])
        XCTAssertEqual(sampleView.displayState.selectedSample, selectedSample)
        XCTAssertEqual(sampleView.displayState.waveformPCM, source.pcm)
        XCTAssertEqual(sampleView.displayState.panning, source.panning)
        XCTAssertEqual(sampleView.displayState.sampleSlots.map(\.slot), [1, 2, 3])
        XCTAssertTrue(sampleView.displayState.isSwapEnabled)
        XCTAssertEqual(stoppedTokens, [token])
        XCTAssertNil(sampleView.activeAuditionToken)
        XCTAssertEqual(harness.appliedDocuments, [swapped])
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Reorder Samples")

        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual([instrumentView.displayState.selectedSampleSlot, sampleView.displayState.selectedSampleSlot], [3, 3])
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, swapped)
        XCTAssertEqual([instrumentView.displayState.selectedSampleSlot, sampleView.displayState.selectedSampleSlot], [1, 1])
    }

    func testSwapSampleUIWithEmptyIdentityPreservesUnavailableRouteAndUndoRedo() throws {
        let map = (0..<TrackerNoteKeyMap.maximumNoteValue).map { [0, 1, 2][$0 % 3] }
        let before = makeSampleKeymapEditableDocument(
            sampleIndices: [0, 2], noteSampleMap: map,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3)
        )
        let routingBefore = resolvedSampleContentIdentities(in: before)
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        let identity = UUID()
        let coordinator = SampleEditorSwapCoordinator(
            contextProvider: {
                SampleEditorSwapContext(
                    documentIdentity: identity, documentRevision: UInt64(harness.revision),
                    editContext: harness.context
                )
            },
            commitHandler: { harness.coordinator.applySampleSlotPermutation($0, instrumentAt: $1) }
        )

        let request = try XCTUnwrap(coordinator.begin())
        XCTAssertTrue(coordinator.confirm(operationToken: request.operationToken, destinationSampleIndex: 1))

        let swapped = try XCTUnwrap(harness.editableDocument)
        let instrument = try XCTUnwrap(swapped.instrumentPalette[1])
        XCTAssertEqual(instrument.samples.map(\.name), ["Sample 1", "Sample 3"])
        XCTAssertEqual(instrument.samples.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(instrument.noteSampleMap?[0...2].map { $0 }, [0, 2, 1])
        XCTAssertEqual(swapped.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(swapped.sampleSlotPresentationRows(forInstrument: 1).map(\.isEmptyDestination), [false, false, true])
        XCTAssertEqual(resolvedSampleContentIdentities(in: swapped), routingBefore)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 2, instrument: instrument
        ))
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Reorder Samples")
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, swapped)
        XCTAssertEqual(harness.appliedDocuments, [swapped, before, swapped])
    }

    func testSampleSlotPermutationRejectsStateDWithoutFallbackMutationRevisionOrHistory() throws {
        let before = makeSampleKeymapEditableDocument(
            sampleIndices: [0],
            noteSampleMap: nil,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        )
        let permutation = try SampleSlotPermutation.move(from: 0, to: 1)
        let instrument = try XCTUnwrap(before.instrumentPalette[1])
        let fallbackIdentityBefore = PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 1,
            instrument: instrument,
            missingKeymapPolicy: .firstPlayableSample
        )?.sample.name
        var directDocument = before
        XCTAssertFalse(directDocument.applySampleSlotPermutation(permutation, instrumentAt: 0))
        XCTAssertEqual(directDocument, before)
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertFalse(harness.coordinator.applySampleSlotPermutation(permutation, instrumentAt: 0))
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(harness.editableDocument?.selection, before.selection)
        XCTAssertEqual(harness.revision, 0)
        XCTAssertTrue(harness.appliedDocuments.isEmpty)
        XCTAssertFalse(harness.undoManager.canUndo)
        let instrumentAfter = try XCTUnwrap(harness.editableDocument?.instrumentPalette[1])
        XCTAssertNil(instrumentAfter.noteSampleMap)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 1,
            instrument: instrumentAfter,
            missingKeymapPolicy: .firstPlayableSample
        )?.sample.name, fallbackIdentityBefore)
    }

    func testSampleSlotPermutationRejectsNoncanonicalDocumentsWithoutMutationOrHistory() throws {
        var mapWithInvalidValue = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
        mapWithInvalidValue[47] = SampleSlotPermutation.slotCount
        let cases: [(name: String, document: BlankTrackerDocument, instrumentIndex: Int)] = [
            ("zero samples and nil map", makeSampleKeymapEditableDocument(sampleIndices: [], noteSampleMap: nil), 0),
            ("zero samples and exact map", makeSampleKeymapEditableDocument(sampleIndices: []), 0),
            ("short map", makeSampleKeymapEditableDocument(noteSampleMap: Array(repeating: 0, count: 95)), 0),
            ("out-of-range map value", makeSampleKeymapEditableDocument(noteSampleMap: mapWithInvalidValue), 0),
            ("duplicate sample identity", makeSampleKeymapEditableDocument(sampleIndices: [0, 0]), 0),
            ("out-of-range sample identity", makeSampleKeymapEditableDocument(sampleIndices: [16]), 0),
            (
                "out-of-range selection",
                makeSampleKeymapEditableDocument(
                    selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 17)
                ),
                0
            ),
            (
                "different selected instrument",
                makeSampleKeymapEditableDocument(
                    selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)
                ),
                0
            ),
            ("unrepresented target", makeSampleKeymapEditableDocument(), 2),
            (
                "incomplete represented sample",
                makeSampleKeymapEditableDocument(sampleIndices: [0], emptySampleIndices: [0]),
                0
            ),
        ]
        let permutation = try SampleSlotPermutation.move(from: 0, to: 1)

        for testCase in cases {
            var directDocument = testCase.document
            XCTAssertFalse(
                directDocument.applySampleSlotPermutation(permutation, instrumentAt: testCase.instrumentIndex),
                testCase.name
            )
            XCTAssertEqual(directDocument, testCase.document, testCase.name)
            let harness = EditHarness(context: .editable(document: testCase.document, isPlaybackActive: false))
            XCTAssertFalse(
                harness.coordinator.applySampleSlotPermutation(permutation, instrumentAt: testCase.instrumentIndex),
                testCase.name
            )
            XCTAssertEqual(harness.editableDocument, testCase.document, testCase.name)
            XCTAssertEqual(harness.revision, 0, testCase.name)
            XCTAssertTrue(harness.appliedDocuments.isEmpty, testCase.name)
            XCTAssertFalse(harness.undoManager.canUndo, testCase.name)
        }
    }

    func testSampleSlotPermutationIdentityReadOnlyAndPlayingContextsCreateNoEdit() throws {
        let before = makeSampleKeymapEditableDocument()
        let identity = try SampleSlotPermutation.swap(0, 0)
        let identityHarness = EditHarness(context: .editable(document: before, isPlaybackActive: false))

        XCTAssertTrue(identity.isIdentity)
        var directDocument = before
        XCTAssertFalse(directDocument.applySampleSlotPermutation(identity, instrumentAt: Int.max))
        XCTAssertEqual(directDocument, before)
        XCTAssertFalse(identityHarness.coordinator.applySampleSlotPermutation(identity, instrumentAt: 0))
        XCTAssertEqual(identityHarness.editableDocument, before)
        XCTAssertEqual(identityHarness.revision, 0)
        XCTAssertFalse(identityHarness.undoManager.canUndo)

        let permutation = try SampleSlotPermutation.swap(0, 1)
        let blockedContexts: [EditableDocumentEditContext] = [
            .loadedReadOnly,
            .editable(document: before, isPlaybackActive: true),
        ]
        for context in blockedContexts {
            let harness = EditHarness(context: context)
            XCTAssertFalse(harness.coordinator.applySampleSlotPermutation(permutation, instrumentAt: 0))
            XCTAssertEqual(harness.revision, 0)
            XCTAssertTrue(harness.appliedDocuments.isEmpty)
            XCTAssertFalse(harness.undoManager.canUndo)
        }
    }

    func testAudioImportRejectsLoadedPlayingInvalidAndStaleDestinationsWithoutHistory() throws {
        let base = BlankTrackerDocument.makeDefault()
        let invalid = documentWithInvalidSelectedSampleDestination()
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
        let wrongSelection = documentWithSelectedInteriorEmptySample()
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
        var before = makeSampleKeymapEditableDocument()
        before.selectSample(2)
        before.pattern.rows[0][0] = XMPatternEventCell(
            note: 72, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0
        )
        before.pattern.rows[1][0] = XMPatternEventCell(
            note: 73, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0
        )
        let harness = EditHarness(context: .editable(document: before, isPlaybackActive: false))
        let originalExport = try EditableXMWriter().data(from: before)
        func resolvedSampleIndices(in document: BlankTrackerDocument?) -> [Int?] {
            guard let document else { return [] }
            return [UInt8(72), 73].map { noteValue in
                guard let request = InstrumentEditorAuditionRequestFactory.request(
                    noteValue: noteValue, selection: document.selection, sourceContext: .blankDocument
                ), case let .potentiallyAvailable(descriptor) = document.noteAuditionAvailability(for: request) else {
                    return nil
                }
                return descriptor.sampleIndex
            }
        }
        func scheduledSampleIndices(in document: BlankTrackerDocument?) -> [Int] {
            guard let document else { return [] }
            return RuntimeCMixerAdapterEventPlan.make(
                song: EditablePlaybackSongBuilder.build(from: document), sampleRate: 8_363
            ).events.compactMap { event -> Int? in
                guard case let .noteTrigger(_, _, mapping) = event.action else { return nil }
                return mapping.sampleIndex
            }
        }

        XCTAssertEqual(resolvedSampleIndices(in: before), [0, 0])
        XCTAssertEqual(scheduledSampleIndices(in: before), [0, 0])

        let outcome = try harness.coordinator.mapSampleToNoteRange(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 60, upperNote: 71
        ).get()
        let edited = try XCTUnwrap(harness.editableDocument)
        let editedMap = try XCTUnwrap(edited.instrumentPalette[1]?.noteSampleMap)

        XCTAssertEqual(outcome.changedNoteCount, 12)
        XCTAssertEqual(outcome.noteRange, 60...71)
        XCTAssertEqual(Array(editedMap[60...71]), Array(repeating: 1, count: 12))
        XCTAssertEqual(editedMap[59], 0)
        XCTAssertEqual(editedMap[72], 0)
        XCTAssertEqual(edited.selection, before.selection)
        XCTAssertEqual(harness.appliedDocuments, [edited])
        XCTAssertEqual(harness.revision, 1)
        XCTAssertEqual(harness.coordinator.undoMenuItemTitle, "Undo Map Sample to Note Range")
        XCTAssertEqual(resolvedSampleIndices(in: edited), [1, 0])
        XCTAssertEqual(scheduledSampleIndices(in: edited), [1, 0])
        var selectedS01 = edited
        selectedS01.selectSample(1)
        XCTAssertEqual(resolvedSampleIndices(in: selectedS01), [1, 0])
        XCTAssertEqual(scheduledSampleIndices(in: selectedS01), [1, 0])
        XCTAssertTrue(harness.coordinator.undo())
        XCTAssertEqual(harness.editableDocument, before)
        XCTAssertEqual(resolvedSampleIndices(in: harness.editableDocument), [0, 0])
        XCTAssertEqual(scheduledSampleIndices(in: harness.editableDocument), [0, 0])
        XCTAssertEqual(
            try EditableXMWriter().data(from: XCTUnwrap(harness.editableDocument)),
            originalExport
        )
        XCTAssertEqual(harness.coordinator.redoMenuItemTitle, "Redo Map Sample to Note Range")
        XCTAssertTrue(harness.coordinator.redo())
        XCTAssertEqual(harness.editableDocument, edited)
        XCTAssertEqual(resolvedSampleIndices(in: harness.editableDocument), [1, 0])
        XCTAssertEqual(scheduledSampleIndices(in: harness.editableDocument), [1, 0])
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

    private func expectedDocument(
        afterApplying permutation: SampleSlotPermutation,
        instrumentAt zeroBasedInstrumentIndex: Int,
        to document: BlankTrackerDocument
    ) throws -> BlankTrackerDocument {
        let instrumentIndex = zeroBasedInstrumentIndex + 1
        let instrument = try XCTUnwrap(document.instrumentPalette[instrumentIndex])
        let transformedSamples = try instrument.samples.map {
            $0.reidentified(sampleIndex: try permutation.apply(to: $0.sampleIndex))
        }.sorted { $0.sampleIndex < $1.sampleIndex }
        let transformedMap = try XCTUnwrap(instrument.noteSampleMap).map(permutation.apply(to:))
        var palette = document.instrumentPalette
        palette[instrumentIndex] = PlaybackInstrument(
            index: instrument.index,
            name: instrument.name,
            samples: transformedSamples,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            noteSampleMap: transformedMap
        )
        return BlankTrackerDocument(
            title: document.title,
            songLength: document.songLength,
            currentPosition: document.currentPosition,
            restartPosition: document.restartPosition,
            currentPatternIndex: document.currentPatternIndex,
            tempo: document.tempo,
            speed: document.speed,
            orderTable: document.orderTable,
            selection: TrackerEditorSelection(
                selectedInstrument: document.selection.selectedInstrument,
                selectedSample: try permutation.apply(to: document.selection.selectedSample - 1) + 1
            ),
            instrumentPalette: palette,
            patterns: document.patterns
        )
    }

    private func resolvedSampleContentIdentities(in document: BlankTrackerDocument?) -> [String?] {
        guard let instrument = document?.instrumentPalette[1] else { return [] }
        return (1...TrackerNoteKeyMap.maximumNoteValue).map { note in
            PlaybackInstrumentSampleResolver.resolveSample(
                instrumentIndex: 1,
                note: UInt8(note),
                instrument: instrument
            )?.sample.name
        }
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
    lazy var navigationCoordinator = EditableDocumentNavigationCoordinator(
        contextProvider: { [unowned self] in context },
        documentApplyHandler: { [unowned self] document, _ in
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
    samples: [PlaybackSample]? = nil,
    noteSampleMap: [Int]? = nil
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
        autoVibrato: autoVibrato,
        noteSampleMap: noteSampleMap
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

private func documentWithSelectedInteriorEmptySample() -> BlankTrackerDocument {
    var document = documentWithInstrumentName("Sparse", samples: [
        makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, name: "S01"),
        makePlaybackSample(instrumentIndex: 1, sampleIndex: 2, name: "S03"),
    ])
    document.selectSample(2)
    return document
}

private func documentWithInvalidSelectedSampleDestination() -> BlankTrackerDocument {
    let base = BlankTrackerDocument.makeDefault()
    return BlankTrackerDocument(
        title: base.title,
        songLength: base.songLength,
        currentPosition: base.currentPosition,
        restartPosition: base.restartPosition,
        currentPatternIndex: base.currentPatternIndex,
        tempo: base.tempo,
        speed: base.speed,
        orderTable: base.orderTable,
        selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 17),
        instrumentPalette: base.instrumentPalette,
        patterns: base.patterns
    )
}

private func documentWithThreeDistinctSamplesSelectedS02() -> BlankTrackerDocument {
    let first = makePlaybackSample(
        instrumentIndex: 1, sampleIndex: 0, name: "Pulse S01", pcm: [-0.25, 0.25]
    )
    let second = makePlaybackSample(
        instrumentIndex: 1, sampleIndex: 1, name: "Layer S02", pcm: [-0.5, 0, 0.5]
    )
    let third = makePlaybackSample(
        instrumentIndex: 1, sampleIndex: 2, name: "Impulse S03", pcm: [0.875]
    )
    var map = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
    for noteIndex in 32...63 { map[noteIndex] = 1 }
    for noteIndex in 64...95 { map[noteIndex] = 2 }
    var document = documentWithInstrumentName(
        "Layered", samples: [first, second, third], noteSampleMap: map
    )
    document.selectSample(2)
    return document
}

private func documentWithArrangedSongDataAndPalette() -> BlankTrackerDocument {
    let paletteDocument = documentWithThreeDistinctSamplesSelectedS02()
    var firstPattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 2)
    firstPattern.rows[1][0] = XMPatternEventCell(
        note: 49, instrument: 1, volumeColumn: 0x40, effectType: 0x0F, effectParam: 0x7D
    )
    var secondPattern = BlankTrackerDocument.makeEmptyPattern(index: 7, rowCount: 32, channels: 3)
    secondPattern.rows[2][1] = XMPatternEventCell(
        note: TrackerNoteKeyMap.keyOffNoteValue,
        instrument: 1,
        volumeColumn: 0x30,
        effectType: 0x0E,
        effectParam: 0x9C
    )
    return BlankTrackerDocument(
        title: "Arranged Song",
        songLength: 3,
        currentPosition: 1,
        restartPosition: 2,
        currentPatternIndex: 7,
        tempo: 144,
        speed: 3,
        orderTable: [0, 7, 0],
        selection: paletteDocument.selection,
        instrumentPalette: paletteDocument.instrumentPalette,
        patterns: [firstPattern, secondPattern]
    )
}

private func samplePCMBaseAddress(in document: BlankTrackerDocument) -> UInt? {
    guard let pcm = document.instrumentPalette[1]?.samples.first?.pcm else { return nil }
    return pcm.withUnsafeBufferPointer { buffer in
        buffer.baseAddress.map { UInt(bitPattern: $0) }
    }
}
