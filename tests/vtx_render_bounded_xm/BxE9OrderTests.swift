import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Public sine controls independently characterized against the pinned FT2 replayer.
final class BxE9OrderTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer
    private let rates = [44_100.0, 48_000]
    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ volume: UInt8 = 0,
                   _ effect: UInt8 = 0, _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private var original: [PlaybackCell] { [c(49, 1, 0xA8), c(0, 0, 0xB8, 14, 0x93)] }

    func testRawBirthSupersessionAndCurrentGenerationAppliedPitch() throws {
        for linear in [true, false] { for rate in rates {
            let input = song(original, linear), runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), tick = Int(rate / 50), birth = 9 * tick
            let ds = plan.diagnostics.vibratoEffects.filter { $0.syntheticRow == 1 }
            XCTAssertEqual(ds.map(\.activeEventIndex), [0, 1])
            XCTAssertEqual(ds.map(\.phaseAfter), [96, 64])
            XCTAssertEqual(ds.flatMap(\.stepUpdates).map(\.syntheticTick), [1, 2, 4, 5])
            XCTAssertEqual(ds.flatMap(\.stepUpdates).compactMap(\.vibrato).map(\.phaseBefore), [0, 32, 0, 32])
            let raw = try XCTUnwrap(plan.nativePitchWriterSpans.spans.first {
                $0.family == .vibrato && $0.supersededRetriggerBirth && $0.originalChildren.last?.syntheticTick == 3
            }?.originalChildren.last)
            XCTAssertEqual(raw.vibrato?.phaseBefore, 64)
            XCTAssertEqual(raw.vibrato?.phaseAfter, 96)
            XCTAssertEqual(raw.audibleNativePeriod(linear: linear), linear ? 4671 : 7100)
            XCTAssertEqual(plan.semanticPitch(row: 1, tick: 3, channel: 0)?.output, .known(linear ? 4608 : 6848))
            XCTAssertEqual(plan.semanticPitch(row: 1, tick: 3, channel: 0)?.associatedGeneration, 1)
            let observations = plan.nativePitchWriterSpans.spans.indices.flatMap { span in
                (0..<plan.nativePitchWriterSpans.spans[span].capturedChildCount).compactMap { plan.nativePitchWriter(span: span, child: $0) }
            }
            let suppressed = try XCTUnwrap(observations.first { $0.delivery == .supersededRetriggerBirth })
            XCTAssertEqual(suppressed.associatedGeneration, 0)
            XCTAssertEqual(suppressed.syntheticTick, 3)
            let events = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
            XCTAssertFalse(events.contains { $0.scheduledFrame == birth && $0.categories.contains("vibrato_update") })
            let later = events.filter { $0.scheduledFrame == 11 * tick && $0.categories.contains("vibrato_update") }
            XCTAssertEqual(later.count, 1)
            if case let .stepUpdate(source, _) = later.first?.action { XCTAssertEqual(source, 1) }
            else { XCTFail("Missing current-generation step") }
            let session = R(preparedPlan: plan).prepare(request(input, rate))
            _ = session.render(frames: birth)
#if DEBUG
            let old = try XCTUnwrap(session.sourceVoiceForTesting(0))
#endif
            _ = session.render(frames: 1)
#if DEBUG
            let newborn = try XCTUnwrap(session.sourceVoiceForTesting(1))
            XCTAssertEqual(newborn.samplePosition, newborn.sampleStep)
            XCTAssertEqual(newborn.sampleStep * 65536, rate == 48_000 ? 11418 : 12428)
            XCTAssertEqual(session.sourceVoiceForTesting(0)?.sampleStep, old.sampleStep)
#endif
            _ = session.render(frames: Int(rate * 0.005) - 1)
#if DEBUG
            XCTAssertEqual(session.sourceVoiceForTesting(0)?.active, false)
#endif
            _ = session.render(frames: 11 * tick - birth - Int(rate * 0.005))
#if DEBUG
            let before = try XCTUnwrap(session.sourceVoiceForTesting(1))
#endif
            _ = session.render(frames: 1)
#if DEBUG
            let after = try XCTUnwrap(session.sourceVoiceForTesting(1))
            XCTAssertEqual(after.sampleStep * 65536, rate == 48_000 ? (linear ? 10963 : 11125) : (linear ? 11933 : 12109))
            XCTAssertTrue(after.active && after.keyOn)
            XCTAssertNotEqual(before.samplePosition, after.samplePosition)
#endif
            try session.controlAdmission.requireSuccess()
        } }
    }

    func testUnaffectedDiagnosticReflectionHasNoRetriggerMember() {
        let input = song([original[0], c(0, 0, 0xB8)], true)
        let plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        XCTAssertFalse(plan.nativePitchWriterSpans.spans.isEmpty)
        XCTAssertTrue(plan.nativePitchWriterSpans.spans.allSatisfy { !$0.supersededRetriggerBirth })
        for diagnostic in plan.diagnostics.vibratoEffects {
            XCTAssertFalse(Mirror(reflecting: diagnostic).children.contains { $0.label == "supersededRetriggerBirth" })
        }
    }

    func testIntervalsEffectiveSpeedAndHeldLocalZeroDispatch() {
        for linear in [true, false] { for rate in rates {
            for (parameter, speed, held, births): (UInt8, Int, Bool, [Int]) in [
                (0x90, 6, false, [0]), (0x91, 6, false, [1, 2, 3, 4, 5]),
                (0x92, 6, false, [2, 4]), (0x93, 6, false, [3]), (0x97, 6, false, []),
                (0x93, 1, false, []), (0x92, 3, false, [2]), (0x92, 6, true, [2, 4, 6, 8, 10])] {
                let rows = [original[0], c(0, 0, 0xB8, 14, parameter)]
                let secondary = [c(), held ? c(0, 0, 0, 14, 0xE1) : c(0, 0, 0, 15, UInt8(speed))]
                let plan = A.adapt(song(rows, linear, secondary: secondary), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.diagnostics.retriggerEffects.flatMap(\.retriggerTicks), births)
                XCTAssertEqual(plan.pattern.events.count, 1 + births.count)
                if parameter == 0x92 && speed == 6 {
                    let admitted = plan.diagnostics.vibratoEffects.flatMap(\.stepUpdates).compactMap(\.vibrato)
                    XCTAssertTrue(admitted.allSatisfy { $0.phaseBefore == 0 && $0.phaseAfter == 32 })
                }
                if parameter == 0x97 { XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase, 160) }
            }
            let held = A.adapt(song([original[0], c(0, 0, 0, 15, 1), c(0, 0, 0xB8, 14, 0x93)], linear,
                secondary: [c(), c(), c(0, 0, 0, 14, 0xE1)]), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(held.diagnostics.retriggerEffects.last?.retriggerTicks, [1])
            XCTAssertEqual(held.pattern.events.last?.scheduledStartFrame, 8 * Int(rate / 50))
        } }
    }

    func testSuppressionMemorySilentCompletedAndEmptyRoutes() throws {
        for linear in [true, false] { for rate in rates {
            let suppressed = A.adapt(song([c(49, 1, 0xA8, 14, 0x44), original[1]], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(suppressed.diagnostics.vibratoEffects.last?.phaseBefore, 96)
            XCTAssertEqual(suppressed.diagnostics.vibratoEffects.last?.phaseAfter, 160)
            XCTAssertEqual(suppressed.semanticPitch(row: 1, tick: 3, channel: 0)?.output, .known(linear ? 4608 : 6848))
            let carried = A.adapt(song(original + [c(0, 0, 0xB0, 14, 0x92), c(0, 0, 0xB0)], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(carried.diagnostics.vibratoEffects.last?.phaseAfter, 192)
            XCTAssertTrue(carried.diagnostics.vibratoEffects.allSatisfy { $0.vibratoDepth == 8 && $0.vibratoSpeed == 8 })
            for kind in ["silent", "completed", "empty"] {
                let input = song(original, linear, kind: kind), plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, kind == "empty" ? 0 : 2)
                XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase, 64)
                if kind == "silent" { XCTAssertTrue(plan.pattern.events.allSatisfy { $0.gain == 0 }) }
                let session = R(preparedPlan: plan).prepare(request(input, rate))
                _ = session.render(frames: 9 * Int(rate / 50) + 1)
#if DEBUG
                if kind == "completed" { XCTAssertEqual(session.sourceVoiceForTesting(1)?.active, true) }
#endif
                try session.controlAdmission.requireSuccess()
            }
        } }
    }

    func testExactDeliveryAndAutomaticContinuationUseTheNewGeneration() throws {
        for linear in [true, false] { for rate in rates { for automatic in [false, true] {
            let input = song(original + [c()], linear, automatic: automatic), req = request(input, rate)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), renderer = R(preparedPlan: plan)
            let whole = renderer.render(req).block.interleavedPCM, birth = 9 * Int(rate / 50)
            let boundaries = [birth - 1, birth, birth + 1, birth + Int(rate * 0.005) - 1, birth + Int(rate * 0.005), birth + Int(rate * 0.005) + 1]
            XCTAssertEqual(renderer.renderWindowed(req, windowRows: 1).block.interleavedPCM, whole)
            XCTAssertEqual(renderer.render(req, splitFrameCounts: [birth, 1, req.boundedFrameCount - birth - 1]).block.interleavedPCM, whole)
            var streamed = [Float]()
            _ = renderer.renderStreaming(req, chunkFrameCount: 511) { _, _, block in streamed += block.interleavedPCM }
            XCTAssertEqual(streamed, whole)
#if DEBUG
            for indexed in [false, true] {
                XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(req, boundaries: boundaries, usePreindexedScheduling: indexed).block.interleavedPCM, whole)
            }
            let session = renderer.prepare(req)
            session.configureAdmissionForTesting(forceSlow: true)
            XCTAssertEqual(session.render(frames: req.boundedFrameCount).interleavedPCM, whole)
            session.reset()
            XCTAssertEqual(session.render(frames: req.boundedFrameCount).interleavedPCM, whole)
#endif
            if automatic {
                let clock = try XCTUnwrap(plan.instrumentAutovibrato(row: 2, tick: 0, channel: 0))
                let delta = PlaybackSongInstrumentAutovibratoComposition.delta(clock: clock)
                let bounds = PlaybackSongInstrumentAutovibratoComposition.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
                let expected = try XCTUnwrap(bounds.step(period: linear ? 4653 : 7028, delta: delta))
                XCTAssertEqual(plan.instrumentAutovibratoRequests.last { $0.syntheticRow == 2 && $0.syntheticTick == 0 }?.activeEventIndex, 1)
                XCTAssertEqual(plan.instrumentAutovibratoRequests.last { $0.syntheticRow == 2 && $0.syntheticTick == 0 }?.playbackStep, expected)
            }
        } } }
    }

    private func request(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongOfflineRenderRequest {
        .init(song: input, config: .init(sampleRate: rate), frames: input.patternsByIndex[0]!.rows.count * 6 * Int(rate / 50))
    }
    private func song(_ cells: [PlaybackCell], _ linear: Bool, secondary: [PlaybackCell]? = nil,
                      kind: String = "normal", automatic: Bool = false) -> PlaybackSong {
        let count = kind == "empty" ? 0 : kind == "completed" ? 16 : 256
        let pcm = (0..<count).map { Float((8192 * sin(Double($0) * .pi / 8)).rounded()) / 32768 }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: kind == "silent" ? 0 : 0.5,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0,
            loopLength: kind == "completed" ? 0 : count, loopType: kind == "completed" || count == 0 ? 0 : 1)
        let rows = cells.enumerated().map { index, cell in PlaybackRow(index: index, cells: [cell, secondary?[index] ?? c()]) }
        return .init(title: "Public Bx E9 order", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], autoVibrato: automatic
                ? .init(waveformType: 0, sweep: 0, depth: 8, rate: 16) : .disabled, noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
