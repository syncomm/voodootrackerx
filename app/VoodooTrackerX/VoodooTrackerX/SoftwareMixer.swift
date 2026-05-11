import Foundation

/// Deterministic software mixer configuration for offline rendering and a later runtime backend migration.
///
/// This skeleton intentionally describes output shape only. It does not replace the existing
/// `AVAudioPlayerNode` playback path and currently renders silence until sample/voice rendering is added.
struct MixerRenderConfig: Equatable {
    static let defaultSampleRate = 44_100.0
    static let defaultChannelCount = 2

    let sampleRate: Double
    let channelCount: Int
    let isInterleaved: Bool

    /// Creates a safe render configuration, falling back to deterministic defaults for invalid values.
    init(sampleRate: Double = defaultSampleRate, channelCount: Int = defaultChannelCount, isInterleaved: Bool = true) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : Self.defaultSampleRate
        self.channelCount = channelCount > 0 ? channelCount : Self.defaultChannelCount
        self.isInterleaved = isInterleaved
    }
}

/// A single interleaved mixer output frame.
///
/// Future mixer PRs can use this as a typed boundary for inspecting per-frame channel samples without
/// depending on CoreAudio or AppKit types.
struct MixerFrame: Equatable {
    let samples: [Float]

    /// Creates one silent frame for the requested channel count.
    init(channelCount: Int) {
        samples = Array(repeating: 0, count: max(0, channelCount))
    }
}

/// Explicit per-channel voice state placeholder for the deterministic mixer.
///
/// Voices are intentionally inactive in this skeleton. Later PRs will add sample position, loop, envelope,
/// panning, and effect state here while keeping the current runtime backend intact until the mixer is proven.
struct MixerVoice: Equatable {
    let channelIndex: Int
    var isActive: Bool

    init(channelIndex: Int, isActive: Bool = false) {
        self.channelIndex = max(0, channelIndex)
        self.isActive = isActive
    }
}

/// A deterministic Float32 PCM render block produced by `SoftwareMixer`.
///
/// Samples are interleaved according to `config.channelCount`. For this initial skeleton every sample is
/// silence; the type exists so future offline render and comparison work can share a stable data boundary.
struct MixerRenderBlock: Equatable {
    let config: MixerRenderConfig
    let frameCount: Int
    let interleavedPCM: [Float]

    var sampleCount: Int {
        interleavedPCM.count
    }
}

/// Pull-based software mixer skeleton behind the playback/audio boundary.
///
/// This type is independent of AppKit, `AVAudioPlayerNode`, and CoreAudio render-thread assumptions. It
/// currently renders deterministic interleaved Float32 silence only; live playback remains on
/// `PlaybackAudioEngine` until future offline rendering and reference comparison work proves the mixer.
final class SoftwareMixer {
    private(set) var config: MixerRenderConfig
    private(set) var voices: [MixerVoice]

    init(config: MixerRenderConfig = MixerRenderConfig()) {
        self.config = config
        voices = []
    }

    /// Applies a new render configuration using safe deterministic defaults for invalid values.
    func configure(sampleRate: Double, channelCount: Int) {
        config = MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount)
        reset()
    }

    /// Returns an interleaved Float32 PCM block containing exactly `frames` frames for positive requests.
    ///
    /// Non-positive frame requests are handled predictably by returning an empty block. This keeps callers
    /// safe while the mixer is still used for bounded offline experiments rather than runtime audio.
    func render(frames: Int) -> MixerRenderBlock {
        let frameCount = max(0, frames)
        let sampleCount = frameCount * config.channelCount
        return MixerRenderBlock(
            config: config,
            frameCount: frameCount,
            interleavedPCM: Array(repeating: 0, count: sampleCount)
        )
    }

    /// Clears transient mixer state so repeated renders from the same inputs are deterministic.
    func reset() {
        voices.removeAll()
    }
}
