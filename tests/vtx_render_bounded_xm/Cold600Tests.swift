import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class Cold600Tests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testHeldGlobalTargetRefreshAtNativeAndSameRowFxxSpeeds() throws {
        for rate in [44_100.0, 48_000] {
            for linear in [false, true] {
                for speed in [1, 3, 6] {
                    for fxx in [false, true] {
                        let module = song([[c(4, 0x48, note: 49, instrument: 1), c(16, 16)], [],
                            [c(6), fxx ? c(15, UInt8(speed)) : c()], [c(6)]],
                            speed: fxx ? 6 : speed, base: 64, linear: linear)
                        let (context, states) = inspect(module, rate)
                        let updates = context.voiceStateUpdates.filter { $0.effectType == 6 && $0.syntheticRow == 2 }
                        XCTAssertEqual(updates.filter(\.applied).map(\.syntheticTick), Array(1..<speed))
                        XCTAssertTrue(updates.allSatisfy { $0.effectiveVolumeBefore == 64 && $0.effectiveVolumeAfter == 64 })
                        XCTAssertTrue(updates.allSatisfy { !$0.effectMemoryReused && $0.memorySource == nil && !$0.effectMemoryDeferred })
                        XCTAssertTrue(states.allSatisfy { $0[0].volumeSlideMemory == nil })
                        XCTAssertEqual(states[2][0].baseChannelVolume, 64)
                        XCTAssertEqual(states[2][0].outputChannelVolume, 64)
                        let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                        XCTAssertEqual(runtime.plan?.pattern.events.first?.gain, 1)
                        let gains = gainEvents(runtime, row: 2)
                        XCTAssertEqual(gains.count, speed > 1 ? 1 : 0)
                        XCTAssertTrue(gainEvents(runtime, row: 3).isEmpty)
                        if speed > 1 {
                            let event = try XCTUnwrap(gains.first)
                            XCTAssertEqual(event.syntheticTick, 1)
                            XCTAssertEqual(event.scheduledFrame, ((fxx ? 12 : speed * 2) + 1) * Int(rate / 50))
                            if case let .gainPanUpdate(index, gain, _) = event.action {
                                XCTAssertEqual(index, 0); XCTAssertEqual(gain, 0.25)
                            }
                            let target = try XCTUnwrap(runtime.plan?.diagnostics.voiceStateUpdates.first {
                                if case .gxxChannelTarget = $0.command { return $0.syntheticRow == 2 && $0.syntheticTick == 1 }; return false
                            })
                            XCTAssertEqual(target.gainBefore, 1); XCTAssertEqual(target.gainAfter, 0.25)
                            XCTAssertEqual(target.activeEventIndex, 0)
                        }
                    }
                }
            }
        }
    }

    func testNumericRestorationAndConvergedTargetsDoNotDuplicate() {
        for rate in [44_100.0, 48_000] {
            for tremolo in [false, true] {
                let module = song([[c(note: 49, instrument: 1)], [tremolo ? c(7, 0x48) : c()], [c(6)], [c(6)]])
                let (context, states) = inspect(module, rate)
                let updates = context.voiceStateUpdates.filter { $0.effectType == 6 && $0.syntheticRow == 2 }
                XCTAssertEqual(updates.map(\.effectiveVolumeBefore), [tremolo ? 63 : 32, 32, 32, 32, 32])
                XCTAssertEqual(updates.map(\.effectiveVolumeAfter), Array(repeating: 32, count: 5))
                XCTAssertTrue(updates.allSatisfy(\.applied))
                XCTAssertEqual(states[2][0].tremolo, states[1][0].tremolo)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                let gains = gainEvents(runtime, row: 2)
                XCTAssertEqual(gains.count, tremolo ? 1 : 0)
                XCTAssertTrue(gainEvents(runtime, row: 3).isEmpty)
                if case let .gainPanUpdate(_, gain, _) = gains.first?.action {
                    XCTAssertEqual(gain, 0.5); XCTAssertEqual(gains.first?.syntheticTick, 1)
                }
            }
        }
    }

    func testSeededReplayKeepsByteOriginAndMixedNibblePolicy() {
        for family: UInt8 in [10, 5, 6] {
            for byte: UInt8 in [4, 0x12] {
                let module = song([[c(note: 49, instrument: 1)], [c(family, byte, volume: 0x50)], [c(6)]])
                let (context, states) = inspect(module)
                let replay = context.voiceStateUpdates.filter { $0.effectType == 6 && $0.syntheticRow == 2 }
                XCTAssertEqual(states[2][0].volumeSlideMemory?.parameter, byte)
                XCTAssertEqual(states[2][0].volumeSlideMemory?.source.effectType, family)
                XCTAssertEqual(states[2][0].volumeSlideMemory?.source.source.rowIndex, 1)
                XCTAssertTrue(replay.allSatisfy { $0.applied && $0.effectMemoryReused && $0.memorySource?.effectType == family })
                XCTAssertEqual(replay.map(\.effectiveVolumeAfter), byte == 4 ? [40, 36, 32, 28, 24] : [64, 64, 64, 64, 64])
            }
        }
    }

    func testColdVibratoKeepsBothPitchModesE4ColumnInteractionAndZeroResume() {
        for linear in [false, true] {
            for control: UInt8 in 0...15 {
                for column: UInt8 in [0, 0xB3] {
                    func plan(_ effect: UInt8) -> PlaybackSongSyntheticPlan {
                        Adapter.adapt(song([[c(14, 0x40 | control)], [c(4, 0x4F, note: 95, instrument: 1)],
                            [c(effect, volume: column)], [c(effect)], [c(effect)], []], linear: linear, finetune: 8),
                            orderIndex: 0, sampleRate: 48000)
                    }
                    let combined = plan(6), pure = plan(4)
                    XCTAssertEqual(combined.diagnostics.vibratoEffects.map(\.stepUpdates), pure.diagnostics.vibratoEffects.map(\.stepUpdates))
                    XCTAssertEqual(combined.diagnostics.vibratoEffects.map(\.phaseAfter), pure.diagnostics.vibratoEffects.map(\.phaseAfter))
                    XCTAssertEqual(combined.diagnostics.vibratoEffects.map(\.vibratoSpeed), pure.diagnostics.vibratoEffects.map(\.vibratoSpeed))
                    XCTAssertEqual(combined.diagnostics.vibratoEffects.map(\.vibratoDepth), pure.diagnostics.vibratoEffects.map(\.vibratoDepth))
                    if !linear && control == 0 && column == 0 {
                        let steps = combined.diagnostics.vibratoEffects.flatMap(\.stepUpdates)
                        let zero = steps.firstIndex { $0.playbackStepAfter == 0 }
                        XCTAssertNotNil(zero)
                        if let zero { XCTAssertGreaterThan(steps[zero + 1].playbackStepAfter, 0) }
                    }
                }
            }
        }
    }

    func testSilentEmptyAndCompletedRoutesKeepSemanticsWithoutNewSources() {
        for rate in [44_100.0, 48_000] {
            for route in 0...2 {
                let module = song([[route == 0 ? c() : c(note: route == 1 ? 50 : 49, instrument: 1)],
                                   [], [c(6)], [c(note: 49, instrument: route == 0 ? 1 : 0)]], completed: route == 2)
                let (context, states) = inspect(module, rate)
                XCTAssertEqual(context.events.count, route == 2 ? 2 : 1)
                XCTAssertEqual(context.events.last?.gain, 0.5)
                XCTAssertEqual(states[2][0].baseChannelVolume, route == 0 ? 64 : 32)
                XCTAssertEqual(states[2][0].outputChannelVolume, route == 0 ? 64 : 32)
                XCTAssertNil(states[2][0].volumeSlideMemory)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                XCTAssertTrue(gainEvents(runtime, row: 2).isEmpty)
                let full = PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 1), rows: 4))
                let tick = Int(rate / 50)
                XCTAssertTrue(full.block.interleavedPCM[(12 * tick)..<(18 * tick)].allSatisfy { $0 == 0 })
                XCTAssertEqual(full.block.interleavedPCM[18 * tick + 100], 0.5 / 32, accuracy: 1e-7)
            }
        }
    }

    func testEnvelopeFadeoutAndGlobalCompositionMatchExistingColdA00Writer() {
        for rate in [44_100.0, 48_000] {
            func render(_ effect: UInt8) -> PlaybackSongOfflineRenderResult {
                let module = song([[c(note: 49, instrument: 1), c(16, 31)], [c(7, 0x48)],
                                   [c(effect, note: 97)], [c(effect)]], envelope: true)
                return PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 4))
            }
            let combined = render(6), a00 = render(10)
            XCTAssertEqual(combined.plan.xmEnvelopeTimeline, a00.plan.xmEnvelopeTimeline)
            XCTAssertEqual(combined.plan.xmAudibleTimeline, a00.plan.xmAudibleTimeline)
            assertPCMEqual(combined.block.interleavedPCM, a00.block.interleavedPCM)
        }
    }

    func testPublicFixturePinsDiagnosticsWindowsAndGeneration() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/cold-600-local-publication.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 4)
            let full = PlaybackSongOfflineRenderer().render(request)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertEqual(gainEvents(runtime, row: 2).count, 1)
            XCTAssertEqual(gainEvents(runtime, row: 2).first?.activeEventIndex, 0)
            for window in [1, 2, 3] {
                assertPCMEqual(full.block.interleavedPCM, PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: window).block.interleavedPCM)
            }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let updates = try XCTUnwrap(json["volume_panning_state_updates"] as? [[String: Any]])
            let cold = updates.filter { $0["effect_type"] as? Int == 6 && $0["effect_param"] as? Int == 0 }
            XCTAssertEqual(cold.count, 10)
            XCTAssertTrue(cold.allSatisfy { $0["volume_slide_amount"] as? Int == 0 })
            XCTAssertTrue(cold.allSatisfy { $0["applied"] as? Bool == true && $0["effect_memory_deferred"] as? Bool == false })
            XCTAssertTrue(cold.allSatisfy { $0["effect_memory_reused"] as? Bool == false && $0["memory_source"] is NSNull })
        }
    }

    private func assertPCMEqual(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func gainEvents(_ runtime: RuntimeCMixerAdapterEventPlan, row: Int) -> [RuntimeCMixerAdapterEvent] {
        runtime.events.filter { if case .gainPanUpdate = $0.action { return $0.source.rowIndex == row }; return false }
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
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, base: Int = 32, linear: Bool = true,
                      finetune: Int = 0, envelope: Bool = false, completed: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1 / 32, count: completed ? 32 : 256),
            volume: Float(base) / 64, panning: 128, relativeNote: 0, finetune: finetune, baseSampleRate: 8363,
            loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: Float(base) / 64, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 32), .init(tick: 64, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 1024 : 0)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        return .init(title: "Public cold 600", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count)) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: UInt8(base), panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
