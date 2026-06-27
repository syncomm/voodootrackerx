// Owns app lifecycle, menu/setup, module loading, and top-level coordination between state and the main window.
// It intentionally does not build the window hierarchy directly, but it still owns tracker state/render coordination for now.
import AppKit
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private static var retainedDelegate: AppDelegate?
    private var windowController: TrackerWindowController?
    private var blankDocument: BlankTrackerDocument?
    private var loadedMetadata: ParsedModuleMetadata?
    private var displayedPatternEntries = [ModuleMetadataLoader.PatternSelectionEntry]()
    private var invalidReferencedPatternIndices = [Int]()
    private var selectedPatternSelectionIndex = 0
    private var selectedSongPositionIndex = 0
    private var currentPatternIndex = 0
    private var loadedModuleSelection = TrackerEditorSelection.default
    private var cursor = PatternCursor(row: 0, channel: 0, field: .note)
    private var visibleGridRangesByRow = [Int: NSRange]()
    private var currentViewportState: PatternViewportState?
    private var currentViewportLayout: PatternViewportTextLayout?
    private let theme = TrackerTheme.legacyDark
    private let metadataLoader = ModuleMetadataLoader()
    private let playbackTimingRecorder = PlaybackTimingTraceConfiguration.makeRecorder()
    private let playbackEngine: PlaybackEngine
    private let noteAuditionPreviewer = EditorNoteAuditionPreviewer(sink: EditorNoteAuditionAudioSink())
    private var isSyncingScroll = false
    private var isEditModeEnabled = false
    private var isLoopPlaybackEnabled = false
    private var selectedOctave = 4
    private var lastGridViewportSize = NSSize.zero
    private var lastStableGridHorizontalOrigin: CGFloat = 0
    private var pendingHorizontalViewportOrigin: CGFloat?
    private var isLiveResizingTrackerViewport = false
    private var liveResizeHorizontalOrigin: CGFloat?
    private var debugStopTimer: Timer?
    private var debugAutoplayTimer: Timer?

    private var mainWindow: NSWindow? { windowController?.window }
    private var controlPanelView: ControlPanelView? { windowController?.controlPanelView }
    private var trackerEditorView: TrackerEditorView? { windowController?.trackerEditorView }
    private var metadataTextView: PatternTextView? { trackerEditorView?.metadataTextView }
    private var patternInfoLabel: NSTextField? { trackerEditorView?.patternInfoLabel }
    private var patternHeaderTextView: PatternTextView? { trackerEditorView?.patternHeaderTextView }
    private var patternHeaderScrollView: NSScrollView? { trackerEditorView?.patternHeaderScrollView }
    private var gridScrollView: NSScrollView? { trackerEditorView?.gridScrollView }
    private var trackerDividerUnderlayView: TrackerDividerUnderlayView? { trackerEditorView?.trackerDividerUnderlayView }
    private var trackerChromeOverlayView: TrackerChromeOverlayView? { trackerEditorView?.trackerChromeOverlayView }
    private var patternSelector: NSPopUpButton? { controlPanelView?.patternSelector }
    private var editModeCheckbox: NSButton? { controlPanelView?.editModeButton }
    private var displayedMetadata: ParsedModuleMetadata? { loadedMetadata ?? blankDocument?.metadata }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let runtimeCMixerTraceWriter = RuntimeCMixerTraceConfiguration.makeWriter(environment: environment)
        let runtimeMixerMetricsTraceWriter = RuntimeMixerMetricsTraceConfiguration.makeWriter(environment: environment)
        let adapterPlanProfileRecorder = AdapterPlanProfileConfiguration.makeRecorder(environment: environment)
        let audioOutput = PlaybackAudioOutputFactory.make(
            environment: environment,
            runtimeCMixerTraceWriter: runtimeCMixerTraceWriter,
            runtimeMixerMetricsTraceWriter: runtimeMixerMetricsTraceWriter
        )
        playbackEngine = PlaybackEngine(
            audioEngine: audioOutput,
            runtimeCMixerTraceWriter: runtimeCMixerTraceWriter,
            playbackTimingRecorder: playbackTimingRecorder,
            adapterPlanProfileRecorder: adapterPlanProfileRecorder,
            environment: environment
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        if windowController == nil {
            let controller = TrackerWindowController(theme: theme)
            wireTrackerWindowController(controller)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(gridClipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: controller.trackerEditorView.gridScrollView.contentView
            )
            windowController = controller
            lastGridViewportSize = controller.trackerEditorView.gridScrollView.contentView.bounds.size
            resetToBlankTrackerDocument()
        }
        windowController?.showWindowAndActivate()
        if let metadataTextView {
            mainWindow?.makeFirstResponder(metadataTextView)
        }
        let debugOpenPath = ProcessInfo.processInfo.environment["VTX_OPEN_PATH"] ?? ""
        if !debugOpenPath.isEmpty {
            loadModule(from: URL(fileURLWithPath: debugOpenPath))
            return
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case ApplicationMenuBuilder.Actions.newTrackerDocument,
             ApplicationMenuBuilder.Actions.openModuleFile:
            return true
        case ApplicationMenuBuilder.Actions.play:
            return loadedMetadata != nil && !playbackEngine.state.isPlaying
        case ApplicationMenuBuilder.Actions.stop:
            return playbackEngine.state.isPlaying
        case ApplicationMenuBuilder.Actions.toggleLoop:
            menuItem.state = isLoopPlaybackEnabled ? .on : .off
            return true
        case ApplicationMenuBuilder.Actions.toggleEditMode:
            menuItem.state = isEditModeEnabled ? .on : .off
            return true
        case ApplicationMenuBuilder.Actions.clearCurrentPattern:
            return EditorCommandAvailability.canClearCurrentPattern(
                hasBlankDocument: blankDocument != nil,
                sourceContext: currentEditorNoteAuditionSourceContext()
            )
        case ApplicationMenuBuilder.Actions.clearSongData:
            return EditorCommandAvailability.canClearSongData(
                hasBlankDocument: blankDocument != nil,
                sourceContext: currentEditorNoteAuditionSourceContext(),
                loadedModuleCanMakeEditableCopy: loadedModuleCanMakeEditableCopy()
            )
        case #selector(NSWindow.performClose(_:)):
            return mainWindow != nil
        default:
            return true
        }
    }

    // AppDelegate owns mutable tracker/module state and pushes view updates into the window-controller tree.
    private func wireTrackerWindowController(_ controller: TrackerWindowController) {
        controller.trackerEditorView.metadataTextView.navigationHandler = { [weak self] command in
            self?.handlePatternNavigation(command)
        }
        controller.trackerEditorView.metadataTextView.editInputHandler = { [weak self] input in
            self?.handlePatternEditInput(input) ?? false
        }
        controller.trackerEditorView.metadataTextView.noteKeyReleaseHandler = { [weak self] character in
            self?.handlePatternNoteKeyRelease(character) ?? false
        }
        controller.trackerEditorView.metadataTextView.transportShortcutHandler = { [weak self] in
            self?.handleSpacebarTransportShortcut() ?? false
        }
        controller.trackerEditorView.metadataTextView.wheelNavigationHandler = { [weak self] deltaY in
            self?.handlePatternWheel(deltaY: deltaY)
        }

        controller.controlPanelView.playButton.target = self
        controller.controlPanelView.playButton.action = #selector(playPressed(_:))
        controller.controlPanelView.stopButton.target = self
        controller.controlPanelView.stopButton.action = #selector(stopPressed(_:))
        controller.controlPanelView.loopButton.target = self
        controller.controlPanelView.loopButton.action = #selector(loopToggled(_:))
        controller.controlPanelView.editModeButton.target = self
        controller.controlPanelView.editModeButton.action = #selector(editModeToggled(_:))
        controller.controlPanelView.patternSelector.target = self
        controller.controlPanelView.patternSelector.action = #selector(patternSelectionChanged(_:))
        controller.controlPanelView.instrumentSelector.target = self
        controller.controlPanelView.instrumentSelector.action = #selector(instrumentSelectionChanged(_:))
        controller.controlPanelView.sampleSelector.target = self
        controller.controlPanelView.sampleSelector.action = #selector(sampleSelectionChanged(_:))
        controller.controlPanelView.songPositionStepper.target = self
        controller.controlPanelView.songPositionStepper.action = #selector(currentSongPositionStepperChanged(_:))
        controller.controlPanelView.octaveSelector.target = self
        controller.controlPanelView.octaveSelector.action = #selector(octaveSelectionChanged(_:))

        playbackEngine.positionDidChange = { [weak self] position in
            self?.applyPlaybackPosition(position)
        }
        playbackEngine.playbackDidStop = { [weak self] in
            guard let position = self?.playbackEngine.currentPosition else {
                self?.syncControlPanelView()
                return
            }
            self?.applyPlaybackPosition(position)
        }
        playbackEngine.runtimeAdapterPlanDidUpdate = { [weak self] in
            self?.syncControlPanelView()
        }

        controller.liveResizeWillStartHandler = { [weak self] in
            self?.trackerWindowWillStartLiveResize()
        }
        controller.liveResizeDidEndHandler = { [weak self] in
            self?.trackerWindowDidEndLiveResize()
        }
    }

    private func configureMenu() {
        let builtMenu = ApplicationMenuBuilder.build(target: self)
        NSApp.mainMenu = builtMenu.mainMenu
        NSApp.windowsMenu = builtMenu.windowMenu
    }

    @objc
    private func openModuleFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.message = "Choose a MOD or XM module file"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadModule(from: url)
    }

    @objc
    private func newTrackerDocument(_ sender: Any?) {
        resetToBlankTrackerDocument()
    }

    @objc
    private func clearCurrentPattern(_ sender: Any?) {
        guard var document = blankDocument,
              loadedMetadata == nil,
              EditorCommandAvailability.canClearCurrentPattern(
                  hasBlankDocument: true,
                  sourceContext: document.noteAuditionSourceContext
              ) else {
            return
        }

        guard document.clearCurrentPattern(patternIndex: currentPatternIndex) else {
            return
        }

        blankDocument = document
        renderCurrentPattern(metadata: document.metadata)
        syncControlPanelView()
    }

    @objc
    private func clearSongData(_ sender: Any?) {
        if var document = blankDocument,
           loadedMetadata == nil,
           EditorCommandAvailability.canClearSongData(
               hasBlankDocument: true,
               sourceContext: document.noteAuditionSourceContext
           ) {
            document.clearSongData()
            blankDocument = document
            selectedSongPositionIndex = document.currentPosition
            currentPatternIndex = document.currentPatternIndex
            cursor = .clearSongDataResetPosition
            visibleGridRangesByRow = [:]
            currentViewportState = nil
            currentViewportLayout = nil
            updatePatternSelector(for: document.metadata, keepPattern: document.currentPatternIndex)
            renderCurrentPattern(metadata: document.metadata)
            syncControlPanelView()
            return
        }

        guard let metadata = loadedMetadata,
              let playbackSong = playbackEngine.song,
              EditorCommandAvailability.canClearSongData(
                  hasBlankDocument: false,
                  sourceContext: .loadedModule(patternIndex: currentPatternIndex),
                  loadedModuleCanMakeEditableCopy: loadedModuleCanMakeEditableCopy()
              ),
              let document = BlankTrackerDocument.makeEditableCopyClearingSongData(
                  from: metadata,
                  playbackSong: playbackSong,
                  selection: loadedModuleSelection,
                  sourcePatternIndex: currentPatternIndex
              ) else {
            return
        }

        noteAuditionPreviewer.cancelPreview()
        playbackEngine.load(song: nil)
        blankDocument = document
        loadedMetadata = nil
        loadedModuleSelection = .default
        debugAutoplayTimer?.invalidate()
        debugAutoplayTimer = nil
        debugStopTimer?.invalidate()
        debugStopTimer = nil
        selectedSongPositionIndex = document.currentPosition
        currentPatternIndex = document.currentPatternIndex
        cursor = .clearSongDataResetPosition
        visibleGridRangesByRow = [:]
        currentViewportState = nil
        currentViewportLayout = nil
        updatePatternSelector(for: document.metadata, keepPattern: document.currentPatternIndex)
        renderCurrentPattern(metadata: document.metadata)
        syncControlPanelView()
    }

    private func loadModule(from url: URL) {
        let timingSession = playbackTimingRecorder.beginLifecycle("load")
        var timingMetadata: ParsedModuleMetadata?
        var timingPlaybackSong: PlaybackSong?
        do {
            let metadataStart = timingSession?.beginPhase()
            let metadata = try metadataLoader.load(fromPath: url.path)
            timingMetadata = metadata
            timingSession?.recordPhase(
                "module_metadata_loader_load",
                startedAt: metadataStart,
                fields: PlaybackTimingTraceFields.moduleMetadata(metadata)
            )

            let stateUpdateStart = timingSession?.beginPhase()
            noteAuditionPreviewer.cancelPreview()
            blankDocument = nil
            loadedMetadata = metadata
            timingSession?.recordPhase("app_module_state_update", startedAt: stateUpdateStart)

            let playbackSongBuildStart = timingSession?.beginPhase()
            let playbackSong = try? PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
            timingPlaybackSong = playbackSong
            timingSession?.recordPhase(
                "playback_song_builder_build",
                startedAt: playbackSongBuildStart,
                fields: PlaybackTimingTraceFields.playbackSong(playbackSong, buildSucceeded: playbackSong != nil)
            )

            let engineLoadStart = timingSession?.beginPhase()
            playbackEngine.load(song: playbackSong, timingSession: timingSession)
            timingSession?.recordPhase(
                "playback_engine_load",
                startedAt: engineLoadStart,
                fields: PlaybackTimingTraceFields.playbackSong(playbackSong)
            )

            let selectionResetStart = timingSession?.beginPhase()
            selectedPatternSelectionIndex = 0
            selectedSongPositionIndex = 0
            currentPatternIndex = 0
            loadedModuleSelection = clampedLoadedModuleSelection(.default, song: playbackSong)
            cursor = PatternCursor(row: 0, channel: 0, field: .note)
            isEditModeEnabled = false
            isLoopPlaybackEnabled = false
            editModeCheckbox?.state = .off
            timingSession?.recordPhase("app_selection_reset", startedAt: selectionResetStart)

            let trackerRefreshStart = timingSession?.beginPhase()
            if metadata.type == "XM", !metadata.xmPatterns.isEmpty {
                patternInfoLabel?.isHidden = true
                patternHeaderScrollView?.isHidden = false
                trackerDividerUnderlayView?.isHidden = false
                trackerChromeOverlayView?.isHidden = false
                updatePatternSelector(for: metadata, keepPattern: nil)
                applySongPosition(selectedSongPositionIndex, in: metadata, resetCursor: false)
                renderCurrentPattern(metadata: metadata)
            } else {
                metadataTextView?.activeFieldRange = nil
                metadataTextView?.dividerCharacterIndices = []
                metadataTextView?.dividerTopCharacterIndex = nil
                visibleGridRangesByRow = [:]
                currentViewportState = nil
                currentViewportLayout = nil
                trackerDividerUnderlayView?.isHidden = true
                trackerChromeOverlayView?.viewportState = nil
                trackerChromeOverlayView?.isHidden = true
                patternInfoLabel?.stringValue = ""
                patternInfoLabel?.isHidden = true
                patternHeaderTextView?.string = ""
                patternHeaderTextView?.dividerCharacterIndices = []
                patternSelector?.removeAllItems()
                patternHeaderScrollView?.isHidden = true
                metadataTextView?.string = """
                File: \(url.lastPathComponent)
                Path: \(url.path)

                \(metadata.displayText)
                """
            }
            timingSession?.recordPhase("tracker_ui_refresh", startedAt: trackerRefreshStart)

            let controlPanelStart = timingSession?.beginPhase()
            syncControlPanelView()
            timingSession?.recordPhase("control_panel_sync", startedAt: controlPanelStart)

            finishLoadTimingSession(timingSession, succeeded: true, metadata: timingMetadata, playbackSong: timingPlaybackSong)
            applyDebugLaunchConfigurationIfNeeded()
        } catch {
            finishLoadTimingSession(timingSession, succeeded: false, metadata: timingMetadata, playbackSong: timingPlaybackSong)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to Open Module"
            alert.informativeText = error.localizedDescription
            if let mainWindow {
                alert.beginSheetModal(for: mainWindow)
            } else {
                alert.runModal()
            }
        }
    }

    private func resetToBlankTrackerDocument() {
        noteAuditionPreviewer.cancelPreview()
        let document = BlankTrackerDocument.makeDefault()
        blankDocument = document
        loadedMetadata = nil
        playbackEngine.load(song: nil)
        loadedModuleSelection = .default
        debugAutoplayTimer?.invalidate()
        debugAutoplayTimer = nil
        debugStopTimer?.invalidate()
        debugStopTimer = nil
        displayedPatternEntries = [
            ModuleMetadataLoader.PatternSelectionEntry(
                patternIndex: document.currentPatternIndex,
                isUsed: true,
                rowCount: document.pattern.rowCount
            )
        ]
        invalidReferencedPatternIndices = []
        selectedPatternSelectionIndex = 0
        selectedSongPositionIndex = document.currentPosition
        currentPatternIndex = document.currentPatternIndex
        cursor = PatternCursor(row: 0, channel: 0, field: .note)
        visibleGridRangesByRow = [:]
        currentViewportState = nil
        currentViewportLayout = nil
        isEditModeEnabled = false
        isLoopPlaybackEnabled = false

        patternInfoLabel?.isHidden = true
        patternHeaderScrollView?.isHidden = false
        trackerDividerUnderlayView?.isHidden = false
        trackerChromeOverlayView?.isHidden = false
        patternSelector?.removeAllItems()
        patternSelector?.addItem(withTitle: formattedPatternSelectorTitle(patternIndex: document.currentPatternIndex, rowCount: document.pattern.rowCount))
        patternSelector?.selectItem(at: 0)
        renderCurrentPattern(metadata: document.metadata)
        syncControlPanelView()
    }

    @objc
    private func patternSelectionChanged(_ sender: NSPopUpButton) {
        guard let metadata = displayedMetadata else {
            return
        }
        selectedPatternSelectionIndex = max(0, sender.indexOfSelectedItem)
        guard displayedPatternEntries.indices.contains(selectedPatternSelectionIndex) else {
            return
        }
        currentPatternIndex = displayedPatternEntries[selectedPatternSelectionIndex].patternIndex
        cursor = PatternCursor(row: 0, channel: 0, field: .note)
        renderCurrentPattern(metadata: metadata)
        syncControlPanelView()
    }

    @objc
    private func instrumentSelectionChanged(_ sender: NSPopUpButton) {
        if var document = blankDocument,
           loadedMetadata == nil,
           document.hasInstrumentSamplePalette {
            let selectedInstrument = selectedPopupSlot(sender) ?? sender.indexOfSelectedItem + 1
            document.selectInstrument(selectedInstrument)
            blankDocument = document
            syncControlPanelView()
            return
        }

        guard let metadata = loadedMetadata,
              metadata.type == "XM",
              metadata.instruments > 0 else {
            return
        }

        let selectedInstrument = selectedPopupSlot(sender) ?? min(max(1, sender.indexOfSelectedItem + 1), metadata.instruments)
        let proposedSelection = TrackerEditorSelection(
            selectedInstrument: selectedInstrument,
            selectedSample: loadedModuleSelection.selectedSample
        )
        loadedModuleSelection = clampedLoadedModuleSelection(
            proposedSelection
        )
        syncControlPanelView()
    }

    @objc
    private func sampleSelectionChanged(_ sender: NSPopUpButton) {
        if var document = blankDocument,
           loadedMetadata == nil,
           document.hasInstrumentSamplePalette {
            let selectedSample = selectedPopupSlot(sender) ?? sender.indexOfSelectedItem + 1
            document.selectSample(selectedSample)
            blankDocument = document
            syncControlPanelView()
            return
        }

        guard let metadata = loadedMetadata,
              metadata.type == "XM",
              metadata.instruments > 0 else {
            return
        }

        let selectedSample = selectedPopupSlot(sender) ?? sender.indexOfSelectedItem + 1
        loadedModuleSelection = loadedModuleSelection.withSelectedSample(selectedSample)
        syncControlPanelView()
    }

    @objc
    private func currentSongPositionStepperChanged(_ sender: NSStepper) {
        guard let metadata = displayedMetadata else {
            return
        }
        applySongPosition(sender.integerValue, in: metadata)
        renderCurrentPattern(metadata: metadata)
        syncControlPanelView()
    }

    @objc
    private func editModeToggled(_ sender: Any?) {
        if let button = sender as? NSButton {
            isEditModeEnabled = button.state == .on
        } else {
            isEditModeEnabled.toggle()
        }
        syncControlPanelView()
    }

    @objc
    private func playPressed(_ sender: Any?) {
        let timingSession = playbackTimingRecorder.beginLifecycle("play")
        let context = measuredPlaybackStartContext(timingSession: timingSession)
        let enginePlayStart = timingSession?.beginPhase()
        playbackEngine.play(from: context, loopEnabled: isLoopPlaybackEnabled, timingSession: timingSession)
        timingSession?.recordPhase(
            "app_delegate_play_to_playback_engine_play",
            startedAt: enginePlayStart,
            fields: [PlaybackTimingTraceField("is_playing_after", playbackEngine.state.isPlaying)]
        )
        let controlPanelStart = timingSession?.beginPhase()
        syncControlPanelView()
        timingSession?.recordPhase("control_panel_sync_after_play", startedAt: controlPanelStart)
        finishPlayTimingSession(timingSession, context: context)
    }

    @objc
    private func stopPressed(_ sender: Any?) {
        playbackEngine.stop()
        syncControlPanelView()
    }

    private func handleSpacebarTransportShortcut() -> Bool {
        guard loadedMetadata != nil else {
            return false
        }
        let timingSession = playbackEngine.state.isPlaying ? nil : playbackTimingRecorder.beginLifecycle("play")
        let context = measuredPlaybackStartContext(timingSession: timingSession)
        playbackEngine.togglePlayStop(from: context, loopEnabled: isLoopPlaybackEnabled, timingSession: timingSession)
        syncControlPanelView()
        finishPlayTimingSession(timingSession, context: context)
        return true
    }

    @objc
    private func loopToggled(_ sender: Any?) {
        if let button = sender as? NSButton {
            isLoopPlaybackEnabled = button.state == .on
        } else {
            isLoopPlaybackEnabled.toggle()
        }
        syncControlPanelView()
    }

    @objc
    private func octaveSelectionChanged(_ sender: NSPopUpButton) {
        selectedOctave = max(0, sender.indexOfSelectedItem)
        syncControlPanelView()
    }

    @objc
    private func debugJumpToNextOrder(_ sender: Any?) {
        debugJumpOrder(delta: 1)
    }

    @objc
    private func debugJumpToPreviousOrder(_ sender: Any?) {
        debugJumpOrder(delta: -1)
    }

    @objc
    private func debugRestartCurrentOrder(_ sender: Any?) {
        debugSeekToOrder(currentPlaybackOrderIndex(), rowIndex: 0)
    }

    private func applyDebugLaunchConfigurationIfNeeded() {
        let configuration = PlaybackDebugLaunchConfiguration.parse()
        debugAutoplayTimer?.invalidate()
        debugAutoplayTimer = nil
        guard configuration.autoplay else {
            if let request = configuration.startRequest {
                playbackEngine.seek(to: request, autoplay: false)
            }
            syncControlPanelView()
            return
        }
        guard let delay = configuration.prePlayDelaySeconds,
              delay > 0 else {
            performDebugAutoplay(configuration)
            return
        }
        debugAutoplayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.debugAutoplayTimer = nil
                self.performDebugAutoplay(configuration)
            }
        }
        syncControlPanelView()
    }

    private func performDebugAutoplay(_ configuration: PlaybackDebugLaunchConfiguration) {
        let timingSession = playbackTimingRecorder.beginLifecycle("play")
        if let request = configuration.startRequest {
            playbackEngine.seek(to: request, autoplay: true, timingSession: timingSession)
        } else {
            let context = measuredPlaybackStartContext(timingSession: timingSession)
            playbackEngine.play(from: context, loopEnabled: isLoopPlaybackEnabled, timingSession: timingSession)
        }
        scheduleDebugStop(after: configuration.stopAfterSeconds, replayAfterStop: configuration.replayAfterStop)
        syncControlPanelView()
        finishPlayTimingSession(timingSession, context: currentPlaybackStartContext())
    }

    private func scheduleDebugStop(after seconds: TimeInterval?, replayAfterStop: Bool = false) {
        debugStopTimer?.invalidate()
        debugStopTimer = nil
        guard let seconds else {
            return
        }
        debugStopTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.playbackEngine.stopFromDebugTimer()
                self.syncControlPanelView()
                if replayAfterStop {
                    self.playDebugReplayAfterStop(stopAfterSeconds: seconds)
                }
            }
        }
    }

    private func playDebugReplayAfterStop(stopAfterSeconds seconds: TimeInterval?) {
        let timingSession = playbackTimingRecorder.beginLifecycle("play")
        let context = measuredPlaybackStartContext(timingSession: timingSession)
        playbackEngine.play(from: context, loopEnabled: isLoopPlaybackEnabled, timingSession: timingSession)
        syncControlPanelView()
        finishPlayTimingSession(timingSession, context: context)
        scheduleDebugStop(after: seconds, replayAfterStop: false)
    }

    private func debugJumpOrder(delta: Int) {
        guard let song = playbackEngine.song,
              !song.orders.isEmpty else {
            return
        }
        let proposedOrderIndex = currentPlaybackOrderIndex() + delta
        let clampedOrderIndex = min(max(0, proposedOrderIndex), song.orders.count - 1)
        debugSeekToOrder(clampedOrderIndex, rowIndex: 0)
    }

    private func debugSeekToOrder(_ orderIndex: Int, rowIndex: Int) {
        let shouldAutoplay = playbackEngine.state.isPlaying
        playbackEngine.seek(
            to: PlaybackDebugStartRequest(orderIndex: orderIndex, rowIndex: rowIndex),
            autoplay: shouldAutoplay
        )
        syncControlPanelView()
    }

    private func currentPlaybackOrderIndex() -> Int {
        playbackEngine.currentPosition?.orderIndex ?? selectedSongPositionIndex
    }

    private var interactionMode: TrackerInteractionMode {
        if isEditModeEnabled {
            return .edit
        }
        if playbackEngine.state.isPlaying {
            return .playOnly
        }
        return .navigation
    }

    private func currentPlaybackStartContext() -> PlaybackStartContext? {
        guard let metadata = loadedMetadata else {
            return nil
        }
        return PlaybackStartContext(
            moduleTitle: metadata.title.isEmpty ? nil : metadata.title,
            songPosition: selectedSongPositionIndex,
            patternIndex: currentPatternIndex,
            row: cursor.row
        )
    }

    private func measuredPlaybackStartContext(timingSession: PlaybackTimingTraceSession?) -> PlaybackStartContext? {
        let start = timingSession?.beginPhase()
        let context = currentPlaybackStartContext()
        timingSession?.recordPhase(
            "app_play_start_context_resolution",
            startedAt: start,
            fields: PlaybackTimingTraceFields.playbackStartContext(context)
        )
        return context
    }

    private func finishLoadTimingSession(
        _ timingSession: PlaybackTimingTraceSession?,
        succeeded: Bool,
        metadata: ParsedModuleMetadata?,
        playbackSong: PlaybackSong?
    ) {
        guard let timingSession else {
            return
        }
        var fields = [PlaybackTimingTraceField("load_succeeded", succeeded)]
        if let metadata {
            fields.append(contentsOf: PlaybackTimingTraceFields.moduleMetadata(metadata))
        }
        fields.append(contentsOf: PlaybackTimingTraceFields.playbackSong(playbackSong))
        timingSession.finish(fields: fields)
    }

    private func finishPlayTimingSession(_ timingSession: PlaybackTimingTraceSession?, context: PlaybackStartContext?) {
        guard let timingSession else {
            return
        }
        var fields = PlaybackTimingTraceFields.playbackStartContext(context)
        fields.append(contentsOf: PlaybackTimingTraceFields.playbackSong(playbackEngine.song))
        fields.append(PlaybackTimingTraceField("is_playing_after", playbackEngine.state.isPlaying))
        timingSession.finish(fields: fields)
    }

    private func applyPlaybackPosition(_ position: PlaybackPosition) {
        guard let metadata = loadedMetadata,
              metadata.type == "XM",
              metadata.xmPatterns.indices.contains(position.patternIndex) else {
            syncControlPanelView()
            return
        }

        selectedSongPositionIndex = clampedSongPosition(position.orderIndex, songLength: metadata.songLength)
        currentPatternIndex = position.patternIndex
        if let selectorIndex = displayedPatternEntries.firstIndex(where: { $0.patternIndex == position.patternIndex }) {
            selectedPatternSelectionIndex = selectorIndex
            patternSelector?.selectItem(at: selectorIndex)
        }
        cursor.row = position.rowIndex
        renderCurrentPattern(metadata: metadata)
        syncControlPanelView()
    }

    private func updatePatternSelector(for metadata: ParsedModuleMetadata, keepPattern: Int?) {
        guard let selector = patternSelector else {
            return
        }
        let referencedPatterns = Set(
            metadata.orderTable.filter { $0 >= 0 && $0 < metadata.xmPatterns.count }
        )
        let nonEmptyPatterns = Set(
            metadata.xmPatterns.compactMap { pattern in
                let hasData = pattern.rows.contains { row in
                    row.contains { $0 != .empty }
                }
                return hasData ? pattern.index : nil
            }
        )
        let intersectedUsed = referencedPatterns.intersection(nonEmptyPatterns)
        let effectiveUsedPatterns: Set<Int> = intersectedUsed.isEmpty ? referencedPatterns : intersectedUsed
        let rowCounts = metadata.xmPatterns.map(\.rowCount)
        let selection = ModuleMetadataLoader.buildPatternSelection(
            orderTable: metadata.orderTable,
            patternCount: metadata.xmPatterns.count,
            rowCounts: rowCounts,
            showAllPatterns: false,
            usedPatternIndices: effectiveUsedPatterns
        )
        displayedPatternEntries = selection.entries
        invalidReferencedPatternIndices = selection.invalidReferencedPatterns

        selector.removeAllItems()
        for entry in displayedPatternEntries {
            selector.addItem(withTitle: formattedPatternSelectorTitle(patternIndex: entry.patternIndex, rowCount: entry.rowCount))
        }
        guard !displayedPatternEntries.isEmpty else {
            selector.isEnabled = false
            return
        }

        if let keepPattern, let index = displayedPatternEntries.firstIndex(where: { $0.patternIndex == keepPattern }) {
            selectedPatternSelectionIndex = index
        } else {
            selectedPatternSelectionIndex = 0
        }
        currentPatternIndex = displayedPatternEntries[selectedPatternSelectionIndex].patternIndex
        selector.selectItem(at: selectedPatternSelectionIndex)
        selector.isEnabled = true
    }

    private func applySongPosition(_ proposedPosition: Int, in metadata: ParsedModuleMetadata, resetCursor: Bool = true) {
        let clampedPosition = clampedSongPosition(proposedPosition, songLength: metadata.songLength)
        selectedSongPositionIndex = clampedPosition
        if let patternIndex = displayedPatternIndex(in: metadata, songPosition: clampedPosition) {
            currentPatternIndex = patternIndex
            if let selectorIndex = displayedPatternEntries.firstIndex(where: { $0.patternIndex == patternIndex }) {
                selectedPatternSelectionIndex = selectorIndex
                patternSelector?.selectItem(at: selectorIndex)
            }
        }
        if resetCursor {
            cursor = PatternCursor(row: 0, channel: 0, field: .note)
        }
    }

    private func displayedPatternIndex(in metadata: ParsedModuleMetadata, songPosition: Int) -> Int? {
        let safeSongLength = min(metadata.songLength, metadata.orderTable.count)
        guard safeSongLength > 0 else { return nil }
        let clampedPosition = min(max(0, songPosition), safeSongLength - 1)
        let patternIndex = metadata.orderTable[clampedPosition]
        guard metadata.xmPatterns.indices.contains(patternIndex) else {
            return nil
        }
        return patternIndex
    }

    private func formattedPatternSelectorTitle(patternIndex: Int, rowCount: Int) -> String {
        ControlPanelDisplayState.patternDisplayTitle(patternIndex: patternIndex)
    }

    private func clampedSongPosition(_ proposedPosition: Int, songLength: Int) -> Int {
        guard songLength > 0 else { return 0 }
        return min(max(0, proposedPosition), songLength - 1)
    }

    private func renderCurrentPattern(metadata: ParsedModuleMetadata, isViewportResizeRerender: Bool = false) {
        guard metadata.type == "XM", metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }
        let pattern = metadata.xmPatterns[currentPatternIndex]
        if pattern.rowCount == 0 {
            metadataTextView?.string = "Pattern \(pattern.index) is empty."
            return
        }

        cursor.clamp(rowCount: pattern.rowCount, channelCount: pattern.channels)
        patternInfoLabel?.stringValue = ""
        patternInfoLabel?.isHidden = true
        let channelHeader = ModuleMetadataLoader.renderXMChannelHeader(channels: pattern.channels)
        let metrics = viewportMetrics()
        let viewportState = PatternViewportState(currentRow: cursor.row, rowCount: pattern.rowCount, metrics: metrics)
        let viewportLayout = PatternViewportTextLayout(pattern: pattern, state: viewportState)
        currentViewportState = viewportState
        currentViewportLayout = viewportLayout
        visibleGridRangesByRow = viewportLayout.gridRangesByRow

        updatePatternHeader(channelHeader, channels: pattern.channels)
        updatePatternDividerIndices(channels: pattern.channels, layout: viewportLayout)

        let attributed = NSMutableAttributedString(string: viewportLayout.renderedText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .ligature: 0,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.text
        ]
        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        applyBeatAccentStyling(attributed, layout: viewportLayout)
        if let range = viewportLayout.fullRangesByRow[cursor.row] {
            attributed.addAttribute(.backgroundColor, value: theme.rowHighlight, range: range)
        }
        metadataTextView?.textStorage?.setAttributedString(attributed)
        updateActiveFieldRange()
        updateMetadataTextViewDocumentSize(renderedRowCount: viewportState.visibleRowCount)
        syncTrackerViewport()
        if let textView = metadataTextView {
            mainWindow?.makeFirstResponder(textView)
        }
        if TrackerViewportResizeBehavior.shouldRevealCursorHorizontally(
            isViewportResizeRerender: isViewportResizeRerender
        ) {
            scrollCursorFieldHorizontallyIntoView(offset: 0)
        }
        refreshTrackerChromeOverlay()
    }

    private func handlePatternNavigation(_ command: PatternNavigationCommand) {
        guard let metadata = displayedMetadata, metadata.type == "XM",
              metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }

        let pattern = metadata.xmPatterns[currentPatternIndex]
        cursor.move(command, rowCount: pattern.rowCount, channelCount: pattern.channels)
        renderCurrentPattern(metadata: metadata)
    }

    private func handlePatternEditInput(_ input: PatternEditInput) -> Bool {
        let sourceContext = currentEditorNoteAuditionSourceContext()
        let route = EditorNoteAuditionInputPolicy.route(
            input: noteAuditionInputKind(for: input),
            editModeEnabled: isEditModeEnabled,
            sourceContext: sourceContext,
            isNoteField: cursor.field == .note
        )
        let previewOutcome = route.shouldAttemptPreview
            ? attemptEditorNoteAuditionPreview(for: input, sourceContext: sourceContext)
            : .skipped(.missingRequest)

        guard !route.shouldConsumeRepeatedNoteKey else {
            return true
        }

        guard route.shouldMutatePattern,
              var document = blankDocument,
              loadedMetadata == nil else {
            return route.shouldConsumeNonMutatingInput(previewOutcome: previewOutcome)
        }

        let didMutate: Bool
        switch input {
        case let .noteKey(character, _):
            didMutate = document.enterNote(
                trackerKey: character,
                octave: selectedOctave,
                row: cursor.row,
                channel: cursor.channel,
                patternIndex: currentPatternIndex
            )
        case .keyOff:
            didMutate = document.enterKeyOff(row: cursor.row, channel: cursor.channel, patternIndex: currentPatternIndex)
        case .clearField:
            didMutate = document.clearNote(row: cursor.row, channel: cursor.channel, patternIndex: currentPatternIndex)
        case .hexDigit:
            didMutate = false
        }

        guard didMutate else {
            return false
        }

        let editedPattern = document.pattern(for: currentPatternIndex) ?? document.pattern
        cursor.row = TrackerEditStep.advancedRow(after: cursor.row, rowCount: editedPattern.rowCount)
        blankDocument = document
        renderCurrentPattern(metadata: document.metadata)
        syncControlPanelView()
        return true
    }

    private func handlePatternNoteKeyRelease(_ character: Character) -> Bool {
        guard let keyIdentity = EditorNoteAuditionKeyIdentity(trackerKey: character) else {
            return false
        }
        let didStopPreview = noteAuditionPreviewer.stopPreview(for: keyIdentity)
        return EditorNoteAuditionInputPolicy.shouldConsumeNoteKeyRelease(
            didStopPreview: didStopPreview,
            editModeEnabled: isEditModeEnabled,
            isNoteField: cursor.field == .note
        )
    }

    private func noteAuditionInputKind(for input: PatternEditInput) -> EditorNoteAuditionInputKind {
        switch input {
        case let .noteKey(_, isRepeat):
            return .noteKey(isRepeat: isRepeat)
        case .keyOff:
            return .keyOff
        case .clearField:
            return .clearField
        case .hexDigit:
            return .other
        }
    }

    private func currentEditorNoteAuditionSourceContext() -> EditorNoteAuditionSourceContext {
        loadedMetadata != nil
            ? .loadedModule(patternIndex: currentPatternIndex)
            : blankDocument?.noteAuditionSourceContext ?? .blankDocument
    }

    private func attemptEditorNoteAuditionPreview(
        for input: PatternEditInput,
        sourceContext: EditorNoteAuditionSourceContext
    ) -> EditorNoteAuditionPreviewOutcome {
        guard case let .noteKey(character, isRepeat) = input else {
            return noteAuditionPreviewer.preview(
                request: nil,
                availability: .unavailable(.selectedInstrumentSampleNotPlayable)
            )
        }
        let selection = currentEditorSelection()
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: character,
            selectedOctave: selectedOctave,
            selection: selection,
            sourceContext: sourceContext,
            channelIndex: cursor.channel,
            rowIndex: cursor.row,
            isRepeatedKeyDown: isRepeat
        )
        let keyIdentity = EditorNoteAuditionKeyIdentity(trackerKey: character)
        let availability: EditorNoteAuditionAvailability
        if loadedMetadata != nil {
            availability = request.map {
                EditorNoteAuditionAvailabilityResolver.availability(
                    for: $0,
                    loadedPlaybackSong: playbackEngine.song
                )
            } ?? .unavailable(.selectedInstrumentSampleNotPlayable)
        } else if let document = blankDocument {
            availability = document.noteAuditionAvailability
        } else {
            availability = .unavailable(.blankDocumentMissingInstrumentSamplePayload)
        }
        return noteAuditionPreviewer.preview(
            request: request,
            availability: availability,
            keyIdentity: keyIdentity
        )
    }

    private func handlePatternWheel(deltaY: CGFloat) {
        guard let metadata = displayedMetadata,
              metadata.type == "XM",
              metadata.xmPatterns.indices.contains(currentPatternIndex) else {
            return
        }

        let command: PatternNavigationCommand = deltaY < 0 ? .down : .up
        handlePatternNavigation(command)
    }

    private func scrollCursorFieldHorizontallyIntoView(offset: Int) {
        guard let rowRange = visibleGridRangesByRow[cursor.row],
              let textView = metadataTextView,
              let scrollView = gridScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        let clampedChannel = max(0, cursor.channel)
        let channelOffset = clampedChannel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let fieldOffset = cursor.field.textOffset
        let fieldLength = cursor.field.textLength
        let maxLocation = rowRange.location + max(0, rowRange.length - 1)
        let targetLocation = min(maxLocation, rowRange.location + channelOffset + fieldOffset)
        let range = NSRange(location: targetLocation + offset, length: max(1, fieldLength))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return
        }
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textView.textContainerOrigin.x
        cursorRect.origin.y += textView.textContainerOrigin.y
        let visibleRect = scrollView.contentView.bounds
        let horizontalMargin = PatternCursorOutlineGeometry.scrollMargin.width
        let targetMinX = cursorRect.minX - horizontalMargin
        let targetMaxX = cursorRect.maxX + horizontalMargin
        let leftObstructionWidth = trackerChromeOverlayView?.dividerX ?? 0
        var targetOrigin = visibleRect.origin
        let visibleMinX = visibleRect.minX + leftObstructionWidth
        if targetMinX < visibleMinX {
            targetOrigin.x = max(0, targetMinX - leftObstructionWidth)
        } else if targetMaxX > visibleRect.maxX {
            let maxOriginX = max(0, textView.frame.width - visibleRect.width)
            targetOrigin.x = min(maxOriginX, targetMaxX - visibleRect.width)
        }
        scrollView.contentView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncStickyPanesToGrid()
    }

    private func updateActiveFieldRange() {
        guard let rowRange = visibleGridRangesByRow[cursor.row],
              let textView = metadataTextView else {
            return
        }

        let channelOffset = cursor.channel * (ModuleMetadataLoader.xmRenderedCellWidth + ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
        let fieldOffset = cursor.field.textOffset
        let location = rowRange.location + channelOffset + fieldOffset
        let maxLocation = rowRange.location + max(0, rowRange.length - 1)
        let clampedLocation = min(location, maxLocation)
        textView.activeFieldRange = NSRange(location: clampedLocation, length: max(1, cursor.field.textLength))
    }

    private func updateMetadataTextViewDocumentSize(renderedRowCount: Int) {
        guard let textView = metadataTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer).integral
        let inset = textView.textContainerInset
        let contentWidth = usedRect.width + inset.width * 2 + 2 + PatternViewportMetrics.trailingContentPadding
        let viewport = textView.enclosingScrollView?.contentView.bounds.size ?? .zero
        let metrics = viewportMetrics()
        let contentHeight = metrics.contentHeight(forRenderedRowCount: renderedRowCount, insetHeight: inset.height)

        let targetSize = NSSize(
            width: max(viewport.width, contentWidth),
            height: max(viewport.height, contentHeight)
        )
        textView.setFrameSize(targetSize)
    }

    private func viewportMetrics() -> PatternViewportMetrics {
        PatternViewportMetrics(
            rowHeight: max(1, measuredPatternRowHeight()),
            viewportHeight: gridScrollView?.contentView.bounds.height ?? 0
        )
    }

    private func measuredPatternRowHeight() -> CGFloat {
        guard let firstRange = visibleGridRangesByRow.keys.sorted().first.flatMap({ visibleGridRangesByRow[$0] }),
              let textView = metadataTextView,
              let layoutManager = textView.layoutManager else {
            return 17
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: firstRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return 17
        }
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
        return max(1, lineRect.height)
    }

    private func syncTrackerViewport() {
        guard let scrollView = gridScrollView,
              let documentView = scrollView.documentView else { return }
        let currentOrigin = scrollView.contentView.bounds.origin
        let preferredOriginX = pendingHorizontalViewportOrigin ?? currentOrigin.x
        let clampedOriginX = TrackerViewportScrollGeometry.clampedHorizontalOrigin(
            preferredOriginX: preferredOriginX,
            contentWidth: documentView.frame.width,
            viewportWidth: scrollView.contentView.bounds.width
        )
        pendingHorizontalViewportOrigin = nil
        scrollView.contentView.scroll(to: NSPoint(x: clampedOriginX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncStickyPanesToGrid()
    }

    private func syncStickyPanesToGrid() {
        guard let gridClipView = gridScrollView?.contentView else { return }
        let origin = gridClipView.bounds.origin
        let isLiveResize = isLiveResizingTrackerViewport || (mainWindow?.inLiveResize ?? false)
        if TrackerViewportResizeBehavior.shouldCaptureStableHorizontalOrigin(isLiveResize: isLiveResize) {
            lastStableGridHorizontalOrigin = origin.x
        }
        if let patternHeaderScrollView {
            patternHeaderScrollView.contentView.scroll(to: NSPoint(x: origin.x, y: 0))
            patternHeaderScrollView.reflectScrolledClipView(patternHeaderScrollView.contentView)
        }
        refreshTrackerChromeOverlay()
        trackerChromeOverlayView?.needsDisplay = true
    }

    private func updatePatternDividerIndices(channels: Int, layout: PatternViewportTextLayout) {
        guard let textView = metadataTextView,
              channels > 0,
              let firstVisibleRowRange = layout.slotGridRanges.first else {
            metadataTextView?.dividerCharacterIndices = []
            metadataTextView?.dividerTopCharacterIndex = nil
            return
        }

        let rowStart = firstVisibleRowRange.location
        let separatorMidOffset = ModuleMetadataLoader.xmRenderedCellSeparatorWidth / 2
        var indices = [Int]()
        indices.reserveCapacity(max(0, channels - 1))

        for divider in 1..<channels {
            let separatorStart = rowStart + (divider * ModuleMetadataLoader.xmRenderedCellWidth) +
                ((divider - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
            indices.append(separatorStart + separatorMidOffset)
        }
        textView.dividerCharacterIndices = indices
        textView.dividerTopCharacterIndex = nil
    }

    private func updatePatternHeader(_ headerText: String, channels: Int) {
        guard let headerTextView = patternHeaderTextView else {
            return
        }
        let headerPrefixLength = PatternViewportTextLayout.rowNumberPrefixLength
        let headerLeadingPadding = String(repeating: " ", count: PatternViewportTextLayout.leadingChannelPaddingLength)
        let attributed = NSMutableAttributedString(
            string: String(repeating: " ", count: headerPrefixLength) + headerLeadingPadding + headerText
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        attributed.addAttributes(
            [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .ligature: 0,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.accent
            ],
            range: NSRange(location: 0, length: attributed.length)
        )
        headerTextView.textStorage?.setAttributedString(attributed)
        let viewportWidth = patternHeaderScrollView?.contentView.bounds.width ?? 0
        headerTextView.setFrameSize(NSSize(width: max(viewportWidth, attributed.size().width + 16), height: 24))
        let separatorMidOffset = ModuleMetadataLoader.xmRenderedCellSeparatorWidth / 2
        var indices = [Int]()
        indices.reserveCapacity(max(0, channels - 1))
        for divider in 1..<channels {
            let separatorStart = headerPrefixLength + PatternViewportTextLayout.leadingChannelPaddingLength +
                (divider * ModuleMetadataLoader.xmRenderedCellWidth) +
                ((divider - 1) * ModuleMetadataLoader.xmRenderedCellSeparatorWidth)
            indices.append(separatorStart + separatorMidOffset)
        }
        headerTextView.dividerCharacterIndices = indices
        headerTextView.dividerTopCharacterIndex = nil
    }

    private func applyBeatAccentStyling(_ attributed: NSMutableAttributedString, layout: PatternViewportTextLayout) {
        let interval = PatternGridPreferences.beatAccentInterval
        guard interval > 0 else { return }

        for rowIndex in layout.slotRows.compactMap({ $0 }) where rowIndex % interval == 0 {
            guard let rowRange = layout.fullRangesByRow[rowIndex] else { continue }
            guard rowRange.location + rowRange.length <= attributed.length else {
                continue
            }
            attributed.addAttribute(.backgroundColor, value: theme.beatAccent, range: rowRange)
            attributed.addAttribute(.foregroundColor, value: theme.text, range: rowRange)
        }
    }

    @objc
    private func gridClipViewBoundsDidChange(_ notification: Notification) {
        guard !isSyncingScroll,
              let clipView = notification.object as? NSClipView,
              clipView === gridScrollView?.contentView else {
            return
        }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        let viewportSize = clipView.bounds.size
        if viewportSize != lastGridViewportSize,
           let metadata = displayedMetadata,
           metadata.type == "XM",
           metadata.xmPatterns.indices.contains(currentPatternIndex) {
            pendingHorizontalViewportOrigin = liveResizeHorizontalOrigin ?? lastStableGridHorizontalOrigin
            lastGridViewportSize = viewportSize
            renderCurrentPattern(metadata: metadata, isViewportResizeRerender: true)
            return
        }
        syncStickyPanesToGrid()
    }

    private func trackerWindowWillStartLiveResize() {
        guard let scrollView = gridScrollView else { return }
        isLiveResizingTrackerViewport = true
        liveResizeHorizontalOrigin = scrollView.contentView.bounds.origin.x
        pendingHorizontalViewportOrigin = liveResizeHorizontalOrigin
    }

    private func trackerWindowDidEndLiveResize() {
        isLiveResizingTrackerViewport = false
        if let scrollView = gridScrollView {
            lastGridViewportSize = scrollView.contentView.bounds.size
            lastStableGridHorizontalOrigin = scrollView.contentView.bounds.origin.x
        }
        liveResizeHorizontalOrigin = nil
    }

    private func updateTrackerChromeOverlay(layout: PatternViewportTextLayout, viewportState: PatternViewportState) {
        guard let trackerChromeOverlayView,
              let textView = metadataTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let firstGridRange = layout.slotGridRanges.first else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        textView.layoutSubtreeIfNeeded()
        let gridGlyphRange = layoutManager.glyphRange(forCharacterRange: firstGridRange, actualCharacterRange: nil)
        let firstGridGlyphIndex = gridGlyphRange.location
        let firstGridGlyphLocation = layoutManager.location(forGlyphAt: firstGridGlyphIndex)
        let leadingChannelPaddingWidth = NSString(
            string: String(repeating: " ", count: PatternViewportTextLayout.leadingChannelPaddingLength)
        ).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
        let gutterBoundaryX = floor(textView.textContainerOrigin.x + firstGridGlyphLocation.x - leadingChannelPaddingWidth)
        let rowNumberWidth = NSString(string: "00").size(
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        ).width
        let visibleDividerX = TrackerPinnedGutterGeometry.visibleWidth(for: gutterBoundaryX, rowNumberWidth: rowNumberWidth)

        trackerChromeOverlayView.viewportState = viewportState
        trackerChromeOverlayView.currentRow = cursor.row
        trackerChromeOverlayView.gutterWidth = visibleDividerX
        trackerChromeOverlayView.dividerX = gutterBoundaryX
        trackerDividerUnderlayView?.gutterWidth = visibleDividerX
        trackerDividerUnderlayView?.dividerX = gutterBoundaryX
        trackerChromeOverlayView.beatInterval = PatternGridPreferences.beatAccentInterval
        trackerChromeOverlayView.rowEntries = layout.slotRows.enumerated().compactMap { slotIndex, rowIndex in
            let characterRange = layout.slotFullRanges[slotIndex]
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }

            var lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            lineRect.origin.x += textView.textContainerOrigin.x
            lineRect.origin.y += textView.textContainerOrigin.y
            let overlayRect = trackerChromeOverlayView.convert(lineRect, from: textView)
            return TrackerChromeOverlayView.RowEntry(rowIndex: rowIndex, rect: overlayRect)
        }
        trackerChromeOverlayView.isHidden = false
        trackerChromeOverlayView.needsDisplay = true
    }

    private func refreshTrackerChromeOverlay() {
        guard let layout = currentViewportLayout,
              let viewportState = currentViewportState else {
            return
        }
        updateTrackerChromeOverlay(layout: layout, viewportState: viewportState)
    }

    private func syncControlPanelView() {
        if let blankDocument {
            reloadInstrumentControls(for: blankDocument)
            controlPanelView?.apply(ControlPanelDisplayState.blankDocumentContent(
                for: blankDocument,
                selectedOctave: selectedOctave,
                isLoopEnabled: isLoopPlaybackEnabled,
                isEditModeEnabled: isEditModeEnabled,
                isPlaybackActive: playbackEngine.state.isPlaying
            ))
            return
        }

        if let metadata = loadedMetadata {
            reloadInstrumentControls(for: metadata, selection: loadedModuleSelection)
            let selectedInstrument = playbackEngine.song?.instrument(forInstrument: loadedModuleSelection.selectedInstrument)
            let selectedSample = selectedInstrument?.sample(selectedSampleSlot: loadedModuleSelection.selectedSample)
            controlPanelView?.apply(ControlPanelDisplayState.loadedModuleContent(
                metadata: metadata,
                selection: loadedModuleSelection,
                selectedSongPositionIndex: selectedSongPositionIndex,
                currentPatternIndex: currentPatternIndex,
                selectedOctave: selectedOctave,
                isLoopEnabled: isLoopPlaybackEnabled,
                isEditModeEnabled: isEditModeEnabled,
                isPlaybackActive: playbackEngine.state.isPlaying,
                songTime: ControlPanelDisplayState.songTimeDisplay(
                    durationSeconds: playbackEngine.runtimeAdapterPlanDurationSeconds
                ),
                selectedInstrumentName: selectedInstrument?.name,
                selectedSampleName: selectedSample?.name
            ))
        } else {
            reloadInstrumentControls(for: nil, selection: .default)
            controlPanelView?.apply(ControlPanelContent())
        }
    }

    private func reloadInstrumentControls(for metadata: ParsedModuleMetadata?, selection: TrackerEditorSelection) {
        let instrumentSlots: [Int]
        if let metadata, metadata.type == "XM", metadata.instruments > 0 {
            instrumentSlots = Array(1...min(metadata.instruments, 32))
        } else {
            instrumentSlots = []
        }
        reloadInstrumentControls(
            instrumentSlots: instrumentSlots,
            selection: selection,
            instrumentProvider: { [weak self] slot in
                self?.playbackEngine.song?.instrument(forInstrument: slot)
            }
        )
    }

    private func reloadInstrumentControls(for document: BlankTrackerDocument) {
        reloadInstrumentControls(
            instrumentSlots: Array(document.instrumentPalette.keys.sorted().prefix(32)),
            selection: document.selection,
            instrumentProvider: { slot in
                document.instrument(forInstrument: slot)
            }
        )
    }

    private func reloadInstrumentControls(
        instrumentSlots: [Int],
        selection: TrackerEditorSelection,
        instrumentProvider: (Int) -> PlaybackInstrument?
    ) {
        guard let controlPanelView else {
            return
        }
        controlPanelView.instrumentSelector.removeAllItems()
        controlPanelView.sampleSelector.removeAllItems()

        guard !instrumentSlots.isEmpty else {
            controlPanelView.instrumentSelector.addItem(withTitle: "No Inst")
            controlPanelView.sampleSelector.addItem(withTitle: "No Sample")
            return
        }

        for slot in instrumentSlots {
            let display = ControlPanelSlotDisplay.instrument(
                slot: slot,
                name: instrumentProvider(slot)?.name
            )
            controlPanelView.instrumentSelector.addItem(withTitle: display.displayTitle)
            controlPanelView.instrumentSelector.lastItem?.representedObject = slot
            controlPanelView.instrumentSelector.lastItem?.toolTip = display.tooltip
        }
        if let selectedInstrumentIndex = instrumentSlots.firstIndex(of: selection.selectedInstrument) {
            controlPanelView.instrumentSelector.selectItem(at: selectedInstrumentIndex)
        } else {
            controlPanelView.instrumentSelector.selectItem(at: 0)
        }
        reloadSampleSelector(selection: selection, instrumentProvider: instrumentProvider)
    }

    private func currentEditorSelection() -> TrackerEditorSelection {
        if loadedMetadata != nil {
            return loadedModuleSelection
        }
        return blankDocument?.selection ?? .default
    }

    private func reloadSampleSelector(
        selection: TrackerEditorSelection,
        instrumentProvider: (Int) -> PlaybackInstrument?
    ) {
        guard let controlPanelView else {
            return
        }

        controlPanelView.sampleSelector.removeAllItems()
        let instrument = instrumentProvider(selection.selectedInstrument)
        let sampleSlots = instrument?.availableSampleSlots ?? []
        let displayedSampleSlots = sampleSlots.isEmpty ? [selection.selectedSample] : sampleSlots

        for slot in displayedSampleSlots {
            let display = ControlPanelSlotDisplay.sample(
                slot: slot,
                name: instrument?.sample(selectedSampleSlot: slot)?.name
            )
            controlPanelView.sampleSelector.addItem(withTitle: display.displayTitle)
            controlPanelView.sampleSelector.lastItem?.representedObject = slot
            controlPanelView.sampleSelector.lastItem?.toolTip = display.tooltip
        }
        let selectedDisplay = ControlPanelSlotDisplay.sample(
            slot: selection.selectedSample,
            name: instrument?.sample(selectedSampleSlot: selection.selectedSample)?.name
        )
        controlPanelView.sampleSelector.selectItem(withTitle: selectedDisplay.displayTitle)
    }

    private func loadedModuleCanMakeEditableCopy() -> Bool {
        guard blankDocument == nil,
              loadedMetadata != nil,
              let song = playbackEngine.song else {
            return false
        }
        return song.instrumentsByIndex.values.contains { instrument in
            instrument.samples.contains { !$0.pcm.isEmpty }
        }
    }

    private func clampedLoadedModuleSelection(
        _ selection: TrackerEditorSelection,
        song: PlaybackSong? = nil
    ) -> TrackerEditorSelection {
        let playbackSong = song ?? playbackEngine.song
        let sampleSlots = playbackSong?
            .instrument(forInstrument: selection.selectedInstrument)?
            .availableSampleSlots ?? []
        return selection.clampedToAvailableSampleSlots(sampleSlots)
    }

    private func selectedPopupSlot(_ sender: NSPopUpButton) -> Int? {
        sender.selectedItem?.representedObject as? Int
    }

}
