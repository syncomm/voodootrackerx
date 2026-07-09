import AppKit
import Foundation
import UniformTypeIdentifiers

enum WAVExportDocumentKind: Equatable {
    case none
    case editable
    case loadedReadOnly
}

struct WAVExportDocumentContext: Equatable {
    let kind: WAVExportDocumentKind
    let editableDocument: BlankTrackerDocument?
    let loadedPlaybackSong: PlaybackSong?
    let isPlaybackActive: Bool
    let displayName: String?
    let hasValidDisplayState: Bool

    static func editable(
        document: BlankTrackerDocument?,
        displayName: String?,
        isPlaybackActive: Bool,
        hasValidDisplayState: Bool = true
    ) -> WAVExportDocumentContext {
        WAVExportDocumentContext(
            kind: .editable,
            editableDocument: document,
            loadedPlaybackSong: nil,
            isPlaybackActive: isPlaybackActive,
            displayName: displayName,
            hasValidDisplayState: hasValidDisplayState
        )
    }

    static func loadedReadOnly(
        playbackSong: PlaybackSong?,
        displayName: String?,
        isPlaybackActive: Bool,
        hasValidDisplayState: Bool = true
    ) -> WAVExportDocumentContext {
        WAVExportDocumentContext(
            kind: .loadedReadOnly,
            editableDocument: nil,
            loadedPlaybackSong: playbackSong,
            isPlaybackActive: isPlaybackActive,
            displayName: displayName,
            hasValidDisplayState: hasValidDisplayState
        )
    }

    static func none(isPlaybackActive: Bool) -> WAVExportDocumentContext {
        WAVExportDocumentContext(
            kind: .none,
            editableDocument: nil,
            loadedPlaybackSong: nil,
            isPlaybackActive: isPlaybackActive,
            displayName: nil,
            hasValidDisplayState: false
        )
    }
}

enum WAVExportUnavailableReason: Equatable {
    case noDocument
    case playbackActive
    case noRenderableSong
    case exportPlanUnavailable(String)
}

enum WAVExportPlanError: LocalizedError, Equatable {
    case noRenderableSong
    case renderDurationTooSmall
    case renderDurationTooLarge(frames: Int, maximumFrames: Int)
    case renderDurationNotDeterministic(String)
    case wavFileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .noRenderableSong:
            return "No renderable playback model is available."
        case .renderDurationTooSmall:
            return "The current song is too short to render."
        case let .renderDurationTooLarge(frames, maximumFrames):
            return "The current song would render \(frames) frames, exceeding the product export safety limit of \(maximumFrames) frames."
        case let .renderDurationNotDeterministic(message):
            return "The current song duration could not be safely determined. \(message)"
        case let .wavFileTooLarge(message):
            return "The current song cannot be exported as a WAV file. \(message)"
        }
    }
}

enum WAVExportScope: Equatable, Sendable {
    case wholeSong
}

enum WAVExportLongRenderPolicy: Equatable, Sendable {
    case allowUserInitiatedWholeSong
}

enum WAVExportHeadroomPolicy: Equatable, Sendable {
    case auto
}

struct WAVExportConfiguration: Equatable, Sendable {
    let scope: WAVExportScope
    let sampleRate: Double
    let channelCount: Int
    let mixProfile: MixerMixProfile
    let wavFormat: MixerWAVFormat
    let longRenderPolicy: WAVExportLongRenderPolicy
    let headroomPolicy: WAVExportHeadroomPolicy
    let tailSeconds: Double
    let chunkFrameCount: Int
    let windowRows: Int
    let maximumFrameCount: Int
}

struct WAVExportDestinationRequest: Equatable {
    static let fileExtension = "wav"

    let suggestedFilename: String
    let allowedFileExtension: String

    init(suggestedFilename: String, allowedFileExtension: String = Self.fileExtension) {
        self.suggestedFilename = suggestedFilename
        self.allowedFileExtension = allowedFileExtension
    }
}

struct WAVExportPlan: @unchecked Sendable {
    let request: PlaybackSongOfflineRenderRequest
    let configuration: WAVExportConfiguration
    let suggestedFilename: String
    let wavFormat: MixerWAVFormat
    let chunkFrameCount: Int
    let wavLayout: MixerWAVLayout
    let songEndFrameCount: Int
    let tailFrameCount: Int
    let renderWindowCount: Int
    let performanceDiagnostics: WAVExportPlanPerformanceDiagnostics

    var totalFrameCount: Int {
        request.boundedFrameCount
    }
}

enum WAVExportStartResult {
    case unavailable(WAVExportUnavailableReason)
    case cancelled
    case ready(plan: WAVExportPlan, destination: URL)
}

enum WAVExportFailure: Equatable, Sendable {
    case renderFailed(String)
    case fileWriteFailed(String)

    var userFacingMessage: String {
        switch self {
        case let .renderFailed(message):
            return "Could not render WAV data. \(message)"
        case let .fileWriteFailed(message):
            return "Could not write WAV file. \(message)"
        }
    }
}

enum WAVExportCompletionResult: @unchecked Sendable {
    case exported(destination: URL, renderResult: PlaybackSongOfflineStreamingRenderResult)
    case failed(WAVExportFailure)

    var userFacingTitle: String {
        switch self {
        case .exported:
            return "Export Audio Completed"
        case .failed:
            return "Export WAV Failed"
        }
    }

    var userFacingMessage: String {
        switch self {
        case .exported:
            return "WAV file saved successfully."
        case let .failed(failure):
            return "Export WAV failed: \(failure.userFacingMessage)"
        }
    }
}

enum WAVExportProgressStage: Equatable, Sendable {
    case rendering
    case applyingHeadroom
    case writingFile
    case completed
}

struct WAVExportProgress: Equatable, Sendable {
    let stage: WAVExportProgressStage
    let completedFrames: Int
    let totalFrames: Int
    let completedWindows: Int
    let totalWindows: Int

    var fractionCompleted: Double {
        guard totalFrames > 0 else {
            return stage == .completed ? 1 : 0
        }
        return min(1, max(0, Double(completedFrames) / Double(totalFrames)))
    }
}

typealias WAVExportProgressHandler = @Sendable (WAVExportProgress) -> Void

enum WAVExportPipelineEvent: Equatable, Sendable {
    case expensiveRenderStarted
    case headroomPostProcessStarted
}

typealias WAVExportPipelineEventHandler = @Sendable (WAVExportPipelineEvent) -> Void

struct WAVExportExecutionHooks: @unchecked Sendable {
    static let none = WAVExportExecutionHooks()

    var afterRenderBlockWritten: (@Sendable () throws -> Void)?
    var afterPostProcessChunkWritten: (@Sendable () throws -> Void)?

    init(
        afterRenderBlockWritten: (@Sendable () throws -> Void)? = nil,
        afterPostProcessChunkWritten: (@Sendable () throws -> Void)? = nil
    ) {
        self.afterRenderBlockWritten = afterRenderBlockWritten
        self.afterPostProcessChunkWritten = afterPostProcessChunkWritten
    }
}

@MainActor
protocol WAVExportDestinationProviding {
    func chooseWAVExportDestination(request: WAVExportDestinationRequest) -> URL?
}

struct WAVExportCoordinator {
    static let sampleRate = 48_000.0
    static let channelCount = MixerRenderConfig.defaultChannelCount
    static let mixProfile = MixerMixProfile.vtx
    static let wavFormat = MixerWAVFormat.float32
    static let defaultChunkFrameCount = Int(sampleRate)
    static let defaultWindowRows = 64
    static let maximumFrameCount = 100_000_000
    static let runtimeTailPolicy = RuntimeCMixerSongEndTailPolicy.defaultPolicy
    static let defaultConfiguration = WAVExportConfiguration(
        scope: .wholeSong,
        sampleRate: sampleRate,
        channelCount: channelCount,
        mixProfile: mixProfile,
        wavFormat: wavFormat,
        longRenderPolicy: .allowUserInitiatedWholeSong,
        headroomPolicy: .auto,
        tailSeconds: runtimeTailPolicy.tailSeconds,
        chunkFrameCount: defaultChunkFrameCount,
        windowRows: defaultWindowRows,
        maximumFrameCount: maximumFrameCount
    )

    private let destinationProvider: any WAVExportDestinationProviding

    @MainActor
    init(destinationProvider: any WAVExportDestinationProviding) {
        self.destinationProvider = destinationProvider
    }

    static func canExport(context: WAVExportDocumentContext) -> Bool {
        unavailableReason(for: context) == nil
    }

    static func unavailableReason(for context: WAVExportDocumentContext) -> WAVExportUnavailableReason? {
        switch context.kind {
        case .none:
            return .noDocument
        case .editable, .loadedReadOnly:
            break
        }

        guard !context.isPlaybackActive else {
            return .playbackActive
        }
        guard context.hasValidDisplayState else {
            return .noRenderableSong
        }

        do {
            _ = try makePlan(context: context)
            return nil
        } catch WAVExportPlanError.noRenderableSong {
            return .noRenderableSong
        } catch {
            return .exportPlanUnavailable(errorMessage(from: error))
        }
    }

    @MainActor
    func beginExport(context: WAVExportDocumentContext) -> WAVExportStartResult {
        if let reason = Self.unavailableReason(for: context) {
            return .unavailable(reason)
        }

        let plan: WAVExportPlan
        do {
            plan = try Self.makePlan(context: context)
        } catch WAVExportPlanError.noRenderableSong {
            return .unavailable(.noRenderableSong)
        } catch {
            return .unavailable(.exportPlanUnavailable(Self.errorMessage(from: error)))
        }

        let request = WAVExportDestinationRequest(suggestedFilename: plan.suggestedFilename)
        guard let destination = destinationProvider.chooseWAVExportDestination(request: request) else {
            return .cancelled
        }

        return .ready(
            plan: plan,
            destination: Self.normalizedWAVURL(destination, fileExtension: request.allowedFileExtension)
        )
    }

    static func makePlan(context: WAVExportDocumentContext) throws -> WAVExportPlan {
        try makePlan(context: context, configuration: defaultConfiguration)
    }

    static func makePlan(
        context: WAVExportDocumentContext,
        configuration: WAVExportConfiguration
    ) throws -> WAVExportPlan {
        let totalStartTime = VTXPerformanceClock.now()
        guard !context.isPlaybackActive else {
            throw WAVExportPlanError.noRenderableSong
        }

        let songBuildStartTime = VTXPerformanceClock.now()
        let song: PlaybackSong
        switch context.kind {
        case .none:
            throw WAVExportPlanError.noRenderableSong
        case .loadedReadOnly:
            guard let loadedPlaybackSong = context.loadedPlaybackSong else {
                throw WAVExportPlanError.noRenderableSong
            }
            song = loadedPlaybackSong
        case .editable:
            guard let editableDocument = context.editableDocument else {
                throw WAVExportPlanError.noRenderableSong
            }
            song = EditablePlaybackSongBuilder.build(from: editableDocument)
        }
        let songBuildDuration = VTXPerformanceClock.seconds(since: songBuildStartTime)

        guard !song.orders.isEmpty else {
            throw WAVExportPlanError.noRenderableSong
        }
        guard configuration.scope == .wholeSong else {
            throw WAVExportPlanError.renderDurationNotDeterministic("Only whole-song WAV export is supported.")
        }
        guard configuration.wavFormat == .float32 else {
            throw WAVExportPlanError.wavFileTooLarge("Only 32-bit float WAV export is supported.")
        }

        let config = MixerRenderConfig(
            sampleRate: configuration.sampleRate,
            channelCount: configuration.channelCount,
            mixProfile: configuration.mixProfile
        )
        let traversalStartTime = VTXPerformanceClock.now()
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: 0,
            orderCount: song.orders.count
        )
        try validateWholeSongTraversal(traversalPlan)
        let traversalDuration = VTXPerformanceClock.seconds(since: traversalStartTime)
        let timingStartTime = VTXPerformanceClock.now()
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            traversalPlan: traversalPlan,
            sampleRate: config.sampleRate
        )
        let timingDuration = VTXPerformanceClock.seconds(since: timingStartTime)
        let songEndFrames = timingPlan.frameFor(row: timingPlan.rowTimings.count, tick: 0)
        let tailFrames = frameCountAllowingZero(seconds: configuration.tailSeconds, sampleRate: config.sampleRate)
        let (totalFrames, overflow) = songEndFrames.addingReportingOverflow(tailFrames)
        guard !overflow else {
            throw WAVExportPlanError.renderDurationTooLarge(
                frames: Int.max,
                maximumFrames: configuration.maximumFrameCount
            )
        }
        guard totalFrames > 0 else {
            throw WAVExportPlanError.renderDurationTooSmall
        }
        guard totalFrames <= configuration.maximumFrameCount else {
            throw WAVExportPlanError.renderDurationTooLarge(
                frames: totalFrames,
                maximumFrames: configuration.maximumFrameCount
            )
        }

        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: 0,
            orderCount: song.orders.count,
            config: config,
            frames: totalFrames,
            maximumFrameCount: totalFrames
        )
        let wavLayout: MixerWAVLayout
        let layoutValidationStartTime = VTXPerformanceClock.now()
        do {
            wavLayout = try validatePlannedWAVLayout(config: config, frameCount: totalFrames)
        } catch {
            throw WAVExportPlanError.wavFileTooLarge(errorMessage(from: error))
        }
        let layoutValidationDuration = VTXPerformanceClock.seconds(since: layoutValidationStartTime)
        let renderWindowCount = windowCount(
            syntheticRowCount: timingPlan.rowTimings.count,
            windowRows: configuration.windowRows
        )
        return WAVExportPlan(
            request: request,
            configuration: configuration,
            suggestedFilename: defaultFilename(displayName: context.displayName ?? song.title),
            wavFormat: configuration.wavFormat,
            chunkFrameCount: configuration.chunkFrameCount,
            wavLayout: wavLayout,
            songEndFrameCount: songEndFrames,
            tailFrameCount: tailFrames,
            renderWindowCount: renderWindowCount,
            performanceDiagnostics: WAVExportPlanPerformanceDiagnostics(
                totalDurationSeconds: VTXPerformanceClock.seconds(since: totalStartTime),
                songBuildDurationSeconds: songBuildDuration,
                traversalPlanningDurationSeconds: traversalDuration,
                durationTimingPlanningDurationSeconds: timingDuration,
                wavLayoutValidationDurationSeconds: layoutValidationDuration,
                totalFramesPlanned: totalFrames,
                renderWindowCount: renderWindowCount
            )
        )
    }

    static func validatePlannedWAVLayout(
        config: MixerRenderConfig,
        frameCount: Int
    ) throws -> MixerWAVLayout {
        try MixerWAVExporter.layout(config: config, frameCount: frameCount, format: wavFormat)
    }

    static func export(
        plan: WAVExportPlan,
        to destination: URL,
        fileManager: FileManager = .default,
        progress: WAVExportProgressHandler? = nil,
        pipelineEvents: WAVExportPipelineEventHandler? = nil,
        executionHooks: WAVExportExecutionHooks = .none,
        collectPerformanceDiagnostics: Bool = true
    ) -> WAVExportCompletionResult {
        let exportStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let normalizedDestination = normalizedWAVURL(destination)
        let rawTempURL = temporaryURL(for: normalizedDestination, purpose: "render")
        let finalTempURL = temporaryURL(for: normalizedDestination, purpose: "final")
        try? fileManager.removeItem(at: rawTempURL)
        try? fileManager.removeItem(at: finalTempURL)

        do {
            var progressEmitter = WAVExportProgressEmitter(progress)
            let renderer = PlaybackSongOfflineRenderer(maximumFrameCount: plan.request.maximumFrameCount)
            var renderResult: PlaybackSongOfflineStreamingRenderResult?
            var tempWAVWriteDuration = Double(0)
            var windowWriteDiagnostics = [WAVExportWindowWritePerformanceDiagnostic]()
            let renderPhaseStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            pipelineEvents?(.expensiveRenderStarted)
            let preHeadroomDiagnostics = try MixerWAVExporter.writeStreamingFloat32WAV(
                config: plan.request.config,
                frameCount: plan.totalFrameCount,
                to: rawTempURL,
                exportPolicy: .unity
            ) { writer in
                progressEmitter.emit(WAVExportProgress(
                    stage: .rendering,
                    completedFrames: 0,
                    totalFrames: plan.totalFrameCount,
                    completedWindows: 0,
                    totalWindows: plan.renderWindowCount
                ))
                renderResult = try renderer.renderWindowedStreaming(
                    plan.request,
                    windowRows: plan.configuration.windowRows,
                    collectPerformanceDiagnostics: collectPerformanceDiagnostics
                ) { completedWindow, totalWindows, window, block in
                    let writeStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
                    try writer.write(block: block)
                    if collectPerformanceDiagnostics {
                        let writeDuration = VTXPerformanceClock.seconds(since: writeStartTime)
                        tempWAVWriteDuration += writeDuration
                        windowWriteDiagnostics.append(WAVExportWindowWritePerformanceDiagnostic(
                            windowIndex: window.windowIndex,
                            tempWAVWriteDurationSeconds: writeDuration
                        ))
                    }
                    try executionHooks.afterRenderBlockWritten?()
                    progressEmitter.emit(WAVExportProgress(
                        stage: .rendering,
                        completedFrames: min(plan.totalFrameCount, max(0, window.endFrame)),
                        totalFrames: plan.totalFrameCount,
                        completedWindows: completedWindow,
                        totalWindows: totalWindows
                    ))
                }
            }
            guard let renderResult else {
                throw WAVExportPlanError.renderDurationTooSmall
            }
            let renderPhaseDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: renderPhaseStartTime)
                : 0

            let exportPolicy = exportPolicy(for: plan, preHeadroomDiagnostics: preHeadroomDiagnostics)
            let headroomStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            pipelineEvents?(.headroomPostProcessStarted)
            progressEmitter.emit(WAVExportProgress(
                stage: .applyingHeadroom,
                completedFrames: 0,
                totalFrames: plan.totalFrameCount,
                completedWindows: 0,
                totalWindows: plan.renderWindowCount
            ), force: true)
            let diagnostics = try MixerWAVExporter.writeFloat32WAVApplyingGain(
                from: rawTempURL,
                to: finalTempURL,
                exportPolicy: exportPolicy,
                chunkSampleCount: max(1, plan.chunkFrameCount * plan.request.config.channelCount)
            ) { completedBytes, totalBytes in
                try executionHooks.afterPostProcessChunkWritten?()
                progressEmitter.emit(WAVExportProgress(
                    stage: .applyingHeadroom,
                    completedFrames: frameProgress(
                        completedBytes: completedBytes,
                        totalBytes: totalBytes,
                        totalFrames: plan.totalFrameCount
                    ),
                    totalFrames: plan.totalFrameCount,
                    completedWindows: plan.renderWindowCount,
                    totalWindows: plan.renderWindowCount
                ))
            }
            let headroomDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: headroomStartTime)
                : 0

            progressEmitter.emit(WAVExportProgress(
                stage: .writingFile,
                completedFrames: plan.totalFrameCount,
                totalFrames: plan.totalFrameCount,
                completedWindows: plan.renderWindowCount,
                totalWindows: plan.renderWindowCount
            ), force: true)
            let replaceStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            try replaceItem(at: normalizedDestination, withItemAt: finalTempURL, fileManager: fileManager)
            let replaceDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: replaceStartTime)
                : 0
            try? fileManager.removeItem(at: rawTempURL)
            progressEmitter.emit(WAVExportProgress(
                stage: .completed,
                completedFrames: plan.totalFrameCount,
                totalFrames: plan.totalFrameCount,
                completedWindows: plan.renderWindowCount,
                totalWindows: plan.renderWindowCount
            ), force: true)
            let exportPerformanceDiagnostics = collectPerformanceDiagnostics
                ? WAVExportPerformanceDiagnostics(
                    totalExportDurationSeconds: VTXPerformanceClock.seconds(since: exportStartTime),
                    planPerformanceDiagnostics: plan.performanceDiagnostics,
                    renderPhaseDurationSeconds: renderPhaseDuration,
                    tempWAVWriteDurationSeconds: tempWAVWriteDuration,
                    headroomPostProcessDurationSeconds: headroomDuration,
                    finalAtomicReplaceDurationSeconds: replaceDuration,
                    totalFramesPlanned: plan.totalFrameCount,
                    totalFramesRendered: renderResult.renderedFrameCount,
                    renderWindowCount: renderResult.windowedRenderSummary?.windowCount ?? 0,
                    windowRows: plan.configuration.windowRows,
                    renderPerformanceDiagnostics: renderResult.performanceDiagnostics,
                    windowWriteDiagnostics: windowWriteDiagnostics
                )
                : nil
            return .exported(
                destination: normalizedDestination,
                renderResult: renderResult
                    .replacingExportDiagnostics(diagnostics)
                    .replacingWAVExportPerformanceDiagnostics(exportPerformanceDiagnostics)
            )
        } catch let error as WAVExportPlanError {
            try? fileManager.removeItem(at: rawTempURL)
            try? fileManager.removeItem(at: finalTempURL)
            return .failed(.renderFailed(errorMessage(from: error)))
        } catch let error as MixerWAVExportError {
            try? fileManager.removeItem(at: rawTempURL)
            try? fileManager.removeItem(at: finalTempURL)
            return .failed(.fileWriteFailed(errorMessage(from: error)))
        } catch {
            try? fileManager.removeItem(at: rawTempURL)
            try? fileManager.removeItem(at: finalTempURL)
            return .failed(.fileWriteFailed(errorMessage(from: error)))
        }
    }

    static func defaultFilename(displayName: String?) -> String {
        let rawName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sanitizedBaseName = sanitizedFilenameBase(rawName)
        guard !sanitizedBaseName.lowercased().hasSuffix(".wav") else {
            return sanitizedBaseName
        }
        return "\(sanitizedBaseName).wav"
    }

    private static func exportPolicy(
        for plan: WAVExportPlan,
        preHeadroomDiagnostics: MixerWAVExportDiagnostics
    ) -> MixerWAVExportPolicy {
        switch plan.configuration.headroomPolicy {
        case .auto:
            return MixerWAVExportPolicy.autoHeadroom(preExportPeak: preHeadroomDiagnostics.preExportPeak)
        }
    }

    static func normalizedWAVURL(
        _ url: URL,
        fileExtension: String = WAVExportDestinationRequest.fileExtension
    ) -> URL {
        guard url.pathExtension.lowercased() != fileExtension.lowercased() else {
            return url
        }
        return url.deletingPathExtension().appendingPathExtension(fileExtension)
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

    private static func temporaryURL(for destination: URL, purpose: String) -> URL {
        let directory = destination.deletingLastPathComponent()
        let temporaryName = ".\(destination.lastPathComponent).vtx-export-\(purpose)-\(UUID().uuidString).tmp"
        return directory.appendingPathComponent(temporaryName)
    }

    private static func frameProgress(completedBytes: Int, totalBytes: Int, totalFrames: Int) -> Int {
        guard completedBytes > 0,
              totalBytes > 0,
              totalFrames > 0 else {
            return 0
        }
        let fraction = min(1, max(0, Double(completedBytes) / Double(totalBytes)))
        return min(totalFrames, max(0, Int((fraction * Double(totalFrames)).rounded(.down))))
    }

    private static func validateWholeSongTraversal(_ traversalPlan: PlaybackSongTraversalPlan) throws {
        guard !traversalPlan.rows.isEmpty else {
            throw WAVExportPlanError.renderDurationTooSmall
        }
        guard traversalPlan.stopReason == .songEnd else {
            throw WAVExportPlanError.renderDurationNotDeterministic(
                "Traversal stopped with \(traversalPlan.stopReason.rawValue) before a full song end."
            )
        }
        guard !traversalPlan.guardHit else {
            throw WAVExportPlanError.renderDurationNotDeterministic("Traversal hit the song safety guard.")
        }
    }

    private static func frameCountAllowingZero(seconds: Double, sampleRate: Double) -> Int {
        guard seconds.isFinite,
              seconds > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        let frames = (seconds * sampleRate).rounded(.toNearestOrAwayFromZero)
        guard frames > 0 else {
            return 0
        }
        guard frames < Double(Int.max) else {
            return Int.max
        }
        return Int(frames)
    }

    private static func windowCount(syntheticRowCount: Int, windowRows: Int) -> Int {
        let rowCount = max(0, syntheticRowCount)
        guard rowCount > 0 else {
            return 1
        }
        return Int(ceil(Double(rowCount) / Double(max(1, windowRows))))
    }

    private static func replaceItem(
        at destination: URL,
        withItemAt tempURL: URL,
        fileManager: FileManager
    ) throws {
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
        let localizedDescription = (error as NSError).localizedDescription
        return localizedDescription.isEmpty ? String(describing: error) : localizedDescription
    }
}

private struct WAVExportProgressEmitter {
    private let handler: WAVExportProgressHandler?
    private var lastStage: WAVExportProgressStage?
    private var lastFraction = Double(-1)

    init(_ handler: WAVExportProgressHandler?) {
        self.handler = handler
    }

    mutating func emit(_ progress: WAVExportProgress, force: Bool = false) {
        guard let handler else {
            return
        }
        let fraction = progress.fractionCompleted
        let stageChanged = progress.stage != lastStage
        let completed = progress.stage == .completed || fraction >= 1
        guard force || stageChanged || completed || fraction - lastFraction >= 0.01 else {
            return
        }
        lastStage = progress.stage
        lastFraction = fraction
        handler(progress)
    }
}

@MainActor
final class NSSavePanelWAVExportDestinationProvider: WAVExportDestinationProviding {
    func chooseWAVExportDestination(request: WAVExportDestinationRequest) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Choose a destination for the WAV export"
        panel.nameFieldStringValue = request.suggestedFilename
        if let wavContentType = UTType(filenameExtension: request.allowedFileExtension) {
            panel.allowedContentTypes = [wavContentType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return WAVExportCoordinator.normalizedWAVURL(url, fileExtension: request.allowedFileExtension)
    }
}
