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

struct EditorClearSongDataResetPosition: Equatable {
    static let start = EditorClearSongDataResetPosition(row: 0, channel: 0, fieldRawValue: 0)

    let row: Int
    let channel: Int
    let fieldRawValue: Int
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

    func withSelectedInstrument(_ selectedInstrument: Int, availableSampleSlots: [Int] = []) -> TrackerEditorSelection {
        TrackerEditorSelection(
            selectedInstrument: selectedInstrument,
            selectedSample: selectedSample
        ).clampedToAvailableSampleSlots(availableSampleSlots)
    }

    func withSelectedSample(_ selectedSample: Int) -> TrackerEditorSelection {
        TrackerEditorSelection(
            selectedInstrument: selectedInstrument,
            selectedSample: selectedSample
        )
    }

    func clampedToAvailableSampleSlots(_ availableSampleSlots: [Int]) -> TrackerEditorSelection {
        let sampleSlots = Self.normalizedSampleSlots(availableSampleSlots)
        guard !sampleSlots.isEmpty else {
            return TrackerEditorSelection(selectedInstrument: selectedInstrument, selectedSample: Self.defaultSample)
        }
        let sample = sampleSlots.contains(selectedSample) ? selectedSample : sampleSlots[0]
        return TrackerEditorSelection(selectedInstrument: selectedInstrument, selectedSample: sample)
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

    private static func normalizedSampleSlots(_ sampleSlots: [Int]) -> [Int] {
        Array(Set(sampleSlots.map(clampedTrackerIndex))).sorted()
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

    static func canClearCurrentPattern(sourceContext: EditorNoteAuditionSourceContext) -> Bool {
        canMutatePattern(sourceContext: sourceContext)
    }

    static func canClearSongData(sourceContext: EditorNoteAuditionSourceContext) -> Bool {
        canMutatePattern(sourceContext: sourceContext)
    }
}

enum EditorCommandAvailability {
    static func canClearCurrentPattern(
        hasBlankDocument: Bool,
        sourceContext: EditorNoteAuditionSourceContext
    ) -> Bool {
        hasBlankDocument && EditorPatternMutationPolicy.canClearCurrentPattern(sourceContext: sourceContext)
    }

    static func canClearSongData(
        hasBlankDocument: Bool,
        sourceContext: EditorNoteAuditionSourceContext,
        loadedModuleCanMakeEditableCopy: Bool = false
    ) -> Bool {
        switch sourceContext {
        case .blankDocument:
            return hasBlankDocument && EditorPatternMutationPolicy.canClearSongData(sourceContext: sourceContext)
        case .loadedModule:
            return !hasBlankDocument && loadedModuleCanMakeEditableCopy
        }
    }
}

struct EditorNoteAuditionInputRoute: Equatable {
    let shouldAttemptPreview: Bool
    let shouldMutatePattern: Bool
    let shouldConsumeRepeatedNoteKey: Bool
    let shouldSuppressRepeatedMutation: Bool

    func shouldConsumeNonMutatingInput(previewOutcome: EditorNoteAuditionPreviewOutcome) -> Bool {
        shouldConsumeRepeatedNoteKey || shouldSuppressRepeatedMutation || previewOutcome.didAttemptPreview
    }
}

enum EditorNoteAuditionInputKind: Equatable {
    case noteKey(isRepeat: Bool)
    case keyOff
    case repeatedKeyOff
    case clearField
    case repeatedClearField
    case other
}

enum EditablePatternCellField {
    case note
    case instrument
    case volume
    case effectType
    case effectParam
}

enum EditorNoteAuditionInputPolicy {
    static func route(
        input: EditorNoteAuditionInputKind,
        editModeEnabled: Bool,
        sourceContext: EditorNoteAuditionSourceContext,
        isNoteField: Bool
    ) -> EditorNoteAuditionInputRoute {
        let canMutateSource = EditorPatternMutationPolicy.canMutatePattern(sourceContext: sourceContext)
        let shouldConsumeRepeatedNoteKey = isNoteField && isRepeatedNoteKey(input)
        let shouldSuppressRepeatedMutation = isRepeatedInput(input) &&
            isMutationInput(input, isNoteField: isNoteField)
        return EditorNoteAuditionInputRoute(
            shouldAttemptPreview: isNoteField && isNoteKey(input) && !shouldConsumeRepeatedNoteKey,
            shouldMutatePattern: editModeEnabled &&
                canMutateSource &&
                isMutationInput(input, isNoteField: isNoteField) &&
                !shouldSuppressRepeatedMutation,
            shouldConsumeRepeatedNoteKey: shouldConsumeRepeatedNoteKey,
            shouldSuppressRepeatedMutation: shouldSuppressRepeatedMutation
        )
    }

    static func shouldConsumeNoteKeyRelease(
        didStopPreview: Bool,
        editModeEnabled: Bool,
        isNoteField: Bool
    ) -> Bool {
        didStopPreview || (editModeEnabled && isNoteField)
    }

    private static func isNoteKey(_ input: EditorNoteAuditionInputKind) -> Bool {
        if case .noteKey = input {
            return true
        }
        return false
    }

    private static func isRepeatedNoteKey(_ input: EditorNoteAuditionInputKind) -> Bool {
        if case let .noteKey(isRepeat) = input {
            return isRepeat
        }
        return false
    }

    private static func isRepeatedInput(_ input: EditorNoteAuditionInputKind) -> Bool {
        switch input {
        case let .noteKey(isRepeat):
            return isRepeat
        case .repeatedKeyOff, .repeatedClearField:
            return true
        case .keyOff, .clearField, .other:
            return false
        }
    }

    private static func isMutationInput(_ input: EditorNoteAuditionInputKind, isNoteField: Bool) -> Bool {
        switch input {
        case .clearField, .repeatedClearField:
            return true
        case .keyOff, .repeatedKeyOff, .noteKey:
            return isNoteField
        case .other:
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
    let previewLoop: MixerSampleLoop
    let sourceContext: EditorNoteAuditionSourceContext
    let previewPCM: [Float]
    let previewVolume: Float
    let previewPanning: UInt8
    let previewBaseSampleRate: Double
    let previewRelativeNote: Int
    let previewFinetune: Int

    init(
        instrumentIndex: Int,
        sampleIndex: Int,
        sampleFrameCount: Int,
        hasSamplePayload: Bool,
        hasLoopMetadata: Bool,
        previewLoop: MixerSampleLoop = .none,
        sourceContext: EditorNoteAuditionSourceContext,
        previewPCM: [Float] = [],
        previewVolume: Float = 1,
        previewPanning: UInt8 = PlaybackSample.xmCenterPanning,
        previewBaseSampleRate: Double = 8_363,
        previewRelativeNote: Int = 0,
        previewFinetune: Int = 0
    ) {
        let sanitizedFrameCount = max(0, sampleFrameCount)
        let sanitizedLoop = previewLoop.sanitized(sampleFrameCount: sanitizedFrameCount)
        self.instrumentIndex = max(1, instrumentIndex)
        self.sampleIndex = max(0, sampleIndex)
        self.sampleFrameCount = sanitizedFrameCount
        self.hasSamplePayload = hasSamplePayload
        self.hasLoopMetadata = hasLoopMetadata || sanitizedLoop.mode != .none
        self.previewLoop = sanitizedLoop
        self.sourceContext = sourceContext
        self.previewPCM = previewPCM.map { $0.isFinite ? $0 : 0 }
        self.previewVolume = previewVolume.isFinite ? min(1, max(0, previewVolume)) : 1
        self.previewPanning = previewPanning
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

struct EditorNoteAuditionKeyIdentity: Equatable {
    let trackerKey: Character?

    init?(trackerKey character: Character) {
        guard let normalized = String(character).lowercased().first,
              TrackerNoteKeyMap.isTrackerNoteKey(normalized) else {
            return nil
        }
        trackerKey = normalized
    }

    static let instrumentEditorKeyboard = EditorNoteAuditionKeyIdentity()

    private init() { trackerKey = nil }
}

struct EditorNoteAuditionPreviewToken: Equatable {
    let generation: UInt64
    let keyIdentity: EditorNoteAuditionKeyIdentity
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
    private(set) var activePreviewToken: EditorNoteAuditionPreviewToken?
    private var previewGeneration: UInt64 = 0

    init(sink: EditorNoteAuditionPreviewSink = NoopEditorNoteAuditionPreviewSink()) {
        self.sink = sink
    }

    @discardableResult
    func preview(
        request: EditorNoteAuditionRequest?,
        availability: EditorNoteAuditionAvailability,
        keyIdentity: EditorNoteAuditionKeyIdentity? = nil
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
        guard descriptor.hasSamplePayload,
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
        activePreviewToken = keyIdentity.map {
            nextPreviewToken(keyIdentity: $0, noteValue: noteValue, selectedOctave: selectedOctave)
        }
        return .attempted(event)
    }

    @discardableResult
    func stopPreview(for keyIdentity: EditorNoteAuditionKeyIdentity) -> Bool {
        guard let token = activePreviewToken,
              token.keyIdentity == keyIdentity else {
            return false
        }
        return stopPreview(for: token)
    }

    @discardableResult
    func stopPreview(for token: EditorNoteAuditionPreviewToken) -> Bool {
        guard activePreviewToken == token else {
            return false
        }
        activePreviewToken = nil
        sink.cancelPreview()
        return true
    }

    func cancelPreview() {
        activePreviewToken = nil
        sink.cancelPreview()
    }

    private func nextPreviewToken(
        keyIdentity: EditorNoteAuditionKeyIdentity,
        noteValue: UInt8,
        selectedOctave: Int
    ) -> EditorNoteAuditionPreviewToken {
        previewGeneration &+= 1
        return EditorNoteAuditionPreviewToken(
            generation: previewGeneration,
            keyIdentity: keyIdentity,
            noteValue: noteValue,
            selectedOctave: selectedOctave
        )
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

        guard case .noteOn = request.kind else {
            return .unavailable(.selectedSampleUnavailable)
        }
        guard let sample = instrument.sample(selectedSampleSlot: request.selectedSampleIndex) else {
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
            previewLoop: PlaybackSongSyntheticAdapter.mixerLoop(from: sample),
            sourceContext: request.sourceContext,
            previewPCM: Array(sample.pcm.prefix(frameCount)),
            previewVolume: sample.volume,
            previewPanning: sample.panning,
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
    let orderTable: [Int]
    var selection: TrackerEditorSelection
    let instrumentPalette: [Int: PlaybackInstrument]
    var patterns: [XMPatternData]

    var pattern: XMPatternData {
        get {
            pattern(for: currentPatternIndex)
                ?? Self.makeEmptyPattern(index: currentPatternIndex)
        }
        set {
            replacePattern(newValue)
        }
    }

    static func makeDefault() -> BlankTrackerDocument {
        let pattern = makeEmptyPattern(
            index: defaultPatternIndex,
            rowCount: defaultRowCount,
            channels: defaultChannelCount
        )
        return BlankTrackerDocument(
            title: defaultTitle,
            songLength: defaultSongLength,
            currentPosition: defaultCurrentPosition,
            restartPosition: defaultRestartPosition,
            currentPatternIndex: defaultPatternIndex,
            tempo: defaultTempo,
            speed: defaultSpeed,
            orderTable: [defaultPatternIndex],
            selection: .default,
            instrumentPalette: [:],
            patterns: [pattern]
        )
    }

    static func makeEditableCopyClearingSongData(
        from metadata: ParsedModuleMetadata,
        playbackSong: PlaybackSong,
        selection: TrackerEditorSelection,
        sourcePatternIndex: Int = defaultPatternIndex
    ) -> BlankTrackerDocument? {
        guard hasUsableInstrumentSamplePalette(playbackSong.instrumentsByIndex) else {
            return nil
        }

        let sourcePattern = metadata.xmPatterns.first { $0.index == sourcePatternIndex }
            ?? metadata.xmPatterns.first
        let rowCount = max(1, sourcePattern?.rowCount ?? defaultRowCount)
        let channelCount = max(1, metadata.channels > 0 ? metadata.channels : sourcePattern?.channels ?? defaultChannelCount)
        let pattern = makeEmptyPattern(
            index: defaultPatternIndex,
            rowCount: rowCount,
            channels: channelCount
        )
        let palette = playbackSong.instrumentsByIndex
        return BlankTrackerDocument(
            title: defaultTitle,
            songLength: defaultSongLength,
            currentPosition: defaultCurrentPosition,
            restartPosition: defaultRestartPosition,
            currentPatternIndex: defaultPatternIndex,
            tempo: metadata.defaultBPM > 0 ? metadata.defaultBPM : defaultTempo,
            speed: metadata.defaultTempo > 0 ? metadata.defaultTempo : defaultSpeed,
            orderTable: [defaultPatternIndex],
            selection: clampedSelection(selection, instrumentPalette: palette),
            instrumentPalette: palette,
            patterns: [pattern]
        )
    }

    static func makeEditableCopy(
        from metadata: ParsedModuleMetadata,
        playbackSong: PlaybackSong,
        selection: TrackerEditorSelection,
        sourcePatternIndex: Int = defaultPatternIndex
    ) -> BlankTrackerDocument? {
        guard let copiedPatterns = copiedEditablePatterns(from: metadata) else {
            return nil
        }

        let safeOrderTable = copiedOrderTable(from: metadata, availablePatterns: copiedPatterns)
        let selectedPosition = min(max(0, sourceOrderPosition(for: sourcePatternIndex, in: safeOrderTable)), safeOrderTable.count - 1)
        let selectedPatternIndex = safeOrderTable[selectedPosition]
        let palette = playbackSong.instrumentsByIndex
        return BlankTrackerDocument(
            title: defaultTitle,
            songLength: safeOrderTable.count,
            currentPosition: selectedPosition,
            restartPosition: clampedRestartPosition(metadata.restartPosition, songLength: safeOrderTable.count),
            currentPatternIndex: selectedPatternIndex,
            tempo: metadata.defaultBPM > 0 ? metadata.defaultBPM : defaultTempo,
            speed: metadata.defaultTempo > 0 ? metadata.defaultTempo : defaultSpeed,
            orderTable: safeOrderTable,
            selection: clampedSelection(selection, instrumentPalette: palette),
            instrumentPalette: palette,
            patterns: copiedPatterns
        )
    }

    static func makeEmptyPattern(
        index: Int,
        rowCount: Int = defaultRowCount,
        channels: Int = defaultChannelCount
    ) -> XMPatternData {
        let safeRowCount = max(0, rowCount)
        let safeChannelCount = max(0, channels)
        let rows = Array(
            repeating: Array(repeating: XMPatternEventCell.empty, count: safeChannelCount),
            count: safeRowCount
        )
        return XMPatternData(
            index: max(0, index),
            rowCount: safeRowCount,
            channels: safeChannelCount,
            rows: rows
        )
    }

    var metadata: ParsedModuleMetadata {
        let currentPattern = pattern
        return ParsedModuleMetadata(
            type: "XM",
            title: title,
            version: nil,
            channels: currentPattern.channels,
            patterns: patterns.count,
            instruments: instrumentCount,
            xmFlags: 0x0001,
            defaultTempo: speed,
            defaultBPM: tempo,
            songLength: songLength,
            restartPosition: restartPosition,
            orderTable: orderTable,
            xmPatterns: patterns
        )
    }

    var controlPanelMetadata: BlankTrackerControlPanelMetadata {
        let currentPattern = pattern
        return BlankTrackerControlPanelMetadata(
            songTitle: title,
            songLength: String(format: "%02d", songLength),
            songPosition: String(format: "%02d", currentPosition),
            restartPosition: String(format: "%02d", restartPosition),
            patternRowCount: "\(currentPattern.rowCount)",
            channelCount: "\(currentPattern.channels)",
            selectedInstrumentDisplay: selectedInstrumentDisplay.displayTitle,
            selectedInstrumentTooltip: selectedInstrumentDisplay.tooltip,
            selectedSampleDisplay: selectedSampleDisplay.displayTitle,
            selectedSampleTooltip: selectedSampleDisplay.tooltip,
            tempo: "\(tempo)",
            speed: String(format: "%02d", speed),
            songPositionValue: currentPosition,
            maximumSongPosition: max(0, songLength - 1),
            isSongPositionEnabled: songLength > 1,
            isPatternControlsEnabled: true,
            areInstrumentPlaceholdersEnabled: hasInstrumentSamplePalette
        )
    }

    var noteAuditionSourceContext: EditorNoteAuditionSourceContext {
        .blankDocument
    }

    var noteAuditionAvailability: EditorNoteAuditionAvailability {
        noteAuditionAvailability(for: selection)
    }

    func noteAuditionAvailability(for selection: TrackerEditorSelection) -> EditorNoteAuditionAvailability {
        guard let instrument = instrument(forInstrument: selection.selectedInstrument) else {
            return .unavailable(hasInstrumentSamplePalette ? .selectedInstrumentUnavailable : .blankDocumentMissingInstrumentSamplePayload)
        }
        guard let sample = instrument.sample(selectedSampleSlot: selection.selectedSample) else {
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
            previewLoop: PlaybackSongSyntheticAdapter.mixerLoop(from: sample),
            sourceContext: noteAuditionSourceContext,
            previewPCM: Array(sample.pcm.prefix(frameCount)),
            previewVolume: sample.volume,
            previewPanning: sample.panning,
            previewBaseSampleRate: sample.baseSampleRate,
            previewRelativeNote: sample.relativeNote,
            previewFinetune: sample.finetune
        ))
    }

    var hasInstrumentSamplePalette: Bool {
        Self.hasUsableInstrumentSamplePalette(instrumentPalette)
    }

    var instrumentCount: Int {
        max(instrumentPalette.keys.max() ?? 0, hasInstrumentSamplePalette ? 1 : 0)
    }

    func pattern(for patternIndex: Int) -> XMPatternData? {
        patterns.first { $0.index == patternIndex }
    }

    func instrument(forInstrument instrumentIndex: Int) -> PlaybackInstrument? {
        guard instrumentIndex > 0 else {
            return nil
        }
        return instrumentPalette[instrumentIndex]
    }

    func availableSampleSlots(forInstrument instrumentIndex: Int) -> [Int] {
        instrument(forInstrument: instrumentIndex)?.availableSampleSlots ?? []
    }

    mutating func selectInstrument(_ instrumentIndex: Int) {
        guard let instrument = instrument(forInstrument: instrumentIndex) else { return }
        selection = selection.withSelectedInstrument(
            instrumentIndex,
            availableSampleSlots: instrument.availableSampleSlots
        )
    }

    mutating func selectSample(_ sampleIndex: Int) {
        selection = selection.withSelectedSample(sampleIndex)
    }

    @discardableResult
    mutating func renameInstrument(at zeroBasedIndex: Int, name: String) -> Bool {
        guard zeroBasedIndex >= 0, zeroBasedIndex < 255 else { return false }
        let instrumentSlot = zeroBasedIndex + 1
        guard let instrument = instrumentPalette[instrumentSlot] else { return false }

        let sanitizedName = EditableXMTextEncoding.sanitizedInstrumentName(name)
        guard instrument.name != sanitizedName else { return false }

        var updatedPalette = instrumentPalette
        updatedPalette[instrumentSlot] = instrument.withName(sanitizedName)
        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: updatedPalette,
            patterns: patterns
        )
        return true
    }

    @discardableResult
    mutating func setSampleVolume(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, volume: UInt8) -> Bool {
        guard volume <= PlaybackSample.xmMaximumVolume,
              (0..<255).contains(zeroBasedInstrumentIndex),
              (0..<255).contains(zeroBasedSampleIndex),
              let instrument = instrumentPalette[zeroBasedInstrumentIndex + 1],
              let sampleStorageIndex = instrument.samples.firstIndex(where: {
                  $0.sampleIndex == zeroBasedSampleIndex && $0.sampleLength > 0 && !$0.pcm.isEmpty
              }),
              instrument.samples[sampleStorageIndex].xmVolume != volume else {
            return false
        }

        var samples = instrument.samples
        samples[sampleStorageIndex] = samples[sampleStorageIndex].withVolume(volume)
        var palette = instrumentPalette
        palette[zeroBasedInstrumentIndex + 1] = PlaybackInstrument(
            index: instrument.index,
            name: instrument.name,
            samples: samples,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            noteSampleMap: instrument.noteSampleMap
        )
        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: palette,
            patterns: patterns
        )
        return true
    }

    @discardableResult
    mutating func setSampleRelativeNote(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, relativeNote: Int) -> Bool {
        guard PlaybackSample.xmRelativeNoteRange.contains(relativeNote),
              (0..<255).contains(zeroBasedInstrumentIndex),
              (0..<255).contains(zeroBasedSampleIndex),
              let instrument = instrumentPalette[zeroBasedInstrumentIndex + 1],
              let sampleStorageIndex = instrument.samples.firstIndex(where: {
                  $0.sampleIndex == zeroBasedSampleIndex && $0.sampleLength > 0 && !$0.pcm.isEmpty
              }),
              instrument.samples[sampleStorageIndex].relativeNote != relativeNote else {
            return false
        }

        var samples = instrument.samples
        samples[sampleStorageIndex] = samples[sampleStorageIndex].withRelativeNote(relativeNote)
        var palette = instrumentPalette
        palette[zeroBasedInstrumentIndex + 1] = PlaybackInstrument(
            index: instrument.index,
            name: instrument.name,
            samples: samples,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            noteSampleMap: instrument.noteSampleMap
        )
        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: palette,
            patterns: patterns
        )
        return true
    }

    @discardableResult
    mutating func setSampleFinetune(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, finetune: Int) -> Bool {
        guard PlaybackSample.xmFinetuneRange.contains(finetune),
              (0..<255).contains(zeroBasedInstrumentIndex),
              (0..<255).contains(zeroBasedSampleIndex),
              let instrument = instrumentPalette[zeroBasedInstrumentIndex + 1],
              let sampleStorageIndex = instrument.samples.firstIndex(where: {
                  $0.sampleIndex == zeroBasedSampleIndex && $0.sampleLength > 0 && !$0.pcm.isEmpty
              }),
              instrument.samples[sampleStorageIndex].finetune != finetune else {
            return false
        }

        var samples = instrument.samples
        samples[sampleStorageIndex] = samples[sampleStorageIndex].withFinetune(finetune)
        var palette = instrumentPalette
        palette[zeroBasedInstrumentIndex + 1] = PlaybackInstrument(
            index: instrument.index,
            name: instrument.name,
            samples: samples,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            noteSampleMap: instrument.noteSampleMap
        )
        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: palette,
            patterns: patterns
        )
        return true
    }

    @discardableResult
    mutating func setSamplePanning(instrumentAt zeroBasedInstrumentIndex: Int, sampleAt zeroBasedSampleIndex: Int, panning: UInt8) -> Bool {
        guard (0..<255).contains(zeroBasedInstrumentIndex),
              (0..<255).contains(zeroBasedSampleIndex),
              let instrument = instrumentPalette[zeroBasedInstrumentIndex + 1],
              let sampleStorageIndex = instrument.samples.firstIndex(where: {
                  $0.sampleIndex == zeroBasedSampleIndex && $0.sampleLength > 0 && !$0.pcm.isEmpty
              }),
              instrument.samples[sampleStorageIndex].panning != panning else {
            return false
        }

        var samples = instrument.samples
        samples[sampleStorageIndex] = samples[sampleStorageIndex].withPanning(panning)
        var palette = instrumentPalette
        palette[zeroBasedInstrumentIndex + 1] = PlaybackInstrument(
            index: instrument.index,
            name: instrument.name,
            samples: samples,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            noteSampleMap: instrument.noteSampleMap
        )
        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: palette,
            patterns: patterns
        )
        return true
    }

    mutating func enterNote(
        trackerKey: Character,
        octave: Int,
        row: Int,
        channel: Int,
        patternIndex: Int? = nil
    ) -> Bool {
        let targetPatternIndex = patternIndex ?? currentPatternIndex
        guard let storageIndex = patterns.firstIndex(where: { $0.index == targetPatternIndex }),
              patterns[storageIndex].rows.indices.contains(row),
              patterns[storageIndex].rows[row].indices.contains(channel),
              let note = TrackerNoteKeyMap.noteValue(forTrackerKey: trackerKey, octave: octave) else {
            return false
        }

        setNoteValue(
            note,
            instrument: selectedInstrumentForNoteEntry(),
            row: row,
            channel: channel,
            storageIndex: storageIndex
        )
        return true
    }

    mutating func enterKeyOff(row: Int, channel: Int, patternIndex: Int? = nil) -> Bool {
        let targetPatternIndex = patternIndex ?? currentPatternIndex
        guard let storageIndex = patterns.firstIndex(where: { $0.index == targetPatternIndex }),
              patterns[storageIndex].rows.indices.contains(row),
              patterns[storageIndex].rows[row].indices.contains(channel) else {
            return false
        }

        setNoteValue(
            TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 0,
            row: row,
            channel: channel,
            storageIndex: storageIndex
        )
        return true
    }

    mutating func clearNote(row: Int, channel: Int, patternIndex: Int? = nil) -> Bool {
        clearField(.note, row: row, channel: channel, patternIndex: patternIndex)
    }

    mutating func clearField(_ field: EditablePatternCellField, row: Int, channel: Int, patternIndex: Int? = nil) -> Bool {
        let targetPatternIndex = patternIndex ?? currentPatternIndex
        guard let storageIndex = patterns.firstIndex(where: { $0.index == targetPatternIndex }),
              patterns[storageIndex].rows.indices.contains(row),
              patterns[storageIndex].rows[row].indices.contains(channel) else {
            return false
        }

        let cell = patterns[storageIndex].rows[row][channel]
        patterns[storageIndex].rows[row][channel] = cell.clearing(field)
        return true
    }

    mutating func clearCurrentPattern(patternIndex: Int? = nil) -> Bool {
        let targetPatternIndex = patternIndex ?? currentPatternIndex
        guard let storageIndex = patterns.firstIndex(where: { $0.index == targetPatternIndex }) else {
            return false
        }

        let pattern = patterns[storageIndex]
        patterns[storageIndex] = Self.makeEmptyPattern(
            index: pattern.index,
            rowCount: pattern.rowCount,
            channels: pattern.channels
        )
        return true
    }

    mutating func duplicateCurrentPatternForEditing(patternIndex: Int? = nil) -> Bool {
        let targetPatternIndex = patternIndex ?? currentPatternIndex
        guard let sourcePattern = pattern(for: targetPatternIndex),
              let newPatternIndex = nextUnusedPatternIndex() else {
            return false
        }

        let duplicatedPattern = XMPatternData(
            index: newPatternIndex,
            rowCount: sourcePattern.rowCount,
            channels: sourcePattern.channels,
            rows: sourcePattern.rows
        )
        var updatedPatterns = patterns
        updatedPatterns.append(duplicatedPattern)
        updatedPatterns.sort { $0.index < $1.index }

        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: newPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: instrumentPalette,
            patterns: updatedPatterns
        )
        return true
    }

    mutating func assignPatternToSelectedOrder(_ patternIndex: Int) -> Bool {
        guard pattern(for: patternIndex) != nil else {
            return false
        }
        let effectiveOrderCount = min(max(0, songLength), orderTable.count)
        guard currentPosition >= 0,
              currentPosition < effectiveOrderCount else {
            return false
        }

        var updatedOrderTable = orderTable
        updatedOrderTable[currentPosition] = patternIndex
        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: patternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: updatedOrderTable,
            selection: selection,
            instrumentPalette: instrumentPalette,
            patterns: patterns
        )
        return true
    }

    mutating func stepSelectedOrderPattern(delta: Int) -> Bool {
        guard delta != 0 else {
            return false
        }
        let effectiveOrderCount = min(max(0, songLength), orderTable.count)
        guard currentPosition >= 0,
              currentPosition < effectiveOrderCount else {
            return false
        }
        let selectedPatternIndex = orderTable[currentPosition]
        let allocatedPatternIndices = Array(Set(patterns.map(\.index))).sorted()
        guard allocatedPatternIndices.contains(selectedPatternIndex) else {
            return false
        }

        let targetPatternIndex: Int?
        if delta < 0 {
            targetPatternIndex = allocatedPatternIndices.last { $0 < selectedPatternIndex }
        } else {
            targetPatternIndex = allocatedPatternIndices.first { $0 > selectedPatternIndex }
        }
        guard let targetPatternIndex else {
            return false
        }
        return assignPatternToSelectedOrder(targetPatternIndex)
    }

    mutating func createBlankPatternAndSelectForEditing() -> Bool {
        guard let newPatternIndex = nextUnusedPatternIndex() else {
            return false
        }

        let sourcePattern = pattern
        let newPattern = Self.makeEmptyPattern(
            index: newPatternIndex,
            rowCount: sourcePattern.rowCount,
            channels: sourcePattern.channels
        )
        var updatedPatterns = patterns
        updatedPatterns.append(newPattern)
        updatedPatterns.sort { $0.index < $1.index }

        self = BlankTrackerDocument(
            title: title,
            songLength: songLength,
            currentPosition: currentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: newPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: instrumentPalette,
            patterns: updatedPatterns
        )
        return true
    }

    mutating func insertOrderAfterSelected() -> Bool {
        let effectiveOrderTable = Array(orderTable.prefix(min(max(0, songLength), orderTable.count)))
        guard effectiveOrderTable.indices.contains(currentPosition),
              let patternIndex = safeExistingPatternIndex(preferredPatternIndex: effectiveOrderTable[currentPosition]) else {
            return false
        }

        var updatedOrderTable = effectiveOrderTable
        let insertedPosition = currentPosition + 1
        updatedOrderTable.insert(patternIndex, at: insertedPosition)
        replaceOrderState(orderTable: updatedOrderTable, currentPosition: insertedPosition, currentPatternIndex: patternIndex)
        return true
    }

    mutating func duplicateSelectedOrder() -> Bool {
        let effectiveOrderTable = Array(orderTable.prefix(min(max(0, songLength), orderTable.count)))
        guard effectiveOrderTable.indices.contains(currentPosition) else {
            return false
        }
        let patternIndex = effectiveOrderTable[currentPosition]
        guard pattern(for: patternIndex) != nil else {
            return false
        }

        var updatedOrderTable = effectiveOrderTable
        let duplicatedPosition = currentPosition + 1
        updatedOrderTable.insert(patternIndex, at: duplicatedPosition)
        replaceOrderState(orderTable: updatedOrderTable, currentPosition: duplicatedPosition, currentPatternIndex: patternIndex)
        return true
    }

    mutating func moveSelectedOrderUp() -> Bool {
        let effectiveOrderTable = Array(orderTable.prefix(min(max(0, songLength), orderTable.count)))
        guard effectiveOrderTable.indices.contains(currentPosition),
              currentPosition > 0 else {
            return false
        }
        let patternIndex = effectiveOrderTable[currentPosition]
        guard pattern(for: patternIndex) != nil else {
            return false
        }

        var updatedOrderTable = effectiveOrderTable
        let movedPosition = currentPosition - 1
        updatedOrderTable.swapAt(currentPosition, movedPosition)
        replaceOrderState(orderTable: updatedOrderTable, currentPosition: movedPosition, currentPatternIndex: patternIndex)
        return true
    }

    mutating func moveSelectedOrderDown() -> Bool {
        let effectiveOrderTable = Array(orderTable.prefix(min(max(0, songLength), orderTable.count)))
        guard effectiveOrderTable.indices.contains(currentPosition),
              currentPosition < effectiveOrderTable.count - 1 else {
            return false
        }
        let patternIndex = effectiveOrderTable[currentPosition]
        guard pattern(for: patternIndex) != nil else {
            return false
        }

        var updatedOrderTable = effectiveOrderTable
        let movedPosition = currentPosition + 1
        updatedOrderTable.swapAt(currentPosition, movedPosition)
        replaceOrderState(orderTable: updatedOrderTable, currentPosition: movedPosition, currentPatternIndex: patternIndex)
        return true
    }

    mutating func deleteSelectedOrder() -> Bool {
        let effectiveOrderTable = Array(orderTable.prefix(min(max(0, songLength), orderTable.count)))
        guard effectiveOrderTable.indices.contains(currentPosition) else {
            return false
        }

        guard effectiveOrderTable.count > 1 else {
            guard let patternIndex = safeExistingPatternIndex(preferredPatternIndex: effectiveOrderTable.first) else {
                return false
            }
            guard songLength != 1 ||
                orderTable != [patternIndex] ||
                currentPosition != 0 ||
                currentPatternIndex != patternIndex else {
                return false
            }
            replaceOrderState(orderTable: [patternIndex], currentPosition: 0, currentPatternIndex: patternIndex)
            return true
        }

        var updatedOrderTable = effectiveOrderTable
        updatedOrderTable.remove(at: currentPosition)
        let selectedPosition = min(currentPosition, updatedOrderTable.count - 1)
        guard let patternIndex = safeExistingPatternIndex(preferredPatternIndex: updatedOrderTable[selectedPosition]) else {
            return false
        }
        replaceOrderState(orderTable: updatedOrderTable, currentPosition: selectedPosition, currentPatternIndex: patternIndex)
        return true
    }

    mutating func clearSongData() {
        let currentPattern = pattern
        let blankPattern = Self.makeEmptyPattern(
            index: Self.defaultPatternIndex,
            rowCount: currentPattern.rowCount,
            channels: currentPattern.channels
        )
        self = BlankTrackerDocument(
            title: title,
            songLength: Self.defaultSongLength,
            currentPosition: Self.defaultCurrentPosition,
            restartPosition: restartPosition,
            currentPatternIndex: Self.defaultPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: [Self.defaultPatternIndex],
            selection: selection,
            instrumentPalette: instrumentPalette,
            patterns: [blankPattern]
        )
    }

    private func safeExistingPatternIndex(preferredPatternIndex: Int?) -> Int? {
        let existingPatternIndices = Set(patterns.map(\.index))
        for candidate in [preferredPatternIndex, currentPatternIndex, Self.defaultPatternIndex].compactMap(\.self)
            where existingPatternIndices.contains(candidate) {
            return candidate
        }
        return existingPatternIndices.sorted().first
    }

    private mutating func replaceOrderState(orderTable updatedOrderTable: [Int], currentPosition updatedPosition: Int, currentPatternIndex patternIndex: Int) {
        self = BlankTrackerDocument(
            title: title,
            songLength: updatedOrderTable.count,
            currentPosition: updatedPosition,
            restartPosition: restartPosition,
            currentPatternIndex: patternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: updatedOrderTable,
            selection: selection,
            instrumentPalette: instrumentPalette,
            patterns: patterns
        )
    }

    private func nextUnusedPatternIndex() -> Int? {
        let existingPatternIndices = Set(patterns.map(\.index).filter { $0 >= 0 })
        guard let highestPatternIndex = existingPatternIndices.max() else {
            return Self.defaultPatternIndex
        }
        guard highestPatternIndex < Int.max else {
            return nil
        }
        var candidate = highestPatternIndex + 1
        while existingPatternIndices.contains(candidate) {
            guard candidate < Int.max else {
                return nil
            }
            candidate += 1
        }
        return candidate
    }

    private var selectedInstrumentDisplay: ControlPanelSlotDisplay {
        ControlPanelSlotDisplay.instrument(
            slot: selection.selectedInstrument,
            name: instrument(forInstrument: selection.selectedInstrument)?.name
        )
    }

    private var selectedSampleDisplay: ControlPanelSlotDisplay {
        ControlPanelSlotDisplay.sample(
            slot: selection.selectedSample,
            name: instrument(forInstrument: selection.selectedInstrument)?
                .sample(selectedSampleSlot: selection.selectedSample)?
                .name
        )
    }

    private static func hasUsableInstrumentSamplePalette(_ palette: [Int: PlaybackInstrument]) -> Bool {
        palette.values.contains { instrument in
            instrument.samples.contains { !$0.pcm.isEmpty }
        }
    }

    private static func copiedEditablePatterns(from metadata: ParsedModuleMetadata) -> [XMPatternData]? {
        guard metadata.type == "XM" else {
            return nil
        }
        let channelCount = max(1, metadata.channels)
        let sourcePatterns = metadata.xmPatterns.sorted { $0.index < $1.index }
        guard !sourcePatterns.isEmpty else {
            return nil
        }

        let copiedPatterns = sourcePatterns.map { sourcePattern in
            let rows = (0..<max(1, sourcePattern.rowCount)).map { rowIndex -> [XMPatternEventCell] in
                let sourceRow = sourcePattern.rows.indices.contains(rowIndex) ? sourcePattern.rows[rowIndex] : []
                return (0..<channelCount).map { channelIndex in
                    sourceRow.indices.contains(channelIndex) ? sourceRow[channelIndex] : .empty
                }
            }
            return XMPatternData(
                index: max(0, sourcePattern.index),
                rowCount: rows.count,
                channels: channelCount,
                rows: rows
            )
        }
        return copiedPatterns
    }

    private static func copiedOrderTable(from metadata: ParsedModuleMetadata, availablePatterns: [XMPatternData]) -> [Int] {
        let availablePatternIndices = Set(availablePatterns.map(\.index))
        let effectiveOrderTable = metadata.orderTable
            .prefix(max(0, metadata.songLength))
            .filter { availablePatternIndices.contains($0) }
        if !effectiveOrderTable.isEmpty {
            return Array(effectiveOrderTable)
        }
        return [availablePatterns.sorted { $0.index < $1.index }[0].index]
    }

    private static func clampedRestartPosition(_ restartPosition: Int, songLength: Int) -> Int {
        guard songLength > 0 else {
            return defaultRestartPosition
        }
        return min(max(0, restartPosition), songLength - 1)
    }

    private static func sourceOrderPosition(for sourcePatternIndex: Int, in orderTable: [Int]) -> Int {
        orderTable.firstIndex(of: sourcePatternIndex) ?? defaultCurrentPosition
    }

    private static func clampedSelection(
        _ selection: TrackerEditorSelection,
        instrumentPalette: [Int: PlaybackInstrument]
    ) -> TrackerEditorSelection {
        if let instrument = instrumentPalette[selection.selectedInstrument] {
            return selection.clampedToAvailableSampleSlots(instrument.availableSampleSlots)
        }
        guard let firstInstrument = instrumentPalette.values
            .filter({ !$0.availableSampleSlots.isEmpty })
            .sorted(by: { $0.index < $1.index })
            .first else {
            return selection
        }
        return TrackerEditorSelection(
            selectedInstrument: firstInstrument.index,
            selectedSample: firstInstrument.availableSampleSlots[0]
        )
    }

    private func selectedInstrumentForNoteEntry() -> UInt8? {
        guard selection.selectedInstrument > 0,
              selection.selectedInstrument <= Int(UInt8.max),
              instrument(forInstrument: selection.selectedInstrument) != nil else {
            return nil
        }
        return UInt8(selection.selectedInstrument)
    }

    private mutating func setNoteValue(
        _ note: UInt8,
        instrument: UInt8? = nil,
        row: Int,
        channel: Int,
        storageIndex: Int
    ) {
        let cell = patterns[storageIndex].rows[row][channel]
        patterns[storageIndex].rows[row][channel] = XMPatternEventCell(
            note: note,
            instrument: instrument ?? cell.instrument,
            volumeColumn: cell.volumeColumn,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
    }

    private mutating func replacePattern(_ newValue: XMPatternData) {
        if let storageIndex = patterns.firstIndex(where: { $0.index == newValue.index }) {
            patterns[storageIndex] = newValue
        } else {
            patterns.append(newValue)
            patterns.sort { $0.index < $1.index }
        }
    }
}

private extension XMPatternEventCell {
    func clearing(_ field: EditablePatternCellField) -> XMPatternEventCell {
        switch field {
        case .note:
            return XMPatternEventCell(note: 0, instrument: 0, volumeColumn: volumeColumn, effectType: effectType, effectParam: effectParam)
        case .instrument:
            return XMPatternEventCell(note: note, instrument: 0, volumeColumn: volumeColumn, effectType: effectType, effectParam: effectParam)
        case .volume:
            return XMPatternEventCell(note: note, instrument: instrument, volumeColumn: 0, effectType: effectType, effectParam: effectParam)
        case .effectType:
            return XMPatternEventCell(note: note, instrument: instrument, volumeColumn: volumeColumn, effectType: 0, effectParam: effectParam)
        case .effectParam:
            return XMPatternEventCell(note: note, instrument: instrument, volumeColumn: volumeColumn, effectType: effectType, effectParam: 0)
        }
    }
}

enum EditablePlaybackSongBuilder {
    static func build(
        from document: BlankTrackerDocument,
        endBehavior: PlaybackEndBehavior = .stopAtEnd
    ) -> PlaybackSong {
        let sourcePatterns = document.patterns.isEmpty ? [document.pattern] : document.patterns
        let patterns = sourcePatterns.reduce(into: [Int: PlaybackPattern]()) { result, pattern in
            result[pattern.index] = playbackPattern(from: pattern)
        }
        let currentPatternIndex = document.currentPatternIndex
        let fallbackPatternIndex = patterns[currentPatternIndex] != nil
            ? currentPatternIndex
            : patterns.keys.sorted().first ?? BlankTrackerDocument.defaultPatternIndex
        let orderPatternIndices = document.orderTable
            .prefix(max(0, document.songLength))
            .filter { patterns[$0] != nil }
        let playableOrderPatternIndices = orderPatternIndices.isEmpty ? [fallbackPatternIndex] : Array(orderPatternIndices)
        let orders = playableOrderPatternIndices.enumerated().map { orderIndex, patternIndex in
            PlaybackOrderEntry(orderIndex: orderIndex, patternIndex: patternIndex)
        }
        let restartOrderIndex = orders.isEmpty
            ? 0
            : min(max(0, document.restartPosition), orders.count - 1)

        return PlaybackSong(
            title: document.title,
            orders: orders,
            patternsByIndex: patterns,
            instrumentsByIndex: document.instrumentPalette,
            restartOrderIndex: restartOrderIndex,
            endBehavior: endBehavior,
            initialTiming: PlaybackTiming(
                speed: document.speed > 0 ? document.speed : PlaybackTiming.xmDefault.speed,
                bpm: document.tempo > 0 ? document.tempo : PlaybackTiming.xmDefault.bpm
            ),
            usesLinearFrequencyTable: true
        )
    }

    private static func playbackPattern(from pattern: XMPatternData) -> PlaybackPattern {
        let rowCount = max(0, pattern.rowCount)
        let widestSourceRow = pattern.rows.map(\.count).max() ?? 0
        let channelCount = max(0, pattern.channels, widestSourceRow)
        let rows = (0..<rowCount).map { rowIndex in
            PlaybackRow(
                index: rowIndex,
                cells: playbackCells(
                    sourceCells: pattern.rows.indices.contains(rowIndex) ? pattern.rows[rowIndex] : [],
                    channelCount: channelCount
                )
            )
        }
        return PlaybackPattern(index: pattern.index, rows: rows)
    }

    private static func playbackCells(sourceCells: [XMPatternEventCell], channelCount: Int) -> [PlaybackCell] {
        (0..<channelCount).map { channelIndex in
            let cell = sourceCells.indices.contains(channelIndex) ? sourceCells[channelIndex] : .empty
            return PlaybackCell(
                note: cell.note,
                instrument: cell.instrument,
                volumeColumn: cell.volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam
            )
        }
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
    let selectedInstrumentTooltip: String
    let selectedSampleDisplay: String
    let selectedSampleTooltip: String
    let tempo: String
    let speed: String
    let songPositionValue: Int
    let maximumSongPosition: Int
    let isSongPositionEnabled: Bool
    let isPatternControlsEnabled: Bool
    let areInstrumentPlaceholdersEnabled: Bool
}
