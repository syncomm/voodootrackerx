import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VibratoEmptyRouteTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testPublicFixtureRetainsSilentStateAndLaterExactPitchAcrossModesRatesAndWindows() throws {
        for linear in [true, false] {
            for rate in [44_100.0, 48_000] {
                let song = try fixtureSong(linear: linear)
                let plan = Adapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let states = plan.xmChannelRows.map(\.controls)
                XCTAssertEqual(states.map(\.vibratoPhase), [0, 60, 120, 180, 44, 164, 28, 28])
                XCTAssertEqual(states.map(\.vibratoSpeed), [0, 3, 3, 3, 6, 6, 6, 6])
                XCTAssertEqual(states.map(\.vibratoDepth), [0, 5, 5, 5, 4, 4, 4, 4])
                XCTAssertEqual(plan.pattern.events.map(\.row), [1, 3, 6])
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.mappedSampleIndex), [0, 0, 0])
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
                for row in [2, 4, 5] {
                    XCTAssertNil(states[row].activeEventIndex)
                    let effect = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == row })
                    XCTAssertEqual(effect.status, .noActiveVoice)
                    XCTAssertTrue(effect.stepUpdates.isEmpty)
                }
                let later = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 3 })
                XCTAssertEqual(later.phaseBefore, 120)
                XCTAssertEqual(later.vibratoSpeed, 3)
                XCTAssertEqual(later.vibratoDepth, 5)
                XCTAssertEqual(later.vibratoControlValue, 4)
                // Executed project-authored control at the pinned FT2 reference, in reference units.
                let periods = linear ? [4615.0, 4605, 4593, 4583, 4575] : [1719.0, 1709, 1697, 1687, 1679]
                for (index, update) in later.stepUpdates.enumerated() {
                    let period = linear ? update.linearPeriodAfter : try XCTUnwrap(update.amigaPeriodAfter) / 4
                    XCTAssertEqual(period, periods[index])
                    XCTAssertEqual(update.scheduledFrame, Int(rate / 50) * (18 + index + 1))
                    let step = linear ? 8363 * pow(2, (4608 - period) / 768) / rate : 8363 * 1712 / period / rate
                    XCTAssertEqual(update.playbackStepAfter, step, accuracy: 1e-12)
                }
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate)
                XCTAssertEqual(runtime.plan, plan)
                XCTAssertEqual(runtime.events.filter { $0.categories.contains("note_trigger") }.map(\.source.rowIndex), [1, 3, 6])
                let renderer = PlaybackSongOfflineRenderer()
                let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: 8)
                let whole = renderer.render(request)
                for window in [1, 2, 3, 4, 5] {
                    let result = renderer.renderWindowed(request, windowRows: window)
                    XCTAssertEqual(result.plan, whole.plan)
                    XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM, result.block.interleavedPCM)
                        .map { abs($0 - $1) }.max() ?? 0, 1e-7)
                }
                for row in [2, 4, 5] {
                    let frame = Int(rate / 50) * row * 6
                    XCTAssertTrue(whole.block.interleavedPCM[(frame * 2)..<((frame + Int(rate / 50) * 6) * 2)].allSatisfy { $0 == 0 })
                }
            }
        }
    }

    func testEmptyTriggersUseExistingResetPolicyAndDispatchNonzeroTicksAtEverySpeed() throws {
        for linear in [true, false] {
            for speed in [1, 3, 6] {
                for control: UInt8 in [0, 4, 1, 5] {
                    for explicit in [false, true] {
                        let cells = [cell(14, 0x40 | control), cell(4, 0x35, note: 49, instrument: 1),
                            cell(4, 0x64, note: 50, instrument: explicit ? 1 : 0), cell(14, 0x44 | (control & 3)),
                            cell(4, 0, note: 49, instrument: 1)]
                        let plan = Adapter.adapt(module(cells, linear: linear, speed: speed), orderIndex: 0, sampleRate: 48000)
                        let empty = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 2 })
                        let start = explicit && control & 4 == 0 ? 0 : (speed - 1) * 12
                        XCTAssertEqual(empty.phaseBefore, Double(start))
                        XCTAssertEqual(empty.phaseAfter, Double((start + (speed - 1) * 24) & 255))
                        XCTAssertEqual(empty.vibratoSpeed, speed == 1 ? 0 : 6)
                        XCTAssertEqual(empty.vibratoDepth, speed == 1 ? 0 : 4)
                        XCTAssertEqual(empty.vibratoControlValue, Int(control))
                        XCTAssertEqual(empty.vibratoWaveform, control & 3 == 0 ? "sine" : "ramp_down")
                        XCTAssertFalse(empty.activeVoiceFound)
                        XCTAssertTrue(empty.stepUpdates.isEmpty)
                        XCTAssertEqual(plan.diagnostics.vibratoEffects.last?.phaseBefore, empty.phaseAfter)
                        XCTAssertEqual(plan.pattern.events.count, 2)
                    }
                }
            }
        }
    }

    func testColdCompletedSourceLessAndUndeclaredRoutesNeverInventVoices() throws {
        for linear in [true, false] {
            let cold = Adapter.adapt(module([cell(4, 0, note: 50, instrument: 1), cell(14, 0x44),
                cell(4, 0, note: 49, instrument: 1)], linear: linear), orderIndex: 0, sampleRate: 48000)
            XCTAssertTrue(cold.xmChannelRows.allSatisfy { $0.controls.vibratoSpeed == 0 && $0.controls.vibratoDepth == 0 && $0.controls.vibratoPhase == 0 })
            let seeded = Adapter.adapt(module([cell(4, 0x35, note: 50, instrument: 1), cell(14, 0x44),
                cell(4, 0, note: 49, instrument: 1)], linear: linear), orderIndex: 0, sampleRate: 48000)
            XCTAssertEqual(seeded.diagnostics.vibratoEffects.last?.phaseBefore, 60)
            XCTAssertEqual(seeded.diagnostics.vibratoEffects.last?.vibratoSpeed, 3)
            XCTAssertEqual(seeded.diagnostics.vibratoEffects.last?.vibratoDepth, 5)
            XCTAssertEqual(seeded.pattern.events.map(\.row), [2])
            for sourceLess in [true, false] {
                for declared in [true, false] {
                    let cells = [cell(14, 0x44), cell(4, 0x35, note: sourceLess ? 0 : 49, instrument: 1),
                        cell(6, 0, note: 50), cell(4, 0, instrument: 1), cell(4, 0, note: 49)]
                    let song = module(cells, linear: linear, declared: declared, completed: !sourceLess)
                    let plan = Adapter.adapt(song, orderIndex: 0, sampleRate: 48000)
                    XCTAssertEqual(plan.xmChannelRows.map { $0.controls.vibratoPhase }, [0, 60, 120, 180, 240])
                    XCTAssertTrue(plan.xmChannelRows[2...3].allSatisfy { $0.controls.activeEventIndex == nil })
                    XCTAssertEqual(plan.pattern.events.map(\.row), sourceLess ? [4] : [1, 4])
                    XCTAssertEqual(plan.diagnostics.vibratoEffects.last?.phaseBefore, 180)
                    if !sourceLess {
                        let pcm = PlaybackSongOfflineRenderer().render(.init(song: song, config: .init(sampleRate: 48000), rows: 5)).block.interleavedPCM
                        XCTAssertTrue(pcm[12_000..<46_080].allSatisfy { $0 == 0 })
                    }
                }
            }
        }
    }

    func testUnavailableSourceWithoutVibratoPreservesLawfulResetAndAxBxStayDeferred() {
        for suppressed in [false, true] {
            let plan = Adapter.adapt(module([cell(14, suppressed ? 0x44 : 0x40), cell(4, 0x35, note: 49, instrument: 1),
                cell(note: 50, instrument: 1)], linear: true), orderIndex: 0, sampleRate: 48000)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.vibratoPhase, suppressed ? 60 : 0)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.vibratoSpeed, 3)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.vibratoDepth, 5)
        }
        for raw in UInt8(0xA0)...0xBF { XCTAssertTrue(PlaybackSongVolumeColumnDecoder.decode(raw).deferred) }
    }

    private func cell(_ effect: UInt8 = 0, _ param: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: param)
    }

    private func module(_ cells: [PlaybackCell], linear: Bool, speed: Int = 6,
                        declared: Bool = true, completed: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0.5, 0, -0.5], volume: 1,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: completed ? 0 : 4, loopType: completed ? 0 : 1)
        var map = Array(repeating: 0, count: 96); map[49] = declared ? 1 : 15
        return .init(title: "Empty vibrato", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: declared ? [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]] : [:])
    }

    private func fixtureSong(linear: Bool) throws -> PlaybackSong {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/vibrato-empty-route-state.xm")
        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        return .init(title: song.title, orders: song.orders, patternsByIndex: song.patternsByIndex, instrumentsByIndex: song.instrumentsByIndex,
            restartOrderIndex: song.restartOrderIndex, endBehavior: song.endBehavior, initialTiming: song.initialTiming,
            usesLinearFrequencyTable: linear, xmSampleSlotProvenanceByInstrument: song.xmSampleSlotProvenanceByInstrument)
    }
}
