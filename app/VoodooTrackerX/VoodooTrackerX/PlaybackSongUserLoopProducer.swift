import Foundation

/// One serial off-audio owner of explicit user-pattern Loop semantic production.
/// Ordinary song playback never constructs this producer.
final class PlaybackSongUserLoopProducer {
    typealias Adapter = PlaybackSongSyntheticAdapter
    typealias Scratch = PlaybackSongLoopContinuation
    typealias Semantic = PlaybackSongSemanticPitchProjection
    typealias Automatic = PlaybackSongInstrumentAutovibratoPublication

    struct Batch {
        let sequence: UInt64
        let predecessorSequence: UInt64
        let firstIteration: UInt64
        let startFrame: Int
        let endFrame: Int
        let importedSourceCount: Int
        let sourceIdentities: [Int: RuntimeLoopNativeSourceIdentity]
        let adapterPlan: RuntimeCMixerAdapterEventPlan
        var naturalBoundaries: [NaturalBoundary] = []
        var authorizedCarriedBirths: Set<RuntimeLoopNativeSourceIdentity> = []
    }

    struct NaturalBoundary {
        let frame: Int
        let rowCount: Int
        let iteration: UInt64
        let stateToken: UInt64
    }

    enum Failure: Error { case invalidScope, invalidCheckpoint, incompatibleRefresh, cancelled, sequenceExhausted, unavailable }

    /// Owned checkpoint element/capacity observations, not a malloc or whole-app census.
    struct Resources: Equatable {
        let channels: Int, channelCapacity: Int
        let sources: Int, sourceCapacity: Int
        let selectionInputs: Int, originalSelectionScalars: Int
        let pendingPitchChildren: Int, resetFacts: Int
        let envelopeChannels: Int, audibleSources: Int
        let sourceMapCapacity: Int, factMapCapacity: Int
        let cachedSampleBuffers: Int, sampleCacheCapacity: Int
        let canonicalSampleBuffers: Int, canonicalSampleCapacity: Int
    }

    var resources: Resources {
        .init(channels: checkpoint?.scratch.channelCount ?? 0,
            channelCapacity: checkpoint?.scratch.channels.capacity ?? 0,
            sources: checkpoint?.scratch.sourceCount ?? 0,
            sourceCapacity: checkpoint?.scratch.sources.capacity ?? 0,
            selectionInputs: checkpoint?.scratch.selectionInputCount ?? 0,
            originalSelectionScalars: checkpoint?.scratch.selectionOriginCount ?? 0,
            pendingPitchChildren: checkpoint?.pending.childCount ?? 0,
            resetFacts: checkpoint?.resets.factCount ?? 0,
            envelopeChannels: checkpoint?.envelope.count ?? 0,
            audibleSources: checkpoint?.audible.count ?? 0,
            sourceMapCapacity: checkpoint?.sourceMap.capacity ?? 0,
            factMapCapacity: checkpoint?.factMap.capacity ?? 0,
            cachedSampleBuffers: sampleBuffers.count, sampleCacheCapacity: sampleBuffers.capacity,
            canonicalSampleBuffers: catalogSource.normalizedPCM.buffers.count,
            canonicalSampleCapacity: catalogSource.normalizedPCM.buffers.capacity)
    }

    fileprivate struct Checkpoint {
        let scratch: Scratch.Checkpoint
        let semantic: Semantic.ContinuationSeed
        let automatic: Automatic.Builder.ContinuationSeed
        let pending: PlaybackSongPendingRowPitch
        let sourceMap: [Int: Int]
        let factMap: [Int: Int]
        let global: Adapter.GlobalVolumeProjectionCheckpoint
        let envelope: [Int: PlaybackXMEnvelopeTimeline.ChannelCheckpoint]
        let audible: [Int: PlaybackXMAudibleTimeline.SourceCheckpoint]
        let resets: PlaybackSongLoopResetContinuation
    }

    /// Opaque bounded musical input. Source rows/plans/contexts and predecessor
    /// snapshots are absent; cached PCM values share existing immutable storage.
    struct ResumeState {
        fileprivate let checkpoint: Checkpoint?
        fileprivate let traversal: PlaybackSongTraversalPlanner.UserLoopState
        fileprivate let timing: PlaybackSongFxxTimingPlanner.State
        fileprivate let sampleBuffers: [Adapter.MixerSampleBufferCacheKey: MixerSampleBuffer]
        fileprivate let sampleKeys: [SampleIdentity: Adapter.MixerSampleBufferCacheKey]
        fileprivate let automaticEnabled: Bool
        fileprivate let catalogSource: CatalogSource
        let sourceGeneration: UInt64
        let transportEpoch: UInt64
        let sampleRate: Double
        let sequence: UInt64
        let usesLinearFrequencyTable: Bool
        var startFrame: Int { Int(timing.nextExactFrame.rounded(.down)) }
        var isNaturalBoundary: Bool { traversal.pendingBoundary != nil }
    }

    fileprivate struct SampleIdentity: Hashable { let instrument: Int, sample: Int }

    /// Preparation-only values shared by equal catalogs on the single producer worker.
    /// Canonical keys bound storage to the finite catalog, including revoked candidates.
    fileprivate final class NormalizedPCMCache {
        var buffers = [SampleIdentity: MixerSampleBuffer]()
    }

    /// Shared immutable source input, never a song/row/plan or a predecessor chain.
    /// Only normalized PCM preparation is mutable; it never advances musical state.
    fileprivate final class CatalogSource {
        struct RowShape: Equatable { let index: Int, channels: Int }
        let instruments: [Int: PlaybackInstrument]
        let initialTiming: PlaybackTiming
        let linear: Bool
        let order: Int
        let pattern: Int
        let shape: [RowShape]
        let normalizedPCM: NormalizedPCMCache

        init(song: PlaybackSong, order: Int, pattern: Int,
             normalizedPCM: NormalizedPCMCache = .init()) {
            self.normalizedPCM = normalizedPCM
            instruments = song.instrumentsByIndex; initialTiming = song.initialTiming
            linear = song.usesLinearFrequencyTable; self.order = order; self.pattern = pattern
            shape = song.pattern(for: order)?.rows.map { .init(index: $0.index, channels: $0.cells.count) } ?? []
        }
    }

    /// Only the factory can construct this proof. Its exact new source is owned here;
    /// the consuming initializer accepts no separate, retargetable song argument.
    struct RefreshCatalogProof {
        fileprivate let previousCatalog: CatalogSource
        fileprivate let previousGeneration: UInt64
        fileprivate let transportEpoch: UInt64
        fileprivate let sampleRateBits: UInt64
        fileprivate let nextGeneration: UInt64
        fileprivate let nextSong: PlaybackSong
        fileprivate let nextCatalog: CatalogSource
        fileprivate let nextKeys: [SampleIdentity: Adapter.MixerSampleBufferCacheKey]
        let validationNanoseconds: UInt64
    }

    /// Checks the current live-edit permission once while the ordinary ready successor
    /// remains published. A prefix resume from this same sealed source may consume it.
    static func prevalidateRefresh(song: PlaybackSong, resuming state: ResumeState,
                                  sourceGeneration: UInt64) throws -> RefreshCatalogProof {
        let started = DispatchTime.now().uptimeNanoseconds
        let old = state.catalogSource
        guard sourceGeneration > state.sourceGeneration,
              state.sampleRate.isFinite, state.sampleRate > 0,
              old.linear == state.usesLinearFrequencyTable,
              old.order == state.traversal.orderIndex, old.pattern == state.traversal.patternIndex,
              song.usesLinearFrequencyTable == old.linear, song.initialTiming == old.initialTiming,
              let pattern = song.pattern(for: old.order), pattern.index == old.pattern,
              pattern.rows.map({ CatalogSource.RowShape(index: $0.index, channels: $0.cells.count) }) == old.shape,
              old.instruments == song.instrumentsByIndex else { throw Failure.incompatibleRefresh }
        let next = CatalogSource(song: song, order: old.order, pattern: old.pattern,
            normalizedPCM: old.normalizedPCM)
        let keys = sampleKeys(in: song)
        return .init(previousCatalog: old, previousGeneration: state.sourceGeneration,
            transportEpoch: state.transportEpoch, sampleRateBits: state.sampleRate.bitPattern,
            nextGeneration: sourceGeneration, nextSong: song, nextCatalog: next, nextKeys: keys,
            validationNanoseconds: DispatchTime.now().uptimeNanoseconds - started)
    }

    private struct Prepared {
        var plan: PlaybackSongSyntheticPlan
        let checkpoint: Checkpoint
        let importedSourceCount: Int
        let identities: [Int: RuntimeLoopNativeSourceIdentity]
    }

    /// Synchronous worker scratch, released before native event assembly. Keeping
    /// row interpretation and terminal folding in separate frames bounds ASan stack use.
    private final class RowPreparation {
        var context = Adapter.AdapterRowContext()
        var imported = Scratch.Import()
        var resetInput: PlaybackSongLoopResetContinuation.Import?
        var automatic = Automatic.Builder()
        var ordinal = 0
        var mappings = [PlaybackSongSyntheticRowMapping]()
        var runs = [PlaybackSongCanonicalTickClock.ClockRun]()

        init(automaticEnabled: Bool) { automatic.enabled = automaticEnabled }
    }

    private let song: PlaybackSong
    private let sampleRate: Double
    private let sourceGeneration: UInt64
    private let transportEpoch: UInt64
    private let automaticEnabled: Bool
    private var traversal: PlaybackSongTraversalPlanner.UserLoopState
    private var timing: PlaybackSongFxxTimingPlanner.State
    private var checkpoint: Checkpoint?
    private var sequence: UInt64 = 0
    private var sampleBuffers = [Adapter.MixerSampleBufferCacheKey: MixerSampleBuffer]()
    private let sampleKeys: [SampleIdentity: Adapter.MixerSampleBufferCacheKey]
    private let catalogSource: CatalogSource
    private var trustedCarriedBirths = Set<RuntimeLoopNativeSourceIdentity>()
    private var trustedResetOriginScopes = Set<Scratch.Scope>()

    init(song: PlaybackSong, initialPosition: PlaybackPosition, sampleRate: Double,
         sourceGeneration: UInt64, transportEpoch: UInt64) throws {
        guard let state = PlaybackSongTraversalPlanner.makeUserLoopState(song, initialPosition: initialPosition),
              sampleRate.isFinite, sampleRate > 0 else { throw Failure.invalidScope }
        self.song = song; self.sampleRate = sampleRate
        self.sourceGeneration = sourceGeneration; self.transportEpoch = transportEpoch
        traversal = state
        let config = SyntheticTrackerTimingConfig(speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm, sampleRate: sampleRate)
        timing = .init(speed: config.speed, bpm: config.bpm, nextExactFrame: 0)
        automaticEnabled = song.instrumentsByIndex.values.contains { $0.autoVibrato.depth > 0 && $0.autoVibrato.rate > 0 }
        sampleKeys = Self.sampleKeys(in: song)
        catalogSource = .init(song: song, order: state.orderIndex, pattern: state.patternIndex)
    }

    /// Replays the old source with its original birth sequence, or starts a
    /// validated new revision at an actual natural boundary without retriggering.
    init(song: PlaybackSong, resuming state: ResumeState, sourceGeneration: UInt64,
         previousSong: PlaybackSong? = nil) throws {
        guard song.usesLinearFrequencyTable == state.usesLinearFrequencyTable,
              sourceGeneration >= state.sourceGeneration else { throw Failure.incompatibleRefresh }
        self.song = song; sampleRate = state.sampleRate; transportEpoch = state.transportEpoch
        self.sourceGeneration = sourceGeneration
        timing = state.timing; sequence = state.sequence; checkpoint = state.checkpoint
        automaticEnabled = state.automaticEnabled
        if sourceGeneration == state.sourceGeneration {
            traversal = state.traversal; sampleBuffers = state.sampleBuffers; sampleKeys = state.sampleKeys
            catalogSource = state.catalogSource
        } else {
            guard let previousSong, previousSong.instrumentsByIndex == song.instrumentsByIndex,
                  state.catalogSource.instruments == song.instrumentsByIndex,
                  let entry = PlaybackSongTraversalPlanner.resumeUserLoopAtNaturalEntry(song, previous: state.traversal)
                else { throw Failure.incompatibleRefresh }
            traversal = entry
            catalogSource = .init(song: song, order: entry.orderIndex, pattern: entry.patternIndex,
                normalizedPCM: state.catalogSource.normalizedPCM)
            let keys = Self.sampleKeys(in: song)
            sampleKeys = keys
            // Equal value-owned PCM may have a fresh Array storage identity. Reuse
            // its already sanitized buffer instead of growing a per-edit C cache.
            for (identity, old) in state.sampleKeys {
                if let buffer = state.sampleBuffers[old], let next = keys[identity] { sampleBuffers[next] = buffer }
            }
        }
        seedNormalizedPCM()
        if let checkpoint = state.checkpoint {
            trustedCarriedBirths = Set(checkpoint.scratch.sources.map(\.birth))
            trustedResetOriginScopes = Set(checkpoint.resets.rows.map { $0.origin.identity.scope } +
                checkpoint.resets.delayed.map { $0.origin.identity.scope })
        }
    }

    /// Consumes a prevalidated exact source at its actual natural boundary.
    /// Identity checks are scalar/reference-only; catalog/PCM equality is not repeated.
    init(resuming state: ResumeState, validatedRefresh proof: RefreshCatalogProof) throws {
        guard proof.previousCatalog === state.catalogSource,
              proof.previousGeneration == state.sourceGeneration,
              proof.transportEpoch == state.transportEpoch,
              proof.sampleRateBits == state.sampleRate.bitPattern,
              proof.nextGeneration > state.sourceGeneration,
              proof.nextCatalog.linear == state.usesLinearFrequencyTable,
              let entry = PlaybackSongTraversalPlanner.resumeUserLoopAtNaturalEntry(
                proof.nextSong, previous: state.traversal) else { throw Failure.incompatibleRefresh }
        song = proof.nextSong; sampleRate = state.sampleRate; transportEpoch = state.transportEpoch
        sourceGeneration = proof.nextGeneration; automaticEnabled = state.automaticEnabled
        catalogSource = proof.nextCatalog; sampleKeys = proof.nextKeys
        traversal = entry; timing = state.timing; sequence = state.sequence; checkpoint = state.checkpoint
        for (identity, old) in state.sampleKeys {
            if let buffer = state.sampleBuffers[old], let next = proof.nextKeys[identity] { sampleBuffers[next] = buffer }
        }
        seedNormalizedPCM()
        if let checkpoint = state.checkpoint {
            trustedCarriedBirths = Set(checkpoint.scratch.sources.map(\.birth))
            trustedResetOriginScopes = Set(checkpoint.resets.rows.map { $0.origin.identity.scope } +
                checkpoint.resets.delayed.map { $0.origin.identity.scope })
        }
    }

    func exportResumeState() -> ResumeState {
        .init(checkpoint: checkpoint, traversal: traversal, timing: timing, sampleBuffers: sampleBuffers,
            sampleKeys: sampleKeys, automaticEnabled: automaticEnabled, catalogSource: catalogSource,
            sourceGeneration: sourceGeneration,
            transportEpoch: transportEpoch, sampleRate: sampleRate, sequence: sequence,
            usesLinearFrequencyTable: song.usesLinearFrequencyTable)
    }

    private static func sampleKeys(in song: PlaybackSong) -> [SampleIdentity: Adapter.MixerSampleBufferCacheKey] {
        var result = [SampleIdentity: Adapter.MixerSampleBufferCacheKey]()
        for (instrument, value) in song.instrumentsByIndex { for sample in value.samples {
            result[.init(instrument: instrument, sample: sample.sampleIndex)] = sample.pcm.withUnsafeBufferPointer {
                .init(storageAddress: UInt(bitPattern: $0.baseAddress), frameCount: $0.count)
            }
        } }
        return result
    }

    /// Seeds only immutable PCM preparation, never checkpoint execution or source bindings.
    private func seedNormalizedPCM() {
        for (identity, key) in sampleKeys {
            if let buffer = catalogSource.normalizedPCM.buffers[identity] { sampleBuffers[key] = buffer }
        }
    }

    /// Remembers successful sanitization even if subsequent semantic/native work is revoked.
    /// Equal revisions use their own raw storage keys while sharing one canonical buffer.
    private func rememberNormalizedPCM(_ buffers: [Adapter.MixerSampleBufferCacheKey: MixerSampleBuffer]) {
        for (identity, key) in sampleKeys where catalogSource.normalizedPCM.buffers[identity] == nil {
            if let buffer = buffers[key] { catalogSource.normalizedPCM.buffers[identity] = buffer }
        }
    }

    /// Produces only after the caller reserved its single successor slot. Speculative
    /// terminal values do not acknowledge native delivery or advance its frontier.
    func next(minimumHorizonFrames: Int, maximumRows: Int = 128,
              untilFrame: Int? = nil, nextRowOverride: PlaybackRow? = nil,
              minimumNaturalBoundaryTailFrames: Int = 0,
              isCancelled: (() -> Bool)? = nil) throws -> Batch {
        guard sequence < .max else { throw Failure.sequenceExhausted }
        guard isCancelled?() != true else { throw Failure.cancelled }
        guard let visits = PlaybackSongTraversalPlanner.planUserLoopBatch(song, state: traversal,
            timing: timing, sampleRate: sampleRate, minimumHorizonFrames: minimumHorizonFrames,
            maximumRows: maximumRows, untilFrame: untilFrame,
            minimumNaturalBoundaryTailFrames: minimumNaturalBoundaryTailFrames, isCancelled: isCancelled) else {
            throw isCancelled?() == true ? Failure.cancelled : Failure.unavailable
        }
        let nextSequence = sequence + 1
        var prepared = try interpret(visits, sequence: nextSequence, nextRowOverride: nextRowOverride, isCancelled: isCancelled)
        let start = visits.timing.rowTimings[0].rowStartFrame
        let end = visits.timing.rowTimings.last!.rowEndFrame
        // Full row captures retire before wide native event assembly. All checkpoint
        // extraction above completed while those captures were deliberately available.
        prepared.plan.$xmChannelRows.finalizeForRuntime()
        let bounded = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: sampleRate,
            preparedPlan: prepared.plan, rowCaptureRetention: .runtimeFinalized,
            isCancelled: isCancelled, lookupOnlySourceCount: prepared.importedSourceCount,
            admittedFrames: start..<end)
        guard bounded.generated, isCancelled?() != true else { throw Failure.cancelled }
        var boundaries = [NaturalBoundary]()
        for index in visits.iterationByRow.indices {
            let natural = index + 1 < visits.iterationByRow.count
                ? visits.iterationByRow[index] != visits.iterationByRow[index + 1]
                : visits.terminalTraversal.pendingBoundary != nil
            if natural {
                guard visits.iterationByRow[index] < .max else { throw Failure.sequenceExhausted }
                boundaries.append(.init(frame: visits.timing.rowTimings[index].rowEndFrame, rowCount: index + 1,
                    iteration: visits.iterationByRow[index] + 1,
                    stateToken: index + 1 == visits.iterationByRow.count ? nextSequence : UInt64(index + 1)))
            }
        }
        let result = Batch(sequence: nextSequence, predecessorSequence: sequence,
            firstIteration: visits.iterationByRow[0], startFrame: start, endFrame: end,
            importedSourceCount: prepared.importedSourceCount, sourceIdentities: prepared.identities,
            adapterPlan: bounded, naturalBoundaries: boundaries,
            authorizedCarriedBirths: Set(prepared.identities.values.filter { $0.sourceGeneration != sourceGeneration }))
        checkpoint = prepared.checkpoint
        traversal = visits.terminalTraversal; timing = visits.timing.terminalState
        sequence = nextSequence
        return result
    }

    // Keep row-interpreter scratch out of the event assembler's Debug/ASan stack.
    @inline(never)
    private func interpret(_ visits: PlaybackSongTraversalPlanner.UserLoopBatch, sequence: UInt64,
                           nextRowOverride: PlaybackRow?, isCancelled: (() -> Bool)?) throws -> Prepared {
        let scratch = RowPreparation(automaticEnabled: automaticEnabled)
        defer { rememberNormalizedPCM(scratch.context.mixerSampleBuffers) }
        try interpretRows(visits, context: &scratch.context, scratch: scratch,
            nextRowOverride: nextRowOverride, isCancelled: isCancelled)
        return try finishInterpretedRows(visits, sequence: sequence,
            context: &scratch.context, scratch: scratch, isCancelled: isCancelled)
    }

    @inline(never)
    private func interpretRows(_ visits: PlaybackSongTraversalPlanner.UserLoopBatch,
                               context: inout Adapter.AdapterRowContext, scratch: RowPreparation,
                               nextRowOverride: PlaybackRow?, isCancelled: (() -> Bool)?) throws {
        let rows = visits.traversal.rows, framePlan = visits.timing
        let start = framePlan.rowTimings[0].rowStartFrame
        // Match ordinary adaptation's construction estimates, using only this
        // bounded interval. No unplayed song rows or prior batches are retained.
        let estimatedRows = rows.count
        scratch.mappings.reserveCapacity(estimatedRows)
        scratch.runs.reserveCapacity(estimatedRows)
        context.rowDiagnostics.reserveCapacity(estimatedRows)
        context.events.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.eventMappings.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.ignoredCells.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.deferredCellFields.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.effectCommandDiagnostics.reserveCapacity(min(estimatedRows, 65_536))
        context.volumeColumnMappings.reserveCapacity(min(estimatedRows, 65_536))
        context.voiceStateUpdates.reserveCapacity(min(estimatedRows * 2, 65_536))
        if let checkpoint {
            scratch.imported = try checkpoint.scratch.restore(into: &context, source: rows[0].source,
                batchStartFrame: start, linear: song.usesLinearFrequencyTable)
            guard let resets = checkpoint.resets.restore(into: &context),
                context.semanticPitchBuilder.restoreContinuation(checkpoint.semantic,
                factMap: checkpoint.factMap, sourceMap: checkpoint.sourceMap,
                ownerFactIndices: scratch.imported.ownerFactIndices, rowResetMap: resets.rowResetMap,
                delayedResetMap: resets.delayedResetMap),
                checkpoint.pending.restore(into: &context, sourceMap: checkpoint.sourceMap,
                    mappingMap: checkpoint.sourceMap) != nil else { throw Failure.invalidCheckpoint }
            scratch.resetInput = resets
            scratch.automatic.restoreContinuation(checkpoint.automatic, sourceMap: checkpoint.sourceMap)
            scratch.ordinal = checkpoint.semantic.nextOrdinal
        }
        // A ResumeState may predate the first preparation or a revoked sibling candidate.
        // Refresh its PCM aliases without importing any of that candidate's musical state.
        seedNormalizedPCM()
        context.mixerSampleBuffers = sampleBuffers
        context.traversalEffectStatuses = Adapter.traversalEffectStatuses(from: visits.traversal.traversalDiagnostics)
        for (index, row) in rows.enumerated() {
            guard isCancelled?() != true else { throw Failure.cancelled }
            let rowTiming = framePlan.rowTimings[index]
            let config = framePlan.timingConfig(forSyntheticRow: index)
            scratch.mappings.append(.init(source: row.source, syntheticRow: index))
            scratch.runs.append(.init(timingRowIndex: index, firstCanonicalTickOrdinal: scratch.ordinal))
            context.semanticPitchBuilder.begin(states: context.channelStates, count: row.row.cells.count,
                firstOrdinal: scratch.ordinal, speed: config.actualTickCount, linear: song.usesLinearFrequencyTable,
                retriggers: context.retriggerEffects.count, rowResets: context.rowEntryTriggerResetObserver.facts.count,
                delayedResets: context.delayedInstrumentResetObserver.facts.count,
                exits: context.rowExitObserver.references.count, rows: context.xmChannelRows.count)
            context.semanticPitchBuilder.firstRelease = context.keyOffEvents.count
            let diagnostic = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: index,
                song: song, timingConfig: config, timingPlan: framePlan, scheduledStartFrame: rowTiming.rowStartFrame,
                nextRow: index + 1 < rows.count ? rows[index + 1].row : nextRowOverride ?? visits.nextRow, context: &context)
            Adapter.finishSemanticPitchRow(context: &context, song: song)
            if automaticEnabled {
                Adapter.materializeInstrumentAutovibratoRow(context: &context, builder: &scratch.automatic,
                    source: row.source, row: index, channelCount: row.row.cells.count,
                    timingConfig: config, timingPlan: framePlan)
            }
            context.rowDiagnostics.append(diagnostic)
            let next = scratch.ordinal.addingReportingOverflow(config.actualTickCount)
            guard !next.overflow else { throw Failure.sequenceExhausted }; scratch.ordinal = next.partialValue
        }
    }

    @inline(never)
    private func finishInterpretedRows(_ visits: PlaybackSongTraversalPlanner.UserLoopBatch, sequence: UInt64,
                                      context: inout Adapter.AdapterRowContext, scratch: RowPreparation,
                                      isCancelled: (() -> Bool)?) throws -> Prepared {
        let rows = visits.traversal.rows, framePlan = visits.timing
        let start = framePlan.rowTimings[0].rowStartFrame, end = framePlan.rowTimings.last!.rowEndFrame
        // A batch boundary never invokes the terminal song-tail reducer.
        var global = Adapter.GlobalVolumeProjectionCheckpoint()
        Adapter.planGlobalVolumeChannelTargets(timingPlan: framePlan, context: &context,
            initialState: checkpoint?.global, includeTerminalTail: false, terminalCheckpoint: { global = $0 })
        var folds: Adapter.ContinuationFoldOutput?
        let input = Adapter.ContinuationFoldInput(batchStartFrame: start,
            importedEventIndices: Set(0..<context.importedSourceCount), envelope: checkpoint?.envelope,
            audible: checkpoint?.audible, pitch: scratch.imported.pitchSeed)
        guard var plan = Adapter.finishAdaptation(song: song, startOrderIndex: traversal.orderIndex, orderCount: 1,
            timingPlan: framePlan, traversalPlan: visits.traversal,
            timingConfig: .init(speed: framePlan.initialSpeed, bpm: framePlan.initialBPM, sampleRate: sampleRate),
            rowMappings: scratch.mappings, clockRuns: scratch.runs, canonicalTickCount: scratch.ordinal, context: &context,
            automaticPitchBuilder: scratch.automatic, profileSession: nil, totalStart: nil, eligibilityOracle: nil,
            isCancelled: isCancelled, continuation: input, terminalCheckpoint: { folds = $0 }),
            let folds else { throw isCancelled?() == true ? Failure.cancelled : Failure.unavailable }
        let semantic = context.semanticPitchBuilder.exportContinuation(plan: plan,
            terminalChannels: context.channelStates, nextOrdinal: scratch.ordinal)
        let pending = PlaybackSongPendingRowPitch.capture(plan: plan, lastSyntheticRow: rows.count - 1,
            boundaryFrame: end, ordinaryDelayedVibratoIndices: context.ordinaryDelayedVibratoIndices)
        var wanted = Set(pending.arpeggios.compactMap { $0.command.activeEventIndex })
        wanted.formUnion(pending.vibratos.compactMap { $0.command.activeEventIndex })
        wanted.formUnion(semantic.pending.map(\.generation).filter { $0 >= 0 })
        guard let resetSources = PlaybackSongLoopResetContinuation.requiredSourceIndices(plan: plan, seed: semantic)
            else { throw Failure.invalidCheckpoint }
        wanted.formUnion(resetSources)
        let owners = Dictionary(uniqueKeysWithValues: semantic.channels.enumerated().map { channel, value in
            (channel, Scratch.OwnerObservation(instrument: value.owner.instrument, sample: value.owner.sample,
                carriedInstrument: value.owner.carriedInstrument,
                sourceEventIndex: value.generation >= 0 ? value.generation : nil))
        })
        let compact = try Scratch.export(scope: .init(sourceGeneration: sourceGeneration,
            transportEpoch: transportEpoch, sequence: sequence), song: song, context: context, plan: plan,
            boundaryFrame: end, sourceIdentities: scratch.imported.sourceIdentities, pitch: folds.pitch,
            retainingSources: wanted, importedSelectionOrigins: scratch.imported.selectionOrigins,
            ownerOverrides: owners,
            semanticSelectionIndices: context.semanticPitchBuilder.states.map { $0.selection >= 0 ? $0.selection : nil },
            trustedCarriedBirths: trustedCarriedBirths,
            isCancelled: isCancelled)
        var envelope = folds.envelope
        for channel in envelope.keys {
            if let old = envelope[channel]?.route?.sourceEventIndex {
                guard let mapped = compact.sourceMap[old] else { throw Failure.invalidCheckpoint }
                envelope[channel]?.route?.sourceEventIndex = mapped
            }
        }
        let audible = folds.audible.reduce(into: [Int: PlaybackXMAudibleTimeline.SourceCheckpoint]()) { result, pair in
            if let mapped = compact.sourceMap[pair.key] { result[mapped] = pair.value }
        }
        guard let resets = PlaybackSongLoopResetContinuation.capture(
            scope: .init(sourceGeneration: sourceGeneration, transportEpoch: transportEpoch, sequence: sequence),
            plan: plan, seed: semantic, sourceMap: compact.sourceMap, sourceIdentities: scratch.imported.sourceIdentities,
            importedSourceCount: context.importedSourceCount, importedRows: scratch.resetInput?.rowOrigins ?? [:],
            importedDelayed: scratch.resetInput?.delayedOrigins ?? [:], trustedCarriedBirths: trustedCarriedBirths,
            trustedOriginScopes: trustedResetOriginScopes) else { throw Failure.invalidCheckpoint }
        let terminal = Checkpoint(scratch: compact.checkpoint, semantic: semantic,
            automatic: scratch.automatic.exportContinuation(), pending: pending, sourceMap: compact.sourceMap,
            factMap: compact.factMap, global: global.remappedSources(compact.sourceMap),
            envelope: envelope, audible: audible, resets: resets)
        var identities = scratch.imported.sourceIdentities
        for index in context.importedSourceCount..<plan.pattern.events.count {
            identities[index] = .init(sourceGeneration: sourceGeneration, transportEpoch: transportEpoch,
                birthSequence: sequence, birthEventIndex: index)
        }
        sampleBuffers = context.mixerSampleBuffers
        plan.$xmChannelRows.finalizeForRuntime()
        return .init(plan: plan, checkpoint: terminal, importedSourceCount: context.importedSourceCount, identities: identities)
    }
}
