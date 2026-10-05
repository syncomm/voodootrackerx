import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VolumeColumnVibratoTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testAxBxShareZeroAndNibbleMemoryWithBothEffectFamiliesAtAllSpeeds() throws {
        for linear in [true, false] {
            for speed in [1, 3, 6] {
                let cells = [cell(0xA3, note: 49, instrument: 1), cell(0xB4), cell(0xA0), cell(0xB0),
                    cell(effect: 4), cell(effect: 6, param: 2), cell(effect: 6), cell(0xA1), cell(0xB3)]
                let plan = Adapter.adapt(song(cells, linear: linear, speed: speed), orderIndex: 0, sampleRate: 48000)
                let n = speed - 1
                XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoPhase },
                    [0, n*12, n*12, n*24, n*36, n*48, n*60, n*60, n*64].map { $0 & 255 })
                XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoSpeed }, [3, 3, 3, 3, 3, 3, 3, 1, 1])
                XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoDepth },
                    speed == 1 ? Array(repeating: 0, count: 9) : [0, 4, 4, 4, 4, 4, 4, 4, 3])
                XCTAssertFalse(plan.diagnostics.vibratoEffects.contains { [0, 2, 7].contains($0.syntheticRow) })
                XCTAssertTrue(plan.diagnostics.volumeColumnMappings.allSatisfy { $0.volumeColumn.applied && !$0.volumeColumn.deferred })
                let replay = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 4 })
                XCTAssertEqual(replay.vibratoSpeedMemorySource?.source.rowIndex, 0)
                XCTAssertEqual(replay.vibratoDepthMemorySource?.source.rowIndex, speed == 1 ? nil : 1)
                XCTAssertEqual(replay.stepUpdates.filter { $0.vibrato != nil }.count, n)
            }
            let plan = Adapter.adapt(song([cell(0xA3, note: 49, instrument: 1), cell(0xB4),
                cell(effect: 4, param: 5), cell(effect: 4, param: 0x70), cell(effect: 6)], linear: linear), orderIndex: 0, sampleRate: 48000)
            XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoSpeed }, [3, 3, 3, 7, 7])
            XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoDepth }, [0, 4, 5, 5, 5])
        }
        for raw in UInt8(0xA0)...0xBF { XCTAssertTrue(PlaybackSongVolumeColumnDecoder.decode(raw).applied) }
        let cold = Adapter.adapt(song([cell(0xA0, note: 49, instrument: 1), cell(0xB0)], linear: true), orderIndex: 0, sampleRate: 48000)
        XCTAssertTrue(cold.xmChannelRows.allSatisfy { $0.controls.vibratoSpeed == 0 && $0.controls.vibratoDepth == 0 && $0.controls.vibratoPhase == 0 })
    }

    func testTwoChannelsKeepIndependentColumnAndEffectMemory() {
        for linear in [true, false] {
            let first = [cell(0xA3, note: 49, instrument: 1), cell(0xB4), cell(0xA0), cell(effect: 4)]
            let second = [cell(0xA1, note: 49, instrument: 1), cell(0xB1), cell(0xAF), cell(0xB0)]
            let base = song(first, linear: linear)
            let input = PlaybackSong(title: base.title, orders: base.orders,
                patternsByIndex: [0: .init(index: 0, rows: first.indices.map { .init(index: $0, cells: [first[$0], second[$0]]) })],
                instrumentsByIndex: base.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: base.initialTiming, usesLinearFrequencyTable: linear)
            let plan = Adapter.adapt(input, orderIndex: 0, sampleRate: 48000)
            XCTAssertEqual(plan.xmChannelRows.filter { $0.channelIndex == 0 }.map { $0.controls.vibratoPhase }, [0, 60, 60, 120])
            XCTAssertEqual(plan.xmChannelRows.filter { $0.channelIndex == 1 }.map { $0.controls.vibratoPhase }, [0, 20, 20, 64])
            XCTAssertEqual(plan.xmChannelRows.filter { $0.channelIndex == 0 }.map { $0.controls.vibratoDepth }, [0, 4, 4, 4])
            XCTAssertEqual(plan.xmChannelRows.filter { $0.channelIndex == 1 }.map { $0.controls.vibratoDepth }, [0, 1, 1, 1])
        }
    }

    func testMixedWritersExecuteInReferenceOrderWithoutCollapsingPhaseOrEventIdentity() throws {
        for linear in [true, false] {
            for effect: UInt8 in [4, 6] {
                let plan = Adapter.adapt(song([cell(note: 49, instrument: 1, effect: 4, param: 0x21),
                    cell(0xB3, effect: effect, param: effect == 4 ? 0x56 : 2), cell(effect: 4)], linear: linear), orderIndex: 0, sampleRate: 48000)
                let mixed = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 1 })
                let updates = mixed.stepUpdates
                XCTAssertEqual(updates.map(\.syntheticTick), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
                guard updates.count == 10 else { continue }
                XCTAssertEqual(updates.compactMap { $0.vibrato?.phaseBefore }, effect == 4
                    ? [40, 48, 68, 88, 108, 128, 148, 168, 188, 208] : [40, 48, 56, 64, 72, 80, 88, 96, 104, 112])
                let periods: [Double] = effect == 4 ? [4652, 4647, 4608, 4569, 4564] : [4630, 4631, 4630, 4624, 4617]
                for tick in 1...5 {
                    let update = updates[tick * 2 - 1]
                    XCTAssertEqual(linear ? update.linearPeriodAfter : try XCTUnwrap(update.amigaPeriodAfter) / 4,
                        linear ? periods[tick - 1] : periods[tick - 1] - 2896)
                    XCTAssertEqual(update.scheduledFrame, (6 + tick) * 960)
                }
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song([cell(note: 49, instrument: 1, effect: 4, param: 0x21),
                    cell(0xB3, effect: effect, param: effect == 4 ? 0x56 : 2), cell(effect: 4)], linear: linear), sampleRate: 48000)
                let events = runtime.events.filter { $0.source.rowIndex == 1 && $0.categories.contains("vibrato_update") }
                XCTAssertEqual(events.count, 10)
                guard events.count == 10 else { continue }
                XCTAssertEqual(Set(events.map(\.id)).count, 10)
                for tick in 1...5 {
                    let pair = events.filter { $0.syntheticTick == tick }
                    XCTAssertLessThan(pair[0].id, pair[1].id)
                    guard case let .stepUpdate(_, first) = pair[0].action, case let .stepUpdate(_, last) = pair[1].action else {
                        return XCTFail("Missing ordered pitch writer")
                    }
                    XCTAssertEqual(first, updates[(tick - 1) * 2].playbackStepAfter)
                    XCTAssertEqual(last, updates[tick * 2 - 1].playbackStepAfter)
                }
            }
            let ax = Adapter.adapt(song([cell(note: 49, instrument: 1, effect: 4, param: 0x21),
                cell(0xA3, effect: 4, param: 0x56), cell(0xA3, effect: 6)], linear: linear), orderIndex: 0, sampleRate: 48000)
            XCTAssertEqual(ax.xmChannelRows.map { $0.controls.vibratoPhase }, [40, 140, 200])
            XCTAssertEqual(ax.xmChannelRows.map { $0.controls.vibratoSpeed }, [2, 5, 3])
        }
    }

    func testSilentRoutesCompletedSourcesAndE4ResetsUseTheSharedEngine() throws {
        for linear in [true, false] {
            for kind in 0...4 {
                let cells = [cell(0xA3, note: kind == 2 || kind == 4 ? 50 : (kind == 3 ? 49 : 0), instrument: kind == 0 ? 0 : 1),
                    cell(0xB4), cell(0xB0, effect: 14, param: 0x44), cell(0xB0, note: 49, instrument: 1)]
                let input = song(cells, linear: linear, completed: kind == 3, invalid: kind == 4)
                let plan = Adapter.adapt(input, orderIndex: 0, sampleRate: 48000)
                XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoPhase }, [0, 60, 120, 180])
                XCTAssertEqual(plan.pattern.events.map(\.row), kind == 3 ? [0, 3] : [3])
                if kind != 3 {
                    XCTAssertTrue(plan.diagnostics.vibratoEffects.filter { $0.syntheticRow < 3 }.allSatisfy { !$0.activeVoiceFound && $0.stepUpdates.isEmpty })
                } else {
                    let pcm = PlaybackSongOfflineRenderer().render(.init(song: input, config: .init(sampleRate: 48000), rows: 4)).block.interleavedPCM
                    XCTAssertTrue(pcm[11_520..<34_560].allSatisfy { $0 == 0 })
                }
            }
            for control: UInt8 in [0, 1, 2, 4, 5, 6, 12, 13, 14] {
                for instrument: UInt8 in [0, 1] {
                    let plan = Adapter.adapt(song([cell(effect: 14, param: 0x40 | control), cell(0xA3, note: 49, instrument: 1),
                        cell(0xB4), cell(0xB0, note: 49, instrument: instrument), cell(0xB0, instrument: 1)], linear: linear), orderIndex: 0, sampleRate: 48000)
                    let effects = plan.diagnostics.vibratoEffects
                    XCTAssertEqual(effects[1].phaseBefore, instrument == 0 || control & 4 != 0 ? 60 : 0)
                    XCTAssertEqual(effects[2].phaseBefore, control & 4 != 0 ? effects[1].phaseAfter : 0)
                    XCTAssertTrue(effects.allSatisfy { $0.vibratoControlValue == Int(control) })
                    XCTAssertEqual(effects[0].vibratoWaveform, ["sine", "ramp_down", "square"][Int(control & 3)])
                }
            }
        }
        let zero = Adapter.adapt(song([cell(0xA4, note: 95, instrument: 1), cell(0xBF), cell(0xB0), cell(0xB0)], linear: false, finetune: 8), orderIndex: 0, sampleRate: 48000)
        XCTAssertEqual(zero.diagnostics.vibratoEffects.last?.stepUpdates.compactMap { $0.amigaPeriodAfter.map { $0 / 4 } }, [35, 9, 0, 9, 35])
        XCTAssertTrue(zero.diagnostics.vibratoEffects.last?.stepUpdates.contains { $0.playbackStepAfter == 0 } == true)
    }

    func testPublicFixtureExactStateAndWholeWindowRuntimePlanParityAcrossModesAndRates() throws {
        for linear in [true, false] {
            for rate in [44_100.0, 48_000] {
                let input = try fixtureSong(linear: linear)
                let plan = Adapter.adapt(input, orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoPhase },
                    [0, 0, 24, 84, 84, 144, 80, 24, 44, 44, 64, 84, 20, 20, 20, 80, 140, 200, 4, 4, 4, 84, 164, 244, 244])
                XCTAssertEqual(plan.pattern.events.map(\.row), [0, 11, 16, 23])
                for row in [14, 15] { XCTAssertNil(plan.xmChannelRows[row].controls.activeEventIndex) }
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
                XCTAssertEqual(runtime.plan, plan)
                let renderer = PlaybackSongOfflineRenderer()
                let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 25)
                let whole = renderer.render(request)
                for width in [1, 3, 7, 14, 16] {
                    let window = renderer.renderWindowed(request, windowRows: width)
                    XCTAssertEqual(window.plan, whole.plan)
                    XCTAssertEqual(window.block.frameCount, whole.block.frameCount)
                    XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM, window.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
                }
            }
        }
    }

    private func cell(_ volume: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0,
                      effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ cells: [PlaybackCell], linear: Bool, speed: Int = 6, completed: Bool = false,
                      invalid: Bool = false, finetune: Int = 0) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0.5, 0, -0.5], volume: 1,
            relativeNote: 0, finetune: finetune, baseSampleRate: 8363, loopLength: completed ? 0 : 4, loopType: completed ? 0 : 1)
        var map = Array(repeating: 0, count: 96); map[49] = invalid ? 15 : 1
        return .init(title: "Column vibrato", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: map)], restartOrderIndex: 0,
            endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }

    private func fixtureSong(linear: Bool) throws -> PlaybackSong {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/volume-column-vibrato.xm")
        let parsed = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        return .init(title: parsed.title, orders: parsed.orders, patternsByIndex: parsed.patternsByIndex,
            instrumentsByIndex: parsed.instrumentsByIndex, restartOrderIndex: parsed.restartOrderIndex,
            endBehavior: parsed.endBehavior, initialTiming: parsed.initialTiming, usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: parsed.xmSampleSlotProvenanceByInstrument)
    }
}
