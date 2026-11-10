import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Direct construction tests; the normal-Play integration witness remains open (#516).
final class ColdEntryTests: XCTestCase {
    func testColdOrderAndRowUseFreshTimingSourcesAndIndependentIsolatedPCM() throws {
        let source = try fixture()
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(source, linear: linear), tick = Int(rate / 50)
            let order = adapt(input, rate, order: 1, row: 0)
            XCTAssertEqual(Array(order.diagnostics.rowTiming.prefix(3)).map(\.rowStartFrame), [0, 6*tick, 7*tick])
            XCTAssertFalse(order.diagnostics.eventMappings.contains { $0.syntheticRow == 0 && $0.channelIndex == 1 })
            let cold = adapt(input, rate, order: 1, row: 3)
            XCTAssertEqual(cold.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6*tick, 12*tick])
            XCTAssertEqual(cold.diagnostics.rowMappings.map(\.source), (3...5).map {
                .init(orderIndex: 1, patternIndex: 1, rowIndex: $0)
            })
            XCTAssertEqual(cold.diagnostics.eventMappings.map(\.channelIndex), [0, 0, 0])
            XCTAssertEqual(cold.pattern.events.map(\.row), [0, 1, 2])
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: cold)
            let births = runtime.events.filter { if case .noteTrigger = $0.action { return true }; return false }
            XCTAssertEqual(births.map(\.activeEventIndex), [0, 1, 2])
            XCTAssertEqual(births.map(\.channelIndex), [0, 0, 0])
            XCTAssertEqual(births.map(\.source.rowIndex), [3, 4, 5])
            XCTAssertEqual(births.map(\.scheduledFrame), [0, 6*tick, 12*tick])
            XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count)
            // Independently authored isolated notes share only the reviewed sample.
            let isolated = song(source, linear: linear, patterns: [0: pattern(0, [51, 53, 55].map {
                [cell(note: UInt8($0), instrument: 1), cell(note: UInt8($0)), cell()]
            })], orders: [.init(orderIndex: 0, patternIndex: 0)])
            let oracle = adapt(isolated, rate, order: 0, row: 0)
            XCTAssertEqual(cold.pattern.events, oracle.pattern.events)
            let rendered = render(input, cold, rate)
            XCTAssertEqual(rendered.block.interleavedPCM, render(isolated, oracle, rate).block.interleavedPCM)
            XCTAssertEqual(rendered.scheduledVoiceRejectionReasons.count, 3)
            XCTAssertTrue(rendered.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
        } }
    }

    func testStructuralAnchorDoesNotExecuteSkippedMusicOrOtherChannelHistory() throws {
        let source = try fixture()
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(source, linear: linear), tick = Int(rate / 50)
            let plan = adapt(input, rate, order: 1, row: 2)
            XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.rowIndex), [2, 1, 2, 3, 4, 5])
            XCTAssertEqual(plan.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6*tick, 7*tick, 8*tick, 9*tick, 10*tick])
            XCTAssertEqual(plan.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 1, 1, 1, 1, 1])
            let loops = plan.diagnostics.traversalDiagnostics
            XCTAssertEqual(loops.filter(\.loopTaken).map(\.loopStartRowIndex), [1])
            XCTAssertEqual(loops.first?.source.rowIndex, 2)
            XCTAssertEqual(loops.first?.syntheticRow, 0)
            // A different channel's row-1 anchor and an earlier order's row-2
            // anchor cannot override channel 0's implicit row zero.
            let earlier = pattern(0, [[cell()], [cell()], [cell(14, 0x60)]])
            let target = pattern(1, [[cell()], [cell(), cell(14, 0x60)], [cell(14, 0x61)], [cell()]])
            let independent = song(source, linear: linear, patterns: [0: earlier, 1: target])
            let control = adapt(independent, rate, order: 1, row: 2)
            XCTAssertEqual(control.diagnostics.rowMappings.map(\.source.rowIndex), [2, 0, 1, 2, 3])
            XCTAssertEqual(control.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6*tick, 12*tick, 18*tick, 24*tick])
        } }
    }

    func testEntryDoesNotBecomeTraversalFloorAndWriterPrecedenceSurvives() throws {
        let source = try fixture()
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (commands, owner, targetRow) in [
                ([cell(11, 0), cell(13, 1), cell(14, 0x61)], 2, 2),
                ([cell(14, 0x61), cell(13, 1), cell(11, 0)], 0, 0),
                ([cell(11, 0), cell(14, 0x61), cell(13, 1)], 1, 1)
            ] {
                var anchor = Array(repeating: cell(), count: 3); anchor[owner] = cell(14, 0x60)
                let input = song(source, linear: linear, patterns: [
                    0: pattern(0, Array(repeating: [cell(11, 2)], count: 3)),
                    1: pattern(1, [[cell()], [cell(15, 1)], anchor, commands])
                ])
                let plan = adapt(input, rate, order: 1, row: 3)
                XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.orderIndex), [1, 0])
                XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source.rowIndex), [3, targetRow])
                XCTAssertEqual(plan.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6 * Int(rate / 50)])
                let bounded = PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 1, orderCount: 1,
                    sampleRate: rate, initialPosition: .init(orderIndex: 1, patternIndex: 1, rowIndex: 3))
                XCTAssertEqual(bounded.diagnostics.rowMappings.map(\.source.rowIndex), [3])
            }
        } }
    }

    func testDefaultAndRangeForwardingKeepCompletePlansAndEventIdentities() throws {
        let source = try fixture()
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(source, linear: linear)
            let full = PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 0, orderCount: 2, sampleRate: rate)
            let explicit = adapt(input, rate, order: 0, row: 0)
            XCTAssertEqual(full, explicit)
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate).events,
                RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: explicit).events)
            let range = PlaybackSongSyntheticAdapter.adapt(input, orderRange: 1..<2, sampleRate: rate)
            XCTAssertEqual(range, PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 1, orderCount: 1,
                sampleRate: rate, initialPosition: .init(orderIndex: 1, patternIndex: 1, rowIndex: 0)))
        } }
    }

    func testExplicitPositionsRejectInvalidRequestsAndRetainSourceRowLabels() throws {
        let source = try fixture()
        for position in [PlaybackPosition(orderIndex: -1, patternIndex: 1, rowIndex: 0),
                         .init(orderIndex: 2, patternIndex: 1, rowIndex: 0),
                         .init(orderIndex: 1, patternIndex: 0, rowIndex: 0),
                         .init(orderIndex: 1, patternIndex: 1, rowIndex: -1),
                         .init(orderIndex: 1, patternIndex: 1, rowIndex: 6)] {
            let plan = PlaybackSongSyntheticAdapter.adapt(source, startOrderIndex: 0, orderCount: 2,
                sampleRate: 48_000, initialPosition: position)
            XCTAssertTrue(plan.pattern.events.isEmpty)
            XCTAssertEqual(plan.diagnostics.traversalStopReason, .outOfRange)
        }
        let labeled = PlaybackPattern(index: 1, rows: [10, 20, 30, 40].enumerated().map {
            .init(index: $0.element, cells: [cell($0.offset == 1 ? 14 : 0, $0.offset == 1 ? 0x60 : 0)])
        })
        let input = song(source, linear: true, patterns: [1: labeled])
        XCTAssertEqual(adapt(input, 48_000, order: 1, row: 2).diagnostics.rowMappings.map(\.source.rowIndex), [30, 40])
    }

    private func adapt(_ input: PlaybackSong, _ rate: Double, order: Int, row: Int) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(input, startOrderIndex: 0, orderCount: input.orders.count,
            sampleRate: rate, initialPosition: .init(orderIndex: order, patternIndex: input.orders[order].patternIndex, rowIndex: row))
    }

    private func render(_ input: PlaybackSong, _ plan: PlaybackSongSyntheticPlan, _ rate: Double) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderer(preparedPlan: plan).render(.init(song: input, config: .init(sampleRate: rate), frames: Int(rate)))
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func pattern(_ index: Int, _ rows: [[PlaybackCell]]) -> PlaybackPattern {
        .init(index: index, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })
    }

    private func song(_ source: PlaybackSong, linear: Bool, patterns: [Int: PlaybackPattern]? = nil,
                      orders: [PlaybackOrderEntry]? = nil) -> PlaybackSong {
        .init(title: source.title, orders: orders ?? source.orders, patternsByIndex: patterns ?? source.patternsByIndex,
            instrumentsByIndex: source.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: source.initialTiming, usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: source.xmSampleSlotProvenanceByInstrument)
    }

    private func fixture() throws -> PlaybackSong {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resolved = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VTX_TEST_ARTIFACT_ROOT"] ?? "/private/tmp")
            .resolvingSymlinksInPath().path
        // Foundation spells an existing /private/tmp directory as its /tmp alias.
        let pathRoot = resolved == "/tmp" || resolved.hasPrefix("/tmp/") ? "/private" + resolved : resolved
        guard pathRoot.hasPrefix("/private/tmp/") || pathRoot == "/private/tmp" else { throw CocoaError(.fileWriteInvalidFileName) }
        let root = URL(fileURLWithPath: pathRoot)
        let output = root.appendingPathComponent("vtx-cold-entry-tests-" + UUID().uuidString)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", repo.appendingPathComponent("scripts/generate-synthetic-xm-fixtures.py").path,
            "--manifest", repo.appendingPathComponent("tests/reference-xm/source/cold-entry-v1.manifest.json").path,
            "--output-dir", output.path, "--validate", "--write-xm", "--verify"]
        var environment = ProcessInfo.processInfo.environment
        for key in ["TMPDIR", "TMP", "TEMP"] { environment[key] = "/private/tmp" }
        process.environment = environment; process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let path = output.appendingPathComponent("generated/cold-entry-v1.xm").path
        return try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
    }
}
