import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original public controls and numerical observations from the pinned external native observer.
final class LinearVibratoNativeWordTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testNativeWordBoundariesAndFractionalBaseStorageBeforeModulation() throws {
        // Executed native doVibrato/period conversion at 87be42543dac82cf802b5bddad917bda62ace131.
        // Fractions enter native base storage first; the signed temporary output wraps independently.
        let observations: [(Double, Int, Double, Int, Int)] = [
            (7744, 119, 7863, 658, 604), (68, -119, 65485, 832863, 765192),
            (118, -119, 65535, 796114, 731429), (119, -119, 0, 0, 0),
            (120, -119, 1, 794678, 730110), (65416, 119, 65535, 796114, 731429),
            (65417, 119, 0, 0, 0), (65535, 119, 118, 715041, 656944),
            (64.5, -119, 65481, 835875, 767960), (118.75, -119, 65535, 796114, 731429),
            (65535.75, 119, 118, 715041, 656944)
        ]
        for (base, delta, expected, q44100, q48000) in observations {
            let output = A.vibratoLinearPeriod(basePeriod: base, signedReferenceDelta: delta)
            XCTAssertEqual(output, expected)
            for (rate, q16) in [(44_100.0, q44100), (48_000, q48000)] {
                XCTAssertEqual(try XCTUnwrap(A.playbackStep(linearPeriod: output,
                    baseSampleRate: 8363, outputSampleRate: rate)) * 65_536, Double(q16))
            }
        }
        for base in [Double.nan, .infinity, -.infinity] {
            let output = A.vibratoLinearPeriod(basePeriod: base, signedReferenceDelta: 119)
            XCTAssertTrue(output.isNaN)
            XCTAssertNil(A.playbackStep(linearPeriod: output, baseSampleRate: 8363, outputSampleRate: 48_000))
        }
        XCTAssertEqual(A.clampedLinearPeriod(7863), 7744)
        XCTAssertEqual(A.clampedLinearPeriod(-51), 64.5)
    }

    func testExactFirstChangedTickPeriodStepAndAmigaNegativeControls() throws {
        for upper in [false, true] { for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(witness(upper: upper), upper: upper, linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let effect = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)
            let updates = effect.stepUpdates
            let periods: [Double] = linear
                ? (upper ? [187, 187, 187, 65485, 65485] : [7863, 7863, 7863, 7625, 7625])
                : (upper ? [141, 141, 141, 65439, 65439] : [29143, 29143, 29143, 28905, 28905])
            let q16: [Int]
            if linear {
                q16 = upper ? (rate == 48_000 ? [617281, 617281, 617281, 765192, 765192]
                    : [671870, 671870, 671870, 832863, 832863])
                    : (rate == 48_000 ? [604, 604, 604, 749, 749] : [658, 658, 658, 816, 816])
            } else {
                q16 = upper ? (rate == 48_000 ? [138639, 138639, 138639, 298, 298]
                    : [150899, 150899, 150899, 325, 325])
                    : (rate == 48_000 ? [670, 670, 670, 676, 676] : [730, 730, 730, 736, 736])
            }
            XCTAssertEqual(updates.map { linear ? $0.linearPeriodAfter : $0.amigaPeriodAfter! / 4 }, periods)
            XCTAssertEqual(updates.map { Int($0.playbackStepAfter * 65_536) }, q16)
            XCTAssertEqual(updates.map { $0.vibrato?.phaseBefore }, [0, 60, 120, 180, 240])
            XCTAssertEqual(updates.map(\.scheduledFrame), (7...11).map { $0 * Int(rate / 50) })
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(effect.activeEventIndex, 0)
            let base: Double = linear ? (upper ? 68 : 7744) : (upper ? 22 : 29024)
            let restoration = try XCTUnwrap(plan.diagnostics.vibratoEffects.last?.stepUpdates.last)
            XCTAssertEqual(linear ? restoration.linearPeriodAfter : restoration.amigaPeriodAfter! / 4, base)
            if linear {
                let old: [Double] = upper ? [187, 187, 187, 64.5, 64.5] : [7744, 7744, 7744, 7625, 7625]
                let first = try XCTUnwrap(zip(periods, old).enumerated().first { $0.element.0 != $0.element.1 })
                XCTAssertEqual(updates[first.offset].syntheticTick, upper ? 4 : 1)
                XCTAssertEqual(updates[first.offset].scheduledFrame, Int(rate / 50) * (upper ? 10 : 7))
            }
            // Apply the actual plan's pitch children through the existing C step protocol.
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 2))
            let voices = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)
            let voice = try XCTUnwrap(voices[0])
            for update in plan.diagnostics.vibratoEffects.flatMap(\.stepUpdates) {
                XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                    scheduledFrame: update.scheduledFrame, playbackStep: update.playbackStepAfter).wasAccepted)
            }
            let frame = updates[upper ? 3 : 0].scheduledFrame
            _ = mixer.render(frames: frame)
            let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            _ = mixer.render(frames: 1)
            let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(before.active && after.active)
            XCTAssertEqual(after.sampleStep, updates[upper ? 3 : 0].playbackStepAfter)
            XCTAssertEqual(after.samplePosition,
                (before.samplePosition + after.sampleStep).truncatingRemainder(dividingBy: 256), accuracy: 1e-10)
        } } }
    }

    func testSharedMemoryOrderedWritersAndCanonicalBaseAreIndependentOfOutputWord() throws {
        for upper in [false, true] { for rate in [44_100.0, 48_000] { for family: UInt8 in [4, 6] {
            let cells = [c(14, 0x42), c(4, 0xFF, note: upper ? 96 : 1, instrument: 1),
                c(family, volume: 0xBF), c(4), c(6), c()]
            let plan = A.adapt(song(cells, upper: upper), orderIndex: 0, sampleRate: rate)
            let mixed = plan.diagnostics.vibratoEffects[1]
            XCTAssertEqual(mixed.stepUpdates.compactMap(\.vibrato).map(\.phaseBefore),
                [44, 104, 164, 224, 28, 88, 148, 208, 12, 72])
            XCTAssertEqual(mixed.stepUpdates.map(\.syntheticTick), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
            XCTAssertEqual(mixed.stepUpdates.map(\.linearPeriodAfter), upper
                ? [187, 187, 65485, 65485, 187, 187, 65485, 65485, 187, 187]
                : [7863, 7863, 7625, 7625, 7863, 7863, 7625, 7625, 7863, 7863])
            XCTAssertTrue(plan.diagnostics.vibratoEffects.allSatisfy { $0.vibratoSpeed == 15 && $0.vibratoDepth == 15 })
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.vibratoEffects.last?.stepUpdates.last?.linearPeriodAfter, upper ? 68 : 7744)
        } } }
    }

    func testEveryDeliveryPartitionKeepsNativeOutputAndSourceCursor() throws {
        for upper in [false, true] { for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(witness(upper: upper), upper: upper, linear: linear)
            let request = PlaybackSongOfflineRenderRequest(song: input,
                config: .init(sampleRate: rate, channelCount: 2), rows: 5)
            let renderer = R(), result = renderer.render(request)
            for rows in [1, 2, 3] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, result.block.interleavedPCM)
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request,
                    windowRows: rows).block.interleavedPCM, result.block.interleavedPCM)
            }
            var pcm: [Float] = []
            let stream = renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in pcm += block.interleavedPCM }
            try stream.controlAdmission.requireSuccess()
            XCTAssertEqual(pcm, result.block.interleavedPCM)
            pcm = []
            let windowStream = renderer.renderWindowedStreaming(request, windowRows: 2) { _, _, _, block in pcm += block.interleavedPCM }
            try windowStream.controlAdmission.requireSuccess()
            XCTAssertEqual(pcm, result.block.interleavedPCM)
            #if DEBUG
            let first = (upper ? 10 : 7) * Int(rate / 50)
            var seed: UInt64 = 3902, frame = 0, boundaries = [first - 1, first, first + 1]
            while frame < result.block.frameCount {
                seed = seed &* 6364136223846793005 &+ 1
                frame += 1 + Int(seed % 2048)
                if frame < result.block.frameCount { boundaries.append(frame) }
            }
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: boundaries.sorted()).block.interleavedPCM, result.block.interleavedPCM)
            #endif
        } } }
    }

    private func witness(upper: Bool) -> [PlaybackCell] {
        [c(14, 0x42), c(4, 0xFF, note: upper ? 96 : 1, instrument: 1), c(4), c(), c(note: 97)]
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                   instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], upper: Bool, linear: Bool = true) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<256).map { Float(sin(Double($0) * .pi / 8) / 4) }, volume: 0.5,
            relativeNote: upper ? 23 : 0, finetune: upper ? 127 : -128, baseSampleRate: 8363,
            loopLength: 256, loopType: 1)
        return .init(title: "Original Linear native word", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map {
                .init(index: $0.offset, cells: [$0.element])
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
