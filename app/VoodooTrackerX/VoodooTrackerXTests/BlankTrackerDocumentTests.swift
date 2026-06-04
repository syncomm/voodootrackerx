import XCTest

final class BlankTrackerDocumentTests: XCTestCase {
    func testDefaultBlankDocumentUsesTrackerStartupDefaults() {
        let document = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(document.title, "Untitled")
        XCTAssertEqual(document.songLength, 1)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.restartPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.pattern.index, 0)
        XCTAssertEqual(document.pattern.rowCount, 64)
        XCTAssertEqual(document.pattern.channels, 8)
        XCTAssertEqual(document.tempo, 125)
        XCTAssertEqual(document.speed, 6)
    }

    func testDefaultBlankDocumentExposesOneEmptyPattern() {
        let metadata = BlankTrackerDocument.makeDefault().metadata

        XCTAssertEqual(metadata.title, "Untitled")
        XCTAssertEqual(metadata.songLength, 1)
        XCTAssertEqual(metadata.orderTable, [0])
        XCTAssertEqual(metadata.xmPatterns.count, 1)
        XCTAssertEqual(metadata.xmPatterns[0].rowCount, 64)
        XCTAssertEqual(metadata.xmPatterns[0].channels, 8)
        XCTAssertEqual(metadata.xmPatterns[0].rows.count, 64)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0].count, 8)
        XCTAssertTrue(metadata.xmPatterns[0].rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testBlankDocumentControlPanelMetadataIsSane() {
        let metadata = BlankTrackerDocument.makeDefault().controlPanelMetadata

        XCTAssertEqual(metadata.songTitle, "Untitled")
        XCTAssertEqual(metadata.songLength, "01")
        XCTAssertEqual(metadata.songPosition, "00")
        XCTAssertEqual(metadata.restartPosition, "00")
        XCTAssertEqual(metadata.patternRowCount, "64")
        XCTAssertEqual(metadata.channelCount, "8")
        XCTAssertEqual(metadata.tempo, "125")
        XCTAssertEqual(metadata.speed, "06")
        XCTAssertEqual(metadata.songPositionValue, 0)
        XCTAssertEqual(metadata.maximumSongPosition, 0)
        XCTAssertFalse(metadata.isSongPositionEnabled)
        XCTAssertTrue(metadata.isPatternControlsEnabled)
        XCTAssertFalse(metadata.areInstrumentPlaceholdersEnabled)
    }

    func testBlankDocumentControlPanelDisplayStateUsesStartupDefaults() {
        let content = ControlPanelDisplayState.blankDocumentContent(
            for: BlankTrackerDocument.makeDefault(),
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(content.songTitle, "Untitled")
        XCTAssertEqual(content.songLength, "01")
        XCTAssertEqual(content.songPosition, "00")
        XCTAssertEqual(content.restartPosition, "00")
        XCTAssertEqual(content.patternRowCount, "64")
        XCTAssertEqual(content.channelCount, "8")
        XCTAssertEqual(content.tempo, "125")
        XCTAssertEqual(content.speed, "06")
        XCTAssertEqual(content.selectedOctave, 4)
        XCTAssertEqual(content.songPositionValue, 0)
        XCTAssertEqual(content.maximumSongPosition, 0)
        XCTAssertFalse(content.isSongPositionEnabled)
        XCTAssertTrue(content.isPatternControlsEnabled)
        XCTAssertFalse(content.areInstrumentPlaceholdersEnabled)
    }

    func testFileNewEquivalentControlPanelDisplayStateReturnsToBlankDefaults() {
        var loadedLikeContent = ControlPanelContent()
        loadedLikeContent.songTitle = "Loaded Module"
        loadedLikeContent.songLength = "12"
        loadedLikeContent.songPosition = "05"
        loadedLikeContent.restartPosition = "02"
        loadedLikeContent.patternRowCount = "48"
        loadedLikeContent.channelCount = "16"
        loadedLikeContent.tempo = "180"
        loadedLikeContent.speed = "03"
        loadedLikeContent.selectedOctave = 7
        loadedLikeContent.isLoopEnabled = true
        loadedLikeContent.isEditModeEnabled = true

        let content = ControlPanelDisplayState.blankDocumentContent(
            for: BlankTrackerDocument.makeDefault(),
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertNotEqual(content, loadedLikeContent)
        XCTAssertEqual(content.songTitle, "Untitled")
        XCTAssertEqual(content.songLength, "01")
        XCTAssertEqual(content.songPosition, "00")
        XCTAssertEqual(content.restartPosition, "00")
        XCTAssertEqual(content.patternRowCount, "64")
        XCTAssertEqual(content.channelCount, "8")
        XCTAssertEqual(content.tempo, "125")
        XCTAssertEqual(content.speed, "06")
        XCTAssertEqual(content.selectedOctave, 4)
        XCTAssertFalse(content.isLoopEnabled)
        XCTAssertFalse(content.isEditModeEnabled)
    }

    func testLoadedModuleControlPanelDisplayStateUsesModuleMetadataAndEditorOctave() {
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 6,
            patterns: 2,
            instruments: 3,
            xmFlags: 0x0001,
            defaultTempo: 3,
            defaultBPM: 180,
            songLength: 12,
            restartPosition: 2,
            orderTable: [1, 0],
            xmPatterns: [
                XMPatternData(index: 0, rowCount: 32, channels: 6, rows: []),
                XMPatternData(index: 1, rowCount: 48, channels: 6, rows: [])
            ]
        )

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selectedSongPositionIndex: 5,
            currentPatternIndex: 1,
            selectedOctave: 7,
            isLoopEnabled: true,
            isEditModeEnabled: true,
            isPlaybackActive: true
        )

        XCTAssertEqual(content.songTitle, "Loaded Module")
        XCTAssertEqual(content.songLength, "12")
        XCTAssertEqual(content.songPosition, "05")
        XCTAssertEqual(content.restartPosition, "02")
        XCTAssertEqual(content.patternRowCount, "48")
        XCTAssertEqual(content.channelCount, "6")
        XCTAssertEqual(content.tempo, "180")
        XCTAssertEqual(content.speed, "03")
        XCTAssertEqual(content.selectedOctave, 7)
        XCTAssertEqual(content.songPositionValue, 5)
        XCTAssertEqual(content.maximumSongPosition, 11)
        XCTAssertTrue(content.isLoopEnabled)
        XCTAssertTrue(content.isEditModeEnabled)
        XCTAssertTrue(content.isPlaybackActive)
        XCTAssertTrue(content.isSongPositionEnabled)
        XCTAssertTrue(content.isPatternControlsEnabled)
        XCTAssertTrue(content.areInstrumentPlaceholdersEnabled)
    }

    func testFileNewEquivalentCreatesFreshBlankDocumentState() {
        let previous = BlankTrackerDocument.makeDefault()
        var previousPattern = previous.pattern
        previousPattern.rows[0][0] = XMPatternEventCell(
            note: 48,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0,
            effectParam: 0
        )

        let reset = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(reset.pattern.rows[0][0], .empty)
        XCTAssertNotEqual(previousPattern.rows[0][0], reset.pattern.rows[0][0])
    }

    func testBlankDocumentDoesNotRequirePlaybackOrAudioState() {
        let document = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(document.metadata.instruments, 0)
        XCTAssertEqual(document.metadata.patterns, 1)
        XCTAssertEqual(document.metadata.defaultBPM, 125)
        XCTAssertEqual(document.metadata.defaultTempo, 6)
        XCTAssertEqual(document.metadata.restartPosition, 0)
    }
}
