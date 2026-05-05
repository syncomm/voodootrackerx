import Foundation

@MainActor
protocol PlaybackTransport: AnyObject {
    var state: PlaybackState { get }

    func play(from context: PlaybackStartContext?)
    func stop()
    func pause()
    func togglePlayPause(from context: PlaybackStartContext?)
}
