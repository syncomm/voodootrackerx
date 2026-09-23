import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMEnvelopeSemanticTests: XCTestCase {
    func testInitialRisingFallingTargetsPublishOncePerCanonicalTick() throws {
        for (rate, bpm, frames) in [(48_000.0, 125, 960), (48_000, 250, 480), (44_100, 125, 882)] {
            let module = song(envelope: envelope([(0, 16), (4, 64), (8, 32)]), bpm: bpm)
            let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
            let updates = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(Array(updates.prefix(9)).map(\.scheduledFrame), (0..<9).map { $0 * frames })
            XCTAssertEqual(Array(updates.prefix(9)).map(\.state.volumeTick), Array(0...8))
            XCTAssertEqual(Array(updates.prefix(9)).map(\.state.volumeValue), [0.25, 0.4375, 0.625, 0.8125, 1, 0.875, 0.75, 0.625, 0.5])
            let (mixer, voice) = direct(plan, rate: rate)
            for update in updates.prefix(9) {
                let pcm = mixer.render(frames: frames).interleavedPCM
                XCTAssertTrue(pcm.allSatisfy { $0 == update.state.volumeValue })
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.envelopeSemanticState, update.state)
            }
        }
    }

    func testCarriedClockFollowsLaterBPMAndSpeedWithoutStartupCadence() throws {
        let module = song(envelope: envelope([(0, 16), (4, 64), (40, 16)]),
            commands: [1: cell(effect: 15, parameter: 250), 2: cell(effect: 15, parameter: 3)])
        let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        let updates = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
        XCTAssertEqual(Array(updates[5...9]).map(\.scheduledFrame), [4800, 5760, 6240, 6720, 7200])
        XCTAssertEqual(Array(updates[5...9]).map(\.bpm), [125, 250, 250, 250, 250])
        XCTAssertEqual(Array(updates[12...15]).map(\.speed), [3, 3, 3, 3])
        XCTAssertEqual(Array(updates[12...15]).map(\.source.rowIndex), [2, 2, 2, 3])
        XCTAssertEqual(Array(updates[12...15]).map(\.tick), [0, 1, 2, 0])
        XCTAssertEqual(Array(updates[12...15]).map(\.state.volumeTick), [12, 13, 14, 15])
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48_000)
        let semantic = runtime.events.filter { if case .envelopeSemanticUpdate = $0.action { return true }; return false }
        XCTAssertEqual(semantic.map(\.scheduledFrame), updates.map(\.scheduledFrame))
        XCTAssertEqual(semantic.map(\.source), updates.map(\.source))
        XCTAssertEqual(semantic.map(\.syntheticTick), updates.map(\.tick))
        XCTAssertTrue(semantic.allSatisfy { $0.activeEventIndex == 0 && $0.channelIndex == 0 })
    }

    func testSustainReleaseFadeoutAndLoopTargets() throws {
        let sustained = song(envelope: envelope([(0, 16), (3, 64), (15, 16)], sustain: 1, fadeout: 1024),
            commands: [2: cell(note: 97)])
        let plan = PlaybackSongSyntheticAdapter.adapt(sustained, orderIndex: 0, sampleRate: 48_000)
        let updates = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
        XCTAssertEqual(Array(updates[3...12]).map(\.state.volumeTick), Array(repeating: 3, count: 10))
        XCTAssertTrue(updates[11].state.keyOn)
        XCTAssertFalse(updates[12].state.keyOn)
        XCTAssertEqual(updates[12].state.fadeoutAccumulator, 31_744)
        XCTAssertEqual(updates[13].state.volumeTick, 4)
        XCTAssertEqual(updates[13].state.volumeValue, 0.9375)
        XCTAssertEqual(updates[43].state.fadeoutAccumulator, 0)
        XCTAssertEqual(updates[44].state.fadeoutAccumulator, 0)
        for sustain in [nil, 2] as [Int?] {
            let module = song(envelope: envelope([(0, 16), (2, 32), (6, 64), (10, 16)], sustain: sustain, loop: (1, 2)),
                commands: [2: cell(note: 97)])
            let clock = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000).xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(Array(clock.prefix(11)).map(\.state.volumeTick), [0, 1, 2, 3, 4, 5, 2, 3, 4, 5, 2])
            XCTAssertEqual(Array(clock[12...15]).map(\.state.volumeTick), sustain == nil ? [4, 5, 2, 3] : [4, 5, 6, 7])
        }
    }

    func testFadeoutIntegerDecrementAndClampIncludeReleaseTickAtEveryRate() throws {
        for rate in [44_100.0, 48_000] {
            for fadeout in [0, 1, 1024, 1234, 32_768, 65_535] {
                let module = song(envelope: envelope([(0, 64), (100, 64)], fadeout: fadeout),
                    commands: [1: cell(note: 97), 2: cell(effect: 15, parameter: 250)])
                let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
                let updates = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                let (mixer, voice) = direct(plan, rate: rate)
                for (index, update) in updates.enumerated() {
                    XCTAssertEqual(update.state.fadeoutAccumulator, max(0, 32_768 - max(0, index - 5) * fadeout))
                    _ = mixer.render(frames: update.scheduledFrame + 1 - Int(mixer.currentFrame))
                    let actual = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                    XCTAssertEqual(actual.envelopeSemanticState, update.state)
                    XCTAssertEqual(actual.fadeoutValue, update.state.fadeoutValue)
                    XCTAssertTrue(actual.active)
                }
            }
        }
    }

    func testKeyOffWithoutEnvelopeKeepsSourceAndLaterVolumeCanRestoreResidualFadeout() throws {
        let module = song(envelope: envelope([], fadeout: 1024),
            commands: [1: cell(note: 97), 2: cell(effect: 12, parameter: 64)])
        let config = MixerRenderConfig(sampleRate: 48_000, channelCount: 1)
        let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 16)
        let renderer = PlaybackSongOfflineRenderer()
        let result = renderer.render(request)
        let updates = result.diagnostics.voiceStateUpdates.filter(\.applied)
        XCTAssertEqual(updates.map(\.effectiveVolumeAfter), [0, 64])
        XCTAssertTrue(updates.allSatisfy { $0.activeEventIndex == 0 })
        XCTAssertEqual(result.block.interleavedPCM[5760 + 32], 0)
        XCTAssertEqual(result.block.interleavedPCM[11520 + 32], 25.0 / 32)
        XCTAssertTrue(result.block.interleavedPCM[35520...].allSatisfy { $0 == 0 })
        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
    }

    func testPanClockIsInertAndWindowImportsMatchAcrossReleaseLoopAndTimingChanges() throws {
        let pan = PlaybackPanningEnvelope(enabled: true, points: [.init(tick: 0, value: 0), .init(tick: 4, value: 64)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 1, typeFlags: 5)
        let module = song(envelope: envelope([(0, 16), (2, 32), (6, 64)], loop: (1, 2), fadeout: 1234), pan: pan,
            commands: [1: cell(effect: 15, parameter: 250), 2: cell(note: 97), 3: cell(effect: 15, parameter: 3)])
        for rate in [44_100.0, 48_000] {
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 16)
            let renderer = PlaybackSongOfflineRenderer()
            let result = renderer.render(request)
            for window in [1, 2, 3, 5, 7] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, result.block.interleavedPCM)
                let index = renderer.makeWindowedRenderScheduleIndex(for: result.plan,
                    totalFrames: result.block.frameCount, windowRows: window, includedEventIndices: nil)
                let (continuous, voice) = direct(result.plan, rate: rate)
                for bucket in index.windows where bucket.startFrame > 0 {
                    _ = continuous.render(frames: bucket.startFrame - Int(continuous.currentFrame))
                    let actual = try XCTUnwrap(continuous.voiceDiagnostic(forVoiceAt: voice)?.envelopeSemanticState)
                    let carry = try XCTUnwrap(bucket.continuations.first)
                    XCTAssertEqual(carry.envelopeSemanticState, actual)
                    let imported = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
                    let slot = try XCTUnwrap(PlaybackSongOfflineRenderer.scheduleContinuation(carry, on: imported).voiceIndex)
                    XCTAssertEqual(imported.voiceDiagnostic(forVoiceAt: slot)?.envelopeSemanticState, actual)
                }
            }
            let states = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(Array(states.prefix(9)).map(\.state.panTick), [0, 1, 2, 3, 0, 1, 2, 3, 0])
            for frame in 0..<result.block.frameCount {
                XCTAssertEqual(result.block.interleavedPCM[frame * 2], result.block.interleavedPCM[frame * 2 + 1])
            }
        }
    }

    func testLxxSetsTheCurrentTickAndCompletedVoiceCannotBeReactivated() throws {
        let module = song(envelope: envelope([(0, 16), (4, 64), (12, 32)]), commands: [1: cell(effect: 0x15, parameter: 8)])
        let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
        XCTAssertEqual(states[6].state.volumeTick, 8)
        XCTAssertEqual(states[6].state.volumeValue, 0.75)
        XCTAssertEqual(states[7].state.volumeTick, 9)
        let mixer = CSoftwareMixer(config: .init(sampleRate: 48_000, channelCount: 1))
        XCTAssertFalse(mixer.setEnvelopeSemanticState(states[0].state, forVoiceAt: 0))
        let voice = mixer.addVoice(sample: .init(monoPCM: [1, 1]))
        XCTAssertTrue(mixer.setEnvelopeSemanticState(states[0].state, forVoiceAt: voice))
        _ = mixer.render(frames: 3)
        let before = mixer.voiceDiagnostic(forVoiceAt: voice)
        XCTAssertFalse(mixer.setEnvelopeSemanticState(states[5].state, forVoiceAt: voice))
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice), before)
        XCTAssertEqual(mixer.render(frames: 3).interleavedPCM, [0, 0, 0])
    }

    func testKxxZeroAndLaterTickUseTheSameNoEnvelopeReleaseContract() throws {
        for tick: UInt8 in [0, 2] {
            let module = song(envelope: envelope([], fadeout: 1024),
                commands: [0: cell(note: 49, effect: 0x14, parameter: tick)])
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 48_000, channelCount: 1), rows: 16)
            let renderer = PlaybackSongOfflineRenderer()
            let result = renderer.render(request)
            let releaseFrame = Int(tick) * 960
            XCTAssertEqual(result.diagnostics.keyOffEvents.first?.scheduledFrame, releaseFrame)
            let target = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.updates.first { $0.scheduledFrame == releaseFrame })
            XCTAssertEqual(target.state.fadeoutAccumulator, 31_744)
            XCTAssertFalse(target.state.keyOn)
            XCTAssertTrue(result.block.interleavedPCM[(releaseFrame + 32)...].allSatisfy { $0 == 0 })
            if tick == 0 { XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 }) }
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
        }
    }

    func testPartialResetBetweenTicksImportsExactStateWithoutAdvancingFadeout() throws {
        let module = song(envelope: envelope([(0, 16), (4, 64), (12, 32)], fadeout: 1024), commands: [1: cell(note: 97)])
        var plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        plan.playbackStateEvents = [.init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 6001,
            change: .reset(.init(volumeEnvelope: true, fadeout: true)))]
        let updates = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
        let reset = try XCTUnwrap(updates.first { $0.scheduledFrame == 6001 })
        XCTAssertEqual(reset.state.volumeTick, 0)
        XCTAssertEqual(reset.state.volumeValue, 0.25)
        XCTAssertEqual(reset.state.fadeoutAccumulator, 32_768)
        XCTAssertFalse(reset.state.keyOn)
        XCTAssertEqual(updates.first { $0.scheduledFrame == 6720 }?.state.fadeoutAccumulator, 31_744)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 48_000, channelCount: 1), rows: 16)
        let pcm = renderer.render(request).block.interleavedPCM
        XCTAssertEqual(pcm[6001], 0.25)
        XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, pcm)
    }

    private func direct(_ plan: PlaybackSongSyntheticPlan, rate: Double) -> (CSoftwareMixer, Int) {
        let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
        let voices = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)
        let voice = voices[0]!
        PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: mixer)
        return (mixer, voice)
    }

    private func envelope(_ points: [(Int, Int)], sustain: Int? = nil, loop: (Int, Int)? = nil, fadeout: Int = 0) -> PlaybackVolumeEnvelope {
        .init(enabled: !points.isEmpty, points: points.map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: sustain, loopStartPointIndex: loop?.0, loopEndPointIndex: loop?.1,
            typeFlags: (points.isEmpty ? 0 : 1) | (sustain == nil ? 0 : 2) | (loop == nil ? 0 : 4), fadeout: fadeout)
    }

    private func cell(note: UInt8 = 0, effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: note == 49 ? 1 : 0, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func song(envelope: PlaybackVolumeEnvelope, pan: PlaybackPanningEnvelope = .disabled,
                      commands: [Int: PlaybackCell] = [:], bpm: Int = 125) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1, count: 256),
            volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 100,
            loopStart: 0, loopLength: 256, loopType: 1)
        return PlaybackSong(title: "Envelope semantics", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<16).map { row in
                .init(index: row, cells: [commands[row] ?? (row == 0 ? cell(note: 49) : cell())])
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: envelope, panningEnvelope: pan)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: bpm), usesLinearFrequencyTable: true)
    }
}
