import AVFoundation
import Foundation
import os

@MainActor
protocol PlaybackAudioOutput: AnyObject {
    var audioBufferSampleRate: Double { get }

    func trigger(_ request: AudioVoiceRequest)
    func update(channel: Int, controls: AudioChannelControls)
    func stop(channel: Int)
    func stopAll()
    func reset()
}

enum RuntimeAudioBackend: Equatable {
    case avAudio
    case cMixer

    var diagnosticName: String {
        switch self {
        case .avAudio:
            return "av_audio"
        case .cMixer:
            return "c_mixer"
        }
    }
}

struct RuntimeAudioBackendSelection: Equatable {
    static let environmentKey = "VTX_AUDIO_BACKEND"
    static let cMixerEnvironmentValue = "c_mixer"

    let backend: RuntimeAudioBackend
    let requestedValue: String?
    let fallbackReason: String?

    var experimentalCMixerEnabled: Bool {
        backend == .cMixer
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeAudioBackendSelection {
        let requestedValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedValue,
              !requestedValue.isEmpty else {
            return RuntimeAudioBackendSelection(backend: .avAudio, requestedValue: nil, fallbackReason: nil)
        }
        guard requestedValue == cMixerEnvironmentValue else {
            return RuntimeAudioBackendSelection(
                backend: .avAudio,
                requestedValue: requestedValue,
                fallbackReason: "unknown_backend"
            )
        }
        return RuntimeAudioBackendSelection(backend: .cMixer, requestedValue: requestedValue, fallbackReason: nil)
    }
}

@MainActor
protocol PlaybackAudioBackendProviding: AnyObject {
    var runtimeAudioBackend: RuntimeAudioBackend { get }
}

struct RuntimeCMixerTraceEvent: Encodable, Equatable {
    let schemaVersion: Int
    let runtimeAction: String
    let runtimeAudioBackend: String
    let backendFlagValue: String?
    let fallbackReason: String?
    let runtimeEventSource: String?
    let adapterPlanGenerated: Bool?
    let plannedEventCount: Int?
    let consumedPlannedEventCount: Int?
    let skippedUnmatchedPlannedEventCount: Int?
    let runtimeRowOrderMapping: String?
    let adapterEventCategory: String?
    let adapterEventCategoriesConsumed: [String]?
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
    let fallbackToSimpleRuntimeEventCount: UInt64?
    let runtimeEventFallbackReason: String?
    let experimentalCMixerEnabled: Bool
    let sampleRate: Double?
    let channelCount: Int?
    let orderIndex: Int?
    let patternIndex: Int?
    let rowIndex: Int?
    let tickInRow: Int?
    let tickIndex: UInt64?
    let channelIndex: Int?
    let noteValue: UInt8?
    let instrumentIndex: Int?
    let effectType: String?
    let effectParam: String?
    let effect: String?
    let volumeColumn: String?
    let targetScope: String
    let targetedAllVoices: Bool
    let activeVoiceCount: Int?
    let loadedVoiceCount: Int?
    let activeVoiceCountBefore: Int?
    let activeVoiceCountAfter: Int?
    let loadedVoiceCountBefore: Int?
    let loadedVoiceCountAfter: Int?
    let stoppedVoiceCount: Int?
    let rampedVoiceCount: Int?
    let replacementRampFrames: Int?
    let replacementVoicesOverlap: Bool?
    let targetVoiceIndex: Int?
    let gainBefore: Float?
    let gainAfter: Float?
    let panBefore: Float?
    let panAfter: Float?
    let sampleStepBefore: Double?
    let sampleStepAfter: Double?
    let updateDisposition: String?
    let updateType: String?
    let updateEpsilon: Double?
    let gainRequested: Float?
    let panRequested: Float?
    let sampleStepRequested: Double?
    let gainDelta: Double?
    let panDelta: Double?
    let sampleStepDelta: Double?
    let gainUpdateStatus: String?
    let panUpdateStatus: String?
    let sampleStepUpdateStatus: String?
    let currentFrame: UInt64?
    let runtimeRenderedFrameCount: UInt64?
    let scheduledVoiceCount: Int?
    let eventQueueBacklogCount: Int?
    let callbackIndex: UInt64?
    let callbackRequestedFrameCount: Int?
    let callbackStartFrame: UInt64?
    let callbackEndFrame: UInt64?
    let renderCallbackCount: UInt64?
    let renderCallCount: UInt64?
    let successfulRenderCount: UInt64?
    let failedRenderCount: UInt64?
    let requestedFrameCount: Int?
    let cumulativeRequestedFrameCount: UInt64?
    let renderedFrameCount: UInt64?
    let renderFrameCount: Int?
    let minRequestedFrameCount: Int?
    let maxRequestedFrameCount: Int?
    let lastRequestedFrameCount: Int?
    let lastRenderedFrameCount: Int?
    let lastRenderSucceeded: Bool?
    let zeroFillCount: UInt64?
    let underrunCount: UInt64?
    let silentOutputCallbackCount: UInt64?
    let unexpectedSilentOutputCount: UInt64?
    let outputPeak: Float?
    let outputRMS: Float?
    let lastOutputPeak: Float?
    let lastOutputRMS: Float?
    let overrangeSampleCount: UInt64?
    let clippingSampleCount: UInt64?
    let clippingDetected: Bool?
    let runtimeOutputGain: Float?
    let runtimeHeadroomPolicy: String?
    let runtimeGainPolicyLabel: String?
    let runtimeAutoHeadroomEnabled: Bool?
    let runtimeFixedHeadroomDB: Double?
    let runtimeGainConfigurationWarning: String?
    let runtimeClippingRecommendation: String?
    let noteTriggerEventCount: UInt64?
    let cMixerAddVoiceCount: UInt64?
    let gainPanUpdateCount: UInt64?
    let stepUpdateCount: UInt64?
    let updateSuppressedEpsilonGainCount: UInt64?
    let updateSuppressedEpsilonPanCount: UInt64?
    let updateSuppressedEpsilonStepCount: UInt64?
    let updateSuppressedNoChangeCount: UInt64?
    let updateAppliedAfterEpsilonFilterCount: UInt64?
    let stopChannelCount: UInt64?
    let replacementRampCount: UInt64?
    let clearAllCount: UInt64?
    let previousOrderIndex: Int?
    let previousPatternIndex: Int?
    let previousRowIndex: Int?
    let nextOrderIndex: Int?
    let nextPatternIndex: Int?
    let nextRowIndex: Int?
    let transitionPhase: String?
    let transitionRuntimeFrame: UInt64?
    let transitionReplacementRampCount: UInt64?
    let transitionUpdateCount: UInt64?
    let cMixerCallSucceeded: Bool?
    let reason: String?

    init(
        schemaVersion: Int = 1,
        runtimeAction: String,
        runtimeAudioBackend: String,
        backendFlagValue: String? = nil,
        fallbackReason: String? = nil,
        runtimeEventSource: String? = nil,
        adapterPlanGenerated: Bool? = nil,
        plannedEventCount: Int? = nil,
        consumedPlannedEventCount: Int? = nil,
        skippedUnmatchedPlannedEventCount: Int? = nil,
        runtimeRowOrderMapping: String? = nil,
        adapterEventCategory: String? = nil,
        adapterEventCategoriesConsumed: [String]? = nil,
        runtimeEventCategory: String? = nil,
        plannedEventID: Int? = nil,
        plannedSourceOrderIndex: Int? = nil,
        plannedSourcePatternIndex: Int? = nil,
        plannedSourceRowIndex: Int? = nil,
        plannedSourceTickInRow: Int? = nil,
        plannedSourceChannelIndex: Int? = nil,
        plannedEventFrame: Int? = nil,
        plannedRuntimeFrame: Int? = nil,
        plannedRuntimeFrameOffset: Int? = nil,
        runtimeApplicationFrame: UInt64? = nil,
        eventFrameDelta: Int? = nil,
        eventApplicationTiming: String? = nil,
        fallbackToSimpleRuntimeEventCount: UInt64? = nil,
        runtimeEventFallbackReason: String? = nil,
        experimentalCMixerEnabled: Bool,
        sampleRate: Double? = nil,
        channelCount: Int? = nil,
        context: AudioRuntimeTraceContext? = nil,
        targetScope: String = "none",
        targetedAllVoices: Bool = false,
        activeVoiceCount: Int? = nil,
        loadedVoiceCount: Int? = nil,
        activeVoiceCountBefore: Int? = nil,
        activeVoiceCountAfter: Int? = nil,
        loadedVoiceCountBefore: Int? = nil,
        loadedVoiceCountAfter: Int? = nil,
        stoppedVoiceCount: Int? = nil,
        rampedVoiceCount: Int? = nil,
        replacementRampFrames: Int? = nil,
        replacementVoicesOverlap: Bool? = nil,
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
        currentFrame: UInt64? = nil,
        runtimeRenderedFrameCount: UInt64? = nil,
        scheduledVoiceCount: Int? = nil,
        eventQueueBacklogCount: Int? = nil,
        callbackIndex: UInt64? = nil,
        callbackRequestedFrameCount: Int? = nil,
        callbackStartFrame: UInt64? = nil,
        callbackEndFrame: UInt64? = nil,
        renderCallbackCount: UInt64? = nil,
        renderCallCount: UInt64? = nil,
        successfulRenderCount: UInt64? = nil,
        failedRenderCount: UInt64? = nil,
        requestedFrameCount: Int? = nil,
        cumulativeRequestedFrameCount: UInt64? = nil,
        renderedFrameCount: UInt64? = nil,
        renderFrameCount: Int? = nil,
        minRequestedFrameCount: Int? = nil,
        maxRequestedFrameCount: Int? = nil,
        lastRequestedFrameCount: Int? = nil,
        lastRenderedFrameCount: Int? = nil,
        lastRenderSucceeded: Bool? = nil,
        zeroFillCount: UInt64? = nil,
        underrunCount: UInt64? = nil,
        silentOutputCallbackCount: UInt64? = nil,
        unexpectedSilentOutputCount: UInt64? = nil,
        outputPeak: Float? = nil,
        outputRMS: Float? = nil,
        lastOutputPeak: Float? = nil,
        lastOutputRMS: Float? = nil,
        overrangeSampleCount: UInt64? = nil,
        clippingSampleCount: UInt64? = nil,
        clippingDetected: Bool? = nil,
        runtimeOutputGain: Float? = nil,
        runtimeHeadroomPolicy: String? = nil,
        runtimeGainPolicyLabel: String? = nil,
        runtimeAutoHeadroomEnabled: Bool? = nil,
        runtimeFixedHeadroomDB: Double? = nil,
        runtimeGainConfigurationWarning: String? = nil,
        runtimeClippingRecommendation: String? = nil,
        noteTriggerEventCount: UInt64? = nil,
        cMixerAddVoiceCount: UInt64? = nil,
        gainPanUpdateCount: UInt64? = nil,
        stepUpdateCount: UInt64? = nil,
        updateSuppressedEpsilonGainCount: UInt64? = nil,
        updateSuppressedEpsilonPanCount: UInt64? = nil,
        updateSuppressedEpsilonStepCount: UInt64? = nil,
        updateSuppressedNoChangeCount: UInt64? = nil,
        updateAppliedAfterEpsilonFilterCount: UInt64? = nil,
        stopChannelCount: UInt64? = nil,
        replacementRampCount: UInt64? = nil,
        clearAllCount: UInt64? = nil,
        previousOrderIndex: Int? = nil,
        previousPatternIndex: Int? = nil,
        previousRowIndex: Int? = nil,
        nextOrderIndex: Int? = nil,
        nextPatternIndex: Int? = nil,
        nextRowIndex: Int? = nil,
        transitionPhase: String? = nil,
        transitionRuntimeFrame: UInt64? = nil,
        transitionReplacementRampCount: UInt64? = nil,
        transitionUpdateCount: UInt64? = nil,
        cMixerCallSucceeded: Bool? = nil,
        reason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeAction = runtimeAction
        self.runtimeAudioBackend = runtimeAudioBackend
        self.backendFlagValue = backendFlagValue
        self.fallbackReason = fallbackReason
        self.runtimeEventSource = runtimeEventSource
        self.adapterPlanGenerated = adapterPlanGenerated
        self.plannedEventCount = plannedEventCount
        self.consumedPlannedEventCount = consumedPlannedEventCount
        self.skippedUnmatchedPlannedEventCount = skippedUnmatchedPlannedEventCount
        self.runtimeRowOrderMapping = runtimeRowOrderMapping
        self.adapterEventCategory = adapterEventCategory
        self.adapterEventCategoriesConsumed = adapterEventCategoriesConsumed
        self.runtimeEventCategory = runtimeEventCategory
        self.plannedEventID = plannedEventID
        self.plannedSourceOrderIndex = plannedSourceOrderIndex
        self.plannedSourcePatternIndex = plannedSourcePatternIndex
        self.plannedSourceRowIndex = plannedSourceRowIndex
        self.plannedSourceTickInRow = plannedSourceTickInRow
        self.plannedSourceChannelIndex = plannedSourceChannelIndex
        self.plannedEventFrame = plannedEventFrame
        self.plannedRuntimeFrame = plannedRuntimeFrame
        self.plannedRuntimeFrameOffset = plannedRuntimeFrameOffset
        self.runtimeApplicationFrame = runtimeApplicationFrame
        self.eventFrameDelta = eventFrameDelta
        self.eventApplicationTiming = eventApplicationTiming
        self.fallbackToSimpleRuntimeEventCount = fallbackToSimpleRuntimeEventCount
        self.runtimeEventFallbackReason = runtimeEventFallbackReason
        self.experimentalCMixerEnabled = experimentalCMixerEnabled
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        orderIndex = context?.orderIndex
        patternIndex = context?.patternIndex
        rowIndex = context?.rowIndex
        tickInRow = context?.tickInRow
        tickIndex = context?.tickIndex
        channelIndex = context?.channelIndex
        noteValue = context?.noteValue
        instrumentIndex = context?.instrumentIndex
        effectType = Self.hexByte(context?.effectType)
        effectParam = Self.hexByte(context?.effectParam)
        effect = Self.effectString(effectType: context?.effectType, effectParam: context?.effectParam)
        volumeColumn = Self.hexByte(context?.volumeColumn)
        self.targetScope = targetScope
        self.targetedAllVoices = targetedAllVoices
        self.activeVoiceCount = activeVoiceCount
        self.loadedVoiceCount = loadedVoiceCount
        self.activeVoiceCountBefore = activeVoiceCountBefore
        self.activeVoiceCountAfter = activeVoiceCountAfter
        self.loadedVoiceCountBefore = loadedVoiceCountBefore
        self.loadedVoiceCountAfter = loadedVoiceCountAfter
        self.stoppedVoiceCount = stoppedVoiceCount
        self.rampedVoiceCount = rampedVoiceCount
        self.replacementRampFrames = replacementRampFrames
        self.replacementVoicesOverlap = replacementVoicesOverlap
        self.targetVoiceIndex = targetVoiceIndex
        self.gainBefore = gainBefore
        self.gainAfter = gainAfter
        self.panBefore = panBefore
        self.panAfter = panAfter
        self.sampleStepBefore = sampleStepBefore
        self.sampleStepAfter = sampleStepAfter
        self.updateDisposition = updateDisposition
        self.updateType = updateType
        self.updateEpsilon = updateEpsilon
        self.gainRequested = gainRequested
        self.panRequested = panRequested
        self.sampleStepRequested = sampleStepRequested
        self.gainDelta = gainDelta
        self.panDelta = panDelta
        self.sampleStepDelta = sampleStepDelta
        self.gainUpdateStatus = gainUpdateStatus
        self.panUpdateStatus = panUpdateStatus
        self.sampleStepUpdateStatus = sampleStepUpdateStatus
        self.currentFrame = currentFrame
        self.runtimeRenderedFrameCount = runtimeRenderedFrameCount
        self.scheduledVoiceCount = scheduledVoiceCount
        self.eventQueueBacklogCount = eventQueueBacklogCount
        self.callbackIndex = callbackIndex
        self.callbackRequestedFrameCount = callbackRequestedFrameCount
        self.callbackStartFrame = callbackStartFrame
        self.callbackEndFrame = callbackEndFrame
        self.renderCallbackCount = renderCallbackCount
        self.renderCallCount = renderCallCount
        self.successfulRenderCount = successfulRenderCount
        self.failedRenderCount = failedRenderCount
        self.requestedFrameCount = requestedFrameCount
        self.cumulativeRequestedFrameCount = cumulativeRequestedFrameCount
        self.renderedFrameCount = renderedFrameCount
        self.renderFrameCount = renderFrameCount
        self.minRequestedFrameCount = minRequestedFrameCount
        self.maxRequestedFrameCount = maxRequestedFrameCount
        self.lastRequestedFrameCount = lastRequestedFrameCount
        self.lastRenderedFrameCount = lastRenderedFrameCount
        self.lastRenderSucceeded = lastRenderSucceeded
        self.zeroFillCount = zeroFillCount
        self.underrunCount = underrunCount
        self.silentOutputCallbackCount = silentOutputCallbackCount
        self.unexpectedSilentOutputCount = unexpectedSilentOutputCount
        self.outputPeak = outputPeak
        self.outputRMS = outputRMS
        self.lastOutputPeak = lastOutputPeak
        self.lastOutputRMS = lastOutputRMS
        self.overrangeSampleCount = overrangeSampleCount
        self.clippingSampleCount = clippingSampleCount
        self.clippingDetected = clippingDetected
        self.runtimeOutputGain = runtimeOutputGain
        self.runtimeHeadroomPolicy = runtimeHeadroomPolicy
        self.runtimeGainPolicyLabel = runtimeGainPolicyLabel
        self.runtimeAutoHeadroomEnabled = runtimeAutoHeadroomEnabled
        self.runtimeFixedHeadroomDB = runtimeFixedHeadroomDB
        self.runtimeGainConfigurationWarning = runtimeGainConfigurationWarning
        self.runtimeClippingRecommendation = runtimeClippingRecommendation
        self.noteTriggerEventCount = noteTriggerEventCount
        self.cMixerAddVoiceCount = cMixerAddVoiceCount
        self.gainPanUpdateCount = gainPanUpdateCount
        self.stepUpdateCount = stepUpdateCount
        self.updateSuppressedEpsilonGainCount = updateSuppressedEpsilonGainCount
        self.updateSuppressedEpsilonPanCount = updateSuppressedEpsilonPanCount
        self.updateSuppressedEpsilonStepCount = updateSuppressedEpsilonStepCount
        self.updateSuppressedNoChangeCount = updateSuppressedNoChangeCount
        self.updateAppliedAfterEpsilonFilterCount = updateAppliedAfterEpsilonFilterCount
        self.stopChannelCount = stopChannelCount
        self.replacementRampCount = replacementRampCount
        self.clearAllCount = clearAllCount
        self.previousOrderIndex = previousOrderIndex
        self.previousPatternIndex = previousPatternIndex
        self.previousRowIndex = previousRowIndex
        self.nextOrderIndex = nextOrderIndex
        self.nextPatternIndex = nextPatternIndex
        self.nextRowIndex = nextRowIndex
        self.transitionPhase = transitionPhase
        self.transitionRuntimeFrame = transitionRuntimeFrame
        self.transitionReplacementRampCount = transitionReplacementRampCount
        self.transitionUpdateCount = transitionUpdateCount
        self.cMixerCallSucceeded = cMixerCallSucceeded
        self.reason = reason
    }

    private static func hexByte(_ value: UInt8?) -> String? {
        value.map { String(format: "%02X", $0) }
    }

    private static func effectString(effectType: UInt8?, effectParam: UInt8?) -> String? {
        guard let effectType,
              let effectParam else {
            return nil
        }
        return String(format: "%02X%02X", effectType, effectParam)
    }
}

@MainActor
protocol RuntimeCMixerTraceWriting: AnyObject {
    var isEnabled: Bool { get }

    func record(_ event: RuntimeCMixerTraceEvent)
    func flush()
}

@MainActor
final class NoopRuntimeCMixerTraceWriter: RuntimeCMixerTraceWriting {
    static let shared = NoopRuntimeCMixerTraceWriter()

    let isEnabled = false

    private init() {}

    func record(_ event: RuntimeCMixerTraceEvent) {}

    func flush() {}
}

enum RuntimeCMixerTraceJSONLFormatter {
    static func line(for event: RuntimeCMixerTraceEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }
}

@MainActor
final class RuntimeCMixerTraceJSONLWriter: RuntimeCMixerTraceWriting {
    let isEnabled = true

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "RuntimeCMixerTrace")
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

    func record(_ event: RuntimeCMixerTraceEvent) {
        do {
            try fileHandle.write(contentsOf: RuntimeCMixerTraceJSONLFormatter.line(for: event))
        } catch {
            logger.error("Unable to write runtime C mixer trace event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flush() {
        try? fileHandle.synchronize()
    }
}

enum RuntimeCMixerTraceConfiguration {
    static let pathEnvironmentKey = "VTX_C_MIXER_RUNTIME_TRACE_PATH"

    static func traceURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let rawPath = environment[pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
    }

    @MainActor
    static func makeWriter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeCMixerTraceWriting {
        #if DEBUG
        guard let url = traceURL(environment: environment) else {
            return NoopRuntimeCMixerTraceWriter.shared
        }
        do {
            return try RuntimeCMixerTraceJSONLWriter(url: url)
        } catch {
            Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "RuntimeCMixerTrace")
                .error("Unable to open runtime C mixer trace at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return NoopRuntimeCMixerTraceWriter.shared
        }
        #else
        return NoopRuntimeCMixerTraceWriter.shared
        #endif
    }
}

@MainActor
enum PlaybackAudioOutputFactory {
    private static let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "AudioBackend")

    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting = RuntimeCMixerTraceConfiguration.makeWriter()
    ) -> PlaybackAudioOutput {
        let selection = RuntimeAudioBackendSelection.resolve(environment: environment)
        let outputPolicy = selection.backend == .cMixer
            ? RuntimeCMixerOutputPolicy.resolve(environment: environment)
            : nil
        if let requestedValue = selection.requestedValue,
           let fallbackReason = selection.fallbackReason {
            logger.warning(
                "Unknown VTX_AUDIO_BACKEND value '\(requestedValue, privacy: .public)'; falling back to av_audio reason=\(fallbackReason, privacy: .public)"
            )
        }
        if let warning = outputPolicy?.configurationWarning {
            logger.warning(
                "Runtime C mixer output policy warning=\(warning, privacy: .public) gain=\(outputPolicy?.outputGain ?? 1, privacy: .public)"
            )
        }
        logger.info(
            "Selected audio backend=\(selection.backend.diagnosticName, privacy: .public) experimental_c_mixer_enabled=\(selection.experimentalCMixerEnabled, privacy: .public) sample_rate=\(MixerRenderConfig.defaultSampleRate, privacy: .public) channel_count=\(MixerRenderConfig.defaultChannelCount, privacy: .public)"
        )
        if runtimeCMixerTraceWriter.isEnabled {
            runtimeCMixerTraceWriter.record(RuntimeCMixerTraceEvent(
                runtimeAction: "backend_selected",
                runtimeAudioBackend: selection.backend.diagnosticName,
                backendFlagValue: selection.requestedValue,
                fallbackReason: selection.fallbackReason,
                experimentalCMixerEnabled: selection.experimentalCMixerEnabled,
                sampleRate: MixerRenderConfig.defaultSampleRate,
                channelCount: selection.backend == .cMixer ? MixerRenderConfig.defaultChannelCount : 1,
                targetScope: "none",
                targetedAllVoices: false,
                runtimeOutputGain: outputPolicy?.outputGain,
                runtimeHeadroomPolicy: outputPolicy?.headroomPolicy,
                runtimeGainPolicyLabel: outputPolicy?.headroomPolicy,
                runtimeAutoHeadroomEnabled: outputPolicy?.autoHeadroomEnabled,
                runtimeFixedHeadroomDB: outputPolicy?.fixedHeadroomDB,
                runtimeGainConfigurationWarning: outputPolicy?.configurationWarning,
                cMixerCallSucceeded: nil,
                reason: selection.fallbackReason
            ))
        }
        switch selection.backend {
        case .avAudio:
            return PlaybackAudioEngine()
        case .cMixer:
            return RuntimeCMixerAudioEngine(
                outputPolicy: outputPolicy ?? .defaultPolicy,
                traceWriter: runtimeCMixerTraceWriter
            )
        }
    }
}

struct RuntimeCMixerRenderSnapshot: Equatable {
    let sampleRate: Double
    let channelCount: Int
    let activeVoiceCount: Int
    let loadedVoiceCount: Int
    let scheduledVoiceCount: Int
    let eventQueueBacklogCount: Int
    let renderCallbackCount: UInt64
    let renderCallCount: UInt64
    let successfulRenderCount: UInt64
    let failedRenderCount: UInt64
    let requestedFrameCount: Int?
    let cumulativeRequestedFrameCount: UInt64
    let renderedFrameCount: UInt64
    let callbackIndex: UInt64?
    let callbackRequestedFrameCount: Int?
    let callbackStartFrame: UInt64?
    let callbackEndFrame: UInt64?
    let minRequestedFrameCount: Int?
    let maxRequestedFrameCount: Int?
    let lastRequestedFrameCount: Int?
    let lastRenderedFrameCount: Int?
    let lastRenderSucceeded: Bool?
    let zeroFillCount: UInt64
    let underrunCount: UInt64
    let silentOutputCallbackCount: UInt64
    let unexpectedSilentOutputCount: UInt64
    let outputPeak: Float
    let outputRMS: Float
    let lastOutputPeak: Float
    let lastOutputRMS: Float
    let overrangeSampleCount: UInt64
    let clippingSampleCount: UInt64
    let clippingDetected: Bool
    let runtimeOutputGain: Float
    let runtimeHeadroomPolicy: String
    let runtimeAutoHeadroomEnabled: Bool
    let runtimeFixedHeadroomDB: Double?
    let runtimeGainConfigurationWarning: String?
    let runtimeClippingRecommendation: String?
    let currentFrame: UInt64
}

struct RuntimeCMixerOutputPolicy: Equatable {
    static let gainEnvironmentKey = "VTX_C_MIXER_RUNTIME_GAIN"
    static let headroomDBEnvironmentKey = "VTX_C_MIXER_RUNTIME_HEADROOM_DB"
    static let defaultHeadroomDB = -10.0
    static let clippingRecommendation = "reduce VTX_C_MIXER_RUNTIME_GAIN or set a more negative VTX_C_MIXER_RUNTIME_HEADROOM_DB"

    static let defaultPolicy = RuntimeCMixerOutputPolicy(
        outputGain: Float(pow(10.0, defaultHeadroomDB / 20.0)),
        headroomPolicy: "default_runtime_headroom_db",
        fixedHeadroomDB: defaultHeadroomDB
    )

    let outputGain: Float
    let headroomPolicy: String
    let autoHeadroomEnabled: Bool
    let fixedHeadroomDB: Double?
    let configurationWarning: String?

    init(
        outputGain: Float,
        headroomPolicy: String,
        autoHeadroomEnabled: Bool = false,
        fixedHeadroomDB: Double? = nil,
        configurationWarning: String? = nil
    ) {
        self.outputGain = outputGain.isFinite && outputGain > 0 ? outputGain : Self.defaultPolicy.outputGain
        self.headroomPolicy = headroomPolicy
        self.autoHeadroomEnabled = autoHeadroomEnabled
        self.fixedHeadroomDB = fixedHeadroomDB
        self.configurationWarning = configurationWarning
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeCMixerOutputPolicy {
        let rawGain = trimmedEnvironmentValue(environment[gainEnvironmentKey])
        let rawHeadroomDB = trimmedEnvironmentValue(environment[headroomDBEnvironmentKey])

        if rawGain != nil, rawHeadroomDB != nil {
            return defaultPolicy.withWarning("conflicting_runtime_gain_policy")
        }

        if let rawGain {
            guard let parsedGain = Double(rawGain),
                  parsedGain.isFinite,
                  parsedGain > 0,
                  parsedGain <= 1 else {
                return defaultPolicy.withWarning("invalid_runtime_gain")
            }
            return RuntimeCMixerOutputPolicy(
                outputGain: Float(parsedGain),
                headroomPolicy: "env_runtime_gain"
            )
        }

        if let rawHeadroomDB {
            guard let parsedHeadroomDB = Double(rawHeadroomDB),
                  parsedHeadroomDB.isFinite,
                  parsedHeadroomDB <= 0 else {
                return defaultPolicy.withWarning("invalid_runtime_headroom_db")
            }
            let gain = pow(10.0, parsedHeadroomDB / 20.0)
            guard gain.isFinite,
                  gain > 0,
                  gain <= 1 else {
                return defaultPolicy.withWarning("invalid_runtime_headroom_db")
            }
            return RuntimeCMixerOutputPolicy(
                outputGain: Float(gain),
                headroomPolicy: "env_runtime_headroom_db",
                fixedHeadroomDB: parsedHeadroomDB
            )
        }

        return defaultPolicy
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func withWarning(_ warning: String) -> RuntimeCMixerOutputPolicy {
        RuntimeCMixerOutputPolicy(
            outputGain: outputGain,
            headroomPolicy: "\(headroomPolicy)_fallback",
            autoHeadroomEnabled: autoHeadroomEnabled,
            fixedHeadroomDB: fixedHeadroomDB,
            configurationWarning: warning
        )
    }
}

private struct RuntimeCMixerOutputMetrics: Equatable {
    let sampleCount: Int
    let peak: Float
    let squareSum: Double
    let overrangeSampleCount: Int
    let clippingSampleCount: Int

    var rms: Float {
        guard sampleCount > 0 else {
            return 0
        }
        return Float(sqrt(squareSum / Double(sampleCount)))
    }

    var isSilent: Bool {
        peak <= 0.000_001
    }

    static let silence = RuntimeCMixerOutputMetrics(
        sampleCount: 0,
        peak: 0,
        squareSum: 0,
        overrangeSampleCount: 0,
        clippingSampleCount: 0
    )
}

struct RuntimeCMixerTriggerResult: Equatable {
    let succeeded: Bool
    let reason: String?
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let channelStopBeforeAdd: RuntimeCMixerChannelStopResult?
}

struct RuntimeCMixerUpdateResult: Equatable {
    let channel: Int
    let targetVoiceIndex: Int?
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let gainPanApplied: Bool
    let stepApplied: Bool
    let gainPanAttempted: Bool
    let stepAttempted: Bool
    let gainBefore: Float?
    let gainAfter: Float?
    let panBefore: Float?
    let panAfter: Float?
    let sampleStepBefore: Double?
    let sampleStepAfter: Double?
    let updateEpsilon: Double?
    let gainRequested: Float?
    let panRequested: Float?
    let sampleStepRequested: Double?
    let gainDelta: Double?
    let panDelta: Double?
    let sampleStepDelta: Double?
    let gainUpdateStatus: String?
    let panUpdateStatus: String?
    let sampleStepUpdateStatus: String?
    let epsilonSuppressedGain: Bool
    let epsilonSuppressedPan: Bool
    let epsilonSuppressedStep: Bool
    let appliedAfterEpsilonFilter: Bool
    let disposition: String
    let updateType: String
    let succeeded: Bool?
    let reason: String

    init(
        channel: Int,
        targetVoiceIndex: Int?,
        snapshotBefore: RuntimeCMixerRenderSnapshot,
        snapshotAfter: RuntimeCMixerRenderSnapshot,
        gainPanApplied: Bool,
        stepApplied: Bool,
        gainPanAttempted: Bool,
        stepAttempted: Bool,
        gainBefore: Float?,
        gainAfter: Float?,
        panBefore: Float?,
        panAfter: Float?,
        sampleStepBefore: Double?,
        sampleStepAfter: Double?,
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
        epsilonSuppressedGain: Bool = false,
        epsilonSuppressedPan: Bool = false,
        epsilonSuppressedStep: Bool = false,
        appliedAfterEpsilonFilter: Bool = false,
        disposition: String,
        updateType: String,
        succeeded: Bool?,
        reason: String
    ) {
        self.channel = channel
        self.targetVoiceIndex = targetVoiceIndex
        self.snapshotBefore = snapshotBefore
        self.snapshotAfter = snapshotAfter
        self.gainPanApplied = gainPanApplied
        self.stepApplied = stepApplied
        self.gainPanAttempted = gainPanAttempted
        self.stepAttempted = stepAttempted
        self.gainBefore = gainBefore
        self.gainAfter = gainAfter
        self.panBefore = panBefore
        self.panAfter = panAfter
        self.sampleStepBefore = sampleStepBefore
        self.sampleStepAfter = sampleStepAfter
        self.updateEpsilon = updateEpsilon
        self.gainRequested = gainRequested
        self.panRequested = panRequested
        self.sampleStepRequested = sampleStepRequested
        self.gainDelta = gainDelta
        self.panDelta = panDelta
        self.sampleStepDelta = sampleStepDelta
        self.gainUpdateStatus = gainUpdateStatus
        self.panUpdateStatus = panUpdateStatus
        self.sampleStepUpdateStatus = sampleStepUpdateStatus
        self.epsilonSuppressedGain = epsilonSuppressedGain
        self.epsilonSuppressedPan = epsilonSuppressedPan
        self.epsilonSuppressedStep = epsilonSuppressedStep
        self.appliedAfterEpsilonFilter = appliedAfterEpsilonFilter
        self.disposition = disposition
        self.updateType = updateType
        self.succeeded = succeeded
        self.reason = reason
    }

    var traceAction: String {
        switch disposition {
        case "update_applied":
            switch (gainPanApplied, stepApplied) {
            case (true, true):
                return "c_mixer_update_gain_pan_step_applied"
            case (true, false):
                return "c_mixer_update_gain_pan_applied"
            case (false, true):
                return "c_mixer_update_step_applied"
            case (false, false):
                return "c_mixer_update_applied"
            }
        case "update_suppressed_no_change":
            return "c_mixer_update_suppressed_no_change"
        case "update_stored_channel_state":
            return "c_mixer_update_stored_channel_state"
        case "update_deferred_no_active_voice":
            return "c_mixer_update_deferred_no_active_voice"
        case "update_deferred_stale_after_stop":
            return "c_mixer_update_deferred_stale_after_stop"
        case "update_deferred_missing_data":
            return "c_mixer_update_deferred_missing_data"
        default:
            return "c_mixer_update_deferred_unsupported"
        }
    }
}

struct RuntimeCMixerChannelStopResult: Equatable {
    let channel: Int
    let stoppedVoiceCount: Int
    let rampedVoiceCount: Int
    let replacementRampFrames: Int?
    let replacementVoicesOverlap: Bool
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let reason: String
}

struct RuntimeCMixerStopResult: Equatable {
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let targetedAllVoices: Bool
    let stoppedVoiceCount: Int
    let reason: String
}

struct RuntimeCMixerPlannedCutResult: Equatable {
    let channel: Int
    let targetVoiceIndex: Int?
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let succeeded: Bool?
    let reason: String
}

private struct RuntimeCMixerChannelVoiceState: Equatable {
    let voiceIndex: Int
    let sample: PlaybackSample
    let note: UInt8
    var gain: Float
    var pan: Float
    var sampleStep: Double
}

private struct RuntimeCMixerAdapterVoiceState: Equatable {
    let voiceIndex: Int
    let channel: Int
    var gain: Float
    var pan: Float
    var sampleStep: Double
}

private struct RuntimeCMixerChannelControlState: Equatable {
    var volumeScale: Float
    var panning: Float
    var pitchOffsetSemitones: Double

    init(volumeScale: Float, panning: Float, pitchOffsetSemitones: Double) {
        self.volumeScale = PlaybackVolumeCalculator.clamped(volumeScale)
        self.panning = panning.isFinite ? min(1, max(-1, panning)) : 0
        self.pitchOffsetSemitones = pitchOffsetSemitones.isFinite ? pitchOffsetSemitones : 0
    }
}

private struct RuntimeCMixerFieldUpdateDecision: Equatable {
    let previous: Double
    let requested: Double
    let delta: Double
    let shouldApply: Bool
    let suppressedByEpsilon: Bool

    var status: String {
        if shouldApply {
            return "applied"
        }
        return suppressedByEpsilon ? "suppressed_epsilon" : "unchanged"
    }
}

final class RuntimeCMixerRenderCore: @unchecked Sendable {
    static let updateEpsilon = 0.00001

    private let lock = NSLock()
    private let mixer: CSoftwareMixer
    private let maximumRenderFrames: Int
    private var scratchInterleavedPCM: [Float]
    private var voiceStateByChannel = [Int: RuntimeCMixerChannelVoiceState]()
    private var adapterVoiceStateByEventIndex = [Int: RuntimeCMixerAdapterVoiceState]()
    private var adapterEventIndexByChannel = [Int: Int]()
    private var controlStateByChannel = [Int: RuntimeCMixerChannelControlState]()
    private var stoppedFrameByChannel = [Int: UInt64]()
    private var renderCallCount: UInt64 = 0
    private var renderCallbackCount: UInt64 = 0
    private var successfulRenderCount: UInt64 = 0
    private var failedRenderCount: UInt64 = 0
    private var cumulativeRequestedFrameCount: UInt64 = 0
    private var renderedFrameCount: UInt64 = 0
    private var minRequestedFrameCount: Int?
    private var maxRequestedFrameCount: Int?
    private var lastRequestedFrameCount: Int?
    private var lastRenderedFrameCount: Int?
    private var lastRenderSucceeded: Bool?
    private var lastCallbackIndex: UInt64?
    private var lastCallbackRequestedFrameCount: Int?
    private var lastCallbackStartFrame: UInt64?
    private var lastCallbackEndFrame: UInt64?
    private var zeroFillCount: UInt64 = 0
    private var underrunCount: UInt64 = 0
    private var silentOutputCallbackCount: UInt64 = 0
    private var unexpectedSilentOutputCount: UInt64 = 0
    private var cumulativeOutputSampleCount: UInt64 = 0
    private var cumulativeOutputSquareSum = Double(0)
    private var outputPeak = Float(0)
    private var lastOutputPeak = Float(0)
    private var lastOutputRMS = Float(0)
    private var overrangeSampleCount: UInt64 = 0
    private var clippingSampleCount: UInt64 = 0

    let config: MixerRenderConfig
    let outputPolicy: RuntimeCMixerOutputPolicy

    init(
        config: MixerRenderConfig = MixerRenderConfig(),
        maximumRenderFrames: Int = 16_384,
        outputPolicy: RuntimeCMixerOutputPolicy = .defaultPolicy
    ) {
        self.config = config
        self.outputPolicy = outputPolicy
        self.maximumRenderFrames = max(1, maximumRenderFrames)
        mixer = CSoftwareMixer(config: config)
        scratchInterleavedPCM = Array(repeating: 0, count: self.maximumRenderFrames * mixer.config.channelCount)
    }

    @discardableResult
    func trigger(_ request: AudioVoiceRequest) -> Bool {
        triggerWithDiagnostics(request).succeeded
    }

    @discardableResult
    func triggerWithDiagnostics(_ request: AudioVoiceRequest) -> RuntimeCMixerTriggerResult {
        let invalidReason: String?
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              request.channel >= 0,
              request.channel <= Int(UInt32.max),
              request.sampleStartOffset < request.sample.pcm.count else {
            if !request.sample.isPlayable {
                invalidReason = "sample_not_playable"
            } else if request.note == 0 || request.note > 96 {
                invalidReason = "invalid_note"
            } else if request.channel < 0 || request.channel > Int(UInt32.max) {
                invalidReason = "invalid_channel"
            } else {
                invalidReason = "sample_start_offset_out_of_range"
            }
            let snapshot = snapshot()
            return RuntimeCMixerTriggerResult(
                succeeded: false,
                reason: invalidReason,
                snapshotBefore: snapshot,
                snapshotAfter: snapshot,
                channelStopBeforeAdd: nil
            )
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        let snapshotBefore = snapshotLocked()
        let replacementRampBeforeAdd = rampDownReplacementChannelLocked(
            request.channel,
            reason: "note_replacement_stop_channel"
        )
        let requestControlState = RuntimeCMixerChannelControlState(
            volumeScale: request.volumeScale,
            panning: request.panning,
            pitchOffsetSemitones: request.pitchOffsetSemitones
        )
        let storedControlState = controlStateByChannel[request.channel]
        let effectiveControlState = RuntimeCMixerChannelControlState(
            volumeScale: storedControlState?.volumeScale ?? requestControlState.volumeScale,
            panning: storedControlState?.panning ?? requestControlState.panning,
            pitchOffsetSemitones: requestControlState.pitchOffsetSemitones
        )
        let initialGain = runtimeGain(sample: request.sample, volumeScale: effectiveControlState.volumeScale)
        let initialPan = sanitizedPan(effectiveControlState.panning)
        let initialSampleStep = playbackStep(
            note: request.note,
            sample: request.sample,
            pitchOffsetSemitones: effectiveControlState.pitchOffsetSemitones
        ) ?? 1

        let voiceIndex = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: request.sample.pcm),
            gain: initialGain,
            pan: initialPan,
            playbackStep: initialSampleStep,
            loop: mixerLoop(for: request.sample),
            initialSourceFrame: request.sampleStartOffset
        )
        mixer.setChannelTag(request.channel, forVoiceAt: voiceIndex)
        voiceStateByChannel[request.channel] = RuntimeCMixerChannelVoiceState(
            voiceIndex: voiceIndex,
            sample: request.sample,
            note: request.note,
            gain: initialGain,
            pan: initialPan,
            sampleStep: initialSampleStep
        )
        controlStateByChannel[request.channel] = effectiveControlState
        stoppedFrameByChannel.removeValue(forKey: request.channel)
        let snapshotAfter = snapshotLocked()
        let channelStopBeforeAdd: RuntimeCMixerChannelStopResult?
        if replacementRampBeforeAdd.rampedVoiceCount > 0 {
            channelStopBeforeAdd = RuntimeCMixerChannelStopResult(
                channel: replacementRampBeforeAdd.channel,
                stoppedVoiceCount: replacementRampBeforeAdd.stoppedVoiceCount,
                rampedVoiceCount: replacementRampBeforeAdd.rampedVoiceCount,
                replacementRampFrames: replacementRampBeforeAdd.replacementRampFrames,
                replacementVoicesOverlap: true,
                snapshotBefore: replacementRampBeforeAdd.snapshotBefore,
                snapshotAfter: snapshotAfter,
                reason: replacementRampBeforeAdd.reason
            )
        } else {
            channelStopBeforeAdd = nil
        }
        return RuntimeCMixerTriggerResult(
            succeeded: true,
            reason: nil,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotAfter,
            channelStopBeforeAdd: channelStopBeforeAdd
        )
    }

    @discardableResult
    func triggerAdapterEventWithDiagnostics(
        _ event: SyntheticTrackerEvent,
        eventIndex: Int,
        mapping: PlaybackSongSyntheticEventMapping
    ) -> RuntimeCMixerTriggerResult {
        let invalidReason: String?
        guard event.sample.frameCount > 0,
              mapping.note > 0,
              mapping.note <= 96,
              mapping.channelIndex >= 0,
              mapping.channelIndex <= Int(UInt32.max),
              event.initialSourceFrame < event.sample.frameCount else {
            if event.sample.frameCount <= 0 {
                invalidReason = "sample_not_playable"
            } else if mapping.note == 0 || mapping.note > 96 {
                invalidReason = "invalid_note"
            } else if mapping.channelIndex < 0 || mapping.channelIndex > Int(UInt32.max) {
                invalidReason = "invalid_channel"
            } else {
                invalidReason = "sample_start_offset_out_of_range"
            }
            let snapshot = snapshot()
            return RuntimeCMixerTriggerResult(
                succeeded: false,
                reason: invalidReason,
                snapshotBefore: snapshot,
                snapshotAfter: snapshot,
                channelStopBeforeAdd: nil
            )
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        guard mixer.currentFrame <= UInt64(Int.max) else {
            let snapshot = snapshotLocked()
            return RuntimeCMixerTriggerResult(
                succeeded: false,
                reason: "current_frame_out_of_range",
                snapshotBefore: snapshot,
                snapshotAfter: snapshot,
                channelStopBeforeAdd: nil
            )
        }

        let snapshotBefore = snapshotLocked()
        let replacementRampBeforeAdd = rampDownReplacementChannelLocked(
            mapping.channelIndex,
            reason: "note_replacement_stop_channel"
        )
        let runtimeKeyOffFrame = runtimeKeyOffFrame(
            plannedKeyOffFrame: event.keyOffFrame,
            plannedStartFrame: event.scheduledStartFrame ?? 0,
            runtimeStartFrame: Int(mixer.currentFrame)
        )
        let voiceIndex = mixer.addVoice(
            sample: event.sample,
            gain: event.gain,
            pan: event.pan,
            playbackStep: event.playbackStep,
            loop: event.loop,
            initialSourceFrame: event.initialSourceFrame,
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: runtimeKeyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
        mixer.setChannelTag(mapping.channelIndex, forVoiceAt: voiceIndex)
        adapterVoiceStateByEventIndex[eventIndex] = RuntimeCMixerAdapterVoiceState(
            voiceIndex: voiceIndex,
            channel: mapping.channelIndex,
            gain: event.gain,
            pan: event.pan,
            sampleStep: event.playbackStep
        )
        adapterEventIndexByChannel[mapping.channelIndex] = eventIndex
        stoppedFrameByChannel.removeValue(forKey: mapping.channelIndex)
        let snapshotAfter = snapshotLocked()
        let channelStopBeforeAdd: RuntimeCMixerChannelStopResult?
        if replacementRampBeforeAdd.rampedVoiceCount > 0 {
            channelStopBeforeAdd = RuntimeCMixerChannelStopResult(
                channel: replacementRampBeforeAdd.channel,
                stoppedVoiceCount: replacementRampBeforeAdd.stoppedVoiceCount,
                rampedVoiceCount: replacementRampBeforeAdd.rampedVoiceCount,
                replacementRampFrames: replacementRampBeforeAdd.replacementRampFrames,
                replacementVoicesOverlap: true,
                snapshotBefore: replacementRampBeforeAdd.snapshotBefore,
                snapshotAfter: snapshotAfter,
                reason: replacementRampBeforeAdd.reason
            )
        } else {
            channelStopBeforeAdd = nil
        }
        return RuntimeCMixerTriggerResult(
            succeeded: true,
            reason: nil,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotAfter,
            channelStopBeforeAdd: channelStopBeforeAdd
        )
    }

    func update(channel: Int, controls: AudioChannelControls) {
        _ = updateWithDiagnostics(channel: channel, controls: controls)
    }

    @discardableResult
    func updateWithDiagnostics(
        channel: Int,
        controls: AudioChannelControls,
        context: AudioRuntimeTraceContext? = nil
    ) -> RuntimeCMixerUpdateResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        let snapshotBefore = snapshotLocked()
        guard channel >= 0 && channel <= Int(UInt32.max) else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: nil,
                gainAfter: nil,
                panBefore: nil,
                panAfter: nil,
                sampleStepBefore: nil,
                sampleStepAfter: nil,
                disposition: "update_deferred_unsupported",
                updateType: "none",
                succeeded: false,
                reason: "runtime_c_mixer_update_deferred_unsupported_invalid_channel"
            )
        }
        guard controls.volumeScale.isFinite,
              controls.panning.isFinite,
              controls.pitchOffsetSemitones.isFinite else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceStateByChannel[channel]?.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: voiceStateByChannel[channel]?.gain,
                gainAfter: nil,
                panBefore: voiceStateByChannel[channel]?.pan,
                panAfter: nil,
                sampleStepBefore: voiceStateByChannel[channel]?.sampleStep,
                sampleStepAfter: nil,
                disposition: "update_deferred_unsupported",
                updateType: "none",
                succeeded: false,
                reason: "runtime_c_mixer_update_deferred_unsupported_invalid_update_values"
            )
        }
        let nextControlState = RuntimeCMixerChannelControlState(
            volumeScale: controls.volumeScale,
            panning: controls.panning,
            pitchOffsetSemitones: controls.pitchOffsetSemitones
        )
        guard var voiceState = voiceStateByChannel[channel] else {
            return updateWithoutActiveVoiceLocked(
                channel: channel,
                nextControlState: nextControlState,
                snapshotBefore: snapshotBefore,
                context: context
            )
        }
        guard voiceState.sample.baseSampleRate.isFinite,
              voiceState.sample.baseSampleRate > 0 else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: true,
                gainBefore: voiceState.gain,
                gainAfter: nil,
                panBefore: voiceState.pan,
                panAfter: nil,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: nil,
                disposition: "update_deferred_missing_data",
                updateType: "step",
                succeeded: false,
                reason: "runtime_c_mixer_update_deferred_missing_data_missing_sample_step_target"
            )
        }
        guard let nextSampleStep = playbackStep(
            note: voiceState.note,
            sample: voiceState.sample,
            pitchOffsetSemitones: nextControlState.pitchOffsetSemitones
        ) else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: true,
                gainBefore: voiceState.gain,
                gainAfter: nil,
                panBefore: voiceState.pan,
                panAfter: nil,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: nil,
                disposition: "update_deferred_missing_data",
                updateType: "step",
                succeeded: false,
                reason: "runtime_c_mixer_update_deferred_missing_data_missing_sample_step_target"
            )
        }
        guard mixer.currentFrame <= UInt64(Int.max) else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: voiceState.gain,
                gainAfter: nil,
                panBefore: voiceState.pan,
                panAfter: nil,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: nil,
                disposition: "update_deferred_missing_data",
                updateType: "none",
                succeeded: false,
                reason: "runtime_c_mixer_update_deferred_missing_data_frame_out_of_range"
            )
        }

        let nextGain = runtimeGain(sample: voiceState.sample, volumeScale: nextControlState.volumeScale)
        let nextPan = sanitizedPan(nextControlState.panning)
        let scheduledFrame = Int(mixer.currentFrame)
        let currentControlState = controlStateByChannel[channel] ?? defaultControlState(for: channel)
        let gainDecision = updateDecision(previous: Double(voiceState.gain), requested: Double(nextGain))
        let panDecision = updateDecision(previous: Double(voiceState.pan), requested: Double(nextPan))
        let stepDecision = updateDecision(previous: voiceState.sampleStep, requested: nextSampleStep)
        let gainChanged = gainDecision.shouldApply
        let panChanged = panDecision.shouldApply
        let gainPanChanged = gainChanged || panChanged
        let stepChanged = stepDecision.shouldApply
        let updateType = self.updateType(gainChanged: gainChanged, panChanged: panChanged, stepChanged: stepChanged)
        guard gainPanChanged || stepChanged else {
            let epsilonSuppressed = gainDecision.suppressedByEpsilon || panDecision.suppressedByEpsilon || stepDecision.suppressedByEpsilon
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: voiceState.gain,
                gainAfter: voiceState.gain,
                panBefore: voiceState.pan,
                panAfter: voiceState.pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: voiceState.sampleStep,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: nextGain,
                panRequested: nextPan,
                sampleStepRequested: nextSampleStep,
                gainDelta: gainDecision.delta,
                panDelta: panDecision.delta,
                sampleStepDelta: stepDecision.delta,
                gainUpdateStatus: gainDecision.status,
                panUpdateStatus: panDecision.status,
                sampleStepUpdateStatus: stepDecision.status,
                epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
                epsilonSuppressedPan: panDecision.suppressedByEpsilon,
                epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
                disposition: "update_suppressed_no_change",
                updateType: updateType,
                succeeded: nil,
                reason: epsilonSuppressed
                    ? "runtime_c_mixer_update_suppressed_no_change_epsilon_filtered"
                    : "runtime_c_mixer_update_suppressed_no_change"
            )
        }
        let updateResult: CSoftwareMixerVoiceStateUpdateResult
        if gainPanChanged, stepChanged {
            updateResult = mixer.scheduleVoiceGainPanStepUpdate(
                voiceIndex: voiceState.voiceIndex,
                scheduledFrame: scheduledFrame,
                gain: gainChanged ? nextGain : nil,
                pan: panChanged ? nextPan : nil,
                playbackStep: nextSampleStep
            )
        } else if gainPanChanged {
            updateResult = mixer.scheduleVoiceGainPanUpdate(
                voiceIndex: voiceState.voiceIndex,
                scheduledFrame: scheduledFrame,
                gain: gainChanged ? nextGain : nil,
                pan: panChanged ? nextPan : nil
            )
        } else {
            updateResult = mixer.scheduleVoicePlaybackStepUpdate(
                voiceIndex: voiceState.voiceIndex,
                scheduledFrame: scheduledFrame,
                playbackStep: nextSampleStep
            )
        }
        guard updateResult.wasAccepted else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotLocked(),
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: gainPanChanged,
                stepAttempted: stepChanged,
                gainBefore: voiceState.gain,
                gainAfter: nextGain,
                panBefore: voiceState.pan,
                panAfter: nextPan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: nextSampleStep,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: nextGain,
                panRequested: nextPan,
                sampleStepRequested: nextSampleStep,
                gainDelta: gainDecision.delta,
                panDelta: panDecision.delta,
                sampleStepDelta: stepDecision.delta,
                gainUpdateStatus: gainDecision.status,
                panUpdateStatus: panDecision.status,
                sampleStepUpdateStatus: stepDecision.status,
                epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
                epsilonSuppressedPan: panDecision.suppressedByEpsilon,
                epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
                disposition: "update_deferred_unsupported",
                updateType: updateType,
                succeeded: false,
                reason: updateResult.rejectionReason?.rawValue ?? "runtime_c_mixer_update_deferred_unsupported_c_mixer_rejected"
            )
        }

        let gainBefore = voiceState.gain
        let panBefore = voiceState.pan
        let sampleStepBefore = voiceState.sampleStep
        voiceState.gain = gainChanged ? nextGain : voiceState.gain
        voiceState.pan = panChanged ? nextPan : voiceState.pan
        voiceState.sampleStep = stepChanged ? nextSampleStep : voiceState.sampleStep
        voiceStateByChannel[channel] = voiceState
        controlStateByChannel[channel] = RuntimeCMixerChannelControlState(
            volumeScale: gainChanged ? nextControlState.volumeScale : currentControlState.volumeScale,
            panning: panChanged ? nextControlState.panning : currentControlState.panning,
            pitchOffsetSemitones: stepChanged ? nextControlState.pitchOffsetSemitones : currentControlState.pitchOffsetSemitones
        )
        let epsilonSuppressed = gainDecision.suppressedByEpsilon || panDecision.suppressedByEpsilon || stepDecision.suppressedByEpsilon
        return RuntimeCMixerUpdateResult(
            channel: channel,
            targetVoiceIndex: voiceState.voiceIndex,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            gainPanApplied: gainPanChanged,
            stepApplied: stepChanged,
            gainPanAttempted: gainPanChanged,
            stepAttempted: stepChanged,
            gainBefore: gainBefore,
            gainAfter: voiceState.gain,
            panBefore: panBefore,
            panAfter: voiceState.pan,
            sampleStepBefore: sampleStepBefore,
            sampleStepAfter: voiceState.sampleStep,
            updateEpsilon: Self.updateEpsilon,
            gainRequested: nextGain,
            panRequested: nextPan,
            sampleStepRequested: nextSampleStep,
            gainDelta: gainDecision.delta,
            panDelta: panDecision.delta,
            sampleStepDelta: stepDecision.delta,
            gainUpdateStatus: gainDecision.status,
            panUpdateStatus: panDecision.status,
            sampleStepUpdateStatus: stepDecision.status,
            epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
            epsilonSuppressedPan: panDecision.suppressedByEpsilon,
            epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
            appliedAfterEpsilonFilter: true,
            disposition: "update_applied",
            updateType: updateType,
            succeeded: true,
            reason: appliedUpdateReason(gainPanChanged: gainPanChanged, stepChanged: stepChanged, epsilonSuppressed: epsilonSuppressed)
        )
    }

    private func updateWithoutActiveVoiceLocked(
        channel: Int,
        nextControlState: RuntimeCMixerChannelControlState,
        snapshotBefore: RuntimeCMixerRenderSnapshot,
        context: AudioRuntimeTraceContext?
    ) -> RuntimeCMixerUpdateResult {
        let currentControlState = controlStateByChannel[channel] ?? defaultControlState(for: channel)
        let gainDecision = updateDecision(previous: Double(currentControlState.volumeScale), requested: Double(nextControlState.volumeScale))
        let panDecision = updateDecision(previous: Double(currentControlState.panning), requested: Double(nextControlState.panning))
        let stepDecision = updateDecision(previous: currentControlState.pitchOffsetSemitones, requested: nextControlState.pitchOffsetSemitones)
        let gainChanged = gainDecision.shouldApply
        let panChanged = panDecision.shouldApply
        let stepChanged = stepDecision.shouldApply
        let updateType = self.updateType(gainChanged: gainChanged, panChanged: panChanged, stepChanged: stepChanged)

        guard stoppedFrameByChannel[channel] == nil else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: gainChanged || panChanged,
                stepAttempted: stepChanged,
                gainBefore: currentControlState.volumeScale,
                gainAfter: nextControlState.volumeScale,
                panBefore: currentControlState.panning,
                panAfter: nextControlState.panning,
                sampleStepBefore: nil,
                sampleStepAfter: nil,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: nextControlState.volumeScale,
                panRequested: nextControlState.panning,
                sampleStepRequested: nextControlState.pitchOffsetSemitones,
                gainDelta: gainDecision.delta,
                panDelta: panDecision.delta,
                sampleStepDelta: stepDecision.delta,
                gainUpdateStatus: gainDecision.status,
                panUpdateStatus: panDecision.status,
                sampleStepUpdateStatus: stepDecision.status,
                epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
                epsilonSuppressedPan: panDecision.suppressedByEpsilon,
                epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
                disposition: "update_deferred_stale_after_stop",
                updateType: updateType,
                succeeded: nil,
                reason: "runtime_c_mixer_update_deferred_stale_after_stop"
            )
        }

        if gainChanged || panChanged {
            let classification = noActiveVoiceClassification(
                context: context,
                hasStoredControlState: controlStateByChannel[channel] != nil,
                hasStepChange: stepChanged
            )
            controlStateByChannel[channel] = RuntimeCMixerChannelControlState(
                volumeScale: gainChanged ? nextControlState.volumeScale : currentControlState.volumeScale,
                panning: panChanged ? nextControlState.panning : currentControlState.panning,
                pitchOffsetSemitones: currentControlState.pitchOffsetSemitones
            )
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: true,
                stepAttempted: stepChanged,
                gainBefore: currentControlState.volumeScale,
                gainAfter: gainChanged ? nextControlState.volumeScale : currentControlState.volumeScale,
                panBefore: currentControlState.panning,
                panAfter: panChanged ? nextControlState.panning : currentControlState.panning,
                sampleStepBefore: nil,
                sampleStepAfter: nil,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: nextControlState.volumeScale,
                panRequested: nextControlState.panning,
                sampleStepRequested: nextControlState.pitchOffsetSemitones,
                gainDelta: gainDecision.delta,
                panDelta: panDecision.delta,
                sampleStepDelta: stepDecision.delta,
                gainUpdateStatus: gainDecision.status,
                panUpdateStatus: panDecision.status,
                sampleStepUpdateStatus: stepDecision.status,
                epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
                epsilonSuppressedPan: panDecision.suppressedByEpsilon,
                epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
                disposition: "update_stored_channel_state",
                updateType: updateType,
                succeeded: nil,
                reason: stepChanged
                    ? "runtime_c_mixer_update_stored_channel_state_\(classification)_step_deferred_no_active_voice"
                    : "runtime_c_mixer_update_stored_channel_state_\(classification)"
            )
        }

        guard stepChanged else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: currentControlState.volumeScale,
                gainAfter: currentControlState.volumeScale,
                panBefore: currentControlState.panning,
                panAfter: currentControlState.panning,
                sampleStepBefore: nil,
                sampleStepAfter: nil,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: nextControlState.volumeScale,
                panRequested: nextControlState.panning,
                sampleStepRequested: nextControlState.pitchOffsetSemitones,
                gainDelta: gainDecision.delta,
                panDelta: panDecision.delta,
                sampleStepDelta: stepDecision.delta,
                gainUpdateStatus: gainDecision.status,
                panUpdateStatus: panDecision.status,
                sampleStepUpdateStatus: stepDecision.status,
                epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
                epsilonSuppressedPan: panDecision.suppressedByEpsilon,
                epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
                disposition: "update_suppressed_no_change",
                updateType: "none",
                succeeded: nil,
                reason: gainDecision.suppressedByEpsilon || panDecision.suppressedByEpsilon || stepDecision.suppressedByEpsilon
                    ? "runtime_c_mixer_update_suppressed_no_change_harmless_no_active_voice_epsilon_filtered"
                    : "runtime_c_mixer_update_suppressed_no_change_harmless_no_active_voice"
            )
        }

        let classification = noActiveVoiceClassification(
            context: context,
            hasStoredControlState: controlStateByChannel[channel] != nil,
            hasStepChange: true
        )
        return RuntimeCMixerUpdateResult(
            channel: channel,
            targetVoiceIndex: nil,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotBefore,
            gainPanApplied: false,
            stepApplied: false,
            gainPanAttempted: false,
            stepAttempted: true,
            gainBefore: currentControlState.volumeScale,
            gainAfter: nextControlState.volumeScale,
            panBefore: currentControlState.panning,
            panAfter: nextControlState.panning,
            sampleStepBefore: nil,
            sampleStepAfter: nil,
            updateEpsilon: Self.updateEpsilon,
            gainRequested: nextControlState.volumeScale,
            panRequested: nextControlState.panning,
            sampleStepRequested: nextControlState.pitchOffsetSemitones,
            gainDelta: gainDecision.delta,
            panDelta: panDecision.delta,
            sampleStepDelta: stepDecision.delta,
            gainUpdateStatus: gainDecision.status,
            panUpdateStatus: panDecision.status,
            sampleStepUpdateStatus: stepDecision.status,
            epsilonSuppressedGain: gainDecision.suppressedByEpsilon,
            epsilonSuppressedPan: panDecision.suppressedByEpsilon,
            epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
            disposition: "update_deferred_no_active_voice",
            updateType: "step",
            succeeded: nil,
            reason: "runtime_c_mixer_update_deferred_no_active_voice_\(classification)"
        )
    }

    @discardableResult
    func applyAdapterGainPanUpdateWithDiagnostics(
        channel: Int,
        activeEventIndex: Int,
        gain: Float?,
        pan: Float?
    ) -> RuntimeCMixerUpdateResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        let snapshotBefore = snapshotLocked()
        guard var voiceState = adapterVoiceStateByEventIndex[activeEventIndex] else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: gain != nil || pan != nil,
                stepAttempted: false,
                gainBefore: nil,
                gainAfter: gain,
                panBefore: nil,
                panAfter: pan,
                sampleStepBefore: nil,
                sampleStepAfter: nil,
                disposition: "update_deferred_no_active_voice",
                updateType: "none",
                succeeded: nil,
                reason: "runtime_c_mixer_adapter_plan_unmatched_active_voice"
            )
        }
        guard mixer.currentFrame <= UInt64(Int.max) else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: gain != nil || pan != nil,
                stepAttempted: false,
                gainBefore: voiceState.gain,
                gainAfter: gain,
                panBefore: voiceState.pan,
                panAfter: pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: voiceState.sampleStep,
                disposition: "update_deferred_missing_data",
                updateType: "none",
                succeeded: false,
                reason: "runtime_c_mixer_adapter_plan_frame_out_of_range"
            )
        }
        let gainDecision = gain.map { updateDecision(previous: Double(voiceState.gain), requested: Double($0)) }
        let panDecision = pan.map { updateDecision(previous: Double(voiceState.pan), requested: Double($0)) }
        let nextGain = gainDecision?.shouldApply == true ? gain : nil
        let nextPan = panDecision?.shouldApply == true ? pan : nil
        let gainChanged = nextGain != nil
        let panChanged = nextPan != nil
        let updateType = self.updateType(gainChanged: gainChanged, panChanged: panChanged, stepChanged: false)
        guard gainChanged || panChanged else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: voiceState.gain,
                gainAfter: voiceState.gain,
                panBefore: voiceState.pan,
                panAfter: voiceState.pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: voiceState.sampleStep,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: gain,
                panRequested: pan,
                gainDelta: gainDecision?.delta,
                panDelta: panDecision?.delta,
                gainUpdateStatus: gainDecision?.status,
                panUpdateStatus: panDecision?.status,
                epsilonSuppressedGain: gainDecision?.suppressedByEpsilon ?? false,
                epsilonSuppressedPan: panDecision?.suppressedByEpsilon ?? false,
                disposition: "update_suppressed_no_change",
                updateType: updateType,
                succeeded: nil,
                reason: "runtime_c_mixer_adapter_plan_update_suppressed_no_change"
            )
        }
        let updateResult = mixer.scheduleVoiceGainPanUpdate(
            voiceIndex: voiceState.voiceIndex,
            scheduledFrame: Int(mixer.currentFrame),
            gain: nextGain,
            pan: nextPan
        )
        guard updateResult.wasAccepted else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotLocked(),
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: true,
                stepAttempted: false,
                gainBefore: voiceState.gain,
                gainAfter: gain,
                panBefore: voiceState.pan,
                panAfter: pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: voiceState.sampleStep,
                updateEpsilon: Self.updateEpsilon,
                gainRequested: gain,
                panRequested: pan,
                gainDelta: gainDecision?.delta,
                panDelta: panDecision?.delta,
                gainUpdateStatus: gainDecision?.status,
                panUpdateStatus: panDecision?.status,
                disposition: "update_deferred_unsupported",
                updateType: updateType,
                succeeded: false,
                reason: updateResult.rejectionReason?.rawValue ?? "runtime_c_mixer_adapter_plan_update_rejected"
            )
        }
        let gainBefore = voiceState.gain
        let panBefore = voiceState.pan
        voiceState.gain = nextGain ?? voiceState.gain
        voiceState.pan = nextPan ?? voiceState.pan
        adapterVoiceStateByEventIndex[activeEventIndex] = voiceState
        return RuntimeCMixerUpdateResult(
            channel: channel,
            targetVoiceIndex: voiceState.voiceIndex,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            gainPanApplied: true,
            stepApplied: false,
            gainPanAttempted: true,
            stepAttempted: false,
            gainBefore: gainBefore,
            gainAfter: voiceState.gain,
            panBefore: panBefore,
            panAfter: voiceState.pan,
            sampleStepBefore: voiceState.sampleStep,
            sampleStepAfter: voiceState.sampleStep,
            updateEpsilon: Self.updateEpsilon,
            gainRequested: gain,
            panRequested: pan,
            gainDelta: gainDecision?.delta,
            panDelta: panDecision?.delta,
            gainUpdateStatus: gainDecision?.status,
            panUpdateStatus: panDecision?.status,
            epsilonSuppressedGain: gainDecision?.suppressedByEpsilon ?? false,
            epsilonSuppressedPan: panDecision?.suppressedByEpsilon ?? false,
            appliedAfterEpsilonFilter: gainDecision?.suppressedByEpsilon == true || panDecision?.suppressedByEpsilon == true,
            disposition: "update_applied",
            updateType: updateType,
            succeeded: true,
            reason: "runtime_c_mixer_adapter_plan_gain_pan_update_applied"
        )
    }

    @discardableResult
    func applyAdapterStepUpdateWithDiagnostics(
        channel: Int,
        activeEventIndex: Int,
        playbackStep: Double
    ) -> RuntimeCMixerUpdateResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        let snapshotBefore = snapshotLocked()
        guard var voiceState = adapterVoiceStateByEventIndex[activeEventIndex] else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: true,
                gainBefore: nil,
                gainAfter: nil,
                panBefore: nil,
                panAfter: nil,
                sampleStepBefore: nil,
                sampleStepAfter: playbackStep,
                disposition: "update_deferred_no_active_voice",
                updateType: "step",
                succeeded: nil,
                reason: "runtime_c_mixer_adapter_plan_unmatched_active_voice"
            )
        }
        guard playbackStep.isFinite,
              playbackStep > 0,
              mixer.currentFrame <= UInt64(Int.max) else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: true,
                gainBefore: voiceState.gain,
                gainAfter: voiceState.gain,
                panBefore: voiceState.pan,
                panAfter: voiceState.pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: playbackStep,
                disposition: "update_deferred_missing_data",
                updateType: "step",
                succeeded: false,
                reason: "runtime_c_mixer_adapter_plan_invalid_step_update"
            )
        }
        let stepDecision = updateDecision(previous: voiceState.sampleStep, requested: playbackStep)
        guard stepDecision.shouldApply else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: false,
                gainBefore: voiceState.gain,
                gainAfter: voiceState.gain,
                panBefore: voiceState.pan,
                panAfter: voiceState.pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: voiceState.sampleStep,
                updateEpsilon: Self.updateEpsilon,
                sampleStepRequested: playbackStep,
                sampleStepDelta: stepDecision.delta,
                sampleStepUpdateStatus: stepDecision.status,
                epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
                disposition: "update_suppressed_no_change",
                updateType: "none",
                succeeded: nil,
                reason: "runtime_c_mixer_adapter_plan_update_suppressed_no_change"
            )
        }
        let updateResult = mixer.scheduleVoicePlaybackStepUpdate(
            voiceIndex: voiceState.voiceIndex,
            scheduledFrame: Int(mixer.currentFrame),
            playbackStep: playbackStep
        )
        guard updateResult.wasAccepted else {
            return RuntimeCMixerUpdateResult(
                channel: channel,
                targetVoiceIndex: voiceState.voiceIndex,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotLocked(),
                gainPanApplied: false,
                stepApplied: false,
                gainPanAttempted: false,
                stepAttempted: true,
                gainBefore: voiceState.gain,
                gainAfter: voiceState.gain,
                panBefore: voiceState.pan,
                panAfter: voiceState.pan,
                sampleStepBefore: voiceState.sampleStep,
                sampleStepAfter: playbackStep,
                updateEpsilon: Self.updateEpsilon,
                sampleStepRequested: playbackStep,
                sampleStepDelta: stepDecision.delta,
                sampleStepUpdateStatus: stepDecision.status,
                disposition: "update_deferred_unsupported",
                updateType: "step",
                succeeded: false,
                reason: updateResult.rejectionReason?.rawValue ?? "runtime_c_mixer_adapter_plan_update_rejected"
            )
        }
        let stepBefore = voiceState.sampleStep
        voiceState.sampleStep = playbackStep
        adapterVoiceStateByEventIndex[activeEventIndex] = voiceState
        return RuntimeCMixerUpdateResult(
            channel: channel,
            targetVoiceIndex: voiceState.voiceIndex,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            gainPanApplied: false,
            stepApplied: true,
            gainPanAttempted: false,
            stepAttempted: true,
            gainBefore: voiceState.gain,
            gainAfter: voiceState.gain,
            panBefore: voiceState.pan,
            panAfter: voiceState.pan,
            sampleStepBefore: stepBefore,
            sampleStepAfter: voiceState.sampleStep,
            updateEpsilon: Self.updateEpsilon,
            sampleStepRequested: playbackStep,
            sampleStepDelta: stepDecision.delta,
            sampleStepUpdateStatus: stepDecision.status,
            epsilonSuppressedStep: stepDecision.suppressedByEpsilon,
            disposition: "update_applied",
            updateType: "step",
            succeeded: true,
            reason: "runtime_c_mixer_adapter_plan_step_update_applied"
        )
    }

    @discardableResult
    func applyAdapterNoteCutWithDiagnostics(
        channel: Int,
        activeEventIndex: Int?
    ) -> RuntimeCMixerPlannedCutResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        let snapshotBefore = snapshotLocked()
        guard let activeEventIndex,
              let voiceState = adapterVoiceStateByEventIndex[activeEventIndex],
              mixer.currentFrame <= UInt64(Int.max) else {
            return RuntimeCMixerPlannedCutResult(
                channel: channel,
                targetVoiceIndex: nil,
                snapshotBefore: snapshotBefore,
                snapshotAfter: snapshotBefore,
                succeeded: nil,
                reason: "runtime_c_mixer_adapter_plan_note_cut_unmatched_active_voice"
            )
        }
        let updateResult = mixer.scheduleVoiceGainPanImmediateUpdate(
            voiceIndex: voiceState.voiceIndex,
            scheduledFrame: Int(mixer.currentFrame),
            gain: 0,
            pan: nil
        )
        adapterVoiceStateByEventIndex.removeValue(forKey: activeEventIndex)
        if adapterEventIndexByChannel[channel] == activeEventIndex {
            adapterEventIndexByChannel.removeValue(forKey: channel)
        }
        return RuntimeCMixerPlannedCutResult(
            channel: channel,
            targetVoiceIndex: voiceState.voiceIndex,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            succeeded: updateResult.wasAccepted,
            reason: updateResult.wasAccepted
                ? "runtime_c_mixer_adapter_plan_note_cut_applied"
                : updateResult.rejectionReason?.rawValue ?? "runtime_c_mixer_adapter_plan_note_cut_rejected"
        )
    }

    private func noActiveVoiceClassification(
        context: AudioRuntimeTraceContext?,
        hasStoredControlState: Bool,
        hasStepChange: Bool
    ) -> String {
        if let noteValue = context?.noteValue,
           (1...96).contains(noteValue) {
            return "update_before_note"
        }
        if hasStepChange, !hasStoredControlState {
            return "missing_runtime_channel_state"
        }
        if context == nil, !hasStoredControlState {
            return "unknown"
        }
        return "harmless_no_active_voice"
    }

    private func updateDecision(previous: Double, requested: Double) -> RuntimeCMixerFieldUpdateDecision {
        let delta = abs(requested - previous)
        let suppressedByEpsilon = delta > 0 && delta <= Self.updateEpsilon
        return RuntimeCMixerFieldUpdateDecision(
            previous: previous,
            requested: requested,
            delta: delta,
            shouldApply: delta > Self.updateEpsilon,
            suppressedByEpsilon: suppressedByEpsilon
        )
    }

    private func appliedUpdateReason(gainPanChanged: Bool, stepChanged: Bool, epsilonSuppressed: Bool) -> String {
        if epsilonSuppressed {
            return "runtime_c_mixer_update_applied_after_epsilon_filter"
        }
        if gainPanChanged && stepChanged {
            return "runtime_c_mixer_update_applied_combined"
        }
        return gainPanChanged
            ? "runtime_c_mixer_update_applied_gain_pan"
            : "runtime_c_mixer_update_applied_step"
    }

    private func updateType(gainChanged: Bool, panChanged: Bool, stepChanged: Bool) -> String {
        let changedCount = [gainChanged, panChanged, stepChanged].filter { $0 }.count
        if changedCount == 0 {
            return "none"
        }
        if changedCount > 1 {
            return "combined"
        }
        if gainChanged {
            return "gain"
        }
        if panChanged {
            return "pan"
        }
        return "step"
    }

    func stop(channel: Int) {
        _ = stopChannelWithDiagnostics(channel, reason: "channel_stop")
    }

    func stopAll() {
        _ = stopAllWithDiagnostics(reason: "transport_stop_all")
    }

    @discardableResult
    func stopChannelWithDiagnostics(_ channel: Int, reason: String) -> RuntimeCMixerChannelStopResult {
        lock.lock()
        defer {
            lock.unlock()
        }
        return stopChannelLocked(channel, reason: reason)
    }

    @discardableResult
    func stopAllWithDiagnostics(reason: String) -> RuntimeCMixerStopResult {
        lock.lock()
        defer {
            lock.unlock()
        }
        let snapshotBefore = snapshotLocked()
        resetLocked()
        return RuntimeCMixerStopResult(
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            targetedAllVoices: true,
            stoppedVoiceCount: snapshotBefore.loadedVoiceCount,
            reason: reason
        )
    }

    @discardableResult
    func render(into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>, frameCount: Int) -> Bool {
        let safeFrameCount = max(0, frameCount)
        guard lock.try() else {
            clear(outputInterleavedPCM)
            return false
        }
        defer {
            lock.unlock()
        }
        let callbackStartFrame = mixer.currentFrame
        let activeVoiceCountBefore = mixer.activeVoiceCount
        let loadedVoiceCountBefore = mixer.loadedVoiceCount
        guard safeFrameCount > 0 else {
            recordRenderCompletionLocked(
                requestedFrameCount: safeFrameCount,
                renderedFrameCount: 0,
                callbackStartFrame: callbackStartFrame,
                callbackEndFrame: callbackStartFrame,
                succeeded: true,
                zeroFilled: false,
                activeVoiceCountBefore: activeVoiceCountBefore,
                loadedVoiceCountBefore: loadedVoiceCountBefore,
                outputMetrics: .silence
            )
            return true
        }
        guard safeFrameCount <= maximumRenderFrames,
              outputInterleavedPCM.count >= safeFrameCount * mixer.config.channelCount else {
            clear(outputInterleavedPCM)
            recordRenderCompletionLocked(
                requestedFrameCount: safeFrameCount,
                renderedFrameCount: 0,
                callbackStartFrame: callbackStartFrame,
                callbackEndFrame: callbackStartFrame,
                succeeded: false,
                zeroFilled: true,
                activeVoiceCountBefore: activeVoiceCountBefore,
                loadedVoiceCountBefore: loadedVoiceCountBefore,
                outputMetrics: .silence
            )
            return false
        }
        _ = mixer.render(into: outputInterleavedPCM, frames: safeFrameCount)
        let sampleCount = safeFrameCount * mixer.config.channelCount
        applyOutputGain(outputInterleavedPCM, sampleCount: sampleCount)
        recordRenderCompletionLocked(
            requestedFrameCount: safeFrameCount,
            renderedFrameCount: safeFrameCount,
            callbackStartFrame: callbackStartFrame,
            callbackEndFrame: mixer.currentFrame,
            succeeded: true,
            zeroFilled: false,
            activeVoiceCountBefore: activeVoiceCountBefore,
            loadedVoiceCountBefore: loadedVoiceCountBefore,
            outputMetrics: outputMetrics(outputInterleavedPCM, sampleCount: sampleCount)
        )
        return true
    }

    func render(frameCount: AVAudioFrameCount, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let safeFrameCount = Int(frameCount)

        // Audio callback safety rules: no AppKit, no parsing, no file I/O, no diagnostics logging, and no
        // allocation-heavy work. Voice/sample preparation happens on the main side before this callback; this
        // callback only renders the preloaded C mixer into preallocated scratch storage and copies it out.
        clear(ioData: ioData, frameCount: safeFrameCount)
        guard safeFrameCount > 0 else {
            return noErr
        }
        guard safeFrameCount <= maximumRenderFrames else {
            recordZeroFillCallback(frameCount: safeFrameCount)
            return noErr
        }

        let sampleCount = safeFrameCount * mixer.config.channelCount
        let rendered = scratchInterleavedPCM.withUnsafeMutableBufferPointer { scratch in
            render(
                into: UnsafeMutableBufferPointer(start: scratch.baseAddress, count: sampleCount),
                frameCount: safeFrameCount
            )
        }
        if rendered {
            copyScratchToAudioBuffers(ioData: ioData, frameCount: safeFrameCount)
        }
        return noErr
    }

    private func resetLocked() {
        mixer.clearVoices()
        mixer.reset()
        voiceStateByChannel.removeAll()
        adapterVoiceStateByEventIndex.removeAll()
        adapterEventIndexByChannel.removeAll()
        controlStateByChannel.removeAll()
        stoppedFrameByChannel.removeAll()
    }

    private func recordZeroFillCallback(frameCount: Int) {
        guard lock.try() else {
            return
        }
        defer {
            lock.unlock()
        }
        recordRenderCompletionLocked(
            requestedFrameCount: max(0, frameCount),
            renderedFrameCount: 0,
            callbackStartFrame: mixer.currentFrame,
            callbackEndFrame: mixer.currentFrame,
            succeeded: false,
            zeroFilled: true,
            activeVoiceCountBefore: mixer.activeVoiceCount,
            loadedVoiceCountBefore: mixer.loadedVoiceCount,
            outputMetrics: .silence
        )
    }

    private func rampDownReplacementChannelLocked(_ channel: Int, reason: String) -> RuntimeCMixerChannelStopResult {
        let snapshotBefore = snapshotLocked()
        let rampedVoiceCount: Int
        if channel >= 0 && channel <= Int(UInt32.max) {
            rampedVoiceCount = mixer.rampDownVoices(
                channel: channel,
                rampFrames: CSoftwareMixer.replacementStopRampFrameCount
            )
            voiceStateByChannel.removeValue(forKey: channel)
            clearAdapterVoiceState(channel: channel)
        } else {
            rampedVoiceCount = 0
        }
        return RuntimeCMixerChannelStopResult(
            channel: channel,
            stoppedVoiceCount: 0,
            rampedVoiceCount: rampedVoiceCount,
            replacementRampFrames: CSoftwareMixer.replacementStopRampFrameCount,
            replacementVoicesOverlap: false,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            reason: reason
        )
    }

    private func stopChannelLocked(_ channel: Int, reason: String) -> RuntimeCMixerChannelStopResult {
        let snapshotBefore = snapshotLocked()
        let stoppedVoiceCount: Int
        if channel >= 0 && channel <= Int(UInt32.max) {
            stoppedVoiceCount = mixer.stopVoices(channel: channel)
            voiceStateByChannel.removeValue(forKey: channel)
            clearAdapterVoiceState(channel: channel)
            stoppedFrameByChannel[channel] = mixer.currentFrame
        } else {
            stoppedVoiceCount = 0
        }
        return RuntimeCMixerChannelStopResult(
            channel: channel,
            stoppedVoiceCount: stoppedVoiceCount,
            rampedVoiceCount: 0,
            replacementRampFrames: nil,
            replacementVoicesOverlap: false,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            reason: reason
        )
    }

    func snapshot() -> RuntimeCMixerRenderSnapshot {
        lock.lock()
        defer {
            lock.unlock()
        }
        return snapshotLocked()
    }

    private func snapshotLocked() -> RuntimeCMixerRenderSnapshot {
        let rms = cumulativeOutputSampleCount > 0
            ? Float(sqrt(cumulativeOutputSquareSum / Double(cumulativeOutputSampleCount)))
            : 0
        return RuntimeCMixerRenderSnapshot(
            sampleRate: mixer.config.sampleRate,
            channelCount: mixer.config.channelCount,
            activeVoiceCount: mixer.activeVoiceCount,
            loadedVoiceCount: mixer.loadedVoiceCount,
            scheduledVoiceCount: 0,
            eventQueueBacklogCount: 0,
            renderCallbackCount: renderCallbackCount,
            renderCallCount: renderCallCount,
            successfulRenderCount: successfulRenderCount,
            failedRenderCount: failedRenderCount,
            requestedFrameCount: lastRequestedFrameCount,
            cumulativeRequestedFrameCount: cumulativeRequestedFrameCount,
            renderedFrameCount: renderedFrameCount,
            callbackIndex: lastCallbackIndex,
            callbackRequestedFrameCount: lastCallbackRequestedFrameCount,
            callbackStartFrame: lastCallbackStartFrame,
            callbackEndFrame: lastCallbackEndFrame,
            minRequestedFrameCount: minRequestedFrameCount,
            maxRequestedFrameCount: maxRequestedFrameCount,
            lastRequestedFrameCount: lastRequestedFrameCount,
            lastRenderedFrameCount: lastRenderedFrameCount,
            lastRenderSucceeded: lastRenderSucceeded,
            zeroFillCount: zeroFillCount,
            underrunCount: underrunCount,
            silentOutputCallbackCount: silentOutputCallbackCount,
            unexpectedSilentOutputCount: unexpectedSilentOutputCount,
            outputPeak: outputPeak,
            outputRMS: rms,
            lastOutputPeak: lastOutputPeak,
            lastOutputRMS: lastOutputRMS,
            overrangeSampleCount: overrangeSampleCount,
            clippingSampleCount: clippingSampleCount,
            clippingDetected: clippingSampleCount > 0,
            runtimeOutputGain: outputPolicy.outputGain,
            runtimeHeadroomPolicy: outputPolicy.headroomPolicy,
            runtimeAutoHeadroomEnabled: outputPolicy.autoHeadroomEnabled,
            runtimeFixedHeadroomDB: outputPolicy.fixedHeadroomDB,
            runtimeGainConfigurationWarning: outputPolicy.configurationWarning,
            runtimeClippingRecommendation: clippingSampleCount > 0 ? RuntimeCMixerOutputPolicy.clippingRecommendation : nil,
            currentFrame: mixer.currentFrame
        )
    }

    private func recordRenderCompletionLocked(
        requestedFrameCount: Int,
        renderedFrameCount renderedFrames: Int,
        callbackStartFrame: UInt64,
        callbackEndFrame: UInt64,
        succeeded: Bool,
        zeroFilled: Bool,
        activeVoiceCountBefore: Int,
        loadedVoiceCountBefore: Int,
        outputMetrics: RuntimeCMixerOutputMetrics
    ) {
        let callbackIndex = renderCallbackCount &+ 1
        renderCallbackCount &+= 1
        lastCallbackIndex = callbackIndex
        lastCallbackRequestedFrameCount = requestedFrameCount
        lastCallbackStartFrame = callbackStartFrame
        lastCallbackEndFrame = callbackEndFrame
        cumulativeRequestedFrameCount &+= UInt64(max(0, requestedFrameCount))
        minRequestedFrameCount = minRequestedFrameCount.map { min($0, requestedFrameCount) } ?? requestedFrameCount
        maxRequestedFrameCount = max(maxRequestedFrameCount ?? requestedFrameCount, requestedFrameCount)
        lastRequestedFrameCount = requestedFrameCount
        lastRenderedFrameCount = renderedFrames
        lastRenderSucceeded = succeeded
        lastOutputPeak = outputMetrics.peak
        lastOutputRMS = outputMetrics.rms

        if succeeded {
            renderCallCount &+= 1
            successfulRenderCount &+= 1
            self.renderedFrameCount &+= UInt64(max(0, renderedFrames))
            if outputMetrics.isSilent {
                silentOutputCallbackCount &+= 1
                if activeVoiceCountBefore > 0 || loadedVoiceCountBefore > 0 {
                    unexpectedSilentOutputCount &+= 1
                    underrunCount &+= 1
                }
            }
            cumulativeOutputSampleCount &+= UInt64(max(0, outputMetrics.sampleCount))
            cumulativeOutputSquareSum += outputMetrics.squareSum
            outputPeak = max(outputPeak, outputMetrics.peak)
            overrangeSampleCount &+= UInt64(max(0, outputMetrics.overrangeSampleCount))
            clippingSampleCount &+= UInt64(max(0, outputMetrics.clippingSampleCount))
        } else {
            failedRenderCount &+= 1
            if zeroFilled {
                zeroFillCount &+= 1
                underrunCount &+= 1
            }
        }
    }

    private func outputMetrics(
        _ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        sampleCount: Int
    ) -> RuntimeCMixerOutputMetrics {
        let boundedSampleCount = min(max(0, sampleCount), outputInterleavedPCM.count)
        guard boundedSampleCount > 0 else {
            return .silence
        }
        var peak = Float(0)
        var squareSum = Double(0)
        var overrangeCount = 0
        var clippingCount = 0
        for index in 0..<boundedSampleCount {
            let sample = outputInterleavedPCM[index].isFinite ? outputInterleavedPCM[index] : 0
            let absolute = abs(sample)
            peak = max(peak, absolute)
            squareSum += Double(sample) * Double(sample)
            if absolute > 1 {
                overrangeCount += 1
            }
            if absolute >= 1 {
                clippingCount += 1
            }
        }
        return RuntimeCMixerOutputMetrics(
            sampleCount: boundedSampleCount,
            peak: peak,
            squareSum: squareSum,
            overrangeSampleCount: overrangeCount,
            clippingSampleCount: clippingCount
        )
    }

    private func applyOutputGain(
        _ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        sampleCount: Int
    ) {
        let gain = outputPolicy.outputGain
        guard gain != 1 else {
            return
        }
        let boundedSampleCount = min(max(0, sampleCount), outputInterleavedPCM.count)
        for index in 0..<boundedSampleCount {
            outputInterleavedPCM[index] *= gain
        }
    }

    private func runtimeGain(sample: PlaybackSample, volumeScale: Float) -> Float {
        PlaybackVolumeCalculator.finalAppliedVolume(sampleVolume: sample.volume, nodeVolumeScale: volumeScale)
    }

    private func sanitizedPan(_ pan: Float) -> Float {
        guard pan.isFinite else {
            return 0
        }
        return min(1, max(-1, pan))
    }

    private func defaultControlState(for channel: Int) -> RuntimeCMixerChannelControlState {
        RuntimeCMixerChannelControlState(
            volumeScale: 1,
            panning: PlaybackEffectHandler.audioPanning(
                forXMValue: PlaybackChannelState.defaultPanning(forChannel: channel)
            ),
            pitchOffsetSemitones: 0
        )
    }

    private func playbackStep(
        note: UInt8,
        sample: PlaybackSample,
        pitchOffsetSemitones: Double
    ) -> Double? {
        guard note > 0,
              note <= 96,
              pitchOffsetSemitones.isFinite else {
            return nil
        }
        let step = PlaybackPitchCalculator.calculation(
            note: note,
            sample: sample,
            pitchOffsetSemitones: pitchOffsetSemitones,
            outputSampleRate: mixer.config.sampleRate
        ).playbackRate
        return step.isFinite && step > 0 ? step : nil
    }

    private func clearAdapterVoiceState(channel: Int) {
        guard let eventIndex = adapterEventIndexByChannel.removeValue(forKey: channel) else {
            return
        }
        adapterVoiceStateByEventIndex.removeValue(forKey: eventIndex)
    }

    private func runtimeKeyOffFrame(
        plannedKeyOffFrame: Int?,
        plannedStartFrame: Int,
        runtimeStartFrame: Int
    ) -> Int? {
        guard let plannedKeyOffFrame else {
            return nil
        }
        let relativeFrame = max(0, plannedKeyOffFrame - max(0, plannedStartFrame))
        guard runtimeStartFrame <= Int.max - relativeFrame else {
            return nil
        }
        return runtimeStartFrame + relativeFrame
    }

    private func mixerLoop(for sample: PlaybackSample) -> MixerSampleLoop {
        let loop = sample.loopRegion
        guard loop.isEnabled else {
            return .none
        }
        return MixerSampleLoop(
            mode: loop.isPingPongLoop ? .pingPong : .forward,
            startFrame: loop.startFrame,
            endFrame: loop.endFrame
        )
    }

    private func clear(_ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>) {
        for index in outputInterleavedPCM.indices {
            outputInterleavedPCM[index] = 0
        }
    }

    private func clear(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for buffer in buffers {
            guard let data = buffer.mData else {
                continue
            }
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let requestedSampleCount = max(0, frameCount) * max(1, Int(buffer.mNumberChannels))
            let sampleCount = min(availableSampleCount, requestedSampleCount)
            let output = data.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = 0
            }
        }
    }

    private func copyScratchToAudioBuffers(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        let channelCount = mixer.config.channelCount
        if buffers.count == 1,
           let data = buffers[0].mData,
           Int(buffers[0].mNumberChannels) == channelCount {
            let sampleCount = min(
                Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size,
                frameCount * channelCount
            )
            let output = data.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = scratchInterleavedPCM[sampleIndex]
            }
            return
        }

        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else {
                continue
            }
            let bufferChannelCount = max(1, Int(buffer.mNumberChannels))
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for bufferChannel in 0..<bufferChannelCount {
                    let outputIndex = frame * bufferChannelCount + bufferChannel
                    guard outputIndex < availableSampleCount else {
                        return
                    }
                    let sourceChannel = buffers.count == channelCount ? bufferIndex : bufferChannel
                    output[outputIndex] = sourceChannel < channelCount
                        ? scratchInterleavedPCM[(frame * channelCount) + sourceChannel]
                        : 0
                }
            }
        }
    }
}

private func makeRuntimeCMixerSourceNode(
    format: AVAudioFormat,
    renderCore: RuntimeCMixerRenderCore
) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, ioData in
        renderCore.render(frameCount: frameCount, ioData: ioData)
    }
}

@MainActor
protocol RuntimeAudioDiagnosticOutput: AnyObject {
    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?)
    func update(channel: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?)
    func stop(channel: Int, context: AudioRuntimeTraceContext?)
    func stopAll(context: AudioRuntimeTraceContext?, reason: String)
    func recordTransition(previousContext: AudioRuntimeTraceContext?, context: AudioRuntimeTraceContext?, phase: String, reason: String)
}

@MainActor
protocol RuntimeCMixerAdapterEventConsuming: AnyObject {
    var hasRuntimeAdapterEventPlan: Bool { get }

    func configureRuntimeAdapterEventPlan(_ plan: RuntimeCMixerAdapterEventPlan)
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
}

private struct RuntimeCMixerTransitionTraceFields: Equatable {
    let previousContext: AudioRuntimeTraceContext?
    let nextContext: AudioRuntimeTraceContext?
    let phase: String
    let runtimeFrame: UInt64
    let replacementRampCount: UInt64?
    let updateCount: UInt64?
}

private struct RuntimeCMixerPendingTransition: Equatable {
    let previousContext: AudioRuntimeTraceContext?
    let nextContext: AudioRuntimeTraceContext?
    let snapshot: RuntimeCMixerRenderSnapshot
    let replacementRampCount: UInt64
    let updateCount: UInt64
}

@MainActor
final class RuntimeCMixerAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding, RuntimeAudioDiagnosticOutput, RuntimeCMixerAdapterEventConsuming {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sourceNode: AVAudioSourceNode
    private let renderCore: RuntimeCMixerRenderCore
    private let fallbackAudioEngine = PlaybackAudioEngine()
    private let traceWriter: RuntimeCMixerTraceWriting
    private var isPrepared = false
    private var isFallbackActive = false
    private var eventCounters = RuntimeCMixerEventCounters()
    private var adapterEventPlan = RuntimeCMixerAdapterEventPlan.unavailable()
    private var consumedAdapterEventIDs = Set<Int>()
    private var consumedAdapterEventCategories = Set<String>()
    private var plannedRuntimeFrameOffset: Int?
    private var pendingTransition: RuntimeCMixerPendingTransition?

    init(
        sampleRate: Double = MixerRenderConfig.defaultSampleRate,
        channelCount: Int = MixerRenderConfig.defaultChannelCount,
        outputPolicy: RuntimeCMixerOutputPolicy = .defaultPolicy,
        traceWriter: RuntimeCMixerTraceWriting = NoopRuntimeCMixerTraceWriter.shared
    ) {
        let config = MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount)
        renderCore = RuntimeCMixerRenderCore(config: config, outputPolicy: outputPolicy)
        self.traceWriter = traceWriter
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: renderCore.config.sampleRate,
            channels: AVAudioChannelCount(renderCore.config.channelCount),
            interleaved: false
        )!
        sourceNode = makeRuntimeCMixerSourceNode(format: format, renderCore: renderCore)
        logger.info(
            "Initialized experimental C mixer runtime backend sample_rate=\(self.renderCore.config.sampleRate, privacy: .public) channel_count=\(self.renderCore.config.channelCount, privacy: .public)"
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
        .cMixer
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    var hasRuntimeAdapterEventPlan: Bool {
        adapterEventPlan.generated
    }

    func configureRuntimeAdapterEventPlan(_ plan: RuntimeCMixerAdapterEventPlan) {
        adapterEventPlan = plan
        resetRuntimeAdapterEventConsumption()
        recordRuntimeEvent(
            action: "adapter_plan_configured",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: plan.generated,
            runtimeEventSource: plan.generated ? RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue : RuntimeCMixerAdapterEventSource.playbackEngineSimple.rawValue,
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
        pendingTransition = nil
    }

    func consumeRuntimeAdapterEvents(context: AudioRuntimeTraceContext?) {
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

        let matchingEvents = adapterEventPlan.events(matching: context)
        for event in matchingEvents where !consumedAdapterEventIDs.contains(event.id) {
            consumedAdapterEventIDs.insert(event.id)
            eventCounters.consumedPlannedEventCount &+= 1
            consumedAdapterEventCategories.formUnion(event.categories)
            consumeRuntimeAdapterEvent(event, context: context)
        }
    }

    private func eventTimingTraceFields(
        for event: RuntimeCMixerAdapterEvent,
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot,
        runtimeEventCategory: String? = nil
    ) -> RuntimeCMixerEventTimingTraceFields {
        let applicationFrame = snapshot.currentFrame
        let offset = resolvedPlannedRuntimeFrameOffset(
            context: context,
            snapshot: snapshot
        )
        let plannedRuntimeFrame = offset.flatMap { safeAdding(event.scheduledFrame, $0) }
        let frameDelta = plannedRuntimeFrame.flatMap { delta(runtimeFrame: applicationFrame, plannedFrame: $0) }
        return RuntimeCMixerEventTimingTraceFields(
            runtimeEventCategory: runtimeEventCategory ?? diagnosticCategory(for: event),
            plannedEventID: event.id,
            plannedSourceOrderIndex: event.source.orderIndex,
            plannedSourcePatternIndex: event.source.patternIndex,
            plannedSourceRowIndex: event.source.rowIndex,
            plannedSourceTickInRow: event.syntheticTick,
            plannedSourceChannelIndex: event.channelIndex,
            plannedEventFrame: event.scheduledFrame,
            plannedRuntimeFrame: plannedRuntimeFrame,
            plannedRuntimeFrameOffset: offset,
            runtimeApplicationFrame: applicationFrame,
            eventFrameDelta: frameDelta,
            eventApplicationTiming: eventApplicationTiming(
                plannedRuntimeFrame: plannedRuntimeFrame,
                runtimeApplicationFrame: applicationFrame,
                context: context,
                snapshot: snapshot
            )
        )
    }

    private func transitionTimingTraceFields(
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> RuntimeCMixerEventTimingTraceFields? {
        guard let context,
              let plannedRowStartFrame = adapterEventPlan.plannedRowStartFrame(matching: context) else {
            return nil
        }
        let offset = resolvedPlannedRuntimeFrameOffset(context: context, snapshot: snapshot)
        let plannedRuntimeFrame = offset.flatMap { safeAdding(plannedRowStartFrame, $0) }
        let frameDelta = plannedRuntimeFrame.flatMap { delta(runtimeFrame: snapshot.currentFrame, plannedFrame: $0) }
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
            runtimeApplicationFrame: snapshot.currentFrame,
            eventFrameDelta: frameDelta,
            eventApplicationTiming: eventApplicationTiming(
                plannedRuntimeFrame: plannedRuntimeFrame,
                runtimeApplicationFrame: snapshot.currentFrame,
                context: context,
                snapshot: snapshot
            )
        )
    }

    private func resolvedPlannedRuntimeFrameOffset(
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> Int? {
        if let plannedRuntimeFrameOffset {
            return plannedRuntimeFrameOffset
        }
        guard snapshot.currentFrame <= UInt64(Int.max),
              let plannedRowStartFrame = adapterEventPlan.plannedRowStartFrame(matching: context) else {
            return nil
        }
        let offset = Int(snapshot.currentFrame) - plannedRowStartFrame
        plannedRuntimeFrameOffset = offset
        return offset
    }

    private func eventApplicationTiming(
        plannedRuntimeFrame: Int?,
        runtimeApplicationFrame: UInt64,
        context: AudioRuntimeTraceContext?,
        snapshot: RuntimeCMixerRenderSnapshot
    ) -> String {
        if let plannedRuntimeFrame,
           let applicationFrame = intFrame(runtimeApplicationFrame),
           applicationFrame == plannedRuntimeFrame {
            return "exact_frame"
        }
        if snapshot.callbackEndFrame == runtimeApplicationFrame {
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

    private func consumeRuntimeAdapterEvent(_ event: RuntimeCMixerAdapterEvent, context: AudioRuntimeTraceContext?) {
        let eventContext = contextWithFallbackChannel(context, channel: event.channelIndex)
        switch event.action {
        case let .noteTrigger(eventIndex, syntheticEvent, mapping):
            prepareIfNeeded()
            let result = renderCore.triggerAdapterEventWithDiagnostics(
                syntheticEvent,
                eventIndex: eventIndex,
                mapping: mapping
            )
            let timing = eventTimingTraceFields(
                for: event,
                context: eventContext,
                snapshot: result.snapshotBefore
            )
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
                    runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                    adapterEventCategory: "replacement",
                    eventTiming: eventTimingTraceFields(
                        for: event,
                        context: eventContext,
                        snapshot: channelStop.snapshotBefore,
                        runtimeEventCategory: "replacement_stop_ramp"
                    ),
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
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: event.primaryCategory,
                eventTiming: timing,
                reason: result.reason ?? "runtime_c_mixer_adapter_plan_note_trigger"
            )
            guard result.succeeded else {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
                return
            }
            if !startEngineIfNeeded() {
                isFallbackActive = true
            }

        case let .gainPanUpdate(activeEventIndex, gain, pan):
            let result = renderCore.applyAdapterGainPanUpdateWithDiagnostics(
                channel: event.channelIndex,
                activeEventIndex: activeEventIndex,
                gain: gain,
                pan: pan
            )
            let timing = eventTimingTraceFields(
                for: event,
                context: eventContext,
                snapshot: result.snapshotBefore
            )
            if result.gainPanAttempted {
                eventCounters.gainPanUpdateCount &+= 1
            }
            recordRuntimeUpdateEvent(
                result,
                context: eventContext,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: event.primaryCategory,
                eventTiming: timing
            )
            if result.targetVoiceIndex == nil {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }

        case let .stepUpdate(activeEventIndex, playbackStep):
            let result = renderCore.applyAdapterStepUpdateWithDiagnostics(
                channel: event.channelIndex,
                activeEventIndex: activeEventIndex,
                playbackStep: playbackStep
            )
            let timing = eventTimingTraceFields(
                for: event,
                context: eventContext,
                snapshot: result.snapshotBefore
            )
            if result.stepAttempted {
                eventCounters.stepUpdateCount &+= 1
            }
            recordRuntimeUpdateEvent(
                result,
                context: eventContext,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: event.primaryCategory,
                eventTiming: timing
            )
            if result.targetVoiceIndex == nil {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }

        case let .noteCut(activeEventIndex):
            let result = renderCore.applyAdapterNoteCutWithDiagnostics(
                channel: event.channelIndex,
                activeEventIndex: activeEventIndex
            )
            let timing = eventTimingTraceFields(
                for: event,
                context: eventContext,
                snapshot: result.snapshotBefore
            )
            recordRuntimeEvent(
                action: "c_mixer_adapter_note_cut",
                context: eventContext,
                targetScope: "channel",
                snapshotBefore: result.snapshotBefore,
                snapshot: result.snapshotAfter,
                succeeded: result.succeeded,
                targetVoiceIndex: result.targetVoiceIndex,
                runtimeEventSource: RuntimeCMixerAdapterEventSource.offlineAdapterPlan.rawValue,
                adapterEventCategory: event.primaryCategory,
                eventTiming: timing,
                reason: result.reason
            )
            if result.targetVoiceIndex == nil {
                eventCounters.skippedUnmatchedPlannedEventCount &+= 1
            }
        }
    }

    func trigger(_ request: AudioVoiceRequest) {
        trigger(request, context: nil)
    }

    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?) {
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
        prepareIfNeeded()
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
            runtimeEventSource: simpleRuntimeEventSource().rawValue,
            adapterEventCategory: nil,
            runtimeEventFallbackReason: fallbackReason,
            reason: result.reason
        )
        guard result.succeeded else {
            logger.debug("Experimental C mixer runtime ignored an unplayable trigger")
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
        if isFallbackActive {
            fallbackAudioEngine.update(channel: channel, controls: controls)
        } else {
            let fallbackReason = recordSimpleRuntimeFallbackIfNeeded()
            let result = renderCore.updateWithDiagnostics(channel: channel, controls: controls, context: context)
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
            recordRuntimeUpdateEvent(
                result,
                context: contextWithFallbackChannel(context, channel: channel),
                runtimeEventSource: simpleRuntimeEventSource().rawValue,
                adapterEventCategory: nil,
                runtimeEventFallbackReason: fallbackReason
            )
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
        engine.pause()
        if isFallbackActive {
            fallbackAudioEngine.stopAll()
        }
    }

    func recordTransition(
        previousContext: AudioRuntimeTraceContext?,
        context: AudioRuntimeTraceContext?,
        phase: String,
        reason: String
    ) {
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

    func reset() {
        stopAll()
        engine.stop()
        fallbackAudioEngine.reset()
        isFallbackActive = false
        if isPrepared {
            engine.detach(sourceNode)
        }
        engine.reset()
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
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isPrepared = true
        recordRuntimeEvent(
            action: "backend_prepared",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: true,
            reason: "runtime_c_mixer_source_node_prepared"
        )
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else {
            return true
        }
        do {
            try engine.start()
            logger.info(
                "Experimental C mixer runtime start succeeded=true sample_rate=\(self.format.sampleRate, privacy: .public) channel_count=\(self.format.channelCount, privacy: .public)"
            )
            recordRuntimeEvent(
                action: "backend_start",
                context: nil,
                targetScope: "none",
                snapshot: renderCore.snapshot(),
                succeeded: true,
                reason: "runtime_c_mixer_engine_started"
            )
            return true
        } catch {
            logger.error(
                "Experimental C mixer runtime start succeeded=false falling_back=true error=\(error.localizedDescription, privacy: .public)"
            )
            renderCore.stopAll()
            recordRuntimeEvent(
                action: "backend_start_failed",
                context: nil,
                targetScope: "none",
                snapshot: renderCore.snapshot(),
                succeeded: false,
                reason: "runtime_c_mixer_engine_start_failed"
            )
            return false
        }
    }

    private func simpleRuntimeEventSource() -> RuntimeCMixerAdapterEventSource {
        adapterEventPlan.generated ? .hybrid : .playbackEngineSimple
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
        eventTiming: RuntimeCMixerEventTimingTraceFields? = nil,
        transition: RuntimeCMixerTransitionTraceFields? = nil,
        runtimeEventFallbackReason: String? = nil,
        reason: String?
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        traceWriter.record(RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: runtimeAudioBackend.diagnosticName,
            runtimeEventSource: runtimeEventSource,
            adapterPlanGenerated: adapterEventPlan.generated,
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
            fallbackToSimpleRuntimeEventCount: eventCounters.fallbackToSimpleRuntimeEventCount,
            runtimeEventFallbackReason: runtimeEventFallbackReason,
            experimentalCMixerEnabled: true,
            sampleRate: snapshot.sampleRate,
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
            callbackIndex: snapshot.callbackIndex,
            callbackRequestedFrameCount: snapshot.callbackRequestedFrameCount,
            callbackStartFrame: snapshot.callbackStartFrame,
            callbackEndFrame: snapshot.callbackEndFrame,
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
            overrangeSampleCount: snapshot.overrangeSampleCount,
            clippingSampleCount: snapshot.clippingSampleCount,
            clippingDetected: snapshot.clippingDetected,
            runtimeOutputGain: snapshot.runtimeOutputGain,
            runtimeHeadroomPolicy: snapshot.runtimeHeadroomPolicy,
            runtimeGainPolicyLabel: snapshot.runtimeHeadroomPolicy,
            runtimeAutoHeadroomEnabled: snapshot.runtimeAutoHeadroomEnabled,
            runtimeFixedHeadroomDB: snapshot.runtimeFixedHeadroomDB,
            runtimeGainConfigurationWarning: snapshot.runtimeGainConfigurationWarning,
            runtimeClippingRecommendation: snapshot.runtimeClippingRecommendation,
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
        ))
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

@MainActor
final class PlaybackAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding {
    private final class ChannelVoice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
    }

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voicesByChannel = [Int: ChannelVoice]()
    private var isPrepared = false

    init(sampleRate: Double = 44_100) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    var runtimeAudioBackend: RuntimeAudioBackend {
        .avAudio
    }

    func trigger(_ request: AudioVoiceRequest) {
        guard let plan = AudioSamplePlaybackPlanner.plan(for: request.sample, sampleStartOffset: request.sampleStartOffset) else {
            return
        }
        let introBuffer = plan.introRange.flatMap { makeBuffer(for: request, sampleRange: $0) }
        let loopBuffer = plan.loopRange.flatMap { loopRange in
            plan.usesPingPongLoop
                ? makePingPongLoopBuffer(for: request, sampleRange: loopRange)
                : makeBuffer(for: request, sampleRange: loopRange)
        }
        guard introBuffer != nil || loopBuffer != nil else {
            return
        }
        let voice = voice(forChannel: request.channel)
        prepareIfNeeded()
        guard startEngineIfNeeded() else {
            return
        }

        apply(
            AudioChannelControls(
                volumeScale: request.volumeScale,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                panning: request.panning
            ),
            to: voice
        )
        voice.player.stop()
        if let introBuffer {
            voice.player.scheduleBuffer(introBuffer, at: nil, options: [], completionHandler: nil)
        }
        if let loopBuffer {
            voice.player.scheduleBuffer(loopBuffer, at: nil, options: .loops, completionHandler: nil)
        }
        voice.player.play()
    }

    func update(channel: Int, controls: AudioChannelControls) {
        guard let voice = voicesByChannel[channel] else {
            return
        }
        apply(controls, to: voice)
    }

    func stop(channel: Int) {
        voicesByChannel[channel]?.player.stop()
    }

    func stopAll() {
        for voice in voicesByChannel.values {
            voice.player.stop()
        }
        engine.pause()
    }

    func reset() {
        stopAll()
        for voice in voicesByChannel.values {
            engine.detach(voice.player)
            engine.detach(voice.varispeed)
        }
        voicesByChannel.removeAll()
        engine.reset()
        isPrepared = false
    }

    private func prepareIfNeeded() {
        guard !isPrepared else {
            return
        }
        engine.prepare()
        isPrepared = true
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else {
            return true
        }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Unable to start audio engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func voice(forChannel channel: Int) -> ChannelVoice {
        if let voice = voicesByChannel[channel] {
            return voice
        }
        let voice = ChannelVoice()
        engine.attach(voice.player)
        engine.attach(voice.varispeed)
        engine.connect(voice.player, to: voice.varispeed, format: format)
        engine.connect(voice.varispeed, to: engine.mainMixerNode, format: format)
        voicesByChannel[channel] = voice
        return voice
    }

    private func apply(_ controls: AudioChannelControls, to voice: ChannelVoice) {
        voice.player.volume = min(1, max(0, controls.volumeScale))
        voice.player.pan = min(1, max(-1, controls.panning))
        let rate = Float(pow(2.0, controls.pitchOffsetSemitones / 12.0))
        voice.varispeed.rate = min(4, max(0.25, rate))
    }

    private func makeBuffer(for request: AudioVoiceRequest, sampleRange: Range<Int>) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              sampleRange.lowerBound >= 0,
              sampleRange.upperBound <= request.sample.pcm.count,
              !sampleRange.isEmpty else {
            return nil
        }
        return makeBuffer(for: request, sourceFrameCount: sampleRange.count) { sourceFrame in
            let sampleIndex = min(sampleRange.upperBound - 1, sampleRange.lowerBound + sourceFrame)
            return request.sample.pcm[sampleIndex]
        }
    }

    private func makePingPongLoopBuffer(for request: AudioVoiceRequest, sampleRange: Range<Int>) -> AVAudioPCMBuffer? {
        let frameIndices = AudioSampleLoopFrameBuilder.pingPongFrameIndices(
            for: sampleRange,
            sampleFrameCount: request.sample.pcm.count
        )
        guard !frameIndices.isEmpty else {
            return nil
        }
        return makeBuffer(for: request, sourceFrameCount: frameIndices.count) { sourceFrame in
            request.sample.pcm[frameIndices[sourceFrame]]
        }
    }

    private func makeBuffer(
        for request: AudioVoiceRequest,
        sourceFrameCount: Int,
        sampleAt: (Int) -> Float
    ) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              sourceFrameCount > 0 else {
            return nil
        }
        let pitchRatio = PlaybackPitchCalculator.notePitchRatio(note: request.note, sample: request.sample)
        let increment = max(0.001, (request.sample.baseSampleRate / format.sampleRate) * pitchRatio)
        let frameCount = max(1, Int(Double(sourceFrameCount) / increment))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let output = buffer.floatChannelData?[0] else {
            return nil
        }

        var samplePosition = 0.0
        let gain = min(0.8, max(0, request.sample.volume))
        for frame in 0..<frameCount {
            let sourceFrame = min(sourceFrameCount - 1, Int(samplePosition))
            output[frame] = sampleAt(sourceFrame) * gain
            samplePosition += increment
        }
        return buffer
    }
}
