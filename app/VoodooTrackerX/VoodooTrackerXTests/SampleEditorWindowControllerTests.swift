import AppKit
import XCTest

@MainActor
final class SampleEditorWindowControllerTests: XCTestCase {
    func testNoDocumentAndBlankDocumentStayHonestlyEmptyAndReadOnly() {
        let noDocument = SampleEditorDisplayState.empty
        let blank = SampleEditorDisplayState.editableDocument(.makeDefault())

        XCTAssertTrue(noDocument.isReadOnly)
        XCTAssertTrue(noDocument.instrumentOptions.isEmpty)
        XCTAssertEqual(noDocument.instrumentDisplay, "—")

        XCTAssertTrue(blank.isReadOnly)
        XCTAssertEqual(blank.instrumentOptions.map(\.title), ["I01  (unnamed instrument)"])
        XCTAssertEqual(blank.instrumentOptions.map(\.isSelected), [true])
        XCTAssertEqual(blank.instrumentDisplay, "I01")
        XCTAssertEqual(blank.instrumentName, "(unnamed instrument)")
        XCTAssertNil(blank.selectedSample)
        XCTAssertTrue(blank.sampleSlots.isEmpty)
        XCTAssertEqual(blank.sampleName, "No represented sample")
        XCTAssertEqual(blank.sampleDisplay, "—")
        XCTAssertEqual(blank.lengthDisplay, "—")
        XCTAssertEqual(blank.formatDisplay, "FORMAT UNAVAILABLE")
        XCTAssertEqual(blank.loop.status, .inactive)
        XCTAssertEqual(blank.loop.endDisplay, "—")
        XCTAssertTrue(blank.waveformPCM.isEmpty)
        XCTAssertEqual(blank.volumeDisplay, "—")
        XCTAssertEqual(blank.panningDisplay, "—")
        XCTAssertEqual(blank.relativeNoteDisplay, "—")
        XCTAssertEqual(blank.finetuneDisplay, "—")
    }

    func testInstrumentPopupIsEmptyAndDisabledWithoutDocumentContext() throws {
        let controller = SampleEditorWindowController(
            displayState: .empty,
            instrumentSelectionHandler: { _ in true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? SampleEditorView)
        let selector = try XCTUnwrap(view.instrumentSelector)

        XCTAssertEqual(selector.numberOfItems, 0)
        XCTAssertFalse(selector.isEnabled)
        XCTAssertFalse(selector.pullsDown)
        XCTAssertTrue(selector.cell is NSPopUpButtonCell)
        XCTAssertNil(selector.cell as? NSTextFieldCell)
        XCTAssertEqual(selector.accessibilityLabel(), "Sample Editor instrument")
        XCTAssertEqual(selector.accessibilityValue() as? String, "No instrument selected")
    }

    func testBlankDocumentPopupSelectsI01WhileSampleSurfacesStayEmpty() throws {
        let controller = SampleEditorWindowController(
            displayState: .editableDocument(.makeDefault()),
            instrumentSelectionHandler: { _ in true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? SampleEditorView)
        let selector = try XCTUnwrap(view.instrumentSelector)

        XCTAssertEqual(selector.numberOfItems, 1)
        XCTAssertEqual(selector.selectedItem?.representedObject as? Int, 1)
        XCTAssertEqual(selector.accessibilityValue() as? String, "I01  (unnamed instrument)")
        XCTAssertTrue(selector.isEnabled)
        XCTAssertNil(view.displayState.selectedSample)
        XCTAssertTrue(view.displayState.waveformPCM.isEmpty)
        XCTAssertEqual(view.displayState.loop, .inactive)
    }

    func testMetadataMatrixInstrumentPopupUsesOrderedOneBasedTitlesAndCanonicalSelection() throws {
        let song = try loadReferenceSong("generated/instrument-metadata-matrix.xm")
        let before = song
        var selection = TrackerEditorSelection.default
        var callbackCount = 0
        var controller: SampleEditorWindowController!
        controller = SampleEditorWindowController(
            displayState: .loadedModule(playbackSong: song, selection: selection),
            instrumentSelectionHandler: { slot in
                callbackCount += 1
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
        let view = try XCTUnwrap(controller.window?.contentView as? SampleEditorView)
        let selector = try XCTUnwrap(view.instrumentSelector)

        XCTAssertEqual(view.displayState.instrumentOptions.map(\.title), [
            "I01  PAN00 VOL00 NEG",
            "I02  PAN64 VOL16 FWD",
            "I03  PAN128 VOL32 PP",
            "I04  PAN192 VOL48 POS",
            "I05  PAN255 VOL64 FWD",
        ])
        XCTAssertEqual(selector.itemTitles, view.displayState.instrumentOptions.map(\.title))
        XCTAssertEqual(selector.itemArray.compactMap { $0.representedObject as? Int }, [1, 2, 3, 4, 5])
        XCTAssertEqual(selector.selectedItem?.representedObject as? Int, 1)
        XCTAssertEqual(selector.accessibilityValue() as? String, "I01  PAN00 VOL00 NEG")
        XCTAssertTrue(selector.isEnabled)

        let expected: [(slot: Int, sampleName: String, format: String, loop: SampleLoopDisplayState.Mode)] = [
            (2, "TRIANGLE FWD 16", "16-BIT · MONO", .forward),
            (3, "SAW PINGPONG 8", "8-BIT · MONO", .pingPong),
            (4, "PULSE ONESHOT 16", "16-BIT · MONO", .none),
            (5, "TRIANGLE FWD 8", "8-BIT · MONO", .forward),
            (1, "SILENT SINE 8", "8-BIT · MONO", .none),
        ]
        for (index, value) in expected.enumerated() {
            let currentSelector = try XCTUnwrap(view.instrumentSelector)
            currentSelector.selectItem(at: value.slot - 1)
            XCTAssertTrue(currentSelector.sendAction(currentSelector.action, to: currentSelector.target))
            XCTAssertEqual(callbackCount, index + 1)
            XCTAssertEqual(selection, TrackerEditorSelection(selectedInstrument: value.slot, selectedSample: 1))
            XCTAssertEqual(view.displayState.instrumentSlot, value.slot)
            XCTAssertEqual(view.displayState.sampleName, value.sampleName)
            XCTAssertEqual(view.displayState.formatDisplay, value.format)
            XCTAssertEqual(view.displayState.loop.mode, value.loop)
            XCTAssertEqual(view.instrumentSelector?.selectedItem?.representedObject as? Int, value.slot)
            XCTAssertEqual(
                InstrumentEditorDisplayState.loadedModule(
                    playbackSong: song,
                    selection: selection
                ).selectedInstrumentSlot,
                value.slot
            )
        }
        XCTAssertEqual(song, before)

        let externalSelection = TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)
        XCTAssertTrue(controller.apply(displayState: .loadedModule(playbackSong: song, selection: externalSelection)))
        XCTAssertEqual(callbackCount, expected.count)
        XCTAssertEqual(view.instrumentSelector?.selectedItem?.representedObject as? Int, 2)
    }

    func testUnnamedRepresentedSampleAndSamplelessInstrumentHaveDistinctCoherentStates() {
        let unnamedSample = makePlaybackSample(name: "   ", pcm: [-0.5, 0.5], volume: 0.25)
        let song = makeSampleEditorSong(instruments: [
            1: PlaybackInstrument(index: 1, name: "", samples: [unnamedSample]),
            2: PlaybackInstrument(index: 2, name: "Sampleless", samples: []),
        ])
        let before = song

        let represented = SampleEditorDisplayState.loadedModule(playbackSong: song, selection: .default)
        XCTAssertEqual(represented.instrumentOptions.map(\.title), [
            "I01  (unnamed instrument)", "I02  Sampleless",
        ])
        XCTAssertEqual(represented.sampleName, "(unnamed sample)")
        XCTAssertEqual(represented.sampleDisplay, "S01")
        XCTAssertEqual(represented.sampleSlots.filter(\.isSelected).map(\.slot), [1])
        XCTAssertEqual(represented.waveformPCM, [-0.5, 0.5])
        XCTAssertEqual(represented.lengthDisplay, "000002")
        XCTAssertEqual(represented.volumeDisplay, "16")

        let absent = SampleEditorDisplayState.loadedModule(
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1)
        )
        XCTAssertEqual(absent.instrumentName, "Sampleless")
        XCTAssertEqual(absent.sampleName, "No represented sample")
        XCTAssertEqual(absent.sampleDisplay, "—")
        XCTAssertTrue(absent.sampleSlots.isEmpty)
        XCTAssertNil(absent.selectedSample)
        XCTAssertTrue(absent.waveformPCM.isEmpty)
        XCTAssertEqual(absent.lengthDisplay, "—")
        XCTAssertEqual(absent.formatDisplay, "FORMAT UNAVAILABLE")
        XCTAssertEqual(absent.volumeDisplay, "—")
        XCTAssertEqual(absent.panningDisplay, "—")
        XCTAssertEqual(absent.relativeNoteDisplay, "—")
        XCTAssertEqual(absent.finetuneDisplay, "—")
        XCTAssertEqual(absent.loop, .inactive)
        XCTAssertEqual(song, before)
    }

    func testMetadataMatrixFixtureProducesExactMetadataAndLoopModes() throws {
        let song = try loadReferenceSong("generated/instrument-metadata-matrix.xm")
        let expected: [(Int, String, Int, Int, Int, UInt8, Int, Int, SampleLoopDisplayState.Mode, Int, Int)] = [
            (1, "SILENT SINE 8", 256, 8, 0, 0, -12, -96, .none, 0, 0),
            (2, "TRIANGLE FWD 16", 512, 16, 16, 64, 5, -32, .forward, 64, 256),
            (3, "SAW PINGPONG 8", 384, 8, 32, 128, -5, 0, .pingPong, 64, 256),
            (4, "PULSE ONESHOT 16", 640, 16, 48, 192, 12, 48, .none, 0, 0),
            (5, "TRIANGLE FWD 8", 768, 8, 64, 255, 0, 96, .forward, 128, 512),
        ]

        for value in expected {
            let state = SampleEditorDisplayState.loadedModule(
                playbackSong: song,
                selection: TrackerEditorSelection(selectedInstrument: value.0, selectedSample: 1)
            )
            XCTAssertEqual(state.sampleName, value.1)
            XCTAssertEqual(state.frameLength, value.2)
            XCTAssertEqual(state.bitDepthBits, value.3)
            XCTAssertEqual(state.volume, value.4)
            XCTAssertEqual(state.panning, value.5)
            XCTAssertEqual(state.relativeNote, value.6)
            XCTAssertEqual(state.finetune, value.7)
            XCTAssertEqual(state.loop.mode, value.8)
            XCTAssertEqual(state.loop.startFrame, value.9)
            XCTAssertEqual(state.loop.lengthFrames, value.10)
            XCTAssertEqual(state.loop.endFrame, value.9 + value.10)
            XCTAssertEqual(state.loop.status, value.8 == .none ? .inactive : .valid)
            XCTAssertEqual(state.waveformPCM.count, value.2)
            XCTAssertTrue(state.isReadOnly)
        }
    }

    func testLoadedAndEditableCopyExposeTheSameReadOnlySampleWithoutMutation() throws {
        let fixture = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
        let before = song
        let selection = TrackerEditorSelection.default
        let loaded = SampleEditorDisplayState.loadedModule(playbackSong: song, selection: selection)
        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: selection,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        guard case let .copied(document) = result else { return XCTFail("expected editable copy") }
        let editable = SampleEditorDisplayState.editableDocument(document)

        XCTAssertEqual(loaded.instrumentDisplay, "I01")
        XCTAssertEqual(loaded.sampleDisplay, "S01")
        XCTAssertEqual(loaded.sampleName, "SINE SUSTAIN 16")
        XCTAssertEqual(loaded.frameLength, 16_384)
        XCTAssertEqual(loaded.loop.startFrame, 4_096)
        XCTAssertEqual(loaded.loop.endFrame, 12_288)
        XCTAssertEqual(loaded.instrumentDisplay, editable.instrumentDisplay)
        XCTAssertEqual(loaded.instrumentName, editable.instrumentName)
        XCTAssertEqual(loaded.sampleSlots, editable.sampleSlots)
        XCTAssertEqual(loaded.selectedSample, editable.selectedSample)
        XCTAssertEqual(song, before)
    }

    func testExistingControllerRefreshesAfterMetadataEditUndoAndRedo() throws {
        let fixture = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        guard case let .copied(initialDocument) = result else { return XCTFail("expected editable copy") }

        var document = initialDocument
        let controller = SampleEditorWindowController(displayState: .editableDocument(document))
        let view = try XCTUnwrap(controller.window?.contentView as? SampleEditorView)
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: {
                document = $0
                controller.apply(displayState: .editableDocument($0))
            }
        )

        XCTAssertEqual(view.displayState.volume, 64)
        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
        XCTAssertEqual(view.displayState.volume, 17)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(view.displayState.volume, 64)
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(view.displayState.volume, 17)
    }

    func testCanonicalSampleRowSelectionRefreshesKeymapFixtureWithoutUndo() throws {
        let fixture = try referenceXMFixtureURL("generated/instrument-envelopes-keymap.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: false
        ))
        guard case let .copied(initialDocument) = result else { return XCTFail("expected editable copy") }
        var document = initialDocument
        let before = document
        let undoManager = UndoManager()
        let editCoordinator = EditableDocumentEditCoordinator(
            undoManager: undoManager,
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: { document = $0 }
        )
        var controller: SampleEditorWindowController!
        controller = SampleEditorWindowController(
            displayState: .editableDocument(document),
            sampleSelectionHandler: { slot in
                let previous = document.selection
                document.selectSample(slot)
                guard document.selection != previous else { return false }
                return controller.apply(displayState: .editableDocument(document))
            }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? SampleEditorView)

        XCTAssertTrue(try XCTUnwrap(view.sampleRow(slot: 2)).accessibilityPerformPress())
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(view.displayState.sampleName, "HIGH TRIANGLE 16")
        XCTAssertEqual(view.displayState.sampleSlots.map(\.isSelected), [false, true])
        XCTAssertEqual(view.displayState.waveformPCM.count, 2_048)
        XCTAssertEqual(document.instrumentPalette, before.instrumentPalette)
        XCTAssertEqual(document.patterns, before.patterns)
        XCTAssertFalse(editCoordinator.canUndo)
        XCTAssertFalse(undoManager.canUndo)
    }

    func testSelectedSampleRowScrollsIntoViewWithoutChangingInstrument() throws {
        let samples = (0..<12).map { index in
            makePlaybackSample(
                instrumentIndex: 1,
                sampleIndex: index,
                name: "Sample \(index + 1)",
                pcm: [Float(index) / 12]
            )
        }
        let song = makeSampleEditorSong(instruments: [
            1: PlaybackInstrument(index: 1, name: "Many samples", samples: samples),
        ])
        let selection = TrackerEditorSelection(selectedInstrument: 1, selectedSample: 12)
        let controller = SampleEditorWindowController(
            displayState: .loadedModule(playbackSong: song, selection: selection),
            sampleSelectionHandler: { _ in true }
        )
        let view = try XCTUnwrap(controller.window?.contentView as? SampleEditorView)
        let row = try XCTUnwrap(view.sampleRow(slot: 12))
        let scrollView = try XCTUnwrap(row.enclosingScrollView)

        scrollView.layoutSubtreeIfNeeded()
        XCTAssertTrue(scrollView.documentVisibleRect.intersects(row.frame))
        XCTAssertEqual(view.displayState.instrumentSlot, 1)
        XCTAssertEqual(view.displayState.selectedSampleSlot, 12)
    }

    func testProjectionHandlesEdgeCasesAndPreservesSignedExtrema() {
        XCTAssertTrue(SampleWaveformProjection.make(pcm: [], pixelWidth: 20).isEmpty)
        XCTAssertTrue(SampleWaveformProjection.make(pcm: [1], pixelWidth: 0).isEmpty)
        XCTAssertEqual(SampleWaveformProjection.make(pcm: [-0.25], pixelWidth: 20), [.init(minimum: -0.25, maximum: -0.25)])
        XCTAssertEqual(SampleWaveformProjection.make(pcm: [0, 0, 0], pixelWidth: 2), [
            .init(minimum: 0, maximum: 0), .init(minimum: 0, maximum: 0),
        ])
        XCTAssertEqual(SampleWaveformProjection.make(pcm: [-1, 0.5, -0.25, 1], pixelWidth: 2), [
            .init(minimum: -1, maximum: 0.5), .init(minimum: -0.25, maximum: 1),
        ])
        XCTAssertEqual(SampleWaveformProjection.make(pcm: [0.2, 0.8], pixelWidth: 1).first?.minimum, 0.2)
        XCTAssertEqual(SampleWaveformProjection.make(pcm: [-0.8, -0.2], pixelWidth: 1).first?.maximum, -0.2)
    }

    func testProjectionIsBoundedDeterministicFiniteAndDoesNotRewriteSource() {
        let pcm: [Float] = [.nan, -.infinity, -1, 0.25, .infinity, 1, -0.5, 0.5]
        let bitPatterns = pcm.map(\.bitPattern)
        let first = SampleWaveformProjection.make(pcm: pcm, pixelWidth: 3)
        let second = SampleWaveformProjection.make(pcm: pcm, pixelWidth: 3)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 3)
        XCTAssertTrue(first.allSatisfy { $0.minimum.isFinite && $0.maximum.isFinite })
        XCTAssertEqual(pcm.map(\.bitPattern), bitPatterns)
        XCTAssertLessThanOrEqual(SampleWaveformProjection.make(pcm: Array(repeating: 1, count: 10_000), pixelWidth: 80).count, 80)
    }

    func testProjectionCacheReusesWidthAndInvalidatesForWidthOrReplacedPayload() {
        let cache = SampleWaveformProjectionCache()
        cache.setSample(makePlaybackSample(pcm: [-1, 1]))
        let first = cache.projection(pixelWidth: 2)
        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(cache.projection(pixelWidth: 2), first)
        XCTAssertEqual(cache.buildCount, 1)
        _ = cache.projection(pixelWidth: 1)
        XCTAssertEqual(cache.buildCount, 2)
        cache.setSample(makePlaybackSample(pcm: [0.25, 0.5]))
        XCTAssertEqual(cache.projection(pixelWidth: 1), [.init(minimum: 0.25, maximum: 0.5)])
        XCTAssertEqual(cache.buildCount, 3)
    }

    func testLoopDisplayMapsModesAndRejectsInvalidMetadataWithoutMutation() {
        let none = makePlaybackSample(pcm: Array(repeating: 0, count: 100))
        let forward = makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: 25, loopLength: 50, loopType: 1)
        let pingPong = makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: 10, loopLength: 20, loopType: 2)
        let invalid = [
            makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: 10, loopLength: 20, loopType: 9),
            makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: -1, loopLength: 20, loopType: 1),
            makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: 10, loopLength: 0, loopType: 1),
            makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: 100, loopLength: 1, loopType: 1),
            makePlaybackSample(pcm: Array(repeating: 0, count: 100), loopStart: 80, loopLength: 21, loopType: 2),
            PlaybackSample(
                instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0], volume: 1, relativeNote: 0, finetune: 0,
                baseSampleRate: 8_363, sampleLength: 100, loopStart: 0, loopLength: 3, loopType: 2
            ),
            PlaybackSample(
                instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0], volume: 1, relativeNote: 0, finetune: 0,
                baseSampleRate: 8_363, sampleLength: 2, loopStart: Int.max, loopLength: 4, loopType: 1
            ),
        ]
        let invalidBefore = invalid

        XCTAssertEqual(SampleLoopDisplayState(sample: none).status, .inactive)
        XCTAssertEqual(SampleLoopDisplayState(sample: forward).mode, .forward)
        XCTAssertEqual(SampleLoopDisplayState(sample: forward).startFraction, 0.25)
        XCTAssertEqual(SampleLoopDisplayState(sample: forward).endFraction, 0.75)
        XCTAssertEqual(SampleLoopDisplayState(sample: pingPong).mode, .pingPong)
        XCTAssertEqual(SampleLoopDisplayState(sample: pingPong).startFraction, 0.1)
        XCTAssertEqual(SampleLoopDisplayState(sample: pingPong).endFraction, 0.3)
        XCTAssertEqual(SampleLoopDisplayState(sample: pingPong).endFrame, 30)
        for sample in invalid {
            XCTAssertEqual(SampleLoopDisplayState(sample: sample).status, .invalid)
            XCTAssertNil(SampleLoopDisplayState(sample: sample).startFraction)
            XCTAssertNil(SampleLoopDisplayState(sample: sample).endFraction)
        }
        XCTAssertEqual(invalid, invalidBefore)
    }

    func testWindowMatchesFixedMockupHierarchyAndKeepsFutureControlsInert() throws {
        let song = try loadReferenceSong("generated/instrument-sustained-defaults.xm")
        let controller = SampleEditorWindowController(displayState: .loadedModule(playbackSong: song, selection: .default))
        let window = try XCTUnwrap(controller.window)
        let view = try XCTUnwrap(window.contentView as? SampleEditorView)
        let descendants = view.sampleEditorDescendants
        let ids = Set(descendants.compactMap { $0.identifier?.rawValue })

        XCTAssertEqual(SampleEditorWindowController.contentSize, NSSize(width: 940, height: 560))
        XCTAssertEqual(window.contentMinSize, SampleEditorWindowController.contentSize)
        XCTAssertEqual(window.contentMaxSize, SampleEditorWindowController.contentSize)
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.utilityWindow))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        for id in SampleEditorViewIdentifier.majorRegions { XCTAssertTrue(ids.contains(id), id) }
        let values = Set(descendants.compactMap { ($0 as? NSTextField)?.stringValue })
        for copy in ["SMP", "NAME", "FORMAT", "AUDITION", "SAMPLES", "WAVEFORM", "LOOP", "SAMPLE PARAMS", "GENERATE", "FILE", "EDIT"] {
            XCTAssertTrue(values.contains(copy), copy)
        }
        let future = descendants.compactMap { $0 as? NSControl }.filter {
            $0.identifier?.rawValue.hasPrefix(SampleEditorViewIdentifier.futureControlPrefix) == true
        }
        XCTAssertFalse(future.isEmpty)
        XCTAssertTrue(future.allSatisfy { !$0.isEnabled && $0.target == nil && $0.action == nil })
        let nonNavigationControls = descendants.compactMap { $0 as? NSControl }.filter {
            !($0 is InstrumentEditorListRowControl) && !($0 is NSPopUpButton)
        }
        XCTAssertTrue(nonNavigationControls.allSatisfy { $0.target == nil && $0.action == nil })
        XCTAssertNil(try XCTUnwrap(view.waveformView).hitTest(.zero))

        let editable = SampleEditorWindowController(displayState: .editableDocument(.makeDefault()))
        let editableControls = try XCTUnwrap(editable.window?.contentView).sampleEditorDescendants
            .compactMap { $0 as? NSControl }.filter {
                !($0 is InstrumentEditorListRowControl) && !($0 is NSPopUpButton)
            }
        XCTAssertTrue(editableControls.allSatisfy { $0.target == nil && $0.action == nil })
    }

    func testPresenterReusesOpenControllerAndReopensWithoutTextFocusOrDuplicates() throws {
        let song = try loadReferenceSong("generated/instrument-sustained-defaults.xm")
        let state = SampleEditorDisplayState.loadedModule(playbackSong: song, selection: .default)
        let presenter = SampleEditorWindowPresenter()
        let first = presenter.show(displayState: state)
        let second = presenter.show(displayState: state)

        XCTAssertTrue(first === second)
        XCTAssertTrue(first.window?.firstResponder === first.window?.contentView)
        XCTAssertFalse(first.window?.firstResponder is NSTextView)
        first.window?.close()
        XCTAssertNil(presenter.windowController)
        let reopened = presenter.show(displayState: state)
        XCTAssertFalse(reopened === first)
        XCTAssertEqual((reopened.window?.contentView as? SampleEditorView)?.displayState.sampleDisplay, "S01")
        XCTAssertTrue(reopened.window?.firstResponder === reopened.window?.contentView)
        reopened.window?.close()
    }

    private func loadReferenceSong(_ relativePath: String) throws -> PlaybackSong {
        let url = try referenceXMFixtureURL(relativePath)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        return try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
    }

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("tests/reference-xm").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Missing fixture \(relativePath)") }
        return url
    }
}

private func makeSampleEditorSong(instruments: [Int: PlaybackInstrument]) -> PlaybackSong {
    PlaybackSong(
        title: "Sample Editor Test",
        orders: [],
        patternsByIndex: [:],
        instrumentsByIndex: instruments,
        restartOrderIndex: 0,
        endBehavior: .stopAtEnd
    )
}

private extension NSView {
    var sampleEditorDescendants: [NSView] { subviews + subviews.flatMap(\.sampleEditorDescendants) }
}
