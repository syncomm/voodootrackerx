import Foundation

struct AudioVoiceRequest: Equatable {
    let sample: PlaybackSample
    let note: UInt8
    let channel: Int
}
