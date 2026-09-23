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
