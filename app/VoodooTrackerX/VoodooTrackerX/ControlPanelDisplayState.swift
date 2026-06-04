import Foundation

struct ControlPanelContent: Equatable {
    var songTitle = BlankTrackerDocument.defaultTitle
    var songLength = "01"
    var songPosition = "00"
    var restartPosition = "00"
    var patternRowCount = "64"
    var channelCount = "8"
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

enum ControlPanelDisplayState {
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
        selectedSongPositionIndex: Int,
        currentPatternIndex: Int,
        selectedOctave: Int,
        isLoopEnabled: Bool,
        isEditModeEnabled: Bool,
        isPlaybackActive: Bool
    ) -> ControlPanelContent {
        var content = ControlPanelContent()
        content.songTitle = metadata.title.isEmpty ? "(empty title)" : metadata.title
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

        if metadata.type == "XM",
           metadata.xmPatterns.indices.contains(currentPatternIndex) {
            let pattern = metadata.xmPatterns[currentPatternIndex]
            content.patternRowCount = "\(pattern.rowCount)"
            content.channelCount = "\(pattern.channels)"
            content.isPatternControlsEnabled = true
            content.areInstrumentPlaceholdersEnabled = metadata.instruments > 0
        } else {
            content.patternRowCount = "--"
            content.channelCount = twoDigit(metadata.channels)
            content.isPatternControlsEnabled = false
            content.areInstrumentPlaceholdersEnabled = false
        }

        return content
    }

    private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
