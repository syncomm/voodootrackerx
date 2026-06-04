import Foundation

enum TrackerNoteKeyMap {
    static let keyOffNoteValue = XMPatternEventCell.keyOffNoteValue
    // Backtick is the Mac-friendly FT2/MilkyTracker-style key-below-Escape default.
    static let keyOffKey: Character = "`"

    private static let noteSemitonesByKey: [Character: UInt8] = [
        "z": 0,
        "s": 1,
        "x": 2,
        "d": 3,
        "c": 4,
        "v": 5,
        "g": 6,
        "b": 7,
        "h": 8,
        "n": 9,
        "j": 10,
        "m": 11
    ]

    static func isTrackerNoteKey(_ character: Character) -> Bool {
        noteSemitone(forTrackerKey: character) != nil
    }

    static func isKeyOffKey(_ character: Character) -> Bool {
        character == keyOffKey
    }

    static func noteValue(forTrackerKey character: Character, octave: Int) -> UInt8? {
        guard let semitone = noteSemitone(forTrackerKey: character) else {
            return nil
        }
        let noteValue = octave * 12 + Int(semitone) + 1
        guard (1...96).contains(noteValue) else {
            return nil
        }
        return UInt8(noteValue)
    }

    private static func noteSemitone(forTrackerKey character: Character) -> UInt8? {
        guard let lowercased = String(character).lowercased().first else {
            return nil
        }
        return noteSemitonesByKey[lowercased]
    }
}

typealias TrackerNaturalNoteKeyMap = TrackerNoteKeyMap

enum TrackerEditStep {
    static let defaultStep = 1

    static func advancedRow(after row: Int, rowCount: Int, editStep: Int = defaultStep) -> Int {
        guard rowCount > 0 else {
            return 0
        }
        return min(rowCount - 1, max(0, row) + max(0, editStep))
    }
}

struct TrackerEditorSelection: Equatable {
    static let defaultInstrument = 1
    static let defaultSample = 1
    static let `default` = TrackerEditorSelection()

    let selectedInstrument: Int
    let selectedSample: Int

    init(
        selectedInstrument: Int = Self.defaultInstrument,
        selectedSample: Int = Self.defaultSample
    ) {
        self.selectedInstrument = Self.clampedTrackerIndex(selectedInstrument)
        self.selectedSample = Self.clampedTrackerIndex(selectedSample)
    }

    var instrumentDisplayTitle: String {
        String(format: "I%02X", selectedInstrument)
    }

    var sampleDisplayTitle: String {
        String(format: "S%02X", selectedSample)
    }

    private static func clampedTrackerIndex(_ value: Int) -> Int {
        min(255, max(1, value))
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
    let selection: TrackerEditorSelection
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
            selection: .default,
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
            selectedInstrumentDisplay: selection.instrumentDisplayTitle,
            selectedSampleDisplay: selection.sampleDisplayTitle,
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
              let note = TrackerNoteKeyMap.noteValue(forTrackerKey: trackerKey, octave: octave) else {
            return false
        }

        setNoteValue(note, row: row, channel: channel)
        return true
    }

    mutating func enterKeyOff(row: Int, channel: Int) -> Bool {
        guard pattern.rows.indices.contains(row),
              pattern.rows[row].indices.contains(channel) else {
            return false
        }

        setNoteValue(TrackerNoteKeyMap.keyOffNoteValue, row: row, channel: channel)
        return true
    }

    mutating func clearNote(row: Int, channel: Int) -> Bool {
        guard pattern.rows.indices.contains(row),
              pattern.rows[row].indices.contains(channel) else {
            return false
        }

        setNoteValue(0, row: row, channel: channel)
        return true
    }

    private mutating func setNoteValue(_ note: UInt8, row: Int, channel: Int) {
        let cell = pattern.rows[row][channel]
        pattern.rows[row][channel] = XMPatternEventCell(
            note: note,
            instrument: cell.instrument,
            volumeColumn: cell.volumeColumn,
            effectType: cell.effectType,
            effectParam: cell.effectParam
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
    let selectedInstrumentDisplay: String
    let selectedSampleDisplay: String
    let tempo: String
    let speed: String
    let songPositionValue: Int
    let maximumSongPosition: Int
    let isSongPositionEnabled: Bool
    let isPatternControlsEnabled: Bool
    let areInstrumentPlaceholdersEnabled: Bool
}
