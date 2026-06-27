import Foundation
import os

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
    let adapterPlanGenerationMS: Double?
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
    let runtimeOutputHostType: String?
    let runtimeOutputHostRunning: Bool?
    let runtimeOutputHostStartCount: UInt64?
    let runtimeOutputHostPrepareStatus: Int?
    let runtimeOutputHostInitializeStatus: Int?
    let runtimeOutputHostStartStatus: Int?
    let runtimeOutputHostStopStatus: Int?
    let runtimeOutputHostLastErrorStatus: Int?
    let debugStopAfterSeconds: Double?
    let sampleRate: Double?
    let selectedRuntimeSampleRate: Double?
    let cMixerRuntimeSampleRate: Double?
    let runtimeSampleRatePolicy: String?
    let runtimeSampleRateSource: String?
    let runtimeSampleRateConfigurationWarning: String?
    let cMixerRenderSampleRate: Double?
    let cMixerRenderChannelCount: Int?
    let audioHardwareNominalSampleRate: Double?
    let audioHardwareDeviceID: UInt32?
    let audioHardwareDeviceUIDHash: String?
    let audioOutputRouteLabel: String?
    let audioHardwareIOBufferFrameSize: UInt32?
    let audioHardwareIOBufferDuration: Double?
    let audioHardwareLatencyFrames: UInt32?
    let audioHardwareLatencyDuration: Double?
    let audioHardwareSafetyOffsetFrames: UInt32?
    let audioHardwareSafetyOffsetDuration: Double?
    let audioHardwareTransportType: UInt32?
    let audioHardwareTransportTypeName: String?
    let audioGraphFormatChangeCount: UInt64?
    let audioOutputRouteChangeCount: UInt64?
    let audioGraphFormatChanged: Bool?
    let audioOutputRouteChanged: Bool?
    let audioOutputDeviceChanged: Bool?
    let audioOutputSampleRateChanged: Bool?
    let audioOutputChannelCountChanged: Bool?
    let audioHardwareIOBufferDurationChanged: Bool?
    let audioFormatConversionLikely: Bool?
    let runtimeCaptureMatchesHardwareSampleRate: Bool?
    let cMixerRenderedFrames: UInt64?
    let cMixerPlaybackSeconds: Double?
    let cMixerRenderedFramesBeforeClear: UInt64?
    let cMixerPlaybackSecondsBeforeClear: Double?
    let plannedSongEndFrame: Int?
    let plannedSongEndSeconds: Double?
    let plannedSongEndRuntimeFrame: UInt64?
    let plannedSongEndRuntimeSeconds: Double?
    let runtimeFrameAtPlannedSongEnd: UInt64?
    let runtimeSecondsAtPlannedSongEnd: Double?
    let runtimeTailSeconds: Double?
    let runtimeTailFrames: Int?
    let runtimeTailPolicy: String?
    let runtimeTailConfigurationWarning: String?
    let songEndStopFrame: Int?
    let songEndStopSeconds: Double?
    let songEndStopRuntimeFrame: UInt64?
    let songEndStopRuntimeSeconds: Double?
    let runtimeFrameAtSongEndTailStop: UInt64?
    let runtimeSecondsAtSongEndTailStop: Double?
    let eventQueueExhausted: Bool?
    let eventQueueExhaustedFrame: UInt64?
    let eventQueueExhaustedSeconds: Double?
    let activeVoiceCountAtPlannedSongEnd: Int?
    let loadedVoiceCountAtPlannedSongEnd: Int?
    let activeVoiceCountAtTailStop: Int?
    let loadedVoiceCountAtTailStop: Int?
    let activeVoiceCountAfterPlannedSongEnd: Int?
    let loadedVoiceCountAfterPlannedSongEnd: Int?
    let outputContinuesAfterPlannedSongEnd: Bool?
    let finalSustainedVoicesContinueAfterPlannedSongEnd: Bool?
    let captureSeconds: Double?
    let captureEndFrame: Int?
    let captureTruncated: Bool?
    let captureCapTriggeredPlaybackStop: Bool?
    let stopReason: String?
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
    let followPublishedCount: UInt64?
    let followConsumedCount: UInt64?
    let followDroppedCount: UInt64?
    let followSuppressedCount: UInt64?
    let followUnresolvedPositionCount: UInt64?
    let followLastPublishedOrder: Int?
    let followLastPublishedRow: Int?
    let followLastPublishedTick: Int?
    let followLastConsumedOrder: Int?
    let followLastConsumedRow: Int?
    let followLastConsumedTick: Int?
    let followSampleFrame: Int?
    let followResolverFailureReason: String?
    let followFreezeDetected: Bool?
    let directStartOffsetFrame: Int?
    let resolverTimelineStartOrder: Int?
    let resolverTimelineBaseFrame: Int?
    let resolverMaxFrame: Int?
    let resolverEndReached: Bool?
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
    let callbackMaxDurationMS: Double?
    let callbackAvgDurationMS: Double?
    let callbackDurationWarningCount: UInt64?
    let callbackRenderQuantumDurationMS: Double?
    let callbackRenderQuantumMinMS: Double?
    let callbackRenderQuantumMaxMS: Double?
    let callbackOverRenderQuantumBudgetCount: UInt64?
    let callbackNearBudgetWarningCount: UInt64?
    let callbackIntervalMinMS: Double?
    let callbackIntervalMaxMS: Double?
    let callbackIntervalLastMS: Double?
    let callbackThreadIsMain: Bool?
    let callbackThreadID: UInt64?
    let callbackMainThreadDependencyDetected: Bool?
    let callbackAllocationWarning: Bool?
    let callbackRealtimeSafeDiagnostics: Bool?
    let callbackDiagnosticDropCount: UInt64?
    let callbackRingBufferCapacity: Int?
    let callbackLockWaitCount: UInt64?
    let callbackLockWaitDurationMS: Double?
    let callbackLockFailureCount: UInt64?
    let callbackLockAttemptCount: UInt64?
    let callbackTryLockFailureCount: UInt64?
    let callbackLockFailureAudioImpact: Bool?
    let callbackRenderedFromStaleSnapshotCount: UInt64?
    let callbackRenderedSilenceDueToUnavailableStateCount: UInt64?
    let callbackSkippedDiagnosticsDueToLockCount: UInt64?
    let callbackSkippedAudioDueToLockCount: UInt64?
    let lifecycleChangeWhileRenderingCount: UInt64?
    let audioUnitLifecycleCallWhileCallbackActiveCount: UInt64?
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
        adapterPlanGenerationMS: Double? = nil,
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
        runtimeOutputHostType: String? = nil,
        runtimeOutputHostRunning: Bool? = nil,
        runtimeOutputHostStartCount: UInt64? = nil,
        runtimeOutputHostPrepareStatus: Int? = nil,
        runtimeOutputHostInitializeStatus: Int? = nil,
        runtimeOutputHostStartStatus: Int? = nil,
        runtimeOutputHostStopStatus: Int? = nil,
        runtimeOutputHostLastErrorStatus: Int? = nil,
        debugStopAfterSeconds: Double? = nil,
        sampleRate: Double? = nil,
        selectedRuntimeSampleRate: Double? = nil,
        cMixerRuntimeSampleRate: Double? = nil,
        runtimeSampleRatePolicy: String? = nil,
        runtimeSampleRateSource: String? = nil,
        runtimeSampleRateConfigurationWarning: String? = nil,
        cMixerRenderSampleRate: Double? = nil,
        cMixerRenderChannelCount: Int? = nil,
        audioHardwareNominalSampleRate: Double? = nil,
        audioHardwareDeviceID: UInt32? = nil,
        audioHardwareDeviceUIDHash: String? = nil,
        audioOutputRouteLabel: String? = nil,
        audioHardwareIOBufferFrameSize: UInt32? = nil,
        audioHardwareIOBufferDuration: Double? = nil,
        audioHardwareLatencyFrames: UInt32? = nil,
        audioHardwareLatencyDuration: Double? = nil,
        audioHardwareSafetyOffsetFrames: UInt32? = nil,
        audioHardwareSafetyOffsetDuration: Double? = nil,
        audioHardwareTransportType: UInt32? = nil,
        audioHardwareTransportTypeName: String? = nil,
        audioGraphFormatChangeCount: UInt64? = nil,
        audioOutputRouteChangeCount: UInt64? = nil,
        audioGraphFormatChanged: Bool? = nil,
        audioOutputRouteChanged: Bool? = nil,
        audioOutputDeviceChanged: Bool? = nil,
        audioOutputSampleRateChanged: Bool? = nil,
        audioOutputChannelCountChanged: Bool? = nil,
        audioHardwareIOBufferDurationChanged: Bool? = nil,
        audioFormatConversionLikely: Bool? = nil,
        runtimeCaptureMatchesHardwareSampleRate: Bool? = nil,
        cMixerRenderedFrames: UInt64? = nil,
        cMixerPlaybackSeconds: Double? = nil,
        cMixerRenderedFramesBeforeClear: UInt64? = nil,
        cMixerPlaybackSecondsBeforeClear: Double? = nil,
        plannedSongEndFrame: Int? = nil,
        plannedSongEndSeconds: Double? = nil,
        plannedSongEndRuntimeFrame: UInt64? = nil,
        plannedSongEndRuntimeSeconds: Double? = nil,
        runtimeFrameAtPlannedSongEnd: UInt64? = nil,
        runtimeSecondsAtPlannedSongEnd: Double? = nil,
        runtimeTailSeconds: Double? = nil,
        runtimeTailFrames: Int? = nil,
        runtimeTailPolicy: String? = nil,
        runtimeTailConfigurationWarning: String? = nil,
        songEndStopFrame: Int? = nil,
        songEndStopSeconds: Double? = nil,
        songEndStopRuntimeFrame: UInt64? = nil,
        songEndStopRuntimeSeconds: Double? = nil,
        runtimeFrameAtSongEndTailStop: UInt64? = nil,
        runtimeSecondsAtSongEndTailStop: Double? = nil,
        eventQueueExhausted: Bool? = nil,
        eventQueueExhaustedFrame: UInt64? = nil,
        eventQueueExhaustedSeconds: Double? = nil,
        activeVoiceCountAtPlannedSongEnd: Int? = nil,
        loadedVoiceCountAtPlannedSongEnd: Int? = nil,
        activeVoiceCountAtTailStop: Int? = nil,
        loadedVoiceCountAtTailStop: Int? = nil,
        activeVoiceCountAfterPlannedSongEnd: Int? = nil,
        loadedVoiceCountAfterPlannedSongEnd: Int? = nil,
        outputContinuesAfterPlannedSongEnd: Bool? = nil,
        finalSustainedVoicesContinueAfterPlannedSongEnd: Bool? = nil,
        captureSeconds: Double? = nil,
        captureEndFrame: Int? = nil,
        captureTruncated: Bool? = nil,
        captureCapTriggeredPlaybackStop: Bool? = nil,
        stopReason: String? = nil,
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
        followPublishedCount: UInt64? = nil,
        followConsumedCount: UInt64? = nil,
        followDroppedCount: UInt64? = nil,
        followSuppressedCount: UInt64? = nil,
        followUnresolvedPositionCount: UInt64? = nil,
        followLastPublishedOrder: Int? = nil,
        followLastPublishedRow: Int? = nil,
        followLastPublishedTick: Int? = nil,
        followLastConsumedOrder: Int? = nil,
        followLastConsumedRow: Int? = nil,
        followLastConsumedTick: Int? = nil,
        followSampleFrame: Int? = nil,
        followResolverFailureReason: String? = nil,
        followFreezeDetected: Bool? = nil,
        directStartOffsetFrame: Int? = nil,
        resolverTimelineStartOrder: Int? = nil,
        resolverTimelineBaseFrame: Int? = nil,
        resolverMaxFrame: Int? = nil,
        resolverEndReached: Bool? = nil,
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
        callbackMaxDurationMS: Double? = nil,
        callbackAvgDurationMS: Double? = nil,
        callbackDurationWarningCount: UInt64? = nil,
        callbackRenderQuantumDurationMS: Double? = nil,
        callbackRenderQuantumMinMS: Double? = nil,
        callbackRenderQuantumMaxMS: Double? = nil,
        callbackOverRenderQuantumBudgetCount: UInt64? = nil,
        callbackNearBudgetWarningCount: UInt64? = nil,
        callbackIntervalMinMS: Double? = nil,
        callbackIntervalMaxMS: Double? = nil,
        callbackIntervalLastMS: Double? = nil,
        callbackThreadIsMain: Bool? = nil,
        callbackThreadID: UInt64? = nil,
        callbackMainThreadDependencyDetected: Bool? = nil,
        callbackAllocationWarning: Bool? = nil,
        callbackRealtimeSafeDiagnostics: Bool? = nil,
        callbackDiagnosticDropCount: UInt64? = nil,
        callbackRingBufferCapacity: Int? = nil,
        callbackLockWaitCount: UInt64? = nil,
        callbackLockWaitDurationMS: Double? = nil,
        callbackLockFailureCount: UInt64? = nil,
        callbackLockAttemptCount: UInt64? = nil,
        callbackTryLockFailureCount: UInt64? = nil,
        callbackLockFailureAudioImpact: Bool? = nil,
        callbackRenderedFromStaleSnapshotCount: UInt64? = nil,
        callbackRenderedSilenceDueToUnavailableStateCount: UInt64? = nil,
        callbackSkippedDiagnosticsDueToLockCount: UInt64? = nil,
        callbackSkippedAudioDueToLockCount: UInt64? = nil,
        lifecycleChangeWhileRenderingCount: UInt64? = nil,
        audioUnitLifecycleCallWhileCallbackActiveCount: UInt64? = nil,
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
        self.adapterPlanGenerationMS = adapterPlanGenerationMS
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
        self.runtimeOutputHostType = runtimeOutputHostType
        self.runtimeOutputHostRunning = runtimeOutputHostRunning
        self.runtimeOutputHostStartCount = runtimeOutputHostStartCount
        self.runtimeOutputHostPrepareStatus = runtimeOutputHostPrepareStatus
        self.runtimeOutputHostInitializeStatus = runtimeOutputHostInitializeStatus
        self.runtimeOutputHostStartStatus = runtimeOutputHostStartStatus
        self.runtimeOutputHostStopStatus = runtimeOutputHostStopStatus
        self.runtimeOutputHostLastErrorStatus = runtimeOutputHostLastErrorStatus
        self.debugStopAfterSeconds = debugStopAfterSeconds
        self.sampleRate = sampleRate
        self.selectedRuntimeSampleRate = selectedRuntimeSampleRate
        self.cMixerRuntimeSampleRate = cMixerRuntimeSampleRate
        self.runtimeSampleRatePolicy = runtimeSampleRatePolicy
        self.runtimeSampleRateSource = runtimeSampleRateSource
        self.runtimeSampleRateConfigurationWarning = runtimeSampleRateConfigurationWarning
        self.cMixerRenderSampleRate = cMixerRenderSampleRate
        self.cMixerRenderChannelCount = cMixerRenderChannelCount
        self.audioHardwareNominalSampleRate = audioHardwareNominalSampleRate
        self.audioHardwareDeviceID = audioHardwareDeviceID
        self.audioHardwareDeviceUIDHash = audioHardwareDeviceUIDHash
        self.audioOutputRouteLabel = audioOutputRouteLabel
        self.audioHardwareIOBufferFrameSize = audioHardwareIOBufferFrameSize
        self.audioHardwareIOBufferDuration = audioHardwareIOBufferDuration
        self.audioHardwareLatencyFrames = audioHardwareLatencyFrames
        self.audioHardwareLatencyDuration = audioHardwareLatencyDuration
        self.audioHardwareSafetyOffsetFrames = audioHardwareSafetyOffsetFrames
        self.audioHardwareSafetyOffsetDuration = audioHardwareSafetyOffsetDuration
        self.audioHardwareTransportType = audioHardwareTransportType
        self.audioHardwareTransportTypeName = audioHardwareTransportTypeName
        self.audioGraphFormatChangeCount = audioGraphFormatChangeCount
        self.audioOutputRouteChangeCount = audioOutputRouteChangeCount
        self.audioGraphFormatChanged = audioGraphFormatChanged
        self.audioOutputRouteChanged = audioOutputRouteChanged
        self.audioOutputDeviceChanged = audioOutputDeviceChanged
        self.audioOutputSampleRateChanged = audioOutputSampleRateChanged
        self.audioOutputChannelCountChanged = audioOutputChannelCountChanged
        self.audioHardwareIOBufferDurationChanged = audioHardwareIOBufferDurationChanged
        self.audioFormatConversionLikely = audioFormatConversionLikely
        self.runtimeCaptureMatchesHardwareSampleRate = runtimeCaptureMatchesHardwareSampleRate
        self.cMixerRenderedFrames = cMixerRenderedFrames
        self.cMixerPlaybackSeconds = cMixerPlaybackSeconds
        self.cMixerRenderedFramesBeforeClear = cMixerRenderedFramesBeforeClear
        self.cMixerPlaybackSecondsBeforeClear = cMixerPlaybackSecondsBeforeClear
        self.plannedSongEndFrame = plannedSongEndFrame
        self.plannedSongEndSeconds = plannedSongEndSeconds
        self.plannedSongEndRuntimeFrame = plannedSongEndRuntimeFrame
        self.plannedSongEndRuntimeSeconds = plannedSongEndRuntimeSeconds
        self.runtimeFrameAtPlannedSongEnd = runtimeFrameAtPlannedSongEnd
        self.runtimeSecondsAtPlannedSongEnd = runtimeSecondsAtPlannedSongEnd
        self.runtimeTailSeconds = runtimeTailSeconds
        self.runtimeTailFrames = runtimeTailFrames
        self.runtimeTailPolicy = runtimeTailPolicy
        self.runtimeTailConfigurationWarning = runtimeTailConfigurationWarning
        self.songEndStopFrame = songEndStopFrame
        self.songEndStopSeconds = songEndStopSeconds
        self.songEndStopRuntimeFrame = songEndStopRuntimeFrame
        self.songEndStopRuntimeSeconds = songEndStopRuntimeSeconds
        self.runtimeFrameAtSongEndTailStop = runtimeFrameAtSongEndTailStop
        self.runtimeSecondsAtSongEndTailStop = runtimeSecondsAtSongEndTailStop
        self.eventQueueExhausted = eventQueueExhausted
        self.eventQueueExhaustedFrame = eventQueueExhaustedFrame
        self.eventQueueExhaustedSeconds = eventQueueExhaustedSeconds
        self.activeVoiceCountAtPlannedSongEnd = activeVoiceCountAtPlannedSongEnd
        self.loadedVoiceCountAtPlannedSongEnd = loadedVoiceCountAtPlannedSongEnd
        self.activeVoiceCountAtTailStop = activeVoiceCountAtTailStop
        self.loadedVoiceCountAtTailStop = loadedVoiceCountAtTailStop
        self.activeVoiceCountAfterPlannedSongEnd = activeVoiceCountAfterPlannedSongEnd
        self.loadedVoiceCountAfterPlannedSongEnd = loadedVoiceCountAfterPlannedSongEnd
        self.outputContinuesAfterPlannedSongEnd = outputContinuesAfterPlannedSongEnd
        self.finalSustainedVoicesContinueAfterPlannedSongEnd = finalSustainedVoicesContinueAfterPlannedSongEnd
        self.captureSeconds = captureSeconds
        self.captureEndFrame = captureEndFrame
        self.captureTruncated = captureTruncated
        self.captureCapTriggeredPlaybackStop = captureCapTriggeredPlaybackStop
        self.stopReason = stopReason
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
        self.followPublishedCount = followPublishedCount
        self.followConsumedCount = followConsumedCount
        self.followDroppedCount = followDroppedCount
        self.followSuppressedCount = followSuppressedCount
        self.followUnresolvedPositionCount = followUnresolvedPositionCount
        self.followLastPublishedOrder = followLastPublishedOrder
        self.followLastPublishedRow = followLastPublishedRow
        self.followLastPublishedTick = followLastPublishedTick
        self.followLastConsumedOrder = followLastConsumedOrder
        self.followLastConsumedRow = followLastConsumedRow
        self.followLastConsumedTick = followLastConsumedTick
        self.followSampleFrame = followSampleFrame
        self.followResolverFailureReason = followResolverFailureReason
        self.followFreezeDetected = followFreezeDetected
        self.directStartOffsetFrame = directStartOffsetFrame
        self.resolverTimelineStartOrder = resolverTimelineStartOrder
        self.resolverTimelineBaseFrame = resolverTimelineBaseFrame
        self.resolverMaxFrame = resolverMaxFrame
        self.resolverEndReached = resolverEndReached
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
        self.callbackMaxDurationMS = callbackMaxDurationMS
        self.callbackAvgDurationMS = callbackAvgDurationMS
        self.callbackDurationWarningCount = callbackDurationWarningCount
        self.callbackRenderQuantumDurationMS = callbackRenderQuantumDurationMS
        self.callbackRenderQuantumMinMS = callbackRenderQuantumMinMS
        self.callbackRenderQuantumMaxMS = callbackRenderQuantumMaxMS
        self.callbackOverRenderQuantumBudgetCount = callbackOverRenderQuantumBudgetCount
        self.callbackNearBudgetWarningCount = callbackNearBudgetWarningCount
        self.callbackIntervalMinMS = callbackIntervalMinMS
        self.callbackIntervalMaxMS = callbackIntervalMaxMS
        self.callbackIntervalLastMS = callbackIntervalLastMS
        self.callbackThreadIsMain = callbackThreadIsMain
        self.callbackThreadID = callbackThreadID
        self.callbackMainThreadDependencyDetected = callbackMainThreadDependencyDetected
        self.callbackAllocationWarning = callbackAllocationWarning
        self.callbackRealtimeSafeDiagnostics = callbackRealtimeSafeDiagnostics
        self.callbackDiagnosticDropCount = callbackDiagnosticDropCount
        self.callbackRingBufferCapacity = callbackRingBufferCapacity
        self.callbackLockWaitCount = callbackLockWaitCount
        self.callbackLockWaitDurationMS = callbackLockWaitDurationMS
        self.callbackLockFailureCount = callbackLockFailureCount
        self.callbackLockAttemptCount = callbackLockAttemptCount
        self.callbackTryLockFailureCount = callbackTryLockFailureCount
        self.callbackLockFailureAudioImpact = callbackLockFailureAudioImpact
        self.callbackRenderedFromStaleSnapshotCount = callbackRenderedFromStaleSnapshotCount
        self.callbackRenderedSilenceDueToUnavailableStateCount = callbackRenderedSilenceDueToUnavailableStateCount
        self.callbackSkippedDiagnosticsDueToLockCount = callbackSkippedDiagnosticsDueToLockCount
        self.callbackSkippedAudioDueToLockCount = callbackSkippedAudioDueToLockCount
        self.lifecycleChangeWhileRenderingCount = lifecycleChangeWhileRenderingCount
        self.audioUnitLifecycleCallWhileCallbackActiveCount = audioUnitLifecycleCallWhileCallbackActiveCount
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

struct RuntimeMixerMetricsTraceField: Equatable {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        let sanitizedKey = Self.sanitizedKey(key)
        self.key = sanitizedKey
        self.value = Self.sanitizedValue(value, key: sanitizedKey)
    }

    init(_ key: String, _ value: Int) {
        self.init(key, String(value))
    }

    init(_ key: String, _ value: UInt64) {
        self.init(key, String(value))
    }

    init(_ key: String, _ value: Bool) {
        self.init(key, value ? "true" : "false")
    }

    init(_ key: String, _ value: Float) {
        self.init(key, Self.format(Double(value)))
    }

    init(_ key: String, _ value: Double) {
        self.init(key, Self.format(value))
    }

    private static func format(_ value: Double) -> String {
        let safeValue = value.isFinite ? value : 0
        return String(format: "%.6f", safeValue)
    }

    private static func sanitizedKey(_ key: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        let scalars = key.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        let result = scalars.joined()
        return result.isEmpty ? "field" : result
    }

    private static func sanitizedValue(_ value: String, key: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "empty"
        }
        let lowercased = trimmed.lowercased()
        let lowercasedKey = key.lowercased()
        if lowercasedKey.contains("path") ||
            lowercasedKey.contains("url") ||
            lowercasedKey.contains("title") ||
            trimmed.contains("/") ||
            trimmed.contains("\\") ||
            lowercased.contains("desktop") {
            return "redacted"
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,:+-=@")
        let scalars = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return scalars.joined()
    }
}

struct RuntimeMixerMetricsTraceRecord: Equatable {
    let phase: String
    let fields: [RuntimeMixerMetricsTraceField]
}

enum RuntimeMixerMetricsClassification {
    static let adjacentJumpWatchThreshold: Float = 0.25

    static func continuityStatus(
        outputDiscontinuityCount: UInt64,
        adjacentJumpCountGT025: UInt64,
        maxOutputAdjacentSampleJump: Float
    ) -> String {
        if outputDiscontinuityCount > 0 {
            return "possible_discontinuity"
        }
        if adjacentJumpCountGT025 > 0 ||
            maxOutputAdjacentSampleJump.isFinite &&
            maxOutputAdjacentSampleJump > adjacentJumpWatchThreshold {
            return "watch"
        }
        return "clean"
    }

    static func outputLevelStatus(
        overrangeSampleCount: UInt64,
        clippingSampleCount: UInt64,
        clippingDetected: Bool
    ) -> String {
        clippingDetected || clippingSampleCount > 0 || overrangeSampleCount > 0
            ? "level_concern"
            : "clean"
    }
}

enum RuntimeMixerMetricsTraceFormatter {
    static func line(for record: RuntimeMixerMetricsTraceRecord) -> String {
        var parts = [
            "vtx_runtime_mixer_metrics",
            "schema=1",
            "phase=\(RuntimeMixerMetricsTraceField("phase", record.phase).value)",
        ]
        parts.append(contentsOf: record.fields.map { "\($0.key)=\($0.value)" })
        return parts.joined(separator: " ")
    }
}

@MainActor
protocol RuntimeMixerMetricsTraceWriting: AnyObject {
    var isEnabled: Bool { get }

    func record(_ record: RuntimeMixerMetricsTraceRecord)
    func flush()
}

@MainActor
final class NoopRuntimeMixerMetricsTraceWriter: RuntimeMixerMetricsTraceWriting {
    static let shared = NoopRuntimeMixerMetricsTraceWriter()

    let isEnabled = false

    private init() {}

    func record(_ record: RuntimeMixerMetricsTraceRecord) {}

    func flush() {}
}

@MainActor
final class StandardErrorRuntimeMixerMetricsTraceWriter: RuntimeMixerMetricsTraceWriting {
    static let shared = StandardErrorRuntimeMixerMetricsTraceWriter()

    let isEnabled = true

    private init() {}

    func record(_ record: RuntimeMixerMetricsTraceRecord) {
        let line = RuntimeMixerMetricsTraceFormatter.line(for: record)
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        FileHandle.standardError.write(data)
    }

    func flush() {}
}

enum RuntimeMixerMetricsTraceConfiguration {
    static let enabledEnvironmentKey = "VTX_RUNTIME_MIXER_METRICS_TRACE"

    @MainActor
    static func makeWriter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeMixerMetricsTraceWriting {
        flagEnabled(enabledEnvironmentKey, environment: environment)
            ? StandardErrorRuntimeMixerMetricsTraceWriter.shared
            : NoopRuntimeMixerMetricsTraceWriter.shared
    }

    static func flagEnabled(_ key: String, environment: [String: String]) -> Bool {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
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
