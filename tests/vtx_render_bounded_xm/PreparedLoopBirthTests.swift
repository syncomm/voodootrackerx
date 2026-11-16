import XCTest
import MixerCore
@testable import VoodooTrackerXPlaybackSupport

/// Loop-only prepared birth shares existing C DSP; ordinary paths remain controls.
final class PreparedLoopBirthTests: XCTestCase {
    func testPreparedBirthMatchesOrdinaryPCMAtBothRatesWithLoopsEnvelopesAndOnset() throws {
        let loops: [MixerSampleLoop] = [.none,
            .init(mode: .forward, startFrame: 8, endFrame: 64),
            .init(mode: .pingPong, startFrame: 8, endFrame: 64)]
        for rate in [44_100.0, 48_000] { for loop in loops { for envelopes in [false, true] {
            for initialFrame in [0, 11] {
                let sample = MixerSampleBuffer(monoPCM: (0..<128).map { Float(($0 * 37 + 19) % 127 - 63) / 128 })
                let cache = CSoftwareMixerSharedSamplePayloadCache()
                let reference = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 2))
                let prepared = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 2))
                defer {
                    reference.clearVoices(); prepared.clearVoices()
                    withExtendedLifetime(cache) {} // Native references die before cache destruction.
                }
                let volume: MixerEnvelope? = envelopes ? .init(points: [
                    .init(positionFrame: 0, value: 0.75), .init(positionFrame: 31, value: 0.25),
                    .init(positionFrame: 80, value: 0.9)], sustainFrame: 31, loopStartFrame: 31, loopEndFrame: 80) : nil
                let pan: MixerEnvelope? = envelopes ? .init(points: [
                    .init(positionFrame: 0, value: -0.5), .init(positionFrame: 23, value: 0.5),
                    .init(positionFrame: 71, value: -0.125)], sustainFrame: 23, loopStartFrame: 23, loopEndFrame: 71) : nil
                // Nonzero native timeline proves prepared scheduling is an actual birth, not a restart.
                XCTAssertEqual(reference.render(frames: 37), prepared.render(frames: 37))
                let storage = try XCTUnwrap(CSoftwareMixerPreparedLoopBirthStorage(cache: cache, sample: sample,
                    gain: 0.7, pan: -0.3, playbackStep: 0.875, loop: loop, initialSourceFrame: initialFrame,
                    volumeEnvelope: volume, panEnvelope: pan, absoluteKeyOffFrame: 157,
                    fadeoutFrameDecrement: 1.0 / 65_536))
                let a = try XCTUnwrap(reference.addVoiceWithResult(sample: sample, gain: 0.7, pan: -0.3,
                    playbackStep: 0.875, loop: loop, initialSourceFrame: initialFrame,
                    volumeEnvelope: volume, panEnvelope: pan, keyOffFrame: 157,
                    fadeoutFrameDecrement: 1.0 / 65_536, sourceOnsetElapsedFrames: 0).voiceIndex)
                let b = try XCTUnwrap(prepared.addPreparedLoopVoice(storage.birth).voiceIndex)
                let beforeA = try XCTUnwrap(reference.voiceDiagnostic(forVoiceAt: a))
                let beforeB = try XCTUnwrap(prepared.voiceDiagnostic(forVoiceAt: b))
                XCTAssertEqual(beforeA.sourceOnsetDurationFrames, beforeB.sourceOnsetDurationFrames)
                XCTAssertEqual(beforeA.sourceOnsetElapsedFrames, 0)
                XCTAssertEqual(beforeB.sourceOnsetElapsedFrames, 0)
                var remaining = 1_433, ordinal = 0
                let partitions = [1, 7, 13, 64, 3, 211, 512]
                while remaining > 0 {
                    let count = min(remaining, partitions[ordinal % partitions.count])
                    let lhs = reference.render(frames: count), rhs = prepared.render(frames: count)
                    XCTAssertEqual(lhs.interleavedPCM, rhs.interleavedPCM,
                        "rate=\(rate), loop=\(loop), envelopes=\(envelopes), initial=\(initialFrame), partition=\(ordinal)")
                    let va = try XCTUnwrap(reference.voiceDiagnostic(forVoiceAt: a))
                    let vb = try XCTUnwrap(prepared.voiceDiagnostic(forVoiceAt: b))
                    XCTAssertEqual(va.samplePosition, vb.samplePosition)
                    XCTAssertEqual(va.pingPongDirection, vb.pingPongDirection)
                    XCTAssertEqual(va.sourceOnsetElapsedFrames, vb.sourceOnsetElapsedFrames)
                    XCTAssertEqual(va.keyOn, vb.keyOn)
                    XCTAssertEqual(va.fadeoutValue, vb.fadeoutValue)
                    remaining -= count; ordinal += 1
                }
                withExtendedLifetime(storage) {}
            }
        } } }
    }

    func testOnePreparedPayloadIsSharedAndNativeResetReleasesAllVoiceReferences() throws {
        let cache = CSoftwareMixerSharedSamplePayloadCache()
        let mixer = CSoftwareMixer(config: .init(sampleRate: 48_000, channelCount: 2))
        defer { mixer.clearVoices(); withExtendedLifetime(cache) {} }
        let sample = MixerSampleBuffer(monoPCM: Array(repeating: 0.25, count: 64))
        let first = try XCTUnwrap(CSoftwareMixerPreparedLoopBirthStorage(cache: cache, sample: sample))
        let second = try XCTUnwrap(CSoftwareMixerPreparedLoopBirthStorage(cache: cache, sample: sample))
        XCTAssertEqual(first.birth.payload, second.birth.payload)
        var native = VTXCMixerSharedSamplePayloadDiagnostics()
        XCTAssertEqual(vtx_c_mixer_shared_sample_payload_get_diagnostics(first.birth.payload, &native), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(native.active_voice_reference_count, 0)
        XCTAssertNotNil(mixer.addPreparedLoopVoice(first.birth).voiceIndex)
        XCTAssertNotNil(mixer.addPreparedLoopVoice(second.birth).voiceIndex)
        XCTAssertEqual(vtx_c_mixer_shared_sample_payload_get_diagnostics(first.birth.payload, &native), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(native.active_voice_reference_count, 2)
        XCTAssertEqual(native.payload_bytes_allocated, UInt64(sample.frameCount * MemoryLayout<Float>.stride))
        mixer.clearVoices()
        XCTAssertEqual(vtx_c_mixer_shared_sample_payload_get_diagnostics(first.birth.payload, &native), VTX_C_MIXER_STATUS_OK)
        XCTAssertEqual(native.active_voice_reference_count, 0)
        XCTAssertEqual(native.payload_destroy_count, 0, "Payload destruction belongs off audio after reset")
    }
}
