import AppKit
import AudioToolbox
import XCTest

final class PlaybackEngineTests: XCTestCase {
    @MainActor
    func testPlaybackTimingTraceDisabledByDefaultEmitsNoLines() {
        let sink = TestPlaybackTimingTraceSink()
        let clock = TestPlaybackTimingTraceClock()
        let recorder = PlaybackTimingTraceConfiguration.makeRecorder(
            environment: [:],
            clock: clock,
            sink: sink
        )

        XCTAssertFalse(recorder.isEnabled)
        XCTAssertNil(recorder.beginLifecycle("load"))
        XCTAssertTrue(sink.lines.isEmpty)
    }

    @MainActor
    func testPlaybackTimingTraceRecordsOrderedPhasesWithInjectedClockAndSink() throws {
        let sink = TestPlaybackTimingTraceSink()
        let clock = TestPlaybackTimingTraceClock()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, clock: clock, sink: sink)
        let session = try XCTUnwrap(recorder.beginLifecycle("load"))

        let metadataStart = session.beginPhase()
        clock.advance(milliseconds: 1.25)
        session.recordPhase(
            "module_metadata_loader_load",
            startedAt: metadataStart,
            fields: [PlaybackTimingTraceField("pattern_count", 2)]
        )

        let buildStart = session.beginPhase()
        clock.advance(milliseconds: 2.5)
        session.recordPhase(
            "playback_song_builder_build",
            startedAt: buildStart,
            fields: [PlaybackTimingTraceField("sample_count", 1)]
        )

        clock.advance(milliseconds: 0.25)
        session.finish(fields: [PlaybackTimingTraceField("load_succeeded", true)])

        XCTAssertEqual(timingPhases(in: sink.lines), [
            "module_metadata_loader_load",
            "playback_song_builder_build",
            "total",
        ])
        XCTAssertTrue(sink.lines[0].contains("elapsed_ms=1.250"))
        XCTAssertTrue(sink.lines[1].contains("elapsed_ms=2.500"))
        XCTAssertTrue(sink.lines[2].contains("elapsed_ms=4.000"))
    }

    func testPlaybackTimingTraceFormattingRedactsLocalPaths() {
        let pathLikeValue = ["", "Use" + "rs", "example", "Desk" + "top", "private.xm"].joined(separator: "/")
        let line = PlaybackTimingTraceFormatter.line(for: PlaybackTimingTraceRecord(
            lifecycle: "load",
            phase: "format",
            index: 1,
            elapsedMS: 1,
            fields: [
                PlaybackTimingTraceField("module_path", pathLikeValue),
                PlaybackTimingTraceField("order_count", 1),
            ]
        ))

        XCTAssertFalse(line.contains("/" + "Use" + "rs"))
        XCTAssertFalse(line.contains("Desk" + "top"))
        XCTAssertTrue(line.contains("module_path=redacted"))
        XCTAssertTrue(line.contains("order_count=1"))
    }

    func testAdapterPlanProfileDisabledByDefaultEmitsNoLines() {
        let sink = TestAdapterPlanProfileSink()
        let recorder = AdapterPlanProfileConfiguration.makeRecorder(
            environment: [:],
            clock: TestPlaybackTimingTraceClock(),
            sink: sink
        )

        XCTAssertNil(recorder)
        XCTAssertTrue(sink.lines.isEmpty)
    }

    func testAdapterPlanProfileFormattingRedactsPathsAndTitles() {
        let pathLikeValue = ["", "Use" + "rs", "example", "Desk" + "top", "private.xm"].joined(separator: "/")
        let line = AdapterPlanProfileFormatter.line(for: AdapterPlanProfileRecord(
            lifecycle: "test",
            phase: "format",
            index: 1,
            elapsedMS: 1,
            fields: [
                AdapterPlanProfileField("module_path", pathLikeValue),
                AdapterPlanProfileField("module_title", "private-local-title"),
                AdapterPlanProfileField("order_count", 1),
            ]
        ))

        XCTAssertTrue(line.hasPrefix("vtx_adapter_plan_profile schema=1 lifecycle=test phase=format"))
        XCTAssertTrue(line.contains("module_path=redacted"))
        XCTAssertTrue(line.contains("module_title=redacted"))
        XCTAssertTrue(line.contains("order_count=1"))
        XCTAssertFalse(line.contains("/" + "Use" + "rs"))
        XCTAssertFalse(line.contains("Desk" + "top"))
        XCTAssertFalse(line.contains("private-local-title"))
    }

    @MainActor
    func testAdapterPlanProfileRecordsOrderedConstructionPhasesWithSyntheticSong() throws {
        let sink = TestAdapterPlanProfileSink()
        let recorder = AdapterPlanProfileRecorder(
            isEnabled: true,
            clock: TestPlaybackTimingTraceClock(),
            sink: sink
        )
        let session = try XCTUnwrap(recorder.beginLifecycle("test"))

        let plan = RuntimeCMixerAdapterEventPlan.make(
            song: makeRuntimeAdapterPlaybackSong(patternIndex: 2),
            sampleRate: 100,
            profileSession: session
        )

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(adapterPlanProfilePhases(in: sink.lines), [
            "order_traversal",
            "timing_frame_calculation",
            "traversal_effect_status_indexing",
            "event_generation",
            "pattern_row_iteration",
            "playback_song_synthetic_adapter_adapt_total",
            "adapter_diagnostic_indexing",
            "adapter_event_generation",
            "event_sorting_grouping",
            "runtime_c_mixer_adapter_event_plan_make_total",
        ])
        let output = sink.lines.joined(separator: "\n")
        XCTAssertTrue(output.contains("order_count=1"))
        XCTAssertTrue(output.contains("pattern_count=1"))
        XCTAssertTrue(output.contains("row_count=2"))
        XCTAssertTrue(output.contains("planned_event_count=1"))
        XCTAssertTrue(output.contains("category_count=1"))
        XCTAssertFalse(output.contains("private"))
        XCTAssertFalse(output.contains("/"))
    }

    @MainActor
    func testRuntimeAdapterEventPlanReportsDurationSecondsFromPlannedSongEndFrame() {
        let plan = RuntimeCMixerAdapterEventPlan(
            generated: true,
            sampleRate: 100,
            plannedSongEndFrame: 18_500,
            plannedEventCount: 0,
            events: [],
            categories: [],
            plan: nil
        )

        XCTAssertEqual(plan.plannedSongEndSeconds, 185)
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: plan.plannedSongEndSeconds), "03:05")
    }

    @MainActor
    func testRuntimeAdapterEventPlanDurationIsUnavailableWhenPlanIsInvalid() {
        let invalidSampleRatePlan = RuntimeCMixerAdapterEventPlan(
            generated: true,
            sampleRate: 0,
            plannedSongEndFrame: 18_500,
            plannedEventCount: 0,
            events: [],
            categories: [],
            plan: nil
        )
        let invalidFramePlan = RuntimeCMixerAdapterEventPlan(
            generated: true,
            sampleRate: 100,
            plannedSongEndFrame: -1,
            plannedEventCount: 0,
            events: [],
            categories: [],
            plan: nil
        )
        let unavailablePlan = RuntimeCMixerAdapterEventPlan.unavailable(sampleRate: 100)

        XCTAssertNil(invalidSampleRatePlan.plannedSongEndSeconds)
        XCTAssertNil(invalidFramePlan.plannedSongEndSeconds)
        XCTAssertNil(unavailablePlan.plannedSongEndSeconds)
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: unavailablePlan.plannedSongEndSeconds), "--:--")
    }

    @MainActor
    func testPlaybackEngineRecordsPlayTimingPhasesWhenEnabled() throws {
        let sink = TestPlaybackTimingTraceSink()
        let clock = TestPlaybackTimingTraceClock()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, clock: clock, sink: sink)
        let engine = PlaybackEngine(
            audioEngine: TestPlaybackAudioOutput(),
            startsRealtimeTimer: false,
            playbackTimingRecorder: recorder
        )
        engine.load(song: makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 1]))
        let session = try XCTUnwrap(recorder.beginLifecycle("play"))

        engine.play(
            from: PlaybackStartContext(moduleTitle: "private title omitted", songPosition: 0, patternIndex: 2, row: 0),
            timingSession: session
        )
        session.finish(fields: [PlaybackTimingTraceField("test_finished", true)])

        let phases = timingPhases(in: sink.lines)
        XCTAssertTrue(phases.contains("playback_engine_start_position_resolution"))
        XCTAssertTrue(phases.contains("playback_engine_transient_runtime_state_reset"))
        XCTAssertTrue(phases.contains("playback_engine_enter_selected_playback_position"))
        XCTAssertTrue(phases.contains("playback_engine_restart_timer"))
        XCTAssertTrue(phases.contains("total"))
        XCTAssertFalse(sink.lines.joined(separator: "\n").contains("private title omitted"))
    }

    @MainActor
    func testPlaybackEngineLoadDefersRuntimeAdapterPlanUntilFirstPlay() throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let song = makeRuntimeAdapterPlaybackSong(patternIndex: 2)

        engine.load(song: song)

        XCTAssertEqual(prewarmScheduler.requests.count, 1)
        XCTAssertFalse(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 0)
        XCTAssertEqual(audioOutput.unavailablePlanConfigureCount, 1)

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.consumedContexts.count, 1)
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
    }

    @MainActor
    func testPlaybackEngineSecondPlayAfterStopReusesRuntimeAdapterPlan() throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        let stopAllCountAfterLoad = audioOutput.stopAllCount

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.stop()
        engine.play(from: nil)

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.stopAllCount, stopAllCountAfterLoad + 1)
        XCTAssertEqual(audioOutput.consumedContexts.count, 2)
    }

    @MainActor
    func testPlaybackEngineLoadingDifferentSongInvalidatesAndRebuildsRuntimeAdapterPlanOnNextPlay() throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        let firstSong = makeRuntimeAdapterPlaybackSong(patternIndex: 2)
        let secondSong = makeRuntimeAdapterPlaybackSong(patternIndex: 7)

        engine.load(song: firstSong)
        engine.play(from: PlaybackStartContext(moduleTitle: "first", songPosition: 0, patternIndex: 2, row: 0))
        engine.load(song: secondSong)

        XCTAssertFalse(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.unavailablePlanConfigureCount, 2)

        engine.play(from: PlaybackStartContext(moduleTitle: "second", songPosition: 0, patternIndex: 7, row: 0))

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 2)
        let lastContext = try XCTUnwrap(audioOutput.consumedContexts.last ?? nil)
        XCTAssertEqual(lastContext.patternIndex, 7)
    }

    @MainActor
    func testPlaybackEngineLoadNilClearsRuntimeAdapterPlan() throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        engine.load(song: nil)

        XCTAssertFalse(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.configuredPlans.last?.generated, false)
        XCTAssertEqual(engine.song, nil)
    }

    @MainActor
    func testPlaybackEngineSuccessfulPrewarmInstallsCachedPlanForCurrentGeneration() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        prewarmScheduler.complete()
        await Task.yield()

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.consumedContexts.count, 1)
    }

    @MainActor
    func testPlaybackEngineFirstPlayUsesPrewarmedPlanWhenReady() async throws {
        let sink = TestPlaybackTimingTraceSink()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, sink: sink)
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            playbackTimingRecorder: recorder,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        prewarmScheduler.complete()
        await Task.yield()

        XCTAssertTrue(timingPhases(in: sink.lines, lifecycle: "prewarm").contains("runtime_adapter_event_plan_prewarm_scheduled"))
        XCTAssertTrue(timingPhases(in: sink.lines, lifecycle: "prewarm").contains("runtime_adapter_event_plan_prewarm_make"))
        XCTAssertTrue(timingPhases(in: sink.lines, lifecycle: "prewarm").contains("runtime_adapter_event_plan_prewarm_configure"))

        let playSession = try XCTUnwrap(recorder.beginLifecycle("play"))
        engine.play(
            from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0),
            timingSession: playSession
        )
        playSession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])

        XCTAssertEqual(timingField(in: sink.lines, lifecycle: "play", phase: "runtime_adapter_event_plan_ready_for_play", key: "play_adapter_plan_mode"), "prewarmed")
        XCTAssertFalse(timingPhases(in: sink.lines, lifecycle: "play").contains("runtime_adapter_event_plan_make"))
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
    }

    @MainActor
    func testPlaybackEnginePrewarmCompletionPublishesAdapterPlanDuration() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        var observedDurations = [TimeInterval]()
        engine.runtimeAdapterPlanDidUpdate = { [weak engine] in
            if let duration = engine?.runtimeAdapterPlanDurationSeconds {
                observedDurations.append(duration)
            }
        }

        engine.load(song: makeDurationPlaybackSong(patternIndex: 2))

        XCTAssertNil(engine.runtimeAdapterPlanDurationSeconds)

        prewarmScheduler.complete()
        await Task.yield()

        XCTAssertEqual(engine.runtimeAdapterPlanDurationSeconds ?? 0, 185, accuracy: 0.000_001)
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "03:05")
        XCTAssertEqual(observedDurations.count, 1)
        XCTAssertEqual(observedDurations[0], 185, accuracy: 0.000_001)
    }

    @MainActor
    func testPlaybackEngineFirstPlayWaitsForPrewarmInProgressWithoutDuplicatePlanBuild() throws {
        let sink = TestPlaybackTimingTraceSink()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, sink: sink)
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            playbackTimingRecorder: recorder,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        prewarmScheduler.jobs[0].waitResult = prewarmScheduler.defaultResult()
        let playSession = try XCTUnwrap(recorder.beginLifecycle("play"))
        engine.play(
            from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0),
            timingSession: playSession
        )
        playSession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])

        XCTAssertEqual(prewarmScheduler.jobs[0].waitCount, 1)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(timingField(in: sink.lines, lifecycle: "play", phase: "runtime_adapter_event_plan_ready_for_play", key: "play_adapter_plan_mode"), "waited")
        XCTAssertFalse(timingPhases(in: sink.lines, lifecycle: "play").contains("runtime_adapter_event_plan_make"))

        prewarmScheduler.complete()
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
    }

    @MainActor
    func testPlaybackEngineFirstPlaySynchronousFallbackPublishesAdapterPlanDuration() throws {
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        var updateCount = 0
        engine.runtimeAdapterPlanDidUpdate = {
            updateCount += 1
        }

        engine.load(song: makeDurationPlaybackSong(patternIndex: 2))
        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(prewarmScheduler.jobs[0].waitCount, 1)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(engine.runtimeAdapterPlanDurationSeconds ?? 0, 185, accuracy: 0.000_001)
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "03:05")
        XCTAssertEqual(updateCount, 1)
    }

    @MainActor
    func testPlaybackEngineFirstPlayBuildsSynchronouslyWhenPrewarmUnavailable() throws {
        let sink = TestPlaybackTimingTraceSink()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, sink: sink)
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            playbackTimingRecorder: recorder,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        let playSession = try XCTUnwrap(recorder.beginLifecycle("play"))
        engine.play(
            from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0),
            timingSession: playSession
        )
        playSession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])

        XCTAssertEqual(prewarmScheduler.jobs[0].waitCount, 1)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(timingField(in: sink.lines, lifecycle: "play", phase: "runtime_adapter_event_plan_ready_for_play", key: "play_adapter_plan_mode"), "sync_fallback")
        XCTAssertTrue(timingPhases(in: sink.lines, lifecycle: "play").contains("runtime_adapter_event_plan_make"))
    }

    @MainActor
    func testPlaybackEngineLoadNilCancelsPrewarmAndClearsPlan() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        engine.load(song: nil)
        prewarmScheduler.complete()
        await Task.yield()

        XCTAssertEqual(prewarmScheduler.jobs[0].cancelCount, 1)
        XCTAssertFalse(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 0)
        XCTAssertEqual(audioOutput.configuredPlans.last?.generated, false)
    }

    @MainActor
    func testPlaybackEngineStalePrewarmResultCannotInstallIntoNewSongGeneration() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        let staleResult = prewarmScheduler.defaultResult(at: 0)
        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 7))
        prewarmScheduler.complete(at: 0, result: staleResult)
        await Task.yield()

        XCTAssertFalse(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 0)

        prewarmScheduler.complete(at: 1)
        await Task.yield()

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        engine.play(from: PlaybackStartContext(moduleTitle: "second", songPosition: 0, patternIndex: 7, row: 0))
        let lastContext = try XCTUnwrap(audioOutput.consumedContexts.last ?? nil)
        XCTAssertEqual(lastContext.patternIndex, 7)
    }

    @MainActor
    func testPlaybackEngineStopDoesNotInvalidateCachedPrewarmedPlanAndSecondPlayReusesIt() async throws {
        let sink = TestPlaybackTimingTraceSink()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, sink: sink)
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            playbackTimingRecorder: recorder,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2))
        prewarmScheduler.complete()
        await Task.yield()
        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.stop()

        let lineCountBeforeSecondPlay = sink.lines.count
        let secondPlaySession = try XCTUnwrap(recorder.beginLifecycle("play"))
        engine.play(from: nil, timingSession: secondPlaySession)
        secondPlaySession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])
        let secondPlayLines = Array(sink.lines.dropFirst(lineCountBeforeSecondPlay))

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.consumedContexts.count, 2)
        XCTAssertEqual(timingField(in: secondPlayLines, lifecycle: "play", phase: "runtime_adapter_event_plan_ready_for_play", key: "play_adapter_plan_mode"), "cached_reuse")
        XCTAssertFalse(timingPhases(in: secondPlayLines, lifecycle: "play").contains("runtime_adapter_event_plan_make"))
    }

    @MainActor
    func testPlaybackEngineStopAndPlayAfterStopKeepAdapterPlanDuration() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeDurationPlaybackSong(patternIndex: 2))
        prewarmScheduler.complete()
        await Task.yield()
        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.stop()

        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "03:05")

        engine.play(from: nil)

        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "03:05")
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
    }

    @MainActor
    func testPlaybackEngineLoadClearsStaleAdapterPlanDurationUntilNewPlanIsReady() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeDurationPlaybackSong(patternIndex: 2))
        prewarmScheduler.complete()
        await Task.yield()

        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "03:05")

        engine.load(song: makeDurationPlaybackSong(patternIndex: 7, rowCount: 2))

        XCTAssertNil(engine.runtimeAdapterPlanDurationSeconds)
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "--:--")
    }

    @MainActor
    func testPlaybackEngineLoadNilClearsStaleAdapterPlanDurationForFileNew() async throws {
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )

        engine.load(song: makeDurationPlaybackSong(patternIndex: 2))
        prewarmScheduler.complete()
        await Task.yield()

        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "03:05")

        engine.load(song: nil)

        XCTAssertNil(engine.runtimeAdapterPlanDurationSeconds)
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: engine.runtimeAdapterPlanDurationSeconds), "--:--")
    }

    @MainActor
    func testPatternLoopOffPublicFixtureNormalTraversalReachesAllOrders() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.load(song: song)
        engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: false,
            timingSession: nil
        )
        advanceRows(song.orders.count * 4, engine: engine, timing: song.initialTiming)

        XCTAssertTrue(Set(positions.map(\.orderIndex)).isSuperset(of: Set([0, 1, 2])))
        XCTAssertTrue(audioOutput.consumedPatternLoopRanges.allSatisfy { $0 == nil })
    }

    @MainActor
    func testPatternLoopOnFromOrderZeroWrapsWithinCurrentOrder() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let rowCount = try XCTUnwrap(song.patternsByIndex[0]?.rowCount)
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.load(song: song)
        engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: true,
            timingSession: nil
        )
        advanceRows(rowCount * 3, engine: engine, timing: song.initialTiming)

        XCTAssertTrue(positions.contains(PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)))
        XCTAssertTrue(positions.allSatisfy { $0.orderIndex == 0 && $0.patternIndex == 0 })
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.first??.orderIndex, 0)
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
    }

    @MainActor
    func testPatternLoopOnFromOrderOneWrapsWithinCurrentOrder() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let rowCount = try XCTUnwrap(song.patternsByIndex[1]?.rowCount)
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.load(song: song)
        engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 1, patternIndex: 1, row: 0),
            loopEnabled: true,
            timingSession: nil
        )
        advanceRows(rowCount * 3, engine: engine, timing: song.initialTiming)

        XCTAssertTrue(positions.contains(PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0)))
        XCTAssertTrue(positions.allSatisfy { $0.orderIndex == 1 && $0.patternIndex == 1 })
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.first??.orderIndex, 1)
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
    }

    @MainActor
    func testPatternLoopDisabledAfterStopNormalTraversalResumesOnNextPlay() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let rowCount = try XCTUnwrap(song.patternsByIndex[0]?.rowCount)
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.load(song: song)
        let startContext = PlaybackStartContext(moduleTitle: "fixture", songPosition: 0, patternIndex: 0, row: 0)
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        advanceRows(rowCount + 1, engine: engine, timing: song.initialTiming)
        engine.stop()
        positions.removeAll()

        engine.play(from: startContext, loopEnabled: false, timingSession: nil)
        advanceRows(rowCount + 1, engine: engine, timing: song.initialTiming)

        XCTAssertTrue(positions.contains { $0.orderIndex == 1 && $0.patternIndex == 1 })
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.last ?? nil, nil)
    }

    @MainActor
    func testPatternLoopDoesNotArmRuntimeSongEndStopTimer() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 4],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makePlaybackSample(pcm: [0.25], baseSampleRate: 100)])],
            note: 49,
            instrument: 1,
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let startContext = PlaybackStartContext(moduleTitle: "editable", songPosition: 0, patternIndex: 0, row: 0)
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )

        engine.load(song: song)
        engine.play(from: startContext, loopEnabled: false, timingSession: nil)
        XCTAssertTrue(engine.isRuntimeCMixerSongEndStopPendingForTesting)
        engine.stop()

        engine.play(from: startContext, loopEnabled: true, timingSession: nil)

        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.last??.orderIndex, 0)
        XCTAssertFalse(engine.isRuntimeCMixerSongEndStopPendingForTesting)
        XCTAssertEqual(engine.state.mode, .playing)
    }

    @MainActor
    func testStopWhilePatternLoopedKeepsCachedRuntimeAdapterPlan() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )

        engine.load(song: song)
        engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: true,
            timingSession: nil
        )
        engine.stop()

        XCTAssertTrue(audioOutput.hasRuntimeAdapterEventPlan)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.first??.orderIndex, 0)
    }

    @MainActor
    func testActiveEditablePatternLoopRefreshInstallsFreshPlanAtLoopBoundary() async throws {
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let initialSong = makeEditablePatternLoopSong(notesByRow: [0: 49])
        let refreshedSong = makeEditablePatternLoopSong(notesByRow: [0: 49, 1: 51])
        let startContext = PlaybackStartContext(moduleTitle: "editable", songPosition: 0, patternIndex: 0, row: 0)

        engine.load(song: initialSong)
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        engine.requestEditablePatternLoopRefresh(song: refreshedSong)

        XCTAssertEqual(prewarmScheduler.requests.count, 2)
        XCTAssertEqual(noteTriggerNotes(in: RuntimeCMixerAdapterEventPlan.make(song: prewarmScheduler.requests.last?.song, sampleRate: 100)), [49, 51])

        prewarmScheduler.complete(at: 1)
        await Task.yield()

        XCTAssertTrue(engine.hasPendingEditablePatternLoopRefreshForTesting)
        XCTAssertEqual(noteTriggerNotes(in: try XCTUnwrap(engine.pendingEditablePatternLoopRefreshPlanForTesting)), [49, 51])
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)

        advanceRows(4, engine: engine, timing: initialSong.initialTiming)

        XCTAssertEqual(engine.song, refreshedSong)
        XCTAssertFalse(engine.hasPendingEditablePatternLoopRefreshForTesting)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 2)
        XCTAssertEqual(noteTriggerNotes(in: try XCTUnwrap(audioOutput.configuredPlans.last)), [49, 51])
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.last??.orderIndex, 0)
    }

    @MainActor
    func testActiveEditablePatternLoopRefreshCoalescesToLatestSnapshot() async throws {
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let initialSong = makeEditablePatternLoopSong(notesByRow: [0: 49])
        let staleSong = makeEditablePatternLoopSong(notesByRow: [0: 49, 1: 51])
        let latestSong = makeEditablePatternLoopSong(notesByRow: [0: 49, 1: 51, 2: 53])
        let startContext = PlaybackStartContext(moduleTitle: "editable", songPosition: 0, patternIndex: 0, row: 0)

        engine.load(song: initialSong)
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        engine.requestEditablePatternLoopRefresh(song: staleSong)
        engine.requestEditablePatternLoopRefresh(song: latestSong)

        XCTAssertEqual(prewarmScheduler.requests.count, 3)
        XCTAssertEqual(prewarmScheduler.jobs[1].cancelCount, 1)

        prewarmScheduler.complete(at: 1)
        await Task.yield()
        XCTAssertNil(engine.pendingEditablePatternLoopRefreshPlanForTesting)

        prewarmScheduler.complete(at: 2)
        await Task.yield()
        XCTAssertEqual(noteTriggerNotes(in: try XCTUnwrap(engine.pendingEditablePatternLoopRefreshPlanForTesting)), [49, 51, 53])

        advanceRows(4, engine: engine, timing: initialSong.initialTiming)

        XCTAssertEqual(engine.song, latestSong)
        XCTAssertEqual(noteTriggerNotes(in: try XCTUnwrap(audioOutput.configuredPlans.last)), [49, 51, 53])
    }

    @MainActor
    func testStopCancelsPendingEditablePatternLoopRefresh() async throws {
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let initialSong = makeEditablePatternLoopSong(notesByRow: [0: 49])
        let refreshedSong = makeEditablePatternLoopSong(notesByRow: [0: 49, 1: 51])
        let startContext = PlaybackStartContext(moduleTitle: "editable", songPosition: 0, patternIndex: 0, row: 0)

        engine.load(song: initialSong)
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        engine.requestEditablePatternLoopRefresh(song: refreshedSong)
        engine.stop()

        XCTAssertFalse(engine.hasPendingEditablePatternLoopRefreshForTesting)
        XCTAssertEqual(prewarmScheduler.jobs[1].cancelCount, 1)

        prewarmScheduler.complete(at: 1)
        await Task.yield()
        advanceRows(4, engine: engine, timing: initialSong.initialTiming)

        XCTAssertEqual(engine.song, initialSong)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
        XCTAssertFalse(engine.hasPendingEditablePatternLoopRefreshForTesting)
    }

    @MainActor
    func testEditablePatternLoopRefreshIgnoredWhenLoopInactive() throws {
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let initialSong = makeEditablePatternLoopSong(notesByRow: [0: 49])
        let refreshedSong = makeEditablePatternLoopSong(notesByRow: [0: 49, 1: 51])
        let startContext = PlaybackStartContext(moduleTitle: "editable", songPosition: 0, patternIndex: 0, row: 0)

        engine.load(song: initialSong)
        engine.play(from: startContext, loopEnabled: false, timingSession: nil)
        engine.requestEditablePatternLoopRefresh(song: refreshedSong)

        XCTAssertEqual(prewarmScheduler.requests.count, 1)
        XCTAssertFalse(engine.hasPendingEditablePatternLoopRefreshForTesting)
        XCTAssertNil(audioOutput.consumedPatternLoopRanges.last ?? nil)
    }

    @MainActor
    func testPlaybackTimingTraceRecordsDeferredAdapterPlanCreationDuringPlay() throws {
        let sink = TestPlaybackTimingTraceSink()
        let clock = TestPlaybackTimingTraceClock()
        let recorder = PlaybackTimingTraceRecorder(isEnabled: true, clock: clock, sink: sink)
        let audioOutput = TestRuntimeAdapterAudioOutput()
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )

        let loadSession = try XCTUnwrap(recorder.beginLifecycle("load"))
        engine.load(song: makeRuntimeAdapterPlaybackSong(patternIndex: 2), timingSession: loadSession)
        loadSession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])

        XCTAssertFalse(timingPhases(in: sink.lines, lifecycle: "load").contains("runtime_adapter_event_plan_make"))
        XCTAssertFalse(timingPhases(in: sink.lines, lifecycle: "load").contains("runtime_adapter_event_plan_configure"))

        let firstPlaySession = try XCTUnwrap(recorder.beginLifecycle("play"))
        engine.play(
            from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0),
            timingSession: firstPlaySession
        )
        firstPlaySession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])

        XCTAssertTrue(timingPhases(in: sink.lines, lifecycle: "play").contains("runtime_adapter_event_plan_make"))
        XCTAssertTrue(timingPhases(in: sink.lines, lifecycle: "play").contains("runtime_adapter_event_plan_configure"))

        engine.stop()
        let lineCountBeforeSecondPlay = sink.lines.count
        let secondPlaySession = try XCTUnwrap(recorder.beginLifecycle("play"))
        engine.play(from: nil, timingSession: secondPlaySession)
        secondPlaySession.finish(fields: [PlaybackTimingTraceField("test_finished", true)])
        let secondPlayLines = Array(sink.lines.dropFirst(lineCountBeforeSecondPlay))

        XCTAssertFalse(timingPhases(in: secondPlayLines, lifecycle: "play").contains("runtime_adapter_event_plan_make"))
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
    }

    @MainActor
    func testPlaybackEngineRecordsTraceForTriggeredNote() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1024),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x02)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        let timingEvent = traceWriter.events.first { $0.decision == .observed && $0.decisionReason == "row_timing_before_effects" }
        XCTAssertEqual(timingEvent?.speed, 6)
        XCTAssertEqual(timingEvent?.bpm, 125)
        XCTAssertEqual(timingEvent?.tickDuration ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertEqual(timingEvent?.rowDuration ?? 0, 0.12, accuracy: 0.0001)

        let event = traceWriter.events.first { $0.decision == .triggered }
        XCTAssertEqual(event?.tickIndex, 0)
        XCTAssertEqual(event?.orderIndex, 0)
        XCTAssertEqual(event?.patternIndex, 2)
        XCTAssertEqual(event?.rowIndex, 0)
        XCTAssertEqual(event?.tickInRow, 0)
        XCTAssertEqual(event?.channelIndex, 0)
        XCTAssertEqual(event?.startedFromDebugSeek, false)
        XCTAssertEqual(event?.noteValue, 49)
        XCTAssertEqual(event?.instrumentIndex, 1)
        XCTAssertEqual(event?.sampleIndex, 0)
        XCTAssertEqual(event?.effectCommand, "09")
        XCTAssertEqual(event?.effectParameter, "02")
        XCTAssertEqual(event?.computedVolume, 1)
        XCTAssertEqual(event?.computedPanning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 64), accuracy: 0.0001)
        XCTAssertEqual(event?.computedPitchSemitones, 0)
        XCTAssertEqual(event?.sourceSampleRate, 8_363)
        XCTAssertEqual(event?.audioBufferSampleRate, 44_100)
        XCTAssertEqual(event?.targetFrequency ?? 0, 8_363, accuracy: 0.0001)
        XCTAssertEqual(event?.computedRate ?? 0, 8_363.0 / 44_100.0, accuracy: 0.000001)
        XCTAssertEqual(event?.rateBasis, PlaybackPitchCalculator.audioBufferSampleRateBasis)
        XCTAssertEqual(event?.loopEnabled, false)
        XCTAssertEqual(event?.sampleOffset, 512)
        XCTAssertEqual(event?.envelopeEnabled, false)
        XCTAssertEqual(event?.envelopeTick, 0)
        XCTAssertEqual(event?.envelopeValue, 1)
        XCTAssertEqual(event?.fadeoutValue, 1)
        XCTAssertEqual(event?.finalAppliedVolume, 1)
        XCTAssertEqual(event?.decisionReason, "row_note")
        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 64), accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineStartsFromDebugOrderRowAndAnnotatesTrace() {
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput(), traceWriter: traceWriter)
        engine.load(song: makePlaybackSong(orderPatternIndices: [2, 5], patternRowCounts: [2: 2, 5: 8]))

        engine.play(
            from: nil,
            debugStart: PlaybackDebugStartRequest(orderIndex: 1, rowIndex: 3)
        )

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 3))
        let timingEvent = traceWriter.events.first { $0.decision == .observed && $0.decisionReason == "row_timing_before_effects" }
        XCTAssertEqual(timingEvent?.startedFromDebugSeek, true)
        XCTAssertEqual(timingEvent?.requestedStartOrder, 1)
        XCTAssertNil(timingEvent?.requestedStartPattern)
        XCTAssertEqual(timingEvent?.requestedStartRow, 3)
        XCTAssertNil(timingEvent?.requestedStartTick)
        XCTAssertEqual(timingEvent?.actualStartOrder, 1)
        XCTAssertEqual(timingEvent?.actualStartPattern, 5)
        XCTAssertEqual(timingEvent?.actualStartRow, 3)
        XCTAssertEqual(timingEvent?.actualStartTick, 0)
    }

    @MainActor
    func testPlaybackEngineDebugSeekCanResolvePatternIndexWithoutAutoplay() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(orderPatternIndices: [2, 5, 2], patternRowCounts: [2: 4, 5: 8]))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        let position = engine.seek(
            to: PlaybackDebugStartRequest(patternIndex: 5, rowIndex: 6),
            autoplay: false
        )

        XCTAssertEqual(position, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 6))
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 6))
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertEqual(positions, [PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 6)])
    }

    @MainActor
    func testPlaybackEngineDebugSeekWhilePlayingResetsStateAndCanStartAtTick() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 5],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1)],
                5: [makePlaybackRow(index: 0, note: 53, instrument: 1, effectType: 0x0E, effectParam: 0xC2)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        ))

        engine.play(from: nil)
        _ = engine.seek(
            to: PlaybackDebugStartRequest(orderIndex: 1, rowIndex: 0, tickInRow: 2),
            autoplay: true
        )

        XCTAssertEqual(audioOutput.stopAllCount, 1)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 0))
        XCTAssertTrue(audioOutput.stoppedChannels.contains(0))
        let debugTickEvent = traceWriter.events.last { $0.startedFromDebugSeek && $0.tickInRow == 2 }
        XCTAssertEqual(debugTickEvent?.requestedStartOrder, 1)
        XCTAssertEqual(debugTickEvent?.requestedStartRow, 0)
        XCTAssertEqual(debugTickEvent?.requestedStartTick, 2)
        XCTAssertEqual(debugTickEvent?.actualStartOrder, 1)
        XCTAssertEqual(debugTickEvent?.actualStartPattern, 5)
        XCTAssertEqual(debugTickEvent?.actualStartRow, 0)
        XCTAssertEqual(debugTickEvent?.actualStartTick, 2)
    }

    @MainActor
    func testPlaybackEngineRecordsTraceForDelayCutAndRetriggerDecisions() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 3, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(traceWriter.events.contains { $0.decision == .delayed && $0.decisionReason == "note_delay" })
        XCTAssertTrue(traceWriter.events.contains { $0.decision == .cut && $0.decisionReason == "note_cut" })
        XCTAssertTrue(traceWriter.events.contains { $0.decision == .retriggered && $0.decisionReason == "retrigger_interval" })
    }

    @MainActor
    func testPlaybackEngineAppliesVolumeColumnSetVolume() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x3D)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale ?? 0, Float(45) / 64.0, accuracy: 0.0001)
        let event = traceWriter.events.first { $0.decision == .triggered }
        XCTAssertEqual(event?.rawVolumeColumn, "3D")
        XCTAssertEqual(event?.decodedVolumeColumnCommand, "setVolume")
        XCTAssertEqual(event?.volumeColumnApplied, true)
        XCTAssertEqual(event?.volumeColumnVolume, 45)
        XCTAssertEqual(event?.computedVolume ?? 0, Float(45) / 64.0, accuracy: 0.0001)
        XCTAssertEqual(event?.finalAppliedVolume ?? 0, Float(45) / 64.0, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineMapsVolumeColumnPanning() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xCC)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 204), accuracy: 0.0001)
        let event = traceWriter.events.first { $0.decision == .triggered }
        XCTAssertEqual(event?.rawVolumeColumn, "CC")
        XCTAssertEqual(event?.decodedVolumeColumnCommand, "setPanning")
        XCTAssertEqual(event?.volumeColumnApplied, true)
        XCTAssertEqual(event?.volumeColumnPanning, 204)
        XCTAssertEqual(event?.computedPanning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 204), accuracy: 0.0001)
    }

    func testPlaybackEngineStartsPlayingFromContext() {
        let engine = TestPlaybackEngine()
        let context = TestPlaybackStartContext(moduleTitle: "example", songPosition: 3, patternIndex: 2, row: 16)

        engine.play(from: context)

        XCTAssertEqual(engine.state, TestPlaybackState(mode: .playing, context: context))
    }

    func testPlaybackEngineStopsAndClearsContext() {
        let engine = TestPlaybackEngine()
        engine.play(from: TestPlaybackStartContext(moduleTitle: "example", songPosition: 3, patternIndex: 2, row: 16))

        engine.stop()

        XCTAssertEqual(engine.state, .stopped)
    }

    func testPlaybackEnginePausePreservesContext() {
        let engine = TestPlaybackEngine()
        let context = TestPlaybackStartContext(moduleTitle: "example", songPosition: 3, patternIndex: 2, row: 16)
        engine.play(from: context)

        engine.pause()

        XCTAssertEqual(engine.state, TestPlaybackState(mode: .paused, context: context))
    }

    @MainActor
    func testPlaybackEngineIgnoresPlayWhileAlreadyPlaying() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 4],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            note: 49,
            instrument: 1
        ))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        let firstContext = PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0)
        let secondContext = PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 2)
        engine.play(from: firstContext)
        engine.play(from: secondContext)

        XCTAssertEqual(engine.state, PlaybackState(mode: .playing, context: firstContext))
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(positions, [PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0)])
        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
    }

    @MainActor
    func testPlaybackEngineStopPreservesAdvancedPositionAndDoesNotResetToSongStart() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, runtimeCMixerTraceWriter: traceWriter)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowCounts: [2: 2, 3: 4],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.stop()

        let preserved = PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 1)
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentPosition, preserved)
        XCTAssertNotEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(audioOutput.stopAllCount, 1)

        let stopEvent = traceWriter.events.last { $0.runtimeAction == "stop" }
        XCTAssertEqual(stopEvent?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(stopEvent?.previousOrderIndex, 1)
        XCTAssertEqual(stopEvent?.previousPatternIndex, 3)
        XCTAssertEqual(stopEvent?.previousRowIndex, 1)
        XCTAssertEqual(stopEvent?.nextOrderIndex, 1)
        XCTAssertEqual(stopEvent?.nextPatternIndex, 3)
        XCTAssertEqual(stopEvent?.nextRowIndex, 1)
        XCTAssertEqual(stopEvent?.reason, "transport_stop_preserve_position")
    }

    @MainActor
    func testPlaybackEngineReportsPlannedSongEndStopSeparatelyFromManualStop() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, runtimeCMixerTraceWriter: traceWriter)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 1],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(audioOutput.stopAllCount, 1)
        let stopEvent = traceWriter.events.last { $0.runtimeAction == "stop" }
        XCTAssertEqual(stopEvent?.reason, "planned_song_end")
    }

    @MainActor
    func testPlaybackEnginePlayAfterStopStartsFromPreservedPosition() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 64), baseSampleRate: 44_100)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 4],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            note: 49,
            instrument: 1,
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.stop()
        let preserved = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2)
        XCTAssertEqual(engine.currentPosition, preserved)

        engine.play(from: nil)

        XCTAssertEqual(engine.state.mode, .playing)
        XCTAssertEqual(engine.currentPosition, preserved)
        XCTAssertEqual(audioOutput.triggeredRequests.count, 4)
    }

    @MainActor
    func testPlaybackEngineSpacebarToggleStopsAndPreservesPosition() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, runtimeCMixerTraceWriter: traceWriter)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 4],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 1))
        engine.advanceOneTick()
        engine.togglePlayStop(from: nil)

        let preserved = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2)
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentPosition, preserved)
        XCTAssertEqual(audioOutput.stopAllCount, 1)
        XCTAssertEqual(traceWriter.events.last { $0.runtimeAction == "spacebarStop" }?.nextRowIndex, 2)
    }

    @MainActor
    func testPlaybackEngineSpacebarToggleStartsFromPreservedPosition() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, runtimeCMixerTraceWriter: traceWriter)
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 64), baseSampleRate: 44_100)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 4],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            note: 49,
            instrument: 1,
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))
        let preservedContext = PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 2)
        engine.play(from: preservedContext)
        engine.stop()

        engine.togglePlayStop(from: nil)

        XCTAssertEqual(engine.state.mode, .playing)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2))
        XCTAssertEqual(traceWriter.events.last { $0.runtimeAction == "spacebarPlay" }?.nextRowIndex, 2)
        XCTAssertEqual(audioOutput.triggeredRequests.count, 2)
    }

    @MainActor
    func testPlaybackEngineStopIsIdempotentAfterPlayback() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        engine.load(song: makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4]))
        var stopNotificationCount = 0
        engine.playbackDidStop = { stopNotificationCount += 1 }

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.stop()
        engine.stop()

        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(stopNotificationCount, 1)
        XCTAssertEqual(audioOutput.stopAllCount, 1)
    }

    @MainActor
    func testPlaybackEngineLoadWhilePlayingStopsAndReplacesSong() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let firstSong = makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4])
        let secondSong = makePlaybackSong(orderPatternIndices: [7], patternRowCounts: [7: 8])
        var stopNotificationCount = 0
        engine.playbackDidStop = { stopNotificationCount += 1 }

        engine.load(song: firstSong)
        engine.play(from: PlaybackStartContext(moduleTitle: "first", songPosition: 0, patternIndex: 2, row: 0))
        engine.load(song: secondSong)

        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 7, rowIndex: 0))
        XCTAssertEqual(stopNotificationCount, 0)
        XCTAssertEqual(audioOutput.resetCount, 2)
    }

    @MainActor
    func testPlaybackEngineToggleStartsThroughPlaybackPath() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        engine.load(song: makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4]))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.togglePlayPause(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 1))

        XCTAssertEqual(engine.state, PlaybackState(mode: .playing, context: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 1)))
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(positions, [PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)])
    }

    @MainActor
    func testPlaybackEngineAppliesFxxTimingOnRowEntry() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            effectType: 0x0F,
            effectParam: 0x03
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 3, bpm: 125))
    }

    @MainActor
    func testPlaybackEngineUsesSongInitialTimingFromXMHeader() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        let song = makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 2], initialTiming: PlaybackTiming(speed: 2, bpm: 183))

        engine.load(song: song)

        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 2, bpm: 183))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 2, bpm: 183))
    }

    @MainActor
    func testPlaybackEngineDistinguishesFxxSpeedAndBPM() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1, effectType: 0x0F, effectParam: 0x7D),
                    makePlaybackRow(index: 2)
                ]
            ],
            initialTiming: PlaybackTiming(speed: 6, bpm: 183)
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 3, bpm: 183))

        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 3, bpm: 125))
    }

    @MainActor
    func testPlaybackEngineAppliesBxxPositionJumpOnNextRowAdvance() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3, 4],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x02)],
                3: [makePlaybackRow(index: 0)],
                4: [makePlaybackRow(index: 0)]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 0))
        XCTAssertEqual(positions, [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 0)
        ])
    }

    @MainActor
    func testPlaybackEngineIgnoresOutOfBoundsBxxPositionJump() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x7F)],
                3: [makePlaybackRow(index: 0)]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 0))
    }

    @MainActor
    func testPlaybackEngineAppliesDxxPatternBreakOnNextRowAdvance() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0D, effectParam: 0x02)],
                3: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2),
                    makePlaybackRow(index: 3)
                ]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 2))
    }

    @MainActor
    func testPlaybackEngineAppliesCxxVolumeToTriggeredVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0C, effectParam: 0x20)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale, 0.5)
    }

    @MainActor
    func testPlaybackEngineApplies8xxPanningToTriggeredVoiceAndTrace() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x08, effectParam: 0xFF)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(traceWriter.events.first { $0.decision == .triggered }?.computedPanning ?? 0, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineUsesConservativeDefaultChannelPanning() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    PlaybackRow(
                        index: 0,
                        cells: [
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                        ]
                    )
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(
            audioOutput.triggeredRequests.map(\.panning),
            [
                PlaybackEffectHandler.audioPanning(forXMValue: 64),
                PlaybackEffectHandler.audioPanning(forXMValue: 191),
                PlaybackEffectHandler.audioPanning(forXMValue: 191),
                PlaybackEffectHandler.audioPanning(forXMValue: 64)
            ]
        )
    }

    @MainActor
    func testPlaybackEngineAppliesGxxGlobalVolumeToTriggeredVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x10, effectParam: 0x20)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale, 0.5)
    }

    @MainActor
    func testPlaybackEngineAppliesArpeggioAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x00, effectParam: 0x37),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.updatedControls.suffix(3).map { $0.controls.pitchOffsetSemitones }, [3, 7, 0])
    }

    @MainActor
    func testPlaybackEngineAppliesVolumeAndPitchSlidesAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0C, effectParam: 0x20),
                    makePlaybackRow(index: 1, effectType: 0x0A, effectParam: 0x20),
                    makePlaybackRow(index: 2, effectType: 0x01, effectParam: 0x08),
                    makePlaybackRow(index: 3)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.53125) < 0.0001 })
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.pitchOffsetSemitones - 0.125) < 0.0001 })
    }

    @MainActor
    func testPlaybackEngineAppliesPxyPanningSlideAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x08, effectParam: 0x80),
                    makePlaybackRow(index: 1, effectType: 0x19, effectParam: 0x20),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.updatedControls.contains {
            $0.channel == 0 && abs($0.controls.panning - PlaybackEffectHandler.audioPanning(forXMValue: 130)) < 0.0001
        })
    }

    @MainActor
    func testPlaybackEngineAppliesTonePortamentoWithoutRetriggeringSample() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1, effectType: 0x03, effectParam: 0x10),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.pitchOffsetSemitones - 0.25) < 0.0001 })
    }

    @MainActor
    func testPlaybackEngineAppliesVibratoAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 3, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()

        let vibratoOffsets = audioOutput.updatedControls.map { $0.controls.pitchOffsetSemitones }.filter { abs($0) > 0.0001 }
        XCTAssertFalse(vibratoOffsets.isEmpty)
    }

    @MainActor
    func testPlaybackEngineAppliesTremoloAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0C, effectParam: 0x20),
                    makePlaybackRow(index: 1, effectType: 0x07, effectParam: 0x48),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && $0.controls.volumeScale > 0.5 && $0.controls.volumeScale < 1.0 })
    }

    @MainActor
    func testPlaybackEngineAppliesHxyGlobalVolumeSlideAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x10, effectParam: 0x20),
                    makePlaybackRow(index: 1, effectType: 0x11, effectParam: 0x10),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.515625) < 0.0001 })
    }

    @MainActor
    func testPlaybackEngineAppliesVolumeEnvelopeToActiveVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32)
            ],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x01,
            fadeout: 0
        )
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)]
        ))
        engine.configureTiming(PlaybackTiming(speed: 3, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.5) < 0.0001 })
        let updatedEvent = traceWriter.events.first { $0.decision == .updated && $0.envelopeTick == 1 }
        XCTAssertEqual(updatedEvent?.envelopeEnabled, true)
        XCTAssertEqual(updatedEvent?.envelopeValue ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(updatedEvent?.finalAppliedVolume ?? 0, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineAppliesFadeoutAfterKeyOff() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let envelope = PlaybackVolumeEnvelope(
            enabled: false,
            points: [],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0,
            fadeout: 32_768
        )
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 97),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(traceWriter.events.contains { $0.decisionReason == "key_off" && $0.noteValue == 97 })
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.5) < 0.0001 })
        XCTAssertTrue(traceWriter.events.contains { $0.fadeoutValue.map { abs($0 - 0.5) < 0.0001 } ?? false })
    }

    @MainActor
    func testPlaybackEngineAppliesSampleOffsetToTriggeredVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 1024), volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x02)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.sampleStartOffset, 512)
    }

    @MainActor
    func testPlaybackEngineRetriggersCurrentVoiceOnConfiguredTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.map(\.note), [49, 49])
    }

    @MainActor
    func testPlaybackEngineCutsNoteOnConfiguredTick() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC2),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
        XCTAssertEqual(audioOutput.stoppedChannels, [0])
    }

    @MainActor
    func testPlaybackEngineDelaysNoteUntilConfiguredTick() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)

        engine.advanceOneTick()
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)

        engine.advanceOneTick()
        XCTAssertEqual(audioOutput.triggeredRequests.map(\.note), [49])
    }

    @MainActor
    func testPlaybackEngineSkipsNoteDelayBeyondCurrentRowSpeed() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD3),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
    }

    @MainActor
    func testPlaybackEngineAppliesPatternDelayBeforeAdvancingRows() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0xE2),
                    makePlaybackRow(index: 1)
                ]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        for _ in 0..<5 {
            engine.advanceOneTick()
        }
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))

        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(positions, [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)
        ])
    }
}

private final class TestPlaybackTimingTraceClock: PlaybackTimingTraceClock, AdapterPlanProfileClock {
    private var currentNanoseconds: UInt64 = 0

    func nowNanoseconds() -> UInt64 {
        currentNanoseconds
    }

    func advance(milliseconds: Double) {
        currentNanoseconds += UInt64((milliseconds * 1_000_000).rounded())
    }
}

@MainActor
private final class TestPlaybackTimingTraceSink: PlaybackTimingTraceSinking {
    private(set) var lines = [String]()

    func writePlaybackTimingTraceLine(_ line: String) {
        lines.append(line)
    }
}

private final class TestAdapterPlanProfileSink: AdapterPlanProfileSinking {
    private(set) var lines = [String]()

    func writeAdapterPlanProfileLine(_ line: String) {
        lines.append(line)
    }
}

private func timingPhases(in lines: [String]) -> [String] {
    lines.compactMap { line in
        line.split(separator: " ").first { $0.hasPrefix("phase=") }?.dropFirst("phase=".count).description
    }
}

private func adapterPlanProfilePhases(in lines: [String]) -> [String] {
    lines.compactMap { line in
        line.split(separator: " ").first { $0.hasPrefix("phase=") }?.dropFirst("phase=".count).description
    }
}

private func timingPhases(in lines: [String], lifecycle: String) -> [String] {
    timingPhases(in: lines.filter { $0.contains("lifecycle=\(lifecycle)") })
}

private func timingField(in lines: [String], lifecycle: String, phase: String, key: String) -> String? {
    lines.reversed().compactMap { line -> String? in
        guard line.contains("lifecycle=\(lifecycle)"),
              line.contains("phase=\(phase)") else {
            return nil
        }
        return line.split(separator: " ").first { $0.hasPrefix("\(key)=") }?
            .dropFirst(key.count + 1)
            .description
    }.first
}

private func loadMultiPatternLoopBoundarySong() throws -> PlaybackSong {
    let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
    let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
    return try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
}

private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent("tests/reference-xm").appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(
            domain: "VoodooTrackerXTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing reference XM fixture at \(url.path)"]
        )
    }
    return url
}

@MainActor
private func advanceRows(_ rowCount: Int, engine: PlaybackEngine, timing: PlaybackTiming) {
    for _ in 0..<(max(0, rowCount) * timing.ticksPerRow) {
        engine.advanceOneTick()
    }
}

private func makeRuntimeAdapterPlaybackSong(patternIndex: Int) -> PlaybackSong {
    let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125], baseSampleRate: 100)
    return makePlaybackSong(
        orderPatternIndices: [patternIndex],
        patternRowsByIndex: [
            patternIndex: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1)
            ]
        ],
        instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
        initialTiming: PlaybackTiming(speed: 1, bpm: 250)
    )
}

private func makeEditablePatternLoopSong(notesByRow: [Int: UInt8], rowCount: Int = 4) -> PlaybackSong {
    let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125], baseSampleRate: 100)
    let rows = (0..<rowCount).map { rowIndex in
        makePlaybackRow(
            index: rowIndex,
            note: notesByRow[rowIndex] ?? 0,
            instrument: notesByRow[rowIndex] == nil ? 0 : 1
        )
    }
    return makePlaybackSong(
        orderPatternIndices: [0],
        patternRowsByIndex: [0: rows],
        instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
        initialTiming: PlaybackTiming(speed: 1, bpm: 25)
    )
}

private func noteTriggerNotes(in plan: RuntimeCMixerAdapterEventPlan) -> [UInt8] {
    plan.events.compactMap { event in
        guard case let .noteTrigger(_, _, mapping) = event.action else {
            return nil
        }
        return mapping.note
    }
}

private func makeDurationPlaybackSong(patternIndex: Int, rowCount: Int = 74) -> PlaybackSong {
    let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125], baseSampleRate: 100)
    let rows = (0..<rowCount).map { rowIndex in
        rowIndex == 0
            ? makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
            : makePlaybackRow(index: rowIndex)
    }
    return makePlaybackSong(
        orderPatternIndices: [patternIndex],
        patternRowsByIndex: [patternIndex: rows],
        instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
        initialTiming: PlaybackTiming(speed: 1, bpm: 1)
    )
}
