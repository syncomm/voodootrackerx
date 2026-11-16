import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class RuntimeLoopNativeDeliveryTests: XCTestCase {
    func testMissingSuccessorRetiresAtExactBoundaryThenSilencesAndRejectsLateProducer() throws {
        for rate in [44_100.0, 48_000] {
            let boundary = 512, retirement = Int(rate * 0.005), total = boundary + retirement + 73
            let scope = scope(rate)
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
            defer { channel.shutdownAfterCallbackQuiescence() }
            let owner = Commands([])
            let first = try XCTUnwrap(channel.reserve())
            XCTAssertTrue(channel.publish(first, header: header(scope, sequence: 1, start: 0, end: boundary, owner), retaining: owner))
            let late = try XCTUnwrap(channel.reserve()) // Producer occupied, deliberately unfinished.
            let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: retirement)
            let actual = try Sink(rate: rate, frames: total), expected = try mixer(rate)
            XCTAssertTrue(expected.scheduleSongVoiceRetirement(voiceIndex: 0, scheduledFrame: boundary).wasAccepted)
            actual.pull(cursor, frames: boundary - 1)
            XCTAssertNil(cursor.takeCompletedFault())
            XCTAssertEqual(channel.acknowledgedSequence, 0)
            actual.pull(cursor, frames: 1)
            XCTAssertEqual(channel.acknowledgedSequence, 1)
            XCTAssertEqual(actual.retirementCount, 1)
            XCTAssertNil(cursor.takeCompletedFault(), "UI Stop cannot truncate the C-owned tail")
            let lateOwner = Commands([])
            XCTAssertFalse(channel.publish(late,
                header: header(scope, sequence: 2, start: boundary, end: boundary * 2, lateOwner), retaining: lateOwner))
            actual.pull(cursor, frames: retirement - 1)
            XCTAssertNil(cursor.takeCompletedFault())
            actual.pull(cursor, frames: 1)
            let fault = try XCTUnwrap(cursor.takeCompletedFault())
            XCTAssertEqual(fault.reason, .missingSuccessor)
            XCTAssertEqual(fault.boundaryFrame, UInt64(boundary))
            XCTAssertEqual(fault.retirementEndFrame, UInt64(boundary + retirement))
            XCTAssertNil(cursor.takeCompletedFault())
            actual.pull(cursor, frames: 73)
            XCTAssertEqual(actual.retirementCount, 1)
            XCTAssertEqual(actual.pcm(), expected.render(frames: total).interleavedPCM)
            XCTAssertTrue(actual.pcm().suffix(73 * 2).allSatisfy { $0 == 0 })
            XCTAssertNil(channel.reserve())
        }
    }

    func testReadySuccessorPreservesNativeCursorAcrossIrregularPartitionsAndEmptyBatch() throws {
        for rate in [44_100.0, 48_000] { for partitions in [[512, 333], [1, 127, 31, 7, 509]] {
            let boundary = 512, total = 845, scope = scope(rate)
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
            defer { channel.shutdownAfterCallbackQuiescence() }
            let first = Commands([]), second = Commands([
                .init(eventID: 7, eventOrdinal: 0, localSourceIndex: 0, channel: 0,
                    localFrame: boundary, targetBindingOrdinal: -1, opcode: 1, payload: nil)
            ])
            XCTAssertTrue(channel.publish(try XCTUnwrap(channel.reserve()),
                header: header(scope, sequence: 1, start: 0, end: boundary, first), retaining: first))
            _ = channel.begin(at: 0) // Host is quiescent; allows one ready successor before start.
            XCTAssertTrue(channel.publish(try XCTUnwrap(channel.reserve()),
                header: header(scope, sequence: 2, start: boundary, end: boundary * 2, second), retaining: second))
            let actual = try Sink(rate: rate, frames: total), expected = try mixer(rate)
            XCTAssertTrue(expected.scheduleVoicePlaybackStepUpdate(voiceIndex: 0,
                scheduledFrame: boundary, playbackStep: 0.75).wasAccepted)
            let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope,
                retirementFrames: Int(rate * 0.005))
            var remaining = total, index = 0
            while remaining > 0 {
                let count = min(remaining, partitions[index % partitions.count])
                actual.pull(cursor, frames: count)
                remaining -= count; index += 1
            }
            XCTAssertEqual(actual.pcm(), expected.render(frames: total).interleavedPCM)
            XCTAssertEqual(channel.acknowledgedSequence, 1)
            XCTAssertEqual(actual.appliedEventID, 7)
            XCTAssertEqual(actual.appliedFrame, UInt64(boundary))
            XCTAssertEqual(actual.retirementCount, 0)
            XCTAssertNil(cursor.takeCompletedFault())
        } }
    }

    private final class Commands {
        let pointer: UnsafeMutablePointer<RuntimeLoopNativeCommandDescriptor>
        let count: Int
        init(_ commands: [RuntimeLoopNativeCommandDescriptor]) {
            count = commands.count
            pointer = .allocate(capacity: max(1, count))
            for (index, value) in commands.enumerated() { pointer.advanced(by: index).initialize(to: value) }
        }
        deinit { pointer.deinitialize(count: count); pointer.deallocate() }
    }

    private final class Sink: RuntimeLoopNativeDeliverySink {
        let mixer: CSoftwareMixer
        let output: UnsafeMutablePointer<Float>
        let capacity: Int
        var base = 0
        var retirementCount = 0
        var appliedEventID: Int?
        var appliedFrame: UInt64?
        var nativeLoopCurrentFrame: UInt64 { mixer.currentFrame }
        init(rate: Double, frames: Int) throws {
            mixer = try RuntimeLoopNativeDeliveryTests.mixer(rate)
            capacity = frames * 2
            output = .allocate(capacity: capacity)
            output.initialize(repeating: 0, count: capacity)
        }
        deinit { output.deinitialize(count: capacity); output.deallocate() }
        func pull(_ cursor: RuntimeLoopNativeDeliveryCursor, frames: Int) {
            cursor.render(frameCount: frames, sink: self)
            base += frames
        }
        func renderNativeLoopFrames(outputOffset: Int, frameCount: Int) {
            _ = mixer.render(into: .init(start: output.advanced(by: (base + outputOffset) * 2),
                count: frameCount * 2), frames: frameCount)
        }
        func silenceNativeLoopFrames(outputOffset: Int, frameCount: Int) {
            output.advanced(by: (base + outputOffset) * 2).update(repeating: 0, count: frameCount * 2)
        }
        func applyPreparedNativeLoopCommand(_ command: RuntimeLoopNativeCommandDescriptor,
            header: RuntimeLoopNativeBatchHeader, target: RuntimeLoopNativeSourceBinding?) -> Bool {
            appliedEventID = command.eventID; appliedFrame = mixer.currentFrame
            return mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: 0, scheduledFrame: Int(mixer.currentFrame),
                playbackStep: 0.75).wasAccepted
        }
        func beginNativeLoopRetirement() { retirementCount += 1; _ = mixer.retireSongVoices(channel: 0) }
        func pcm() -> [Float] { Array(UnsafeBufferPointer(start: output, count: capacity)) }
    }

    private func scope(_ rate: Double) -> RuntimeLoopNativeScope {
        .init(documentHigh: 1, documentLow: 2, sourceGeneration: 3, transportEpoch: 4,
            sampleRateBits: rate.bitPattern, semanticVersion: 1, linearFrequencyMode: true,
            order: 0, pattern: 0, firstRow: 0, lastRow: 3)
    }
    private func header(_ scope: RuntimeLoopNativeScope, sequence: UInt64, start: Int, end: Int,
                        _ owner: Commands) -> RuntimeLoopNativeBatchHeader {
        .init(scope: scope, sequence: sequence, predecessorSequence: sequence - 1,
            predecessorStateToken: sequence == 1 ? 0 : sequence - 1, terminalStateToken: sequence,
            firstIteration: sequence - 1, runtimeStartFrame: UInt64(start), runtimeEndFrame: UInt64(end),
            localStartFrame: start, commands: UnsafeRawPointer(owner.pointer), commandCount: owner.count,
            commandStride: MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride, bindings: nil, bindingCount: 0)
    }
    private func mixer(_ rate: Double) throws -> CSoftwareMixer { try Self.mixer(rate) }
    private static func mixer(_ rate: Double) throws -> CSoftwareMixer {
        let mixer = CSoftwareMixer(config: .init(sampleRate: rate))
        let sample = MixerSampleBuffer(monoPCM: (0..<64).map { Float(sin(Double($0) * 0.11)) * 0.1 })
        let voice = try XCTUnwrap(mixer.addVoice(sample: sample, playbackStep: 0.37,
            loop: .init(mode: .forward, startFrame: 0, endFrame: 64), sourceOnsetElapsedFrames: 0))
        mixer.setChannelTag(0, forVoiceAt: voice)
        return mixer
    }
}
