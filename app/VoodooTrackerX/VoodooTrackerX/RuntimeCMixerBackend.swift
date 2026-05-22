import AVFoundation
import AudioToolbox
import Foundation
import os

@MainActor
protocol RuntimeAudioDiagnosticOutput: AnyObject {
    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?)
    func update(channel: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?)
    func stop(channel: Int, context: AudioRuntimeTraceContext?)
    func stopAll(context: AudioRuntimeTraceContext?, reason: String)
    func recordTransition(previousContext: AudioRuntimeTraceContext?, context: AudioRuntimeTraceContext?, phase: String, reason: String)
    func recordPublishedPlaybackFollowPosition(timerContext: AudioRuntimeTraceContext?, publishedPosition: PlaybackFollowPosition, publicationDisabled: Bool)
}

@MainActor
protocol RuntimeCMixerAdapterEventConsuming: AnyObject {
    var hasRuntimeAdapterEventPlan: Bool { get }

    func configureRuntimeAdapterEventPlan(_ plan: RuntimeCMixerAdapterEventPlan, generationMS: Double?)
    func resetRuntimeAdapterEventConsumption()
    func consumeRuntimeAdapterEvents(context: AudioRuntimeTraceContext?)
}

private struct RuntimeCMixerEventCounters: Equatable {
    var cMixerAddVoiceCount: UInt64 = 0
    var gainPanUpdateCount: UInt64 = 0
    var stepUpdateCount: UInt64 = 0
    var updateSuppressedEpsilonGainCount: UInt64 = 0
    var updateSuppressedEpsilonPanCount: UInt64 = 0
    var updateSuppressedEpsilonStepCount: UInt64 = 0
    var updateSuppressedNoChangeCount: UInt64 = 0
    var updateAppliedAfterEpsilonFilterCount: UInt64 = 0
    var stopChannelCount: UInt64 = 0
    var replacementRampCount: UInt64 = 0
    var clearAllCount: UInt64 = 0
    var consumedPlannedEventCount: UInt64 = 0
    var skippedUnmatchedPlannedEventCount: UInt64 = 0
    var fallbackToSimpleRuntimeEventCount: UInt64 = 0
}

private struct RuntimeCMixerEventTimingTraceFields: Equatable {
    let runtimeEventCategory: String?
    let plannedEventID: Int?
    let plannedSourceOrderIndex: Int?
    let plannedSourcePatternIndex: Int?
    let plannedSourceRowIndex: Int?
    let plannedSourceTickInRow: Int?
    let plannedSourceChannelIndex: Int?
    let plannedEventFrame: Int?
    let plannedRuntimeFrame: Int?
    let plannedRuntimeFrameOffset: Int?
    let runtimeApplicationFrame: UInt64?
    let eventFrameDelta: Int?
    let eventApplicationTiming: String?
    let eventAppliedFrame: UInt64?
    let inCallbackOffset: Int?
    let plannedVsAppliedDelta: Int?
    let sameFrameBurstSize: Int?
    let sameFrameBurst: RuntimeCMixerSameFrameBurstDiagnostic?
    let adapterActiveEventIndex: Int?
    let adapterCurrentEventIndexBefore: Int?
    let adapterCurrentEventIndexAfter: Int?
    let adapterChannelAssociationRetained: Bool?
    let adapterSustainedVoiceUpdate: Bool?
    let callbackIndex: UInt64?
    let callbackRequestedFrameCount: Int?
    let callbackStartFrame: UInt64?
    let callbackEndFrame: UInt64?
}

private struct RuntimeCMixerTransitionTraceFields: Equatable {
    let previousContext: AudioRuntimeTraceContext?
    let nextContext: AudioRuntimeTraceContext?
    let phase: String
    let runtimeFrame: UInt64
    let replacementRampCount: UInt64?
    let updateCount: UInt64?
}

private struct RuntimeCMixerSampleTimePositionTraceFields: Equatable {
    let cMixerRenderedFrames: UInt64
    let cMixerPlaybackSeconds: Double?
    let cMixerSampleTimeFrame: Int?
    let cMixerSampleTimePositionStatus: String?
    let cMixerSampleTimeOrderIndex: Int?
    let cMixerSampleTimePatternIndex: Int?
    let cMixerSampleTimeRowIndex: Int?
    let cMixerSampleTimeTickInRow: Int?
    let cMixerSampleTimeSyntheticRow: Int?
    let playbackEngineOrderIndex: Int?
    let playbackEnginePatternIndex: Int?
    let playbackEngineRowIndex: Int?
    let playbackEngineTickInRow: Int?
    let playbackEngineToCMixerFrameDelta: Int?
    let playbackEngineToCMixerPositionMismatch: Bool?
    let rowTransitionDeltaCategory: String?
}

private struct RuntimeCMixerPendingTransition: Equatable {
    let previousContext: AudioRuntimeTraceContext?
    let nextContext: AudioRuntimeTraceContext?
    let snapshot: RuntimeCMixerRenderSnapshot
    let replacementRampCount: UInt64
    let updateCount: UInt64
}

private let runtimeCMixerDefaultOutputUnitRenderCallback: AURenderCallback = { userData, _, _, _, frameCount, ioData in
    guard let ioData else {
        return noErr
    }
    let host = Unmanaged<RuntimeCMixerDefaultOutputUnitHost>.fromOpaque(userData).takeUnretainedValue()
    return host.render(frameCount: frameCount, ioData: ioData)
}

private final class RuntimeCMixerDefaultOutputUnitHost {
    private let renderCore: RuntimeCMixerRenderCore
    private(set) var configuration: RuntimeCMixerCoreAudioHostConfiguration
    private var outputUnit: AudioUnit?
    private var lifecycle = RuntimeCMixerOutputHostLifecycle()

    init(
        configuration: RuntimeCMixerCoreAudioHostConfiguration,
        renderCore: RuntimeCMixerRenderCore
    ) {
        self.configuration = configuration
        self.renderCore = renderCore
    }

    deinit {
        reset()
    }

    var isPrepared: Bool {
        outputUnit != nil && lifecycle.state != .stopped
    }

    var isRunning: Bool {
        lifecycle.state == .running
    }

    var lastPrepareStatus: OSStatus? {
        lifecycle.lastPrepareStatus
    }

    var lastInitializeStatus: OSStatus? {
        lifecycle.lastInitializeStatus
    }

    var lastStartStatus: OSStatus? {
        lifecycle.lastStartStatus
    }

    var lastStopStatus: OSStatus? {
        lifecycle.lastStopStatus
    }

    var lastErrorStatus: OSStatus? {
        lifecycle.lastErrorStatus
    }

    @discardableResult
    func prepare() -> OSStatus {
        if isPrepared {
            return noErr
        }
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            let status = kAudio_ParamError
            lifecycle.prepare(status: status)
            return status
        }
        var unit: AudioUnit?
        recordAudioUnitLifecycleCallIfCallbackActive()
        let newInstanceStatus = AudioComponentInstanceNew(component, &unit)
        guard newInstanceStatus == noErr else {
            lifecycle.prepare(status: newInstanceStatus)
            return newInstanceStatus
        }
        guard let unit else {
            let status = kAudio_ParamError
            lifecycle.prepare(status: status)
            return status
        }
        outputUnit = unit

        var streamDescription = configuration.streamDescription
        recordAudioUnitLifecycleCallIfCallbackActive()
        let streamFormatStatus = withUnsafePointer(to: &streamDescription) { pointer in
            AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                0,
                pointer,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )
        }
        guard streamFormatStatus == noErr else {
            lifecycle.prepare(status: streamFormatStatus)
            reset()
            return streamFormatStatus
        }

        var callback = AURenderCallbackStruct(
            inputProc: runtimeCMixerDefaultOutputUnitRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        recordAudioUnitLifecycleCallIfCallbackActive()
        let callbackStatus = withUnsafePointer(to: &callback) { pointer in
            AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input,
                0,
                pointer,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
        }
        guard callbackStatus == noErr else {
            lifecycle.prepare(status: callbackStatus)
            reset()
            return callbackStatus
        }

        recordAudioUnitLifecycleCallIfCallbackActive()
        let initializeStatus = AudioUnitInitialize(unit)
        guard initializeStatus == noErr else {
            lifecycle.prepare(status: initializeStatus, initializeStatus: initializeStatus)
            reset()
            return initializeStatus
        }
        lifecycle.prepare(status: noErr, initializeStatus: initializeStatus)
        return noErr
    }

    @discardableResult
    func start() -> OSStatus {
        if isRunning {
            return noErr
        }
        let prepareStatus = prepare()
        guard prepareStatus == noErr,
              let unit = outputUnit else {
            return prepareStatus
        }
        recordAudioUnitLifecycleCallIfCallbackActive()
        let startStatus = AudioOutputUnitStart(unit)
        lifecycle.start(status: startStatus)
        return startStatus
    }

    @discardableResult
    func stop() -> OSStatus {
        guard let unit = outputUnit,
              isPrepared else {
            lifecycle.stop(status: noErr)
            return noErr
        }
        recordAudioUnitLifecycleCallIfCallbackActive()
        let status = isRunning ? AudioOutputUnitStop(unit) : noErr
        lifecycle.stop(status: status)
        return status
    }

    func reset() {
        if let unit = outputUnit {
            if isRunning {
                recordAudioUnitLifecycleCallIfCallbackActive()
                let status = AudioOutputUnitStop(unit)
                lifecycle.stop(status: status)
            }
            recordAudioUnitLifecycleCallIfCallbackActive()
            AudioUnitUninitialize(unit)
            recordAudioUnitLifecycleCallIfCallbackActive()
            AudioComponentInstanceDispose(unit)
        }
        outputUnit = nil
        lifecycle.reset()
    }

    fileprivate func render(
        frameCount: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        renderCore.render(frameCount: AVAudioFrameCount(frameCount), ioData: ioData)
    }

    private func recordAudioUnitLifecycleCallIfCallbackActive() {
        renderCore.recordAudioUnitLifecycleCallIfCallbackActive()
    }
}

@MainActor
final class RuntimeCMixerAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding, PlaybackFollowPositionProviding, RuntimeAudioDiagnosticOutput, RuntimeCMixerAdapterEventConsuming {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let backend: RuntimeAudioBackend
    private let format: AVAudioFormat
    private let coreAudioOutputHost: RuntimeCMixerDefaultOutputUnitHost
    private let renderCore: RuntimeCMixerRenderCore
    private let fallbackAudioEngine = PlaybackAudioEngine()
    private let traceWriter: RuntimeCMixerTraceWriting
    private let runtimeSampleRateSelection: RuntimeCMixerSampleRateSelection?
    private let routeLabel: String?
    private let startsOutputHostOnDemand: Bool
    private var isPrepared = false
    private var isFallbackActive = false
    private var engineConfigurationChangeCount: UInt64 = 0
    private var audioEngineRestartCount: UInt64 = 0
    private var audioGraphFormatChangeCount: UInt64 = 0
    private var audioOutputRouteChangeCount: UInt64 = 0
    private var lastAudioGraphFormatSignature: [String]?
    private var lastAudioGraphWasPrepared = false
    private var lastAudioOutputRouteSignature: [String]?
    private var lastAudioGraphDiagnostics: RuntimeCMixerAudioGraphDiagnostics?
    private var playbackFollowPublicationCount: UInt64 = 0
    private var playbackFollowPublicationSuppressedCount: UInt64 = 0
    private var eventCounters = RuntimeCMixerEventCounters()
    private var adapterEventPlan = RuntimeCMixerAdapterEventPlan.unavailable()
    private var consumedAdapterEventIDs = Set<Int>()
    private var consumedAdapterEventCategories = Set<String>()
    private var plannedRuntimeFrameOffset: Int?
    private var sampleTimePositionResolver: PlaybackSongSampleTimePositionResolver?
    private var adapterEventScheduleConfigured = false
    private var pendingTransition: RuntimeCMixerPendingTransition?

    init(
        backend: RuntimeAudioBackend = .cMixer,
        sampleRate: Double = MixerRenderConfig.defaultSampleRate,
        channelCount: Int = MixerRenderConfig.defaultChannelCount,
        outputPolicy: RuntimeCMixerOutputPolicy = .defaultPolicy,
        updatePolicy: RuntimeCMixerUpdatePolicy = .defaultPolicy,
        captureConfiguration: RuntimeCMixerCaptureConfiguration? = nil,
        callbackDiagnostics: RuntimeCMixerCallbackDiagnosticsConfiguration = .defaultConfiguration,
        songEndTailPolicy: RuntimeCMixerSongEndTailPolicy = .defaultPolicy,
        runtimeSampleRateSelection: RuntimeCMixerSampleRateSelection? = nil,
        routeLabel: String? = nil,
        startsOutputHostOnDemand: Bool = true,
        traceWriter: RuntimeCMixerTraceWriting = NoopRuntimeCMixerTraceWriter.shared
    ) {
        let resolvedBackend = backend.usesRuntimeCMixer ? backend : .cMixer
        self.backend = resolvedBackend
        self.startsOutputHostOnDemand = startsOutputHostOnDemand
        let config = MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount)
        renderCore = RuntimeCMixerRenderCore(
            config: config,
            outputPolicy: outputPolicy,
            updatePolicy: updatePolicy,
            captureConfiguration: captureConfiguration,
            callbackDiagnostics: callbackDiagnostics,
            songEndTailPolicy: songEndTailPolicy
        )
        self.traceWriter = traceWriter
        self.runtimeSampleRateSelection = runtimeSampleRateSelection
        self.routeLabel = RuntimeCMixerDeviceIdentityRedactor.safeRouteLabel(routeLabel)
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: renderCore.config.sampleRate,
            channels: AVAudioChannelCount(renderCore.config.channelCount),
            interleaved: false
        )!
        coreAudioOutputHost = RuntimeCMixerDefaultOutputUnitHost(
            configuration: RuntimeCMixerCoreAudioHostConfiguration(
                sampleRate: renderCore.config.sampleRate,
                channelCount: renderCore.config.channelCount
            ),
            renderCore: renderCore
        )
        logger.info(
            "Initialized experimental C mixer runtime backend=\(self.backend.diagnosticName, privacy: .public) host_type=\(self.backend.runtimeOutputHostType, privacy: .public) sample_rate=\(self.renderCore.config.sampleRate, privacy: .public) channel_count=\(self.renderCore.config.channelCount, privacy: .public)"
        )
        recordRuntimeEvent(
            action: "backend_initialized",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: nil,
            reason: "runtime_c_mixer_initialized"
        )
    }

    var runtimeAudioBackend: RuntimeAudioBackend {
        backend
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    func renderForTesting(frameCount: Int) -> [Float] {
        let safeFrameCount = max(0, frameCount)
        var output = Array(repeating: Float(0), count: safeFrameCount * renderCore.config.channelCount)
        output.withUnsafeMutableBufferPointer { buffer in
            _ = renderCore.render(into: buffer, frameCount: safeFrameCount)
        }
        drainAppliedRuntimeAdapterEvents()
        return output
    }

#if DEBUG
    func configureAdapterEventScheduleForTesting(
        _ events: [RuntimeCMixerAdapterEvent],
        runtimeFrameOffset: Int,
        plannedSongEndFrame: Int? = nil
    ) {
        _ = renderCore.configureAdapterEventSchedule(
            events,
            runtimeFrameOffset: runtimeFrameOffset,
            plannedSongEndFrame: plannedSongEndFrame
        )
    }

    func snapshotForTesting() -> RuntimeCMixerRenderSnapshot {
        renderCore.snapshot()
    }
#endif

    var hasRuntimeAdapterEventPlan: Bool {
        adapterEventPlan.generated
    }

    func playbackFollowPosition(timerPosition: PlaybackPosition, timerTickInRow: Int) -> PlaybackFollowPosition? {
        guard adapterEventPlan.generated,
             let cMixerPosition = resolvedSampleTimePosition(
                 context: traceContext(position: timerPosition, tickInRow: timerTickInRow),
                 currentFrame: renderCore.realtimeCurrentFrame
             ) else {
            return nil
        }
        return PlaybackFollowPosition(
            position: cMixerPosition.source,
            tickInRow: cMixerPosition.tickInRow,
            source: .cMixerSampleTime,
            sampleTimeFrame: cMixerPosition.frame,
            sampleTimeStatus: cMixerPosition.status,
            syntheticRow: cMixerPosition.syntheticRow
        )
    }

    func configureRuntimeAdapterEventPlan(_ plan: RuntimeCMixerAdapterEventPlan, generationMS: Double?) {
        adapterEventPlan = plan
        sampleTimePositionResolver = plan.plan.map(PlaybackSongSampleTimePositionResolver.init(plan:))
        resetRuntimeAdapterEventConsumption()
        recordRuntimeEvent(
            action: "adapter_plan_configured",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: plan.generated,
            runtimeEventSource: plan.generated ? RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue : RuntimeCMixerAdapterEventSource.playbackEngineSimple.rawValue,
            adapterPlanGenerationMS: generationMS,
            reason: plan.generated ? "runtime_c_mixer_adapter_plan_generated" : "runtime_c_mixer_adapter_plan_unavailable"
        )
    }

    func resetRuntimeAdapterEventConsumption() {
        consumedAdapterEventIDs.removeAll()
        consumedAdapterEventCategories.removeAll()
        eventCounters.consumedPlannedEventCount = 0
        eventCounters.skippedUnmatchedPlannedEventCount = 0
        eventCounters.fallbackToSimpleRuntimeEventCount = 0
        plannedRuntimeFrameOffset = nil
        sampleTimePositionResolver = adapterEventPlan.plan.map(PlaybackSongSampleTimePositionResolver.init(plan:))
        adapterEventScheduleConfigured = false
        pendingTransition = nil
        renderCore.clearAdapterEventSchedule()
    }

    func consumeRuntimeAdapterEvents(context: AudioRuntimeTraceContext?) {
        drainAppliedRuntimeAdapterEvents()
        guard adapterEventPlan.generated else {
            eventCounters.fallbackToSimpleRuntimeEventCount &+= 1
            recordRuntimeEvent(
                action: "adapter_plan_unavailable",
                context: context,
                targetScope: "none",
                snapshot: renderCore.snapshot(),
                succeeded: nil,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.playbackEngineSimple.rawValue,
                runtimeEventFallbackReason: "adapter_plan_unavailable",
                reason: "runtime_c_mixer_adapter_plan_unavailable"
            )
            return
        }

        configureAdapterEventScheduleIfNeeded(context: context)
    }

    private func configureAdapterEventScheduleIfNeeded(context: AudioRuntimeTraceContext?) {
        guard !adapterEventScheduleConfigured else {
            return
        }
        let snapshot = renderCore.snapshot()
        guard let offset = resolvedPlannedRuntimeFrameOffset(context: context, snapshot: snapshot) else {
            return
        }
        let result = renderCore.configureAdapterEventSchedule(
            adapterEventPlan.events,
            runtimeFrameOffset: offset,
            plannedSongEndFrame: adapterEventPlan.plannedSongEndFrame
        )
        adapterEventScheduleConfigured = true
        if startsOutputHostOnDemand {
            prepareIfNeeded()
            if !startEngineIfNeeded() {
                isFallbackActive = true
            }
        }
        recordRuntimeEvent(
            action: "adapter_event_schedule_configured",
            context: context,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: true,
            runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
            reason: "runtime_c_mixer_adapter_event_schedule_configured queued=\(result.queuedEventCount) skipped_before_runtime_start=\(result.skippedNegativeRuntimeFrameCount) skipped_overflow=\(result.skippedOverflowCount)"
        )
    }

    private func transitionTimingTraceFields(
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> RuntimeCMixerEventTimingTraceFields? {
        transitionTimingTraceFields(
            context: context,
            currentFrame: snapshot.currentFrame,
            callbackEndFrame: snapshot.callbackEndFrame
        )
    }

    private func transitionTimingTraceFields(
        context: AudioRuntimeTraceContext?,
        currentFrame: UInt64,
        callbackEndFrame: UInt64? = nil
    ) -> RuntimeCMixerEventTimingTraceFields? {
        guard let context,
              let plannedRowStartFrame = adapterEventPlan.plannedRowStartFrame(matching: context) else {
            return nil
        }
        let offset = resolvedPlannedRuntimeFrameOffset(context: context, currentFrame: currentFrame)
        let plannedRuntimeFrame = offset.flatMap { safeAdding(plannedRowStartFrame, $0) }
        let frameDelta = plannedRuntimeFrame.flatMap { delta(runtimeFrame: currentFrame, plannedFrame: $0) }
        return RuntimeCMixerEventTimingTraceFields(
            runtimeEventCategory: "row_transition",
            plannedEventID: nil,
            plannedSourceOrderIndex: context.orderIndex,
            plannedSourcePatternIndex: context.patternIndex,
            plannedSourceRowIndex: context.rowIndex,
            plannedSourceTickInRow: context.tickInRow,
            plannedSourceChannelIndex: context.channelIndex,
            plannedEventFrame: plannedRowStartFrame,
            plannedRuntimeFrame: plannedRuntimeFrame,
            plannedRuntimeFrameOffset: offset,
            runtimeApplicationFrame: currentFrame,
            eventFrameDelta: frameDelta,
            eventApplicationTiming: eventApplicationTiming(
                plannedRuntimeFrame: plannedRuntimeFrame,
                runtimeApplicationFrame: currentFrame,
                context: context,
                callbackEndFrame: callbackEndFrame
            ),
            eventAppliedFrame: currentFrame,
            inCallbackOffset: nil,
            plannedVsAppliedDelta: frameDelta,
            sameFrameBurstSize: nil,
            sameFrameBurst: nil,
            adapterActiveEventIndex: nil,
            adapterCurrentEventIndexBefore: nil,
            adapterCurrentEventIndexAfter: nil,
            adapterChannelAssociationRetained: nil,
            adapterSustainedVoiceUpdate: nil,
            callbackIndex: nil,
            callbackRequestedFrameCount: nil,
            callbackStartFrame: nil,
            callbackEndFrame: nil
        )
    }

    private func sampleTimePositionTraceFields(
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot,
        isRowTransition: Bool
    ) -> RuntimeCMixerSampleTimePositionTraceFields {
        sampleTimePositionTraceFields(
            context: context,
            currentFrame: snapshot.currentFrame,
            sampleRate: snapshot.sampleRate,
            isRowTransition: isRowTransition
        )
    }

    private func sampleTimePositionTraceFields(
        context: AudioRuntimeTraceContext?,
        currentFrame: UInt64,
        sampleRate: Double,
        isRowTransition: Bool
    ) -> RuntimeCMixerSampleTimePositionTraceFields {
        let playbackSeconds = sampleRate > 0
            ? Double(currentFrame) / sampleRate
            : nil
        let offset = plannedRuntimeFrameOffset ?? resolvedPlannedRuntimeFrameOffset(
            context: context,
            currentFrame: currentFrame
        )
        let cMixerSampleTimeFrame = offset.flatMap { plannedFrame(runtimeFrame: currentFrame, runtimeFrameOffset: $0) }
        let cMixerPosition = cMixerSampleTimeFrame.flatMap { sampleTimePositionResolver?.position(atFrame: $0) }
        let playbackEnginePlannedFrame = adapterEventPlan.plannedFrame(matching: context)
        let playbackEngineRuntimeFrame = playbackEnginePlannedFrame.flatMap { plannedFrame in
            offset.flatMap { safeAdding(plannedFrame, $0) }
        }
        let frameDelta = playbackEngineRuntimeFrame.flatMap { plannedFrame in
            delta(runtimeFrame: currentFrame, plannedFrame: plannedFrame)
        }
        let mismatch = positionMismatch(context: context, cMixerPosition: cMixerPosition)
        return RuntimeCMixerSampleTimePositionTraceFields(
            cMixerRenderedFrames: currentFrame,
            cMixerPlaybackSeconds: playbackSeconds,
            cMixerSampleTimeFrame: cMixerSampleTimeFrame,
            cMixerSampleTimePositionStatus: cMixerPosition?.status,
            cMixerSampleTimeOrderIndex: cMixerPosition?.source.orderIndex,
            cMixerSampleTimePatternIndex: cMixerPosition?.source.patternIndex,
            cMixerSampleTimeRowIndex: cMixerPosition?.source.rowIndex,
            cMixerSampleTimeTickInRow: cMixerPosition?.tickInRow,
            cMixerSampleTimeSyntheticRow: cMixerPosition?.syntheticRow,
            playbackEngineOrderIndex: context?.orderIndex,
            playbackEnginePatternIndex: context?.patternIndex,
            playbackEngineRowIndex: context?.rowIndex,
            playbackEngineTickInRow: context?.tickInRow,
            playbackEngineToCMixerFrameDelta: frameDelta,
            playbackEngineToCMixerPositionMismatch: mismatch,
            rowTransitionDeltaCategory: isRowTransition
                ? rowTransitionDeltaCategory(delta: frameDelta, context: context, cMixerPosition: cMixerPosition, sampleRate: sampleRate)
                : nil
        )
    }

    private func resolvedSampleTimePosition(
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> PlaybackSongSampleTimePosition? {
        let offset = plannedRuntimeFrameOffset ?? resolvedPlannedRuntimeFrameOffset(context: context, snapshot: snapshot)
        let frame = offset.flatMap { plannedFrame(runtimeFrame: snapshot.currentFrame, runtimeFrameOffset: $0) }
        return frame.flatMap { sampleTimePositionResolver?.position(atFrame: $0) }
    }

    private func resolvedSampleTimePosition(
        context: AudioRuntimeTraceContext?,
        currentFrame: UInt64
    ) -> PlaybackSongSampleTimePosition? {
        let offset = plannedRuntimeFrameOffset ?? resolvedPlannedRuntimeFrameOffset(
            context: context,
            currentFrame: currentFrame
        )
        let frame = offset.flatMap { plannedFrame(runtimeFrame: currentFrame, runtimeFrameOffset: $0) }
        return frame.flatMap { sampleTimePositionResolver?.position(atFrame: $0) }
    }

    private func plannedFrame(runtimeFrame: UInt64, runtimeFrameOffset: Int) -> Int? {
        guard let frame = intFrame(runtimeFrame) else {
            return nil
        }
        let (value, overflow) = frame.subtractingReportingOverflow(runtimeFrameOffset)
        return overflow ? nil : value
    }

    private func plannedFrame(for publishedPosition: PlaybackFollowPosition) -> Int? {
        if let sampleTimeFrame = publishedPosition.sampleTimeFrame {
            return sampleTimeFrame
        }
        return adapterEventPlan.plannedFrame(matching: traceContext(
            position: publishedPosition.position,
            tickInRow: publishedPosition.tickInRow
        ))
    }

    private func plannedPosition(for publishedPosition: PlaybackFollowPosition) -> PlaybackSongSampleTimePosition? {
        plannedFrame(for: publishedPosition).flatMap { sampleTimePositionResolver?.position(atFrame: $0) }
    }

    private func plannedPosition(for context: AudioRuntimeTraceContext) -> PlaybackSongSampleTimePosition? {
        adapterEventPlan.plannedFrame(matching: context).flatMap { sampleTimePositionResolver?.position(atFrame: $0) }
    }

    private func positionMismatch(
        context: AudioRuntimeTraceContext?,
        cMixerPosition: PlaybackSongSampleTimePosition?
    ) -> Bool? {
        guard let context,
              let cMixerPosition,
              let orderIndex = context.orderIndex,
              let patternIndex = context.patternIndex,
              let rowIndex = context.rowIndex else {
            return nil
        }
        let tickInRow = context.tickInRow ?? 0
        return cMixerPosition.source.orderIndex != orderIndex ||
            cMixerPosition.source.patternIndex != patternIndex ||
            cMixerPosition.source.rowIndex != rowIndex ||
            cMixerPosition.tickInRow != tickInRow
    }

    private func rowTransitionDeltaCategory(
        delta: Int?,
        context: AudioRuntimeTraceContext?,
        cMixerPosition: PlaybackSongSampleTimePosition?,
        sampleRate: Double
    ) -> String? {
        guard let delta else {
            return nil
        }
        let magnitude = abs(delta)
        if magnitude == 0 {
            return "exact"
        }
        if magnitude <= 1 {
            return "within_one_frame"
        }
        if let context,
           let cMixerPosition {
            if cMixerPosition.source.orderIndex != context.orderIndex ||
                cMixerPosition.source.patternIndex != context.patternIndex ||
                cMixerPosition.source.rowIndex != context.rowIndex {
                return "different_row_or_order"
            }
            if cMixerPosition.tickInRow != (context.tickInRow ?? 0) {
                return "same_row_different_tick"
            }
        }
        let tickFrames: Int?
        if let cMixerPosition {
            tickFrames = max(1, cMixerPosition.rowDurationFrames / max(1, cMixerPosition.effectiveSpeed))
        } else {
            let bpm = context?.bpm ?? PlaybackTiming.xmDefault.bpm
            tickFrames = sampleRate.isFinite && sampleRate > 0
                ? Int((sampleRate * 2.5 / Double(max(1, bpm))).rounded(.up))
                : nil
        }
        if let tickFrames,
           magnitude < max(1, tickFrames) {
            return "within_tick"
        }
        return "different_row_or_order"
    }

    private func resolvedPlannedRuntimeFrameOffset(
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> Int? {
        resolvedPlannedRuntimeFrameOffset(context: context, currentFrame: snapshot.currentFrame)
    }

    private func resolvedPlannedRuntimeFrameOffset(
        context: AudioRuntimeTraceContext?,
        currentFrame: UInt64
    ) -> Int? {
        if let plannedRuntimeFrameOffset {
            return plannedRuntimeFrameOffset
        }
        guard currentFrame <= UInt64(Int.max),
              let plannedRowStartFrame = adapterEventPlan.plannedRowStartFrame(matching: context) else {
            return nil
        }
        let offset = Int(currentFrame) - plannedRowStartFrame
        plannedRuntimeFrameOffset = offset
        return offset
    }

    private func eventApplicationTiming(
        plannedRuntimeFrame: Int?,
        runtimeApplicationFrame: UInt64,
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> String {
        eventApplicationTiming(
            plannedRuntimeFrame: plannedRuntimeFrame,
            runtimeApplicationFrame: runtimeApplicationFrame,
            context: context,
            callbackEndFrame: snapshot.callbackEndFrame
        )
    }

    private func eventApplicationTiming(
        plannedRuntimeFrame: Int?,
        runtimeApplicationFrame: UInt64,
        context: AudioRuntimeTraceContext?,
        callbackEndFrame: UInt64?
    ) -> String {
        if let plannedRuntimeFrame,
           let applicationFrame = intFrame(runtimeApplicationFrame),
           applicationFrame == plannedRuntimeFrame {
            return "exact_frame"
        }
        if callbackEndFrame == runtimeApplicationFrame {
            return "callback_start"
        }
        if context?.tickInRow == 0 {
            return "row_boundary"
        }
        if context?.tickInRow != nil {
            return "tick_boundary"
        }
        return "unknown"
    }

    private func diagnosticCategory(for event: RuntimeCMixerAdapterEvent) -> String {
        if event.categories.contains("key_off") {
            return "key_off_fadeout"
        }
        if event.categories.contains("hxy_global_volume_update") {
            return "hxy_global_volume"
        }
        if event.categories.contains("note_cut") ||
            event.categories.contains("note_delay") ||
            event.categories.contains("retrigger") {
            return "ecx_edx_e9x"
        }
        switch event.action {
        case .noteTrigger:
            return "note_trigger"
        case .gainPanUpdate:
            return "gain_pan_update"
        case .stepUpdate:
            return "step_pitch_update"
        case .noteCut:
            return "ecx_edx_e9x"
        }
    }

    private func safeAdding(_ lhs: Int, _ rhs: Int) -> Int? {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : value
    }

    private func delta(runtimeFrame: UInt64, plannedFrame: Int) -> Int? {
        guard let applicationFrame = intFrame(runtimeFrame) else {
            return nil
        }
        let (value, overflow) = applicationFrame.subtractingReportingOverflow(plannedFrame)
        return overflow ? nil : value
    }

    private func intFrame(_ frame: UInt64) -> Int? {
        guard frame <= UInt64(Int.max) else {
            return nil
        }
        return Int(frame)
    }

    private func seconds(frame: Int?, sampleRate: Double) -> Double? {
        guard let frame,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }
        return Double(frame) / sampleRate
    }

    private func seconds(frame: UInt64?, sampleRate: Double) -> Double? {
        guard let frame,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }
        return Double(frame) / sampleRate
    }

    private func audioGraphDiagnostics(snapshot: RuntimeCMixerRenderSnapshot) -> RuntimeCMixerAudioGraphDiagnostics {
        let outputDevice = RuntimeCMixerAudioOutputDeviceDiagnostics.currentDefaultOutputDevice()
        return RuntimeCMixerAudioGraphDiagnostics(
            snapshot: snapshot,
            routeLabel: routeLabel,
            outputDevice: outputDevice,
            outputHostRunning: coreAudioOutputHost.isRunning
        )
    }

    private func updateAudioGraphChangeCounters(_ graph: RuntimeCMixerAudioGraphDiagnostics) -> RuntimeCMixerAudioGraphChanges {
        let formatChanged: Bool
        if lastAudioGraphWasPrepared,
           graph.engineRunning,
           let lastAudioGraphFormatSignature {
            formatChanged = lastAudioGraphFormatSignature != graph.formatSignature
        } else {
            formatChanged = false
        }
        if formatChanged {
            audioGraphFormatChangeCount &+= 1
        }
        lastAudioGraphFormatSignature = graph.formatSignature
        lastAudioGraphWasPrepared = graph.engineRunning

        let routeChanged: Bool
        if let lastAudioOutputRouteSignature {
            routeChanged = lastAudioOutputRouteSignature != graph.routeSignature
        } else {
            routeChanged = false
        }
        if routeChanged {
            audioOutputRouteChangeCount &+= 1
        }
        lastAudioOutputRouteSignature = graph.routeSignature
        let previousGraph = lastAudioGraphDiagnostics
        let changes = RuntimeCMixerAudioGraphChanges(
            formatChanged: formatChanged,
            routeChanged: routeChanged,
            outputDeviceChanged: previousGraph.map {
                $0.outputDeviceIdentitySignature != graph.outputDeviceIdentitySignature
            } ?? false,
            outputSampleRateChanged: previousGraph.map {
                Self.sampleRateChanged($0.hardwareNominalSampleRate, graph.hardwareNominalSampleRate)
            } ?? false,
            outputChannelCountChanged: previousGraph.map {
                $0.cMixerRenderChannelCount != graph.cMixerRenderChannelCount
            } ?? false,
            hardwareIOBufferDurationChanged: previousGraph.map {
                Self.doubleChanged($0.hardwareIOBufferDuration, graph.hardwareIOBufferDuration)
            } ?? false,
            outputNodeFormatChanged: false
        )
        lastAudioGraphDiagnostics = graph
        return changes
    }

    private static func sampleRateChanged(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs,
              let rhs else {
            return lhs != nil || rhs != nil
        }
        return !RuntimeCMixerFormatDiagnostics.sampleRatesMatch(lhs, rhs)
    }

    private static func doubleChanged(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs,
              let rhs else {
            return lhs != nil || rhs != nil
        }
        return lhs.isFinite && rhs.isFinite ? abs(lhs - rhs) > 0.000_001 : lhs != rhs
    }

    private func drainAppliedRuntimeAdapterEvents(drainAllAvailable: Bool = false) {
        guard !coreAudioOutputHost.isRunning else {
            return
        }
        repeat {
            let diagnostics = renderCore.drainAppliedAdapterEventDiagnostics()
            guard !diagnostics.isEmpty else {
                return
            }
            for diagnostic in diagnostics {
                if !consumedAdapterEventIDs.contains(diagnostic.event.id) {
                    consumedAdapterEventIDs.insert(diagnostic.event.id)
                    eventCounters.consumedPlannedEventCount &+= 1
                    consumedAdapterEventCategories.formUnion(diagnostic.event.categories)
                }
                recordAppliedRuntimeAdapterEvent(diagnostic)
            }
        } while drainAllAvailable
    }

    private func recordAppliedRuntimeAdapterEvent(_ diagnostic: RuntimeCMixerAppliedAdapterEventDiagnostic) {
        let eventContext = contextWithFallbackChannel(diagnostic.context, channel: diagnostic.event.channelIndex)
        switch diagnostic.result {
        case let .noteTrigger(result):
            let timing = eventTimingTraceFields(for: diagnostic)
            if let channelStop = result.channelStopBeforeAdd {
                eventCounters.replacementRampCount &+= 1
                recordRuntimeEvent(
                    action: "c_mixer_stop_channel_ramped",
                    context: eventContext,
                    targetScope: "channel",
                    snapshotBefore: channelStop.snapshotBefore,
                    snapshot: channelStop.snapshotAfter,
                    succeeded: true,
                    stoppedVoiceCount: nil,
                    rampedVoiceCount: channelStop.rampedVoiceCount,
                    replacementRampFrames: channelStop.replacementRampFrames,
                    replacementVoicesOverlap: channelStop.replacementVoicesOverlap,
                    replacementOldVoiceState: channelStop.replacementOldVoiceState,
                    replacementRampStartState: channelStop.replacementRampStartState,
                    replacementRampTargetGain: channelStop.replacementRampTargetGain,
                    replacementNewVoiceIndex: channelStop.replacementNewVoiceIndex,
                    replacementNewVoiceChannelTag: channelStop.replacementNewVoiceChannelTag,
                    replacementGainPanAppliedBeforeRamp: channelStop.replacementGainPanAppliedBeforeRamp,
                    replacementStepAppliedBeforeRamp: channelStop.replacementStepAppliedBeforeRamp,
                    replacementKeyOffAppliedBeforeRamp: channelStop.replacementKeyOffAppliedBeforeRamp,
                    replacementFadeoutAppliedBeforeRamp: channelStop.replacementFadeoutAppliedBeforeRamp,
                    targetVoiceIndex: channelStop.replacementOldVoiceState?.voiceIndex,
                    runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                    adapterEventCategory: "replacement",
                    eventTiming: eventTimingTraceFields(for: diagnostic, runtimeEventCategory: "replacement_stop_ramp"),
                    reason: channelStop.reason
                )
            }
            eventCounters.cMixerAddVoiceCount &+= 1
            recordRuntimeEvent(
                action: "c_mixer_add_voice",
                context: eventContext,
                targetScope: "channel",
                snapshotBefore: result.snapshotBefore,
                snapshot: result.snapshotAfter,
                succeeded: result.succeeded,
                targetVoiceIndex: result.newVoiceIndex,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: diagnostic.event.primaryCategory,
                eventTiming: timing,
                reason: result.reason ?? "runtime_c_mixer_adapter_plan_note_trigger"
            )
            if !result.succeeded {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }

        case let .gainPanUpdate(result):
            recordRuntimeUpdateCounters(result)
            recordRuntimeUpdateEvent(
                result,
                context: eventContext,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: diagnostic.event.primaryCategory,
                eventTiming: eventTimingTraceFields(for: diagnostic)
            )
            if result.targetVoiceIndex == nil {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }

        case let .stepUpdate(result):
            recordRuntimeUpdateCounters(result)
            recordRuntimeUpdateEvent(
                result,
                context: eventContext,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: diagnostic.event.primaryCategory,
                eventTiming: eventTimingTraceFields(for: diagnostic)
            )
            if result.targetVoiceIndex == nil {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }

        case let .noteCut(result):
            recordRuntimeEvent(
                action: "c_mixer_adapter_note_cut",
                context: eventContext,
                targetScope: "channel",
                snapshotBefore: result.snapshotBefore,
                snapshot: result.snapshotAfter,
                succeeded: result.succeeded,
                targetVoiceIndex: result.targetVoiceIndex,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: diagnostic.event.primaryCategory,
                eventTiming: eventTimingTraceFields(for: diagnostic),
                reason: result.reason
            )
            if result.targetVoiceIndex == nil {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }
        }
    }

    private func eventTimingTraceFields(
        for diagnostic: RuntimeCMixerAppliedAdapterEventDiagnostic,
        runtimeEventCategory: String? = nil
    ) -> RuntimeCMixerEventTimingTraceFields {
        RuntimeCMixerEventTimingTraceFields(
            runtimeEventCategory: runtimeEventCategory ?? diagnosticCategory(for: diagnostic.event),
            plannedEventID: diagnostic.event.id,
            plannedSourceOrderIndex: diagnostic.event.source.orderIndex,
            plannedSourcePatternIndex: diagnostic.event.source.patternIndex,
            plannedSourceRowIndex: diagnostic.event.source.rowIndex,
            plannedSourceTickInRow: diagnostic.event.syntheticTick,
            plannedSourceChannelIndex: diagnostic.event.channelIndex,
            plannedEventFrame: diagnostic.event.scheduledFrame,
            plannedRuntimeFrame: diagnostic.plannedRuntimeFrame,
            plannedRuntimeFrameOffset: diagnostic.plannedRuntimeFrame - diagnostic.event.scheduledFrame,
            runtimeApplicationFrame: diagnostic.appliedFrame,
            eventFrameDelta: diagnostic.eventFrameDelta,
            eventApplicationTiming: diagnostic.eventApplicationTiming,
            eventAppliedFrame: diagnostic.appliedFrame,
            inCallbackOffset: diagnostic.inCallbackOffset,
            plannedVsAppliedDelta: diagnostic.eventFrameDelta,
            sameFrameBurstSize: diagnostic.sameFrameBurstSize,
            sameFrameBurst: diagnostic.sameFrameBurst,
            adapterActiveEventIndex: diagnostic.adapterActiveEventIndex,
            adapterCurrentEventIndexBefore: diagnostic.adapterCurrentEventIndexBefore,
            adapterCurrentEventIndexAfter: diagnostic.adapterCurrentEventIndexAfter,
            adapterChannelAssociationRetained: diagnostic.adapterChannelAssociationRetained,
            adapterSustainedVoiceUpdate: diagnostic.adapterSustainedVoiceUpdate,
            callbackIndex: diagnostic.callbackIndex,
            callbackRequestedFrameCount: diagnostic.callbackRequestedFrameCount,
            callbackStartFrame: diagnostic.callbackStartFrame,
            callbackEndFrame: diagnostic.callbackEndFrame
        )
    }

    func trigger(_ request: AudioVoiceRequest) {
        trigger(request, context: nil)
    }

    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?) {
        drainAppliedRuntimeAdapterEvents()
        if isFallbackActive {
            recordRuntimeEvent(
                action: "unsupported_runtime_action",
                context: context,
                targetScope: "channel",
                snapshot: renderCore.snapshot(),
                succeeded: nil,
                reason: "runtime_c_mixer_fallback_av_audio_active"
            )
            fallbackAudioEngine.trigger(request)
            return
        }
        if startsOutputHostOnDemand {
            prepareIfNeeded()
        }
        let fallbackReason = recordSimpleRuntimeFallbackIfNeeded()
        let result = renderCore.triggerWithDiagnostics(request)
        if let channelStop = result.channelStopBeforeAdd {
            eventCounters.replacementRampCount &+= 1
            recordRuntimeEvent(
                action: "c_mixer_stop_channel_ramped",
                context: contextWithFallbackChannel(context, channel: channelStop.channel),
                targetScope: "channel",
                snapshotBefore: channelStop.snapshotBefore,
                snapshot: channelStop.snapshotAfter,
                succeeded: true,
                stoppedVoiceCount: nil,
                rampedVoiceCount: channelStop.rampedVoiceCount,
                replacementRampFrames: channelStop.replacementRampFrames,
                replacementVoicesOverlap: channelStop.replacementVoicesOverlap,
                replacementOldVoiceState: channelStop.replacementOldVoiceState,
                replacementRampStartState: channelStop.replacementRampStartState,
                replacementRampTargetGain: channelStop.replacementRampTargetGain,
                replacementNewVoiceIndex: channelStop.replacementNewVoiceIndex,
                replacementNewVoiceChannelTag: channelStop.replacementNewVoiceChannelTag,
                replacementGainPanAppliedBeforeRamp: channelStop.replacementGainPanAppliedBeforeRamp,
                replacementStepAppliedBeforeRamp: channelStop.replacementStepAppliedBeforeRamp,
                replacementKeyOffAppliedBeforeRamp: channelStop.replacementKeyOffAppliedBeforeRamp,
                replacementFadeoutAppliedBeforeRamp: channelStop.replacementFadeoutAppliedBeforeRamp,
                targetVoiceIndex: channelStop.replacementOldVoiceState?.voiceIndex,
                runtimeEventSource: simpleRuntimeEventSource().rawValue,
                adapterEventCategory: nil,
                runtimeEventFallbackReason: fallbackReason,
                reason: channelStop.reason
            )
        }
        eventCounters.cMixerAddVoiceCount &+= 1
        recordRuntimeEvent(
            action: "c_mixer_add_voice",
            context: context,
            targetScope: "channel",
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: result.succeeded,
            targetVoiceIndex: result.newVoiceIndex,
            runtimeEventSource: simpleRuntimeEventSource().rawValue,
            adapterEventCategory: nil,
            runtimeEventFallbackReason: fallbackReason,
            reason: result.reason
        )
        guard result.succeeded else {
            logger.debug("Experimental C mixer runtime ignored an unplayable trigger")
            return
        }
        guard startsOutputHostOnDemand else {
            return
        }
        if !startEngineIfNeeded() {
            isFallbackActive = true
            fallbackAudioEngine.trigger(request)
        }
    }

    func update(channel: Int, controls: AudioChannelControls) {
        update(channel: channel, controls: controls, context: nil)
    }

    func update(channel: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?) {
        drainAppliedRuntimeAdapterEvents()
        if isFallbackActive {
            fallbackAudioEngine.update(channel: channel, controls: controls)
        } else {
            let fallbackReason = recordSimpleRuntimeFallbackIfNeeded()
            let result = renderCore.updateWithDiagnostics(channel: channel, controls: controls, context: context)
            recordRuntimeUpdateCounters(result)
            recordRuntimeUpdateEvent(
                result,
                context: contextWithFallbackChannel(context, channel: channel),
                runtimeEventSource: simpleRuntimeEventSource().rawValue,
                adapterEventCategory: nil,
                runtimeEventFallbackReason: fallbackReason
            )
        }
    }

    private func recordRuntimeUpdateCounters(_ result: RuntimeCMixerUpdateResult) {
        if result.gainPanAttempted {
            eventCounters.gainPanUpdateCount &+= 1
        }
        if result.stepAttempted {
            eventCounters.stepUpdateCount &+= 1
        }
        if result.epsilonSuppressedGain {
            eventCounters.updateSuppressedEpsilonGainCount &+= 1
        }
        if result.epsilonSuppressedPan {
            eventCounters.updateSuppressedEpsilonPanCount &+= 1
        }
        if result.epsilonSuppressedStep {
            eventCounters.updateSuppressedEpsilonStepCount &+= 1
        }
        if result.disposition == "update_suppressed_no_change" {
            eventCounters.updateSuppressedNoChangeCount &+= 1
        }
        if result.appliedAfterEpsilonFilter {
            eventCounters.updateAppliedAfterEpsilonFilterCount &+= 1
        }
    }

    private func recordRuntimeUpdateEvent(
        _ result: RuntimeCMixerUpdateResult,
        context: AudioRuntimeTraceContext?,
        runtimeEventSource: String?,
        adapterEventCategory: String?,
        eventTiming: RuntimeCMixerEventTimingTraceFields? = nil,
        runtimeEventFallbackReason: String? = nil
    ) {
        recordRuntimeEvent(
            action: result.traceAction,
            context: context,
            targetScope: "channel",
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: result.succeeded,
            targetVoiceIndex: result.targetVoiceIndex,
            gainBefore: result.gainBefore,
            gainAfter: result.gainAfter,
            panBefore: result.panBefore,
            panAfter: result.panAfter,
            sampleStepBefore: result.sampleStepBefore,
            sampleStepAfter: result.sampleStepAfter,
            updateDisposition: result.disposition,
            updateType: result.updateType,
            updateEpsilon: result.updateEpsilon,
            gainRequested: result.gainRequested,
            panRequested: result.panRequested,
            sampleStepRequested: result.sampleStepRequested,
            gainDelta: result.gainDelta,
            panDelta: result.panDelta,
            sampleStepDelta: result.sampleStepDelta,
            gainUpdateStatus: result.gainUpdateStatus,
            panUpdateStatus: result.panUpdateStatus,
            sampleStepUpdateStatus: result.sampleStepUpdateStatus,
            runtimeEventSource: runtimeEventSource,
            adapterEventCategory: adapterEventCategory,
            eventTiming: eventTiming,
            runtimeEventFallbackReason: runtimeEventFallbackReason,
            reason: result.reason
        )
    }

    func stop(channel: Int) {
        stop(channel: channel, context: nil)
    }

    func stop(channel: Int, context: AudioRuntimeTraceContext?) {
        drainAppliedRuntimeAdapterEvents()
        let result = renderCore.stopChannelWithDiagnostics(channel, reason: "channel_stop")
        eventCounters.stopChannelCount &+= 1
        recordRuntimeEvent(
            action: "c_mixer_stop_channel",
            context: contextWithFallbackChannel(context, channel: channel),
            targetScope: "channel",
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: true,
            stoppedVoiceCount: result.stoppedVoiceCount,
            reason: result.reason
        )
        if isFallbackActive {
            fallbackAudioEngine.stop(channel: channel)
        }
    }

    func stopAll() {
        stopAll(context: nil, reason: "transport_stop_all")
    }

    func stopAll(context: AudioRuntimeTraceContext?, reason: String) {
        coreAudioOutputHost.stop()
        drainAppliedRuntimeAdapterEvents(drainAllAvailable: true)
        let result = renderCore.stopAllWithDiagnostics(reason: reason)
        eventCounters.clearAllCount &+= 1
        recordRuntimeEvent(
            action: "c_mixer_clear_all",
            context: context,
            targetScope: "all_channels",
            targetedAllVoices: result.targetedAllVoices,
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: true,
            stoppedVoiceCount: result.stoppedVoiceCount,
            reason: result.reason
        )
        if isFallbackActive {
            fallbackAudioEngine.stopAll()
        }
        finishRuntimeCaptureIfNeeded(reason: reason)
        resetRuntimeAdapterEventConsumption()
    }

    func recordTransition(
        previousContext: AudioRuntimeTraceContext?,
        context: AudioRuntimeTraceContext?,
        phase: String,
        reason: String
    ) {
        if coreAudioOutputHost.isRunning {
            recordRunningRuntimeTransition(
                previousContext: previousContext,
                context: context,
                phase: phase,
                reason: reason
            )
            return
        }
        drainAppliedRuntimeAdapterEvents()
        let snapshot = renderCore.snapshot()
        let eventTiming = transitionTimingTraceFields(context: context, snapshot: snapshot)
        let transition: RuntimeCMixerTransitionTraceFields
        let action: String
        switch phase {
        case "after_events":
            action = "row_transition_after_events"
            let updateCount = eventCounters.gainPanUpdateCount &+ eventCounters.stepUpdateCount
            let replacementDelta: UInt64?
            let updateDelta: UInt64?
            let snapshotBefore: RuntimeCMixerRenderSnapshot?
            if let pendingTransition,
               pendingTransition.nextContext?.orderIndex == context?.orderIndex,
               pendingTransition.nextContext?.patternIndex == context?.patternIndex,
               pendingTransition.nextContext?.rowIndex == context?.rowIndex {
                replacementDelta = eventCounters.replacementRampCount &- pendingTransition.replacementRampCount
                updateDelta = updateCount &- pendingTransition.updateCount
                snapshotBefore = pendingTransition.snapshot
            } else {
                replacementDelta = nil
                updateDelta = nil
                snapshotBefore = nil
            }
            transition = RuntimeCMixerTransitionTraceFields(
                previousContext: previousContext,
                nextContext: context,
                phase: phase,
                runtimeFrame: snapshot.currentFrame,
                replacementRampCount: replacementDelta,
                updateCount: updateDelta
            )
            recordRuntimeEvent(
                action: action,
                context: context,
                targetScope: "none",
                snapshotBefore: snapshotBefore,
                snapshot: snapshot,
                succeeded: nil,
                eventTiming: eventTiming,
                transition: transition,
                reason: reason
            )
            pendingTransition = nil
            return
        default:
            action = "row_transition"
            let updateCount = eventCounters.gainPanUpdateCount &+ eventCounters.stepUpdateCount
            pendingTransition = RuntimeCMixerPendingTransition(
                previousContext: previousContext,
                nextContext: context,
                snapshot: snapshot,
                replacementRampCount: eventCounters.replacementRampCount,
                updateCount: updateCount
            )
            transition = RuntimeCMixerTransitionTraceFields(
                previousContext: previousContext,
                nextContext: context,
                phase: phase,
                runtimeFrame: snapshot.currentFrame,
                replacementRampCount: nil,
                updateCount: nil
            )
        }
        recordRuntimeEvent(
            action: action,
            context: context,
            targetScope: "none",
            snapshot: snapshot,
            succeeded: nil,
            eventTiming: eventTiming,
            transition: transition,
            reason: reason
        )
    }

    func recordPublishedPlaybackFollowPosition(
        timerContext: AudioRuntimeTraceContext?,
        publishedPosition: PlaybackFollowPosition,
        publicationDisabled: Bool
    ) {
        if publicationDisabled {
            playbackFollowPublicationSuppressedCount &+= 1
        } else {
            playbackFollowPublicationCount &+= 1
        }
        if coreAudioOutputHost.isRunning {
            recordRuntimeEventWithoutRenderSnapshot(
                action: "playback_follow_position_published",
                context: timerContext,
                publishedPlaybackFollowPosition: publishedPosition,
                playbackFollowPublicationDisabled: publicationDisabled,
                reason: "playback_follow_position_published"
            )
            return
        }
        drainAppliedRuntimeAdapterEvents()
        recordRuntimeEvent(
            action: "playback_follow_position_published",
            context: timerContext,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: nil,
            publishedPlaybackFollowPosition: publishedPosition,
            playbackFollowPublicationDisabled: publicationDisabled,
            reason: "playback_follow_position_published"
        )
    }

    private func recordRunningRuntimeTransition(
        previousContext: AudioRuntimeTraceContext?,
        context: AudioRuntimeTraceContext?,
        phase: String,
        reason: String
    ) {
        let currentFrame = renderCore.realtimeCurrentFrame
        let action = phase == "after_events" ? "row_transition_after_events" : "row_transition"
        let eventTiming = transitionTimingTraceFields(context: context, currentFrame: currentFrame)
        let transition = RuntimeCMixerTransitionTraceFields(
            previousContext: previousContext,
            nextContext: context,
            phase: phase,
            runtimeFrame: currentFrame,
            replacementRampCount: nil,
            updateCount: nil
        )
        recordRuntimeEventWithoutRenderSnapshot(
            action: action,
            context: context,
            eventTiming: eventTiming,
            transition: transition,
            reason: reason
        )
    }

    func reset() {
        drainAppliedRuntimeAdapterEvents()
        stopAll()
        coreAudioOutputHost.reset()
        fallbackAudioEngine.reset()
        isFallbackActive = false
        isPrepared = false
        recordRuntimeEvent(
            action: "backend_reset",
            context: nil,
            targetScope: "all_channels",
            targetedAllVoices: true,
            snapshot: renderCore.snapshot(),
            succeeded: true,
            reason: "runtime_c_mixer_backend_reset"
        )
    }

    private func prepareIfNeeded() {
        guard !isPrepared else {
            return
        }
        let status = coreAudioOutputHost.prepare()
        isPrepared = status == noErr
        recordRuntimeEvent(
            action: status == noErr ? "backend_prepared" : "backend_prepare_failed",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: status == noErr,
            reason: status == noErr
                ? "runtime_c_mixer_coreaudio_output_unit_prepared"
                : "runtime_c_mixer_coreaudio_output_unit_prepare_failed_status_\(status)"
        )
    }

    private func startEngineIfNeeded() -> Bool {
        guard !coreAudioOutputHost.isRunning else {
            return true
        }
        let status = coreAudioOutputHost.start()
        guard status == noErr else {
            logger.error(
                "Experimental C mixer CoreAudio output unit start succeeded=false falling_back=true status=\(status, privacy: .public)"
            )
            renderCore.stopAll()
            recordRuntimeEvent(
                action: "backend_start_failed",
                context: nil,
                targetScope: "none",
                snapshot: renderCore.snapshot(),
                succeeded: false,
                reason: "runtime_c_mixer_coreaudio_output_unit_start_failed_status_\(status)"
            )
            return false
        }
        isPrepared = true
        audioEngineRestartCount &+= 1
        logger.info(
            "Experimental C mixer CoreAudio output unit start succeeded=true sample_rate=\(self.format.sampleRate, privacy: .public) channel_count=\(self.format.channelCount, privacy: .public)"
        )
        recordRuntimeEvent(
            action: "backend_start",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: true,
            reason: "runtime_c_mixer_coreaudio_output_unit_started"
        )
        return true
    }

    private func finishRuntimeCaptureIfNeeded(reason: String) {
        guard let capture = renderCore.captureBlockSnapshotForWriting() else {
            return
        }
        let captureAction: String
        let writeSucceeded: Bool
        let writeError: String?
        let captureReason: String
        do {
            try RuntimeCMixerCaptureWAVWriter.write(capture)
            writeSucceeded = true
            writeError = nil
            captureAction = capture.snapshot.truncated ? "capture_truncated" : "capture_written"
            captureReason = capture.snapshot.truncated
                ? "runtime_c_mixer_capture_truncated"
                : "runtime_c_mixer_capture_finished_\(reason)"
        } catch {
            logger.error(
                "Runtime C mixer capture write failed path_name=\(capture.configuration.pathName, privacy: .public) error=capture_wav_write_failed"
            )
            writeSucceeded = false
            writeError = "capture_wav_write_failed"
            captureAction = "capture_write_failed"
            captureReason = "runtime_c_mixer_capture_write_failed"
        }
        recordRuntimeEvent(
            action: captureAction,
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: writeSucceeded,
            captureWriteSucceeded: writeSucceeded,
            captureWriteError: writeError,
            reason: captureReason
        )
        renderCore.resetCaptureBuffer()
    }

    private func simpleRuntimeEventSource() -> RuntimeCMixerAdapterEventSource {
        adapterEventPlan.generated ? .hybrid : .playbackEngineSimple
    }

    private func recordRuntimeEventWithoutRenderSnapshot(
        action: String,
        context: AudioRuntimeTraceContext?,
        eventTiming: RuntimeCMixerEventTimingTraceFields? = nil,
        transition: RuntimeCMixerTransitionTraceFields? = nil,
        publishedPlaybackFollowPosition: PlaybackFollowPosition? = nil,
        playbackFollowPublicationDisabled: Bool? = nil,
        reason: String?
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        let currentFrame = renderCore.realtimeCurrentFrame
        let sampleRate = renderCore.config.sampleRate
        let sampleTimePosition = sampleTimePositionTraceFields(
            context: context,
            currentFrame: currentFrame,
            sampleRate: sampleRate,
            isRowTransition: action.hasPrefix("row_transition") || eventTiming?.runtimeEventCategory == "row_transition"
        )
        let publishedPlannedFrame = publishedPlaybackFollowPosition.flatMap { plannedFrame(for: $0) }
        let publishedPlannedPosition = publishedPlaybackFollowPosition.flatMap { plannedPosition(for: $0) }
        let playbackEnginePlannedPosition = context.flatMap { plannedPosition(for: $0) }
        let playbackEnginePlannedFrame = context.flatMap { adapterEventPlan.plannedFrame(matching: $0) }
        let publishedToCMixerFrameDelta = publishedPlannedFrame.flatMap { publishedFrame in
            sampleTimePosition.cMixerSampleTimeFrame.map { $0 - publishedFrame }
        }
        let publishedToCMixerRowDelta = publishedPlannedPosition.flatMap { publishedPosition in
            sampleTimePosition.cMixerSampleTimeSyntheticRow.map { $0 - publishedPosition.syntheticRow }
        }
        let playbackEngineToPublishedFrameDelta = publishedPlannedFrame.flatMap { publishedFrame in
            playbackEnginePlannedFrame.map { publishedFrame - $0 }
        }
        let playbackEngineToPublishedRowDelta = publishedPlannedPosition.flatMap { publishedPosition in
            playbackEnginePlannedPosition.map { publishedPosition.syntheticRow - $0.syntheticRow }
        }
        let event = RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: runtimeAudioBackend.diagnosticName,
            runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
            adapterPlanGenerated: adapterEventPlan.generated,
            plannedEventCount: adapterEventPlan.plannedEventCount,
            consumedPlannedEventCount: Int(min(eventCounters.consumedPlannedEventCount, UInt64(Int.max))),
            skippedUnmatchedPlannedEventCount: Int(min(eventCounters.skippedUnmatchedPlannedEventCount, UInt64(Int.max))),
            runtimeRowOrderMapping: runtimeRowOrderMapping(for: context),
            adapterEventCategoriesConsumed: consumedAdapterEventCategories.sorted(),
            runtimeEventCategory: eventTiming?.runtimeEventCategory,
            plannedSourceOrderIndex: eventTiming?.plannedSourceOrderIndex,
            plannedSourcePatternIndex: eventTiming?.plannedSourcePatternIndex,
            plannedSourceRowIndex: eventTiming?.plannedSourceRowIndex,
            plannedSourceTickInRow: eventTiming?.plannedSourceTickInRow,
            plannedEventFrame: eventTiming?.plannedEventFrame,
            plannedRuntimeFrame: eventTiming?.plannedRuntimeFrame,
            plannedRuntimeFrameOffset: eventTiming?.plannedRuntimeFrameOffset,
            runtimeApplicationFrame: eventTiming?.runtimeApplicationFrame,
            eventFrameDelta: eventTiming?.eventFrameDelta,
            eventApplicationTiming: eventTiming?.eventApplicationTiming,
            eventAppliedFrame: eventTiming?.eventAppliedFrame,
            plannedVsAppliedDelta: eventTiming?.plannedVsAppliedDelta,
            experimentalCMixerEnabled: true,
            alternativeRuntimeOutputHostEnabled: runtimeAudioBackend.alternativeRuntimeOutputHostEnabled,
            runtimeOutputHostType: runtimeAudioBackend.runtimeOutputHostType,
            runtimeOutputHostPrepareStatus: coreAudioOutputHost.lastPrepareStatus.map(Int.init),
            runtimeOutputHostInitializeStatus: coreAudioOutputHost.lastInitializeStatus.map(Int.init),
            runtimeOutputHostStartStatus: coreAudioOutputHost.lastStartStatus.map(Int.init),
            runtimeOutputHostStopStatus: coreAudioOutputHost.lastStopStatus.map(Int.init),
            runtimeOutputHostLastErrorStatus: coreAudioOutputHost.lastErrorStatus.map(Int.init),
            sampleRate: sampleRate,
            selectedRuntimeSampleRate: runtimeSampleRateSelection?.sampleRate ?? sampleRate,
            cMixerRuntimeSampleRate: sampleRate,
            runtimeSampleRatePolicy: runtimeSampleRateSelection?.policy,
            runtimeSampleRateSource: runtimeSampleRateSelection?.source,
            runtimeSampleRateConfigurationWarning: runtimeSampleRateSelection?.configurationWarning,
            cMixerRenderSampleRate: sampleRate,
            cMixerRenderChannelCount: renderCore.config.channelCount,
            audioEngineRunning: coreAudioOutputHost.isRunning,
            cMixerRenderedFrames: sampleTimePosition.cMixerRenderedFrames,
            cMixerPlaybackSeconds: sampleTimePosition.cMixerPlaybackSeconds,
            cMixerSampleTimeFrame: sampleTimePosition.cMixerSampleTimeFrame,
            cMixerSampleTimePositionStatus: sampleTimePosition.cMixerSampleTimePositionStatus,
            cMixerSampleTimeOrderIndex: sampleTimePosition.cMixerSampleTimeOrderIndex,
            cMixerSampleTimePatternIndex: sampleTimePosition.cMixerSampleTimePatternIndex,
            cMixerSampleTimeRowIndex: sampleTimePosition.cMixerSampleTimeRowIndex,
            cMixerSampleTimeTickInRow: sampleTimePosition.cMixerSampleTimeTickInRow,
            playbackEngineOrderIndex: sampleTimePosition.playbackEngineOrderIndex,
            playbackEnginePatternIndex: sampleTimePosition.playbackEnginePatternIndex,
            playbackEngineRowIndex: sampleTimePosition.playbackEngineRowIndex,
            playbackEngineTickInRow: sampleTimePosition.playbackEngineTickInRow,
            playbackEngineToCMixerFrameDelta: sampleTimePosition.playbackEngineToCMixerFrameDelta,
            playbackEngineToCMixerPositionMismatch: sampleTimePosition.playbackEngineToCMixerPositionMismatch,
            rowTransitionDeltaCategory: sampleTimePosition.rowTransitionDeltaCategory,
            publishedPlaybackFollowPositionSource: publishedPlaybackFollowPosition?.source.rawValue,
            publishedPlaybackFollowOrderIndex: publishedPlaybackFollowPosition?.position.orderIndex,
            publishedPlaybackFollowPatternIndex: publishedPlaybackFollowPosition?.position.patternIndex,
            publishedPlaybackFollowRowIndex: publishedPlaybackFollowPosition?.position.rowIndex,
            publishedPlaybackFollowTickInRow: publishedPlaybackFollowPosition?.tickInRow,
            publishedPlaybackFollowSampleTimeFrame: publishedPlannedFrame,
            publishedPlaybackFollowPositionStatus: publishedPlaybackFollowPosition?.sampleTimeStatus ?? publishedPlannedPosition?.status,
            publishedPlaybackFollowSyntheticRow: publishedPlannedPosition?.syntheticRow ?? publishedPlaybackFollowPosition?.syntheticRow,
            publishedPlaybackFollowToCMixerFrameDelta: publishedToCMixerFrameDelta,
            publishedPlaybackFollowToCMixerRowDelta: publishedToCMixerRowDelta,
            playbackEngineToPublishedPlaybackFollowFrameDelta: playbackEngineToPublishedFrameDelta,
            playbackEngineToPublishedPlaybackFollowRowDelta: playbackEngineToPublishedRowDelta,
            playbackFollowPublicationDisabled: playbackFollowPublicationDisabled,
            playbackFollowPublicationCount: playbackFollowPublicationCount,
            playbackFollowPublicationSuppressedCount: playbackFollowPublicationSuppressedCount,
            channelCount: renderCore.config.channelCount,
            context: context,
            currentFrame: currentFrame,
            runtimeRenderedFrameCount: currentFrame,
            previousOrderIndex: transition?.previousContext?.orderIndex,
            previousPatternIndex: transition?.previousContext?.patternIndex,
            previousRowIndex: transition?.previousContext?.rowIndex,
            nextOrderIndex: transition?.nextContext?.orderIndex,
            nextPatternIndex: transition?.nextContext?.patternIndex,
            nextRowIndex: transition?.nextContext?.rowIndex,
            transitionPhase: transition?.phase,
            transitionRuntimeFrame: transition?.runtimeFrame,
            cMixerCallSucceeded: nil,
            reason: reason
        )
        traceWriter.record(event)
    }

    @discardableResult
    private func recordSimpleRuntimeFallbackIfNeeded() -> String? {
        guard !adapterEventPlan.generated else {
            return nil
        }
        eventCounters.fallbackToSimpleRuntimeEventCount &+= 1
        return "adapter_plan_unavailable"
    }

    private func recordRuntimeEvent(
        action: String,
        context: AudioRuntimeTraceContext?,
        targetScope: String,
        targetedAllVoices: Bool = false,
        snapshotBefore: RuntimeCMixerRenderSnapshot? = nil,
        snapshot: RuntimeCMixerRenderSnapshot,
        succeeded: Bool?,
        stoppedVoiceCount: Int? = nil,
        rampedVoiceCount: Int? = nil,
        replacementRampFrames: Int? = nil,
        replacementVoicesOverlap: Bool? = nil,
        replacementOldVoiceState: RuntimeCMixerReplacementVoiceState? = nil,
        replacementRampStartState: RuntimeCMixerReplacementVoiceState? = nil,
        replacementRampTargetGain: Float? = nil,
        replacementNewVoiceIndex: Int? = nil,
        replacementNewVoiceChannelTag: Int? = nil,
        replacementGainPanAppliedBeforeRamp: Bool? = nil,
        replacementStepAppliedBeforeRamp: Bool? = nil,
        replacementKeyOffAppliedBeforeRamp: Bool? = nil,
        replacementFadeoutAppliedBeforeRamp: Bool? = nil,
        targetVoiceIndex: Int? = nil,
        gainBefore: Float? = nil,
        gainAfter: Float? = nil,
        panBefore: Float? = nil,
        panAfter: Float? = nil,
        sampleStepBefore: Double? = nil,
        sampleStepAfter: Double? = nil,
        updateDisposition: String? = nil,
        updateType: String? = nil,
        updateEpsilon: Double? = nil,
        gainRequested: Float? = nil,
        panRequested: Float? = nil,
        sampleStepRequested: Double? = nil,
        gainDelta: Double? = nil,
        panDelta: Double? = nil,
        sampleStepDelta: Double? = nil,
        gainUpdateStatus: String? = nil,
        panUpdateStatus: String? = nil,
        sampleStepUpdateStatus: String? = nil,
        runtimeEventSource: String? = nil,
        adapterEventCategory: String? = nil,
        adapterPlanGenerationMS: Double? = nil,
        eventTiming: RuntimeCMixerEventTimingTraceFields? = nil,
        transition: RuntimeCMixerTransitionTraceFields? = nil,
        runtimeEventFallbackReason: String? = nil,
        publishedPlaybackFollowPosition: PlaybackFollowPosition? = nil,
        playbackFollowPublicationDisabled: Bool? = nil,
        captureWriteSucceeded: Bool? = nil,
        captureWriteError: String? = nil,
        reason: String?
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        let sampleTimePosition = sampleTimePositionTraceFields(
            context: context,
            snapshot: snapshot,
            isRowTransition: action.hasPrefix("row_transition") || eventTiming?.runtimeEventCategory == "row_transition"
        )
        let publishedPlannedFrame = publishedPlaybackFollowPosition.flatMap { plannedFrame(for: $0) }
        let publishedPlannedPosition = publishedPlaybackFollowPosition.flatMap { plannedPosition(for: $0) }
        let playbackEnginePlannedPosition = context.flatMap { plannedPosition(for: $0) }
        let playbackEnginePlannedFrame = context.flatMap { adapterEventPlan.plannedFrame(matching: $0) }
        let publishedToCMixerFrameDelta = publishedPlannedFrame.flatMap { publishedFrame in
            sampleTimePosition.cMixerSampleTimeFrame.map { $0 - publishedFrame }
        }
        let publishedToCMixerRowDelta = publishedPlannedPosition.flatMap { publishedPosition in
            sampleTimePosition.cMixerSampleTimeSyntheticRow.map { $0 - publishedPosition.syntheticRow }
        }
        let playbackEngineToPublishedFrameDelta = publishedPlannedFrame.flatMap { publishedFrame in
            playbackEnginePlannedFrame.map { publishedFrame - $0 }
        }
        let playbackEngineToPublishedRowDelta = publishedPlannedPosition.flatMap { publishedPosition in
            playbackEnginePlannedPosition.map { publishedPosition.syntheticRow - $0.syntheticRow }
        }
        let lifecycleSnapshot = snapshotBefore ?? snapshot
        let plannedSongEndFrame = adapterEventPlan.plannedSongEndFrame ?? lifecycleSnapshot.plannedSongEndFrame ?? snapshot.plannedSongEndFrame
        let plannedSongEndRuntimeFrame = lifecycleSnapshot.plannedSongEndRuntimeFrame ?? snapshot.plannedSongEndRuntimeFrame
        let runtimeFrameAtPlannedSongEnd = lifecycleSnapshot.runtimeFrameAtPlannedSongEnd ?? snapshot.runtimeFrameAtPlannedSongEnd
        let songEndStopFrame = lifecycleSnapshot.songEndStopFrame ?? snapshot.songEndStopFrame
        let songEndStopRuntimeFrame = lifecycleSnapshot.songEndStopRuntimeFrame ?? snapshot.songEndStopRuntimeFrame
        let runtimeFrameAtSongEndTailStop = lifecycleSnapshot.runtimeFrameAtSongEndTailStop ?? snapshot.runtimeFrameAtSongEndTailStop
        let stopReason = normalizedStopReason(action: action, reason: reason, snapshot: snapshot, snapshotBefore: snapshotBefore)
        let audioGraph = audioGraphDiagnostics(snapshot: snapshot)
        let audioGraphChanges = updateAudioGraphChangeCounters(audioGraph)
        let event = RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: runtimeAudioBackend.diagnosticName,
            runtimeEventSource: runtimeEventSource,
            adapterPlanGenerated: adapterEventPlan.generated,
            adapterPlanGenerationMS: adapterPlanGenerationMS,
            plannedEventCount: adapterEventPlan.plannedEventCount,
            consumedPlannedEventCount: Int(min(eventCounters.consumedPlannedEventCount, UInt64(Int.max))),
            skippedUnmatchedPlannedEventCount: Int(min(eventCounters.skippedUnmatchedPlannedEventCount, UInt64(Int.max))),
            runtimeRowOrderMapping: runtimeRowOrderMapping(for: context),
            adapterEventCategory: adapterEventCategory,
            adapterEventCategoriesConsumed: consumedAdapterEventCategories.sorted(),
            runtimeEventCategory: eventTiming?.runtimeEventCategory,
            plannedEventID: eventTiming?.plannedEventID,
            plannedSourceOrderIndex: eventTiming?.plannedSourceOrderIndex,
            plannedSourcePatternIndex: eventTiming?.plannedSourcePatternIndex,
            plannedSourceRowIndex: eventTiming?.plannedSourceRowIndex,
            plannedSourceTickInRow: eventTiming?.plannedSourceTickInRow,
            plannedSourceChannelIndex: eventTiming?.plannedSourceChannelIndex,
            plannedEventFrame: eventTiming?.plannedEventFrame,
            plannedRuntimeFrame: eventTiming?.plannedRuntimeFrame,
            plannedRuntimeFrameOffset: eventTiming?.plannedRuntimeFrameOffset,
            runtimeApplicationFrame: eventTiming?.runtimeApplicationFrame,
            eventFrameDelta: eventTiming?.eventFrameDelta,
            eventApplicationTiming: eventTiming?.eventApplicationTiming,
            eventAppliedFrame: eventTiming?.eventAppliedFrame,
            inCallbackOffset: eventTiming?.inCallbackOffset,
            plannedVsAppliedDelta: eventTiming?.plannedVsAppliedDelta,
            sameFrameBurstSize: eventTiming?.sameFrameBurstSize,
            sameFrameBurstID: eventTiming?.sameFrameBurst?.id,
            sameFrameBurstEventOrdinal: eventTiming?.sameFrameBurst?.eventOrdinal,
            sameFrameBurstCategories: eventTiming?.sameFrameBurst?.categories,
            sameFrameBurstAffectedChannels: eventTiming?.sameFrameBurst?.affectedChannels,
            sameFrameBurstNoteTriggerCount: eventTiming?.sameFrameBurst?.noteTriggerCount,
            sameFrameBurstReplacementRampCount: eventTiming?.sameFrameBurst?.replacementRampCount,
            sameFrameBurstGainPanUpdateCount: eventTiming?.sameFrameBurst?.gainPanUpdateCount,
            sameFrameBurstStepUpdateCount: eventTiming?.sameFrameBurst?.stepUpdateCount,
            sameFrameBurstNoteCutCount: eventTiming?.sameFrameBurst?.noteCutCount,
            sameFrameBurstKeyOffCount: eventTiming?.sameFrameBurst?.keyOffCount,
            sameFrameBurstGlobalVolumeUpdateCount: eventTiming?.sameFrameBurst?.globalVolumeUpdateCount,
            sameFrameBurstActiveVoiceCountBefore: eventTiming?.sameFrameBurst?.activeVoiceCountBefore,
            sameFrameBurstActiveVoiceCountAfter: eventTiming?.sameFrameBurst?.activeVoiceCountAfter,
            sameFrameBurstLoadedVoiceCountBefore: eventTiming?.sameFrameBurst?.loadedVoiceCountBefore,
            sameFrameBurstLoadedVoiceCountAfter: eventTiming?.sameFrameBurst?.loadedVoiceCountAfter,
            sameFrameBurstVoicesEnteringRampDown: eventTiming?.sameFrameBurst?.voicesEnteringRampDown,
            sameFrameBurstVoicesCompletingRampDown: eventTiming?.sameFrameBurst?.voicesCompletingRampDown,
            sameFrameBurstNewVoicesStarted: eventTiming?.sameFrameBurst?.newVoicesStarted,
            sameFrameBurstSustainedVoicesCarried: eventTiming?.sameFrameBurst?.sustainedVoicesCarried,
            sameFrameBurstAtOrderStart: eventTiming?.sameFrameBurst?.atOrderStart,
            sameFrameBurstAtRowTransition: eventTiming?.sameFrameBurst?.atRowTransition,
            adapterActiveEventIndex: eventTiming?.adapterActiveEventIndex,
            adapterCurrentEventIndexBefore: eventTiming?.adapterCurrentEventIndexBefore,
            adapterCurrentEventIndexAfter: eventTiming?.adapterCurrentEventIndexAfter,
            adapterChannelAssociationRetained: eventTiming?.adapterChannelAssociationRetained,
            adapterSustainedVoiceUpdate: eventTiming?.adapterSustainedVoiceUpdate,
            maxPlannedVsAppliedDelta: snapshot.maxPlannedVsAppliedDelta,
            appliedPlannedEventCount: snapshot.appliedPlannedEventCount,
            exactFrameAppliedEventCount: snapshot.exactFrameAppliedEventCount,
            callbackBoundaryAppliedEventCount: snapshot.callbackBoundaryAppliedEventCount,
            latePlannedEventCount: snapshot.latePlannedEventCount,
            fallbackToSimpleRuntimeEventCount: eventCounters.fallbackToSimpleRuntimeEventCount,
            runtimeEventFallbackReason: runtimeEventFallbackReason,
            experimentalCMixerEnabled: true,
            alternativeRuntimeOutputHostEnabled: runtimeAudioBackend.alternativeRuntimeOutputHostEnabled,
            runtimeOutputHostType: runtimeAudioBackend.runtimeOutputHostType,
            runtimeOutputHostPrepareStatus: coreAudioOutputHost.lastPrepareStatus.map(Int.init),
            runtimeOutputHostInitializeStatus: coreAudioOutputHost.lastInitializeStatus.map(Int.init),
            runtimeOutputHostStartStatus: coreAudioOutputHost.lastStartStatus.map(Int.init),
            runtimeOutputHostStopStatus: coreAudioOutputHost.lastStopStatus.map(Int.init),
            runtimeOutputHostLastErrorStatus: coreAudioOutputHost.lastErrorStatus.map(Int.init),
            sampleRate: snapshot.sampleRate,
            selectedRuntimeSampleRate: runtimeSampleRateSelection?.sampleRate ?? snapshot.sampleRate,
            cMixerRuntimeSampleRate: snapshot.sampleRate,
            runtimeSampleRatePolicy: runtimeSampleRateSelection?.policy,
            runtimeSampleRateSource: runtimeSampleRateSelection?.source,
            runtimeSampleRateConfigurationWarning: runtimeSampleRateSelection?.configurationWarning,
            cMixerRenderSampleRate: audioGraph.cMixerRenderSampleRate,
            cMixerRenderChannelCount: audioGraph.cMixerRenderChannelCount,
            audioSourceNodeRenderSampleRate: nil,
            audioSourceNodeChannelCount: nil,
            audioEngineMainMixerOutputSampleRate: nil,
            audioEngineMainMixerOutputChannelCount: nil,
            audioEngineMainMixerInputSampleRate: nil,
            audioEngineMainMixerInputChannelCount: nil,
            audioEngineMainMixerLatency: nil,
            audioEngineMainMixerOutputPresentationLatency: nil,
            audioEngineOutputNodeSampleRate: nil,
            audioEngineOutputNodeChannelCount: nil,
            audioEngineOutputNodeLatency: nil,
            audioEngineOutputNodeOutputPresentationLatency: nil,
            audioHardwareNominalSampleRate: audioGraph.hardwareNominalSampleRate,
            audioHardwareDeviceID: audioGraph.outputDeviceID,
            audioHardwareDeviceUIDHash: audioGraph.outputDeviceUIDHash,
            audioOutputRouteLabel: audioGraph.routeLabel,
            audioHardwareIOBufferFrameSize: audioGraph.hardwareIOBufferFrameSize,
            audioHardwareIOBufferDuration: audioGraph.hardwareIOBufferDuration,
            audioHardwareLatencyFrames: audioGraph.hardwareLatencyFrames,
            audioHardwareLatencyDuration: audioGraph.hardwareLatencyDuration,
            audioHardwareSafetyOffsetFrames: audioGraph.hardwareSafetyOffsetFrames,
            audioHardwareSafetyOffsetDuration: audioGraph.hardwareSafetyOffsetDuration,
            audioHardwareTransportType: audioGraph.hardwareTransportType,
            audioHardwareTransportTypeName: audioGraph.hardwareTransportTypeName,
            audioEngineRunning: audioGraph.engineRunning,
            audioEngineSourceNodeAttached: false,
            audioEngineSourceNodeConnected: false,
            audioEngineMainMixerConnectedToOutput: false,
            audioEngineConfigurationChangeCount: engineConfigurationChangeCount,
            audioEngineRestartCount: audioEngineRestartCount,
            audioGraphFormatChangeCount: audioGraphFormatChangeCount,
            audioOutputRouteChangeCount: audioOutputRouteChangeCount,
            audioGraphFormatChanged: audioGraphChanges.formatChanged,
            audioOutputRouteChanged: audioGraphChanges.routeChanged,
            audioOutputDeviceChanged: audioGraphChanges.outputDeviceChanged,
            audioOutputSampleRateChanged: audioGraphChanges.outputSampleRateChanged,
            audioOutputChannelCountChanged: audioGraphChanges.outputChannelCountChanged,
            audioHardwareIOBufferDurationChanged: audioGraphChanges.hardwareIOBufferDurationChanged,
            audioEngineOutputNodeFormatChanged: audioGraphChanges.outputNodeFormatChanged,
            audioFormatConversionLikely: audioGraph.formatConversionLikely,
            runtimeCaptureMatchesSourceNodeFormat: nil,
            runtimeCaptureMatchesEngineOutputFormat: nil,
            runtimeCaptureMatchesHardwareSampleRate: audioGraph.captureMatchesHardwareSampleRate,
            cMixerRenderedFrames: sampleTimePosition.cMixerRenderedFrames,
            cMixerPlaybackSeconds: sampleTimePosition.cMixerPlaybackSeconds,
            cMixerRenderedFramesBeforeClear: action == "c_mixer_clear_all" ? snapshotBefore?.currentFrame : nil,
            cMixerPlaybackSecondsBeforeClear: action == "c_mixer_clear_all"
                ? seconds(frame: snapshotBefore?.currentFrame, sampleRate: snapshotBefore?.sampleRate ?? snapshot.sampleRate)
                : nil,
            plannedSongEndFrame: plannedSongEndFrame,
            plannedSongEndSeconds: seconds(frame: plannedSongEndFrame, sampleRate: snapshot.sampleRate),
            plannedSongEndRuntimeFrame: plannedSongEndRuntimeFrame,
            plannedSongEndRuntimeSeconds: seconds(frame: plannedSongEndRuntimeFrame, sampleRate: snapshot.sampleRate),
            runtimeFrameAtPlannedSongEnd: runtimeFrameAtPlannedSongEnd,
            runtimeSecondsAtPlannedSongEnd: seconds(frame: runtimeFrameAtPlannedSongEnd, sampleRate: snapshot.sampleRate),
            runtimeTailSeconds: lifecycleSnapshot.runtimeTailSeconds,
            runtimeTailFrames: lifecycleSnapshot.runtimeTailFrames,
            runtimeTailPolicy: lifecycleSnapshot.runtimeTailPolicy,
            runtimeTailConfigurationWarning: lifecycleSnapshot.runtimeTailConfigurationWarning,
            songEndStopFrame: songEndStopFrame,
            songEndStopSeconds: seconds(frame: songEndStopFrame, sampleRate: snapshot.sampleRate),
            songEndStopRuntimeFrame: songEndStopRuntimeFrame,
            songEndStopRuntimeSeconds: seconds(frame: songEndStopRuntimeFrame, sampleRate: snapshot.sampleRate),
            runtimeFrameAtSongEndTailStop: runtimeFrameAtSongEndTailStop,
            runtimeSecondsAtSongEndTailStop: seconds(frame: runtimeFrameAtSongEndTailStop, sampleRate: snapshot.sampleRate),
            eventQueueExhausted: snapshot.eventQueueExhausted,
            eventQueueExhaustedFrame: snapshot.eventQueueExhaustedFrame,
            eventQueueExhaustedSeconds: seconds(frame: snapshot.eventQueueExhaustedFrame, sampleRate: snapshot.sampleRate),
            activeVoiceCountAtPlannedSongEnd: lifecycleSnapshot.activeVoiceCountAtPlannedSongEnd ?? snapshot.activeVoiceCountAtPlannedSongEnd,
            loadedVoiceCountAtPlannedSongEnd: lifecycleSnapshot.loadedVoiceCountAtPlannedSongEnd ?? snapshot.loadedVoiceCountAtPlannedSongEnd,
            activeVoiceCountAtTailStop: lifecycleSnapshot.activeVoiceCountAtTailStop ?? snapshot.activeVoiceCountAtTailStop,
            loadedVoiceCountAtTailStop: lifecycleSnapshot.loadedVoiceCountAtTailStop ?? snapshot.loadedVoiceCountAtTailStop,
            activeVoiceCountAfterPlannedSongEnd: snapshot.activeVoiceCountAfterPlannedSongEnd,
            loadedVoiceCountAfterPlannedSongEnd: snapshot.loadedVoiceCountAfterPlannedSongEnd,
            outputContinuesAfterPlannedSongEnd: snapshot.outputContinuesAfterPlannedSongEnd,
            finalSustainedVoicesContinueAfterPlannedSongEnd: snapshot.finalSustainedVoicesContinueAfterPlannedSongEnd,
            captureSeconds: snapshot.capture.seconds,
            captureEndFrame: snapshot.capture.frameLimit,
            captureTruncated: snapshot.capture.truncated,
            captureCapTriggeredPlaybackStop: lifecycleSnapshot.captureCapTriggeredPlaybackStop,
            stopReason: stopReason,
            cMixerSampleTimeFrame: sampleTimePosition.cMixerSampleTimeFrame,
            cMixerSampleTimePositionStatus: sampleTimePosition.cMixerSampleTimePositionStatus,
            cMixerSampleTimeOrderIndex: sampleTimePosition.cMixerSampleTimeOrderIndex,
            cMixerSampleTimePatternIndex: sampleTimePosition.cMixerSampleTimePatternIndex,
            cMixerSampleTimeRowIndex: sampleTimePosition.cMixerSampleTimeRowIndex,
            cMixerSampleTimeTickInRow: sampleTimePosition.cMixerSampleTimeTickInRow,
            playbackEngineOrderIndex: sampleTimePosition.playbackEngineOrderIndex,
            playbackEnginePatternIndex: sampleTimePosition.playbackEnginePatternIndex,
            playbackEngineRowIndex: sampleTimePosition.playbackEngineRowIndex,
            playbackEngineTickInRow: sampleTimePosition.playbackEngineTickInRow,
            playbackEngineToCMixerFrameDelta: sampleTimePosition.playbackEngineToCMixerFrameDelta,
            playbackEngineToCMixerPositionMismatch: sampleTimePosition.playbackEngineToCMixerPositionMismatch,
            rowTransitionDeltaCategory: sampleTimePosition.rowTransitionDeltaCategory,
            publishedPlaybackFollowPositionSource: publishedPlaybackFollowPosition?.source.rawValue,
            publishedPlaybackFollowOrderIndex: publishedPlaybackFollowPosition?.position.orderIndex,
            publishedPlaybackFollowPatternIndex: publishedPlaybackFollowPosition?.position.patternIndex,
            publishedPlaybackFollowRowIndex: publishedPlaybackFollowPosition?.position.rowIndex,
            publishedPlaybackFollowTickInRow: publishedPlaybackFollowPosition?.tickInRow,
            publishedPlaybackFollowSampleTimeFrame: publishedPlannedFrame,
            publishedPlaybackFollowPositionStatus: publishedPlaybackFollowPosition?.sampleTimeStatus ?? publishedPlannedPosition?.status,
            publishedPlaybackFollowSyntheticRow: publishedPlannedPosition?.syntheticRow ?? publishedPlaybackFollowPosition?.syntheticRow,
            publishedPlaybackFollowToCMixerFrameDelta: publishedToCMixerFrameDelta,
            publishedPlaybackFollowToCMixerRowDelta: publishedToCMixerRowDelta,
            playbackEngineToPublishedPlaybackFollowFrameDelta: playbackEngineToPublishedFrameDelta,
            playbackEngineToPublishedPlaybackFollowRowDelta: playbackEngineToPublishedRowDelta,
            playbackFollowPublicationDisabled: playbackFollowPublicationDisabled,
            playbackFollowPublicationCount: playbackFollowPublicationCount,
            playbackFollowPublicationSuppressedCount: playbackFollowPublicationSuppressedCount,
            channelCount: snapshot.channelCount,
            context: context,
            targetScope: targetScope,
            targetedAllVoices: targetedAllVoices,
            activeVoiceCount: snapshot.activeVoiceCount,
            loadedVoiceCount: snapshot.loadedVoiceCount,
            activeVoiceCountBefore: snapshotBefore?.activeVoiceCount,
            activeVoiceCountAfter: snapshot.activeVoiceCount,
            loadedVoiceCountBefore: snapshotBefore?.loadedVoiceCount,
            loadedVoiceCountAfter: snapshot.loadedVoiceCount,
            stoppedVoiceCount: stoppedVoiceCount,
            rampedVoiceCount: rampedVoiceCount,
            replacementRampFrames: replacementRampFrames,
            replacementVoicesOverlap: replacementVoicesOverlap,
            replacementOldVoiceState: replacementOldVoiceState,
            replacementRampStartState: replacementRampStartState,
            replacementRampTargetGain: replacementRampTargetGain,
            replacementNewVoiceIndex: replacementNewVoiceIndex,
            replacementNewVoiceChannelTag: replacementNewVoiceChannelTag,
            replacementGainPanAppliedBeforeRamp: replacementGainPanAppliedBeforeRamp,
            replacementStepAppliedBeforeRamp: replacementStepAppliedBeforeRamp,
            replacementKeyOffAppliedBeforeRamp: replacementKeyOffAppliedBeforeRamp,
            replacementFadeoutAppliedBeforeRamp: replacementFadeoutAppliedBeforeRamp,
            targetVoiceIndex: targetVoiceIndex,
            gainBefore: gainBefore,
            gainAfter: gainAfter,
            panBefore: panBefore,
            panAfter: panAfter,
            sampleStepBefore: sampleStepBefore,
            sampleStepAfter: sampleStepAfter,
            updateDisposition: updateDisposition,
            updateType: updateType,
            updateEpsilon: updateEpsilon,
            gainRequested: gainRequested,
            panRequested: panRequested,
            sampleStepRequested: sampleStepRequested,
            gainDelta: gainDelta,
            panDelta: panDelta,
            sampleStepDelta: sampleStepDelta,
            gainUpdateStatus: gainUpdateStatus,
            panUpdateStatus: panUpdateStatus,
            sampleStepUpdateStatus: sampleStepUpdateStatus,
            currentFrame: snapshot.currentFrame,
            runtimeRenderedFrameCount: snapshot.renderedFrameCount,
            scheduledVoiceCount: snapshot.scheduledVoiceCount,
            eventQueueBacklogCount: snapshot.eventQueueBacklogCount,
            callbackIndex: eventTiming?.callbackIndex ?? snapshot.callbackIndex,
            callbackRequestedFrameCount: eventTiming?.callbackRequestedFrameCount ?? snapshot.callbackRequestedFrameCount,
            callbackStartFrame: eventTiming?.callbackStartFrame ?? snapshot.callbackStartFrame,
            callbackEndFrame: eventTiming?.callbackEndFrame ?? snapshot.callbackEndFrame,
            callbackDurationWarningThresholdMS: snapshot.callbackDurationWarningThresholdMS,
            callbackDurationMinMS: snapshot.callbackDurationMinMS,
            callbackDurationMaxMS: snapshot.callbackDurationMaxMS,
            callbackDurationAverageMS: snapshot.callbackDurationAverageMS,
            callbackMaxDurationMS: snapshot.callbackMaxDurationMS,
            callbackAvgDurationMS: snapshot.callbackAvgDurationMS,
            callbackDurationWarningCount: snapshot.callbackDurationWarningCount,
            callbackRenderQuantumDurationMS: snapshot.callbackRenderQuantumDurationMS,
            callbackRenderQuantumMinMS: snapshot.callbackRenderQuantumMinMS,
            callbackRenderQuantumMaxMS: snapshot.callbackRenderQuantumMaxMS,
            callbackOverRenderQuantumBudgetCount: snapshot.callbackOverRenderQuantumBudgetCount,
            callbackNearBudgetWarningCount: snapshot.callbackNearBudgetWarningCount,
            callbackIntervalMinMS: snapshot.callbackIntervalMinMS,
            callbackIntervalMaxMS: snapshot.callbackIntervalMaxMS,
            callbackIntervalLastMS: snapshot.callbackIntervalLastMS,
            callbackThreadIsMain: snapshot.callbackThreadIsMain,
            callbackThreadID: snapshot.callbackThreadID,
            callbackMainThreadDependencyDetected: snapshot.callbackMainThreadDependencyDetected,
            callbackAllocationWarning: snapshot.callbackAllocationWarning,
            callbackRealtimeSafeDiagnostics: snapshot.callbackRealtimeSafeDiagnostics,
            callbackDiagnosticDropCount: snapshot.callbackDiagnosticDropCount,
            callbackRingBufferCapacity: snapshot.callbackRingBufferCapacity,
            callbackLockWaitCount: snapshot.callbackLockWaitCount,
            callbackLockWaitDurationMS: snapshot.callbackLockWaitDurationMS,
            callbackLockFailureCount: snapshot.callbackLockFailureCount,
            callbackLockAttemptCount: snapshot.callbackLockAttemptCount,
            callbackTryLockFailureCount: snapshot.callbackTryLockFailureCount,
            callbackLockFailureAudioImpact: snapshot.callbackLockFailureAudioImpact,
            callbackRenderedFromStaleSnapshotCount: snapshot.callbackRenderedFromStaleSnapshotCount,
            callbackRenderedSilenceDueToUnavailableStateCount: snapshot.callbackRenderedSilenceDueToUnavailableStateCount,
            callbackSkippedDiagnosticsDueToLockCount: snapshot.callbackSkippedDiagnosticsDueToLockCount,
            callbackSkippedAudioDueToLockCount: snapshot.callbackSkippedAudioDueToLockCount,
            lifecycleChangeWhileRenderingCount: snapshot.lifecycleChangeWhileRenderingCount,
            audioUnitLifecycleCallWhileCallbackActiveCount: snapshot.audioUnitLifecycleCallWhileCallbackActiveCount,
            eventQueueProducerThreadID: snapshot.eventQueueProducerThreadID,
            eventQueueProducerThreadIsMain: snapshot.eventQueueProducerThreadIsMain,
            eventQueueConsumerThreadID: snapshot.eventQueueConsumerThreadID,
            eventQueueConsumerThreadIsMain: snapshot.eventQueueConsumerThreadIsMain,
            runtimeMinimalCallbackMode: snapshot.runtimeMinimalCallbackMode,
            outputBufferCopyAttemptCount: snapshot.outputBufferCopyAttemptCount,
            outputBufferCopyFailureCount: snapshot.outputBufferCopyFailureCount,
            outputBufferCopyLastSucceeded: snapshot.outputBufferCopyLastSucceeded,
            outputBufferCopyLayout: snapshot.outputBufferCopyLayout,
            outputBufferCopyRequestedFrameCount: snapshot.outputBufferCopyRequestedFrameCount,
            outputBufferCopySourceChannelCount: snapshot.outputBufferCopySourceChannelCount,
            outputBufferCopyOutputBufferCount: snapshot.outputBufferCopyOutputBufferCount,
            outputBufferCopyOutputChannelCount: snapshot.outputBufferCopyOutputChannelCount,
            outputBufferCopyCopiedFrameCount: snapshot.outputBufferCopyCopiedFrameCount,
            outputBufferCopyCopiedSampleCount: snapshot.outputBufferCopyCopiedSampleCount,
            outputBufferCopyExpectedSampleCount: snapshot.outputBufferCopyExpectedSampleCount,
            outputBufferCopyFilledRequestedFrames: snapshot.outputBufferCopyFilledRequestedFrames,
            outputBufferCopyChannelCountMatches: snapshot.outputBufferCopyChannelCountMatches,
            outputBufferCopyPartialCopy: snapshot.outputBufferCopyPartialCopy,
            outputBufferCopyScratchHash: snapshot.outputBufferCopyScratchHash,
            outputBufferCopyCaptureHash: snapshot.outputBufferCopyCaptureHash,
            outputBufferCopyOutputHash: snapshot.outputBufferCopyOutputHash,
            outputBufferCopyScratchCaptureHashMatches: snapshot.outputBufferCopyScratchCaptureHashMatches,
            outputBufferCopyScratchOutputHashMatches: snapshot.outputBufferCopyScratchOutputHashMatches,
            renderCallbackCount: snapshot.renderCallbackCount,
            renderCallCount: snapshot.renderCallCount,
            successfulRenderCount: snapshot.successfulRenderCount,
            failedRenderCount: snapshot.failedRenderCount,
            requestedFrameCount: snapshot.requestedFrameCount,
            cumulativeRequestedFrameCount: snapshot.cumulativeRequestedFrameCount,
            renderedFrameCount: snapshot.renderedFrameCount,
            renderFrameCount: snapshot.lastRequestedFrameCount,
            minRequestedFrameCount: snapshot.minRequestedFrameCount,
            maxRequestedFrameCount: snapshot.maxRequestedFrameCount,
            lastRequestedFrameCount: snapshot.lastRequestedFrameCount,
            lastRenderedFrameCount: snapshot.lastRenderedFrameCount,
            lastRenderSucceeded: snapshot.lastRenderSucceeded,
            zeroFillCount: snapshot.zeroFillCount,
            underrunCount: snapshot.underrunCount,
            silentOutputCallbackCount: snapshot.silentOutputCallbackCount,
            unexpectedSilentOutputCount: snapshot.unexpectedSilentOutputCount,
            outputPeak: snapshot.outputPeak,
            outputRMS: snapshot.outputRMS,
            lastOutputPeak: snapshot.lastOutputPeak,
            lastOutputRMS: snapshot.lastOutputRMS,
            outputDiscontinuityThreshold: snapshot.outputDiscontinuityThreshold,
            outputDiscontinuityCount: snapshot.outputDiscontinuityCount,
            outputDiscontinuityThresholdCounts: snapshot.outputDiscontinuityThresholdCounts,
            maxOutputAdjacentSampleJump: snapshot.maxOutputAdjacentSampleJump,
            topOutputAdjacentSampleJumps: snapshot.topOutputAdjacentSampleJumps,
            lastOutputDiscontinuitySampleJump: snapshot.lastOutputDiscontinuitySampleJump,
            lastOutputDiscontinuityCallbackIndex: snapshot.lastOutputDiscontinuityCallbackIndex,
            lastOutputDiscontinuityRuntimeFrame: snapshot.lastOutputDiscontinuityRuntimeFrame,
            lastOutputDiscontinuityFrameOffset: snapshot.lastOutputDiscontinuityFrameOffset,
            lastOutputDiscontinuityChannelIndex: snapshot.lastOutputDiscontinuityChannelIndex,
            outputPeakWarningThreshold: snapshot.outputPeakWarningThreshold,
            outputPeakWarningSampleCount: snapshot.outputPeakWarningSampleCount,
            topOutputPeaks: snapshot.topOutputPeaks,
            overrangeSampleCount: snapshot.overrangeSampleCount,
            clippingSampleCount: snapshot.clippingSampleCount,
            clippingDetected: snapshot.clippingDetected,
            runtimeOutputGain: snapshot.runtimeOutputGain,
            runtimeHeadroomPolicy: snapshot.runtimeHeadroomPolicy,
            runtimeGainPolicyLabel: snapshot.runtimeHeadroomPolicy,
            runtimeDefaultHeadroomDB: snapshot.runtimeDefaultHeadroomDB,
            runtimeGainPolicySource: snapshot.runtimeGainPolicySource,
            runtimeGainPolicyIsEnvironmentOverride: snapshot.runtimeGainPolicyIsEnvironmentOverride,
            runtimeAutoHeadroomEnabled: snapshot.runtimeAutoHeadroomEnabled,
            runtimeFixedHeadroomDB: snapshot.runtimeFixedHeadroomDB,
            runtimeGainConfigurationWarning: snapshot.runtimeGainConfigurationWarning,
            runtimeClippingRecommendation: snapshot.runtimeClippingRecommendation,
            runtimeUpdateEpsilon: snapshot.runtimeUpdateEpsilon,
            runtimeUpdateEpsilonPolicy: snapshot.runtimeUpdateEpsilonPolicy,
            runtimeUpdateEpsilonConfigurationWarning: snapshot.runtimeUpdateEpsilonConfigurationWarning,
            runtimeCaptureEnabled: snapshot.capture.enabled,
            runtimeCapturePathName: snapshot.capture.pathName,
            runtimeCaptureSampleRate: snapshot.capture.sampleRate,
            runtimeCaptureChannelCount: snapshot.capture.channelCount,
            runtimeCaptureSeconds: snapshot.capture.seconds,
            runtimeCaptureFrameLimit: snapshot.capture.frameLimit,
            runtimeCapturedFrameCount: snapshot.capture.capturedFrameCount,
            runtimeCaptureDurationSeconds: snapshot.capture.durationSeconds,
            runtimeCaptureTruncated: snapshot.capture.truncated,
            runtimeCaptureOutputPeak: snapshot.capture.outputPeak,
            runtimeCaptureOutputRMS: snapshot.capture.outputRMS,
            runtimeCaptureOverrangeSampleCount: snapshot.capture.overrangeSampleCount,
            runtimeCaptureClippingSampleCount: snapshot.capture.clippingSampleCount,
            runtimeCaptureWriteSucceeded: captureWriteSucceeded,
            runtimeCaptureWriteError: captureWriteError,
            runtimeCaptureConfigurationWarning: snapshot.capture.configurationWarning,
            cMixerAddVoiceCount: eventCounters.cMixerAddVoiceCount,
            gainPanUpdateCount: eventCounters.gainPanUpdateCount,
            stepUpdateCount: eventCounters.stepUpdateCount,
            updateSuppressedEpsilonGainCount: eventCounters.updateSuppressedEpsilonGainCount,
            updateSuppressedEpsilonPanCount: eventCounters.updateSuppressedEpsilonPanCount,
            updateSuppressedEpsilonStepCount: eventCounters.updateSuppressedEpsilonStepCount,
            updateSuppressedNoChangeCount: eventCounters.updateSuppressedNoChangeCount,
            updateAppliedAfterEpsilonFilterCount: eventCounters.updateAppliedAfterEpsilonFilterCount,
            stopChannelCount: eventCounters.stopChannelCount,
            replacementRampCount: eventCounters.replacementRampCount,
            clearAllCount: eventCounters.clearAllCount,
            rampingOutVoiceCount: snapshot.rampingOutVoiceCount,
            rampDownStartCount: snapshot.rampDownStartCount,
            rampDownCompletionCount: snapshot.rampDownCompletionCount,
            abruptRampDownStopCount: snapshot.abruptRampDownStopCount,
            previousOrderIndex: transition?.previousContext?.orderIndex,
            previousPatternIndex: transition?.previousContext?.patternIndex,
            previousRowIndex: transition?.previousContext?.rowIndex,
            nextOrderIndex: transition?.nextContext?.orderIndex,
            nextPatternIndex: transition?.nextContext?.patternIndex,
            nextRowIndex: transition?.nextContext?.rowIndex,
            transitionPhase: transition?.phase,
            transitionRuntimeFrame: transition?.runtimeFrame,
            transitionReplacementRampCount: transition?.replacementRampCount,
            transitionUpdateCount: transition?.updateCount,
            cMixerCallSucceeded: succeeded,
            reason: reason
        )
        traceWriter.record(event)
        recordAudioGraphChangeEvents(
            graph: audioGraph,
            changes: audioGraphChanges,
            snapshot: snapshot,
            baseReason: reason
        )
    }

    private func recordAudioGraphChangeEvents(
        graph: RuntimeCMixerAudioGraphDiagnostics,
        changes: RuntimeCMixerAudioGraphChanges,
        snapshot: RuntimeCMixerRenderSnapshot,
        baseReason: String?
    ) {
        if changes.outputNodeFormatChanged {
            traceWriter.record(audioGraphChangeEvent(
                action: "audio_output_node_format_changed",
                graph: graph,
                changes: changes,
                snapshot: snapshot,
                reason: "audio_output_node_format_changed"
            ))
        }
        if changes.routeChanged {
            traceWriter.record(audioGraphChangeEvent(
                action: "audio_output_route_changed",
                graph: graph,
                changes: changes,
                snapshot: snapshot,
                reason: baseReason ?? "audio_output_route_changed"
            ))
        }
    }

    private func normalizedStopReason(
        action: String,
        reason: String?,
        snapshot: RuntimeCMixerRenderSnapshot,
        snapshotBefore: RuntimeCMixerRenderSnapshot?
    ) -> String? {
        if action == "capture_truncated" {
            return "capture_cap_only"
        }
        let lifecycleSnapshot = snapshotBefore ?? snapshot
        if lifecycleSnapshot.songEndTailStopReached {
            return "song_end_tail"
        }
        switch reason {
        case "debug_stop_after_seconds":
            return "debug_stop"
        case "runtime_song_end_tail", "planned_song_end":
            return "song_end_tail"
        case "transport_stop":
            return "user_stop"
        case "transport_pause", "transport_stop_all", "runtime_c_mixer_backend_reset", "runtime_c_mixer_engine_start_failed":
            return "transport_stop"
        case "runtime_capture_cap_stop":
            return "capture_cap_only"
        default:
            return nil
        }
    }

    private func audioGraphChangeEvent(
        action: String,
        graph: RuntimeCMixerAudioGraphDiagnostics,
        changes: RuntimeCMixerAudioGraphChanges,
        snapshot: RuntimeCMixerRenderSnapshot,
        reason: String
    ) -> RuntimeCMixerTraceEvent {
        RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: runtimeAudioBackend.diagnosticName,
            runtimeEventCategory: "audio_graph_change",
            experimentalCMixerEnabled: true,
            alternativeRuntimeOutputHostEnabled: runtimeAudioBackend.alternativeRuntimeOutputHostEnabled,
            runtimeOutputHostType: runtimeAudioBackend.runtimeOutputHostType,
            runtimeOutputHostPrepareStatus: coreAudioOutputHost.lastPrepareStatus.map(Int.init),
            runtimeOutputHostInitializeStatus: coreAudioOutputHost.lastInitializeStatus.map(Int.init),
            runtimeOutputHostStartStatus: coreAudioOutputHost.lastStartStatus.map(Int.init),
            runtimeOutputHostStopStatus: coreAudioOutputHost.lastStopStatus.map(Int.init),
            runtimeOutputHostLastErrorStatus: coreAudioOutputHost.lastErrorStatus.map(Int.init),
            sampleRate: snapshot.sampleRate,
            selectedRuntimeSampleRate: runtimeSampleRateSelection?.sampleRate ?? snapshot.sampleRate,
            cMixerRuntimeSampleRate: snapshot.sampleRate,
            runtimeSampleRatePolicy: runtimeSampleRateSelection?.policy,
            runtimeSampleRateSource: runtimeSampleRateSelection?.source,
            runtimeSampleRateConfigurationWarning: runtimeSampleRateSelection?.configurationWarning,
            cMixerRenderSampleRate: graph.cMixerRenderSampleRate,
            cMixerRenderChannelCount: graph.cMixerRenderChannelCount,
            audioSourceNodeRenderSampleRate: nil,
            audioSourceNodeChannelCount: nil,
            audioEngineMainMixerOutputSampleRate: nil,
            audioEngineMainMixerOutputChannelCount: nil,
            audioEngineMainMixerInputSampleRate: nil,
            audioEngineMainMixerInputChannelCount: nil,
            audioEngineMainMixerLatency: nil,
            audioEngineMainMixerOutputPresentationLatency: nil,
            audioEngineOutputNodeSampleRate: nil,
            audioEngineOutputNodeChannelCount: nil,
            audioEngineOutputNodeLatency: nil,
            audioEngineOutputNodeOutputPresentationLatency: nil,
            audioHardwareNominalSampleRate: graph.hardwareNominalSampleRate,
            audioHardwareDeviceID: graph.outputDeviceID,
            audioHardwareDeviceUIDHash: graph.outputDeviceUIDHash,
            audioOutputRouteLabel: graph.routeLabel,
            audioHardwareIOBufferFrameSize: graph.hardwareIOBufferFrameSize,
            audioHardwareIOBufferDuration: graph.hardwareIOBufferDuration,
            audioHardwareLatencyFrames: graph.hardwareLatencyFrames,
            audioHardwareLatencyDuration: graph.hardwareLatencyDuration,
            audioHardwareSafetyOffsetFrames: graph.hardwareSafetyOffsetFrames,
            audioHardwareSafetyOffsetDuration: graph.hardwareSafetyOffsetDuration,
            audioHardwareTransportType: graph.hardwareTransportType,
            audioHardwareTransportTypeName: graph.hardwareTransportTypeName,
            audioEngineRunning: graph.engineRunning,
            audioEngineSourceNodeAttached: false,
            audioEngineSourceNodeConnected: false,
            audioEngineMainMixerConnectedToOutput: false,
            audioEngineConfigurationChangeCount: engineConfigurationChangeCount,
            audioEngineRestartCount: audioEngineRestartCount,
            audioGraphFormatChangeCount: audioGraphFormatChangeCount,
            audioOutputRouteChangeCount: audioOutputRouteChangeCount,
            audioGraphFormatChanged: changes.formatChanged,
            audioOutputRouteChanged: changes.routeChanged,
            audioOutputDeviceChanged: changes.outputDeviceChanged,
            audioOutputSampleRateChanged: changes.outputSampleRateChanged,
            audioOutputChannelCountChanged: changes.outputChannelCountChanged,
            audioHardwareIOBufferDurationChanged: changes.hardwareIOBufferDurationChanged,
            audioEngineOutputNodeFormatChanged: changes.outputNodeFormatChanged,
            audioFormatConversionLikely: graph.formatConversionLikely,
            runtimeCaptureMatchesSourceNodeFormat: nil,
            runtimeCaptureMatchesEngineOutputFormat: nil,
            runtimeCaptureMatchesHardwareSampleRate: graph.captureMatchesHardwareSampleRate,
            cMixerRenderedFrames: snapshot.currentFrame,
            cMixerPlaybackSeconds: snapshot.sampleRate > 0 ? Double(snapshot.currentFrame) / snapshot.sampleRate : nil,
            channelCount: snapshot.channelCount,
            targetScope: "none",
            currentFrame: snapshot.currentFrame,
            runtimeRenderedFrameCount: snapshot.renderedFrameCount,
            callbackIndex: snapshot.callbackIndex,
            callbackRequestedFrameCount: snapshot.callbackRequestedFrameCount,
            callbackStartFrame: snapshot.callbackStartFrame,
            callbackEndFrame: snapshot.callbackEndFrame,
            renderCallbackCount: snapshot.renderCallbackCount,
            reason: reason
        )
    }

    private func contextWithFallbackChannel(
        _ context: AudioRuntimeTraceContext?,
        channel: Int
    ) -> AudioRuntimeTraceContext? {
        guard let context else {
            return AudioRuntimeTraceContext(channelIndex: channel)
        }
        guard context.channelIndex == nil else {
            return context
        }
        return AudioRuntimeTraceContext(
            orderIndex: context.orderIndex,
            patternIndex: context.patternIndex,
            rowIndex: context.rowIndex,
            tickInRow: context.tickInRow,
            channelIndex: channel,
            noteValue: context.noteValue,
            instrumentIndex: context.instrumentIndex,
            effectType: context.effectType,
            effectParam: context.effectParam,
            volumeColumn: context.volumeColumn,
            speed: context.speed,
            bpm: context.bpm,
            tickIndex: context.tickIndex
        )
    }

    private func traceContext(position: PlaybackPosition, tickInRow: Int) -> AudioRuntimeTraceContext {
        AudioRuntimeTraceContext(
            orderIndex: position.orderIndex,
            patternIndex: position.patternIndex,
            rowIndex: position.rowIndex,
            tickInRow: tickInRow
        )
    }

    private func runtimeRowOrderMapping(for context: AudioRuntimeTraceContext?) -> String? {
        guard let context,
              let orderIndex = context.orderIndex,
              let rowIndex = context.rowIndex else {
            return nil
        }
        let patternIndex = context.patternIndex.map(String.init) ?? "unknown"
        let tickInRow = context.tickInRow ?? 0
        return "order:\(orderIndex) pattern:\(patternIndex) row:\(rowIndex) tick:\(tickInRow)"
    }
}
