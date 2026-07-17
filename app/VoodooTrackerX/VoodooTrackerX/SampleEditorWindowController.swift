import AppKit

typealias SampleEditorSampleSelectionHandler = (_ oneBasedSampleSlot: Int) -> Bool

struct SampleWaveformBucket: Equatable {
    let minimum: Float
    let maximum: Float
}

enum SampleWaveformProjection {
    static func make(pcm: [Float], pixelWidth: Int, frameCount: Int? = nil) -> [SampleWaveformBucket] {
        let count = min(pcm.count, max(0, frameCount ?? pcm.count))
        guard pixelWidth > 0, count > 0 else { return [] }
        let bucketCount = min(pixelWidth, count)
        return (0..<bucketCount).map { bucket in
            let start = bucket * count / bucketCount
            let end = max(start + 1, (bucket + 1) * count / bucketCount)
            var low = Float.greatestFiniteMagnitude
            var high = -Float.greatestFiniteMagnitude
            for index in start..<min(end, count) {
                let value = pcm[index].isFinite ? pcm[index] : 0
                low = min(low, value)
                high = max(high, value)
            }
            return SampleWaveformBucket(minimum: low, maximum: high)
        }
    }
}

final class SampleWaveformProjectionCache {
    private var sample: PlaybackSample?
    private var cachedWidth: Int?
    private var cachedProjection: [SampleWaveformBucket] = []
    private(set) var buildCount = 0

    func setSample(_ sample: PlaybackSample?) {
        self.sample = sample
        cachedWidth = nil
        cachedProjection = []
    }

    func projection(pixelWidth: Int) -> [SampleWaveformBucket] {
        let width = max(0, pixelWidth)
        if cachedWidth == width { return cachedProjection }
        buildCount += 1
        cachedWidth = width
        cachedProjection = sample.map {
            SampleWaveformProjection.make(pcm: $0.pcm, pixelWidth: width, frameCount: $0.sampleLength)
        } ?? []
        return cachedProjection
    }
}

struct SampleLoopDisplayState: Equatable {
    enum Mode: Equatable { case none, forward, pingPong, unknown }
    enum Status: Equatable { case inactive, valid, invalid }

    static let inactive = SampleLoopDisplayState(
        mode: .none, status: .inactive, startFrame: nil, lengthFrames: nil, endFrame: nil,
        startFraction: nil, endFraction: nil
    )

    let mode: Mode
    let status: Status
    let startFrame: Int?
    let lengthFrames: Int?
    let endFrame: Int?
    let startFraction: Double?
    let endFraction: Double?

    init(sample: PlaybackSample) {
        mode = switch sample.loopType {
        case 0: .none
        case 1: .forward
        case 2: .pingPong
        default: .unknown
        }
        startFrame = sample.loopStart
        lengthFrames = sample.loopLength
        let addition = sample.loopStart.addingReportingOverflow(sample.loopLength)
        endFrame = addition.overflow ? nil : addition.partialValue
        guard mode != .none else {
            status = .inactive
            startFraction = nil
            endFraction = nil
            return
        }
        let frameCount = min(max(0, sample.sampleLength), sample.pcm.count)
        guard mode != .unknown, frameCount > 0, sample.loopStart >= 0, sample.loopLength > 0,
              !addition.overflow, addition.partialValue > sample.loopStart,
              sample.loopStart < frameCount, addition.partialValue <= frameCount else {
            status = .invalid
            startFraction = nil
            endFraction = nil
            return
        }
        status = .valid
        startFraction = min(1, max(0, Double(sample.loopStart) / Double(frameCount)))
        endFraction = min(1, max(0, Double(addition.partialValue) / Double(frameCount)))
    }

    private init(
        mode: Mode, status: Status, startFrame: Int?, lengthFrames: Int?, endFrame: Int?,
        startFraction: Double?, endFraction: Double?
    ) {
        self.mode = mode
        self.status = status
        self.startFrame = startFrame
        self.lengthFrames = lengthFrames
        self.endFrame = endFrame
        self.startFraction = startFraction
        self.endFraction = endFraction
    }

    var modeDisplay: String {
        switch mode { case .none: "NONE"; case .forward: "FWD"; case .pingPong: "PINGPONG"; case .unknown: "UNKNOWN" }
    }
    var statusDisplay: String {
        switch status {
        case .inactive: "LOOP INACTIVE"
        case .valid: "DISPLAY ONLY"
        case .invalid: "INVALID RANGE"
        }
    }
    var startDisplay: String { startFrame.map(String.init) ?? "—" }
    var lengthDisplay: String { lengthFrames.map(String.init) ?? "—" }
    var endDisplay: String {
        if startFrame == nil, lengthFrames == nil { return "—" }
        return endFrame.map(String.init) ?? "OVERFLOW"
    }
}

struct SampleEditorDisplayState: Equatable {
    enum Source: Equatable { case none, loadedModule, editableDocument }
    struct SampleSlot: Equatable {
        let slot: Int
        let name: String
        let isSelected: Bool
        var display: String { String(format: "S%02X", slot) }
    }

    static let empty = SampleEditorDisplayState(
        source: .none, instrumentSlot: nil, instrumentName: "No instrument available",
        selectedSampleSlot: nil, sampleSlots: [], selectedSample: nil,
        emptyMessage: "No document sample palette is available."
    )

    let source: Source
    let instrumentSlot: Int?
    let instrumentName: String
    let selectedSampleSlot: Int?
    let sampleSlots: [SampleSlot]
    let selectedSample: PlaybackSample?
    let emptyMessage: String
    var isReadOnly: Bool { true }
    var instrumentDisplay: String { instrumentSlot.map { String(format: "I%02X", $0) } ?? "—" }
    var sampleDisplay: String { selectedSampleSlot.map { String(format: "S%02X", $0) } ?? "—" }
    var sampleName: String { Self.name(selectedSample?.name, fallback: "No represented sample") }
    var frameLength: Int? { selectedSample?.sampleLength }
    var lengthDisplay: String { frameLength.map { String(format: "%06d", max(0, $0)) } ?? "—" }
    var bitDepthBits: Int? { selectedSample?.sourceBitDepthBits }
    var formatDisplay: String {
        guard selectedSample != nil else { return "FORMAT UNAVAILABLE" }
        return bitDepthBits.map { "\($0)-BIT · MONO" } ?? "BIT DEPTH — · MONO"
    }
    var volume: Int? { selectedSample.map { Int($0.xmVolume) } }
    var volumeDisplay: String { volume.map(String.init) ?? "—" }
    var panning: UInt8? { selectedSample?.panning }
    var panningDisplay: String { panning.map { "\($0) / 255" } ?? "—" }
    var relativeNote: Int? { selectedSample?.relativeNote }
    var relativeNoteDisplay: String { relativeNote.map(Self.signed) ?? "—" }
    var finetune: Int? { selectedSample?.finetune }
    var finetuneDisplay: String { finetune.map(Self.signed) ?? "—" }
    var waveformPCM: [Float] { selectedSample?.pcm ?? [] }
    var loop: SampleLoopDisplayState { selectedSample.map(SampleLoopDisplayState.init(sample:)) ?? .inactive }

    static func loadedModule(playbackSong: PlaybackSong?, selection: TrackerEditorSelection) -> Self {
        make(source: .loadedModule, palette: playbackSong?.instrumentsByIndex ?? [:], selection: selection)
    }

    static func editableDocument(_ document: BlankTrackerDocument) -> Self {
        make(source: .editableDocument, palette: document.instrumentPalette, selection: document.selection)
    }

    private static func make(
        source: Source, palette: [Int: PlaybackInstrument], selection: TrackerEditorSelection
    ) -> Self {
        guard let instrument = palette[selection.selectedInstrument] else {
            return SampleEditorDisplayState(
                source: source, instrumentSlot: nil, instrumentName: "No instrument available",
                selectedSampleSlot: nil, sampleSlots: [], selectedSample: nil,
                emptyMessage: palette.isEmpty
                    ? "No represented instruments are available."
                    : "\(String(format: "I%02X", selection.selectedInstrument)) is not represented."
            )
        }
        let selected = instrument.sample(selectedSampleSlot: selection.selectedSample)
        let slots = instrument.samples.map {
            SampleSlot(
                slot: min(255, max(1, $0.sampleIndex + 1)),
                name: name($0.name, fallback: "(unnamed sample)"),
                isSelected: $0.sampleIndex + 1 == selection.selectedSample
            )
        }.sorted { $0.slot < $1.slot }
        return SampleEditorDisplayState(
            source: source,
            instrumentSlot: selection.selectedInstrument,
            instrumentName: name(instrument.name, fallback: "(unnamed instrument)"),
            selectedSampleSlot: selected.map { $0.sampleIndex + 1 },
            sampleSlots: slots,
            selectedSample: selected,
            emptyMessage: selected == nil
                ? (slots.isEmpty ? "This instrument has no represented samples." : "The selected sample is not represented.")
                : ""
        )
    }

    private static func name(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
    private static func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}

enum SampleEditorViewIdentifier {
    static let contentView = "sampleEditor.contentView"
    static let headerPanel = "sampleEditor.headerPanel"
    static let samplesPanel = "sampleEditor.samplesPanel"
    static let waveformPanel = "sampleEditor.waveformPanel"
    static let waveformView = "sampleEditor.waveformView"
    static let loopPanel = "sampleEditor.loopPanel"
    static let loopPreview = "sampleEditor.loopPreview"
    static let sampleParamsPanel = "sampleEditor.sampleParamsPanel"
    static let generatePanel = "sampleEditor.generatePanel"
    static let filePanel = "sampleEditor.filePanel"
    static let editPanel = "sampleEditor.editPanel"
    static let sampleRowPrefix = "sampleEditor.sampleRow."
    static let futureControlPrefix = "sampleEditor.futureControl."
    static let majorRegions = [
        headerPanel, samplesPanel, waveformPanel, waveformView, loopPanel, loopPreview,
        sampleParamsPanel, generatePanel, filePanel, editPanel,
    ]
}

final class SampleWaveformView: NSView {
    private let cache = SampleWaveformProjectionCache()
    private var loop = SampleLoopDisplayState.inactive
    private var hasSample = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(sample: PlaybackSample?, loop: SampleLoopDisplayState) {
        cache.setSample(sample)
        hasSample = sample != nil
        self.loop = loop
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current?.cgContext
        context?.setFillColor(VTXEditorControlTheme.recessedReadoutBackground.cgColor)
        context?.fill(bounds)
        context?.setStrokeColor(VTXEditorControlTheme.mutedGoldBorderSubtle.cgColor)
        context?.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
        drawLoop(in: context)
        context?.setStrokeColor(VTXEditorControlTheme.accentGold.withAlphaComponent(0.12).cgColor)
        context?.move(to: CGPoint(x: 1, y: bounds.midY))
        context?.addLine(to: CGPoint(x: bounds.maxX - 1, y: bounds.midY))
        context?.strokePath()
        let width = bounds.width.isFinite ? max(0, Int(bounds.width.rounded(.down))) : 0
        let buckets = cache.projection(pixelWidth: max(0, width / 2))
        guard !buckets.isEmpty else {
            let copy = hasSample ? "EMPTY PCM" : "NO REPRESENTED SAMPLE"
            (copy as NSString).draw(
                at: CGPoint(x: max(8, bounds.midX - 66), y: bounds.midY - 5),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                                 .foregroundColor: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28)]
            )
            return
        }
        let extremaPath = NSBezierPath()
        extremaPath.lineWidth = 1
        let tracePath = NSBezierPath()
        tracePath.lineWidth = 1
        let step = buckets.count > 1 ? (bounds.width - 2) / CGFloat(buckets.count - 1) : 0
        for (index, bucket) in buckets.enumerated() {
            let x = buckets.count == 1 ? bounds.midX : 1 + CGFloat(index) * step
            let low = y(for: bucket.minimum)
            let high = y(for: bucket.maximum)
            if abs(high - low) < 0.5 {
                extremaPath.move(to: CGPoint(x: x - 0.75, y: low))
                extremaPath.line(to: CGPoint(x: x + 0.75, y: high))
            } else {
                extremaPath.move(to: CGPoint(x: x, y: low))
                extremaPath.line(to: CGPoint(x: x, y: high))
            }
            let center = CGPoint(x: x, y: (low + high) / 2)
            if index == 0 {
                tracePath.move(to: center)
            } else {
                tracePath.line(to: center)
            }
        }
        VTXEditorControlTheme.accentGold.withAlphaComponent(0.24).setStroke()
        extremaPath.stroke()
        VTXEditorControlTheme.accentGold.withAlphaComponent(0.82).setStroke()
        tracePath.stroke()
    }

    private func y(for amplitude: Float) -> CGFloat {
        let value = CGFloat(min(1, max(-1, amplitude)))
        return bounds.midY + value * max(1, bounds.height * 0.44)
    }

    private func drawLoop(in context: CGContext?) {
        guard loop.status == .valid, let start = loop.startFraction, let end = loop.endFraction else { return }
        let startX = CGFloat(start) * bounds.width
        let endX = CGFloat(end) * bounds.width
        context?.setFillColor(VTXEditorControlTheme.indigoSelection.withAlphaComponent(0.40).cgColor)
        context?.fill(CGRect(x: startX, y: 1, width: max(0, endX - startX), height: max(0, bounds.height - 2)))
        context?.setStrokeColor(VTXEditorControlTheme.indicatorLEDRed.cgColor)
        context?.setLineWidth(1.25)
        for x in [startX, endX] {
            context?.move(to: CGPoint(x: x, y: 0)); context?.addLine(to: CGPoint(x: x, y: bounds.height)); context?.strokePath()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .bold),
            .foregroundColor: VTXEditorControlTheme.indicatorLEDRed,
        ]
        ("L◀" as NSString).draw(at: CGPoint(x: startX + 3, y: bounds.maxY - 11), withAttributes: attributes)
        ("▶L" as NSString).draw(at: CGPoint(x: max(2, endX - 18), y: bounds.maxY - 11), withAttributes: attributes)
    }
}

@MainActor
final class SampleEditorWindowPresenter {
    private(set) var windowController: SampleEditorWindowController?

    @discardableResult
    func show(
        displayState: SampleEditorDisplayState,
        sampleSelectionHandler: SampleEditorSampleSelectionHandler? = nil
    ) -> SampleEditorWindowController {
        if let windowController {
            windowController.sampleSelectionHandler = sampleSelectionHandler
            windowController.apply(displayState: displayState)
            windowController.showWindowAndActivate()
            return windowController
        }
        let controller = SampleEditorWindowController(
            displayState: displayState, sampleSelectionHandler: sampleSelectionHandler
        )
        controller.closeHandler = { [weak self, weak controller] in
            guard let self, let controller, self.windowController === controller else { return }
            self.windowController = nil
        }
        windowController = controller
        controller.showWindowAndActivate()
        return controller
    }

    func refresh(displayState: SampleEditorDisplayState) { windowController?.apply(displayState: displayState) }
}

@MainActor
final class SampleEditorWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 940, height: 560)
    private var didInstallInitialFirstResponder = false
    var closeHandler: (() -> Void)?
    var sampleSelectionHandler: SampleEditorSampleSelectionHandler? {
        didSet { (window?.contentView as? SampleEditorView)?.sampleSelectionHandler = sampleSelectionHandler }
    }

    init(
        displayState: SampleEditorDisplayState = .empty,
        sampleSelectionHandler: SampleEditorSampleSelectionHandler? = nil
    ) {
        self.sampleSelectionHandler = sampleSelectionHandler
        let view = SampleEditorView(
            frame: NSRect(origin: .zero, size: Self.contentSize),
            displayState: displayState,
            sampleSelectionHandler: sampleSelectionHandler
        )
        let panel = NSPanel(
            contentRect: view.frame, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false
        )
        panel.title = "Sample Editor"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = VTXEditorControlTheme.windowBackground
        panel.contentView = view
        panel.contentMinSize = Self.contentSize
        panel.contentMaxSize = Self.contentSize
        panel.setContentSize(Self.contentSize)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.initialFirstResponder = view
        panel.center()
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showWindowAndActivate() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        if !didInstallInitialFirstResponder {
            didInstallInitialFirstResponder = true
            window.makeFirstResponder(window.contentView)
        }
    }

    @discardableResult
    func apply(displayState: SampleEditorDisplayState) -> Bool {
        (window?.contentView as? SampleEditorView)?.apply(displayState: displayState) ?? false
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        sampleSelectionHandler = nil
        closeHandler?()
    }
}

@MainActor
final class SampleEditorView: FlippedEditorView {
    override var acceptsFirstResponder: Bool { true }
    private(set) var displayState: SampleEditorDisplayState
    private(set) var rebuildCount = 0
    private(set) weak var waveformView: SampleWaveformView?
    private var sampleRows: [Int: InstrumentEditorListRowControl] = [:]
    var sampleSelectionHandler: SampleEditorSampleSelectionHandler?

    init(
        frame frameRect: NSRect,
        displayState: SampleEditorDisplayState = .empty,
        sampleSelectionHandler: SampleEditorSampleSelectionHandler? = nil
    ) {
        self.displayState = displayState
        self.sampleSelectionHandler = sampleSelectionHandler
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.contentView)
        style(background: VTXEditorControlTheme.windowBackground)
        buildShell()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func apply(displayState: SampleEditorDisplayState) -> Bool {
        guard self.displayState != displayState else { return false }
        self.displayState = displayState
        rebuildCount += 1
        subviews.forEach { $0.removeFromSuperview() }
        sampleRows.removeAll()
        buildShell()
        return true
    }

    func sampleRow(slot: Int) -> InstrumentEditorListRowControl? { sampleRows[slot] }

    private func buildShell() {
        addSurface(to: self, frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1), background: VTXEditorControlTheme.accentGold.withAlphaComponent(0.60))
        buildHeader(panel(SampleEditorViewIdentifier.headerPanel, title: nil, frame: NSRect(x: 12, y: 13, width: 916, height: 50)))
        buildSamples(panel(SampleEditorViewIdentifier.samplesPanel, title: "Samples", frame: NSRect(x: 12, y: 73, width: 172, height: 224)))
        buildWaveform(panel(SampleEditorViewIdentifier.waveformPanel, title: "Waveform", frame: NSRect(x: 194, y: 73, width: 734, height: 224)))
        buildLoop(panel(SampleEditorViewIdentifier.loopPanel, title: "Loop", frame: NSRect(x: 12, y: 307, width: 250, height: 177)))
        buildParams(panel(SampleEditorViewIdentifier.sampleParamsPanel, title: "Sample params", frame: NSRect(x: 272, y: 307, width: 256, height: 177)))
        buildGenerate(panel(SampleEditorViewIdentifier.generatePanel, title: "Generate", frame: NSRect(x: 538, y: 307, width: 390, height: 81)))
        buildFile(panel(SampleEditorViewIdentifier.filePanel, title: "File", frame: NSRect(x: 538, y: 398, width: 390, height: 86)))
        buildEdit(panel(SampleEditorViewIdentifier.editPanel, title: "Edit", frame: NSRect(x: 12, y: 494, width: 916, height: 54)))
    }

    private func buildHeader(_ parent: NSView) {
        label("SMP", parent, NSRect(x: 10, y: 20, width: 28, height: 12), gold: true)
        readout(displayState.sampleDisplay, parent, NSRect(x: 42, y: 13, width: 45, height: 23))
        label("NAME", parent, NSRect(x: 98, y: 20, width: 32, height: 12), gold: true)
        readout(displayState.sampleName, parent, NSRect(x: 135, y: 13, width: 300, height: 23), alignment: .left)
        label("FORMAT", parent, NSRect(x: 447, y: 20, width: 45, height: 12), gold: true)
        readout(displayState.formatDisplay, parent, NSRect(x: 498, y: 13, width: 184, height: 23))
        label("AUDITION", parent, NSRect(x: 694, y: 20, width: 52, height: 12), gold: true)
        readout("C-4", parent, NSRect(x: 751, y: 13, width: 45, height: 23))
        futureButton("▶", id: "audition", parent, NSRect(x: 802, y: 12, width: 35, height: 25), role: .activePlay)
        addControl(VTXEditorControlFactory.makeIndicatorLED(state: .off), to: parent, frame: NSRect(x: 847, y: 21, width: 8, height: 8))
    }

    private func buildSamples(_ parent: NSView) {
        let instrumentSummary = displayState.instrumentSlot == nil
            ? "INSTR — · UNAVAILABLE"
            : "INSTR \(displayState.instrumentDisplay) · \(displayState.instrumentName)"
        label(instrumentSummary, parent, NSRect(x: 10, y: 26, width: 152, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.48), size: 7.5)
        let frame = NSRect(x: 10, y: 42, width: 152, height: 172)
        guard !displayState.sampleSlots.isEmpty else {
            let surface = addSurface(to: parent, frame: frame, background: VTXEditorControlTheme.recessedReadoutBackground, border: VTXEditorControlTheme.mutedGoldBorderSubtle, radius: 3)
            let emptyLabel = label("NO REPRESENTED SAMPLES", surface, NSRect(x: 8, y: 77, width: 136, height: 12), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8, alignment: .center)
            emptyLabel.setAccessibilityLabel(displayState.emptyMessage)
            return
        }
        let rowHeight: CGFloat = 22
        let rows = FlippedEditorView(frame: NSRect(x: 0, y: 0, width: frame.width, height: max(frame.height, rowHeight * CGFloat(displayState.sampleSlots.count))))
        rows.style(background: VTXEditorControlTheme.recessedReadoutBackground)
        for (index, slot) in displayState.sampleSlots.enumerated() {
            let row = InstrumentEditorListRowControl(frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: frame.width, height: rowHeight), slot: slot.slot, isSelected: slot.isSelected)
            row.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.sampleRowPrefix + "\(slot.slot)")
            row.target = self
            row.action = #selector(selectSample(_:))
            row.setAccessibilityLabel("\(slot.display) \(slot.name)")
            sampleRows[slot.slot] = row
            rows.addSubview(row)
            label(slot.display, row, NSRect(x: 8, y: 5, width: 30, height: 11), color: slot.isSelected ? .white.withAlphaComponent(0.65) : VTXEditorControlTheme.panelLabelText, size: 8.5)
            label(slot.name, row, NSRect(x: 42, y: 5, width: 102, height: 11), color: slot.isSelected ? .white : VTXEditorControlTheme.warmValueText.withAlphaComponent(0.62), size: 8.5)
        }
        let scroll = NSScrollView(frame: frame)
        scroll.drawsBackground = false
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = rows.frame.height > frame.height
        scroll.autohidesScrollers = true
        scroll.documentView = rows
        parent.addSubview(scroll)
    }

    @objc private func selectSample(_ sender: InstrumentEditorListRowControl) {
        guard displayState.sampleSlots.contains(where: { $0.slot == sender.slot }) else { return }
        _ = sampleSelectionHandler?(sender.slot)
        window?.makeFirstResponder(sampleRows[sender.slot] ?? sender)
    }

    private func buildWaveform(_ parent: NSView) {
        label("— DISPLAY ONLY · LOOP REGION FROM METADATA", parent, NSRect(x: 83, y: 10, width: 330, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.30), size: 8)
        let waveform = SampleWaveformView(frame: NSRect(x: 10, y: 31, width: 714, height: 150))
        waveform.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.waveformView)
        waveform.apply(sample: displayState.selectedSample, loop: displayState.loop)
        parent.addSubview(waveform)
        waveformView = waveform
        label("LEN", parent, NSRect(x: 10, y: 194, width: 23, height: 11), gold: true)
        readout(displayState.lengthDisplay, parent, NSRect(x: 37, y: 187, width: 70, height: 23))
        label("SEL", parent, NSRect(x: 118, y: 194, width: 23, height: 11), gold: true)
        readout("—", parent, NSRect(x: 145, y: 187, width: 82, height: 23))
        label("ZOOM", parent, NSRect(x: 396, y: 194, width: 34, height: 11), gold: true)
        futureSlider(id: "zoom", parent, NSRect(x: 435, y: 183, width: 100, height: 32), value: -0.45)
        label("SCROLL", parent, NSRect(x: 548, y: 194, width: 44, height: 11), gold: true)
        futureSlider(id: "scroll", parent, NSRect(x: 598, y: 183, width: 116, height: 32), value: -0.3)
    }

    private func buildLoop(_ parent: NSView) {
        label("MODE", parent, NSRect(x: 10, y: 37, width: 32, height: 11), gold: true)
        for (index, value) in ["NONE", "FWD", "PINGPONG"].enumerated() {
            let widths: [CGFloat] = [50, 42, 72]
            let x = 47 + widths.prefix(index).reduce(0, +)
            futureButton(value, id: "loopMode\(index)", parent, NSRect(x: x, y: 30, width: widths[index], height: 25), role: displayState.loop.modeDisplay == value ? .selected : .normal)
        }
        addControl(VTXEditorControlFactory.makeIndicatorLED(state: displayState.loop.status == .valid ? .redActive : .off), to: parent, frame: NSRect(x: 222, y: 38, width: 8, height: 8))
        label("START", parent, NSRect(x: 10, y: 70, width: 37, height: 11), gold: true)
        readout(displayState.loop.startDisplay, parent, NSRect(x: 51, y: 63, width: 60, height: 23))
        futureStepper(id: "loopStart", parent, NSRect(x: 113, y: 63, width: 18, height: 23))
        label("END", parent, NSRect(x: 139, y: 70, width: 24, height: 11), gold: true)
        readout(displayState.loop.endDisplay, parent, NSRect(x: 167, y: 63, width: 60, height: 23))
        label("LENGTH", parent, NSRect(x: 10, y: 98, width: 43, height: 11), gold: true)
        readout(displayState.loop.lengthDisplay, parent, NSRect(x: 58, y: 91, width: 72, height: 23))
        label(displayState.loop.statusDisplay, parent, NSRect(x: 135, y: 98, width: 102, height: 11), color: displayState.loop.status == .invalid ? VTXEditorControlTheme.dangerRed : VTXEditorControlTheme.warmValueText.withAlphaComponent(0.30), size: 7, alignment: .right)
        let preview = SampleWaveformView(frame: NSRect(x: 10, y: 119, width: 230, height: 48))
        preview.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.loopPreview)
        preview.apply(sample: displayState.selectedSample, loop: displayState.loop)
        parent.addSubview(preview)
    }

    private func buildParams(_ parent: NSView) {
        disabledKnob(value: Double(displayState.volume ?? 0), range: 0...64, id: "volume", title: "VOLUME", readoutValue: displayState.volumeDisplay, parent: parent, x: 25, emphasized: true)
        disabledKnob(value: Double(displayState.finetune ?? 0), range: -128...127, id: "finetune", title: "FINETUNE", readoutValue: displayState.finetuneDisplay, parent: parent, x: 116)
        label("PAN", parent, NSRect(x: 10, y: 127, width: 28, height: 11), gold: true)
        let panValue = displayState.panning.map { PlaybackSamplePanningPolicy.plannedPan($0) } ?? 0
        futureSlider(id: "panning", parent, NSRect(x: 45, y: 116, width: 154, height: 32), value: Double(panValue))
        label(displayState.panningDisplay, parent, NSRect(x: 202, y: 127, width: 44, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.40), size: 7, alignment: .right)
        label("REL NOTE", parent, NSRect(x: 10, y: 158, width: 50, height: 11), gold: true)
        readout(displayState.relativeNoteDisplay, parent, NSRect(x: 66, y: 151, width: 48, height: 23))
        futureStepper(id: "relativeNote", parent, NSRect(x: 116, y: 151, width: 18, height: 23))
    }

    private func buildGenerate(_ parent: NSView) {
        label("— REPLACES SAMPLE (CONFIRM)", parent, NSRect(x: 80, y: 10, width: 210, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8)
        let entries = ["∿\nSINE", "⊓\nSQUARE", "⊿\nTRI", "◺\nSAW", "▦\nNOISE"]
        for (index, title) in entries.enumerated() {
            futureButton(title, id: "generate\(index)", parent, NSRect(x: 10 + CGFloat(index) * 74, y: 29, width: 68, height: 42))
        }
    }

    private func buildFile(_ parent: NSView) {
        label("— SAMPLE IMPORT / EXPORT · XI IS MENU-CANONICAL", parent, NSRect(x: 48, y: 10, width: 320, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8)
        for (index, title) in ["⤓\nLOAD", "⤒\nEXPORT", "⌫\nCLEAR", "⟲\nREPLACE"].enumerated() {
            futureButton(title, id: "file\(index)", parent, NSRect(x: 10 + CGFloat(index) * 93, y: 31, width: 87, height: 45), role: index >= 2 ? .danger : .normal)
        }
    }

    private func buildEdit(_ parent: NSView) {
        label("— ACTS ON SELECTION (OR WHOLE SAMPLE) · FUTURE", parent, NSRect(x: 45, y: 10, width: 310, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8)
        let titles = ["✂ TRIM", "▣ CROP", "CUT", "COPY", "PASTE", "▲ NORMALIZE", "⇄ REVERSE", "◢ FADE IN", "◣ FADE OUT", "↶ UNDO"]
        var x: CGFloat = 10
        for (index, title) in titles.enumerated() {
            let width = max(49, CGFloat(title.count * 7 + 14))
            futureButton(title, id: "edit\(index)", parent, NSRect(x: x, y: 25, width: width, height: 23))
            x += width + (index == 1 || index == 4 ? 14 : 5)
        }
    }

    private func disabledKnob(value: Double, range: ClosedRange<Int>, id: String, title: String, readoutValue: String, parent: NSView, x: CGFloat, emphasized: Bool = false) {
        let knob = VTXEditorControlFactory.makeKnobControl(value: value, minimumValue: Double(range.lowerBound), maximumValue: Double(range.upperBound), isEmphasized: emphasized)
        knob.isEnabled = false; knob.target = nil; knob.action = nil; knob.identifier = futureID(id)
        addControl(knob, to: parent, frame: NSRect(x: x, y: 27, width: 72, height: 72))
        label(title, parent, NSRect(x: x, y: 99, width: 72, height: 10), color: VTXEditorControlTheme.panelLabelText, size: 8, alignment: .center)
        readout(readoutValue, parent, NSRect(x: x + 12, y: 108, width: 48, height: 20))
    }

    private func futureSlider(id: String, _ parent: NSView, _ frame: NSRect, value: Double) {
        let slider = VTXEditorControlFactory.makePanSliderControl(value: value, snapsToCenter: false, showsCenteredIndicator: value == 0)
        slider.isEnabled = false; slider.target = nil; slider.action = nil; slider.identifier = futureID(id)
        addControl(slider, to: parent, frame: frame)
    }

    private func futureStepper(id: String, _ parent: NSView, _ frame: NSRect) {
        let stepper = TrackerStepper(); stepper.isEnabled = false; stepper.target = nil; stepper.action = nil; stepper.identifier = futureID(id)
        addControl(stepper, to: parent, frame: frame)
    }

    private func futureButton(_ title: String, id: String, _ parent: NSView, _ frame: NSRect, role: VTXEditorButtonRole = .normal) {
        let button = VTXEditorControlFactory.makeButton(title: title, role: role, fixedWidth: frame.width)
        button.isEnabled = false; button.target = nil; button.action = nil; button.sendAction(on: []); button.identifier = futureID(id)
        addControl(button, to: parent, frame: frame)
    }

    private func futureID(_ value: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.futureControlPrefix + value)
    }

    private func panel(_ id: String, title: String?, frame: NSRect) -> FlippedEditorView {
        let view = addSurface(to: self, frame: frame, background: VTXEditorControlTheme.panelSurface, border: VTXEditorControlTheme.mutedGoldBorderFaint, radius: 4)
        view.identifier = NSUserInterfaceItemIdentifier(id)
        if let title { addControl(VTXEditorControlFactory.makePanelLabel(title), to: view, frame: NSRect(x: 10, y: 10, width: min(130, frame.width - 20), height: 12)) }
        return view
    }

    private func readout(_ value: String, _ parent: NSView, _ frame: NSRect, alignment: NSTextAlignment = .center) {
        addControl(VTXEditorControlFactory.makeSegmentReadout(value: value, fixedWidth: frame.width, alignment: alignment), to: parent, frame: frame)
    }

    @discardableResult private func label(_ value: String, _ parent: NSView, _ frame: NSRect, gold: Bool) -> NSTextField {
        label(value, parent, frame, color: gold ? VTXEditorControlTheme.accentGold : VTXEditorControlTheme.warmValueText, size: 9, weight: .bold)
    }

    @discardableResult private func label(_ value: String, _ parent: NSView, _ frame: NSRect, color: NSColor, size: CGFloat, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        field.textColor = color; field.alignment = alignment; field.lineBreakMode = .byTruncatingTail
        addControl(field, to: parent, frame: frame)
        return field
    }

    @discardableResult private func addSurface(to parent: NSView, frame: NSRect, background: NSColor, border: NSColor? = nil, radius: CGFloat = 0) -> FlippedEditorView {
        let view = FlippedEditorView(frame: frame); view.style(background: background, border: border, radius: radius); parent.addSubview(view); return view
    }

    private func addControl(_ view: NSView, to parent: NSView, frame: NSRect) {
        view.translatesAutoresizingMaskIntoConstraints = true; view.frame = frame; parent.addSubview(view)
    }
}
