import AVFoundation
import Foundation
import os

@MainActor
protocol PlaybackAudioOutput: AnyObject {
    func trigger(_ request: AudioVoiceRequest)
    func update(channel: Int, controls: AudioChannelControls)
    func stop(channel: Int)
    func stopAll()
    func reset()
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

    func trigger(_ request: AudioVoiceRequest) {
        guard let buffer = makeBuffer(for: request) else {
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
        voice.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
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

    private func makeBuffer(for request: AudioVoiceRequest) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96 else {
            return nil
        }
        let pitchRatio = PlaybackPitchCalculator.notePitchRatio(note: request.note, sample: request.sample)
        let increment = max(0.001, (request.sample.baseSampleRate / format.sampleRate) * pitchRatio)
        let startOffset = min(max(0, request.sampleStartOffset), request.sample.pcm.count)
        guard startOffset < request.sample.pcm.count else {
            return nil
        }
        let availableSampleCount = request.sample.pcm.count - startOffset
        let frameCount = max(1, Int(Double(availableSampleCount) / increment))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let output = buffer.floatChannelData?[0] else {
            return nil
        }

        var samplePosition = Double(startOffset)
        let gain = min(0.8, max(0, request.sample.volume))
        for frame in 0..<frameCount {
            let sampleIndex = min(request.sample.pcm.count - 1, Int(samplePosition))
            output[frame] = request.sample.pcm[sampleIndex] * gain
            samplePosition += increment
        }
        return buffer
    }
}
