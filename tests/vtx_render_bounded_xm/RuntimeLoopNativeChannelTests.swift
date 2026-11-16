import Dispatch
import Synchronization
import XCTest
@testable import VoodooTrackerXPlaybackSupport

/// Channel arbitration/lifetime tests; actual rendered-frontier/PCM tests are separate.
final class RuntimeLoopNativeChannelTests: XCTestCase {
    func testReadySuccessorNeedsNoMainActorNotificationAndReclaimsOnlyOffConsumer() throws {
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
        defer { channel.shutdownAfterCallbackQuiescence() }
        let probe = DisposalProbe()
        let first = try publish(channel, header: header(), probe: probe)
        _ = try admitted(channel.begin(at: 0), sequence: 1)
        let second = try publish(channel, header: header(sequence: 2, start: 4, end: 8), probe: probe)
        XCTAssertNil(channel.reserve(), "Active+ready must leave no third construction slot")
        XCTAssertEqual(channel.acknowledgedSequence, 0)
        let finished = DispatchSemaphore(value: 0)
        let callbackPassed = Atomic(false)
        // No Task, notification, UI delivery or producer operation is needed at B.
        DispatchQueue.global().async {
            probe.callbackActive.store(true, ordering: .releasing)
            let result = channel.finishBoundary(at: 4)
            if case let .admitted(lease) = result, lease.header.sequence == 2 {
                callbackPassed.store(true, ordering: .releasing)
            }
            probe.callbackActive.store(false, ordering: .releasing)
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(callbackPassed.load(ordering: .acquiring))
        XCTAssertEqual(channel.acknowledgedSequence, 1)
        XCTAssertNotNil(first.value, "Consumer acknowledgment must not destroy payload owner")
        XCTAssertNotNil(second.value)
        XCTAssertNil(channel.reserve(), "Retired owner is still a charged slot until producer reclaim")
        XCTAssertEqual(channel.reclaimRetired(), 1)
        XCTAssertNil(first.value)
        XCTAssertNotNil(second.value)
        XCTAssertEqual(probe.duringCallback.load(ordering: .acquiring), 0)
        XCTAssertEqual(probe.destroyed.load(ordering: .acquiring), 1)
    }

    func testThousandSequentialBatchesHaveExactEndAcknowledgmentsAndAtMostTwoOwners() throws {
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
        defer { channel.shutdownAfterCallbackQuiescence() }
        var owners = [WeakOwner]()
        owners.append(try publish(channel, header: header()))
        _ = try admitted(channel.begin(at: 0), sequence: 1)
        for sequence in UInt64(1)...1000 {
            if sequence < 1000 {
                owners.append(try publish(channel, header: header(sequence: sequence + 1,
                    start: sequence * 4, end: (sequence + 1) * 4)))
            }
            XCTAssertLessThanOrEqual(owners.filter { $0.value != nil }.count, 2)
            XCTAssertEqual(channel.acknowledgedSequence, sequence - 1,
                           "Prepared successor is not acknowledged execution")
            let result = channel.finishBoundary(at: sequence * 4)
            if sequence < 1000 { _ = try admitted(result, sequence: sequence + 1) }
            else { guard case .missingSuccessor = result else { return XCTFail("Expected terminal missing successor") } }
            XCTAssertEqual(channel.acknowledgedSequence, sequence)
            XCTAssertEqual(channel.reclaimRetired(), 1)
            XCTAssertEqual(owners.filter { $0.value != nil }.count, sequence < 1000 ? 1 : 0)
        }
        XCTAssertNil(channel.reserve(), "Terminal deadline closure is sticky")
    }

    func testWrongEndCannotAdvanceAcknowledgmentOrInstallSuccessor() throws {
        for wrongFrame in [UInt64(3), 5] {
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
            defer { channel.shutdownAfterCallbackQuiescence() }
            _ = try publish(channel, header: header())
            _ = try admitted(channel.begin(at: 0), sequence: 1)
            _ = try publish(channel, header: header(sequence: 2, start: 4, end: 8))
            guard case .invalidBoundary = channel.finishBoundary(at: wrongFrame) else {
                return XCTFail("Inexact end was accepted")
            }
            XCTAssertEqual(channel.acknowledgedSequence, 0)
            XCTAssertNil(channel.reserve())
        }
    }

    func testEveryScopeFieldIsRejectedBeforePublicationWithoutHoldingOwner() throws {
        let variants = [scope(documentHigh: 9), scope(documentLow: 9), scope(sourceGeneration: 9),
            scope(transportEpoch: 9), scope(sampleRateBits: Double(44_100).bitPattern),
            scope(semanticVersion: 9), scope(linear: false), scope(order: 9), scope(pattern: 9),
            scope(firstRow: 1), scope(lastRow: 2)]
        for bad in variants {
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
            defer { channel.shutdownAfterCallbackQuiescence() }
            let reservation = try XCTUnwrap(channel.reserve())
            var owner: Owner? = Owner()
            let weak = WeakOwner(owner!)
            XCTAssertFalse(channel.publish(reservation, header: header(scope: bad), retaining: owner!))
            owner = nil
            XCTAssertNil(weak.value)
            XCTAssertEqual(channel.acknowledgedSequence, 0)
            let fresh = try XCTUnwrap(channel.reserve(), "Rejected publication releases its unpublished slot")
            channel.discard(fresh)
        }
    }

    func testSequencePredecessorStateAndGapRejectWithoutAcknowledgingBadBatch() throws {
        let variants = [header(sequence: 3, start: 4, end: 8, predecessor: 1, predecessorState: 101),
            header(sequence: 2, start: 4, end: 8, predecessor: 0),
            header(sequence: 2, start: 4, end: 8, predecessorState: 999),
            header(sequence: 2, start: 5, end: 9)]
        for bad in variants {
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
            defer { channel.shutdownAfterCallbackQuiescence() }
            let old = try publish(channel, header: header())
            _ = try admitted(channel.begin(at: 0), sequence: 1)
            let rejected = try publish(channel, header: bad)
            guard case .invalidSuccessor = channel.finishBoundary(at: 4) else {
                return XCTFail("Incompatible successor was admitted")
            }
            XCTAssertEqual(channel.acknowledgedSequence, 1)
            XCTAssertNotNil(old.value)
            XCTAssertNotNil(rejected.value, "Rejected published storage also retires off consumer")
            XCTAssertEqual(channel.reclaimRetired(), 2)
            XCTAssertNil(old.value)
            XCTAssertNil(rejected.value)
            XCTAssertNil(channel.reserve())
        }
    }

    func testMissingSuccessorSealsEpochAndRejectsLatePreparingCompletion() throws {
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
        defer { channel.shutdownAfterCallbackQuiescence() }
        let first = try publish(channel, header: header())
        _ = try admitted(channel.begin(at: 0), sequence: 1)
        let preparing = try XCTUnwrap(channel.reserve())
        guard case .missingSuccessor = channel.finishBoundary(at: 4) else {
            return XCTFail("Expected exact-boundary missing successor")
        }
        XCTAssertEqual(channel.acknowledgedSequence, 1)
        var owner: Owner? = Owner()
        let late = WeakOwner(owner!)
        XCTAssertFalse(channel.publish(preparing, header: header(sequence: 2, start: 4, end: 8), retaining: owner!))
        owner = nil
        XCTAssertNil(late.value)
        guard case .revoked = channel.begin(at: 4) else { return XCTFail("Closed epoch reopened") }
        XCTAssertNil(channel.reserve())
        XCTAssertEqual(channel.reclaimRetired(), 1)
        XCTAssertNil(first.value)
    }

    func testStaleReservationCannotPublishIntoRecycledSlot() throws {
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
        defer { channel.shutdownAfterCallbackQuiescence() }
        let stale = try XCTUnwrap(channel.reserve())
        channel.discard(stale)
        let current = try XCTUnwrap(channel.reserve())
        XCTAssertFalse(channel.publish(stale, header: header(), retaining: Owner()))
        XCTAssertTrue(channel.publish(current, header: header(), retaining: Owner()))
        _ = try admitted(channel.begin(at: 0), sequence: 1)
    }

    func testRevokeDoesNotDisposePublishedOwnerBeforeHostQuiescence() throws {
        for activate in [false, true] {
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope())
            let owner = try publish(channel, header: header())
            if activate { _ = try admitted(channel.begin(at: 0), sequence: 1) }
            channel.revoke()
            XCTAssertNotNil(owner.value)
            XCTAssertEqual(channel.reclaimRetired(), 0)
            XCTAssertNotNil(owner.value)
            XCTAssertNil(channel.reserve())
            channel.shutdownAfterCallbackQuiescence()
            XCTAssertNil(owner.value)
        }
    }

    private func publish(_ channel: RuntimeLoopNativeTwoSlotChannel,
                         header: RuntimeLoopNativeBatchHeader, probe: DisposalProbe? = nil) throws -> WeakOwner {
        let reservation = try XCTUnwrap(channel.reserve())
        let owner = Owner(probe: probe)
        let weak = WeakOwner(owner)
        XCTAssertTrue(channel.publish(reservation, header: header, retaining: owner))
        return weak
    }

    @discardableResult
    private func admitted(_ result: RuntimeLoopNativeAdmission, sequence: UInt64,
                          file: StaticString = #filePath, line: UInt = #line) throws -> RuntimeLoopNativeBatchLease {
        guard case let .admitted(lease) = result else {
            XCTFail("Expected admission for sequence \(sequence)", file: file, line: line)
            throw Failure.expectedAdmission
        }
        XCTAssertEqual(lease.header.sequence, sequence, file: file, line: line)
        return lease
    }

    private func scope(documentHigh: UInt64 = 1, documentLow: UInt64 = 2, sourceGeneration: UInt64 = 3,
        transportEpoch: UInt64 = 4, sampleRateBits: UInt64 = Double(48_000).bitPattern,
        semanticVersion: UInt32 = 1, linear: Bool = true, order: Int = 0, pattern: Int = 0,
        firstRow: Int = 0, lastRow: Int = 3) -> RuntimeLoopNativeScope {
        .init(documentHigh: documentHigh, documentLow: documentLow, sourceGeneration: sourceGeneration,
              transportEpoch: transportEpoch, sampleRateBits: sampleRateBits, semanticVersion: semanticVersion,
              linearFrequencyMode: linear, order: order, pattern: pattern, firstRow: firstRow, lastRow: lastRow)
    }

    private func header(scope suppliedScope: RuntimeLoopNativeScope? = nil, sequence: UInt64 = 1,
        start: UInt64 = 0, end: UInt64 = 4, predecessor: UInt64? = nil,
        predecessorState: UInt64? = nil) -> RuntimeLoopNativeBatchHeader {
        .init(scope: suppliedScope ?? scope(), sequence: sequence,
              predecessorSequence: predecessor ?? sequence - 1,
              predecessorStateToken: predecessorState ?? (sequence == 1 ? 0 : sequence + 99),
              terminalStateToken: sequence + 100, firstIteration: sequence - 1,
              runtimeStartFrame: start, runtimeEndFrame: end, localStartFrame: 0,
              commands: nil, commandCount: 0, commandStride: 0, bindings: nil, bindingCount: 0)
    }

    private enum Failure: Error { case expectedAdmission }
    private final class DisposalProbe: Sendable {
        let callbackActive = Atomic(false)
        let duringCallback = Atomic(0)
        let destroyed = Atomic(0)
    }
    private final class Owner: Sendable {
        let probe: DisposalProbe?
        init(probe: DisposalProbe? = nil) { self.probe = probe }
        deinit {
            if let probe {
                if probe.callbackActive.load(ordering: .acquiring) {
                    _ = probe.duringCallback.wrappingAdd(1, ordering: .relaxed)
                }
                _ = probe.destroyed.wrappingAdd(1, ordering: .relaxed)
            }
        }
    }
    private final class WeakOwner {
        weak var value: Owner?
        init(_ value: Owner) { self.value = value }
    }
}
