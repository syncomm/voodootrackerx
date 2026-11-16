import Foundation

struct ControlPanelContent: Equatable {
    static let unavailableSongTime = "--:--"

    var songTitle = BlankTrackerDocument.defaultTitle
    var songTime = ControlPanelContent.unavailableSongTime
    var songTimeTooltip = "Total song duration"
    var songLength = "01"
    var songPosition = "00"
    var restartPosition = "00"
    var patternRowCount = "64"
    var channelCount = "8"
    var selectedInstrumentDisplay = TrackerEditorSelection.default.instrumentDisplayTitle
    var selectedInstrumentTooltip = TrackerEditorSelection.default.instrumentDisplayTitle
    var selectedSampleDisplay = TrackerEditorSelection.default.sampleDisplayTitle
    var selectedSampleTooltip = TrackerEditorSelection.default.sampleDisplayTitle
    var tempo = "125"
    var speed = "06"
    var selectedOctave = 4
    var songPositionValue = 0
    var maximumSongPosition = 0
    var isLoopEnabled = false
    var isEditModeEnabled = false
    var isPlaybackActive = false
    var isPlaybackPreparing = false
    var isSongPositionEnabled = false
    var isPatternControlsEnabled = false
    var areInstrumentPlaceholdersEnabled = false
}

/// Document metadata only: never prepares audio or observes the transport clock.
@MainActor
final class SongDurationDisplayModel {
    typealias Calculation = @Sendable (PlaybackSong, @Sendable () -> Bool) -> TimeInterval?

    var didChange: (() -> Void)?
    private(set) var durationSeconds: TimeInterval?
    private(set) var isPending = false
    private(set) var generation: UInt64 = 0
    private var identity: UUID?
    private var editableInput: BlankTrackerDocument?
    private var cancellation: PlaybackPreparationCancellation?
    private let queue = DispatchQueue(label: "com.syncomm.VoodooTrackerX.song-duration", qos: .utility)
    private let calculate: Calculation

    init(calculate: @escaping Calculation = { PlaybackSongDuration.seconds(for: $0, isCancelled: $1) }) {
        self.calculate = calculate
    }

    deinit { cancellation?.cancel() }

    var tooltip: String {
        if isPending { return "Calculating total song duration" }
        return durationSeconds == nil
            ? "Total duration unavailable: no playable song, invalid traversal, or cyclic/guarded flow"
            : "Total song duration from the beginning, excluding the playback tail"
    }

    /// Replaces the document immediately, dropping its old value before asynchronous work.
    func load(song: PlaybackSong?, identity: UUID?) {
        self.identity = identity
        editableInput = nil
        guard let song else { schedule(nil); return }
        // Retain timing/flow cells, never sample payloads or a mixer event graph.
        let input = PlaybackSong(title: "", orders: song.orders, patternsByIndex: song.patternsByIndex,
            instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: song.endBehavior,
            initialTiming: song.initialTiming, usesLinearFrequencyTable: song.usesLinearFrequencyTable)
        schedule { input }
    }

    /// CoW timing values ignore focus, navigation, sample content and one-pass restart metadata.
    /// The shared editable builder converts cells on the worker, not on Main.
    func update(document: BlankTrackerDocument?, identity: UUID?) {
        guard let document else { load(song: nil, identity: nil); return }
        let input = BlankTrackerDocument(title: "", songLength: document.songLength,
            currentPosition: 0, restartPosition: 0,
            currentPatternIndex: document.orderTable.first ?? BlankTrackerDocument.defaultPatternIndex,
            tempo: document.tempo, speed: document.speed, orderTable: document.orderTable,
            selection: .default, instrumentPalette: [:], patterns: document.patterns)
        guard self.identity != identity || editableInput != input else { return }
        self.identity = identity
        editableInput = input
        schedule {
            let orders = input.orderTable.prefix(max(0, input.songLength))
            let patterns = Set(input.patterns.map(\.index))
            guard !orders.isEmpty, orders.count == input.songLength,
                  orders.allSatisfy({ patterns.contains($0) }) else { return nil }
            return EditablePlaybackSongBuilder.build(from: input)
        }
    }

    private func schedule(_ build: (@Sendable () -> PlaybackSong?)?) {
        cancellation?.cancel()
        let token = PlaybackPreparationCancellation()
        cancellation = token
        generation &+= 1
        durationSeconds = nil
        isPending = build != nil
        // Document setters may still be updating selection/playback ownership.
        // Publish after that transaction, and never revive a superseded value.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.cancellation === token, !token.isCancelled else { return }
            self.didChange?()
        }
        guard let build else { return }
        let calculate = calculate
        queue.async { [weak self] in
            guard !token.isCancelled else { return }
            let song = build()
            guard !token.isCancelled else { return }
            let seconds = song.flatMap { calculate($0, { token.isCancelled }) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.cancellation === token, !token.isCancelled else { return }
                self.durationSeconds = seconds
                self.isPending = false
                self.didChange?()
            }
        }
    }
}

struct ControlPanelSlotDisplay: Equatable {
    static let maximumDisplayNameLength = 12

    let code: String
    let name: String?

    static func instrument(slot: Int, name: String? = nil) -> ControlPanelSlotDisplay {
        ControlPanelSlotDisplay(code: String(format: "I%02X", clampedSlot(slot)), name: name)
    }

    static func sample(slot: Int, name: String? = nil) -> ControlPanelSlotDisplay {
        ControlPanelSlotDisplay(code: String(format: "S%02X", clampedSlot(slot)), name: name)
    }

    static func sample(row: SampleSlotPresentationRow) -> ControlPanelSlotDisplay {
        switch row.state {
        case let .represented(representedSample):
            let trimmedName = representedSample.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return sample(
                slot: row.sampleSlot,
                name: trimmedName.isEmpty ? "(unnamed sample)" : trimmedName
            )
        case .emptyDestination:
            return sample(slot: row.sampleSlot, name: "Empty destination")
        }
    }

    var displayTitle: String {
        guard let name = normalizedName else {
            return code
        }
        // Instruments use the recovered row space; native popup drawing elides at narrow widths.
        return "\(code) \(code.hasPrefix("I") ? name : Self.truncated(name, maximumLength: Self.maximumDisplayNameLength))"
    }

    var tooltip: String {
        guard let name = normalizedName else {
            return code
        }
        return "\(code) \(name)"
    }

    private var normalizedName: String? {
        guard let name else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncated(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength, maximumLength > 3 else {
            return value
        }
        return String(value.prefix(maximumLength - 3)) + "..."
    }

    private static func clampedSlot(_ slot: Int) -> Int {
        min(255, max(1, slot))
    }
}

enum ControlPanelDisplayState {
    static func patternDisplayTitle(patternIndex: Int) -> String {
        String(format: "%03ld", max(0, patternIndex))
    }

    static func songTimeDisplay(durationSeconds: TimeInterval?) -> String {
        guard let durationSeconds,
              durationSeconds.isFinite,
              durationSeconds >= 0,
              durationSeconds < Double(Int.max) else {
            return ControlPanelContent.unavailableSongTime
        }
        let wholeSeconds = Int(durationSeconds.rounded())
        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func blankDocumentContent(
        for document: BlankTrackerDocument,
        selectedSongPositionIndex: Int,
        selectedOctave: Int,
        isLoopEnabled: Bool,
        isEditModeEnabled: Bool,
        isPlaybackActive: Bool
    ) -> ControlPanelContent {
        let metadata = document.controlPanelMetadata
        let displayedSongPosition = isPlaybackActive
            ? selectedSongPositionIndex
            : metadata.songPositionValue
        var content = ControlPanelContent()
        content.songTitle = metadata.songTitle
        content.songLength = metadata.songLength
        content.songPosition = twoDigit(displayedSongPosition)
        content.restartPosition = metadata.restartPosition
        content.patternRowCount = metadata.patternRowCount
        content.channelCount = metadata.channelCount
        content.selectedInstrumentDisplay = metadata.selectedInstrumentDisplay
        content.selectedInstrumentTooltip = metadata.selectedInstrumentTooltip
        content.selectedSampleDisplay = metadata.selectedSampleDisplay
        content.selectedSampleTooltip = metadata.selectedSampleTooltip
        content.tempo = metadata.tempo
        content.speed = metadata.speed
        content.selectedOctave = selectedOctave
        content.songPositionValue = displayedSongPosition
        content.maximumSongPosition = metadata.maximumSongPosition
        content.isLoopEnabled = isLoopEnabled
        content.isEditModeEnabled = isEditModeEnabled
        content.isPlaybackActive = isPlaybackActive
        content.isSongPositionEnabled = metadata.isSongPositionEnabled
        content.isPatternControlsEnabled = metadata.isPatternControlsEnabled
        content.areInstrumentPlaceholdersEnabled = metadata.areInstrumentPlaceholdersEnabled
        return content
    }

    static func loadedModuleContent(
        metadata: ParsedModuleMetadata,
        selection: TrackerEditorSelection = .default,
        selectedSongPositionIndex: Int,
        currentPatternIndex: Int,
        selectedOctave: Int,
        isLoopEnabled: Bool,
        isEditModeEnabled: Bool,
        isPlaybackActive: Bool,
        songTime: String = ControlPanelContent.unavailableSongTime,
        selectedInstrumentName: String? = nil,
        selectedSampleName: String? = nil
    ) -> ControlPanelContent {
        var content = ControlPanelContent()
        content.songTitle = titleDisplay(from: metadata.title)
        content.songTime = songTime
        content.songLength = twoDigit(metadata.songLength)
        content.songPosition = twoDigit(selectedSongPositionIndex)
        content.restartPosition = twoDigit(metadata.restartPosition)
        content.tempo = "\(metadata.defaultBPM)"
        content.speed = twoDigit(metadata.defaultTempo)
        content.selectedOctave = selectedOctave
        content.songPositionValue = selectedSongPositionIndex
        content.maximumSongPosition = max(0, metadata.songLength - 1)
        content.isLoopEnabled = isLoopEnabled
        content.isEditModeEnabled = isEditModeEnabled
        content.isPlaybackActive = isPlaybackActive
        content.isSongPositionEnabled = metadata.songLength > 0

        if let pattern = metadata.xmPattern(index: currentPatternIndex) {
            content.patternRowCount = "\(pattern.rowCount)"
            content.channelCount = "\(pattern.channels)"
            content.isPatternControlsEnabled = true
            content.areInstrumentPlaceholdersEnabled = metadata.instruments > 0
            if metadata.instruments > 0 {
                let instrument = ControlPanelSlotDisplay.instrument(
                    slot: selection.selectedInstrument,
                    name: selectedInstrumentName
                )
                let sample = ControlPanelSlotDisplay.sample(
                    slot: selection.selectedSample,
                    name: selectedSampleName
                )
                content.selectedInstrumentDisplay = instrument.displayTitle
                content.selectedInstrumentTooltip = instrument.tooltip
                content.selectedSampleDisplay = sample.displayTitle
                content.selectedSampleTooltip = sample.tooltip
            } else {
                content.selectedInstrumentDisplay = "No Inst"
                content.selectedInstrumentTooltip = "No instrument slots"
                content.selectedSampleDisplay = "No Sample"
                content.selectedSampleTooltip = "No sample slots"
            }
        } else {
            content.patternRowCount = "--"
            content.channelCount = twoDigit(metadata.channels)
            content.isPatternControlsEnabled = false
            content.areInstrumentPlaceholdersEnabled = false
            content.selectedInstrumentDisplay = "No Inst"
            content.selectedInstrumentTooltip = "No instrument slots"
            content.selectedSampleDisplay = "No Sample"
            content.selectedSampleTooltip = "No sample slots"
        }

        return content
    }

    private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private static func titleDisplay(from rawTitle: String) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "(empty title)"
        }
        return trimmedTitle
    }
}
