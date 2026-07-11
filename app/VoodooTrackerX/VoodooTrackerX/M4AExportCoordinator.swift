import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

typealias M4AExportDocumentContext = WAVExportDocumentContext
typealias M4AExportUnavailableReason = WAVExportUnavailableReason
typealias M4AExportCancellationToken = WAVExportCancellationToken

struct M4AExportDestinationRequest: Equatable {
    static let fileExtension = "m4a"

    let suggestedFilename: String
    let allowedFileExtension: String

    init(suggestedFilename: String, allowedFileExtension: String = Self.fileExtension) {
        self.suggestedFilename = suggestedFilename
        self.allowedFileExtension = allowedFileExtension
    }
}

struct M4AAudioEncoderConfiguration: Equatable, Sendable {
    static let productDefault = M4AAudioEncoderConfiguration(
        sampleRate: AudioExportRenderProfile.productWAVExport.sampleRate,
        channelCount: AudioExportRenderProfile.productWAVExport.channelCount,
        bitRate: 192_000,
        chunkFrameCount: 8_192
    )

    let sampleRate: Double
    let channelCount: Int
    let bitRate: Int
    let chunkFrameCount: Int
}

struct M4AAudioEncoderProgress: Equatable, Sendable {
    let completedFrames: Int
    let totalFrames: Int
}

typealias M4AAudioEncoderProgressHandler = @Sendable (M4AAudioEncoderProgress) -> Void

struct M4AAudioEncodingResult: Equatable, Sendable {
    let sourceFrameCount: Int
    let sampleRate: Double
    let channelCount: Int
}

protocol M4AAudioEncoding: Sendable {
    func encodeFloat32WAV(
        at sourceURL: URL,
        to destinationURL: URL,
        configuration: M4AAudioEncoderConfiguration,
        cancellationCheck: @Sendable () throws -> Void,
        progress: M4AAudioEncoderProgressHandler?
    ) throws -> M4AAudioEncodingResult
}

enum M4AAudioEncoderError: LocalizedError {
    case invalidSource(String)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSource(message):
            return "The rendered Float32 audio could not be encoded. \(message)"
        case let .encodingFailed(message):
            return "AAC encoding failed. \(message)"
        }
    }
}

struct AVFoundationM4AAudioEncoder: M4AAudioEncoding {
    func encodeFloat32WAV(
        at sourceURL: URL,
        to destinationURL: URL,
        configuration: M4AAudioEncoderConfiguration,
        cancellationCheck: @Sendable () throws -> Void,
        progress: M4AAudioEncoderProgressHandler?
    ) throws -> M4AAudioEncodingResult {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        do {
            try cancellationCheck()
            return try encode(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                configuration: configuration,
                cancellationCheck: cancellationCheck,
                progress: progress
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let encoderError = error as? M4AAudioEncoderError {
                throw encoderError
            }
            throw M4AAudioEncoderError.encodingFailed(Self.errorMessage(from: error))
        }
    }

    private func encode(
        sourceURL: URL,
        destinationURL: URL,
        configuration: M4AAudioEncoderConfiguration,
        cancellationCheck: @Sendable () throws -> Void,
        progress: M4AAudioEncoderProgressHandler?
    ) throws -> M4AAudioEncodingResult {
        guard destinationURL.pathExtension.lowercased() == M4AExportDestinationRequest.fileExtension else {
            throw M4AAudioEncoderError.invalidSource("The encoder destination must use the .m4a extension.")
        }
        guard configuration.sampleRate > 0,
              configuration.channelCount > 0,
              configuration.bitRate > 0,
              configuration.chunkFrameCount > 0 else {
            throw M4AAudioEncoderError.invalidSource("The encoder configuration is invalid.")
        }

        let source = try AVAudioFile(
            forReading: sourceURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )
        let fileSettings = source.fileFormat.settings
        guard source.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              (fileSettings[AVLinearPCMIsFloatKey] as? Bool) == true,
              (fileSettings[AVLinearPCMBitDepthKey] as? Int) == 32 else {
            throw M4AAudioEncoderError.invalidSource("Expected 32-bit Float WAV input.")
        }
        guard abs(source.processingFormat.sampleRate - configuration.sampleRate) < 0.5,
              Int(source.processingFormat.channelCount) == configuration.channelCount else {
            throw M4AAudioEncoderError.invalidSource("The render format does not match the product export profile.")
        }
        let totalFrames = Int(source.length)
        guard totalFrames > 0 else {
            throw M4AAudioEncoderError.invalidSource("The rendered audio is empty.")
        }
        try cancellationCheck()

        let output = try AVAudioFile(
            forWriting: destinationURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: configuration.sampleRate,
                AVNumberOfChannelsKey: configuration.channelCount,
                AVEncoderBitRateKey: configuration.bitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: source.processingFormat,
            frameCapacity: AVAudioFrameCount(configuration.chunkFrameCount)
        ) else {
            throw M4AAudioEncoderError.encodingFailed("Could not allocate the Float32 conversion buffer.")
        }
        try cancellationCheck()

        var completedFrames = 0
        while completedFrames < totalFrames {
            try cancellationCheck()
            let requestedFrames = min(configuration.chunkFrameCount, totalFrames - completedFrames)
            try source.read(into: buffer, frameCount: AVAudioFrameCount(requestedFrames))
            guard buffer.frameLength > 0 else {
                break
            }
            try output.write(from: buffer)
            completedFrames += Int(buffer.frameLength)
            progress?(M4AAudioEncoderProgress(
                completedFrames: min(totalFrames, completedFrames),
                totalFrames: totalFrames
            ))
            try cancellationCheck()
        }
        guard completedFrames == totalFrames else {
            throw M4AAudioEncoderError.encodingFailed(
                "Encoded \(completedFrames) of \(totalFrames) rendered frames."
            )
        }
        return M4AAudioEncodingResult(
            sourceFrameCount: totalFrames,
            sampleRate: configuration.sampleRate,
            channelCount: configuration.channelCount
        )
    }

    private static func errorMessage(from error: any Error) -> String {
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? String(describing: error) : message
    }
}

struct M4AExportPlan: @unchecked Sendable {
    let renderPlan: WAVExportPlan
    let encoderConfiguration: M4AAudioEncoderConfiguration
    let suggestedFilename: String
}

enum M4AExportStartResult {
    case unavailable(M4AExportUnavailableReason)
    case cancelled
    case ready(plan: M4AExportPlan, destination: URL)
}

enum M4AExportFailure: Equatable, Sendable {
    case renderFailed(String)
    case encodingFailed(String)
    case fileWriteFailed(String)
}

enum M4AExportCompletionResult: @unchecked Sendable {
    case exported(
        destination: URL,
        renderResult: PlaybackSongOfflineStreamingRenderResult,
        encodingResult: M4AAudioEncodingResult
    )
    case cancelled
    case failed(M4AExportFailure)

    var userFacingTitle: String {
        switch self {
        case .exported:
            return "Export Audio Completed"
        case .cancelled:
            return "Export Audio Cancelled"
        case .failed:
            return "Export M4A Failed"
        }
    }

    var userFacingMessage: String {
        switch self {
        case .exported:
            return "M4A file saved successfully."
        case .cancelled:
            return "M4A export was cancelled."
        case let .failed(.renderFailed(message)):
            return "Could not render audio for M4A export. \(message)"
        case let .failed(.encodingFailed(message)):
            return "Could not encode AAC audio. \(message)"
        case let .failed(.fileWriteFailed(message)):
            return "Could not write the M4A file. \(message)"
        }
    }
}

enum M4AExportProgressStage: Equatable, Sendable {
    case preparingRender
    case rendering
    case applyingHeadroom
    case encoding
    case writingFile
    case completed
}

struct M4AExportProgress: Equatable, Sendable {
    let stage: M4AExportProgressStage
    let completedFrames: Int
    let totalFrames: Int
    let completedWindows: Int
    let totalWindows: Int
    let fractionCompleted: Double

    var isIndeterminate: Bool {
        stage == .preparingRender
    }
}

typealias M4AExportProgressHandler = @Sendable (M4AExportProgress) -> Void

@MainActor
protocol M4AExportDestinationProviding {
    func chooseM4AExportDestination(request: M4AExportDestinationRequest) -> URL?
}

struct M4AExportCoordinator {
    static let defaultEncoderConfiguration = M4AAudioEncoderConfiguration.productDefault

    private let destinationProvider: any M4AExportDestinationProviding

    @MainActor
    init(destinationProvider: any M4AExportDestinationProviding) {
        self.destinationProvider = destinationProvider
    }

    static func canExport(context: M4AExportDocumentContext) -> Bool {
        WAVExportCoordinator.canExport(context: context)
    }

    static func unavailableReason(for context: M4AExportDocumentContext) -> M4AExportUnavailableReason? {
        WAVExportCoordinator.unavailableReason(for: context)
    }

    static func makePlan(context: M4AExportDocumentContext) throws -> M4AExportPlan {
        M4AExportPlan(
            renderPlan: try WAVExportCoordinator.makePlan(context: context),
            encoderConfiguration: defaultEncoderConfiguration,
            suggestedFilename: defaultFilename(displayName: context.displayName)
        )
    }

    @MainActor
    func beginExport(context: M4AExportDocumentContext) -> M4AExportStartResult {
        if let reason = Self.unavailableReason(for: context) {
            return .unavailable(reason)
        }
        let plan: M4AExportPlan
        do {
            plan = try Self.makePlan(context: context)
        } catch {
            return .unavailable(.exportPlanUnavailable(Self.errorMessage(from: error)))
        }
        let request = M4AExportDestinationRequest(suggestedFilename: plan.suggestedFilename)
        guard let destination = destinationProvider.chooseM4AExportDestination(request: request) else {
            return .cancelled
        }
        return .ready(
            plan: plan,
            destination: Self.normalizedM4AURL(destination, fileExtension: request.allowedFileExtension)
        )
    }

    static func export(
        plan: M4AExportPlan,
        to destination: URL,
        fileManager: FileManager = .default,
        cancellationToken: M4AExportCancellationToken = M4AExportCancellationToken(),
        encoder: any M4AAudioEncoding = AVFoundationM4AAudioEncoder(),
        progress: M4AExportProgressHandler? = nil
    ) -> M4AExportCompletionResult {
        let normalizedDestination = normalizedM4AURL(destination)
        let pcmTempURL = temporaryURL(for: normalizedDestination, purpose: "pcm", fileExtension: "wav")
        let encodedTempURL = temporaryURL(for: normalizedDestination, purpose: "encoded", fileExtension: "m4a")
        try? fileManager.removeItem(at: pcmTempURL)
        try? fileManager.removeItem(at: encodedTempURL)
        defer {
            try? fileManager.removeItem(at: pcmTempURL)
            try? fileManager.removeItem(at: encodedTempURL)
        }

        let wavCompletion = WAVExportCoordinator.export(
            plan: plan.renderPlan,
            to: pcmTempURL,
            fileManager: fileManager,
            cancellationToken: cancellationToken,
            progress: { wavProgress in
                if let mapped = mappedRenderProgress(wavProgress) {
                    progress?(mapped)
                }
            }
        )
        let renderResult: PlaybackSongOfflineStreamingRenderResult
        switch wavCompletion {
        case let .exported(_, result):
            renderResult = result
        case .cancelled:
            return .cancelled
        case let .failed(.renderFailed(message)), let .failed(.fileWriteFailed(message)):
            return .failed(.renderFailed(message))
        }
        guard !cancellationToken.isCancellationRequested else {
            return .cancelled
        }

        let encodingResult: M4AAudioEncodingResult
        do {
            encodingResult = try encoder.encodeFloat32WAV(
                at: pcmTempURL,
                to: encodedTempURL,
                configuration: plan.encoderConfiguration,
                cancellationCheck: {
                    if cancellationToken.isCancellationRequested {
                        throw M4AExportCancellationError.cancelled
                    }
                },
                progress: { encoderProgress in
                    progress?(mappedEncoderProgress(encoderProgress, renderPlan: plan.renderPlan))
                }
            )
        } catch {
            if cancellationToken.isCancellationRequested {
                return .cancelled
            }
            return .failed(.encodingFailed(errorMessage(from: error)))
        }
        guard !cancellationToken.isCancellationRequested else {
            return .cancelled
        }

        progress?(M4AExportProgress(
            stage: .writingFile,
            completedFrames: plan.renderPlan.totalFrameCount,
            totalFrames: plan.renderPlan.totalFrameCount,
            completedWindows: plan.renderPlan.renderWindowCount,
            totalWindows: plan.renderPlan.renderWindowCount,
            fractionCompleted: 0.99
        ))
        guard !cancellationToken.isCancellationRequested else {
            return .cancelled
        }
        do {
            try replaceItem(at: normalizedDestination, withItemAt: encodedTempURL, fileManager: fileManager)
        } catch {
            return .failed(.fileWriteFailed(errorMessage(from: error)))
        }
        progress?(M4AExportProgress(
            stage: .completed,
            completedFrames: plan.renderPlan.totalFrameCount,
            totalFrames: plan.renderPlan.totalFrameCount,
            completedWindows: plan.renderPlan.renderWindowCount,
            totalWindows: plan.renderPlan.renderWindowCount,
            fractionCompleted: 1
        ))
        return .exported(
            destination: normalizedDestination,
            renderResult: renderResult,
            encodingResult: encodingResult
        )
    }

    static func defaultFilename(displayName: String?) -> String {
        let wavFilename = WAVExportCoordinator.defaultFilename(displayName: displayName)
        let base = URL(fileURLWithPath: wavFilename).deletingPathExtension().lastPathComponent
        guard !base.lowercased().hasSuffix(".m4a") else {
            return base
        }
        return "\(base).m4a"
    }

    static func normalizedM4AURL(
        _ url: URL,
        fileExtension: String = M4AExportDestinationRequest.fileExtension
    ) -> URL {
        guard url.pathExtension.lowercased() != fileExtension.lowercased() else {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    private static func mappedRenderProgress(_ progress: WAVExportProgress) -> M4AExportProgress? {
        let stage: M4AExportProgressStage
        let completedFrames: Int
        switch progress.stage {
        case .preparingRender:
            stage = .preparingRender
            completedFrames = progress.completedFrames
        case .rendering:
            stage = .rendering
            completedFrames = progress.completedFrames
        case .applyingHeadroom:
            stage = .applyingHeadroom
            completedFrames = progress.completedFrames
        case .writingFile:
            stage = .encoding
            completedFrames = 0
        case .completed:
            return nil
        }
        return M4AExportProgress(
            stage: stage,
            completedFrames: completedFrames,
            totalFrames: progress.totalFrames,
            completedWindows: progress.completedWindows,
            totalWindows: progress.totalWindows,
            fractionCompleted: min(0.95, progress.fractionCompleted)
        )
    }

    private static func mappedEncoderProgress(
        _ progress: M4AAudioEncoderProgress,
        renderPlan: WAVExportPlan
    ) -> M4AExportProgress {
        let fraction = progress.totalFrames > 0
            ? min(1, max(0, Double(progress.completedFrames) / Double(progress.totalFrames)))
            : 0
        return M4AExportProgress(
            stage: .encoding,
            completedFrames: progress.completedFrames,
            totalFrames: progress.totalFrames,
            completedWindows: renderPlan.renderWindowCount,
            totalWindows: renderPlan.renderWindowCount,
            fractionCompleted: 0.95 + (0.04 * fraction)
        )
    }

    private static func temporaryURL(for destination: URL, purpose: String, fileExtension: String) -> URL {
        let name = ".\(destination.lastPathComponent).vtx-export-\(purpose)-\(UUID().uuidString).\(fileExtension)"
        return destination.deletingLastPathComponent().appendingPathComponent(name)
    }

    private static func replaceItem(at destination: URL, withItemAt tempURL: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: destination)
        }
    }

    private static func errorMessage(from error: any Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        let message = (error as NSError).localizedDescription
        return message.isEmpty ? String(describing: error) : message
    }
}

private enum M4AExportCancellationError: Error {
    case cancelled
}

@MainActor
final class NSSavePanelM4AExportDestinationProvider: M4AExportDestinationProviding {
    func chooseM4AExportDestination(request: M4AExportDestinationRequest) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Choose a destination for the M4A export"
        panel.nameFieldStringValue = request.suggestedFilename
        if let contentType = UTType(filenameExtension: request.allowedFileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return M4AExportCoordinator.normalizedM4AURL(url, fileExtension: request.allowedFileExtension)
    }
}
