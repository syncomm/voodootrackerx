import AVFoundation
import Foundation
import os

@MainActor
protocol PlaybackAudioOutput: AnyObject {
    var audioBufferSampleRate: Double { get }

    func trigger(_ request: AudioVoiceRequest)
    func update(channel: Int, controls: AudioChannelControls)
    func stop(channel: Int)
    func stopAll()
    func reset()
}

enum RuntimeAudioBackend: Equatable {
    case avAudio
    case cMixer

    var diagnosticName: String {
        switch self {
        case .avAudio:
            return "av_audio"
        case .cMixer:
            return "c_mixer"
        }
    }
}

struct RuntimeAudioBackendSelection: Equatable {
    static let environmentKey = "VTX_AUDIO_BACKEND"
    static let cMixerEnvironmentValue = "c_mixer"

    let backend: RuntimeAudioBackend
    let requestedValue: String?
    let fallbackReason: String?

    var experimentalCMixerEnabled: Bool {
        backend == .cMixer
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeAudioBackendSelection {
        let requestedValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedValue,
              !requestedValue.isEmpty else {
            return RuntimeAudioBackendSelection(backend: .avAudio, requestedValue: nil, fallbackReason: nil)
        }
        guard requestedValue == cMixerEnvironmentValue else {
            return RuntimeAudioBackendSelection(
                backend: .avAudio,
                requestedValue: requestedValue,
                fallbackReason: "unknown_backend"
            )
        }
        return RuntimeAudioBackendSelection(backend: .cMixer, requestedValue: requestedValue, fallbackReason: nil)
    }
}

@MainActor
enum PlaybackAudioOutputFactory {
    private static let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "AudioBackend")

    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> PlaybackAudioOutput {
        let selection = RuntimeAudioBackendSelection.resolve(environment: environment)
        if let requestedValue = selection.requestedValue,
           let fallbackReason = selection.fallbackReason {
            logger.warning(
                "Unknown VTX_AUDIO_BACKEND value '\(requestedValue, privacy: .public)'; falling back to av_audio reason=\(fallbackReason, privacy: .public)"
            )
        }
        logger.info(
            "Selected audio backend=\(selection.backend.diagnosticName, privacy: .public) experimental_c_mixer_enabled=\(selection.experimentalCMixerEnabled, privacy: .public) sample_rate=\(MixerRenderConfig.defaultSampleRate, privacy: .public) channel_count=\(MixerRenderConfig.defaultChannelCount, privacy: .public)"
        )
        switch selection.backend {
        case .avAudio:
            return PlaybackAudioEngine()
        case .cMixer:
            return RuntimeCMixerAudioEngine()
        }
    }
}

final class RuntimeCMixerRenderCore: @unchecked Sendable {
    private let lock = NSLock()
    private let mixer: CSoftwareMixer
    private let maximumRenderFrames: Int
    private var scratchInterleavedPCM: [Float]
    private var loadedVoiceCount = 0

    let config: MixerRenderConfig

    init(config: MixerRenderConfig = MixerRenderConfig(), maximumRenderFrames: Int = 16_384) {
        self.config = config
        self.maximumRenderFrames = max(1, maximumRenderFrames)
        mixer = CSoftwareMixer(config: config)
        scratchInterleavedPCM = Array(repeating: 0, count: self.maximumRenderFrames * mixer.config.channelCount)
    }

    @discardableResult
    func trigger(_ request: AudioVoiceRequest) -> Bool {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              request.sampleStartOffset < request.sample.pcm.count else {
            return false
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        if loadedVoiceCount >= CSoftwareMixer.maximumVoiceCount {
            resetLocked()
        }

        _ = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: request.sample.pcm),
            gain: PlaybackVolumeCalculator.clamped(request.sample.volume * request.volumeScale),
            pan: request.panning,
            playbackStep: PlaybackPitchCalculator.calculation(
                note: request.note,
                sample: request.sample,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                outputSampleRate: mixer.config.sampleRate
            ).playbackRate,
            loop: mixerLoop(for: request.sample),
            initialSourceFrame: request.sampleStartOffset
        )
        loadedVoiceCount += 1
        return true
    }

    func update(channel _: Int, controls _: AudioChannelControls) {
        // The first runtime C mixer smoke path applies controls at note trigger time.
        // Continuous tick-level gain/pan/pitch automation needs a frame-position bridge and is intentionally
        // deferred so this backend remains an opt-in skeleton.
    }

    func stop(channel _: Int) {
        // The current C wrapper has no runtime voice-stealing/removal primitive. For the experimental skeleton,
        // a channel stop silences the whole C path rather than risking a stale voice in the source-node callback.
        stopAll()
    }

    func stopAll() {
        lock.lock()
        defer {
            lock.unlock()
        }
        resetLocked()
    }

    @discardableResult
    func render(into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>, frameCount: Int) -> Bool {
        let safeFrameCount = max(0, frameCount)
        guard safeFrameCount > 0 else {
            return true
        }
        guard safeFrameCount <= maximumRenderFrames,
              outputInterleavedPCM.count >= safeFrameCount * mixer.config.channelCount else {
            clear(outputInterleavedPCM)
            return false
        }
        guard lock.try() else {
            clear(outputInterleavedPCM)
            return false
        }
        defer {
            lock.unlock()
        }
        _ = mixer.render(into: outputInterleavedPCM, frames: safeFrameCount)
        return true
    }

    func render(frameCount: AVAudioFrameCount, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let safeFrameCount = Int(frameCount)

        // Audio callback safety rules: no AppKit, no parsing, no file I/O, no diagnostics logging, and no
        // allocation-heavy work. Voice/sample preparation happens on the main side before this callback; this
        // callback only renders the preloaded C mixer into preallocated scratch storage and copies it out.
        clear(ioData: ioData, frameCount: safeFrameCount)
        guard safeFrameCount > 0,
              safeFrameCount <= maximumRenderFrames else {
            return noErr
        }

        let sampleCount = safeFrameCount * mixer.config.channelCount
        let rendered = scratchInterleavedPCM.withUnsafeMutableBufferPointer { scratch in
            render(
                into: UnsafeMutableBufferPointer(start: scratch.baseAddress, count: sampleCount),
                frameCount: safeFrameCount
            )
        }
        if rendered {
            copyScratchToAudioBuffers(ioData: ioData, frameCount: safeFrameCount)
        }
        return noErr
    }

    private func resetLocked() {
        mixer.clearVoices()
        mixer.reset()
        loadedVoiceCount = 0
    }

    private func mixerLoop(for sample: PlaybackSample) -> MixerSampleLoop {
        let loop = sample.loopRegion
        guard loop.isEnabled else {
            return .none
        }
        return MixerSampleLoop(
            mode: loop.isPingPongLoop ? .pingPong : .forward,
            startFrame: loop.startFrame,
            endFrame: loop.endFrame
        )
    }

    private func clear(_ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>) {
        for index in outputInterleavedPCM.indices {
            outputInterleavedPCM[index] = 0
        }
    }

    private func clear(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for buffer in buffers {
            guard let data = buffer.mData else {
                continue
            }
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let requestedSampleCount = max(0, frameCount) * max(1, Int(buffer.mNumberChannels))
            let sampleCount = min(availableSampleCount, requestedSampleCount)
            let output = data.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = 0
            }
        }
    }

    private func copyScratchToAudioBuffers(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        let channelCount = mixer.config.channelCount
        if buffers.count == 1,
           let data = buffers[0].mData,
           Int(buffers[0].mNumberChannels) == channelCount {
            let sampleCount = min(
                Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size,
                frameCount * channelCount
            )
            let output = data.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = scratchInterleavedPCM[sampleIndex]
            }
            return
        }

        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else {
                continue
            }
            let bufferChannelCount = max(1, Int(buffer.mNumberChannels))
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for bufferChannel in 0..<bufferChannelCount {
                    let outputIndex = frame * bufferChannelCount + bufferChannel
                    guard outputIndex < availableSampleCount else {
                        return
                    }
                    let sourceChannel = buffers.count == channelCount ? bufferIndex : bufferChannel
                    output[outputIndex] = sourceChannel < channelCount
                        ? scratchInterleavedPCM[(frame * channelCount) + sourceChannel]
                        : 0
                }
            }
        }
    }
}

private func makeRuntimeCMixerSourceNode(
    format: AVAudioFormat,
    renderCore: RuntimeCMixerRenderCore
) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, ioData in
        renderCore.render(frameCount: frameCount, ioData: ioData)
    }
}

@MainActor
final class RuntimeCMixerAudioEngine: PlaybackAudioOutput {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sourceNode: AVAudioSourceNode
    private let renderCore: RuntimeCMixerRenderCore
    private let fallbackAudioEngine = PlaybackAudioEngine()
    private var isPrepared = false
    private var isFallbackActive = false

    init(sampleRate: Double = MixerRenderConfig.defaultSampleRate, channelCount: Int = MixerRenderConfig.defaultChannelCount) {
        let config = MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount)
        renderCore = RuntimeCMixerRenderCore(config: config)
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: renderCore.config.sampleRate,
            channels: AVAudioChannelCount(renderCore.config.channelCount),
            interleaved: false
        )!
        sourceNode = makeRuntimeCMixerSourceNode(format: format, renderCore: renderCore)
        logger.info(
            "Initialized experimental C mixer runtime backend sample_rate=\(self.renderCore.config.sampleRate, privacy: .public) channel_count=\(self.renderCore.config.channelCount, privacy: .public)"
        )
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    func trigger(_ request: AudioVoiceRequest) {
        if isFallbackActive {
            fallbackAudioEngine.trigger(request)
            return
        }
        prepareIfNeeded()
        guard renderCore.trigger(request) else {
            logger.debug("Experimental C mixer runtime ignored an unplayable trigger")
            return
        }
        if !startEngineIfNeeded() {
            isFallbackActive = true
            fallbackAudioEngine.trigger(request)
        }
    }

    func update(channel: Int, controls: AudioChannelControls) {
        if isFallbackActive {
            fallbackAudioEngine.update(channel: channel, controls: controls)
        } else {
            renderCore.update(channel: channel, controls: controls)
        }
    }

    func stop(channel: Int) {
        renderCore.stop(channel: channel)
        if isFallbackActive {
            fallbackAudioEngine.stop(channel: channel)
        }
    }

    func stopAll() {
        renderCore.stopAll()
        engine.pause()
        if isFallbackActive {
            fallbackAudioEngine.stopAll()
        }
    }

    func reset() {
        stopAll()
        engine.stop()
        fallbackAudioEngine.reset()
        isFallbackActive = false
        if isPrepared {
            engine.detach(sourceNode)
        }
        engine.reset()
        isPrepared = false
    }

    private func prepareIfNeeded() {
        guard !isPrepared else {
            return
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isPrepared = true
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else {
            return true
        }
        do {
            try engine.start()
            logger.info(
                "Experimental C mixer runtime start succeeded=true sample_rate=\(self.format.sampleRate, privacy: .public) channel_count=\(self.format.channelCount, privacy: .public)"
            )
            return true
        } catch {
            logger.error(
                "Experimental C mixer runtime start succeeded=false falling_back=true error=\(error.localizedDescription, privacy: .public)"
            )
            renderCore.stopAll()
            return false
        }
    }
}

@MainActor
final class PlaybackAudioEngine: PlaybackAudioOutput {
    private final class ChannelVoice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
    }

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voicesByChannel = [Int: ChannelVoice]()
    private var isPrepared = false

    init(sampleRate: Double = 44_100) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    func trigger(_ request: AudioVoiceRequest) {
        guard let plan = AudioSamplePlaybackPlanner.plan(for: request.sample, sampleStartOffset: request.sampleStartOffset) else {
            return
        }
        let introBuffer = plan.introRange.flatMap { makeBuffer(for: request, sampleRange: $0) }
        let loopBuffer = plan.loopRange.flatMap { loopRange in
            plan.usesPingPongLoop
                ? makePingPongLoopBuffer(for: request, sampleRange: loopRange)
                : makeBuffer(for: request, sampleRange: loopRange)
        }
        guard introBuffer != nil || loopBuffer != nil else {
            return
        }
        let voice = voice(forChannel: request.channel)
        prepareIfNeeded()
        guard startEngineIfNeeded() else {
            return
        }

        apply(
            AudioChannelControls(
                volumeScale: request.volumeScale,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                panning: request.panning
            ),
            to: voice
        )
        voice.player.stop()
        if let introBuffer {
            voice.player.scheduleBuffer(introBuffer, at: nil, options: [], completionHandler: nil)
        }
        if let loopBuffer {
            voice.player.scheduleBuffer(loopBuffer, at: nil, options: .loops, completionHandler: nil)
        }
        voice.player.play()
    }

    func update(channel: Int, controls: AudioChannelControls) {
        guard let voice = voicesByChannel[channel] else {
            return
        }
        apply(controls, to: voice)
    }

    func stop(channel: Int) {
        voicesByChannel[channel]?.player.stop()
    }

    func stopAll() {
        for voice in voicesByChannel.values {
            voice.player.stop()
        }
        engine.pause()
    }

    func reset() {
        stopAll()
        for voice in voicesByChannel.values {
            engine.detach(voice.player)
            engine.detach(voice.varispeed)
        }
        voicesByChannel.removeAll()
        engine.reset()
        isPrepared = false
    }

    private func prepareIfNeeded() {
        guard !isPrepared else {
            return
        }
        engine.prepare()
        isPrepared = true
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else {
            return true
        }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Unable to start audio engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func voice(forChannel channel: Int) -> ChannelVoice {
        if let voice = voicesByChannel[channel] {
            return voice
        }
        let voice = ChannelVoice()
        engine.attach(voice.player)
        engine.attach(voice.varispeed)
        engine.connect(voice.player, to: voice.varispeed, format: format)
        engine.connect(voice.varispeed, to: engine.mainMixerNode, format: format)
        voicesByChannel[channel] = voice
        return voice
    }

    private func apply(_ controls: AudioChannelControls, to voice: ChannelVoice) {
        voice.player.volume = min(1, max(0, controls.volumeScale))
        voice.player.pan = min(1, max(-1, controls.panning))
        let rate = Float(pow(2.0, controls.pitchOffsetSemitones / 12.0))
        voice.varispeed.rate = min(4, max(0.25, rate))
    }

    private func makeBuffer(for request: AudioVoiceRequest, sampleRange: Range<Int>) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              sampleRange.lowerBound >= 0,
              sampleRange.upperBound <= request.sample.pcm.count,
              !sampleRange.isEmpty else {
            return nil
        }
        return makeBuffer(for: request, sourceFrameCount: sampleRange.count) { sourceFrame in
            let sampleIndex = min(sampleRange.upperBound - 1, sampleRange.lowerBound + sourceFrame)
            return request.sample.pcm[sampleIndex]
        }
    }

    private func makePingPongLoopBuffer(for request: AudioVoiceRequest, sampleRange: Range<Int>) -> AVAudioPCMBuffer? {
        let frameIndices = AudioSampleLoopFrameBuilder.pingPongFrameIndices(
            for: sampleRange,
            sampleFrameCount: request.sample.pcm.count
        )
        guard !frameIndices.isEmpty else {
            return nil
        }
        return makeBuffer(for: request, sourceFrameCount: frameIndices.count) { sourceFrame in
            request.sample.pcm[frameIndices[sourceFrame]]
        }
    }

    private func makeBuffer(
        for request: AudioVoiceRequest,
        sourceFrameCount: Int,
        sampleAt: (Int) -> Float
    ) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              sourceFrameCount > 0 else {
            return nil
        }
        let pitchRatio = PlaybackPitchCalculator.notePitchRatio(note: request.note, sample: request.sample)
        let increment = max(0.001, (request.sample.baseSampleRate / format.sampleRate) * pitchRatio)
        let frameCount = max(1, Int(Double(sourceFrameCount) / increment))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let output = buffer.floatChannelData?[0] else {
            return nil
        }

        var samplePosition = 0.0
        let gain = min(0.8, max(0, request.sample.volume))
        for frame in 0..<frameCount {
            let sourceFrame = min(sourceFrameCount - 1, Int(samplePosition))
            output[frame] = sampleAt(sourceFrame) * gain
            samplePosition += increment
        }
        return buffer
    }
}
