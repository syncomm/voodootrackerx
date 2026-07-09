import AppKit
import AudioToolbox
import XCTest

final class CSoftwareMixerTests: XCTestCase {
    func testCMixerCoreReturnsPredictableInvalidArgumentStatus() {
        let config = vtx_c_mixer_default_config()
        var state = VTXCMixerState()
        XCTAssertEqual(vtx_c_mixer_init(&state, config), VTX_C_MIXER_STATUS_OK)

        XCTAssertEqual(vtx_c_mixer_init(nil, config), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_reset(nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_configure(nil, config), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_clear_voices(nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_one_shot_sample(nil, nil, 0, 1, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_one_shot_sample(&state, nil, 1, 1, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_sample_voice(nil, nil, 0, 1, 0, VTX_C_MIXER_LOOP_FORWARD, 0, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_sample_voice(&state, nil, 1, 1, 0, VTX_C_MIXER_LOOP_FORWARD, 0, 1, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_scheduled_sample_voice(nil, nil, 0, 1, 0, VTX_C_MIXER_LOOP_NONE, 0, 0, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_scheduled_sample_voice(&state, nil, 1, 1, 0, VTX_C_MIXER_LOOP_NONE, 0, 0, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_volume_envelope(nil, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_volume_envelope(&state, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_pan_envelope(nil, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_pan_envelope(&state, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_channel_tag(nil, 0, 0), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_channel_tag(&state, 0, 0), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_stop_voices_for_channel_tag(nil, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_gain_pan_sample_step_update(nil, 0, 0, 1, 1, 1, 0, 1), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_schedule_voice_gain_pan_sample_step_update(&state, 0, 0, 1, 1, 1, 0, 1), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_render(nil, nil, 0), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_render(&state, nil, 1), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_render(&state, nil, 0), VTX_C_MIXER_STATUS_OK)

        var scheduledState = VTXCMixerState()
        XCTAssertEqual(vtx_c_mixer_init(&scheduledState, config), VTX_C_MIXER_STATUS_OK)
        var output = Array(repeating: Float(0), count: 4)
        XCTAssertEqual(
            output.withUnsafeMutableBufferPointer { buffer in
                vtx_c_mixer_render(&scheduledState, buffer.baseAddress, 2)
            },
            VTX_C_MIXER_STATUS_OK
        )
        let sample: [Float] = [1]
        XCTAssertEqual(
            sample.withUnsafeBufferPointer { buffer in
                vtx_c_mixer_add_scheduled_sample_voice(
                    &scheduledState,
                    buffer.baseAddress,
                    1,
                    1,
                    0,
                    VTX_C_MIXER_LOOP_NONE,
                    0,
                    0,
                    1,
                    nil
                )
            },
            VTX_C_MIXER_STATUS_INVALID_ARGUMENT
        )
    }

    func testCSoftwareMixerInitializesWithDefaultRenderConfiguration() {
        let mixer = CSoftwareMixer()

        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(mixer.config.sampleRate, 44_100)
        XCTAssertEqual(mixer.config.channelCount, 2)
        XCTAssertTrue(mixer.config.isInterleaved)
    }

    func testCSoftwareMixerInitializesAndRendersOnBackgroundQueue() {
        let expectation = expectation(description: "background mixer render completes")
        let resultBox = LockedResultBox<MixerRenderBlock>()

        DispatchQueue.global(qos: .userInitiated).async {
            let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2))
            _ = mixer.addScheduledVoice(
                sample: MixerSampleBuffer(monoPCM: Array(repeating: 0.25, count: 2_048)),
                scheduledStartFrame: 0,
                gain: 0.5,
                pan: 0
            )
            resultBox.store(.success(mixer.render(frames: 8_192)))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        let block = try? resultBox.result?.get()
        XCTAssertEqual(block?.frameCount, 8_192)
        XCTAssertEqual(block?.interleavedPCM.count, 16_384)
        XCTAssertEqual(block?.config.channelCount, 2)
    }

    func testCSoftwareMixerCanConfigureSampleRateAndChannelCount() {
        let mixer = CSoftwareMixer()

        mixer.configure(sampleRate: 48_000, channelCount: 1)

        XCTAssertEqual(mixer.config.sampleRate, 48_000)
        XCTAssertEqual(mixer.config.channelCount, 1)
    }

    func testCSoftwareMixerZeroFrameRenderReturnsEmptyBlock() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2))

        let block = mixer.render(frames: 0)

        XCTAssertEqual(block, MixerRenderBlock(config: mixer.config, frameCount: 0, interleavedPCM: []))
    }

    func testCSoftwareMixerPositiveRenderReturnsRequestedFramesAndSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2))

        let block = mixer.render(frames: 8)

        XCTAssertEqual(block.frameCount, 8)
        XCTAssertEqual(block.sampleCount, 16)
        XCTAssertEqual(block.sampleCount, block.frameCount * mixer.config.channelCount)
        XCTAssertEqual(block.interleavedPCM, Array(repeating: Float(0), count: 16))
    }

    func testCSoftwareMixerStopsTaggedChannelWithoutStoppingOtherChannels() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let loudVoice = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 1, 1]))
        mixer.setChannelTag(0, forVoiceAt: loudVoice)
        let quietVoice = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25, 0.25, 0.25]))
        mixer.setChannelTag(1, forVoiceAt: quietVoice)

        XCTAssertEqual(mixer.loadedVoiceCount, 2)
        XCTAssertEqual(mixer.activeVoiceCount, 2)
        XCTAssertEqual(mixer.stopVoices(channel: 0), 1)
        XCTAssertEqual(mixer.loadedVoiceCount, 1)
        XCTAssertEqual(mixer.activeVoiceCount, 1)

        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25, 0.25])
    }

    func testCSoftwareMixerResetIsDeterministic() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 22_050, channelCount: 2))

        let first = mixer.render(frames: 6)
        mixer.reset()
        let second = mixer.render(frames: 6)

        XCTAssertEqual(first, second)
    }

    func testCSoftwareMixerRepeatedRendersAfterResetMatch() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))

        let first = mixer.render(frames: 4)
        _ = mixer.render(frames: 4)
        mixer.reset()
        let reset = mixer.render(frames: 4)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, Array(repeating: Float(0), count: 4))
    }

    func testCSoftwareMixerInvalidConfigurationFallsBackToDeterministicDefaults() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: -1, channelCount: 0))

        XCTAssertEqual(mixer.config, MixerRenderConfig())

        mixer.configure(sampleRate: .nan, channelCount: -4)
        let block = mixer.render(frames: 2)

        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testCSoftwareMixerOneSampleBufferMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let cBlock = cOneShotBlock(sample: sample, frames: 3)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 3)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 1, 0, 0, 0, 0])
    }

    func testCSoftwareMixerMultiSampleBufferMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5, -1])

        let cBlock = cOneShotBlock(sample: sample, frames: 4)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 4)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 1, 0.5, 0.5, -0.5, -0.5, -1, -1])
    }

    func testCSoftwareMixerDefaultPlaybackStepPreservesOneSourceFramePerOutputFrame() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])

        let block = cOneShotBlock(
            sample: sample,
            frames: 5,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1)
        )

        XCTAssertEqual(block.interleavedPCM, [0, 1, 2, 3, 0])
    }

    func testCSoftwareMixerPlaybackStepAdvancesSourceFasterThanDefault() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4, 5])

        let block = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 2
        )

        XCTAssertEqual(block.interleavedPCM, [0, 2, 4, 0])
    }

    func testCSoftwareMixerHalfStepUsesLinearInterpolationDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])

        let block = cOneShotBlock(
            sample: sample,
            frames: 9,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 0.5
        )

        XCTAssertEqual(block.interleavedPCM, [0, 0.5, 1, 1.5, 2, 2.5, 3, 3, 0])
    }

    func testCSoftwareMixerQuarterStepUsesLinearInterpolationDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0, 4, 8])

        let block = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 0.25
        )

        XCTAssertEqual(block.interleavedPCM, [0, 1, 2, 3])
    }

    func testCSoftwareMixerRuntimeStateSamplePositionUsesLinearInterpolation() {
        let sample = MixerSampleBuffer(monoPCM: [0, 4, 8, 12])
        let halfPositionMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let halfPositionVoice = halfPositionMixer.addVoice(sample: sample)
        halfPositionMixer.setRuntimeState(
            CSoftwareMixerVoiceRuntimeState(samplePosition: 0.5),
            forVoiceAt: halfPositionVoice
        )
        let weightedPositionMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let weightedPositionVoice = weightedPositionMixer.addVoice(sample: sample)
        weightedPositionMixer.setRuntimeState(
            CSoftwareMixerVoiceRuntimeState(samplePosition: 1.25),
            forVoiceAt: weightedPositionVoice
        )

        XCTAssertEqual(halfPositionMixer.render(frames: 1).interleavedPCM, [2])
        XCTAssertEqual(weightedPositionMixer.render(frames: 1).interleavedPCM, [5])
    }

    func testCSoftwareMixerIntegerRuntimeStateSamplePositionKeepsPointValue() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0, 4, 8]))
        mixer.setRuntimeState(
            CSoftwareMixerVoiceRuntimeState(samplePosition: 1.0),
            forVoiceAt: voiceIndex
        )

        XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [4])
    }

    func testCSoftwareMixerFractionalSampleStepAccumulationStaysSplitDeterministic() {
        let sample = MixerSampleBuffer(monoPCM: [0, 4, 8, 12])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        singleRenderMixer.addVoice(sample: sample, playbackStep: 0.25)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        splitRenderMixer.addVoice(sample: sample, playbackStep: 0.25)

        let singleRender = singleRenderMixer.render(frames: 7)
        let splitRender = splitRenderMixer.render(frames: 3).interleavedPCM +
            splitRenderMixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(singleRender.interleavedPCM, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testCSoftwareMixerNoLoopInterpolationClampsAtSampleEndSafely() {
        let sample = MixerSampleBuffer(monoPCM: [0, 2, 4])

        let block = cOneShotBlock(
            sample: sample,
            frames: 5,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 0.75
        )

        XCTAssertEqual(block.interleavedPCM, [0, 1.5, 3, 4, 0])
    }

    func testCSoftwareMixerForwardLoopEndpointInterpolationWrapsToLoopStart() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let voiceIndex = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 10, 20, 30]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )
        mixer.setRuntimeState(
            CSoftwareMixerVoiceRuntimeState(samplePosition: 2.75),
            forVoiceAt: voiceIndex
        )

        XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [12.5])
    }

    func testCSoftwareMixerForwardLoopRuntimeStateAtExclusiveEndPreservesOvershoot() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let voiceIndex = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )
        mixer.setRuntimeState(
            CSoftwareMixerVoiceRuntimeState(samplePosition: 3.25),
            forVoiceAt: voiceIndex
        )

        XCTAssertEqual(mixer.render(frames: 3).interleavedPCM, [12.5, 17.5, 12.5])
    }

    func testCSoftwareMixerPingPongEndpointInterpolationReflectsAtTurnaround() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        let voiceIndex = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )
        mixer.setRuntimeState(
            CSoftwareMixerVoiceRuntimeState(samplePosition: 3.25),
            forVoiceAt: voiceIndex
        )

        XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [27.5])
    }

    func testCSoftwareMixerInitialSourceFrameStartsAtRequestedSampleFrame() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])

        let block = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            initialSourceFrame: 2
        )

        XCTAssertEqual(block.interleavedPCM, [2, 3, 0, 0])
    }

    func testCSoftwareMixerForwardLoopInitialSourceFrameAtExclusiveEndStartsAtLoopStart() {
        let sample = MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let block = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            loop: loop,
            initialSourceFrame: 3
        )

        XCTAssertEqual(block.interleavedPCM, [10, 20, 10, 20])
    }

    func testCSoftwareMixerForwardLoopInitialSourceFrameAfterExclusiveEndPreservesTailRead() {
        let sample = MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let block = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            loop: loop,
            initialSourceFrame: 4
        )

        XCTAssertEqual(block.interleavedPCM, [40, 10, 20, 10])
    }

    func testCSoftwareMixerInitialSourceFrameCombinesWithStepAndInterpolation() {
        let sample = MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40])

        let block = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 1.5,
            initialSourceFrame: 1
        )

        XCTAssertEqual(block.interleavedPCM, [10, 25, 40, 0])
    }

    func testCSoftwareMixerInitialSourceFrameBeyondSampleRendersSilenceSafely() {
        let sample = MixerSampleBuffer(monoPCM: [1, 2, 3])

        let block = cOneShotBlock(
            sample: sample,
            frames: 3,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            initialSourceFrame: 3
        )

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0])
    }

    func testCSoftwareMixerInitialSourceFramePreservesSplitAndResetDeterminism() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        singleRenderMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2, initialSourceFrame: 2)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        splitRenderMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2, initialSourceFrame: 2)
        let resetMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        resetMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2, initialSourceFrame: 2)

        let single = singleRenderMixer.render(frames: 6)
        let split = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM
        let resetFirst = resetMixer.render(frames: 6)
        _ = resetMixer.render(frames: 2)
        resetMixer.reset()
        let resetSecond = resetMixer.render(frames: 6)

        XCTAssertEqual(single.interleavedPCM, [0, 0, 2, 3, 4, 0])
        XCTAssertEqual(split, single.interleavedPCM)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, single)
    }

    func testCSoftwareMixerMonoOutputMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let config = MixerRenderConfig(sampleRate: 1_000, channelCount: 1)

        let cBlock = cOneShotBlock(sample: sample, frames: 4, config: config)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 4, config: config)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 0.5, -0.5, 0])
    }

    func testCSoftwareMixerRendersSilenceAfterSampleEndsLikeSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25])

        let cBlock = cOneShotBlock(sample: sample, frames: 5)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0, 0, 0, 0])
    }

    func testCSoftwareMixerRepeatedRenderAfterResetRewindsVoicesDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample)

        let first = mixer.render(frames: 4)
        mixer.reset()
        let second = mixer.render(frames: 4)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, swiftOneShotBlock(sample: sample, frames: 4))
    }

    func testCSoftwareMixerClearVoicesReturnsToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5]))

        mixer.clearVoices()
        let block = mixer.render(frames: 2)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testCSoftwareMixerGainMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, -1])

        let cBlock = cOneShotBlock(sample: sample, frames: 2, gain: 0.5)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 2, gain: 0.5)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.5, 0.5, -0.5, -0.5])
    }

    func testCSoftwareMixerCenterMonoToStereoMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0.25])

        let cBlock = cOneShotBlock(sample: sample, frames: 1, pan: 0)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 1, pan: 0)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.25, 0.25])
    }

    func testCSoftwareMixerPanBehaviorMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let cMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        cMixer.addVoice(sample: sample, gain: 0.25, pan: -1)
        cMixer.addVoice(sample: sample, gain: 0.5, pan: 1)

        let swiftMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        swiftMixer.addVoice(sample: sample, gain: 0.25, pan: -1)
        swiftMixer.addVoice(sample: sample, gain: 0.5, pan: 1)

        let cBlock = cMixer.render(frames: 1)
        let swiftBlock = swiftMixer.render(frames: 1)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.25, 0.5])
    }

    func testCSoftwareMixerGainUpdateMicroRampsInsteadOfStepping() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 40)))

        let update = mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 1, gain: 0.5)
        let block = mixer.render(frames: 35)

        XCTAssertTrue(update.wasAccepted)
        XCTAssertEqual(CSoftwareMixer.gainPanUpdateRampFrameCount, 32)
        XCTAssertEqual(block.interleavedPCM[0], 1)
        XCTAssertEqual(block.interleavedPCM[1], 0.984375, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[16], 0.75, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[32], 0.5, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[33], 0.5, accuracy: 0.000_001)
    }

    func testCSoftwareMixerChannelRampDownUsesFixedReplacementRamp() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let replacedVoice = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 40)))
        let otherVoice = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(0.25), count: 40)))
        mixer.setChannelTag(0, forVoiceAt: replacedVoice)
        mixer.setChannelTag(1, forVoiceAt: otherVoice)

        let rampedCount = mixer.rampDownVoices(channel: 0)
        let block = mixer.render(frames: 34)

        XCTAssertEqual(CSoftwareMixer.replacementStopRampFrameCount, 32)
        XCTAssertEqual(CSoftwareMixer.replacementStopRampFrameCount, CSoftwareMixer.gainPanUpdateRampFrameCount)
        XCTAssertEqual(rampedCount, 1)
        XCTAssertEqual(block.interleavedPCM[0], 1.21875, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[30], 0.28125, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[31], 0.25, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[33], 0.25, accuracy: 0.000_001)
        XCTAssertEqual(mixer.activeVoiceCount, 1)
    }

    func testCSoftwareMixerScheduledReplacementRampRetiresVoice() throws {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let oldVoice = mixer.addScheduledVoice(
            sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 64)),
            scheduledStartFrame: 0
        )
        let newVoice = mixer.addScheduledVoice(
            sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(0.25), count: 64)),
            scheduledStartFrame: 1
        )

        let ramp = mixer.scheduleVoiceRampDownAndDeactivate(
            voiceIndex: try XCTUnwrap(oldVoice),
            scheduledFrame: 1
        )
        let block = mixer.render(frames: 35)

        XCTAssertNotNil(newVoice)
        XCTAssertTrue(ramp.wasAccepted)
        XCTAssertEqual(block.interleavedPCM[0], 1, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[1], 1.21875, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[31], 0.28125, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[32], 0.25, accuracy: 0.000_001)
        XCTAssertEqual(mixer.rampDownCompletionCount, 1)
        XCTAssertEqual(mixer.activeVoiceCount, 1)
    }

    func testCSoftwareMixerPanUpdateMicroRampsInsteadOfStepping() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 40)), pan: 0)

        let update = mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 1, pan: 1)
        let block = mixer.render(frames: 35)

        XCTAssertTrue(update.wasAccepted)
        XCTAssertEqual(block.interleavedPCM[0], 1)
        XCTAssertEqual(block.interleavedPCM[1], 1)
        XCTAssertEqual(block.interleavedPCM[2], 0.96875, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[3], 1, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[64], 0, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[65], 1, accuracy: 0.000_001)
    }

    func testCSoftwareMixerCombinedGainAndPanUpdateRampsBothValues() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 40)), gain: 1, pan: 0)

        let update = mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 1, gain: 0.5, pan: 1)
        let block = mixer.render(frames: 35)

        XCTAssertTrue(update.wasAccepted)
        XCTAssertEqual(block.interleavedPCM[2], 0.9536133, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[3], 0.984375, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[64], 0, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[65], 0.5, accuracy: 0.000_001)
    }

    func testCSoftwareMixerRenderWithoutGainPanUpdatesRemainsUnchanged() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2))
        _ = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]), gain: 0.5, pan: -1)

        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, [0.5, 0, 0.25, 0, -0.25, 0])
    }

    func testCSoftwareMixerGainPanUpdateAfterVoiceEndsIsSafe() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]))

        let update = mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 2, gain: 0.25, pan: -1)
        let block = mixer.render(frames: 4)

        XCTAssertTrue(update.wasAccepted)
        XCTAssertEqual(block.interleavedPCM, [1, 0, 0, 0])
    }

    func testCSoftwareMixerSecondUpdateDuringActiveRampStartsFromInterpolatedValue() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 80)))

        XCTAssertTrue(mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 1, gain: 0).wasAccepted)
        XCTAssertTrue(mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 17, gain: 0.5).wasAccepted)
        let block = mixer.render(frames: 40)

        XCTAssertEqual(block.interleavedPCM[16], 0.5, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[17], 0.46972656, accuracy: 0.000_001)
        XCTAssertEqual(block.interleavedPCM[18], 0.47070312, accuracy: 0.000_001)
    }

    func testCSoftwareMixerImmediateGainUpdatePreservesHardCutSemantics() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let voiceIndex = mixer.addVoice(sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 8)))

        XCTAssertTrue(mixer.scheduleVoiceGainPanImmediateUpdate(voiceIndex: voiceIndex, scheduledFrame: 2, gain: 0).wasAccepted)
        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, [1, 1, 0, 0, 0])
    }

    func testCSoftwareMixerSampleStepUpdateAppliesFromScheduledFrameAndReset() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4, 5])
        let singleMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let splitMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let resetMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let singleVoice = singleMixer.addVoice(sample: sample)
        let splitVoice = splitMixer.addVoice(sample: sample)
        let resetVoice = resetMixer.addVoice(sample: sample)

        XCTAssertTrue(singleMixer.scheduleVoicePlaybackStepUpdate(voiceIndex: singleVoice, scheduledFrame: 2, playbackStep: 2).wasAccepted)
        XCTAssertTrue(splitMixer.scheduleVoicePlaybackStepUpdate(voiceIndex: splitVoice, scheduledFrame: 2, playbackStep: 2).wasAccepted)
        XCTAssertTrue(resetMixer.scheduleVoicePlaybackStepUpdate(voiceIndex: resetVoice, scheduledFrame: 2, playbackStep: 2).wasAccepted)

        let single = singleMixer.render(frames: 5)
        let split = splitMixer.render(frames: 1).interleavedPCM +
            splitMixer.render(frames: 2).interleavedPCM +
            splitMixer.render(frames: 2).interleavedPCM
        let resetFirst = resetMixer.render(frames: 5)
        resetMixer.reset()
        let resetSecond = resetMixer.render(frames: 5)

        XCTAssertEqual(single.interleavedPCM, [0, 1, 2, 4, 0])
        XCTAssertEqual(split, single.interleavedPCM)
        XCTAssertEqual(resetFirst, single)
        XCTAssertEqual(resetSecond, single)
    }

    func testCSoftwareMixerShortForwardLoopSampleStepUpdatesPreservePhaseAfterManyCrossings() throws {
        let loopLength = 188
        let sample = MixerSampleBuffer(monoPCM: (0..<loopLength).map { Float($0) / Float(loopLength - 1) })
        let loop = MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: loopLength)
        let startPosition = 186.28167527251867
        let initialStep = 0.17113042646777588
        let stepUpdates = [
            (frame: 960, step: 0.17514993149344293),
            (frame: 1_920, step: 0.17936279815594305),
            (frame: 2_880, step: 0.18378332306428424),
            (frame: 3_840, step: 0.18842724784165088),
            (frame: 4_800, step: 0.19206718179866925),
        ]
        let totalFrames = 33_600

        func configuredMixer() -> (mixer: CSoftwareMixer, voiceIndex: Int) {
            let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 1))
            let voiceIndex = mixer.addVoice(sample: sample, playbackStep: initialStep, loop: loop)
            mixer.setRuntimeState(
                CSoftwareMixerVoiceRuntimeState(samplePosition: startPosition),
                forVoiceAt: voiceIndex
            )
            for update in stepUpdates {
                XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.frame,
                    playbackStep: update.step
                ).wasAccepted)
            }
            return (mixer, voiceIndex)
        }

        let single = configuredMixer()
        let split = configuredMixer()
        let singleBlock = single.mixer.render(frames: totalFrames)
        let splitPCM = [511, 600, 1_409, 1_234, 2_222, 14_000, 13_624].flatMap {
            split.mixer.render(frames: $0).interleavedPCM
        }

        var rawPosition = startPosition
        var cursorFrame = 0
        var step = initialStep
        for update in stepUpdates {
            rawPosition += Double(update.frame - cursorFrame) * step
            cursorFrame = update.frame
            step = update.step
        }
        rawPosition += Double(totalFrames - cursorFrame) * step
        let expectedCrossings = Int(rawPosition / Double(loopLength))
        let expectedLoopPosition = rawPosition.truncatingRemainder(dividingBy: Double(loopLength))

        XCTAssertEqual(expectedCrossings, 34)
        XCTAssertEqual(expectedLoopPosition, 187.75608901636588, accuracy: 0.000000001)
        XCTAssertFloatArrayEqual(splitPCM, singleBlock.interleavedPCM)

        let singleDiagnostic = try XCTUnwrap(single.mixer.voiceDiagnostic(forVoiceAt: single.voiceIndex))
        let splitDiagnostic = try XCTUnwrap(split.mixer.voiceDiagnostic(forVoiceAt: split.voiceIndex))
        XCTAssertTrue(singleDiagnostic.active)
        XCTAssertEqual(singleDiagnostic.sampleStep, try XCTUnwrap(stepUpdates.last?.step), accuracy: 0.000000000001)
        XCTAssertEqual(singleDiagnostic.samplePosition, expectedLoopPosition, accuracy: 0.000000001)
        XCTAssertEqual(splitDiagnostic.samplePosition, singleDiagnostic.samplePosition, accuracy: 0.000000001)
    }

    func testCSoftwareMixerGainPanRampSplitAndResetRemainDeterministic() {
        let sample = MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 80))
        let singleMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let splitMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let resetMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1))
        let singleVoice = singleMixer.addVoice(sample: sample)
        let splitVoice = splitMixer.addVoice(sample: sample)
        let resetVoice = resetMixer.addVoice(sample: sample)
        singleMixer.scheduleVoiceGainPanUpdate(voiceIndex: singleVoice, scheduledFrame: 1, gain: 0.5)
        splitMixer.scheduleVoiceGainPanUpdate(voiceIndex: splitVoice, scheduledFrame: 1, gain: 0.5)
        resetMixer.scheduleVoiceGainPanUpdate(voiceIndex: resetVoice, scheduledFrame: 1, gain: 0.5)

        let single = singleMixer.render(frames: 40)
        let split = splitMixer.render(frames: 3).interleavedPCM +
            splitMixer.render(frames: 7).interleavedPCM +
            splitMixer.render(frames: 30).interleavedPCM
        let resetFirst = resetMixer.render(frames: 40)
        _ = resetMixer.render(frames: 4)
        resetMixer.reset()
        let resetSecond = resetMixer.render(frames: 40)

        XCTAssertFloatArrayEqual(split, single.interleavedPCM)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, single)
    }

    func testCSoftwareMixerMultipleSmallRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        singleRenderMixer.addVoice(sample: sample)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        splitRenderMixer.addVoice(sample: sample)

        let singleRender = singleRenderMixer.render(frames: 5)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(singleRender, swiftOneShotBlock(sample: sample, frames: 5))
    }

    func testCSoftwareMixerEmptySampleBufferRendersSilenceSafely() {
        let sample = MixerSampleBuffer(monoPCM: [])

        let cBlock = cOneShotBlock(sample: sample, frames: 3)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 3)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerInvalidGainAndPanMatchSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let invalidGainCBlock = cOneShotBlock(sample: sample, frames: 1, gain: .nan, pan: 0)
        let invalidGainSwiftBlock = swiftOneShotBlock(sample: sample, frames: 1, gain: .nan, pan: 0)
        XCTAssertEqual(invalidGainCBlock, invalidGainSwiftBlock)
        XCTAssertEqual(invalidGainCBlock.interleavedPCM, [0, 0])

        let invalidPanCBlock = cOneShotBlock(sample: sample, frames: 1, gain: 1, pan: .infinity)
        let invalidPanSwiftBlock = swiftOneShotBlock(sample: sample, frames: 1, gain: 1, pan: .infinity)
        XCTAssertEqual(invalidPanCBlock, invalidPanSwiftBlock)
        XCTAssertEqual(invalidPanCBlock.interleavedPCM, [1, 1])
    }

    func testCSoftwareMixerNoLoopModeStillMatchesOneShotBehavior() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let loop = MixerSampleLoop(mode: .none, startFrame: 1, endFrame: 3)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [1, 0.5, -0.5, 0, 0]))
    }

    func testCSoftwareMixerForwardLoopRepeatsExclusiveLoopRegionAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 9, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 9, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testCSoftwareMixerForwardLoopCrossesBoundaryInFirstRenderAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1]))
    }

    func testCSoftwareMixerForwardLoopWorksAcrossSmallRenderCalls() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testCSoftwareMixerForwardLoopWorksWithNonNeutralPlaybackStep() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let block = cOneShotBlock(
            sample: sample,
            frames: 6,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 2,
            loop: loop
        )

        XCTAssertEqual(block.interleavedPCM, [0, 2, 1, 3, 2, 1])
    }

    func testCSoftwareMixerForwardLoopStepGreaterThanLoopLengthLandsAtWrappedPosition() {
        let sample = MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let block = cOneShotBlock(
            sample: sample,
            frames: 5,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 5,
            loop: loop
        )

        XCTAssertEqual(block.interleavedPCM, [0, 20, 10, 30, 20])
    }

    func testCSoftwareMixerForwardLoopWorksWithFractionalPlaybackStep() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let block = cOneShotBlock(
            sample: sample,
            frames: 10,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 0.5,
            loop: loop
        )

        XCTAssertEqual(block.interleavedPCM, [0, 0.5, 1, 1.5, 2, 2.5, 3, 2, 1, 1.5])
    }

    func testCSoftwareMixerForwardLoopInitialSourceFrameInsideLoopStaysSplitDeterministic() {
        let sample = MixerSampleBuffer(monoPCM: [0, 10, 20, 30, 40])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        singleRenderMixer.addVoice(sample: sample, playbackStep: 1.25, loop: loop, initialSourceFrame: 2)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        splitRenderMixer.addVoice(sample: sample, playbackStep: 1.25, loop: loop, initialSourceFrame: 2)

        let singleRender = singleRenderMixer.render(frames: 5)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(singleRender.interleavedPCM, [20, 25, 15, 27.5, 10])
        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testCSoftwareMixerPingPongLoopReversesDirectionAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 9, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 9, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testCSoftwareMixerPingPongLoopCrossesBoundaryInFirstRenderAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2]))
    }

    func testCSoftwareMixerPingPongLoopWorksAcrossSmallRenderCalls() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testCSoftwareMixerPingPongLoopWorksWithFractionalPlaybackStep() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        let block = cOneShotBlock(
            sample: sample,
            frames: 12,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            playbackStep: 0.5,
            loop: loop
        )

        XCTAssertEqual(block.interleavedPCM, [0, 0.5, 1, 1.5, 2, 2.5, 3, 2.5, 2, 1.5, 1, 1.5])
    }

    func testCSoftwareMixerLoopSplitRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loops = [
            MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4),
            MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        ]

        for loop in loops {
            let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            singleRenderMixer.addVoice(sample: sample, loop: loop)
            let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            splitRenderMixer.addVoice(sample: sample, loop: loop)

            let singleRender = singleRenderMixer.render(frames: 11)
            let splitRender = splitRenderMixer.render(frames: 4).interleavedPCM +
                splitRenderMixer.render(frames: 1).interleavedPCM +
                splitRenderMixer.render(frames: 6).interleavedPCM

            XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        }
    }

    func testCSoftwareMixerFractionalLoopInterpolationSplitAndResetRemainDeterministic() {
        let sample = MixerSampleBuffer(monoPCM: [0, 4, 8, 12, 16])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        singleRenderMixer.addVoice(sample: sample, playbackStep: 0.75, loop: loop)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        splitRenderMixer.addVoice(sample: sample, playbackStep: 0.75, loop: loop)
        let resetMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        resetMixer.addVoice(sample: sample, playbackStep: 0.75, loop: loop)

        let singleRender = singleRenderMixer.render(frames: 10)
        let splitRender = splitRenderMixer.render(frames: 3).interleavedPCM +
            splitRenderMixer.render(frames: 4).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM
        let resetFirst = resetMixer.render(frames: 10)
        _ = resetMixer.render(frames: 2)
        resetMixer.reset()
        let resetSecond = resetMixer.render(frames: 10)

        XCTAssertEqual(singleRender.interleavedPCM, [0, 3, 6, 9, 12, 6, 6, 9, 12, 6])
        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, singleRender)
    }

    func testCSoftwareMixerResetRestoresForwardLoopOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, swiftOneShotBlock(sample: sample, frames: 9, loop: loop))
    }

    func testCSoftwareMixerResetRestoresPingPongLoopOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, swiftOneShotBlock(sample: sample, frames: 9, loop: loop))
    }

    func testCSoftwareMixerClearVoicesReturnsLoopedMixerToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        _ = mixer.render(frames: 4)
        mixer.clearVoices()
        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerGainAppliesToLoopedOutputAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 2, 3])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, gain: 0.5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, gain: 0.5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0.5, 1, 1.5, 1, 1.5]))
    }

    func testCSoftwareMixerPanAppliesToLoopedOutputAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, 0.25])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let cBlock = cOneShotBlock(sample: sample, frames: 4, pan: -1, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 4, pan: -1, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 0, 0.5, 0, 0.25, 0, 0.5, 0])
    }

    func testCSoftwareMixerInvalidLoopDefinitionsFallBackToOneShotPlaybackLikeSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2])
        let invalidLoops = [
            MixerSampleLoop(mode: .forward, startFrame: -1, endFrame: 2),
            MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4),
            MixerSampleLoop(mode: .forward, startFrame: 2, endFrame: 2),
            MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 2)
        ]

        for loop in invalidLoops {
            let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
            let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

            XCTAssertEqual(cBlock, swiftBlock)
            XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 0, 0]))
        }
    }

    func testCSoftwareMixerLoopedEmptySampleRendersSilenceSafelyLikeSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 1)

        let cBlock = cOneShotBlock(sample: sample, frames: 3, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 3, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerConstantVolumeEnvelopeProducesDeterministicOutput() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0.5)
        ])

        let block = cOneShotBlock(sample: sample, frames: 4, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0.5, 0.5, 0.5, 0.5]))
    }

    func testCSoftwareMixerDescendingVolumeEnvelopeReducesOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 1),
            MixerEnvelopePoint(positionFrame: 2, value: 0)
        ])

        let block = cOneShotBlock(sample: sample, frames: 3, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [1, 0.5, 0]))
    }

    func testCSoftwareMixerAscendingVolumeEnvelopeIncreasesOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 2, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 3, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0.5, 1]))
    }

    func testCSoftwareMixerVolumeEnvelopeFirstAudibleFrameUsesInitialPositionBeforeAdvance() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 1, value: 1)
        ])

        let block = cScheduledBlock(
            sample: sample,
            scheduledStartFrame: 2,
            frames: 4,
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            volumeEnvelope: envelope
        )

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1])
    }

    func testCSoftwareMixerVolumeEnvelopeInterpolatesAndClampsOutsidePoints() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 2, value: 0),
            MixerEnvelopePoint(positionFrame: 4, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 6, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0, 0.5, 1, 1]))
    }

    func testCSoftwareMixerVolumeEnvelopeWorksAcrossPointBoundariesAndSplitRenders() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 1, value: 1),
            MixerEnvelopePoint(positionFrame: 3, value: 0)
        ])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        singleRenderMixer.addVoice(sample: sample, volumeEnvelope: envelope)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        splitRenderMixer.addVoice(sample: sample, volumeEnvelope: envelope)

        let singleRender = singleRenderMixer.render(frames: 4)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 1).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(singleRender.interleavedPCM, stereoPCM(from: [0, 1, 0.5, 0]))
    }

    func testCSoftwareMixerResetRestoresVolumeEnvelopeOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 3, value: 1)
        ])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, volumeEnvelope: envelope)

        let first = mixer.render(frames: 4)
        _ = mixer.render(frames: 2)
        mixer.reset()
        let reset = mixer.render(frames: 4)

        XCTAssertEqual(first, reset)
    }

    func testCSoftwareMixerClearVoicesReturnsEnvelopeEnabledMixerToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 1, 1]),
            volumeEnvelope: MixerEnvelope(points: [
                MixerEnvelopePoint(positionFrame: 0, value: 1),
                MixerEnvelopePoint(positionFrame: 2, value: 0)
            ])
        )

        _ = mixer.render(frames: 2)
        mixer.clearVoices()
        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerInvalidVolumeEnvelopeFallsBackToConstantGainSafely() {
        let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5])
        let invalidEnvelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 0, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 2, volumeEnvelope: invalidEnvelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0.25, 0.5]))
    }

    func testCSoftwareMixerGainCombinesWithVolumeEnvelopeDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0.5)
        ])

        let block = cOneShotBlock(sample: sample, frames: 1, gain: 0.5, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25])
    }

    func testCSoftwareMixerGainEnvelopeAndFadeoutMultiplyDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0.5)
        ])

        let block = cOneShotBlock(
            sample: sample,
            frames: 2,
            gain: 0.5,
            volumeEnvelope: envelope,
            keyOffFrame: 0,
            fadeoutFrameDecrement: 0.5
        )

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25, 0.125, 0.125])
    }

    func testCSoftwareMixerExistingPanStillAppliesWithEnvelopeEnabledVoice() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 2, pan: -1, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 1, 0])
    }

    func testCSoftwareMixerPanningEnvelopeIsDeterministic() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let panEnvelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: -1),
            MixerEnvelopePoint(positionFrame: 2, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 3, panEnvelope: panEnvelope)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 1, 1, 0, 1])
    }

    func testCSoftwareMixerScheduledRenderWithoutVoicesProducesSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0, 0]))
    }

    func testCSoftwareMixerReportsFixedOfflineVoiceCapacityPolicy() {
        XCTAssertEqual(CSoftwareMixer.maximumVoiceCount, 256)
        XCTAssertEqual(CSoftwareMixer.maximumScheduledVoiceCount, 256)
        XCTAssertEqual(CSoftwareMixer.maximumActiveVoiceCount, 256)
        XCTAssertEqual(CSoftwareMixer.maximumVoiceStateEventCount, 4096)
    }

    func testCSoftwareMixerScheduledFrameZeroMatchesImmediateOneShotRendering() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])

        let scheduled = cScheduledBlock(sample: sample, scheduledStartFrame: 0, frames: 5)
        let immediate = cOneShotBlock(sample: sample, frames: 5)

        XCTAssertEqual(scheduled, immediate)
        XCTAssertEqual(scheduled.interleavedPCM, stereoPCM(from: [1, 0.5, -0.5, 0, 0]))
    }

    func testCSoftwareMixerScheduledVoiceRendersSilenceBeforeStartAndBeginsExactlyOnFrame() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 3, frames: 6, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 1, 0])
    }

    func testCSoftwareMixerScheduledVoiceContinuesAcrossSplitRenderCalls() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, 0.25])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2))

        let splitPCM = mixer.render(frames: 1).interleavedPCM +
            mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitPCM, [0, 0, 1, 0.5, 0.25, 0])
    }

    func testCSoftwareMixerScheduledSplitRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(singleRenderMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 4))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(splitRenderMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 4))

        let singleRender = singleRenderMixer.render(frames: 8)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(singleRender.interleavedPCM, stereoPCM(from: [0, 0, 0, 0, 1, 0.5, -0.5, 0]))
    }

    func testCSoftwareMixerScheduledResetRestoresPlaybackDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2))

        let first = mixer.render(frames: 5)
        _ = mixer.render(frames: 3)
        mixer.reset()
        let reset = mixer.render(frames: 5)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, stereoPCM(from: [0, 0, 1, 0.5, 0]))
    }

    func testCSoftwareMixerClearScheduledVoicesReturnsToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5]), scheduledStartFrame: 1))

        mixer.clearScheduledVoices()
        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0, 0]))
    }

    func testCSoftwareMixerMultipleScheduledVoicesRenderAtNonOverlappingPositions() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1, 1]), scheduledStartFrame: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]), scheduledStartFrame: 4))

        let block = mixer.render(frames: 7)

        XCTAssertEqual(block.interleavedPCM, [0, 1, 1, 0, 0.5, 0.25, 0])
    }

    func testCSoftwareMixerOverlappingScheduledVoicesMixDeterministically() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1, 1, 1]), scheduledStartFrame: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]), scheduledStartFrame: 2))

        let block = mixer.render(frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 1, 1.5, 1.25, 0, 0])
    }

    func testCSoftwareMixerGainAppliesToScheduledVoice() {
        let sample = MixerSampleBuffer(monoPCM: [1, -1])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 1, frames: 4, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), gain: 0.5)

        XCTAssertEqual(block.interleavedPCM, [0, 0.5, -0.5, 0])
    }

    func testCSoftwareMixerPanAppliesToScheduledVoice() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 1, frames: 3, pan: -1)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 0, 0, 0])
    }

    func testMixerMixProfileExpectedValuesDocumentReferencePolicy() {
        let centerPan = Float(sqrt(0.5))

        XCTAssertEqual(MixerMixProfile.vtx.panLaw, .linear)
        XCTAssertEqual(MixerMixProfile.vtx.outputScale, 1)
        XCTAssertEqual(MixerMixProfile.vtx.centerPanContribution, 1)
        XCTAssertEqual(MixerMixProfile.vtx.centeredOutputContribution, 1)

        XCTAssertEqual(MixerMixProfile.ft2.panLaw, .ft2EqualPower)
        XCTAssertEqual(MixerMixProfile.ft2.outputScale, 0.3125)
        XCTAssertEqual(MixerMixProfile.ft2.centerPanContribution, centerPan, accuracy: 0.000_001)
        XCTAssertEqual(MixerMixProfile.ft2.centeredOutputContribution, 0.220_970_87, accuracy: 0.000_001)
        XCTAssertEqual(
            MixerMixProfile.ft2.outputScale,
            (MixerMixProfile.ft2ReferenceAmplification * MixerMixProfile.ft2ReferenceMasterVolume) /
                MixerMixProfile.ft2ReferenceOutputDivisor
        )
    }

    func testCSoftwareMixerPanGainHelpersExposeCurrentAndFT2Policies() {
        let centerPan = Float(sqrt(0.5))

        XCTAssertEqual(vtx_c_mixer_pan_left_gain(VTX_C_MIXER_PAN_LAW_LINEAR, 0), 1)
        XCTAssertEqual(vtx_c_mixer_pan_right_gain(VTX_C_MIXER_PAN_LAW_LINEAR, 0), 1)
        XCTAssertEqual(vtx_c_mixer_pan_left_gain(VTX_C_MIXER_PAN_LAW_LINEAR, -1), 1)
        XCTAssertEqual(vtx_c_mixer_pan_right_gain(VTX_C_MIXER_PAN_LAW_LINEAR, -1), 0)
        XCTAssertEqual(vtx_c_mixer_pan_left_gain(VTX_C_MIXER_PAN_LAW_LINEAR, 1), 0)
        XCTAssertEqual(vtx_c_mixer_pan_right_gain(VTX_C_MIXER_PAN_LAW_LINEAR, 1), 1)

        XCTAssertEqual(vtx_c_mixer_pan_left_gain(VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER, 0), centerPan, accuracy: 0.000_001)
        XCTAssertEqual(vtx_c_mixer_pan_right_gain(VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER, 0), centerPan, accuracy: 0.000_001)
        XCTAssertEqual(vtx_c_mixer_pan_left_gain(VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER, -1), 1)
        XCTAssertEqual(vtx_c_mixer_pan_right_gain(VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER, -1), 0)
        XCTAssertEqual(vtx_c_mixer_pan_left_gain(VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER, 1), 0)
        XCTAssertEqual(vtx_c_mixer_pan_right_gain(VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER, 1), 1)
    }

    func testCSoftwareMixerDefaultMixProfileKeepsLinearPanAndUnityOutputScale() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let centered = cOneShotBlock(sample: sample, frames: 1, pan: 0)
        let hardLeft = cOneShotBlock(sample: sample, frames: 1, pan: -1)
        let hardRight = cOneShotBlock(sample: sample, frames: 1, pan: 1)

        XCTAssertEqual(centered.config.mixProfile, .vtx)
        XCTAssertEqual(centered.config.outputScale, 1)
        XCTAssertEqual(centered.interleavedPCM, [1, 1])
        XCTAssertEqual(hardLeft.interleavedPCM, [1, 0])
        XCTAssertEqual(hardRight.interleavedPCM, [0, 1])
    }

    func testCSoftwareMixerFT2MixProfileAppliesOutputScaleOnlyAtPanExtremes() {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let config = MixerRenderConfig(sampleRate: 1_000, channelCount: 2, mixProfile: .ft2)

        let hardLeft = cOneShotBlock(sample: sample, frames: 1, config: config, pan: -1)
        let hardRight = cOneShotBlock(sample: sample, frames: 1, config: config, pan: 1)

        XCTAssertEqual(hardLeft.config.mixProfile, .ft2)
        XCTAssertEqual(hardLeft.config.outputScale, 0.3125)
        XCTAssertEqual(hardLeft.interleavedPCM, [0.3125, 0])
        XCTAssertEqual(hardRight.interleavedPCM, [0, 0.3125])
    }

    func testCSoftwareMixerFT2MixProfileCombinesCenterPanContributionAndOutputScale() {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let config = MixerRenderConfig(sampleRate: 1_000, channelCount: 2, mixProfile: .ft2)

        let block = cOneShotBlock(sample: sample, frames: 1, config: config, pan: 0)
        let expected = MixerMixProfile.ft2.centeredOutputContribution

        XCTAssertFloatArrayEqual(block.interleavedPCM, [expected, expected])
        XCTAssertEqual(expected, 0.220_970_87, accuracy: 0.000_001)
    }

    func testCSoftwareMixerFT2MixProfileFloat32ExportPreservesProfileValues() throws {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let config = MixerRenderConfig(sampleRate: 48_000, channelCount: 2, mixProfile: .ft2)
        let block = cOneShotBlock(sample: sample, frames: 1, config: config, pan: 0)

        let export = try MixerWAVExporter.wavExport(from: block, format: .float32)
        let expected = MixerMixProfile.ft2.centeredOutputContribution
        let wavSamples = [
            Float(bitPattern: readLE32(export.data, offset: 44)),
            Float(bitPattern: readLE32(export.data, offset: 48)),
        ]

        XCTAssertEqual(export.diagnostics.wavFormat, .float32)
        XCTAssertEqual(export.diagnostics.policy.gain, 1)
        XCTAssertEqual(readLE16(export.data, offset: 20), 3)
        XCTAssertEqual(readLE16(export.data, offset: 34), 32)
        XCTAssertEqual(export.diagnostics.postGainPeak, expected, accuracy: 0.000_001)
        XCTAssertFloatArrayEqual(wavSamples, [expected, expected])
    }

    func testCSoftwareMixerScheduledGainPanUpdatesApplyFromFrameAndReset() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        guard let voiceIndex = mixer.addScheduledVoice(sample: sample, scheduledStartFrame: 0, gain: 1, pan: 0) else {
            XCTFail("Expected scheduled voice to be accepted")
            return
        }

        XCTAssertEqual(mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 2, gain: 0.25).wasAccepted, true)
        XCTAssertEqual(mixer.scheduleVoiceGainPanUpdate(voiceIndex: voiceIndex, scheduledFrame: 3, pan: 1).wasAccepted, true)

        let first = mixer.render(frames: 4)
        mixer.reset()
        let reset = mixer.render(frames: 4)

        XCTAssertFloatArrayEqual(first.interleavedPCM, [1, 1, 1, 1, 0.9765625, 0.9765625, 0.92333984, 0.953125])
        XCTAssertEqual(reset, first)
    }

    func testCSoftwareMixerVolumeEnvelopeAppliesFromScheduledVoiceStart() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 2, value: 1)
        ])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 2, frames: 6, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.5, 1, 0])
    }

    func testCSoftwareMixerForwardLoopVoiceCanBeScheduled() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 2, frames: 8, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), loop: loop)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 2, 1, 2, 1])
    }

    func testCSoftwareMixerPingPongLoopVoiceCanBeScheduled() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 3)

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 2, frames: 8, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), loop: loop)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 2, 1, 2, 1])
    }

    func testCSoftwareMixerInvalidScheduledStartIsRejectedSafely() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))

        XCTAssertNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1]), scheduledStartFrame: -1))
        _ = mixer.render(frames: 2)
        XCTAssertNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1]), scheduledStartFrame: 1))
        XCTAssertEqual(mixer.render(frames: 3).interleavedPCM, [0, 0, 0])
    }

    func testSyntheticTrackerTimingFramesPerTickUsesPlaybackTimingFormula() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 183, sampleRate: 44_100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(timing.framesPerTick, 44_100 * (2.5 / 183.0), accuracy: 0.000001)
    }

    func testSyntheticTrackerTimingFramesPerRowUsesConfiguredSpeed() {
        let config = SyntheticTrackerTimingConfig(speed: 3, bpm: 250, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(timing.framesPerTick, 1)
        XCTAssertEqual(timing.framesPerRow, 3)
    }

    func testSyntheticTrackerTimingMapsRowsAndTicksToAbsoluteFrames() {
        let timing = SyntheticTrackerTiming(config: SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100))

        XCTAssertEqual(timing.frameFor(row: 0, tick: 0), 0)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 0), 2)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 3)
    }

    func testSyntheticTrackerTimingUsesDeterministicFloorRoundingForFractionalFrames() {
        let timing = SyntheticTrackerTiming(config: SyntheticTrackerTimingConfig(speed: 2, bpm: 183, sampleRate: 44_100))

        XCTAssertEqual(timing.frameFor(row: 1, tick: 0), 1_204)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 1_807)
    }

    func testSyntheticTrackerTimingInvalidBPMClampsSafely() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 0, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(config.bpm, 1)
        XCTAssertEqual(timing.framesPerTick, 250)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 0), 500)
    }

    func testSyntheticTrackerTimingInvalidSpeedClampsSafely() {
        let config = SyntheticTrackerTimingConfig(speed: 0, bpm: 250, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(config.speed, 1)
        XCTAssertEqual(timing.framesPerRow, 1)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 1)
    }

    func testSyntheticTrackerTimingInvalidSampleRateFallsBackSafely() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 125, sampleRate: .nan)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(config.sampleRate, MixerRenderConfig.defaultSampleRate)
        XCTAssertEqual(timing.framesPerTick, 882)
    }

    func testSyntheticTrackerSchedulerFrameZeroRendersLikeImmediatePlayback() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5])
        let event = SyntheticTrackerEvent(row: 0, tick: 0, sample: sample)

        let scheduled = cSyntheticTrackerBlock(events: [event], frames: 4, timingConfig: config)
        let immediate = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1)
        )

        XCTAssertEqual(scheduled, immediate)
        XCTAssertEqual(scheduled.interleavedPCM, [1, 0.5, 0, 0])
    }

    func testSyntheticTrackerSchedulerLaterRowRendersSilenceBeforeEvent() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5])
        let event = SyntheticTrackerEvent(row: 2, tick: 0, sample: sample)

        let block = cSyntheticTrackerBlock(events: [event], frames: 7)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticTrackerSchedulerRowTickEventStartsAtComputedFrame() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticTrackerScheduler(config: config)
        let event = SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.75]))

        let block = cSyntheticTrackerBlock(events: [event], frames: 5, timingConfig: config)

        XCTAssertEqual(scheduler.frame(for: event), 3)
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.75, 0])
    }

    func testSyntheticTrackerSchedulerMultipleEventsRenderAtDeterministicPositions() {
        let events = [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: MixerSampleBuffer(monoPCM: [1])),
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.5])),
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ]

        let block = cSyntheticTrackerBlock(events: events, frames: 5)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 0.5, 0.25, 0])
    }

    func testSyntheticTrackerSchedulerOverlappingEventsMixDeterministically() {
        let events = [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 1, 1])),
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]))
        ]

        let block = cSyntheticTrackerBlock(events: events, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 1.5, 1.25, 0])
    }

    func testSyntheticTrackerSchedulerSplitRendersMatchOneLargerRender() {
        let events = [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])),
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ]
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticTrackerScheduler(config: config)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        _ = scheduler.schedule(events, on: singleRenderMixer)
        _ = scheduler.schedule(events, on: splitRenderMixer)

        let singleRender = singleRenderMixer.render(frames: 6)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testSyntheticTrackerSchedulerResetRestoresPlaybackDeterministically() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticTrackerScheduler(config: config)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        _ = scheduler.schedule(
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [1, 0.5])),
            on: mixer
        )

        let first = mixer.render(frames: 6)
        _ = mixer.render(frames: 3)
        mixer.reset()
        let reset = mixer.render(frames: 6)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, [0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticPatternEmptyPatternRendersSilence() {
        let pattern = SyntheticPattern(rowCount: 4)

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0, 0, 0])
    }

    func testSyntheticPatternFrameZeroEventMatchesImmediateScheduledPlayback() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let pattern = SyntheticPattern(rowCount: 1, events: [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: sample)
        ])

        let patternBlock = cSyntheticPatternBlock(pattern: pattern, frames: 5)
        let immediateBlock = cScheduledBlock(
            sample: sample,
            scheduledStartFrame: 0,
            frames: 5,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1)
        )

        XCTAssertEqual(patternBlock, immediateBlock)
        XCTAssertEqual(patternBlock.interleavedPCM, [1, 0.5, -0.5, 0, 0])
    }

    func testSyntheticPatternLaterRowRendersSilenceBeforeEvent() {
        let pattern = SyntheticPattern(rowCount: 3, events: [
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 0.5]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 7)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticPatternEventStartsAtSyntheticTimingFrame() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)
        let scheduler = SyntheticPatternScheduler(config: config)
        let event = SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.75]))
        let pattern = SyntheticPattern(rowCount: 2, events: [event])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 5, timingConfig: config)

        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 3)
        XCTAssertEqual(scheduler.frame(for: event), 3)
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.75, 0])
    }

    func testSyntheticPatternMultipleRowsRenderDeterministically() {
        let pattern = SyntheticPattern(rowCount: 3, events: [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: MixerSampleBuffer(monoPCM: [1])),
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.5])),
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 0.5, 0, 0.25, 0])
    }

    func testSyntheticPatternMultipleEventsOnSameRowMixDeterministically() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 1])),
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 5)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1.5, 1.25, 0])
    }

    func testSyntheticPatternDifferentTicksInSameRowRenderDeterministically() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 1, 1])),
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 1.5, 1.25, 0])
    }

    func testSyntheticPatternLoopedEventUsesCForwardLoopBehavior() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(
                row: 1,
                tick: 0,
                sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3]),
                loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
            )
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 8)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 2, 1, 2, 1])
    }

    func testSyntheticPatternEnvelopeEventUsesCEnvelopeBehavior() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(
                row: 1,
                tick: 0,
                sample: MixerSampleBuffer(monoPCM: [1, 1, 1]),
                volumeEnvelope: MixerEnvelope(points: [
                    MixerEnvelopePoint(positionFrame: 0, value: 0),
                    MixerEnvelopePoint(positionFrame: 2, value: 1)
                ])
            )
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.5, 1, 0])
    }

    func testSyntheticPatternSplitRendersMatchOneLargerRender() {
        let pattern = SyntheticPattern(rowCount: 3, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])),
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ])
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticPatternScheduler(config: config)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        _ = scheduler.schedule(pattern, on: singleRenderMixer)
        _ = scheduler.schedule(pattern, on: splitRenderMixer)

        let singleRender = singleRenderMixer.render(frames: 6)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testSyntheticPatternResetRestoresPlaybackDeterministically() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticPatternScheduler(config: config)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [1, 0.5]))
        ])
        _ = scheduler.schedule(pattern, on: mixer)

        let first = mixer.render(frames: 6)
        _ = mixer.render(frames: 3)
        mixer.reset()
        let reset = mixer.render(frames: 6)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, [0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticPatternEmptyRowsAreSafeAndDeterministic() {
        let pattern = SyntheticPattern(rowCount: 4, events: [
            SyntheticTrackerEvent(row: 3, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let first = cSyntheticPatternBlock(pattern: pattern, frames: 8)
        let second = cSyntheticPatternBlock(pattern: pattern, frames: 8)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.interleavedPCM, [0, 0, 0, 0, 0, 0, 1, 0])
    }

    func testSyntheticPatternInvalidRowCountClampsToEmptyPattern() {
        let pattern = SyntheticPattern(rowCount: -4, events: [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 3)

        XCTAssertEqual(pattern.rowCount, 0)
        XCTAssertEqual(pattern.scheduledEvents, [])
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0])
    }

    func testSyntheticPatternEventsBeyondPatternRowCountAreIgnored() {
        let pattern = SyntheticPattern(rowCount: 1, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 4)

        XCTAssertEqual(pattern.scheduledEvents, [])
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testSyntheticPatternInvalidNegativeRowEventsAreIgnored() {
        let pattern = SyntheticPattern(rowCount: 1, events: [
            SyntheticTrackerEvent(row: -1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 3)

        XCTAssertEqual(pattern.scheduledEvents, [])
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0])
    }

    func testCSoftwareMixerEnvelopeSustainHoldsUntilKeyOffFrame() {
        let envelope = MixerEnvelope(
            points: [
                MixerEnvelopePoint(positionFrame: 0, value: 1),
                MixerEnvelopePoint(positionFrame: 1, value: 0.5),
                MixerEnvelopePoint(positionFrame: 3, value: 0)
            ],
            sustainFrame: 1
        )

        let block = cOneShotBlock(
            sample: MixerSampleBuffer(monoPCM: Array(repeating: 1, count: 6)),
            frames: 6,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            volumeEnvelope: envelope,
            keyOffFrame: 4
        )

        XCTAssertEqual(block.interleavedPCM, [1, 0.5, 0.5, 0.5, 0.5, 0.25])
    }

    func testCSoftwareMixerEnvelopeLoopRepeatsWhileKeyedOn() {
        let envelope = MixerEnvelope(
            points: [
                MixerEnvelopePoint(positionFrame: 0, value: 1),
                MixerEnvelopePoint(positionFrame: 1, value: 0.5),
                MixerEnvelopePoint(positionFrame: 2, value: 0.25)
            ],
            loopStartFrame: 1,
            loopEndFrame: 2
        )

        let block = cOneShotBlock(
            sample: MixerSampleBuffer(monoPCM: Array(repeating: 1, count: 6)),
            frames: 6,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            volumeEnvelope: envelope
        )

        XCTAssertEqual(block.interleavedPCM, [1, 0.5, 0.25, 0.5, 0.25, 0.5])
    }

    func testCSoftwareMixerEnvelopeLoopStopsAfterKeyOffFrame() {
        let envelope = MixerEnvelope(
            points: [
                MixerEnvelopePoint(positionFrame: 0, value: 1),
                MixerEnvelopePoint(positionFrame: 1, value: 0.5),
                MixerEnvelopePoint(positionFrame: 2, value: 0.25),
                MixerEnvelopePoint(positionFrame: 3, value: 0)
            ],
            loopStartFrame: 1,
            loopEndFrame: 2
        )

        let block = cOneShotBlock(
            sample: MixerSampleBuffer(monoPCM: Array(repeating: 1, count: 6)),
            frames: 6,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            volumeEnvelope: envelope,
            keyOffFrame: 4
        )

        XCTAssertEqual(block.interleavedPCM, [1, 0.5, 0.25, 0.5, 0.25, 0])
    }

    func testCSoftwareMixerFadeoutAppliesAfterKeyOffFrame() {
        let block = cOneShotBlock(
            sample: MixerSampleBuffer(monoPCM: Array(repeating: 1, count: 8)),
            frames: 7,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            keyOffFrame: 2,
            fadeoutFrameDecrement: 0.25
        )

        XCTAssertEqual(block.interleavedPCM, [1, 1, 1, 0.75, 0.5, 0.25, 0])
    }

    func testSoftwareMixerInitializesWithDefaultRenderConfiguration() {
        let mixer = SoftwareMixer()

        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(mixer.config.sampleRate, 44_100)
        XCTAssertEqual(mixer.config.channelCount, 2)
        XCTAssertTrue(mixer.config.isInterleaved)
    }

    func testSoftwareMixerRenderReturnsRequestedFrameCount() {
        let mixer = SoftwareMixer()

        let block = mixer.render(frames: 16)

        XCTAssertEqual(block.frameCount, 16)
        XCTAssertEqual(block.sampleCount, 32)
        XCTAssertEqual(block.interleavedPCM.count, 16 * mixer.config.channelCount)
    }

    func testSoftwareMixerSilenceRenderingIsDeterministicAfterReset() {
        let mixer = SoftwareMixer()

        let first = mixer.render(frames: 8)
        mixer.reset()
        let second = mixer.render(frames: 8)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.interleavedPCM, Array(repeating: Float(0), count: 16))
    }

    func testSoftwareMixerOneSampleBufferRendersOneFrameThenSilence() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]))

        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, [1, 1, 0, 0, 0, 0])
        XCTAssertEqual(mixer.voices.first?.isActive, false)
    }

    func testSoftwareMixerMultiSampleBufferRendersSamplesInOrder() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5, -1]))

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, [1, 1, 0.5, 0.5, -0.5, -0.5, -1, -1])
    }

    func testSoftwareMixerMonoOutputUsesMonoSampleValues() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]))

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, [1, 0.5, -0.5, 0])
    }

    func testSoftwareMixerRendersSilenceAfterSampleEnds() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25]))

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0, 0, 0, 0])
    }

    func testSoftwareMixerRepeatedRenderAfterResetRewindsVoicesDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25]))

        let first = mixer.render(frames: 4)
        mixer.reset()
        let second = mixer.render(frames: 4)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerClearVoicesReturnsToSilence() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5]))

        mixer.clearVoices()
        let block = mixer.render(frames: 2)

        XCTAssertTrue(mixer.voices.isEmpty)
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testSoftwareMixerGainIsAppliedDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, -1]), gain: 0.5)

        let block = mixer.render(frames: 2)

        XCTAssertEqual(block.interleavedPCM, [0.5, 0.5, -0.5, -0.5])
    }

    func testSoftwareMixerCenterMonoToStereoOutputIsDeterministic() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25]), pan: 0)

        let block = mixer.render(frames: 1)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25])
    }

    func testSoftwareMixerPanBehaviorIsDeterministic() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]), gain: 0.25, pan: -1)
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]), gain: 0.5, pan: 1)

        let block = mixer.render(frames: 1)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.5])
    }

    func testSoftwareMixerMultipleSmallRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let singleRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        singleRenderMixer.addVoice(sample: sample)
        let splitRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        splitRenderMixer.addVoice(sample: sample)

        let singleRender = singleRenderMixer.render(frames: 5)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testSoftwareMixerResetReturnsToInitialDeterministicState() {
        let mixer = SoftwareMixer()
        mixer.configure(sampleRate: 48_000, channelCount: 2)
        let configuredBlock = mixer.render(frames: 4)

        mixer.reset()
        let resetBlock = mixer.render(frames: 4)

        XCTAssertEqual(configuredBlock, resetBlock)
        XCTAssertTrue(mixer.voices.isEmpty)
    }

    func testSoftwareMixerHandlesZeroAndInvalidFrameRequestsSafely() {
        let mixer = SoftwareMixer()

        XCTAssertEqual(mixer.render(frames: 0), MixerRenderBlock(config: mixer.config, frameCount: 0, interleavedPCM: []))
        XCTAssertEqual(mixer.render(frames: -12), MixerRenderBlock(config: mixer.config, frameCount: 0, interleavedPCM: []))

        mixer.configure(sampleRate: -1, channelCount: 0)
        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(mixer.render(frames: 0).sampleCount, 0)
    }

    func testSoftwareMixerOfflineRendererInitializesWithExistingMixer() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 8_000, channelCount: 1))
        let renderer = SoftwareMixerOfflineRenderer(mixer: mixer, maximumFrameCount: 128)

        XCTAssertEqual(renderer.config.sampleRate, 8_000)
        XCTAssertEqual(renderer.config.channelCount, 1)
        XCTAssertEqual(renderer.maximumFrameCount, 128)
    }

    func testSoftwareMixerOfflineRendererCreatesMixerFromRenderConfiguration() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2))

        XCTAssertEqual(renderer.config.sampleRate, 48_000)
        XCTAssertEqual(renderer.config.channelCount, 2)
        XCTAssertEqual(renderer.maximumFrameCount, OfflineRenderRequest.defaultMaximumFrameCount)
    }

    func testSoftwareMixerOfflineRendererRendersExplicitFrameCount() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let result = renderer.render(frames: 16)

        XCTAssertEqual(result.requestedFrameCount, 16)
        XCTAssertEqual(result.renderedFrameCount, 16)
        XCTAssertEqual(result.block.sampleCount, 32)
        XCTAssertFalse(result.wasFrameCountBounded)
    }

    func testSoftwareMixerOfflineRendererConvertsDurationToFramesDeterministically() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let result = renderer.render(durationSeconds: 0.125)

        XCTAssertEqual(result.requestedFrameCount, 125)
        XCTAssertEqual(result.renderedFrameCount, 125)
        XCTAssertEqual(result.block.sampleCount, 250)
    }

    func testSoftwareMixerOfflineRendererReturnsEmptyBlocksForZeroRequests() {
        let renderer = SoftwareMixerOfflineRenderer()

        XCTAssertEqual(renderer.render(frames: 0).block, MixerRenderBlock(config: renderer.config, frameCount: 0, interleavedPCM: []))
        XCTAssertEqual(renderer.render(durationSeconds: 0).block, MixerRenderBlock(config: renderer.config, frameCount: 0, interleavedPCM: []))
    }

    func testSoftwareMixerOfflineRendererHandlesInvalidRequestsSafely() {
        let renderer = SoftwareMixerOfflineRenderer()

        XCTAssertEqual(renderer.render(frames: -64).renderedFrameCount, 0)
        XCTAssertEqual(renderer.render(durationSeconds: -0.5).renderedFrameCount, 0)
        XCTAssertEqual(renderer.render(durationSeconds: .nan).renderedFrameCount, 0)
    }

    func testSoftwareMixerOfflineRendererBoundsOversizedRequests() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2), maximumFrameCount: 10)

        let result = renderer.render(frames: 12)

        XCTAssertEqual(result.requestedFrameCount, 12)
        XCTAssertEqual(result.renderedFrameCount, 10)
        XCTAssertEqual(result.maximumFrameCount, 10)
        XCTAssertTrue(result.wasFrameCountBounded)
        XCTAssertEqual(result.block.sampleCount, 20)
    }

    func testSoftwareMixerOfflineRendererAppliesRequestConfigurationWithinRendererLimit() {
        let renderer = SoftwareMixerOfflineRenderer(maximumFrameCount: 10)
        let request = OfflineRenderRequest(
            config: MixerRenderConfig(sampleRate: 2_000, channelCount: 1),
            frames: 12,
            maximumFrameCount: 20
        )

        let result = renderer.render(request)

        XCTAssertEqual(renderer.config.sampleRate, 2_000)
        XCTAssertEqual(renderer.config.channelCount, 1)
        XCTAssertEqual(result.renderedFrameCount, 10)
        XCTAssertEqual(result.maximumFrameCount, 10)
        XCTAssertTrue(result.wasFrameCountBounded)
    }

    func testSoftwareMixerOfflineRendererRepeatedRenderAfterResetIsDeterministic() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let first = renderer.render(frames: 8)
        renderer.reset()
        let second = renderer.render(frames: 8)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerOfflineRendererRendersSilenceWhenNoVoicesAreLoaded() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let result = renderer.render(frames: 4)

        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 8))
    }

    func testSoftwareMixerOfflineRendererRendersSyntheticOneShotVoice() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        renderer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]), gain: 0.5)

        let result = renderer.render(frames: 5)

        XCTAssertEqual(result.renderedFrameCount, 5)
        XCTAssertEqual(result.block.interleavedPCM, [0.5, 0.5, 0.25, 0.25, -0.25, -0.25, 0, 0, 0, 0])
    }

    func testSoftwareMixerNoLoopModeStillMatchesOneShotBehavior() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]),
            loop: MixerSampleLoop(mode: .none, startFrame: 1, endFrame: 3)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [1, 0.5, -0.5, 0, 0]))
    }

    func testSoftwareMixerForwardLoopRepeatsExclusiveLoopRegion() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 9)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testSoftwareMixerForwardLoopCrossesBoundaryInFirstRender() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1]))
    }

    func testSoftwareMixerForwardLoopWorksAcrossSmallRenderCalls() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testSoftwareMixerPingPongLoopReversesDirectionDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 9)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testSoftwareMixerPingPongLoopCrossesBoundaryInFirstRender() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2]))
    }

    func testSoftwareMixerPingPongLoopWorksAcrossSmallRenderCalls() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testSoftwareMixerLoopSplitRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let forwardLoop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let pingPongLoop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        for loop in [forwardLoop, pingPongLoop] {
            let singleRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            singleRenderMixer.addVoice(sample: sample, loop: loop)
            let splitRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            splitRenderMixer.addVoice(sample: sample, loop: loop)

            let singleRender = singleRenderMixer.render(frames: 11)
            let splitRender = splitRenderMixer.render(frames: 4).interleavedPCM +
                splitRenderMixer.render(frames: 1).interleavedPCM +
                splitRenderMixer.render(frames: 6).interleavedPCM

            XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        }
    }

    func testSoftwareMixerResetRestoresForwardLoopOutputDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerResetRestoresPingPongLoopOutputDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerClearVoicesReturnsLoopedMixerToSilence() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        _ = mixer.render(frames: 4)
        mixer.clearVoices()
        let block = mixer.render(frames: 3)

        XCTAssertTrue(mixer.voices.isEmpty)
        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testSoftwareMixerGainAppliesToLoopedOutput() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 2, 3]),
            gain: 0.5,
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0.5, 1, 1.5, 1, 1.5]))
    }

    func testSoftwareMixerPanAppliesToLoopedOutput() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, 0.25]),
            pan: -1,
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 0.5, 0, 0.25, 0, 0.5, 0])
    }

    func testSoftwareMixerInvalidLoopDefinitionsFallBackToOneShotPlayback() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2])
        let invalidLoops = [
            MixerSampleLoop(mode: .forward, startFrame: -1, endFrame: 2),
            MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4),
            MixerSampleLoop(mode: .forward, startFrame: 2, endFrame: 2),
            MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 2)
        ]

        for loop in invalidLoops {
            let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            mixer.addVoice(sample: sample, loop: loop)

            let block = mixer.render(frames: 5)

            XCTAssertEqual(mixer.voices.first?.loop, MixerSampleLoop.none)
            XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 0, 0]))
        }
    }

    func testSoftwareMixerLoopedEmptySampleRendersSilenceSafely() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: []),
            loop: MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 1)
        )

        let block = mixer.render(frames: 3)

        XCTAssertEqual(mixer.voices.first?.loop, MixerSampleLoop.none)
        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testSoftwareMixerOfflineRendererRendersSyntheticLoopedVoices() {
        let forwardRenderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        forwardRenderer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )
        let pingPongRenderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        pingPongRenderer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let forward = forwardRenderer.render(frames: 6)
        let pingPong = pingPongRenderer.render(frames: 6)

        XCTAssertEqual(forward.block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2]))
        XCTAssertEqual(pingPong.block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1]))
    }
}

private final class LockedResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Value, Error>?

    var result: Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }
}
