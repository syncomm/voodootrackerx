import Foundation
import os

enum PlaybackTraceConfiguration {
    static let pathEnvironmentKey = "VTX_PLAYBACK_TRACE_PATH"

    @MainActor
    static func makeWriter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PlaybackTraceWriting {
        #if DEBUG
        guard let rawPath = environment[pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return NoopPlaybackTraceWriter.shared
        }

        let expandedPath = NSString(string: rawPath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        do {
            return try PlaybackTraceJSONLWriter(url: url)
        } catch {
            Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "PlaybackTrace")
                .error("Unable to open playback trace at \(expandedPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return NoopPlaybackTraceWriter.shared
        }
        #else
        return NoopPlaybackTraceWriter.shared
        #endif
    }
}
