import AVFoundation
import XCTest

@MainActor
final class M4AExportCoordinatorTests: XCTestCase {
    func testPlanSharesProductWAVRenderPolicyAndUsesDefaultAACSettings() throws {
        let context = M4AExportDocumentContext.loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Plan Demo",
            isPlaybackActive: false
        )

        let plan = try M4AExportCoordinator.makePlan(context: context)
        let profile = AudioExportRenderProfile.productWAVExport

        XCTAssertEqual(plan.renderPlan.configuration, WAVExportCoordinator.defaultConfiguration)
        XCTAssertEqual(plan.renderPlan.request.config.sampleRate, profile.sampleRate)
        XCTAssertEqual(plan.renderPlan.request.config.channelCount, profile.channelCount)
        XCTAssertEqual(plan.renderPlan.request.config.mixProfile, .vtx)
        XCTAssertEqual(plan.renderPlan.configuration.tailSeconds, 3)
        XCTAssertEqual(plan.renderPlan.configuration.windowRows, 64)
        XCTAssertEqual(plan.renderPlan.configuration.headroomPolicy, .auto)
        XCTAssertEqual(plan.renderPlan.configuration.longRenderPolicy, .allowUserInitiatedWholeSong)
        XCTAssertEqual(plan.encoderConfiguration.sampleRate, 48_000)
        XCTAssertEqual(plan.encoderConfiguration.channelCount, 2)
        XCTAssertEqual(plan.encoderConfiguration.bitRate, 192_000)
        XCTAssertEqual(plan.suggestedFilename, "Plan Demo.m4a")
    }

    func testGatingMatchesWAVForNoDocumentPlaybackLoadedAndEditableContexts() {
        let song = makeSampleBearingSong()
        let editable = BlankTrackerDocument.makeDefault()

        XCTAssertFalse(M4AExportCoordinator.canExport(context: .none(isPlaybackActive: false)))
        XCTAssertFalse(M4AExportCoordinator.canExport(context: .loadedReadOnly(
            playbackSong: song,
            displayName: "Playing",
            isPlaybackActive: true
        )))
        XCTAssertFalse(M4AExportCoordinator.canExport(context: .loadedReadOnly(
            playbackSong: nil,
            displayName: "Missing",
            isPlaybackActive: false
        )))
        XCTAssertTrue(M4AExportCoordinator.canExport(context: .loadedReadOnly(
            playbackSong: song,
            displayName: "Loaded",
            isPlaybackActive: false
        )))
        XCTAssertTrue(M4AExportCoordinator.canExport(context: .editable(
            document: editable,
            displayName: editable.title,
            isPlaybackActive: false
        )))
    }

    func testLoadedExportWritesOnlySelectedM4ADestinationAndLeavesSourceUntouched() throws {
        let directory = try temporaryDirectory()
        let sourceURL = directory.appendingPathComponent("source-sentinel.xm")
        let sourceData = Data("read-only source sentinel".utf8)
        try sourceData.write(to: sourceURL)
        let selectedURL = directory.appendingPathComponent("shared-audio")
        let expectedURL = selectedURL.appendingPathExtension("m4a")
        let provider = FakeM4AExportDestinationProvider(destination: selectedURL)
        let coordinator = M4AExportCoordinator(destinationProvider: provider)

        let start = coordinator.beginExport(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Share Demo",
            isPlaybackActive: false
        ))
        guard case let .ready(plan, destination) = start else {
            return XCTFail("Expected ready M4A export, got \(start)")
        }
        XCTAssertEqual(provider.requests, [M4AExportDestinationRequest(suggestedFilename: "Share Demo.m4a")])
        XCTAssertEqual(destination, expectedURL)

        let completion = M4AExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(exportedURL, renderResult, encodingResult) = completion else {
            return XCTFail("Expected exported M4A result, got \(completion)")
        }
        XCTAssertEqual(exportedURL, expectedURL)
        XCTAssertEqual(renderResult.renderedFrameCount, plan.renderPlan.totalFrameCount)
        XCTAssertEqual(renderResult.exportDiagnostics?.autoHeadroomEnabled, true)
        XCTAssertEqual(encodingResult.sourceFrameCount, plan.renderPlan.totalFrameCount)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedURL.path))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), [
            sourceURL.lastPathComponent,
            expectedURL.lastPathComponent,
        ])
        XCTAssertEqual(completion.userFacingTitle, "Export Audio Completed")
        XCTAssertEqual(completion.userFacingMessage, "M4A file saved successfully.")
    }

    func testEditableExportDoesNotMutateDocument() throws {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.generateSineInSelectedEmptySample())
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let original = document
        let destination = try temporaryDirectory().appendingPathComponent("editable.m4a")
        let plan = try M4AExportCoordinator.makePlan(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        let completion = M4AExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(_, renderResult, _) = completion else {
            return XCTFail("Expected editable M4A export, got \(completion)")
        }
        XCTAssertEqual(document, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertGreaterThan(renderResult.exportDiagnostics?.preExportPeak ?? 0, 0)
    }

    func testProgressOrderingIncludesRenderHeadroomEncodingWritingAndCompletion() throws {
        let destination = try temporaryDirectory().appendingPathComponent("progress.m4a")
        let plan = try M4AExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Progress",
            isPlaybackActive: false
        ))
        let recorder = M4AProgressRecorder()

        let completion = M4AExportCoordinator.export(plan: plan, to: destination) {
            recorder.append($0)
        }
        guard case .exported = completion else {
            return XCTFail("Expected exported result, got \(completion)")
        }
        let events = recorder.events
        let stages = events.map(\.stage)
        XCTAssertEqual(stages.first, .preparingRender)
        XCTAssertTrue(events.first?.isIndeterminate == true)
        XCTAssertLessThan(try XCTUnwrap(stages.firstIndex(of: .preparingRender)), try XCTUnwrap(stages.firstIndex(of: .rendering)))
        XCTAssertLessThan(try XCTUnwrap(stages.firstIndex(of: .rendering)), try XCTUnwrap(stages.firstIndex(of: .applyingHeadroom)))
        XCTAssertLessThan(try XCTUnwrap(stages.firstIndex(of: .applyingHeadroom)), try XCTUnwrap(stages.firstIndex(of: .encoding)))
        XCTAssertLessThan(try XCTUnwrap(stages.firstIndex(of: .encoding)), try XCTUnwrap(stages.firstIndex(of: .writingFile)))
        XCTAssertEqual(stages.last, .completed)
        XCTAssertEqual(events.last?.fractionCompleted, 1)
        for (current, next) in zip(events.filter { !$0.isIndeterminate }, events.filter { !$0.isIndeterminate }.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.fractionCompleted, current.fractionCompleted)
        }
    }

    func testCancellationBeforeAndDuringRenderIsDistinctAndCleansTemporaryOutput() throws {
        for cancelDuringRender in [false, true] {
            let directory = try temporaryDirectory()
            let destination = directory.appendingPathComponent("cancel.m4a")
            let plan = try M4AExportCoordinator.makePlan(context: .loadedReadOnly(
                playbackSong: makeSampleBearingSong(),
                displayName: "Cancel",
                isPlaybackActive: false
            ))
            let token = M4AExportCancellationToken()
            if !cancelDuringRender {
                token.cancel()
            }

            let completion = M4AExportCoordinator.export(
                plan: plan,
                to: destination,
                cancellationToken: token
            ) { progress in
                if cancelDuringRender, progress.stage == .rendering, progress.completedWindows > 0 {
                    token.cancel()
                }
            }

            guard case .cancelled = completion else {
                return XCTFail("Expected cancellation, got \(completion)")
            }
            XCTAssertEqual(completion.userFacingTitle, "Export Audio Cancelled")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(try exportTemporaryFiles(in: directory).isEmpty)
        }
        guard case .failed = M4AExportCompletionResult.failed(.encodingFailed("failure")) else {
            return XCTFail("Failure must remain distinct from cancellation")
        }
    }

    func testCancellationDuringEncodingAndEncoderFailureRemovePartialOutput() throws {
        for shouldCancel in [true, false] {
            let directory = try temporaryDirectory()
            let destination = directory.appendingPathComponent("partial.m4a")
            let plan = try M4AExportCoordinator.makePlan(context: .loadedReadOnly(
                playbackSong: makeSampleBearingSong(),
                displayName: "Partial",
                isPlaybackActive: false
            ))
            let token = M4AExportCancellationToken()
            let encoder = PartialM4AAudioEncoder(shouldFail: !shouldCancel)

            let completion = M4AExportCoordinator.export(
                plan: plan,
                to: destination,
                cancellationToken: token,
                encoder: encoder
            ) { progress in
                if shouldCancel, progress.stage == .encoding, progress.completedFrames > 0 {
                    token.cancel()
                }
            }

            if shouldCancel {
                guard case .cancelled = completion else {
                    return XCTFail("Expected encoding cancellation, got \(completion)")
                }
            } else if case .failed(.encodingFailed) = completion {
                // Expected encoder failure.
            } else {
                return XCTFail("Expected encoding failure, got \(completion)")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertTrue(try exportTemporaryFiles(in: directory).isEmpty)
        }
    }

    func testAVFoundationEncoderWritesRecognizableAACM4AWithSaneDuration() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.wav")
        let destination = directory.appendingPathComponent("encoded.m4a")
        let expectedFrames = 12_000
        try writePublicSafeFloat32WAV(to: source, frameCount: expectedFrames)

        let result = try AVFoundationM4AAudioEncoder().encodeFloat32WAV(
            at: source,
            to: destination,
            configuration: .productDefault,
            cancellationCheck: {},
            progress: nil
        )

        let data = try Data(contentsOf: destination)
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data[4..<8], encoding: .ascii), "ftyp")
        let audioFile = try AVAudioFile(forReading: destination)
        XCTAssertEqual(audioFile.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(result.sourceFrameCount, expectedFrames)
        XCTAssertEqual(result.sampleRate, 48_000)
        XCTAssertEqual(result.channelCount, 2)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        XCTAssertEqual(duration, Double(expectedFrames) / 48_000, accuracy: 0.05)
    }

    func testAVFoundationEncoderCancellationCleansPartialFile() throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.wav")
        let destination = directory.appendingPathComponent("cancelled.m4a")
        try writePublicSafeFloat32WAV(to: source, frameCount: 24_000)
        let probe = ThrowingCancellationProbe(failOnCheck: 4)

        XCTAssertThrowsError(try AVFoundationM4AAudioEncoder().encodeFloat32WAV(
            at: source,
            to: destination,
            configuration: .productDefault,
            cancellationCheck: probe.check,
            progress: nil
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func makeSampleBearingSong() -> PlaybackSong {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, -0.25],
            baseSampleRate: 8_363
        )
        return makePlaybackSong(
            orderPatternIndices: [0],
            patternRowsByIndex: [0: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

@MainActor
private final class FakeM4AExportDestinationProvider: M4AExportDestinationProviding {
    let destination: URL?
    private(set) var requests = [M4AExportDestinationRequest]()

    init(destination: URL?) {
        self.destination = destination
    }

    func chooseM4AExportDestination(request: M4AExportDestinationRequest) -> URL? {
        requests.append(request)
        return destination
    }
}

private struct PartialM4AAudioEncoder: M4AAudioEncoding {
    enum Failure: Error { case expected }
    let shouldFail: Bool

    func encodeFloat32WAV(
        at sourceURL: URL,
        to destinationURL: URL,
        configuration: M4AAudioEncoderConfiguration,
        cancellationCheck: @Sendable () throws -> Void,
        progress: M4AAudioEncoderProgressHandler?
    ) throws -> M4AAudioEncodingResult {
        try Data("partial".utf8).write(to: destinationURL)
        progress?(M4AAudioEncoderProgress(completedFrames: 1, totalFrames: 2))
        try cancellationCheck()
        if shouldFail { throw Failure.expected }
        return M4AAudioEncodingResult(sourceFrameCount: 2, sampleRate: configuration.sampleRate, channelCount: configuration.channelCount)
    }
}

private final class M4AProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [M4AExportProgress]()
    var events: [M4AExportProgress] { lock.withLock { storage } }
    func append(_ progress: M4AExportProgress) { lock.withLock { storage.append(progress) } }
}

private final class ThrowingCancellationProbe: @unchecked Sendable {
    enum Failure: Error { case cancelled }
    private let lock = NSLock()
    private let failOnCheck: Int
    private var checkCount = 0

    init(failOnCheck: Int) {
        self.failOnCheck = failOnCheck
    }

    func check() throws {
        try lock.withLock {
            checkCount += 1
            if checkCount >= failOnCheck { throw Failure.cancelled }
        }
    }
}

private func writePublicSafeFloat32WAV(to url: URL, frameCount: Int) throws {
    var pcm = [Float]()
    pcm.reserveCapacity(frameCount * 2)
    for frame in 0..<frameCount {
        let sample = Float(sin((Double(frame) / 48_000) * 2 * .pi * 440) * 0.25)
        pcm.append(sample)
        pcm.append(sample)
    }
    let block = MixerRenderBlock(
        config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2),
        frameCount: frameCount,
        interleavedPCM: pcm
    )
    try MixerWAVExporter.float32WAVData(from: block).write(to: url)
}

private func exportTemporaryFiles(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".vtx-export-") }
}
