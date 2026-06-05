import Foundation

enum TrackerNoteKeyMap {
    private struct NoteKeyEntry {
        let semitone: UInt8
        let octaveOffset: Int
    }

    static let keyOffNoteValue = XMPatternEventCell.keyOffNoteValue
    // Backtick is the Mac-friendly FT2/MilkyTracker-style key-below-Escape default.
    static let keyOffKey: Character = "`"
    static let maximumNoteValue = 96
    static let maximumOctave = 7

    private static let noteEntriesByKey: [Character: NoteKeyEntry] = [
        "z": NoteKeyEntry(semitone: 0, octaveOffset: 0),
        "s": NoteKeyEntry(semitone: 1, octaveOffset: 0),
        "x": NoteKeyEntry(semitone: 2, octaveOffset: 0),
        "d": NoteKeyEntry(semitone: 3, octaveOffset: 0),
        "c": NoteKeyEntry(semitone: 4, octaveOffset: 0),
        "v": NoteKeyEntry(semitone: 5, octaveOffset: 0),
        "g": NoteKeyEntry(semitone: 6, octaveOffset: 0),
        "b": NoteKeyEntry(semitone: 7, octaveOffset: 0),
        "h": NoteKeyEntry(semitone: 8, octaveOffset: 0),
        "n": NoteKeyEntry(semitone: 9, octaveOffset: 0),
        "j": NoteKeyEntry(semitone: 10, octaveOffset: 0),
        "m": NoteKeyEntry(semitone: 11, octaveOffset: 0),
        "q": NoteKeyEntry(semitone: 0, octaveOffset: 1),
        "2": NoteKeyEntry(semitone: 1, octaveOffset: 1),
        "w": NoteKeyEntry(semitone: 2, octaveOffset: 1),
        "3": NoteKeyEntry(semitone: 3, octaveOffset: 1),
        "e": NoteKeyEntry(semitone: 4, octaveOffset: 1),
        "r": NoteKeyEntry(semitone: 5, octaveOffset: 1),
        "5": NoteKeyEntry(semitone: 6, octaveOffset: 1),
        "t": NoteKeyEntry(semitone: 7, octaveOffset: 1),
        "6": NoteKeyEntry(semitone: 8, octaveOffset: 1),
        "y": NoteKeyEntry(semitone: 9, octaveOffset: 1),
        "7": NoteKeyEntry(semitone: 10, octaveOffset: 1),
        "u": NoteKeyEntry(semitone: 11, octaveOffset: 1)
    ]

    static func isTrackerNoteKey(_ character: Character) -> Bool {
        noteEntry(forTrackerKey: character) != nil
    }

    static func isKeyOffKey(_ character: Character) -> Bool {
        character == keyOffKey
    }

    static func noteValue(forTrackerKey character: Character, octave: Int) -> UInt8? {
        guard let entry = noteEntry(forTrackerKey: character) else {
            return nil
        }
        let targetOctave = octave + entry.octaveOffset
        let clampedOctave = entry.octaveOffset > 0 ? min(targetOctave, maximumOctave) : targetOctave
        let noteValue = clampedOctave * 12 + Int(entry.semitone) + 1
        guard (1...maximumNoteValue).contains(noteValue) else {
            return nil
        }
        return UInt8(noteValue)
    }

    private static func noteEntry(forTrackerKey character: Character) -> NoteKeyEntry? {
        guard let lowercased = String(character).lowercased().first else {
            return nil
        }
        return noteEntriesByKey[lowercased]
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
