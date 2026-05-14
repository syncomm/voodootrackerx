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
        XCTAssertEqual(render["rendered_frame_count"] as? Int, result.renderedFrameCount)
        XCTAssertEqual(events.count, result.diagnostics.emittedEventCount)
        XCTAssertFalse(String(decoding: diagnosticsData, as: UTF8.self).contains(fixturePath("minimal.xm").path))
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

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vtx-render-bounded-xm-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
