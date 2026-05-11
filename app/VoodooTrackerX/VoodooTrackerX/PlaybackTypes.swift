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

struct PlaybackDebugStartRequest: Equatable {
    var requestedOrderIndex: Int?
    var requestedPatternIndex: Int?
    var requestedRowIndex: Int
    var requestedTickInRow: Int?

    init(orderIndex: Int? = nil, patternIndex: Int? = nil, rowIndex: Int = 0, tickInRow: Int? = nil) {
        requestedOrderIndex = orderIndex.map { max(0, $0) }
        requestedPatternIndex = patternIndex.map { max(0, $0) }
        requestedRowIndex = max(0, rowIndex)
        requestedTickInRow = tickInRow.map { max(0, $0) }
    }
}

struct PlaybackDebugLaunchConfiguration: Equatable {
    static let startOrderEnvironmentKey = "VTX_DEBUG_START_ORDER"
    static let startPatternEnvironmentKey = "VTX_DEBUG_START_PATTERN"
    static let startRowEnvironmentKey = "VTX_DEBUG_START_ROW"
    static let startTickEnvironmentKey = "VTX_DEBUG_START_TICK"
    static let autoplayEnvironmentKey = "VTX_DEBUG_AUTOPLAY"
    static let stopAfterSecondsEnvironmentKey = "VTX_DEBUG_STOP_AFTER_SECONDS"

    var startRequest: PlaybackDebugStartRequest?
    var autoplay: Bool
    var stopAfterSeconds: TimeInterval?

    static func parse(environment: [String: String] = ProcessInfo.processInfo.environment) -> PlaybackDebugLaunchConfiguration {
        let requestedOrder = nonNegativeInt(environment[startOrderEnvironmentKey])
        let requestedPattern = nonNegativeInt(environment[startPatternEnvironmentKey])
        let requestedRow = nonNegativeInt(environment[startRowEnvironmentKey])
        let requestedTick = nonNegativeInt(environment[startTickEnvironmentKey])
        let request: PlaybackDebugStartRequest?
        if requestedOrder != nil || requestedPattern != nil || requestedRow != nil || requestedTick != nil {
            request = PlaybackDebugStartRequest(
                orderIndex: requestedOrder,
                patternIndex: requestedPattern,
                rowIndex: requestedRow ?? 0,
                tickInRow: requestedTick
            )
        } else {
            request = nil
        }

        return PlaybackDebugLaunchConfiguration(
            startRequest: request,
            autoplay: boolValue(environment[autoplayEnvironmentKey]),
            stopAfterSeconds: positiveTimeInterval(environment[stopAfterSecondsEnvironmentKey])
        )
    }

    private static func nonNegativeInt(_ rawValue: String?) -> Int? {
        guard let rawValue,
              let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return max(0, value)
    }

    private static func boolValue(_ rawValue: String?) -> Bool {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value)
    }

    private static func positiveTimeInterval(_ rawValue: String?) -> TimeInterval? {
        guard let rawValue,
              let value = TimeInterval(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0 else {
            return nil
        }
        return value
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
