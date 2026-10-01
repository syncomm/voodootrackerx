import Foundation

/// Adapter-owned channel controls survive source absence. No cursor or PCM is stored here.
struct PlaybackXMChannelRow: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let scheduledFrame: Int
    let controls: PlaybackSongSyntheticAdapter.ChannelState
    let instrumentOnlyReset: MixerPlaybackStateChange?
}

/// An exact mapped header selection with no represented audio source.
struct PlaybackXMEmptyRoute: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let scheduledFrame: Int
    let instrumentIndex: Int
    let sampleIndex: Int
    let stoppedEventIndex: Int?
}

/// One channel's canonical tick state. A nil source generation requires no mixer voice.
struct PlaybackXMChannelUpdate: Equatable {
    let channelIndex: Int
    let instrumentIndex: Int
    let sampleIndex: Int
    let sourceEventIndex: Int?
    let source: PlaybackPosition
    let tick: Int
    let scheduledFrame: Int
    let bpm: Int
    let speed: Int
    let state: MixerEnvelopeSemanticState
    var carriedInstrumentIndex: Int? = nil
    var cachedDefaultVolume: Int? = nil
    var cachedDefaultPan: UInt8? = nil
    var selectionFrame = 0
}

extension PlaybackSongSyntheticAdapter {
    /// Selects immutable header state without resolving or fabricating a PlaybackSample.
    static func selectEmptyHeader(_ header: XMSourceSampleSlotProvenance, cell: PlaybackCell,
        song: PlaybackSong, timingConfig: SyntheticTrackerTimingConfig, state: inout ChannelState) -> PlaybackStepMapping {
        state.activeEventIndex = nil
        state.activeEventMappingIndex = nil
        state.activeInstrumentIndex = nil
        state.activeSampleIndex = nil
        state.activeSampleVolume = nil
        state.semanticInstrumentIndex = Int(cell.instrument)
        state.semanticSampleIndex = header.sampleIndex
        state.triggeredSampleDefaultVolume = clampedVolumeValue(Int(header.volume))
        state.triggeredSampleDefaultPan = header.panning
        state.baseChannelVolume = state.triggeredSampleDefaultVolume
        state.volumeValueZeroedByAxy = false
        state.initializePanning(fromSampleHeader: header.panning)
        let instrument = song.instrumentsByIndex[Int(cell.instrument)]!
        state.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
        applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope, timingConfig: timingConfig), to: &state)
        let finetune = cell.effectType == 0x0E && cell.effectParam >> 4 == 5 && song.usesLinearFrequencyTable
            ? setFinetuneValue(from: cell) : header.finetune
        // These are period-domain controls, not a source cursor or a mixer step event.
        state.activeSampleBaseSampleRate = PlaybackSample.xmNeutralSampleRate
        state.activeSampleRelativeNote = header.relativeNote
        state.activeSampleFinetune = finetune
        state.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
        let pitch = playbackStepMapping(note: cell.note, relativeNote: header.relativeNote, finetune: finetune,
            baseSampleRate: PlaybackSample.xmNeutralSampleRate, usesLinearFrequencyTable: song.usesLinearFrequencyTable,
            timingConfig: timingConfig)
        state.activeLinearPeriod = pitch.linearPeriod
        state.activeAmigaPeriod = pitch.amigaPeriod
        state.activePlaybackStep = pitch.playbackStep
        state.vibratoOutputLinearPeriod = nil
        state.vibratoOutputAmigaPeriod = nil
        return pitch
    }
}

/// A held semantic target. Source playback and audible ramps have separate ownership.
struct MixerEnvelopeSemanticState: Equatable {
    var volumeTick = 0
    var panTick = 0
    var keyOn = true
    var fadeoutAccumulator = 32_768
    var volumeValue: Float = 1

    var fadeoutValue: Float { Float(fadeoutAccumulator) / 32_768 }
}

struct PlaybackXMEnvelopeUpdate: Equatable {
    let eventIndex: Int
    let channelIndex: Int
    let source: PlaybackPosition
    let tick: Int
    let scheduledFrame: Int
    let bpm: Int
    let speed: Int
    let state: MixerEnvelopeSemanticState
}

/// Derives all envelope/release targets from the already traversed Fxx timeline.
/// Neither renderer advances this state from elapsed samples or a cached BPM.
struct PlaybackXMEnvelopeTimeline: Equatable {
    struct Instrument: Equatable {
        let volume: PlaybackVolumeEnvelope
        let pan: PlaybackPanningEnvelope
    }

    let timing: PlaybackSongFxxTimingPlan
    let instruments: [Int: Instrument]
    let instrumentsByIdentity: [Int: Instrument]
    private(set) var endFrame: Int
    private(set) var updates: [PlaybackXMEnvelopeUpdate] = []
    private(set) var updatesByEvent: [Int: [PlaybackXMEnvelopeUpdate]] = [:]
    private(set) var channelUpdates: [PlaybackXMChannelUpdate] = []

    init(song: PlaybackSong, timing: PlaybackSongFxxTimingPlan, plan: PlaybackSongSyntheticPlan) {
        self.timing = timing
        endFrame = timing.frameFor(row: timing.rowTimings.count)
        instrumentsByIdentity = song.instrumentsByIndex.mapValues {
            Instrument(volume: $0.volumeEnvelope, pan: $0.panningEnvelope)
        }
        instruments = Dictionary(uniqueKeysWithValues: plan.diagnostics.eventMappings.compactMap { mapping in
            guard let instrument = song.instrumentsByIndex[mapping.instrumentIndex] else { return nil }
            let volume = instrument.volumeEnvelope
            let pan = instrument.panningEnvelope
            return (mapping.eventIndex, Instrument(volume: PlaybackVolumeEnvelope(enabled: volume.enabled,
                points: Array(volume.points.prefix(12)), sustainPointIndex: volume.sustainPointIndex,
                loopStartPointIndex: volume.loopStartPointIndex, loopEndPointIndex: volume.loopEndPointIndex,
                typeFlags: volume.typeFlags, fadeout: volume.fadeout), pan: PlaybackPanningEnvelope(enabled: pan.enabled,
                points: Array(pan.points.prefix(12)), sustainPointIndex: pan.sustainPointIndex,
                loopStartPointIndex: pan.loopStartPointIndex, loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags)))
        })
        rebuild(plan: plan)
    }

    /// Re-fold explicit reset history while retaining the canonical tick frames.
    mutating func rebuild(plan: PlaybackSongSyntheticPlan) {
        updates = []
        updatesByEvent = [:]
        channelUpdates = []
        guard !plan.xmEmptyRoutes.isEmpty ||
                plan.pattern.events.contains(where: { $0.volumeEnvelope != nil || $0.panEnvelope != nil }) ||
                plan.diagnostics.keyOffEvents.contains(where: \.applied) || !plan.playbackStateEvents.isEmpty else { return }
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        let mappings = plan.diagnostics.eventMappings.sorted { $0.eventIndex < $1.eventIndex }
        struct Tick {
            let row: Int
            let source: PlaybackPosition
            let tick: Int
            let frame: Int
            let bpm: Int
            let speed: Int
            var advances = true
        }
        var ticks = [Tick]()
        var rowIndex = 0
        while rowIndex < timing.rowTimings.count || timing.frameFor(row: rowIndex) < endFrame {
            guard let source = timing.rowTimings.indices.contains(rowIndex)
                ? timing.rowTimings[rowIndex].source : timing.rowTimings.last?.source else { break }
            let config = timing.timingConfig(forSyntheticRow: rowIndex)
            for tick in 0..<config.speed {
                ticks.append(Tick(row: rowIndex, source: source, tick: tick,
                    frame: timing.frameFor(row: rowIndex, tick: tick), bpm: config.bpm, speed: config.speed))
            }
            rowIndex += 1
        }
        let tickFrames = Set(ticks.map(\.frame))
        struct Route {
            let eventIndex: Int?
            let channelIndex: Int
            let instrumentIndex: Int
            let sampleIndex: Int
            let frame: Int
        }
        var routes = mappings.map { mapping in
            Route(eventIndex: mapping.eventIndex, channelIndex: mapping.channelIndex,
                instrumentIndex: mapping.instrumentIndex, sampleIndex: mapping.sampleIndex,
                frame: scheduler.frame(for: plan.pattern.events[mapping.eventIndex]))
        }
        routes += plan.xmEmptyRoutes.map { Route(eventIndex: nil, channelIndex: $0.channelIndex,
            instrumentIndex: $0.instrumentIndex, sampleIndex: $0.sampleIndex, frame: $0.scheduledFrame) }
        routes.sort { $0.frame == $1.frame ? ($0.eventIndex ?? -1) < ($1.eventIndex ?? -1) : $0.frame < $1.frame }
        let changes = PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan)
        let routesByChannel = Dictionary(grouping: routes, by: \.channelIndex)
        let rowsByChannel = Dictionary(grouping: plan.xmChannelRows, by: \.channelIndex)
        let changesByEvent = Dictionary(grouping: changes, by: \.activeEventIndex)
        let releasesByChannel = Dictionary(grouping: plan.diagnostics.keyOffEvents.filter(\.applied), by: \.channelIndex)
        let positionsByChannel = Dictionary(grouping: plan.diagnostics.envelopePositionEffects.filter(\.applied), by: \.channelIndex)
        let cutsByChannel = Dictionary(grouping: plan.diagnostics.noteCutEffects.filter(\.applied), by: \.channelIndex)
        struct Change {
            let scheduledFrame: Int
            let change: MixerPlaybackStateChange
        }
        for (channel, channelRoutes) in routesByChannel {
            let channelRows = rowsByChannel[channel] ?? []
            let controlsByRow = Dictionary(uniqueKeysWithValues: channelRows.map { ($0.syntheticRow, $0.controls) })
            for (routeIndex, route) in channelRoutes.enumerated() {
                guard let instrument = route.eventIndex.flatMap({ instruments[$0] }) ?? instrumentsByIdentity[route.instrumentIndex] else { continue }
                let index = route.eventIndex
                let start = route.frame
                let stop = routeIndex + 1 < channelRoutes.count ? channelRoutes[routeIndex + 1].frame : Int.max
                let cuts = (cutsByChannel[channel] ?? []).filter {
                    $0.activeEventIndex == index }.compactMap(\.scheduledFrame).filter { $0 >= start }
                let sourceEnd = cuts.min() ?? Int.max
                let releases = Set((releasesByChannel[channel] ?? []).filter {
                    ($0.activeEventIndex == index || $0.activeEventIndex == nil) &&
                        $0.scheduledFrame.map { $0 >= start && $0 < stop } == true
                }.compactMap(\.scheduledFrame))
                let positions = (positionsByChannel[channel] ?? []).filter {
                    ($0.activeEventIndex == index || $0.activeEventIndex == nil) &&
                        $0.scheduledFrame >= start && $0.scheduledFrame < stop
                }
                var resets = (index.flatMap { changesByEvent[$0] } ?? []).map {
                    Change(scheduledFrame: $0.scheduledFrame, change: $0.change)
                }
                // The existing instrument-only dispatch owns default restoration. Its silent
                // reset belongs to this channel clock, never to a fabricated source event.
                resets += channelRows.compactMap { row in
                    guard row.channelIndex == channel, row.scheduledFrame >= start, row.scheduledFrame < stop,
                          row.controls.activeEventIndex == nil, let reset = row.instrumentOnlyReset else { return nil }
                    return Change(scheduledFrame: row.scheduledFrame, change: reset)
                }
                let volumeEnabled = index.map { plan.pattern.events[$0].volumeEnvelope != nil }
                    ?? (instrument.volume.enabled && !instrument.volume.points.isEmpty)
                let panEnabled = index.map { plan.pattern.events[$0].panEnvelope != nil }
                    ?? (instrument.pan.enabled && !instrument.pan.points.isEmpty)
                let publishesToVoice = volumeEnabled || panEnabled || releases.contains { $0 < sourceEnd } ||
                    resets.contains { $0.scheduledFrame < sourceEnd }
                guard publishesToVoice || plan.xmEmptyRoutes.contains(where: { $0.channelIndex == channel }) else { continue }
                let routeControls = channelRows.last { $0.scheduledFrame <= start }?.controls
                var state = MixerEnvelopeSemanticState()
                var first = true
                var history = [PlaybackXMEnvelopeUpdate]()
                var low = 0
                var high = ticks.count
                while low < high {
                    let middle = (low + high) / 2
                    if ticks[middle].frame < start { low = middle + 1 } else { high = middle }
                }
                var clock = Array(ticks[low...].prefix { $0.frame < stop })
                for frame in Set(resets.map(\.scheduledFrame)).subtracting(tickFrames) where frame >= start && frame < stop {
                    if let context = ticks.last(where: { $0.frame <= frame }) {
                        clock.append(Tick(row: context.row, source: context.source, tick: context.tick,
                            frame: frame, bpm: context.bpm, speed: context.speed, advances: false))
                    }
                }
                clock.sort {
                    if $0.frame != $1.frame { return $0.frame < $1.frame }
                    return $0.row == $1.row ? $0.tick < $1.tick : $0.row < $1.row
                }
                for tick in clock {
                    let frame = tick.frame
                    guard frame >= start && frame < stop else { continue }
                    var resetVolume = first
                    var resetPan = first
                    let wasKeyOn = state.keyOn
                    for reset in resets where reset.scheduledFrame == frame {
                        switch reset.change {
                        case let .reset(dimensions):
                            if dimensions.volumeEnvelope { state.volumeTick = 0; resetVolume = true }
                            if dimensions.panEnvelope { state.panTick = 0; resetPan = true }
                            if dimensions.keyOn { state.keyOn = true }
                            if dimensions.fadeout { state.fadeoutAccumulator = 32_768 }
                        case .keyOff:
                            // XM uses the instrument's tick fadeout; per-frame rates belong to generic synthetic voices.
                            state.keyOn = false
                        }
                    }
                    if releases.contains(frame) { state.keyOn = false }
                    let releasing = wasKeyOn && !state.keyOn
                    if volumeEnabled {
                        if let position = positions.last(where: { $0.scheduledFrame == frame }) {
                            state.volumeTick = Int(position.effectParam)
                        } else if !resetVolume && tick.advances {
                            state.volumeTick = Self.advance(state.volumeTick, envelope: instrument.volume,
                                keyOn: state.keyOn, releasing: releasing)
                        }
                        state.volumeValue = instrument.volume.value(at: state.volumeTick)
                    }
                    if panEnabled && !resetPan && tick.advances {
                        let pan = instrument.pan
                        let clock = PlaybackVolumeEnvelope(enabled: pan.enabled, points: pan.points,
                            sustainPointIndex: pan.sustainPointIndex, loopStartPointIndex: pan.loopStartPointIndex,
                            loopEndPointIndex: pan.loopEndPointIndex, typeFlags: pan.typeFlags, fadeout: 0)
                        state.panTick = Self.advance(state.panTick, envelope: clock, keyOn: state.keyOn, releasing: releasing)
                    }
                    if !state.keyOn && tick.advances {
                        state.fadeoutAccumulator = max(0, state.fadeoutAccumulator - max(0, instrument.volume.fadeout))
                    }
                    let sourceIndex = frame < sourceEnd ? index : nil
                    channelUpdates.append(.init(channelIndex: channel, instrumentIndex: route.instrumentIndex,
                        sampleIndex: route.sampleIndex, sourceEventIndex: sourceIndex, source: tick.source,
                        tick: tick.tick, scheduledFrame: frame, bpm: tick.bpm, speed: tick.speed, state: state,
                        carriedInstrumentIndex: (controlsByRow[tick.row] ?? channelRows.last?.controls)?.carriedInstrumentIndex,
                        cachedDefaultVolume: routeControls?.triggeredSampleDefaultVolume,
                        cachedDefaultPan: routeControls?.triggeredSampleDefaultPan, selectionFrame: start))
                    if let index = sourceIndex, publishesToVoice {
                        history.append(PlaybackXMEnvelopeUpdate(eventIndex: index, channelIndex: channel,
                            source: tick.source, tick: tick.tick, scheduledFrame: frame, bpm: tick.bpm,
                            speed: tick.speed, state: state))
                    }
                    first = false
                }
                if let index, !history.isEmpty { updatesByEvent[index] = history }
                updates.append(contentsOf: history)
            }
        }
        channelUpdates.sort { $0.scheduledFrame == $1.scheduledFrame ? $0.channelIndex < $1.channelIndex : $0.scheduledFrame < $1.scheduledFrame }
        updates.sort { $0.scheduledFrame == $1.scheduledFrame ? $0.eventIndex < $1.eventIndex : $0.scheduledFrame < $1.scheduledFrame }
    }

    /// Bounded offline tails use the timing plan's existing final-tempo extrapolation.
    /// Tail coordinates retain the last source row; no additional song rows or Fxx commands are invented.
    mutating func extend(throughFrame frame: Int, plan: PlaybackSongSyntheticPlan) {
        guard frame > endFrame else { return }
        endFrame = frame
        rebuild(plan: plan)
    }

    /// Returns state immediately before a window; the boundary tick remains scheduled.
    func state(eventIndex: Int, before frame: Int) -> MixerEnvelopeSemanticState? {
        guard let history = updatesByEvent[eventIndex] else { return nil }
        var low = 0
        var high = history.count
        while low < high {
            let middle = (low + high) / 2
            if history[middle].scheduledFrame < frame { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? history[low - 1].state : nil
    }

    /// Includes the boundary tick. Silent state is available without consulting any C voice.
    func channelState(channelIndex: Int, atOrBefore frame: Int) -> PlaybackXMChannelUpdate? {
        channelUpdates.last { $0.channelIndex == channelIndex && $0.scheduledFrame <= frame }
    }

    private static func advance(_ position: Int, envelope: PlaybackVolumeEnvelope, keyOn: Bool, releasing: Bool) -> Int {
        let held = envelope.sustainEnabled && position == envelope.sustainPoint?.tick
        // Release publishes the held sustain point once, then advances on the next tick.
        if held && (keyOn || releasing) { return position }
        let next = position + 1
        if envelope.loopEnabled, let start = envelope.loopStartPoint?.tick, let end = envelope.loopEndPoint?.tick,
           start <= end, next >= end, !(envelope.sustainEnabled && envelope.sustainPoint?.tick == end && !keyOn) {
            return start
        }
        return next
    }
}

extension PlaybackSongSyntheticPlan {
    func extendingEnvelopeTail(throughFrame frame: Int) -> PlaybackSongSyntheticPlan {
        var plan = self
        var timeline = xmEnvelopeTimeline
        timeline?.extend(throughFrame: frame, plan: self)
        plan.xmEnvelopeTimeline = timeline
        return plan
    }
}
