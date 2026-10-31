import Dispatch
import Darwin
import Foundation

enum VTXPerformanceClock {
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func seconds(since start: UInt64, to end: UInt64 = now()) -> Double {
        guard end >= start else {
            return 0
        }
        return Double(end - start) / 1_000_000_000.0
    }
}

struct PlaybackSongRenderIsolationFilter: Equatable {
    let soloChannelIndex: Int?
    let soloInstrumentIndex: Int?
    let soloSampleIndex: Int?

    init(
        soloChannelIndex: Int? = nil,
        soloInstrumentIndex: Int? = nil,
        soloSampleIndex: Int? = nil
    ) {
        self.soloChannelIndex = soloChannelIndex.map { max(0, $0) }
        self.soloInstrumentIndex = soloInstrumentIndex.map { max(1, $0) }
        self.soloSampleIndex = soloSampleIndex.map { max(0, $0) }
    }

    var isEnabled: Bool {
        soloChannelIndex != nil || soloInstrumentIndex != nil || soloSampleIndex != nil
    }

    func includes(_ mapping: PlaybackSongSyntheticEventMapping) -> Bool {
        if let soloChannelIndex, mapping.channelIndex != soloChannelIndex {
            return false
        }
        if let soloInstrumentIndex, mapping.instrumentIndex != soloInstrumentIndex {
            return false
        }
        if let soloSampleIndex, mapping.sampleIndex != soloSampleIndex {
            return false
        }
        return true
    }
}

struct PlaybackSongOfflineRenderRequest: Equatable {
    static let defaultMaximumFrameCount = OfflineRenderRequest.defaultMaximumFrameCount

    let song: PlaybackSong
    let startOrderIndex: Int
    let orderCount: Int
    let config: MixerRenderConfig
    let requestedFrameCount: Int
    let maximumFrameCount: Int
    let isolationFilter: PlaybackSongRenderIsolationFilter?

    var boundedFrameCount: Int {
        min(requestedFrameCount, maximumFrameCount)
    }

    var wasFrameCountBounded: Bool {
        requestedFrameCount > maximumFrameCount
    }

    init(
        song: PlaybackSong,
        startOrderIndex: Int = 0,
        orderCount: Int = 1,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount,
        isolationFilter: PlaybackSongRenderIsolationFilter? = nil
    ) {
        self.song = song
        self.startOrderIndex = startOrderIndex
        self.orderCount = max(0, orderCount)
        self.config = config
        requestedFrameCount = max(0, frames)
        self.maximumFrameCount = max(0, maximumFrameCount)
        self.isolationFilter = isolationFilter?.isEnabled == true ? isolationFilter : nil
    }

    init(
        song: PlaybackSong,
        orderIndex: Int,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount,
        isolationFilter: PlaybackSongRenderIsolationFilter? = nil
    ) {
        self.init(
            song: song,
            startOrderIndex: orderIndex,
            orderCount: 1,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount,
            isolationFilter: isolationFilter
        )
    }

    init(
        song: PlaybackSong,
        orderRange: Range<Int>,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount,
        isolationFilter: PlaybackSongRenderIsolationFilter? = nil
    ) {
        self.init(
            song: song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: orderRange.count,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount,
            isolationFilter: isolationFilter
        )
    }

    init(
        song: PlaybackSong,
        startOrderIndex: Int = 0,
        orderCount: Int = 1,
        config: MixerRenderConfig = MixerRenderConfig(),
        rows: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount,
        isolationFilter: PlaybackSongRenderIsolationFilter? = nil
    ) {
        let timing = PlaybackSongFxxTimingPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            sampleRate: config.sampleRate
        )
        self.init(
            song: song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            config: config,
            frames: timing.frameFor(row: max(0, rows), tick: 0),
            maximumFrameCount: maximumFrameCount,
            isolationFilter: isolationFilter
        )
    }

    func replacingFrameCount(_ frameCount: Int, maximumFrameCount: Int? = nil) -> PlaybackSongOfflineRenderRequest {
        PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            config: config,
            frames: frameCount,
            maximumFrameCount: maximumFrameCount ?? self.maximumFrameCount,
            isolationFilter: isolationFilter
        )
    }
}

/// Result from rendering an adapted `PlaybackSong` segment through the C-backed offline mixer.
struct PlaybackSongScheduledVoiceAttempt: Equatable {
    let eventIndex: Int
    let voiceIndex: Int?
    let rejectionReason: CSoftwareMixerScheduledVoiceRejectionReason?
    let windowIndex: Int?
}

enum PlaybackSongOfflineSamplePayloadStorageMode: Equatable, Sendable {
    case perVoiceDefensiveCopy
    case perVoicePreSanitizedCopy
    case sharedCPayload

    var cUploadMode: CSoftwareMixerSamplePayloadUploadMode {
        switch self {
        case .perVoiceDefensiveCopy:
            .defensiveSanitizingCopy
        case .perVoicePreSanitizedCopy:
            .preSanitizedBulkCopy
        case .sharedCPayload:
            .sharedPreSanitizedCache
        }
    }

    init(cUploadMode: CSoftwareMixerSamplePayloadUploadMode) {
        switch cUploadMode {
        case .defensiveSanitizingCopy:
            self = .perVoiceDefensiveCopy
        case .preSanitizedBulkCopy:
            self = .perVoicePreSanitizedCopy
        case .sharedPreSanitizedCache:
            self = .sharedCPayload
        }
    }
}

struct PlaybackSongRenderWindowPerformanceDiagnostic: Equatable {
    let windowIndex: Int
    let schedulingDurationSeconds: Double
    let cMixerRenderDurationSeconds: Double
    let totalWindowDurationSeconds: Double
    let cMixerVoiceAddCount: Int
    let samplePayloadUploadCount: Int
    let approximateSamplePayloadBytesCopied: Int
    let continuationSamplePayloadUploadCount: Int
    let approximateContinuationSamplePayloadBytesCopied: Int
    let continuationSharedSamplePayloadVoiceReferenceCount: Int
    let uniqueSamplePayloadIdentityCount: Int
    let duplicateSamplePayloadUploadCount: Int
    let defensiveSanitizingUploadCount: Int
    let preSanitizedBulkCopyUploadCount: Int
    let sharedSamplePayloadCreateCount: Int
    let sharedSamplePayloadBytesAllocated: Int
    let sharedSamplePayloadVoiceReferenceCount: Int
    let avoidedPerVoiceSamplePayloadUploadCount: Int
    let approximateAvoidedPerVoiceSamplePayloadUploadBytes: Int
}

struct PlaybackSongRenderPerformanceDiagnostics: Equatable {
    let totalDurationSeconds: Double
    let planAdaptDurationSeconds: Double
    let samplePayloadStorageMode: PlaybackSongOfflineSamplePayloadStorageMode
    let usedPreindexedWindowScheduling: Bool
    let preindexedWindowSchedulingConsumedWindowCount: Int
    let windowedRenderIndexDiagnostics: PlaybackSongWindowedRenderIndexDiagnostics?
    let totalWindowSchedulingDurationSeconds: Double
    let totalCMixerRenderDurationSeconds: Double
    let renderWindowCount: Int
    let windowRows: Int
    let totalFramesPlanned: Int
    let totalFramesRendered: Int
    let totalScheduledEvents: Int
    let totalAcceptedScheduledEvents: Int
    let totalRejectedScheduledEvents: Int
    let totalScheduledCapacityRejects: Int
    let totalInvalidScheduledVoiceRejects: Int
    let totalCarriedVoices: Int
    let totalBoundaryContinuations: Int
    let totalDroppedAtWindowBoundaries: Int
    let mayContainBoundaryCuts: Bool
    let cMixerVoiceAddCount: Int
    let samplePayloadUploadCount: Int
    let approximateSamplePayloadBytesCopied: Int
    let continuationSamplePayloadUploadCount: Int
    let approximateContinuationSamplePayloadBytesCopied: Int
    let continuationSharedSamplePayloadVoiceReferenceCount: Int
    let uniqueSamplePayloadIdentityCount: Int
    let duplicateSamplePayloadUploadCount: Int
    let defensiveSanitizingUploadCount: Int
    let preSanitizedBulkCopyUploadCount: Int
    let sharedSamplePayloadCreateCount: Int
    let sharedSamplePayloadBytesAllocated: Int
    let sharedSamplePayloadVoiceReferenceCount: Int
    let avoidedPerVoiceSamplePayloadUploadCount: Int
    let approximateAvoidedPerVoiceSamplePayloadUploadBytes: Int
    let windows: [PlaybackSongRenderWindowPerformanceDiagnostic]
}

struct WAVExportPlanPerformanceDiagnostics: Equatable {
    let totalDurationSeconds: Double
    let songBuildDurationSeconds: Double
    let traversalPlanningDurationSeconds: Double
    let durationTimingPlanningDurationSeconds: Double
    let wavLayoutValidationDurationSeconds: Double
    let totalFramesPlanned: Int
    let renderWindowCount: Int
}

struct WAVExportWindowWritePerformanceDiagnostic: Equatable {
    let windowIndex: Int
    let tempWAVWriteDurationSeconds: Double
}

struct WAVExportPerformanceDiagnostics: Equatable {
    let totalExportDurationSeconds: Double
    let planPerformanceDiagnostics: WAVExportPlanPerformanceDiagnostics
    let renderPhaseDurationSeconds: Double
    let tempWAVWriteDurationSeconds: Double
    let headroomPostProcessDurationSeconds: Double
    let usedUnityGainFastPath: Bool
    let finalAtomicReplaceDurationSeconds: Double
    let totalFramesPlanned: Int
    let totalFramesRendered: Int
    let renderWindowCount: Int
    let windowRows: Int
    let renderPerformanceDiagnostics: PlaybackSongRenderPerformanceDiagnostics?
    let windowWriteDiagnostics: [WAVExportWindowWritePerformanceDiagnostic]
}

struct PlaybackSongWindowedRenderWindowDiagnostic: Equatable {
    let windowIndex: Int
    let startRow: Int
    let endRowExclusive: Int
    let startFrame: Int
    let endFrame: Int
    let renderedFrames: Int
    let carriedVoiceCount: Int
    let releasedVoiceCarryoverCount: Int
    let carriedTonePortamentoVoiceCount: Int
    let boundaryContinuationCount: Int
    let droppedAtWindowBoundaryCount: Int
    let mayContainBoundaryCuts: Bool
    let unsupportedCarryoverReasons: [String]
    let scheduledEventCount: Int
    let acceptedScheduledEventCount: Int
    let rejectedScheduledEventCount: Int
    let scheduledCapacityRejectedCount: Int
    let invalidScheduledVoiceRejectedCount: Int
    let performanceDiagnostics: PlaybackSongRenderWindowPerformanceDiagnostic?
}

struct PlaybackSongWindowedRenderSummary: Equatable {
    static let firstRejectingWindowLimit = 10
    static let stateCarryoverLimitations = [
        "Windowed offline renders now carry practical active voice state across fresh C mixer windows.",
        "Carryover is computed from the bounded adapter plan and includes sample position, forward/ping-pong loop state, envelope position, key-off/release, fadeout, gain, pan, and active 0xy/1xx/2xx/3xx/4xy/Xxy sample-step state.",
        "Unsupported/deferred XM effects and full FT2/OpenMPT parity remain out of scope, so effect-driven continuity can still be approximate.",
    ]

    let windowRows: Int
    let windows: [PlaybackSongWindowedRenderWindowDiagnostic]
    let totalRenderedFrames: Int
    let totalCarriedVoices: Int
    let totalReleasedVoiceCarryovers: Int
    let totalCarriedTonePortamentoVoices: Int
    let totalBoundaryContinuations: Int
    let totalDroppedAtWindowBoundaries: Int
    let mayContainBoundaryCuts: Bool
    let totalScheduledEvents: Int
    let totalAcceptedScheduledEvents: Int
    let totalRejectedScheduledEvents: Int
    let totalScheduledCapacityRejects: Int
    let totalInvalidScheduledVoiceRejects: Int
    let knownUnsupportedCarryoverReasons: [String]
    let knownStateCarryoverLimitations: [String]
    let performanceDiagnostics: PlaybackSongRenderPerformanceDiagnostics?

    var windowCount: Int {
        windows.count
    }

    var firstWindowsWithRejects: [PlaybackSongWindowedRenderWindowDiagnostic] {
        Array(windows.filter { $0.rejectedScheduledEventCount > 0 }.prefix(Self.firstRejectingWindowLimit))
    }
}

enum PlaybackSongWindowSchedulingUpdateKind: String, CaseIterable, Hashable {
    case envelopePosition
    case voiceGainPan
    case tonePortamentoStep
    case portamentoSlideStep
    case finePortamentoUpStep
    case finePortamentoDownStep
    case extraFinePortamentoStep
    case arpeggioStep
    case vibratoStep
    case instrumentAutoPitchStep
    case noteCut
    case retriggerCut
    case sameChannelReplacementRamp
}

struct PlaybackSongWindowScheduledEvent: Equatable {
    let eventIndex: Int
    let source: PlaybackPosition?
    let channelIndex: Int?
    let scheduledFrame: Int
}

struct PlaybackSongWindowContinuationCandidate: Equatable {
    let eventIndex: Int
    let source: PlaybackPosition?
    let channelIndex: Int?
    let scheduledFrame: Int
}

struct PlaybackSongWindowSchedulingUpdateCandidate: Equatable {
    let kind: PlaybackSongWindowSchedulingUpdateKind
    let sourceDiagnosticIndex: Int
    let childUpdateIndex: Int?
    let activeEventIndex: Int
    let scheduledFrame: Int
}

struct PlaybackSongWindowContinuation: Equatable {
    let eventIndex: Int
    let event: SyntheticTrackerEvent
    // Current step is independent of the original positive-step trigger.
    let playbackStep: Double
    let runtimeState: CSoftwareMixerVoiceRuntimeState
    let keyOffFrame: Int?
    let carriedTonePortamentoActive: Bool
    var fadeoutDecrement: Float? = nil
    var envelopeSemanticState: MixerEnvelopeSemanticState? = nil
    var audibleOutputState: MixerAudibleOutputState? = nil
}

struct PlaybackSongWindowBucket: Equatable {
    let windowIndex: Int
    let startRow: Int
    let endRowExclusive: Int
    let startFrame: Int
    let endFrame: Int
    let scheduledEvents: [PlaybackSongWindowScheduledEvent]
    let continuationCandidates: [PlaybackSongWindowContinuationCandidate]
    let continuations: [PlaybackSongWindowContinuation]
    let schedulingUpdateCandidates: [PlaybackSongWindowSchedulingUpdateCandidate]
}

struct PlaybackSongWindowedRenderIndexDiagnostics: Equatable {
    // Scan estimates cover top-level source passes; nested continuation-history lookups are excluded.
    // Continuation state still uses its proven per-window history scan and is counted separately.
    let buildDurationSeconds: Double
    let indexedWindowCount: Int
    let indexedEventCount: Int
    let indexedContinuationCandidateCount: Int
    let indexedUpdateCandidateCount: Int
    let currentWindowEventAndUpdateFullArrayScanCount: Int
    let currentContinuationTopLevelFullArrayScanCount: Int
    let currentTopLevelFullArrayScanCount: Int
    let indexedEventAndUpdateSourceArrayScanCount: Int
    let estimatedAvoidedEventAndUpdateFullArrayScanCount: Int
    let eventCountsByWindow: [Int]
    let continuationCandidateCountsByWindow: [Int]
    let updateCandidateCountsByWindow: [Int]
}

/// Internal offline index for the existing pre-acceptance window scheduler inputs.
struct PlaybackSongWindowedRenderIndex: Equatable {
    let windowRows: Int
    let windows: [PlaybackSongWindowBucket]
    let diagnostics: PlaybackSongWindowedRenderIndexDiagnostics
}

struct PlaybackSongSameChannelReplacementEvent: Equatable {
    let sourceChannelIndex: Int
    let oldEventIndex: Int
    let newEventIndex: Int
    let replacementFrame: Int
    let completionFrame: Int
    let oldVoiceKeptReason: String
    let oldVoiceRampDurationFrames: Int

    func rampState(
        startGain: Float,
        at boundaryFrame: Int
    ) -> CSoftwareMixerValueRampRuntimeState? {
        guard boundaryFrame > replacementFrame,
              boundaryFrame < completionFrame else {
            return nil
        }
        return CSoftwareMixerValueRampRuntimeState(
            start: startGain,
            target: 0,
            totalFrames: oldVoiceRampDurationFrames,
            positionFrame: boundaryFrame - replacementFrame,
            deactivateAfterRamp: true,
            songRetirement: true
        )
    }
}

struct PlaybackSongSameChannelVoiceLifetimeDiagnostics: Equatable {
    static let oldVoiceKeptReasonReplacementRamp = "replacement_ramp_overlap"

    let replacementRampFrameCount: Int
    let activeVoicesBySourceChannel: [Int: Int]
    let loadedVoicesBySourceChannel: [Int: Int]
    let sameChannelActiveVoiceCount: Int
    let sameChannelReplacementStartCount: Int
    let sameChannelReplacementCompletionCount: Int
    let sameChannelVoiceOverlapFrames: Int
    let maxVoicesPerSourceChannel: [Int: Int]
    let oldVoiceKeptReasonCounts: [String: Int]
    let oldVoiceRampDurationFrames: Int
    let windowBoundaryPruneCount: Int
    let replacementEvents: [PlaybackSongSameChannelReplacementEvent]
    let replacementEventsByOldEventIndex: [Int: [PlaybackSongSameChannelReplacementEvent]]

    func rampEvent(
        forOldEventIndex eventIndex: Int,
        at boundaryFrame: Int
    ) -> PlaybackSongSameChannelReplacementEvent? {
        replacementEventsByOldEventIndex[eventIndex]?.last { event in
            event.oldEventIndex == eventIndex &&
                event.replacementFrame <= boundaryFrame &&
                boundaryFrame < event.completionFrame
        }
    }

    func firstReplacementFrame(forOldEventIndex eventIndex: Int) -> Int? {
        // Construction appends each generation's replacements in chronological order.
        replacementEventsByOldEventIndex[eventIndex]?.first?.replacementFrame
    }

    /// Runtime retirement removes queued writes before the replacement frame is mixed.
    func permitsPitchUpdate(eventIndex: Int, at frame: Int) -> Bool {
        firstReplacementFrame(forOldEventIndex: eventIndex).map { frame < $0 } ?? true
    }
}

struct PlaybackSongOfflineRenderResult: Equatable {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let block: MixerRenderBlock
    let scheduledVoiceIndices: [Int?]
    let scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]
    let scheduledVoiceAttempts: [PlaybackSongScheduledVoiceAttempt]
    let windowedRenderSummary: PlaybackSongWindowedRenderSummary?
    let sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics
    let exportDiagnostics: MixerWAVExportDiagnostics?
    let controlAdmission: OfflineControlAdmissionSnapshot

    init(
        request: PlaybackSongOfflineRenderRequest,
        plan: PlaybackSongSyntheticPlan,
        block: MixerRenderBlock,
        scheduledVoiceIndices: [Int?],
        scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?] = [],
        scheduledVoiceAttempts: [PlaybackSongScheduledVoiceAttempt]? = nil,
        windowedRenderSummary: PlaybackSongWindowedRenderSummary? = nil,
        sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        exportDiagnostics: MixerWAVExportDiagnostics? = nil,
        controlAdmission: OfflineControlAdmissionSnapshot = .init()
    ) {
        self.controlAdmission = controlAdmission
        self.request = request
        self.plan = plan
        self.block = block
        self.scheduledVoiceIndices = scheduledVoiceIndices
        let normalizedRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]
        if scheduledVoiceRejectionReasons.count == scheduledVoiceIndices.count {
            normalizedRejectionReasons = scheduledVoiceRejectionReasons
        } else {
            normalizedRejectionReasons = scheduledVoiceIndices.map { $0 == nil ? .invalidScheduledVoice : nil }
        }
        self.scheduledVoiceRejectionReasons = normalizedRejectionReasons
        self.scheduledVoiceAttempts = scheduledVoiceAttempts ?? scheduledVoiceIndices.enumerated().map { eventIndex, voiceIndex in
            PlaybackSongScheduledVoiceAttempt(
                eventIndex: eventIndex,
                voiceIndex: voiceIndex,
                rejectionReason: normalizedRejectionReasons.indices.contains(eventIndex) ? normalizedRejectionReasons[eventIndex] : nil,
                windowIndex: nil
            )
        }
        self.windowedRenderSummary = windowedRenderSummary
        self.sameChannelVoiceLifetime = sameChannelVoiceLifetime ?? PlaybackSongOfflineRenderer.sameChannelVoiceLifetimeDiagnostics(
            for: plan,
            renderedFrameCount: block.frameCount
        )
        self.exportDiagnostics = exportDiagnostics
    }

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    var performanceDiagnostics: PlaybackSongRenderPerformanceDiagnostics? {
        windowedRenderSummary?.performanceDiagnostics
    }

    var requestedFrameCount: Int {
        request.requestedFrameCount
    }

    var renderedFrameCount: Int {
        block.frameCount
    }

    var maximumFrameCount: Int {
        request.maximumFrameCount
    }

    var wasFrameCountBounded: Bool {
        request.wasFrameCountBounded
    }

    func replacingExportDiagnostics(
        _ diagnostics: MixerWAVExportDiagnostics?
    ) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderResult(
            request: request,
            plan: plan,
            block: block,
            scheduledVoiceIndices: scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: scheduledVoiceRejectionReasons,
            scheduledVoiceAttempts: scheduledVoiceAttempts,
            windowedRenderSummary: windowedRenderSummary,
            sameChannelVoiceLifetime: sameChannelVoiceLifetime,
            exportDiagnostics: diagnostics,
            controlAdmission: controlAdmission
        )
    }
}

struct PlaybackSongOfflineStreamingRenderResult: Equatable {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let renderedFrameCount: Int
    let scheduledVoiceIndices: [Int?]
    let scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]
    let windowedRenderSummary: PlaybackSongWindowedRenderSummary?
    let sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics
    let exportDiagnostics: MixerWAVExportDiagnostics?
    let wavExportPerformanceDiagnostics: WAVExportPerformanceDiagnostics?
    var controlAdmission: OfflineControlAdmissionSnapshot = .init()

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    var performanceDiagnostics: PlaybackSongRenderPerformanceDiagnostics? {
        windowedRenderSummary?.performanceDiagnostics
    }

    var requestedFrameCount: Int {
        request.requestedFrameCount
    }

    var maximumFrameCount: Int {
        request.maximumFrameCount
    }

    var wasFrameCountBounded: Bool {
        request.wasFrameCountBounded
    }

    func replacingExportDiagnostics(
        _ diagnostics: MixerWAVExportDiagnostics?
    ) -> PlaybackSongOfflineStreamingRenderResult {
        PlaybackSongOfflineStreamingRenderResult(
            request: request,
            plan: plan,
            renderedFrameCount: renderedFrameCount,
            scheduledVoiceIndices: scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: scheduledVoiceRejectionReasons,
            windowedRenderSummary: windowedRenderSummary,
            sameChannelVoiceLifetime: sameChannelVoiceLifetime,
            exportDiagnostics: diagnostics,
            wavExportPerformanceDiagnostics: wavExportPerformanceDiagnostics,
            controlAdmission: controlAdmission
        )
    }

    func replacingWAVExportPerformanceDiagnostics(
        _ diagnostics: WAVExportPerformanceDiagnostics?
    ) -> PlaybackSongOfflineStreamingRenderResult {
        PlaybackSongOfflineStreamingRenderResult(
            request: request,
            plan: plan,
            renderedFrameCount: renderedFrameCount,
            scheduledVoiceIndices: scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: scheduledVoiceRejectionReasons,
            windowedRenderSummary: windowedRenderSummary,
            sameChannelVoiceLifetime: sameChannelVoiceLifetime,
            exportDiagnostics: exportDiagnostics,
            wavExportPerformanceDiagnostics: diagnostics,
            controlAdmission: controlAdmission
        )
    }
}

private struct PlaybackSongWindowedRenderCoreResult {
    var controlAdmission: OfflineControlAdmissionSnapshot = .init()
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let outputConfig: MixerRenderConfig
    let renderedFrameCount: Int
    let scheduledVoiceAttempts: [PlaybackSongScheduledVoiceAttempt]
    let windowedRenderSummary: PlaybackSongWindowedRenderSummary
    let sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics
}

private enum PlaybackSongWindowedSchedulingSource {
    case preindexed
    case scanPerWindowReference
}

/// A failed offline control admission is distinct from source-voice capacity.
struct OfflineControlFailure: Error, Equatable, LocalizedError {
    enum Reason: String { case invalidControl, stateQueueCapacity, singleFrameCapacity, controlStagingBudgetExceeded, sourceVoiceCapacity }
    let reason: Reason
    let key: OfflineControlKey?
    let voice: Int?
    let frameOrigin: Int
    var errorDescription: String? { "Offline control admission failed: \(reason.rawValue)" }
}

/// Submission accounting; pending controls remain valid beyond a bounded request's end.
struct OfflineControlAdmissionSnapshot: Equatable {
    var sources: OfflineSourceAdmissionSnapshot? = nil
    var intended = 0, accepted = 0, cancelled = 0, rejected = 0
    var usedSlowPath = false
    var stagedKeyCount = 0, allocatedBytes = 0, peakQueuedCount = 0
    var failure: OfflineControlFailure?
    var retryTrigger: OfflineControlFailure?
    var retryRejectedCount = 0
    mutating func merge(_ other: Self) {
        intended += other.intended; accepted += other.accepted; cancelled += other.cancelled; rejected += other.rejected
        peakQueuedCount = max(peakQueuedCount, other.peakQueuedCount)
        if failure == nil { failure = other.failure }
    }
    var pending: Int { max(0, intended - accepted - cancelled - rejected) }
    var sortScratchBytes: Int { 0 }
    func requireSuccess() throws { if let failure { throw failure } }
}

/// Logical births and physical continuation imports are accounted for separately.
struct OfflineSourceAdmissionSnapshot: Equatable {
    struct Window: Equatable {
        let startFrame: Int
        let endFrame: Int
        let continuations: Int
        let births: Int
    }
    var intended = 0, imported = 0, started = 0, cancelled = 0, rejected = 0
    var capacityRejected = 0, invalidRejected = 0
    var peakLoaded = 0, continuationImports = 0, continuationPayloadBytes = 0
    var releasedContinuations = 0, pitchContinuations = 0
    var windows: [Window] = []
    var deferred: Int { max(0, intended - imported - rejected) }
}

/// POD selectors reference existing immutable diagnostics, never PCM or copied events.
struct OfflineControlKey: Equatable {
    let frame: Int64
    let ordinal: UInt64
    let source: UInt32
    let parent: UInt32
    let child: UInt32
    let family: UInt8
    var sourceStopApplied = false // Uses existing POD padding; selector coordinates stay unchanged.
}

/// Transient call arguments, shared by eager emission and selector replay.
enum OfflineControlValue: Equatable {
    case state(MixerPlaybackStateChange), gainPan(Float?, Float?), step(Double), position(Int)
    case cut, retirement, combined(Float?, Float?, Double), rampDown(Int)
    case semantic(MixerEnvelopeSemanticState), audible(PlaybackXMAudibleUpdate), stop
    func apply(on mixer: CSoftwareMixer, voice: Int, frame: Int) -> CSoftwareMixerVoiceStateUpdateResult {
        switch self {
        case let .state(change): return mixer.schedulePlaybackStateChange(change, voiceIndex: voice, scheduledFrame: frame)
        case let .gainPan(gain, pan): return mixer.scheduleVoiceGainPanUpdate(voiceIndex: voice, scheduledFrame: frame, gain: gain, pan: pan)
        case let .step(step): return mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: frame, playbackStep: step)
        case let .position(position): return mixer.scheduleVoiceVolumeEnvelopePositionUpdate(voiceIndex: voice, scheduledFrame: frame, positionFrame: position)
        case .cut: return mixer.scheduleVoiceGainPanImmediateUpdate(voiceIndex: voice, scheduledFrame: frame, gain: 0)
        case .retirement: return mixer.scheduleSongVoiceRetirement(voiceIndex: voice, scheduledFrame: frame)
        case let .combined(gain, pan, step): return mixer.scheduleVoiceGainPanStepUpdate(voiceIndex: voice, scheduledFrame: frame, gain: gain, pan: pan, playbackStep: step)
        case let .rampDown(frames): return mixer.scheduleVoiceRampDownAndDeactivate(voiceIndex: voice, scheduledFrame: frame, rampFrames: frames)
        case let .semantic(state): return .init(wasAccepted: mixer.setEnvelopeSemanticState(state, forVoiceAt: voice), rejectionReason: nil)
        case let .audible(target): return .init(wasAccepted: mixer.publishAudibleOutput(target, forVoiceAt: voice), rejectionReason: nil)
        case .stop: return .init(wasAccepted: mixer.stopVoice(at: voice), rejectionReason: nil)
        }
    }
}

/// Bounded offline-only admission. Generic C callers and runtime delivery retain ownership.
final class OfflineControlAdmission {
    static let byteLimit = 8 * 1024 * 1024
    static let queueLimit = 4096
    private(set) var snapshot = OfflineControlAdmissionSnapshot()
    private var storage: UnsafeMutablePointer<OfflineControlKey>?
    private var capacity = 0, initialized = 0, cursor = 0
    private var capturing = false, rehydrating = false
    private var replayCount = 0
    let capturesSourceSchedules: Bool
    private let countingOnly: Bool
    private(set) var hadInvalidControl = false
    private let frameOrigin: Int
    var stopsBySource: [Int: Int] = [:] // Populated only on the slow path from existing stop authority.
#if DEBUG
    struct LedgerEntry: Equatable { let key: OfflineControlKey; let voice: Int; let value: OfflineControlValue; let accepted: Bool }
    var ledger: [LedgerEntry]?
#endif
    init(stagingCount: Int? = nil, frameOrigin: Int = 0, capturesSourceSchedules: Bool = false, countingOnly: Bool = false) {
        self.frameOrigin = frameOrigin
        self.capturesSourceSchedules = capturesSourceSchedules
        self.countingOnly = countingOnly
        if countingOnly { snapshot.usedSlowPath = true; return }
        guard let count = stagingCount else { return }
        snapshot.usedSlowPath = true
        snapshot.stagedKeyCount = count
        let (bytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<OfflineControlKey>.stride)
        guard count >= 0, !overflow, bytes <= Self.byteLimit,
              malloc_good_size(bytes) <= Self.byteLimit else { fail(.controlStagingBudgetExceeded); return }
        if count > 0 {
            guard let raw = malloc(bytes) else { fail(.controlStagingBudgetExceeded); return }
            let actual = malloc_size(raw)
            guard actual >= bytes, actual <= Self.byteLimit else { free(raw); fail(.controlStagingBudgetExceeded); return }
            storage = raw.bindMemory(to: OfflineControlKey.self, capacity: count)
            snapshot.allocatedBytes = actual
        }
        capacity = count
        capturing = true
    }
    deinit { storage?.deinitialize(count: initialized); free(storage) }
    private func fail(_ reason: OfflineControlFailure.Reason, key: OfflineControlKey? = nil, voice: Int? = nil) {
        if reason == .controlStagingBudgetExceeded && snapshot.intended == 0 { snapshot.intended = max(0, snapshot.stagedKeyCount) }
        if snapshot.failure == nil || reason == .invalidControl { snapshot.failure = .init(reason: reason, key: key, voice: voice, frameOrigin: frameOrigin) }
    }
    func rejectInvalid() { hadInvalidControl = true; fail(.invalidControl) }
    func recordRetry(_ attempt: OfflineControlAdmissionSnapshot) {
        snapshot.retryTrigger = attempt.failure
        snapshot.retryRejectedCount = attempt.rejected
    }
    func submit(family: Int, parent: Int, child: Int = 0, source: Int, voice: Int, frame: Int,
                on mixer: CSoftwareMixer, value: @autoclosure () -> OfflineControlValue) {
        if rehydrating { replayCount += 1; return }
        let ordinal = snapshot.intended
        guard ordinal < Int.max, let f = UInt8(exactly: family), let s = UInt32(exactly: source),
              let p = UInt32(exactly: parent), let c = UInt32(exactly: child), frame >= 0 else {
            hadInvalidControl = true; fail(.invalidControl); return
        }
        let key = OfflineControlKey(frame: Int64(frame), ordinal: UInt64(ordinal), source: s, parent: p, child: c, family: f)
        snapshot.intended += 1
        if countingOnly { return }
        if capturing {
            guard initialized < capacity else { fail(.controlStagingBudgetExceeded, key: key); return }
            storage!.advanced(by: initialized).initialize(to: key); initialized += 1
        } else { apply(key, voice: voice, value: value(), on: mixer) }
    }
    private func apply(_ key: OfflineControlKey, voice: Int, value: OfflineControlValue, on mixer: CSoftwareMixer, frame: Int? = nil) {
        let result = value.apply(on: mixer, voice: voice, frame: frame ?? Int(key.frame))
        if result.wasAccepted { snapshot.accepted += 1 }
        else {
            snapshot.rejected += 1
            let invalid = result.rejectionReason != .voiceStateEventCapacity
            hadInvalidControl = hadInvalidControl || invalid
            fail(invalid ? .invalidControl : .stateQueueCapacity, key: key, voice: voice)
        }
#if DEBUG
        if ledger != nil { ledger!.append(.init(key: key, voice: voice, value: value, accepted: result.wasAccepted)) }
#endif
        if !snapshot.usedSlowPath { snapshot.peakQueuedCount = snapshot.accepted }
    }
    func finishCapture() {
        capturing = false
        guard snapshot.failure == nil else { return }
        guard initialized == capacity else { fail(.invalidControl); return }
        // Unique ordinals make an in-place heap sort sufficient: no auxiliary key allocation.
        func less(_ a: OfflineControlKey, _ b: OfflineControlKey) -> Bool {
            if capturesSourceSchedules && a.frame == b.frame {
                // Match CSoftwareMixer.render: stop, envelope, audible target, then native commands.
                func priority(_ family: UInt8) -> Int { family == 16 ? 0 : family == 14 ? 1 : family == 15 ? 2 : 3 }
                if priority(a.family) != priority(b.family) { return priority(a.family) < priority(b.family) }
            }
            return a.frame == b.frame ? a.ordinal < b.ordinal : a.frame < b.frame
        }
        func sift(_ start: Int, _ end: Int) {
            var parent = start
            while parent < end / 2 {
                var child = parent * 2 + 1
                if child + 1 < end && less(storage![child], storage![child + 1]) { child += 1 }
                guard less(storage![parent], storage![child]) else { return }
                let value = storage![parent]; storage![parent] = storage![child]; storage![child] = value; parent = child
            }
        }
        if initialized > 1 {
            for i in stride(from: initialized / 2 - 1, through: 0, by: -1) { sift(i, initialized) }
            for end in stride(from: initialized - 1, through: 1, by: -1) {
                let value = storage![0]; storage![0] = storage![end]; storage![end] = value; sift(0, end)
            }
        }
        var start = 0
        while start < initialized {
            var end = start + 1
            while end < initialized && storage![end].frame == storage![start].frame { end += 1 }
            let nativeCount = capturesSourceSchedules ? (start..<end).reduce(0) { $0 + (storage![$1].family < 14 ? 1 : 0) } : end - start
            if nativeCount > Self.queueLimit { fail(.singleFrameCapacity, key: storage![start]); return }
            start = end
        }
    }
    var nextFrame: Int { cursor < initialized ? Int(storage![cursor].frame) : Int.max }
    /// Frees current owners before checkpoint occupancy; unadmitted owners stay pending for this frame.
    func applySourceStopsBeforeCheckpoint(_ frame: Int, on mixer: CSoftwareMixer, voices: [Int: Int],
                                         isRetired: (Int) -> Bool) {
        var index = cursor
        while index < initialized, storage![index].frame == frame, storage![index].family == 16, snapshot.failure == nil {
            let key = storage![index]; index += 1
            guard !key.sourceStopApplied, !isRetired(Int(key.source)), let voice = voices[Int(key.source)],
                  mixer.voiceDiagnostic(forVoiceAt: voice)?.active == true else { continue }
            // Only the wrapper's immediate physical stop precedes envelope/audible/native commands.
            apply(key, voice: voice, value: .stop, on: mixer)
            storage![index - 1].sourceStopApplied = true
        }
    }
    /// Admits only this causal frame; future source owners retain their immutable selectors.
    func deliverSourceFrame(_ frame: Int, origin: Int, on mixer: CSoftwareMixer, voices: [Int: Int],
                            isRetired: (Int) -> Bool,
                            resolve: (OfflineControlKey) -> OfflineControlValue,
                            accepted: (OfflineControlKey, OfflineControlValue) -> Void) {
        var queued = 0
        while cursor < initialized, storage![cursor].frame == frame, snapshot.failure == nil {
            let key = storage![cursor]; cursor += 1
            if key.sourceStopApplied { continue }
            guard !isRetired(Int(key.source)), let voice = voices[Int(key.source)], let state = mixer.voiceDiagnostic(forVoiceAt: voice),
                  state.active, key.family == 16 || !state.deactivateAfterGainRamp else {
                snapshot.cancelled += 1; continue
            }
            let value = resolve(key)
            apply(key, voice: voice, value: value, on: mixer, frame: frame - origin)
            if snapshot.failure == nil { accepted(key, value) }
            if key.family < 14 { queued += 1 }
        }
        snapshot.peakQueuedCount = max(snapshot.peakQueuedCount, queued)
    }
    /// Reuses captured keys when a checkpoint session is reset, without a second producer scan.
    func rewindSourceFrames() {
        for index in 0..<initialized { storage![index].sourceStopApplied = false }
        beginReplay(); rehydrating = false
    }
    func rejectSourceCapacity(at frame: Int) {
        snapshot.failure = .init(reason: .sourceVoiceCapacity, key: nil, voice: nil, frameOrigin: frame)
    }
    func refill(on mixer: CSoftwareMixer, voices: [Int: Int], resolve: (OfflineControlKey) -> OfflineControlValue) {
        guard snapshot.failure == nil else { return }
        var batch = 0
        while cursor < initialized {
            var end = cursor + 1
            while end < initialized && storage![end].frame == storage![cursor].frame { end += 1 }
            guard batch + end - cursor <= Self.queueLimit else { break }
            for i in cursor..<end {
                let key = storage![i], source = Int(key.source)
                if let stop = stopsBySource[source], stop < Int(mixer.currentFrame), Int(key.frame) >= stop {
                    snapshot.cancelled += 1; continue
                }
                guard let voice = voices[source] else { fail(.invalidControl, key: key); return }
                apply(key, voice: voice, value: resolve(key), on: mixer)
                if snapshot.failure != nil { return }
                batch += 1
            }
            cursor = end
        }
        snapshot.peakQueuedCount = max(snapshot.peakQueuedCount, batch)
    }
    func beginReplay() {
        let bytes = snapshot.allocatedBytes, count = snapshot.stagedKeyCount
        let trigger = snapshot.retryTrigger, rejected = snapshot.retryRejectedCount
        snapshot = .init(); snapshot.usedSlowPath = true; snapshot.allocatedBytes = bytes; snapshot.stagedKeyCount = count
        snapshot.retryTrigger = trigger; snapshot.retryRejectedCount = rejected
        snapshot.intended = initialized; cursor = 0; replayCount = 0; rehydrating = true
#if DEBUG
        ledger?.removeAll(keepingCapacity: true)
#endif
    }
    func endReplay() { rehydrating = false; if replayCount != initialized { fail(.invalidControl) } }
}

/// Compact forward source references; native slots and per-generation state never outlive a horizon.
private final class OfflineSourceCursor {
    struct Key { let frame: Int; let source: Int }
    let keys: [Key]
    var nextImport = 0, nextBirth = 0, origin = 0, end = 0
    var voices: [Int: Int] = [:]
    var fadeoutRates: [Int: Float] = [:]
    var cutFrames: [Int: Int] = [:]
    var pitchSources: Set<Int> = []
    var snapshot = OfflineSourceAdmissionSnapshot()
#if DEBUG
    var boundaries: [Int] = []
    var births: [(source: Int, frame: Int, cursor: Double)]? = nil
#endif
    init(plan: PlaybackSongSyntheticPlan) {
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        keys = plan.pattern.events.enumerated().compactMap { i, event in
            plan.pattern.contains(row: event.row) ? Key(frame: scheduler.frame(for: event), source: i) : nil
        }.sorted { $0.frame == $1.frame ? $0.source < $1.source : $0.frame < $1.frame }
        snapshot.intended = keys.count
    }
    func rewind() {
        nextImport = 0; nextBirth = 0; origin = 0; end = 0
        voices.removeAll(keepingCapacity: true); fadeoutRates.removeAll(keepingCapacity: true); cutFrames.removeAll(keepingCapacity: true)
        pitchSources.removeAll(keepingCapacity: true)
        snapshot = .init(); snapshot.intended = keys.count
#if DEBUG
        if births != nil { births = [] }
#endif
    }
}

/// Prepared offline render session for split renders and reset determinism checks.
final class PlaybackSongOfflineRenderSession {
    let request: PlaybackSongOfflineRenderRequest
    private(set) var plan: PlaybackSongSyntheticPlan
    private(set) var scheduledVoiceIndices: [Int?] = []
    private(set) var scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?] = []
    let sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics
    private let includedEventIndices: Set<Int>?
    private var mixer: CSoftwareMixer?
    private var controls = OfflineControlAdmission()
    private var slowVoices: [Int: Int] = [:]
    private var renderedFrameCount = 0
    private var sources: OfflineSourceCursor?
    private var recordsSourcePerformance = false
    fileprivate private(set) var sourceSchedulingSeconds = 0.0, sourceRenderSeconds = 0.0
    fileprivate func takeSourcePayloadDiagnostics() -> CSoftwareMixerSamplePayloadUploadDiagnostics {
        mixer!.takeSamplePayloadUploadDiagnostics()
    }
    var config: MixerRenderConfig { mixer?.config ?? request.config }
    var diagnostics: PlaybackSongSyntheticDiagnostics { plan.diagnostics }
    var controlAdmission: OfflineControlAdmissionSnapshot {
        var result = controls.snapshot; result.sources = sources?.snapshot; return result
    }

    init(request: PlaybackSongOfflineRenderRequest, preparedPlan: PlaybackSongSyntheticPlan? = nil,
         samplePayloadUploadMode: CSoftwareMixerSamplePayloadUploadMode = .defensiveSanitizingCopy,
         sharedSamplePayloadCache: CSoftwareMixerSharedSamplePayloadCache? = nil,
         recordsSamplePayloadUploads: Bool = false) {
        self.request = request
        recordsSourcePerformance = recordsSamplePayloadUploads
        let fullPlan = preparedPlan ?? PlaybackSongSyntheticAdapter.adapt(request.song,
            startOrderIndex: request.startOrderIndex, orderCount: request.orderCount, sampleRate: request.config.sampleRate)
        includedEventIndices = PlaybackSongOfflineRenderer.includedEventIndices(for: fullPlan, isolationFilter: request.isolationFilter)
        plan = PlaybackSongOfflineRenderer.plan(fullPlan, mutingEventsNotIn: includedEventIndices)
            .extendingEnvelopeTail(throughFrame: request.boundedFrameCount)
        sameChannelVoiceLifetime = PlaybackSongOfflineRenderer.sameChannelVoiceLifetimeDiagnostics(for: plan, renderedFrameCount: request.boundedFrameCount)
        if plan.pattern.events.count > CSoftwareMixer.maximumVoiceCount {
            mixer = CSoftwareMixer(config: request.config, samplePayloadUploadMode: samplePayloadUploadMode,
                sharedSamplePayloadCache: sharedSamplePayloadCache, recordsSamplePayloadUploads: recordsSamplePayloadUploads)
            prepareSourceCheckpoints()
            return
        }
        installVoices()
        let rejected = scheduledVoiceRejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count
        plan = plan.replacingEventCoverage(plan.diagnostics.eventCoverage.reportingCMixerVoiceCapacityRejections(rejected))
        emitControls()
        if controls.snapshot.failure?.reason == .stateQueueCapacity && !controls.hadInvalidControl { prepareStaged() }
    }
    private func installVoices() {
        let installed = CSoftwareMixer(config: request.config)
        let results = SyntheticPatternScheduler(config: plan.timingConfig).scheduleWithResults(plan.pattern, on: installed)
        scheduledVoiceIndices = results.map(\.voiceIndex)
        scheduledVoiceRejectionReasons = results.map(\.rejectionReason)
        mixer = installed
    }
    private func emitControls() {
        guard let mixer else { return }
        let voiceIndices = scheduledVoiceIndices
        PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(
            plan, voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer, includedEventIndices: includedEventIndices, admission: controls)
        PlaybackSongOfflineRenderer.scheduleEnvelopePositionUpdates(
            plan.diagnostics.envelopePositionEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices, admission: controls)
        PlaybackSongOfflineRenderer.scheduleVoiceStateUpdates(
            plan.diagnostics.voiceStateUpdates,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices, admission: controls)
        PlaybackSongOfflineRenderer.scheduleTonePortamentoStepUpdates(
            plan.diagnostics.tonePortamentoEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.schedulePortamentoSlideStepUpdates(
            plan.diagnostics.portamentoSlideEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleFinePortamentoUpStepUpdates(
            plan.diagnostics.finePortamentoUpEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleFinePortamentoDownStepUpdates(
            plan.diagnostics.finePortamentoDownEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleExtraFinePortamentoStepUpdates(
            plan.diagnostics.extraFinePortamentoEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleArpeggioStepUpdates(
            plan.diagnostics.arpeggioEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleVibratoStepUpdates(
            plan.diagnostics.vibratoEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleInstrumentAutoPitchUpdates(plan.instrumentAutovibratoRequests,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices), on: mixer,
            includedEventIndices: includedEventIndices, sameChannelLifetime: sameChannelVoiceLifetime, admission: controls)
        PlaybackSongOfflineRenderer.scheduleRetriggerCuts(
            plan.diagnostics.retriggerEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices, admission: controls)
        PlaybackSongOfflineRenderer.scheduleSameChannelReplacementRamps(
            sameChannelVoiceLifetime.replacementEvents,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: mixer,
            includedEventIndices: includedEventIndices, admission: controls)
    }
    private func prepareStaged() {
        let attempt = controls.snapshot, count = attempt.intended
        let previousVoices = scheduledVoiceIndices, previousRejections = scheduledVoiceRejectionReasons
#if DEBUG
        let recordsLedger = controls.ledger != nil
#endif
        mixer = nil // Release the rejected epoch and uploaded PCM before rebuilding.
        controls = OfflineControlAdmission(stagingCount: count)
        controls.recordRetry(attempt)
#if DEBUG
        if recordsLedger { controls.ledger = [] }
#endif
        guard controls.snapshot.failure == nil else { return }
        installVoices()
        guard scheduledVoiceIndices == previousVoices, scheduledVoiceRejectionReasons == previousRejections else {
            controls.rejectInvalid(); return
        }
        emitControls() // Same selectors/eligibility; capture mode never calls C.
        controls.finishCapture()
        slowVoices = Self.voiceIndexByEventIndex(from: scheduledVoiceIndices)
        if let mixer { controls.refill(on: mixer, voices: slowVoices, resolve: resolve) }
    }
    private func resolve(_ key: OfflineControlKey) -> OfflineControlValue {
        let p = Int(key.parent), c = Int(key.child), d = plan.diagnostics
        switch key.family {
        case 0: return .step(0)
        case 1: return .state(plan.playbackStateEvents[p].change)
        case 2: return .position(d.envelopePositionEffects[p].appliedPositionFrame!)
        case 3:
            let u = d.voiceStateUpdates[p]
            return .gainPan(u.physicalGainChange, PlaybackSongOfflineRenderer.changedPan(from: u))
        case 4: return .step(d.tonePortamentoEffects[p].stepUpdates[c].playbackStepAfter)
        case 5: return .step(d.portamentoSlideEffects[p].stepUpdates[c].playbackStepAfter)
        case 6: return .step(d.finePortamentoUpEffects[p].stepUpdates[c].playbackStepAfter)
        case 7: return .step(d.finePortamentoDownEffects[p].stepUpdates[c].playbackStepAfter)
        case 8: return .step(d.extraFinePortamentoEffects[p].stepUpdates[c].playbackStepAfter)
        case 9: return .step(d.arpeggioEffects[p].stepUpdates[c].playbackStepAfter)
        case 10: return .step(d.vibratoEffects[p].stepUpdates[c].playbackStepAfter)
        case 11: return .step(plan.instrumentAutovibratoRequests[p].playbackStep)
        case 12: return .cut
        case 13: return .retirement
        case 14: return .semantic(plan.xmEnvelopeTimeline!.updates[p].state)
        case 15: return .audible(plan.xmAudibleTimeline!.updates[p])
        case 16: return .stop
        default: preconditionFailure("Unknown offline selector")
        }
    }
    func render(frames: Int) -> MixerRenderBlock {
        let count = min(max(0, frames), max(0, request.boundedFrameCount - renderedFrameCount))
        guard controlAdmission.failure == nil, let mixer else {
            return .init(config: config, frameCount: 0, interleavedPCM: [])
        }
        if let sources { return renderSourceFrames(count, sources: sources, mixer: mixer) }
        guard controls.snapshot.usedSlowPath, count > 0 else {
            let block = mixer.render(frames: count); renderedFrameCount += block.frameCount; return block
        }
        var pcm = Array(repeating: Float(0), count: count * config.channelCount)
        let start = renderedFrameCount, end = start + count
        pcm.withUnsafeMutableBufferPointer { buffer in
            while renderedFrameCount < end {
                if controls.nextFrame <= renderedFrameCount { controls.refill(on: mixer, voices: slowVoices, resolve: resolve) }
                guard controlAdmission.failure == nil else { break }
                let stop = min(end, controls.nextFrame)
                let frames = stop - renderedFrameCount
                precondition(frames > 0)
                let output = UnsafeMutableBufferPointer(start: buffer.baseAddress!.advanced(by: (renderedFrameCount - start) * config.channelCount), count: frames * config.channelCount)
                renderedFrameCount += mixer.render(into: output, frames: frames)
            }
        }
        let rendered = renderedFrameCount - start
        if rendered < count { pcm.removeLast((count - rendered) * config.channelCount) }
        return .init(config: config, frameCount: rendered, interleavedPCM: pcm)
    }
    func reset() {
        guard controlAdmission.failure == nil else { return }
        renderedFrameCount = 0
        if let sources {
            scheduledVoiceIndices = Array(repeating: nil, count: plan.pattern.events.count)
            scheduledVoiceRejectionReasons = Array(repeating: nil, count: plan.pattern.events.count)
            sources.rewind(); controls.rewindSourceFrames(); advanceSourceWindow(); return
        }
        if controls.snapshot.usedSlowPath {
            let previousVoices = scheduledVoiceIndices, previousRejections = scheduledVoiceRejectionReasons
            mixer = nil
            controls.beginReplay()
            installVoices()
            guard scheduledVoiceIndices == previousVoices, scheduledVoiceRejectionReasons == previousRejections else {
                controls.rejectInvalid(); return
            }
            emitControls() // Reinstall the separate G05/envelope/stop schedules only.
            controls.endReplay()
            if let mixer { controls.refill(on: mixer, voices: slowVoices, resolve: resolve) }
        } else { mixer?.reset() } // Preexisting eager reset-after-stop debt is deliberately unchanged.
    }
#if DEBUG
    /// Forces real checkpoint delivery for below-capacity eager/continuation parity controls.
    func configureSourceAdmissionForTesting(boundaries: [Int] = []) {
        precondition(renderedFrameCount == 0)
        prepareSourceCheckpoints()
        sources!.boundaries = boundaries.sorted()
        sources!.births = []
        controls.ledger = []
        reset()
    }
    var sourceBirthsForTesting: [(source: Int, frame: Int, cursor: Double)] { sources?.births ?? [] }
    var sourceMixerIdentityForTesting: ObjectIdentifier? { mixer.map(ObjectIdentifier.init) }
    func sourceSlotForTesting(_ event: Int) -> Int? { sources?.voices[event] }
    func sourceVoiceForTesting(_ event: Int) -> CSoftwareMixerVoiceDiagnostic? {
        let slot: Int?
        if let sources { slot = sources.voices[event] }
        else { slot = scheduledVoiceIndices.indices.contains(event) ? scheduledVoiceIndices[event] : nil }
        guard let slot else { return nil }
        return mixer?.voiceDiagnostic(forVoiceAt: slot)
    }
    func advanceSourceWindowForTesting() { precondition(sources?.end == renderedFrameCount); advanceSourceWindow() }
    /// Forces identical producer capture for ledger/parity tests; absent from Release.
    func configureAdmissionForTesting(forceSlow: Bool, recordLedger: Bool = true) {
        precondition(renderedFrameCount == 0)
        if sources != nil { if recordLedger { controls.ledger = [] }; return }
        mixer = nil; controls = OfflineControlAdmission()
        if recordLedger { controls.ledger = [] }
        installVoices(); emitControls()
        if forceSlow || controls.snapshot.failure?.reason == .stateQueueCapacity { prepareStaged() }
    }
    var controlLedgerForTesting: [OfflineControlAdmission.LedgerEntry] { controls.ledger ?? [] }
#endif
    private static func voiceIndexByEventIndex(from voiceIndices: [Int?]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: voiceIndices.enumerated().compactMap { i, voice in voice.map { (i, $0) } })
    }

    private func prepareSourceCheckpoints() {
        let started = recordsSourcePerformance ? VTXPerformanceClock.now() : 0
        // Reuse every existing producer/eligibility rule; placeholders are logical IDs, never C slots.
        scheduledVoiceIndices = plan.pattern.events.indices.map { Optional($0) }
        controls = OfflineControlAdmission(capturesSourceSchedules: true, countingOnly: true)
        emitControls()
        controls = OfflineControlAdmission(stagingCount: controls.snapshot.intended, capturesSourceSchedules: true)
        if controls.snapshot.failure == nil { emitControls(); controls.finishCapture() }
        scheduledVoiceIndices = Array(repeating: nil, count: plan.pattern.events.count)
        scheduledVoiceRejectionReasons = Array(repeating: nil, count: plan.pattern.events.count)
        sources = OfflineSourceCursor(plan: plan)
        if recordsSourcePerformance { sourceSchedulingSeconds += VTXPerformanceClock.seconds(since: started) }
        advanceSourceWindow()
    }

    private func advanceSourceWindow() {
        guard let sources, let mixer, controls.snapshot.failure == nil else { return }
        let started = recordsSourcePerformance ? VTXPerformanceClock.now() : 0
        defer { if recordsSourcePerformance { sourceSchedulingSeconds += VTXPerformanceClock.seconds(since: started) } }
        let origin = renderedFrameCount
        controls.applySourceStopsBeforeCheckpoint(origin, on: mixer, voices: sources.voices,
            isRetired: { source in sources.cutFrames[source].map { $0 < origin } ?? false })
        guard controls.snapshot.failure == nil else { return }
        let saved = sources.voices.compactMap { source, slot -> (Int, CSoftwareMixerVoiceDiagnostic)? in
            // Match stem-window eligibility: excluded generations have no later audible writers.
            guard includedEventIndices?.contains(source) ?? true,
                  let state = mixer.voiceDiagnostic(forVoiceAt: slot), state.active,
                  sources.cutFrames[source].map({ $0 >= origin }) ?? true else { return nil }
            return (source, state)
        }
        let states = Dictionary(uniqueKeysWithValues: saved)
        var cursor = sources.nextImport, count = states.count, end = request.boundedFrameCount
#if DEBUG
        if let cut = sources.boundaries.first(where: { $0 > origin }) { end = min(end, cut) }
#endif
        while cursor < sources.keys.count, sources.keys[cursor].frame < end {
            let frame = sources.keys[cursor].frame
            var groupEnd = cursor + 1
            while groupEnd < sources.keys.count, sources.keys[groupEnd].frame == frame { groupEnd += 1 }
            let proposed = count + groupEnd - cursor
            if proposed > 224 && frame > origin { end = frame; break }
            if proposed > CSoftwareMixer.maximumVoiceCount {
                for key in sources.keys[cursor..<groupEnd] { scheduledVoiceRejectionReasons[key.source] = .scheduledVoiceCapacity }
                sources.snapshot.rejected += groupEnd - cursor
                sources.snapshot.capacityRejected += groupEnd - cursor
                controls.rejectSourceCapacity(at: frame)
                plan = plan.replacingEventCoverage(plan.diagnostics.eventCoverage.reportingCMixerVoiceCapacityRejections(sources.snapshot.rejected))
                return
            }
            count = proposed; cursor = groupEnd
        }
        let newKeys = sources.keys[sources.nextImport..<cursor]
        let newSources = Set(newKeys.map(\.source))
        let ordered = (Array(states.keys) + newKeys.map(\.source)).sorted()
        // Clear BEFORE reloading: there is only one native pool, and no stale Swift/C slot owner.
        mixer.clearScheduledVoices(); mixer.setSourceStopSchedule([]); mixer.reset()
        sources.voices.removeAll(keepingCapacity: true)
        sources.fadeoutRates = sources.fadeoutRates.filter { states[$0.key] != nil }
        sources.cutFrames = sources.cutFrames.filter { states[$0.key] != nil }
        sources.pitchSources.formIntersection(states.keys)
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        for source in ordered {
            let event = plan.pattern.events[source]
            let result: CSoftwareMixerScheduledVoiceResult
            if let state = states[source] {
                let continuation = PlaybackSongWindowContinuation(eventIndex: source,
                    event: event.withGainPan(gain: state.gain, pan: state.pan), playbackStep: state.sampleStep,
                    runtimeState: .init(samplePosition: state.samplePosition, pingPongDirection: state.pingPongDirection,
                        volumeEnvelopePositionFrame: state.volumeEnvelopePositionFrame, panEnvelopePositionFrame: state.panEnvelopePositionFrame,
                        keyOn: state.keyOn, fadeoutValue: state.fadeoutValue, gainRamp: state.gainRamp, panRamp: state.panRamp,
                        sourceOnsetElapsedFrames: state.sourceOnsetElapsedFrames),
                    keyOffFrame: event.keyOffFrame.flatMap { $0 >= origin ? $0 - origin : nil },
                    carriedTonePortamentoActive: sources.pitchSources.contains(source), fadeoutDecrement: sources.fadeoutRates[source] ?? event.fadeoutFrameDecrement,
                    envelopeSemanticState: state.envelopeSemanticState, audibleOutputState: state.audibleOutputState)
                result = PlaybackSongOfflineRenderer.scheduleContinuation(continuation, on: mixer)
                sources.snapshot.continuationImports += result.wasAccepted ? 1 : 0
                if result.wasAccepted {
                    sources.snapshot.continuationPayloadBytes += event.sample.frameCount * MemoryLayout<Float>.stride
                    sources.snapshot.releasedContinuations += state.keyOn ? 0 : 1
                    sources.snapshot.pitchContinuations += sources.pitchSources.contains(source) ? 1 : 0
                }
            } else {
                result = scheduler.scheduleWithResult(PlaybackSongOfflineRenderer.localEvent(from: event, windowStartFrame: origin, scheduler: scheduler), on: mixer)
                scheduledVoiceIndices[source] = result.voiceIndex; scheduledVoiceRejectionReasons[source] = result.rejectionReason
                sources.snapshot.imported += result.wasAccepted ? 1 : 0
                sources.snapshot.rejected += result.wasAccepted ? 0 : 1
                sources.snapshot.capacityRejected += result.rejectionReason == .scheduledVoiceCapacity ? 1 : 0
                sources.snapshot.invalidRejected += result.rejectionReason == .invalidScheduledVoice ? 1 : 0
                sources.fadeoutRates[source] = event.fadeoutFrameDecrement
            }
            guard let slot = result.voiceIndex else { controls.rejectInvalid(); return }
            sources.voices[source] = slot
        }
        precondition(newSources.count == newKeys.count && ordered.count <= CSoftwareMixer.maximumVoiceCount)
        sources.nextImport = cursor; sources.origin = origin; sources.end = end
        sources.snapshot.peakLoaded = max(sources.snapshot.peakLoaded, mixer.loadedVoiceCount)
        sources.snapshot.windows.append(.init(startFrame: origin, endFrame: end, continuations: states.count, births: newKeys.count))
    }

    private func renderSourceFrames(_ count: Int, sources: OfflineSourceCursor, mixer: CSoftwareMixer) -> MixerRenderBlock {
        let started = recordsSourcePerformance ? VTXPerformanceClock.now() : 0
        let oldRender = sourceRenderSeconds, oldScheduling = sourceSchedulingSeconds
        defer {
            if recordsSourcePerformance {
                sourceSchedulingSeconds = oldScheduling + VTXPerformanceClock.seconds(since: started) - (sourceRenderSeconds - oldRender)
            }
        }
        let start = renderedFrameCount, end = start + count
        var pcm = Array(repeating: Float(0), count: count * config.channelCount)
        pcm.withUnsafeMutableBufferPointer { buffer in
            while renderedFrameCount < end, controls.snapshot.failure == nil {
                if renderedFrameCount == sources.end { advanceSourceWindow() }
                guard controls.snapshot.failure == nil else { break }
                while sources.nextBirth < sources.keys.count, sources.keys[sources.nextBirth].frame == renderedFrameCount {
                    let key = sources.keys[sources.nextBirth]; sources.nextBirth += 1
                    if let slot = sources.voices[key.source], let state = mixer.voiceDiagnostic(forVoiceAt: slot), state.active {
                        sources.snapshot.started += 1
#if DEBUG
                        if sources.births != nil { sources.births!.append((key.source, key.frame, state.samplePosition)) }
#endif
                    } else { sources.snapshot.cancelled += 1 }
                }
                controls.deliverSourceFrame(renderedFrameCount, origin: sources.origin, on: mixer, voices: sources.voices,
                    isRetired: { source in sources.cutFrames[source].map { $0 < self.renderedFrameCount } ?? false }, resolve: resolve,
                    accepted: { key, value in
                        if case let .state(.keyOff(decrement)) = value { sources.fadeoutRates[Int(key.source)] = decrement }
                        if (4...11).contains(key.family) { sources.pitchSources.insert(Int(key.source)) }
                        if key.family == 12 || key.family == 16 { sources.cutFrames[Int(key.source)] = self.renderedFrameCount }
                    })
                guard controls.snapshot.failure == nil else { break }
                let birth = sources.nextBirth < sources.keys.count ? sources.keys[sources.nextBirth].frame : Int.max
                let stop = min(end, sources.end, birth, controls.nextFrame)
                precondition(stop > renderedFrameCount)
                let frames = stop - renderedFrameCount
                let output = UnsafeMutableBufferPointer(start: buffer.baseAddress!.advanced(by: (renderedFrameCount - start) * config.channelCount), count: frames * config.channelCount)
                let nativeStart = recordsSourcePerformance ? VTXPerformanceClock.now() : 0
                renderedFrameCount += mixer.render(into: output, frames: frames)
                if recordsSourcePerformance { sourceRenderSeconds += VTXPerformanceClock.seconds(since: nativeStart) }
            }
        }
        let rendered = renderedFrameCount - start
        if rendered < count { pcm.removeLast((count - rendered) * config.channelCount) }
        return .init(config: config, frameCount: rendered, interleavedPCM: pcm)
    }
}

/// Offline renderer for tiny bounded `PlaybackSong` adapter segments.
///
/// This renderer adapts a bounded playback-model order selection, schedules the resulting synthetic pattern
/// through `CSoftwareMixer`, and returns the in-memory PCM block with adapter diagnostics. It intentionally
/// does not implement full XM playback, FT2/OpenMPT resampler parity, effect-column commands beyond minimal
/// `Fxx`, full volume-column semantics, full FT2/OpenMPT envelope parity, runtime backend switching,
/// or app Play button wiring.
final class PlaybackSongOfflineRenderer {
    let maximumFrameCount: Int
    // Internal semantic-plan input must match the request range and sample rate.
    private let preparedPlan: PlaybackSongSyntheticPlan?
#if DEBUG
    private var verificationFrameBoundaries: [Int]?

    /// Exposes the same continuation reconstruction at exact retirement frames.
    func continuationsForTesting(_ plan: PlaybackSongSyntheticPlan, at frame: Int,
                                 config: MixerRenderConfig) -> [PlaybackSongWindowContinuation] {
        Self.continuations(for: .init(index: 0, startRow: 0, endRowExclusive: plan.pattern.rowCount,
            startFrame: frame, endFrame: frame + 1), plan: plan,
            scheduler: SyntheticTrackerScheduler(config: plan.timingConfig),
            sameChannelLifetime: Self.sameChannelVoiceLifetimeDiagnostics(for: plan, renderedFrameCount: frame),
            config: config)
    }

    /// Exercises the existing scan-reference continuation path at exact frame splits.
    func renderWindowedAtFrameBoundariesForTesting(_ request: PlaybackSongOfflineRenderRequest,
        boundaries: [Int], usePreindexedScheduling: Bool = false) -> PlaybackSongOfflineRenderResult {
        precondition(boundaries.allSatisfy { $0 > 0 && $0 < request.boundedFrameCount })
        precondition(zip(boundaries, boundaries.dropFirst()).allSatisfy { $0 < $1 })
        verificationFrameBoundaries = boundaries
        defer { verificationFrameBoundaries = nil }
        return renderWindowed(request, windowRows: 1, schedulingSource: usePreindexedScheduling ? .preindexed : .scanPerWindowReference,
            samplePayloadUploadMode: .preSanitizedBulkCopy, collectPerformanceDiagnostics: false, progress: nil)
    }
#endif

    init(maximumFrameCount: Int = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount, preparedPlan: PlaybackSongSyntheticPlan? = nil) {
        self.preparedPlan = preparedPlan
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    static func includedEventIndices(
        for plan: PlaybackSongSyntheticPlan,
        isolationFilter: PlaybackSongRenderIsolationFilter?
    ) -> Set<Int>? {
        guard let isolationFilter, isolationFilter.isEnabled else {
            return nil
        }
        return Set(plan.diagnostics.eventMappings.compactMap { mapping in
            isolationFilter.includes(mapping) ? mapping.eventIndex : nil
        })
    }

    static func plan(
        _ plan: PlaybackSongSyntheticPlan,
        mutingEventsNotIn includedEventIndices: Set<Int>?
    ) -> PlaybackSongSyntheticPlan {
        guard let includedEventIndices else {
            return plan
        }
        let events = plan.pattern.events.enumerated().map { eventIndex, event in
            includedEventIndices.contains(eventIndex) ? event : event.withGainPan(gain: 0)
        }
        return PlaybackSongSyntheticPlan(
            timingConfig: plan.timingConfig,
            pattern: SyntheticPattern(rowCount: plan.pattern.rowCount, events: events),
            diagnostics: plan.diagnostics,
            canonicalTickClock: plan.canonicalTickClock,
            selectionDispatchFacts: plan.selectionDispatchFacts,
            instrumentAutovibratoClock: plan.instrumentAutovibratoClock,
            instrumentAutovibratoRequests: plan.instrumentAutovibratoRequests,
            instrumentAutovibratoInitialHoldEventIndices: plan.instrumentAutovibratoInitialHoldEventIndices,
            semanticPitchProjection: plan.semanticPitchProjection,
            heldPitchProvenance: plan.heldPitchProvenance,
            nativePitchWriterSpans: plan.nativePitchWriterSpans,
            g23ChildlessPitchInvocations: plan.g23ChildlessPitchInvocations,
            rowExitProvenance: plan.rowExitProvenance,
            rowEntryTriggerResetFacts: plan.rowEntryTriggerResetFacts,
            delayedInstrumentResetFacts: plan.delayedInstrumentResetFacts,
            noteOnlyEventIndices: plan.noteOnlyEventIndices, coldReleasedEventIndices: plan.coldReleasedEventIndices,
            playbackStateEvents: plan.playbackStateEvents,
            xmEnvelopeTimeline: plan.xmEnvelopeTimeline,
            xmAudibleTimeline: plan.xmAudibleTimeline,
            xmChannelRows: plan.xmChannelRows, xmEmptyRoutes: plan.xmEmptyRoutes, xmInstrumentSelections: plan.xmInstrumentSelections,
            initialHeldPitchEventIndices: plan.initialHeldPitchEventIndices
        )
    }

    private static func includesEvent(
        _ eventIndex: Int,
        includedEventIndices: Set<Int>?
    ) -> Bool {
        includedEventIndices?.contains(eventIndex) ?? true
    }

    func prepare(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderSession {
        PlaybackSongOfflineRenderSession(request: effectiveRequest(from: request, frames: request.requestedFrameCount), preparedPlan: preparedPlan)
    }

    func render(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest, preparedPlan: preparedPlan)
        let block = session.render(frames: effectiveRequest.boundedFrameCount)
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: block,
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons,
            sameChannelVoiceLifetime: session.sameChannelVoiceLifetime,
            controlAdmission: session.controlAdmission
        )
    }

    func renderWindowed(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        samplePayloadStorageMode: PlaybackSongOfflineSamplePayloadStorageMode = .sharedCPayload,
        collectPerformanceDiagnostics: Bool = false,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic) -> Void)? = nil
    ) -> PlaybackSongOfflineRenderResult {
        renderWindowed(
            request,
            windowRows: windowRows,
            schedulingSource: .preindexed,
            samplePayloadUploadMode: samplePayloadStorageMode.cUploadMode,
            collectPerformanceDiagnostics: collectPerformanceDiagnostics,
            progress: progress
        )
    }

    private func renderWindowed(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        schedulingSource: PlaybackSongWindowedSchedulingSource,
        samplePayloadUploadMode: CSoftwareMixerSamplePayloadUploadMode,
        collectPerformanceDiagnostics: Bool,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic) -> Void)?
    ) -> PlaybackSongOfflineRenderResult {
        var interleavedPCM = [Float]()
        let coreResult = renderWindowedCore(
            request,
            windowRows: windowRows,
            schedulingSource: schedulingSource,
            samplePayloadUploadMode: samplePayloadUploadMode,
            collectPerformanceDiagnostics: collectPerformanceDiagnostics,
            cancellationCheck: nil,
            preparationCompleted: nil,
            prepareOutput: { totalFrames, config in
                interleavedPCM.reserveCapacity(totalFrames * config.channelCount)
                return CSoftwareMixer(config: config).config
            },
            collectBlock: { block in
                interleavedPCM.append(contentsOf: block.interleavedPCM)
            },
            windowSink: { completedWindow, totalWindows, diagnostic, _ in
                progress?(completedWindow, totalWindows, diagnostic)
            }
        )
        let block = MixerRenderBlock(
            config: coreResult.outputConfig,
            frameCount: coreResult.renderedFrameCount,
            interleavedPCM: interleavedPCM
        )
        return PlaybackSongOfflineRenderResult(
            request: coreResult.request,
            plan: coreResult.plan,
            block: block,
            scheduledVoiceIndices: coreResult.scheduledVoiceAttempts.map(\.voiceIndex),
            scheduledVoiceRejectionReasons: coreResult.scheduledVoiceAttempts.map(\.rejectionReason),
            scheduledVoiceAttempts: coreResult.scheduledVoiceAttempts,
            windowedRenderSummary: coreResult.windowedRenderSummary,
            sameChannelVoiceLifetime: coreResult.sameChannelVoiceLifetime,
            controlAdmission: coreResult.controlAdmission
        )
    }

    /// Retains the former scan-per-window scheduler as a byte-parity reference for tests only.
    func renderWindowedUsingScanPerWindowSchedulingReference(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int
    ) -> PlaybackSongOfflineRenderResult {
        renderWindowed(
            request,
            windowRows: windowRows,
            schedulingSource: .scanPerWindowReference,
            samplePayloadUploadMode: .preSanitizedBulkCopy,
            collectPerformanceDiagnostics: false,
            progress: nil
        )
    }

    /// Retains the defensive C sample sanitizer as an output-parity reference for tests.
    func renderWindowedUsingDefensiveSamplePayloadUploadReference(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        collectPerformanceDiagnostics: Bool = false
    ) -> PlaybackSongOfflineRenderResult {
        renderWindowed(
            request,
            windowRows: windowRows,
            schedulingSource: .preindexed,
            samplePayloadUploadMode: PlaybackSongOfflineSamplePayloadStorageMode.perVoiceDefensiveCopy.cUploadMode,
            collectPerformanceDiagnostics: collectPerformanceDiagnostics,
            progress: nil
        )
    }

    /// Builds the internal offline index; `includedEventIndices` must match any adapted isolation filter.
    func makeWindowedRenderScheduleIndex(
        for plan: PlaybackSongSyntheticPlan,
        totalFrames: Int,
        windowRows: Int,
        includedEventIndices: Set<Int>?,
        config: MixerRenderConfig = .init()
    ) -> PlaybackSongWindowedRenderIndex {
        let buildStartTime = VTXPerformanceClock.now()
        let safeWindowRows = max(1, windowRows)
        let safeTotalFrames = max(0, totalFrames)
        let specs = Self.windowSpecs(
            for: plan,
            totalFrames: safeTotalFrames,
            windowRows: safeWindowRows
        )
        let sameChannelLifetime = Self.sameChannelVoiceLifetimeDiagnostics(
            for: plan,
            renderedFrameCount: safeTotalFrames
        )
        return makeWindowedRenderScheduleIndex(
            for: plan,
            specs: specs,
            windowRows: safeWindowRows,
            includedEventIndices: includedEventIndices,
            sameChannelLifetime: sameChannelLifetime,
            buildStartTime: buildStartTime,
            config: config
        )
    }

    private func makeWindowedRenderScheduleIndex(
        for plan: PlaybackSongSyntheticPlan,
        specs: [RenderWindowSpec],
        windowRows: Int,
        includedEventIndices: Set<Int>?,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics,
        buildStartTime: UInt64,
        config: MixerRenderConfig
    ) -> PlaybackSongWindowedRenderIndex {
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        let mappingsByEventIndex = Dictionary(
            uniqueKeysWithValues: plan.diagnostics.eventMappings.map { ($0.eventIndex, $0) }
        )
        var eventBuckets = Array(repeating: [PlaybackSongWindowScheduledEvent](), count: specs.count)
        var continuationBuckets = Array(repeating: [PlaybackSongWindowContinuationCandidate](), count: specs.count)
        var continuations = Array(repeating: [PlaybackSongWindowContinuation](), count: specs.count)
        var updateBuckets = Array(repeating: [PlaybackSongWindowSchedulingUpdateCandidate](), count: specs.count)
        var windowIndexByRow: [Int: Int] = [:]
        var hasSubrowWindows = false
        for spec in specs {
            for row in spec.startRow..<spec.endRowExclusive {
                if windowIndexByRow.updateValue(spec.index, forKey: row) != nil { hasSubrowWindows = true }
            }
        }
        for (eventIndex, event) in plan.pattern.events.enumerated() {
            let scheduledFrame = scheduler.frame(for: event)
            // Keep the existing constant-time row shortcut only while rows have one frame window.
            let destination = hasSubrowWindows ? Self.windowIndex(containingFrame: scheduledFrame, in: specs) : windowIndexByRow[event.row]
            guard let windowIndex = destination,
                  specs.indices.contains(windowIndex),
                  scheduledFrame >= specs[windowIndex].startFrame,
                  scheduledFrame < specs[windowIndex].endFrame else {
                continue
            }
            eventBuckets[windowIndex].append(Self.windowScheduledEvent(
                eventIndex: eventIndex,
                event: event,
                scheduledFrame: scheduledFrame,
                mappingsByEventIndex: mappingsByEventIndex
            ))
        }

        for spec in specs where spec.startFrame > 0 {
            let windowContinuations = Self.continuations(
                for: spec,
                plan: plan,
                scheduler: scheduler,
                sameChannelLifetime: sameChannelLifetime,
                includedEventIndices: includedEventIndices,
                config: config
            )
            continuations[spec.index] = windowContinuations
            continuationBuckets[spec.index] = windowContinuations.map { continuation in
                Self.windowContinuationCandidate(
                    continuation,
                    scheduler: scheduler,
                    mappingsByEventIndex: mappingsByEventIndex
                )
            }
        }

        let allUpdates = Self.windowSchedulingUpdateCandidates(
            for: plan,
            sameChannelLifetime: sameChannelLifetime,
            includedEventIndices: includedEventIndices
        )
        for update in allUpdates {
            guard let windowIndex = Self.windowIndex(
                containingFrame: update.scheduledFrame,
                in: specs
            ) else {
                continue
            }
            updateBuckets[windowIndex].append(update)
        }
        let buckets = specs.map { spec in
            PlaybackSongWindowBucket(
                windowIndex: spec.index,
                startRow: spec.startRow,
                endRowExclusive: spec.endRowExclusive,
                startFrame: spec.startFrame,
                endFrame: spec.endFrame,
                scheduledEvents: eventBuckets[spec.index],
                continuationCandidates: continuationBuckets[spec.index],
                continuations: continuations[spec.index],
                schedulingUpdateCandidates: updateBuckets[spec.index]
            )
        }
        let buildDuration = VTXPerformanceClock.seconds(since: buildStartTime)
        let indexedSourceScanCount = PlaybackSongWindowSchedulingUpdateKind.allCases.count +
            (plan.instrumentAutovibratoRequests.isEmpty ? 0 : 1)
        let currentWindowScanCount = specs.count * indexedSourceScanCount
        let continuationScanCount = max(0, specs.count - 1) * 3
        let diagnostics = PlaybackSongWindowedRenderIndexDiagnostics(
            buildDurationSeconds: buildDuration,
            indexedWindowCount: buckets.count,
            indexedEventCount: buckets.map(\.scheduledEvents.count).reduce(0, +),
            indexedContinuationCandidateCount: buckets.map(\.continuationCandidates.count).reduce(0, +),
            indexedUpdateCandidateCount: buckets.map(\.schedulingUpdateCandidates.count).reduce(0, +),
            currentWindowEventAndUpdateFullArrayScanCount: currentWindowScanCount,
            currentContinuationTopLevelFullArrayScanCount: continuationScanCount,
            currentTopLevelFullArrayScanCount: currentWindowScanCount + continuationScanCount,
            indexedEventAndUpdateSourceArrayScanCount: indexedSourceScanCount,
            estimatedAvoidedEventAndUpdateFullArrayScanCount: max(0, currentWindowScanCount - indexedSourceScanCount),
            eventCountsByWindow: buckets.map(\.scheduledEvents.count),
            continuationCandidateCountsByWindow: buckets.map(\.continuationCandidates.count),
            updateCandidateCountsByWindow: buckets.map(\.schedulingUpdateCandidates.count)
        )
        return PlaybackSongWindowedRenderIndex(
            windowRows: windowRows,
            windows: buckets,
            diagnostics: diagnostics
        )
    }

    /// Recreates the existing scan-per-window inputs for prototype equivalence tests only.
    func currentWindowedRenderPreAcceptanceInputs(
        for plan: PlaybackSongSyntheticPlan,
        totalFrames: Int,
        windowRows: Int,
        includedEventIndices: Set<Int>?,
        config: MixerRenderConfig = .init()
    ) -> [PlaybackSongWindowBucket] {
        let specs = Self.windowSpecs(for: plan, totalFrames: max(0, totalFrames), windowRows: max(1, windowRows))
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        let mappings = Dictionary(uniqueKeysWithValues: plan.diagnostics.eventMappings.map { ($0.eventIndex, $0) })
        let lifetime = Self.sameChannelVoiceLifetimeDiagnostics(for: plan, renderedFrameCount: max(0, totalFrames))
        return specs.map { spec in
            let events = Self.eventPairs(in: spec, plan: plan, scheduler: scheduler).map { pair in
                Self.windowScheduledEvent(
                    eventIndex: pair.offset,
                    event: pair.element,
                    scheduledFrame: scheduler.frame(for: pair.element),
                    mappingsByEventIndex: mappings
                )
            }
            let windowContinuations = Self.continuations(
                for: spec,
                plan: plan,
                scheduler: scheduler,
                sameChannelLifetime: lifetime,
                includedEventIndices: includedEventIndices,
                config: config
            )
            let continuationCandidates = windowContinuations.map {
                Self.windowContinuationCandidate($0, scheduler: scheduler, mappingsByEventIndex: mappings)
            }
            return PlaybackSongWindowBucket(
                windowIndex: spec.index,
                startRow: spec.startRow,
                endRowExclusive: spec.endRowExclusive,
                startFrame: spec.startFrame,
                endFrame: spec.endFrame,
                scheduledEvents: events,
                continuationCandidates: continuationCandidates,
                continuations: windowContinuations,
                schedulingUpdateCandidates: Self.windowSchedulingUpdateCandidates(
                    for: plan,
                    sameChannelLifetime: lifetime,
                    includedEventIndices: includedEventIndices,
                    windowStartFrame: spec.startFrame,
                    windowEndFrame: spec.endFrame
                )
            )
        }
    }

    private func renderWindowedCore(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        schedulingSource: PlaybackSongWindowedSchedulingSource,
        samplePayloadUploadMode: CSoftwareMixerSamplePayloadUploadMode,
        collectPerformanceDiagnostics: Bool,
        cancellationCheck: (() throws -> Void)?,
        preparationCompleted: (() throws -> Void)?,
        prepareOutput: ((Int, MixerRenderConfig) -> MixerRenderConfig)?,
        collectBlock: ((MixerRenderBlock) -> Void)?,
        windowSink: (Int, Int, PlaybackSongWindowedRenderWindowDiagnostic, MixerRenderBlock) throws -> Void
    ) rethrows -> PlaybackSongWindowedRenderCoreResult {
        try cancellationCheck?()
        let renderStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let safeWindowRows = max(1, windowRows)
        let planAdaptStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let fullPlan = preparedPlan ?? PlaybackSongSyntheticAdapter.adapt(
            effectiveRequest.song,
            startOrderIndex: effectiveRequest.startOrderIndex,
            orderCount: effectiveRequest.orderCount,
            sampleRate: effectiveRequest.config.sampleRate
        )
        try cancellationCheck?()
        let includedEventIndices = Self.includedEventIndices(
            for: fullPlan,
            isolationFilter: effectiveRequest.isolationFilter
        )
        let adaptedPlan = Self.plan(
            fullPlan,
            mutingEventsNotIn: includedEventIndices
        ).extendingEnvelopeTail(throughFrame: effectiveRequest.boundedFrameCount)
        let totalFrames = effectiveRequest.boundedFrameCount
        let indexBuildStartTime = VTXPerformanceClock.now()
        var windows = Self.windowSpecs(
            for: adaptedPlan,
            totalFrames: totalFrames,
            windowRows: safeWindowRows
        )
#if DEBUG
        if let boundaries = verificationFrameBoundaries {
            let cuts = [0] + boundaries + [totalFrames]
            windows = zip(cuts, cuts.dropFirst()).enumerated().map { index, pair in
                RenderWindowSpec(index: index, startRow: 0, endRowExclusive: adaptedPlan.pattern.rowCount,
                    startFrame: pair.0, endFrame: pair.1)
            }
        }
#endif
        let scheduler = SyntheticTrackerScheduler(config: adaptedPlan.timingConfig)
        var admissionSummary = OfflineControlAdmissionSnapshot()
        var renderedFrames = 0
        var outputConfig = prepareOutput?(totalFrames, effectiveRequest.config) ?? effectiveRequest.config
        var attempts = [PlaybackSongScheduledVoiceAttempt]()
        var windowDiagnostics = [PlaybackSongWindowedRenderWindowDiagnostic]()
        let knownUnsupportedCarryoverReasons = Self.knownUnsupportedCarryoverReasons(for: adaptedPlan)
        let sameChannelLifetime = Self.sameChannelVoiceLifetimeDiagnostics(
            for: adaptedPlan,
            renderedFrameCount: totalFrames
        )
        let planAdaptDuration = collectPerformanceDiagnostics
            ? VTXPerformanceClock.seconds(since: planAdaptStartTime)
            : 0
        // Detect overfull row windows with compact frame counts before any history reconstruction.
        var needsSourceCheckpoints = false
        if adaptedPlan.pattern.events.count > CSoftwareMixer.maximumVoiceCount {
            var counts = Array(repeating: 0, count: windows.count)
            for event in adaptedPlan.pattern.events {
                if let index = Self.windowIndex(containingFrame: scheduler.frame(for: event), in: windows) { counts[index] += 1 }
            }
            needsSourceCheckpoints = counts.contains { $0 > CSoftwareMixer.maximumVoiceCount }
        }
#if DEBUG
        if verificationFrameBoundaries != nil && adaptedPlan.pattern.events.count > CSoftwareMixer.maximumVoiceCount {
            needsSourceCheckpoints = true
        }
#endif
        var windowedRenderIndex: PlaybackSongWindowedRenderIndex?
        switch schedulingSource {
        case .preindexed:
            try cancellationCheck?()
            windowedRenderIndex = needsSourceCheckpoints ? nil : makeWindowedRenderScheduleIndex(
                for: adaptedPlan,
                specs: windows,
                windowRows: safeWindowRows,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime,
                buildStartTime: indexBuildStartTime,
                config: effectiveRequest.config
            )
        case .scanPerWindowReference:
            windowedRenderIndex = nil
            if !needsSourceCheckpoints && adaptedPlan.pattern.events.count > CSoftwareMixer.maximumVoiceCount {
                let capacity = makeWindowedRenderScheduleIndex(for: adaptedPlan, specs: windows, windowRows: safeWindowRows,
                    includedEventIndices: includedEventIndices, sameChannelLifetime: sameChannelLifetime,
                    buildStartTime: indexBuildStartTime, config: effectiveRequest.config)
                needsSourceCheckpoints = capacity.windows.contains { $0.scheduledEvents.count + $0.continuations.count > CSoftwareMixer.maximumVoiceCount }
            }
        }
        if windowedRenderIndex?.windows.contains(where: { $0.scheduledEvents.count + $0.continuations.count > CSoftwareMixer.maximumVoiceCount }) == true {
            needsSourceCheckpoints = true
            windowedRenderIndex = nil
        }
        let sharedSamplePayloadCache = samplePayloadUploadMode == .sharedPreSanitizedCache
            ? CSoftwareMixerSharedSamplePayloadCache() : nil
        let sourceSession = needsSourceCheckpoints ? PlaybackSongOfflineRenderSession(
            request: effectiveRequest, preparedPlan: adaptedPlan, samplePayloadUploadMode: samplePayloadUploadMode,
            sharedSamplePayloadCache: sharedSamplePayloadCache, recordsSamplePayloadUploads: collectPerformanceDiagnostics) : nil
#if DEBUG
        if let sourceSession, let boundaries = verificationFrameBoundaries {
            sourceSession.configureSourceAdmissionForTesting(boundaries: boundaries)
        }
#endif
        try cancellationCheck?()
        try preparationCompleted?()
        try cancellationCheck?()
        var preindexedConsumedWindowCount = 0
        var uploadedSamplePayloadIdentities = Set<CSoftwareMixerSamplePayloadIdentity>()
        for spec in windows {
            if let session = sourceSession {
                try cancellationCheck?()
                let started = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
                var before = session.controlAdmission.sources!
                // Only final results retain the growing receipt list, never per-chunk counter snapshots.
                before.windows = []; admissionSummary.sources = nil
                let schedulingBefore = spec.index == 0 ? 0 : session.sourceSchedulingSeconds
                let renderingBefore = session.sourceRenderSeconds
                let block = session.render(frames: spec.frameCount)
                admissionSummary = session.controlAdmission
                let after = admissionSummary.sources!, payload = session.takeSourcePayloadDiagnostics()
                uploadedSamplePayloadIdentities.formUnion(payload.uploadedSampleIdentities)
                let carried = after.continuationImports - before.continuationImports
                let scheduled = after.started - before.started + after.cancelled - before.cancelled
                let rejected = after.rejected - (spec.index == 0 ? 0 : before.rejected)
                let performance = collectPerformanceDiagnostics ? Self.sourceWindowPerformance(
                    index: spec.index, after: payload,
                    scheduling: session.sourceSchedulingSeconds - schedulingBefore,
                    rendering: session.sourceRenderSeconds - renderingBefore,
                    total: VTXPerformanceClock.seconds(since: started), carried: carried,
                    carriedBytes: after.continuationPayloadBytes - before.continuationPayloadBytes,
                    shared: samplePayloadUploadMode == .sharedPreSanitizedCache) : nil
                let diagnostic = PlaybackSongWindowedRenderWindowDiagnostic(windowIndex: spec.index,
                    startRow: spec.startRow, endRowExclusive: spec.endRowExclusive,
                    startFrame: spec.startFrame, endFrame: spec.endFrame, renderedFrames: block.frameCount,
                    carriedVoiceCount: carried, releasedVoiceCarryoverCount: after.releasedContinuations - before.releasedContinuations,
                    carriedTonePortamentoVoiceCount: after.pitchContinuations - before.pitchContinuations,
                    boundaryContinuationCount: carried, droppedAtWindowBoundaryCount: 0, mayContainBoundaryCuts: false,
                    unsupportedCarryoverReasons: knownUnsupportedCarryoverReasons,
                    scheduledEventCount: scheduled + rejected, acceptedScheduledEventCount: after.started - before.started,
                    rejectedScheduledEventCount: rejected,
                    scheduledCapacityRejectedCount: after.capacityRejected - (spec.index == 0 ? 0 : before.capacityRejected),
                    invalidScheduledVoiceRejectedCount: after.invalidRejected - (spec.index == 0 ? 0 : before.invalidRejected), performanceDiagnostics: performance)
                windowDiagnostics.append(diagnostic)
                if block.frameCount > 0 {
                    renderedFrames += block.frameCount; collectBlock?(block)
                    try windowSink(spec.index + 1, windows.count, diagnostic, block)
                }
                if admissionSummary.failure != nil || block.frameCount == 0 { break }
                continue
            }
            let admission = OfflineControlAdmission(frameOrigin: spec.startFrame)
            try cancellationCheck?()
            let windowStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            let schedulingStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            let mixer = CSoftwareMixer(
                config: effectiveRequest.config,
                samplePayloadUploadMode: samplePayloadUploadMode,
                sharedSamplePayloadCache: sharedSamplePayloadCache,
                recordsSamplePayloadUploads: collectPerformanceDiagnostics
            )
            outputConfig = mixer.config
            let indexedBucket: PlaybackSongWindowBucket?
            if let windowedRenderIndex {
                precondition(windowedRenderIndex.windows.indices.contains(spec.index))
                let bucket = windowedRenderIndex.windows[spec.index]
                precondition(
                    bucket.windowIndex == spec.index &&
                        bucket.startRow == spec.startRow &&
                        bucket.endRowExclusive == spec.endRowExclusive &&
                        bucket.startFrame == spec.startFrame &&
                        bucket.endFrame == spec.endFrame
                )
                indexedBucket = bucket
                preindexedConsumedWindowCount += 1
            } else {
                indexedBucket = nil
            }
            let eventPairs: [(offset: Int, element: SyntheticTrackerEvent)]
            let continuations: [PlaybackSongWindowContinuation]
            if let indexedBucket {
                eventPairs = indexedBucket.scheduledEvents.map { scheduledEvent in
                    precondition(adaptedPlan.pattern.events.indices.contains(scheduledEvent.eventIndex))
                    return (
                        offset: scheduledEvent.eventIndex,
                        element: adaptedPlan.pattern.events[scheduledEvent.eventIndex]
                    )
                }
                continuations = indexedBucket.continuations
            } else {
                eventPairs = Self.eventPairs(
                    in: spec,
                    plan: adaptedPlan,
                    scheduler: scheduler
                )
                continuations = Self.continuations(
                    for: spec,
                    plan: adaptedPlan,
                    scheduler: scheduler,
                    sameChannelLifetime: sameChannelLifetime,
                    includedEventIndices: includedEventIndices,
                    config: effectiveRequest.config
                )
            }
            var continuationResults = [CSoftwareMixerScheduledVoiceResult]()
            continuationResults.reserveCapacity(continuations.count)
            for continuation in continuations {
                let result = Self.scheduleContinuation(continuation, on: mixer)
                continuationResults.append(result)
                attempts.append(PlaybackSongScheduledVoiceAttempt(
                    eventIndex: continuation.eventIndex,
                    voiceIndex: result.voiceIndex,
                    rejectionReason: result.rejectionReason,
                    windowIndex: spec.index
                ))
            }
            let localEvents = eventPairs.map { _, event in
                Self.localEvent(from: event, windowStartFrame: spec.startFrame, scheduler: scheduler)
            }
            let scheduledResults = scheduler.scheduleWithResults(localEvents, on: mixer)
            var voiceIndexByEventIndex = [Int: Int]()
            for (continuation, result) in zip(continuations, continuationResults) {
                if let voiceIndex = result.voiceIndex {
                    voiceIndexByEventIndex[continuation.eventIndex] = voiceIndex
                }
            }
            for (pair, result) in zip(eventPairs, scheduledResults) {
                if let voiceIndex = result.voiceIndex {
                    voiceIndexByEventIndex[pair.offset] = voiceIndex
                }
            }
            Self.schedulePlaybackStateEvents(
                adaptedPlan, voiceIndexByEventIndex: voiceIndexByEventIndex, on: mixer,
                includedEventIndices: includedEventIndices, windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame, admission: admission)
            if let indexedBucket {
                Self.schedulePreindexedWindowUpdates(
                    indexedBucket.schedulingUpdateCandidates,
                    plan: adaptedPlan,
                    sameChannelLifetime: sameChannelLifetime,
                    voiceIndexByEventIndex: voiceIndexByEventIndex,
                    on: mixer,
                    windowStartFrame: spec.startFrame, admission: admission)
            }
            let usesScanReference = indexedBucket == nil
            // The legacy calls remain a parity-test reference; production passes empty inputs after
            // consuming the ordered pre-indexed candidates above.
            Self.scheduleEnvelopePositionUpdates(
                usesScanReference ? adaptedPlan.diagnostics.envelopePositionEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices, admission: admission)
            Self.scheduleVoiceStateUpdates(
                usesScanReference ? adaptedPlan.diagnostics.voiceStateUpdates : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices, admission: admission)
            Self.scheduleTonePortamentoStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.tonePortamentoEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.schedulePortamentoSlideStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.portamentoSlideEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleFinePortamentoUpStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.finePortamentoUpEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleFinePortamentoDownStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.finePortamentoDownEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleExtraFinePortamentoStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.extraFinePortamentoEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleArpeggioStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.arpeggioEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleVibratoStepUpdates(
                usesScanReference ? adaptedPlan.diagnostics.vibratoEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices,
                sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleInstrumentAutoPitchUpdates(usesScanReference ? adaptedPlan.instrumentAutovibratoRequests : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex, on: mixer,
                windowStartFrame: spec.startFrame, windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices, sameChannelLifetime: sameChannelLifetime, admission: admission)
            Self.scheduleRetriggerCuts(
                usesScanReference ? adaptedPlan.diagnostics.retriggerEffects : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices, admission: admission)
            Self.scheduleSameChannelReplacementRamps(
                usesScanReference ? sameChannelLifetime.replacementEvents : [],
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices, admission: admission)
            attempts.append(contentsOf: zip(eventPairs, scheduledResults).map { pair, result in
                PlaybackSongScheduledVoiceAttempt(
                    eventIndex: pair.offset,
                    voiceIndex: result.voiceIndex,
                    rejectionReason: result.rejectionReason,
                    windowIndex: spec.index
                )
            })

            let schedulingDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: schedulingStartTime)
                : 0
            let mixerRenderStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            try cancellationCheck?()
            admissionSummary.merge(admission.snapshot)
            if admission.snapshot.failure != nil { break }
            let block = mixer.render(frames: spec.frameCount)
            try cancellationCheck?()
            let mixerRenderDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: mixerRenderStartTime)
                : 0
            renderedFrames += block.frameCount
            collectBlock?(block)
            let samplePayloadUploads = mixer.samplePayloadUploadDiagnostics
            uploadedSamplePayloadIdentities.formUnion(samplePayloadUploads.uploadedSampleIdentities)
            let acceptedContinuationPayloads = collectPerformanceDiagnostics
                ? zip(continuations, continuationResults).filter {
                    $0.1.wasAccepted && $0.0.event.sample.frameCount > 0
                }
                : []
            let continuationPayloadUploadCount = samplePayloadUploadMode == .sharedPreSanitizedCache
                ? 0
                : acceptedContinuationPayloads.count
            let continuationPayloadBytes = samplePayloadUploadMode == .sharedPreSanitizedCache
                ? 0
                : acceptedContinuationPayloads.reduce(0) { partial, pair in
                    partial + pair.0.event.sample.frameCount * MemoryLayout<Float>.size
                }
            let continuationSharedPayloadVoiceReferenceCount = samplePayloadUploadMode == .sharedPreSanitizedCache
                ? acceptedContinuationPayloads.count
                : 0
            let performanceDiagnostic = collectPerformanceDiagnostics
                ? PlaybackSongRenderWindowPerformanceDiagnostic(
                    windowIndex: spec.index,
                    schedulingDurationSeconds: schedulingDuration,
                    cMixerRenderDurationSeconds: mixerRenderDuration,
                    totalWindowDurationSeconds: VTXPerformanceClock.seconds(since: windowStartTime),
                    cMixerVoiceAddCount: samplePayloadUploads.cMixerVoiceAddCount,
                    samplePayloadUploadCount: samplePayloadUploads.uploadCount,
                    approximateSamplePayloadBytesCopied: samplePayloadUploads.approximateBytesCopied,
                    continuationSamplePayloadUploadCount: continuationPayloadUploadCount,
                    approximateContinuationSamplePayloadBytesCopied: continuationPayloadBytes,
                    continuationSharedSamplePayloadVoiceReferenceCount: continuationSharedPayloadVoiceReferenceCount,
                    uniqueSamplePayloadIdentityCount: samplePayloadUploads.uniqueSampleIdentityCount,
                    duplicateSamplePayloadUploadCount: samplePayloadUploads.duplicateUploadCount,
                    defensiveSanitizingUploadCount: samplePayloadUploads.defensiveSanitizingUploadCount,
                    preSanitizedBulkCopyUploadCount: samplePayloadUploads.preSanitizedBulkCopyUploadCount,
                    sharedSamplePayloadCreateCount: samplePayloadUploads.sharedPayloadCreateCount,
                    sharedSamplePayloadBytesAllocated: samplePayloadUploads.sharedPayloadBytesAllocated,
                    sharedSamplePayloadVoiceReferenceCount: samplePayloadUploads.sharedPayloadVoiceReferenceCount,
                    avoidedPerVoiceSamplePayloadUploadCount: samplePayloadUploads.avoidedPerVoiceUploadCount,
                    approximateAvoidedPerVoiceSamplePayloadUploadBytes: samplePayloadUploads.avoidedPerVoiceUploadBytes
                )
                : nil

            let droppedContinuations = continuationResults.filter { $0.rejectionReason != nil }.count
            let diagnostic = PlaybackSongWindowedRenderWindowDiagnostic(
                windowIndex: spec.index,
                startRow: spec.startRow,
                endRowExclusive: spec.endRowExclusive,
                startFrame: spec.startFrame,
                endFrame: spec.endFrame,
                renderedFrames: block.frameCount,
                carriedVoiceCount: continuationResults.filter(\.wasAccepted).count,
                releasedVoiceCarryoverCount: continuations.filter { !$0.runtimeState.keyOn }.count,
                carriedTonePortamentoVoiceCount: continuations.filter(\.carriedTonePortamentoActive).count,
                boundaryContinuationCount: continuations.count,
                droppedAtWindowBoundaryCount: droppedContinuations,
                mayContainBoundaryCuts: droppedContinuations > 0,
                unsupportedCarryoverReasons: spec.index == 0 ? [] : knownUnsupportedCarryoverReasons,
                scheduledEventCount: scheduledResults.count + continuationResults.count,
                acceptedScheduledEventCount: scheduledResults.filter(\.wasAccepted).count + continuationResults.filter(\.wasAccepted).count,
                rejectedScheduledEventCount: scheduledResults.filter { $0.rejectionReason != nil }.count + continuationResults.filter { $0.rejectionReason != nil }.count,
                scheduledCapacityRejectedCount: scheduledResults.filter { $0.rejectionReason == .scheduledVoiceCapacity }.count + continuationResults.filter { $0.rejectionReason == .scheduledVoiceCapacity }.count,
                invalidScheduledVoiceRejectedCount: scheduledResults.filter { $0.rejectionReason == .invalidScheduledVoice }.count + continuationResults.filter { $0.rejectionReason == .invalidScheduledVoice }.count,
                performanceDiagnostics: performanceDiagnostic
            )
            windowDiagnostics.append(diagnostic)
            try windowSink(spec.index + 1, windows.count, diagnostic, block)
            try cancellationCheck?()
        }

        try cancellationCheck?()

        if let session = sourceSession {
            attempts = session.scheduledVoiceIndices.enumerated().compactMap { source, voice in
                let reason = session.scheduledVoiceRejectionReasons[source]
                guard voice != nil || reason != nil else { return nil }
                return .init(eventIndex: source, voiceIndex: voice, rejectionReason: reason, windowIndex: nil)
            }
        }

        let scheduledCapacityRejectedCount = attempts.filter { $0.rejectionReason == .scheduledVoiceCapacity }.count
        let eventCoverage = adaptedPlan.diagnostics.eventCoverage
            .reportingCMixerVoiceCapacityRejections(scheduledCapacityRejectedCount)
        let finalPlan = adaptedPlan.replacingEventCoverage(eventCoverage)
        let windowPerformanceDiagnostics = windowDiagnostics.compactMap(\.performanceDiagnostics)
        let totalCarriedVoices = windowDiagnostics.map(\.carriedVoiceCount).reduce(0, +)
        let totalReleasedVoiceCarryovers = windowDiagnostics.map(\.releasedVoiceCarryoverCount).reduce(0, +)
        let totalCarriedTonePortamentoVoices = windowDiagnostics.map(\.carriedTonePortamentoVoiceCount).reduce(0, +)
        let totalBoundaryContinuations = windowDiagnostics.map(\.boundaryContinuationCount).reduce(0, +)
        let totalDroppedAtWindowBoundaries = windowDiagnostics.map(\.droppedAtWindowBoundaryCount).reduce(0, +)
        let totalInvalidScheduledVoiceRejects = attempts.filter { $0.rejectionReason == .invalidScheduledVoice }.count
        let performanceDiagnostics = collectPerformanceDiagnostics
            ? PlaybackSongRenderPerformanceDiagnostics(
                totalDurationSeconds: VTXPerformanceClock.seconds(since: renderStartTime),
                planAdaptDurationSeconds: planAdaptDuration,
                samplePayloadStorageMode: PlaybackSongOfflineSamplePayloadStorageMode(
                    cUploadMode: samplePayloadUploadMode
                ),
                usedPreindexedWindowScheduling: windowedRenderIndex != nil &&
                    preindexedConsumedWindowCount == windows.count,
                preindexedWindowSchedulingConsumedWindowCount: preindexedConsumedWindowCount,
                windowedRenderIndexDiagnostics: windowedRenderIndex?.diagnostics,
                totalWindowSchedulingDurationSeconds: windowPerformanceDiagnostics.map(\.schedulingDurationSeconds).reduce(0, +),
                totalCMixerRenderDurationSeconds: windowPerformanceDiagnostics.map(\.cMixerRenderDurationSeconds).reduce(0, +),
                renderWindowCount: windowDiagnostics.count,
                windowRows: safeWindowRows,
                totalFramesPlanned: totalFrames,
                totalFramesRendered: renderedFrames,
                totalScheduledEvents: attempts.count,
                totalAcceptedScheduledEvents: attempts.filter { $0.voiceIndex != nil }.count,
                totalRejectedScheduledEvents: attempts.filter { $0.rejectionReason != nil }.count,
                totalScheduledCapacityRejects: scheduledCapacityRejectedCount,
                totalInvalidScheduledVoiceRejects: totalInvalidScheduledVoiceRejects,
                totalCarriedVoices: totalCarriedVoices,
                totalBoundaryContinuations: totalBoundaryContinuations,
                totalDroppedAtWindowBoundaries: totalDroppedAtWindowBoundaries,
                mayContainBoundaryCuts: windowDiagnostics.contains { $0.mayContainBoundaryCuts },
                cMixerVoiceAddCount: windowPerformanceDiagnostics.map(\.cMixerVoiceAddCount).reduce(0, +),
                samplePayloadUploadCount: windowPerformanceDiagnostics.map(\.samplePayloadUploadCount).reduce(0, +),
                approximateSamplePayloadBytesCopied: windowPerformanceDiagnostics.map(\.approximateSamplePayloadBytesCopied).reduce(0, +),
                continuationSamplePayloadUploadCount: windowPerformanceDiagnostics.map(\.continuationSamplePayloadUploadCount).reduce(0, +),
                approximateContinuationSamplePayloadBytesCopied: windowPerformanceDiagnostics.map(\.approximateContinuationSamplePayloadBytesCopied).reduce(0, +),
                continuationSharedSamplePayloadVoiceReferenceCount: windowPerformanceDiagnostics.map(\.continuationSharedSamplePayloadVoiceReferenceCount).reduce(0, +),
                uniqueSamplePayloadIdentityCount: uploadedSamplePayloadIdentities.count,
                duplicateSamplePayloadUploadCount: max(
                    0,
                    windowPerformanceDiagnostics.map(\.samplePayloadUploadCount).reduce(0, +) - uploadedSamplePayloadIdentities.count
                ),
                defensiveSanitizingUploadCount: windowPerformanceDiagnostics.map(\.defensiveSanitizingUploadCount).reduce(0, +),
                preSanitizedBulkCopyUploadCount: windowPerformanceDiagnostics.map(\.preSanitizedBulkCopyUploadCount).reduce(0, +),
                sharedSamplePayloadCreateCount: windowPerformanceDiagnostics.map(\.sharedSamplePayloadCreateCount).reduce(0, +),
                sharedSamplePayloadBytesAllocated: windowPerformanceDiagnostics.map(\.sharedSamplePayloadBytesAllocated).reduce(0, +),
                sharedSamplePayloadVoiceReferenceCount: windowPerformanceDiagnostics.map(\.sharedSamplePayloadVoiceReferenceCount).reduce(0, +),
                avoidedPerVoiceSamplePayloadUploadCount: windowPerformanceDiagnostics.map(\.avoidedPerVoiceSamplePayloadUploadCount).reduce(0, +),
                approximateAvoidedPerVoiceSamplePayloadUploadBytes: windowPerformanceDiagnostics.map(\.approximateAvoidedPerVoiceSamplePayloadUploadBytes).reduce(0, +),
                windows: windowPerformanceDiagnostics
            )
            : nil
        let summary = PlaybackSongWindowedRenderSummary(
            windowRows: safeWindowRows,
            windows: windowDiagnostics,
            totalRenderedFrames: renderedFrames,
            totalCarriedVoices: totalCarriedVoices,
            totalReleasedVoiceCarryovers: totalReleasedVoiceCarryovers,
            totalCarriedTonePortamentoVoices: totalCarriedTonePortamentoVoices,
            totalBoundaryContinuations: totalBoundaryContinuations,
            totalDroppedAtWindowBoundaries: totalDroppedAtWindowBoundaries,
            mayContainBoundaryCuts: windowDiagnostics.contains { $0.mayContainBoundaryCuts },
            totalScheduledEvents: attempts.count,
            totalAcceptedScheduledEvents: attempts.filter { $0.voiceIndex != nil }.count,
            totalRejectedScheduledEvents: attempts.filter { $0.rejectionReason != nil }.count,
            totalScheduledCapacityRejects: scheduledCapacityRejectedCount,
            totalInvalidScheduledVoiceRejects: totalInvalidScheduledVoiceRejects,
            knownUnsupportedCarryoverReasons: knownUnsupportedCarryoverReasons,
            knownStateCarryoverLimitations: PlaybackSongWindowedRenderSummary.stateCarryoverLimitations,
            performanceDiagnostics: performanceDiagnostics
        )
        return PlaybackSongWindowedRenderCoreResult(
            controlAdmission: admissionSummary,
            request: effectiveRequest,
            plan: finalPlan,
            outputConfig: outputConfig,
            renderedFrameCount: renderedFrames,
            scheduledVoiceAttempts: attempts,
            windowedRenderSummary: summary,
            sameChannelVoiceLifetime: sameChannelLifetime
        )
    }

    private static func sourceWindowPerformance(index: Int,
        after: CSoftwareMixerSamplePayloadUploadDiagnostics, scheduling: Double, rendering: Double,
        total: Double, carried: Int, carriedBytes: Int, shared: Bool) -> PlaybackSongRenderWindowPerformanceDiagnostic {
        .init(windowIndex: index, schedulingDurationSeconds: scheduling, cMixerRenderDurationSeconds: rendering,
            totalWindowDurationSeconds: total, cMixerVoiceAddCount: after.cMixerVoiceAddCount,
            samplePayloadUploadCount: after.uploadCount,
            approximateSamplePayloadBytesCopied: after.approximateBytesCopied,
            continuationSamplePayloadUploadCount: shared ? 0 : carried,
            approximateContinuationSamplePayloadBytesCopied: shared ? 0 : carriedBytes,
            continuationSharedSamplePayloadVoiceReferenceCount: shared ? carried : 0,
            uniqueSamplePayloadIdentityCount: after.uniqueSampleIdentityCount,
            duplicateSamplePayloadUploadCount: after.duplicateUploadCount,
            defensiveSanitizingUploadCount: after.defensiveSanitizingUploadCount,
            preSanitizedBulkCopyUploadCount: after.preSanitizedBulkCopyUploadCount,
            sharedSamplePayloadCreateCount: after.sharedPayloadCreateCount,
            sharedSamplePayloadBytesAllocated: after.sharedPayloadBytesAllocated,
            sharedSamplePayloadVoiceReferenceCount: after.sharedPayloadVoiceReferenceCount,
            avoidedPerVoiceSamplePayloadUploadCount: after.avoidedPerVoiceUploadCount,
            approximateAvoidedPerVoiceSamplePayloadUploadBytes: after.avoidedPerVoiceUploadBytes)
    }

    func render(_ request: PlaybackSongOfflineRenderRequest, splitFrameCounts: [Int]) -> PlaybackSongOfflineRenderResult {
        let requestedFrames = splitFrameCounts.reduce(0) { partialResult, frames in
            let safeFrames = max(0, frames)
            guard partialResult <= Int.max - safeFrames else {
                return Int.max
            }
            return partialResult + safeFrames
        }
        let effectiveRequest = effectiveRequest(from: request, frames: requestedFrames)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest, preparedPlan: preparedPlan)
        var remainingFrames = effectiveRequest.boundedFrameCount
        var interleavedPCM = [Float]()
        for requestedChunkFrames in splitFrameCounts where remainingFrames > 0 {
            let chunkFrames = min(max(0, requestedChunkFrames), remainingFrames)
            let chunk = session.render(frames: chunkFrames)
            interleavedPCM.append(contentsOf: chunk.interleavedPCM)
            remainingFrames -= chunk.frameCount
            if session.controlAdmission.failure != nil { break }
        }
        let block = MixerRenderBlock(
            config: session.config,
            frameCount: effectiveRequest.boundedFrameCount - remainingFrames,
            interleavedPCM: interleavedPCM
        )
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: block,
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons,
            sameChannelVoiceLifetime: session.sameChannelVoiceLifetime,
            controlAdmission: session.controlAdmission
        )
    }

    func renderStreaming(
        _ request: PlaybackSongOfflineRenderRequest,
        chunkFrameCount: Int,
        progress: ((Int, Int, MixerRenderBlock) throws -> Void)? = nil
    ) rethrows -> PlaybackSongOfflineStreamingRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest, preparedPlan: preparedPlan)
        let totalFrames = effectiveRequest.boundedFrameCount
        let safeChunkFrameCount = max(1, chunkFrameCount)
        var renderedFrames = 0
        while renderedFrames < totalFrames {
            let requestedFrames = min(safeChunkFrameCount, totalFrames - renderedFrames)
            let block = session.render(frames: requestedFrames)
            guard block.frameCount > 0 else {
                break
            }
            renderedFrames += block.frameCount
            try progress?(renderedFrames, totalFrames, block)
            if session.controlAdmission.failure != nil { break }
        }
        return PlaybackSongOfflineStreamingRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            renderedFrameCount: renderedFrames,
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons,
            windowedRenderSummary: nil,
            sameChannelVoiceLifetime: session.sameChannelVoiceLifetime,
            exportDiagnostics: nil,
            wavExportPerformanceDiagnostics: nil,
            controlAdmission: session.controlAdmission
        )
    }

    func renderWindowedStreaming(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        samplePayloadStorageMode: PlaybackSongOfflineSamplePayloadStorageMode = .sharedCPayload,
        collectPerformanceDiagnostics: Bool = false,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic, MixerRenderBlock) throws -> Void)? = nil
    ) rethrows -> PlaybackSongOfflineStreamingRenderResult {
        try renderWindowedStreaming(
            request,
            windowRows: windowRows,
            samplePayloadStorageMode: samplePayloadStorageMode,
            collectPerformanceDiagnostics: collectPerformanceDiagnostics,
            cancellationCheck: nil,
            preparationCompleted: nil,
            progress: progress
        )
    }

    func renderWindowedStreaming(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        samplePayloadStorageMode: PlaybackSongOfflineSamplePayloadStorageMode = .sharedCPayload,
        collectPerformanceDiagnostics: Bool = false,
        cancellationCheck: (() throws -> Void)?,
        preparationCompleted: (() throws -> Void)? = nil,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic, MixerRenderBlock) throws -> Void)? = nil
    ) rethrows -> PlaybackSongOfflineStreamingRenderResult {
        let coreResult = try renderWindowedCore(
            request,
            windowRows: windowRows,
            schedulingSource: .preindexed,
            samplePayloadUploadMode: samplePayloadStorageMode.cUploadMode,
            collectPerformanceDiagnostics: collectPerformanceDiagnostics,
            cancellationCheck: cancellationCheck,
            preparationCompleted: preparationCompleted,
            prepareOutput: nil,
            collectBlock: nil,
            windowSink: { completedWindow, totalWindows, diagnostic, block in
                try progress?(completedWindow, totalWindows, diagnostic, block)
            }
        )
        return PlaybackSongOfflineStreamingRenderResult(
            request: coreResult.request,
            plan: coreResult.plan,
            renderedFrameCount: coreResult.renderedFrameCount,
            scheduledVoiceIndices: coreResult.scheduledVoiceAttempts.map(\.voiceIndex),
            scheduledVoiceRejectionReasons: coreResult.scheduledVoiceAttempts.map(\.rejectionReason),
            windowedRenderSummary: coreResult.windowedRenderSummary,
            sameChannelVoiceLifetime: coreResult.sameChannelVoiceLifetime,
            exportDiagnostics: nil,
            wavExportPerformanceDiagnostics: nil,
            controlAdmission: coreResult.controlAdmission
        )
    }

    private static func schedulePreindexedWindowUpdates(
        _ candidates: [PlaybackSongWindowSchedulingUpdateCandidate],
        plan: PlaybackSongSyntheticPlan,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics,
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int,
        admission: OfflineControlAdmission
    ) {
        for candidate in candidates {
            guard let voiceIndex = voiceIndexByEventIndex[candidate.activeEventIndex] else {
                continue
            }
            precondition(candidate.scheduledFrame >= windowStartFrame)
            let localFrame = candidate.scheduledFrame - windowStartFrame
            let parent = candidate.sourceDiagnosticIndex, child = candidate.childUpdateIndex ?? 0
            func emit(_ family: Int, _ value: OfflineControlValue) {
                admission.submit(family: family, parent: parent, child: child, source: candidate.activeEventIndex,
                    voice: voiceIndex, frame: localFrame, on: mixer, value: value)
            }
            switch candidate.kind {
            case .envelopePosition:
                let diagnostics = plan.diagnostics.envelopePositionEffects
                precondition(diagnostics.indices.contains(candidate.sourceDiagnosticIndex))
                guard let position = diagnostics[candidate.sourceDiagnosticIndex].appliedPositionFrame else {
                    preconditionFailure("Pre-indexed envelope update lost its applied position")
                }
                emit(2, .position(position))
            case .voiceGainPan:
                let updates = plan.diagnostics.voiceStateUpdates
                precondition(updates.indices.contains(candidate.sourceDiagnosticIndex))
                let update = updates[candidate.sourceDiagnosticIndex]
                emit(3, .gainPan(changedGain(from: update), changedPan(from: update)))
            case .tonePortamentoStep,
                 .portamentoSlideStep,
                 .finePortamentoUpStep,
                 .finePortamentoDownStep,
                 .extraFinePortamentoStep,
                 .arpeggioStep,
                 .vibratoStep:
                guard sameChannelLifetime.permitsPitchUpdate(eventIndex: candidate.activeEventIndex, at: candidate.scheduledFrame) else { continue }
                let update = preindexedStepUpdate(candidate, diagnostics: plan.diagnostics)
                let rank: Int
                switch candidate.kind {
                case .tonePortamentoStep: rank = 4
                case .portamentoSlideStep: rank = 5
                case .finePortamentoUpStep: rank = 6
                case .finePortamentoDownStep: rank = 7
                case .extraFinePortamentoStep: rank = 8
                case .arpeggioStep: rank = 9
                default: rank = 10
                }
                emit(rank, .step(update.playbackStepAfter))
            case .instrumentAutoPitchStep:
                guard sameChannelLifetime.permitsPitchUpdate(eventIndex: candidate.activeEventIndex, at: candidate.scheduledFrame) else { continue }
                let request = plan.instrumentAutovibratoRequests[candidate.sourceDiagnosticIndex]
                emit(11, .step(request.playbackStep))
            case .noteCut:
                break // The audible timeline owns ECx; this index entry is diagnostic only.
            case .retriggerCut:
                emit(12, .cut)
            case .sameChannelReplacementRamp:
                let replacements = sameChannelLifetime.replacementEvents
                precondition(replacements.indices.contains(candidate.sourceDiagnosticIndex))
                emit(13, .retirement)
            }
        }
    }

    private static func preindexedStepUpdate(
        _ candidate: PlaybackSongWindowSchedulingUpdateCandidate,
        diagnostics: PlaybackSongSyntheticDiagnostics
    ) -> PlaybackSongSyntheticTonePortamentoStepUpdate {
        guard let childIndex = candidate.childUpdateIndex else {
            preconditionFailure("Pre-indexed step update lost its child index")
        }
        let diagnosticIndex = candidate.sourceDiagnosticIndex
        switch candidate.kind {
        case .tonePortamentoStep:
            precondition(diagnostics.tonePortamentoEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.tonePortamentoEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        case .portamentoSlideStep:
            precondition(diagnostics.portamentoSlideEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.portamentoSlideEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        case .finePortamentoUpStep:
            precondition(diagnostics.finePortamentoUpEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.finePortamentoUpEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        case .finePortamentoDownStep:
            precondition(diagnostics.finePortamentoDownEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.finePortamentoDownEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        case .extraFinePortamentoStep:
            precondition(diagnostics.extraFinePortamentoEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.extraFinePortamentoEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        case .arpeggioStep:
            precondition(diagnostics.arpeggioEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.arpeggioEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        case .vibratoStep:
            precondition(diagnostics.vibratoEffects.indices.contains(diagnosticIndex))
            let updates = diagnostics.vibratoEffects[diagnosticIndex].stepUpdates
            precondition(updates.indices.contains(childIndex))
            return updates[childIndex]
        default:
            preconditionFailure("Pre-indexed non-step update reached the step scheduler")
        }
    }

    fileprivate static func scheduleVoiceStateUpdates(
        _ updates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, update) in updates.enumerated() where update.activeVoiceUpdated {
            guard let activeEventIndex = update.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            guard update.scheduledFrame >= windowStartFrame else {
                continue
            }
            if let windowEndFrame,
               update.scheduledFrame >= windowEndFrame {
                continue
            }
            let gain = changedGain(from: update)
            let pan = changedPan(from: update)
            guard gain != nil || pan != nil else {
                continue
            }
            admission.submit(family: 3, parent: parent, source: activeEventIndex, voice: voiceIndex,
                frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .gainPan(gain, pan))
        }
    }

    /// Opt-in planning/test counters; ordinary playback allocates no work recorder.
    final class CarriedPlaybackStateWork {
        var indexBuildCount = 0
        var mappingsVisited = 0
        var entriesIndexed = 0
        var sortComparisons = 0
        var lookupCount = 0
        var entriesVisited = 0
    }

    /// Filters stale channel generations before either runtime or offline scheduling.
    /// The scalar index belongs to this invocation, so manually mutated and derived plans
    /// always use their current sources, mappings and inclusive cut diagnostics.
    static func carriedPlaybackStateEvents(
        for plan: PlaybackSongSyntheticPlan, work: CarriedPlaybackStateWork? = nil,
        visit: ((Int, PlaybackVoiceStateEvent) -> Void)? = nil
    ) -> [PlaybackVoiceStateEvent] {
        let qualifying = plan.playbackStateEvents.enumerated().filter { _, update in
            switch update.change {
            case let .reset(reset): guard reset.dimensions != 0 else { return false }
            case let .keyOff(decrement): guard decrement.isFinite, decrement >= 0 else { return false }
            }
            return plan.pattern.events.indices.contains(update.activeEventIndex)
        }
        guard !qualifying.isEmpty else { return [] }
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        var sourcesByChannel = [Int: [(frame: Int, eventIndex: Int)]]()
        work?.indexBuildCount += 1
        for mapping in plan.diagnostics.eventMappings {
            work?.mappingsVisited += 1
            guard plan.pattern.events.indices.contains(mapping.eventIndex) else { continue }
            sourcesByChannel[mapping.channelIndex, default: []].append(
                (scheduler.frame(for: plan.pattern.events[mapping.eventIndex]), mapping.eventIndex))
            work?.entriesIndexed += 1
        }
        for channel in Array(sourcesByChannel.keys) {
            sourcesByChannel[channel]?.sort {
                work?.sortComparisons += 1
                return $0.frame == $1.frame ? $0.eventIndex < $1.eventIndex : $0.frame < $1.frame
            }
        }
        return qualifying.filter { _, update in
            work?.lookupCount += 1
            guard let sources = sourcesByChannel[update.channelIndex] else { return false }
            var lower = 0, upper = sources.count
            // Upper bound includes the boundary and leaves the greatest event index
            // last on equal source frames, regardless of mapping enumeration order.
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                work?.entriesVisited += 1
                if sources[middle].frame <= update.scheduledFrame { lower = middle + 1 }
                else { upper = middle }
            }
            guard lower > 0, sources[lower - 1].eventIndex == update.activeEventIndex else { return false }
            return !hasAppliedSourceStop(eventIndex: update.activeEventIndex, atOrBefore: update.scheduledFrame, plan: plan) &&
                !hasAppliedRetriggerCut(eventIndex: update.activeEventIndex, atOrBefore: update.scheduledFrame, plan: plan)
        }.sorted {
            $0.element.scheduledFrame == $1.element.scheduledFrame ? $0.offset < $1.offset : $0.element.scheduledFrame < $1.element.scheduledFrame
        }.map { visit?($0.offset, $0.element); return $0.element }
    }

    /// Schedules only the current window's transitions; C checks activity again at application.
    static func schedulePlaybackStateEvents(
        _ plan: PlaybackSongSyntheticPlan, voiceIndexByEventIndex: [Int: Int], on mixer: CSoftwareMixer,
        includedEventIndices: Set<Int>? = nil, windowStartFrame: Int = 0, windowEndFrame: Int = Int.max,
        admission: OfflineControlAdmission = .init()
    ) {
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        for eventIndex in plan.initialHeldPitchEventIndices {
            let frame = scheduler.frame(for: plan.pattern.events[eventIndex])
            guard frame >= windowStartFrame, frame < windowEndFrame,
                  includesEvent(eventIndex, includedEventIndices: includedEventIndices),
                  let voice = voiceIndexByEventIndex[eventIndex] else { continue }
            // Use the existing explicit-zero update; generic initial-step sanitization stays intact.
            admission.submit(family: 0, parent: eventIndex, source: eventIndex, voice: voice,
                frame: frame - windowStartFrame, on: mixer, value: .step(0))
        }
        mixer.setSourceStopSchedule(plan.xmEmptyRoutes.enumerated().compactMap { parent, route in
            guard route.scheduledFrame >= windowStartFrame, route.scheduledFrame < windowEndFrame,
                  let event = route.stoppedEventIndex, includesEvent(event, includedEventIndices: includedEventIndices),
                  let voice = voiceIndexByEventIndex[event] else { return nil }
            if admission.capturesSourceSchedules {
                admission.submit(family: 16, parent: parent, source: event, voice: voice,
                    frame: route.scheduledFrame - windowStartFrame, on: mixer, value: .stop)
                return nil
            }
            // The exact installed stop owns cancellation of not-yet-admitted slow keys.
            if admission.snapshot.usedSlowPath {
                admission.stopsBySource[event] = min(admission.stopsBySource[event] ?? Int.max, route.scheduledFrame)
            }
            return (frame: route.scheduledFrame - windowStartFrame, voice: voice)
        })
        mixer.setAudibleOutputSchedule((plan.xmAudibleTimeline?.updates ?? []).enumerated().compactMap { parent, update in
            guard update.scheduledFrame >= windowStartFrame, update.scheduledFrame < windowEndFrame,
                  includesEvent(update.eventIndex, includedEventIndices: includedEventIndices),
                  let voice = voiceIndexByEventIndex[update.eventIndex] else { return nil }
            if admission.capturesSourceSchedules {
                admission.submit(family: 15, parent: parent, source: update.eventIndex, voice: voice,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .audible(update))
                return nil
            }
            return (frame: update.scheduledFrame - windowStartFrame, voice: voice, target: update)
        })
        let semanticUpdates = plan.xmEnvelopeTimeline?.updates ?? []
        mixer.setEnvelopeSemanticSchedule(semanticUpdates.enumerated().compactMap { parent, update in
            guard update.scheduledFrame >= windowStartFrame, update.scheduledFrame < windowEndFrame,
                  includesEvent(update.eventIndex, includedEventIndices: includedEventIndices),
                  let voice = voiceIndexByEventIndex[update.eventIndex] else { return nil }
            if admission.capturesSourceSchedules {
                admission.submit(family: 14, parent: parent, source: update.eventIndex, voice: voice,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .semantic(update.state))
                return nil
            }
            return (frame: update.scheduledFrame - windowStartFrame, voice: voice, state: update.state)
        })
        _ = carriedPlaybackStateEvents(for: plan, visit: { parent, update in
            guard update.scheduledFrame >= windowStartFrame, update.scheduledFrame < windowEndFrame,
                  plan.xmEnvelopeTimeline?.updatesByEvent[update.activeEventIndex] == nil,
                  includesEvent(update.activeEventIndex, includedEventIndices: includedEventIndices),
                  let voice = voiceIndexByEventIndex[update.activeEventIndex] else { return }
            admission.submit(family: 1, parent: parent, source: update.activeEventIndex, voice: voice,
                frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .state(update.change))
        })
    }

    fileprivate static func scheduleEnvelopePositionUpdates(
        _ diagnostics: [PlaybackSongSyntheticEnvelopePositionDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex],
                  let appliedPositionFrame = diagnostic.appliedPositionFrame else {
                continue
            }
            guard diagnostic.scheduledFrame >= windowStartFrame else {
                continue
            }
            if let windowEndFrame,
               diagnostic.scheduledFrame >= windowEndFrame {
                continue
            }
            admission.submit(family: 2, parent: parent, source: activeEventIndex, voice: voiceIndex,
                frame: diagnostic.scheduledFrame - windowStartFrame, on: mixer, value: .position(appliedPositionFrame))
        }
    }

    fileprivate static func scheduleTonePortamentoStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticTonePortamentoDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 4, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    fileprivate static func schedulePortamentoSlideStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticPortamentoSlideDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 5, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    fileprivate static func scheduleFinePortamentoUpStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticFinePortamentoUpDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 6, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    fileprivate static func scheduleFinePortamentoDownStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticFinePortamentoDownDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 7, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    fileprivate static func scheduleExtraFinePortamentoStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticExtraFinePortamentoDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 8, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    fileprivate static func scheduleArpeggioStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticArpeggioDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 9, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    fileprivate static func scheduleVibratoStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticVibratoDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, diagnostic) in diagnostics.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for (child, update) in diagnostic.stepUpdates.enumerated() {
                guard update.scheduledFrame >= windowStartFrame,
                      sameChannelLifetime?.permitsPitchUpdate(eventIndex: activeEventIndex, at: update.scheduledFrame) != false else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 10, parent: parent, child: child, source: activeEventIndex, voice: voiceIndex,
                    frame: update.scheduledFrame - windowStartFrame, on: mixer, value: .step(update.playbackStepAfter))
            }
        }
    }

    /// Uses the same source-generation and replacement cancellation contract as ordinary pitch.
    fileprivate static func scheduleInstrumentAutoPitchUpdates(
        _ requests: [PlaybackSongInstrumentAutovibratoPublication.Request],
        voiceIndexByEventIndex: [Int: Int], on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0, windowEndFrame: Int = Int.max,
        includedEventIndices: Set<Int>? = nil,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, request) in requests.enumerated() {
            guard request.scheduledFrame >= windowStartFrame, request.scheduledFrame < windowEndFrame,
                  includesEvent(request.activeEventIndex, includedEventIndices: includedEventIndices),
                  sameChannelLifetime?.permitsPitchUpdate(eventIndex: request.activeEventIndex, at: request.scheduledFrame) != false,
                  let voice = voiceIndexByEventIndex[request.activeEventIndex] else { continue }
            admission.submit(family: 11, parent: parent, source: request.activeEventIndex, voice: voice,
                frame: request.scheduledFrame - windowStartFrame, on: mixer, value: .step(request.playbackStep))
        }
    }

    fileprivate static func scheduleRetriggerCuts(
        _ retriggers: [PlaybackSongSyntheticRetriggerDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, retrigger) in retriggers.enumerated() where retrigger.applied {
            for (child, (eventIndex, scheduledFrame)) in zip(retrigger.replacedEventIndices, retrigger.replacementFrames ?? retrigger.retriggerFrames).enumerated() {
                guard includesEvent(eventIndex, includedEventIndices: includedEventIndices),
                      let voiceIndex = voiceIndexByEventIndex[eventIndex] else {
                    continue
                }
                guard scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   scheduledFrame >= windowEndFrame {
                    continue
                }
                admission.submit(family: 12, parent: parent, child: child, source: eventIndex, voice: voiceIndex,
                    frame: scheduledFrame - windowStartFrame, on: mixer, value: .cut)
            }
        }
    }

    fileprivate static func scheduleSameChannelReplacementRamps(
        _ replacements: [PlaybackSongSameChannelReplacementEvent],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil,
        admission: OfflineControlAdmission = .init()
    ) {
        for (parent, replacement) in replacements.enumerated() {
            guard includesEvent(replacement.oldEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[replacement.oldEventIndex] else {
                continue
            }
            guard replacement.replacementFrame >= windowStartFrame else {
                continue
            }
            if let windowEndFrame,
               replacement.replacementFrame >= windowEndFrame {
                continue
            }
            admission.submit(family: 13, parent: parent, source: replacement.oldEventIndex, voice: voiceIndex,
                frame: replacement.replacementFrame - windowStartFrame, on: mixer, value: .retirement)
        }
    }

    private static func changedGain(
        from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Float? {
        update.physicalGainChange
    }

    fileprivate static func changedPan(
        from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Float? {
        guard let before = update.panBefore,
              let after = update.panAfter,
              before != after else {
            return nil
        }
        return after
    }

    /// Renders a bounded adapted `PlaybackSong` segment through the offline C-backed mixer and writes PCM16 WAV.
    ///
    /// This is a local comparison helper only. It reuses the existing bounded render path and does not parse
    /// modules, traverse full songs, compare against reference renderers, or change live playback.
    @discardableResult
    func exportWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to url: URL,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> PlaybackSongOfflineRenderResult {
        let result = render(request)
        try result.controlAdmission.requireSuccess()
        let diagnostics = try MixerWAVExporter.writePCM16WAV(from: result.block, to: url, exportPolicy: exportPolicy)
        return result.replacingExportDiagnostics(diagnostics)
    }

    @discardableResult
    func exportWindowedWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to url: URL,
        windowRows: Int,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> PlaybackSongOfflineRenderResult {
        let result = renderWindowed(request, windowRows: windowRows)
        try result.controlAdmission.requireSuccess()
        let diagnostics = try MixerWAVExporter.writePCM16WAV(from: result.block, to: url, exportPolicy: exportPolicy)
        return result.replacingExportDiagnostics(diagnostics)
    }

    private func effectiveRequest(
        from request: PlaybackSongOfflineRenderRequest,
        frames: Int
    ) -> PlaybackSongOfflineRenderRequest {
        request.replacingFrameCount(
            frames,
            maximumFrameCount: min(request.maximumFrameCount, maximumFrameCount)
        )
    }

    private struct RenderWindowSpec: Equatable {
        let index: Int
        let startRow: Int
        let endRowExclusive: Int
        let startFrame: Int
        let endFrame: Int

        var frameCount: Int {
            max(0, endFrame - startFrame)
        }
    }

    private struct SourcePositionState: Equatable {
        let samplePosition: Double
        let pingPongDirection: Int
    }

    private struct GainPanRampSimulation: Equatable {
        let start: Float
        let target: Float
        let scheduledFrame: Int
        let totalFrames: Int

        func value(at frame: Int) -> Float {
            let elapsedFrames = max(0, frame - scheduledFrame)
            let progressFrame = min(totalFrames, elapsedFrames + 1)
            let progress = Float(progressFrame) / Float(totalFrames)
            return start + ((target - start) * progress)
        }

        func runtimeState(at boundaryFrame: Int) -> CSoftwareMixerValueRampRuntimeState? {
            let elapsedFrames = boundaryFrame - scheduledFrame
            guard elapsedFrames >= 0,
                  elapsedFrames < totalFrames else {
                return nil
            }
            return CSoftwareMixerValueRampRuntimeState(
                start: start,
                target: target,
                totalFrames: totalFrames,
                positionFrame: elapsedFrames
            )
        }
    }

    private struct GainPanStateAtBoundary: Equatable {
        let gain: Float
        let pan: Float
        let effectiveGain: Float
        let effectivePan: Float
        let gainRamp: CSoftwareMixerValueRampRuntimeState?
        let panRamp: CSoftwareMixerValueRampRuntimeState?
    }

    private struct StepStateAtBoundary: Equatable {
        let playbackStep: Double
        let carriedTonePortamentoActive: Bool
    }

    private struct SameChannelActiveVoice: Equatable {
        let eventIndex: Int
        var rampCompletionFrame: Int?
        var pitchUpdateEndFrame: Int? = nil
    }

    private static func windowSpecs(
        for plan: PlaybackSongSyntheticPlan,
        totalFrames: Int,
        windowRows: Int
    ) -> [RenderWindowSpec] {
        guard totalFrames > 0 else {
            return []
        }
        let safeWindowRows = max(1, windowRows)
        let syntheticRowCount = max(0, plan.diagnostics.syntheticRowCount)
        guard syntheticRowCount > 0 else {
            return [
                RenderWindowSpec(
                    index: 0,
                    startRow: 0,
                    endRowExclusive: 0,
                    startFrame: 0,
                    endFrame: totalFrames
                )
            ]
        }

        let rowStartFrames = Dictionary(
            uniqueKeysWithValues: plan.diagnostics.rowTiming.map { ($0.syntheticRow, $0.rowStartFrame) }
        )
        var specs = [RenderWindowSpec]()
        var startRow = 0
        while startRow < syntheticRowCount {
            let endRow = min(syntheticRowCount, startRow + safeWindowRows)
            let startFrame = min(totalFrames, max(0, rowStartFrames[startRow] ?? specs.last?.endFrame ?? 0))
            let plannedEndFrame = endRow < syntheticRowCount
                ? (rowStartFrames[endRow] ?? totalFrames)
                : totalFrames
            let endFrame = min(totalFrames, max(startFrame, plannedEndFrame))
            if startFrame < totalFrames, endFrame > startFrame {
                specs.append(RenderWindowSpec(
                    index: specs.count,
                    startRow: startRow,
                    endRowExclusive: endRow,
                    startFrame: startFrame,
                    endFrame: endFrame
                ))
            }
            startRow = endRow
        }
        if specs.isEmpty {
            return [
                RenderWindowSpec(
                    index: 0,
                    startRow: 0,
                    endRowExclusive: 0,
                    startFrame: 0,
                    endFrame: totalFrames
                )
            ]
        }
        return specs
    }

    private static func continuations(
        for window: RenderWindowSpec,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics,
        includedEventIndices: Set<Int>? = nil,
        config: MixerRenderConfig
    ) -> [PlaybackSongWindowContinuation] {
        let windowStartFrame = window.startFrame
        guard windowStartFrame > 0 else {
            return []
        }
        let latestEventIndexByChannel = latestEventIndicesByChannel(
            atOrBefore: windowStartFrame,
            plan: plan,
            scheduler: scheduler
        )
        let mappingsByEventIndex = Dictionary(uniqueKeysWithValues: plan.diagnostics.eventMappings.map { ($0.eventIndex, $0) })
        return plan.pattern.events.enumerated().compactMap { eventIndex, event in
            guard includesEvent(eventIndex, includedEventIndices: includedEventIndices) else {
                return nil
            }
            let eventStartFrame = scheduler.frame(for: event)
            guard eventStartFrame < windowStartFrame else {
                return nil
            }
            let replacementRampEvent = sameChannelLifetime.rampEvent(
                forOldEventIndex: eventIndex,
                at: windowStartFrame
            )
            if let mapping = mappingsByEventIndex[eventIndex],
               let latestEventIndex = latestEventIndexByChannel[mapping.channelIndex] {
                let isLatestChannelVoice = latestEventIndex == eventIndex
                let isReplacementRampCarry = replacementRampEvent != nil
                if !isLatestChannelVoice && !isReplacementRampCarry {
                    return nil
                }
            }
            if hasAppliedSourceStop(
                eventIndex: eventIndex,
                before: windowStartFrame,
                plan: plan
            ) || hasAppliedRetriggerCut(
                eventIndex: eventIndex,
                before: windowStartFrame,
                plan: plan
            ) {
                return nil
            }
            let gainPanState = gainPanStateAtBoundary(
                for: event,
                eventIndex: eventIndex,
                plan: plan,
                before: windowStartFrame
            )
            let replacementGainRamp = replacementRampEvent?.rampState(
                startGain: replacementRampStartGain(
                    for: event,
                    eventIndex: eventIndex,
                    plan: plan,
                    replacementFrame: replacementRampEvent?.replacementFrame
                ),
                at: windowStartFrame
            )
            let pitchUpdateEndFrame = sameChannelLifetime.firstReplacementFrame(forOldEventIndex: eventIndex)
            let stepState = stepStateAtBoundary(
                for: event,
                eventIndex: eventIndex,
                plan: plan,
                before: windowStartFrame,
                pitchUpdateEndFrame: pitchUpdateEndFrame
            )
            let carriedEvent = event
                .withGainPan(gain: gainPanState.gain, pan: gainPanState.pan)
            return continuation(
                eventIndex: eventIndex,
                event: carriedEvent,
                sourceEvent: event,
                playbackStep: stepState.playbackStep,
                pitchUpdateEndFrame: pitchUpdateEndFrame,
                eventStartFrame: eventStartFrame,
                boundaryFrame: windowStartFrame,
                plan: plan,
                gainRamp: replacementGainRamp ?? gainPanState.gainRamp,
                panRamp: gainPanState.panRamp,
                carriedTonePortamentoActive: stepState.carriedTonePortamentoActive,
                audibleOutputState: plan.xmAudibleTimeline?.state(eventIndex: eventIndex, before: windowStartFrame,
                    config: config, replacementFrame: replacementRampEvent?.replacementFrame)
            )
        }
    }

    /// Reuses the existing generic-ramp reconstruction only until release activates final output.
    static func audibleActivationSeed(for event: SyntheticTrackerEvent, eventIndex: Int,
                                      voiceStateUpdates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
                                      before frame: Int) -> MixerAudibleOutputSeed {
        let state = gainPanStateAtBoundary(for: event, eventIndex: eventIndex,
            voiceStateUpdates: voiceStateUpdates, before: frame)
        return MixerAudibleOutputSeed(amplitude: state.effectiveGain, pan: state.effectivePan)
    }

    private static func gainPanStateAtBoundary(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        before boundaryFrame: Int,
        includingUpdatesAtBoundary: Bool = false
    ) -> GainPanStateAtBoundary {
        gainPanStateAtBoundary(for: event, eventIndex: eventIndex,
            voiceStateUpdates: plan.diagnostics.voiceStateUpdates, before: boundaryFrame,
            includingUpdatesAtBoundary: includingUpdatesAtBoundary)
    }

    private static func gainPanStateAtBoundary(
        for event: SyntheticTrackerEvent, eventIndex: Int,
        voiceStateUpdates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        before boundaryFrame: Int, includingUpdatesAtBoundary: Bool = false
    ) -> GainPanStateAtBoundary {
        var gain = event.gain
        var pan = event.pan
        var gainRamp: GainPanRampSimulation?
        var panRamp: GainPanRampSimulation?
        let rampFrames = CSoftwareMixer.gainPanUpdateRampFrameCount

        for update in voiceStateUpdates {
            guard update.activeVoiceUpdated,
                  update.activeEventIndex == eventIndex,
                  update.scheduledFrame < boundaryFrame ||
                  (includingUpdatesAtBoundary && update.scheduledFrame == boundaryFrame) else {
                continue
            }
            if let target = changedGain(from: update) {
                let start = effectiveValue(
                    fallback: gain,
                    ramp: gainRamp,
                    at: update.scheduledFrame
                )
                gainRamp = GainPanRampSimulation(
                    start: start,
                    target: target,
                    scheduledFrame: update.scheduledFrame,
                    totalFrames: rampFrames
                )
                gain = target
            }
            if let target = changedPan(from: update) {
                let start = effectiveValue(
                    fallback: pan,
                    ramp: panRamp,
                    at: update.scheduledFrame
                )
                panRamp = GainPanRampSimulation(
                    start: start,
                    target: target,
                    scheduledFrame: update.scheduledFrame,
                    totalFrames: rampFrames
                )
                pan = target
            }
        }
        let effectiveGain = effectiveValue(fallback: gain, ramp: gainRamp, at: boundaryFrame)
        let effectivePan = effectiveValue(fallback: pan, ramp: panRamp, at: boundaryFrame)
        return GainPanStateAtBoundary(
            gain: gainRamp?.runtimeState(at: boundaryFrame)?.target ?? effectiveGain,
            pan: panRamp?.runtimeState(at: boundaryFrame)?.target ?? effectivePan,
            effectiveGain: effectiveGain,
            effectivePan: effectivePan,
            gainRamp: gainRamp?.runtimeState(at: boundaryFrame),
            panRamp: panRamp?.runtimeState(at: boundaryFrame)
        )
    }

    private static func stepStateAtBoundary(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        before boundaryFrame: Int,
        pitchUpdateEndFrame: Int? = nil
    ) -> StepStateAtBoundary {
        var playbackStep = plan.initialHeldPitchEventIndices.contains(eventIndex) ? 0 : event.playbackStep
        var sawPriorUpdate = false
        var hasFutureUpdate = false
        for update in sampleStepUpdates(for: eventIndex, plan: plan) {
            guard pitchUpdateEndFrame.map({ update.scheduledFrame < $0 }) ?? true else { continue }
            if update.scheduledFrame < boundaryFrame {
                playbackStep = update.playbackStepAfter
                sawPriorUpdate = true
            } else {
                hasFutureUpdate = true
            }
        }
        return StepStateAtBoundary(
            playbackStep: playbackStep,
            carriedTonePortamentoActive: sawPriorUpdate || hasFutureUpdate
        )
    }

    private static func replacementRampStartGain(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        replacementFrame: Int?
    ) -> Float {
        guard let replacementFrame else {
            return event.gain
        }
        return gainPanStateAtBoundary(
            for: event,
            eventIndex: eventIndex,
            plan: plan,
            before: replacementFrame,
            includingUpdatesAtBoundary: true
        ).effectiveGain
    }

    private static func sampleStepUpdates(
        for eventIndex: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> [PlaybackSongSyntheticTonePortamentoStepUpdate] {
        let toneUpdates = plan.diagnostics.tonePortamentoEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let slideUpdates = plan.diagnostics.portamentoSlideEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let finePortamentoUpUpdates = plan.diagnostics.finePortamentoUpEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let finePortamentoDownUpdates = plan.diagnostics.finePortamentoDownEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let extraFinePortamentoUpdates = plan.diagnostics.extraFinePortamentoEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let arpeggioUpdates = plan.diagnostics.arpeggioEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let vibratoUpdates = plan.diagnostics.vibratoEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .flatMap(\.stepUpdates)
        let automaticUpdates = plan.instrumentAutovibratoRequests.filter { $0.activeEventIndex == eventIndex }.map(\.stepUpdate)
        return (toneUpdates + slideUpdates + finePortamentoUpUpdates + finePortamentoDownUpdates + extraFinePortamentoUpdates + arpeggioUpdates + vibratoUpdates + automaticUpdates)
            .sorted { lhs, rhs in
                if lhs.scheduledFrame != rhs.scheduledFrame {
                    return lhs.scheduledFrame < rhs.scheduledFrame
                }
                return lhs.syntheticTick < rhs.syntheticTick
            }
    }

    private static func effectiveValue(
        fallback: Float,
        ramp: GainPanRampSimulation?,
        at frame: Int
    ) -> Float {
        guard let ramp else {
            return fallback
        }
        if frame - ramp.scheduledFrame >= ramp.totalFrames {
            return ramp.target
        }
        return ramp.value(at: frame)
    }

    private static func hasAppliedSourceStop(
        eventIndex: Int,
        before boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.xmEmptyRoutes.contains { $0.stoppedEventIndex == eventIndex && $0.scheduledFrame < boundaryFrame }
    }

    private static func hasAppliedSourceStop(
        eventIndex: Int,
        atOrBefore boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.xmEmptyRoutes.contains { $0.stoppedEventIndex == eventIndex && $0.scheduledFrame <= boundaryFrame }
    }

    private static func hasAppliedRetriggerCut(
        eventIndex: Int,
        before boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.diagnostics.retriggerEffects.contains { retrigger in
            guard retrigger.applied else {
                return false
            }
            return zip(retrigger.replacedEventIndices, retrigger.replacementFrames ?? retrigger.retriggerFrames).contains { replacedEventIndex, frame in
                replacedEventIndex == eventIndex && frame < boundaryFrame
            }
        }
    }

    private static func hasAppliedRetriggerCut(
        eventIndex: Int,
        atOrBefore boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.diagnostics.retriggerEffects.contains { retrigger in
            guard retrigger.applied else {
                return false
            }
            return zip(retrigger.replacedEventIndices, retrigger.replacementFrames ?? retrigger.retriggerFrames).contains { replacedEventIndex, frame in
                replacedEventIndex == eventIndex && frame <= boundaryFrame
            }
        }
    }

    private static func latestEventIndicesByChannel(
        atOrBefore boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler
    ) -> [Int: Int] {
        var latestByChannel = [Int: (frame: Int, eventIndex: Int)]()
        for mapping in plan.diagnostics.eventMappings {
            guard plan.pattern.events.indices.contains(mapping.eventIndex) else {
                continue
            }
            let frame = scheduler.frame(for: plan.pattern.events[mapping.eventIndex])
            guard frame <= boundaryFrame else {
                continue
            }
            if let existing = latestByChannel[mapping.channelIndex] {
                if frame > existing.frame ||
                    (frame == existing.frame && mapping.eventIndex > existing.eventIndex) {
                    latestByChannel[mapping.channelIndex] = (frame, mapping.eventIndex)
                }
            } else {
                latestByChannel[mapping.channelIndex] = (frame, mapping.eventIndex)
            }
        }
        return latestByChannel.mapValues(\.eventIndex)
    }

    fileprivate static func sameChannelVoiceLifetimeDiagnostics(
        for plan: PlaybackSongSyntheticPlan,
        renderedFrameCount: Int,
        windowBoundaryPruneCount: Int = 0
    ) -> PlaybackSongSameChannelVoiceLifetimeDiagnostics {
        struct EventInfo {
            let eventIndex: Int
            let event: SyntheticTrackerEvent
            let channelIndex: Int
            let frame: Int
        }
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        let mappingsByEventIndex = Dictionary(uniqueKeysWithValues: plan.diagnostics.eventMappings.map { ($0.eventIndex, $0) })
        let eventInfos = plan.pattern.events.enumerated().compactMap { eventIndex, event -> EventInfo? in
            guard let mapping = mappingsByEventIndex[eventIndex] else {
                return nil
            }
            return EventInfo(
                eventIndex: eventIndex,
                event: event,
                channelIndex: mapping.channelIndex,
                frame: scheduler.frame(for: event)
            )
        }.sorted { lhs, rhs in
            if lhs.frame != rhs.frame {
                return lhs.frame < rhs.frame
            }
            return lhs.eventIndex < rhs.eventIndex
        }

        let rampFrames = CSoftwareMixer.songReplacementRampFrameCount(sampleRate: plan.timingConfig.sampleRate)
        let renderedFrameCount = max(0, renderedFrameCount)
        var activeByChannel = [Int: [SameChannelActiveVoice]]()
        var maxVoicesByChannel = [Int: Int]()
        var loadedByChannel = [Int: Int]()
        var replacementEvents = [PlaybackSongSameChannelReplacementEvent]()

        for info in eventInfos {
            loadedByChannel[info.channelIndex, default: 0] += 1
            var activeVoices = activeByChannel[info.channelIndex] ?? []
            activeVoices = activeVoices.filter { voice in
                sameChannelVoiceIsActive(
                    voice,
                    at: info.frame,
                    plan: plan,
                    scheduler: scheduler
                )
            }
            for index in activeVoices.indices {
                // Each generation owns one immutable retirement interval, even during rapid replacement.
                guard activeVoices[index].rampCompletionFrame == nil else { continue }
                let oldEventIndex = activeVoices[index].eventIndex
                let completionFrame = info.frame + rampFrames
                replacementEvents.append(PlaybackSongSameChannelReplacementEvent(
                    sourceChannelIndex: info.channelIndex,
                    oldEventIndex: oldEventIndex,
                    newEventIndex: info.eventIndex,
                    replacementFrame: info.frame,
                    completionFrame: completionFrame,
                    oldVoiceKeptReason: PlaybackSongSameChannelVoiceLifetimeDiagnostics.oldVoiceKeptReasonReplacementRamp,
                    oldVoiceRampDurationFrames: rampFrames
                ))
                activeVoices[index].rampCompletionFrame = completionFrame
                // The pre-replacement physical pitch stream remains closed for this generation (R02).
                if activeVoices[index].pitchUpdateEndFrame == nil {
                    activeVoices[index].pitchUpdateEndFrame = info.frame
                }
            }
            activeVoices.append(SameChannelActiveVoice(eventIndex: info.eventIndex, rampCompletionFrame: nil))
            activeByChannel[info.channelIndex] = activeVoices
            maxVoicesByChannel[info.channelIndex] = max(
                maxVoicesByChannel[info.channelIndex] ?? 0,
                activeVoices.count
            )
        }

        let activeAtEndByChannel = activeByChannel.mapValues { voices in
            voices.filter { voice in
                sameChannelVoiceIsActive(
                    voice,
                    at: renderedFrameCount,
                    plan: plan,
                    scheduler: scheduler
                )
            }.count
        }.filter { $0.value > 0 }
        let replacementCompletionCount = replacementEvents.filter {
            $0.completionFrame <= renderedFrameCount
        }.count
        let overlapFrames = replacementEvents.map { replacement in
            max(0, min(renderedFrameCount, replacement.completionFrame) - replacement.replacementFrame)
        }.reduce(0, +)
        let keptReasonCounts = replacementEvents.reduce(into: [String: Int]()) { result, event in
            result[event.oldVoiceKeptReason, default: 0] += 1
        }
        let replacementEventsByOldEventIndex = replacementEvents.reduce(
            into: [Int: [PlaybackSongSameChannelReplacementEvent]]()
        ) { result, event in
            result[event.oldEventIndex, default: []].append(event)
        }
        return PlaybackSongSameChannelVoiceLifetimeDiagnostics(
            replacementRampFrameCount: rampFrames,
            activeVoicesBySourceChannel: activeAtEndByChannel,
            loadedVoicesBySourceChannel: loadedByChannel.filter { $0.value > 0 },
            sameChannelActiveVoiceCount: maxVoicesByChannel.values.max() ?? 0,
            sameChannelReplacementStartCount: replacementEvents.count,
            sameChannelReplacementCompletionCount: replacementCompletionCount,
            sameChannelVoiceOverlapFrames: overlapFrames,
            maxVoicesPerSourceChannel: maxVoicesByChannel.filter { $0.value > 0 },
            oldVoiceKeptReasonCounts: keptReasonCounts,
            oldVoiceRampDurationFrames: rampFrames,
            windowBoundaryPruneCount: max(0, windowBoundaryPruneCount),
            replacementEvents: replacementEvents,
            replacementEventsByOldEventIndex: replacementEventsByOldEventIndex
        )
    }

    /// Plan-local scalar projection of the existing pitch histories and inclusive source cuts.
    /// Source indices are generations, never reusable channel/voice slots. No PCM is retained.
    struct PitchSourceHistory {
        struct Segment {
            let frame: Int
            let position: Double
            let step: Double
        }
        private struct Entry {
            let lower: Int
            let upper: Int
            let cutFrame: Int?
        }
        final class Work {
            var lookupCount = 0
            var entriesVisited = 0
        }
        private let entries: [Entry]
        private let segments: [Segment]
        let diagnosticsVisited: Int
        let work: Work?
        var sourceCount: Int { entries.count }
        var recordCount: Int { segments.count }
        var logicalBytes: Int {
            entries.count * MemoryLayout<Entry>.stride + segments.count * MemoryLayout<Segment>.stride
        }
        var sourceStride: Int { MemoryLayout<Entry>.stride }
        var recordStride: Int { MemoryLayout<Segment>.stride }

        init(plan: PlaybackSongSyntheticPlan, work: Work? = nil) {
            self.work = work
            typealias Step = PlaybackSongSyntheticTonePortamentoStepUpdate
            struct Point {
                let frame: Int
                let tick: Int
                let step: Double
            }
            var bySource = Array(repeating: [Point](), count: plan.pattern.events.count)
            var visited = 0, stepCount = 0
            func append(_ steps: [Step], source: Int?, applied: Bool) {
                visited += 1
                guard applied, let source, bySource.indices.contains(source) else { return }
                for step in steps {
                    bySource[source].append(.init(frame: step.scheduledFrame, tick: step.syntheticTick, step: step.playbackStepAfter))
                }
                stepCount += steps.count
            }
            // Match the scan's family order; the stable sort keeps equal-frame/tick writers exact.
            let d = plan.diagnostics
            for x in d.tonePortamentoEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for x in d.portamentoSlideEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for x in d.finePortamentoUpEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for x in d.finePortamentoDownEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for x in d.extraFinePortamentoEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for x in d.arpeggioEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for x in d.vibratoEffects { append(x.stepUpdates, source: x.activeEventIndex, applied: x.applied) }
            for request in plan.instrumentAutovibratoRequests {
                guard bySource.indices.contains(request.activeEventIndex) else { continue }
                bySource[request.activeEventIndex].append(.init(frame: request.scheduledFrame,
                    tick: request.syntheticTick, step: request.playbackStep))
                stepCount += 1
            }
            diagnosticsVisited = visited
            var cuts = [Int: Int]()
            func cut(_ source: Int?, at frame: Int) {
                guard let source else { return }
                cuts[source] = min(cuts[source] ?? frame, frame)
            }
            for route in plan.xmEmptyRoutes { cut(route.stoppedEventIndex, at: route.scheduledFrame) }
            for x in d.retriggerEffects where x.applied {
                for (source, frame) in zip(x.replacedEventIndices, x.replacementFrames ?? x.retriggerFrames) { cut(source, at: frame) }
            }
            let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
            var entries = [Entry](), segments = [Segment]()
            entries.reserveCapacity(bySource.count)
            segments.reserveCapacity(bySource.count + stepCount)
            for (source, event) in plan.pattern.events.enumerated() {
                bySource[source].sort {
                    $0.frame == $1.frame ? $0.tick < $1.tick : $0.frame < $1.frame
                }
                let start = scheduler.frame(for: event), lower = segments.count
                var cursor = start, position = Double(max(0, event.initialSourceFrame))
                var step = plan.initialHeldPitchEventIndices.contains(source) ? 0 : event.playbackStep
                segments.append(.init(frame: start, position: position, step: step))
                for update in bySource[source] where update.frame > start {
                    // Preserve the scan's sequential Double operations, including equal-frame writes.
                    position += Double(max(0, update.frame - cursor)) * step
                    cursor = update.frame
                    step = update.step
                    segments.append(.init(frame: cursor, position: position, step: step))
                }
                entries.append(.init(lower: lower, upper: segments.count, cutFrame: cuts[source]))
            }
            self.entries = entries
            self.segments = segments
        }

        func cutFrame(for source: Int) -> Int? {
            entries.indices.contains(source) ? entries[source].cutFrame : nil
        }

        /// Strict-before lookup matches boundary events queued at local frame zero.
        func advancedPosition(for source: Int, at frame: Int) -> Double? {
            guard entries.indices.contains(source) else { return nil }
            work?.lookupCount += 1
            let entry = entries[source]
            var lower = entry.lower + 1, upper = entry.upper
            while lower < upper {
                work?.entriesVisited += 1
                let middle = lower + (upper - lower) / 2
                if segments[middle].frame < frame { lower = middle + 1 } else { upper = middle }
            }
            let segment = segments[lower - 1]
            return segment.position + Double(max(0, frame - segment.frame)) * segment.step
        }
    }

    /// Reuses window/lifetime reconstruction to check a planned source before a local publication.
    static func hasActiveSource(eventIndex: Int, at frame: Int, plan: PlaybackSongSyntheticPlan,
                                pitchHistory: PitchSourceHistory? = nil) -> Bool {
        sameChannelVoiceIsActive(.init(eventIndex: eventIndex, rampCompletionFrame: nil), at: frame,
            plan: plan, scheduler: SyntheticTrackerScheduler(config: plan.timingConfig), pitchHistory: pitchHistory)
    }

    private static func sameChannelVoiceIsActive(
        _ voice: SameChannelActiveVoice,
        at frame: Int,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler,
        pitchHistory: PitchSourceHistory? = nil
    ) -> Bool {
        if let rampCompletionFrame = voice.rampCompletionFrame,
           frame >= rampCompletionFrame {
            return false
        }
        guard plan.pattern.events.indices.contains(voice.eventIndex) else {
            return false
        }
        let event = plan.pattern.events[voice.eventIndex]
        let eventStartFrame = scheduler.frame(for: event)
        guard eventStartFrame <= frame else {
            return false
        }
        if let pitchHistory {
            if let cut = pitchHistory.cutFrame(for: voice.eventIndex), cut <= frame { return false }
        } else if hasAppliedSourceStop(
            eventIndex: voice.eventIndex,
            atOrBefore: frame,
            plan: plan
        ) || hasAppliedRetriggerCut(
            eventIndex: voice.eventIndex,
            atOrBefore: frame,
            plan: plan
        ) {
            return false
        }
        guard sourcePositionState(
            for: event,
            eventIndex: voice.eventIndex,
            plan: plan,
            eventStartFrame: eventStartFrame,
            boundaryFrame: frame,
            pitchHistory: pitchHistory,
            pitchUpdateEndFrame: voice.pitchUpdateEndFrame
        ) != nil else {
            return false
        }
        if plan.xmEnvelopeTimeline?.updatesByEvent[voice.eventIndex] != nil { return true }
        if let state = reconstructedPlaybackState(for: event, eventIndex: voice.eventIndex, plan: plan,
                                                  eventStartFrame: eventStartFrame, boundaryFrame: frame,
                                                  pitchHistory: pitchHistory, pitchUpdateEndFrame: voice.pitchUpdateEndFrame) {
            return state.fadeout > 0
        }
        let releasedFrames = releasedFrameCount(
            boundaryFrame: frame,
            keyOffFrame: event.keyOffFrame
        )
        return fadeoutValue(
            releasedFrames: releasedFrames,
            decrementPerFrame: event.fadeoutFrameDecrement
        ) > 0
    }

    private struct ReconstructedPlaybackState {
        var volumePosition = 0
        var panPosition = 0
        var keyOn = true
        var fadeout: Float = 1
        var decrement: Float = 0
    }

    /// Folds explicit transitions before the boundary. Boundary events remain queued at local frame zero.
    /// The legacy path is retained when no new transitions exist, preserving existing render output.
    private static func reconstructedPlaybackState(
        for event: SyntheticTrackerEvent, eventIndex: Int, plan: PlaybackSongSyntheticPlan,
        eventStartFrame: Int, boundaryFrame: Int, pitchHistory: PitchSourceHistory? = nil,
        pitchUpdateEndFrame: Int? = nil
    ) -> ReconstructedPlaybackState? {
        let changes = carriedPlaybackStateEvents(for: plan).filter { $0.activeEventIndex == eventIndex }
        guard !changes.isEmpty else { return nil }
        var timeline: [(frame: Int, order: Int, change: MixerPlaybackStateChange?, position: Int?)] = changes.enumerated().map {
            ($0.element.scheduledFrame, $0.offset, $0.element.change, nil)
        }
        for update in envelopePositionUpdates(for: eventIndex, plan: plan) {
            timeline.append((update.scheduledFrame, Int.max - 1, nil, update.appliedPositionFrame))
        }
        // The legacy trigger-owned key-off runs after queued state updates at its frame in C.
        if let frame = event.keyOffFrame {
            timeline.append((frame, Int.max, .keyOff(fadeoutDecrement: event.fadeoutFrameDecrement), nil))
        }
        timeline = timeline.filter { $0.frame >= eventStartFrame && $0.frame < boundaryFrame }.sorted {
            $0.frame == $1.frame ? $0.order < $1.order : $0.frame < $1.frame
        }
        timeline.append((boundaryFrame, 0, nil, nil))
        var state = ReconstructedPlaybackState(decrement: event.fadeoutFrameDecrement)
        var cursor = eventStartFrame
        for item in timeline {
            let frames = item.frame - cursor
            if let envelope = event.volumeEnvelope {
                state.volumePosition = advanceEnvelopePosition(state.volumePosition, frames: frames, keyOn: state.keyOn, envelope: envelope)
            }
            if let envelope = event.panEnvelope {
                state.panPosition = advanceEnvelopePosition(state.panPosition, frames: frames, keyOn: state.keyOn, envelope: envelope)
            }
            if !state.keyOn, state.decrement > 0 {
                // Match C's repeated Float32 subtraction, including rounding at completion.
                for _ in 0..<frames {
                    state.fadeout = max(0, state.fadeout - state.decrement)
                    if state.fadeout == 0 { break }
                }
            }
            cursor = item.frame
            guard state.fadeout > 0, sourcePositionState(for: event, eventIndex: eventIndex, plan: plan,
                eventStartFrame: eventStartFrame, boundaryFrame: item.frame, pitchHistory: pitchHistory,
                pitchUpdateEndFrame: pitchUpdateEndFrame) != nil else {
                state.fadeout = 0
                return state
            }
            switch item.change {
            case let .reset(reset):
                if reset.volumeEnvelope, event.volumeEnvelope != nil { state.volumePosition = 0 }
                if reset.panEnvelope, event.panEnvelope != nil { state.panPosition = 0 }
                if reset.keyOn { state.keyOn = true }
                if reset.fadeout { state.fadeout = 1 }
            case let .keyOff(decrement):
                state.keyOn = false
                // Trigger-owned release only flips the key; explicit release events own rate writes.
                if item.order != Int.max { state.decrement = min(1, decrement) }
            case nil: break
            }
            if let position = item.position { state.volumePosition = clampedEnvelopePosition(position) }
        }
        return state
    }

    private static func continuation(
        eventIndex: Int,
        event: SyntheticTrackerEvent,
        sourceEvent: SyntheticTrackerEvent,
        playbackStep: Double,
        pitchUpdateEndFrame: Int? = nil,
        eventStartFrame: Int,
        boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan,
        gainRamp: CSoftwareMixerValueRampRuntimeState?,
        panRamp: CSoftwareMixerValueRampRuntimeState?,
        carriedTonePortamentoActive: Bool,
        audibleOutputState: MixerAudibleOutputState?
    ) -> PlaybackSongWindowContinuation? {
        let elapsedFrames = max(0, boundaryFrame - eventStartFrame)
        guard elapsedFrames > 0,
              let sourceState = sourcePositionState(
                  for: sourceEvent,
                  eventIndex: eventIndex,
                  plan: plan,
                  eventStartFrame: eventStartFrame,
                  boundaryFrame: boundaryFrame,
                  pitchUpdateEndFrame: pitchUpdateEndFrame
              ) else {
            return nil
        }
        let keyOffFrame = event.keyOffFrame
        let semanticState = plan.xmEnvelopeTimeline?.state(eventIndex: eventIndex, before: boundaryFrame)
        let resetState = semanticState == nil ? reconstructedPlaybackState(for: sourceEvent, eventIndex: eventIndex, plan: plan,
                                                    eventStartFrame: eventStartFrame, boundaryFrame: boundaryFrame,
                                                    pitchUpdateEndFrame: pitchUpdateEndFrame) : nil
        let keyOn = semanticState?.keyOn ?? resetState?.keyOn ?? (keyOffFrame.map { boundaryFrame <= $0 } ?? true)
        let keyedFrames = keyedFrameCount(
            elapsedFrames: elapsedFrames,
            eventStartFrame: eventStartFrame,
            keyOffFrame: keyOffFrame
        )
        let releasedFrames = releasedFrameCount(
            boundaryFrame: boundaryFrame,
            keyOffFrame: keyOffFrame
        )
        let fadeoutValue = semanticState?.fadeoutValue ?? resetState?.fadeout ?? fadeoutValue(
            releasedFrames: releasedFrames,
            decrementPerFrame: event.fadeoutFrameDecrement
        )
        guard semanticState != nil || fadeoutValue > 0 else {
            return nil
        }
        let volumeEnvelopePosition = semanticState != nil ? 0 : resetState?.volumePosition ?? volumeEnvelopePosition(
            for: event.volumeEnvelope,
            eventIndex: eventIndex,
            plan: plan,
            eventStartFrame: eventStartFrame,
            boundaryFrame: boundaryFrame,
            keyOffFrame: keyOffFrame
        )
        let panEnvelopePosition = semanticState != nil ? 0 : resetState?.panPosition ?? envelopePosition(
            for: event.panEnvelope,
            keyedFrames: keyedFrames,
            releasedFrames: releasedFrames
        )
        let localKeyOffFrame: Int?
        if let keyOffFrame, keyOffFrame >= boundaryFrame, semanticState == nil {
            localKeyOffFrame = keyOffFrame - boundaryFrame
        } else {
            localKeyOffFrame = nil
        }
        return PlaybackSongWindowContinuation(
            eventIndex: eventIndex,
            event: event,
            playbackStep: playbackStep,
            runtimeState: CSoftwareMixerVoiceRuntimeState(
                samplePosition: sourceState.samplePosition,
                pingPongDirection: sourceState.pingPongDirection,
                volumeEnvelopePositionFrame: volumeEnvelopePosition,
                panEnvelopePositionFrame: panEnvelopePosition,
                keyOn: keyOn,
                fadeoutValue: fadeoutValue,
                gainRamp: audibleOutputState == nil || gainRamp?.deactivateAfterRamp == true ? gainRamp : nil,
                panRamp: audibleOutputState == nil ? panRamp : nil,
                sourceOnsetElapsedFrames: gainRamp?.songRetirement == true
                    ? min(elapsedFrames, max(0, (pitchUpdateEndFrame ?? boundaryFrame) - eventStartFrame)) : elapsedFrames
            ),
            keyOffFrame: localKeyOffFrame,
            carriedTonePortamentoActive: carriedTonePortamentoActive,
            fadeoutDecrement: resetState?.decrement ?? event.fadeoutFrameDecrement,
            envelopeSemanticState: semanticState,
            audibleOutputState: audibleOutputState
        )
    }

    /// Restores an existing voice at an offline window boundary, including an explicit hold.
    static func scheduleContinuation(
        _ continuation: PlaybackSongWindowContinuation,
        on mixer: CSoftwareMixer
    ) -> CSoftwareMixerScheduledVoiceResult {
        let event = continuation.event
        let result = mixer.addScheduledVoiceWithResult(
            sample: event.sample,
            scheduledStartFrame: 0,
            gain: event.gain,
            pan: event.pan,
            playbackStep: continuation.playbackStep == 0 ? event.playbackStep : continuation.playbackStep,
            loop: event.loop,
            initialSourceFrame: Int(continuation.runtimeState.samplePosition.rounded(.down)),
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: continuation.keyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
        if let voiceIndex = result.voiceIndex {
            if continuation.playbackStep == 0 {
                // This is imported physical state, not a later write to a retiring generation.
                precondition(mixer.setContinuationPlaybackStep(0, forVoiceAt: voiceIndex))
            }
            mixer.setFadeoutDecrement(continuation.fadeoutDecrement ?? event.fadeoutFrameDecrement, forVoiceAt: voiceIndex)
            if let semantic = continuation.envelopeSemanticState {
                mixer.setEnvelopeSemanticState(semantic, forVoiceAt: voiceIndex)
            }
            if let output = continuation.audibleOutputState {
                mixer.setAudibleOutputState(output, forVoiceAt: voiceIndex)
            }
            mixer.setRuntimeState(continuation.runtimeState, forVoiceAt: voiceIndex)
        }
        return result
    }

    private static func sourcePositionState(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        eventStartFrame: Int,
        boundaryFrame: Int,
        pitchHistory: PitchSourceHistory? = nil,
        pitchUpdateEndFrame: Int? = nil
    ) -> SourcePositionState? {
        let sampleFrameCount = event.sample.frameCount
        guard sampleFrameCount > 0,
              event.playbackStep.isFinite,
              event.playbackStep > 0 else {
            return nil
        }
        let sanitizedLoop = event.loop.sanitized(sampleFrameCount: sampleFrameCount)
        let initialPosition = Double(max(0, event.initialSourceFrame))
        guard initialPosition < Double(sampleFrameCount) else {
            return nil
        }
        var advancedPosition = initialPosition
        var cursorFrame = eventStartFrame
        var currentStep = plan.initialHeldPitchEventIndices.contains(eventIndex) ? 0 : event.playbackStep
        if let pitchHistory, pitchUpdateEndFrame == nil {
            guard let position = pitchHistory.advancedPosition(for: eventIndex, at: boundaryFrame) else { return nil }
            advancedPosition = position
        } else {
            for update in sampleStepUpdates(for: eventIndex, plan: plan) {
                guard update.scheduledFrame > eventStartFrame,
                      update.scheduledFrame < boundaryFrame,
                      pitchUpdateEndFrame.map({ update.scheduledFrame < $0 }) ?? true else { continue }
                let segmentFrames = max(0, update.scheduledFrame - cursorFrame)
                advancedPosition += Double(segmentFrames) * currentStep
                cursorFrame = update.scheduledFrame
                currentStep = update.playbackStepAfter
            }
            // Retirement freezes the last executed step, while its cursor keeps advancing.
            advancedPosition += Double(max(0, boundaryFrame - cursorFrame)) * currentStep
        }
        guard advancedPosition.isFinite,
              advancedPosition >= 0,
              advancedPosition <= Double(UInt32.max) else {
            return nil
        }

        switch sanitizedLoop.mode {
        case .none:
            guard advancedPosition < Double(sampleFrameCount) else {
                return nil
            }
            return SourcePositionState(samplePosition: advancedPosition, pingPongDirection: 1)
        case .forward:
            let start = Double(sanitizedLoop.startFrame)
            let end = Double(sanitizedLoop.endFrame)
            let length = max(0, end - start)
            guard length > 0 else {
                return nil
            }
            if advancedPosition < end {
                return SourcePositionState(samplePosition: advancedPosition, pingPongDirection: 1)
            }
            let overflow = advancedPosition - end
            return SourcePositionState(
                samplePosition: start + overflow.truncatingRemainder(dividingBy: length),
                pingPongDirection: 1
            )
        case .pingPong:
            return pingPongSourcePositionState(advancedPosition: advancedPosition, loop: sanitizedLoop)
        }
    }

    private static func pingPongSourcePositionState(
        advancedPosition: Double,
        loop: MixerSampleLoop
    ) -> SourcePositionState? {
        let firstLoopFrame = Double(loop.startFrame)
        let lastLoopFrame = Double(loop.endFrame - 1)
        let span = lastLoopFrame - firstLoopFrame
        guard span > 0 else {
            return nil
        }
        if advancedPosition <= lastLoopFrame {
            return SourcePositionState(samplePosition: advancedPosition, pingPongDirection: 1)
        }
        let period = span * 2.0
        guard period > 0 else {
            return nil
        }
        let overshoot = (advancedPosition - lastLoopFrame).truncatingRemainder(dividingBy: period)
        if overshoot == 0 {
            return SourcePositionState(samplePosition: lastLoopFrame, pingPongDirection: 1)
        }
        if overshoot <= span {
            return SourcePositionState(samplePosition: lastLoopFrame - overshoot, pingPongDirection: -1)
        }
        return SourcePositionState(
            samplePosition: firstLoopFrame + (overshoot - span),
            pingPongDirection: 1
        )
    }

    private static func keyedFrameCount(
        elapsedFrames: Int,
        eventStartFrame: Int,
        keyOffFrame: Int?
    ) -> Int {
        guard let keyOffFrame else {
            return elapsedFrames
        }
        return min(elapsedFrames, max(0, keyOffFrame - eventStartFrame))
    }

    private static func releasedFrameCount(
        boundaryFrame: Int,
        keyOffFrame: Int?
    ) -> Int {
        guard let keyOffFrame,
              boundaryFrame > keyOffFrame else {
            return 0
        }
        return boundaryFrame - keyOffFrame
    }

    private static func fadeoutValue(
        releasedFrames: Int,
        decrementPerFrame: Float
    ) -> Float {
        guard releasedFrames > 0,
              decrementPerFrame.isFinite,
              decrementPerFrame > 0 else {
            return 1
        }
        return max(0, 1 - (Float(releasedFrames) * decrementPerFrame))
    }

    private static func volumeEnvelopePosition(
        for envelope: MixerEnvelope?,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        eventStartFrame: Int,
        boundaryFrame: Int,
        keyOffFrame: Int?
    ) -> Int {
        guard let envelope,
              !envelope.points.isEmpty,
              boundaryFrame > eventStartFrame else {
            return 0
        }
        var position = 0
        var cursorFrame = eventStartFrame
        for update in envelopePositionUpdates(for: eventIndex, plan: plan) {
            guard update.scheduledFrame >= eventStartFrame,
                  update.scheduledFrame < boundaryFrame,
                  let appliedPositionFrame = update.appliedPositionFrame else {
                continue
            }
            position = advanceEnvelopePosition(
                position,
                fromFrame: cursorFrame,
                toFrame: update.scheduledFrame,
                keyOffFrame: keyOffFrame,
                envelope: envelope
            )
            position = clampedEnvelopePosition(appliedPositionFrame)
            cursorFrame = update.scheduledFrame
        }
        return advanceEnvelopePosition(
            position,
            fromFrame: cursorFrame,
            toFrame: boundaryFrame,
            keyOffFrame: keyOffFrame,
            envelope: envelope
        )
    }

    private static func envelopePositionUpdates(
        for eventIndex: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> [PlaybackSongSyntheticEnvelopePositionDiagnostic] {
        plan.diagnostics.envelopePositionEffects
            .filter { $0.applied && $0.activeEventIndex == eventIndex }
            .sorted { lhs, rhs in
                if lhs.scheduledFrame != rhs.scheduledFrame {
                    return lhs.scheduledFrame < rhs.scheduledFrame
                }
                if lhs.syntheticRow != rhs.syntheticRow {
                    return lhs.syntheticRow < rhs.syntheticRow
                }
                return lhs.channelIndex < rhs.channelIndex
            }
    }

    private static func advanceEnvelopePosition(
        _ position: Int,
        fromFrame: Int,
        toFrame: Int,
        keyOffFrame: Int?,
        envelope: MixerEnvelope
    ) -> Int {
        guard toFrame > fromFrame else {
            return position
        }
        if let keyOffFrame,
           fromFrame < keyOffFrame,
           toFrame > keyOffFrame {
            let keyedPosition = advanceEnvelopePosition(
                position,
                frames: keyOffFrame - fromFrame,
                keyOn: true,
                envelope: envelope
            )
            return advanceEnvelopePosition(
                keyedPosition,
                frames: toFrame - keyOffFrame,
                keyOn: false,
                envelope: envelope
            )
        }
        let keyOn = keyOffFrame.map { fromFrame < $0 } ?? true
        return advanceEnvelopePosition(
            position,
            frames: toFrame - fromFrame,
            keyOn: keyOn,
            envelope: envelope
        )
    }

    private static func envelopePosition(
        for envelope: MixerEnvelope?,
        keyedFrames: Int,
        releasedFrames: Int
    ) -> Int {
        guard let envelope,
              !envelope.points.isEmpty else {
            return 0
        }
        var position = 0
        position = advanceEnvelopePosition(position, frames: keyedFrames, keyOn: true, envelope: envelope)
        position = advanceEnvelopePosition(position, frames: releasedFrames, keyOn: false, envelope: envelope)
        return position
    }

    private static func advanceEnvelopePosition(
        _ position: Int,
        frames: Int,
        keyOn: Bool,
        envelope: MixerEnvelope
    ) -> Int {
        guard frames > 0 else {
            return position
        }
        if !keyOn {
            return clampedEnvelopePosition(position + frames)
        }
        if let sustainFrame = envelope.sustainFrame,
           position >= sustainFrame {
            return sustainFrame
        }

        let loopStart = envelope.loopStartFrame
        let loopEnd = envelope.loopEndFrame
        if let sustainFrame = envelope.sustainFrame,
           canReachSustainBeforeLoop(
               position: position,
               frames: frames,
               sustainFrame: sustainFrame,
               loopEndFrame: loopEnd
           ) {
            return sustainFrame
        }
        guard let loopStart,
              let loopEnd,
              loopEnd >= loopStart else {
            return clampedEnvelopePosition(position + frames)
        }

        let target = position + frames
        guard target > loopEnd else {
            return clampedEnvelopePosition(target)
        }
        let loopLength = loopEnd - loopStart + 1
        guard loopLength > 0 else {
            return clampedEnvelopePosition(target)
        }
        return loopStart + ((target - loopEnd - 1) % loopLength)
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

    private static func knownUnsupportedCarryoverReasons(
        for plan: PlaybackSongSyntheticPlan
    ) -> [String] {
        var reasons = [String]()
        if plan.diagnostics.deferredCellFields.contains(where: { $0.field == .effect }) {
            reasons.append("deferred_effect_commands_not_interpreted_for_window_carryover")
        }
        if plan.diagnostics.deferredCellFields.contains(where: { $0.field == .volumeColumn }) {
            reasons.append("deferred_volume_column_commands_not_interpreted_for_window_carryover")
        }
        if plan.diagnostics.traversalHazardSummary.likelyIgnoresStructureChangingBehavior {
            reasons.append("deferred_pattern_traversal_effects_not_applied")
        }
        return reasons
    }

    private static func windowScheduledEvent(
        eventIndex: Int,
        event: SyntheticTrackerEvent,
        scheduledFrame: Int,
        mappingsByEventIndex: [Int: PlaybackSongSyntheticEventMapping]
    ) -> PlaybackSongWindowScheduledEvent {
        let mapping = mappingsByEventIndex[eventIndex]
        return PlaybackSongWindowScheduledEvent(
            eventIndex: eventIndex,
            source: mapping?.source,
            channelIndex: mapping?.channelIndex,
            scheduledFrame: scheduledFrame
        )
    }

    private static func windowContinuationCandidate(
        _ continuation: PlaybackSongWindowContinuation,
        scheduler: SyntheticTrackerScheduler,
        mappingsByEventIndex: [Int: PlaybackSongSyntheticEventMapping]
    ) -> PlaybackSongWindowContinuationCandidate {
        let mapping = mappingsByEventIndex[continuation.eventIndex]
        return PlaybackSongWindowContinuationCandidate(
            eventIndex: continuation.eventIndex,
            source: mapping?.source,
            channelIndex: mapping?.channelIndex,
            scheduledFrame: scheduler.frame(for: continuation.event)
        )
    }

    private static func windowIndex(
        containingFrame frame: Int,
        in specs: [RenderWindowSpec]
    ) -> Int? {
        var lowerBound = 0
        var upperBound = specs.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + ((upperBound - lowerBound) / 2)
            let spec = specs[midpoint]
            if frame < spec.startFrame {
                upperBound = midpoint
            } else if frame >= spec.endFrame {
                lowerBound = midpoint + 1
            } else {
                return spec.index
            }
        }
        return nil
    }

    private static func windowSchedulingUpdateCandidates(
        for plan: PlaybackSongSyntheticPlan,
        sameChannelLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics,
        includedEventIndices: Set<Int>?,
        windowStartFrame: Int? = nil,
        windowEndFrame: Int? = nil
    ) -> [PlaybackSongWindowSchedulingUpdateCandidate] {
        var updates = [PlaybackSongWindowSchedulingUpdateCandidate]()
        func append(
            _ kind: PlaybackSongWindowSchedulingUpdateKind,
            diagnosticIndex: Int,
            childIndex: Int? = nil,
            eventIndex: Int,
            frame: Int
        ) {
            guard includesEvent(eventIndex, includedEventIndices: includedEventIndices) else {
                return
            }
            if let windowStartFrame, frame < windowStartFrame {
                return
            }
            if let windowEndFrame, frame >= windowEndFrame {
                return
            }
            updates.append(PlaybackSongWindowSchedulingUpdateCandidate(
                kind: kind,
                sourceDiagnosticIndex: diagnosticIndex,
                childUpdateIndex: childIndex,
                activeEventIndex: eventIndex,
                scheduledFrame: frame
            ))
        }
        func appendStepDiagnostics<Diagnostic>(
            _ diagnostics: [Diagnostic],
            kind: PlaybackSongWindowSchedulingUpdateKind,
            isApplied: (Diagnostic) -> Bool,
            eventIndex: (Diagnostic) -> Int?,
            stepUpdates: (Diagnostic) -> [PlaybackSongSyntheticTonePortamentoStepUpdate]
        ) {
            for (diagnosticIndex, diagnostic) in diagnostics.enumerated() where isApplied(diagnostic) {
                guard let activeEventIndex = eventIndex(diagnostic) else {
                    continue
                }
                for (childIndex, update) in stepUpdates(diagnostic).enumerated() {
                    append(
                        kind,
                        diagnosticIndex: diagnosticIndex,
                        childIndex: childIndex,
                        eventIndex: activeEventIndex,
                        frame: update.scheduledFrame
                    )
                }
            }
        }

        for (diagnosticIndex, diagnostic) in plan.diagnostics.envelopePositionEffects.enumerated() {
            guard diagnostic.applied,
                  let activeEventIndex = diagnostic.activeEventIndex,
                  diagnostic.appliedPositionFrame != nil else {
                continue
            }
            append(.envelopePosition, diagnosticIndex: diagnosticIndex, eventIndex: activeEventIndex, frame: diagnostic.scheduledFrame)
        }
        for (diagnosticIndex, diagnostic) in plan.diagnostics.voiceStateUpdates.enumerated() where diagnostic.activeVoiceUpdated {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            guard changedGain(from: diagnostic) != nil || changedPan(from: diagnostic) != nil else {
                continue
            }
            append(.voiceGainPan, diagnosticIndex: diagnosticIndex, eventIndex: activeEventIndex, frame: diagnostic.scheduledFrame)
        }
        appendStepDiagnostics(plan.diagnostics.tonePortamentoEffects, kind: .tonePortamentoStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        appendStepDiagnostics(plan.diagnostics.portamentoSlideEffects, kind: .portamentoSlideStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        appendStepDiagnostics(plan.diagnostics.finePortamentoUpEffects, kind: .finePortamentoUpStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        appendStepDiagnostics(plan.diagnostics.finePortamentoDownEffects, kind: .finePortamentoDownStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        appendStepDiagnostics(plan.diagnostics.extraFinePortamentoEffects, kind: .extraFinePortamentoStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        appendStepDiagnostics(plan.diagnostics.arpeggioEffects, kind: .arpeggioStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        appendStepDiagnostics(plan.diagnostics.vibratoEffects, kind: .vibratoStep, isApplied: { $0.applied }, eventIndex: { $0.activeEventIndex }, stepUpdates: { $0.stepUpdates })
        for (index, request) in plan.instrumentAutovibratoRequests.enumerated() {
            append(.instrumentAutoPitchStep, diagnosticIndex: index,
                eventIndex: request.activeEventIndex, frame: request.scheduledFrame)
        }
        for (diagnosticIndex, diagnostic) in plan.diagnostics.noteCutEffects.enumerated() where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  let scheduledFrame = diagnostic.scheduledFrame else {
                continue
            }
            append(.noteCut, diagnosticIndex: diagnosticIndex, eventIndex: activeEventIndex, frame: scheduledFrame)
        }
        for (diagnosticIndex, diagnostic) in plan.diagnostics.retriggerEffects.enumerated() where diagnostic.applied {
            for (childIndex, pair) in zip(diagnostic.replacedEventIndices, diagnostic.replacementFrames ?? diagnostic.retriggerFrames).enumerated() {
                let (activeEventIndex, scheduledFrame) = pair
                append(.retriggerCut, diagnosticIndex: diagnosticIndex, childIndex: childIndex, eventIndex: activeEventIndex, frame: scheduledFrame)
            }
        }
        for (replacementIndex, replacement) in sameChannelLifetime.replacementEvents.enumerated() {
            append(.sameChannelReplacementRamp, diagnosticIndex: replacementIndex, eventIndex: replacement.oldEventIndex, frame: replacement.replacementFrame)
        }
        return updates
    }

    private static func eventPairs(
        in window: RenderWindowSpec,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler
    ) -> [(offset: Int, element: SyntheticTrackerEvent)] {
        plan.pattern.events.enumerated().filter { _, event in
            let startFrame = scheduler.frame(for: event)
            return event.row >= window.startRow &&
                event.row < window.endRowExclusive &&
                startFrame >= window.startFrame &&
                startFrame < window.endFrame
        }
    }

    fileprivate static func localEvent(
        from event: SyntheticTrackerEvent,
        windowStartFrame: Int,
        scheduler: SyntheticTrackerScheduler
    ) -> SyntheticTrackerEvent {
        let absoluteStartFrame = scheduler.frame(for: event)
        let localStartFrame = max(0, absoluteStartFrame - windowStartFrame)
        let localKeyOffFrame = event.keyOffFrame.map { max(localStartFrame, $0 - windowStartFrame) }
        return SyntheticTrackerEvent(
            row: event.row,
            tick: event.tick,
            scheduledStartFrame: localStartFrame,
            sample: event.sample,
            gain: event.gain,
            pan: event.pan,
            playbackStep: event.playbackStep,
            loop: event.loop,
            initialSourceFrame: event.initialSourceFrame,
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: localKeyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
    }
}
