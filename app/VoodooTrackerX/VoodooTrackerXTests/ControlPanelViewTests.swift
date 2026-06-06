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
}
