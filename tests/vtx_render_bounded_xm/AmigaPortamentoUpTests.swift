import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class AmigaPortamentoUpTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]

    func testAmiga104And100UseExistingStepPath() throws {
        for rate in rates {
            let plan = adapt([[c(note: 49, instrument: 1)], [c(1, 4)], [c(1)]], rate)
            let effects = plan.diagnostics.portamentoSlideEffects
            XCTAssertEqual(effects.map(\.status), [.applied, .applied])
            XCTAssertEqual(effects.map(\.slideAmount), [4, 4])
            XCTAssertEqual(effects.map(\.effectMemoryReused), [false, true])
            XCTAssertEqual(effects.last?.memorySource?.source.rowIndex, 1)
            XCTAssertEqual(effects.flatMap(\.stepUpdates).map(\.amigaPeriodAfter), [6784, 6720, 6656, 6592])
            XCTAssertEqual(effects.flatMap(\.stepUpdates).map(\.scheduledFrame), [4,5,7,8].map { $0*Int(rate/50) })
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertTrue(effects.allSatisfy { $0.activeEventIndex == 0 && !$0.clamped })
            XCTAssertEqual(effects.last?.policy, "amiga_zero_param_reuses_prior_1xx_portamento_up_memory")
        }
    }

    func testParametersSpeedsTuningAndOppositeDirectionAtEarlierLaterFxx() throws {
        // Pinned FT2 C-1 periods in VTX's 4x domain; +1 quantizes with zero.
        let bases = [(-128, 58048.0), (0, 54784), (1, 54784), (127, 51904)]
        for rate in rates {
            for speed in [1,2,3,6] {
                for amount: UInt8 in [1,2,4,8,16,32,64,127,255] {
                    for (finetune, base) in bases {
                        for relative in [-12,0,12] {
                            for channel in [0,1] {
                                let start = base * pow(2, -Double(relative)/12)
                                for effect: UInt8 in [1,2] {
                                    var note = [c(), c()], slide = [c(), c()]
                                    note[channel] = c(note: 13, instrument: 1)
                                    slide[channel] = c(effect, amount); slide[1-channel] = c(15, UInt8(speed))
                                    let plan = adapt([note, slide], rate, finetune: finetune, relative: relative)
                                    let d = try XCTUnwrap(plan.diagnostics.portamentoSlideEffects.first)
                                    XCTAssertEqual(d.status, .applied)
                                    XCTAssertEqual(d.rowSpeed, speed)
                                    XCTAssertEqual(d.slideAmount, Int(amount))
                                    XCTAssertEqual(d.currentAmigaPeriodBefore, start)
                                    XCTAssertNil(d.currentLinearPeriodBefore)
                                    XCTAssertFalse(d.clamped)
                                    XCTAssertEqual(d.stepUpdates.map(\.syntheticTick), Array(1..<speed))
                                    XCTAssertEqual(d.stepUpdates.map(\.scheduledFrame), (1..<speed).map { (3+$0)*Int(rate/50) })
                                    for u in d.stepUpdates {
                                        let delta = Double(amount)*16*(effect == 1 ? -1.0 : 1)
                                        XCTAssertEqual(u.amigaPeriodBefore, start+Double(u.syntheticTick-1)*delta)
                                        XCTAssertEqual(u.amigaPeriodAfter, start+Double(u.syntheticTick)*delta)
                                        XCTAssertEqual(u.playbackStepAfter, Adapter.playbackStep(amigaPeriod: start+Double(u.syntheticTick)*delta, baseSampleRate: 8363, outputSampleRate: rate)!, accuracy: 1e-12)
                                    }
                                    if speed == 1 { XCTAssertEqual(d.policy, "regular_portamento_no_nonzero_ticks_no_memory_admission") }
                                    XCTAssertEqual(plan.pattern.events.count, 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testNoOwnerAdmitsMemoryWithoutPlaybackAndClampRetainsG30Policy() throws {
        for rate in rates {
            let cold = adapt([[c(1)], [c(1,4)], [c(1)]], rate)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertEqual(cold.diagnostics.portamentoSlideEffects.map(\.status), [.zeroParamEffectMemoryDeferred, .noActiveVoice, .noActiveVoice])
            XCTAssertEqual(cold.diagnostics.portamentoSlideEffects.last?.slideAmount, 4)
            XCTAssertTrue(cold.diagnostics.portamentoSlideEffects.last?.effectMemoryReused == true)
            let edge = adapt([[c(1,255,note: 96,instrument: 1)], [c(1)]], rate, speed: 6)
            XCTAssertEqual(edge.pattern.events.count, 1)
            for d in edge.diagnostics.portamentoSlideEffects {
                XCTAssertTrue(d.clamped)
                XCTAssertEqual(d.currentAmigaPeriodAfter, 107)
                XCTAssertEqual(d.stepUpdates.count, 1)
                XCTAssertEqual(d.stepUpdates.first?.syntheticTick, 1)
                XCTAssertEqual(d.stepUpdates.first?.playbackStepAfter ?? 0, Adapter.playbackStep(amigaPeriod: 107, baseSampleRate: 8363, outputSampleRate: rate)!, accuracy: 1e-12)
            }
            // Existing VTX minimum/break-on-clamp is retained. FT2 reaches native
            // period 1 (4 in this representation); that extreme residual is G30.
        }
    }

    func testPublicFixtureWholeWindowRuntimeTargetsAndBoundarySplits() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/amiga-portamento-up.xm")
        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        XCTAssertFalse(song.usesLinearFrequencyTable)
        for rate in rates {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate)
            let renderer = PlaybackSongOfflineRenderer()
            let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let whole = renderer.render(request)
            XCTAssertEqual(whole.plan, runtime.plan)
            XCTAssertTrue(whole.block.interleavedPCM.contains { $0 != 0 })
            for rows in [1,3,5] { assertPCM(whole.block.interleavedPCM, renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM) }
            let effects = whole.diagnostics.portamentoSlideEffects
            XCTAssertTrue(effects.filter { $0.source.rowIndex == 1 && $0.channelIndex == 0 }.allSatisfy(\.effectMemoryMissing))
            XCTAssertEqual(effects.first { $0.source.rowIndex == 4 && $0.channelIndex == 0 }?.slideAmount, 1)
            XCTAssertTrue(effects.filter { $0.source.rowIndex >= 16 }.allSatisfy(\.clamped))
            for d in effects {
                for u in d.stepUpdates {
                    let event = try XCTUnwrap(runtime.events.first { $0.source == d.source && $0.channelIndex == d.channelIndex && $0.syntheticTick == u.syntheticTick && $0.categories.contains("step_update") })
                    guard case let .stepUpdate(index, step) = event.action else { return XCTFail("Expected step update") }
                    XCTAssertEqual(index, d.activeEventIndex); XCTAssertEqual(event.scheduledFrame, u.scheduledFrame)
                    XCTAssertEqual(step, u.playbackStepAfter)
                }
            }
#if DEBUG
            let timing = PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
            let boundaries = [1,3,4,5,8,10,12,14,16].map { timing.frameFor(row: $0) } + [timing.frameFor(row: 4,tick: 1)]
            for offset in [-1,0,1] { assertPCM(whole.block.interleavedPCM, renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries.map { $0+offset }.sorted()).block.interleavedPCM) }
#endif
        }
    }

    private func c(_ effect: UInt8 = 0, _ param: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: param)
    }
    private func adapt(_ rows: [[PlaybackCell]], _ rate: Double, speed: Int = 3, finetune: Int = 0, relative: Int = 0) -> PlaybackSongSyntheticPlan {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0,0.25,0,-0.25], volume: 0.5,
            relativeNote: relative, finetune: finetune, baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
        let song = PlaybackSong(title: "Public Amiga portamento up", orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1,samples: [sample],noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: false)
        return PlaybackSongSyntheticAdapter.adapt(song,orderIndex: 0,sampleRate: rate)
    }
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count,rhs.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(lhs,rhs).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
