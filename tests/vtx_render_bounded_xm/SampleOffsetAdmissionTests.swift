import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Independent synthetic controls for G41A's pinned FT2 numerical oracle
/// (87be42543dac82cf802b5bddad917bda62ace131); no reference implementation is embedded.
final class SampleOffsetAdmissionTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer
    private let rates = [44_100.0, 48_000.0]
    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ effect: UInt8 = 0,
                   _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    func testDecodedFrameUnitsAndExclusivePhysicalOrLoopAdmissionEnd() throws {
        for bit in [8, 16] { for linear in [true, false] { for rate in rates {
            for loop in 0...2 { for end in [255, 256, 257] {
                let input = try fixture([[c(49, 1, 9, 1)]], bit: bit, linear: linear,
                    length: loop == 0 ? end : 513, loop: loop, end: end)
                let sample = try XCTUnwrap(input.instrumentsByIndex[1]?.samples.first)
                XCTAssertEqual(sample.sourceBitDepthBits, bit)
                XCTAssertEqual(sample.sourceIsSignedPCM, true)
                XCTAssertEqual(sample.pcm[0], 0.5)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let admitted = end == 257
                XCTAssertEqual(plan.pattern.events.count, admitted ? 1 : 0, "bit=\(bit), loop=\(loop), end=\(end)")
                XCTAssertEqual(plan.xmChannelRows.first?.controls.sampleOffsetMemory?.offsetFrames, 256)
                XCTAssertEqual(plan.diagnostics.sampleOffsetEffects.first?.computedOffsetFrames, 256)
                XCTAssertEqual(plan.diagnostics.sampleOffsetEffects.first?.skipped, !admitted)
                if admitted {
                    XCTAssertEqual(plan.pattern.events[0].initialSourceFrame, 256)
                    XCTAssertEqual(plan.diagnostics.eventMappings[0].sampleIndex, 0)
                } else {
                    XCTAssertTrue(R().render(.init(song: input, config: .init(sampleRate: rate), frames: 257))
                        .block.interleavedPCM.allSatisfy { $0 == 0 })
                }
            } }
            let before = try fixture([[c(49, 1, 9, 0)]], bit: bit, linear: linear, loop: 1, end: 256)
            XCTAssertEqual(A.adapt(before, orderIndex: 0, sampleRate: rate).pattern.events.first?.initialSourceFrame, 0)
        } } }
    }

    func testWholeByteChannelMemoryNeedsANoteAndSurvivesInstrumentReplacement() throws {
        let rows = [[c(49, 1, 9, 1), c(49, 1, 9, 0)], [c(0, 0, 9, 2), c(0, 1, 9, 3)],
            [c(0, 1, 9, 4), c(49, 1, 9, 0)], [c(49, 0, 9, 0), c(49, 0, 9, 2)],
            [c(49, 2, 9, 0), c(49, 0, 9, 0)]]
        for bit in [8, 16] { for linear in [true, false] { for rate in rates {
            let input = try fixture(rows, bit: bit, linear: linear, length: 1025)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), [256, 0, 0, 256, 512, 256, 512])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.source.rowIndex), [0, 0, 2, 3, 3, 4, 4])
            let firstChannel = plan.xmChannelRows.filter { $0.channelIndex == 0 }.map(\.controls)
            XCTAssertEqual(firstChannel.map { $0.sampleOffsetMemory?.offsetFrames }, Array(repeating: 256, count: 5))
            XCTAssertEqual(firstChannel.last?.sampleOffsetMemory?.source.effectParam, 1)
            XCTAssertEqual(plan.diagnostics.eventMappings[5].instrumentIndex, 2)
            XCTAssertEqual(plan.diagnostics.eventMappings[5].sampleIndex, 0)
        } } }
        let cold = try fixture([[c(0, 0, 9, 2)], [c(0, 1, 9, 3)], [c(49, 0, 9, 0)]])
        let plan = A.adapt(cold, orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), [0])
        XCTAssertTrue(plan.xmChannelRows.allSatisfy { $0.controls.sampleOffsetMemory == nil })
    }

    func testCanonicalEmptyCommitsMemoryBeforePCMAdmissionIncludingNoteOnly() throws {
        for bit in [8, 16] { for linear in [true, false] { for rate in rates { for noteOnly in [false, true] {
            let rows = noteOnly
                ? [[c(49, 1, 9, 1)], [c(0, 2)], [c(49, 0, 9, 2)], [c(49, 1, 9, 0)]]
                : [[c(49, 1, 9, 1)], [c(49, 2, 9, 2)], [c(49, 1, 9, 0)]]
            let input = try fixture(rows, bit: bit, linear: linear, secondEmpty: true)
            XCTAssertEqual(input.instrumentsByIndex[2]?.noteSampleMap?.count, 96)
            XCTAssertEqual(input.instrumentsByIndex[2]?.samples.count, 0)
            XCTAssertEqual(input.xmSampleSlotProvenanceByInstrument[2]?.first?.isCanonicalEmptySlotHeader, true)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), emptyRow = noteOnly ? 2 : 1
            XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), [256, 512])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1, 1])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.source.rowIndex), [0, emptyRow + 1])
            let empty = try XCTUnwrap(plan.xmChannelRows.first { $0.source.rowIndex == emptyRow })
            XCTAssertEqual(empty.controls.sampleOffsetMemory?.offsetFrames, 512)
            XCTAssertEqual(empty.controls.sampleOffsetMemory?.source.effectParam, 2)
            XCTAssertEqual(empty.controls.sampleOffsetMemory?.source.source.rowIndex, emptyRow)
            XCTAssertNil(empty.controls.activeEventIndex)
            XCTAssertEqual(plan.diagnostics.sampleOffsetEffects.last?.memorySource?.source.rowIndex, emptyRow)
        } } } }
    }

    func testUnrepresentedAndAbsentRoutesDoNotBecomeCanonicalEmptyOrFallback() throws {
        for bit in [8, 16] { for linear in [true, false] { for rate in rates {
            let seed = try fixture([[c(48, 1, 9, 1)], [c(49, 1, 9, 2)], [c(48, 1, 9, 0)]], bit: bit, linear: linear)
            let represented = try XCTUnwrap(seed.instrumentsByIndex[1])
            var map = Array(repeating: 0, count: 96); map[48] = 5
            let unmapped = copy(seed, instrument: .init(index: 1, samples: represented.samples, noteSampleMap: map))
            let plan = A.adapt(unmapped, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), [256, 256])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 0])
            XCTAssertEqual(plan.xmChannelRows.last?.controls.sampleOffsetMemory?.source.effectParam, 1)
            let cold = try fixture([[c(0, 1)], [c(49, 0, 9, 2)]], bit: bit, linear: linear)
            let absent = copy(cold, instrument: .init(index: 1, samples: represented.samples, noteSampleMap: nil))
            let noRoute = A.adapt(absent, orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(noRoute.pattern.events.isEmpty)
            XCTAssertTrue(noRoute.xmChannelRows.allSatisfy { $0.controls.sampleOffsetMemory == nil })
        } } }
    }

    func testRejectedReplacementRetiresOneGenerationAtItsExactFiveMillisecondDeadline() throws {
        for bit in [8, 16] { for linear in [true, false] { for rate in rates { for released in [false, true] {
            let rows = released ? [[c(49, 1)], [c(97)], [c(49, 1, 9, 255)], [c(49, 1, 9, 0)], [c()]]
                : [[c(49, 1)], [c(49, 1, 9, 255)], [c(49, 1, 9, 0)], [c()]]
            let input = try fixture(rows, bit: bit, linear: linear, length: 2049)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let frame = (released ? 2 : 1) * 3 * Int(rate / 50), n = Int(rate * 0.005)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), frames: frame + n + 2)
            let renderer = R(preparedPlan: plan), result = renderer.render(request)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.sampleOffsetMemory?.offsetFrames, 65_280)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.sampleOffsetMemory?.source.effectParam, 255)
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.count, 1)
            let retirement = try XCTUnwrap(result.sameChannelVoiceLifetime.replacementEvents.first)
            XCTAssertEqual(retirement.oldEventIndex, 0)
            XCTAssertNil(retirement.newEventIndex)
            XCTAssertEqual(retirement.replacementFrame, frame)
            XCTAssertEqual(retirement.completionFrame, frame + n)
            XCTAssertTrue(result.block.interleavedPCM[(2 * (frame + n))...].allSatisfy { $0 == 0 })
            if !released {
                for k in [0, 1, n / 2, n - 1] {
                    XCTAssertEqual(result.block.interleavedPCM[2 * (frame + k)], 0.5 * (1 - Float(k) / Float(n)), accuracy: 1e-7)
                }
            }
#if DEBUG
            let session = renderer.prepare(request)
            _ = session.render(frames: frame)
            let before = try XCTUnwrap(session.sourceVoiceForTesting(0))
            _ = session.render(frames: 1)
            let fading = try XCTUnwrap(session.sourceVoiceForTesting(0))
            XCTAssertEqual(fading.sampleStep, before.sampleStep)
            XCTAssertEqual(fading.samplePosition, before.samplePosition + before.sampleStep, accuracy: 1e-8)
            XCTAssertEqual(fading.sourceOnsetElapsedFrames, n)
            XCTAssertEqual(fading.gainRamp?.songRetirement, true)
            XCTAssertEqual(fading.gainRamp?.totalFrames, n)
            _ = session.render(frames: n - 1)
            XCTAssertEqual(session.sourceVoiceForTesting(0)?.active, false)
            XCTAssertNil(session.sourceVoiceForTesting(1))
#endif
            if !released { try assertPaths(renderer, request) }
        } } } }
    }

    func testCompletedPriorSourceCannotBeResurrectedByRejectedOffset() throws {
        for linear in [true, false] { for rate in rates {
            let input = try fixture([[c(49, 1)], [c(49, 1, 9, 255)], [c(49, 1, 9, 0)]], linear: linear, length: 7)
            let result = R().render(.init(song: input, config: .init(sampleRate: rate), rows: 3))
            XCTAssertEqual(result.plan.pattern.events.count, 1)
            XCTAssertTrue(result.block.interleavedPCM[(3 * Int(rate / 50) * 2)...].allSatisfy { $0 == 0 })
            XCTAssertEqual(result.plan.xmChannelRows.last?.controls.sampleOffsetMemory?.offsetFrames, 65_280)
        } }
    }

    func testRefusedAttemptsDoNotExtendAnOlderTailDuringNewSourceOnset() throws {
        for linear in [true, false] { for rate in rates {
            // Deliberately synthetic timing overlaps G02/G03; no native XM BPM-range claim.
            let seed = try fixture([[c(49, 1)], [c(49, 1, 9, 255)], [c(49, 1)], [c(49, 1, 9, 255)], [c()]])
            let input = copy(seed, linear: linear, timing: .init(speed: 1, bpm: 1000))
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), n = Int(rate * 0.005)
            let tick = Int(rate * 2.5 / 1000), first = tick, second = 3 * tick
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), frames: second + n + 2)
            let renderer = R(preparedPlan: plan), result = renderer.render(request)
            XCTAssertEqual(plan.pattern.events.count, 2)
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.map(\.oldEventIndex), [0, 1])
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.map(\.completionFrame), [first + n, second + n])
#if DEBUG
            let session = renderer.prepare(request)
            _ = session.render(frames: 2 * tick + 1)
            let old = try XCTUnwrap(session.sourceVoiceForTesting(0)), newborn = try XCTUnwrap(session.sourceVoiceForTesting(1))
            XCTAssertEqual(old.gainRamp?.positionFrame, tick + 1)
            XCTAssertEqual(old.sourceOnsetElapsedFrames, tick)
            XCTAssertEqual(newborn.sourceOnsetElapsedFrames, 1)
            _ = session.render(frames: first + n - 2 * tick - 1)
            XCTAssertEqual(session.sourceVoiceForTesting(0)?.active, false)
            _ = session.render(frames: second + n - first - n)
            XCTAssertEqual(session.sourceVoiceForTesting(1)?.active, false)
#endif
            try assertPaths(renderer, request)
        } }
    }

    func testVolumeColumnToneRowsDoNotBecomeOffsetReplacementAttempts() throws {
        for linear in [true, false] { for rate in rates { for parameter: UInt8 in [1, 255] {
            let tone = PlaybackCell(note: 49, instrument: 1, volumeColumn: 0xF0, effectType: 9, effectParam: parameter)
            let input = try fixture([[c(49, 1)], [tone], [c()]], linear: linear, loop: 1, end: 256)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let frame = 3 * Int(rate / 50), request = PlaybackSongOfflineRenderRequest(
                song: input, config: .init(sampleRate: rate), frames: frame + 2)
            let renderer = R(preparedPlan: plan), result = renderer.render(request)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertTrue(result.sameChannelVoiceLifetime.replacementEvents.isEmpty)
            XCTAssertFalse(plan.xmEmptyRoutes.contains(where: \.retiresSource))
#if DEBUG
            let session = renderer.prepare(request)
            _ = session.render(frames: frame)
            let before = try XCTUnwrap(session.sourceVoiceForTesting(0))
            _ = session.render(frames: 1)
            let after = try XCTUnwrap(session.sourceVoiceForTesting(0))
            XCTAssertTrue(after.active)
            XCTAssertEqual(after.sampleStep, before.sampleStep)
            XCTAssertEqual(after.samplePosition, (before.samplePosition + before.sampleStep).truncatingRemainder(dividingBy: 256), accuracy: 1e-8)
            XCTAssertFalse(after.deactivateAfterGainRamp)
            XCTAssertNil(session.sourceVoiceForTesting(1))
#endif
        } } }
    }

    private func assertPaths(_ renderer: R, _ request: PlaybackSongOfflineRenderRequest) throws {
        let whole = renderer.render(request)
        try whole.controlAdmission.requireSuccess()
        XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
        XCTAssertEqual(renderer.render(request, splitFrameCounts: [1, 17, whole.block.frameCount - 18]).block.interleavedPCM, whole.block.interleavedPCM)
        var streamed = [Float]()
        _ = renderer.renderStreaming(request, chunkFrameCount: 137) { _, _, block in streamed += block.interleavedPCM }
        XCTAssertEqual(streamed, whole.block.interleavedPCM)
    }

    private func copy(_ source: PlaybackSong, instrument: PlaybackInstrument? = nil, linear: Bool? = nil,
                      timing: PlaybackTiming? = nil) -> PlaybackSong {
        var instruments = source.instrumentsByIndex
        if let instrument { instruments[instrument.index] = instrument }
        return .init(title: source.title, orders: source.orders, patternsByIndex: source.patternsByIndex,
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: timing ?? source.initialTiming, usesLinearFrequencyTable: linear ?? source.usesLinearFrequencyTable,
            xmSampleSlotProvenanceByInstrument: instrument == nil ? source.xmSampleSlotProvenanceByInstrument : [:])
    }

    /// Writes ordinary XM1.04 bytes independently: constant signed PCM makes the expected ramps mathematical.
    private func fixture(_ rows: [[PlaybackCell]], bit: Int = 8, linear: Bool = true, length: Int = 513,
                         loop: Int = 0, end: Int = 0, secondEmpty: Bool = false) throws -> PlaybackSong {
        func le(_ value: Int, _ width: Int) -> [UInt8] { (0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        func text(_ string: String, _ count: Int) -> [UInt8] { Array((Array(string.utf8) + Array(repeating: 0, count: count)).prefix(count)) }
        let channels = rows.map(\.count).max() ?? 1
        var bytes = Array("Extended Module: ".utf8) + text("G41B public control", 20) + [26]
        bytes += text("VTX synthetic", 20) + le(0x104, 2) + le(276, 4)
        bytes += [1, 0, channels, 1, 2, linear ? 1 : 0, 3, 125].flatMap { le($0, 2) } + Array(repeating: 0, count: 256)
        bytes += le(9, 4) + [0] + le(rows.count, 2) + le(rows.count * channels * 5, 2)
        for row in rows { for cell in row + Array(repeating: c(), count: channels - row.count) {
            bytes += [cell.note, cell.instrument, cell.volumeColumn, cell.effectType, cell.effectParam]
        } }
        for instrument in 1...2 {
            let empty = instrument == 2 && secondEmpty, count = empty ? 0 : length, width = bit / 8
            var header = Array(repeating: UInt8(0), count: 263)
            header.replaceSubrange(0..<4, with: le(263, 4)); header.replaceSubrange(27..<29, with: le(1, 2))
            header.replaceSubrange(29..<33, with: le(40, 4)); bytes += header
            var sample = Array(repeating: UInt8(0), count: 40)
            sample.replaceSubrange(0..<4, with: le(count * width, 4))
            if loop > 0 && !empty {
                sample.replaceSubrange(4..<8, with: le(251 * width, 4))
                sample.replaceSubrange(8..<12, with: le((end - 251) * width, 4))
            }
            sample[12] = empty ? 0 : 64; sample[14] = empty ? 0 : UInt8((bit == 16 ? 16 : 0) | loop)
            sample[15] = empty ? 0 : 128; bytes += sample
            if count > 0 { bytes += le(bit == 16 ? 16_384 : 64, width) + Array(repeating: 0, count: (count - 1) * width) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-offset-\(UUID().uuidString).xm")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        return try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
    }
}
