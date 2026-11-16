import Darwin
import Foundation
import XCTest

final class LoopEngineLifecycleTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["VTX_REQUIRE_LOOP_ASAN"] == "1" else { return }
        let handle = try XCTUnwrap(dlopen(nil, RTLD_NOW))
        defer { dlclose(handle) }
        XCTAssertNotNil(dlsym(handle, "__asan_init"))
        let images = (0..<_dyld_image_count()).compactMap { index -> String? in
            _dyld_get_image_name(index).map { String(cString: $0) }
        }
        XCTAssertTrue(images.contains { $0.contains("libclang_rt.asan_osx_dynamic") })
        let pid = ProcessInfo.processInfo.processIdentifier
        let marker = "VTX_LOOP_ASAN_RUNTIME_ACTIVE pid=\(pid)"
        print(marker)
        if let directory = ProcessInfo.processInfo.environment["VTX_LOOP_ASAN_EVIDENCE_ROOT"] {
            // Successful parallel XCTest output may be omitted from xcodebuild's
            // console; retain the same checked-runtime marker for PID correlation.
            let file = URL(fileURLWithPath: directory).appendingPathComponent("loop-\(pid).txt")
            try marker.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func song(note: UInt8 = 49, bpm: Int = 125) -> PlaybackSong {
        let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
            loopStart: 0, loopLength: 4, loopType: 1)
        return makePlaybackSong(orderPatternIndices: [0], patternRowsByIndex: [0: [
            makePlaybackRow(index: 0, note: note, instrument: 1), makePlaybackRow(index: 1),
            makePlaybackRow(index: 2, effectType: 1, effectParam: 1), makePlaybackRow(index: 3)]],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            initialTiming: .init(speed: 3, bpm: bpm))
    }

    @MainActor
    func testUnavailableQuiescentHeadRetainsAnExplicitlyTaggedLastKnownCoordinate() {
        for pauses in [false, true] {
            let output = TestRuntimeFollowAudioOutput()
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer { output.hasRuntimePlaybackHead = false; engine.stop(); engine.load(song: nil) }
            engine.load(song: song())
            let start = PlaybackStartContext(moduleTitle: "unavailable capture", songPosition: 0, patternIndex: 0, row: 0)
            engine.play(from: start)
            let follow = PlaybackFollowPosition(position: .init(orderIndex: 0, patternIndex: 0, rowIndex: 1),
                tickInRow: 1, source: .cMixerSampleTime, sampleTimeFrame: 4_000,
                sampleTimeStatus: "in_range", syntheticRow: 1)
            output.hasRuntimePlaybackHead = true
            output.playbackHeads = [.init(runtimeFrame: 4_000, follow: follow,
                timing: .init(speed: 3, bpm: 125), actualTickCount: 3)]
            engine.advanceOneTick()
            XCTAssertEqual(engine.state.context?.row, start.row, "The original explicit Play context still names row 0")
            output.captureOverride = .unavailable("test_host_stop_failure")
            if pauses { engine.pause() } else { engine.stop() }
            XCTAssertEqual(engine.currentPosition, follow.position)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.position, follow.position)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.sampleTimeFrame, 4_000)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.sampleTimeStatus, "capture_unavailable")
            XCTAssertEqual(engine.state.mode, pauses ? .paused : .stopped)
            if pauses {
                // Capture failed: resume from the tagged last-known row, without
                // reinterpreting that coordinate as a fresh quiescent audio head.
                XCTAssertEqual(engine.state.context?.songPosition, follow.position.orderIndex)
                XCTAssertEqual(engine.state.context?.patternIndex, follow.position.patternIndex)
                XCTAssertEqual(engine.state.context?.row, follow.position.rowIndex)
                XCTAssertNotEqual(engine.state.context?.row, start.row)
                XCTAssertEqual(engine.currentPublishedFollowPosition?.sampleTimeStatus, "capture_unavailable")
                engine.togglePlayPause(from: nil)
                XCTAssertTrue(engine.state.isPlaying)
                XCTAssertEqual(engine.currentPosition, follow.position)
            }
        }
    }

    @MainActor
    func testLiveHeadIsReadOnceAndMissingPacketNeverAdvancesTimerState() throws {
        let output = TestRuntimeFollowAudioOutput()
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
        defer {
            output.hasRuntimePlaybackHead = false
            engine.positionDidChange = nil; engine.playbackDidStop = nil
            engine.stop(); engine.load(song: nil)
        }
        engine.load(song: song())
        engine.play(from: nil)
        let followReads = output.followReadCount
        let diagnosticCount = output.recordedFollowEvents.count
        let first = PlaybackFollowPosition(position: .init(orderIndex: 0, patternIndex: 0, rowIndex: 1),
            tickInRow: 4, source: .cMixerSampleTime, sampleTimeFrame: 4_000,
            sampleTimeStatus: "in_range", syntheticRow: 1)
        let sameRowNextTick = PlaybackFollowPosition(position: first.position,
            tickInRow: 5, source: .cMixerSampleTime, sampleTimeFrame: 4_500,
            sampleTimeStatus: "in_range", syntheticRow: 1)
        let sameRowSameTick = PlaybackFollowPosition(position: first.position,
            tickInRow: 5, source: .cMixerSampleTime, sampleTimeFrame: 4_600,
            sampleTimeStatus: "in_range", syntheticRow: 1)
        let later = PlaybackFollowPosition(position: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2),
            tickInRow: 0, source: .cMixerSampleTime, sampleTimeFrame: 8_000,
            sampleTimeStatus: "in_range", syntheticRow: 2)
        let laterHead = RuntimeCMixerPlaybackHead(runtimeFrame: 8_000, follow: later,
            timing: .init(speed: 3, bpm: 125), actualTickCount: 3)
        output.hasRuntimePlaybackHead = true
        output.playbackHeads = [.init(runtimeFrame: 4_000, follow: first,
            timing: .init(speed: 5, bpm: 150), actualTickCount: 10),
            .init(runtimeFrame: 4_500, follow: sameRowNextTick,
                timing: .init(speed: 5, bpm: 150), actualTickCount: 10),
            .init(runtimeFrame: 4_600, follow: sameRowSameTick,
                timing: .init(speed: 5, bpm: 150), actualTickCount: 10), nil, laterHead]
        var shown = [PlaybackPosition]()
        engine.positionDidChange = { shown.append($0) }
        engine.advanceOneTick()
        XCTAssertEqual(output.playbackHeadReadCount, 1)
        XCTAssertEqual(output.followReadCount, followReads)
        XCTAssertEqual(engine.currentPosition, first.position)
        XCTAssertEqual(engine.currentPublishedFollowPosition, first)
        XCTAssertEqual(engine.timing, .init(speed: 5, bpm: 150))

        // A row-only observer must not redraw the tracker for elapsed ticks in
        // that row. The same coherent native head still owns exact follow/trace.
        engine.advanceOneTick()
        XCTAssertEqual(engine.currentPosition, first.position)
        XCTAssertEqual(engine.currentPublishedFollowPosition, sameRowNextTick)
        XCTAssertEqual(engine.currentPublishedFollowPosition?.tickInRow, 5)
        XCTAssertEqual(output.recordedFollowEvents.last?.position, sameRowNextTick)
        XCTAssertEqual(shown, [first.position], "Same-row tick changes are not new row notifications")
        engine.advanceOneTick()
        XCTAssertEqual(engine.currentPublishedFollowPosition, sameRowSameTick)
        XCTAssertEqual(output.recordedFollowEvents.last?.position, sameRowSameTick)
        XCTAssertEqual(shown, [first.position])

        engine.advanceOneTick() // An unavailable packet holds the last coherent head.
        XCTAssertEqual(engine.currentPosition, first.position)
        XCTAssertEqual(engine.currentPublishedFollowPosition, sameRowSameTick)
        XCTAssertEqual(output.recordedFollowEvents.count, diagnosticCount + 3)
        XCTAssertEqual(shown, [first.position])
        engine.advanceOneTick()
        XCTAssertEqual(output.playbackHeadReadCount, 5)
        XCTAssertEqual(output.followReadCount, followReads)
        XCTAssertEqual(engine.currentPosition, later.position)
        XCTAssertEqual(engine.currentPublishedFollowPosition, later)
        XCTAssertEqual(engine.timing, .init(speed: 3, bpm: 125))
        XCTAssertEqual(shown, [first.position, later.position])
        XCTAssertEqual(output.recordedFollowEvents.dropFirst(diagnosticCount).map(\.position),
            [first, sameRowNextTick, sameRowSameTick, later])

        // Stop has its own callback and exact capture. Forced explicit Play at
        // this same row must continue notifying even after ordinary deduplication.
        var stopped: PlaybackPosition?
        engine.playbackDidStop = { stopped = engine.currentPosition }
        output.captureOverride = .captured(laterHead)
        engine.stop()
        XCTAssertEqual(stopped, later.position)
        XCTAssertEqual(engine.currentPublishedFollowPosition, later)
        let beforeForcedPlay = shown.count
        output.hasRuntimePlaybackHead = false
        engine.play(from: .init(moduleTitle: "forced same-row start", songPosition: 0, patternIndex: 0, row: 2))
        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertEqual(engine.currentPosition, later.position)
        XCTAssertGreaterThan(shown.count, beforeForcedPlay, "Explicit startup keeps notifyDuplicatePositions:true")
        XCTAssertEqual(shown.last, later.position)
    }

    @MainActor
    func testFollowDiagnosticReentryCannotPublishRetiredPositionToUI() {
        let output = TestRuntimeFollowAudioOutput()
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
        defer { output.didRecordFollow = nil; engine.stop(); engine.load(song: nil) }
        engine.load(song: song())
        engine.play(from: nil)
        let replacement = song(note: 57)
        var shown = [PlaybackPosition]()
        engine.positionDidChange = { shown.append($0) }
        output.didRecordFollow = {
            output.didRecordFollow = nil
            engine.load(song: replacement, startContext: .init(moduleTitle: nil,
                songPosition: 0, patternIndex: 0, row: 3))
        }
        // Legacy outputs also pass through the value-taking publication guard.
        for _ in 0..<3 { engine.advanceOneTick() }
        XCTAssertEqual(engine.song, replacement)
        XCTAssertEqual(engine.currentPosition?.rowIndex, 3)
        XCTAssertEqual(engine.currentPublishedFollowPosition?.position.rowIndex, 3)
        XCTAssertTrue(shown.isEmpty)
    }

    @MainActor
    func testStopAndPauseCaptureActualNativeLoopHeadWithoutUITimer() throws {
        for loopEnabled in [false, true] { for pauses in [false, true] {
            let recorder = LoopRestartTraceRecorder()
            let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
                startsOutputHostOnDemand: false, traceWriter: recorder)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer {
                engine.positionDidChange = nil; engine.playbackDidStop = nil
                engine.stop(); engine.load(song: nil)
            }
            var shown = [PlaybackPosition]()
            var stopped: PlaybackPosition?
            engine.positionDidChange = { shown.append($0) }
            engine.playbackDidStop = { stopped = engine.currentPosition }
            engine.load(song: song(), loopEnabled: loopEnabled)
            engine.play(from: nil, loopEnabled: loopEnabled, timingSession: nil)
            XCTAssertEqual(engine.currentPosition?.rowIndex, 0)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.position.rowIndex, 0)
            XCTAssertTrue(output.renderForTesting(frameCount: 4_000).contains { $0 != 0 })
            let head = try XCTUnwrap(output.runtimePlaybackHead())
            let actual = head.follow
            XCTAssertEqual(head.runtimeFrame, 4_000)
            XCTAssertEqual(actual.position.rowIndex, 1)
            XCTAssertEqual(actual.tickInRow, 1)
            // No main timer or explicit service tick has brought the UI forward.
            XCTAssertEqual(engine.currentPosition?.rowIndex, 0)
            if pauses { engine.pause() } else { engine.stop() }
            XCTAssertEqual(engine.state.mode, pauses ? .paused : .stopped)
            XCTAssertEqual(engine.currentPosition, actual.position)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.position, actual.position)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.source, .cMixerSampleTime)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.sampleTimeFrame, 4_000)
            if pauses { XCTAssertEqual(shown.last, actual.position) }
            else { XCTAssertEqual(stopped, actual.position) }
            let clear = try XCTUnwrap(recorder.events.last { $0.runtimeAction == "c_mixer_clear_all" })
            XCTAssertEqual(clear.rowIndex, actual.position.rowIndex)
            XCTAssertEqual(clear.tickInRow, actual.tickInRow)
            XCTAssertFalse(output.hasRuntimeUserLoop)
        } }
    }

    @MainActor
    func testActualPlannedCMixerTickUsesOneRenderedHeadForLoopAndNormalPlay() throws {
        for loopEnabled in [false, true] {
            let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
                startsOutputHostOnDemand: false)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer { engine.stop(); engine.load(song: nil) }
            let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
                loopStart: 0, loopLength: 4, loopType: 1)
            let source = makePlaybackSong(orderPatternIndices: [0], patternRowsByIndex: [0: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0F, effectParam: 5),
                makePlaybackRow(index: 2), makePlaybackRow(index: 3)]],
                instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
                initialTiming: .init(speed: 3, bpm: 125))
            engine.load(song: source, loopEnabled: loopEnabled)
            engine.play(from: nil, loopEnabled: loopEnabled, timingSession: nil)
            _ = output.renderForTesting(frameCount: 4_000)
            engine.advanceOneTick()
            XCTAssertEqual(engine.currentPosition?.rowIndex, 1)
            XCTAssertEqual(engine.timing.speed, 5)
            XCTAssertEqual(engine.timing.bpm, 125)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.position, engine.currentPosition)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.tickInRow, 1)
            XCTAssertEqual(engine.currentPublishedFollowPosition?.sampleTimeFrame, 4_000)
        }
    }

    @MainActor
    func testPauseNativeHeadPublicationCannotOverwriteNewerLoad() throws {
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
            startsOutputHostOnDemand: false)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
        defer { engine.positionDidChange = nil; engine.stop(); engine.load(song: nil) }
        engine.load(song: song(), loopEnabled: true)
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        _ = output.renderForTesting(frameCount: 4_000)
        let replacement = song(note: 57)
        let desired = PlaybackStartContext(moduleTitle: "replacement", songPosition: 0, patternIndex: 0, row: 3)
        var replaced = false
        engine.positionDidChange = { _ in
            guard !replaced else { return }
            replaced = true
            engine.load(song: replacement, startContext: desired)
        }
        engine.pause()
        XCTAssertTrue(replaced)
        XCTAssertEqual(engine.song, replacement)
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertEqual(engine.currentPosition?.rowIndex, 3)
        XCTAssertEqual(engine.currentPublishedFollowPosition?.position.rowIndex, 3)
        XCTAssertFalse(output.hasRuntimeUserLoop)
    }

    @MainActor
    func testNormalSongEndTimerOnlyStopsAfterActualNativeTailDeadline() throws {
        let rate = 48_000.0
        let environment = [RuntimeCMixerSongEndTailPolicy.tailSecondsEnvironmentKey: "0.005"]
        let tail = RuntimeCMixerSongEndTailPolicy.resolve(environment: environment)
        let output = RuntimeCMixerAudioEngine(sampleRate: rate, channelCount: 1,
            songEndTailPolicy: tail, startsOutputHostOnDemand: false)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false, environment: environment)
        defer { engine.stop(); engine.load(song: nil) }
        let source = song()
        let inspection = RuntimeCMixerAdapterEventPlan.make(song: source, sampleRate: rate)
        let end = try XCTUnwrap(inspection.plannedSongEndFrame)
        let deadline = end + tail.tailFrames(sampleRate: rate)
        XCTAssertGreaterThan(deadline, 1_000)
        engine.load(song: source)
        engine.play(from: nil, loopEnabled: false, timingSession: nil)
        _ = output.renderForTesting(frameCount: 1_000)
        // A wall timer waking ahead of native delivery cannot end the song.
        engine.finishRuntimeCMixerSongEndTailForTesting()
        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertTrue(engine.isRuntimeCMixerSongEndStopPendingForTesting)
        var remaining = deadline - 1_000
        while remaining > 0 {
            let count = min(remaining, 4_096)
            _ = output.renderForTesting(frameCount: count)
            remaining -= count
        }
        engine.finishRuntimeCMixerSongEndTailForTesting()
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertEqual(engine.currentPosition?.rowIndex, 3)
    }

    @MainActor
    func testActualCHeadResolvesExactRowHeldFxxAndJumpBoundaries() throws {
        func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
            .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
        }
        let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
            loopStart: 0, loopLength: 4, loopType: 1)
        let source = makePlaybackSong(orderPatternIndices: [0, 1], patternRowsByIndex: [
            0: [.init(index: 0, cells: [cell(note: 49, instrument: 1)]),
                .init(index: 1, cells: [cell(0x0F, 2), cell(0x0E, 0xE1)]),
                .init(index: 2, cells: [cell(0x0D, 2)]), .init(index: 3, cells: [cell()])],
            1: [makePlaybackRow(index: 0), makePlaybackRow(index: 1),
                makePlaybackRow(index: 2, note: 52, instrument: 1), makePlaybackRow(index: 3)]],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            initialTiming: .init(speed: 3, bpm: 125))
        for loopEnabled in [false, true] {
            let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
                startsOutputHostOnDemand: false)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer { engine.stop(); engine.load(song: nil) }
            engine.load(song: source, loopEnabled: loopEnabled)
            engine.play(from: nil, loopEnabled: loopEnabled, timingSession: nil)
            // Frame, source order/row, elapsed tick, effective speed, actual held ticks.
            let points: [(Int, Int, Int, Int, Int, Int)] = [
                (2_879, 0, 0, 2, 3, 3), (2_880, 0, 1, 0, 2, 4),
                (5_759, 0, 1, 2, 2, 4), (5_760, 0, 1, 3, 2, 4),
                (6_719, 0, 1, 3, 2, 4), (6_720, 0, 2, 0, 2, 2),
                (8_639, 0, 2, 1, 2, 2),
                (8_640, loopEnabled ? 0 : 1, loopEnabled ? 0 : 2, 0, 2, 2)]
            var rendered = 0
            for (frame, order, row, tick, speed, ticks) in points {
                _ = output.renderForTesting(frameCount: frame - rendered); rendered = frame
                let head = try XCTUnwrap(output.runtimePlaybackHead())
                XCTAssertEqual(head.runtimeFrame, UInt64(frame))
                XCTAssertEqual(head.follow.position.orderIndex, order)
                XCTAssertEqual(head.follow.position.patternIndex, order)
                XCTAssertEqual(head.follow.position.rowIndex, row)
                XCTAssertEqual(head.follow.tickInRow, tick)
                XCTAssertEqual(head.timing.speed, speed)
                XCTAssertEqual(head.actualTickCount, ticks)
                engine.advanceOneTick()
                XCTAssertEqual(engine.currentPosition, head.follow.position)
                XCTAssertEqual(engine.currentPublishedFollowPosition, head.follow)
                XCTAssertEqual(engine.timing, head.timing)
            }
        }
    }

    @MainActor
    func testNormalSelectedColdOriginWaitsForItsActualTailDeadlineAndKeepsMappedFrameMeaning() throws {
        let rate = 48_000.0
        let environment = [RuntimeCMixerSongEndTailPolicy.tailSecondsEnvironmentKey: "0.005"]
        let tail = RuntimeCMixerSongEndTailPolicy.resolve(environment: environment)
        let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
            loopStart: 0, loopLength: 4, loopType: 1)
        let rows = (0..<4).map { makePlaybackRow(index: $0, note: $0 == 0 ? 49 : 0, instrument: $0 == 0 ? 1 : 0) }
        let source = makePlaybackSong(orderPatternIndices: [0, 1], patternRowsByIndex: [0: rows, 1: rows],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            initialTiming: .init(speed: 3, bpm: 125))
        let origin = try XCTUnwrap(source.position(orderIndex: 1, rowIndex: 2))
        let context = PlaybackStartContext(moduleTitle: "selected", songPosition: 1, patternIndex: 1, row: 2)
        let output = RuntimeCMixerAudioEngine(sampleRate: rate, channelCount: 1,
            songEndTailPolicy: tail, startsOutputHostOnDemand: false)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false, environment: environment)
        defer { engine.stop(); engine.load(song: nil) }
        let selected = RuntimeCMixerAdapterEventPlan.make(song: source, sampleRate: rate, initialPosition: origin)
        let end = try XCTUnwrap(selected.plannedSongEndFrame)
        let deadline = end + tail.tailFrames(sampleRate: rate)
        engine.load(song: source, startContext: context)
        engine.play(from: context, loopEnabled: false, timingSession: nil)
        XCTAssertEqual(try XCTUnwrap(engine.runtimeAdapterPlanDurationSeconds), Double(end) / rate, accuracy: 1e-12)
        var remaining = deadline - 1
        while remaining > 0 {
            let count = min(remaining, 4_096); _ = output.renderForTesting(frameCount: count); remaining -= count
        }
        engine.finishRuntimeCMixerSongEndTailForTesting()
        XCTAssertTrue(engine.state.isPlaying)
        _ = output.renderForTesting(frameCount: 1)
        engine.finishRuntimeCMixerSongEndTailForTesting()
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertEqual(engine.currentPosition?.orderIndex, 1)
        XCTAssertEqual(engine.currentPosition?.rowIndex, 3)

        // The retained full-plan/range API maps raw frame zero into a nonzero plan coordinate.
        let ranged = RuntimeCMixerAudioEngine(sampleRate: rate, channelCount: 1,
            songEndTailPolicy: tail, startsOutputHostOnDemand: false)
        defer { ranged.stopAll() }
        let full = RuntimeCMixerAdapterEventPlan.make(song: source, sampleRate: rate)
        ranged.configureRuntimeAdapterEventPlan(full, generationMS: nil, timingSession: nil)
        ranged.consumeRuntimeAdapterEvents(context: .init(orderIndex: 1, patternIndex: 1, rowIndex: 2, tickInRow: 0),
            patternLoopRange: nil, timingSession: nil)
        let mapped = try XCTUnwrap(ranged.runtimePlaybackHead())
        XCTAssertEqual(mapped.runtimeFrame, 0)
        XCTAssertGreaterThan(try XCTUnwrap(mapped.follow.sampleTimeFrame), 0)
        XCTAssertEqual(mapped.follow.position, origin)
        guard case .captured(let rangedCapture) = ranged.quiesceAndCaptureRuntimePlaybackHead() else {
            return XCTFail("Expected the quiescent mapped native head")
        }
        XCTAssertEqual(rangedCapture.follow, mapped.follow)
    }

    @MainActor
    func testCompletedNativeFaultCaptureMarksTerminalMusicalCoordinateAndExactRawHead() throws {
        let queue = DispatchQueue(label: "public.loop.terminal.capture")
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
            startsOutputHostOnDemand: false)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: DispatchQueueRuntimeAdapterPlanPrewarmScheduler(workerQueue: queue))
        let release = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        var released = false
        defer { if !released { release.signal() }; engine.stop(); engine.load(song: nil) }
        var failure: RuntimeLoopNativeDeliveryFault?
        engine.userLoopPlaybackDidFail = { if case let .planning(value, _) = $0 { failure = value } }
        engine.load(song: song(), loopEnabled: true)
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        queue.async { entered.signal(); release.wait() }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        for _ in 0..<188 { _ = output.renderForTesting(frameCount: 512) }
        let live = try XCTUnwrap(output.runtimePlaybackHead())
        guard case .captured(let captured) = output.quiesceAndCaptureRuntimePlaybackHead() else {
            return XCTFail("Expected the quiescent terminal native head")
        }
        let native = try XCTUnwrap(output.runtimeUserLoopPosition())
        XCTAssertEqual(live.follow.sampleTimeStatus, "terminal")
        XCTAssertTrue(native.isTerminal)
        XCTAssertEqual(captured.runtimeFrame, live.runtimeFrame)
        XCTAssertEqual(captured.follow, live.follow)
        release.signal(); released = true
        engine.advanceOneTick()
        let observed = try XCTUnwrap(failure)
        XCTAssertEqual(observed.reason, .missingSuccessor)
        XCTAssertEqual(captured.runtimeFrame, observed.retirementEndFrame)
        XCTAssertEqual(native.rowEndFrame, Int(observed.boundaryFrame))
        XCTAssertEqual(engine.currentPosition, captured.follow.position)
        XCTAssertEqual(engine.currentPublishedFollowPosition?.sampleTimeStatus, "terminal")
        XCTAssertEqual(engine.state.mode, .stopped)
    }

    @MainActor
    func testPauseResumeContextUsesCapturedNativeRow() throws {
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
            startsOutputHostOnDemand: false)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
        defer { engine.stop(); engine.load(song: nil) }
        engine.load(song: song(), loopEnabled: true)
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        _ = output.renderForTesting(frameCount: 4_000)
        engine.pause()
        XCTAssertEqual(engine.state.context?.row, 1)
        engine.togglePlayPause(from: nil)
        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertEqual(engine.currentPosition?.rowIndex, 1)
        XCTAssertEqual(engine.currentPublishedFollowPosition?.position.rowIndex, 1)
    }

    @MainActor
    func testActualHostCoalescesEditsWithoutMainActorAcknowledgementThenColdSeeksAndReturnsToNormal() throws {
        for rate in [44_100.0, 48_000] {
            let output = RuntimeCMixerAudioEngine(sampleRate: rate, channelCount: 1)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer { engine.stop(); engine.load(song: nil) }
            let context = PlaybackStartContext(moduleTitle: "test", songPosition: 0, patternIndex: 0, row: 2)
            let initial = song(), obsolete = song(note: 50), desired = song(note: 52)
            var faults = [RuntimeUserLoopPlaybackFailure]()
            engine.userLoopPlaybackDidFail = { faults.append($0) }
            engine.load(song: initial, startContext: context, loopEnabled: true)
            engine.play(from: context, loopEnabled: true, timingSession: nil)
            XCTAssertTrue(output.hasRuntimeUserLoop)
            let progressAtStart = output.hostProgressForTesting()
            engine.requestEditablePatternLoopRefresh(song: obsolete)
            engine.requestEditablePatternLoopRefresh(song: desired)
            // Delivery and the same serial producer must admit without a MainActor tick.
            let progressDeadline = Date(timeIntervalSinceNow: 10)
            while Date() < progressDeadline {
                if let position = output.runtimeUserLoopPosition(), position.nativeFrame > UInt64(rate) { break }
                Thread.sleep(forTimeInterval: 0.001)
            }
            let progressAtDeadline = output.hostProgressForTesting()
            XCTAssertNil(output.consumeRuntimeUserLoopFailure())
            engine.advanceOneTick()
            XCTAssertEqual(engine.song, desired)
            XCTAssertTrue(engine.state.isPlaying)
            XCTAssertTrue(faults.isEmpty)
            let before = try XCTUnwrap(output.runtimeUserLoopPosition()).nativeFrame
            if before <= UInt64(rate) {
                // Preserve the primary failure's live observations first. A full
                // snapshot is safe only after host stop; normal assertions and
                // existing deferred engine cleanup still run below.
                let quiescent = output.quiescedSnapshotForTesting()
                let diagnostic = """
                sampleRate=\(rate)
                start=\(progressAtStart)
                deadline=\(progressAtDeadline)
                afterHostStop=\(output.hostProgressForTesting())
                quiescent=\(String(reflecting: quiescent))
                """
                let attachment = XCTAttachment(string: diagnostic)
                attachment.name = "native-host-progress-\(Int(rate))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertGreaterThan(before, UInt64(rate), "Native playback did not advance through one second within the bounded wait")
            let selected = engine.seek(to: .init(orderIndex: 0, rowIndex: 1, tickInRow: 0), autoplay: true)
            XCTAssertEqual(selected?.rowIndex, 1)
            XCTAssertTrue(output.hasRuntimeUserLoop)
            Thread.sleep(forTimeInterval: 0.04)
            XCTAssertLessThan(try XCTUnwrap(output.runtimeUserLoopPosition()).nativeFrame, before)
            engine.pause()
            XCTAssertFalse(output.hasRuntimeUserLoop)
            XCTAssertEqual(engine.state.mode, .paused)
            engine.play(from: context, loopEnabled: true, timingSession: nil)
            XCTAssertTrue(output.hasRuntimeUserLoop)
            engine.stop()
            engine.prepare(from: context, loopEnabled: false)
            engine.play(from: context, loopEnabled: false, timingSession: nil)
            XCTAssertFalse(output.hasRuntimeUserLoop)
            XCTAssertTrue(output.hasRuntimeAdapterEventPlan)
            XCTAssertFalse(engine.isPatternLoopPlaybackActive)
            XCTAssertTrue(faults.isEmpty)
        }
    }

    @MainActor
    func testIncompatibleLiveTempoUsesTypedStopAndFreshPlayThenLoadCancelsOldGeneration() throws {
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
        defer { engine.stop(); engine.load(song: nil) }
        let context = PlaybackStartContext(moduleTitle: "test", songPosition: 0, patternIndex: 0, row: 0)
        var faults = [RuntimeUserLoopPlaybackFailure]()
        engine.userLoopPlaybackDidFail = { faults.append($0) }
        engine.load(song: song(), startContext: context, loopEnabled: true)
        engine.play(from: context, loopEnabled: true, timingSession: nil)
        let replacement = song(bpm: 127)
        engine.requestEditablePatternLoopRefresh(song: replacement)
        Thread.sleep(forTimeInterval: 0.05)
        engine.advanceOneTick()
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertFalse(output.hasRuntimeUserLoop)
        XCTAssertEqual(faults.count, 1)
        if case let .refresh(_, reason) = faults.first { XCTAssertEqual(reason, .stoppedReloadRequired) }
        else { XCTFail("Expected explicit stopped reload, not an underrun") }
        XCTAssertEqual(engine.song, replacement)
        engine.play(from: context, loopEnabled: true, timingSession: nil)
        XCTAssertTrue(output.hasRuntimeUserLoop)
        engine.requestEditablePatternLoopRefresh(song: song(note: 54, bpm: 127))
        engine.load(song: song(note: 57), startContext: context, loopEnabled: true)
        engine.play(from: context, loopEnabled: true, timingSession: nil)
        Thread.sleep(forTimeInterval: 0.6)
        engine.advanceOneTick()
        XCTAssertEqual(engine.song, song(note: 57))
        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertEqual(faults.count, 1)
    }

    @MainActor
    func testRefusedRefreshStopObserverCanLoadAndPlayANewerSong() throws {
        for replay in [false, true] {
            let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
                startsOutputHostOnDemand: false)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer {
                engine.playbackDidStop = nil
                engine.stop(); engine.load(song: nil)
            }
            let original = song(), refused = song(bpm: 127), newer = song(note: 57, bpm: 143)
            var faults = [RuntimeUserLoopPlaybackFailure]()
            engine.userLoopPlaybackDidFail = { faults.append($0) }
            engine.load(song: original, loopEnabled: true)
            engine.play(from: nil, loopEnabled: true, timingSession: nil)
            engine.requestEditablePatternLoopRefresh(song: refused)
            let deadline = Date(timeIntervalSinceNow: 5)
            while Date() < deadline {
                if case .refused = engine.userLoopRefreshStatusForTesting { break }
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard case .refused = engine.userLoopRefreshStatusForTesting else {
                return XCTFail("Expected incompatible tempo refusal before servicing Stop")
            }
            var stopped = 0
            engine.playbackDidStop = {
                stopped += 1
                engine.load(song: newer, loopEnabled: true)
                if replay { engine.play(from: nil, loopEnabled: true, timingSession: nil) }
            }

            engine.advanceOneTick()

            XCTAssertEqual(stopped, 1)
            XCTAssertEqual(engine.song, newer, "The old refusal must not replace a newer loaded source")
            XCTAssertEqual(engine.state.mode, replay ? .playing : .stopped)
            XCTAssertEqual(output.hasRuntimeUserLoop, replay)
            XCTAssertTrue(faults.isEmpty, "The old refusal must not alert against the newer source")
            if replay {
                XCTAssertTrue(output.renderForTesting(frameCount: 128).contains { $0 != 0 })
                engine.advanceOneTick()
                XCTAssertEqual(engine.song, newer)
                XCTAssertEqual(engine.timing.bpm, 143)
                XCTAssertTrue(engine.state.isPlaying)
                XCTAssertTrue(faults.isEmpty)
            }
        }
    }

    @MainActor
    func testBlockedActualProducerStopsAfterNativeRetirementAndRejectsLateWork() throws {
        let queue = DispatchQueue(label: "public.loop.blocked.producer")
        let scheduler = DispatchQueueRuntimeAdapterPlanPrewarmScheduler(workerQueue: queue)
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: scheduler)
        let release = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        var didRelease = false
        defer {
            if !didRelease { release.signal() }
            engine.stop(); engine.load(song: nil)
        }
        var faults = [RuntimeUserLoopPlaybackFailure]()
        engine.userLoopPlaybackDidFail = { faults.append($0) }
        engine.load(song: song(), loopEnabled: true)
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        queue.async { entered.signal(); release.wait() }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        // Both initial batches execute, then the real deadline owns its C fade.
        // MainActor neither acknowledges nor services the failure during this interval.
        // Sanitizer/host scheduling can delay delivery; qualify actual native
        // retirement completion while the worker remains blocked, not wall time.
        // This cold session has no rebase: production batch storage gives local
        // and native frames the same origin, so row end is the fault boundary.
        let retirementDeadline = Date(timeIntervalSinceNow: 10)
        var completedRetirement: RuntimeLoopNativeFollowSnapshot?
        while Date() < retirementDeadline {
            if let position = output.runtimeUserLoopPosition(), position.isTerminal,
               position.rowEndFrame >= 0,
               position.nativeFrame >= UInt64(position.rowEndFrame) + 240 {
                completedRetirement = position
                break
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertNotNil(completedRetirement,
            "Native retirement did not complete: \(String(describing: output.runtimeUserLoopPosition()))")
        release.signal(); didRelease = true
        engine.advanceOneTick()
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertFalse(output.hasRuntimeUserLoop)
        XCTAssertEqual(faults.count, 1)
        if case let .planning(fault, _) = faults.first {
            XCTAssertEqual(fault.reason, .missingSuccessor)
            XCTAssertEqual(fault.retirementEndFrame - fault.boundaryFrame, 240)
        } else { XCTFail("Expected the exact native missing-successor fault") }
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        Thread.sleep(forTimeInterval: 0.05)
        engine.advanceOneTick()
        XCTAssertTrue(engine.state.isPlaying)
        XCTAssertEqual(faults.count, 1)
    }


    @MainActor
    func testPauseAdoptsNativeEditEvenWhenWorkerAcknowledgementAndMainServiceAreDelayed() throws {
        let queue = DispatchQueue(label: "public.loop.delayed.admission.receipt")
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1)
        let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: DispatchQueueRuntimeAdapterPlanPrewarmScheduler(workerQueue: queue))
        let release = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        var releaseScheduled = false
        defer {
            if !releaseScheduled { release.signal() }
            engine.stop(); engine.load(song: nil)
        }
        engine.load(song: song(), loopEnabled: true)
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        let firstCallbackDeadline = Date(timeIntervalSinceNow: 2)
        while output.runtimeUserLoopPosition() == nil, Date() < firstCallbackDeadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertNotNil(output.runtimeUserLoopPosition())
        let edited = song(note: 54)
        engine.requestEditablePatternLoopRefresh(song: edited)
        let deadline = Date(timeIntervalSinceNow: 2)
        var boundary: UInt64?
        while Date() < deadline {
            if case let .published(_, frame) = engine.userLoopRefreshStatusForTesting { boundary = frame; break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        let admittedAt = try XCTUnwrap(boundary)
        queue.async { entered.signal(); release.wait() }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let frame = try XCTUnwrap(output.runtimeUserLoopPosition()).nativeFrame
        XCTAssertLessThan(frame, admittedAt)
        // Audio admits the already-ready edit; neither worker nor UI can reconcile it.
        Thread.sleep(forTimeInterval: Double(admittedAt - frame) / 48_000 + 0.03)
        XCTAssertNil(output.consumeRuntimeUserLoopFailure())
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { release.signal() }
        releaseScheduled = true
        engine.pause() // Quiescence/join must preserve the final actually admitted source.
        XCTAssertEqual(engine.song, edited)
        XCTAssertEqual(engine.state.mode, .paused)
        engine.play(from: nil, loopEnabled: true, timingSession: nil)
        XCTAssertEqual(engine.song, edited)
        XCTAssertTrue(output.hasRuntimeUserLoop)
    }


    @MainActor
    func testPauseReplayCreatesFreshNativeBirthScopeWithoutChangingPlanLocalIDs() throws {
        for rate in [44_100.0, 48_000] { for linear in [true, false] {
            let recorder = LoopRestartTraceRecorder()
            let output = RuntimeCMixerAudioEngine(sampleRate: rate, channelCount: 1,
                startsOutputHostOnDemand: false, traceWriter: recorder)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer { engine.stop(); engine.load(song: nil) }
            let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
                loopStart: 0, loopLength: 4, loopType: 1)
            let toneSong = makePlaybackSong(orderPatternIndices: [0], patternRowsByIndex: [0: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 52, instrument: 1, volumeColumn: 0xB3, effectType: 3, effectParam: 3),
                makePlaybackRow(index: 2, volumeColumn: 0xB0, effectType: 3, effectParam: 0), makePlaybackRow(index: 3)]],
                instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
                initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
            engine.load(song: toneSong, loopEnabled: true)
            engine.play(from: nil, loopEnabled: true, timingSession: nil)
            XCTAssertTrue(output.renderForTesting(frameCount: 128).contains { $0 != 0 })
            engine.pause()
            let first = try XCTUnwrap(recorder.events.compactMap(\.loopOccurrence).first { $0.opcode == 0 })
            XCTAssertEqual(engine.state.mode, .paused)
            engine.play(from: nil, loopEnabled: true, timingSession: nil)
            XCTAssertTrue(output.renderForTesting(frameCount: 128).contains { $0 != 0 })
            engine.stop()
            let births = recorder.events.compactMap(\.loopOccurrence).filter { $0.opcode == 0 }
            let second = try XCTUnwrap(births.last)
            XCTAssertGreaterThan(births.count, 1)
            XCTAssertEqual(first.eventID, second.eventID)
            XCTAssertEqual(first.localSourceIndex, second.localSourceIndex)
            XCTAssertEqual(first.batchSequence, second.batchSequence)
            XCTAssertEqual(first.scope.sourceGeneration, second.scope.sourceGeneration)
            XCTAssertNotEqual(first.scope.transportEpoch, second.scope.transportEpoch)
            XCTAssertNotEqual(first.targetBirth, second.targetBirth)
        } }
    }

    @MainActor
    func testFirstFollowObserverCanReplacePendingLoopStartWithPlaySeekOrStop() throws {
        for request in 0..<3 {
            let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
                startsOutputHostOnDemand: false)
            let engine = PlaybackEngine(audioEngine: output, startsRealtimeTimer: false)
            defer { engine.stop(); engine.load(song: nil) }
            let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
                loopStart: 0, loopLength: 4, loopType: 1)
            let reentrantSong = makePlaybackSong(orderPatternIndices: [0], patternRowsByIndex: [0: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0F, effectParam: 1),
                makePlaybackRow(index: 1, note: 52, instrument: 1, effectType: 0x0F, effectParam: 5)]],
                instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
                initialTiming: .init(speed: 3, bpm: 125))
            engine.load(song: reentrantSong, loopEnabled: true)
            var didReenter = false
            engine.positionDidChange = { _ in
                guard !didReenter else { return }
                didReenter = true
                switch request {
                case 0: engine.play(from: nil, loopEnabled: true, timingSession: nil)
                case 1: _ = engine.seek(to: .init(orderIndex: 0, rowIndex: 1, tickInRow: 0), autoplay: true)
                default: engine.stop()
                }
            }
            engine.play(from: nil, loopEnabled: true, timingSession: nil)
            XCTAssertTrue(didReenter)
            if request == 2 {
                XCTAssertEqual(engine.state.mode, .stopped)
                XCTAssertFalse(output.hasRuntimeUserLoop)
                XCTAssertTrue(output.renderForTesting(frameCount: 128).allSatisfy { $0 == 0 })
            } else {
                XCTAssertTrue(engine.state.isPlaying)
                XCTAssertTrue(output.hasRuntimeUserLoop)
                let pcm = output.renderForTesting(frameCount: 128)
                XCTAssertNil(output.consumeRuntimeUserLoopFailure())
                if request == 0 { XCTAssertTrue(pcm.contains { $0 != 0 }) }
                else {
                    XCTAssertEqual(engine.currentPosition?.rowIndex, 1)
                    XCTAssertEqual(engine.timing.speed, 5)
                }
                engine.advanceOneTick()
                XCTAssertTrue(engine.state.isPlaying)
            }
        }
    }

}


@MainActor
private final class LoopRestartTraceRecorder: RuntimeCMixerTraceWriting {
    let isEnabled = true
    var events = [RuntimeCMixerTraceEvent]()
    func record(_ event: RuntimeCMixerTraceEvent) { events.append(event) }
    func flush() {}
}
