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
    let currentFrame: UInt64?
    let scheduledVoiceCount: Int?
    let eventQueueBacklogCount: Int?
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
    let stopChannelCount: UInt64?
    let clearAllCount: UInt64?
    let cMixerCallSucceeded: Bool?
    let reason: String?

    init(
        schemaVersion: Int = 1,
        runtimeAction: String,
        runtimeAudioBackend: String,
        backendFlagValue: String? = nil,
        fallbackReason: String? = nil,
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
        currentFrame: UInt64? = nil,
        scheduledVoiceCount: Int? = nil,
        eventQueueBacklogCount: Int? = nil,
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
        stopChannelCount: UInt64? = nil,
        clearAllCount: UInt64? = nil,
        cMixerCallSucceeded: Bool? = nil,
        reason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeAction = runtimeAction
        self.runtimeAudioBackend = runtimeAudioBackend
        self.backendFlagValue = backendFlagValue
        self.fallbackReason = fallbackReason
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
        self.currentFrame = currentFrame
        self.scheduledVoiceCount = scheduledVoiceCount
        self.eventQueueBacklogCount = eventQueueBacklogCount
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
        self.stopChannelCount = stopChannelCount
        self.clearAllCount = clearAllCount
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

struct RuntimeCMixerChannelStopResult: Equatable {
    let channel: Int
    let stoppedVoiceCount: Int
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

final class RuntimeCMixerRenderCore: @unchecked Sendable {
    private let lock = NSLock()
    private let mixer: CSoftwareMixer
    private let maximumRenderFrames: Int
    private var scratchInterleavedPCM: [Float]
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
        let channelStopBeforeAdd = stopChannelLocked(
            request.channel,
            reason: "note_replacement_stop_channel"
        )

        let voiceIndex = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: request.sample.pcm),
            gain: PlaybackVolumeCalculator.clamped(request.sample.volume * request.volumeScale),
            pan: request.panning,
            playbackStep: PlaybackPitchCalculator.calculation(
                note: request.note,
                sample: request.sample,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                outputSampleRate: mixer.config.sampleRate
            ).playbackRate,
            loop: mixerLoop(for: request.sample),
            initialSourceFrame: request.sampleStartOffset
        )
        mixer.setChannelTag(request.channel, forVoiceAt: voiceIndex)
        return RuntimeCMixerTriggerResult(
            succeeded: true,
            reason: nil,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            channelStopBeforeAdd: channelStopBeforeAdd.stoppedVoiceCount > 0 ? channelStopBeforeAdd : nil
        )
    }

    func update(channel _: Int, controls _: AudioChannelControls) {
        // The first runtime C mixer smoke path applies controls at note trigger time.
        // Continuous tick-level gain/pan/pitch automation needs a frame-position bridge and is intentionally
        // deferred so this backend remains an opt-in skeleton.
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
        let activeVoiceCountBefore = mixer.activeVoiceCount
        let loadedVoiceCountBefore = mixer.loadedVoiceCount
        guard safeFrameCount > 0 else {
            recordRenderCompletionLocked(
                requestedFrameCount: safeFrameCount,
                renderedFrameCount: 0,
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
            succeeded: false,
            zeroFilled: true,
            activeVoiceCountBefore: mixer.activeVoiceCount,
            loadedVoiceCountBefore: mixer.loadedVoiceCount,
            outputMetrics: .silence
        )
    }

    private func stopChannelLocked(_ channel: Int, reason: String) -> RuntimeCMixerChannelStopResult {
        let snapshotBefore = snapshotLocked()
        let stoppedVoiceCount: Int
        if channel >= 0 && channel <= Int(UInt32.max) {
            stoppedVoiceCount = mixer.stopVoices(channel: channel)
        } else {
            stoppedVoiceCount = 0
        }
        return RuntimeCMixerChannelStopResult(
            channel: channel,
            stoppedVoiceCount: stoppedVoiceCount,
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
        succeeded: Bool,
        zeroFilled: Bool,
        activeVoiceCountBefore: Int,
        loadedVoiceCountBefore: Int,
        outputMetrics: RuntimeCMixerOutputMetrics
    ) {
        renderCallbackCount &+= 1
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
    func recordTransition(context: AudioRuntimeTraceContext?, reason: String)
}

private struct RuntimeCMixerEventCounters: Equatable {
    var cMixerAddVoiceCount: UInt64 = 0
    var gainPanUpdateCount: UInt64 = 0
    var stepUpdateCount: UInt64 = 0
    var stopChannelCount: UInt64 = 0
    var clearAllCount: UInt64 = 0
}

@MainActor
final class RuntimeCMixerAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding, RuntimeAudioDiagnosticOutput {
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
        let result = renderCore.triggerWithDiagnostics(request)
        if let channelStop = result.channelStopBeforeAdd {
            eventCounters.stopChannelCount &+= 1
            recordRuntimeEvent(
                action: "c_mixer_stop_channel",
                context: contextWithFallbackChannel(context, channel: channelStop.channel),
                targetScope: "channel",
                snapshotBefore: channelStop.snapshotBefore,
                snapshot: channelStop.snapshotAfter,
                succeeded: true,
                stoppedVoiceCount: channelStop.stoppedVoiceCount,
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
            renderCore.update(channel: channel, controls: controls)
            eventCounters.gainPanUpdateCount &+= 1
            eventCounters.stepUpdateCount &+= 1
            recordRuntimeEvent(
                action: "c_mixer_update_gain_pan_step_deferred",
                context: context,
                targetScope: "channel",
                snapshot: renderCore.snapshot(),
                succeeded: nil,
                reason: "runtime_c_mixer_update_gain_pan_and_step_deferred"
            )
        }
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

    func recordTransition(context: AudioRuntimeTraceContext?, reason: String) {
        recordRuntimeEvent(
            action: "row_transition",
            context: context,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: nil,
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

    private func recordRuntimeEvent(
        action: String,
        context: AudioRuntimeTraceContext?,
        targetScope: String,
        targetedAllVoices: Bool = false,
        snapshotBefore: RuntimeCMixerRenderSnapshot? = nil,
        snapshot: RuntimeCMixerRenderSnapshot,
        succeeded: Bool?,
        stoppedVoiceCount: Int? = nil,
        reason: String?
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        traceWriter.record(RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: runtimeAudioBackend.diagnosticName,
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
            currentFrame: snapshot.currentFrame,
            scheduledVoiceCount: snapshot.scheduledVoiceCount,
            eventQueueBacklogCount: snapshot.eventQueueBacklogCount,
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
            stopChannelCount: eventCounters.stopChannelCount,
            clearAllCount: eventCounters.clearAllCount,
            cMixerCallSucceeded: succeeded,
            reason: reason
        ))
    }

    private func contextWithFallbackChannel(
        _ context: AudioRuntimeTraceContext?,
        channel: Int
    ) -> AudioRuntimeTraceContext? {
        guard context?.channelIndex == nil else {
            return context
        }
        return AudioRuntimeTraceContext(channelIndex: channel)
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
