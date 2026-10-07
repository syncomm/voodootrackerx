import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class Cold500Tests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private var toneStates: [PlaybackCell] { [c(), c(3, 1, note: 53), c(3, note: 53), c(3, 1)] }

    func testIndependentHalvesAtNativeAndEarlierLaterFxxSpeeds() throws {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for fxxChannel in [-1, 0, 1] {
                    for (state, preparation) in toneStates.enumerated() {
                        let channel = fxxChannel == 0 ? 1 : 0
                        func lane(_ cell: PlaybackCell, fxx: Bool = false) -> [PlaybackCell] {
                            var cells = [c(), c()]; cells[channel] = cell
                            if fxx { cells[fxxChannel] = c(15, UInt8(speed)) }; return cells
                        }
                        func module(_ effect: UInt8) -> PlaybackSong {
                            song([lane(c(note: 49, instrument: 1)), lane(preparation), lane(c(7, 0x48)),
                                  lane(c(effect), fxx: fxxChannel >= 0)], speed: fxxChannel < 0 ? speed : 6)
                        }
                        let combined = module(5), pure = module(3)
                        let (context, states) = inspect(combined, rate)
                        let updates = context.voiceStateUpdates.filter { $0.effectType == 5 && $0.applied }
                        XCTAssertEqual(updates.map(\.syntheticTick), Array(1..<speed))
                        XCTAssertTrue(updates.allSatisfy { $0.effectiveVolumeAfter == 32 && !$0.effectMemoryReused && !$0.effectMemoryMissing && !$0.effectMemoryDeferred && $0.memorySource == nil })
                        XCTAssertTrue(states.allSatisfy { $0[channel].volumeSlideMemory == nil })
                        XCTAssertEqual(states[3][channel].baseChannelVolume, 32)
                        XCTAssertEqual(states[3][channel].outputChannelVolume, speed > 1 ? 32 : states[2][channel].outputChannelVolume)
                        XCTAssertEqual(states[3][channel].tremolo, states[2][channel].tremolo)
                        XCTAssertEqual(states[3][channel].tonePortamentoTargetNote, states[2][channel].tonePortamentoTargetNote)
                        XCTAssertEqual(states[3][channel].tonePortamentoSpeed, states[2][channel].tonePortamentoSpeed)
                        let tones = context.tonePortamentoEffects.filter { $0.syntheticRow == 3 }
                        XCTAssertEqual(tones.flatMap(\.stepUpdates).count, state == 1 ? speed - 1 : 0)
                        XCTAssertEqual(tones.flatMap(\.stepUpdates), inspect(pure, rate).0.tonePortamentoEffects.filter { $0.syntheticRow == 3 }.flatMap(\.stepUpdates))
                        XCTAssertEqual(context.events.count, 1)
                        let gains = gainEvents(RuntimeCMixerAdapterEventPlan.make(song: combined, sampleRate: rate), row: 3)
                        XCTAssertEqual(gains.count, speed > 1 ? 1 : 0)
                        if let event = gains.first {
                            XCTAssertEqual(event.syntheticTick, 1)
                            XCTAssertEqual(event.scheduledFrame, ((fxxChannel < 0 ? speed * 3 : 18) + 1) * Int(rate / 50))
                        }
                    }
                }
            }
        }
    }

    func testHeldSourceTargetRefreshAndTremoloContinuationInEveryToneState() throws {
        for rate in [44_100.0, 48_000] {
            for preparation in toneStates {
                let held = song([[c(note: 49, instrument: 1)], [preparation], [c(), c(16, 16)], [c(5)], [c(5)]], base: 64)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: held, sampleRate: rate)
                let event = try XCTUnwrap(gainEvents(runtime, row: 3).first)
                XCTAssertEqual(event.activeEventIndex, 0); XCTAssertEqual(event.syntheticTick, 1)
                if case let .gainPanUpdate(index, gain, _) = event.action { XCTAssertEqual(index, 0); XCTAssertEqual(gain, 0.25) }
                XCTAssertEqual(gainEvents(runtime, row: 3).count, 1)
                XCTAssertTrue(gainEvents(runtime, row: 4).isEmpty)
                let target = try XCTUnwrap(runtime.plan?.diagnostics.voiceStateUpdates.first {
                    if case .gxxChannelTarget = $0.command { return $0.syntheticRow == 3 }; return false
                })
                XCTAssertEqual(target.gainBefore, 1); XCTAssertEqual(target.gainAfter, 0.25)
                XCTAssertEqual(target.effectiveVolumeBefore, 64); XCTAssertEqual(target.effectiveVolumeAfter, 64)
                for control: UInt8 in [0, 6] {
                    let module = song([[c(14, 0x70 | control, note: 49, instrument: 1)], [preparation],
                                       [c(7, 0x48)], [c(5)], [c(7)], [c(5)]])
                    let (context, states) = inspect(module, rate)
                    XCTAssertEqual(states[2][0].outputChannelVolume, 63)
                    XCTAssertEqual(states[3][0].outputChannelVolume, 32)
                    XCTAssertEqual(states[3][0].tremolo, states[2][0].tremolo)
                    XCTAssertEqual(states[3][0].tremolo.phase, 80)
                    XCTAssertEqual(states[3][0].tremolo.control, Int(control))
                    XCTAssertEqual(states[4][0].tremolo.phase, 160)
                    XCTAssertEqual(states[5][0].tremolo, states[4][0].tremolo)
                    if control == 0 {
                        XCTAssertEqual(context.voiceStateUpdates.filter { $0.effectType == 7 && $0.syntheticRow == 4 }.map(\.effectiveVolumeAfter), [61, 54, 44, 32, 20])
                    }
                }
            }
        }
    }

    func testRealSharedSeedsKeepWholeByteAndOriginWithIndependentToneGates() {
        for preparation in toneStates {
            for (family, byte, base): (UInt8, UInt8, Int) in [(10, 4, 64), (5, 4, 64), (6, 4, 64), (10, 0x24, 32)] {
                let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [preparation], [c(family, byte)], [c(5)]], base: base))
                XCTAssertEqual(states[2][0].baseChannelVolume, byte == 4 ? 44 : 42)
                XCTAssertEqual(states[3][0].baseChannelVolume, byte == 4 ? 24 : 52)
                XCTAssertEqual(states[3][0].volumeSlideMemory?.parameter, byte)
                XCTAssertEqual(states[3][0].volumeSlideMemory?.source.effectType, family)
                XCTAssertEqual(states[3][0].volumeSlideMemory?.source.source.rowIndex, 2)
                XCTAssertTrue(context.voiceStateUpdates.filter { $0.effectType == 5 && $0.syntheticRow == 3 }.allSatisfy { $0.applied && $0.effectMemoryReused && $0.memorySource?.effectType == family })
            }
        }
    }

    func testOrdinaryVolumeColumnStillRunsBeforeColdZeroSlide() {
        for preparation in toneStates {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [preparation],
                [c(7, 0x48)], [c(5, volume: 0x61)]]))
            let updates = context.voiceStateUpdates.filter { update in
                if case .effect5xyVolumeSlide = update.command { return true }; return false
            }
            XCTAssertEqual(updates.map(\.effectiveVolumeAfter), [31, 30, 29, 28, 27])
            XCTAssertEqual(states[3][0].baseChannelVolume, 27)
            XCTAssertNil(states[3][0].volumeSlideMemory)
        }
    }

    func testSameCellTargetsAndReachedTargetsDoNotRetriggerOrResetCursor() {
        for target in [c(5, note: 55, instrument: 1), c(5, note: 55), c(5)] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [c(3, 1, note: 53)], [c(7, 0x48)], [target]]))
            XCTAssertEqual(context.events.count, 1)
            XCTAssertEqual(states[3][0].activeEventIndex, states[2][0].activeEventIndex)
            XCTAssertEqual(states[3][0].tonePortamentoTargetNote, target.note == 0 ? 53 : 55)
            XCTAssertEqual(states[3][0].outputChannelVolume, target.instrument == 0 ? 32 : 64)
            XCTAssertTrue(context.tonePortamentoEffects.allSatisfy { !$0.noteTriggerEventCreated && !$0.samplePositionReset })
        }
        for (target, speed, expected): (UInt8, UInt8, [Double?]) in [(53, 8, [4416, 4384, 4352]), (51, 0x40, [])] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [c(3, speed, note: target)], [c(7, 0x48)], [c(5)]]))
            XCTAssertEqual(context.tonePortamentoEffects.filter { $0.syntheticRow == 3 }.flatMap(\.stepUpdates).map(\.linearPeriodAfter), expected)
            XCTAssertEqual(states[3][0].outputChannelVolume, 32)
        }
    }

    func testSilentEmptyAndCompletedRoutesRestoreStateWithoutSources() {
        for rate in [44_100.0, 48_000] {
            for preparation in toneStates {
                for route in 0...3 {
                    let module = song([[route == 0 ? c() : c(note: route == 2 ? 49 : 50, instrument: 1)],
                        [preparation], [c(7, 0x48)], [c(5)], [c(note: 49, instrument: route == 0 ? 1 : 0)]],
                        completed: route == 2, canonicalEmpty: route == 3)
                    let (context, states) = inspect(module, rate)
                    XCTAssertEqual(context.events.count, route == 2 ? 2 : 1)
                    XCTAssertEqual(states[3][0].outputChannelVolume, route == 0 ? 64 : route == 3 ? 0 : 32)
                    XCTAssertNil(states[3][0].volumeSlideMemory)
                    XCTAssertEqual(context.events.last?.gain, route == 3 ? 0 : 0.5)
                    let full = PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 1), rows: 5))
                    let tick = Int(rate / 50)
                    XCTAssertTrue(full.block.interleavedPCM[(18 * tick)..<(24 * tick)].allSatisfy { $0 == 0 })
                    XCTAssertEqual(full.block.interleavedPCM[24 * tick + 100], route == 3 ? 0 : 0.5 / 32, accuracy: 1e-7)
                    if route != 2 { XCTAssertTrue(gainEvents(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate), row: 3).isEmpty) }
                }
            }
        }
        // Source absence must gate publication even when period controls survive.
        let module = song([[c(5)]])
        let traversal = PlaybackSongTraversalPlanner.plan(module, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(module, traversalPlan: traversal, sampleRate: 48000)
        for state in 0...3 {
            var controls = Adapter.ChannelState(); controls.baseChannelVolume = 32; controls.outputChannelVolume = 63
            controls.tonePortamentoSpeed = state == 1 || state == 3 ? 1 : nil
            controls.tonePortamentoTargetLinearPeriod = state == 1 || state == 2 ? 4352 : nil
            controls.tonePortamentoTargetPlaybackStep = controls.tonePortamentoTargetLinearPeriod.map { pow(2, (4608 - $0) / 768) }
            let before = controls
            let updates = Adapter.applyEffectColumnVolumeSlide(from: c(5), source: traversal.rows[0].source,
                channelIndex: 0, syntheticRow: 0, timingConfig: timing.timingConfig(forSyntheticRow: 0),
                timingPlan: timing, channelState: &controls, usesLinearFrequencyTable: true, globalVolumeValue: 64)
            XCTAssertEqual(updates.count, 5)
            XCTAssertTrue(updates.allSatisfy { $0.applied && !$0.activeVoiceUpdated })
            XCTAssertEqual(controls.outputChannelVolume, 32); XCTAssertNil(controls.volumeSlideMemory)
            XCTAssertEqual(controls.tonePortamentoTargetLinearPeriod, before.tonePortamentoTargetLinearPeriod)
            XCTAssertEqual(controls.tonePortamentoSpeed, before.tonePortamentoSpeed)
        }
    }

    func testEnvelopeFadeoutAndGlobalCompositionKeepClocksAndExistingWriters() {
        for rate in [44_100.0, 48_000] {
            func render(_ effect: UInt8) -> PlaybackSongOfflineRenderResult {
                let module = song([[c(note: 49, instrument: 1), c(16, 16)], [c(7, 0x48)], [c(effect, note: 97)], [c(effect)]], envelope: true)
                return PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 4))
            }
            let combined = render(5)
            for family: UInt8 in [10, 6] {
                let other = render(family)
                XCTAssertEqual(combined.plan.xmEnvelopeTimeline, other.plan.xmEnvelopeTimeline)
                XCTAssertEqual(combined.plan.xmAudibleTimeline, other.plan.xmAudibleTimeline)
                assertPCMEqual(combined.block.interleavedPCM, other.block.interleavedPCM)
            }
            XCTAssertEqual(combined.plan.xmEnvelopeTimeline, render(0).plan.xmEnvelopeTimeline)
            XCTAssertEqual(inspect(song([[c(note: 49, instrument: 1)], [c(7, 0x48)], [c(17)]])).1[2][0].outputChannelVolume, 63)
        }
    }

    func testAmigaPartialPathKeepsCold500UnclosedAndSeededBehavior() {
        for parameter: UInt8 in [0, 4] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1)], [c(3, 1, note: 53)], [c(7, 0x48)], [c(5, parameter)]], linear: false))
            XCTAssertEqual(context.tonePortamentoEffects.filter { $0.syntheticRow == 3 }.flatMap(\.stepUpdates).count, 5)
            XCTAssertEqual(states[3][0].outputChannelVolume, parameter == 0 ? 63 : 12)
            let updates = context.voiceStateUpdates.filter { $0.effectType == 5 }
            XCTAssertEqual(updates.filter(\.applied).count, parameter == 0 ? 0 : 5)
            if parameter == 0 { XCTAssertTrue(updates.allSatisfy(\.effectMemoryDeferred)); XCTAssertNil(states[3][0].volumeSlideMemory) }
        }
        XCTAssertEqual(inspect(song([[c(5)]], linear: false)).0.voiceStateUpdates.filter(\.applied).count, 0)
    }

    func testPublicFixtureDiagnosticsGenerationAndWindowParity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/cold-500-local-publication.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 4)
            let full = PlaybackSongOfflineRenderer().render(request)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertEqual(gainEvents(runtime, row: 2).count, 1)
            XCTAssertEqual(gainEvents(runtime, row: 2).first?.activeEventIndex, 0)
            XCTAssertTrue(gainEvents(runtime, row: 3).isEmpty)
            for window in [1, 2, 3] { assertPCMEqual(full.block.interleavedPCM, PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: window).block.interleavedPCM) }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let updates = try XCTUnwrap(json["volume_panning_state_updates"] as? [[String: Any]])
            let cold = updates.filter { $0["effect_type"] as? Int == 5 && $0["effect_param"] as? Int == 0 }
            XCTAssertEqual(cold.count, 10)
            XCTAssertTrue(cold.allSatisfy { $0["volume_slide_policy"] as? String == "500_cold_zero_slide_output_restoration" && $0["applied"] as? Bool == true })
            XCTAssertTrue(cold.allSatisfy { $0["effect_memory_reused"] as? Bool == false && $0["effect_memory_missing"] as? Bool == false && $0["memory_source"] is NSNull })
        }
    }

    private func gainEvents(_ runtime: RuntimeCMixerAdapterEventPlan, row: Int) -> [RuntimeCMixerAdapterEvent] {
        runtime.events.filter { if case .gainPanUpdate = $0.action { return $0.source.rowIndex == row }; return false }
    }
    private func assertPCMEqual(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func inspect(_ song: PlaybackSong, _ rate: Double = 48000) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
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
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, base: Int = 32, linear: Bool = true, envelope: Bool = false, completed: Bool = false, canonicalEmpty: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1 / 32, count: completed ? 32 : 256),
            volume: Float(base) / 64, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: canonicalEmpty ? 0 : Float(base) / 64, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 32), .init(tick: 64, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 1024 : 0)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        return .init(title: "Public cold 500", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count)) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: canonicalEmpty, volume: canonicalEmpty ? 0 : UInt8(base), panning: canonicalEmpty ? 0 : 128, finetune: 0, relativeNote: 0)]])
    }
}
