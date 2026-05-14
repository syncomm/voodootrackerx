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
            print(usage())
            return 0
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            FileHandle.standardError.write(Data("\(toolName): \(message)\n\n\(usage())\n".utf8))
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
             let .invalidOrderRange(message):
            return message
        }
    }
}

struct RenderToolArguments: Equatable {
    let inputPath: String
    let outputPath: String
    let order: Int
    let orderCount: Int
    let rows: Int?
    let sampleRate: Double
    let maxFrames: Int?
    let seconds: Double?

    static func parse(_ argv: [String]) throws -> RenderToolArguments {
        var inputPath: String?
        var outputPath: String?
        var order: Int?
        var orderCount = 1
        var rows: Int?
        var sampleRate = MixerRenderConfig.defaultSampleRate
        var maxFrames: Int?
        var seconds: Double?
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

        return RenderToolArguments(
            inputPath: try required(inputPath, "--input"),
            outputPath: try required(outputPath, "--output"),
            order: try required(order, "--order"),
            orderCount: orderCount,
            rows: rows,
            sampleRate: sampleRate,
            maxFrames: maxFrames,
            seconds: seconds
        )
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
}

struct RenderTool {
    let fileManager: FileManager
    let currentDirectory: URL

    init(fileManager: FileManager = .default, currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.fileManager = fileManager
        self.currentDirectory = currentDirectory
    }

    func run(_ arguments: RenderToolArguments) throws -> PlaybackSongOfflineRenderResult {
        let inputURL = URL(fileURLWithPath: arguments.inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments.outputPath).standardizedFileURL

        try validateInput(inputURL)
        try validateOutput(outputURL)

        let metadata = try ModuleMetadataLoader().load(fromPath: inputURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: inputURL.path)
        try validateOrderRange(start: arguments.order, count: arguments.orderCount, orderTotal: song.orders.count)

        let config = MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: MixerRenderConfig.defaultChannelCount)
        let request = renderRequest(song: song, arguments: arguments, config: config)
        let result = try PlaybackSongOfflineRenderer().exportWAV(request, to: outputURL)
        return result
    }

    func renderRequest(
        song: PlaybackSong,
        arguments: RenderToolArguments,
        config: MixerRenderConfig
    ) -> PlaybackSongOfflineRenderRequest {
        let maximumFrameCount = max(0, arguments.maxFrames ?? PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount)
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

private func usage() -> String {
    """
    Usage:
      \(toolName) --input /path/to/module.xm --output /tmp/vtx-candidate.wav --order 10 [options]

    Options:
      --input PATH          Local XM module path. Required.
      --output PATH         Local candidate WAV path. Required; prefer /tmp.
      --order N             Zero-based order index to render. Required.
      --order-count N       Number of playable orders to include. Default: 1.
      --rows N              Render this many flattened rows from the bounded range.
      --sample-rate HZ      Output sample rate. Default: 44100.
      --max-frames N        Maximum output frames. Default: 60 seconds at 44100 Hz.
      --seconds N           Render this many seconds instead of --rows/--max-frames.
      --help                Show this help.

    Generated WAVs are local diagnostic artifacts and must not be committed.
    This helper uses the offline C-backed PlaybackSongOfflineRenderer.exportWAV path only.
    """
}

private func printSummary(
    arguments: RenderToolArguments,
    result: PlaybackSongOfflineRenderResult
) {
    let duration = result.block.config.sampleRate > 0
        ? Double(result.renderedFrameCount) / result.block.config.sampleRate
        : 0
    print("Developer-only bounded XM candidate WAV render.")
    print("Generated WAVs/reports/traces/screenshots are local artifacts and must not be committed.")
    print("Runtime playback remains AVAudioPlayerNode / AVAudioUnitVarispeed; the C mixer is offline-only.")
    print("Module: \(URL(fileURLWithPath: arguments.inputPath).standardizedFileURL.path)")
    print("Output: \(URL(fileURLWithPath: arguments.outputPath).standardizedFileURL.path)")
    print("Order range: \(arguments.order)..<\(arguments.order + arguments.orderCount)")
    if let rows = arguments.rows {
        print("Rows requested: \(rows)")
    }
    print("Sample rate: \(Int(result.block.config.sampleRate)) Hz")
    print("Rendered frames: \(result.renderedFrameCount)")
    print(String(format: "Rendered duration: %.3f seconds", duration))
    if result.wasFrameCountBounded {
        print("Frame count was clamped to \(result.maximumFrameCount) frames.")
    }
    print("Export succeeded.")
}
