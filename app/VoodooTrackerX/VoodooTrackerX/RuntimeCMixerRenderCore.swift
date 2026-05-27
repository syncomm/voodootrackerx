import AVFoundation
import AudioToolbox
import Darwin
import Foundation
import Synchronization

struct RuntimeCMixerRenderSnapshot: Equatable {
    let sampleRate: Double
    let channelCount: Int
    let activeVoiceCount: Int
    let loadedVoiceCount: Int
    let scheduledVoiceCount: Int
    let eventQueueBacklogCount: Int
    let eventQueueExhausted: Bool
    let eventQueueExhaustedFrame: UInt64?
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
    let callbackMaxDurationMS: Double?
    let callbackAvgDurationMS: Double?
    let callbackDurationWarningCount: UInt64
    let callbackRenderQuantumDurationMS: Double?
    let callbackRenderQuantumMinMS: Double?
    let callbackRenderQuantumMaxMS: Double?
    let callbackOverRenderQuantumBudgetCount: UInt64
    let callbackNearBudgetWarningCount: UInt64
    let callbackIntervalMinMS: Double?
    let callbackIntervalMaxMS: Double?
    let callbackIntervalLastMS: Double?
    let callbackThreadIsMain: Bool?
    let callbackThreadID: UInt64?
    let callbackMainThreadDependencyDetected: Bool
    let callbackAllocationWarning: Bool
    let callbackRealtimeSafeDiagnostics: Bool
    let callbackDiagnosticDropCount: UInt64
    let callbackRingBufferCapacity: Int
    let callbackLockWaitCount: UInt64
    let callbackLockWaitDurationMS: Double
    let callbackLockFailureCount: UInt64
    let callbackLockAttemptCount: UInt64
    let callbackTryLockFailureCount: UInt64
    let callbackLockFailureAudioImpact: Bool?
    let callbackRenderedFromStaleSnapshotCount: UInt64
    let callbackRenderedSilenceDueToUnavailableStateCount: UInt64
    let callbackSkippedDiagnosticsDueToLockCount: UInt64
    let callbackSkippedAudioDueToLockCount: UInt64
    let lifecycleChangeWhileRenderingCount: UInt64
    let audioUnitLifecycleCallWhileCallbackActiveCount: UInt64
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
    let plannedSongEndFrame: Int?
    let plannedSongEndRuntimeFrame: UInt64?
    let runtimeFrameAtPlannedSongEnd: UInt64?
    let runtimeTailSeconds: Double
    let runtimeTailFrames: Int
    let runtimeTailPolicy: String
    let runtimeTailConfigurationWarning: String?
    let songEndStopFrame: Int?
    let songEndStopRuntimeFrame: UInt64?
    let runtimeFrameAtSongEndTailStop: UInt64?
    let activeVoiceCountAtPlannedSongEnd: Int?
    let loadedVoiceCountAtPlannedSongEnd: Int?
    let activeVoiceCountAtTailStop: Int?
    let loadedVoiceCountAtTailStop: Int?
    let activeVoiceCountAfterPlannedSongEnd: Int?
    let loadedVoiceCountAfterPlannedSongEnd: Int?
    let outputContinuesAfterPlannedSongEnd: Bool?
    let finalSustainedVoicesContinueAfterPlannedSongEnd: Bool?
    let songEndTailStopReached: Bool
    let captureCapTriggeredPlaybackStop: Bool
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
    let sampleCount: Int
    let peak: Float
    let squareSum: Double
    let discontinuityCount025: Int
    let discontinuityCount035: Int
    let discontinuityCount050: Int
    let discontinuityCount075: Int
    let maxAdjacentSampleJump: Float
    let maxDiscontinuityFrameOffset: Int?
    let maxDiscontinuityChannelIndex: Int?
    let maxDiscontinuitySampleJump: Float?
    let peakWarningSampleCount: Int
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
        maxDiscontinuityFrameOffset: nil,
        maxDiscontinuityChannelIndex: nil,
        maxDiscontinuitySampleJump: nil,
        peakWarningSampleCount: 0,
        overrangeSampleCount: 0,
        clippingSampleCount: 0
    )
}

private struct RuntimeCMixerBurstRenderState: Equatable {
    let activeVoiceCount: Int
    let loadedVoiceCount: Int
    let rampDownStartCount: UInt64
    let rampDownCompletionCount: UInt64
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

enum RuntimeCMixerAppliedAdapterEventResult: Equatable {
    case noteTrigger(RuntimeCMixerTriggerResult)
    case gainPanUpdate(RuntimeCMixerUpdateResult)
    case stepUpdate(RuntimeCMixerUpdateResult)
    case noteCut(RuntimeCMixerPlannedCutResult)
}

struct RuntimeCMixerAffectedChannelSet: Equatable {
    static let capacity = 8

    private(set) var count = 0
    private var channel0 = 0
    private var channel1 = 0
    private var channel2 = 0
    private var channel3 = 0
    private var channel4 = 0
    private var channel5 = 0
    private var channel6 = 0
    private var channel7 = 0

    mutating func insert(_ channel: Int) {
        guard !contains(channel),
              count < Self.capacity else {
            return
        }
        setValue(channel, at: count)
        count += 1
        var index = count - 1
        while index > 0,
              value(at: index) < value(at: index - 1) {
            swapAt(index, index - 1)
            index -= 1
        }
    }

    func values() -> [Int] {
        guard count > 0 else {
            return []
        }
        var result = [Int]()
        result.reserveCapacity(count)
        for index in 0..<count {
            result.append(value(at: index))
        }
        return result
    }

    private func contains(_ channel: Int) -> Bool {
        for index in 0..<count where value(at: index) == channel {
            return true
        }
        return false
    }

    private func value(at index: Int) -> Int {
        switch index {
        case 0: channel0
        case 1: channel1
        case 2: channel2
        case 3: channel3
        case 4: channel4
        case 5: channel5
        case 6: channel6
        default: channel7
        }
    }

    private mutating func setValue(_ value: Int, at index: Int) {
        switch index {
        case 0: channel0 = value
        case 1: channel1 = value
        case 2: channel2 = value
        case 3: channel3 = value
        case 4: channel4 = value
        case 5: channel5 = value
        case 6: channel6 = value
        default: channel7 = value
        }
    }

    private mutating func swapAt(_ lhs: Int, _ rhs: Int) {
        let leftValue = value(at: lhs)
        setValue(value(at: rhs), at: lhs)
        setValue(leftValue, at: rhs)
    }
}

struct RuntimeCMixerSameFrameBurstDiagnostic: Equatable {
    private static let gainPanUpdateCategoryBit: UInt32 = 1 << 0
    private static let globalVolumeUpdateCategoryBit: UInt32 = 1 << 1
    private static let keyOffFadeoutCategoryBit: UInt32 = 1 << 2
    private static let noteCutCategoryBit: UInt32 = 1 << 3
    private static let noteTriggerCategoryBit: UInt32 = 1 << 4
    private static let replacementStopRampCategoryBit: UInt32 = 1 << 5
    private static let stepUpdateCategoryBit: UInt32 = 1 << 6
    private static let otherCategoryBit: UInt32 = 1 << 7

    let id: Int
    let eventOrdinal: Int
    let categoryMask: UInt32
    let affectedChannelSet: RuntimeCMixerAffectedChannelSet
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

    var categories: [String] {
        var result = [String]()
        appendCategory("gain_pan_update", bit: Self.gainPanUpdateCategoryBit, into: &result)
        appendCategory("global_volume_update", bit: Self.globalVolumeUpdateCategoryBit, into: &result)
        appendCategory("key_off_fadeout", bit: Self.keyOffFadeoutCategoryBit, into: &result)
        appendCategory("note_cut", bit: Self.noteCutCategoryBit, into: &result)
        appendCategory("note_trigger", bit: Self.noteTriggerCategoryBit, into: &result)
        appendCategory("replacement_stop_ramp", bit: Self.replacementStopRampCategoryBit, into: &result)
        appendCategory("step_update", bit: Self.stepUpdateCategoryBit, into: &result)
        appendCategory("other", bit: Self.otherCategoryBit, into: &result)
        return result
    }

    var affectedChannels: [Int] {
        affectedChannelSet.values()
    }

    static func categoryMask(for rawCategory: String) -> UInt32 {
        switch rawCategory {
        case "gain_pan_update":
            return gainPanUpdateCategoryBit
        case "hxy_global_volume", "hxy_global_volume_update", "global_volume_update":
            return globalVolumeUpdateCategoryBit
        case "key_off", "key_off_fadeout":
            return keyOffFadeoutCategoryBit
        case "note_cut":
            return noteCutCategoryBit
        case "note_trigger":
            return noteTriggerCategoryBit
        case "replacement", "replacement_stop_ramp":
            return replacementStopRampCategoryBit
        case "step_pitch_update", "step_update":
            return stepUpdateCategoryBit
        default:
            return otherCategoryBit
        }
    }

    private func appendCategory(_ category: String, bit: UInt32, into result: inout [String]) {
        if categoryMask & bit != 0 {
            result.append(category)
        }
    }
}

struct RuntimeCMixerAppliedAdapterEventDiagnostic: Equatable {
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

struct RuntimeCMixerFixedRingBuffer<Element> {
    private var storage: [Element?]
    private var readIndex = 0
    private var storedCount = 0
    private(set) var droppedCount: UInt64 = 0

    init(capacity: Int) {
        storage = Array(repeating: nil, count: max(0, capacity))
    }

    var capacity: Int {
        storage.count
    }

    var count: Int {
        storedCount
    }

    var isEmpty: Bool {
        storedCount == 0
    }

    mutating func record(_ element: Element) {
        guard !storage.isEmpty else {
            droppedCount &+= 1
            return
        }
        guard storedCount < storage.count else {
            droppedCount &+= 1
            return
        }
        let writeIndex = (readIndex + storedCount) % storage.count
        storage[writeIndex] = element
        storedCount += 1
    }

    mutating func recordDrop() {
        droppedCount &+= 1
    }

    mutating func drain(limit: Int? = nil) -> [Element] {
        guard storedCount > 0 else {
            return []
        }
        let requestedCount = limit.map { max(0, $0) } ?? storedCount
        let drainCount = min(storedCount, requestedCount)
        guard drainCount > 0 else {
            return []
        }
        var drained = [Element]()
        drained.reserveCapacity(drainCount)
        for offset in 0..<drainCount {
            let index = (readIndex + offset) % storage.count
            if let element = storage[index] {
                drained.append(element)
            }
            storage[index] = nil
        }
        storedCount -= drainCount
        readIndex = storedCount == 0 ? 0 : (readIndex + drainCount) % storage.count
        return drained
    }

    mutating func removeAll(resetDroppedCount: Bool = true) {
        guard !storage.isEmpty else {
            storedCount = 0
            readIndex = 0
            if resetDroppedCount {
                droppedCount = 0
            }
            return
        }
        for index in storage.indices {
            storage[index] = nil
        }
        readIndex = 0
        storedCount = 0
        if resetDroppedCount {
            droppedCount = 0
        }
    }
}

struct RuntimeCMixerFixedTopDiagnostics<Element: Equatable>: Equatable {
    private var storage: [Element?]
    private var storedCount = 0

    init(capacity: Int) {
        storage = Array(repeating: nil, count: max(0, capacity))
    }

    var values: [Element] {
        guard storedCount > 0 else {
            return []
        }
        var result = [Element]()
        result.reserveCapacity(storedCount)
        for index in 0..<storedCount {
            if let element = storage[index] {
                result.append(element)
            }
        }
        return result
    }

    mutating func record(_ element: Element, precedes: (Element, Element) -> Bool) {
        guard !storage.isEmpty else {
            return
        }
        if storedCount < storage.count {
            storage[storedCount] = element
            storedCount += 1
        } else if let last = storage[storedCount - 1],
                  !precedes(element, last) {
            return
        } else {
            storage[storedCount - 1] = element
        }

        var index = storedCount - 1
        while index > 0,
              let current = storage[index],
              let previous = storage[index - 1],
              precedes(current, previous) {
            storage.swapAt(index, index - 1)
            index -= 1
        }
    }
}

struct RuntimeCMixerAdapterEventScheduleConfigurationResult: Equatable {
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

struct RuntimeCMixerRealtimeState: Equatable {
    let requestedFrameCount: Int
    let callbackThread: RuntimeCMixerThreadDiagnostics
    let startUptimeNanos: UInt64

    static func begin(requestedFrameCount: Int) -> RuntimeCMixerRealtimeState {
        RuntimeCMixerRealtimeState(
            requestedFrameCount: max(0, requestedFrameCount),
            callbackThread: RuntimeCMixerThreadDiagnostics.current(),
            startUptimeNanos: DispatchTime.now().uptimeNanoseconds
        )
    }

    func finish() -> RuntimeCMixerCallbackCounters.Sample {
        RuntimeCMixerCallbackCounters.Sample(
            requestedFrameCount: requestedFrameCount,
            startUptimeNanos: startUptimeNanos,
            endUptimeNanos: DispatchTime.now().uptimeNanoseconds
        )
    }
}

struct RuntimeCMixerCallbackCounters: Equatable {
    struct Sample: Equatable {
        let requestedFrameCount: Int
        let startUptimeNanos: UInt64
        let endUptimeNanos: UInt64
    }
}

final class RuntimeCMixerRenderCore: @unchecked Sendable {
    static let updateEpsilon = RuntimeCMixerUpdatePolicy.defaultUpdateEpsilon
    static let outputDiscontinuityThreshold = Float(0.75)
    static let outputPeakWarningThreshold = Float(0.95)
    static let transientDiagnosticTopCount = 8
    static let callbackDurationWarningThresholdSeconds = 0.002
    static let callbackNearBudgetWarningRatio = 0.75
    static let callbackDiagnosticRingCapacity = 32_768
    static let callbackDiagnosticDrainLimit = 256
    static let callbackBurstScratchCapacity = 128

    private let lock = NSLock()
    private let callbackLockAttemptCounter = Atomic(UInt64(0))
    private let callbackLockFailureCounter = Atomic(UInt64(0))
    private let callbackActiveRenderDepth = Atomic(UInt64(0))
    private let callbackRenderedFromStaleSnapshotCounter = Atomic(UInt64(0))
    private let callbackRenderedSilenceDueToUnavailableStateCounter = Atomic(UInt64(0))
    private let callbackSkippedDiagnosticsDueToLockCounter = Atomic(UInt64(0))
    private let callbackSkippedAudioDueToLockCounter = Atomic(UInt64(0))
    private let lifecycleChangeWhileRenderingCounter = Atomic(UInt64(0))
    private let audioUnitLifecycleCallWhileCallbackActiveCounter = Atomic(UInt64(0))
    private let lastCallbackOutputFrameCountAtomic = Atomic(UInt64(0))
    private let realtimeCurrentFrameCounter = Atomic(UInt64(0))
    private let mixer: CSoftwareMixer
    private let captureBuffer: RuntimeCMixerCaptureBuffer?
    private let callbackDiagnostics: RuntimeCMixerCallbackDiagnosticsConfiguration
    private let songEndTailPolicy: RuntimeCMixerSongEndTailPolicy
    private let runtimeTailFrames: Int
    private let maximumRenderFrames: Int
    private var scratchInterleavedPCM: [Float]
    private var lastCallbackOutputInterleavedPCM: [Float]
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
    private var callbackNearBudgetWarningCount: UInt64 = 0
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
    private var topOutputAdjacentSampleJumps = RuntimeCMixerFixedTopDiagnostics<RuntimeCMixerTopOutputSampleJump>(
        capacity: RuntimeCMixerRenderCore.transientDiagnosticTopCount
    )
    private var lastOutputDiscontinuitySampleJump: Float?
    private var lastOutputDiscontinuityCallbackIndex: UInt64?
    private var lastOutputDiscontinuityRuntimeFrame: UInt64?
    private var lastOutputDiscontinuityFrameOffset: Int?
    private var lastOutputDiscontinuityChannelIndex: Int?
    private var outputPeakWarningSampleCount: UInt64 = 0
    private var topOutputPeaks = RuntimeCMixerFixedTopDiagnostics<RuntimeCMixerTopOutputPeak>(
        capacity: RuntimeCMixerRenderCore.transientDiagnosticTopCount
    )
    private var overrangeSampleCount: UInt64 = 0
    private var clippingSampleCount: UInt64 = 0
    private var adapterEventSchedule = [RuntimeCMixerQueuedAdapterEvent]()
    private var nextAdapterEventScheduleIndex = 0
    private var plannedSongEndFrame: Int?
    private var plannedSongEndRuntimeFrame: UInt64?
    private var runtimeFrameAtPlannedSongEnd: UInt64?
    private var songEndStopFrame: Int?
    private var songEndStopRuntimeFrame: UInt64?
    private var runtimeFrameAtSongEndTailStop: UInt64?
    private var activeVoiceCountAtPlannedSongEnd: Int?
    private var loadedVoiceCountAtPlannedSongEnd: Int?
    private var activeVoiceCountAtTailStop: Int?
    private var loadedVoiceCountAtTailStop: Int?
    private var eventQueueExhaustedFrame: UInt64?
    private var appliedAdapterEventDiagnostics = RuntimeCMixerFixedRingBuffer<RuntimeCMixerAppliedAdapterEventDiagnostic>(
        capacity: RuntimeCMixerRenderCore.callbackDiagnosticRingCapacity
    )
    private var burstDiagnosticScratch: [RuntimeCMixerAppliedAdapterEventDiagnostic?]
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
        callbackDiagnostics: RuntimeCMixerCallbackDiagnosticsConfiguration = .defaultConfiguration,
        songEndTailPolicy: RuntimeCMixerSongEndTailPolicy = .defaultPolicy
    ) {
        self.config = config
        self.outputPolicy = outputPolicy
        self.updatePolicy = updatePolicy
        self.callbackDiagnostics = callbackDiagnostics
        self.songEndTailPolicy = songEndTailPolicy
        runtimeTailFrames = songEndTailPolicy.tailFrames(sampleRate: config.sampleRate)
        self.maximumRenderFrames = max(1, maximumRenderFrames)
        let configuredMixer = CSoftwareMixer(config: config)
        mixer = configuredMixer
        if let captureConfiguration {
            captureBuffer = RuntimeCMixerCaptureBuffer(configuration: captureConfiguration, config: configuredMixer.config)
        } else {
            captureBuffer = nil
        }
        scratchInterleavedPCM = Array(repeating: 0, count: self.maximumRenderFrames * mixer.config.channelCount)
        lastCallbackOutputInterleavedPCM = Array(repeating: 0, count: self.maximumRenderFrames * mixer.config.channelCount)
        burstDiagnosticScratch = Array(repeating: nil, count: Self.callbackBurstScratchCapacity)
    }

    @discardableResult
    func configureAdapterEventSchedule(
        _ events: [RuntimeCMixerAdapterEvent],
        runtimeFrameOffset: Int,
        plannedSongEndFrame: Int? = nil
    ) -> RuntimeCMixerAdapterEventScheduleConfigurationResult {
        recordLifecycleChangeIfCallbackActive()
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
        self.plannedSongEndFrame = plannedSongEndFrame
        plannedSongEndRuntimeFrame = Self.runtimeFrame(plannedFrame: plannedSongEndFrame, offset: runtimeFrameOffset)
        songEndStopFrame = Self.songEndStopFrame(plannedSongEndFrame: plannedSongEndFrame, tailFrames: runtimeTailFrames)
        songEndStopRuntimeFrame = Self.runtimeFrame(plannedFrame: songEndStopFrame, offset: runtimeFrameOffset)
        runtimeFrameAtPlannedSongEnd = nil
        runtimeFrameAtSongEndTailStop = nil
        activeVoiceCountAtPlannedSongEnd = nil
        loadedVoiceCountAtPlannedSongEnd = nil
        activeVoiceCountAtTailStop = nil
        loadedVoiceCountAtTailStop = nil
        eventQueueExhaustedFrame = adapterEventSchedule.isEmpty ? mixer.currentFrame : nil
        eventQueueProducerThreadDiagnostics = RuntimeCMixerThreadDiagnostics.current()
        eventQueueConsumerThreadDiagnostics = nil
        appliedAdapterEventDiagnostics.removeAll()
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

    func clearAdapterEventSchedule() {
        recordLifecycleChangeIfCallbackActive()
        lock.lock()
        defer {
            lock.unlock()
        }
        adapterEventSchedule.removeAll(keepingCapacity: true)
        nextAdapterEventScheduleIndex = 0
        plannedSongEndFrame = nil
        plannedSongEndRuntimeFrame = nil
        songEndStopFrame = nil
        songEndStopRuntimeFrame = nil
        runtimeFrameAtPlannedSongEnd = nil
        runtimeFrameAtSongEndTailStop = nil
        activeVoiceCountAtPlannedSongEnd = nil
        loadedVoiceCountAtPlannedSongEnd = nil
        activeVoiceCountAtTailStop = nil
        loadedVoiceCountAtTailStop = nil
        eventQueueExhaustedFrame = nil
        eventQueueProducerThreadDiagnostics = nil
        eventQueueConsumerThreadDiagnostics = nil
        appliedAdapterEventDiagnostics.removeAll()
        appliedPlannedEventCount = 0
        exactFrameAppliedEventCount = 0
        callbackBoundaryAppliedEventCount = 0
        latePlannedEventCount = 0
        maxPlannedVsAppliedDelta = 0
    }

    func configureAdapterEventScheduleForTesting(
        _ events: [RuntimeCMixerAdapterEvent],
        runtimeFrameOffset: Int,
        plannedSongEndFrame: Int? = nil
    ) {
        _ = configureAdapterEventSchedule(
            events,
            runtimeFrameOffset: runtimeFrameOffset,
            plannedSongEndFrame: plannedSongEndFrame
        )
    }

    func drainAppliedAdapterEventDiagnostics() -> [RuntimeCMixerAppliedAdapterEventDiagnostic] {
        guard lock.try() else {
            callbackSkippedDiagnosticsDueToLockCounter.wrappingAdd(1, ordering: .relaxed)
            return []
        }
        defer {
            lock.unlock()
        }
        return appliedAdapterEventDiagnostics.drain(limit: Self.callbackDiagnosticDrainLimit)
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

    private static func runtimeFrame(plannedFrame: Int?, offset: Int) -> UInt64? {
        guard let plannedFrame else {
            return nil
        }
        let (runtimeFrame, overflow) = plannedFrame.addingReportingOverflow(offset)
        guard !overflow,
              runtimeFrame >= 0 else {
            return nil
        }
        return UInt64(runtimeFrame)
    }

    private static func songEndStopFrame(plannedSongEndFrame: Int?, tailFrames: Int) -> Int? {
        guard let plannedSongEndFrame else {
            return nil
        }
        let (frame, overflow) = plannedSongEndFrame.addingReportingOverflow(max(0, tailFrames))
        guard !overflow else {
            return nil
        }
        return frame
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
        recordLifecycleChangeIfCallbackActive()
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
            callbackLockFailureCounter.wrappingAdd(1, ordering: .relaxed)
            clear(outputInterleavedPCM)
            return false
        }
        defer {
            lock.unlock()
        }
        return renderLocked(
            into: outputInterleavedPCM,
            frameCount: safeFrameCount,
            callbackThread: callbackThread
        )
    }

    private func renderLocked(
        into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        frameCount safeFrameCount: Int,
        callbackThread: RuntimeCMixerThreadDiagnostics? = nil
    ) -> Bool {
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
        let callbackIndex = renderCallbackCount &+ 1
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
                channelCount: mixer.config.channelCount,
                callbackStartFrame: callbackStartFrame,
                callbackIndex: callbackIndex
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

    private func recordCallbackRealtimeDiagnosticsLocked(_ sample: RuntimeCMixerCallbackCounters.Sample) {
        let durationSeconds = seconds(fromNanoseconds: sample.endUptimeNanos &- sample.startUptimeNanos)
        let intervalSeconds = lastCallbackStartUptimeNanos.map { seconds(fromNanoseconds: sample.startUptimeNanos &- $0) }
        lastCallbackStartUptimeNanos = sample.startUptimeNanos
        recordCallbackRealtimeDiagnosticsLocked(
            durationSeconds: durationSeconds,
            requestedFrameCount: sample.requestedFrameCount,
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
        if quantumSeconds > 0,
           durationSeconds >= quantumSeconds * Self.callbackNearBudgetWarningRatio {
            callbackNearBudgetWarningCount &+= 1
        }

        if let intervalSeconds,
           intervalSeconds.isFinite,
           intervalSeconds >= 0 {
            callbackIntervalLastSeconds = intervalSeconds
            callbackIntervalMinSeconds = callbackIntervalMinSeconds.map { min($0, intervalSeconds) } ?? intervalSeconds
            callbackIntervalMaxSeconds = callbackIntervalMaxSeconds.map { max($0, intervalSeconds) } ?? intervalSeconds
        }
    }

    private func recordOutputBufferCopyDiagnosticsLocked(_ diagnostics: RuntimeCMixerOutputBufferCopyDiagnostics) {
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
        if adapterEventSchedule.isEmpty,
           eventQueueExhaustedFrame == nil {
            eventQueueExhaustedFrame = callbackStartFrame
        }
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
            renderSubrangeWithSongEndProbeLocked(
                into: outputInterleavedPCM,
                callbackStartFrame: callbackStartFrame,
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
            let burstStateBefore = burstRenderStateLocked()
            var burstDiagnosticCount = 0
            if let callbackThread {
                eventQueueConsumerThreadDiagnostics = callbackThread
            }
            for eventIndex in burstStartIndex..<burstEndIndex {
                let diagnostic = applyQueuedAdapterEventLocked(
                    adapterEventSchedule[eventIndex],
                    callbackIndex: callbackIndex,
                    callbackRequestedFrameCount: frameCount,
                    callbackStartFrame: callbackStartFrame,
                    callbackEndFrame: callbackEndFrame,
                    sameFrameBurstSize: sameFrameBurstSize
                )
                if burstDiagnosticCount < burstDiagnosticScratch.count {
                    burstDiagnosticScratch[burstDiagnosticCount] = diagnostic
                    burstDiagnosticCount += 1
                } else {
                    appliedAdapterEventDiagnostics.recordDrop()
                }
            }
            let burstStateAfter = burstRenderStateLocked()
            appendBurstDiagnosticsLocked(
                burstDiagnosticCount: burstDiagnosticCount,
                burstID: burstFrame <= UInt64(Int.max) ? Int(burstFrame) : Int.max,
                burstStartIndex: burstStartIndex,
                burstEndIndex: burstEndIndex,
                stateBefore: burstStateBefore,
                stateAfter: burstStateAfter
            )
            for index in 0..<burstDiagnosticCount {
                burstDiagnosticScratch[index] = nil
            }
            nextAdapterEventScheduleIndex = burstEndIndex
            if nextAdapterEventScheduleIndex >= adapterEventSchedule.count,
               eventQueueExhaustedFrame == nil {
                eventQueueExhaustedFrame = mixer.currentFrame
            }
        }

        renderSubrangeWithSongEndProbeLocked(
            into: outputInterleavedPCM,
            callbackStartFrame: callbackStartFrame,
            startFrameOffset: renderedFrames,
            frameCount: max(0, frameCount - renderedFrames)
        )
    }

    private func renderSubrangeWithSongEndProbeLocked(
        into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        callbackStartFrame: UInt64,
        startFrameOffset: Int,
        frameCount: Int
    ) {
        let safeFrameCount = max(0, frameCount)
        guard safeFrameCount > 0 else {
            return
        }
        let safeStartOffset = max(0, startFrameOffset)
        var renderedFrames = 0
        while renderedFrames < safeFrameCount {
            let absoluteOffset = safeStartOffset + renderedFrames
            let subrangeStart = callbackStartFrame.addingReportingOverflow(UInt64(absoluteOffset))
            guard !subrangeStart.overflow else {
                renderSubrangeLocked(
                    into: outputInterleavedPCM,
                    startFrameOffset: absoluteOffset,
                    frameCount: safeFrameCount - renderedFrames
                )
                return
            }
            let subrangeStartFrame = subrangeStart.partialValue
            let remainingFrames = safeFrameCount - renderedFrames
            let subrangeEnd = subrangeStartFrame.addingReportingOverflow(UInt64(remainingFrames))
            let subrangeEndFrame = subrangeEnd.overflow ? UInt64.max : subrangeEnd.partialValue

            if let plannedSongEndRuntimeFrame,
               runtimeFrameAtPlannedSongEnd == nil,
               plannedSongEndRuntimeFrame >= subrangeStartFrame,
               plannedSongEndRuntimeFrame <= subrangeEndFrame {
                let framesBeforeEnd = Int(plannedSongEndRuntimeFrame - subrangeStartFrame)
                renderSubrangeLocked(
                    into: outputInterleavedPCM,
                    startFrameOffset: absoluteOffset,
                    frameCount: framesBeforeEnd
                )
                renderedFrames += framesBeforeEnd
                recordPlannedSongEndBoundaryLocked(runtimeFrame: plannedSongEndRuntimeFrame)
                continue
            }

            if let songEndStopRuntimeFrame,
               runtimeFrameAtSongEndTailStop == nil,
               songEndStopRuntimeFrame >= subrangeStartFrame,
               songEndStopRuntimeFrame <= subrangeEndFrame {
                let framesBeforeStop = Int(songEndStopRuntimeFrame - subrangeStartFrame)
                renderSubrangeLocked(
                    into: outputInterleavedPCM,
                    startFrameOffset: absoluteOffset,
                    frameCount: framesBeforeStop
                )
                renderedFrames += framesBeforeStop
                recordSongEndTailStopBoundaryLocked(runtimeFrame: songEndStopRuntimeFrame)
                continue
            }

            renderSubrangeLocked(
                into: outputInterleavedPCM,
                startFrameOffset: absoluteOffset,
                frameCount: remainingFrames
            )
            return
        }
    }

    private func recordPlannedSongEndBoundaryLocked(runtimeFrame: UInt64) {
        guard runtimeFrameAtPlannedSongEnd == nil else {
            return
        }
        runtimeFrameAtPlannedSongEnd = runtimeFrame
        activeVoiceCountAtPlannedSongEnd = mixer.activeVoiceCount
        loadedVoiceCountAtPlannedSongEnd = mixer.loadedVoiceCount
    }

    private func recordSongEndTailStopBoundaryLocked(runtimeFrame: UInt64) {
        guard runtimeFrameAtSongEndTailStop == nil else {
            return
        }
        if runtimeFrameAtPlannedSongEnd == nil,
           let plannedSongEndRuntimeFrame,
           plannedSongEndRuntimeFrame <= runtimeFrame {
            recordPlannedSongEndBoundaryLocked(runtimeFrame: plannedSongEndRuntimeFrame)
        }
        runtimeFrameAtSongEndTailStop = runtimeFrame
        activeVoiceCountAtTailStop = mixer.activeVoiceCount
        loadedVoiceCountAtTailStop = mixer.loadedVoiceCount
        mixer.clearVoices()
        voiceStateByChannel.removeAll()
        adapterVoiceStateByEventIndex.removeAll()
        adapterEventIndexByChannel.removeAll()
        stoppedFrameByChannel.removeAll()
        nextAdapterEventScheduleIndex = adapterEventSchedule.count
        if eventQueueExhaustedFrame == nil {
            eventQueueExhaustedFrame = runtimeFrame
        }
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

    private func burstRenderStateLocked() -> RuntimeCMixerBurstRenderState {
        RuntimeCMixerBurstRenderState(
            activeVoiceCount: mixer.activeVoiceCount,
            loadedVoiceCount: mixer.loadedVoiceCount,
            rampDownStartCount: mixer.rampDownStartCount,
            rampDownCompletionCount: mixer.rampDownCompletionCount
        )
    }

    private func appendBurstDiagnosticsLocked(
        burstDiagnosticCount: Int,
        burstID: Int,
        burstStartIndex: Int,
        burstEndIndex: Int,
        stateBefore: RuntimeCMixerBurstRenderState,
        stateAfter: RuntimeCMixerBurstRenderState
    ) {
        guard burstDiagnosticCount > 0 else {
            return
        }
        var replacementRampCount = 0
        var voicesEnteringRampDownFromResults = 0
        var newVoicesStarted = 0
        var sustainedVoicesCarried = 0
        for index in 0..<burstDiagnosticCount {
            guard let diagnostic = burstDiagnosticScratch[index] else {
                continue
            }
            if diagnostic.adapterChannelAssociationRetained {
                sustainedVoicesCarried += 1
            }
            if case let .noteTrigger(result) = diagnostic.result {
                let rampedVoiceCount = result.channelStopBeforeAdd?.rampedVoiceCount ?? 0
                if rampedVoiceCount > 0 {
                    replacementRampCount += 1
                }
                voicesEnteringRampDownFromResults += rampedVoiceCount
                if result.succeeded {
                    newVoicesStarted += 1
                }
            }
        }
        let rampDownStartDelta = Self.uint64Delta(stateAfter.rampDownStartCount, stateBefore.rampDownStartCount)
        let voicesEnteringRampDown = max(voicesEnteringRampDownFromResults, rampDownStartDelta)
        let burstSummary = sameFrameBurstSummary(
            burstStartIndex: burstStartIndex,
            burstEndIndex: burstEndIndex,
            replacementRampCount: replacementRampCount
        )
        let burst = RuntimeCMixerSameFrameBurstDiagnostic(
            id: burstID,
            eventOrdinal: 0,
            categoryMask: burstSummary.categoryMask,
            affectedChannelSet: burstSummary.affectedChannelSet,
            noteTriggerCount: burstSummary.noteTriggerCount,
            replacementRampCount: replacementRampCount,
            gainPanUpdateCount: burstSummary.gainPanUpdateCount,
            stepUpdateCount: burstSummary.stepUpdateCount,
            noteCutCount: burstSummary.noteCutCount,
            keyOffCount: burstSummary.keyOffCount,
            globalVolumeUpdateCount: burstSummary.globalVolumeUpdateCount,
            activeVoiceCountBefore: stateBefore.activeVoiceCount,
            activeVoiceCountAfter: stateAfter.activeVoiceCount,
            loadedVoiceCountBefore: stateBefore.loadedVoiceCount,
            loadedVoiceCountAfter: stateAfter.loadedVoiceCount,
            voicesEnteringRampDown: voicesEnteringRampDown,
            voicesCompletingRampDown: Self.uint64Delta(stateAfter.rampDownCompletionCount, stateBefore.rampDownCompletionCount),
            newVoicesStarted: newVoicesStarted,
            sustainedVoicesCarried: sustainedVoicesCarried,
            atOrderStart: burstSummary.atOrderStart,
            atRowTransition: burstSummary.atRowTransition
        )
        let voicesCompletingRampDown = Self.uint64Delta(stateAfter.rampDownCompletionCount, stateBefore.rampDownCompletionCount)
        for index in 0..<burstDiagnosticCount {
            guard let diagnostic = burstDiagnosticScratch[index] else {
                continue
            }
            appliedAdapterEventDiagnostics.record(RuntimeCMixerAppliedAdapterEventDiagnostic(
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
                    categoryMask: burst.categoryMask,
                    affectedChannelSet: burst.affectedChannelSet,
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

    private struct RuntimeCMixerSameFrameBurstSummary {
        let categoryMask: UInt32
        let affectedChannelSet: RuntimeCMixerAffectedChannelSet
        let noteTriggerCount: Int
        let gainPanUpdateCount: Int
        let stepUpdateCount: Int
        let noteCutCount: Int
        let keyOffCount: Int
        let globalVolumeUpdateCount: Int
        let atOrderStart: Bool
        let atRowTransition: Bool
    }

    private func sameFrameBurstSummary(
        burstStartIndex: Int,
        burstEndIndex: Int,
        replacementRampCount: Int
    ) -> RuntimeCMixerSameFrameBurstSummary {
        var categoryMask: UInt32 = 0
        var affectedChannelSet = RuntimeCMixerAffectedChannelSet()
        var noteTriggerCount = 0
        var gainPanUpdateCount = 0
        var stepUpdateCount = 0
        var noteCutCount = 0
        var keyOffCount = 0
        var globalVolumeUpdateCount = 0
        var atOrderStart = false
        var atRowTransition = false
        for index in burstStartIndex..<burstEndIndex {
            let event = adapterEventSchedule[index].event
            affectedChannelSet.insert(event.channelIndex)
            atOrderStart = atOrderStart || (event.source.rowIndex == 0 && event.syntheticTick == 0)
            atRowTransition = atRowTransition || event.syntheticTick == 0
            switch event.action {
            case .noteTrigger:
                noteTriggerCount += 1
            case .gainPanUpdate:
                gainPanUpdateCount += 1
            case .stepUpdate:
                stepUpdateCount += 1
            case .noteCut:
                noteCutCount += 1
            }
            if event.categories.contains("key_off") {
                keyOffCount += 1
            }
            if event.categories.contains("global_volume_update") {
                globalVolumeUpdateCount += 1
            }
            for category in event.categories {
                categoryMask |= RuntimeCMixerSameFrameBurstDiagnostic.categoryMask(for: category)
            }
        }
        if replacementRampCount > 0 {
            categoryMask |= RuntimeCMixerSameFrameBurstDiagnostic.categoryMask(for: "replacement_stop_ramp")
        }
        return RuntimeCMixerSameFrameBurstSummary(
            categoryMask: categoryMask,
            affectedChannelSet: affectedChannelSet,
            noteTriggerCount: noteTriggerCount,
            gainPanUpdateCount: gainPanUpdateCount,
            stepUpdateCount: stepUpdateCount,
            noteCutCount: noteCutCount,
            keyOffCount: keyOffCount,
            globalVolumeUpdateCount: globalVolumeUpdateCount,
            atOrderStart: atOrderStart,
            atRowTransition: atRowTransition
        )
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
        let realtimeState = RuntimeCMixerRealtimeState.begin(requestedFrameCount: safeFrameCount)
        callbackActiveRenderDepth.wrappingAdd(1, ordering: .relaxed)
        defer {
            callbackActiveRenderDepth.wrappingSubtract(1, ordering: .relaxed)
        }

        // Audio callback safety rules: no AppKit, no parsing, no file I/O, no diagnostics logging, and no
        // allocation-heavy work. Voice/sample preparation happens on the main side before this callback.
        clear(ioData: ioData, frameCount: safeFrameCount)
        guard safeFrameCount > 0 else {
            recordRealtimeCallbackSample(realtimeState.finish())
            return noErr
        }
        guard safeFrameCount <= maximumRenderFrames else {
            recordZeroFillCallback(
                frameCount: safeFrameCount,
                callbackThread: realtimeState.callbackThread,
                realtimeSample: realtimeState.finish()
            )
            return noErr
        }

        let sampleCount = safeFrameCount * mixer.config.channelCount
        callbackLockAttemptCounter.wrappingAdd(1, ordering: .relaxed)
        guard lock.try() else {
            callbackLockFailureCounter.wrappingAdd(1, ordering: .relaxed)
            callbackSkippedDiagnosticsDueToLockCounter.wrappingAdd(1, ordering: .relaxed)
            if copyLastCallbackOutputToAudioBuffers(ioData: ioData, frameCount: safeFrameCount) {
                callbackRenderedFromStaleSnapshotCounter.wrappingAdd(1, ordering: .relaxed)
            }
            return noErr
        }
        defer {
            lock.unlock()
        }
        let rendered = scratchInterleavedPCM.withUnsafeMutableBufferPointer { scratch in
            renderLocked(
                into: UnsafeMutableBufferPointer(start: scratch.baseAddress, count: sampleCount),
                frameCount: safeFrameCount,
                callbackThread: realtimeState.callbackThread
            )
        }
        if rendered {
            storeLastCallbackOutputLocked(frameCount: safeFrameCount, sampleCount: sampleCount)
            let copyDiagnostics = copyScratchToAudioBuffersLocked(ioData: ioData, frameCount: safeFrameCount)
            recordOutputBufferCopyDiagnosticsLocked(copyDiagnostics)
        }
        recordCallbackRealtimeDiagnosticsLocked(realtimeState.finish())
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
        plannedSongEndFrame = nil
        plannedSongEndRuntimeFrame = nil
        songEndStopFrame = nil
        songEndStopRuntimeFrame = nil
        runtimeFrameAtPlannedSongEnd = nil
        runtimeFrameAtSongEndTailStop = nil
        activeVoiceCountAtPlannedSongEnd = nil
        loadedVoiceCountAtPlannedSongEnd = nil
        activeVoiceCountAtTailStop = nil
        loadedVoiceCountAtTailStop = nil
        eventQueueExhaustedFrame = nil
        eventQueueProducerThreadDiagnostics = nil
        eventQueueConsumerThreadDiagnostics = nil
        appliedAdapterEventDiagnostics.removeAll()
        lastCaptureSummary = nil
        lastOutputBufferCopyDiagnostics = nil
        callbackLockAttemptCounter.store(0, ordering: .relaxed)
        callbackLockFailureCounter.store(0, ordering: .relaxed)
        callbackRenderedFromStaleSnapshotCounter.store(0, ordering: .relaxed)
        callbackRenderedSilenceDueToUnavailableStateCounter.store(0, ordering: .relaxed)
        callbackSkippedDiagnosticsDueToLockCounter.store(0, ordering: .relaxed)
        callbackSkippedAudioDueToLockCounter.store(0, ordering: .relaxed)
        lifecycleChangeWhileRenderingCounter.store(0, ordering: .relaxed)
        audioUnitLifecycleCallWhileCallbackActiveCounter.store(0, ordering: .relaxed)
        lastCallbackOutputFrameCountAtomic.store(0, ordering: .relaxed)
        realtimeCurrentFrameCounter.store(0, ordering: .relaxed)
        appliedPlannedEventCount = 0
        exactFrameAppliedEventCount = 0
        callbackBoundaryAppliedEventCount = 0
        latePlannedEventCount = 0
        maxPlannedVsAppliedDelta = 0
    }

    private func recordRealtimeCallbackSample(_ realtimeSample: RuntimeCMixerCallbackCounters.Sample) {
        callbackLockAttemptCounter.wrappingAdd(1, ordering: .relaxed)
        guard lock.try() else {
            callbackLockFailureCounter.wrappingAdd(1, ordering: .relaxed)
            callbackSkippedDiagnosticsDueToLockCounter.wrappingAdd(1, ordering: .relaxed)
            return
        }
        defer {
            lock.unlock()
        }
        recordCallbackRealtimeDiagnosticsLocked(realtimeSample)
    }

    private func recordZeroFillCallback(
        frameCount: Int,
        callbackThread: RuntimeCMixerThreadDiagnostics? = nil,
        realtimeSample: RuntimeCMixerCallbackCounters.Sample? = nil
    ) {
        callbackLockAttemptCounter.wrappingAdd(1, ordering: .relaxed)
        guard lock.try() else {
            callbackLockFailureCounter.wrappingAdd(1, ordering: .relaxed)
            callbackSkippedDiagnosticsDueToLockCounter.wrappingAdd(1, ordering: .relaxed)
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
            outputMetrics: .silence,
            callbackThread: callbackThread
        )
        if let realtimeSample {
            recordCallbackRealtimeDiagnosticsLocked(realtimeSample)
        }
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

#if DEBUG
    func withRenderLockHeldForTesting(_ body: () -> Void) {
        lock.lock()
        defer {
            lock.unlock()
        }
        body()
    }

    func withRenderCallbackActiveForTesting(_ body: () -> Void) {
        callbackActiveRenderDepth.wrappingAdd(1, ordering: .relaxed)
        defer {
            callbackActiveRenderDepth.wrappingSubtract(1, ordering: .relaxed)
        }
        body()
    }
#endif

    var isRenderCallbackActive: Bool {
        callbackActiveRenderDepth.load(ordering: .relaxed) > 0
    }

    var realtimeCurrentFrame: UInt64 {
        realtimeCurrentFrameCounter.load(ordering: .relaxed)
    }

    func recordAudioUnitLifecycleCallIfCallbackActive() {
        if isRenderCallbackActive {
            audioUnitLifecycleCallWhileCallbackActiveCounter.wrappingAdd(1, ordering: .relaxed)
        }
    }

    private func recordLifecycleChangeIfCallbackActive() {
        if isRenderCallbackActive {
            lifecycleChangeWhileRenderingCounter.wrappingAdd(1, ordering: .relaxed)
        }
    }

    private func snapshotLocked() -> RuntimeCMixerRenderSnapshot {
        let rms = cumulativeOutputSampleCount > 0
            ? Float(sqrt(cumulativeOutputSquareSum / Double(cumulativeOutputSampleCount)))
            : 0
        let eventQueueExhausted = adapterEventSchedule.isEmpty || nextAdapterEventScheduleIndex >= adapterEventSchedule.count
        let activeAfterSongEnd: Int?
        let loadedAfterSongEnd: Int?
        if let plannedSongEndRuntimeFrame,
           mixer.currentFrame > plannedSongEndRuntimeFrame {
            activeAfterSongEnd = mixer.activeVoiceCount
            loadedAfterSongEnd = mixer.loadedVoiceCount
        } else {
            activeAfterSongEnd = nil
            loadedAfterSongEnd = nil
        }
        let outputContinuesAfterSongEnd = activeAfterSongEnd.map { $0 > 0 || (loadedAfterSongEnd ?? 0) > 0 }
        let sustainedAfterSongEnd = outputContinuesAfterSongEnd.map { $0 && eventQueueExhausted }
        let callbackDurationMaxMS = callbackDurationMaxSeconds.map(milliseconds)
        let callbackDurationAverageMS = callbackDurationSampleCount > 0
            ? milliseconds(callbackDurationTotalSeconds / Double(callbackDurationSampleCount))
            : nil
        let callbackLockAttemptCount = callbackLockAttemptCounter.load(ordering: .relaxed)
        let callbackTryLockFailureCount = callbackLockFailureCounter.load(ordering: .relaxed)
        let callbackRenderedFromStaleSnapshotCount = callbackRenderedFromStaleSnapshotCounter.load(ordering: .relaxed)
        let callbackRenderedSilenceDueToUnavailableStateCount =
            callbackRenderedSilenceDueToUnavailableStateCounter.load(ordering: .relaxed)
        let callbackSkippedAudioDueToLockCount = callbackSkippedAudioDueToLockCounter.load(ordering: .relaxed)
        let callbackLockFailureAudioImpact: Bool? = callbackTryLockFailureCount > 0
            ? callbackSkippedAudioDueToLockCount > 0 ||
                callbackRenderedFromStaleSnapshotCount > 0 ||
                callbackRenderedSilenceDueToUnavailableStateCount > 0
            : nil
        return RuntimeCMixerRenderSnapshot(
            sampleRate: mixer.config.sampleRate,
            channelCount: mixer.config.channelCount,
            activeVoiceCount: mixer.activeVoiceCount,
            loadedVoiceCount: mixer.loadedVoiceCount,
            scheduledVoiceCount: 0,
            eventQueueBacklogCount: max(0, adapterEventSchedule.count - nextAdapterEventScheduleIndex),
            eventQueueExhausted: eventQueueExhausted,
            eventQueueExhaustedFrame: eventQueueExhaustedFrame,
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
            callbackDurationMaxMS: callbackDurationMaxMS,
            callbackDurationAverageMS: callbackDurationAverageMS,
            callbackMaxDurationMS: callbackDurationMaxMS,
            callbackAvgDurationMS: callbackDurationAverageMS,
            callbackDurationWarningCount: callbackDurationWarningCount,
            callbackRenderQuantumDurationMS: callbackRenderQuantumLastSeconds.map(milliseconds),
            callbackRenderQuantumMinMS: callbackRenderQuantumMinSeconds.map(milliseconds),
            callbackRenderQuantumMaxMS: callbackRenderQuantumMaxSeconds.map(milliseconds),
            callbackOverRenderQuantumBudgetCount: callbackOverRenderQuantumBudgetCount,
            callbackNearBudgetWarningCount: callbackNearBudgetWarningCount,
            callbackIntervalMinMS: callbackIntervalMinSeconds.map(milliseconds),
            callbackIntervalMaxMS: callbackIntervalMaxSeconds.map(milliseconds),
            callbackIntervalLastMS: callbackIntervalLastSeconds.map(milliseconds),
            callbackThreadIsMain: lastCallbackThreadDiagnostics?.isMainThread,
            callbackThreadID: lastCallbackThreadDiagnostics?.threadID,
            callbackMainThreadDependencyDetected: callbackMainThreadInvocationCount > 0,
            callbackAllocationWarning: false,
            callbackRealtimeSafeDiagnostics: true,
            callbackDiagnosticDropCount: appliedAdapterEventDiagnostics.droppedCount,
            callbackRingBufferCapacity: appliedAdapterEventDiagnostics.capacity,
            callbackLockWaitCount: 0,
            callbackLockWaitDurationMS: 0,
            callbackLockFailureCount: callbackTryLockFailureCount,
            callbackLockAttemptCount: callbackLockAttemptCount,
            callbackTryLockFailureCount: callbackTryLockFailureCount,
            callbackLockFailureAudioImpact: callbackLockFailureAudioImpact,
            callbackRenderedFromStaleSnapshotCount: callbackRenderedFromStaleSnapshotCount,
            callbackRenderedSilenceDueToUnavailableStateCount: callbackRenderedSilenceDueToUnavailableStateCount,
            callbackSkippedDiagnosticsDueToLockCount: callbackSkippedDiagnosticsDueToLockCounter.load(ordering: .relaxed),
            callbackSkippedAudioDueToLockCount: callbackSkippedAudioDueToLockCount,
            lifecycleChangeWhileRenderingCount: lifecycleChangeWhileRenderingCounter.load(ordering: .relaxed),
            audioUnitLifecycleCallWhileCallbackActiveCount: audioUnitLifecycleCallWhileCallbackActiveCounter.load(ordering: .relaxed),
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
            topOutputAdjacentSampleJumps: topOutputAdjacentSampleJumps.values,
            lastOutputDiscontinuitySampleJump: lastOutputDiscontinuitySampleJump,
            lastOutputDiscontinuityCallbackIndex: lastOutputDiscontinuityCallbackIndex,
            lastOutputDiscontinuityRuntimeFrame: lastOutputDiscontinuityRuntimeFrame,
            lastOutputDiscontinuityFrameOffset: lastOutputDiscontinuityFrameOffset,
            lastOutputDiscontinuityChannelIndex: lastOutputDiscontinuityChannelIndex,
            outputPeakWarningThreshold: Self.outputPeakWarningThreshold,
            outputPeakWarningSampleCount: outputPeakWarningSampleCount,
            topOutputPeaks: topOutputPeaks.values,
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
            plannedSongEndFrame: plannedSongEndFrame,
            plannedSongEndRuntimeFrame: plannedSongEndRuntimeFrame,
            runtimeFrameAtPlannedSongEnd: runtimeFrameAtPlannedSongEnd,
            runtimeTailSeconds: songEndTailPolicy.tailSeconds,
            runtimeTailFrames: runtimeTailFrames,
            runtimeTailPolicy: songEndTailPolicy.tailPolicy,
            runtimeTailConfigurationWarning: songEndTailPolicy.configurationWarning,
            songEndStopFrame: songEndStopFrame,
            songEndStopRuntimeFrame: songEndStopRuntimeFrame,
            runtimeFrameAtSongEndTailStop: runtimeFrameAtSongEndTailStop,
            activeVoiceCountAtPlannedSongEnd: activeVoiceCountAtPlannedSongEnd,
            loadedVoiceCountAtPlannedSongEnd: loadedVoiceCountAtPlannedSongEnd,
            activeVoiceCountAtTailStop: activeVoiceCountAtTailStop,
            loadedVoiceCountAtTailStop: loadedVoiceCountAtTailStop,
            activeVoiceCountAfterPlannedSongEnd: activeAfterSongEnd,
            loadedVoiceCountAfterPlannedSongEnd: loadedAfterSongEnd,
            outputContinuesAfterPlannedSongEnd: outputContinuesAfterSongEnd,
            finalSustainedVoicesContinueAfterPlannedSongEnd: sustainedAfterSongEnd,
            songEndTailStopReached: runtimeFrameAtSongEndTailStop != nil,
            captureCapTriggeredPlaybackStop: false,
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
        realtimeCurrentFrameCounter.store(callbackEndFrame, ordering: .relaxed)
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

    private func insertTopOutputAdjacentSampleJumpLocked(_ row: RuntimeCMixerTopOutputSampleJump) {
        topOutputAdjacentSampleJumps.record(row, precedes: topOutputAdjacentSampleJumpPrecedes)
    }

    private func insertTopOutputPeakLocked(_ row: RuntimeCMixerTopOutputPeak) {
        topOutputPeaks.record(row, precedes: topOutputPeakPrecedes)
    }

    private func topOutputAdjacentSampleJumpPrecedes(
        _ lhs: RuntimeCMixerTopOutputSampleJump,
        _ rhs: RuntimeCMixerTopOutputSampleJump
    ) -> Bool {
        if lhs.sampleJump != rhs.sampleJump {
            return lhs.sampleJump > rhs.sampleJump
        }
        if lhs.runtimeFrame != rhs.runtimeFrame {
            return lhs.runtimeFrame < rhs.runtimeFrame
        }
        return lhs.channelIndex < rhs.channelIndex
    }

    private func topOutputPeakPrecedes(
        _ lhs: RuntimeCMixerTopOutputPeak,
        _ rhs: RuntimeCMixerTopOutputPeak
    ) -> Bool {
        if lhs.peak != rhs.peak {
            return lhs.peak > rhs.peak
        }
        if lhs.runtimeFrame != rhs.runtimeFrame {
            return lhs.runtimeFrame < rhs.runtimeFrame
        }
        return lhs.channelIndex < rhs.channelIndex
    }

    private func outputMetrics(
        _ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        sampleCount: Int,
        channelCount: Int,
        callbackStartFrame: UInt64,
        callbackIndex: UInt64
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
        var maxDiscontinuitySampleJump: Float?
        var maxDiscontinuityFrameOffset: Int?
        var maxDiscontinuityChannelIndex: Int?
        var peakWarningCount = 0
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
            let peakRuntimeFrame = callbackStartFrame.addingReportingOverflow(UInt64(max(0, frameOffset)))
            insertTopOutputPeakLocked(
                RuntimeCMixerTopOutputPeak(
                    peak: absolute,
                    runtimeFrame: peakRuntimeFrame.overflow ? UInt64.max : peakRuntimeFrame.partialValue,
                    callbackIndex: callbackIndex,
                    frameOffset: frameOffset,
                    channelIndex: channelIndex
                )
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
                let jumpRuntimeFrame = callbackStartFrame.addingReportingOverflow(UInt64(max(0, frameOffset)))
                insertTopOutputAdjacentSampleJumpLocked(
                    RuntimeCMixerTopOutputSampleJump(
                        sampleJump: sampleJump,
                        runtimeFrame: jumpRuntimeFrame.overflow ? UInt64.max : jumpRuntimeFrame.partialValue,
                        callbackIndex: callbackIndex,
                        frameOffset: frameOffset,
                        channelIndex: channelIndex
                    )
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
            maxDiscontinuityFrameOffset: maxDiscontinuityFrameOffset,
            maxDiscontinuityChannelIndex: maxDiscontinuityChannelIndex,
            maxDiscontinuitySampleJump: maxDiscontinuitySampleJump,
            peakWarningSampleCount: peakWarningCount,
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
            effectType = event.effectType
            effectParam = event.effectParam
            volumeColumn = event.volumeColumn
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

    private func storeLastCallbackOutputLocked(frameCount: Int, sampleCount: Int) {
        let safeSampleCount = min(max(0, sampleCount), scratchInterleavedPCM.count, lastCallbackOutputInterleavedPCM.count)
        guard safeSampleCount > 0 else {
            lastCallbackOutputFrameCountAtomic.store(0, ordering: .relaxed)
            return
        }
        for index in 0..<safeSampleCount {
            lastCallbackOutputInterleavedPCM[index] = scratchInterleavedPCM[index]
        }
        let storedFrameCount = min(max(0, frameCount), safeSampleCount / max(1, mixer.config.channelCount))
        lastCallbackOutputFrameCountAtomic.store(UInt64(storedFrameCount), ordering: .relaxed)
    }

    private func copyLastCallbackOutputToAudioBuffers(
        ioData: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) -> Bool {
        let channelCount = mixer.config.channelCount
        let availableFrameCount = min(
            Int(clamping: lastCallbackOutputFrameCountAtomic.load(ordering: .relaxed)),
            maximumRenderFrames
        )
        guard frameCount > 0,
              channelCount > 0,
              availableFrameCount > 0 else {
            clear(ioData: ioData, frameCount: frameCount)
            callbackRenderedSilenceDueToUnavailableStateCounter.wrappingAdd(1, ordering: .relaxed)
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        var copiedSampleCount = 0
        if buffers.count == 1,
           let data = buffers[0].mData,
           Int(buffers[0].mNumberChannels) == channelCount {
            let availableSampleCount = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
            let requestedSampleCount = max(0, frameCount) * channelCount
            let sampleCount = min(availableSampleCount, requestedSampleCount)
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<max(0, frameCount) {
                let sourceFrame = frame % availableFrameCount
                for channel in 0..<channelCount {
                    let outputIndex = frame * channelCount + channel
                    guard outputIndex < sampleCount else {
                        break
                    }
                    output[outputIndex] = lastCallbackOutputInterleavedPCM[(sourceFrame * channelCount) + channel]
                    copiedSampleCount += 1
                }
            }
            return copiedSampleCount > 0
        }

        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else {
                continue
            }
            let bufferChannelCount = max(1, Int(buffer.mNumberChannels))
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<max(0, frameCount) {
                let sourceFrame = frame % availableFrameCount
                for bufferChannel in 0..<bufferChannelCount {
                    let outputIndex = frame * bufferChannelCount + bufferChannel
                    guard outputIndex < availableSampleCount else {
                        break
                    }
                    let sourceChannel = buffers.count == channelCount ? bufferIndex : bufferChannel
                    output[outputIndex] = sourceChannel < channelCount
                        ? lastCallbackOutputInterleavedPCM[(sourceFrame * channelCount) + sourceChannel]
                        : 0
                    if sourceChannel < channelCount {
                        copiedSampleCount += 1
                    }
                }
            }
        }
        return copiedSampleCount > 0
    }

    private func copyScratchToAudioBuffersLocked(
        ioData: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) -> RuntimeCMixerOutputBufferCopyDiagnostics {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        let channelCount = mixer.config.channelCount
        let captureSummary = callbackDiagnostics.outputBufferVerificationEnabled
            ? lastCaptureSummary
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
