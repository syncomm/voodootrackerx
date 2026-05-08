import Foundation

struct AudioChannelControls: Equatable {
    var volumeScale: Float = 1
    var pitchOffsetSemitones: Double = 0
}

struct AudioVoiceRequest: Equatable {
    let sample: PlaybackSample
    let note: UInt8
    let channel: Int
    var volumeScale: Float = 1
    var pitchOffsetSemitones: Double = 0
    var sampleStartOffset: Int = 0
}
