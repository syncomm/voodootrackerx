import Foundation
import XCTest

@MainActor
final class ExportXMCoordinatorTests: XCTestCase {
    func testEditableStoppedDocumentWritesNormalizedXMFileAndReloadsThroughParser() throws {
        var firstPattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 2)
        var secondPattern = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 6, channels: 2)
        firstPattern.rows[2][1] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        secondPattern.rows[5][0] = XMPatternEventCell(
            note: 52,
            instrument: 1,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        let document = makeDocument(
            title: "Export Smoke",
            restartPosition: 1,
            tempo: 140,
            speed: 3,
            orderTable: [0, 1],
            patterns: [firstPattern, secondPattern]
        )
        let originalDocument = document
        let selectedDestination = try temporaryDestination(filename: "song")
        let expectedDestination = ExportXMCoordinator.normalizedXMURL(selectedDestination)
        let provider = FakeExportXMDestinationProvider(destination: selectedDestination)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let context = ExportXMDocumentContext.editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        )

        XCTAssertTrue(ExportXMCoordinator.canExport(context: context))
        let result = coordinator.beginExport(context: context)

        XCTAssertEqual(provider.requests, [
            ExportXMDestinationRequest(suggestedFilename: "Export Smoke.xm")
        ])
        XCTAssertEqual(result, .exported(destination: expectedDestination))
        XCTAssertEqual(result.userFacingTitle, "Export XM Completed")
        XCTAssertEqual(result.userFacingMessage, "Export XM completed.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedDestination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDestination.path))
        XCTAssertEqual(document, originalDocument)

        let metadata = try ModuleMetadataLoader().load(fromPath: expectedDestination.path)
        XCTAssertEqual(metadata.type, "XM")
        XCTAssertEqual(metadata.title, "Export Smoke")
        XCTAssertEqual(metadata.version, "1.4")
        XCTAssertEqual(metadata.songLength, 2)
        XCTAssertEqual(metadata.orderTable, [0, 1])
        XCTAssertEqual(metadata.restartPosition, 1)
        XCTAssertEqual(metadata.channels, 2)
        XCTAssertEqual(metadata.patterns, 2)
        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(metadata.defaultTempo, 3)
        XCTAssertEqual(metadata.defaultBPM, 140)

        let reloadedFirst = try XCTUnwrap(metadata.xmPattern(index: 0))
        let reloadedSecond = try XCTUnwrap(metadata.xmPattern(index: 1))
        XCTAssertEqual(reloadedFirst.rowCount, 4)
        XCTAssertEqual(reloadedSecond.rowCount, 6)
        XCTAssertEqual(
            reloadedFirst.rows[2][1],
            XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        )
        XCTAssertEqual(
            reloadedSecond.rows[5][0],
            XMPatternEventCell(note: 52, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        )
    }

    func testEditableStoppedSampleBearingDocumentWritesReloadableSamplePayload() throws {
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
            name: "Tiny",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: 0.5,
            relativeNote: -1,
            finetune: 2,
            baseSampleRate: 8_363,
            sampleLength: 4,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var document = makeDocument(
            title: "Sample Export",
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, name: "Tiny Inst", samples: [sample])
            ]
        )
        XCTAssertTrue(document.renameInstrument(at: 0, name: "Renamed Tiny"))
        let selectedDestination = try temporaryDestination(filename: "sample-export.xm")
        let provider = FakeExportXMDestinationProvider(destination: selectedDestination)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        XCTAssertEqual(result, .exported(destination: selectedDestination))
        let metadata = try ModuleMetadataLoader().load(fromPath: selectedDestination.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: selectedDestination.path)
        XCTAssertEqual(metadata.instruments, 1)
        let reloadedPattern = try XCTUnwrap(metadata.xmPattern(index: 0))
        XCTAssertEqual(reloadedPattern.rows[0][0].instrument, 1)
        let instrument = try XCTUnwrap(song.instrument(forInstrument: 1))
        XCTAssertEqual(instrument.name, "Renamed Tiny")
        let reloadedSample = try XCTUnwrap(instrument.sample(mappedSampleIndex: 0))
        XCTAssertEqual(reloadedSample.name, "Tiny")
        XCTAssertEqual(reloadedSample.pcm.count, 4)
        XCTAssertEqual(reloadedSample.volume, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(reloadedSample.relativeNote, -1)
        XCTAssertEqual(reloadedSample.finetune, 2)
    }

    func testCancelingDestinationSelectionWritesNothingAndLeavesDocumentUnchanged() throws {
        let document = BlankTrackerDocument.makeDefault()
        let originalDocument = document
        let destination = try temporaryDestination(filename: "cancelled.xm")
        let provider = FakeExportXMDestinationProvider(destination: nil)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(result.userFacingTitle)
        XCTAssertNil(result.userFacingMessage)
        XCTAssertEqual(provider.requests, [
            ExportXMDestinationRequest(suggestedFilename: "Untitled.xm")
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(document, originalDocument)
    }

    func testLoadedReadOnlyModuleIsDisabledAndDoesNotRequestDestination() {
        let provider = FakeExportXMDestinationProvider(
            destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.xm")
        )
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let context = ExportXMDocumentContext.loadedReadOnly(isPlaybackActive: false)

        XCTAssertFalse(ExportXMCoordinator.canExport(context: context))
        XCTAssertEqual(coordinator.beginExport(context: context), .unavailable(.loadedModuleReadOnly))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testActivePlaybackIsDisabledAndDoesNotRequestDestination() {
        let document = BlankTrackerDocument.makeDefault()
        let provider = FakeExportXMDestinationProvider(
            destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.xm")
        )
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let context = ExportXMDocumentContext.editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: true
        )

        XCTAssertFalse(ExportXMCoordinator.canExport(context: context))
        XCTAssertEqual(coordinator.beginExport(context: context), .unavailable(.playbackActive))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testNoDocumentAndInvalidEditableStateAreDisabledWithoutDestinationRequest() {
        let document = BlankTrackerDocument.makeDefault()
        let provider = FakeExportXMDestinationProvider(
            destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.xm")
        )
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let missingDocument = ExportXMDocumentContext.none(isPlaybackActive: false)
        let missingEditableDocument = ExportXMDocumentContext.editable(
            document: nil,
            displayName: "Untitled",
            isPlaybackActive: false
        )
        let invalidEditable = ExportXMDocumentContext.editable(
            document: document,
            displayName: "Untitled",
            isPlaybackActive: false,
            hasValidEditableState: false
        )

        XCTAssertFalse(ExportXMCoordinator.canExport(context: missingDocument))
        XCTAssertEqual(coordinator.beginExport(context: missingDocument), .unavailable(.noDocument))
        XCTAssertFalse(ExportXMCoordinator.canExport(context: missingEditableDocument))
        XCTAssertEqual(
            coordinator.beginExport(context: missingEditableDocument),
            .unavailable(.invalidEditableDocumentState)
        )
        XCTAssertFalse(ExportXMCoordinator.canExport(context: invalidEditable))
        XCTAssertEqual(coordinator.beginExport(context: invalidEditable), .unavailable(.invalidEditableDocumentState))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testWriterFailureReturnsFailureWithoutWritingFile() throws {
        let pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)
        let document = makeDocument(
            orderTable: Array(repeating: 0, count: 257),
            patterns: [pattern]
        )
        let destination = try temporaryDestination(filename: "writer-failure.xm")
        let provider = FakeExportXMDestinationProvider(destination: destination)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        guard case let .failed(.writerFailed(message)) = result else {
            return XCTFail("Expected writer failure, got \(result)")
        }
        XCTAssertTrue(message.contains("unsupportedOrderLength"))
        XCTAssertEqual(result.userFacingTitle, "Export XM Failed")
        XCTAssertTrue(result.userFacingMessage?.contains("Could not build XM data.") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnsupportedSamplePayloadFailureReturnsWriterFailureWithoutWritingFile() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0, 0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, samples: [sample])
            ]
        )
        let destination = try temporaryDestination(filename: "unsupported-sample.xm")
        let provider = FakeExportXMDestinationProvider(destination: destination)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        guard case let .failed(.writerFailed(message)) = result else {
            return XCTFail("Expected writer failure, got \(result)")
        }
        XCTAssertTrue(message.contains("unsupportedSampleSourceMetadata"))
        XCTAssertEqual(result.userFacingTitle, "Export XM Failed")
        XCTAssertTrue(result.userFacingMessage?.contains("Could not build XM data.") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFileWriteFailureReturnsFailureWithoutCreatingFile() throws {
        let document = BlankTrackerDocument.makeDefault()
        let destination = try temporaryDestinationInMissingDirectory(filename: "write-failure.xm")
        let provider = FakeExportXMDestinationProvider(destination: destination)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        guard case let .failed(.fileWriteFailed(message)) = result else {
            return XCTFail("Expected file write failure, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(result.userFacingTitle, "Export XM Failed")
        XCTAssertTrue(result.userFacingMessage?.contains("Could not write XM file.") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDefaultFilenameUsesXMExtensionAndSanitizesDocumentDisplayName() {
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: nil), "Untitled.xm")
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: "  Demo Song  "), "Demo Song.xm")
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: "already.xm"), "already.xm")
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: "bad/name:demo"), "bad-name-demo.xm")
        XCTAssertEqual(
            ExportXMCoordinator.normalizedXMURL(URL(fileURLWithPath: "/tmp/demo")).path,
            "/tmp/demo.xm"
        )
        XCTAssertEqual(
            ExportXMCoordinator.normalizedXMURL(URL(fileURLWithPath: "/tmp/demo.xm")).path,
            "/tmp/demo.xm"
        )
    }

    private func makeDocument(
        title: String = BlankTrackerDocument.defaultTitle,
        currentPatternIndex: Int = BlankTrackerDocument.defaultPatternIndex,
        restartPosition: Int = BlankTrackerDocument.defaultRestartPosition,
        tempo: Int = BlankTrackerDocument.defaultTempo,
        speed: Int = BlankTrackerDocument.defaultSpeed,
        orderTable: [Int],
        patterns: [XMPatternData],
        instrumentPalette: [Int: PlaybackInstrument] = [:]
    ) -> BlankTrackerDocument {
        BlankTrackerDocument(
            title: title,
            songLength: orderTable.count,
            currentPosition: 0,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: .default,
            instrumentPalette: instrumentPalette,
            patterns: patterns
        )
    }

    private func temporaryDestination(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(filename)
    }

    private func temporaryDestinationInMissingDirectory(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent(filename)
    }
}

@MainActor
private final class FakeExportXMDestinationProvider: ExportXMDestinationProviding {
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
