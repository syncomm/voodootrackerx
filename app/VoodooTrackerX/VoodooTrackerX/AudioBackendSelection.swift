import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os

enum RuntimeAudioBackend: Equatable {
    case avAudio
    case cMixer
    case cMixerCoreAudio

    var diagnosticName: String {
        switch self {
        case .avAudio:
            return "av_audio"
        case .cMixer:
            return "c_mixer"
        case .cMixerCoreAudio:
            return "c_mixer_coreaudio"
        }
    }

    var usesRuntimeCMixer: Bool {
        switch self {
        case .avAudio:
            return false
        case .cMixer, .cMixerCoreAudio:
            return true
        }
    }

    var alternativeRuntimeOutputHostEnabled: Bool {
        usesRuntimeCMixer
    }

    var runtimeOutputHostType: String {
        switch self {
        case .avAudio:
            return "av_audio_player_node_varispeed"
        case .cMixer, .cMixerCoreAudio:
            return "coreaudio_default_output_unit"
        }
    }
}

struct RuntimeAudioBackendSelection: Equatable {
    static let environmentKey = "VTX_AUDIO_BACKEND"
    static let cMixerEnvironmentValue = "c_mixer"
    static let cMixerCoreAudioEnvironmentValue = "c_mixer_coreaudio"

    let backend: RuntimeAudioBackend
    let requestedValue: String?
    let fallbackReason: String?

    var experimentalCMixerEnabled: Bool {
        backend.usesRuntimeCMixer
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeAudioBackendSelection {
        let requestedValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedValue,
              !requestedValue.isEmpty else {
            return RuntimeAudioBackendSelection(backend: .avAudio, requestedValue: nil, fallbackReason: nil)
        }
        switch requestedValue {
        case cMixerEnvironmentValue:
            return RuntimeAudioBackendSelection(backend: .cMixer, requestedValue: requestedValue, fallbackReason: nil)
        case cMixerCoreAudioEnvironmentValue:
            return RuntimeAudioBackendSelection(backend: .cMixerCoreAudio, requestedValue: requestedValue, fallbackReason: nil)
        default:
            return RuntimeAudioBackendSelection(
                backend: .avAudio,
                requestedValue: requestedValue,
                fallbackReason: "unknown_backend"
            )
        }
    }
}

struct RuntimeCMixerSampleRateCandidates: Equatable {
    let outputNodeSampleRate: Double?
    let mainMixerSampleRate: Double?
    let hardwareSampleRate: Double?

    static func current() -> RuntimeCMixerSampleRateCandidates {
        let probeEngine = AVAudioEngine()
        let outputDevice = RuntimeCMixerAudioOutputDeviceDiagnostics.currentDefaultOutputDevice()
        return RuntimeCMixerSampleRateCandidates(
            outputNodeSampleRate: probeEngine.outputNode.outputFormat(forBus: 0).sampleRate,
            mainMixerSampleRate: probeEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
            hardwareSampleRate: outputDevice.nominalSampleRate
        )
    }
}

struct RuntimeCMixerSampleRateSelection: Equatable {
    static let environmentKey = "VTX_C_MIXER_RUNTIME_SAMPLE_RATE"

    let sampleRate: Double
    let policy: String
    let source: String
    let configurationWarning: String?

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        candidates: RuntimeCMixerSampleRateCandidates = .current()
    ) -> RuntimeCMixerSampleRateSelection {
        if let rawValue = trimmedEnvironmentValue(environment[environmentKey]) {
            if let parsed = Double(rawValue),
               isValidSampleRate(parsed) {
                return RuntimeCMixerSampleRateSelection(
                    sampleRate: parsed,
                    policy: "explicit_env",
                    source: "environment",
                    configurationWarning: nil
                )
            }
            return automaticSelection(
                candidates: candidates,
                configurationWarning: "invalid_runtime_sample_rate"
            )
        }
        return automaticSelection(candidates: candidates, configurationWarning: nil)
    }

    private static func automaticSelection(
        candidates: RuntimeCMixerSampleRateCandidates,
        configurationWarning: String?
    ) -> RuntimeCMixerSampleRateSelection {
        if let outputNodeSampleRate = candidates.outputNodeSampleRate,
           isValidSampleRate(outputNodeSampleRate) {
            return RuntimeCMixerSampleRateSelection(
                sampleRate: outputNodeSampleRate,
                policy: "graph_aligned",
                source: "output_node",
                configurationWarning: configurationWarning
            )
        }
        if let hardwareSampleRate = candidates.hardwareSampleRate,
           isValidSampleRate(hardwareSampleRate) {
            return RuntimeCMixerSampleRateSelection(
                sampleRate: hardwareSampleRate,
                policy: "graph_aligned",
                source: "hardware",
                configurationWarning: configurationWarning
            )
        }
        if let mainMixerSampleRate = candidates.mainMixerSampleRate,
           isValidSampleRate(mainMixerSampleRate) {
            return RuntimeCMixerSampleRateSelection(
                sampleRate: mainMixerSampleRate,
                policy: "graph_aligned",
                source: "main_mixer",
                configurationWarning: configurationWarning
            )
        }
        return RuntimeCMixerSampleRateSelection(
            sampleRate: MixerRenderConfig.defaultSampleRate,
            policy: "fallback_44100",
            source: "fallback_44100",
            configurationWarning: configurationWarning
        )
    }

    private static func isValidSampleRate(_ sampleRate: Double) -> Bool {
        sampleRate.isFinite && sampleRate > 0
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum RuntimeCMixerFormatDiagnostics {
    static func formatConversionLikely(
        sourceSampleRate: Double,
        sourceChannelCount: Int,
        mainMixerSampleRate: Double,
        mainMixerChannelCount: Int,
        outputSampleRate: Double,
        outputChannelCount: Int,
        hardwareSampleRate: Double?
    ) -> Bool {
        let knownRateMismatch = !sampleRatesMatch(sourceSampleRate, mainMixerSampleRate) ||
            !sampleRatesMatch(sourceSampleRate, outputSampleRate) ||
            (hardwareSampleRate.map { !sampleRatesMatch(sourceSampleRate, $0) } ?? false)
        let knownChannelMismatch = sourceChannelCount != mainMixerChannelCount ||
            sourceChannelCount != outputChannelCount
        return knownRateMismatch || knownChannelMismatch
    }

    static func sampleRatesMatch(_ lhs: Double?, _ rhs: Double?) -> Bool? {
        guard let lhs,
              let rhs else {
            return nil
        }
        return sampleRatesMatch(lhs, rhs)
    }

    static func sampleRatesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && abs(lhs - rhs) <= 0.5
    }
}

enum RuntimeCMixerDiagnosticEnvironment {
    static let disableTraceEnvironmentKey = "VTX_C_MIXER_RUNTIME_DISABLE_TRACE"
    static let disableCaptureEnvironmentKey = "VTX_C_MIXER_RUNTIME_DISABLE_CAPTURE"
    static let minimalCallbackEnvironmentKey = "VTX_C_MIXER_RUNTIME_MINIMAL_CALLBACK"
    static let disableFollowPublicationEnvironmentKey = "VTX_C_MIXER_RUNTIME_DISABLE_FOLLOW_PUBLICATION"
    static let outputBufferVerificationEnvironmentKey = "VTX_C_MIXER_RUNTIME_VERIFY_OUTPUT_COPY"
    static let routeLabelEnvironmentKey = "VTX_C_MIXER_RUNTIME_ROUTE_LABEL"

    static func flagEnabled(_ key: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value)
    }
}

struct RuntimeCMixerSongEndTailPolicy: Equatable {
    static let tailSecondsEnvironmentKey = "VTX_C_MIXER_RUNTIME_TAIL_SECONDS"
    static let defaultTailSeconds = 3.0

    let tailSeconds: Double
    let tailPolicy: String
    let configurationWarning: String?

    static let defaultPolicy = RuntimeCMixerSongEndTailPolicy(
        tailSeconds: RuntimeCMixerSongEndTailPolicy.defaultTailSeconds,
        tailPolicy: "default_runtime_tail_seconds",
        configurationWarning: nil
    )

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeCMixerSongEndTailPolicy {
        guard let rawValue = trimmedEnvironmentValue(environment[tailSecondsEnvironmentKey]) else {
            return defaultPolicy
        }
        guard let parsed = Double(rawValue),
              parsed.isFinite,
              parsed >= 0 else {
            return RuntimeCMixerSongEndTailPolicy(
                tailSeconds: defaultTailSeconds,
                tailPolicy: "default_runtime_tail_seconds_fallback",
                configurationWarning: "invalid_runtime_tail_seconds"
            )
        }
        return RuntimeCMixerSongEndTailPolicy(
            tailSeconds: parsed,
            tailPolicy: "env_runtime_tail_seconds",
            configurationWarning: nil
        )
    }

    func tailFrames(sampleRate: Double) -> Int {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : MixerRenderConfig.defaultSampleRate
        let frames = (safeSampleRate * tailSeconds).rounded(.up)
        guard frames.isFinite,
              frames > 0,
              frames <= Double(Int.max) else {
            return 0
        }
        return Int(frames)
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum RuntimeCMixerDeviceIdentityRedactor {
    static func stableHash(_ value: String) -> String {
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    static func hashedStableID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return stableHash(trimmed)
    }

    static func safeRouteLabel(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        safeRouteLabel(environment[RuntimeCMixerDiagnosticEnvironment.routeLabelEnvironmentKey])
    }

    static func safeRouteLabel(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        var result = ""
        var previousWasSeparator = false
        for scalar in trimmed.lowercased().unicodeScalars {
            let character: Character?
            if CharacterSet.alphanumerics.contains(scalar) {
                character = Character(scalar)
                previousWasSeparator = false
            } else if scalar == "-" || scalar == "_" || scalar == "." {
                character = Character(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                character = "-"
                previousWasSeparator = true
            } else {
                character = nil
            }
            if let character {
                result.append(character)
            }
            if result.count >= 48 {
                break
            }
        }
        let sanitized = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return sanitized.isEmpty ? nil : sanitized
    }

    static func transportTypeName(for transportType: UInt32?) -> String? {
        guard let transportType else {
            return nil
        }
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "built_in"
        case kAudioDeviceTransportTypeAggregate:
            return "aggregate"
        case kAudioDeviceTransportTypeVirtual:
            return "virtual"
        case kAudioDeviceTransportTypePCI:
            return "pci"
        case kAudioDeviceTransportTypeUSB:
            return "usb"
        case kAudioDeviceTransportTypeFireWire:
            return "firewire"
        case kAudioDeviceTransportTypeBluetooth:
            return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "bluetooth_le"
        case kAudioDeviceTransportTypeHDMI:
            return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort:
            return "display_port"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplay"
        case kAudioDeviceTransportTypeAVB:
            return "avb"
        case kAudioDeviceTransportTypeThunderbolt:
            return "thunderbolt"
        default:
            return "unknown_\(transportType)"
        }
    }
}

struct RuntimeCMixerCallbackDiagnosticsConfiguration: Equatable {
    let minimalCallbackMode: Bool
    let outputBufferVerificationEnabled: Bool

    static let defaultConfiguration = RuntimeCMixerCallbackDiagnosticsConfiguration(
        minimalCallbackMode: false,
        outputBufferVerificationEnabled: false
    )

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeCMixerCallbackDiagnosticsConfiguration {
        let minimal = RuntimeCMixerDiagnosticEnvironment.flagEnabled(
            RuntimeCMixerDiagnosticEnvironment.minimalCallbackEnvironmentKey,
            environment: environment
        )
        let outputBufferVerificationEnabled = RuntimeCMixerDiagnosticEnvironment.flagEnabled(
            RuntimeCMixerDiagnosticEnvironment.outputBufferVerificationEnvironmentKey,
            environment: environment
        )
        return RuntimeCMixerCallbackDiagnosticsConfiguration(
            minimalCallbackMode: minimal,
            outputBufferVerificationEnabled: !minimal && outputBufferVerificationEnabled
        )
    }
}

struct RuntimeCMixerCoreAudioHostConfiguration: Equatable {
    let sampleRate: Double
    let channelCount: Int

    init(
        sampleRate: Double,
        channelCount: Int
    ) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0
            ? sampleRate
            : MixerRenderConfig.defaultSampleRate
        self.channelCount = max(1, channelCount)
    }

    var streamDescription: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat |
                kAudioFormatFlagIsPacked |
                kAudioFormatFlagsNativeEndian |
                kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
    }
}

struct RuntimeCMixerOutputHostLifecycle: Equatable {
    enum State: Equatable {
        case stopped
        case prepared
        case running
    }

    private(set) var state: State = .stopped
    private(set) var lastPrepareStatus: OSStatus?
    private(set) var lastInitializeStatus: OSStatus?
    private(set) var lastStartStatus: OSStatus?
    private(set) var lastStopStatus: OSStatus?
    private(set) var lastErrorStatus: OSStatus?

    @discardableResult
    mutating func prepare(status: OSStatus = noErr, initializeStatus: OSStatus? = nil) -> Bool {
        lastPrepareStatus = status
        if let initializeStatus {
            lastInitializeStatus = initializeStatus
        }
        if status == noErr,
           state == .stopped {
            state = .prepared
        }
        recordError(status)
        return status == noErr
    }

    @discardableResult
    mutating func start(status: OSStatus = noErr) -> Bool {
        lastStartStatus = status
        if status == noErr {
            state = .running
        }
        recordError(status)
        return status == noErr
    }

    @discardableResult
    mutating func stop(status: OSStatus = noErr) -> Bool {
        lastStopStatus = status
        if status == noErr,
           state == .running {
            state = .prepared
        }
        recordError(status)
        return status == noErr
    }

    mutating func reset() {
        state = .stopped
    }

    private mutating func recordError(_ status: OSStatus) {
        if status != noErr {
            lastErrorStatus = status
        }
    }
}

@MainActor
protocol PlaybackAudioBackendProviding: AnyObject {
    var runtimeAudioBackend: RuntimeAudioBackend { get }
}

@MainActor
protocol PlaybackFollowPositionProviding: AnyObject {
    func playbackFollowPosition(timerPosition: PlaybackPosition, timerTickInRow: Int) -> PlaybackFollowPosition?
}


@MainActor
enum PlaybackAudioOutputFactory {
    private static let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "AudioBackend")

    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting = RuntimeCMixerTraceConfiguration.makeWriter()
    ) -> PlaybackAudioOutput {
        let selection = RuntimeAudioBackendSelection.resolve(environment: environment)
        let outputPolicy = selection.backend.usesRuntimeCMixer
            ? RuntimeCMixerOutputPolicy.resolve(environment: environment)
            : nil
        let updatePolicy = selection.backend.usesRuntimeCMixer
            ? RuntimeCMixerUpdatePolicy.resolve(environment: environment)
            : nil
        let sampleRateSelection = selection.backend.usesRuntimeCMixer
            ? RuntimeCMixerSampleRateSelection.resolve(environment: environment)
            : nil
        let callbackDiagnostics = selection.backend.usesRuntimeCMixer
            ? RuntimeCMixerCallbackDiagnosticsConfiguration.resolve(environment: environment)
            : nil
        let routeLabel = selection.backend.usesRuntimeCMixer
            ? RuntimeCMixerDeviceIdentityRedactor.safeRouteLabel(environment: environment)
            : nil
        let songEndTailPolicy = selection.backend.usesRuntimeCMixer
            ? RuntimeCMixerSongEndTailPolicy.resolve(environment: environment)
            : nil
        let captureConfiguration = selection.backend.usesRuntimeCMixer && callbackDiagnostics?.minimalCallbackMode != true
            ? RuntimeCMixerCaptureConfiguration.resolve(environment: environment)
            : nil
        let debugStopAfterSeconds = PlaybackDebugLaunchConfiguration.parse(environment: environment).stopAfterSeconds
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
        if let warning = updatePolicy?.configurationWarning {
            logger.warning(
                "Runtime C mixer update policy warning=\(warning, privacy: .public) epsilon=\(updatePolicy?.updateEpsilon ?? RuntimeCMixerUpdatePolicy.defaultUpdateEpsilon, privacy: .public)"
            )
        }
        if let warning = sampleRateSelection?.configurationWarning {
            logger.warning(
                "Runtime C mixer sample-rate policy warning=\(warning, privacy: .public) selected_sample_rate=\(sampleRateSelection?.sampleRate ?? MixerRenderConfig.defaultSampleRate, privacy: .public)"
            )
        }
        if let captureConfiguration,
           let warning = captureConfiguration.configurationWarning {
            logger.warning(
                "Runtime C mixer capture policy warning=\(warning, privacy: .public) path_name=\(captureConfiguration.pathName, privacy: .public)"
            )
        }
        if let warning = songEndTailPolicy?.configurationWarning {
            logger.warning(
                "Runtime C mixer tail policy warning=\(warning, privacy: .public) seconds=\(songEndTailPolicy?.tailSeconds ?? RuntimeCMixerSongEndTailPolicy.defaultTailSeconds, privacy: .public)"
            )
        }
        let selectedSampleRate = sampleRateSelection?.sampleRate ?? MixerRenderConfig.defaultSampleRate
        logger.info(
            "Selected audio backend=\(selection.backend.diagnosticName, privacy: .public) experimental_c_mixer_enabled=\(selection.experimentalCMixerEnabled, privacy: .public) sample_rate=\(selectedSampleRate, privacy: .public) channel_count=\(MixerRenderConfig.defaultChannelCount, privacy: .public)"
        )
        if runtimeCMixerTraceWriter.isEnabled {
            runtimeCMixerTraceWriter.record(RuntimeCMixerTraceEvent(
                runtimeAction: "backend_selected",
                runtimeAudioBackend: selection.backend.diagnosticName,
                backendFlagValue: selection.requestedValue,
                fallbackReason: selection.fallbackReason,
                experimentalCMixerEnabled: selection.experimentalCMixerEnabled,
                alternativeRuntimeOutputHostEnabled: selection.backend.alternativeRuntimeOutputHostEnabled,
                runtimeOutputHostType: selection.backend.runtimeOutputHostType,
                debugStopAfterSeconds: debugStopAfterSeconds,
                sampleRate: selectedSampleRate,
                selectedRuntimeSampleRate: sampleRateSelection?.sampleRate,
                cMixerRuntimeSampleRate: sampleRateSelection?.sampleRate,
                runtimeSampleRatePolicy: sampleRateSelection?.policy,
                runtimeSampleRateSource: sampleRateSelection?.source,
                runtimeSampleRateConfigurationWarning: sampleRateSelection?.configurationWarning,
                audioOutputRouteLabel: routeLabel,
                runtimeTailSeconds: songEndTailPolicy?.tailSeconds,
                runtimeTailFrames: songEndTailPolicy.map { $0.tailFrames(sampleRate: selectedSampleRate) },
                runtimeTailPolicy: songEndTailPolicy?.tailPolicy,
                runtimeTailConfigurationWarning: songEndTailPolicy?.configurationWarning,
                captureSeconds: captureConfiguration?.seconds,
                captureEndFrame: captureConfiguration?.frameLimit(sampleRate: selectedSampleRate),
                captureTruncated: captureConfiguration == nil ? nil : false,
                captureCapTriggeredPlaybackStop: false,
                channelCount: selection.backend.usesRuntimeCMixer ? MixerRenderConfig.defaultChannelCount : 1,
                targetScope: "none",
                targetedAllVoices: false,
                runtimeMinimalCallbackMode: callbackDiagnostics?.minimalCallbackMode,
                runtimeOutputGain: outputPolicy?.outputGain,
                runtimeHeadroomPolicy: outputPolicy?.headroomPolicy,
                runtimeGainPolicyLabel: outputPolicy?.headroomPolicy,
                runtimeDefaultHeadroomDB: outputPolicy.map { _ in RuntimeCMixerOutputPolicy.defaultHeadroomDB },
                runtimeGainPolicySource: outputPolicy?.gainPolicySource,
                runtimeGainPolicyIsEnvironmentOverride: outputPolicy?.gainPolicyIsEnvironmentOverride,
                runtimeAutoHeadroomEnabled: outputPolicy?.autoHeadroomEnabled,
                runtimeFixedHeadroomDB: outputPolicy?.fixedHeadroomDB,
                runtimeGainConfigurationWarning: outputPolicy?.configurationWarning,
                runtimeUpdateEpsilon: updatePolicy?.updateEpsilon,
                runtimeUpdateEpsilonPolicy: updatePolicy?.updateEpsilonPolicy,
                runtimeUpdateEpsilonConfigurationWarning: updatePolicy?.configurationWarning,
                runtimeCaptureEnabled: selection.backend.usesRuntimeCMixer && captureConfiguration != nil,
                runtimeCapturePathName: captureConfiguration?.pathName,
                runtimeCaptureSampleRate: captureConfiguration == nil ? nil : selectedSampleRate,
                runtimeCaptureChannelCount: captureConfiguration == nil ? nil : MixerRenderConfig.defaultChannelCount,
                runtimeCaptureSeconds: captureConfiguration?.seconds,
                runtimeCaptureFrameLimit: captureConfiguration?.frameLimit(sampleRate: selectedSampleRate),
                runtimeCapturedFrameCount: captureConfiguration == nil ? nil : 0,
                runtimeCaptureDurationSeconds: captureConfiguration == nil ? nil : 0,
                runtimeCaptureTruncated: captureConfiguration == nil ? nil : false,
                runtimeCaptureOutputPeak: captureConfiguration == nil ? nil : 0,
                runtimeCaptureOutputRMS: captureConfiguration == nil ? nil : 0,
                runtimeCaptureOverrangeSampleCount: captureConfiguration == nil ? nil : 0,
                runtimeCaptureClippingSampleCount: captureConfiguration == nil ? nil : 0,
                runtimeCaptureConfigurationWarning: captureConfiguration?.configurationWarning,
                cMixerCallSucceeded: nil,
                reason: selection.fallbackReason
            ))
        }
        switch selection.backend {
        case .avAudio:
            return PlaybackAudioEngine()
        case .cMixer, .cMixerCoreAudio:
            return RuntimeCMixerAudioEngine(
                backend: selection.backend,
                sampleRate: selectedSampleRate,
                outputPolicy: outputPolicy ?? .defaultPolicy,
                updatePolicy: updatePolicy ?? .defaultPolicy,
                captureConfiguration: captureConfiguration,
                callbackDiagnostics: callbackDiagnostics ?? .defaultConfiguration,
                songEndTailPolicy: songEndTailPolicy ?? .defaultPolicy,
                runtimeSampleRateSelection: sampleRateSelection,
                routeLabel: routeLabel,
                traceWriter: runtimeCMixerTraceWriter
            )
        }
    }
}
