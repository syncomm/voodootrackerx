import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class RuntimeSongNativeDeliveryTests: XCTestCase {
    func testZeroTailRunsEndWriterBeforeClearingCAndAcknowledging() throws {
        let rate = 48_000.0, scope = scope(rate)
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
        defer { channel.shutdownAfterCallbackQuiescence() }
        let owner = Commands(end: 17, commandFrame: 17)
        var terminal = header(scope, end: 17, owner: owner)
        terminal.finiteSongEndFrame = 17
        XCTAssertTrue(channel.publish(try XCTUnwrap(channel.reserve()), header: terminal, retaining: owner))
        let sink = try Sink(rate: rate, frames: 18)
        let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: 5)
        sink.pull(cursor, frames: 17)
        XCTAssertEqual(sink.musicalEnds, [17])
        XCTAssertTrue(sink.commandFrames.isEmpty)
        XCTAssertNil(cursor.takeCompletedSong())
        sink.pull(cursor, frames: 1)
        XCTAssertEqual(sink.commandFrames, [17])
        XCTAssertEqual(sink.stops, [17])
        XCTAssertEqual(channel.acknowledgedSequence, 1)
        XCTAssertEqual(try XCTUnwrap(cursor.takeCompletedSong()).runtimeEndFrame, 17)
        XCTAssertNil(cursor.takeCompletedFault())
        XCTAssertEqual(sink.output.last, 0)
        XCTAssertEqual(sink.mixer.loadedVoiceCount, 0)
    }

    func testFiniteTerminalExecutesMusicalEndWriterClearsBeforeAcknowledgementAndKeepsSilentClock() throws {
        for rate in [44_100.0, 48_000] {
            let scope = scope(rate), channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
            defer { channel.shutdownAfterCallbackQuiescence() }
            var owner: Commands? = Commands(end: 17, commandFrame: 17)
            weak var weakOwner = owner
            var header = header(scope, end: 41, owner: owner!)
            header.finiteSongEndFrame = 17
            XCTAssertTrue(channel.publish(try XCTUnwrap(channel.reserve()), header: header, retaining: owner!))
            owner = nil
            XCTAssertNil(channel.reserve(), "A terminal publication cannot construct another successor")
            let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: 5)
            let sink = try Sink(rate: rate, frames: 79), reference = try makeMixer(rate)
            XCTAssertTrue(reference.scheduleVoicePlaybackStepUpdate(voiceIndex: 0, scheduledFrame: 17,
                playbackStep: 0.75).wasAccepted)

            sink.pull(cursor, frames: 17)
            XCTAssertEqual(sink.musicalEnds, [17])
            XCTAssertNil(cursor.takeCompletedSong())
            XCTAssertEqual(channel.acknowledgedSequence, 0)
            sink.pull(cursor, frames: 23)
            XCTAssertEqual(sink.commandFrames, [17], "The end-frame writer executes before tail samples")
            XCTAssertNil(cursor.takeCompletedSong())
            sink.pull(cursor, frames: 1)
            let completion = try XCTUnwrap(cursor.takeCompletedSong())
            XCTAssertEqual(completion.scope, scope)
            XCTAssertEqual(completion.musicalEndFrame, 17)
            XCTAssertEqual(completion.runtimeEndFrame, 41)
            XCTAssertNil(cursor.takeCompletedSong())
            XCTAssertNil(cursor.takeCompletedFault())
            XCTAssertEqual(sink.stops, [41])
            XCTAssertEqual(sink.retirements, 0, "Successful song end never uses the underrun fade")
            XCTAssertEqual(channel.acknowledgedSequence, 1)
            XCTAssertEqual(channel.reclaimRetired { _ in
                XCTAssertEqual(sink.mixer.activeVoiceCount, 0, "C cannot borrow PCM after retirement publishes")
            }, 1)
            XCTAssertNil(weakOwner, "Terminal follow must outlive the actual freed row/payload owner")

            var expected = reference.render(frames: 41).interleavedPCM
            reference.clearVoices()
            expected += reference.render(frames: 38).interleavedPCM
            sink.pull(cursor, frames: 38)
            XCTAssertEqual(sink.output, expected)
            XCTAssertTrue(sink.output.suffix(38).allSatisfy { $0 == 0 })
            XCTAssertEqual(sink.nativeLoopCurrentFrame, 79, "Normal silent C frame advancement is preserved")
            let follow = try XCTUnwrap(cursor.follow(at: 79, sampleRate: rate))
            XCTAssertTrue(follow.isTerminal)
            XCTAssertEqual(follow.source.rowIndex, 30)
            XCTAssertEqual(follow.rowEndFrame, 17)
            XCTAssertNil(channel.reserve())
        }
    }

    func testFiniteNonterminalStillRequiresSuccessorAndRetiresAsFault() throws {
        let scope = scope(48_000), channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
        defer { channel.shutdownAfterCallbackQuiescence() }
        let owner = Commands(end: 17)
        XCTAssertTrue(channel.publish(try XCTUnwrap(channel.reserve()),
            header: header(scope, end: 17, owner: owner), retaining: owner))
        let sink = try Sink(rate: 48_000, frames: 30)
        let cursor = RuntimeLoopNativeDeliveryCursor(channel: channel, scope: scope, retirementFrames: 5)
        sink.pull(cursor, frames: 30)
        XCTAssertEqual(try XCTUnwrap(cursor.takeCompletedFault()).reason, .missingSuccessor)
        XCTAssertNil(cursor.takeCompletedSong())
        XCTAssertEqual(sink.retirements, 1)
        XCTAssertEqual(sink.stops, [])
        XCTAssertEqual(sink.nativeLoopCurrentFrame, 22)
    }

    func testTerminalMarkerCannotChangeLoopOrEscapeItsNativeInterval() throws {
        let finite = scope(48_000)
        var loop = finite; loop.transportKind = .explicitLoop
        for (value, end) in [(loop, UInt64(17)), (finite, 42)] {
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: value)
            defer { channel.shutdownAfterCallbackQuiescence() }
            let owner = Commands(end: 17)
            var invalid = header(value, end: 41, owner: owner)
            invalid.finiteSongEndFrame = end
            XCTAssertFalse(channel.publish(try XCTUnwrap(channel.reserve()), header: invalid, retaining: owner))
        }
    }

    private final class Commands {
        let rows: UnsafeMutablePointer<RuntimeLoopNativeFollowRow>
        let commands: UnsafeMutablePointer<RuntimeLoopNativeCommandDescriptor>?
        let count: Int
        init(end: Int, commandFrame: Int? = nil) {
            rows = .allocate(capacity: 1)
            rows.initialize(to: .init(source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 30),
                syntheticRow: 0, rowStartExactFrame: 0, rowStartFrame: 0, rowEndFrame: end,
                effectiveSpeed: 1, effectiveBPM: 125, actualTickCount: 1))
            count = commandFrame == nil ? 0 : 1
            if let commandFrame {
                commands = .allocate(capacity: 1)
                commands!.initialize(to: .init(eventID: 7, eventOrdinal: 0, localSourceIndex: 0,
                    channel: 0, localFrame: commandFrame, targetBindingOrdinal: -1, opcode: 1, payload: nil))
            } else { commands = nil }
        }
        deinit {
            rows.deinitialize(count: 1); rows.deallocate()
            commands?.deinitialize(count: count); commands?.deallocate()
        }
    }

    private final class Sink: RuntimeLoopNativeDeliverySink {
        let mixer: CSoftwareMixer
        var output: [Float]
        var base = 0
        var retirements = 0
        var commandFrames = [UInt64](), musicalEnds = [UInt64](), stops = [UInt64]()
        var nativeLoopCurrentFrame: UInt64 { mixer.currentFrame }
        init(rate: Double, frames: Int) throws {
            mixer = try RuntimeSongNativeDeliveryTests.makeMixer(rate)
            output = Array(repeating: 0, count: frames)
        }
        func pull(_ cursor: RuntimeLoopNativeDeliveryCursor, frames: Int) {
            cursor.render(frameCount: frames, sink: self); base += frames
        }
        func renderNativeLoopFrames(outputOffset: Int, frameCount: Int) {
            output.withUnsafeMutableBufferPointer { buffer in
                _ = mixer.render(into: .init(start: buffer.baseAddress!.advanced(by: base + outputOffset),
                    count: frameCount), frames: frameCount)
            }
        }
        func silenceNativeLoopFrames(outputOffset: Int, frameCount: Int) {
            for index in (base + outputOffset)..<(base + outputOffset + frameCount) { output[index] = 0 }
        }
        func applyPreparedNativeLoopCommand(_ command: RuntimeLoopNativeCommandDescriptor,
            header: RuntimeLoopNativeBatchHeader, target: RuntimeLoopNativeSourceBinding?) -> Bool {
            commandFrames.append(mixer.currentFrame)
            return mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: 0,
                scheduledFrame: Int(mixer.currentFrame), playbackStep: 0.75).wasAccepted
        }
        func beginNativeLoopRetirement() { retirements += 1; _ = mixer.retireSongVoices(channel: 0) }
        func reachNativeSongEnd(atRuntimeFrame frame: UInt64) { musicalEnds.append(frame) }
        func finishNativeSong(atRuntimeFrame frame: UInt64) { stops.append(frame); mixer.clearVoices() }
    }

    private func scope(_ rate: Double) -> RuntimeLoopNativeScope {
        .init(documentHigh: 1, documentLow: 2, sourceGeneration: 3, transportEpoch: 4,
            sampleRateBits: rate.bitPattern, semanticVersion: 2, linearFrequencyMode: true,
            order: 0, pattern: 0, firstRow: 0, lastRow: 30, transportKind: .finiteSong)
    }
    private func header(_ scope: RuntimeLoopNativeScope, end: Int, owner: Commands) -> RuntimeLoopNativeBatchHeader {
        .init(scope: scope, sequence: 1, predecessorSequence: 0, predecessorStateToken: 0,
            terminalStateToken: 1, firstIteration: 0, runtimeStartFrame: 0, runtimeEndFrame: UInt64(end),
            localStartFrame: 0, commands: owner.commands.map(UnsafeRawPointer.init), commandCount: owner.count,
            commandStride: MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride, bindings: nil, bindingCount: 0,
            followRows: UnsafePointer(owner.rows), followRowCount: 1)
    }
    private func makeMixer(_ rate: Double) throws -> CSoftwareMixer { try Self.makeMixer(rate) }
    private static func makeMixer(_ rate: Double) throws -> CSoftwareMixer {
        let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
        let index = try XCTUnwrap(mixer.addVoice(sample: .init(monoPCM: [0.25, -0.5, 0.75, -0.125]),
            playbackStep: 0.37, loop: .init(mode: .forward, startFrame: 0, endFrame: 4), sourceOnsetElapsedFrames: 0))
        mixer.setChannelTag(0, forVoiceAt: index)
        return mixer
    }
}
