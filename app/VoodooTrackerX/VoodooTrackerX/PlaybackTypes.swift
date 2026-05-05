import Foundation

enum PlaybackMode: Equatable {
    case stopped
    case playing
    case paused
}

struct PlaybackStartContext: Equatable {
    var moduleTitle: String?
    var songPosition: Int
    var patternIndex: Int
    var row: Int

    init(moduleTitle: String?, songPosition: Int, patternIndex: Int, row: Int) {
        self.moduleTitle = moduleTitle
        self.songPosition = max(0, songPosition)
        self.patternIndex = max(0, patternIndex)
        self.row = max(0, row)
    }
}

struct PlaybackState: Equatable {
    var mode: PlaybackMode
    var context: PlaybackStartContext?

    static let stopped = PlaybackState(mode: .stopped, context: nil)

    var isPlaying: Bool {
        mode == .playing
    }
}

enum PlaybackTransportAction: Equatable {
    case play
    case stop
    case pause
    case togglePlayPause
}
