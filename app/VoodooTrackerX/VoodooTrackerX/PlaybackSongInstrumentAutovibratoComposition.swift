import Foundation

/// Value-only G32 arithmetic; constructing this helper never publishes physical pitch.
enum PlaybackSongInstrumentAutovibratoComposition {
    // Independently generated round(32768 * sin(pi * i / 128)), i=0...64.
    // Mathematical Q15 ordinates, not a copied reference replayer table.
    private static let quarterSine = [0, 804, 1608, 2411, 3212, 4011, 4808, 5602, 6393, 7180, 7962, 8740, 9512,
        10279, 11039, 11793, 12540, 13279, 14010, 14733, 15447, 16151, 16846, 17531, 18205, 18868,
        19520, 20160, 20788, 21403, 22006, 22595, 23170, 23732, 24279, 24812, 25330, 25833, 26320,
        26791, 27246, 27684, 28106, 28511, 28899, 29269, 29622, 29957, 30274, 30572, 30853, 31114,
        31357, 31581, 31786, 31972, 32138, 32286, 32413, 32522, 32610, 32679, 32729, 32758, 32768]

    static func interpreted(_ raw: PlaybackInstrumentAutoVibrato) -> PlaybackInstrumentAutoVibrato {
        .init(waveformType: raw.waveformType < 4 ? raw.waveformType : 0, sweep: raw.sweep,
            depth: min(15, raw.depth), rate: min(63, raw.rate))
    }

    /// Integer nearest rounding with half ties away from zero, including Int.min.
    static func roundedQuotient(_ numerator: Int, _ denominator: Int) -> Int {
        precondition(denominator > 0)
        let remainder = numerator % denominator
        let magnitude = remainder < 0 ? -remainder : remainder
        let rounds = magnitude >= denominator / 2 + denominator % 2
        return numerator / denominator + (rounds ? (numerator < 0 ? -1 : 1) : 0)
    }

    static func delta(raw: PlaybackInstrumentAutoVibrato, phaseAfter: UInt8, sweepElapsed: Int) -> Int {
        let metadata = interpreted(raw)
        guard metadata.depth > 0, metadata.rate > 0 else { return 0 }
        let phase = Int(phaseAfter), ordinate: Int
        switch metadata.waveformType {
        case 1: ordinate = phase < 128 ? -32768 : 32768
        case 2, 3:
            // Waveform names describe pitch direction: positive period lowers pitch.
            let ramp = metadata.waveformType == PlaybackSongInstrumentAutovibratoClock.Waveform.rampDown.rawValue
                ? phase : (256 - phase) & 255
            ordinate = (ramp < 128 ? ramp : ramp - 256) * 256
        default:
            let quadrant = phase / 64, offset = phase % 64
            ordinate = quarterSine[quadrant % 2 == 0 ? offset : 64 - offset] * (quadrant < 2 ? -1 : 1)
        }
        let duration = max(1, Int(metadata.sweep))
        let reached = metadata.sweep == 0 ? 1 : min(duration, max(0, sweepElapsed))
        // One bounded rational retains reached amplitude on release without Q8 overshoot.
        return roundedQuotient(ordinate * Int(metadata.depth) * reached, 32768 * duration)
    }

    static func delta(clock: PlaybackSongInstrumentAutovibratoClock.Result) -> Int {
        guard let raw = clock.raw, let phase = clock.phaseAfter else { return 0 }
        return delta(raw: raw, phaseAfter: phase, sweepElapsed: clock.sweepElapsed)
    }
    /// Cache once for retained source/output conversion inputs, independently of semantic owner.
    struct Bounds {
        let linear: Bool, baseSampleRate: Double, outputSampleRate: Double
        let upper: Int
        init(linear: Bool, baseSampleRate: Double, outputSampleRate: Double) {
            self.linear = linear; self.baseSampleRate = baseSampleRate; self.outputSampleRate = outputSampleRate
            func positive(_ period: Int) -> Bool {
                (PlaybackSongSyntheticAdapter.referencePlaybackStep(nativePeriod: Double(period), linear: linear,
                    baseSampleRate: baseSampleRate, outputSampleRate: outputSampleRate) ?? 0) > 0
            }
            let coefficient = (16777216 * baseSampleRate / outputSampleRate).rounded()
            // Keep unusual source ratios with internal UInt32 aliases outside this
            // automatic domain; their original G30 conversion remains authoritative.
            guard positive(1), !linear || coefficient <= Double(UInt32.max) / 2 else { upper = 0; return }
            var low = 1, high = linear ? 9216 : 65535
            if positive(high) { upper = high; return }
            while low < high {
                let middle = low + (high - low + 1) / 2
                if positive(middle) { low = middle } else { high = middle - 1 }
            }
            upper = low
        }
        func step(period: Double, delta: Int) -> Double? {
            let native = period / (linear ? 1 : 4)
            // Exact zero and existing outside-domain effects retain their native
            // conversion. Only newly composed positive-domain output is saturated.
            let composed = delta != 0 && native >= 1 && native <= Double(upper)
                ? min(Double(upper), max(0, native + Double(delta))) : native
            return PlaybackSongSyntheticAdapter.referencePlaybackStep(nativePeriod: composed,
                linear: linear, baseSampleRate: baseSampleRate, outputSampleRate: outputSampleRate)
        }
    }
}
