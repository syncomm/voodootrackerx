import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class NoteOnlyRoutingTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testCarriedInstrumentAndExactNewNoteMapOwnRoutingAndDefaults() throws {
        let module = song([cell(note: 37, instrument: 1), cell(effect: 12, param: 16),
            cell(note: 39), cell(), cell(instrument: 2), cell(note: 49)])
        let (context, states) = inspect(module)
        XCTAssertEqual(states.map(\.carriedInstrumentIndex), [1, 1, 1, 1, 2, 2])
        XCTAssertEqual(states.map(\.activeInstrumentIndex), [1, 1, 1, 1, 1, 2])
        XCTAssertEqual(context.eventMappings.map(\.sampleIndex), [0, 0, 1])
        XCTAssertEqual(context.eventMappings.map(\.mappedSampleIndex), [0, 0, 1])
        XCTAssertTrue(context.eventMappings.allSatisfy { $0.sampleSelectionMethod == .sampleMap && !$0.firstPlayableSampleFallbackUsed })
        XCTAssertEqual(context.events.map(\.scheduledStartFrame), [0, 11_520, 28_800])
        XCTAssertEqual(context.events.map(\.initialSourceFrame), [0, 0, 0])
        XCTAssertEqual(states.map(\.baseChannelVolume), [64, 16, 16, 16, 64, 64])
        XCTAssertEqual(states.map(\.triggeredSampleDefaultVolume), [64, 64, 64, 64, 64, 40])
        XCTAssertEqual(states[5].outputChannelVolume, 64)
        XCTAssertEqual(states[5].panningValue, 64)
        XCTAssertEqual(states[5].triggeredSampleDefaultPan, 224)
        XCTAssertEqual(context.events.last?.gain, 0.625) // Independent header factor is retained.
        XCTAssertEqual(context.events.last?.sample.monoPCM, Array(repeating: -0.125, count: 256))
    }

    func testOrdinaryReleaseAndCrossInstrumentPendingSegmentContinue() throws {
        for points in [[(0, 32), (4, 64), (40, 64)], [(0, 32), (4, 64), (8, 32), (16, 48)],
                       [(0, 32), (2, 48), (4, 64), (12, 32)]] {
            let module = song([cell(note: 37, instrument: 1), cell(), cell(instrument: 2),
                cell(note: 49), cell(note: 97), cell(), cell(), cell()], secondPoints: points)
            let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
            let history = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1])
            XCTAssertEqual(history.first?.scheduledFrame, 17_280)
            XCTAssertEqual(history.first?.state.volumeTick, 6)
            XCTAssertEqual(history.first?.state.panTick, 2)
            XCTAssertEqual(history.first?.state.volumeValue, 0.25)
            XCTAssertEqual(history.first?.state.keyOn, true)
            XCTAssertEqual(history.first?.state.fadeoutAccumulator, 32_768)
            XCTAssertEqual(history.first { $0.scheduledFrame == 23_040 }?.state.fadeoutAccumulator, 31_744)
            XCTAssertEqual(history.first { $0.scheduledFrame == 19_200 }?.state.volumeValue,
                points[2].0 == 8 ? 0.5 : 0.25)
        }
        let plan = Adapter.adapt(song([cell(note: 37, instrument: 1), cell(note: 97), cell(note: 49), cell()]),
            orderIndex: 0, sampleRate: 48_000)
        let start = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first)
        XCTAssertEqual(start.state.volumeTick, 12)
        XCTAssertFalse(start.state.keyOn)
        XCTAssertEqual(start.state.fadeoutAccumulator, 25_600)
        let plain = inspect(song([cell(note: 37, instrument: 1), cell(note: 97), cell(note: 49)], envelope: false))
        XCTAssertEqual(plain.1.last?.baseChannelVolume, 0)
        XCTAssertEqual(plain.0.events.last?.gain, 0)
    }

    func testNoOwnerColdChannelCompletedSourceAndUnavailableRoutes() throws {
        let empty = inspect(song([cell(note: 37), cell(note: 49)]))
        XCTAssertTrue(empty.0.events.isEmpty)
        XCTAssertTrue(empty.1.allSatisfy { $0.carriedInstrumentIndex == nil && $0.activeEventIndex == nil })
        XCTAssertTrue(inspect(song([cell(instrument: 2), cell(note: 49)], missingMap: true)).0.events.isEmpty)
        let cold = Adapter.adapt(song([cell(instrument: 2), cell(note: 49), cell(), cell(instrument: 2)]),
            orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(cold.pattern.events.count, 1)
        XCTAssertEqual(cold.pattern.events[0].gain, 0)
        XCTAssertEqual(cold.xmEnvelopeTimeline?.updatesByEvent[0]?.first?.state.volumeTick, 1)
        XCTAssertEqual(cold.xmEnvelopeTimeline?.updatesByEvent[0]?.first?.state.volumeValue, 0)
        XCTAssertEqual(cold.xmEnvelopeTimeline?.updates.first { $0.scheduledFrame == 17_280 }?.state.volumeValue, 0.5)
        let coldRelease = Adapter.adapt(song([cell(instrument: 2), cell(note: 97), cell(note: 49), cell()]),
            orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(coldRelease.xmEnvelopeTimeline?.updatesByEvent[0]?.first?.state.keyOn, false)
        XCTAssertEqual(coldRelease.xmEnvelopeTimeline?.updatesByEvent[0]?.first?.state.fadeoutAccumulator, 32_768)
        XCTAssertEqual(coldRelease.xmEnvelopeTimeline?.updatesByEvent[0]?.first?.state.panTick, 0)
        XCTAssertEqual(coldRelease.xmEnvelopeTimeline?.updatesByEvent[0]?.last?.state.panTick, 3)
        let completed = song([cell(note: 37, instrument: 3), cell(), cell(note: 37), cell()])
        let full = PlaybackSongOfflineRenderer().render(.init(song: completed, config: .init(sampleRate: 48_000), rows: 4))
        XCTAssertEqual(full.plan.pattern.events.count, 2)
        XCTAssertTrue(full.block.interleavedPCM[(5760 * 2)..<(11_520 * 2)].allSatisfy { $0 == 0 })
        XCTAssertTrue(full.block.interleavedPCM[(11_520 * 2)..<(12_480 * 2)].contains { $0 != 0 })
        for missing in [true, false] {
            let module = song([cell(note: 37, instrument: 2), cell(note: 49), cell(effect: 12, param: 64), cell()],
                missing: missing, empty: !missing)
            let (context, states) = inspect(module)
            XCTAssertEqual(context.events.count, 1)
            XCTAssertEqual(context.xmEmptyRoutes.map(\.scheduledFrame), [5760])
            XCTAssertNil(states[1].activeEventIndex)
            XCTAssertEqual(states[1].triggeredSampleDefaultVolume, missing ? 48 : 40)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 48_000), rows: 4)
            let renderer = PlaybackSongOfflineRenderer(), result = renderer.render(request)
            XCTAssertTrue(result.block.interleavedPCM[(5760 * 2)...].allSatisfy { $0 == 0 })
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48_000).events
                .filter { $0.primaryCategory == "empty_route_source_stop" }.map(\.scheduledFrame), [5760])
        }
    }

    func testTonePortamentoAndK00DoNotTriggerWhileDelayAndRetriggersTriggerOnce() throws {
        for target in [cell(note: 49, effect: 3, param: 4), cell(note: 49, effect: 5, param: 2), cell(note: 49, volume: 0xF2)] {
            let (context, states) = inspect(song([cell(note: 37, instrument: 1), cell(instrument: 2), target]))
            XCTAssertEqual(context.events.count, 1)
            XCTAssertEqual(states.last?.carriedInstrumentIndex, 2)
            XCTAssertEqual(states.last?.activeInstrumentIndex, 1)
            XCTAssertEqual(states.last?.activeSampleIndex, 0)
            XCTAssertEqual(states.last?.tonePortamentoTargetNote, 49)
        }
        for (effect, param, ticks): (UInt8, UInt8, [Int]) in [(14, 0xD0, [0]), (14, 0xD2, [2]),
                (14, 0xD7, []), (14, 0x92, [0, 2, 4]), (27, 0x92, [0, 2, 4]), (20, 0, [])] {
            let module = song([cell(note: 37, instrument: 1), cell(note: 97), cell(note: 49, effect: effect, param: param), cell()])
            let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(plan.pattern.events.dropFirst().map(\.tick), ticks)
            XCTAssertEqual(plan.pattern.events.dropFirst().map(\.scheduledStartFrame), ticks.map { 11_520 + $0 * 960 })
            if param == 0xD2 {
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state, .init())
            } else if !ticks.isEmpty {
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.keyOn, false)
            }
        }
    }

    func testModulationPhasesHeldOutputAndEffectMemoriesSurviveNormalTrigger() {
        let module = song([cell(note: 37, instrument: 1), cell(effect: 9, param: 1), cell(note: 39, effect: 3, param: 4),
            cell(effect: 10, param: 2), cell(effect: 4, param: 0x47), cell(volume: 0x30, effect: 7, param: 0x48), cell(note: 49)])
        let (_, states) = inspect(module), before = states[5], after = states[6]
        XCTAssertEqual(after.baseChannelVolume, 32)
        XCTAssertEqual(after.outputChannelVolume, 63)
        XCTAssertEqual(after.vibratoPhase, 80)
        XCTAssertEqual(after.tremolo.phase, 80)
        XCTAssertEqual(after.tonePortamentoTargetNote, before.tonePortamentoTargetNote)
        XCTAssertEqual(after.tonePortamentoSpeed, before.tonePortamentoSpeed)
        XCTAssertEqual(after.volumeSlideMemory, before.volumeSlideMemory)
        XCTAssertEqual(after.sampleOffsetMemory, before.sampleOffsetMemory)
        XCTAssertEqual(after.vibratoSpeed, before.vibratoSpeed)
        XCTAssertEqual(after.vibratoDepth, before.vibratoDepth)
        XCTAssertEqual(after.tremolo, before.tremolo)
    }

    func testSharedRuntimePlanWindowBoundariesAndInertPanningEnvelope() throws {
        let cells = [cell(note: 37, instrument: 1), cell(note: 39), cell(instrument: 2), cell(note: 49),
            cell(note: 51, effect: 3, param: 4), cell(note: 97), cell(note: 49), cell(), cell()]
        for rate in [44_100.0, 48_000] {
            let module = song(cells), runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(runtime.plan, plan)
            XCTAssertEqual(runtime.events.filter { if case .noteTrigger = $0.action { return true }; return false }.map(\.scheduledFrame),
                plan.pattern.events.compactMap(\.scheduledStartFrame))
            let config = MixerRenderConfig(sampleRate: rate), renderer = PlaybackSongOfflineRenderer()
            let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: cells.count)
            let full = renderer.render(request).block.interleavedPCM
            for rows in [1, 2, 3, 4] { XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, full) }
            XCTAssertEqual(renderer.render(.init(song: song(cells, panEnvelope: false), config: config, rows: cells.count)).block.interleavedPCM, full)
        }
    }

    func testEmptyHeaderVolume40SurvivesSilentResetAndLaterPlayableNoteOnly() throws {
        let cells = [cell(note: 37, instrument: 2), cell(effect: 12, param: 16), cell(),
            cell(note: 49), cell(instrument: 2), cell(note: 37), cell(), cell(), cell(note: 97), cell(), cell(), cell()]
        for volume: UInt8 in [0, 40] {
            let module = song(cells, empty: true, emptyVolume: volume)
            let (context, states) = inspect(module)
            XCTAssertEqual(context.events.count, 2)
            XCTAssertEqual(states[3].baseChannelVolume, 16)
            XCTAssertEqual(states[3].triggeredSampleDefaultVolume, Int(volume))
            XCTAssertNil(states[3].activeEventIndex)
            XCTAssertEqual(states[4].baseChannelVolume, Int(volume))
            XCTAssertEqual(states[4].panningValue, 128)
            XCTAssertEqual(states[5].baseChannelVolume, Int(volume))
            XCTAssertEqual(states[5].outputChannelVolume, Int(volume))
            XCTAssertEqual(states[5].triggeredSampleDefaultVolume, 48)
            XCTAssertEqual(states[5].panningValue, 128)
            for rate in [44_100.0, 48_000] {
                let renderer = PlaybackSongOfflineRenderer()
                let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: cells.count)
                let full = renderer.render(request)
                let emptyFrame = Int(rate * 0.36), resetFrame = Int(rate * 0.48), nextFrame = Int(rate * 0.6)
                let timeline = try XCTUnwrap(full.plan.xmEnvelopeTimeline)
                XCTAssertEqual(timeline.channelState(channelIndex: 0, atOrBefore: emptyFrame)?.state.volumeTick, 18)
                XCTAssertEqual(timeline.channelState(channelIndex: 0, atOrBefore: resetFrame)?.state.volumeTick, 0)
                let resumed = try XCTUnwrap(timeline.updatesByEvent[1]?.first)
                XCTAssertEqual(resumed.scheduledFrame, nextFrame)
                XCTAssertEqual(resumed.state.volumeTick, 6)
                XCTAssertEqual(resumed.state.volumeValue, 1)
                XCTAssertTrue(resumed.state.keyOn)
                XCTAssertEqual(resumed.state.fadeoutAccumulator, 32_768)
                XCTAssertTrue(full.block.interleavedPCM[(emptyFrame * 2)..<(nextFrame * 2)].allSatisfy { $0 == 0 })
                XCTAssertEqual(full.block.interleavedPCM[(nextFrame * 2)..<((nextFrame + 1000) * 2)].contains { $0 != 0 }, volume != 0)
                for window in [1, 2, 3, 5] {
                    let result = renderer.renderWindowed(request, windowRows: window)
                    XCTAssertLessThan(zip(full.block.interleavedPCM, result.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
                    XCTAssertEqual(result.plan.xmEnvelopeTimeline?.channelUpdates, timeline.channelUpdates)
                }
            }
        }
    }

    func testEmptyTuningAndSilentReleaseSurviveUntilTheLaterValidNote() throws {
        let module = song([cell(note: 37, instrument: 2), cell(note: 49), cell(note: 56, effect: 3, param: 4),
            cell(note: 97), cell(instrument: 2), cell(note: 37)], empty: true, emptyFinetune: 64, emptyRelativeNote: 12)
        let (_, states) = inspect(module)
        XCTAssertEqual(states[1].activeLinearPeriod, 3808)
        XCTAssertEqual(states[1].activeSampleFinetune, 64)
        XCTAssertEqual(states[1].activeSampleRelativeNote, 12)
        XCTAssertEqual(states[1].panningValue, 32)
        XCTAssertEqual(states[1].triggeredSampleDefaultPan, 128)
        XCTAssertEqual(states[2].tonePortamentoTargetLinearPeriod, 3360)
        XCTAssertEqual(states[4].tonePortamentoTargetLinearPeriod, 3360)
        XCTAssertEqual(states[5].activeLinearPeriod, 5376)
        let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        let release = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: 17_280))
        XCTAssertNil(release.sourceEventIndex)
        XCTAssertFalse(release.state.keyOn)
        XCTAssertEqual(release.state.fadeoutAccumulator, 32_256)
        XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.volumeTick, 6)
    }

    func testEmptyRouteKeepsK00DelayAndE9TimingWithoutCreatingSources() throws {
        for (effect, parameter, stops, ticks): (UInt8, UInt8, [Int], [Int]) in [
            (20, 0, [], [18, 19, 20, 21, 22, 23]),
            (14, 0xD0, [17_280], [18, 19, 20, 21, 22, 23]),
            (14, 0xD2, [19_200], [18, 19, 0, 1, 2, 3]),
            (14, 0xD7, [], [18, 19, 20, 21, 22, 23]),
            (14, 0x92, [17_280], [18, 19, 0, 1, 0, 1]),
            (27, 0x92, [17_280], [18, 19, 20, 21, 22, 23]),
        ] {
            let module = song([cell(note: 37, instrument: 2), cell(volume: 0x20, effect: 4, param: 0x47),
                cell(effect: 7, param: 0x48),
                cell(note: 49, effect: effect, param: parameter), cell(instrument: 2), cell(note: 37)], empty: true)
            let (_, states) = inspect(module)
            XCTAssertEqual(states[2].vibratoPhase, 80)
            XCTAssertEqual(states[2].tremolo.phase, 80)
            let resetsPhases = effect == 14 && (parameter == 0xD2 || parameter == 0x92)
            XCTAssertEqual(states[3].vibratoPhase, resetsPhases ? 0 : 80)
            XCTAssertEqual(states[3].tremolo.phase, resetsPhases ? 0 : 80)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 48_000), rows: 6)
            let renderer = PlaybackSongOfflineRenderer(), result = renderer.render(request)
            XCTAssertEqual(result.plan.pattern.events.count, 2)
            XCTAssertEqual(result.plan.xmEmptyRoutes.filter { $0.stoppedEventIndex != nil }.map(\.scheduledFrame), stops)
            let row = result.plan.xmEnvelopeTimeline!.channelUpdates.filter { $0.source.rowIndex == 3 }
            XCTAssertEqual(row.map(\.state.volumeTick), ticks)
            if let stop = stops.first {
                XCTAssertTrue(result.block.interleavedPCM[(stop * 2)..<(28_800 * 2)].allSatisfy { $0 == 0 })
            }
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
        }
    }

    private func inspect(_ song: PlaybackSong) -> (Adapter.AdapterRowContext, [Adapter.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: 48_000)
        var context = Adapter.AdapterRowContext(), states = [Adapter.ChannelState]()
        for row in traversal.rows {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow), context: &context)
            states.append(context.channelStates[0])
        }
        return (context, states)
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ cells: [PlaybackCell], envelope: Bool = true, panEnvelope: Bool = true,
                      secondPoints: [(Int, Int)] = [(0, 32), (4, 64), (40, 64)], missing: Bool = false, empty: Bool = false, missingMap: Bool = false,
                      emptyVolume: UInt8 = 40, emptyFinetune: Int = 0, emptyRelativeNote: Int = 0) -> PlaybackSong {
        func sample(_ instrument: Int, _ slot: Int, _ volume: Float, _ pan: UInt8) -> PlaybackSample {
            let count = instrument == 3 ? 2 : 256
            return .init(instrumentIndex: instrument, sampleIndex: slot,
                pcm: Array(repeating: slot == 0 ? 0.25 : -0.125, count: count), volume: volume, panning: pan,
                relativeNote: 0, finetune: 0, baseSampleRate: 100, loopStart: 0,
                loopLength: instrument == 3 || count == 0 ? 0 : count, loopType: instrument == 3 || count == 0 ? 0 : 2)
        }
        func volume(_ points: [(Int, Int)], _ fadeout: Int) -> PlaybackVolumeEnvelope {
            .init(enabled: envelope, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: nil,
                loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: fadeout)
        }
        let pan = PlaybackPanningEnvelope(enabled: panEnvelope, points: [.init(tick: 0, value: 0), .init(tick: 4, value: 64)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 1, typeFlags: panEnvelope ? 5 : 0)
        let map = Array(repeating: 0, count: 48) + Array(repeating: 1, count: 48)
        return .init(title: "Note routing", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1, 1, 0.375, 192), sample(1, 0, 1, 64)],
                volumeEnvelope: volume([(0, 64), (3, 16), (40, 16)], 1024), panningEnvelope: pan, noteSampleMap: map),
                2: .init(index: 2, samples: empty ? [sample(2, 0, 0.75, 32)] : [sample(2, 1, 0.625, 224), sample(2, 0, 0.75, 32)],
                    volumeEnvelope: volume(secondPoints, 512), panningEnvelope: pan,
                    noteSampleMap: missingMap ? nil : missing ? Array(repeating: 0, count: 48) + Array(repeating: 15, count: 48) : map),
                3: .init(index: 3, samples: [sample(3, 0, 1, 128)], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: empty ? [2: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: emptyVolume, panning: 128,
                finetune: emptyFinetune, relativeNote: emptyRelativeNote)]] : [:])
    }
}
