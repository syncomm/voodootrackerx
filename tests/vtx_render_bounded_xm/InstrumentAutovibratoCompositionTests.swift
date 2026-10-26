import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

final class InstrumentAutovibratoCompositionTests: XCTestCase {
    private typealias K = PlaybackSongInstrumentAutovibratoComposition
    private typealias A = PlaybackSongSyntheticAdapter
    private func raw(_ waveform: UInt8 = 0, depth: UInt8 = 8, rate: UInt8 = 16, sweep: UInt8 = 0) -> PlaybackInstrumentAutoVibrato {
        .init(waveformType: waveform, sweep: sweep, depth: depth, rate: rate)
    }

    func testSignedNearestTiesAwayAndTinyProducts() {
        XCTAssertEqual((-5...5).map { K.roundedQuotient($0, 2) }, [-3, -2, -2, -1, -1, 0, 1, 1, 2, 2, 3])
        for numerator in 0...1024 { for denominator in [1, 2, 3, 16, 255, 32768] {
            XCTAssertEqual(K.roundedQuotient(-numerator, denominator), -K.roundedQuotient(numerator, denominator))
        } }
        XCTAssertEqual(K.roundedQuotient(1, 32768), 0); XCTAssertEqual(K.roundedQuotient(-1, 32768), 0)
        XCTAssertEqual(K.roundedQuotient(.min, 1), .min); XCTAssertEqual(K.roundedQuotient(.max, 1), .max)
    }

    func testFourWaveformPhaseSignsAmplitudeAndNeutralControls() {
        // Reference controls establish advance-before-sample signs and depth-sized
        // native amplitude; nearest rounding intentionally omits negative-only bias.
        let phases: [UInt8] = [0, 16, 32, 48, 64, 128, 192]
        let expected = [[0, -3, -6, -7, -8, 0, 8], [-8, -8, -8, -8, -8, 8, 8],
                        [0, 1, 2, 3, 4, -8, -4], [0, -1, -2, -3, -4, -8, 4]]
        for type in UInt8(0)...3 {
            XCTAssertEqual(phases.map { K.delta(raw: raw(type), phaseAfter: $0, sweepElapsed: 0) }, expected[Int(type)])
            for phase in UInt8.min...UInt8.max { for depth: UInt8 in [0, 1, 8, 15] { for rate: UInt8 in [0, 1, 16, 63] {
                let value = K.delta(raw: raw(type, depth: depth, rate: rate), phaseAfter: phase, sweepElapsed: 999)
                XCTAssertLessThanOrEqual(abs(value), Int(depth))
                if depth == 0 || rate == 0 { XCTAssertEqual(value, 0) }
            } } }
        }
    }

    func testRawRampTypesMatchFreshReferencePhaseSixteenAnchors() {
        let down = PlaybackSongInstrumentAutovibratoClock.Waveform.rampDown.rawValue
        let up = PlaybackSongInstrumentAutovibratoClock.Waveform.rampUp.rawValue
        XCTAssertEqual(down, 2); XCTAssertEqual(up, 3)
        XCTAssertEqual(K.delta(raw: raw(down), phaseAfter: 16, sweepElapsed: 0), 1)
        XCTAssertEqual(K.delta(raw: raw(up), phaseAfter: 16, sweepElapsed: 0), -1)
    }

    func testSweepDurationsSaturateAndReleasedElapsedKeepsReachedAmplitude() {
        for sweep: UInt8 in [0, 1, 16, 255] {
            let metadata = raw(1, sweep: sweep)
            var previous = 0
            for elapsed in 0...512 {
                let magnitude = abs(K.delta(raw: metadata, phaseAfter: 16, sweepElapsed: elapsed))
                XCTAssertGreaterThanOrEqual(magnitude, previous); XCTAssertLessThanOrEqual(magnitude, 8)
                previous = magnitude
            }
            XCTAssertEqual(previous, 8)
            let releaseElapsed = sweep == 0 ? 0 : Int(sweep) / 2
            let reached = K.delta(raw: metadata, phaseAfter: 16, sweepElapsed: releaseElapsed)
            XCTAssertEqual(K.delta(raw: metadata, phaseAfter: 32, sweepElapsed: releaseElapsed), reached)
            XCTAssertEqual(K.delta(raw: metadata, phaseAfter: 192, sweepElapsed: releaseElapsed), -reached)
        }
        XCTAssertEqual(K.delta(raw: raw(1, sweep: 16), phaseAfter: 16, sweepElapsed: 1), -1)
        XCTAssertEqual(K.delta(raw: raw(1, sweep: 255), phaseAfter: 16, sweepElapsed: 1), 0)
        XCTAssertEqual(K.delta(raw: raw(1, sweep: 255), phaseAfter: 16, sweepElapsed: 16), -1)
    }

    func testMalformedInterpretationPreservesRawMetadata() {
        let metadata = raw(250, depth: 255, rate: 255, sweep: 255), original = metadata
        XCTAssertEqual(K.interpreted(metadata), raw(depth: 15, rate: 63, sweep: 255))
        for phase in UInt8.min...UInt8.max {
            XCTAssertEqual(K.delta(raw: metadata, phaseAfter: phase, sweepElapsed: 300),
                K.delta(raw: raw(depth: 15, rate: 63, sweep: 255), phaseAfter: phase, sweepElapsed: 300))
        }
        XCTAssertEqual(metadata, original)
    }

    func testReleasedClockUsesReachedSweepButContinuesPhase() {
        let clock = PlaybackSongInstrumentAutovibratoClock.Result(phaseBefore: 32, phaseAfter: 192,
            elapsedTicks: 100, sweepElapsed: 3, sweepReached: false, released: true,
            raw: raw(sweep: 16), waveform: .sine, status: .ordinary,
            lastResetOrdinal: 0, resetCause: .rowEntry)
        XCTAssertEqual(K.delta(clock: clock), 2)
    }

    func testModeAndRetainedSourceBoundsPreserveAncestryAndZeroHold() throws {
        for rate in [44_100.0, 48_000] { for linear in [true, false] { for source in [1.0, 8363] {
            let bounds = K.Bounds(linear: linear, baseSampleRate: source, outputSampleRate: rate)
            let upper = source == 8363 ? (linear ? 9216 : 65535)
                : (linear ? (rate == 44100 ? 5045 : 4954) : (rate == 44100 ? 2544 : 2337))
            XCTAssertEqual(bounds.upper, upper)
            let scale = linear ? 1.0 : 4
            XCTAssertEqual(bounds.step(period: Double(upper) * scale, delta: 15),
                A.referencePlaybackStep(nativePeriod: Double(upper), linear: linear, baseSampleRate: source, outputSampleRate: rate))
            for native in [0, upper + 1, 14081, 65535] where native == 0 || native > upper {
                XCTAssertEqual(bounds.step(period: Double(native) * scale, delta: -15),
                    A.referencePlaybackStep(nativePeriod: Double(native), linear: linear, baseSampleRate: source, outputSampleRate: rate))
            }
            XCTAssertEqual(bounds.step(period: scale, delta: -1), 0)
            XCTAssertEqual(bounds.step(period: scale, delta: -15), 0)
            XCTAssertEqual(bounds.step(period: scale, delta: 1),
                A.referencePlaybackStep(nativePeriod: 2, linear: linear, baseSampleRate: source, outputSampleRate: rate))
            XCTAssertNil(bounds.step(period: -.infinity, delta: 1))
        } } }
        let aliased = K.Bounds(linear: true, baseSampleRate: 10_000_000, outputSampleRate: 48000)
        XCTAssertEqual(aliased.upper, 0)
        XCTAssertEqual(aliased.step(period: 4608, delta: 15),
            A.playbackStep(linearPeriod: 4608, baseSampleRate: 10_000_000, outputSampleRate: 48000))
    }
}
