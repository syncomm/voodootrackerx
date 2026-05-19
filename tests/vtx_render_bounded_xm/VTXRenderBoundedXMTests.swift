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
            "--gain", "0.5",
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
        XCTAssertEqual(arguments.gain, 0.5)
        XCTAssertNil(arguments.headroomDB)
        XCTAssertFalse(arguments.autoHeadroom)
        XCTAssertEqual(arguments.exportPolicy.gain, 0.5)
        XCTAssertFalse(arguments.allowLongRender)
        XCTAssertFalse(arguments.progress)
    }

    func testArgumentParsingAcceptsHeadroomDB() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--headroom-db", "-6",
        ])

        XCTAssertNil(arguments.gain)
        XCTAssertEqual(arguments.headroomDB, -6)
        XCTAssertEqual(arguments.exportPolicy.gain, Float(pow(10.0, -6.0 / 20.0)), accuracy: 0.000_001)
    }

    func testArgumentParsingAcceptsAutoHeadroom() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--auto-headroom",
        ])

        XCTAssertTrue(arguments.autoHeadroom)
        XCTAssertNil(arguments.gain)
        XCTAssertNil(arguments.headroomDB)
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

    func testGainAndHeadroomDBFailClearlyTogether() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--gain", "0.5",
            "--headroom-db", "-6",
        ])) { error in
            XCTAssertEqual(error as? RenderToolError, .mutuallyExclusive("--gain", "--headroom-db"))
        }
    }

    func testAutoHeadroomFailsClearlyWithGain() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--auto-headroom",
            "--gain", "0.5",
        ])) { error in
            XCTAssertEqual(error as? RenderToolError, .mutuallyExclusive("--auto-headroom", "--gain"))
        }
    }

    func testAutoHeadroomFailsClearlyWithHeadroomDB() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--auto-headroom",
            "--headroom-db", "-6",
        ])) { error in
            XCTAssertEqual(error as? RenderToolError, .mutuallyExclusive("--auto-headroom", "--headroom-db"))
        }
    }

    func testInvalidGainFailsClearly() {
        for value in ["-1", "0", "nan", "abc"] {
            XCTAssertThrowsError(try RenderToolArguments.parse([
                "--input", "/tmp/module.xm",
                "--output", "/tmp/vtx-candidate.wav",
                "--order", "0",
                "--gain", value,
            ]), "value \(value) should fail") { error in
                XCTAssertTrue(error.localizedDescription.contains("Invalid number for --gain"))
            }
        }
    }

    func testInvalidHeadroomDBFailsClearly() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--headroom-db", "3",
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Headroom dB must be zero or negative"))
        }

        for value in ["nan", "abc"] {
            XCTAssertThrowsError(try RenderToolArguments.parse([
                "--input", "/tmp/module.xm",
                "--output", "/tmp/vtx-candidate.wav",
                "--order", "0",
                "--headroom-db", value,
            ]), "value \(value) should fail") { error in
                XCTAssertTrue(error.localizedDescription.contains("Invalid number for --headroom-db"))
            }
        }
    }

    func testDefaultRenderStillUsesConservativeClamp() throws {
        let request = try RenderTool().renderRequest(
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

        let request = try RenderTool().renderRequest(
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

        let request = try RenderTool().renderRequest(
            song: tinySong(),
            arguments: arguments,
            config: MixerRenderConfig(sampleRate: arguments.sampleRate, channelCount: 2)
        )

        XCTAssertEqual(arguments.maxFrames, 12_345)
        XCTAssertEqual(request.requestedFrameCount, 12_345)
        XCTAssertEqual(request.maximumFrameCount, 12_345)
    }

    func testUntilSongEndComputesExpectedFrameCountForFixedTimingSong() throws {
        let arguments = try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--until-song-end",
        ])
        let song = songWithRows(4)
        let config = MixerRenderConfig(sampleRate: 44_100, channelCount: 2)
        let duration = try RenderTool().renderDurationDiagnostics(song: song, arguments: arguments, config: config)
        let request = try RenderTool().renderRequest(song: song, arguments: arguments, config: config)

        XCTAssertEqual(arguments.renderDurationMode, .untilSongEnd)
        XCTAssertEqual(duration.calculatedSongEndFrames, 21_168)
        XCTAssertEqual(duration.tailSeconds, 0)
        XCTAssertEqual(duration.tailFrames, 0)
        XCTAssertEqual(duration.effectiveFrameCap, 21_168)
        XCTAssertEqual(request.requestedFrameCount, 21_168)
        XCTAssertEqual(request.maximumFrameCount, 21_168)
    }

    func testUntilSongEndAccountsForSupportedFxxTimingChanges() throws {
        let song = PlaybackSong(
            title: "fxx-duration",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [
                0: PlaybackPattern(index: 0, rows: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0F, effectParam: 0x03)
                    ]),
                    PlaybackRow(index: 1, cells: [])
                ])
            ],
            instrumentsByIndex: [:],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let arguments = RenderToolArguments(
            inputPath: "/tmp/module.xm",
            outputPath: "/tmp/vtx-candidate.wav",
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true
        )

        let duration = try RenderTool().renderDurationDiagnostics(
            song: song,
            arguments: arguments,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1)
        )

        XCTAssertEqual(duration.calculatedSongEndFrames, 9)
        XCTAssertEqual(duration.effectiveFrameCap, 9)
    }

    func testTailSecondsAddsExpectedFramesToUntilSongEnd() throws {
        let arguments = RenderToolArguments(
            inputPath: "/tmp/module.xm",
            outputPath: "/tmp/vtx-candidate.wav",
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true,
            tailSeconds: 2.5
        )

        let duration = try RenderTool().renderDurationDiagnostics(
            song: songWithRows(1, timing: PlaybackTiming(speed: 1, bpm: 250)),
            arguments: arguments,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1)
        )

        XCTAssertEqual(duration.calculatedSongEndFrames, 1)
        XCTAssertEqual(duration.tailSeconds, 2.5)
        XCTAssertEqual(duration.tailFrames, 250)
        XCTAssertEqual(duration.effectiveFrameCap, 251)
    }

    func testTailSecondsWithoutUntilSongEndFailsClearly() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--tail-seconds", "2",
        ])) { error in
            XCTAssertTrue(error.localizedDescription.contains("--tail-seconds may only be used with --until-song-end"))
        }
    }

    func testUntilSongEndFailsClearlyWithSecondsAndMaxFrames() {
        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--until-song-end",
            "--seconds", "1",
        ])) { error in
            XCTAssertEqual(error as? RenderToolError, .mutuallyExclusive("--until-song-end", "--seconds"))
        }

        XCTAssertThrowsError(try RenderToolArguments.parse([
            "--input", "/tmp/module.xm",
            "--output", "/tmp/vtx-candidate.wav",
            "--order", "0",
            "--until-song-end",
            "--max-frames", "44100",
        ])) { error in
            XCTAssertEqual(error as? RenderToolError, .mutuallyExclusive("--until-song-end", "--max-frames"))
        }
    }

    func testUntilSongEndLongComputedDurationRequiresAllowLongRender() throws {
        let song = songWithRows(501)
        let config = MixerRenderConfig(sampleRate: 44_100, channelCount: 2)
        let withoutOverride = RenderToolArguments(
            inputPath: "/tmp/module.xm",
            outputPath: "/tmp/vtx-candidate.wav",
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true
        )

        XCTAssertThrowsError(try RenderTool().renderDurationDiagnostics(song: song, arguments: withoutOverride, config: config)) { error in
            XCTAssertTrue(error.localizedDescription.contains("--allow-long-render"))
        }

        let withOverride = RenderToolArguments(
            inputPath: "/tmp/module.xm",
            outputPath: "/tmp/vtx-candidate.wav",
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true,
            allowLongRender: true
        )
        let duration = try RenderTool().renderDurationDiagnostics(song: song, arguments: withOverride, config: config)

        XCTAssertEqual(duration.effectiveFrameCap, 2_651_292)
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
        let inputURL = try generatedPlayableXMPath(in: directory)
        let defaultLimit = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount
        let outputURL = directory.appendingPathComponent("long-allowed-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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

    func testAutoHeadroomKeepsUnityGainWhenPeakIsAtOrBelowOne() {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 3,
            interleavedPCM: [0.25, -0.75, 1.0]
        )
        let policy = MixerWAVExportPolicy.autoHeadroom(for: block)
        let diagnostics = MixerWAVExporter.diagnostics(for: block, exportPolicy: policy)

        XCTAssertTrue(policy.autoHeadroomEnabled)
        XCTAssertEqual(policy.gain, 1)
        XCTAssertEqual(diagnostics.preExportPeak, 1)
        XCTAssertEqual(diagnostics.postGainPeak, 1)
        XCTAssertEqual(diagnostics.computedHeadroomDB, 0, accuracy: 0.000_001)
    }

    func testAutoHeadroomAppliesSafetyMarginForHotRender() {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 2,
            interleavedPCM: [2.0, -0.5]
        )
        let policy = MixerWAVExportPolicy.autoHeadroom(for: block)
        let diagnostics = MixerWAVExporter.diagnostics(for: block, exportPolicy: policy)
        let unclippedFullScaleGain = Float(1.0 / 2.0)
        let expectedSafetyMargin = Float(pow(10.0, MixerWAVExportPolicy.autoHeadroomSafetyDB / 20.0))

        XCTAssertTrue(policy.autoHeadroomEnabled)
        XCTAssertEqual(policy.autoHeadroomSafetyDB, -1)
        XCTAssertLessThan(policy.gain, unclippedFullScaleGain)
        XCTAssertEqual(policy.gain, unclippedFullScaleGain * expectedSafetyMargin, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.preExportPeak, 2)
        XCTAssertEqual(diagnostics.postGainPeak, expectedSafetyMargin, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.pcm16ClippingSampleCount, 0)
        XCTAssertFalse(diagnostics.clippingDetected)
    }

    func testDefaultExportBehaviorRemainsUnityGain() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 2,
            interleavedPCM: [0.25, -0.25]
        )

        let defaultData = try MixerWAVExporter.pcm16WAVData(from: block)
        let unityData = try MixerWAVExporter.pcm16WAVData(from: block, exportPolicy: .unity)
        let defaultDiagnostics = MixerWAVExporter.diagnostics(for: block)

        XCTAssertEqual(defaultData, unityData)
        XCTAssertEqual(defaultDiagnostics.policy.gain, 1)
        XCTAssertFalse(defaultDiagnostics.autoHeadroomEnabled)
    }

    func testHelpAndSummaryDescribeClampAndOverrideBehavior() {
        let usage = renderToolUsage()

        XCTAssertTrue(usage.contains("--seconds N"))
        XCTAssertTrue(usage.contains("--max-frames N"))
        XCTAssertTrue(usage.contains("--until-song-end"))
        XCTAssertTrue(usage.contains("--tail-seconds N"))
        XCTAssertTrue(usage.contains("--window-rows N"))
        XCTAssertTrue(usage.contains("--gain N"))
        XCTAssertTrue(usage.contains("--headroom-db N"))
        XCTAssertTrue(usage.contains("--auto-headroom"))
        XCTAssertTrue(usage.contains("-1 dB margin"))
        XCTAssertTrue(usage.contains("--allow-long-render"))
        XCTAssertTrue(usage.contains("--progress"))
        XCTAssertTrue(usage.contains("Default safety clamp"))
        XCTAssertTrue(usage.contains("before PCM16 conversion"))
        XCTAssertTrue(usage.contains("rendered frames or row windows"))
        XCTAssertTrue(usage.contains("not full FT2/OpenMPT song loop/restart parity"))

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
        XCTAssertTrue(summary.contains("Render duration mode: max frames"))
        XCTAssertTrue(summary.contains("Calculated song-end frames: not applicable"))
        XCTAssertTrue(summary.contains("Tail: 0.000 seconds (0 frames)"))
        XCTAssertTrue(summary.contains("Auto-headroom: disabled"))
        XCTAssertTrue(summary.contains("Effective export gain: 1.000000"))
        XCTAssertTrue(summary.contains("Computed export gain: 1.000000 (0.000 dB)"))
        XCTAssertTrue(summary.contains("Pre-export peak: 0.000000"))
        XCTAssertTrue(summary.contains("PCM16 clipping/clamping samples after gain: 0"))
        XCTAssertTrue(summary.contains("Effective frame cap: \(defaultLimit + 1)"))
        XCTAssertTrue(summary.contains("Render cap mode: explicit override with --allow-long-render"))
        XCTAssertTrue(summary.contains("not full FT2/OpenMPT song loop/restart parity"))
    }

    func testSummaryReportsAutoHeadroomComputedGain() {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 2,
            interleavedPCM: [2.0, -2.0]
        )
        let exportPolicy = MixerWAVExportPolicy.autoHeadroom(for: block)
        let exportDiagnostics = MixerWAVExporter.diagnostics(for: block, exportPolicy: exportPolicy)
        let result = PlaybackSongOfflineRenderResult(
            request: PlaybackSongOfflineRenderRequest(
                song: tinySong(),
                orderIndex: 0,
                config: block.config,
                frames: 2
            ),
            plan: PlaybackSongSyntheticAdapter.adapt(tinySong(), orderIndex: 0, sampleRate: block.config.sampleRate),
            block: block,
            scheduledVoiceIndices: [],
            exportDiagnostics: exportDiagnostics
        )

        let summary = renderToolSummary(
            arguments: RenderToolArguments(
                inputPath: "/tmp/module.xm",
                outputPath: "/tmp/vtx-candidate.wav",
                diagnosticsJSONPath: nil,
                order: 0,
                orderCount: 1,
                rows: nil,
                sampleRate: 44_100,
                maxFrames: 2,
                seconds: nil,
                autoHeadroom: true
            ),
            result: result
        )

        XCTAssertTrue(summary.contains("Auto-headroom: enabled"))
        XCTAssertTrue(summary.contains("safety margin -1.000 dB"))
        XCTAssertTrue(summary.contains("Computed export gain: 0.445625 (-7.021 dB)"))
        XCTAssertTrue(summary.contains("Pre-export peak: 2.000000"))
        XCTAssertTrue(summary.contains("Post-gain peak: 0.891251"))
        XCTAssertTrue(summary.contains("PCM16 clipping/clamping samples after gain: 0"))
    }

    func testSummaryReportsGainHeadroomAndClippingWarning() {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 2,
            interleavedPCM: [1.5, -1.5]
        )
        let exportDiagnostics = MixerWAVExporter.diagnostics(for: block, exportPolicy: MixerWAVExportPolicy(gain: 0.5))
        let result = PlaybackSongOfflineRenderResult(
            request: PlaybackSongOfflineRenderRequest(
                song: tinySong(),
                orderIndex: 0,
                config: block.config,
                frames: 2
            ),
            plan: PlaybackSongSyntheticAdapter.adapt(tinySong(), orderIndex: 0, sampleRate: block.config.sampleRate),
            block: block,
            scheduledVoiceIndices: [],
            exportDiagnostics: exportDiagnostics
        )

        let summary = renderToolSummary(
            arguments: RenderToolArguments(
                inputPath: "/tmp/module.xm",
                outputPath: "/tmp/vtx-candidate.wav",
                diagnosticsJSONPath: nil,
                order: 0,
                orderCount: 1,
                rows: nil,
                sampleRate: 44_100,
                maxFrames: 2,
                seconds: nil,
                gain: 0.5
            ),
            result: result
        )

        XCTAssertTrue(summary.contains("Effective export gain: 0.500000"))
        XCTAssertTrue(summary.contains("Pre-export peak: 1.500000"))
        XCTAssertTrue(summary.contains("Post-gain peak: 0.750000"))
        XCTAssertTrue(summary.contains("Pre-export overrange samples: 2"))
        XCTAssertTrue(summary.contains("PCM16 clipping/clamping samples after gain: 0"))
        XCTAssertTrue(summary.contains("Notice: Pre-export overrange samples were present, but export gain kept PCM16 output below clipping."))
        XCTAssertFalse(summary.contains("Warning: PCM16 clipping/clamping detected after export gain"))
    }

    func testProgressFlagProducesCoarseStatusOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        XCTAssertTrue(progressText.contains("writing WAV (export gain 1.000000)"))
        XCTAssertTrue(progressText.contains("writing WAV completed"))
        XCTAssertTrue(progressText.contains("export succeeded"))
    }

    func testWindowedProgressOutputIncludesWindowProgress() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("windowed-progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        XCTAssertTrue(progressText.contains("carried"))
        XCTAssertTrue(progressText.contains("scheduled"))
        XCTAssertTrue(progressText.contains("writing WAV completed"))
    }

    func testUntilSongEndProgressOutputIncludesDurationModeAndFrameCap() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("until-progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true,
            progress: true
        )

        let result = try RenderTool(
            currentDirectory: repoRoot(),
            progressOutput: { progressLines.append($0) }
        ).run(arguments)
        let progressText = progressLines.joined(separator: "\n")

        XCTAssertEqual(result.renderedFrameCount, 21_168)
        XCTAssertTrue(progressText.contains("render duration mode: until song end"))
        XCTAssertTrue(progressText.contains("calculated song-end: 21168 frames"))
        XCTAssertTrue(progressText.contains("effective frame cap: 21168 frames"))
    }

    func testUntilSongEndWorksWithWindowRowsAndAutoHeadroom() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("until-windowed-auto-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: nil,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true,
            windowRows: 1,
            autoHeadroom: true
        )

        let result = try RenderTool(currentDirectory: repoRoot()).run(arguments)

        XCTAssertEqual(result.renderedFrameCount, 21_168)
        XCTAssertEqual(result.windowedRenderSummary?.windowRows, 1)
        XCTAssertEqual(result.windowedRenderSummary?.windowCount, 4)
        XCTAssertEqual(result.exportDiagnostics?.autoHeadroomEnabled, true)
    }

    func testProgressRenderOutputMatchesDefaultRenderOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let defaultOutputURL = directory.appendingPathComponent("default-candidate.wav")
        let progressOutputURL = directory.appendingPathComponent("progress-candidate.wav")
        let baseArguments = RenderToolArguments(
            inputPath: inputURL.path,
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
            inputPath: inputURL.path,
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
        let inputURL = try generatedPlayableXMPath(in: directory)
        let defaultOutputURL = directory.appendingPathComponent("default-candidate.wav")
        let windowedOutputURL = directory.appendingPathComponent("windowed-candidate.wav")
        let baseArguments = RenderToolArguments(
            inputPath: inputURL.path,
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
            inputPath: inputURL.path,
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
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("default-no-progress-candidate.wav")
        var progressLines = [String]()
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("invalid-order-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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

    func testRendersGeneratedPlayableXMToWAV() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("generated-playable-candidate.wav")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        XCTAssertEqual(result.diagnostics.eventCoverage.scheduledNoteEvents, 1)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertTrue(outputURL.path.hasPrefix(URL(fileURLWithPath: NSTemporaryDirectory()).path))
    }

    func testMinimalXMFixtureRemainsParserHelperPlumbingSmokeOnly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("minimal-header-plumbing-candidate.wav")
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
        XCTAssertGreaterThan(result.diagnostics.eventCoverage.normalNoteCells, 0)
        XCTAssertEqual(result.diagnostics.eventCoverage.scheduledNoteEvents, 0)
        XCTAssertEqual(result.diagnostics.eventCoverage.skippedNoteEvents, result.diagnostics.eventCoverage.normalNoteCells)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertTrue(outputURL.path.hasPrefix(URL(fileURLWithPath: NSTemporaryDirectory()).path))
    }

    func testRendersDiagnosticsJSONWhenRequested() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("generated-playable-candidate.wav")
        let diagnosticsURL = directory.appendingPathComponent("generated-playable-candidate-diagnostics.json")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        XCTAssertEqual(render["render_duration_mode"] as? String, "fixed_rows")
        XCTAssertTrue(render["calculated_song_end_frames"] is NSNull)
        XCTAssertEqual(render["tail_seconds"] as? Double, 0)
        XCTAssertEqual(render["tail_frames"] as? Int, 0)
        XCTAssertEqual(render["effective_frame_cap"] as? Int, PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount)
        XCTAssertEqual(render["effective_duration_seconds"] as? Double, 60)
        XCTAssertEqual(render["gain_pan_ramp_enabled"] as? Bool, true)
        XCTAssertEqual(render["gain_pan_ramp_frame_count"] as? Int, CSoftwareMixer.gainPanUpdateRampFrameCount)
        XCTAssertEqual(render["gain_pan_update_count"] as? Int, 0)
        XCTAssertEqual(render["gain_pan_ramped_update_count"] as? Int, 0)
        XCTAssertEqual(render["gain_pan_interrupted_ramp_count"] as? Int, 0)
        XCTAssertEqual(render["auto_headroom_enabled"] as? Bool, false)
        XCTAssertTrue(render["auto_headroom_safety_db"] is NSNull)
        XCTAssertEqual(render["export_gain"] as? Double, 1)
        XCTAssertTrue(render["export_headroom_db"] is NSNull)
        XCTAssertNotNil(render["pre_export_peak"] as? Double)
        XCTAssertNotNil(render["pre_export_per_channel_peak"] as? [Double])
        XCTAssertNotNil(render["pre_export_overrange_sample_count"] as? Int)
        XCTAssertNotNil(render["pre_export_rms"] as? Double)
        XCTAssertEqual(render["computed_export_gain"] as? Double, 1)
        XCTAssertEqual(render["computed_headroom_db"] as? Double, 0)
        XCTAssertNotNil(render["post_gain_peak"] as? Double)
        XCTAssertNotNil(render["post_gain_per_channel_peak"] as? [Double])
        XCTAssertNotNil(render["post_gain_rms"] as? Double)
        XCTAssertNotNil(render["pcm16_clipping_count"] as? Int)
        XCTAssertNotNil(render["pcm16_clipping_sample_count"] as? Int)
        XCTAssertNotNil(render["clipping_detected"] as? Bool)
        XCTAssertNotNil(diagnostics["export_diagnostics"] as? [String: Any])
        XCTAssertEqual(render["windowed_render_enabled"] as? Bool, false)
        XCTAssertEqual(render["rendered_frame_count"] as? Int, result.renderedFrameCount)
        XCTAssertEqual(render["maximum_frame_count"] as? Int, result.maximumFrameCount)
        XCTAssertEqual(render["maximum_duration_seconds"] as? Double, 60)
        XCTAssertEqual(render["retrigger_effect_count"] as? Int, result.diagnostics.retriggerEffectCount)
        XCTAssertEqual(coverage["normal_note_cells"] as? Int, result.diagnostics.eventCoverage.normalNoteCells)
        XCTAssertEqual(coverage["scheduled_note_events"] as? Int, result.diagnostics.eventCoverage.scheduledNoteEvents)
        XCTAssertEqual(coverage["skipped_note_events"] as? Int, result.diagnostics.eventCoverage.skippedNoteEvents)
        XCTAssertNotNil(coverage["capacity"] as? [String: Any])
        XCTAssertNotNil(diagnostics["retrigger_effects"] as? [[String: Any]])
        XCTAssertEqual(events.count, result.diagnostics.emittedEventCount)
        XCTAssertFalse(String(decoding: diagnosticsData, as: UTF8.self).contains(inputURL.path))
    }

    func testUntilSongEndDiagnosticsJSONIncludesDurationModeAndTailFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("until-tail-candidate.wav")
        let diagnosticsURL = directory.appendingPathComponent("until-tail-candidate-diagnostics.json")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            diagnosticsJSONPath: diagnosticsURL.path,
            order: 0,
            orderCount: 1,
            rows: nil,
            sampleRate: 44_100,
            maxFrames: nil,
            seconds: nil,
            untilSongEnd: true,
            tailSeconds: 0.25
        )

        let result = try RenderTool(currentDirectory: repoRoot()).run(arguments)
        let diagnosticsData = try Data(contentsOf: diagnosticsURL)
        let diagnostics = try XCTUnwrap(JSONSerialization.jsonObject(with: diagnosticsData) as? [String: Any])
        let render = try XCTUnwrap(diagnostics["render"] as? [String: Any])
        let notes = try XCTUnwrap(diagnostics["notes"] as? [String])

        XCTAssertEqual(result.renderedFrameCount, 32_193)
        XCTAssertEqual(render["render_duration_mode"] as? String, "until_song_end")
        XCTAssertEqual(render["calculated_song_end_frames"] as? Int, 21_168)
        XCTAssertEqual(render["tail_seconds"] as? Double, 0.25)
        XCTAssertEqual(render["tail_frames"] as? Int, 11_025)
        XCTAssertEqual(render["effective_frame_cap"] as? Int, 32_193)
        XCTAssertEqual(render["effective_duration_seconds"] as? Double, Double(32_193) / 44_100)
        XCTAssertTrue(notes.contains { $0.contains("bounded selected order-range end") })
        XCTAssertFalse(String(decoding: diagnosticsData, as: UTF8.self).contains(inputURL.path))
    }

    func testDiagnosticsJSONIncludesAutoHeadroomFieldsWhenEnabled() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 2,
            interleavedPCM: [2.0, -2.0]
        )
        let policy = MixerWAVExportPolicy.autoHeadroom(for: block)
        let exportDiagnostics = MixerWAVExporter.diagnostics(for: block, exportPolicy: policy)
        let result = PlaybackSongOfflineRenderResult(
            request: PlaybackSongOfflineRenderRequest(
                song: tinySong(),
                orderIndex: 0,
                config: block.config,
                frames: 2
            ),
            plan: PlaybackSongSyntheticAdapter.adapt(tinySong(), orderIndex: 0, sampleRate: block.config.sampleRate),
            block: block,
            scheduledVoiceIndices: [],
            exportDiagnostics: exportDiagnostics
        )

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let export = try XCTUnwrap(object["export_diagnostics"] as? [String: Any])

        XCTAssertEqual(render["auto_headroom_enabled"] as? Bool, true)
        XCTAssertEqual(render["auto_headroom_safety_db"] as? Double, -1)
        XCTAssertEqual(render["pre_export_peak"] as? Double, 2)
        XCTAssertEqual(render["computed_export_gain"] as? Double, Double(policy.gain))
        XCTAssertEqual(render["computed_headroom_db"] as? Double, policy.computedHeadroomDB)
        XCTAssertEqual(render["post_gain_peak"] as? Double, Double(exportDiagnostics.postGainPeak))
        XCTAssertEqual(render["pcm16_clipping_count"] as? Int, 0)
        XCTAssertEqual(render["pcm16_clipping_sample_count"] as? Int, 0)
        XCTAssertEqual(render["clipping_detected"] as? Bool, false)
        XCTAssertEqual(export["auto_headroom_enabled"] as? Bool, true)
        XCTAssertEqual(export["computed_export_gain"] as? Double, Double(policy.gain))
        XCTAssertEqual(export["pcm16_clipping_count"] as? Int, 0)
    }

    func testWindowedDiagnosticsJSONIncludesAggregateWindowFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = try generatedPlayableXMPath(in: directory)
        let outputURL = directory.appendingPathComponent("windowed-candidate.wav")
        let diagnosticsURL = directory.appendingPathComponent("windowed-candidate-diagnostics.json")
        let arguments = RenderToolArguments(
            inputPath: inputURL.path,
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
        XCTAssertNotNil(windowed["total_carried_voice_count"] as? Int)
        XCTAssertNotNil(windowed["total_boundary_continuation_count"] as? Int)
        XCTAssertNotNil(windowed["total_dropped_at_window_boundaries"] as? Int)
        XCTAssertNotNil(windowed["may_contain_boundary_cuts"] as? Bool)
        XCTAssertNotNil(windowed["known_unsupported_carryover_reasons"] as? [String])
        XCTAssertNotNil(windowed["known_state_carryover_limitations"] as? [String])
        XCTAssertEqual(perWindow.count, 2)
        XCTAssertNotNil(perWindow.first?["carried_voice_count"] as? Int)
        XCTAssertNotNil(perWindow.first?["boundary_continuation_count"] as? Int)
        XCTAssertNotNil(perWindow.first?["dropped_at_window_boundary_count"] as? Int)
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

    func testDiagnosticsJSONIncludesE9xRetriggerDetails() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1, 0.5, 0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x0E, effectParam: 0x92)
        ])
        let song = PlaybackSong(
            title: "diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: [row])],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let summary = try XCTUnwrap(object["traversal_hazard_summary"] as? [String: Any])
        let retriggers = try XCTUnwrap(object["retrigger_effects"] as? [[String: Any]])
        let first = try XCTUnwrap(retriggers.first)

        XCTAssertEqual(render["retrigger_effect_count"] as? Int, 1)
        XCTAssertEqual(summary["total_e9x_retrigger"] as? Int, 1)
        XCTAssertEqual(first["status"] as? String, "applied")
        XCTAssertEqual(first["applied"] as? Bool, true)
        XCTAssertEqual(first["active_voice_found"] as? Bool, true)
        XCTAssertEqual(first["retrigger_interval_ticks"] as? Int, 2)
        XCTAssertEqual(first["row_speed"] as? Int, 6)
        XCTAssertEqual(first["row_bpm"] as? Int, 250)
        XCTAssertEqual(first["retrigger_ticks"] as? [Int], [2, 4])
        XCTAssertEqual(first["retrigger_frames"] as? [Int], [2, 4])
        XCTAssertEqual(first["retrigger_event_indices"] as? [Int], [1, 2])
        XCTAssertEqual(first["replaced_event_indices"] as? [Int], [0, 1])
        XCTAssertEqual(first["envelope_policy"] as? String, "fresh_event_restarts_envelope")
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

    func testDiagnosticsJSONIncludesNoteCutAndDelayFields() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(1), count: 8),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let song = PlaybackSong(
            title: "note-cut-delay-diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [
                2: PlaybackPattern(index: 2, rows: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x0E, effectParam: 0xD1)
                    ]),
                    PlaybackRow(index: 1, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0E, effectParam: 0xC1)
                    ])
                ])
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let noteCuts = try XCTUnwrap(object["note_cut_effects"] as? [[String: Any]])
        let noteDelays = try XCTUnwrap(object["note_delay_effects"] as? [[String: Any]])
        let effects = try XCTUnwrap(object["pattern_traversal_timing_effects"] as? [[String: Any]])
        let summary = try XCTUnwrap(object["traversal_hazard_summary"] as? [String: Any])
        let event = try XCTUnwrap(events.first)
        let delay = try XCTUnwrap(noteDelays.first)
        let cut = try XCTUnwrap(noteCuts.first)

        XCTAssertEqual(render["note_delay_effect_count"] as? Int, 1)
        XCTAssertEqual(render["note_cut_effect_count"] as? Int, 1)
        XCTAssertEqual(delay["status"] as? String, "applied")
        XCTAssertEqual(delay["requested_tick"] as? Int, 1)
        XCTAssertEqual(delay["row_speed"] as? Int, 3)
        XCTAssertEqual(delay["row_bpm"] as? Int, 250)
        XCTAssertEqual(delay["original_frame"] as? Int, 0)
        XCTAssertEqual(delay["delayed_frame"] as? Int, 1)
        XCTAssertEqual(delay["event_index"] as? Int, 0)
        XCTAssertEqual(cut["status"] as? String, "applied")
        XCTAssertEqual(cut["requested_tick"] as? Int, 1)
        XCTAssertEqual(cut["row_speed"] as? Int, 3)
        XCTAssertEqual(cut["row_bpm"] as? Int, 250)
        XCTAssertEqual(cut["scheduled_frame"] as? Int, 4)
        XCTAssertEqual(cut["absolute_frame"] as? Int, 4)
        XCTAssertEqual(cut["active_event_index"] as? Int, 0)
        XCTAssertEqual(cut["target_voice_index"] as? Int, 0)
        XCTAssertEqual(cut["target_voice_indices"] as? [Int], [0])
        XCTAssertEqual(event["scheduled_start_frame"] as? Int, 1)
        XCTAssertEqual(event["synthetic_tick"] as? Int, 1)
        XCTAssertEqual(event["estimated_end_frame"] as? Int, 4)
        XCTAssertEqual(event["estimated_duration_frames"] as? Int, 3)
        XCTAssertEqual(event["duration_estimate_reason"] as? String, "note_cut")
        XCTAssertEqual(summary["total_ecx_note_cut"] as? Int, 1)
        XCTAssertEqual(summary["total_edx_note_delay"] as? Int, 1)
        XCTAssertEqual(summary["total_other_e_commands"] as? Int, 0)
        XCTAssertTrue(effects.contains { item in
            item["effect_label"] as? String == "EDx note delay" && item["status"] as? String == "applied"
        })
        XCTAssertTrue(effects.contains { item in
            item["effect_label"] as? String == "ECx note cut" && item["status"] as? String == "applied"
        })
    }

    func testDiagnosticsJSONIncludesVolumePanningStateUpdateSummary() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: Float(1), count: 8),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let song = PlaybackSong(
            title: "state-updates",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [
                2: PlaybackPattern(index: 2, rows: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ]),
                    PlaybackRow(index: 1, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0x30, effectType: 0, effectParam: 0)
                    ]),
                    PlaybackRow(index: 2, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0xCF, effectType: 0, effectParam: 0)
                    ]),
                    PlaybackRow(index: 3, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0C, effectParam: 0x20)
                    ]),
                    PlaybackRow(index: 4, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x08, effectParam: 0xFF)
                    ]),
                    PlaybackRow(index: 5, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0A, effectParam: 0x04)
                    ]),
                    PlaybackRow(index: 6, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x11, effectParam: 0x10)
                    ])
                ])
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 7
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let capacity = try XCTUnwrap(try XCTUnwrap(object["event_coverage"] as? [String: Any])["capacity"] as? [String: Any])
        let summary = try XCTUnwrap(object["volume_panning_state_update_summary"] as? [String: Any])
        let updates = try XCTUnwrap(object["volume_panning_state_updates"] as? [[String: Any]])
        let effects = try XCTUnwrap(object["pattern_traversal_timing_effects"] as? [[String: Any]])
        let firstVolumeUpdate = try XCTUnwrap(updates.first { $0["command_name"] as? String == "setVolume" })
        let hxy = try XCTUnwrap(updates.first { $0["command_name"] as? String == "hxyGlobalVolumeSlide" })

        XCTAssertEqual(render["volume_panning_state_update_count"] as? Int, 6)
        XCTAssertEqual(render["active_voice_state_update_count"] as? Int, 5)
        XCTAssertEqual(render["gain_pan_ramp_enabled"] as? Bool, true)
        XCTAssertEqual(render["gain_pan_ramp_frame_count"] as? Int, CSoftwareMixer.gainPanUpdateRampFrameCount)
        XCTAssertEqual(render["gain_pan_update_count"] as? Int, 3)
        XCTAssertEqual(render["gain_pan_ramped_update_count"] as? Int, 3)
        XCTAssertEqual(render["gain_pan_interrupted_ramp_count"] as? Int, 1)
        XCTAssertEqual(capacity["c_mixer_voice_state_event_capacity"] as? Int, CSoftwareMixer.maximumVoiceStateEventCount)
        XCTAssertEqual(summary["total_state_updates"] as? Int, 6)
        XCTAssertEqual(summary["active_voice_updated_count"] as? Int, 5)
        XCTAssertEqual(summary["gain_pan_ramp_enabled"] as? Bool, true)
        XCTAssertEqual(summary["gain_pan_ramp_frame_count"] as? Int, CSoftwareMixer.gainPanUpdateRampFrameCount)
        XCTAssertEqual(summary["gain_pan_update_count"] as? Int, 3)
        XCTAssertEqual(summary["gain_pan_ramped_update_count"] as? Int, 3)
        XCTAssertEqual(summary["gain_pan_interrupted_ramp_count"] as? Int, 1)
        XCTAssertEqual(summary["empty_note_volume_column_set_volume_applied"] as? Int, 1)
        XCTAssertEqual(summary["empty_note_volume_column_set_panning_applied"] as? Int, 1)
        XCTAssertEqual(summary["cxx_set_volume_applied"] as? Int, 1)
        XCTAssertEqual(summary["effect_8xx_set_panning_applied"] as? Int, 1)
        XCTAssertEqual(summary["axy_volume_slide_applied"] as? Int, 1)
        XCTAssertEqual(summary["hxy_global_volume_slide_applied"] as? Int, 1)
        XCTAssertEqual(summary["hxy_global_volume_slide_deferred"] as? Int, 0)
        XCTAssertEqual(summary["hxy_global_volume_slide_clamped_count"] as? Int, 1)
        XCTAssertEqual(firstVolumeUpdate["scheduled_frame"] as? Int, 1)
        XCTAssertEqual(firstVolumeUpdate["active_voice_updated"] as? Bool, true)
        XCTAssertEqual(firstVolumeUpdate["gain_pan_ramp_enabled"] as? Bool, true)
        XCTAssertEqual(firstVolumeUpdate["gain_pan_ramp_frame_count"] as? Int, CSoftwareMixer.gainPanUpdateRampFrameCount)
        XCTAssertEqual(firstVolumeUpdate["effective_volume_before"] as? Int, 64)
        XCTAssertEqual(firstVolumeUpdate["effective_volume_after"] as? Int, 32)
        XCTAssertEqual(firstVolumeUpdate["gain_before"] as? Double, 1)
        XCTAssertEqual(firstVolumeUpdate["gain_after"] as? Double, 0.5)
        XCTAssertEqual(hxy["status"] as? String, "applied")
        XCTAssertEqual(hxy["active_voice_updated"] as? Bool, false)
        XCTAssertEqual(hxy["global_volume_before"] as? Int, 64)
        XCTAssertEqual(hxy["global_volume_after"] as? Int, 64)
        XCTAssertEqual(hxy["global_volume_slide_direction"] as? String, "up")
        XCTAssertEqual(hxy["global_volume_slide_clamped"] as? Bool, true)
        XCTAssertTrue(effects.contains { $0["effect_label"] as? String == "Cxx set volume" && $0["status"] as? String == "applied" })
        XCTAssertTrue(effects.contains { $0["effect_label"] as? String == "8xx set panning" && $0["status"] as? String == "applied" })
        XCTAssertTrue(effects.contains { $0["effect_label"] as? String == "Axy volume slide" && $0["status"] as? String == "applied" })
        XCTAssertTrue(effects.contains { $0["effect_label"] as? String == "Hxy global volume slide" && $0["status"] as? String == "applied" })
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
        XCTAssertEqual(summary["total_e9x_retrigger"] as? Int, 1)
        XCTAssertEqual(summary["total_other_e_commands"] as? Int, 0)
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
        XCTAssertEqual(e9x["current_status"] as? String, "applied")
        XCTAssertEqual(fxx["current_status"] as? String, "applied")
        XCTAssertEqual(fxx["is_traversal_hazard"] as? Bool, false)
    }

    func testDiagnosticsJSONCountsDeferredPitchModulationEffectsWithCoordinates() throws {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [1], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 100)
        let cells = [
            (0, 0x00, 0x37), (0, 0x01, 0x08), (0, 0x02, 0x09), (0, 0x03, 0x10),
            (0, 0x04, 0x48), (0, 0x05, 0x20), (0, 0x06, 0x30), (0, 0x07, 0x48),
            (0xA4, 0, 0), (0xB5, 0, 0), (0xF6, 0, 0),
        ].map { PlaybackCell(note: 49, instrument: 1, volumeColumn: UInt8($0.0), effectType: UInt8($0.1), effectParam: UInt8($0.2)) }
        let row = PlaybackRow(index: 0, cells: cells)
        let song = PlaybackSong(
            title: "pitch-modulation-diagnostics",
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
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let summary = try XCTUnwrap(object["pitch_modulation_deferred_effect_summary"] as? [String: Any])
        let coordinates = try XCTUnwrap(object["pitch_modulation_deferred_effects"] as? [[String: Any]])
        let effects = try XCTUnwrap(object["pattern_traversal_timing_effects"] as? [[String: Any]])
        let first = try XCTUnwrap(coordinates.first)
        let volumeTonePortamento = try XCTUnwrap(coordinates.first { $0["effect_label"] as? String == "volume-column tone portamento" })
        let effectTonePortamento = try XCTUnwrap(effects.first { $0["effect_label"] as? String == "3xx tone portamento" })
        let portamentoSlides = try XCTUnwrap(object["portamento_slide_effects"] as? [[String: Any]])

        [
            "total_arpeggio_count",
            "total_vibrato_count",
            "total_tone_portamento_volume_slide_count",
            "total_vibrato_volume_slide_count",
            "total_tremolo_count",
            "total_volume_column_vibrato_speed_count",
            "total_volume_column_vibrato_count",
            "total_volume_column_tone_portamento_count",
        ].forEach { XCTAssertEqual(summary[$0] as? Int, 1) }
        XCTAssertEqual(summary["total_portamento_up_count"] as? Int, 0)
        XCTAssertEqual(summary["total_portamento_down_count"] as? Int, 0)
        XCTAssertEqual(summary["total_tone_portamento_count"] as? Int, 0)
        XCTAssertEqual(summary["total_deferred_pitch_modulation_effect_count"] as? Int, 8)
        XCTAssertEqual(render["pitch_modulation_deferred_effect_count"] as? Int, 8)
        XCTAssertEqual(render["tone_portamento_3xx_effect_count"] as? Int, 1)
        XCTAssertEqual(render["tone_portamento_3xx_no_active_voice_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_1xx_effect_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_1xx_applied_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_2xx_effect_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_2xx_applied_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_slide_effect_count"] as? Int, 2)
        XCTAssertEqual(render["portamento_slide_applied_count"] as? Int, 2)
        XCTAssertEqual(coordinates.count, 8)
        XCTAssertEqual(portamentoSlides.count, 2)
        XCTAssertEqual(portamentoSlides.map { $0["current_status"] as? String }, ["applied", "applied"])
        XCTAssertEqual(portamentoSlides.map { $0["slide_direction"] as? String }, ["up", "down"])
        XCTAssertEqual((first["source"] as? [String: Any])?["order"] as? Int, 0)
        XCTAssertEqual((first["source"] as? [String: Any])?["pattern"] as? Int, 2)
        XCTAssertEqual((first["source"] as? [String: Any])?["row"] as? Int, 0)
        XCTAssertEqual(first["channel_index"] as? Int, 0)
        XCTAssertEqual(first["effect_type"] as? Int, 0)
        XCTAssertEqual(first["effect_param"] as? Int, 0x37)
        XCTAssertEqual(first["effect_label"] as? String, "0xy arpeggio")
        XCTAssertEqual(first["current_status"] as? String, "deferred/unsupported")
        XCTAssertEqual(volumeTonePortamento["command_source"] as? String, "volume_column")
        XCTAssertEqual(volumeTonePortamento["effect_param"] as? Int, 0xF6)
        XCTAssertEqual(volumeTonePortamento["current_status"] as? String, "deferred/unsupported")
        XCTAssertEqual(effectTonePortamento["current_status"] as? String, "applied")
        XCTAssertFalse(coordinates.contains { $0["effect_label"] as? String == "3xx tone portamento" })
        XCTAssertFalse(coordinates.contains { $0["effect_label"] as? String == "1xx portamento up" })
        XCTAssertFalse(coordinates.contains { $0["effect_label"] as? String == "2xx portamento down" })
        XCTAssertTrue(coordinates.contains { $0["effect_label"] as? String == "5xy tone portamento + volume slide" })
        XCTAssertTrue(coordinates.contains { $0["effect_label"] as? String == "6xy vibrato + volume slide" })
        XCTAssertTrue(coordinates.contains { $0["effect_label"] as? String == "7xy tremolo" })
    }

    func testDiagnosticsJSONReportsAppliedTonePortamento3xxDetails() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: (0..<300).map { Float($0) / 1_000.0 },
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let rows = [
            PlaybackRow(index: 0, cells: [PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)]),
            PlaybackRow(index: 1, cells: [PlaybackCell(note: 61, instrument: 1, volumeColumn: 0, effectType: 0x03, effectParam: 0x40)]),
        ]
        let song = PlaybackSong(
            title: "tone-portamento-diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: rows)],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let tonePortamento = try XCTUnwrap(object["tone_portamento_effects"] as? [[String: Any]])
        let diagnostic: [String: Any] = try XCTUnwrap(tonePortamento.first)
        let stepUpdates = try XCTUnwrap(diagnostic["step_updates"] as? [[String: Any]])
        let targetStep = try XCTUnwrap(diagnostic["target_step"] as? Double)
        let firstStepBefore = try XCTUnwrap(stepUpdates.first?["current_step_before"] as? Double)

        XCTAssertEqual(render["tone_portamento_3xx_effect_count"] as? Int, 1)
        XCTAssertEqual(render["tone_portamento_3xx_applied_count"] as? Int, 1)
        XCTAssertEqual(render["tone_portamento_3xx_no_active_voice_count"] as? Int, 0)
        XCTAssertEqual(diagnostic["current_status"] as? String, "applied")
        XCTAssertEqual(diagnostic["active_voice_found"] as? Bool, true)
        XCTAssertEqual(diagnostic["target_note"] as? Int, 61)
        XCTAssertEqual(targetStep, 2, accuracy: 0.000_001)
        XCTAssertEqual(diagnostic["portamento_speed"] as? Int, 0x40)
        XCTAssertEqual(stepUpdates.map { $0["scheduled_frame"] as? Int }, [5, 6, 7])
        XCTAssertEqual(firstStepBefore, 1, accuracy: 0.000_001)
    }

    func testDiagnosticsJSONReportsAppliedPortamentoSlideDetails() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: (0..<300).map { Float($0) / 1_000.0 },
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let rows = [
            PlaybackRow(index: 0, cells: [PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)]),
            PlaybackRow(index: 1, cells: [PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x01, effectParam: 0x40)]),
            PlaybackRow(index: 2, cells: [PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x02, effectParam: 0x20)]),
        ]
        let song = PlaybackSong(
            title: "portamento-slide-diagnostics",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 2)],
            patternsByIndex: [2: PlaybackPattern(index: 2, rows: rows)],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        ))

        let object = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
        let render = try XCTUnwrap(object["render"] as? [String: Any])
        let diagnostics = try XCTUnwrap(object["portamento_slide_effects"] as? [[String: Any]])
        let up = try XCTUnwrap(diagnostics.first { $0["slide_direction"] as? String == "up" })
        let down = try XCTUnwrap(diagnostics.first { $0["slide_direction"] as? String == "down" })
        let upUpdates = try XCTUnwrap(up["step_updates"] as? [[String: Any]])
        let downUpdates = try XCTUnwrap(down["step_updates"] as? [[String: Any]])
        let upStepBefore = try XCTUnwrap(up["current_step_before"] as? Double)
        let upStepAfter = try XCTUnwrap(up["current_step_after"] as? Double)
        let downStepBefore = try XCTUnwrap(down["current_step_before"] as? Double)
        let downStepAfter = try XCTUnwrap(down["current_step_after"] as? Double)

        XCTAssertEqual(render["portamento_slide_effect_count"] as? Int, 2)
        XCTAssertEqual(render["portamento_slide_applied_count"] as? Int, 2)
        XCTAssertEqual(render["portamento_1xx_effect_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_1xx_applied_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_2xx_effect_count"] as? Int, 1)
        XCTAssertEqual(render["portamento_2xx_applied_count"] as? Int, 1)
        XCTAssertEqual(up["current_status"] as? String, "applied")
        XCTAssertEqual(up["slide_amount"] as? Int, 0x40)
        XCTAssertEqual(up["row_speed"] as? Int, 4)
        XCTAssertEqual(up["row_bpm"] as? Int, 250)
        XCTAssertEqual(upUpdates.map { $0["scheduled_frame"] as? Int }, [5, 6, 7])
        XCTAssertGreaterThan(upStepAfter, upStepBefore)
        XCTAssertEqual(down["current_status"] as? String, "applied")
        XCTAssertEqual(down["slide_amount"] as? Int, 0x20)
        XCTAssertEqual(downUpdates.map { $0["scheduled_frame"] as? Int }, [9, 10, 11])
        XCTAssertLessThan(downStepAfter, downStepBefore)
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

    private func generatedPlayableXMPath(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("generated-playable.xm")
        try generatedPlayableXMData().write(to: url)
        return url
    }

    private func generatedPlayableXMData() -> Data {
        var data = Data()

        appendFixedString("Extended Module: ", count: 17, padding: 0x20, to: &data)
        appendFixedString("VTX PLAYABLE TEST", count: 20, padding: 0x20, to: &data)
        data.append(0x1A)
        appendFixedString("VTX TEST", count: 20, padding: 0x20, to: &data)
        appendLE16(0x0104, to: &data)
        appendLE32(276, to: &data)
        appendLE16(1, to: &data) // song length
        appendLE16(0, to: &data) // restart position
        appendLE16(1, to: &data) // channels
        appendLE16(1, to: &data) // patterns
        appendLE16(1, to: &data) // instruments
        appendLE16(1, to: &data) // linear frequency table
        appendLE16(6, to: &data)
        appendLE16(125, to: &data)
        data.append(0)
        data.append(contentsOf: repeatElement(UInt8(0), count: 255))

        let patternData: [UInt8] = [
            49, 1, 0x40, 0x0F, 0x06,
            0x80,
            0x80,
            0x80
        ]
        appendLE32(9, to: &data)
        data.append(0)
        appendLE16(4, to: &data)
        appendLE16(patternData.count, to: &data)
        data.append(contentsOf: patternData)

        var instrument = Data(count: 263)
        writeLE32(263, to: &instrument, at: 0)
        writeFixedString("PLAYABLE", to: &instrument, at: 4, count: 22, padding: 0)
        writeLE16(1, to: &instrument, at: 27)
        writeLE32(40, to: &instrument, at: 29)
        data.append(instrument)

        var sampleHeader = Data(count: 40)
        writeLE32(64, to: &sampleHeader, at: 0)
        writeLE32(0, to: &sampleHeader, at: 4)
        writeLE32(64, to: &sampleHeader, at: 8)
        sampleHeader[12] = 64
        sampleHeader[14] = 1
        sampleHeader[15] = 128
        writeFixedString("LOOP", to: &sampleHeader, at: 18, count: 22, padding: 0)
        data.append(sampleHeader)

        data.append(32)
        data.append(contentsOf: repeatElement(UInt8(0), count: 63))

        return data
    }

    private func appendLE16(_ value: Int, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendLE32(_ value: Int, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func appendFixedString(_ value: String, count: Int, padding: UInt8, to data: inout Data) {
        let bytes = Array(value.utf8.prefix(count))
        data.append(contentsOf: bytes)
        if bytes.count < count {
            data.append(contentsOf: repeatElement(padding, count: count - bytes.count))
        }
    }

    private func writeLE16(_ value: Int, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private func writeLE32(_ value: Int, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeFixedString(_ value: String, to data: inout Data, at offset: Int, count: Int, padding: UInt8) {
        let bytes = Array(value.utf8.prefix(count))
        for index in 0..<count {
            data[offset + index] = index < bytes.count ? bytes[index] : padding
        }
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

    private func songWithRows(
        _ rowCount: Int,
        timing: PlaybackTiming = .xmDefault
    ) -> PlaybackSong {
        PlaybackSong(
            title: "rows",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [
                0: PlaybackPattern(index: 0, rows: (0..<rowCount).map { rowIndex in
                    PlaybackRow(index: rowIndex, cells: [])
                })
            ],
            instrumentsByIndex: [:],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd,
            initialTiming: timing
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
