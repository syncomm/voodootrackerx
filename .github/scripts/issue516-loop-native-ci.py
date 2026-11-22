#!/usr/bin/env python3
"""Qualify submitted Issue 516 native workloads; retain raw receipts outside git."""

import ctypes
import hashlib
import json
import os
import pathlib
import platform
import re
import shlex
import signal
import stat
import struct
import subprocess
import tempfile
import time

# Full optimized app suite, adding one logical pan sustain/release runtime guard.
APP_RELEASE_COUNT = 1918

# Full optimized suite, adding two logical pan sustain/release policy guards.
PACKAGE_RELEASE_COUNT = 984

# Exact public selectors; no discovery-based reduction, skip or duplicate allowance.
APP = [
    'LoopEngineLifecycleTests/testActualCHeadResolvesExactRowHeldFxxAndJumpBoundaries',
    'LoopEngineLifecycleTests/testActualHostCoalescesEditsWithoutMainActorAcknowledgementThenColdSeeksAndReturnsToNormal',
    'LoopEngineLifecycleTests/testActualPlannedCMixerTickUsesOneRenderedHeadForLoopAndNormalPlay',
    'LoopEngineLifecycleTests/testBlockedActualProducerStopsAfterNativeRetirementAndRejectsLateWork',
    'LoopEngineLifecycleTests/testCompletedNativeFaultCaptureMarksTerminalMusicalCoordinateAndExactRawHead',
    'LoopEngineLifecycleTests/testFirstFollowObserverCanReplacePendingLoopStartWithPlaySeekOrStop',
    'LoopEngineLifecycleTests/testFollowDiagnosticReentryCannotPublishRetiredPositionToUI',
    'LoopEngineLifecycleTests/testIncompatibleLiveTempoUsesTypedStopAndFreshPlayThenLoadCancelsOldGeneration',
    'LoopEngineLifecycleTests/testLiveHeadIsReadOnceAndMissingPacketNeverAdvancesTimerState',
    'LoopEngineLifecycleTests/testNormalSelectedColdOriginWaitsForItsActualTailDeadlineAndKeepsMappedFrameMeaning',
    'LoopEngineLifecycleTests/testNormalSongEndTimerOnlyStopsAfterActualNativeTailDeadline',
    'LoopEngineLifecycleTests/testPauseAdoptsNativeEditEvenWhenWorkerAcknowledgementAndMainServiceAreDelayed',
    'LoopEngineLifecycleTests/testPauseNativeHeadPublicationCannotOverwriteNewerLoad',
    'LoopEngineLifecycleTests/testPauseReplayCreatesFreshNativeBirthScopeWithoutChangingPlanLocalIDs',
    'LoopEngineLifecycleTests/testPauseResumeContextUsesCapturedNativeRow',
    'LoopEngineLifecycleTests/testRefusedRefreshStopObserverCanLoadAndPlayANewerSong',
    'LoopEngineLifecycleTests/testStopAndPauseCaptureActualNativeLoopHeadWithoutUITimer',
    'LoopEngineLifecycleTests/testUnavailableQuiescentHeadRetainsAnExplicitlyTaggedLastKnownCoordinate',
    'PlaybackEngineTests/testPlaybackEngineLoadingDifferentSongInvalidatesAndRebuildsRuntimeAdapterPlanOnNextPlay',
    'PlaybackEngineTests/testPlaybackEngineSecondPlayAfterStopReusesRuntimeAdapterPlan',
    'PlaybackEngineTests/testProductionPreparationDefaultOriginEventsAndNativePCMAreExactInBothModesAndRates',
    'PlaybackEngineTests/testProductionPreparationDelayedMainNotificationCannotRetainOrInstallOldSource',
    'PlaybackEngineTests/testProductionPreparationEngineTeardownReleasesRejectedResultAndSourceOnWorker',
    'PlaybackEngineTests/testProductionPreparationExplicitNilProductRetriesThroughSameOwner',
    'PlaybackEngineTests/testProductionPreparationFirstPlayJoinsActualWorkerWithoutMainNotification',
    'PlaybackEngineTests/testProductionPreparationLoadModeAndRateChangesBeforeAdmissionCannotInstallOldResult',
    'PlaybackEngineTests/testProductionPreparationNestedPlayDuringPausedIsolatedRestoreWinsStop',
    'PlaybackEngineTests/testProductionPreparationNestedSeekWinsBeforeOuterPlayNativeConsumption',
    'PlaybackEngineTests/testProductionPreparationRefreshStaysOwnedUntilBoundaryAndCoalescesWhileMainBlocked',
    'PlaybackEngineTests/testProductionPreparationRefusedRefreshRetiresSourceOnWorkerWithoutClaim',
    'PlaybackEngineTests/testProductionPreparationStopBeforeAdmissionRejectsReadyAttemptAndAllowsFreshIntent',
    'PlaybackEngineTests/testProductionPreparationStopFromPublicationObserversPreventsNativeAdmission',
    'PlaybackEngineTests/testProductionPreparationSupersessionsRetireRejectedGraphsBeforeNewestConstructor',
    'PlaybackEngineTests/testRuntimeFinalizedRowsPreserveNativePCMAndHeldStateAcrossPartitions',
    'RenderCoreNativeLoopIntegrationTests/testCompletedStopSourceFreeSemanticAndStaleBindingPreserveActualBirth',
    'RenderCoreNativeLoopIntegrationTests/testMissingSuccessorRetiresAtExactBoundaryBeforeFaultSilenceAndLateRejection',
    'RenderCoreNativeLoopIntegrationTests/testReadySuccessorsAndSilentBoundaryKeepExactPCMIDsSourceAndZeroCrossings',
    'RuntimeCMixerColdPlanAssemblyTests/testAssemblyCopyKeepsIndependentNonInvolutionPermutationAndRangeRemoval',
    'RuntimeCMixerColdPlanAssemblyTests/testCapacityOverflowDoesNotAllocateOrLoseAnExistingEvent',
    'RuntimeCMixerColdPlanAssemblyTests/testCategoriesPreserveLexicalUnionAndSkipOnlyIdenticalConsecutiveRuns',
    'RuntimeCMixerColdPlanAssemblyTests/testCompactKeysPreserveExactColdComparatorAndPayloads',
    'RuntimeCMixerColdPlanAssemblyTests/testEmptyAndSingleEventPlansReuseTheirConstructionStorage',
    'RuntimeCMixerColdPlanAssemblyTests/testEmptyDuplicateAndRareCategoriesSurviveAssemblyNativeDiagnosticsAndJSON',
    'RuntimeCMixerColdPlanAssemblyTests/testIdenticalKeysRetainWriterOrderWithoutPatternOrChannelTieKeys',
    'RuntimeCMixerColdPlanAssemblyTests/testLargeSyntheticPlanPinsCompactSortCopyAndCategoryWork',
    'RuntimeCMixerColdPlanAssemblyTests/testLongPermutationCyclePreservesIndirectPayloadsAndUnicodeCategories',
    'RuntimeCMixerColdPlanAssemblyTests/testLoopRangeCompactionPreservesRawIDsWriterTiesCategoriesAndRuntimeKeys',
    'RuntimeCMixerColdPlanAssemblyTests/testNontrivialInversionReusesStorageAndMovesOnlyDisplacedEvents',
    'RuntimeCMixerColdPlanAssemblyTests/testRareAmigaNoteMetadataRetainsExactOrderedCategoryValues',
    'RuntimeCMixerColdPlanAssemblyTests/testRareChannelPayloadDoesNotDetermineEveryEventSlotWidth',
    'RuntimeCMixerColdPlanAssemblyTests/testRareChannelPayloadRetainsValueEqualityAndEveryOptionalField',
    'RuntimeCMixerColdPlanAssemblyTests/testRareChannelPayloadSharesQueueStorageAndDispatchesWithoutInventingAVoice',
    'RuntimeCMixerColdPlanAssemblyTests/testResultingRuntimeKeysRetainTheDistinctComparatorAndCachedStorage',
    'RuntimeCMixerColdPlanAssemblyTests/testRowEffectCategoriesShareStorageAcrossRepeatedOrderedShapes',
    'RuntimeCMixerColdPlanAssemblyTests/testSameFrameActionPrioritiesMatchTheLegacyColdComparator',
    'RuntimeCMixerColdPlanAssemblyTests/testSharedCategoryCopyMutationCannotChangePublishedPlanOrQueue',
    'RuntimeCMixerColdPlanAssemblyTests/testSingleOwnerPermutationRemainsValidAfterConstructionScopeIsReleased',
    'RuntimeCMixerColdPlanAssemblyTests/testTriggerPayloadRemainsCompactAndSharesPCMThroughPermutation',
    'RuntimeLoopNativeBatchStoragePCMTests/testProductionStorageAndCoreMatchExpandedPCMAtBothRatesModesAndRowCaps',
    'RuntimeLoopNativeBatchStoragePCMTests/testAuthoredBxxNativeSequencePCMAndOwnershipThroughTwelvePassesWithLoopOffAndOn',
    'SelectedOriginConsumerTests/testCachedCycleAnalysisCannotBecomeLiveEndAndTransportControlsStillWin',
    'RuntimeLoopNativeEarlyCutoverTests/testConcurrentReadyRetractionPreservesClaimedHeaderAndOwner',
    'RuntimeLoopNativeEarlyCutoverTests/testOptionalNaturalBoundaryCoalescingAndUnchangedMandatoryDelivery',
    'RuntimeLoopNativeEarlyEditPCMTests/testWarmEarlyEditMatchesExpandedPCMAtBothRatesAndModes',
    'RuntimeLoopNativeEarlyEditReleasePCMTests/testReleaseEditsMatchExpandedPCMWithoutSpeculativeNativeKeyOff',
    'RuntimeLoopNativeOccurrenceTraceTests/testNormalTraceNilAdditionsPreserveExactJSON',
    'RuntimeLoopNativeOccurrenceTraceTests/testOccurrenceKeepsOriginalNumbersAndDistinguishesImportedBirthScope',
    'RuntimeLoopNativeOccurrenceTraceTests/testStoppedBackendDrainsNativeOccurrencesBeforeCoreResetAndOnlyOnce',
    'RuntimeLoopNativeRawIDAccountingTests/testCompletedBatchesMergeRawUnionWithoutOccurrences',
    'RuntimeLoopNativeRawIDAccountingTests/testExplicitStopIncludesOnlyExecutedPrefixAndSessionFinalCopy',
    'RuntimeLoopNativeRawIDAccountingTests/testFailedCommandDoesNotMarkFailedOrLaterIDs',
    'RuntimeLoopSessionRapidDeadlineTests/testSupersededCandidateRecoversFreeSlotAndFinalQuiescedReceipt',
    'ControlPanelViewTests/testPendingPlayCanBeStoppedWithoutClaimingActivePlayback',
    'PlaybackEngineTests/testPlaybackTimingMilestoneUsesObservedHostStampInsteadOfDelayedPollTime',
    'SelectedOriginConsumerTests/testNormalPlayRequestKeepsMainResponsiveWhileSharedWorkerIsBlocked',
    'SelectedOriginConsumerTests/testNormalPlayStopCancelsBlockedPreparationExactlyOnce',
    'SelectedOriginConsumerTests/testNormalPlayRejectsStaleAdmissionGuardAndReplacementSource',
    'SelectedOriginConsumerTests/testNormalPlayFiniteSelectedRowPCMMatchesFullOracleWithoutFullConstructorOnRestart',
    'SelectedOriginConsumerTests/testNormalPlayAdmissionPredicateCannotInstallReenteredSource',
    'SelectedOriginConsumerTests/testNormalPlayPositionObserverReplacementStartsNewestNativeGeneration',
    'SelectedOriginConsumerTests/testNormalPlayReadyPredicateReentryCannotAdmitSupersededPreparation',
    'SelectedOriginConsumerTests/testFiniteZeroTailCoreExecutesEndWriterBeforeClearAndMatchesPCM',
    'RenderCoreNativeLoopIntegrationTests/testFiniteSongTailUsesOrdinaryClearBeforeRetirementAndPublishesOneCompletion',
    'RuntimeHostOutputTimingTests/testFirstHostTimingIgnoresOfflineZeroFailedAndDisabledRenders',
    'RuntimeHostOutputTimingTests/testFirstSuccessfulHostTimingIsImmutableAndResetsWithTransportGeneration',
    'RuntimeHostOutputTimingTests/testMainHeartbeatUsesOnlyTheExistingOptInFlag',
    'RuntimeHostOutputTimingTests/testMainHeartbeatFinishIncludesOneOutstandingBlockedProbe',
    'RuntimeLoopNativeBatchStoragePCMTests/testFiniteStorageValidatesCrossOrderArrayIndicesAndPreservesSourceLabelsThroughTail',
    'RuntimeLoopNativeOccurrenceTraceTests/testScopeEncodingPreservesLoopV1BytesAndDistinguishesFiniteTransport',
    'RuntimeLoopNativeOccurrenceTraceTests/testOrdinaryV2EnvelopeKeepsBatchNumbersAndOriginalCarriedBirth',
    'RuntimeLoopNativeOccurrenceTraceTests/testFiniteStoppedBackendScopesOccurrencesWithoutImportingLegacyConsumedIDs',
    'RuntimeLoopSessionRapidDeadlineTests/testInitialPreparationCallbackPublishesReadyOnce',
    'RuntimeLoopSessionRapidDeadlineTests/testExplicitLoopWarmupIgnoresFiniteSongTailPolicy',
    'RuntimeLoopSessionRapidDeadlineTests/testInitialPreparationCallbackPublishesCancellationOnceBeforeWarmup',
    'RuntimeLoopSessionRapidDeadlineTests/testInitialPreparationCallbackPublishesValidationFailureOnce',
    'RuntimeLoopSessionRapidDeadlineTests/testFiniteSongSingleTerminalWarmupPublishesReadyWithoutSuccessor',
    'SongDurationTests/testFiniteControlFlowDurationMatchesManualSecondsAndTimingOnlyOracle',
    'SongDurationTests/testOddRowsEmptyInputsAndOutgoingFiniteEndsKeepExecutedCommandRow',
    'SongDurationTests/testMissingCyclicAndCancelledDurationNeverPublishesExactPrefix',
    'SongDurationTests/testLoadPublishesDurationBeforePlayWithoutEngineOrSamplePayload',
    'SongDurationTests/testEditableTimingEditUndoAndRedoRefreshDurationThroughCanonicalCoordinator',
    'SongDurationTests/testNavigationFocusTitleSampleAndRestartChangesPreserveDurationGeneration',
    'SongDurationTests/testReplacementIdentityRejectsBlockedStaleResultAndFileNewClearsDuration',
]
PACKAGE_ASAN = [
    'AuthoredBxxContinuationTests/testBoundedLiveBxxCarriesEveryHxyTickAcrossAdversarialSplitsAndColdOrigins',
    'AuthoredBxxContinuationTests/testLongSilentCyclesRemainBoundedAndCancellationDoesNotAdvanceCheckpoint',
    'AuthoredBxxContinuationTests/testFullAnalysisStillTerminatesAtKnownCycleAndFiniteControlKeepsExactEnd',
    'AuthoredBxxContinuationTests/testBxxReturnStartsFreshPatternLocalE6ButRetainsActualFxxH00State',
    'UserLoopProducerPCMTests/testAuthoredBxxWindowsMatchFiniteExpandedPCMThroughTwelvePasses',
    'CatalogPCMLeaseTests/testRevokedCandidatesReuseOnePayloadForPreviouslyUnplayedCatalogSample',
    'CatalogProofTests/testChangedBytesStaleGenerationOtherLeaseAndEpochCannotUseProof',
    'CatalogProofTests/testPrevalidatedProofConsumesSameLeasePrefixAndReusesSanitizedPCMWithFreshRawStorage',
    'GlobalVolumeProjectionTests/testCanonicalTransitionsAndHeldTargetsStayDistinct',
    'GlobalVolumeProjectionTests/testContinuationKeepsHeldGlobalTargetsWithoutANewGlobalWriter',
    'GlobalVolumeProjectionTests/testFrozenProjectionMatchesPublicFixturesWindowsAndIndependentRebuilds',
    'GlobalVolumeProjectionTests/testFrozenProjectionMatchesSyntheticWriterAndSourceLifecycles',
    'GlobalVolumeProjectionTests/testGlobalRowOrderFastPathMatchesStableSortForCanonicalAndFallbackInputs',
    'GlobalVolumeProjectionTests/testImportedRetiringLookupsCannotRestoreASourceFreeGlobalRoute',
    'GlobalVolumeProjectionTests/testLateWriterCopiesFullControlsOnlyForPublishedTargets',
    'LoopResetContinuationTests/testLastResetInputsKeepExactOriginalCoordinatesAndRemapOnlyScratchSources',
    'LoopResetContinuationTests/testMissingSourceMissingOriginAndNonfreshImportRejectTransactionally',
    'LoopResetContinuationTests/testThousandCarriesKeepFlatFirstScopeAndTwoFactsWithoutParentHistory',
    'LoopScratchCompactionTests/testAThousandActualLoopBatchesKeepSourceBindingsAndStorageBounded',
    'LoopScratchCompactionTests/testActualEmptyRouteDropsSourceZeroAndRemapsSourceOneWithoutNewBirth',
    'LoopScratchCompactionTests/testBlankAndSlideImportsKeepTheOriginalBirthAndActualWriterAnchor',
    'LoopScratchCompactionTests/testHeldKnownMissingAndUnestablishedRemainDistinctAndOwnerOverrideDoesNotRebindHeld',
    'PendingRowPitchContinuationTests/testDelayedVibratoEligibilityUsesImportedIndexAndMissingBindingIsTransactional',
    'PendingRowPitchContinuationTests/testImportedExitCoalescesAtRealLocalRowZeroIncludingHeldRows',
    'PendingRowPitchContinuationTests/testPendingExitKeepsOnlyBoundaryChildrenAndExactMetadata',
    'PreparedLoopBirthTests/testOnePreparedPayloadIsSharedAndNativeResetReleasesAllVoiceReferences',
    'PreparedLoopBirthTests/testPreparedBirthMatchesOrdinaryPCMAtBothRatesWithLoopsEnvelopesAndOnset',
    'RuntimeLoopNativeChannelTests/testEveryScopeFieldIsRejectedBeforePublicationWithoutHoldingOwner',
    'RuntimeLoopNativeChannelTests/testMissingSuccessorSealsEpochAndRejectsLatePreparingCompletion',
    'RuntimeLoopNativeChannelTests/testReadySuccessorNeedsNoMainActorNotificationAndReclaimsOnlyOffConsumer',
    'RuntimeLoopNativeChannelTests/testRevokeDoesNotDisposePublishedOwnerBeforeHostQuiescence',
    'RuntimeLoopNativeChannelTests/testSequencePredecessorStateAndGapRejectWithoutAcknowledgingBadBatch',
    'RuntimeLoopNativeChannelTests/testStaleReservationCannotPublishIntoRecycledSlot',
    'RuntimeLoopNativeChannelTests/testThousandSequentialBatchesHaveExactEndAcknowledgmentsAndAtMostTwoOwners',
    'RuntimeLoopNativeChannelTests/testWrongEndCannotAdvanceAcknowledgmentOrInstallSuccessor',
    'RuntimeLoopNativeDeliveryTests/testMissingSuccessorRetiresAtExactBoundaryThenSilencesAndRejectsLateProducer',
    'RuntimeLoopNativeDeliveryTests/testReadySuccessorPreservesNativeCursorAcrossIrregularPartitionsAndEmptyBatch',
    'RuntimeRowLifetimeTests/testFinalizedAssemblyPreservesValuesOwnersQueriesAndSharedHistoryBuffers',
    'RuntimeRowLifetimeTests/testIndependentRuntimeProductReleasesRowsButInspectionAliasPinsThem',
    'RuntimeRowLifetimeTests/testOddOwnerReferencesPreserveOriginalOrdinalsAndNilValues',
    'RuntimeRowLifetimeTests/testPublicFullPlanReceipt',
    'UserLoopProducerPCMTests/testExecutedContinuationFixesFrozenFrame18241CounterexampleAgainstExpandedPCM',
    'UserLoopProducerSemanticTests/testCancelledProductionDoesNotAdvanceTheCommittedCheckpointOrBirthScope',
    'UserLoopProducerSemanticTests/testLoopAssemblyMatchesFullThenFilterWithoutChangingIDsOrCategories',
    'UserLoopProducerSemanticTests/testProductionArpeggioVibratoHeldRowsAndFractionalFxxMatchExpandedExecution',
    'UserLoopProducerSemanticTests/testSourceFreeAndOwnerOnlyWritersPreserveHonestMissingSourceAcrossCheckpoints',
    'UserLoopTraversalContinuationTests/testArrayIndicesStaySeparateFromSourceLabelsAndInvalidOriginsAreRefused',
    'UserLoopTraversalContinuationTests/testBoundedBatchPartitionsKeepExactExecutedRowsAndFractionalTiming',
    'UserLoopTraversalContinuationTests/testColdSuffixThenWholeIterationsMatchesExpandedOrderOccurrences',
    'UserLoopTraversalContinuationTests/testHeldE6AndSameRowFxxTimingMatchExpandedExecution',
    'UserLoopTraversalContinuationTests/testNaturalEntryDropsEarlierOccurrenceAnchorWithoutColdRescan',
    'UserLoopTraversalContinuationTests/testNaturalTailShapingAndHardCapRollbackPreserveExactExecution',
    'UserLoopTraversalContinuationTests/testOutgoingJumpBreakLoopWritersKeepAcceptedPrecedenceAndDiagnostics',
    'UserLoopTraversalContinuationTests/testRowGuardDoesNotExecutePhantomRowAndUnrelatedOrdersDoNotChangeState',
    'UserLoopTraversalContinuationTests/testSameOrderForwardJumpRetainsRowAndInvalidOrCycleExitDoesNotBecomeAccepted',
    'UserLoopTraversalContinuationTests/testStructuralColdAnchorAndE6StateSurviveArbitraryBatchSplits',
    'XMContinuingFoldTests/testCheckpointsDoNotRetainThePreviousBatchRowCaptures',
    'XMContinuingFoldTests/testDefaultNilCheckpointArgumentsKeepTheColdFoldExact',
    'XMContinuingFoldTests/testEveryRowSplitKeepsSegmentReleaseResetAndAudibleTargetsExact',
    'XMContinuingFoldTests/testPlainReleaseContinuesThroughBlankRowsWithoutNewGlobalOrReleaseWriter',
    'XMContinuingFoldTests/testRetainedSourceRemapsToCompactScratchIndexWithoutBirthOrOldRows',
    'XMContinuingFoldTests/testSourceFreeReleaseSilentResetAndLaterSourceKeepExactTickState',
    'UserLoopProducerPCMTests/testFiniteSongCrossOrderPCMMatchesFullColdPlan',
    'UserLoopProducerSemanticTests/testFiniteSongCrossOrderSemanticEventsMatchFullColdPlan',
    'RuntimeSongNativeDeliveryTests/testFiniteTerminalExecutesMusicalEndWriterClearsBeforeAcknowledgementAndKeepsSilentClock',
    'RuntimeSongNativeDeliveryTests/testFiniteNonterminalStillRequiresSuccessorAndRetiresAsFault',
    'RuntimeSongNativeDeliveryTests/testTerminalMarkerCannotChangeLoopOrEscapeItsNativeInterval',
    'UserLoopProducerPCMTests/testFiniteZeroTailRetainsFullPlanEndFrameWriter',
    'RuntimeSongNativeDeliveryTests/testZeroTailRunsEndWriterBeforeClearingCAndAcknowledging',
]
GUARD_SOURCE = 'import Foundation\n@testable import VoodooTrackerXPlaybackSupport\n\n@main enum GuardProbe {\n    static func main() throws {\n        let path = CommandLine.arguments[1], mode = CommandLine.arguments[2]\n        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)\n        var plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 48_000,\n            rowCaptureRetention: .runtimeFinalized).plan!\n        switch mode {\n        case "read": print(plan.xmChannelRows.count)\n        case "fold": plan.playbackStateEvents = []\n        case "tail": _ = plan.extendingEnvelopeTail(throughFrame: 0)\n        case "assemble": _ = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 48_000, preparedPlan: plan)\n        default: fatalError("Unknown guard test")\n        }\n        print("GUARD_WAS_BYPASSED")\n        exit(86)\n    }\n}\n'
GUARD_SHA = '16ab0b11cb6bc27ee34a305e6c5492bdb1e0e20636518bf709c150868b8927c1'

root = None
APP_RUNTIME = {}

def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()

def output(args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

# Live-kernel, mapped-bundle, options and PID-log attribution reused from R1.
def kernel_identity(pid):
    lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    buffer = ctypes.create_string_buffer(4096)
    count = lib.proc_pidpath(int(pid), buffer, len(buffer))
    if count <= 0:
        return None
    executable = os.fsdecode(buffer.value)
    class BSDInfo(ctypes.Structure):
        _fields_ = [(name, ctypes.c_uint32) for name in ['flags', 'status', 'xstatus', 'pid', 'ppid', 'uid', 'gid', 'ruid', 'rgid', 'svuid', 'svgid', 'reserved']] + [
            ('comm', ctypes.c_char * 16), ('name', ctypes.c_char * 32)] + [
            (name, ctypes.c_uint32) for name in ['nfiles', 'pgid', 'pjobc', 'tdev', 'tpgid', 'nice']] + [
            ('start_sec', ctypes.c_uint64), ('start_usec', ctypes.c_uint64)]
    info = BSDInfo()
    lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    if lib.proc_pidinfo(int(pid), 3, 0, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):
        return None
    base = {'pid': pid, 'executable': executable, 'uid': info.uid, 'start': [info.start_sec, info.start_usec]}
    libc = ctypes.CDLL(None, use_errno=True)
    libc.sysctl.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t]
    mib = (ctypes.c_int * 3)(1, 49, int(pid))  # CTL_KERN, KERN_PROCARGS2
    size = ctypes.c_size_t()
    if libc.sysctl(mib, 3, None, ctypes.byref(size), None, 0) != 0 or not 0 < size.value < 1024 * 1024:
        return {**base, 'options': None}
    data = ctypes.create_string_buffer(size.value)
    if libc.sysctl(mib, 3, data, ctypes.byref(size), None, 0) != 0:
        return {**base, 'options': None}
    raw = data.raw[:size.value]
    argc = struct.unpack_from('i', raw)[0]
    if not 0 < argc < 4096:
        return {**base, 'options': None}
    try:
        offset = raw.index(b'\0', 4) + 1
        while offset < len(raw) and raw[offset] == 0:
            offset += 1
        for _ in range(argc):
            offset = raw.index(b'\0', offset) + 1
    except ValueError:
        return {**base, 'options': None}
    # Inspect only the proof option; do not retain or publish any other environment value.
    options = next((os.fsdecode(x[len(b'ASAN_OPTIONS='):]) for x in raw[offset:].split(b'\0') if x.startswith(b'ASAN_OPTIONS=')), None)
    return {**base, 'options': options}

def mapped_text_files(pid):
    try:
        child = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(pid), '-d', 'txt', '-Fn'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
    except subprocess.TimeoutExpired:
        return []
    return [os.fsdecode(line[1:]) for line in child.stdout.splitlines() if line.startswith(b'n')]

def runner_pids():
    child = subprocess.run(['pgrep', '-x', 'xctest'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return {int(x) for x in child.stdout.split() if x.isdigit()}

def observe_app_command(args, env, handle, stderr_handle=None):
    context = APP_RUNTIME
    context['started'] = time.time()
    context['observations'] = {}
    context['baselinePIDs'] = sorted(runner_pids())
    process = subprocess.Popen(args, env=env, stdout=handle,
                               stderr=stderr_handle if stderr_handle is not None else subprocess.STDOUT)
    while process.poll() is None:
        if context['bundleImage'].is_file():
            for pid in runner_pids() - set(context['baselinePIDs']):
                if len(context['observations']) >= 16 and pid not in context['observations']:
                    context['overflow'] = True
                    continue
                identity = kernel_identity(pid)
                if not identity:
                    continue
                executable = str(pathlib.Path(identity['executable']).resolve())
                if executable not in context['runners']:
                    continue
                prior = context['observations'].get(pid)
                if prior and prior['start'] != identity['start']:
                    context['reusedPID'] = True
                if prior and prior.get('bundleMatched'):
                    continue
                mapped = mapped_text_files(pid)
                candidates = [pathlib.Path(p) for p in mapped if p.endswith('/Contents/MacOS/' + context['bundleImage'].name)]
                bundle_sha = sha(context['bundleImage'])
                matched = any(path.is_file() and sha(path) == bundle_sha for path in candidates)
                options = dict(part.split('=', 1) for part in (identity['options'] or '').split(':') if '=' in part)
                identity.update({'executable': executable, 'bundleMatched': matched, 'bundleSHA256': bundle_sha if matched else None,
                                 'optionsMatched': all(options.get(key) == value for key, value in context['flags'].items()),
                                 'observed': time.time()})
                context['observations'][pid] = identity
        time.sleep(.03)
    context['ended'] = time.time()
    private = {key: value for key, value in context.items() if key != 'bundleImage'}
    (root / (context['label'] + '-process-observations.json')).write_text(json.dumps(private, indent=2))
    return process.wait()

def runtime_verdict(expected_methods, mapping, observations, logs, context):
    def fail(reason):
        return {'proven': False, 'reason': reason}
    if len(mapping) != len(expected_methods) or sorted(name for name, pid in mapping) != sorted(expected_methods):
        return fail('incomplete-or-duplicate-test-process-map')
    pids = {pid for name, pid in mapping}
    if not 0 < len(pids) <= 16 or context.get('overflow') or context.get('reusedPID'):
        return fail('process-bound-or-reused-pid')
    if not logs:
        return fail('missing-runtime-log')
    if len(logs) > 32 or any(not item['safeFile'] for item in logs):
        return fail('runtime-log-file-identity-or-bounds')
    if any(item['sanitizerErrors'] for item in logs):
        return fail('sanitizer-finding-in-runtime-stream')
    for pid in pids:
        observation = observations.get(pid)
        if not observation:
            return fail('missing-live-process-identity')
        if observation['executable'] not in context['runners'] or observation['uid'] != os.getuid():
            return fail('unrelated-executable-or-owner')
        started = observation['start'][0] + observation['start'][1] / 1000000
        if pid in context['baselinePIDs'] or started < context['started'] or observation['observed'] > context['ended']:
            return fail('process-run-identity-mismatch')
        if not observation['bundleMatched'] or observation['bundleSHA256'] != context['bundleSHA256']:
            return fail('unrelated-test-bundle')
        if not observation['optionsMatched']:
            return fail('runtime-options-not-attested-in-process')
        own = [item for item in logs if item['pid'] == pid]
        if len(own) != 1:
            return fail('missing-or-ambiguous-log-for-executed-pid')
        if own[0]['initPIDs'] != [pid]:
            return fail('runtime-initialization-missing-or-wrong-pid')
    return {'proven': True, 'reason': 'all-executed-case-pids-correlated', 'caseCount': len(mapping), 'processCount': len(pids),
            'relevantLogCount': len(pids), 'otherLogsScanned': len(logs) - len(pids),
            'mappingSHA256': hashlib.sha256(json.dumps(sorted(mapping)).encode()).hexdigest(),
            'runtimeLogSHA256': sorted(item['SHA256'] for item in logs if item['pid'] in pids),
            'kernelExecutableBundleAndOptions': True, 'sanitizerErrors': 0}


def emit(value):
    print(json.dumps(value, sort_keys=True), flush=True)


def require(condition, reason):
    if not condition:
        raise AssertionError(reason)


def image(path, asan):
    path = pathlib.Path(path)
    require(output(['xcrun', 'lipo', '-archs', str(path)]) == 'arm64', 'non-native image')
    linkage = output(['xcrun', 'otool', '-L', str(path)])
    require(('libclang_rt.asan_osx_dynamic' in linkage) == asan, 'ASan image linkage')
    require('libclang_rt.tsan' not in linkage, 'unexpected TSan linkage')
    if asan:
        require('__asan_' in output(['xcrun', 'nm', '-u', str(path)]), 'ASan symbols absent')
    emit({'image': path.name, 'SHA256': sha(path), 'architecture': 'arm64', 'asan': asan})
    return path


def runtime_context(label, bundle):
    directory = pathlib.Path(tempfile.mkdtemp(prefix=label + '-runtime-', dir=str(root)))
    prefix = str(directory / 'asan')
    flags = {'halt_on_error': '1', 'abort_on_error': '1', 'verbosity': '1',
             'log_path': prefix, 'log_exe_name': '0'}
    developer = pathlib.Path(output(['xcode-select', '-p']))
    runners = {str(pathlib.Path(output(['xcrun', '--find', 'xctest'])).resolve()),
               str((developer / 'Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest').resolve())}
    APP_RUNTIME.clear()
    APP_RUNTIME.update({'label': label, 'directory': str(directory), 'flags': flags,
                        'runners': sorted(runners), 'bundleImage': pathlib.Path(bundle).resolve()})
    options = ':'.join(key + '=' + value for key, value in flags.items())
    return {'ASAN_OPTIONS': options, 'TEST_RUNNER_ASAN_OPTIONS': options}


def run(label, command, extra=None, observe=False, separate_stderr=False):
    env = os.environ.copy()
    env.update(extra or {})
    log = root / (label + '.log')
    stderr_log = root / (label + '.stderr.log') if separate_stderr else None
    require(not separate_stderr or observe, 'separate stderr requires observed process collection')
    with log.open('x') as handle:
        if stderr_log is not None:
            # Xcode writes runner case rows to stdout and completion diagnostics to
            # stderr. A shared descriptor can splice stderr into a partial case row.
            with stderr_log.open('x') as stderr_handle:
                code = observe_app_command(command, env, handle, stderr_handle)
        else:
            code = observe_app_command(command, env, handle) if observe else subprocess.call(
                command, env=env, stdout=handle, stderr=subprocess.STDOUT)
    text = log.read_text()
    stderr_text = stderr_log.read_text() if stderr_log is not None else ''
    emit({'stage': label, 'exitCode': code, 'logSHA256': sha(log)})
    if stderr_log is not None:
        emit({'stage': label + '-stderr', 'logSHA256': sha(stderr_log),
              'asanInitializationPIDs': sorted({int(pid) for pid in re.findall(
                  r'==(\d+)==AddressSanitizer Init done', stderr_text)})})
    if code:
        print(text + stderr_text, flush=True)
    require(code == 0, label + ' failed; original log: ' + str(log))
    all_output = text + stderr_text
    require('ERROR: AddressSanitizer' not in all_output and 'SUMMARY: AddressSanitizer' not in all_output,
            label + ' sanitizer finding')
    return text


def result_cases(result, count, expected=None):
    data = {}
    for kind in ['summary', 'tests']:
        data[kind] = json.loads(output(['xcrun', 'xcresulttool', 'get', 'test-results', kind,
                                       '--path', str(result)]))
        (root / (result.stem + '-' + kind + '.json')).write_text(json.dumps(data[kind], indent=2))
    summary, tests = data['summary'], data['tests']
    wanted = {'totalTestCount': count, 'passedTests': count, 'failedTests': 0,
              'skippedTests': 0, 'expectedFailures': 0}
    require(all(type(summary.get(key)) is int and summary[key] == value for key, value in wanted.items()),
            'incorrect XCTest counts')
    require(bool(tests['devices']) and all(d['architecture'] == 'arm64' for d in tests['devices']),
            'non-native XCTest execution')
    cases = []
    def visit(node):
        if node.get('nodeType') == 'Test Case':
            require(node.get('result') == 'Passed', 'non-passed XCTest case')
            cases.append(node['nodeIdentifier'].removesuffix('()'))
        for child in node.get('children', []):
            visit(child)
    for node in tests['testNodes']:
        visit(node)
    require(len(cases) == len(set(cases)) == count, 'missing or duplicated XCTest case')
    if expected is not None:
        require(sorted(cases) == sorted(expected), 'unexpected XCTest selectors')
    return cases


def package_cases(text, count, expected=None):
    rows = re.findall(r"Test Case '-\[(?:\w+\.)?(\w+) (test\w+)\]' (passed|failed|skipped)", text)
    cases = [cls + '/' + method for cls, method, status in rows]
    require(len(cases) == len(set(cases)) == count, 'missing or duplicated package cases')
    require(all(status == 'passed' for cls, method, status in rows), 'non-passed package case')
    summaries = [detail for total, detail in re.findall(
        r'(?m)^\s*Executed (\d+) tests?, with ([^\r\n]+)$', text) if int(total) == count]
    # Accept the ordinary XCTest footer, but never a passing prefix followed by
    # unexpected/expected failures, skips, or conflicting full-suite summaries.
    require(bool(summaries) and all(re.fullmatch(
        r'0 failures(?: \(0 unexpected\))?(?: in [\d.]+ \([\d.]+\) seconds)?\s*', detail)
        for detail in summaries),
            'package summary count')
    if expected is not None:
        require(sorted(cases) == sorted(expected), 'unexpected package selectors')
    return cases


def runtime_proof(label, mapping, expected):
    context = APP_RUNTIME
    context['bundleSHA256'] = sha(context['bundleImage'])
    logs = []
    for path in pathlib.Path(context['directory']).iterdir():
        if path.name in context.get('validatedLoopMarkerFiles', []):
            continue
        match = re.fullmatch(r'asan\.(\d+)', path.name)
        safe, content, digest = False, '', None
        try:
            metadata = path.lstat()
            safe = bool(match and stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1
                        and metadata.st_uid == os.getuid() and not metadata.st_mode & 0o022
                        and 0 < metadata.st_size <= 8 * 1024 * 1024
                        and context['started'] <= metadata.st_mtime <= context['ended'] + 1)
            if safe:
                content, digest = path.read_text(), sha(path)
        except (OSError, UnicodeError):
            safe = False
        logs.append({'pid': int(match[1]) if match else None, 'safeFile': safe,
                     'initPIDs': sorted({int(pid) for pid in re.findall(
                         r'==(\d+)==AddressSanitizer Init done', content)}),
                     'sanitizerErrors': content.count('ERROR: AddressSanitizer') + content.count('SUMMARY: AddressSanitizer'),
                     'SHA256': digest})
    verdict = runtime_verdict(expected, mapping, context['observations'], logs, context)
    (root / (label + '-runtime-proof.json')).write_text(json.dumps(
        {'mapping': mapping, 'logs': logs, 'verdict': verdict}, indent=2))
    require(verdict['proven'], label + ' actual-process ASan proof: ' + verdict['reason'])
    emit({'stage': label, 'actualProcessASan': verdict})
    return {pid for name, pid in mapping}


def package_image(configuration, asan):
    paths = list(pathlib.Path('.build').glob('*/' + configuration +
        '/VoodooTrackerXCorePackageTests.xctest/Contents/MacOS/VoodooTrackerXCorePackageTests'))
    require(len(paths) == 1, 'ambiguous package image')
    return image(paths[0], asan)


def package_asan_compiler_modes(text):
    """Require unoptimized Swift ASan driver arguments and Clang ASan evidence."""
    if '-fsanitize=address' not in text:
        return False
    wrappers = {'builtin-SwiftDriver', 'builtin-Swift-Compilation',
                'builtin-Swift-Compilation-Requirements'}
    for line in text.splitlines():
        if '-sanitize' not in line or '-Onone' not in line:
            continue
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        try:
            command = list(lexer)
        except ValueError:
            continue
        if len(command) >= 3 and command[0] in wrappers and command[1] == '--':
            command = command[2:]
        if not command or pathlib.PurePath(command[0]).name != 'swiftc':
            continue
        flags = set()
        for previous, argument in zip(command, command[1:]):
            if argument == '--' or re.fullmatch(r'[();<>|&]+', argument):
                break
            if previous not in ('-Xcc', '-Xfrontend', '-Xlinker', '-Xllvm'):
                flags.add(argument)
        if {'-sanitize=address', '-Onone'} <= flags:
            return True
    return False


def release_compiler(text, module, debug):
    lines = [line for line in text.splitlines() if re.search(r'\bswiftc\b', line)
             and re.search(r'-module-name\s+' + re.escape(module) + r'\b', line)]
    require(bool(lines), 'missing actual Release compiler command for ' + module)
    for line in lines:
        require(re.search(r'(?:^|\s)-O(?:\s|$)', line) is not None, 'Release is not optimized')
        require(('-DDEBUG' in line or re.search(r'-D\s+DEBUG\b', line) is not None) == debug,
                'Release DEBUG visibility mismatch')
        require('-sanitize' not in line, 'Release unexpectedly sanitized')
    emit({'stage': 'release-compiler', 'module': module, 'optimization': '-O', 'DEBUG': debug, 'asan': False})


def app_case_pid_mapping(text):
    """Retain the default Xcode runner's independent passed-case/PID attribution."""
    return [(cls + '/' + name, int(pid)) for cls, name, pid in re.findall(
        r"'(\w+)\.(test\w+)\(\)' passed on '[^'\n]*\((\d+)\)'", text) if cls + '/' + name in APP]


def app_case_attribution_text(text, result):
    """Remove one exact current-run success footer only when it interrupts a case row."""
    header = 'Test session results, code coverage, and logs:'
    require(text.count(header) <= 1, 'ambiguous Xcode result footers')
    if header not in text:
        return text, []
    footers = list(re.finditer(
        r'\nTest session results, code coverage, and logs:\n\t([^\n]+)\n\n\*\* TEST SUCCEEDED \*\*\n\n', text))
    require(len(footers) == 1, 'malformed Xcode success footer')
    footer = footers[0]
    require(pathlib.Path(footer[1]).resolve() == pathlib.Path(result).resolve(),
            'Xcode footer result-bundle mismatch')
    left, right = text[:footer.start()], text[footer.end():]
    left_line, right_line = left.rsplit('\n', 1)[-1], right.split('\n', 1)[0]
    # Xcode can split the class identifier too. These are fragments only;
    # the joined row below must still name one exact expected selector/PID.
    prefix = re.fullmatch(r"Test case '[\w.]*", left_line)
    suffix = re.fullmatch(r"[\w.]*\(\)' passed on '[^'\n]*\([1-9][0-9]*\)' \([0-9]+(?:\.[0-9]+)? seconds\)", right_line)
    if prefix is None and suffix is None:
        return text, []  # An ordinary standalone footer does not alter attribution.
    require(prefix is not None and suffix is not None, 'ambiguous interrupted Xcode case row')
    joined = app_case_pid_mapping(left_line + right_line)
    require(len(joined) == 1, 'interrupted Xcode row is not one exact expected case')
    require(joined[0][0] not in {name for name, pid in app_case_pid_mapping(text)},
            'interrupted Xcode case duplicates existing attribution')
    removed = [{'SHA256': hashlib.sha256(footer[0].encode()).hexdigest(),
                'byteCount': len(footer[0].encode())}]
    return left + right, removed


def loop_marker_pids(text, console):
    """Join Loop markers from stdout and target console content to case PIDs."""
    pids = {int(pid) for pid in re.findall(r'VTX_LOOP_ASAN_RUNTIME_ACTIVE pid=(\d+)', text)}
    def visit(node):
        if isinstance(node, dict):
            if node.get('adaptorType') == 'target' and isinstance(node.get('content'), str):
                observed = {int(pid) for pid in re.findall(
                    r'VTX_LOOP_ASAN_RUNTIME_ACTIVE pid=(\d+)', node['content'])}
                metadata = node.get('logData')
                if observed and isinstance(metadata, dict) and type(metadata.get('pid')) is int:
                    require(observed == {metadata['pid']}, 'Loop console marker/PID metadata mismatch')
                pids.update(observed)
            for value in node.values():
                visit(value)
        elif isinstance(node, list):
            for value in node:
                visit(value)
    visit(console)
    return pids


def loop_file_marker_pids(context):
    """Validate CI-only Loop marker files before excluding them from ASan logs."""
    pids, validated = set(), []
    for path in pathlib.Path(context['directory']).glob('loop-*.txt'):
        match = re.fullmatch(r'loop-([1-9][0-9]*)\.txt', path.name)
        metadata = path.lstat()
        require(bool(match) and stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1
                and metadata.st_uid == os.getuid() and not metadata.st_mode & 0o022
                and 0 < metadata.st_size <= 1024
                and context['started'] <= metadata.st_mtime <= context['ended'] + 1,
                'unsafe Loop marker file')
        pid = int(match[1])
        require(re.fullmatch(rb'VTX_LOOP_ASAN_RUNTIME_ACTIVE pid=' + str(pid).encode() + rb'\n?',
                             path.read_bytes()) is not None, 'Loop marker filename/payload mismatch')
        pids.add(pid)
        validated.append(path.name)
    context['validatedLoopMarkerFiles'] = validated
    return pids


def main():
    global root
    root = pathlib.Path(tempfile.mkdtemp(prefix='vtx-loop-native-ci-', dir='/private/tmp'))
    require(platform.machine() == 'arm64', 'host is not native arm64')
    event = json.loads(pathlib.Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    head = output(['git', 'rev-parse', 'HEAD'])
    require(head == event['pull_request']['head']['sha'], 'not submitted PR HEAD')
    require(output(['git', 'status', '--porcelain=v1', '-uall']) == '', 'dirty checkout')
    require('ASAN_OPTIONS' not in os.environ and 'TEST_RUNNER_ASAN_OPTIONS' not in os.environ,
            'inherited sanitizer options')
    emit({'head': head, 'architecture': 'arm64', 'Xcode': output(['xcodebuild', '-version']),
          'Swift': output(['swift', '--version']), 'evidenceRoot': str(root)})
    require(len(APP) == len(set(APP)) == 103 and len(PACKAGE_ASAN) == len(set(PACKAGE_ASAN)) == 69,
            'selector manifest counts')
    base = ['xcodebuild', '-project', 'app/VoodooTrackerX/VoodooTrackerX.xcodeproj', '-scheme',
            'VoodooTrackerX', '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', 'build',
            'CODE_SIGNING_ALLOWED=NO', '-parallel-testing-enabled', 'YES',
            '-parallel-testing-worker-count', '1']
    product = pathlib.Path('build/Build/Products/Debug/VoodooTrackerXTests.xctest/Contents/MacOS/VoodooTrackerXTests')
    options = runtime_context('app-asan', product)
    options.update({'VTX_REQUIRE_LOOP_ASAN': '1', 'TEST_RUNNER_VTX_REQUIRE_LOOP_ASAN': '1',
                    'VTX_LOOP_ASAN_EVIDENCE_ROOT': APP_RUNTIME['directory'],
                    'TEST_RUNNER_VTX_LOOP_ASAN_EVIDENCE_ROOT': APP_RUNTIME['directory']})
    result = root / 'asan.xcresult'
    text = run('app-asan', base + ['-configuration', 'Debug', '-enableAddressSanitizer', 'YES',
        '-enableThreadSanitizer', 'NO', '-resultBundlePath', str(result)] +
        ['-only-testing:VoodooTrackerXTests/' + selector for selector in APP] + ['test'], options, True,
        separate_stderr=True)
    image(product, True)
    result_cases(result, 103, APP)
    attribution, removed = app_case_attribution_text(text, result)
    attribution_log = root / 'app-asan-case-attribution.log'
    attribution_log.write_text(attribution)
    attribution_receipt = {'rawStdoutSHA256': sha(root / 'app-asan.log'),
                           'rawStderrSHA256': sha(root / 'app-asan.stderr.log'),
                           'derivedSHA256': sha(attribution_log),
                           'removedFooterCount': len(removed), 'removedFooters': removed}
    (root / 'app-asan-case-attribution.json').write_text(json.dumps(attribution_receipt, indent=2))
    emit({'stage': 'app-asan-case-attribution', **attribution_receipt})
    mapping = app_case_pid_mapping(attribution)
    file_marker_pids = loop_file_marker_pids(APP_RUNTIME)
    app_pids = runtime_proof('app-asan', mapping, APP)
    console_query = subprocess.run(['xcrun', 'xcresulttool', 'get', 'log', '--type', 'console',
                                   '--path', str(result)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (root / 'app-asan-console-query.log').write_bytes(console_query.stdout + console_query.stderr)
    console = None
    if console_query.returncode == 0:
        (root / 'app-asan-console.json').write_bytes(console_query.stdout)
        console = json.loads(console_query.stdout)
    emit({'stage': 'app-asan-console', 'available': console_query.returncode == 0,
          'exitCode': console_query.returncode})
    marker_pids = loop_marker_pids(text + (root / 'app-asan.stderr.log').read_text(), console) | file_marker_pids
    loop_pids = {pid for name, pid in mapping if name.startswith('LoopEngineLifecycleTests/')}
    require(bool(loop_pids) and marker_pids == loop_pids and loop_pids <= app_pids,
            'Loop marker is not correlated to initialized executed-test PID')

    build = run('package-asan-build', ['swift', 'build', '--build-tests', '-c', 'debug',
                '--sanitize', 'address', '--disable-code-coverage', '-v'])
    require(package_asan_compiler_modes(build), 'ASan build/compiler modes')
    package = package_image('debug', True)
    before = sha(package)
    options = runtime_context('package-asan', package)
    text = run('package-asan', ['swift', 'test', '--skip-build', '-c', 'debug', '--sanitize', 'address',
        '--filter', '|'.join(re.escape(selector) + '$' for selector in PACKAGE_ASAN)], options, True)
    cases = package_cases(text, 69, PACKAGE_ASAN)
    # SwiftPM omits case PIDs. Require one actual mapped XCTest runner for this
    # exact workload; there is no ambiguous multi-process attribution fallback.
    matched = [pid for pid, observation in APP_RUNTIME['observations'].items() if observation['bundleMatched']]
    require(len(matched) == 1, 'SwiftPM workload does not have one attributable XCTest process')
    runtime_proof('package-asan', [(name, matched[0]) for name in cases], PACKAGE_ASAN)
    require(sha(package) == before, 'package ASan image changed during execution')

    result = root / 'release-app.xcresult'
    text = run('release-app', base + ['-configuration', 'Release', '-enableAddressSanitizer', 'NO',
        '-enableThreadSanitizer', 'NO', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG',
        '-resultBundlePath', str(result), 'test'])
    release_compiler(text, 'VoodooTrackerX', True)
    image('build/Build/Products/Release/VoodooTrackerXTests.xctest/Contents/MacOS/VoodooTrackerXTests', False)
    result_cases(result, APP_RELEASE_COUNT)
    build = run('package-release-build', ['swift', 'build', '--build-tests', '-c', 'release',
        '--disable-code-coverage', '-v', '-Xswiftc', '-enable-testing'])
    release_compiler(build, 'VoodooTrackerXPlaybackSupport', False)
    require('-enable-testing' in build, 'missing optimized package testability')
    package = package_image('release', False)
    before = sha(package)
    text = run('package-release', ['swift', 'test', '--skip-build', '-c', 'release'])
    package_cases(text, PACKAGE_RELEASE_COUNT)
    require(sha(package) == before, 'package Release image changed during execution')
    require(hashlib.sha256(GUARD_SOURCE.encode()).hexdigest() == GUARD_SHA, 'guard source changed')
    source, probe = root / 'GuardProbe.swift', root / 'guard-probe'
    source.write_text(GUARD_SOURCE)
    directory = package.parents[3]
    objects = sorted([*directory.glob('VoodooTrackerXPlaybackSupport.build/*.swift.o'),
                      *directory.glob('ModuleCore.build/**/*.o'), *directory.glob('MixerCore.build/**/*.o')])
    require(all(any(component + '.build' in str(p) for p in objects)
                for component in ['VoodooTrackerXPlaybackSupport', 'ModuleCore', 'MixerCore']), 'missing guard objects')
    command = ['xcrun', 'swiftc', '-O', '-g', '-parse-as-library', '-target', 'arm64-apple-macosx15.0']
    for component in ['Modules', 'ModuleCore.build', 'MixerCore.build']:
        command += ['-I', str(directory / component)]
    run('release-guard-build', command + [str(source), *map(str, objects), '-o', str(probe)])
    image(probe, False)
    for mode in ['read', 'fold', 'tail', 'assemble']:
        child = subprocess.run([str(probe), 'tests/reference-xm/generated/basic-instrument-sample.xm', mode],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (root / ('release-guard-' + mode + '.log')).write_bytes(child.stdout)
        require(child.returncode == -signal.SIGTRAP and b'GUARD_WAS_BYPASSED' not in child.stdout
                and b'AddressSanitizer' not in child.stdout, 'optimized guard did not trap: ' + mode)
        emit({'guard': mode, 'expectedSignal': 'SIGTRAP', 'passed': True})
    text = run('release-product', base + ['-configuration', 'Release', '-enableAddressSanitizer', 'NO',
                                        '-enableThreadSanitizer', 'NO', 'build'])
    release_compiler(text, 'VoodooTrackerX', False)
    linkage = output(['xcrun', 'otool', '-L', 'build/Build/Products/Release/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX'])
    require('XCTest' not in linkage, 'ordinary Release linked to XCTest')
    image('build/Build/Products/Release/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX', False)
    require(output(['git', 'rev-parse', 'HEAD']) == head and
            output(['git', 'status', '--porcelain=v1', '-uall']) == '', 'source changed during qualification')
    emit({'head': head, 'status': 'ISSUE516_NATIVE_PASS', 'appASan': 103, 'packageASan': 69,
          'optimizedAppRelease': APP_RELEASE_COUNT, 'optimizedPackageRelease': PACKAGE_RELEASE_COUNT, 'expectedReleaseTraps': 4,
          'failed': 0, 'skipped': 0})


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        if root is not None:
            (root / 'failure.txt').write_text(repr(error))
        raise
