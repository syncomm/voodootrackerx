import Foundation

/// Off-audio immutable owner of one prepared native batch. It retains no semantic plan.
/// The generation separately pins its PCM cache until host quiescence and C reset.
final class RuntimeLoopNativeBatchStorage {
    enum Failure: Error, Equatable {
        case invalidScope, invalidFrames, invalidRows, invalidOrdering, invalidCommand(Int)
        case missingSource(Int), incompatibleSource(Int), invalidBirth(Int), allocationSizeOverflow
    }

    let header: RuntimeLoopNativeBatchHeader
    let rowTimings: [PlaybackSongSyntheticRowTimingDiagnostic]
    let categories: [String]
    let preparedBirthCount: Int
    let ownedPODBytes: Int
    let naturalBoundaries: [PlaybackSongUserLoopProducer.NaturalBoundary]
    private let payloadStorage: UnsafeMutablePointer<RuntimeLoopPreparedCommandPayload>?
    private let commandStorage: UnsafeMutablePointer<RuntimeLoopNativeCommandDescriptor>?
    private let bindingStorage: UnsafeMutablePointer<RuntimeLoopNativeSourceBinding>?
    private let followStorage: UnsafeMutablePointer<RuntimeLoopNativeFollowRow>
    private let executedIDStorage: UnsafeMutablePointer<UInt64>?
    private let naturalBoundaryStorage: UnsafeMutablePointer<RuntimeLoopNativeIterationBoundary>?
    private let preparedBirths: [CSoftwareMixerPreparedLoopBirthStorage]

    /// Converts only after the producer reserved a channel slot. All allocations, cache
    /// lookups, native envelope preparation and ordering validation happen on that producer.
    /// Finite source geometry is borrowed during validation, never retained here.
    init(batch: PlaybackSongUserLoopProducer.Batch, scope: RuntimeLoopNativeScope,
         trackerChannelCount: Int, cache: CSoftwareMixerSharedSamplePayloadCache,
         recordsCategories: Bool = false, earlyCutover: RuntimeLoopNativeEarlyCutover? = nil,
         sourceSong: PlaybackSong? = nil) throws {
        let runtime = batch.adapterPlan
        let finite = scope.transportKind == .finiteSong
        let finiteTerminal = finite && batch.terminalStopReason != nil
        guard batch.sequence > 0, batch.predecessorSequence == batch.sequence - 1,
              trackerChannelCount > 0, trackerChannelCount <= Int(UInt32.max),
              runtime.generated, runtime.sampleRate.isFinite, runtime.sampleRate > 0,
              runtime.sampleRate.bitPattern == scope.sampleRateBits,
              scope.sourceGeneration > 0, scope.transportEpoch > 0,
              scope.firstRow >= 0, scope.lastRow >= scope.firstRow else { throw Failure.invalidScope }
        guard !finite || (sourceSong != nil && earlyCutover == nil &&
            sourceSong?.usesLinearFrequencyTable == scope.linearFrequencyMode),
              finite || batch.terminalStopReason == nil else { throw Failure.invalidScope }
        guard batch.startFrame >= 0, batch.endFrame > batch.startFrame,
              batch.runtimeEndFrame >= batch.endFrame,
              finiteTerminal || batch.runtimeEndFrame == batch.endFrame,
              batch.importedSourceCount >= 0, let plan = runtime.plan,
              batch.importedSourceCount <= plan.pattern.events.count else { throw Failure.invalidFrames }
        let rows = plan.diagnostics.rowTiming
        guard !rows.isEmpty, rows[0].rowStartFrame == batch.startFrame else { throw Failure.invalidRows }
        guard !finite || batch.rowArrayIndices.count == rows.count else { throw Failure.invalidRows }
        var expectedStart = batch.startFrame
        for (ordinal, row) in rows.enumerated() {
            let end = row.rowStartFrame.addingReportingOverflow(row.rowDurationFrames)
            let cycles = row.patternDelayCycles.addingReportingOverflow(1)
            guard row.rowStartFrame == expectedStart, row.rowDurationFrames > 0, !end.overflow,
                  end.partialValue <= batch.endFrame, row.rowStartExactFrame.isFinite,
                  row.rowEndExactFrame.isFinite, row.effectiveBPM > 0, row.effectiveSpeed > 0,
                  row.patternDelayCycles >= 0, !cycles.overflow,
                  !row.effectiveSpeed.multipliedReportingOverflow(by: cycles.partialValue).overflow
                else { throw Failure.invalidRows }
            if finite {
                let arrayIndex = batch.rowArrayIndices[ordinal]
                guard let pattern = sourceSong?.pattern(for: row.source.orderIndex),
                      pattern.index == row.source.patternIndex, pattern.rows.indices.contains(arrayIndex),
                      pattern.rows[arrayIndex].index == row.source.rowIndex else { throw Failure.invalidRows }
            } else {
                guard row.source.orderIndex == scope.order, row.source.patternIndex == scope.pattern,
                      (scope.firstRow...scope.lastRow).contains(row.source.rowIndex) else { throw Failure.invalidRows }
            }
            expectedStart = end.partialValue
        }
        guard expectedStart == batch.endFrame else { throw Failure.invalidRows }
        var previousNaturalFrame = batch.startFrame
        for boundary in batch.naturalBoundaries {
            guard boundary.frame > previousNaturalFrame, boundary.frame <= batch.endFrame,
                  boundary.stateToken > 0, (1...rows.count).contains(boundary.rowCount),
                  rows[boundary.rowCount - 1].rowStartFrame + rows[boundary.rowCount - 1].rowDurationFrames == boundary.frame else {
                throw Failure.invalidFrames
            }
            previousNaturalFrame = boundary.frame
        }
        if let earlyCutover {
            guard earlyCutover.boundaryFrame == UInt64(batch.startFrame),
                  earlyCutover.predecessorSequence == batch.predecessorSequence,
                  earlyCutover.boundaryStateToken > 0, earlyCutover.requestSerial > 0,
                  scope.sourceGeneration > earlyCutover.previousScope.sourceGeneration else { throw Failure.invalidScope }
        }
        let events = runtime.eventStorage.events, ordering = runtime.eventStorage.ordering
        let maximumEventID = events.reduce(-1) { max($0, $1.id) }
        let executedWordCount = maximumEventID >= 0 ? maximumEventID / 64 + 1 : 0
        guard ordering.count == events.count, runtime.plannedEventCount == events.count else {
            throw Failure.invalidOrdering
        }
        var seen = [Bool](repeating: false, count: events.count)
        var payloads = [RuntimeLoopPreparedCommandPayload]()
        var targets = [Int]()
        var bindings = [RuntimeLoopNativeSourceBinding]()
        var bindingBySource = [Int: Int]()
        var births = [CSoftwareMixerPreparedLoopBirthStorage]()
        payloads.reserveCapacity(events.count); targets.reserveCapacity(events.count)
        var previous: RuntimeCMixerAdapterEventStorage.OrderEntry?
        for entry in ordering {
            guard events.indices.contains(entry.eventIndex), !seen[entry.eventIndex],
                  (0...6).contains(entry.priority) else { throw Failure.invalidOrdering }
            seen[entry.eventIndex] = true
            let event = events[entry.eventIndex]
            let inOwnedFrames = (batch.startFrame..<batch.runtimeEndFrame).contains(event.scheduledFrame) ||
                (finiteTerminal && batch.runtimeEndFrame == batch.endFrame &&
                    event.scheduledFrame == batch.runtimeEndFrame)
            guard entry.scheduledFrame == event.scheduledFrame, entry.eventID == event.id, event.id >= 0,
                  inOwnedFrames,
                  (0..<trackerChannelCount).contains(event.channelIndex), event.syntheticTick >= 0 else {
                throw Failure.invalidCommand(entry.eventIndex)
            }
            if let previous {
                let ordered = previous.scheduledFrame < entry.scheduledFrame ||
                    (previous.scheduledFrame == entry.scheduledFrame &&
                        (previous.priority < entry.priority ||
                            (previous.priority == entry.priority && previous.eventID <= entry.eventID)))
                guard ordered else { throw Failure.invalidOrdering }
            }
            previous = entry
            let sourceIndex = event.activeEventIndex
            var targetOrdinal = -1
            if let sourceIndex {
                guard sourceIndex >= 0, sourceIndex < plan.pattern.events.count,
                      let identity = batch.sourceIdentities[sourceIndex] else {
                    throw Failure.missingSource(sourceIndex)
                }
                let trustedCarry = sourceIndex < batch.importedSourceCount && batch.authorizedCarriedBirths.contains(identity)
                guard (identity.sourceGeneration == scope.sourceGeneration || trustedCarry),
                      identity.transportEpoch == scope.transportEpoch,
                      identity.birthSequence > 0, identity.birthSequence <= batch.sequence,
                      identity.birthEventIndex >= 0 else { throw Failure.incompatibleSource(sourceIndex) }
                if let existing = bindingBySource[sourceIndex] { targetOrdinal = existing }
                else {
                    targetOrdinal = bindings.count
                    bindingBySource[sourceIndex] = targetOrdinal
                    bindings.append(.init(localLookupIndex: sourceIndex, birth: identity,
                        nativeSlot: -1, nativeIncarnation: 0))
                }
            }
            let action: RuntimeLoopPreparedCommandPayload.Action
            switch event.action {
            case let .noteTrigger(index, note, mapping):
                guard index >= batch.importedSourceCount, index == sourceIndex,
                      mapping.eventIndex == index, mapping.channelIndex == event.channelIndex,
                      let identity = batch.sourceIdentities[index],
                      identity.birthSequence == batch.sequence, identity.birthEventIndex == index else {
                    throw Failure.invalidBirth(entry.eventIndex)
                }
                // A legacy annotation may point into a tail discarded by a later edit.
                // Loop semantic/audible commands own release at actual executed frames.
                if note.keyOffFrame != nil {
                    guard plan.xmEnvelopeTimeline?.updatesByEvent[index]?.first?.scheduledFrame == event.scheduledFrame else {
                        throw Failure.invalidBirth(entry.eventIndex)
                    }
                }
                guard let prepared = CSoftwareMixerPreparedLoopBirthStorage(cache: cache, sample: note.sample,
                    gain: note.gain, pan: note.pan, playbackStep: note.playbackStep, loop: note.loop,
                    initialSourceFrame: note.initialSourceFrame, volumeEnvelope: note.volumeEnvelope,
                    panEnvelope: note.panEnvelope) else {
                    throw Failure.invalidBirth(entry.eventIndex)
                }
                births.append(prepared); action = .birth(prepared.birth)
            case let .gainPanUpdate(_, gain, pan):
                guard gain?.isFinite != false, pan?.isFinite != false else { throw Failure.invalidCommand(entry.eventIndex) }
                action = .gainPan(gain, pan)
            case let .stepUpdate(_, step):
                guard step.isFinite, step >= 0 else { throw Failure.invalidCommand(entry.eventIndex) }
                action = .step(step)
            case let .playbackStateChange(_, change):
                if case let .keyOff(decrement) = change {
                    guard decrement.isFinite, decrement >= 0 else { throw Failure.invalidCommand(entry.eventIndex) }
                }
                action = .playbackState(change)
            case let .envelopePositionUpdate(_, frame):
                guard frame >= 0 else { throw Failure.invalidCommand(entry.eventIndex) }
                action = .envelopePosition(frame)
            case let .envelopeSemanticUpdate(_, semantic):
                guard semantic.volumeValue.isFinite, semantic.panValue.isFinite else {
                    throw Failure.invalidCommand(entry.eventIndex)
                }
                action = .envelopeSemantic(semantic)
            case let .channelSemanticUpdate(update):
                guard update.channelIndex == event.channelIndex, update.selectionFrame >= 0,
                      update.selectionFrame <= event.scheduledFrame,
                      update.state.volumeValue.isFinite, update.state.panValue.isFinite else {
                    throw Failure.invalidCommand(entry.eventIndex)
                }
                // Producer rows and native C both use the reset generation's absolute frame clock.
                action = .channelSemantic(update, selectionRuntimeFrame: UInt64(update.selectionFrame))
            case let .audibleTargetUpdate(update):
                guard update.channelIndex == event.channelIndex, update.amplitude.isFinite,
                      update.pan.isFinite, update.durationFrames >= 0,
                      update.activation?.amplitude.isFinite != false,
                      update.activation?.pan.isFinite != false else { throw Failure.invalidCommand(entry.eventIndex) }
                action = .audible(amplitude: update.amplitude, pan: update.pan, duration: update.durationFrames,
                    activation: update.activation, rebase: update.rebaseFromCurrent)
            case let .sourceStop(_, retireSong): action = .sourceStop(retireSong: retireSong)
            case .noteCut: action = .noteCut
            }
            payloads.append(.init(source: event.source, tick: event.syntheticTick, action: action))
            targets.append(targetOrdinal)
        }
        // Check native byte strides before allocating or forming any stable pointer ranges.
        var bytes = 0
        for (count, stride) in [(payloads.count, MemoryLayout<RuntimeLoopPreparedCommandPayload>.stride),
            (payloads.count, MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride),
            (bindings.count, MemoryLayout<RuntimeLoopNativeSourceBinding>.stride),
            (rows.count, MemoryLayout<RuntimeLoopNativeFollowRow>.stride),
            (executedWordCount, MemoryLayout<UInt64>.stride),
            (batch.naturalBoundaries.count, MemoryLayout<RuntimeLoopNativeIterationBoundary>.stride)] {
            let product = count.multipliedReportingOverflow(by: stride)
            let total = bytes.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !total.overflow else { throw Failure.allocationSizeOverflow }
            bytes = total.partialValue
        }
        let payloadPointer: UnsafeMutablePointer<RuntimeLoopPreparedCommandPayload>? = payloads.isEmpty ? nil : .allocate(capacity: payloads.count)
        let commandPointer: UnsafeMutablePointer<RuntimeLoopNativeCommandDescriptor>? = payloads.isEmpty ? nil : .allocate(capacity: payloads.count)
        let bindingPointer: UnsafeMutablePointer<RuntimeLoopNativeSourceBinding>? = bindings.isEmpty ? nil : .allocate(capacity: bindings.count)
        let followPointer = UnsafeMutablePointer<RuntimeLoopNativeFollowRow>.allocate(capacity: rows.count)
        let executedPointer: UnsafeMutablePointer<UInt64>? = executedWordCount == 0 ? nil : .allocate(capacity: executedWordCount)
        executedPointer?.initialize(repeating: 0, count: executedWordCount)
        let naturalPointer: UnsafeMutablePointer<RuntimeLoopNativeIterationBoundary>? = batch.naturalBoundaries.isEmpty
            ? nil : .allocate(capacity: batch.naturalBoundaries.count)
        for (index, boundary) in batch.naturalBoundaries.enumerated() {
            naturalPointer!.advanced(by: index).initialize(to: .init(localFrame: boundary.frame,
                iteration: boundary.iteration, stateToken: boundary.stateToken))
        }
        for index in payloads.indices {
            payloadPointer!.advanced(by: index).initialize(to: payloads[index])
            let entry = ordering[index], event = events[entry.eventIndex]
            commandPointer!.advanced(by: index).initialize(to: .init(eventID: event.id,
                eventOrdinal: entry.eventIndex, localSourceIndex: event.activeEventIndex ?? -1,
                channel: event.channelIndex, localFrame: event.scheduledFrame, targetBindingOrdinal: targets[index],
                opcode: payloads[index].opcode, payload: UnsafeRawPointer(payloadPointer!.advanced(by: index))))
        }
        for index in bindings.indices { bindingPointer!.advanced(by: index).initialize(to: bindings[index]) }
        for (index, row) in rows.enumerated() {
            followPointer.advanced(by: index).initialize(to: .init(source: row.source,
                syntheticRow: row.syntheticRow, rowStartExactFrame: row.rowStartExactFrame,
                rowStartFrame: row.rowStartFrame, rowEndFrame: row.rowStartFrame + row.rowDurationFrames,
                effectiveSpeed: row.effectiveSpeed, effectiveBPM: row.effectiveBPM,
                actualTickCount: row.actualTickCount))
        }
        header = .init(scope: scope, sequence: batch.sequence, predecessorSequence: batch.predecessorSequence,
            predecessorStateToken: earlyCutover?.boundaryStateToken ?? batch.predecessorSequence, terminalStateToken: batch.sequence,
            firstIteration: batch.firstIteration, runtimeStartFrame: UInt64(batch.startFrame),
            runtimeEndFrame: UInt64(batch.runtimeEndFrame), localStartFrame: batch.startFrame,
            commands: commandPointer.map(UnsafeRawPointer.init), commandCount: payloads.count,
            commandStride: MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride,
            bindings: bindingPointer.map { UnsafePointer($0) }, bindingCount: bindings.count,
            followRows: UnsafePointer(followPointer), followRowCount: rows.count,
            executedRawIDWords: executedPointer, executedRawIDWordCount: executedWordCount,
            naturalBoundaries: naturalPointer.map { UnsafePointer($0) }, naturalBoundaryCount: batch.naturalBoundaries.count,
            earlyCutover: earlyCutover,
            finiteSongEndFrame: finiteTerminal ? UInt64(batch.endFrame) : nil)
        payloadStorage = payloadPointer; commandStorage = commandPointer; bindingStorage = bindingPointer
        followStorage = followPointer; executedIDStorage = executedPointer; naturalBoundaryStorage = naturalPointer
        naturalBoundaries = batch.naturalBoundaries
        rowTimings = rows; categories = recordsCategories ? runtime.categories : []
        preparedBirths = births; preparedBirthCount = births.count; ownedPODBytes = bytes
    }

    /// Producer only, after retirement acquire or host quiescence. The growing occurrence
    /// stream is never retained; this merges only the unchanged raw numeric ID domain.
    func mergeExecutedRawEventIDs(into result: inout Set<Int>) {
        guard let words = executedIDStorage else { return }
        for index in 0..<header.executedRawIDWordCount {
            var word = words[index]
            while word != 0 {
                result.insert(index * 64 + word.trailingZeroBitCount)
                word &= word - 1
            }
        }
    }

    deinit { // Channel reclaimer, after exact executed acknowledgement or host quiescence.
        commandStorage?.deinitialize(count: header.commandCount); commandStorage?.deallocate()
        payloadStorage?.deinitialize(count: header.commandCount); payloadStorage?.deallocate()
        bindingStorage?.deinitialize(count: header.bindingCount); bindingStorage?.deallocate()
        followStorage.deinitialize(count: header.followRowCount); followStorage.deallocate()
        executedIDStorage?.deinitialize(count: header.executedRawIDWordCount); executedIDStorage?.deallocate()
        naturalBoundaryStorage?.deinitialize(count: header.naturalBoundaryCount); naturalBoundaryStorage?.deallocate()
    }
}
