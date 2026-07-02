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
    let isPlaybackActive: Bool
    let displayName: String?
    let hasValidEditableState: Bool

    static func editable(
        displayName: String?,
        isPlaybackActive: Bool,
        hasValidEditableState: Bool = true
    ) -> ExportXMDocumentContext {
        ExportXMDocumentContext(
            kind: .editable,
            isPlaybackActive: isPlaybackActive,
            displayName: displayName,
            hasValidEditableState: hasValidEditableState
        )
    }

    static func loadedReadOnly(isPlaybackActive: Bool) -> ExportXMDocumentContext {
        ExportXMDocumentContext(
            kind: .loadedReadOnly,
            isPlaybackActive: isPlaybackActive,
            displayName: nil,
            hasValidEditableState: false
        )
    }

    static func none(isPlaybackActive: Bool) -> ExportXMDocumentContext {
        ExportXMDocumentContext(
            kind: .none,
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

enum ExportXMShellResult: Equatable {
    case unavailable(ExportXMUnavailableReason)
    case cancelled
    case pendingNotImplemented(destination: URL)

    var userFacingMessage: String? {
        switch self {
        case .pendingNotImplemented:
            return ExportXMCoordinator.notImplementedMessage
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
    nonisolated static let notImplementedMessage = "Export XM is not implemented yet. This build only wires the export destination flow."

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
            return context.hasValidEditableState ? nil : .invalidEditableDocumentState
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

        return .pendingNotImplemented(destination: destination)
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
        return normalizedXMURL(url, fileExtension: request.allowedFileExtension)
    }

    private func normalizedXMURL(_ url: URL, fileExtension: String) -> URL {
        guard url.pathExtension.lowercased() != fileExtension.lowercased() else {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(fileExtension)
    }
}
