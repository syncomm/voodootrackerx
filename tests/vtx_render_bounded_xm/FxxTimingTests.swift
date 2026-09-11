import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class FxxTimingTests: XCTestCase {
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
