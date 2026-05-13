import Foundation

/// Thin Swift wrapper around the C-backed mixer core.
///
/// This wrapper exists for deterministic offline tests and future mixer migration work. It does not replace
/// `SoftwareMixer` and is not connected to live `AVAudioPlayerNode` playback.
/// Synthetic samples added through this wrapper are copied into C-owned storage so Swift array lifetimes do
/// not leak across the C render boundary.
final class CSoftwareMixer {
    private var state: VTXCMixerState
    private(set) var config: MixerRenderConfig

    init(config: MixerRenderConfig = MixerRenderConfig()) {
        self.config = config
        state = VTXCMixerState()
        Self.requireOK(vtx_c_mixer_init(&state, Self.cConfig(from: config)))
        self.config = Self.swiftConfig(from: state.config)
    }

    deinit {
        _ = vtx_c_mixer_clear_voices(&state)
    }

    /// Applies a complete render configuration and resets transient C mixer state.
    func configure(_ config: MixerRenderConfig) {
        Self.requireOK(vtx_c_mixer_configure(&state, Self.cConfig(from: config)))
        self.config = Self.swiftConfig(from: state.config)
        reset()
    }

    /// Applies a new render configuration using safe deterministic defaults for invalid values.
    func configure(sampleRate: Double, channelCount: Int) {
        configure(MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount))
    }

    /// Adds one synthetic sample voice and copies its PCM data into C-owned storage.
    ///
    /// The C-backed path supports the same synthetic no-loop, forward-loop, and ping-pong-loop modes used by
    /// the Swift reference mixer tests. It intentionally ignores interpolation, pitch conversion, sample
    /// offsets, envelopes, timing, effects, and XM instrument ownership in this PR.
    @discardableResult
    func addVoice(sample: MixerSampleBuffer, gain: Float = 1, pan: Float = 0, loop: MixerSampleLoop = .none) -> Int {
        precondition(sample.frameCount <= Int(UInt32.max), "C mixer sample is too large")
        let sanitizedLoop = loop.sanitized(sampleFrameCount: sample.frameCount)
        var voiceIndex = UInt32(0)
        let status = sample.monoPCM.withUnsafeBufferPointer { buffer in
            vtx_c_mixer_add_sample_voice(
                &state,
                buffer.baseAddress,
                UInt32(sample.frameCount),
                gain,
                pan,
                Self.cLoopMode(from: sanitizedLoop.mode),
                UInt32(sanitizedLoop.startFrame),
                UInt32(sanitizedLoop.endFrame),
                &voiceIndex
            )
        }
        Self.requireOK(status)
        return Int(voiceIndex)
    }

    /// Removes all loaded C-backed voices so subsequent renders produce silence.
    func clearVoices() {
        Self.requireOK(vtx_c_mixer_clear_voices(&state))
    }

    /// Returns an interleaved Float32 PCM block rendered by the C core.
    ///
    /// The C core currently renders deterministic silence plus synthetic one-shot, forward-loop, and
    /// ping-pong-loop sample voices. It does not implement envelopes, timing, effects, XM playback, or
    /// runtime audio backend switching.
    func render(frames: Int) -> MixerRenderBlock {
        let frameCount = max(0, frames)
        let sampleCount = frameCount * config.channelCount
        var interleavedPCM = Array(repeating: Float(0), count: sampleCount)
        guard frameCount > 0 else {
            return MixerRenderBlock(config: config, frameCount: 0, interleavedPCM: [])
        }

        let status = interleavedPCM.withUnsafeMutableBufferPointer { buffer in
            vtx_c_mixer_render(&state, buffer.baseAddress, UInt32(frameCount))
        }
        Self.requireOK(status)

        return MixerRenderBlock(
            config: config,
            frameCount: frameCount,
            interleavedPCM: interleavedPCM
        )
    }

    /// Resets the C mixer state so repeated renders from the same inputs are deterministic.
    func reset() {
        Self.requireOK(vtx_c_mixer_reset(&state))
    }

    private static func cConfig(from config: MixerRenderConfig) -> VTXCMixerConfig {
        let channelCount = config.channelCount <= Int(UInt32.max)
            ? UInt32(config.channelCount)
            : UInt32(MixerRenderConfig.defaultChannelCount)
        return VTXCMixerConfig(
            sample_rate: config.sampleRate,
            channel_count: channelCount
        )
    }

    private static func swiftConfig(from config: VTXCMixerConfig) -> MixerRenderConfig {
        MixerRenderConfig(
            sampleRate: config.sample_rate,
            channelCount: Int(config.channel_count),
            isInterleaved: true
        )
    }

    private static func cLoopMode(from mode: MixerSampleLoopMode) -> VTXCMixerLoopMode {
        switch mode {
        case .none:
            return VTX_C_MIXER_LOOP_NONE
        case .forward:
            return VTX_C_MIXER_LOOP_FORWARD
        case .pingPong:
            return VTX_C_MIXER_LOOP_PING_PONG
        }
    }

    private static func requireOK(_ status: VTXCMixerStatus) {
        precondition(status == VTX_C_MIXER_STATUS_OK, "C mixer returned invalid argument")
    }
}
