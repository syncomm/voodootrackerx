import Foundation

/// Deterministic software mixer configuration for offline rendering and a later runtime backend migration.
///
/// This offline path does not replace the existing `AVAudioPlayerNode` playback path.
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

/// A mono Float32 PCM source owned by the deterministic software mixer.
struct MixerSampleBuffer: Equatable {
    let monoPCM: [Float]

    var frameCount: Int {
        monoPCM.count
    }

    init(monoPCM: [Float]) {
        self.monoPCM = monoPCM.map { $0.isFinite ? $0 : 0 }
    }
}

/// Synthetic sample loop modes owned by the deterministic offline mixer.
enum MixerSampleLoopMode: Equatable {
    case none
    case forward
    case pingPong
}

/// Synthetic sample loop metadata for `MixerVoice`.
///
/// `endFrame` is exclusive. For example, `startFrame: 1, endFrame: 4` loops source frames
/// 1, 2, and 3. Invalid loops are sanitized to `.none` so offline renders fall back to
/// one-shot playback instead of trapping or reading outside the synthetic sample buffer.
struct MixerSampleLoop: Equatable {
    static let none = MixerSampleLoop(mode: .none, startFrame: 0, endFrame: 0)

    let mode: MixerSampleLoopMode
    let startFrame: Int
    let endFrame: Int

    var lengthFrames: Int {
        max(0, endFrame - startFrame)
    }

    init(mode: MixerSampleLoopMode = .none, startFrame: Int = 0, endFrame: Int = 0) {
        self.mode = mode
        self.startFrame = startFrame
        self.endFrame = endFrame
    }

    func sanitized(sampleFrameCount: Int) -> MixerSampleLoop {
        guard mode != .none else {
            return .none
        }
        guard sampleFrameCount > 0,
              startFrame >= 0,
              endFrame <= sampleFrameCount,
              endFrame > startFrame else {
            return .none
        }
        if mode == .pingPong && lengthFrames < 2 {
            return .none
        }
        return self
    }
}

/// Explicit synthetic sample voice state for the deterministic mixer.
///
/// This path supports bounded synthetic mono samples only: no envelopes, pitch conversion,
/// pattern scheduling, or XM instrument ownership.
struct MixerVoice: Equatable {
    let channelIndex: Int
    let sample: MixerSampleBuffer
    let gain: Float
    let pan: Float
    let step: Double
    let loop: MixerSampleLoop
    var isActive: Bool
    private(set) var samplePosition: Double
    private(set) var pingPongDirection: Int

    init(
        channelIndex: Int,
        sample: MixerSampleBuffer = MixerSampleBuffer(monoPCM: []),
        gain: Float = 1,
        pan: Float = 0,
        step: Double = 1,
        loop: MixerSampleLoop = .none,
        isActive: Bool? = nil
    ) {
        self.channelIndex = max(0, channelIndex)
        self.sample = sample
        self.gain = gain.isFinite ? gain : 0
        self.pan = min(1, max(-1, pan.isFinite ? pan : 0))
        self.step = step.isFinite && step > 0 ? step : 1
        self.loop = loop.sanitized(sampleFrameCount: sample.frameCount)
        samplePosition = 0
        pingPongDirection = 1
        self.isActive = isActive ?? !sample.monoPCM.isEmpty
    }

    var leftPanGain: Float {
        pan <= 0 ? 1 : 1 - pan
    }

    var rightPanGain: Float {
        pan >= 0 ? 1 : 1 + pan
    }

    mutating func reset() {
        samplePosition = 0
        pingPongDirection = 1
        isActive = !sample.monoPCM.isEmpty
    }

    mutating func nextMonoSample() -> Float? {
        guard isActive else {
            return nil
        }
        let sourceIndex = Int(samplePosition)
        guard sample.monoPCM.indices.contains(sourceIndex) else {
            isActive = false
            return nil
        }

        let value = sample.monoPCM[sourceIndex] * gain
        advanceSamplePosition()
        return value
    }

    private mutating func advanceSamplePosition() {
        switch loop.mode {
        case .none:
            advanceOneShotPosition()
        case .forward:
            advanceForwardLoopPosition()
        case .pingPong:
            advancePingPongLoopPosition()
        }
    }

    private mutating func advanceOneShotPosition() {
        samplePosition += step
        if samplePosition >= Double(sample.frameCount) {
            isActive = false
        }
    }

    private mutating func advanceForwardLoopPosition() {
        samplePosition += step
        guard samplePosition >= Double(loop.endFrame) else {
            return
        }

        let loopLength = Double(loop.lengthFrames)
        guard loopLength > 0 else {
            isActive = false
            return
        }
        let overflow = samplePosition - Double(loop.endFrame)
        samplePosition = Double(loop.startFrame) + overflow.truncatingRemainder(dividingBy: loopLength)
    }

    private mutating func advancePingPongLoopPosition() {
        samplePosition += step * Double(pingPongDirection)

        let firstLoopFrame = Double(loop.startFrame)
        let lastLoopFrame = Double(loop.endFrame - 1)
        let span = lastLoopFrame - firstLoopFrame
        guard span > 0 else {
            samplePosition = firstLoopFrame
            pingPongDirection = 1
            return
        }

        let period = span * 2
        if pingPongDirection > 0 && samplePosition > lastLoopFrame {
            let overshoot = (samplePosition - lastLoopFrame).truncatingRemainder(dividingBy: period)
            samplePosition = lastLoopFrame + overshoot
        } else if pingPongDirection < 0 && samplePosition < firstLoopFrame {
            let overshoot = (firstLoopFrame - samplePosition).truncatingRemainder(dividingBy: period)
            samplePosition = firstLoopFrame - overshoot
        }

        if pingPongDirection > 0 && samplePosition > lastLoopFrame {
            let overshoot = samplePosition - lastLoopFrame
            samplePosition = lastLoopFrame - overshoot
            pingPongDirection = -1
        } else if pingPongDirection < 0 && samplePosition < firstLoopFrame {
            let overshoot = firstLoopFrame - samplePosition
            samplePosition = firstLoopFrame + overshoot
            pingPongDirection = 1
        }
    }
}

/// A deterministic Float32 PCM render block produced by `SoftwareMixer`.
///
/// Samples are interleaved according to `config.channelCount`.
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

/// Pull-based software mixer behind the playback/audio boundary.
///
/// This type is independent of AppKit, `AVAudioPlayerNode`, and CoreAudio render-thread assumptions. It
/// currently renders deterministic interleaved Float32 PCM for explicitly supplied synthetic sample voices;
/// live playback remains on `PlaybackAudioEngine` until future offline rendering and reference comparison work
/// proves the mixer.
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

    /// Adds one synthetic sample voice for offline rendering and returns its voice array index.
    @discardableResult
    func addVoice(
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        step: Double = 1,
        loop: MixerSampleLoop = .none,
        channelIndex: Int = 0
    ) -> Int {
        voices.append(MixerVoice(
            channelIndex: channelIndex,
            sample: sample,
            gain: gain,
            pan: pan,
            step: step,
            loop: loop
        ))
        return voices.count - 1
    }

    /// Removes all loaded voices so subsequent renders produce silence.
    func clearVoices() {
        voices.removeAll()
    }

    /// Returns an interleaved Float32 PCM block containing exactly `frames` frames for positive requests.
    ///
    /// Non-positive frame requests are handled predictably by returning an empty block. This keeps callers
    /// safe while the mixer is still used for bounded offline experiments rather than runtime audio.
    func render(frames: Int) -> MixerRenderBlock {
        let frameCount = max(0, frames)
        let sampleCount = frameCount * config.channelCount
        var interleavedPCM = Array(repeating: Float(0), count: sampleCount)
        guard frameCount > 0,
              config.channelCount > 0,
              !voices.isEmpty else {
            return MixerRenderBlock(
                config: config,
                frameCount: frameCount,
                interleavedPCM: interleavedPCM
            )
        }

        for frameIndex in 0..<frameCount {
            let frameOffset = frameIndex * config.channelCount
            for voiceIndex in voices.indices {
                guard let monoSample = voices[voiceIndex].nextMonoSample() else {
                    continue
                }
                mix(monoSample, from: voices[voiceIndex], into: &interleavedPCM, at: frameOffset)
            }
        }

        return MixerRenderBlock(
            config: config,
            frameCount: frameCount,
            interleavedPCM: interleavedPCM
        )
    }

    /// Rewinds loaded voices so repeated renders from the same inputs are deterministic.
    func reset() {
        for voiceIndex in voices.indices {
            voices[voiceIndex].reset()
        }
    }

    private func mix(_ monoSample: Float, from voice: MixerVoice, into interleavedPCM: inout [Float], at frameOffset: Int) {
        guard config.channelCount > 0 else {
            return
        }
        if config.channelCount == 1 {
            interleavedPCM[frameOffset] += monoSample
            return
        }

        interleavedPCM[frameOffset] += monoSample * voice.leftPanGain
        interleavedPCM[frameOffset + 1] += monoSample * voice.rightPanGain
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

    /// Adds one synthetic sample voice to the underlying offline mixer.
    @discardableResult
    func addVoice(
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        step: Double = 1,
        loop: MixerSampleLoop = .none,
        channelIndex: Int = 0
    ) -> Int {
        mixer.addVoice(
            sample: sample,
            gain: gain,
            pan: pan,
            step: step,
            loop: loop,
            channelIndex: channelIndex
        )
    }

    /// Removes all voices from the underlying offline mixer.
    func clearVoices() {
        mixer.clearVoices()
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

    /// Rewinds mixer state so the same request can be rendered deterministically again.
    func reset() {
        mixer.reset()
    }
}
