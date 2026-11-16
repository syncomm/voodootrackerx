import Dispatch
import Foundation
import XCTest

private func sourceFreeSong() -> PlaybackSong {
    let cell = PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
    return .init(title: "Public raw-ID delivery control", orders: [.init(orderIndex: 0, patternIndex: 0)],
        patternsByIndex: [0: .init(index: 0, rows: [.init(index: 0, cells: [cell])])],
        instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: .stopAtEnd,
        initialTiming: .init(speed: 1, bpm: 255), usesLinearFrequencyTable: true)
}
private let scope = RuntimeLoopNativeScope(documentHigh: 1, documentLow: 2, sourceGeneration: 3,
    transportEpoch: 4, sampleRateBits: 48_000.0.bitPattern, semanticVersion: 1,
    linearFrequencyMode: true, order: 0, pattern: 0, firstRow: 0, lastRow: 0)
private let origin = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)
private final class Sink: RuntimeLoopNativeDeliverySink {
    var nativeLoopCurrentFrame: UInt64 = 0
    var attempted = 0, accepted = 0, retirements = 0, silenced = 0
    var rejectID: Int?
    func renderNativeLoopFrames(outputOffset: Int, frameCount: Int) { nativeLoopCurrentFrame += UInt64(frameCount) }
    func silenceNativeLoopFrames(outputOffset: Int, frameCount: Int) { silenced += frameCount }
    func applyPreparedNativeLoopCommand(_ command: RuntimeLoopNativeCommandDescriptor,
        header: RuntimeLoopNativeBatchHeader, target: RuntimeLoopNativeSourceBinding?) -> Bool {
        attempted += 1
        guard command.eventID != rejectID else { return false }
        accepted += 1; return true
    }
    func beginNativeLoopRetirement() { retirements += 1 }
}
private func storage(_ batch: PlaybackSongUserLoopProducer.Batch, ids: [(Int, Int)],
                     cache: CSoftwareMixerSharedSamplePayloadCache) throws -> RuntimeLoopNativeBatchStorage {
    let events = ids.map { id, offset in RuntimeCMixerAdapterEvent(id: id, source: origin,
        channelIndex: 0, syntheticTick: 0, scheduledFrame: batch.startFrame + offset,
        action: .noteCut(activeEventIndex: nil), categories: ["note_cut"]) }
    let runtime = RuntimeCMixerAdapterEventPlan(generated: true, sampleRate: 48_000,
        plannedSongEndFrame: batch.endFrame, plannedEventCount: events.count, events: events,
        categories: ["note_cut"], plan: batch.adapterPlan.plan)
    let modified = PlaybackSongUserLoopProducer.Batch(sequence: batch.sequence,
        predecessorSequence: batch.predecessorSequence, firstIteration: batch.firstIteration,
        startFrame: batch.startFrame, endFrame: batch.endFrame, runtimeEndFrame: batch.endFrame,
        importedSourceCount: batch.importedSourceCount,
        sourceIdentities: batch.sourceIdentities, adapterPlan: runtime, terminalStopReason: nil)
    return try .init(batch: modified, scope: scope, trackerChannelCount: 1, cache: cache)
}
private func publish(_ storage: RuntimeLoopNativeBatchStorage, _ channel: RuntimeLoopNativeTwoSlotChannel) {
    guard let reservation = channel.reserve() else { return XCTFail("reserve") }
    XCTAssertTrue(channel.publish(reservation, header: storage.header, retaining: storage), "publish")
}
final class RuntimeLoopNativeRawIDAccountingTests: XCTestCase {
    private func producer() throws -> PlaybackSongUserLoopProducer {
        try .init(song: sourceFreeSong(), initialPosition: origin, sampleRate: 48_000,
            sourceGeneration: 3, transportEpoch: 4)
    }
    func testCompletedBatchesMergeRawUnionWithoutOccurrences() throws {
        let producer = try producer(), cache = CSoftwareMixerSharedSamplePayloadCache()
        let firstBatch = try producer.next(minimumHorizonFrames: 1, maximumRows: 1)
        let secondBatch = try producer.next(minimumHorizonFrames: 1, maximumRows: 1)
        let thirdBatch = try producer.next(minimumHorizonFrames: 1, maximumRows: 1)
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope), sink = Sink()
        let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: 3)
        var first: RuntimeLoopNativeBatchStorage? = try storage(firstBatch, ids: [(0,0),(63,1),(64,2),(64,3),(129,4)], cache: cache)
        weak var firstWeak = first
        publish(first!, channel); first = nil
        guard case .admitted = channel.begin(at: 0) else { return XCTFail("begin") }
        var second: RuntimeLoopNativeBatchStorage? = try storage(secondBatch, ids: [(64,0),(130,1)], cache: cache)
        weak var secondWeak = second
        publish(second!, channel); second = nil
        cursor.render(frameCount: firstBatch.endFrame, sink: sink)
        XCTAssertTrue(firstWeak != nil, "callback cannot dispose old batch owner")
        var union = Set<Int>()
        channel.reclaimRetired { owner in (owner as! RuntimeLoopNativeBatchStorage).mergeExecutedRawEventIDs(into: &union) }
        XCTAssertTrue(firstWeak == nil && union == [0,63,64,129], "retired sparse raw IDs")
        publish(try storage(thirdBatch, ids: [], cache: cache), channel)
        cursor.render(frameCount: secondBatch.endFrame - firstBatch.endFrame, sink: sink)
        XCTAssertTrue(secondWeak != nil, "second owner pinned until producer")
        channel.reclaimRetired { owner in (owner as! RuntimeLoopNativeBatchStorage).mergeExecutedRawEventIDs(into: &union) }
        XCTAssertTrue(secondWeak == nil && union == [0,63,64,129,130] && sink.accepted == 7, "raw union differs from occurrence count")
        channel.shutdownAfterCallbackQuiescence { owner in (owner as! RuntimeLoopNativeBatchStorage).mergeExecutedRawEventIDs(into: &union) }
        XCTAssertTrue(union.count == 5, "empty ready batch adds no IDs")
    }
    func testFailedCommandDoesNotMarkFailedOrLaterIDs() throws {
        let producer = try producer(), cache = CSoftwareMixerSharedSamplePayloadCache()
        let batch = try producer.next(minimumHorizonFrames: 1, maximumRows: 1)
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope), sink = Sink()
        sink.rejectID = 64
        var owned: RuntimeLoopNativeBatchStorage? = try storage(batch, ids: [(0,0),(63,1),(64,2),(129,3)], cache: cache)
        weak var weakOwner = owned; publish(owned!, channel); owned = nil
        let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: 3)
        cursor.render(frameCount: 16, sink: sink)
        XCTAssertTrue(weakOwner != nil && sink.accepted == 2 && sink.attempted == 3 && sink.retirements == 1, "rejection seals once")
        XCTAssertTrue(cursor.takeCompletedFault()?.reason == .nativeCommandFailure, "exact fault")
        var union = Set<Int>()
        channel.shutdownAfterCallbackQuiescence { owner in (owner as! RuntimeLoopNativeBatchStorage).mergeExecutedRawEventIDs(into: &union) }
        XCTAssertTrue(weakOwner == nil && union == [0,63], "failed command and later command not consumed")
    }
    func testExplicitStopIncludesOnlyExecutedPrefixAndSessionFinalCopy() throws {
        let producer = try producer(), cache = CSoftwareMixerSharedSamplePayloadCache()
        let batch = try producer.next(minimumHorizonFrames: 1, maximumRows: 1)
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope), sink = Sink()
        publish(try storage(batch, ids: [(0,0),(63,1),(64,2)], cache: cache), channel)
        let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: 3)
        cursor.render(frameCount: 1, sink: sink)
        channel.revoke()
        var union = Set<Int>()
        channel.shutdownAfterCallbackQuiescence { owner in (owner as! RuntimeLoopNativeBatchStorage).mergeExecutedRawEventIDs(into: &union) }
        XCTAssertTrue(union == [0], "Stop includes executed prefix only")

        let session = RuntimeLoopPlanningSession(song: sourceFreeSong(), origin: origin, scope: scope,
            workerQueue: DispatchQueue(label: "public.raw.id.session.control"), horizonFrames: 1, maximumRows: 1)
        guard case let .ready(preparation) = session.waitForPreparation(timeout: 10) else { return XCTFail("session warmup") }
        let header = try XCTUnwrap(preparation.channel.currentLease()).header
        let commands = header.commands?.assumingMemoryBound(to: RuntimeLoopNativeCommandDescriptor.self)
        var expected = Set<Int>()
        for index in 0..<header.commandCount where commands![index].localFrame == header.localStartFrame { expected.insert(commands![index].eventID) }
        let core = RuntimeCMixerRenderCore(config: .init(sampleRate: 48_000, channelCount: 1), maximumRenderFrames: 1024)
        core.configureNativeLoopDelivery(channel: preparation.channel, scope: scope,
            trackerChannelCount: 1, keepingAlive: session)
        var output = [Float](repeating: 0, count: 1)
        XCTAssertTrue(output.withUnsafeMutableBufferPointer { core.render(into: $0, frameCount: 1) }, "session C render")
        XCTAssertTrue(session.acknowledgedRawUniqueEventCount == 0, "active partial not prematurely acknowledged")
        core.stopAll() // Native reset before generation cache may retire.
        session.cancelAndWait()
        XCTAssertTrue(session.consumedRawEventIDsAfterShutdown() == expected, "Session final partial raw union")
        XCTAssertTrue(session.acknowledgedRawUniqueEventCount == UInt64(expected.count), "final atomic count")
    }
}
