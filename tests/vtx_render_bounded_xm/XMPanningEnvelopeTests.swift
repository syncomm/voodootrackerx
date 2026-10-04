import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMPanningEnvelopeTests: XCTestCase {
    func testNeutralAndDisabledEnvelopePreserveStaticAudioAndGenericRamps() throws {
        for rate in [44_100.0, 48_000] {
            for header: UInt8 in [0, 64, 128, 224, 255] {
                let commands = [1: cell(effect: 8, param: 224), 2: cell(volume: 0x30), 3: cell(instrument: 1)]
                let baseline = render(song(header: header, commands: commands, volumeEnvelope: false), rate)
                for pan in [envelope([(0, 32), (4, 32)], sustain: 1, loop: (0, 1)),
                    PlaybackPanningEnvelope(enabled: false, points: [.init(tick: 0, value: 16)],
                        sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 0)] {
                    let result = render(song(pan, header: header, commands: commands, volumeEnvelope: false), rate)
                    XCTAssertEqual(result.block.interleavedPCM, baseline.block.interleavedPCM)
                    XCTAssertEqual(result.plan.xmAudibleTimeline?.updates, baseline.plan.xmAudibleTimeline?.updates)
                }
            }
        }
    }

    func testObservedIntegerCombinationRuleAndEndpointClampAtBothRates() throws {
        // Project-authored constant curves, observed with the pinned FT2 loader/replayer.
        let cases: [(UInt8, Int, Int)] = [(0, 16, 0), (0, 48, 0), (64, 16, 32), (64, 48, 96),
            (128, 16, 64), (128, 32, 128), (128, 48, 192), (128, 0, 0), (128, 63, 252),
            (128, 64, 252), (224, 16, 208), (224, 48, 240), (255, 0, 254), (255, 64, 255),
            (1, 16, 0), (127, 33, 130), (129, 31, 125)]
        for rate in [44_100.0, 48_000] {
            for (header, value, expectedByte) in cases {
                let result = render(song(envelope([(0, value), (100, value)]), header: header), rate)
                let update = try XCTUnwrap(result.plan.xmAudibleTimeline?.updates.first)
                XCTAssertEqual(update.pan, PlaybackSamplePanningPolicy.plannedPan(expectedByte), accuracy: 1e-7)
                XCTAssertEqual(update.amplitude, 1) // G01 remains one channel/header ownership.
                XCTAssertEqual(update.durationFrames, 0)
                let config = MixerRenderConfig(sampleRate: rate)
                XCTAssertEqual(result.block.interleavedPCM[0], 0.25 * config.panLaw.leftGain(for: update.pan), accuracy: 1e-7)
                XCTAssertEqual(result.block.interleavedPCM[1], 0.25 * config.panLaw.rightGain(for: update.pan), accuracy: 1e-7)
                XCTAssertEqual(result.plan.xmChannelRows.first?.controls.panningValue, Double(header))
            }
        }
    }

    func testMotionSustainLoopReleaseAndResetConsumeExistingClock() throws {
        for rate in [44_100.0, 48_000] {
            let motion = envelope([(0, 32), (4, 16), (8, 48), (12, 32)])
            let plain = render(song(motion), rate).plan
            let targets = try XCTUnwrap(plain.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(targets[4].pan, -0.5)
            XCTAssertEqual(targets[8].pan, 64.0 / 127)
            XCTAssertEqual(targets[12].pan, 0)
            XCTAssertEqual(targets.map(\.scheduledFrame), plain.xmEnvelopeTimeline?.updates.map(\.scheduledFrame))
            let held = render(song(envelope([(0, 32), (4, 16), (8, 48), (12, 32)], sustain: 1),
                commands: [2: cell(note: 97)]), rate).plan
            let states = try XCTUnwrap(held.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(states[4...12].map(\.state.panTick), Array(repeating: 4, count: 9))
            XCTAssertEqual(states[4...12].map(\.state.panValue), Array(repeating: 0.25, count: 9))
            XCTAssertFalse(states[12].state.keyOn)
            // Retain VTX's logical release rule; FT2's raw pan-sustain release quirk is separate.
            XCTAssertEqual(states[13].state.panTick, 5)
            XCTAssertEqual(states[13].state.panValue, 0.375)
            XCTAssertEqual(held.xmAudibleTimeline?.updatesByEvent[0]?[13].pan, -0.25)
            let loop = render(song(envelope([(0, 32), (2, 16), (6, 48), (10, 32)], loop: (1, 2)),
                commands: [2: cell(note: 97)]), rate).plan
            XCTAssertEqual(loop.xmEnvelopeTimeline?.updatesByEvent[0]?.prefix(11).map(\.state.panTick),
                [0, 1, 2, 3, 4, 5, 2, 3, 4, 5, 2])
            XCTAssertEqual(loop.xmAudibleTimeline?.updatesByEvent[0]?[6].pan, -0.5)
            XCTAssertEqual(loop.xmAudibleTimeline?.updatesByEvent[0]?[14].pan, -0.5)
            let carry = render(song(motion, commands: [1: cell(note: 49), 2: cell(instrument: 1), 3: cell(note: 49)]), rate).plan
            XCTAssertEqual(carry.pattern.events.count, 3)
            XCTAssertEqual(carry.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.panTick, 6)
            let reset = try XCTUnwrap(carry.xmAudibleTimeline?.updatesByEvent[1]?.first { $0.source.rowIndex == 2 })
            XCTAssertEqual(reset.pan, 0)
            XCTAssertEqual(reset.durationFrames, Int(rate * 0.005))
            XCTAssertTrue(reset.rebaseFromCurrent)
            XCTAssertEqual(carry.xmEnvelopeTimeline?.updatesByEvent[2]?.first?.state.panTick, 6)
        }
    }

    func testLxxLeavesPanClockAndAudiblePanTrajectoryUnpositioned() throws {
        for rate in [44_100.0, 48_000] {
            for volumeSustain in [false, true] {
                let pan = envelope([(0, 32), (4, 16), (20, 48)])
                let baseline = render(song(pan, volumeSustain: volumeSustain), rate).plan
                let positioned = render(song(pan, commands: [1: cell(effect: 0x15, param: 8)], volumeSustain: volumeSustain), rate).plan
                XCTAssertEqual(positioned.xmEnvelopeTimeline?.updates.map(\.state.panTick), baseline.xmEnvelopeTimeline?.updates.map(\.state.panTick))
                XCTAssertEqual(positioned.xmEnvelopeTimeline?.updates.map(\.state.panValue), baseline.xmEnvelopeTimeline?.updates.map(\.state.panValue))
                XCTAssertEqual(positioned.xmAudibleTimeline?.updates.map(\.pan), baseline.xmAudibleTimeline?.updates.map(\.pan))
                XCTAssertEqual(positioned.xmEnvelopeTimeline?.updatesByEvent[0]?[6].state.volumeTick, 8)
            }
        }
    }

    func test8xxAndVolumeColumnPanKeepTheirStoredStateAndConversionBaseline() throws {
        for rate in [44_100.0, 48_000] {
            let result = render(song(envelope([(0, 32), (2, 16), (6, 48), (10, 32)], loop: (1, 2)),
                commands: [1: cell(effect: 8, param: 224), 2: cell(volume: 0xC4)]), rate)
            let targets = try XCTUnwrap(result.plan.xmAudibleTimeline?.updatesByEvent[0])
            let rows = result.plan.xmChannelRows.map(\.controls)
            XCTAssertEqual(rows[1].panningValue, 224)
            XCTAssertEqual(rows[2].panningValue, 68) // Retain G11's current 17*nibble mapping.
            XCTAssertEqual(targets[8].pan, rows[1].pan) // Envelope is neutral at tick 4.
            let delta = PlaybackSamplePanningPolicy.plannedPan(232) - PlaybackSamplePanningPolicy.plannedPan(224)
            XCTAssertEqual(targets[9].pan, rows[1].pan + delta)
            XCTAssertEqual(targets[12].pan, rows[2].pan) // Neutral loop position again.
        }
    }

    func testPanOnlyActivationPreservesEarlierAudioAndOneOutputRamp() throws {
        let pan = envelope([(0, 32), (2, 32), (4, 16), (8, 48)])
        for rate in [44_100.0, 48_000] {
            let result = render(song(pan, volumeEnvelope: false), rate)
            let baseline = render(song(volumeEnvelope: false), rate)
            let first = try XCTUnwrap(result.plan.xmAudibleTimeline?.updates.first)
            XCTAssertEqual(first.scheduledFrame, Int(rate / 50) * 3)
            XCTAssertNotNil(first.activation)
            XCTAssertEqual(Array(result.block.interleavedPCM[..<(first.scheduledFrame * 2)]),
                Array(baseline.block.interleavedPCM[..<(first.scheduledFrame * 2)]))
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate))
            let voices = SyntheticPatternScheduler(config: result.plan.timingConfig).schedule(result.plan.pattern, on: mixer)
            PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(result.plan, voiceIndexByEventIndex: [0: voices[0]!], on: mixer)
            _ = mixer.render(frames: first.scheduledFrame + 1)
            let diagnostic = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voices[0]!))
            XCTAssertNotNil(diagnostic.audibleOutputState)
            XCTAssertNil(diagnostic.gainRamp)
            XCTAssertNil(diagnostic.panRamp)
        }
    }

    func testSilentRoutesAndCompletedSourceKeepClockWithoutCreatingOutput() throws {
        for rate in [44_100.0, 48_000] {
            let module = song(envelope([(0, 32), (24, 8)]), commands: [1: cell(note: 50), 3: cell(note: 49)], empty: true)
            let result = render(module, rate), plan = result.plan
            let rowFrames = Int(rate / 50) * 6
            let silent = try XCTUnwrap(plan.xmEnvelopeTimeline).channelUpdates.filter {
                (rowFrames..<(3 * rowFrames)).contains($0.scheduledFrame)
            }
            XCTAssertTrue(silent.allSatisfy { $0.sourceEventIndex == nil })
            XCTAssertEqual(silent.map(\.state.panTick), Array(6..<18))
            XCTAssertEqual(plan.pattern.events.count, 2)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 0])
            XCTAssertFalse(plan.xmAudibleTimeline!.updates.contains { (rowFrames..<(3 * rowFrames)).contains($0.scheduledFrame) })
            XCTAssertTrue(result.block.interleavedPCM[(rowFrames * 2)..<(3 * rowFrames * 2)].allSatisfy { $0 == 0 })
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.panTick, 18)
            XCTAssertEqual(plan.xmAudibleTimeline?.updatesByEvent[1]?.first?.pan, -0.5625)
            let ended = render(song(envelope([(0, 32), (24, 8)]), oneShot: true), rate)
            XCTAssertGreaterThan(ended.plan.xmEnvelopeTimeline!.updates.last!.state.panTick, 0)
            XCTAssertTrue(ended.block.interleavedPCM[(Int(rate / 50) * 4)...].allSatisfy { $0 == 0 })
        }
    }

    func testWholeWindowAndRuntimePlanParityForEveryTransition() throws {
        for rate in [44_100.0, 48_000] {
            for profile in MixerMixProfile.allCases {
                let module = song(envelope([(0, 32), (2, 16), (6, 48), (10, 32)], loop: (1, 2)),
                    commands: [1: cell(effect: 8, param: 224), 2: cell(instrument: 1),
                        3: cell(effect: 15, param: 250), 4: cell(note: 97)])
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 8)
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
                for window in [1, 2, 3] {
                    XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, full.block.interleavedPCM)
                }
                let mixer = CSoftwareMixer(config: config)
                let voices = SyntheticPatternScheduler(config: full.plan.timingConfig).schedule(full.plan.pattern, on: mixer)
                PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(full.plan, voiceIndexByEventIndex: [0: voices[0]!], on: mixer)
                for update in full.plan.xmAudibleTimeline!.updates {
                    let boundary = update.scheduledFrame + max(1, update.durationFrames / 2)
                    _ = mixer.render(frames: boundary - Int(mixer.currentFrame))
                    XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voices[0]!)?.audibleOutputState,
                        full.plan.xmAudibleTimeline?.state(eventIndex: 0, before: boundary, config: config))
                }
            }
        }
    }

    private func envelope(_ points: [(Int, Int)], sustain: Int? = nil, loop: (Int, Int)? = nil) -> PlaybackPanningEnvelope {
        .init(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: sustain,
            loopStartPointIndex: loop?.0, loopEndPointIndex: loop?.1, typeFlags: 1 | (sustain == nil ? 0 : 2) | (loop == nil ? 0 : 4))
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ pan: PlaybackPanningEnvelope = .disabled, header: UInt8 = 128, commands: [Int: PlaybackCell] = [:],
                      volumeEnvelope: Bool = true, volumeSustain: Bool = false, empty: Bool = false, oneShot: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: 1, panning: header, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
            loopStart: 0, loopLength: oneShot ? 0 : 256, loopType: oneShot ? 0 : 1)
        var map = Array(repeating: 0, count: 96)
        if empty { map[49] = 1 }
        let volume = PlaybackVolumeEnvelope(enabled: volumeEnvelope, points: [.init(tick: 0, value: 64), .init(tick: 100, value: 64)],
            sustainPointIndex: volumeSustain ? 1 : nil, loopStartPointIndex: nil, loopEndPointIndex: nil,
            typeFlags: volumeEnvelope ? (volumeSustain ? 3 : 1) : 0, fadeout: 0)
        return PlaybackSong(title: "Public G06 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in
                .init(index: row, cells: [commands[row] ?? (row == 0 ? cell(note: 49, instrument: 1) : cell())])
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volume, panningEnvelope: pan, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: empty ? [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]] : [:])
    }

    private func render(_ module: PlaybackSong, _ rate: Double) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate), rows: 8))
    }
}
