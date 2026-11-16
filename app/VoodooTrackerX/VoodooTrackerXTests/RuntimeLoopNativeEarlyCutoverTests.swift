import Dispatch
import Foundation
import XCTest
import Synchronization

private func verify(_ value: @autoclosure () -> Bool, _ message: String,
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value(), message, file: file, line: line)
}
private func scope(_ generation: UInt64) -> RuntimeLoopNativeScope {
    .init(documentHigh: 1, documentLow: 2, sourceGeneration: generation, transportEpoch: 9,
        sampleRateBits: 48_000.0.bitPattern, semanticVersion: 1, linearFrequencyMode: true,
        order: 0, pattern: 0, firstRow: 0, lastRow: 0)
}
private final class Owner {
    static let live = Atomic<Int>(0)
    let header: RuntimeLoopNativeBatchHeader
    private let commands: UnsafeMutablePointer<RuntimeLoopNativeCommandDescriptor>?
    private let boundaries: UnsafeMutablePointer<RuntimeLoopNativeIterationBoundary>?
    init(_ scope: RuntimeLoopNativeScope, sequence: UInt64, start: UInt64, end: UInt64,
         ids: [(Int,Int)] = [], natural: [(Int,UInt64)] = [], edit: RuntimeLoopNativeEarlyCutover? = nil) {
        _ = Self.live.wrappingAdd(1, ordering: .relaxed)
        commands = ids.isEmpty ? nil : .allocate(capacity: ids.count)
        for (index, entry) in ids.enumerated() {
            commands!.advanced(by: index).initialize(to: .init(eventID: entry.0, eventOrdinal: index,
                localSourceIndex: -1, channel: 0, localFrame: entry.1, targetBindingOrdinal: -1,
                opcode: 0, payload: nil))
        }
        boundaries = natural.isEmpty ? nil : .allocate(capacity: natural.count)
        for (index, entry) in natural.enumerated() {
            boundaries!.advanced(by: index).initialize(to: .init(localFrame: entry.0, iteration: UInt64(index + 1), stateToken: entry.1))
        }
        header = .init(scope: scope, sequence: sequence, predecessorSequence: sequence - 1,
            predecessorStateToken: edit?.boundaryStateToken ?? sequence - 1, terminalStateToken: sequence,
            firstIteration: 0, runtimeStartFrame: start, runtimeEndFrame: end, localStartFrame: 0,
            commands: commands.map(UnsafeRawPointer.init), commandCount: ids.count,
            commandStride: MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride, bindings: nil, bindingCount: 0,
            naturalBoundaries: boundaries.map { UnsafePointer($0) }, naturalBoundaryCount: natural.count, earlyCutover: edit)
    }
    deinit {
        commands?.deinitialize(count: header.commandCount); commands?.deallocate()
        boundaries?.deinitialize(count: header.naturalBoundaryCount); boundaries?.deallocate()
        _ = Self.live.wrappingSubtract(1, ordering: .relaxed)
    }
}
private final class Sink: RuntimeLoopNativeDeliverySink {
    var nativeLoopCurrentFrame: UInt64 = 0
    var mask: UInt64 = 0, generation: UInt64 = 0
    var retirements = 0, zeroFrames = 0
    func renderNativeLoopFrames(outputOffset: Int, frameCount: Int) { nativeLoopCurrentFrame += UInt64(frameCount) }
    func silenceNativeLoopFrames(outputOffset: Int, frameCount: Int) { zeroFrames += frameCount }
    func applyPreparedNativeLoopCommand(_ command: RuntimeLoopNativeCommandDescriptor,
        header: RuntimeLoopNativeBatchHeader, target: RuntimeLoopNativeSourceBinding?) -> Bool {
        mask |= UInt64(1) << command.eventID; return true
    }
    func beginNativeLoopRetirement() { retirements += 1 }
    func didAdmitNativeLoopScope(_ scope: RuntimeLoopNativeScope) { generation = scope.sourceGeneration }
}
private func publish(_ owner: Owner, _ channel: RuntimeLoopNativeTwoSlotChannel,
                     reservation: RuntimeLoopNativeTwoSlotChannel.Reservation? = nil) {
    verify(channel.publish(reservation ?? channel.reserve()!, header: owner.header, retaining: owner), "publish")
}
private func cutover(_ generation: UInt64, frame: UInt64, token: UInt64, serial: UInt64) -> RuntimeLoopNativeEarlyCutover {
    .init(previousScope: scope(generation), predecessorSequence: 1, boundaryFrame: frame, boundaryStateToken: token, requestSerial: serial)
}
final class RuntimeLoopNativeEarlyCutoverTests: XCTestCase {
    func testOptionalNaturalBoundaryCoalescingAndUnchangedMandatoryDelivery() {
        for variant in 0..<3 { assertVariant(variant) }
        XCTAssertEqual(Owner.live.load(ordering: .relaxed), 0)
    }
    func testConcurrentReadyRetractionPreservesClaimedHeaderAndOwner() {
        for _ in 0..<1000 { raceRetractionAgainstClaim() }
        XCTAssertEqual(Owner.live.load(ordering: .relaxed), 0)
    }
    private func assertVariant(_ variant: Int) {
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope(3)), sink = Sink()
        publish(Owner(scope(3), sequence: 1, start: 0, end: 100,
            ids: [(0,0),(1,10),(2,20)], natural: [(10,101),(20,102),(100,103)]), channel)
        guard case .admitted = channel.begin(at: 0) else { return XCTFail("begin") }
        let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope(3), retirementFrames: 3)
        publish(Owner(scope(3), sequence: 2, start: 100, end: 200), channel)
        if variant != 0 {
            channel.authorizeRefreshRequest(5)
            let reservation = channel.retractReady()!
            publish(Owner(scope(4), sequence: 2, start: 10, end: 200, ids: [(3,0)],
                edit: cutover(3, frame: 10, token: 101, serial: 5)), channel, reservation: reservation)
            if variant == 2 { channel.authorizeRefreshRequest(6); channel.authorizeRefreshRequest(5) }
        }
        cursor.render(frameCount: 10, sink: sink)
        if variant == 1 {
            let f = channel.latestExecutionFrontier!
            verify(f.frame == 10 && f.sequence == 1 && !f.wholeBatch && f.admittedSourceGeneration == 4 && f.admittedSequence == 2, "exact prefix receipt at callback edge")
            verify(sink.mask == 1 && sink.generation == 4, "old B writer not applied")
            channel.reclaimRetired()
            cursor.render(frameCount: 1, sink: sink)
            verify(sink.mask == 9 && sink.retirements == 0, "prepared new command only")
        } else if variant == 2 {
            verify(channel.latestExecutionFrontier == nil && channel.rejectedRefreshRequestSerial == 5, "stale request rejected without Stop")
            channel.reclaimRetired()
            publish(Owner(scope(5), sequence: 2, start: 20, end: 200, ids: [(3,0)],
                edit: cutover(3, frame: 20, token: 102, serial: 6)), channel)
            cursor.render(frameCount: 10, sink: sink)
            verify(channel.latestExecutionFrontier?.frame == 20 && sink.generation == 5, "latest request admits next B")
            cursor.render(frameCount: 1, sink: sink)
            verify(sink.mask == 11 && sink.retirements == 0, "only truly executed old prefix and latest commands")
        } else {
            verify(channel.latestExecutionFrontier == nil, "optional B without edit does not ACK/end batch")
            cursor.render(frameCount: 90, sink: sink)
            verify(channel.latestExecutionFrontier?.wholeBatch == true && channel.latestExecutionFrontier?.frame == 100, "normal mandatory end unchanged")
            verify(sink.mask == 7 && sink.retirements == 0, "old commands continue unchanged")
        }
        verify(cursor.takeCompletedFault() == nil, "no false fault")
        channel.shutdownAfterCallbackQuiescence()
    }
    private func raceRetractionAgainstClaim() {
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope(3))
        publish(Owner(scope(3), sequence: 1, start: 0, end: 100, natural: [(10,101)]), channel)
        guard case .admitted = channel.begin(at: 0) else { return XCTFail("race begin") }
        channel.authorizeRefreshRequest(1)
        let began = DispatchSemaphore(value: 0), ended = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            publish(Owner(scope(4), sequence: 2, start: 10, end: 100,
                edit: cutover(3, frame: 10, token: 101, serial: 1)), channel)
            began.signal()
            for _ in 0..<20 {
                guard let reservation = channel.retractReady() else { break }
                publish(Owner(scope(4), sequence: 2, start: 10, end: 100,
                    edit: cutover(3, frame: 10, token: 101, serial: 1)), channel, reservation: reservation)
            }
            ended.signal()
        }
        began.wait()
        let admitted = channel.tryAdmitEarlyCutover(at: 10, stateToken: 101)
        ended.wait()
        if let admitted { verify(admitted.header.scope.sourceGeneration == 4 && admitted.header.runtimeStartFrame == 10, "race claimed exact immutable header") }
        verify(channel.currentLease()?.header.scope.sourceGeneration == (admitted == nil ? 3 : 4), "CAS loser never releases claimed header")
        channel.shutdownAfterCallbackQuiescence()
    }
}
