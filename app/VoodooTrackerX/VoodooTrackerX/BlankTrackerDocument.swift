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

enum EditorNoteAuditionSourceContext: Equatable {
    case blankDocument
    case loadedModule(patternIndex: Int?)
}

enum EditorNoteAuditionRequestKind: Equatable {
    case noteOn(noteValue: UInt8, selectedOctave: Int)
    case previewKeyOff
}

struct EditorNoteAuditionRequest: Equatable {
    let kind: EditorNoteAuditionRequestKind
    let selectedInstrumentIndex: Int
    let selectedSampleIndex: Int
    let sourceContext: EditorNoteAuditionSourceContext
    let channelIndex: Int?
    let rowIndex: Int?
    let isRepeatedKeyDown: Bool

    init(
        kind: EditorNoteAuditionRequestKind,
        selection: TrackerEditorSelection,
        sourceContext: EditorNoteAuditionSourceContext,
        channelIndex: Int? = nil,
        rowIndex: Int? = nil,
        isRepeatedKeyDown: Bool = false
    ) {
        self.kind = kind
        selectedInstrumentIndex = selection.selectedInstrument
        selectedSampleIndex = selection.selectedSample
        self.sourceContext = sourceContext
        self.channelIndex = channelIndex.map { max(0, $0) }
        self.rowIndex = rowIndex.map { max(0, $0) }
        self.isRepeatedKeyDown = isRepeatedKeyDown
    }

    static func noteOn(
        trackerKey: Character,
        selectedOctave: Int,
        selection: TrackerEditorSelection,
        sourceContext: EditorNoteAuditionSourceContext,
        channelIndex: Int? = nil,
        rowIndex: Int? = nil,
        isRepeatedKeyDown: Bool = false
    ) -> EditorNoteAuditionRequest? {
        guard let noteValue = TrackerNoteKeyMap.noteValue(forTrackerKey: trackerKey, octave: selectedOctave) else {
            return nil
        }
        return EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: noteValue, selectedOctave: selectedOctave),
            selection: selection,
            sourceContext: sourceContext,
            channelIndex: channelIndex,
            rowIndex: rowIndex,
            isRepeatedKeyDown: isRepeatedKeyDown
        )
    }

    static func previewKeyOff(
        selection: TrackerEditorSelection,
        sourceContext: EditorNoteAuditionSourceContext,
        channelIndex: Int? = nil,
        rowIndex: Int? = nil
    ) -> EditorNoteAuditionRequest {
        EditorNoteAuditionRequest(
            kind: .previewKeyOff,
            selection: selection,
            sourceContext: sourceContext,
            channelIndex: channelIndex,
            rowIndex: rowIndex
        )
    }
}

enum EditorPatternMutationPolicy {
    static func canMutatePattern(sourceContext: EditorNoteAuditionSourceContext) -> Bool {
        switch sourceContext {
        case .blankDocument:
            return true
        case .loadedModule:
            return false
        }
    }
}

enum EditorNoteAuditionUnavailableReason: Equatable {
    case blankDocumentMissingInstrumentSamplePayload
    case loadedModuleMissingPlaybackSong
    case selectedInstrumentUnavailable
    case selectedSampleUnavailable
    case selectedSampleMissingPayload
    case selectedInstrumentSampleNotPlayable
}

struct EditorNoteAuditionSampleDescriptor: Equatable {
    let instrumentIndex: Int
    let sampleIndex: Int
    let sampleFrameCount: Int
    let hasSamplePayload: Bool
    let hasLoopMetadata: Bool
    let sourceContext: EditorNoteAuditionSourceContext
    let previewPCM: [Float]
    let previewVolume: Float
    let previewBaseSampleRate: Double
    let previewRelativeNote: Int
    let previewFinetune: Int

    init(
        instrumentIndex: Int,
        sampleIndex: Int,
        sampleFrameCount: Int,
        hasSamplePayload: Bool,
        hasLoopMetadata: Bool,
        sourceContext: EditorNoteAuditionSourceContext,
        previewPCM: [Float] = [],
        previewVolume: Float = 1,
        previewBaseSampleRate: Double = 8_363,
        previewRelativeNote: Int = 0,
        previewFinetune: Int = 0
    ) {
        self.instrumentIndex = max(1, instrumentIndex)
        self.sampleIndex = max(0, sampleIndex)
        self.sampleFrameCount = max(0, sampleFrameCount)
        self.hasSamplePayload = hasSamplePayload
        self.hasLoopMetadata = hasLoopMetadata
        self.sourceContext = sourceContext
        self.previewPCM = previewPCM.map { $0.isFinite ? $0 : 0 }
        self.previewVolume = previewVolume.isFinite ? min(1, max(0, previewVolume)) : 1
        self.previewBaseSampleRate = previewBaseSampleRate.isFinite && previewBaseSampleRate > 0
            ? previewBaseSampleRate
            : 8_363
        self.previewRelativeNote = min(96, max(-96, previewRelativeNote))
        self.previewFinetune = PlaybackSongSyntheticAdapter.clampedFinetune(previewFinetune)
    }
}

enum EditorNoteAuditionAvailability: Equatable {
    case potentiallyAvailable(EditorNoteAuditionSampleDescriptor)
    case unavailable(EditorNoteAuditionUnavailableReason)
}

struct EditorNoteAuditionPreviewEvent: Equatable {
    let request: EditorNoteAuditionRequest
    let sampleDescriptor: EditorNoteAuditionSampleDescriptor
    let noteValue: UInt8
    let selectedOctave: Int
}

enum EditorNoteAuditionPreviewSkipReason: Equatable {
    case missingRequest
    case nonNoteRequest
    case repeatedKeyDown
    case unavailable(EditorNoteAuditionUnavailableReason)
    case loadedModulePayloadRequired
}

enum EditorNoteAuditionPreviewOutcome: Equatable {
    case attempted(EditorNoteAuditionPreviewEvent)
    case skipped(EditorNoteAuditionPreviewSkipReason)

    var didAttemptPreview: Bool {
        if case .attempted = self {
            return true
        }
        return false
    }
}

protocol EditorNoteAuditionPreviewSink: AnyObject {
    func preview(_ event: EditorNoteAuditionPreviewEvent)
    func cancelPreview()
}

final class NoopEditorNoteAuditionPreviewSink: EditorNoteAuditionPreviewSink {
    func preview(_ event: EditorNoteAuditionPreviewEvent) {}
    func cancelPreview() {}
}

final class EditorNoteAuditionPreviewer {
    private let sink: EditorNoteAuditionPreviewSink

    init(sink: EditorNoteAuditionPreviewSink = NoopEditorNoteAuditionPreviewSink()) {
        self.sink = sink
    }

    @discardableResult
    func preview(
        request: EditorNoteAuditionRequest?,
        availability: EditorNoteAuditionAvailability
    ) -> EditorNoteAuditionPreviewOutcome {
        guard let request else {
            return .skipped(.missingRequest)
        }
        guard !request.isRepeatedKeyDown else {
            return .skipped(.repeatedKeyDown)
        }
        guard case let .noteOn(noteValue, selectedOctave) = request.kind else {
            return .skipped(.nonNoteRequest)
        }
        guard case let .potentiallyAvailable(descriptor) = availability else {
            if case let .unavailable(reason) = availability {
                return .skipped(.unavailable(reason))
            }
            return .skipped(.loadedModulePayloadRequired)
        }
        guard case .loadedModule = descriptor.sourceContext,
              descriptor.hasSamplePayload,
              descriptor.sampleFrameCount > 0,
              !descriptor.previewPCM.isEmpty else {
            return .skipped(.loadedModulePayloadRequired)
        }

        let event = EditorNoteAuditionPreviewEvent(
            request: request,
            sampleDescriptor: descriptor,
            noteValue: noteValue,
            selectedOctave: selectedOctave
        )
        sink.preview(event)
        return .attempted(event)
    }

    func cancelPreview() {
        sink.cancelPreview()
    }
}

enum EditorNoteAuditionAvailabilityResolver {
    static func availability(
        for request: EditorNoteAuditionRequest,
        hasRealInstrumentSamplePayload: Bool,
        selectedInstrumentSampleIsPlayable: Bool
    ) -> EditorNoteAuditionAvailability {
        if request.sourceContext == .blankDocument && !hasRealInstrumentSamplePayload {
            return .unavailable(.blankDocumentMissingInstrumentSamplePayload)
        }
        if !selectedInstrumentSampleIsPlayable {
            return .unavailable(.selectedInstrumentSampleNotPlayable)
        }
        return .potentiallyAvailable(EditorNoteAuditionSampleDescriptor(
            instrumentIndex: request.selectedInstrumentIndex,
            sampleIndex: max(0, request.selectedSampleIndex - 1),
            sampleFrameCount: 0,
            hasSamplePayload: hasRealInstrumentSamplePayload,
            hasLoopMetadata: false,
            sourceContext: request.sourceContext
        ))
    }

    static func availability(
        for request: EditorNoteAuditionRequest,
        loadedPlaybackSong song: PlaybackSong?
    ) -> EditorNoteAuditionAvailability {
        guard case .loadedModule = request.sourceContext else {
            return availability(
                for: request,
                hasRealInstrumentSamplePayload: false,
                selectedInstrumentSampleIsPlayable: false
            )
        }
        guard let song else {
            return .unavailable(.loadedModuleMissingPlaybackSong)
        }
        guard let instrument = song.instrument(forInstrument: request.selectedInstrumentIndex) else {
            return .unavailable(.selectedInstrumentUnavailable)
        }

        guard case let .noteOn(noteValue, _) = request.kind else {
            return .unavailable(.selectedSampleUnavailable)
        }
        let sampleSelection = PlaybackSongSyntheticAdapter.selectSample(forNote: noteValue, from: instrument)
        guard let sample = sampleSelection.sample else {
            if sampleSelection.skippedReason == .samplePCMEmpty {
                return .unavailable(.selectedSampleMissingPayload)
            }
            return .unavailable(.selectedSampleUnavailable)
        }

        let frameCount = min(max(0, sample.sampleLength), sample.pcm.count)
        guard frameCount > 0 else {
            return .unavailable(.selectedSampleMissingPayload)
        }
        guard sample.isPlayable else {
            return .unavailable(.selectedInstrumentSampleNotPlayable)
        }

        return .potentiallyAvailable(EditorNoteAuditionSampleDescriptor(
            instrumentIndex: instrument.index,
            sampleIndex: sample.sampleIndex,
            sampleFrameCount: frameCount,
            hasSamplePayload: true,
            hasLoopMetadata: sample.loopRegion.isEnabled,
            sourceContext: request.sourceContext,
            previewPCM: Array(sample.pcm.prefix(frameCount)),
            previewVolume: sample.volume,
            previewBaseSampleRate: sample.baseSampleRate,
            previewRelativeNote: sample.relativeNote,
            previewFinetune: sample.finetune
        ))
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

    var noteAuditionSourceContext: EditorNoteAuditionSourceContext {
        .blankDocument
    }

    var noteAuditionAvailability: EditorNoteAuditionAvailability {
        .unavailable(.blankDocumentMissingInstrumentSamplePayload)
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
