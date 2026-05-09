import Foundation
import os

@MainActor
protocol PlaybackTraceWriting: AnyObject {
    var isEnabled: Bool { get }

    func record(_ event: PlaybackTraceEvent)
    func flush()
}

@MainActor
final class NoopPlaybackTraceWriter: PlaybackTraceWriting {
    static let shared = NoopPlaybackTraceWriter()

    let isEnabled = false

    private init() {}

    func record(_ event: PlaybackTraceEvent) {}

    func flush() {}
}

enum PlaybackTraceJSONLFormatter {
    static func line(for event: PlaybackTraceEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }
}

@MainActor
final class PlaybackTraceJSONLWriter: PlaybackTraceWriting {
    let isEnabled = true

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "PlaybackTrace")
    private let fileHandle: FileHandle

    init(url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.truncate(atOffset: 0)
    }

    deinit {
        try? fileHandle.close()
    }

    func record(_ event: PlaybackTraceEvent) {
        do {
            try fileHandle.write(contentsOf: PlaybackTraceJSONLFormatter.line(for: event))
        } catch {
            logger.error("Unable to write playback trace event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flush() {
        try? fileHandle.synchronize()
    }
}
