import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class LinearArpeggioOrderingTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    // Independently observed FT2 phases, including tick zero; 1 = x, 2 = y.
    private let phases = [[0], [0,1], [0,2,1], [0,0,2,1], [0,1,0,2,1],
                          [0,2,1,0,2,1], [0,0,2,1,0,2,1], [0,1,0,2,1,0,2,1]]
    private let rates = [44_100.0, 48_000]

    func testPinnedInRangeVectorsAndFramesAtAllSpeedsAndNibbles() throws {
        for rate in rates {
            for speed in 1...8 {
                for parameter: UInt8 in [0x37, 0x73, 0x11, 0x10, 0x01, 0xF1, 0x1F] {
                    let expected = offsets(speed, parameter)
                    XCTAssertEqual((0..<speed).map {
                        Adapter.arpeggioSemitoneOffset(effectiveSpeed: speed, tick: $0,
                            x: Int(parameter >> 4), y: Int(parameter & 15))
                    }, expected)
                    for note: UInt8 in [1, 49, 81] {
                        let plan = adapt([[c(parameter, note: note, instrument: 1)], [c()]], rate, speed: speed)
                        let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                        let base = 7680 - Double(note - 1) * 64
                        XCTAssertEqual(plan.pattern.events.count, 1)
                        XCTAssertEqual(plan.pattern.events[0].playbackStep, step(base, rate), accuracy: 1e-12)
                        let ticks = d.stepUpdates.filter { $0.syntheticTick < speed }
                        XCTAssertEqual(ticks.map(\.syntheticTick), Array(1..<speed))
                        XCTAssertEqual(ticks.map(\.scheduledFrame), (1..<speed).map { $0 * Int(rate / 50) })
                        XCTAssertEqual(ticks.map(\.linearPeriodAfter), expected.dropFirst().map { base - Double($0) * 64 })
                        for u in ticks { XCTAssertEqual(u.playbackStepAfter, step(u.linearPeriodAfter, rate), accuracy: 1e-12) }
                        XCTAssertEqual(d.currentLinearPeriodAfter, base)
                    }
                }
            }
        }
        XCTAssertEqual(Adapter.arpeggioSemitoneOffset(effectiveSpeed: 0, tick: 0, x: 3, y: 7), 0)
        XCTAssertEqual(Adapter.arpeggioSemitoneOffset(effectiveSpeed: Int.max, tick: -1, x: 3, y: 7), 0)
    }

    func testSameRowFxxBeforeAndAfterWithFreshNoteOnlyActiveAndReleasedSources() throws {
        for rate in rates {
            for speed in [1, 2, 3, 4, 6, 7] {
                for channel in [0, 1] {
                    for shape in 0..<4 {
                        var rows = Array(repeating: [c(), c()], count: 4)
                        rows[0][channel] = c(note: 49, instrument: 1)
                        if shape == 3 { rows[1][channel] = c(note: 97) }
                        rows[2][channel] = c(0x37, note: shape < 2 ? 49 : 0, instrument: shape == 0 ? 1 : 0)
                        rows[2][1-channel] = c(effect: 15, parameter: UInt8(speed))
                        let plan = adapt(rows, rate, speed: 8)
                        let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                        XCTAssertEqual(d.rowSpeed, speed)
                        XCTAssertEqual(plan.pattern.events.count, shape < 2 ? 2 : 1)
                        XCTAssertEqual(d.activeEventIndex, shape < 2 ? 1 : 0)
                        let first = shape < 2 ? 1 : 0
                        let ticks = d.stepUpdates.filter { $0.syntheticTick < speed }
                        XCTAssertEqual(ticks.map(\.syntheticTick), Array(first..<speed))
                        XCTAssertEqual(ticks.map(\.scheduledFrame), (first..<speed).map { (16 + $0) * Int(rate / 50) })
                        XCTAssertEqual(ticks.map(\.linearPeriodAfter), offsets(speed, 0x37).dropFirst(first).map { 4608 - Double($0) * 64 })
                        XCTAssertEqual(d.currentLinearPeriodAfter, 4608)
                        if shape == 3 { XCTAssertEqual(plan.pattern.events[0].keyOffFrame, 8 * Int(rate / 50)) }
                    }
                }
            }
        }
    }

    func test000AndBlankRowsNeverReplayOrInventAnOwner() throws {
        for rate in rates {
            let plan = adapt([[c(0x37, note: 49, instrument: 1)], [c()], [c(0x73)], [c()]], rate)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.arpeggioEffects.map(\.syntheticRow), [0, 2])
            XCTAssertTrue(plan.diagnostics.arpeggioEffects.allSatisfy { !$0.effectMemoryDeferred && $0.activeEventIndex == 0 })
            let later = try XCTUnwrap(plan.diagnostics.arpeggioEffects.last)
            XCTAssertEqual(later.stepUpdates.filter { $0.syntheticTick < 6 }.map(\.linearPeriodAfter), [4608,4416,4160,4608,4416,4160])
            // The outgoing command restores base at the row boundary; 000 itself emits nothing.
            XCTAssertTrue(plan.diagnostics.arpeggioEffects.flatMap(\.stepUpdates).filter {
                $0.scheduledFrame >= 6 * Int(rate / 50) && $0.scheduledFrame < 12 * Int(rate / 50)
            }.allSatisfy { $0.syntheticTick == 6 && $0.linearPeriodAfter == 4608 })
            let cold = adapt([[c(0x37)], [c()], [c(0x73)]], rate)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertTrue(cold.diagnostics.arpeggioEffects.allSatisfy { $0.status == .noActiveVoice && $0.stepUpdates.isEmpty })
            XCTAssertTrue(adapt([[c(note: 49, instrument: 1)], [c()]], rate).diagnostics.arpeggioEffects.isEmpty)
        }
    }

    func testTunedPitchAndExplicitG30UpperBoundaryPreserveExistingConversion() throws {
        for rate in rates {
            for (fine, base): (Int, Double) in [(8,4412), (1,4416)] {
                let plan = adapt([[c(0x37, note: 49, instrument: 1)], [c()]], rate, finetune: fine, relative: 3)
                XCTAssertEqual(plan.pattern.events[0].playbackStep, step(base, rate), accuracy: 1e-12)
                let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                XCTAssertEqual(d.stepUpdates.map(\.linearPeriodAfter), [base-448,base-192,base,base-448,base-192,base])
            }
            let plan = adapt([[c(0x37, note: 96, instrument: 1)], [c()]], rate)
            let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
            XCTAssertEqual(offsets(6, 0x37), [0,7,3,0,7,3])
            // FT2's raised targets are 1540. G30 owns that range policy; keep VTX's arithmetic.
            XCTAssertEqual(d.stepUpdates.map(\.linearPeriodAfter), [1152,1408,1600,1152,1408,1600])
            for u in d.stepUpdates { XCTAssertEqual(u.playbackStepAfter, step(u.linearPeriodAfter, rate), accuracy: 1e-12) }
        }
    }

    func testCarriedPitchAndLaterVibratoStateStayOwnedByExistingEngines() {
        for command: UInt8 in [1, 2, 3, 5, 14, 33] {
            let parameter: UInt8 = command == 14 || command == 33 ? 0x11 : 4
            let plan = adapt([[c(note: 49, instrument: 1)], [c(note: command == 3 || command == 5 ? 53 : 0, effect: command, parameter: parameter)], [c(0x37)], [c()]], 48000)
            let d = plan.diagnostics.arpeggioEffects[0], base = d.currentLinearPeriodBefore!
            XCTAssertEqual(d.stepUpdates.map(\.linearPeriodAfter), [base,base-448,base-192,base,base-448,base-192,base])
            XCTAssertEqual(d.currentLinearPeriodAfter, base)
            XCTAssertEqual(plan.pattern.events.count, 1)
        }
        for writer: UInt8 in [4, 6, 7] {
            func module(_ middle: PlaybackCell) -> PlaybackSongSyntheticPlan {
                adapt([[c(note: 49, instrument: 1)], [c(effect: writer, parameter: 0x48)], [middle], [c(effect: writer)]], 48000)
            }
            let arp = module(c(0x37)), blank = module(c())
            if writer == 7 {
                XCTAssertEqual(arp.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 3 }, blank.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 3 })
            } else {
                XCTAssertEqual(arp.diagnostics.vibratoEffects.filter { $0.syntheticRow == 3 }, blank.diagnostics.vibratoEffects.filter { $0.syntheticRow == 3 })
            }
        }
    }

    func testPublicFixtureWholeWindowRuntimePlanAndSelectedOffsetDiagnostics() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/linear-arpeggio-ordering.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in rates {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            for rows in [1, 2, 5] { assertPCM(full.block.interleavedPCM, renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM) }
            let d = full.diagnostics.arpeggioEffects
            XCTAssertTrue(Set([2,3,6,7]).isSubset(of: Set(d.map(\.rowSpeed))))
            let updates = runtime.events.filter { $0.categories.contains("arpeggio_0xy") && $0.categories.contains("step_update") }
            XCTAssertEqual(updates.count, d.flatMap(\.stepUpdates).count)
            for diagnostic in d {
                for update in diagnostic.stepUpdates {
                    let event = try XCTUnwrap(updates.first { $0.source == diagnostic.source && $0.channelIndex == diagnostic.channelIndex && $0.syntheticTick == update.syntheticTick })
                    XCTAssertEqual(event.scheduledFrame, update.scheduledFrame)
                    guard case let .stepUpdate(index, step) = event.action else { return XCTFail("Expected pitch update") }
                    XCTAssertEqual(index, diagnostic.activeEventIndex); XCTAssertEqual(step, update.playbackStepAfter)
                }
            }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let diagnostics = try XCTUnwrap(json["arpeggio_effects"] as? [[String: Any]])
            let edge = try XCTUnwrap(diagnostics.first { $0["synthetic_row"] as? Int == 14 })
            let steps = try XCTUnwrap(edge["step_updates"] as? [[String: Any]])
            XCTAssertEqual(steps.compactMap { $0["selected_semitone_offset"] as? Int }, [7,3,0,7,3,0])
#if DEBUG
            let boundaries = Set(d.flatMap(\.stepUpdates).map(\.scheduledFrame)).filter { $0 > 1 && $0 + 1 < request.boundedFrameCount }.sorted()
            for offset in [-1, 0, 1] {
                assertPCM(full.block.interleavedPCM, renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries.map { $0 + offset }).block.interleavedPCM)
            }
#endif
        }
    }

    private func offsets(_ speed: Int, _ parameter: UInt8) -> [Int] {
        phases[speed-1].map { [0, Int(parameter >> 4), Int(parameter & 15)][$0] }
    }
    private func step(_ period: Double, _ rate: Double) -> Double { Adapter.playbackStep(linearPeriod: period, baseSampleRate: 8363, outputSampleRate: rate)! }
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0-$1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func c(_ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, effect: UInt8 = 0, parameter explicit: UInt8? = nil) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: explicit ?? parameter)
    }
    private func adapt(_ rows: [[PlaybackCell]], _ rate: Double, speed: Int = 6, finetune: Int = 0, relative: Int = 0, linear: Bool = true) -> PlaybackSongSyntheticPlan {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: (0..<256).map { Float(sin(Double($0) * .pi / 8) / 16) }, volume: 0.5,
            panning: 128, relativeNote: relative, finetune: finetune, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        let song = PlaybackSong(title: "Public Linear arpeggio", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2-$0.element.count)) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear)
        return Adapter.adapt(song, orderIndex: 0, sampleRate: rate)
    }
}
