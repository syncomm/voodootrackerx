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

/// Bounded offline render request for deterministic software mixer validation.
///
/// Frame counts are sanitized to zero for invalid input and clamped to `maximumFrameCount` before
/// rendering. The default maximum is 60 seconds at 44.1 kHz so local comparison tooling cannot
/// accidentally request unbounded PCM.
struct OfflineRenderRequest: Equatable {
    static let defaultMaximumFrameCount = Int(MixerRenderConfig.defaultSampleRate) * 60

    let config: MixerRenderConfig
    let requestedFrameCount: Int
    let maximumFrameCount: Int

    var boundedFrameCount: Int {
        min(requestedFrameCount, maximumFrameCount)
    }

    var wasFrameCountBounded: Bool {
        requestedFrameCount > maximumFrameCount
    }

    init(
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.config = config
        requestedFrameCount = max(0, frames)
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    init(
        config: MixerRenderConfig = MixerRenderConfig(),
        durationSeconds: Double,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.init(
            config: config,
            frames: Self.frameCount(durationSeconds: durationSeconds, sampleRate: config.sampleRate),
            maximumFrameCount: maximumFrameCount
        )
    }

    private static func frameCount(durationSeconds: Double, sampleRate: Double) -> Int {
        guard durationSeconds.isFinite,
              durationSeconds > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        let frameCount = (durationSeconds * sampleRate).rounded(.down)
        guard frameCount.isFinite,
              frameCount > 0 else {
            return 0
        }
        guard frameCount < Double(Int.max) else {
            return Int.max
        }
        return Int(frameCount)
    }
}

/// Result metadata for a bounded offline software mixer render.
struct OfflineRenderResult: Equatable {
    let request: OfflineRenderRequest
    let block: MixerRenderBlock

    var requestedFrameCount: Int {
        request.requestedFrameCount
    }

    var renderedFrameCount: Int {
        block.frameCount
    }

    var maximumFrameCount: Int {
        request.maximumFrameCount
    }

    var wasFrameCountBounded: Bool {
        request.wasFrameCountBounded
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

    /// Applies a complete render configuration and resets transient mixer state.
    func configure(_ config: MixerRenderConfig) {
        self.config = config
        reset()
    }

    /// Applies a new render configuration using safe deterministic defaults for invalid values.
    func configure(sampleRate: Double, channelCount: Int) {
        configure(MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount))
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

/// Offline harness for bounded deterministic renders from `SoftwareMixer`.
///
/// This renderer is independent of AppKit, `AVAudioPlayerNode`, and live playback. It exists for tests and
/// future CLI/export tooling; runtime playback remains on `PlaybackAudioEngine`.
final class SoftwareMixerOfflineRenderer {
    private let mixer: SoftwareMixer
    let maximumFrameCount: Int

    var config: MixerRenderConfig {
        mixer.config
    }

    init(
        mixer: SoftwareMixer,
        maximumFrameCount: Int = OfflineRenderRequest.defaultMaximumFrameCount
    ) {
        self.mixer = mixer
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    convenience init(
        config: MixerRenderConfig = MixerRenderConfig(),
        maximumFrameCount: Int = OfflineRenderRequest.defaultMaximumFrameCount
    ) {
        self.init(
            mixer: SoftwareMixer(config: config),
            maximumFrameCount: maximumFrameCount
        )
    }

    /// Renders a bounded frame count using the renderer's current mixer configuration.
    func render(frames: Int) -> OfflineRenderResult {
        render(OfflineRenderRequest(
            config: mixer.config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        ))
    }

    /// Converts duration to frames with deterministic floor rounding, then renders a bounded block.
    func render(durationSeconds: Double) -> OfflineRenderResult {
        render(OfflineRenderRequest(
            config: mixer.config,
            durationSeconds: durationSeconds,
            maximumFrameCount: maximumFrameCount
        ))
    }

    /// Renders a request after applying its configuration, clamping oversized requests to the configured maximum.
    func render(_ request: OfflineRenderRequest) -> OfflineRenderResult {
        let effectiveRequest = OfflineRenderRequest(
            config: request.config,
            frames: request.requestedFrameCount,
            maximumFrameCount: min(request.maximumFrameCount, maximumFrameCount)
        )
        if mixer.config != request.config {
            mixer.configure(request.config)
        }
        return OfflineRenderResult(
            request: effectiveRequest,
            block: mixer.render(frames: effectiveRequest.boundedFrameCount)
        )
    }

    /// Clears mixer state so the same request can be rendered deterministically again.
    func reset() {
        mixer.reset()
    }
}
