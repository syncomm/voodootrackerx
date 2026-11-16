import Dispatch
import Foundation
import XCTest
import Synchronization

private func ensure(_ value: @autoclosure () -> Bool, _ reason: String,
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value(), reason, file: file, line: line)
}
private final class Clock: @unchecked Sendable { let frame = Atomic<UInt64>(0) }
private final class InitialPreparationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values = [String]()
    let arrived = DispatchSemaphore(value: 0)
    func record(_ result: RuntimeLoopPlanningSession.PreparationResult) {
        let value: String
        switch result {
        case .ready: value = "ready"
        case .failed: value = "failed"
        case .cancelled: value = "cancelled"
        case .pending: value = "pending"
        }
        lock.lock(); values.append(value); lock.unlock()
        arrived.signal()
    }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
}
private func song(_ note: UInt8) -> PlaybackSong {
    let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25, 0.125, -0.125],
        volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
    let cells = (0..<5).map { row in PlaybackRow(index: row, cells: [PlaybackCell(note: row == 0 ? note : 0,
        instrument: row == 0 ? 1 : 0, volumeColumn: 0, effectType: 0, effectParam: 0)]) }
    return .init(title: "Public mandatory deadline supersession regression", orders: [.init(orderIndex: 0, patternIndex: 0)],
        patternsByIndex: [0: .init(index: 0, rows: cells)], instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
        restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 5, bpm: 125), usesLinearFrequencyTable: true)
}
private func scope(_ rate: Double, _ generation: UInt64) -> RuntimeLoopNativeScope {
    .init(documentHigh: 1, documentLow: 2, sourceGeneration: generation, transportEpoch: 9,
        sampleRateBits: rate.bitPattern, semanticVersion: 1, linearFrequencyMode: true,
        order: 0, pattern: 0, firstRow: 0, lastRow: 4)
}
private func renderUntil(_ target: UInt64, core: RuntimeCMixerRenderCore, clock: Clock) {
    var output = [Float](repeating: 0, count: 1024)
    while clock.frame.load(ordering: .acquiring) < target {
        let current = clock.frame.load(ordering: .acquiring)
        let count = Int(min(512, target - current))
        ensure(output.withUnsafeMutableBufferPointer { core.render(into: $0, frameCount: count) }, "manual C delivery")
        let next = core.realtimeCurrentFrame
        guard next > current else { return XCTFail("native cursor stopped before requested delivery") }
        clock.frame.store(next, ordering: .releasing)
    }
}
private func waitPublished(_ session: RuntimeLoopPlanningSession, serial: UInt64) -> UInt64 {
    let deadline = Date(timeIntervalSinceNow: 5)
    while Date() < deadline {
        if case let .published(actual, frame) = session.latestEditableRefreshStatus(), actual == serial { return frame }
        if case let .refused(_, reason) = session.latestEditableRefreshStatus() { XCTFail("refusal \(reason)"); return 0 }
        if let failure = session.latestProductionFailure() { XCTFail("worker \(failure.message)"); return 0 }
        Thread.sleep(forTimeInterval: 0.001)
    }
    XCTFail("edit publication timeout"); return 0
}
final class RuntimeLoopSessionRapidDeadlineTests: XCTestCase {
    func testInitialPreparationCallbackPublishesReadyOnce() {
        let capture = InitialPreparationCapture()
        let session = RuntimeLoopPlanningSession(song: song(49),
            origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), scope: scope(48_000, 3),
            workerQueue: .init(label: "public.session.ready.callback"), horizonFrames: 512,
            onInitialPreparation: { capture.record($0) })
        XCTAssertEqual(capture.arrived.wait(timeout: .now() + 5), .success)
        guard case .ready = session.waitForPreparation() else {
            session.cancelAndWait(); return XCTFail("Ready callback must follow published state")
        }
        session.cancelAndWait()
        XCTAssertEqual(capture.snapshot(), ["ready"])
    }

    func testExplicitLoopWarmupIgnoresFiniteSongTailPolicy() {
        let rate = 48_000.0
        let session = RuntimeLoopPlanningSession(song: song(49),
            origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), scope: scope(rate, 3),
            workerQueue: .init(label: "public.session.explicit-loop.tail-isolation"), horizonFrames: 512,
            finiteSongTailFrames: RuntimeCMixerSongEndTailPolicy.defaultPolicy.tailFrames(sampleRate: rate))
        guard case let .ready(ready) = session.waitForPreparation(timeout: 5),
              let active = ready.channel.currentLease() else {
            session.cancelAndWait(); return XCTFail("Explicit Loop must ignore finite-song tail policy")
        }
        XCTAssertNil(active.header.finiteSongEndFrame)
        XCTAssertEqual(active.header.runtimeEndFrame, UInt64(ready.firstBatchEndFrame))
        session.cancelAndWait()
    }

    func testInitialPreparationCallbackPublishesCancellationOnceBeforeWarmup() {
        let capture = InitialPreparationCapture()
        let queue = DispatchQueue(label: "public.session.cancel.callback")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        queue.async { entered.signal(); release.wait() }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        let session = RuntimeLoopPlanningSession(song: song(49),
            origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), scope: scope(48_000, 3),
            workerQueue: queue, horizonFrames: 512,
            onInitialPreparation: { capture.record($0) })
        session.cancel()
        XCTAssertEqual(capture.arrived.wait(timeout: .now() + 5), .success)
        release.signal()
        session.cancelAndWait()
        XCTAssertEqual(capture.snapshot(), ["cancelled"])
    }

    func testInitialPreparationCallbackPublishesValidationFailureOnce() {
        let capture = InitialPreparationCapture()
        let invalid = RuntimeLoopNativeScope(documentHigh: 1, documentLow: 2, sourceGeneration: 3,
            transportEpoch: 9, sampleRateBits: 48_000.0.bitPattern, semanticVersion: 1,
            linearFrequencyMode: true, order: 0, pattern: 0, firstRow: -1, lastRow: 4)
        let session = RuntimeLoopPlanningSession(song: song(49),
            origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), scope: invalid,
            workerQueue: .init(label: "public.session.failure.callback"), horizonFrames: 512,
            onInitialPreparation: { capture.record($0) })
        XCTAssertEqual(capture.arrived.wait(timeout: .now() + 5), .success)
        guard case .failed = session.waitForPreparation() else {
            session.cancelAndWait(); return XCTFail("Failure callback must follow published state")
        }
        session.cancelAndWait()
        XCTAssertEqual(capture.snapshot(), ["failed"])
    }

    func testFiniteSongSingleTerminalWarmupPublishesReadyWithoutSuccessor() {
        let rate = 48_000.0, input = song(49), capture = InitialPreparationCapture()
        var finiteScope = scope(rate, 3)
        finiteScope.transportKind = .finiteSong
        let tailFrames = Int(rate * 3)
        let session = RuntimeLoopPlanningSession(song: input,
            origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), scope: finiteScope,
            workerQueue: .init(label: "public.session.finite.terminal"), horizonFrames: Int.max,
            maximumRows: 8, finiteSongTailFrames: tailFrames,
            onInitialPreparation: { capture.record($0) })
        XCTAssertEqual(capture.arrived.wait(timeout: .now() + 5), .success)
        guard case let .ready(ready) = session.waitForPreparation(),
              let active = ready.channel.currentLease() else {
            session.cancelAndWait(); return XCTFail("Single terminal finite batch must be ready")
        }
        XCTAssertEqual(ready.preparedThroughFrame, ready.firstBatchEndFrame)
        XCTAssertEqual(active.header.finiteSongEndFrame.map { $0 + UInt64(tailFrames) },
            active.header.runtimeEndFrame)
        XCTAssertEqual(active.header.scope.transportKind, .finiteSong)
        var nextScope = scope(rate, 4)
        nextScope.transportKind = .finiteSong
        let serial = session.requestEditableRefresh(song: input, scope: nextScope)
        guard case let .refused(refused, reason) = session.latestEditableRefreshStatus() else {
            session.cancelAndWait(); return XCTFail("Finite live refresh must ask for stopped reload")
        }
        XCTAssertEqual(refused, serial)
        XCTAssertEqual(reason, .stoppedReloadRequired)
        session.cancelAndWait()
        XCTAssertEqual(capture.snapshot(), ["ready"])
    }

    func testSupersededCandidateRecoversFreeSlotAndFinalQuiescedReceipt() {
        for rate in [44_100.0, 48_000] { qualify(rate) }
    }
    private func qualify(_ rate: Double) {
        let clock = Clock(), queue = DispatchQueue(label: "public.session.rapid.deadline")
        let session = RuntimeLoopPlanningSession(song: song(49), origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            scope: scope(rate, 3), workerQueue: queue, horizonFrames: Int(rate / 2), maximumRows: 128,
            refreshPublicationGuardFrames: 512)
        guard case let .ready(ready) = session.waitForPreparation(timeout: 5) else { return XCTFail("warmup") }
        let active = ready.channel.currentLease()!.header // No callback exists yet.
        let firstB = UInt64(active.naturalBoundaries![0].localFrame)
        ensure(firstB < active.runtimeEndFrame && active.runtimeEndFrame - firstB > 512, "natural B leaves real mandatory fallback tail")
        let core = RuntimeCMixerRenderCore(config: .init(sampleRate: rate, channelCount: 1), maximumRenderFrames: 1024)
        core.configureNativeLoopDelivery(channel: ready.channel, scope: ready.scope,
            trackerChannelCount: ready.trackerChannelCount, keepingAlive: session)
        session.startProduction(nativeFrame: { clock.frame.load(ordering: .acquiring) }, nativeQuantum: { 512 })
        let first = session.requestEditableRefresh(song: song(52), scope: scope(rate, 4))!
        let chosenB = waitPublished(session, serial: first)
        ensure(chosenB == firstB, "first feasible natural boundary")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        queue.async { entered.signal(); release.wait() }
        ensure(entered.wait(timeout: .now() + 5) == .success, "worker barrier")
        renderUntil(chosenB - 1, core: core, clock: clock)
        let second = session.requestEditableRefresh(song: song(55), scope: scope(rate, 5))!
        renderUntil(chosenB + 1, core: core, clock: clock)
        ensure(session.channel.latestExecutionFrontier == nil && session.channel.rejectedRefreshRequestSerial == first,
            "obsolete5 rejected at optional B without source admission")
        release.signal()
        // Native clock deliberately stands still while worker reclaims the rejected slot.
        // This isolates the free-slot recovery from scheduling jitter, without UI acknowledgement.
        Thread.sleep(forTimeInterval: 0.1)
        renderUntil(active.runtimeEndFrame, core: core, clock: clock)
        let ordinary = session.channel.latestExecutionFrontier!
        guard ordinary.wholeBatch && ordinary.admittedSequence == 2 && ordinary.admittedSourceGeneration == 3 else {
            core.stopAll(); session.cancelAndWait()
            return XCTFail("ordinary successor missing at mandatory E after free-slot reclaim")
        }
        ensure(core.consumeNativeLoopPlanningFailure() == nil, "rapid edit is not an underrun")
        let nextB = waitPublished(session, serial: second)
        guard nextB > clock.frame.load(ordering: .acquiring) else {
            core.stopAll(); session.cancelAndWait(); return XCTFail("latest candidate not published")
        }
        let entered2 = DispatchSemaphore(value: 0), release2 = DispatchSemaphore(value: 0)
        queue.async { entered2.signal(); release2.wait() }
        ensure(entered2.wait(timeout: .now() + 5) == .success, "receipt barrier")
        renderUntil(nextB + 1, core: core, clock: clock)
        let actual = session.channel.latestExecutionFrontier!
        ensure(actual.admittedSourceGeneration == 5 && actual.firstNaturalBoundaryAfterReady == nextB,
            "actual first-ready-visible boundary and newest admission")
        // Force the native receipt to be newer than worker/Main publication, then stop.
        session.cancel()
        core.stopAll()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { release2.signal() }
        session.cancelAndWait()
        let final = session.latestAdmittedEditableRefresh()!
        ensure(final.serial == second && final.scope.sourceGeneration == 5 && final.boundaryFrame == nextB && final.song == song(55),
            "quiesced final receipt preserves actual source before worker tick")
        ensure(core.consumeNativeLoopPlanningFailure() == nil, "no delayed musical fault")
    }
}
