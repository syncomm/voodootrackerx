import Foundation
#if canImport(MixerCore)
import MixerCore
#endif

/// Value-owned copy of the C output state. All transition math stays in the shared C engine.
struct MixerAudibleOutputState: Equatable {
    var raw = VTXCMixerOutputState()
    var enabled: Bool { raw.enabled != 0 }
    var durationFrames: Int { Int(raw.duration_frames) }
    var positionFrame: Int { Int(raw.position_frame) }
    var start: [Float] { [raw.start.mono, raw.start.left, raw.start.right] }
    var target: [Float] { [raw.target.mono, raw.target.left, raw.target.right] }
    var current: [Float] {
        let value = vtx_c_mixer_output_value(raw)
        return [value.mono, value.left, value.right]
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.enabled == rhs.enabled && lhs.start == rhs.start && lhs.target == rhs.target &&
            lhs.durationFrames == rhs.durationFrames && lhs.positionFrame == rhs.positionFrame &&
            lhs.raw.retiring == rhs.raw.retiring
    }

    mutating func publish(_ update: PlaybackXMAudibleUpdate, config: MixerRenderConfig) {
        let law = config.panLaw == .linear ? VTX_C_MIXER_PAN_LAW_LINEAR : VTX_C_MIXER_PAN_LAW_FT2_EQUAL_POWER
        if !enabled, let seed = update.activation {
            _ = vtx_c_mixer_output_publish(&raw, vtx_c_mixer_output_gains(law, seed.amplitude, seed.pan), 0, 0)
        }
        let target = vtx_c_mixer_output_gains(law, update.amplitude, update.pan)
        _ = vtx_c_mixer_output_publish(&raw, target, UInt32(clamping: update.durationFrames), update.rebaseFromCurrent ? 1 : 0)
    }

    mutating func advance(_ frames: Int) {
        vtx_c_mixer_output_advance(&raw, UInt32(clamping: frames))
    }

    mutating func retire(frames: Int) {
        vtx_c_mixer_output_retire(&raw, UInt32(clamping: frames))
    }

    mutating func retireSong(sampleRate: Double) {
        vtx_c_mixer_output_retire_song(&raw, vtx_c_mixer_song_retirement_frame_count(sampleRate))
    }
}

/// Existing generic gain/pan where a plain voice first enters release/reset output.
struct MixerAudibleOutputSeed: Equatable {
    let amplitude: Float
    let pan: Float
}

struct PlaybackXMAudibleUpdate: Equatable {
    let eventIndex: Int
    let channelIndex: Int
    let source: PlaybackPosition
    let tick: Int
    let scheduledFrame: Int
    let bpm: Int
    let speed: Int
    let amplitude: Float
    let pan: Float
    let durationFrames: Int
    let intent: String
    var activation: MixerAudibleOutputSeed? = nil
    var rebaseFromCurrent = false
}

/// Coalesces existing typed factor writes with semantic targets without changing effect handlers.
struct PlaybackXMAudibleTimeline: Equatable {
    let updates: [PlaybackXMAudibleUpdate]
    let updatesByEvent: [Int: [PlaybackXMAudibleUpdate]]
    let planningHistoryDiagnostics: PlaybackXMHistoryLookupDiagnostics
    // Construction identity slots preceding automatic pitch, including pruned publications.
    let preexistingPublicationCount: Int

    init(plan: PlaybackSongSyntheticPlan) {
        var all = [PlaybackXMAudibleUpdate]()
        let changes = Dictionary(grouping: plan.diagnostics.voiceStateUpdates.filter(\.activeVoiceUpdated),
            by: { $0.activeEventIndex ?? -1 })
        var work = PlaybackXMHistoryLookupDiagnostics()
        work.indexBuildCount = 1
        work.entriesIndexed = changes.values.reduce(0) { $0 + $1.count }
        let resets = Dictionary(grouping: PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), by: \.activeEventIndex)
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        var preexistingCount = 0
        var mappingsByIndex: [Int: PlaybackSongSyntheticEventMapping]?
        for (index, event) in plan.pattern.events.enumerated() {
            let mapping: PlaybackSongSyntheticEventMapping?
            if plan.diagnostics.eventMappings.indices.contains(index),
               plan.diagnostics.eventMappings[index].eventIndex == index {
                mapping = plan.diagnostics.eventMappings[index]
            } else {
                // Native producers append mappings with their generations. Only manual
                // or orphaned histories need this temporary index, built at most once.
                if mappingsByIndex == nil {
                    mappingsByIndex = Dictionary(plan.diagnostics.eventMappings.map { ($0.eventIndex, $0) },
                        uniquingKeysWith: { _, last in last })
                }
                mapping = mappingsByIndex?[index]
            }
            let history = plan.xmEnvelopeTimeline?.updatesByEvent[index] ?? []
            let emitsOutput = mapping != nil && event.sample.frameCount > 0 &&
                event.initialSourceFrame < event.sample.frameCount
            // Planned legacy identities existed even when C refused the source.
            if event.volumeEnvelope != nil { preexistingCount += history.count }
            guard emitsOutput || (event.volumeEnvelope == nil && !history.isEmpty) else { continue }
            let birth = emitsOutput ? scheduler.frame(for: event) : history[0].scheduledFrame
            let channel = mapping?.channelIndex ?? history[0].channelIndex
            // Consume the existing semantic clock where it is needed. Plain sources add
            // only their birth and actual factor-write frames, never a neutral tick clock.
            let retainsTickPublications = event.volumeEnvelope != nil
            let sourceWrites = changes[index] ?? []
            let writes = sourceWrites.enumerated().sorted {
                $0.element.scheduledFrame == $1.element.scheduledFrame ? $0.offset < $1.offset :
                    $0.element.scheduledFrame < $1.element.scheduledFrame
            }.map(\.element)
            let resetFrames = Set((resets[index] ?? []).compactMap { update -> Int? in
                if case .reset = update.change { return update.scheduledFrame }; return nil
            })
            var gain = event.gain
            var pan = event.pan
            var writeIndex = 0
            var semanticIndex = 0
            var observedPriorGain = event.gain
            var observedPriorPan = event.pan
            var observedActivation = false
            var state = MixerEnvelopeSemanticState()
            var channelPanning = 128.0
            var initial = true
            var lastAmplitude: Float?
            var lastPan: Float?
            let birthRow = mapping?.syntheticRow ?? event.row
            let birthTiming = plan.diagnostics.rowTiming.indices.contains(birthRow)
                ? plan.diagnostics.rowTiming[birthRow] : nil
            while initial || semanticIndex < history.count || writeIndex < writes.count {
                let frame = initial ? birth : min(
                    semanticIndex < history.count ? history[semanticIndex].scheduledFrame : Int.max,
                    writeIndex < writes.count ? writes[writeIndex].scheduledFrame : Int.max)
                // Global projection records a prospective first-tail target. It only
                // becomes audible when the existing semantic timeline extends there.
                if !initial, frame >= (plan.xmEnvelopeTimeline?.endFrame ?? Int.max) { break }
                var source = mapping?.source ?? history[0].source
                var tick = mapping?.syntheticTick ?? history[0].tick
                var bpm = birthTiming?.effectiveBPM ?? plan.timingConfig.bpm
                var speed = birthTiming?.effectiveSpeed ?? plan.timingConfig.speed
                // A write between canonical ticks consumes held semantic factors. It
                // does not invent another envelope advancement or source generation.
                if writeIndex < writes.count, writes[writeIndex].scheduledFrame == frame {
                    let write = writes[writeIndex]
                    source = write.source; tick = write.syntheticTick
                    if plan.diagnostics.rowTiming.indices.contains(write.syntheticRow) {
                        let timing = plan.diagnostics.rowTiming[write.syntheticRow]
                        bpm = timing.effectiveBPM; speed = timing.effectiveSpeed
                    } else {
                        bpm = plan.xmEnvelopeTimeline?.timing.finalBPM ?? bpm
                        speed = plan.xmEnvelopeTimeline?.timing.finalSpeed ?? speed
                    }
                }
                let firstSemanticIndex = semanticIndex
                while semanticIndex < history.count && history[semanticIndex].scheduledFrame <= frame {
                    let semantic = history[semanticIndex]
                    state = semantic.state; channelPanning = semantic.channelPanningValue
                    source = semantic.source; tick = semantic.tick; bpm = semantic.bpm; speed = semantic.speed
                    semanticIndex += 1
                }
                var visibleGain = gain
                var quickVolume = false
                var noteCut = false
                while writeIndex < writes.count && writes[writeIndex].scheduledFrame <= frame {
                    let write = writes[writeIndex]
                    if let after = write.gainAfter, write.gainBefore != after {
                        gain = after
                        // Reference targets see global writes only through their own channel's turn.
                        let laterGlobal: Bool
                        if case .gxxSetGlobalVolume = write.command {
                            laterGlobal = write.scheduledFrame == frame && write.channelIndex > channel
                        } else { laterGlobal = false }
                        if !laterGlobal { visibleGain = gain }
                    }
                    if let after = write.panAfter, write.panBefore != after { pan = after }
                    if write.scheduledFrame == frame {
                        switch write.command {
                        case .ecxNoteCut: quickVolume = true; noteCut = true
                        case .cxxSetVolume, .keyOffWithoutEnvelope, .volumeColumn(.setVolume): quickVolume = true
                        case .instrumentDefaultVolume where write.cellNote == 0: quickVolume = true
                        default: break
                        }
                    }
                    writeIndex += 1
                }
                let audiblePan = event.panEnvelope == nil ? pan : Self.envelopePan(
                    staticPan: pan, channelPanning: channelPanning, value: state.panValue)
                if event.volumeEnvelope == nil && !observedActivation && firstSemanticIndex < semanticIndex {
                    // Observe only original semantic records, never added birth/write
                    // contexts. The first legacy activation reserves every later slot,
                    // including equal/zero targets that sparse G05 output now prunes.
                    for ordinal in firstSemanticIndex..<semanticIndex {
                        let semantic = history[ordinal]
                        let first = ordinal == firstSemanticIndex
                        let observedGain = first ? visibleGain : gain
                        let priorGain = first ? observedPriorGain : gain
                        let priorPan = first ? observedPriorPan : pan
                        let observedPan = ordinal == semanticIndex - 1 || event.panEnvelope == nil ? audiblePan :
                            Self.envelopePan(staticPan: pan, channelPanning: semantic.channelPanningValue,
                                value: semantic.state.panValue)
                        let changedReset = resetFrames.contains(semantic.scheduledFrame) &&
                            (observedGain != priorGain || pan != priorPan)
                        // Equal-frame records consumed writes only on their first turn.
                        if !semantic.state.keyOn || changedReset || (first && noteCut) || observedPan != pan {
                            preexistingCount += history.count - ordinal
                            observedActivation = true
                            break
                        }
                    }
                    observedPriorGain = gain; observedPriorPan = pan
                }
                guard emitsOutput else { initial = false; continue }
                let amplitude = visibleGain * state.volumeValue * state.fadeoutValue
                // C deduplicates dense envelope targets. Formerly plain sources also
                // prune equal tuples here, avoiding new per-tick runtime event storage.
                if !initial && !retainsTickPublications && amplitude == lastAmplitude &&
                    (amplitude == 0 || audiblePan == lastPan) { continue }
                let reset = !initial && resetFrames.contains(frame)
                let duration = initial ? 0 : reset || noteCut ? max(1, Int((plan.timingConfig.sampleRate * 0.005).rounded(.down))) :
                    max(1, Int((plan.timingConfig.sampleRate * (quickVolume ? 0.005 : 2.5 / Double(bpm))).rounded(.down)))
                all.append(PlaybackXMAudibleUpdate(eventIndex: index, channelIndex: channel,
                    source: source, tick: tick, scheduledFrame: frame, bpm: bpm, speed: speed,
                    amplitude: amplitude, pan: audiblePan, durationFrames: duration,
                    intent: initial ? "initial" : reset ? "nonretriggering_reset" :
                        (quickVolume ? "quick_volume" : "ordinary_tick"), rebaseFromCurrent: reset))
                lastAmplitude = amplitude; lastPan = audiblePan
                initial = false
            }
        }
        updates = all.sorted { $0.scheduledFrame == $1.scheduledFrame ? $0.eventIndex < $1.eventIndex : $0.scheduledFrame < $1.scheduledFrame }
        updatesByEvent = Dictionary(grouping: updates, by: \.eventIndex)
        planningHistoryDiagnostics = work
        preexistingPublicationCount = preexistingCount
    }

    /// Applies the observed byte-domain envelope displacement while retaining the static conversion baseline.
    private static func envelopePan(staticPan: Float, channelPanning: Double, value: Float) -> Float {
        let channel = min(255, max(0, Int(channelPanning.rounded())))
        let envelope = min(63, max(0, Double(value) * 64))
        let displacement = Int(((envelope - 32) * Double(min(channel, 256 - channel)) / 32).rounded(.down))
        guard displacement != 0 else { return staticPan }
        // Header/8xx conversions and profile laws remain G40. Apply only the envelope's
        // change in the existing byte conversion, preserving the exact neutral baseline.
        let offset = PlaybackSamplePanningPolicy.plannedPan(channel + displacement) -
            PlaybackSamplePanningPolicy.plannedPan(channel)
        return min(1, max(-1, staticPan + offset))
    }

    /// Folds only prior publications through the same pure C state operations used while rendering.
    func state(eventIndex: Int, before frame: Int, config: MixerRenderConfig,
               replacementFrame: Int? = nil) -> MixerAudibleOutputState? {
        guard let history = updatesByEvent[eventIndex] else { return nil }
        var output = MixerAudibleOutputState()
        var cursor = 0
        // Same-frame publications are delivered before C's scheduled retirement;
        // subsequent old-generation publications are rejected by the retiring voice.
        for update in history where update.scheduledFrame < frame && update.scheduledFrame <= (replacementFrame ?? frame) {
            output.advance(update.scheduledFrame - cursor)
            output.publish(update, config: config)
            cursor = update.scheduledFrame
        }
        guard output.enabled else { return nil }
        if let replacementFrame, replacementFrame < frame {
            output.advance(replacementFrame - cursor)
            output.retireSong(sampleRate: config.sampleRate)
            cursor = replacementFrame
        }
        output.advance(frame - cursor)
        return output
    }
}
