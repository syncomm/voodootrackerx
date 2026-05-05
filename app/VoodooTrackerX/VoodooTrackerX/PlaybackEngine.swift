import Foundation
import os

@MainActor
final class PlaybackEngine: PlaybackTransport {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Playback")
    private let audioEngine = PlaybackAudioEngine()

    private(set) var state: PlaybackState = .stopped
    private(set) var song: PlaybackSong?
    private(set) var currentPosition: PlaybackPosition?
    private(set) var timing = PlaybackTiming.xmDefault
    private var tickState = PlaybackTickState()
    private var timer: Timer?

    var positionDidChange: ((PlaybackPosition) -> Void)?
    var playbackDidStop: (() -> Void)?

    func load(song: PlaybackSong?) {
        stop(notify: false)
        self.song = song
        currentPosition = song?.startPosition
    }

    func configureTiming(_ timing: PlaybackTiming) {
        self.timing = timing
        if state.isPlaying {
            restartTimer()
        }
    }

    func play(from context: PlaybackStartContext?) {
        guard let song else {
            stop()
            return
        }
        currentPosition = playbackStartPosition(from: context, in: song) ?? song.startPosition
        tickState.reset()
        if let currentPosition {
            positionDidChange?(currentPosition)
            triggerAudio(at: currentPosition)
        }
        restartTimer()
        apply(action: .play, nextState: PlaybackState(mode: .playing, context: context))
    }

    func stop() {
        stop(notify: true)
    }

    private func stop(notify: Bool) {
        timer?.invalidate()
        timer = nil
        tickState.reset()
        audioEngine.stopAll()
        currentPosition = song?.startPosition
        apply(action: .stop, nextState: .stopped)
        if notify {
            playbackDidStop?()
        }
    }

    func pause() {
        guard state.mode == .playing else {
            return
        }
        timer?.invalidate()
        timer = nil
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

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: timing.tickDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOneTick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceOneTick() {
        guard state.isPlaying,
              let song,
              let position = currentPosition else {
            return
        }
        guard tickState.advance(timing: timing) else {
            return
        }
        switch song.position(after: position) {
        case let .advanced(nextPosition):
            currentPosition = nextPosition
            positionDidChange?(nextPosition)
            triggerAudio(at: nextPosition)
        case let .ended(restartPosition):
            if let restartPosition {
                currentPosition = restartPosition
                positionDidChange?(restartPosition)
            }
            stop()
        }
    }

    private func triggerAudio(at position: PlaybackPosition) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        for (channelIndex, cell) in row.cells.enumerated() {
            guard cell.note > 0,
                  cell.note <= 96,
                  let sample = song.sample(forInstrument: Int(cell.instrument)) else {
                continue
            }
            audioEngine.trigger(AudioVoiceRequest(sample: sample, note: cell.note, channel: channelIndex))
        }
    }

    private func playbackStartPosition(from context: PlaybackStartContext?, in song: PlaybackSong) -> PlaybackPosition? {
        guard let context else {
            return song.startPosition
        }
        if let contextPosition = song.position(orderIndex: context.songPosition, rowIndex: context.row),
           contextPosition.patternIndex == context.patternIndex {
            return contextPosition
        }
        for order in song.orders where order.patternIndex == context.patternIndex {
            return song.position(orderIndex: order.orderIndex, rowIndex: context.row)
        }
        return song.startPosition
    }
}
