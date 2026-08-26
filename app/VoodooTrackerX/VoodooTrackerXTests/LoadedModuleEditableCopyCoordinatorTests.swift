import CryptoKit
import XCTest

final class LoadedModuleEditableCopyCoordinatorTests: XCTestCase {
    func testLoadedReadOnlyStoppedXMModuleCanMakeEditableCopyWhenSupported() {
        let context = supportedLoadedContext(isPlaybackActive: false)

        XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context))
        XCTAssertNil(LoadedModuleEditableCopyCoordinator.unavailableReason(for: context))
    }

    func testAlreadyEditableNoDocumentPlaybackAndUnsupportedStatesAreUnavailable() {
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: .editable(isPlaybackActive: false)),
            .alreadyEditable
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: .none(isPlaybackActive: false)),
            .noLoadedModule
        )

        var activePlaybackContext = supportedLoadedContext(isPlaybackActive: true)
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: activePlaybackContext),
            .playbackActive
        )

        activePlaybackContext = .loadedReadOnly(
            metadata: activePlaybackContext.loadedMetadata,
            playbackSong: nil,
            selection: activePlaybackContext.selection,
            currentPatternIndex: activePlaybackContext.currentPatternIndex,
            isPlaybackActive: false
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: activePlaybackContext),
            .missingPlaybackSong
        )

        let unsupportedMetadata = makeLoadedModuleMetadata(type: "MOD", patterns: [])
        let unsupportedContext = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: unsupportedMetadata,
            playbackSong: makePlaybackSong(orderPatternIndices: [0], patternRowCounts: [0: 64]),
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: unsupportedContext),
            .unavailable(.unsupportedLoadedModule)
        )

        let unsupportedSample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, -0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let unsupportedSampleContext = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: supportedLoadedContext(isPlaybackActive: false).loadedMetadata,
            playbackSong: makePlaybackSong(
                orderPatternIndices: [0],
                patternRowCounts: [0: 4],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [unsupportedSample])]
            ),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: unsupportedSampleContext),
            .unavailable(.unsupportedLoadedModule)
        )
    }

    func testAmigaFrequencyTableModuleIsRejectedInsteadOfSilentlyConvertedToLinear() {
        var context = supportedLoadedContext(isPlaybackActive: false)
        context = .loadedReadOnly(
            metadata: context.loadedMetadata.map { metadata in
                makeLoadedModuleMetadata(
                    channels: metadata.channels,
                    xmFlags: 0,
                    orderTable: metadata.orderTable,
                    patterns: metadata.xmPatterns
                )
            },
            playbackSong: context.loadedPlaybackSong,
            selection: context.selection,
            currentPatternIndex: context.currentPatternIndex,
            isPlaybackActive: false
        )

        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: context),
            .unsupportedLoadedModule
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context),
            .unavailable(.unsupportedLoadedModule)
        )
    }

    @MainActor
    func testCopyIsEditableUntitledInMemoryAndDoesNotMutateLoadedSourceState() throws {
        let context = supportedLoadedContext(isPlaybackActive: false)
        let originalMetadata = context.loadedMetadata
        let originalSong = context.loadedPlaybackSong

        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context)

        guard case let .copied(document) = result else {
            return XCTFail("expected editable copy")
        }
        XCTAssertEqual(document.title, BlankTrackerDocument.defaultTitle)
        XCTAssertEqual(document.noteAuditionSourceContext, .blankDocument)
        XCTAssertTrue(EditorPatternMutationPolicy.canMutatePattern(sourceContext: document.noteAuditionSourceContext))
        XCTAssertEqual(context.loadedMetadata, originalMetadata)
        XCTAssertEqual(context.loadedPlaybackSong, originalSong)

        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
        XCTAssertTrue(ExportXMCoordinator.canExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        )))
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: true
        )))

        let mainMenu = ApplicationMenuBuilder.build(target: nil).mainMenu
        let fileMenu = try XCTUnwrap(mainMenu.item(withTitle: "File")?.submenu)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save As...")).isEnabled)
    }

    func testCopyPreservesOrderPatternNotesAndPalettePayload() throws {
        let firstPattern = pattern(
            index: 0,
            rowCount: 4,
            channels: 2,
            cells: [
                (1, 0, XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0x40, effectType: 0x0F, effectParam: 0x06))
            ]
        )
        let secondPattern = pattern(
            index: 1,
            rowCount: 6,
            channels: 2,
            cells: [
                (5, 1, XMPatternEventCell(note: XMPatternEventCell.keyOffNoteValue, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0))
            ]
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Tiny",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: 0.5,
            panning: 37,
            relativeNote: -1,
            finetune: 2,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let metadata = makeLoadedModuleMetadata(
            title: "Loaded Source",
            channels: 2,
            defaultTempo: 3,
            defaultBPM: 140,
            songLength: 2,
            restartPosition: 1,
            orderTable: [0, 1],
            patterns: [firstPattern, secondPattern]
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0, 1],
            patternRowCounts: [0: 4, 1: 6],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, name: "Tiny Inst", samples: [sample])]
        )
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 1,
            isPlaybackActive: false
        )

        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context)

        guard case let .copied(document) = result else {
            return XCTFail("expected editable copy")
        }
        XCTAssertEqual(document.title, "Untitled")
        XCTAssertEqual(document.songLength, 2)
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.restartPosition, 1)
        XCTAssertEqual(document.tempo, 140)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.orderTable, [0, 1])
        XCTAssertEqual(document.patterns, [firstPattern, secondPattern])
        XCTAssertEqual(document.pattern(for: 0)?.rows[1][0].note, 49)
        XCTAssertEqual(document.pattern(for: 1)?.rows[5][1].note, XMPatternEventCell.keyOffNoteValue)
        let copiedSample = try XCTUnwrap(document.instrumentPalette[1]?.sample(selectedSampleSlot: 1))
        XCTAssertEqual(copiedSample.name, "Tiny")
        XCTAssertEqual(copiedSample.pcm, [0, 0.5, -0.5, 0.25])
        XCTAssertEqual(copiedSample.volume, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(copiedSample.panning, 37)
        XCTAssertEqual(copiedSample.relativeNote, -1)
        XCTAssertEqual(copiedSample.finetune, 2)
    }

    @MainActor
    func testExportSmokeAfterEditableCopyReopensAsLoadedReadOnly() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected public fixture to become an editable copy")
        }
        let destination = try temporaryDestination(filename: "editable-copy-smoke.xm")
        let provider = FakeEditableCopyExportXMDestinationProvider(destination: destination)

        let exportResult = ExportXMCoordinator(destinationProvider: provider).beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        XCTAssertEqual(exportResult, .exported(destination: destination))
        let reloaded = try ModuleMetadataLoader().load(fromPath: destination.path)
        XCTAssertEqual(reloaded.type, "XM")
        XCTAssertEqual(reloaded.title, "Untitled")
        XCTAssertEqual(reloaded.orderTable, metadata.orderTable)
        XCTAssertEqual(reloaded.channels, metadata.channels)
        XCTAssertEqual(reloaded.patterns, metadata.patterns)
        XCTAssertEqual(reloaded.instruments, 1)
        XCTAssertEqual(reloaded.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(reloaded.xmPatterns[0].rows[0][0].instrument, 1)

        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
    }

    func testClearedInteriorSampleReopensCopiesAndReexportsByteIdenticallyWithExactIdentityAndMap() throws {
        let first = makePlaybackSample(
            sampleIndex: 0,
            name: "Distinct S01",
            pcm: [-0.25, 0.25],
            volume: 0.5,
            panning: 37,
            relativeNote: -2,
            finetune: 7,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let second = makePlaybackSample(
            sampleIndex: 1,
            name: "Cleared S02",
            pcm: [-0.5, 0, 0.5],
            volume: 0.25,
            panning: 111,
            relativeNote: 1,
            finetune: 2,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let third = makePlaybackSample(
            sampleIndex: 2,
            name: "Distinct S03",
            pcm: [-0.75, 0.75],
            volume: 0.75,
            panning: 201,
            relativeNote: 3,
            finetune: -8,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        noteSampleMap[49] = 2
        let sourceInstrument = PlaybackInstrument(
            index: 1,
            name: "Sparse Instrument",
            samples: [first, second, third],
            autoVibrato: .init(waveformType: 2, sweep: 3, depth: 4, rate: 5),
            noteSampleMap: noteSampleMap
        )
        var sourceDocument = sparseSourceDocument(
            instrument: sourceInstrument,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        )
        XCTAssertTrue(sourceDocument.clearSample(instrumentAt: 0, sampleAt: 1))
        let clearedInstrument = try XCTUnwrap(sourceDocument.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [first, third])
        XCTAssertEqual(clearedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(clearedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(sourceDocument.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(
            sourceDocument.sampleSlotPresentationRows(forInstrument: 1).map(\.isEmptyDestination),
            [false, true, false]
        )

        let sourceData = try EditableXMWriter().data(from: sourceDocument)
        let sourceURL = try temporaryDestination(filename: "sparse-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let loadedInstrument = try XCTUnwrap(song.instrumentsByIndex[1])
        XCTAssertEqual(loadedInstrument, clearedInstrument)
        XCTAssertEqual(loadedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(loadedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
            .init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true),
            .init(sampleIndex: 2, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
        ])
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context))
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected canonical sparse source to become editable")
        }
        let copiedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(copiedInstrument, loadedInstrument)
        XCTAssertEqual(copiedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertNil(copiedInstrument.sample(mappedSampleIndex: 1))
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrument: copiedInstrument
        ))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 50, instrument: copiedInstrument
        )?.sampleIndex, 2)

        let reexportedData = try EditableXMWriter().data(from: document)
        XCTAssertEqual(reexportedData, sourceData)
        let reexportedURL = try temporaryDestination(filename: "sparse-reexported.xm")
        try reexportedData.write(to: reexportedURL, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: reexportedURL.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: reexportedURL.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1], loadedInstrument)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testClearingOnlyMappedSamplePreservesInstrumentMetadataAndMapThroughReopenAndCopy() throws {
        let onlySample = makePlaybackSample(
            name: "Only S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let noteSampleMap = Array(repeating: 0, count: 96)
        let sourceInstrument = PlaybackInstrument(
            index: 1,
            name: "Only Mapped Sample",
            samples: [onlySample],
            volumeEnvelope: .init(
                enabled: true,
                points: [.init(tick: 0, value: 64), .init(tick: 8, value: 32)],
                sustainPointIndex: 1,
                loopStartPointIndex: 0,
                loopEndPointIndex: 1,
                typeFlags: 0x07,
                fadeout: 2_048
            ),
            panningEnvelope: .init(
                enabled: true,
                points: [.init(tick: 0, value: 32), .init(tick: 8, value: 48)],
                sustainPointIndex: 0,
                loopStartPointIndex: 0,
                loopEndPointIndex: 1,
                typeFlags: 0x05
            ),
            autoVibrato: .init(waveformType: 2, sweep: 8, depth: 6, rate: 24),
            noteSampleMap: noteSampleMap
        )
        var document = sparseSourceDocument(instrument: sourceInstrument)

        XCTAssertTrue(document.clearSample(instrumentAt: 0, sampleAt: 0))
        let clearedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [])
        XCTAssertEqual(clearedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(clearedInstrument.name, sourceInstrument.name)
        XCTAssertEqual(clearedInstrument.volumeEnvelope, sourceInstrument.volumeEnvelope)
        XCTAssertEqual(clearedInstrument.panningEnvelope, sourceInstrument.panningEnvelope)
        XCTAssertEqual(clearedInstrument.autoVibrato, sourceInstrument.autoVibrato)
        XCTAssertEqual(document.selection, .default)
        XCTAssertEqual(document.sampleSlotPresentationRows(forInstrument: 1).map(\.isEmptyDestination), [true])

        let sourceData = try EditableXMWriter().data(from: document)
        let sourceURL = try temporaryDestination(filename: "cleared-only-mapped-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let reopenedInstrument = try XCTUnwrap(song.instrumentsByIndex[1])
        XCTAssertEqual(reopenedInstrument, clearedInstrument)
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true),
        ])
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrument: reopenedInstrument
        ))

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(copiedDocument) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected cleared mapped-only source to become editable")
        }
        XCTAssertEqual(copiedDocument.instrumentPalette[1], clearedInstrument)
        XCTAssertEqual(copiedDocument.selection, .default)
        XCTAssertEqual(try EditableXMWriter().data(from: copiedDocument), sourceData)
    }

    func testClearingHighestUnreferencedSelectedSampleKeepsSessionDestinationButDoesNotExtendSerializedSpan() throws {
        let first = makePlaybackSample(
            name: "Mapped S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let second = makePlaybackSample(
            sampleIndex: 1,
            name: "Unreferenced S02",
            pcm: [-0.75, 0, 0.75],
            panning: 201,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let noteSampleMap = Array(repeating: 0, count: 96)
        var document = sparseSourceDocument(
            instrument: PlaybackInstrument(
                index: 1,
                name: "Trailing Session Dest",
                samples: [first, second],
                noteSampleMap: noteSampleMap
            ),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        )

        XCTAssertTrue(document.clearSample(instrumentAt: 0, sampleAt: 1))
        let clearedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [first])
        XCTAssertEqual(clearedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        let sessionRows = document.sampleSlotPresentationRows(forInstrument: 1)
        XCTAssertEqual(sessionRows.map(\.sampleSlot), [1, 2])
        XCTAssertEqual(sessionRows.map(\.isEmptyDestination), [false, true])

        let sourceData = try EditableXMWriter().data(from: document)
        let instrumentOffset = firstInstrumentOffset(in: sourceData)
        XCTAssertEqual(readLE16(sourceData, offset: instrumentOffset + 27), 1)
        let sourceURL = try temporaryDestination(filename: "cleared-unreferenced-trailing-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let reopenedInstrument = try XCTUnwrap(song.instrumentsByIndex[1])
        XCTAssertEqual(reopenedInstrument, clearedInstrument)
        XCTAssertEqual(reopenedInstrument.samples.map(\.sampleIndex), [0])
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
        ])

    }

    func testTrailingReferencedEmptyCanonicalSlotStillRecoversAsEditableCopy() throws {
        let first = makePlaybackSample(
            name: "Only S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        let sourceInstrument = PlaybackInstrument(
            index: 1,
            name: "Trailing Empty",
            samples: [first],
            noteSampleMap: noteSampleMap
        )
        let sourceData = try EditableXMWriter().data(from: sparseSourceDocument(instrument: sourceInstrument))
        let sourceURL = try temporaryDestination(filename: "trailing-empty-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
            .init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true),
        ])
        let selectedEmptyS02 = TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: selectedEmptyS02,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected canonical trailing empty source to become editable")
        }
        XCTAssertEqual(document.instrumentPalette[1], sourceInstrument)
        XCTAssertEqual(document.selection, selectedEmptyS02)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrument: sourceInstrument
        ))
        XCTAssertEqual(try EditableXMWriter().data(from: document), sourceData)
    }

    func testNoncanonicalZeroLengthSourceHeadersRemainUnavailableForEditableCopy() throws {
        let first = makePlaybackSample(
            name: "Only S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        let canonicalData = try EditableXMWriter().data(from: sparseSourceDocument(
            instrument: PlaybackInstrument(index: 1, samples: [first], noteSampleMap: noteSampleMap)
        ))
        let instrumentOffset = firstInstrumentOffset(in: canonicalData)
        let emptyHeaderOffset = firstInstrumentSampleHeaderOffset(in: canonicalData, sampleIndex: 1)
        let mutations: [(String, Int, UInt8, Bool)] = [
            ("name", 18, 0x4E, false),
            ("volume", 12, 1, false),
            ("panning", 15, 128, false),
            ("reserved", 17, 1, false),
            ("unreferenced-trailing-name", 18, 0x4E, true),
        ]

        for (name, fieldOffset, value, removesEmptyReference) in mutations {
            var sourceData = canonicalData
            sourceData[emptyHeaderOffset + fieldOffset] = value
            if removesEmptyReference {
                sourceData.replaceSubrange(instrumentOffset + 33..<instrumentOffset + 129, with: repeatElement(0, count: 96))
            }
            let sourceURL = try temporaryDestination(filename: "noncanonical-empty-\(name).xm")
            try sourceData.write(to: sourceURL, options: .atomic)
            let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
            let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
            let provenance = try XCTUnwrap(song.xmSampleSlotProvenanceByInstrument[1])
            XCTAssertEqual(provenance[1].decodedPayloadLength, 0, name)
            XCTAssertFalse(provenance[1].isCanonicalEmptySlotHeader, name)
            let context = LoadedModuleEditableCopyContext.loadedReadOnly(
                metadata: metadata,
                playbackSong: song,
                selection: .default,
                currentPatternIndex: 0,
                isPlaybackActive: false
            )

            XCTAssertFalse(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context), name)
            XCTAssertEqual(
                LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context),
                .unavailable(.unsupportedLoadedModule),
                name
            )
            XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData, name)
        }
    }

    @MainActor
    func testNonCenterSamplePanningSurvivesLoadedCopyExportAndReopenRoundTrip() throws {
        let sourceURL = try temporaryDestination(filename: "sample-panning-source.xm")
        let sourceData = try EditableXMWriter().data(from: samplePanningSourceDocument(panning: 37))
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        XCTAssertEqual(context.kind, .loadedReadOnly)
        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.samples.first?.panning, 37)
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected generated public-safe XM to become an editable copy")
        }
        XCTAssertEqual(document.instrumentPalette[1]?.samples.first?.panning, 37)

        var editedDocument = document
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: false) },
            documentApplyHandler: { editedDocument = $0 }
        )
        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
        XCTAssertEqual(editedDocument.selection, document.selection)
        let sourceSample = try XCTUnwrap(loadedSong.instrumentsByIndex[1]?.samples.first)
        let editedSample = try XCTUnwrap(editedDocument.instrumentPalette[1]?.samples.first)
        XCTAssertEqual(editedSample.panning, 201)
        XCTAssertEqual(editedSample.withPanning(37), sourceSample)

        let destination = try temporaryDestination(filename: "sample-panning-export.xm")
        let result = ExportXMCoordinator(
            destinationProvider: FakeEditableCopyExportXMDestinationProvider(destination: destination)
        ).beginExport(context: .editable(
            document: editedDocument,
            displayName: editedDocument.title,
            isPlaybackActive: false
        ))
        XCTAssertEqual(result, .exported(destination: destination))

        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        let reopenedSample = try XCTUnwrap(reopenedSong.instrumentsByIndex[1]?.samples.first)
        XCTAssertEqual(reopenedSample.panning, 201)
        XCTAssertEqual(reopenedSample.withPanning(37), sourceSample)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
    }

    @MainActor
    func testEditedSampleVolumeSurvivesLoadedCopyExportAndReopenRoundTrip() throws {
        let sourceURL = try temporaryDestination(filename: "sample-volume-source.xm")
        let sourceData = try EditableXMWriter().data(from: samplePanningSourceDocument(panning: 37, volume: 48))
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected generated public-safe XM to become an editable copy")
        }
        let sourceSample = try XCTUnwrap(loadedSong.instrumentsByIndex[1]?.samples.first)
        XCTAssertEqual(sourceSample.xmVolume, 48)
        XCTAssertEqual(document.instrumentPalette[1]?.samples.first?.xmVolume, 48)

        var editedDocument = document
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: false) },
            documentApplyHandler: { editedDocument = $0 }
        )
        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
        let editedSample = try XCTUnwrap(editedDocument.instrumentPalette[1]?.samples.first)
        XCTAssertEqual(editedSample.xmVolume, 17)
        XCTAssertEqual(editedSample.withVolume(48), sourceSample)
        XCTAssertEqual(editedDocument.selection, document.selection)

        let destination = try temporaryDestination(filename: "sample-volume-export.xm")
        let result = ExportXMCoordinator(
            destinationProvider: FakeEditableCopyExportXMDestinationProvider(destination: destination)
        ).beginExport(context: .editable(
            document: editedDocument,
            displayName: editedDocument.title,
            isPlaybackActive: false
        ))
        XCTAssertEqual(result, .exported(destination: destination))

        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        let reopenedSample = try XCTUnwrap(reopenedSong.instrumentsByIndex[1]?.samples.first)
        XCTAssertEqual(reopenedSample.xmVolume, 17)
        XCTAssertEqual(reopenedSample.withVolume(48), sourceSample)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testInstrumentPanningEnvelopeAndAutoVibratoSurviveLoadedCopyExportAndReopenRoundTrip() throws {
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 32),
                PlaybackEnvelopePoint(tick: 6, value: 48),
                PlaybackEnvelopePoint(tick: 18, value: 16),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 2,
            typeFlags: 0x07
        )
        let autoVibrato = PlaybackInstrumentAutoVibrato(
            waveformType: 3,
            sweep: 17,
            depth: 42,
            rate: 199
        )
        let sourceURL = try temporaryDestination(filename: "instrument-autovibrato-source.xm")
        let sourceData = try EditableXMWriter().data(from: samplePanningSourceDocument(
            panning: 37,
            panningEnvelope: panningEnvelope,
            autoVibrato: autoVibrato
        ))
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.panningEnvelope, panningEnvelope)
        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.autoVibrato, autoVibrato)
        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.samples.first?.panning, 37)
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected generated public-safe XM to become an editable copy")
        }
        XCTAssertEqual(document.instrumentPalette[1]?.panningEnvelope, panningEnvelope)
        XCTAssertEqual(document.instrumentPalette[1]?.autoVibrato, autoVibrato)
        XCTAssertEqual(document.instrumentPalette[1]?.samples.first?.panning, 37)

        let destination = try temporaryDestination(filename: "instrument-autovibrato-export.xm")
        let result = ExportXMCoordinator(
            destinationProvider: FakeEditableCopyExportXMDestinationProvider(destination: destination)
        ).beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))
        XCTAssertEqual(result, .exported(destination: destination))

        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1]?.panningEnvelope, panningEnvelope)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1]?.autoVibrato, autoVibrato)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1]?.samples.first?.panning, 37)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
    }

    @MainActor
    func testSustainedFixtureLoadsCopiesAndNoEditRoundTripsExactSemantics() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let instrument = try XCTUnwrap(loadedSong.instrumentsByIndex[1])
        let sample = try XCTUnwrap(instrument.samples.first)

        XCTAssertEqual(metadata.title, "VTX SUSTAINED")
        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [64])
        XCTAssertEqual(instrument.name, "SUSTAINED DEFAULTS")
        XCTAssertEqual(sample.name, "SINE SUSTAIN 16")
        XCTAssertEqual(sample.sampleLength, 16_384)
        XCTAssertEqual(sample.sourceBitDepthBits, 16)
        XCTAssertEqual(sample.xmVolume, 64)
        XCTAssertEqual(sample.panning, 128)
        XCTAssertEqual(sample.finetune, 0)
        XCTAssertEqual(sample.relativeNote, 0)
        XCTAssertEqual(sample.loopType, 1)
        XCTAssertEqual(sample.loopStart, 4_096)
        XCTAssertEqual(sample.loopLength, 8_192)
        XCTAssertEqual(pcmSHA256(sample), "46c42a0de8820c8b24419c1676b183398d1e7ced677860df1fe0ea45a48779b0")
        XCTAssertEqual(instrument.volumeEnvelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 24, value: 56),
            PlaybackEnvelopePoint(tick: 48, value: 64),
        ])

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected sustained fixture to become an editable copy")
        }
        guard case .potentiallyAvailable = document.noteAuditionAvailability else {
            return XCTFail("expected sustained fixture note preview to be available")
        }
        XCTAssertEqual(document.instrumentPalette, loadedSong.instrumentsByIndex)

        let destination = try temporaryDestination(filename: "round-trip-sustained.xm")
        try EditableXMWriter().data(from: document).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedMetadata.orderTable, metadata.orderTable)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, loadedSong.instrumentsByIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testSustainedFixtureSupportsFocusedEditsUndoRedoAndExportReopen() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(sourceDocument) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected sustained fixture to become editable")
        }
        let sourceInstrument = try XCTUnwrap(sourceDocument.instrumentPalette[1])
        let sourceSample = try XCTUnwrap(sourceInstrument.samples.first)
        let sourcePlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: sourceDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        var editedDocument = sourceDocument
        var playbackActive = false
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: playbackActive) },
            documentApplyHandler: { editedDocument = $0 }
        )

        XCTAssertTrue(coordinator.renameInstrument(at: 0, name: "Edited Sustained"))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.name, sourceInstrument.name)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
        let panningPlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: editedDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        XCTAssertEqual(panningPlan.pattern.events.map(\.pan), Array(
            repeating: PlaybackSamplePanningPolicy.plannedPan(201),
            count: sourcePlan.pattern.events.count
        ))
        XCTAssertEqual(panningPlan.pattern.events.map(\.row), sourcePlan.pattern.events.map(\.row))
        XCTAssertEqual(panningPlan.pattern.events.map(\.tick), sourcePlan.pattern.events.map(\.tick))
        XCTAssertEqual(panningPlan.pattern.events.map(\.gain), sourcePlan.pattern.events.map(\.gain))
        XCTAssertEqual(panningPlan.pattern.events.map(\.playbackStep), sourcePlan.pattern.events.map(\.playbackStep))
        XCTAssertEqual(panningPlan.pattern.events.map(\.sample), sourcePlan.pattern.events.map(\.sample))
        XCTAssertEqual(panningPlan.pattern.events.map(\.loop), sourcePlan.pattern.events.map(\.loop))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.panning, 128)
        XCTAssertTrue(coordinator.redo())

        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.xmVolume, 64)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: 64))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.finetune, 0)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: -12))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.relativeNote, 0)
        XCTAssertTrue(coordinator.redo())

        playbackActive = true
        let previewAvailability = editedDocument.noteAuditionAvailability
        XCTAssertFalse(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 17))
        XCTAssertEqual(editedDocument.noteAuditionAvailability, previewAvailability)
        playbackActive = false

        let editedInstrument = try XCTUnwrap(editedDocument.instrumentPalette[1])
        let editedSample = try XCTUnwrap(editedInstrument.samples.first)
        XCTAssertEqual(editedInstrument.name, "Edited Sustained")
        XCTAssertEqual(editedSample.panning, 201)
        XCTAssertEqual(editedSample.xmVolume, 17)
        XCTAssertEqual(editedSample.finetune, 64)
        XCTAssertEqual(editedSample.relativeNote, -12)
        XCTAssertEqual(editedSample.pcm, sourceSample.pcm)
        XCTAssertEqual(editedSample.loopRegion, sourceSample.loopRegion)
        XCTAssertEqual(editedInstrument.volumeEnvelope, sourceInstrument.volumeEnvelope)
        let editedPlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: editedDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        let sourceEvent = try XCTUnwrap(sourcePlan.pattern.events.first)
        let editedEvent = try XCTUnwrap(editedPlan.pattern.events.first)
        XCTAssertEqual(editedEvent.gain, 17.0 / 64.0, accuracy: 0.000_001)
        XCTAssertEqual(
            editedEvent.playbackStep,
            sourceEvent.playbackStep * pow(2.0, -11.5 / 12.0),
            accuracy: 0.000_001
        )

        let destination = try temporaryDestination(filename: "edited-sustained.xm")
        try EditableXMWriter().data(from: editedDocument).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1], editedInstrument)
    }

    @MainActor
    func testMetadataMatrixFixtureLoadsCopiesAndNoEditRoundTripsExactSemantics() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-metadata-matrix.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let samples = try (1...5).map { try XCTUnwrap(loadedSong.instrumentsByIndex[$0]?.samples.first) }

        XCTAssertEqual(metadata.title, "VTX META MATRIX")
        XCTAssertEqual(metadata.instruments, 5)
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [48])
        XCTAssertEqual(samples.map(\.xmVolume), [0, 16, 32, 48, 64])
        XCTAssertEqual(samples.map(\.panning), [0, 64, 128, 192, 255])
        XCTAssertEqual(samples.map(\.finetune), [-96, -32, 0, 48, 96])
        XCTAssertEqual(samples.map(\.relativeNote), [-12, 5, -5, 12, 0])
        XCTAssertEqual(samples.map(\.sourceBitDepthBits), [8, 16, 8, 16, 8])
        XCTAssertEqual(samples.map(\.loopType), [0, 1, 2, 0, 1])
        XCTAssertEqual(samples.map(pcmSHA256), [
            "47a72c66257b66e4f88bb5e0debaf033873db681b1355945de9370f4bac43984",
            "f333231435f182b19ad8e75a6687fa3ee79d963a36ba6a7599e5f9612e49d838",
            "fad28cc0b65e3ca34d80665310de002cce1ea02327185abae6eb2676945891dc",
            "1bab28408c4d7ac5b9ed7d8d87595ec051ce5f744077487865dbde189b63ab33",
            "151d0d127539d5eb8c8a7dbcfb3d1b01434ed30c6f63325d770b05b080e5b147",
        ])

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 3, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected metadata matrix to become editable")
        }
        XCTAssertEqual(document.instrumentPalette, loadedSong.instrumentsByIndex)

        let destination = try temporaryDestination(filename: "round-trip-metadata-matrix.xm")
        try EditableXMWriter().data(from: document).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, loadedSong.instrumentsByIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testMetadataMatrixFocusedMutationPreservesNeighborsAndPanningAffectsNextPlan() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-metadata-matrix.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 3, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(sourceDocument) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected metadata matrix to become editable")
        }
        let sourceInstrument = try XCTUnwrap(sourceDocument.instrumentPalette[3])
        let sourceSample = try XCTUnwrap(sourceInstrument.samples.first)
        let sourcePlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: sourceDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        var editedDocument = sourceDocument
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: false) },
            documentApplyHandler: { editedDocument = $0 }
        )

        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 2, sampleAt: 0, panning: 37))
        let editedPanningPlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: editedDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        let sourceMapping = try XCTUnwrap(sourcePlan.diagnostics.eventMappings.first { $0.instrumentIndex == 3 })
        let editedMapping = try XCTUnwrap(editedPanningPlan.diagnostics.eventMappings.first { $0.instrumentIndex == 3 })
        let sourceEvent = sourcePlan.pattern.events[sourceMapping.eventIndex]
        let editedEvent = editedPanningPlan.pattern.events[editedMapping.eventIndex]
        XCTAssertEqual(sourceEvent.pan, 0)
        XCTAssertEqual(editedEvent.pan, PlaybackSamplePanningPolicy.plannedPan(37), accuracy: 0.000_001)
        XCTAssertEqual(sourceEvent.row, editedEvent.row)
        XCTAssertEqual(sourceEvent.tick, editedEvent.tick)
        XCTAssertEqual(sourceEvent.gain, editedEvent.gain)
        XCTAssertEqual(sourceEvent.playbackStep, editedEvent.playbackStep)
        XCTAssertEqual(sourcePlan.pattern.events.count, editedPanningPlan.pattern.events.count)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.panning, 128)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 2, sampleAt: 0, volume: 47))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.xmVolume, 32)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleFinetune(instrumentAt: 2, sampleAt: 0, finetune: -17))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.finetune, 0)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleRelativeNote(instrumentAt: 2, sampleAt: 0, relativeNote: 7))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.relativeNote, -5)
        XCTAssertTrue(coordinator.redo())

        let editedInstrument = try XCTUnwrap(editedDocument.instrumentPalette[3])
        let editedSample = try XCTUnwrap(editedInstrument.samples.first)
        XCTAssertEqual(editedSample.panning, 37)
        XCTAssertEqual(editedSample.xmVolume, 47)
        XCTAssertEqual(editedSample.finetune, -17)
        XCTAssertEqual(editedSample.relativeNote, 7)
        XCTAssertEqual(editedSample.pcm, sourceSample.pcm)
        XCTAssertEqual(editedSample.loopRegion, sourceSample.loopRegion)
        XCTAssertEqual(editedSample.name, sourceSample.name)
        for instrumentIndex in [1, 2, 4, 5] {
            XCTAssertEqual(editedDocument.instrumentPalette[instrumentIndex], sourceDocument.instrumentPalette[instrumentIndex])
        }

        let destination = try temporaryDestination(filename: "edited-metadata-matrix.xm")
        try EditableXMWriter().data(from: editedDocument).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, editedDocument.instrumentPalette)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testEnvelopesKeymapFixtureLoadsCopiesAndRoundTripsExactSemantics() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-envelopes-keymap.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let instrument = try XCTUnwrap(loadedSong.instrumentsByIndex[1])

        XCTAssertEqual(metadata.title, "VTX ENV KEYMAP")
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [32])
        XCTAssertEqual(instrument.name, "SPLIT ENV KEYMAP")
        XCTAssertEqual(instrument.samples.map(\.name), ["LOW PULSE 8", "HIGH TRIANGLE 16"])
        XCTAssertEqual(instrument.samples.map(\.sourceBitDepthBits), [8, 16])
        XCTAssertEqual(instrument.samples.map(\.loopType), [1, 1])
        XCTAssertEqual(instrument.samples.map(\.loopStart), [256, 256])
        XCTAssertEqual(instrument.samples.map(\.loopLength), [1_536, 1_536])
        XCTAssertEqual(instrument.samples.map(pcmSHA256), [
            "405470958403dee4c1dbd41c888b2f8f6cb7c8eb5d950dcf1f4fcf09e447fc33",
            "24d3e9d895e34280cf17e78111b7c5d14c035996c8c88d8bd3a0d78c5077b46b",
        ])
        let noteSampleMap = try XCTUnwrap(instrument.noteSampleMap)
        XCTAssertEqual(Array(noteSampleMap.prefix(48)), Array(repeating: 0, count: 48))
        XCTAssertEqual(Array(noteSampleMap.suffix(48)), Array(repeating: 1, count: 48))
        XCTAssertEqual(instrument.mappedSampleIndex(forNote: 48), 0)
        XCTAssertEqual(instrument.mappedSampleIndex(forNote: 49), 1)
        XCTAssertEqual(instrument.volumeEnvelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 8, value: 48),
            PlaybackEnvelopePoint(tick: 16, value: 32),
            PlaybackEnvelopePoint(tick: 24, value: 64),
        ])
        XCTAssertEqual(instrument.volumeEnvelope.sustainPointIndex, 1)
        XCTAssertEqual(instrument.volumeEnvelope.loopStartPointIndex, 1)
        XCTAssertEqual(instrument.volumeEnvelope.loopEndPointIndex, 3)
        XCTAssertEqual(instrument.volumeEnvelope.typeFlags, 7)
        XCTAssertEqual(instrument.volumeEnvelope.fadeout, 2_048)
        XCTAssertEqual(instrument.panningEnvelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 32),
            PlaybackEnvelopePoint(tick: 8, value: 48),
            PlaybackEnvelopePoint(tick: 16, value: 16),
            PlaybackEnvelopePoint(tick: 24, value: 32),
        ])
        XCTAssertEqual(instrument.panningEnvelope.sustainPointIndex, 2)
        XCTAssertEqual(instrument.panningEnvelope.loopStartPointIndex, 0)
        XCTAssertEqual(instrument.panningEnvelope.loopEndPointIndex, 3)
        XCTAssertEqual(instrument.panningEnvelope.typeFlags, 7)
        XCTAssertEqual(instrument.autoVibrato, PlaybackInstrumentAutoVibrato(
            waveformType: 2,
            sweep: 8,
            depth: 6,
            rate: 24
        ))

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected envelopes/keymap fixture to become editable")
        }
        XCTAssertEqual(document.instrumentPalette, loadedSong.instrumentsByIndex)

        let destination = try temporaryDestination(filename: "round-trip-envelopes-keymap.xm")
        try EditableXMWriter().data(from: document).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, loadedSong.instrumentsByIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    private func supportedLoadedContext(isPlaybackActive: Bool) -> LoadedModuleEditableCopyContext {
        let pattern = pattern(
            index: 0,
            rowCount: 4,
            channels: 1,
            cells: [
                (0, 0, XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0))
            ]
        )
        let metadata = makeLoadedModuleMetadata(
            channels: 1,
            orderTable: [0],
            patterns: [pattern]
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 4]
        )
        return .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: isPlaybackActive
        )
    }

    private func sparseSourceDocument(
        instrument: PlaybackInstrument,
        selection: TrackerEditorSelection = .default
    ) -> BlankTrackerDocument {
        BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: 1,
            currentPosition: 0,
            restartPosition: 0,
            currentPatternIndex: 0,
            tempo: 125,
            speed: 6,
            orderTable: [0],
            selection: selection,
            instrumentPalette: [instrument.index: instrument],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)]
        )
    }

    private func firstInstrumentSampleHeaderOffset(in data: Data, sampleIndex: Int) -> Int {
        let offset = firstInstrumentOffset(in: data)
        let instrumentHeaderSize = Int(readLE32(data, offset: offset))
        let sampleHeaderSize = Int(readLE32(data, offset: offset + 29))
        return offset + instrumentHeaderSize + (sampleIndex * sampleHeaderSize)
    }

    private func firstInstrumentOffset(in data: Data) -> Int {
        var offset = 60 + Int(readLE32(data, offset: 60))
        for _ in 0..<Int(readLE16(data, offset: 70)) {
            offset += Int(readLE32(data, offset: offset)) + Int(readLE16(data, offset: offset + 7))
        }
        return offset
    }

    private func readLE16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readLE32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private func samplePanningSourceDocument(
        panning: UInt8,
        volume: UInt8 = 64,
        panningEnvelope: PlaybackPanningEnvelope = .disabled,
        autoVibrato: PlaybackInstrumentAutoVibrato = .disabled
    ) -> BlankTrackerDocument {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)
        pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Panning Sample",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: Float(volume) / 64.0,
            panning: panning,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        return BlankTrackerDocument(
            title: "Panning Source",
            songLength: 1,
            currentPosition: 0,
            restartPosition: 0,
            currentPatternIndex: 0,
            tempo: 125,
            speed: 6,
            orderTable: [0],
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    name: "Panning Instrument",
                    samples: [sample],
                    panningEnvelope: panningEnvelope,
                    autoVibrato: autoVibrato
                )
            ],
            patterns: [pattern]
        )
    }

    private func makeLoadedModuleMetadata(
        type: String = "XM",
        title: String = "Loaded Module",
        channels: Int = 1,
        instruments: Int = 0,
        xmFlags: Int = 0x0001,
        defaultTempo: Int = 6,
        defaultBPM: Int = 125,
        songLength: Int? = nil,
        restartPosition: Int = 0,
        orderTable: [Int] = [0],
        patterns: [XMPatternData]
    ) -> ParsedModuleMetadata {
        ParsedModuleMetadata(
            type: type,
            title: title,
            version: type == "XM" ? "1.4" : nil,
            channels: channels,
            patterns: patterns.count,
            instruments: instruments,
            xmFlags: xmFlags,
            defaultTempo: defaultTempo,
            defaultBPM: defaultBPM,
            songLength: songLength ?? orderTable.count,
            restartPosition: restartPosition,
            orderTable: orderTable,
            xmPatterns: patterns
        )
    }

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("tests/reference-xm")
            .appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing reference XM fixture \(relativePath)")
        }
        return url
    }

    private func pcmSHA256(_ sample: PlaybackSample) -> String {
        var data = Data()
        if sample.sourceBitDepthBits == 16 {
            for value in sample.pcm {
                let quantized = UInt16(truncatingIfNeeded: max(-32_768, min(32_767, Int((value * 32_768).rounded()))))
                data.append(UInt8(quantized & 0x00FF))
                data.append(UInt8((quantized >> 8) & 0x00FF))
            }
        } else {
            for value in sample.pcm {
                data.append(UInt8(truncatingIfNeeded: max(-128, min(127, Int((value * 128).rounded())))))
            }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryDestination(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtx-editable-copy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(filename)
    }

    private func pattern(
        index: Int,
        rowCount: Int,
        channels: Int,
        cells: [(row: Int, channel: Int, cell: XMPatternEventCell)]
    ) -> XMPatternData {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: index, rowCount: rowCount, channels: channels)
        for cell in cells where pattern.rows.indices.contains(cell.row) && pattern.rows[cell.row].indices.contains(cell.channel) {
            pattern.rows[cell.row][cell.channel] = cell.cell
        }
        return pattern
    }
}

@MainActor
private final class FakeEditableCopyExportXMDestinationProvider: ExportXMDestinationProviding {
    private let destination: URL?
    private(set) var requests = [ExportXMDestinationRequest]()

    init(destination: URL?) {
        self.destination = destination
    }

    func chooseExportXMDestination(request: ExportXMDestinationRequest) -> URL? {
        requests.append(request)
        return destination
    }
}
