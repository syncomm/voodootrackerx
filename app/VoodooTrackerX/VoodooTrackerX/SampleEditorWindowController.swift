import AppKit

typealias SampleEditorInstrumentSelectionHandler = (_ oneBasedInstrumentSlot: Int) -> Bool
typealias SampleEditorSampleSelectionHandler = (_ oneBasedSampleSlot: Int) -> Bool
typealias SampleEditorSineGenerationHandler = () -> Bool
typealias SampleEditorWAVLoadHandler = () -> Bool
typealias SampleEditorClearHandler = () -> Bool

struct SampleEditorClearContext: Equatable {
    static let unavailable = Self(
        documentIdentity: nil,
        documentRevision: 0,
        editContext: .none
    )

    let documentIdentity: UUID?
    let documentRevision: UInt64
    let editContext: EditableDocumentEditContext
    let hasConflictingLifecycleOperation: Bool
    let hasConflictingModalPresentation: Bool

    init(
        documentIdentity: UUID?,
        documentRevision: UInt64,
        editContext: EditableDocumentEditContext,
        hasConflictingLifecycleOperation: Bool = false,
        hasConflictingModalPresentation: Bool = false
    ) {
        self.documentIdentity = documentIdentity
        self.documentRevision = documentRevision
        self.editContext = editContext
        self.hasConflictingLifecycleOperation = hasConflictingLifecycleOperation
        self.hasConflictingModalPresentation = hasConflictingModalPresentation
    }
}

struct SampleEditorClearRequest: Equatable {
    let operationToken: UUID
    let instrumentIndex: Int
    let sampleIndex: Int
    let sampleDisplay: String
    let mappedNoteCount: Int
}

private struct SampleEditorClearCapture {
    let documentIdentity: UUID
    let documentRevision: UInt64
    let instrumentIndex: Int
    let sampleIndex: Int
    let sample: PlaybackSample
    let mappedNoteCount: Int

    init?(context: SampleEditorClearContext) {
        guard !context.hasConflictingLifecycleOperation,
              !context.hasConflictingModalPresentation,
              let documentIdentity = context.documentIdentity,
              case let .editable(document, false) = context.editContext else { return nil }
        let instrumentIndex = document.selection.selectedInstrument - 1
        let sampleIndex = document.selection.selectedSample - 1
        guard let sample = document.representedSampleForClear(
            instrumentAt: instrumentIndex, sampleAt: sampleIndex
        ), let instrument = document.instrument(forInstrument: instrumentIndex + 1) else { return nil }

        self.documentIdentity = documentIdentity
        self.documentRevision = context.documentRevision
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
        self.sample = sample
        mappedNoteCount = instrument.noteSampleMap?
            .prefix(TrackerNoteKeyMap.maximumNoteValue)
            .filter { $0 == sampleIndex }
            .count ?? 0
    }

    func isCurrent(in context: SampleEditorClearContext) -> Bool {
        // The Clear confirmation sheet is expected to be attached here. Only a
        // competing lifecycle operation invalidates an already captured request.
        guard !context.hasConflictingLifecycleOperation,
              context.documentIdentity == documentIdentity,
              context.documentRevision == documentRevision,
              case let .editable(document, false) = context.editContext,
              document.selection.selectedInstrument == instrumentIndex + 1,
              document.selection.selectedSample == sampleIndex + 1 else {
            return false
        }
        return document.representedSampleForClear(
            instrumentAt: instrumentIndex, sampleAt: sampleIndex
        ) == sample
    }
}

@MainActor
final class SampleEditorClearCoordinator {
    private let contextProvider: () -> SampleEditorClearContext
    private let commitHandler: (Int, Int) -> Bool
    private let stateChangeHandler: () -> Void
    private var activeOperation: (token: UUID, capture: SampleEditorClearCapture)?

    init(
        contextProvider: @escaping () -> SampleEditorClearContext,
        commitHandler: @escaping (Int, Int) -> Bool,
        stateChangeHandler: @escaping () -> Void = {}
    ) {
        self.contextProvider = contextProvider
        self.commitHandler = commitHandler
        self.stateChangeHandler = stateChangeHandler
    }

    var isActive: Bool { activeOperation != nil }
    var canBegin: Bool {
        activeOperation == nil && SampleEditorClearCapture(context: contextProvider()) != nil
    }

    func begin() -> SampleEditorClearRequest? {
        guard activeOperation == nil,
              let capture = SampleEditorClearCapture(context: contextProvider()) else { return nil }
        let token = UUID()
        activeOperation = (token, capture)
        stateChangeHandler()
        return SampleEditorClearRequest(
            operationToken: token,
            instrumentIndex: capture.instrumentIndex,
            sampleIndex: capture.sampleIndex,
            sampleDisplay: String(format: "S%02X", capture.sampleIndex + 1),
            mappedNoteCount: capture.mappedNoteCount
        )
    }

    @discardableResult
    func cancel(operationToken: UUID) -> Bool {
        guard activeOperation?.token == operationToken else { return false }
        finish()
        return true
    }

    @discardableResult
    func confirm(operationToken: UUID) -> Bool {
        guard let activeOperation, activeOperation.token == operationToken else { return false }
        defer { finish() }
        guard activeOperation.capture.isCurrent(in: contextProvider()) else { return false }
        return commitHandler(activeOperation.capture.instrumentIndex, activeOperation.capture.sampleIndex)
    }

    private func finish() {
        activeOperation = nil
        stateChangeHandler()
    }
}

@MainActor
enum SampleEditorClearAlert {
    static func make(request: SampleEditorClearRequest) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear Sample \(request.sampleDisplay)?"
        var detail = "The sample PCM and metadata will be removed. Undo can restore it."
        if request.mappedNoteCount > 0 {
            let noteLabel = request.mappedNoteCount == 1 ? "mapped note" : "mapped notes"
            detail += "\n\n\(request.mappedNoteCount) \(noteLabel) currently reference \(request.sampleDisplay). "
            detail += "Those mappings will be preserved and will become unavailable until explicitly remapped or the slot is populated again."
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "Clear Sample")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].setAccessibilityLabel("Clear \(request.sampleDisplay)")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert
    }

    static func isConfirmed(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }
}

struct SampleEditorAuditionHandlers {
    let start: () -> EditorNoteAuditionPreviewToken?
    let stop: (EditorNoteAuditionPreviewToken) -> Bool
}

enum SampleEditorAuditionRequestFactory {
    static let noteValue = UInt8(PlaybackPitchCalculator.c4NoteValue)
    static let octave = (PlaybackPitchCalculator.c4NoteValue - 1) / 12

    static func request(selection: TrackerEditorSelection,
                        sourceContext: EditorNoteAuditionSourceContext) -> EditorNoteAuditionRequest {
        EditorNoteAuditionRequest(kind: .noteOn(noteValue: noteValue, selectedOctave: octave),
                                  selection: selection, sampleResolution: .directSelectedSample,
                                  sourceContext: sourceContext)
    }
}

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
    struct InstrumentOption: Equatable {
        let slot: Int
        let name: String
        let isSelected: Bool
        var display: String { String(format: "I%02X", slot) }
        var title: String { "\(display)  \(name)" }
    }
    struct SampleSlot: Equatable {
        let slot: Int
        let name: String
        let isEmptyDestination: Bool
        let isSelected: Bool
        var display: String { String(format: "S%02X", slot) }
    }

    static let empty = SampleEditorDisplayState(
        source: .none, instrumentSlot: nil, instrumentName: "No instrument available",
        instrumentOptions: [], selectedSampleSlot: nil, sampleSlots: [], selectedSample: nil,
        emptyMessage: "No document sample palette is available.", isSineGenerationEnabled: false,
        isWAVLoadEnabled: false, isClearEnabled: false, isDuplicateEnabled: false,
        isImportingWAV: false, isAuditionEnabled: false
    )

    let source: Source
    let instrumentSlot: Int?
    let instrumentName: String
    let instrumentOptions: [InstrumentOption]
    let selectedSampleSlot: Int?
    let sampleSlots: [SampleSlot]
    let selectedSample: PlaybackSample?
    let emptyMessage: String
    let isSineGenerationEnabled: Bool
    let isWAVLoadEnabled: Bool
    let isClearEnabled: Bool
    let isDuplicateEnabled: Bool
    let isImportingWAV: Bool
    let isAuditionEnabled: Bool
    var isReadOnly: Bool { source != .editableDocument }
    var instrumentDisplay: String { instrumentSlot.map { String(format: "I%02X", $0) } ?? "—" }
    var sampleDisplay: String { selectedSampleSlot.map { String(format: "S%02X", $0) } ?? "—" }
    var sampleName: String {
        guard let selectedSample else {
            return selectedSampleRow?.isEmptyDestination == true
                ? "Empty sample destination"
                : "No represented sample"
        }
        return Self.name(selectedSample.name, fallback: "(unnamed sample)")
    }
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
    private var selectedSampleRow: SampleSlot? { sampleSlots.first(where: \.isSelected) }

    static func loadedModule(playbackSong: PlaybackSong?, selection: TrackerEditorSelection,
                             isPreviewAvailable: Bool = true) -> Self {
        make(source: .loadedModule, palette: playbackSong?.instrumentsByIndex ?? [:],
             selection: selection,
             presentationRows: playbackSong?.sampleSlotPresentationRows(
                forInstrument: selection.selectedInstrument
             ) ?? [],
             isSineGenerationEnabled: false, isWAVLoadEnabled: false,
             isClearEnabled: false, isDuplicateEnabled: false,
             isImportingWAV: false, isPreviewAvailable: isPreviewAvailable)
    }

    static func editableDocument(
        _ document: BlankTrackerDocument,
        isPlaybackActive: Bool = false,
        isImportingWAV: Bool = false,
        hasConflictingLifecycleOperation: Bool = false,
        isPreviewAvailable: Bool = true
    ) -> Self {
        let hasClearTarget = document.representedSampleForClear(
            instrumentAt: document.selection.selectedInstrument - 1,
            sampleAt: document.selection.selectedSample - 1
        ) != nil
        return make(source: .editableDocument, palette: document.instrumentPalette, selection: document.selection,
             presentationRows: document.sampleSlotPresentationRows(
                forInstrument: document.selection.selectedInstrument
             ),
             isSineGenerationEnabled: !isPlaybackActive && !isImportingWAV &&
                !hasConflictingLifecycleOperation && document.canGenerateSineInSelectedEmptySample,
             isWAVLoadEnabled: !isPlaybackActive && !isImportingWAV &&
                !hasConflictingLifecycleOperation && document.selectedSampleImportDestination != nil,
             isClearEnabled: !isPlaybackActive && !isImportingWAV &&
                !hasConflictingLifecycleOperation && hasClearTarget,
             isDuplicateEnabled: !isPlaybackActive && !isImportingWAV &&
                !hasConflictingLifecycleOperation && document.canDuplicateSelectedSample,
             isImportingWAV: isImportingWAV, isPreviewAvailable: isPreviewAvailable)
    }

    private static func make(source: Source, palette: [Int: PlaybackInstrument],
                             selection: TrackerEditorSelection,
                             presentationRows: [SampleSlotPresentationRow],
                             isSineGenerationEnabled: Bool,
                             isWAVLoadEnabled: Bool, isClearEnabled: Bool,
                             isDuplicateEnabled: Bool,
                             isImportingWAV: Bool, isPreviewAvailable: Bool) -> Self {
        let instrumentOptions = palette
            .filter { (1...255).contains($0.key) }
            .map { slot, instrument in
                InstrumentOption(
                    slot: slot,
                    name: name(instrument.name, fallback: "(unnamed instrument)"),
                    isSelected: slot == selection.selectedInstrument
                )
            }
            .sorted { $0.slot < $1.slot }
        guard let instrument = palette[selection.selectedInstrument] else {
            return SampleEditorDisplayState(
                source: source, instrumentSlot: nil, instrumentName: "No instrument available",
                instrumentOptions: instrumentOptions,
                selectedSampleSlot: nil, sampleSlots: [], selectedSample: nil,
                emptyMessage: palette.isEmpty
                    ? "No represented instruments are available."
                    : "\(String(format: "I%02X", selection.selectedInstrument)) is not represented.",
                isSineGenerationEnabled: false, isWAVLoadEnabled: false, isClearEnabled: false,
                isDuplicateEnabled: false,
                isImportingWAV: isImportingWAV,
                isAuditionEnabled: false
            )
        }
        let selected = presentationRows
            .first(where: { $0.sampleSlot == selection.selectedSample })?
            .representedSample
        let slots = presentationRows.map { row in
            SampleSlot(
                slot: row.sampleSlot,
                name: row.representedSample.map { name($0.name, fallback: "(unnamed sample)") }
                    ?? "Empty destination",
                isEmptyDestination: row.isEmptyDestination,
                isSelected: row.sampleSlot == selection.selectedSample
            )
        }
        let selectedSlot = slots.first(where: \.isSelected)
        return SampleEditorDisplayState(
            source: source,
            instrumentSlot: selection.selectedInstrument,
            instrumentName: name(instrument.name, fallback: "(unnamed instrument)"),
            instrumentOptions: instrumentOptions,
            selectedSampleSlot: selectedSlot?.slot,
            sampleSlots: slots,
            selectedSample: selected,
            emptyMessage: selected == nil
                ? (selectedSlot?.isEmptyDestination == true
                    ? "\(selectedSlot?.display ?? "Sample") is an empty sample destination."
                    : (slots.isEmpty
                        ? "This instrument has no represented samples."
                        : "The selected sample is not represented."))
                : "",
            isSineGenerationEnabled: isSineGenerationEnabled,
            isWAVLoadEnabled: isWAVLoadEnabled,
            isClearEnabled: isClearEnabled,
            isDuplicateEnabled: isDuplicateEnabled,
            isImportingWAV: isImportingWAV,
            isAuditionEnabled: isPreviewAvailable && !isImportingWAV && selected.map(isAuditionPlayable) == true
        )
    }

    private static func isAuditionPlayable(_ sample: PlaybackSample) -> Bool {
        let frameCount = min(max(0, sample.sampleLength), sample.pcm.count)
        return sample.isPlayable &&
            frameCount > 0 &&
            sample.baseSampleRate.isFinite &&
            sample.baseSampleRate > 0 && sample.pcm.prefix(frameCount).allSatisfy(\.isFinite)
    }

    private static func name(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
    private static func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}

enum SampleEditorDuplicateCommandAvailability {
    static func canPerform(
        displayState: SampleEditorDisplayState,
        isSampleEditorActionContext: Bool
    ) -> Bool {
        isSampleEditorActionContext && displayState.isDuplicateEnabled
    }
}

enum SampleEditorViewIdentifier {
    static let contentView = "sampleEditor.contentView"
    static let headerPanel = "sampleEditor.headerPanel"
    static let samplesPanel = "sampleEditor.samplesPanel"
    static let instrumentSelector = "sampleEditor.instrumentSelector"
    static let waveformPanel = "sampleEditor.waveformPanel"
    static let waveformView = "sampleEditor.waveformView"
    static let loopPanel = "sampleEditor.loopPanel"
    static let loopPreview = "sampleEditor.loopPreview"
    static let sampleParamsPanel = "sampleEditor.sampleParamsPanel"
    static let generatePanel = "sampleEditor.generatePanel"
    static let filePanel = "sampleEditor.filePanel"
    static let wavLoadButton = "sampleEditor.wavLoadButton"
    static let clearButton = "sampleEditor.clearButton"
    static let auditionButton = "sampleEditor.auditionButton"
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
    var isActionContextActive: Bool {
        windowController?.window?.isVisible == true && windowController?.window?.isKeyWindow == true
    }

    @discardableResult
    func show(
        displayState: SampleEditorDisplayState,
        instrumentSelectionHandler: SampleEditorInstrumentSelectionHandler? = nil,
        sampleSelectionHandler: SampleEditorSampleSelectionHandler? = nil,
        sineGenerationHandler: SampleEditorSineGenerationHandler? = nil,
        wavLoadHandler: SampleEditorWAVLoadHandler? = nil,
        clearHandler: SampleEditorClearHandler? = nil,
        auditionHandlers: SampleEditorAuditionHandlers? = nil
    ) -> SampleEditorWindowController {
        if let windowController {
            windowController.instrumentSelectionHandler = instrumentSelectionHandler
            windowController.sampleSelectionHandler = sampleSelectionHandler
            windowController.sineGenerationHandler = sineGenerationHandler
            windowController.wavLoadHandler = wavLoadHandler
            windowController.clearHandler = clearHandler
            windowController.auditionHandlers = auditionHandlers
            windowController.apply(displayState: displayState)
            windowController.showWindowAndActivate()
            return windowController
        }
        let controller = SampleEditorWindowController(
            displayState: displayState,
            instrumentSelectionHandler: instrumentSelectionHandler,
            sampleSelectionHandler: sampleSelectionHandler,
            sineGenerationHandler: sineGenerationHandler,
            wavLoadHandler: wavLoadHandler,
            clearHandler: clearHandler,
            auditionHandlers: auditionHandlers
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
    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        windowController?.synchronizeActivePreviewToken(token)
    }
}

@MainActor
final class SampleEditorWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 940, height: 560)
    private var didInstallInitialFirstResponder = false
    var closeHandler: (() -> Void)?
    var instrumentSelectionHandler: SampleEditorInstrumentSelectionHandler? {
        didSet { (window?.contentView as? SampleEditorView)?.instrumentSelectionHandler = instrumentSelectionHandler }
    }
    var sampleSelectionHandler: SampleEditorSampleSelectionHandler? {
        didSet { (window?.contentView as? SampleEditorView)?.sampleSelectionHandler = sampleSelectionHandler }
    }
    var sineGenerationHandler: SampleEditorSineGenerationHandler? {
        didSet { (window?.contentView as? SampleEditorView)?.sineGenerationHandler = sineGenerationHandler }
    }
    var wavLoadHandler: SampleEditorWAVLoadHandler? {
        didSet { (window?.contentView as? SampleEditorView)?.wavLoadHandler = wavLoadHandler }
    }
    var clearHandler: SampleEditorClearHandler? {
        didSet { (window?.contentView as? SampleEditorView)?.clearHandler = clearHandler }
    }
    var auditionHandlers: SampleEditorAuditionHandlers? {
        didSet { (window?.contentView as? SampleEditorView)?.auditionHandlers = auditionHandlers }
    }

    init(
        displayState: SampleEditorDisplayState = .empty,
        instrumentSelectionHandler: SampleEditorInstrumentSelectionHandler? = nil,
        sampleSelectionHandler: SampleEditorSampleSelectionHandler? = nil,
        sineGenerationHandler: SampleEditorSineGenerationHandler? = nil,
        wavLoadHandler: SampleEditorWAVLoadHandler? = nil,
        clearHandler: SampleEditorClearHandler? = nil,
        auditionHandlers: SampleEditorAuditionHandlers? = nil
    ) {
        self.instrumentSelectionHandler = instrumentSelectionHandler
        self.sampleSelectionHandler = sampleSelectionHandler
        self.sineGenerationHandler = sineGenerationHandler
        self.wavLoadHandler = wavLoadHandler
        self.clearHandler = clearHandler
        self.auditionHandlers = auditionHandlers
        let view = SampleEditorView(
            frame: NSRect(origin: .zero, size: Self.contentSize),
            displayState: displayState,
            instrumentSelectionHandler: instrumentSelectionHandler,
            sampleSelectionHandler: sampleSelectionHandler,
            sineGenerationHandler: sineGenerationHandler,
            wavLoadHandler: wavLoadHandler,
            clearHandler: clearHandler,
            auditionHandlers: auditionHandlers
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

    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        (window?.contentView as? SampleEditorView)?.synchronizeActivePreviewToken(token)
    }

    func windowDidResignKey(_ notification: Notification) {
        (window?.contentView as? SampleEditorView)?.releaseActiveAudition()
    }

    func windowWillClose(_ notification: Notification) {
        (window?.contentView as? SampleEditorView)?.releaseActiveAudition()
        window?.makeFirstResponder(nil)
        instrumentSelectionHandler = nil
        sampleSelectionHandler = nil
        sineGenerationHandler = nil
        wavLoadHandler = nil
        clearHandler = nil
        auditionHandlers = nil
        closeHandler?()
    }
}

@MainActor
final class SampleEditorView: FlippedEditorView {
    override var acceptsFirstResponder: Bool { true }
    private(set) var displayState: SampleEditorDisplayState
    private(set) var rebuildCount = 0
    private(set) weak var waveformView: SampleWaveformView?
    private(set) weak var instrumentSelector: NSPopUpButton?
    private(set) weak var sineButton: NSButton?
    private(set) weak var wavLoadButton: NSButton?
    private(set) weak var clearButton: NSButton?
    private(set) weak var auditionButton: VTXEditorButton?
    private(set) weak var auditionIndicator: VTXEditorIndicatorLEDView?
    private(set) weak var wavImportProgressIndicator: NSProgressIndicator?
    private(set) var activeAuditionToken: EditorNoteAuditionPreviewToken?
    private var sampleRows: [Int: InstrumentEditorListRowControl] = [:]
    var instrumentSelectionHandler: SampleEditorInstrumentSelectionHandler? {
        didSet { configureInstrumentSelectorHandler() }
    }
    var sampleSelectionHandler: SampleEditorSampleSelectionHandler?
    var sineGenerationHandler: SampleEditorSineGenerationHandler? {
        didSet { configureSineButtonHandler() }
    }
    var wavLoadHandler: SampleEditorWAVLoadHandler? {
        didSet { configureWAVLoadButtonHandler() }
    }
    var clearHandler: SampleEditorClearHandler? {
        didSet { configureClearButtonHandler() }
    }
    var auditionHandlers: SampleEditorAuditionHandlers? {
        didSet { configureAuditionButtonHandler() }
    }

    init(
        frame frameRect: NSRect,
        displayState: SampleEditorDisplayState = .empty,
        instrumentSelectionHandler: SampleEditorInstrumentSelectionHandler? = nil,
        sampleSelectionHandler: SampleEditorSampleSelectionHandler? = nil,
        sineGenerationHandler: SampleEditorSineGenerationHandler? = nil,
        wavLoadHandler: SampleEditorWAVLoadHandler? = nil,
        clearHandler: SampleEditorClearHandler? = nil,
        auditionHandlers: SampleEditorAuditionHandlers? = nil
    ) {
        self.displayState = displayState
        self.instrumentSelectionHandler = instrumentSelectionHandler
        self.sampleSelectionHandler = sampleSelectionHandler
        self.sineGenerationHandler = sineGenerationHandler
        self.wavLoadHandler = wavLoadHandler
        self.clearHandler = clearHandler
        self.auditionHandlers = auditionHandlers
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.contentView)
        style(background: VTXEditorControlTheme.windowBackground)
        buildShell()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func apply(displayState: SampleEditorDisplayState) -> Bool {
        if activeAuditionToken != nil,
           (!displayState.isAuditionEnabled ||
            self.displayState.source != displayState.source ||
            self.displayState.instrumentSlot != displayState.instrumentSlot ||
            self.displayState.selectedSampleSlot != displayState.selectedSampleSlot ||
            self.displayState.selectedSample != displayState.selectedSample) {
            releaseActiveAudition()
        }
        guard self.displayState != displayState else { return false }
        self.displayState = displayState
        rebuildCount += 1
        subviews.forEach { $0.removeFromSuperview() }
        sampleRows.removeAll()
        buildShell()
        return true
    }

    func synchronizeActivePreviewToken(_ token: EditorNoteAuditionPreviewToken?) {
        activeAuditionToken = token?.keyIdentity == .sampleEditorAudition ? token : nil
        updateAuditionVisualState()
    }

    func releaseActiveAudition() {
        guard let token = activeAuditionToken else { return }
        activeAuditionToken = nil
        _ = auditionHandlers?.stop(token)
        updateAuditionVisualState()
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
        let button = VTXEditorControlFactory.makeButton(title: "▶", role: .activePlay, fixedWidth: 35)
        button.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.auditionButton)
        addControl(button, to: parent, frame: NSRect(x: 802, y: 12, width: 35, height: 25))
        auditionButton = button
        let indicator = VTXEditorControlFactory.makeIndicatorLED(state: .off)
        addControl(indicator, to: parent, frame: NSRect(x: 847, y: 21, width: 8, height: 8))
        auditionIndicator = indicator
        configureAuditionButtonHandler()
    }

    private func configureAuditionButtonHandler() {
        guard let button = auditionButton else { return }
        let enabled = displayState.isAuditionEnabled && auditionHandlers != nil
        button.isEnabled = enabled
        button.target = enabled ? self : nil
        button.action = enabled ? #selector(toggleAudition(_:)) : nil
        button.setAccessibilityEnabled(enabled)
        button.setAccessibilityLabel("Audition selected sample")
        updateAuditionVisualState()
    }

    private func updateAuditionVisualState() {
        let isActive = activeAuditionToken != nil
        auditionButton?.title = isActive ? "■" : "▶"
        auditionButton?.apply(role: isActive ? .selected : .activePlay)
        auditionButton?.setAccessibilityValue(isActive ? "Active at fixed note C-4" : "Stopped at fixed note C-4")
        auditionIndicator?.state = isActive ? .redActive : .off
    }

    @objc private func toggleAudition(_ sender: NSButton) {
        if activeAuditionToken != nil { releaseActiveAudition(); return }
        guard displayState.isAuditionEnabled,
              let token = auditionHandlers?.start(),
              token.keyIdentity == .sampleEditorAudition,
              token.noteValue == SampleEditorAuditionRequestFactory.noteValue else {
            synchronizeActivePreviewToken(nil)
            return
        }
        synchronizeActivePreviewToken(token)
    }

    private func buildSamples(_ parent: NSView) {
        let selector = NSPopUpButton(frame: .zero, pullsDown: false)
        TrackerThemeStyling.applyPopupChrome(selector, width: nil, minimumWidth: nil, theme: .legacyDark)
        selector.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.instrumentSelector)
        selector.setAccessibilityLabel("Sample Editor instrument")
        for option in displayState.instrumentOptions {
            selector.addItem(withTitle: option.title)
            selector.lastItem?.representedObject = option.slot
            selector.lastItem?.toolTip = option.title
        }
        if let selectedIndex = displayState.instrumentOptions.firstIndex(where: \.isSelected) {
            selector.selectItem(at: selectedIndex)
        } else {
            selector.select(nil)
        }
        let selectedTitle = displayState.instrumentOptions.first(where: \.isSelected)?.title
        selector.toolTip = selectedTitle ?? displayState.emptyMessage
        selector.setAccessibilityValue(selectedTitle ?? "No instrument selected")
        addControl(selector, to: parent, frame: NSRect(x: 10, y: 24, width: 152, height: 26))
        instrumentSelector = selector
        configureInstrumentSelectorHandler()

        let frame = NSRect(x: 10, y: 58, width: 152, height: 156)
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
            row.setAccessibilityLabel(slot.isEmptyDestination
                ? "\(slot.display), empty sample destination"
                : "\(slot.display), \(slot.name)")
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
        if let selectedIndex = displayState.sampleSlots.firstIndex(where: \.isSelected) {
            rows.scrollToVisible(NSRect(
                x: 0, y: CGFloat(selectedIndex) * rowHeight,
                width: rows.bounds.width, height: rowHeight
            ))
        }
    }

    private func configureInstrumentSelectorHandler() {
        guard let selector = instrumentSelector else { return }
        let isEnabled = !displayState.instrumentOptions.isEmpty && instrumentSelectionHandler != nil
        selector.isEnabled = isEnabled
        selector.target = isEnabled ? self : nil
        selector.action = isEnabled ? #selector(selectInstrument(_:)) : nil
        selector.setAccessibilityEnabled(isEnabled)
    }

    @objc private func selectInstrument(_ sender: NSPopUpButton) {
        guard let slot = sender.selectedItem?.representedObject as? Int,
              displayState.instrumentOptions.contains(where: { $0.slot == slot }) else { return }
        guard instrumentSelectionHandler?(slot) == true else {
            if let selectedIndex = displayState.instrumentOptions.firstIndex(where: \.isSelected) {
                sender.selectItem(at: selectedIndex)
            } else {
                sender.select(nil)
            }
            return
        }
        window?.makeFirstResponder(instrumentSelector ?? sender)
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

    // Swift 6.3.2's CopyPropagation pass crashes on this UI-only function.
    @_optimize(none)
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
        label("— SELECTED EMPTY GENERATION", parent, NSRect(x: 80, y: 10, width: 210, height: 11), color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8)
        let entries = ["∿\nSINE", "⊓\nSQUARE", "⊿\nTRI", "◺\nSAW", "▦\nNOISE"]
        let sine = VTXEditorControlFactory.makeButton(title: entries[0], role: .normal, fixedWidth: 68)
        sine.identifier = futureID("generate0")
        addControl(sine, to: parent, frame: NSRect(x: 10, y: 29, width: 68, height: 42))
        sineButton = sine
        configureSineButtonHandler()
        for (index, title) in entries.enumerated().dropFirst() {
            futureButton(title, id: "generate\(index)", parent, NSRect(x: 10 + CGFloat(index) * 74, y: 29, width: 68, height: 42))
        }
    }

    private func configureSineButtonHandler() {
        guard let sineButton else { return }
        let enabled = displayState.isSineGenerationEnabled && sineGenerationHandler != nil
        sineButton.isEnabled = enabled
        sineButton.target = enabled ? self : nil
        sineButton.action = enabled ? #selector(generateSine(_:)) : nil
        sineButton.alphaValue = enabled ? 1 : 0.38
        sineButton.setAccessibilityEnabled(enabled)
    }

    @objc private func generateSine(_ sender: NSButton) {
        guard displayState.isSineGenerationEnabled else { return }
        _ = sineGenerationHandler?()
    }

    private func buildFile(_ parent: NSView) {
        label(
            displayState.isImportingWAV ? "— IMPORTING SAMPLE" : "— WAV · AIFF · AIFC · FLAC LOAD",
            parent, NSRect(x: 48, y: 10, width: 300, height: 11),
            color: VTXEditorControlTheme.warmValueText.withAlphaComponent(0.28), size: 8
        )
        if displayState.isImportingWAV {
            let progress = NSProgressIndicator(frame: NSRect(x: 350, y: 7, width: 14, height: 14))
            progress.style = .spinning
            progress.controlSize = .small
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            parent.addSubview(progress)
            wavImportProgressIndicator = progress
        }
        let load = VTXEditorControlFactory.makeButton(title: "⤓\nLOAD", role: .normal, fixedWidth: 87)
        load.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.wavLoadButton)
        addControl(load, to: parent, frame: NSRect(x: 10, y: 31, width: 87, height: 45))
        wavLoadButton = load
        configureWAVLoadButtonHandler()
        futureButton("⤒\nEXPORT", id: "file1", parent, NSRect(x: 103, y: 31, width: 87, height: 45))
        let clear = VTXEditorControlFactory.makeButton(title: "⌫\nCLEAR", role: .danger, fixedWidth: 87)
        clear.identifier = NSUserInterfaceItemIdentifier(SampleEditorViewIdentifier.clearButton)
        addControl(clear, to: parent, frame: NSRect(x: 196, y: 31, width: 87, height: 45))
        clearButton = clear
        configureClearButtonHandler()
        futureButton(
            "⟲\nREPLACE", id: "file3", parent,
            NSRect(x: 289, y: 31, width: 87, height: 45), role: .danger
        )
    }

    private func configureWAVLoadButtonHandler() {
        guard let wavLoadButton else { return }
        let enabled = displayState.isWAVLoadEnabled && wavLoadHandler != nil
        wavLoadButton.isEnabled = enabled
        wavLoadButton.target = enabled ? self : nil
        wavLoadButton.action = enabled ? #selector(loadWAV(_:)) : nil
        wavLoadButton.alphaValue = enabled ? 1 : 0.38
        wavLoadButton.setAccessibilityEnabled(enabled)
    }

    @objc private func loadWAV(_ sender: NSButton) {
        guard displayState.isWAVLoadEnabled else { return }
        _ = wavLoadHandler?()
    }

    private func configureClearButtonHandler() {
        guard let clearButton else { return }
        let enabled = displayState.isClearEnabled && clearHandler != nil
        clearButton.isEnabled = enabled
        clearButton.target = enabled ? self : nil
        clearButton.action = enabled ? #selector(clearSelectedSample(_:)) : nil
        clearButton.alphaValue = enabled ? 1 : 0.38
        clearButton.setAccessibilityEnabled(enabled)
        clearButton.setAccessibilityLabel("Clear selected sample")
    }

    @objc private func clearSelectedSample(_ sender: NSButton) {
        guard displayState.isClearEnabled else { return }
        _ = clearHandler?()
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
