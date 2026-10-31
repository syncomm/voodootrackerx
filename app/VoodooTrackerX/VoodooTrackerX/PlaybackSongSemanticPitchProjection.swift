import Foundation

/// Depth-off native semantics; physical delivery and source eligibility remain separate.
struct PlaybackSongSemanticPitchProjection: Equatable {
    typealias Family = PlaybackSongNativePitchWriterSpans.Family
    enum Coverage { case notAdapterProduced, nativeDepthOffV1 }
    enum Pitch: Equatable { case known(Double), notEstablished, notCaptured }
    enum Producer: Equatable {
        case incoming, selection(Int), nativeWriter(span: Int, child: Int)
        case diagnosticScalar(family: Family, index: Int), rowExit(family: Family, index: Int)
        case notCaptured
    }
    struct Result: Equatable {
        let base: Pitch, output: Pitch, incoming: Pitch
        // Incoming is the semantic effect latch before the last writer, separately from arithmetic base.
        let baseProducer: Producer, producer: Producer, incomingProducer: Producer
        let semanticInstrument: Int?, semanticSample: Int?, carriedInstrument: Int?
        let associatedGeneration: Int?, selectionFactIndex: Int?, emptyRouteIndex: Int?, rowControlIndex: Int?
        let rowEntryResetIndex: Int?, delayedResetIndex: Int?
    }
    /// Packed references share existing producer storage, including original numeric children.
    struct Ref: Equatable {
        enum Kind: UInt64 { case cold, missing, selection, writer, writerInput, fineUp, fineDown, extraFine, arpExit, vibratoExit, suppressedExit, toneHold, seed }
        let raw: UInt64
        init(_ kind: Kind, _ index: Int = 0, _ child: Int = 0) {
            precondition(index >= 0 && index < 1 << 28 && child >= 0 && child < 1 << 28)
            raw = kind.rawValue << 56 | UInt64(index) << 28 | UInt64(child)
        }
        var kind: Kind { Kind(rawValue: raw >> 56)! }
        var index: Int { Int(raw >> 28 & 0x0fff_ffff) }
        var child: Int { Int(raw & 0x0fff_ffff) }
        var producer: Producer {
            switch kind {
            case .cold, .seed: return .incoming
            case .missing: return .notCaptured
            case .selection: return .selection(index)
            case .writer, .writerInput: return .nativeWriter(span: index, child: child)
            case .fineUp: return .diagnosticScalar(family: .finePortamentoUp, index: index)
            case .fineDown: return .diagnosticScalar(family: .finePortamentoDown, index: index)
            case .extraFine: return .diagnosticScalar(family: .extraFinePortamento, index: index)
            case .toneHold: return .diagnosticScalar(family: .tonePortamento, index: index)
            case .arpExit: return .rowExit(family: .arpeggio, index: index)
            case .vibratoExit: return .rowExit(family: .vibrato, index: index)
            case .suppressedExit: return .rowExit(family: .vibrato, index: child)
            }
        }
    }
    struct Record: Equatable {
        var ordinal = 0
        var base = Ref(.cold), output = Ref(.cold), incoming = Ref(.cold)
        var selection = -1, generation = -1
        func sameState(as other: Self) -> Bool {
            base == other.base && output == other.output && incoming == other.incoming &&
                selection == other.selection && generation == other.generation
        }
    }
    /// Sparse reset provenance retains exact actual invocation coordinates independently of pitch.
    struct ResetRun: Equatable { var ordinal: Int, rowReset: Int, delayedReset: Int }
    let coverage: Coverage
    let channels: [[Record]]
    let resetRuns: [[ResetRun]]
    let seeds: [Double]
    let storageGrowthCount: Int
    let workspaceCapacity: Int
    let captureFailureCount: Int
    var recordCount: Int { channels.reduce(0) { $0 + $1.count } }
    var recordCapacity: Int { channels.reduce(0) { $0 + $1.capacity } }
    var resetRunCount: Int { resetRuns.reduce(0) { $0 + $1.count } }
    var resetRunCapacity: Int { resetRuns.reduce(0) { $0 + $1.capacity } }
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, channels: [], resetRuns: [], seeds: [], storageGrowthCount: 0, workspaceCapacity: 0, captureFailureCount: 0)

    func pitch(_ ref: Ref, plan: PlaybackSongSyntheticPlan) -> Pitch {
        func known(_ value: Double?) -> Pitch { value.map(Pitch.known) ?? .notCaptured }
        let linear = plan.nativePitchWriterSpans.domain == .linear
        switch ref.kind {
        case .cold: return .notEstablished
        case .missing: return .notCaptured
        case .seed: return seeds.indices.contains(ref.index) ? .known(seeds[ref.index]) : .notCaptured
        case .selection:
            guard plan.selectionDispatchFacts.facts.indices.contains(ref.index) else { return .notCaptured }
            switch plan.selectionDispatchFacts.facts[ref.index].pitch {
            case .known(_, let value): return .known(value)
            case .unavailable: return .notEstablished
            }
        case .writer, .writerInput:
            guard plan.nativePitchWriterSpans.spans.indices.contains(ref.index),
                  let child = plan.nativePitchWriterSpans.spans[ref.index].child(at: ref.child) else { return .notCaptured }
            return known(ref.kind == .writerInput
                ? (linear ? child.linearPeriodBefore : child.amigaPeriodBefore)
                : (linear ? child.linearPeriodAfter : child.amigaPeriodAfter))
        case .fineUp:
            guard plan.diagnostics.finePortamentoUpEffects.indices.contains(ref.index) else { return .notCaptured }
            return known(ref.child == 1 ? plan.diagnostics.finePortamentoUpEffects[ref.index].currentLinearPeriodBefore
                : plan.diagnostics.finePortamentoUpEffects[ref.index].currentLinearPeriodAfter)
        case .fineDown:
            guard plan.diagnostics.finePortamentoDownEffects.indices.contains(ref.index) else { return .notCaptured }
            return known(ref.child == 1 ? plan.diagnostics.finePortamentoDownEffects[ref.index].currentLinearPeriodBefore
                : plan.diagnostics.finePortamentoDownEffects[ref.index].currentLinearPeriodAfter)
        case .extraFine:
            guard plan.diagnostics.extraFinePortamentoEffects.indices.contains(ref.index) else { return .notCaptured }
            return known(ref.child == 1 ? plan.diagnostics.extraFinePortamentoEffects[ref.index].currentLinearPeriodBefore
                : plan.diagnostics.extraFinePortamentoEffects[ref.index].currentLinearPeriodAfter)
        case .toneHold:
            guard plan.diagnostics.tonePortamentoEffects.indices.contains(ref.index) else { return .notCaptured }
            let command = plan.diagnostics.tonePortamentoEffects[ref.index]
            return known(linear ? command.currentLinearPeriodAfter : command.currentAmigaPeriodAfter)
        case .arpExit:
            guard plan.diagnostics.arpeggioEffects.indices.contains(ref.index) else { return .notCaptured }
            let command = plan.diagnostics.arpeggioEffects[ref.index]
            guard let child = command.subsumedRowExit ?? command.stepUpdates.last,
                  child.syntheticTick == (plan.diagnostics.rowTiming.indices.contains(command.syntheticRow) ? plan.diagnostics.rowTiming[command.syntheticRow].actualTickCount : command.rowSpeed) else { return .notCaptured }
            return known(linear ? child.linearPeriodAfter : child.amigaPeriodAfter)
        case .vibratoExit:
            guard plan.diagnostics.vibratoEffects.indices.contains(ref.index) else { return .notCaptured }
            let command = plan.diagnostics.vibratoEffects[ref.index]
            let child = ref.child > 0 && plan.nativePitchWriterSpans.spans.indices.contains(ref.child - 1)
                ? plan.nativePitchWriterSpans.spans[ref.child - 1].originalChildren.last
                : command.stepUpdates.last ?? command.inactiveSourceStepUpdates.last
            guard let child, child.syntheticTick == (plan.diagnostics.rowTiming.indices.contains(command.syntheticRow) ? plan.diagnostics.rowTiming[command.syntheticRow].actualTickCount : command.rowSpeed) else { return .notCaptured }
            return known(linear ? child.linearPeriodAfter : child.amigaPeriodAfter)
        case .suppressedExit:
            return known(plan.suppressedRowExit(at: ref.index)?.nativePeriodAfter)
        }
    }

    /// Negative owner references reuse existing empty routes (even) or row controls (odd).
    static func owner(_ index: Int, facts: borrowing [PlaybackSongSelectionDispatchFacts.Fact],
        rows: borrowing [PlaybackXMChannelRow], routes: borrowing [PlaybackXMEmptyRoute]) -> (Int?, Int?, Int?) {
        if index >= 0, facts.indices.contains(index) {
            return (facts[index].semanticInstrument, facts[index].semanticSample, facts[index].carriedInstrument)
        }
        guard index < -1 else { return (nil, nil, nil) }
        let raw = -2 - index, ordinal = raw / 2
        if raw % 2 == 0, routes.indices.contains(ordinal) {
            return (routes[ordinal].instrumentIndex, routes[ordinal].sampleIndex, routes[ordinal].instrumentIndex)
        }
        guard raw % 2 != 0, rows.indices.contains(ordinal) else { return (nil, nil, nil) }
        let row = rows[ordinal]
        return (row.controls.semanticInstrumentIndex, row.controls.semanticSampleIndex, row.controls.carriedInstrumentIndex)
    }

    /// Planning-only row workspace: no full controls, PCM, or retained numeric-child copies.
    struct Builder {
        enum Action {
            case writer(Ref, Bool, Int?, Double?), selection(Int), emptyRoute(Int), rowOwner(Int)
            case generation(Int), boundary(Ref)
            case automaticReset(PlaybackSongInstrumentAutovibratoClock.ResetCause), automaticRelease
            var ownerRef: Int? {
                switch self {
                case .selection(let index): return index
                case .emptyRoute(let index): return -2 - 2 * index
                case .rowOwner(let index): return -3 - 2 * index
                default: return nil
                }
            }
        }
        struct Operation { let tick: Int, channel: Int, ordinal: Int; let action: Action }
        struct Boundary { let channel: Int, generation: Int, index: Int; let ref: Ref }
        var channels = [[Record]](), states = [Record](), resetRuns = [[ResetRun]]()
        var automatic = PlaybackSongInstrumentAutovibratoClock.Builder()
        var baseValues = [Double?](), seeds = [Double]()
        var operations = [Operation](), pending = [Boundary](), following = [Boundary]()
        var touched = [Int](), lastTicks = [Int](), folds = [Int](), rowStarts = [Int](), entryOwners = [Int]()
        var firstOrdinal = 0, speed = 0, growths = 0, workspaceHighWater = 0, failures = 0
        var operationCapacityHighWater = 0, boundaryCapacityHighWater = 0, resetGrowths = 0
        var linear = true
        var firstRetrigger = 0, firstRowReset = 0, firstDelayedReset = 0, firstExit = 0, firstRow = 0
        var firstRelease = 0

        mutating func begin(states incoming: borrowing [PlaybackSongSyntheticAdapter.ChannelState], count: Int,
            firstOrdinal: Int, speed: Int, linear: Bool, retriggers: Int, rowResets: Int, delayedResets: Int, exits: Int, rows: Int) {
            self.firstOrdinal = firstOrdinal; self.speed = speed; self.linear = linear
            operations.removeAll(keepingCapacity: true); touched.removeAll(keepingCapacity: true)
            swap(&pending, &following); following.removeAll(keepingCapacity: true)
            firstRetrigger = retriggers; firstRowReset = rowResets; firstDelayedReset = delayedResets; firstExit = exits; firstRow = rows
            let capacities = (states.capacity, channels.capacity, baseValues.capacity, lastTicks.capacity, folds.capacity, rowStarts.capacity, resetRuns.capacity)
            while states.count < count {
                states.append(.init()); channels.append([]); resetRuns.append([]); baseValues.append(nil); lastTicks.append(-1); folds.append(-1); rowStarts.append(0); entryOwners.append(-1)
            }
            automatic.ensureChannels(count)
            growths += (capacities.0 != states.capacity ? 1 : 0) + (capacities.1 != channels.capacity ? 1 : 0)
                + (capacities.2 != baseValues.capacity ? 1 : 0) + (capacities.3 != lastTicks.capacity ? 1 : 0)
                + (capacities.4 != folds.capacity ? 1 : 0) + (capacities.5 != rowStarts.capacity ? 1 : 0)
                + (capacities.6 != resetRuns.capacity ? 1 : 0)
            for channel in states.indices {
                lastTicks[channel] = -1; folds[channel] = -1; rowStarts[channel] = channels[channel].count; entryOwners[channel] = states[channel].selection
                let native = incoming.indices.contains(channel) ? (linear ? incoming[channel].activeLinearPeriod : incoming[channel].activeAmigaPeriod) : nil
                if native != baseValues[channel] {
                    if let native {
                        let capacity = seeds.capacity
                        states[channel].base = Ref(.seed, seeds.count); seeds.append(native)
                        if capacity != seeds.capacity { growths += 1 }
                    } else { states[channel].base = Ref(.cold) }
                    // An incoming base observation cannot reconstruct an unobserved held writer.
                    states[channel].output = Ref(.missing)
                    baseValues[channel] = native
                    add(tick: 0, channel: channel, action: .boundary(states[channel].output))
                }
            }
        }

        mutating func add(tick: Int, channel: Int, action: Action) {
            guard tick >= 0 && tick < speed else { return }
            if tick == 0, let owner = action.ownerRef { entryOwners[channel] = owner }
            let capacity = operations.capacity
            operations.append(.init(tick: tick, channel: channel, ordinal: operations.count, action: action))
            if capacity != operations.capacity { growths += 1 }
        }

        mutating func writer(span: Int?, family: Family, index: Int, channel: Int, rowSpeed: Int,
            children: borrowing [PlaybackSongSyntheticTonePortamentoStepUpdate], folded: Int? = nil,
            scalar: Double? = nil, calculated: Bool = false, generation: Int? = nil) {
            let count = children.count - (children.last?.syntheticTick == rowSpeed ? 1 : 0)
            if let span {
                for child in 0..<count {
                    add(tick: children[child].syntheticTick, channel: channel,
                        action: .writer(Ref(.writer, span, child), family != .vibrato && family != .arpeggio, folded,
                            linear ? children[child].linearPeriodAfter : children[child].amigaPeriodAfter))
                }
            } else if calculated, scalar != nil {
                let kind: Ref.Kind = family == .finePortamentoUp ? .fineUp : family == .finePortamentoDown ? .fineDown : .extraFine
                add(tick: 0, channel: channel, action: .writer(Ref(kind, index), true, folded, scalar))
            }
            if let exit = children.last, exit.syntheticTick == rowSpeed {
                let capacity = following.capacity
                following.append(.init(channel: channel, generation: generation ?? -1, index: index,
                    ref: Ref(family == .arpeggio ? .arpExit : .vibratoExit, index, family == .vibrato ? (span.map { $0 + 1 } ?? 0) : 0)))
                if capacity != following.capacity { growths += 1 }
            }
        }

        mutating func finish(context: borrowing PlaybackSongSyntheticAdapter.AdapterRowContext, song: borrowing PlaybackSong) {
            for index in firstRow..<context.xmChannelRows.count {
                let channel = context.xmChannelRows[index].channelIndex
                let actual = Self.owner(-3 - 2 * index, context: context)
                if actual != Self.owner(entryOwners[channel], context: context) {
                    // Some ED snapshots include future dispatch; its existing operation owns timing.
                    let future = operations.contains { op in op.channel == channel && op.tick > 0 &&
                        op.action.ownerRef.map { Self.owner($0, context: context) == actual } == true }
                    if !future { add(tick: 0, channel: channel, action: .rowOwner(index)) }
                }
            }
            // E9 clones do not emit selection facts; their existing diagnostic owns generations.
            for index in firstRetrigger..<context.retriggerEffects.count {
                let command = context.retriggerEffects[index]
                if command.effectType == 14 && command.effectParam >> 4 == 9 {
                    for (tick, event) in zip(command.retriggerTicks, command.retriggerEventIndices) {
                        add(tick: tick, channel: command.channelIndex, action: .generation(event))
                        // New automatic-clock reset at a real E9 source dispatch, not an
                        // invented observation of the legacy aggregated effect-phase call.
                        if command.effectParam & 15 > 0 {
                            add(tick: tick, channel: command.channelIndex, action: .automaticReset(.retrigger))
                        }
                    }
                }
            }
            for index in firstRowReset..<context.rowEntryTriggerResetObserver.facts.count {
                let fact = context.rowEntryTriggerResetObserver.facts[index]
                appendReset(ordinal: firstOrdinal, channel: fact.channelIndex, index: index, delayed: false)
                add(tick: 0, channel: fact.channelIndex, action: .automaticReset(.rowEntry))
            }
            for index in firstDelayedReset..<context.delayedInstrumentResetObserver.facts.count {
                let fact = context.delayedInstrumentResetObserver.facts[index]
                appendReset(ordinal: firstOrdinal + fact.syntheticTick, channel: fact.channelIndex, index: index, delayed: true)
                add(tick: fact.syntheticTick, channel: fact.channelIndex, action: .automaticReset(.delayedInstrument))
            }
            for release in context.keyOffEvents[firstRelease...] where release.applied {
                add(tick: release.syntheticTick, channel: release.channelIndex, action: .automaticRelease)
            }
            for boundary in pending where states[boundary.channel].generation == boundary.generation {
                var ref = boundary.ref
                if ref.kind == .vibratoExit && ref.child == 0,
                   let index = (firstExit..<context.rowExitObserver.references.count).first(where: {
                       context.rowExitObserver.references[$0].outgoingDiagnosticIndex == boundary.index &&
                           context.rowExitObserver.references[$0].witness != .arpeggioDiagnostic
                   }) { ref = Ref(.suppressedExit, index, boundary.index) }
                // Subsumption removes physical delivery, not the genuine native restoration
                // seen by incoming calculation. It still precedes the next canonical tick.
                operations.append(.init(tick: 0, channel: boundary.channel, ordinal: -1, action: .boundary(ref)))
            }
            operations.sort { $0.tick != $1.tick ? $0.tick < $1.tick : $0.ordinal < $1.ordinal }
            for op in operations {
                let channel = op.channel
                if lastTicks[channel] != op.tick {
                    if lastTicks[channel] >= 0 { publish(channel: channel, context: context, song: song) } else { touched.append(channel) }
                    lastTicks[channel] = op.tick
                }
                switch op.action {
                case let .writer(ref, writesBase, folded, native):
                    states[channel].incoming = states[channel].output
                    if folded != nil { states[channel].incoming = ref.kind == .writer
                        ? Ref(.writerInput, ref.index, ref.child) : Ref(ref.kind, ref.index, 1) }
                    states[channel].output = ref
                    if writesBase { states[channel].base = ref; baseValues[channel] = native }
                    if let folded { folds[channel] = folded }
                case .selection(let index):
                    let fact = context.selectionFacts[index]
                    states[channel].selection = index
                    states[channel].generation = fact.associatedGeneration ?? -1
                    if fact.role == .trigger || fact.role == .emptySelection || fact.role == .retainedNoteRestart {
                        if folds[channel] != (fact.associatedGeneration ?? -2) {
                            states[channel].incoming = states[channel].output
                            states[channel].base = Ref(.selection, index); states[channel].output = Ref(.selection, index)
                            if case let .known(_, native) = fact.pitch { baseValues[channel] = native } else { baseValues[channel] = nil }
                        }
                    }
                case .emptyRoute(let index):
                    // Existing note-only unavailable-route evidence owns this dispatch;
                    // preserve canonical/held pitch and all preexisting selection ordinals.
                    states[channel].selection = -2 - 2 * index; states[channel].generation = -1
                case .rowOwner(let index): states[channel].selection = -3 - 2 * index
                case .generation(let generation): states[channel].generation = generation
                case .boundary(let ref): states[channel].incoming = states[channel].output; states[channel].output = ref
                case .automaticReset(let cause): automatic.resets[channel] = cause
                case .automaticRelease: automatic.releases[channel] = true
                }
            }
            // Compare independently captured producer values with actual incoming-next-row base.
            // An unobserved assignment fails the entire row explicitly instead of fabricating pitch.
            for channel in 0..<context.channelStates.count {
                let state = context.channelStates[channel]
                let actual = linear ? state.activeLinearPeriod : state.activeAmigaPeriod
                let owner = Self.owner(states[channel].selection, context: context)
                if actual != baseValues[channel] || owner != (state.semanticInstrumentIndex, state.semanticSampleIndex, state.carriedInstrumentIndex) ||
                    states[channel].generation != (state.activeEventIndex ?? -1) {
                    failures += 1
                    // A pitch capture gap cannot supply trustworthy automatic ownership,
                    // nor rewind a clock anchor already published earlier in this row.
                    automatic.valid = false
                    channels[channel].removeSubrange(rowStarts[channel]..<channels[channel].count)
                    states[channel].base = Ref(.missing); states[channel].output = Ref(.missing)
                    if lastTicks[channel] < 0 { touched.append(channel) }
                    lastTicks[channel] = 0
                }
            }
            for channel in touched { publish(channel: channel, context: context, song: song) }
            operationCapacityHighWater = max(operationCapacityHighWater, operations.capacity)
            boundaryCapacityHighWater = max(boundaryCapacityHighWater, pending.capacity + following.capacity)
            workspaceHighWater = max(workspaceHighWater, operations.capacity + pending.capacity + following.capacity)
        }

        static func owner(_ index: Int, context: borrowing PlaybackSongSyntheticAdapter.AdapterRowContext) -> (Int?, Int?, Int?) {
            PlaybackSongSemanticPitchProjection.owner(index, facts: context.selectionFacts, rows: context.xmChannelRows, routes: context.xmEmptyRoutes)
        }
        mutating func appendReset(ordinal: Int, channel: Int, index: Int, delayed: Bool) {
            var run = resetRuns[channel].last ?? .init(ordinal: ordinal, rowReset: -1, delayedReset: -1)
            precondition(ordinal >= run.ordinal, "Reset facts must retain actual traversal order")
            run.ordinal = ordinal
            if delayed { run.delayedReset = index } else { run.rowReset = index }
            let capacity = resetRuns[channel].capacity
            resetRuns[channel].append(run)
            if capacity != resetRuns[channel].capacity { growths += 1; resetGrowths += 1 }
        }
        mutating func publish(channel: Int, context: borrowing PlaybackSongSyntheticAdapter.AdapterRowContext, song: borrowing PlaybackSong) {
            var record = states[channel]; record.ordinal = firstOrdinal + lastTicks[channel]
            let owner = Self.owner(record.selection, context: context).0
            automatic.publish(channel: channel, ordinal: record.ordinal, instrument: owner, song: song)
            if let prior = channels[channel].last, prior.sameState(as: record) { return }
            let capacity = channels[channel].capacity
            channels[channel].append(record)
            if capacity != channels[channel].capacity { growths += 1 }
        }
        var evidence: PlaybackSongSemanticPitchProjection {
            .init(coverage: .nativeDepthOffV1, channels: channels, resetRuns: resetRuns, seeds: seeds,
                storageGrowthCount: growths, workspaceCapacity: workspaceHighWater, captureFailureCount: failures)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Returns one immutable native result at a canonical tick, without physical/source admission.
    func semanticPitch(row: Int, tick: Int, channel: Int) -> PlaybackSongSemanticPitchProjection.Result? {
        let projection = semanticPitchProjection
        guard projection.coverage == .nativeDepthOffV1,
              let coordinate = canonicalTickClock.coordinate(syntheticRow: row, tick: tick, channel: channel),
              projection.channels.indices.contains(channel), projection.resetRuns.indices.contains(channel) else { return nil }
        let records = projection.channels[channel]
        var low = 0, high = records.count
        while low < high {
            let middle = low + (high - low) / 2
            if records[middle].ordinal <= coordinate.canonicalTickOrdinal { low = middle + 1 } else { high = middle }
        }
        let record = low == 0 ? PlaybackSongSemanticPitchProjection.Record() : records[low - 1]
        // Reset-only changes have a sparse indexed history, without repeating two Ints per pitch writer.
        let resets = projection.resetRuns[channel]
        low = 0; high = resets.count
        while low < high {
            let middle = low + (high - low) / 2
            if resets[middle].ordinal <= coordinate.canonicalTickOrdinal { low = middle + 1 } else { high = middle }
        }
        let reset = low == 0 ? nil : resets[low - 1]
        let rowReset = reset?.rowReset ?? -1, delayedReset = reset?.delayedReset ?? -1
        let owner = PlaybackSongSemanticPitchProjection.owner(record.selection, facts: selectionDispatchFacts.facts, rows: xmChannelRows, routes: xmEmptyRoutes)
        let ownerOrdinal = record.selection < -1 ? (-2 - record.selection) / 2 : nil
        return .init(base: projection.pitch(record.base, plan: self), output: projection.pitch(record.output, plan: self),
            incoming: projection.pitch(record.incoming, plan: self), baseProducer: record.base.producer,
            producer: record.output.producer, incomingProducer: record.incoming.producer, semanticInstrument: owner.0, semanticSample: owner.1,
            carriedInstrument: owner.2, associatedGeneration: record.generation >= 0 ? record.generation : nil,
            selectionFactIndex: record.selection >= 0 ? record.selection : nil, emptyRouteIndex: record.selection < -1 && record.selection % 2 == 0 ? ownerOrdinal : nil,
            rowControlIndex: record.selection < -1 && record.selection % 2 != 0 ? ownerOrdinal : nil,
            rowEntryResetIndex: rowReset >= 0 ? rowReset : nil,
            delayedResetIndex: delayedReset >= 0 ? delayedReset : nil)
    }
}

extension PlaybackSongSyntheticAdapter {
    /// Moves workspace out temporarily so row inspection cannot copy its mutable COW buffers.
    static func finishSemanticPitchRow(context: inout AdapterRowContext, song: borrowing PlaybackSong) {
        var builder = PlaybackSongSemanticPitchProjection.Builder()
        swap(&builder, &context.semanticPitchBuilder)
        builder.finish(context: context, song: song)
        swap(&builder, &context.semanticPitchBuilder)
    }
}
