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
    }
}
