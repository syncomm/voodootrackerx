import Foundation

enum RuntimeCMixerAdapterEventSource: String, Equatable {
    case playbackEngineSimple = "playback_engine_simple"
    case offlineAdapterPlan = "offline_adapter_plan"
    case hybrid = "hybrid"
}

enum RuntimeCMixerAdapterEventAction: Equatable {
    // Box only the large trigger payload during planning, keeping every semantic tick compact.
    indirect case noteTrigger(eventIndex: Int, event: SyntheticTrackerEvent, mapping: PlaybackSongSyntheticEventMapping)
    case gainPanUpdate(activeEventIndex: Int, gain: Float?, pan: Float?)
    case stepUpdate(activeEventIndex: Int, playbackStep: Double)
    case envelopePositionUpdate(activeEventIndex: Int, positionFrame: Int)
    case playbackStateChange(activeEventIndex: Int, change: MixerPlaybackStateChange)
    case envelopeSemanticUpdate(activeEventIndex: Int, state: MixerEnvelopeSemanticState)
    case channelSemanticUpdate(PlaybackXMChannelUpdate)
    case sourceStop(activeEventIndex: Int)
    case audibleTargetUpdate(PlaybackXMAudibleUpdate)
    case noteCut(activeEventIndex: Int?)
}

struct RuntimeCMixerAdapterEvent: Equatable {
    let id: Int
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticTick: Int
    let scheduledFrame: Int
    let action: RuntimeCMixerAdapterEventAction
    let categories: [String]
    let effectType: UInt8?
    let effectParam: UInt8?
    let volumeColumn: UInt8?

    init(
        id: Int,
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticTick: Int,
        scheduledFrame: Int,
        action: RuntimeCMixerAdapterEventAction,
        categories: [String],
        effectType: UInt8? = nil,
        effectParam: UInt8? = nil,
        volumeColumn: UInt8? = nil
    ) {
        self.id = id
        self.source = source
        self.channelIndex = channelIndex
        self.syntheticTick = syntheticTick
        self.scheduledFrame = scheduledFrame
        self.action = action
        self.categories = categories
        self.effectType = effectType
        self.effectParam = effectParam
        self.volumeColumn = volumeColumn
    }

    var primaryCategory: String {
        categories.first ?? "unknown"
    }

    var activeEventIndex: Int? {
        switch action {
        case let .noteTrigger(eventIndex, _, _):
            return eventIndex
        case let .gainPanUpdate(activeEventIndex, _, _),
             let .stepUpdate(activeEventIndex, _),
             let .envelopePositionUpdate(activeEventIndex, _),
             let .playbackStateChange(activeEventIndex, _),
             let .envelopeSemanticUpdate(activeEventIndex, _):
            return activeEventIndex
        case let .noteCut(activeEventIndex):
            return activeEventIndex
        case let .sourceStop(activeEventIndex):
            return activeEventIndex
        case let .channelSemanticUpdate(update):
            return update.sourceEventIndex
        case let .audibleTargetUpdate(target):
            return target.eventIndex
        }
    }
}

/// Orders small keys and permutes owned event storage without another full-width array.
struct RuntimeCMixerAdapterPlanAssembly {
    struct OrderingRecord {
        var eventIndex: Int
        let frame: Int
        let tick: Int
        let priority: Int
        let order: Int
        let row: Int
        let id: Int
    }

    struct Metrics {
        let eventCount: Int
        let orderingRecordSortCount: Int
        let wideEventMoveCount: Int
        let categoryUnionCount: Int
        let reservedCapacity: Int
        let wideEventSortCount = 0
        let fullWidthPlanCopyCount = 0
        let categoryFlatMapCount = 0
    }

    struct Result {
        let events: [RuntimeCMixerAdapterEvent]
        let runtimeOrderingEntries: [RuntimeCMixerAdapterEventStorage.OrderEntry]
        let categories: [String]
        let metrics: Metrics
    }

    private var events = [RuntimeCMixerAdapterEvent]()
    private var ordering = [OrderingRecord]()
    private var categories = Set<String>()
    private var previousCategories: [String]?
    private var categoryUnionCount = 0
    private var categoryNanoseconds: UInt64 = 0
    private var reservedCapacity = 0
    private let measuresCategories: Bool

    var count: Int { events.count }

    init(initialCapacity: Int, measuresCategories: Bool = false) {
        self.measuresCategories = measuresCategories
        events.reserveCapacity(initialCapacity)
        ordering.reserveCapacity(initialCapacity)
    }

    mutating func append(_ event: RuntimeCMixerAdapterEvent) {
        ordering.append(.init(eventIndex: count, frame: event.scheduledFrame, tick: event.syntheticTick,
            priority: Self.priority(event), order: event.source.orderIndex, row: event.source.rowIndex, id: event.id))
        events.append(event)
        let start = measuresCategories ? DispatchTime.now().uptimeNanoseconds : nil
        // Long semantic publication runs share categories; union an unchanged run only once.
        if previousCategories != event.categories {
            categories.formUnion(event.categories)
            previousCategories = event.categories
            categoryUnionCount += 1
        }
        if let start { categoryNanoseconds += DispatchTime.now().uptimeNanoseconds - start }
    }

    /// Counts come from already-built bounded adapter arrays, never raw module headers.
    @discardableResult
    mutating func reserveAdditionalCapacity(_ counts: [Int]) -> Bool {
        var capacity = count
        for addition in counts {
            let sum = capacity.addingReportingOverflow(addition)
            guard addition >= 0, !sum.overflow else { return false }
            capacity = sum.partialValue
        }
        events.reserveCapacity(capacity)
        ordering.reserveCapacity(capacity)
        reservedCapacity = capacity
        return true
    }

    /// Consumes construction storage; downstream callers still receive canonical physical order.
    mutating func finish(profileSession: AdapterPlanProfileSession? = nil) -> Result {
        let eventCount = count
        let orderingStart = profileSession?.beginPhase()
        if ordering.count > 1 {
            ordering.sort { lhs, rhs in
                if lhs.frame != rhs.frame { return lhs.frame < rhs.frame }
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                if lhs.row != rhs.row { return lhs.row < rhs.row }
                if lhs.id != rhs.id { return lhs.id < rhs.id }
                return lhs.eventIndex < rhs.eventIndex // Exact original writer order for equal keys.
            }
        }
        profileSession?.recordPhase("cold_event_ordering", startedAt: orderingStart, fields: [
            .init("ordering_record_count", eventCount), .init("ordering_record_stride", MemoryLayout<OrderingRecord>.stride)
        ])
        let materializationStart = profileSession?.beginPhase()
        let moveCount = materializeOrderInPlace()
        let orderedEvents = events
        // Reuse scalar keys for the distinct runtime comparator without another wide-array walk.
        let runtimeEntries = ordering.enumerated().map { index, key in
            RuntimeCMixerAdapterEventStorage.OrderEntry(eventIndex: index, scheduledFrame: key.frame,
                priority: key.priority, eventID: key.id)
        }
        events = []
        ordering = []
        profileSession?.recordPhase("cold_event_materialization", startedAt: materializationStart,
            fields: [.init("wide_event_move_count", moveCount), .init("full_width_plan_copy_count", 0)])
        let categoryStart = measuresCategories ? DispatchTime.now().uptimeNanoseconds : nil
        let sortedCategories = categories.sorted()
        if let categoryStart { categoryNanoseconds += DispatchTime.now().uptimeNanoseconds - categoryStart }
        let metrics = Metrics(eventCount: eventCount, orderingRecordSortCount: eventCount > 1 ? 1 : 0,
            wideEventMoveCount: moveCount, categoryUnionCount: categoryUnionCount,
            reservedCapacity: reservedCapacity)
        profileSession?.recordMeasuredPhase("cold_category_aggregation", elapsedMS: Double(categoryNanoseconds) / 1_000_000,
            fields: [.init("category_event_visit_count", eventCount), .init("category_union_count", categoryUnionCount),
                     .init("category_flat_map_count", metrics.categoryFlatMapCount)])
        return Result(events: orderedEvents, runtimeOrderingEntries: runtimeEntries,
            categories: sortedCategories, metrics: metrics)
    }

    private mutating func materializeOrderInPlace() -> Int {
        ordering.withUnsafeMutableBufferPointer { keys in
            events.withUnsafeMutableBufferPointer { payloads in
                var moves = 0
                for start in keys.indices where keys[start].eventIndex >= 0 {
                    if keys[start].eventIndex == start {
                        keys[start].eventIndex = -1
                        continue
                    }
                    // A permutation cycle needs only one saved wide value. Negative indices
                    // mark visited keys; the runtime index consumes their untouched scalar fields.
                    let saved = payloads[start]
                    var destination = start
                    while true {
                        let source = keys[destination].eventIndex
                        keys[destination].eventIndex = -1
                        moves += 1
                        if source == start {
                            payloads[destination] = saved
                            break
                        }
                        payloads[destination] = payloads[source]
                        destination = source
                    }
                }
                return moves
            }
        }
    }

    private static func priority(_ event: RuntimeCMixerAdapterEvent) -> Int {
        switch event.action {
        case .gainPanUpdate, .stepUpdate: return 0
        case .noteCut, .sourceStop: return 1
        case .noteTrigger: return 2
        case .playbackStateChange: return 3
        case .envelopePositionUpdate: return 4
        case .envelopeSemanticUpdate, .channelSemanticUpdate: return 5
        case .audibleTargetUpdate: return 6
        }
    }
}

/// Immutable semantic event storage paired with a small, once-built runtime ordering index.
struct RuntimeCMixerAdapterEventStorage: Equatable {
    struct OrderEntry: Equatable {
        let eventIndex: Int
        let scheduledFrame: Int
        let priority: Int
        let eventID: Int
    }

    let events: [RuntimeCMixerAdapterEvent]
    let ordering: [OrderEntry]

    init(events: [RuntimeCMixerAdapterEvent], orderingEntries: [OrderEntry]? = nil,
         profileSession: AdapterPlanProfileSession? = nil) {
        let start = profileSession?.beginPhase()
        self.events = events
        var ordering = orderingEntries ?? events.enumerated().map { index, event in
            OrderEntry(eventIndex: index, scheduledFrame: event.scheduledFrame,
                       priority: Self.priority(event), eventID: event.id)
        }
        // Runtime frame/priority/id differs from the cold plan's tick/source comparator.
        // Sorting only keys also preserves original writer order for identical keys.
        ordering.sort {
            if $0.scheduledFrame != $1.scheduledFrame { return $0.scheduledFrame < $1.scheduledFrame }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.eventID < $1.eventID
        }
        self.ordering = ordering
        profileSession?.recordPhase("runtime_adapter_queue_order_index", startedAt: start, fields: [
            AdapterPlanProfileField("entry_count", ordering.count),
            AdapterPlanProfileField("entry_stride", MemoryLayout<OrderEntry>.stride),
            AdapterPlanProfileField("index_sort_count", 1),
            AdapterPlanProfileField("ordering_entries_precomputed", orderingEntries != nil)
        ])
    }

    private static func priority(_ event: RuntimeCMixerAdapterEvent) -> Int {
        switch event.action {
        case .gainPanUpdate, .stepUpdate: return 0
        case .noteCut, .sourceStop: return 1
        case .noteTrigger: return 2
        case .playbackStateChange: return 3
        case .envelopePositionUpdate: return 4
        case .envelopeSemanticUpdate, .channelSemanticUpdate: return 5
        case .audibleTargetUpdate: return 6
        }
    }
}

struct RuntimeCMixerAdapterEventLoopRange: Equatable {
    let playbackRange: PlaybackPatternLoopRange
    let plannedStartFrame: Int
    let plannedEndFrame: Int
    let eventStorage: RuntimeCMixerAdapterEventStorage

    var events: [RuntimeCMixerAdapterEvent] { eventStorage.events }

    init(playbackRange: PlaybackPatternLoopRange, plannedStartFrame: Int, plannedEndFrame: Int,
         events: [RuntimeCMixerAdapterEvent]) {
        self.playbackRange = playbackRange
        self.plannedStartFrame = plannedStartFrame
        self.plannedEndFrame = plannedEndFrame
        eventStorage = .init(events: events)
    }

    var frameCount: Int {
        max(0, plannedEndFrame - plannedStartFrame)
    }
}

struct RuntimeCMixerAdapterEventPlan: Equatable {
    let generated: Bool
    let sampleRate: Double
    let plannedSongEndFrame: Int?
    let plannedEventCount: Int
    let eventStorage: RuntimeCMixerAdapterEventStorage
    let categories: [String]
    let plan: PlaybackSongSyntheticPlan?

    var events: [RuntimeCMixerAdapterEvent] { eventStorage.events }

    init(generated: Bool, sampleRate: Double, plannedSongEndFrame: Int?, plannedEventCount: Int,
         events: [RuntimeCMixerAdapterEvent], categories: [String], plan: PlaybackSongSyntheticPlan?,
         runtimeOrderingEntries: [RuntimeCMixerAdapterEventStorage.OrderEntry]? = nil,
         profileSession: AdapterPlanProfileSession? = nil) {
        self.generated = generated
        self.sampleRate = sampleRate
        self.plannedSongEndFrame = plannedSongEndFrame
        self.plannedEventCount = plannedEventCount
        self.categories = categories
        self.plan = plan
        eventStorage = .init(events: events, orderingEntries: runtimeOrderingEntries, profileSession: profileSession)
    }

    var plannedSongEndSeconds: Double? {
        guard generated,
              let plannedSongEndFrame,
              plannedSongEndFrame >= 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }
        return Double(plannedSongEndFrame) / sampleRate
    }

    static func unavailable(sampleRate: Double = MixerRenderConfig.defaultSampleRate) -> RuntimeCMixerAdapterEventPlan {
        RuntimeCMixerAdapterEventPlan(
            generated: false,
            sampleRate: sampleRate,
            plannedSongEndFrame: nil,
            plannedEventCount: 0,
            events: [],
            categories: [],
            plan: nil
        )
    }

    static func make(
        song: PlaybackSong?,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil,
        preparedPlan: PlaybackSongSyntheticPlan? = nil
    ) -> RuntimeCMixerAdapterEventPlan {
        let makeStart = profileSession?.beginPhase()
        guard let song else {
            let unavailablePlan = unavailable(sampleRate: sampleRate)
            profileSession?.recordPhase(
                "runtime_c_mixer_adapter_event_plan_make_total",
                startedAt: makeStart,
                fields: AdapterPlanProfileFields.adapterPlan(unavailablePlan)
            )
            return unavailablePlan
        }
        let adaptedPlan = preparedPlan ?? PlaybackSongSyntheticAdapter.adapt(
            song,
            startOrderIndex: 0,
            orderCount: song.orders.count,
            sampleRate: sampleRate,
            profileSession: profileSession
        )
        let diagnosticIndexingStart = profileSession?.beginPhase()
        let scheduler = SyntheticTrackerScheduler(config: adaptedPlan.timingConfig)
        let eventMappingsByIndex = Dictionary(
            uniqueKeysWithValues: adaptedPlan.diagnostics.eventMappings.map { ($0.eventIndex, $0) }
        )
        let keyOffDiagnosticsByEventIndex = Dictionary(
            grouping: adaptedPlan.diagnostics.keyOffEvents.filter { $0.applied },
            by: { $0.activeEventIndex ?? -1 }
        )
        let appliedVibratoVolumeSlideEventIndices = Set(
            adaptedPlan.diagnostics.vibratoEffects
                .filter { $0.effectType == 0x06 && $0.applied }
                .compactMap(\.activeEventIndex)
        )
        let slideMemoryTriggerCoordinates = Set(adaptedPlan.diagnostics.voiceStateUpdates.filter {
            $0.effectType == 6 && $0.effectMemoryReused && $0.applied && (1...96).contains($0.cellNote)
        }.map { [$0.syntheticRow, $0.channelIndex] })
        let appliedAxyVolumeSlideEventIndices = Set(
            adaptedPlan.diagnostics.voiceStateUpdates
                .filter { update in
                    guard update.applied,
                          case .axyVolumeSlide = update.command else {
                        return false
                    }
                    return true
                }
                .compactMap(\.activeEventIndex)
        )
        let axyVolumeSlideMemoryReusedEventIndices = Set(
            adaptedPlan.diagnostics.voiceStateUpdates
                .filter { update in
                    guard update.applied,
                          update.effectMemoryReused,
                          case .axyVolumeSlide = update.command else {
                        return false
                    }
                    return true
                }
                .compactMap(\.activeEventIndex)
        )
        let appliedArpeggioEventIndices = Set(
            adaptedPlan.diagnostics.arpeggioEffects
                .filter(\.applied)
                .compactMap(\.activeEventIndex)
        )
        let appliedExtraFinePortamentoByEventIndex = adaptedPlan.diagnostics.extraFinePortamentoEffects
            .filter(\.applied)
            .reduce(into: [Int: PlaybackSongSyntheticExtraFinePortamentoDiagnostic]()) { result, diagnostic in
                guard diagnostic.appliedToInitialPlaybackStep,
                      let activeEventIndex = diagnostic.activeEventIndex,
                      result[activeEventIndex] == nil else {
                    return
                }
                result[activeEventIndex] = diagnostic
            }
        func portamentoSlideTriggerKey(
            eventIndex: Int,
            source: PlaybackPosition,
            channelIndex: Int
        ) -> String {
            "\(eventIndex):\(source.orderIndex):\(source.patternIndex):\(source.rowIndex):\(channelIndex)"
        }
        let appliedPortamentoSlidesByTriggerKey = adaptedPlan.diagnostics.portamentoSlideEffects
            .filter(\.applied)
            .reduce(into: [String: PlaybackSongSyntheticPortamentoSlideDiagnostic]()) { result, diagnostic in
                guard let activeEventIndex = diagnostic.activeEventIndex else {
                    return
                }
                let key = portamentoSlideTriggerKey(
                    eventIndex: activeEventIndex,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex
                )
                if result[key] == nil {
                    result[key] = diagnostic
                }
            }
        var events = RuntimeCMixerAdapterPlanAssembly(initialCapacity: adaptedPlan.pattern.events.count,
            measuresCategories: profileSession != nil)
        var nextID = 0
        var seenNoteTriggerChannels = Set<Int>()
        profileSession?.recordPhase(
            "adapter_diagnostic_indexing",
            startedAt: diagnosticIndexingStart,
            fields: [
                AdapterPlanProfileField("event_mapping_count", eventMappingsByIndex.count),
                AdapterPlanProfileField("key_off_diagnostic_group_count", keyOffDiagnosticsByEventIndex.count),
                AdapterPlanProfileField("applied_vibrato_volume_slide_event_count", appliedVibratoVolumeSlideEventIndices.count),
                AdapterPlanProfileField("applied_axy_volume_slide_event_count", appliedAxyVolumeSlideEventIndices.count),
                AdapterPlanProfileField("applied_arpeggio_event_count", appliedArpeggioEventIndices.count),
                AdapterPlanProfileField("extra_fine_portamento_event_count", appliedExtraFinePortamentoByEventIndex.count),
                AdapterPlanProfileField("portamento_slide_trigger_count", appliedPortamentoSlidesByTriggerKey.count),
            ]
        )

        let eventGenerationStart = profileSession?.beginPhase()
        for (eventIndex, syntheticEvent) in adaptedPlan.pattern.events.enumerated() {
            guard let mapping = eventMappingsByIndex[eventIndex] else {
                continue
            }
            var categories = ["note_trigger"]
            if seenNoteTriggerChannels.contains(mapping.channelIndex) {
                categories.append("replacement")
            }
            seenNoteTriggerChannels.insert(mapping.channelIndex)
            let bridgedPortamentoSlide = appliedPortamentoSlidesByTriggerKey[portamentoSlideTriggerKey(
                eventIndex: eventIndex,
                source: mapping.source,
                channelIndex: mapping.channelIndex
            )]
            if mapping.sampleOffset.applied {
                categories.append("sample_offset")
                if mapping.sampleOffset.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    if mapping.sampleOffset.effectType == 0x09,
                       mapping.sampleOffset.effectParam == 0 {
                        categories.append("900_sample_offset_memory_applied")
                    }
                }
            }
            if mapping.syntheticTick > 0 {
                categories.append("note_delay")
            }
            let isE9xRetrigger = mapping.effectType == 0x0E &&
                ((mapping.effectParam >> 4) & 0x0F) == 0x09
            let isRxyMultiRetrigger = mapping.effectType == 0x1B
            if isE9xRetrigger {
                categories.append("retrigger")
            }
            if isRxyMultiRetrigger {
                categories.append("retrigger")
                categories.append("rxy_multi_retrigger")
            }
            let isSetFinetune = mapping.effectType == 0x0E &&
                ((mapping.effectParam >> 4) & 0x0F) == 0x05
            if isSetFinetune {
                categories.append("e5x_set_finetune")
            }
            let isFinePortamentoUp = mapping.effectType == 0x0E &&
                ((mapping.effectParam >> 4) & 0x0F) == 0x01
            if isFinePortamentoUp {
                categories.append("e1x_fine_portamento_up")
            }
            let isFinePortamentoDown = mapping.effectType == 0x0E &&
                ((mapping.effectParam >> 4) & 0x0F) == 0x02
            if isFinePortamentoDown {
                categories.append("e2x_fine_portamento_down")
            }
            let bridgedExtraFinePortamento: PlaybackSongSyntheticExtraFinePortamentoDiagnostic? =
                mapping.effectType == 0x21 ? appliedExtraFinePortamentoByEventIndex[eventIndex] : nil
            if let bridgedExtraFinePortamento {
                categories.append("xxy_extra_fine_portamento")
                if bridgedExtraFinePortamento.direction == .up {
                    categories.append("x1x_extra_fine_portamento_up")
                } else if bridgedExtraFinePortamento.direction == .down {
                    categories.append("x2x_extra_fine_portamento_down")
                }
            }
            let fineVolumeSlideAmount = mapping.effectParam & 0x0F
            let isFineVolumeSlideUp = mapping.effectType == 0x0E &&
                ((mapping.effectParam >> 4) & 0x0F) == 0x0A &&
                fineVolumeSlideAmount > 0
            let isFineVolumeSlideDown = mapping.effectType == 0x0E &&
                ((mapping.effectParam >> 4) & 0x0F) == 0x0B &&
                fineVolumeSlideAmount > 0
            if isFineVolumeSlideUp {
                categories.append("eax_fine_volume_slide_up")
            }
            if isFineVolumeSlideDown {
                categories.append("ebx_fine_volume_slide_down")
            }
            let isVibratoVolumeSlide = mapping.effectType == 0x06 &&
                appliedVibratoVolumeSlideEventIndices.contains(eventIndex)
            if isVibratoVolumeSlide {
                categories.append("vibrato_volume_slide_6xy")
            }
            if mapping.effectType == 6 && slideMemoryTriggerCoordinates.contains([
                mapping.syntheticRow, mapping.channelIndex
            ]) {
                categories.append("effect_memory_reused")
                categories.append("vibrato_volume_slide_600_memory_reused")
            }
            let isAxyVolumeSlide = mapping.effectType == 0x0A &&
                appliedAxyVolumeSlideEventIndices.contains(eventIndex)
            if isAxyVolumeSlide {
                categories.append("axy_volume_slide")
                if axyVolumeSlideMemoryReusedEventIndices.contains(eventIndex) {
                    categories.append("effect_memory_reused")
                    categories.append("axy_volume_slide_memory_reused")
                }
            }
            let isArpeggio = mapping.effectType == 0x00 &&
                mapping.effectParam != 0 &&
                appliedArpeggioEventIndices.contains(eventIndex)
            if isArpeggio {
                categories.append("arpeggio_0xy")
            }
            if mapping.frequencyTableStatus == .amigaApplied {
                categories.append("amiga_frequency_table")
                categories.append("amiga_period_sample_step")
            }
            if let bridgedPortamentoSlide {
                categories.append("portamento_update")
                categories.append(bridgedPortamentoSlide.direction == .up ? "portamento_1xx" : "portamento_2xx")
                if bridgedPortamentoSlide.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    categories.append(
                        bridgedPortamentoSlide.direction == .up
                            ? "portamento_1xx_memory_reused"
                            : "portamento_2xx_memory_reused"
                    )
                }
            }
            let keyOffDiagnostic = keyOffDiagnosticsByEventIndex[eventIndex]?.first
            if syntheticEvent.keyOffFrame != nil {
                categories.append("key_off")
                if keyOffDiagnostic?.effectType == 0x14 {
                    categories.append("kxx_key_off")
                }
            }
            let hasBridgedEffectMetadata = isSetFinetune ||
                mapping.effectType == 0x07 ||
                (mapping.effectType == 0x0E && mapping.effectParam >> 4 == 0x07) ||
                isFinePortamentoUp ||
                isFinePortamentoDown ||
                bridgedExtraFinePortamento != nil ||
                isFineVolumeSlideUp ||
                isFineVolumeSlideDown ||
                isVibratoVolumeSlide ||
                isAxyVolumeSlide ||
                isArpeggio ||
                isE9xRetrigger ||
                isRxyMultiRetrigger ||
                bridgedPortamentoSlide != nil ||
                mapping.sampleOffset.applied ||
                keyOffDiagnostic?.effectType == 0x14
            let bridgedEffectType = keyOffDiagnostic?.effectType == 0x14 ? keyOffDiagnostic?.effectType : mapping.effectType
            let bridgedEffectParam = keyOffDiagnostic?.effectType == 0x14 ? keyOffDiagnostic?.effectParam : mapping.effectParam
            events.append(RuntimeCMixerAdapterEvent(
                id: nextID,
                source: mapping.source,
                channelIndex: mapping.channelIndex,
                syntheticTick: mapping.syntheticTick,
                scheduledFrame: scheduler.frame(for: syntheticEvent),
                action: .noteTrigger(eventIndex: eventIndex, event: syntheticEvent, mapping: mapping),
                categories: categories,
                effectType: hasBridgedEffectMetadata ? bridgedEffectType : nil,
                effectParam: hasBridgedEffectMetadata ? bridgedEffectParam : nil
            ))
            nextID += 1
        }

        for update in adaptedPlan.diagnostics.voiceStateUpdates where update.applied && update.activeVoiceUpdated {
            guard let activeEventIndex = update.activeEventIndex else {
                continue
            }
            let gain = changedGain(from: update)
            let pan = changedPan(from: update)
            guard gain != nil || pan != nil else {
                continue
            }
            var categories = ["gain_pan_update"]
            switch update.command {
            case .tremolo:
                categories.append("tremolo_7xy")
                if update.effectMemoryReused { categories.append("effect_memory_reused") }
            case .gxxSetGlobalVolume:
                categories.append("gxx_global_volume_update")
                categories.append("global_volume_update")
            case .hxyGlobalVolumeSlide:
                categories.append("hxy_global_volume_update")
                categories.append("global_volume_update")
            case .axyVolumeSlide:
                categories.append("axy_volume_slide")
                if update.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    categories.append("axy_volume_slide_memory_reused")
                }
            case .volumeColumn:
                categories.append("volume_column_update")
            case .instrumentDefaultVolume:
                categories.append("instrument_default_volume_update")
            case .eaxFineVolumeSlideUp:
                categories.append("eax_fine_volume_slide_up")
            case .ebxFineVolumeSlideDown:
                categories.append("ebx_fine_volume_slide_down")
            case .effect5xyVolumeSlide:
                categories.append("tone_portamento_volume_slide_5xy")
                if update.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    categories.append("tone_portamento_volume_slide_5xy_memory_reused")
                    if update.effectParam == 0 {
                        categories.append("tone_portamento_volume_slide_5xy_500_memory_reused")
                    }
                }
            case .effect6xyVolumeSlide:
                categories.append("vibrato_volume_slide_6xy")
                if update.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    categories.append("vibrato_volume_slide_600_memory_reused")
                }
            default:
                break
            }
            events.append(RuntimeCMixerAdapterEvent(
                id: nextID,
                source: update.source,
                channelIndex: update.targetChannelIndex ?? update.channelIndex,
                syntheticTick: update.syntheticTick,
                scheduledFrame: update.scheduledFrame,
                action: .gainPanUpdate(activeEventIndex: activeEventIndex, gain: gain, pan: pan),
                categories: categories,
                effectType: update.effectType,
                effectParam: update.effectParam
            ))
            nextID += 1
        }

        for diagnostic in adaptedPlan.diagnostics.tonePortamentoEffects where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                var categories = ["step_update", "portamento_update"]
                if diagnostic.effectType == 0x05 {
                    categories.append("tone_portamento_volume_slide_5xy")
                }
                if diagnostic.commandSource == .volumeColumn {
                    categories.append("volume_column_tone_portamento")
                    categories.append("volume_column_update")
                }
                if diagnostic.frequencyTableStatus == .amigaApplied {
                    categories.append("amiga_frequency_table")
                    categories.append("amiga_period_sample_step")
                }
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: categories,
                    effectType: diagnostic.commandSource == .effectColumn && diagnostic.effectType == 0x05 ? diagnostic.effectType : nil,
                    effectParam: diagnostic.commandSource == .effectColumn && diagnostic.effectType == 0x05 ? diagnostic.effectParam : nil,
                    volumeColumn: diagnostic.commandSource == .volumeColumn ? diagnostic.rawVolumeColumn : nil
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.portamentoSlideEffects where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                var categories = [
                    "step_update",
                    "portamento_update",
                    diagnostic.direction == .up ? "portamento_1xx" : "portamento_2xx",
                ]
                if diagnostic.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    categories.append(
                        diagnostic.direction == .up
                            ? "portamento_1xx_memory_reused"
                            : "portamento_2xx_memory_reused"
                    )
                }
                if diagnostic.frequencyTableStatus == .amigaApplied {
                    categories.append("amiga_frequency_table")
                    categories.append("amiga_period_sample_step")
                }
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: categories,
                    effectType: diagnostic.effectType,
                    effectParam: diagnostic.effectParam
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.finePortamentoUpEffects where diagnostic.applied && !diagnostic.appliedToInitialPlaybackStep {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: ["step_update", "e1x_fine_portamento_up"],
                    effectType: diagnostic.effectType,
                    effectParam: diagnostic.effectParam
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.finePortamentoDownEffects where diagnostic.applied && !diagnostic.appliedToInitialPlaybackStep {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: ["step_update", "e2x_fine_portamento_down"],
                    effectType: diagnostic.effectType,
                    effectParam: diagnostic.effectParam
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.extraFinePortamentoEffects where diagnostic.applied && !diagnostic.appliedToInitialPlaybackStep {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                var categories = ["step_update", "xxy_extra_fine_portamento"]
                if diagnostic.direction == .up {
                    categories.append("x1x_extra_fine_portamento_up")
                } else if diagnostic.direction == .down {
                    categories.append("x2x_extra_fine_portamento_down")
                }
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: categories,
                    effectType: diagnostic.effectType,
                    effectParam: diagnostic.effectParam
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.arpeggioEffects where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: ["step_update", "arpeggio_0xy"],
                    effectType: diagnostic.effectType,
                    effectParam: diagnostic.effectParam
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.vibratoEffects where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex else {
                continue
            }
            for update in diagnostic.stepUpdates {
                var categories = ["step_update", "vibrato_update"]
                if diagnostic.effectMemoryReused {
                    categories.append("effect_memory_reused")
                    if diagnostic.effectType == 0x04 {
                        categories.append("4xy_vibrato_memory_applied")
                    }
                    if diagnostic.effectType == 0x06 {
                        categories.append("6xy_vibrato_memory_applied")
                    }
                }
                if diagnostic.effectType == 0x06 {
                    categories.append("vibrato_volume_slide_6xy")
                }
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: categories,
                    effectType: diagnostic.effectType,
                    effectParam: diagnostic.effectParam
                ))
                nextID += 1
            }
        }

        for diagnostic in adaptedPlan.diagnostics.envelopePositionEffects where diagnostic.applied {
            guard let activeEventIndex = diagnostic.activeEventIndex,
                  let appliedPositionFrame = diagnostic.appliedPositionFrame else {
                continue
            }
            events.append(RuntimeCMixerAdapterEvent(
                id: nextID,
                source: diagnostic.source,
                channelIndex: diagnostic.channelIndex,
                syntheticTick: diagnostic.syntheticTick,
                scheduledFrame: diagnostic.scheduledFrame,
                action: .envelopePositionUpdate(
                    activeEventIndex: activeEventIndex,
                    positionFrame: appliedPositionFrame
                ),
                categories: ["lxx_set_envelope_position", "envelope_position_update"],
                effectType: diagnostic.effectType,
                effectParam: diagnostic.effectParam
            ))
            nextID += 1
        }

        for cut in adaptedPlan.diagnostics.noteCutEffects where cut.applied {
            events.append(RuntimeCMixerAdapterEvent(
                id: nextID,
                source: cut.source,
                channelIndex: cut.channelIndex,
                syntheticTick: cut.syntheticTick,
                scheduledFrame: cut.scheduledFrame ?? 0,
                action: .noteCut(activeEventIndex: cut.activeEventIndex),
                categories: ["note_cut"]
            ))
            nextID += 1
        }
        profileSession?.recordPhase(
            "adapter_event_generation",
            startedAt: eventGenerationStart,
            fields: [
                AdapterPlanProfileField("synthetic_event_count", adaptedPlan.pattern.events.count),
                AdapterPlanProfileField("generated_adapter_event_count", events.count),
                AdapterPlanProfileField("voice_state_update_count", adaptedPlan.diagnostics.voiceStateUpdates.count),
                AdapterPlanProfileField("tone_portamento_effect_count", adaptedPlan.diagnostics.tonePortamentoEffects.count),
                AdapterPlanProfileField("portamento_slide_effect_count", adaptedPlan.diagnostics.portamentoSlideEffects.count),
                AdapterPlanProfileField("arpeggio_effect_count", adaptedPlan.diagnostics.arpeggioEffects.count),
                AdapterPlanProfileField("vibrato_effect_count", adaptedPlan.diagnostics.vibratoEffects.count),
                AdapterPlanProfileField("note_cut_effect_count", adaptedPlan.diagnostics.noteCutEffects.count),
            ]
        )

        let semanticMaterializationStart = profileSession?.beginPhase()
        let stateEvents = PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: adaptedPlan)
        let sourceFreeChannels = Set(adaptedPlan.xmEmptyRoutes.map(\.channelIndex))
        let carriedCount = stateEvents.lazy.filter {
            adaptedPlan.xmEnvelopeTimeline?.updatesByEvent[$0.activeEventIndex] == nil &&
                eventMappingsByIndex[$0.activeEventIndex] != nil
        }.count
        let stopCount = adaptedPlan.xmEmptyRoutes.lazy.filter { $0.stoppedEventIndex != nil }.count
        let channelCount = sourceFreeChannels.isEmpty ? 0 :
            (adaptedPlan.xmEnvelopeTimeline?.channelUpdates ?? []).lazy.filter { sourceFreeChannels.contains($0.channelIndex) }.count
        events.reserveAdditionalCapacity([carriedCount, stopCount, channelCount,
            adaptedPlan.xmEnvelopeTimeline?.updates.count ?? 0, adaptedPlan.xmAudibleTimeline?.updates.count ?? 0])
        let statePositionResolver = stateEvents.isEmpty ? nil : PlaybackSongSampleTimePositionResolver(plan: adaptedPlan)
        // Immutable lists share their backing storage across a publication run.
        let carriedPlaybackStateCategories = ["carried_playback_state"]
        for update in stateEvents {
            guard adaptedPlan.xmEnvelopeTimeline?.updatesByEvent[update.activeEventIndex] == nil else { continue }
            guard let mapping = eventMappingsByIndex[update.activeEventIndex] else { continue }
            // A carried voice may have started on a different row/tick (including EDx).
            let position = statePositionResolver?.position(atFrame: update.scheduledFrame)
            events.append(RuntimeCMixerAdapterEvent(
                id: events.count, source: position?.source ?? mapping.source, channelIndex: update.channelIndex,
                syntheticTick: position?.tickInRow ?? mapping.syntheticTick, scheduledFrame: update.scheduledFrame,
                action: .playbackStateChange(activeEventIndex: update.activeEventIndex, change: update.change),
                categories: carriedPlaybackStateCategories))
        }
        let emptyRouteStopCategories = ["empty_route_source_stop"]
        for route in adaptedPlan.xmEmptyRoutes {
            guard let old = route.stoppedEventIndex else { continue }
            events.append(.init(id: events.count, source: route.source, channelIndex: route.channelIndex,
                syntheticTick: route.tick, scheduledFrame: route.scheduledFrame, action: .sourceStop(activeEventIndex: old),
                categories: emptyRouteStopCategories))
        }
        let channelSemanticCategories = ["xm_channel_semantic_tick"]
        for update in adaptedPlan.xmEnvelopeTimeline?.channelUpdates ?? [] where sourceFreeChannels.contains(update.channelIndex) {
            events.append(.init(id: events.count, source: update.source, channelIndex: update.channelIndex,
                syntheticTick: update.tick, scheduledFrame: update.scheduledFrame, action: .channelSemanticUpdate(update),
                categories: channelSemanticCategories))
        }
        let envelopeSemanticCategories = ["xm_envelope_semantic_tick"]
        for update in adaptedPlan.xmEnvelopeTimeline?.updates ?? [] {
            events.append(RuntimeCMixerAdapterEvent(id: events.count, source: update.source,
                channelIndex: update.channelIndex, syntheticTick: update.tick, scheduledFrame: update.scheduledFrame,
                action: .envelopeSemanticUpdate(activeEventIndex: update.eventIndex, state: update.state),
                categories: envelopeSemanticCategories))
        }
        let audibleTargetCategories = ["xm_audible_output_target"]
        for update in adaptedPlan.xmAudibleTimeline?.updates ?? [] {
            events.append(RuntimeCMixerAdapterEvent(id: events.count, source: update.source,
                channelIndex: update.channelIndex, syntheticTick: update.tick, scheduledFrame: update.scheduledFrame,
                action: .audibleTargetUpdate(update), categories: audibleTargetCategories))
        }
        profileSession?.recordPhase("adapter_semantic_event_materialization", startedAt: semanticMaterializationStart)
        let sortingStart = profileSession?.beginPhase()
        let unsortedEventCount = events.count
        let assembly = events.finish(profileSession: profileSession)
        let plannedSongEndFrame = adaptedPlan.diagnostics.rowTiming
            .map { max($0.rowStartFrame, $0.rowStartFrame + max(0, $0.rowDurationFrames)) }
            .max()
        let plan = RuntimeCMixerAdapterEventPlan(
            generated: true,
            sampleRate: sampleRate,
            plannedSongEndFrame: plannedSongEndFrame,
            plannedEventCount: assembly.events.count,
            events: assembly.events,
            categories: assembly.categories,
            plan: adaptedPlan,
            runtimeOrderingEntries: assembly.runtimeOrderingEntries,
            profileSession: profileSession
        )
        profileSession?.recordPhase(
            "event_sorting_grouping",
            startedAt: sortingStart,
            fields: AdapterPlanProfileFields.adapterPlan(plan) + [
                AdapterPlanProfileField("unsorted_event_count", unsortedEventCount),
                AdapterPlanProfileField("wide_event_sort_count", assembly.metrics.wideEventSortCount),
                AdapterPlanProfileField("ordering_record_sort_count", assembly.metrics.orderingRecordSortCount),
                AdapterPlanProfileField("full_width_plan_copy_count", assembly.metrics.fullWidthPlanCopyCount),
                AdapterPlanProfileField("reserved_final_capacity", assembly.metrics.reservedCapacity),
            ]
        )
        profileSession?.recordPhase(
            "runtime_c_mixer_adapter_event_plan_make_total",
            startedAt: makeStart,
            fields: AdapterPlanProfileFields.playbackSong(song) +
                AdapterPlanProfileFields.syntheticPlan(adaptedPlan) +
                AdapterPlanProfileFields.adapterPlan(plan)
        )
        return plan
    }

    func events(matching context: AudioRuntimeTraceContext?) -> [RuntimeCMixerAdapterEvent] {
        guard let context,
              let orderIndex = context.orderIndex,
              let rowIndex = context.rowIndex else {
            return []
        }
        let tick = context.tickInRow ?? 0
        return events.filter { event in
            event.source.orderIndex == orderIndex &&
                event.source.rowIndex == rowIndex &&
                event.syntheticTick == tick &&
                (context.patternIndex == nil || context.patternIndex == event.source.patternIndex)
        }
    }

    func events(in range: PlaybackPatternLoopRange) -> [RuntimeCMixerAdapterEvent] {
        events.filter { range.contains($0.source) }
    }

    func adapterEventLoopRange(for range: PlaybackPatternLoopRange) -> RuntimeCMixerAdapterEventLoopRange? {
        guard generated,
              let diagnostics = plan?.diagnostics else {
            return nil
        }
        let rowTimings = diagnostics.rowTiming.filter { range.contains($0.source) }
        guard !rowTimings.isEmpty else {
            return nil
        }
        let plannedStartFrame = rowTimings
            .map(\.rowStartFrame)
            .min() ?? 0
        let plannedEndFrame = rowTimings
            .map { $0.rowStartFrame + max(0, $0.rowDurationFrames) }
            .max() ?? plannedStartFrame
        guard plannedEndFrame > plannedStartFrame else {
            return nil
        }
        return RuntimeCMixerAdapterEventLoopRange(
            playbackRange: range,
            plannedStartFrame: plannedStartFrame,
            plannedEndFrame: plannedEndFrame,
            events: events(in: range)
        )
    }

    func plannedRowStartFrame(matching context: AudioRuntimeTraceContext?) -> Int? {
        guard let context,
              let orderIndex = context.orderIndex,
              let rowIndex = context.rowIndex,
              let diagnostics = plan?.diagnostics else {
            return nil
        }
        return diagnostics.rowTiming.first { timing in
            timing.source.orderIndex == orderIndex &&
                timing.source.rowIndex == rowIndex &&
                (context.patternIndex == nil || timing.source.patternIndex == context.patternIndex)
        }?.rowStartFrame
    }

    func plannedFrame(matching context: AudioRuntimeTraceContext?) -> Int? {
        guard let context,
              let orderIndex = context.orderIndex,
              let rowIndex = context.rowIndex,
              let diagnostics = plan?.diagnostics else {
            return nil
        }
        guard let timing = diagnostics.rowTiming.first(where: { timing in
            timing.source.orderIndex == orderIndex &&
                timing.source.rowIndex == rowIndex &&
                (context.patternIndex == nil || timing.source.patternIndex == context.patternIndex)
        }) else {
            return nil
        }
        let tickInRow = min(max(0, context.tickInRow ?? 0), max(0, timing.effectiveSpeed - 1))
        let framesPerTick = sampleRate * 2.5 / Double(max(1, timing.effectiveBPM))
        let exactFrame = timing.rowStartExactFrame + (Double(tickInRow) * framesPerTick)
        guard exactFrame.isFinite else {
            return nil
        }
        if exactFrame <= 0 {
            return 0
        }
        if exactFrame >= Double(Int.max) {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }

    private static func changedGain(from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic) -> Float? {
        guard let before = update.gainBefore,
              let after = update.gainAfter,
              before != after else {
            return nil
        }
        return after
    }

    private static func changedPan(from update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic) -> Float? {
        guard let before = update.panBefore,
              let after = update.panAfter,
              before != after else {
            return nil
        }
        return after
    }
}

struct PlaybackSongSampleTimePosition: Equatable {
    let frame: Int
    let source: PlaybackPosition
    let syntheticRow: Int
    let tickInRow: Int
    let rowStartFrame: Int
    let rowEndFrame: Int
    let rowDurationFrames: Int
    let frameOffsetInRow: Int
    let effectiveSpeed: Int
    let effectiveBPM: Int
    let status: String
}

struct PlaybackSongSampleTimePositionResolver: Equatable {
    private let sampleRate: Double
    private let rowTimings: [PlaybackSongSyntheticRowTimingDiagnostic]

    init(plan: PlaybackSongSyntheticPlan) {
        sampleRate = plan.timingConfig.sampleRate
        rowTimings = plan.diagnostics.rowTiming.sorted { lhs, rhs in
            if lhs.syntheticRow != rhs.syntheticRow {
                return lhs.syntheticRow < rhs.syntheticRow
            }
            return lhs.rowStartFrame < rhs.rowStartFrame
        }
    }

    init(rowTimings: [PlaybackSongSyntheticRowTimingDiagnostic], sampleRate: Double) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : MixerRenderConfig.defaultSampleRate
        self.rowTimings = rowTimings.sorted { lhs, rhs in
            if lhs.syntheticRow != rhs.syntheticRow {
                return lhs.syntheticRow < rhs.syntheticRow
            }
            return lhs.rowStartFrame < rhs.rowStartFrame
        }
    }

    func position(atFrame frame: Int) -> PlaybackSongSampleTimePosition? {
        guard !rowTimings.isEmpty else {
            return nil
        }
        let safeFrame = max(0, frame)
        guard let first = rowTimings.first,
              let last = rowTimings.last else {
            return nil
        }
        if safeFrame < first.rowStartFrame {
            return position(in: first, frame: safeFrame, status: "before_start")
        }
        let finalEndFrame = max(last.rowStartFrame + last.rowDurationFrames, last.rowStartFrame)
        if safeFrame >= finalEndFrame {
            return position(in: last, frame: safeFrame, status: "at_or_after_end")
        }

        var lowerBound = 0
        var upperBound = rowTimings.count - 1
        while lowerBound <= upperBound {
            let mid = (lowerBound + upperBound) / 2
            let timing = rowTimings[mid]
            let rowStart = timing.rowStartFrame
            let rowEnd = max(timing.rowStartFrame + timing.rowDurationFrames, rowStart + 1)
            if safeFrame < rowStart {
                upperBound = mid - 1
            } else if safeFrame >= rowEnd {
                lowerBound = mid + 1
            } else {
                return position(in: timing, frame: safeFrame, status: "in_range")
            }
        }

        let fallbackIndex = min(max(0, upperBound), rowTimings.count - 1)
        return position(in: rowTimings[fallbackIndex], frame: safeFrame, status: "in_range")
    }

    private func position(
        in timing: PlaybackSongSyntheticRowTimingDiagnostic,
        frame: Int,
        status: String
    ) -> PlaybackSongSampleTimePosition {
        let framesPerTick = sampleRate * 2.5 / Double(max(1, timing.effectiveBPM))
        let tick = tickInRow(forFrame: frame, timing: timing, framesPerTick: framesPerTick)
        return PlaybackSongSampleTimePosition(
            frame: frame,
            source: timing.source,
            syntheticRow: timing.syntheticRow,
            tickInRow: tick,
            rowStartFrame: timing.rowStartFrame,
            rowEndFrame: timing.rowStartFrame + timing.rowDurationFrames,
            rowDurationFrames: timing.rowDurationFrames,
            frameOffsetInRow: max(0, frame - timing.rowStartFrame),
            effectiveSpeed: timing.effectiveSpeed,
            effectiveBPM: timing.effectiveBPM,
            status: status
        )
    }

    private func tickInRow(
        forFrame frame: Int,
        timing: PlaybackSongSyntheticRowTimingDiagnostic,
        framesPerTick: Double
    ) -> Int {
        guard framesPerTick.isFinite,
              framesPerTick > 0,
              timing.effectiveSpeed > 1 else {
            return 0
        }
        var result = 0
        for tick in 1..<timing.effectiveSpeed {
            let tickFrame = Self.floorFrame(timing.rowStartExactFrame + (Double(tick) * framesPerTick))
            guard frame >= tickFrame else {
                break
            }
            result = tick
        }
        return result
    }

    private static func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}
