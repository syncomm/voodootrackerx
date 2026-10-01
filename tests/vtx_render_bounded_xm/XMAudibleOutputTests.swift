import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMAudibleOutputTests: XCTestCase {
    func testExactFinalStereoInterpolationUnchangedTargetAndReferenceInterruption() throws {
        let config = MixerRenderConfig(sampleRate: 48_000, mixProfile: .vtx)
        var state = MixerAudibleOutputState()
        state.publish(target(0.25, pan: -0.5), config: config)
        state.publish(target(1, pan: 0.5), config: config)
        XCTAssertEqual(state.start, [0.25, 0.25, 0.125])
        XCTAssertEqual(state.target, [1, 0.5, 1])
        for (offset, expected) in [(0, [Float(0.25), 0.25, 0.125]),
            (240, [0.4375, 0.3125, 0.34375]), (480, [0.625, 0.375, 0.5625]),
            (720, [0.8125, 0.4375, 0.78125]), (960, [1, 0.5, 1])] {
            var point = state
            point.advance(offset)
            XCTAssertEqual(point.current, expected)
        }
        state.advance(480)
        let unchanged = state
        state.publish(target(1, pan: 0.5), config: config)
        XCTAssertEqual(state, unchanged)
        // Pinned early-delivery observations prove previous-target rebasing.
        state.publish(target(0.5, pan: -0.5), config: config)
        XCTAssertEqual(state.current, [1, 0.5, 1])
        state.advance(480)
        XCTAssertEqual(state.current, [0.75, 0.5, 0.625])
        state.advance(1000)
        XCTAssertEqual(state.current, [0.5, 0.5, 0.25])
        XCTAssertEqual(state.positionFrame, 960)
    }

    func testCanonicalTargetsTempoSpeedSustainAndReleaseAtBothRates() throws {
        for rate in [44_100.0, 48_000] {
            let plan = adapt(song(commands: [1: cell(effect: 15, param: 250), 2: cell(effect: 15, param: 3),
                3: cell(note: 97)], sustain: 1, fadeout: 1024), rate)
            let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            let semantics = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(updates.map(\.scheduledFrame), semantics.map(\.scheduledFrame))
            XCTAssertEqual(updates[0].durationFrames, 0)
            XCTAssertEqual(updates[1].durationFrames, Int(rate / 50))
            XCTAssertEqual(updates[6].durationFrames, Int(rate / 100))
            XCTAssertEqual(updates[12].speed, 3)
            XCTAssertEqual(updates[12].durationFrames, Int(rate / 100))
            XCTAssertEqual(updates[4...14].map(\.amplitude), Array(repeating: 1, count: 11))
            XCTAssertEqual(updates[15].amplitude, 31.0 / 32)
            XCTAssertEqual(updates[16].amplitude, 0.875 * 30 / 32)
            var held = MixerAudibleOutputState()
            let config = MixerRenderConfig(sampleRate: rate)
            for update in updates.prefix(5) { held.publish(update, config: config); held.advance(update.durationFrames) }
            let before = held
            held.publish(updates[5], config: config)
            XCTAssertEqual(held, before)
        }
    }

    func testQuietHeaderGlobalAndStaticPanUseOneCoalescedTarget() throws {
        for profile in MixerMixProfile.allCases {
            let config = MixerRenderConfig(sampleRate: 48_000, mixProfile: profile)
            let module = song(commands: [0: cell(note: 49, effect: 16, param: 32),
                1: cell(volume: 0x30, effect: 8, param: 192)], volume: 0.25, panning: 64)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 8)
            let renderer = PlaybackSongOfflineRenderer()
            let result = renderer.render(request)
            let updates = try XCTUnwrap(result.plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(updates[0].amplitude, 0.25 * 0.25 * 0.5 * 0.25)
            XCTAssertEqual(updates[6].amplitude, 0.5 * 0.25 * 0.5 * 0.75)
            XCTAssertEqual(updates[6].durationFrames, 240)
            let old = updates[5], next = updates[6]
            for offset in [0, 1, 32, 60, 120, 180, 240] {
                let fraction = Float(offset) / 240
                for channel in 0..<2 {
                    let law = channel == 0 ? config.panLaw.leftGain : config.panLaw.rightGain
                    let start = old.amplitude * law(old.pan), end = next.amplitude * law(next.pan)
                    XCTAssertEqual(result.block.interleavedPCM[2 * (next.scheduledFrame + offset) + channel],
                        (start + (end - start) * fraction) * config.outputScale, accuracy: 0.0000001)
                }
            }
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
        }
    }

    func testGlobalWriteVisibilityFollowsChannelTurnWithoutChangingSemanticGain() throws {
        for writerFirst in [false, true] {
            let plan = adapt(song(globalWriterFirst: writerFirst), 48_000)
            let history = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(history[6].amplitude, 0.75 * (writerFirst ? 0.5 : 1))
            XCTAssertEqual(history[7].amplitude, 0.625 * 0.5)
            XCTAssertEqual(history[6].durationFrames, 960)
            var resetPlan = plan
            let channel = history[6].channelIndex
            resetPlan.playbackStateEvents = [.init(activeEventIndex: 0, channelIndex: channel, scheduledFrame: 5760,
                change: .reset(.init(volumeEnvelope: true, keyOn: true, fadeout: true)))]
            let resetHistory = try XCTUnwrap(resetPlan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(resetHistory[6].amplitude, 0.25 * (writerFirst ? 0.5 : 1))
            XCTAssertEqual(resetHistory[7].amplitude, 0.4375 * 0.5)
            XCTAssertEqual(resetHistory[6].durationFrames, 240)
            XCTAssertTrue(resetHistory[6].rebaseFromCurrent)
        }
    }

    func testEveryWindowBoundaryImportsExactAudibleStateAndPCM() throws {
        for rate in [44_100.0, 48_000] {
            for profile in MixerMixProfile.allCases {
                let config = MixerRenderConfig(sampleRate: rate, channelCount: 2, mixProfile: profile)
                let module = song(commands: [1: cell(effect: 15, param: 250), 2: cell(note: 97)],
                    sustain: 1, fadeout: 1024)
                let full = PlaybackSongOfflineRenderer().render(.init(song: module, config: config, rows: 8))
                let plan = full.plan
                let history = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
                var candidates = Set<Int>()
                for update in history.prefix(20) {
                    let frame = update.scheduledFrame, duration = update.durationFrames
                    for boundary in [frame, frame + 1, frame + duration / 2, frame + max(0, duration - 1), frame + duration] {
                        if boundary > 0 { candidates.insert(boundary) }
                    }
                }
                let boundaries = candidates.sorted()
                let continuous = CSoftwareMixer(config: config)
                let voice = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: continuous)[0]!
                PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: continuous)
                for boundary in boundaries {
                    _ = continuous.render(frames: boundary - Int(continuous.currentFrame))
                    let expected = try XCTUnwrap(continuous.voiceDiagnostic(forVoiceAt: voice)?.audibleOutputState)
                    let carry = try XCTUnwrap(plan.xmAudibleTimeline?.state(eventIndex: 0, before: boundary, config: config))
                    XCTAssertEqual(carry, expected, "boundary \(boundary)")
                    let imported = CSoftwareMixer(config: config)
                    let slot = imported.addVoice(sample: .init(monoPCM: Array(repeating: 1, count: 128)))
                    XCTAssertTrue(imported.setAudibleOutputState(carry, forVoiceAt: slot))
                    PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: slot],
                        on: imported, windowStartFrame: boundary)
                    // Constant public PCM separates output continuity from source interpolation.
                    XCTAssertEqual(imported.render(frames: 64).interleavedPCM,
                        Array(full.block.interleavedPCM[(boundary * 2)..<((boundary + 64) * 2)]))
                }
            }
        }
    }

    func testManagedFactorsAvoidDoubleRampAndRetirementKeeps32FrameLifetime() throws {
        let mixer = CSoftwareMixer(config: .init(sampleRate: 48_000))
        let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 1, count: 2048)))
        mixer.setChannelTag(0, forVoiceAt: voice)
        XCTAssertTrue(mixer.publishAudibleOutput(target(0.25), forVoiceAt: voice))
        XCTAssertTrue(mixer.publishAudibleOutput(target(1, pan: 0.5), forVoiceAt: voice))
        mixer.scheduleVoiceGainPanUpdate(voiceIndex: voice, scheduledFrame: 0, gain: 1, pan: 0.5)
        _ = mixer.render(frames: 480)
        let diagnostic = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
        XCTAssertNil(diagnostic.gainRamp)
        XCTAssertNil(diagnostic.panRamp)
        let before = try XCTUnwrap(diagnostic.audibleOutputState)
        XCTAssertEqual(mixer.rampDownVoices(channel: 0), 1)
        XCTAssertFalse(mixer.publishAudibleOutput(target(1), forVoiceAt: voice))
        XCTAssertFalse(mixer.setAudibleOutputState(before, forVoiceAt: voice))
        let tail = mixer.render(frames: 32).interleavedPCM
        for k in 0..<32 {
            for channel in 0..<2 {
                XCTAssertEqual(tail[k * 2 + channel], before.current[channel + 1] * (1 - Float(k + 1) / 32), accuracy: 0.0000001)
            }
        }
        XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice)).active)
        XCTAssertFalse(mixer.publishAudibleOutput(target(1), forVoiceAt: voice))
        XCTAssertFalse(mixer.setAudibleOutputState(before, forVoiceAt: voice))
    }

    func testFutureNoEnvelopeReleaseCannotChangeEarlierGainPanAudio() throws {
        for rate in [100.0, 44_100, 48_000] {
            let config = MixerRenderConfig(sampleRate: rate, channelCount: 2)
            let writes = [1: cell(volume: 0x30, effect: 8, param: 192)]
            let control = song(commands: writes, fadeout: 1024, hasEnvelope: false)
            let released = song(commands: writes.merging([2: cell(note: 97)]) { _, new in new },
                fadeout: 1024, hasEnvelope: false)
            let renderer = PlaybackSongOfflineRenderer()
            let baseline = renderer.render(.init(song: control, config: config, rows: 8))
            let request = PlaybackSongOfflineRenderRequest(song: released, config: config, rows: 8)
            let result = renderer.render(request)
            let frame = Int(rate * 2.5 / 125) * 12
            XCTAssertEqual(Array(result.block.interleavedPCM[..<(frame * 2)]),
                Array(baseline.block.interleavedPCM[..<(frame * 2)]))
            XCTAssertEqual(result.plan.xmAudibleTimeline?.updates.first?.scheduledFrame, frame)
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM,
                result.block.interleavedPCM)
            XCTAssertEqual(Array(result.block.interleavedPCM[(frame * 2)..<(frame * 2 + 2)]),
                Array(baseline.block.interleavedPCM[(frame * 2)..<(frame * 2 + 2)]))
        }
    }

    func testWindowsInsideReplacementTailPreserveIdentityAndRetirement() {
        let module = song(commands: [1: cell(note: 49), 4: cell(note: 49)])
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 2)
        let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 8)
        let renderer = PlaybackSongOfflineRenderer()
        let full = renderer.render(request)
        for rows in [1, 2, 3] {
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM,
                full.block.interleavedPCM)
        }
        let index = renderer.makeWindowedRenderScheduleIndex(for: full.plan,
            totalFrames: full.block.frameCount, windowRows: 1, includedEventIndices: nil, config: config)
        let tails = index.windows.flatMap(\.continuations).filter { $0.runtimeState.gainRamp?.deactivateAfterRamp == true }
        XCTAssertFalse(tails.isEmpty)
        XCTAssertTrue(tails.allSatisfy { $0.audibleOutputState?.raw.retiring == 1 })
    }

    func testHardECxRemainsImmediateAndQuickHandoffUsesSameState() throws {
        let module = song(commands: [1: cell(effect: 14, param: 0xC2)])
        let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 48_000), rows: 8)
        let renderer = PlaybackSongOfflineRenderer()
        let result = renderer.render(request)
        XCTAssertGreaterThan(result.block.interleavedPCM[7680 * 2 - 1], 0)
        XCTAssertTrue(result.block.interleavedPCM[(7680 * 2)...].allSatisfy { $0 == 0 })
        XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
        for (rate, duration) in [(48_000.0, 240), (44_100.0, 220)] {
            var state = MixerAudibleOutputState()
            let config = MixerRenderConfig(sampleRate: rate)
            state.publish(target(1), config: config)
            state.publish(target(0.25, duration: duration), config: config)
            state.advance(duration)
            XCTAssertEqual(state.current, [0.25, 0.25, 0.25])
            state.advance(Int(rate / 50) - duration)
            state.publish(target(0.4375, duration: Int(rate / 50)), config: config)
            XCTAssertEqual(state.start, [0.25, 0.25, 0.25])
            XCTAssertEqual(state.target, [0.4375, 0.4375, 0.4375])
        }
    }

    private func target(_ amplitude: Float, pan: Float = 0, duration: Int = 960) -> PlaybackXMAudibleUpdate {
        .init(eventIndex: 0, channelIndex: 0, source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), tick: 0,
            scheduledFrame: 0, bpm: 125, speed: 6, amplitude: amplitude, pan: pan, durationFrames: duration, intent: "test")
    }

    private func adapt(_ module: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
    }

    private func cell(note: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: note == 49 ? 1 : 0, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(commands: [Int: PlaybackCell] = [:], volume: Float = 1, panning: UInt8 = 128,
                      sustain: Int? = nil, fadeout: Int = 0, globalWriterFirst: Bool? = nil, hasEnvelope: Bool = true) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1, count: 256),
            volume: volume, panning: panning, relativeNote: 0, finetune: 0, baseSampleRate: 100,
            loopStart: 0, loopLength: 256, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(enabled: hasEnvelope,
            points: [(0, 16), (4, 64), (8, 32)].map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: sustain, loopStartPointIndex: nil, loopEndPointIndex: nil,
            typeFlags: sustain == nil ? 1 : 3, fadeout: fadeout)
        return PlaybackSong(title: "Audible output cadence", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in
                var cells = [commands[row] ?? (row == 0 ? cell(note: 49) : cell())]
                if let first = globalWriterFirst {
                    let writer = row == 1 ? cell(effect: 16, param: 32) : cell()
                    if first { cells.insert(writer, at: 0) } else { cells.append(writer) }
                }
                return .init(index: row, cells: cells)
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: envelope)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
