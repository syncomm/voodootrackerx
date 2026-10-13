import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class RxyNibbleMemoryTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testPublicCounterCarryFixtureUsesHonestRoutesAndWindowContinuationAtBothRates() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/rxy-counter-timing-carry.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: fixture.path), modulePath: fixture.path)
        for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, orderCount: 2,
                config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertTrue(full.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            let rxy = full.diagnostics.retriggerEffects.filter { $0.effectType == 27 }
            XCTAssertEqual(rxy.first?.volumeValuesAfter, [1, 2, 3, 4, 5, 6])
            XCTAssertEqual(rxy[1].status, .uninitializedRxyExcluded)
            XCTAssertTrue(rxy.contains { $0.invocations.contains(where: \.semanticOnlyVolumeChange) })
            XCTAssertTrue(rxy.contains { $0.invocations.first?.coalescedWithRowTrigger == true })
            XCTAssertTrue(full.plan.xmEmptyRoutes.contains { $0.sampleIndex == 1 })
            XCTAssertTrue(full.plan.xmEnvelopeTimeline?.updatesByEvent.values.joined().contains { !$0.state.keyOn } == true)
            for rows in [1, 2, 3, 5] {
                let window = renderer.renderWindowed(request, windowRows: rows)
                XCTAssertEqual(window.plan, full.plan)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }

    func testIndependentSeededReplayPreservesMemoryAndUnchangedArithmetic() {
        for rate in [44_100.0, 48_000] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)]] +
                [0x93, 0x00, 0x03, 0x90, 0x04, 0x20, 0x00].map { [c(27, UInt8($0))] }), rate)
            XCTAssertEqual(states.dropFirst().map { $0[0].rVolumeModeMemory }, [9, 9, 9, 9, 9, 2, 2])
            XCTAssertEqual(states.dropFirst().map { $0[0].rRetriggerSpeedMemory }, [3, 3, 3, 3, 4, 4, 4])
            XCTAssertEqual(context.retriggerEffects.map(\.retriggerTicks), [[2, 5], [2, 5], [2, 5], [2, 5], [3], [1, 5], [3]])
            XCTAssertEqual(context.retriggerEffects.map(\.volumeValuesAfter), [[33, 34], [35, 36], [37, 38], [39, 40], [41], [39, 37], [35]])
            XCTAssertEqual(context.retriggerEffects.map(\.intervalNibble), [3, 0, 3, 0, 4, 0, 0])
            let down = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x13)], [c(27)]]), rate).0
            XCTAssertEqual(down.retriggerEffects.map(\.volumeModeNibble), [1, 1])
            XCTAssertEqual(down.retriggerEffects.map(\.volumeValuesAfter), [[31, 30], [29, 28]])
        }
        XCTAssertEqual(Adapter.retriggerVolumeAdjustment(modeNibble: 6, currentVolume: 32).volumeAfter, 21) // G22 stays open.
        XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.size, 1152)
        XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.alignment, 8)
    }

    func testColdSequencesResolveLiteralBytesWithIndependentExecutionState() throws {
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
                        XCTAssertFalse(diagnostic.deferred)
                        XCTAssertEqual(diagnostic.invocations.count, 6)
                        XCTAssertTrue(diagnostic.invocations.allSatisfy { $0.fired && $0.counterAfter == 0 })
                        XCTAssertEqual(diagnostic.retriggerEventIndices.count, active ? 6 : 0)
                        XCTAssertEqual(diagnostic.volumeValuesAfter.count, active ? 6 : 0)
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
                    XCTAssertEqual(item["zero_interval_execution_deferred_to_g21"] as? Bool, false)
                }
            }
        }
        let cold = inspect(song([[c(27, 0x90)], [c(27)]])).1
        XCTAssertEqual(cold.map { $0[0].baseChannelVolume }, [64, 64]) // Only the fully uninitialized mutation is excluded.
        let carried = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x90)], [c(27)]])).1
        XCTAssertEqual(carried.map { $0[0].baseChannelVolume }, [32, 38, 44])
        XCTAssertEqual(carried.map { $0[0].activeEventIndex }, [0, 6, 12])
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
            XCTAssertFalse(context.retriggerEffects[0].deferred)
        }
        let gated = inspect(song([[c(27, 0x93, note: 49, instrument: 1, volume: 0xF1)], [c(27)]]))
        XCTAssertEqual(gated.1[0][0].rVolumeModeMemory, 9)
        XCTAssertTrue(gated.0.retriggerEffects.first?.invocations.first?.gated == true)
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

    func testE9IndependenceSpeedAndFxxPreserveNibbleMemory() {
        for e9: UInt8 in [0x90, 0x93] {
            let cold = inspect(song([[c(note: 49, instrument: 1)], [c(14, e9)], [c(27)]]))
            XCTAssertEqual(cold.1.last?[0].rRetriggerSpeedMemory, 0)
            XCTAssertEqual(cold.1.last?[0].rVolumeModeMemory, 0)
            let seeded = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [c(14, e9)], [c(27)]]))
            XCTAssertEqual(seeded.0.retriggerEffects[1].retriggerTicks, e9 == 0x90 ? [0] : [3])
            XCTAssertEqual(seeded.0.retriggerEffects.last?.retriggerTicks, e9 == 0x90 ? [1, 5] : [3])
        }
        for speed in [1, 2, 3, 6] {
            let plan = Adapter.adapt(song([[c(note: 49, instrument: 1)], [c(27, 0x93)], [c(27)]], speed: speed), orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(plan.diagnostics.retriggerEffects.map(\.retriggerTicks),
                [1: [[], []], 2: [[], [0]], 3: [[2], [2]], 6: [[2, 5], [2, 5]]][speed])
            XCTAssertTrue(plan.diagnostics.retriggerEffects.allSatisfy { $0.retriggerIntervalTicks == 3 })
            for writer in [0, 1] {
                var row = [c(27), c(27)]; row[writer] = c(15, UInt8(speed))
                let (context, states) = inspect(song([[c(note: 49, instrument: 1), c(note: 49, instrument: 1)], [c(27, 0x93), c(27, 0x93)], row]))
                XCTAssertEqual(states.last?[1 - writer].rRetriggerSpeedMemory, 3)
                XCTAssertEqual(context.retriggerEffects.last?.retriggerTicks, [1: [], 2: [], 3: [2], 6: [2, 5]][speed])
            }
        }
    }

    func testNonzeroE9CounterResetDoesNotRequireAnAudioSource() {
        for rate in [44_100.0, 48_000] {
            for prefix in [c(), c(instrument: 1), c(note: 50, instrument: 1)] {
                for parameter: UInt8 in [0x90, 0x91, 0x93, 0x95, 0x97] {
                    let (context, states) = inspect(song([[prefix], [c(27, 0x94)], [c(14, parameter)], [c(27)]]), rate)
                    let resets = parameter != 0x90 && parameter < 0x96
                    XCTAssertEqual(states[1][0].rRetriggerCounter, 2)
                    XCTAssertNil(states[2][0].activeEventIndex)
                    XCTAssertEqual(states[2][0].rRetriggerCounter, resets ? 0 : 2)
                    XCTAssertEqual(context.retriggerEffects.last?.invocations.filter(\.fired).map(\.tick), resets ? [3] : [1, 5])
                    XCTAssertEqual(states.last?[0].rVolumeModeMemory, 9)
                    XCTAssertEqual(states.last?[0].rRetriggerSpeedMemory, 4)
                }
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

    func testPersistentCounterMatchesPinnedSpeedAndReplayGrid() {
        let expected: [Int: [[Int]]] = [1: [[], [], [0], []], 2: [[], [0], [1], []],
            3: [[2], [2], [2], [2]], 6: [[2, 5], [2, 5], [2, 5], [2, 5]]]
        for rate in [44_100.0, 48_000] {
            for speed in [1, 2, 3, 6] {
                for replay: UInt8 in [0, 3, 0x90] {
                    let module = song([[c(note: 49, instrument: 1)], [c(27, 0x93)]] +
                        Array(repeating: [c(27, replay)], count: 3), speed: speed)
                    let diagnostics = inspect(module, rate).0.retriggerEffects
                    XCTAssertEqual(diagnostics.map(\.retriggerTicks), expected[speed])
                    XCTAssertTrue(diagnostics.allSatisfy { $0.invocations.count == speed })
                }
                for command: UInt8 in [0, 0x90] {
                    let context = inspect(song([[c(note: 49, instrument: 1)], [c(27, command)]], speed: speed), rate).0
                    XCTAssertEqual(context.retriggerEffects[0].retriggerTicks, Array(0..<speed))
                    XCTAssertTrue(context.retriggerEffects[0].invocations.allSatisfy { $0.fired && $0.counterAfter == 0 })
                    XCTAssertEqual(context.events.last?.gain, Float(command == 0 ? 32 : 32 + speed) / 64)
                }
            }
        }
    }

    func testCounterResetBoundariesAreIndependentOfNibbleMemory() {
        let transitions: [(PlaybackCell, [Int])] = [(c(), [1, 5]), (c(note: 53), [1, 5]),
            (c(note: 53, instrument: 2), [3]), (c(instrument: 2), [3]),
            (c(14, 0x90), [1, 5]), (c(14, 0x93), [3]), (c(20), [1, 5]), (c(note: 97), [1, 5])]
        for (transition, expected) in transitions {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [transition], [c(27)]]))
            XCTAssertEqual(states[1][0].rRetriggerCounter, 2)
            XCTAssertEqual(context.retriggerEffects.last?.retriggerTicks, expected)
            XCTAssertEqual(states.last?[0].rRetriggerSpeedMemory, 4)
            XCTAssertEqual(states.last?[0].rVolumeModeMemory, 9)
        }
        let orders = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [c()], [c(27)]], split: 3)).0
        XCTAssertEqual(orders.retriggerEffects.map(\.retriggerTicks), [[3], [1, 5]])
        let loop = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [c(14, 0x60)], [c(27)], [c(14, 0x61)]])).0
        XCTAssertEqual(loop.retriggerEffects.map(\.retriggerTicks), [[3], [1, 5], [3]])
    }

    func testVolumeColumnGateAndInterleavedWritersMatchReference() {
        let ungated: Set<UInt8> = [0, 0x10, 0xA0, 0xC0]
        for raw: UInt8 in [0, 0x10, 0x11, 0x20, 0x50, 0x60, 0x61, 0x70, 0x71, 0x80, 0x81, 0x8F,
                          0x90, 0x91, 0x9F, 0xA0, 0xA1, 0xB0, 0xB1, 0xC0, 0xC3, 0xCF, 0xD0, 0xD1, 0xE0, 0xE1, 0xF0, 0xF1] {
            let context = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [c(27, volume: raw)]])).0
            let diagnostic = context.retriggerEffects[1]
            XCTAssertEqual(diagnostic.invocations.first?.gated, !ungated.contains(raw), String(raw, radix: 16))
            XCTAssertEqual(diagnostic.retriggerTicks, ungated.contains(raw) ? [1, 5] : [2])
            XCTAssertEqual(diagnostic.volumeModeNibble, 9)
            XCTAssertEqual(diagnostic.retriggerIntervalTicks, 4)
        }
        let slide = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x90, volume: 0x61)]])).0
        XCTAssertEqual(slide.retriggerEffects[0].volumeValuesBefore, [31, 31, 31, 31, 31])
        XCTAssertEqual(slide.retriggerEffects[0].volumeValuesAfter, [32, 32, 32, 32, 32])
        let set = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x90, volume: 0x20)]])).0
        XCTAssertEqual(set.retriggerEffects[0].volumeValuesAfter, [16, 16, 16, 16, 16])
        let pan = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [c(27, volume: 0xD1)]]))
        XCTAssertEqual(pan.1.last?[0].panningValue, 123)
    }

    func testSameCellOrderingCoalescesOnlyPendingOrdinarySource() throws {
        for (shape, ticks) in [(c(27, note: 53), [1, 5]), (c(27, note: 53, instrument: 2), [3]), (c(27, instrument: 2), [3])] {
            let context = inspect(song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [shape]])).0
            XCTAssertEqual(context.retriggerEffects.last?.retriggerTicks, ticks)
        }
        for shape in [c(27, 0x90, note: 53), c(27, 0x90, note: 53, instrument: 2), c(27, 0x90, instrument: 1)] {
            let module = song([[c(note: 49, instrument: 1)], [shape]])
            let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
            let diagnostic = plan.diagnostics.retriggerEffects[0]
            XCTAssertEqual(plan.pattern.events.count, 7)
            XCTAssertEqual(diagnostic.retriggerTicks, [0, 1, 2, 3, 4, 5])
            XCTAssertEqual(diagnostic.invocations.first?.coalescedWithRowTrigger, shape.note != 0)
            XCTAssertTrue(plan.pattern.events.allSatisfy { $0.initialSourceFrame == 0 })
            let first = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first)
            XCTAssertEqual(first.state.volumeTick, shape.instrument == 0 ? 6 : 0)
        }
        let offset = inspect(song([[c(9, 1, note: 49, instrument: 1)], [c(27, 0x93)], [c(9, note: 49)]], sampleFrames: 512))
        XCTAssertEqual(offset.0.events.map(\.initialSourceFrame), [256, 0, 0, 256])
        XCTAssertEqual(offset.1.last?[0].sampleOffsetMemory?.offsetFrames, 256)
    }

    func testReleasedAndCompletedSourcesRestartWithSemanticCarry() throws {
        for rate in [44_100.0, 48_000] {
            for completed in [false, true] {
                for release in [c(20), c(note: 97)] {
                    let module = song([[c(note: 49, instrument: 1)], [c(27, 0x94)], [release], [c(27)]], completed: completed)
                    let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                    XCTAssertEqual(plan.diagnostics.retriggerEffects.map(\.retriggerTicks), [[3], [1, 5]])
                    let states = try [1, 2, 3].map { try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[$0]?.first?.state) }
                    XCTAssertEqual(states.map(\.volumeTick), [9, 19, 23])
                    XCTAssertEqual(states.map(\.keyOn), [true, false, false])
                    XCTAssertEqual(states.map(\.fadeoutAccumulator), [32_768, 30_720, 29_696])
                    XCTAssertTrue(plan.pattern.events.allSatisfy { $0.initialSourceFrame == 0 })
                    XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed && $0.sampleIndex == 0 })
                }
            }
        }
    }

    func testSourceLessInitializedVolumeSurvivesAndExclusionIsNarrow() {
        for speed in [1, 2, 3, 6] {
            let initialized = song([[c(instrument: 1)], [c(27, 0x90)], [c(note: 49)]], speed: speed)
            let (context, states) = inspect(initialized)
            XCTAssertEqual(states.map { $0[0].baseChannelVolume }, [0, speed, speed])
            XCTAssertEqual(context.events.count, 1)
            XCTAssertEqual(context.events[0].gain, Float(speed) / 64)
            XCTAssertTrue(context.retriggerEffects[0].invocations.allSatisfy {
                $0.arithmeticApplied && $0.semanticOnlyVolumeChange && !$0.restartApplied && !$0.uninitializedMutationExcluded
            })
            let bare = song([[c(27, 0x90)], [c(note: 49, instrument: 1)]], speed: speed)
            let blank = song([[c()], [c(note: 49, instrument: 1)]], speed: speed)
            let excluded = inspect(bare).0
            XCTAssertTrue(excluded.retriggerEffects[0].invocations.allSatisfy { $0.uninitializedMutationExcluded && !$0.arithmeticApplied })
            let renderer = PlaybackSongOfflineRenderer()
            XCTAssertEqual(renderer.render(.init(song: bare, rows: 2)).block.interleavedPCM,
                           renderer.render(.init(song: blank, rows: 2)).block.interleavedPCM)
        }
        // An exact empty route is initialized even though it has no represented source.
        let (empty, states) = inspect(song([[c(note: 49, instrument: 1)], [c(note: 50)], [c(27, 0x90)], [c(note: 49)]]))
        XCTAssertEqual(states[2][0].baseChannelVolume, 38)
        XCTAssertTrue(empty.retriggerEffects[0].invocations.allSatisfy { $0.arithmeticApplied && !$0.restartApplied && !$0.uninitializedMutationExcluded })
        XCTAssertEqual(empty.events.last?.gain, 38 / 64)
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
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, completed: Bool = false, split: Int? = nil, sampleFrames: Int = 256) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: (0..<sampleFrames).map { Float($0) / 4096 - 1 / 32 },
            volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: completed ? 0 : sampleFrames, loopType: completed ? 0 : 1)
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
