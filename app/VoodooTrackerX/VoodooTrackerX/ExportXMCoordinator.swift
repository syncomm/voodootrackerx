import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportXMDocumentKind: Equatable {
    case none
    case editable
    case loadedReadOnly
}

struct ExportXMDocumentContext: Equatable {
    let kind: ExportXMDocumentKind
    let editableDocument: BlankTrackerDocument?
    let isPlaybackActive: Bool
    let displayName: String?
    let hasValidEditableState: Bool

    static func editable(
        document: BlankTrackerDocument?,
        displayName: String?,
        isPlaybackActive: Bool,
        hasValidEditableState: Bool = true
    ) -> ExportXMDocumentContext {
        ExportXMDocumentContext(
            kind: .editable,
            editableDocument: document,
            isPlaybackActive: isPlaybackActive,
            displayName: displayName,
            hasValidEditableState: hasValidEditableState
        )
    }

    static func loadedReadOnly(isPlaybackActive: Bool) -> ExportXMDocumentContext {
        ExportXMDocumentContext(
            kind: .loadedReadOnly,
            editableDocument: nil,
            isPlaybackActive: isPlaybackActive,
            displayName: nil,
            hasValidEditableState: false
        )
    }

    static func none(isPlaybackActive: Bool) -> ExportXMDocumentContext {
        ExportXMDocumentContext(
            kind: .none,
            editableDocument: nil,
            isPlaybackActive: isPlaybackActive,
            displayName: nil,
            hasValidEditableState: false
        )
    }
}

enum ExportXMUnavailableReason: Equatable {
    case noDocument
    case loadedModuleReadOnly
    case playbackActive
    case invalidEditableDocumentState
}

struct ExportXMDestinationRequest: Equatable {
    static let fileExtension = "xm"

    let suggestedFilename: String
    let allowedFileExtension: String

    init(suggestedFilename: String, allowedFileExtension: String = Self.fileExtension) {
        self.suggestedFilename = suggestedFilename
        self.allowedFileExtension = allowedFileExtension
    }
}

enum ExportXMFailure: Equatable {
    case writerFailed(String)
    case fileWriteFailed(String)

    var userFacingMessage: String {
        switch self {
        case let .writerFailed(message):
            return "Could not build XM data. \(message)"
        case let .fileWriteFailed(message):
            return "Could not write XM file. \(message)"
        }
    }
}

enum ExportXMShellResult: Equatable {
    case unavailable(ExportXMUnavailableReason)
    case cancelled
    case exported(destination: URL)
    case failed(ExportXMFailure)

    var userFacingTitle: String? {
        switch self {
        case .exported:
            return "Export XM Completed"
        case .failed:
            return "Export XM Failed"
        case .unavailable, .cancelled:
            return nil
        }
    }

    var userFacingMessage: String? {
        switch self {
        case .exported:
            return "Export XM completed."
        case let .failed(failure):
            return "Export XM failed: \(failure.userFacingMessage)"
        case .unavailable, .cancelled:
            return nil
        }
    }
}

@MainActor
protocol ExportXMDestinationProviding {
    func chooseExportXMDestination(request: ExportXMDestinationRequest) -> URL?
}

@MainActor
struct ExportXMCoordinator {
    private let destinationProvider: any ExportXMDestinationProviding

    init(destinationProvider: any ExportXMDestinationProviding) {
        self.destinationProvider = destinationProvider
    }

    static func canExport(context: ExportXMDocumentContext) -> Bool {
        unavailableReason(for: context) == nil
    }

    static func unavailableReason(for context: ExportXMDocumentContext) -> ExportXMUnavailableReason? {
        switch context.kind {
        case .none:
            return .noDocument
        case .editable, .loadedReadOnly:
            break
        }

        guard !context.isPlaybackActive else {
            return .playbackActive
        }

        switch context.kind {
        case .none:
            return .noDocument
        case .loadedReadOnly:
            return .loadedModuleReadOnly
        case .editable:
            return context.hasValidEditableState && context.editableDocument != nil
                ? nil
                : .invalidEditableDocumentState
        }
    }

    func beginExport(context: ExportXMDocumentContext) -> ExportXMShellResult {
        if let reason = Self.unavailableReason(for: context) {
            return .unavailable(reason)
        }

        let request = ExportXMDestinationRequest(
            suggestedFilename: Self.defaultFilename(displayName: context.displayName)
        )
        guard let destination = destinationProvider.chooseExportXMDestination(request: request) else {
            return .cancelled
        }
        let normalizedDestination = Self.normalizedXMURL(
            destination,
            fileExtension: request.allowedFileExtension
        )

        guard let document = context.editableDocument else {
            return .unavailable(.invalidEditableDocumentState)
        }

        let data: Data
        do {
            data = try EditableXMWriter().data(from: document)
        } catch {
            return .failed(.writerFailed(Self.errorMessage(from: error)))
        }

        do {
            try data.write(to: normalizedDestination, options: .atomic)
        } catch {
            return .failed(.fileWriteFailed(Self.errorMessage(from: error)))
        }

        return .exported(destination: normalizedDestination)
    }

    static func defaultFilename(displayName: String?) -> String {
        let rawName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sanitizedBaseName = sanitizedFilenameBase(rawName)
        guard !sanitizedBaseName.lowercased().hasSuffix(".xm") else {
            return sanitizedBaseName
        }
        return "\(sanitizedBaseName).xm"
    }

    private static func sanitizedFilenameBase(_ rawName: String) -> String {
        let invalidScalars = CharacterSet(charactersIn: "/\\:")
            .union(.newlines)
            .union(.controlCharacters)
        var scalars = String.UnicodeScalarView()
        for scalar in rawName.unicodeScalars {
            scalars.append(invalidScalars.contains(scalar) ? "-" : scalar)
        }

        let trimmed = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return trimmed.isEmpty ? BlankTrackerDocument.defaultTitle : trimmed
    }

    static func normalizedXMURL(
        _ url: URL,
        fileExtension: String = ExportXMDestinationRequest.fileExtension
    ) -> URL {
        guard url.pathExtension.lowercased() != fileExtension.lowercased() else {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    private static func errorMessage(from error: any Error) -> String {
        if let writerError = error as? EditableXMWriterError {
            return String(describing: writerError)
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        let localizedDescription = (error as NSError).localizedDescription
        return localizedDescription.isEmpty ? String(describing: error) : localizedDescription
    }
}

@MainActor
final class NSSavePanelExportXMDestinationProvider: ExportXMDestinationProviding {
    func chooseExportXMDestination(request: ExportXMDestinationRequest) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Choose a destination for the XM export"
        panel.nameFieldStringValue = request.suggestedFilename
        if let xmContentType = UTType(filenameExtension: request.allowedFileExtension) {
            panel.allowedContentTypes = [xmContentType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return ExportXMCoordinator.normalizedXMURL(url, fileExtension: request.allowedFileExtension)
    }
}
