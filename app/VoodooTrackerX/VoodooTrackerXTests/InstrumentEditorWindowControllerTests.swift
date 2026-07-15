import AppKit
import XCTest

@MainActor
final class InstrumentEditorWindowControllerTests: XCTestCase {
    func testNoDocumentAndBlankDocumentProduceExplicitReadOnlyEmptyStates() {
        let noDocument = InstrumentEditorDisplayState.empty
        let blankDocument = InstrumentEditorDisplayState.editableDocument(.makeDefault())

        XCTAssertEqual(noDocument.source, .none)
        XCTAssertTrue(noDocument.isReadOnly)
        XCTAssertFalse(noDocument.isInstrumentNameEditable)
        XCTAssertFalse(noDocument.isSampleVolumeEditable)
        XCTAssertFalse(noDocument.isSampleFinetuneEditable)
        XCTAssertFalse(noDocument.isSamplePanningEditable)
        XCTAssertNil(noDocument.selectedInstrumentSlot)
        XCTAssertTrue(noDocument.instrumentSlots.isEmpty)
        XCTAssertTrue(noDocument.sampleSlots.isEmpty)
        XCTAssertNil(noDocument.volumeEnvelope)
        XCTAssertNil(noDocument.panningEnvelope)
        XCTAssertNil(noDocument.autoVibrato)
        XCTAssertTrue(noDocument.keymapRanges.isEmpty)
        XCTAssertEqual(noDocument.emptyMessage, "No document instrument palette is available.")

        XCTAssertEqual(blankDocument.source, .editableDocument)
        XCTAssertTrue(blankDocument.isReadOnly)
        XCTAssertFalse(blankDocument.isInstrumentNameEditable)
        XCTAssertFalse(blankDocument.isSampleVolumeEditable)
        XCTAssertFalse(blankDocument.isSampleFinetuneEditable)
        XCTAssertFalse(blankDocument.isSamplePanningEditable)
        XCTAssertNil(blankDocument.selectedInstrumentSlot)
        XCTAssertTrue(blankDocument.instrumentSlots.isEmpty)
        XCTAssertTrue(blankDocument.sampleSlots.isEmpty)
        XCTAssertNil(blankDocument.volumeEnvelope)
        XCTAssertNil(blankDocument.panningEnvelope)
        XCTAssertNil(blankDocument.autoVibrato)
        XCTAssertTrue(blankDocument.keymapRanges.isEmpty)
        XCTAssertEqual(blankDocument.emptyMessage, "No represented instruments are available.")
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

    func testVolumeFinetuneAndPanAreEnabledOnlyForStoppedEditableRepresentedSample() throws {
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
            let finetune = try XCTUnwrap(descendants.sampleFinetuneControl)
            let pan = try XCTUnwrap(descendants.samplePanningControl)
            XCTAssertEqual(volume.isEnabled, expectedEnabled)
            XCTAssertEqual(finetune.isEnabled, expectedEnabled)
            XCTAssertEqual(pan.isEnabled, expectedEnabled)
            XCTAssertEqual(state.isSampleVolumeEditable, expectedEnabled)
            XCTAssertEqual(state.isSampleFinetuneEditable, expectedEnabled)
            XCTAssertEqual(state.isSamplePanningEditable, expectedEnabled)
            XCTAssertEqual(volume.minimumValue, 0)
            XCTAssertEqual(volume.maximumValue, 64)
            XCTAssertEqual(volume.value, 48)
            XCTAssertFalse(volume.isContinuous)
            XCTAssertEqual(finetune.minimumValue, -128)
            XCTAssertEqual(finetune.maximumValue, 127)
            XCTAssertEqual(finetune.value, -8)
            XCTAssertFalse(finetune.isContinuous)
            XCTAssertEqual(pan.value, -0.75, accuracy: 0.000_001)
            XCTAssertEqual(descendants.sampleVolumeReadout?.stringValue, "48")
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

    func testEmptySampleStateKeepsVolumeFinetuneAndPanDisplaysCleanAndInert() throws {
        let controller = InstrumentEditorWindowController(displayState: .editableDocument(.makeDefault()))
        let descendants = try XCTUnwrap(controller.window?.contentView).instrumentEditorDescendants
        let volume = try XCTUnwrap(descendants.sampleVolumeControl)
        let finetune = try XCTUnwrap(descendants.sampleFinetuneControl)
        let pan = try XCTUnwrap(descendants.compactMap { $0 as? VTXEditorPanSliderControl }.first)

        XCTAssertFalse(volume.isEnabled)
        XCTAssertEqual(volume.value, 0)
        XCTAssertEqual(descendants.sampleVolumeReadout?.stringValue, "—")
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
        XCTAssertFalse(playingState.isSampleFinetuneEditable)
        XCTAssertFalse(playingState.isSamplePanningEditable)
    }

    func testWindowCreatesFixedMockupHierarchyWithNameVolumeFinetuneAndPanEditable() throws {
        let controller = InstrumentEditorWindowController(
            displayState: .editableDocument(makeEditableDocument(palette: makeInstrumentPalette()))
        )
        let window = try XCTUnwrap(controller.window)
        let panel = try XCTUnwrap(window as? NSPanel)
        let contentView = try XCTUnwrap(window.contentView)
        let descendants = contentView.instrumentEditorDescendants
        let identifiers = Set(descendants.compactMap { $0.identifier?.rawValue })
        let fieldValues = Set(descendants.compactMap { ($0 as? NSTextField)?.stringValue })

        XCTAssertEqual(window.title, "Instrument Editor")
        XCTAssertTrue(window.styleMask.contains(.utilityWindow))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, InstrumentEditorWindowController.contentSize)
        XCTAssertEqual(window.contentMaxSize, InstrumentEditorWindowController.contentSize)
        XCTAssertTrue(panel.isFloatingPanel)
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
        XCTAssertTrue(fieldValues.contains("N/V/F/P EDIT"))
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
            ["IMPORT XI", "EXPORT XI", "▶", "+ ADD PT", "DEL PT", "ON", "∿", "⊓", "⊿", "◺", "◀ C-2", "C-4 ▶"]
        )
        XCTAssertEqual(futureControls.compactMap { $0 as? VTXEditorKnobControl }.count, 3)
        XCTAssertEqual(futureControls.compactMap { $0 as? VTXEditorPanSliderControl }.count, 0)
        XCTAssertTrue(try XCTUnwrap(descendants.sampleVolumeControl).isEnabled)
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

    func testApplyingSelectionChangeRefreshesVisibleSampleRows() throws {
        let palette = makeInstrumentPalette()
        let controller = InstrumentEditorWindowController(displayState: .loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))
        let contentView = try XCTUnwrap(controller.window?.contentView as? InstrumentEditorView)
        let initialRebuildCount = contentView.rebuildCount
        let updated = InstrumentEditorDisplayState.loadedModule(
            playbackSong: makePlaybackSong(instruments: palette),
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2)
        )

        XCTAssertTrue(controller.apply(displayState: updated))
        XCTAssertEqual(contentView.displayState, updated)
        XCTAssertEqual(contentView.rebuildCount, initialRebuildCount + 1)
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

    func testPresenterReusesOneControllerForRepeatedOpenCommands() throws {
        let presenter = InstrumentEditorWindowPresenter()
        let state = InstrumentEditorDisplayState.editableDocument(.makeDefault())

        let first = presenter.show(displayState: state)
        let second = presenter.show(displayState: state)

        XCTAssertTrue(first === second)
        XCTAssertTrue(first.window === second.window)
        XCTAssertTrue(first.window?.isVisible == true)

        first.window?.close()
        XCTAssertNil(presenter.windowController)
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

private func makeEditableDocument(palette: [Int: PlaybackInstrument]) -> BlankTrackerDocument {
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
        selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 2),
        instrumentPalette: palette,
        patterns: base.patterns
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
}
