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
    let diagnosticsJSONPath: String?
    let order: Int
    let orderCount: Int
    let rows: Int?
    let sampleRate: Double
    let maxFrames: Int?
    let seconds: Double?

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
            diagnosticsJSONPath: diagnosticsJSONPath,
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
        let diagnosticsURL = arguments.diagnosticsJSONPath.map { URL(fileURLWithPath: $0).standardizedFileURL }

        try validateInput(inputURL)
        try validateOutput(outputURL)
        if let diagnosticsURL {
            try validateDiagnosticsOutput(diagnosticsURL)
        }

        let metadata = try ModuleMetadataLoader().load(fromPath: inputURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: inputURL.path)
        try validateOrderRange(start: arguments.order, count: arguments.orderCount, orderTotal: song.orders.count)

        let config = MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: MixerRenderConfig.defaultChannelCount)
        let request = renderRequest(song: song, arguments: arguments, config: config)
        let result = try PlaybackSongOfflineRenderer().exportWAV(request, to: outputURL)
        if let diagnosticsURL {
            try PlaybackSongDiagnosticsJSONExporter.write(result, to: diagnosticsURL)
        }
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
                "was_frame_count_bounded": result.wasFrameCountBounded,
                "initial_speed": diagnostics.initialSpeed,
                "initial_bpm": diagnostics.initialBPM,
                "uses_linear_frequency_table": diagnostics.usesLinearFrequencyTable,
                "synthetic_row_count": diagnostics.syntheticRowCount,
                "emitted_event_count": diagnostics.emittedEventCount,
                "ignored_cell_count": diagnostics.ignoredCellCount,
                "empty_or_skipped_row_count": diagnostics.emptyOrSkippedRowCount,
            ],
            "orders": diagnostics.adaptedOrders.map(orderJSON),
            "row_mappings": diagnostics.rowMappings.map(rowMappingJSON),
            "row_timing": diagnostics.rowTiming.map(rowTimingJSON),
            "timing_changes": diagnostics.timingChanges.map(timingChangeJSON),
            "row_diagnostics": diagnostics.rowDiagnostics.map(rowDiagnosticJSON),
            "volume_column_mappings": diagnostics.volumeColumnMappings.map(volumeColumnMappingJSON),
            "key_off_events": diagnostics.keyOffEvents.map(keyOffEventJSON),
            "events": eventJSON(from: result),
            "ignored_cells": diagnostics.ignoredCells.map(ignoredCellJSON),
            "deferred_fields": diagnostics.deferredCellFields.map(deferredFieldJSON),
        ]
    }

    private static func eventJSON(from result: PlaybackSongOfflineRenderResult) -> [[String: Any]] {
        result.diagnostics.eventMappings.map { mapping in
            let event = result.plan.pattern.events.indices.contains(mapping.eventIndex)
                ? result.plan.pattern.events[mapping.eventIndex]
                : nil
            let startFrame = event?.scheduledStartFrame ?? 0
            let playbackStep = event?.playbackStep ?? mapping.playbackStep
            let sampleFrameCount = event?.sample.frameCount ?? 0
            let durationFrames: Int
            let durationReason: String
            if mapping.loopMode == .none {
                let estimated = playbackStep > 0
                    ? Int((Double(sampleFrameCount) / playbackStep).rounded(.up))
                    : sampleFrameCount
                durationFrames = max(1, estimated)
                durationReason = "one_shot_sample_length"
            } else {
                durationFrames = max(0, result.renderedFrameCount - startFrame)
                durationReason = "looped_until_render_end"
            }
            let endFrame = max(startFrame, startFrame + durationFrames)
            var object: [String: Any] = [
                "source": positionJSON(mapping.source),
                "channel_index": mapping.channelIndex,
                "note": Int(mapping.note),
                "instrument_index": mapping.instrumentIndex,
                "sample_index": mapping.sampleIndex,
                "synthetic_row": mapping.syntheticRow,
                "synthetic_tick": mapping.syntheticTick,
                "event_index": mapping.eventIndex,
                "scheduled_start_frame": startFrame,
                "estimated_end_frame": endFrame,
                "estimated_duration_frames": durationFrames,
                "duration_estimate_reason": durationReason,
                "sample_frame_count": sampleFrameCount,
                "gain": Double(event?.gain ?? 0),
                "pan": Double(event?.pan ?? mapping.effectivePan),
                "loop_mode": loopModeName(mapping.loopMode),
                "volume_column": volumeColumnDiagnosticJSON(mapping.volumeColumn),
                "has_ignored_volume_column": mapping.hasIgnoredVolumeColumn,
                "has_ignored_effect": mapping.hasIgnoredEffect,
                "effective_volume_value": mapping.effectiveVolumeValue,
                "effective_pan": Double(mapping.effectivePan),
                "volume_envelope": [
                    "status": volumeEnvelopeStatusName(mapping.volumeEnvelopeStatus),
                    "enabled": mapping.volumeEnvelopeSemantics.envelopeEnabled,
                    "source_point_count": mapping.sourceVolumeEnvelopePointCount,
                    "mapped_point_count": mapping.mappedVolumeEnvelopePointCount,
                    "sustain_enabled": mapping.volumeEnvelopeSemantics.sustainEnabled,
                    "sustain_applied": mapping.volumeEnvelopeSemantics.sustainApplied,
                    "sustain_deferred": mapping.volumeEnvelopeSemantics.sustainDeferred,
                    "sustain_point_index": mapping.volumeEnvelopeSemantics.sustainPointIndex.map { $0 as Any } ?? NSNull(),
                    "sustain_tick": mapping.volumeEnvelopeSemantics.sustainTick.map { $0 as Any } ?? NSNull(),
                    "sustain_frame": mapping.volumeEnvelopeSemantics.sustainFrame.map { $0 as Any } ?? NSNull(),
                    "loop_enabled": mapping.volumeEnvelopeSemantics.loopEnabled,
                    "loop_applied": mapping.volumeEnvelopeSemantics.loopApplied,
                    "loop_deferred": mapping.volumeEnvelopeSemantics.loopDeferred,
                    "loop_start_point_index": mapping.volumeEnvelopeSemantics.loopStartPointIndex.map { $0 as Any } ?? NSNull(),
                    "loop_end_point_index": mapping.volumeEnvelopeSemantics.loopEndPointIndex.map { $0 as Any } ?? NSNull(),
                    "loop_start_tick": mapping.volumeEnvelopeSemantics.loopStartTick.map { $0 as Any } ?? NSNull(),
                    "loop_end_tick": mapping.volumeEnvelopeSemantics.loopEndTick.map { $0 as Any } ?? NSNull(),
                    "loop_start_frame": mapping.volumeEnvelopeSemantics.loopStartFrame.map { $0 as Any } ?? NSNull(),
                    "loop_end_frame": mapping.volumeEnvelopeSemantics.loopEndFrame.map { $0 as Any } ?? NSNull(),
                    "key_off_encountered": mapping.volumeEnvelopeSemantics.keyOffEncountered,
                    "key_off_applied": mapping.volumeEnvelopeSemantics.keyOffApplied,
                    "key_off_deferred": mapping.volumeEnvelopeSemantics.keyOffDeferred,
                    "key_off_source": mapping.volumeEnvelopeSemantics.keyOffSource.map(positionJSON) ?? NSNull(),
                    "key_off_channel_index": mapping.volumeEnvelopeSemantics.keyOffChannelIndex.map { $0 as Any } ?? NSNull(),
                    "key_off_synthetic_row": mapping.volumeEnvelopeSemantics.keyOffSyntheticRow.map { $0 as Any } ?? NSNull(),
                    "key_off_synthetic_tick": mapping.volumeEnvelopeSemantics.keyOffSyntheticTick.map { $0 as Any } ?? NSNull(),
                    "release_frame": mapping.volumeEnvelopeSemantics.releaseFrame.map { $0 as Any } ?? NSNull(),
                    "fadeout_value": mapping.volumeEnvelopeSemantics.fadeoutValue,
                    "fadeout_applied": mapping.volumeEnvelopeSemantics.fadeoutApplied,
                    "fadeout_deferred": mapping.volumeEnvelopeSemantics.fadeoutDeferred,
                    "limitations": mapping.volumeEnvelopeSemantics.limitations,
                    "has_deferred_sustain": mapping.hasDeferredVolumeEnvelopeSustain,
                    "has_deferred_loop": mapping.hasDeferredVolumeEnvelopeLoop,
                    "has_deferred_fadeout": mapping.hasDeferredVolumeEnvelopeFadeout,
                ],
                "pitch": [
                    "source_note": Int(mapping.note),
                    "sample_base_sample_rate": mapping.sampleBaseSampleRate,
                    "sample_relative_note": mapping.sampleRelativeNote,
                    "sample_finetune": mapping.sampleFinetune,
                    "output_sample_rate": mapping.outputSampleRate,
                    "effective_note_value": mapping.effectiveNoteValue.map { $0 as Any } ?? NSNull(),
                    "effective_note_index": mapping.effectiveNoteIndex.map { $0 as Any } ?? NSNull(),
                    "effective_finetune": mapping.effectiveFinetune.map { $0 as Any } ?? NSNull(),
                    "linear_period": mapping.linearPeriod.map { $0 as Any } ?? NSNull(),
                    "linear_frequency": mapping.linearFrequency.map { $0 as Any } ?? NSNull(),
                    "finetune_status": finetuneStatusName(mapping.finetuneStatus),
                    "uses_linear_frequency_table": mapping.usesLinearFrequencyTable,
                    "frequency_table_status": frequencyTableStatusName(mapping.frequencyTableStatus),
                    "linear_frequency_applied": mapping.linearFrequencyApplied,
                    "amiga_frequency_deferred": mapping.amigaFrequencyDeferred,
                    "playback_step": mapping.playbackStep,
                    "mapping_applied": mapping.pitchMappingApplied,
                    "used_neutral_step": mapping.pitchMappingUsedNeutralStep,
                    "fallback_neutral_step_used": mapping.pitchMappingUsedNeutralStep,
                ],
            ]
            if let startSeconds = seconds(forFrame: startFrame, sampleRate: result.block.config.sampleRate) {
                object["scheduled_start_seconds"] = startSeconds
            }
            if let endSeconds = seconds(forFrame: endFrame, sampleRate: result.block.config.sampleRate) {
                object["estimated_end_seconds"] = endSeconds
            }
            return object
        }
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

    private static func ignoredCellJSON(_ cell: PlaybackSongSyntheticIgnoredCell) -> [String: Any] {
        [
            "source": positionJSON(cell.source),
            "channel_index": cell.channelIndex,
            "note": Int(cell.note),
            "instrument_index": cell.instrumentIndex,
            "reason": ignoredCellReasonName(cell.reason),
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

    private static func put(_ value: Any?, forKey key: String, into object: inout [String: Any]) {
        if let value {
            object[key] = value
        }
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
        case .keyOff:
            return "key_off"
        case .invalidNote:
            return "invalid_note"
        case .missingInstrument:
            return "missing_instrument"
        case .noPlayableSample:
            return "no_playable_sample"
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

private func usage() -> String {
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
    if let diagnosticsJSONPath = arguments.diagnosticsJSONPath {
        print("Diagnostics JSON: \(URL(fileURLWithPath: diagnosticsJSONPath).standardizedFileURL.path)")
    }
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
