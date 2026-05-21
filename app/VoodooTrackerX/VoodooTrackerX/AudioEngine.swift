import Foundation

@MainActor
protocol PlaybackAudioOutput: AnyObject {
    var audioBufferSampleRate: Double { get }

    func trigger(_ request: AudioVoiceRequest)
    func update(channel: Int, controls: AudioChannelControls)
    func stop(channel: Int)
    func stopAll()
    func reset()
}
