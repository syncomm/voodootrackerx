import AppKit

typealias InstrumentEditorNoteAuditionKeyDownHandler = (_ trackerKey: Character, _ isRepeat: Bool) -> Bool
typealias InstrumentEditorNoteAuditionKeyUpHandler = (_ trackerKey: Character) -> Bool
typealias InstrumentEditorNoteAuditionCancelHandler = () -> Void
typealias InstrumentEditorInstrumentSelectionHandler = (_ oneBasedInstrumentSlot: Int) -> Bool
typealias InstrumentEditorSampleSelectionHandler = (_ oneBasedSampleSlot: Int) -> Bool
typealias InstrumentKeyboardVisibleRangeChangeHandler = (InstrumentKeyboardVisibleRange) -> Void
typealias InstrumentKeymapRangeAssignmentHandler = (_ focusedNote: UInt8?) -> Bool

enum InstrumentEditorCopy {
    static let keymapSummary = "FULL 96-NOTE COMMITTED OWNERSHIP · USE MAP RANGE… TO EDIT · PIANO AUDITIONS"
    static let auditionKeyboard = "AUDITION KEYBOARD · CLICK / DRAG TO PREVIEW"
}

enum InstrumentKeyboardRangeShift: Equatable {
    case lower
    case higher
}

/// Canonical three-octave slice of the 96-note XM instrument map.
struct InstrumentKeyboardVisibleRange: Equatable {
    static let noteCount = 36
    static let octaveStep = 12
    static let minimumStartNote = 1
    static let maximumStartNote = TrackerNoteKeyMap.maximumNoteValue - noteCount + 1
    static let defaultRange = InstrumentKeyboardVisibleRange(uncheckedStartNote: 25) // C-2...B-4

    let startNote: Int

    init?(startNote: Int) {
        guard (Self.minimumStartNote...Self.maximumStartNote).contains(startNote),
              (startNote - 1).isMultiple(of: Self.octaveStep) else { return nil }
        self.startNote = startNote
    }

    private init(uncheckedStartNote: Int) { startNote = uncheckedStartNote }

    var endNote: Int { startNote + Self.noteCount - 1 }
    var noteCount: Int { Self.noteCount }
    var noteRange: ClosedRange<UInt8> { UInt8(startNote)...UInt8(endNote) }
    var startLabel: String { ModuleMetadataLoader.formatXMNote(UInt8(startNote)) }
    var endLabel: String { ModuleMetadataLoader.formatXMNote(UInt8(endNote)) }

    func contains(_ noteValue: UInt8) -> Bool { noteRange.contains(noteValue) }

    func canShift(_ direction: InstrumentKeyboardRangeShift) -> Bool {
        switch direction {
        case .lower: startNote > Self.minimumStartNote
        case .higher: startNote < Self.maximumStartNote
        }
    }

    func shifted(_ direction: InstrumentKeyboardRangeShift) -> InstrumentKeyboardVisibleRange {
        guard canShift(direction) else { return self }
        let delta = direction == .lower ? -Self.octaveStep : Self.octaveStep
        return InstrumentKeyboardVisibleRange(startNote: startNote + delta) ?? self
    }
}

/// Shared geometry for drawing committed ownership on the full 96-note summary strip.
enum InstrumentKeymapSummaryGeometry {
    static let noteCount = TrackerNoteKeyMap.maximumNoteValue
    static let borderInset: CGFloat = 1

    static func drawableBounds(in bounds: NSRect) -> NSRect? {
        let drawable = bounds.insetBy(dx: borderInset, dy: borderInset)
        guard drawable.width > 0, drawable.height > 0,
              drawable.width.isFinite, drawable.height.isFinite else { return nil }
        return drawable
    }

    static func rect(for noteIndices: ClosedRange<Int>, in bounds: NSRect) -> NSRect? {
        guard let drawable = drawableBounds(in: bounds) else { return nil }
        let lower = min(noteCount - 1, max(0, noteIndices.lowerBound))
        let upper = min(noteCount - 1, max(lower, noteIndices.upperBound))
        let cellWidth = drawable.width / CGFloat(noteCount)
        return NSRect(
            x: drawable.minX + CGFloat(lower) * cellWidth,
            y: drawable.minY,
            width: CGFloat(upper - lower + 1) * cellWidth,
            height: drawable.height
        )
    }
}

enum InstrumentKeymapRangeDefaultPolicy {
    static func noteRange(
        focusedNote: UInt8?,
        selectedOctave: Int?
    ) -> ClosedRange<Int> {
        if let focusedNote, (1...TrackerNoteKeyMap.maximumNoteValue).contains(Int(focusedNote)) {
            let noteIndex = Int(focusedNote) - 1
            return noteIndex...noteIndex
        }
        if let selectedOctave, (0...7).contains(selectedOctave) {
            return (selectedOctave * 12)...(selectedOctave * 12 + 11)
        }
        return 48...59 // C-4...B-4
    }
}

struct InstrumentKeymapRangeAssignmentContext: Equatable {
    static let unavailable = Self(
        documentIdentity: nil, documentRevision: 0, editContext: .none,
        hasConflictingModalSheet: false
    )
    let documentIdentity: UUID?
    let documentRevision: UInt64
    let editContext: EditableDocumentEditContext
    let hasConflictingModalSheet: Bool
}

@MainActor
enum InstrumentKeymapRangeAssignmentConfirmationGate {
    typealias CommitResult = Result<
        SampleKeymapRangeAssignmentOutcome, SampleKeymapRangeEditFailure
    >

    static func perform(
        in context: InstrumentKeymapRangeAssignmentContext,
        commit: () -> CommitResult
    ) -> CommitResult? {
        guard context.documentIdentity != nil,
              case .editable(_, false) = context.editContext else { return nil }
        return commit()
    }
}

@MainActor
enum InstrumentKeymapRangeAssignmentSheetLifecycle {
    static func refreshAfterDismissal(_ refresh: @escaping @MainActor () -> Void) {
        // AppKit can still report the completed sheet as attached inside its
        // completion callback, so recompute modal eligibility on the next turn.
        DispatchQueue.main.async {
            refresh()
        }
    }
}

struct InstrumentKeymapRangeAssignmentRequest: Equatable {
    let operationToken: UUID
    let sampleDisplay: String
    let initialNoteRange: ClosedRange<Int>
}

extension SampleKeymapRangeEditFailure {
    var keymapRangeAssignmentMessage: String {
        switch self {
        case .noEditableDocument: "The document changed before the note range could be mapped."
        case .readOnlyDocument: "This document is read-only."
        case .playbackActive: "Stop playback before mapping a note range."
        case .invalidInstrumentIndex, .instrumentNotSelected, .instrumentNotRepresented:
            "The selected instrument is no longer available."
        case .invalidSampleIndex, .sampleNotRepresented, .emptySampleDestination:
            "The selected sample is no longer represented."
        case .invalidNoteRange: "Choose a valid first and last note."
        case .malformedKeymap: "This instrument does not have the canonical 96-note map."
        case .editApplicationRejected: "This note-range assignment is no longer active."
        }
    }
}

private struct InstrumentKeymapRangeAssignmentCapture {
    let documentIdentity: UUID
    let documentRevision: UInt64
    let instrumentIndex, sampleIndex: Int

    init?(context: InstrumentKeymapRangeAssignmentContext) {
        guard !context.hasConflictingModalSheet,
              let documentIdentity = context.documentIdentity,
              case let .editable(document, false) = context.editContext else { return nil }
        let instrumentIndex = document.selection.selectedInstrument - 1
        let sampleIndex = document.selection.selectedSample - 1
        guard let instrument = document.instrument(forInstrument: instrumentIndex + 1),
              let sample = instrument.sample(mappedSampleIndex: sampleIndex),
              sample.sampleLength > 0,
              !sample.pcm.isEmpty,
              instrument.noteSampleMap?.count == TrackerNoteKeyMap.maximumNoteValue else { return nil }
        self.documentIdentity = documentIdentity
        documentRevision = context.documentRevision
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
    }

    func failure(in context: InstrumentKeymapRangeAssignmentContext) -> SampleKeymapRangeEditFailure? {
        if context.editContext == .loadedReadOnly { return .readOnlyDocument }
        guard context.documentIdentity == documentIdentity,
              context.documentRevision == documentRevision else { return .noEditableDocument }
        guard case let .editable(document, isPlaying) = context.editContext else { return .noEditableDocument }
        guard !isPlaying else { return .playbackActive }
        guard document.selection.selectedInstrument == instrumentIndex + 1 else {
            return .instrumentNotSelected(instrumentIndex)
        }
        guard let instrument = document.instrument(forInstrument: instrumentIndex + 1) else {
            return .instrumentNotRepresented(instrumentIndex)
        }
        guard let sample = instrument.sample(mappedSampleIndex: sampleIndex) else {
            return .sampleNotRepresented(instrumentIndex: instrumentIndex, sampleIndex: sampleIndex)
        }
        guard sample.sampleLength > 0, !sample.pcm.isEmpty else {
            return .emptySampleDestination(instrumentIndex: instrumentIndex, sampleIndex: sampleIndex)
        }
        guard instrument.noteSampleMap?.count == TrackerNoteKeyMap.maximumNoteValue else {
            return .malformedKeymap(expectedCount: TrackerNoteKeyMap.maximumNoteValue,
                                    actualCount: instrument.noteSampleMap?.count)
        }
        return nil
    }
}

@MainActor
final class InstrumentKeymapRangeAssignmentCoordinator {
    typealias CommitHandler = (Int, Int, Int, Int) -> Result<
        SampleKeymapRangeAssignmentOutcome, SampleKeymapRangeEditFailure
    >

    private let contextProvider: () -> InstrumentKeymapRangeAssignmentContext
    private let commitHandler: CommitHandler
    private let stateChangeHandler: () -> Void
    private var activeOperation: (token: UUID, capture: InstrumentKeymapRangeAssignmentCapture)?

    init(
        contextProvider: @escaping () -> InstrumentKeymapRangeAssignmentContext,
        commitHandler: @escaping CommitHandler,
        stateChangeHandler: @escaping () -> Void = {}
    ) {
        self.contextProvider = contextProvider
        self.commitHandler = commitHandler
        self.stateChangeHandler = stateChangeHandler
    }

    var canBegin: Bool {
        activeOperation == nil && InstrumentKeymapRangeAssignmentCapture(context: contextProvider()) != nil
    }

    func begin(
        focusedNote: UInt8?,
        selectedOctave: Int?
    ) -> InstrumentKeymapRangeAssignmentRequest? {
        guard activeOperation == nil,
              let capture = InstrumentKeymapRangeAssignmentCapture(context: contextProvider()) else { return nil }
        let token = UUID()
        activeOperation = (token, capture)
        stateChangeHandler()
        return InstrumentKeymapRangeAssignmentRequest(
            operationToken: token,
            sampleDisplay: String(format: "S%02X", capture.sampleIndex + 1),
            initialNoteRange: InstrumentKeymapRangeDefaultPolicy.noteRange(
                focusedNote: focusedNote,
                selectedOctave: selectedOctave
            )
        )
    }

    @discardableResult
    func cancel(operationToken: UUID) -> Bool {
        guard activeOperation?.token == operationToken else { return false }
        finish()
        return true
    }

    func commit(
        operationToken: UUID,
        lowerNote: Int,
        upperNote: Int
    ) -> Result<SampleKeymapRangeAssignmentOutcome, SampleKeymapRangeEditFailure> {
        guard let activeOperation, activeOperation.token == operationToken else {
            return .failure(.editApplicationRejected)
        }
        defer { finish() }
        let capture = activeOperation.capture
        if let failure = capture.failure(in: contextProvider()) {
            return .failure(failure)
        }
        return commitHandler(capture.instrumentIndex, capture.sampleIndex, lowerNote, upperNote)
    }

    private func finish() {
        activeOperation = nil
        stateChangeHandler()
    }
}

@MainActor
final class InstrumentKeymapRangeAssignmentSheet: NSObject {
    static let noteTitles = (1...TrackerNoteKeyMap.maximumNoteValue)
        .map { ModuleMetadataLoader.formatXMNote(UInt8($0)) }

    let alert = NSAlert()
    let firstNotePopup = NSPopUpButton()
    let lastNotePopup = NSPopUpButton()
    let summaryLabel = NSTextField(labelWithString: "")
    private let sampleDisplay: String
    var mapButton: NSButton { alert.buttons[0] }
    var firstNote: Int { firstNotePopup.indexOfSelectedItem }
    var lastNote: Int { lastNotePopup.indexOfSelectedItem }

    init(request: InstrumentKeymapRangeAssignmentRequest) {
        sampleDisplay = request.sampleDisplay
        super.init()
        alert.alertStyle = .informational
        alert.messageText = "Map Selected Sample to Note Range"
        alert.informativeText = "Notes in this inclusive range will use \(request.sampleDisplay).\nAssignments outside the range will not change."
        alert.addButton(withTitle: "Map Range")
        alert.addButton(withTitle: "Cancel")
        mapButton.setAccessibilityLabel("Map selected sample")
        alert.buttons[1].keyEquivalent = "\u{1b}"

        [(firstNotePopup, "First note"), (lastNotePopup, "Last note")].forEach { popup, label in
            popup.addItems(withTitles: Self.noteTitles)
            popup.target = self
            popup.action = #selector(noteSelectionChanged(_:))
            popup.setAccessibilityLabel(label)
            popup.widthAnchor.constraint(equalToConstant: 100).isActive = true
        }
        summaryLabel.alignment = .center
        summaryLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let rangeRow = NSStackView(views: [
            NSTextField(labelWithString: "From:"), firstNotePopup,
            NSTextField(labelWithString: "To:"), lastNotePopup,
        ])
        rangeRow.spacing = 6
        let accessory = NSStackView(views: [
            NSTextField(labelWithString: "Sample: \(request.sampleDisplay)"),
            rangeRow,
            summaryLabel,
        ])
        accessory.orientation = .vertical
        accessory.alignment = .centerX
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        accessory.frame.size = NSSize(width: 340, height: 86)
        alert.accessoryView = accessory
        selectNoteRange(lowerNote: request.initialNoteRange.lowerBound,
                        upperNote: request.initialNoteRange.upperBound)
    }

    func selectNoteRange(lowerNote: Int, upperNote: Int) {
        firstNotePopup.selectItem(at: min(95, max(0, lowerNote)))
        lastNotePopup.selectItem(at: min(95, max(0, upperNote)))
        updateSummaryAndConfirmation()
    }

    @objc private func noteSelectionChanged(_ sender: Any?) { updateSummaryAndConfirmation() }

    private func updateSummaryAndConfirmation() {
        let firstTitle = Self.noteTitles[firstNote]
        let lastTitle = Self.noteTitles[lastNote]
        mapButton.isEnabled = firstNote <= lastNote
        mapButton.setAccessibilityEnabled(mapButton.isEnabled)
        summaryLabel.stringValue = "\(sampleDisplay) · \(firstTitle) THROUGH \(lastTitle) · INCLUSIVE"
        summaryLabel.setAccessibilityLabel("Selected sample \(sampleDisplay). Inclusive range \(firstTitle) through \(lastTitle).")
    }
}

enum InstrumentEditorPreviewLifecycle {
    static func cancelForSelectionChange(
        cancelOnScreenNote: () -> Bool,
        hasActivePreview: () -> Bool,
        cancelPreview: () -> Void
    ) {
        let releasedOnScreenNote = cancelOnScreenNote()
        if releasedOnScreenNote || hasActivePreview() { cancelPreview() }
    }
}

enum InstrumentEditorOnScreenNoteIntent: Equatable {
    case press(UInt8)
    case release(UInt8)
}

typealias InstrumentEditorOnScreenNoteHandler = (InstrumentEditorOnScreenNoteIntent) -> Bool

enum InstrumentEditorAuditionRequestFactory {
    static func request(
        noteValue: UInt8,
        selection: TrackerEditorSelection,
        sourceContext: EditorNoteAuditionSourceContext,
        channelIndex: Int? = nil,
        rowIndex: Int? = nil,
        isRepeatedKeyDown: Bool = false
    ) -> EditorNoteAuditionRequest? {
        guard (1...96).contains(noteValue) else { return nil }
        return EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: noteValue, selectedOctave: (Int(noteValue) - 1) / 12),
            selection: selection,
            sampleResolution: .instrumentKeymap,
            sourceContext: sourceContext,
            channelIndex: channelIndex,
            rowIndex: rowIndex,
            isRepeatedKeyDown: isRepeatedKeyDown
        )
    }

    static func request(
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
        return request(
            noteValue: noteValue,
            selection: selection,
            sourceContext: sourceContext,
            channelIndex: channelIndex,
            rowIndex: rowIndex,
            isRepeatedKeyDown: isRepeatedKeyDown
        )
    }
}

@MainActor
enum LoadedModuleEditableCopyAlertHostPolicy {
    struct Presentation {
        let hostWindow: NSWindow?
        let auxiliaryWindowToRestore: NSWindow?
    }

    static func presentation(keyWindow: NSWindow?, mainWindow: NSWindow?) -> Presentation {
        let hostWindow = mainWindow ?? keyWindow
        let auxiliaryWindow = keyWindow is NSPanel && keyWindow !== hostWindow
            ? keyWindow
            : nil
        return Presentation(
            hostWindow: hostWindow,
            auxiliaryWindowToRestore: auxiliaryWindow
        )
    }
}

@MainActor
enum LoadedModuleEditableCopyAlertPresenter {
    @MainActor
    struct Actions {
        let orderBack: (NSWindow) -> Void
        let makeKeyAndOrderFront: (NSWindow) -> Void
        let beginSheet: (NSAlert, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void
        let runModal: (NSAlert) -> Void

        static var appKit: Actions {
            Actions(
                orderBack: { $0.orderBack(nil) },
                makeKeyAndOrderFront: { $0.makeKeyAndOrderFront(nil) },
                beginSheet: { alert, hostWindow, completionHandler in
                    alert.beginSheetModal(for: hostWindow, completionHandler: completionHandler)
                },
                runModal: { _ = $0.runModal() }
            )
        }
    }

    static func present(
        _ alert: NSAlert,
        keyWindow: NSWindow?,
        mainWindow: NSWindow?,
        actions: Actions? = nil
    ) {
        let actions = actions ?? .appKit
        let presentation = LoadedModuleEditableCopyAlertHostPolicy.presentation(
            keyWindow: keyWindow,
            mainWindow: mainWindow
        )
        guard let hostWindow = presentation.hostWindow else {
            actions.runModal(alert)
            return
        }

        let auxiliaryWasFloating = (presentation.auxiliaryWindowToRestore as? NSPanel)?.isFloatingPanel
        if let auxiliaryWindow = presentation.auxiliaryWindowToRestore {
            // Floating utility panels remain above main-window sheets even after orderBack.
            // Temporarily use normal panel ordering so the document sheet stays visible.
            (auxiliaryWindow as? NSPanel)?.isFloatingPanel = false
            actions.orderBack(auxiliaryWindow)
            actions.makeKeyAndOrderFront(hostWindow)
        }
        actions.beginSheet(alert, hostWindow) { [weak auxiliaryWindow = presentation.auxiliaryWindowToRestore] _ in
            guard let auxiliaryWindow else {
                return
            }
            if let auxiliaryPanel = auxiliaryWindow as? NSPanel,
               let auxiliaryWasFloating {
                auxiliaryPanel.isFloatingPanel = auxiliaryWasFloating
            }
            guard auxiliaryWindow.isVisible,
                  auxiliaryWindow.sheetParent == nil else {
                return
            }
            actions.makeKeyAndOrderFront(auxiliaryWindow)
        }
    }
}

enum InstrumentEditorNoteAuditionRoutingAction: Equatable {
    case noteKeyDown(Character, isRepeat: Bool)
    case noteKeyUp(Character)
}

enum InstrumentEditorWindowEventRoutingPolicy {
    static func shouldInspectForNoteAudition(_ eventType: NSEvent.EventType) -> Bool {
        eventType == .keyDown || eventType == .keyUp
    }
}

@MainActor
enum InstrumentEditorNoteAuditionRoutingPolicy {
    private static let protectedKeyCodes: Set<UInt16> = [
        36, 76, // Return and keypad Enter
        48, // Tab
        51, 117, // Backspace and forward Delete
        53, // Escape
        64, 79, 80, 90, 96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120, 122, // F1...F20
        114, 115, 116, 119, 121, 123, 124, 125, 126, // Help and navigation
    ]

    static func action(
        eventType: NSEvent.EventType,
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        isARepeat: Bool,
        isKeyWindow: Bool,
        firstResponder: NSResponder?
    ) -> InstrumentEditorNoteAuditionRoutingAction? {
        guard isKeyWindow,
              eventType == .keyDown || eventType == .keyUp,
              !isTextEditingResponder(firstResponder),
              !protectedKeyCodes.contains(keyCode) else {
            return nil
        }

        let protectedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        guard modifierFlags.intersection(protectedModifiers).isEmpty,
              let character = charactersIgnoringModifiers?.first,
              TrackerNoteKeyMap.isTrackerNoteKey(character) else {
            return nil
        }

        return eventType == .keyDown
            ? .noteKeyDown(character, isRepeat: isARepeat)
            : .noteKeyUp(character)
    }

    private static func isTextEditingResponder(_ responder: NSResponder?) -> Bool {
        responder is NSTextView || responder is NSTextField
    }
}

@MainActor
final class InstrumentEditorKeyboardAuditionRouter {
    var noteKeyDownHandler: InstrumentEditorNoteAuditionKeyDownHandler?
    var noteKeyUpHandler: InstrumentEditorNoteAuditionKeyUpHandler?

    func handle(_ event: NSEvent, isKeyWindow: Bool, firstResponder: NSResponder?) -> Bool {
        switch InstrumentEditorNoteAuditionRoutingPolicy.action(
            eventType: event.type,
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags,
            isARepeat: event.isARepeat,
            isKeyWindow: isKeyWindow,
            firstResponder: firstResponder
        ) {
        case let .noteKeyDown(character, isRepeat):
            return noteKeyDownHandler?(character, isRepeat) == true
        case let .noteKeyUp(character):
            return noteKeyUpHandler?(character) == true
        case nil:
            return false
        }
    }
}

@MainActor
final class InstrumentEditorPanel: NSPanel {
    let keyboardAuditionRouter = InstrumentEditorKeyboardAuditionRouter()

    override func sendEvent(_ event: NSEvent) {
        // Title-bar, traffic-light, and activation events must reach NSPanel untouched.
        guard InstrumentEditorWindowEventRoutingPolicy.shouldInspectForNoteAudition(event.type) else {
            super.sendEvent(event)
            return
        }
        if keyboardAuditionRouter.handle(
            event,
            isKeyWindow: isKeyWindow,
            firstResponder: firstResponder
        ) {
            return
        }
        super.sendEvent(event)
    }
}

enum InstrumentEditorViewIdentifier {
    static let contentView = "instrumentEditor.contentView"
    static let headerPanel = "instrumentEditor.headerPanel"
    static let instrumentListPanel = "instrumentEditor.instrumentListPanel"
    static let sampleSlotsPanel = "instrumentEditor.sampleSlotsPanel"
    static let envelopePanel = "instrumentEditor.envelopePanel"
    static let envelopeGraph = "instrumentEditor.envelopeGraph"
    static let volumeEnvelopeTab = "instrumentEditor.volumeEnvelopeTab"
    static let panningEnvelopeTab = "instrumentEditor.panningEnvelopeTab"
    static let vibratoPanel = "instrumentEditor.vibratoPanel"
    static let defaultsPanel = "instrumentEditor.defaultsPanel"
    static let noteKeymapPanel = "instrumentEditor.noteKeymapPanel"
    static let keymapRangeStrip = "instrumentEditor.keymapRangeStrip"
    static let keymapRangeAssignment = "instrumentEditor.keymapRangeAssignment"
    static let keymapPreviousOctave = "instrumentEditor.keymapPreviousOctave"
    static let keymapNextOctave = "instrumentEditor.keymapNextOctave"
    static let keyboardPlaceholder = "instrumentEditor.keyboardPlaceholder"
    static let readOnlyBadge = "instrumentEditor.readOnlyBadge"
    static let instrumentNameField = "instrumentEditor.instrumentNameField"
    static let sampleVolumeControl = "instrumentEditor.sampleVolumeControl"
    static let sampleVolumeReadout = "instrumentEditor.sampleVolumeReadout"
    static let sampleRelativeNoteControl = "instrumentEditor.sampleRelativeNoteControl"
    static let sampleRelativeNoteReadout = "instrumentEditor.sampleRelativeNoteReadout"
    static let sampleFinetuneControl = "instrumentEditor.sampleFinetuneControl"
    static let sampleFinetuneReadout = "instrumentEditor.sampleFinetuneReadout"
    static let samplePanningControl = "instrumentEditor.samplePanningControl"
    static let samplePanningReadout = "instrumentEditor.samplePanningReadout"
    static let instrumentRowPrefix = "instrumentEditor.instrumentRow."
    static let sampleRowPrefix = "instrumentEditor.sampleRow."
    static let futureControlPrefix = "instrumentEditor.futureControl."
}

@MainActor
final class InstrumentEditorListRowControl: NSControl {
    let slot: Int

    init(frame frameRect: NSRect, slot: Int, isSelected: Bool) {
        self.slot = slot
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = (isSelected
            ? VTXEditorControlTheme.indigoSelection
            : VTXEditorControlTheme.recessedReadoutBackground).cgColor
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override var acceptsFirstResponder: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { event?.type == .leftMouseDown }
    override func accessibilityPerformPress() -> Bool { performPrimarySelection() }

    @discardableResult
    func performPrimarySelection() -> Bool {
        guard isEnabled else { return false }
        window?.makeFirstResponder(self)
        return sendAction(action, to: target)
    }

    static func acceptsPrimarySelection(buttonNumber: Int, clickCount: Int) -> Bool { buttonNumber == 0 && clickCount == 1 }
    override func mouseDown(with event: NSEvent) {
        guard Self.acceptsPrimarySelection(buttonNumber: event.buttonNumber, clickCount: event.clickCount) else { return }
        _ = performPrimarySelection()
    }

    override func mouseDragged(with event: NSEvent) {}
}

enum InstrumentEnvelopeDisplayMode: Equatable {
    case volume
    case panning

    var title: String {
        switch self {
        case .volume: "VOLUME"
        case .panning: "PANNING"
        }
    }
}

enum InstrumentEnvelopeReadout: String, CaseIterable {
    case pointCount
    case sustainState
    case sustainPoint
    case loopState
    case loopStart
    case loopEnd
    case fadeout

    var identifier: String { "instrumentEditor.envelopeReadout.\(rawValue)" }
}

struct InstrumentEditorEnvelopeDisplayState: Equatable {
    let enabled: Bool
    let points: [PlaybackEnvelopePoint]
    let sustainEnabled: Bool
    let sustainPointIndex: Int?
    let loopEnabled: Bool
    let loopStartPointIndex: Int?
    let loopEndPointIndex: Int?
    let fadeout: Int?

    var pointCount: Int { points.count }

    var sustainPoint: PlaybackEnvelopePoint? {
        guard let sustainPointIndex, points.indices.contains(sustainPointIndex) else { return nil }
        return points[sustainPointIndex]
    }

    var loopStartPoint: PlaybackEnvelopePoint? {
        guard let loopStartPointIndex, points.indices.contains(loopStartPointIndex) else { return nil }
        return points[loopStartPointIndex]
    }

    var loopEndPoint: PlaybackEnvelopePoint? {
        guard let loopEndPointIndex, points.indices.contains(loopEndPointIndex) else { return nil }
        return points[loopEndPointIndex]
    }

    init(volumeEnvelope envelope: PlaybackVolumeEnvelope) {
        enabled = envelope.enabled
        points = envelope.points
        sustainEnabled = envelope.sustainEnabled
        sustainPointIndex = envelope.sustainPointIndex
        loopEnabled = envelope.loopEnabled
        loopStartPointIndex = envelope.loopStartPointIndex
        loopEndPointIndex = envelope.loopEndPointIndex
        fadeout = envelope.fadeout
    }

    init(panningEnvelope envelope: PlaybackPanningEnvelope) {
        enabled = envelope.enabled
        points = envelope.points
        sustainEnabled = envelope.sustainEnabled
        sustainPointIndex = envelope.sustainPointIndex
        loopEnabled = envelope.loopEnabled
        loopStartPointIndex = envelope.loopStartPointIndex
        loopEndPointIndex = envelope.loopEndPointIndex
        fadeout = nil
    }
}

struct InstrumentEditorDisplayState: Equatable {
    enum Source: Equatable {
        case none
        case loadedModule
        case editableDocument

        var display: String {
            switch self {
            case .none: "NO DOCUMENT"
            case .loadedModule: "LOADED MODULE PALETTE"
            case .editableDocument: "EDITABLE DOCUMENT PALETTE"
            }
        }

        var compactDisplay: String {
            switch self {
            case .none: "NO DOCUMENT"
            case .loadedModule: "LOADED"
            case .editableDocument: "EDITABLE"
            }
        }
    }

    struct InstrumentSlot: Equatable {
        let slot: Int
        let name: String
        let sampleCount: Int
        let isSelected: Bool

        var slotDisplay: String { String(format: "I%02X", min(255, max(1, slot))) }
    }

    struct SampleSlot: Equatable {
        let slot: Int
        let name: String
        let length: Int
        let loopType: Int
        let loopStart: Int
        let loopLength: Int
        let volume: Float
        let panning: UInt8
        let relativeNote: Int
        let finetune: Int
        let sourceBitDepthBits: Int?
        let isSelected: Bool

        var slotDisplay: String { String(format: "S%02X", min(255, max(1, slot))) }
        var lengthDisplay: String { "\(max(0, length))" }
        var loopModeDisplay: String {
            switch loopType {
            case 0: "None"
            case 1: "Forward"
            case 2: "Ping-pong"
            default: "Unknown (\(loopType))"
            }
        }
        var loopRangeDisplay: String {
            let start = max(0, loopStart)
            let count = max(0, loopLength)
            guard loopType != 0, count > 0 else { return "—" }
            let end = start > Int.max - count ? Int.max : start + count
            return "\(start)..<\(end)"
        }
        var volumeLevel: Int {
            let normalizedVolume = volume.isFinite ? min(1, max(0, volume)) : 0
            return Int((normalizedVolume * 64).rounded())
        }
        var volumeDisplay: String { "\(volumeLevel) / 64" }
        var panningDisplay: String { Self.panningDisplay(panning) }
        static func panningDisplay(_ panning: UInt8) -> String {
            switch panning {
            case 0: "0 · LEFT"
            case PlaybackSample.xmCenterPanning: "128 · CENTER"
            case 255: "255 · RIGHT"
            default: "\(panning) / 255"
            }
        }
        var panSliderValue: Double { Self.panSliderValue(for: panning) }
        static func panSliderValue(for panning: UInt8) -> Double {
            if panning == PlaybackSample.xmCenterPanning {
                return 0
            }
            if panning < PlaybackSample.xmCenterPanning {
                return Double(Int(panning) - 128) / 128.0
            }
            return Double(Int(panning) - 128) / 127.0
        }
        static func panningByte(forPanSliderValue value: Double) -> UInt8 {
            let safeValue = value.isFinite ? min(1, max(-1, value)) : 0
            let byte = safeValue <= 0
                ? 128 + Int((safeValue * 128).rounded())
                : 128 + Int((safeValue * 127).rounded())
            return UInt8(min(255, max(0, byte)))
        }
        var relativeNoteDisplay: String { Self.signedDisplay(relativeNote) }
        var finetuneDisplay: String { Self.signedDisplay(finetune) }
        var bitDepthDisplay: String { sourceBitDepthBits.map { "\($0)-BIT" } ?? "BIT —" }

        init(sample: PlaybackSample, selectedSampleSlot: Int) {
            slot = min(254, max(0, sample.sampleIndex)) + 1
            name = Self.normalizedName(sample.name, fallback: "(unnamed sample)")
            length = sample.sampleLength
            loopType = sample.loopType
            loopStart = sample.loopStart
            loopLength = sample.loopLength
            volume = sample.volume
            panning = sample.panning
            relativeNote = sample.relativeNote
            finetune = sample.finetune
            sourceBitDepthBits = sample.sourceBitDepthBits
            isSelected = slot == selectedSampleSlot
        }

        static func signedDisplay(_ value: Int) -> String {
            value > 0 ? "+\(value)" : "\(value)"
        }

        private static func normalizedName(_ name: String?, fallback: String) -> String {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? fallback : trimmed
        }
    }

    struct KeymapRange: Equatable {
        let startNote: Int
        let endNote: Int
        let sampleSlot: Int?
        let sampleName: String
        let isSelected: Bool

        var sampleDisplay: String {
            sampleSlot.map { String(format: "S%02X", min(255, max(1, $0))) } ?? "—"
        }

        var colorIndex: Int? {
            sampleSlot.map { max(0, $0 - 1) % 3 }
        }
    }

    static let empty = InstrumentEditorDisplayState(
        source: .none,
        instrumentSlots: [],
        selectedInstrumentSlot: nil,
        instrumentName: "No instrument available",
        instrumentNameEditValue: "",
        isInstrumentNameEditable: false,
        isSampleVolumeEditable: false,
        isSampleRelativeNoteEditable: false,
        isSampleFinetuneEditable: false,
        isSamplePanningEditable: false,
        isKeymapRangeAssignmentEnabled: false,
        sampleCount: 0,
        selectedSampleSlot: nil,
        emptySampleDestinationSlot: nil,
        sampleSlots: [],
        volumeEnvelope: nil,
        panningEnvelope: nil,
        autoVibrato: nil,
        keymapRanges: [],
        emptyMessage: "No document instrument palette is available."
    )

    let source: Source
    let instrumentSlots: [InstrumentSlot]
    let selectedInstrumentSlot: Int?
    let instrumentName: String
    let instrumentNameEditValue: String
    let isInstrumentNameEditable: Bool
    let isSampleVolumeEditable: Bool
    let isSampleRelativeNoteEditable: Bool
    let isSampleFinetuneEditable: Bool
    let isSamplePanningEditable: Bool
    let isKeymapRangeAssignmentEnabled: Bool
    let sampleCount: Int
    let selectedSampleSlot: Int?
    let emptySampleDestinationSlot: Int?
    let sampleSlots: [SampleSlot]
    let volumeEnvelope: PlaybackVolumeEnvelope?
    let panningEnvelope: PlaybackPanningEnvelope?
    let autoVibrato: PlaybackInstrumentAutoVibrato?
    let keymapRanges: [KeymapRange]
    let emptyMessage: String
    var isReadOnly: Bool {
        !isInstrumentNameEditable &&
            !isSampleVolumeEditable &&
            !isSampleRelativeNoteEditable &&
            !isSampleFinetuneEditable &&
            !isSamplePanningEditable
    }

    var selectedSample: SampleSlot? {
        sampleSlots.first(where: \.isSelected)
    }

    var hasCanonicalKeymap: Bool {
        guard keymapRanges.first?.startNote == 1,
              keymapRanges.last?.endNote == TrackerNoteKeyMap.maximumNoteValue,
              keymapRanges.allSatisfy({ $0.startNote <= $0.endNote }) else { return false }
        return zip(keymapRanges, keymapRanges.dropFirst()).allSatisfy { pair in
            pair.0.endNote + 1 == pair.1.startNote
        }
    }

    func envelope(for mode: InstrumentEnvelopeDisplayMode) -> InstrumentEditorEnvelopeDisplayState? {
        switch mode {
        case .volume:
            volumeEnvelope.map(InstrumentEditorEnvelopeDisplayState.init(volumeEnvelope:))
        case .panning:
            panningEnvelope.map(InstrumentEditorEnvelopeDisplayState.init(panningEnvelope:))
        }
    }

    var instrumentDisplay: String {
        selectedInstrumentSlot.map { String(format: "I%02X", min(255, max(1, $0))) } ?? "—"
    }

    var selectedSampleDisplay: String {
        selectedSampleSlot.map { String(format: "S%02X", min(255, max(1, $0))) } ?? "—"
    }

    static func loadedModule(
        playbackSong: PlaybackSong?,
        selection: TrackerEditorSelection
    ) -> InstrumentEditorDisplayState {
        make(
            source: .loadedModule,
            palette: playbackSong?.instrumentsByIndex ?? [:],
            selection: selection,
            allowsInstrumentNameEditing: false,
            allowsKeymapRangeAssignment: false
        )
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool = false,
        allowsKeymapRangeAssignment: Bool = true
    ) -> InstrumentEditorDisplayState {
        make(
            source: .editableDocument,
            palette: document.instrumentPalette,
            selection: document.selection,
            allowsInstrumentNameEditing: !isPlaybackActive,
            allowsKeymapRangeAssignment: allowsKeymapRangeAssignment
        )
    }

    private static func make(
        source: Source,
        palette: [Int: PlaybackInstrument],
        selection: TrackerEditorSelection,
        allowsInstrumentNameEditing: Bool,
        allowsKeymapRangeAssignment: Bool
    ) -> InstrumentEditorDisplayState {
        let instrumentSlots = palette
            .filter { (1...255).contains($0.key) }
            .map { slot, instrument in
                InstrumentSlot(
                    slot: slot,
                    name: normalizedName(instrument.name, fallback: "(unnamed instrument)"),
                    sampleCount: instrument.samples.count,
                    isSelected: slot == selection.selectedInstrument
                )
            }
            .sorted { ($0.slot, $0.name) < ($1.slot, $1.name) }

        guard let instrument = palette[selection.selectedInstrument] else {
            let message = palette.isEmpty
                ? "No represented instruments are available."
                : "\(String(format: "I%02X", selection.selectedInstrument)) is not represented in this document palette."
            return InstrumentEditorDisplayState(
                source: source,
                instrumentSlots: instrumentSlots,
                selectedInstrumentSlot: nil,
                instrumentName: "No instrument available",
                instrumentNameEditValue: "",
                isInstrumentNameEditable: false,
                isSampleVolumeEditable: false,
                isSampleRelativeNoteEditable: false,
                isSampleFinetuneEditable: false,
                isSamplePanningEditable: false,
                isKeymapRangeAssignmentEnabled: false,
                sampleCount: 0,
                selectedSampleSlot: nil,
                emptySampleDestinationSlot: nil,
                sampleSlots: [],
                volumeEnvelope: nil,
                panningEnvelope: nil,
                autoVibrato: nil,
                keymapRanges: [],
                emptyMessage: message
            )
        }

        let slots = instrument.samples
            .map { SampleSlot(sample: $0, selectedSampleSlot: selection.selectedSample) }
            .sorted { ($0.slot, $0.name) < ($1.slot, $1.name) }
        let emptySampleDestinationSlot = slots.isEmpty ? selection.selectedSample : nil
        let selectedSampleSlot = slots.contains(where: \.isSelected) || emptySampleDestinationSlot != nil
            ? selection.selectedSample
            : nil
        let selectedRepresentedSample = instrument.sample(selectedSampleSlot: selection.selectedSample)
        let allowsSelectedSampleEditing = allowsInstrumentNameEditing &&
            selectedRepresentedSample.map { $0.sampleLength > 0 && !$0.pcm.isEmpty } == true
        return InstrumentEditorDisplayState(
            source: source,
            instrumentSlots: instrumentSlots,
            selectedInstrumentSlot: selection.selectedInstrument,
            instrumentName: normalizedName(instrument.name, fallback: "(unnamed instrument)"),
            instrumentNameEditValue: instrument.name ?? "",
            isInstrumentNameEditable: allowsInstrumentNameEditing,
            isSampleVolumeEditable: allowsSelectedSampleEditing,
            isSampleRelativeNoteEditable: allowsSelectedSampleEditing,
            isSampleFinetuneEditable: allowsSelectedSampleEditing,
            isSamplePanningEditable: allowsSelectedSampleEditing,
            isKeymapRangeAssignmentEnabled: source == .editableDocument &&
                allowsKeymapRangeAssignment &&
                allowsSelectedSampleEditing &&
                instrument.noteSampleMap?.count == TrackerNoteKeyMap.maximumNoteValue,
            sampleCount: instrument.samples.count,
            selectedSampleSlot: selectedSampleSlot,
            emptySampleDestinationSlot: emptySampleDestinationSlot,
            sampleSlots: slots,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            keymapRanges: makeKeymapRanges(instrument: instrument, selectedSampleSlot: selection.selectedSample),
            emptyMessage: slots.isEmpty
                ? "\(String(format: "S%02X", selection.selectedSample)) is an empty destination; no sample is represented."
                : ""
        )
    }

    private static func makeKeymapRanges(
        instrument: PlaybackInstrument,
        selectedSampleSlot: Int
    ) -> [KeymapRange] {
        guard let map = instrument.noteSampleMap, !map.isEmpty else {
            return []
        }

        var ranges: [KeymapRange] = []
        var rangeStart = 0
        var mappedSampleIndex = map[0]

        func appendRange(endingAt endIndex: Int) {
            let sample = instrument.samples.first { $0.sampleIndex == mappedSampleIndex }
            let slot = sample.map { min(254, max(0, $0.sampleIndex)) + 1 }
            ranges.append(KeymapRange(
                startNote: rangeStart + 1,
                endNote: endIndex + 1,
                sampleSlot: slot,
                sampleName: sample.map { normalizedName($0.name, fallback: "(unnamed sample)") } ?? "Unavailable mapping",
                isSelected: slot == selectedSampleSlot
            ))
        }

        for index in 1..<map.count where map[index] != mappedSampleIndex {
            appendRange(endingAt: index - 1)
            rangeStart = index
            mappedSampleIndex = map[index]
        }
        appendRange(endingAt: map.count - 1)
        return ranges
    }

    private static func normalizedName(_ name: String?, fallback: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}

typealias InstrumentNameEditHandler = (_ zeroBasedInstrumentIndex: Int, _ name: String) -> Bool
typealias SampleVolumeEditHandler =
    (_ zeroBasedInstrumentIndex: Int, _ zeroBasedSampleIndex: Int, _ volume: UInt8) -> Bool
typealias SampleRelativeNoteEditHandler =
    (_ zeroBasedInstrumentIndex: Int, _ zeroBasedSampleIndex: Int, _ relativeNote: Int) -> Bool
typealias SampleFinetuneEditHandler =
    (_ zeroBasedInstrumentIndex: Int, _ zeroBasedSampleIndex: Int, _ finetune: Int) -> Bool
typealias SamplePanningEditHandler =
    (_ zeroBasedInstrumentIndex: Int, _ zeroBasedSampleIndex: Int, _ panning: UInt8) -> Bool

struct InstrumentControlDragSession: Equatable {
    enum Control: Equatable { case volume, finetune, panning }

    let control: Control
    let instrumentSlot: Int
    let sampleSlot: Int
    let originalCommittedValue: Int
    private(set) var currentTransientValue: Int
    let supportedRange: ClosedRange<Int>

    mutating func update(to value: Int) {
        currentTransientValue = min(supportedRange.upperBound, max(supportedRange.lowerBound, value))
    }
}

@MainActor
final class InstrumentEditorWindowPresenter {
    private(set) var windowController: InstrumentEditorWindowController?
    private(set) var keyboardVisibleRange = InstrumentKeyboardVisibleRange.defaultRange

    @discardableResult
    func show(
        displayState: InstrumentEditorDisplayState,
        instrumentSelectionHandler: InstrumentEditorInstrumentSelectionHandler? = nil,
        sampleSelectionHandler: InstrumentEditorSampleSelectionHandler? = nil,
        instrumentNameEditHandler: InstrumentNameEditHandler? = nil,
        sampleVolumeEditHandler: SampleVolumeEditHandler? = nil,
        sampleRelativeNoteEditHandler: SampleRelativeNoteEditHandler? = nil,
        sampleFinetuneEditHandler: SampleFinetuneEditHandler? = nil,
        samplePanningEditHandler: SamplePanningEditHandler? = nil,
        keymapRangeAssignmentHandler: InstrumentKeymapRangeAssignmentHandler? = nil,
        onScreenNoteHandler: InstrumentEditorOnScreenNoteHandler? = nil,
        noteAuditionKeyDownHandler: InstrumentEditorNoteAuditionKeyDownHandler? = nil,
        noteAuditionKeyUpHandler: InstrumentEditorNoteAuditionKeyUpHandler? = nil,
        noteAuditionCancelHandler: InstrumentEditorNoteAuditionCancelHandler? = nil
    ) -> InstrumentEditorWindowController {
        if let windowController {
            windowController.instrumentSelectionHandler = instrumentSelectionHandler
            windowController.sampleSelectionHandler = sampleSelectionHandler
            windowController.instrumentNameEditHandler = instrumentNameEditHandler
            windowController.sampleVolumeEditHandler = sampleVolumeEditHandler
            windowController.sampleRelativeNoteEditHandler = sampleRelativeNoteEditHandler
            windowController.sampleFinetuneEditHandler = sampleFinetuneEditHandler
            windowController.samplePanningEditHandler = samplePanningEditHandler
            windowController.keymapRangeAssignmentHandler = keymapRangeAssignmentHandler
            windowController.onScreenNoteHandler = onScreenNoteHandler
            windowController.noteAuditionKeyDownHandler = noteAuditionKeyDownHandler
            windowController.noteAuditionKeyUpHandler = noteAuditionKeyUpHandler
            windowController.noteAuditionCancelHandler = noteAuditionCancelHandler
            windowController.keyboardVisibleRangeChangeHandler = { [weak self] in self?.keyboardVisibleRange = $0 }
            windowController.apply(displayState: displayState)
            windowController.showWindowAndActivate()
            return windowController
        }

        let controller = InstrumentEditorWindowController(
            displayState: displayState,
            instrumentSelectionHandler: instrumentSelectionHandler,
            sampleSelectionHandler: sampleSelectionHandler,
            instrumentNameEditHandler: instrumentNameEditHandler,
            sampleVolumeEditHandler: sampleVolumeEditHandler,
            sampleRelativeNoteEditHandler: sampleRelativeNoteEditHandler,
            sampleFinetuneEditHandler: sampleFinetuneEditHandler,
            samplePanningEditHandler: samplePanningEditHandler,
            keymapRangeAssignmentHandler: keymapRangeAssignmentHandler,
            onScreenNoteHandler: onScreenNoteHandler,
            keyboardVisibleRange: keyboardVisibleRange,
            keyboardVisibleRangeChangeHandler: { [weak self] in self?.keyboardVisibleRange = $0 },
            noteAuditionKeyDownHandler: noteAuditionKeyDownHandler,
            noteAuditionKeyUpHandler: noteAuditionKeyUpHandler,
            noteAuditionCancelHandler: noteAuditionCancelHandler
        )
        controller.closeHandler = { [weak self, weak controller] in
            guard let self, let controller, self.windowController === controller else { return }
            self.windowController = nil
        }
        windowController = controller
        controller.showWindowAndActivate()
        return controller
    }

    func refresh(displayState: InstrumentEditorDisplayState) {
        windowController?.apply(displayState: displayState)
    }

    @discardableResult
    func cancelOnScreenNoteAudition() -> Bool {
        windowController?.cancelOnScreenNoteAudition() ?? false
    }

    func clearOnScreenPressedState() { windowController?.clearOnScreenPressedState() }

    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        windowController?.synchronizeActivePreviewToken(token)
    }
}

@MainActor
final class InstrumentEditorWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 920, height: 638)
    private var didInstallInitialFirstResponder = false
    var closeHandler: (() -> Void)?
    var instrumentSelectionHandler: InstrumentEditorInstrumentSelectionHandler? {
        didSet { (window?.contentView as? InstrumentEditorView)?.instrumentSelectionHandler = instrumentSelectionHandler }
    }
    var sampleSelectionHandler: InstrumentEditorSampleSelectionHandler? {
        didSet { (window?.contentView as? InstrumentEditorView)?.sampleSelectionHandler = sampleSelectionHandler }
    }
    var instrumentNameEditHandler: InstrumentNameEditHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.instrumentNameEditHandler = instrumentNameEditHandler
        }
    }
    var sampleVolumeEditHandler: SampleVolumeEditHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.sampleVolumeEditHandler = sampleVolumeEditHandler
        }
    }
    var sampleRelativeNoteEditHandler: SampleRelativeNoteEditHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.sampleRelativeNoteEditHandler = sampleRelativeNoteEditHandler
        }
    }
    var sampleFinetuneEditHandler: SampleFinetuneEditHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.sampleFinetuneEditHandler = sampleFinetuneEditHandler
        }
    }
    var samplePanningEditHandler: SamplePanningEditHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.samplePanningEditHandler = samplePanningEditHandler
        }
    }
    var keymapRangeAssignmentHandler: InstrumentKeymapRangeAssignmentHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.keymapRangeAssignmentHandler =
                keymapRangeAssignmentHandler
        }
    }
    var onScreenNoteHandler: InstrumentEditorOnScreenNoteHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.onScreenNoteHandler = onScreenNoteHandler
        }
    }
    var keyboardVisibleRangeChangeHandler: InstrumentKeyboardVisibleRangeChangeHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.keyboardVisibleRangeChangeHandler = keyboardVisibleRangeChangeHandler
        }
    }
    var noteAuditionKeyDownHandler: InstrumentEditorNoteAuditionKeyDownHandler? {
        didSet {
            (window as? InstrumentEditorPanel)?.keyboardAuditionRouter.noteKeyDownHandler = noteAuditionKeyDownHandler
        }
    }
    var noteAuditionKeyUpHandler: InstrumentEditorNoteAuditionKeyUpHandler? {
        didSet {
            (window as? InstrumentEditorPanel)?.keyboardAuditionRouter.noteKeyUpHandler = noteAuditionKeyUpHandler
        }
    }
    var noteAuditionCancelHandler: InstrumentEditorNoteAuditionCancelHandler?

    init(
        displayState: InstrumentEditorDisplayState = .empty,
        instrumentSelectionHandler: InstrumentEditorInstrumentSelectionHandler? = nil,
        sampleSelectionHandler: InstrumentEditorSampleSelectionHandler? = nil,
        instrumentNameEditHandler: InstrumentNameEditHandler? = nil,
        sampleVolumeEditHandler: SampleVolumeEditHandler? = nil,
        sampleRelativeNoteEditHandler: SampleRelativeNoteEditHandler? = nil,
        sampleFinetuneEditHandler: SampleFinetuneEditHandler? = nil,
        samplePanningEditHandler: SamplePanningEditHandler? = nil,
        keymapRangeAssignmentHandler: InstrumentKeymapRangeAssignmentHandler? = nil,
        onScreenNoteHandler: InstrumentEditorOnScreenNoteHandler? = nil,
        keyboardVisibleRange: InstrumentKeyboardVisibleRange = .defaultRange,
        keyboardVisibleRangeChangeHandler: InstrumentKeyboardVisibleRangeChangeHandler? = nil,
        noteAuditionKeyDownHandler: InstrumentEditorNoteAuditionKeyDownHandler? = nil,
        noteAuditionKeyUpHandler: InstrumentEditorNoteAuditionKeyUpHandler? = nil,
        noteAuditionCancelHandler: InstrumentEditorNoteAuditionCancelHandler? = nil
    ) {
        self.instrumentSelectionHandler = instrumentSelectionHandler
        self.sampleSelectionHandler = sampleSelectionHandler
        self.instrumentNameEditHandler = instrumentNameEditHandler
        self.sampleVolumeEditHandler = sampleVolumeEditHandler
        self.sampleRelativeNoteEditHandler = sampleRelativeNoteEditHandler
        self.sampleFinetuneEditHandler = sampleFinetuneEditHandler
        self.samplePanningEditHandler = samplePanningEditHandler
        self.keymapRangeAssignmentHandler = keymapRangeAssignmentHandler
        self.onScreenNoteHandler = onScreenNoteHandler
        self.keyboardVisibleRangeChangeHandler = keyboardVisibleRangeChangeHandler
        self.noteAuditionKeyDownHandler = noteAuditionKeyDownHandler
        self.noteAuditionKeyUpHandler = noteAuditionKeyUpHandler
        self.noteAuditionCancelHandler = noteAuditionCancelHandler
        let contentView = InstrumentEditorView(
            frame: NSRect(origin: .zero, size: Self.contentSize),
            displayState: displayState,
            instrumentSelectionHandler: instrumentSelectionHandler,
            sampleSelectionHandler: sampleSelectionHandler,
            instrumentNameEditHandler: instrumentNameEditHandler,
            sampleVolumeEditHandler: sampleVolumeEditHandler,
            sampleRelativeNoteEditHandler: sampleRelativeNoteEditHandler,
            sampleFinetuneEditHandler: sampleFinetuneEditHandler,
            samplePanningEditHandler: samplePanningEditHandler,
            keymapRangeAssignmentHandler: keymapRangeAssignmentHandler,
            onScreenNoteHandler: onScreenNoteHandler,
            keyboardVisibleRange: keyboardVisibleRange,
            keyboardVisibleRangeChangeHandler: keyboardVisibleRangeChangeHandler
        )
        let panel = InstrumentEditorPanel(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Instrument Editor"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = VTXEditorControlTheme.windowBackground
        panel.contentView = contentView
        panel.contentMinSize = Self.contentSize
        panel.contentMaxSize = Self.contentSize
        panel.setContentSize(Self.contentSize)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.keyboardAuditionRouter.noteKeyDownHandler = noteAuditionKeyDownHandler
        panel.keyboardAuditionRouter.noteKeyUpHandler = noteAuditionKeyUpHandler
        panel.initialFirstResponder = contentView
        panel.center()
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if !didInstallInitialFirstResponder {
            didInstallInitialFirstResponder = true
            if let contentView = window.contentView {
                window.makeFirstResponder(contentView)
            }
        }
    }

    @discardableResult
    func apply(displayState: InstrumentEditorDisplayState) -> Bool {
        guard let view = window?.contentView as? InstrumentEditorView else { return false }
        if view.displayState.source != displayState.source ||
            view.displayState.selectedInstrumentSlot != displayState.selectedInstrumentSlot ||
            view.displayState.selectedSampleSlot != displayState.selectedSampleSlot {
            cancelAuditionForLifecycleTransition(in: view)
        }
        return view.apply(displayState: displayState)
    }

    func clearOnScreenPressedState() { (window?.contentView as? InstrumentEditorView)?.clearOnScreenPressedState() }

    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        (window?.contentView as? InstrumentEditorView)?.synchronizeActivePreviewToken(token)
    }

    @discardableResult
    func cancelOnScreenNoteAudition() -> Bool {
        (window?.contentView as? InstrumentEditorView)?.cancelOnScreenNoteAudition() ?? false
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        if let view = window?.contentView as? InstrumentEditorView {
            view.cancelControlDrag()
            cancelAuditionForLifecycleTransition(in: view, cancelUntrackedPreview: true)
        }
        noteAuditionCancelHandler = nil
        onScreenNoteHandler = nil
        instrumentSelectionHandler = nil
        sampleSelectionHandler = nil
        instrumentNameEditHandler = nil
        sampleVolumeEditHandler = nil
        sampleRelativeNoteEditHandler = nil
        sampleFinetuneEditHandler = nil
        samplePanningEditHandler = nil
        keymapRangeAssignmentHandler = nil
        keyboardVisibleRangeChangeHandler = nil
        noteAuditionKeyDownHandler = nil
        noteAuditionKeyUpHandler = nil
        closeHandler?()
    }

    func windowDidResignKey(_ notification: Notification) {
        if let view = window?.contentView as? InstrumentEditorView {
            view.cancelControlDrag()
            cancelAuditionForLifecycleTransition(in: view)
        }
    }

    private func cancelAuditionForLifecycleTransition(
        in view: InstrumentEditorView,
        cancelUntrackedPreview: Bool = false
    ) {
        let releasedPointer = view.cancelOnScreenNoteAudition()
        if releasedPointer || cancelUntrackedPreview || view.activePreviewToken != nil {
            noteAuditionCancelHandler?()
        }
        view.clearOnScreenPressedState()
    }
}

@MainActor
final class InstrumentEditorView: FlippedEditorView {
    override var acceptsFirstResponder: Bool { true }

    private(set) var displayState: InstrumentEditorDisplayState
    private(set) var envelopeDisplayMode: InstrumentEnvelopeDisplayMode = .volume
    private(set) var activeOnScreenNoteValue: UInt8?
    private(set) var activePreviewToken: EditorNoteAuditionPreviewToken?
    private(set) var keyboardVisibleRange: InstrumentKeyboardVisibleRange
    private(set) var rebuildCount = 0
    private(set) var controlDragSession: InstrumentControlDragSession?
    private var envelopePanelView: NSView?
    private var keymapPanelView: NSView?
    private weak var onScreenKeyboardView: InstrumentEditorKeyboardPlaceholderView?
    private weak var sampleVolumeControl: VTXEditorKnobControl?
    private weak var sampleVolumeReadout: VTXEditorSegmentReadout?
    private weak var sampleFinetuneControl: VTXEditorKnobControl?
    private weak var sampleFinetuneReadout: VTXEditorSegmentReadout?
    private weak var samplePanningControl: VTXEditorPanSliderControl?
    private weak var samplePanningReadout: NSTextField?
    private weak var keymapRangeAssignmentButton: VTXEditorButton?
    private weak var instrumentListScrollView: NSScrollView?
    private weak var sampleListScrollView: NSScrollView?
    private var instrumentRowControls: [Int: InstrumentEditorListRowControl] = [:]
    private var sampleRowControls: [Int: InstrumentEditorListRowControl] = [:]
    var instrumentSelectionHandler: InstrumentEditorInstrumentSelectionHandler?
    var sampleSelectionHandler: InstrumentEditorSampleSelectionHandler?
    var instrumentNameEditHandler: InstrumentNameEditHandler?
    var sampleVolumeEditHandler: SampleVolumeEditHandler?
    var sampleRelativeNoteEditHandler: SampleRelativeNoteEditHandler?
    var sampleFinetuneEditHandler: SampleFinetuneEditHandler?
    var samplePanningEditHandler: SamplePanningEditHandler?
    var keymapRangeAssignmentHandler: InstrumentKeymapRangeAssignmentHandler? {
        didSet { updateKeymapRangeAssignmentButton() }
    }
    var onScreenNoteHandler: InstrumentEditorOnScreenNoteHandler?
    var keyboardVisibleRangeChangeHandler: InstrumentKeyboardVisibleRangeChangeHandler?

    init(
        frame frameRect: NSRect,
        displayState: InstrumentEditorDisplayState = .empty,
        instrumentSelectionHandler: InstrumentEditorInstrumentSelectionHandler? = nil,
        sampleSelectionHandler: InstrumentEditorSampleSelectionHandler? = nil,
        instrumentNameEditHandler: InstrumentNameEditHandler? = nil,
        sampleVolumeEditHandler: SampleVolumeEditHandler? = nil,
        sampleRelativeNoteEditHandler: SampleRelativeNoteEditHandler? = nil,
        sampleFinetuneEditHandler: SampleFinetuneEditHandler? = nil,
        samplePanningEditHandler: SamplePanningEditHandler? = nil,
        keymapRangeAssignmentHandler: InstrumentKeymapRangeAssignmentHandler? = nil,
        onScreenNoteHandler: InstrumentEditorOnScreenNoteHandler? = nil,
        keyboardVisibleRange: InstrumentKeyboardVisibleRange = .defaultRange,
        keyboardVisibleRangeChangeHandler: InstrumentKeyboardVisibleRangeChangeHandler? = nil
    ) {
        self.displayState = displayState
        self.instrumentSelectionHandler = instrumentSelectionHandler
        self.sampleSelectionHandler = sampleSelectionHandler
        self.instrumentNameEditHandler = instrumentNameEditHandler
        self.sampleVolumeEditHandler = sampleVolumeEditHandler
        self.sampleRelativeNoteEditHandler = sampleRelativeNoteEditHandler
        self.sampleFinetuneEditHandler = sampleFinetuneEditHandler
        self.samplePanningEditHandler = samplePanningEditHandler
        self.keymapRangeAssignmentHandler = keymapRangeAssignmentHandler
        self.onScreenNoteHandler = onScreenNoteHandler
        self.keyboardVisibleRange = keyboardVisibleRange
        self.keyboardVisibleRangeChangeHandler = keyboardVisibleRangeChangeHandler
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.contentView)
        style(background: VTXEditorControlTheme.windowBackground)
        buildShell()
    }

    @discardableResult
    func cancelOnScreenNoteAudition() -> Bool {
        onScreenKeyboardView?.cancelActiveNote() ?? false
    }

    func clearOnScreenPressedState() {
        activeOnScreenNoteValue = nil
        activePreviewToken = nil
        onScreenKeyboardView?.clearActiveNote()
        onScreenKeyboardView?.synchronizeActivePreviewToken(nil)
    }

    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        activePreviewToken = token
        onScreenKeyboardView?.synchronizeActivePreviewToken(token)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func apply(displayState: InstrumentEditorDisplayState) -> Bool {
        cancelControlDrag()
        guard self.displayState != displayState else {
            restoreCommittedControlDisplays()
            return false
        }
        let scrollOrigins = [instrumentListScrollView, sampleListScrollView].map {
            $0?.contentView.bounds.origin
        }
        self.displayState = displayState
        rebuildCount += 1
        subviews.forEach { $0.removeFromSuperview() }
        keymapPanelView = nil
        instrumentRowControls.removeAll()
        sampleRowControls.removeAll()
        buildShell()
        for (scrollView, origin) in zip([instrumentListScrollView, sampleListScrollView], scrollOrigins) {
            guard let scrollView, let origin else { continue }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        return true
    }

    /// Cancels an active continuous-control gesture and restores committed display values.
    @discardableResult
    func cancelControlDrag() -> Bool {
        guard let session = controlDragSession else { return false }
        switch session.control {
        case .volume: sampleVolumeControl?.cancelTracking()
        case .finetune: sampleFinetuneControl?.cancelTracking()
        case .panning: samplePanningControl?.cancelTracking()
        }
        if controlDragSession != nil {
            controlDragSession = nil
            restoreCommittedControlDisplay(for: session.control)
        }
        return true
    }

    private func buildShell() {
        addSurface(
            in: self,
            frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1),
            background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.60)
        )

        buildHeader(plainPanel(InstrumentEditorViewIdentifier.headerPanel, NSRect(x: 12, y: 13, width: 896, height: 50)))

        buildInstrumentList(panel(
            InstrumentEditorViewIdentifier.instrumentListPanel,
            title: "Instruments",
            frame: NSRect(x: 12, y: 73, width: 170, height: 195)
        ))
        buildSampleSlots(panel(
            InstrumentEditorViewIdentifier.sampleSlotsPanel,
            title: "Sample slots",
            frame: NSRect(x: 12, y: 278, width: 170, height: 155)
        ))
        buildEnvelopePanel()
        buildVibrato(panel(
            InstrumentEditorViewIdentifier.vibratoPanel,
            title: "Vibrato",
            frame: NSRect(x: 670, y: 73, width: 238, height: 160)
        ))
        buildDefaults(panel(
            InstrumentEditorViewIdentifier.defaultsPanel,
            title: "Defaults",
            frame: NSRect(x: 670, y: 243, width: 238, height: 190)
        ))
        buildKeymapPanel()
    }

    private func buildKeymapPanel() {
        let keymapPanel = panel(
            InstrumentEditorViewIdentifier.noteKeymapPanel,
            title: "Note keymap",
            frame: NSRect(x: 12, y: 443, width: 896, height: 183)
        )
        keymapPanelView = keymapPanel
        buildKeymap(keymapPanel)
    }

    @discardableResult
    func shiftKeyboardVisibleRange(_ direction: InstrumentKeyboardRangeShift) -> Bool {
        let shifted = keyboardVisibleRange.shifted(direction)
        guard shifted != keyboardVisibleRange else { return false }
        keyboardVisibleRange = shifted
        keymapPanelView?.removeFromSuperview()
        buildKeymapPanel()
        keyboardVisibleRangeChangeHandler?(shifted)
        return true
    }

    @objc private func showPreviousKeyboardOctave(_ sender: Any?) { _ = shiftKeyboardVisibleRange(.lower) }
    @objc private func showNextKeyboardOctave(_ sender: Any?) { _ = shiftKeyboardVisibleRange(.higher) }

    private func buildEnvelopePanel() {
        let envelopePanel = panel(
            InstrumentEditorViewIdentifier.envelopePanel,
            title: "Envelope",
            frame: NSRect(x: 192, y: 73, width: 468, height: 360)
        )
        envelopePanelView = envelopePanel
        buildEnvelope(envelopePanel)
    }

    @discardableResult
    func selectEnvelopeDisplayMode(_ mode: InstrumentEnvelopeDisplayMode) -> Bool {
        guard envelopeDisplayMode != mode else { return false }
        envelopeDisplayMode = mode
        envelopePanelView?.removeFromSuperview()
        buildEnvelopePanel()
        return true
    }

    @objc private func showVolumeEnvelope(_ sender: Any?) {
        selectEnvelopeDisplayMode(.volume)
    }

    @objc private func showPanningEnvelope(_ sender: Any?) {
        selectEnvelopeDisplayMode(.panning)
    }

    private func buildHeader(_ panel: NSView) {
        addLabel("INST", to: panel, frame: NSRect(x: 10, y: 20, width: 28, height: 12), color: VTXEditorControlTheme.accentGold, size: 9, weight: .bold)
        addReadout(displayState.instrumentDisplay, to: panel, frame: NSRect(x: 42, y: 13, width: 42, height: 23))

        addLabel("NAME", to: panel, frame: NSRect(x: 96, y: 20, width: 32, height: 12), color: VTXEditorControlTheme.accentGold, size: 9, weight: .bold)
        addInstrumentNameField(to: panel, frame: NSRect(x: 133, y: 13, width: 257, height: 23))

        addDisabledButton("IMPORT XI", id: "importXI", to: panel, frame: NSRect(x: 402, y: 12, width: 92, height: 25))
        addDisabledButton("EXPORT XI", id: "exportXI", to: panel, frame: NSRect(x: 500, y: 12, width: 92, height: 25))

        addLabel("AUDITION", to: panel, frame: NSRect(x: 606, y: 20, width: 51, height: 12), color: VTXEditorControlTheme.accentGold, size: 9, weight: .bold)
        addReadout("C-4", to: panel, frame: NSRect(x: 662, y: 13, width: 42, height: 23))
        addDisabledButton("▶", id: "audition", to: panel, frame: NSRect(x: 710, y: 12, width: 32, height: 25), role: .activePlay)
        addControl(VTXEditorControlFactory.makeIndicatorLED(state: .off, diameter: 8), to: panel, frame: NSRect(x: 750, y: 21, width: 8, height: 8))

        let editableFields = [
            displayState.isInstrumentNameEditable ? "NAME" : nil,
            displayState.isSampleVolumeEditable ? "VOL" : nil,
            displayState.isSampleRelativeNoteEditable ? "REL" : nil,
            displayState.isSampleFinetuneEditable ? "FINE" : nil,
            displayState.isSamplePanningEditable ? "PAN" : nil,
        ].compactMap { $0 }
        let editStatus = editableFields.count == 5
            ? "N/V/R/F/P"
            : editableFields.count > 1
                ? editableFields.joined(separator: "/")
                : editableFields.first.map { "\($0) EDITABLE" } ?? "READ-ONLY"
        let readOnly = VTXEditorControlFactory.makeSegmentReadout(
            value: editStatus,
            fixedWidth: 112
        )
        readOnly.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.readOnlyBadge)
        addControl(readOnly, to: panel, frame: NSRect(x: 774, y: 5, width: 112, height: 23))
        addLabel(
            editableFields.isEmpty ? "EDITING UNAVAILABLE" : "OTHER FIELDS READ-ONLY",
            to: panel,
            frame: NSRect(x: 765, y: 31, width: 130, height: 10),
            color: VTXEditorControlTheme.panelLabelText,
            size: 7.5,
            weight: .bold,
            alignment: .center
        )
    }

    private func addInstrumentNameField(to parent: NSView, frame: NSRect) {
        let isEditable = displayState.isInstrumentNameEditable
        let value = isEditable ? displayState.instrumentNameEditValue : displayState.instrumentName
        let field = VTXEditorControlFactory.makeSegmentReadout(
            value: value,
            fixedWidth: frame.width,
            alignment: .left
        )
        field.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.instrumentNameField)
        field.isEnabled = isEditable
        field.isEditable = isEditable
        field.isSelectable = isEditable
        field.focusRingType = isEditable ? .exterior : .none
        field.placeholderString = isEditable ? "(unnamed instrument)" : nil
        field.cell?.sendsActionOnEndEditing = true
        field.layer?.backgroundColor = (isEditable
            ? VTXEditorControlTheme.interactiveFieldBackground
            : VTXEditorControlTheme.recessedReadoutBackground).cgColor
        field.layer?.borderColor = (isEditable
            ? VTXEditorControlTheme.mutedGoldBorderMedium
            : VTXEditorControlTheme.mutedGoldBorderSubtle).cgColor
        field.target = isEditable ? self : nil
        field.action = isEditable ? #selector(commitInstrumentName(_:)) : nil
        field.toolTip = isEditable
            ? "Edit the selected instrument name and press Return"
            : "Instrument names are editable only in stopped editable documents"
        addControl(field, to: parent, frame: frame)
        nextKeyView = field
        field.nextKeyView = self
    }

    @objc
    private func commitInstrumentName(_ sender: NSTextField) {
        guard displayState.isInstrumentNameEditable,
              let instrumentSlot = displayState.selectedInstrumentSlot,
              instrumentSlot > 0,
              instrumentNameEditHandler?(instrumentSlot - 1, sender.stringValue) == true else {
            sender.stringValue = displayState.instrumentNameEditValue
            return
        }
    }

    private func buildInstrumentList(_ panel: NSView) {
        addLabel(displayState.source.compactDisplay, to: panel, frame: NSRect(x: 78, y: 9, width: 82, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.30), size: 7.5, alignment: .right)
        let frame = NSRect(x: 10, y: 30, width: 150, height: 155)
        let rowHeight: CGFloat = 20
        let contentHeight = max(frame.height, CGFloat(max(1, displayState.instrumentSlots.count)) * rowHeight)
        let rowsView = listDocumentView(frame: frame, contentHeight: contentHeight)

        if displayState.instrumentSlots.isEmpty {
            addEmptyListMessage(displayState.emptyMessage, to: rowsView, width: frame.width, height: frame.height)
        } else {
            for (index, instrument) in displayState.instrumentSlots.enumerated() {
                let row = listRow(
                    in: rowsView,
                    frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: frame.width, height: rowHeight),
                    slot: instrument.slot,
                    isSelected: instrument.isSelected,
                    identifier: InstrumentEditorViewIdentifier.instrumentRowPrefix + instrument.slotDisplay
                )
                row.target = self
                row.action = #selector(selectInstrumentRow(_:))
                row.setAccessibilityLabel("\(instrument.slotDisplay) \(instrument.name)")
                instrumentRowControls[instrument.slot] = row
                addLabel(instrument.slotDisplay, to: row, frame: NSRect(x: 8, y: 4, width: 30, height: 12), color: codeColor(selected: instrument.isSelected), size: 9, weight: .semibold)
                addLabel(instrument.name, to: row, frame: NSRect(x: 42, y: 4, width: 82, height: 12), color: rowTextColor(selected: instrument.isSelected), size: 9)
                addLabel("\(instrument.sampleCount)", to: row, frame: NSRect(x: 128, y: 4, width: 14, height: 12), color: rowTextColor(selected: instrument.isSelected).withAlphaComponent(0.68), size: 8, alignment: .right)
            }
        }
        instrumentListScrollView = addScrollView(
            to: panel, frame: frame, documentView: rowsView,
            rowCount: displayState.instrumentSlots.count, rowHeight: rowHeight,
            selectedRowIndex: displayState.instrumentSlots.firstIndex(where: \.isSelected)
        )
    }

    private func buildSampleSlots(_ panel: NSView) {
        addLabel("\(displayState.sampleCount) SAMPLES", to: panel, frame: NSRect(x: 100, y: 9, width: 60, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.30), size: 7.5, alignment: .right)
        let frame = NSRect(x: 10, y: 30, width: 150, height: 115)
        let rowHeight: CGFloat = 20
        let rowCount = displayState.sampleSlots.count + (displayState.emptySampleDestinationSlot == nil ? 0 : 1)
        let contentHeight = max(frame.height, CGFloat(max(1, rowCount)) * rowHeight)
        let rowsView = listDocumentView(frame: frame, contentHeight: contentHeight)

        if let slot = displayState.emptySampleDestinationSlot {
            let slotDisplay = String(format: "S%02X", slot)
            let row = listRow(
                in: rowsView,
                frame: NSRect(x: 0, y: 0, width: frame.width, height: rowHeight),
                slot: slot,
                isSelected: true,
                identifier: InstrumentEditorViewIdentifier.sampleRowPrefix + slotDisplay
            )
            row.isEnabled = false
            row.setAccessibilityLabel("\(slotDisplay) Empty destination")
            sampleRowControls[slot] = row
            addLabel(slotDisplay, to: row, frame: NSRect(x: 8, y: 4, width: 30, height: 12), color: codeColor(selected: true), size: 9, weight: .semibold)
            addLabel("Empty destination", to: row, frame: NSRect(x: 42, y: 4, width: 100, height: 12), color: rowTextColor(selected: true), size: 9)
        } else if displayState.sampleSlots.isEmpty {
            addEmptyListMessage(displayState.emptyMessage, to: rowsView, width: frame.width, height: frame.height)
        } else {
            for (index, sample) in displayState.sampleSlots.enumerated() {
                let row = listRow(
                    in: rowsView,
                    frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: frame.width, height: rowHeight),
                    slot: sample.slot,
                    isSelected: sample.isSelected,
                    identifier: InstrumentEditorViewIdentifier.sampleRowPrefix + sample.slotDisplay
                )
                row.target = self
                row.action = #selector(selectSampleRow(_:))
                row.setAccessibilityLabel("\(sample.slotDisplay) \(sample.name)")
                sampleRowControls[sample.slot] = row
                addLabel(sample.slotDisplay, to: row, frame: NSRect(x: 8, y: 4, width: 30, height: 12), color: codeColor(selected: sample.isSelected), size: 9, weight: .semibold)
                addLabel(sample.name, to: row, frame: NSRect(x: 42, y: 4, width: 100, height: 12), color: rowTextColor(selected: sample.isSelected), size: 9)
            }
        }
        sampleListScrollView = addScrollView(
            to: panel, frame: frame, documentView: rowsView,
            rowCount: rowCount, rowHeight: rowHeight,
            selectedRowIndex: displayState.emptySampleDestinationSlot == nil
                ? displayState.sampleSlots.firstIndex(where: \.isSelected)
                : 0
        )
    }

    @objc
    private func selectInstrumentRow(_ sender: InstrumentEditorListRowControl) {
        guard displayState.instrumentSlots.contains(where: { $0.slot == sender.slot }) else { return }
        _ = instrumentSelectionHandler?(sender.slot)
        window?.makeFirstResponder(instrumentRowControls[sender.slot] ?? sender)
    }

    @objc
    private func selectSampleRow(_ sender: InstrumentEditorListRowControl) {
        guard displayState.sampleSlots.contains(where: { $0.slot == sender.slot }) else { return }
        _ = sampleSelectionHandler?(sender.slot)
        window?.makeFirstResponder(sampleRowControls[sender.slot] ?? sender)
    }

    private func buildEnvelope(_ panel: NSView) {
        addEnvelopeSelector("VOL", mode: .volume, to: panel, frame: NSRect(x: 70, y: 5, width: 40, height: 25))
        addEnvelopeSelector("PAN", mode: .panning, to: panel, frame: NSRect(x: 114, y: 5, width: 40, height: 25))
        addDisabledButton("+ ADD PT", id: "addEnvelopePoint", to: panel, frame: NSRect(x: 164, y: 5, width: 78, height: 25))
        addDisabledButton("DEL PT", id: "deleteEnvelopePoint", to: panel, frame: NSRect(x: 246, y: 5, width: 72, height: 25))
        addLabel("ENABLE", to: panel, frame: NSRect(x: 326, y: 12, width: 43, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        let envelope = displayState.envelope(for: envelopeDisplayMode)
        let envelopeEnabled = envelope?.enabled == true
        addDisabledButton(envelopeEnabled ? "ON" : "OFF", id: "envelopeEnable", to: panel, frame: NSRect(x: 373, y: 5, width: 42, height: 25))
        addControl(
            VTXEditorControlFactory.makeIndicatorLED(state: envelopeEnabled ? .amberActive : .off, diameter: 8),
            to: panel,
            frame: NSRect(x: 431, y: 13, width: 8, height: 8)
        )

        let graph = InstrumentEditorEnvelopeGraphView(
            frame: NSRect(x: 10, y: 42, width: 448, height: 242),
            mode: envelopeDisplayMode,
            envelope: envelope
        )
        graph.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.envelopeGraph)
        panel.addSubview(graph)

        addLabel("SUSTAIN", to: panel, frame: NSRect(x: 10, y: 307, width: 45, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        addEnvelopeReadout(envelope?.sustainEnabled == true ? "ON" : "OFF", readout: .sustainState, to: panel, frame: NSRect(x: 58, y: 300, width: 46, height: 23))
        addLabel("PT", to: panel, frame: NSRect(x: 108, y: 307, width: 15, height: 11), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addEnvelopeReadout(pointDisplay(envelope?.sustainPointIndex), readout: .sustainPoint, to: panel, frame: NSRect(x: 126, y: 300, width: 34, height: 23))

        addLabel("LOOP", to: panel, frame: NSRect(x: 169, y: 307, width: 29, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        addEnvelopeReadout(envelope?.loopEnabled == true ? "ON" : "OFF", readout: .loopState, to: panel, frame: NSRect(x: 201, y: 300, width: 46, height: 23))
        addLabel("ST", to: panel, frame: NSRect(x: 251, y: 307, width: 15, height: 11), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addEnvelopeReadout(pointDisplay(envelope?.loopStartPointIndex), readout: .loopStart, to: panel, frame: NSRect(x: 269, y: 300, width: 34, height: 23))
        addLabel("EN", to: panel, frame: NSRect(x: 307, y: 307, width: 15, height: 11), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addEnvelopeReadout(pointDisplay(envelope?.loopEndPointIndex), readout: .loopEnd, to: panel, frame: NSRect(x: 325, y: 300, width: 34, height: 23))

        addLabel("FADE", to: panel, frame: NSRect(x: 367, y: 307, width: 28, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        addEnvelopeReadout(envelope?.fadeout.map { String(format: "%04X", max(0, $0)) } ?? "—", readout: .fadeout, to: panel, frame: NSRect(x: 398, y: 300, width: 60, height: 23))

        addLabel("PTS", to: panel, frame: NSRect(x: 10, y: 337, width: 22, height: 11), color: VTXEditorControlTheme.panelLabelText, size: 8, weight: .bold)
        addEnvelopeReadout(String(format: "%02d", envelope?.pointCount ?? 0), readout: .pointCount, to: panel, frame: NSRect(x: 35, y: 330, width: 38, height: 23))
        addLabel("\(envelopeDisplayMode.title) ENVELOPE · DISPLAY ONLY", to: panel, frame: NSRect(x: 82, y: 337, width: 376, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8, alignment: .center)
    }

    private func addEnvelopeSelector(
        _ title: String, mode: InstrumentEnvelopeDisplayMode, to parent: NSView, frame: NSRect
    ) {
        let button = VTXEditorControlFactory.makeButton(
            title: title,
            role: envelopeDisplayMode == mode ? .selected : .normal,
            fixedWidth: frame.width
        )
        button.identifier = NSUserInterfaceItemIdentifier(
            mode == .volume
                ? InstrumentEditorViewIdentifier.volumeEnvelopeTab
                : InstrumentEditorViewIdentifier.panningEnvelopeTab
        )
        button.target = self
        button.action = mode == .volume ? #selector(showVolumeEnvelope(_:)) : #selector(showPanningEnvelope(_:))
        button.toolTip = "Show the represented \(mode.title.lowercased()) envelope read-only"
        addControl(button, to: parent, frame: frame)
    }

    private func buildVibrato(_ panel: NSView) {
        let autoVibrato = displayState.autoVibrato
        let waveforms = [("∿", 75), ("⊓", 104), ("⊿", 133), ("◺", 162)]
        for (index, waveform) in waveforms.enumerated() {
            addDisabledButton(
                waveform.0,
                id: "vibratoWaveform\(index)",
                to: panel,
                frame: NSRect(x: waveform.1, y: 5, width: 26, height: 25),
                role: autoVibrato.map { Int($0.waveformType) == index } == true ? .activePlay : .normal
            )
        }
        let indicatorState: VTXEditorIndicatorLEDState = autoVibrato.map { $0 != .disabled } == true ? .amberActive : .off
        addControl(VTXEditorControlFactory.makeIndicatorLED(state: indicatorState, diameter: 8), to: panel, frame: NSRect(x: 210, y: 13, width: 8, height: 8))

        addDisabledKnob(value: Double(autoVibrato?.sweep ?? 0), minimum: 0, maximum: 255, id: "vibratoSweep", label: "SWEEP", readout: autoVibrato.map { "\($0.sweep)" } ?? "—", to: panel, x: 10)
        addDisabledKnob(value: Double(autoVibrato?.depth ?? 0), minimum: 0, maximum: 255, id: "vibratoDepth", label: "DEPTH", readout: autoVibrato.map { "\($0.depth)" } ?? "—", to: panel, x: 82)
        addDisabledKnob(value: Double(autoVibrato?.rate ?? 0), minimum: 0, maximum: 255, id: "vibratoRate", label: "RATE", readout: autoVibrato.map { "\($0.rate)" } ?? "—", to: panel, x: 154)
    }

    private func buildDefaults(_ panel: NSView) {
        let sample = displayState.selectedSample
        addSampleRelativeNoteControl(sample, to: panel)

        addSampleVolumeControl(sample, to: panel)
        addSampleFinetuneControl(sample, to: panel)

        addLabel("PAN", to: panel, frame: NSRect(x: 10, y: 151, width: 28, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        let pan = VTXEditorControlFactory.makePanSliderControl(
            value: sample?.panSliderValue ?? 0,
            centerDetentThreshold: 0,
            snapsToCenter: false,
            showsCenteredIndicator: sample?.panning == PlaybackSample.xmCenterPanning
        )
        pan.isEnabled = displayState.isSamplePanningEditable
        pan.isContinuous = false
        pan.target = displayState.isSamplePanningEditable ? self : nil
        pan.action = displayState.isSamplePanningEditable ? #selector(commitSamplePanning(_:)) : nil
        pan.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.samplePanningControl)
        pan.setAccessibilityElement(true)
        pan.setAccessibilityRole(.slider)
        pan.setAccessibilityLabel("Sample panning")
        pan.setAccessibilityMinValue(NSNumber(value: 0))
        pan.setAccessibilityMaxValue(NSNumber(value: 255))
        pan.setAccessibilityValue(NSNumber(value: sample?.panning ?? 0))
        pan.trackingHandler = { [weak self, weak pan] event in
            guard let pan else { return }
            self?.handlePanningTracking(event, sender: pan)
        }
        pan.toolTip = displayState.isSamplePanningEditable
            ? "Change the selected sample panning"
            : "Sample panning is editable only for represented samples in stopped editable documents"
        addControl(pan, to: panel, frame: NSRect(x: 52, y: 142, width: 170, height: 32))
        let readout = addLabel(sample?.panningDisplay ?? "— NO SAMPLE", to: panel, frame: NSRect(x: 52, y: 174, width: 170, height: 10), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.42), size: 7.5, alignment: .center)
        readout.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.samplePanningReadout)
        samplePanningControl = pan
        samplePanningReadout = readout
    }

    private func addSampleVolumeControl(
        _ sample: InstrumentEditorDisplayState.SampleSlot?,
        to parent: NSView
    ) {
        let isEditable = displayState.isSampleVolumeEditable
        let x: CGFloat = 24
        let y: CGFloat = 34
        let knob = VTXEditorControlFactory.makeKnobControl(
            value: Double(sample?.volumeLevel ?? 0),
            minimumValue: 0,
            maximumValue: Double(PlaybackSample.xmMaximumVolume),
            isEmphasized: true
        )
        knob.isEnabled = isEditable
        knob.isContinuous = false
        knob.target = isEditable ? self : nil
        knob.action = isEditable ? #selector(commitSampleVolume(_:)) : nil
        knob.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.sampleVolumeControl)
        knob.setAccessibilityElement(true)
        knob.setAccessibilityRole(.slider)
        knob.setAccessibilityLabel("Sample volume")
        knob.setAccessibilityMinValue(NSNumber(value: 0))
        knob.setAccessibilityMaxValue(NSNumber(value: PlaybackSample.xmMaximumVolume))
        knob.setAccessibilityValue(NSNumber(value: sample?.volumeLevel ?? 0))
        knob.trackingHandler = { [weak self, weak knob] event in
            guard let knob else { return }
            self?.handleKnobTracking(event, control: .volume, sender: knob)
        }
        knob.toolTip = isEditable
            ? "Change the selected sample default volume"
            : "Sample volume is editable only for represented samples in stopped editable documents"
        addControl(knob, to: parent, frame: NSRect(x: x, y: y, width: 72, height: 72))
        addLabel("VOLUME", to: parent, frame: NSRect(x: x, y: y + 73, width: 72, height: 10), color: VTXEditorControlTheme.panelLabelText, size: 8, alignment: .center)
        let readout = VTXEditorControlFactory.makeSegmentReadout(
            value: sample.map { String($0.volumeLevel) } ?? "—",
            fixedWidth: 56
        )
        readout.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.sampleVolumeReadout)
        addControl(readout, to: parent, frame: NSRect(x: x + 8, y: y + 88, width: 56, height: 23))
        sampleVolumeControl = knob
        sampleVolumeReadout = readout
    }

    private func addSampleRelativeNoteControl(
        _ sample: InstrumentEditorDisplayState.SampleSlot?,
        to parent: NSView
    ) {
        let isEditable = displayState.isSampleRelativeNoteEditable
        addLabel("REL", to: parent, frame: NSRect(x: 151, y: 11, width: 21, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        let readout = VTXEditorControlFactory.makeSegmentReadout(
            value: sample?.relativeNoteDisplay ?? "—",
            fixedWidth: 32
        )
        readout.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.sampleRelativeNoteReadout)
        addControl(readout, to: parent, frame: NSRect(x: 176, y: 5, width: 32, height: 23))

        let stepper = TrackerStepper()
        stepper.controlSize = .small
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.autorepeat = false
        stepper.minValue = Double(PlaybackSample.xmRelativeNoteRange.lowerBound)
        stepper.maxValue = Double(PlaybackSample.xmRelativeNoteRange.upperBound)
        stepper.integerValue = sample?.relativeNote ?? 0
        stepper.isEnabled = isEditable
        stepper.target = isEditable ? self : nil
        stepper.action = isEditable ? #selector(commitSampleRelativeNote(_:)) : nil
        stepper.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.sampleRelativeNoteControl)
        stepper.toolTip = isEditable
            ? "Change the selected sample relative note"
            : "Sample relative note is editable only for represented samples in stopped editable documents"
        addControl(stepper, to: parent, frame: NSRect(x: 210, y: 5, width: 18, height: 23))
    }

    private func addSampleFinetuneControl(
        _ sample: InstrumentEditorDisplayState.SampleSlot?,
        to parent: NSView
    ) {
        let isEditable = displayState.isSampleFinetuneEditable
        let x: CGFloat = 110
        let y: CGFloat = 34
        let knob = VTXEditorControlFactory.makeKnobControl(
            value: Double(sample?.finetune ?? 0),
            minimumValue: Double(PlaybackSample.xmFinetuneRange.lowerBound),
            maximumValue: Double(PlaybackSample.xmFinetuneRange.upperBound)
        )
        knob.isEnabled = isEditable
        knob.isContinuous = false
        knob.target = isEditable ? self : nil
        knob.action = isEditable ? #selector(commitSampleFinetune(_:)) : nil
        knob.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.sampleFinetuneControl)
        knob.setAccessibilityElement(true)
        knob.setAccessibilityRole(.slider)
        knob.setAccessibilityLabel("Sample finetune")
        knob.setAccessibilityMinValue(NSNumber(value: PlaybackSample.xmFinetuneRange.lowerBound))
        knob.setAccessibilityMaxValue(NSNumber(value: PlaybackSample.xmFinetuneRange.upperBound))
        knob.setAccessibilityValue(NSNumber(value: sample?.finetune ?? 0))
        knob.trackingHandler = { [weak self, weak knob] event in
            guard let knob else { return }
            self?.handleKnobTracking(event, control: .finetune, sender: knob)
        }
        knob.toolTip = isEditable
            ? "Change the selected sample finetune"
            : "Sample finetune is editable only for represented samples in stopped editable documents"
        addControl(knob, to: parent, frame: NSRect(x: x, y: y, width: 72, height: 72))
        addLabel("FINETUNE", to: parent, frame: NSRect(x: x, y: y + 73, width: 72, height: 10), color: VTXEditorControlTheme.panelLabelText, size: 8, alignment: .center)
        let readout = VTXEditorControlFactory.makeSegmentReadout(
            value: sample?.finetuneDisplay ?? "—",
            fixedWidth: 56
        )
        readout.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.sampleFinetuneReadout)
        addControl(readout, to: parent, frame: NSRect(x: x + 8, y: y + 88, width: 56, height: 23))
        sampleFinetuneControl = knob
        sampleFinetuneReadout = readout
    }

    private func handleKnobTracking(
        _ event: VTXEditorContinuousControlTrackingEvent,
        control: InstrumentControlDragSession.Control,
        sender: VTXEditorKnobControl
    ) {
        let range = controlRange(control)
        let value = min(range.upperBound, max(range.lowerBound, Int(event.value.rounded())))
        if event.phase == .changed { sender.setValue(Double(value)) }
        handleControlTracking(event.phase, control: control, value: value)
    }

    private func handlePanningTracking(
        _ event: VTXEditorContinuousControlTrackingEvent,
        sender: VTXEditorPanSliderControl
    ) {
        let panning = InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: event.value)
        if event.phase == .changed {
            sender.setValue(
                InstrumentEditorDisplayState.SampleSlot.panSliderValue(for: panning),
                applyCenterDetent: false
            )
        }
        handleControlTracking(event.phase, control: .panning, value: Int(panning))
    }

    private func handleControlTracking(
        _ phase: VTXEditorContinuousControlTrackingPhase,
        control: InstrumentControlDragSession.Control,
        value: Int
    ) {
        switch phase {
        case .began:
            cancelControlDrag()
            guard isEditable(control),
                  let instrumentSlot = displayState.selectedInstrumentSlot,
                  let sampleSlot = displayState.selectedSampleSlot,
                  let committedValue = committedValue(for: control) else { return }
            controlDragSession = InstrumentControlDragSession(
                control: control,
                instrumentSlot: instrumentSlot,
                sampleSlot: sampleSlot,
                originalCommittedValue: committedValue,
                currentTransientValue: committedValue,
                supportedRange: controlRange(control)
            )
        case .changed, .ended:
            guard var session = controlDragSession,
                  session.control == control,
                  session.instrumentSlot == displayState.selectedInstrumentSlot,
                  session.sampleSlot == displayState.selectedSampleSlot,
                  isEditable(control) else {
                cancelControlDrag()
                return
            }
            session.update(to: value)
            controlDragSession = phase == .ended ? nil : session
            displayControlValue(session.currentTransientValue, for: control)
        case .cancelled:
            guard controlDragSession?.control == control else { return }
            controlDragSession = nil
            restoreCommittedControlDisplay(for: control)
        }
    }

    private func isEditable(_ control: InstrumentControlDragSession.Control) -> Bool {
        switch control {
        case .volume: displayState.isSampleVolumeEditable
        case .finetune: displayState.isSampleFinetuneEditable
        case .panning: displayState.isSamplePanningEditable
        }
    }

    private func controlRange(_ control: InstrumentControlDragSession.Control) -> ClosedRange<Int> {
        switch control {
        case .volume: 0...Int(PlaybackSample.xmMaximumVolume)
        case .finetune: PlaybackSample.xmFinetuneRange
        case .panning: 0...255
        }
    }

    private func committedValue(for control: InstrumentControlDragSession.Control) -> Int? {
        guard let sample = displayState.selectedSample else { return nil }
        return switch control {
        case .volume: sample.volumeLevel
        case .finetune: sample.finetune
        case .panning: Int(sample.panning)
        }
    }

    private func displayControlValue(_ value: Int, for control: InstrumentControlDragSession.Control) {
        switch control {
        case .volume:
            sampleVolumeControl?.setValue(Double(value))
            sampleVolumeControl?.setAccessibilityValue(NSNumber(value: value))
            sampleVolumeReadout?.stringValue = String(value)
        case .finetune:
            sampleFinetuneControl?.setValue(Double(value))
            sampleFinetuneControl?.setAccessibilityValue(NSNumber(value: value))
            sampleFinetuneReadout?.stringValue = InstrumentEditorDisplayState.SampleSlot.signedDisplay(value)
        case .panning:
            let panning = UInt8(min(255, max(0, value)))
            samplePanningControl?.setValue(
                InstrumentEditorDisplayState.SampleSlot.panSliderValue(for: panning),
                applyCenterDetent: false
            )
            samplePanningControl?.setAccessibilityValue(NSNumber(value: panning))
            samplePanningReadout?.stringValue = InstrumentEditorDisplayState.SampleSlot.panningDisplay(panning)
        }
    }

    private func restoreCommittedControlDisplays() {
        [InstrumentControlDragSession.Control.volume, .finetune, .panning]
            .forEach(restoreCommittedControlDisplay(for:))
    }

    private func restoreCommittedControlDisplay(for control: InstrumentControlDragSession.Control) {
        guard let value = committedValue(for: control) else { return }
        displayControlValue(value, for: control)
    }

    @objc
    private func commitSampleVolume(_ sender: VTXEditorKnobControl) {
        let volume = Int(sender.value.rounded())
        if controlRange(.volume).contains(volume) { displayControlValue(volume, for: .volume) }
        guard displayState.isSampleVolumeEditable,
              (0...Int(PlaybackSample.xmMaximumVolume)).contains(volume),
              let instrumentSlot = displayState.selectedInstrumentSlot,
              let sampleSlot = displayState.selectedSampleSlot,
              instrumentSlot > 0,
              sampleSlot > 0,
              sampleVolumeEditHandler?(
                  instrumentSlot - 1,
                  sampleSlot - 1,
                  UInt8(volume)
              ) == true else {
            restoreCommittedControlDisplay(for: .volume)
            return
        }
    }

    @objc
    private func commitSampleRelativeNote(_ sender: TrackerStepper) {
        let relativeNote = sender.integerValue
        guard displayState.isSampleRelativeNoteEditable,
              PlaybackSample.xmRelativeNoteRange.contains(relativeNote),
              let instrumentSlot = displayState.selectedInstrumentSlot,
              let sampleSlot = displayState.selectedSampleSlot,
              instrumentSlot > 0,
              sampleSlot > 0,
              sampleRelativeNoteEditHandler?(
                  instrumentSlot - 1,
                  sampleSlot - 1,
                  relativeNote
              ) == true else {
            sender.integerValue = displayState.selectedSample?.relativeNote ?? 0
            return
        }
    }

    @objc
    private func commitSampleFinetune(_ sender: VTXEditorKnobControl) {
        let finetune = Int(sender.value.rounded())
        if controlRange(.finetune).contains(finetune) { displayControlValue(finetune, for: .finetune) }
        guard displayState.isSampleFinetuneEditable,
              PlaybackSample.xmFinetuneRange.contains(finetune),
              let instrumentSlot = displayState.selectedInstrumentSlot,
              let sampleSlot = displayState.selectedSampleSlot,
              instrumentSlot > 0,
              sampleSlot > 0,
              sampleFinetuneEditHandler?(
                  instrumentSlot - 1,
                  sampleSlot - 1,
                  finetune
              ) == true else {
            restoreCommittedControlDisplay(for: .finetune)
            return
        }
    }

    @objc
    private func commitSamplePanning(_ sender: VTXEditorPanSliderControl) {
        let panning = InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: sender.value)
        displayControlValue(Int(panning), for: .panning)
        guard displayState.isSamplePanningEditable,
              let instrumentSlot = displayState.selectedInstrumentSlot,
              let sampleSlot = displayState.selectedSampleSlot,
              instrumentSlot > 0,
              sampleSlot > 0,
              samplePanningEditHandler?(
                  instrumentSlot - 1,
                  sampleSlot - 1,
                  panning
              ) == true else {
            restoreCommittedControlDisplay(for: .panning)
            return
        }
    }

    private func buildKeymap(_ panel: NSView) {
        addLabel(
            InstrumentEditorCopy.keymapSummary,
            to: panel,
            frame: NSRect(x: 91, y: 9, width: 505, height: 11),
            color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.42),
            size: 8
        )
        addKeymapRangeAssignmentButton(to: panel, frame: NSRect(x: 606, y: 5, width: 106, height: 25))
        addKeyboardRangeButton(.lower, to: panel, frame: NSRect(x: 722, y: 5, width: 78, height: 25))
        addKeyboardRangeButton(.higher, to: panel, frame: NSRect(x: 806, y: 5, width: 80, height: 25))

        let strip = InstrumentEditorKeymapRangeView(
            frame: NSRect(x: 10, y: 34, width: 876, height: 18),
            ranges: displayState.keymapRanges
        )
        strip.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.keymapRangeStrip)
        panel.addSubview(strip)

        let keyboard = InstrumentEditorKeyboardPlaceholderView(
            frame: NSRect(x: 10, y: 52, width: 876, height: 96),
            hasKeymapData: !displayState.keymapRanges.isEmpty,
            activeNoteValue: activeOnScreenNoteValue,
            activePreviewToken: activePreviewToken,
            visibleRange: keyboardVisibleRange,
            noteIntentHandler: { [weak self] intent in
                guard let self else { return false }
                let accepted = self.onScreenNoteHandler?(intent) == true
                switch intent {
                case let .press(noteValue) where accepted: self.activeOnScreenNoteValue = noteValue
                case .release: self.activeOnScreenNoteValue = nil
                default: break
                }
                return accepted
            }
        )
        keyboard.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.keyboardPlaceholder)
        panel.addSubview(keyboard)
        onScreenKeyboardView = keyboard

        addLabel(sampleMetadataSummary, to: panel, frame: NSRect(x: 10, y: 157, width: 876, height: 13), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.52), size: 8.5, alignment: .center)
    }

    private var sampleMetadataSummary: String {
        guard let sample = displayState.selectedSample else {
            return displayState.emptyMessage.isEmpty ? "NO REPRESENTED SAMPLE SELECTED" : displayState.emptyMessage.uppercased()
        }
        return "\(sample.slotDisplay) · \(sample.name) · \(sample.bitDepthDisplay) · LEN \(sample.lengthDisplay) · LOOP \(sample.loopModeDisplay.uppercased()) \(sample.loopRangeDisplay) · VOL \(sample.volumeDisplay) · REL \(sample.relativeNoteDisplay) · FINE \(sample.finetuneDisplay)"
    }

    private func pointDisplay(_ pointIndex: Int?) -> String {
        pointIndex.map { String(format: "%02d", $0 + 1) } ?? "—"
    }

    private func addDisabledKnob(
        value: Double,
        minimum: Double,
        maximum: Double,
        id: String,
        label: String,
        readout: String,
        to parent: NSView,
        x: CGFloat,
        y: CGFloat = 36,
        emphasized: Bool = false
    ) {
        let knob = VTXEditorControlFactory.makeKnobControl(
            value: value,
            minimumValue: minimum,
            maximumValue: maximum,
            isEmphasized: emphasized
        )
        knob.isEnabled = false
        knob.target = nil
        knob.action = nil
        knob.identifier = futureControlIdentifier(id)
        addControl(knob, to: parent, frame: NSRect(x: x, y: y, width: 72, height: 72))
        addLabel(label, to: parent, frame: NSRect(x: x, y: y + 73, width: 72, height: 10), color: VTXEditorControlTheme.panelLabelText, size: 8, alignment: .center)
        addReadout(readout, to: parent, frame: NSRect(x: x + 8, y: y + 88, width: 56, height: 23))
    }

    private func addDisabledButton(
        _ title: String,
        id: String,
        to parent: NSView,
        frame: NSRect,
        role: VTXEditorButtonRole = .normal
    ) {
        let button = VTXEditorControlFactory.makeButton(title: title, role: role, fixedWidth: frame.width)
        button.isEnabled = false
        button.target = nil
        button.action = nil
        button.sendAction(on: [])
        button.identifier = futureControlIdentifier(id)
        button.toolTip = "Read-only shell — editing coming later"
        addControl(button, to: parent, frame: frame)
    }

    private func addKeymapRangeAssignmentButton(to parent: NSView, frame: NSRect) {
        let button = VTXEditorControlFactory.makeButton(title: "MAP RANGE…", fixedWidth: frame.width)
        button.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.keymapRangeAssignment)
        button.setAccessibilityLabel("Map selected sample to note range")
        keymapRangeAssignmentButton = button
        updateKeymapRangeAssignmentButton()
        addControl(button, to: parent, frame: frame)
    }

    private func updateKeymapRangeAssignmentButton() {
        let isEnabled = displayState.isKeymapRangeAssignmentEnabled &&
            keymapRangeAssignmentHandler != nil
        guard let button = keymapRangeAssignmentButton else { return }
        button.isEnabled = isEnabled
        button.target = isEnabled ? self : nil
        button.action = isEnabled ? #selector(requestKeymapRangeAssignment(_:)) : nil
        button.alphaValue = isEnabled ? 1 : 0.38
        button.setAccessibilityEnabled(isEnabled)
        button.toolTip = isEnabled
            ? "Map the selected represented sample to an inclusive note range"
            : "Available only for an editable, stopped document with a represented sample"
    }

    @objc private func requestKeymapRangeAssignment(_ sender: Any?) {
        guard displayState.source == .editableDocument,
              displayState.isKeymapRangeAssignmentEnabled,
              keymapRangeAssignmentButton?.isEnabled == true,
              let keymapRangeAssignmentHandler else { return }
        let focusedNote = [activePreviewToken?.noteValue, activeOnScreenNoteValue]
            .compactMap { $0 }
            .first(where: keyboardVisibleRange.contains)
        _ = keymapRangeAssignmentHandler(focusedNote)
    }

    private func addKeyboardRangeButton(
        _ direction: InstrumentKeyboardRangeShift,
        to parent: NSView,
        frame: NSRect
    ) {
        let isLower = direction == .lower
        let title = isLower
            ? "◀ \(keyboardVisibleRange.startLabel)"
            : "\(keyboardVisibleRange.endLabel) ▶"
        let button = VTXEditorControlFactory.makeButton(title: title, fixedWidth: frame.width)
        button.identifier = NSUserInterfaceItemIdentifier(isLower
            ? InstrumentEditorViewIdentifier.keymapPreviousOctave
            : InstrumentEditorViewIdentifier.keymapNextOctave)
        button.target = self
        button.action = isLower ? #selector(showPreviousKeyboardOctave(_:)) : #selector(showNextKeyboardOctave(_:))
        button.isEnabled = keyboardVisibleRange.canShift(direction)
        button.setAccessibilityLabel(isLower
            ? "Shift piano range down one octave"
            : "Shift piano range up one octave")
        button.setAccessibilityEnabled(button.isEnabled)
        button.toolTip = isLower ? "Show the previous piano octave" : "Show the next piano octave"
        addControl(button, to: parent, frame: frame)
    }

    private func futureControlIdentifier(_ id: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.futureControlPrefix + id)
    }

    private func addReadout(
        _ value: String,
        to parent: NSView,
        frame: NSRect,
        alignment: NSTextAlignment = .center
    ) {
        addControl(
            VTXEditorControlFactory.makeSegmentReadout(value: value, fixedWidth: frame.width, alignment: alignment),
            to: parent,
            frame: frame
        )
    }

    private func addEnvelopeReadout(
        _ value: String, readout: InstrumentEnvelopeReadout, to parent: NSView, frame: NSRect
    ) {
        let field = VTXEditorControlFactory.makeSegmentReadout(value: value, fixedWidth: frame.width)
        field.identifier = NSUserInterfaceItemIdentifier(readout.identifier)
        addControl(field, to: parent, frame: frame)
    }

    private func listDocumentView(frame: NSRect, contentHeight: CGFloat) -> FlippedEditorView {
        let view = FlippedEditorView(frame: NSRect(x: 0, y: 0, width: frame.width, height: contentHeight))
        view.style(background: VTXEditorControlTheme.recessedReadoutBackground)
        return view
    }

    private func listRow(
        in parent: NSView,
        frame: NSRect,
        slot: Int,
        isSelected: Bool,
        identifier: String
    ) -> InstrumentEditorListRowControl {
        let row = InstrumentEditorListRowControl(frame: frame, slot: slot, isSelected: isSelected)
        row.identifier = NSUserInterfaceItemIdentifier(identifier)
        parent.addSubview(row)
        addSurface(
            in: parent,
            frame: NSRect(x: 0, y: frame.maxY - 1, width: frame.width, height: 1),
            background: VTXEditorControlTheme.mutedGoldBorderFaint.withAlphaComponent(0.45)
        )
        return row
    }

    private func addEmptyListMessage(_ message: String, to parent: NSView, width: CGFloat, height: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: message.uppercased())
        label.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        label.textColor = VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28)
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        addControl(label, to: parent, frame: NSRect(x: 8, y: max(8, (height - 48) * 0.5), width: width - 16, height: 48))
    }

    private func addScrollView(
        to parent: NSView,
        frame: NSRect,
        documentView: NSView,
        rowCount: Int,
        rowHeight: CGFloat,
        selectedRowIndex: Int?
    ) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.drawsBackground = false
        scrollView.borderType = .lineBorder
        scrollView.hasVerticalScroller = CGFloat(rowCount) * rowHeight > frame.height
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        parent.addSubview(scrollView)
        if let selectedRowIndex {
            documentView.scrollToVisible(NSRect(x: 0, y: CGFloat(selectedRowIndex) * rowHeight,
                                                width: documentView.bounds.width, height: rowHeight))
        }
        return scrollView
    }

    private func codeColor(selected: Bool) -> NSColor {
        selected ? NSColor.white.withAlphaComponent(0.68) : VTXEditorControlTheme.accentGold.withAlphaComponent(0.55)
    }

    private func rowTextColor(selected: Bool) -> NSColor {
        selected ? .white : VTXEditorControlTheme.warmValueText.withAlphaComponent(0.62)
    }

    private func panel(_ identifier: String, title: String, frame: NSRect) -> NSView {
        let view = plainPanel(identifier, frame)
        addPanelLabel(title, to: view, frame: NSRect(x: 10, y: 10, width: min(130, frame.width - 20), height: 12))
        return view
    }

    private func plainPanel(_ identifier: String, _ frame: NSRect) -> NSView {
        let view = addSurface(
            in: self,
            frame: frame,
            background: VTXEditorControlTheme.panelSurface,
            border: VTXEditorControlTheme.mutedGoldBorderFaint,
            radius: 4
        )
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        return view
    }

    private func addPanelLabel(_ title: String, to parent: NSView, frame: NSRect) {
        addControl(VTXEditorControlFactory.makePanelLabel(title), to: parent, frame: frame)
    }

    @discardableResult
    private func addLabel(
        _ text: String,
        to parent: NSView,
        frame: NSRect,
        color: NSColor,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        addControl(label, to: parent, frame: frame)
        return label
    }

    @discardableResult
    private func addSurface(
        in parent: NSView,
        frame: NSRect,
        background: NSColor,
        border: NSColor? = nil,
        radius: CGFloat = 0
    ) -> FlippedEditorView {
        let view = FlippedEditorView(frame: frame)
        view.style(background: background, border: border, radius: radius)
        parent.addSubview(view)
        return view
    }

    private func addControl(_ view: NSView, to parent: NSView, frame: NSRect) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = frame
        parent.addSubview(view)
    }
}

final class InstrumentEditorEnvelopeGraphView: FlippedEditorView {
    let displayMode: InstrumentEnvelopeDisplayMode
    private(set) var envelope: InstrumentEditorEnvelopeDisplayState?

    init(frame frameRect: NSRect, mode: InstrumentEnvelopeDisplayMode, envelope: InstrumentEditorEnvelopeDisplayState?) {
        displayMode = mode
        self.envelope = envelope
        super.init(frame: frameRect)
        style(
            background: VTXEditorControlTheme.recessedReadoutBackground,
            border: VTXEditorControlTheme.mutedGoldBorderSubtle,
            radius: 3
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawGrid()
        if let emptyStateMessage {
            drawCenteredText(emptyStateMessage)
            return
        }
        guard let envelope else { return }
        drawEnvelope(envelope)
    }

    var emptyStateMessage: String? {
        guard let envelope else {
            return "NO \(displayMode.title) ENVELOPE REPRESENTED"
        }
        guard envelope.points.isEmpty else { return nil }
        if displayMode == .panning, !envelope.enabled {
            return "PANNING ENVELOPE DISABLED / EMPTY"
        }
        if envelope.enabled {
            return "\(displayMode.title) ENVELOPE EMPTY"
        }
        return "NO \(displayMode.title) ENVELOPE REPRESENTED"
    }

    private func drawGrid() {
        VTXEditorControlTheme.accentGold.withAlphaComponent(0.07).setStroke()
        for column in 1..<10 {
            let x = bounds.width * CGFloat(column) / 10
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: 1))
            path.line(to: NSPoint(x: x, y: bounds.height - 1))
            path.stroke()
        }
        for row in 1..<5 {
            let y = bounds.height * CGFloat(row) / 5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1, y: y))
            path.line(to: NSPoint(x: bounds.width - 1, y: y))
            path.stroke()
        }
    }

    private func drawEnvelope(_ envelope: InstrumentEditorEnvelopeDisplayState) {
        let points = envelope.points.sorted { ($0.tick, $0.value) < ($1.tick, $1.value) }
        let maxTick = max(1, points.map(\.tick).max() ?? 1)
        let graphRect = bounds.insetBy(dx: 12, dy: 12)

        if envelope.loopEnabled,
           let start = envelope.loopStartPoint,
           let end = envelope.loopEndPoint {
            let startX = graphX(tick: start.tick, maxTick: maxTick, rect: graphRect)
            let endX = graphX(tick: end.tick, maxTick: maxTick, rect: graphRect)
            VTXEditorControlTheme.indigoSelection.withAlphaComponent(0.30).setFill()
            NSBezierPath(rect: NSRect(x: min(startX, endX), y: graphRect.minY, width: abs(endX - startX), height: graphRect.height)).fill()
        }

        if envelope.sustainEnabled, let sustain = envelope.sustainPoint {
            let x = graphX(tick: sustain.tick, maxTick: maxTick, rect: graphRect)
            let path = NSBezierPath()
            path.setLineDash([3, 3], count: 2, phase: 0)
            path.move(to: NSPoint(x: x, y: graphRect.minY))
            path.line(to: NSPoint(x: x, y: graphRect.maxY))
            VTXEditorControlTheme.accentGold.withAlphaComponent(0.48).setStroke()
            path.stroke()
        }

        let path = NSBezierPath()
        path.lineWidth = 2
        for (index, point) in points.enumerated() {
            let location = graphPoint(point, maxTick: maxTick, rect: graphRect)
            index == 0 ? path.move(to: location) : path.line(to: location)
        }
        VTXEditorControlTheme.accentGold.withAlphaComponent(envelope.enabled ? 1 : 0.48).setStroke()
        path.stroke()

        for point in points {
            let location = graphPoint(point, maxTick: maxTick, rect: graphRect)
            let marker = NSRect(x: location.x - 3.5, y: location.y - 3.5, width: 7, height: 7)
            VTXEditorControlTheme.recessedReadoutBackground.setFill()
            VTXEditorControlTheme.accentGold.withAlphaComponent(envelope.enabled ? 1 : 0.48).setStroke()
            let markerPath = NSBezierPath(ovalIn: marker)
            markerPath.lineWidth = 1.5
            markerPath.fill()
            markerPath.stroke()
        }

        let state = envelope.enabled ? "ENABLED" : "DISABLED"
        drawCornerText("\(displayMode.title) · \(state) · \(envelope.pointCount) PTS · READ-ONLY")
    }

    private func graphX(tick: Int, maxTick: Int, rect: NSRect) -> CGFloat {
        rect.minX + (CGFloat(max(0, tick)) / CGFloat(maxTick) * rect.width)
    }

    private func graphPoint(_ point: PlaybackEnvelopePoint, maxTick: Int, rect: NSRect) -> NSPoint {
        NSPoint(
            x: graphX(tick: point.tick, maxTick: maxTick, rect: rect),
            y: rect.maxY - (CGFloat(point.value) / 64 * rect.height)
        )
    }

    private func drawCenteredText(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.26),
            .paragraphStyle: centeredParagraphStyle(),
        ]
        text.draw(in: NSRect(x: 0, y: bounds.midY - 7, width: bounds.width, height: 14), withAttributes: attributes)
    }

    private func drawCornerText(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7.5, weight: .bold),
            .foregroundColor: VTXEditorControlTheme.panelLabelText,
            .paragraphStyle: rightParagraphStyle(),
        ]
        text.draw(in: NSRect(x: 10, y: 8, width: bounds.width - 20, height: 11), withAttributes: attributes)
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private func rightParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }
}

final class InstrumentEditorKeymapRangeView: FlippedEditorView {
    private let ranges: [InstrumentEditorDisplayState.KeymapRange]

    override var acceptsFirstResponder: Bool { false }

    var ownershipRects: [NSRect] {
        ranges.compactMap { range in
            guard range.startNote <= range.endNote else { return nil }
            return InstrumentKeymapSummaryGeometry.rect(
                for: (range.startNote - 1)...(range.endNote - 1),
                in: bounds
            )
        }
    }

    init(
        frame frameRect: NSRect,
        ranges: [InstrumentEditorDisplayState.KeymapRange]
    ) {
        self.ranges = ranges
        super.init(frame: frameRect)
        style(
            background: VTXEditorControlTheme.recessedReadoutBackground,
            border: VTXEditorControlTheme.mutedGoldBorderSubtle,
            radius: 3
        )
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Instrument sample keymap")
        setAccessibilityHelp("Committed 96-note sample ownership; use Map Range to edit")
        setAccessibilityEnabled(true)
        setAccessibilityValue(ownershipAccessibilityValue)
        toolTip = ranges.isEmpty
            ? "No canonical 96-note keymap is available"
            : "Committed 96-note sample ownership; use MAP RANGE… to edit"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !ranges.isEmpty else {
            drawText("NO NOTE MAP REPRESENTED", in: bounds, color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.25))
            return
        }

        for (range, rect) in zip(ranges, ownershipRects) {
            rangeColor(range).setFill()
            NSBezierPath(rect: rect).fill()
            if range.isSelected {
                NSColor.white.withAlphaComponent(0.65).setStroke()
                let selection = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
                selection.lineWidth = 1
                selection.stroke()
            }
            if rect.width >= 54 {
                let label = range.sampleSlot == nil
                    ? "— · UNAVAILABLE"
                    : "\(range.sampleDisplay) · \(range.sampleName)"
                drawText(label, in: rect.insetBy(dx: 3, dy: 1), color: range.sampleSlot == nil ? VTXEditorControlTheme.warmValueText.withAlphaComponent(0.30) : .white.withAlphaComponent(0.82))
            }
        }
    }

    private var ownershipAccessibilityValue: String {
        guard !ranges.isEmpty else { return "No committed note map represented" }
        let descriptions = ranges.map { range in
            let lower = ModuleMetadataLoader.formatXMNote(UInt8(range.startNote))
            let upper = ModuleMetadataLoader.formatXMNote(UInt8(range.endNote))
            return "\(lower) through \(upper) uses \(range.sampleDisplay)"
        }
        return "Committed ownership: \(descriptions.joined(separator: "; "))"
    }

    private func rangeColor(_ range: InstrumentEditorDisplayState.KeymapRange) -> NSColor {
        guard let colorIndex = range.colorIndex else {
            return VTXEditorControlTheme.interactiveFieldBackground
        }
        let colors = [
            VTXEditorControlTheme.accentGold.withAlphaComponent(0.58),
            VTXEditorControlTheme.playActiveGreen.withAlphaComponent(0.48),
            VTXEditorControlTheme.indigoSelection.withAlphaComponent(0.88),
        ]
        return colors[colorIndex]
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        text.draw(in: rect, withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }
}

struct InstrumentEditorKeyboardLayout {
    struct Key {
        let noteValue: UInt8
        let frame: NSRect
    }

    static let displayedNoteRange = InstrumentKeyboardVisibleRange.defaultRange.noteRange
    let visibleRange: InstrumentKeyboardVisibleRange
    let whiteKeys: [Key]
    let blackKeys: [Key]
    var keys: [Key] { whiteKeys + blackKeys }

    init(bounds: NSRect, visibleRange: InstrumentKeyboardVisibleRange = .defaultRange) {
        self.visibleRange = visibleRange
        let content = bounds.insetBy(dx: 1, dy: 1)
        guard content.width > 0, content.height > 0 else {
            whiteKeys = []
            blackKeys = []
            return
        }

        let whitePitchClasses = Set([0, 2, 4, 5, 7, 9, 11])
        let whiteKeyWidth = content.width / 21
        let blackKeyWidth = whiteKeyWidth * 0.58
        var whites: [Key] = []
        var blacks: [Key] = []
        var whiteIndex = 0
        for noteValue in visibleRange.noteRange {
            let pitchClass = (Int(noteValue) - 1) % 12
            if whitePitchClasses.contains(pitchClass) {
                whites.append(Key(
                    noteValue: noteValue,
                    frame: NSRect(
                        x: content.minX + (CGFloat(whiteIndex) * whiteKeyWidth),
                        y: content.minY,
                        width: whiteKeyWidth,
                        height: content.height
                    )
                ))
                whiteIndex += 1
            } else {
                blacks.append(Key(
                    noteValue: noteValue,
                    frame: NSRect(
                        x: content.minX + (CGFloat(whiteIndex) * whiteKeyWidth) - (blackKeyWidth * 0.5),
                        y: content.minY,
                        width: blackKeyWidth,
                        height: content.height * 0.60
                    )
                ))
            }
        }
        whiteKeys = whites
        blackKeys = blacks
    }

    func noteValue(at point: NSPoint) -> UInt8? {
        // Half-open rectangles make shared white-key boundaries deterministic.
        (blackKeys.first { contains(point, in: $0.frame) } ??
            whiteKeys.first { contains(point, in: $0.frame) })?.noteValue
    }

    private func contains(_ point: NSPoint, in frame: NSRect) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX &&
            point.y >= frame.minY && point.y < frame.maxY
    }
}

final class InstrumentEditorKeyboardPlaceholderView: FlippedEditorView {
    private let hasKeymapData: Bool
    private let visibleRange: InstrumentKeyboardVisibleRange
    private var noteIntentHandler: InstrumentEditorOnScreenNoteHandler?
    private(set) var activeNoteValue: UInt8?
    private(set) var activePreviewToken: EditorNoteAuditionPreviewToken?

    var keyboardLayout: InstrumentEditorKeyboardLayout {
        InstrumentEditorKeyboardLayout(bounds: bounds, visibleRange: visibleRange)
    }

    var highlightedNoteValue: UInt8? {
        guard let noteValue = activePreviewToken?.noteValue,
              visibleRange.contains(noteValue) else { return nil }
        return noteValue
    }

    init(
        frame frameRect: NSRect,
        hasKeymapData: Bool,
        activeNoteValue: UInt8? = nil,
        activePreviewToken: EditorNoteAuditionPreviewToken? = nil,
        visibleRange: InstrumentKeyboardVisibleRange = .defaultRange,
        noteIntentHandler: InstrumentEditorOnScreenNoteHandler? = nil
    ) {
        self.hasKeymapData = hasKeymapData
        self.activeNoteValue = activeNoteValue
        self.activePreviewToken = activePreviewToken
        self.visibleRange = visibleRange
        self.noteIntentHandler = noteIntentHandler
        super.init(frame: frameRect)
        style(
            background: VTXEditorControlTheme.recessedReadoutBackground,
            border: VTXEditorControlTheme.mutedGoldBorderMedium,
            radius: 3
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        return keyboardLayout.noteValue(at: localPoint) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { event?.type == .leftMouseDown }

    override func mouseDown(with event: NSEvent) {
        _ = handlePointerDown(at: convert(event.locationInWindow, from: nil), buttonNumber: event.buttonNumber)
    }

    override func mouseDragged(with event: NSEvent) { _ = handlePointerDrag(to: convert(event.locationInWindow, from: nil)) }

    override func mouseUp(with event: NSEvent) { _ = handlePointerUp() }

    @discardableResult
    func handlePointerDown(at point: NSPoint, buttonNumber: Int) -> Bool {
        guard buttonNumber == 0 else { return false }
        let noteValue = keyboardLayout.noteValue(at: point)
        let hadActiveNote = releaseActiveNote()
        guard let noteValue else { return hadActiveNote }
        if noteIntentHandler?(.press(noteValue)) == true {
            activeNoteValue = noteValue
            needsDisplay = true
        }
        return true
    }

    @discardableResult
    func handlePointerDrag(to point: NSPoint) -> Bool {
        let noteValue = keyboardLayout.noteValue(at: point)
        guard noteValue != activeNoteValue else { return activeNoteValue != nil }
        let hadActiveNote = releaseActiveNote()
        guard let noteValue else { return hadActiveNote }
        if noteIntentHandler?(.press(noteValue)) == true {
            activeNoteValue = noteValue
            needsDisplay = true
        }
        return true
    }

    @discardableResult func handlePointerUp() -> Bool { releaseActiveNote() }

    @discardableResult func cancelActiveNote() -> Bool { releaseActiveNote() }

    func clearActiveNote() {
        guard activeNoteValue != nil else { return }
        activeNoteValue = nil
        needsDisplay = true
    }

    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        guard activePreviewToken != token else { return }
        activePreviewToken = token
        needsDisplay = true
    }

    @discardableResult
    private func releaseActiveNote() -> Bool {
        guard let noteValue = activeNoteValue else { return false }
        activeNoteValue = nil
        needsDisplay = true
        return noteIntentHandler?(.release(noteValue)) == true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let layout = keyboardLayout
        let whiteFill = VTXEditorControlTheme.warmValueText.withAlphaComponent(hasKeymapData ? 0.78 : 0.46)

        for key in layout.whiteKeys {
            drawKey(
                key,
                normalFill: whiteFill,
                normalStroke: VTXEditorControlTheme.recessedReadoutBackground.withAlphaComponent(0.72)
            )
        }
        for key in layout.blackKeys {
            drawKey(
                key,
                normalFill: VTXEditorControlTheme.interactiveFieldBackground.withAlphaComponent(hasKeymapData ? 1 : 0.82),
                normalStroke: VTXEditorControlTheme.recessedReadoutBackground
            )
        }

        let content = bounds.insetBy(dx: 1, dy: 1)
        VTXEditorControlTheme.accentGold.withAlphaComponent(0.38).setFill()
        NSBezierPath(rect: NSRect(x: content.minX, y: content.maxY - 5, width: content.width, height: 5)).fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        InstrumentEditorCopy.auditionKeyboard.draw(
            in: NSRect(x: 0, y: bounds.height - 18, width: bounds.width, height: 11),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 7.5, weight: .bold),
                .foregroundColor: VTXEditorControlTheme.recessedReadoutBackground.withAlphaComponent(0.68),
                .paragraphStyle: style,
            ]
        )
    }

    private func drawKey(_ key: InstrumentEditorKeyboardLayout.Key, normalFill: NSColor, normalStroke: NSColor) {
        let isPressed = key.noteValue == highlightedNoteValue
        (isPressed ? VTXEditorControlTheme.indigoSelection : normalFill).setFill()
        (isPressed ? VTXEditorControlTheme.accentGold : normalStroke).setStroke()
        let path = NSBezierPath(rect: key.frame)
        path.lineWidth = isPressed ? 2 : 1
        path.fill()
        path.stroke()
    }
}
