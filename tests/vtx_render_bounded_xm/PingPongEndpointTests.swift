import Foundation
import MixerCore
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Independent public controls for the native 87be425 FT2 numerical traversal oracle.
final class PingPongEndpointTests: XCTestCase {
    private typealias R = PlaybackSongOfflineRenderer
    private let rates = [44_100.0, 48_000.0]
    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ effect: UInt8 = 0,
                   _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    func testNativeLastEndpointAndFirstRowContinuationAcrossFormatsModesRatesAndProfiles() throws {
        for bit in [8, 16] { for linear in [true, false] { for rate in rates { for profile in MixerMixProfile.allCases {
            let song = try fixture([[c(49, 1, 9, 1)], [c()], [c()]], bit: bit, linear: linear)
            let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            let frame = 3 * Int(rate / 50), request = PlaybackSongOfflineRenderRequest(song: song, config: config, frames: frame + 17)
            let renderer = R(preparedPlan: plan), result = renderer.render(request)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.pattern.events[0].initialSourceFrame, 256)
            XCTAssertEqual(song.instrumentsByIndex[1]?.samples.first?.sourceBitDepthBits, bit)
            XCTAssertEqual(result.block.interleavedPCM[0], 0) // G02 remains independent of the moving source.
            let expected = Float(0.0625) * config.panLaw.leftGain(for: 0) * config.outputScale / Float(Int(rate * 0.005))
            XCTAssertEqual(result.block.interleavedPCM[2], expected, accuracy: 1e-10)
#if DEBUG
            let session = renderer.prepare(request)
            _ = session.render(frames: 1)
            let first = try XCTUnwrap(session.sourceVoiceForTesting(0))
            XCTAssertEqual(first.samplePosition, 256 + first.sampleStep)
            XCTAssertEqual(first.pingPongDirection, 1)
            XCTAssertEqual(first.sourceOnsetElapsedFrames, 1)
            _ = session.render(frames: frame - 1)
            let current = try XCTUnwrap(session.sourceVoiceForTesting(0))
            // Fresh native row-boundary values; these are not the old 2(L-1) projection.
            let nativeCursor = rate == 48_000 ? 253.767578125 : 253.7774658203125
            XCTAssertEqual(current.samplePosition, nativeCursor)
            XCTAssertEqual(current.pingPongDirection, 1)
            XCTAssertEqual(current.sourceOnsetElapsedFrames, Int(rate * 0.005))
            let continuation = try XCTUnwrap(renderer.continuationsForTesting(plan, at: frame, config: config).first)
            XCTAssertEqual(continuation.eventIndex, 0)
            XCTAssertEqual(continuation.runtimeState.samplePosition, current.samplePosition)
            XCTAssertEqual(continuation.runtimeState.pingPongDirection, current.pingPongDirection)
#endif
            try assertPaths(renderer, request)
        } } } }
    }

    func testScalarProjectionUsesExclusiveTurningCoordinateAndBoundedCrossingParity() {
        // Native-backed [3,8) controls: upper sample 7 is held while the phase reaches 8.
        let cases: [(Double, Int32, Double, Double, Int32)] = [
            (7, 1, 0, 7, 1), (7, 1, 0.5, 7.5, 1), (7, 1, 1, 8, -1),
            (7, 1, 1.5, 7.5, -1), (7, 1, 2, 7, -1), (7, 1, 6, 3, 1),
            (7, 1, 11, 8, -1), (7, 1, 20.5, 7.5, 1), (7.5, -1, 0.5, 7, -1),
            (3.25, -1, 0.5, 3.25, 1), (0, 1, 2, 2, 1), (0, 1, 1_000_007, 7, 1)
        ]
        for (position, direction, distance, expectedPosition, expectedDirection) in cases {
            var next = Double.nan, facing: Int32 = 0
            XCTAssertEqual(vtx_c_mixer_project_ping_pong_cursor(position, direction, distance, 3, 8, &next, &facing), VTX_C_MIXER_STATUS_OK)
            XCTAssertEqual(next, expectedPosition)
            XCTAssertEqual(facing, expectedDirection)
        }
        for distance in [-1.0, .infinity, .nan] {
            var next = 0.0, direction: Int32 = 0
            XCTAssertEqual(vtx_c_mixer_project_ping_pong_cursor(3, 1, distance, 3, 8, &next, &direction), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        }
    }

    func testTinyOddAndPhysicalEndLoopsReadSafelyAcrossRepeatedReversalsAndHolds() throws {
        for length in [1, 2, 3, 5] { for tail in [0, 3] { for step in [0.5, 1, 1.5, Double(2 * length) + 0.25, Double(4 * length)] {
            let end = 3 + length, sample = MixerSampleBuffer(monoPCM: (0..<(end + tail)).map { Float($0) / 16 })
            let loop = MixerSampleLoop(mode: .pingPong, startFrame: 3, endFrame: end)
            let config = MixerRenderConfig(sampleRate: 48_000, channelCount: 1)
            let whole = CSoftwareMixer(config: config), split = CSoftwareMixer(config: config)
            let voice = whole.addVoice(sample: sample, playbackStep: step, loop: loop, initialSourceFrame: end - 1)
            _ = split.addVoice(sample: sample, playbackStep: step, loop: loop, initialSourceFrame: end - 1)
            let expected = whole.render(frames: 41).interleavedPCM
            let actual = split.render(frames: 1).interleavedPCM + split.render(frames: 7).interleavedPCM + split.render(frames: 33).interleavedPCM
            exact(actual, expected)
            let state = try XCTUnwrap(whole.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(state.active)
            XCTAssertGreaterThanOrEqual(state.samplePosition, 3)
            XCTAssertLessThanOrEqual(state.samplePosition, Double(end))
            XCTAssertTrue(expected.allSatisfy { $0 >= 3.0 / 16 && $0 <= Float(end - 1) / 16 })
            if length == 1 { XCTAssertEqual(expected, Array(repeating: 3.0 / 16, count: 41)) }
            XCTAssertTrue(whole.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 41, playbackStep: 0).wasAccepted)
            _ = whole.render(frames: 3)
            XCTAssertEqual(whole.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, state.samplePosition)
            XCTAssertEqual(whole.voiceDiagnostic(forVoiceAt: voice)?.pingPongDirection, state.pingPongDirection)
        } } }
    }

    func testChangingPitchHistoryUsesTheSameGeometryInIndexedFallbackAndStreamedWindows() throws {
        let rows = [[c(49, 1, 9, 1)], [c(0, 0, 1, 4)], [c(0, 0, 2, 3)],
            [c(0, 0, 14, 0x11)], [c()], [c(49, 1, 9, 255)], [c()]]
        for linear in [true, false] { for rate in rates { for profile in MixerMixProfile.allCases {
            let song = try fixture(rows, bit: 16, linear: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            XCTAssertGreaterThan(plan.diagnostics.portamentoSlideEffects.flatMap(\.stepUpdates).count, 0)
            let renderer = R(preparedPlan: plan), request = PlaybackSongOfflineRenderRequest(
                song: song, config: .init(sampleRate: rate, mixProfile: profile), frames: rows.count * 3 * Int(rate / 50))
            try assertPaths(renderer, request)
#if DEBUG
            let session = renderer.prepare(request)
            var rendered = 0
            for boundary in [3, 6, 9, 12].map({ $0 * Int(rate / 50) }) {
                _ = session.render(frames: boundary - rendered); rendered = boundary
                let current = try XCTUnwrap(session.sourceVoiceForTesting(0))
                let carry = try XCTUnwrap(renderer.continuationsForTesting(plan, at: boundary, config: request.config).first)
                XCTAssertEqual(carry.runtimeState.samplePosition, current.samplePosition)
                XCTAssertEqual(carry.runtimeState.pingPongDirection, current.pingPongDirection)
                XCTAssertEqual(carry.playbackStep, current.sampleStep)
            }
#endif
        } } }
    }

    func testLengthOneDescriptorReachesCAndPreservesWindowContinuity() throws {
        for linear in [true, false] { for rate in rates {
            let song = try fixture([[c(49, 1)], [c()], [c()]], linear: linear, length: 4, start: 3, span: 1)
            let renderer = R(), request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: 3)
            let result = renderer.render(request)
            XCTAssertEqual(result.plan.pattern.events.first?.loop.mode, .pingPong)
            XCTAssertTrue(result.block.interleavedPCM[(Int(rate * 0.005) * 2)...].allSatisfy { $0 == Float(30) / 128 })
            try assertPaths(renderer, request)
        } }
    }

    func testOrdinaryWindowRestoresExactUpperTurnAtPhysicalSampleEnd() throws {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 1, 2, 3], volume: 1,
            relativeNote: 0, finetune: 0, baseSampleRate: 100, loopStart: 1, loopLength: 3, loopType: 2)
        let rows = (0..<7).map { PlaybackRow(index: $0, cells: [$0 == 0 ? c(49, 1) : c()]) }
        let song = PlaybackSong(title: "Public physical-end checkpoint", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 1, bpm: 250))
        for profile in MixerMixProfile.allCases {
            let config = MixerRenderConfig(sampleRate: 100, channelCount: 1, mixProfile: profile)
            let request = PlaybackSongOfflineRenderRequest(song: song, config: config, frames: 7), renderer = R()
            let whole = renderer.render(request)
            exact(whole.block.interleavedPCM, [Float(0), 1, 2, 3, 3, 3, 2].map { $0 * config.outputScale })
            exact(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
            exact(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
            exact(renderer.render(request, splitFrameCounts: [1, 2, 1, 3]).block.interleavedPCM, whole.block.interleavedPCM)
            var streamed = [Float]()
            _ = renderer.renderStreaming(request, chunkFrameCount: 2) { _, _, block in streamed += block.interleavedPCM }
            exact(streamed, whole.block.interleavedPCM)
#if DEBUG
            let carry = try XCTUnwrap(renderer.continuationsForTesting(whole.plan, at: 4, config: config).first)
            XCTAssertEqual(carry.runtimeState.samplePosition, 4)
            XCTAssertEqual(carry.runtimeState.pingPongDirection, -1)
            let mixer = CSoftwareMixer(config: config)
            let attempt = R.scheduleContinuation(carry, on: mixer)
            XCTAssertTrue(attempt.wasAccepted)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: try XCTUnwrap(attempt.voiceIndex))?.samplePosition, 4)
            XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [3 * config.outputScale])
#endif
        }
    }

    func testG41BAdmissionMemoryAndRefusedReplacementRemainIndependentOfTraversal() throws {
        let rows = [[c(49, 1, 9, 1)], [c(49, 1, 9, 2)], [c(0, 0, 9, 3)],
            [c(0, 2, 9, 4)], [c(49, 2, 9, 2)], [c(49, 1, 9, 0)]]
        for bit in [8, 16] { for linear in [true, false] { for rate in rates {
            let song = try fixture(rows, bit: bit, linear: linear), renderer = R()
            let result = renderer.render(.init(song: song, config: .init(sampleRate: rate), rows: rows.count))
            XCTAssertEqual(result.plan.pattern.events.count, 1)
            XCTAssertEqual(result.plan.xmChannelRows.map { $0.controls.sampleOffsetMemory?.offsetFrames }, [256, 512, 512, 512, 512, 512])
            let retirement = try XCTUnwrap(result.sameChannelVoiceLifetime.replacementEvents.first)
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.count, 1)
            XCTAssertNil(retirement.newEventIndex)
            XCTAssertEqual(retirement.replacementFrame, 3 * Int(rate / 50))
            XCTAssertEqual(retirement.completionFrame, retirement.replacementFrame + Int(rate * 0.005))
            XCTAssertEqual(result.plan.diagnostics.eventMappings.first?.sampleIndex, 0)
        } } }
    }

    private func assertPaths(_ renderer: R, _ request: PlaybackSongOfflineRenderRequest) throws {
        let whole = renderer.render(request)
        try whole.controlAdmission.requireSuccess()
        exact(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
        exact(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
        exact(renderer.render(request, splitFrameCounts: [1, 7, 232, 1, 1423, whole.block.frameCount - 1664]).block.interleavedPCM, whole.block.interleavedPCM)
        var pcm = [Float]()
        _ = renderer.renderStreaming(request, chunkFrameCount: 137) { _, _, block in pcm += block.interleavedPCM }
        exact(pcm, whole.block.interleavedPCM); pcm.removeAll(keepingCapacity: true)
        _ = renderer.renderWindowedStreaming(request, windowRows: 1) { _, _, _, block in pcm += block.interleavedPCM }
        exact(pcm, whole.block.interleavedPCM)
    }
    private func exact(_ actual: [Float], _ expected: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.withUnsafeBytes { a in expected.withUnsafeBytes { a.elementsEqual($0) } }, "Float32 PCM differs", file: file, line: line)
    }

    /// Independent XM1.04 writer. Formula values distinguish endpoint interpolation from reflection.
    private func fixture(_ rows: [[PlaybackCell]], bit: Int = 8, linear: Bool = true,
                         length: Int = 513, start: Int = 251, span: Int = 6) throws -> PlaybackSong {
        func le(_ value: Int, _ width: Int) -> [UInt8] { (0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        func text(_ string: String, _ count: Int) -> [UInt8] { Array((Array(string.utf8) + Array(repeating: 0, count: count)).prefix(count)) }
        let channels = rows.map(\.count).max() ?? 1
        var bytes = Array("Extended Module: ".utf8) + text("G41C public control", 20) + [26]
        bytes += text("VTX synthetic", 20) + le(0x104, 2) + le(276, 4)
        bytes += [1, 0, channels, 1, 2, linear ? 1 : 0, 3, 125].flatMap { le($0, 2) } + Array(repeating: 0, count: 256)
        bytes += le(9, 4) + [0] + le(rows.count, 2) + le(rows.count * channels * 5, 2)
        for row in rows { for cell in row + Array(repeating: c(), count: channels - row.count) {
            bytes += [cell.note, cell.instrument, cell.volumeColumn, cell.effectType, cell.effectParam]
        } }
        for instrument in 1...2 {
            let count = instrument == 2 ? 0 : length, width = bit / 8
            var header = Array(repeating: UInt8(0), count: 263)
            header.replaceSubrange(0..<4, with: le(263, 4)); header.replaceSubrange(27..<29, with: le(1, 2))
            header.replaceSubrange(29..<33, with: le(40, 4)); bytes += header
            var sample = Array(repeating: UInt8(0), count: 40)
            sample.replaceSubrange(0..<4, with: le(count * width, 4))
            if count > 0 {
                sample.replaceSubrange(4..<8, with: le(start * width, 4)); sample.replaceSubrange(8..<12, with: le(span * width, 4))
                sample[12] = 64; sample[14] = UInt8((bit == 16 ? 16 : 0) | 2); sample[15] = 128
            }
            bytes += sample
            var previous = 0
            for frame in 0..<count {
                let value = (((frame * 17 + 29) % 101 - 50) + (frame >= 256 ? 20 : frame >= 128 ? -20 : 0)) * (bit == 16 ? 256 : 1)
                bytes += le(value - previous, width); previous = value
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-pingpong-\(UUID().uuidString).xm")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        return try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
    }
}
