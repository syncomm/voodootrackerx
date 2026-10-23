import MixerCore
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class NonretriggeringResetTests: XCTestCase {
    private let all = MixerPlaybackReset(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true)

    func testEveryResetDimensionIsIndependentAndPreservesSourceIdentity() {
        for mask in UInt32(1)...15 {
            let probe = ResetProbe()
            _ = probe.render(7)
            let before = probe.voice
            XCTAssertEqual(before.ping_pong_direction, -1)
            XCTAssertNotEqual(before.sample_position.rounded(.down), before.sample_position)
            XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 7, mask), VTX_C_MIXER_STATUS_OK)
            let pcm = probe.render(1)
            let after = probe.voice
            let keyed = mask & 4 != 0
            let fade: Float = mask & 8 != 0 ? 1 : before.fadeout_value
            XCTAssertEqual(after.key_on, keyed ? 1 : 0)
            XCTAssertEqual(after.fadeout_value, fade - (keyed ? 0 : 0.0625))
            XCTAssertEqual(after.volume_envelope.position_frame, mask & 1 != 0 ? 1 : before.volume_envelope.position_frame + 1)
            XCTAssertEqual(after.pan_envelope.position_frame, mask & 2 != 0 ? 1 : (keyed ? 3 : before.pan_envelope.position_frame + 1))
            XCTAssertEqual(after.sample_position, before.sample_position - 0.75)
            XCTAssertEqual(after.sample_pcm, before.sample_pcm)
            XCTAssertEqual(after.sample_step, before.sample_step)
            XCTAssertEqual(after.ping_pong_direction, before.ping_pong_direction)
            XCTAssertEqual(after.loop_mode, before.loop_mode)
            XCTAssertEqual(after.loop_start_frame, before.loop_start_frame)
            XCTAssertEqual(after.loop_end_frame, before.loop_end_frame)
            XCTAssertEqual(after.gain, before.gain)
            XCTAssertEqual(after.pan, before.pan)
            XCTAssertEqual(after.active, 1)
            XCTAssertEqual(probe.state.voice_count, 1)
            if mask & 1 != 0 {
                XCTAssertEqual(pcm, [Float(before.sample_position / 8) * 0.25 * fade])
            }
        }
    }

    func testResetRekeysSustainAndLaterReleaseStillFires() throws {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 100, channelCount: 1))
        let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 1, count: 32)),
            volumeEnvelope: .init(points: [.init(positionFrame: 0, value: 0.25), .init(positionFrame: 2, value: 0.75)], sustainFrame: 2),
            keyOffFrame: 1, fadeoutFrameDecrement: 0.125)
        XCTAssertTrue(mixer.schedulePlaybackStateChange(.reset(all), voiceIndex: voice, scheduledFrame: 3).wasAccepted)
        XCTAssertTrue(mixer.schedulePlaybackStateChange(.keyOff(fadeoutDecrement: 0.125), voiceIndex: voice, scheduledFrame: 7).wasAccepted)
        _ = mixer.render(frames: 3)
        XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice)).keyOn)
        XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [0.25])
        let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
        XCTAssertTrue(after.keyOn)
        XCTAssertEqual(after.fadeoutValue, 1)
        XCTAssertEqual(after.volumeEnvelopePositionFrame, 1)
        XCTAssertEqual(mixer.render(frames: 3).interleavedPCM, [0.5, 0.75, 0.75])
        _ = mixer.render(frames: 1)
        XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice)).keyOn)
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.fadeoutValue, 0.875)
    }

    func testFutureLegacyKeyOffSurvivesResetIncludingSameFrame() {
        for frame in [3, 5] {
            let probe = ResetProbe()
            XCTAssertEqual(vtx_c_mixer_set_voice_key_off_frame(&probe.state, 0, UInt64(frame), 0.125), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 3, 15), VTX_C_MIXER_STATUS_OK)
            _ = probe.render(frame)
            XCTAssertEqual(probe.voice.key_on, 1)
            _ = probe.render(1)
            XCTAssertEqual(probe.voice.key_on, 0)
            XCTAssertEqual(probe.voice.fadeout_value, 0.875)
        }
    }

    func testDisabledClocksArePreservedAndInvalidOrAbsentResetIsRejected() {
        let probe = ResetProbe()
        XCTAssertEqual(vtx_c_mixer_set_voice_volume_envelope(&probe.state, 0, nil), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_set_voice_pan_envelope(&probe.state, 0, nil), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_set_voice_runtime_state(&probe.state, 0, 1.25, -1, 17, 23, 0, 0.5), VTX_C_MIXER_STATUS_OK)
        for mask: UInt32 in [0, 16, UInt32.max] {
            XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 0, mask), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        }
        XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 1, 0, 15), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 0, 15), VTX_C_MIXER_STATUS_OK)
        _ = probe.render(1)
        XCTAssertEqual(probe.voice.volume_envelope.position_frame, 17)
        XCTAssertEqual(probe.voice.pan_envelope.position_frame, 23)
    }

    func testCompletedVoiceAndReplacementTailCannotBeResetOrResurrectedByImport() {
        for completion in 0...2 {
            let probe = ResetProbe()
            if completion == 0 {
                XCTAssertEqual(vtx_c_mixer_set_voice_key_off_frame(&probe.state, 0, 0, 1), VTX_C_MIXER_STATUS_OK)
            } else if completion == 1 {
                probe.state.voices.0.loop_mode = VTX_C_MIXER_LOOP_NONE
            } else {
                XCTAssertEqual(vtx_c_mixer_schedule_voice_ramp_down_and_deactivate(&probe.state, 0, 0, 2), VTX_C_MIXER_STATUS_OK)
                XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 1, 15), VTX_C_MIXER_STATUS_OK)
            }
            _ = probe.render(20)
            let before = probe.voice
            XCTAssertEqual(before.active, 0)
            XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 20, 15), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(probe.render(1), [0])
            XCTAssertEqual(probe.voice.sample_position, before.sample_position)
            XCTAssertEqual(probe.voice.fadeout_value, before.fadeout_value)
            XCTAssertEqual(vtx_c_mixer_set_voice_runtime_state(&probe.state, 0, 0.25, 1, 0, 0, 1, 1), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(probe.voice.active, 0)
            XCTAssertEqual(probe.voice.sample_position, before.sample_position)
            XCTAssertEqual(probe.render(1), [0])
        }
    }

    func testReleasedSlotReuseDropsStaleResetAndKeyOff() {
        let probe = ResetProbe()
        XCTAssertEqual(vtx_c_mixer_set_voice_channel_tag(&probe.state, 0, 0), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_playback_reset(&probe.state, 0, 4, 15), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_release(&probe.state, 0, 5, 1), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_stop_voices_for_channel_tag(&probe.state, 0, nil), VTX_C_MIXER_STATUS_OK)
        let pcm: [Float] = Array(repeating: 1, count: 16)
        var slot: UInt32 = 99
        pcm.withUnsafeBufferPointer {
            XCTAssertEqual(vtx_c_mixer_add_one_shot_sample(&probe.state, $0.baseAddress, 16, 1, 0, &slot), VTX_C_MIXER_STATUS_OK)
        }
        XCTAssertEqual(slot, 0)
        XCTAssertEqual(probe.render(8), Array(repeating: 1, count: 8))
        XCTAssertEqual(probe.voice.key_on, 1)
    }

    func testHistoricalKeyOffIsClearedByImportButFutureOneSurvives() {
        let probe = ResetProbe()
        _ = probe.render(4)
        XCTAssertEqual(vtx_c_mixer_set_voice_runtime_state(&probe.state, 0, 3, 1, 0, 0, 1, 1), VTX_C_MIXER_STATUS_OK)
        _ = probe.render(1)
        XCTAssertEqual(probe.voice.key_on, 1)
        XCTAssertEqual(vtx_c_mixer_set_voice_key_off_frame(&probe.state, 0, 6, 0.125), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_set_voice_runtime_state(&probe.state, 0, 3.75, 1, 0, 0, 1, 1), VTX_C_MIXER_STATUS_OK)
        _ = probe.render(2)
        XCTAssertEqual(probe.voice.key_on, 0)
    }

    func testWindowReconstructionMatchesBoundedStateAndPCMBeforeAtAndAfterReset() throws {
        for mode in [MixerSampleLoopMode.none, .forward, .pingPong] {
            for windows in [1, 2, 3, 7, 8, 13] {
                let (song, plan) = makePlan(mode: mode)
                let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)
                let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
                let request = PlaybackSongOfflineRenderRequest(song: song, config: config, frames: 40)
                let bounded = renderer.render(request)
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: windows).block.interleavedPCM, bounded.block.interleavedPCM)
                let index = renderer.makeWindowedRenderScheduleIndex(for: plan, totalFrames: 40, windowRows: windows, includedEventIndices: nil)
                let continuous = CSoftwareMixer(config: config)
                let voices = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: continuous)
                PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: try XCTUnwrap(voices[0])], on: continuous)
                for bucket in index.windows where bucket.startFrame > 0 {
                    _ = continuous.render(frames: bucket.startFrame - Int(continuous.currentFrame))
                    let actual = try XCTUnwrap(continuous.voiceDiagnostic(forVoiceAt: 0))
                    if !actual.active {
                        XCTAssertTrue(bucket.continuations.isEmpty)
                        continue
                    }
                    let carry = try XCTUnwrap(bucket.continuations.first)
                    XCTAssertEqual(carry.runtimeState.keyOn, actual.keyOn)
                    XCTAssertEqual(carry.runtimeState.fadeoutValue, actual.fadeoutValue)
                    XCTAssertEqual(carry.runtimeState.volumeEnvelopePositionFrame, actual.volumeEnvelopePositionFrame)
                    XCTAssertEqual(carry.runtimeState.panEnvelopePositionFrame, actual.panEnvelopePositionFrame)
                    XCTAssertEqual(carry.runtimeState.samplePosition, actual.samplePosition)
                    XCTAssertEqual(carry.runtimeState.pingPongDirection, actual.pingPongDirection)
                    XCTAssertEqual(carry.playbackStep, actual.sampleStep)
                }
            }
        }
    }

    func testWindowReconstructionPreservesPartialResetsAndFloatFadeoutRounding() {
        for mask in 1...15 {
            let reset = MixerPlaybackReset(volumeEnvelope: mask & 1 != 0, panEnvelope: mask & 2 != 0,
                keyOn: mask & 4 != 0, fadeout: mask & 8 != 0)
            let (song, plan) = makePlan(mode: .pingPong, reset: reset, decrement: 0.0031)
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
            let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: 100, channelCount: 1), frames: 40)
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 2).block.interleavedPCM,
                           renderer.render(request).block.interleavedPCM)
        }
    }

    func testExplicitReleaseResetAndFutureTriggerOwnedReleaseReconstructTheCarriedRate() {
        let (song, baseline) = makePlan(mode: .pingPong)
        var plan = PlaybackSongSyntheticPlan(timingConfig: baseline.timingConfig,
            pattern: .init(rowCount: 40, events: [baseline.pattern.events[0].withKeyOffFrame(13, fadeoutFrameDecrement: 0.125)]),
            diagnostics: baseline.diagnostics)
        plan.playbackStateEvents = [
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 2, change: .keyOff(fadeoutDecrement: 0.03125)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 7, change: .reset(all))]
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: 100, channelCount: 1), frames: 40)
        for windowRows in [1, 3, 7, 13] {
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: windowRows).block.interleavedPCM,
                           renderer.render(request).block.interleavedPCM)
        }
    }

    func testReplacementWindowBoundaryRejectsStaleResetAndRelease() {
        let (originalSong, originalPlan) = makePlan(mode: .pingPong)
        let rows = (0..<40).map { row in PlaybackRow(index: row, cells: [PlaybackCell(
            note: row == 0 || row == 6 ? 49 : 0, instrument: row == 0 || row == 6 ? 1 : 0,
            volumeColumn: 0, effectType: 0, effectParam: 0)]) }
        let song = PlaybackSong(title: "Replacement reset", orders: originalSong.orders,
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: rows)], instrumentsByIndex: originalSong.instrumentsByIndex,
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: originalSong.initialTiming, usesLinearFrequencyTable: true)
        let baseline = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let old = originalPlan.pattern.events[0]
        let replacement = SyntheticTrackerEvent(row: 6, scheduledStartFrame: 6, sample: old.sample,
            playbackStep: 0.25, loop: old.loop, volumeEnvelope: old.volumeEnvelope, panEnvelope: old.panEnvelope)
        var plan = PlaybackSongSyntheticPlan(timingConfig: baseline.timingConfig,
            pattern: .init(rowCount: 40, events: [old, replacement]), diagnostics: baseline.diagnostics)
        plan.playbackStateEvents = [
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 5, change: .reset(all)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 6, change: .reset(all)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 8, change: .keyOff(fadeoutDecrement: 1)),
            .init(activeEventIndex: 1, channelIndex: 0, scheduledFrame: 7, change: .reset(all)),
            .init(activeEventIndex: 1, channelIndex: 0, scheduledFrame: 14, change: .keyOff(fadeoutDecrement: 0.03125))]
        XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan).map(\.scheduledFrame), [5, 7, 14])
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: 100, channelCount: 1), frames: 40)
        let expected = renderer.render(request).block.interleavedPCM
        for windowRows in [1, 2, 3, 6, 7, 8] {
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: windowRows).block.interleavedPCM, expected)
        }
    }

    func testMissingWrongChannelAndInvalidStateEventsAreExcludedFromBothPlans() {
        let (song, initial) = makePlan(mode: .forward)
        var plan = initial
        plan.playbackStateEvents = [
            .init(activeEventIndex: 0, channelIndex: 1, scheduledFrame: 7, change: .reset(all)),
            .init(activeEventIndex: 99, channelIndex: 0, scheduledFrame: 7, change: .reset(all)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: -1, change: .reset(all)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 7, change: .reset(.init())),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 7, change: .keyOff(fadeoutDecrement: .nan))]
        XCTAssertTrue(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan).isEmpty)
        var invalidPayloads = plan
        invalidPayloads.playbackStateEvents = Array(plan.playbackStateEvents.suffix(2))
        let work = PlaybackSongOfflineRenderer.CarriedPlaybackStateWork()
        XCTAssertTrue(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: invalidPayloads, work: work).isEmpty)
        XCTAssertEqual(work.indexBuildCount, 0)
        XCTAssertEqual(work.mappingsVisited, 0)
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100, preparedPlan: plan)
        XCTAssertEqual(runtime.events.count, 1)
        XCTAssertEqual(runtime.events[0].primaryCategory, "note_trigger")
    }

    func testPanningClockMapsAndResetsWithoutAudibleModulationOrFinalCellDispatch() throws {
        let (song, plan) = makePlan(mode: .forward)
        let adapter = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        XCTAssertTrue(adapter.playbackStateEvents.isEmpty)
        let clock = try XCTUnwrap(adapter.pattern.events.first?.panEnvelope)
        XCTAssertEqual(clock.points.map(\.positionFrame), [0, 3])
        XCTAssertEqual(clock.points.map(\.value), [0, 0])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 100, channelCount: 2))
        let event = plan.pattern.events[0]
        let voice = mixer.addVoice(sample: event.sample, pan: 0.25, playbackStep: 0.75, loop: event.loop, panEnvelope: clock)
        _ = mixer.render(frames: 7)
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.panEnvelopePositionFrame, 3)
        XCTAssertTrue(mixer.schedulePlaybackStateChange(.reset(.init(panEnvelope: true)), voiceIndex: voice, scheduledFrame: 7).wasAccepted)
        let output = mixer.render(frames: 1).interleavedPCM
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.panEnvelopePositionFrame, 1)
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.pan, 0.25)
        XCTAssertEqual(output[0] / output[1], 0.75, accuracy: 0.000001)
    }

    private func makePlan(mode: MixerSampleLoopMode, reset: MixerPlaybackReset? = nil, decrement: Float = 0.0625) -> (PlaybackSong, PlaybackSongSyntheticPlan) {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1, count: 64), volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 100)
        let pan = PlaybackPanningEnvelope(enabled: true, points: [.init(tick: 0, value: 0), .init(tick: 3, value: 64)], sustainPointIndex: 1, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 3)
        let song = PlaybackSong(title: "Reset foundation", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: (0..<40).map { row in
                .init(index: row, cells: [.init(note: row == 0 ? 49 : 0, instrument: row == 0 ? 1 : 0, volumeColumn: 0, effectType: 0, effectParam: 0)])
            })], instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], panningEnvelope: pan)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 1, bpm: 250), usesLinearFrequencyTable: true)
        let baseline = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let event = SyntheticTrackerEvent(row: 0, scheduledStartFrame: 0, sample: .init(monoPCM: (0..<64).map { Float($0) / 64 }),
            playbackStep: 0.75, loop: .init(mode: mode, startFrame: 1, endFrame: 5),
            volumeEnvelope: .init(points: [.init(positionFrame: 0, value: 0.25), .init(positionFrame: 4, value: 0.75)], sustainFrame: 4),
            panEnvelope: baseline.pattern.events[0].panEnvelope, keyOffFrame: 2, fadeoutFrameDecrement: decrement)
        var plan = PlaybackSongSyntheticPlan(timingConfig: baseline.timingConfig, pattern: .init(rowCount: 40, events: [event]), diagnostics: baseline.diagnostics)
        plan.playbackStateEvents = [
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 7, change: .reset(reset ?? all)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 13, change: .keyOff(fadeoutDecrement: decrement)),
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 31, change: .reset(all))]
        return (song, plan)
    }
}

private final class ResetProbe {
    var state = VTXCMixerState()
    var voice: VTXCMixerVoice { state.voices.0 }
    init() {
        var config = vtx_c_mixer_default_config(); config.sample_rate = 100; config.channel_count = 1
        XCTAssertEqual(vtx_c_mixer_init(&state, config), VTX_C_MIXER_STATUS_OK)
        let samples = (0..<8).map { Float($0) / 8 }
        samples.withUnsafeBufferPointer {
            XCTAssertEqual(vtx_c_mixer_add_sample_voice_with_step(&state, $0.baseAddress, 8, 0.75, 1, 0, VTX_C_MIXER_LOOP_PING_PONG, 1, 5, nil), VTX_C_MIXER_STATUS_OK)
        }
        let points = [VTXCMixerEnvelopePoint(position_frame: 0, value: 0.25), VTXCMixerEnvelopePoint(position_frame: 4, value: 0.75)]
        points.withUnsafeBufferPointer {
            var envelope = VTXCMixerEnvelope(points: $0.baseAddress, point_count: 2, sustain_enabled: 0, sustain_frame: 0, loop_enabled: 0, loop_start_frame: 0, loop_end_frame: 0)
            XCTAssertEqual(vtx_c_mixer_set_voice_volume_envelope(&state, 0, &envelope), VTX_C_MIXER_STATUS_OK)
        }
        let pan = [VTXCMixerEnvelopePoint(position_frame: 0, value: 0), VTXCMixerEnvelopePoint(position_frame: 3, value: 0)]
        pan.withUnsafeBufferPointer {
            var envelope = VTXCMixerEnvelope(points: $0.baseAddress, point_count: 2, sustain_enabled: 1, sustain_frame: 3, loop_enabled: 0, loop_start_frame: 0, loop_end_frame: 0)
            XCTAssertEqual(vtx_c_mixer_set_voice_pan_envelope(&state, 0, &envelope), VTX_C_MIXER_STATUS_OK)
        }
        XCTAssertEqual(vtx_c_mixer_set_voice_key_off_frame(&state, 0, 2, 0.0625), VTX_C_MIXER_STATUS_OK)
    }
    deinit { vtx_c_mixer_clear_voices(&state) }
    func render(_ frames: Int) -> [Float] {
        var pcm = Array(repeating: Float(0), count: frames)
        pcm.withUnsafeMutableBufferPointer { XCTAssertEqual(vtx_c_mixer_render(&state, $0.baseAddress, UInt32(frames)), VTX_C_MIXER_STATUS_OK) }
        return pcm
    }
}

extension NonretriggeringResetTests {
    func testCarriedStateReferencePinsFrameIndexTiesAndInputOrder() {
        let seed = PlaybackSongSyntheticAdapter.adapt(CarriedStatePublicControl.song(), orderIndex: 0, sampleRate: 48_000)
        let template = seed.diagnostics.eventMappings[0]
        let events = [8, 0, 8, 4, 12, 3].enumerated().map { index, frame in
            SyntheticTrackerEvent(row: 30 - index, scheduledStartFrame: frame, sample: seed.pattern.events[0].sample)
        }
        let mappings = [(0, 0), (1, 1), (2, 0), (3, 1), (4, 0), (-1, 0), (99, 1)].map {
            CarriedStateEligibilityReference.mapping(template, eventIndex: $0.0, channelIndex: $0.1)
        }
        var plan = PlaybackSongSyntheticPlan(timingConfig: seed.timingConfig, pattern: .init(rowCount: 64, events: events),
            diagnostics: CarriedStateEligibilityReference.diagnostics(seed.diagnostics, mappings: mappings))
        func state(_ source: Int, _ channel: Int, _ frame: Int, _ change: MixerPlaybackStateChange) -> PlaybackVoiceStateEvent {
            .init(activeEventIndex: source, channelIndex: channel, scheduledFrame: frame, change: change)
        }
        let reset = MixerPlaybackStateChange.reset(all)
        plan.playbackStateEvents = [state(4, 0, 12, reset), state(0, 0, 8, reset), state(2, 0, 8, reset),
            state(2, 0, 8, .keyOff(fadeoutDecrement: 0)), state(1, 1, 3, reset), state(3, 1, 4, reset),
            state(1, 1, 4, reset), state(5, 0, 7, reset), state(2, 1, 8, reset), state(2, 2, 8, reset),
            state(-1, 0, 8, reset), state(99, 0, 8, reset), state(1, 1, -1, reset),
            state(2, 0, 9, .reset(.init()))]
        for mask in 1...15 {
            plan.playbackStateEvents.append(state(2, 0, 9, .reset(.init(volumeEnvelope: mask & 1 != 0,
                panEnvelope: mask & 2 != 0, keyOn: mask & 4 != 0, fadeout: mask & 8 != 0))))
        }
        for decrement: Float in [0.125, 0, -1, .nan, .infinity, -.infinity] {
            plan.playbackStateEvents.append(state(2, 0, 9, .keyOff(fadeoutDecrement: decrement)))
        }
        let expected = CarriedStateEligibilityReference.events(plan)
        XCTAssertEqual(expected.count, 22)
        XCTAssertEqual(Array(expected.prefix(4)), [plan.playbackStateEvents[4], plan.playbackStateEvents[5],
            plan.playbackStateEvents[2], plan.playbackStateEvents[3]])
        XCTAssertEqual(expected.last, plan.playbackStateEvents[0])
        XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), expected)
        plan.diagnostics = CarriedStateEligibilityReference.diagnostics(plan.diagnostics, mappings: mappings.reversed())
        XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), expected)
    }

    func testCarriedReferenceAcrossPublicCutsReplacementsAndMutableCopies() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["empty-slot-playback-state", "delayed-instrument-only-edx", "note-only-routing",
                     "e90-row-entry-retrigger", "tone-portamento-retained-source-reset", "envelope-release-fadeout-timing"] {
            let path = root.appendingPathComponent("reference-xm/generated/\(name).xm").path
            let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
            for rate in [44_100.0, 48_000] {
                var plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: song.orders.count, sampleRate: rate)
                // Keep the independently planned diagnostics but avoid rebuilding semantic timelines
                // while injecting deliberately stale probes around inclusive lifetime boundaries.
                plan.xmEnvelopeTimeline = nil
                let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
                var probes = plan.playbackStateEvents
                for mapping in plan.diagnostics.eventMappings {
                    let start = scheduler.frame(for: plan.pattern.events[mapping.eventIndex])
                    var frames = [start - 1, start, start + 1, Int.max]
                    frames += plan.xmEmptyRoutes.filter { $0.stoppedEventIndex == mapping.eventIndex }.map(\.scheduledFrame)
                    frames += plan.diagnostics.noteCutEffects.filter { $0.activeEventIndex == mapping.eventIndex }.compactMap(\.scheduledFrame)
                    for retrigger in plan.diagnostics.retriggerEffects {
                        frames += zip(retrigger.replacedEventIndices, retrigger.replacementFrames ?? retrigger.retriggerFrames)
                            .filter { $0.0 == mapping.eventIndex }.map { $0.1 }
                    }
                    for frame in frames {
                        for boundary in [frame == Int.min ? frame : frame - 1, frame] {
                            probes.append(.init(activeEventIndex: mapping.eventIndex, channelIndex: mapping.channelIndex,
                                scheduledFrame: boundary, change: .reset(all)))
                        }
                    }
                }
                plan.playbackStateEvents = probes.reversed()
                XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), CarriedStateEligibilityReference.events(plan), name)
                let original = plan
                plan.playbackStateEvents = []
                XCTAssertTrue(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan).isEmpty)
                plan = original
                plan.xmEmptyRoutes = []
                plan.diagnostics = CarriedStateEligibilityReference.diagnostics(plan.diagnostics, mappings: [])
                XCTAssertTrue(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan).isEmpty)
                XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: original), CarriedStateEligibilityReference.events(original))
            }
        }
    }

    func testPublicCarriedControlBothModesRatesAndWindowReferences() {
        for linear in [true, false] {
            for rate in [44_100.0, 48_000] {
                let song = CarriedStatePublicControl.song(linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 1, sampleRate: rate)
                XCTAssertFalse(plan.playbackStateEvents.isEmpty)
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { $0.source.orderIndex == 1 })
                XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), CarriedStateEligibilityReference.events(plan))
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan)
                XCTAssertEqual(runtime.plan, plan)
                let states = runtime.events.compactMap { event -> PlaybackVoiceStateEvent? in
                    if case let .playbackStateChange(index, change) = event.action {
                        return .init(activeEventIndex: index, channelIndex: event.channelIndex,
                            scheduledFrame: event.scheduledFrame, change: change)
                    }; return nil
                }
                XCTAssertEqual(states, CarriedStateEligibilityReference.events(plan).filter {
                    plan.xmEnvelopeTimeline?.updatesByEvent[$0.activeEventIndex] == nil
                })
                let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
                let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: 8)
                let whole = renderer.render(request)
                let indexed = renderer.renderWindowed(request, windowRows: 2)
                let scan = renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 2)
                XCTAssertEqual(indexed.block.interleavedPCM, scan.block.interleavedPCM)
                XCTAssertEqual(indexed.plan.xmEnvelopeTimeline, whole.plan.xmEnvelopeTimeline)
                XCTAssertEqual(indexed.plan.xmAudibleTimeline, whole.plan.xmAudibleTimeline)
                XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM, indexed.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }

    func testAudibleCutsRetainCarriedStateWhileSourceRetirementsRemainInclusive() {
        let (_, seed) = makePlan(mode: .forward)
        let source = seed.diagnostics.eventMappings[0].source
        var plan = seed
        plan.playbackStateEvents = [6, 7, 8, 9, Int.max - 1, Int.max].map {
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: $0, change: .reset(all))
        }
        func check(_ frames: [Int]) {
            XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan).map(\.scheduledFrame), frames)
            XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), CarriedStateEligibilityReference.events(plan))
        }
        func cut(_ frame: Int?, _ applied: Bool = true, _ event: Int = 0) -> PlaybackSongSyntheticNoteCutDiagnostic {
            .init(source: source, channelIndex: 0, syntheticRow: 1, syntheticTick: 1, effectType: 14, effectParam: 0xC1,
                status: .applied, detected: true, applied: applied, deferred: false, ignoredAsNoOp: false, outOfRow: false,
                requestedTick: 1, rowSpeed: 6, rowBPM: 125, scheduledFrame: frame, activeEventIndex: event)
        }
        func diagnostics(_ cuts: [PlaybackSongSyntheticNoteCutDiagnostic] = [], _ retriggers: [PlaybackSongSyntheticRetriggerDiagnostic] = []) {
            plan.diagnostics = CarriedStateEligibilityReference.diagnostics(seed.diagnostics,
                mappings: seed.diagnostics.eventMappings, cuts: cuts, retriggers: retriggers)
        }
        let allFrames = plan.playbackStateEvents.map(\.scheduledFrame)
        diagnostics([cut(7)]); check(allFrames)
        diagnostics([cut(nil)]); check(allFrames)
        diagnostics([cut(0, false), cut(0, true, 99)]); check(allFrames)
        var retrigger = PlaybackSongSyntheticRetriggerDiagnostic(source: source, channelIndex: 0,
            syntheticRow: 1, syntheticTick: 2, effectType: 14, effectParam: 0x92, status: .applied,
            detected: true, applied: true, deferred: false, ignoredAsNoOp: false, outOfRow: false, activeVoiceFound: true,
            retriggerIntervalTicks: 2, rowSpeed: 6, rowBPM: 125, retriggerTicks: [2], retriggerFrames: [9],
            retriggerEventIndices: [1], replacedEventIndices: [0, 99], volumeModeNibble: 0, intervalNibble: 2,
            volumeChangePolicy: nil, volumeChangeCount: 0, volumeValuesBefore: [], volumeValuesAfter: [], retriggerGains: [],
            activeEventIndexBefore: 0, selectedSampleIndex: 0, selectedSampleLength: 64, initialSourceFrame: 0,
            playbackStep: 1, gain: 1, pan: 0, envelopePolicy: "carried")
        retrigger.replacementFrames = [7]
        diagnostics([], [retrigger]); check([6])
        retrigger.replacementFrames = []
        diagnostics([], [retrigger]); check(allFrames)
        retrigger.replacementFrames = nil
        diagnostics([], [retrigger]); check([6, 7, 8])
        retrigger.applied = false
        diagnostics([], [retrigger]); check(allFrames)
        diagnostics()
        plan.xmEmptyRoutes = [.init(source: source, channelIndex: 0, scheduledFrame: 7,
            instrumentIndex: 1, sampleIndex: 2, stoppedEventIndex: 0)]
        check([6])
        plan.xmEmptyRoutes = []
        check(allFrames)
    }

    func testCarriedReferenceKeepsDistinctLoopOccurrencesAtANonzeroOrderStart() {
        for linear in [true, false] {
            for rate in [44_100.0, 48_000] {
                let song = CarriedStatePublicControl.song(linear: linear, patternLoop: true)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 1, sampleRate: rate)
                XCTAssertGreaterThan(plan.diagnostics.rowMappings.filter { $0.source.rowIndex == 1 }.count, 1)
                XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), CarriedStateEligibilityReference.events(plan))
            }
        }
    }

    func testPublicCarriedScalingVariesMappingsAndQueriesIndependently() {
        for orders in [1, 2, 4, 8, 16] {
            for density in [1, 3] {
                let song = CarriedStatePublicControl.song(orders: orders, resetDensity: density)
                var plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: orders, sampleRate: 48_000)
                plan.xmEnvelopeTimeline = nil
                let expected = CarriedStateEligibilityReference.events(plan)
                XCTAssertGreaterThan(expected.count, 0)
                XCTAssertEqual(plan.diagnostics.eventMappings.count, orders * 64)
                XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), expected)
                for repetitions in [1, 3] {
                    plan.playbackStateEvents = Array(repeating: expected, count: repetitions).flatMap { $0 }
                    let work = PlaybackSongOfflineRenderer.CarriedPlaybackStateWork()
                    XCTAssertEqual(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan, work: work), CarriedStateEligibilityReference.events(plan))
                    let queries = plan.playbackStateEvents.count, mappings = plan.diagnostics.eventMappings.count
                    XCTAssertEqual(work.indexBuildCount, 1)
                    XCTAssertEqual(work.mappingsVisited, mappings)
                    XCTAssertEqual(work.entriesIndexed, mappings)
                    XCTAssertEqual(work.lookupCount, queries)
                    // Four independent channels, at most log2(M/4)+1 frame comparisons per query.
                    XCTAssertLessThanOrEqual(work.entriesVisited, queries * (Int(log2(Double(mappings / 4))) + 1))
                    XCTAssertLessThan(work.mappingsVisited + work.entriesVisited, queries * mappings)
                }
                plan.playbackStateEvents = []
                let emptyWork = PlaybackSongOfflineRenderer.CarriedPlaybackStateWork()
                XCTAssertTrue(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan, work: emptyWork).isEmpty)
                XCTAssertEqual(emptyWork.indexBuildCount, 0)
                XCTAssertEqual(emptyWork.mappingsVisited, 0)
                XCTAssertEqual(emptyWork.entriesVisited, 0)
            }
        }
    }
}

// Test-only controls shared verbatim with the external ordinary-optimized observer.
enum CarriedStatePublicControl {
    static func song(orders: Int = 2, resetDensity: Int = 3, linear: Bool = true, patternLoop: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<64).map { Float(($0 % 16) - 8) / 16 }, volume: 0.75,
            relativeNote: 0, finetune: 0, baseSampleRate: 8_363, loopStart: 0, loopLength: 64, loopType: 1)
        let rows = (0..<64).map { row in
            PlaybackRow(index: row, cells: (0..<4).map { channel in
                let phase = row % 8
                return PlaybackCell(note: phase == 0 || phase == 4 ? UInt8(37 + channel * 3) : (phase == 7 ? 97 : 0),
                    instrument: phase == 0 || (1...resetDensity).contains(phase) || phase == 5 ? 1 : 0,
                    volumeColumn: 0, effectType: patternLoop && channel == 0 && [0, 2].contains(row) ? 14 : 0,
                    effectParam: patternLoop && channel == 0 && [0, 2].contains(row) ? (row == 0 ? 0x60 : 0x62) : 0)
            })
        }
        return PlaybackSong(title: "Public carried state control", orders: (0..<orders).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 250), usesLinearFrequencyTable: linear)
    }
}

enum CarriedStateEligibilityReference {
    /// Independent scan oracle: collect this channel's eligible source candidates, select
    /// the lexicographic maximum (source frame, event index), then apply inclusive cuts.
    static func events(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackVoiceStateEvent] {
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        var admitted: [(Int, PlaybackVoiceStateEvent)] = []
        for (offset, update) in plan.playbackStateEvents.enumerated() {
            switch update.change {
            case let .reset(reset): if reset.dimensions == 0 { continue }
            case let .keyOff(value): if !value.isFinite || value < 0 { continue }
            }
            guard plan.pattern.events.indices.contains(update.activeEventIndex) else { continue }
            var winner: (frame: Int, index: Int)?
            for mapping in plan.diagnostics.eventMappings {
                guard mapping.channelIndex == update.channelIndex,
                      plan.pattern.events.indices.contains(mapping.eventIndex) else { continue }
                let frame = scheduler.frame(for: plan.pattern.events[mapping.eventIndex])
                guard frame <= update.scheduledFrame else { continue }
                if winner == nil || frame > winner!.frame || (frame == winner!.frame && mapping.eventIndex > winner!.index) {
                    winner = (frame, mapping.eventIndex)
                }
            }
            guard winner?.index == update.activeEventIndex else { continue }
            let empty = plan.xmEmptyRoutes.contains { $0.stoppedEventIndex == update.activeEventIndex && $0.scheduledFrame <= update.scheduledFrame }
            let replaced = plan.diagnostics.retriggerEffects.contains { effect in
                effect.applied && zip(effect.replacedEventIndices, effect.replacementFrames ?? effect.retriggerFrames).contains {
                    $0.0 == update.activeEventIndex && $0.1 <= update.scheduledFrame
                }
            }
            if !empty && !replaced { admitted.append((offset, update)) }
        }
        return admitted.sorted {
            $0.1.scheduledFrame == $1.1.scheduledFrame ? $0.0 < $1.0 : $0.1.scheduledFrame < $1.1.scheduledFrame
        }.map { $0.1 }
    }

    static func mapping(_ base: PlaybackSongSyntheticEventMapping, eventIndex: Int, channelIndex: Int) -> PlaybackSongSyntheticEventMapping {
        .init(
            source: base.source, channelIndex: channelIndex,
            note: base.note, instrumentIndex: base.instrumentIndex,
            sampleIndex: base.sampleIndex, sampleVolume: base.sampleVolume,
            sampleVolumeRawEstimate: base.sampleVolumeRawEstimate, selectedSampleLength: base.selectedSampleLength,
            sampleMapKeymapPresent: base.sampleMapKeymapPresent, mappedSampleIndex: base.mappedSampleIndex,
            mappedSampleValid: base.mappedSampleValid, sampleSelectionMethod: base.sampleSelectionMethod,
            sampleSelectionStrategy: base.sampleSelectionStrategy, firstPlayableSampleFallbackUsed: base.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: base.sampleMapKeymapBehaviorDeferred, sampleMapKeymapMissingOrDeferred: base.sampleMapKeymapMissingOrDeferred,
            effectType: base.effectType, effectParam: base.effectParam,
            syntheticRow: base.syntheticRow, syntheticTick: base.syntheticTick,
            eventIndex: eventIndex, loopMode: base.loopMode,
            volumeColumn: base.volumeColumn, sampleOffset: base.sampleOffset,
            hasIgnoredVolumeColumn: base.hasIgnoredVolumeColumn, hasIgnoredEffect: base.hasIgnoredEffect,
            effectiveVolumeValue: base.effectiveVolumeValue, effectiveGlobalVolumeValue: base.effectiveGlobalVolumeValue,
            effectiveGlobalVolumeMultiplier: base.effectiveGlobalVolumeMultiplier, effectivePan: base.effectivePan,
            volumeEnvelopeStatus: base.volumeEnvelopeStatus, sourceVolumeEnvelopePointCount: base.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: base.mappedVolumeEnvelopePointCount, hasDeferredVolumeEnvelopeSustain: base.hasDeferredVolumeEnvelopeSustain,
            hasDeferredVolumeEnvelopeLoop: base.hasDeferredVolumeEnvelopeLoop, hasDeferredVolumeEnvelopeFadeout: base.hasDeferredVolumeEnvelopeFadeout,
            volumeEnvelopeSemantics: base.volumeEnvelopeSemantics, sampleBaseSampleRate: base.sampleBaseSampleRate,
            sampleRelativeNote: base.sampleRelativeNote, sampleFinetune: base.sampleFinetune,
            outputSampleRate: base.outputSampleRate, effectiveNoteValue: base.effectiveNoteValue,
            effectiveNoteIndex: base.effectiveNoteIndex, effectiveFinetune: base.effectiveFinetune,
            linearPeriod: base.linearPeriod, linearFrequency: base.linearFrequency,
            amigaPeriod: base.amigaPeriod, amigaFrequency: base.amigaFrequency,
            finetuneStatus: base.finetuneStatus, usesLinearFrequencyTable: base.usesLinearFrequencyTable,
            frequencyTableStatus: base.frequencyTableStatus, linearFrequencyApplied: base.linearFrequencyApplied,
            amigaFrequencyApplied: base.amigaFrequencyApplied, amigaFrequencyDeferred: base.amigaFrequencyDeferred,
            playbackStep: base.playbackStep, pitchMappingApplied: base.pitchMappingApplied,
            pitchMappingUsedNeutralStep: base.pitchMappingUsedNeutralStep
        )
    }

    static func diagnostics(_ base: PlaybackSongSyntheticDiagnostics, mappings: [PlaybackSongSyntheticEventMapping],
        cuts: [PlaybackSongSyntheticNoteCutDiagnostic]? = nil, retriggers: [PlaybackSongSyntheticRetriggerDiagnostic]? = nil) -> PlaybackSongSyntheticDiagnostics {
        .init(
            requestedStartOrderIndex: base.requestedStartOrderIndex, requestedOrderCount: base.requestedOrderCount,
            sampleRate: base.sampleRate, initialSpeed: base.initialSpeed,
            initialBPM: base.initialBPM, usesLinearFrequencyTable: base.usesLinearFrequencyTable,
            syntheticRowCount: base.syntheticRowCount, adaptedOrders: base.adaptedOrders,
            rowMappings: base.rowMappings, rowTiming: base.rowTiming,
            timingChanges: base.timingChanges, traversalDiagnostics: base.traversalDiagnostics,
            traversalPathLength: base.traversalPathLength, traversalStopReason: base.traversalStopReason,
            traversalGuardHit: base.traversalGuardHit, effectCommandDiagnostics: base.effectCommandDiagnostics,
            rowDiagnostics: base.rowDiagnostics, volumeColumnMappings: base.volumeColumnMappings,
            voiceStateUpdates: base.voiceStateUpdates, sampleOffsetEffects: base.sampleOffsetEffects,
            setFinetuneEffects: base.setFinetuneEffects, envelopePositionEffects: base.envelopePositionEffects,
            noteCutEffects: cuts ?? base.noteCutEffects, noteDelayEffects: base.noteDelayEffects,
            retriggerEffects: retriggers ?? base.retriggerEffects, tonePortamentoEffects: base.tonePortamentoEffects,
            portamentoSlideEffects: base.portamentoSlideEffects, finePortamentoUpEffects: base.finePortamentoUpEffects,
            finePortamentoDownEffects: base.finePortamentoDownEffects, extraFinePortamentoEffects: base.extraFinePortamentoEffects,
            arpeggioEffects: base.arpeggioEffects, vibratoControlEffects: base.vibratoControlEffects,
            vibratoEffects: base.vibratoEffects, keyOffEvents: base.keyOffEvents,
            eventMappings: mappings, ignoredCells: base.ignoredCells,
            deferredCellFields: base.deferredCellFields, eventCoverage: base.eventCoverage
        )
    }
}
