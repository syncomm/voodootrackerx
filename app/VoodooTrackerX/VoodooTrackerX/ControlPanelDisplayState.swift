import Foundation

struct ControlPanelContent: Equatable {
    static let unavailableSongTime = "--:--"

    var songTitle = BlankTrackerDocument.defaultTitle
    var songTime = ControlPanelContent.unavailableSongTime
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
    var isSongPositionEnabled = false
    var isPatternControlsEnabled = false
    var areInstrumentPlaceholdersEnabled = false
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
        return "\(code) \(Self.truncated(name, maximumLength: Self.maximumDisplayNameLength))"
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
        String(format: "%03d", max(0, patternIndex))
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
        selectedOctave: Int,
        isLoopEnabled: Bool,
        isEditModeEnabled: Bool,
        isPlaybackActive: Bool
    ) -> ControlPanelContent {
        let metadata = document.controlPanelMetadata
        var content = ControlPanelContent()
        content.songTitle = metadata.songTitle
        content.songLength = metadata.songLength
        content.songPosition = metadata.songPosition
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
        content.songPositionValue = metadata.songPositionValue
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
