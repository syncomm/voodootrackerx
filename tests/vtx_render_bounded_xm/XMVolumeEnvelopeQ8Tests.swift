import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMVolumeEnvelopeQ8Tests: XCTestCase {
    func testIndependentSignedSlopeAndEndpointVectors() {
        // Independently authored controls observed with pinned ft2-clone. Each
        // integer is an accumulator observation, not a rounded Float oracle.
        let vectors: [(Int, Int, Int, [Int])] = [
            (64, 32, 3, [16384, 13654, 10924, 8192]),
            (32, 64, 3, [8192, 10922, 13652, 16384]),
            (0, 64, 3, [0, 5461, 10922, 16384]),
            (64, 0, 3, [16384, 10923, 5462, 0]),
            (16, 64, 4, [4096, 7168, 10240, 13312, 16384]),
            (0, 64, 1, [0, 16384]), (64, 0, 1, [16384, 0]),
            (47, 47, 3, [12032, 12032, 12032, 12032]),
            (0, 0, 2, [0, 0, 0])
        ]
        for (start, end, span, expected) in vectors {
            let curve = envelope([(0, start), (span, end)])
            for (tick, q8) in expected.enumerated() {
                XCTAssertEqual(PlaybackVolumeEnvelopeQ8.value(at: tick, from: curve.points[0], to: curve.points[1]), q8)
                XCTAssertEqual(curve.value(at: tick), Float(q8) / 16384)
            }
            XCTAssertEqual(curve.value(at: span + 100), Float(end) / 64)
        }
        for (start, end) in [(32, 33), (33, 32)] {
            let curve = envelope([(0, start), (512, end)])
            XCTAssertEqual(PlaybackVolumeEnvelopeQ8.slope(from: curve.points[0], to: curve.points[1]), 0)
            XCTAssertEqual(curve.value(at: 511), Float(start) / 64)
            XCTAssertEqual(curve.value(at: 512), Float(end) / 64)
        }
        let long = envelope([(0, 1), (257, 64)])
        XCTAssertEqual(long.value(at: 256), Float(16128) / 16384)
        XCTAssertEqual(long.value(at: 257), 1)
        let wide = envelope([(40_000, 64), (65_535, 0)])
        XCTAssertEqual(wide.points.map(\.tick), [40_000, 65_535]) // No loader/writer normalization.
        XCTAssertEqual(wide.value(at: 65_535), 0)
        XCTAssertEqual(envelope([(0, 64), (Int.max, 0)]).value(at: Int.max - 1), 1)
    }

    func testDirectSemanticAndFinalStereoTargetsUseTheSameExactFactor() throws {
        let curve = envelope([(0, 64), (3, 32)])
        for rate in [44_100.0, 48_000] {
            for pan: UInt8 in [0, 64, 128, 192, 255] {
                let plan = adapt(song(curve, pan: pan), rate)
                let semantic = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                let targets = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: .ft2)
                for (tick, q8) in [16384, 13654, 10924, 8192].enumerated() {
                    let factor = Float(q8) / 16384
                    XCTAssertEqual(semantic[tick].state.volumeValue, factor)
                    XCTAssertEqual(curve.value(at: tick), factor)
                    XCTAssertEqual(targets[tick].amplitude, factor)
                    XCTAssertEqual(targets[tick].scheduledFrame, tick * Int(rate / 50))
                    var output = MixerAudibleOutputState()
                    output.publish(targets[tick], config: config)
                    XCTAssertEqual(output.target, [factor, factor * config.panLaw.leftGain(for: targets[tick].pan),
                                                   factor * config.panLaw.rightGain(for: targets[tick].pan)])
                }
            }
        }
    }

    func testCarriedOldSegmentKeepsItsQuantizedSlopeUntilTheNewPendingPoint() throws {
        let old = envelope([(0, 64), (7, 17), (20, 61)])
        for nextPoint in [3, 13] {
            let next = envelope([(0, 13), (nextPoint, 61), (20, 27), (25, 48)])
            let module = song(old, commands: [1: cell(instrument: 2), 2: cell(note: 49)], second: next)
            for rate in [44_100.0, 48_000] {
                let plan = adapt(module, rate)
                let history = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1])
                XCTAssertEqual(history[0].state.volumeTick, 6)
                XCTAssertEqual(history[0].state.volumeValue, Float(6076) / 16384)
                XCTAssertEqual(history[1].state.volumeValue, Float(4358) / 16384)
                XCTAssertEqual(history[2].state.volumeValue, Float(2640) / 16384)
                XCTAssertEqual(history[3].state.volumeValue, Float(922) / 16384)
                XCTAssertEqual(history[4].state.volumeValue, 0) // Independently observed emitted clamp.
                XCTAssertEqual(history[7].state.volumeValue, nextPoint == 13 ? Float(61) / 64 : 0)
                XCTAssertEqual(plan.pattern.events.count, 2)
            }
        }
    }

    func testSustainReleaseLoopAndFadeoutKeepTheirExistingClocks() throws {
        for rate in [44_100.0, 48_000] {
            let curve = envelope([(0, 19), (3, 53), (10, 17)], sustain: 1, fadeout: 1234)
            for release in [cell(note: 97), cell(effect: 20, parameter: 2)] {
                let plan = adapt(song(curve, commands: [2: release]), rate)
                let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                let tick = release.note == 97 ? 12 : 14
                XCTAssertEqual(states[tick].state.volumeTick, 3)
                XCTAssertEqual(states[tick].state.volumeValue, Float(13568) / 16384)
                XCTAssertEqual(states[tick].state.fadeoutAccumulator, 31534)
                XCTAssertEqual(states[tick + 1].state.volumeTick, 4)
                XCTAssertEqual(states[tick + 1].state.volumeValue, Float(12252) / 16384)
                XCTAssertEqual(states[tick + 1].state.fadeoutAccumulator, 30300)
            }
            let loop = envelope([(0, 19), (3, 53), (10, 17), (15, 61)], loop: (1, 2))
            let states = try XCTUnwrap(adapt(song(loop), rate).xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(states[9].state.volumeTick, 9)
            XCTAssertEqual(states[9].state.volumeValue, Float(5672) / 16384)
            XCTAssertEqual(states[10].state.volumeTick, 3)
            XCTAssertEqual(states[10].state.volumeValue, Float(13568) / 16384)
        }
    }

    func testLxxBoundaryAndColdBeforeFirstRemainSeparateKnownDifferences() throws {
        let curve = envelope([(0, 19), (3, 53), (10, 17), (15, 61)], loop: (1, 2))
        for rate in [44_100.0, 48_000] {
            for requested in [6, 10, 12] {
                let states = try XCTUnwrap(adapt(song(curve, commands: [1: cell(effect: 21, parameter: UInt8(requested))]), rate)
                    .xmEnvelopeTimeline?.updatesByEvent[0])
                // Deliberately retain volume Lxx's requested tick and next-tick wrap.
                // Reference loop-end/past-end positioning requires a separate contract.
                XCTAssertEqual(states[6].state.volumeTick, requested)
                XCTAssertEqual(states[6].state.volumeValue, curve.value(at: requested))
                XCTAssertEqual(states[7].state.volumeTick, requested >= 10 ? 3 : 7)
            }
            let cold = try XCTUnwrap(adapt(song(envelope([(3, 48), (10, 16)])), rate).xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(cold.prefix(3).map(\.state.volumeValue), [0.75, 0.75, 0.75])
        }
    }

    func testNongridPanStillUsesFloatAndPublicFixtureMatchesEveryWindow() throws {
        let points = [(0, 13), (7, 61)]
        let pan = PlaybackPanningEnvelope(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/volume-envelope-q8.xm")
        let fixture = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let states = try XCTUnwrap(adapt(song(envelope(points), panEnvelope: pan), rate).xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(states[1].state.panValue, Float(13) / 64 + (Float(48) / 64) * (Float(1) / 7))
            XCTAssertNotEqual(states[1].state.volumeValue, states[1].state.panValue)
            let config = MixerRenderConfig(sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: fixture, config: config, rows: 12)
            let renderer = PlaybackSongOfflineRenderer(), whole = renderer.render(request)
            XCTAssertEqual(whole.plan, RuntimeCMixerAdapterEventPlan.make(song: fixture, sampleRate: rate).plan)
            for update in whole.plan.xmEnvelopeTimeline?.updates ?? [] {
                XCTAssertEqual(update.state.volumeValue, fixture.instrumentsByIndex[1]!.volumeEnvelope.value(at: update.state.volumeTick))
            }
            for size in [1, 2, 3, 5] {
                let window = renderer.renderWindowed(request, windowRows: size)
                XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM, window.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }

    func testSilentExactRouteAndCompletedVoiceKeepNumericStateWithoutResurrection() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/empty-slot-playback-state.xm")
        let original = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        let curve = envelope([(0, 64), (7, 17), (20, 61)])
        let instruments = original.instrumentsByIndex.mapValues { instrument in
            PlaybackInstrument(index: instrument.index, samples: instrument.samples, volumeEnvelope: curve,
                panningEnvelope: instrument.panningEnvelope, noteSampleMap: instrument.noteSampleMap)
        }
        let silent = PlaybackSong(title: original.title, orders: original.orders, patternsByIndex: original.patternsByIndex,
            instrumentsByIndex: instruments, restartOrderIndex: original.restartOrderIndex, endBehavior: original.endBehavior,
            initialTiming: original.initialTiming, usesLinearFrequencyTable: original.usesLinearFrequencyTable,
            xmSampleSlotProvenanceByInstrument: original.xmSampleSlotProvenanceByInstrument)
        for rate in [44_100.0, 48_000] {
            let plan = adapt(silent, rate)
            let state = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelUpdates.first {
                $0.channelIndex == 0 && $0.source.rowIndex == 2 && $0.tick == 1
            })
            XCTAssertNil(state.sourceEventIndex)
            XCTAssertEqual(state.sampleIndex, 2)
            XCTAssertEqual(state.state.volumeValue, Float(14666) / 16384)
            XCTAssertFalse(plan.xmEnvelopeTimeline!.updates.contains { $0.channelIndex == 0 && $0.source.rowIndex == 2 })
            let completed = adapt(song(curve, commands: [1: cell(instrument: 1)], completed: true), rate)
            XCTAssertEqual(completed.pattern.events.count, 1)
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let event = completed.pattern.events[0]
            let voice = mixer.addVoice(sample: event.sample, gain: event.gain, pan: event.pan, playbackStep: event.playbackStep)
            _ = mixer.render(frames: 6 * Int(rate / 50))
            XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice)).active)
            let reset = try XCTUnwrap(completed.xmEnvelopeTimeline?.updatesByEvent[0]?.first { $0.source.rowIndex == 1 })
            XCTAssertEqual(reset.state.volumeTick, 0)
            XCTAssertEqual(reset.state.volumeValue, 1)
            XCTAssertFalse(mixer.setEnvelopeSemanticState(reset.state, forVoiceAt: voice))
        }
    }

    private func envelope(_ points: [(Int, Int)], sustain: Int? = nil, loop: (Int, Int)? = nil, fadeout: Int = 0) -> PlaybackVolumeEnvelope {
        .init(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: sustain,
            loopStartPointIndex: loop?.0, loopEndPointIndex: loop?.1,
            typeFlags: 1 | (sustain == nil ? 0 : 2) | (loop == nil ? 0 : 4), fadeout: fadeout)
    }
    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }
    private func adapt(_ song: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
    }
    private func song(_ curve: PlaybackVolumeEnvelope, pan: UInt8 = 128, commands: [Int: PlaybackCell] = [:],
                      second: PlaybackVolumeEnvelope? = nil, panEnvelope: PlaybackPanningEnvelope = .disabled,
                      completed: Bool = false) -> PlaybackSong {
        func instrument(_ index: Int, _ envelope: PlaybackVolumeEnvelope) -> PlaybackInstrument {
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: Array(repeating: 0.25, count: completed ? 4 : 256),
                volume: 1, panning: pan, relativeNote: 0, finetune: 0, baseSampleRate: 100,
                loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
            return .init(index: index, samples: [sample], volumeEnvelope: envelope, panningEnvelope: panEnvelope,
                         noteSampleMap: Array(repeating: 0, count: 96))
        }
        return .init(title: "Public Q8 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in
                .init(index: row, cells: [commands[row] ?? (row == 0 ? cell(note: 49, instrument: 1) : cell())])
            })], instrumentsByIndex: [1: instrument(1, curve), 2: instrument(2, second ?? curve)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
