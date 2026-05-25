import AppKit
import AudioToolbox
import XCTest

final class PlaybackEngineTests: XCTestCase {
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
