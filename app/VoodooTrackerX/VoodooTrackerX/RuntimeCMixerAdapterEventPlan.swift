import Foundation

enum RuntimeCMixerAdapterEventSource: String, Equatable {
    case playbackEngineSimple = "playback_engine_simple"
    case offlineAdapterPlan = "offline_adapter_plan"
    case hybrid = "hybrid"
}

enum RuntimeCMixerAdapterEventAction: Equatable {
    case noteTrigger(eventIndex: Int, event: SyntheticTrackerEvent, mapping: PlaybackSongSyntheticEventMapping)
    case gainPanUpdate(activeEventIndex: Int, gain: Float?, pan: Float?)
    case stepUpdate(activeEventIndex: Int, playbackStep: Double)
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
             let .stepUpdate(activeEventIndex, _):
            return activeEventIndex
        case let .noteCut(activeEventIndex):
            return activeEventIndex
        }
    }
}

struct RuntimeCMixerAdapterEventPlan: Equatable {
    let generated: Bool
    let sampleRate: Double
    let plannedSongEndFrame: Int?
    let plannedEventCount: Int
    let events: [RuntimeCMixerAdapterEvent]
    let categories: [String]
    let plan: PlaybackSongSyntheticPlan?

    var plannedSongEndSeconds: Double? {
        guard let plannedSongEndFrame,
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

    static func make(song: PlaybackSong?, sampleRate: Double) -> RuntimeCMixerAdapterEventPlan {
        guard let song else {
            return unavailable(sampleRate: sampleRate)
        }
        let adaptedPlan = PlaybackSongSyntheticAdapter.adapt(
            song,
            startOrderIndex: 0,
            orderCount: song.orders.count,
            sampleRate: sampleRate
        )
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
        let appliedArpeggioEventIndices = Set(
            adaptedPlan.diagnostics.arpeggioEffects
                .filter(\.applied)
                .compactMap(\.activeEventIndex)
        )
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
        var events = [RuntimeCMixerAdapterEvent]()
        var nextID = 0
        var seenNoteTriggerChannels = Set<Int>()

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
            let isAxyVolumeSlide = mapping.effectType == 0x0A &&
                appliedAxyVolumeSlideEventIndices.contains(eventIndex)
            if isAxyVolumeSlide {
                categories.append("axy_volume_slide")
            }
            let isArpeggio = mapping.effectType == 0x00 &&
                mapping.effectParam != 0 &&
                appliedArpeggioEventIndices.contains(eventIndex)
            if isArpeggio {
                categories.append("arpeggio_0xy")
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
                isFinePortamentoUp ||
                isFinePortamentoDown ||
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
            case .gxxSetGlobalVolume:
                categories.append("gxx_global_volume_update")
                categories.append("global_volume_update")
            case .hxyGlobalVolumeSlide:
                categories.append("hxy_global_volume_update")
                categories.append("global_volume_update")
            case .axyVolumeSlide:
                categories.append("axy_volume_slide")
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
            case .effect6xyVolumeSlide:
                categories.append("vibrato_volume_slide_6xy")
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
                events.append(RuntimeCMixerAdapterEvent(
                    id: nextID,
                    source: diagnostic.source,
                    channelIndex: diagnostic.channelIndex,
                    syntheticTick: update.syntheticTick,
                    scheduledFrame: update.scheduledFrame,
                    action: .stepUpdate(activeEventIndex: activeEventIndex, playbackStep: update.playbackStepAfter),
                    categories: categories,
                    effectType: diagnostic.effectType == 0x05 ? diagnostic.effectType : nil,
                    effectParam: diagnostic.effectType == 0x05 ? diagnostic.effectParam : nil
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

        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.scheduledFrame != rhs.scheduledFrame {
                return lhs.scheduledFrame < rhs.scheduledFrame
            }
            if lhs.syntheticTick != rhs.syntheticTick {
                return lhs.syntheticTick < rhs.syntheticTick
            }
            if priority(lhs.action) != priority(rhs.action) {
                return priority(lhs.action) < priority(rhs.action)
            }
            if lhs.source.orderIndex != rhs.source.orderIndex {
                return lhs.source.orderIndex < rhs.source.orderIndex
            }
            if lhs.source.rowIndex != rhs.source.rowIndex {
                return lhs.source.rowIndex < rhs.source.rowIndex
            }
            return lhs.id < rhs.id
        }
        let categories = Array(Set(sortedEvents.flatMap(\.categories))).sorted()
        let plannedSongEndFrame = adaptedPlan.diagnostics.rowTiming
            .map { max($0.rowStartFrame, $0.rowStartFrame + max(0, $0.rowDurationFrames)) }
            .max()
        return RuntimeCMixerAdapterEventPlan(
            generated: true,
            sampleRate: sampleRate,
            plannedSongEndFrame: plannedSongEndFrame,
            plannedEventCount: sortedEvents.count,
            events: sortedEvents,
            categories: categories,
            plan: adaptedPlan
        )
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

    private static func priority(_ action: RuntimeCMixerAdapterEventAction) -> Int {
        switch action {
        case .gainPanUpdate, .stepUpdate:
            return 0
        case .noteCut:
            return 1
        case .noteTrigger:
            return 2
        }
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
