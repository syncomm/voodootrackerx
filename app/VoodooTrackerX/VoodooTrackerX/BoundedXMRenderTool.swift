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
    case invalidExportGainPolicy(String)
    case invalidIsolationFilter(String)
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
             let .invalidWindowRows(message),
             let .invalidExportGainPolicy(message),
             let .invalidIsolationFilter(message):
            return message
        case let .longRenderRequiresAllowLongRender(frames, defaultLimit):
            return "Requested render cap \(frames) frames exceeds the default safety clamp \(defaultLimit) frames. Pass --allow-long-render intentionally for longer local renders."
        }
    }
}

enum RenderDurationMode: String, Equatable {
    case defaultSafetyClamp = "default_safety_clamp"
    case fixedRows = "fixed_rows"
    case fixedSeconds = "fixed_seconds"
    case maxFrames = "max_frames"
    case untilSongEnd = "until_song_end"

    var summaryName: String {
        switch self {
        case .defaultSafetyClamp:
            return "default safety clamp"
        case .fixedRows:
            return "fixed rows"
        case .fixedSeconds:
            return "fixed seconds"
        case .maxFrames:
            return "max frames"
        case .untilSongEnd:
            return "until song end"
        }
    }
}

struct RenderDurationDiagnostics: Equatable {
    let mode: RenderDurationMode
    let calculatedSongEndFrames: Int?
    let tailSeconds: Double
    let tailFrames: Int
    let effectiveFrameCap: Int
    let effectiveDurationSeconds: Double

    static func fallback(from result: PlaybackSongOfflineRenderResult) -> RenderDurationDiagnostics {
        let duration = result.block.config.sampleRate > 0
            ? Double(result.maximumFrameCount) / result.block.config.sampleRate
            : 0
        return RenderDurationDiagnostics(
            mode: .defaultSafetyClamp,
            calculatedSongEndFrames: nil,
            tailSeconds: 0,
            tailFrames: 0,
            effectiveFrameCap: result.maximumFrameCount,
            effectiveDurationSeconds: duration
        )
    }
}

struct RenderToolArguments: Equatable {
    let inputPath: String
    let outputPath: String
    let diagnosticsJSONPath: String?
    let effectCoverageJSONPath: String?
    let order: Int
    let orderCount: Int
    let rows: Int?
    let sampleRate: Double
    let maxFrames: Int?
    let seconds: Double?
    let untilSongEnd: Bool
    let tailSeconds: Double?
    let windowRows: Int?
    let allowLongRender: Bool
    let progress: Bool
    let gain: Double?
    let headroomDB: Double?
    let autoHeadroom: Bool
    let isolationFilter: PlaybackSongRenderIsolationFilter?

    init(
        inputPath: String,
        outputPath: String,
        diagnosticsJSONPath: String?,
        effectCoverageJSONPath: String? = nil,
        order: Int,
        orderCount: Int,
        rows: Int?,
        sampleRate: Double,
        maxFrames: Int?,
        seconds: Double?,
        untilSongEnd: Bool = false,
        tailSeconds: Double? = nil,
        windowRows: Int? = nil,
        allowLongRender: Bool = false,
        progress: Bool = false,
        gain: Double? = nil,
        headroomDB: Double? = nil,
        autoHeadroom: Bool = false,
        isolationFilter: PlaybackSongRenderIsolationFilter? = nil
    ) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.diagnosticsJSONPath = diagnosticsJSONPath
        self.effectCoverageJSONPath = effectCoverageJSONPath
        self.order = order
        self.orderCount = orderCount
        self.rows = rows
        self.sampleRate = sampleRate
        self.maxFrames = maxFrames
        self.seconds = seconds
        self.untilSongEnd = untilSongEnd
        self.tailSeconds = tailSeconds
        self.windowRows = windowRows
        self.allowLongRender = allowLongRender
        self.progress = progress
        self.gain = gain
        self.headroomDB = headroomDB
        self.autoHeadroom = autoHeadroom
        self.isolationFilter = isolationFilter?.isEnabled == true ? isolationFilter : nil
    }

    static func parse(_ argv: [String]) throws -> RenderToolArguments {
        var inputPath: String?
        var outputPath: String?
        var diagnosticsJSONPath: String?
        var effectCoverageJSONPath: String?
        var order: Int?
        var orderCount = 1
        var rows: Int?
        var sampleRate = MixerRenderConfig.defaultSampleRate
        var maxFrames: Int?
        var seconds: Double?
        var untilSongEnd = false
        var tailSeconds: Double?
        var windowRows: Int?
        var allowLongRender = false
        var progress = false
        var gain: Double?
        var headroomDB: Double?
        var autoHeadroom = false
        var soloChannelIndex: Int?
        var soloInstrumentIndex: Int?
        var soloSampleIndex: Int?
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
            if argument == "--auto-headroom" {
                if !seen.insert(argument).inserted {
                    throw RenderToolError.duplicateArgument(argument)
                }
                autoHeadroom = true
                index += 1
                continue
            }
            if argument == "--until-song-end" {
                if !seen.insert(argument).inserted {
                    throw RenderToolError.duplicateArgument(argument)
                }
                untilSongEnd = true
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
            case "--effect-coverage-json":
                effectCoverageJSONPath = value
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
            case "--tail-seconds":
                tailSeconds = try parseNonNegativeDouble(value, name: argument)
            case "--window-rows":
                windowRows = try parseWindowRows(value, name: argument)
            case "--gain":
                gain = try parseExportGain(value, name: argument)
            case "--headroom-db":
                headroomDB = try parseHeadroomDB(value, name: argument)
            case "--solo-channel":
                soloChannelIndex = try parseNonNegativeInt(value, name: argument)
            case "--solo-instrument":
                soloInstrumentIndex = try parsePositiveInt(value, name: argument)
            case "--solo-sample":
                let soloSample = try parseSoloSample(value, name: argument)
                soloInstrumentIndex = soloSample.instrumentIndex
                soloSampleIndex = soloSample.sampleIndex
            default:
                throw RenderToolError.unknownArgument(argument)
            }
            index += 1
        }

        if rows != nil && seconds != nil {
            throw RenderToolError.mutuallyExclusive("--rows", "--seconds")
        }
        if untilSongEnd && rows != nil {
            throw RenderToolError.mutuallyExclusive("--until-song-end", "--rows")
        }
        if untilSongEnd && seconds != nil {
            throw RenderToolError.mutuallyExclusive("--until-song-end", "--seconds")
        }
        if untilSongEnd && maxFrames != nil {
            throw RenderToolError.mutuallyExclusive("--until-song-end", "--max-frames")
        }
        if tailSeconds != nil && !untilSongEnd {
            throw RenderToolError.invalidRenderLimit("--tail-seconds may only be used with --until-song-end.")
        }
        if maxFrames != nil && seconds != nil {
            throw RenderToolError.mutuallyExclusive("--max-frames", "--seconds")
        }
        if gain != nil && headroomDB != nil {
            throw RenderToolError.mutuallyExclusive("--gain", "--headroom-db")
        }
        if autoHeadroom && gain != nil {
            throw RenderToolError.mutuallyExclusive("--auto-headroom", "--gain")
        }
        if autoHeadroom && headroomDB != nil {
            throw RenderToolError.mutuallyExclusive("--auto-headroom", "--headroom-db")
        }
        if seen.contains("--solo-instrument") && seen.contains("--solo-sample") {
            throw RenderToolError.mutuallyExclusive("--solo-instrument", "--solo-sample")
        }
        try validateExplicitRenderLimit(
            maxFrames: maxFrames,
            seconds: seconds,
            sampleRate: sampleRate,
            allowLongRender: allowLongRender
        )
        let isolationFilter = PlaybackSongRenderIsolationFilter(
            soloChannelIndex: soloChannelIndex,
            soloInstrumentIndex: soloInstrumentIndex,
            soloSampleIndex: soloSampleIndex
        )

        return RenderToolArguments(
            inputPath: try required(inputPath, "--input"),
            outputPath: try required(outputPath, "--output"),
            diagnosticsJSONPath: diagnosticsJSONPath,
            effectCoverageJSONPath: effectCoverageJSONPath,
            order: try required(order, "--order"),
            orderCount: orderCount,
            rows: rows,
            sampleRate: sampleRate,
            maxFrames: maxFrames,
            seconds: seconds,
            untilSongEnd: untilSongEnd,
            tailSeconds: tailSeconds,
            windowRows: windowRows,
            allowLongRender: allowLongRender,
            progress: progress,
            gain: gain,
            headroomDB: headroomDB,
            autoHeadroom: autoHeadroom,
            isolationFilter: isolationFilter
        )
    }

    var usesDefaultRenderClamp: Bool {
        maxFrames == nil && seconds == nil && !untilSongEnd && rows == nil
    }

    var renderDurationMode: RenderDurationMode {
        if untilSongEnd {
            return .untilSongEnd
        }
        if seconds != nil {
            return .fixedSeconds
        }
        if maxFrames != nil {
            return .maxFrames
        }
        if rows != nil {
            return .fixedRows
        }
        return .defaultSafetyClamp
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

    var exportPolicy: MixerWAVExportPolicy {
        if let headroomDB {
            return MixerWAVExportPolicy(headroomDB: headroomDB)
        }
        if let gain {
            return MixerWAVExportPolicy(gain: Float(gain))
        }
        return .unity
    }

    func exportPolicy(for block: MixerRenderBlock) -> MixerWAVExportPolicy {
        autoHeadroom ? MixerWAVExportPolicy.autoHeadroom(for: block) : exportPolicy
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

    private static func parseNonNegativeInt(_ value: String, name: String) throws -> Int {
        let parsed = try parseInt(value, name: name)
        guard parsed >= 0 else {
            throw RenderToolError.invalidInteger(name: name, value: value)
        }
        return parsed
    }

    private static func parseSoloSample(
        _ value: String,
        name: String
    ) throws -> (instrumentIndex: Int, sampleIndex: Int) {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw RenderToolError.invalidIsolationFilter("\(name) must use instrument:sample, for example 23:0.")
        }
        let instrumentIndex = try parsePositiveInt(String(parts[0]), name: name)
        let sampleIndex = try parseNonNegativeInt(String(parts[1]), name: name)
        return (instrumentIndex, sampleIndex)
    }

    private static func parsePositiveDouble(_ value: String, name: String) throws -> Double {
        let parsed = try parseDouble(value, name: name)
        guard parsed > 0 else {
            throw RenderToolError.invalidDouble(name: name, value: value)
        }
        return parsed
    }

    private static func parseNonNegativeDouble(_ value: String, name: String) throws -> Double {
        let parsed = try parseDouble(value, name: name)
        guard parsed >= 0 else {
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

    private static func parseExportGain(_ value: String, name: String) throws -> Double {
        let parsed = try parseDouble(value, name: name)
        guard parsed > 0,
              parsed <= Double(Float.greatestFiniteMagnitude) else {
            throw RenderToolError.invalidDouble(name: name, value: value)
        }
        return parsed
    }

    private static func parseHeadroomDB(_ value: String, name: String) throws -> Double {
        let parsed = try parseDouble(value, name: name)
        guard parsed <= 0 else {
            throw RenderToolError.invalidExportGainPolicy("Headroom dB must be zero or negative; got \(value).")
        }
        let gain = Float(pow(10.0, parsed / 20.0))
        guard gain.isFinite, gain > 0 else {
            throw RenderToolError.invalidExportGainPolicy("Headroom dB is too low to produce a nonzero export gain; got \(value).")
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
        let effectCoverageURL = arguments.effectCoverageJSONPath.map { URL(fileURLWithPath: $0).standardizedFileURL }

        try validateInput(inputURL)
        try validateOutput(outputURL)
        if let diagnosticsURL {
            try validateDiagnosticsOutput(diagnosticsURL)
        }
        if let effectCoverageURL {
            try validateDiagnosticsOutput(effectCoverageURL)
        }

        emitProgress("loading module", arguments: arguments)
        let metadata = try ModuleMetadataLoader().load(fromPath: inputURL.path)
        emitProgress("building playback song", arguments: arguments)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: inputURL.path)
        try validateOrderRange(start: arguments.order, count: arguments.orderCount, orderTotal: song.orders.count)

        let config = MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: MixerRenderConfig.defaultChannelCount)
        let durationDiagnostics = try renderDurationDiagnostics(song: song, arguments: arguments, config: config)
        let request = try renderRequest(song: song, arguments: arguments, config: config)
        let renderer = PlaybackSongOfflineRenderer(maximumFrameCount: request.maximumFrameCount)
        emitProgress("render started", arguments: arguments)
        emitProgress(renderCapProgressLine(for: request, durationDiagnostics: durationDiagnostics), arguments: arguments)
        let result = try renderAndExportWAV(
            request,
            to: outputURL,
            renderer: renderer,
            arguments: arguments,
            startedAt: start
        )
        if let diagnosticsURL {
            emitProgress("writing diagnostics JSON", arguments: arguments)
            try PlaybackSongDiagnosticsJSONExporter.write(result, to: diagnosticsURL, renderDuration: durationDiagnostics)
        }
        if let effectCoverageURL {
            emitProgress("writing effect coverage JSON", arguments: arguments)
            try PlaybackSongDiagnosticsJSONExporter.writeEffectCoverage(result, to: effectCoverageURL, renderDuration: durationDiagnostics)
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
            emitProgress(wavWritingProgressLine(arguments: arguments), arguments: arguments)
            let exportPolicy = arguments.exportPolicy(for: result.block)
            let diagnostics = try MixerWAVExporter.writePCM16WAV(
                from: result.block,
                to: outputURL,
                exportPolicy: exportPolicy
            )
            emitProgress("writing WAV completed", arguments: arguments)
            return result.replacingExportDiagnostics(diagnostics)
        }
        let result = renderer.render(request)
        let exportPolicy = arguments.exportPolicy(for: result.block)
        let diagnostics = try MixerWAVExporter.writePCM16WAV(
            from: result.block,
            to: outputURL,
            exportPolicy: exportPolicy
        )
        return result.replacingExportDiagnostics(diagnostics)
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
        emitProgress(wavWritingProgressLine(arguments: arguments), arguments: arguments)
        let exportPolicy = arguments.exportPolicy(for: result.block)
        let diagnostics = try MixerWAVExporter.writePCM16WAV(
            from: result.block,
            to: outputURL,
            exportPolicy: exportPolicy
        )
        emitProgress("writing WAV completed", arguments: arguments)
        return result.replacingExportDiagnostics(diagnostics)
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

    func renderCapProgressLine(
        for request: PlaybackSongOfflineRenderRequest,
        durationDiagnostics: RenderDurationDiagnostics
    ) -> String {
        if durationDiagnostics.mode == .untilSongEnd {
            return String(
                format: "render duration mode: %@; calculated song-end: %@ frames; tail: %.3f seconds (%d frames); effective frame cap: %d frames (%.3f seconds)",
                durationDiagnostics.mode.summaryName,
                durationDiagnostics.calculatedSongEndFrames.map(String.init) ?? "not calculated",
                durationDiagnostics.tailSeconds,
                durationDiagnostics.tailFrames,
                request.maximumFrameCount,
                durationDiagnostics.effectiveDurationSeconds
            )
        }
        return String(
            format: "render duration mode: %@; effective frame cap: %d frames (%.3f seconds)",
            durationDiagnostics.mode.summaryName,
            request.maximumFrameCount,
            durationDiagnostics.effectiveDurationSeconds
        )
    }

    func wavWritingProgressLine(arguments: RenderToolArguments) -> String {
        if arguments.autoHeadroom {
            return "writing WAV (auto-headroom)"
        }
        return String(format: "writing WAV (export gain %.6f)", arguments.exportPolicy.gain)
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
    ) throws -> PlaybackSongOfflineRenderRequest {
        let durationDiagnostics = try renderDurationDiagnostics(song: song, arguments: arguments, config: config)
        let maximumFrameCount = max(0, durationDiagnostics.effectiveFrameCap)
        if arguments.untilSongEnd {
            return PlaybackSongOfflineRenderRequest(
                song: song,
                startOrderIndex: arguments.order,
                orderCount: arguments.orderCount,
                config: config,
                frames: durationDiagnostics.effectiveFrameCap,
                maximumFrameCount: maximumFrameCount,
                isolationFilter: arguments.isolationFilter
            )
        }
        if let rows = arguments.rows {
            return PlaybackSongOfflineRenderRequest(
                song: song,
                startOrderIndex: arguments.order,
                orderCount: arguments.orderCount,
                config: config,
                rows: rows,
                maximumFrameCount: maximumFrameCount,
                isolationFilter: arguments.isolationFilter
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
            maximumFrameCount: maximumFrameCount,
            isolationFilter: arguments.isolationFilter
        )
    }

    func renderDurationDiagnostics(
        song: PlaybackSong,
        arguments: RenderToolArguments,
        config: MixerRenderConfig
    ) throws -> RenderDurationDiagnostics {
        let mode = arguments.renderDurationMode
        let calculatedSongEndFrames: Int?
        let tailSeconds: Double
        let tailFrames: Int
        let effectiveFrameCap: Int

        if arguments.untilSongEnd {
            let timingPlan = PlaybackSongFxxTimingPlanner.plan(
                song,
                startOrderIndex: arguments.order,
                orderCount: arguments.orderCount,
                sampleRate: config.sampleRate
            )
            let songEndFrames = timingPlan.frameFor(row: timingPlan.rowTimings.count, tick: 0)
            let requestedTailSeconds = arguments.tailSeconds ?? 0
            let requestedTailFrames = Self.frameCountAllowingZero(seconds: requestedTailSeconds, sampleRate: config.sampleRate)
            let (combinedFrames, overflow) = songEndFrames.addingReportingOverflow(requestedTailFrames)
            guard !overflow else {
                throw RenderToolError.invalidRenderLimit("Calculated song-end plus tail exceeds integer bounds.")
            }
            calculatedSongEndFrames = songEndFrames
            tailSeconds = requestedTailSeconds
            tailFrames = requestedTailFrames
            effectiveFrameCap = combinedFrames
        } else {
            calculatedSongEndFrames = nil
            tailSeconds = 0
            tailFrames = 0
            effectiveFrameCap = arguments.effectiveFrameCap(sampleRate: config.sampleRate)
        }

        try validateRenderLimit(
            frames: effectiveFrameCap,
            allowLongRender: arguments.allowLongRender
        )
        return RenderDurationDiagnostics(
            mode: mode,
            calculatedSongEndFrames: calculatedSongEndFrames,
            tailSeconds: tailSeconds,
            tailFrames: tailFrames,
            effectiveFrameCap: effectiveFrameCap,
            effectiveDurationSeconds: config.sampleRate > 0 ? Double(effectiveFrameCap) / config.sampleRate : 0
        )
    }

    private func validateRenderLimit(frames: Int, allowLongRender: Bool) throws {
        guard frames > 0 else {
            throw RenderToolError.invalidRenderLimit("Render duration is too small to produce at least one frame.")
        }
        guard frames <= Self.absoluteMaximumFrameCount else {
            throw RenderToolError.invalidRenderLimit(
                "Requested render cap \(frames) frames exceeds the helper's hard safety limit \(Self.absoluteMaximumFrameCount) frames."
            )
        }
        let defaultLimit = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount
        if frames > defaultLimit, !allowLongRender {
            throw RenderToolError.longRenderRequiresAllowLongRender(frames: frames, defaultLimit: defaultLimit)
        }
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

    static func frameCountAllowingZero(seconds: Double, sampleRate: Double) -> Int {
        guard seconds.isFinite, seconds >= 0, sampleRate.isFinite, sampleRate > 0 else {
            return 0
        }
        guard seconds > 0 else {
            return 0
        }
        return frameCount(seconds: seconds, sampleRate: sampleRate)
    }
}

enum PlaybackSongDiagnosticsJSONExporter {
    static func write(
        _ result: PlaybackSongOfflineRenderResult,
        to url: URL,
        renderDuration: RenderDurationDiagnostics? = nil
    ) throws {
        var data = try JSONSerialization.data(
            withJSONObject: jsonObject(from: result, renderDuration: renderDuration),
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(UInt8(0x0A))
        try data.write(to: url, options: [])
    }

    static func writeEffectCoverage(
        _ result: PlaybackSongOfflineRenderResult,
        to url: URL,
        renderDuration: RenderDurationDiagnostics? = nil
    ) throws {
        try Data().write(to: url, options: [])
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        let diagnostics = result.diagnostics
        var firstKey = true
        writeString("{\n", to: handle)
        try writeJSONKey("schema_version", value: 1, firstKey: &firstKey, to: handle)
        try writeJSONKey("tool", value: "vtx_render_bounded_xm_effect_coverage", firstKey: &firstKey, to: handle)
        try writeJSONKey("local_only", value: true, firstKey: &firstKey, to: handle)
        try writeJSONKey(
            "notes",
            value: [
                "Compact local effect coverage diagnostics only.",
                "Generated diagnostics are local artifacts and must not be committed.",
            ],
            firstKey: &firstKey,
            to: handle
        )
        try writeJSONKey(
            "render",
            value: effectCoverageRenderJSON(from: result, renderDuration: renderDuration),
            firstKey: &firstKey,
            to: handle
        )
        try writeJSONArray("pattern_traversal_timing_effects", diagnostics.effectCommandDiagnostics, firstKey: &firstKey, to: handle, transform: effectCommandCoverageJSON)
        try writeJSONArray("volume_column_mappings", diagnostics.volumeColumnMappings, firstKey: &firstKey, to: handle, transform: volumeColumnMappingCoverageJSON)
        try writeJSONArray("sample_offset_effects", diagnostics.sampleOffsetEffects, firstKey: &firstKey, to: handle, transform: sampleOffsetCoverageJSON)
        try writeJSONArray("set_finetune_effects", diagnostics.setFinetuneEffects, firstKey: &firstKey, to: handle, transform: setFinetuneCoverageJSON)
        try writeJSONArray("note_cut_effects", diagnostics.noteCutEffects, firstKey: &firstKey, to: handle, transform: noteCutCoverageJSON)
        try writeJSONArray("note_delay_effects", diagnostics.noteDelayEffects, firstKey: &firstKey, to: handle, transform: noteDelayCoverageJSON)
        try writeJSONArray("retrigger_effects", diagnostics.retriggerEffects, firstKey: &firstKey, to: handle, transform: retriggerCoverageJSON)
        try writeJSONArray("arpeggio_effects", diagnostics.arpeggioEffects, firstKey: &firstKey, to: handle, transform: arpeggioCoverageJSON)
        try writeJSONArray("tone_portamento_effects", diagnostics.tonePortamentoEffects, firstKey: &firstKey, to: handle, transform: tonePortamentoCoverageJSON)
        try writeJSONArray("portamento_slide_effects", diagnostics.portamentoSlideEffects, firstKey: &firstKey, to: handle, transform: portamentoSlideCoverageJSON)
        try writeJSONArray("fine_portamento_up_effects", diagnostics.finePortamentoUpEffects, firstKey: &firstKey, to: handle, transform: finePortamentoUpCoverageJSON)
        try writeJSONArray("fine_portamento_down_effects", diagnostics.finePortamentoDownEffects, firstKey: &firstKey, to: handle, transform: finePortamentoDownCoverageJSON)
        try writeJSONArray("vibrato_control_effects", diagnostics.vibratoControlEffects, firstKey: &firstKey, to: handle, transform: vibratoControlCoverageJSON)
        try writeJSONArray("vibrato_effects", diagnostics.vibratoEffects, firstKey: &firstKey, to: handle, transform: vibratoCoverageJSON)
        try writeJSONArray("key_off_events", diagnostics.keyOffEvents, firstKey: &firstKey, to: handle, transform: keyOffEventJSON)
        try writeJSONArray("deferred_fields", diagnostics.deferredCellFields, firstKey: &firstKey, to: handle, transform: deferredFieldCoverageJSON)
        writeString("\n}\n", to: handle)
    }

    private static func effectCoverageRenderJSON(
        from result: PlaybackSongOfflineRenderResult,
        renderDuration: RenderDurationDiagnostics? = nil
    ) -> [String: Any] {
        let diagnostics = result.diagnostics
        let renderDuration = renderDuration ?? RenderDurationDiagnostics.fallback(from: result)
        return [
            "requested_start_order_index": diagnostics.requestedStartOrderIndex,
            "requested_order_count": diagnostics.requestedOrderCount,
            "sample_rate": diagnostics.sampleRate,
            "render_isolation": renderIsolationJSON(from: result),
            "render_duration_mode": renderDuration.mode.rawValue,
            "effective_frame_cap": renderDuration.effectiveFrameCap,
            "effective_duration_seconds": renderDuration.effectiveDurationSeconds,
            "requested_frame_count": result.requestedFrameCount,
            "rendered_frame_count": result.renderedFrameCount,
            "maximum_frame_count": result.maximumFrameCount,
            "was_frame_count_bounded": result.wasFrameCountBounded,
            "uses_linear_frequency_table": diagnostics.usesLinearFrequencyTable,
            "synthetic_row_count": diagnostics.syntheticRowCount,
        ]
    }

    private static func effectCommandCoverageJSON(
        _ diagnostic: PlaybackSongSyntheticEffectCommandDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": effectCommandStatusName(diagnostic.status),
            "current_status": effectCommandStatusName(diagnostic.status),
        ]
    }

    private static func baseEffectCoverageJSON(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticTick: Int,
        effectType: UInt8,
        effectParam: UInt8,
        status: String,
        applied: Bool,
        deferred: Bool,
        ignoredAsNoOp: Bool
    ) -> [String: Any] {
        [
            "source": positionJSON(source),
            "channel_index": channelIndex,
            "synthetic_tick": syntheticTick,
            "effect_type": Int(effectType),
            "effect_param": Int(effectParam),
            "status": status,
            "current_status": status,
            "applied": applied,
            "deferred": deferred,
            "ignored_as_no_op": ignoredAsNoOp,
        ]
    }

    private static func sampleOffsetCoverageJSON(_ diagnostic: PlaybackSongSyntheticSampleOffsetDiagnostic) -> [String: Any] {
        var object = baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: sampleOffsetStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
        object["effect_memory_reused"] = diagnostic.effectMemoryReused
        object["effect_memory_missing"] = diagnostic.effectMemoryMissing
        object["effect_memory_deferred"] = diagnostic.effectMemoryDeferred
        object["memory_unavailable_reason"] = diagnostic.memoryUnavailableReason.map { $0 as Any } ?? NSNull()
        return object
    }

    private static func setFinetuneCoverageJSON(_ diagnostic: PlaybackSongSyntheticSetFinetuneDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: setFinetuneStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func noteCutCoverageJSON(_ diagnostic: PlaybackSongSyntheticNoteCutDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: noteCutStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func noteDelayCoverageJSON(_ diagnostic: PlaybackSongSyntheticNoteDelayDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: noteDelayStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func retriggerCoverageJSON(_ diagnostic: PlaybackSongSyntheticRetriggerDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: retriggerStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func arpeggioCoverageJSON(_ diagnostic: PlaybackSongSyntheticArpeggioDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: arpeggioStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func tonePortamentoCoverageJSON(_ diagnostic: PlaybackSongSyntheticTonePortamentoDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: tonePortamentoStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func portamentoSlideCoverageJSON(_ diagnostic: PlaybackSongSyntheticPortamentoSlideDiagnostic) -> [String: Any] {
        var object = baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: portamentoSlideStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
        object["effect_memory_reused"] = diagnostic.effectMemoryReused
        object["effect_memory_missing"] = diagnostic.effectMemoryMissing
        object["effect_memory_deferred"] = diagnostic.effectMemoryDeferred
        object["memory_unavailable_reason"] = diagnostic.memoryUnavailableReason.map { $0 as Any } ?? NSNull()
        return object
    }

    private static func finePortamentoUpCoverageJSON(_ diagnostic: PlaybackSongSyntheticFinePortamentoUpDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: finePortamentoUpStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func finePortamentoDownCoverageJSON(_ diagnostic: PlaybackSongSyntheticFinePortamentoDownDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: finePortamentoDownStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func vibratoControlCoverageJSON(_ diagnostic: PlaybackSongSyntheticVibratoControlDiagnostic) -> [String: Any] {
        baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: vibratoControlStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
    }

    private static func vibratoCoverageJSON(_ diagnostic: PlaybackSongSyntheticVibratoDiagnostic) -> [String: Any] {
        var object = baseEffectCoverageJSON(
            source: diagnostic.source,
            channelIndex: diagnostic.channelIndex,
            syntheticTick: diagnostic.syntheticTick,
            effectType: diagnostic.effectType,
            effectParam: diagnostic.effectParam,
            status: vibratoStatusName(diagnostic.status),
            applied: diagnostic.applied,
            deferred: diagnostic.deferred,
            ignoredAsNoOp: diagnostic.ignoredAsNoOp
        )
        object["effect_memory_reused"] = diagnostic.effectMemoryReused
        object["effect_memory_missing"] = diagnostic.effectMemoryMissing
        object["effect_memory_deferred"] = diagnostic.effectMemoryDeferred
        object["memory_unavailable_reason"] = diagnostic.memoryUnavailableReason.map { $0 as Any } ?? NSNull()
        return object
    }

    private static func volumeColumnMappingCoverageJSON(_ mapping: PlaybackSongSyntheticVolumeColumnMapping) -> [String: Any] {
        [
            "source": positionJSON(mapping.source),
            "channel_index": mapping.channelIndex,
            "synthetic_tick": mapping.syntheticTick,
            "volume_column": volumeColumnCoverageJSON(mapping.volumeColumn),
        ]
    }

    private static func volumeColumnCoverageJSON(_ diagnostic: PlaybackSongSyntheticVolumeColumnDiagnostic) -> [String: Any] {
        [
            "raw_value": Int(diagnostic.rawValue),
            "command": volumeCommandJSON(diagnostic.command),
            "classification": volumeColumnClassificationName(diagnostic.classification),
            "applied": diagnostic.applied,
            "ignored_as_empty_or_no_op": diagnostic.ignoredAsEmptyOrNoOp,
            "deferred": diagnostic.deferred,
        ]
    }

    private static func deferredFieldCoverageJSON(_ field: PlaybackSongSyntheticDeferredCellField) -> [String: Any] {
        [
            "source": positionJSON(field.source),
            "channel_index": field.channelIndex,
            "volume_column_raw": Int(field.volumeColumn),
            "volume_column": volumeColumnCoverageJSON(field.volumeColumnDiagnostic),
            "field": deferredFieldName(field.field),
        ]
    }

    private static func writeJSONKey(
        _ key: String,
        value: Any,
        firstKey: inout Bool,
        to handle: FileHandle
    ) throws {
        try writeKeyPrefix(key, firstKey: &firstKey, to: handle)
        try writeJSONValue(value, to: handle)
    }

    private static func writeJSONArray<Element>(
        _ key: String,
        _ values: [Element],
        firstKey: inout Bool,
        to handle: FileHandle,
        transform: (Element) -> [String: Any]
    ) throws {
        try writeKeyPrefix(key, firstKey: &firstKey, to: handle)
        writeString("[", to: handle)
        for (index, value) in values.enumerated() {
            if index > 0 {
                writeString(",", to: handle)
            }
            try writeJSONValue(transform(value), to: handle)
        }
        writeString("]", to: handle)
    }

    private static func writeKeyPrefix(
        _ key: String,
        firstKey: inout Bool,
        to handle: FileHandle
    ) throws {
        if firstKey {
            firstKey = false
        } else {
            writeString(",\n", to: handle)
        }
        try writeJSONValue(key, to: handle)
        writeString(":", to: handle)
    }

    private static func writeJSONValue(_ value: Any, to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        handle.write(data)
    }

    private static func writeString(_ value: String, to handle: FileHandle) {
        handle.write(Data(value.utf8))
    }

    static func jsonObject(
        from result: PlaybackSongOfflineRenderResult,
        renderDuration: RenderDurationDiagnostics? = nil
    ) -> [String: Any] {
        let diagnostics = result.diagnostics
        let exportDiagnostics = exportDiagnostics(from: result)
        let renderDuration = renderDuration ?? RenderDurationDiagnostics.fallback(from: result)
        let gxxEffectDiagnostics = diagnostics.effectCommandDiagnostics.filter(\.isGxxSetGlobalVolume)
        let gxxAppliedCount = gxxEffectDiagnostics.filter { $0.status == .applied }.count
        let gxxDeferredCount = gxxEffectDiagnostics.filter { $0.status == .deferredUnsupported }.count
        let hxyEffectDiagnostics = diagnostics.effectCommandDiagnostics.filter(\.isHxyGlobalVolumeSlide)
        let hxyAppliedCount = hxyEffectDiagnostics.filter { $0.status == .applied }.count
        let hxyIgnoredNoOpCount = hxyEffectDiagnostics.filter { $0.status == .ignoredNoOp }.count
        let hxyDeferredCount = hxyEffectDiagnostics.filter { $0.status == .deferredUnsupported }.count
        let pitchModulationSummary = pitchModulationDeferredEffectSummaryJSON(diagnostics)
        let arpeggioAppliedCount = diagnostics.arpeggioEffects.filter(\.applied).count
        let arpeggioNoActiveVoiceCount = diagnostics.arpeggioEffects.filter { $0.status == .noActiveVoice }.count
        let arpeggioDeferredCount = diagnostics.arpeggioEffects.filter(\.deferred).count
        let arpeggioScheduledStepUpdateCount = diagnostics.arpeggioEffects.map(\.stepUpdates.count).reduce(0, +)
        let tonePortamento3xxEffectCount = diagnostics.tonePortamentoEffectCount
        let tonePortamento3xxAppliedCount = diagnostics.tonePortamentoEffects.filter(\.applied).count
        let tonePortamento3xxNoActiveVoiceCount = diagnostics.tonePortamentoEffects.filter { $0.status == .noActiveVoice }.count
        let tonePortamento3xxNoTargetCount = diagnostics.tonePortamentoEffects.filter { $0.status == .noTarget }.count
        let tonePortamento3xxDeferredCount = diagnostics.tonePortamentoEffects.filter(\.deferred).count
        let portamentoUpEffects = diagnostics.portamentoSlideEffects.filter { $0.direction == .up }
        let portamentoDownEffects = diagnostics.portamentoSlideEffects.filter { $0.direction == .down }
        let portamentoSlideAppliedCount = diagnostics.portamentoSlideEffects.filter(\.applied).count
        let portamentoSlideNoActiveVoiceCount = diagnostics.portamentoSlideEffects.filter { $0.status == .noActiveVoice }.count
        let portamentoSlideZeroParamCount = diagnostics.portamentoSlideEffects.filter { $0.status == .zeroParamEffectMemoryDeferred }.count
        let portamentoSlideDeferredCount = diagnostics.portamentoSlideEffects.filter(\.deferred).count
        let portamentoUpMemoryReusedCount = portamentoUpEffects.filter { $0.applied && $0.effectMemoryReused }.count
        let portamentoDownMemoryReusedCount = portamentoDownEffects.filter { $0.applied && $0.effectMemoryReused }.count
        let portamentoUpMemoryMissingCount = portamentoUpEffects.filter(\.effectMemoryMissing).count
        let portamentoDownMemoryMissingCount = portamentoDownEffects.filter(\.effectMemoryMissing).count
        let portamentoSlideMemoryMissingCount = diagnostics.portamentoSlideEffects.filter(\.effectMemoryMissing).count
        let portamentoSlideScheduledStepUpdateCount = diagnostics.portamentoSlideEffects.map(\.stepUpdates.count).reduce(0, +)
        let finePortamentoUpAppliedCount = diagnostics.finePortamentoUpEffects.filter(\.applied).count
        let finePortamentoUpNoActiveVoiceCount = diagnostics.finePortamentoUpEffects.filter { $0.status == .noActiveVoice }.count
        let finePortamentoUpZeroAmountCount = diagnostics.finePortamentoUpEffects.filter { $0.status == .zeroAmountEffectMemoryDeferred }.count
        let finePortamentoUpDeferredCount = diagnostics.finePortamentoUpEffects.filter(\.deferred).count
        let finePortamentoUpScheduledStepUpdateCount = diagnostics.finePortamentoUpEffects.map(\.stepUpdates.count).reduce(0, +)
        let finePortamentoDownAppliedCount = diagnostics.finePortamentoDownEffects.filter(\.applied).count
        let finePortamentoDownNoActiveVoiceCount = diagnostics.finePortamentoDownEffects.filter { $0.status == .noActiveVoice }.count
        let finePortamentoDownZeroAmountCount = diagnostics.finePortamentoDownEffects.filter { $0.status == .zeroAmountEffectMemoryDeferred }.count
        let finePortamentoDownDeferredCount = diagnostics.finePortamentoDownEffects.filter(\.deferred).count
        let finePortamentoDownScheduledStepUpdateCount = diagnostics.finePortamentoDownEffects.map(\.stepUpdates.count).reduce(0, +)
        let setFinetuneAppliedCount = diagnostics.setFinetuneEffects.filter(\.applied).count
        let setFinetuneNoNoteDeferredCount = diagnostics.setFinetuneEffects.filter { $0.status == .noNoteDeferred }.count
        let setFinetuneNoActiveVoiceCount = diagnostics.setFinetuneEffects.filter { $0.status == .noActiveVoice }.count
        let setFinetuneDeferredCount = diagnostics.setFinetuneEffects.filter(\.deferred).count
        let vibratoControlStoredCount = diagnostics.vibratoControlEffects.filter(\.stored).count
        let vibratoControlUnsupportedCount = diagnostics.vibratoControlEffects.filter(\.unsupportedWaveform).count
        let vibratoControlDeferredCount = diagnostics.vibratoControlEffects.filter(\.deferred).count
        let vibrato4xyEffects = diagnostics.vibratoEffects.filter { $0.effectType == 0x04 }
        let vibrato6xyEffects = diagnostics.vibratoEffects.filter { $0.effectType == 0x06 }
        let vibratoAppliedCount = vibrato4xyEffects.filter(\.applied).count
        let vibratoNoActiveVoiceCount = vibrato4xyEffects.filter { $0.status == .noActiveVoice }.count
        let vibratoZeroParamCount = vibrato4xyEffects.filter { $0.status == .zeroParamEffectMemoryDeferred }.count
        let vibratoZeroNibbleCount = vibrato4xyEffects.filter { $0.status == .zeroSpeedOrDepthEffectMemoryDeferred }.count
        let vibratoDeferredCount = vibrato4xyEffects.filter(\.deferred).count
        let vibratoMemoryAppliedCount = vibrato4xyEffects.filter { $0.applied && $0.effectMemoryReused }.count
        let vibratoMemoryMissingCount = vibrato4xyEffects.filter(\.effectMemoryMissing).count
        let vibratoScheduledStepUpdateCount = vibrato4xyEffects.map(\.stepUpdates.count).reduce(0, +)
        let vibrato6xyAppliedCount = vibrato6xyEffects.filter(\.applied).count
        let vibrato6xyNoActiveVoiceCount = vibrato6xyEffects.filter { $0.status == .noActiveVoice }.count
        let vibrato6xyZeroParamCount = vibrato6xyEffects.filter { $0.status == .zeroParamEffectMemoryDeferred }.count
        let vibrato6xyZeroSpeedDepthCount = vibrato6xyEffects.filter { $0.status == .zeroSpeedOrDepthEffectMemoryDeferred }.count
        let vibrato6xyDeferredCount = vibrato6xyEffects.filter(\.deferred).count
        let vibrato6xyMemoryAppliedCount = vibrato6xyEffects.filter { $0.applied && $0.effectMemoryReused }.count
        let vibrato6xyMemoryMissingCount = vibrato6xyEffects.filter(\.effectMemoryMissing).count
        let vibrato6xyScheduledStepUpdateCount = vibrato6xyEffects.map(\.stepUpdates.count).reduce(0, +)
        let sampleOffset900MemoryAppliedCount = diagnostics.sampleOffsetEffects.filter {
            $0.effectType == 0x09 && $0.effectParam == 0 && $0.applied && $0.effectMemoryReused
        }.count
        let sampleOffset900MemoryMissingCount = diagnostics.sampleOffsetEffects.filter {
            $0.effectType == 0x09 && $0.effectParam == 0 && $0.effectMemoryMissing
        }.count
        let eaxFineVolumeSlides = diagnostics.voiceStateUpdates.filter(isEaxFineVolumeSlideUpdate)
        let ebxFineVolumeSlides = diagnostics.voiceStateUpdates.filter(isEbxFineVolumeSlideUpdate)
        let vibrato6xyVolumeSlides = diagnostics.voiceStateUpdates.filter(is6xyVolumeSlideUpdate)
        let axyEffectDiagnostics = diagnostics.effectCommandDiagnostics.filter(\.isAxyVolumeSlide)
        let axyVolumeSlides = diagnostics.voiceStateUpdates.filter(isAxyVolumeSlideUpdate)
        let axyAppliedCount = axyVolumeSlides.filter(\.applied).count
        let axyIgnoredNoOpCount = axyVolumeSlides.filter(\.ignoredAsNoOp).count
        let axyDeferredCount = axyVolumeSlides.filter(\.deferred).count
        let axyNoActiveVoiceCount = axyVolumeSlides.filter(isAxyVolumeSlideNoActiveVoice).count
        let axyScheduledGainUpdateCount = axyVolumeSlides.filter(isChangedGainStateUpdate).count
        let axyTickLevelUpdateCount = axyVolumeSlides.filter { $0.applied && $0.syntheticTick > 0 }.count
        let axyTick0SuppressedCount = axyEffectDiagnostics.filter {
            $0.status == .applied && $0.effectParam != 0
        }.count
        let axyMixedNibblePolicy = axyVolumeSlides.first {
            $0.volumeSlideBothNibblesNonzero == true
        }?.volumeSlidePolicy ?? "up_nibble_precedence_mikmod_observed"
        let eaxFineVolumeSlideAppliedCount = eaxFineVolumeSlides.filter(\.applied).count
        let ebxFineVolumeSlideAppliedCount = ebxFineVolumeSlides.filter(\.applied).count
        let eaxFineVolumeSlideNoActiveVoiceCount = eaxFineVolumeSlides.filter(isFineVolumeSlideNoActiveVoice).count
        let ebxFineVolumeSlideNoActiveVoiceCount = ebxFineVolumeSlides.filter(isFineVolumeSlideNoActiveVoice).count
        let eaxFineVolumeSlideZeroAmountCount = eaxFineVolumeSlides.filter(isFineVolumeSlideZeroAmountNoOp).count
        let ebxFineVolumeSlideZeroAmountCount = ebxFineVolumeSlides.filter(isFineVolumeSlideZeroAmountNoOp).count
        let eaxFineVolumeSlideDeferredCount = eaxFineVolumeSlides.filter(\.deferred).count
        let ebxFineVolumeSlideDeferredCount = ebxFineVolumeSlides.filter(\.deferred).count
        let eaxFineVolumeSlideScheduledGainUpdateCount = eaxFineVolumeSlides.filter(isChangedGainStateUpdate).count
        let ebxFineVolumeSlideScheduledGainUpdateCount = ebxFineVolumeSlides.filter(isChangedGainStateUpdate).count
        let vibrato6xyScheduledGainUpdateCount = vibrato6xyVolumeSlides.filter(isChangedGainStateUpdate).count
        let activeVoiceStateUpdateCount = diagnostics.voiceStateUpdates.filter(\.activeVoiceUpdated).count
        let gainPanUpdateCount = changedVoiceStateUpdateCount(diagnostics.voiceStateUpdates)
        let gainPanInterruptedRampCount = interruptedRampCount(diagnostics.voiceStateUpdates)
        let sameChannelVoiceLifetime = result.sameChannelVoiceLifetime
        let pitchModulationDeferredEffectCount = pitchModulationSummary["total_deferred_pitch_modulation_effect_count"] as? Int ?? 0
        let traversalSummary = diagnostics.traversalSummary
        let samplePCMStats = samplePCMStatsJSON(from: result.request.song)
        let notes = [
            "Approximate bounded adapter diagnostics only; not proof of reference correctness.",
            "Generated diagnostics are local artifacts and must not be committed.",
            "Offline C mixer rendering/export remains separate from CoreAudio runtime playback.",
            "C-backed offline sample stepping uses simple deterministic linear interpolation.",
            "Envelope sustain, loop, key-off, and fadeout are first-pass bounded offline approximations.",
            "Minimal 9xx sample offset is applied only in bounded offline adapter renders; 900 reuses prior nonzero 9xx per-channel memory when available and remains diagnosed as effect-memory-deferred/no-op when unavailable.",
            "Minimal ECx note cut and EDx note delay are applied only in bounded offline adapter renders.",
            "Minimal E9x retrigger is applied only in bounded offline adapter renders; E90 effect memory is not implemented.",
            "XM instrument sample-map/keymap selection is applied only in bounded offline adapter renders.",
            "Minimal 1xx/2xx portamento up/down and 3xx tone portamento are applied only in bounded offline adapter renders; 100/200 replay prior nonzero same-family per-channel memory when available, while missing memory remains diagnosed as effect-memory-deferred/no-op. 5xy and volume-column tone portamento remain deferred.",
            "Minimal 0xy arpeggio applies deterministic tick-level sample-step updates through the shared runtime/offline C mixer adapter path; 000 remains a no-op and arpeggio effect memory is intentionally deferred.",
            "Minimal E1x fine portamento up applies one deterministic row-level linear-period decrease through the shared runtime/offline sample-step path; E10 effect memory remains deferred.",
            "Minimal E2x fine portamento down applies one deterministic row-level linear-period increase through the shared runtime/offline sample-step path; E20 effect memory remains deferred.",
            "Minimal E5x set finetune is applied only for same-cell note triggers through the linear-frequency sample-step path; no-note/effect-memory and non-linear table cases remain deferred.",
            "Minimal E4x vibrato control stores deterministic sine/ramp/square/random waveform state for later 4xy/6xy vibrato; unsupported control values remain explicitly deferred and E4x emits no direct audio event.",
            "Minimal 4xy vibrato uses deterministic linear-period sample-step updates in the shared runtime/offline C mixer adapter path; 400 and single-zero nibbles reuse available per-channel vibrato memory, while unavailable memory and volume-column vibrato remain deferred.",
            "Minimal 6xy vibrato + volume slide reuses prior channel vibrato memory plus its existing row-level volume-slide/gain path; 600 can replay vibrato memory without volume-slide memory, while unavailable vibrato memory remains effect-memory-deferred/no-op.",
            "Minimal volume/panning state updates are applied for bounded offline empty-note and same-cell 3xx no-retrigger volume-column state commands plus Cxx/8xx and tick-level Axy effect-column commands where diagnosed as applied.",
            "Supported bounded/offline gain/pan update events use a fixed deterministic micro-ramp; ECx note cuts remain hard cuts.",
            "Minimal EAx/EBx fine volume slides are deterministic row-level channel-volume updates in the shared runtime/offline gain path; EA0/EB0 effect memory remains deferred/no-op.",
            "Minimal Gxx set-global-volume commands are row-level bounded offline adapter updates that clamp the XM global volume value to 0...64.",
            "Minimal Hxy global volume slides are row-level bounded offline adapter updates; H00 is a no-op and both-nibble parameters use the runtime-compatible up-nibble precedence policy.",
            "Focused traversal planning applies Dxx pattern break, Bxx position jump, and E6x pattern loop in the Swift adapter path; EEx pattern delay remains deferred.",
            "Dxx row targets use XM BCD decoding; invalid BCD targets are diagnosed and clamped safely.",
            "When Bxx and Dxx share a row, Bxx selects the target order and Dxx supplies the target row.",
            "E6x loop starts and loop counts are scoped per channel/order/pattern; missing loop starts are diagnosed without inventing a row-0 loop.",
            "Windowed renders are developer/offline helper renders only; practical active voice state is carried across fresh C mixer windows where supported.",
            "Export gain/headroom, including auto-headroom, is applied after Float32 offline rendering and before PCM16 conversion.",
            "Until-song-end duration is the bounded selected order-range end from the adapter timing model, not full FT2/OpenMPT song loop/restart parity.",
        ]
        let render: [String: Any] = [
                "requested_start_order_index": diagnostics.requestedStartOrderIndex,
                "requested_order_count": diagnostics.requestedOrderCount,
                "sample_rate": diagnostics.sampleRate,
                "channel_count": result.block.config.channelCount,
                "render_isolation": renderIsolationJSON(from: result),
                "isolation_enabled": result.request.isolationFilter?.isEnabled ?? false,
                "sample_interpolation": CSoftwareMixer.interpolationMode,
                "sample_interpolation_enabled": CSoftwareMixer.interpolationEnabled,
                "sample_interpolation_kernel": [
                    "kernel": CSoftwareMixer.interpolationKernel,
                    "source_index_policy": CSoftwareMixer.interpolationSourceIndexPolicy,
                    "fraction_policy": CSoftwareMixer.interpolationFractionPolicy,
                    "blend_formula": CSoftwareMixer.interpolationBlendFormula,
                    "sample_value_policy": CSoftwareMixer.interpolationSampleValuePolicy,
                    "sample_end_policy": CSoftwareMixer.interpolationEndPolicy,
                    "forward_loop_policy": CSoftwareMixer.interpolationForwardLoopPolicy,
                    "ping_pong_policy": CSoftwareMixer.interpolationPingPongPolicy,
                    "always_enabled": CSoftwareMixer.interpolationEnabled,
                    "point_sampling_fallback": CSoftwareMixer.interpolationPointSamplingFallback,
                ],
                "sample_step_precision_mode": CSoftwareMixer.sampleStepPrecisionMode,
                "gain_construction_policy": [
                    "sample_volume_source": "XM sample header volume normalized once as raw_volume / 64 into PlaybackSample.volume",
                    "sample_volume_raw_range": "0...64",
                    "channel_volume_range": "0...64",
                    "global_volume_range": "0...64",
                    "event_gain_formula": "sample_volume * (channel_volume / 64) * (global_volume / 64)",
                    "c_mixer_render_multiplier": "event_gain * volume_envelope * fadeout before panning",
                    "c_mixer_expected_gain_range": "finite non-negative Float32; bounded adapter clamps event gain to 0...1",
                    "normalization_notes": [
                        "sample volume is not divided by 64 again in the C mixer",
                        "volume envelopes and fadeout are separate C-side multipliers",
                    ],
                ],
                "render_duration_mode": renderDuration.mode.rawValue,
                "calculated_song_end_frames": nullableJSONValue(renderDuration.calculatedSongEndFrames),
                "tail_seconds": renderDuration.tailSeconds,
                "tail_frames": renderDuration.tailFrames,
                "effective_frame_cap": renderDuration.effectiveFrameCap,
                "effective_duration_seconds": renderDuration.effectiveDurationSeconds,
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
                "sample_pcm_stat_count": samplePCMStats.count,
                "ignored_cell_count": diagnostics.ignoredCellCount,
                "empty_or_skipped_row_count": diagnostics.emptyOrSkippedRowCount,
                "sample_offset_effect_count": diagnostics.sampleOffsetEffectCount,
                "sample_offset_900_memory_applied_count": sampleOffset900MemoryAppliedCount,
                "sample_offset_900_memory_missing_count": sampleOffset900MemoryMissingCount,
                "note_cut_effect_count": diagnostics.noteCutEffectCount,
                "note_delay_effect_count": diagnostics.noteDelayEffectCount,
                "retrigger_effect_count": diagnostics.retriggerEffectCount,
                "arpeggio_0xy_effect_count": diagnostics.arpeggioEffectCount,
                "arpeggio_0xy_detected_count": diagnostics.arpeggioEffectCount,
                "arpeggio_0xy_applied_count": arpeggioAppliedCount,
                "arpeggio_0xy_no_active_voice_count": arpeggioNoActiveVoiceCount,
                "arpeggio_0xy_deferred_count": arpeggioDeferredCount,
                "arpeggio_0xy_effect_memory_deferred_count": 0,
                "arpeggio_0xy_scheduled_sample_step_update_count": arpeggioScheduledStepUpdateCount,
                "tone_portamento_3xx_effect_count": tonePortamento3xxEffectCount,
                "tone_portamento_3xx_applied_count": tonePortamento3xxAppliedCount,
                "tone_portamento_3xx_no_active_voice_count": tonePortamento3xxNoActiveVoiceCount,
                "tone_portamento_3xx_no_target_count": tonePortamento3xxNoTargetCount,
                "tone_portamento_3xx_deferred_count": tonePortamento3xxDeferredCount,
                "portamento_1xx_effect_count": portamentoUpEffects.count,
                "portamento_1xx_applied_count": portamentoUpEffects.filter(\.applied).count,
                "portamento_1xx_no_active_voice_count": portamentoUpEffects.filter { $0.status == .noActiveVoice }.count,
                "portamento_1xx_zero_param_effect_memory_deferred_count": portamentoUpEffects.filter { $0.status == .zeroParamEffectMemoryDeferred }.count,
                "portamento_1xx_memory_reused_count": portamentoUpMemoryReusedCount,
                "portamento_1xx_memory_missing_count": portamentoUpMemoryMissingCount,
                "portamento_1xx_scheduled_sample_step_update_count": portamentoUpEffects.map(\.stepUpdates.count).reduce(0, +),
                "portamento_2xx_effect_count": portamentoDownEffects.count,
                "portamento_2xx_applied_count": portamentoDownEffects.filter(\.applied).count,
                "portamento_2xx_no_active_voice_count": portamentoDownEffects.filter { $0.status == .noActiveVoice }.count,
                "portamento_2xx_zero_param_effect_memory_deferred_count": portamentoDownEffects.filter { $0.status == .zeroParamEffectMemoryDeferred }.count,
                "portamento_2xx_memory_reused_count": portamentoDownMemoryReusedCount,
                "portamento_2xx_memory_missing_count": portamentoDownMemoryMissingCount,
                "portamento_2xx_scheduled_sample_step_update_count": portamentoDownEffects.map(\.stepUpdates.count).reduce(0, +),
                "portamento_slide_effect_count": diagnostics.portamentoSlideEffectCount,
                "portamento_slide_applied_count": portamentoSlideAppliedCount,
                "portamento_slide_no_active_voice_count": portamentoSlideNoActiveVoiceCount,
                "portamento_slide_zero_param_effect_memory_deferred_count": portamentoSlideZeroParamCount,
                "portamento_slide_deferred_count": portamentoSlideDeferredCount,
                "portamento_memory_missing_count": portamentoSlideMemoryMissingCount,
                "portamento_slide_scheduled_sample_step_update_count": portamentoSlideScheduledStepUpdateCount,
                "e1x_fine_portamento_up_effect_count": diagnostics.finePortamentoUpEffectCount,
                "e1x_fine_portamento_up_detected_count": diagnostics.finePortamentoUpEffectCount,
                "e1x_fine_portamento_up_applied_count": finePortamentoUpAppliedCount,
                "e1x_fine_portamento_up_no_active_voice_count": finePortamentoUpNoActiveVoiceCount,
                "e1x_fine_portamento_up_zero_amount_effect_memory_deferred_count": finePortamentoUpZeroAmountCount,
                "e1x_fine_portamento_up_deferred_count": finePortamentoUpDeferredCount,
                "e1x_fine_portamento_up_scheduled_sample_step_update_count": finePortamentoUpScheduledStepUpdateCount,
                "e2x_fine_portamento_down_effect_count": diagnostics.finePortamentoDownEffectCount,
                "e2x_fine_portamento_down_detected_count": diagnostics.finePortamentoDownEffectCount,
                "e2x_fine_portamento_down_applied_count": finePortamentoDownAppliedCount,
                "e2x_fine_portamento_down_no_active_voice_count": finePortamentoDownNoActiveVoiceCount,
                "e2x_fine_portamento_down_zero_amount_effect_memory_deferred_count": finePortamentoDownZeroAmountCount,
                "e2x_fine_portamento_down_deferred_count": finePortamentoDownDeferredCount,
                "e2x_fine_portamento_down_scheduled_sample_step_update_count": finePortamentoDownScheduledStepUpdateCount,
                "e5x_set_finetune_effect_count": diagnostics.setFinetuneEffectCount,
                "e5x_set_finetune_detected_count": diagnostics.setFinetuneEffectCount,
                "e5x_set_finetune_applied_count": setFinetuneAppliedCount,
                "e5x_set_finetune_no_note_deferred_count": setFinetuneNoNoteDeferredCount,
                "e5x_set_finetune_no_active_voice_count": setFinetuneNoActiveVoiceCount,
                "e5x_set_finetune_deferred_count": setFinetuneDeferredCount,
                "e4x_vibrato_control_effect_count": diagnostics.vibratoControlEffectCount,
                "e4x_vibrato_control_detected_count": diagnostics.vibratoControlEffectCount,
                "e4x_vibrato_control_stored_count": vibratoControlStoredCount,
                "e4x_vibrato_control_applied_count": vibratoControlStoredCount,
                "e4x_vibrato_control_unsupported_waveform_count": vibratoControlUnsupportedCount,
                "e4x_vibrato_control_deferred_count": vibratoControlDeferredCount,
                "vibrato_4xy_effect_count": vibrato4xyEffects.count,
                "vibrato_4xy_applied_count": vibratoAppliedCount,
                "vibrato_4xy_no_active_voice_count": vibratoNoActiveVoiceCount,
                "vibrato_4xy_zero_param_effect_memory_deferred_count": vibratoZeroParamCount,
                "vibrato_4xy_zero_speed_or_depth_effect_memory_deferred_count": vibratoZeroNibbleCount,
                "vibrato_4xy_deferred_count": vibratoDeferredCount,
                "vibrato_4xy_memory_applied_count": vibratoMemoryAppliedCount,
                "vibrato_4xy_memory_missing_count": vibratoMemoryMissingCount,
                "vibrato_4xy_scheduled_sample_step_update_count": vibratoScheduledStepUpdateCount,
                "vibrato_volume_slide_6xy_effect_count": vibrato6xyEffects.count,
                "vibrato_volume_slide_6xy_detected_count": vibrato6xyEffects.count,
                "vibrato_volume_slide_6xy_applied_count": vibrato6xyAppliedCount,
                "vibrato_volume_slide_6xy_no_active_voice_count": vibrato6xyNoActiveVoiceCount,
                "vibrato_volume_slide_6xy_zero_param_effect_memory_deferred_count": vibrato6xyZeroParamCount,
                "vibrato_volume_slide_6xy_zero_speed_or_depth_effect_memory_deferred_count": vibrato6xyZeroSpeedDepthCount,
                "vibrato_volume_slide_6xy_deferred_count": vibrato6xyDeferredCount,
                "vibrato_volume_slide_6xy_memory_applied_count": vibrato6xyMemoryAppliedCount,
                "vibrato_volume_slide_6xy_memory_missing_count": vibrato6xyMemoryMissingCount,
                "vibrato_volume_slide_6xy_scheduled_sample_step_update_count": vibrato6xyScheduledStepUpdateCount,
                "vibrato_volume_slide_6xy_scheduled_gain_update_count": vibrato6xyScheduledGainUpdateCount,
                "axy_volume_slide_effect_count": axyEffectDiagnostics.count,
                "axy_volume_slide_detected_count": axyEffectDiagnostics.count,
                "axy_volume_slide_applied_count": axyAppliedCount,
                "axy_volume_slide_ignored_no_op_count": axyIgnoredNoOpCount,
                "axy_volume_slide_no_active_voice_count": axyNoActiveVoiceCount,
                "axy_volume_slide_deferred_count": axyDeferredCount,
                "axy_volume_slide_scheduled_gain_update_count": axyScheduledGainUpdateCount,
                "axy_tick_level_updates": axyTickLevelUpdateCount,
                "axy_tick0_suppressed": axyTick0SuppressedCount,
                "axy_tick0_suppressed_count": axyTick0SuppressedCount,
                "axy_mixed_nibble_policy": axyMixedNibblePolicy,
                "eax_fine_volume_slide_up_effect_count": eaxFineVolumeSlides.count,
                "eax_fine_volume_slide_up_detected_count": eaxFineVolumeSlides.count,
                "eax_fine_volume_slide_up_applied_count": eaxFineVolumeSlideAppliedCount,
                "eax_fine_volume_slide_up_no_active_voice_count": eaxFineVolumeSlideNoActiveVoiceCount,
                "eax_fine_volume_slide_up_zero_amount_effect_memory_deferred_count": eaxFineVolumeSlideZeroAmountCount,
                "eax_fine_volume_slide_up_deferred_count": eaxFineVolumeSlideDeferredCount,
                "eax_fine_volume_slide_up_scheduled_gain_update_count": eaxFineVolumeSlideScheduledGainUpdateCount,
                "ebx_fine_volume_slide_down_effect_count": ebxFineVolumeSlides.count,
                "ebx_fine_volume_slide_down_detected_count": ebxFineVolumeSlides.count,
                "ebx_fine_volume_slide_down_applied_count": ebxFineVolumeSlideAppliedCount,
                "ebx_fine_volume_slide_down_no_active_voice_count": ebxFineVolumeSlideNoActiveVoiceCount,
                "ebx_fine_volume_slide_down_zero_amount_effect_memory_deferred_count": ebxFineVolumeSlideZeroAmountCount,
                "ebx_fine_volume_slide_down_deferred_count": ebxFineVolumeSlideDeferredCount,
                "ebx_fine_volume_slide_down_scheduled_gain_update_count": ebxFineVolumeSlideScheduledGainUpdateCount,
                "volume_panning_state_update_count": diagnostics.voiceStateUpdates.count,
                "active_voice_state_update_count": activeVoiceStateUpdateCount,
                "gain_pan_ramp_enabled": true,
                "gain_pan_ramp_frame_count": CSoftwareMixer.gainPanUpdateRampFrameCount,
                "gain_pan_update_count": gainPanUpdateCount,
                "gain_pan_ramped_update_count": gainPanUpdateCount,
                "gain_pan_interrupted_ramp_count": gainPanInterruptedRampCount,
                "same_channel_replacement_ramp_enabled": true,
                "same_channel_replacement_ramp_frame_count": sameChannelVoiceLifetime.replacementRampFrameCount,
                "same_channel_active_voice_count": sameChannelVoiceLifetime.sameChannelActiveVoiceCount,
                "same_channel_replacement_start_count": sameChannelVoiceLifetime.sameChannelReplacementStartCount,
                "same_channel_replacement_completion_count": sameChannelVoiceLifetime.sameChannelReplacementCompletionCount,
                "same_channel_voice_overlap_frames": sameChannelVoiceLifetime.sameChannelVoiceOverlapFrames,
                "max_voices_per_source_channel": intKeyedDictionaryJSON(sameChannelVoiceLifetime.maxVoicesPerSourceChannel),
                "old_voice_kept_reason_counts": sameChannelVoiceLifetime.oldVoiceKeptReasonCounts,
                "old_voice_ramp_duration_frames": sameChannelVoiceLifetime.oldVoiceRampDurationFrames,
                "window_boundary_prune_count": sameChannelVoiceLifetime.windowBoundaryPruneCount,
                "gxx_set_global_volume_detected_count": gxxEffectDiagnostics.count,
                "gxx_set_global_volume_applied_count": gxxAppliedCount,
                "gxx_set_global_volume_deferred_count": gxxDeferredCount,
                "hxy_global_volume_slide_detected_count": hxyEffectDiagnostics.count,
                "hxy_global_volume_slide_applied_count": hxyAppliedCount,
                "hxy_global_volume_slide_ignored_no_op_count": hxyIgnoredNoOpCount,
                "hxy_global_volume_slide_deferred_count": hxyDeferredCount,
                "pitch_modulation_deferred_effect_count": pitchModulationDeferredEffectCount,
                "traversal_hazard_count": diagnostics.traversalHazardSummary.totalTraversalHazards,
                "traversal_path_length": traversalSummary.pathLength,
                "traversal_stop_reason": traversalSummary.stopReason.rawValue,
                "traversal_guard_hit": traversalSummary.guardHit,
                "traversal_applied_count": traversalSummary.appliedTraversalCount,
                "traversal_dxx_detected_count": traversalSummary.dxxDetectedCount,
                "traversal_dxx_applied_count": traversalSummary.dxxAppliedCount,
                "traversal_dxx_invalid_target_count": traversalSummary.dxxInvalidTargetCount,
                "traversal_dxx_out_of_range_count": traversalSummary.dxxOutOfRangeCount,
                "traversal_bxx_detected_count": traversalSummary.bxxDetectedCount,
                "traversal_bxx_applied_count": traversalSummary.bxxAppliedCount,
                "traversal_bxx_out_of_range_count": traversalSummary.bxxOutOfRangeCount,
                "traversal_e6x_detected_count": traversalSummary.e6xDetectedCount,
                "traversal_e6x_loop_start_count": traversalSummary.e6xLoopStartCount,
                "traversal_e6x_loop_taken_count": traversalSummary.e6xLoopTakenCount,
                "traversal_e6x_missing_start_count": traversalSummary.e6xMissingStartCount,
                "traversal_e6x_loop_limit_hit_count": traversalSummary.e6xLoopLimitHitCount,
                "windowed_render_enabled": result.windowedRenderSummary != nil,
                "window_rows": nullableJSONValue(result.windowedRenderSummary?.windowRows),
                "window_count": result.windowedRenderSummary?.windowCount ?? 0,
                "auto_headroom_enabled": exportDiagnostics.autoHeadroomEnabled,
                "auto_headroom_safety_db": nullableJSONValue(exportDiagnostics.autoHeadroomSafetyDB),
                "export_gain": Double(exportDiagnostics.policy.gain),
                "export_headroom_db": nullableJSONValue(exportDiagnostics.policy.headroomDB),
                "pre_export_peak": Double(exportDiagnostics.preExportPeak),
                "pre_export_per_channel_peak": exportDiagnostics.preExportPerChannelPeak.map { Double($0) },
                "pre_export_overrange_sample_count": exportDiagnostics.preExportOverrangeSampleCount,
                "pre_export_rms": Double(exportDiagnostics.preExportRMS),
                "computed_export_gain": Double(exportDiagnostics.computedExportGain),
                "computed_headroom_db": exportDiagnostics.computedHeadroomDB,
                "post_gain_peak": Double(exportDiagnostics.postGainPeak),
                "post_gain_per_channel_peak": exportDiagnostics.postGainPerChannelPeak.map { Double($0) },
                "post_gain_rms": Double(exportDiagnostics.postGainRMS),
                "pcm16_clipping_count": exportDiagnostics.pcm16ClippingSampleCount,
                "pcm16_clipping_sample_count": exportDiagnostics.pcm16ClippingSampleCount,
                "clipping_detected": exportDiagnostics.clippingDetected,
                "clipping_recommendation": nullableJSONValue(exportDiagnostics.recommendation),
        ]
        return [
            "schema_version": 1,
            "tool": "vtx_render_bounded_xm",
            "local_only": true,
            "notes": notes,
            "render": render,
            "export_diagnostics": exportDiagnosticsJSON(exportDiagnostics),
            "windowed_render": windowedRenderJSON(from: result),
            "row_tick_frame_mapping_policy": rowTickFrameMappingPolicyJSON(),
            "event_application_timing_policy": eventApplicationTimingPolicyJSON(),
            "same_channel_voice_lifetime": sameChannelVoiceLifetimeJSON(sameChannelVoiceLifetime),
            "event_coverage": eventCoverageJSON(from: result),
            "traversal_hazard_summary": traversalHazardSummaryJSON(diagnostics.traversalHazardSummary),
            "traversal_summary": traversalSummaryJSON(traversalSummary),
            "traversal_effects": diagnostics.traversalDiagnostics.map(traversalDiagnosticJSON),
            "pattern_traversal_timing_effects": diagnostics.effectCommandDiagnostics.map(effectCommandDiagnosticJSON),
            "pitch_modulation_deferred_effect_summary": pitchModulationSummary,
            "pitch_modulation_deferred_effects": pitchModulationDeferredEffectsJSON(diagnostics),
            "orders": diagnostics.adaptedOrders.map(orderJSON),
            "row_mappings": diagnostics.rowMappings.map(rowMappingJSON),
            "row_timing": diagnostics.rowTiming.map { rowTimingJSON($0, sampleRate: diagnostics.sampleRate) },
            "timing_changes": diagnostics.timingChanges.map(timingChangeJSON),
            "row_diagnostics": diagnostics.rowDiagnostics.map(rowDiagnosticJSON),
            "sample_pcm_stats": samplePCMStats,
            "volume_column_mappings": diagnostics.volumeColumnMappings.map(volumeColumnMappingJSON),
            "volume_panning_state_update_summary": voiceStateUpdateSummaryJSON(diagnostics.voiceStateUpdates),
            "volume_panning_state_updates": diagnostics.voiceStateUpdates.map(voiceStateUpdateJSON),
            "sample_offset_effects": diagnostics.sampleOffsetEffects.map(sampleOffsetDiagnosticJSON),
            "set_finetune_effects": diagnostics.setFinetuneEffects.map(setFinetuneDiagnosticJSON),
            "note_cut_effects": diagnostics.noteCutEffects.map { noteCutDiagnosticJSON($0, from: result) },
            "note_delay_effects": diagnostics.noteDelayEffects.map(noteDelayDiagnosticJSON),
            "retrigger_effects": diagnostics.retriggerEffects.map(retriggerDiagnosticJSON),
            "arpeggio_effects": diagnostics.arpeggioEffects.map(arpeggioDiagnosticJSON),
            "arpeggio_0xy_effects": diagnostics.arpeggioEffects.map(arpeggioDiagnosticJSON),
            "tone_portamento_effects": diagnostics.tonePortamentoEffects.map(tonePortamentoDiagnosticJSON),
            "portamento_slide_effects": diagnostics.portamentoSlideEffects.map(portamentoSlideDiagnosticJSON),
            "fine_portamento_up_effects": diagnostics.finePortamentoUpEffects.map(finePortamentoUpDiagnosticJSON),
            "e1x_fine_portamento_up_effects": diagnostics.finePortamentoUpEffects.map(finePortamentoUpDiagnosticJSON),
            "fine_portamento_down_effects": diagnostics.finePortamentoDownEffects.map(finePortamentoDownDiagnosticJSON),
            "e2x_fine_portamento_down_effects": diagnostics.finePortamentoDownEffects.map(finePortamentoDownDiagnosticJSON),
            "vibrato_effects": diagnostics.vibratoEffects.map(vibratoDiagnosticJSON),
            "vibrato_control_effects": diagnostics.vibratoControlEffects.map(vibratoControlDiagnosticJSON),
            "vibrato_volume_slide_6xy_effects": diagnostics.vibratoEffects.filter { $0.effectType == 0x06 }.map(vibratoDiagnosticJSON),
            "key_off_events": diagnostics.keyOffEvents.map(keyOffEventJSON),
            "events": eventJSON(from: result),
            "ignored_cells": diagnostics.ignoredCells.map(ignoredCellJSON),
            "deferred_fields": diagnostics.deferredCellFields.map(deferredFieldJSON),
        ]
    }

    private static func exportDiagnostics(
        from result: PlaybackSongOfflineRenderResult
    ) -> MixerWAVExportDiagnostics {
        result.exportDiagnostics ?? MixerWAVExporter.diagnostics(for: result.block)
    }

    private static func exportDiagnosticsJSON(
        _ diagnostics: MixerWAVExportDiagnostics
    ) -> [String: Any] {
        [
            "auto_headroom_enabled": diagnostics.autoHeadroomEnabled,
            "auto_headroom_safety_db": nullableJSONValue(diagnostics.autoHeadroomSafetyDB),
            "export_gain": Double(diagnostics.policy.gain),
            "export_headroom_db": nullableJSONValue(diagnostics.policy.headroomDB),
            "pre_export_peak": Double(diagnostics.preExportPeak),
            "pre_export_per_channel_peak": diagnostics.preExportPerChannelPeak.map { Double($0) },
            "pre_export_overrange_sample_count": diagnostics.preExportOverrangeSampleCount,
            "pre_export_rms": Double(diagnostics.preExportRMS),
            "computed_export_gain": Double(diagnostics.computedExportGain),
            "computed_headroom_db": diagnostics.computedHeadroomDB,
            "post_gain_peak": Double(diagnostics.postGainPeak),
            "post_gain_per_channel_peak": diagnostics.postGainPerChannelPeak.map { Double($0) },
            "post_gain_rms": Double(diagnostics.postGainRMS),
            "pcm16_clipping_count": diagnostics.pcm16ClippingSampleCount,
            "pcm16_clipping_sample_count": diagnostics.pcm16ClippingSampleCount,
            "clipping_detected": diagnostics.clippingDetected,
            "recommendation": nullableJSONValue(diagnostics.recommendation),
        ]
    }

    private static func renderIsolationJSON(from result: PlaybackSongOfflineRenderResult) -> [String: Any] {
        let filter = result.request.isolationFilter
        let includedEventIndices = PlaybackSongOfflineRenderer.includedEventIndices(
            for: result.plan,
            isolationFilter: filter
        )
        let totalEvents = result.plan.pattern.events.count
        return [
            "enabled": filter?.isEnabled ?? false,
            "solo_channel_index": nullableJSONValue(filter?.soloChannelIndex),
            "solo_instrument_index": nullableJSONValue(filter?.soloInstrumentIndex),
            "solo_sample_index": nullableJSONValue(filter?.soloSampleIndex),
            "total_scheduled_event_count": totalEvents,
            "included_scheduled_event_count": includedEventIndices?.count ?? totalEvents,
            "muted_scheduled_event_count": includedEventIndices.map { max(0, totalEvents - $0.count) } ?? 0,
            "policy": "nonmatching scheduled voices start at zero gain and their later state updates are not applied; timing and adapter diagnostics are still planned from the full bounded song",
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
                "total_carried_tone_portamento_voice_count": 0,
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
            "total_carried_tone_portamento_voice_count": summary.totalCarriedTonePortamentoVoices,
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
            "carried_tone_portamento_voice_count": diagnostic.carriedTonePortamentoVoiceCount,
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

    private static func sameChannelVoiceLifetimeJSON(
        _ diagnostics: PlaybackSongSameChannelVoiceLifetimeDiagnostics
    ) -> [String: Any] {
        [
            "replacement_ramp_frame_count": diagnostics.replacementRampFrameCount,
            "active_voices_by_source_channel": intKeyedDictionaryJSON(diagnostics.activeVoicesBySourceChannel),
            "loaded_voices_by_source_channel": intKeyedDictionaryJSON(diagnostics.loadedVoicesBySourceChannel),
            "same_channel_active_voice_count": diagnostics.sameChannelActiveVoiceCount,
            "same_channel_replacement_start_count": diagnostics.sameChannelReplacementStartCount,
            "same_channel_replacement_completion_count": diagnostics.sameChannelReplacementCompletionCount,
            "same_channel_voice_overlap_frames": diagnostics.sameChannelVoiceOverlapFrames,
            "max_voices_per_source_channel": intKeyedDictionaryJSON(diagnostics.maxVoicesPerSourceChannel),
            "old_voice_kept_reason_counts": diagnostics.oldVoiceKeptReasonCounts,
            "old_voice_ramp_duration_frames": diagnostics.oldVoiceRampDurationFrames,
            "window_boundary_prune_count": diagnostics.windowBoundaryPruneCount,
            "replacement_events": diagnostics.replacementEvents.map(sameChannelReplacementEventJSON),
        ]
    }

    private static func sameChannelReplacementEventJSON(
        _ event: PlaybackSongSameChannelReplacementEvent
    ) -> [String: Any] {
        [
            "source_channel_index": event.sourceChannelIndex,
            "old_event_index": event.oldEventIndex,
            "new_event_index": event.newEventIndex,
            "replacement_frame": event.replacementFrame,
            "completion_frame": event.completionFrame,
            "old_voice_kept_reason": event.oldVoiceKeptReason,
            "old_voice_ramp_duration_frames": event.oldVoiceRampDurationFrames,
        ]
    }

    private static func intKeyedDictionaryJSON(_ values: [Int: Int]) -> [String: Int] {
        values.reduce(into: [String: Int]()) { result, entry in
            result[String(entry.key)] = entry.value
        }
    }

    private static func eventJSON(from result: PlaybackSongOfflineRenderResult) -> [[String: Any]] {
        result.diagnostics.eventMappings.map { mapping in
            eventJSON(for: mapping, from: result)
        }
    }

    private static func samplePCMStatsJSON(from song: PlaybackSong) -> [[String: Any]] {
        song.instrumentsByIndex.values
            .sorted { $0.index < $1.index }
            .flatMap { instrument in
                instrument.samples
                    .sorted { $0.sampleIndex < $1.sampleIndex }
                    .map(samplePCMStatJSON)
            }
    }

    private struct SamplePCMStats {
        let minimum: Float?
        let maximum: Float?
        let rms: Float
        let peak: Float
        let zeroCrossingCount: Int
    }

    private static func samplePCMStats(_ pcm: [Float]) -> SamplePCMStats {
        guard let first = pcm.first else {
            return SamplePCMStats(
                minimum: nil,
                maximum: nil,
                rms: 0,
                peak: 0,
                zeroCrossingCount: 0
            )
        }
        var minimum = first
        var maximum = first
        var squareSum = Double(0)
        var peak = Float(0)
        var zeroCrossingCount = 0
        var previousSign = first < 0 ? -1 : (first > 0 ? 1 : 0)
        for sample in pcm {
            minimum = min(minimum, sample)
            maximum = max(maximum, sample)
            peak = max(peak, abs(sample))
            squareSum += Double(sample) * Double(sample)
            let sign = sample < 0 ? -1 : (sample > 0 ? 1 : 0)
            if sign != 0, previousSign != 0, sign != previousSign {
                zeroCrossingCount += 1
            }
            if sign != 0 {
                previousSign = sign
            }
        }
        return SamplePCMStats(
            minimum: minimum,
            maximum: maximum,
            rms: Float(sqrt(squareSum / Double(pcm.count))),
            peak: peak,
            zeroCrossingCount: zeroCrossingCount
        )
    }

    private static func samplePCMStatJSON(_ sample: PlaybackSample) -> [String: Any] {
        let stats = samplePCMStats(sample.pcm)
        let loop = sample.loopRegion
        return [
            "instrument_index": sample.instrumentIndex,
            "sample_index": sample.sampleIndex,
            "frame_count": sample.pcm.count,
            "sample_length": sample.sampleLength,
            "min": nullableJSONValue(stats.minimum.map { Double($0) }),
            "max": nullableJSONValue(stats.maximum.map { Double($0) }),
            "rms": Double(stats.rms),
            "peak": Double(stats.peak),
            "zero_crossing_count": stats.zeroCrossingCount,
            "loop_start_frame": loop.startFrame,
            "loop_end_frame": loop.endFrame,
            "loop_length_frames": loop.lengthFrames,
            "loop_enabled": loop.isEnabled,
            "loop_type": loop.loopType,
            "loop_type_name": loop.loopTypeName,
            "sample_volume": Double(sample.volume),
            "sample_volume_raw_estimate": Int((sample.volume * 64).rounded()),
            "sample_volume_raw_range": "0...64",
            "relative_note": sample.relativeNote,
            "finetune": sample.finetune,
            "base_sample_rate": sample.baseSampleRate,
            "pcm_value_domain": "PlaybackSample.pcm Float32 values after XM delta decode or synthetic construction",
            "source_bit_depth_bits": nullableJSONValue(sample.sourceBitDepthBits),
            "source_16_bit": nullableJSONValue(sample.sourceBitDepthBits.map { $0 == 16 }),
            "source_signedness": sample.sourceIsSignedPCM.map { $0 ? "signed" : "unsigned" } ?? NSNull(),
            "source_delta_encoded": nullableJSONValue(sample.sourceIsDeltaEncoded),
            "source_format_note": sample.sourceBitDepthBits == nil
                ? "source sample bit depth and signedness are not available for synthetic samples"
                : "XM sample payload is delta-decoded into PlaybackSample.pcm Float32 values",
        ]
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
            "total_e6x_pattern_loop": summary.totalE6xPatternLoop,
            "total_eex_pattern_delay": summary.totalEExPatternDelay,
            "total_fxx_speed_bpm": summary.totalFxxSpeedBPM,
            "total_e9x_retrigger": summary.totalE9xRetrigger,
            "total_ecx_note_cut": summary.totalECxNoteCut,
            "total_edx_note_delay": summary.totalEDxNoteDelay,
            "total_other_e_commands": summary.totalOtherECommands,
            "total_traversal_hazards": summary.totalTraversalHazards,
            "likely_ignores_structure_changing_behavior": summary.likelyIgnoresStructureChangingBehavior,
            "first_traversal_hazard_coordinates": summary.firstTraversalHazards.map(effectCommandDiagnosticJSON),
            "e_command_subtype_counts": summary.eCommandSubtypeCounts.map(eCommandSubtypeCountJSON),
        ]
    }

    private static func traversalSummaryJSON(
        _ summary: PlaybackSongSyntheticTraversalSummary
    ) -> [String: Any] {
        [
            "path_length": summary.pathLength,
            "traversal_path_length": summary.pathLength,
            "stop_reason": summary.stopReason.rawValue,
            "traversal_stop_reason": summary.stopReason.rawValue,
            "guard_hit": summary.guardHit,
            "traversal_guard_hit": summary.guardHit,
            "applied_traversal_count": summary.appliedTraversalCount,
            "traversal_applied_count": summary.appliedTraversalCount,
            "dxx_detected_count": summary.dxxDetectedCount,
            "dxx_applied_count": summary.dxxAppliedCount,
            "dxx_invalid_target_count": summary.dxxInvalidTargetCount,
            "dxx_out_of_range_count": summary.dxxOutOfRangeCount,
            "bxx_detected_count": summary.bxxDetectedCount,
            "bxx_applied_count": summary.bxxAppliedCount,
            "bxx_out_of_range_count": summary.bxxOutOfRangeCount,
            "e6x_detected_count": summary.e6xDetectedCount,
            "e6x_loop_start_count": summary.e6xLoopStartCount,
            "e6x_loop_taken_count": summary.e6xLoopTakenCount,
            "e6x_missing_start_count": summary.e6xMissingStartCount,
            "e6x_loop_limit_hit_count": summary.e6xLoopLimitHitCount,
            "first_coordinates": summary.firstDiagnostics.map(traversalDiagnosticJSON),
            "first_traversal_coordinates": summary.firstDiagnostics.map(traversalDiagnosticJSON),
        ]
    }

    private static func traversalDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticTraversalDiagnostic
    ) -> [String: Any] {
        [
            "kind": diagnostic.kind.rawValue,
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "effect_label": traversalEffectLabel(diagnostic.kind),
            "decoded_label": traversalEffectLabel(diagnostic.kind),
            "status": diagnostic.status.rawValue,
            "current_status": diagnostic.status.rawValue,
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "invalid_target": diagnostic.invalidTarget,
            "out_of_range": diagnostic.outOfRange,
            "loop_start_marked": diagnostic.loopStartMarked,
            "loop_taken": diagnostic.loopTaken,
            "loop_remaining": nullableJSONValue(diagnostic.loopRemaining),
            "missing_loop_start": diagnostic.missingLoopStart,
            "loop_limit_hit": diagnostic.loopLimitHit,
            "loop_limit": nullableJSONValue(diagnostic.loopLimit),
            "next_order": nullableJSONValue(diagnostic.nextOrderIndex),
            "target_order": nullableJSONValue(diagnostic.targetOrderIndex),
            "target_pattern": nullableJSONValue(diagnostic.targetPatternIndex),
            "target_row": nullableJSONValue(diagnostic.targetRowIndex),
            "loop_start_row": nullableJSONValue(diagnostic.loopStartRowIndex),
            "combined_with_bxx": diagnostic.combinedWithBxx,
            "combined_with_dxx": diagnostic.combinedWithDxx,
            "policy": diagnostic.policy,
        ]
    }

    private static func traversalEffectLabel(
        _ kind: PlaybackSongSyntheticTraversalDiagnostic.Kind
    ) -> String {
        switch kind {
        case .dxxPatternBreak:
            return "Dxx pattern break"
        case .bxxPositionJump:
            return "Bxx position jump"
        case .e6xPatternLoop:
            return "E6x pattern loop"
        }
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

    private static func pitchModulationDeferredEffectSummaryJSON(
        _ diagnostics: PlaybackSongSyntheticDiagnostics
    ) -> [String: Any] {
        let effectCounts = Dictionary(
            grouping: diagnostics.effectCommandDiagnostics
                .filter { $0.status == .deferredUnsupported && $0.isPitchModulationDiagnostic }
                .map(\.decodedLabel),
            by: { $0 }
        ).mapValues(\.count)
        let volumeCounts = Dictionary(
            grouping: diagnostics.volumeColumnMappings.compactMap { mapping in
                mapping.volumeColumn.deferred ? pitchModulationVolumeColumnLabel(mapping.volumeColumn.command) : nil
            },
            by: { $0 }
        ).mapValues(\.count)
        let coordinates = pitchModulationDeferredEffectsJSON(diagnostics)
        return [
            "total_arpeggio_count": effectCounts["0xy arpeggio"] ?? 0,
            "total_portamento_up_count": effectCounts["1xx portamento up"] ?? 0,
            "total_portamento_down_count": effectCounts["2xx portamento down"] ?? 0,
            "total_tone_portamento_count": effectCounts["3xx tone portamento"] ?? 0,
            "total_vibrato_count": effectCounts["4xy vibrato"] ?? 0,
            "total_tone_portamento_volume_slide_count": effectCounts["5xy tone portamento + volume slide"] ?? 0,
            "total_vibrato_volume_slide_count": effectCounts["6xy vibrato + volume slide"] ?? 0,
            "total_tremolo_count": effectCounts["7xy tremolo"] ?? 0,
            "total_volume_column_vibrato_speed_count": volumeCounts["volume-column vibrato speed"] ?? 0,
            "total_volume_column_vibrato_count": volumeCounts["volume-column vibrato"] ?? 0,
            "total_volume_column_tone_portamento_count": volumeCounts["volume-column tone portamento"] ?? 0,
            "total_deferred_pitch_modulation_effect_count": coordinates.count,
            "first_deferred_effect_coordinates": Array(coordinates.prefix(10)),
        ]
    }

    private static func pitchModulationDeferredEffectsJSON(
        _ diagnostics: PlaybackSongSyntheticDiagnostics
    ) -> [[String: Any]] {
        var coordinates = [[String: Any]]()
        for diagnostic in diagnostics.effectCommandDiagnostics
            where diagnostic.status == .deferredUnsupported && diagnostic.isPitchModulationDiagnostic
        {
            coordinates.append([
                "source": positionJSON(diagnostic.source),
                "channel_index": diagnostic.channelIndex,
                "command_source": "effect_column",
                "effect_type": Int(diagnostic.effectType),
                "effect_param": Int(diagnostic.effectParam),
                "effect_label": diagnostic.decodedLabel,
                "decoded_label": diagnostic.decodedLabel,
                "status": effectCommandStatusName(diagnostic.status),
                "current_status": effectCommandStatusName(diagnostic.status),
            ])
        }
        for mapping in diagnostics.volumeColumnMappings {
            guard mapping.volumeColumn.deferred,
                  let label = pitchModulationVolumeColumnLabel(mapping.volumeColumn.command)
            else {
                continue
            }
            coordinates.append([
                "source": positionJSON(mapping.source),
                "channel_index": mapping.channelIndex,
                "command_source": "volume_column",
                "effect_type": "volume_column",
                "effect_param": Int(mapping.volumeColumn.rawValue),
                "raw_volume_column": Int(mapping.volumeColumn.rawValue),
                "effect_label": label,
                "decoded_label": label,
                "status": volumeColumnCurrentStatusName(mapping.volumeColumn),
                "current_status": volumeColumnCurrentStatusName(mapping.volumeColumn),
            ])
        }
        return coordinates
    }

    private static func pitchModulationVolumeColumnLabel(
        _ command: PlaybackSongSyntheticVolumeColumnCommand
    ) -> String? {
        switch command {
        case .setVibratoSpeed:
            return "volume-column vibrato speed"
        case .vibrato:
            return "volume-column vibrato"
        case .tonePortamento:
            return "volume-column tone portamento"
        case .none,
             .setVolume,
             .volumeSlideDown,
             .volumeSlideUp,
             .fineVolumeSlideDown,
             .fineVolumeSlideUp,
             .setPanning,
             .panningSlideLeft,
             .panningSlideRight,
             .unsupported:
            return nil
        }
    }

    private static func volumeColumnCurrentStatusName(
        _ diagnostic: PlaybackSongSyntheticVolumeColumnDiagnostic
    ) -> String {
        if diagnostic.applied {
            return "applied"
        }
        if diagnostic.deferred {
            return "deferred/unsupported"
        }
        if diagnostic.ignoredAsEmptyOrNoOp {
            return "ignored/no-op"
        }
        return "unknown"
    }

    private static func arpeggioDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticArpeggioDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "effect_label": "0xy arpeggio",
            "decoded_label": "0xy arpeggio",
            "status": arpeggioStatusName(diagnostic.status),
            "current_status": arpeggioStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "x_semitone_offset": diagnostic.xSemitoneOffset,
            "y_semitone_offset": diagnostic.ySemitoneOffset,
            "current_linear_period_before": diagnostic.currentLinearPeriodBefore.map { $0 as Any } ?? NSNull(),
            "current_linear_period_after": diagnostic.currentLinearPeriodAfter.map { $0 as Any } ?? NSNull(),
            "current_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "current_playback_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_playback_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "active_voice_update_count": diagnostic.applied ? diagnostic.stepUpdates.count : 0,
            "scheduled_sample_step_update_count": diagnostic.stepUpdates.count,
            "step_update_count": diagnostic.stepUpdates.count,
            "step_updates": diagnostic.stepUpdates.map(tonePortamentoStepUpdateJSON),
            "policy": diagnostic.policy,
        ]
    }

    private static func scheduledVoiceRejectedCount(from result: PlaybackSongOfflineRenderResult) -> Int {
        result.scheduledVoiceAttempts.compactMap(\.rejectionReason).count
    }

    private static func changedVoiceStateUpdateCount(
        _ updates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    ) -> Int {
        updates.filter { update in
            update.activeVoiceUpdated &&
                ((update.gainBefore != nil && update.gainAfter != nil && update.gainBefore != update.gainAfter) ||
                    (update.panBefore != nil && update.panAfter != nil && update.panBefore != update.panAfter))
        }.count
    }

    private static func interruptedRampCount(
        _ updates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]
    ) -> Int {
        var lastGainUpdateFrameByEventIndex = [Int: Int]()
        var lastPanUpdateFrameByEventIndex = [Int: Int]()
        var interruptedCount = 0
        for update in updates where update.activeVoiceUpdated {
            guard let eventIndex = update.activeEventIndex else {
                continue
            }
            if update.gainBefore != update.gainAfter {
                if let previousFrame = lastGainUpdateFrameByEventIndex[eventIndex],
                   update.scheduledFrame - previousFrame < CSoftwareMixer.gainPanUpdateRampFrameCount {
                    interruptedCount += 1
                }
                lastGainUpdateFrameByEventIndex[eventIndex] = update.scheduledFrame
            }
            if update.panBefore != update.panAfter {
                if let previousFrame = lastPanUpdateFrameByEventIndex[eventIndex],
                   update.scheduledFrame - previousFrame < CSoftwareMixer.gainPanUpdateRampFrameCount {
                    interruptedCount += 1
                }
                lastPanUpdateFrameByEventIndex[eventIndex] = update.scheduledFrame
            }
        }
        return interruptedCount
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
        object["note_text"] = noteText(mapping.note)
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
        object["sample_volume"] = Double(mapping.sampleVolume)
        object["sample_volume_raw_estimate"] = mapping.sampleVolumeRawEstimate
        object["sample_volume_source"] = "xm_sample_header_volume_div_64"
        object["sample_volume_raw_range"] = "0...64"
        object["effective_volume_multiplier"] = Double(normalizedVolumeMultiplier(mapping.effectiveVolumeValue))
        object["pan"] = Double(event?.pan ?? mapping.effectivePan)
        object["loop_mode"] = loopModeName(mapping.loopMode)
        object["loop_start_frame"] = event?.loop.startFrame ?? 0
        object["loop_end_frame"] = event?.loop.endFrame ?? 0
        object["loop_length_frames"] = event?.loop.lengthFrames ?? 0
        object["volume_column"] = volumeColumnDiagnosticJSON(mapping.volumeColumn)
        object["sample_offset"] = sampleOffsetDiagnosticJSON(mapping.sampleOffset)
        object["has_ignored_volume_column"] = mapping.hasIgnoredVolumeColumn
        object["has_ignored_effect"] = mapping.hasIgnoredEffect
        object["effective_volume_value"] = mapping.effectiveVolumeValue
        object["effective_global_volume_value"] = mapping.effectiveGlobalVolumeValue
        object["effective_global_volume_multiplier"] = Double(mapping.effectiveGlobalVolumeMultiplier)
        object["effective_pan"] = Double(mapping.effectivePan)
        object["gain_construction"] = gainConstructionJSON(mapping: mapping, event: event)
        object["volume_envelope"] = eventVolumeEnvelopeJSON(mapping, event: event, startFrame: startFrame)
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

    private static func eventVolumeEnvelopeJSON(
        _ mapping: PlaybackSongSyntheticEventMapping,
        event: SyntheticTrackerEvent?,
        startFrame: Int
    ) -> [String: Any] {
        let semantics = mapping.volumeEnvelopeSemantics
        let envelope = event?.volumeEnvelope
        let keyOffFrame = event?.keyOffFrame
        let fadeoutFrameDecrement = event?.fadeoutFrameDecrement ?? 0
        let startSnapshot = envelopeDiagnosticSnapshot(
            label: "start",
            envelope: envelope,
            absoluteFrame: startFrame,
            startFrame: startFrame,
            keyOffFrame: keyOffFrame,
            fadeoutFrameDecrement: fadeoutFrameDecrement,
            baseGain: event?.gain ?? 0
        )
        let keyOffSnapshot = keyOffFrame.map {
            envelopeDiagnosticSnapshot(
                label: "key_off",
                envelope: envelope,
                absoluteFrame: $0,
                startFrame: startFrame,
                keyOffFrame: keyOffFrame,
                fadeoutFrameDecrement: fadeoutFrameDecrement,
                baseGain: event?.gain ?? 0
            )
        }
        var object: [String: Any] = [
            "status": volumeEnvelopeStatusName(mapping.volumeEnvelopeStatus),
            "enabled": semantics.envelopeEnabled,
            "clock_policy": "xm_ticks_mapped_to_output_frames",
            "point_mapping_policy": "floor_xm_tick_times_frames_per_tick_at_event",
            "position_domain": "output_frames",
            "advance_policy": "evaluate_then_advance_one_output_frame",
            "first_audible_frame_policy": "note_start_uses_position_zero_before_advance",
            "sustain_policy": "hold_at_sustain_frame_while_key_on_before_loop",
            "key_off_policy": "release_before_rendering_key_off_frame",
            "release_policy": "continue_from_current_or_sustain_position_after_key_off",
            "loop_policy": "inclusive_frame_loop_while_key_on_after_sustain_check",
            "loop_end_policy": "inclusive",
            "loop_after_key_off": false,
            "source_point_count": mapping.sourceVolumeEnvelopePointCount,
            "mapped_point_count": mapping.mappedVolumeEnvelopePointCount,
            "points": envelopePointsJSON(envelope),
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
            "key_off_frame": nullableJSONValue(keyOffFrame),
            "fadeout_start_frame": nullableJSONValue(keyOffFrame),
            "fadeout_frame_decrement": Double(fadeoutFrameDecrement),
            "fadeout_value": semantics.fadeoutValue,
            "fadeout_applied": semantics.fadeoutApplied,
            "fadeout_deferred": semantics.fadeoutDeferred,
            "limitations": semantics.limitations,
            "has_deferred_sustain": mapping.hasDeferredVolumeEnvelopeSustain,
            "has_deferred_loop": mapping.hasDeferredVolumeEnvelopeLoop,
            "has_deferred_fadeout": mapping.hasDeferredVolumeEnvelopeFadeout,
        ]
        appendEnvelopeSnapshotFields(startSnapshot, suffix: "at_start", to: &object)
        if let keyOffSnapshot {
            appendEnvelopeSnapshotFields(keyOffSnapshot, suffix: "at_key_off", to: &object)
        }
        object["diagnostic_snapshots"] = [startSnapshot, keyOffSnapshot].compactMap { $0 }.map(envelopeSnapshotJSON)
        return object
    }

    private struct EnvelopeDiagnosticSnapshot {
        let label: String
        let absoluteFrame: Int
        let positionFrame: Int?
        let positionFrameAfterAdvance: Int?
        let value: Double?
        let segmentIndex: Int?
        let sustainHeld: Bool?
        let loopActive: Bool?
        let loopTakenCount: Int?
        let keyOn: Bool
        let fadeoutValue: Double
        let fadeoutAppliedGain: Double
        let finalVoiceGain: Double
    }

    private static func envelopePointsJSON(_ envelope: MixerEnvelope?) -> [[String: Any]] {
        envelope?.points.enumerated().map { index, point in
            [
                "index": index,
                "position_frame": point.positionFrame,
                "value": Double(point.value),
            ]
        } ?? []
    }

    private static func appendEnvelopeSnapshotFields(
        _ snapshot: EnvelopeDiagnosticSnapshot,
        suffix: String,
        to object: inout [String: Any]
    ) {
        object["envelope_tick_frame_\(suffix)"] = snapshot.absoluteFrame
        object["envelope_position_frame_\(suffix)"] = nullableJSONValue(snapshot.positionFrame)
        object["envelope_position_frame_after_advance_\(suffix)"] = nullableJSONValue(snapshot.positionFrameAfterAdvance)
        object["envelope_value_\(suffix)"] = nullableJSONValue(snapshot.value)
        object["envelope_segment_index_\(suffix)"] = nullableJSONValue(snapshot.segmentIndex)
        object["envelope_sustain_held_\(suffix)"] = nullableJSONValue(snapshot.sustainHeld)
        object["envelope_loop_active_\(suffix)"] = nullableJSONValue(snapshot.loopActive)
        object["envelope_loop_taken_count_\(suffix)"] = nullableJSONValue(snapshot.loopTakenCount)
        object["key_on_\(suffix)"] = snapshot.keyOn
        object["fadeout_value_\(suffix)"] = snapshot.fadeoutValue
        object["fadeout_applied_gain_\(suffix)"] = snapshot.fadeoutAppliedGain
        object["final_voice_gain_\(suffix)"] = snapshot.finalVoiceGain
    }

    private static func envelopeSnapshotJSON(_ snapshot: EnvelopeDiagnosticSnapshot) -> [String: Any] {
        [
            "label": snapshot.label,
            "absolute_frame": snapshot.absoluteFrame,
            "position_frame": nullableJSONValue(snapshot.positionFrame),
            "position_frame_after_advance": nullableJSONValue(snapshot.positionFrameAfterAdvance),
            "value": nullableJSONValue(snapshot.value),
            "segment_index": nullableJSONValue(snapshot.segmentIndex),
            "sustain_held": nullableJSONValue(snapshot.sustainHeld),
            "loop_active": nullableJSONValue(snapshot.loopActive),
            "loop_taken_count": nullableJSONValue(snapshot.loopTakenCount),
            "key_on": snapshot.keyOn,
            "fadeout_value": snapshot.fadeoutValue,
            "fadeout_applied_gain": snapshot.fadeoutAppliedGain,
            "final_voice_gain": snapshot.finalVoiceGain,
        ]
    }

    private static func envelopeDiagnosticSnapshot(
        label: String,
        envelope: MixerEnvelope?,
        absoluteFrame: Int,
        startFrame: Int,
        keyOffFrame: Int?,
        fadeoutFrameDecrement: Float,
        baseGain: Float
    ) -> EnvelopeDiagnosticSnapshot {
        let relativeFrame = max(0, absoluteFrame - max(0, startFrame))
        let relativeKeyOffFrame = keyOffFrame.map { max(0, $0 - max(0, startFrame)) }
        let keyOn = relativeKeyOffFrame.map { relativeFrame < $0 } ?? true
        let keyedFrames = keyOn ? relativeFrame : min(relativeFrame, relativeKeyOffFrame ?? relativeFrame)
        let releasedFrames = keyOn ? 0 : max(0, relativeFrame - (relativeKeyOffFrame ?? relativeFrame))
        let positionFrame: Int?
        let positionFrameAfterAdvance: Int?
        let value: Double?
        let segmentIndex: Int?
        let sustainHeld: Bool?
        let loopActive: Bool?
        let loopTakenCount: Int?
        if let envelope, !envelope.points.isEmpty {
            let keyedPosition = advancedEnvelopePosition(0, frames: keyedFrames, keyOn: true, envelope: envelope)
            let position = advancedEnvelopePosition(keyedPosition, frames: releasedFrames, keyOn: false, envelope: envelope)
            positionFrame = position
            positionFrameAfterAdvance = advancedEnvelopePosition(position, frames: 1, keyOn: keyOn, envelope: envelope)
            value = envelopeValue(envelope, at: position)
            segmentIndex = envelopeSegmentIndex(envelope, at: position)
            sustainHeld = keyOn && envelope.sustainFrame.map { position == $0 && keyedFrames >= $0 } == true
            loopActive = keyOn && envelope.loopStartFrame.map { start in
                envelope.loopEndFrame.map { end in position >= start && position <= end } ?? false
            } == true
            loopTakenCount = envelopeLoopTakenCount(keyedFrames: keyedFrames, envelope: envelope)
        } else {
            positionFrame = nil
            positionFrameAfterAdvance = nil
            value = nil
            segmentIndex = nil
            sustainHeld = nil
            loopActive = nil
            loopTakenCount = nil
        }
        let safeFadeoutDecrement = fadeoutFrameDecrement.isFinite && fadeoutFrameDecrement > 0
            ? Double(fadeoutFrameDecrement)
            : 0
        let fadeoutValue = keyOn ? 1.0 : max(0, 1.0 - (Double(releasedFrames) * safeFadeoutDecrement))
        let envelopeGain = value ?? 1.0
        let baseGain = baseGain.isFinite ? Double(baseGain) : 0
        return EnvelopeDiagnosticSnapshot(
            label: label,
            absoluteFrame: absoluteFrame,
            positionFrame: positionFrame,
            positionFrameAfterAdvance: positionFrameAfterAdvance,
            value: value,
            segmentIndex: segmentIndex,
            sustainHeld: sustainHeld,
            loopActive: loopActive,
            loopTakenCount: loopTakenCount,
            keyOn: keyOn,
            fadeoutValue: fadeoutValue,
            fadeoutAppliedGain: fadeoutValue,
            finalVoiceGain: baseGain * envelopeGain * fadeoutValue
        )
    }

    private static func advancedEnvelopePosition(
        _ position: Int,
        frames: Int,
        keyOn: Bool,
        envelope: MixerEnvelope
    ) -> Int {
        let current = max(0, position)
        guard frames > 0 else {
            return current
        }
        guard keyOn else {
            return clampedEnvelopePosition(current + frames)
        }
        if let sustainFrame = envelope.sustainFrame,
           current >= sustainFrame {
            return sustainFrame
        }
        if let sustainFrame = envelope.sustainFrame,
           canReachSustainBeforeLoop(
               position: current,
               frames: frames,
               sustainFrame: sustainFrame,
               loopEndFrame: envelope.loopEndFrame
           ) {
            return sustainFrame
        }
        guard let loopStartFrame = envelope.loopStartFrame,
              let loopEndFrame = envelope.loopEndFrame,
              loopEndFrame >= loopStartFrame else {
            return clampedEnvelopePosition(current + frames)
        }
        let target = current + frames
        guard target > loopEndFrame else {
            return clampedEnvelopePosition(target)
        }
        let loopLength = loopEndFrame - loopStartFrame + 1
        guard loopLength > 0 else {
            return clampedEnvelopePosition(target)
        }
        return loopStartFrame + ((target - loopEndFrame - 1) % loopLength)
    }

    private static func envelopeLoopTakenCount(keyedFrames: Int, envelope: MixerEnvelope) -> Int {
        guard keyedFrames > 0,
              let loopStartFrame = envelope.loopStartFrame,
              let loopEndFrame = envelope.loopEndFrame,
              loopEndFrame >= loopStartFrame else {
            return 0
        }
        let initialPosition = 0
        if let sustainFrame = envelope.sustainFrame {
            if sustainFrame <= initialPosition {
                return 0
            }
            if canReachSustainBeforeLoop(
                position: initialPosition,
                frames: keyedFrames,
                sustainFrame: sustainFrame,
                loopEndFrame: loopEndFrame
            ) {
                return 0
            }
        }
        let target = initialPosition + keyedFrames
        guard target > loopEndFrame else {
            return 0
        }
        let loopLength = loopEndFrame - loopStartFrame + 1
        guard loopLength > 0 else {
            return 0
        }
        return ((target - loopEndFrame - 1) / loopLength) + 1
    }

    private static func canReachSustainBeforeLoop(
        position: Int,
        frames: Int,
        sustainFrame: Int,
        loopEndFrame: Int?
    ) -> Bool {
        guard position < sustainFrame,
              position + frames >= sustainFrame else {
            return false
        }
        if let loopEndFrame,
           loopEndFrame < sustainFrame,
           position + frames > loopEndFrame {
            return false
        }
        return true
    }

    private static func clampedEnvelopePosition(_ position: Int) -> Int {
        min(Int(UInt32.max), max(0, position))
    }

    private static func envelopeValue(_ envelope: MixerEnvelope, at positionFrame: Int) -> Double {
        guard let first = envelope.points.first else {
            return 1
        }
        if positionFrame <= first.positionFrame {
            return Double(first.value)
        }
        for index in 1..<envelope.points.count {
            let previous = envelope.points[index - 1]
            let next = envelope.points[index]
            guard positionFrame <= next.positionFrame else {
                continue
            }
            let span = Double(max(1, next.positionFrame - previous.positionFrame))
            let progress = Double(positionFrame - previous.positionFrame) / span
            return Double(previous.value) + ((Double(next.value) - Double(previous.value)) * progress)
        }
        return Double(envelope.points.last?.value ?? 1)
    }

    private static func envelopeSegmentIndex(_ envelope: MixerEnvelope, at positionFrame: Int) -> Int? {
        guard !envelope.points.isEmpty else {
            return nil
        }
        if positionFrame <= envelope.points[0].positionFrame {
            return 0
        }
        for index in 1..<envelope.points.count {
            if positionFrame <= envelope.points[index].positionFrame {
                return index - 1
            }
        }
        return envelope.points.count - 1
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

    private static func gainConstructionJSON(
        mapping: PlaybackSongSyntheticEventMapping,
        event: SyntheticTrackerEvent?
    ) -> [String: Any] {
        let channelMultiplier = normalizedVolumeMultiplier(mapping.effectiveVolumeValue)
        return [
            "sample_volume_source": "XM sample header volume normalized once as raw_volume / 64 into PlaybackSample.volume",
            "sample_volume_raw_range": "0...64",
            "sample_volume_raw_estimate": mapping.sampleVolumeRawEstimate,
            "sample_volume_normalized": Double(mapping.sampleVolume),
            "channel_volume_value": mapping.effectiveVolumeValue,
            "channel_volume_multiplier": Double(channelMultiplier),
            "global_volume_value": mapping.effectiveGlobalVolumeValue,
            "global_volume_multiplier": Double(mapping.effectiveGlobalVolumeMultiplier),
            "base_gain_formula": "sample_volume * channel_volume_multiplier * global_volume_multiplier",
            "base_gain": Double(event?.gain ?? 0),
            "envelope_and_fadeout_applied_in_c_mixer": true,
            "normalization_applied_once": true,
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

    private static func rowTickFrameMappingPolicyJSON() -> [String: Any] {
        [
            "frames_per_tick_formula": "sample_rate * 2.5 / bpm",
            "tick_duration_seconds_formula": "2.5 / bpm",
            "row_start_frame_policy": "floor(accumulated_exact_row_start)",
            "row_end_frame_policy": "floor(accumulated_exact_row_end)",
            "tick_start_frame_policy": "floor(row_start_exact_frame + tick * frames_per_tick)",
            "fractional_row_frame_accumulation": true,
            "timing_change_policy": "Fxx applies to rows after the source row",
            "constant_timing_synthetic_policy": "floor((row * speed + tick) * frames_per_tick)",
        ]
    }

    private static func eventApplicationTimingPolicyJSON() -> [String: Any] {
        [
            "note_trigger_frame_policy": "voice_audible_on_scheduled_frame",
            "tick_level_effect_update_frame_policy": "applied_before_rendering_scheduled_frame",
            "sample_step_update_frame_policy": "applied_before_rendering_scheduled_frame",
            "gain_pan_update_frame_policy": "ramp_starts_on_scheduled_frame",
            "volume_column_update_frame_policy": "applied_before_rendering_scheduled_frame",
            "c_mixer_voice_state_event_policy": "scheduled_events_apply_before_mixing_each_frame",
            "runtime_callback_policy": "render_until_event_frame_then_apply_same_frame_burst_before_rendering_event_frame",
            "same_frame_event_order": [
                "gain_pan_update",
                "sample_step_update",
                "note_cut",
                "note_trigger",
            ],
        ]
    }

    private static func rowTimingJSON(
        _ diagnostic: PlaybackSongSyntheticRowTimingDiagnostic,
        sampleRate: Double
    ) -> [String: Any] {
        let framesPerTick = sampleRate * 2.5 / Double(max(1, diagnostic.effectiveBPM))
        return [
            "source": positionJSON(diagnostic.source),
            "synthetic_row": diagnostic.syntheticRow,
            "row_start_exact_frame": diagnostic.rowStartExactFrame,
            "row_end_exact_frame": diagnostic.rowEndExactFrame,
            "row_start_frame": diagnostic.rowStartFrame,
            "row_end_frame": diagnostic.rowStartFrame + diagnostic.rowDurationFrames,
            "row_duration_frames": diagnostic.rowDurationFrames,
            "row_duration_exact_frames": diagnostic.rowEndExactFrame - diagnostic.rowStartExactFrame,
            "frames_per_tick": framesPerTick,
            "tick_start_frame_policy": "floor(row_start_exact_frame + tick * frames_per_tick)",
            "row_start_frame_policy": "floor(accumulated_exact_row_start)",
            "row_end_frame_policy": "floor(accumulated_exact_row_end)",
            "fractional_frame_accumulation": true,
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
        let axyUpdates = updates.filter(isAxyVolumeSlideUpdate)
        let firstAxyCoordinates: [String: Any]? = axyUpdates.first.map { update in
            [
                "source": positionJSON(update.source),
                "channel_index": update.channelIndex,
                "synthetic_row": update.syntheticRow,
                "synthetic_tick": update.syntheticTick,
                "scheduled_frame": update.scheduledFrame,
            ]
        }
        let axyMixedNibblePolicy = axyUpdates.first {
            $0.volumeSlideBothNibblesNonzero == true
        }?.volumeSlidePolicy ?? "up_nibble_precedence_mikmod_observed"
        let axyTick0SuppressedCoordinateCount = Set(axyUpdates.filter {
            $0.volumeSlideTick0Suppressed == true
        }.map {
            "\($0.source.orderIndex):\($0.source.patternIndex):\($0.source.rowIndex):\($0.channelIndex)"
        }).count
        return [
            "total_state_updates": updates.count,
            "applied_count": count(\.applied),
            "deferred_count": count(\.deferred),
            "ignored_no_op_count": count(\.ignoredAsNoOp),
            "active_voice_updated_count": count(\.activeVoiceUpdated),
            "active_voice_not_updated_count": count { !$0.activeVoiceUpdated },
            "gain_pan_ramp_enabled": true,
            "gain_pan_ramp_frame_count": CSoftwareMixer.gainPanUpdateRampFrameCount,
            "gain_pan_update_count": changedVoiceStateUpdateCount(updates),
            "gain_pan_ramped_update_count": changedVoiceStateUpdateCount(updates),
            "gain_pan_interrupted_ramp_count": interruptedRampCount(updates),
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
            "axy_volume_slide_no_active_voice": count {
                isAxyVolumeSlideUpdate($0) && isAxyVolumeSlideNoActiveVoice($0)
            },
            "axy_volume_slide_ignored_no_op": count {
                $0.ignoredAsNoOp && isAxyVolumeSlideUpdate($0)
            },
            "axy_volume_slide_scheduled_gain_update_count": count {
                isAxyVolumeSlideUpdate($0) && isChangedGainStateUpdate($0)
            },
            "axy_tick_level_updates": count {
                $0.applied && isAxyVolumeSlideUpdate($0) && $0.syntheticTick > 0
            },
            "axy_tick0_suppressed": axyTick0SuppressedCoordinateCount,
            "axy_mixed_nibble_policy": axyMixedNibblePolicy,
            "first_axy_coordinates": firstAxyCoordinates.map { $0 as Any } ?? NSNull(),
            "eax_fine_volume_slide_up_applied": count {
                $0.applied && isEaxFineVolumeSlideUpdate($0)
            },
            "eax_fine_volume_slide_up_deferred": count {
                $0.deferred && isEaxFineVolumeSlideUpdate($0)
            },
            "eax_fine_volume_slide_up_no_active_voice": count {
                isEaxFineVolumeSlideUpdate($0) && isFineVolumeSlideNoActiveVoice($0)
            },
            "eax_fine_volume_slide_up_zero_amount_effect_memory_deferred": count {
                isEaxFineVolumeSlideUpdate($0) && isFineVolumeSlideZeroAmountNoOp($0)
            },
            "eax_fine_volume_slide_up_scheduled_gain_update_count": count {
                isEaxFineVolumeSlideUpdate($0) && isChangedGainStateUpdate($0)
            },
            "ebx_fine_volume_slide_down_applied": count {
                $0.applied && isEbxFineVolumeSlideUpdate($0)
            },
            "ebx_fine_volume_slide_down_deferred": count {
                $0.deferred && isEbxFineVolumeSlideUpdate($0)
            },
            "ebx_fine_volume_slide_down_no_active_voice": count {
                isEbxFineVolumeSlideUpdate($0) && isFineVolumeSlideNoActiveVoice($0)
            },
            "ebx_fine_volume_slide_down_zero_amount_effect_memory_deferred": count {
                isEbxFineVolumeSlideUpdate($0) && isFineVolumeSlideZeroAmountNoOp($0)
            },
            "ebx_fine_volume_slide_down_scheduled_gain_update_count": count {
                isEbxFineVolumeSlideUpdate($0) && isChangedGainStateUpdate($0)
            },
            "vibrato_volume_slide_6xy_volume_slide_applied": count {
                $0.applied && is6xyVolumeSlideUpdate($0)
            },
            "vibrato_volume_slide_6xy_volume_slide_deferred": count {
                $0.deferred && is6xyVolumeSlideUpdate($0)
            },
            "vibrato_volume_slide_6xy_no_active_voice": count {
                is6xyVolumeSlideUpdate($0) && is6xyVolumeSlideNoActiveVoice($0)
            },
            "vibrato_volume_slide_6xy_zero_param_effect_memory_deferred": count {
                is6xyVolumeSlideUpdate($0) && is6xyVolumeSlideZeroParamNoOp($0)
            },
            "vibrato_volume_slide_6xy_scheduled_gain_update_count": count {
                is6xyVolumeSlideUpdate($0) && isChangedGainStateUpdate($0)
            },
            "gxx_set_global_volume_applied": count {
                $0.applied && isGxxSetGlobalVolumeUpdate($0)
            },
            "gxx_set_global_volume_active_voice_update_count": count {
                $0.activeVoiceUpdated && isGxxSetGlobalVolumeUpdate($0)
            },
            "hxy_global_volume_slide_applied": count {
                $0.applied && isHxyGlobalVolumeSlideUpdate($0)
            },
            "hxy_global_volume_slide_deferred": count {
                $0.deferred && isHxyGlobalVolumeSlideUpdate($0)
            },
            "hxy_global_volume_slide_ignored_no_op": count {
                $0.ignoredAsNoOp && isHxyGlobalVolumeSlideUpdate($0)
            },
            "hxy_global_volume_slide_active_voice_update_count": count {
                $0.activeVoiceUpdated && isHxyGlobalVolumeSlideUpdate($0)
            },
            "hxy_global_volume_slide_clamped_count": count {
                isHxyGlobalVolumeSlideUpdate($0) && $0.globalVolumeSlideClamped == true
            },
            "hxy_global_volume_slide_both_nibbles_nonzero_count": count {
                isHxyGlobalVolumeSlideUpdate($0) && $0.globalVolumeSlideBothNibblesNonzero == true
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

    private static func isGxxSetGlobalVolumeUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .gxxSetGlobalVolume = update.command {
            return true
        }
        return false
    }

    private static func isEaxFineVolumeSlideUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .eaxFineVolumeSlideUp = update.command {
            return true
        }
        return false
    }

    private static func isEbxFineVolumeSlideUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .ebxFineVolumeSlideDown = update.command {
            return true
        }
        return false
    }

    private static func is6xyVolumeSlideUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        if case .effect6xyVolumeSlide = update.command {
            return true
        }
        return false
    }

    private static func isFineVolumeSlideNoActiveVoice(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        (isEaxFineVolumeSlideUpdate(update) || isEbxFineVolumeSlideUpdate(update)) &&
            update.applied &&
            update.cellNote == 0 &&
            !update.activeVoiceUpdated
    }

    private static func isAxyVolumeSlideNoActiveVoice(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        isAxyVolumeSlideUpdate(update) &&
            update.applied &&
            !update.activeVoiceUpdated
    }

    private static func isFineVolumeSlideZeroAmountNoOp(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        guard update.ignoredAsNoOp else {
            return false
        }
        switch update.command {
        case let .eaxFineVolumeSlideUp(amount),
             let .ebxFineVolumeSlideDown(amount):
            return amount == 0
        default:
            return false
        }
    }

    private static func is6xyVolumeSlideNoActiveVoice(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        is6xyVolumeSlideUpdate(update) &&
            update.applied &&
            update.cellNote == 0 &&
            !update.activeVoiceUpdated
    }

    private static func is6xyVolumeSlideZeroParamNoOp(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        guard update.ignoredAsNoOp else {
            return false
        }
        if case let .effect6xyVolumeSlide(up, down) = update.command {
            return up == 0 && down == 0
        }
        return false
    }

    private static func isChangedGainStateUpdate(
        _ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Bool {
        update.activeVoiceUpdated && update.gainBefore != update.gainAfter
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
            "cell_note_text": noteText(update.cellNote),
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
            "gain_pan_ramp_enabled": update.activeVoiceUpdated && (update.gainBefore != update.gainAfter || update.panBefore != update.panAfter),
            "gain_pan_ramp_frame_count": CSoftwareMixer.gainPanUpdateRampFrameCount,
        ]
        put(update.rawVolumeColumn.map { Int($0) }, forKey: "raw_volume_column", into: &object)
        put(update.effectType.map { Int($0) }, forKey: "effect_type", into: &object)
        put(update.effectParam.map { Int($0) }, forKey: "effect_param", into: &object)
        put(update.behavior.map(volumeColumnBehaviorName), forKey: "behavior", into: &object)
        put(update.targetChannelIndex, forKey: "target_channel_index", into: &object)
        put(update.activeEventIndex, forKey: "active_event_index", into: &object)
        put(update.effectiveVolumeBefore, forKey: "effective_volume_before", into: &object)
        put(update.effectiveVolumeAfter, forKey: "effective_volume_after", into: &object)
        put(update.effectivePanBefore.map { Double($0) }, forKey: "effective_pan_before", into: &object)
        put(update.effectivePanAfter.map { Double($0) }, forKey: "effective_pan_after", into: &object)
        put(update.globalVolumeBefore, forKey: "global_volume_before", into: &object)
        put(update.globalVolumeAfter, forKey: "global_volume_after", into: &object)
        put(update.globalVolumeMultiplierBefore.map { Double($0) }, forKey: "global_volume_multiplier_before", into: &object)
        put(update.globalVolumeMultiplierAfter.map { Double($0) }, forKey: "global_volume_multiplier_after", into: &object)
        put(update.globalVolumeSlideDirection?.rawValue, forKey: "global_volume_slide_direction", into: &object)
        put(update.globalVolumeSlideAmount, forKey: "global_volume_slide_amount", into: &object)
        put(update.globalVolumeSlideClamped, forKey: "global_volume_slide_clamped", into: &object)
        put(update.globalVolumeSlideBothNibblesNonzero, forKey: "global_volume_slide_both_nibbles_nonzero", into: &object)
        put(update.globalVolumeSlidePolicy, forKey: "global_volume_slide_policy", into: &object)
        put(update.gainBefore.map { Double($0) }, forKey: "gain_before", into: &object)
        put(update.gainAfter.map { Double($0) }, forKey: "gain_after", into: &object)
        put(update.panBefore.map { Double($0) }, forKey: "pan_before", into: &object)
        put(update.panAfter.map { Double($0) }, forKey: "pan_after", into: &object)
        switch update.command {
        case let .axyVolumeSlide(up, down):
            let rawUp = update.volumeSlideRawUpNibble ?? update.effectParam.map { Int(($0 & 0xF0) >> 4) }
            let rawDown = update.volumeSlideRawDownNibble ?? update.effectParam.map { Int($0 & 0x0F) }
            let bothNibblesNonzero = update.volumeSlideBothNibblesNonzero ?? ((rawUp ?? 0) > 0 && (rawDown ?? 0) > 0)
            let policy = update.volumeSlidePolicy ?? (bothNibblesNonzero ? "up_nibble_precedence_mikmod_observed" : "single_nonzero_nibble")
            object["volume_slide_up"] = up
            object["volume_slide_down"] = down
            object["volume_slide_amount"] = max(up, down)
            object["volume_slide_direction"] = up > 0 ? "up" : (down > 0 ? "down" : "none")
            object["volume_slide_raw_up_nibble"] = rawUp.map { $0 as Any } ?? NSNull()
            object["volume_slide_raw_down_nibble"] = rawDown.map { $0 as Any } ?? NSNull()
            object["volume_slide_both_nibbles_nonzero"] = bothNibblesNonzero
            object["volume_slide_policy"] = policy
            object["volume_slide_clamped"] = update.volumeSlideClamped.map { $0 as Any } ?? NSNull()
            object["volume_slide_tick0_suppressed"] = update.volumeSlideTick0Suppressed.map { $0 as Any } ?? NSNull()
            object["volume_slide_row_speed"] = update.volumeSlideRowSpeed.map { $0 as Any } ?? NSNull()
            object["axy_tick_level_update"] = update.applied && update.syntheticTick > 0
            object["axy_tick0_suppressed"] = update.volumeSlideTick0Suppressed.map { $0 as Any } ?? NSNull()
            object["axy_mixed_nibble_policy"] = policy
            object["axy_volume_before_tick"] = update.effectiveVolumeBefore.map { $0 as Any } ?? NSNull()
            object["axy_volume_after_tick"] = update.effectiveVolumeAfter.map { $0 as Any } ?? NSNull()
            object["scheduled_gain_update_count"] = isChangedGainStateUpdate(update) ? 1 : 0
        case let .eaxFineVolumeSlideUp(amount):
            object["fine_volume_slide_direction"] = "up"
            object["fine_amount"] = amount
            object["fine_amount_nibble"] = amount
            object["effect_memory_deferred"] = update.ignoredAsNoOp && amount == 0
            object["no_active_voice"] = isFineVolumeSlideNoActiveVoice(update)
        case let .ebxFineVolumeSlideDown(amount):
            object["fine_volume_slide_direction"] = "down"
            object["fine_amount"] = amount
            object["fine_amount_nibble"] = amount
            object["effect_memory_deferred"] = update.ignoredAsNoOp && amount == 0
            object["no_active_voice"] = isFineVolumeSlideNoActiveVoice(update)
        case let .effect6xyVolumeSlide(up, down):
            object["volume_slide_up"] = up
            object["volume_slide_down"] = down
            object["volume_slide_amount"] = max(up, down)
            object["volume_slide_direction"] = up > 0 ? "up" : (down > 0 ? "down" : "none")
            object["effect_memory_deferred"] = update.ignoredAsNoOp && up == 0 && down == 0
            object["no_active_voice"] = is6xyVolumeSlideNoActiveVoice(update)
        default:
            break
        }
        return object
    }

    private static func ignoredCellJSON(_ cell: PlaybackSongSyntheticIgnoredCell) -> [String: Any] {
        [
            "source": positionJSON(cell.source),
            "channel_index": cell.channelIndex,
            "note": Int(cell.note),
            "note_text": noteText(cell.note),
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
            "note_text": noteText(field.note),
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
            "effect_memory_reused": diagnostic.effectMemoryReused,
            "effect_memory_missing": diagnostic.effectMemoryMissing,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "memory_source": diagnostic.memorySource.map(effectMemorySourceJSON) ?? NSNull(),
            "memory_source_effect_type": diagnostic.memorySource.map { Int($0.effectType) as Any } ?? NSNull(),
            "memory_source_effect_param": diagnostic.memorySource.map { Int($0.effectParam) as Any } ?? NSNull(),
            "memory_target_effect_type": Int(diagnostic.effectType),
            "memory_target_effect_param": Int(diagnostic.effectParam),
            "memory_unavailable_reason": diagnostic.memoryUnavailableReason.map { $0 as Any } ?? NSNull(),
            "900_sample_offset_memory_applied": diagnostic.effectType == 0x09 &&
                diagnostic.effectParam == 0 &&
                diagnostic.applied &&
                diagnostic.effectMemoryReused,
        ]
    }

    private static func setFinetuneDiagnosticJSON(_ diagnostic: PlaybackSongSyntheticSetFinetuneDiagnostic) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": setFinetuneStatusName(diagnostic.status),
            "current_status": setFinetuneStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "finetune_nibble": diagnostic.finetuneNibble,
            "sample_finetune": diagnostic.sampleFinetune.map { $0 as Any } ?? NSNull(),
            "effective_finetune": diagnostic.effectiveFinetune.map { $0 as Any } ?? NSNull(),
            "linear_period": diagnostic.linearPeriod.map { $0 as Any } ?? NSNull(),
            "linear_frequency": diagnostic.linearFrequency.map { $0 as Any } ?? NSNull(),
            "playback_step": diagnostic.playbackStep.map { $0 as Any } ?? NSNull(),
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "policy": diagnostic.policy,
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

    private static func retriggerDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticRetriggerDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": retriggerStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "out_of_row": diagnostic.outOfRow,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_sample_found": diagnostic.activeVoiceFound,
            "retrigger_interval_ticks": diagnostic.retriggerIntervalTicks,
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "retrigger_ticks": diagnostic.retriggerTicks,
            "retrigger_frames": diagnostic.retriggerFrames,
            "generated_retrigger_frames": diagnostic.retriggerFrames,
            "retrigger_event_indices": diagnostic.retriggerEventIndices,
            "replaced_event_indices": diagnostic.replacedEventIndices,
            "active_event_index_before": diagnostic.activeEventIndexBefore.map { $0 as Any } ?? NSNull(),
            "selected_sample_index": diagnostic.selectedSampleIndex.map { $0 as Any } ?? NSNull(),
            "selected_sample_length": diagnostic.selectedSampleLength.map { $0 as Any } ?? NSNull(),
            "initial_source_frame": diagnostic.initialSourceFrame.map { $0 as Any } ?? NSNull(),
            "playback_step": diagnostic.playbackStep.map { $0 as Any } ?? NSNull(),
            "gain": diagnostic.gain.map { $0 as Any } ?? NSNull(),
            "pan": diagnostic.pan.map { $0 as Any } ?? NSNull(),
            "envelope_policy": diagnostic.envelopePolicy,
        ]
    }

    private static func tonePortamentoDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticTonePortamentoDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": tonePortamentoStatusName(diagnostic.status),
            "current_status": tonePortamentoStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "same_cell_note": diagnostic.sameCellNote,
            "note_trigger_event_created": diagnostic.noteTriggerEventCreated,
            "voice_replacement": diagnostic.voiceReplacement,
            "sample_position_reset": diagnostic.samplePositionReset,
            "instrument_state_updated": diagnostic.instrumentStateUpdated,
            "instrument_index_before": diagnostic.instrumentIndexBefore.map { $0 as Any } ?? NSNull(),
            "instrument_index_after": diagnostic.instrumentIndexAfter.map { $0 as Any } ?? NSNull(),
            "sample_selected_before": diagnostic.sampleSelectedBefore.map { $0 as Any } ?? NSNull(),
            "sample_selected_after": diagnostic.sampleSelectedAfter.map { $0 as Any } ?? NSNull(),
            "instrument_default_volume_applied": diagnostic.instrumentDefaultVolumeApplied,
            "envelope_reset": diagnostic.envelopeReset,
            "envelope_reset_modeled": diagnostic.envelopeResetModeled,
            "channel_volume_before": diagnostic.channelVolumeBefore.map { $0 as Any } ?? NSNull(),
            "channel_volume_after": diagnostic.channelVolumeAfter.map { $0 as Any } ?? NSNull(),
            "gain_before": diagnostic.gainBefore.map { Double($0) as Any } ?? NSNull(),
            "gain_after": diagnostic.gainAfter.map { Double($0) as Any } ?? NSNull(),
            "note_target_before": diagnostic.noteTargetBefore.map { Int($0) as Any } ?? NSNull(),
            "note_target_after": diagnostic.noteTargetAfter.map { Int($0) as Any } ?? NSNull(),
            "note_target_before_text": diagnostic.noteTargetBefore.map(noteText) ?? NSNull(),
            "note_target_after_text": diagnostic.noteTargetAfter.map(noteText) ?? NSNull(),
            "audible_transient_expected": diagnostic.audibleTransientExpected,
            "c_mixer_received_new_voice": diagnostic.cMixerReceivesNewVoice,
            "c_mixer_received_only_state_updates": diagnostic.cMixerReceivesOnlyStateUpdates,
            "target_exists_before": diagnostic.targetExistsBefore,
            "target_exists_after": diagnostic.targetExistsAfter,
            "target_note": diagnostic.targetNote.map { Int($0) as Any } ?? NSNull(),
            "target_note_text": diagnostic.targetNote.map(noteText) ?? NSNull(),
            "target_linear_period": diagnostic.targetLinearPeriod.map { $0 as Any } ?? NSNull(),
            "target_step": diagnostic.targetPlaybackStep.map { $0 as Any } ?? NSNull(),
            "target_playback_step": diagnostic.targetPlaybackStep.map { $0 as Any } ?? NSNull(),
            "current_linear_period_before": diagnostic.currentLinearPeriodBefore.map { $0 as Any } ?? NSNull(),
            "current_linear_period_after": diagnostic.currentLinearPeriodAfter.map { $0 as Any } ?? NSNull(),
            "current_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "current_playback_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_playback_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "portamento_speed": diagnostic.portamentoSpeed,
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "step_update_count": diagnostic.stepUpdates.count,
            "step_updates": diagnostic.stepUpdates.map(tonePortamentoStepUpdateJSON),
            "policy": diagnostic.policy,
        ]
    }

    private static func portamentoSlideDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticPortamentoSlideDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": portamentoSlideStatusName(diagnostic.status),
            "current_status": portamentoSlideStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "effect_memory_reused": diagnostic.effectMemoryReused,
            "effect_memory_missing": diagnostic.effectMemoryMissing,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "memory_source": diagnostic.memorySource.map(effectMemorySourceJSON) ?? NSNull(),
            "memory_source_effect_type": diagnostic.memorySource.map { Int($0.effectType) as Any } ?? NSNull(),
            "memory_source_effect_param": diagnostic.memorySource.map { Int($0.effectParam) as Any } ?? NSNull(),
            "memory_target_effect_type": Int(diagnostic.effectType),
            "memory_target_effect_param": Int(diagnostic.effectParam),
            "memory_unavailable_reason": diagnostic.memoryUnavailableReason.map { $0 as Any } ?? NSNull(),
            "portamento_1xx_memory_reused": diagnostic.direction == .up &&
                diagnostic.applied &&
                diagnostic.effectMemoryReused,
            "portamento_2xx_memory_reused": diagnostic.direction == .down &&
                diagnostic.applied &&
                diagnostic.effectMemoryReused,
            "portamento_memory_missing": diagnostic.effectMemoryMissing,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "slide_direction": diagnostic.direction.rawValue,
            "slide_amount": diagnostic.slideAmount,
            "current_linear_period_before": diagnostic.currentLinearPeriodBefore.map { $0 as Any } ?? NSNull(),
            "current_linear_period_after": diagnostic.currentLinearPeriodAfter.map { $0 as Any } ?? NSNull(),
            "current_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "current_playback_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_playback_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "step_update_count": diagnostic.stepUpdates.count,
            "scheduled_sample_step_update_count": diagnostic.stepUpdates.count,
            "step_updates": diagnostic.stepUpdates.map(tonePortamentoStepUpdateJSON),
            "clamped": diagnostic.clamped,
            "policy": diagnostic.policy,
        ]
    }

    private static func finePortamentoUpDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticFinePortamentoUpDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": finePortamentoUpStatusName(diagnostic.status),
            "current_status": finePortamentoUpStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "fine_amount": diagnostic.fineAmount,
            "fine_amount_nibble": diagnostic.fineAmountNibble,
            "current_linear_period_before": diagnostic.currentLinearPeriodBefore.map { $0 as Any } ?? NSNull(),
            "current_linear_period_after": diagnostic.currentLinearPeriodAfter.map { $0 as Any } ?? NSNull(),
            "current_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "current_playback_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_playback_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "scheduled_frame": diagnostic.scheduledFrame.map { $0 as Any } ?? NSNull(),
            "applied_to_initial_playback_step": diagnostic.appliedToInitialPlaybackStep,
            "active_voice_update_count": diagnostic.applied ? diagnostic.stepUpdates.count : 0,
            "scheduled_sample_step_update_count": diagnostic.stepUpdates.count,
            "step_update_count": diagnostic.stepUpdates.count,
            "step_updates": diagnostic.stepUpdates.map(tonePortamentoStepUpdateJSON),
            "clamped": diagnostic.clamped,
            "policy": diagnostic.policy,
        ]
    }

    private static func finePortamentoDownDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticFinePortamentoDownDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "status": finePortamentoDownStatusName(diagnostic.status),
            "current_status": finePortamentoDownStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "fine_amount": diagnostic.fineAmount,
            "fine_amount_nibble": diagnostic.fineAmountNibble,
            "current_linear_period_before": diagnostic.currentLinearPeriodBefore.map { $0 as Any } ?? NSNull(),
            "current_linear_period_after": diagnostic.currentLinearPeriodAfter.map { $0 as Any } ?? NSNull(),
            "current_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "current_playback_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_playback_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "scheduled_frame": diagnostic.scheduledFrame.map { $0 as Any } ?? NSNull(),
            "applied_to_initial_playback_step": diagnostic.appliedToInitialPlaybackStep,
            "active_voice_update_count": diagnostic.applied ? diagnostic.stepUpdates.count : 0,
            "scheduled_sample_step_update_count": diagnostic.stepUpdates.count,
            "step_update_count": diagnostic.stepUpdates.count,
            "step_updates": diagnostic.stepUpdates.map(tonePortamentoStepUpdateJSON),
            "clamped": diagnostic.clamped,
            "policy": diagnostic.policy,
        ]
    }

    private static func vibratoDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticVibratoDiagnostic
    ) -> [String: Any] {
        let memorySource = diagnostic.vibratoSpeedMemorySource ?? diagnostic.vibratoDepthMemorySource
        return [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "effect_label": diagnostic.effectType == 0x06 ? "6xy vibrato + volume slide" : "4xy vibrato",
            "decoded_label": diagnostic.effectType == 0x06 ? "6xy vibrato + volume slide" : "4xy vibrato",
            "status": vibratoStatusName(diagnostic.status),
            "current_status": vibratoStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "vibrato_speed": diagnostic.vibratoSpeed,
            "speed": diagnostic.vibratoSpeed,
            "vibrato_depth": diagnostic.vibratoDepth,
            "depth": diagnostic.vibratoDepth,
            "vibrato_speed_source": diagnostic.vibratoSpeedSource.map { $0 as Any } ?? NSNull(),
            "vibrato_depth_source": diagnostic.vibratoDepthSource.map { $0 as Any } ?? NSNull(),
            "vibrato_control_value": diagnostic.vibratoControlValue,
            "vibrato_waveform": diagnostic.vibratoWaveform,
            "vibrato_waveform_source": diagnostic.vibratoWaveformSource,
            "effect_memory_reused": diagnostic.effectMemoryReused,
            "effect_memory_missing": diagnostic.effectMemoryMissing,
            "effect_memory_deferred": diagnostic.effectMemoryDeferred,
            "vibrato_speed_memory_source": diagnostic.vibratoSpeedMemorySource.map(effectMemorySourceJSON) ?? NSNull(),
            "vibrato_depth_memory_source": diagnostic.vibratoDepthMemorySource.map(effectMemorySourceJSON) ?? NSNull(),
            "vibrato_speed_memory_source_effect_type": diagnostic.vibratoSpeedMemorySource.map { Int($0.effectType) as Any } ?? NSNull(),
            "vibrato_speed_memory_source_effect_param": diagnostic.vibratoSpeedMemorySource.map { Int($0.effectParam) as Any } ?? NSNull(),
            "vibrato_depth_memory_source_effect_type": diagnostic.vibratoDepthMemorySource.map { Int($0.effectType) as Any } ?? NSNull(),
            "vibrato_depth_memory_source_effect_param": diagnostic.vibratoDepthMemorySource.map { Int($0.effectParam) as Any } ?? NSNull(),
            "memory_source_effect_type": memorySource.map { Int($0.effectType) as Any } ?? NSNull(),
            "memory_source_effect_param": memorySource.map { Int($0.effectParam) as Any } ?? NSNull(),
            "memory_target_effect_type": Int(diagnostic.effectType),
            "memory_target_effect_param": Int(diagnostic.effectParam),
            "memory_unavailable_reason": diagnostic.memoryUnavailableReason.map { $0 as Any } ?? NSNull(),
            "4xy_vibrato_memory_applied": diagnostic.effectType == 0x04 &&
                diagnostic.applied &&
                diagnostic.effectMemoryReused,
            "6xy_vibrato_memory_applied": diagnostic.effectType == 0x06 &&
                diagnostic.applied &&
                diagnostic.effectMemoryReused,
            "volume_slide_up": diagnostic.volumeSlideUp.map { $0 as Any } ?? NSNull(),
            "volume_slide_down": diagnostic.volumeSlideDown.map { $0 as Any } ?? NSNull(),
            "volume_slide_amount": diagnostic.volumeSlideAmount.map { $0 as Any } ?? NSNull(),
            "volume_slide_direction": diagnostic.volumeSlideDirection.map { $0 as Any } ?? NSNull(),
            "phase_before": diagnostic.phaseBefore,
            "phase_after": diagnostic.phaseAfter,
            "current_linear_period_before": diagnostic.currentLinearPeriodBefore.map { $0 as Any } ?? NSNull(),
            "current_linear_period_after": diagnostic.currentLinearPeriodAfter.map { $0 as Any } ?? NSNull(),
            "current_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "current_playback_step_before": diagnostic.currentPlaybackStepBefore.map { $0 as Any } ?? NSNull(),
            "current_playback_step_after": diagnostic.currentPlaybackStepAfter.map { $0 as Any } ?? NSNull(),
            "row_speed": diagnostic.rowSpeed,
            "row_bpm": diagnostic.rowBPM,
            "active_voice_update_count": diagnostic.applied ? diagnostic.stepUpdates.count : 0,
            "scheduled_sample_step_update_count": diagnostic.stepUpdates.count,
            "step_update_count": diagnostic.stepUpdates.count,
            "step_updates": diagnostic.stepUpdates.map(tonePortamentoStepUpdateJSON),
            "policy": diagnostic.policy,
        ]
    }

    private static func vibratoControlDiagnosticJSON(
        _ diagnostic: PlaybackSongSyntheticVibratoControlDiagnostic
    ) -> [String: Any] {
        [
            "source": positionJSON(diagnostic.source),
            "channel_index": diagnostic.channelIndex,
            "synthetic_row": diagnostic.syntheticRow,
            "synthetic_tick": diagnostic.syntheticTick,
            "effect_type": Int(diagnostic.effectType),
            "effect_param": Int(diagnostic.effectParam),
            "effect_label": "E4x vibrato control",
            "decoded_label": "E4x vibrato control",
            "status": vibratoControlStatusName(diagnostic.status),
            "current_status": vibratoControlStatusName(diagnostic.status),
            "detected": diagnostic.detected,
            "applied": diagnostic.applied,
            "stored": diagnostic.stored,
            "deferred": diagnostic.deferred,
            "ignored_as_no_op": diagnostic.ignoredAsNoOp,
            "active_voice_found": diagnostic.activeVoiceFound,
            "active_event_index": diagnostic.activeEventIndex.map { $0 as Any } ?? NSNull(),
            "active_event_mapping_index": diagnostic.activeEventMappingIndex.map { $0 as Any } ?? NSNull(),
            "control_value": diagnostic.controlValue,
            "vibrato_control_value": diagnostic.controlValue,
            "waveform_id": diagnostic.waveformID,
            "waveform_name": diagnostic.waveformName,
            "vibrato_waveform": diagnostic.waveformName,
            "retrigger_suppressed": diagnostic.retriggerSuppressed,
            "unsupported_waveform": diagnostic.unsupportedWaveform,
            "affects_later_4xy_6xy": diagnostic.affectsLaterVibrato,
            "policy": diagnostic.policy,
        ]
    }

    private static func tonePortamentoStepUpdateJSON(
        _ update: PlaybackSongSyntheticTonePortamentoStepUpdate
    ) -> [String: Any] {
        [
            "synthetic_tick": update.syntheticTick,
            "scheduled_frame": update.scheduledFrame,
            "absolute_frame": update.scheduledFrame,
            "linear_period_before": update.linearPeriodBefore,
            "linear_period_after": update.linearPeriodAfter,
            "playback_step_before": update.playbackStepBefore,
            "playback_step_after": update.playbackStepAfter,
            "current_step_before": update.playbackStepBefore,
            "current_step_after": update.playbackStepAfter,
            "reached_target": update.reachedTarget,
            "clamped": update.clamped,
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

    private static func effectMemorySourceJSON(_ source: PlaybackSongSyntheticEffectMemorySource) -> [String: Any] {
        [
            "source": positionJSON(source.source),
            "channel_index": source.channelIndex,
            "effect_type": Int(source.effectType),
            "effect_param": Int(source.effectParam),
        ]
    }

    private static func noteText(_ note: UInt8) -> String {
        ModuleMetadataLoader.formatXMNote(note)
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
        case let .instrumentDefaultVolume(value):
            return ["name": "instrumentDefaultVolume", "label": command.label, "value": value]
        case let .cxxSetVolume(value):
            return ["name": "cxxSetVolume", "label": command.label, "value": value]
        case let .effect8xxSetPanning(value):
            return ["name": "effect8xxSetPanning", "label": command.label, "value": value]
        case let .axyVolumeSlide(up, down):
            return ["name": "axyVolumeSlide", "label": command.label, "up": up, "down": down]
        case let .gxxSetGlobalVolume(value):
            return ["name": "gxxSetGlobalVolume", "label": command.label, "value": value]
        case let .hxyGlobalVolumeSlide(up, down):
            return ["name": "hxyGlobalVolumeSlide", "label": command.label, "up": up, "down": down]
        case let .eaxFineVolumeSlideUp(amount):
            return [
                "name": "eaxFineVolumeSlideUp",
                "label": command.label,
                "amount": amount,
                "fine_amount_nibble": amount,
            ]
        case let .ebxFineVolumeSlideDown(amount):
            return [
                "name": "ebxFineVolumeSlideDown",
                "label": command.label,
                "amount": amount,
                "fine_amount_nibble": amount,
            ]
        case let .effect6xyVolumeSlide(up, down):
            return [
                "name": "effect6xyVolumeSlide",
                "label": command.label,
                "up": up,
                "down": down,
                "amount": max(up, down),
            ]
        }
    }

    private static func voiceStateCommandName(
        _ command: PlaybackSongSyntheticVoiceStateUpdateCommand
    ) -> String {
        switch command {
        case let .volumeColumn(command):
            return command.name
        case .instrumentDefaultVolume:
            return "instrumentDefaultVolume"
        case .cxxSetVolume:
            return "cxxSetVolume"
        case .effect8xxSetPanning:
            return "effect8xxSetPanning"
        case .axyVolumeSlide:
            return "axyVolumeSlide"
        case .gxxSetGlobalVolume:
            return "gxxSetGlobalVolume"
        case .hxyGlobalVolumeSlide:
            return "hxyGlobalVolumeSlide"
        case .eaxFineVolumeSlideUp:
            return "eaxFineVolumeSlideUp"
        case .ebxFineVolumeSlideDown:
            return "ebxFineVolumeSlideDown"
        case .effect6xyVolumeSlide:
            return "effect6xyVolumeSlide"
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

    private static func normalizedVolumeMultiplier(_ value: Int) -> Float {
        Float(min(64, max(0, value))) / 64.0
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
        case .tickLevelAfterTick0:
            return "tick_level_after_tick0"
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

    private static func setFinetuneStatusName(_ status: PlaybackSongSyntheticSetFinetuneDiagnostic.Status) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noNoteDeferred:
            return "no_note_deferred"
        case .noActiveVoice:
            return "no_active_voice"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
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

    private static func retriggerStatusName(_ status: PlaybackSongSyntheticRetriggerDiagnostic.Status) -> String {
        switch status {
        case .applied:
            return "applied"
        case .ignoredE90NoEffectMemory:
            return "ignored_e90_no_effect_memory"
        case .noActiveVoice:
            return "no_active_voice"
        case .outOfRowNoOp:
            return "out_of_row_no_op"
        }
    }

    private static func tonePortamentoStatusName(
        _ status: PlaybackSongSyntheticTonePortamentoDiagnostic.Status
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .noTarget:
            return "no_target"
        case .noSpeed:
            return "no_speed"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
        }
    }

    private static func portamentoSlideStatusName(
        _ status: PlaybackSongSyntheticPortamentoSlideDiagnostic.Status
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .zeroParamEffectMemoryDeferred:
            return "zero_param_effect_memory_deferred"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
        }
    }

    private static func finePortamentoDownStatusName(
        _ status: PlaybackSongSyntheticFinePortamentoDownDiagnostic.Status
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .zeroAmountEffectMemoryDeferred:
            return "zero_amount_effect_memory_deferred"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
        }
    }

    private static func arpeggioStatusName(
        _ status: PlaybackSongSyntheticArpeggioDiagnostic.Status
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
        }
    }

    private static func finePortamentoUpStatusName(
        _ status: PlaybackSongSyntheticFinePortamentoUpDiagnostic.Status
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .zeroAmountEffectMemoryDeferred:
            return "zero_amount_effect_memory_deferred"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
        }
    }

    private static func vibratoStatusName(
        _ status: PlaybackSongSyntheticVibratoDiagnostic.Status
    ) -> String {
        switch status {
        case .applied:
            return "applied"
        case .noActiveVoice:
            return "no_active_voice"
        case .zeroParamEffectMemoryDeferred:
            return "zero_param_effect_memory_deferred"
        case .zeroSpeedOrDepthEffectMemoryDeferred:
            return "zero_speed_or_depth_effect_memory_deferred"
        case .unsupportedFrequencyTable:
            return "deferred/unsupported_frequency_table"
        case .outOfRange:
            return "out_of_range"
        }
    }

    private static func vibratoControlStatusName(
        _ status: PlaybackSongSyntheticVibratoControlDiagnostic.Status
    ) -> String {
        switch status {
        case .stored:
            return "stored"
        case .unsupportedWaveform:
            return "deferred/unsupported_waveform"
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
        case .invalidTarget:
            return "invalid_target"
        case .outOfRange:
            return "out_of_range"
        case .missingLoopStart:
            return "missing_loop_start"
        case .loopLimitHit:
            return "loop_limit_hit"
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
        case .instrumentState:
            return "instrument_state"
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
      --effect-coverage-json PATH
                            Optional compact effect coverage JSON path for summarize-xm-effect-coverage.py; prefer /tmp.
      --order N             Zero-based order index to render. Required.
      --order-count N       Number of playable orders to include. Default: 1.
      --rows N              Render this many flattened rows from the bounded range.
      --sample-rate HZ      Output sample rate. Default: 44100.
      --seconds N           Render this many seconds; converted to seconds * sample-rate frames.
      --max-frames N        Explicit maximum output frames.
      --until-song-end      Render to the bounded selected order-range end.
      --tail-seconds N      Add this many seconds after --until-song-end. Default: 0.
      --window-rows N       Opt into row-windowed offline scheduling for long local renders.
      --solo-channel N      Render only zero-based VTX channel N; timing/global planning remains full-song.
      --solo-instrument I   Render only one-based instrument I.
      --solo-sample I:S     Render only one-based instrument I and zero-based sample S.
      --gain N              Apply linear export gain before PCM16 conversion. Default: 1.0.
      --headroom-db N       Apply dB headroom before PCM16 conversion; value must be <= 0.
      --auto-headroom       Compute safe export gain from the rendered Float32 peak with a -1 dB margin.
      --allow-long-render   Required when --seconds/--max-frames exceeds the default safety clamp.
      --progress            Print render percentage and phase/status messages to stderr.
      --help                Show this help.

    Default safety clamp: \(PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount) frames (60 seconds at 44100 Hz).
    --gain, --headroom-db, and --auto-headroom are mutually exclusive and do not change mixer math or runtime playback.
    --progress reports render percentage by rendered frames or row windows, then a coarse WAV-writing phase.
    --until-song-end, --seconds, --max-frames, and --rows are mutually exclusive duration modes.
    --until-song-end uses the bounded adapter's selected order-range timing, including supported Fxx changes and focused Dxx/Bxx/E6x traversal; it is not full FT2/OpenMPT song loop/restart parity.
    --solo-channel may be combined with --solo-instrument or --solo-sample for local isolation diagnostics.
    Keep long outputs under /tmp or ignored scratch paths.
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
    let exportDiagnostics = result.exportDiagnostics ?? MixerWAVExporter.diagnostics(
        for: result.block,
        exportPolicy: arguments.exportPolicy(for: result.block)
    )
    let durationDiagnostics = renderDurationDiagnostics(from: result, arguments: arguments)
    var lines = [
        "Developer-only bounded XM candidate WAV render.",
        "Generated WAVs/reports/traces/screenshots are local artifacts and must not be committed.",
        "Offline C mixer rendering/export remains separate from CoreAudio runtime playback.",
        "Calculated song-end duration is bounded adapter duration, not full FT2/OpenMPT song loop/restart parity.",
        "Module: \(URL(fileURLWithPath: arguments.inputPath).standardizedFileURL.path)",
        "Output: \(URL(fileURLWithPath: arguments.outputPath).standardizedFileURL.path)",
    ]
    if let diagnosticsJSONPath = arguments.diagnosticsJSONPath {
        lines.append("Diagnostics JSON: \(URL(fileURLWithPath: diagnosticsJSONPath).standardizedFileURL.path)")
    }
    if let effectCoverageJSONPath = arguments.effectCoverageJSONPath {
        lines.append("Effect coverage JSON: \(URL(fileURLWithPath: effectCoverageJSONPath).standardizedFileURL.path)")
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
    lines.append(renderIsolationSummaryLine(result.request.isolationFilter))
    lines.append("Sample rate: \(Int(result.block.config.sampleRate)) Hz")
    lines.append("Render duration mode: \(durationDiagnostics.mode.summaryName)")
    if let calculatedSongEndFrames = durationDiagnostics.calculatedSongEndFrames {
        lines.append("Calculated song-end frames: \(calculatedSongEndFrames)")
    } else {
        lines.append("Calculated song-end frames: not applicable")
    }
    lines.append(String(format: "Tail: %.3f seconds (%d frames)", durationDiagnostics.tailSeconds, durationDiagnostics.tailFrames))
    lines.append("Effective frame cap: \(result.maximumFrameCount)")
    lines.append(String(format: "Effective duration cap: %.3f seconds", capDuration))
    if exportDiagnostics.autoHeadroomEnabled {
        lines.append(String(format: "Auto-headroom: enabled (safety margin %.3f dB)", exportDiagnostics.autoHeadroomSafetyDB ?? 0))
    } else {
        lines.append("Auto-headroom: disabled.")
    }
    lines.append(String(format: "Effective export gain: %.6f", exportDiagnostics.policy.gain))
    lines.append(String(format: "Computed export gain: %.6f (%.3f dB)", exportDiagnostics.computedExportGain, exportDiagnostics.computedHeadroomDB))
    if let headroomDB = exportDiagnostics.policy.headroomDB {
        lines.append(String(format: "Export headroom dB: %.3f", headroomDB))
    } else {
        lines.append("Export headroom dB: not specified")
    }
    let clampMode = arguments.usesDefaultRenderClamp
        ? "default safety clamp"
        : "explicit override\(arguments.allowLongRender ? " with --allow-long-render" : "")"
    lines.append("Render cap mode: \(clampMode)")
    lines.append("Rendered frames: \(result.renderedFrameCount)")
    lines.append(String(format: "Rendered duration: %.3f seconds", renderedDuration))
    lines.append(String(format: "Pre-export peak: %.6f", exportDiagnostics.preExportPeak))
    lines.append(String(format: "Post-gain peak: %.6f", exportDiagnostics.postGainPeak))
    lines.append("Pre-export overrange samples: \(exportDiagnostics.preExportOverrangeSampleCount)")
    lines.append("PCM16 clipping/clamping samples after gain: \(exportDiagnostics.pcm16ClippingSampleCount)")
    lines.append(String(format: "Overall RMS before/after gain: %.6f / %.6f", exportDiagnostics.preExportRMS, exportDiagnostics.postGainRMS))
    if let recommendation = exportDiagnostics.recommendation {
        lines.append("Warning: \(recommendation)")
    } else if exportDiagnostics.preExportOverrangeDetected {
        lines.append("Notice: Pre-export overrange samples were present, but export gain kept PCM16 output below clipping.")
    }
    if result.wasFrameCountBounded {
        lines.append("Frame count was clamped to \(result.maximumFrameCount) frames.")
    }
    appendWindowedRenderSummary(to: &lines, result: result)
    if arguments.diagnosticsJSONPath != nil || arguments.effectCoverageJSONPath != nil || arguments.progress {
        appendEventCoverageSummary(to: &lines, result: result)
    }
    lines.append("Export succeeded.")
    return lines.joined(separator: "\n")
}

private func renderIsolationSummaryLine(_ filter: PlaybackSongRenderIsolationFilter?) -> String {
    guard let filter, filter.isEnabled else {
        return "Render isolation: disabled."
    }
    var parts = [String]()
    if let channel = filter.soloChannelIndex {
        parts.append("channel \(channel)")
    }
    if let instrument = filter.soloInstrumentIndex {
        parts.append("instrument \(instrument)")
    }
    if let sample = filter.soloSampleIndex {
        parts.append("sample \(sample)")
    }
    return "Render isolation: " + parts.joined(separator: ", ") + "."
}

private func renderDurationDiagnostics(
    from result: PlaybackSongOfflineRenderResult,
    arguments: RenderToolArguments
) -> RenderDurationDiagnostics {
    let calculatedSongEndFrames: Int?
    if arguments.untilSongEnd {
        calculatedSongEndFrames = max(0, result.requestedFrameCount - RenderTool.frameCountAllowingZero(
            seconds: arguments.tailSeconds ?? 0,
            sampleRate: result.block.config.sampleRate
        ))
    } else {
        calculatedSongEndFrames = nil
    }
    let tailSeconds = arguments.untilSongEnd ? arguments.tailSeconds ?? 0 : 0
    let tailFrames = RenderTool.frameCountAllowingZero(seconds: tailSeconds, sampleRate: result.block.config.sampleRate)
    return RenderDurationDiagnostics(
        mode: arguments.renderDurationMode,
        calculatedSongEndFrames: calculatedSongEndFrames,
        tailSeconds: tailSeconds,
        tailFrames: tailFrames,
        effectiveFrameCap: result.maximumFrameCount,
        effectiveDurationSeconds: result.block.config.sampleRate > 0
            ? Double(result.maximumFrameCount) / result.block.config.sampleRate
            : 0
    )
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
    let rampedStateUpdates = stateUpdates.filter { update in
        update.activeVoiceUpdated &&
            ((update.gainBefore != nil && update.gainAfter != nil && update.gainBefore != update.gainAfter) ||
                (update.panBefore != nil && update.panAfter != nil && update.panBefore != update.panAfter))
    }.count
    lines.append(
        "Volume/panning state updates: \(appliedStateUpdates) applied, \(deferredStateUpdates) deferred, \(activeVoiceStateUpdates) active voice updates."
    )
    let gxxEffects = result.diagnostics.effectCommandDiagnostics.filter(\.isGxxSetGlobalVolume)
    let gxxApplied = gxxEffects.filter { $0.status == .applied }.count
    let gxxDeferred = gxxEffects.filter { $0.status == .deferredUnsupported }.count
    let gxxActiveUpdates = stateUpdates.filter { update in
        guard update.activeVoiceUpdated else {
            return false
        }
        if case .gxxSetGlobalVolume = update.command {
            return true
        }
        return false
    }.count
    lines.append(
        "Global volume set Gxx: \(gxxApplied) applied, \(gxxDeferred) deferred, \(gxxActiveUpdates) active voice updates."
    )
    let hxyEffects = result.diagnostics.effectCommandDiagnostics.filter(\.isHxyGlobalVolumeSlide)
    let hxyApplied = hxyEffects.filter { $0.status == .applied }.count
    let hxyNoOp = hxyEffects.filter { $0.status == .ignoredNoOp }.count
    let hxyDeferred = hxyEffects.filter { $0.status == .deferredUnsupported }.count
    let hxyActiveUpdates = stateUpdates.filter { update in
        guard update.activeVoiceUpdated else {
            return false
        }
        if case .hxyGlobalVolumeSlide = update.command {
            return true
        }
        return false
    }.count
    lines.append(
        "Global volume slide Hxy: \(hxyApplied) applied, \(hxyNoOp) no-op, \(hxyDeferred) deferred, \(hxyActiveUpdates) active voice updates."
    )
    lines.append(
        "Gain/pan update micro-ramp: enabled, \(CSoftwareMixer.gainPanUpdateRampFrameCount) frames, \(rampedStateUpdates) ramped active updates."
    )
    let appliedCuts = result.diagnostics.noteCutEffects.filter(\.applied).count
    let deferredCuts = result.diagnostics.noteCutEffects.filter(\.deferred).count
    let noActiveCuts = result.diagnostics.noteCutEffects.filter { $0.status == .noActiveVoice }.count
    let appliedDelays = result.diagnostics.noteDelayEffects.filter(\.applied).count
    let deferredDelays = result.diagnostics.noteDelayEffects.filter(\.deferred).count
    let outOfRowDelays = result.diagnostics.noteDelayEffects.filter(\.outOfRow).count
    let appliedRetriggers = result.diagnostics.retriggerEffects.filter(\.applied).count
    let deferredRetriggers = result.diagnostics.retriggerEffects.filter(\.deferred).count
    let noActiveRetriggers = result.diagnostics.retriggerEffects.filter { $0.status == .noActiveVoice }.count
    let outOfRowRetriggers = result.diagnostics.retriggerEffects.filter(\.outOfRow).count
    lines.append(
        "Note cut/delay: ECx \(appliedCuts) applied, \(deferredCuts) deferred, \(noActiveCuts) no-active; EDx \(appliedDelays) applied, \(deferredDelays) deferred, \(outOfRowDelays) out-of-row."
    )
    lines.append(
        "Retrigger: E9x \(appliedRetriggers) applied, \(deferredRetriggers) deferred, \(noActiveRetriggers) no-active, \(outOfRowRetriggers) out-of-row/no-op."
    )
    lines.append(
        "Arpeggio 0xy: \(result.diagnostics.arpeggioEffects.filter(\.applied).count) applied, \(result.diagnostics.arpeggioEffects.filter(\.deferred).count) deferred, \(result.diagnostics.arpeggioEffects.filter { $0.status == .noActiveVoice }.count) no-active, \(result.diagnostics.arpeggioEffects.map(\.stepUpdates.count).reduce(0, +)) sample-step updates."
    )
    let portamentoUp = result.diagnostics.portamentoSlideEffects.filter { $0.direction == .up }
    let portamentoDown = result.diagnostics.portamentoSlideEffects.filter { $0.direction == .down }
    lines.append(
        "Portamento slide: 1xx \(portamentoUp.filter(\.applied).count) applied, \(portamentoUp.filter(\.deferred).count) deferred, \(portamentoUp.filter { $0.status == .noActiveVoice }.count) no-active; 2xx \(portamentoDown.filter(\.applied).count) applied, \(portamentoDown.filter(\.deferred).count) deferred, \(portamentoDown.filter { $0.status == .noActiveVoice }.count) no-active."
    )
    lines.append(
        "Fine portamento: E1x \(result.diagnostics.finePortamentoUpEffects.filter(\.applied).count) applied, \(result.diagnostics.finePortamentoUpEffects.filter(\.deferred).count) deferred, \(result.diagnostics.finePortamentoUpEffects.filter { $0.status == .noActiveVoice }.count) no-active; E2x \(result.diagnostics.finePortamentoDownEffects.filter(\.applied).count) applied, \(result.diagnostics.finePortamentoDownEffects.filter(\.deferred).count) deferred, \(result.diagnostics.finePortamentoDownEffects.filter { $0.status == .noActiveVoice }.count) no-active."
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
