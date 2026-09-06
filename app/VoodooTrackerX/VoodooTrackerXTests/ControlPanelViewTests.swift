import AppKit
import XCTest

@MainActor
final class ControlPanelViewTests: XCTestCase {
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
            view.sampleSelector.toolTip,
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
        XCTAssertTrue(view.sampleSelector.isEnabled)
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
        XCTAssertEqual(view.groupSeparatorViews.count, 5)
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

    func testApplyMapsSelectedInstrumentAndSampleDisplayWithoutAudioState() {
        let view = ControlPanelView(frame: .zero)
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = "I01"
        content.selectedSampleDisplay = "S01"
        content.selectedOctave = 4
        content.areInstrumentPlaceholdersEnabled = false

        view.apply(content)

        XCTAssertEqual(view.instrumentSelector.titleOfSelectedItem, "I01")
        XCTAssertEqual(view.sampleSelector.titleOfSelectedItem, "S01")
        XCTAssertEqual(view.octaveSelector.titleOfSelectedItem, "4")
        XCTAssertFalse(view.instrumentSelector.isEnabled)
        XCTAssertFalse(view.sampleSelector.isEnabled)
    }

    func testSlotDisplayFallsBackToCodeOnlyWhenNoNameExists() {
        let instrument = ControlPanelSlotDisplay.instrument(slot: 1)
        let sample = ControlPanelSlotDisplay.sample(slot: 1, name: "   ")

        XCTAssertEqual(instrument.displayTitle, "I01")
        XCTAssertEqual(instrument.tooltip, "I01")
        XCTAssertEqual(sample.displayTitle, "S01")
        XCTAssertEqual(sample.tooltip, "S01")
    }

    func testSlotDisplayIncludesTruncatedNameAndFullTooltipWhenNameExists() {
        let instrument = ControlPanelSlotDisplay.instrument(slot: 1, name: "Very Long Instrument")
        let sample = ControlPanelSlotDisplay.sample(slot: 1, name: "Kick")

        XCTAssertEqual(instrument.displayTitle, "I01 Very Long...")
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

    func testApplyMapsInstrumentAndSampleNameTooltips() {
        let view = ControlPanelView(frame: .zero)
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
        XCTAssertEqual(view.sampleSelector.titleOfSelectedItem, "S01 SINE64")
        XCTAssertEqual(view.sampleSelector.toolTip, "S01 SINE64")
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

    func testApplyPreservesInstrumentAndSamplePopupMenusWhenSelectingExistingItems() {
        let view = ControlPanelView(frame: .zero)
        let actionRecorder = ControlPanelPopupActionRecorder()
        view.instrumentSelector.removeAllItems()
        view.instrumentSelector.addItem(withTitle: "I01 Piano")
        view.instrumentSelector.lastItem?.representedObject = 1
        view.instrumentSelector.addItem(withTitle: "I02 Lead")
        view.instrumentSelector.lastItem?.representedObject = 2
        view.sampleSelector.removeAllItems()
        view.sampleSelector.addItem(withTitle: "S01 Kick")
        view.sampleSelector.lastItem?.representedObject = 1
        view.sampleSelector.addItem(withTitle: "S03 Snare")
        view.sampleSelector.lastItem?.representedObject = 3
        view.sampleSelector.target = actionRecorder
        view.sampleSelector.action = #selector(ControlPanelPopupActionRecorder.recordAction(_:))
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
        XCTAssertEqual(view.sampleSelector.numberOfItems, 2)
        XCTAssertEqual(view.sampleSelector.titleOfSelectedItem, "S03 Snare")
        XCTAssertEqual(view.sampleSelector.selectedItem?.representedObject as? Int, 3)
        XCTAssertEqual(actionRecorder.actionCount, 0)
        XCTAssertTrue(view.instrumentSelector.isEnabled)
        XCTAssertTrue(view.sampleSelector.isEnabled)
    }

    func testPopupCentersHitNativePopupControls() {
        let view = ControlPanelView(frame: NSRect(x: 0, y: 0, width: 1120, height: 84))
        view.instrumentSelector.removeAllItems()
        view.instrumentSelector.addItem(withTitle: "I01 Piano")
        view.instrumentSelector.lastItem?.representedObject = 1
        view.instrumentSelector.addItem(withTitle: "I02 Lead")
        view.instrumentSelector.lastItem?.representedObject = 2
        view.sampleSelector.removeAllItems()
        view.sampleSelector.addItem(withTitle: "S01 Kick")
        view.sampleSelector.lastItem?.representedObject = 1
        view.sampleSelector.addItem(withTitle: "S02 Snare")
        view.sampleSelector.lastItem?.representedObject = 2
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
        XCTAssertTrue(view.popupCenterHitsControl(view.sampleSelector))
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

    func testApplySelectsExistingSampleSlotControlItem() {
        let view = ControlPanelView(frame: .zero)
        view.sampleSelector.removeAllItems()
        view.sampleSelector.addItems(withTitles: ["S01", "S02", "S03"])
        var content = ControlPanelContent()
        content.selectedInstrumentDisplay = "I01"
        content.selectedSampleDisplay = "S03"
        content.areInstrumentPlaceholdersEnabled = true

        view.apply(content)

        XCTAssertEqual(view.sampleSelector.numberOfItems, 3)
        XCTAssertEqual(view.sampleSelector.titleOfSelectedItem, "S03")
        XCTAssertTrue(view.sampleSelector.isEnabled)
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

    @objc func recordAction(_ sender: NSPopUpButton) {
        actionCount += 1
    }
}

private extension ControlPanelView {
    func popupCenterHitsControl(_ popup: NSPopUpButton) -> Bool {
        let center = NSPoint(x: popup.bounds.midX, y: popup.bounds.midY)
        let point = convert(center, from: popup)
        guard let hitView = hitTest(point) else {
            return false
        }
        return hitView === popup || hitView.isDescendant(of: popup)
    }
}
