import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Characterizes existing conversion; these controls do not approve a composition clamp.
final class InstrumentAutovibratoBoundaryPreflightTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]

    func testNativeWordAndLinearExponentEdgesAreDifferentBoundaries() throws {
        // Literal Q16 results from current G30 conversion, not an automatic oscillator.
        let linear = [[794678, 194, 0, 0, 6357427, 0, 796114, 0],
                      [730110, 178, 0, 0, 5840886, 0, 731429, 0]]
        let amiga = [[21276843, 2308, 2308, 1511, 1511, 664, 324, 0],
                     [19548100, 2121, 2120, 1388, 1388, 610, 298, 0]]
        let periods = [1, 9216, 9217, 14080, 14081, 31999, 65535, 65536]
        for (i, rate) in rates.enumerated() { for isLinear in [true, false] {
            for (j, period) in periods.enumerated() {
                let value = isLinear
                    ? A.playbackStep(linearPeriod: Double(period), baseSampleRate: 8363, outputSampleRate: rate)
                    : A.playbackStep(amigaPeriod: Double(period) * 4, baseSampleRate: 8363, outputSampleRate: rate)
                XCTAssertEqual(try XCTUnwrap(value) * 65536, Double((isLinear ? linear : amiga)[i][j]))
            }
            XCTAssertEqual(A.referencePlaybackStep(nativePeriod: 0, linear: isLinear,
                baseSampleRate: 8363, outputSampleRate: rate), 0)
            XCTAssertNil(A.referencePlaybackStep(nativePeriod: -1, linear: isLinear,
                baseSampleRate: 8363, outputSampleRate: rate))
        } }
    }

    func testPositiveStepBoundaryAlsoDependsOnSourceConversionInputs() throws {
        // Rate one is an existing supported test input. Q16 quantization reaches zero
        // before the Linear exponent edge and before the Amiga UInt16 word edge.
        for (i, rate) in rates.enumerated() { for linear in [true, false] {
            let last = (linear ? [5045, 4954] : [2544, 2337])[i]
            XCTAssertEqual(A.referencePlaybackStep(nativePeriod: Double(last), linear: linear,
                baseSampleRate: 1, outputSampleRate: rate), 1.0 / 65536)
            XCTAssertEqual(A.referencePlaybackStep(nativePeriod: Double(last + 1), linear: linear,
                baseSampleRate: 1, outputSampleRate: rate), 0)
        } }
    }

    func testExistingOrdinaryLinearAncestryReachesHighPeriodHoldAndResumesSameCSource() throws {
        for (i, rate) in rates.enumerated() {
            // C-0 7680 -> two 2C0 ticks -> 9216 -> X21 9217 -> X11 9216.
            let rows = [[c(1, 1)], [c(fx: 2, p: 0xc0)], [c(fx: 33, p: 0x21)],
                        [c()], [c(fx: 33, p: 0x11)]]
            let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
                pcm: (0..<256).map { Float(sin(Double($0) * .pi / 8) / 16) }, volume: 0.5,
                panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 256, loopType: 1)
            let instrument = PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))
            let song = PlaybackSong(title: "Public native boundary preflight",
                orders: [.init(orderIndex: 0, patternIndex: 0)],
                patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
                instrumentsByIndex: [1: instrument], restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: true)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), source = try XCTUnwrap(plan.pattern.events.first)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.portamentoSlideEffects.first?.stepUpdates.map(\.linearPeriodAfter), [8448, 9216])
            for (row, period) in [(0, 7680.0), (1, 9216), (2, 9217), (3, 9217), (4, 9216)] {
                let semantic = try XCTUnwrap(plan.semanticPitch(row: row, tick: row == 1 ? 2 : 0, channel: 0))
                XCTAssertEqual(semantic.base, .known(period)); XCTAssertEqual(semantic.output, .known(period))
                XCTAssertEqual(semantic.associatedGeneration, 0); XCTAssertEqual(semantic.semanticInstrument, 1)
            }
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: source.sample, gain: source.gain, pan: source.pan,
                playbackStep: source.playbackStep, loop: source.loop)
            for event in runtime.events {
                if case let .stepUpdate(index, step) = event.action {
                    XCTAssertEqual(index, 0)
                    XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                        scheduledFrame: event.scheduledFrame, playbackStep: step).wasAccepted)
                }
            }
            let unit = Int(rate / 50), positive = Double([194, 178][i]) / 65536
            _ = mixer.render(frames: 6 * unit)
            let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertEqual(before.sampleStep, positive)
            _ = mixer.render(frames: 6 * unit)
            let held = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(held.active); XCTAssertEqual(held.sampleStep, 0)
            XCTAssertEqual(held.samplePosition, before.samplePosition)
            _ = mixer.render(frames: 1)
            let resumed = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(resumed.active); XCTAssertEqual(resumed.sampleStep, positive)
            XCTAssertEqual(resumed.samplePosition, held.samplePosition + positive, accuracy: 1e-9)
        }
    }

    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, fx: UInt8 = 0, p: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: fx, effectParam: p)
    }
}
