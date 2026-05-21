import AVFoundation
import CoreAudio
import Darwin
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

    static func flagEnabled(_ key: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value)
    }
}

struct RuntimeCMixerCallbackDiagnosticsConfiguration: Equatable {
    let minimalCallbackMode: Bool
    let outputBufferVerificationEnabled: Bool

    static let defaultConfiguration = RuntimeCMixerCallbackDiagnosticsConfiguration(
        minimalCallbackMode: false,
        outputBufferVerificationEnabled: true
    )

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeCMixerCallbackDiagnosticsConfiguration {
        let minimal = RuntimeCMixerDiagnosticEnvironment.flagEnabled(
            RuntimeCMixerDiagnosticEnvironment.minimalCallbackEnvironmentKey,
            environment: environment
        )
        return RuntimeCMixerCallbackDiagnosticsConfiguration(
            minimalCallbackMode: minimal,
            outputBufferVerificationEnabled: !minimal
        )
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

struct RuntimeCMixerDiscontinuityThresholdCount: Encodable, Equatable {
    let threshold: Float
    let count: UInt64
}

struct RuntimeCMixerTopOutputSampleJump: Encodable, Equatable {
    let sampleJump: Float
    let runtimeFrame: UInt64
    let callbackIndex: UInt64
    let frameOffset: Int
    let channelIndex: Int
}

struct RuntimeCMixerTopOutputPeak: Encodable, Equatable {
    let peak: Float
    let runtimeFrame: UInt64
    let callbackIndex: UInt64
    let frameOffset: Int
    let channelIndex: Int
}

struct RuntimeCMixerSampleSummary: Encodable, Equatable {
    let frameCount: Int
    let channelCount: Int
    let sampleCount: Int
    let finiteSampleCount: Int
    let checksum: UInt64
    let peak: Float
    let rms: Float

    static let empty = RuntimeCMixerSampleSummary(
        frameCount: 0,
        channelCount: 0,
        sampleCount: 0,
        finiteSampleCount: 0,
        checksum: RuntimeCMixerSampleSummary.hashOffsetBasis,
        peak: 0,
        rms: 0
    )

    private static let hashOffsetBasis = UInt64(14_695_981_039_346_656_037)
    private static let hashPrime = UInt64(1_099_511_628_211)

    static func summarize(
        _ buffer: UnsafeBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) -> RuntimeCMixerSampleSummary {
        let safeChannelCount = max(1, channelCount)
        let boundedSampleCount = min(max(0, frameCount) * safeChannelCount, buffer.count)
        guard boundedSampleCount > 0 else {
            return .empty
        }

        var checksum = hashOffsetBasis
        var peak = Float(0)
        var squareSum = Double(0)
        var finiteSampleCount = 0
        for sampleIndex in 0..<boundedSampleCount {
            let sample = buffer[sampleIndex].isFinite ? buffer[sampleIndex] : 0
            if buffer[sampleIndex].isFinite {
                finiteSampleCount += 1
            }
            peak = max(peak, abs(sample))
            squareSum += Double(sample) * Double(sample)
            checksum = hash(checksum, sample: sample)
        }
        return RuntimeCMixerSampleSummary(
            frameCount: boundedSampleCount / safeChannelCount,
            channelCount: safeChannelCount,
            sampleCount: boundedSampleCount,
            finiteSampleCount: finiteSampleCount,
            checksum: checksum,
            peak: peak,
            rms: Float(sqrt(squareSum / Double(boundedSampleCount)))
        )
    }

    static func hash(_ hash: UInt64, sample: Float) -> UInt64 {
        var value = hash
        let bits = sample.bitPattern
        for shift in stride(from: 0, through: 24, by: 8) {
            value ^= UInt64((bits >> UInt32(shift)) & 0xFF)
            value &*= hashPrime
        }
        return value
    }
}

struct RuntimeCMixerOutputBufferCopyDiagnostics: Equatable {
    let layout: String
    let requestedFrameCount: Int
    let sourceChannelCount: Int
    let outputBufferCount: Int
    let outputChannelCount: Int
    let copiedFrameCount: Int
    let copiedSampleCount: Int
    let expectedSampleCount: Int
    let filledRequestedFrames: Bool
    let channelCountMatches: Bool
    let partialCopy: Bool
    let scratchSummary: RuntimeCMixerSampleSummary?
    let captureSummary: RuntimeCMixerSampleSummary?
    let outputSummary: RuntimeCMixerSampleSummary?

    var succeeded: Bool {
        filledRequestedFrames && channelCountMatches && !partialCopy
    }

    var scratchCaptureHashMatches: Bool? {
        guard let scratchSummary,
              let captureSummary else {
            return nil
        }
        return scratchSummary.checksum == captureSummary.checksum &&
            scratchSummary.sampleCount == captureSummary.sampleCount
    }

    var scratchOutputHashMatches: Bool? {
        guard let scratchSummary,
              let outputSummary else {
            return nil
        }
        return scratchSummary.checksum == outputSummary.checksum &&
            scratchSummary.sampleCount == outputSummary.sampleCount
    }
}

enum RuntimeCMixerOutputBufferCopy {
    static func copyInterleavedSamples(
        scratch: UnsafeBufferPointer<Float>,
        frameCount: Int,
        sourceChannelCount: Int,
        into output: UnsafeMutableBufferPointer<Float>,
        outputChannelCount: Int,
        captureSummary: RuntimeCMixerSampleSummary? = nil,
        collectSummaries: Bool = true
    ) -> RuntimeCMixerOutputBufferCopyDiagnostics {
        let safeFrameCount = max(0, frameCount)
        let safeSourceChannelCount = max(1, sourceChannelCount)
        let safeOutputChannelCount = max(1, outputChannelCount)
        let expectedSampleCount = safeFrameCount * safeSourceChannelCount
        let availableSourceFrames = scratch.count / safeSourceChannelCount
        let availableOutputFrames = output.count / safeOutputChannelCount
        let framesToCopy = min(safeFrameCount, availableSourceFrames, availableOutputFrames)
        let channelCountMatches = safeOutputChannelCount == safeSourceChannelCount
        var outputHash = RuntimeCMixerSampleSummary.empty.checksum
        var outputPeak = Float(0)
        var outputSquareSum = Double(0)
        var outputFiniteSampleCount = 0
        var copiedSampleCount = 0

        for frame in 0..<framesToCopy {
            for outputChannel in 0..<safeOutputChannelCount {
                let outputIndex = frame * safeOutputChannelCount + outputChannel
                let sample: Float
                if outputChannel < safeSourceChannelCount {
                    let sourceIndex = frame * safeSourceChannelCount + outputChannel
                    sample = scratch[sourceIndex].isFinite ? scratch[sourceIndex] : 0
                    copiedSampleCount += 1
                    if collectSummaries {
                        outputHash = RuntimeCMixerSampleSummary.hash(outputHash, sample: sample)
                        outputPeak = max(outputPeak, abs(sample))
                        outputSquareSum += Double(sample) * Double(sample)
                        outputFiniteSampleCount += 1
                    }
                } else {
                    sample = 0
                }
                output[outputIndex] = sample
            }
        }

        let scratchSummary = collectSummaries
            ? RuntimeCMixerSampleSummary.summarize(
                scratch,
                frameCount: safeFrameCount,
                channelCount: safeSourceChannelCount
            )
            : nil
        let outputSummary: RuntimeCMixerSampleSummary?
        if collectSummaries, copiedSampleCount > 0 {
            outputSummary = RuntimeCMixerSampleSummary(
                frameCount: framesToCopy,
                channelCount: safeSourceChannelCount,
                sampleCount: copiedSampleCount,
                finiteSampleCount: outputFiniteSampleCount,
                checksum: outputHash,
                peak: outputPeak,
                rms: Float(sqrt(outputSquareSum / Double(copiedSampleCount)))
            )
        } else {
            outputSummary = collectSummaries ? .empty : nil
        }
        let filledRequestedFrames = framesToCopy == safeFrameCount && copiedSampleCount >= expectedSampleCount
        return RuntimeCMixerOutputBufferCopyDiagnostics(
            layout: "single_interleaved_buffer",
            requestedFrameCount: safeFrameCount,
            sourceChannelCount: safeSourceChannelCount,
            outputBufferCount: 1,
            outputChannelCount: safeOutputChannelCount,
            copiedFrameCount: framesToCopy,
            copiedSampleCount: copiedSampleCount,
            expectedSampleCount: expectedSampleCount,
            filledRequestedFrames: filledRequestedFrames,
            channelCountMatches: channelCountMatches,
            partialCopy: !filledRequestedFrames,
            scratchSummary: scratchSummary,
            captureSummary: captureSummary,
            outputSummary: outputSummary
        )
    }
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
    let eventAppliedFrame: UInt64?
    let inCallbackOffset: Int?
    let plannedVsAppliedDelta: Int?
    let sameFrameBurstSize: Int?
    let sameFrameBurstID: Int?
    let sameFrameBurstEventOrdinal: Int?
    let sameFrameBurstCategories: [String]?
    let sameFrameBurstAffectedChannels: [Int]?
    let sameFrameBurstNoteTriggerCount: Int?
    let sameFrameBurstReplacementRampCount: Int?
    let sameFrameBurstGainPanUpdateCount: Int?
    let sameFrameBurstStepUpdateCount: Int?
    let sameFrameBurstNoteCutCount: Int?
    let sameFrameBurstKeyOffCount: Int?
    let sameFrameBurstGlobalVolumeUpdateCount: Int?
    let sameFrameBurstActiveVoiceCountBefore: Int?
    let sameFrameBurstActiveVoiceCountAfter: Int?
    let sameFrameBurstLoadedVoiceCountBefore: Int?
    let sameFrameBurstLoadedVoiceCountAfter: Int?
    let sameFrameBurstVoicesEnteringRampDown: Int?
    let sameFrameBurstVoicesCompletingRampDown: Int?
    let sameFrameBurstNewVoicesStarted: Int?
    let sameFrameBurstSustainedVoicesCarried: Int?
    let sameFrameBurstAtOrderStart: Bool?
    let sameFrameBurstAtRowTransition: Bool?
    let adapterActiveEventIndex: Int?
    let adapterCurrentEventIndexBefore: Int?
    let adapterCurrentEventIndexAfter: Int?
    let adapterChannelAssociationRetained: Bool?
    let adapterSustainedVoiceUpdate: Bool?
    let maxPlannedVsAppliedDelta: Int?
    let appliedPlannedEventCount: UInt64?
    let exactFrameAppliedEventCount: UInt64?
    let callbackBoundaryAppliedEventCount: UInt64?
    let latePlannedEventCount: UInt64?
    let fallbackToSimpleRuntimeEventCount: UInt64?
    let runtimeEventFallbackReason: String?
    let experimentalCMixerEnabled: Bool
    let sampleRate: Double?
    let selectedRuntimeSampleRate: Double?
    let cMixerRuntimeSampleRate: Double?
    let runtimeSampleRatePolicy: String?
    let runtimeSampleRateSource: String?
    let runtimeSampleRateConfigurationWarning: String?
    let cMixerRenderSampleRate: Double?
    let cMixerRenderChannelCount: Int?
    let audioSourceNodeRenderSampleRate: Double?
    let audioSourceNodeChannelCount: Int?
    let audioEngineMainMixerOutputSampleRate: Double?
    let audioEngineMainMixerOutputChannelCount: Int?
    let audioEngineMainMixerInputSampleRate: Double?
    let audioEngineMainMixerInputChannelCount: Int?
    let audioEngineMainMixerLatency: Double?
    let audioEngineMainMixerOutputPresentationLatency: Double?
    let audioEngineOutputNodeSampleRate: Double?
    let audioEngineOutputNodeChannelCount: Int?
    let audioEngineOutputNodeLatency: Double?
    let audioEngineOutputNodeOutputPresentationLatency: Double?
    let audioHardwareNominalSampleRate: Double?
    let audioHardwareDeviceID: UInt32?
    let audioHardwareDeviceUIDHash: String?
    let audioHardwareIOBufferFrameSize: UInt32?
    let audioHardwareIOBufferDuration: Double?
    let audioHardwareLatencyFrames: UInt32?
    let audioHardwareLatencyDuration: Double?
    let audioHardwareSafetyOffsetFrames: UInt32?
    let audioHardwareSafetyOffsetDuration: Double?
    let audioHardwareTransportType: UInt32?
    let audioEngineRunning: Bool?
    let audioEngineSourceNodeAttached: Bool?
    let audioEngineSourceNodeConnected: Bool?
    let audioEngineMainMixerConnectedToOutput: Bool?
    let audioEngineConfigurationChangeCount: UInt64?
    let audioGraphFormatChangeCount: UInt64?
    let audioOutputRouteChangeCount: UInt64?
    let audioGraphFormatChanged: Bool?
    let audioOutputRouteChanged: Bool?
    let audioFormatConversionLikely: Bool?
    let runtimeCaptureMatchesSourceNodeFormat: Bool?
    let runtimeCaptureMatchesEngineOutputFormat: Bool?
    let runtimeCaptureMatchesHardwareSampleRate: Bool?
    let cMixerRenderedFrames: UInt64?
    let cMixerPlaybackSeconds: Double?
    let cMixerSampleTimeFrame: Int?
    let cMixerSampleTimePositionStatus: String?
    let cMixerSampleTimeOrderIndex: Int?
    let cMixerSampleTimePatternIndex: Int?
    let cMixerSampleTimeRowIndex: Int?
    let cMixerSampleTimeTickInRow: Int?
    let playbackEngineOrderIndex: Int?
    let playbackEnginePatternIndex: Int?
    let playbackEngineRowIndex: Int?
    let playbackEngineTickInRow: Int?
    let playbackEngineToCMixerFrameDelta: Int?
    let playbackEngineToCMixerPositionMismatch: Bool?
    let rowTransitionDeltaCategory: String?
    let publishedPlaybackFollowPositionSource: String?
    let publishedPlaybackFollowOrderIndex: Int?
    let publishedPlaybackFollowPatternIndex: Int?
    let publishedPlaybackFollowRowIndex: Int?
    let publishedPlaybackFollowTickInRow: Int?
    let publishedPlaybackFollowSampleTimeFrame: Int?
    let publishedPlaybackFollowPositionStatus: String?
    let publishedPlaybackFollowSyntheticRow: Int?
    let publishedPlaybackFollowToCMixerFrameDelta: Int?
    let publishedPlaybackFollowToCMixerRowDelta: Int?
    let playbackEngineToPublishedPlaybackFollowFrameDelta: Int?
    let playbackEngineToPublishedPlaybackFollowRowDelta: Int?
    let playbackFollowPublicationDisabled: Bool?
    let playbackFollowPublicationCount: UInt64?
    let playbackFollowPublicationSuppressedCount: UInt64?
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
    let replacementOldVoiceIndex: Int?
    let replacementOldVoiceChannelTag: Int?
    let replacementOldVoiceGain: Float?
    let replacementOldVoiceEffectiveGain: Float?
    let replacementOldVoicePan: Float?
    let replacementOldVoiceEffectivePan: Float?
    let replacementOldVoiceSampleStep: Double?
    let replacementOldVoiceKeyOn: Bool?
    let replacementOldVoiceFadeoutValue: Float?
    let replacementRampStartVoiceIndex: Int?
    let replacementRampStartVoiceChannelTag: Int?
    let replacementRampStartGain: Float?
    let replacementRampTargetGain: Float?
    let replacementRampStartPan: Float?
    let replacementRampTargetPan: Float?
    let replacementRampStartSampleStep: Double?
    let replacementRampStartKeyOn: Bool?
    let replacementRampStartFadeoutValue: Float?
    let replacementNewVoiceIndex: Int?
    let replacementNewVoiceChannelTag: Int?
    let replacementGainPanAppliedBeforeRamp: Bool?
    let replacementStepAppliedBeforeRamp: Bool?
    let replacementKeyOffAppliedBeforeRamp: Bool?
    let replacementFadeoutAppliedBeforeRamp: Bool?
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
    let callbackDurationWarningThresholdMS: Double?
    let callbackDurationMinMS: Double?
    let callbackDurationMaxMS: Double?
    let callbackDurationAverageMS: Double?
    let callbackDurationWarningCount: UInt64?
    let callbackRenderQuantumDurationMS: Double?
    let callbackRenderQuantumMinMS: Double?
    let callbackRenderQuantumMaxMS: Double?
    let callbackOverRenderQuantumBudgetCount: UInt64?
    let callbackIntervalMinMS: Double?
    let callbackIntervalMaxMS: Double?
    let callbackIntervalLastMS: Double?
    let callbackThreadIsMain: Bool?
    let callbackThreadID: UInt64?
    let callbackMainThreadDependencyDetected: Bool?
    let callbackAllocationWarning: Bool?
    let callbackLockWaitCount: UInt64?
    let callbackLockWaitDurationMS: Double?
    let eventQueueProducerThreadID: UInt64?
    let eventQueueProducerThreadIsMain: Bool?
    let eventQueueConsumerThreadID: UInt64?
    let eventQueueConsumerThreadIsMain: Bool?
    let runtimeMinimalCallbackMode: Bool?
    let outputBufferCopyAttemptCount: UInt64?
    let outputBufferCopyFailureCount: UInt64?
    let outputBufferCopyLastSucceeded: Bool?
    let outputBufferCopyLayout: String?
    let outputBufferCopyRequestedFrameCount: Int?
    let outputBufferCopySourceChannelCount: Int?
    let outputBufferCopyOutputBufferCount: Int?
    let outputBufferCopyOutputChannelCount: Int?
    let outputBufferCopyCopiedFrameCount: Int?
    let outputBufferCopyCopiedSampleCount: Int?
    let outputBufferCopyExpectedSampleCount: Int?
    let outputBufferCopyFilledRequestedFrames: Bool?
    let outputBufferCopyChannelCountMatches: Bool?
    let outputBufferCopyPartialCopy: Bool?
    let outputBufferCopyScratchHash: UInt64?
    let outputBufferCopyCaptureHash: UInt64?
    let outputBufferCopyOutputHash: UInt64?
    let outputBufferCopyScratchCaptureHashMatches: Bool?
    let outputBufferCopyScratchOutputHashMatches: Bool?
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
    let outputDiscontinuityThreshold: Float?
    let outputDiscontinuityCount: UInt64?
    let outputDiscontinuityThresholdCounts: [RuntimeCMixerDiscontinuityThresholdCount]?
    let maxOutputAdjacentSampleJump: Float?
    let topOutputAdjacentSampleJumps: [RuntimeCMixerTopOutputSampleJump]?
    let lastOutputDiscontinuitySampleJump: Float?
    let lastOutputDiscontinuityCallbackIndex: UInt64?
    let lastOutputDiscontinuityRuntimeFrame: UInt64?
    let lastOutputDiscontinuityFrameOffset: Int?
    let lastOutputDiscontinuityChannelIndex: Int?
    let outputPeakWarningThreshold: Float?
    let outputPeakWarningSampleCount: UInt64?
    let topOutputPeaks: [RuntimeCMixerTopOutputPeak]?
    let overrangeSampleCount: UInt64?
    let clippingSampleCount: UInt64?
    let clippingDetected: Bool?
    let runtimeOutputGain: Float?
    let runtimeHeadroomPolicy: String?
    let runtimeGainPolicyLabel: String?
    let runtimeDefaultHeadroomDB: Double?
    let runtimeGainPolicySource: String?
    let runtimeGainPolicyIsEnvironmentOverride: Bool?
    let runtimeAutoHeadroomEnabled: Bool?
    let runtimeFixedHeadroomDB: Double?
    let runtimeGainConfigurationWarning: String?
    let runtimeClippingRecommendation: String?
    let runtimeUpdateEpsilon: Double?
    let runtimeUpdateEpsilonPolicy: String?
    let runtimeUpdateEpsilonConfigurationWarning: String?
    let runtimeCaptureEnabled: Bool?
    let runtimeCapturePathName: String?
    let runtimeCaptureSampleRate: Double?
    let runtimeCaptureChannelCount: Int?
    let runtimeCaptureSeconds: Double?
    let runtimeCaptureFrameLimit: Int?
    let runtimeCapturedFrameCount: Int?
    let runtimeCaptureDurationSeconds: Double?
    let runtimeCaptureTruncated: Bool?
    let runtimeCaptureOutputPeak: Float?
    let runtimeCaptureOutputRMS: Float?
    let runtimeCaptureOverrangeSampleCount: UInt64?
    let runtimeCaptureClippingSampleCount: UInt64?
    let runtimeCaptureWriteSucceeded: Bool?
    let runtimeCaptureWriteError: String?
    let runtimeCaptureConfigurationWarning: String?
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
    let rampingOutVoiceCount: Int?
    let rampDownStartCount: UInt64?
    let rampDownCompletionCount: UInt64?
    let abruptRampDownStopCount: UInt64?
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
        eventAppliedFrame: UInt64? = nil,
        inCallbackOffset: Int? = nil,
        plannedVsAppliedDelta: Int? = nil,
        sameFrameBurstSize: Int? = nil,
        sameFrameBurstID: Int? = nil,
        sameFrameBurstEventOrdinal: Int? = nil,
        sameFrameBurstCategories: [String]? = nil,
        sameFrameBurstAffectedChannels: [Int]? = nil,
        sameFrameBurstNoteTriggerCount: Int? = nil,
        sameFrameBurstReplacementRampCount: Int? = nil,
        sameFrameBurstGainPanUpdateCount: Int? = nil,
        sameFrameBurstStepUpdateCount: Int? = nil,
        sameFrameBurstNoteCutCount: Int? = nil,
        sameFrameBurstKeyOffCount: Int? = nil,
        sameFrameBurstGlobalVolumeUpdateCount: Int? = nil,
        sameFrameBurstActiveVoiceCountBefore: Int? = nil,
        sameFrameBurstActiveVoiceCountAfter: Int? = nil,
        sameFrameBurstLoadedVoiceCountBefore: Int? = nil,
        sameFrameBurstLoadedVoiceCountAfter: Int? = nil,
        sameFrameBurstVoicesEnteringRampDown: Int? = nil,
        sameFrameBurstVoicesCompletingRampDown: Int? = nil,
        sameFrameBurstNewVoicesStarted: Int? = nil,
        sameFrameBurstSustainedVoicesCarried: Int? = nil,
        sameFrameBurstAtOrderStart: Bool? = nil,
        sameFrameBurstAtRowTransition: Bool? = nil,
        adapterActiveEventIndex: Int? = nil,
        adapterCurrentEventIndexBefore: Int? = nil,
        adapterCurrentEventIndexAfter: Int? = nil,
        adapterChannelAssociationRetained: Bool? = nil,
        adapterSustainedVoiceUpdate: Bool? = nil,
        maxPlannedVsAppliedDelta: Int? = nil,
        appliedPlannedEventCount: UInt64? = nil,
        exactFrameAppliedEventCount: UInt64? = nil,
        callbackBoundaryAppliedEventCount: UInt64? = nil,
        latePlannedEventCount: UInt64? = nil,
        fallbackToSimpleRuntimeEventCount: UInt64? = nil,
        runtimeEventFallbackReason: String? = nil,
        experimentalCMixerEnabled: Bool,
        sampleRate: Double? = nil,
        selectedRuntimeSampleRate: Double? = nil,
        cMixerRuntimeSampleRate: Double? = nil,
        runtimeSampleRatePolicy: String? = nil,
        runtimeSampleRateSource: String? = nil,
        runtimeSampleRateConfigurationWarning: String? = nil,
        cMixerRenderSampleRate: Double? = nil,
        cMixerRenderChannelCount: Int? = nil,
        audioSourceNodeRenderSampleRate: Double? = nil,
        audioSourceNodeChannelCount: Int? = nil,
        audioEngineMainMixerOutputSampleRate: Double? = nil,
        audioEngineMainMixerOutputChannelCount: Int? = nil,
        audioEngineMainMixerInputSampleRate: Double? = nil,
        audioEngineMainMixerInputChannelCount: Int? = nil,
        audioEngineMainMixerLatency: Double? = nil,
        audioEngineMainMixerOutputPresentationLatency: Double? = nil,
        audioEngineOutputNodeSampleRate: Double? = nil,
        audioEngineOutputNodeChannelCount: Int? = nil,
        audioEngineOutputNodeLatency: Double? = nil,
        audioEngineOutputNodeOutputPresentationLatency: Double? = nil,
        audioHardwareNominalSampleRate: Double? = nil,
        audioHardwareDeviceID: UInt32? = nil,
        audioHardwareDeviceUIDHash: String? = nil,
        audioHardwareIOBufferFrameSize: UInt32? = nil,
        audioHardwareIOBufferDuration: Double? = nil,
        audioHardwareLatencyFrames: UInt32? = nil,
        audioHardwareLatencyDuration: Double? = nil,
        audioHardwareSafetyOffsetFrames: UInt32? = nil,
        audioHardwareSafetyOffsetDuration: Double? = nil,
        audioHardwareTransportType: UInt32? = nil,
        audioEngineRunning: Bool? = nil,
        audioEngineSourceNodeAttached: Bool? = nil,
        audioEngineSourceNodeConnected: Bool? = nil,
        audioEngineMainMixerConnectedToOutput: Bool? = nil,
        audioEngineConfigurationChangeCount: UInt64? = nil,
        audioGraphFormatChangeCount: UInt64? = nil,
        audioOutputRouteChangeCount: UInt64? = nil,
        audioGraphFormatChanged: Bool? = nil,
        audioOutputRouteChanged: Bool? = nil,
        audioFormatConversionLikely: Bool? = nil,
        runtimeCaptureMatchesSourceNodeFormat: Bool? = nil,
        runtimeCaptureMatchesEngineOutputFormat: Bool? = nil,
        runtimeCaptureMatchesHardwareSampleRate: Bool? = nil,
        cMixerRenderedFrames: UInt64? = nil,
        cMixerPlaybackSeconds: Double? = nil,
        cMixerSampleTimeFrame: Int? = nil,
        cMixerSampleTimePositionStatus: String? = nil,
        cMixerSampleTimeOrderIndex: Int? = nil,
        cMixerSampleTimePatternIndex: Int? = nil,
        cMixerSampleTimeRowIndex: Int? = nil,
        cMixerSampleTimeTickInRow: Int? = nil,
        playbackEngineOrderIndex: Int? = nil,
        playbackEnginePatternIndex: Int? = nil,
        playbackEngineRowIndex: Int? = nil,
        playbackEngineTickInRow: Int? = nil,
        playbackEngineToCMixerFrameDelta: Int? = nil,
        playbackEngineToCMixerPositionMismatch: Bool? = nil,
        rowTransitionDeltaCategory: String? = nil,
        publishedPlaybackFollowPositionSource: String? = nil,
        publishedPlaybackFollowOrderIndex: Int? = nil,
        publishedPlaybackFollowPatternIndex: Int? = nil,
        publishedPlaybackFollowRowIndex: Int? = nil,
        publishedPlaybackFollowTickInRow: Int? = nil,
        publishedPlaybackFollowSampleTimeFrame: Int? = nil,
        publishedPlaybackFollowPositionStatus: String? = nil,
        publishedPlaybackFollowSyntheticRow: Int? = nil,
        publishedPlaybackFollowToCMixerFrameDelta: Int? = nil,
        publishedPlaybackFollowToCMixerRowDelta: Int? = nil,
        playbackEngineToPublishedPlaybackFollowFrameDelta: Int? = nil,
        playbackEngineToPublishedPlaybackFollowRowDelta: Int? = nil,
        playbackFollowPublicationDisabled: Bool? = nil,
        playbackFollowPublicationCount: UInt64? = nil,
        playbackFollowPublicationSuppressedCount: UInt64? = nil,
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
        currentFrame: UInt64? = nil,
        runtimeRenderedFrameCount: UInt64? = nil,
        scheduledVoiceCount: Int? = nil,
        eventQueueBacklogCount: Int? = nil,
        callbackIndex: UInt64? = nil,
        callbackRequestedFrameCount: Int? = nil,
        callbackStartFrame: UInt64? = nil,
        callbackEndFrame: UInt64? = nil,
        callbackDurationWarningThresholdMS: Double? = nil,
        callbackDurationMinMS: Double? = nil,
        callbackDurationMaxMS: Double? = nil,
        callbackDurationAverageMS: Double? = nil,
        callbackDurationWarningCount: UInt64? = nil,
        callbackRenderQuantumDurationMS: Double? = nil,
        callbackRenderQuantumMinMS: Double? = nil,
        callbackRenderQuantumMaxMS: Double? = nil,
        callbackOverRenderQuantumBudgetCount: UInt64? = nil,
        callbackIntervalMinMS: Double? = nil,
        callbackIntervalMaxMS: Double? = nil,
        callbackIntervalLastMS: Double? = nil,
        callbackThreadIsMain: Bool? = nil,
        callbackThreadID: UInt64? = nil,
        callbackMainThreadDependencyDetected: Bool? = nil,
        callbackAllocationWarning: Bool? = nil,
        callbackLockWaitCount: UInt64? = nil,
        callbackLockWaitDurationMS: Double? = nil,
        eventQueueProducerThreadID: UInt64? = nil,
        eventQueueProducerThreadIsMain: Bool? = nil,
        eventQueueConsumerThreadID: UInt64? = nil,
        eventQueueConsumerThreadIsMain: Bool? = nil,
        runtimeMinimalCallbackMode: Bool? = nil,
        outputBufferCopyAttemptCount: UInt64? = nil,
        outputBufferCopyFailureCount: UInt64? = nil,
        outputBufferCopyLastSucceeded: Bool? = nil,
        outputBufferCopyLayout: String? = nil,
        outputBufferCopyRequestedFrameCount: Int? = nil,
        outputBufferCopySourceChannelCount: Int? = nil,
        outputBufferCopyOutputBufferCount: Int? = nil,
        outputBufferCopyOutputChannelCount: Int? = nil,
        outputBufferCopyCopiedFrameCount: Int? = nil,
        outputBufferCopyCopiedSampleCount: Int? = nil,
        outputBufferCopyExpectedSampleCount: Int? = nil,
        outputBufferCopyFilledRequestedFrames: Bool? = nil,
        outputBufferCopyChannelCountMatches: Bool? = nil,
        outputBufferCopyPartialCopy: Bool? = nil,
        outputBufferCopyScratchHash: UInt64? = nil,
        outputBufferCopyCaptureHash: UInt64? = nil,
        outputBufferCopyOutputHash: UInt64? = nil,
        outputBufferCopyScratchCaptureHashMatches: Bool? = nil,
        outputBufferCopyScratchOutputHashMatches: Bool? = nil,
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
        outputDiscontinuityThreshold: Float? = nil,
        outputDiscontinuityCount: UInt64? = nil,
        outputDiscontinuityThresholdCounts: [RuntimeCMixerDiscontinuityThresholdCount]? = nil,
        maxOutputAdjacentSampleJump: Float? = nil,
        topOutputAdjacentSampleJumps: [RuntimeCMixerTopOutputSampleJump]? = nil,
        lastOutputDiscontinuitySampleJump: Float? = nil,
        lastOutputDiscontinuityCallbackIndex: UInt64? = nil,
        lastOutputDiscontinuityRuntimeFrame: UInt64? = nil,
        lastOutputDiscontinuityFrameOffset: Int? = nil,
        lastOutputDiscontinuityChannelIndex: Int? = nil,
        outputPeakWarningThreshold: Float? = nil,
        outputPeakWarningSampleCount: UInt64? = nil,
        topOutputPeaks: [RuntimeCMixerTopOutputPeak]? = nil,
        overrangeSampleCount: UInt64? = nil,
        clippingSampleCount: UInt64? = nil,
        clippingDetected: Bool? = nil,
        runtimeOutputGain: Float? = nil,
        runtimeHeadroomPolicy: String? = nil,
        runtimeGainPolicyLabel: String? = nil,
        runtimeDefaultHeadroomDB: Double? = nil,
        runtimeGainPolicySource: String? = nil,
        runtimeGainPolicyIsEnvironmentOverride: Bool? = nil,
        runtimeAutoHeadroomEnabled: Bool? = nil,
        runtimeFixedHeadroomDB: Double? = nil,
        runtimeGainConfigurationWarning: String? = nil,
        runtimeClippingRecommendation: String? = nil,
        runtimeUpdateEpsilon: Double? = nil,
        runtimeUpdateEpsilonPolicy: String? = nil,
        runtimeUpdateEpsilonConfigurationWarning: String? = nil,
        runtimeCaptureEnabled: Bool? = nil,
        runtimeCapturePathName: String? = nil,
        runtimeCaptureSampleRate: Double? = nil,
        runtimeCaptureChannelCount: Int? = nil,
        runtimeCaptureSeconds: Double? = nil,
        runtimeCaptureFrameLimit: Int? = nil,
        runtimeCapturedFrameCount: Int? = nil,
        runtimeCaptureDurationSeconds: Double? = nil,
        runtimeCaptureTruncated: Bool? = nil,
        runtimeCaptureOutputPeak: Float? = nil,
        runtimeCaptureOutputRMS: Float? = nil,
        runtimeCaptureOverrangeSampleCount: UInt64? = nil,
        runtimeCaptureClippingSampleCount: UInt64? = nil,
        runtimeCaptureWriteSucceeded: Bool? = nil,
        runtimeCaptureWriteError: String? = nil,
        runtimeCaptureConfigurationWarning: String? = nil,
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
        rampingOutVoiceCount: Int? = nil,
        rampDownStartCount: UInt64? = nil,
        rampDownCompletionCount: UInt64? = nil,
        abruptRampDownStopCount: UInt64? = nil,
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
        self.eventAppliedFrame = eventAppliedFrame ?? runtimeApplicationFrame
        self.inCallbackOffset = inCallbackOffset
        self.plannedVsAppliedDelta = plannedVsAppliedDelta ?? eventFrameDelta
        self.sameFrameBurstSize = sameFrameBurstSize
        self.sameFrameBurstID = sameFrameBurstID
        self.sameFrameBurstEventOrdinal = sameFrameBurstEventOrdinal
        self.sameFrameBurstCategories = sameFrameBurstCategories
        self.sameFrameBurstAffectedChannels = sameFrameBurstAffectedChannels
        self.sameFrameBurstNoteTriggerCount = sameFrameBurstNoteTriggerCount
        self.sameFrameBurstReplacementRampCount = sameFrameBurstReplacementRampCount
        self.sameFrameBurstGainPanUpdateCount = sameFrameBurstGainPanUpdateCount
        self.sameFrameBurstStepUpdateCount = sameFrameBurstStepUpdateCount
        self.sameFrameBurstNoteCutCount = sameFrameBurstNoteCutCount
        self.sameFrameBurstKeyOffCount = sameFrameBurstKeyOffCount
        self.sameFrameBurstGlobalVolumeUpdateCount = sameFrameBurstGlobalVolumeUpdateCount
        self.sameFrameBurstActiveVoiceCountBefore = sameFrameBurstActiveVoiceCountBefore
        self.sameFrameBurstActiveVoiceCountAfter = sameFrameBurstActiveVoiceCountAfter
        self.sameFrameBurstLoadedVoiceCountBefore = sameFrameBurstLoadedVoiceCountBefore
        self.sameFrameBurstLoadedVoiceCountAfter = sameFrameBurstLoadedVoiceCountAfter
        self.sameFrameBurstVoicesEnteringRampDown = sameFrameBurstVoicesEnteringRampDown
        self.sameFrameBurstVoicesCompletingRampDown = sameFrameBurstVoicesCompletingRampDown
        self.sameFrameBurstNewVoicesStarted = sameFrameBurstNewVoicesStarted
        self.sameFrameBurstSustainedVoicesCarried = sameFrameBurstSustainedVoicesCarried
        self.sameFrameBurstAtOrderStart = sameFrameBurstAtOrderStart
        self.sameFrameBurstAtRowTransition = sameFrameBurstAtRowTransition
        self.adapterActiveEventIndex = adapterActiveEventIndex
        self.adapterCurrentEventIndexBefore = adapterCurrentEventIndexBefore
        self.adapterCurrentEventIndexAfter = adapterCurrentEventIndexAfter
        self.adapterChannelAssociationRetained = adapterChannelAssociationRetained
        self.adapterSustainedVoiceUpdate = adapterSustainedVoiceUpdate
        self.maxPlannedVsAppliedDelta = maxPlannedVsAppliedDelta
        self.appliedPlannedEventCount = appliedPlannedEventCount
        self.exactFrameAppliedEventCount = exactFrameAppliedEventCount
        self.callbackBoundaryAppliedEventCount = callbackBoundaryAppliedEventCount
        self.latePlannedEventCount = latePlannedEventCount
        self.fallbackToSimpleRuntimeEventCount = fallbackToSimpleRuntimeEventCount
        self.runtimeEventFallbackReason = runtimeEventFallbackReason
        self.experimentalCMixerEnabled = experimentalCMixerEnabled
        self.sampleRate = sampleRate
        self.selectedRuntimeSampleRate = selectedRuntimeSampleRate
        self.cMixerRuntimeSampleRate = cMixerRuntimeSampleRate
        self.runtimeSampleRatePolicy = runtimeSampleRatePolicy
        self.runtimeSampleRateSource = runtimeSampleRateSource
        self.runtimeSampleRateConfigurationWarning = runtimeSampleRateConfigurationWarning
        self.cMixerRenderSampleRate = cMixerRenderSampleRate
        self.cMixerRenderChannelCount = cMixerRenderChannelCount
        self.audioSourceNodeRenderSampleRate = audioSourceNodeRenderSampleRate
        self.audioSourceNodeChannelCount = audioSourceNodeChannelCount
        self.audioEngineMainMixerOutputSampleRate = audioEngineMainMixerOutputSampleRate
        self.audioEngineMainMixerOutputChannelCount = audioEngineMainMixerOutputChannelCount
        self.audioEngineMainMixerInputSampleRate = audioEngineMainMixerInputSampleRate
        self.audioEngineMainMixerInputChannelCount = audioEngineMainMixerInputChannelCount
        self.audioEngineMainMixerLatency = audioEngineMainMixerLatency
        self.audioEngineMainMixerOutputPresentationLatency = audioEngineMainMixerOutputPresentationLatency
        self.audioEngineOutputNodeSampleRate = audioEngineOutputNodeSampleRate
        self.audioEngineOutputNodeChannelCount = audioEngineOutputNodeChannelCount
        self.audioEngineOutputNodeLatency = audioEngineOutputNodeLatency
        self.audioEngineOutputNodeOutputPresentationLatency = audioEngineOutputNodeOutputPresentationLatency
        self.audioHardwareNominalSampleRate = audioHardwareNominalSampleRate
        self.audioHardwareDeviceID = audioHardwareDeviceID
        self.audioHardwareDeviceUIDHash = audioHardwareDeviceUIDHash
        self.audioHardwareIOBufferFrameSize = audioHardwareIOBufferFrameSize
        self.audioHardwareIOBufferDuration = audioHardwareIOBufferDuration
        self.audioHardwareLatencyFrames = audioHardwareLatencyFrames
        self.audioHardwareLatencyDuration = audioHardwareLatencyDuration
        self.audioHardwareSafetyOffsetFrames = audioHardwareSafetyOffsetFrames
        self.audioHardwareSafetyOffsetDuration = audioHardwareSafetyOffsetDuration
        self.audioHardwareTransportType = audioHardwareTransportType
        self.audioEngineRunning = audioEngineRunning
        self.audioEngineSourceNodeAttached = audioEngineSourceNodeAttached
        self.audioEngineSourceNodeConnected = audioEngineSourceNodeConnected
        self.audioEngineMainMixerConnectedToOutput = audioEngineMainMixerConnectedToOutput
        self.audioEngineConfigurationChangeCount = audioEngineConfigurationChangeCount
        self.audioGraphFormatChangeCount = audioGraphFormatChangeCount
        self.audioOutputRouteChangeCount = audioOutputRouteChangeCount
        self.audioGraphFormatChanged = audioGraphFormatChanged
        self.audioOutputRouteChanged = audioOutputRouteChanged
        self.audioFormatConversionLikely = audioFormatConversionLikely
        self.runtimeCaptureMatchesSourceNodeFormat = runtimeCaptureMatchesSourceNodeFormat
        self.runtimeCaptureMatchesEngineOutputFormat = runtimeCaptureMatchesEngineOutputFormat
        self.runtimeCaptureMatchesHardwareSampleRate = runtimeCaptureMatchesHardwareSampleRate
        self.cMixerRenderedFrames = cMixerRenderedFrames
        self.cMixerPlaybackSeconds = cMixerPlaybackSeconds
        self.cMixerSampleTimeFrame = cMixerSampleTimeFrame
        self.cMixerSampleTimePositionStatus = cMixerSampleTimePositionStatus
        self.cMixerSampleTimeOrderIndex = cMixerSampleTimeOrderIndex
        self.cMixerSampleTimePatternIndex = cMixerSampleTimePatternIndex
        self.cMixerSampleTimeRowIndex = cMixerSampleTimeRowIndex
        self.cMixerSampleTimeTickInRow = cMixerSampleTimeTickInRow
        self.playbackEngineOrderIndex = playbackEngineOrderIndex ?? context?.orderIndex
        self.playbackEnginePatternIndex = playbackEnginePatternIndex ?? context?.patternIndex
        self.playbackEngineRowIndex = playbackEngineRowIndex ?? context?.rowIndex
        self.playbackEngineTickInRow = playbackEngineTickInRow ?? context?.tickInRow
        self.playbackEngineToCMixerFrameDelta = playbackEngineToCMixerFrameDelta
        self.playbackEngineToCMixerPositionMismatch = playbackEngineToCMixerPositionMismatch
        self.rowTransitionDeltaCategory = rowTransitionDeltaCategory
        self.publishedPlaybackFollowPositionSource = publishedPlaybackFollowPositionSource
        self.publishedPlaybackFollowOrderIndex = publishedPlaybackFollowOrderIndex
        self.publishedPlaybackFollowPatternIndex = publishedPlaybackFollowPatternIndex
        self.publishedPlaybackFollowRowIndex = publishedPlaybackFollowRowIndex
        self.publishedPlaybackFollowTickInRow = publishedPlaybackFollowTickInRow
        self.publishedPlaybackFollowSampleTimeFrame = publishedPlaybackFollowSampleTimeFrame
        self.publishedPlaybackFollowPositionStatus = publishedPlaybackFollowPositionStatus
        self.publishedPlaybackFollowSyntheticRow = publishedPlaybackFollowSyntheticRow
        self.publishedPlaybackFollowToCMixerFrameDelta = publishedPlaybackFollowToCMixerFrameDelta
        self.publishedPlaybackFollowToCMixerRowDelta = publishedPlaybackFollowToCMixerRowDelta
        self.playbackEngineToPublishedPlaybackFollowFrameDelta = playbackEngineToPublishedPlaybackFollowFrameDelta
        self.playbackEngineToPublishedPlaybackFollowRowDelta = playbackEngineToPublishedPlaybackFollowRowDelta
        self.playbackFollowPublicationDisabled = playbackFollowPublicationDisabled
        self.playbackFollowPublicationCount = playbackFollowPublicationCount
        self.playbackFollowPublicationSuppressedCount = playbackFollowPublicationSuppressedCount
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
        replacementOldVoiceIndex = replacementOldVoiceState?.voiceIndex
        replacementOldVoiceChannelTag = replacementOldVoiceState?.channelTag
        replacementOldVoiceGain = replacementOldVoiceState?.gain
        replacementOldVoiceEffectiveGain = replacementOldVoiceState?.effectiveGain
        replacementOldVoicePan = replacementOldVoiceState?.pan
        replacementOldVoiceEffectivePan = replacementOldVoiceState?.effectivePan
        replacementOldVoiceSampleStep = replacementOldVoiceState?.sampleStep
        replacementOldVoiceKeyOn = replacementOldVoiceState?.keyOn
        replacementOldVoiceFadeoutValue = replacementOldVoiceState?.fadeoutValue
        replacementRampStartVoiceIndex = replacementRampStartState?.voiceIndex
        replacementRampStartVoiceChannelTag = replacementRampStartState?.channelTag
        replacementRampStartGain = replacementRampStartState?.gainRampStart ?? replacementRampStartState?.effectiveGain
        self.replacementRampTargetGain = replacementRampTargetGain ?? replacementRampStartState?.gainRampTarget
        replacementRampStartPan = replacementRampStartState?.panRampStart ?? replacementRampStartState?.effectivePan
        replacementRampTargetPan = replacementRampStartState?.panRampTarget ?? replacementRampStartState?.pan
        replacementRampStartSampleStep = replacementRampStartState?.sampleStep
        replacementRampStartKeyOn = replacementRampStartState?.keyOn
        replacementRampStartFadeoutValue = replacementRampStartState?.fadeoutValue
        self.replacementNewVoiceIndex = replacementNewVoiceIndex
        self.replacementNewVoiceChannelTag = replacementNewVoiceChannelTag
        self.replacementGainPanAppliedBeforeRamp = replacementGainPanAppliedBeforeRamp
        self.replacementStepAppliedBeforeRamp = replacementStepAppliedBeforeRamp
        self.replacementKeyOffAppliedBeforeRamp = replacementKeyOffAppliedBeforeRamp
        self.replacementFadeoutAppliedBeforeRamp = replacementFadeoutAppliedBeforeRamp
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
        self.callbackDurationWarningThresholdMS = callbackDurationWarningThresholdMS
        self.callbackDurationMinMS = callbackDurationMinMS
        self.callbackDurationMaxMS = callbackDurationMaxMS
        self.callbackDurationAverageMS = callbackDurationAverageMS
        self.callbackDurationWarningCount = callbackDurationWarningCount
        self.callbackRenderQuantumDurationMS = callbackRenderQuantumDurationMS
        self.callbackRenderQuantumMinMS = callbackRenderQuantumMinMS
        self.callbackRenderQuantumMaxMS = callbackRenderQuantumMaxMS
        self.callbackOverRenderQuantumBudgetCount = callbackOverRenderQuantumBudgetCount
        self.callbackIntervalMinMS = callbackIntervalMinMS
        self.callbackIntervalMaxMS = callbackIntervalMaxMS
        self.callbackIntervalLastMS = callbackIntervalLastMS
        self.callbackThreadIsMain = callbackThreadIsMain
        self.callbackThreadID = callbackThreadID
        self.callbackMainThreadDependencyDetected = callbackMainThreadDependencyDetected
        self.callbackAllocationWarning = callbackAllocationWarning
        self.callbackLockWaitCount = callbackLockWaitCount
        self.callbackLockWaitDurationMS = callbackLockWaitDurationMS
        self.eventQueueProducerThreadID = eventQueueProducerThreadID
        self.eventQueueProducerThreadIsMain = eventQueueProducerThreadIsMain
        self.eventQueueConsumerThreadID = eventQueueConsumerThreadID
        self.eventQueueConsumerThreadIsMain = eventQueueConsumerThreadIsMain
        self.runtimeMinimalCallbackMode = runtimeMinimalCallbackMode
        self.outputBufferCopyAttemptCount = outputBufferCopyAttemptCount
        self.outputBufferCopyFailureCount = outputBufferCopyFailureCount
        self.outputBufferCopyLastSucceeded = outputBufferCopyLastSucceeded
        self.outputBufferCopyLayout = outputBufferCopyLayout
        self.outputBufferCopyRequestedFrameCount = outputBufferCopyRequestedFrameCount
        self.outputBufferCopySourceChannelCount = outputBufferCopySourceChannelCount
        self.outputBufferCopyOutputBufferCount = outputBufferCopyOutputBufferCount
        self.outputBufferCopyOutputChannelCount = outputBufferCopyOutputChannelCount
        self.outputBufferCopyCopiedFrameCount = outputBufferCopyCopiedFrameCount
        self.outputBufferCopyCopiedSampleCount = outputBufferCopyCopiedSampleCount
        self.outputBufferCopyExpectedSampleCount = outputBufferCopyExpectedSampleCount
        self.outputBufferCopyFilledRequestedFrames = outputBufferCopyFilledRequestedFrames
        self.outputBufferCopyChannelCountMatches = outputBufferCopyChannelCountMatches
        self.outputBufferCopyPartialCopy = outputBufferCopyPartialCopy
        self.outputBufferCopyScratchHash = outputBufferCopyScratchHash
        self.outputBufferCopyCaptureHash = outputBufferCopyCaptureHash
        self.outputBufferCopyOutputHash = outputBufferCopyOutputHash
        self.outputBufferCopyScratchCaptureHashMatches = outputBufferCopyScratchCaptureHashMatches
        self.outputBufferCopyScratchOutputHashMatches = outputBufferCopyScratchOutputHashMatches
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
        self.outputDiscontinuityThreshold = outputDiscontinuityThreshold
        self.outputDiscontinuityCount = outputDiscontinuityCount
        self.outputDiscontinuityThresholdCounts = outputDiscontinuityThresholdCounts
        self.maxOutputAdjacentSampleJump = maxOutputAdjacentSampleJump
        self.topOutputAdjacentSampleJumps = topOutputAdjacentSampleJumps
        self.lastOutputDiscontinuitySampleJump = lastOutputDiscontinuitySampleJump
        self.lastOutputDiscontinuityCallbackIndex = lastOutputDiscontinuityCallbackIndex
        self.lastOutputDiscontinuityRuntimeFrame = lastOutputDiscontinuityRuntimeFrame
        self.lastOutputDiscontinuityFrameOffset = lastOutputDiscontinuityFrameOffset
        self.lastOutputDiscontinuityChannelIndex = lastOutputDiscontinuityChannelIndex
        self.outputPeakWarningThreshold = outputPeakWarningThreshold
        self.outputPeakWarningSampleCount = outputPeakWarningSampleCount
        self.topOutputPeaks = topOutputPeaks
        self.overrangeSampleCount = overrangeSampleCount
        self.clippingSampleCount = clippingSampleCount
        self.clippingDetected = clippingDetected
        self.runtimeOutputGain = runtimeOutputGain
        self.runtimeHeadroomPolicy = runtimeHeadroomPolicy
        self.runtimeGainPolicyLabel = runtimeGainPolicyLabel
        self.runtimeDefaultHeadroomDB = runtimeDefaultHeadroomDB
        self.runtimeGainPolicySource = runtimeGainPolicySource
        self.runtimeGainPolicyIsEnvironmentOverride = runtimeGainPolicyIsEnvironmentOverride
        self.runtimeAutoHeadroomEnabled = runtimeAutoHeadroomEnabled
        self.runtimeFixedHeadroomDB = runtimeFixedHeadroomDB
        self.runtimeGainConfigurationWarning = runtimeGainConfigurationWarning
        self.runtimeClippingRecommendation = runtimeClippingRecommendation
        self.runtimeUpdateEpsilon = runtimeUpdateEpsilon
        self.runtimeUpdateEpsilonPolicy = runtimeUpdateEpsilonPolicy
        self.runtimeUpdateEpsilonConfigurationWarning = runtimeUpdateEpsilonConfigurationWarning
        self.runtimeCaptureEnabled = runtimeCaptureEnabled
        self.runtimeCapturePathName = runtimeCapturePathName
        self.runtimeCaptureSampleRate = runtimeCaptureSampleRate
        self.runtimeCaptureChannelCount = runtimeCaptureChannelCount
        self.runtimeCaptureSeconds = runtimeCaptureSeconds
        self.runtimeCaptureFrameLimit = runtimeCaptureFrameLimit
        self.runtimeCapturedFrameCount = runtimeCapturedFrameCount
        self.runtimeCaptureDurationSeconds = runtimeCaptureDurationSeconds
        self.runtimeCaptureTruncated = runtimeCaptureTruncated
        self.runtimeCaptureOutputPeak = runtimeCaptureOutputPeak
        self.runtimeCaptureOutputRMS = runtimeCaptureOutputRMS
        self.runtimeCaptureOverrangeSampleCount = runtimeCaptureOverrangeSampleCount
        self.runtimeCaptureClippingSampleCount = runtimeCaptureClippingSampleCount
        self.runtimeCaptureWriteSucceeded = runtimeCaptureWriteSucceeded
        self.runtimeCaptureWriteError = runtimeCaptureWriteError
        self.runtimeCaptureConfigurationWarning = runtimeCaptureConfigurationWarning
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
        self.rampingOutVoiceCount = rampingOutVoiceCount
        self.rampDownStartCount = rampDownStartCount
        self.rampDownCompletionCount = rampDownCompletionCount
        self.abruptRampDownStopCount = abruptRampDownStopCount
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
        guard
            !RuntimeCMixerDiagnosticEnvironment.flagEnabled(
                RuntimeCMixerDiagnosticEnvironment.disableTraceEnvironmentKey,
                environment: environment
            ),
            !RuntimeCMixerDiagnosticEnvironment.flagEnabled(
                RuntimeCMixerDiagnosticEnvironment.minimalCallbackEnvironmentKey,
                environment: environment
            )
        else {
            return nil
        }
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

struct RuntimeCMixerCaptureConfiguration: Equatable {
    static let pathEnvironmentKey = "VTX_C_MIXER_RUNTIME_CAPTURE_PATH"
    static let secondsEnvironmentKey = "VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS"
    static let defaultCaptureSeconds = 240.0
    static let maximumCaptureSeconds = 240.0

    let url: URL
    let pathName: String
    let seconds: Double
    let secondsPolicy: String
    let configurationWarning: String?

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeCMixerCaptureConfiguration? {
        guard !RuntimeCMixerDiagnosticEnvironment.flagEnabled(
            RuntimeCMixerDiagnosticEnvironment.disableCaptureEnvironmentKey,
            environment: environment
        ) else {
            return nil
        }
        guard let rawPath = trimmedEnvironmentValue(environment[pathEnvironmentKey]) else {
            return nil
        }
        let url = URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
        let pathName = url.lastPathComponent.isEmpty ? "runtime-c-mixer-capture.wav" : url.lastPathComponent
        let rawSeconds = trimmedEnvironmentValue(environment[secondsEnvironmentKey])
        let secondsResult = seconds(from: rawSeconds)
        return RuntimeCMixerCaptureConfiguration(
            url: url,
            pathName: pathName,
            seconds: secondsResult.seconds,
            secondsPolicy: secondsResult.policy,
            configurationWarning: secondsResult.warning
        )
    }

    func frameLimit(sampleRate: Double) -> Int {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : MixerRenderConfig.defaultSampleRate
        let frames = (safeSampleRate * seconds).rounded(.up)
        guard frames.isFinite,
              frames > 0,
              frames <= Double(Int.max) else {
            return Int.max
        }
        return max(1, Int(frames))
    }

    private static func seconds(from rawValue: String?) -> (seconds: Double, policy: String, warning: String?) {
        guard let rawValue else {
            return (defaultCaptureSeconds, "default_runtime_capture_seconds", nil)
        }
        guard let parsed = Double(rawValue),
              parsed.isFinite,
              parsed > 0 else {
            return (defaultCaptureSeconds, "default_runtime_capture_seconds_fallback", "invalid_runtime_capture_seconds")
        }
        guard parsed <= maximumCaptureSeconds else {
            return (maximumCaptureSeconds, "max_runtime_capture_seconds_fallback", "runtime_capture_seconds_capped")
        }
        return (parsed, "env_runtime_capture_seconds", nil)
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct RuntimeCMixerCaptureSnapshot: Equatable {
    let enabled: Bool
    let pathName: String?
    let sampleRate: Double?
    let channelCount: Int?
    let seconds: Double?
    let frameLimit: Int?
    let capturedFrameCount: Int
    let truncated: Bool
    let outputPeak: Float
    let outputRMS: Float
    let overrangeSampleCount: UInt64
    let clippingSampleCount: UInt64
    let configurationWarning: String?

    var durationSeconds: Double? {
        guard let sampleRate,
              sampleRate > 0 else {
            return nil
        }
        return Double(capturedFrameCount) / sampleRate
    }

    static let disabled = RuntimeCMixerCaptureSnapshot(
        enabled: false,
        pathName: nil,
        sampleRate: nil,
        channelCount: nil,
        seconds: nil,
        frameLimit: nil,
        capturedFrameCount: 0,
        truncated: false,
        outputPeak: 0,
        outputRMS: 0,
        overrangeSampleCount: 0,
        clippingSampleCount: 0,
        configurationWarning: nil
    )
}

struct RuntimeCMixerCaptureBlockSnapshot: Equatable {
    let configuration: RuntimeCMixerCaptureConfiguration
    let snapshot: RuntimeCMixerCaptureSnapshot
    let block: MixerRenderBlock
}

final class RuntimeCMixerCaptureBuffer {
    let configuration: RuntimeCMixerCaptureConfiguration
    let config: MixerRenderConfig
    let frameLimit: Int

    private var interleavedPCM: [Float]
    private var capturedFrameCount = 0
    private var truncated = false
    private var outputPeak = Float(0)
    private var outputSquareSum = Double(0)
    private var capturedSampleCount: UInt64 = 0
    private var overrangeSampleCount: UInt64 = 0
    private var clippingSampleCount: UInt64 = 0

    init(configuration: RuntimeCMixerCaptureConfiguration, config: MixerRenderConfig) {
        self.configuration = configuration
        self.config = config
        frameLimit = configuration.frameLimit(sampleRate: config.sampleRate)
        let channelCount = max(1, config.channelCount)
        let sampleCount = frameLimit.multipliedReportingOverflow(by: channelCount)
        interleavedPCM = Array(repeating: 0, count: sampleCount.overflow ? 0 : max(0, sampleCount.partialValue))
    }

    var snapshot: RuntimeCMixerCaptureSnapshot {
        let rms = capturedSampleCount > 0
            ? Float(sqrt(outputSquareSum / Double(capturedSampleCount)))
            : 0
        return RuntimeCMixerCaptureSnapshot(
            enabled: true,
            pathName: configuration.pathName,
            sampleRate: config.sampleRate,
            channelCount: config.channelCount,
            seconds: configuration.seconds,
            frameLimit: frameLimit,
            capturedFrameCount: capturedFrameCount,
            truncated: truncated,
            outputPeak: outputPeak,
            outputRMS: rms,
            overrangeSampleCount: overrangeSampleCount,
            clippingSampleCount: clippingSampleCount,
            configurationWarning: configuration.configurationWarning
        )
    }

    @discardableResult
    func capture(
        _ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) -> RuntimeCMixerSampleSummary? {
        let safeChannelCount = max(1, channelCount)
        let availableFrames = outputInterleavedPCM.count / safeChannelCount
        let requestedFrames = min(max(0, frameCount), availableFrames)
        guard requestedFrames > 0 else {
            return nil
        }
        guard !truncated,
              capturedFrameCount < frameLimit,
              !interleavedPCM.isEmpty else {
            truncated = true
            return nil
        }

        let remainingFrames = max(0, frameLimit - capturedFrameCount)
        let framesToCopy = min(requestedFrames, remainingFrames)
        let samplesToCopy = framesToCopy * safeChannelCount
        let destinationStart = capturedFrameCount * safeChannelCount
        guard samplesToCopy > 0,
              destinationStart >= 0,
              destinationStart + samplesToCopy <= interleavedPCM.count else {
            truncated = true
            return nil
        }

        var checksum = RuntimeCMixerSampleSummary.empty.checksum
        var segmentPeak = Float(0)
        var segmentSquareSum = Double(0)
        for sampleIndex in 0..<samplesToCopy {
            let sample = outputInterleavedPCM[sampleIndex].isFinite ? outputInterleavedPCM[sampleIndex] : 0
            interleavedPCM[destinationStart + sampleIndex] = sample
            checksum = RuntimeCMixerSampleSummary.hash(checksum, sample: sample)
            let absolute = abs(sample)
            segmentPeak = max(segmentPeak, absolute)
            segmentSquareSum += Double(sample) * Double(sample)
            outputPeak = max(outputPeak, absolute)
            outputSquareSum += Double(sample) * Double(sample)
            capturedSampleCount &+= 1
            if absolute > 1 {
                overrangeSampleCount &+= 1
            }
            if absolute >= 1 {
                clippingSampleCount &+= 1
            }
        }

        capturedFrameCount += framesToCopy
        if framesToCopy < requestedFrames || capturedFrameCount >= frameLimit {
            truncated = true
        }
        let rms = samplesToCopy > 0
            ? Float(sqrt(segmentSquareSum / Double(samplesToCopy)))
            : 0
        return RuntimeCMixerSampleSummary(
            frameCount: framesToCopy,
            channelCount: safeChannelCount,
            sampleCount: samplesToCopy,
            finiteSampleCount: samplesToCopy,
            checksum: checksum,
            peak: segmentPeak,
            rms: rms
        )
    }

    func blockSnapshot() -> RuntimeCMixerCaptureBlockSnapshot? {
        let sampleCount = capturedFrameCount * max(1, config.channelCount)
        guard sampleCount <= interleavedPCM.count else {
            return nil
        }
        return RuntimeCMixerCaptureBlockSnapshot(
            configuration: configuration,
            snapshot: snapshot,
            block: MixerRenderBlock(
                config: config,
                frameCount: capturedFrameCount,
                interleavedPCM: Array(interleavedPCM.prefix(sampleCount))
            )
        )
    }

    func reset() {
        capturedFrameCount = 0
        truncated = false
        outputPeak = 0
        outputSquareSum = 0
        capturedSampleCount = 0
        overrangeSampleCount = 0
        clippingSampleCount = 0
    }
}

enum RuntimeCMixerCaptureWAVWriter {
    @discardableResult
    static func write(_ capture: RuntimeCMixerCaptureBlockSnapshot) throws -> MixerWAVExportDiagnostics {
        try FileManager.default.createDirectory(
            at: capture.configuration.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try MixerWAVExporter.writePCM16WAV(from: capture.block, to: capture.configuration.url)
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
        let updatePolicy = selection.backend == .cMixer
            ? RuntimeCMixerUpdatePolicy.resolve(environment: environment)
            : nil
        let sampleRateSelection = selection.backend == .cMixer
            ? RuntimeCMixerSampleRateSelection.resolve(environment: environment)
            : nil
        let callbackDiagnostics = selection.backend == .cMixer
            ? RuntimeCMixerCallbackDiagnosticsConfiguration.resolve(environment: environment)
            : nil
        let captureConfiguration = selection.backend == .cMixer && callbackDiagnostics?.minimalCallbackMode != true
            ? RuntimeCMixerCaptureConfiguration.resolve(environment: environment)
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
                sampleRate: selectedSampleRate,
                selectedRuntimeSampleRate: sampleRateSelection?.sampleRate,
                cMixerRuntimeSampleRate: sampleRateSelection?.sampleRate,
                runtimeSampleRatePolicy: sampleRateSelection?.policy,
                runtimeSampleRateSource: sampleRateSelection?.source,
                runtimeSampleRateConfigurationWarning: sampleRateSelection?.configurationWarning,
                channelCount: selection.backend == .cMixer ? MixerRenderConfig.defaultChannelCount : 1,
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
                runtimeCaptureEnabled: selection.backend == .cMixer && captureConfiguration != nil,
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
        case .cMixer:
            return RuntimeCMixerAudioEngine(
                sampleRate: selectedSampleRate,
                outputPolicy: outputPolicy ?? .defaultPolicy,
                updatePolicy: updatePolicy ?? .defaultPolicy,
                captureConfiguration: captureConfiguration,
                callbackDiagnostics: callbackDiagnostics ?? .defaultConfiguration,
                runtimeSampleRateSelection: sampleRateSelection,
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
    let callbackDurationWarningThresholdMS: Double
    let callbackDurationMinMS: Double?
    let callbackDurationMaxMS: Double?
    let callbackDurationAverageMS: Double?
    let callbackDurationWarningCount: UInt64
    let callbackRenderQuantumDurationMS: Double?
    let callbackRenderQuantumMinMS: Double?
    let callbackRenderQuantumMaxMS: Double?
    let callbackOverRenderQuantumBudgetCount: UInt64
    let callbackIntervalMinMS: Double?
    let callbackIntervalMaxMS: Double?
    let callbackIntervalLastMS: Double?
    let callbackThreadIsMain: Bool?
    let callbackThreadID: UInt64?
    let callbackMainThreadDependencyDetected: Bool
    let callbackAllocationWarning: Bool
    let callbackLockWaitCount: UInt64
    let callbackLockWaitDurationMS: Double
    let eventQueueProducerThreadID: UInt64?
    let eventQueueProducerThreadIsMain: Bool?
    let eventQueueConsumerThreadID: UInt64?
    let eventQueueConsumerThreadIsMain: Bool?
    let runtimeMinimalCallbackMode: Bool
    let outputBufferCopyAttemptCount: UInt64
    let outputBufferCopyFailureCount: UInt64
    let outputBufferCopyLastSucceeded: Bool?
    let outputBufferCopyLayout: String?
    let outputBufferCopyRequestedFrameCount: Int?
    let outputBufferCopySourceChannelCount: Int?
    let outputBufferCopyOutputBufferCount: Int?
    let outputBufferCopyOutputChannelCount: Int?
    let outputBufferCopyCopiedFrameCount: Int?
    let outputBufferCopyCopiedSampleCount: Int?
    let outputBufferCopyExpectedSampleCount: Int?
    let outputBufferCopyFilledRequestedFrames: Bool?
    let outputBufferCopyChannelCountMatches: Bool?
    let outputBufferCopyPartialCopy: Bool?
    let outputBufferCopyScratchHash: UInt64?
    let outputBufferCopyCaptureHash: UInt64?
    let outputBufferCopyOutputHash: UInt64?
    let outputBufferCopyScratchCaptureHashMatches: Bool?
    let outputBufferCopyScratchOutputHashMatches: Bool?
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
    let outputDiscontinuityThreshold: Float
    let outputDiscontinuityCount: UInt64
    let outputDiscontinuityThresholdCounts: [RuntimeCMixerDiscontinuityThresholdCount]
    let maxOutputAdjacentSampleJump: Float
    let topOutputAdjacentSampleJumps: [RuntimeCMixerTopOutputSampleJump]
    let lastOutputDiscontinuitySampleJump: Float?
    let lastOutputDiscontinuityCallbackIndex: UInt64?
    let lastOutputDiscontinuityRuntimeFrame: UInt64?
    let lastOutputDiscontinuityFrameOffset: Int?
    let lastOutputDiscontinuityChannelIndex: Int?
    let outputPeakWarningThreshold: Float
    let outputPeakWarningSampleCount: UInt64
    let topOutputPeaks: [RuntimeCMixerTopOutputPeak]
    let overrangeSampleCount: UInt64
    let clippingSampleCount: UInt64
    let clippingDetected: Bool
    let runtimeOutputGain: Float
    let runtimeHeadroomPolicy: String
    let runtimeDefaultHeadroomDB: Double
    let runtimeGainPolicySource: String
    let runtimeGainPolicyIsEnvironmentOverride: Bool
    let runtimeAutoHeadroomEnabled: Bool
    let runtimeFixedHeadroomDB: Double?
    let runtimeGainConfigurationWarning: String?
    let runtimeClippingRecommendation: String?
    let runtimeUpdateEpsilon: Double
    let runtimeUpdateEpsilonPolicy: String
    let runtimeUpdateEpsilonConfigurationWarning: String?
    let capture: RuntimeCMixerCaptureSnapshot
    let currentFrame: UInt64
    let appliedPlannedEventCount: UInt64
    let exactFrameAppliedEventCount: UInt64
    let callbackBoundaryAppliedEventCount: UInt64
    let latePlannedEventCount: UInt64
    let maxPlannedVsAppliedDelta: Int
    let rampingOutVoiceCount: Int
    let rampDownStartCount: UInt64
    let rampDownCompletionCount: UInt64
    let abruptRampDownStopCount: UInt64
}

struct RuntimeCMixerOutputPolicy: Equatable {
    static let gainEnvironmentKey = "VTX_C_MIXER_RUNTIME_GAIN"
    static let headroomDBEnvironmentKey = "VTX_C_MIXER_RUNTIME_HEADROOM_DB"
    static let defaultHeadroomDB = -12.0
    static let clippingRecommendation = "reduce VTX_C_MIXER_RUNTIME_GAIN or set a more negative VTX_C_MIXER_RUNTIME_HEADROOM_DB"

    static let defaultPolicy = RuntimeCMixerOutputPolicy(
        outputGain: Float(pow(10.0, defaultHeadroomDB / 20.0)),
        headroomPolicy: "default_runtime_headroom_db",
        gainPolicySource: "default",
        fixedHeadroomDB: defaultHeadroomDB
    )

    let outputGain: Float
    let headroomPolicy: String
    let gainPolicySource: String
    let gainPolicyIsEnvironmentOverride: Bool
    let autoHeadroomEnabled: Bool
    let fixedHeadroomDB: Double?
    let configurationWarning: String?

    init(
        outputGain: Float,
        headroomPolicy: String,
        gainPolicySource: String,
        gainPolicyIsEnvironmentOverride: Bool = false,
        autoHeadroomEnabled: Bool = false,
        fixedHeadroomDB: Double? = nil,
        configurationWarning: String? = nil
    ) {
        self.outputGain = outputGain.isFinite && outputGain > 0 ? outputGain : Self.defaultPolicy.outputGain
        self.headroomPolicy = headroomPolicy
        self.gainPolicySource = gainPolicySource
        self.gainPolicyIsEnvironmentOverride = gainPolicyIsEnvironmentOverride
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
                headroomPolicy: "env_runtime_gain",
                gainPolicySource: "environment_override",
                gainPolicyIsEnvironmentOverride: true
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
                gainPolicySource: "environment_override",
                gainPolicyIsEnvironmentOverride: true,
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
            gainPolicySource: "default_fallback",
            gainPolicyIsEnvironmentOverride: false,
            autoHeadroomEnabled: autoHeadroomEnabled,
            fixedHeadroomDB: fixedHeadroomDB,
            configurationWarning: warning
        )
    }
}

struct RuntimeCMixerUpdatePolicy: Equatable {
    static let epsilonEnvironmentKey = "VTX_C_MIXER_RUNTIME_UPDATE_EPSILON"
    static let defaultUpdateEpsilon = 0.00001

    static let defaultPolicy = RuntimeCMixerUpdatePolicy(
        updateEpsilon: defaultUpdateEpsilon,
        updateEpsilonPolicy: "default_runtime_update_epsilon"
    )

    let updateEpsilon: Double
    let updateEpsilonPolicy: String
    let configurationWarning: String?

    init(
        updateEpsilon: Double,
        updateEpsilonPolicy: String,
        configurationWarning: String? = nil
    ) {
        self.updateEpsilon = updateEpsilon.isFinite && updateEpsilon >= 0
            ? updateEpsilon
            : Self.defaultUpdateEpsilon
        self.updateEpsilonPolicy = updateEpsilonPolicy
        self.configurationWarning = configurationWarning
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeCMixerUpdatePolicy {
        guard let rawEpsilon = trimmedEnvironmentValue(environment[epsilonEnvironmentKey]) else {
            return defaultPolicy
        }
        guard let parsedEpsilon = Double(rawEpsilon),
              parsedEpsilon.isFinite,
              parsedEpsilon >= 0,
              parsedEpsilon <= 0.01 else {
            return defaultPolicy.withWarning("invalid_runtime_update_epsilon")
        }
        return RuntimeCMixerUpdatePolicy(
            updateEpsilon: parsedEpsilon,
            updateEpsilonPolicy: "env_runtime_update_epsilon"
        )
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func withWarning(_ warning: String) -> RuntimeCMixerUpdatePolicy {
        RuntimeCMixerUpdatePolicy(
            updateEpsilon: updateEpsilon,
            updateEpsilonPolicy: "\(updateEpsilonPolicy)_fallback",
            configurationWarning: warning
        )
    }
}

private struct RuntimeCMixerOutputMetrics: Equatable {
    struct SampleJump: Equatable {
        let sampleJump: Float
        let frameOffset: Int
        let channelIndex: Int
    }

    struct Peak: Equatable {
        let peak: Float
        let frameOffset: Int
        let channelIndex: Int
    }

    let sampleCount: Int
    let peak: Float
    let squareSum: Double
    let discontinuityCount025: Int
    let discontinuityCount035: Int
    let discontinuityCount050: Int
    let discontinuityCount075: Int
    let maxAdjacentSampleJump: Float
    let topAdjacentSampleJumps: [SampleJump]
    let maxDiscontinuityFrameOffset: Int?
    let maxDiscontinuityChannelIndex: Int?
    let maxDiscontinuitySampleJump: Float?
    let peakWarningSampleCount: Int
    let topPeaks: [Peak]
    let overrangeSampleCount: Int
    let clippingSampleCount: Int

    var discontinuityCount: Int {
        discontinuityCount075
    }

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
        discontinuityCount025: 0,
        discontinuityCount035: 0,
        discontinuityCount050: 0,
        discontinuityCount075: 0,
        maxAdjacentSampleJump: 0,
        topAdjacentSampleJumps: [],
        maxDiscontinuityFrameOffset: nil,
        maxDiscontinuityChannelIndex: nil,
        maxDiscontinuitySampleJump: nil,
        peakWarningSampleCount: 0,
        topPeaks: [],
        overrangeSampleCount: 0,
        clippingSampleCount: 0
    )
}

struct RuntimeCMixerTriggerResult: Equatable {
    let succeeded: Bool
    let reason: String?
    let newVoiceIndex: Int?
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
    let replacementOldVoiceState: RuntimeCMixerReplacementVoiceState?
    let replacementRampStartState: RuntimeCMixerReplacementVoiceState?
    let replacementRampTargetGain: Float?
    let replacementNewVoiceIndex: Int?
    let replacementNewVoiceChannelTag: Int?
    let replacementGainPanAppliedBeforeRamp: Bool?
    let replacementStepAppliedBeforeRamp: Bool?
    let replacementKeyOffAppliedBeforeRamp: Bool?
    let replacementFadeoutAppliedBeforeRamp: Bool?
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
    var lastGainPanUpdateFrame: UInt64?
    var lastStepUpdateFrame: UInt64?
}

struct RuntimeCMixerReplacementVoiceState: Equatable {
    let voiceIndex: Int
    let channelTag: Int?
    let gain: Float
    let effectiveGain: Float
    let pan: Float
    let effectivePan: Float
    let sampleStep: Double
    let keyOn: Bool
    let fadeoutValue: Float
    let gainRampStart: Float?
    let gainRampTarget: Float?
    let panRampStart: Float?
    let panRampTarget: Float?

    init(voiceIndex: Int, diagnostic: CSoftwareMixerVoiceDiagnostic) {
        self.voiceIndex = voiceIndex
        channelTag = diagnostic.channelTag
        gain = diagnostic.gain
        effectiveGain = diagnostic.effectiveGain
        pan = diagnostic.pan
        effectivePan = diagnostic.effectivePan
        sampleStep = diagnostic.sampleStep
        keyOn = diagnostic.keyOn
        fadeoutValue = diagnostic.fadeoutValue
        gainRampStart = diagnostic.gainRamp?.start
        gainRampTarget = diagnostic.gainRamp?.target
        panRampStart = diagnostic.panRamp?.start
        panRampTarget = diagnostic.panRamp?.target
    }
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

fileprivate struct RuntimeCMixerQueuedAdapterEvent: Equatable {
    let event: RuntimeCMixerAdapterEvent
    let plannedRuntimeFrame: Int
    let runtimeFrame: UInt64
}

fileprivate enum RuntimeCMixerAppliedAdapterEventResult: Equatable {
    case noteTrigger(RuntimeCMixerTriggerResult)
    case gainPanUpdate(RuntimeCMixerUpdateResult)
    case stepUpdate(RuntimeCMixerUpdateResult)
    case noteCut(RuntimeCMixerPlannedCutResult)
}

fileprivate struct RuntimeCMixerSameFrameBurstDiagnostic: Equatable {
    let id: Int
    let eventOrdinal: Int
    let categories: [String]
    let affectedChannels: [Int]
    let noteTriggerCount: Int
    let replacementRampCount: Int
    let gainPanUpdateCount: Int
    let stepUpdateCount: Int
    let noteCutCount: Int
    let keyOffCount: Int
    let globalVolumeUpdateCount: Int
    let activeVoiceCountBefore: Int
    let activeVoiceCountAfter: Int
    let loadedVoiceCountBefore: Int
    let loadedVoiceCountAfter: Int
    let voicesEnteringRampDown: Int
    let voicesCompletingRampDown: Int
    let newVoicesStarted: Int
    let sustainedVoicesCarried: Int
    let atOrderStart: Bool
    let atRowTransition: Bool
}

fileprivate struct RuntimeCMixerAppliedAdapterEventDiagnostic: Equatable {
    let event: RuntimeCMixerAdapterEvent
    let context: AudioRuntimeTraceContext?
    let plannedRuntimeFrame: Int
    let appliedFrame: UInt64
    let callbackIndex: UInt64
    let callbackRequestedFrameCount: Int
    let callbackStartFrame: UInt64
    let callbackEndFrame: UInt64
    let inCallbackOffset: Int
    let eventFrameDelta: Int
    let eventApplicationTiming: String
    let sameFrameBurstSize: Int
    let sameFrameBurst: RuntimeCMixerSameFrameBurstDiagnostic?
    let adapterActiveEventIndex: Int?
    let adapterCurrentEventIndexBefore: Int?
    let adapterCurrentEventIndexAfter: Int?
    let adapterChannelAssociationRetained: Bool
    let adapterSustainedVoiceUpdate: Bool
    let result: RuntimeCMixerAppliedAdapterEventResult
}

fileprivate struct RuntimeCMixerAdapterEventScheduleConfigurationResult: Equatable {
    let queuedEventCount: Int
    let skippedNegativeRuntimeFrameCount: Int
    let skippedOverflowCount: Int
}

struct RuntimeCMixerThreadDiagnostics: Equatable {
    let threadID: UInt64
    let isMainThread: Bool

    static func current() -> RuntimeCMixerThreadDiagnostics {
        RuntimeCMixerThreadDiagnostics(
            threadID: UInt64(pthread_mach_thread_np(pthread_self())),
            isMainThread: Thread.isMainThread
        )
    }
}

final class RuntimeCMixerRenderCore: @unchecked Sendable {
    static let updateEpsilon = RuntimeCMixerUpdatePolicy.defaultUpdateEpsilon
    static let outputDiscontinuityThreshold = Float(0.75)
    static let outputPeakWarningThreshold = Float(0.95)
    static let transientDiagnosticTopCount = 8
    static let callbackDurationWarningThresholdSeconds = 0.002

    private let lock = NSLock()
    private let mixer: CSoftwareMixer
    private let captureBuffer: RuntimeCMixerCaptureBuffer?
    private let callbackDiagnostics: RuntimeCMixerCallbackDiagnosticsConfiguration
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
    private var callbackDurationMinSeconds: Double?
    private var callbackDurationMaxSeconds: Double?
    private var callbackDurationTotalSeconds = Double(0)
    private var callbackDurationSampleCount: UInt64 = 0
    private var callbackDurationWarningCount: UInt64 = 0
    private var callbackRenderQuantumLastSeconds: Double?
    private var callbackRenderQuantumMinSeconds: Double?
    private var callbackRenderQuantumMaxSeconds: Double?
    private var callbackOverRenderQuantumBudgetCount: UInt64 = 0
    private var callbackIntervalMinSeconds: Double?
    private var callbackIntervalMaxSeconds: Double?
    private var callbackIntervalLastSeconds: Double?
    private var lastCallbackStartUptimeNanos: UInt64?
    private var lastCallbackThreadDiagnostics: RuntimeCMixerThreadDiagnostics?
    private var callbackMainThreadInvocationCount: UInt64 = 0
    private var eventQueueProducerThreadDiagnostics: RuntimeCMixerThreadDiagnostics?
    private var eventQueueConsumerThreadDiagnostics: RuntimeCMixerThreadDiagnostics?
    private var lastCaptureSummary: RuntimeCMixerSampleSummary?
    private var outputBufferCopyAttemptCount: UInt64 = 0
    private var outputBufferCopyFailureCount: UInt64 = 0
    private var lastOutputBufferCopyDiagnostics: RuntimeCMixerOutputBufferCopyDiagnostics?
    private var zeroFillCount: UInt64 = 0
    private var underrunCount: UInt64 = 0
    private var silentOutputCallbackCount: UInt64 = 0
    private var unexpectedSilentOutputCount: UInt64 = 0
    private var cumulativeOutputSampleCount: UInt64 = 0
    private var cumulativeOutputSquareSum = Double(0)
    private var outputPeak = Float(0)
    private var lastOutputPeak = Float(0)
    private var lastOutputRMS = Float(0)
    private var outputDiscontinuityCount025: UInt64 = 0
    private var outputDiscontinuityCount035: UInt64 = 0
    private var outputDiscontinuityCount050: UInt64 = 0
    private var outputDiscontinuityCount: UInt64 = 0
    private var maxOutputAdjacentSampleJump = Float(0)
    private var topOutputAdjacentSampleJumps = [RuntimeCMixerTopOutputSampleJump]()
    private var lastOutputDiscontinuitySampleJump: Float?
    private var lastOutputDiscontinuityCallbackIndex: UInt64?
    private var lastOutputDiscontinuityRuntimeFrame: UInt64?
    private var lastOutputDiscontinuityFrameOffset: Int?
    private var lastOutputDiscontinuityChannelIndex: Int?
    private var outputPeakWarningSampleCount: UInt64 = 0
    private var topOutputPeaks = [RuntimeCMixerTopOutputPeak]()
    private var overrangeSampleCount: UInt64 = 0
    private var clippingSampleCount: UInt64 = 0
    private var adapterEventSchedule = [RuntimeCMixerQueuedAdapterEvent]()
    private var nextAdapterEventScheduleIndex = 0
    private var appliedAdapterEventDiagnostics = [RuntimeCMixerAppliedAdapterEventDiagnostic]()
    private var appliedPlannedEventCount: UInt64 = 0
    private var exactFrameAppliedEventCount: UInt64 = 0
    private var callbackBoundaryAppliedEventCount: UInt64 = 0
    private var latePlannedEventCount: UInt64 = 0
    private var maxPlannedVsAppliedDelta = 0

    let config: MixerRenderConfig
    let outputPolicy: RuntimeCMixerOutputPolicy
    let updatePolicy: RuntimeCMixerUpdatePolicy

    init(
        config: MixerRenderConfig = MixerRenderConfig(),
        maximumRenderFrames: Int = 16_384,
        outputPolicy: RuntimeCMixerOutputPolicy = .defaultPolicy,
        updatePolicy: RuntimeCMixerUpdatePolicy = .defaultPolicy,
        captureConfiguration: RuntimeCMixerCaptureConfiguration? = nil,
        callbackDiagnostics: RuntimeCMixerCallbackDiagnosticsConfiguration = .defaultConfiguration
    ) {
        self.config = config
        self.outputPolicy = outputPolicy
        self.updatePolicy = updatePolicy
        self.callbackDiagnostics = callbackDiagnostics
        self.maximumRenderFrames = max(1, maximumRenderFrames)
        let configuredMixer = CSoftwareMixer(config: config)
        mixer = configuredMixer
        if let captureConfiguration {
            captureBuffer = RuntimeCMixerCaptureBuffer(configuration: captureConfiguration, config: configuredMixer.config)
        } else {
            captureBuffer = nil
        }
        scratchInterleavedPCM = Array(repeating: 0, count: self.maximumRenderFrames * mixer.config.channelCount)
        topOutputAdjacentSampleJumps.reserveCapacity(Self.transientDiagnosticTopCount)
        topOutputPeaks.reserveCapacity(Self.transientDiagnosticTopCount)
    }

    @discardableResult
    fileprivate func configureAdapterEventSchedule(
        _ events: [RuntimeCMixerAdapterEvent],
        runtimeFrameOffset: Int
    ) -> RuntimeCMixerAdapterEventScheduleConfigurationResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        var queuedEvents = [RuntimeCMixerQueuedAdapterEvent]()
        queuedEvents.reserveCapacity(events.count)
        var skippedNegativeRuntimeFrameCount = 0
        var skippedOverflowCount = 0
        for event in events {
            let (plannedRuntimeFrame, overflow) = event.scheduledFrame.addingReportingOverflow(runtimeFrameOffset)
            guard !overflow else {
                skippedOverflowCount += 1
                continue
            }
            guard plannedRuntimeFrame >= 0 else {
                skippedNegativeRuntimeFrameCount += 1
                continue
            }
            queuedEvents.append(RuntimeCMixerQueuedAdapterEvent(
                event: event,
                plannedRuntimeFrame: plannedRuntimeFrame,
                runtimeFrame: UInt64(plannedRuntimeFrame)
            ))
        }

        adapterEventSchedule = queuedEvents.sorted(by: Self.adapterEventScheduleSort)
        nextAdapterEventScheduleIndex = 0
        eventQueueProducerThreadDiagnostics = RuntimeCMixerThreadDiagnostics.current()
        eventQueueConsumerThreadDiagnostics = nil
        appliedAdapterEventDiagnostics.removeAll(keepingCapacity: true)
        appliedAdapterEventDiagnostics.reserveCapacity(adapterEventSchedule.count)
        appliedPlannedEventCount = 0
        exactFrameAppliedEventCount = 0
        callbackBoundaryAppliedEventCount = 0
        latePlannedEventCount = 0
        maxPlannedVsAppliedDelta = 0
        return RuntimeCMixerAdapterEventScheduleConfigurationResult(
            queuedEventCount: adapterEventSchedule.count,
            skippedNegativeRuntimeFrameCount: skippedNegativeRuntimeFrameCount,
            skippedOverflowCount: skippedOverflowCount
        )
    }

    fileprivate func clearAdapterEventSchedule() {
        lock.lock()
        defer {
            lock.unlock()
        }
        adapterEventSchedule.removeAll(keepingCapacity: true)
        nextAdapterEventScheduleIndex = 0
        eventQueueProducerThreadDiagnostics = nil
        eventQueueConsumerThreadDiagnostics = nil
        appliedAdapterEventDiagnostics.removeAll(keepingCapacity: true)
        appliedPlannedEventCount = 0
        exactFrameAppliedEventCount = 0
        callbackBoundaryAppliedEventCount = 0
        latePlannedEventCount = 0
        maxPlannedVsAppliedDelta = 0
    }

    func configureAdapterEventScheduleForTesting(
        _ events: [RuntimeCMixerAdapterEvent],
        runtimeFrameOffset: Int
    ) {
        _ = configureAdapterEventSchedule(events, runtimeFrameOffset: runtimeFrameOffset)
    }

    fileprivate func drainAppliedAdapterEventDiagnostics() -> [RuntimeCMixerAppliedAdapterEventDiagnostic] {
        lock.lock()
        defer {
            lock.unlock()
        }
        let diagnostics = appliedAdapterEventDiagnostics
        appliedAdapterEventDiagnostics.removeAll(keepingCapacity: true)
        return diagnostics
    }

    func captureBlockSnapshotForWriting() -> RuntimeCMixerCaptureBlockSnapshot? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let capture = captureBuffer?.blockSnapshot(),
              capture.snapshot.capturedFrameCount > 0 else {
            return nil
        }
        return capture
    }

    func resetCaptureBuffer() {
        lock.lock()
        defer {
            lock.unlock()
        }
        captureBuffer?.reset()
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
                newVoiceIndex: nil,
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
                replacementOldVoiceState: replacementRampBeforeAdd.replacementOldVoiceState,
                replacementRampStartState: replacementRampBeforeAdd.replacementRampStartState,
                replacementRampTargetGain: replacementRampBeforeAdd.replacementRampTargetGain,
                replacementNewVoiceIndex: voiceIndex,
                replacementNewVoiceChannelTag: request.channel,
                replacementGainPanAppliedBeforeRamp: replacementRampBeforeAdd.replacementGainPanAppliedBeforeRamp,
                replacementStepAppliedBeforeRamp: replacementRampBeforeAdd.replacementStepAppliedBeforeRamp,
                replacementKeyOffAppliedBeforeRamp: replacementRampBeforeAdd.replacementKeyOffAppliedBeforeRamp,
                replacementFadeoutAppliedBeforeRamp: replacementRampBeforeAdd.replacementFadeoutAppliedBeforeRamp,
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
            newVoiceIndex: voiceIndex,
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
        lock.lock()
        defer {
            lock.unlock()
        }
        return triggerAdapterEventWithDiagnosticsLocked(event, eventIndex: eventIndex, mapping: mapping)
    }

    private func triggerAdapterEventWithDiagnosticsLocked(
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
            let snapshot = snapshotLocked()
            return RuntimeCMixerTriggerResult(
                succeeded: false,
                reason: invalidReason,
                newVoiceIndex: nil,
                snapshotBefore: snapshot,
                snapshotAfter: snapshot,
                channelStopBeforeAdd: nil
            )
        }

        guard mixer.currentFrame <= UInt64(Int.max) else {
            let snapshot = snapshotLocked()
            return RuntimeCMixerTriggerResult(
                succeeded: false,
                reason: "current_frame_out_of_range",
                newVoiceIndex: nil,
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
            sampleStep: event.playbackStep,
            lastGainPanUpdateFrame: nil,
            lastStepUpdateFrame: nil
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
                replacementOldVoiceState: replacementRampBeforeAdd.replacementOldVoiceState,
                replacementRampStartState: replacementRampBeforeAdd.replacementRampStartState,
                replacementRampTargetGain: replacementRampBeforeAdd.replacementRampTargetGain,
                replacementNewVoiceIndex: voiceIndex,
                replacementNewVoiceChannelTag: mapping.channelIndex,
                replacementGainPanAppliedBeforeRamp: replacementRampBeforeAdd.replacementGainPanAppliedBeforeRamp,
                replacementStepAppliedBeforeRamp: replacementRampBeforeAdd.replacementStepAppliedBeforeRamp,
                replacementKeyOffAppliedBeforeRamp: replacementRampBeforeAdd.replacementKeyOffAppliedBeforeRamp,
                replacementFadeoutAppliedBeforeRamp: replacementRampBeforeAdd.replacementFadeoutAppliedBeforeRamp,
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
            newVoiceIndex: voiceIndex,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
            updateEpsilon: updatePolicy.updateEpsilon,
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
            appliedAfterEpsilonFilter: epsilonSuppressed,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
            updateEpsilon: updatePolicy.updateEpsilon,
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
        return applyAdapterGainPanUpdateWithDiagnosticsLocked(
            channel: channel,
            activeEventIndex: activeEventIndex,
            gain: gain,
            pan: pan
        )
    }

    private func applyAdapterGainPanUpdateWithDiagnosticsLocked(
        channel: Int,
        activeEventIndex: Int,
        gain: Float?,
        pan: Float?
    ) -> RuntimeCMixerUpdateResult {

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
                updateEpsilon: updatePolicy.updateEpsilon,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
        voiceState.lastGainPanUpdateFrame = mixer.currentFrame
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
            updateEpsilon: updatePolicy.updateEpsilon,
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
        return applyAdapterStepUpdateWithDiagnosticsLocked(
            channel: channel,
            activeEventIndex: activeEventIndex,
            playbackStep: playbackStep
        )
    }

    private func applyAdapterStepUpdateWithDiagnosticsLocked(
        channel: Int,
        activeEventIndex: Int,
        playbackStep: Double
    ) -> RuntimeCMixerUpdateResult {

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
                updateEpsilon: updatePolicy.updateEpsilon,
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
                updateEpsilon: updatePolicy.updateEpsilon,
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
        voiceState.lastStepUpdateFrame = mixer.currentFrame
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
            updateEpsilon: updatePolicy.updateEpsilon,
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
        return applyAdapterNoteCutWithDiagnosticsLocked(channel: channel, activeEventIndex: activeEventIndex)
    }

    private func applyAdapterNoteCutWithDiagnosticsLocked(
        channel: Int,
        activeEventIndex: Int?
    ) -> RuntimeCMixerPlannedCutResult {

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
        let suppressedByEpsilon = delta > 0 && delta <= updatePolicy.updateEpsilon
        return RuntimeCMixerFieldUpdateDecision(
            previous: previous,
            requested: requested,
            delta: delta,
            shouldApply: delta > updatePolicy.updateEpsilon,
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

    private static func adapterEventScheduleSort(
        lhs: RuntimeCMixerQueuedAdapterEvent,
        rhs: RuntimeCMixerQueuedAdapterEvent
    ) -> Bool {
        if lhs.runtimeFrame != rhs.runtimeFrame {
            return lhs.runtimeFrame < rhs.runtimeFrame
        }
        let leftPriority = adapterEventPriority(lhs.event)
        let rightPriority = adapterEventPriority(rhs.event)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        return lhs.event.id < rhs.event.id
    }

    private static func adapterEventPriority(_ event: RuntimeCMixerAdapterEvent) -> Int {
        // Match the offline C mixer frame boundary: frame-stamped voice-state
        // events are applied before voices render at that frame, then note
        // starts become audible on the same sample.
        switch event.action {
        case .gainPanUpdate, .stepUpdate:
            return 0
        case .noteCut:
            return 1
        case .noteTrigger:
            return 2
        }
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
    func render(
        into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        callbackThread: RuntimeCMixerThreadDiagnostics? = nil
    ) -> Bool {
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
                outputMetrics: .silence,
                callbackThread: callbackThread
            )
            return true
        }
        guard safeFrameCount <= maximumRenderFrames,
              outputInterleavedPCM.count >= safeFrameCount * mixer.config.channelCount else {
            clear(outputInterleavedPCM)
            captureOutputLocked(outputInterleavedPCM, frameCount: safeFrameCount)
            recordRenderCompletionLocked(
                requestedFrameCount: safeFrameCount,
                renderedFrameCount: 0,
                callbackStartFrame: callbackStartFrame,
                callbackEndFrame: callbackStartFrame,
                succeeded: false,
                zeroFilled: true,
                activeVoiceCountBefore: activeVoiceCountBefore,
                loadedVoiceCountBefore: loadedVoiceCountBefore,
                outputMetrics: .silence,
                callbackThread: callbackThread
            )
            return false
        }
        let callbackEndFrame = callbackStartFrame.addingReportingOverflow(UInt64(safeFrameCount)).overflow
            ? UInt64.max
            : callbackStartFrame + UInt64(safeFrameCount)
        renderCallbackWithScheduledAdapterEventsLocked(
            into: outputInterleavedPCM,
            frameCount: safeFrameCount,
            callbackStartFrame: callbackStartFrame,
            callbackEndFrame: callbackEndFrame,
            callbackIndex: renderCallbackCount &+ 1,
            callbackThread: callbackThread
        )
        let sampleCount = safeFrameCount * mixer.config.channelCount
        applyOutputGain(outputInterleavedPCM, sampleCount: sampleCount)
        captureOutputLocked(outputInterleavedPCM, frameCount: safeFrameCount)
        recordRenderCompletionLocked(
            requestedFrameCount: safeFrameCount,
            renderedFrameCount: safeFrameCount,
            callbackStartFrame: callbackStartFrame,
            callbackEndFrame: mixer.currentFrame,
            succeeded: true,
            zeroFilled: false,
            activeVoiceCountBefore: activeVoiceCountBefore,
            loadedVoiceCountBefore: loadedVoiceCountBefore,
            outputMetrics: outputMetrics(
                outputInterleavedPCM,
                sampleCount: sampleCount,
                channelCount: mixer.config.channelCount
            ),
            callbackThread: callbackThread
        )
        return true
    }

    private func captureOutputLocked(_ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>, frameCount: Int) {
        lastCaptureSummary = captureBuffer?.capture(
            outputInterleavedPCM,
            frameCount: frameCount,
            channelCount: mixer.config.channelCount
        )
    }

    private func lastCaptureSummaryForOutputCopy() -> RuntimeCMixerSampleSummary? {
        guard lock.try() else {
            return nil
        }
        defer {
            lock.unlock()
        }
        return lastCaptureSummary
    }

    func recordCallbackRealtimeDiagnosticsForTesting(
        durationSeconds: Double,
        requestedFrameCount: Int,
        intervalSeconds: Double? = nil
    ) {
        lock.lock()
        defer {
            lock.unlock()
        }
        recordCallbackRealtimeDiagnosticsLocked(
            durationSeconds: durationSeconds,
            requestedFrameCount: requestedFrameCount,
            intervalSeconds: intervalSeconds
        )
    }

    private func recordCallbackRealtimeDiagnostics(
        startUptimeNanos: UInt64,
        endUptimeNanos: UInt64,
        requestedFrameCount: Int
    ) {
        guard lock.try() else {
            return
        }
        defer {
            lock.unlock()
        }
        let durationSeconds = seconds(fromNanoseconds: endUptimeNanos &- startUptimeNanos)
        let intervalSeconds = lastCallbackStartUptimeNanos.map { seconds(fromNanoseconds: startUptimeNanos &- $0) }
        lastCallbackStartUptimeNanos = startUptimeNanos
        recordCallbackRealtimeDiagnosticsLocked(
            durationSeconds: durationSeconds,
            requestedFrameCount: requestedFrameCount,
            intervalSeconds: intervalSeconds
        )
    }

    private func recordCallbackRealtimeDiagnosticsLocked(
        durationSeconds: Double,
        requestedFrameCount: Int,
        intervalSeconds: Double?
    ) {
        guard durationSeconds.isFinite,
              durationSeconds >= 0 else {
            return
        }
        callbackDurationMinSeconds = callbackDurationMinSeconds.map { min($0, durationSeconds) } ?? durationSeconds
        callbackDurationMaxSeconds = callbackDurationMaxSeconds.map { max($0, durationSeconds) } ?? durationSeconds
        callbackDurationTotalSeconds += durationSeconds
        callbackDurationSampleCount &+= 1
        if durationSeconds > Self.callbackDurationWarningThresholdSeconds {
            callbackDurationWarningCount &+= 1
        }

        let quantumSeconds = renderQuantumDurationSeconds(frameCount: requestedFrameCount)
        callbackRenderQuantumLastSeconds = quantumSeconds
        callbackRenderQuantumMinSeconds = callbackRenderQuantumMinSeconds.map { min($0, quantumSeconds) } ?? quantumSeconds
        callbackRenderQuantumMaxSeconds = callbackRenderQuantumMaxSeconds.map { max($0, quantumSeconds) } ?? quantumSeconds
        if durationSeconds > quantumSeconds {
            callbackOverRenderQuantumBudgetCount &+= 1
        }

        if let intervalSeconds,
           intervalSeconds.isFinite,
           intervalSeconds >= 0 {
            callbackIntervalLastSeconds = intervalSeconds
            callbackIntervalMinSeconds = callbackIntervalMinSeconds.map { min($0, intervalSeconds) } ?? intervalSeconds
            callbackIntervalMaxSeconds = callbackIntervalMaxSeconds.map { max($0, intervalSeconds) } ?? intervalSeconds
        }
    }

    private func recordOutputBufferCopyDiagnostics(_ diagnostics: RuntimeCMixerOutputBufferCopyDiagnostics) {
        guard lock.try() else {
            return
        }
        defer {
            lock.unlock()
        }
        outputBufferCopyAttemptCount &+= 1
        if !diagnostics.succeeded {
            outputBufferCopyFailureCount &+= 1
        }
        lastOutputBufferCopyDiagnostics = diagnostics
    }

    private func renderQuantumDurationSeconds(frameCount: Int) -> Double {
        guard mixer.config.sampleRate.isFinite,
              mixer.config.sampleRate > 0 else {
            return 0
        }
        return Double(max(0, frameCount)) / mixer.config.sampleRate
    }

    private func seconds(fromNanoseconds nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000_000.0
    }

    private func milliseconds(_ seconds: Double) -> Double {
        seconds * 1_000.0
    }

    private func renderCallbackWithScheduledAdapterEventsLocked(
        into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        callbackStartFrame: UInt64,
        callbackEndFrame: UInt64,
        callbackIndex: UInt64,
        callbackThread: RuntimeCMixerThreadDiagnostics?
    ) {
        var renderedFrames = 0
        while nextAdapterEventScheduleIndex < adapterEventSchedule.count {
            let nextEvent = adapterEventSchedule[nextAdapterEventScheduleIndex]
            guard nextEvent.runtimeFrame < callbackEndFrame else {
                break
            }

            let eventOffset = nextEvent.runtimeFrame <= callbackStartFrame
                ? 0
                : Int(nextEvent.runtimeFrame - callbackStartFrame)
            let framesBeforeEvent = max(0, eventOffset - renderedFrames)
            renderSubrangeLocked(
                into: outputInterleavedPCM,
                startFrameOffset: renderedFrames,
                frameCount: framesBeforeEvent
            )
            renderedFrames += framesBeforeEvent

            let burstFrame = nextEvent.runtimeFrame
            let burstStartIndex = nextAdapterEventScheduleIndex
            var burstEndIndex = burstStartIndex
            while burstEndIndex < adapterEventSchedule.count,
                  adapterEventSchedule[burstEndIndex].runtimeFrame == burstFrame {
                burstEndIndex += 1
            }
            let sameFrameBurstSize = burstEndIndex - burstStartIndex
            let burstSnapshotBefore = snapshotLocked()
            let burstAssociationBefore = adapterEventIndexByChannel
            let rampDownStartCountBefore = mixer.rampDownStartCount
            let rampDownCompletionCountBefore = mixer.rampDownCompletionCount
            var burstDiagnostics = [RuntimeCMixerAppliedAdapterEventDiagnostic]()
            burstDiagnostics.reserveCapacity(sameFrameBurstSize)
            if let callbackThread {
                eventQueueConsumerThreadDiagnostics = callbackThread
            }
            for eventIndex in burstStartIndex..<burstEndIndex {
                burstDiagnostics.append(applyQueuedAdapterEventLocked(
                    adapterEventSchedule[eventIndex],
                    callbackIndex: callbackIndex,
                    callbackRequestedFrameCount: frameCount,
                    callbackStartFrame: callbackStartFrame,
                    callbackEndFrame: callbackEndFrame,
                    sameFrameBurstSize: sameFrameBurstSize
                ))
            }
            let burstSnapshotAfter = snapshotLocked()
            let burstAssociationAfter = adapterEventIndexByChannel
            appendBurstDiagnosticsLocked(
                burstDiagnostics,
                burstID: burstFrame <= UInt64(Int.max) ? Int(burstFrame) : Int.max,
                burstEvents: Array(adapterEventSchedule[burstStartIndex..<burstEndIndex].map(\.event)),
                snapshotBefore: burstSnapshotBefore,
                snapshotAfter: burstSnapshotAfter,
                associationBefore: burstAssociationBefore,
                associationAfter: burstAssociationAfter,
                rampDownStartCountBefore: rampDownStartCountBefore,
                rampDownCompletionCountBefore: rampDownCompletionCountBefore
            )
            nextAdapterEventScheduleIndex = burstEndIndex
        }

        renderSubrangeLocked(
            into: outputInterleavedPCM,
            startFrameOffset: renderedFrames,
            frameCount: max(0, frameCount - renderedFrames)
        )
    }

    private func renderSubrangeLocked(
        into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        startFrameOffset: Int,
        frameCount: Int
    ) {
        let safeFrameCount = max(0, frameCount)
        guard safeFrameCount > 0 else {
            return
        }
        let channelCount = mixer.config.channelCount
        let sampleOffset = max(0, startFrameOffset) * channelCount
        let sampleCount = safeFrameCount * channelCount
        guard let baseAddress = outputInterleavedPCM.baseAddress,
              sampleOffset >= 0,
              sampleOffset + sampleCount <= outputInterleavedPCM.count else {
            return
        }
        _ = mixer.render(
            into: UnsafeMutableBufferPointer(
                start: baseAddress.advanced(by: sampleOffset),
                count: sampleCount
            ),
            frames: safeFrameCount
        )
    }

    private func appendBurstDiagnosticsLocked(
        _ diagnostics: [RuntimeCMixerAppliedAdapterEventDiagnostic],
        burstID: Int,
        burstEvents: [RuntimeCMixerAdapterEvent],
        snapshotBefore: RuntimeCMixerRenderSnapshot,
        snapshotAfter: RuntimeCMixerRenderSnapshot,
        associationBefore: [Int: Int],
        associationAfter: [Int: Int],
        rampDownStartCountBefore: UInt64,
        rampDownCompletionCountBefore: UInt64
    ) {
        guard !diagnostics.isEmpty else {
            return
        }
        let replacementRampCount = diagnostics.filter { diagnostic in
            if case let .noteTrigger(result) = diagnostic.result {
                return result.channelStopBeforeAdd?.rampedVoiceCount ?? 0 > 0
            }
            return false
        }.count
        let rampDownStartDelta = Self.uint64Delta(snapshotAfter.rampDownStartCount, rampDownStartCountBefore)
        let voicesEnteringRampDownFromResults = diagnostics.reduce(0) { total, diagnostic in
            if case let .noteTrigger(result) = diagnostic.result {
                return total + (result.channelStopBeforeAdd?.rampedVoiceCount ?? 0)
            }
            return total
        }
        let voicesEnteringRampDown = max(voicesEnteringRampDownFromResults, rampDownStartDelta)
        let newVoicesStarted = diagnostics.filter { diagnostic in
            if case let .noteTrigger(result) = diagnostic.result {
                return result.succeeded
            }
            return false
        }.count
        let sustainedVoicesCarried = associationBefore.filter { channel, eventIndex in
            associationAfter[channel] == eventIndex
        }.count
        let burst = RuntimeCMixerSameFrameBurstDiagnostic(
            id: burstID,
            eventOrdinal: 0,
            categories: sameFrameBurstCategories(from: burstEvents, replacementRampCount: replacementRampCount),
            affectedChannels: Array(Set(burstEvents.map(\.channelIndex))).sorted(),
            noteTriggerCount: burstEvents.filter { event in
                if case .noteTrigger = event.action { return true }
                return false
            }.count,
            replacementRampCount: replacementRampCount,
            gainPanUpdateCount: burstEvents.filter { event in
                if case .gainPanUpdate = event.action { return true }
                return false
            }.count,
            stepUpdateCount: burstEvents.filter { event in
                if case .stepUpdate = event.action { return true }
                return false
            }.count,
            noteCutCount: burstEvents.filter { event in
                if case .noteCut = event.action { return true }
                return false
            }.count,
            keyOffCount: burstEvents.filter { $0.categories.contains("key_off") }.count,
            globalVolumeUpdateCount: burstEvents.filter { $0.categories.contains("hxy_global_volume_update") }.count,
            activeVoiceCountBefore: snapshotBefore.activeVoiceCount,
            activeVoiceCountAfter: snapshotAfter.activeVoiceCount,
            loadedVoiceCountBefore: snapshotBefore.loadedVoiceCount,
            loadedVoiceCountAfter: snapshotAfter.loadedVoiceCount,
            voicesEnteringRampDown: voicesEnteringRampDown,
            voicesCompletingRampDown: Self.uint64Delta(snapshotAfter.rampDownCompletionCount, rampDownCompletionCountBefore),
            newVoicesStarted: newVoicesStarted,
            sustainedVoicesCarried: sustainedVoicesCarried,
            atOrderStart: burstEvents.contains { $0.source.rowIndex == 0 && $0.syntheticTick == 0 },
            atRowTransition: burstEvents.contains { $0.syntheticTick == 0 }
        )
        let voicesCompletingRampDown = Self.uint64Delta(snapshotAfter.rampDownCompletionCount, rampDownCompletionCountBefore)
        for (index, diagnostic) in diagnostics.enumerated() {
            appliedAdapterEventDiagnostics.append(RuntimeCMixerAppliedAdapterEventDiagnostic(
                event: diagnostic.event,
                context: diagnostic.context,
                plannedRuntimeFrame: diagnostic.plannedRuntimeFrame,
                appliedFrame: diagnostic.appliedFrame,
                callbackIndex: diagnostic.callbackIndex,
                callbackRequestedFrameCount: diagnostic.callbackRequestedFrameCount,
                callbackStartFrame: diagnostic.callbackStartFrame,
                callbackEndFrame: diagnostic.callbackEndFrame,
                inCallbackOffset: diagnostic.inCallbackOffset,
                eventFrameDelta: diagnostic.eventFrameDelta,
                eventApplicationTiming: diagnostic.eventApplicationTiming,
                sameFrameBurstSize: diagnostic.sameFrameBurstSize,
                sameFrameBurst: RuntimeCMixerSameFrameBurstDiagnostic(
                    id: burst.id,
                    eventOrdinal: index + 1,
                    categories: burst.categories,
                    affectedChannels: burst.affectedChannels,
                    noteTriggerCount: burst.noteTriggerCount,
                    replacementRampCount: burst.replacementRampCount,
                    gainPanUpdateCount: burst.gainPanUpdateCount,
                    stepUpdateCount: burst.stepUpdateCount,
                    noteCutCount: burst.noteCutCount,
                    keyOffCount: burst.keyOffCount,
                    globalVolumeUpdateCount: burst.globalVolumeUpdateCount,
                    activeVoiceCountBefore: burst.activeVoiceCountBefore,
                    activeVoiceCountAfter: burst.activeVoiceCountAfter,
                    loadedVoiceCountBefore: burst.loadedVoiceCountBefore,
                    loadedVoiceCountAfter: burst.loadedVoiceCountAfter,
                    voicesEnteringRampDown: burst.voicesEnteringRampDown,
                    voicesCompletingRampDown: voicesCompletingRampDown,
                    newVoicesStarted: burst.newVoicesStarted,
                    sustainedVoicesCarried: burst.sustainedVoicesCarried,
                    atOrderStart: burst.atOrderStart,
                    atRowTransition: burst.atRowTransition
                ),
                adapterActiveEventIndex: diagnostic.adapterActiveEventIndex,
                adapterCurrentEventIndexBefore: diagnostic.adapterCurrentEventIndexBefore,
                adapterCurrentEventIndexAfter: diagnostic.adapterCurrentEventIndexAfter,
                adapterChannelAssociationRetained: diagnostic.adapterChannelAssociationRetained,
                adapterSustainedVoiceUpdate: diagnostic.adapterSustainedVoiceUpdate,
                result: diagnostic.result
            ))
        }
    }

    private func sameFrameBurstCategories(
        from events: [RuntimeCMixerAdapterEvent],
        replacementRampCount: Int
    ) -> [String] {
        var categories = Set(events.flatMap(\.categories).map(Self.normalizedBurstCategory))
        if replacementRampCount > 0 {
            categories.insert("replacement_stop_ramp")
        }
        return categories.sorted()
    }

    private static func normalizedBurstCategory(_ category: String) -> String {
        switch category {
        case "step_pitch_update":
            return "step_update"
        case "hxy_global_volume", "hxy_global_volume_update":
            return "global_volume_update"
        case "key_off":
            return "key_off_fadeout"
        case "replacement":
            return "replacement_stop_ramp"
        default:
            return category
        }
    }

    private static func uint64Delta(_ current: UInt64, _ previous: UInt64) -> Int {
        Int(min(current &- previous, UInt64(Int.max)))
    }

    private func applyQueuedAdapterEventLocked(
        _ queuedEvent: RuntimeCMixerQueuedAdapterEvent,
        callbackIndex: UInt64,
        callbackRequestedFrameCount: Int,
        callbackStartFrame: UInt64,
        callbackEndFrame: UInt64,
        sameFrameBurstSize: Int
    ) -> RuntimeCMixerAppliedAdapterEventDiagnostic {
        let appliedFrame = mixer.currentFrame
        let appliedFrameInt = appliedFrame <= UInt64(Int.max) ? Int(appliedFrame) : Int.max
        let eventFrameDelta = appliedFrameInt - queuedEvent.plannedRuntimeFrame
        let inCallbackOffset = appliedFrame >= callbackStartFrame
            ? Int(min(UInt64(Int.max), appliedFrame - callbackStartFrame))
            : 0
        let timing: String
        if queuedEvent.runtimeFrame < callbackStartFrame {
            timing = "late"
            latePlannedEventCount &+= 1
        } else if eventFrameDelta == 0 {
            timing = "exact_frame"
            exactFrameAppliedEventCount &+= 1
        } else if appliedFrame == callbackStartFrame {
            timing = "callback_start"
            callbackBoundaryAppliedEventCount &+= 1
        } else {
            timing = "unknown"
        }
        appliedPlannedEventCount &+= 1
        maxPlannedVsAppliedDelta = max(maxPlannedVsAppliedDelta, abs(eventFrameDelta))

        let adapterCurrentEventIndexBefore = adapterEventIndexByChannel[queuedEvent.event.channelIndex]
        let adapterActiveEventIndex = queuedEvent.event.activeEventIndex
        let result: RuntimeCMixerAppliedAdapterEventResult
        switch queuedEvent.event.action {
        case let .noteTrigger(eventIndex, syntheticEvent, mapping):
            result = .noteTrigger(triggerAdapterEventWithDiagnosticsLocked(
                syntheticEvent,
                eventIndex: eventIndex,
                mapping: mapping
            ))
        case let .gainPanUpdate(activeEventIndex, gain, pan):
            result = .gainPanUpdate(applyAdapterGainPanUpdateWithDiagnosticsLocked(
                channel: queuedEvent.event.channelIndex,
                activeEventIndex: activeEventIndex,
                gain: gain,
                pan: pan
            ))
        case let .stepUpdate(activeEventIndex, playbackStep):
            result = .stepUpdate(applyAdapterStepUpdateWithDiagnosticsLocked(
                channel: queuedEvent.event.channelIndex,
                activeEventIndex: activeEventIndex,
                playbackStep: playbackStep
            ))
        case let .noteCut(activeEventIndex):
            result = .noteCut(applyAdapterNoteCutWithDiagnosticsLocked(
                channel: queuedEvent.event.channelIndex,
                activeEventIndex: activeEventIndex
            ))
        }
        let adapterCurrentEventIndexAfter = adapterEventIndexByChannel[queuedEvent.event.channelIndex]
        let associationRetained = adapterCurrentEventIndexBefore != nil &&
            adapterCurrentEventIndexBefore == adapterCurrentEventIndexAfter
        let sustainedVoiceUpdate: Bool
        switch queuedEvent.event.action {
        case .gainPanUpdate, .stepUpdate, .noteCut:
            sustainedVoiceUpdate = adapterActiveEventIndex != nil &&
                adapterActiveEventIndex == adapterCurrentEventIndexBefore
        case .noteTrigger:
            sustainedVoiceUpdate = false
        }

        return RuntimeCMixerAppliedAdapterEventDiagnostic(
            event: queuedEvent.event,
            context: runtimeTraceContext(for: queuedEvent.event),
            plannedRuntimeFrame: queuedEvent.plannedRuntimeFrame,
            appliedFrame: appliedFrame,
            callbackIndex: callbackIndex,
            callbackRequestedFrameCount: callbackRequestedFrameCount,
            callbackStartFrame: callbackStartFrame,
            callbackEndFrame: callbackEndFrame,
            inCallbackOffset: inCallbackOffset,
            eventFrameDelta: eventFrameDelta,
            eventApplicationTiming: timing,
            sameFrameBurstSize: sameFrameBurstSize,
            sameFrameBurst: nil,
            adapterActiveEventIndex: adapterActiveEventIndex,
            adapterCurrentEventIndexBefore: adapterCurrentEventIndexBefore,
            adapterCurrentEventIndexAfter: adapterCurrentEventIndexAfter,
            adapterChannelAssociationRetained: associationRetained,
            adapterSustainedVoiceUpdate: sustainedVoiceUpdate,
            result: result
        )
    }

    func render(frameCount: AVAudioFrameCount, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let safeFrameCount = Int(frameCount)
        let callbackThread = RuntimeCMixerThreadDiagnostics.current()
        let callbackStartNanos = DispatchTime.now().uptimeNanoseconds
        defer {
            recordCallbackRealtimeDiagnostics(
                startUptimeNanos: callbackStartNanos,
                endUptimeNanos: DispatchTime.now().uptimeNanoseconds,
                requestedFrameCount: safeFrameCount
            )
        }

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
                frameCount: safeFrameCount,
                callbackThread: callbackThread
            )
        }
        if rendered {
            let copyDiagnostics = copyScratchToAudioBuffers(ioData: ioData, frameCount: safeFrameCount)
            recordOutputBufferCopyDiagnostics(copyDiagnostics)
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
        adapterEventSchedule.removeAll(keepingCapacity: true)
        nextAdapterEventScheduleIndex = 0
        eventQueueProducerThreadDiagnostics = nil
        eventQueueConsumerThreadDiagnostics = nil
        appliedAdapterEventDiagnostics.removeAll(keepingCapacity: true)
        lastCaptureSummary = nil
        lastOutputBufferCopyDiagnostics = nil
        appliedPlannedEventCount = 0
        exactFrameAppliedEventCount = 0
        callbackBoundaryAppliedEventCount = 0
        latePlannedEventCount = 0
        maxPlannedVsAppliedDelta = 0
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
        let currentFrame = mixer.currentFrame
        let adapterVoiceState = adapterEventIndexByChannel[channel].flatMap { adapterVoiceStateByEventIndex[$0] }
        let fallbackVoiceIndex = voiceStateByChannel[channel]?.voiceIndex
        let replacementOldVoiceIndex = adapterVoiceState?.voiceIndex ?? fallbackVoiceIndex
        let replacementOldVoiceState = replacementOldVoiceIndex
            .flatMap { replacementVoiceState(voiceIndex: $0) }
        let sameFrameGainPanUpdate = adapterVoiceState?.lastGainPanUpdateFrame == currentFrame
        let sameFrameStepUpdate = adapterVoiceState?.lastStepUpdateFrame == currentFrame
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
        let replacementRampStartState = rampedVoiceCount > 0
            ? replacementOldVoiceIndex.flatMap { replacementVoiceState(voiceIndex: $0) }
            : nil
        let replacementGainPanAppliedBeforeRamp = replacementGainPanAppliedBeforeRamp(
            expected: adapterVoiceState,
            rampStartState: replacementRampStartState,
            sameFrameGainPanUpdate: sameFrameGainPanUpdate
        )
        let replacementStepAppliedBeforeRamp = replacementStepAppliedBeforeRamp(
            expected: adapterVoiceState,
            rampStartState: replacementRampStartState,
            sameFrameStepUpdate: sameFrameStepUpdate
        )
        return RuntimeCMixerChannelStopResult(
            channel: channel,
            stoppedVoiceCount: 0,
            rampedVoiceCount: rampedVoiceCount,
            replacementRampFrames: CSoftwareMixer.replacementStopRampFrameCount,
            replacementVoicesOverlap: false,
            replacementOldVoiceState: replacementOldVoiceState,
            replacementRampStartState: replacementRampStartState,
            replacementRampTargetGain: replacementRampStartState?.gainRampTarget,
            replacementNewVoiceIndex: nil,
            replacementNewVoiceChannelTag: nil,
            replacementGainPanAppliedBeforeRamp: replacementGainPanAppliedBeforeRamp,
            replacementStepAppliedBeforeRamp: replacementStepAppliedBeforeRamp,
            replacementKeyOffAppliedBeforeRamp: replacementRampStartState.map { !$0.keyOn },
            replacementFadeoutAppliedBeforeRamp: replacementRampStartState.map { $0.fadeoutValue < 0.999_999 },
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            reason: reason
        )
    }

    private func replacementVoiceState(voiceIndex: Int) -> RuntimeCMixerReplacementVoiceState? {
        mixer.voiceDiagnostic(forVoiceAt: voiceIndex).map {
            RuntimeCMixerReplacementVoiceState(voiceIndex: voiceIndex, diagnostic: $0)
        }
    }

    private func replacementGainPanAppliedBeforeRamp(
        expected: RuntimeCMixerAdapterVoiceState?,
        rampStartState: RuntimeCMixerReplacementVoiceState?,
        sameFrameGainPanUpdate: Bool
    ) -> Bool? {
        guard sameFrameGainPanUpdate,
              let expected,
              let rampStartState else {
            return nil
        }
        let rampStartGain = rampStartState.gainRampStart ?? rampStartState.effectiveGain
        return Self.approximatelyEqual(rampStartGain, expected.gain) &&
            Self.approximatelyEqual(rampStartState.pan, expected.pan)
    }

    private func replacementStepAppliedBeforeRamp(
        expected: RuntimeCMixerAdapterVoiceState?,
        rampStartState: RuntimeCMixerReplacementVoiceState?,
        sameFrameStepUpdate: Bool
    ) -> Bool? {
        guard sameFrameStepUpdate,
              let expected,
              let rampStartState else {
            return nil
        }
        return Self.approximatelyEqual(rampStartState.sampleStep, expected.sampleStep)
    }

    private static func approximatelyEqual(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.000_001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.000_001) -> Bool {
        abs(lhs - rhs) <= tolerance
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
            replacementOldVoiceState: nil,
            replacementRampStartState: nil,
            replacementRampTargetGain: nil,
            replacementNewVoiceIndex: nil,
            replacementNewVoiceChannelTag: nil,
            replacementGainPanAppliedBeforeRamp: nil,
            replacementStepAppliedBeforeRamp: nil,
            replacementKeyOffAppliedBeforeRamp: nil,
            replacementFadeoutAppliedBeforeRamp: nil,
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
            eventQueueBacklogCount: max(0, adapterEventSchedule.count - nextAdapterEventScheduleIndex),
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
            callbackDurationWarningThresholdMS: milliseconds(Self.callbackDurationWarningThresholdSeconds),
            callbackDurationMinMS: callbackDurationMinSeconds.map(milliseconds),
            callbackDurationMaxMS: callbackDurationMaxSeconds.map(milliseconds),
            callbackDurationAverageMS: callbackDurationSampleCount > 0
                ? milliseconds(callbackDurationTotalSeconds / Double(callbackDurationSampleCount))
                : nil,
            callbackDurationWarningCount: callbackDurationWarningCount,
            callbackRenderQuantumDurationMS: callbackRenderQuantumLastSeconds.map(milliseconds),
            callbackRenderQuantumMinMS: callbackRenderQuantumMinSeconds.map(milliseconds),
            callbackRenderQuantumMaxMS: callbackRenderQuantumMaxSeconds.map(milliseconds),
            callbackOverRenderQuantumBudgetCount: callbackOverRenderQuantumBudgetCount,
            callbackIntervalMinMS: callbackIntervalMinSeconds.map(milliseconds),
            callbackIntervalMaxMS: callbackIntervalMaxSeconds.map(milliseconds),
            callbackIntervalLastMS: callbackIntervalLastSeconds.map(milliseconds),
            callbackThreadIsMain: lastCallbackThreadDiagnostics?.isMainThread,
            callbackThreadID: lastCallbackThreadDiagnostics?.threadID,
            callbackMainThreadDependencyDetected: callbackMainThreadInvocationCount > 0,
            callbackAllocationWarning: true,
            callbackLockWaitCount: 0,
            callbackLockWaitDurationMS: 0,
            eventQueueProducerThreadID: eventQueueProducerThreadDiagnostics?.threadID,
            eventQueueProducerThreadIsMain: eventQueueProducerThreadDiagnostics?.isMainThread,
            eventQueueConsumerThreadID: eventQueueConsumerThreadDiagnostics?.threadID,
            eventQueueConsumerThreadIsMain: eventQueueConsumerThreadDiagnostics?.isMainThread,
            runtimeMinimalCallbackMode: callbackDiagnostics.minimalCallbackMode,
            outputBufferCopyAttemptCount: outputBufferCopyAttemptCount,
            outputBufferCopyFailureCount: outputBufferCopyFailureCount,
            outputBufferCopyLastSucceeded: lastOutputBufferCopyDiagnostics?.succeeded,
            outputBufferCopyLayout: lastOutputBufferCopyDiagnostics?.layout,
            outputBufferCopyRequestedFrameCount: lastOutputBufferCopyDiagnostics?.requestedFrameCount,
            outputBufferCopySourceChannelCount: lastOutputBufferCopyDiagnostics?.sourceChannelCount,
            outputBufferCopyOutputBufferCount: lastOutputBufferCopyDiagnostics?.outputBufferCount,
            outputBufferCopyOutputChannelCount: lastOutputBufferCopyDiagnostics?.outputChannelCount,
            outputBufferCopyCopiedFrameCount: lastOutputBufferCopyDiagnostics?.copiedFrameCount,
            outputBufferCopyCopiedSampleCount: lastOutputBufferCopyDiagnostics?.copiedSampleCount,
            outputBufferCopyExpectedSampleCount: lastOutputBufferCopyDiagnostics?.expectedSampleCount,
            outputBufferCopyFilledRequestedFrames: lastOutputBufferCopyDiagnostics?.filledRequestedFrames,
            outputBufferCopyChannelCountMatches: lastOutputBufferCopyDiagnostics?.channelCountMatches,
            outputBufferCopyPartialCopy: lastOutputBufferCopyDiagnostics?.partialCopy,
            outputBufferCopyScratchHash: lastOutputBufferCopyDiagnostics?.scratchSummary?.checksum,
            outputBufferCopyCaptureHash: lastOutputBufferCopyDiagnostics?.captureSummary?.checksum,
            outputBufferCopyOutputHash: lastOutputBufferCopyDiagnostics?.outputSummary?.checksum,
            outputBufferCopyScratchCaptureHashMatches: lastOutputBufferCopyDiagnostics?.scratchCaptureHashMatches,
            outputBufferCopyScratchOutputHashMatches: lastOutputBufferCopyDiagnostics?.scratchOutputHashMatches,
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
            outputDiscontinuityThreshold: Self.outputDiscontinuityThreshold,
            outputDiscontinuityCount: outputDiscontinuityCount,
            outputDiscontinuityThresholdCounts: outputDiscontinuityThresholdCountsLocked(),
            maxOutputAdjacentSampleJump: maxOutputAdjacentSampleJump,
            topOutputAdjacentSampleJumps: topOutputAdjacentSampleJumps,
            lastOutputDiscontinuitySampleJump: lastOutputDiscontinuitySampleJump,
            lastOutputDiscontinuityCallbackIndex: lastOutputDiscontinuityCallbackIndex,
            lastOutputDiscontinuityRuntimeFrame: lastOutputDiscontinuityRuntimeFrame,
            lastOutputDiscontinuityFrameOffset: lastOutputDiscontinuityFrameOffset,
            lastOutputDiscontinuityChannelIndex: lastOutputDiscontinuityChannelIndex,
            outputPeakWarningThreshold: Self.outputPeakWarningThreshold,
            outputPeakWarningSampleCount: outputPeakWarningSampleCount,
            topOutputPeaks: topOutputPeaks,
            overrangeSampleCount: overrangeSampleCount,
            clippingSampleCount: clippingSampleCount,
            clippingDetected: clippingSampleCount > 0,
            runtimeOutputGain: outputPolicy.outputGain,
            runtimeHeadroomPolicy: outputPolicy.headroomPolicy,
            runtimeDefaultHeadroomDB: RuntimeCMixerOutputPolicy.defaultHeadroomDB,
            runtimeGainPolicySource: outputPolicy.gainPolicySource,
            runtimeGainPolicyIsEnvironmentOverride: outputPolicy.gainPolicyIsEnvironmentOverride,
            runtimeAutoHeadroomEnabled: outputPolicy.autoHeadroomEnabled,
            runtimeFixedHeadroomDB: outputPolicy.fixedHeadroomDB,
            runtimeGainConfigurationWarning: outputPolicy.configurationWarning,
            runtimeClippingRecommendation: clippingSampleCount > 0 ? RuntimeCMixerOutputPolicy.clippingRecommendation : nil,
            runtimeUpdateEpsilon: updatePolicy.updateEpsilon,
            runtimeUpdateEpsilonPolicy: updatePolicy.updateEpsilonPolicy,
            runtimeUpdateEpsilonConfigurationWarning: updatePolicy.configurationWarning,
            capture: captureBuffer?.snapshot ?? .disabled,
            currentFrame: mixer.currentFrame,
            appliedPlannedEventCount: appliedPlannedEventCount,
            exactFrameAppliedEventCount: exactFrameAppliedEventCount,
            callbackBoundaryAppliedEventCount: callbackBoundaryAppliedEventCount,
            latePlannedEventCount: latePlannedEventCount,
            maxPlannedVsAppliedDelta: maxPlannedVsAppliedDelta,
            rampingOutVoiceCount: mixer.rampingOutVoiceCount,
            rampDownStartCount: mixer.rampDownStartCount,
            rampDownCompletionCount: mixer.rampDownCompletionCount,
            abruptRampDownStopCount: mixer.abruptRampDownStopCount
        )
    }

    private func outputDiscontinuityThresholdCountsLocked() -> [RuntimeCMixerDiscontinuityThresholdCount] {
        [
            RuntimeCMixerDiscontinuityThresholdCount(threshold: 0.25, count: outputDiscontinuityCount025),
            RuntimeCMixerDiscontinuityThresholdCount(threshold: 0.35, count: outputDiscontinuityCount035),
            RuntimeCMixerDiscontinuityThresholdCount(threshold: 0.50, count: outputDiscontinuityCount050),
            RuntimeCMixerDiscontinuityThresholdCount(threshold: Self.outputDiscontinuityThreshold, count: outputDiscontinuityCount)
        ]
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
        outputMetrics: RuntimeCMixerOutputMetrics,
        callbackThread: RuntimeCMixerThreadDiagnostics? = nil
    ) {
        let callbackIndex = renderCallbackCount &+ 1
        renderCallbackCount &+= 1
        if let callbackThread {
            lastCallbackThreadDiagnostics = callbackThread
            if callbackThread.isMainThread {
                callbackMainThreadInvocationCount &+= 1
            }
        }
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
            outputDiscontinuityCount025 &+= UInt64(max(0, outputMetrics.discontinuityCount025))
            outputDiscontinuityCount035 &+= UInt64(max(0, outputMetrics.discontinuityCount035))
            outputDiscontinuityCount050 &+= UInt64(max(0, outputMetrics.discontinuityCount050))
            outputDiscontinuityCount &+= UInt64(max(0, outputMetrics.discontinuityCount))
            maxOutputAdjacentSampleJump = max(maxOutputAdjacentSampleJump, outputMetrics.maxAdjacentSampleJump)
            recordTopOutputAdjacentSampleJumpsLocked(
                outputMetrics.topAdjacentSampleJumps,
                callbackStartFrame: callbackStartFrame,
                callbackIndex: callbackIndex
            )
            if let discontinuityFrameOffset = outputMetrics.maxDiscontinuityFrameOffset,
               let discontinuitySampleJump = outputMetrics.maxDiscontinuitySampleJump {
                lastOutputDiscontinuitySampleJump = discontinuitySampleJump
                lastOutputDiscontinuityCallbackIndex = callbackIndex
                lastOutputDiscontinuityFrameOffset = discontinuityFrameOffset
                lastOutputDiscontinuityChannelIndex = outputMetrics.maxDiscontinuityChannelIndex
                let runtimeFrame = callbackStartFrame.addingReportingOverflow(UInt64(discontinuityFrameOffset))
                lastOutputDiscontinuityRuntimeFrame = runtimeFrame.overflow ? UInt64.max : runtimeFrame.partialValue
            }
            outputPeakWarningSampleCount &+= UInt64(max(0, outputMetrics.peakWarningSampleCount))
            recordTopOutputPeaksLocked(
                outputMetrics.topPeaks,
                callbackStartFrame: callbackStartFrame,
                callbackIndex: callbackIndex
            )
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

    private func recordTopOutputAdjacentSampleJumpsLocked(
        _ jumps: [RuntimeCMixerOutputMetrics.SampleJump],
        callbackStartFrame: UInt64,
        callbackIndex: UInt64
    ) {
        for jump in jumps {
            let runtimeFrame = callbackStartFrame.addingReportingOverflow(UInt64(max(0, jump.frameOffset)))
            let row = RuntimeCMixerTopOutputSampleJump(
                sampleJump: jump.sampleJump,
                runtimeFrame: runtimeFrame.overflow ? UInt64.max : runtimeFrame.partialValue,
                callbackIndex: callbackIndex,
                frameOffset: jump.frameOffset,
                channelIndex: jump.channelIndex
            )
            insertTopOutputAdjacentSampleJumpLocked(row)
        }
    }

    private func recordTopOutputPeaksLocked(
        _ peaks: [RuntimeCMixerOutputMetrics.Peak],
        callbackStartFrame: UInt64,
        callbackIndex: UInt64
    ) {
        for peak in peaks {
            let runtimeFrame = callbackStartFrame.addingReportingOverflow(UInt64(max(0, peak.frameOffset)))
            let row = RuntimeCMixerTopOutputPeak(
                peak: peak.peak,
                runtimeFrame: runtimeFrame.overflow ? UInt64.max : runtimeFrame.partialValue,
                callbackIndex: callbackIndex,
                frameOffset: peak.frameOffset,
                channelIndex: peak.channelIndex
            )
            insertTopOutputPeakLocked(row)
        }
    }

    private func insertTopOutputAdjacentSampleJumpLocked(_ row: RuntimeCMixerTopOutputSampleJump) {
        topOutputAdjacentSampleJumps.append(row)
        topOutputAdjacentSampleJumps.sort {
            if $0.sampleJump != $1.sampleJump {
                return $0.sampleJump > $1.sampleJump
            }
            if $0.runtimeFrame != $1.runtimeFrame {
                return $0.runtimeFrame < $1.runtimeFrame
            }
            return $0.channelIndex < $1.channelIndex
        }
        if topOutputAdjacentSampleJumps.count > Self.transientDiagnosticTopCount {
            topOutputAdjacentSampleJumps.removeLast(topOutputAdjacentSampleJumps.count - Self.transientDiagnosticTopCount)
        }
    }

    private func insertTopOutputPeakLocked(_ row: RuntimeCMixerTopOutputPeak) {
        topOutputPeaks.append(row)
        topOutputPeaks.sort {
            if $0.peak != $1.peak {
                return $0.peak > $1.peak
            }
            if $0.runtimeFrame != $1.runtimeFrame {
                return $0.runtimeFrame < $1.runtimeFrame
            }
            return $0.channelIndex < $1.channelIndex
        }
        if topOutputPeaks.count > Self.transientDiagnosticTopCount {
            topOutputPeaks.removeLast(topOutputPeaks.count - Self.transientDiagnosticTopCount)
        }
    }

    private func outputMetrics(
        _ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        sampleCount: Int,
        channelCount: Int
    ) -> RuntimeCMixerOutputMetrics {
        let boundedSampleCount = min(max(0, sampleCount), outputInterleavedPCM.count)
        guard boundedSampleCount > 0 else {
            return .silence
        }
        let safeChannelCount = max(1, channelCount)
        var peak = Float(0)
        var squareSum = Double(0)
        var discontinuityCount025 = 0
        var discontinuityCount035 = 0
        var discontinuityCount050 = 0
        var discontinuityCount075 = 0
        var maxAdjacentSampleJump = Float(0)
        var topAdjacentSampleJumps = [RuntimeCMixerOutputMetrics.SampleJump]()
        topAdjacentSampleJumps.reserveCapacity(Self.transientDiagnosticTopCount)
        var maxDiscontinuitySampleJump: Float?
        var maxDiscontinuityFrameOffset: Int?
        var maxDiscontinuityChannelIndex: Int?
        var peakWarningCount = 0
        var topPeaks = [RuntimeCMixerOutputMetrics.Peak]()
        topPeaks.reserveCapacity(Self.transientDiagnosticTopCount)
        var overrangeCount = 0
        var clippingCount = 0
        for index in 0..<boundedSampleCount {
            let sample = outputInterleavedPCM[index].isFinite ? outputInterleavedPCM[index] : 0
            let absolute = abs(sample)
            let frameOffset = index / safeChannelCount
            let channelIndex = index % safeChannelCount
            peak = max(peak, absolute)
            squareSum += Double(sample) * Double(sample)
            if absolute > Self.outputPeakWarningThreshold {
                peakWarningCount += 1
            }
            insertPeak(
                RuntimeCMixerOutputMetrics.Peak(
                    peak: absolute,
                    frameOffset: frameOffset,
                    channelIndex: channelIndex
                ),
                into: &topPeaks
            )
            if absolute > 1 {
                overrangeCount += 1
            }
            if absolute >= 1 {
                clippingCount += 1
            }
            if index >= safeChannelCount {
                let previous = outputInterleavedPCM[index - safeChannelCount].isFinite
                    ? outputInterleavedPCM[index - safeChannelCount]
                    : 0
                let sampleJump = abs(sample - previous)
                maxAdjacentSampleJump = max(maxAdjacentSampleJump, sampleJump)
                if sampleJump > 0.25 {
                    discontinuityCount025 += 1
                }
                if sampleJump > 0.35 {
                    discontinuityCount035 += 1
                }
                if sampleJump > 0.50 {
                    discontinuityCount050 += 1
                }
                if sampleJump > Self.outputDiscontinuityThreshold {
                    discontinuityCount075 += 1
                    if maxDiscontinuitySampleJump.map({ sampleJump > $0 }) ?? true {
                        maxDiscontinuitySampleJump = sampleJump
                        maxDiscontinuityFrameOffset = frameOffset
                        maxDiscontinuityChannelIndex = channelIndex
                    }
                }
                insertSampleJump(
                    RuntimeCMixerOutputMetrics.SampleJump(
                        sampleJump: sampleJump,
                        frameOffset: frameOffset,
                        channelIndex: channelIndex
                    ),
                    into: &topAdjacentSampleJumps
                )
            }
        }
        return RuntimeCMixerOutputMetrics(
            sampleCount: boundedSampleCount,
            peak: peak,
            squareSum: squareSum,
            discontinuityCount025: discontinuityCount025,
            discontinuityCount035: discontinuityCount035,
            discontinuityCount050: discontinuityCount050,
            discontinuityCount075: discontinuityCount075,
            maxAdjacentSampleJump: maxAdjacentSampleJump,
            topAdjacentSampleJumps: topAdjacentSampleJumps,
            maxDiscontinuityFrameOffset: maxDiscontinuityFrameOffset,
            maxDiscontinuityChannelIndex: maxDiscontinuityChannelIndex,
            maxDiscontinuitySampleJump: maxDiscontinuitySampleJump,
            peakWarningSampleCount: peakWarningCount,
            topPeaks: topPeaks,
            overrangeSampleCount: overrangeCount,
            clippingSampleCount: clippingCount
        )
    }

    private func insertSampleJump(
        _ row: RuntimeCMixerOutputMetrics.SampleJump,
        into rows: inout [RuntimeCMixerOutputMetrics.SampleJump]
    ) {
        rows.append(row)
        rows.sort {
            if $0.sampleJump != $1.sampleJump {
                return $0.sampleJump > $1.sampleJump
            }
            if $0.frameOffset != $1.frameOffset {
                return $0.frameOffset < $1.frameOffset
            }
            return $0.channelIndex < $1.channelIndex
        }
        if rows.count > Self.transientDiagnosticTopCount {
            rows.removeLast(rows.count - Self.transientDiagnosticTopCount)
        }
    }

    private func insertPeak(
        _ row: RuntimeCMixerOutputMetrics.Peak,
        into rows: inout [RuntimeCMixerOutputMetrics.Peak]
    ) {
        rows.append(row)
        rows.sort {
            if $0.peak != $1.peak {
                return $0.peak > $1.peak
            }
            if $0.frameOffset != $1.frameOffset {
                return $0.frameOffset < $1.frameOffset
            }
            return $0.channelIndex < $1.channelIndex
        }
        if rows.count > Self.transientDiagnosticTopCount {
            rows.removeLast(rows.count - Self.transientDiagnosticTopCount)
        }
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

    private func runtimeTraceContext(for event: RuntimeCMixerAdapterEvent) -> AudioRuntimeTraceContext {
        let noteValue: UInt8?
        let instrumentIndex: Int?
        let effectType: UInt8?
        let effectParam: UInt8?
        let volumeColumn: UInt8?
        switch event.action {
        case let .noteTrigger(_, _, mapping):
            noteValue = mapping.note
            instrumentIndex = mapping.instrumentIndex
            effectType = mapping.effectType
            effectParam = mapping.effectParam
            volumeColumn = mapping.volumeColumn.rawValue
        case .gainPanUpdate, .stepUpdate, .noteCut:
            noteValue = nil
            instrumentIndex = nil
            effectType = nil
            effectParam = nil
            volumeColumn = nil
        }
        return AudioRuntimeTraceContext(
            orderIndex: event.source.orderIndex,
            patternIndex: event.source.patternIndex,
            rowIndex: event.source.rowIndex,
            tickInRow: event.syntheticTick,
            channelIndex: event.channelIndex,
            noteValue: noteValue,
            instrumentIndex: instrumentIndex,
            effectType: effectType,
            effectParam: effectParam,
            volumeColumn: volumeColumn
        )
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

    private func copyScratchToAudioBuffers(
        ioData: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) -> RuntimeCMixerOutputBufferCopyDiagnostics {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        let channelCount = mixer.config.channelCount
        let captureSummary = callbackDiagnostics.outputBufferVerificationEnabled
            ? lastCaptureSummaryForOutputCopy()
            : nil
        if buffers.count == 1,
           let data = buffers[0].mData,
           Int(buffers[0].mNumberChannels) == channelCount {
            let sampleCount = min(
                Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size,
                frameCount * channelCount
            )
            let output = data.assumingMemoryBound(to: Float.self)
            let scratchCount = min(sampleCount, scratchInterleavedPCM.count)
            return scratchInterleavedPCM.withUnsafeBufferPointer { scratch in
                RuntimeCMixerOutputBufferCopy.copyInterleavedSamples(
                    scratch: UnsafeBufferPointer(start: scratch.baseAddress, count: scratchCount),
                    frameCount: frameCount,
                    sourceChannelCount: channelCount,
                    into: UnsafeMutableBufferPointer(start: output, count: sampleCount),
                    outputChannelCount: channelCount,
                    captureSummary: captureSummary,
                    collectSummaries: callbackDiagnostics.outputBufferVerificationEnabled
                )
            }
        }

        var outputHash = RuntimeCMixerSampleSummary.empty.checksum
        var outputPeak = Float(0)
        var outputSquareSum = Double(0)
        var outputFiniteSampleCount = 0
        var copiedSampleCount = 0
        var copiedFrameCount = max(0, frameCount)
        var partialCopy = false
        var outputChannelCount = 0
        let collectSummaries = callbackDiagnostics.outputBufferVerificationEnabled
        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else {
                partialCopy = true
                continue
            }
            let bufferChannelCount = max(1, Int(buffer.mNumberChannels))
            outputChannelCount += bufferChannelCount
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            copiedFrameCount = min(copiedFrameCount, availableSampleCount / bufferChannelCount)
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for bufferChannel in 0..<bufferChannelCount {
                    let outputIndex = frame * bufferChannelCount + bufferChannel
                    guard outputIndex < availableSampleCount else {
                        partialCopy = true
                        break
                    }
                    let sourceChannel = buffers.count == channelCount ? bufferIndex : bufferChannel
                    let sample: Float = sourceChannel < channelCount
                        ? scratchInterleavedPCM[(frame * channelCount) + sourceChannel]
                        : 0
                    output[outputIndex] = sample
                    if sourceChannel < channelCount {
                        copiedSampleCount += 1
                        if collectSummaries {
                            let sanitized = sample.isFinite ? sample : 0
                            outputHash = RuntimeCMixerSampleSummary.hash(outputHash, sample: sanitized)
                            outputPeak = max(outputPeak, abs(sanitized))
                            outputSquareSum += Double(sanitized) * Double(sanitized)
                            outputFiniteSampleCount += sample.isFinite ? 1 : 0
                        }
                    }
                }
            }
        }
        let expectedSampleCount = max(0, frameCount) * channelCount
        let filledRequestedFrames = copiedSampleCount >= expectedSampleCount && !partialCopy
        let channelCountMatches = outputChannelCount == channelCount
        let scratchSummary = collectSummaries
            ? scratchInterleavedPCM.withUnsafeBufferPointer { scratch in
                RuntimeCMixerSampleSummary.summarize(
                    scratch,
                    frameCount: frameCount,
                    channelCount: channelCount
                )
            }
            : nil
        let outputSummary: RuntimeCMixerSampleSummary?
        if collectSummaries, copiedSampleCount > 0, buffers.count == channelCount {
            var splitHash = RuntimeCMixerSampleSummary.empty.checksum
            var splitPeak = Float(0)
            var splitSquareSum = Double(0)
            var splitFiniteSampleCount = 0
            var splitSampleCount = 0
            for frame in 0..<copiedFrameCount {
                for sourceChannel in 0..<channelCount {
                    let buffer = buffers[sourceChannel]
                    guard let data = buffer.mData else {
                        continue
                    }
                    let bufferChannelCount = max(1, Int(buffer.mNumberChannels))
                    let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let outputIndex = frame * bufferChannelCount
                    guard outputIndex < availableSampleCount else {
                        continue
                    }
                    let sample = data.assumingMemoryBound(to: Float.self)[outputIndex]
                    let sanitized = sample.isFinite ? sample : 0
                    splitHash = RuntimeCMixerSampleSummary.hash(splitHash, sample: sanitized)
                    splitPeak = max(splitPeak, abs(sanitized))
                    splitSquareSum += Double(sanitized) * Double(sanitized)
                    splitFiniteSampleCount += sample.isFinite ? 1 : 0
                    splitSampleCount += 1
                }
            }
            outputSummary = RuntimeCMixerSampleSummary(
                frameCount: copiedFrameCount,
                channelCount: channelCount,
                sampleCount: splitSampleCount,
                finiteSampleCount: splitFiniteSampleCount,
                checksum: splitHash,
                peak: splitPeak,
                rms: splitSampleCount > 0 ? Float(sqrt(splitSquareSum / Double(splitSampleCount))) : 0
            )
        } else if collectSummaries, copiedSampleCount > 0 {
            outputSummary = RuntimeCMixerSampleSummary(
                frameCount: copiedFrameCount,
                channelCount: channelCount,
                sampleCount: copiedSampleCount,
                finiteSampleCount: outputFiniteSampleCount,
                checksum: outputHash,
                peak: outputPeak,
                rms: Float(sqrt(outputSquareSum / Double(copiedSampleCount)))
            )
        } else {
            outputSummary = collectSummaries ? .empty : nil
        }
        return RuntimeCMixerOutputBufferCopyDiagnostics(
            layout: buffers.count == channelCount ? "split_noninterleaved_buffers" : "multi_buffer_interleaved",
            requestedFrameCount: max(0, frameCount),
            sourceChannelCount: channelCount,
            outputBufferCount: buffers.count,
            outputChannelCount: outputChannelCount,
            copiedFrameCount: copiedFrameCount,
            copiedSampleCount: copiedSampleCount,
            expectedSampleCount: expectedSampleCount,
            filledRequestedFrames: filledRequestedFrames,
            channelCountMatches: channelCountMatches,
            partialCopy: partialCopy || !filledRequestedFrames,
            scratchSummary: scratchSummary,
            captureSummary: captureSummary,
            outputSummary: outputSummary
        )
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

private struct RuntimeCMixerAudioOutputDeviceDiagnostics: Equatable {
    let deviceID: AudioObjectID?
    let deviceUIDHash: String?
    let nominalSampleRate: Double?
    let ioBufferFrameSize: UInt32?
    let latencyFrames: UInt32?
    let safetyOffsetFrames: UInt32?
    let transportType: UInt32?

    var ioBufferDuration: Double? {
        guard let nominalSampleRate,
              nominalSampleRate > 0,
              let ioBufferFrameSize else {
            return nil
        }
        return Double(ioBufferFrameSize) / nominalSampleRate
    }

    var latencyDuration: Double? {
        duration(frames: latencyFrames)
    }

    var safetyOffsetDuration: Double? {
        duration(frames: safetyOffsetFrames)
    }

    static func currentDefaultOutputDevice() -> RuntimeCMixerAudioOutputDeviceDiagnostics {
        guard let deviceID = defaultOutputDeviceID() else {
            return RuntimeCMixerAudioOutputDeviceDiagnostics(
                deviceID: nil,
                deviceUIDHash: nil,
                nominalSampleRate: nil,
                ioBufferFrameSize: nil,
                latencyFrames: nil,
                safetyOffsetFrames: nil,
                transportType: nil
            )
        }
        return RuntimeCMixerAudioOutputDeviceDiagnostics(
            deviceID: deviceID,
            deviceUIDHash: deviceUIDHash(for: deviceID),
            nominalSampleRate: nominalSampleRate(for: deviceID),
            ioBufferFrameSize: ioBufferFrameSize(for: deviceID),
            latencyFrames: uint32Property(for: deviceID, selector: kAudioDevicePropertyLatency),
            safetyOffsetFrames: uint32Property(for: deviceID, selector: kAudioDevicePropertySafetyOffset),
            transportType: uint32Property(for: deviceID, selector: kAudioDevicePropertyTransportType)
        )
    }

    private func duration(frames: UInt32?) -> Double? {
        guard let nominalSampleRate,
              nominalSampleRate > 0,
              let frames else {
            return nil
        }
        return Double(frames) / nominalSampleRate
    }

    private static func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr,
              deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    private static func nominalSampleRate(for deviceID: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }
        return Double(sampleRate)
    }

    private static func ioBufferFrameSize(for deviceID: AudioObjectID) -> UInt32? {
        uint32Property(for: deviceID, selector: kAudioDevicePropertyBufferFrameSize)
    }

    private static func uint32Property(for deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr,
              value > 0 else {
            return nil
        }
        return value
    }

    private static func deviceUIDHash(for deviceID: AudioObjectID) -> String? {
        guard let uid = stringProperty(for: deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            return nil
        }
        return stableHash(uid)
    }

    private static func stringProperty(for deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            return nil
        }
        guard let string = value?.takeUnretainedValue() as String?,
              !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func stableHash(_ value: String) -> String {
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private struct RuntimeCMixerAudioGraphDiagnostics: Equatable {
    let cMixerRenderSampleRate: Double
    let cMixerRenderChannelCount: Int
    let sourceNodeRenderSampleRate: Double
    let sourceNodeChannelCount: Int
    let mainMixerOutputSampleRate: Double
    let mainMixerOutputChannelCount: Int
    let mainMixerInputSampleRate: Double
    let mainMixerInputChannelCount: Int
    let mainMixerLatency: Double
    let mainMixerOutputPresentationLatency: Double
    let outputNodeSampleRate: Double
    let outputNodeChannelCount: Int
    let outputNodeLatency: Double
    let outputNodeOutputPresentationLatency: Double
    let outputDeviceID: AudioObjectID?
    let outputDeviceUIDHash: String?
    let hardwareNominalSampleRate: Double?
    let hardwareIOBufferFrameSize: UInt32?
    let hardwareIOBufferDuration: Double?
    let hardwareLatencyFrames: UInt32?
    let hardwareLatencyDuration: Double?
    let hardwareSafetyOffsetFrames: UInt32?
    let hardwareSafetyOffsetDuration: Double?
    let hardwareTransportType: UInt32?
    let engineRunning: Bool
    let sourceNodeAttached: Bool
    let sourceNodeConnected: Bool
    let mainMixerConnectedToOutput: Bool
    let formatConversionLikely: Bool
    let captureMatchesSourceNodeFormat: Bool?
    let captureMatchesEngineOutputFormat: Bool?
    let captureMatchesHardwareSampleRate: Bool?

    init(
        snapshot: RuntimeCMixerRenderSnapshot,
        sourceFormat: AVAudioFormat,
        mainMixerInputFormat: AVAudioFormat,
        mainMixerOutputFormat: AVAudioFormat,
        outputNodeFormat: AVAudioFormat,
        outputDevice: RuntimeCMixerAudioOutputDeviceDiagnostics,
        engineRunning: Bool,
        sourceNodeAttached: Bool,
        sourceNodeConnected: Bool,
        mainMixerConnectedToOutput: Bool,
        mainMixerLatency: Double,
        mainMixerOutputPresentationLatency: Double,
        outputNodeLatency: Double,
        outputNodeOutputPresentationLatency: Double
    ) {
        cMixerRenderSampleRate = snapshot.sampleRate
        cMixerRenderChannelCount = snapshot.channelCount
        sourceNodeRenderSampleRate = sourceFormat.sampleRate
        sourceNodeChannelCount = Int(sourceFormat.channelCount)
        mainMixerOutputSampleRate = mainMixerOutputFormat.sampleRate
        mainMixerOutputChannelCount = Int(mainMixerOutputFormat.channelCount)
        mainMixerInputSampleRate = mainMixerInputFormat.sampleRate
        mainMixerInputChannelCount = Int(mainMixerInputFormat.channelCount)
        self.mainMixerLatency = mainMixerLatency
        self.mainMixerOutputPresentationLatency = mainMixerOutputPresentationLatency
        outputNodeSampleRate = outputNodeFormat.sampleRate
        outputNodeChannelCount = Int(outputNodeFormat.channelCount)
        self.outputNodeLatency = outputNodeLatency
        self.outputNodeOutputPresentationLatency = outputNodeOutputPresentationLatency
        outputDeviceID = outputDevice.deviceID
        outputDeviceUIDHash = outputDevice.deviceUIDHash
        hardwareNominalSampleRate = outputDevice.nominalSampleRate
        hardwareIOBufferFrameSize = outputDevice.ioBufferFrameSize
        hardwareIOBufferDuration = outputDevice.ioBufferDuration
        hardwareLatencyFrames = outputDevice.latencyFrames
        hardwareLatencyDuration = outputDevice.latencyDuration
        hardwareSafetyOffsetFrames = outputDevice.safetyOffsetFrames
        hardwareSafetyOffsetDuration = outputDevice.safetyOffsetDuration
        hardwareTransportType = outputDevice.transportType
        self.engineRunning = engineRunning
        self.sourceNodeAttached = sourceNodeAttached
        self.sourceNodeConnected = sourceNodeConnected
        self.mainMixerConnectedToOutput = mainMixerConnectedToOutput
        formatConversionLikely = RuntimeCMixerFormatDiagnostics.formatConversionLikely(
            sourceSampleRate: sourceNodeRenderSampleRate,
            sourceChannelCount: sourceNodeChannelCount,
            mainMixerSampleRate: mainMixerOutputSampleRate,
            mainMixerChannelCount: mainMixerOutputChannelCount,
            outputSampleRate: outputNodeSampleRate,
            outputChannelCount: outputNodeChannelCount,
            hardwareSampleRate: hardwareNominalSampleRate
        )
        captureMatchesSourceNodeFormat = Self.captureMatches(
            capture: snapshot.capture,
            sampleRate: sourceNodeRenderSampleRate,
            channelCount: sourceNodeChannelCount
        )
        captureMatchesEngineOutputFormat = Self.captureMatches(
            capture: snapshot.capture,
            sampleRate: outputNodeSampleRate,
            channelCount: outputNodeChannelCount
        )
        captureMatchesHardwareSampleRate = RuntimeCMixerFormatDiagnostics.sampleRatesMatch(
            snapshot.capture.sampleRate,
            hardwareNominalSampleRate
        )
    }

    var formatSignature: [String] {
        [
            "\(cMixerRenderSampleRate)",
            "\(cMixerRenderChannelCount)",
            "\(sourceNodeRenderSampleRate)",
            "\(sourceNodeChannelCount)",
            "\(mainMixerInputSampleRate)",
            "\(mainMixerInputChannelCount)",
            "\(mainMixerOutputSampleRate)",
            "\(mainMixerOutputChannelCount)",
            "\(outputNodeSampleRate)",
            "\(outputNodeChannelCount)",
            "\(hardwareNominalSampleRate ?? -1)"
        ]
    }

    var routeSignature: [String] {
        [
            outputDeviceUIDHash ?? "unknown",
            "\(outputDeviceID ?? 0)",
            "\(hardwareNominalSampleRate ?? -1)",
            "\(hardwareIOBufferFrameSize ?? 0)",
            "\(hardwareLatencyFrames ?? 0)",
            "\(hardwareSafetyOffsetFrames ?? 0)",
            "\(hardwareTransportType ?? 0)"
        ]
    }

    private static func captureMatches(
        capture: RuntimeCMixerCaptureSnapshot,
        sampleRate: Double,
        channelCount: Int
    ) -> Bool? {
        guard capture.enabled,
              let captureSampleRate = capture.sampleRate,
              let captureChannelCount = capture.channelCount else {
            return nil
        }
        return RuntimeCMixerFormatDiagnostics.sampleRatesMatch(captureSampleRate, sampleRate) &&
            captureChannelCount == channelCount
    }
}

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

@MainActor
final class RuntimeCMixerAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding, PlaybackFollowPositionProviding, RuntimeAudioDiagnosticOutput, RuntimeCMixerAdapterEventConsuming {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sourceNode: AVAudioSourceNode
    private let renderCore: RuntimeCMixerRenderCore
    private let fallbackAudioEngine = PlaybackAudioEngine()
    private let traceWriter: RuntimeCMixerTraceWriting
    private let runtimeSampleRateSelection: RuntimeCMixerSampleRateSelection?
    private var isPrepared = false
    private var isFallbackActive = false
    nonisolated(unsafe) private var engineConfigurationObserver: NSObjectProtocol?
    private var engineConfigurationChangeCount: UInt64 = 0
    private var audioGraphFormatChangeCount: UInt64 = 0
    private var audioOutputRouteChangeCount: UInt64 = 0
    private var lastAudioGraphFormatSignature: [String]?
    private var lastAudioGraphWasPrepared = false
    private var lastAudioOutputRouteSignature: [String]?
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
        sampleRate: Double = MixerRenderConfig.defaultSampleRate,
        channelCount: Int = MixerRenderConfig.defaultChannelCount,
        outputPolicy: RuntimeCMixerOutputPolicy = .defaultPolicy,
        updatePolicy: RuntimeCMixerUpdatePolicy = .defaultPolicy,
        captureConfiguration: RuntimeCMixerCaptureConfiguration? = nil,
        callbackDiagnostics: RuntimeCMixerCallbackDiagnosticsConfiguration = .defaultConfiguration,
        runtimeSampleRateSelection: RuntimeCMixerSampleRateSelection? = nil,
        traceWriter: RuntimeCMixerTraceWriting = NoopRuntimeCMixerTraceWriter.shared
    ) {
        let config = MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount)
        renderCore = RuntimeCMixerRenderCore(
            config: config,
            outputPolicy: outputPolicy,
            updatePolicy: updatePolicy,
            captureConfiguration: captureConfiguration,
            callbackDiagnostics: callbackDiagnostics
        )
        self.traceWriter = traceWriter
        self.runtimeSampleRateSelection = runtimeSampleRateSelection
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
        engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordEngineConfigurationChange()
            }
        }
    }

    deinit {
        if let engineConfigurationObserver {
            NotificationCenter.default.removeObserver(engineConfigurationObserver)
        }
    }

    var runtimeAudioBackend: RuntimeAudioBackend {
        .cMixer
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

    var hasRuntimeAdapterEventPlan: Bool {
        adapterEventPlan.generated
    }

    func playbackFollowPosition(timerPosition: PlaybackPosition, timerTickInRow: Int) -> PlaybackFollowPosition? {
        guard adapterEventPlan.generated,
              let cMixerPosition = resolvedSampleTimePosition(
                context: traceContext(position: timerPosition, tickInRow: timerTickInRow),
                snapshot: renderCore.snapshot()
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

    func configureRuntimeAdapterEventPlan(_ plan: RuntimeCMixerAdapterEventPlan) {
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
            runtimeFrameOffset: offset
        )
        adapterEventScheduleConfigured = true
        prepareIfNeeded()
        if !startEngineIfNeeded() {
            isFallbackActive = true
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
            ),
            eventAppliedFrame: snapshot.currentFrame,
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
        let playbackSeconds = snapshot.sampleRate > 0
            ? Double(snapshot.currentFrame) / snapshot.sampleRate
            : nil
        let offset = plannedRuntimeFrameOffset ?? resolvedPlannedRuntimeFrameOffset(context: context, snapshot: snapshot)
        let cMixerSampleTimeFrame = offset.flatMap { plannedFrame(runtimeFrame: snapshot.currentFrame, runtimeFrameOffset: $0) }
        let cMixerPosition = cMixerSampleTimeFrame.flatMap { sampleTimePositionResolver?.position(atFrame: $0) }
        let playbackEnginePlannedFrame = adapterEventPlan.plannedFrame(matching: context)
        let playbackEngineRuntimeFrame = playbackEnginePlannedFrame.flatMap { plannedFrame in
            offset.flatMap { safeAdding(plannedFrame, $0) }
        }
        let frameDelta = playbackEngineRuntimeFrame.flatMap { plannedFrame in
            delta(runtimeFrame: snapshot.currentFrame, plannedFrame: plannedFrame)
        }
        let mismatch = positionMismatch(context: context, cMixerPosition: cMixerPosition)
        return RuntimeCMixerSampleTimePositionTraceFields(
            cMixerRenderedFrames: snapshot.currentFrame,
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
                ? rowTransitionDeltaCategory(delta: frameDelta, context: context, cMixerPosition: cMixerPosition, sampleRate: snapshot.sampleRate)
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
        if let context,
           let cMixerPosition,
           cMixerPosition.source.orderIndex == context.orderIndex,
           cMixerPosition.source.patternIndex == context.patternIndex,
           cMixerPosition.source.rowIndex == context.rowIndex {
            return "same_row_different_tick"
        }
        return "different_row_or_order"
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

    private func audioGraphDiagnostics(snapshot: RuntimeCMixerRenderSnapshot) -> RuntimeCMixerAudioGraphDiagnostics {
        let outputDevice = RuntimeCMixerAudioOutputDeviceDiagnostics.currentDefaultOutputDevice()
        return RuntimeCMixerAudioGraphDiagnostics(
            snapshot: snapshot,
            sourceFormat: format,
            mainMixerInputFormat: engine.mainMixerNode.inputFormat(forBus: 0),
            mainMixerOutputFormat: engine.mainMixerNode.outputFormat(forBus: 0),
            outputNodeFormat: engine.outputNode.outputFormat(forBus: 0),
            outputDevice: outputDevice,
            engineRunning: engine.isRunning,
            sourceNodeAttached: isPrepared,
            sourceNodeConnected: isPrepared && !engine.outputConnectionPoints(for: sourceNode, outputBus: 0).isEmpty,
            mainMixerConnectedToOutput: !engine.outputConnectionPoints(for: engine.mainMixerNode, outputBus: 0).isEmpty,
            mainMixerLatency: engine.mainMixerNode.latency,
            mainMixerOutputPresentationLatency: engine.mainMixerNode.outputPresentationLatency,
            outputNodeLatency: engine.outputNode.latency,
            outputNodeOutputPresentationLatency: engine.outputNode.outputPresentationLatency
        )
    }

    private func recordEngineConfigurationChange() {
        engineConfigurationChangeCount &+= 1
        recordRuntimeEvent(
            action: "engine_configuration_change",
            context: nil,
            targetScope: "none",
            snapshot: renderCore.snapshot(),
            succeeded: nil,
            reason: "av_audio_engine_configuration_change"
        )
    }

    private func updateAudioGraphChangeCounters(_ graph: RuntimeCMixerAudioGraphDiagnostics) -> (formatChanged: Bool, routeChanged: Bool) {
        let formatChanged: Bool
        if lastAudioGraphWasPrepared,
           graph.sourceNodeAttached,
           let lastAudioGraphFormatSignature {
            formatChanged = lastAudioGraphFormatSignature != graph.formatSignature
        } else {
            formatChanged = false
        }
        if formatChanged {
            audioGraphFormatChangeCount &+= 1
        }
        lastAudioGraphFormatSignature = graph.formatSignature
        lastAudioGraphWasPrepared = graph.sourceNodeAttached

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
        return (formatChanged, routeChanged)
    }

    private func drainAppliedRuntimeAdapterEvents() {
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
        drainAppliedRuntimeAdapterEvents()
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
        finishRuntimeCaptureIfNeeded(reason: reason)
        resetRuntimeAdapterEventConsumption()
    }

    func recordTransition(
        previousContext: AudioRuntimeTraceContext?,
        context: AudioRuntimeTraceContext?,
        phase: String,
        reason: String
    ) {
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
        drainAppliedRuntimeAdapterEvents()
        if publicationDisabled {
            playbackFollowPublicationSuppressedCount &+= 1
        } else {
            playbackFollowPublicationCount &+= 1
        }
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

    func reset() {
        drainAppliedRuntimeAdapterEvents()
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
        let audioGraph = audioGraphDiagnostics(snapshot: snapshot)
        let audioGraphChanges = updateAudioGraphChangeCounters(audioGraph)
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
            sampleRate: snapshot.sampleRate,
            selectedRuntimeSampleRate: runtimeSampleRateSelection?.sampleRate ?? snapshot.sampleRate,
            cMixerRuntimeSampleRate: snapshot.sampleRate,
            runtimeSampleRatePolicy: runtimeSampleRateSelection?.policy,
            runtimeSampleRateSource: runtimeSampleRateSelection?.source,
            runtimeSampleRateConfigurationWarning: runtimeSampleRateSelection?.configurationWarning,
            cMixerRenderSampleRate: audioGraph.cMixerRenderSampleRate,
            cMixerRenderChannelCount: audioGraph.cMixerRenderChannelCount,
            audioSourceNodeRenderSampleRate: audioGraph.sourceNodeRenderSampleRate,
            audioSourceNodeChannelCount: audioGraph.sourceNodeChannelCount,
            audioEngineMainMixerOutputSampleRate: audioGraph.mainMixerOutputSampleRate,
            audioEngineMainMixerOutputChannelCount: audioGraph.mainMixerOutputChannelCount,
            audioEngineMainMixerInputSampleRate: audioGraph.mainMixerInputSampleRate,
            audioEngineMainMixerInputChannelCount: audioGraph.mainMixerInputChannelCount,
            audioEngineMainMixerLatency: audioGraph.mainMixerLatency,
            audioEngineMainMixerOutputPresentationLatency: audioGraph.mainMixerOutputPresentationLatency,
            audioEngineOutputNodeSampleRate: audioGraph.outputNodeSampleRate,
            audioEngineOutputNodeChannelCount: audioGraph.outputNodeChannelCount,
            audioEngineOutputNodeLatency: audioGraph.outputNodeLatency,
            audioEngineOutputNodeOutputPresentationLatency: audioGraph.outputNodeOutputPresentationLatency,
            audioHardwareNominalSampleRate: audioGraph.hardwareNominalSampleRate,
            audioHardwareDeviceID: audioGraph.outputDeviceID,
            audioHardwareDeviceUIDHash: audioGraph.outputDeviceUIDHash,
            audioHardwareIOBufferFrameSize: audioGraph.hardwareIOBufferFrameSize,
            audioHardwareIOBufferDuration: audioGraph.hardwareIOBufferDuration,
            audioHardwareLatencyFrames: audioGraph.hardwareLatencyFrames,
            audioHardwareLatencyDuration: audioGraph.hardwareLatencyDuration,
            audioHardwareSafetyOffsetFrames: audioGraph.hardwareSafetyOffsetFrames,
            audioHardwareSafetyOffsetDuration: audioGraph.hardwareSafetyOffsetDuration,
            audioHardwareTransportType: audioGraph.hardwareTransportType,
            audioEngineRunning: audioGraph.engineRunning,
            audioEngineSourceNodeAttached: audioGraph.sourceNodeAttached,
            audioEngineSourceNodeConnected: audioGraph.sourceNodeConnected,
            audioEngineMainMixerConnectedToOutput: audioGraph.mainMixerConnectedToOutput,
            audioEngineConfigurationChangeCount: engineConfigurationChangeCount,
            audioGraphFormatChangeCount: audioGraphFormatChangeCount,
            audioOutputRouteChangeCount: audioOutputRouteChangeCount,
            audioGraphFormatChanged: audioGraphChanges.formatChanged,
            audioOutputRouteChanged: audioGraphChanges.routeChanged,
            audioFormatConversionLikely: audioGraph.formatConversionLikely,
            runtimeCaptureMatchesSourceNodeFormat: audioGraph.captureMatchesSourceNodeFormat,
            runtimeCaptureMatchesEngineOutputFormat: audioGraph.captureMatchesEngineOutputFormat,
            runtimeCaptureMatchesHardwareSampleRate: audioGraph.captureMatchesHardwareSampleRate,
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
            callbackDurationWarningCount: snapshot.callbackDurationWarningCount,
            callbackRenderQuantumDurationMS: snapshot.callbackRenderQuantumDurationMS,
            callbackRenderQuantumMinMS: snapshot.callbackRenderQuantumMinMS,
            callbackRenderQuantumMaxMS: snapshot.callbackRenderQuantumMaxMS,
            callbackOverRenderQuantumBudgetCount: snapshot.callbackOverRenderQuantumBudgetCount,
            callbackIntervalMinMS: snapshot.callbackIntervalMinMS,
            callbackIntervalMaxMS: snapshot.callbackIntervalMaxMS,
            callbackIntervalLastMS: snapshot.callbackIntervalLastMS,
            callbackThreadIsMain: snapshot.callbackThreadIsMain,
            callbackThreadID: snapshot.callbackThreadID,
            callbackMainThreadDependencyDetected: snapshot.callbackMainThreadDependencyDetected,
            callbackAllocationWarning: snapshot.callbackAllocationWarning,
            callbackLockWaitCount: snapshot.callbackLockWaitCount,
            callbackLockWaitDurationMS: snapshot.callbackLockWaitDurationMS,
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
