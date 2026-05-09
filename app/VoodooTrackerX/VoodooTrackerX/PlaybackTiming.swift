import Foundation

struct PlaybackTiming: Equatable {
    var speed: Int
    var bpm: Int

    static let xmDefault = PlaybackTiming(speed: 6, bpm: 125)

    var tickDuration: TimeInterval {
        2.5 / Double(max(1, bpm))
    }

    var rowDuration: TimeInterval {
        tickDuration * Double(ticksPerRow)
    }

    var ticksPerRow: Int {
        max(1, speed)
    }
}

struct PlaybackTickState: Equatable {
    var tickInRow: Int = 0

    mutating func advance(timing: PlaybackTiming) -> Bool {
        tickInRow += 1
        guard tickInRow >= timing.ticksPerRow else {
            return false
        }
        tickInRow = 0
        return true
    }

    mutating func reset() {
        tickInRow = 0
    }
}
