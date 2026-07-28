import Foundation
import XCTest

@MainActor
final class WAVExportCoordinatorTests: XCTestCase {
    func testDefaultConfigurationUsesSharedProductExportProfile() {
        let profile = AudioExportRenderProfile.productWAVExport
        let configuration = WAVExportCoordinator.defaultConfiguration

        XCTAssertEqual(profile.scope, .untilSongEnd)
        XCTAssertEqual(profile.sampleRate, 48_000)
        XCTAssertEqual(profile.wavFormat, .float32)
        XCTAssertEqual(profile.mixProfile, .vtx)
        XCTAssertEqual(profile.tailSeconds, 3)
        XCTAssertEqual(profile.windowRows, 64)
        XCTAssertTrue(profile.autoHeadroomEnabled)
        XCTAssertTrue(profile.allowLongRender)
        XCTAssertEqual(profile.maximumFrameCount, AudioExportRenderLimits.maximumFrameCount)
        XCTAssertEqual(profile.maximumFrameCount, 100_000_000)

        XCTAssertEqual(configuration.scope, .wholeSong)
        XCTAssertEqual(configuration.sampleRate, profile.sampleRate)
        XCTAssertEqual(configuration.channelCount, profile.channelCount)
        XCTAssertEqual(configuration.wavFormat, profile.wavFormat)
        XCTAssertEqual(configuration.mixProfile, profile.mixProfile)
        XCTAssertEqual(configuration.tailSeconds, profile.tailSeconds)
        XCTAssertEqual(configuration.chunkFrameCount, 48_000)
        XCTAssertEqual(configuration.windowRows, profile.windowRows)
        XCTAssertEqual(configuration.maximumFrameCount, profile.maximumFrameCount)
        XCTAssertEqual(configuration.longRenderPolicy, .allowUserInitiatedWholeSong)
        XCTAssertEqual(configuration.headroomPolicy, .auto)
    }

    func testProductExportFrameCountPreservesNearestRounding() {
        XCTAssertEqual(
            AudioExportFrameCount.frameCount(seconds: 0.015, sampleRate: 100),
            2
        )
        XCTAssertEqual(
            AudioExportFrameCount.frameCount(seconds: 3, sampleRate: 48_000),
            144_000
        )
        XCTAssertEqual(AudioExportFrameCount.frameCount(seconds: 0, sampleRate: 48_000), 0)
        XCTAssertEqual(AudioExportFrameCount.frameCount(seconds: .infinity, sampleRate: 48_000), 0)
    }

    func testLoadedStoppedRenderableSongWritesFloat32WAVOnlyToNormalizedDestination() throws {
        let song = makeSampleBearingSong()
        let selectedDestination = try temporaryDestination(filename: "loaded-export")
        let expectedDestination = WAVExportCoordinator.normalizedWAVURL(selectedDestination)
        let provider = FakeWAVExportDestinationProvider(destination: selectedDestination)
        let coordinator = WAVExportCoordinator(destinationProvider: provider)
        let context = WAVExportDocumentContext.loadedReadOnly(
            playbackSong: song,
            displayName: "Loaded Demo",
            isPlaybackActive: false
        )

        XCTAssertTrue(WAVExportCoordinator.canExport(context: context))
        let start = coordinator.beginExport(context: context)
        guard case let .ready(plan, destination) = start else {
            return XCTFail("Expected ready export, got \(start)")
        }
        XCTAssertEqual(provider.requests, [
            WAVExportDestinationRequest(suggestedFilename: "Loaded Demo.wav")
        ])
        XCTAssertEqual(destination, expectedDestination)
        XCTAssertEqual(plan.wavFormat, .float32)
        XCTAssertEqual(plan.request.config.mixProfile, .vtx)
        XCTAssertEqual(plan.configuration.scope, .wholeSong)
        XCTAssertEqual(plan.configuration.wavFormat, .float32)
        XCTAssertEqual(plan.configuration.longRenderPolicy, .allowUserInitiatedWholeSong)
        XCTAssertEqual(plan.configuration.headroomPolicy, .auto)
        XCTAssertEqual(plan.configuration.mixProfile, .vtx)
        XCTAssertEqual(plan.configuration.sampleRate, WAVExportCoordinator.sampleRate)
        XCTAssertEqual(plan.configuration.sampleRate, 48_000)
        XCTAssertEqual(plan.configuration.windowRows, 64)
        XCTAssertEqual(plan.tailFrameCount, RuntimeCMixerSongEndTailPolicy.defaultPolicy.tailFrames(
            sampleRate: WAVExportCoordinator.sampleRate
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(exportedDestination, renderResult) = completion else {
            return XCTFail("Expected exported result, got \(completion)")
        }
        XCTAssertEqual(exportedDestination, expectedDestination)
        XCTAssertEqual(completion.userFacingTitle, "Export Audio Completed")
        XCTAssertEqual(completion.userFacingMessage, "WAV file saved successfully.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectedDestination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: expectedDestination.deletingLastPathComponent().path), [
            expectedDestination.lastPathComponent
        ])
        XCTAssertEqual(renderResult.exportDiagnostics?.wavFormat, .float32)
        XCTAssertEqual(renderResult.exportDiagnostics?.autoHeadroomEnabled, true)

        let wav = try parseFloat32WAV(Data(contentsOf: expectedDestination))
        XCTAssertEqual(wav.formatCode, 3)
        XCTAssertEqual(wav.bitsPerSample, 32)
        XCTAssertEqual(wav.channelCount, UInt16(WAVExportCoordinator.channelCount))
        XCTAssertEqual(wav.sampleRate, UInt32(WAVExportCoordinator.sampleRate))
        XCTAssertEqual(wav.sampleRate, 48_000)
        XCTAssertEqual(wav.frameCount, plan.totalFrameCount)
        XCTAssertGreaterThan(wav.frameCount, 0)
    }

    func testEditableStoppedDocumentBuildsPlanWritesWAVAndDoesNotMutateDocument() throws {
        var document = makeSampleKeymapEditableDocument()
        document.pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        _ = try document.assignSample(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 48, upperNote: 48
        ).get()
        let originalDocument = document
        let destination = try temporaryDestination(filename: "editable.wav")
        let provider = FakeWAVExportDestinationProvider(destination: destination)
        let coordinator = WAVExportCoordinator(destinationProvider: provider)

        let start = coordinator.beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        guard case let .ready(plan, selectedDestination) = start else {
            return XCTFail("Expected ready export, got \(start)")
        }
        XCTAssertEqual(selectedDestination, destination)
        XCTAssertEqual(document, originalDocument)
        XCTAssertEqual(plan.request.song.instrument(forInstrument: 1)?.mappedSampleIndex(forNote: 49), 1)

        let completion = WAVExportCoordinator.export(plan: plan, to: selectedDestination)

        guard case let .exported(_, renderResult) = completion else {
            return XCTFail("Expected exported result, got \(completion)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(document, originalDocument)
        let data = try Data(contentsOf: destination)
        let wav = try parseFloat32WAV(data)
        XCTAssertEqual(wav.formatCode, 3)
        XCTAssertEqual(wav.bitsPerSample, 32)
        XCTAssertGreaterThan(renderResult.exportDiagnostics?.preExportPeak ?? 0, 0)
        XCTAssertGreaterThan(maxAbsFloat32Sample(
            in: data, channelCount: Int(wav.channelCount), sampleRate: Int(wav.sampleRate),
            fromSecond: 0, durationSeconds: 1
        ), 0)

        let repeatedDestination = try temporaryDestination(filename: "editable-repeat.wav")
        guard case let .exported(_, repeatedRenderResult) = WAVExportCoordinator.export(plan: plan, to: repeatedDestination) else {
            return XCTFail("Expected repeated exported result")
        }
        XCTAssertEqual(try Data(contentsOf: repeatedDestination), data)
        XCTAssertEqual(repeatedRenderResult.exportDiagnostics, renderResult.exportDiagnostics)
    }

    func testUnavailableStatesDoNotRequestDestination() {
        let song = makeSampleBearingSong()
        let provider = FakeWAVExportDestinationProvider(
            destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.wav")
        )
        let coordinator = WAVExportCoordinator(destinationProvider: provider)
        let noDocument = WAVExportDocumentContext.none(isPlaybackActive: false)
        let activePlayback = WAVExportDocumentContext.loadedReadOnly(
            playbackSong: song,
            displayName: "Playing",
            isPlaybackActive: true
        )
        let missingSong = WAVExportDocumentContext.loadedReadOnly(
            playbackSong: nil,
            displayName: "Missing",
            isPlaybackActive: false
        )

        XCTAssertFalse(WAVExportCoordinator.canExport(context: noDocument))
        XCTAssertEqual(coordinator.beginExport(context: noDocument).unavailableReason, .noDocument)
        XCTAssertFalse(WAVExportCoordinator.canExport(context: activePlayback))
        XCTAssertEqual(coordinator.beginExport(context: activePlayback).unavailableReason, .playbackActive)
        XCTAssertFalse(WAVExportCoordinator.canExport(context: missingSong))
        XCTAssertEqual(coordinator.beginExport(context: missingSong).unavailableReason, .noRenderableSong)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testCancelledDestinationSelectionWritesNothing() throws {
        let destination = try temporaryDestination(filename: "cancelled.wav")
        let provider = FakeWAVExportDestinationProvider(destination: nil)
        let coordinator = WAVExportCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Cancel Demo",
            isPlaybackActive: false
        ))

        XCTAssertEqual(result.cancelled, true)
        XCTAssertEqual(provider.requests, [
            WAVExportDestinationRequest(suggestedFilename: "Cancel Demo.wav")
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testProgressCallbacksUseIndeterminatePreparationThenDeterminatePipelineOrdering() throws {
        let destination = try temporaryDestination(filename: "progress.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeAppToolParitySong(),
            displayName: "Progress",
            isPlaybackActive: false
        ))
        let progressRecorder = TestWAVExportProgressRecorder()

        let completion = WAVExportCoordinator.export(plan: plan, to: destination) { progress in
            progressRecorder.append(progress)
        }
        let progressEvents = progressRecorder.events

        guard case .exported = completion else {
            return XCTFail("Expected exported result, got \(completion)")
        }
        XCTAssertEqual(progressEvents.first?.stage, .preparingRender)
        XCTAssertEqual(progressEvents.first?.isIndeterminate, true)
        XCTAssertEqual(progressEvents.filter { $0.stage == .preparingRender }.count, 1)
        XCTAssertTrue(progressEvents.contains { $0.stage == .rendering })
        XCTAssertTrue(progressEvents.contains { $0.stage == .applyingHeadroom })
        XCTAssertTrue(progressEvents.contains { $0.stage == .writingFile })
        XCTAssertEqual(progressEvents.last?.stage, .completed)
        XCTAssertEqual(progressEvents.last?.fractionCompleted, 1)
        let determinateProgress = progressEvents.filter { !$0.isIndeterminate }
        for (current, next) in zip(determinateProgress, determinateProgress.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.fractionCompleted, current.fractionCompleted)
        }
        XCTAssertTrue(
            progressEvents
                .filter { $0.stage == .rendering }
                .allSatisfy { !$0.isIndeterminate }
        )
        XCTAssertTrue(
            progressEvents
                .filter { $0.stage == .applyingHeadroom || $0.stage == .writingFile || $0.stage == .completed }
                .allSatisfy { !$0.isIndeterminate }
        )
        XCTAssertTrue(progressEvents.allSatisfy { $0.totalFrames == plan.totalFrameCount })
        XCTAssertTrue(progressEvents.allSatisfy { $0.totalWindows == plan.renderWindowCount })
        XCTAssertLessThan(
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .preparingRender)),
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .rendering))
        )
        let firstRenderingProgress = try XCTUnwrap(progressEvents.first { $0.stage == .rendering })
        XCTAssertEqual(firstRenderingProgress.completedWindows, 0)
        XCTAssertEqual(firstRenderingProgress.fractionCompleted, 0.05, accuracy: 0.000_001)
        XCTAssertLessThan(
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .rendering)),
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .applyingHeadroom))
        )
        XCTAssertLessThan(
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .applyingHeadroom)),
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .writingFile))
        )
        XCTAssertLessThan(
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .writingFile)),
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .completed))
        )
        let renderingProgress = progressEvents.filter { $0.stage == .rendering }
        let headroomProgress = progressEvents.filter { $0.stage == .applyingHeadroom }
        XCTAssertTrue(renderingProgress.allSatisfy {
            $0.fractionCompleted >= 0.05 && $0.fractionCompleted <= 0.850_001
        })
        XCTAssertEqual(try XCTUnwrap(headroomProgress.first).fractionCompleted, 0.85, accuracy: 0.000_001)
        XCTAssertTrue(headroomProgress.allSatisfy {
            $0.fractionCompleted >= 0.85 && $0.fractionCompleted <= 0.950_001
        })
        XCTAssertEqual(
            try XCTUnwrap(progressEvents.first { $0.stage == .writingFile }).fractionCompleted,
            0.95,
            accuracy: 0.000_001
        )
    }

    func testCancellationBeforeRenderReturnsCancelledAndCleansTemporaryFiles() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("cancel-before-render.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Cancel Before Render",
            isPlaybackActive: false
        ))
        let cancellationToken = WAVExportCancellationToken()
        let eventRecorder = TestWAVExportPipelineEventRecorder()
        cancellationToken.cancel()

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            cancellationToken: cancellationToken,
            pipelineEvents: { eventRecorder.append($0) }
        )

        guard case .cancelled = completion else {
            return XCTFail("Expected cancelled result, got \(completion)")
        }
        XCTAssertEqual(completion.userFacingTitle, "Export Audio Cancelled")
        XCTAssertEqual(completion.userFacingMessage, "WAV export was cancelled.")
        XCTAssertTrue(eventRecorder.events.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try exportTempFiles(in: directory).isEmpty)
    }

    func testCancellationDuringRenderWindowReturnsCancelledAfterProgressAndCleansTemporaryFiles() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("cancel-during-render.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingRepeatingOrderSong(orderCount: 3),
            displayName: "Cancel During Render",
            isPlaybackActive: false
        ))
        let cancellationToken = WAVExportCancellationToken()
        let progressRecorder = TestWAVExportProgressRecorder()

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            cancellationToken: cancellationToken
        ) { progress in
            progressRecorder.append(progress)
            if progress.stage == .rendering, progress.completedWindows > 0 {
                cancellationToken.cancel()
            }
        }

        guard case .cancelled = completion else {
            return XCTFail("Expected cancelled result, got \(completion)")
        }
        XCTAssertTrue(progressRecorder.events.contains {
            $0.stage == .rendering && $0.completedWindows > 0
        })
        XCTAssertFalse(progressRecorder.events.contains { $0.stage == .applyingHeadroom })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try exportTempFiles(in: directory).isEmpty)
    }

    func testCancellationDuringHeadroomReturnsCancelledAndCleansTemporaryFiles() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("cancel-during-headroom.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeHotSampleBearingSong(),
            displayName: "Cancel During Headroom",
            isPlaybackActive: false
        ))
        let cancellationToken = WAVExportCancellationToken()
        let progressRecorder = TestWAVExportProgressRecorder()

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            cancellationToken: cancellationToken
        ) { progress in
            progressRecorder.append(progress)
            if progress.stage == .applyingHeadroom, progress.completedFrames > 0 {
                cancellationToken.cancel()
            }
        }

        guard case .cancelled = completion else {
            return XCTFail("Expected cancelled result, got \(completion)")
        }
        XCTAssertTrue(progressRecorder.events.contains {
            $0.stage == .applyingHeadroom && $0.completedFrames > 0
        })
        XCTAssertFalse(progressRecorder.events.contains { $0.stage == .writingFile })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try exportTempFiles(in: directory).isEmpty)
    }

    func testCancellationAtFinalWriteCheckpointPreservesExistingDestination() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("existing.wav")
        let originalData = Data("existing destination".utf8)
        try originalData.write(to: destination)
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Cancel Before Replace",
            isPlaybackActive: false
        ))
        let cancellationToken = WAVExportCancellationToken()

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            cancellationToken: cancellationToken
        ) { progress in
            if progress.stage == .writingFile {
                cancellationToken.cancel()
            }
        }

        guard case .cancelled = completion else {
            return XCTFail("Expected cancelled result, got \(completion)")
        }
        XCTAssertEqual(try Data(contentsOf: destination), originalData)
        XCTAssertTrue(try exportTempFiles(in: directory).isEmpty)
    }

    func testCancellationResultIsDistinctFromFailure() {
        let cancelled = WAVExportCompletionResult.cancelled
        let failed = WAVExportCompletionResult.failed(.fileWriteFailed("failure"))

        guard case .cancelled = cancelled else {
            return XCTFail("Expected a dedicated cancellation result")
        }
        guard case .failed = failed else {
            return XCTFail("Expected failure to remain distinct from cancellation")
        }
        XCTAssertNil(cancelled.performanceSummary)
    }

    func testWholeSongExportLongerThanThirtySecondsIsNotTruncatedAndTailStartsAfterSongEnd() throws {
        let destination = try temporaryDestination(filename: "whole-song-longer-than-thirty.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeWholeSongLongerThanThirtySeconds(),
            displayName: "Whole Song",
            isPlaybackActive: false
        ))
        let thirtySecondFrames = Int(WAVExportCoordinator.sampleRate * 30)
        let progressRecorder = TestWAVExportProgressRecorder()

        XCTAssertGreaterThan(plan.songEndFrameCount, thirtySecondFrames)
        XCTAssertEqual(plan.totalFrameCount, plan.songEndFrameCount + plan.tailFrameCount)
        XCTAssertEqual(plan.tailFrameCount, RuntimeCMixerSongEndTailPolicy.defaultPolicy.tailFrames(
            sampleRate: WAVExportCoordinator.sampleRate
        ))
        XCTAssertEqual(plan.request.maximumFrameCount, plan.totalFrameCount)

        let completion = WAVExportCoordinator.export(plan: plan, to: destination) { progress in
            progressRecorder.append(progress)
        }

        guard case let .exported(_, renderResult) = completion else {
            return XCTFail("Expected long whole-song export, got \(completion)")
        }
        XCTAssertEqual(renderResult.renderedFrameCount, plan.totalFrameCount)
        let wav = try parseFloat32WAV(Data(contentsOf: destination))
        XCTAssertEqual(wav.frameCount, plan.totalFrameCount)
        XCTAssertGreaterThan(wav.frameCount, thirtySecondFrames)
        XCTAssertFalse(progressRecorder.events.isEmpty)
        XCTAssertTrue(progressRecorder.events.allSatisfy { $0.totalFrames == plan.totalFrameCount })
        XCTAssertEqual(progressRecorder.events.last?.completedFrames, plan.totalFrameCount)
    }

    func testUserInitiatedWholeSongPlanExplicitlyAllowsLongRenderBeyondDiagnosticClamp() throws {
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeWholeSongLongerThanSixtySeconds(),
            displayName: "Long Whole Song",
            isPlaybackActive: false
        ))

        XCTAssertGreaterThan(plan.totalFrameCount, PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount)
        XCTAssertEqual(plan.configuration.longRenderPolicy, .allowUserInitiatedWholeSong)
        XCTAssertEqual(plan.request.maximumFrameCount, plan.totalFrameCount)
    }

    func testAutoHeadroomPolicyIsAppliedAtFloat32WAVExportBoundary() throws {
        let destination = try temporaryDestination(filename: "auto-headroom.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeHotSampleBearingSong(),
            displayName: "Hot Song",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(_, renderResult) = completion,
              let diagnostics = renderResult.exportDiagnostics else {
            return XCTFail("Expected auto-headroom export, got \(completion)")
        }
        XCTAssertEqual(diagnostics.wavFormat, .float32)
        XCTAssertTrue(diagnostics.autoHeadroomEnabled)
        XCTAssertGreaterThan(diagnostics.preExportPeak, 1)
        XCTAssertLessThan(diagnostics.computedExportGain, 1)
        XCTAssertLessThanOrEqual(diagnostics.postGainPeak, 0.892)
        XCTAssertEqual(
            diagnostics.policy,
            MixerWAVExportPolicy.autoHeadroom(preExportPeak: diagnostics.preExportPeak)
        )
        let wavData = try Data(contentsOf: destination)
        let wav = try parseFloat32WAV(wavData)
        XCTAssertLessThanOrEqual(
            maxAbsFloat32Sample(
                in: wavData,
                channelCount: Int(wav.channelCount),
                sampleRate: Int(wav.sampleRate),
                fromSecond: 0,
                durationSeconds: Double(wav.frameCount) / Double(wav.sampleRate)
            ),
            0.892
        )
    }

    func testUnityGainAutoHeadroomSkipsRewriteAndPreservesPreHeadroomWAVBytes() throws {
        let destination = try temporaryDestination(filename: "unity-fast-path.wav")
        let song = makeSampleBearingSong()
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: song,
            displayName: "Unity Fast Path",
            isPlaybackActive: false
        ))
        let renderer = PlaybackSongOfflineRenderer(maximumFrameCount: plan.request.maximumFrameCount)
        let expectedRender = renderer.renderWindowed(
            plan.request,
            windowRows: plan.configuration.windowRows
        )
        let expectedBytes = try MixerWAVExporter.float32WAVData(
            from: expectedRender.block,
            exportPolicy: .unity
        )
        let eventRecorder = TestWAVExportPipelineEventRecorder()

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            pipelineEvents: { eventRecorder.append($0) }
        )

        guard case let .exported(_, renderResult) = completion,
              let diagnostics = renderResult.exportDiagnostics,
              let performance = renderResult.wavExportPerformanceDiagnostics else {
            return XCTFail("Expected unity-gain export, got \(completion)")
        }
        let finalBytes = try Data(contentsOf: destination)
        _ = try assertValidProductFloat32WAV(finalBytes, expectedFrameCount: plan.totalFrameCount)
        XCTAssertTrue(diagnostics.autoHeadroomEnabled)
        XCTAssertGreaterThan(diagnostics.preExportPeak, 0)
        XCTAssertLessThanOrEqual(diagnostics.preExportPeak, 1)
        XCTAssertEqual(diagnostics.computedExportGain, 1)
        XCTAssertEqual(eventRecorder.events.filter { $0 == .expensiveRenderStarted }.count, 1)
        XCTAssertEqual(eventRecorder.events.filter { $0 == .headroomPostProcessStarted }.count, 0)
        XCTAssertTrue(performance.usedUnityGainFastPath)
        XCTAssertEqual(performance.headroomPostProcessDurationSeconds, 0)
        let performanceSummary = try XCTUnwrap(completion.performanceSummary)
        XCTAssertEqual(performanceSummary.autoHeadroomGain, 1)
        XCTAssertTrue(performanceSummary.usedUnityGainFastPath)
        XCTAssertEqual(performanceSummary.headroomPostProcessDurationSeconds, 0)
        XCTAssertEqual(finalBytes, expectedBytes)
    }

    func testAutoHeadroomUsesOneExpensiveRenderAndOneFloat32PostProcess() throws {
        let destination = try temporaryDestination(filename: "single-render-auto-headroom.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeHotSampleBearingSong(),
            displayName: "Single Render",
            isPlaybackActive: false
        ))
        let eventRecorder = TestWAVExportPipelineEventRecorder()

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            pipelineEvents: { event in
                eventRecorder.append(event)
            }
        )

        guard case let .exported(_, renderResult) = completion else {
            return XCTFail("Expected single-render export, got \(completion)")
        }
        XCTAssertEqual(eventRecorder.events.filter { $0 == .expensiveRenderStarted }.count, 1)
        XCTAssertEqual(eventRecorder.events.filter { $0 == .headroomPostProcessStarted }.count, 1)
        XCTAssertEqual(renderResult.windowedRenderSummary?.windowRows, WAVExportCoordinator.defaultWindowRows)
        XCTAssertEqual(renderResult.exportDiagnostics?.autoHeadroomEnabled, true)
        XCTAssertEqual(renderResult.wavExportPerformanceDiagnostics?.usedUnityGainFastPath, false)
        let performanceSummary = try XCTUnwrap(completion.performanceSummary)
        XCTAssertLessThan(performanceSummary.autoHeadroomGain, 1)
        XCTAssertFalse(performanceSummary.usedUnityGainFastPath)
        XCTAssertGreaterThanOrEqual(performanceSummary.headroomPostProcessDurationSeconds, 0)
    }

    func testExportPerformanceDiagnosticsArePopulatedForWindowedFixture() throws {
        let destination = try temporaryDestination(filename: "performance-windowed.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingRepeatingOrderSong(orderCount: 3),
            displayName: "Performance",
            isPlaybackActive: false
        ))

        XCTAssertEqual(plan.renderWindowCount, 3)
        XCTAssertEqual(plan.performanceDiagnostics.renderWindowCount, 3)
        XCTAssertEqual(plan.performanceDiagnostics.totalFramesPlanned, plan.totalFrameCount)
        assertNonNegativePlanPerformance(plan.performanceDiagnostics)

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(_, renderResult) = completion,
              let summary = renderResult.windowedRenderSummary,
              let renderPerformance = renderResult.performanceDiagnostics,
              let exportPerformance = renderResult.wavExportPerformanceDiagnostics,
              let performanceSummary = completion.performanceSummary,
              let exportDiagnostics = renderResult.exportDiagnostics else {
            return XCTFail("Expected performance diagnostics, got \(completion)")
        }
        XCTAssertEqual(renderResult.renderedFrameCount, plan.totalFrameCount)
        XCTAssertEqual(summary.windowRows, WAVExportCoordinator.defaultWindowRows)
        XCTAssertEqual(summary.windowCount, 3)
        XCTAssertEqual(summary.windows.count, 3)
        XCTAssertEqual(renderPerformance.renderWindowCount, 3)
        XCTAssertEqual(renderPerformance.windowRows, WAVExportCoordinator.defaultWindowRows)
        XCTAssertEqual(renderPerformance.totalFramesPlanned, plan.totalFrameCount)
        XCTAssertEqual(renderPerformance.totalFramesRendered, plan.totalFrameCount)
        XCTAssertEqual(renderPerformance.windows.count, summary.windowCount)
        XCTAssertEqual(renderPerformance.totalScheduledEvents, summary.totalScheduledEvents)
        XCTAssertEqual(renderPerformance.totalAcceptedScheduledEvents, summary.totalAcceptedScheduledEvents)
        XCTAssertEqual(renderPerformance.totalRejectedScheduledEvents, summary.totalRejectedScheduledEvents)
        XCTAssertEqual(renderPerformance.totalScheduledCapacityRejects, summary.totalScheduledCapacityRejects)
        XCTAssertEqual(renderPerformance.totalCarriedVoices, summary.totalCarriedVoices)
        XCTAssertEqual(renderPerformance.totalBoundaryContinuations, summary.totalBoundaryContinuations)
        XCTAssertEqual(renderPerformance.totalDroppedAtWindowBoundaries, summary.totalDroppedAtWindowBoundaries)
        XCTAssertEqual(renderPerformance.mayContainBoundaryCuts, summary.mayContainBoundaryCuts)
        XCTAssertEqual(renderPerformance.cMixerVoiceAddCount, renderPerformance.totalAcceptedScheduledEvents)
        XCTAssertGreaterThan(renderPerformance.samplePayloadUploadCount, 0)
        XCTAssertGreaterThan(renderPerformance.approximateSamplePayloadBytesCopied, 0)
        XCTAssertGreaterThan(renderPerformance.uniqueSamplePayloadIdentityCount, 0)
        XCTAssertEqual(renderPerformance.samplePayloadUploadCount, renderPerformance.sharedSamplePayloadCreateCount)
        XCTAssertEqual(renderPerformance.approximateSamplePayloadBytesCopied, renderPerformance.sharedSamplePayloadBytesAllocated)
        XCTAssertEqual(renderPerformance.sharedSamplePayloadVoiceReferenceCount, renderPerformance.cMixerVoiceAddCount)
        XCTAssertEqual(
            renderPerformance.avoidedPerVoiceSamplePayloadUploadCount,
            renderPerformance.sharedSamplePayloadVoiceReferenceCount - renderPerformance.sharedSamplePayloadCreateCount
        )
        XCTAssertGreaterThan(renderPerformance.avoidedPerVoiceSamplePayloadUploadCount, 0)
        XCTAssertEqual(renderPerformance.preSanitizedBulkCopyUploadCount, renderPerformance.samplePayloadUploadCount)
        XCTAssertEqual(renderPerformance.defensiveSanitizingUploadCount, 0)
        XCTAssertEqual(exportPerformance.totalFramesPlanned, plan.totalFrameCount)
        XCTAssertEqual(exportPerformance.totalFramesRendered, plan.totalFrameCount)
        XCTAssertEqual(exportPerformance.renderWindowCount, summary.windowCount)
        XCTAssertEqual(exportPerformance.windowWriteDiagnostics.count, summary.windowCount)
        XCTAssertEqual(exportPerformance.renderPerformanceDiagnostics, renderPerformance)
        XCTAssertGreaterThanOrEqual(performanceSummary.totalDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(performanceSummary.planAndAdaptDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(performanceSummary.preparationIndexDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(performanceSummary.renderDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(performanceSummary.headroomPostProcessDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(performanceSummary.writeAndAtomicReplaceDurationSeconds, 0)
        XCTAssertEqual(
            performanceSummary.totalDurationSeconds,
            plan.performanceDiagnostics.totalDurationSeconds + exportPerformance.totalExportDurationSeconds
        )
        XCTAssertEqual(
            performanceSummary.planAndAdaptDurationSeconds,
            plan.performanceDiagnostics.totalDurationSeconds + renderPerformance.planAdaptDurationSeconds
        )
        XCTAssertEqual(
            performanceSummary.preparationIndexDurationSeconds,
            renderPerformance.windowedRenderIndexDiagnostics?.buildDurationSeconds
        )
        XCTAssertEqual(performanceSummary.renderDurationSeconds, exportPerformance.renderPhaseDurationSeconds)
        XCTAssertEqual(
            performanceSummary.writeAndAtomicReplaceDurationSeconds,
            exportPerformance.tempWAVWriteDurationSeconds + exportPerformance.finalAtomicReplaceDurationSeconds
        )
        XCTAssertGreaterThan(performanceSummary.renderWindowCount, 0)
        XCTAssertEqual(performanceSummary.renderWindowCount, summary.windowCount)
        XCTAssertEqual(performanceSummary.totalFramesPlanned, plan.totalFrameCount)
        XCTAssertEqual(performanceSummary.totalFramesRendered, plan.totalFrameCount)
        XCTAssertEqual(performanceSummary.scheduledEventCount, summary.totalScheduledEvents)
        XCTAssertEqual(performanceSummary.acceptedEventCount, summary.totalAcceptedScheduledEvents)
        XCTAssertEqual(performanceSummary.rejectedEventCount, summary.totalRejectedScheduledEvents)
        XCTAssertEqual(performanceSummary.carriedVoiceCount, summary.totalCarriedVoices)
        XCTAssertEqual(performanceSummary.boundaryDropCount, summary.totalDroppedAtWindowBoundaries)
        XCTAssertEqual(performanceSummary.mayContainBoundaryCuts, summary.mayContainBoundaryCuts)
        XCTAssertEqual(performanceSummary.sharedSamplePayloadCount, renderPerformance.sharedSamplePayloadCreateCount)
        XCTAssertEqual(performanceSummary.sharedSamplePayloadBytes, renderPerformance.sharedSamplePayloadBytesAllocated)
        XCTAssertEqual(
            performanceSummary.sharedSamplePayloadVoiceReferenceCount,
            renderPerformance.sharedSamplePayloadVoiceReferenceCount
        )
        XCTAssertGreaterThan(performanceSummary.sharedSamplePayloadCount, 0)
        XCTAssertGreaterThan(performanceSummary.sharedSamplePayloadBytes, 0)
        XCTAssertGreaterThan(performanceSummary.sharedSamplePayloadVoiceReferenceCount, 0)
        XCTAssertEqual(
            performanceSummary.avoidedSamplePayloadUploadCount,
            renderPerformance.avoidedPerVoiceSamplePayloadUploadCount
        )
        XCTAssertEqual(
            performanceSummary.avoidedSamplePayloadUploadBytes,
            renderPerformance.approximateAvoidedPerVoiceSamplePayloadUploadBytes
        )
        XCTAssertGreaterThan(performanceSummary.avoidedSamplePayloadUploadCount, 0)
        XCTAssertEqual(performanceSummary.fallbackCopiedSamplePayloadUploadCount, 0)
        XCTAssertEqual(performanceSummary.fallbackCopiedSamplePayloadUploadBytes, 0)
        XCTAssertEqual(performanceSummary.uploadCopyMode, .sharedCPayload)
        XCTAssertEqual(performanceSummary.autoHeadroomGain, exportDiagnostics.computedExportGain)
        XCTAssertEqual(performanceSummary.usedUnityGainFastPath, exportPerformance.usedUnityGainFastPath)
        assertNonNegativeRenderPerformance(renderPerformance)
        assertNonNegativeExportPerformance(exportPerformance)
    }

    func testExportPerformanceInstrumentationDoesNotChangeFloat32WAVBytes() throws {
        let enabledDestination = try temporaryDestination(filename: "instrumented.wav")
        let disabledDestination = try temporaryDestination(filename: "baseline.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeHotSampleBearingSong(),
            displayName: "Byte Identity",
            isPlaybackActive: false
        ))

        let enabled = WAVExportCoordinator.export(
            plan: plan,
            to: enabledDestination,
            collectPerformanceDiagnostics: true
        )
        let disabled = WAVExportCoordinator.export(
            plan: plan,
            to: disabledDestination,
            collectPerformanceDiagnostics: false
        )

        guard case let .exported(_, enabledResult) = enabled,
              case let .exported(_, disabledResult) = disabled else {
            return XCTFail("Expected two successful exports, got \(enabled) and \(disabled)")
        }
        XCTAssertNotNil(enabledResult.wavExportPerformanceDiagnostics)
        XCTAssertNotNil(enabledResult.performanceDiagnostics)
        XCTAssertNil(disabledResult.wavExportPerformanceDiagnostics)
        XCTAssertNil(disabledResult.performanceDiagnostics)
        XCTAssertNotNil(enabled.performanceSummary)
        XCTAssertNil(disabled.performanceSummary)
        XCTAssertEqual(try Data(contentsOf: enabledDestination), try Data(contentsOf: disabledDestination))
    }

    func testPerformanceSummaryFormattingIsConciseAndDoesNotIncludeLocalExportContext() throws {
        let destination = try temporaryDestination(filename: "summary-output.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingRepeatingOrderSong(orderCount: 3),
            displayName: "Local Summary Fixture",
            isPlaybackActive: false
        ))
        let completion = WAVExportCoordinator.export(plan: plan, to: destination)
        let performanceSummary = try XCTUnwrap(completion.performanceSummary)

        let line = WAVExportPerformanceSummaryFormatter.line(for: performanceSummary)

        XCTAssertTrue(line.hasPrefix("vtx_wav_export_performance_summary schema=1 "))
        XCTAssertTrue(line.contains("upload_copy_mode=shared_c_payload"))
        XCTAssertTrue(line.contains("unity_fast_path="))
        XCTAssertFalse(line.contains(destination.path))
        XCTAssertFalse(line.contains(destination.lastPathComponent))
        XCTAssertFalse(line.contains("Local Summary Fixture"))
        let absoluteHomeMarker = ["", "Users", "example"].joined(separator: "/")
        let desktopMarker = ["Desk", "top"].joined()
        XCTAssertFalse(line.contains(absoluteHomeMarker))
        XCTAssertFalse(line.localizedCaseInsensitiveContains(desktopMarker))
    }

    func testPerformanceSummaryLoggingIsOffByDefaultAndEnabledOnlyByExplicitEnvironmentFlag() throws {
        let destination = try temporaryDestination(filename: "summary-log-output.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Summary Logging",
            isPlaybackActive: false
        ))
        let completion = WAVExportCoordinator.export(plan: plan, to: destination)
        let sink = TestWAVExportPerformanceSummarySink()

        XCTAssertFalse(WAVExportPerformanceSummaryLogger.isEnabled(environment: [:]))
        XCTAssertFalse(WAVExportPerformanceSummaryLogger.isEnabled(environment: [
            WAVExportPerformanceSummaryLogger.enabledEnvironmentKey: "0",
        ]))
        XCTAssertFalse(WAVExportPerformanceSummaryLogger.isEnabled(environment: [
            WAVExportPerformanceSummaryLogger.enabledEnvironmentKey: "unexpected",
        ]))
        WAVExportPerformanceSummaryLogger.writeIfEnabled(
            completion,
            environment: [:],
            sink: sink
        )
        XCTAssertTrue(sink.lines.isEmpty)

        WAVExportPerformanceSummaryLogger.writeIfEnabled(
            completion,
            environment: [WAVExportPerformanceSummaryLogger.enabledEnvironmentKey: "1"],
            sink: sink
        )

        XCTAssertEqual(sink.lines.count, 1)
        XCTAssertEqual(
            sink.lines.first,
            completion.performanceSummary.map(WAVExportPerformanceSummaryFormatter.line(for:))
        )
        for enabledValue in ["true", "YES", "on"] {
            XCTAssertTrue(WAVExportPerformanceSummaryLogger.isEnabled(environment: [
                WAVExportPerformanceSummaryLogger.enabledEnvironmentKey: enabledValue,
            ]))
        }
    }

    func testAppExportFloat32WAVBytesMatchToolEquivalentWindowedRender() throws {
        let appDestination = try temporaryDestination(filename: "app-parity.wav")
        let referenceDestination = try temporaryDestination(filename: "tool-equivalent-parity.wav")
        let unityDestination = try temporaryDestination(filename: "unity-policy-parity.wav")
        let song = makeAppToolParitySong()
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: song,
            displayName: "App Tool Parity",
            isPlaybackActive: false
        ))

        XCTAssertEqual(plan.configuration.sampleRate, 48_000)
        XCTAssertEqual(plan.configuration.wavFormat, .float32)
        XCTAssertEqual(plan.configuration.mixProfile, .vtx)
        XCTAssertEqual(plan.configuration.windowRows, 64)
        XCTAssertEqual(plan.configuration.headroomPolicy, .auto)
        XCTAssertEqual(plan.configuration.longRenderPolicy, .allowUserInitiatedWholeSong)
        XCTAssertEqual(plan.tailFrameCount, RuntimeCMixerSongEndTailPolicy.defaultPolicy.tailFrames(
            sampleRate: WAVExportCoordinator.sampleRate
        ))
        XCTAssertGreaterThan(plan.renderWindowCount, 1)

        let appCompletion = WAVExportCoordinator.export(plan: plan, to: appDestination)
        guard case let .exported(_, appRenderResult) = appCompletion else {
            return XCTFail("Expected app export, got \(appCompletion)")
        }

        let renderer = PlaybackSongOfflineRenderer(maximumFrameCount: plan.request.maximumFrameCount)
        let referenceRenderResult = renderer.renderWindowed(plan.request, windowRows: 64)
        let referencePolicy = MixerWAVExportPolicy.autoHeadroom(for: referenceRenderResult.block)
        let referenceDiagnostics = try MixerWAVExporter.writeWAV(
            from: referenceRenderResult.block,
            to: referenceDestination,
            format: .float32,
            exportPolicy: referencePolicy
        )
        try MixerWAVExporter.writeWAV(
            from: referenceRenderResult.block,
            to: unityDestination,
            format: .float32,
            exportPolicy: .unity
        )

        let appSummary = try XCTUnwrap(appRenderResult.windowedRenderSummary)
        let appPerformance = try XCTUnwrap(appRenderResult.performanceDiagnostics)
        let indexDiagnostics = try XCTUnwrap(appPerformance.windowedRenderIndexDiagnostics)
        let referenceSummary = try XCTUnwrap(referenceRenderResult.windowedRenderSummary)
        XCTAssertEqual(appRenderResult.renderedFrameCount, plan.totalFrameCount)
        XCTAssertEqual(referenceRenderResult.renderedFrameCount, plan.totalFrameCount)
        XCTAssertEqual(appSummary.windowRows, 64)
        XCTAssertEqual(referenceSummary.windowRows, 64)
        XCTAssertGreaterThan(appSummary.windowCount, 1)
        XCTAssertEqual(appSummary.windowCount, referenceSummary.windowCount)
        XCTAssertGreaterThan(appSummary.totalScheduledEvents, 1)
        XCTAssertGreaterThan(appSummary.totalBoundaryContinuations, 0)
        XCTAssertEqual(appSummary.totalScheduledCapacityRejects, 0)
        XCTAssertTrue(appPerformance.usedPreindexedWindowScheduling)
        XCTAssertEqual(appPerformance.preindexedWindowSchedulingConsumedWindowCount, appSummary.windowCount)
        XCTAssertEqual(indexDiagnostics.indexedWindowCount, appSummary.windowCount)
        XCTAssertGreaterThan(indexDiagnostics.buildDurationSeconds, 0)

        let firstBoundaryFrame = try XCTUnwrap(appSummary.windows.dropFirst().first?.startFrame)
        XCTAssertGreaterThan(firstBoundaryFrame, 0)
        let appBytes = try Data(contentsOf: appDestination)
        let referenceBytes = try Data(contentsOf: referenceDestination)
        let unityBytes = try Data(contentsOf: unityDestination)
        let appWAV = try assertValidProductFloat32WAV(appBytes, expectedFrameCount: plan.totalFrameCount)
        _ = try assertValidProductFloat32WAV(referenceBytes, expectedFrameCount: plan.totalFrameCount)

        XCTAssertGreaterThan(appBytes.count, 44)
        XCTAssertGreaterThan(referenceBytes.count, 44)
        XCTAssertEqual(appRenderResult.exportDiagnostics?.wavFormat, .float32)
        XCTAssertTrue(appRenderResult.exportDiagnostics?.autoHeadroomEnabled ?? false)
        XCTAssertEqual(appRenderResult.exportDiagnostics?.preExportPeak, referenceDiagnostics.preExportPeak)
        XCTAssertEqual(appRenderResult.exportDiagnostics?.computedExportGain, referenceDiagnostics.computedExportGain)
        XCTAssertGreaterThan(referenceDiagnostics.preExportPeak, 1)
        XCTAssertLessThan(referenceDiagnostics.computedExportGain, 1)
        XCTAssertGreaterThan(
            maxAbsFloat32Sample(in: appBytes, channelCount: Int(appWAV.channelCount), sampleRate: Int(appWAV.sampleRate), fromSecond: 0, durationSeconds: 2),
            0.001
        )
        XCTAssertGreaterThan(
            maxAbsFloat32Sample(
                in: appBytes,
                channelCount: Int(appWAV.channelCount),
                sampleRate: Int(appWAV.sampleRate),
                fromSecond: Double(firstBoundaryFrame) / Double(appWAV.sampleRate),
                durationSeconds: 2
            ),
            0.001
        )
        XCTAssertEqual(appBytes, referenceBytes)
        XCTAssertNotEqual(appBytes, unityBytes)
    }

    func testHeadroomPostProcessPerformanceDiagnosticsArePresent() throws {
        let destination = try temporaryDestination(filename: "headroom-performance.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeHotSampleBearingSong(),
            displayName: "Headroom Performance",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(_, renderResult) = completion,
              let exportDiagnostics = renderResult.exportDiagnostics,
              let performance = renderResult.wavExportPerformanceDiagnostics else {
            return XCTFail("Expected headroom performance diagnostics, got \(completion)")
        }
        XCTAssertTrue(exportDiagnostics.autoHeadroomEnabled)
        XCTAssertGreaterThan(exportDiagnostics.preExportPeak, 1)
        XCTAssertLessThan(exportDiagnostics.computedExportGain, 1)
        XCTAssertFalse(performance.usedUnityGainFastPath)
        XCTAssertGreaterThanOrEqual(performance.headroomPostProcessDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(performance.tempWAVWriteDurationSeconds, 0)
        XCTAssertEqual(performance.windowWriteDiagnostics.count, renderResult.windowedRenderSummary?.windowCount)
    }

    func testWindowedExportContainsNonSilentAudioAfterThirtyFiveSeconds() throws {
        let destination = try temporaryDestination(filename: "late-audio.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeManyEventSongWithContentBeyondThirtySeconds(),
            displayName: "Late Audio",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(_, renderResult) = completion else {
            return XCTFail("Expected late-audio export, got \(completion)")
        }
        XCTAssertEqual(renderResult.renderedFrameCount, plan.totalFrameCount)
        XCTAssertEqual(renderResult.windowedRenderSummary?.windowRows, WAVExportCoordinator.defaultWindowRows)
        XCTAssertGreaterThan(renderResult.windowedRenderSummary?.windows.count ?? 0, 1)
        XCTAssertEqual(renderResult.windowedRenderSummary?.totalScheduledCapacityRejects, 0)

        let wavData = try Data(contentsOf: destination)
        let wav = try parseFloat32WAV(wavData)
        XCTAssertGreaterThan(wav.frameCount, Int(45 * WAVExportCoordinator.sampleRate))
        XCTAssertGreaterThan(
            maxAbsFloat32Sample(in: wavData, channelCount: Int(wav.channelCount), sampleRate: Int(wav.sampleRate), fromSecond: 35, durationSeconds: 2),
            0.001
        )
    }

    func testWindowedExportContainsNonSilentAudioBeforeAndAfterThirtySeconds() throws {
        let destination = try temporaryDestination(filename: "before-after-thirty.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeManyEventSongWithContentBeyondThirtySeconds(),
            displayName: "Before After",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case .exported = completion else {
            return XCTFail("Expected before/after export, got \(completion)")
        }
        let wavData = try Data(contentsOf: destination)
        let wav = try parseFloat32WAV(wavData)
        XCTAssertGreaterThan(
            maxAbsFloat32Sample(in: wavData, channelCount: Int(wav.channelCount), sampleRate: Int(wav.sampleRate), fromSecond: 10, durationSeconds: 2),
            0.001
        )
        XCTAssertGreaterThan(
            maxAbsFloat32Sample(in: wavData, channelCount: Int(wav.channelCount), sampleRate: Int(wav.sampleRate), fromSecond: 42, durationSeconds: 2),
            0.001
        )
        XCTAssertEqual(wav.frameCount, plan.totalFrameCount)
    }

    func testTailRegionIsSilentAfterFiniteNonLoopingSongEnd() throws {
        let destination = try temporaryDestination(filename: "tail-after-song-end.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeManyEventSongWithContentBeyondThirtySeconds(),
            displayName: "Tail",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case .exported = completion else {
            return XCTFail("Expected tail export, got \(completion)")
        }
        let wavData = try Data(contentsOf: destination)
        let wav = try parseFloat32WAV(wavData)
        let tailStartSecond = Double(plan.songEndFrameCount) / WAVExportCoordinator.sampleRate
        XCTAssertGreaterThan(
            maxAbsFloat32Sample(in: wavData, channelCount: Int(wav.channelCount), sampleRate: Int(wav.sampleRate), fromSecond: tailStartSecond - 1.0, durationSeconds: 0.5),
            0.001
        )
        XCTAssertLessThan(
            maxAbsFloat32Sample(in: wavData, channelCount: Int(wav.channelCount), sampleRate: Int(wav.sampleRate), fromSecond: tailStartSecond + 1.0, durationSeconds: 0.5),
            0.000_1
        )
    }

    func testNonDeterministicWholeSongTraversalFailsPlanInsteadOfExportingShortTail() {
        let loopingSong = makePlaybackSong(
            orderPatternIndices: [0, 1],
            patternRowsByIndex: [
                0: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, effectType: 0x0B, effectParam: 0),
                ],
                1: [makePlaybackRow(index: 0)],
            ],
            initialTiming: PlaybackTiming(speed: 6, bpm: 125)
        )

        XCTAssertThrowsError(try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: loopingSong,
            displayName: "Loop",
            isPlaybackActive: false
        ))) { error in
            guard case .renderDurationNotDeterministic = error as? WAVExportPlanError else {
                return XCTFail("Expected non-deterministic duration error, got \(error)")
            }
        }
    }

    func testLongerLoadedStyleExportRunsOnBackgroundQueueAndWritesValidFloat32WAV() throws {
        let destination = try temporaryDestination(filename: "background-longer.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeLongerSampleBearingSong(),
            displayName: "Background Longer",
            isPlaybackActive: false
        ))
        let progressRecorder = TestWAVExportProgressRecorder()
        let expectation = expectation(description: "background WAV export completes")
        let resultBox = TestWAVExportCompletionBox()

        DispatchQueue.global(qos: .userInitiated).async {
            let completion = WAVExportCoordinator.export(plan: plan, to: destination) { progress in
                progressRecorder.append(progress)
            }
            resultBox.store(completion)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
        guard case let .exported(exportedDestination, renderResult) = resultBox.result else {
            return XCTFail("Expected background export, got \(String(describing: resultBox.result))")
        }
        XCTAssertEqual(exportedDestination, destination)
        XCTAssertEqual(renderResult.renderedFrameCount, plan.totalFrameCount)
        XCTAssertEqual(renderResult.exportDiagnostics?.wavFormat, .float32)

        let wav = try parseFloat32WAV(Data(contentsOf: destination))
        XCTAssertEqual(wav.formatCode, 3)
        XCTAssertEqual(wav.bitsPerSample, 32)
        XCTAssertEqual(wav.frameCount, plan.totalFrameCount)
        XCTAssertGreaterThan(progressRecorder.events.filter { $0.stage == .rendering }.count, 1)
        XCTAssertTrue(progressRecorder.events.contains { $0.stage == .applyingHeadroom })
    }

    func testPlanCapturesImmutablePlaybackSongSnapshotForBackgroundExport() throws {
        var sourceSong = makeLongerSampleBearingSong()
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: sourceSong,
            displayName: "Snapshot",
            isPlaybackActive: false
        ))
        sourceSong = makePlaybackSong(orderPatternIndices: [], patternRowCounts: [:])
        let destination = try temporaryDestination(filename: "snapshot.wav")

        let completion = WAVExportCoordinator.export(plan: plan, to: destination)

        guard case let .exported(_, renderResult) = completion else {
            return XCTFail("Expected snapshot export, got \(completion)")
        }
        XCTAssertTrue(sourceSong.orders.isEmpty)
        XCTAssertEqual(renderResult.request.song.orders.count, 16)
        XCTAssertEqual(renderResult.renderedFrameCount, plan.totalFrameCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testWAVLayoutValidationRejectsTooLargeFloat32Output() {
        let tooManyStereoFloat32Frames = Int(UInt32.max) / (
            WAVExportCoordinator.channelCount * WAVExportCoordinator.wavFormat.bytesPerSample
        ) + 1

        XCTAssertThrowsError(try WAVExportCoordinator.validatePlannedWAVLayout(
            config: MixerRenderConfig(
                sampleRate: WAVExportCoordinator.sampleRate,
                channelCount: WAVExportCoordinator.channelCount,
                mixProfile: WAVExportCoordinator.mixProfile
            ),
            frameCount: tooManyStereoFloat32Frames
        )) { error in
            XCTAssertEqual(error as? MixerWAVExportError, .fileTooLarge)
        }
    }

    func testWriteFailureRemovesTemporaryOutputAndReportsFailure() throws {
        let directory = try temporaryDirectory()
        let missingDestination = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("failure.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Failure",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(plan: plan, to: missingDestination)

        guard case let .failed(failure) = completion else {
            return XCTFail("Expected write failure, got \(completion)")
        }
        XCTAssertTrue(failure.userFacingMessage.contains("Could not write WAV file."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDestination.deletingLastPathComponent().path))
    }

    func testRenderFailureRemovesTemporaryOutputs() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("render-failure.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
            displayName: "Render Failure",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            executionHooks: WAVExportExecutionHooks(
                afterRenderBlockWritten: {
                    throw TestWAVExportInjectedError.renderFailure
                }
            )
        )

        guard case let .failed(failure) = completion else {
            return XCTFail("Expected render failure, got \(completion)")
        }
        XCTAssertTrue(failure.userFacingMessage.contains("Could not write WAV file."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try exportTempFiles(in: directory).isEmpty)
    }

    func testHeadroomPostProcessFailureRemovesTemporaryOutputs() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("postprocess-failure.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeHotSampleBearingSong(),
            displayName: "Postprocess Failure",
            isPlaybackActive: false
        ))

        let completion = WAVExportCoordinator.export(
            plan: plan,
            to: destination,
            executionHooks: WAVExportExecutionHooks(
                afterPostProcessChunkWritten: {
                    throw TestWAVExportInjectedError.postProcessFailure
                }
            )
        )

        guard case let .failed(failure) = completion else {
            return XCTFail("Expected postprocess failure, got \(completion)")
        }
        XCTAssertTrue(failure.userFacingMessage.contains("Could not write WAV file."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try exportTempFiles(in: directory).isEmpty)
    }

    func testDefaultFilenameUsesWAVExtensionAndSanitizesDisplayName() {
        XCTAssertEqual(WAVExportCoordinator.defaultFilename(displayName: nil), "Untitled.wav")
        XCTAssertEqual(WAVExportCoordinator.defaultFilename(displayName: "  Demo Song  "), "Demo Song.wav")
        XCTAssertEqual(WAVExportCoordinator.defaultFilename(displayName: "already.wav"), "already.wav")
        XCTAssertEqual(WAVExportCoordinator.defaultFilename(displayName: "bad/name:demo"), "bad-name-demo.wav")
        XCTAssertEqual(
            WAVExportCoordinator.normalizedWAVURL(URL(fileURLWithPath: "/tmp/demo")).path,
            "/tmp/demo.wav"
        )
        XCTAssertEqual(
            WAVExportCoordinator.normalizedWAVURL(URL(fileURLWithPath: "/tmp/demo.wav")).path,
            "/tmp/demo.wav"
        )
    }

    private func makeSampleBearingSong() -> PlaybackSong {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25], baseSampleRate: 8_363)
        return makePlaybackSong(
            orderPatternIndices: [0],
            patternRowsByIndex: [
                0: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
    }

    private func makeLongerSampleBearingSong() -> PlaybackSong {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(0.2), count: 2_048),
            baseSampleRate: 8_363
        )
        let rows = (0..<16).map { rowIndex in
            rowIndex == 0 || rowIndex == 8
                ? makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
                : makePlaybackRow(index: rowIndex)
        }
        return makePlaybackSong(
            orderPatternIndices: Array(repeating: 0, count: 16),
            patternRowsByIndex: [0: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 125)
        )
    }

    private func makeWholeSongLongerThanThirtySeconds() -> PlaybackSong {
        makeSampleBearingRepeatingOrderSong(orderCount: 5)
    }

    private func makeWholeSongLongerThanSixtySeconds() -> PlaybackSong {
        makeSampleBearingRepeatingOrderSong(orderCount: 9)
    }

    private func makeSampleBearingRepeatingOrderSong(orderCount: Int) -> PlaybackSong {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(0.15), count: 1_024),
            baseSampleRate: 8_363
        )
        let rows = (0..<64).map { rowIndex in
            rowIndex == 0
                ? makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
                : makePlaybackRow(index: rowIndex)
        }
        return makePlaybackSong(
            orderPatternIndices: Array(repeating: 0, count: orderCount),
            patternRowsByIndex: [0: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 125)
        )
    }

    private func makeHotSampleBearingSong() -> PlaybackSong {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(2.0), count: 2_048),
            baseSampleRate: 8_363
        )
        return makePlaybackSong(
            orderPatternIndices: [0],
            patternRowsByIndex: [
                0: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
    }

    private func makeManyEventSongWithContentBeyondThirtySeconds() -> PlaybackSong {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(0.6), count: 4_096),
            baseSampleRate: 8_363
        )
        let rows = (0..<64).map { rowIndex in
            makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
        }
        return makePlaybackSong(
            orderPatternIndices: Array(repeating: 0, count: 9),
            patternRowsByIndex: [0: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 125)
        )
    }

    private func makeAppToolParitySong() -> PlaybackSong {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [2.0, -1.5, 1.25, -2.0, 0.75, -0.5, 1.75, -1.25],
            volume: 1,
            baseSampleRate: 48_000,
            loopStart: 0,
            loopLength: 8,
            loopType: 1
        )
        let rows = (0..<64).map { rowIndex in
            rowIndex == 0 || rowIndex == 32
                ? makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
                : makePlaybackRow(index: rowIndex)
        }
        return makePlaybackSong(
            orderPatternIndices: Array(repeating: 0, count: 3),
            patternRowsByIndex: [0: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 125)
        )
    }

    private func temporaryDestination(filename: String) throws -> URL {
        try temporaryDirectory().appendingPathComponent(filename)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

@MainActor
private final class FakeWAVExportDestinationProvider: WAVExportDestinationProviding {
    private let destination: URL?
    private(set) var requests = [WAVExportDestinationRequest]()

    init(destination: URL?) {
        self.destination = destination
    }

    func chooseWAVExportDestination(request: WAVExportDestinationRequest) -> URL? {
        requests.append(request)
        return destination
    }
}

private extension WAVExportStartResult {
    var unavailableReason: WAVExportUnavailableReason? {
        if case let .unavailable(reason) = self {
            return reason
        }
        return nil
    }

    var cancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}

private struct TestFloat32WAV {
    let formatCode: UInt16
    let sampleRate: UInt32
    let channelCount: UInt16
    let bitsPerSample: UInt16
    let dataSize: UInt32

    var frameCount: Int {
        Int(dataSize) / Int(channelCount) / 4
    }
}

private func parseFloat32WAV(_ data: Data) throws -> TestFloat32WAV {
    guard data.count >= 44,
          Array(data[0..<4]) == Array("RIFF".utf8),
          Array(data[8..<12]) == Array("WAVE".utf8),
          Array(data[12..<16]) == Array("fmt ".utf8),
          readLE32(data, offset: 16) == 16,
          Array(data[36..<40]) == Array("data".utf8) else {
        throw TestWAVParseError.invalidData
    }

    let channelCount = readLE16(data, offset: 22)
    let bitsPerSample = readLE16(data, offset: 34)
    let dataSize = readLE32(data, offset: 40)
    guard channelCount > 0,
          bitsPerSample == 32,
          data.count == 44 + Int(dataSize),
          dataSize % UInt32(channelCount * 4) == 0 else {
        throw TestWAVParseError.invalidData
    }

    return TestFloat32WAV(
        formatCode: readLE16(data, offset: 20),
        sampleRate: readLE32(data, offset: 24),
        channelCount: channelCount,
        bitsPerSample: bitsPerSample,
        dataSize: dataSize
    )
}

private func assertValidProductFloat32WAV(
    _ data: Data,
    expectedFrameCount: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> TestFloat32WAV {
    let wav = try parseFloat32WAV(data)
    XCTAssertEqual(wav.formatCode, 3, file: file, line: line)
    XCTAssertEqual(wav.bitsPerSample, 32, file: file, line: line)
    XCTAssertEqual(wav.channelCount, UInt16(WAVExportCoordinator.channelCount), file: file, line: line)
    XCTAssertEqual(wav.sampleRate, UInt32(WAVExportCoordinator.sampleRate), file: file, line: line)
    XCTAssertEqual(wav.frameCount, expectedFrameCount, file: file, line: line)
    XCTAssertGreaterThan(wav.frameCount, 0, file: file, line: line)
    return wav
}

private func maxAbsFloat32Sample(
    in data: Data,
    channelCount: Int,
    sampleRate: Int,
    fromSecond: Double,
    durationSeconds: Double
) -> Float {
    let channelCount = max(1, channelCount)
    let sampleRate = max(1, sampleRate)
    let startFrame = max(0, Int((fromSecond * Double(sampleRate)).rounded(.down)))
    let frameCount = max(0, Int((durationSeconds * Double(sampleRate)).rounded(.down)))
    let startSample = startFrame * channelCount
    let endSample = min((data.count - 44) / 4, (startFrame + frameCount) * channelCount)
    guard endSample > startSample else {
        return 0
    }

    var peak = Float(0)
    for sampleIndex in startSample..<endSample {
        let offset = 44 + sampleIndex * 4
        let sample = Float(bitPattern: readLE32(data, offset: offset))
        if sample.isFinite {
            peak = max(peak, abs(sample))
        }
    }
    return peak
}

private func exportTempFiles(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.contains(".vtx-export-") || $0.hasSuffix(".tmp") }
        .sorted()
}

private func assertNonNegativePlanPerformance(
    _ diagnostics: WAVExportPlanPerformanceDiagnostics,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(diagnostics.totalDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.songBuildDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.traversalPlanningDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.durationTimingPlanningDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.wavLayoutValidationDurationSeconds, 0, file: file, line: line)
}

private func assertNonNegativeRenderPerformance(
    _ diagnostics: PlaybackSongRenderPerformanceDiagnostics,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(diagnostics.totalDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.planAdaptDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.totalWindowSchedulingDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.totalCMixerRenderDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.cMixerVoiceAddCount, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.samplePayloadUploadCount, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.approximateSamplePayloadBytesCopied, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.continuationSamplePayloadUploadCount, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.approximateContinuationSamplePayloadBytesCopied, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.continuationSharedSamplePayloadVoiceReferenceCount, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.duplicateSamplePayloadUploadCount, 0, file: file, line: line)
    for window in diagnostics.windows {
        XCTAssertGreaterThanOrEqual(window.schedulingDurationSeconds, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(window.cMixerRenderDurationSeconds, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(window.totalWindowDurationSeconds, 0, file: file, line: line)
    }
}

private func assertNonNegativeExportPerformance(
    _ diagnostics: WAVExportPerformanceDiagnostics,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(diagnostics.totalExportDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.renderPhaseDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.tempWAVWriteDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.headroomPostProcessDurationSeconds, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(diagnostics.finalAtomicReplaceDurationSeconds, 0, file: file, line: line)
    for window in diagnostics.windowWriteDiagnostics {
        XCTAssertGreaterThanOrEqual(window.tempWAVWriteDurationSeconds, 0, file: file, line: line)
    }
}

private enum TestWAVExportInjectedError: LocalizedError {
    case renderFailure
    case postProcessFailure

    var errorDescription: String? {
        switch self {
        case .renderFailure:
            return "Injected render failure."
        case .postProcessFailure:
            return "Injected post-process failure."
        }
    }
}

private final class TestWAVExportProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents = [WAVExportProgress]()

    var events: [WAVExportProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func append(_ progress: WAVExportProgress) {
        lock.lock()
        storedEvents.append(progress)
        lock.unlock()
    }
}

private final class TestWAVExportPipelineEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents = [WAVExportPipelineEvent]()

    var events: [WAVExportPipelineEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func append(_ event: WAVExportPipelineEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}

private final class TestWAVExportPerformanceSummarySink: WAVExportPerformanceSummarySinking, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLines = [String]()

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedLines
    }

    func writeWAVExportPerformanceSummaryLine(_ line: String) {
        lock.lock()
        storedLines.append(line)
        lock.unlock()
    }
}

private final class TestWAVExportCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: WAVExportCompletionResult?

    var result: WAVExportCompletionResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func store(_ result: WAVExportCompletionResult) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}
