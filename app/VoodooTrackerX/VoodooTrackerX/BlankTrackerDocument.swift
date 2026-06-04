import Foundation

struct BlankTrackerDocument: Equatable {
    static let defaultTitle = "Untitled"
    static let defaultSongLength = 1
    static let defaultCurrentPosition = 0
    static let defaultRestartPosition = 0
    static let defaultPatternIndex = 0
    static let defaultRowCount = 64
    static let defaultChannelCount = 8
    static let defaultTempo = 125
    static let defaultSpeed = 6

    let title: String
    let songLength: Int
    let currentPosition: Int
    let restartPosition: Int
    let currentPatternIndex: Int
    let tempo: Int
    let speed: Int
    let pattern: XMPatternData

    static func makeDefault() -> BlankTrackerDocument {
        let rows = Array(
            repeating: Array(repeating: XMPatternEventCell.empty, count: defaultChannelCount),
            count: defaultRowCount
        )
        return BlankTrackerDocument(
            title: defaultTitle,
            songLength: defaultSongLength,
            currentPosition: defaultCurrentPosition,
            restartPosition: defaultRestartPosition,
            currentPatternIndex: defaultPatternIndex,
            tempo: defaultTempo,
            speed: defaultSpeed,
            pattern: XMPatternData(
                index: defaultPatternIndex,
                rowCount: defaultRowCount,
                channels: defaultChannelCount,
                rows: rows
            )
        )
    }

    var metadata: ParsedModuleMetadata {
        ParsedModuleMetadata(
            type: "XM",
            title: title,
            version: nil,
            channels: pattern.channels,
            patterns: 1,
            instruments: 0,
            xmFlags: 0x0001,
            defaultTempo: speed,
            defaultBPM: tempo,
            songLength: songLength,
            orderTable: [currentPatternIndex],
            xmPatterns: [pattern]
        )
    }

    var controlPanelMetadata: BlankTrackerControlPanelMetadata {
        BlankTrackerControlPanelMetadata(
            songTitle: title,
            songLength: String(format: "%02d", songLength),
            songPosition: String(format: "%02d", currentPosition),
            restartPosition: String(format: "%02d", restartPosition),
            patternRowCount: "\(pattern.rowCount)",
            channelCount: "\(pattern.channels)",
            tempo: "\(tempo)",
            speed: String(format: "%02d", speed),
            songPositionValue: currentPosition,
            maximumSongPosition: max(0, songLength - 1),
            isSongPositionEnabled: songLength > 1,
            isPatternControlsEnabled: true,
            areInstrumentPlaceholdersEnabled: false
        )
    }
}

struct BlankTrackerControlPanelMetadata: Equatable {
    let songTitle: String
    let songLength: String
    let songPosition: String
    let restartPosition: String
    let patternRowCount: String
    let channelCount: String
    let tempo: String
    let speed: String
    let songPositionValue: Int
    let maximumSongPosition: Int
    let isSongPositionEnabled: Bool
    let isPatternControlsEnabled: Bool
    let areInstrumentPlaceholdersEnabled: Bool
}
