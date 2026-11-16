import Foundation

/// Bounded lookup/state input for the existing explicit-loop row interpreter.
/// A checkpoint owns scalar channel/provenance values and selected immutable source
/// lookup payloads; it never owns a parent plan, context, row capture, or history.
struct PlaybackSongLoopContinuation {
    typealias Adapter = PlaybackSongSyntheticAdapter
    typealias Facts = PlaybackSongSelectionDispatchFacts
    typealias Held = PlaybackSongHeldPitchProvenance
    typealias PitchCheckpoint = PlaybackSongOfflineRenderer.PitchSourceHistory.Checkpoint

    struct Scope: Equatable, Hashable {
        let sourceGeneration: UInt64
        let transportEpoch: UInt64
        let sequence: UInt64
    }

    struct FactIdentity: Equatable {
        let scope: Scope
        let originalFactIndex: Int
    }

    struct HeldProducerIdentity: Equatable {
        let scope: Scope
        let producer: Held.Producer
    }

    /// These are original scalar identities, never links to a predecessor checkpoint.
    struct SelectionOrigins: Equatable {
        var baseRate: FactIdentity?
        var relativeNote: FactIdentity?
        var finetune: FactIdentity?
        var semanticOwner: FactIdentity?
        var heldSelection: FactIdentity?
        var heldProducer: HeldProducerIdentity?
    }

    /// The semantic fold may own a different tuple from the terminal row dispatcher.
    /// Export accepts old scratch source indices; the checkpoint stores compact ones.
    struct OwnerObservation: Equatable {
        var instrument: Int?
        var sample: Int?
        var carriedInstrument: Int?
        var sourceEventIndex: Int?

        var hasOwner: Bool {
            instrument != nil || sample != nil || carriedInstrument != nil || sourceEventIndex != nil
        }
    }

    struct SourceLookup: Equatable {
        let birth: RuntimeLoopNativeSourceIdentity
        let birthAbsoluteFrame: Int
        let event: SyntheticTrackerEvent
        let mapping: PlaybackSongSyntheticEventMapping
        let pitch: PitchCheckpoint
        let sampleCacheKey: Adapter.MixerSampleBufferCacheKey?
        let noteOnly: Bool
        let coldReleased: Bool
    }

    /// A distinct held selection is still one scalar observation, never an old fact graph.
    struct HeldSelectionInput: Equatable {
        let owner: OwnerObservation
        let carriedNote: UInt8
        let pitch: Facts.Pitch
        let baseRate: Double?, relativeNote: Int?, finetune: Int?
        let cachedDefaultVolume: Int, cachedDefaultPan: UInt8
        let routedInstrument: Int?, mappedSample: Int?
        let selectionMethod: PlaybackSongSyntheticSampleSelectionMethod?

        func fact(source: PlaybackPosition, frame: Int, channel: Int, linear: Bool) -> Facts.Fact {
            var state = Adapter.ChannelState()
            state.semanticInstrumentIndex = owner.instrument; state.semanticSampleIndex = owner.sample
            state.carriedInstrumentIndex = owner.carriedInstrument; state.activeEventIndex = owner.sourceEventIndex
            state.carriedNote = carriedNote
            state.activeSampleBaseSampleRate = baseRate; state.activeSampleRelativeNote = relativeNote
            state.activeSampleFinetune = finetune
            state.triggeredSampleDefaultVolume = cachedDefaultVolume; state.triggeredSampleDefaultPan = cachedDefaultPan
            if case let .known(domain, value) = pitch {
                if domain == .linear { state.activeLinearPeriod = value } else { state.activeAmigaPeriod = value }
            }
            return Facts.continuationInput(source: source, channelIndex: channel, frame: frame,
                linear: linear, state: state, routedInstrument: routedInstrument,
                mappedSample: mappedSample, selectionMethod: selectionMethod)
        }
    }

    struct Checkpoint: Equatable {
        let scope: Scope
        let channels: [Adapter.ChannelState]
        let globalVolume: Adapter.GlobalVolumeState
        let sources: [SourceLookup]
        let ownerInputs: [OwnerObservation]
        let selectionOrigins: [SelectionOrigins]
        let heldInputs: [Held.Held]
        let distinctHeldInputs: [HeldSelectionInput?]

        var channelCount: Int { channels.count }
        var sourceCount: Int { sources.count }
        var selectionInputCount: Int { channels.count + distinctHeldInputs.compactMap { $0 }.count }
        var selectionOriginCount: Int {
            selectionOrigins.reduce(0) { count, roots in
                count + [roots.baseRate, roots.relativeNote, roots.finetune,
                    roots.semanticOwner, roots.heldSelection].compactMap { $0 }.count
            }
        }

        /// Restores fresh bounded scratch. All imported source entries are lookup-only.
        /// The caller separately restores semantic/automatic and envelope/audible folds.
        func restore(into context: inout Adapter.AdapterRowContext, source: PlaybackPosition,
                     batchStartFrame: Int, linear: Bool) throws -> Import {
            guard context.events.isEmpty, context.eventMappings.isEmpty,
                  context.channelStates.isEmpty, context.selectionFacts.isEmpty,
                  context.xmChannelRows.isEmpty else { throw Failure.nonemptyScratch }
            guard ownerInputs.count == channels.count, selectionOrigins.count == channels.count,
                  heldInputs.count == channels.count, distinctHeldInputs.count == channels.count else { throw Failure.invalidCheckpoint }
            context.importedSourceCount = sources.count
            context.channelStates = channels
            context.globalVolumeState = globalVolume
            context.heldPitchObserver.channels = heldInputs
            var result = Import()
            for (index, lookup) in sources.enumerated() {
                context.events.append(lookup.event)
                context.eventMappings.append(lookup.mapping)
                if lookup.noteOnly { context.noteOnlyEventIndices.insert(index) }
                if lookup.coldReleased { context.coldReleasedEventIndices.insert(index) }
                if let key = lookup.sampleCacheKey { context.mixerSampleBuffers[key] = lookup.event.sample }
                result.sourceIdentities[index] = lookup.birth
                result.pitchSeed[index] = lookup.pitch
            }
            for channel in channels.indices {
                var input = channels[channel]
                let owner = ownerInputs[channel]
                input.semanticInstrumentIndex = owner.instrument
                input.semanticSampleIndex = owner.sample
                input.carriedInstrumentIndex = owner.carriedInstrument
                input.activeEventIndex = owner.sourceEventIndex
                let index = context.selectionFacts.count
                context.selectionFacts.append(Facts.continuationInput(source: source, channelIndex: channel,
                    frame: batchStartFrame, linear: linear, state: input))
                context.selectionTuningProducers.append(.init(
                    baseRate: input.activeSampleBaseSampleRate == nil ? -1 : index,
                    relativeNote: input.activeSampleRelativeNote == nil ? -1 : index,
                    finetune: input.activeSampleFinetune == nil ? -1 : index))
                result.selectionOrigins[index] = selectionOrigins[channel]
                result.ownerFactIndices.append(owner.hasOwner ? index : nil)
            }
            for channel in channels.indices {
                guard let input = distinctHeldInputs[channel] else { continue }
                let index = context.selectionFacts.count
                context.selectionFacts.append(input.fact(source: source, frame: batchStartFrame,
                    channel: channel, linear: linear))
                var metadata = SelectionOrigins()
                metadata.heldSelection = selectionOrigins[channel].heldSelection
                metadata.heldProducer = selectionOrigins[channel].heldProducer
                result.selectionOrigins[index] = metadata
            }
            return result
        }
    }

    struct Import {
        var sourceIdentities = [Int: RuntimeLoopNativeSourceIdentity]()
        var pitchSeed = [Int: PitchCheckpoint]()
        var selectionOrigins = [Int: SelectionOrigins]()
        var ownerFactIndices = [Int?]()
    }

    struct Export {
        let checkpoint: Checkpoint
        /// Old scratch indices to the successor checkpoint's compact lookup indices.
        let sourceMap: [Int: Int]
        let factMap: [Int: Int]
        let ownerFactIndices: [Int?]
    }

    enum Failure: Error, Equatable {
        case cancelled, nonemptyScratch, invalidCheckpoint
        case missingSource(Int), missingMapping(Int), missingPitch(Int), missingBirthIdentity(Int)
        case incompatibleBirthScope(Int), invalidBirthFrame(Int), invalidPitchBoundary(Int)
        case invalidChannelAssociation(Int), missingSelectionProducer(Int), invalidSelectionFact(Int)
        case missingImportedSelectionOrigin(Int), invalidOwnerChannel(Int)
    }

    /// Copies only active/explicitly requested sources. Extra indices must come from
    /// bounded pending-writer references, never an ever-growing played-source ledger.
    static func export(scope: Scope, song: borrowing PlaybackSong,
        context: borrowing Adapter.AdapterRowContext, plan: borrowing PlaybackSongSyntheticPlan,
        boundaryFrame: Int, sourceIdentities: [Int: RuntimeLoopNativeSourceIdentity] = [:],
        pitch: [Int: PitchCheckpoint], retainingSources: Set<Int> = [],
        importedSelectionOrigins: [Int: SelectionOrigins] = [:],
        ownerOverrides: [Int: OwnerObservation] = [:], semanticSelectionIndices: [Int?] = [],
        trustedCarriedBirths: Set<RuntimeLoopNativeSourceIdentity> = [],
        isCancelled: (() -> Bool)? = nil) throws -> Export {
        guard scope.sequence > 0, boundaryFrame >= 0 else { throw Failure.invalidCheckpoint }
        var owners = context.channelStates.map {
            OwnerObservation(instrument: $0.semanticInstrumentIndex, sample: $0.semanticSampleIndex,
                carriedInstrument: $0.carriedInstrumentIndex, sourceEventIndex: $0.activeEventIndex)
        }
        for (channel, owner) in ownerOverrides {
            guard owners.indices.contains(channel) else { throw Failure.invalidOwnerChannel(channel) }
            owners[channel] = owner
        }
        var wanted = retainingSources
        wanted.formUnion(context.channelStates.compactMap(\.activeEventIndex))
        wanted.formUnion(owners.compactMap(\.sourceEventIndex))
        for held in context.heldPitchObserver.channels {
            guard case let .known(known) = held else { continue }
            guard context.selectionFacts.indices.contains(known.selectionFactIndex) else {
                throw Failure.invalidSelectionFact(known.selectionFactIndex)
            }
            if let generation = context.selectionFacts[known.selectionFactIndex].associatedGeneration { wanted.insert(generation) }
        }
        let oldSources = wanted.sorted()
        let sourceMap = Dictionary(uniqueKeysWithValues: oldSources.enumerated().map { ($0.element, $0.offset) })
        var mappings = [Int: PlaybackSongSyntheticEventMapping]()
        for mapping in plan.diagnostics.eventMappings where wanted.contains(mapping.eventIndex) {
            mappings[mapping.eventIndex] = mapping
        }
        var sources = [SourceLookup]()
        sources.reserveCapacity(oldSources.count)
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        for (index, old) in oldSources.enumerated() {
            if index & 63 == 0, isCancelled?() == true { throw Failure.cancelled }
            guard plan.pattern.events.indices.contains(old) else { throw Failure.missingSource(old) }
            guard let mapping = mappings[old] else { throw Failure.missingMapping(old) }
            guard let integral = pitch[old] else { throw Failure.missingPitch(old) }
            let original = plan.pattern.events[old]
            let birthFrame = scheduler.frame(for: original)
            guard birthFrame < boundaryFrame else { throw Failure.invalidBirthFrame(old) }
            guard integral.lastWriterFrame < boundaryFrame,
                  integral.cutFrame.map({ $0 < boundaryFrame }) ?? true else { throw Failure.invalidPitchBoundary(old) }
            let birth: RuntimeLoopNativeSourceIdentity
            if let existing = sourceIdentities[old] { birth = existing }
            else if old < context.importedSourceCount { throw Failure.missingBirthIdentity(old) }
            else {
                birth = .init(sourceGeneration: scope.sourceGeneration, transportEpoch: scope.transportEpoch,
                    birthSequence: scope.sequence, birthEventIndex: old)
            }
            let trustedImport = old < context.importedSourceCount && sourceIdentities[old] == birth && trustedCarriedBirths.contains(birth)
            guard (birth.sourceGeneration == scope.sourceGeneration || trustedImport), birth.transportEpoch == scope.transportEpoch else {
                throw Failure.incompatibleBirthScope(old)
            }
            // This is an explicit scratch copy. Original birth identity and absolute
            // frame stay unchanged; neither sample cursor nor integral is reanchored.
            let event = SyntheticTrackerEvent(row: -1, tick: original.tick, scheduledStartFrame: birthFrame,
                sample: original.sample, gain: original.gain, pan: original.pan, playbackStep: original.playbackStep,
                loop: original.loop, initialSourceFrame: original.initialSourceFrame,
                volumeEnvelope: original.volumeEnvelope, panEnvelope: original.panEnvelope,
                keyOffFrame: original.keyOffFrame, fadeoutFrameDecrement: original.fadeoutFrameDecrement)
            let remapped = Adapter.eventMapping(mapping, applying: mapping.volumeEnvelopeSemantics,
                lookupEventIndex: index, lookupSyntheticRow: -1)
            let sample = song.instrumentsByIndex[mapping.instrumentIndex]?.samples.first { $0.sampleIndex == mapping.sampleIndex }
            let key = sample.map { sample in sample.pcm.withUnsafeBufferPointer {
                Adapter.MixerSampleBufferCacheKey(storageAddress: UInt(bitPattern: $0.baseAddress), frameCount: $0.count)
            } }
            sources.append(.init(birth: birth, birthAbsoluteFrame: birthFrame, event: event, mapping: remapped,
                pitch: integral, sampleCacheKey: key, noteOnly: plan.noteOnlyEventIndices.contains(old),
                coldReleased: plan.coldReleasedEventIndices.contains(old)))
        }
        var channels = context.channelStates
        for channel in channels.indices {
            if let old = channels[channel].activeEventIndex {
                guard let index = sourceMap[old] else { throw Failure.missingSource(old) }
                channels[channel].activeEventIndex = index
            }
            if let ordinal = channels[channel].activeEventMappingIndex {
                guard context.eventMappings.indices.contains(ordinal),
                      let index = sourceMap[context.eventMappings[ordinal].eventIndex],
                      channels[channel].activeEventIndex == index else { throw Failure.invalidChannelAssociation(channel) }
                channels[channel].activeEventMappingIndex = index
            }
            if let old = owners[channel].sourceEventIndex {
                guard let index = sourceMap[old] else { throw Failure.missingSource(old) }
                owners[channel].sourceEventIndex = index
            }
        }
        var factMap = [Int: Int](), origins = [SelectionOrigins](), held = [Held.Held]()
        var ownerFacts = [Int?](), distinctHeld = [HeldSelectionInput?]()
        var nextHeldFactIndex = channels.count
        for channel in channels.indices {
            if channel & 63 == 0, isCancelled?() == true { throw Failure.cancelled }
            let state = channels[channel]
            let producers = context.selectionTuningProducers.indices.contains(channel)
                ? context.selectionTuningProducers[channel] : Facts.TuningProducers()
            func fact(_ index: Int?, field: KeyPath<SelectionOrigins, FactIdentity?>) throws -> FactIdentity? {
                guard let index, index >= 0 else { return nil }
                guard context.selectionFacts.indices.contains(index), context.selectionFacts[index].channel == channel else {
                    throw Failure.invalidSelectionFact(index)
                }
                factMap[index] = channel
                if context.selectionFacts[index].role == .continuationInput {
                    guard let previous = importedSelectionOrigins[index] else { throw Failure.missingImportedSelectionOrigin(index) }
                    return previous[keyPath: field]
                }
                return .init(scope: scope, originalFactIndex: index)
            }
            func tuning(_ valuePresent: Bool, producer: Int, field: KeyPath<SelectionOrigins, FactIdentity?>) throws -> FactIdentity? {
                guard valuePresent else { return nil }
                guard producer >= 0 else { throw Failure.missingSelectionProducer(channel) }
                return try fact(producer, field: field)
            }
            var roots = SelectionOrigins()
            roots.baseRate = try tuning(state.activeSampleBaseSampleRate != nil, producer: producers.baseRate, field: \.baseRate)
            roots.relativeNote = try tuning(state.activeSampleRelativeNote != nil, producer: producers.relativeNote, field: \.relativeNote)
            roots.finetune = try tuning(state.activeSampleFinetune != nil, producer: producers.finetune, field: \.finetune)
            if semanticSelectionIndices.indices.contains(channel) {
                roots.semanticOwner = try fact(semanticSelectionIndices[channel], field: \.semanticOwner)
            }
            let value = context.heldPitchObserver.channels.indices.contains(channel)
                ? context.heldPitchObserver.channels[channel] : Held.Held.notEstablished
            switch value {
            case let .known(known):
                roots.heldSelection = try fact(known.selectionFactIndex, field: \.heldSelection)
                if known.producer == .continuationInput {
                    guard let previous = importedSelectionOrigins[known.selectionFactIndex] else {
                        throw Failure.missingImportedSelectionOrigin(known.selectionFactIndex)
                    }
                    roots.heldProducer = previous.heldProducer
                } else { roots.heldProducer = .init(scope: scope, producer: known.producer) }
                let original = context.selectionFacts[known.selectionFactIndex]
                let heldOwner = OwnerObservation(instrument: original.semanticInstrument,
                    sample: original.semanticSample, carriedInstrument: original.carriedInstrument,
                    sourceEventIndex: original.associatedGeneration.flatMap { sourceMap[$0] })
                let selectionIndex: Int
                if heldOwner == owners[channel] {
                    selectionIndex = channel
                    distinctHeld.append(nil)
                } else {
                    selectionIndex = nextHeldFactIndex; nextHeldFactIndex += 1
                    distinctHeld.append(.init(owner: heldOwner, carriedNote: original.carriedNote,
                        pitch: original.pitch, baseRate: original.baseRate, relativeNote: original.relativeNote,
                        finetune: original.finetune, cachedDefaultVolume: original.cachedDefaultVolume,
                        cachedDefaultPan: original.cachedDefaultPan, routedInstrument: original.routedInstrument,
                        mappedSample: original.mappedSample, selectionMethod: original.selectionMethod))
                }
                factMap[known.selectionFactIndex] = selectionIndex
                held.append(.known(.init(domain: known.domain, nativePeriod: known.nativePeriod,
                    producer: .continuationInput, selectionFactIndex: selectionIndex)))
            case .notEstablished: held.append(.notEstablished); distinctHeld.append(nil)
            case .notCaptured: held.append(.notCaptured); distinctHeld.append(nil)
            }
            origins.append(roots)
            ownerFacts.append(owners[channel].hasOwner ? channel : nil)
        }
        if isCancelled?() == true { throw Failure.cancelled }
        return .init(checkpoint: .init(scope: scope, channels: channels, globalVolume: context.globalVolumeState,
            sources: sources, ownerInputs: owners, selectionOrigins: origins, heldInputs: held, distinctHeldInputs: distinctHeld),
            sourceMap: sourceMap, factMap: factMap, ownerFactIndices: ownerFacts)
    }
}
