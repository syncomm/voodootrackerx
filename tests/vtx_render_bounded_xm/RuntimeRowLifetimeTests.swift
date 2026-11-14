import CryptoKit
import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class RuntimeRowLifetimeTests: XCTestCase {
    private let fixtures = ["fxx-timing", "empty-slot-playback-state", "global-volume-publication",
        "envelope-release-fadeout-timing", "instrument-autovibrato-composition-linear",
        "instrument-autovibrato-composition-amiga", "delayed-instrument-only-edx", "rxy-counter-timing-carry"]

    // Public receipt format v1. Baseline receipts are sealed before production changes.
    func testPublicFullPlanReceipt() throws {
        var receipt = [String: String]()
        for (name, song, rate) in try cases() {
            let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0,
                orderCount: song.orders.count, sampleRate: rate)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan)
            XCTAssertEqual(runtime.plan, plan)
            var hash = SHA256()
            for value: Any in [runtime.events, runtime.eventStorage.ordering, runtime.categories,
                runtime.plannedSongEndFrame as Any, plan.pattern, plan.diagnostics, plan.canonicalTickClock,
                plan.xmChannelRows, plan.selectionDispatchFacts, plan.semanticPitchProjection,
                plan.instrumentAutovibratoClock, plan.instrumentAutovibratoRequests,
                plan.heldPitchProvenance, plan.nativePitchWriterSpans, plan.rowExitProvenance,
                plan.rowEntryTriggerResetFacts, plan.delayedInstrumentResetFacts,
                plan.xmEnvelopeTimeline as Any, plan.xmAudibleTimeline as Any] {
                hash.update(data: Data(snapshot(value).utf8))
            }
            for row in plan.diagnostics.rowTiming {
                for tick in 0..<row.actualTickCount { for channel in 0..<plan.diagnostics.rowDiagnostics[row.syntheticRow].cellCount {
                    hash.update(data: Data(snapshot(plan.semanticPitch(row: row.syntheticRow,
                        tick: tick, channel: channel) as Any).utf8))
                } }
            }
            receipt[name] = hash.finalize().map { String(format: "%02x", $0) }.joined()
            let request = PlaybackSongOfflineRenderRequest(song: song, orderCount: song.orders.count,
                config: .init(sampleRate: rate), frames: 4096)
            let pcm = PlaybackSongOfflineRenderer(preparedPlan: plan).render(request).block.interleavedPCM
            receipt[name + "/pcm"] = pcm.withUnsafeBytes {
                SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined()
            }
        }
        XCTAssertEqual(receipt.count, fixtures.count * 4 * 2)
        if let destination = ProcessInfo.processInfo.environment["VTX_ROW_LIFETIME_RECEIPT"] {
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: destination))
        }
    }

    func testFinalizedAssemblyPreservesValuesOwnersQueriesAndSharedHistoryBuffers() throws {
        for (_, song, rate) in try cases() {
            let source = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0,
                orderCount: song.orders.count, sampleRate: rate)
            let full = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: source)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate,
                preparedPlan: source, rowCaptureRetention: .runtimeFinalized)
            let finalized = try XCTUnwrap(runtime.plan)
            XCTAssertTrue(full.plan!.$xmChannelRows.isFullCapture)
            XCTAssertFalse(finalized.$xmChannelRows.isFullCapture)
            XCTAssertEqual(runtime.eventStorage, full.eventStorage)
            XCTAssertEqual(runtime.categories, full.categories)
            XCTAssertEqual(runtime.plannedSongEndFrame, full.plannedSongEndFrame)
            XCTAssertEqual(finalized.diagnostics, source.diagnostics)
            XCTAssertEqual(finalized.$xmChannelRows.count, source.xmChannelRows.count)
            for index in source.xmChannelRows.indices {
                XCTAssertEqual(finalized.$xmChannelRows.owner(at: index), .init(source.xmChannelRows[index]))
            }
            XCTAssertNil(finalized.$xmChannelRows.owner(at: -1))
            XCTAssertNil(finalized.$xmChannelRows.owner(at: source.xmChannelRows.count))
            for row in source.diagnostics.rowTiming {
                for tick in 0..<row.actualTickCount { for channel in 0..<source.diagnostics.rowDiagnostics[row.syntheticRow].cellCount {
                    XCTAssertEqual(finalized.semanticPitch(row: row.syntheticRow, tick: tick, channel: channel),
                        source.semanticPitch(row: row.syntheticRow, tick: tick, channel: channel))
                } }
            }
            XCTAssertEqual(address(finalized.pattern.events), address(source.pattern.events))
            XCTAssertEqual(address(finalized.xmEnvelopeTimeline?.updates ?? []), address(source.xmEnvelopeTimeline?.updates ?? []))
            XCTAssertEqual(address(finalized.xmEnvelopeTimeline?.channelUpdates ?? []), address(source.xmEnvelopeTimeline?.channelUpdates ?? []))
            XCTAssertEqual(address(finalized.xmAudibleTimeline?.updates ?? []), address(source.xmAudibleTimeline?.updates ?? []))
            for (key, history) in source.xmEnvelopeTimeline?.updatesByEvent ?? [:] {
                XCTAssertEqual(address(finalized.xmEnvelopeTimeline!.updatesByEvent[key]!), address(history))
            }
            for (key, history) in source.xmAudibleTimeline?.updatesByEvent ?? [:] {
                XCTAssertEqual(address(finalized.xmAudibleTimeline!.updatesByEvent[key]!), address(history))
            }
            for copy in [finalized.replacingEventCoverage(finalized.diagnostics.eventCoverage),
                PlaybackSongOfflineRenderer.plan(finalized, mutingEventsNotIn: [])] {
                XCTAssertEqual(copy.$xmChannelRows, finalized.$xmChannelRows)
                XCTAssertFalse(copy.$xmChannelRows.isFullCapture)
            }
            XCTAssertTrue(source.extendingEnvelopeTail(throughFrame: (full.plannedSongEndFrame ?? 0) + 1).$xmChannelRows.isFullCapture)
        }
    }

    func testOddOwnerReferencesPreserveOriginalOrdinalsAndNilValues() throws {
        let (_, song, rate) = try XCTUnwrap(cases().first)
        let seed = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: song.orders.count, sampleRate: rate)
        for ordinal in seed.xmChannelRows.indices {
            var full = seed
            var record = PlaybackSongSemanticPitchProjection.Record()
            record.selection = -3 - 2 * ordinal
            full.semanticPitchProjection = .init(coverage: .nativeDepthOffV1, channels: [[record]], resetRuns: [[]],
                seeds: [], storageGrowthCount: 0, workspaceCapacity: 0, captureFailureCount: 0)
            var finalized = full
            finalized.$xmChannelRows.finalizeForRuntime()
            let expected = try XCTUnwrap(full.semanticPitch(row: 0, tick: 0, channel: 0))
            XCTAssertEqual(finalized.semanticPitch(row: 0, tick: 0, channel: 0), expected)
            XCTAssertEqual(expected.rowControlIndex, ordinal)
        }
    }

    func testIndependentRuntimeProductReleasesRowsButInspectionAliasPinsThem() throws {
        final class WeakRow { weak var row: PlaybackXMChannelRow?; init(_ row: PlaybackXMChannelRow) { self.row = row } }
        let (_, song, rate) = try XCTUnwrap(cases().first)
        var observations = [WeakRow]()
        func build(keepInspection: Bool) -> (RuntimeCMixerAdapterEventPlan, PlaybackSongSyntheticPlan?) {
            let full = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: song.orders.count, sampleRate: rate)
            observations = full.xmChannelRows.map(WeakRow.init)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate,
                preparedPlan: full, rowCaptureRetention: .runtimeFinalized)
            return (runtime, keepInspection ? full : nil)
        }
        var independent: (RuntimeCMixerAdapterEventPlan, PlaybackSongSyntheticPlan?)? = build(keepInspection: false)
        XCTAssertFalse(independent!.0.plan!.$xmChannelRows.isFullCapture)
        XCTAssertTrue(observations.allSatisfy { $0.row == nil })
        independent = nil
        var aliased: (RuntimeCMixerAdapterEventPlan, PlaybackSongSyntheticPlan?)? = build(keepInspection: true)
        XCTAssertEqual(observations.filter { $0.row != nil }.count, aliased!.1!.xmChannelRows.count)
        aliased!.1 = nil
        XCTAssertTrue(observations.allSatisfy { $0.row == nil })
        XCTAssertFalse(aliased!.0.plan!.$xmChannelRows.isFullCapture)
    }

    private func address<T>(_ array: [T]) -> UInt? {
        array.withUnsafeBufferPointer { $0.baseAddress.map { UInt(bitPattern: $0) } }
    }

    private func cases() throws -> [(String, PlaybackSong, Double)] {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("reference-xm/generated")
        return try fixtures.flatMap { name in
            let path = directory.appendingPathComponent(name + ".xm").path
            let source = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
            return [true, false].flatMap { linear in [44_100.0, 48_000].map { rate in
                ("\(name)/\(linear)/\(Int(rate))", PlaybackSong(title: source.title, orders: source.orders,
                    patternsByIndex: source.patternsByIndex, instrumentsByIndex: source.instrumentsByIndex,
                    restartOrderIndex: source.restartOrderIndex, endBehavior: source.endBehavior,
                    initialTiming: source.initialTiming, usesLinearFrequencyTable: linear,
                    xmSampleSlotProvenanceByInstrument: source.xmSampleSlotProvenanceByInstrument), rate)
            } }
        }
    }

    private func snapshot(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.children.isEmpty { return String(describing: value) }
        let fields = mirror.children.map { "\($0.label ?? "_"):\(snapshot($0.value))" }
        return (mirror.displayStyle == .dictionary || mirror.displayStyle == .set ? fields.sorted() : fields)
            .joined(separator: "|")
    }
}
