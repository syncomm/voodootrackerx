import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMWarmVolumeEnvelopeTests: XCTestCase {
    func testWarmResetReplacesEitherOldSignedSlopeWithTheNewFirstValue() throws {
        let next = curve([(3, 48), (10, 16)])
        for (points, oldQ8, oldSlope) in [([(0, 20), (12, 56), (24, 8)], 8960, 768),
                                          ([(0, 64), (12, 16), (24, 56)], 11264, -1024)] {
            let old = curve(points)
            var segment = PlaybackXMEnvelopeTimeline.Segment()
            segment.sample(5, envelope: old, keyOn: true, volumeQ8: true)
            XCTAssertEqual(segment.value * 16384, Float(oldQ8))
            XCTAssertEqual(segment.slope * 16384, Float(oldSlope))
            XCTAssertEqual(segment.pendingPoint, 1)
            segment.sample(0, envelope: next, keyOn: true, volumeQ8: true)
            for (tick, q8) in [12288, 12288, 12288, 12288, 11118].enumerated() {
                if tick > 0 {
                    let position = segment.nextPosition(tick - 1, envelope: next, keyOn: true, releasing: false)
                    XCTAssertEqual(position, tick)
                    segment.advance(from: tick - 1, to: position, envelope: next, keyOn: true, volumeQ8: true)
                }
                XCTAssertEqual(segment.value * 16384, Float(q8))
                XCTAssertEqual(segment.slope * 16384, tick < 3 ? 0 : -1170)
                XCTAssertEqual(segment.pendingPoint, 1)
                XCTAssertTrue(segment.followsCurve)
            }
            for linear in [true, false] { for rate in [44_100.0, 48_000] {
                let input = song(old, second: next, linear: linear, commands: [1: cell(note: 49, instrument: 2)])
                let plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
                let oldState = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0]?.last)
                XCTAssertEqual(oldState.state.volumeValue * 16384, Float(oldQ8))
                let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1])
                for (tick, q8) in [12288, 12288, 12288, 12288, 11118].enumerated() {
                    XCTAssertEqual(states[tick].scheduledFrame, (6 + tick) * Int(rate / 50))
                    XCTAssertEqual(states[tick].state.volumeTick, tick)
                    XCTAssertEqual(states[tick].state.volumeValue * 16384, Float(q8))
                    XCTAssertTrue(states[tick].state.keyOn)
                    XCTAssertEqual(states[tick].state.fadeoutAccumulator, 32768)
                    let target = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[1]?[tick])
                    XCTAssertEqual(target.amplitude, Float(q8) / 16384)
                    for profile in MixerMixProfile.allCases {
                        let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                        var output = MixerAudibleOutputState()
                        output.publish(target, config: config)
                        XCTAssertEqual(output.target, [target.amplitude, target.amplitude * config.panLaw.leftGain(for: target.pan),
                            target.amplitude * config.panLaw.rightGain(for: target.pan)])
                    }
                }
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1, 2])
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 0])
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            } }
        }
    }

    func testFlatWarmGreenControlAndNoteOnlyCarryKeepExactFactors() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for first in [37, 48] {
                let next = curve([(3, first), (10, first == 37 ? 37 : 16)])
                let input = song(curve([(0, 20), (12, 56), (24, 8)]), second: next, linear: linear,
                    commands: [1: cell(note: 49, instrument: 2), 2: cell(note: 49)])
                let plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
                let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1])
                XCTAssertEqual(reset.prefix(4).map { $0.state.volumeValue * 16384 }, Array(repeating: Float(first * 256), count: 4))
                let carried = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[2])
                XCTAssertEqual(carried.prefix(3).map(\.state.volumeTick), [6, 7, 8])
                XCTAssertEqual(carried.prefix(3).map { $0.state.volumeValue * 16384 },
                    first == 37 ? [9472, 9472, 9472] : [8778, 7608, 6438])
                XCTAssertEqual(plan.pattern.events.count, 3) // Note-only starts PCM but carries the envelope.
            }
        } }
    }

    func testInstrumentOnlyWarmResetKeepsExactTargetsAndWholeWindowStreamPCM() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for profile in MixerMixProfile.allCases {
            let input = song(curve([(3, 48), (10, 16)]), linear: linear, commands: [1: cell(instrument: 2)])
            let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile), tick = Int(rate / 50)
            let renderer = PlaybackSongOfflineRenderer()
            let request = PlaybackSongOfflineRenderRequest(song: input, config: config, rows: 3)
            let whole = renderer.render(request), plan = whole.plan
            XCTAssertEqual(plan, RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate).plan)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0])
            XCTAssertEqual(plan.pattern.events[0].sample.monoPCM, input.instrumentsByIndex[1]?.samples[0].pcm)
            XCTAssertEqual(input.instrumentsByIndex[1]?.noteSampleMap?.count, 96)
            XCTAssertEqual(plan.playbackStateEvents.map(\.activeEventIndex), [0])
            XCTAssertEqual(plan.playbackStateEvents.map(\.scheduledFrame), [6 * tick])
            let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(states.prefix(4).map { $0.state.volumeValue * 16384 }, [0, 0, 0, 12288])
            XCTAssertEqual(states[5].state.volumeValue * 16384, 9948)
            XCTAssertEqual(states[6].state.volumeValue * 16384, 12288)
            let target = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == 6 * tick })
            XCTAssertEqual(target.intent, "nonretriggering_reset")
            XCTAssertTrue(target.rebaseFromCurrent)
            XCTAssertEqual(target.durationFrames, Int(rate * 0.005))
            XCTAssertEqual(target.amplitude, 0.75)
            var output = MixerAudibleOutputState()
            output.publish(target, config: config)
            XCTAssertEqual(output.target, [0.75, 0.75 * config.panLaw.leftGain(for: target.pan),
                                                0.75 * config.panLaw.rightGain(for: target.pan)])
            let ramp = Int(rate * 0.005), start = Float(9948) / 16384
            for k in [0, ramp / 2, ramp, ramp + 1] {
                let amplitude = start + (0.75 - start) * min(1, Float(k) / Float(ramp))
                for (channel, panGain) in [config.panLaw.leftGain(for: target.pan), config.panLaw.rightGain(for: target.pan)].enumerated() {
                    XCTAssertEqual(whole.block.interleavedPCM[(6 * tick + k) * 2 + channel],
                        0.25 * amplitude * panGain * config.outputScale, accuracy: 1e-7)
                }
            }
            for rows in [1, 2] { XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, whole.block.interleavedPCM) }
            var streamed = [Float]()
            _ = renderer.renderStreaming(request, chunkFrameCount: 997) { _, _, block in streamed += block.interleavedPCM }
            XCTAssertEqual(streamed, whole.block.interleavedPCM)
            #if DEBUG
            let n = 6 * tick
            let partition = renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [n - 1, n, n + 1, n + ramp / 2, n + ramp, n + ramp + 1, 9 * tick, 10 * tick])
            XCTAssertEqual(partition.block.interleavedPCM, whole.block.interleavedPCM)
            #endif
        } } }
    }

    private func curve(_ points: [(Int, Int)]) -> PlaybackVolumeEnvelope {
        .init(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: nil,
            loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 0)
    }
    private func cell(note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: 0, effectParam: 0)
    }
    private func song(_ first: PlaybackVolumeEnvelope, second: PlaybackVolumeEnvelope? = nil, linear: Bool,
                      commands: [Int: PlaybackCell]) -> PlaybackSong {
        func instrument(_ index: Int, _ envelope: PlaybackVolumeEnvelope) -> PlaybackInstrument {
            let pcm: [Float] = index == 1 ? Array(repeating: 0.25, count: 256) : [-0.5, -0.5]
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: pcm,
                volume: 1, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: pcm.count, loopType: 1)
            return .init(index: index, samples: [sample], volumeEnvelope: envelope, noteSampleMap: Array(repeating: 0, count: 96))
        }
        return .init(title: "Public warm volume reset control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<3).map { row in
                .init(index: row, cells: [commands[row] ?? (row == 0 ? cell(note: 49, instrument: 1) : cell())])
            })], instrumentsByIndex: [1: instrument(1, first), 2: instrument(2, second ?? .disabled)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
