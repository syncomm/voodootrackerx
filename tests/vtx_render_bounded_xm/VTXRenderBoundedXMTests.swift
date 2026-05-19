import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VTXRenderBoundedXMTests: XCTestCase {
    func testArgumentParsingAcceptsRequiredArgumentsAndBounds() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--diagnostics-json", "/tmp/vtx-candidate-diagnostics.json",
            "--order", "10",
            "--order-count", "2",
            "--rows", "16",
            "--sample-rate", "48000",
            "--max-frames", "96000",
            "--window-rows", "64",
        ])

        XCTAssertEqual(arguments.inputPath, "/tmp/module.xm")
        XCTAssertEqual(arguments.outputPath, "/tmp/vtx-candidate.wav")
        XCTAssertEqual(arguments.diagnosticsJSONPath, "/tmp/vtx-candidate-diagnostics.json")
        XCTAssertEqual(arguments.order, 10)
        XCTAssertEqual(arguments.orderCount, 2)
        XCTAssertEqual(arguments.rows, 16)
        XCTAssertEqual(arguments.sampleRate, 48_000)
        XCTAssertEqual(arguments.maxFrames, 96_000)
        XCTAssertEqual(arguments.windowRows, 64)
        XCTAssertFalse(arguments.allowLongRender)
        XCTAssertFalse(arguments.progress)
    }

    func testArgumentParsingAcceptsProgressFlag() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--progress",
        ])

        XCTAssertTrue(arguments.progress)
    }

    func testInvalidWindowRowsFailClearly() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--window-rows", "0",
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Window row count must be greater than zero"))
        }

        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--window-rows", "abc",
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Invalid integer for --window-rows"))
        }
    }

    func testDefaultRenderStillUsesConservativeClamp() throws {
        let request = RenderTool().renderRequest(
            song: tinySong(),
            arguments: RenderToolArguments(
                inputPath: "/tmp/module.xm",
                outputPath: "/tmp/vtx-candidate.wav",
                diagnosticsJSONPath: nil,
                order: 0,
                orderCount: 1,
                rows: nil,
                sampleRate: 44_100,
                maxFrames: nil,
                seconds: nil
            ),
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2)
        )

        XCTAssertEqual(request.requestedFrameCount, PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount)
        XCTAssertEqual(request.maximumFrameCount, PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount)
    }

    func testSecondsParsesAndSetsExpectedFrameCap() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--sample-rate", "48000",
            "--seconds", "2.5",
        ])

        let request = RenderTool().renderRequest(
            song: tinySong(),
            arguments: arguments,
            config: MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: 2)
        )

        XCTAssertEqual(arguments.seconds, 2.5)
        XCTAssertEqual(request.requestedFrameCount, 120_000)
        XCTAssertEqual(request.maximumFrameCount, 120_000)
    }

    func testMaxFramesParsesAndSetsExpectedFrameCap() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--max-frames", "12345",
        ])

        let request = RenderTool().renderRequest(
            song: tinySong(),
            arguments: arguments,
            config: MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: 2)
        )

        XCTAssertEqual(arguments.maxFrames, 12_345)
        XCTAssertEqual(request.requestedFrameCount, 12_345)
        XCTAssertEqual(request.maximumFrameCount, 12_345)
    }

    func testSecondsAndMaxFramesFailClearlyTogether() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--seconds", "1",
            "--max-frames", "44100",
        ])) { error in
            XCTAssertEqual(error as? RenderToolError, .mutuallyExclusive("--max-frames", "--seconds"))
        }
    }

    func testInvalidSecondsFailClearly() {
        for value in ["-1", "0", "nan", "abc"] {
            XCTAssertThrowsError(try RenderToolArguments.parse([
                "--input", "/tmp/module.xm",
                "--output", "/tmp/vtx-candidate.wav",
                "--order", "0",
                "--seconds", value,
            ]), "value \(value) should fail") { error in
                XCTAssertTrue(error.localizedDescription.contains("Invalid number for --seconds"))
            }
        }
    }

    func testInvalidMaxFramesFailClearly() {
        for value in ["-1", "0", "abc"] {
            XCTAssertThrowsError(try RenderToolArguments.parse([
                "--input", "/tmp/module.xm",
                "--output", "/tmp/vtx-candidate.wav",
                "--order", "0",
                "--max-frames", value,
            ]), "value \(value) should fail") { error in
                XCTAssertTrue(error.localizedDescription.contains("Invalid integer for --max-frames"))
            }
        }
    }

    func testLongRenderOverrideRequiresAllowLongRender() throws {
        let defaultLimit = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount

        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--max-frames", "\(defaultLimit + 1)",
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("--allow-long-render"))
        }

        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--max-frames", "\(defaultLimit + 1)",
            "--allow-long-render",
        ])

        XCTAssertTrue(arguments.allowLongRender)
        XCTAssertEqual(arguments.maxFrames, defaultLimit + 1)
    }

    func testLongAllowedRenderUsesExplicitCap() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultLimit = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount
        let outputURL = directory.appendingPathComponent("long-allowed-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: defaultLimit + 1,
            seconds: nil,
            allowLongRender: true
        )

        let result = try RenderTool(currentDirectory: repoRoot()).run(arguments)

        XCTAssertEqual(result.maximumFrameCount, defaultLimit + 1)
        XCTAssertEqual(result.renderedFrameCount, defaultLimit + 1)
    }

    func testHelpAndSummaryDescribeClampAndOverrideBehavior() {
        let usage = renderToolUsage()

        XCTAssertTrue(usage.contains("--seconds N"))
        XCTAssertTrue(usage.contains("--max-frames N"))
        XCTAssertTrue(usage.contains("--window-rows N"))
        XCTAssertTrue(usage.contains("--allow-long-render"))
        XCTAssertTrue(usage.contains("--progress"))
        XCTAssertTrue(usage.contains("Default safety clamp"))
        XCTAssertTrue(usage.contains("rendered frames or row windows"))

        let defaultLimit = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount
        let request = PlaybackSongOfflineRenderRequest(
            song: tinySong(),
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frames: 1,
            maximumFrameCount: defaultLimit + 1
        )
        let result = PlaybackSongOfflineRenderer(maximumFrameCount: defaultLimit + 1).render(request)
        let summary = renderToolSummary(
            arguments: RenderToolArguments(
                inputPath: "/tmp/module.xm",
                outputPath: "/tmp/vtx-candidate.wav",
                diagnosticsJSONPath: nil,
                order: 0,
                orderCount: 1,
                rows: nil,
                sampleRate: 44_100,
                maxFrames: defaultLimit + 1,
                seconds: nil,
                allowLongRender: true
            ),
            result: result
        )

        XCTAssertTrue(summary.contains("Requested order range: 0..<1"))
        XCTAssertTrue(summary.contains("Requested rows: not specified"))
        XCTAssertTrue(summary.contains("Windowed render: disabled"))
        XCTAssertTrue(summary.contains("Sample rate: 44100 Hz"))
        XCTAssertTrue(summary.contains("Effective frame cap: \(defaultLimit + 1)"))
        XCTAssertTrue(summary.contains("Render cap mode: explicit override with --allow-long-render"))
    }

    func testProgressFlagProducesCoarseStatusOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            progress: true
        )

        let result = try RenderTool(
            currentDirectory: repoRoot(),
            progressOutput: { progressLines.append($0) }
        ).run(arguments)
        let progressText = progressLines.joined(separator: "\n")

        XCTAssertGreaterThan(result.renderedFrameCount, 0)
        XCTAssertTrue(progressText.contains("loading module"))
        XCTAssertTrue(progressText.contains("building playback song"))
        XCTAssertTrue(progressText.contains("render started"))
        XCTAssertTrue(progressText.contains("effective frame cap: 2646000 frames (60.000 seconds)"))
        XCTAssertTrue(progressText.contains("rendering bounded candidate: 0% (0 / 5292 frames)"))
        XCTAssertTrue(progressText.contains("rendering bounded candidate: 100% (5292 / 5292 frames)"))
        XCTAssertTrue(progressText.contains("render completed: rendered"))
        XCTAssertTrue(progressText.contains("writing WAV"))
        XCTAssertTrue(progressText.contains("writing WAV completed"))
        XCTAssertTrue(progressText.contains("export succeeded"))
    }

    func testWindowedProgressOutputIncludesWindowProgress() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("windowed-progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 2,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            windowRows: 1,
            progress: true
        )

        let result = try RenderTool(
            currentDirectory: repoRoot(),
            progressOutput: { progressLines.append($0) }
        ).run(arguments)
        let progressText = progressLines.joined(separator: "\n")

        XCTAssertEqual(result.windowedRenderSummary?.windowRows, 1)
        XCTAssertEqual(result.windowedRenderSummary?.windowCount, 2)
        XCTAssertTrue(progressText.contains("rendering window 1 / 2"))
        XCTAssertTrue(progressText.contains("rendering window 2 / 2"))
        XCTAssertTrue(progressText.contains("scheduled"))
        XCTAssertTrue(progressText.contains("writing WAV completed"))
    }

    func testProgressRenderOutputMatchesDefaultRenderOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultOutputURL = directory.appendingPathComponent("default-candidate.wav")
        let progressOutputURL = directory.appendingPathComponent("progress-candidate.wav")
        let baseArguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: defaultOutputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: 44_100,
            seconds: nil
        )
        let progressArguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: progressOutputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: 44_100,
            seconds: nil,
            progress: true
        )

        _ = try RenderTool(currentDirectory: repoRoot()).run(baseArguments)
        _ = try RenderTool(
            currentDirectory: repoRoot(),
            progressOutput: { _ in }
        ).run(progressArguments)

        XCTAssertEqual(try Data(contentsOf: progressOutputURL), try Data(contentsOf: defaultOutputURL))
    }

    func testWindowedSingleWindowOutputMatchesDefaultRenderOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultOutputURL = directory.appendingPathComponent("default-candidate.wav")
        let windowedOutputURL = directory.appendingPathComponent("windowed-candidate.wav")
        let baseArguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: defaultOutputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )
        let windowedArguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: windowedOutputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            windowRows: 64
        )

        _ = try RenderTool(currentDirectory: repoRoot()).run(baseArguments)
        let windowed = try RenderTool(currentDirectory: repoRoot()).run(windowedArguments)

        XCTAssertEqual(windowed.windowedRenderSummary?.windowCount, 1)
        XCTAssertEqual(try Data(contentsOf: windowedOutputURL), try Data(contentsOf: defaultOutputURL))
    }

    func testDefaultRunDoesNotEmitProgressStatusOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("default-no-progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )

        _ = try RenderTool(
            currentDirectory: repoRoot(),
            progressOutput: { progressLines.append($0) }
        ).run(arguments)

        XCTAssertTrue(progressLines.isEmpty)
    }

    func testMissingInputPathFailsClearly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("missing-input-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: "/tmp/vtx-missing-input.xm",
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )

        XCTAssertThrowsError(try RenderTool(currentDirectory: repoRoot()).run(arguments)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Input module does not exist"))
        }
    }

    func testTrackedRepoOutputPathFailsClearly() throws {
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: repoRoot().appendingPathComponent("unsafe-candidate.wav").path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )

        XCTAssertThrowsError(try RenderTool(currentDirectory: repoRoot()).run(arguments)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Refusing to write candidate WAV inside a tracked repo path"))
        }
    }

    func testInvalidOrderRangeFailsClearly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("invalid-order-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 99,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )

        XCTAssertThrowsError(try RenderTool(currentDirectory: repoRoot()).run(arguments)) { error in
            XCTAssertTrue(error.localizedDescription.contains("outside the playable order range"))
        }
    }

    func testRendersRedistributionSafeTinyXMFixtureToWAV() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("minimal-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )

        let result = try RenderTool(currentDirectory: repoRoot()).run(arguments)
        let data = try Data(contentsOf: outputURL)

        XCTAssertGreaterThan(result.renderedFrameCount, 0)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertTrue(outputURL.path.hasPrefix(URL(fileURLWithPath: NSTemporaryDirectory()).path))
    }

    func testRendersDiagnosticsJSONWhenRequested() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("minimal-candidate.wav")
        let diagnosticsURL = directory.appendingPathComponent("minimal-candidate-diagnostics.json")
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: diagnosticsURL.path,
            order: 0,
            orderCount: 1,
            rows: 1,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil
        )

        let result = try RenderTool(currentDirectory: repoRoot()).run(arguments)
        let diagnosticsData = try Data(contentsOf: diagnosticsURL)
        let diagnostics = try XCTUnwrap(JSONSerialization.jsonObject(with: diagnosticsData) as? [String: Any])
        let render = try XCTUnwrap(diagnostics["render"] as? [String: Any])
        let coverage = try XCTUnwrap(diagnostics["event_coverage"] as? [String: Any])
        let events = try XCTUnwrap(diagnostics["events"] as? [[String: Any]])

        XCTAssertEqual(diagnostics["schema_version"] as? Int, 1)
        XCTAssertEqual(diagnostics["tool"] as? String, "vtx_render_bounded_xm")
        XCTAssertEqual(diagnostics["local_only"] as? Bool, true)
        XCTAssertEqual(render["sample_rate"] as? Double, 44_100)
        XCTAssertEqual(render["sample_interpolation"] as? String, "linear")
        XCTAssertEqual(render["windowed_render_enabled"] as? Bool, false)
        XCTAssertEqual(render["rendered_frame_count"] as? Int, result.renderedFrameCount)
        XCTAssertEqual(render["maximum_frame_count"] as? Int, result.maximumFrameCount)
        XCTAssertEqual(render["maximum_duration_seconds"] as? Double, 60)
        XCTAssertEqual(coverage["normal_note_cells"] as? Int, result.diagnostics.eventCoverage.normalNoteCells)
        XCTAssertEqual(coverage["scheduled_note_events"] as? Int, result.diagnostics.eventCoverage.scheduledNoteEvents)
        XCTAssertEqual(coverage["skipped_note_events"] as? Int, result.diagnostics.eventCoverage.skippedNoteEvents)
        XCTAssertNotNil(coverage["capacity"] as? [String: Any])
        XCTAssertEqual(events.count, result.diagnostics.emittedEventCount)
        XCTAssertFalse(String(decoding: diagnosticsData, as: UTF8.self).contains(fixturePath("minimal.xm").path))
    }

    func testWindowedDiagnosticsJSONIncludesAggregateWindowFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("windowed-candidate.wav")
        let diagnosticsURL = directory.appendingPathComponent("windowed-candidate-diagnostics.json")
        let arguments = RenderToolArguments(
            inputPath: fixturePath("minimal.xm").path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: diagnosticsURL.path,
            order: 0,
            orderCount: 1,
            rows: 2,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            windowRows: 1
        )

        let result = try RenderTool(currentDirectory: repoRoot()).run(arguments)
        let diagnosticsData = try Data(contentsOf: diagnosticsURL)
        let diagnostics = try XCTUnwrap(JSONSerialization.jsonObject(with: diagnosticsData) as? [String: Any])
        let render = try XCTUnwrap(diagnostics["render"] as? [String: Any])
        let windowed = try XCTUnwrap(diagnostics["windowed_render"] as? [String: Any])
        let perWindow = try XCTUnwrap(windowed["per_window"] as? [[String: Any]])
        let coverage = try XCTUnwrap(diagnostics["event_coverage"] as? [String: Any])
        let capacity = try XCTUnwrap(coverage["capacity"] as? [String: Any])

        XCTAssertEqual(render["windowed_render_enabled"] as? Bool, true)
        XCTAssertEqual(render["window_rows"] as? Int, 1)
        XCTAssertEqual(render["window_count"] as? Int, 2)
        XCTAssertEqual(windowed["enabled"] as? Bool, true)
        XCTAssertEqual(windowed["window_rows"] as? Int, 1)
        XCTAssertEqual(windowed["window_count"] as? Int, 2)
        XCTAssertEqual(windowed["total_rendered_frames"] as? Int, result.renderedFrameCount)
        XCTAssertEqual(windowed["total_scheduled_events"] as? Int, result.scheduledVoiceAttempts.count)
        XCTAssertEqual(windowed["total_accepted_scheduled_events"] as? Int, result.scheduledVoiceAttempts.filter { $0.voiceIndex != nil }.count)
        XCTAssertNotNil(windowed["known_state_carryover_limitations"] as? [String])
        XCTAssertEqual(perWindow.count, 2)
        XCTAssertNotNil(perWindow.first?["scheduled_event_count"] as? Int)
        XCTAssertEqual(capacity["scheduled_voice_attempt_count"] as? Int, result.scheduledVoiceAttempts.count)
    }

    func testDiagnosticsJSONEventCoverageIncludesScheduledAndSkippedCoordinates() throws {
        let playableSample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 1,
            pcm: [1, 0.5],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let emptySample = PlaybackSample(
            instrumentIndex: 2,
            sampleIndex: 0,
            pcm: [],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let row = PlaybackRow(index: 3, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 9, volumeColumn: 0, effectType: 0, effectParam: 0)
        ])
        let song = PlaybackSong(
            title: "diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [row])],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [
                    PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 100),
                    playableSample
                ]),
                2: PlaybackInstrument(index: 2, samples: [emptySample])
            ],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let coverage = try XCTUnwrap(object["event_coverage"] as? [String: Any])
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let ignored = try XCTUnwrap(object["ignored_cells"] as? [[String: Any]])
        let firstSkipped = try XCTUnwrap(coverage["first_skipped_note_coordinates"] as? [[String: Any]])
        let firstEvent = try XCTUnwrap(events.first)

        XCTAssertEqual(coverage["normal_note_cells"] as? Int, 4)
        XCTAssertEqual(coverage["scheduled_note_events"] as? Int, 1)
        XCTAssertEqual(coverage["skipped_note_events"] as? Int, 3)
        XCTAssertEqual(coverage["sample_map_selection_events"] as? Int, 0)
        XCTAssertEqual(coverage["first_playable_sample_fallback_events"] as? Int, 1)
        XCTAssertEqual(coverage["fallback_after_invalid_sample_map_events"] as? Int, 0)
        XCTAssertEqual(coverage["skipped_no_valid_sample_events"] as? Int, 1)
        XCTAssertEqual(firstEvent["sample_index"] as? Int, 1)
        XCTAssertEqual(firstEvent["selected_sample_length"] as? Int, 2)
        XCTAssertEqual(firstEvent["sample_map_keymap_present"] as? Bool, false)
        XCTAssertTrue(firstEvent["mapped_sample_index"] is NSNull)
        XCTAssertEqual(firstEvent["mapped_sample_valid"] as? Bool, false)
        XCTAssertEqual(firstEvent["sample_selection_method"] as? String, "first_playable_fallback")
        XCTAssertEqual(firstEvent["selected_sample_selection_method"] as? String, "first_playable_fallback")
        XCTAssertEqual(firstEvent["sample_selection_strategy"] as? String, "first_playable_fallback")
        XCTAssertEqual(firstEvent["first_playable_sample_fallback_used"] as? Bool, true)
        XCTAssertEqual(firstEvent["sample_map_keymap_behavior_deferred"] as? Bool, true)
        XCTAssertEqual(firstEvent["sample_map_keymap_missing_or_deferred"] as? Bool, true)
        XCTAssertEqual(ignored.map { $0["skip_reason"] as? String }, [
            "missing_instrument",
            "sample_pcm_empty",
            "unknown_instrument"
        ])
        XCTAssertEqual(firstSkipped.first?["channel_index"] as? Int, 1)
        XCTAssertEqual((firstSkipped.first?["source"] as? [String: Any])?["row"] as? Int, 3)
    }

    func testDiagnosticsJSONReportsCMixerVoiceCapacityRejections() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let attemptedVoiceCount = CSoftwareMixer.maximumScheduledVoiceCount + 1
        let row = PlaybackRow(index: 0, cells: (0..<attemptedVoiceCount).map { _ in
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        })
        let song = PlaybackSong(
            title: "capacity",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [row])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let coverage = try XCTUnwrap(object["event_coverage"] as? [String: Any])
        let capacity = try XCTUnwrap(coverage["capacity"] as? [String: Any])
        let skipReasons = try XCTUnwrap(coverage["skip_reason_counts"] as? [[String: Any]])
        let rejectedCoordinates = try XCTUnwrap(capacity["rejected_event_coordinates"] as? [[String: Any]])

        XCTAssertEqual(coverage["normal_note_cells"] as? Int, attemptedVoiceCount)
        XCTAssertEqual(coverage["scheduled_note_events"] as? Int, attemptedVoiceCount)
        XCTAssertEqual(coverage["c_mixer_voice_capacity_limit_count"] as? Int, 1)
        XCTAssertEqual(capacity["c_mixer_voice_capacity"] as? Int, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(capacity["c_mixer_scheduled_voice_capacity"] as? Int, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(capacity["c_mixer_active_voice_capacity"] as? Int, CSoftwareMixer.maximumActiveVoiceCount)
        XCTAssertEqual(capacity["scheduled_voice_capacity"] as? Int, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(capacity["active_voice_capacity"] as? Int, CSoftwareMixer.maximumActiveVoiceCount)
        XCTAssertEqual(capacity["scheduled_voice_attempt_count"] as? Int, attemptedVoiceCount)
        XCTAssertEqual(capacity["scheduled_voice_accepted_count"] as? Int, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(capacity["scheduled_voice_rejected_count"] as? Int, 1)
        XCTAssertEqual(capacity["scheduled_voice_capacity_rejected_count"] as? Int, 1)
        XCTAssertEqual(capacity["active_voice_capacity_rejected_count"] as? Int, 0)
        XCTAssertEqual(capacity["invalid_scheduled_voice_rejected_count"] as? Int, 0)
        XCTAssertEqual(rejectedCoordinates.count, 1)
        XCTAssertEqual(rejectedCoordinates.first?["reason"] as? String, "scheduled_voice_capacity")
        XCTAssertEqual(rejectedCoordinates.first?["channel_index"] as? Int, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual((rejectedCoordinates.first?["source"] as? [String: Any])?["row"] as? Int, 0)
        XCTAssertTrue(skipReasons.contains { item in
            item["reason"] as? String == "c_mixer_voice_capacity_limit" && item["count"] as? Int == 1
        })
    }

    func testDiagnosticsJSONReportsCapacityValuesAndZeroRejectsBelowCapacity() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let row = PlaybackRow(index: 0, cells: (0..<33).map { _ in
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        })
        let song = PlaybackSong(
            title: "below-capacity",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [row])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let coverage = try XCTUnwrap(object["event_coverage"] as? [String: Any])
        let capacity = try XCTUnwrap(coverage["capacity"] as? [String: Any])
        let rejectedCoordinates = try XCTUnwrap(capacity["rejected_event_coordinates"] as? [[String: Any]])

        XCTAssertEqual(coverage["normal_note_cells"] as? Int, 33)
        XCTAssertEqual(coverage["scheduled_note_events"] as? Int, 33)
        XCTAssertEqual(coverage["c_mixer_voice_capacity_limit_count"] as? Int, 0)
        XCTAssertEqual(capacity["scheduled_voice_capacity"] as? Int, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(capacity["active_voice_capacity"] as? Int, CSoftwareMixer.maximumActiveVoiceCount)
        XCTAssertEqual(capacity["scheduled_voice_attempt_count"] as? Int, 33)
        XCTAssertEqual(capacity["scheduled_voice_accepted_count"] as? Int, 33)
        XCTAssertEqual(capacity["scheduled_voice_rejected_count"] as? Int, 0)
        XCTAssertEqual(capacity["scheduled_voice_capacity_rejected_count"] as? Int, 0)
        XCTAssertEqual(capacity["active_voice_capacity_rejected_count"] as? Int, 0)
        XCTAssertTrue(rejectedCoordinates.isEmpty)
    }

    func testDiagnosticsJSONReportsSampleMapSelectionSummary() throws {
        let firstSample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let mappedSample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 1,
            pcm: [0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        let song = PlaybackSong(
            title: "sample-map",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [
                2: PlaybackPattern(index: 2, rows: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ])
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [firstSample, mappedSample], noteSampleMap: noteSampleMap)
            ],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let coverage = try XCTUnwrap(object["event_coverage"] as? [String: Any])
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(coverage["sample_map_selection_events"] as? Int, 1)
        XCTAssertEqual(coverage["first_playable_sample_fallback_events"] as? Int, 0)
        XCTAssertEqual(coverage["fallback_after_invalid_sample_map_events"] as? Int, 0)
        XCTAssertEqual(coverage["skipped_no_valid_sample_events"] as? Int, 0)
        XCTAssertEqual(event["sample_index"] as? Int, 1)
        XCTAssertEqual(event["sample_map_keymap_present"] as? Bool, true)
        XCTAssertEqual(event["mapped_sample_index"] as? Int, 1)
        XCTAssertEqual(event["mapped_sample_valid"] as? Bool, true)
        XCTAssertEqual(event["sample_selection_method"] as? String, "sample_map")
        XCTAssertEqual(event["first_playable_sample_fallback_used"] as? Bool, false)
    }

    func testDiagnosticsJSONIncludesPitchPeriodFields() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0, 1, 2],
            volume: 1,
            relativeNote: 12,
            finetune: 64,
            baseSampleRate: 8_363
        )
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        ])
        let song = PlaybackSong(
            title: "diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [row])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frames: 3
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let pitch = try XCTUnwrap(try XCTUnwrap(events.first)["pitch"] as? [String: Any])

        XCTAssertEqual(pitch["source_note"] as? Int, 49)
        XCTAssertEqual(pitch["sample_relative_note"] as? Int, 12)
        XCTAssertEqual(pitch["sample_finetune"] as? Int, 64)
        XCTAssertEqual(pitch["output_sample_rate"] as? Double, 44_100)
        XCTAssertEqual(pitch["effective_note_value"] as? Int, 61)
        XCTAssertEqual(pitch["effective_note_index"] as? Int, 60)
        XCTAssertEqual(pitch["effective_finetune"] as? Int, 64)
        XCTAssertEqual(pitch["linear_period"] as? Double, 3_808)
        XCTAssertEqual(pitch["frequency_table_status"] as? String, "linear_applied")
        XCTAssertEqual(pitch["linear_frequency_applied"] as? Bool, true)
        XCTAssertEqual(pitch["amiga_frequency_deferred"] as? Bool, false)
        XCTAssertEqual(pitch["fallback_neutral_step_used"] as? Bool, false)
    }

    func testDiagnosticsJSONIncludesSampleOffsetFields() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(1), count: 300),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x09, effectParam: 0x01)
        ])
        let song = PlaybackSong(
            title: "diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [row])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let sampleOffsetEffects = try XCTUnwrap(object["sample_offset_effects"] as? [[String: Any]])
        let sampleOffset = try XCTUnwrap(try XCTUnwrap(events.first)["sample_offset"] as? [String: Any])

        XCTAssertEqual(try XCTUnwrap(events.first)["effect_type"] as? Int, 0x09)
        XCTAssertEqual(try XCTUnwrap(events.first)["effect_param"] as? Int, 0x01)
        XCTAssertEqual(try XCTUnwrap(events.first)["initial_source_frame"] as? Int, 256)
        XCTAssertEqual(sampleOffset["status"] as? String, "applied")
        XCTAssertEqual(sampleOffset["computed_offset_frames"] as? Int, 256)
        XCTAssertEqual(sampleOffset["applied_offset_frames"] as? Int, 256)
        XCTAssertEqual(sampleOffset["selected_sample_length"] as? Int, 300)
        XCTAssertEqual(sampleOffset["out_of_range"] as? Bool, false)
        XCTAssertEqual(sampleOffsetEffects.count, 1)
        XCTAssertEqual(sampleOffsetEffects.first?["status"] as? String, "applied")
    }

    func testDiagnosticsJSONCountsTraversalHazardsWithCoordinatesAndStatuses() throws {
        let rows = [
            PlaybackRow(index: 0, cells: [
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0B, effectParam: 0x02),
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0D, effectParam: 0x10),
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0E, effectParam: 0xE2),
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0F, effectParam: 0x06),
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0E, effectParam: 0x94)
            ])
        ]
        let song = PlaybackSong(
            title: "traversal-diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: rows)],
            instrumentsByIndex: [:],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let summary = try XCTUnwrap(object["traversal_hazard_summary"] as? [String: Any])
        let effects = try XCTUnwrap(object["pattern_traversal_timing_effects"] as? [[String: Any]])
        let firstHazards = try XCTUnwrap(summary["first_traversal_hazard_coordinates"] as? [[String: Any]])
        let bxx = try XCTUnwrap(effects.first { $0["effect_label"] as? String == "Bxx position jump" })
        let dxx = try XCTUnwrap(effects.first { $0["effect_label"] as? String == "Dxx pattern break" })
        let eex = try XCTUnwrap(effects.first { $0["effect_label"] as? String == "EEx pattern delay" })
        let fxx = try XCTUnwrap(effects.first { $0["effect_label"] as? String == "Fxx speed/BPM" })
        let e9x = try XCTUnwrap(effects.first { $0["effect_label"] as? String == "E9x retrigger" })

        XCTAssertEqual(summary["total_bxx_position_jump"] as? Int, 1)
        XCTAssertEqual(summary["total_dxx_pattern_break"] as? Int, 1)
        XCTAssertEqual(summary["total_eex_pattern_delay"] as? Int, 1)
        XCTAssertEqual(summary["total_fxx_speed_bpm"] as? Int, 1)
        XCTAssertEqual(summary["total_other_e_commands"] as? Int, 1)
        XCTAssertEqual(summary["total_traversal_hazards"] as? Int, 3)
        XCTAssertEqual(summary["likely_ignores_structure_changing_behavior"] as? Bool, true)
        XCTAssertEqual(firstHazards.count, 3)
        XCTAssertEqual((firstHazards.first?["source"] as? [String: Any])?["order"] as? Int, 0)
        XCTAssertEqual((firstHazards.first?["source"] as? [String: Any])?["pattern"] as? Int, 2)
        XCTAssertEqual((firstHazards.first?["source"] as? [String: Any])?["row"] as? Int, 0)
        XCTAssertEqual(firstHazards.first?["channel_index"] as? Int, 0)
        XCTAssertEqual(bxx["current_status"] as? String, "deferred/unsupported")
        XCTAssertEqual(dxx["current_status"] as? String, "deferred/unsupported")
        XCTAssertEqual(eex["current_status"] as? String, "deferred/unsupported")
        XCTAssertEqual(e9x["current_status"] as? String, "deferred/unsupported")
        XCTAssertEqual(fxx["current_status"] as? String, "applied")
        XCTAssertEqual(fxx["is_traversal_hazard"] as? Bool, false)
    }

    func testTraversalDiagnosticsDoNotChangeRenderedAudio() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1, 0.5, -0.5],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let baseline = PlaybackSong(
            title: "baseline",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [
                PlaybackRow(index: 0, cells: [
                    PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                ])
            ])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let withTraversalHazard = PlaybackSong(
            title: "with-traversal-hazard",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [
                PlaybackRow(index: 0, cells: [
                    PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x0B, effectParam: 0x01)
                ])
            ])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)
        let baselineResult = renderer.render(PlaybackSongOfflineRenderRequest(
            song: baseline,
            orderIndex: 0,
            config: config,
            frames: 3
        ))
        let traversalResult = renderer.render(PlaybackSongOfflineRenderRequest(
            song: withTraversalHazard,
            orderIndex: 0,
            config: config,
            frames: 3
        ))

        XCTAssertEqual(traversalResult.block.interleavedPCM, baselineResult.block.interleavedPCM)
        XCTAssertEqual(traversalResult.diagnostics.traversalHazardSummary.totalBxxPositionJump, 1)
    }

    func testDiagnosticsJSONIncludesEnvelopeSemanticsAndKeyOffFields() throws {
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32)
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x03,
            fadeout: 65_536
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1, 1, 1],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let song = PlaybackSong(
            title: "diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [
                2: PlaybackPattern(index: 2, rows: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ]),
                    PlaybackRow(index: 1, cells: [
                        PlaybackCell(note: 97, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ])
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let keyOffEvents = try XCTUnwrap(object["key_off_events"] as? [[String: Any]])
        let volumeEnvelope = try XCTUnwrap(try XCTUnwrap(events.first)["volume_envelope"] as? [String: Any])

        XCTAssertEqual(volumeEnvelope["sustain_enabled"] as? Bool, true)
        XCTAssertEqual(volumeEnvelope["sustain_applied"] as? Bool, true)
        XCTAssertEqual(volumeEnvelope["sustain_point_index"] as? Int, 1)
        XCTAssertEqual(volumeEnvelope["sustain_frame"] as? Int, 1)
        XCTAssertEqual(volumeEnvelope["key_off_encountered"] as? Bool, true)
        XCTAssertEqual(volumeEnvelope["key_off_applied"] as? Bool, true)
        XCTAssertEqual(volumeEnvelope["release_frame"] as? Int, 1)
        XCTAssertEqual(volumeEnvelope["fadeout_value"] as? Int, 65_536)
        XCTAssertEqual(volumeEnvelope["fadeout_applied"] as? Bool, true)
        XCTAssertEqual(keyOffEvents.first?["applied"] as? Bool, true)
        XCTAssertEqual(keyOffEvents.first?["release_frame"] as? Int, 1)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixturePath(_ name: String) -> URL {
        repoRoot().appendingPathComponent("tests/fixtures").appendingPathComponent(name)
    }

    private func tinySong() -> PlaybackSong {
        PlaybackSong(
            title: "tiny",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [
                0: PlaybackPattern(index: 0, rows: [
                    PlaybackRow(index: 0, cells: [])
                ])
            ],
            instrumentsByIndex: [:],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vtx-render-bounded-xm-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
