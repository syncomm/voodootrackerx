import AVFoundation
import Foundation
import os

@MainActor
protocol PlaybackAudioOutput: AnyObject {
    func trigger(_ request: AudioVoiceRequest)
    func stopAll()
    func reset()
}

@MainActor
final class PlaybackAudioEngine: PlaybackAudioOutput {
    private final class ChannelVoice {
        let player = AVAudioPlayerNode()
    }

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voicesByChannel = [Int: ChannelVoice]()
    private var isPrepared = false

    init(sampleRate: Double = 44_100) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    func trigger(_ request: AudioVoiceRequest) {
        guard let buffer = makeBuffer(for: request) else {
            return
        }
        let voice = voice(forChannel: request.channel)
        prepareIfNeeded()
        guard startEngineIfNeeded() else {
            return
        }

        voice.player.stop()
        voice.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.player.play()
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
        engine.connect(voice.player, to: engine.mainMixerNode, format: format)
        voicesByChannel[channel] = voice
        return voice
    }

    private func makeBuffer(for request: AudioVoiceRequest) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96 else {
            return nil
        }
        let noteOffset = Double(Int(request.note) + request.sample.relativeNote - 49)
        let finetuneOffset = Double(request.sample.finetune) / (128.0 * 12.0)
        let pitchRatio = pow(2.0, (noteOffset / 12.0) + finetuneOffset)
        let increment = max(0.001, (request.sample.baseSampleRate / format.sampleRate) * pitchRatio)
        let frameCount = max(1, Int(Double(request.sample.pcm.count) / increment))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let output = buffer.floatChannelData?[0] else {
            return nil
        }

        var samplePosition = 0.0
        let gain = min(0.8, request.sample.volume * max(0, request.volumeScale))
        for frame in 0..<frameCount {
            let sampleIndex = min(request.sample.pcm.count - 1, Int(samplePosition))
            output[frame] = request.sample.pcm[sampleIndex] * gain
            samplePosition += increment
        }
        return buffer
    }
}
