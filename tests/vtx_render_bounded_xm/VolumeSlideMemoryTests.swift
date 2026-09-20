import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VolumeSlideMemoryTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testSharedWholeByteMemoryAndCrossFamilyReplay() throws {
        // FT2 87be425: A/5/6 dispatch to volSlide; upper nibble wins, whole byte persists.
        for (seed, replay): (UInt8, UInt8) in [(6, 6), (10, 6), (5, 6), (6, 10), (6, 5)] {
            for parameter: UInt8 in [2, 0x30, 0x12, 0xFF] {
                let (context, states) = inspect(song([[cell(seed, parameter, note: 49, volume: 0x30)], [cell(replay)]]))
                XCTAssertNil(Adapter.ChannelState().volumeSlideMemory)
                XCTAssertEqual(states.map { $0[0].volumeSlideMemory?.parameter }, [parameter, parameter])
                XCTAssertEqual(states.map { $0[0].volumeSlideMemory?.source.effectParam }, [parameter, parameter])
                let delta = parameter >> 4 > 0 ? Int(parameter >> 4) : -Int(parameter & 15)
                let afterSeed = min(64, max(0, 32 + delta * (seed == 6 ? 1 : 2)))
                let afterReplay = min(64, max(0, afterSeed + delta * (replay == 6 ? 1 : 2)))
                XCTAssertEqual(states.map { $0[0].baseChannelVolume }, [afterSeed, afterReplay])
                XCTAssertEqual(states.map { $0[0].outputChannelVolume }, [afterSeed, afterReplay])
                let updates = context.voiceStateUpdates.filter { $0.source.rowIndex == 1 }
                XCTAssertEqual(updates.count, replay == 6 ? 1 : 2)
                for update in updates {
                    XCTAssertEqual(update.effectParam, 0)
                    XCTAssertTrue(update.effectMemoryReused)
                    XCTAssertFalse(update.effectMemoryDeferred)
                    XCTAssertEqual(update.memorySource?.effectType, seed)
                    XCTAssertEqual(update.memorySource?.effectParam, parameter)
                    XCTAssertEqual(update.memorySource?.source.rowIndex, 0)
                    XCTAssertEqual(update.volumeSlideRawUpNibble, Int(parameter >> 4))
                    XCTAssertEqual(update.volumeSlideRawDownNibble, Int(parameter & 15))
                }
            }
        }
    }

    func testInitialZeroAndVibratoMemoryRemainIndependent() {
        for vibrato in [false, true] {
            for slide in [false, true] {
                let rows = [[cell(vibrato ? 4 : 0, vibrato ? 0x48 : 0, note: 49, volume: 0x30)],
                            [cell(6, slide ? 2 : 0)], [cell(6)]]
                let (context, states) = inspect(song(rows))
                XCTAssertEqual(states.map { $0[0].baseChannelVolume }, slide ? [32, 30, 28] : [32, 32, 32])
                XCTAssertEqual(states.map { $0[0].vibratoSpeed }, Array(repeating: vibrato ? 4 : 0, count: 3))
                XCTAssertEqual(states.map { $0[0].vibratoDepth }, Array(repeating: vibrato ? 8 : 0, count: 3))
                XCTAssertEqual(states.map { $0[0].vibratoPhase }, vibrato ? [32, 64, 96] : [0, 0, 0])
                let last = context.voiceStateUpdates.last!
                XCTAssertEqual(last.effectMemoryReused, slide)
                XCTAssertFalse(last.effectMemoryDeferred)
                XCTAssertEqual(last.applied, slide)
                XCTAssertEqual(last.command, .effect6xyVolumeSlide(up: 0, down: slide ? 2 : 0))
                XCTAssertTrue(context.vibratoEffects.allSatisfy { !$0.effectMemoryMissing && !$0.effectMemoryDeferred })
                XCTAssertEqual(context.vibratoEffects.last?.vibratoSpeedSource, vibrato ? "4xy_channel_state" : "initial_zero_state")
            }
        }
    }

    func testChannelLocalMemorySurvivesRowsEffectsAndTriggers() {
        let rows = [[cell(6, 2, note: 49, volume: 0x30), cell(6, 0x30, note: 49, volume: 0x30)],
                    [cell(), cell()], [cell(12, 32), cell(8, 128)],
                    [cell(instrument: 1), cell(note: 49, instrument: 0)], [cell(6), cell(6)]]
        let (context, states) = inspect(song(rows))
        for row in states {
            XCTAssertEqual(row.map { $0.volumeSlideMemory?.source.effectParam }, [2, 0x30])
            XCTAssertEqual(row.map { $0.volumeSlideMemory?.source.source.rowIndex }, [0, 0])
        }
        let replay = context.voiceStateUpdates.filter { $0.source.rowIndex == 4 }
        XCTAssertEqual(replay.map(\.command), [.effect6xyVolumeSlide(up: 0, down: 2), .effect6xyVolumeSlide(up: 3, down: 0)])
        XCTAssertEqual(replay.map { $0.memorySource?.channelIndex }, [0, 1])
    }

    func testSpeedOneCannotSeedOrOverwriteSharedMemoryAndKeepsNonzeroRowApplication() {
        for family: UInt8 in [5, 6, 10] {
            let (context, states) = inspect(song([[cell(family, 2, note: 49, volume: 0x30)], [cell(6)]], speed: 1))
            XCTAssertTrue(states.allSatisfy { $0[0].volumeSlideMemory == nil })
            XCTAssertEqual(states.map { $0[0].baseChannelVolume }, family == 6 ? [30, 30] : [32, 32])
            XCTAssertTrue(context.vibratoEffects.allSatisfy { $0.stepUpdates.isEmpty })
        }
        let rows = [[cell(6, 2, note: 49, volume: 0x30), cell()],
                    [cell(6, 0x40), cell(15, 1)], [cell(6), cell()], [cell(6), cell(15, 3)]]
        let (_, states) = inspect(song(rows))
        XCTAssertEqual(states.map { $0[0].volumeSlideMemory?.source.effectParam }, [2, 2, 2, 2])
        XCTAssertEqual(states.map { $0[0].baseChannelVolume }, [30, 34, 34, 32])
    }

    func testReplayUsesBaseClampsAndPreservesDownstreamGainFactors() throws {
        for (parameter, base, expected): (UInt8, Int, Int) in [(2, 32, 30), (0x30, 63, 64), (15, 1, 0), (0, 32, 32)] {
            var state = Adapter.ChannelState()
            let source = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)
            _ = Adapter.applyEffectColumnState(from: cell(6, parameter), source: source, channelIndex: 0,
                syntheticRow: 0, scheduledFrame: 0, rowSpeed: 3, channelState: &state, globalVolumeValue: 32)
            state.baseChannelVolume = base
            state.outputChannelVolume = 16
            state.activeSampleVolume = 0.25
            state.activeEventIndex = 0
            let before = state.volumeSlideMemory
            let update = try XCTUnwrap(Adapter.applyEffectColumnState(from: cell(6), source: source, channelIndex: 0,
                syntheticRow: 1, scheduledFrame: 2880, rowSpeed: 3, channelState: &state, globalVolumeValue: 32))
            XCTAssertEqual(state.volumeSlideMemory, before)
            XCTAssertEqual(state.baseChannelVolume, expected)
            XCTAssertEqual(state.outputChannelVolume, expected)
            XCTAssertEqual(state.activeSampleVolume, 0.25)
            XCTAssertEqual(update.gainBefore, Float(16) / 512)
            XCTAssertEqual(update.gainAfter, Float(expected) / 512)
            XCTAssertEqual(update.syntheticTick, 0) // Existing row approximation, not FT2 tick parity.
            XCTAssertEqual(update.scheduledFrame, 2880)
            XCTAssertEqual(update.behavior, .rowLevelApproximation)
        }
    }

    func testLooped600TriggerClassificationUsesEachVisitMemory() {
        let module = song([[cell(6, note: 49, volume: 0x30), cell(14, 0x60)],
                           [cell(6, 2), cell()], [cell(), cell(14, 0x61)]])
        let plan = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48000)
        let triggers = plan.events.filter { if case .noteTrigger = $0.action { return true }; return false }
        XCTAssertEqual(triggers.count, 2)
        XCTAssertEqual(triggers.map { $0.categories.contains("vibrato_volume_slide_600_memory_reused") }, [false, true])
        let gains = triggers.compactMap { event -> Float? in
            if case let .noteTrigger(_, note, _) = event.action { return note.gain }; return nil
        }
        XCTAssertEqual(gains, [32 / 64, 30 / 64])
    }

    func testPublicFixturePinsMemoryOriginsDiagnosticsAndWindowedRendering() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/effect-memory.xm")
        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        let (_, states) = inspect(song)
        XCTAssertEqual(states.map { $0[0].volumeSlideMemory?.source.effectParam }, [nil] + Array(repeating: 2, count: 15))
        XCTAssertEqual(states.map { $0[1].volumeSlideMemory?.source.effectType },
                       [nil, nil, nil, nil, 10, 10, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6])
        let request = PlaybackSongOfflineRenderRequest(song: song, config: MixerRenderConfig(sampleRate: 48000, channelCount: 1), rows: 16)
        let renderer = PlaybackSongOfflineRenderer(), bounded = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 2)
        XCTAssertEqual(bounded.block.frameCount, 82560)
        XCTAssertEqual(bounded.block.interleavedPCM.count, windowed.block.interleavedPCM.count)
        XCTAssertLessThanOrEqual(zip(bounded.block.interleavedPCM, windowed.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-6)
        let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: bounded)
        let updates = try XCTUnwrap(json["volume_panning_state_updates"] as? [[String: Any]])
            .filter { $0["effect_type"] as? Int == 6 && $0["effect_param"] as? Int == 0 }
        XCTAssertEqual(updates.filter { $0["effect_memory_reused"] as? Bool == true }.count, 10)
        XCTAssertTrue(updates.allSatisfy { $0["effect_memory_deferred"] as? Bool == false })
        let commands = try XCTUnwrap(json["pattern_traversal_timing_effects"] as? [[String: Any]])
        for update in updates where update["effect_memory_reused"] as? Bool == true {
            let source = try XCTUnwrap(update["source"] as? [String: Int])
            let command = try XCTUnwrap(commands.first {
                $0["source"] as? [String: Int] == source && $0["channel_index"] as? Int == update["channel_index"] as? Int
            })
            XCTAssertEqual(command["status"] as? String, "applied")
        }
        let summary = try XCTUnwrap(json["volume_panning_state_update_summary"] as? [String: Any])
        XCTAssertEqual(summary["vibrato_volume_slide_6xy_zero_param_effect_memory_deferred"] as? Int, 0)
    }

    private func inspect(_ song: PlaybackSong) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: 48000)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
        for row in traversal.rows {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow,
                song: song, timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow, tick: 0), context: &context)
            states.append(context.channelStates)
        }
        return (context, states)
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                      instrument: UInt8? = nil, volume: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: instrument ?? (note == 49 ? 1 : 0), volumeColumn: volume,
                     effectType: effect, effectParam: parameter)
    }

    private func song(_ rows: [[PlaybackCell]], speed: Int = 3) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0.5, 0, -0.5], volume: 1,
                                    relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 4, loopType: 1)
        return PlaybackSong(title: "Slide memory", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: rows.enumerated().map { PlaybackRow(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: speed, bpm: 125), usesLinearFrequencyTable: true)
    }
}
