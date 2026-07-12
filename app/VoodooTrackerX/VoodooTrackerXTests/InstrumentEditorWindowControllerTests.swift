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
        XCTAssertNil(noDocument.selectedInstrumentSlot)
        XCTAssertTrue(noDocument.instrumentSlots.isEmpty)
        XCTAssertTrue(noDocument.sampleSlots.isEmpty)
        XCTAssertNil(noDocument.volumeEnvelope)
        XCTAssertTrue(noDocument.keymapRanges.isEmpty)
        XCTAssertEqual(noDocument.emptyMessage, "No document instrument palette is available.")

        XCTAssertEqual(blankDocument.source, .editableDocument)
        XCTAssertTrue(blankDocument.isReadOnly)
        XCTAssertFalse(blankDocument.isInstrumentNameEditable)
        XCTAssertNil(blankDocument.selectedInstrumentSlot)
        XCTAssertTrue(blankDocument.instrumentSlots.isEmpty)
        XCTAssertTrue(blankDocument.sampleSlots.isEmpty)
        XCTAssertNil(blankDocument.volumeEnvelope)
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
        XCTAssertEqual(state.keymapRanges.map(\.startNote), [1, 49])
        XCTAssertEqual(state.keymapRanges.map(\.endNote), [48, 96])
        XCTAssertEqual(state.keymapRanges.map(\.sampleDisplay), ["S01", "S02"])
        XCTAssertEqual(state.keymapRanges.map(\.isSelected), [false, true])
        XCTAssertEqual(song, before)
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
        XCTAssertEqual(sample.volumeDisplay, "48 / 64")
        XCTAssertEqual(sample.relativeNoteDisplay, "+2")
        XCTAssertEqual(sample.finetuneDisplay, "-8")
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
    }

    func testWindowCreatesFixedMockupHierarchyWithOnlyNameFieldEditable() throws {
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
        XCTAssertTrue(fieldValues.contains("NAME EDITABLE"))
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
            ["IMPORT XI", "EXPORT XI", "▶", "VOL", "PAN", "+ ADD PT", "DEL PT", "ON", "∿", "⊓", "⊿", "◺", "◀ C-2", "C-4 ▶"]
        )
        XCTAssertEqual(futureControls.compactMap { $0 as? VTXEditorKnobControl }.count, 5)
        XCTAssertEqual(futureControls.compactMap { $0 as? VTXEditorPanSliderControl }.count, 1)

        let envelopeGraph = try XCTUnwrap(descendants.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.envelopeGraph
        })
        let keyboard = try XCTUnwrap(descendants.first {
            $0.identifier?.rawValue == InstrumentEditorViewIdentifier.keyboardPlaceholder
        })
        XCTAssertNil(envelopeGraph.hitTest(.zero))
        XCTAssertNil(keyboard.hitTest(.zero))
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
        noteSampleMap: Array(repeating: 0, count: 48) + Array(repeating: 1, count: 48)
    )
    return [1: bass, 2: lead]
}

private func makeInstrumentEditorSample(
    instrument: Int,
    sample: Int,
    name: String,
    length: Int = 4,
    volume: Float = 1,
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
}
