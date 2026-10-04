import MixerCore
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMResetOutputTests: XCTestCase {
    private let reset = MixerPlaybackReset(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true)

    func testResetInteriorsCompletionHoldAndOrdinaryResumeAcrossRatesAndTempos() throws {
        for rate in [32_000.0, 44_100, 48_000] {
            for bpm in [125, 250] {
                for rising in [false, true] {
                    let song = fixture(rising: rising, bpm: bpm)
                    let tick = Int(rate * 2.5 / Double(bpm)), n = tick * 18, d = Int(rate * 0.005)
                    let plan = prepared(song, rate: rate, frame: n)
                    let config = MixerRenderConfig(sampleRate: rate, mixProfile: .ft2)
                    let pcm = PlaybackSongOfflineRenderer(preparedPlan: plan).render(.init(song: song,
                        config: config, rows: 8)).block.interleavedPCM
                    let publication = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == n })
                    XCTAssertEqual(publication.intent, "nonretriggering_reset")
                    XCTAssertTrue(publication.rebaseFromCurrent)
                    XCTAssertEqual(publication.durationFrames, d)
                    XCTAssertEqual(plan.xmEnvelopeTimeline?.updates.first { $0.scheduledFrame == n }?.state.volumeTick, 0)
                    let start: Float = rising ? 1 : 0.25, target: Float = rising ? 0.25 : 1
                    let scale = Float(0.25) * config.panLaw.leftGain(for: 0) * config.outputScale
                    for k in [0, 1, d / 4, d / 2, d * 3 / 4, d, d + 1, tick - 1] {
                        let expected = (start + (target - start) * min(1, Float(k) / Float(d))) * scale
                        XCTAssertEqual(pcm[(n + k) * 2], expected, accuracy: 1e-7)
                        XCTAssertEqual(pcm[(n + k) * 2 + 1], expected, accuracy: 1e-7)
                    }
                    XCTAssertEqual(pcm[n * 2], pcm[(n - 1) * 2])
                    XCTAssertEqual(pcm[(n + tick) * 2], target * scale)
                    let ordinaryInterior = target + (rising ? Float(0.25) : -0.25) * Float(tick / 2) / Float(tick)
                    XCTAssertEqual(pcm[(n + tick + tick / 2) * 2], ordinaryInterior * scale, accuracy: 1e-7)
                    XCTAssertLessThanOrEqual(abs(pcm[(n + d) * 2] - pcm[(n + d - 1) * 2]), 0.75 * scale / Float(d) + 1e-7)
                }
            }
        }
    }

    func testResetInterruptsCurrentAudibleStereoValueAndPreservesSource() throws {
        let song = fixture(), n = 1440
        let plan = prepared(song, frame: n)
        let config = MixerRenderConfig(sampleRate: 48_000)
        let mixer = CSoftwareMixer(config: config)
        let slots = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)
        let voice = try XCTUnwrap(slots[0])
        PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: mixer)
        _ = mixer.render(frames: n)
        let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
        XCTAssertEqual(before.audibleOutputState?.current, [0.875, 0.875, 0.875])
        XCTAssertEqual(before.audibleOutputState?.target, [0.75, 0.75, 0.75])
        XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [0.21875, 0.21875])
        let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
        XCTAssertEqual(after.audibleOutputState?.start, before.audibleOutputState?.current)
        XCTAssertEqual(after.audibleOutputState?.target, [1, 1, 1])
        XCTAssertEqual(after.samplePosition, before.samplePosition + before.sampleStep, accuracy: 1e-10)
        XCTAssertEqual(after.sampleStep, before.sampleStep)
        XCTAssertEqual(after.channelTag, before.channelTag)
        XCTAssertEqual(after.pingPongDirection, before.pingPongDirection)
        XCTAssertEqual(plan.pattern.events.count, 1)
    }

    func testReleasedResetIncludesSameFrameVolumePanAndGlobalFactors() throws {
        for rate in [44_100.0, 48_000] {
            let song = fixture(volume: 0.25, commands: [0: cell(note: 49, effect: 16, param: 32),
                2: cell(note: 97), 3: cell(volume: 0x30, effect: 8, param: 224)], fadeout: 1024)
            let n = Int(rate / 50) * 18, d = Int(rate * 0.005)
            let plan = prepared(song, rate: rate, frame: n)
            let config = MixerRenderConfig(sampleRate: rate)
            let target = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == n })
            XCTAssertEqual(target.amplitude, 0.5 * 0.5)
            let semantic = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates.first { $0.scheduledFrame == n })
            XCTAssertTrue(semantic.state.keyOn)
            XCTAssertEqual(semantic.state.fadeoutAccumulator, 32_768)
            XCTAssertEqual(semantic.state.volumeTick, 0)
            let start = try XCTUnwrap(plan.xmAudibleTimeline?.state(eventIndex: 0, before: n, config: config)).current
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
            let request = PlaybackSongOfflineRenderRequest(song: song, config: config, rows: 8)
            let full = renderer.render(request).block.interleavedPCM
            for (channel, panGain) in [config.panLaw.leftGain(for: target.pan), config.panLaw.rightGain(for: target.pan)].enumerated() {
                let end = target.amplitude * panGain
                for k in [0, d / 2, d, d + 1] {
                    XCTAssertEqual(full[(n + k) * 2 + channel],
                        0.25 * (start[channel + 1] + (end - start[channel + 1]) * min(1, Float(k) / Float(d))), accuracy: 1e-7)
                }
            }
            for rows in [1, 2, 3, 5] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, full)
            }
        }
    }

    func testWindowImportAcrossResetAndLaterBPMAndSpeedChanges() throws {
        for rate in [44_100.0, 48_000] {
            for profile in MixerMixProfile.allCases {
                let song = fixture(commands: [2: cell(effect: 15, param: 250), 3: cell(effect: 15, param: 3)])
                let tick = Int(rate / 50), n = tick * 6, d = Int(rate * 0.005)
                let plan = prepared(song, rate: rate, frame: n)
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
                let request = PlaybackSongOfflineRenderRequest(song: song, config: config, rows: 8)
                let full = renderer.render(request).block.interleavedPCM
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, full)
                let crossing = PlaybackSongOfflineRenderer(preparedPlan: prepared(song, rate: rate, frame: n - d / 2))
                XCTAssertEqual(crossing.renderWindowed(request, windowRows: 1).block.interleavedPCM,
                    crossing.render(request).block.interleavedPCM)
                let targets = try XCTUnwrap(plan.xmAudibleTimeline?.updates)
                XCTAssertTrue(targets.filter { $0.bpm == 250 }.allSatisfy { $0.durationFrames == Int(rate / 100) })
                XCTAssertTrue(targets.contains { $0.speed == 3 && $0.bpm == 250 })
                // Separate from the row-window check: import exact shared state at arbitrary frame boundaries.
                for boundary in [n - 1, n, n + 1, n + d / 2, n + d, n + d + 1, tick * 7, tick * 12 + 1] {
                    let carry = try XCTUnwrap(plan.xmAudibleTimeline?.state(eventIndex: 0, before: boundary, config: config))
                    let mixer = CSoftwareMixer(config: config)
                    let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.25, count: 128)))
                    XCTAssertTrue(mixer.setAudibleOutputState(carry, forVoiceAt: voice))
                    PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice],
                        on: mixer, windowStartFrame: boundary)
                    XCTAssertEqual(mixer.render(frames: 64).interleavedPCM, Array(full[(boundary * 2)..<((boundary + 64) * 2)]))
                }
            }
        }
    }

    func testUnchangedResetDoesNotRestartInFlightTargetAndOrdinaryInterruptionIsPreserved() {
        let config = MixerRenderConfig(sampleRate: 48_000)
        func target(_ amplitude: Float, reset: Bool = false) -> PlaybackXMAudibleUpdate {
            .init(eventIndex: 0, channelIndex: 0, source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
                tick: 0, scheduledFrame: 0, bpm: 125, speed: 6, amplitude: amplitude, pan: 0,
                durationFrames: reset ? 240 : 960, intent: "test", rebaseFromCurrent: reset)
        }
        var state = MixerAudibleOutputState()
        state.publish(target(0.25), config: config)
        state.publish(target(1), config: config)
        state.advance(360)
        let before = state
        state.publish(target(1, reset: true), config: config)
        XCTAssertEqual(state, before)
        state.publish(target(0.5, reset: true), config: config)
        XCTAssertEqual(state.start, before.current)
        state.advance(120)
        state.publish(target(0.75), config: config)
        XCTAssertEqual(state.start, [0.5, 0.5, 0.5])
        XCTAssertEqual(state.durationFrames, 960)
    }

    func testResetPublicationDoesNotTouchPingPongCursorOrSoftenHardStop() {
        var state = VTXCMixerState()
        XCTAssertEqual(vtx_c_mixer_init(&state, .init(sample_rate: 48_000, channel_count: 2,
            pan_law: VTX_C_MIXER_PAN_LAW_LINEAR, output_scale: 1)), VTX_C_MIXER_STATUS_OK)
        defer { _ = vtx_c_mixer_clear_voices(&state) }
        let pcm = Array(repeating: Float(0.25), count: 16)
        var voice: UInt32 = 0
        pcm.withUnsafeBufferPointer {
            XCTAssertEqual(vtx_c_mixer_add_one_shot_sample(&state, $0.baseAddress, 16, 1, 0, &voice), VTX_C_MIXER_STATUS_OK)
        }
        state.voices.0.sample_position = 6.75
        state.voices.0.sample_step = 0.75
        state.voices.0.loop_mode = VTX_C_MIXER_LOOP_PING_PONG
        state.voices.0.loop_start_frame = 2
        state.voices.0.loop_end_frame = 12
        state.voices.0.ping_pong_direction = -1
        let before = state.voices.0
        XCTAssertEqual(vtx_c_mixer_publish_voice_output(&state, voice, 0.25, 0, 0, 0), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_publish_voice_output(&state, voice, 1, 0.5, 240, 1), VTX_C_MIXER_STATUS_OK)
        let after = state.voices.0
        XCTAssertEqual(after.sample_pcm, before.sample_pcm)
        XCTAssertEqual(after.sample_position, before.sample_position)
        XCTAssertEqual(after.sample_step, before.sample_step)
        XCTAssertEqual(after.loop_mode, before.loop_mode)
        XCTAssertEqual(after.loop_start_frame, before.loop_start_frame)
        XCTAssertEqual(after.loop_end_frame, before.loop_end_frame)
        XCTAssertEqual(after.ping_pong_direction, before.ping_pong_direction)
        XCTAssertEqual(state.voice_count, 1)
        XCTAssertEqual(vtx_c_mixer_clear_voices(&state), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(vtx_c_mixer_publish_voice_output(&state, voice, 1, 0, 240, 1), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        var output = Array(repeating: Float(1), count: 2)
        XCTAssertEqual(vtx_c_mixer_render(&state, &output, 1), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(output, [0, 0])
    }

    func testNoEnvelopeResetRestoresReleasedOutputButNeutralResetPreservesGenericRamp() throws {
        let neutral = fixture(commands: [1: cell(volume: 0x30, effect: 8, param: 192)], hasEnvelope: false)
        let config = MixerRenderConfig(sampleRate: 100)
        let request = PlaybackSongOfflineRenderRequest(song: neutral, config: config, rows: 8)
        let neutralPlan = prepared(neutral, rate: 100, frame: 24)
        XCTAssertTrue(try XCTUnwrap(neutralPlan.xmAudibleTimeline?.updates).isEmpty)
        XCTAssertEqual(PlaybackSongOfflineRenderer(preparedPlan: neutralPlan).render(request).block.interleavedPCM,
            PlaybackSongOfflineRenderer().render(request).block.interleavedPCM)
        for rate in [44_100.0, 48_000] {
            let song = fixture(commands: [1: cell(note: 97), 2: cell(effect: 12, param: 64)], fadeout: 1024, hasEnvelope: false)
            let n = Int(rate / 50) * 12, d = Int(rate * 0.005)
            let plan = prepared(song, rate: rate, frame: n)
            let pcm = PlaybackSongOfflineRenderer(preparedPlan: plan).render(.init(song: song,
                config: .init(sampleRate: rate), rows: 8)).block.interleavedPCM
            XCTAssertEqual(pcm[n * 2], 0)
            XCTAssertEqual(pcm[(n + d / 2) * 2], 0.125)
            XCTAssertEqual(pcm[(n + d) * 2], 0.25)
            XCTAssertTrue(pcm[(n + d)...].suffix(100).allSatisfy { $0 == 0.25 })
            let changedPlan = prepared(neutral, rate: rate, frame: n / 2)
            let publication = try XCTUnwrap(changedPlan.xmAudibleTimeline?.updates.first)
            XCTAssertEqual(publication.scheduledFrame, n / 2)
            XCTAssertEqual(publication.activation, .init(amplitude: 1, pan: 0))
            XCTAssertEqual(publication.amplitude, 0.5)
            let changedConfig = MixerRenderConfig(sampleRate: rate)
            let changedRequest = PlaybackSongOfflineRenderRequest(song: neutral, config: changedConfig, rows: 8)
            let changedRenderer = PlaybackSongOfflineRenderer(preparedPlan: changedPlan)
            let changedPCM = changedRenderer.render(changedRequest).block.interleavedPCM
            for (channel, panGain) in [changedConfig.panLaw.leftGain(for: publication.pan),
                                      changedConfig.panLaw.rightGain(for: publication.pan)].enumerated() {
                for k in [0, d / 2, d] {
                    XCTAssertEqual(changedPCM[(n / 2 + k) * 2 + channel],
                        0.25 * (1 + (0.5 * panGain - 1) * Float(k) / Float(d)), accuracy: 1e-7)
                }
            }
            XCTAssertEqual(changedRenderer.renderWindowed(changedRequest, windowRows: 1).block.interleavedPCM, changedPCM)
        }
    }

    private func prepared(_ song: PlaybackSong, rate: Double = 48_000, frame: Int) -> PlaybackSongSyntheticPlan {
        var plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
        plan.playbackStateEvents = [.init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: frame, change: .reset(reset))]
        return plan
    }

    private func cell(note: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: note == 49 ? 1 : 0, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func fixture(rising: Bool = false, bpm: Int = 125, volume: Float = 1,
                         commands: [Int: PlaybackCell] = [:], fadeout: Int = 0, hasEnvelope: Bool = true) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: volume, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 100,
            loopStart: 0, loopLength: 256, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(enabled: hasEnvelope,
            points: [(0, rising ? 16 : 64), (3, rising ? 64 : 16), (20, rising ? 64 : 16)].map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: fadeout)
        return PlaybackSong(title: "Reset output", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in
                .init(index: row, cells: [commands[row] ?? (row == 0 ? cell(note: 49) : cell())])
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: envelope)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: bpm), usesLinearFrequencyTable: true)
    }
}
