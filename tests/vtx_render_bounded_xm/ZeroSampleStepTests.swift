import MixerCore
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class ZeroSampleStepTests: XCTestCase {
    func testCZeroHoldsFractionalCursorAndResumesAllLoopModes() {
        for mode in [VTX_C_MIXER_LOOP_NONE, VTX_C_MIXER_LOOP_FORWARD, VTX_C_MIXER_LOOP_PING_PONG] {
            let probe = DirectStepMixer(mode: mode)
            _ = probe.render(7)
            let before = probe.voice
            XCTAssertNotEqual(before.sample_position.rounded(.down), before.sample_position)
            if mode == VTX_C_MIXER_LOOP_PING_PONG { XCTAssertEqual(before.ping_pong_direction, -1) }
            XCTAssertEqual(probe.update(0), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(probe.render(17), Array(repeating: Float(before.sample_position / 8), count: 17))
            XCTAssertEqual(probe.voice.sample_step, 0)
            XCTAssertEqual(probe.voice.sample_position, before.sample_position)
            XCTAssertEqual(probe.voice.ping_pong_direction, before.ping_pong_direction)
            XCTAssertEqual(probe.voice.active, 1)
            XCTAssertEqual(probe.voice.loop_start_frame, before.loop_start_frame)
            XCTAssertEqual(probe.voice.loop_end_frame, before.loop_end_frame)
            XCTAssertEqual(probe.update(0.25), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(probe.render(1), [Float(before.sample_position / 8)])
            XCTAssertEqual(probe.voice.sample_position, before.sample_position + 0.25 * Double(before.ping_pong_direction))
            XCTAssertEqual(probe.state.voice_count, 1)
        }
    }

    func testCAbsentStepUpdateContinuesWhileExplicitZeroHolds() {
        let absent = DirectStepMixer(), held = DirectStepMixer()
        _ = absent.render(3); _ = held.render(3)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_gain_pan_update(&absent.state, 0, 3, 1, 1, 0, 0), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(held.update(0), VTX_C_MIXER_STATUS_OK)
        _ = absent.render(2); _ = held.render(2)
        XCTAssertEqual(absent.voice.sample_position, 3.75)
        XCTAssertEqual(absent.voice.sample_step, 0.75)
        XCTAssertEqual(held.voice.sample_position, 2.25)
        XCTAssertEqual(held.voice.sample_step, 0)
    }

    func testCHoldContinuesGainPanAndReplacementRamps() {
        let probe = DirectStepMixer()
        _ = probe.render(3)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_gain_pan_sample_step_update(
            &probe.state, 0, 3, 1, 0.25, 1, 1, 0), VTX_C_MIXER_STATUS_OK)
        _ = probe.render(16)
        XCTAssertEqual(probe.voice.sample_position, 2.25)
        XCTAssertEqual(probe.voice.gain_ramp_position_frame, 16)
        XCTAssertEqual(probe.voice.pan_ramp_position_frame, 16)
        _ = probe.render(16)
        XCTAssertEqual(probe.voice.gain, 0.25)
        XCTAssertEqual(probe.voice.pan, 1)
        XCTAssertEqual(probe.voice.active, 1)
        XCTAssertEqual(probe.voice.sample_position, 2.25)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_ramp_down_and_deactivate(
            &probe.state, 0, probe.state.current_frame, 4), VTX_C_MIXER_STATUS_OK)
        _ = probe.render(4)
        XCTAssertEqual(probe.voice.sample_position, 2.25)
        XCTAssertEqual(probe.voice.active, 0)
        XCTAssertEqual(probe.state.ramp_down_completion_count, 1)
    }

    func testCCompletedVoiceIsNotResurrectedAndInitialZeroIsStillSanitized() {
        let probe = DirectStepMixer()
        _ = probe.render(16)
        let endedPosition = probe.voice.sample_position
        XCTAssertEqual(probe.voice.active, 0)
        for step in [0.0, 0.5] {
            XCTAssertEqual(probe.update(step), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(probe.render(3), [0, 0, 0])
            XCTAssertEqual(probe.voice.sample_position, endedPosition)
            XCTAssertEqual(probe.voice.active, 0)
        }
        XCTAssertEqual(DirectStepMixer(step: 0).voice.sample_step, 1)
        XCTAssertEqual(SyntheticTrackerEvent(row: 0, sample: MixerSampleBuffer(monoPCM: [1]), playbackStep: 0).playbackStep, 1)
    }

    func testCAndSwiftAcceptBothZerosAndRejectInvalidSteps() {
        let direct = DirectStepMixer()
        let swift = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 1))
        let voice = swift.addVoice(sample: MixerSampleBuffer(monoPCM: [0, 0.5, 0, -0.5]), playbackStep: 0.75)
        for invalid in [Double.nan, .infinity, -.infinity, -0.25, -Double.leastNonzeroMagnitude, Double(UInt32.max) + 1] {
            XCTAssertEqual(direct.update(invalid), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
            XCTAssertEqual(vtx_c_mixer_schedule_voice_gain_pan_sample_step_update(
                &direct.state, 0, 0, 1, 1, 0, 0, invalid), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
            XCTAssertFalse(swift.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 0, playbackStep: invalid).wasAccepted)
            XCTAssertFalse(swift.scheduleVoiceGainPanStepUpdate(voiceIndex: voice, scheduledFrame: 0, gain: 1, playbackStep: invalid).wasAccepted)
        }
        for zero in [0.0, -0.0] {
            XCTAssertEqual(direct.update(zero), VTX_C_MIXER_STATUS_OK)
            _ = direct.render(1)
            XCTAssertEqual(direct.voice.sample_step, 0)
            XCTAssertEqual(direct.voice.sample_position, 0)
            XCTAssertTrue(swift.scheduleVoiceGainPanStepUpdate(voiceIndex: voice, scheduledFrame: Int(swift.currentFrame), gain: 1, playbackStep: zero).wasAccepted)
            _ = swift.render(frames: 1)
            XCTAssertEqual(swift.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, 0)
            XCTAssertEqual(swift.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, 0)
        }
    }

    func testWindowContinuationRestoresHoldBeforeRenderingAndResumesWithoutRetrigger() throws {
        let sample = MixerSampleBuffer(monoPCM: (0..<8).map { Float($0) / 8 })
        for mode in [MixerSampleLoopMode.none, .forward, .pingPong] {
            let loop = MixerSampleLoop(mode: mode, startFrame: 1, endFrame: 5)
            let direction = loop.mode == .pingPong ? -1 : 1
            let continuation = PlaybackSongWindowContinuation(
                eventIndex: 0, event: SyntheticTrackerEvent(row: 0, sample: sample, playbackStep: 0.75, loop: loop),
                playbackStep: 0, runtimeState: CSoftwareMixerVoiceRuntimeState(samplePosition: 2.25, pingPongDirection: direction),
                keyOffFrame: nil, carriedTonePortamentoActive: true)
            let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 1))
            let voice = try XCTUnwrap(PlaybackSongOfflineRenderer.scheduleContinuation(continuation, on: mixer).voiceIndex)
            XCTAssertEqual(mixer.render(frames: 9).interleavedPCM, Array(repeating: 2.25 / 8, count: 9))
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, 2.25)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, 0)
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 9, playbackStep: 0.25).wasAccepted)
            _ = mixer.render(frames: 1)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, 2.25 + Double(direction) * 0.25)
            XCTAssertEqual(mixer.loadedVoiceCount, 1)
        }
    }
}

private final class DirectStepMixer {
    var state = VTXCMixerState()
    var voice: VTXCMixerVoice { state.voices.0 }

    init(mode: VTXCMixerLoopMode = VTX_C_MIXER_LOOP_NONE, step: Double = 0.75) {
        var config = vtx_c_mixer_default_config()
        config.sample_rate = 48_000; config.channel_count = 1
        XCTAssertEqual(vtx_c_mixer_init(&state, config), VTX_C_MIXER_STATUS_OK)
        let pcm = (0..<8).map { Float($0) / 8 }
        pcm.withUnsafeBufferPointer {
            XCTAssertEqual(vtx_c_mixer_add_sample_voice_with_step(
                &state, $0.baseAddress, 8, step, 1, 0, mode, 1, 5, nil), VTX_C_MIXER_STATUS_OK)
        }
    }

    deinit { vtx_c_mixer_clear_voices(&state) }

    func update(_ step: Double) -> VTXCMixerStatus {
        vtx_c_mixer_schedule_voice_sample_step_update(&state, 0, state.current_frame, step)
    }

    func render(_ frames: Int) -> [Float] {
        var pcm = Array(repeating: Float(0), count: frames)
        pcm.withUnsafeMutableBufferPointer {
            XCTAssertEqual(vtx_c_mixer_render(&state, $0.baseAddress, UInt32(frames)), VTX_C_MIXER_STATUS_OK)
        }
        return pcm
    }
}
