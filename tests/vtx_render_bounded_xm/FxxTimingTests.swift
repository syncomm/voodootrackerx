import Foundation
import CryptoKit
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class FxxTimingTests: XCTestCase {
    func testCanonicalClockPhysicalBaseline() throws {
        // Captured twice on clean production ad359d2, before installing the clock (64 public cases).
        let expected = ["true44100": "0e8e52cd019c120059b5f840cfe0d418559ade5d3279e500106c9dc123494a94",
            "true48000": "c54829c314948f96b3d64faef83fb0d5880aa27b0a518ac5828d215350e4aad4",
            "false44100": "eddc7793bc9c39e03f3306fef5e95625eba24d81c395ba3bcf5001e355c88d7b",
            "false48000": "cfafb7ec2f77ed6e09112f6876fb99a6c4b888745b66c2ebd909d741b150c97b"]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            var evidence = Data()
            for cells in clockSentinels {
                let song = clockSong(cells, linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan)
                let clock = plan.canonicalTickClock
                XCTAssertEqual(clock.runs.count, cells.count)
                XCTAssertEqual(clock.totalCanonicalTicks, cells.count * 6)
                for row in cells.indices { for tick in 0..<6 {
                    let coordinate = try XCTUnwrap(clock.coordinate(syntheticRow: row, tick: tick, channel: 0))
                    XCTAssertEqual(coordinate.canonicalTickOrdinal, row * 6 + tick)
                    XCTAssertEqual(coordinate.absoluteFrame, (row * 6 + tick) * (rate == 48_000 ? 960 : 882))
                } }
                // Freeze all ordered payloads, IDs, categories, sources and diagnostics, independently of clock data.
                evidence.append(Data(clockSnapshot(runtime.events).utf8))
                evidence.append(Data(clockSnapshot(runtime.eventStorage.ordering).utf8))
                evidence.append(Data(clockSnapshot(plan.diagnostics).utf8))
                let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: cells.count)
                let pcm = PlaybackSongOfflineRenderer(preparedPlan: plan).render(request).block.interleavedPCM
                pcm.withUnsafeBytes { evidence.append(contentsOf: $0) }
            }
            XCTAssertEqual(SHA256.hash(data: evidence).map { String(format: "%02x", $0) }.joined(), expected["\(linear)\(Int(rate))"])
        } }
    }

    func testCanonicalClockFxxFramesAndNoWriterRows() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let rows = [[cc(), cc()], [cc(15, 3), cc(15, 1)], [cc(15, 1), cc(15, 3)],
                [cc(15, 6), cc(15, 150)], [cc(15, 125), cc(15, 255)], [cc(15, 125), cc(15, 0)], []]
            let song = PlaybackSong(title: "Public Fxx clock", orders: [.init(orderIndex: 0, patternIndex: 0)],
                patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
                instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate), clock = plan.canonicalTickClock
            let frames = rate == 48_000
                ? [[0,960,1920,2880,3840,4800], [5760], [6720,7680,8640], [9600,10400,11200,12000,12800,13600],
                   [14400,14870,15341,15811,16282,16752], [17223,18183,19143,20103,21063,22023]]
                : [[0,882,1764,2646,3528,4410], [5292], [6174,7056,7938], [8820,9555,10290,11025,11760,12495],
                   [13230,13662,14094,14527,14959,15391], [15824,16706,17588,18470,19352,20234]]
            XCTAssertEqual(clock.runs.map(\.firstCanonicalTickOrdinal), [0,6,7,10,16,22,28])
            XCTAssertEqual(clock.runs.map(\.timingRowIndex), Array(0..<7))
            XCTAssertEqual(clock.totalCanonicalTicks, 34)
            XCTAssertEqual(clock.rowTiming.map(\.effectiveSpeed), [6,1,3,6,6,6,6])
            let timing = PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
            for (row, ticks) in frames.enumerated() { for (tick, frame) in ticks.enumerated() { for channel in 0..<2 {
                let value = try XCTUnwrap(clock.coordinate(syntheticRow: row, tick: tick, channel: channel))
                XCTAssertEqual(value, clock.coordinate(syntheticRow: row, tick: tick, channel: channel))
                XCTAssertEqual(value.absoluteFrame, frame)
                XCTAssertEqual(value.absoluteFrame, timing.frameFor(row: row, tick: tick))
                XCTAssertEqual(value.syntheticRow, row); XCTAssertEqual(value.tick, tick); XCTAssertEqual(value.channel, channel)
            } } }
            for (row, tick, channel) in [(-1,0,0), (7,0,0), (0,-1,0), (1,1,0), (0,6,0), (0,0,-1), (0,0,2), (6,0,0), (Int.max,0,0)] {
                XCTAssertNil(clock.coordinate(syntheticRow: row, tick: tick, channel: channel))
            }
            XCTAssertTrue(plan.pattern.events.isEmpty)
            XCTAssertTrue(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan).events.isEmpty)
            let sink = ClockProfileSink(), session = AdapterPlanProfileRecorder(isEnabled: true, sink: sink).beginLifecycle("test")
            let blank = PlaybackSongSyntheticAdapter.adapt(clockSong([cc(), cc(), cc()], linear: linear),
                orderIndex: 0, sampleRate: rate, profileSession: session)
            XCTAssertEqual(blank.canonicalTickClock.totalCanonicalTicks, 18)
            XCTAssertTrue(sink.lines.contains { $0.contains("empty_cell_bypass_count=3") && $0.contains("full_cell_dispatch_count=0") })
        } }
    }

    func testCanonicalClockNonzeroStartLoopsAndJumpsHaveNoPrerollOrExitTick() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let patterns = [[cc(15,1)], [cc(14,0x60), cc(14,0x61), cc(15,3)], [cc(11,4)]]
            let song = PlaybackSong(title: "Public traversal clock",
                orders: [0,1,1,2].enumerated().map { .init(orderIndex: $0.offset, patternIndex: $0.element) },
                patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.enumerated().map { i, cells in
                    (i, .init(index: i, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })) }),
                instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 3, sampleRate: rate)
            let clock = plan.canonicalTickClock
            XCTAssertEqual(plan.diagnostics.rowMappings.map { $0.source.rowIndex }, [0,1,0,1,2,0,1,0,1,2,0])
            XCTAssertEqual(plan.diagnostics.rowMappings.map { $0.source.orderIndex }, [1,1,1,1,1,2,2,2,2,2,3])
            XCTAssertEqual(clock.runs.map(\.firstCanonicalTickOrdinal), [0,6,12,18,24,27,30,33,36,39,42])
            XCTAssertEqual(clock.totalCanonicalTicks, 45)
            for (row, run) in clock.runs.enumerated() {
                XCTAssertEqual(clock.coordinate(syntheticRow: row, tick: 0, channel: 0)?.absoluteFrame,
                    run.firstCanonicalTickOrdinal * (rate == 48_000 ? 960 : 882))
                XCTAssertNil(clock.coordinate(syntheticRow: row, tick: clock.rowTiming[row].effectiveSpeed, channel: 0))
            }
            XCTAssertNil(clock.coordinate(syntheticRow: 11, tick: 0, channel: 0))
        } }
    }

    private final class ClockProfileSink: AdapterPlanProfileSinking {
        var lines = [String]()
        func writeAdapterPlanProfileLine(_ line: String) { lines.append(line) }
    }

    func testCanonicalClockMissingMappedDestinationRetainsSourceIdentity() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let seed = clockSong([cc(note: 49, instrument: 1), cc(14, 0xD3, note: 49, instrument: 8), cc()], linear: linear)
            var instruments = seed.instrumentsByIndex
            instruments[8] = .init(index: 8, samples: [], noteSampleMap: Array(repeating: 1, count: 96))
            let song = PlaybackSong(title: seed.title, orders: seed.orders, patternsByIndex: seed.patternsByIndex,
                instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: seed.initialTiming, usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count, 1); XCTAssertEqual(plan.pattern.events.first?.row, 0)
            XCTAssertTrue(plan.xmEmptyRoutes.isEmpty) // Missing metadata is distinct from the represented empty header sentinel.
            XCTAssertEqual(plan.canonicalTickClock.totalCanonicalTicks, 18)
            XCTAssertEqual(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: 3, channel: 0)?.absoluteFrame,
                rate == 48_000 ? 8640 : 7938)
        } }
    }

    private func clockSnapshot(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.children.isEmpty { return String(describing: value) }
        let fields = mirror.children.map { "\($0.label ?? "_"):\(clockSnapshot($0.value))" }
        // Coverage diagnostics contain dictionaries; iteration order is deliberately not evidence.
        return (mirror.displayStyle == .dictionary || mirror.displayStyle == .set ? fields.sorted() : fields).joined(separator: "|")
    }

    private func cc(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                    instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private var clockSentinels: [[PlaybackCell]] {
        let birth = cc(note: 49, instrument: 1, volume: 0xA4)
        return [[birth, cc(4, 0x48, volume: 0xB8), cc()],
            [birth, cc(3, 4, note: 53), cc(1, 3), cc(2, 2), cc(14, 0x11), cc(14, 0x21),
             cc(33, 0x11), cc(0, 0x37), cc(4, 0x21), cc(4, 0x56, volume: 0xB3), cc(6, 2), cc(14, 0x44), cc()],
            [birth, cc(14, 0xD3, instrument: 2, volume: 0xB8), cc()],
            [birth, cc(14, 0x44), cc(14, 0x93), cc(14, 0x90), cc(27, 0x93), cc()],
            [cc(14, 0x11, note: 49, instrument: 1), cc(33, 0x11, note: 53, instrument: 1)],
            [cc(note: 49, instrument: 7), cc(14, 0x11), cc()],
            [birth, cc(0, 0x37), cc(4, 0x48, volume: 0xB8), cc()],
            [cc(4, 0x48, note: 49, instrument: 1), cc(note: 49, instrument: 2), cc()]]
            + [0xD0, 0xD3, 0xD6].map { [birth, cc(14, UInt8($0), note: 49, instrument: 2, volume: 0xB8), cc()] }
            + [3, 4, 5, 6, 99].map { [birth, cc(14, 0xD3, note: 49, instrument: UInt8($0), volume: 0xB8), cc()] }
    }

    private func clockSong(_ cells: [PlaybackCell], linear: Bool) -> PlaybackSong {
        // Instruments 3...7 distinguish empty, refused, nil-map (OPEN Policy B gap), quiet PCM and zero pitch.
        var instruments = [Int: PlaybackInstrument]()
        for i in 1...7 where i != 3 {
            let sample = PlaybackSample(instrumentIndex: i, sampleIndex: 0,
                pcm: (0..<32_768).map { Float(($0 * 137 + 731) % 16_384 - 8_192) / 32_768 },
                volume: i == 6 ? 0 : 0.5, relativeNote: i == 4 ? 96 : i == 7 ? -49 : 0,
                finetune: 0, baseSampleRate: 8363)
            instruments[i] = .init(index: i, samples: [sample], noteSampleMap: i == 5 ? nil : Array(repeating: 0, count: 96))
        }
        instruments[3] = .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96))
        return .init(title: "Public clock sentinels", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 40, panning: 128, finetune: 24, relativeNote: 12)]])
    }

    func testParsedFixtureMixedTimingControlsBoundedAndWindowedRenders() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("reference-xm/generated/fxx-timing.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
        let rows = try XCTUnwrap(song.patternsByIndex[0]).rows
        XCTAssertEqual(rows.map { $0.cells[0].effectParam },
                       [0, 3, 0, 150, 0, 6, 125, 31, 32, 255, 3, 32, 3, 0, 6, 0])
        XCTAssertEqual(rows.map { $0.cells[1].effectParam },
                       [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 125, 150, 0, 0, 0])
        XCTAssertTrue(rows.flatMap(\.cells).allSatisfy { $0.effectType == 0 || $0.effectType == 0x0F })
        let plan = PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: 48_000)
        let starts = [0, 5_760, 8_640, 11_520, 13_920, 16_320, 21_120, 26_880,
                      56_640, 172_890, 187_478, 190_301, 196_061, 198_461, 200_861, 205_661]
        XCTAssertEqual(plan.rowTimings.map(\.rowStartFrame), starts)
        XCTAssertEqual(plan.rowTimings.map(\.effectiveSpeed), [6, 3, 3, 3, 3, 6, 6, 31, 31, 31, 6, 6, 3, 3, 6, 6])
        XCTAssertEqual(plan.rowTimings.map(\.effectiveBPM), [125, 125, 125, 150, 150, 150, 125, 125, 32, 255, 255, 125, 150, 150, 150, 150])
        let conflicts = plan.timingChanges.filter { (10...12).contains($0.source.rowIndex) }
        XCTAssertEqual(conflicts.map(\.channelIndex), [0, 1, 0, 1, 0, 1])
        XCTAssertEqual(conflicts.map(\.appliesToSyntheticRowAfter), [10, 10, 11, 11, 12, 12])
        let request = PlaybackSongOfflineRenderRequest(
            song: song, config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2), rows: 16
        )
        XCTAssertEqual(request.requestedFrameCount, 210_461)
        let renderer = PlaybackSongOfflineRenderer()
        let bounded = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 3)
        XCTAssertEqual(bounded.diagnostics.rowTiming, plan.rowTimingDiagnostics)
        XCTAssertEqual(bounded.plan.pattern.events.map(\.scheduledStartFrame), starts.map(Optional.some))
        XCTAssertEqual(bounded.block.interleavedPCM.count, 210_461 * 2)
        XCTAssertTrue(bounded.block.interleavedPCM.contains { $0 != 0 })
        XCTAssertEqual(windowed.block.interleavedPCM, bounded.block.interleavedPCM)
    }

    func testSpeedAppliesToCommandRowAndFollowingRows() {
        for speed in [3, 6, 31] {
            let plan = timingPlan(parameter: UInt8(speed), initialSpeed: 4, initialBPM: 125)
            XCTAssertEqual(plan.rowTimings.map(\.effectiveSpeed), [4, speed, speed, speed, speed])
            XCTAssertEqual(plan.rowTimings.map(\.effectiveBPM), [125, 125, 125, 125, 125])
            XCTAssertEqual(plan.rowTimings.map(\.rowStartFrame),
                           [0, 3_840, 3_840 + speed * 960, 3_840 + speed * 1_920, 3_840 + speed * 2_880])
            XCTAssertEqual(plan.rowTimings[1].rowDurationFrames, speed * 960)
            XCTAssertEqual(plan.frameFor(row: 1, tick: 1), 4_800)
            XCTAssertEqual(plan.frameFor(row: 1, tick: speed - 1), 3_840 + (speed - 1) * 960)
            XCTAssertEqual(plan.frameFor(row: 1, tick: speed), plan.frameFor(row: 1, tick: speed - 1))
            XCTAssertEqual(plan.timingChanges.first?.appliesToSyntheticRowAfter, 1)
        }
    }

    func testBPMStartsAtTickZeroOfCommandRowWithoutAccumulatedBoundaryDrift() {
        let cases: [(UInt8, [Int], Int, Int)] = [
            (0x20, [0, 1_440, 12_690, 23_940, 35_190], 5_190, 46_440),
            (0x7D, [0, 1_440, 4_320, 7_200, 10_080], 2_400, 12_960),
            (0x96, [0, 1_440, 3_840, 6_240, 8_640], 2_240, 11_040),
            (0xFF, [0, 1_440, 2_851, 4_263, 5_675], 1_910, 7_087),
        ]
        for (bpm, starts, firstTick, end) in cases {
            let plan = timingPlan(parameter: bpm, initialSpeed: 3, initialBPM: 250)
            XCTAssertEqual(plan.frameFor(row: 0, tick: 1), 480)
            XCTAssertEqual(plan.rowTimings.map(\.rowStartFrame), starts)
            XCTAssertEqual(plan.rowTimings.map(\.effectiveSpeed), [3, 3, 3, 3, 3])
            XCTAssertEqual(plan.rowTimings.map(\.effectiveBPM), [250] + Array(repeating: Int(bpm), count: 4))
            XCTAssertEqual(plan.frameFor(row: 1, tick: 1), firstTick)
            XCTAssertEqual(plan.frameFor(row: 5), end)
            XCTAssertEqual(plan.rowTimings[1].rowEndExactFrame - plan.rowTimings[1].rowStartExactFrame,
                           3 * 120_000 / Double(bpm), accuracy: 1e-9)
        }
    }

    private func timingPlan(parameter: UInt8, initialSpeed: Int, initialBPM: Int) -> PlaybackSongFxxTimingPlan {
        let rows = (0..<5).map { row in
            PlaybackRow(index: row, cells: [PlaybackCell(
                note: 0, instrument: 0, volumeColumn: 0,
                effectType: row == 1 ? 0x0F : 0, effectParam: row == 1 ? parameter : 0
            )])
        }
        let song = PlaybackSong(
            title: "Fxx boundaries", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: rows)], instrumentsByIndex: [:],
            restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: initialSpeed, bpm: initialBPM)
        )
        return PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: 48_000)
    }
}
