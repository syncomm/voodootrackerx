import Foundation
import XCTest

@MainActor
final class WAVExportCoordinatorTests: XCTestCase {
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
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)
        pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25], baseSampleRate: 8_363)
        let document = BlankTrackerDocument(
            title: "Editable Demo",
            songLength: 1,
            currentPosition: 0,
            restartPosition: 0,
            currentPatternIndex: 0,
            tempo: 125,
            speed: 6,
            orderTable: [0],
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])],
            patterns: [pattern]
        )
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

        let completion = WAVExportCoordinator.export(plan: plan, to: selectedDestination)

        guard case .exported = completion else {
            return XCTFail("Expected exported result, got \(completion)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(document, originalDocument)
        let wav = try parseFloat32WAV(Data(contentsOf: destination))
        XCTAssertEqual(wav.formatCode, 3)
        XCTAssertEqual(wav.bitsPerSample, 32)
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

    func testProgressCallbacksRepresentRenderingWritingAndCompletion() throws {
        let destination = try temporaryDestination(filename: "progress.wav")
        let plan = try WAVExportCoordinator.makePlan(context: .loadedReadOnly(
            playbackSong: makeSampleBearingSong(),
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
        XCTAssertEqual(progressEvents.first?.stage, .rendering)
        XCTAssertTrue(progressEvents.contains { $0.stage == .rendering })
        XCTAssertTrue(progressEvents.contains { $0.stage == .applyingHeadroom })
        XCTAssertTrue(progressEvents.contains { $0.stage == .writingFile })
        XCTAssertEqual(progressEvents.last?.stage, .completed)
        XCTAssertEqual(progressEvents.last?.fractionCompleted, 1)
        XCTAssertTrue(progressEvents.allSatisfy { $0.totalFrames == plan.totalFrameCount })
        XCTAssertTrue(progressEvents.allSatisfy { $0.totalWindows == plan.renderWindowCount })
        XCTAssertEqual(progressEvents.map(\.stage).firstIndex(of: .rendering), 0)
        XCTAssertLessThan(
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .rendering)),
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .applyingHeadroom))
        )
        XCTAssertLessThan(
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .applyingHeadroom)),
            try XCTUnwrap(progressEvents.map(\.stage).firstIndex(of: .writingFile))
        )
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
              let exportPerformance = renderResult.wavExportPerformanceDiagnostics else {
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
        XCTAssertGreaterThan(renderPerformance.samplePayloadUploadCount, 0)
        XCTAssertGreaterThan(renderPerformance.approximateSamplePayloadBytesCopied, 0)
        XCTAssertEqual(exportPerformance.totalFramesPlanned, plan.totalFrameCount)
        XCTAssertEqual(exportPerformance.totalFramesRendered, plan.totalFrameCount)
        XCTAssertEqual(exportPerformance.renderWindowCount, summary.windowCount)
        XCTAssertEqual(exportPerformance.windowWriteDiagnostics.count, summary.windowCount)
        XCTAssertEqual(exportPerformance.renderPerformanceDiagnostics, renderPerformance)
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
        XCTAssertEqual(try Data(contentsOf: enabledDestination), try Data(contentsOf: disabledDestination))
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
