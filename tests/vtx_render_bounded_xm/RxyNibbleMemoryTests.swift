import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class RxyNibbleMemoryTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testIndependentSeededReplayUsesCurrentSchedulerAndUnchangedArithmetic() {
        for rate in [44_100.0, 48_000] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)]] +
                [0x93, 0x00, 0x03, 0x90, 0x04, 0x20, 0x00].map { [c(27, UInt8($0))] }), rate)
            XCTAssertEqual(states.dropFirst().map { $0[0].rVolumeModeMemory }, [9, 9, 9, 9, 9, 2, 2])
            XCTAssertEqual(states.dropFirst().map { $0[0].rRetriggerSpeedMemory }, [3, 3, 3, 3, 4, 4, 4])
            XCTAssertEqual(context.retriggerEffects.map(\.retriggerTicks), [[3], [3], [3], [3], [4], [4], [4]])
            XCTAssertEqual(context.retriggerEffects.map(\.volumeValuesAfter), [[33], [34], [35], [36], [37], [35], [33]])
            XCTAssertEqual(context.retriggerEffects.map(\.intervalNibble), [3, 0, 3, 0, 4, 0, 0])
            let down = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x13)], [c(27)]]), rate).0
            XCTAssertEqual(down.retriggerEffects.map(\.volumeModeNibble), [1, 1])
            XCTAssertEqual(down.retriggerEffects.map(\.volumeValuesAfter), [[31], [30]])
        }
        XCTAssertEqual(Adapter.retriggerVolumeAdjustment(modeNibble: 6, currentVolume: 32).volumeAfter, 21) // G22 stays open.
        XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.size, 1152)
        XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.alignment, 8)
    }

    func testColdSequencesResolveLiteralBytesWithoutZeroIntervalDispatch() throws {
        let cases: [([UInt8], [UInt8], [UInt8])] = [
            ([0x90, 0x03, 0], [9, 9, 9], [0, 3, 3]),
            ([0x03, 0x90, 0], [0, 9, 9], [3, 3, 3]),
            ([0x90, 0], [9, 9], [0, 0]), ([0x03, 0], [0, 0], [3, 3]), ([0], [0], [0])]
        for (parameters, modes, speeds) in cases {
            for active in [false, true] {
                let prefix = active ? [[c(note: 49, instrument: 1)]] : []
                let module = song(prefix + parameters.map { [c(27, $0)] })
                let (context, states) = inspect(module)
                XCTAssertEqual(states.dropFirst(prefix.count).map { $0[0].rVolumeModeMemory }, modes)
                XCTAssertEqual(states.dropFirst(prefix.count).map { $0[0].rRetriggerSpeedMemory }, speeds)
                for (index, diagnostic) in context.retriggerEffects.enumerated() {
                    XCTAssertEqual(diagnostic.volumeModeNibble, Int(modes[index]))
                    XCTAssertEqual(diagnostic.retriggerIntervalTicks, Int(speeds[index]))
                    if speeds[index] == 0 {
                        XCTAssertEqual(diagnostic.status, .rxyZeroIntervalDeferredToG21)
                        XCTAssertTrue(diagnostic.deferred)
                        XCTAssertFalse(diagnostic.ignoredAsNoOp)
                        XCTAssertTrue(diagnostic.retriggerEventIndices.isEmpty)
                        XCTAssertTrue(diagnostic.volumeValuesAfter.isEmpty)
                    }
                }
                let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from:
                    PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: 48_000), rows: module.patternsByIndex[0]!.rows.count)))
                let diagnostics = try XCTUnwrap(json["retrigger_effects"] as? [[String: Any]])
                for (index, item) in diagnostics.enumerated() {
                    XCTAssertEqual(item["stored_mode_memory"] as? Int, Int(modes[index]))
                    XCTAssertEqual(item["resolved_speed_nibble"] as? Int, Int(speeds[index]))
                    XCTAssertEqual(item["mode_memory_has_nonzero_origin"] as? Bool, modes[index] != 0)
                    XCTAssertEqual(item["speed_memory_has_nonzero_origin"] as? Bool, speeds[index] != 0)
                    XCTAssertEqual(item["mode_memory_reused"] as? Bool, parameters[index] >> 4 == 0)
                    XCTAssertEqual(item["speed_memory_reused"] as? Bool, parameters[index] & 15 == 0)
                    XCTAssertEqual(item["zero_interval_execution_deferred_to_g21"] as? Bool, speeds[index] == 0)
                }
            }
        }
        let cold = inspect(song([[c(27, 0x90)], [c(27)]])).1
        XCTAssertEqual(cold.map { $0[0].baseChannelVolume }, [64, 64]) // No source-less G21 arithmetic.
        let carried = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x90)], [c(27)]])).1
        XCTAssertEqual(carried.map { $0[0].baseChannelVolume }, [32, 32, 32])
        XCTAssertEqual(carried.map { $0[0].activeEventIndex }, [0, 0, 0])
    }

    func testChannelIndependenceAndSameCellResolutionRegardlessOfAdmission() {
        let (_, states) = inspect(song([[c(note: 49, instrument: 1), c(note: 49, instrument: 1)],
            [c(27, 0x93), c(27, 0x24)], [c(27), c(27)]]))
        XCTAssertEqual(states.last?.map(\.rVolumeModeMemory), [9, 2])
        XCTAssertEqual(states.last?.map(\.rRetriggerSpeedMemory), [3, 4])
        for shape in [c(27, 0x90, note: 53, instrument: 2), c(27, 0x90, note: 53), c(27, 0x90, instrument: 2),
                      c(27, 0x90, volume: 0x20), c(27, 0x90, volume: 0xC3), c(27, 0x90, volume: 0x61),
                      c(27, 0x90, volume: 0xF1), c(27, 0x90, note: 98), c(27, 0x90, note: 49, instrument: 99)] {
            let (context, history) = inspect(song([[c(note: 49, instrument: 1)], [shape], [c(27, 3)], [c(27)]]))
            XCTAssertEqual(history[1][0].rVolumeModeMemory, 9)
            XCTAssertEqual(history[1][0].rRetriggerSpeedMemory, 0)
            XCTAssertEqual(context.retriggerEffects.count, 3)
            XCTAssertEqual(context.retriggerEffects.map(\.volumeModeNibble), [9, 9, 9])
            XCTAssertEqual(context.retriggerEffects.map(\.retriggerIntervalTicks), [0, 3, 3])
            XCTAssertEqual(context.retriggerEffects[0].status, .rxyZeroIntervalDeferredToG21)
        }
        let gated = inspect(song([[c(27, 0x93, note: 49, instrument: 1, volume: 0xF1)], [c(27)]]))
        XCTAssertEqual(gated.1[0][0].rVolumeModeMemory, 9)
        XCTAssertEqual(gated.0.retriggerEffects.first?.status, .rowEntryNotScheduled)
    }

    func testLifetimeAcrossNotesInstrumentsReleaseCompletionEmptyRoutingOrdersAndLoops() {
        for transition in [c(note: 53), c(instrument: 2), c(note: 53, instrument: 2), c(note: 97), c(20), c(note: 50)] {
            for completed in [false, true] {
                let rows = [[c(note: 49, instrument: 1)], [c(27, 0x93)], [transition], [c(27)]]
                let (context, states) = inspect(song(rows, completed: completed, split: 3))
                XCTAssertTrue(states.dropFirst().allSatisfy { $0[0].rVolumeModeMemory == 9 && $0[0].rRetriggerSpeedMemory == 3 })
                XCTAssertEqual(context.retriggerEffects.last?.volumeModeNibble, 9)
                XCTAssertEqual(context.retriggerEffects.last?.retriggerIntervalTicks, 3)
            }
        }
        let loop = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x93)], [c(14, 0x60)], [c(27)], [c(14, 0x61)]]))
        XCTAssertEqual(loop.0.retriggerEffects.count, 3)
        XCTAssertTrue(loop.0.retriggerEffects.allSatisfy { $0.volumeModeNibble == 9 && $0.retriggerIntervalTicks == 3 })
        // Revisit a restart order in the same planning context; fresh contexts still start at zero.
        let module = song([[c(27, 0x93)], [c(27)]], split: 1)
        let (_, first) = inspect(module)
        let (restart, _) = inspect(song([[c(27)]]), initial: first.last)
        XCTAssertEqual(restart.retriggerEffects.last?.retriggerIntervalTicks, 3)
        XCTAssertEqual(inspect(song([[c(27)]])).0.retriggerEffects.first?.retriggerIntervalTicks, 0)
    }

    func testE9IndependenceSpeedAndFxxDoNotChangeTheCurrentRepeatGrid() {
        for e9: UInt8 in [0x90, 0x93] {
            let cold = inspect(song([[c(note: 49, instrument: 1)], [c(14, e9)], [c(27)]]))
            XCTAssertEqual(cold.1.last?[0].rRetriggerSpeedMemory, 0)
            XCTAssertEqual(cold.1.last?[0].rVolumeModeMemory, 0)
            let seeded = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [c(14, e9)], [c(27)]]))
            XCTAssertEqual(seeded.0.retriggerEffects[1].retriggerTicks, e9 == 0x90 ? [0] : [3])
            XCTAssertEqual(seeded.0.retriggerEffects.last?.retriggerTicks, [4])
        }
        for speed in [1, 2, 3, 6] {
            let plan = Adapter.adapt(song([[c(note: 49, instrument: 1)], [c(27, 0x93)], [c(27)]], speed: speed), orderIndex: 0, sampleRate: 48_000)
            XCTAssertTrue(plan.diagnostics.retriggerEffects.allSatisfy { $0.retriggerIntervalTicks == 3 && $0.retriggerTicks == (speed == 6 ? [3] : []) })
            for writer in [0, 1] {
                var row = [c(27), c(27)]; row[writer] = c(15, UInt8(speed))
                let (context, states) = inspect(song([[c(note: 49, instrument: 1), c(note: 49, instrument: 1)], [c(27, 0x93), c(27, 0x93)], row]))
                XCTAssertEqual(states.last?[1 - writer].rRetriggerSpeedMemory, 3)
                XCTAssertEqual(context.retriggerEffects.last?.retriggerTicks, speed == 6 ? [3] : [])
            }
        }
    }

    func testWholeWindowRuntimePlansAndMemoryDiagnosticsAgreeAtBothRates() throws {
        let module = song([[c(27, 0x90), c(27, 3)], [c(27, 3), c(27, 0x90)], [c(27), c(27)],
            [c(27, 0x93, note: 49, instrument: 1), c(27, 0x13, note: 53, instrument: 2)],
            [c(27), c(27)], [c(27, 3), c(27, 0x90)], [c(14, 0x90), c(note: 97)], [c(27), c(27)]], split: 4)
        for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, orderCount: 2, config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertEqual(runtime.events.filter { if case .noteTrigger = $0.action { return true }; return false }.map(\.scheduledFrame), full.plan.pattern.events.compactMap(\.scheduledStartFrame).sorted())
            for trigger in runtime.events {
                if case let .noteTrigger(index, event, mapping) = trigger.action {
                    XCTAssertEqual(event, full.plan.pattern.events[index])
                    XCTAssertEqual(mapping, full.plan.diagnostics.eventMappings.first { $0.eventIndex == index })
                    XCTAssertEqual(trigger.scheduledFrame, event.scheduledStartFrame)
                }
            }
            for window in [1, 2, 3, 5] {
                let result = renderer.renderWindowed(request, windowRows: window)
                XCTAssertEqual(result.plan.diagnostics.retriggerEffects, full.plan.diagnostics.retriggerEffects)
                XCTAssertEqual(result.block.interleavedPCM.count, full.block.interleavedPCM.count)
                XCTAssertLessThanOrEqual(zip(result.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
            XCTAssertTrue(full.plan.diagnostics.retriggerEffects.filter { $0.retriggerIntervalTicks == 0 && $0.effectType == 27 }.allSatisfy { !$0.applied && $0.retriggerFrames.isEmpty })
        }
    }

    private func inspect(_ song: PlaybackSong, _ rate: Double = 48_000, initial: [Adapter.ChannelState]? = nil) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: song.orders.count)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
        if let initial { context.channelStates = initial }
        for (index, row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index + 1 < traversal.rows.count ? traversal.rows[index + 1].row : nil, context: &context)
            states.append(context.channelStates)
        }
        return (context, states)
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, completed: Bool = false, split: Int? = nil) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: (0..<256).map { Float($0) / 4096 - 1 / 32 },
            volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: 0, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let alternate = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: sample.pcm.map { -$0 }, volume: 0.75,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(enabled: true, points: [.init(tick: 0, value: 64), .init(tick: 64, value: 32)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 256)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        let chunks = split.map { [Array(rows[..<$0]), Array(rows[$0...])] } ?? [rows]
        let patterns = chunks.enumerated().map { index, chunk in PlaybackPattern(index: index, rows: chunk.enumerated().map {
            PlaybackRow(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count)) }) }
        return .init(title: "Public R nibble memory", orders: patterns.map { .init(orderIndex: $0.index, patternIndex: $0.index) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { ($0.index, $0) }),
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: envelope, noteSampleMap: map),
                                 2: .init(index: 2, samples: [alternate], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: split == nil ? 0 : 1, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true)
    }
}
