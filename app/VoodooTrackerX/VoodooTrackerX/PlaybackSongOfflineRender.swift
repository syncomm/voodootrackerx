import Dispatch
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

struct PlaybackSongRenderWindowPerformanceDiagnostic: Equatable {
    let windowIndex: Int
    let schedulingDurationSeconds: Double
    let cMixerRenderDurationSeconds: Double
    let totalWindowDurationSeconds: Double
    let samplePayloadUploadCount: Int
    let approximateSamplePayloadBytesCopied: Int
}

struct PlaybackSongRenderPerformanceDiagnostics: Equatable {
    let totalDurationSeconds: Double
    let planAdaptDurationSeconds: Double
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
    let samplePayloadUploadCount: Int
    let approximateSamplePayloadBytesCopied: Int
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
            deactivateAfterRamp: true
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

    func rampEvent(
        forOldEventIndex eventIndex: Int,
        at boundaryFrame: Int
    ) -> PlaybackSongSameChannelReplacementEvent? {
        replacementEvents.last { event in
            event.oldEventIndex == eventIndex &&
                event.replacementFrame <= boundaryFrame &&
                boundaryFrame < event.completionFrame
        }
    }

    func firstReplacementFrame(forOldEventIndex eventIndex: Int) -> Int? {
        replacementEvents
            .filter { $0.oldEventIndex == eventIndex }
            .map(\.replacementFrame)
            .min()
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

    init(
        request: PlaybackSongOfflineRenderRequest,
        plan: PlaybackSongSyntheticPlan,
        block: MixerRenderBlock,
        scheduledVoiceIndices: [Int?],
        scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?] = [],
        scheduledVoiceAttempts: [PlaybackSongScheduledVoiceAttempt]? = nil,
        windowedRenderSummary: PlaybackSongWindowedRenderSummary? = nil,
        sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics? = nil,
        exportDiagnostics: MixerWAVExportDiagnostics? = nil
    ) {
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
            exportDiagnostics: diagnostics
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
            wavExportPerformanceDiagnostics: wavExportPerformanceDiagnostics
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
            wavExportPerformanceDiagnostics: diagnostics
        )
    }
}

/// Prepared offline render session for split renders and reset determinism checks.
final class PlaybackSongOfflineRenderSession {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let scheduledVoiceIndices: [Int?]
    let scheduledVoiceRejectionReasons: [CSoftwareMixerScheduledVoiceRejectionReason?]
    let sameChannelVoiceLifetime: PlaybackSongSameChannelVoiceLifetimeDiagnostics

    private let mixer: CSoftwareMixer
    private var renderedFrameCount = 0

    var config: MixerRenderConfig {
        mixer.config
    }

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    init(request: PlaybackSongOfflineRenderRequest) {
        self.request = request
        let fullPlan = PlaybackSongSyntheticAdapter.adapt(
            request.song,
            startOrderIndex: request.startOrderIndex,
            orderCount: request.orderCount,
            sampleRate: request.config.sampleRate
        )
        let includedEventIndices = PlaybackSongOfflineRenderer.includedEventIndices(
            for: fullPlan,
            isolationFilter: request.isolationFilter
        )
        let adaptedPlan = PlaybackSongOfflineRenderer.plan(
            fullPlan,
            mutingEventsNotIn: includedEventIndices
        )
        let preparedMixer = CSoftwareMixer(config: request.config)
        let scheduledResults = SyntheticPatternScheduler(config: adaptedPlan.timingConfig).scheduleWithResults(adaptedPlan.pattern, on: preparedMixer)
        let voiceIndices = scheduledResults.map(\.voiceIndex)
        PlaybackSongOfflineRenderer.scheduleEnvelopePositionUpdates(
            adaptedPlan.diagnostics.envelopePositionEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleVoiceStateUpdates(
            adaptedPlan.diagnostics.voiceStateUpdates,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleTonePortamentoStepUpdates(
            adaptedPlan.diagnostics.tonePortamentoEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.schedulePortamentoSlideStepUpdates(
            adaptedPlan.diagnostics.portamentoSlideEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleFinePortamentoUpStepUpdates(
            adaptedPlan.diagnostics.finePortamentoUpEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleFinePortamentoDownStepUpdates(
            adaptedPlan.diagnostics.finePortamentoDownEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleExtraFinePortamentoStepUpdates(
            adaptedPlan.diagnostics.extraFinePortamentoEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleArpeggioStepUpdates(
            adaptedPlan.diagnostics.arpeggioEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleVibratoStepUpdates(
            adaptedPlan.diagnostics.vibratoEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleNoteCuts(
            adaptedPlan.diagnostics.noteCutEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        PlaybackSongOfflineRenderer.scheduleRetriggerCuts(
            adaptedPlan.diagnostics.retriggerEffects,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        sameChannelVoiceLifetime = PlaybackSongOfflineRenderer.sameChannelVoiceLifetimeDiagnostics(
            for: adaptedPlan,
            renderedFrameCount: request.boundedFrameCount
        )
        PlaybackSongOfflineRenderer.scheduleSameChannelReplacementRamps(
            sameChannelVoiceLifetime.replacementEvents,
            voiceIndexByEventIndex: Self.voiceIndexByEventIndex(from: voiceIndices),
            on: preparedMixer,
            includedEventIndices: includedEventIndices
        )
        let rejectionReasons = scheduledResults.map(\.rejectionReason)
        let scheduledCapacityRejectedCount = rejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count
        let eventCoverage = adaptedPlan.diagnostics.eventCoverage
            .reportingCMixerVoiceCapacityRejections(scheduledCapacityRejectedCount)
        plan = adaptedPlan.replacingEventCoverage(eventCoverage)
        mixer = preparedMixer
        scheduledVoiceIndices = voiceIndices
        scheduledVoiceRejectionReasons = rejectionReasons
    }

    func render(frames: Int) -> MixerRenderBlock {
        let requestedFrames = max(0, frames)
        let remainingFrames = max(0, request.boundedFrameCount - renderedFrameCount)
        let frameCount = min(requestedFrames, remainingFrames)
        let block = mixer.render(frames: frameCount)
        renderedFrameCount += block.frameCount
        return block
    }

    func reset() {
        mixer.reset()
        renderedFrameCount = 0
    }

    private static func voiceIndexByEventIndex(from voiceIndices: [Int?]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: voiceIndices.enumerated().compactMap { eventIndex, voiceIndex in
            voiceIndex.map { (eventIndex, $0) }
        })
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

    init(maximumFrameCount: Int = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount) {
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
            diagnostics: plan.diagnostics
        )
    }

    private static func includesEvent(
        _ eventIndex: Int,
        includedEventIndices: Set<Int>?
    ) -> Bool {
        includedEventIndices?.contains(eventIndex) ?? true
    }

    func prepare(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderSession {
        PlaybackSongOfflineRenderSession(request: effectiveRequest(from: request, frames: request.requestedFrameCount))
    }

    func render(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: session.render(frames: effectiveRequest.boundedFrameCount),
            scheduledVoiceIndices: session.scheduledVoiceIndices,
            scheduledVoiceRejectionReasons: session.scheduledVoiceRejectionReasons,
            sameChannelVoiceLifetime: session.sameChannelVoiceLifetime
        )
    }

    func renderWindowed(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        collectPerformanceDiagnostics: Bool = false,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic) -> Void)? = nil
    ) -> PlaybackSongOfflineRenderResult {
        let renderStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let safeWindowRows = max(1, windowRows)
        let planAdaptStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let fullPlan = PlaybackSongSyntheticAdapter.adapt(
            effectiveRequest.song,
            startOrderIndex: effectiveRequest.startOrderIndex,
            orderCount: effectiveRequest.orderCount,
            sampleRate: effectiveRequest.config.sampleRate
        )
        let includedEventIndices = Self.includedEventIndices(
            for: fullPlan,
            isolationFilter: effectiveRequest.isolationFilter
        )
        let adaptedPlan = Self.plan(
            fullPlan,
            mutingEventsNotIn: includedEventIndices
        )
        let totalFrames = effectiveRequest.boundedFrameCount
        let windows = Self.windowSpecs(
            for: adaptedPlan,
            totalFrames: totalFrames,
            windowRows: safeWindowRows
        )
        let scheduler = SyntheticTrackerScheduler(config: adaptedPlan.timingConfig)
        var renderedFrames = 0
        var interleavedPCM = [Float]()
        interleavedPCM.reserveCapacity(totalFrames * effectiveRequest.config.channelCount)
        var attempts = [PlaybackSongScheduledVoiceAttempt]()
        var windowDiagnostics = [PlaybackSongWindowedRenderWindowDiagnostic]()
        var outputConfig = CSoftwareMixer(config: effectiveRequest.config).config
        let knownUnsupportedCarryoverReasons = Self.knownUnsupportedCarryoverReasons(for: adaptedPlan)
        let sameChannelLifetime = Self.sameChannelVoiceLifetimeDiagnostics(
            for: adaptedPlan,
            renderedFrameCount: totalFrames
        )
        let planAdaptDuration = collectPerformanceDiagnostics
            ? VTXPerformanceClock.seconds(since: planAdaptStartTime)
            : 0

        for spec in windows {
            let windowStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            let schedulingStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            let mixer = CSoftwareMixer(
                config: effectiveRequest.config,
                recordsSamplePayloadUploads: collectPerformanceDiagnostics
            )
            outputConfig = mixer.config
            let eventPairs = Self.eventPairs(
                in: spec,
                plan: adaptedPlan,
                scheduler: scheduler
            )
            let continuations = Self.continuations(
                for: spec,
                plan: adaptedPlan,
                scheduler: scheduler,
                sameChannelLifetime: sameChannelLifetime,
                includedEventIndices: includedEventIndices
            )
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
            Self.scheduleEnvelopePositionUpdates(
                adaptedPlan.diagnostics.envelopePositionEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleVoiceStateUpdates(
                adaptedPlan.diagnostics.voiceStateUpdates,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleTonePortamentoStepUpdates(
                adaptedPlan.diagnostics.tonePortamentoEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.schedulePortamentoSlideStepUpdates(
                adaptedPlan.diagnostics.portamentoSlideEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleFinePortamentoUpStepUpdates(
                adaptedPlan.diagnostics.finePortamentoUpEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleFinePortamentoDownStepUpdates(
                adaptedPlan.diagnostics.finePortamentoDownEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleExtraFinePortamentoStepUpdates(
                adaptedPlan.diagnostics.extraFinePortamentoEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleArpeggioStepUpdates(
                adaptedPlan.diagnostics.arpeggioEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleVibratoStepUpdates(
                adaptedPlan.diagnostics.vibratoEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleNoteCuts(
                adaptedPlan.diagnostics.noteCutEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleRetriggerCuts(
                adaptedPlan.diagnostics.retriggerEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleSameChannelReplacementRamps(
                sameChannelLifetime.replacementEvents,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
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
            let block = mixer.render(frames: spec.frameCount)
            let mixerRenderDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: mixerRenderStartTime)
                : 0
            renderedFrames += block.frameCount
            interleavedPCM.append(contentsOf: block.interleavedPCM)
            let samplePayloadUploads = mixer.samplePayloadUploadDiagnostics
            let performanceDiagnostic = collectPerformanceDiagnostics
                ? PlaybackSongRenderWindowPerformanceDiagnostic(
                    windowIndex: spec.index,
                    schedulingDurationSeconds: schedulingDuration,
                    cMixerRenderDurationSeconds: mixerRenderDuration,
                    totalWindowDurationSeconds: VTXPerformanceClock.seconds(since: windowStartTime),
                    samplePayloadUploadCount: samplePayloadUploads.uploadCount,
                    approximateSamplePayloadBytesCopied: samplePayloadUploads.approximateBytesCopied
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
            progress?(spec.index + 1, windows.count, diagnostic)
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
                samplePayloadUploadCount: windowPerformanceDiagnostics.map(\.samplePayloadUploadCount).reduce(0, +),
                approximateSamplePayloadBytesCopied: windowPerformanceDiagnostics.map(\.approximateSamplePayloadBytesCopied).reduce(0, +),
                windows: windowPerformanceDiagnostics
            )
            : nil
        let block = MixerRenderBlock(
            config: outputConfig,
            frameCount: renderedFrames,
            interleavedPCM: interleavedPCM
        )
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
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: finalPlan,
            block: block,
            scheduledVoiceIndices: attempts.map(\.voiceIndex),
            scheduledVoiceRejectionReasons: attempts.map(\.rejectionReason),
            scheduledVoiceAttempts: attempts,
            windowedRenderSummary: summary,
            sameChannelVoiceLifetime: sameChannelLifetime
        )
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
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
        var remainingFrames = effectiveRequest.boundedFrameCount
        var interleavedPCM = [Float]()
        for requestedChunkFrames in splitFrameCounts where remainingFrames > 0 {
            let chunkFrames = min(max(0, requestedChunkFrames), remainingFrames)
            let chunk = session.render(frames: chunkFrames)
            interleavedPCM.append(contentsOf: chunk.interleavedPCM)
            remainingFrames -= chunk.frameCount
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
            sameChannelVoiceLifetime: session.sameChannelVoiceLifetime
        )
    }

    func renderStreaming(
        _ request: PlaybackSongOfflineRenderRequest,
        chunkFrameCount: Int,
        progress: ((Int, Int, MixerRenderBlock) throws -> Void)? = nil
    ) rethrows -> PlaybackSongOfflineStreamingRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
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
            wavExportPerformanceDiagnostics: nil
        )
    }

    func renderWindowedStreaming(
        _ request: PlaybackSongOfflineRenderRequest,
        windowRows: Int,
        collectPerformanceDiagnostics: Bool = false,
        progress: ((Int, Int, PlaybackSongWindowedRenderWindowDiagnostic, MixerRenderBlock) throws -> Void)? = nil
    ) rethrows -> PlaybackSongOfflineStreamingRenderResult {
        let renderStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let safeWindowRows = max(1, windowRows)
        let planAdaptStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
        let fullPlan = PlaybackSongSyntheticAdapter.adapt(
            effectiveRequest.song,
            startOrderIndex: effectiveRequest.startOrderIndex,
            orderCount: effectiveRequest.orderCount,
            sampleRate: effectiveRequest.config.sampleRate
        )
        let includedEventIndices = Self.includedEventIndices(
            for: fullPlan,
            isolationFilter: effectiveRequest.isolationFilter
        )
        let adaptedPlan = Self.plan(
            fullPlan,
            mutingEventsNotIn: includedEventIndices
        )
        let totalFrames = effectiveRequest.boundedFrameCount
        let windows = Self.windowSpecs(
            for: adaptedPlan,
            totalFrames: totalFrames,
            windowRows: safeWindowRows
        )
        let scheduler = SyntheticTrackerScheduler(config: adaptedPlan.timingConfig)
        var renderedFrames = 0
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

        for spec in windows {
            let windowStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            let schedulingStartTime = collectPerformanceDiagnostics ? VTXPerformanceClock.now() : 0
            let mixer = CSoftwareMixer(
                config: effectiveRequest.config,
                recordsSamplePayloadUploads: collectPerformanceDiagnostics
            )
            let eventPairs = Self.eventPairs(
                in: spec,
                plan: adaptedPlan,
                scheduler: scheduler
            )
            let continuations = Self.continuations(
                for: spec,
                plan: adaptedPlan,
                scheduler: scheduler,
                sameChannelLifetime: sameChannelLifetime,
                includedEventIndices: includedEventIndices
            )
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
            Self.scheduleEnvelopePositionUpdates(
                adaptedPlan.diagnostics.envelopePositionEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleVoiceStateUpdates(
                adaptedPlan.diagnostics.voiceStateUpdates,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleTonePortamentoStepUpdates(
                adaptedPlan.diagnostics.tonePortamentoEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.schedulePortamentoSlideStepUpdates(
                adaptedPlan.diagnostics.portamentoSlideEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleFinePortamentoUpStepUpdates(
                adaptedPlan.diagnostics.finePortamentoUpEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleFinePortamentoDownStepUpdates(
                adaptedPlan.diagnostics.finePortamentoDownEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleExtraFinePortamentoStepUpdates(
                adaptedPlan.diagnostics.extraFinePortamentoEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleArpeggioStepUpdates(
                adaptedPlan.diagnostics.arpeggioEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleVibratoStepUpdates(
                adaptedPlan.diagnostics.vibratoEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleNoteCuts(
                adaptedPlan.diagnostics.noteCutEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleRetriggerCuts(
                adaptedPlan.diagnostics.retriggerEffects,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
            Self.scheduleSameChannelReplacementRamps(
                sameChannelLifetime.replacementEvents,
                voiceIndexByEventIndex: voiceIndexByEventIndex,
                on: mixer,
                windowStartFrame: spec.startFrame,
                windowEndFrame: spec.endFrame,
                includedEventIndices: includedEventIndices
            )
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
            let block = mixer.render(frames: spec.frameCount)
            let mixerRenderDuration = collectPerformanceDiagnostics
                ? VTXPerformanceClock.seconds(since: mixerRenderStartTime)
                : 0
            renderedFrames += block.frameCount
            let samplePayloadUploads = mixer.samplePayloadUploadDiagnostics
            let performanceDiagnostic = collectPerformanceDiagnostics
                ? PlaybackSongRenderWindowPerformanceDiagnostic(
                    windowIndex: spec.index,
                    schedulingDurationSeconds: schedulingDuration,
                    cMixerRenderDurationSeconds: mixerRenderDuration,
                    totalWindowDurationSeconds: VTXPerformanceClock.seconds(since: windowStartTime),
                    samplePayloadUploadCount: samplePayloadUploads.uploadCount,
                    approximateSamplePayloadBytesCopied: samplePayloadUploads.approximateBytesCopied
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
            try progress?(spec.index + 1, windows.count, diagnostic, block)
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
                samplePayloadUploadCount: windowPerformanceDiagnostics.map(\.samplePayloadUploadCount).reduce(0, +),
                approximateSamplePayloadBytesCopied: windowPerformanceDiagnostics.map(\.approximateSamplePayloadBytesCopied).reduce(0, +),
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
        return PlaybackSongOfflineStreamingRenderResult(
            request: effectiveRequest,
            plan: finalPlan,
            renderedFrameCount: renderedFrames,
            scheduledVoiceIndices: attempts.map(\.voiceIndex),
            scheduledVoiceRejectionReasons: attempts.map(\.rejectionReason),
            windowedRenderSummary: summary,
            sameChannelVoiceLifetime: sameChannelLifetime,
            exportDiagnostics: nil,
            wavExportPerformanceDiagnostics: nil
        )
    }

    fileprivate static func scheduleVoiceStateUpdates(
        _ updates: [PlaybackSongSyntheticVoiceStateUpdateDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for update in updates where update.activeVoiceUpdated {
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
            _ = mixer.scheduleVoiceGainPanUpdate(
                voiceIndex: voiceIndex,
                scheduledFrame: update.scheduledFrame - windowStartFrame,
                gain: gain,
                pan: pan
            )
        }
    }

    fileprivate static func scheduleEnvelopePositionUpdates(
        _ diagnostics: [PlaybackSongSyntheticEnvelopePositionDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
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
            _ = mixer.scheduleVoiceVolumeEnvelopePositionUpdate(
                voiceIndex: voiceIndex,
                scheduledFrame: diagnostic.scheduledFrame - windowStartFrame,
                positionFrame: appliedPositionFrame
            )
        }
    }

    fileprivate static func scheduleTonePortamentoStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticTonePortamentoDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func schedulePortamentoSlideStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticPortamentoSlideDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func scheduleFinePortamentoUpStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticFinePortamentoUpDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func scheduleFinePortamentoDownStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticFinePortamentoDownDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func scheduleExtraFinePortamentoStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticExtraFinePortamentoDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func scheduleArpeggioStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticArpeggioDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func scheduleVibratoStepUpdates(
        _ diagnostics: [PlaybackSongSyntheticVibratoDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for diagnostic in diagnostics where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex] else {
                continue
            }
            for update in diagnostic.stepUpdates {
                guard update.scheduledFrame >= windowStartFrame else {
                    continue
                }
                if let windowEndFrame,
                   update.scheduledFrame >= windowEndFrame {
                    continue
                }
                _ = mixer.scheduleVoicePlaybackStepUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: update.scheduledFrame - windowStartFrame,
                    playbackStep: update.playbackStepAfter
                )
            }
        }
    }

    fileprivate static func scheduleNoteCuts(
        _ cuts: [PlaybackSongSyntheticNoteCutDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for cut in cuts where cut.applied {
            guard let activeEventIndex = cut.activeEventIndex,
                  includesEvent(activeEventIndex, includedEventIndices: includedEventIndices),
                  let voiceIndex = voiceIndexByEventIndex[activeEventIndex],
                  let scheduledFrame = cut.scheduledFrame else {
                continue
            }
            guard scheduledFrame >= windowStartFrame else {
                continue
            }
            if let windowEndFrame,
               scheduledFrame >= windowEndFrame {
                continue
            }
            _ = mixer.scheduleVoiceGainPanImmediateUpdate(
                voiceIndex: voiceIndex,
                scheduledFrame: scheduledFrame - windowStartFrame,
                gain: 0,
                pan: nil
            )
        }
    }

    fileprivate static func scheduleRetriggerCuts(
        _ retriggers: [PlaybackSongSyntheticRetriggerDiagnostic],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for retrigger in retriggers where retrigger.applied {
            for (eventIndex, scheduledFrame) in zip(retrigger.replacedEventIndices, retrigger.retriggerFrames) {
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
                _ = mixer.scheduleVoiceGainPanImmediateUpdate(
                    voiceIndex: voiceIndex,
                    scheduledFrame: scheduledFrame - windowStartFrame,
                    gain: 0,
                    pan: nil
                )
            }
        }
    }

    fileprivate static func scheduleSameChannelReplacementRamps(
        _ replacements: [PlaybackSongSameChannelReplacementEvent],
        voiceIndexByEventIndex: [Int: Int],
        on mixer: CSoftwareMixer,
        windowStartFrame: Int = 0,
        windowEndFrame: Int? = nil,
        includedEventIndices: Set<Int>? = nil
    ) {
        for replacement in replacements {
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
            _ = mixer.scheduleVoiceRampDownAndDeactivate(
                voiceIndex: voiceIndex,
                scheduledFrame: replacement.replacementFrame - windowStartFrame,
                rampFrames: replacement.oldVoiceRampDurationFrames
            )
        }
    }

    private static func changedGain(
        from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic
    ) -> Float? {
        guard let before = update.gainBefore,
              let after = update.gainAfter,
              before != after else {
            return nil
        }
        return after
    }

    private static func changedPan(
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

    private struct WindowContinuation: Equatable {
        let eventIndex: Int
        let event: SyntheticTrackerEvent
        let runtimeState: CSoftwareMixerVoiceRuntimeState
        let keyOffFrame: Int?
        let carriedTonePortamentoActive: Bool
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
        includedEventIndices: Set<Int>? = nil
    ) -> [WindowContinuation] {
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
            if let mapping = mappingsByEventIndex[eventIndex],
               let latestEventIndex = latestEventIndexByChannel[mapping.channelIndex] {
                let isLatestChannelVoice = latestEventIndex == eventIndex
                let isReplacementRampCarry = sameChannelLifetime.rampEvent(
                    forOldEventIndex: eventIndex,
                    at: windowStartFrame
                ) != nil
                if !isLatestChannelVoice && !isReplacementRampCarry {
                    return nil
                }
            }
            if hasAppliedNoteCut(
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
            let replacementRampEvent = sameChannelLifetime.rampEvent(
                forOldEventIndex: eventIndex,
                at: windowStartFrame
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
            let stepState = stepStateAtBoundary(
                for: event,
                eventIndex: eventIndex,
                plan: plan,
                before: windowStartFrame
            )
            let carriedEvent = event
                .withGainPan(gain: gainPanState.gain, pan: gainPanState.pan)
                .withPlaybackStep(stepState.playbackStep)
            return continuation(
                eventIndex: eventIndex,
                event: carriedEvent,
                sourceEvent: event,
                eventStartFrame: eventStartFrame,
                boundaryFrame: windowStartFrame,
                plan: plan,
                gainRamp: replacementGainRamp ?? gainPanState.gainRamp,
                panRamp: gainPanState.panRamp,
                carriedTonePortamentoActive: stepState.carriedTonePortamentoActive
            )
        }
    }

    private static func gainPanStateAtBoundary(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        before boundaryFrame: Int,
        includingUpdatesAtBoundary: Bool = false
    ) -> GainPanStateAtBoundary {
        var gain = event.gain
        var pan = event.pan
        var gainRamp: GainPanRampSimulation?
        var panRamp: GainPanRampSimulation?
        let rampFrames = CSoftwareMixer.gainPanUpdateRampFrameCount

        for update in plan.diagnostics.voiceStateUpdates {
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
            gainRamp: gainRamp?.runtimeState(at: boundaryFrame),
            panRamp: panRamp?.runtimeState(at: boundaryFrame)
        )
    }

    private static func stepStateAtBoundary(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        before boundaryFrame: Int
    ) -> StepStateAtBoundary {
        var playbackStep = event.playbackStep
        var sawPriorUpdate = false
        var hasFutureUpdate = false
        for update in sampleStepUpdates(for: eventIndex, plan: plan) {
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
        ).gain
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
        return (toneUpdates + slideUpdates + finePortamentoUpUpdates + finePortamentoDownUpdates + extraFinePortamentoUpdates + arpeggioUpdates + vibratoUpdates)
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

    private static func hasAppliedNoteCut(
        eventIndex: Int,
        before boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.diagnostics.noteCutEffects.contains { cut in
            cut.applied &&
                cut.activeEventIndex == eventIndex &&
                (cut.scheduledFrame ?? Int.max) < boundaryFrame
        }
    }

    private static func hasAppliedNoteCut(
        eventIndex: Int,
        atOrBefore boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan
    ) -> Bool {
        plan.diagnostics.noteCutEffects.contains { cut in
            cut.applied &&
                cut.activeEventIndex == eventIndex &&
                (cut.scheduledFrame ?? Int.max) <= boundaryFrame
        }
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
            return zip(retrigger.replacedEventIndices, retrigger.retriggerFrames).contains { replacedEventIndex, frame in
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
            return zip(retrigger.replacedEventIndices, retrigger.retriggerFrames).contains { replacedEventIndex, frame in
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

        let rampFrames = CSoftwareMixer.replacementStopRampFrameCount
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
            replacementEvents: replacementEvents
        )
    }

    private static func sameChannelVoiceIsActive(
        _ voice: SameChannelActiveVoice,
        at frame: Int,
        plan: PlaybackSongSyntheticPlan,
        scheduler: SyntheticTrackerScheduler
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
        if hasAppliedNoteCut(
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
            boundaryFrame: frame
        ) != nil else {
            return false
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

    private static func continuation(
        eventIndex: Int,
        event: SyntheticTrackerEvent,
        sourceEvent: SyntheticTrackerEvent,
        eventStartFrame: Int,
        boundaryFrame: Int,
        plan: PlaybackSongSyntheticPlan,
        gainRamp: CSoftwareMixerValueRampRuntimeState?,
        panRamp: CSoftwareMixerValueRampRuntimeState?,
        carriedTonePortamentoActive: Bool
    ) -> WindowContinuation? {
        let elapsedFrames = max(0, boundaryFrame - eventStartFrame)
        guard elapsedFrames > 0,
              let sourceState = sourcePositionState(
                  for: sourceEvent,
                  eventIndex: eventIndex,
                  plan: plan,
                  eventStartFrame: eventStartFrame,
                  boundaryFrame: boundaryFrame
              ) else {
            return nil
        }
        let keyOffFrame = event.keyOffFrame
        let keyOn = keyOffFrame.map { boundaryFrame <= $0 } ?? true
        let keyedFrames = keyedFrameCount(
            elapsedFrames: elapsedFrames,
            eventStartFrame: eventStartFrame,
            keyOffFrame: keyOffFrame
        )
        let releasedFrames = releasedFrameCount(
            boundaryFrame: boundaryFrame,
            keyOffFrame: keyOffFrame
        )
        let fadeoutValue = fadeoutValue(
            releasedFrames: releasedFrames,
            decrementPerFrame: event.fadeoutFrameDecrement
        )
        guard fadeoutValue > 0 else {
            return nil
        }
        let volumeEnvelopePosition = volumeEnvelopePosition(
            for: event.volumeEnvelope,
            eventIndex: eventIndex,
            plan: plan,
            eventStartFrame: eventStartFrame,
            boundaryFrame: boundaryFrame,
            keyOffFrame: keyOffFrame
        )
        let panEnvelopePosition = envelopePosition(
            for: event.panEnvelope,
            keyedFrames: keyedFrames,
            releasedFrames: releasedFrames
        )
        let localKeyOffFrame: Int?
        if let keyOffFrame {
            localKeyOffFrame = max(0, keyOffFrame - boundaryFrame)
        } else {
            localKeyOffFrame = nil
        }
        return WindowContinuation(
            eventIndex: eventIndex,
            event: event,
            runtimeState: CSoftwareMixerVoiceRuntimeState(
                samplePosition: sourceState.samplePosition,
                pingPongDirection: sourceState.pingPongDirection,
                volumeEnvelopePositionFrame: volumeEnvelopePosition,
                panEnvelopePositionFrame: panEnvelopePosition,
                keyOn: keyOn,
                fadeoutValue: fadeoutValue,
                gainRamp: gainRamp,
                panRamp: panRamp
            ),
            keyOffFrame: localKeyOffFrame,
            carriedTonePortamentoActive: carriedTonePortamentoActive
        )
    }

    private static func scheduleContinuation(
        _ continuation: WindowContinuation,
        on mixer: CSoftwareMixer
    ) -> CSoftwareMixerScheduledVoiceResult {
        let event = continuation.event
        let result = mixer.addScheduledVoiceWithResult(
            sample: event.sample,
            scheduledStartFrame: 0,
            gain: event.gain,
            pan: event.pan,
            playbackStep: event.playbackStep,
            loop: event.loop,
            initialSourceFrame: Int(continuation.runtimeState.samplePosition.rounded(.down)),
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: continuation.keyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
        if let voiceIndex = result.voiceIndex {
            mixer.setRuntimeState(continuation.runtimeState, forVoiceAt: voiceIndex)
        }
        return result
    }

    private static func sourcePositionState(
        for event: SyntheticTrackerEvent,
        eventIndex: Int,
        plan: PlaybackSongSyntheticPlan,
        eventStartFrame: Int,
        boundaryFrame: Int
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
        var currentStep = event.playbackStep
        for update in sampleStepUpdates(for: eventIndex, plan: plan) {
            guard update.scheduledFrame > eventStartFrame,
                  update.scheduledFrame < boundaryFrame else {
                continue
            }
            let segmentFrames = max(0, update.scheduledFrame - cursorFrame)
            advancedPosition += Double(segmentFrames) * currentStep
            cursorFrame = update.scheduledFrame
            currentStep = update.playbackStepAfter
        }
        advancedPosition += Double(max(0, boundaryFrame - cursorFrame)) * currentStep
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

    private static func localEvent(
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
