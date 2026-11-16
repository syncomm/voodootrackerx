import Foundation
import XCTest

/// Drives the actual RenderCore callback wrapper, native cursor, fixed occurrence
/// ring and C mixer using immutable prepared commands and deterministic public PCM.
final class RenderCoreNativeLoopIntegrationTests: XCTestCase {
    private final class GenerationOwner {
        let cache = CSoftwareMixerSharedSamplePayloadCache()
    }

    /// Owns every payload pointer borrowed by a published native batch header.
    private final class NativeBatch {
        let payloads: UnsafeMutablePointer<RuntimeLoopPreparedCommandPayload>
        let commands: UnsafeMutablePointer<RuntimeLoopNativeCommandDescriptor>
        let bindings: UnsafeMutablePointer<RuntimeLoopNativeSourceBinding>
        let count: Int
        let bindingCount: Int
        let retained: [AnyObject]

        init(_ specs: [(Int, Int, Int, Int, RuntimeLoopPreparedCommandPayload)],
             bindings values: [RuntimeLoopNativeSourceBinding], retained: [AnyObject] = []) {
            count = specs.count; bindingCount = values.count; self.retained = retained
            payloads = .allocate(capacity: max(1, count)); commands = .allocate(capacity: max(1, count))
            bindings = .allocate(capacity: max(1, values.count))
            for (index, value) in values.enumerated() { bindings.advanced(by: index).initialize(to: value) }
            for (index, spec) in specs.enumerated() {
                payloads.advanced(by: index).initialize(to: spec.4)
                commands.advanced(by: index).initialize(to: .init(eventID: spec.0, eventOrdinal: index,
                    localSourceIndex: spec.1, channel: 0, localFrame: spec.2,
                    targetBindingOrdinal: spec.3, opcode: spec.4.opcode,
                    payload: UnsafeRawPointer(payloads.advanced(by: index))))
            }
        }

        deinit {
            commands.deinitialize(count: count); commands.deallocate()
            payloads.deinitialize(count: count); payloads.deallocate()
            bindings.deinitialize(count: bindingCount); bindings.deallocate()
        }

        func header(_ scope: RuntimeLoopNativeScope, sequence: UInt64,
                    start: UInt64, end: UInt64) -> RuntimeLoopNativeBatchHeader {
            .init(scope: scope, sequence: sequence, predecessorSequence: sequence - 1,
                predecessorStateToken: sequence == 1 ? 0 : (sequence - 1) * 11,
                terminalStateToken: sequence * 11, firstIteration: sequence - 1,
                runtimeStartFrame: start, runtimeEndFrame: end, localStartFrame: 0,
                commands: count == 0 ? nil : UnsafeRawPointer(commands), commandCount: count,
                commandStride: MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride,
                bindings: bindingCount == 0 ? nil : UnsafePointer(bindings), bindingCount: bindingCount)
        }
    }

    func testReadySuccessorsAndSilentBoundaryKeepExactPCMIDsSourceAndZeroCrossings() throws {
        for rate in [44_100.0, 48_000] {
            let owner = GenerationOwner(), scope = scope(rate), core = core(rate)
            let sample = MixerSampleBuffer(monoPCM: [0.25, -0.5, 0.75, -0.125])
            let loop = MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 4)
            let prepared = try birth(owner, sample: sample, loop: loop), target = binding(0)
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
            let first = NativeBatch([(7, 0, 0, 0, payload(.birth(prepared.birth)))],
                bindings: [target], retained: [prepared])
            try publish(first, first.header(scope, sequence: 1, start: 0, end: 19), channel)
            guard case .admitted = channel.begin(at: 0) else { return XCTFail("Initial batch was not admitted") }
            let second = NativeBatch([
                (8, 0, 0, 0, payload(.gainPan(0.5, 0))),
                (9, 0, 0, 0, payload(.step(0))),
                (10, 0, 1, 0, payload(.gainPan(0.5000001, nil))),
                (11, 0, 2, 0, payload(.step(0.875))),
                (12, 0, 3, 0, payload(.step(0.0000001))),
                (13, 0, 4, 0, payload(.step(0))),
                (14, 0, 5, 0, payload(.step(0.0000001))),
                (15, 0, 6, 0, payload(.step(0.875)))
            ], bindings: [target])
            try publish(second, second.header(scope, sequence: 2, start: 19, end: 50), channel)
            core.configureNativeLoopDelivery(channel: channel, scope: scope, trackerChannelCount: 1,
                keepingAlive: owner, recordsOccurrences: true)
            let reference = CSoftwareMixer(config: core.config)
            defer { core.stopAll(); reference.clearVoices(); channel.shutdownAfterCallbackQuiescence() }
            let voice = reference.addVoice(sample: sample, gain: 0.7, playbackStep: 0.875,
                loop: loop, sourceOnsetElapsedFrames: 0)
            reference.setChannelTag(0, forVoiceAt: voice)

            var actual = [Float]()
            for count in [1, 7, 11] { actual += renderCoreAudioRuntimePCM(core, frames: count) }
            XCTAssertEqual(channel.acknowledgedSequence, 1, "Acknowledge the exact callback-edge boundary")
            channel.reclaimRetired()
            let third = NativeBatch([], bindings: [])
            try publish(third, third.header(scope, sequence: 3, start: 50, end: 100), channel)
            for count in [1, 3, 17, 10] { actual += renderCoreAudioRuntimePCM(core, frames: count) }
            XCTAssertEqual(channel.acknowledgedSequence, 2)
            channel.reclaimRetired()
            let fourth = NativeBatch([], bindings: [])
            try publish(fourth, fourth.header(scope, sequence: 4, start: 100, end: 1_000), channel)
            for count in [1, 29, 20] { actual += renderCoreAudioRuntimePCM(core, frames: count) }
            XCTAssertEqual(channel.acknowledgedSequence, 3, "An empty batch still acknowledges its complete interval")
            actual += renderCoreAudioRuntimePCM(core, frames: 37)

            var expected = reference.render(frames: 19).interleavedPCM
            XCTAssertTrue(reference.scheduleVoiceGainPanUpdate(voiceIndex: voice, scheduledFrame: 19, gain: 0.5, pan: nil).wasAccepted)
            XCTAssertTrue(reference.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 19, playbackStep: 0).wasAccepted)
            expected += reference.render(frames: 2).interleavedPCM
            XCTAssertTrue(reference.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 21, playbackStep: 0.875).wasAccepted)
            for (frame, step) in [(22, 0.0000001), (23, 0), (24, 0.0000001), (25, 0.875)] {
                expected += reference.render(frames: 1).interleavedPCM
                XCTAssertTrue(reference.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                    scheduledFrame: frame, playbackStep: step).wasAccepted)
            }
            expected += reference.render(frames: actual.count - expected.count).interleavedPCM
            XCTAssertEqual(actual, expected, "Exact PCM proves the existing source cursor continues through holds and empty batches")
            XCTAssertNil(core.consumeNativeLoopPlanningFailure()); XCTAssertNil(core.consumeNativeLoopHostFault())
            let diagnostics = core.drainNativeLoopOccurrences()
            XCTAssertEqual(RuntimeCMixerRenderCore.callbackDiagnosticRingCapacity, 32_768)
            XCTAssertEqual(diagnostics.drops, 0)
            XCTAssertEqual(diagnostics.attempts, 9); XCTAssertEqual(diagnostics.applied, 8)
            XCTAssertEqual(diagnostics.suppressed, 1); XCTAssertEqual(diagnostics.failures, 0)
            XCTAssertEqual(diagnostics.events.map(\.eventID), Array(7...15))
            XCTAssertEqual(diagnostics.events.map(\.plannedFrame), [0, 19, 19, 20, 21, 22, 23, 24, 25])
            XCTAssertEqual(diagnostics.events.map(\.appliedFrame), diagnostics.events.map(\.plannedFrame))
            XCTAssertEqual(diagnostics.events.map(\.disposition), [0, 0, 0, 1, 0, 0, 0, 0, 0])
            XCTAssertTrue(diagnostics.events.allSatisfy { $0.scope == scope && $0.targetBirth == target.birth && $0.sourceAfter == target.birth })
            XCTAssertEqual(diagnostics.events.filter { $0.opcode == 0 }.count, 1)
            let nativeVoice = try XCTUnwrap(diagnostics.events.first?.nativeVoiceIndex)
            XCTAssertTrue(diagnostics.events.allSatisfy { $0.nativeVoiceIndex == nativeVoice })
        }
    }

    func testMissingSuccessorRetiresAtExactBoundaryBeforeFaultSilenceAndLateRejection() throws {
        for rate in [44_100.0, 48_000] {
            let owner = GenerationOwner(), scope = scope(rate), core = core(rate)
            let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5, -0.25, 0.125])
            let loop = MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 4)
            let prepared = try birth(owner, sample: sample, loop: loop)
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
            let first = NativeBatch([(7, 0, 0, 0, payload(.birth(prepared.birth)))],
                bindings: [binding(0)], retained: [prepared])
            try publish(first, first.header(scope, sequence: 1, start: 0, end: 19), channel)
            let lateReservation = try XCTUnwrap(channel.reserve())
            core.configureNativeLoopDelivery(channel: channel, scope: scope, trackerChannelCount: 1, keepingAlive: owner)
            let reference = CSoftwareMixer(config: core.config)
            defer { core.stopAll(); reference.clearVoices(); channel.shutdownAfterCallbackQuiescence() }
            let voice = reference.addVoice(sample: sample, gain: 0.7, playbackStep: 0.875,
                loop: loop, sourceOnsetElapsedFrames: 0)
            reference.setChannelTag(0, forVoiceAt: voice)
            XCTAssertEqual(renderCoreAudioRuntimePCM(core, frames: 19), reference.render(frames: 19).interleavedPCM)
            XCTAssertEqual(channel.acknowledgedSequence, 1)
            XCTAssertNil(core.consumeNativeLoopPlanningFailure(), "Retirement must finish before reporting Stop")
            let ramp = CSoftwareMixer.songReplacementRampFrameCount(sampleRate: rate)
            XCTAssertEqual(ramp, rate == 44_100 ? 220 : 240)
            _ = reference.retireSongVoices(channel: 0)
            XCTAssertEqual(renderCoreAudioRuntimePCM(core, frames: ramp - 1), reference.render(frames: ramp - 1).interleavedPCM)
            XCTAssertNil(core.consumeNativeLoopPlanningFailure())
            XCTAssertEqual(renderCoreAudioRuntimePCM(core, frames: 1), reference.render(frames: 1).interleavedPCM)
            let failure = try XCTUnwrap(core.consumeNativeLoopPlanningFailure())
            XCTAssertEqual(failure.scope, scope)
            XCTAssertEqual(failure.reason, .missingSuccessor)
            XCTAssertEqual(failure.sequence, 1)
            XCTAssertEqual(failure.boundaryFrame, 19)
            XCTAssertEqual(failure.retirementEndFrame, UInt64(19 + ramp))
            XCTAssertNil(core.consumeNativeLoopPlanningFailure(), "Publish the failure once")
            XCTAssertNil(core.consumeNativeLoopHostFault())
            XCTAssertTrue(renderCoreAudioRuntimePCM(core, frames: 97, initialValue: 0.75).allSatisfy { $0 == 0 })
            let late = NativeBatch([], bindings: [])
            XCTAssertFalse(channel.publish(lateReservation,
                header: late.header(scope, sequence: 2, start: 19, end: 1_000), retaining: late))
            XCTAssertNil(channel.reserve())
        }
    }

    func testCompletedStopSourceFreeSemanticAndStaleBindingPreserveActualBirth() throws {
        for rate in [44_100.0, 48_000] {
            let owner = GenerationOwner(), scope = scope(rate), core = core(rate)
            let sample = MixerSampleBuffer(monoPCM: [0.25, -0.25])
            let prepared = try birth(owner, sample: sample, gain: 0.5, step: 1)
            let channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
            let old = binding(0), current = binding(1)
            let semantic = PlaybackXMChannelUpdate(channelIndex: 0, instrumentIndex: 1, sampleIndex: 0,
                sourceEventIndex: nil, source: position, tick: 0, scheduledFrame: 6, bpm: 125, speed: 6, state: .init())
            let first = NativeBatch([
                (7, 0, 0, 0, payload(.birth(prepared.birth))),
                (8, 0, 5, 0, payload(.sourceStop(retireSong: true))),
                (9, -1, 6, -1, payload(.channelSemantic(semantic, selectionRuntimeFrame: 6))),
                (10, 1, 7, 1, payload(.birth(prepared.birth))),
                (11, 0, 8, 0, payload(.gainPan(1, nil)))
            ], bindings: [old, current], retained: [prepared])
            try publish(first, first.header(scope, sequence: 1, start: 0, end: 1_000), channel)
            core.configureNativeLoopDelivery(channel: channel, scope: scope, trackerChannelCount: 1,
                keepingAlive: owner, recordsOccurrences: true)
            defer { core.stopAll(); channel.shutdownAfterCallbackQuiescence() }
            _ = renderCoreAudioRuntimePCM(core, frames: 16)
            let diagnostics = core.drainNativeLoopOccurrences()
            XCTAssertEqual(diagnostics.events.count, 5); XCTAssertEqual(diagnostics.drops, 0)
            XCTAssertEqual(diagnostics.attempts, 5); XCTAssertEqual(diagnostics.applied, 4)
            XCTAssertEqual(diagnostics.suppressed, 1); XCTAssertEqual(diagnostics.failures, 0)
            XCTAssertEqual(diagnostics.events.map(\.eventID), [7, 8, 9, 10, 11])
            XCTAssertEqual(diagnostics.events.map(\.plannedFrame), [0, 5, 6, 7, 8])
            XCTAssertEqual(diagnostics.events.map(\.appliedFrame), diagnostics.events.map(\.plannedFrame))
            guard diagnostics.events.count == 5 else { continue }
            XCTAssertNil(diagnostics.events[1].sourceAfter, "Completed source Stop clears its association")
            XCTAssertEqual(diagnostics.events[2].disposition, 0)
            XCTAssertNil(diagnostics.events[2].targetBirth); XCTAssertNil(diagnostics.events[2].sourceAfter)
            XCTAssertEqual(diagnostics.events[3].sourceAfter, current.birth)
            XCTAssertEqual(diagnostics.events[4].targetBirth, old.birth)
            XCTAssertEqual(diagnostics.events[4].sourceBefore, current.birth)
            XCTAssertEqual(diagnostics.events[4].sourceAfter, current.birth)
            XCTAssertEqual(diagnostics.events[4].disposition, 2)
            XCTAssertNil(core.consumeNativeLoopPlanningFailure()); XCTAssertNil(core.consumeNativeLoopHostFault())
        }
    }

    private var position: PlaybackPosition { .init(orderIndex: 0, patternIndex: 0, rowIndex: 0) }
    private func payload(_ action: RuntimeLoopPreparedCommandPayload.Action) -> RuntimeLoopPreparedCommandPayload {
        .init(source: position, tick: 0, action: action)
    }
    private func scope(_ rate: Double) -> RuntimeLoopNativeScope {
        .init(documentHigh: 1, documentLow: 2, sourceGeneration: 3, transportEpoch: 4,
            sampleRateBits: rate.bitPattern, semanticVersion: 1, linearFrequencyMode: true,
            order: 0, pattern: 0, firstRow: 0, lastRow: 0)
    }
    private func binding(_ index: Int) -> RuntimeLoopNativeSourceBinding {
        .init(localLookupIndex: index, birth: .init(sourceGeneration: 3, transportEpoch: 4,
            birthSequence: 1, birthEventIndex: index), nativeSlot: -1, nativeIncarnation: 0)
    }
    private func publish(_ batch: NativeBatch, _ header: RuntimeLoopNativeBatchHeader,
                         _ channel: RuntimeLoopNativeTwoSlotChannel) throws {
        let reservation = try XCTUnwrap(channel.reserve())
        XCTAssertTrue(channel.publish(reservation, header: header, retaining: batch))
    }
    private func core(_ rate: Double) -> RuntimeCMixerRenderCore {
        .init(config: .init(sampleRate: rate, channelCount: 1), maximumRenderFrames: 1024,
            outputPolicy: .init(outputGain: 1, headroomPolicy: "control", gainPolicySource: "control"))
    }
    private func birth(_ owner: GenerationOwner, sample: MixerSampleBuffer, gain: Float = 0.7,
                       step: Double = 0.875, loop: MixerSampleLoop = .none) throws -> CSoftwareMixerPreparedLoopBirthStorage {
        try XCTUnwrap(CSoftwareMixerPreparedLoopBirthStorage(cache: owner.cache,
            sample: sample, gain: gain, pan: 0, playbackStep: step, loop: loop))
    }
}
