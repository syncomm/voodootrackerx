import Foundation

enum WAVExportSamplePayloadCopyMode: String, Equatable, Sendable {
    case perVoiceDefensiveCopy = "per_voice_defensive_copy"
    case perVoicePreSanitizedCopy = "per_voice_pre_sanitized_copy"
    case sharedCPayload = "shared_c_payload"

    init(storageMode: PlaybackSongOfflineSamplePayloadStorageMode) {
        switch storageMode {
        case .perVoiceDefensiveCopy:
            self = .perVoiceDefensiveCopy
        case .perVoicePreSanitizedCopy:
            self = .perVoicePreSanitizedCopy
        case .sharedCPayload:
            self = .sharedCPayload
        }
    }
}

/// Concise, public-safe metrics for one completed app WAV export.
///
/// The values aggregate existing render/export instrumentation only. Some phase
/// durations are nested measurements and are not intended to sum to `totalDurationSeconds`.
struct WAVExportPerformanceSummary: Equatable, Sendable {
    let totalDurationSeconds: Double
    let planAndAdaptDurationSeconds: Double
    let preparationIndexDurationSeconds: Double
    let renderDurationSeconds: Double
    let headroomPostProcessDurationSeconds: Double
    let writeAndAtomicReplaceDurationSeconds: Double
    let renderWindowCount: Int
    let totalFramesPlanned: Int
    let totalFramesRendered: Int
    let scheduledEventCount: Int
    let acceptedEventCount: Int
    let rejectedEventCount: Int
    let carriedVoiceCount: Int
    let boundaryDropCount: Int
    let mayContainBoundaryCuts: Bool
    let sharedSamplePayloadCount: Int
    let sharedSamplePayloadBytes: Int
    let sharedSamplePayloadVoiceReferenceCount: Int
    let avoidedSamplePayloadUploadCount: Int
    let avoidedSamplePayloadUploadBytes: Int
    let fallbackCopiedSamplePayloadUploadCount: Int
    let fallbackCopiedSamplePayloadUploadBytes: Int
    let uploadCopyMode: WAVExportSamplePayloadCopyMode
    let autoHeadroomGain: Float
    let usedUnityGainFastPath: Bool

    init?(renderResult: PlaybackSongOfflineStreamingRenderResult) {
        guard let exportPerformance = renderResult.wavExportPerformanceDiagnostics,
              let renderPerformance = exportPerformance.renderPerformanceDiagnostics,
              let exportDiagnostics = renderResult.exportDiagnostics else {
            return nil
        }

        let planDuration = exportPerformance.planPerformanceDiagnostics.totalDurationSeconds
        totalDurationSeconds = planDuration + exportPerformance.totalExportDurationSeconds
        planAndAdaptDurationSeconds = planDuration + renderPerformance.planAdaptDurationSeconds
        preparationIndexDurationSeconds = renderPerformance.windowedRenderIndexDiagnostics?.buildDurationSeconds ?? 0
        renderDurationSeconds = exportPerformance.renderPhaseDurationSeconds
        headroomPostProcessDurationSeconds = exportPerformance.headroomPostProcessDurationSeconds
        writeAndAtomicReplaceDurationSeconds = exportPerformance.tempWAVWriteDurationSeconds
            + exportPerformance.finalAtomicReplaceDurationSeconds
        renderWindowCount = exportPerformance.renderWindowCount
        totalFramesPlanned = exportPerformance.totalFramesPlanned
        totalFramesRendered = exportPerformance.totalFramesRendered
        scheduledEventCount = renderPerformance.totalScheduledEvents
        acceptedEventCount = renderPerformance.totalAcceptedScheduledEvents
        rejectedEventCount = renderPerformance.totalRejectedScheduledEvents
        carriedVoiceCount = renderPerformance.totalCarriedVoices
        boundaryDropCount = renderPerformance.totalDroppedAtWindowBoundaries
        mayContainBoundaryCuts = renderPerformance.mayContainBoundaryCuts
        sharedSamplePayloadCount = renderPerformance.sharedSamplePayloadCreateCount
        sharedSamplePayloadBytes = renderPerformance.sharedSamplePayloadBytesAllocated
        sharedSamplePayloadVoiceReferenceCount = renderPerformance.sharedSamplePayloadVoiceReferenceCount
        avoidedSamplePayloadUploadCount = renderPerformance.avoidedPerVoiceSamplePayloadUploadCount
        avoidedSamplePayloadUploadBytes = renderPerformance.approximateAvoidedPerVoiceSamplePayloadUploadBytes
        fallbackCopiedSamplePayloadUploadCount = max(
            0,
            renderPerformance.samplePayloadUploadCount - renderPerformance.sharedSamplePayloadCreateCount
        )
        fallbackCopiedSamplePayloadUploadBytes = max(
            0,
            renderPerformance.approximateSamplePayloadBytesCopied
                - renderPerformance.sharedSamplePayloadBytesAllocated
        )
        uploadCopyMode = WAVExportSamplePayloadCopyMode(storageMode: renderPerformance.samplePayloadStorageMode)
        autoHeadroomGain = exportDiagnostics.computedExportGain
        usedUnityGainFastPath = exportPerformance.usedUnityGainFastPath
    }
}

extension WAVExportCompletionResult {
    var performanceSummary: WAVExportPerformanceSummary? {
        guard case let .exported(_, renderResult) = self else {
            return nil
        }
        return WAVExportPerformanceSummary(renderResult: renderResult)
    }
}

enum WAVExportPerformanceSummaryFormatter {
    static func line(for summary: WAVExportPerformanceSummary) -> String {
        [
            "vtx_wav_export_performance_summary",
            "schema=1",
            "total_s=\(seconds(summary.totalDurationSeconds))",
            "plan_adapt_s=\(seconds(summary.planAndAdaptDurationSeconds))",
            "prepare_index_s=\(seconds(summary.preparationIndexDurationSeconds))",
            "render_s=\(seconds(summary.renderDurationSeconds))",
            "headroom_post_s=\(seconds(summary.headroomPostProcessDurationSeconds))",
            "write_replace_s=\(seconds(summary.writeAndAtomicReplaceDurationSeconds))",
            "windows=\(summary.renderWindowCount)",
            "frames_planned=\(summary.totalFramesPlanned)",
            "frames_rendered=\(summary.totalFramesRendered)",
            "events_scheduled=\(summary.scheduledEventCount)",
            "events_accepted=\(summary.acceptedEventCount)",
            "events_rejected=\(summary.rejectedEventCount)",
            "carried_voices=\(summary.carriedVoiceCount)",
            "boundary_drops=\(summary.boundaryDropCount)",
            "may_contain_boundary_cuts=\(summary.mayContainBoundaryCuts)",
            "shared_payloads=\(summary.sharedSamplePayloadCount)",
            "shared_payload_bytes=\(summary.sharedSamplePayloadBytes)",
            "shared_payload_voice_refs=\(summary.sharedSamplePayloadVoiceReferenceCount)",
            "avoided_uploads=\(summary.avoidedSamplePayloadUploadCount)",
            "avoided_upload_bytes=\(summary.avoidedSamplePayloadUploadBytes)",
            "fallback_copied_uploads=\(summary.fallbackCopiedSamplePayloadUploadCount)",
            "fallback_copied_upload_bytes=\(summary.fallbackCopiedSamplePayloadUploadBytes)",
            "upload_copy_mode=\(summary.uploadCopyMode.rawValue)",
            "auto_headroom_gain=\(gain(summary.autoHeadroomGain))",
            "unity_fast_path=\(summary.usedUnityGainFastPath)",
        ].joined(separator: " ")
    }

    private static func seconds(_ value: Double) -> String {
        formatted(value.isFinite ? max(0, value) : 0, decimalPlaces: 3)
    }

    private static func gain(_ value: Float) -> String {
        let safeValue = value.isFinite ? max(0, Double(value)) : 0
        return formatted(safeValue, decimalPlaces: 6)
    }

    private static func formatted(_ value: Double, decimalPlaces: Int) -> String {
        String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            decimalPlaces,
            value
        )
    }
}

protocol WAVExportPerformanceSummarySinking: AnyObject {
    func writeWAVExportPerformanceSummaryLine(_ line: String)
}

final class StandardErrorWAVExportPerformanceSummarySink: WAVExportPerformanceSummarySinking, @unchecked Sendable {
    static let shared = StandardErrorWAVExportPerformanceSummarySink()

    private let lock = NSLock()

    private init() {}

    func writeWAVExportPerformanceSummaryLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        lock.lock()
        FileHandle.standardError.write(data)
        lock.unlock()
    }
}

enum WAVExportPerformanceSummaryLogger {
    static let enabledEnvironmentKey = "VTX_WAV_EXPORT_PERFORMANCE_SUMMARY"

    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let rawValue = environment[enabledEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !rawValue.isEmpty else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }

    static func writeIfEnabled(
        _ result: WAVExportCompletionResult,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sink: WAVExportPerformanceSummarySinking = StandardErrorWAVExportPerformanceSummarySink.shared
    ) {
        guard isEnabled(environment: environment),
              let summary = result.performanceSummary else {
            return
        }
        sink.writeWAVExportPerformanceSummaryLine(WAVExportPerformanceSummaryFormatter.line(for: summary))
    }
}
