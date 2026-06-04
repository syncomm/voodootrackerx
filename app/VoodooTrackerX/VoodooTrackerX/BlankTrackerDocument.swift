import Foundation

enum TrackerNaturalNoteKeyMap {
    private static let naturalNoteSemitonesByKey: [Character: UInt8] = [
        "z": 0,
        "x": 2,
        "c": 4,
        "v": 5,
        "b": 7,
        "n": 9,
        "m": 11
    ]

    static func isTrackerNoteKey(_ character: Character) -> Bool {
        naturalNoteSemitone(forTrackerKey: character) != nil
    }

    static func noteValue(forTrackerKey character: Character, octave: Int) -> UInt8? {
        guard let semitone = naturalNoteSemitone(forTrackerKey: character) else {
            return nil
        }
        let noteValue = octave * 12 + Int(semitone) + 1
        guard (1...96).contains(noteValue) else {
            return nil
        }
        return UInt8(noteValue)
    }

    private static func naturalNoteSemitone(forTrackerKey character: Character) -> UInt8? {
        guard let lowercased = String(character).lowercased().first else {
            return nil
        }
        return naturalNoteSemitonesByKey[lowercased]
    }
}

enum TrackerEditStep {
    static let defaultStep = 1

    static func advancedRow(after row: Int, rowCount: Int, editStep: Int = defaultStep) -> Int {
        guard rowCount > 0 else {
            return 0
        }
        return min(rowCount - 1, max(0, row) + max(0, editStep))
    }
}

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
    var pattern: XMPatternData

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
            restartPosition: restartPosition,
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

    mutating func enterNote(trackerKey: Character, octave: Int, row: Int, channel: Int) -> Bool {
        guard pattern.rows.indices.contains(row),
              pattern.rows[row].indices.contains(channel),
              let note = TrackerNaturalNoteKeyMap.noteValue(forTrackerKey: trackerKey, octave: octave) else {
            return false
        }

        let cell = pattern.rows[row][channel]
        pattern.rows[row][channel] = XMPatternEventCell(
            note: note,
            instrument: cell.instrument,
            volumeColumn: cell.volumeColumn,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
        return true
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
