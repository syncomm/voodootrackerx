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

    init(plan: PlaybackSongSyntheticPlan) {
        var all = [PlaybackXMAudibleUpdate]()
        let changes = Dictionary(grouping: plan.diagnostics.voiceStateUpdates.filter(\.activeVoiceUpdated),
            by: { $0.activeEventIndex ?? -1 })
        var work = PlaybackXMHistoryLookupDiagnostics()
        work.indexBuildCount = 1
        work.entriesIndexed = changes.values.reduce(0) { $0 + $1.count }
        let resets = Dictionary(grouping: PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan), by: \.activeEventIndex)
        for (index, history) in plan.xmEnvelopeTimeline?.updatesByEvent ?? [:] {
            guard plan.pattern.events.indices.contains(index), !history.isEmpty else { continue }
            let event = plan.pattern.events[index]
            // Seed reconstruction retains source order; tick target consumption uses frame order.
            let sourceWrites = changes[index] ?? []
            let writes = sourceWrites.enumerated().sorted {
                $0.element.scheduledFrame == $1.element.scheduledFrame ? $0.offset < $1.offset :
                    $0.element.scheduledFrame < $1.element.scheduledFrame
            }.map(\.element)
            let resetFrames = Set((resets[index] ?? []).compactMap { update -> Int? in
                if case .reset = update.change { return update.scheduledFrame }; return nil
            })
            // A neutral pan clock alone must not change audible behavior.
            guard event.volumeEnvelope != nil || history.contains(where: { !$0.state.keyOn }) || !resetFrames.isEmpty else { continue }
            var gain = event.gain
            var pan = event.pan
            var writeIndex = 0
            var managesOutput = event.volumeEnvelope != nil
            for (offset, semantic) in history.enumerated() {
                let frame = semantic.scheduledFrame
                let priorGain = gain, priorPan = pan
                var visibleGain = gain
                var quickVolume = false
                while writeIndex < writes.count && writes[writeIndex].scheduledFrame <= frame {
                    let write = writes[writeIndex]
                    if let after = write.gainAfter, write.gainBefore != after {
                        gain = after
                        // Reference targets see global writes only through their own channel's turn.
                        let laterGlobal: Bool
                        if case .gxxSetGlobalVolume = write.command {
                            laterGlobal = write.scheduledFrame == frame && write.channelIndex > semantic.channelIndex
                        } else { laterGlobal = false }
                        if !laterGlobal { visibleGain = gain }
                    }
                    if let after = write.panAfter, write.panBefore != after { pan = after }
                    if write.scheduledFrame == frame {
                        switch write.command {
                        case .cxxSetVolume, .keyOffWithoutEnvelope, .volumeColumn(.setVolume): quickVolume = true
                        case .instrumentDefaultVolume where write.cellNote == 0: quickVolume = true
                        default: break
                        }
                    }
                    writeIndex += 1
                }
                var activation: MixerAudibleOutputSeed?
                if !managesOutput {
                    // A future release/reset must never change the earlier generic gain/pan audio.
                    // A neutral reset must also leave an unfinished generic ramp untouched.
                    let changedReset = resetFrames.contains(frame) && (visibleGain != priorGain || pan != priorPan)
                    guard !semantic.state.keyOn || changedReset else { continue }
                    managesOutput = true
                    if offset > 0 {
                        work.lookupCount += 1
                        work.entriesVisited += sourceWrites.count
                        activation = PlaybackSongOfflineRenderer.audibleActivationSeed(
                            for: event, eventIndex: index, voiceStateUpdates: sourceWrites, before: frame)
                    }
                }
                let initial = offset == 0
                let reset = !initial && resetFrames.contains(frame)
                let duration = initial ? 0 : reset ? Int((plan.timingConfig.sampleRate * 0.005).rounded(.down)) :
                    max(1, Int((plan.timingConfig.sampleRate * (quickVolume ? 0.005 : 2.5 / Double(semantic.bpm))).rounded(.down)))
                all.append(PlaybackXMAudibleUpdate(eventIndex: index, channelIndex: semantic.channelIndex,
                    source: semantic.source, tick: semantic.tick, scheduledFrame: frame,
                    bpm: semantic.bpm, speed: semantic.speed,
                    amplitude: visibleGain * semantic.state.volumeValue * semantic.state.fadeoutValue,
                    pan: pan, durationFrames: duration,
                    intent: initial ? "initial" : reset ? "nonretriggering_reset" :
                        (quickVolume ? "quick_volume" : "ordinary_tick"), activation: activation,
                    rebaseFromCurrent: reset))
            }
        }
        updates = all.sorted { $0.scheduledFrame == $1.scheduledFrame ? $0.eventIndex < $1.eventIndex : $0.scheduledFrame < $1.scheduledFrame }
        updatesByEvent = Dictionary(grouping: updates, by: \.eventIndex)
        planningHistoryDiagnostics = work
    }

    /// Folds only prior publications through the same pure C state operations used while rendering.
    func state(eventIndex: Int, before frame: Int, config: MixerRenderConfig,
               replacementFrame: Int? = nil) -> MixerAudibleOutputState? {
        guard let history = updatesByEvent[eventIndex] else { return nil }
        var output = MixerAudibleOutputState()
        var cursor = 0
        for update in history where update.scheduledFrame < frame {
            output.advance(update.scheduledFrame - cursor)
            output.publish(update, config: config)
            cursor = update.scheduledFrame
        }
        guard output.enabled else { return nil }
        if let replacementFrame, replacementFrame < frame {
            output.advance(replacementFrame - cursor)
            output.retire(frames: CSoftwareMixer.replacementStopRampFrameCount)
            cursor = replacementFrame
        }
        output.advance(frame - cursor)
        return output
    }
}
