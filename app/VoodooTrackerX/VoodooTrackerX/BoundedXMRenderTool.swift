import Foundation

private let toolName = "vtx_render_bounded_xm"

public enum BoundedXMRenderToolCLI {
    public static func main(argv: [String]) -> Int {
        do {
            let arguments = try RenderToolArguments.parse(argv)
            let result = try RenderTool().run(arguments)
            printSummary(arguments: arguments, result: result)
            return 0
        } catch RenderToolError.helpRequested {
            print(renderToolUsage())
            return 0
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            FileHandle.standardError.write(Data("\(toolName): \(message)\n\n\(renderToolUsage())\n".utf8))
            return 1
        }
    }
}

enum RenderToolError: LocalizedError, Equatable {
    case helpRequested
    case unknownArgument(String)
    case missingValue(String)
    case duplicateArgument(String)
    case missingRequiredArgument(String)
    case invalidInteger(name: String, value: String)
    case invalidDouble(name: String, value: String)
    case mutuallyExclusive(String, String)
    case invalidInputPath(String)
    case invalidOutputPath(String)
    case invalidOrderRange(String)
    case invalidRenderLimit(String)
    case invalidWindowRows(String)
    case longRenderRequiresAllowLongRender(frames: Int, defaultLimit: Int)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)"
        case let .missingValue(argument):
            return "Missing value for \(argument)"
        case let .duplicateArgument(argument):
            return "Duplicate argument: \(argument)"
        case let .missingRequiredArgument(argument):
            return "Missing required argument: \(argument)"
        case let .invalidInteger(name, value):
            return "Invalid integer for \(name): \(value)"
        case let .invalidDouble(name, value):
            return "Invalid number for \(name): \(value)"
        case let .mutuallyExclusive(first, second):
            return "\(first) and \(second) cannot be used together"
        case let .invalidInputPath(message),
             let .invalidOutputPath(message),
             let .invalidOrderRange(message),
             let .invalidRenderLimit(message),
             let .invalidWindowRows(message):
            return message
        case let .longRenderRequiresAllowLongRender(frames, defaultLimit):
            return "Requested render cap \(frames) frames exceeds the default safety clamp \(defaultLimit) frames. Pass --allow-long-render intentionally for longer local renders."
        }
    }
}

struct RenderToolArguments: Equatable {
    let inputPath: String
    let outputPath: String
    let diagnosticsJSONPath: String?
    let order: Int
    let orderCount: Int
    let rows: Int?
    let sampleRate: Double
    let maxFrames: Int?
    let seconds: Double?
    let windowRows: Int?
    let allowLongRender: Bool
    let progress: Bool

    init(
        inputPath: String,
        outputPath: String,
        diagnosticsJSONPath: String?,
        order: Int,
        orderCount: Int,
        rows: Int?,
        sampleRate: Double,
        maxFrames: Int?,
        seconds: Double?,
        windowRows: Int? = nil,
        allowLongRender: Bool = false,
        progress: Bool = false
    ) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.diagnosticsJSONPath = diagnosticsJSONPath
        self.order = order
        self.orderCount = orderCount
        self.rows = rows
        self.sampleRate = sampleRate
        self.maxFrames = maxFrames
        self.seconds = seconds
        self.windowRows = windowRows
        self.allowLongRender = allowLongRender
        self.progress = progress
    }

    static func parse(_ argv: [String]) throws -> RenderToolArguments {
        var inputPath: String?
        var outputPath: String?
        var diagnosticsJSONPath: String?
        var order: Int?
        var orderCount = 1
        var rows: Int?
        var sampleRate = MixerRenderConfig.defaultSampleRate
        var maxFrames: Int?
        var seconds: Double?
        var windowRows: Int?
        var allowLongRender = false
        var progress = false
        var seen = Set<String>()
        var index = 0

        while index < argv.count {
            let argument = argv[index]
            if argument == "--help" || argument == "-h" {
                throw RenderToolError.helpRequested
            }
            guard argument.hasPrefix("--") else {
                throw RenderToolError.unknownArgument(argument)
            }
            if argument == "--allow-long-render" {
                if !seen.insert(argument).inserted {
                    throw RenderToolError.duplicateArgument(argument)
                }
                allowLongRender = true
                index += 1
                continue
            }
            if argument == "--progress" {
                if !seen.insert(argument).inserted {
                    throw RenderToolError.duplicateArgument(argument)
                }
                progress = true
                index += 1
                continue
            }
            guard let value = value(after: argument, in: argv, at: &index) else {
                throw RenderToolError.missingValue(argument)
            }
            if !seen.insert(argument).inserted {
                throw RenderToolError.duplicateArgument(argument)
            }
            switch argument {
            case "--input":
                inputPath = value
            case "--output":
                outputPath = value
            case "--diagnostics-json":
                diagnosticsJSONPath = value
            case "--order":
                order = try parseInt(value, name: argument)
            case "--order-count":
                orderCount = try parseInt(value, name: argument)
            case "--rows":
                rows = try parsePositiveInt(value, name: argument)
            case "--sample-rate":
                sampleRate = try parsePositiveDouble(value, name: argument)
            case "--max-frames":
                maxFrames = try parsePositiveInt(value, name: argument)
            case "--seconds":
                seconds = try parsePositiveDouble(value, name: argument)
            case "--window-rows":
                windowRows = try parseWindowRows(value, name: argument)
            default:
                throw RenderToolError.unknownArgument(argument)
            }
            index += 1
        }

        if rows != nil && seconds != nil {
            throw RenderToolError.mutuallyExclusive("--rows", "--seconds")
        }
        if maxFrames != nil && seconds != nil {
            throw RenderToolError.mutuallyExclusive("--max-frames", "--seconds")
        }
        try validateExplicitRenderLimit(
            maxFrames: maxFrames,
            seconds: seconds,
            sampleRate: sampleRate,
            allowLongRender: allowLongRender
        )

        return RenderToolArguments(
            inputPath: try required(inputPath, "--input"),
            outputPath: try required(outputPath, "--output"),
            diagnosticsJSONPath: diagnosticsJSONPath,
            order: try required(order, "--order"),
            orderCount: orderCount,
            rows: rows,
            sampleRate: sampleRate,
            maxFrames: maxFrames,
            seconds: seconds,
            windowRows: windowRows,
            allowLongRender: allowLongRender,
            progress: progress
        )
    }

    var usesDefaultRenderClamp: Bool {
        maxFrames == nil && seconds == nil
    }

    func effectiveFrameCap(sampleRate: Double) -> Int {
        if let maxFrames {
            return maxFrames
        }
        if let seconds {
            return Self.frameCount(seconds: seconds, sampleRate: sampleRate)
        }
        return PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount
    }

    private static func value(after argument: String, in argv: [String], at index: inout Int) -> String? {
        let nextIndex = index + 1
        guard nextIndex < argv.count else {
            return nil
        }
        let value = argv[nextIndex]
        guard !value.hasPrefix("--") else {
            return nil
        }
        index = nextIndex
        return value
    }

    private static func required<T>(_ value: T?, _ argument: String) throws -> T {
        guard let value else {
            throw RenderToolError.missingRequiredArgument(argument)
        }
        return value
    }

    private static func parseInt(_ value: String, name: String) throws -> Int {
        guard let parsed = Int(value) else {
            throw RenderToolError.invalidInteger(name: name, value: value)
        }
        return parsed
    }

    private static func parseDouble(_ value: String, name: String) throws -> Double {
        guard let parsed = Double(value), parsed.isFinite else {
            throw RenderToolError.invalidDouble(name: name, value: value)
        }
        return parsed
    }

    private static func parsePositiveInt(_ value: String, name: String) throws -> Int {
        let parsed = try parseInt(value, name: name)
        guard parsed > 0 else {
            throw RenderToolError.invalidInteger(name: name, value: value)
        }
        return parsed
    }

    private static func parsePositiveDouble(_ value: String, name: String) throws -> Double {
        let parsed = try parseDouble(value, name: name)
        guard parsed > 0 else {
            throw RenderToolError.invalidDouble(name: name, value: value)
        }
        return parsed
    }

    private static func parseWindowRows(_ value: String, name: String) throws -> Int {
        let parsed = try parseInt(value, name: name)
        guard parsed > 0 else {
            throw RenderToolError.invalidWindowRows("Window row count must be greater than zero; got \(value).")
        }
        return parsed
    }

    private static func validateExplicitRenderLimit(
        maxFrames: Int?,
        seconds: Double?,
        sampleRate: Double,
        allowLongRender: Bool
    ) throws {
        let frames: Int?
        if let maxFrames {
            frames = maxFrames
        } else if let seconds {
            frames = frameCount(seconds: seconds, sampleRate: sampleRate)
        } else {
            frames = nil
        }
        guard let frames else {
            return
        }
        guard frames > 0 else {
            throw RenderToolError.invalidRenderLimit("Render duration is too small to produce at least one frame.")
        }
        guard frames <= RenderTool.absoluteMaximumFrameCount else {
            throw RenderToolError.invalidRenderLimit(
                "Requested render cap \(frames) frames exceeds the helper's hard safety limit \(RenderTool.absoluteMaximumFrameCount) frames."
            )
        }
        let defaultLimit = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount
        if frames > defaultLimit, !allowLongRender {
            throw RenderToolError.longRenderRequiresAllowLongRender(frames: frames, defaultLimit: defaultLimit)
        }
    }

    private static func frameCount(seconds: Double, sampleRate: Double) -> Int {
        RenderTool.frameCount(seconds: seconds, sampleRate: sampleRate)
    }
}

struct RenderTool {
    static let absoluteMaximumFrameCount = 100_000_000

    let fileManager: FileManager
    let currentDirectory: URL
    let progressOutput: (String) -> Void

    init(
        fileManager: FileManager = .default,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        progressOutput: @escaping (String) -> Void = RenderTool.writeProgressToStandardError
    ) {
        self.fileManager = fileManager
        self.currentDirectory = currentDirectory
        self.progressOutput = progressOutput
    }

    func run(_ arguments: RenderToolArguments) throws -> PlaybackSongOfflineRenderResult {
        let start = Date()
        let inputURL = URL(fileURLWithPath: arguments.inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments.outputPath).standardizedFileURL
        let diagnosticsURL = arguments.diagnosticsJSONPath.map { URL(fileURLWithPath: $0).standardizedFileURL }

        try validateInput(inputURL)
        try validateOutput(outputURL)
        if let diagnosticsURL {
            try validateDiagnosticsOutput(diagnosticsURL)
        }

        emitProgress("loading module", arguments: arguments)
        let metadata = try ModuleMetadataLoader().load(fromPath: inputURL.path)
        emitProgress("building playback song", arguments: arguments)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: inputURL.path)
        try validateOrderRange(start: arguments.order, count: arguments.orderCount, orderTotal: song.orders.count)

        let config = MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: MixerRenderConfig.defaultChannelCount)
        let request = renderRequest(song: song, arguments: arguments, config: config)
        let renderer = PlaybackSongOfflineRenderer(maximumFrameCount: request.maximumFrameCount)
        emitProgress("render started", arguments: arguments)
        emitProgress(renderCapProgressLine(for: request), arguments: arguments)
        let result = try renderAndExportWAV(
            request,
            to: outputURL,
            renderer: renderer,
            arguments: arguments,
            startedAt: start
        )
        if let diagnosticsURL {
            emitProgress("writing diagnostics JSON", arguments: arguments)
            try PlaybackSongDiagnosticsJSONExporter.write(result, to: diagnosticsURL)
        }
        emitProgress("export succeeded", arguments: arguments)
        return result
    }

    func renderAndExportWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to outputURL: URL,
        renderer: PlaybackSongOfflineRenderer,
        arguments: RenderToolArguments,
        startedAt: Date
    ) throws -> PlaybackSongOfflineRenderResult {
        if let windowRows = arguments.windowRows {
            let result = try renderWindowedAndExportWAV(
                request,
                to: outputURL,
                renderer: renderer,
                windowRows: windowRows,
                arguments: arguments
            )
            emitProgress(renderCompletedProgressLine(for: result, startedAt: startedAt), arguments: arguments)
            return result
        }
        if arguments.progress {
            let result = renderWithProgress(request, renderer: renderer, arguments: arguments)
            emitProgress(renderCompletedProgressLine(for: result, startedAt: startedAt), arguments: arguments)
            emitProgress("writing WAV", arguments: arguments)
            try MixerWAVExporter.writePCM16WAV(from: result.block, to: outputURL)
            emitProgress("writing WAV completed", arguments: arguments)
            return result
        }
        return try renderer.exportWAV(request, to: outputURL)
    }

    func renderWindowedAndExportWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to outputURL: URL,
        renderer: PlaybackSongOfflineRenderer,
        windowRows: Int,
        arguments: RenderToolArguments
    ) throws -> PlaybackSongOfflineRenderResult {
        let result = renderer.renderWindowed(request, windowRows: windowRows) { completedWindow, totalWindows, window in
            emitWindowRenderProgress(
                completedWindow: completedWindow,
                totalWindows: totalWindows,
                window: window,
                totalFrames: request.boundedFrameCount,
                arguments: arguments
            )
        }
        emitProgress("writing WAV", arguments: arguments)
        try MixerWAVExporter.writePCM16WAV(from: result.block, to: outputURL)
        emitProgress("writing WAV completed", arguments: arguments)
        return result
    }

    func renderWithProgress(
        _ request: PlaybackSongOfflineRenderRequest,
        renderer: PlaybackSongOfflineRenderer,
        arguments: RenderToolArguments
    ) -> PlaybackSongOfflineRenderResult {
        let session = renderer.prepare(request)
        let totalFrames = session.request.boundedFrameCount
        let chunkSize = progressChunkSize(totalFrames: totalFrames)
        var completedFrames = 0
        var interleavedPCM = [Float]()
        interleavedPCM.reserveCapacity(totalFrames * session.config.channelCount)
        emitRenderProgress(completedFrames: completedFrames, totalFrames: totalFrames, arguments: arguments)
        while completedFrames < totalFrames {
            let requestedFrames = min(chunkSize, totalFrames - completedFrames)
            let chunk = session.render(frames: requestedFrames)
            guard chunk.frameCount > 0 else {
                break
            }
            completedFrames += chunk.frameCount
            interleavedPCM.append(contentsOf: chunk.interleavedPCM)
            emitRenderProgress(completedFrames: completedFrames, totalFrames: totalFrames, arguments: arguments)
        }
        let block = MixerRenderBlock(
            config: session.config,
            frameCount: completedFrames,
            interleavedPCM: interleavedPCM
        )
        return PlaybackSongOfflineRenderResult(
            request: session.request.replacingFrameCount(completedFrames),
            plan: session.plan,
            block: block,
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons
        )
    }

    func progressChunkSize(totalFrames: Int) -> Int {
        guard totalFrames > 0 else {
            return 1
        }
        return max(1, Int((Double(totalFrames) / 10.0).rounded(.up)))
    }

    func emitProgress(_ message: String, arguments: RenderToolArguments) {
        guard arguments.progress else {
            return
        }
        progressOutput("[\(toolName)] \(message)")
    }

    func emitRenderProgress(completedFrames: Int, totalFrames: Int, arguments: RenderToolArguments) {
        let percent = totalFrames > 0
            ? Int((Double(completedFrames) / Double(totalFrames) * 100.0).rounded(.down))
            : 100
        emitProgress(
            "rendering bounded candidate: \(min(100, max(0, percent)))% (\(completedFrames) / \(totalFrames) frames)",
            arguments: arguments
        )
    }

    func emitWindowRenderProgress(
        completedWindow: Int,
        totalWindows: Int,
        window: PlaybackSongWindowedRenderWindowDiagnostic,
        totalFrames: Int,
        arguments: RenderToolArguments
    ) {
        let completedFrames = min(totalFrames, max(0, window.endFrame))
        let percent = totalFrames > 0
            ? Int((Double(completedFrames) / Double(totalFrames) * 100.0).rounded(.down))
            : 100
        emitProgress(
            "rendering window \(completedWindow) / \(totalWindows): \(min(100, max(0, percent)))% (\(completedFrames) / \(totalFrames) frames), rows \(window.startRow)..<\(window.endRowExclusive), carried \(window.carriedVoiceCount), scheduled \(window.scheduledEventCount), accepted \(window.acceptedScheduledEventCount), rejected \(window.rejectedScheduledEventCount)",
            arguments: arguments
        )
    }

    func renderCapProgressLine(for request: PlaybackSongOfflineRenderRequest) -> String {
        let duration = request.config.sampleRate > 0
            ? Double(request.maximumFrameCount) / request.config.sampleRate
            : 0
        return String(format: "effective frame cap: %d frames (%.3f seconds)", request.maximumFrameCount, duration)
    }

    func renderCompletedProgressLine(for result: PlaybackSongOfflineRenderResult, startedAt: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(startedAt))
        return String(format: "render completed: rendered %d frames in %.3f seconds", result.renderedFrameCount, elapsed)
    }

    static func writeProgressToStandardError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    func renderRequest(
        song: PlaybackSong,
        arguments: RenderToolArguments,
        config: MixerRenderConfig
    ) -> PlaybackSongOfflineRenderRequest {
        let maximumFrameCount = max(0, arguments.effectiveFrameCap(sampleRate: config.sampleRate))
        if let rows = arguments.rows {
            return PlaybackSongOfflineRenderRequest(
                song: song,
                startOrderIndex: arguments.order,
                orderCount: arguments.orderCount,
                config: config,
                rows: rows,
                maximumFrameCount: maximumFrameCount
            )
        }
        let frames: Int
        if let seconds = arguments.seconds {
            frames = Self.frameCount(seconds: seconds, sampleRate: config.sampleRate)
        } else {
            frames = maximumFrameCount
        }
        return PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: arguments.order,
            orderCount: arguments.orderCount,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        )
    }

    func validateInput(_ inputURL: URL) throws {
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw RenderToolError.invalidInputPath("Input module does not exist: \(inputURL.path)")
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw RenderToolError.invalidInputPath("Input path is not a file: \(inputURL.path)")
        }
    }

    func validateOutput(_ outputURL: URL) throws {
        guard outputURL.pathExtension.lowercased() == "wav" else {
            throw RenderToolError.invalidOutputPath("Output path must end in .wav: \(outputURL.path)")
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                throw RenderToolError.invalidOutputPath("Output path is a directory: \(outputURL.path)")
            }
        }
        let parent = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RenderToolError.invalidOutputPath("Output directory does not exist: \(parent.path)")
        }
        if let repoRoot = findRepoRoot(), outputURL.isInside(repoRoot), !isAllowedRepoOutput(outputURL, repoRoot: repoRoot) {
            throw RenderToolError.invalidOutputPath(
                "Refusing to write candidate WAV inside a tracked repo path: \(outputURL.path). Use /tmp or an ignored local audio comparison output directory."
            )
        }
    }

    func validateDiagnosticsOutput(_ outputURL: URL) throws {
        guard outputURL.pathExtension.lowercased() == "json" else {
            throw RenderToolError.invalidOutputPath("Diagnostics JSON path must end in .json: \(outputURL.path)")
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                throw RenderToolError.invalidOutputPath("Diagnostics JSON path is a directory: \(outputURL.path)")
            }
        }
        let parent = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RenderToolError.invalidOutputPath("Diagnostics JSON output directory does not exist: \(parent.path)")
        }
        if let repoRoot = findRepoRoot(), outputURL.isInside(repoRoot), !isAllowedRepoOutput(outputURL, repoRoot: repoRoot) {
            throw RenderToolError.invalidOutputPath(
                "Refusing to write diagnostics JSON inside a tracked repo path: \(outputURL.path). Use /tmp or an ignored local audio comparison output directory."
            )
        }
    }

    func validateOrderRange(start: Int, count: Int, orderTotal: Int) throws {
        guard start >= 0 else {
            throw RenderToolError.invalidOrderRange("Order must be non-negative; got \(start).")
        }
        guard count > 0 else {
            throw RenderToolError.invalidOrderRange("Order count must be greater than zero; got \(count).")
        }
        guard start < orderTotal else {
            throw RenderToolError.invalidOrderRange("Order \(start) is outside the playable order range 0...\(max(0, orderTotal - 1)).")
        }
        guard start <= Int.max - count else {
            throw RenderToolError.invalidOrderRange("Order range starting at \(start) with count \(count) exceeds integer bounds.")
        }
        let end = start + count
        guard end <= orderTotal else {
            throw RenderToolError.invalidOrderRange("Order range \(start)..<\(end) exceeds playable order count \(orderTotal).")
        }
    }

    private func findRepoRoot() -> URL? {
        var candidate = currentDirectory.standardizedFileURL
        while true {
            let gitPath = candidate.appendingPathComponent(".git").path
            let agentsPath = candidate.appendingPathComponent("AGENTS.md").path
            if fileManager.fileExists(atPath: gitPath), fileManager.fileExists(atPath: agentsPath) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private func isAllowedRepoOutput(_ outputURL: URL, repoRoot: URL) -> Bool {
        guard let relativePath = outputURL.relativePath(from: repoRoot) else {
            return true
        }
        guard let firstPart = relativePath.split(separator: "/").first else {
            return false
        }
        return [
            "local-audio-compare",
            "audio-compare-output",
            "vtx-audio-compare",
            "vtx-local-reference-comparison",
        ].contains { firstPart.hasPrefix($0) }
    }

    static func frameCount(seconds: Double, sampleRate: Double) -> Int {
        guard seconds.isFinite, seconds > 0, sampleRate.isFinite, sampleRate > 0 else {
            return 0
        }
        let frameCount = (seconds * sampleRate).rounded(.down)
        guard frameCount.isFinite, frameCount > 0 else {
            return 0
        }
        guard frameCount < Double(Int.max) else {
            return Int.max
        }
        return Int(frameCount)
    }
}

enum PlaybackSongDiagnosticsJSONExporter {
    static func write(_ result: PlaybackSongOfflineRenderResult, to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: jsonObject(from: result), options: [.prettyPrinted, .sortedKeys])
        data.append(UInt8(0x0A))
        try data.write(to: url, options: [])
    }

    static func jsonObject(from result: PlaybackSongOfflineRenderResult) -> [String: Any] {
        let diagnostics = result.diagnostics
        return [
            "schema_version": 1,
            "tool": "vtx_render_bounded_xm",
            "local_only": true,
            "notes": [
                "Approximate bounded adapter diagnostics only; not proof of reference correctness.",
                "Generated diagnostics are local artifacts and must not be committed.",
                "Runtime playback remains AVAudioPlayerNode / AVAudioUnitVarispeed; the C mixer is offline-only.",
                "C-backed offline sample stepping uses simple deterministic linear interpolation.",
                "Envelope sustain, loop, key-off, and fadeout are first-pass bounded offline approximations.",
                "Minimal nonzero 9xx sample offset is applied only in bounded offline adapter renders; 900 is a diagnosed no-op.",
                "Minimal ECx note cut and EDx note delay are applied only in bounded offline adapter renders.",
                "XM instrument sample-map/keymap selection is applied only in bounded offline adapter renders.",
                "Minimal volume/panning state updates are applied for bounded offline empty-note volume-column state commands and Cxx/8xx/Axy effect-column commands where diagnosed as applied.",
                "Hxy global volume slide remains diagnostic/deferred in bounded offline renders.",
                "Bxx position jump, Dxx pattern break, and EEx pattern delay are diagnostic/deferred only in bounded offline renders.",
                "Windowed renders are developer/offline helper renders only; practical active voice state is carried across fresh C mixer windows where supported.",
            ],
            "render": [
                "requested_start_order_index": diagnostics.requestedStartOrderIndex,
                "requested_order_count": diagnostics.requestedOrderCount,
                "sample_rate": diagnostics.sampleRate,
                "channel_count": result.block.config.channelCount,
                "sample_interpolation": "linear",
                "requested_frame_count": result.requestedFrameCount,
                "rendered_frame_count": result.renderedFrameCount,
                "maximum_frame_count": result.maximumFrameCount,
                "maximum_duration_seconds": seconds(forFrame: result.maximumFrameCount, sampleRate: result.block.config.sampleRate) ?? 0,
                "was_frame_count_bounded": result.wasFrameCountBounded,
                "initial_speed": diagnostics.initialSpeed,
                "initial_bpm": diagnostics.initialBPM,
                "uses_linear_frequency_table": diagnostics.usesLinearFrequencyTable,
                "synthetic_row_count": diagnostics.syntheticRowCount,
                "emitted_event_count": diagnostics.emittedEventCount,
                "ignored_cell_count": diagnostics.ignoredCellCount,
                "empty_or_skipped_row_count": diagnostics.emptyOrSkippedRowCount,
                "sample_offset_effect_count": diagnostics.sampleOffsetEffectCount,
                "note_cut_effect_count": diagnostics.noteCutEffectCount,
                "note_delay_effect_count": diagnostics.noteDelayEffectCount,
                "volume_panning_state_update_count": diagnostics.voiceStateUpdates.count,
                "active_voice_state_update_count": diagnostics.voiceStateUpdates.filter(\.activeVoiceUpdated).count,
                "traversal_hazard_count": diagnostics.traversalHazardSummary.totalTraversalHazards,
                "windowed_render_enabled": result.windowedRenderSummary != nil,
                "window_rows": nullableJSONValue(result.windowedRenderSummary?.windowRows),
                "window_count": result.windowedRenderSummary?.windowCount ?? 0,
            ],
            "windowed_render": windowedRenderJSON(from: result),
            "event_coverage": eventCoverageJSON(from: result),
            "traversal_hazard_summary": traversalHazardSummaryJSON(diagnostics.traversalHazardSummary),
            "pattern_traversal_timing_effects": diagnostics.effectCommandDiagnostics.map(effectCommandDiagnosticJSON),
            "orders": diagnostics.adaptedOrders.map(orderJSON),
            "row_mappings": diagnostics.rowMappings.map(rowMappingJSON),
            "row_timing": diagnostics.rowTiming.map(rowTimingJSON),
            "timing_changes": diagnostics.timingChanges.map(timingChangeJSON),
            "row_diagnostics": diagnostics.rowDiagnostics.map(rowDiagnosticJSON),
            "volume_column_mappings": diagnostics.volumeColumnMappings.map(volumeColumnMappingJSON),
            "volume_panning_state_update_summary": voiceStateUpdateSummaryJSON(diagnostics.voiceStateUpdates),
            "volume_panning_state_updates": diagnostics.voiceStateUpdates.map(voiceStateUpdateJSON),
            "sample_offset_effects": diagnostics.sampleOffsetEffects.map(sampleOffsetDiagnosticJSON),
            "note_cut_effects": diagnostics.noteCutEffects.map { noteCutDiagnosticJSON($0, from: result) },
            "note_delay_effects": diagnostics.noteDelayEffects.map(noteDelayDiagnosticJSON),
            "key_off_events": diagnostics.keyOffEvents.map(keyOffEventJSON),
            "events": eventJSON(from: result),
            "ignored_cells": diagnostics.ignoredCells.map(ignoredCellJSON),
            "deferred_fields": diagnostics.deferredCellFields.map(deferredFieldJSON),
        ]
    }

    private static func windowedRenderJSON(from result: PlaybackSongOfflineRenderResult) -> [String: Any] {
        guard let summary = result.windowedRenderSummary else {
            return [
                "enabled": false,
                "window_rows": NSNull(),
                "window_count": 0,
                "total_rendered_frames": result.renderedFrameCount,
                "total_scheduled_events": result.scheduledVoiceAttempts.count,
                "total_accepted_scheduled_events": result.scheduledVoiceAttempts.filter { $0.voiceIndex != nil }.count,
                "total_scheduled_capacity_rejects": 0,
                "total_carried_voice_count": 0,
                "total_released_voice_carryover_count": 0,
                "total_boundary_continuation_count": 0,
                "total_dropped_at_window_boundaries": 0,
                "may_contain_boundary_cuts": false,
                "per_window": [],
                "first_windows_with_rejects": [],
                "known_unsupported_carryover_reasons": [],
                "known_state_carryover_limitations": [],
            ]
        }
        return [
            "enabled": true,
            "window_rows": summary.windowRows,
            "window_count": summary.windowCount,
            "total_rendered_frames": summary.totalRenderedFrames,
            "total_carried_voice_count": summary.totalCarriedVoices,
            "total_released_voice_carryover_count": summary.totalReleasedVoiceCarryovers,
            "total_boundary_continuation_count": summary.totalBoundaryContinuations,
            "total_dropped_at_window_boundaries": summary.totalDroppedAtWindowBoundaries,
            "may_contain_boundary_cuts": summary.mayContainBoundaryCuts,
            "total_scheduled_events": summary.totalScheduledEvents,
            "total_accepted_scheduled_events": summary.totalAcceptedScheduledEvents,
            "total_rejected_scheduled_events": summary.totalRejectedScheduledEvents,
            "total_scheduled_capacity_rejects": summary.totalScheduledCapacityRejects,
            "total_invalid_scheduled_voice_rejects": summary.totalInvalidScheduledVoiceRejects,
            "per_window": summary.windows.map(windowDiagnosticJSON),
            "first_windows_with_rejects": summary.firstWindowsWithRejects.map(windowDiagnosticJSON),
            "known_unsupported_carryover_reasons": summary.knownUnsupportedCarryoverReasons,
            "known_state_carryover_limitations": summary.knownStateCarryoverLimitations,
        ]
    }

    private static func windowDiagnosticJSON(_ diagnostic: PlaybackSongWindowedRenderWindowDiagnostic) -> [String: Any] {
        [
            "window_index": diagnostic.windowIndex,
            "start_row": diagnostic.startRow,
            "end_row_exclusive": diagnostic.endRowExclusive,
            "start_frame": diagnostic.startFrame,
            "end_frame": diagnostic.endFrame,
            "rendered_frames": diagnostic.renderedFrames,
            "carried_voice_count": diagnostic.carriedVoiceCount,
            "released_voice_carryover_count": diagnostic.releasedVoiceCarryoverCount,
            "boundary_continuation_count": diagnostic.boundaryContinuationCount,
            "dropped_at_window_boundary_count": diagnostic.droppedAtWindowBoundaryCount,
            "may_contain_boundary_cuts": diagnostic.mayContainBoundaryCuts,
            "unsupported_carryover_reasons": diagnostic.unsupportedCarryoverReasons,
            "scheduled_event_count": diagnostic.scheduledEventCount,
            "accepted_scheduled_event_count": diagnostic.acceptedScheduledEventCount,
            "rejected_scheduled_event_count": diagnostic.rejectedScheduledEventCount,
            "scheduled_capacity_rejected_count": diagnostic.scheduledCapacityRejectedCount,
            "invalid_scheduled_voice_rejected_count": diagnostic.invalidScheduledVoiceRejectedCount,
        ]
    }

    private static func eventJSON(from result: PlaybackSongOfflineRenderResult) -> [[String: Any]] {
        result.diagnostics.eventMappings.map { mapping in
            eventJSON(for: mapping, from: result)
        }
    }

    private static func eventCoverageJSON(from result: PlaybackSongOfflineRenderResult) -> [String: Any] {
        let coverage = result.diagnostics.eventCoverage
        let rejectedVoiceCount = scheduledVoiceRejectedCount(from: result)
        let acceptedVoiceCount = result.scheduledVoiceAttempts.filter { $0.voiceIndex != nil }.count
        let scheduledCapacityRejectedCount = scheduledVoiceRejectionCount(
            from: result,
            reason: .scheduledVoiceCapacity
        )
        let invalidScheduledVoiceRejectedCount = scheduledVoiceRejectionCount(
            from: result,
            reason: .invalidScheduledVoice
        )
        return [
            "total_cells_visited": coverage.totalCellsVisited,
            "empty_cells": coverage.emptyCells,
            "normal_note_cells": coverage.normalNoteCells,
            "note_off_cells": coverage.noteOffCells,
            "invalid_note_cells": coverage.invalidNoteCells,
            "instrument_only_cells": coverage.instrumentOnlyCells,
            "note_with_instrument_cells": coverage.noteWithInstrumentCells,
            "note_with_missing_or_zero_instrument_cells": coverage.noteWithMissingOrZeroInstrumentCells,
            "scheduled_note_events": coverage.scheduledNoteEvents,
            "skipped_note_events": coverage.skippedNoteEvents,
            "skipped_note_off_events_no_active_voice": coverage.skippedNoteOffEventsNoActiveVoice,
            "ignored_or_deferred_cells": coverage.ignoredOrDeferredCells,
            "sample_map_selection_events": coverage.sampleMapSelectionEvents,
            "first_playable_sample_fallback_events": coverage.firstPlayableSampleFallbackEvents,
            "fallback_after_invalid_sample_map_events": coverage.fallbackAfterInvalidSampleMapEvents,
            "skipped_no_valid_sample_events": coverage.skippedNoValidSampleEvents,
            "sample_map_keymap_deferred_events": coverage.sampleMapKeymapDeferredEvents,
            "sample_map_keymap_missing_or_deferred_events": coverage.sampleMapKeymapDeferredEvents,
            "event_outside_bounded_row_range_count": coverage.eventOutsideBoundedRowRangeCount,
            "event_capacity_limit_count": coverage.eventCapacityLimitCount,
            "c_mixer_voice_capacity_limit_count": coverage.cMixerVoiceCapacityLimitCount,
            "skip_reason_counts": coverage.skipReasonCounts.map(skipReasonCountJSON),
            "capacity": [
                "c_mixer_voice_capacity": CSoftwareMixer.maximumScheduledVoiceCount,
                "c_mixer_scheduled_voice_capacity": CSoftwareMixer.maximumScheduledVoiceCount,
                "c_mixer_active_voice_capacity": CSoftwareMixer.maximumActiveVoiceCount,
                "c_mixer_voice_state_event_capacity": CSoftwareMixer.maximumVoiceStateEventCount,
                "scheduled_voice_capacity": CSoftwareMixer.maximumScheduledVoiceCount,
                "active_voice_capacity": CSoftwareMixer.maximumActiveVoiceCount,
                "scheduled_voice_attempt_count": result.scheduledVoiceAttempts.count,
                "scheduled_voice_accepted_count": acceptedVoiceCount,
                "scheduled_voice_rejected_count": rejectedVoiceCount,
                "scheduled_voice_capacity_rejected_count": scheduledCapacityRejectedCount,
                "active_voice_capacity_rejected_count": 0,
                "invalid_scheduled_voice_rejected_count": invalidScheduledVoiceRejectedCount,
                "potentially_unscheduled_event_count": rejectedVoiceCount,
                "event_capacity_limit_count": coverage.eventCapacityLimitCount,
                "c_mixer_voice_capacity_limit_count": coverage.cMixerVoiceCapacityLimitCount,
                "rejected_event_coordinates": rejectedEventCoordinatesJSON(from: result),
            ],
            "first_skipped_note_coordinates": firstSkippedNoteCoordinatesJSON(from: result.diagnostics.ignoredCells),
        ]
    }

    private static func traversalHazardSummaryJSON(
        _ summary: PlaybackSongSyntheticTraversalHazardSummary
    ) -> [String: Any] {
        [
            "total_bxx_position_jump": summary.totalBxxPositionJump,
            "total_dxx_pattern_break": summary.totalDxxPatternBreak,
            "total_eex_pattern_delay": summary.totalEExPatternDelay,
            "total_fxx_speed_bpm": summary.totalFxxSpeedBPM,
            "total_ecx_note_cut": summary.totalECxNoteCut,
            "total_edx_note_delay": summary.totalEDxNoteDelay,
            "total_other_e_commands": summary.totalOtherECommands,
            "total_traversal_hazards": summary.totalTraversalHazards,
            "likely_ignores_structure_changing_behavior": summary.likelyIgnoresStructureChangingBehavior,
            "first_traversal_hazard_coordinates": summary.firstTraversalHazards.map(effectCommandDiagnosticJSON),
            "e_command_subtype_counts": summary.eCommandSubtypeCounts.map(eCommandSubtypeCountJSON),
        ]
    }

    private static func effectCommandDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticEffectCommandDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "effect_label": diagnostic.decodedLabel,
            "decoded_label": diagnostic.decodedLabel,
            "status": effectCommandStatusName(diagnostic.status),
            "current_status": effectCommandStatusName(diagnostic.status),
            "is_traversal_hazard": diagnostic.isTraversalHazard,
        ]
    }

    private static func eCommandSubtypeCountJSON(
        _ count: PlaybackSongSyntheticECommandSubtypeCount
    ) -> [String: Any] {
        [
            "label": count.label,
            "count": count.count,
        ]
    }

    private static func scheduledVoiceRejectedCount(from result: PlaybackSongOfflineRenderResult) -> Int {
        result.scheduledVoiceAttempts.compactMap(\.rejectionReason).count
    }

    private static func scheduledVoiceRejectionCount(
        from result: PlaybackSongOfflineRenderResult,
        reason: CSoftwareMixerScheduledVoiceRejectionReason
    ) -> Int {
        result.scheduledVoiceAttempts.filter { $0.rejectionReason == reason }.count
    }

    private static func rejectedEventCoordinatesJSON(from result: PlaybackSongOfflineRenderResult) -> [[String: Any]] {
        let mappingsByEventIndex = Dictionary(uniqueKeysWithValues: result.diagnostics.eventMappings.map { ($0.eventIndex, $0) })
        return result.scheduledVoiceAttempts.compactMap { attempt -> [String: Any]? in
            guard let rejectionReason = attempt.rejectionReason else {
                return nil
            }
            var object: [String: Any] = [
                "event_index": attempt.eventIndex,
                "reason": rejectionReason.rawValue,
            ]
            if let windowIndex = attempt.windowIndex {
                object["window_index"] = windowIndex
            }
            if let mapping = mappingsByEventIndex[attempt.eventIndex] {
                object["source"] = positionJSON(mapping.source)
                object["channel_index"] = mapping.channelIndex
                object["note"] = Int(mapping.note)
                object["instrument_index"] = mapping.instrumentIndex
                object["sample_index"] = mapping.sampleIndex
                object["sample_selection_method"] = mapping.sampleSelectionMethod.rawValue
                if result.plan.pattern.events.indices.contains(attempt.eventIndex) {
                    object["scheduled_start_frame"] = result.plan.pattern.events[attempt.eventIndex].scheduledStartFrame ?? 0
                }
            }
            return object
        }
    }

    private static func skipReasonCountJSON(_ count: PlaybackSongSyntheticSkipReasonCount) -> [String: Any] {
        [
            "reason": count.reason.rawValue,
            "count": count.count,
        ]
    }

    private static func firstSkippedNoteCoordinatesJSON(from ignoredCells: [PlaybackSongSyntheticIgnoredCell]) -> [[String: Any]] {
        ignoredCells
            .filter { (1...96).contains($0.note) }
            .prefix(10)
            .map { cell in
                [
                    "source": positionJSON(cell.source),
                    "channel_index": cell.channelIndex,
                    "note": Int(cell.note),
                    "instrument_index": cell.instrumentIndex,
                    "reason": cell.skipReason.rawValue,
                ]
            }
    }

    private static func eventJSON(
        for mapping: PlaybackSongSyntheticEventMapping,
        from result: PlaybackSongOfflineRenderResult
    ) -> [String: Any] {
        let event: SyntheticTrackerEvent? = result.plan.pattern.events.indices.contains(mapping.eventIndex)
            ? result.plan.pattern.events[mapping.eventIndex]
            : nil
        let startFrame = event?.scheduledStartFrame ?? 0
        let playbackStep = event?.playbackStep ?? mapping.playbackStep
        let sampleFrameCount = event?.sample.frameCount ?? 0
        let initialSourceFrame = event?.initialSourceFrame ?? mapping.sampleOffset.appliedOffsetFrames ?? 0
        let duration = eventDurationJSONFields(
            mapping: mapping,
            renderedFrameCount: result.renderedFrameCount,
            startFrame: startFrame,
            sampleFrameCount: sampleFrameCount,
            initialSourceFrame: initialSourceFrame,
            playbackStep: playbackStep
        )
        var durationFrames = duration.frames
        var durationReason = duration.reason
        var endFrame = max(startFrame, startFrame + duration.frames)
        if let cutFrame = firstAppliedNoteCutFrame(
            forEventIndex: mapping.eventIndex,
            from: result.diagnostics.noteCutEffects
        ), cutFrame >= startFrame {
            endFrame = min(endFrame, cutFrame)
            durationFrames = max(0, endFrame - startFrame)
            durationReason = "note_cut"
        }

        var object = [String: Any]()
        object["source"] = positionJSON(mapping.source)
        object["channel_index"] = mapping.channelIndex
        object["note"] = Int(mapping.note)
        object["instrument_index"] = mapping.instrumentIndex
        object["sample_index"] = mapping.sampleIndex
        object["selected_sample_length"] = mapping.selectedSampleLength
        object["sample_map_keymap_present"] = mapping.sampleMapKeymapPresent
        object["mapped_sample_index"] = nullableJSONValue(mapping.mappedSampleIndex)
        object["mapped_sample_valid"] = mapping.mappedSampleValid
        object["sample_selection_method"] = mapping.sampleSelectionMethod.rawValue
        object["selected_sample_selection_method"] = mapping.sampleSelectionMethod.rawValue
        object["sample_selection_strategy"] = mapping.sampleSelectionStrategy
        object["first_playable_sample_fallback_used"] = mapping.firstPlayableSampleFallbackUsed
        object["sample_map_keymap_behavior_deferred"] = mapping.sampleMapKeymapBehaviorDeferred
        object["sample_map_keymap_missing_or_deferred"] = mapping.sampleMapKeymapMissingOrDeferred
        object["effect_type"] = Int(mapping.effectType)
        object["effect_param"] = Int(mapping.effectParam)
        object["synthetic_row"] = mapping.syntheticRow
        object["synthetic_tick"] = mapping.syntheticTick
        object["event_index"] = mapping.eventIndex
        object["scheduled_start_frame"] = startFrame
        object["estimated_end_frame"] = endFrame
        object["estimated_duration_frames"] = durationFrames
        object["duration_estimate_reason"] = durationReason
        object["sample_frame_count"] = sampleFrameCount
        object["initial_source_frame"] = initialSourceFrame
        object["gain"] = Double(event?.gain ?? 0)
        object["pan"] = Double(event?.pan ?? mapping.effectivePan)
        object["loop_mode"] = loopModeName(mapping.loopMode)
        object["volume_column"] = volumeColumnDiagnosticJSON(mapping.volumeColumn)
        object["sample_offset"] = sampleOffsetDiagnosticJSON(mapping.sampleOffset)
        object["has_ignored_volume_column"] = mapping.hasIgnoredVolumeColumn
        object["has_ignored_effect"] = mapping.hasIgnoredEffect
        object["effective_volume_value"] = mapping.effectiveVolumeValue
        object["effective_pan"] = Double(mapping.effectivePan)
        object["volume_envelope"] = eventVolumeEnvelopeJSON(mapping)
        object["pitch"] = eventPitchJSON(mapping)
        if let startSeconds = seconds(forFrame: startFrame, sampleRate: result.block.config.sampleRate) {
            object["scheduled_start_seconds"] = startSeconds
        }
        if let endSeconds = seconds(forFrame: endFrame, sampleRate: result.block.config.sampleRate) {
            object["estimated_end_seconds"] = endSeconds
        }
        return object
    }

    private static func firstAppliedNoteCutFrame(
        forEventIndex eventIndex: Int,
        from cuts: [PlaybackSongSyntheticNoteCutDiagnostic]
    ) -> Int? {
        cuts
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .compactMap(\.scheduledFrame)
            .min()
    }

    private static func eventDurationJSONFields(
        mapping: PlaybackSongSyntheticEventMapping,
        renderedFrameCount: Int,
        startFrame: Int,
        sampleFrameCount: Int,
        initialSourceFrame: Int,
        playbackStep: Double
    ) -> (frames: Int, reason: String) {
        guard mapping.loopMode == .none else {
            return (max(0, renderedFrameCount - startFrame), "looped_until_render_end")
        }
        let remainingSourceFrames = max(0, sampleFrameCount - initialSourceFrame)
        let estimated = playbackStep > 0
            ? Int((Double(remainingSourceFrames) / playbackStep).rounded(.up))
            : remainingSourceFrames
        return (max(1, estimated), "one_shot_sample_length")
    }

    private static func eventVolumeEnvelopeJSON(_ mapping: PlaybackSongSyntheticEventMapping) -> [String: Any] {
        let semantics = mapping.volumeEnvelopeSemantics
        return [
            "status": volumeEnvelopeStatusName(mapping.volumeEnvelopeStatus),
            "enabled": semantics.envelopeEnabled,
            "source_point_count": mapping.sourceVolumeEnvelopePointCount,
            "mapped_point_count": mapping.mappedVolumeEnvelopePointCount,
            "sustain_enabled": semantics.sustainEnabled,
            "sustain_applied": semantics.sustainApplied,
            "sustain_deferred": semantics.sustainDeferred,
            "sustain_point_index": nullableJSONValue(semantics.sustainPointIndex),
            "sustain_tick": nullableJSONValue(semantics.sustainTick),
            "sustain_frame": nullableJSONValue(semantics.sustainFrame),
            "loop_enabled": semantics.loopEnabled,
            "loop_applied": semantics.loopApplied,
            "loop_deferred": semantics.loopDeferred,
            "loop_start_point_index": nullableJSONValue(semantics.loopStartPointIndex),
            "loop_end_point_index": nullableJSONValue(semantics.loopEndPointIndex),
            "loop_start_tick": nullableJSONValue(semantics.loopStartTick),
            "loop_end_tick": nullableJSONValue(semantics.loopEndTick),
            "loop_start_frame": nullableJSONValue(semantics.loopStartFrame),
            "loop_end_frame": nullableJSONValue(semantics.loopEndFrame),
            "key_off_encountered": semantics.keyOffEncountered,
            "key_off_applied": semantics.keyOffApplied,
            "key_off_deferred": semantics.keyOffDeferred,
            "key_off_source": semantics.keyOffSource.map(positionJSON) ?? NSNull(),
            "key_off_channel_index": nullableJSONValue(semantics.keyOffChannelIndex),
            "key_off_synthetic_row": nullableJSONValue(semantics.keyOffSyntheticRow),
            "key_off_synthetic_tick": nullableJSONValue(semantics.keyOffSyntheticTick),
            "release_frame": nullableJSONValue(semantics.releaseFrame),
            "fadeout_value": semantics.fadeoutValue,
            "fadeout_applied": semantics.fadeoutApplied,
            "fadeout_deferred": semantics.fadeoutDeferred,
            "limitations": semantics.limitations,
            "has_deferred_sustain": mapping.hasDeferredVolumeEnvelopeSustain,
            "has_deferred_loop": mapping.hasDeferredVolumeEnvelopeLoop,
            "has_deferred_fadeout": mapping.hasDeferredVolumeEnvelopeFadeout,
        ]
    }

    private static func eventPitchJSON(_ mapping: PlaybackSongSyntheticEventMapping) -> [String: Any] {
        [
            "source_note": Int(mapping.note),
            "sample_base_sample_rate": mapping.sampleBaseSampleRate,
            "sample_relative_note": mapping.sampleRelativeNote,
            "sample_finetune": mapping.sampleFinetune,
            "output_sample_rate": mapping.outputSampleRate,
            "effective_note_value": nullableJSONValue(mapping.effectiveNoteValue),
            "effective_note_index": nullableJSONValue(mapping.effectiveNoteIndex),
            "effective_finetune": nullableJSONValue(mapping.effectiveFinetune),
            "linear_period": nullableJSONValue(mapping.linearPeriod),
            "linear_frequency": nullableJSONValue(mapping.linearFrequency),
            "finetune_status": finetuneStatusName(mapping.finetuneStatus),
            "uses_linear_frequency_table": mapping.usesLinearFrequencyTable,
            "frequency_table_status": frequencyTableStatusName(mapping.frequencyTableStatus),
            "linear_frequency_applied": mapping.linearFrequencyApplied,
            "amiga_frequency_deferred": mapping.amigaFrequencyDeferred,
            "playback_step": mapping.playbackStep,
            "mapping_applied": mapping.pitchMappingApplied,
            "used_neutral_step": mapping.pitchMappingUsedNeutralStep,
            "fallback_neutral_step_used": mapping.pitchMappingUsedNeutralStep,
        ]
    }

    private static func keyOffEventJSON(_ diagnostic: PlaybackSongSyntheticKeyOffDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "release_frame": diagnostic.releaseFrame.map { $0 as Any } ?? NSNull(),
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "reason": keyOffReasonName(diagnostic.reason),
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
        ]
    }

    private static func orderJSON(_ diagnostic: PlaybackSongSyntheticOrderDiagnostic) -> [String: Any] {
        [
            "requested_order_index": diagnostic.requestedOrderIndex,
            "pattern_index": diagnostic.patternIndex ?? NSNull(),
            "synthetic_start_row": diagnostic.syntheticStartRow,
            "row_count": diagnostic.rowCount,
            "status": orderStatusName(diagnostic.status),
        ]
    }

    private static func rowMappingJSON(_ mapping: PlaybackSongSyntheticRowMapping) -> [String: Any] {
        [
            "source": positionJSON(mapping.source),
            "synthetic_row": mapping.syntheticRow,
        ]
    }

    private static func rowDiagnosticJSON(_ diagnostic: PlaybackSongSyntheticRowDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "synthetic_row": diagnostic.syntheticRow,
            "cell_count": diagnostic.cellCount,
            "emitted_event_count": diagnostic.emittedEventCount,
            "ignored_cell_count": diagnostic.ignoredCellCount,
        ]
    }

    private static func rowTimingJSON(_ diagnostic: PlaybackSongSyntheticRowTimingDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "synthetic_row": diagnostic.syntheticRow,
            "row_start_frame": diagnostic.rowStartFrame,
            "row_end_frame": diagnostic.rowStartFrame + diagnostic.rowDurationFrames,
            "row_duration_frames": diagnostic.rowDurationFrames,
            "effective_speed": diagnostic.effectiveSpeed,
            "effective_bpm": diagnostic.effectiveBPM,
        ]
    }

    private static func timingChangeJSON(_ diagnostic: PlaybackSongSyntheticTimingChangeDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "row_start_frame": diagnostic.rowStartFrame,
            "applies_to_synthetic_row_after": diagnostic.appliesToSyntheticRowAfter,
            "kind": timingChangeKindName(diagnostic.kind),
            "applied": diagnostic.applied,
            "speed_before": diagnostic.speedBefore,
            "bpm_before": diagnostic.bpmBefore,
            "speed_after": diagnostic.speedAfter,
            "bpm_after": diagnostic.bpmAfter,
        ]
    }

    private static func volumeColumnMappingJSON(_ mapping: PlaybackSongSyntheticVolumeColumnMapping) -> [String: Any] {
        [
            "source": positionJSON(mapping.source),
            "channel_index": mapping.channelIndex,
            "synthetic_row": mapping.syntheticRow,
            "synthetic_tick": mapping.syntheticTick,
            "volume_column": volumeColumnDiagnosticJSON(mapping.volumeColumn),
        ]
    }

    private static func voiceStateUpdateSummaryJSON(
        _ updates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    ) -> [String: Any] {
        func count(_ predicate: (PlaybackSongSyntheticVoiceStateUpdateDiagnostic) -> Bool) -> Int {
            updates.filter(predicate).count
        }
        return [
            "total_state_updates": updates.count,
            "applied_count": count(\.applied),
            "deferred_count": count(\.deferred),
            "ignored_no_op_count": count(\.ignoredAsNoOp),
            "active_voice_updated_count": count(\.activeVoiceUpdated),
            "active_voice_not_updated_count": count { !$0.activeVoiceUpdated },
            "empty_note_volume_column_set_volume_applied": count {
                $0.applied && isEmptyNoteVolumeColumnSetVolume($0)
            },
            "empty_note_volume_column_set_volume_deferred": count {
                $0.deferred && isEmptyNoteVolumeColumnSetVolume($0)
            },
            "empty_note_volume_column_set_panning_applied": count {
                $0.applied && isEmptyNoteVolumeColumnSetPanning($0)
            },
            "empty_note_volume_column_set_panning_deferred": count {
                $0.deferred && isEmptyNoteVolumeColumnSetPanning($0)
            },
            "cxx_set_volume_applied": count {
                $0.applied && isCxxSetVolumeUpdate($0)
            },
            "cxx_set_volume_deferred": count {
                $0.deferred && isCxxSetVolumeUpdate($0)
            },
            "effect_8xx_set_panning_applied": count {
                $0.applied && is8xxSetPanningUpdate($0)
            },
            "effect_8xx_set_panning_deferred": count {
                $0.deferred && is8xxSetPanningUpdate($0)
            },
            "axy_volume_slide_applied": count {
                $0.applied && isAxyVolumeSlideUpdate($0)
            },
            "axy_volume_slide_deferred": count {
                $0.deferred && isAxyVolumeSlideUpdate($0)
            },
            "hxy_global_volume_slide_applied": count {
                $0.applied && isHxyGlobalVolumeSlideUpdate($0)
            },
            "hxy_global_volume_slide_deferred": count {
                $0.deferred && isHxyGlobalVolumeSlideUpdate($0)
            },
        ]
    }

    private static func isEmptyNoteVolumeColumnSetVolume(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        guard update.hasEmptyNote,
              update.commandSource == .volumeColumn,
              case let .volumeColumn(command) = update.command else {
            return false
        }
        if case .setVolume = command {
            return true
        }
        return false
    }

    private static func isEmptyNoteVolumeColumnSetPanning(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        guard update.hasEmptyNote,
              update.commandSource == .volumeColumn,
              case let .volumeColumn(command) = update.command else {
            return false
        }
        if case .setPanning = command {
            return true
        }
        return false
    }

    private static func isCxxSetVolumeUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .cxxSetVolume = update.command {
            return true
        }
        return false
    }

    private static func is8xxSetPanningUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .effect8xxSetPanning = update.command {
            return true
        }
        return false
    }

    private static func isAxyVolumeSlideUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .axyVolumeSlide = update.command {
            return true
        }
        return false
    }

    private static func isHxyGlobalVolumeSlideUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .hxyGlobalVolumeSlide = update.command {
            return true
        }
        return false
    }

    private static func voiceStateUpdateJSON(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> [String: Any] {
        var object: [String: Any] = [
            "source": positionJSON(update.source),
            "channel_index": update.channelIndex,
            "synthetic_row": update.syntheticRow,
            "synthetic_tick": update.syntheticTick,
            "scheduled_frame": update.scheduledFrame,
            "cell_note": Int(update.cellNote),
            "instrument_index": update.instrumentIndex,
            "command_source": voiceStateUpdateSourceName(update.commandSource),
            "command_label": update.command.label,
            "command_name": voiceStateCommandName(update.command),
            "command": voiceStateCommandJSON(update.command),
            "status": voiceStateUpdateStatusName(update.status),
            "applied": update.applied,
            "deferred": update.deferred,
            "ignored_as_no_op": update.ignoredAsNoOp,
            "active_voice_updated": update.activeVoiceUpdated,
        ]
        put(update.rawVolumeColumn.map { Int($0) }, forKey: "raw_volume_column", into: &object)
        put(update.effectType.map { Int($0) }, forKey: "effect_type", into: &object)
        put(update.effectParam.map { Int($0) }, forKey: "effect_param", into: &object)
        put(update.behavior.map(volumeColumnBehaviorName), forKey: "behavior", into: &object)
        put(update.activeEventIndex, forKey: "active_event_index", into: &object)
        put(update.effectiveVolumeBefore, forKey: "effective_volume_before", into: &object)
        put(update.effectiveVolumeAfter, forKey: "effective_volume_after", into: &object)
        put(update.effectivePanBefore.map { Double($0) }, forKey: "effective_pan_before", into: &object)
        put(update.effectivePanAfter.map { Double($0) }, forKey: "effective_pan_after", into: &object)
        put(update.gainBefore.map { Double($0) }, forKey: "gain_before", into: &object)
        put(update.gainAfter.map { Double($0) }, forKey: "gain_after", into: &object)
        put(update.panBefore.map { Double($0) }, forKey: "pan_before", into: &object)
        put(update.panAfter.map { Double($0) }, forKey: "pan_after", into: &object)
        return object
    }

    private static func ignoredCellJSON(_ cell: PlaybackSongSyntheticIgnoredCell) -> [String: Any] {
        [
            "source": positionJSON(cell.source),
            "channel_index": cell.channelIndex,
            "note": Int(cell.note),
            "instrument_index": cell.instrumentIndex,
            "reason": ignoredCellReasonName(cell.reason),
            "skip_reason": cell.skipReason.rawValue,
            "selected_sample_index": cell.selectedSampleIndex.map { $0 as Any } ?? NSNull(),
            "selected_sample_length": cell.selectedSampleLength.map { $0 as Any } ?? NSNull(),
            "selected_sample_loop_mode": cell.selectedSampleLoopMode.map(loopModeName) ?? NSNull(),
            "sample_map_keymap_present": cell.sampleMapKeymapPresent,
            "mapped_sample_index": cell.mappedSampleIndex.map { $0 as Any } ?? NSNull(),
            "mapped_sample_valid": cell.mappedSampleValid,
            "sample_selection_method": cell.sampleSelectionMethod.rawValue,
            "selected_sample_selection_method": cell.sampleSelectionMethod.rawValue,
            "first_playable_sample_fallback_used": cell.firstPlayableSampleFallbackUsed,
            "sample_map_keymap_behavior_deferred": cell.sampleMapKeymapBehaviorDeferred,
            "sample_map_keymap_missing_or_deferred": cell.sampleMapKeymapMissingOrDeferred,
            "sample_relative_note": cell.sampleRelativeNote.map { $0 as Any } ?? NSNull(),
            "sample_finetune": cell.sampleFinetune.map { $0 as Any } ?? NSNull(),
            "sample_base_sample_rate": cell.sampleBaseSampleRate.map { $0 as Any } ?? NSNull(),
            "sample_offset_frames": cell.sampleOffsetFrames.map { $0 as Any } ?? NSNull(),
            "volume_column": volumeColumnDiagnosticJSON(cell.volumeColumn),
            "has_ignored_volume_column": cell.hasIgnoredVolumeColumn,
            "has_ignored_effect": cell.hasIgnoredEffect,
        ]
    }

    private static func deferredFieldJSON(_ field: PlaybackSongSyntheticDeferredCellField) -> [String: Any] {
        [
            "source": positionJSON(field.source),
            "channel_index": field.channelIndex,
            "note": Int(field.note),
            "instrument_index": field.instrumentIndex,
            "volume_column_raw": Int(field.volumeColumn),
            "volume_column": volumeColumnDiagnosticJSON(field.volumeColumnDiagnostic),
            "effect_type": Int(field.effectType),
            "effect_param": Int(field.effectParam),
            "field": deferredFieldName(field.field),
        ]
    }

    private static func volumeColumnDiagnosticJSON(_ diagnostic: PlaybackSongSyntheticVolumeColumnDiagnostic) -> [String: Any] {
        var object: [String: Any] = [
            "raw_value": Int(diagnostic.rawValue),
            "command": volumeCommandJSON(diagnostic.command),
            "classification": volumeColumnClassificationName(diagnostic.classification),
            "applied": diagnostic.applied,
            "ignored_as_empty_or_no_op": diagnostic.ignoredAsEmptyOrNoOp,
            "deferred": diagnostic.deferred,
        ]
        put(diagnostic.appliedVolumeValue, forKey: "applied_volume_value", into: &object)
        put(diagnostic.appliedGainMultiplier.map { Double($0) }, forKey: "applied_gain_multiplier", into: &object)
        put(diagnostic.appliedPanningValue, forKey: "applied_panning_value", into: &object)
        put(diagnostic.appliedPan.map { Double($0) }, forKey: "applied_pan", into: &object)
        put(diagnostic.slideAmount, forKey: "slide_amount", into: &object)
        put(diagnostic.slideDirection.map(slideDirectionName), forKey: "slide_direction", into: &object)
        put(diagnostic.effectiveVolumeBefore, forKey: "effective_volume_before", into: &object)
        put(diagnostic.effectiveVolumeAfter, forKey: "effective_volume_after", into: &object)
        put(diagnostic.effectivePanBefore.map { Double($0) }, forKey: "effective_pan_before", into: &object)
        put(diagnostic.effectivePanAfter.map { Double($0) }, forKey: "effective_pan_after", into: &object)
        put(diagnostic.behavior.map(volumeColumnBehaviorName), forKey: "behavior", into: &object)
        return object
    }

    private static func sampleOffsetDiagnosticJSON(_ diagnostic: PlaybackSongSyntheticSampleOffsetDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": sampleOffsetStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "skipped": diagnostic.skipped,
            "out_of_range": diagnostic.outOfRange,
            "computed_offset_frames": diagnostic.computedOffsetFrames,
            "applied_offset_frames": diagnostic.appliedOffsetFrames.map { $0 as Any } ?? NSNull(),
            "selected_sample_length": diagnostic.selectedSampleLength.map { $0 as Any } ?? NSNull(),
        ]
    }

    private static func noteCutDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticNoteCutDiagnostic,
        from result: PlaybackSongOfflineRenderResult
    ) -> [String: Any] {
        var object: [String: Any] = [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": noteCutStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "out_of_row": diagnostic.outOfRow,
            "requested_tick": diagnostic.requestedTick,
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "scheduled_frame": diagnostic.scheduledFrame.map { $0 as Any } ?? NSNull(),
            "absolute_frame": diagnostic.scheduledFrame.map { $0 as Any } ?? NSNull(),
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
        ]
        let targetVoiceIndices = targetVoiceIndices(
            forEventIndex: diagnostic.activeEventIndex,
            in: result
        )
        object["target_voice_indices"] = targetVoiceIndices
        object["target_voice_index"] = targetVoiceIndices.first.map { $0 as Any } ?? NSNull()
        return object
    }

    private static func noteDelayDiagnosticJSON(_ diagnostic: PlaybackSongSyntheticNoteDelayDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": noteDelayStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "out_of_row": diagnostic.outOfRow,
            "requested_tick": diagnostic.requestedTick,
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "original_frame": diagnostic.originalFrame,
            "delayed_frame": diagnostic.delayedFrame.map { $0 as Any } ?? NSNull(),
            "scheduled_frame": diagnostic.delayedFrame.map { $0 as Any } ?? NSNull(),
            "absolute_frame": diagnostic.delayedFrame.map { $0 as Any } ?? NSNull(),
            "event_index": diagnostic.eventIndex.map { $0 as Any } ?? NSNull(),
        ]
    }

    private static func targetVoiceIndices(
        forEventIndex eventIndex: Int?,
        in result: PlaybackSongOfflineRenderResult
    ) -> [Int] {
        guard let eventIndex else {
            return []
        }
        return result.scheduledVoiceAttempts.compactMap { attempt in
            guard attempt.eventIndex == eventIndex else {
                return nil
            }
            return attempt.voiceIndex
        }
    }

    private static func positionJSON(_ position: PlaybackPosition) -> [String: Any] {
        [
            "order": position.orderIndex,
            "pattern": position.patternIndex,
            "row": position.rowIndex,
        ]
    }

    private static func volumeCommandJSON(_ command: PlaybackSongSyntheticVolumeColumnCommand) -> [String: Any] {
        switch command {
        case .none:
            return ["name": "none"]
        case let .setVolume(value):
            return ["name": "setVolume", "value": value]
        case let .volumeSlideDown(amount):
            return ["name": "volumeSlideDown", "amount": amount]
        case let .volumeSlideUp(amount):
            return ["name": "volumeSlideUp", "amount": amount]
        case let .fineVolumeSlideDown(amount):
            return ["name": "fineVolumeSlideDown", "amount": amount]
        case let .fineVolumeSlideUp(amount):
            return ["name": "fineVolumeSlideUp", "amount": amount]
        case let .setVibratoSpeed(amount):
            return ["name": "setVibratoSpeed", "amount": amount]
        case let .vibrato(amount):
            return ["name": "vibrato", "amount": amount]
        case let .setPanning(value):
            return ["name": "setPanning", "value": value]
        case let .panningSlideLeft(amount):
            return ["name": "panningSlideLeft", "amount": amount]
        case let .panningSlideRight(amount):
            return ["name": "panningSlideRight", "amount": amount]
        case let .tonePortamento(amount):
            return ["name": "tonePortamento", "amount": amount]
        case let .unsupported(rawValue):
            return ["name": "unsupported", "raw_value": Int(rawValue)]
        }
    }

    private static func voiceStateCommandJSON(
        _ command: PlaybackSongSyntheticVoiceStateUpdateCommand
    ) -> [String: Any] {
        switch command {
        case let .volumeColumn(command):
            return [
                "name": voiceStateCommandName(.volumeColumn(command)),
                "label": command.name,
                "volume_column": volumeCommandJSON(command),
            ]
        case let .cxxSetVolume(value):
            return ["name": "cxxSetVolume", "label": command.label, "value": value]
        case let .effect8xxSetPanning(value):
            return ["name": "effect8xxSetPanning", "label": command.label, "value": value]
        case let .axyVolumeSlide(up, down):
            return ["name": "axyVolumeSlide", "label": command.label, "up": up, "down": down]
        case .hxyGlobalVolumeSlide:
            return ["name": "hxyGlobalVolumeSlide", "label": command.label]
        }
    }

    private static func voiceStateCommandName(
        _ command: PlaybackSongSyntheticVoiceStateUpdateCommand
    ) -> String {
        switch command {
        case let .volumeColumn(command):
            return command.name
        case .cxxSetVolume:
            return "cxxSetVolume"
        case .effect8xxSetPanning:
            return "effect8xxSetPanning"
        case .axyVolumeSlide:
            return "axyVolumeSlide"
        case .hxyGlobalVolumeSlide:
            return "hxyGlobalVolumeSlide"
        }
    }

    private static func put(_ value: Any?, forKey key: String, into object: inout [String: Any]) {
        if let value {
            object[key] = value
        }
    }

    private static func nullableJSONValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func seconds(forFrame frame: Int, sampleRate: Double) -> Double? {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return nil
        }
        return Double(frame) / sampleRate
    }

    private static func orderStatusName(_ status: PlaybackSongSyntheticOrderDiagnostic.Status) -> String {
        switch status {
        case .adapted:
            return "adapted"
        case .invalidOrder:
            return "invalid_order"
        case .missingPattern:
            return "missing_pattern"
        }
    }

    private static func timingChangeKindName(_ kind: PlaybackSongSyntheticTimingChangeDiagnostic.Kind) -> String {
        switch kind {
        case .speed:
            return "speed"
        case .bpm:
            return "bpm"
        case .ignoredF00:
            return "ignored_f00"
        }
    }

    private static func volumeColumnClassificationName(_ classification: PlaybackSongSyntheticVolumeColumnClassification) -> String {
        switch classification {
        case .ignoredNoOp:
            return "ignored_no_op"
        case .supported:
            return "supported"
        case .deferred:
            return "deferred"
        }
    }

    private static func slideDirectionName(_ direction: PlaybackSongSyntheticVolumeColumnSlideDirection) -> String {
        switch direction {
        case .volumeDown:
            return "volume_down"
        case .volumeUp:
            return "volume_up"
        case .panningLeft:
            return "panning_left"
        case .panningRight:
            return "panning_right"
        }
    }

    private static func volumeColumnBehaviorName(_ behavior: PlaybackSongSyntheticVolumeColumnBehavior) -> String {
        switch behavior {
        case .rowLevelApproximation:
            return "row_level_approximation"
        }
    }

    private static func sampleOffsetStatusName(_ status: PlaybackSongSyntheticSampleOffsetDiagnostic.Status) -> String {
        switch status {
        case .notPresent:
            return "not_present"
        case .applied:
            return "applied"
        case .ignored900NoOp:
            return "ignored_900_no_op"
        case .outOfRangeSkipped:
            return "out_of_range_skipped"
        }
    }

    private static func noteCutStatusName(_ status: PlaybackSongSyntheticNoteCutDiagnostic.Status) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .outOfRowNoOp:
            return "out_of_row_no_op"
        }
    }

    private static func noteDelayStatusName(_ status: PlaybackSongSyntheticNoteDelayDiagnostic.Status) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noNoteDeferred:
            return "no_note_deferred"
        case .outOfRowNoOp:
            return "out_of_row_no_op"
        }
    }

    private static func effectCommandStatusName(_ status: PlaybackSongSyntheticEffectCommandDiagnostic.Status) -> String {
        switch status {
        case .applied:
            return "applied"
        case .ignoredNoOp:
            return "ignored/no-op"
        case .deferredUnsupported:
            return "deferred/unsupported"
        case .unknown:
            return "unknown"
        }
    }

    private static func voiceStateUpdateSourceName(
        _ source: PlaybackSongSyntheticVoiceStateUpdateSource
    ) -> String {
        switch source {
        case .volumeColumn:
            return "volume_column"
        case .effectColumn:
            return "effect_column"
        }
    }

    private static func voiceStateUpdateStatusName(
        _ status: PlaybackSongSyntheticVoiceStateUpdateStatus
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .ignoredNoOp:
            return "ignored/no-op"
        case .deferredUnsupported:
            return "deferred/unsupported"
        }
    }

    private static func loopModeName(_ mode: MixerSampleLoopMode) -> String {
        switch mode {
        case .none:
            return "none"
        case .forward:
            return "forward"
        case .pingPong:
            return "ping_pong"
        }
    }

    private static func volumeEnvelopeStatusName(_ status: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus) -> String {
        switch status {
        case .absent:
            return "absent"
        case .disabled:
            return "disabled"
        case .invalidOrEmptyIgnored:
            return "invalid_or_empty_ignored"
        case .mapped:
            return "mapped"
        }
    }

    private static func finetuneStatusName(_ status: PlaybackSongSyntheticEventMapping.FinetuneStatus) -> String {
        switch status {
        case .applied:
            return "applied"
        case .deferred:
            return "deferred"
        }
    }

    private static func frequencyTableStatusName(_ status: PlaybackSongSyntheticEventMapping.FrequencyTableStatus) -> String {
        switch status {
        case .linearApplied:
            return "linear_applied"
        case .amigaTableDeferredNeutralFallback:
            return "amiga_table_deferred_neutral_fallback"
        }
    }

    private static func ignoredCellReasonName(_ reason: PlaybackSongSyntheticIgnoredCell.Reason) -> String {
        switch reason {
        case .emptyNote:
            return "empty_note"
        case .instrumentOnly:
            return "instrument_only"
        case .keyOff:
            return "key_off"
        case .invalidNote:
            return "invalid_note"
        case .missingInstrument:
            return "missing_instrument"
        case .unknownInstrument:
            return "unknown_instrument"
        case .instrumentHasNoPlayableSample:
            return "instrument_has_no_playable_sample"
        case .samplePCMEmpty:
            return "sample_pcm_empty"
        case .sampleOffsetOutOfRange:
            return "sample_offset_out_of_range"
        case .noteDelayOutOfRow:
            return "note_delay_out_of_row"
        case .noteDelayWithoutNote:
            return "note_delay_without_note"
        case .noSelectedSampleForNote:
            return "no_selected_sample_for_note"
        case .unsupportedDeferredEffectInteraction:
            return "unsupported_deferred_effect_interaction"
        case .unknown:
            return "unknown"
        }
    }

    private static func keyOffReasonName(_ reason: PlaybackSongSyntheticKeyOffDiagnostic.Reason) -> String {
        switch reason {
        case .releasedActiveVoice:
            return "released_active_voice"
        case .noActiveVoice:
            return "no_active_voice"
        }
    }

    private static func deferredFieldName(_ field: PlaybackSongSyntheticDeferredCellField.Field) -> String {
        switch field {
        case .volumeColumn:
            return "volume_column"
        case .effect:
            return "effect"
        case .keyOff:
            return "key_off"
        case .volumeEnvelopeSustain:
            return "volume_envelope_sustain"
        case .volumeEnvelopeLoop:
            return "volume_envelope_loop"
        case .volumeEnvelopeFadeout:
            return "volume_envelope_fadeout"
        }
    }
}

private extension URL {
    func isInside(_ parent: URL) -> Bool {
        relativePath(from: parent) != nil
    }

    func relativePath(from parent: URL) -> String? {
        let childPath = standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        if childPath == parentPath {
            return ""
        }
        let prefix = parentPath.hasSuffix("/") ? parentPath : parentPath + "/"
        guard childPath.hasPrefix(prefix) else {
            return nil
        }
        return String(childPath.dropFirst(prefix.count))
    }
}

func renderToolUsage() -> String {
    """
    Usage:
      \(toolName) --input /path/to/module.xm --output /tmp/vtx-candidate.wav --order 10 [options]

    Options:
      --input PATH          Local XM module path. Required.
      --output PATH         Local candidate WAV path. Required; prefer /tmp.
      --diagnostics-json PATH
                            Optional local adapter diagnostics JSON path; prefer /tmp.
      --order N             Zero-based order index to render. Required.
      --order-count N       Number of playable orders to include. Default: 1.
      --rows N              Render this many flattened rows from the bounded range.
      --sample-rate HZ      Output sample rate. Default: 44100.
      --seconds N           Render this many seconds; converted to seconds * sample-rate frames.
      --max-frames N        Explicit maximum output frames.
      --window-rows N       Opt into row-windowed offline scheduling for long local renders.
      --allow-long-render   Required when --seconds/--max-frames exceeds the default safety clamp.
      --progress            Print render percentage and phase/status messages to stderr.
      --help                Show this help.

    Default safety clamp: \(PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount) frames (60 seconds at 44100 Hz).
    --progress reports render percentage by rendered frames or row windows, then a coarse WAV-writing phase.
    --seconds and --max-frames are mutually exclusive. Keep long outputs under /tmp or ignored scratch paths.
    Generated WAVs are local diagnostic artifacts and must not be committed.
    This helper uses the offline C-backed PlaybackSongOfflineRenderer.exportWAV path only.
    """
}

func renderToolSummary(
    arguments: RenderToolArguments,
    result: PlaybackSongOfflineRenderResult
) -> String {
    let renderedDuration = result.block.config.sampleRate > 0
        ? Double(result.renderedFrameCount) / result.block.config.sampleRate
        : 0
    let capDuration = result.block.config.sampleRate > 0
        ? Double(result.maximumFrameCount) / result.block.config.sampleRate
        : 0
    var lines = [
        "Developer-only bounded XM candidate WAV render.",
        "Generated WAVs/reports/traces/screenshots are local artifacts and must not be committed.",
        "Runtime playback remains AVAudioPlayerNode / AVAudioUnitVarispeed; the C mixer is offline-only.",
        "Module: \(URL(fileURLWithPath: arguments.inputPath).standardizedFileURL.path)",
        "Output: \(URL(fileURLWithPath: arguments.outputPath).standardizedFileURL.path)",
    ]
    if let diagnosticsJSONPath = arguments.diagnosticsJSONPath {
        lines.append("Diagnostics JSON: \(URL(fileURLWithPath: diagnosticsJSONPath).standardizedFileURL.path)")
    }
    lines.append("Requested order range: \(arguments.order)..<\(arguments.order + arguments.orderCount)")
    if let rows = arguments.rows {
        lines.append("Requested rows: \(rows)")
    } else {
        lines.append("Requested rows: not specified")
    }
    if let windowRows = arguments.windowRows {
        lines.append("Windowed render: enabled, \(windowRows) rows per window.")
    } else {
        lines.append("Windowed render: disabled.")
    }
    lines.append("Sample rate: \(Int(result.block.config.sampleRate)) Hz")
    lines.append("Effective frame cap: \(result.maximumFrameCount)")
    lines.append(String(format: "Effective duration cap: %.3f seconds", capDuration))
    let clampMode = arguments.usesDefaultRenderClamp
        ? "default safety clamp"
        : "explicit override\(arguments.allowLongRender ? " with --allow-long-render" : "")"
    lines.append("Render cap mode: \(clampMode)")
    lines.append("Rendered frames: \(result.renderedFrameCount)")
    lines.append(String(format: "Rendered duration: %.3f seconds", renderedDuration))
    if result.wasFrameCountBounded {
        lines.append("Frame count was clamped to \(result.maximumFrameCount) frames.")
    }
    appendWindowedRenderSummary(to: &lines, result: result)
    if arguments.diagnosticsJSONPath != nil || arguments.progress {
        appendEventCoverageSummary(to: &lines, result: result)
    }
    lines.append("Export succeeded.")
    return lines.joined(separator: "\n")
}

private func appendWindowedRenderSummary(
    to lines: inout [String],
    result: PlaybackSongOfflineRenderResult
) {
    guard let summary = result.windowedRenderSummary else {
        return
    }
    lines.append(
        "Windowed scheduling: \(summary.windowCount) windows, \(summary.totalAcceptedScheduledEvents)/\(summary.totalScheduledEvents) accepted, \(summary.totalScheduledCapacityRejects) scheduled capacity rejects."
    )
    lines.append(
        "Window carryover: \(summary.totalCarriedVoices) carried voices, \(summary.totalReleasedVoiceCarryovers) released/fadeout carryovers, \(summary.totalDroppedAtWindowBoundaries) boundary drops, may contain boundary cuts: \(summary.mayContainBoundaryCuts)."
    )
    if !summary.knownUnsupportedCarryoverReasons.isEmpty {
        lines.append("Unsupported carryover reasons: \(summary.knownUnsupportedCarryoverReasons.joined(separator: ", ")).")
    }
}

private func appendEventCoverageSummary(
    to lines: inout [String],
    result: PlaybackSongOfflineRenderResult
) {
    let coverage = result.diagnostics.eventCoverage
    let traversal = result.diagnostics.traversalHazardSummary
    let rejectedVoiceCount = result.scheduledVoiceAttempts.compactMap(\.rejectionReason).count
    lines.append("Event coverage: parsed normal notes \(coverage.normalNoteCells), scheduled events \(coverage.scheduledNoteEvents), skipped notes \(coverage.skippedNoteEvents).")
    lines.append(
        "Sample selection: sample_map \(coverage.sampleMapSelectionEvents), first_playable_fallback \(coverage.firstPlayableSampleFallbackEvents), fallback_after_invalid_map \(coverage.fallbackAfterInvalidSampleMapEvents), skipped_no_valid_sample \(coverage.skippedNoValidSampleEvents), missing_or_deferred_keymap \(coverage.sampleMapKeymapDeferredEvents)."
    )
    let topReasons = coverage.skipReasonCounts.prefix(3).map { "\($0.reason.rawValue)=\($0.count)" }
    lines.append("Top skip reasons: \(topReasons.isEmpty ? "none" : topReasons.joined(separator: ", ")).")
    let skippedCoordinates = result.diagnostics.ignoredCells
        .filter { (1...96).contains($0.note) }
        .prefix(5)
        .map { cell in
            "order \(cell.source.orderIndex) pattern \(cell.source.patternIndex) row \(cell.source.rowIndex) ch \(cell.channelIndex) \(cell.skipReason.rawValue)"
        }
    lines.append("First skipped note coordinates: \(skippedCoordinates.isEmpty ? "none" : skippedCoordinates.joined(separator: "; ")).")
    lines.append(
        "C mixer scheduling: \(result.scheduledVoiceAttempts.count - rejectedVoiceCount)/\(result.scheduledVoiceAttempts.count) accepted, \(rejectedVoiceCount) rejected, scheduled capacity \(CSoftwareMixer.maximumScheduledVoiceCount), active capacity \(CSoftwareMixer.maximumActiveVoiceCount)."
    )
    let stateUpdates = result.diagnostics.voiceStateUpdates
    let appliedStateUpdates = stateUpdates.filter(\.applied).count
    let deferredStateUpdates = stateUpdates.filter(\.deferred).count
    let activeVoiceStateUpdates = stateUpdates.filter(\.activeVoiceUpdated).count
    lines.append(
        "Volume/panning state updates: \(appliedStateUpdates) applied, \(deferredStateUpdates) deferred, \(activeVoiceStateUpdates) active voice updates."
    )
    let appliedCuts = result.diagnostics.noteCutEffects.filter(\.applied).count
    let deferredCuts = result.diagnostics.noteCutEffects.filter(\.deferred).count
    let noActiveCuts = result.diagnostics.noteCutEffects.filter { $0.status == .noActiveVoice }.count
    let appliedDelays = result.diagnostics.noteDelayEffects.filter(\.applied).count
    let deferredDelays = result.diagnostics.noteDelayEffects.filter(\.deferred).count
    let outOfRowDelays = result.diagnostics.noteDelayEffects.filter(\.outOfRow).count
    lines.append(
        "Note cut/delay: ECx \(appliedCuts) applied, \(deferredCuts) deferred, \(noActiveCuts) no-active; EDx \(appliedDelays) applied, \(deferredDelays) deferred, \(outOfRowDelays) out-of-row."
    )
    lines.append(
        "Traversal hazards: Bxx \(traversal.totalBxxPositionJump), Dxx \(traversal.totalDxxPatternBreak), EEx \(traversal.totalEExPatternDelay), total \(traversal.totalTraversalHazards), likely ignored \(traversal.likelyIgnoresStructureChangingBehavior)."
    )
}

private func printSummary(
    arguments: RenderToolArguments,
    result: PlaybackSongOfflineRenderResult
) {
    print(renderToolSummary(arguments: arguments, result: result))
}
