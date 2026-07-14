import AppKit

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
    static let keyboardPlaceholder = "instrumentEditor.keyboardPlaceholder"
    static let readOnlyBadge = "instrumentEditor.readOnlyBadge"
    static let instrumentNameField = "instrumentEditor.instrumentNameField"
    static let sampleVolumeControl = "instrumentEditor.sampleVolumeControl"
    static let sampleVolumeReadout = "instrumentEditor.sampleVolumeReadout"
    static let samplePanningControl = "instrumentEditor.samplePanningControl"
    static let samplePanningReadout = "instrumentEditor.samplePanningReadout"
    static let instrumentRowPrefix = "instrumentEditor.instrumentRow."
    static let sampleRowPrefix = "instrumentEditor.sampleRow."
    static let futureControlPrefix = "instrumentEditor.futureControl."
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
        var panningDisplay: String {
            switch panning {
            case 0: "0 · LEFT"
            case PlaybackSample.xmCenterPanning: "128 · CENTER"
            case 255: "255 · RIGHT"
            default: "\(panning) / 255"
            }
        }
        var panSliderValue: Double {
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
        var relativeNoteDisplay: String { Self.signed(relativeNote) }
        var finetuneDisplay: String { Self.signed(finetune) }

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
            isSelected = slot == selectedSampleSlot
        }

        private static func signed(_ value: Int) -> String {
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
        isSamplePanningEditable: false,
        sampleCount: 0,
        selectedSampleSlot: nil,
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
    let isSamplePanningEditable: Bool
    let sampleCount: Int
    let selectedSampleSlot: Int?
    let sampleSlots: [SampleSlot]
    let volumeEnvelope: PlaybackVolumeEnvelope?
    let panningEnvelope: PlaybackPanningEnvelope?
    let autoVibrato: PlaybackInstrumentAutoVibrato?
    let keymapRanges: [KeymapRange]
    let emptyMessage: String
    var isReadOnly: Bool {
        !isInstrumentNameEditable && !isSampleVolumeEditable && !isSamplePanningEditable
    }

    var selectedSample: SampleSlot? {
        sampleSlots.first(where: \.isSelected)
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
            allowsInstrumentNameEditing: false
        )
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool = false
    ) -> InstrumentEditorDisplayState {
        make(
            source: .editableDocument,
            palette: document.instrumentPalette,
            selection: document.selection,
            allowsInstrumentNameEditing: !isPlaybackActive
        )
    }

    private static func make(
        source: Source,
        palette: [Int: PlaybackInstrument],
        selection: TrackerEditorSelection,
        allowsInstrumentNameEditing: Bool
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
                isSamplePanningEditable: false,
                sampleCount: 0,
                selectedSampleSlot: nil,
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
        let selectedSampleSlot = slots.contains(where: \.isSelected) ? selection.selectedSample : nil
        let selectedRepresentedSample = instrument.sample(selectedSampleSlot: selection.selectedSample)
        return InstrumentEditorDisplayState(
            source: source,
            instrumentSlots: instrumentSlots,
            selectedInstrumentSlot: selection.selectedInstrument,
            instrumentName: normalizedName(instrument.name, fallback: "(unnamed instrument)"),
            instrumentNameEditValue: instrument.name ?? "",
            isInstrumentNameEditable: allowsInstrumentNameEditing,
            isSampleVolumeEditable: allowsInstrumentNameEditing &&
                selectedRepresentedSample.map { $0.sampleLength > 0 && !$0.pcm.isEmpty } == true,
            isSamplePanningEditable: allowsInstrumentNameEditing &&
                selectedRepresentedSample.map { $0.sampleLength > 0 && !$0.pcm.isEmpty } == true,
            sampleCount: instrument.samples.count,
            selectedSampleSlot: selectedSampleSlot,
            sampleSlots: slots,
            volumeEnvelope: instrument.volumeEnvelope,
            panningEnvelope: instrument.panningEnvelope,
            autoVibrato: instrument.autoVibrato,
            keymapRanges: makeKeymapRanges(instrument: instrument, selectedSampleSlot: selection.selectedSample),
            emptyMessage: slots.isEmpty ? "This instrument has no represented sample slots." : ""
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
typealias SamplePanningEditHandler =
    (_ zeroBasedInstrumentIndex: Int, _ zeroBasedSampleIndex: Int, _ panning: UInt8) -> Bool

@MainActor
final class InstrumentEditorWindowPresenter {
    private(set) var windowController: InstrumentEditorWindowController?

    @discardableResult
    func show(
        displayState: InstrumentEditorDisplayState,
        instrumentNameEditHandler: InstrumentNameEditHandler? = nil,
        sampleVolumeEditHandler: SampleVolumeEditHandler? = nil,
        samplePanningEditHandler: SamplePanningEditHandler? = nil
    ) -> InstrumentEditorWindowController {
        if let windowController {
            windowController.instrumentNameEditHandler = instrumentNameEditHandler
            windowController.sampleVolumeEditHandler = sampleVolumeEditHandler
            windowController.samplePanningEditHandler = samplePanningEditHandler
            windowController.apply(displayState: displayState)
            windowController.showWindowAndActivate()
            return windowController
        }

        let controller = InstrumentEditorWindowController(
            displayState: displayState,
            instrumentNameEditHandler: instrumentNameEditHandler,
            sampleVolumeEditHandler: sampleVolumeEditHandler,
            samplePanningEditHandler: samplePanningEditHandler
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
}

@MainActor
final class InstrumentEditorWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 920, height: 638)
    var closeHandler: (() -> Void)?
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
    var samplePanningEditHandler: SamplePanningEditHandler? {
        didSet {
            (window?.contentView as? InstrumentEditorView)?.samplePanningEditHandler = samplePanningEditHandler
        }
    }

    init(
        displayState: InstrumentEditorDisplayState = .empty,
        instrumentNameEditHandler: InstrumentNameEditHandler? = nil,
        sampleVolumeEditHandler: SampleVolumeEditHandler? = nil,
        samplePanningEditHandler: SamplePanningEditHandler? = nil
    ) {
        self.instrumentNameEditHandler = instrumentNameEditHandler
        self.sampleVolumeEditHandler = sampleVolumeEditHandler
        self.samplePanningEditHandler = samplePanningEditHandler
        let contentView = InstrumentEditorView(
            frame: NSRect(origin: .zero, size: Self.contentSize),
            displayState: displayState,
            instrumentNameEditHandler: instrumentNameEditHandler,
            sampleVolumeEditHandler: sampleVolumeEditHandler,
            samplePanningEditHandler: samplePanningEditHandler
        )
        let panel = NSPanel(
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
    }

    @discardableResult
    func apply(displayState: InstrumentEditorDisplayState) -> Bool {
        (window?.contentView as? InstrumentEditorView)?.apply(displayState: displayState) ?? false
    }

    func windowWillClose(_ notification: Notification) {
        closeHandler?()
    }
}

@MainActor
final class InstrumentEditorView: FlippedEditorView {
    private(set) var displayState: InstrumentEditorDisplayState
    private(set) var envelopeDisplayMode: InstrumentEnvelopeDisplayMode = .volume
    private(set) var rebuildCount = 0
    private var envelopePanelView: NSView?
    var instrumentNameEditHandler: InstrumentNameEditHandler?
    var sampleVolumeEditHandler: SampleVolumeEditHandler?
    var samplePanningEditHandler: SamplePanningEditHandler?

    init(
        frame frameRect: NSRect,
        displayState: InstrumentEditorDisplayState = .empty,
        instrumentNameEditHandler: InstrumentNameEditHandler? = nil,
        sampleVolumeEditHandler: SampleVolumeEditHandler? = nil,
        samplePanningEditHandler: SamplePanningEditHandler? = nil
    ) {
        self.displayState = displayState
        self.instrumentNameEditHandler = instrumentNameEditHandler
        self.sampleVolumeEditHandler = sampleVolumeEditHandler
        self.samplePanningEditHandler = samplePanningEditHandler
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.contentView)
        style(background: VTXEditorControlTheme.windowBackground)
        buildShell()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func apply(displayState: InstrumentEditorDisplayState) -> Bool {
        guard self.displayState != displayState else { return false }
        self.displayState = displayState
        rebuildCount += 1
        subviews.forEach { $0.removeFromSuperview() }
        buildShell()
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
        buildKeymap(panel(
            InstrumentEditorViewIdentifier.noteKeymapPanel,
            title: "Note keymap",
            frame: NSRect(x: 12, y: 443, width: 896, height: 183)
        ))
    }

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
            displayState.isSamplePanningEditable ? "PAN" : nil,
        ].compactMap { $0 }
        let editStatus = editableFields.count > 1
            ? editableFields.joined(separator: " + ")
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
                    isSelected: instrument.isSelected,
                    identifier: InstrumentEditorViewIdentifier.instrumentRowPrefix + instrument.slotDisplay
                )
                addLabel(instrument.slotDisplay, to: row, frame: NSRect(x: 8, y: 4, width: 30, height: 12), color: codeColor(selected: instrument.isSelected), size: 9, weight: .semibold)
                addLabel(instrument.name, to: row, frame: NSRect(x: 42, y: 4, width: 82, height: 12), color: rowTextColor(selected: instrument.isSelected), size: 9)
                addLabel("\(instrument.sampleCount)", to: row, frame: NSRect(x: 128, y: 4, width: 14, height: 12), color: rowTextColor(selected: instrument.isSelected).withAlphaComponent(0.68), size: 8, alignment: .right)
            }
        }
        addScrollView(to: panel, frame: frame, documentView: rowsView, rowCount: displayState.instrumentSlots.count, rowHeight: rowHeight)
    }

    private func buildSampleSlots(_ panel: NSView) {
        addLabel("\(displayState.sampleCount) SHOWN", to: panel, frame: NSRect(x: 100, y: 9, width: 60, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.30), size: 7.5, alignment: .right)
        let frame = NSRect(x: 10, y: 30, width: 150, height: 115)
        let rowHeight: CGFloat = 20
        let contentHeight = max(frame.height, CGFloat(max(1, displayState.sampleSlots.count)) * rowHeight)
        let rowsView = listDocumentView(frame: frame, contentHeight: contentHeight)

        if displayState.sampleSlots.isEmpty {
            addEmptyListMessage(displayState.emptyMessage, to: rowsView, width: frame.width, height: frame.height)
        } else {
            for (index, sample) in displayState.sampleSlots.enumerated() {
                let row = listRow(
                    in: rowsView,
                    frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: frame.width, height: rowHeight),
                    isSelected: sample.isSelected,
                    identifier: InstrumentEditorViewIdentifier.sampleRowPrefix + sample.slotDisplay
                )
                addLabel(sample.slotDisplay, to: row, frame: NSRect(x: 8, y: 4, width: 30, height: 12), color: codeColor(selected: sample.isSelected), size: 9, weight: .semibold)
                addLabel(sample.name, to: row, frame: NSRect(x: 42, y: 4, width: 100, height: 12), color: rowTextColor(selected: sample.isSelected), size: 9)
            }
        }
        addScrollView(to: panel, frame: frame, documentView: rowsView, rowCount: displayState.sampleSlots.count, rowHeight: rowHeight)
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
        addLabel("REL", to: panel, frame: NSRect(x: 151, y: 11, width: 21, height: 11), color: VTXEditorControlTheme.accentGold, size: 8, weight: .bold)
        addReadout(sample?.relativeNoteDisplay ?? "—", to: panel, frame: NSRect(x: 176, y: 5, width: 52, height: 23))

        addSampleVolumeControl(sample, to: panel)
        addDisabledKnob(value: Double(sample?.finetune ?? 0), minimum: -128, maximum: 127, id: "defaultFinetune", label: "FINETUNE", readout: sample?.finetuneDisplay ?? "—", to: panel, x: 110, y: 34)

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
        pan.toolTip = displayState.isSamplePanningEditable
            ? "Change the selected sample panning"
            : "Sample panning is editable only for represented samples in stopped editable documents"
        addControl(pan, to: panel, frame: NSRect(x: 52, y: 142, width: 170, height: 32))
        let readout = addLabel(sample?.panningDisplay ?? "— NO SAMPLE", to: panel, frame: NSRect(x: 52, y: 174, width: 170, height: 10), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.42), size: 7.5, alignment: .center)
        readout.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.samplePanningReadout)
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
    }

    @objc
    private func commitSampleVolume(_ sender: VTXEditorKnobControl) {
        let volume = Int(sender.value.rounded())
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
            sender.setValue(Double(displayState.selectedSample?.volumeLevel ?? 0))
            return
        }
    }

    @objc
    private func commitSamplePanning(_ sender: VTXEditorPanSliderControl) {
        guard displayState.isSamplePanningEditable,
              let instrumentSlot = displayState.selectedInstrumentSlot,
              let sampleSlot = displayState.selectedSampleSlot,
              instrumentSlot > 0,
              sampleSlot > 0,
              samplePanningEditHandler?(
                  instrumentSlot - 1,
                  sampleSlot - 1,
                  InstrumentEditorDisplayState.SampleSlot.panningByte(forPanSliderValue: sender.value)
              ) == true else {
            sender.setValue(displayState.selectedSample?.panSliderValue ?? 0, applyCenterDetent: false)
            return
        }
    }

    private func buildKeymap(_ panel: NSView) {
        addLabel("FULL 96-NOTE MAP SUMMARY · READ-ONLY · ASSIGNMENT/AUDITION LATER", to: panel, frame: NSRect(x: 91, y: 9, width: 560, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.32), size: 8)
        addDisabledButton("◀ C-2", id: "keymapPreviousOctave", to: panel, frame: NSRect(x: 722, y: 5, width: 78, height: 25))
        addDisabledButton("C-4 ▶", id: "keymapNextOctave", to: panel, frame: NSRect(x: 806, y: 5, width: 80, height: 25))

        let strip = InstrumentEditorKeymapRangeView(
            frame: NSRect(x: 10, y: 34, width: 876, height: 18),
            ranges: displayState.keymapRanges
        )
        strip.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.keymapRangeStrip)
        panel.addSubview(strip)

        let keyboard = InstrumentEditorKeyboardPlaceholderView(
            frame: NSRect(x: 10, y: 52, width: 876, height: 96),
            hasKeymapData: !displayState.keymapRanges.isEmpty
        )
        keyboard.identifier = NSUserInterfaceItemIdentifier(InstrumentEditorViewIdentifier.keyboardPlaceholder)
        panel.addSubview(keyboard)

        addLabel(sampleMetadataSummary, to: panel, frame: NSRect(x: 10, y: 157, width: 876, height: 13), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.52), size: 8.5, alignment: .center)
    }

    private var sampleMetadataSummary: String {
        guard let sample = displayState.selectedSample else {
            return displayState.emptyMessage.isEmpty ? "NO REPRESENTED SAMPLE SELECTED" : displayState.emptyMessage.uppercased()
        }
        return "\(sample.slotDisplay) · \(sample.name) · LEN \(sample.lengthDisplay) · LOOP \(sample.loopModeDisplay.uppercased()) \(sample.loopRangeDisplay) · VOL \(sample.volumeDisplay) · REL \(sample.relativeNoteDisplay) · FINE \(sample.finetuneDisplay)"
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
        isSelected: Bool,
        identifier: String
    ) -> NSView {
        let row = addSurface(
            in: parent,
            frame: frame,
            background: isSelected ? VTXEditorControlTheme.indigoSelection : VTXEditorControlTheme.recessedReadoutBackground
        )
        row.identifier = NSUserInterfaceItemIdentifier(identifier)
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
        rowHeight: CGFloat
    ) {
        let scrollView = NSScrollView(frame: frame)
        scrollView.drawsBackground = false
        scrollView.borderType = .lineBorder
        scrollView.hasVerticalScroller = CGFloat(rowCount) * rowHeight > frame.height
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        parent.addSubview(scrollView)
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

    init(frame frameRect: NSRect, ranges: [InstrumentEditorDisplayState.KeymapRange]) {
        self.ranges = ranges
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
        guard !ranges.isEmpty else {
            drawText("NO NOTE MAP REPRESENTED", in: bounds, color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.25))
            return
        }

        let content = bounds.insetBy(dx: 1, dy: 1)
        for range in ranges {
            let startFraction = CGFloat(max(0, range.startNote - 1)) / 96
            let noteCount = max(1, range.endNote - range.startNote + 1)
            let rect = NSRect(
                x: content.minX + (startFraction * content.width),
                y: content.minY,
                width: CGFloat(noteCount) / 96 * content.width,
                height: content.height
            )
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

final class InstrumentEditorKeyboardPlaceholderView: FlippedEditorView {
    private let hasKeymapData: Bool

    init(frame frameRect: NSRect, hasKeymapData: Bool) {
        self.hasKeymapData = hasKeymapData
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
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let content = bounds.insetBy(dx: 1, dy: 1)
        let whiteKeyCount = 21
        let keyWidth = content.width / CGFloat(whiteKeyCount)
        let whiteFill = VTXEditorControlTheme.warmValueText.withAlphaComponent(hasKeymapData ? 0.78 : 0.46)

        for index in 0..<whiteKeyCount {
            let rect = NSRect(
                x: content.minX + (CGFloat(index) * keyWidth),
                y: content.minY,
                width: keyWidth,
                height: content.height
            )
            whiteFill.setFill()
            VTXEditorControlTheme.recessedReadoutBackground.withAlphaComponent(0.72).setStroke()
            let path = NSBezierPath(rect: rect)
            path.fill()
            path.stroke()
        }

        let blackWidth = keyWidth * 0.58
        let blackHeight = content.height * 0.60
        let blackAfterWhite = Set([0, 1, 3, 4, 5])
        for index in 0..<(whiteKeyCount - 1) where blackAfterWhite.contains(index % 7) {
            let x = content.minX + (CGFloat(index + 1) * keyWidth) - (blackWidth * 0.5)
            VTXEditorControlTheme.interactiveFieldBackground.withAlphaComponent(hasKeymapData ? 1 : 0.82).setFill()
            NSBezierPath(rect: NSRect(x: x, y: content.minY, width: blackWidth, height: blackHeight)).fill()
        }

        VTXEditorControlTheme.accentGold.withAlphaComponent(0.38).setFill()
        NSBezierPath(rect: NSRect(x: content.minX, y: content.maxY - 5, width: content.width, height: 5)).fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        "KEYMAP PREVIEW · READ-ONLY".draw(
            in: NSRect(x: 0, y: bounds.height - 18, width: bounds.width, height: 11),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 7.5, weight: .bold),
                .foregroundColor: VTXEditorControlTheme.recessedReadoutBackground.withAlphaComponent(0.68),
                .paragraphStyle: style,
            ]
        )
    }
}
