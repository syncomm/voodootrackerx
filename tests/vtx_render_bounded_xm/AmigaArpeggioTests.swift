import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class AmigaArpeggioTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]
    // Observed pinned FT2 phases; independent of the production selector.
    private let phases = [[0], [0,1], [0,2,1], [0,0,2,1], [0,1,0,2,1],
                          [0,2,1,0,2,1], [0,0,2,1,0,2,1], [0,1,0,2,1,0,2,1]]

    func testAllSpeedsNibblesPeriodsAndFrames() throws {
        let periods = [0:1712.0, 1:1616, 3:1440, 7:1140, 15:720]
        for rate in rates {
            for speed in 1...8 {
                for parameter: UInt8 in [0x37, 0x73, 0x11, 0x10, 0x01, 0xF1, 0x1F, 0] {
                    let plan = adapt([[c(parameter, note: 49, instrument: 1)], [c()]], rate, speed: speed)
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    XCTAssertEqual(plan.pattern.events[0].playbackStep, step(1712 * 4, rate), accuracy: 1e-12)
                    if parameter == 0 { XCTAssertTrue(plan.diagnostics.arpeggioEffects.isEmpty); continue }
                    let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                    let ticks = d.stepUpdates.filter { $0.syntheticTick < speed }
                    let offsets = phases[speed-1].map { [0, Int(parameter >> 4), Int(parameter & 15)][$0] }
                    XCTAssertEqual(d.status, .applied)
                    XCTAssertEqual(ticks.map(\.syntheticTick), Array(1..<speed))
                    XCTAssertEqual(ticks.map(\.scheduledFrame), (1..<speed).map { $0 * Int(rate / 50) })
                    XCTAssertEqual(ticks.map(\.amigaPeriodAfter), offsets.dropFirst().map { periods[$0]! * 4 })
                    XCTAssertNil(d.currentLinearPeriodBefore)
                    XCTAssertEqual(d.currentAmigaPeriodBefore, 6848)
                    XCTAssertEqual(d.currentAmigaPeriodAfter, 6848)
                    for u in ticks { XCTAssertEqual(u.playbackStepAfter, step(try XCTUnwrap(u.amigaPeriodAfter), rate), accuracy: 1e-12) }
                }
            }
        }
    }

    func testPinnedFinetunesRelativeNotesAndOctaveCrossings() throws {
        // Project-authored controls observed at both rates. Periods are native FT2
        // [base, +7, +3]; these vectors do not derive expected values from VTX.
        let vectors: [(UInt8, Int, Int, [Double])] = [
            (25, -128, 0, [7256, 4832, 6096]),
            (25, -64, 0, [7048, 4704, 5928]),
            (25, -1, 0, [6872, 4580, 5780]),
            (25, 0, 0, [6848, 4560, 5760]),
            (25, 1, 0, [6848, 4560, 5760]),
            (25, 64, 0, [6656, 4440, 5592]),
            (25, 127, 0, [6488, 4324, 5448]),
            (48, -128, 0, [1920, 1280, 1616]),
            (48, -64, 0, [1868, 1246, 1570]),
            (48, -1, 0, [1821, 1214, 1530]),
            (48, 0, -12, [3628, 2416, 3048]),
            (48, 0, 0, [1814, 1208, 1524]),
            (48, 0, 12, [907, 604, 762]),
            (48, 1, 0, [1814, 1208, 1524]),
            (48, 64, 0, [1762, 1176, 1482]),
            (48, 127, 0, [1718, 1145, 1445]),
            (61, -128, 0, [907, 604, 762]),
            (61, -64, 0, [881, 588, 741]),
            (61, -1, 0, [859, 572, 722]),
            (61, 0, -12, [1712, 1140, 1440]),
            (61, 0, 0, [856, 570, 720]),
            (61, 0, 12, [428, 285, 360]),
            (61, 1, 0, [856, 570, 720]),
            (61, 64, 0, [832, 555, 699]),
            (61, 127, -12, [1622, 1081, 1362]),
            (61, 127, 0, [811, 540, 681]),
            (61, 127, 12, [405, 270, 340]),
        ]
        for rate in rates {
            for (note, fine, relative, native) in vectors {
                let plan = adapt([[c(0x37, note: note, instrument: 1)], [c()]], rate, fine: fine, relative: relative)
                let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                let expected = [native[1],native[2],native[0],native[1],native[2],native[0]].map { $0 * 4 }
                XCTAssertEqual(d.currentAmigaPeriodBefore, native[0] * 4)
                XCTAssertEqual(d.stepUpdates.map(\.amigaPeriodAfter), expected, "note \(note), fine \(fine), relative \(relative)")
                let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
                XCTAssertEqual(mapping.effectiveFinetune, fine)
                XCTAssertEqual(mapping.effectiveNoteValue, Int(note) + relative)
                for u in d.stepUpdates { XCTAssertEqual(u.playbackStepAfter, step(try XCTUnwrap(u.amigaPeriodAfter), rate), accuracy: 1e-12) }
            }
        }
    }

    func testFxxBeforeAndAfterFreshNoteOnlyActiveAndReleasedSources() throws {
        for rate in rates {
            for speed in [1,2,3,4,6,7] {
                for channel in [0,1] {
                    for shape in 0..<4 {
                        var rows = Array(repeating: [c(),c()], count: 4)
                        rows[0][channel] = c(note: 49, instrument: 1)
                        if shape == 3 { rows[1][channel] = c(note: 97) }
                        rows[2][channel] = c(0x37, note: shape < 2 ? 49 : 0, instrument: shape == 0 ? 1 : 0)
                        rows[2][1-channel] = c(UInt8(speed), effect: 15)
                        let plan = adapt(rows, rate, speed: 8)
                        let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                        let first = shape < 2 ? 1 : 0
                        let ticks = d.stepUpdates.filter { $0.syntheticTick < speed }
                        XCTAssertEqual(d.rowSpeed, speed)
                        XCTAssertEqual(plan.pattern.events.count, shape < 2 ? 2 : 1)
                        XCTAssertEqual(d.activeEventIndex, shape < 2 ? 1 : 0)
                        XCTAssertEqual(ticks.map(\.scheduledFrame), (first..<speed).map { (16+$0)*Int(rate/50) })
                        let native = [1712.0,1440,1140]
                        XCTAssertEqual(ticks.map(\.amigaPeriodAfter), phases[speed-1].dropFirst(first).map { native[$0]*4 })
                        if shape == 3 { XCTAssertEqual(plan.pattern.events[0].keyOffFrame, 8*Int(rate/50)) }
                    }
                }
            }
        }
    }

    func test000DoesNotReplayAndColdChannelsDoNotInventPitchOrSources() throws {
        for rate in rates {
            let plan = adapt([[c(0x37, note: 49, instrument: 1)], [c()], [c(0x73)], [c()]], rate)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.arpeggioEffects.map(\.syntheticRow), [0,2])
            XCTAssertTrue(plan.diagnostics.arpeggioEffects.allSatisfy { !$0.effectMemoryDeferred && $0.activeEventIndex == 0 })
            XCTAssertEqual(plan.diagnostics.arpeggioEffects.last?.stepUpdates.map(\.amigaPeriodAfter), [6848,5760,4560,6848,5760,4560,6848])
            let during000 = plan.diagnostics.arpeggioEffects.flatMap(\.stepUpdates).filter {
                $0.scheduledFrame >= 6*Int(rate/50) && $0.scheduledFrame < 12*Int(rate/50)
            }
            // Only the outgoing nonzero row's base restoration exists at this boundary.
            XCTAssertEqual(during000.count, 1)
            XCTAssertEqual(during000.first?.syntheticTick, 6)
            XCTAssertEqual(during000.first?.amigaPeriodAfter, 6848)
            let cold = adapt([[c(0x37)], [c()], [c(0x73)]], rate)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertTrue(cold.diagnostics.arpeggioEffects.allSatisfy { $0.status == .noActiveVoice && $0.stepUpdates.isEmpty })
        }
    }

    func testG30HighAndLowBaseRangePolicyStaysWithExistingPitchResolver() throws {
        for rate in rates {
            // Baseline VTX 4x periods, deliberately distinct from FT2 range policy.
            let edges: [(UInt8, Int, Int, Double, [Double])] = [
                (96,0,0,452,[300,380,452,300,380,452]),
                (1,0,-128,116096,[77312,97536,116096,77312,97536,116096]),
                (1,-12,0,109568,Array(repeating: 109568, count: 5)),
            ]
            for (note, relative, fine, base, expected) in edges {
                let plan = adapt([[c(0x37, note: note, instrument: 1)], [c()]], rate, fine: fine, relative: relative)
                let d = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
                XCTAssertEqual(d.currentAmigaPeriodBefore, base)
                XCTAssertEqual(d.stepUpdates.map(\.amigaPeriodAfter), expected)
                let offsets = [7,3,0,7,3,0]
                for (u, offset) in zip(d.stepUpdates, offsets) {
                    XCTAssertEqual(Adapter.arpeggioSemitoneOffset(effectiveSpeed: 6, tick: u.syntheticTick, x: 3, y: 7), offset)
                    let target = try XCTUnwrap(Adapter.amigaPitchTarget(note: note, relativeNote: relative+offset,
                        finetune: fine, baseSampleRate: 8363, outputSampleRate: rate))
                    XCTAssertEqual(u.amigaPeriodAfter, target.amigaPeriod)
                    XCTAssertEqual(u.playbackStepAfter, target.playbackStep)
                }
            }
        }
    }

    func testPublicFixtureWholeWindowRuntimeAndDiagnostics() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/amiga-arpeggio-ordering.xm")
        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        XCTAssertFalse(song.usesLinearFrequencyTable)
        for rate in rates {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            for rows in [1,2,5] { assertPCM(full.block.interleavedPCM, renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM) }
            let ds = full.diagnostics.arpeggioEffects
            XCTAssertTrue(Set([3,6,7]).isSubset(of: Set(ds.map(\.rowSpeed))))
            let updates = runtime.events.filter { $0.categories.contains("arpeggio_0xy") && $0.categories.contains("step_update") }
            XCTAssertEqual(updates.count, ds.flatMap(\.stepUpdates).count)
            for d in ds {
                for u in d.stepUpdates {
                    let event = try XCTUnwrap(updates.first { $0.source == d.source && $0.channelIndex == d.channelIndex && $0.syntheticTick == u.syntheticTick })
                    XCTAssertEqual(event.scheduledFrame, u.scheduledFrame)
                    guard case let .stepUpdate(index, step) = event.action else { return XCTFail("Expected pitch update") }
                    XCTAssertEqual(index, d.activeEventIndex); XCTAssertEqual(step, u.playbackStepAfter)
                }
            }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let diagnostics = try XCTUnwrap(json["arpeggio_effects"] as? [[String: Any]])
            XCTAssertTrue(diagnostics.allSatisfy { $0["frequency_table"] as? String == "amiga" })
            let steps = try XCTUnwrap(diagnostics.first?["step_updates"] as? [[String: Any]])
            XCTAssertNotNil(steps.first?["amiga_period_after"] as? Double)
            XCTAssertNotNil(steps.first?["selected_semitone_offset"] as? Int)
#if DEBUG
            let boundaries = Set(ds.flatMap(\.stepUpdates).map(\.scheduledFrame)).filter { $0 > 1 && $0+1 < request.boundedFrameCount }.sorted()
            for offset in [-1,0,1] {
                assertPCM(full.block.interleavedPCM, renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries.map { $0+offset }).block.interleavedPCM)
            }
#endif
        }
    }

    private func step(_ period: Double, _ rate: Double) -> Double { Adapter.playbackStep(amigaPeriod: period, baseSampleRate: 8363, outputSampleRate: rate)! }
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs,rhs).map { abs($0-$1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func c(_ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, effect: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }
    private func adapt(_ rows: [[PlaybackCell]], _ rate: Double, speed: Int = 6, fine: Int = 0, relative: Int = 0) -> PlaybackSongSyntheticPlan {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: (0..<256).map { Float(sin(Double($0) * .pi / 8)/16) }, volume: 0.5,
            panning: 128, relativeNote: relative, finetune: fine, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        let song = PlaybackSong(title: "Public Amiga arpeggio", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2-$0.element.count)) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: false)
        return Adapter.adapt(song, orderIndex: 0, sampleRate: rate)
    }
}
