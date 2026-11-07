import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMColdVolumeEnvelopeTests: XCTestCase {
    func testPinnedColdFactorsKeepImmediateED0AndED1BirthAndClock() throws {
        // Independently authored stimuli: pinned native observations, in Q8 units.
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for first in [0, 3] { for segmented in [false, true] {
                for delay: UInt8 in [0, 0xD0, 0xD1] {
                    let points = [(first, 48)] + (segmented ? [(first + 7, 16)] : [])
                    let plan = adapt(song(curve(points), linear: linear, delay: delay), rate)
                    let birth = delay == 0xD1 ? 1 : 0
                    let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                    let targets = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    for tick in 0...10 {
                        let q8 = tick < first ? 0 : !segmented || tick >= first + 7
                            ? (segmented ? 4096 : 12288) : 12288 - 1170 * (tick - first)
                        XCTAssertEqual(states[tick].state.volumeTick, tick)
                        XCTAssertEqual(states[tick].scheduledFrame, (birth + tick) * Int(rate / 50))
                        XCTAssertEqual(states[tick].state.volumeValue, Float(q8) / 16384)
                        XCTAssertEqual(targets[tick].amplitude, Float(q8) / 16384)
                    }
                }
            } }
        } }
    }

    func testDisabledPanHistoryIsColdButPriorEnabledVolumeHistoryStaysWarm() throws {
        let cold = curve([(3, 48), (10, 16)])
        let neutral = PlaybackPanningEnvelope(enabled: true, points: [.init(tick: 0, value: 32), .init(tick: 10, value: 32)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1)
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let disabled = adapt(song(.disabled, linear: linear, commands: [1: cell(note: 49, instrument: 2)],
                second: cold, pan: neutral), rate)
            XCTAssertEqual(disabled.xmAudibleTimeline?.updatesByEvent[0]?.first?.amplitude, 1)
            XCTAssertEqual(disabled.xmEnvelopeTimeline?.updatesByEvent[1]?.prefix(4).map(\.state.volumeValue), [0, 0, 0, 0.75])
            let warm = adapt(song(curve([(0, 48)]), linear: linear,
                commands: [1: cell(note: 49, instrument: 3), 2: cell(note: 49, instrument: 2)],
                second: cold, pan: neutral), rate)
            XCTAssertEqual(warm.xmEnvelopeTimeline?.updatesByEvent[2]?.prefix(4).map(\.state.volumeValue), [0.75, 0.75, 0.75, 0.75])
            let selection = adapt(song(cold, linear: linear, commands: [0: cell(instrument: 1), 1: cell(note: 49, instrument: 1)]), rate)
            XCTAssertEqual(selection.pattern.events.count, 1)
            XCTAssertEqual(selection.xmEnvelopeTimeline?.updatesByEvent[0]?.prefix(4).map(\.state.volumeValue), [0, 0, 0, 0.75])
            // Positioning remains its existing explicit evaluator contract, including L00.
            let seek = adapt(song(cold, linear: linear, commands: [0: cell(note: 49, instrument: 1, effect: 21)]), rate)
            XCTAssertEqual(seek.xmEnvelopeTimeline?.updatesByEvent[0]?.first?.state.volumeValue, 0.75)
        } }
    }

    func testNoteOnlyCarryReachesThePendingPointAndColdSustainHoldsItsValue() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let carried = adapt(song(curve([(7, 48), (14, 16)]), linear: linear, commands: [1: cell(note: 49)]), rate)
            XCTAssertEqual(carried.pattern.events.count, 2)
            let states = try XCTUnwrap(carried.xmEnvelopeTimeline?.updatesByEvent[1])
            XCTAssertEqual(states.prefix(3).map(\.state.volumeTick), [6, 7, 8])
            XCTAssertEqual(states.prefix(3).map(\.state.volumeValue), [0, 0.75, Float(11118) / 16384])
            let held = adapt(song(curve([(7, 48)], sustain: 0), linear: linear), rate)
            let sustain = try XCTUnwrap(held.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(sustain.prefix(8).map(\.state.volumeValue), Array(repeating: 0, count: 7) + [0.75])
            XCTAssertEqual(sustain[8].state.volumeTick, 7) // Preserve the qualified logical hold clock.
            XCTAssertEqual(sustain[8].state.volumeValue, 0.75)
        } }
    }

    func testPublicColdFixtureWindowsRuntimePlansAndSilentSourceAdvancement() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/cold-volume-envelope-start.xm")
        let original = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for profile in [MixerMixProfile.vtx, .ft2] {
            let input = PlaybackSong(title: original.title, orders: original.orders, patternsByIndex: original.patternsByIndex,
                instrumentsByIndex: original.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: original.initialTiming, usesLinearFrequencyTable: linear,
                xmSampleSlotProvenanceByInstrument: original.xmSampleSlotProvenanceByInstrument)
            let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile), tick = Int(rate / 50)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: config, rows: 8)
            let renderer = PlaybackSongOfflineRenderer(), whole = renderer.render(request)
            XCTAssertEqual(whole.plan, RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate).plan)
            XCTAssertEqual(whole.plan.diagnostics.eventMappings.map(\.channelIndex), [1, 2])
            XCTAssertEqual(whole.plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1])
            XCTAssertTrue(whole.block.interleavedPCM.prefix(4 * tick * 2).allSatisfy { $0 == 0 })
            XCTAssertTrue(whole.block.interleavedPCM.dropFirst(4 * tick * 2).contains { $0 != 0 })
            let empty = try XCTUnwrap(whole.plan.xmEnvelopeTimeline?.channelState(channelIndex: 3, atOrBefore: 2 * tick))
            XCTAssertNil(empty.sourceEventIndex)
            XCTAssertEqual(empty.sampleIndex, 2)
            XCTAssertEqual(empty.state.volumeValue, 0)
            XCTAssertNil(whole.plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: 4 * tick))
            for size in [1, 3, 5] { XCTAssertEqual(whole.block.interleavedPCM, renderer.renderWindowed(request, windowRows: size).block.interleavedPCM) }
            var streamed = [Float]()
            _ = renderer.renderStreaming(request, chunkFrameCount: 997) { _, _, block in streamed += block.interleavedPCM }
            XCTAssertEqual(streamed, whole.block.interleavedPCM)
            #if DEBUG
            let session = PlaybackSongOfflineRenderSession(request: request)
            _ = session.render(frames: 2 * tick)
            let source = try XCTUnwrap(session.sourceVoiceForTesting(0))
            XCTAssertTrue(source.active)
            XCTAssertGreaterThan(source.samplePosition, 0) // Zero envelope does not postpone source admission.
            XCTAssertEqual(source.envelopeSemanticState?.volumeTick, 0)
            XCTAssertEqual(source.envelopeSemanticState?.volumeValue, 0)
            XCTAssertEqual(source.audibleOutputState?.target, [0, 0, 0])
            let partition = renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [tick - 1, tick, tick + 1, 4 * tick - 1, 4 * tick, 4 * tick + 1, 8 * tick])
            XCTAssertEqual(partition.block.interleavedPCM, whole.block.interleavedPCM)
            #endif
        } } }
    }

    private func curve(_ points: [(Int, Int)], sustain: Int? = nil) -> PlaybackVolumeEnvelope {
        .init(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: sustain,
            loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: sustain == nil ? 1 : 3, fadeout: 0)
    }
    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }
    private func adapt(_ song: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
    }
    private func song(_ envelope: PlaybackVolumeEnvelope, linear: Bool, delay: UInt8 = 0,
                      commands: [Int: PlaybackCell] = [:], second: PlaybackVolumeEnvelope? = nil,
                      pan: PlaybackPanningEnvelope = .disabled) -> PlaybackSong {
        func instrument(_ index: Int, _ volume: PlaybackVolumeEnvelope) -> PlaybackInstrument {
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
                volume: 1, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 256, loopType: 1)
            return .init(index: index, samples: [sample], volumeEnvelope: volume, panningEnvelope: pan,
                noteSampleMap: Array(repeating: 0, count: 96))
        }
        return .init(title: "Public cold envelope control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in .init(index: row, cells: [
                commands[row] ?? (row == 0 ? cell(note: 49, instrument: 1, effect: delay == 0 ? 0 : 14, parameter: delay) : cell())
            ]) })], instrumentsByIndex: [1: instrument(1, envelope), 2: instrument(2, second ?? envelope), 3: instrument(3, .disabled)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
