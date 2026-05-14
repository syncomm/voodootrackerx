import Foundation
#if canImport(MixerCore)
import MixerCore
#endif

/// One synthetic frame-based envelope point for the C-backed offline mixer.
struct MixerEnvelopePoint: Equatable {
    let positionFrame: Int
    let value: Float

    init(positionFrame: Int, value: Float) {
        self.positionFrame = positionFrame
        self.value = value
    }
}

/// Synthetic offline envelope data copied into C-owned fixed voice storage.
///
/// Volume envelopes use values in `0.0...1.0`. Panning envelopes use the C mixer's
/// `-1.0...1.0` pan convention and act as a neutral-centered offset added to the
/// voice pan. Parsed volume envelopes are converted to this frame-based shape in
/// Swift before they reach the C-backed offline mixer.
struct MixerEnvelope: Equatable {
    let points: [MixerEnvelopePoint]
    let sustainFrame: Int?
    let loopStartFrame: Int?
    let loopEndFrame: Int?

    init(
        points: [MixerEnvelopePoint],
        sustainFrame: Int? = nil,
        loopStartFrame: Int? = nil,
        loopEndFrame: Int? = nil
    ) {
        self.points = points
        self.sustainFrame = sustainFrame.map { max(0, $0) }
        self.loopStartFrame = loopStartFrame.map { max(0, $0) }
        self.loopEndFrame = loopEndFrame.map { max(0, $0) }
    }
}

/// Thin Swift wrapper around the C-backed mixer core.
///
/// This wrapper exists for deterministic offline tests and future mixer migration work. It does not replace
/// `SoftwareMixer` and is not connected to live `AVAudioPlayerNode` playback.
/// Synthetic samples added through this wrapper are copied into C-owned storage so Swift array lifetimes do
/// not leak across the C render boundary. Synthetic envelope points are also copied into C-owned voice
/// storage when attached.
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
    /// the Swift reference mixer tests. Callers may provide an explicit source-sample playback step; fractional
    /// source positions are rendered with deterministic linear interpolation. This wrapper intentionally does
    /// not implement FT2/OpenMPT resampler parity, sample offsets, timing effects, or XM instrument ownership.
    @discardableResult
    func addVoice(
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        playbackStep: Double = 1,
        loop: MixerSampleLoop = .none,
        volumeEnvelope: MixerEnvelope? = nil,
        panEnvelope: MixerEnvelope? = nil,
        keyOffFrame: Int? = nil,
        fadeoutFrameDecrement: Float = 0
    ) -> Int {
        precondition(sample.frameCount <= Int(UInt32.max), "C mixer sample is too large")
        let sanitizedLoop = loop.sanitized(sampleFrameCount: sample.frameCount)
        var voiceIndex = UInt32(0)
        let status = sample.monoPCM.withUnsafeBufferPointer { buffer in
            vtx_c_mixer_add_sample_voice_with_step(
                &state,
                buffer.baseAddress,
                UInt32(sample.frameCount),
                playbackStep,
                gain,
                pan,
                Self.cLoopMode(from: sanitizedLoop.mode),
                UInt32(sanitizedLoop.startFrame),
                UInt32(sanitizedLoop.endFrame),
                &voiceIndex
            )
        }
        Self.requireOK(status)
        if let volumeEnvelope {
            setVolumeEnvelope(volumeEnvelope, forVoiceAt: Int(voiceIndex))
        }
        if let panEnvelope {
            setPanEnvelope(panEnvelope, forVoiceAt: Int(voiceIndex))
        }
        if let keyOffFrame {
            setKeyOffFrame(keyOffFrame, fadeoutFrameDecrement: fadeoutFrameDecrement, forVoiceAt: Int(voiceIndex))
        }
        return Int(voiceIndex)
    }

    /// Adds one synthetic sample voice scheduled at an absolute output frame in the C mixer timeline.
    ///
    /// This is frame-based offline scheduling only. It does not parse tracker rows, handle XM effects, own
    /// parsed instruments, or route runtime playback through the C mixer. Returns nil for invalid scheduled
    /// event definitions such as negative or already-past start frames.
    @discardableResult
    func addScheduledVoice(
        sample: MixerSampleBuffer,
        scheduledStartFrame: Int,
        gain: Float = 1,
        pan: Float = 0,
        playbackStep: Double = 1,
        loop: MixerSampleLoop = .none,
        volumeEnvelope: MixerEnvelope? = nil,
        panEnvelope: MixerEnvelope? = nil,
        keyOffFrame: Int? = nil,
        fadeoutFrameDecrement: Float = 0
    ) -> Int? {
        guard scheduledStartFrame >= 0 else {
            return nil
        }
        precondition(sample.frameCount <= Int(UInt32.max), "C mixer sample is too large")
        let sanitizedLoop = loop.sanitized(sampleFrameCount: sample.frameCount)
        var voiceIndex = UInt32(0)
        let status = sample.monoPCM.withUnsafeBufferPointer { buffer in
            vtx_c_mixer_add_scheduled_sample_voice_with_step(
                &state,
                buffer.baseAddress,
                UInt32(sample.frameCount),
                playbackStep,
                gain,
                pan,
                Self.cLoopMode(from: sanitizedLoop.mode),
                UInt32(sanitizedLoop.startFrame),
                UInt32(sanitizedLoop.endFrame),
                UInt64(scheduledStartFrame),
                &voiceIndex
            )
        }
        guard status == VTX_C_MIXER_STATUS_OK else {
            return nil
        }
        if let volumeEnvelope {
            setVolumeEnvelope(volumeEnvelope, forVoiceAt: Int(voiceIndex))
        }
        if let panEnvelope {
            setPanEnvelope(panEnvelope, forVoiceAt: Int(voiceIndex))
        }
        if let keyOffFrame {
            setKeyOffFrame(keyOffFrame, fadeoutFrameDecrement: fadeoutFrameDecrement, forVoiceAt: Int(voiceIndex))
        }
        return Int(voiceIndex)
    }

    /// Copies a synthetic volume envelope into an existing C-backed voice.
    func setVolumeEnvelope(_ envelope: MixerEnvelope?, forVoiceAt voiceIndex: Int) {
        precondition(voiceIndex >= 0 && voiceIndex <= Int(UInt32.max), "C mixer voice index is out of range")
        let status = Self.withCEnvelope(envelope) { cEnvelope in
            vtx_c_mixer_set_voice_volume_envelope(&state, UInt32(voiceIndex), cEnvelope)
        }
        Self.requireOK(status)
    }

    /// Copies a synthetic panning envelope into an existing C-backed voice.
    func setPanEnvelope(_ envelope: MixerEnvelope?, forVoiceAt voiceIndex: Int) {
        precondition(voiceIndex >= 0 && voiceIndex <= Int(UInt32.max), "C mixer voice index is out of range")
        let status = Self.withCEnvelope(envelope) { cEnvelope in
            vtx_c_mixer_set_voice_pan_envelope(&state, UInt32(voiceIndex), cEnvelope)
        }
        Self.requireOK(status)
    }

    /// Schedules an absolute-frame key-off/release for an existing C-backed voice.
    func setKeyOffFrame(_ keyOffFrame: Int, fadeoutFrameDecrement: Float = 0, forVoiceAt voiceIndex: Int) {
        precondition(voiceIndex >= 0 && voiceIndex <= Int(UInt32.max), "C mixer voice index is out of range")
        precondition(keyOffFrame >= 0, "C mixer key-off frame is out of range")
        let status = vtx_c_mixer_set_voice_key_off_frame(
            &state,
            UInt32(voiceIndex),
            UInt64(keyOffFrame),
            fadeoutFrameDecrement.isFinite ? fadeoutFrameDecrement : 0
        )
        Self.requireOK(status)
    }

    /// Removes all loaded C-backed voices so subsequent renders produce silence.
    func clearVoices() {
        Self.requireOK(vtx_c_mixer_clear_voices(&state))
    }

    /// Removes all loaded and scheduled C-backed voices.
    func clearScheduledVoices() {
        clearVoices()
    }

    /// Returns an interleaved Float32 PCM block rendered by the C core.
    ///
    /// The C core currently renders deterministic silence plus synthetic one-shot, forward-loop, and
    /// ping-pong-loop sample voices with explicit playback steps, simple linear interpolation, plus synthetic
    /// volume and pan envelopes. Volume envelopes can use first-pass sustain/loop frames and scheduled
    /// voice key-off/fadeout when the bounded offline adapter supplies them.
    /// Scheduled synthetic voices can start at absolute output frames in the offline mixer timeline.
    /// Swift-side synthetic row/tick helpers can map simple tracker coordinates to those absolute frames, but
    /// the C core does not implement broad XM effects, full XM playback, FT2/OpenMPT envelope parity,
    /// FT2/OpenMPT pitch parity, or runtime audio backend switching.
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

    private static func withCEnvelope(
        _ envelope: MixerEnvelope?,
        _ body: (UnsafePointer<VTXCMixerEnvelope>?) -> VTXCMixerStatus
    ) -> VTXCMixerStatus {
        guard let envelope else {
            return body(nil)
        }
        precondition(envelope.points.count <= Int(UInt32.max), "C mixer envelope has too many points")
        let cPoints = envelope.points.map { point in
            VTXCMixerEnvelopePoint(
                position_frame: UInt32(clamping: point.positionFrame),
                value: point.value
            )
        }
        return cPoints.withUnsafeBufferPointer { buffer in
            var cEnvelope = VTXCMixerEnvelope(
                points: buffer.baseAddress,
                point_count: UInt32(cPoints.count),
                sustain_enabled: envelope.sustainFrame == nil ? 0 : 1,
                sustain_frame: UInt32(clamping: envelope.sustainFrame ?? 0),
                loop_enabled: envelope.loopStartFrame == nil || envelope.loopEndFrame == nil ? 0 : 1,
                loop_start_frame: UInt32(clamping: envelope.loopStartFrame ?? 0),
                loop_end_frame: UInt32(clamping: envelope.loopEndFrame ?? 0)
            )
            return withUnsafePointer(to: &cEnvelope) { cEnvelopePointer in
                body(cEnvelopePointer)
            }
        }
    }

    private static func requireOK(_ status: VTXCMixerStatus) {
        precondition(status == VTX_C_MIXER_STATUS_OK, "C mixer returned invalid argument")
    }
}
