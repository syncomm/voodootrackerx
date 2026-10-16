import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class RegularPortamentoMemoryAdmissionTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]
    private let paths: [(Bool, UInt8)] = [(true, 1), (true, 2), (false, 2)]

    func testSpeedOneNeitherSeedsNorReplacesDirectionalMemory() throws {
        for rate in rates {
            for (linear, effect) in paths {
                for prior in [false, true] {
                    let module = song([[c(prior ? effect : 0, prior ? 1 : 0, note: 49, instrument: 1)],
                        [c(effect, 4), c(15, 1)], [c(effect), c(15, 3)]], linear: linear)
                    let (context, states) = inspect(module, rate)
                    XCTAssertEqual(memory(states[1][0], effect)?.amount, prior ? 1 : nil)
                    let replay = try XCTUnwrap(context.portamentoSlideEffects.last)
                    XCTAssertEqual(replay.slideAmount, prior ? 1 : 0)
                    XCTAssertEqual(replay.effectMemoryMissing, !prior)
                    XCTAssertEqual(replay.effectMemoryReused, prior)
                    XCTAssertEqual(replay.stepUpdates.count, prior ? 2 : 0)
                    XCTAssertEqual(context.events.count, 1)
                }
            }
        }
    }

    func testEffectiveSpeedParameterMatrixAndEarlierLaterFxxPinMemoryPeriodsAndFrames() throws {
        // Pinned FT2 87be425: stores start at tick 1, using command-row Fxx speed.
        for rate in rates {
            for (linear, effect) in paths {
                for speed in [1, 2, 3, 6] {
                    for amount: UInt8 in [1, 4, 16, 127, 255] {
                        for channel in [0, 1] {
                            func lane(_ cell: PlaybackCell, speed: Int = 3) -> [PlaybackCell] {
                                var cells = [c(), c()]; cells[channel] = cell
                                cells[1-channel] = c(15, UInt8(speed)); return cells
                            }
                            let note: UInt8 = linear ? (effect == 1 ? 1 : 96) : 13
                            let relative = linear && effect == 2 ? 17 : 0
                            let module = song([lane(c(note: note, instrument: 1)), lane(c(effect, amount), speed: speed),
                                lane(c(effect))], linear: linear, relative: relative)
                            let (context, states) = inspect(module, rate)
                            XCTAssertEqual(memory(states[1][channel], effect)?.amount, speed > 1 ? Int(amount) : nil)
                            let seed = context.portamentoSlideEffects[0], replay = context.portamentoSlideEffects[1]
                            XCTAssertEqual(seed.rowSpeed, speed)
                            XCTAssertEqual(seed.stepUpdates.map(\.syntheticTick), Array(1..<speed))
                            if speed == 1 { XCTAssertEqual(seed.policy, "regular_portamento_no_nonzero_ticks_no_memory_admission") }
                            XCTAssertEqual(replay.slideAmount, speed > 1 ? Int(amount) : 0)
                            XCTAssertEqual(replay.memorySource?.source.rowIndex, speed > 1 ? 1 : nil)
                            let start = linear ? (effect == 1 ? 7680.0 : 512) : 54784
                            let delta = Double(amount) * (linear ? 4 : 16) * (effect == 1 ? -1 : 1)
                            let updates = seed.stepUpdates + replay.stepUpdates
                            XCTAssertEqual(updates.map(\.linearPeriodAfter), (1...max(1, updates.count)).prefix(updates.count).map { start + Double($0)*delta })
                            XCTAssertEqual(updates.map(\.scheduledFrame), ((1..<speed).map { 3+$0 } + (speed > 1 ? [4+speed, 5+speed] : [])).map { $0*Int(rate/50) })
                            XCTAssertFalse(seed.clamped || replay.clamped)
                            for update in updates {
                                let hz = linear ? 8363*pow(2, (4608-update.linearPeriodAfter)/768) : 8363*6848/update.linearPeriodAfter
                                XCTAssertEqual(update.playbackStepAfter, hz/rate, accuracy: 1e-12)
                            }
                        }
                    }
                }
            }
        }
    }

    func testColdReplayAndDirectionalIndependenceKeepExistingMissingHistoryPolicy() throws {
        for rate in rates {
            for linear in [true, false] {
                for effect: UInt8 in [1, 2] {
                    for speed in [1, 3, 6] {
                        let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [c(effect)], [c(effect)]], linear: linear, speed: speed), rate)
                        XCTAssertTrue(states.allSatisfy { memory($0[0], effect) == nil })
                        XCTAssertTrue(context.portamentoSlideEffects.allSatisfy { $0.status == .zeroParamEffectMemoryDeferred && $0.effectMemoryMissing && $0.stepUpdates.isEmpty })
                    }
                }
                let sequences: [[(UInt8, UInt8)]] = [[(1,4),(2,0)], [(2,4),(1,0)],
                    [(1,4),(2,4),(1,0)], [(2,4),(1,4),(2,0)], [(1,4),(2,16),(1,0)], [(2,16),(1,4),(2,0)]]
                for sequence in sequences {
                    let (context, states) = inspect(song([[c(note: 49, instrument: 1)]] + sequence.map { [c($0.0, $0.1)] }, linear: linear), rate)
                    let last = try XCTUnwrap(context.portamentoSlideEffects.last)
                    let expected = sequence.dropLast().last { $0.0 == sequence.last!.0 }?.1
                    XCTAssertEqual(last.slideAmount, Int(expected ?? 0))
                    XCTAssertEqual(last.effectMemoryMissing, expected == nil)
                    XCTAssertEqual(memory(states.last![0], 1)?.amount, sequence.last { $0.0 == 1 && $0.1 > 0 }.map { Int($0.1) })
                    XCTAssertEqual(memory(states.last![0], 2)?.amount, sequence.last { $0.0 == 2 && $0.1 > 0 }.map { Int($0.1) })
                }
                if !linear {
                    let (context, _) = inspect(song([[c(1, 4, note: 49, instrument: 1)]], linear: false), rate)
                    XCTAssertEqual(context.portamentoSlideEffects.first?.status, .unsupportedFrequencyTable)
                    XCTAssertTrue(context.portamentoSlideEffects.first?.stepUpdates.isEmpty == true)
                }
            }
        }
    }

    func testLifetimeAndSourceAbsenceDoNotResetOrGateExecutableMemory() throws {
        for rate in rates {
            for (linear, effect) in paths {
                for boundary in [c(note: 53, instrument: 1), c(note: 53), c(instrument: 1), c(note: 97), c(20), c(20, 1), c()] {
                    for completed in [false, true] {
                        let module = song([[c(effect, 4, note: 49, instrument: 1)], [boundary], [c(effect)]], linear: linear, completed: completed)
                        let (context, states) = inspect(module, rate)
                        XCTAssertTrue(states.allSatisfy { memory($0[0], effect)?.amount == 4 })
                        XCTAssertEqual(context.portamentoSlideEffects.last?.slideAmount, 4)
                        XCTAssertEqual(context.portamentoSlideEffects.last?.memorySource?.source.rowIndex, 0)
                    }
                }
                let loop = song([[c(effect, 4, note: 49, instrument: 1)], [c(effect), c(14, 0x60)], [c(), c(14, 0x61)], [c(effect)]], linear: linear)
                let (context, _) = inspect(loop, rate)
                XCTAssertEqual(context.portamentoSlideEffects.map(\.slideAmount), [4,4,4,4])
                let absent = song([[c(effect, 4)], [c(effect, note: 49, instrument: 1)]], linear: linear)
                XCTAssertEqual(inspect(absent, rate).0.portamentoSlideEffects.last?.slideAmount, 4)
                let order = song([[c(effect, 4, note: 49, instrument: 1)], [c(effect)]], linear: linear, splitOrders: true)
                XCTAssertEqual(inspect(order, rate).0.portamentoSlideEffects.last?.memorySource?.source.orderIndex, 0)
            }
        }
    }

    func testPublicFixtureWholeWindowAndRuntimeEventTargets() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/regular-portamento-memory-admission.xm")
        let parsed = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for linear in [true, false] {
            let module = PlaybackSong(title: parsed.title, orders: parsed.orders, patternsByIndex: parsed.patternsByIndex,
                instrumentsByIndex: parsed.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: parsed.initialTiming, usesLinearFrequencyTable: linear)
            for rate in rates {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                let renderer = PlaybackSongOfflineRenderer()
                let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
                let full = renderer.render(request)
                XCTAssertEqual(full.plan, runtime.plan)
                for rows in [1,2,5] { assertPCM(full.block.interleavedPCM, renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM) }
                let ds = full.diagnostics.portamentoSlideEffects
                XCTAssertTrue(ds.filter { $0.source.rowIndex == 1 }.allSatisfy { $0.effectMemoryMissing })
                XCTAssertTrue(ds.filter { $0.source.rowIndex == 4 && $0.channelIndex < 2 }.allSatisfy { $0.slideAmount == 1 && $0.effectMemoryReused })
                XCTAssertEqual(ds.first { $0.source.rowIndex == 8 && $0.channelIndex == 2 }?.slideAmount, 16)
                for d in ds {
                    for u in d.stepUpdates {
                        let event = try XCTUnwrap(runtime.events.first { $0.source == d.source && $0.channelIndex == d.channelIndex && $0.syntheticTick == u.syntheticTick && $0.categories.contains("step_update") && $0.categories.contains(d.direction == .up ? "portamento_1xx" : "portamento_2xx") })
                        XCTAssertEqual(event.scheduledFrame, u.scheduledFrame)
                        guard case let .stepUpdate(index, step) = event.action else { return XCTFail("Expected step update") }
                        XCTAssertEqual(index, d.activeEventIndex); XCTAssertEqual(step, u.playbackStepAfter)
                    }
                }
#if DEBUG
                let timing = PlaybackSongFxxTimingPlanner.plan(module, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
                let boundaries = [timing.frameFor(row: 1), timing.frameFor(row: 3), timing.frameFor(row: 4), timing.frameFor(row: 4, tick: 1), timing.frameFor(row: 5)]
                for offset in [-1,0,1] { assertPCM(full.block.interleavedPCM, renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries.map { $0+offset }).block.interleavedPCM) }
#endif
            }
        }
    }

    private func memory(_ state: Adapter.ChannelState, _ effect: UInt8) -> Adapter.PortamentoSlideMemory? {
        effect == 1 ? state.portamentoUpMemory : state.portamentoDownMemory
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }
    private func inspect(_ song: PlaybackSong, _ rate: Double) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: song.orders.count)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
        for (index, row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow), nextRow: index+1 < traversal.rows.count ? traversal.rows[index+1].row : nil, context: &context)
            states.append(context.channelStates)
        }
        return (context, states)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool, speed: Int = 3, relative: Int = 0, completed: Bool = false, splitOrders: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1/32, count: 256), volume: 0.5,
            relativeNote: relative, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let groups = splitOrders ? [Array(rows.prefix(1)), Array(rows.dropFirst())] : [rows]
        let patterns = Dictionary(uniqueKeysWithValues: groups.enumerated().map { i, group in (i, PlaybackPattern(index: i, rows: group.enumerated().map { r, cells in .init(index: r, cells: cells + Array(repeating: c(), count: 2-cells.count)) })) })
        return .init(title: "Public regular slide memory", orders: groups.indices.map { .init(orderIndex: $0, patternIndex: $0) }, patternsByIndex: patterns,
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear)
    }
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs,rhs).map { abs($0-$1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
}
