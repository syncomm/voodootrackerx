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
        ])

        XCTAssertEqual(arguments.inputPath, "/tmp/module.xm")
        XCTAssertEqual(arguments.outputPath, "/tmp/vtx-candidate.wav")
        XCTAssertEqual(arguments.diagnosticsJSONPath, "/tmp/vtx-candidate-diagnostics.json")
        XCTAssertEqual(arguments.order, 10)
        XCTAssertEqual(arguments.orderCount, 2)
        XCTAssertEqual(arguments.rows, 16)
        XCTAssertEqual(arguments.sampleRate, 48_000)
        XCTAssertEqual(arguments.maxFrames, 96_000)
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
        XCTAssertTrue(usage.contains("--allow-long-render"))
        XCTAssertTrue(usage.contains("--progress"))
        XCTAssertTrue(usage.contains("Default safety clamp"))
        XCTAssertTrue(usage.contains("percentage by rendered frames"))

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
        let events = try XCTUnwrap(diagnostics["events"] as? [[String: Any]])

        XCTAssertEqual(diagnostics["schema_version"] as? Int, 1)
        XCTAssertEqual(diagnostics["tool"] as? String, "vtx_render_bounded_xm")
        XCTAssertEqual(diagnostics["local_only"] as? Bool, true)
        XCTAssertEqual(render["sample_rate"] as? Double, 44_100)
        XCTAssertEqual(render["sample_interpolation"] as? String, "linear")
        XCTAssertEqual(render["rendered_frame_count"] as? Int, result.renderedFrameCount)
        XCTAssertEqual(render["maximum_frame_count"] as? Int, result.maximumFrameCount)
        XCTAssertEqual(render["maximum_duration_seconds"] as? Double, 60)
        XCTAssertEqual(events.count, result.diagnostics.emittedEventCount)
        XCTAssertFalse(String(decoding: diagnosticsData, as: UTF8.self).contains(fixturePath("minimal.xm").path))
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
