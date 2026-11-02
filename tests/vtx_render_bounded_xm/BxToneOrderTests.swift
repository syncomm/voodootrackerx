import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Exact periods, phases and Q16 controls were independently observed in pinned FT2.
final class BxToneOrderTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer
    private let rates = [44_100.0, 48_000]
    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ effect: UInt8 = 0,
                   _ parameter: UInt8 = 0, _ volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func original(_ glissando: UInt8 = 0x31) -> [PlaybackCell] {
        [c(49, 1, 14, glissando, 0xA4), c(61, 0, 3, 3, 0xB8), c(0, 0, 3, 0, 0xB8), c(97)]
    }

    func testPhaseNativeRequestsSemanticOutputAndAppliedToneStayIndependent() throws {
        for linear in [true, false] { for rate in rates { for glissando: UInt8 in [0x30, 0x31] {
            let rows = original(glissando), input = song(rows, linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), frame = 13 * Int(rate / 50)
            let first = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)
            let second = try XCTUnwrap(plan.diagnostics.vibratoEffects.last)
            XCTAssertEqual(first.stepUpdates.compactMap(\.vibrato).map(\.phaseBefore), [0, 16, 32, 48, 64])
            XCTAssertEqual(first.stepUpdates.compactMap(\.vibrato).map(\.phaseAfter), [16, 32, 48, 64, 80])
            XCTAssertEqual(first.phaseAfter, 80)
            XCTAssertEqual(first.vibratoSpeed, 4)
            XCTAssertEqual(first.vibratoDepth, 8)
            XCTAssertEqual(second.stepUpdates.first?.vibrato?.phaseBefore, 80)
            XCTAssertEqual(second.stepUpdates.first?.vibrato?.phaseAfter, 96)
            XCTAssertEqual(second.stepUpdates.first?.audibleNativePeriod(linear: linear), linear ? 4606 : 6840)
            let tone = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.last)
            XCTAssertEqual(tone.stepUpdates.first?.linearPeriodAfter, linear ? 4536 : 6560)
            XCTAssertEqual(tone.targetLinearPeriod, linear ? 3840 : nil)
            XCTAssertEqual(tone.targetAmigaPeriod, linear ? nil : 3424)
            XCTAssertEqual(tone.directionAtExecution, .towardLowerPeriod)
            XCTAssertEqual(tone.portamentoSpeed, 3)
            XCTAssertEqual(plan.semanticPitch(row: 2, tick: 1, channel: 0)?.output,
                           .known(glissando == 0x31 ? (linear ? 4544 : 6464) : (linear ? 4536 : 6560)))
            let requests = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
                .filter { $0.scheduledFrame == frame && $0.categories.contains("step_update") }
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(requests.first?.categories.contains("vibrato_update") == true)
            XCTAssertTrue(requests.last?.categories.contains("portamento_update") == true)
            XCTAssertEqual(first.activeEventIndex, 0)
            XCTAssertEqual(tone.activeEventIndex, 0)
            XCTAssertEqual(plan.pattern.events.count, 1)
            if glissando == 0x31 {
                try assertApplied(input, plan, rate, frame, rate == 48_000 ? (linear ? 12097 : 12096) : (linear ? 13167 : 13166))
            }
            XCTAssertEqual(R().render(request(input, rate)).block.interleavedPCM,
                           R().render(request(song(rows, linear, bx: false), rate)).block.interleavedPCM)
        } } }
    }

    func testAutomaticBlankTickComposesFromLastToneNativeAndFiveSharesThePair() throws {
        for linear in [true, false] { for rate in rates {
            var rows = original()
            rows.insert(c(), at: 3)
            let input = song(rows, linear, automatic: true)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let expected = rate == 48_000 ? (linear ? 12897 : 12149) : (linear ? 14038 : 13223)
            let clock = try XCTUnwrap(plan.instrumentAutovibrato(row: 3, tick: 0, channel: 0))
            XCTAssertEqual(PlaybackSongInstrumentAutovibratoComposition.delta(clock: clock), -7)
            try assertApplied(input, plan, rate, 18 * Int(rate / 50), expected)
            let five = [c(49, 1, 14, 0x31, 0xA4), c(61, 0, 3, 3),
                        c(61, 0, 5, 1, 0xB8), c(0, 0, 5, 0, 0xB8), c(97)]
            let fiveSong = song(five, linear), fivePlan = A.adapt(fiveSong, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(fivePlan.diagnostics.vibratoEffects.map(\.phaseBefore), [0, 80])
            XCTAssertEqual(fivePlan.diagnostics.vibratoEffects.map(\.phaseAfter), [80, 160])
            let volumes = fivePlan.diagnostics.voiceStateUpdates.filter { $0.applied && $0.effectType == 5 }
            XCTAssertEqual(volumes.compactMap(\.effectiveVolumeAfter), Array(stride(from: 31, through: 22, by: -1)))
            try assertApplied(fiveSong, fivePlan, rate, 19 * Int(rate / 50),
                              rate == 48_000 ? (linear ? 12816 : 12096) : (linear ? 13950 : 13166))
            XCTAssertEqual(R().render(request(fiveSong, rate)).block.interleavedPCM,
                           R().render(request(song(five, linear, bx: false), rate)).block.interleavedPCM)
        } }
    }

    func testAllOfflineConsumersKeepPairOrderAcrossExactTickBoundaries() throws {
        for linear in [true, false] { for rate in rates {
            let input = song(original(), linear), req = request(input, rate), renderer = R()
            let whole = renderer.render(req).block.interleavedPCM, frame = 13 * Int(rate / 50)
            XCTAssertEqual(renderer.render(req, splitFrameCounts: [frame, 1, req.boundedFrameCount - frame - 1]).block.interleavedPCM, whole)
            XCTAssertEqual(renderer.renderWindowed(req, windowRows: 1).block.interleavedPCM, whole)
            var streamed = [Float]()
            _ = renderer.renderStreaming(req, chunkFrameCount: 511) { _, _, block in streamed += block.interleavedPCM }
            XCTAssertEqual(streamed, whole)
#if DEBUG
            for indexed in [false, true] {
                XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(req,
                    boundaries: [frame - 1, frame, frame + 1], usePreindexedScheduling: indexed).block.interleavedPCM, whole)
            }
            let staged = renderer.prepare(req)
            staged.configureAdmissionForTesting(forceSlow: true)
            XCTAssertEqual(staged.render(frames: req.boundedFrameCount).interleavedPCM, whole)
            try staged.controlAdmission.requireSuccess()
#endif
        } }
    }

    func testHeldZeroSpeedEmptyRoutingAndResetCarryDoNotInventSources() throws {
        for linear in [true, false] { for rate in rates {
            let held = [c(49, 1, 14, 0x30, 0xA4), c(49, 0, 3, 0, 0xB8), c(0, 0, 3, 0, 0xB0)]
            let heldSong = song(held, linear), plan = A.adapt(heldSong, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.diagnostics.vibratoEffects.map(\.phaseAfter), [80, 160])
            XCTAssertTrue(plan.diagnostics.tonePortamentoEffects.allSatisfy { $0.stepUpdates.isEmpty })
            XCTAssertNotEqual(R().render(request(heldSong, rate)).block.interleavedPCM,
                              R().render(request(song(held, linear, bx: false), rate)).block.interleavedPCM)
            let arrived = [c(49, 1, 14, 0x31, 0xA4), c(61, 0, 3, 0xFF, 0xB8), c(0, 0, 3, 0, 0xB0)]
            XCTAssertEqual(R().render(request(song(arrived, linear), rate)).block.interleavedPCM,
                           R().render(request(song(arrived, linear, bx: false), rate)).block.interleavedPCM)
            let empty = A.adapt(song(original(), linear, empty: true), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(empty.pattern.events.isEmpty)
            XCTAssertEqual(empty.diagnostics.vibratoEffects.last?.phaseAfter, 160)
            let silent = song(original(), linear, silent: true)
            let silentPlan = A.adapt(silent, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(silentPlan.pattern.events.count, 1)
            XCTAssertEqual(silentPlan.pattern.events.first?.gain, 0)
            try assertApplied(silent, silentPlan, rate, 13 * Int(rate / 50),
                              rate == 48_000 ? (linear ? 12097 : 12096) : (linear ? 13167 : 13166))
            for reset in [false, true] {
                let rows = Array(original().prefix(3)) + [reset ? c(0, 1) : c(53), c(0, 0, 4)]
                let carried = A.adapt(song(rows, linear), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(carried.diagnostics.vibratoEffects.last?.phaseBefore, reset ? 0 : 160)
                XCTAssertEqual(carried.pattern.events.count, reset ? 1 : 2)
            }
        } }
    }

    private func assertApplied(_ input: PlaybackSong, _ plan: PlaybackSongSyntheticPlan,
                               _ rate: Double, _ frame: Int, _ q16: Int) throws {
        let session = R(preparedPlan: plan).prepare(request(input, rate))
        _ = session.render(frames: frame)
#if DEBUG
        let before = try XCTUnwrap(session.sourceVoiceForTesting(0))
#endif
        _ = session.render(frames: 1)
#if DEBUG
        let after = try XCTUnwrap(session.sourceVoiceForTesting(0))
        XCTAssertEqual(after.sampleStep * 65536, Double(q16))
        XCTAssertTrue(after.active)
        XCTAssertTrue(after.keyOn)
        XCTAssertNotEqual(after.samplePosition, before.samplePosition)
#endif
        try session.controlAdmission.requireSuccess()
    }
    private func request(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongOfflineRenderRequest {
        .init(song: input, config: .init(sampleRate: rate), frames: input.patternsByIndex[0]!.rows.count * 6 * Int(rate / 50))
    }
    private func song(_ rows: [PlaybackCell], _ linear: Bool, bx: Bool = true,
                      automatic: Bool = false, empty: Bool = false, silent: Bool = false) -> PlaybackSong {
        let pcm = empty ? [] : (0..<256).map { Float((8192 * sin(Double($0) * .pi / 8)).rounded()) / 32768 }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: silent ? 0 : 0.5,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: empty ? 0 : 256, loopType: empty ? 0 : 1)
        let patternRows = rows.enumerated().map { index, cell in
            let volume = !bx && cell.volumeColumn >> 4 == 11 ? 0 : cell.volumeColumn
            return PlaybackRow(index: index, cells: [c(cell.note, cell.instrument, cell.effectType, cell.effectParam, volume), c()])
        }
        return .init(title: "Original Bx tone order", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: patternRows)],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], autoVibrato: automatic
                ? .init(waveformType: 0, sweep: 0, depth: 8, rate: 16) : .disabled, noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
