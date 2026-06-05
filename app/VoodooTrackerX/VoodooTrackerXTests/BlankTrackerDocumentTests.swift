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
        XCTAssertEqual(document.selection, .default)
        XCTAssertEqual(document.selection.selectedInstrument, 1)
        XCTAssertEqual(document.selection.selectedSample, 1)
    }

    func testTrackerEditorSelectionUsesOneBasedTrackerDefaultsAndClampsToSlotRange() {
        XCTAssertEqual(TrackerEditorSelection.default.selectedInstrument, 1)
        XCTAssertEqual(TrackerEditorSelection.default.selectedSample, 1)
        XCTAssertEqual(TrackerEditorSelection.default.instrumentDisplayTitle, "I01")
        XCTAssertEqual(TrackerEditorSelection.default.sampleDisplayTitle, "S01")

        let clampedLow = TrackerEditorSelection(selectedInstrument: 0, selectedSample: -8)
        XCTAssertEqual(clampedLow.selectedInstrument, 1)
        XCTAssertEqual(clampedLow.selectedSample, 1)

        let clampedHigh = TrackerEditorSelection(selectedInstrument: 999, selectedSample: 300)
        XCTAssertEqual(clampedHigh.selectedInstrument, 255)
        XCTAssertEqual(clampedHigh.selectedSample, 255)
        XCTAssertEqual(clampedHigh.instrumentDisplayTitle, "IFF")
        XCTAssertEqual(clampedHigh.sampleDisplayTitle, "SFF")
    }

    func testEditorNoteAuditionRequestCapturesNoteSelectionAndSourceContext() {
        let selection = TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3)
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "q",
            selectedOctave: 4,
            selection: selection,
            sourceContext: .blankDocument,
            channelIndex: 2,
            rowIndex: 12
        )

        XCTAssertEqual(
            request,
            EditorNoteAuditionRequest(
                kind: .noteOn(noteValue: 61, selectedOctave: 4),
                selection: selection,
                sourceContext: .blankDocument,
                channelIndex: 2,
                rowIndex: 12
            )
        )
        XCTAssertEqual(request?.selectedInstrumentIndex, 7)
        XCTAssertEqual(request?.selectedSampleIndex, 3)
    }

    func testEditorNoteAuditionRequestRejectsNonNoteKeys() {
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "i",
            selectedOctave: 4,
            selection: .default,
            sourceContext: .blankDocument
        )

        XCTAssertNil(request)
    }

    func testBlankDocumentNoteAuditionAvailabilityIsUnavailableWithoutInstrumentSamplePayload() {
        let document = BlankTrackerDocument.makeDefault()
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "z",
            selectedOctave: 4,
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(document.noteAuditionSourceContext, .blankDocument)
        XCTAssertEqual(document.noteAuditionAvailability, .unavailable(.blankDocumentMissingInstrumentSamplePayload))
        let availability = request.map {
            EditorNoteAuditionAvailabilityResolver.availability(
                for: $0,
                hasRealInstrumentSamplePayload: false,
                selectedInstrumentSampleIsPlayable: false
            )
        }

        XCTAssertEqual(availability, .unavailable(.blankDocumentMissingInstrumentSamplePayload))
    }

    func testLoadedModuleNoteAuditionAvailabilityCanBeAvailableWhenPlayableSampleResolves() {
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 2),
            channelIndex: 0,
            rowIndex: 16
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(
                for: request,
                hasRealInstrumentSamplePayload: true,
                selectedInstrumentSampleIsPlayable: true
            ),
            .available
        )
        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(
                for: request,
                hasRealInstrumentSamplePayload: true,
                selectedInstrumentSampleIsPlayable: false
            ),
            .unavailable(.selectedInstrumentSampleNotPlayable)
        )
    }

    func testPreviewKeyReleaseRequestDoesNotWritePatternKeyOffData() {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let beforeRelease = document

        let request = EditorNoteAuditionRequest.previewKeyOff(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(request.kind, .previewKeyOff)
        XCTAssertEqual(document, beforeRelease)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
        XCTAssertNotEqual(document.pattern.rows[0][0].note, TrackerNoteKeyMap.keyOffNoteValue)
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
        XCTAssertEqual(metadata.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(metadata.selectedSampleDisplay, "S01")
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
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(content.selectedSampleDisplay, "S01")
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
        loadedLikeContent.selectedInstrumentDisplay = "I07"
        loadedLikeContent.selectedSampleDisplay = "S03"
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
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(content.selectedSampleDisplay, "S01")
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
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(content.selectedSampleDisplay, "Sample Map")
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
        XCTAssertEqual(reset.selection, .default)
        XCTAssertNotEqual(previousPattern.rows[0][0], reset.pattern.rows[0][0])
    }

    func testEnteringNaturalTrackerNoteMutatesSelectedBlankPatternCell() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0].note, 49)
        XCTAssertEqual(document.pattern.rows[0][1], .empty)
    }

    func testLowerRowNaturalAndSharpTrackerNotesUseSelectedOctave() {
        let expectedNotes: [(Character, UInt8, String)] = [
            ("z", 49, "C-4"),
            ("s", 50, "C#4"),
            ("x", 51, "D-4"),
            ("d", 52, "D#4"),
            ("c", 53, "E-4"),
            ("v", 54, "F-4"),
            ("g", 55, "F#4"),
            ("b", 56, "G-4"),
            ("h", 57, "G#4"),
            ("n", 58, "A-4"),
            ("j", 59, "A#4"),
            ("m", 60, "B-4")
        ]

        for (key, noteValue, noteText) in expectedNotes {
            var document = BlankTrackerDocument.makeDefault()

            XCTAssertTrue(document.enterNote(trackerKey: key, octave: 4, row: 0, channel: 0), String(key))
            XCTAssertEqual(document.pattern.rows[0][0].note, noteValue, String(key))
            XCTAssertEqual(ModuleMetadataLoader.formatXMNote(noteValue), noteText, String(key))
        }
    }

    func testUpperRowNaturalTrackerNotesUseSelectedOctavePlusOne() {
        let expectedNotes: [(Character, UInt8, String)] = [
            ("q", 61, "C-5"),
            ("w", 63, "D-5"),
            ("e", 65, "E-5"),
            ("r", 66, "F-5"),
            ("t", 68, "G-5"),
            ("y", 70, "A-5"),
            ("u", 72, "B-5")
        ]

        for (key, noteValue, noteText) in expectedNotes {
            var document = BlankTrackerDocument.makeDefault()

            XCTAssertTrue(document.enterNote(trackerKey: key, octave: 4, row: 0, channel: 0), String(key))
            XCTAssertEqual(document.pattern.rows[0][0].note, noteValue, String(key))
            XCTAssertEqual(ModuleMetadataLoader.formatXMNote(noteValue), noteText, String(key))
        }
    }

    func testUpperRowSharpTrackerNotesUseSelectedOctavePlusOne() {
        let expectedNotes: [(Character, UInt8, String)] = [
            ("2", 62, "C#5"),
            ("3", 64, "D#5"),
            ("5", 67, "F#5"),
            ("6", 69, "G#5"),
            ("7", 71, "A#5")
        ]

        for (key, noteValue, noteText) in expectedNotes {
            var document = BlankTrackerDocument.makeDefault()

            XCTAssertTrue(document.enterNote(trackerKey: key, octave: 4, row: 0, channel: 0), String(key))
            XCTAssertEqual(document.pattern.rows[0][0].note, noteValue, String(key))
            XCTAssertEqual(ModuleMetadataLoader.formatXMNote(noteValue), noteText, String(key))
        }
    }

    func testEditedBlankPatternCellFormatsExpectedNaturalNoteText() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
    }

    func testNoteEntryUsesSelectedOctave() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "m", octave: 7, row: 3, channel: 2))

        XCTAssertEqual(document.pattern.rows[3][2].note, 96)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[3][2].note), "B-7")
    }

    func testSelectedOctaveChangesAffectLowerAndUpperRows() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 3, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 3, row: 1, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 5, row: 2, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 5, row: 3, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "C-3")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[1][0].note), "C-4")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[2][0].note), "C-5")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[3][0].note), "C-6")
    }

    func testUpperRowClampsToSupportedNoteRangeNearTopOctave() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 7, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "u", octave: 7, row: 1, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "C-7")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[1][0].note), "B-7")
    }

    func testAccidentalNoteEntryUsesSelectedOctave() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "s", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "j", octave: 5, row: 1, channel: 1))

        XCTAssertEqual(document.pattern.rows[0][0].note, 50)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "C#4")
        XCTAssertEqual(document.pattern.rows[1][1].note, 71)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[1][1].note), "A#5")
    }

    func testKeyOffEntryUsesDistinctNoteOffValueAndFormatsAsEquals() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0].note, TrackerNoteKeyMap.keyOffNoteValue)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "===")
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "=== .. .. ...")
        XCTAssertNotEqual(document.pattern.rows[0][0], .empty)
    }

    func testKeyOffDisplayIsDistinctFromEmptyCellDisplay() {
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(0), "...")
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(.empty), "... .. .. ...")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(TrackerNoteKeyMap.keyOffNoteValue), "===")
        XCTAssertNotEqual(ModuleMetadataLoader.formatXMNote(0), ModuleMetadataLoader.formatXMNote(TrackerNoteKeyMap.keyOffNoteValue))
    }

    func testClearNoteReturnsSelectedNoteCellToEmptyDisplay() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))
        XCTAssertTrue(document.clearNote(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0], .empty)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "...")
    }

    func testNoteKeyOffAndClearEntryUseOneRowEditStepAndClampAtFinalRow() {
        var row = 10
        row = TrackerEditStep.advancedRow(after: row, rowCount: BlankTrackerDocument.defaultRowCount)
        XCTAssertEqual(row, 11)

        row = TrackerEditStep.advancedRow(after: 63, rowCount: BlankTrackerDocument.defaultRowCount)
        XCTAssertEqual(row, 63)
    }

    func testFinalRowNoteEntryIsSafeAndClampsEditAdvance() {
        var document = BlankTrackerDocument.makeDefault()
        let selectedRow = 63
        let selectedChannel = 0

        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: selectedRow, channel: selectedChannel))
        let advancedRow = TrackerEditStep.advancedRow(after: selectedRow, rowCount: document.pattern.rowCount)

        XCTAssertEqual(document.pattern.rows[63][0].note, 51)
        XCTAssertEqual(advancedRow, 63)
        XCTAssertEqual(document.pattern.rows.count, BlankTrackerDocument.defaultRowCount)
    }

    func testFinalRowUpperNoteEntryUsesSameEditAdvanceClamp() {
        var document = BlankTrackerDocument.makeDefault()
        let selectedRow = 63

        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 4, row: selectedRow, channel: 0))
        let advancedRow = TrackerEditStep.advancedRow(after: selectedRow, rowCount: document.pattern.rowCount)

        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[63][0].note), "C-5")
        XCTAssertEqual(advancedRow, 63)
    }

    func testBlankDocumentNoteEntryRejectsNonNoteKeysAndOutOfRangeCoordinates() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertFalse(document.enterNote(trackerKey: "i", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: ",", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: ".", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "/", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "z", octave: 8, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "z", octave: 4, row: 64, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 8))
        XCTAssertFalse(document.enterKeyOff(row: 64, channel: 0))
        XCTAssertFalse(document.clearNote(row: 0, channel: 8))
        XCTAssertEqual(document.pattern.rows[0][0], .empty)
    }

    func testBlankDocumentDoesNotRequirePlaybackOrAudioState() {
        let document = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(document.metadata.instruments, 0)
        XCTAssertEqual(document.metadata.patterns, 1)
        XCTAssertEqual(document.metadata.defaultBPM, 125)
        XCTAssertEqual(document.metadata.defaultTempo, 6)
        XCTAssertEqual(document.metadata.restartPosition, 0)
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(document.controlPanelMetadata.selectedSampleDisplay, "S01")
    }
}
