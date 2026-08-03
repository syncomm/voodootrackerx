import AppKit
import XCTest

@MainActor
final class InstrumentEditorWindowControllerTests: XCTestCase {
    func testNoDocumentStaysEmptyAndBlankDocumentShowsEditableI01WithEmptyS01Destination() {
        let noDocument = InstrumentEditorDisplayState.empty
        let blankDocument = InstrumentEditorDisplayState.editableDocument(.makeDefault())

        XCTAssertEqual(noDocument.source, .none)
        XCTAssertTrue(noDocument.isReadOnly)
        XCTAssertFalse(noDocument.isInstrumentNameEditable)
        XCTAssertFalse(noDocument.isSampleVolumeEditable)
        XCTAssertFalse(noDocument.isSampleRelativeNoteEditable)
        XCTAssertFalse(noDocument.isSampleFinetuneEditable)
        XCTAssertFalse(noDocument.isSamplePanningEditable)
        XCTAssertNil(noDocument.selectedInstrumentSlot)
        XCTAssertTrue(noDocument.instrumentSlots.isEmpty)
        XCTAssertTrue(noDocument.sampleSlots.isEmpty)
        XCTAssertNil(noDocument.emptySampleDestinationSlot)
        XCTAssertNil(noDocument.volumeEnvelope)
        XCTAssertNil(noDocument.panningEnvelope)
        XCTAssertNil(noDocument.autoVibrato)
        XCTAssertTrue(noDocument.keymapRanges.isEmpty)
        XCTAssertEqual(noDocument.emptyMessage, "No document instrument palette is available.")

        XCTAssertEqual(blankDocument.source, .editableDocument)
        XCTAssertFalse(blankDocument.isReadOnly)
        XCTAssertTrue(blankDocument.isInstrumentNameEditable)
        XCTAssertFalse(blankDocument.isSampleVolumeEditable)
        XCTAssertFalse(blankDocument.isSampleRelativeNoteEditable)
        XCTAssertFalse(blankDocument.isSampleFinetuneEditable)
        XCTAssertFalse(blankDocument.isSamplePanningEditable)
        XCTAssertEqual(blankDocument.selectedInstrumentSlot, 1)
        XCTAssertEqual(blankDocument.instrumentName, "(unnamed instrument)")
        XCTAssertEqual(blankDocument.instrumentNameEditValue, "")
        XCTAssertEqual(blankDocument.instrumentSlots.map(\.slotDisplay), ["I01"])
        XCTAssertEqual(blankDocument.instrumentSlots.map(\.sampleCount), [0])
        XCTAssertEqual(blankDocument.instrumentSlots.map(\.isSelected), [true])
        XCTAssertTrue(blankDocument.sampleSlots.isEmpty)
        XCTAssertEqual(blankDocument.emptySampleDestinationSlot, 1)
        XCTAssertEqual(blankDocument.selectedSampleSlot, 1)
        XCTAssertNil(blankDocument.selectedSample)
        XCTAssertEqual(blankDocument.volumeEnvelope, .disabled)
        XCTAssertEqual(blankDocument.panningEnvelope, .disabled)
        XCTAssertEqual(blankDocument.autoVibrato, .disabled)
        XCTAssertTrue(blankDocument.keymapRanges.isEmpty)
        XCTAssertEqual(blankDocument.emptyMessage, "S01 is an empty destination; no sample is represented.")
    }

    func testBlankInstrumentViewRendersSelectedDestinationWithoutSampleMetadataOrAudition() throws {
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(.makeDefault()))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let destination = try view.sampleRow(slot: 1)

        XCTAssertFalse(destination.isEnabled)
        XCTAssertEqual(destination.accessibilityLabel(), "S01 Empty destination")
        XCTAssertTrue(view.displayState.isInstrumentNameEditable)
        XCTAssertNil(view.displayState.selectedSample)
        XCTAssertFalse(view.displayState.isSampleVolumeEditable)
        XCTAssertFalse(view.displayState.isSampleRelativeNoteEditable)
        XCTAssertFalse(view.displayState.isSampleFinetuneEditable)
        XCTAssertFalse(view.displayState.isSamplePanningEditable)
    }

    func testLoadedPaletteShowsSelectedInstrumentNameAndSampleCount() {
        let palette = makeInstrumentPalette()
        let state = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )

        XCTAssertEqual(state.source, .loadedModule)
        XCTAssertTrue(state.isReadOnly)
        XCTAssertFalse(state.isInstrumentNameEditable)
        XCTAssertFalse(state.isSampleVolumeEditable)
        XCTAssertFalse(state.isSampleRelativeNoteEditable)
        XCTAssertFalse(state.isSampleFinetuneEditable)
        XCTAssertEqual(state.instrumentDisplay, "I02")
        XCTAssertEqual(state.instrumentName, "Lead")
        XCTAssertEqual(state.sampleCount, 2)
        XCTAssertEqual(state.selectedSampleDisplay, "S02")
        XCTAssertEqual(state.sampleSlots.map(\.slotDisplay), ["S01", "S02"])
        XCTAssertEqual(state.sampleSlots.map(\.isSelected), [false, true])
        XCTAssertEqual(state.instrumentSlots.map(\.slotDisplay), ["I01", "I02"])
        XCTAssertEqual(state.instrumentSlots.map(\.isSelected), [false, true])
    }

    func testSelectedInstrumentChangeProducesNewBoundState() {
        let song = makePlaybackSong(instruments: makeInstrumentPalette())
        let first = InstrumentEditorDisplayState.loadedModule(
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        )
        let second = InstrumentEditorDisplayState.loadedModule(
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)
        )

        XCTAssertEqual(first.instrumentDisplay, "I01")
        XCTAssertEqual(first.instrumentName, "Bass")
        XCTAssertEqual(second.instrumentDisplay, "I02")
        XCTAssertEqual(second.instrumentName, "Lead")
        XCTAssertEqual(first.instrumentSlots.map(\.isSelected), [true, false])
        XCTAssertEqual(second.instrumentSlots.map(\.isSelected), [false, true])
        XCTAssertNotEqual(first, second)
    }

    func testSelectedSampleChangeUpdatesSampleAndKeymapSelectionWithoutChangingInstrument() {
        let song = makePlaybackSong(instruments: makeInstrumentPalette())
        let first = InstrumentEditorDisplayState.loadedModule(
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)
        )
        let second = InstrumentEditorDisplayState.loadedModule(
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )

        XCTAssertEqual(first.instrumentDisplay, second.instrumentDisplay)
        XCTAssertEqual(first.instrumentName, second.instrumentName)
        XCTAssertEqual(first.sampleSlots.map(\.isSelected), [true, false])
        XCTAssertEqual(second.sampleSlots.map(\.isSelected), [false, true])
        XCTAssertEqual(first.keymapRanges.map(\.isSelected), [true, false])
        XCTAssertEqual(second.keymapRanges.map(\.isSelected), [false, true])
    }

    func testInstrumentRowsSelectMetadataMatrixThroughCanonicalStateWithoutUndo() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/instrument-metadata-matrix.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let songBefore = song
        let undoManager = UndoManager()
        var selection = TrackerEditorSelection.default
        var controller: InstrumentEditorWindowController!
        controller = InstrumentEditorWindowController(
            displayState: .loadedModule(playbackSong: song, selection: selection),
            instrumentSelectionHandler: { slot in
                guard let instrument = song.instrument(forInstrument: slot) else { return false }
                let updated = selection.withSelectedInstrument(
                    slot,
                    availableSampleSlots: instrument.availableSampleSlots
                )
                guard updated != selection else { return false }
                selection = updated
                return controller.apply(displayState: .loadedModule(playbackSong: song, selection: selection))
            }
        )

        let names = ["PAN00 VOL00 NEG", "PAN64 VOL16 FWD", "PAN128 VOL32 PP", "PAN192 VOL48 POS", "PAN255 VOL64 FWD"]
        let volumes = [0, 16, 32, 48, 64]
        let pannings: [UInt8] = [0, 64, 128, 192, 255]
        let relativeNotes = [-12, 5, -5, 12, 0]
        let finetunes = [-96, -32, 0, 48, 96]
        let loopTypes = [0, 1, 2, 0, 1]
        let bitDepths = [8, 16, 8, 16, 8]
        let loopRanges = ["—", "64..<320", "64..<320", "—", "128..<640"]

        for slot in 1...5 {
            let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
            XCTAssertTrue(try view.instrumentRow(slot: slot).accessibilityPerformPress())
            let selected = try XCTUnwrap(view.displayState.selectedSample)
            XCTAssertEqual(selection, TrackerEditorSelection(selectedInstrument: slot, selectedSample: 1))
            XCTAssertEqual(view.displayState.instrumentName, names[slot - 1])
            XCTAssertEqual(selected.volumeLevel, volumes[slot - 1])
            XCTAssertEqual(selected.panning, pannings[slot - 1])
            XCTAssertEqual(selected.relativeNote, relativeNotes[slot - 1])
            XCTAssertEqual(selected.finetune, finetunes[slot - 1])
            XCTAssertEqual(selected.loopType, loopTypes[slot - 1])
            XCTAssertEqual(selected.sourceBitDepthBits, bitDepths[slot - 1])
            XCTAssertEqual(selected.loopRangeDisplay, loopRanges[slot - 1])
            XCTAssertEqual(view.displayState.instrumentSlots.filter(\.isSelected).map(\.slot), [slot])
            XCTAssertEqual(view.displayState.sampleSlots.filter(\.isSelected).map(\.slot), [1])
            XCTAssertTrue(view.displayState.isReadOnly)
        }

        XCTAssertEqual(song, songBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testSampleRowsSelectKeymapFixtureWithoutChangingNoteDrivenSelection() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/instrument-envelopes-keymap.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let instrument = try XCTUnwrap(song.instrument(forInstrument: 1))
        var selection = TrackerEditorSelection.default
        var controller: InstrumentEditorWindowController!
        controller = InstrumentEditorWindowController(
            displayState: .loadedModule(playbackSong: song, selection: selection),
            sampleSelectionHandler: { slot in
                guard instrument.availableSampleSlots.contains(slot) else { return false }
                let updated = selection.withSelectedSample(slot)
                guard updated != selection else { return false }
                selection = updated
                return controller.apply(displayState: .loadedModule(playbackSong: song, selection: selection))
            }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)

        XCTAssertTrue(try view.sampleRow(slot: 2).accessibilityPerformPress())
        XCTAssertEqual(selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(view.displayState.selectedSample?.name, "HIGH TRIANGLE 16")
        XCTAssertEqual(view.displayState.sampleSlots.map(\.isSelected), [false, true])
        XCTAssertEqual(view.displayState.keymapRanges.map(\.isSelected), [false, true])

        let lowGraphicalRequest = try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
            noteValue: 48,
            selection: selection,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        let lowFocusedRequest = try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
            trackerKey: "z",
            selectedOctave: 3,
            selection: selection,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        let highFocusedRequest = try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
            trackerKey: "q",
            selectedOctave: 4,
            selection: selection,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        let lowAvailability = EditorNoteAuditionAvailabilityResolver.availability(for: lowFocusedRequest, loadedPlaybackSong: song)
        let highAvailability = EditorNoteAuditionAvailabilityResolver.availability(for: highFocusedRequest, loadedPlaybackSong: song)
        guard case let .potentiallyAvailable(lowDescriptor) = lowAvailability,
              case let .potentiallyAvailable(highDescriptor) = highAvailability else {
            return XCTFail("expected both mapped samples to be previewable")
        }

        XCTAssertEqual(lowGraphicalRequest.selectedSampleIndex, 2)
        XCTAssertEqual(lowFocusedRequest.selectedSampleIndex, 2)
        XCTAssertEqual(highFocusedRequest.selectedSampleIndex, 2)
        XCTAssertEqual([lowGraphicalRequest, lowFocusedRequest, highFocusedRequest].map(\.sampleResolution),
                       Array(repeating: .instrumentKeymap, count: 3))
        XCTAssertEqual(lowDescriptor.previewPanning, 64)
        XCTAssertEqual(highDescriptor.previewPanning, 192)
        XCTAssertEqual(PlaybackSamplePanningPolicy.plannedPan(lowDescriptor.previewPanning), -0.5)
        XCTAssertEqual(PlaybackSamplePanningPolicy.plannedPan(highDescriptor.previewPanning), 64.0 / 127.0, accuracy: 0.000_001)
        XCTAssertEqual(selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(song, try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path))
    }

    func testListRowsStaySelectionEnabledWhileMutationIsLoadedOrPlayingReadOnly() throws {
        let palette = makeInstrumentPalette()
        let states = [
            InstrumentEditorDisplayState.loadedModule(
                playbackSong: makePlaybackSong(instruments: palette),
                selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
            ),
            InstrumentEditorDisplayState.editableDocument(
                makeEditableDocument(palette: palette),
                isPlaybackActive: true
            ),
        ]

        for state in states {
            var instrumentIntents: [Int] = []
            var sampleIntents: [Int] = []
            let controller = InstrumentEditorWindowController(
                displayState: state,
                instrumentSelectionHandler: { instrumentIntents.append($0); return true },
                sampleSelectionHandler: { sampleIntents.append($0); return true }
            )
            let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
            let instrumentRow = try view.instrumentRow(slot: 1)
            let sampleRow = try view.sampleRow(slot: 1)

            XCTAssertTrue(instrumentRow.isEnabled)
            XCTAssertTrue(sampleRow.isEnabled)
            XCTAssertTrue(instrumentRow.performPrimarySelection())
            XCTAssertTrue(sampleRow.performPrimarySelection())
            XCTAssertEqual(instrumentIntents, [1])
            XCTAssertEqual(sampleIntents, [1])
            XCTAssertTrue(view.displayState.isReadOnly)
            XCTAssertTrue(controller.window?.makeFirstResponder(sampleRow) == true)
            XCTAssertTrue(controller.window?.firstResponder === sampleRow)
        }
    }

    func testSelectedInstrumentRowScrollsIntoView() throws {
        let palette = Dictionary(uniqueKeysWithValues: (1...12).map { slot in
            (slot, PlaybackInstrument(
                index: slot,
                name: "Instrument \(slot)",
                samples: [makeInstrumentEditorSample(instrument: slot, sample: 0, name: "Sample \(slot)")]
            ))
        })
        let controller = InstrumentEditorWindowController(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 12, selectedSample: 1)
        ))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let row = try view.instrumentRow(slot: 12)
        let scrollView = try XCTUnwrap(row.enclosingScrollView)

        scrollView.layoutSubtreeIfNeeded()
        XCTAssertTrue(scrollView.documentVisibleRect.intersects(row.frame))
    }

    func testSelectionPreviewLifecycleUsesOneCancellationPath() {
        var onScreenCancelCount = 0
        var fallbackCancelCount = 0
        for (onScreenNote, activePreview) in [(true, true), (false, true), (false, false)] {
            InstrumentEditorPreviewLifecycle.cancelForSelectionChange(
                cancelOnScreenNote: { onScreenCancelCount += 1; return onScreenNote },
                hasActivePreview: { activePreview },
                cancelPreview: { fallbackCancelCount += 1 }
            )
        }
        XCTAssertEqual(onScreenCancelCount, 3)
        XCTAssertEqual(fallbackCancelCount, 2)
    }

    func testListClickPolicyAndKeymapCopyRemainNonMutatingAndAccurate() {
        XCTAssertTrue(InstrumentEditorListRowControl.acceptsPrimarySelection(buttonNumber: 0, clickCount: 1))
        XCTAssertFalse(InstrumentEditorListRowControl.acceptsPrimarySelection(buttonNumber: 0, clickCount: 2))
        XCTAssertFalse(InstrumentEditorListRowControl.acceptsPrimarySelection(buttonNumber: 1, clickCount: 1))
        XCTAssertEqual(
            InstrumentEditorCopy.keymapSummary,
            "FULL 96-NOTE COMMITTED OWNERSHIP · USE MAP RANGE… TO EDIT · PIANO AUDITIONS"
        )
        XCTAssertEqual(InstrumentEditorCopy.auditionKeyboard, "AUDITION KEYBOARD · CLICK / DRAG TO PREVIEW")
    }

    func testRepresentedEnvelopeAndKeymapRangesRemainReadOnlyDisplayData() throws {
        let song = makePlaybackSong(instruments: makeInstrumentPalette())
        let before = song
        let state = InstrumentEditorDisplayState.loadedModule(
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )
        let envelope = try XCTUnwrap(state.volumeEnvelope)

        XCTAssertTrue(state.isReadOnly)
        XCTAssertTrue(envelope.enabled)
        XCTAssertEqual(envelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 0),
            PlaybackEnvelopePoint(tick: 12, value: 64),
            PlaybackEnvelopePoint(tick: 36, value: 24),
        ])
        XCTAssertEqual(envelope.sustainPointIndex, 1)
        XCTAssertEqual(envelope.loopStartPointIndex, 1)
        XCTAssertEqual(envelope.loopEndPointIndex, 2)
        XCTAssertEqual(envelope.fadeout, 128)
        XCTAssertEqual(state.panningEnvelope, makeInstrumentEditorPanningEnvelope())
        XCTAssertEqual(state.envelope(for: .volume)?.pointCount, 3)
        XCTAssertEqual(state.envelope(for: .volume)?.fadeout, 128)
        XCTAssertEqual(state.envelope(for: .panning)?.pointCount, 4)
        XCTAssertEqual(state.envelope(for: .panning)?.enabled, true)
        XCTAssertNil(state.envelope(for: .panning)?.fadeout)
        XCTAssertEqual(state.keymapRanges.map(\.startNote), [1, 49])
        XCTAssertEqual(state.keymapRanges.map(\.endNote), [48, 96])
        XCTAssertEqual(state.keymapRanges.map(\.sampleDisplay), ["S01", "S02"])
        XCTAssertEqual(state.keymapRanges.map(\.isSelected), [false, true])
        XCTAssertEqual(song, before)
    }

    func testEnvelopeSelectorDefaultsToVolumeAndSwitchesDisplayWithoutMutationOrUndo() throws {
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        let before = document
        var currentDocument = document
        let undoManager = UndoManager()
        let coordinator = EditableDocumentEditCoordinator(
            undoManager: undoManager,
            contextProvider: { .editable(document: currentDocument, isPlaybackActive: false) },
            documentApplyHandler: { currentDocument = $0 }
        )
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            instrumentNameEditHandler: { coordinator.renameInstrument(at: $0, name: $1) }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let nameField = try XCTUnwrap(view.instrumentEditorNameField)
        nameField.stringValue = "Uncommitted draft"

        XCTAssertEqual(view.envelopeDisplayMode, .volume)
        XCTAssertEqual(try view.envelopeSelector(.volume).editorRole, .selected)
        XCTAssertEqual(try view.envelopeSelector(.panning).editorRole, .normal)

        try view.envelopeSelector(.panning).performClick(nil)

        XCTAssertEqual(view.envelopeDisplayMode, .panning)
        XCTAssertEqual(try view.envelopeSelector(.volume).editorRole, .normal)
        XCTAssertEqual(try view.envelopeSelector(.panning).editorRole, .selected)
        XCTAssertEqual(view.displayState, .editableDocument(document))
        XCTAssertEqual(currentDocument, before)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(nameField === view.instrumentEditorNameField)
        XCTAssertEqual(nameField.stringValue, "Uncommitted draft")

        try view.envelopeSelector(.volume).performClick(nil)

        XCTAssertEqual(view.envelopeDisplayMode, .volume)
        XCTAssertEqual(try view.envelopeGraph().displayMode, .volume)
        XCTAssertEqual(try view.envelopeReadout(.pointCount).stringValue, "03")
        XCTAssertEqual(try view.envelopeReadout(.fadeout).stringValue, "0080")
        XCTAssertEqual(currentDocument, before)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testPanningSelectionDisplaysRepresentedReadoutsAndKeepsEditingInert() throws {
        let palette = makeInstrumentPalette()
        let selection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        let states = [
            InstrumentEditorDisplayState.loadedModule(
                playbackSong: makePlaybackSong(instruments: palette),
                selection: selection
            ),
            InstrumentEditorDisplayState.editableDocument(makeEditableDocument(palette: palette)),
        ]

        for state in states {
            let controller = InstrumentEditorWindowController(displayState: state)
            let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
            try view.envelopeSelector(.panning).performClick(nil)
            let envelopePanel = try view.identifiedView(InstrumentEditorViewIdentifier.envelopePanel)
            let graph = try view.envelopeGraph()

            XCTAssertEqual(graph.displayMode, .panning)
            XCTAssertEqual(graph.envelope?.points, makeInstrumentEditorPanningEnvelope().points)
            XCTAssertNil(graph.emptyStateMessage)
            XCTAssertNil(graph.hitTest(.zero))
            XCTAssertEqual(try envelopePanel.envelopeReadout(.pointCount).stringValue, "04")
            XCTAssertEqual(try envelopePanel.envelopeReadout(.sustainState).stringValue, "ON")
            XCTAssertEqual(try envelopePanel.envelopeReadout(.sustainPoint).stringValue, "03")
            XCTAssertEqual(try envelopePanel.envelopeReadout(.loopState).stringValue, "ON")
            XCTAssertEqual(try envelopePanel.envelopeReadout(.loopStart).stringValue, "01")
            XCTAssertEqual(try envelopePanel.envelopeReadout(.loopEnd).stringValue, "04")
            XCTAssertEqual(try envelopePanel.envelopeReadout(.fadeout).stringValue, "—")

            let editingControls = envelopePanel.instrumentEditorDescendants.compactMap { $0 as? NSControl }.filter {
                $0.identifier?.rawValue.hasPrefix(InstrumentEditorViewIdentifier.futureControlPrefix) == true
            }
            XCTAssertEqual(Set(editingControls.compactMap { ($0 as? NSButton)?.title }), ["+ ADD PT", "DEL PT", "ON"])
            XCTAssertTrue(editingControls.allSatisfy { !$0.isEnabled && $0.target == nil && $0.action == nil })
        }
    }

    func testPanningSelectionShowsCleanNoInstrumentAndDisabledEmptyStates() throws {
        let noInstrumentController = InstrumentEditorWindowController(displayState: .empty)
        let noInstrumentView = try XCTUnwrap(noInstrumentController.window?.contentView as? InstrumentEditorView)
        try noInstrumentView.envelopeSelector(.panning).performClick(nil)
        let noInstrumentGraph = try noInstrumentView.envelopeGraph()

        XCTAssertNil(noInstrumentGraph.envelope)
        XCTAssertEqual(noInstrumentGraph.emptyStateMessage, "NO PANNING ENVELOPE REPRESENTED")
        XCTAssertEqual(try noInstrumentView.envelopeReadout(.pointCount).stringValue, "00")

        let disabledState = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: makeInstrumentPalette()),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        )
        let disabledController = InstrumentEditorWindowController(displayState: disabledState)
        let disabledView = try XCTUnwrap(disabledController.window?.contentView as? InstrumentEditorView)
        try disabledView.envelopeSelector(.panning).performClick(nil)
        let disabledGraph = try disabledView.envelopeGraph()

        XCTAssertEqual(disabledGraph.envelope?.enabled, false)
        XCTAssertTrue(disabledGraph.envelope?.points.isEmpty == true)
        XCTAssertEqual(disabledGraph.emptyStateMessage, "PANNING ENVELOPE DISABLED / EMPTY")
        XCTAssertEqual(try disabledView.envelopeReadout(.pointCount).stringValue, "00")
    }

    func testPanningModePersistsAcrossSelectionAndDocumentRefreshTransitions() throws {
        let palette = makeInstrumentPalette()
        let controller = InstrumentEditorWindowController(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        try view.envelopeSelector(.panning).performClick(nil)

        XCTAssertEqual(try view.envelopeGraph().emptyStateMessage, "PANNING ENVELOPE DISABLED / EMPTY")

        XCTAssertTrue(controller.apply(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )))
        XCTAssertEqual(view.envelopeDisplayMode, .panning)
        XCTAssertEqual(try view.envelopeGraph().envelope?.points.count, 4)

        XCTAssertTrue(controller.apply(displayState: .empty))
        XCTAssertEqual(view.envelopeDisplayMode, .panning)
        XCTAssertEqual(try view.envelopeGraph().emptyStateMessage, "NO PANNING ENVELOPE REPRESENTED")

        XCTAssertTrue(controller.apply(displayState: .editableDocument(makeEditableDocument(palette: palette))))
        XCTAssertEqual(view.envelopeDisplayMode, .panning)
        XCTAssertEqual(try view.envelopeGraph().envelope?.points.count, 4)
        XCTAssertTrue(view.displayState.isInstrumentNameEditable)
    }

    func testKeymapRangeColorIdentityFollowsSampleSlotAcrossDisjointRanges() {
        let instrument = PlaybackInstrument(
            index: 4,
            name: "Split",
            samples: [
                makeInstrumentEditorSample(instrument: 4, sample: 0, name: "Low and High"),
                makeInstrumentEditorSample(instrument: 4, sample: 1, name: "Middle"),
            ],
            noteSampleMap: Array(repeating: 0, count: 32)
                + Array(repeating: 1, count: 32)
                + Array(repeating: 0, count: 32)
        )
        let state = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: [4: instrument]),
            selection: TrackerEditorSelection(selectedInstrument: 4, selectedSample: 1)
        )

        XCTAssertEqual(state.keymapRanges.map(\.sampleDisplay), ["S01", "S02", "S01"])
        XCTAssertEqual(state.keymapRanges.map(\.colorIndex), [0, 1, 0])
    }

    func testKeymapSummaryGeometryPinsC5ThroughB5BeforeC6() throws {
        let bounds = NSRect(x: 10, y: 4, width: 962, height: 20)
        let drawable = try XCTUnwrap(InstrumentKeymapSummaryGeometry.drawableBounds(in: bounds))
        let full = try XCTUnwrap(InstrumentKeymapSummaryGeometry.rect(for: 0...95, in: bounds))
        let c5ThroughB5 = try XCTUnwrap(InstrumentKeymapSummaryGeometry.rect(for: 60...71, in: bounds))
        let c6ThroughB7 = try XCTUnwrap(InstrumentKeymapSummaryGeometry.rect(for: 72...95, in: bounds))

        XCTAssertEqual(drawable, NSRect(x: 11, y: 5, width: 960, height: 18))
        XCTAssertEqual(full, drawable)
        XCTAssertEqual(c5ThroughB5, NSRect(x: 611, y: 5, width: 120, height: 18))
        XCTAssertEqual(c5ThroughB5.maxX, c6ThroughB7.minX)
    }

    func testKeymapSummaryIsCommittedOwnershipOnlyAndRejectsHitTesting() throws {
        let document = makeInstrumentEditorRangeDocument()
        let before = document
        let undoManager = UndoManager()
        let state = InstrumentEditorDisplayState.editableDocument(document)
        let strip = InstrumentEditorKeymapRangeView(
            frame: NSRect(x: 0, y: 0, width: 962, height: 20),
            ranges: state.keymapRanges
        )

        XCTAssertEqual(strip.ownershipRects.count, state.keymapRanges.count)
        XCTAssertFalse(strip.acceptsFirstResponder)
        XCTAssertNil(strip.hitTest(NSPoint(x: strip.bounds.midX, y: strip.bounds.midY)))
        XCTAssertEqual(strip.accessibilityLabel(), "Instrument sample keymap")
        XCTAssertEqual(strip.accessibilityValue() as? String, "Committed ownership: C-0 through B-7 uses S01")
        XCTAssertEqual(strip.accessibilityHelp(), "Committed 96-note sample ownership; use Map Range to edit")
        XCTAssertEqual(strip.toolTip, "Committed 96-note sample ownership; use MAP RANGE… to edit")
        XCTAssertEqual(document, before)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testOwnershipSummaryCannotCreateRangePrefillRevisionOrHistory() throws {
        let document = makeInstrumentEditorRangeDocument()
        let before = document
        let undoManager = UndoManager()
        var receivedFocusedNotes: [UInt8?] = []
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            keymapRangeAssignmentHandler: { focusedNote in
                receivedFocusedNotes.append(focusedNote)
                return true
            }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let strip = try view.keymapRangeStrip()
        let labels = Set(view.instrumentEditorDescendants.compactMap { ($0 as? NSTextField)?.stringValue })

        XCTAssertNil(strip.hitTest(NSPoint(x: strip.bounds.midX, y: strip.bounds.midY)))
        XCTAssertTrue(labels.contains(InstrumentEditorCopy.keymapSummary))
        try view.keymapRangeAssignmentButton().performClick(nil)
        XCTAssertEqual(receivedFocusedNotes, [nil])
        XCTAssertEqual(document, before)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testRangeAssignmentEligibilityRequiresStoppedEditableRepresentedSampleAndCanonicalMap() {
        let editable = makeInstrumentEditorRangeDocument()
        XCTAssertTrue(InstrumentEditorDisplayState.editableDocument(editable).isKeymapRangeAssignmentEnabled)
        let disabledStates: [InstrumentEditorDisplayState] = [
            .loadedModule(
                playbackSong: makePlaybackSong(instruments: editable.instrumentPalette),
                selection: editable.selection
            ),
            .editableDocument(editable, isPlaybackActive: true),
            .editableDocument(editable, allowsKeymapRangeAssignment: false),
            .editableDocument(.makeDefault()),
            .editableDocument(makeInstrumentEditorRangeDocument(
                selection: TrackerEditorSelection(selectedInstrument: 3, selectedSample: 2)
            )),
            .editableDocument(makeInstrumentEditorRangeDocument(
                noteSampleMap: Array(repeating: 0, count: 95)
            )),
            .editableDocument(makeInstrumentEditorRangeDocument(samples: [
                makeInstrumentEditorSample(instrument: 2, sample: 0, name: "S01"),
            ])),
        ]
        XCTAssertTrue(disabledStates.allSatisfy { !$0.isKeymapRangeAssignmentEnabled })
    }

    func testLoadedRangeAssignmentIsVisiblyAndDefensivelyUnavailable() throws {
        var protectedDocument = makeInstrumentEditorRangeDocument()
        let before = protectedDocument
        let undoManager = UndoManager()
        let undoTarget = NSObject()
        var revision = 0
        var handlerCallCount = 0
        let controller = InstrumentEditorWindowController(
            displayState: .loadedModule(
                playbackSong: makePlaybackSong(instruments: protectedDocument.instrumentPalette),
                selection: protectedDocument.selection
            ),
            keymapRangeAssignmentHandler: { _ in
                handlerCallCount += 1
                revision += 1
                protectedDocument.selectSample(1)
                undoManager.registerUndo(withTarget: undoTarget) { _ in }
                return true
            }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let button = try view.keymapRangeAssignmentButton()
        let strip = try view.keymapRangeStrip()
        let fieldValues = Set(view.instrumentEditorDescendants.compactMap { ($0 as? NSTextField)?.stringValue })

        XCTAssertFalse(button.isEnabled)
        XCTAssertLessThan(button.alphaValue, 1)
        XCTAssertNil(button.target)
        XCTAssertNil(button.action)
        XCTAssertFalse(button.isAccessibilityEnabled())
        XCTAssertTrue(fieldValues.contains("READ-ONLY"))
        XCTAssertTrue(fieldValues.contains("EDITING UNAVAILABLE"))
        XCTAssertNil(strip.hitTest(NSPoint(x: strip.bounds.midX, y: strip.bounds.midY)))
        XCTAssertEqual(strip.accessibilityValue() as? String, "Committed ownership: C-0 through B-7 uses S01")

        button.performClick(nil)
        button.isEnabled = true
        button.target = view
        button.action = NSSelectorFromString("requestKeymapRangeAssignment:")
        button.performClick(nil)

        XCTAssertEqual(handlerCallCount, 0)
        XCTAssertEqual(revision, 0)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(protectedDocument, before)
    }

    func testRangeAssignmentGatingRefreshesAcrossEditableLoadedCopyAndPlaybackStates() throws {
        let document = makeInstrumentEditorRangeDocument()
        var handlerCallCount = 0
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            keymapRangeAssignmentHandler: { _ in handlerCallCount += 1; return true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)

        var button = try view.keymapRangeAssignmentButton()
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.alphaValue, 1)
        XCTAssertNotNil(button.target)
        XCTAssertNotNil(button.action)

        XCTAssertTrue(controller.apply(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: document.instrumentPalette),
            selection: document.selection
        )))
        button = try view.keymapRangeAssignmentButton()
        var fieldValues = Set(view.instrumentEditorDescendants.compactMap { ($0 as? NSTextField)?.stringValue })
        XCTAssertFalse(button.isEnabled)
        XCTAssertLessThan(button.alphaValue, 1)
        XCTAssertNil(button.target)
        XCTAssertNil(button.action)
        XCTAssertTrue(fieldValues.contains("READ-ONLY"))
        XCTAssertTrue(fieldValues.contains("EDITING UNAVAILABLE"))

        XCTAssertTrue(controller.apply(displayState: .editableDocument(document)))
        button = try view.keymapRangeAssignmentButton()
        fieldValues = Set(view.instrumentEditorDescendants.compactMap { ($0 as? NSTextField)?.stringValue })
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.alphaValue, 1)
        XCTAssertNotNil(button.target)
        XCTAssertNotNil(button.action)
        XCTAssertFalse(fieldValues.contains("READ-ONLY"))
        XCTAssertFalse(fieldValues.contains("EDITING UNAVAILABLE"))
        button.performClick(nil)
        XCTAssertEqual(handlerCallCount, 1)

        XCTAssertTrue(controller.apply(displayState: .editableDocument(
            document, isPlaybackActive: true
        )))
        button = try view.keymapRangeAssignmentButton()
        XCTAssertFalse(button.isEnabled)
        XCTAssertNil(button.target)
        XCTAssertNil(button.action)
        XCTAssertEqual(handlerCallCount, 1)
    }

    func testRangeAssignmentConfirmationGateDoesNotInvokeCoordinatorForReadOnlyContext() {
        var protectedDocument = makeInstrumentEditorRangeDocument()
        let before = protectedDocument
        let undoManager = UndoManager()
        let undoTarget = NSObject()
        var revision = 0
        var coordinatorCallCount = 0
        let readOnly = InstrumentKeymapRangeAssignmentContext(
            documentIdentity: nil,
            documentRevision: 7,
            editContext: .loadedReadOnly,
            hasConflictingModalSheet: false
        )

        let rejected: Result<SampleKeymapRangeAssignmentOutcome, SampleKeymapRangeEditFailure>? =
            InstrumentKeymapRangeAssignmentConfirmationGate.perform(in: readOnly) {
                coordinatorCallCount += 1
                revision += 1
                protectedDocument.selectSample(1)
                undoManager.registerUndo(withTarget: undoTarget) { _ in }
                return .failure(.editApplicationRejected)
            }

        XCTAssertNil(rejected)
        XCTAssertEqual(coordinatorCallCount, 0)
        XCTAssertEqual(revision, 0)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(protectedDocument, before)

        let editable = makeRangeAssignmentContext(UUID(), 7, protectedDocument)
        let accepted = InstrumentKeymapRangeAssignmentConfirmationGate.perform(in: editable) {
            coordinatorCallCount += 1
            return Result<SampleKeymapRangeAssignmentOutcome, SampleKeymapRangeEditFailure>.success(.init(
                instrumentIndex: 1, sampleIndex: 1, noteRange: 48...59, changedNoteCount: 12
            ))
        }
        XCTAssertEqual(try? accepted?.get().noteRange, 48...59)
        XCTAssertEqual(coordinatorCallCount, 1)
    }

    func testRangeAssignmentSheetDismissalRefreshesEligibilityOnNextMainQueueTurn() async throws {
        let document = makeInstrumentEditorRangeDocument()
        var hasConflictingModalSheet = true
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(
                document, allowsKeymapRangeAssignment: !hasConflictingModalSheet
            ),
            keymapRangeAssignmentHandler: { _ in true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let button = try view.keymapRangeAssignmentButton()
        let refreshed = expectation(description: "range eligibility refreshed after sheet dismissal")

        InstrumentKeymapRangeAssignmentSheetLifecycle.refreshAfterDismissal {
            _ = controller.apply(displayState: .editableDocument(
                document, allowsKeymapRangeAssignment: !hasConflictingModalSheet
            ))
            refreshed.fulfill()
        }

        XCTAssertFalse(button.isEnabled)
        hasConflictingModalSheet = false
        await fulfillment(of: [refreshed], timeout: 1)
        let refreshedButton = try view.keymapRangeAssignmentButton()
        XCTAssertTrue(refreshedButton.isEnabled)
        XCTAssertNotNil(refreshedButton.target)
        XCTAssertNotNil(refreshedButton.action)
    }

    func testRangeAssignmentButtonPublishesFocusedNoteAndAccessibilityWithoutMutatingSelection() throws {
        let document = makeInstrumentEditorRangeDocument()
        var focusedNote: UInt8?
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            keymapRangeAssignmentHandler: { value in focusedNote = value; return true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let button = try view.keymapRangeAssignmentButton()

        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.title, "MAP RANGE…")
        XCTAssertEqual(button.accessibilityLabel(), "Map selected sample to note range")
        view.synchronizeActivePreviewToken(.init(
            generation: 1,
            keyIdentity: .instrumentEditorKeyboard,
            noteValue: 53,
            selectedOctave: 4
        ))
        button.performClick(nil)

        XCTAssertEqual(focusedNote, 53)
        _ = view.shiftKeyboardVisibleRange(.higher)
        _ = view.shiftKeyboardVisibleRange(.higher)
        _ = view.shiftKeyboardVisibleRange(.higher)
        focusedNote = 96
        button.performClick(nil)
        XCTAssertNil(focusedNote)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2))
    }

    func testRangeAssignmentDefaultPolicyUsesFocusedNoteThenSelectedOctaveThenC4() {
        XCTAssertEqual(InstrumentKeymapRangeDefaultPolicy.noteRange(focusedNote: 53, selectedOctave: 6), 52...52)
        XCTAssertEqual(InstrumentKeymapRangeDefaultPolicy.noteRange(focusedNote: nil, selectedOctave: 6), 72...83)
        XCTAssertEqual(InstrumentKeymapRangeDefaultPolicy.noteRange(focusedNote: nil, selectedOctave: nil), 48...59)
        XCTAssertEqual(InstrumentKeymapRangeDefaultPolicy.noteRange(focusedNote: 0, selectedOctave: 8), 48...59)
    }

    func testRangeAssignmentSheetSpansCanonicalNotesAndDisablesReversedRange() throws {
        let sheet = InstrumentKeymapRangeAssignmentSheet(request: .init(
            operationToken: UUID(), sampleDisplay: "S02", initialNoteRange: 48...59
        ))
        let boundaries = [(0, "C-0"), (48, "C-4"), (60, "C-5"),
                          (71, "B-5"), (72, "C-6"), (95, "B-7")]

        XCTAssertEqual(sheet.firstNotePopup.numberOfItems, 96)
        for (index, title) in boundaries {
            XCTAssertEqual(sheet.firstNotePopup.itemTitle(at: index), title)
            XCTAssertEqual(sheet.lastNotePopup.indexOfItem(withTitle: title), index)
        }
        XCTAssertEqual([sheet.firstNote, sheet.lastNote], [48, 59])
        XCTAssertTrue(sheet.mapButton.isEnabled)
        XCTAssertEqual(
            [sheet.firstNotePopup.accessibilityLabel(), sheet.lastNotePopup.accessibilityLabel(),
             sheet.mapButton.accessibilityLabel()],
            ["First note", "Last note", "Map selected sample"]
        )
        XCTAssertEqual(sheet.summaryLabel.accessibilityLabel(), "Selected sample S02. Inclusive range C-4 through B-4.")

        sheet.selectNoteRange(lowerNote: 48, upperNote: 48)
        XCTAssertEqual([sheet.firstNote, sheet.lastNote], [48, 48])
        XCTAssertEqual(sheet.summaryLabel.stringValue, "S02 · C-4 THROUGH C-4 · INCLUSIVE")
        sheet.selectNoteRange(lowerNote: 60, upperNote: 71)
        XCTAssertEqual([sheet.firstNote, sheet.lastNote], [60, 71])
        XCTAssertEqual(sheet.summaryLabel.accessibilityLabel(), "Selected sample S02. Inclusive range C-5 through B-5.")
        XCTAssertTrue(sheet.mapButton.isEnabled)
        sheet.selectNoteRange(lowerNote: 72, upperNote: 71)
        XCTAssertFalse(sheet.mapButton.isEnabled)
        sheet.selectNoteRange(lowerNote: 95, upperNote: 95)
        XCTAssertTrue(sheet.mapButton.isEnabled)
        XCTAssertEqual([sheet.firstNote, sheet.lastNote], [95, 95])
        XCTAssertEqual(sheet.summaryLabel.accessibilityLabel(), "Selected sample S02. Inclusive range B-7 through B-7.")
    }

    func testRangeAssignmentCoordinatorCapturesTargetCommitsOnceAndCancelsCleanly() throws {
        let identity = UUID()
        var document = makeInstrumentEditorRangeDocument()
        var commitCalls: [(Int, Int, Int, Int)] = []
        let coordinator = InstrumentKeymapRangeAssignmentCoordinator(
            contextProvider: { makeRangeAssignmentContext(identity, 4, document) },
            commitHandler: { instrument, sample, lower, upper in
                commitCalls.append((instrument, sample, lower, upper))
                return .success(.init(
                    instrumentIndex: instrument,
                    sampleIndex: sample,
                    noteRange: lower...upper,
                    changedNoteCount: upper - lower + 1
                ))
            }
        )
        let request = try XCTUnwrap(coordinator.begin(focusedNote: nil, selectedOctave: 4))
        document.selectSample(1)

        XCTAssertEqual(request.sampleDisplay, "S02")
        XCTAssertEqual(request.initialNoteRange, 48...59)
        let sheet = InstrumentKeymapRangeAssignmentSheet(request: request)
        sheet.selectNoteRange(lowerNote: 60, upperNote: 71)
        let outcome = try coordinator.commit(
            operationToken: request.operationToken,
            lowerNote: sheet.firstNote,
            upperNote: sheet.lastNote
        ).get()
        XCTAssertEqual(outcome.noteRange, 60...71)
        XCTAssertEqual(outcome.changedNoteCount, 12)
        XCTAssertEqual(commitCalls.map { [$0.0, $0.1, $0.2, $0.3] }, [[1, 1, 60, 71]])
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))

        let cancelled = try XCTUnwrap(coordinator.begin(focusedNote: nil, selectedOctave: 3))
        XCTAssertTrue(coordinator.cancel(operationToken: cancelled.operationToken))
        XCTAssertEqual(commitCalls.count, 1)
    }

    func testRangeAssignmentCoordinatorRejectsStaleContextsBeforeFoundationCommit() throws {
        let originalIdentity = UUID()
        let originalDocument = makeInstrumentEditorRangeDocument()
        let staleContexts: [(InstrumentKeymapRangeAssignmentContext, SampleKeymapRangeEditFailure)] = [
            (.init(
                documentIdentity: nil, documentRevision: 9, editContext: .loadedReadOnly,
                hasConflictingModalSheet: false
            ), .readOnlyDocument),
            (makeRangeAssignmentContext(UUID(), 9, originalDocument), .noEditableDocument),
            (makeRangeAssignmentContext(originalIdentity, 10, originalDocument), .noEditableDocument),
            (makeRangeAssignmentContext(originalIdentity, 9, originalDocument, isPlaying: true), .playbackActive),
            (makeRangeAssignmentContext(originalIdentity, 9, makeInstrumentEditorRangeDocument(
                selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
            )), .instrumentNotSelected(1)),
            (makeRangeAssignmentContext(originalIdentity, 9, makeInstrumentEditorRangeDocument(samples: [
                makeInstrumentEditorSample(instrument: 2, sample: 0, name: "S01"),
            ])), .sampleNotRepresented(instrumentIndex: 1, sampleIndex: 1)),
            (makeRangeAssignmentContext(originalIdentity, 9, makeInstrumentEditorRangeDocument(
                noteSampleMap: Array(repeating: 0, count: 95)
            )), .malformedKeymap(expectedCount: 96, actualCount: 95)),
        ]

        var context = makeRangeAssignmentContext(originalIdentity, 9, originalDocument)
        var foundationCallCount = 0
        let coordinator = InstrumentKeymapRangeAssignmentCoordinator(
            contextProvider: { context },
            commitHandler: { _, _, _, _ in
                foundationCallCount += 1
                return .failure(.editApplicationRejected)
            }
        )
        for (staleContext, expectedFailure) in staleContexts {
            context = makeRangeAssignmentContext(originalIdentity, 9, originalDocument)
            let request = try XCTUnwrap(coordinator.begin(focusedNote: nil, selectedOctave: 4))
            context = staleContext
            XCTAssertEqual(
                coordinator.commit(operationToken: request.operationToken, lowerNote: 48, upperNote: 59),
                .failure(expectedFailure)
            )
        }
        XCTAssertEqual(foundationCallCount, 0)
    }

    func testRangeAssignmentRefreshPreservesSelectionAndKeyboardRangeAndShowsOwnership() throws {
        let samples = (0..<16).map {
            makeInstrumentEditorSample(instrument: 2, sample: $0, name: String(format: "S%02X", $0 + 1))
        }
        var document = makeInstrumentEditorRangeDocument(samples: samples)
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            keymapRangeAssignmentHandler: { _ in true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        _ = view.shiftKeyboardVisibleRange(.higher)
        _ = view.shiftKeyboardVisibleRange(.higher)
        let selection = document.selection
        let samplePanel = try XCTUnwrap(view.instrumentEditorDescendants.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleSlotsPanel
        })
        let sampleScroll = try XCTUnwrap(samplePanel.subviews.compactMap { $0 as? NSScrollView }.first)
        sampleScroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        sampleScroll.reflectScrolledClipView(sampleScroll.contentView)

        _ = try document.assignSample(
            instrumentIndex: 1,
            sampleIndex: 1,
            lowerNote: 60,
            upperNote: 71
        ).get()
        XCTAssertTrue(controller.apply(displayState: .editableDocument(document)))

        XCTAssertEqual(view.keyboardVisibleRange.startNote, 49)
        XCTAssertEqual(view.displayState.selectedSampleSlot, 2)
        XCTAssertEqual(view.displayState.keymapRanges.map(\.sampleDisplay), ["S01", "S02", "S01"])
        XCTAssertEqual(view.displayState.keymapRanges.map(\.startNote), [1, 61, 73])
        XCTAssertEqual(view.displayState.keymapRanges.map(\.endNote), [60, 72, 96])
        let refreshedScroll = try XCTUnwrap(view.instrumentEditorDescendants.compactMap { $0 as? NSScrollView }.last)
        XCTAssertEqual(refreshedScroll.contentView.bounds.origin.y, 100, accuracy: 0.1)
        XCTAssertEqual(document.selection, selection)
    }

    func testKeyboardVisibleRangeShiftsOneOctaveAndStopsAtXMMapBounds() throws {
        var range = InstrumentKeyboardVisibleRange.defaultRange
        XCTAssertEqual(range.noteRange, UInt8(25)...UInt8(60)); XCTAssertEqual(range.noteCount, 36)
        XCTAssertEqual(range.startLabel, "C-2"); XCTAssertEqual(range.endLabel, "B-4")

        range = range.shifted(.lower); XCTAssertEqual(range.startNote, 13)
        range = range.shifted(.lower); XCTAssertEqual(range.startNote, 1)
        XCTAssertFalse(range.canShift(.lower))
        XCTAssertEqual(range.shifted(.lower), range)

        for _ in 0..<5 { range = range.shifted(.higher) }
        XCTAssertEqual(range.noteRange, UInt8(61)...UInt8(96))
        XCTAssertEqual(range.startLabel, "C-5"); XCTAssertEqual(range.endLabel, "B-7")
        XCTAssertFalse(range.canShift(.higher))
        XCTAssertEqual(range.shifted(.higher), range)
        XCTAssertNil(InstrumentKeyboardVisibleRange(startNote: 2)); XCTAssertNil(InstrumentKeyboardVisibleRange(startNote: 73))
    }

    func testShiftedKeyboardGeometryKeepsTheSummaryOnTheFull96NoteMap() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/instrument-envelopes-keymap.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let state = InstrumentEditorDisplayState.loadedModule(playbackSong: song, selection: .default)
        let c4Range = try XCTUnwrap(InstrumentKeyboardVisibleRange(startNote: 49))
        XCTAssertEqual(state.keymapRanges.map(\.startNote), [1, 49]); XCTAssertEqual(state.keymapRanges.map(\.endNote), [48, 96])
        let strip = InstrumentEditorKeymapRangeView(
            frame: NSRect(x: 0, y: 0, width: 962, height: 20),
            ranges: state.keymapRanges
        )
        XCTAssertEqual(strip.ownershipRects.count, 2)
        XCTAssertEqual(strip.ownershipRects.map(\.width), [480, 480])
        XCTAssertNil(strip.hitTest(NSPoint(x: strip.bounds.midX, y: strip.bounds.midY)))

        let layout = InstrumentEditorKeyboardLayout(
            bounds: NSRect(x: 0, y: 0, width: 876, height: 96),
            visibleRange: c4Range
        )
        XCTAssertEqual(layout.keys.map(\.noteValue).min(), 49); XCTAssertEqual(layout.keys.map(\.noteValue).max(), 84)
        XCTAssertEqual(layout.whiteKeys.count, 21); XCTAssertEqual(layout.blackKeys.count, 15)
        XCTAssertTrue(layout.keys.allSatisfy {
            layout.noteValue(at: NSPoint(x: $0.frame.midX, y: $0.frame.midY)) == $0.noteValue
        })
    }

    func testRangeControlsAreAccessibleNonMutatingAndPersistForPresenterSession() throws {
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        let before = document
        let undoManager = UndoManager()
        let presenter = InstrumentEditorWindowPresenter()
        var controller = presenter.show(displayState: .editableDocument(document))
        var view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)

        XCTAssertEqual(view.keyboardVisibleRange, .defaultRange)
        var lower = try view.keyboardRangeButton(.lower)
        var higher = try view.keyboardRangeButton(.higher)
        XCTAssertEqual(lower.title, "\u{25C0} C-2")
        XCTAssertEqual(higher.title, "B-4 \u{25B6}")
        XCTAssertTrue(lower.isEnabled)
        XCTAssertTrue(higher.isEnabled)
        XCTAssertEqual(lower.accessibilityLabel(), "Shift piano range down one octave")
        XCTAssertEqual(higher.accessibilityLabel(), "Shift piano range up one octave")

        XCTAssertTrue(view.shiftKeyboardVisibleRange(.higher))
        XCTAssertTrue(view.shiftKeyboardVisibleRange(.higher))
        XCTAssertEqual(view.keyboardVisibleRange.startLabel, "C-4")
        presenter.refresh(displayState: .editableDocument(document))
        XCTAssertEqual(view.keyboardVisibleRange.startNote, 49)
        controller.window?.close()

        controller = presenter.show(displayState: .editableDocument(document))
        view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        XCTAssertEqual(view.keyboardVisibleRange.startNote, 49)
        for _ in 0..<8 { _ = view.shiftKeyboardVisibleRange(.higher) }
        lower = try view.keyboardRangeButton(.lower)
        higher = try view.keyboardRangeButton(.higher)
        XCTAssertTrue(lower.isEnabled)
        XCTAssertFalse(higher.isEnabled)
        XCTAssertEqual(document, before)
        XCTAssertFalse(undoManager.canUndo)
        controller.window?.close()
    }

    func testAcceptedPreviewTokenDrivesOneVisibleHighlightAcrossSourcesAndRangeChanges() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let state = InstrumentEditorDisplayState.loadedModule(playbackSong: song, selection: .default)
        let sink = InstrumentEditorRecordingAuditionSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let presenter = InstrumentEditorWindowPresenter()

        func synchronize() { presenter.synchronizeActivePreviewToken(previewer.activePreviewToken) }
        func pressComputer(_ key: Character, octave: Int, repeatKey: Bool = false) -> EditorNoteAuditionPreviewOutcome {
            let request = InstrumentEditorAuditionRequestFactory.request(
                trackerKey: key, selectedOctave: octave, selection: .default,
                sourceContext: .loadedModule(patternIndex: 0), isRepeatedKeyDown: repeatKey
            )
            let outcome = previewer.preview(
                request: request,
                availability: request.map { EditorNoteAuditionAvailabilityResolver.availability(for: $0, loadedPlaybackSong: song) }
                    ?? .unavailable(.selectedInstrumentSampleNotPlayable),
                keyIdentity: EditorNoteAuditionKeyIdentity(trackerKey: key)
            )
            synchronize()
            return outcome
        }
        func releaseComputer(_ key: Character) -> Bool {
            let stopped = EditorNoteAuditionKeyIdentity(trackerKey: key).map(previewer.stopPreview(for:)) ?? false
            synchronize()
            return stopped
        }

        let controller = presenter.show(
            displayState: state,
            onScreenNoteHandler: { intent in
                switch intent {
                case let .press(note):
                    let request = InstrumentEditorAuditionRequestFactory.request(
                        noteValue: note, selection: .default,
                        sourceContext: .loadedModule(patternIndex: 0)
                    )
                    let accepted = previewer.preview(
                        request: request,
                        availability: request.map { EditorNoteAuditionAvailabilityResolver.availability(for: $0, loadedPlaybackSong: song) }
                            ?? .unavailable(.selectedInstrumentSampleNotPlayable),
                        keyIdentity: .instrumentEditorKeyboard
                    ).didAttemptPreview
                    synchronize()
                    return accepted
                case let .release(note):
                    guard let token = previewer.activePreviewToken,
                          token.keyIdentity == .instrumentEditorKeyboard,
                          token.noteValue == note else { return false }
                    let stopped = previewer.stopPreview(for: token)
                    synchronize()
                    return stopped
                }
            },
            noteAuditionCancelHandler: { previewer.cancelPreview(); synchronize() }
        )
        var keyboard = try instrumentEditorKeyboard(in: controller)

        XCTAssertTrue(pressComputer("z", octave: 2).didAttemptPreview)
        XCTAssertEqual(keyboard.highlightedNoteValue, 25)
        let computerToken = try XCTUnwrap(previewer.activePreviewToken)
        XCTAssertEqual(pressComputer("z", octave: 2, repeatKey: true), .skipped(.repeatedKeyDown))
        XCTAssertEqual(previewer.activePreviewToken, computerToken)
        XCTAssertEqual(sink.events.count, 1)

        let mouseKey = keyboard.keyboardLayout.blackKeys[0]
        XCTAssertTrue(keyboard.handlePointerDown(
            at: NSPoint(x: mouseKey.frame.midX, y: mouseKey.frame.midY), buttonNumber: 0
        ))
        XCTAssertEqual(keyboard.highlightedNoteValue, mouseKey.noteValue)
        XCTAssertFalse(releaseComputer("z"), "stale computer release must not clear the mouse preview")
        XCTAssertEqual(keyboard.highlightedNoteValue, mouseKey.noteValue)
        XCTAssertTrue(keyboard.handlePointerUp())
        XCTAssertNil(keyboard.highlightedNoteValue)

        let whiteKey = keyboard.keyboardLayout.whiteKeys[0]
        XCTAssertTrue(keyboard.handlePointerDown(
            at: NSPoint(x: whiteKey.frame.midX, y: whiteKey.frame.midY), buttonNumber: 0
        ))
        XCTAssertTrue(pressComputer("s", octave: 2).didAttemptPreview)
        XCTAssertEqual(keyboard.highlightedNoteValue, 26)
        XCTAssertFalse(keyboard.handlePointerUp(), "stale mouse release must not clear the computer preview")
        XCTAssertEqual(keyboard.highlightedNoteValue, 26)
        XCTAssertTrue(releaseComputer("s"))

        let rejectedRequest = EditorNoteAuditionRequest.noteOn(
            trackerKey: "z", selectedOctave: 2, selection: .default,
            sourceContext: .loadedModule(patternIndex: 0)
        )
        XCTAssertEqual(previewer.preview(
            request: rejectedRequest,
            availability: .unavailable(.selectedInstrumentSampleNotPlayable),
            keyIdentity: EditorNoteAuditionKeyIdentity(trackerKey: "z")
        ), .skipped(.unavailable(.selectedInstrumentSampleNotPlayable)))
        synchronize()
        XCTAssertNil(keyboard.highlightedNoteValue)

        XCTAssertTrue(pressComputer("z", octave: 5).didAttemptPreview)
        XCTAssertNil(keyboard.highlightedNoteValue, "C-5 auditions outside the default visible range")
        let soundingToken = previewer.activePreviewToken
        let cancellationCountBeforeRangeShift = sink.cancelPreviewCount
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        for _ in 0..<3 { XCTAssertTrue(view.shiftKeyboardVisibleRange(.higher)) }
        keyboard = try instrumentEditorKeyboard(in: controller)
        XCTAssertEqual(keyboard.highlightedNoteValue, 61)
        XCTAssertEqual(previewer.activePreviewToken, soundingToken)
        XCTAssertEqual(sink.cancelPreviewCount, cancellationCountBeforeRangeShift)
        for _ in 0..<3 { XCTAssertTrue(view.shiftKeyboardVisibleRange(.lower)) }
        XCTAssertNil(try instrumentEditorKeyboard(in: controller).highlightedNoteValue)
        XCTAssertTrue(view.shiftKeyboardVisibleRange(.higher))
        XCTAssertEqual(try instrumentEditorKeyboard(in: controller).highlightedNoteValue, 61)
        XCTAssertTrue(releaseComputer("z"))
        XCTAssertNil(try instrumentEditorKeyboard(in: controller).highlightedNoteValue)

        XCTAssertTrue(pressComputer("z", octave: 3).didAttemptPreview)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertNil(try instrumentEditorKeyboard(in: controller).highlightedNoteValue)
        XCTAssertTrue(pressComputer("z", octave: 3).didAttemptPreview)
        controller.window?.close()
        XCTAssertNil(previewer.activePreviewToken)
        let reopened = presenter.show(displayState: state)
        XCTAssertNil(try instrumentEditorKeyboard(in: reopened).highlightedNoteValue)
        reopened.window?.close()
    }

    func testKeyboardLayoutUsesOneScaledGeometryForDrawingAndHitTesting() {
        let bounds = NSRect(x: 0, y: 0, width: 876, height: 96)
        let layout = InstrumentEditorKeyboardLayout(bounds: bounds)
        XCTAssertEqual(layout.whiteKeys.map(\.noteValue), [25, 27, 29, 30, 32, 34, 36, 37, 39, 41, 42, 44, 46, 48, 49, 51, 53, 54, 56, 58, 60])
        XCTAssertEqual(layout.blackKeys.map(\.noteValue), [26, 28, 31, 33, 35, 38, 40, 43, 45, 47, 50, 52, 55, 57, 59])
        let firstBlack = layout.blackKeys[0]
        XCTAssertEqual(layout.noteValue(at: NSPoint(x: firstBlack.frame.midX, y: firstBlack.frame.midY)), 26)
        XCTAssertEqual(layout.noteValue(at: NSPoint(x: layout.whiteKeys[0].frame.maxX, y: bounds.maxY - 4)), 27)
        XCTAssertNil(layout.noteValue(at: .zero))
        XCTAssertNil(layout.noteValue(at: NSPoint(x: bounds.maxX, y: bounds.midY)))
        let scaled = InstrumentEditorKeyboardLayout(bounds: NSRect(x: 0, y: 0, width: 438, height: 144))
        XCTAssertTrue(scaled.keys.allSatisfy {
            scaled.noteValue(at: NSPoint(x: $0.frame.midX, y: $0.frame.midY)) == $0.noteValue
        })
    }

    func testKeyboardPrimaryPointerPressDragAndReleaseEmitMatchingIntents() {
        var intents: [InstrumentEditorOnScreenNoteIntent] = []
        var acceptsPress = true
        let keyboard = InstrumentEditorKeyboardPlaceholderView(
            frame: NSRect(x: 0, y: 0, width: 876, height: 96),
            hasKeymapData: true,
            noteIntentHandler: {
                if case .press = $0, !acceptsPress { return false }
                intents.append($0)
                return true
            }
        )
        let first = keyboard.keyboardLayout.whiteKeys[0]
        let second = keyboard.keyboardLayout.blackKeys[0]
        let firstPoint = NSPoint(x: first.frame.midX, y: first.frame.midY)
        let secondPoint = NSPoint(x: second.frame.midX, y: second.frame.midY)

        XCTAssertFalse(keyboard.handlePointerDown(at: firstPoint, buttonNumber: 1))
        XCTAssertFalse(keyboard.handlePointerDown(at: .zero, buttonNumber: 0))
        XCTAssertTrue(keyboard.handlePointerDown(at: firstPoint, buttonNumber: 0)); XCTAssertEqual(keyboard.activeNoteValue, first.noteValue)
        XCTAssertTrue(keyboard.handlePointerDrag(to: firstPoint))
        XCTAssertEqual(intents, [.press(first.noteValue)])
        XCTAssertTrue(keyboard.handlePointerDrag(to: secondPoint)); XCTAssertEqual(keyboard.activeNoteValue, second.noteValue)
        XCTAssertEqual(intents, [.press(first.noteValue), .release(first.noteValue), .press(second.noteValue)])
        XCTAssertTrue(keyboard.handlePointerDrag(to: .zero)); XCTAssertNil(keyboard.activeNoteValue)
        XCTAssertTrue(keyboard.handlePointerDrag(to: firstPoint)); XCTAssertEqual(keyboard.activeNoteValue, first.noteValue)
        XCTAssertTrue(keyboard.handlePointerUp()); XCTAssertNil(keyboard.activeNoteValue)
        XCTAssertEqual(intents.suffix(3), [.release(second.noteValue), .press(first.noteValue), .release(first.noteValue)])
        XCTAssertTrue(keyboard.handlePointerDown(at: firstPoint, buttonNumber: 0))
        XCTAssertTrue(keyboard.handlePointerDown(at: firstPoint, buttonNumber: 0))
        XCTAssertEqual(intents.suffix(3), [.press(first.noteValue), .release(first.noteValue), .press(first.noteValue)])
        XCTAssertTrue(keyboard.handlePointerUp())
        acceptsPress = false
        XCTAssertTrue(keyboard.handlePointerDown(at: firstPoint, buttonNumber: 0))
        XCTAssertNil(keyboard.activeNoteValue)
        XCTAssertFalse(keyboard.handlePointerUp())
    }

    func testOnScreenRequestUsesExactPitchAndPublicFixtureKeymapWithoutSelectionMutation() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/instrument-envelopes-keymap.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let selection = TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)

        let requests = try [UInt8(48), 49].map { note in
            try XCTUnwrap(InstrumentEditorAuditionRequestFactory.request(
                noteValue: note, selection: selection,
                sourceContext: .loadedModule(patternIndex: 0)
            ))
        }
        let availabilities = requests.map {
            EditorNoteAuditionAvailabilityResolver.availability(for: $0, loadedPlaybackSong: song)
        }
        XCTAssertEqual(requests.map(\.kind), [.noteOn(noteValue: 48, selectedOctave: 3), .noteOn(noteValue: 49, selectedOctave: 4)])
        XCTAssertEqual(requests.map(\.selectedSampleIndex), [2, 2])
        XCTAssertEqual(requests.map(\.sampleResolution), [.instrumentKeymap, .instrumentKeymap])
        XCTAssertEqual(availabilities.compactMap { if case let .potentiallyAvailable(value) = $0 { value.sampleIndex } else { nil } }, [0, 1])
        XCTAssertEqual(selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        let previewer = EditorNoteAuditionPreviewer(sink: InstrumentEditorRecordingAuditionSink())
        XCTAssertTrue(previewer.preview(request: requests[1], availability: availabilities[1],
                                        keyIdentity: .instrumentEditorKeyboard).didAttemptPreview)
        XCTAssertTrue(previewer.stopPreview(for: .instrumentEditorKeyboard))
    }

    func testSampleMetadataUsesRepresentedLengthLoopVolumeAndTuning() throws {
        let state = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: makeInstrumentPalette()),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )
        let sample = try XCTUnwrap(state.sampleSlots.last)

        XCTAssertEqual(sample.name, "Lead Bright")
        XCTAssertEqual(sample.lengthDisplay, "1024")
        XCTAssertEqual(sample.loopModeDisplay, "Ping-pong")
        XCTAssertEqual(sample.loopRangeDisplay, "128..<384")
        XCTAssertEqual(sample.volumeLevel, 48)
        XCTAssertEqual(sample.volumeDisplay, "48 / 64")
        XCTAssertEqual(sample.panning, 32)
        XCTAssertEqual(sample.panningDisplay, "32 / 255")
        XCTAssertEqual(sample.panSliderValue, -0.75, accuracy: 0.000_001)
        XCTAssertEqual(InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: -1), 0)
        XCTAssertEqual(InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: 0), 128)
        XCTAssertEqual(InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: 1), 255)
        XCTAssertEqual(InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: Double(37 - 128) / 128), 37)
        XCTAssertEqual(sample.relativeNoteDisplay, "+2")
        XCTAssertEqual(sample.finetuneDisplay, "-8")
    }

    func testVolumeRelativeNoteFinetuneAndPanAreEnabledOnlyForStoppedEditableRepresentedSample() throws {
        let palette = makeInstrumentPalette()
        let selection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        let loaded = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: selection
        )
        let editable = InstrumentEditorDisplayState.editableDocument(makeEditableDocument(palette: palette))

        XCTAssertEqual(try XCTUnwrap(loaded.selectedSample).panning, 32)
        XCTAssertEqual(try XCTUnwrap(editable.selectedSample).panning, 32)
        XCTAssertEqual(loaded.selectedSample?.panningDisplay, "32 / 255")
        XCTAssertEqual(editable.selectedSample?.panningDisplay, "32 / 255")

        let playing = InstrumentEditorDisplayState.editableDocument(
            makeEditableDocument(palette: palette),
            isPlaybackActive: true
        )

        for (state, expectedEnabled) in [(loaded, false), (editable, true), (playing, false)] {
            let controller = InstrumentEditorWindowController(displayState: state)
            let descendants = try XCTUnwrap(controller.window?.contentView).instrumentEditorDescendants
            let volume = try XCTUnwrap(descendants.sampleVolumeControl)
            let relativeNote = try XCTUnwrap(descendants.sampleRelativeNoteControl)
            let finetune = try XCTUnwrap(descendants.sampleFinetuneControl)
            let pan = try XCTUnwrap(descendants.samplePanningControl)
            XCTAssertEqual(volume.isEnabled, expectedEnabled)
            XCTAssertEqual(relativeNote.isEnabled, expectedEnabled)
            XCTAssertEqual(finetune.isEnabled, expectedEnabled)
            XCTAssertEqual(pan.isEnabled, expectedEnabled)
            XCTAssertEqual(state.isSampleVolumeEditable, expectedEnabled)
            XCTAssertEqual(state.isSampleRelativeNoteEditable, expectedEnabled)
            XCTAssertEqual(state.isSampleFinetuneEditable, expectedEnabled)
            XCTAssertEqual(state.isSamplePanningEditable, expectedEnabled)
            XCTAssertEqual(volume.minimumValue, 0)
            XCTAssertEqual(volume.maximumValue, 64)
            XCTAssertEqual(volume.value, 48)
            XCTAssertFalse(volume.isContinuous)
            XCTAssertEqual(relativeNote.minValue, -128)
            XCTAssertEqual(relativeNote.maxValue, 127)
            XCTAssertEqual(relativeNote.integerValue, 2)
            XCTAssertFalse(relativeNote.autorepeat)
            XCTAssertEqual(finetune.minimumValue, -128)
            XCTAssertEqual(finetune.maximumValue, 127)
            XCTAssertEqual(finetune.value, -8)
            XCTAssertFalse(finetune.isContinuous)
            XCTAssertEqual(pan.value, -0.75, accuracy: 0.000_001)
            XCTAssertEqual(descendants.sampleVolumeReadout?.stringValue, "48")
            XCTAssertEqual(descendants.sampleRelativeNoteReadout?.stringValue, "+2")
            XCTAssertEqual(descendants.sampleFinetuneReadout?.stringValue, "-8")
            XCTAssertTrue(descendants.compactMap { ($0 as? NSTextField)?.stringValue }.contains("32 / 255"))
        }
    }

    func testLoadedAndEditableDocumentsDisplayRepresentedAutoVibratoReadOnly() throws {
        let expected = PlaybackInstrumentAutoVibrato(
            waveformType: 3,
            sweep: 17,
            depth: 42,
            rate: 199
        )
        let palette = makeInstrumentPalette()
        let selection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        let loaded = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: selection
        )
        let editable = InstrumentEditorDisplayState.editableDocument(makeEditableDocument(palette: palette))

        XCTAssertEqual(loaded.autoVibrato, expected)
        XCTAssertEqual(editable.autoVibrato, expected)

        for state in [loaded, editable] {
            let controller = InstrumentEditorWindowController(displayState: state)
            let descendants = try XCTUnwrap(controller.window?.contentView).instrumentEditorDescendants
            let vibratoPanel = try XCTUnwrap(descendants.first {
                $0.identifier?.rawValue == InstrumentEditorViewIdentifier.vibratoPanel
            })
            let vibratoDescendants = vibratoPanel.instrumentEditorDescendants
            let buttons = vibratoDescendants.compactMap { $0 as? VTXEditorButton }
            let knobs = vibratoDescendants.compactMap { $0 as? VTXEditorKnobControl }
            let readouts = Set(vibratoDescendants.compactMap { ($0 as? VTXEditorSegmentReadout)?.stringValue })
            let indicator = try XCTUnwrap(vibratoDescendants.compactMap { $0 as? VTXEditorIndicatorLEDView }.first)

            XCTAssertEqual(buttons.map(\.editorRole), [.normal, .normal, .normal, .activePlay])
            XCTAssertTrue(buttons.allSatisfy { !$0.isEnabled && $0.target == nil && $0.action == nil })
            XCTAssertEqual(knobs.map(\.value), [17, 42, 199])
            XCTAssertEqual(knobs.map(\.maximumValue), [255, 255, 255])
            XCTAssertTrue(knobs.allSatisfy { !$0.isEnabled && $0.target == nil && $0.action == nil })
            XCTAssertEqual(readouts, ["17", "42", "199"])
            XCTAssertEqual(indicator.state, .amberActive)
        }
    }

    func testDefaultAutoVibratoDisplayIsCleanZeroAndInert() throws {
        let state = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: makeInstrumentPalette()),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        )
        let controller = InstrumentEditorWindowController(displayState: state)
        let descendants = try XCTUnwrap(controller.window?.contentView).instrumentEditorDescendants
        let vibratoPanel = try XCTUnwrap(descendants.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.vibratoPanel
        })
        let vibratoDescendants = vibratoPanel.instrumentEditorDescendants
        let buttons = vibratoDescendants.compactMap { $0 as? VTXEditorButton }
        let knobs = vibratoDescendants.compactMap { $0 as? VTXEditorKnobControl }
        let indicator = try XCTUnwrap(vibratoDescendants.compactMap { $0 as? VTXEditorIndicatorLEDView }.first)

        XCTAssertEqual(state.autoVibrato, .disabled)
        XCTAssertEqual(buttons.map(\.editorRole), [.activePlay, .normal, .normal, .normal])
        XCTAssertEqual(knobs.map(\.value), [0, 0, 0])
        XCTAssertTrue(buttons.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(knobs.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(indicator.state, .off)
    }

    func testEmptySampleStateKeepsVolumeTuningAndPanDisplaysCleanAndInert() throws {
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(.makeDefault()))
        let descendants = try XCTUnwrap(controller.window?.contentView).instrumentEditorDescendants
        let volume = try XCTUnwrap(descendants.sampleVolumeControl)
        let relativeNote = try XCTUnwrap(descendants.sampleRelativeNoteControl)
        let finetune = try XCTUnwrap(descendants.sampleFinetuneControl)
        let pan = try XCTUnwrap(descendants.compactMap { $0 as? VTXEditorPanSliderControl }.first)

        XCTAssertFalse(volume.isEnabled)
        XCTAssertEqual(volume.value, 0)
        XCTAssertEqual(descendants.sampleVolumeReadout?.stringValue, "—")
        XCTAssertFalse(relativeNote.isEnabled)
        XCTAssertEqual(relativeNote.integerValue, 0)
        XCTAssertEqual(descendants.sampleRelativeNoteReadout?.stringValue, "—")
        XCTAssertFalse(finetune.isEnabled)
        XCTAssertEqual(finetune.value, 0)
        XCTAssertEqual(descendants.sampleFinetuneReadout?.stringValue, "—")
        XCTAssertFalse(pan.isEnabled)
        XCTAssertEqual(pan.value, 0)
        XCTAssertTrue(descendants.compactMap { ($0 as? NSTextField)?.stringValue }.contains("— NO SAMPLE"))
    }

    func testDisplayStateConstructionDoesNotMutateEditableDocumentOrPalette() {
        let palette = makeInstrumentPalette()
        let document = makeEditableDocument(palette: palette)
        let before = document

        let state = InstrumentEditorDisplayState.editableDocument(document)

        XCTAssertEqual(document, before)
        XCTAssertEqual(document.instrumentPalette, palette)
        XCTAssertFalse(state.isReadOnly)
        XCTAssertTrue(state.isInstrumentNameEditable)
        XCTAssertTrue(state.isSampleVolumeEditable)
        XCTAssertTrue(state.isSampleRelativeNoteEditable)
        XCTAssertTrue(state.isSampleFinetuneEditable)
        XCTAssertTrue(state.isSamplePanningEditable)
        XCTAssertEqual(state.source, .editableDocument)
        XCTAssertTrue(EditorCommandAvailability.canClearCurrentPattern(
            hasBlankDocument: true,
            sourceContext: document.noteAuditionSourceContext
        ))
        XCTAssertFalse(EditorPatternMutationPolicy.canMutatePattern(
            sourceContext: .loadedModule(patternIndex: 0)
        ))

        let playingState = InstrumentEditorDisplayState.editableDocument(document, isPlaybackActive: true)
        XCTAssertTrue(playingState.isReadOnly)
        XCTAssertFalse(playingState.isInstrumentNameEditable)
        XCTAssertFalse(playingState.isSampleVolumeEditable)
        XCTAssertFalse(playingState.isSampleRelativeNoteEditable)
        XCTAssertFalse(playingState.isSampleFinetuneEditable)
        XCTAssertFalse(playingState.isSamplePanningEditable)
    }

    func testWindowCreatesFixedMockupHierarchyWithNameVolumeTuningAndPanEditable() throws {
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette()))
        )
        let songOrderController = SongOrderEditorWindowController()
        let window = try XCTUnwrap(controller.window)
        let panel = try XCTUnwrap(window as? InstrumentEditorPanel)
        let songOrderPanel = try XCTUnwrap(songOrderController.window as? NSPanel)
        let contentView = try XCTUnwrap(window.contentView)
        let descendants = contentView.instrumentEditorDescendants
        let identifiers = Set(descendants.compactMap { $0.identifier?.rawValue })
        let fieldValues = Set(descendants.compactMap { ($0 as? NSTextField)?.stringValue })

        XCTAssertEqual(window.title, "Instrument Editor")
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.utilityWindow))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isEnabled == true)
        XCTAssertNotNil(window.standardWindowButton(.closeButton)?.target)
        XCTAssertNotNil(window.standardWindowButton(.closeButton)?.action)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, InstrumentEditorWindowController.contentSize)
        XCTAssertEqual(window.contentMaxSize, InstrumentEditorWindowController.contentSize)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.worksWhenModal)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertEqual(panel.level, songOrderPanel.level)
        XCTAssertEqual(panel.collectionBehavior, songOrderPanel.collectionBehavior)
        XCTAssertEqual(panel.hidesOnDeactivate, songOrderPanel.hidesOnDeactivate)
        XCTAssertEqual(panel.becomesKeyOnlyIfNeeded, songOrderPanel.becomesKeyOnlyIfNeeded)
        XCTAssertEqual(panel.worksWhenModal, songOrderPanel.worksWhenModal)
        XCTAssertEqual(panel.canBecomeKey, songOrderPanel.canBecomeKey)
        XCTAssertEqual(panel.canBecomeMain, songOrderPanel.canBecomeMain)
        XCTAssertEqual(InstrumentEditorWindowController.contentSize, NSSize(width: 920, height: 638))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.headerPanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.instrumentListPanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.sampleSlotsPanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.envelopePanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.envelopeGraph))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.vibratoPanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.defaultsPanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.noteKeymapPanel))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.keymapRangeStrip))
        XCTAssertTrue(identifiers.contains(InstrumentEditorViewIdentifier.keyboardPlaceholder))
        XCTAssertTrue(fieldValues.contains("N/V/R/F/P"))
        XCTAssertTrue(fieldValues.contains("OTHER FIELDS READ-ONLY"))
        let nameField = try XCTUnwrap(contentView.instrumentEditorNameField)
        XCTAssertTrue(nameField.isEnabled)
        XCTAssertTrue(nameField.isEditable)
        XCTAssertEqual(nameField.stringValue, "Lead")
        XCTAssertTrue(descendants.compactMap { $0 as? NSTextField }.filter { $0 !== nameField }.allSatisfy { !$0.isEditable })

        let futureControls = descendants.compactMap { $0 as? NSControl }.filter {
            $0.identifier?.rawValue.hasPrefix(InstrumentEditorViewIdentifier.futureControlPrefix) == true
        }
        XCTAssertFalse(futureControls.isEmpty)
        XCTAssertTrue(futureControls.allSatisfy { !$0.isEnabled && $0.target == nil && $0.action == nil })
        XCTAssertEqual(
            Set(futureControls.compactMap { ($0 as? NSButton)?.title }),
            ["IMPORT XI", "EXPORT XI", "▶", "+ ADD PT", "DEL PT", "ON", "∿", "⊓", "⊿", "◺"]
        )
        XCTAssertEqual(futureControls.compactMap { $0 as? VTXEditorKnobControl }.count, 3)
        XCTAssertEqual(futureControls.compactMap { $0 as? VTXEditorPanSliderControl }.count, 0)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleVolumeControl).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleRelativeNoteControl).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleFinetuneControl).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.samplePanningControl).isEnabled)

        let envelopeGraph = try XCTUnwrap(descendants.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.envelopeGraph
        })
        let keyboard = try XCTUnwrap(descendants.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.keyboardPlaceholder
        })
        XCTAssertNil(envelopeGraph.hitTest(.zero))
        XCTAssertNil(keyboard.hitTest(.zero))
        XCTAssertTrue(try contentView.envelopeSelector(.volume).isEnabled)
        XCTAssertTrue(try contentView.envelopeSelector(.panning).isEnabled)
    }

    func testLoadedModuleNameFieldRemainsDisabledAndReadOnly() throws {
        let controller = InstrumentEditorWindowController(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: makeInstrumentPalette()),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let nameField = try XCTUnwrap(contentView.instrumentEditorNameField)

        XCTAssertFalse(nameField.isEnabled)
        XCTAssertFalse(nameField.isEditable)
        XCTAssertEqual(nameField.stringValue, "Lead")
        XCTAssertTrue((contentView as? InstrumentEditorView)?.displayState.isReadOnly == true)
    }

    func testClosingInstrumentEditorInvokesCloseHandlerExactlyOnce() throws {
        let controller = InstrumentEditorWindowController()
        let editorWindow = try XCTUnwrap(controller.window)
        var closeCount = 0
        controller.closeHandler = {
            closeCount += 1
        }

        editorWindow.orderFront(nil)
        editorWindow.close()

        XCTAssertFalse(editorWindow.isVisible)
        XCTAssertEqual(closeCount, 1)
    }

    func testGraphicalPressedStateCancelsOnSelectionTransitionDeactivationAndClose() throws {
        let palette = makeInstrumentPalette()
        let presenter = InstrumentEditorWindowPresenter()
        var intents: [InstrumentEditorOnScreenNoteIntent] = []
        var fallbackCancelCount = 0
        let controller = presenter.show(
            displayState: .loadedModule(playbackSong: makePlaybackSong(instruments: palette),
                                        selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)),
            onScreenNoteHandler: { intents.append($0); return true },
            noteAuditionCancelHandler: { fallbackCancelCount += 1 }
        )
        var keyboard = try instrumentEditorKeyboard(in: controller)
        var key = keyboard.keyboardLayout.whiteKeys[0]

        XCTAssertTrue(keyboard.handlePointerDown(at: NSPoint(x: key.frame.midX, y: key.frame.midY), buttonNumber: 0))
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertEqual(intents, [.press(key.noteValue), .release(key.noteValue)])
        intents.removeAll()
        XCTAssertTrue(keyboard.handlePointerDown(at: NSPoint(x: key.frame.midX, y: key.frame.midY), buttonNumber: 0))
        XCTAssertTrue(controller.apply(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )))
        XCTAssertEqual(intents, [.press(key.noteValue), .release(key.noteValue)])
        keyboard = try instrumentEditorKeyboard(in: controller)
        XCTAssertNil(keyboard.activeNoteValue)

        key = keyboard.keyboardLayout.blackKeys[0]
        XCTAssertTrue(keyboard.handlePointerDown(at: NSPoint(x: key.frame.midX, y: key.frame.midY), buttonNumber: 0))
        controller.window?.close()
        XCTAssertEqual(intents.suffix(2), [.press(key.noteValue), .release(key.noteValue)])
        XCTAssertEqual(fallbackCancelCount, 3, "lifecycle releases also publish cancellation barriers")
        XCTAssertNil(presenter.windowController)
    }

    func testEditableNameFieldSubmitsSelectedZeroBasedInstrumentIndex() throws {
        var submittedIndex: Int?
        var submittedName: String?
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette())),
            instrumentNameEditHandler: { index, name in
                submittedIndex = index
                submittedName = name
                return true
            }
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let nameField = try XCTUnwrap(contentView.instrumentEditorNameField)
        nameField.stringValue = "Renamed Lead"

        XCTAssertTrue(nameField.sendAction(nameField.action, to: nameField.target))
        XCTAssertEqual(submittedIndex, 1)
        XCTAssertEqual(submittedName, "Renamed Lead")
    }

    func testEditablePanSubmitsSelectedZeroBasedIndicesAndExactByte() throws {
        var submittedInstrument: Int?
        var submittedSample: Int?
        var submittedPanning: UInt8?
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette())),
            samplePanningEditHandler: { instrument, sample, panning in
                submittedInstrument = instrument
                submittedSample = sample
                submittedPanning = panning
                return true
            }
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let pan = try XCTUnwrap(contentView.instrumentEditorDescendants.samplePanningControl)

        XCTAssertFalse(pan.isContinuous)
        XCTAssertTrue(pan.setValue(1, sendAction: true, applyCenterDetent: false))
        XCTAssertEqual(submittedInstrument, 1)
        XCTAssertEqual(submittedSample, 1)
        XCTAssertEqual(submittedPanning, 255)
    }

    func testEditableVolumeSubmitsSelectedZeroBasedIndicesAndExactXMValue() throws {
        var submittedInstrument: Int?
        var submittedSample: Int?
        var submittedVolume: UInt8?
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette())),
            sampleVolumeEditHandler: { instrument, sample, volume in
                submittedInstrument = instrument
                submittedSample = sample
                submittedVolume = volume
                return true
            }
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let volume = try XCTUnwrap(contentView.instrumentEditorDescendants.sampleVolumeControl)

        XCTAssertFalse(volume.isContinuous)
        XCTAssertTrue(volume.setValue(17, sendAction: true))
        XCTAssertEqual(submittedInstrument, 1)
        XCTAssertEqual(submittedSample, 1)
        XCTAssertEqual(submittedVolume, 17)
    }

    func testEditableFinetuneSubmitsSelectedZeroBasedIndicesAndExactSignedByteValue() throws {
        var submittedInstrument: Int?
        var submittedSample: Int?
        var submittedFinetune: Int?
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette())),
            sampleFinetuneEditHandler: { instrument, sample, finetune in
                submittedInstrument = instrument
                submittedSample = sample
                submittedFinetune = finetune
                return true
            }
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let finetune = try XCTUnwrap(contentView.instrumentEditorDescendants.sampleFinetuneControl)

        XCTAssertFalse(finetune.isContinuous)
        XCTAssertTrue(finetune.setValue(-128, sendAction: true))
        XCTAssertEqual(submittedInstrument, 1)
        XCTAssertEqual(submittedSample, 1)
        XCTAssertEqual(submittedFinetune, -128)
    }

    func testVolumeDragUpdatesReadoutAndAccessibilityBeforeOneUndoableCommit() throws {
        var document = makeEditableDocument(palette: makeInstrumentPalette())
        let original = document
        let undoManager = UndoManager()
        var controller: InstrumentEditorWindowController?
        var editCount = 0
        let coordinator = EditableDocumentEditCoordinator(
            undoManager: undoManager,
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: { updatedDocument in
                document = updatedDocument
                controller?.apply(displayState: .editableDocument(updatedDocument))
            }
        )
        controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            sampleVolumeEditHandler: { instrument, sample, volume in
                editCount += 1
                return coordinator.setSampleVolume(instrumentAt: instrument, sampleAt: sample, volume: volume)
            }
        )
        let view = try XCTUnwrap(controller?.window?.contentView as? InstrumentEditorView)
        let volume = try XCTUnwrap(view.instrumentEditorDescendants.sampleVolumeControl)

        volume.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: volume, x: 36, y: 24))
        volume.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: volume, x: 36, y: 54))

        XCTAssertEqual(volume.value, 64)
        XCTAssertEqual(view.instrumentEditorDescendants.sampleVolumeReadout?.stringValue, "64")
        XCTAssertEqual((volume.accessibilityValue() as? NSNumber)?.intValue, 64)
        XCTAssertEqual(view.controlDragSession?.originalCommittedValue, 48)
        XCTAssertEqual(view.controlDragSession?.currentTransientValue, 64)
        XCTAssertEqual(document, original)
        XCTAssertEqual(editCount, 0)
        XCTAssertFalse(undoManager.canUndo)

        volume.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: volume, x: 36, y: 54))

        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(document.instrumentPalette[2]?.samples[1].volume, 1)
        XCTAssertEqual(coordinator.undoMenuItemTitle, "Undo Change Sample Volume")
        XCTAssertEqual(controller?.window?.contentView?.instrumentEditorDescendants.sampleVolumeReadout?.stringValue, "64")
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(controller?.window?.contentView?.instrumentEditorDescendants.sampleVolumeReadout?.stringValue, "48")
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(controller?.window?.contentView?.instrumentEditorDescendants.sampleVolumeReadout?.stringValue, "64")
    }

    func testFinetuneAndPanReadoutsTrackSignedAndExactByteValuesBeforeCommit() throws {
        let state = InstrumentEditorDisplayState.editableDocument(makeEditableDocument(palette: makeInstrumentPalette()))
        var submittedFinetune: Int?
        var submittedPanning: UInt8?
        let controller = InstrumentEditorWindowController(
            displayState: state,
            sampleFinetuneEditHandler: { _, _, value in submittedFinetune = value; return true },
            samplePanningEditHandler: { _, _, value in submittedPanning = value; return true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let finetune = try XCTUnwrap(view.instrumentEditorDescendants.sampleFinetuneControl)

        finetune.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: finetune, x: 36, y: 12))
        finetune.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: finetune, x: 36, y: 60))
        XCTAssertEqual(finetune.value, 94)
        XCTAssertEqual(view.instrumentEditorDescendants.sampleFinetuneReadout?.stringValue, "+94")
        XCTAssertEqual((finetune.accessibilityValue() as? NSNumber)?.intValue, 94)
        XCTAssertNil(submittedFinetune)
        finetune.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: finetune, x: 36, y: 60))
        XCTAssertEqual(submittedFinetune, 94)

        let pan = try XCTUnwrap(view.instrumentEditorDescendants.samplePanningControl)
        pan.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: pan, x: 27.25, y: 16))
        pan.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: pan, x: 124, y: 16))
        let transientPanning = InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: pan.value)
        XCTAssertEqual(view.instrumentEditorDescendants.samplePanningReadout?.stringValue,
                       InstrumentEditorDisplayState.SampleSlot.panningDisplay(transientPanning))
        XCTAssertEqual((pan.accessibilityValue() as? NSNumber)?.intValue, Int(transientPanning))
        XCTAssertNil(submittedPanning)
        pan.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: pan, x: 124, y: 16))
        XCTAssertEqual(submittedPanning, transientPanning)
    }

    func testLifecycleRefreshNeverCommitsStaleTransientValue() throws {
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        var editCount = 0
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(document),
            sampleVolumeEditHandler: { _, _, _ in editCount += 1; return true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        var volume = try XCTUnwrap(view.instrumentEditorDescendants.sampleVolumeControl)

        volume.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: volume, x: 36, y: 24))
        volume.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: volume, x: 36, y: 48))
        XCTAssertNotEqual(view.instrumentEditorDescendants.sampleVolumeReadout?.stringValue, "48")
        XCTAssertFalse(controller.apply(displayState: .editableDocument(document)))
        XCTAssertEqual(view.instrumentEditorDescendants.sampleVolumeReadout?.stringValue, "48")
        XCTAssertNil(view.controlDragSession)
        volume.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: volume, x: 36, y: 48))

        volume = try XCTUnwrap(view.instrumentEditorDescendants.sampleVolumeControl)
        volume.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: volume, x: 36, y: 24))
        volume.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: volume, x: 36, y: 48))
        XCTAssertTrue(controller.apply(displayState: .editableDocument(document, isPlaybackActive: true)))
        XCTAssertFalse(try XCTUnwrap(controller.window?.contentView?.instrumentEditorDescendants.sampleVolumeControl).isEnabled)
        volume.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: volume, x: 36, y: 48))

        XCTAssertTrue(controller.apply(displayState: .editableDocument(document)))
        volume = try XCTUnwrap(view.instrumentEditorDescendants.sampleVolumeControl)
        volume.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: volume, x: 36, y: 24))
        volume.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: volume, x: 36, y: 48))
        var changedSelection = document
        changedSelection.selectSample(1)
        XCTAssertTrue(controller.apply(displayState: .editableDocument(changedSelection)))
        volume.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: volume, x: 36, y: 48))
        XCTAssertNil(view.controlDragSession)

        XCTAssertTrue(controller.apply(displayState: .editableDocument(document)))
        volume = try XCTUnwrap(view.instrumentEditorDescendants.sampleVolumeControl)
        volume.mouseDown(with: try instrumentEditorPointerEvent(.leftMouseDown, in: volume, x: 36, y: 24))
        volume.mouseDragged(with: try instrumentEditorPointerEvent(.leftMouseDragged, in: volume, x: 36, y: 48))
        controller.window?.close()
        volume.mouseUp(with: try instrumentEditorPointerEvent(.leftMouseUp, in: volume, x: 36, y: 48))
        XCTAssertNil(view.controlDragSession)
        XCTAssertEqual(editCount, 0)
    }

    func testEditableRelativeNoteSubmitsSelectedZeroBasedIndicesAndExactSignedByteValue() throws {
        var submittedInstrument: Int?
        var submittedSample: Int?
        var submittedRelativeNote: Int?
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette())),
            sampleRelativeNoteEditHandler: { instrument, sample, relativeNote in
                submittedInstrument = instrument
                submittedSample = sample
                submittedRelativeNote = relativeNote
                return true
            }
        )
        let contentView = try XCTUnwrap(controller.window?.contentView)
        let relativeNote = try XCTUnwrap(contentView.instrumentEditorDescendants.sampleRelativeNoteControl)
        relativeNote.integerValue = -128

        XCTAssertFalse(relativeNote.autorepeat)
        XCTAssertTrue(relativeNote.sendAction(relativeNote.action, to: relativeNote.target))
        XCTAssertEqual(submittedInstrument, 1)
        XCTAssertEqual(submittedSample, 1)
        XCTAssertEqual(submittedRelativeNote, -128)
    }

    func testApplyingSelectionChangeRefreshesVisibleSampleRows() throws {
        let palette = makeInstrumentPalette()
        let controller = InstrumentEditorWindowController(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let initialRebuildCount = contentView.rebuildCount
        XCTAssertEqual(contentView.instrumentEditorDescendants.sampleRelativeNoteReadout?.stringValue, "0")
        let updated = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )

        XCTAssertTrue(controller.apply(displayState: updated))
        XCTAssertEqual(contentView.displayState, updated)
        XCTAssertEqual(contentView.rebuildCount, initialRebuildCount + 1)
        XCTAssertEqual(contentView.instrumentEditorDescendants.sampleRelativeNoteReadout?.stringValue, "+2")
        XCTAssertEqual(
            contentView.instrumentEditorDescendants.filter {
                $0.identifier?.rawValue.hasPrefix(InstrumentEditorViewIdentifier.sampleRowPrefix) == true
            }.count,
            2
        )
        XCTAssertFalse(controller.apply(displayState: updated))
    }

    func testExistingControllerRefreshesAcrossLoadedEmptyAndEditableDocumentStates() throws {
        let palette = makeInstrumentPalette()
        let loaded = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )
        let document = makeEditableDocument(palette: palette)
        let before = document
        let controller = InstrumentEditorWindowController(displayState: loaded)
        let contentView = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)

        XCTAssertTrue(controller.apply(displayState: .empty))
        XCTAssertEqual(contentView.displayState.source, .none)
        XCTAssertTrue(contentView.displayState.instrumentSlots.isEmpty)

        let editable = InstrumentEditorDisplayState.editableDocument(document)
        XCTAssertTrue(controller.apply(displayState: editable))
        XCTAssertEqual(contentView.displayState.source, .editableDocument)
        XCTAssertEqual(contentView.displayState.instrumentName, "Lead")
        XCTAssertTrue(contentView.displayState.isInstrumentNameEditable)
        XCTAssertEqual(document, before)
    }

    func testEditableCopyMessageUsesMainDocumentWindowAndTracksKeyAuxiliaryForRestoration() throws {
        let mainWindow = NSWindow()
        let editorWindow = try XCTUnwrap(InstrumentEditorWindowController().window)

        let fromMain = LoadedModuleEditableCopyAlertHostPolicy.presentation(
            keyWindow: mainWindow,
            mainWindow: mainWindow
        )
        XCTAssertTrue(fromMain.hostWindow === mainWindow)
        XCTAssertNil(fromMain.auxiliaryWindowToRestore)

        let fromEditor = LoadedModuleEditableCopyAlertHostPolicy.presentation(
            keyWindow: editorWindow,
            mainWindow: mainWindow
        )
        XCTAssertTrue(fromEditor.hostWindow === mainWindow)
        XCTAssertTrue(fromEditor.auxiliaryWindowToRestore === editorWindow)

        let fallback = LoadedModuleEditableCopyAlertHostPolicy.presentation(
            keyWindow: editorWindow,
            mainWindow: nil
        )
        XCTAssertTrue(fallback.hostWindow === editorWindow)
        XCTAssertNil(fallback.auxiliaryWindowToRestore)
        let missing = LoadedModuleEditableCopyAlertHostPolicy.presentation(
            keyWindow: nil,
            mainWindow: nil
        )
        XCTAssertNil(missing.hostWindow)
        XCTAssertNil(missing.auxiliaryWindowToRestore)
    }

    func testEditableCopySheetFromMainLeavesNoAttachedSheetOrModalStateAfterDismissal() throws {
        let mainWindow = makeInstrumentEditorTestWindow(title: "Tracker")
        let alert = makeInstrumentEditorTestAlert()
        var sheetHost: NSWindow?
        var dismissalHandler: ((NSApplication.ModalResponse) -> Void)?
        var orderedWindows: [NSWindow] = []
        var activatedWindows: [NSWindow] = []
        var runModalCount = 0
        let actions = LoadedModuleEditableCopyAlertPresenter.Actions(
            orderBack: { orderedWindows.append($0) },
            makeKeyAndOrderFront: { activatedWindows.append($0) },
            beginSheet: { _, hostWindow, completionHandler in
                sheetHost = hostWindow
                dismissalHandler = completionHandler
            },
            runModal: { _ in runModalCount += 1 }
        )

        LoadedModuleEditableCopyAlertPresenter.present(
            alert,
            keyWindow: mainWindow,
            mainWindow: mainWindow,
            actions: actions
        )

        XCTAssertTrue(sheetHost === mainWindow)
        XCTAssertTrue(orderedWindows.isEmpty)
        XCTAssertTrue(activatedWindows.isEmpty)
        XCTAssertEqual(runModalCount, 0)
        XCTAssertNil(NSApp.modalWindow)
        dismissalHandler?(.OK)
        XCTAssertTrue(activatedWindows.isEmpty)
        XCTAssertNil(mainWindow.attachedSheet)
        XCTAssertNil(alert.window.sheetParent)
        XCTAssertNil(NSApp.modalWindow)
    }

    func testEditableCopySheetFromKeyInstrumentEditorRestoresActivationAndCloseBehavior() throws {
        let mainWindow = makeInstrumentEditorTestWindow(title: "Tracker")
        let controller = InstrumentEditorWindowController()
        let editorWindow = try XCTUnwrap(controller.window)
        let editorPanel = try XCTUnwrap(editorWindow as? NSPanel)
        let closeButton = try XCTUnwrap(editorWindow.standardWindowButton(.closeButton))
        var sheetHost: NSWindow?
        var dismissalHandler: ((NSApplication.ModalResponse) -> Void)?
        var orderedWindows: [NSWindow] = []
        var activatedWindows: [NSWindow] = []
        var runModalCount = 0
        defer {
            editorWindow.close()
            mainWindow.close()
        }
        editorWindow.orderFront(nil)
        let actions = LoadedModuleEditableCopyAlertPresenter.Actions(
            orderBack: { orderedWindows.append($0) },
            makeKeyAndOrderFront: { activatedWindows.append($0) },
            beginSheet: { _, hostWindow, completionHandler in
                sheetHost = hostWindow
                dismissalHandler = completionHandler
            },
            runModal: { _ in runModalCount += 1 }
        )

        let alert = makeInstrumentEditorTestAlert()
        LoadedModuleEditableCopyAlertPresenter.present(
            alert,
            keyWindow: editorWindow,
            mainWindow: mainWindow,
            actions: actions
        )

        XCTAssertTrue(sheetHost === mainWindow)
        XCTAssertEqual(orderedWindows.count, 1)
        XCTAssertTrue(orderedWindows.first === editorWindow)
        XCTAssertEqual(activatedWindows.count, 1)
        XCTAssertTrue(activatedWindows.first === mainWindow)
        XCTAssertEqual(runModalCount, 0)
        XCTAssertFalse(editorPanel.isFloatingPanel)
        XCTAssertNil(editorWindow.attachedSheet)
        XCTAssertTrue(closeButton.isEnabled)
        dismissalHandler?(.OK)
        XCTAssertEqual(activatedWindows.count, 2)
        XCTAssertTrue(activatedWindows.last === editorWindow)
        XCTAssertTrue(editorPanel.isFloatingPanel)
        XCTAssertNil(mainWindow.attachedSheet)
        XCTAssertNil(alert.window.sheetParent)
        XCTAssertNil(NSApp.modalWindow)
        XCTAssertTrue(closeButton.isEnabled)

        closeButton.performClick(nil)
        XCTAssertFalse(editorWindow.isVisible)
    }

    func testPresenterReusesOneControllerAndCloseCancelsAndDetachesAuditionBeforeReopen() throws {
        let presenter = InstrumentEditorWindowPresenter()
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        let state = InstrumentEditorDisplayState.editableDocument(document)
        let harness = InstrumentEditorAuditionHarness(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            selectedOctave: 4,
            availability: { document.noteAuditionAvailability(for: $0) }
        )
        var handlerMarker = 0
        let first = presenter.show(displayState: state, noteAuditionKeyDownHandler: { _, _ in
            handlerMarker = 1
            return true
        })
        let router = try XCTUnwrap((first.window as? InstrumentEditorPanel)?.keyboardAuditionRouter)
        let second = presenter.show(displayState: state, noteAuditionKeyDownHandler: { character, isRepeat in
            handlerMarker = 2
            return harness.router.noteKeyDownHandler?(character, isRepeat) == true
        }, noteAuditionKeyUpHandler: { character in
            harness.router.noteKeyUpHandler?(character) == true
        }, noteAuditionCancelHandler: {
            harness.previewer.cancelPreview()
        })

        XCTAssertTrue(first === second)
        XCTAssertTrue(first.window === second.window)
        XCTAssertTrue(first.window?.isVisible == true)
        XCTAssertTrue(router === (second.window as? InstrumentEditorPanel)?.keyboardAuditionRouter)
        XCTAssertTrue(router.handle(makeInstrumentEditorKeyEvent(keyCode: 6, characters: "z"),
                                    isKeyWindow: true, firstResponder: NSButton()))
        XCTAssertEqual(handlerMarker, 2)
        XCTAssertNotNil(harness.previewer.activePreviewToken)
        XCTAssertEqual(harness.sink.events.count, 1)

        first.window?.close()
        XCTAssertNil(presenter.windowController)
        XCTAssertNil(harness.previewer.activePreviewToken)
        XCTAssertEqual(harness.sink.releasePreviewCount, 0)
        XCTAssertEqual(harness.sink.cancelPreviewCount, 1)
        XCTAssertNil(first.noteAuditionKeyDownHandler)
        XCTAssertNil(first.noteAuditionKeyUpHandler)
        XCTAssertNil(router.noteKeyDownHandler)
        XCTAssertNil(router.noteKeyUpHandler)
        first.window?.close()
        XCTAssertEqual(harness.sink.releasePreviewCount, 0)
        XCTAssertEqual(harness.sink.cancelPreviewCount, 1)
        let reopened = presenter.show(displayState: state)
        XCTAssertFalse(reopened === first)
        XCTAssertFalse((reopened.window as? InstrumentEditorPanel)?.keyboardAuditionRouter === router)
        let reopenedView = try XCTUnwrap(reopened.window?.contentView as? InstrumentEditorView)
        XCTAssertTrue(reopenedView.displayState.isInstrumentNameEditable)
        XCTAssertTrue(reopenedView.displayState.isSampleVolumeEditable)
        XCTAssertTrue(reopenedView.displayState.isSampleRelativeNoteEditable)
        XCTAssertTrue(reopenedView.displayState.isSampleFinetuneEditable)
        XCTAssertTrue(reopenedView.displayState.isSamplePanningEditable)
        reopened.window?.close()
    }

    func testRepeatedCloseReopenCyclesCreateOneFreshControllerAndRouterPerCycle() throws {
        let presenter = InstrumentEditorWindowPresenter()
        let state = InstrumentEditorDisplayState.editableDocument(
            makeEditableDocument(palette: makeInstrumentPalette())
        )
        var controllers = Set<ObjectIdentifier>()
        var routers = Set<ObjectIdentifier>()

        for _ in 0..<3 {
            let controller = presenter.show(displayState: state)
            let router = try XCTUnwrap((controller.window as? InstrumentEditorPanel)?.keyboardAuditionRouter)
            controllers.insert(ObjectIdentifier(controller))
            routers.insert(ObjectIdentifier(router))
            XCTAssertTrue(presenter.windowController === controller)
            XCTAssertTrue(controller.window?.isVisible == true)
            controller.window?.close()
            XCTAssertNil(presenter.windowController)
        }

        XCTAssertEqual(controllers.count, 3)
        XCTAssertEqual(routers.count, 3)
    }

    func testOpenAndReopenStartOutsideNameEditingAndExplicitFocusSuppressesThenRestoresAudition() throws {
        let presenter = InstrumentEditorWindowPresenter()
        let state = InstrumentEditorDisplayState.editableDocument(
            makeEditableDocument(palette: makeInstrumentPalette())
        )
        var auditionCount = 0
        let noteHandler: InstrumentEditorNoteAuditionKeyDownHandler = { _, _ in
            auditionCount += 1
            return true
        }
        let controller = presenter.show(displayState: state, noteAuditionKeyDownHandler: noteHandler)
        let window = try XCTUnwrap(controller.window)
        let contentView = try XCTUnwrap(window.contentView as? InstrumentEditorView)
        let nameField = try XCTUnwrap(window.contentView?.instrumentEditorNameField)
        let router = try XCTUnwrap((window as? InstrumentEditorPanel)?.keyboardAuditionRouter)

        XCTAssertTrue(window.firstResponder === contentView)
        XCTAssertNil(nameField.currentEditor())
        XCTAssertEqual(nameField.stringValue, "Lead")
        XCTAssertTrue(contentView.nextKeyView === nameField)
        XCTAssertTrue(nameField.nextKeyView === contentView)
        XCTAssertTrue(router.handle(makeInstrumentEditorKeyEvent(keyCode: 6, characters: "z"),
                                    isKeyWindow: true, firstResponder: window.firstResponder))
        XCTAssertEqual(auditionCount, 1)

        nameField.selectText(nil)
        XCTAssertTrue(window.firstResponder is NSTextView)
        XCTAssertFalse(router.handle(makeInstrumentEditorKeyEvent(keyCode: 6, characters: "z"),
                                     isKeyWindow: true, firstResponder: window.firstResponder))
        XCTAssertEqual(auditionCount, 1)
        presenter.show(displayState: state, noteAuditionKeyDownHandler: noteHandler)
        XCTAssertTrue(window.firstResponder is NSTextView)

        XCTAssertTrue(window.makeFirstResponder(contentView))
        XCTAssertNil(nameField.currentEditor())
        XCTAssertTrue(router.handle(makeInstrumentEditorKeyEvent(keyCode: 6, characters: "z"),
                                    isKeyWindow: true, firstResponder: window.firstResponder))
        XCTAssertEqual(auditionCount, 2)
        nameField.selectText(nil)

        window.close()

        XCTAssertNil(nameField.currentEditor())
        XCTAssertNil(presenter.windowController)
        let reopened = presenter.show(displayState: state, noteAuditionKeyDownHandler: noteHandler)
        let reopenedWindow = try XCTUnwrap(reopened.window)
        let reopenedView = try XCTUnwrap(reopened.window?.contentView as? InstrumentEditorView)
        let reopenedNameField = try XCTUnwrap(reopenedWindow.contentView?.instrumentEditorNameField)
        let reopenedRouter = try XCTUnwrap((reopenedWindow as? InstrumentEditorPanel)?.keyboardAuditionRouter)
        XCTAssertTrue(reopenedWindow.firstResponder === reopenedView)
        XCTAssertNil(reopenedNameField.currentEditor())
        XCTAssertEqual(reopenedNameField.stringValue, "Lead")
        XCTAssertTrue(reopenedView.nextKeyView === reopenedNameField)
        XCTAssertTrue(reopenedNameField.nextKeyView === reopenedView)
        XCTAssertTrue(reopenedView.displayState.isInstrumentNameEditable)
        XCTAssertTrue(reopenedView.displayState.isSampleVolumeEditable)
        XCTAssertTrue(reopenedRouter.handle(makeInstrumentEditorKeyEvent(keyCode: 6, characters: "z"),
                                            isKeyWindow: true, firstResponder: reopenedWindow.firstResponder))
        XCTAssertEqual(auditionCount, 3)
        reopened.window?.close()
    }

    func testNoteAuditionRoutingPolicyUsesSharedLowerAndUpperTrackerKeyMap() throws {
        let cases: [(Character, UInt16, UInt8)] = [("z", 6, 49), ("q", 12, 61)]
        for testCase in cases {
            XCTAssertEqual(instrumentEditorAuditionAction(keyCode: testCase.1, characters: String(testCase.0)),
                           .noteKeyDown(testCase.0, isRepeat: false))
            XCTAssertEqual(TrackerNoteKeyMap.noteValue(forTrackerKey: testCase.0, octave: 4), testCase.2)
        }
    }

    func testInstrumentEditorPanelInspectsOnlyKeyboardEventsForAudition() {
        XCTAssertTrue(InstrumentEditorWindowEventRoutingPolicy.shouldInspectForNoteAudition(.keyDown))
        XCTAssertTrue(InstrumentEditorWindowEventRoutingPolicy.shouldInspectForNoteAudition(.keyUp))
        for eventType: NSEvent.EventType in [
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .mouseMoved,
            .scrollWheel,
        ] {
            XCTAssertFalse(
                InstrumentEditorWindowEventRoutingPolicy.shouldInspectForNoteAudition(eventType),
                "\(eventType) must go directly to NSPanel.sendEvent"
            )
        }
    }

    func testNoteAuditionRoutingPolicyRejectsUnsupportedCommandsNavigationAndFunctionKeys() {
        XCTAssertNil(instrumentEditorAuditionAction(keyCode: 34, characters: "i"))

        let protectedKeyCodes: [UInt16] = [48, 53, 36, 76, 51, 117, 115, 119, 116, 121,
                                              123, 124, 125, 126, 122]
        for keyCode in protectedKeyCodes {
            XCTAssertNil(instrumentEditorAuditionAction(keyCode: keyCode, characters: "z"),
                         "keyCode \(keyCode) must remain in the normal responder chain")
        }
    }

    func testNoteAuditionRoutingPolicyRejectsCommandControlAndOptionModifiers() {
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            XCTAssertNil(instrumentEditorAuditionAction(keyCode: 6, characters: "z", modifierFlags: modifier))
        }

        XCTAssertEqual(instrumentEditorAuditionAction(keyCode: 6, characters: "Z", modifierFlags: .shift),
                       .noteKeyDown("Z", isRepeat: false))
        for character in ["z", "x", "c", "v", "a", "w"] {
            XCTAssertNil(instrumentEditorAuditionAction(keyCode: 6, characters: character,
                                                        modifierFlags: .command))
        }
        XCTAssertNil(instrumentEditorAuditionAction(keyCode: 6, characters: "z",
                                                    modifierFlags: [.command, .shift]))
    }

    func testCommandWRemainsInTheNormalResponderChain() {
        let router = InstrumentEditorKeyboardAuditionRouter()
        var handlerWasCalled = false
        router.noteKeyDownHandler = { _, _ in
            handlerWasCalled = true
            return true
        }

        XCTAssertFalse(router.handle(
            makeInstrumentEditorKeyEvent(keyCode: 13, characters: "w", modifierFlags: .command),
            isKeyWindow: true,
            firstResponder: NSButton()
        ))
        XCTAssertFalse(handlerWasCalled)
    }

    func testNoteAuditionRoutingPolicyRequiresKeyWindowAndDefersToTextEditingResponders() {
        let textView = NSTextView(frame: .zero)
        let editableNameField = NSTextField(frame: .zero)
        editableNameField.isEditable = true

        XCTAssertNil(instrumentEditorAuditionAction(keyCode: 6, characters: "z", isKeyWindow: false))
        XCTAssertNil(instrumentEditorAuditionAction(keyCode: 6, characters: "z", firstResponder: textView))
        XCTAssertNil(instrumentEditorAuditionAction(keyCode: 6, characters: "z",
                                                    firstResponder: editableNameField))
        XCTAssertEqual(instrumentEditorAuditionAction(keyCode: 6, characters: "z",
                                                      firstResponder: NSButton()),
                       .noteKeyDown("z", isRepeat: false))
    }

    func testRoutedEditableDocumentAuditionUsesExistingPipelineWithoutMutationOrUndo() throws {
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        let documentBefore = document
        let cursor = PatternCursor(row: 9, channel: 3, field: .note)
        let cursorBefore = cursor
        let undoManager = UndoManager()
        let harness = InstrumentEditorAuditionHarness(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            selectedOctave: 4,
            channelIndex: cursor.channel,
            rowIndex: cursor.row,
            availability: { document.noteAuditionAvailability(for: $0) }
        )

        XCTAssertTrue(harness.send(keyCode: 12, characters: "q"))
        let event = try XCTUnwrap(harness.sink.events.first)

        XCTAssertEqual(event.noteValue, 61)
        XCTAssertEqual(event.selectedOctave, 5)
        XCTAssertEqual(event.request.selectedInstrumentIndex, 2)
        XCTAssertEqual(event.request.selectedSampleIndex, 2)
        XCTAssertEqual(event.request.sourceContext, .blankDocument)
        XCTAssertEqual(event.request.channelIndex, 3)
        XCTAssertEqual(event.request.rowIndex, 9)
        XCTAssertEqual(event.sampleDescriptor.instrumentIndex, 2)
        XCTAssertEqual(event.sampleDescriptor.sampleIndex, 1)
        XCTAssertEqual(document, documentBefore)
        XCTAssertEqual(cursor, cursorBefore)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testRoutedLoadedModuleAuditionUsesKeymapAndSuppressesRepeat() throws {
        let song = makePlaybackSong(instruments: makeInstrumentPalette())
        let songBefore = song
        let selection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        let sourceContext = EditorNoteAuditionSourceContext.loadedModule(patternIndex: 7)
        let harness = InstrumentEditorAuditionHarness(
            selection: selection,
            sourceContext: sourceContext,
            selectedOctave: 5,
            availability: { EditorNoteAuditionAvailabilityResolver.availability(for: $0, loadedPlaybackSong: song) }
        )

        XCTAssertTrue(harness.send(keyCode: 6, characters: "z"))
        XCTAssertTrue(harness.send(keyCode: 6, characters: "z", isARepeat: true))

        let preview = try XCTUnwrap(harness.sink.events.first)
        XCTAssertEqual(harness.sink.events.count, 1)
        XCTAssertEqual(preview.request.selectedInstrumentIndex, 2)
        XCTAssertEqual(preview.request.selectedSampleIndex, 2)
        XCTAssertEqual(preview.request.sourceContext, sourceContext)
        XCTAssertEqual(preview.sampleDescriptor.sampleIndex, 1)
        XCTAssertEqual(song, songBefore)
    }

    func testUnavailableInstrumentEditorAuditionDoesNotTriggerPreview() {
        let document = BlankTrackerDocument.makeDefault()
        let harness = InstrumentEditorAuditionHarness(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            selectedOctave: 4,
            availability: { document.noteAuditionAvailability(for: $0) }
        )

        XCTAssertFalse(harness.send(keyCode: 6, characters: "z"))
        XCTAssertTrue(harness.sink.events.isEmpty)
        XCTAssertEqual(harness.sink.cancelPreviewCount, 0)
    }

    func testInstrumentEditorKeyUpCancelsOnlyMatchingPreviewWithoutMutation() throws {
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        let before = document
        let harness = InstrumentEditorAuditionHarness(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            selectedOctave: 4,
            availability: { document.noteAuditionAvailability(for: $0) }
        )
        XCTAssertTrue(harness.send(keyCode: 6, characters: "z"))

        XCTAssertFalse(harness.send(type: .keyUp, keyCode: 12, characters: "q"))
        XCTAssertTrue(harness.send(type: .keyUp, keyCode: 6, characters: "z"))
        XCTAssertEqual(harness.sink.releasePreviewCount, 1)
        XCTAssertEqual(harness.sink.cancelPreviewCount, 0)
        XCTAssertNil(harness.previewer.activePreviewToken)
        XCTAssertEqual(document, before)
    }

    func testActiveAuditionPreviewDoesNotDisableStoppedEditableMetadataControls() throws {
        let document = makeEditableDocument(palette: makeInstrumentPalette())
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(document))
        let descendants = try XCTUnwrap(controller.window?.contentView).instrumentEditorDescendants
        let harness = InstrumentEditorAuditionHarness(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            selectedOctave: 4,
            availability: { document.noteAuditionAvailability(for: $0) }
        )

        XCTAssertTrue(harness.send(keyCode: 6, characters: "z"))
        XCTAssertNotNil(harness.previewer.activePreviewToken)
        XCTAssertTrue(try XCTUnwrap(controller.window?.contentView?.instrumentEditorNameField).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleVolumeControl).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleRelativeNoteControl).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleFinetuneControl).isEnabled)
        XCTAssertTrue(try XCTUnwrap(descendants.samplePanningControl).isEnabled)
        XCTAssertTrue(harness.send(type: .keyUp, keyCode: 6, characters: "z"))
    }

    func testNextAuditionRebuildsVolumePitchAndPanningAfterMetadataEditsWithoutLiveRetrigger() throws {
        var document = makeEditableDocument(palette: makeInstrumentPalette())
        let undoManager = UndoManager()
        let coordinator = EditableDocumentEditCoordinator(
            undoManager: undoManager,
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: { document = $0 }
        )
        let harness = InstrumentEditorAuditionHarness(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            selectedOctave: 4,
            availability: { document.noteAuditionAvailability(for: $0) }
        )

        func triggerAndRelease() throws -> EditorNoteAuditionPreviewRenderParameters {
            XCTAssertTrue(harness.send(keyCode: 6, characters: "z"))
            let event = try XCTUnwrap(harness.sink.events.last)
            XCTAssertTrue(harness.send(type: .keyUp, keyCode: 6, characters: "z"))
            return try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: event, sampleRate: 8_363))
        }

        let original = try triggerAndRelease()
        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 1, sampleAt: 1, volume: 16))
        XCTAssertEqual(harness.sink.events.count, 1)
        let quieter = try triggerAndRelease()
        XCTAssertEqual(quieter.gain, EditorNoteAuditionPreviewGainPolicy.gain(sampleVolume: 0.25), accuracy: 0.000_001)
        XCTAssertLessThan(quieter.gain, original.gain)

        XCTAssertTrue(coordinator.setSampleFinetune(instrumentAt: 1, sampleAt: 1, finetune: 64))
        XCTAssertEqual(harness.sink.events.count, 2)
        let retuned = try triggerAndRelease()
        XCTAssertNotEqual(retuned.playbackStep, quieter.playbackStep, accuracy: 0.000_001)

        XCTAssertTrue(coordinator.setSampleRelativeNote(instrumentAt: 1, sampleAt: 1, relativeNote: 12))
        XCTAssertEqual(harness.sink.events.count, 3)
        let transposed = try triggerAndRelease()
        XCTAssertGreaterThan(transposed.playbackStep, retuned.playbackStep)

        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 1, sampleAt: 1, panning: 201))
        XCTAssertEqual(harness.sink.events.count, 4)
        XCTAssertEqual(document.instrumentPalette[2]?.samples[1].panning, 201)
        let repanned = try triggerAndRelease()
        XCTAssertEqual(repanned.pan, PlaybackSamplePanningPolicy.plannedPan(201), accuracy: 0.000_001)
        XCTAssertEqual(repanned.gain, transposed.gain)
        XCTAssertEqual(repanned.playbackStep, transposed.playbackStep)
        XCTAssertEqual(repanned.loop, transposed.loop)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(coordinator.undoMenuItemTitle, "Undo Change Sample Panning")
    }

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("tests/reference-xm").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Missing reference XM fixture \(relativePath)") }
        return url
    }

    private func instrumentEditorKeyboard(in controller: InstrumentEditorWindowController) throws -> InstrumentEditorKeyboardPlaceholderView {
        try XCTUnwrap(controller.window?.contentView?.instrumentEditorDescendants
            .compactMap { $0 as? InstrumentEditorKeyboardPlaceholderView }.first)
    }

}

@MainActor
private func makeInstrumentEditorTestWindow(title: String) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = title
    return window
}

@MainActor
private func makeInstrumentEditorTestAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Editable copy created"
    alert.informativeText = "Test sheet"
    alert.addButton(withTitle: "OK")
    return alert
}

@MainActor
private func instrumentEditorAuditionAction(
    type: NSEvent.EventType = .keyDown,
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags = [],
    isARepeat: Bool = false,
    isKeyWindow: Bool = true,
    firstResponder: NSResponder? = nil
) -> InstrumentEditorNoteAuditionRoutingAction? {
    InstrumentEditorNoteAuditionRoutingPolicy.action(
        eventType: type,
        keyCode: keyCode,
        charactersIgnoringModifiers: characters,
        modifierFlags: modifierFlags,
        isARepeat: isARepeat,
        isKeyWindow: isKeyWindow,
        firstResponder: firstResponder
    )
}

private func makeInstrumentEditorKeyEvent(
    type: NSEvent.EventType = .keyDown,
    keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags = [],
    isARepeat: Bool = false
) -> NSEvent {
    NSEvent.keyEvent(
        with: type,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: isARepeat,
        keyCode: keyCode
    )!
}

@MainActor
private func instrumentEditorPointerEvent(_ type: NSEvent.EventType, in control: NSView, x: CGFloat, y: CGFloat) throws -> NSEvent {
    NSEvent.mouseEvent(with: type, location: control.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [],
                       timestamp: 0, windowNumber: control.window?.windowNumber ?? 0, context: nil,
                       eventNumber: 0, clickCount: 1, pressure: 1)!
}

private final class InstrumentEditorRecordingAuditionSink: EditorNoteAuditionPreviewSink {
    private(set) var events: [EditorNoteAuditionPreviewEvent] = []
    private(set) var releasePreviewCount = 0
    private(set) var cancelPreviewCount = 0

    func preview(_ event: EditorNoteAuditionPreviewEvent) -> Bool {
        events.append(event)
        return true
    }

    func releasePreview() {
        releasePreviewCount += 1
    }

    func cancelPreview() {
        cancelPreviewCount += 1
    }
}

@MainActor
private final class InstrumentEditorAuditionHarness {
    let sink = InstrumentEditorRecordingAuditionSink()
    let previewer: EditorNoteAuditionPreviewer
    let router: InstrumentEditorKeyboardAuditionRouter

    init(
        selection: TrackerEditorSelection,
        sourceContext: EditorNoteAuditionSourceContext,
        selectedOctave: Int,
        channelIndex: Int? = nil,
        rowIndex: Int? = nil,
        availability: @escaping (EditorNoteAuditionRequest) -> EditorNoteAuditionAvailability
    ) {
        previewer = EditorNoteAuditionPreviewer(sink: sink)
        router = InstrumentEditorKeyboardAuditionRouter()
        router.noteKeyDownHandler = { [previewer] character, isRepeat in
            let route = EditorNoteAuditionInputPolicy.route(
                input: .noteKey(isRepeat: isRepeat),
                editModeEnabled: false,
                sourceContext: sourceContext,
                isNoteField: true
            )
            guard route.shouldAttemptPreview else {
                return route.shouldConsumeNonMutatingInput(previewOutcome: .skipped(.missingRequest))
            }
            let request = InstrumentEditorAuditionRequestFactory.request(
                trackerKey: character,
                selectedOctave: selectedOctave,
                selection: selection,
                sourceContext: sourceContext,
                channelIndex: channelIndex,
                rowIndex: rowIndex,
                isRepeatedKeyDown: isRepeat
            )
            let outcome = previewer.preview(
                request: request,
                availability: request.map(availability) ?? .unavailable(.selectedInstrumentSampleNotPlayable),
                keyIdentity: EditorNoteAuditionKeyIdentity(trackerKey: character)
            )
            return route.shouldConsumeNonMutatingInput(previewOutcome: outcome)
        }
        router.noteKeyUpHandler = { [previewer] character in
            EditorNoteAuditionKeyIdentity(trackerKey: character).map(previewer.stopPreview(for:)) ?? false
        }
    }

    func send(
        type: NSEvent.EventType = .keyDown,
        keyCode: UInt16,
        characters: String,
        isARepeat: Bool = false
    ) -> Bool {
        router.handle(
            makeInstrumentEditorKeyEvent(
                type: type,
                keyCode: keyCode,
                characters: characters,
                isARepeat: isARepeat
            ),
            isKeyWindow: true,
            firstResponder: NSButton()
        )
    }
}

private func makeInstrumentPalette() -> [Int: PlaybackInstrument] {
    let bass = PlaybackInstrument(
        index: 1,
        name: "Bass",
        samples: [makeInstrumentEditorSample(instrument: 1, sample: 0, name: "Bass Core")]
    )
    let lead = PlaybackInstrument(
        index: 2,
        name: "Lead",
        samples: [
            makeInstrumentEditorSample(instrument: 2, sample: 0, name: "Lead Soft"),
            makeInstrumentEditorSample(
                instrument: 2,
                sample: 1,
                name: "Lead Bright",
                length: 1024,
                volume: 0.75,
                panning: 32,
                relativeNote: 2,
                finetune: -8,
                loopStart: 128,
                loopLength: 256,
                loopType: 2
            ),
        ],
        volumeEnvelope: PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 0),
                PlaybackEnvelopePoint(tick: 12, value: 64),
                PlaybackEnvelopePoint(tick: 36, value: 24),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 1,
            loopEndPointIndex: 2,
            typeFlags: 0x07,
            fadeout: 128
        ),
        panningEnvelope: makeInstrumentEditorPanningEnvelope(),
        autoVibrato: PlaybackInstrumentAutoVibrato(
            waveformType: 3,
            sweep: 17,
            depth: 42,
            rate: 199
        ),
        noteSampleMap: Array(repeating: 0, count: 48) + Array(repeating: 1, count: 48)
    )
    return [1: bass, 2: lead]
}

private func makeInstrumentEditorPanningEnvelope() -> PlaybackPanningEnvelope {
    PlaybackPanningEnvelope(
        enabled: true,
        points: [
            PlaybackEnvelopePoint(tick: 0, value: 32),
            PlaybackEnvelopePoint(tick: 8, value: 48),
            PlaybackEnvelopePoint(tick: 20, value: 12),
            PlaybackEnvelopePoint(tick: 32, value: 40),
        ],
        sustainPointIndex: 2,
        loopStartPointIndex: 0,
        loopEndPointIndex: 3,
        typeFlags: 0x07
    )
}

private func makeInstrumentEditorSample(
    instrument: Int,
    sample: Int,
    name: String,
    length: Int = 4,
    volume: Float = 1,
    panning: UInt8 = 128,
    relativeNote: Int = 0,
    finetune: Int = 0,
    loopStart: Int = 0,
    loopLength: Int = 0,
    loopType: Int = 0
) -> PlaybackSample {
    PlaybackSample(
        instrumentIndex: instrument,
        sampleIndex: sample,
        name: name,
        pcm: Array(repeating: 0.25, count: length),
        volume: volume,
        panning: panning,
        relativeNote: relativeNote,
        finetune: finetune,
        baseSampleRate: 8_363,
        loopStart: loopStart,
        loopLength: loopLength,
        loopType: loopType
    )
}

private func makePlaybackSong(instruments: [Int: PlaybackInstrument]) -> PlaybackSong {
    PlaybackSong(
        title: "Synthetic",
        orders: [],
        patternsByIndex: [:],
        instrumentsByIndex: instruments,
        restartOrderIndex: 0,
        endBehavior: .stopAtEnd
    )
}

private func makeEditableDocument(
    palette: [Int: PlaybackInstrument],
    selection: TrackerEditorSelection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
) -> BlankTrackerDocument {
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
        selection: selection,
        instrumentPalette: palette,
        patterns: base.patterns
    )
}

private func makeInstrumentEditorRangeDocument(
    noteSampleMap: [Int]? = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue),
    samples: [PlaybackSample]? = nil,
    selection: TrackerEditorSelection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
) -> BlankTrackerDocument {
    var palette = makeInstrumentPalette()
    let instrument = palette[2]!
    palette[2] = PlaybackInstrument(
        index: 2,
        name: "Lead",
        samples: samples ?? instrument.samples,
        noteSampleMap: noteSampleMap
    )
    return makeEditableDocument(palette: palette, selection: selection)
}

private func makeRangeAssignmentContext(
    _ identity: UUID,
    _ revision: UInt64,
    _ document: BlankTrackerDocument,
    isPlaying: Bool = false
) -> InstrumentKeymapRangeAssignmentContext {
    InstrumentKeymapRangeAssignmentContext(
        documentIdentity: identity,
        documentRevision: revision,
        editContext: .editable(document: document, isPlaybackActive: isPlaying),
        hasConflictingModalSheet: false
    )
}

private extension NSView {
    var instrumentEditorDescendants: [NSView] {
        [self] + subviews.flatMap(\.instrumentEditorDescendants)
    }

    var instrumentEditorNameField: NSTextField? {
        instrumentEditorDescendants.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.instrumentNameField
        }
    }

    func identifiedView(_ identifier: String) throws -> NSView {
        try XCTUnwrap(instrumentEditorDescendants.first { $0.identifier?.rawValue == identifier })
    }

    func envelopeSelector(_ mode: InstrumentEnvelopeDisplayMode) throws -> VTXEditorButton {
        let identifier = mode == .volume
            ? InstrumentEditorViewIdentifier.volumeEnvelopeTab
            : InstrumentEditorViewIdentifier.panningEnvelopeTab
        return try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? VTXEditorButton }.first {
            $0.identifier?.rawValue == identifier
        })
    }

    func envelopeReadout(_ readout: InstrumentEnvelopeReadout) throws -> VTXEditorSegmentReadout {
        try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? VTXEditorSegmentReadout }.first {
            $0.identifier?.rawValue == readout.identifier
        })
    }

    func envelopeGraph() throws -> InstrumentEditorEnvelopeGraphView {
        try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? InstrumentEditorEnvelopeGraphView }.first)
    }

    func keyboardRangeButton(_ direction: InstrumentKeyboardRangeShift) throws -> VTXEditorButton {
        let identifier = direction == .lower
            ? InstrumentEditorViewIdentifier.keymapPreviousOctave
            : InstrumentEditorViewIdentifier.keymapNextOctave
        return try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? VTXEditorButton }.first {
            $0.identifier?.rawValue == identifier
        })
    }

    func keymapRangeAssignmentButton() throws -> VTXEditorButton {
        try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? VTXEditorButton }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.keymapRangeAssignment
        })
    }

    func keymapRangeStrip() throws -> InstrumentEditorKeymapRangeView {
        try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? InstrumentEditorKeymapRangeView }.first)
    }

    func instrumentRow(slot: Int) throws -> InstrumentEditorListRowControl {
        try listRow(prefix: InstrumentEditorViewIdentifier.instrumentRowPrefix, label: "I", slot: slot)
    }

    func sampleRow(slot: Int) throws -> InstrumentEditorListRowControl {
        try listRow(prefix: InstrumentEditorViewIdentifier.sampleRowPrefix, label: "S", slot: slot)
    }

    private func listRow(prefix: String, label: String, slot: Int) throws -> InstrumentEditorListRowControl {
        let identifier = prefix + String(format: "%@%02X", label, slot)
        return try XCTUnwrap(instrumentEditorDescendants.compactMap { $0 as? InstrumentEditorListRowControl }.first {
            $0.identifier?.rawValue == identifier
        })
    }
}

@MainActor
private extension Array where Element == NSView {
    var sampleVolumeControl: VTXEditorKnobControl? {
        compactMap { $0 as? VTXEditorKnobControl }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleVolumeControl
        }
    }

    var sampleVolumeReadout: VTXEditorSegmentReadout? {
        compactMap { $0 as? VTXEditorSegmentReadout }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleVolumeReadout
        }
    }

    var sampleRelativeNoteControl: TrackerStepper? {
        compactMap { $0 as? TrackerStepper }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleRelativeNoteControl
        }
    }

    var sampleRelativeNoteReadout: VTXEditorSegmentReadout? {
        compactMap { $0 as? VTXEditorSegmentReadout }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleRelativeNoteReadout
        }
    }

    var sampleFinetuneControl: VTXEditorKnobControl? {
        compactMap { $0 as? VTXEditorKnobControl }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleFinetuneControl
        }
    }

    var sampleFinetuneReadout: VTXEditorSegmentReadout? {
        compactMap { $0 as? VTXEditorSegmentReadout }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.sampleFinetuneReadout
        }
    }

    var samplePanningControl: VTXEditorPanSliderControl? {
        compactMap { $0 as? VTXEditorPanSliderControl }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.samplePanningControl
        }
    }

    var samplePanningReadout: NSTextField? {
        compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.samplePanningReadout
        }
    }
}
