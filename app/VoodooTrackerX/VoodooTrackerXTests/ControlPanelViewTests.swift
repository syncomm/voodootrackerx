import AppKit
import XCTest

@MainActor
final class ControlPanelViewTests: XCTestCase {
    func testPendingPlayCanBeStoppedWithoutClaimingActivePlayback() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.isPlaybackPreparing = true
        content.isSongPositionEnabled = true
        view.apply(content)
        XCTAssertFalse(content.isPlaybackActive)
        XCTAssertFalse(view.playButton.isEnabled)
        XCTAssertTrue(view.stopButton.isEnabled)
        XCTAssertTrue(view.songPositionStepper.isEnabled)
        content.isPlaybackPreparing = false
        view.apply(content)
        XCTAssertTrue(view.playButton.isEnabled)
        XCTAssertFalse(view.stopButton.isEnabled)
    }

    func testMainControlTooltipsAreSpecificAndNonPlaceholder() {
        let view = ControlPanelView(frame: .zero)
        let tooltips = [
            view.playButton.toolTip,
            view.stopButton.toolTip,
            view.loopButton.toolTip,
            view.editModeButton.toolTip,
            view.songTitleField.toolTip,
            view.songTimeField.toolTip,
            view.songLengthField.toolTip,
            view.songPositionField.toolTip,
            view.songPositionStepper.toolTip,
            view.restartPositionField.toolTip,
            view.patternSelector.toolTip,
            view.patternRowCountField.toolTip,
            view.instrumentSelector.toolTip,
            view.tempoField.toolTip,
            view.speedField.toolTip,
            view.octaveSelector.toolTip,
            view.channelCountField.toolTip
        ]

        XCTAssertTrue(tooltips.allSatisfy { tooltip in
            guard let tooltip, !tooltip.isEmpty else { return false }
            let lowercased = tooltip.lowercased()
            return !tooltip.localizedCaseInsensitiveContains("placeholder") &&
                !(lowercased.contains("playback ui") && lowercased.contains("placeholder"))
        })
    }

    func testApplyMapsLoopEditAndPlaybackControlState() {
        let view = ControlPanelView(frame: .zero)
        view.reloadInstruments(palette: [1: PlaybackInstrument(index: 1, samples: [])], selection: .default)
        var content = ControlPanelContent()
        content.isLoopEnabled = true
        content.isEditModeEnabled = true
        content.isPlaybackActive = true
        content.isSongPositionEnabled = true
        content.isPatternControlsEnabled = true
        content.areInstrumentPlaceholdersEnabled = true

        view.apply(content)

        XCTAssertEqual(view.loopButton.state, .on)
        XCTAssertEqual(view.editModeButton.state, .on)
        XCTAssertFalse(view.playButton.isEnabled)
        XCTAssertTrue(view.stopButton.isEnabled)
        XCTAssertTrue(view.songPositionStepper.isEnabled)
        XCTAssertTrue(view.patternSelector.isEnabled)
        XCTAssertTrue(view.instrumentSelector.isEnabled)
    }

    func testApplyMapsLoopStateWithoutChangingTransportAvailability() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.isLoopEnabled = true
        content.isPlaybackActive = false

        view.apply(content)

        XCTAssertEqual(view.loopButton.state, .on)
        XCTAssertTrue(view.playButton.isEnabled)
        XCTAssertFalse(view.stopButton.isEnabled)
    }

    func testApplyCanGrowSongPositionRangeAndSelectItsNewMaximum() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.isSongPositionEnabled = true

        for (position, maximum) in [(0, 0), (1, 1), (2, 2), (1, 2), (0, 2)] {
            content.songPosition = String(format: "%02d", position)
            content.songPositionValue = position
            content.maximumSongPosition = maximum
            view.apply(content)

            XCTAssertEqual(view.songPositionField.stringValue, String(format: "%02d", position))
            XCTAssertEqual(view.songPositionStepper.integerValue, position)
            XCTAssertEqual(view.songPositionStepper.maxValue, Double(maximum))
        }
    }

    func testControlPanelAddsAccentLineAndGroupSeparators() {
        let view = ControlPanelView(frame: .zero)

        assertColor(view.topAccentLine.layer?.backgroundColor, matches: TrackerControlPalette.panelTopAccent)
        XCTAssertEqual(view.groupSeparatorViews.count, 4)
        XCTAssertTrue(view.groupSeparatorViews.allSatisfy { $0.layer?.backgroundColor != nil })
    }

    func testReadoutAndInteractiveChromeUseDistinctControlPaletteTokens() {
        let view = ControlPanelView(frame: .zero)

        assertColor(view.songTitleField.layer?.backgroundColor, matches: TrackerControlPalette.readoutFieldBackground)
        assertColor(view.songTimeField.layer?.backgroundColor, matches: TrackerControlPalette.readoutFieldBackground)
        assertColor(view.songLengthField.layer?.borderColor, matches: TrackerControlPalette.readoutBorder)
        assertColor(view.channelCountField.layer?.borderColor, matches: TrackerControlPalette.readoutBorder)
        assertColor(view.songPositionField.layer?.backgroundColor, matches: TrackerControlPalette.interactiveFieldBackground)
        assertColor(view.songPositionField.layer?.borderColor, matches: TrackerControlPalette.interactiveBorder)
        assertColor(view.patternSelector.layer?.borderColor, matches: TrackerControlPalette.interactiveBorder)
        assertColor(view.instrumentSelector.layer?.borderColor, matches: TrackerControlPalette.interactiveBorder)
    }

    func testApplyMapsTitleAndTimeIntoSeparateReadouts() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.songTitle = "Fixture Title"
        content.songTime = "--:--"

        view.apply(content)

        XCTAssertEqual(view.songTitleField.stringValue, "Fixture Title")
        XCTAssertEqual(view.songTimeField.stringValue, "--:--")
        XCTAssertFalse(view.songTitleField.stringValue.contains("--:--"))
    }

    func testTitleAndTimeFieldsAreCenteredReadouts() {
        let view = ControlPanelView(frame: .zero)

        XCTAssertEqual(view.songTitleField.alignment, .center)
        XCTAssertEqual(view.songTitleField.cell?.alignment, .center)
        XCTAssertEqual(view.songTimeField.alignment, .center)
        XCTAssertEqual(view.songTimeField.cell?.alignment, .center)
    }

    func testApplyMapsTransportActiveStatePalette() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.isPlaybackActive = true
        content.isLoopEnabled = true
        content.isEditModeEnabled = true

        view.apply(content)

        assertColor(view.playButton.layer?.backgroundColor, matches: TrackerControlPalette.playActiveBackground)
        assertColor(view.stopButton.layer?.backgroundColor, matches: TrackerControlPalette.stopActiveBackground)
        assertColor(view.loopButton.layer?.backgroundColor, matches: TrackerControlPalette.toggleActiveBackground)
        assertColor(view.editModeButton.layer?.backgroundColor, matches: TrackerControlPalette.toggleActiveBackground)
    }

    func testApplyMapsSelectedInstrumentDisplayWithoutAudioState() {
        let view = ControlPanelView(frame: .zero)
        view.reloadInstruments(palette: [1: PlaybackInstrument(index: 1, samples: [])], selection: .default)
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = "I01"
        content.selectedSampleDisplay = "S01"
        content.selectedOctave = 4
        content.areInstrumentPlaceholdersEnabled = false

        view.apply(content)

        XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem, "I01")
        XCTAssertEqual(view.octaveSelector.titleOfSelectedItem, "4")
        XCTAssertFalse(view.instrumentSelector.isEnabled)
    }

    func testSlotDisplayFallsBackToCodeOnlyWhenNoNameExists() {
        let instrument = ControlPanelSlotDisplay.instrument(slot: 1)
        let sample = ControlPanelSlotDisplay.sample(slot: 1, name: "   ")

        XCTAssertEqual(instrument.displayTitle, "I01")
        XCTAssertEqual(instrument.tooltip, "I01")
        XCTAssertEqual(sample.displayTitle, "S01")
        XCTAssertEqual(sample.tooltip, "S01")
    }

    func testInstrumentNameUsesFullTitleWhileSampleNamesRetainTheirDisplayPolicy() {
        let instrument = ControlPanelSlotDisplay.instrument(slot: 1, name: "Very Long Instrument")
        let sample = ControlPanelSlotDisplay.sample(slot: 1, name: "Kick")

        XCTAssertEqual(instrument.displayTitle, "I01 Very Long Instrument")
        XCTAssertEqual(instrument.tooltip, "I01 Very Long Instrument")
        XCTAssertEqual(sample.displayTitle, "S01 Kick")
        XCTAssertEqual(sample.tooltip, "S01 Kick")
    }

    func testProjectedSampleSlotDisplayDistinguishesUnnamedSampleFromEmptyDestination() {
        let unnamed = ControlPanelSlotDisplay.sample(row: SampleSlotPresentationRow(
            sampleIndex: 0,
            state: .represented(makePlaybackSample(name: "   "))
        ))
        let empty = ControlPanelSlotDisplay.sample(row: SampleSlotPresentationRow(
            sampleIndex: 1,
            state: .emptyDestination
        ))

        XCTAssertEqual(unnamed.displayTitle, "S01 (unnamed ...")
        XCTAssertEqual(unnamed.tooltip, "S01 (unnamed sample)")
        XCTAssertEqual(empty.displayTitle, "S02 Empty des...")
        XCTAssertEqual(empty.tooltip, "S02 Empty destination")
        XCTAssertNotEqual(unnamed.displayTitle, empty.displayTitle)
    }

    func testApplyMapsInstrumentNameTooltip() {
        let view = ControlPanelView(frame: .zero)
        view.reloadInstruments(palette: [1: PlaybackInstrument(index: 1, samples: [])], selection: .default)
        let instrument = ControlPanelSlotDisplay.instrument(slot: 1, name: "BASIC SAMPLE")
        let sample = ControlPanelSlotDisplay.sample(slot: 1, name: "SINE64")
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = instrument.displayTitle
        content.selectedInstrumentTooltip = instrument.tooltip
        content.selectedSampleDisplay = sample.displayTitle
        content.selectedSampleTooltip = sample.tooltip
        content.areInstrumentPlaceholdersEnabled = true

        view.apply(content)

        XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem, "I01 BASIC SAMPLE")
        XCTAssertEqual(view.instrumentSelector.toolTip, "I01 BASIC SAMPLE")
    }

    func testApplyPreservesPatternPopupMenuAcrossDisplayRefresh() {
        let view = ControlPanelView(frame: .zero)
        view.patternSelector.removeAllItems()
        view.patternSelector.addItems(withTitles: ["000", "001", "002"])
        view.patternSelector.selectItem(withTitle: "002")
        var content = ControlPanelContent()
        content.isPatternControlsEnabled = true

        view.apply(content)

        XCTAssertEqual(view.patternSelector.numberOfItems, 3)
        XCTAssertEqual(view.patternSelector.titleOfSelectedItem, "002")
        XCTAssertTrue(view.patternSelector.isEnabled)
    }

    func testApplyPreservesOctavePopupMenuAcrossDisplayRefresh() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.selectedOctave = 7

        view.apply(content)

        XCTAssertEqual(view.octaveSelector.numberOfItems, 9)
        XCTAssertEqual(view.octaveSelector.titleOfSelectedItem, "7")
        XCTAssertEqual(view.octaveSelector.itemTitles, (0...8).map(String.init))
    }

    func testApplyPreservesInstrumentPopupMenuWhenSelectingExistingItems() {
        let view = ControlPanelView(frame: .zero)
        let actionRecorder = ControlPanelPopupActionRecorder()
        view.instrumentSelector.target = actionRecorder
        view.instrumentSelector.action = #selector(ControlPanelPopupActionRecorder.recordAction(_:))
        view.instrumentSelector.removeAllItems()
        view.instrumentSelector.addItem(withTitle: "I01 Piano")
        view.instrumentSelector.lastItem?.representedObject = 1
        view.instrumentSelector.addItem(withTitle: "I02 Lead")
        view.instrumentSelector.lastItem?.representedObject = 2
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = "I02 Lead"
        content.selectedInstrumentTooltip = "I02 Lead"
        content.selectedSampleDisplay = "S03 Snare"
        content.selectedSampleTooltip = "S03 Snare"
        content.areInstrumentPlaceholdersEnabled = true

        view.apply(content)

        XCTAssertEqual(view.instrumentSelector.numberOfItems, 2)
        XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem, "I02 Lead")
        XCTAssertEqual(view.instrumentSelector.selectedItem?.representedObject as? Int, 2)
        XCTAssertEqual(actionRecorder.actionCount, 0)
        XCTAssertTrue(view.instrumentSelector.isEnabled)
    }

    func testPopupCentersHitNativePopupControls() {
        let view = ControlPanelView(frame: NSRect(x: 0, y: 0, width: 1120, height: 84))
        view.instrumentSelector.removeAllItems()
        view.instrumentSelector.addItem(withTitle: "I01 Piano")
        view.instrumentSelector.lastItem?.representedObject = 1
        view.instrumentSelector.addItem(withTitle: "I02 Lead")
        view.instrumentSelector.lastItem?.representedObject = 2
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = "I02 Lead"
        content.selectedInstrumentTooltip = "I02 Lead"
        content.selectedSampleDisplay = "S02 Snare"
        content.selectedSampleTooltip = "S02 Snare"
        content.isPatternControlsEnabled = true
        content.areInstrumentPlaceholdersEnabled = true

        view.apply(content)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.popupCenterHitsControl(view.patternSelector))
        XCTAssertTrue(view.popupCenterHitsControl(view.instrumentSelector))
        XCTAssertTrue(view.popupCenterHitsControl(view.octaveSelector))
    }

    func testApplyUpdatesPopupItemWithSameSlotWithoutCollapsingMenu() {
        let view = ControlPanelView(frame: .zero)
        view.instrumentSelector.removeAllItems()
        view.instrumentSelector.addItem(withTitle: "I01 Piano")
        view.instrumentSelector.lastItem?.representedObject = 1
        view.instrumentSelector.addItem(withTitle: "I02 Old")
        view.instrumentSelector.lastItem?.representedObject = 2
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = "I02 New"
        content.selectedInstrumentTooltip = "I02 New"
        content.areInstrumentPlaceholdersEnabled = true

        view.apply(content)

        XCTAssertEqual(view.instrumentSelector.numberOfItems, 2)
        XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem, "I02 New")
        XCTAssertEqual(view.instrumentSelector.selectedItem?.representedObject as? Int, 2)
    }

    func testEmptyPaletteKeepsNoInstrumentWithoutInventingSelectableZero() {
        let view = ControlPanelView(frame: .zero)
        view.reloadInstruments(palette: [:], selection: .default)
        var content = ControlPanelContent()
        content.areInstrumentPlaceholdersEnabled = true
        view.apply(content)
        XCTAssertEqual(view.instrumentSelector.itemTitles, ["No Inst"])
        XCTAssertNil(view.instrumentSelector.selectedItem?.representedObject)
        XCTAssertFalse(view.instrumentSelector.isEnabled)
    }

    func testLoadedInstrumentPalettesExposeEveryRepresentedIdentityThrough255() {
        for count in [0, 1, 32, 33, 56, 255] {
            let ids = count == 0 ? [] : Array(1...count)
            let palette = Dictionary(uniqueKeysWithValues: ids.map {
                ($0, PlaybackInstrument(index: $0, name: "Instrument \($0)", samples: []))
            })
            let song = makePlaybackSong(orderPatternIndices: [0], patternRowCounts: [0: 64], instrumentsByIndex: palette)
            let selection = TrackerEditorSelection(selectedInstrument: max(1, count))
            let editor = InstrumentEditorDisplayState.loadedModule(playbackSong: song, selection: selection)
            let view = ControlPanelView(frame: .zero)
            view.reloadInstruments(palette: song.instrumentsByIndex, selection: selection)
            XCTAssertEqual(view.instrumentSelector.itemArray.compactMap { $0.representedObject as? Int }, ids)
            XCTAssertEqual(editor.instrumentSlots.map(\.slot), ids)
            XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem,
                           count == 0 ? "No Inst" : String(format: "I%02X Instrument %d", count, count))
            XCTAssertFalse(view.instrumentSelector.itemTitles.contains("I00"))
        }
    }

    func testEditableDenseAndSparsePalettesDoNotInventMissingOrZeroIdentities() {
        for ids in [Array(1...33), Array(1...56), [1, 0x21, 0x38]] {
            let palette = Dictionary(uniqueKeysWithValues: ids.map { ($0, PlaybackInstrument(index: $0, samples: [])) })
            let document = instrumentDocument(palette)
            let view = ControlPanelView(frame: .zero)
            view.reloadInstruments(palette: document.instrumentPalette, selection: document.selection)
            XCTAssertEqual(view.instrumentSelector.itemArray.compactMap { $0.representedObject as? Int }, ids)
        }
        let view = ControlPanelView(frame: .zero)
        view.reloadInstruments(palette: [0: PlaybackInstrument(index: 0, samples: [])], selection: .default)
        XCTAssertEqual(view.instrumentSelector.itemTitles, ["No Inst"])
    }

    func testHighInstrumentSelectionSynchronizesBothSurfacesAndKeepsSampleFocusIndependent() throws {
        let palette = Dictionary(uniqueKeysWithValues: [1, 0x21, 0x38].map { id in
            (id, PlaybackInstrument(index: id, name: "Long instrument name", samples: [
                makePlaybackSample(instrumentIndex: id, sampleIndex: 0, pcm: [0.25]),
                makePlaybackSample(instrumentIndex: id, sampleIndex: 2, pcm: [-0.5])
            ], noteSampleMap: Array(repeating: 2, count: 96)))
        })
        for loaded in [true, false] {
            var document = instrumentDocument(palette)
            let before = document
            let song = makePlaybackSong(orderPatternIndices: [0], patternRowCounts: [0: 64], instrumentsByIndex: palette)
            let songBefore = song
            var selection = document.selection
            var revision = 0
            let edits = EditableDocumentEditCoordinator(
                contextProvider: { loaded ? .loadedReadOnly : .editable(document: document, isPlaybackActive: false) },
                documentApplyHandler: { document = $0; revision += 1 }
            )
            let view = ControlPanelView(frame: .zero)
            var editor: InstrumentEditorWindowController!
            let state = { loaded ? InstrumentEditorDisplayState.loadedModule(playbackSong: song, selection: selection)
                : InstrumentEditorDisplayState.editableDocument(document) }
            let refresh = {
                view.reloadInstruments(palette: loaded ? song.instrumentsByIndex : document.instrumentPalette, selection: selection)
                var content = ControlPanelContent()
                let display = ControlPanelSlotDisplay.instrument(slot: selection.selectedInstrument, name: palette[selection.selectedInstrument]?.name)
                content.selectedInstrumentDisplay = display.displayTitle
                content.selectedInstrumentTooltip = display.tooltip
                content.areInstrumentPlaceholdersEnabled = true
                view.apply(content)
                editor?.apply(displayState: state())
            }
            let select: (Int) -> Bool = { id in
                if loaded { selection = selection.withSelectedInstrument(id, availableSampleSlots: [1, 2, 3]) }
                else { document.selectInstrument(id); selection = document.selection }
                refresh()
                return true
            }
            editor = InstrumentEditorWindowController(displayState: state(), instrumentSelectionHandler: select)
            let recorder = ControlPanelPopupActionRecorder()
            recorder.onSelect = { _ = select($0) }
            view.instrumentSelector.target = recorder
            view.instrumentSelector.action = #selector(ControlPanelPopupActionRecorder.recordAction(_:))
            refresh()
            for id in [0x21, 0x38] {
                if id == 0x21 {
                    view.instrumentSelector.selectItem(at: 1)
                    XCTAssertTrue(view.instrumentSelector.sendAction(view.instrumentSelector.action, to: recorder))
                } else {
                    let editorView = try XCTUnwrap(editor.window?.contentView as? InstrumentEditorView)
                    let row = try XCTUnwrap(editorView.subviewsRecursively.first {
                        $0.identifier?.rawValue == InstrumentEditorViewIdentifier.instrumentRowPrefix + "I38"
                    } as? InstrumentEditorListRowControl)
                    XCTAssertTrue(row.accessibilityPerformPress())
                }
                XCTAssertEqual(view.instrumentSelector.selectedItem?.representedObject as? Int, id)
                XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem, String(format: "I%02X Long instrument name", id))
                XCTAssertEqual(view.instrumentSelector.toolTip, view.instrumentSelector.titleOfSelectedItem)
                let editorView = try XCTUnwrap(editor.window?.contentView as? InstrumentEditorView)
                XCTAssertEqual(editorView.displayState.selectedInstrumentSlot, id)
                let request = EditorNoteAuditionRequest(kind: .noteOn(noteValue: 49, selectedOctave: 4),
                    selection: selection, sampleResolution: .instrumentKeymap,
                    sourceContext: loaded ? .loadedModule(patternIndex: 0) : .blankDocument)
                let routed = loaded ? EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song)
                    : document.noteAuditionAvailability(for: request)
                let directRequest = EditorNoteAuditionRequest(
                    kind: request.kind, selection: selection, sampleResolution: .directSelectedSample,
                    sourceContext: request.sourceContext)
                let direct = loaded ? EditorNoteAuditionAvailabilityResolver.availability(for: directRequest, loadedPlaybackSong: song)
                    : document.noteAuditionAvailability(for: directRequest)
                guard case let .potentiallyAvailable(mapped) = routed, case let .potentiallyAvailable(focused) = direct else {
                    return XCTFail("Represented mapped and focused samples must remain available")
                }
                XCTAssertEqual(mapped.sampleIndex, 2)
                XCTAssertEqual(focused.sampleIndex, 0)
                XCTAssertEqual(selection.selectedSample, 1)
                if !loaded {
                    var entry = document
                    XCTAssertTrue(entry.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
                    XCTAssertEqual(entry.pattern.rows[0][0].instrument, UInt8(id))
                }
            }
            XCTAssertEqual(document.instrumentPalette, before.instrumentPalette)
            XCTAssertEqual(document.patterns, before.patterns)
            XCTAssertEqual(song, songBefore)
            XCTAssertEqual(revision, 0)
            XCTAssertFalse(edits.undoManager.canUndo)
        }
    }

    func testLowerRowOrderReadoutsAccessibilityAndFlexibleInstrumentWidth() throws {
        for width: CGFloat in [912, 1072, 1352] {
            let view = ControlPanelView(frame: NSRect(x: 0, y: 0, width: width, height: 84))
            view.layoutSubtreeIfNeeded()
            let fields = view.controlDescendants.compactMap { $0 as? NSTextField }
            let labels = fields.filter { ["PTN", "ROWS", "CHN", "INST", "BPM", "SPD", "OCT"].contains($0.stringValue) }
                .sorted { view.convert($0.bounds, from: $0).minX < view.convert($1.bounds, from: $1).minX }
            XCTAssertEqual(labels.map(\.stringValue), ["PTN", "ROWS", "CHN", "INST", "BPM", "SPD", "OCT"])
            XCTAssertFalse(fields.contains { ["SMP", "TEMPO", "SPEED"].contains($0.stringValue) })
            XCTAssertEqual(view.controlDescendants.compactMap { $0 as? NSPopUpButton }.count, 3)
            XCTAssertGreaterThan(view.instrumentSelector.frame.width, 250)
            // Native popup frames include alignment insets outside the constrained width.
            XCTAssertEqual(view.patternSelector.alignmentRect(forFrame: view.patternSelector.frame).width, 60)
            XCTAssertEqual(view.tempoField.stringValue, "125")
            XCTAssertEqual(view.speedField.stringValue, "06")
            XCTAssertEqual(view.channelCountField.stringValue, "8")
            XCTAssertFalse(view.tempoField.isEditable)
            XCTAssertFalse(view.speedField.isEditable)
            XCTAssertEqual(view.speedField.accessibilityLabel(), "Speed (ticks per row)")
            XCTAssertTrue(view.patternSelector.nextKeyView === view.instrumentSelector)
            XCTAssertTrue(view.instrumentSelector.nextKeyView === view.octaveSelector)
        }
    }

    private func instrumentDocument(_ palette: [Int: PlaybackInstrument]) -> BlankTrackerDocument {
        let blank = BlankTrackerDocument.makeDefault()
        return BlankTrackerDocument(title: blank.title, songLength: blank.songLength, currentPosition: 0,
            restartPosition: 0, currentPatternIndex: 0, tempo: 125, speed: 6, orderTable: [0],
            selection: .default, instrumentPalette: palette, patterns: blank.patterns)
    }

    private func assertColor(
        _ actual: CGColor?,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual,
              let actualColor = NSColor(cgColor: actual)?.usingColorSpace(.sRGB),
              let expectedColor = expected.usingColorSpace(.sRGB) else {
            XCTFail("Missing color", file: file, line: line)
            return
        }

        XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualColor.alphaComponent, expectedColor.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}

@MainActor
private final class ControlPanelPopupActionRecorder: NSObject {
    private(set) var actionCount = 0
    var onSelect: ((Int) -> Void)?

    @objc func recordAction(_ sender: NSPopUpButton) {
        actionCount += 1
        if let id = sender.selectedItem?.representedObject as? Int { onSelect?(id) }
    }
}

private extension ControlPanelView {
    var controlDescendants: [NSView] { subviews.flatMap { [$0] + $0.subviewsRecursively } }
    func popupCenterHitsControl(_ popup: NSPopUpButton) -> Bool {
        let center = NSPoint(x: popup.bounds.midX, y: popup.bounds.midY)
        let point = convert(center, from: popup)
        guard let hitView = hitTest(point) else {
            return false
        }
        return hitView === popup || hitView.isDescendant(of: popup)
    }
}

private extension NSView {
    var subviewsRecursively: [NSView] { subviews.flatMap { [$0] + $0.subviewsRecursively } }
}

@MainActor
final class SongDurationTests: XCTestCase {
    func testFiniteControlFlowDurationMatchesManualSecondsAndTimingOnlyOracle() throws {
        let song = durationSong([0: [
            [durationCell(15, 3), durationCell(15, 150)],
            [durationCell(14, 0x60), durationCell()],
            [durationCell(14, 0x62), durationCell(14, 0xE1)],
            [durationCell(11, 2), durationCell(13, 1)],
        ], 1: [[durationCell(15, 1)]], 2: [
            [durationCell(15, 1)], [durationCell(15, 2), durationCell(15, 125)],
            [durationCell()],
        ]], orders: [0, 1, 2])
        let seconds = try XCTUnwrap(PlaybackSongDuration.seconds(for: song))
        // EE1 commits E6 to anchor1, then advances before fresh cells: repeats
        // enter row2 directly. B02+D01 subsequently skips order1 and row0.
        let rowSeconds: [TimeInterval] = [0.05, 0.05, 0.10, 0.10, 0.10, 0.05, 0.04, 0.04]
        XCTAssertEqual(seconds, rowSeconds.reduce(0, +), accuracy: 1 / 48_000.0)
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 3)
        XCTAssertEqual(traversal.rows.map(\.rowArrayIndex), [0, 1, 2, 2, 2, 3, 1, 2])
        for rate in [44_100.0, 48_000] {
            let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate)
            XCTAssertEqual(timing.rowTimings.map(\.patternDelayCycles), [0, 0, 1, 1, 1, 0, 0, 0])
            for (row, expected) in zip(timing.rowTimings, rowSeconds) {
                XCTAssertEqual((row.rowEndExactFrame - row.rowStartExactFrame) / rate,
                    expected, accuracy: 0.000_000_001)
            }
            let end = try XCTUnwrap(timing.rowTimings.last).rowEndFrame
            XCTAssertEqual(seconds, Double(end) / rate, accuracy: 1 / min(rate, 48_000))
        }
    }

    func testOddRowsEmptyInputsAndOutgoingFiniteEndsKeepExecutedCommandRow() throws {
        let odd = durationSong([0: Array(repeating: [durationCell()], count: 3)])
        XCTAssertEqual(try XCTUnwrap(PlaybackSongDuration.seconds(for: odd)), 0.36, accuracy: 1 / 48_000.0)
        XCTAssertNil(PlaybackSongDuration.seconds(for: durationSong([:], orders: [])))
        XCTAssertNil(PlaybackSongDuration.seconds(for: durationSong([0: []])))
        let emptyOrders = durationSong([0: [], 1: [[durationCell()]], 2: []], orders: [0, 1, 2, 1])
        XCTAssertEqual(try XCTUnwrap(PlaybackSongDuration.seconds(for: emptyOrders)), 0.24,
            accuracy: 1 / 48_000.0)
        for command in [durationCell(11, 7), durationCell(13, 0)] {
            let song = durationSong([0: [[command], [durationCell(15, 1)]]])
            XCTAssertEqual(try XCTUnwrap(PlaybackSongDuration.seconds(for: song)), 0.12, accuracy: 1 / 48_000.0)
        }
    }

    func testMissingCyclicAndCancelledDurationNeverPublishesExactPrefix() {
        XCTAssertNil(PlaybackSongDuration.seconds(for: durationSong([0: [[durationCell()]]], orders: [0, 1])))
        XCTAssertNil(PlaybackSongDuration.seconds(for: durationSong([0: [[durationCell(11, 1)]], 1: []], orders: [0, 1])))
        XCTAssertNil(PlaybackSongDuration.seconds(for: durationSong([0: [[durationCell(11, 0)]]])))
        let song = durationSong([0: Array(repeating: [durationCell()], count: 100)])
        var polls = 0
        XCTAssertNil(PlaybackSongDuration.seconds(for: song, isCancelled: { polls += 1; return polls >= 3 }))
        XCTAssertGreaterThanOrEqual(polls, 3)
    }

    func testLoadPublishesDurationBeforePlayWithoutEngineOrSamplePayload() async throws {
        let model = SongDurationDisplayModel { song, cancelled in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertTrue(song.instrumentsByIndex.isEmpty)
            return PlaybackSongDuration.seconds(for: song, isCancelled: cancelled)
        }
        let sample = makePlaybackSample(pcm: [0.25, -0.25], loopStart: 0, loopLength: 2, loopType: 1)
        let song = makePlaybackSong(orderPatternIndices: [0], patternRowCounts: [0: 125],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample])])
        model.load(song: song, identity: UUID())
        XCTAssertTrue(model.isPending)
        XCTAssertNil(model.durationSeconds)
        await waitForDuration(model)
        XCTAssertEqual(try XCTUnwrap(model.durationSeconds), 15, accuracy: 1 / 48_000.0)
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.songTime = ControlPanelDisplayState.songTimeDisplay(durationSeconds: model.durationSeconds)
        content.songTimeTooltip = model.tooltip
        view.apply(content)
        XCTAssertEqual(view.songTimeField.stringValue, "00:15")
        XCTAssertEqual(view.songTimeField.toolTip, model.tooltip)
        XCTAssertFalse(content.isPlaybackActive)
        XCTAssertTrue(model.tooltip.contains("excluding the playback tail"))
        model.load(song: makePlaybackSong(orderPatternIndices: [0], patternRowCounts: [0: 125],
            endBehavior: .restartFromBeginning), identity: UUID())
        await waitForDuration(model)
        XCTAssertNil(model.durationSeconds)
        content.songTime = ControlPanelDisplayState.songTimeDisplay(durationSeconds: model.durationSeconds)
        content.songTimeTooltip = model.tooltip
        view.apply(content)
        XCTAssertEqual(view.songTimeField.stringValue, "--:--")
        XCTAssertEqual(view.songTimeField.toolTip, model.tooltip)
        XCTAssertTrue(model.tooltip.contains("unavailable"))
    }

    func testEditableTimingEditUndoAndRedoRefreshDurationThroughCanonicalCoordinator() async throws {
        let model = SongDurationDisplayModel(), identity = UUID()
        var current = BlankTrackerDocument.makeDefault()
        let coordinator = EditableDocumentEditCoordinator(undoManager: UndoManager(),
            contextProvider: { .editable(document: current, isPlaybackActive: false) },
            documentApplyHandler: { document in
                current = document
                model.update(document: document, identity: identity)
            })
        model.update(document: current, identity: identity)
        await waitForDuration(model)
        XCTAssertEqual(try XCTUnwrap(model.durationSeconds), 7.68, accuracy: 1 / 48_000.0)
        var edited = current
        edited.patterns[0].rows[0][0] = .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 15, effectParam: 3)
        XCTAssertTrue(coordinator.applyEdit(label: "Change Timing", updatedDocument: edited))
        XCTAssertNil(model.durationSeconds)
        await waitForDuration(model)
        XCTAssertEqual(try XCTUnwrap(model.durationSeconds), 3.84, accuracy: 1 / 48_000.0)
        let generation = model.generation
        XCTAssertFalse(coordinator.applyEdit(label: "No Change", updatedDocument: current))
        XCTAssertEqual(model.generation, generation)
        XCTAssertTrue(coordinator.undo())
        await waitForDuration(model)
        XCTAssertEqual(try XCTUnwrap(model.durationSeconds), 7.68, accuracy: 1 / 48_000.0)
        XCTAssertTrue(coordinator.redo())
        await waitForDuration(model)
        XCTAssertEqual(try XCTUnwrap(model.durationSeconds), 3.84, accuracy: 1 / 48_000.0)
        XCTAssertEqual(coordinator.undoMenuItemTitle, "Undo Change Timing")
        let malformed = BlankTrackerDocument(title: current.title, songLength: current.songLength + 1,
            currentPosition: current.currentPosition, restartPosition: current.restartPosition,
            currentPatternIndex: current.currentPatternIndex, tempo: current.tempo, speed: current.speed,
            orderTable: current.orderTable, selection: current.selection,
            instrumentPalette: current.instrumentPalette, patterns: current.patterns)
        model.update(document: malformed, identity: identity)
        await waitForDuration(model)
        XCTAssertNil(model.durationSeconds, "A short order table cannot supply an exact prefix duration")
    }

    func testNavigationFocusTitleSampleAndRestartChangesPreserveDurationGeneration() async throws {
        let model = SongDurationDisplayModel(), identity = UUID()
        let blank = BlankTrackerDocument.makeDefault()
        let sample = makePlaybackSample(pcm: [0.25])
        let palette = [1: PlaybackInstrument(index: 1, samples: [sample]),
            2: PlaybackInstrument(index: 2, samples: [sample, sample, sample])]
        let base = BlankTrackerDocument(title: blank.title, songLength: 2,
            currentPosition: 0, restartPosition: 0, currentPatternIndex: 0,
            tempo: blank.tempo, speed: blank.speed, orderTable: [0, 1], selection: .default,
            instrumentPalette: palette,
            patterns: blank.patterns + [.init(index: 1, rowCount: 3, channels: 1,
                rows: Array(repeating: [.empty], count: 3))])
        model.update(document: base, identity: identity)
        await waitForDuration(model)
        let generation = model.generation, seconds = model.durationSeconds
        let changed = BlankTrackerDocument(title: "Different title", songLength: base.songLength,
            currentPosition: 1, restartPosition: 1, currentPatternIndex: 1,
            tempo: base.tempo, speed: base.speed, orderTable: base.orderTable,
            selection: .init(selectedInstrument: 2, selectedSample: 3),
            instrumentPalette: [2: .init(index: 2, samples: [makePlaybackSample(pcm: [0.5])])],
            patterns: base.patterns)
        var notifications = 0
        model.didChange = { notifications += 1 }
        defer { model.didChange = nil }
        model.update(document: changed, identity: identity)
        model.update(document: changed, identity: identity)
        XCTAssertEqual(model.generation, generation)
        XCTAssertEqual(model.durationSeconds, seconds)
        XCTAssertFalse(model.isPending)
        XCTAssertEqual(notifications, 0)
        model.update(document: changed, identity: UUID())
        XCTAssertEqual(model.generation, generation + 1)
        XCTAssertNil(model.durationSeconds)
        await waitForDuration(model)
        XCTAssertEqual(model.durationSeconds, seconds)
    }

    func testReplacementIdentityRejectsBlockedStaleResultAndFileNewClearsDuration() async {
        let started = expectation(description: "old duration worker entered")
        let ready = expectation(description: "replacement duration published")
        let first = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        first.signal()
        let model = SongDurationDisplayModel { _, cancelled in
            XCTAssertFalse(Thread.isMainThread)
            if first.wait(timeout: .now()) == .success {
                started.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { return nil }
                XCTAssertTrue(cancelled())
                return 99 // Deliberately ignores cancellation; publication must reject it.
            }
            return 4
        }
        defer { release.signal(); model.didChange = nil }
        var published = [TimeInterval]()
        model.didChange = { [weak model] in
            if let seconds = model?.durationSeconds {
                published.append(seconds)
                if seconds == 4 { ready.fulfill() }
            }
        }
        let song = durationSong([0: [[durationCell()]]])
        model.load(song: song, identity: UUID())
        await fulfillment(of: [started], timeout: 2)
        let generation = model.generation
        model.load(song: song, identity: UUID())
        XCTAssertEqual(model.generation, generation + 1)
        XCTAssertNil(model.durationSeconds)
        XCTAssertTrue(model.isPending)
        release.signal()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(published, [4])
        model.load(song: nil, identity: nil)
        XCTAssertNil(model.durationSeconds)
        XCTAssertFalse(model.isPending)
        XCTAssertTrue(model.tooltip.contains("unavailable"))
    }

    private func waitForDuration(_ model: SongDurationDisplayModel) async {
        guard model.isPending else { return }
        let ready = expectation(description: "duration calculation completed")
        model.didChange = { [weak model] in
            if model?.isPending == false { ready.fulfill() }
        }
        await fulfillment(of: [ready], timeout: 5)
        model.didChange = nil
        XCTAssertFalse(model.isPending)
    }

    private func durationCell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func durationSong(_ patterns: [Int: [[PlaybackCell]]], orders: [Int] = [0]) -> PlaybackSong {
        makePlaybackSong(orderPatternIndices: orders,
            patternRowsByIndex: patterns.mapValues { rows in
                rows.enumerated().map { PlaybackRow(index: $0.offset, cells: $0.element) }
            })
    }
}
