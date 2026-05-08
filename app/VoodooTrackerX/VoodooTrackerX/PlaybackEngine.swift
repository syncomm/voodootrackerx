import Foundation
import os

@MainActor
final class PlaybackEngine: PlaybackTransport {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Playback")
    private let audioEngine: PlaybackAudioOutput

    private(set) var state: PlaybackState = .stopped
    private(set) var song: PlaybackSong?
    private(set) var currentPosition: PlaybackPosition?
    private(set) var timing = PlaybackTiming.xmDefault
    private var tickState = PlaybackTickState()
    private var timer: Timer?
    private var pendingPositionCommand: PlaybackPositionCommand?
    private var channelVolumes = [Int: Float]()

    var positionDidChange: ((PlaybackPosition) -> Void)?
    var playbackDidStop: (() -> Void)?

    init(audioEngine: PlaybackAudioOutput = PlaybackAudioEngine()) {
        self.audioEngine = audioEngine
    }

    func load(song: PlaybackSong?) {
        let wasPlaying = state.isPlaying
        stop(notify: false, resetAudio: true)
        self.song = song
        currentPosition = song?.startPosition
        pendingPositionCommand = nil
        channelVolumes.removeAll()
        logger.debug("Playback song loaded. hadActivePlayback=\(wasPlaying, privacy: .public) hasSong=\((song != nil), privacy: .public)")
    }

    func configureTiming(_ timing: PlaybackTiming) {
        self.timing = timing
        if state.isPlaying {
            restartTimer()
        }
    }

    func play(from context: PlaybackStartContext?) {
        guard !state.isPlaying else {
            logger.debug("Ignoring play request because playback is already active")
            return
        }
        guard let song else {
            stop()
            return
        }
        currentPosition = playbackStartPosition(from: context, in: song) ?? song.startPosition
        tickState.reset()
        pendingPositionCommand = nil
        channelVolumes.removeAll()
        if let currentPosition {
            enter(position: currentPosition)
        }
        restartTimer()
        apply(action: .play, nextState: PlaybackState(mode: .playing, context: context))
    }

    func stop() {
        stop(notify: true, resetAudio: false)
    }

    private func stop(notify: Bool, resetAudio: Bool) {
        let wasActive = state.mode != .stopped || timer != nil
        guard wasActive || resetAudio else {
            logger.debug("Ignoring stop request because playback is already stopped")
            return
        }
        timer?.invalidate()
        timer = nil
        tickState.reset()
        if resetAudio {
            audioEngine.reset()
        } else {
            audioEngine.stopAll()
        }
        currentPosition = song?.startPosition
        pendingPositionCommand = nil
        channelVolumes.removeAll()
        timing = .xmDefault
        apply(action: .stop, nextState: .stopped)
        if notify, wasActive {
            playbackDidStop?()
        }
    }

    func pause() {
        guard state.mode == .playing else {
            return
        }
        timer?.invalidate()
        timer = nil
        audioEngine.stopAll()
        apply(action: .pause, nextState: PlaybackState(mode: .paused, context: state.context))
    }

    func togglePlayPause(from context: PlaybackStartContext?) {
        switch state.mode {
        case .playing:
            pause()
        case .paused, .stopped:
            play(from: context ?? state.context)
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

    func advanceOneTick() {
        guard state.isPlaying,
              let song,
              let position = currentPosition else {
            return
        }
        guard tickState.advance(timing: timing) else {
            return
        }
        switch nextStep(after: position, in: song) {
        case let .advanced(nextPosition):
            currentPosition = nextPosition
            enter(position: nextPosition)
        case let .ended(restartPosition):
            if let restartPosition {
                currentPosition = restartPosition
                positionDidChange?(restartPosition)
            }
            logger.debug("Playback reached end of song; stopping cleanly")
            stop()
        }
    }

    private func enter(position: PlaybackPosition) {
        positionDidChange?(position)
        applyEffects(at: position)
        triggerAudio(at: position)
    }

    private func nextStep(after position: PlaybackPosition, in song: PlaybackSong) -> PlaybackStepResult {
        guard let pendingPositionCommand else {
            return song.position(after: position)
        }
        self.pendingPositionCommand = nil
        switch pendingPositionCommand {
        case let .positionJump(orderIndex):
            guard song.orders.indices.contains(orderIndex) else {
                logger.debug("Ignoring out-of-bounds position jump: \(orderIndex, privacy: .public)")
                return song.position(after: position)
            }
            return song.position(orderIndex: orderIndex, rowIndex: 0).map(PlaybackStepResult.advanced) ?? .ended(restartPosition: nil)
        case let .patternBreak(rowIndex):
            let nextOrderIndex = position.orderIndex + 1
            guard song.orders.indices.contains(nextOrderIndex) else {
                return .ended(restartPosition: nil)
            }
            return song.position(orderIndex: nextOrderIndex, rowIndex: rowIndex).map(PlaybackStepResult.advanced) ?? .ended(restartPosition: nil)
        }
    }

    private func applyEffects(at position: PlaybackPosition) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        for (channelIndex, cell) in row.cells.enumerated() {
            guard let command = PlaybackEffectHandler.command(effectType: cell.effectType, effectParam: cell.effectParam) else {
                logUnsupportedEffectIfNeeded(cell)
                continue
            }
            apply(command, channelIndex: channelIndex)
        }
    }

    private func apply(_ command: PlaybackEffectCommand, channelIndex: Int) {
        switch command {
        case let .setSpeed(speed):
            configureTiming(PlaybackTiming(speed: speed, bpm: timing.bpm))
        case let .setBPM(bpm):
            configureTiming(PlaybackTiming(speed: timing.speed, bpm: bpm))
        case let .positionJump(orderIndex):
            pendingPositionCommand = .positionJump(orderIndex: orderIndex)
        case let .patternBreak(rowIndex):
            pendingPositionCommand = .patternBreak(rowIndex: rowIndex)
        case let .setVolume(volume):
            channelVolumes[channelIndex] = volume
        }
    }

    private func logUnsupportedEffectIfNeeded(_ cell: PlaybackCell) {
        guard cell.effectType != 0 || cell.effectParam != 0 else {
            return
        }
        logger.debug("Deferred XM effect \(cell.effectType, privacy: .public) param \(cell.effectParam, privacy: .public)")
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
            audioEngine.trigger(AudioVoiceRequest(sample: sample, note: cell.note, channel: channelIndex, volumeScale: channelVolumes[channelIndex] ?? 1))
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

private enum PlaybackPositionCommand: Equatable {
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
}
