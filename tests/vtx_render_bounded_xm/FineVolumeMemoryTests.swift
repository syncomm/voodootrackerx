import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class FineVolumeMemoryTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testDirectionalReplayAndChannelLocalProvenance() {
        for (parameters, expected): ([UInt8], [Int]) in [
            ([0xA1, 0xA0], [32, 33, 34]), ([0xB1, 0xB0], [32, 31, 30]),
            ([0xA3, 0xB4, 0xA0, 0xB0], [32, 35, 31, 34, 30])
        ] {
            let rows = [[c(note: 49, instrument: 1), c(note: 49, instrument: 1)]] +
                parameters.map { [c(14, $0), c(14, $0 & 0xF0)] }
            let (context, states) = inspect(song(rows))
            XCTAssertEqual(states.map { $0[0].baseChannelVolume }, expected)
            XCTAssertEqual(states.map { $0[1].baseChannelVolume }, Array(repeating: 32, count: rows.count))
            XCTAssertTrue(states.allSatisfy { $0[1].fineVolumeUpMemory == nil && $0[1].fineVolumeDownMemory == nil })
            for update in fine(context).filter({ $0.channelIndex == 0 && $0.effectParam! & 15 == 0 }) {
                XCTAssertTrue(update.effectMemoryReused)
                XCTAssertEqual(update.memorySource?.channelIndex, 0)
                XCTAssertEqual(update.memorySource?.source.rowIndex, update.effectParam == 0xA0 ? 1 : parameters.count == 2 ? 1 : 2)
            }
            XCTAssertNil(Adapter.ChannelState().fineVolumeUpMemory)
            XCTAssertNil(Adapter.ChannelState().fineVolumeDownMemory)
        }
    }

    func testTickZeroOnceAtAllSpeedsAndEarlierLaterSameRowFxx() {
        for rate in [44_100.0, 48_000] {
            for linear in [false, true] {
                for speed in [1, 3, 6] {
                    for (seed, zero, levels): (UInt8, UInt8, [Int]) in [(0xA3, 0xA0, [32, 35, 38]), (0xB4, 0xB0, [32, 28, 24])] {
                        for fxxChannel in [-1, 0, 1] {
                            let channel = fxxChannel == 0 ? 1 : 0
                            var rows = Array(repeating: [c(), c()], count: 3)
                            rows[0][channel] = c(note: 49, instrument: 1)
                            rows[1][channel] = c(14, seed); rows[2][channel] = c(14, zero)
                            if fxxChannel >= 0 { rows[1][fxxChannel] = c(15, UInt8(speed)) }
                            let module = song(rows, speed: fxxChannel < 0 ? speed : 6, linear: linear)
                            let (context, states) = inspect(module, rate)
                            let updates = fine(context)
                            XCTAssertEqual(updates.map(\.syntheticTick), [0, 0])
                            XCTAssertEqual(updates.map(\.scheduledFrame), [fxxChannel < 0 ? speed : 6, (fxxChannel < 0 ? speed : 6) + speed].map { $0 * Int(rate / 50) })
                            XCTAssertEqual(states.map { $0[channel].baseChannelVolume }, levels)
                            XCTAssertTrue(updates.allSatisfy(\.applied))
                        }
                    }
                }
            }
        }
    }

    func testSameRowBPMChangesKeepBothDirectionalOperationsAtTickZero() {
        for rate in [44_100.0, 48_000] {
            for (seed, zero, levels): (UInt8, UInt8, [Int]) in [(0xA3, 0xA0, [32, 35, 38]), (0xB4, 0xB0, [32, 28, 24])] {
                for channel in [0, 1] {
                    var rows = Array(repeating: [c(), c()], count: 3)
                    rows[0][channel] = c(note: 49, instrument: 1)
                    rows[1][channel] = c(14, seed); rows[1][1 - channel] = c(15, 250)
                    rows[2][channel] = c(14, zero)
                    let (context, states) = inspect(song(rows), rate)
                    XCTAssertEqual(fine(context).map(\.syntheticTick), [0, 0])
                    XCTAssertEqual(fine(context).map(\.scheduledFrame), [6, 9].map { $0 * Int(rate / 50) })
                    XCTAssertEqual(states.map { $0[channel].baseChannelVolume }, levels)
                }
            }
        }
    }

    func testColdCurrentTargetsDeduplicateAndStaleGlobalTargetsRepairWithoutMemory() throws {
        for base in [0, 32, 64] {
            for zero: UInt8 in [0xA0, 0xB0] {
                var state = Adapter.ChannelState()
                state.baseChannelVolume = base; state.outputChannelVolume = 63
                let update = Adapter.applyEffectColumnState(from: c(14, zero), source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
                    channelIndex: 0, syntheticRow: 0, scheduledFrame: 0, rowSpeed: 1, channelState: &state, globalVolumeValue: 64)
                XCTAssertEqual(state.baseChannelVolume, base); XCTAssertEqual(state.outputChannelVolume, base)
                XCTAssertEqual(update?.applied, true); XCTAssertEqual(update?.activeVoiceUpdated, false)
                XCTAssertNil(state.fineVolumeUpMemory); XCTAssertNil(state.fineVolumeDownMemory)
            }
        }
        for rate in [44_100.0, 48_000] {
            for zero: UInt8 in [0xA0, 0xB0] {
                for base in [0, 32, 64] {
                    for stale in [false, true] {
                        let module = song([[c(note: 49, instrument: 1)], [c(), stale ? c(16, 16) : c()],
                                           [c(14, zero)], [c(14, zero)]], base: base)
                        let (context, states) = inspect(module, rate)
                        XCTAssertTrue(states.allSatisfy { $0[0].baseChannelVolume == base && $0[0].outputChannelVolume == base })
                        XCTAssertTrue(states.allSatisfy { $0[0].fineVolumeUpMemory == nil && $0[0].fineVolumeDownMemory == nil })
                        XCTAssertTrue(fine(context).allSatisfy { $0.applied && $0.effectMemoryMissing && !$0.effectMemoryReused && !$0.effectMemoryDeferred && $0.memorySource == nil })
                        let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                        let repairs = gains(runtime, row: 2)
                        XCTAssertEqual(repairs.count, stale && base > 0 ? 1 : 0)
                        XCTAssertTrue(gains(runtime, row: 3).isEmpty)
                        if let event = repairs.first, case let .gainPanUpdate(index, gain, _) = event.action {
                            XCTAssertEqual(index, 0); XCTAssertEqual(event.syntheticTick, 0)
                            XCTAssertEqual(gain, Float(base) / 256)
                            XCTAssertEqual(event.scheduledFrame, 12 * Int(rate / 50))
                        }
                    }
                }
            }
        }
    }

    func testClampsStillPublishAgainstHeldTarget() {
        for (base, seed, zero, expected): (Int, UInt8, UInt8, Int) in [
            (63, 0xA1, 0xA0, 64), (64, 0xA1, 0xA0, 64), (1, 0xB1, 0xB0, 0), (0, 0xB1, 0xB0, 0)
        ] {
            let module = song([[c(note: 49, instrument: 1)], [c(14, seed)], [c(), c(16, 16)], [c(14, zero)], [c(14, zero)]], base: base)
            let (context, states) = inspect(module)
            XCTAssertEqual(states.dropFirst().map { $0[0].baseChannelVolume }, Array(repeating: expected, count: 4))
            XCTAssertTrue(fine(context).allSatisfy(\.applied))
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48000)
            XCTAssertEqual(gains(runtime, row: 1).count, base == expected ? 0 : 1)
            XCTAssertEqual(gains(runtime, row: 3).count, expected > 0 ? 1 : 0)
            XCTAssertTrue(gains(runtime, row: 4).isEmpty)
        }
    }

    func testColdTremoloRestorationKeepsPhaseControlAndLaterContinuation() {
        for rate in [44_100.0, 48_000] {
            for zero: UInt8 in [0xA0, 0xB0] {
                for control: UInt8 in [0, 6] {
                    let (context, states) = inspect(song([[c(14, 0x70 | control, note: 49, instrument: 1)],
                        [c(7, 0x48)], [c(14, zero)], [c(7)], [c(14, zero)]]), rate)
                    XCTAssertEqual(states[1][0].outputChannelVolume, 63)
                    XCTAssertEqual(states[2][0].outputChannelVolume, 32)
                    XCTAssertEqual(states[2][0].tremolo, states[1][0].tremolo)
                    XCTAssertEqual(states[2][0].tremolo.phase, 80)
                    XCTAssertEqual(states[2][0].tremolo.control, Int(control))
                    XCTAssertEqual(states[3][0].tremolo.phase, 160)
                    XCTAssertEqual(states[4][0].tremolo, states[3][0].tremolo)
                    XCTAssertTrue(fine(context).allSatisfy { $0.memorySource == nil && !$0.effectMemoryReused })
                    if control == 0 {
                        XCTAssertEqual(context.voiceStateUpdates.filter { $0.effectType == 7 && $0.syntheticRow == 3 }.map(\.effectiveVolumeAfter), [61, 54, 44, 32, 20])
                    }
                }
            }
        }
    }

    func testOtherMemoryFamiliesAndVolumeColumnFineSlidesStayIndependent() {
        for other in [c(10, 1), c(5, 2), c(6, 3), c(volume: 0x82), c(volume: 0x93),
                      c(14, 0x11), c(14, 0x22), c(33, 0x13), c(33, 0x24)] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [c(14, 0xA3)],
                [c(14, 0xB4)], [other], [c(14, 0xA0, volume: 0x81)], [c(14, 0xB0, volume: 0x92)]]))
            XCTAssertEqual(states[4][0].baseChannelVolume, min(64, max(0, states[3][0].baseChannelVolume - 1) + 3))
            XCTAssertEqual(states[5][0].baseChannelVolume, max(0, min(64, states[4][0].baseChannelVolume + 2) - 4))
            for state in states.dropFirst(3).map({ $0[0] }) {
                XCTAssertEqual(state.fineVolumeUpMemory?.amount, 3)
                XCTAssertEqual(state.fineVolumeDownMemory?.amount, 4)
                XCTAssertEqual(state.fineVolumeUpMemory?.source.source.rowIndex, 1)
                XCTAssertEqual(state.fineVolumeDownMemory?.source.source.rowIndex, 2)
            }
            XCTAssertEqual(states[5][0].volumeSlideMemory, states[3][0].volumeSlideMemory)
            XCTAssertEqual(fine(context).suffix(2).map { $0.memorySource?.effectParam }, [0xA3, 0xB4])
            let (_, coldStates) = inspect(song([[c(note: 49, instrument: 1)], [other], [c(14, 0xA0)], [c(14, 0xB0)]]))
            XCTAssertTrue(coldStates.allSatisfy { $0[0].fineVolumeUpMemory == nil && $0[0].fineVolumeDownMemory == nil })
        }
    }

    func testMemoryLifetimeSameCellDefaultsAndFreshPlannerReset() {
        for linear in [false, true] {
            for (seed, zero): (UInt8, UInt8) in [(0xA3, 0xA0), (0xB4, 0xB0)] {
                for seeded in [false, true] {
                    for boundary in [c(note: 51, instrument: 2), c(note: 51), c(instrument: 2), c(note: 97), c()] {
                        func module(_ parameter: UInt8) -> PlaybackSong {
                            song([[c(note: 49, instrument: 1)], [seeded ? c(14, seed) : c()],
                                [c(14, parameter, note: boundary.note, instrument: boundary.instrument)], [], [c(14, zero)]], linear: linear, split: 2)
                        }
                        let (context, states) = inspect(module(zero))
                        let (_, explicit) = inspect(module(seeded ? seed : zero))
                        XCTAssertEqual(states[2][0].baseChannelVolume, explicit[2][0].baseChannelVolume)
                        XCTAssertEqual(states[2][0].fineVolumeUpMemory, states[1][0].fineVolumeUpMemory)
                        XCTAssertEqual(states[2][0].fineVolumeDownMemory, states[1][0].fineVolumeDownMemory)
                        XCTAssertEqual(context.events.map(\.gain), inspect(module(seeded ? seed : zero)).0.events.map(\.gain))
                        for state in states.dropFirst(2) {
                            XCTAssertEqual(state[0].fineVolumeUpMemory, states[1][0].fineVolumeUpMemory)
                            XCTAssertEqual(state[0].fineVolumeDownMemory, states[1][0].fineVolumeDownMemory)
                        }
                        let update = fine(context).first { $0.syntheticRow == 2 }!
                        XCTAssertEqual(update.syntheticRow, 2); XCTAssertEqual(update.source.orderIndex, 1)
                        XCTAssertEqual(update.effectMemoryReused, seeded)
                        XCTAssertEqual(context.events.count, (1...96).contains(boundary.note) ? 2 : 1)
                    }
                }
                let fresh = inspect(song([[c(14, zero, note: 49, instrument: 1)]])).1[0][0]
                XCTAssertEqual(fresh.baseChannelVolume, 32)
                XCTAssertNil(fresh.fineVolumeUpMemory); XCTAssertNil(fresh.fineVolumeDownMemory)
            }
        }
    }

    func testSourceLessCompletedAndCanonicalEmptyRoutesNeverResurrectAndLaterNotesInherit() {
        for rate in [44_100.0, 48_000] {
            for route in 0...2 {
                for (seed, zero, inherited): (UInt8, UInt8, Int) in [(0xA3, 0xA0, 6), (0xB4, 0xB0, 0)] {
                    for seeded in [false, true] {
                        let module = song([[route == 0 ? c() : c(note: route == 1 ? 49 : 50, instrument: 1)],
                            [c(14, seeded ? seed : zero)], [c(14, zero)], [c(note: 49, instrument: route == 0 ? 1 : 0)]],
                            completed: route == 1, canonicalEmpty: true)
                        let (context, states) = inspect(module, rate)
                        XCTAssertEqual(context.events.count, route == 1 ? 2 : 1)
                        XCTAssertEqual(states[2][0].fineVolumeUpMemory != nil || states[2][0].fineVolumeDownMemory != nil, seeded)
                        if route == 2 { XCTAssertEqual(states[2][0].baseChannelVolume, seeded ? inherited : 0) }
                        let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 1), rows: 4)
                        let rendered = PlaybackSongOfflineRenderer().render(request)
                        let rowFrames = 6 * Int(rate / 50)
                        XCTAssertTrue(rendered.block.interleavedPCM[rowFrames..<(3 * rowFrames)].allSatisfy { $0 == 0 })
                        let expected = route == 0 ? 32 : states[2][0].baseChannelVolume
                        XCTAssertEqual(context.events.last?.gain, Float(expected) / 64)
                        XCTAssertEqual(rendered.block.interleavedPCM[3 * rowFrames + 100], Float(expected) / 2048, accuracy: 1e-7)
                        if route != 1 { XCTAssertTrue(gains(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate), row: 2).isEmpty) }
                    }
                }
            }
        }
    }

    func testEnvelopeFadeoutCompositionAndProtectedColdPolicies() {
        for rate in [44_100.0, 48_000] {
            for zero: UInt8 in [0xA0, 0xB0] {
                func render(_ effect: UInt8, _ parameter: UInt8) -> PlaybackSongOfflineRenderResult {
                    let module = song([[c(note: 49, instrument: 1), c(16, 16)], [c(7, 0x48)],
                        [c(14, zero, note: 97)], [c(effect, parameter)]], envelope: true)
                    return PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 4))
                }
                let fine = render(14, zero), set = render(12, 32)
                XCTAssertEqual(fine.plan.xmEnvelopeTimeline, set.plan.xmEnvelopeTimeline)
                // Cxx uses the existing quick ramp; fine writes retain ordinary tick ramps.
                XCTAssertEqual(fine.plan.xmAudibleTimeline?.updates.map(\.amplitude), set.plan.xmAudibleTimeline?.updates.map(\.amplitude))
                assertPCM(fine.block.interleavedPCM, render(14, zero == 0xA0 ? 0xB0 : 0xA0).block.interleavedPCM)
                for target in fine.plan.xmAudibleTimeline?.updates.filter({ $0.source.rowIndex >= 2 }) ?? [] {
                    let semantic = fine.plan.xmEnvelopeTimeline!.updatesByEvent[target.eventIndex]!.first { $0.scheduledFrame == target.scheduledFrame }!
                    XCTAssertEqual(target.amplitude, 0.125 * semantic.state.volumeValue * semantic.state.fadeoutValue)
                }
                for family: UInt8 in [10, 5, 6, 17] {
                    let (_, states) = inspect(song([[c(note: 49, instrument: 1)], [c(7, 0x48)], [c(family)]]), rate)
                    XCTAssertEqual(states[2][0].outputChannelVolume, family == 17 ? 63 : 32)
                    XCTAssertNil(states[2][0].volumeSlideMemory); XCTAssertNil(states[2][0].globalVolumeSlideMemory)
                }
            }
        }
    }

    func testPublicFixtureDiagnosticsAndWholeWindowRuntimePlanParity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/fine-volume-directional-memory.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, orderCount: 2, config: .init(sampleRate: rate, channelCount: 2), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let full = PlaybackSongOfflineRenderer().render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertTrue(full.diagnostics.effectCommandDiagnostics.filter { $0.effectType == 14 && [0xA, 0xB].contains($0.effectParam >> 4) }.allSatisfy { $0.status == .applied })
            for window in [1, 3, 12] { assertPCM(full.block.interleavedPCM, PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: window).block.interleavedPCM) }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let updates = try XCTUnwrap(json["volume_panning_state_updates"] as? [[String: Any]])
            let cold = updates.filter { $0["effect_type"] as? Int == 14 && $0["fine_amount"] as? Int == 0 }
            XCTAssertFalse(cold.isEmpty)
            XCTAssertTrue(cold.allSatisfy { $0["applied"] as? Bool == true && $0["effect_memory_reused"] as? Bool == false && $0["memory_source"] is NSNull })
            XCTAssertTrue(updates.contains { $0["fine_amount_nibble"] as? Int == 0 && $0["fine_amount"] as? Int == 3 && $0["effect_memory_reused"] as? Bool == true })
        }
    }

    private func fine(_ context: Adapter.AdapterRowContext) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        context.voiceStateUpdates.filter { if case .eaxFineVolumeSlideUp = $0.command { return true }; if case .ebxFineVolumeSlideDown = $0.command { return true }; return false }
    }
    private func gains(_ runtime: RuntimeCMixerAdapterEventPlan, row: Int) -> [RuntimeCMixerAdapterEvent] {
        runtime.events.filter { if case .gainPanUpdate = $0.action { return $0.source.rowIndex == row }; return false }
    }
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func inspect(_ song: PlaybackSong, _ rate: Double = 48000) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: song.orders.count)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
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
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, base: Int = 32, linear: Bool = true, envelope: Bool = false, completed: Bool = false, canonicalEmpty: Bool = false, split: Int? = nil) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1 / 32, count: completed ? 32 : 256),
            volume: Float(base) / 64, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: 0, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let alternate = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: sample.pcm, volume: 0.75,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: sample.pcm.count, loopType: 1)
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 32), .init(tick: 64, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 1024 : 0)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        let chunks = split.map { [Array(rows[..<$0]), Array(rows[$0...])] } ?? [rows]
        let patterns = chunks.enumerated().map { index, chunk in
            PlaybackPattern(index: index, rows: chunk.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count)) })
        }
        return .init(title: "Public fine volume memory", orders: patterns.map { .init(orderIndex: $0.index, patternIndex: $0.index) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { ($0.index, $0) }),
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map),
                                 2: .init(index: 2, samples: [alternate], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: canonicalEmpty, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }
}
