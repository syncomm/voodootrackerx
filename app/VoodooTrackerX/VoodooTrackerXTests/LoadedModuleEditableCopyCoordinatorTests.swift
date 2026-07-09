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

    private func makeLoadedModuleMetadata(
        type: String = "XM",
        title: String = "Loaded Module",
        channels: Int = 1,
        instruments: Int = 0,
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
            xmFlags: 0x0001,
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

    private func temporaryDestination(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtx-editable-copy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
