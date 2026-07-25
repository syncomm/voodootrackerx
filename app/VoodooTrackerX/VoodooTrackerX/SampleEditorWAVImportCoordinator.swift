import AppKit
import UniformTypeIdentifiers

struct SampleEditorWAVFileRequest: Equatable, Sendable {
    static let audio = SampleEditorWAVFileRequest(
        allowedFileExtensions: ["wav", "wave", "aif", "aiff", "aifc", "flac"]
    )

    let allowedFileExtensions: [String]
}

@MainActor
enum SampleEditorWAVOpenPanel {
    static func make(request: SampleEditorWAVFileRequest) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = request.allowedFileExtensions
            .compactMap { UTType(filenameExtension: $0) }
            .filter { $0.conforms(to: .audio) }
            .reduce(into: []) { types, type in
                if !types.contains(where: { $0.identifier == type.identifier }) { types.append(type) }
            }
        panel.title = "Load Sample"
        panel.message = "Load Sample"
        return panel
    }
}

enum SampleEditorOccupiedSampleImportChoice: Equatable {
    case replaceCurrent, addAsNew
}

enum SampleEditorAudioImportAction: Equatable {
    case fillOrReplace(SampleImportDestination)
    case addAsNew(instrumentIndex: Int, originalSampleCount: Int)
}

@MainActor
enum SampleEditorOccupiedImportAlert {
    static let maximumMessage = "This instrument already contains the XM maximum of \(BlankTrackerDocument.maximumSampleCountPerInstrument) samples."

    static func make(canAddAsNew: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Load Audio Sample"
        alert.informativeText = """
        Replace Current Sample keeps the current slot and its references. \
        Add as New Sample appends a represented sample and leaves the keymap unchanged.
        """ + (canAddAsNew ? "" : "\n\(maximumMessage)")
        ["Replace Current Sample", "Add as New Sample", "Cancel"].forEach { alert.addButton(withTitle: $0) }
        alert.buttons[1].isEnabled = canAddAsNew
        return alert
    }

    static func choice(for response: NSApplication.ModalResponse) -> SampleEditorOccupiedSampleImportChoice? {
        switch response {
        case .alertFirstButtonReturn: .replaceCurrent
        case .alertSecondButtonReturn: .addAsNew
        default: nil
        }
    }
}

struct SampleEditorWAVImportContext: Equatable {
    let documentIdentity: UUID?
    let documentRevision: UInt64
    let document: BlankTrackerDocument?
    let isPlaybackActive: Bool
}

struct SampleEditorWAVImportCapture: Equatable {
    let documentIdentity: UUID
    let documentRevision: UInt64
    let destination: SampleImportDestination
    let originalRepresentedSampleCount: Int
    let canAddAsNew: Bool

    init?(context: SampleEditorWAVImportContext) {
        guard let documentIdentity = context.documentIdentity,
              let document = context.document,
              let destination = document.selectedSampleImportDestination,
              let instrument = document.instrument(forInstrument: destination.instrumentIndex),
              !context.isPlaybackActive else { return nil }
        self.documentIdentity = documentIdentity
        documentRevision = context.documentRevision
        self.destination = destination
        originalRepresentedSampleCount = instrument.samples.count
        canAddAsNew = destination.requiresReplacementConfirmation && document.canAppendSample(toInstrument: instrument.index)
    }

    func isCurrent(in context: SampleEditorWAVImportContext, action: SampleEditorAudioImportAction? = nil) -> Bool {
        let matchesCapture = !context.isPlaybackActive &&
            context.documentIdentity == documentIdentity &&
            context.documentRevision == documentRevision &&
            context.document?.selectedSampleImportDestination == destination &&
            context.document?.instrument(forInstrument: destination.instrumentIndex)?.samples.count == originalRepresentedSampleCount
        guard matchesCapture else { return false }
        if case let .addAsNew(instrumentIndex, _) = action {
            return context.document?.canAppendSample(toInstrument: instrumentIndex) == true
        }
        return true
    }
}

struct SampleEditorWAVImportWorker: Sendable {
    typealias Inspect = @Sendable (URL) async -> Result<SampleImportInspection, SampleImportError>
    typealias Normalize = @Sendable (URL, SampleImportChannelMode) async -> Result<NormalizedSampleImport, SampleImportError>

    let inspect: Inspect
    let normalize: Normalize

    static func background(
        inspect: @escaping @Sendable (URL) throws -> SampleImportInspection,
        normalize: @escaping @Sendable (URL, SampleImportChannelMode) throws -> NormalizedSampleImport
    ) -> Self {
        Self(
            inspect: { url in
                await Task.detached(priority: .userInitiated) {
                    do { return .success(try inspect(url)) }
                    catch let error as SampleImportError { return .failure(error) }
                    catch { return .failure(.audioDecodeFailed) }
                }.value
            },
            normalize: { url, mode in
                await Task.detached(priority: .userInitiated) {
                    do { return .success(try normalize(url, mode)) }
                    catch let error as SampleImportError { return .failure(error) }
                    catch { return .failure(.audioDecodeFailed) }
                }.value
            }
        )
    }

    static func live(decoder: SampleImportDecoder = SampleImportDecoder()) -> Self {
        background(
            inspect: { try decoder.inspect(url: $0) },
            normalize: { try decoder.normalizedImport(url: $0, channelMode: $1) }
        )
    }
}

@MainActor
final class SampleEditorWAVImportCoordinator {
    typealias FileChooser = (SampleEditorWAVFileRequest, @escaping @MainActor (URL?) -> Void) -> Void
    typealias OccupiedSampleChoice =
        (_ canAddAsNew: Bool, _ completion: @escaping @MainActor (SampleEditorOccupiedSampleImportChoice?) -> Void) -> Void
    typealias StereoChannelChooser = (@escaping @MainActor (SampleImportChannelMode?) -> Void) -> Void

    private let contextProvider: () -> SampleEditorWAVImportContext
    private let worker: SampleEditorWAVImportWorker
    private let fileChooser: FileChooser
    private let occupiedSampleChoice: OccupiedSampleChoice
    private let stereoChannelChooser: StereoChannelChooser
    private let commitHandler: (NormalizedSampleImport, SampleEditorAudioImportAction) -> Bool
    private let errorHandler: (String) -> Void
    private let importingStateHandler: (Bool) -> Void
    private var operationToken: UUID?
    private var capture: SampleEditorWAVImportCapture?
    private var action: SampleEditorAudioImportAction?

    init(
        contextProvider: @escaping () -> SampleEditorWAVImportContext,
        worker: SampleEditorWAVImportWorker,
        fileChooser: @escaping FileChooser,
        occupiedSampleChoice: @escaping OccupiedSampleChoice,
        stereoChannelChooser: @escaping StereoChannelChooser,
        commitHandler: @escaping (NormalizedSampleImport, SampleEditorAudioImportAction) -> Bool,
        errorHandler: @escaping (String) -> Void,
        importingStateHandler: @escaping (Bool) -> Void = { _ in }
    ) {
        self.contextProvider = contextProvider
        self.worker = worker
        self.fileChooser = fileChooser
        self.occupiedSampleChoice = occupiedSampleChoice
        self.stereoChannelChooser = stereoChannelChooser
        self.commitHandler = commitHandler
        self.errorHandler = errorHandler
        self.importingStateHandler = importingStateHandler
    }

    var isImporting: Bool { operationToken != nil }

    @discardableResult
    func begin() -> Bool {
        guard operationToken == nil,
              let capture = SampleEditorWAVImportCapture(context: contextProvider()) else { return false }
        let token = UUID()
        operationToken = token
        self.capture = capture
        importingStateHandler(true)
        fileChooser(.audio) { [weak self] url in self?.didChooseFile(url, token: token) }
        return true
    }

    private func didChooseFile(_ url: URL?, token: UUID) {
        guard isCurrent(token), let capture else { return }
        guard let url else { finish(token); return }
        guard capture.isCurrent(in: contextProvider()) else { finish(token); return }
        if capture.destination.requiresReplacementConfirmation {
            occupiedSampleChoice(capture.canAddAsNew) { [weak self] choice in
                guard let self, self.isCurrent(token) else { return }
                guard capture.isCurrent(in: self.contextProvider()) else { self.finish(token); return }
                guard let choice else { self.finish(token); return }
                switch choice {
                case .replaceCurrent: self.action = .fillOrReplace(capture.destination)
                case .addAsNew:
                    guard capture.canAddAsNew else {
                        self.finish(token)
                        self.errorHandler(SampleEditorOccupiedImportAlert.maximumMessage)
                        return
                    }
                    self.action = .addAsNew(instrumentIndex: capture.destination.instrumentIndex, originalSampleCount: capture.originalRepresentedSampleCount)
                }
                self.startInspection(url, token: token)
            }
        } else {
            action = .fillOrReplace(capture.destination)
            startInspection(url, token: token)
        }
    }

    private func startInspection(_ url: URL, token: UUID) {
        guard let action, let capture,
              capture.isCurrent(in: contextProvider(), action: action) else {
            finish(token)
            return
        }
        let worker = worker
        Task { [weak self] in
            let result = await worker.inspect(url)
            self?.didInspect(result, url: url, token: token)
        }
    }

    private func didInspect(
        _ result: Result<SampleImportInspection, SampleImportError>,
        url: URL,
        token: UUID
    ) {
        guard isCurrent(token), let capture,
              capture.isCurrent(in: contextProvider(), action: action) else {
            finish(token)
            return
        }
        switch result {
        case let .failure(error): fail(error, token: token)
        case let .success(inspection):
            if inspection.sourceChannelCount == 1 {
                startNormalization(url, mode: .mixToMono, token: token)
            } else if inspection.sourceChannelCount == 2 {
                stereoChannelChooser { [weak self] mode in
                    guard let self, self.isCurrent(token) else { return }
                    guard let mode else { self.finish(token); return }
                    self.startNormalization(url, mode: mode, token: token)
                }
            } else {
                fail(.unsupportedChannelCount(inspection.sourceChannelCount), token: token)
            }
        }
    }

    private func startNormalization(_ url: URL, mode: SampleImportChannelMode, token: UUID) {
        guard let capture,
              capture.isCurrent(in: contextProvider(), action: action) else {
            finish(token)
            return
        }
        let worker = worker
        Task { [weak self] in
            let result = await worker.normalize(url, mode)
            self?.didNormalize(result, token: token)
        }
    }

    private func didNormalize(_ result: Result<NormalizedSampleImport, SampleImportError>, token: UUID) {
        guard isCurrent(token), let capture, let action,
              capture.isCurrent(in: contextProvider(), action: action) else {
            finish(token)
            return
        }
        switch result {
        case let .failure(error): fail(error, token: token)
        case let .success(candidate):
            guard candidate.isValidDocumentSample else { fail(.nonFinitePCM, token: token); return }
            _ = commitHandler(candidate, action)
            finish(token)
        }
    }

    private func fail(_ error: SampleImportError, token: UUID) {
        finish(token)
        errorHandler(error.userFacingMessage)
    }

    private func isCurrent(_ token: UUID) -> Bool { operationToken == token }

    private func finish(_ token: UUID) {
        guard isCurrent(token) else { return }
        operationToken = nil
        capture = nil
        action = nil
        importingStateHandler(false)
    }
}
