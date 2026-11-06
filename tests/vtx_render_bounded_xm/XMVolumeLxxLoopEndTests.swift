import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMVolumeLxxLoopEndTests: XCTestCase {
    private let points = [(0, 19), (3, 53), (10, 17), (15, 61)]

    func testPinnedCommandAndFollowingPositionsFactorsTargetsAndExactRoutes() throws {
        // Public stimuli observed through the pinned native FT2 replayer, not Float interpolation.
        let vectors: [(UInt8, [Int], [Int])] = [
            (2, [2, 3, 4], [10666, 13568, 12252]), (3, [3, 4, 5], [13568, 12252, 10936]),
            (6, [6, 7, 8], [9620, 8304, 6988]), (9, [9, 3, 4], [5672, 13568, 12252]),
            (10, [3, 4, 5], [13568, 12252, 10936]), (12, [12, 13, 14], [8856, 11108, 13360]),
            (15, [15, 16, 17], [15616, 15616, 15616]), (255, [255, 256, 257], [15616, 15616, 15616])
        ]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (request, positions, values) in vectors {
                let plan = adapt(song(linear: linear, commands: [2: cell(effect: 21, parameter: request)]), rate)
                XCTAssertEqual(plan.pattern.events.count, 2)
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1])
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
                for channel in 0..<3 { for tick in 0..<3 {
                    let frame = (12 + tick) * Int(rate / 50)
                    let state = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: channel, atOrBefore: frame))
                    XCTAssertEqual(state.scheduledFrame, frame)
                    XCTAssertEqual(state.state.volumeTick, positions[tick])
                    let factor = Float(values[tick]) / 16384
                    XCTAssertEqual(state.state.volumeValue, factor)
                    XCTAssertEqual(state.state.fadeoutAccumulator, 32768)
                    XCTAssertEqual(state.sampleIndex, UInt8(channel))
                    XCTAssertEqual(state.sourceEventIndex, channel == 2 ? nil : channel)
                    if channel < 2 {
                        let target = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[channel]?.first { $0.scheduledFrame == frame })
                        XCTAssertEqual(target.amplitude, channel == 0 ? factor : 0)
                        XCTAssertEqual(target.durationFrames, Int(rate / 50))
                        var output = MixerAudibleOutputState()
                        let config = MixerRenderConfig(sampleRate: rate, mixProfile: .ft2)
                        output.publish(target, config: config)
                        let gain = target.amplitude * config.panLaw.leftGain(for: target.pan)
                        XCTAssertEqual(output.target, [target.amplitude, gain, gain])
                    }
                } }
            }
        } }
    }

    func testReleaseOrderingOnlyExemptsAReleasedSustainAtTheLoopEnd() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for sustain in [1, 2] { for release in 0..<4 {
                var commands = [2: cell(note: release == 3 ? 97 : 0, effect: 21, parameter: 10)]
                if release == 1 { commands[1] = cell(note: 97) }
                if release == 2 { commands[1] = cell(effect: 20, parameter: 5) }
                let plan = adapt(song(linear: linear, commands: commands, sustain: sustain), rate)
                let releasedEnd = sustain == 2 && release != 0
                let expected = releasedEnd ? [10, 11, 12] : sustain == 1 && release == 0 ? [3, 3, 3] : [3, 4, 5]
                for tick in 0..<3 {
                    let state = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,
                        atOrBefore: (12 + tick) * Int(rate / 50)))
                    XCTAssertEqual(state.state.volumeTick, expected[tick])
                    XCTAssertEqual(state.state.keyOn, release == 0)
                    XCTAssertEqual(state.state.volumeValue, curve(sustain: sustain).value(at: expected[tick]))
                }
            } }
            let held = adapt(song(linear: linear, commands: [2: cell(effect: 21, parameter: 3)], sustain: 1), rate)
            XCTAssertEqual(held.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<15].map(\.state.volumeTick), [3, 3, 3])
            XCTAssertEqual(held.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<15].map(\.state.volumeValue), [53.0 / 64, 53.0 / 64, 53.0 / 64])
        } }
    }

    func testEscapeSurvivesNoteOnlyCarryAndClearsOnResetOrAnotherPosition() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let commands = [2: cell(effect: 21, parameter: 12), 3: cell(note: 49), 4: cell(instrument: 1)]
            let plan = adapt(song(linear: linear, commands: commands), rate)
            XCTAssertEqual(plan.pattern.events.count, 5) // Only the explicit note starts new PCM, including S03's later consumer.
            for channel in 0..<3 {
                let carried = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: channel, atOrBefore: 18 * Int(rate / 50)))
                XCTAssertEqual(carried.state.volumeTick, 18)
                XCTAssertEqual(carried.state.volumeValue, 61.0 / 64)
                let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: channel, atOrBefore: 24 * Int(rate / 50)))
                XCTAssertEqual(reset.state.volumeTick, 0)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.channelState(channelIndex: channel, atOrBefore: 34 * Int(rate / 50))?.state.volumeTick, 3)
            }
            let rearmed = adapt(song(linear: linear, commands: [2: cell(effect: 21, parameter: 255),
                3: cell(effect: 21, parameter: 9)]), rate)
            XCTAssertEqual(rearmed.xmEnvelopeTimeline?.updatesByEvent[0]?[18..<21].map(\.state.volumeTick), [9, 3, 4])
            let last = adapt(song(linear: linear, commands: [2: cell(effect: 21, parameter: 15)], loop: (1, 3)), rate)
            XCTAssertEqual(last.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<15].map(\.state.volumeTick), [3, 4, 5])
        } }
    }

    func testLoopDisabledVolumeDisabledAndBlankCommandsRetainTheirRules() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for request: UInt8 in [10, 12, 255] {
                let commands = [2: cell(effect: 21, parameter: request)]
                let plan = adapt(song(linear: linear, commands: commands, loop: nil), rate)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<15].map(\.state.volumeTick),
                    [Int(request), Int(request) + 1, Int(request) + 2])
                let disabled = song(linear: linear, commands: commands, enabled: false)
                let request = PlaybackSongOfflineRenderRequest(song: disabled, config: .init(sampleRate: rate), rows: 8)
                let full = PlaybackSongOfflineRenderer().render(request)
                let blank = PlaybackSongOfflineRenderer().render(.init(song: song(linear: linear, enabled: false), config: request.config, rows: 8))
                XCTAssertEqual(full.block.interleavedPCM, blank.block.interleavedPCM)
                XCTAssertTrue(full.plan.diagnostics.envelopePositionEffects.allSatisfy { !$0.applied && $0.status == .noEnvelope })
                XCTAssertEqual(full.plan.xmAudibleTimeline?.updatesByEvent[0]?.first?.amplitude, 1)
                let empty = full.plan.xmEnvelopeTimeline?.channelState(channelIndex: 2, atOrBefore: 12 * Int(rate / 50))
                XCTAssertEqual(empty?.state.volumeTick, 0)
                XCTAssertEqual(empty?.state.volumeValue, 1)
                XCTAssertNil(empty?.sourceEventIndex)
            }
            let blank = adapt(song(linear: linear), rate)
            XCTAssertEqual(blank.xmEnvelopeTimeline?.updatesByEvent[0]?[9..<13].map(\.state.volumeTick), [9, 3, 4, 5])
        } }
    }

    func testPublicFixtureWholeWindowsStreamsAndPartitionsAreExact() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/volume-lxx-loop-end.xm")
        let original = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for profile in [MixerMixProfile.vtx, .ft2] {
            let input = PlaybackSong(title: original.title, orders: original.orders, patternsByIndex: original.patternsByIndex,
                instrumentsByIndex: original.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: original.initialTiming, usesLinearFrequencyTable: linear,
                xmSampleSlotProvenanceByInstrument: original.xmSampleSlotProvenanceByInstrument)
            let renderer = PlaybackSongOfflineRenderer()
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate, mixProfile: profile), rows: 16)
            let whole = renderer.render(request)
            XCTAssertEqual(whole.plan, RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate).plan)
            for size in [1, 3, 5] { XCTAssertEqual(whole.block.interleavedPCM, renderer.renderWindowed(request, windowRows: size).block.interleavedPCM) }
            var streamed = [Float]()
            let stream = renderer.renderStreaming(request, chunkFrameCount: 997) { _, _, block in streamed += block.interleavedPCM }
            XCTAssertEqual(stream.renderedFrameCount, whole.block.frameCount)
            XCTAssertEqual(streamed, whole.block.interleavedPCM)
            streamed.removeAll(keepingCapacity: true)
            let windowStream = renderer.renderWindowedStreaming(request, windowRows: 3) { _, _, _, block in streamed += block.interleavedPCM }
            XCTAssertEqual(windowStream.renderedFrameCount, whole.block.frameCount)
            XCTAssertEqual(streamed, whole.block.interleavedPCM)
            #if DEBUG
            let tick = Int(rate / 50)
            let partitioned = renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [12 * tick - 1, 12 * tick, 12 * tick + 1, 18 * tick + 1, 42 * tick + 1, 72 * tick])
            XCTAssertEqual(partitioned.block.interleavedPCM, whole.block.interleavedPCM)
            #endif
        } } }
    }

    #if DEBUG
    func testActualCSourceCursorsStepsAndCompletedLifetimesMatchBlankControls() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for completed in [false, true] {
            for position: UInt8 in [10, 12, 255] {
                let config = MixerRenderConfig(sampleRate: rate)
                let actual = PlaybackSongOfflineRenderSession(request: .init(song: song(linear: linear,
                    commands: [2: cell(effect: 21, parameter: position)], completed: completed), config: config, rows: 8))
                let blank = PlaybackSongOfflineRenderSession(request: .init(song: song(linear: linear, completed: completed), config: config, rows: 8))
                var cursor = 0
                for frame in [12 * Int(rate / 50) - 1, 12 * Int(rate / 50), 12 * Int(rate / 50) + 1, 14 * Int(rate / 50) + 1] {
                    _ = actual.render(frames: frame - cursor); _ = blank.render(frames: frame - cursor); cursor = frame
                    for event in 0..<2 {
                        let a = try XCTUnwrap(actual.sourceVoiceForTesting(event)), b = try XCTUnwrap(blank.sourceVoiceForTesting(event))
                        XCTAssertEqual(a.active, !completed)
                        XCTAssertEqual(a.active, b.active)
                        XCTAssertEqual(a.loaded, b.loaded)
                        XCTAssertEqual(a.sampleStep, b.sampleStep)
                        XCTAssertEqual(a.samplePosition.rounded(.down), b.samplePosition.rounded(.down))
                        XCTAssertEqual(a.samplePosition - a.samplePosition.rounded(.down), b.samplePosition - b.samplePosition.rounded(.down))
                        XCTAssertEqual(a.sourceOnsetElapsedFrames, b.sourceOnsetElapsedFrames)
                        XCTAssertEqual(actual.scheduledVoiceIndices[event], blank.scheduledVoiceIndices[event])
                    }
                    XCTAssertEqual(actual.scheduledVoiceIndices.count, 2)
                }
            }
        } } }
    }
    #endif

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func curve(sustain: Int? = nil, loop: (Int, Int)? = (1, 2), enabled: Bool = true) -> PlaybackVolumeEnvelope {
        .init(enabled: enabled, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: sustain,
            loopStartPointIndex: loop?.0, loopEndPointIndex: loop?.1,
            typeFlags: (enabled ? 1 : 0) | (sustain == nil ? 0 : 2) | (loop == nil ? 0 : 4), fadeout: 0)
    }

    private func adapt(_ song: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
    }

    private func song(linear: Bool, commands: [Int: PlaybackCell] = [:], sustain: Int? = nil,
                      loop: (Int, Int)? = (1, 2), enabled: Bool = true, completed: Bool = false) -> PlaybackSong {
        let samples = (0..<2).map { slot in PlaybackSample(instrumentIndex: 1, sampleIndex: slot,
            pcm: Array(repeating: Float(0.25), count: completed ? 4 : 256), volume: slot == 0 ? 1 : 0,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1) }
        var map = Array(repeating: 0, count: 96); map[49] = 1; map[50] = 2
        return .init(title: "Public volume Lxx boundaries", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in .init(index: row, cells: (0..<3).map { channel in
                commands[row] ?? (row == 0 ? cell(note: UInt8(49 + channel), instrument: 1) : cell())
            }) })], instrumentsByIndex: [1: .init(index: 1, samples: samples,
                volumeEnvelope: curve(sustain: sustain, loop: loop, enabled: enabled), noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 2, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 64, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
