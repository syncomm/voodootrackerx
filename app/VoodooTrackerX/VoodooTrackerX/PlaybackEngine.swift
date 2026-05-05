import Foundation
import os

@MainActor
final class PlaybackEngine: PlaybackTransport {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Playback")

    private(set) var state: PlaybackState = .stopped

    func play(from context: PlaybackStartContext?) {
        apply(action: .play, nextState: PlaybackState(mode: .playing, context: context))
    }

    func stop() {
        apply(action: .stop, nextState: .stopped)
    }

    func pause() {
        guard state.mode == .playing else {
            return
        }
        apply(action: .pause, nextState: PlaybackState(mode: .paused, context: state.context))
    }

    func togglePlayPause(from context: PlaybackStartContext?) {
        switch state.mode {
        case .playing:
            pause()
        case .paused, .stopped:
            apply(action: .togglePlayPause, nextState: PlaybackState(mode: .playing, context: context ?? state.context))
        }
    }

    private func apply(action: PlaybackTransportAction, nextState: PlaybackState) {
        state = nextState
        logger.debug("Playback transport action: \(String(describing: action), privacy: .public)")
    }
}
