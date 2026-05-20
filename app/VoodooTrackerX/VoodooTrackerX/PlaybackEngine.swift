import Foundation
import os

@MainActor
final class PlaybackEngine: PlaybackTransport {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Playback")
    private let audioEngine: PlaybackAudioOutput
    private let traceWriter: PlaybackTraceWriting
    private let runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting

    private(set) var state: PlaybackState = .stopped
    private(set) var song: PlaybackSong?
    private(set) var currentPosition: PlaybackPosition?
    private(set) var timing = PlaybackTiming.xmDefault
    private var tickState = PlaybackTickState()
    private var timer: Timer?
    private var pendingPositionCommand: PlaybackPositionCommand?
    private var channelStates = [Int: PlaybackChannelState]()
    private var globalState = PlaybackGlobalState()
    private var rowDelayDurationsRemaining = 0
    private var lastVoiceRequests = [Int: AudioVoiceRequest]()
    private var delayedVoiceRequests = [Int: AudioVoiceRequest]()
    private var traceTickIndex: UInt64 = 0
    private var runtimeNoteTriggerEventCount: UInt64 = 0
    private var activeDebugStartTraceContext: PlaybackDebugStartTraceContext?

    var positionDidChange: ((PlaybackPosition) -> Void)?
    var playbackDidStop: (() -> Void)?

    init(
        audioEngine: PlaybackAudioOutput? = nil,
        traceWriter: PlaybackTraceWriting = PlaybackTraceConfiguration.makeWriter(),
        runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting = RuntimeCMixerTraceConfiguration.makeWriter()
    ) {
        self.runtimeCMixerTraceWriter = runtimeCMixerTraceWriter
        self.audioEngine = audioEngine ?? PlaybackAudioOutputFactory.make(runtimeCMixerTraceWriter: runtimeCMixerTraceWriter)
        self.traceWriter = traceWriter
    }

    func load(song: PlaybackSong?) {
        let wasPlaying = state.isPlaying
        stop(notify: false, resetAudio: true)
        self.song = song
        timing = song?.initialTiming ?? .xmDefault
        currentPosition = song?.startPosition
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        traceTickIndex = 0
        runtimeNoteTriggerEventCount = 0
        activeDebugStartTraceContext = nil
        configureRuntimeAdapterEventPlan(for: song)
        logger.debug("Playback song loaded. hadActivePlayback=\(wasPlaying, privacy: .public) hasSong=\((song != nil), privacy: .public)")
    }

    func configureTiming(_ timing: PlaybackTiming) {
        self.timing = timing
        if state.isPlaying {
            restartTimer()
        }
    }

    func play(from context: PlaybackStartContext?) {
        play(from: context, debugStart: nil)
    }

    func play(from context: PlaybackStartContext?, debugStart: PlaybackDebugStartRequest?) {
        guard !state.isPlaying else {
            logger.debug("Ignoring play request because playback is already active")
            return
        }
        guard let song else {
            stop()
            return
        }
        let resolvedDebugStart = debugStart.flatMap { resolveDebugStart($0, in: song) }
        currentPosition = resolvedDebugStart?.position ?? playbackStartPosition(from: context, in: song) ?? song.startPosition
        resetRuntimeState(resetTiming: resolvedDebugStart != nil)
        activeDebugStartTraceContext = resolvedDebugStart.map {
            PlaybackDebugStartTraceContext(request: $0.request, position: $0.position, actualTickInRow: $0.actualTickInRow)
        }
        if let currentPosition {
            enter(position: currentPosition)
            applyDebugStartTickIfNeeded(resolvedDebugStart?.actualTickInRow, at: currentPosition)
        }
        restartTimer()
        apply(action: .play, nextState: PlaybackState(mode: .playing, context: context))
    }

    @discardableResult
    func seek(to request: PlaybackDebugStartRequest, autoplay: Bool? = nil) -> PlaybackPosition? {
        guard let song,
              let resolvedStart = resolveDebugStart(request, in: song) else {
            return nil
        }
        let shouldPlay = autoplay ?? state.isPlaying
        timer?.invalidate()
        timer = nil
        stopAllAudio(context: runtimeTraceContext(at: currentPosition, tickInRow: tickState.tickInRow, channelIndex: nil), reason: "debug_seek")
        currentPosition = resolvedStart.position
        resetRuntimeState(resetTiming: true)
        activeDebugStartTraceContext = shouldPlay
            ? PlaybackDebugStartTraceContext(
                request: resolvedStart.request,
                position: resolvedStart.position,
                actualTickInRow: resolvedStart.actualTickInRow
            )
            : nil

        if shouldPlay {
            enter(position: resolvedStart.position)
            applyDebugStartTickIfNeeded(resolvedStart.actualTickInRow, at: resolvedStart.position)
            restartTimer()
            apply(action: .play, nextState: PlaybackState(mode: .playing, context: state.context))
        } else {
            positionDidChange?(resolvedStart.position)
            apply(action: .stop, nextState: .stopped)
        }
        return resolvedStart.position
    }

    func stop() {
        stop(notify: true, resetAudio: false)
    }

    private func stop(notify: Bool, resetAudio: Bool) {
        let wasActive = state.mode != .stopped || timer != nil
        guard wasActive || resetAudio else {
            logger.debug("Ignoring stop request because playback is already stopped")
            return
        }
        timer?.invalidate()
        timer = nil
        tickState.reset()
        if resetAudio {
            audioEngine.reset()
        } else {
            stopAllAudio(context: runtimeTraceContext(at: currentPosition, tickInRow: tickState.tickInRow, channelIndex: nil), reason: "transport_stop")
        }
        currentPosition = song?.startPosition
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        timing = song?.initialTiming ?? .xmDefault
        activeDebugStartTraceContext = nil
        traceWriter.flush()
        runtimeCMixerTraceWriter.flush()
        apply(action: .stop, nextState: .stopped)
        if notify, wasActive {
            playbackDidStop?()
        }
    }

    func pause() {
        guard state.mode == .playing else {
            return
        }
        timer?.invalidate()
        timer = nil
        stopAllAudio(context: runtimeTraceContext(at: currentPosition, tickInRow: tickState.tickInRow, channelIndex: nil), reason: "transport_pause")
        apply(action: .pause, nextState: PlaybackState(mode: .paused, context: state.context))
    }

    func togglePlayPause(from context: PlaybackStartContext?) {
        switch state.mode {
        case .playing:
            pause()
        case .paused, .stopped:
            play(from: context ?? state.context)
        }
    }

    private func apply(action: PlaybackTransportAction, nextState: PlaybackState) {
        state = nextState
        logger.debug("Playback transport action: \(String(describing: action), privacy: .public)")
    }

    private func resetRuntimeState(resetTiming: Bool) {
        tickState.reset()
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        traceTickIndex = 0
        runtimeNoteTriggerEventCount = 0
        if resetTiming {
            timing = song?.initialTiming ?? .xmDefault
        }
        activeDebugStartTraceContext = nil
        (audioEngine as? RuntimeCMixerAdapterEventConsuming)?.resetRuntimeAdapterEventConsumption()
    }

    private var usesRuntimeAdapterEventPlan: Bool {
        (audioEngine as? RuntimeCMixerAdapterEventConsuming)?.hasRuntimeAdapterEventPlan == true
    }

    private func configureRuntimeAdapterEventPlan(for song: PlaybackSong?) {
        guard let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming else {
            return
        }
        adapterConsumer.configureRuntimeAdapterEventPlan(RuntimeCMixerAdapterEventPlan.make(
            song: song,
            sampleRate: audioEngine.audioBufferSampleRate
        ))
    }

    private func consumeRuntimeAdapterEvents(at position: PlaybackPosition, tickInRow: Int) {
        guard let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming else {
            return
        }
        adapterConsumer.consumeRuntimeAdapterEvents(context: runtimeTraceContext(
            at: position,
            tickInRow: tickInRow,
            channelIndex: nil
        ))
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: timing.tickDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOneTick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func advanceOneTick() {
        guard state.isPlaying,
              let song,
              let position = currentPosition else {
            return
        }
        traceTickIndex += 1
        guard tickState.advance(timing: timing) else {
            applyTickEffects(tickInRow: tickState.tickInRow, position: position)
            return
        }
        guard rowDelayDurationsRemaining <= 0 else {
            rowDelayDurationsRemaining -= 1
            return
        }
        switch nextStep(after: position, in: song) {
        case let .advanced(nextPosition):
            currentPosition = nextPosition
            enter(position: nextPosition)
        case let .ended(restartPosition):
            if let restartPosition {
                currentPosition = restartPosition
                positionDidChange?(restartPosition)
            }
            logger.debug("Playback reached end of song; stopping cleanly")
            stop()
        }
    }

    private func enter(position: PlaybackPosition) {
        positionDidChange?(position)
        traceRowTiming(at: position, reason: "row_timing_before_effects")
        recordRuntimeRowTransition(at: position)
        let usesAdapterPlan = usesRuntimeAdapterEventPlan
        prepareRowPlaybackState(at: position, emitRuntimeControlUpdates: !usesAdapterPlan)
        if usesAdapterPlan {
            consumeRuntimeAdapterEvents(at: position, tickInRow: 0)
        } else {
            triggerAudio(at: position)
            applyImmediateTimingEffects()
        }
    }

    private func applyDebugStartTickIfNeeded(_ requestedTickInRow: Int?, at position: PlaybackPosition) {
        guard let requestedTickInRow,
              requestedTickInRow > 0 else {
            return
        }
        let actualTickInRow = min(requestedTickInRow, max(0, timing.ticksPerRow - 1))
        guard actualTickInRow > 0 else {
            return
        }
        for tick in 1...actualTickInRow {
            traceTickIndex += 1
            applyTickEffects(tickInRow: tick, position: position)
        }
        tickState.setTickInRow(actualTickInRow, timing: timing)
    }

    private func nextStep(after position: PlaybackPosition, in song: PlaybackSong) -> PlaybackStepResult {
        guard let pendingPositionCommand else {
            return song.position(after: position)
        }
        self.pendingPositionCommand = nil
        switch pendingPositionCommand {
        case let .positionJump(orderIndex):
            guard song.orders.indices.contains(orderIndex) else {
                logger.debug("Ignoring out-of-bounds position jump: \(orderIndex, privacy: .public)")
                return song.position(after: position)
            }
            return song.position(orderIndex: orderIndex, rowIndex: 0).map(PlaybackStepResult.advanced) ?? .ended(restartPosition: nil)
        case let .patternBreak(rowIndex):
            let nextOrderIndex = position.orderIndex + 1
            guard song.orders.indices.contains(nextOrderIndex) else {
                return .ended(restartPosition: nil)
            }
            return song.position(orderIndex: nextOrderIndex, rowIndex: rowIndex).map(PlaybackStepResult.advanced) ?? .ended(restartPosition: nil)
        }
    }

    private func prepareRowPlaybackState(at position: PlaybackPosition, emitRuntimeControlUpdates: Bool = true) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        globalState.beginRow()
        rowDelayDurationsRemaining = 0
        for (channelIndex, cell) in row.cells.enumerated() {
            var channelState = state(forChannel: channelIndex)
            let volumeColumnCommand = PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn)
            channelState.beginRow()
            if cell.note == 97 {
                channelState.noteOff()
            } else if PlaybackEffectHandler.isTonePortamentoEffect(cell.effectType) || isVolumeColumnTonePortamento(volumeColumnCommand) {
                channelState.setTonePortamentoTarget(note: cell.note)
            } else {
                let volumeEnvelope = song.instrument(forInstrument: Int(cell.instrument))?.volumeEnvelope ?? .disabled
                channelState.start(note: cell.note, volumeEnvelope: volumeEnvelope)
            }

            _ = channelState.apply(volumeColumnCommand: volumeColumnCommand)

            if let command = PlaybackEffectHandler.command(effectType: cell.effectType, effectParam: cell.effectParam) {
                apply(command, channelIndex: channelIndex, channelState: &channelState)
            } else if cell.effectType == 0x11 {
                if !globalState.applyVolumeSlide(effectParam: cell.effectParam) {
                    logUnsupportedEffectIfNeeded(cell)
                }
            } else if !channelState.apply(effectType: cell.effectType, effectParam: cell.effectParam) {
                logUnsupportedEffectIfNeeded(cell)
            }

            channelStates[channelIndex] = channelState
        }
        if emitRuntimeControlUpdates {
            updateActiveChannelControls()
        }
    }

    private func isVolumeColumnTonePortamento(_ command: PlaybackVolumeColumnCommand) -> Bool {
        if case .tonePortamento = command {
            return true
        }
        return false
    }

    private func apply(_ command: PlaybackEffectCommand, channelIndex: Int, channelState: inout PlaybackChannelState) {
        switch command {
        case let .setSpeed(speed):
            configureTiming(PlaybackTiming(speed: speed, bpm: timing.bpm))
        case let .setBPM(bpm):
            configureTiming(PlaybackTiming(speed: timing.speed, bpm: bpm))
        case let .positionJump(orderIndex):
            pendingPositionCommand = .positionJump(orderIndex: orderIndex)
        case let .patternBreak(rowIndex):
            pendingPositionCommand = .patternBreak(rowIndex: rowIndex)
        case let .setVolume(volume):
            channelState.volume = volume
        case let .setPanning(panning):
            channelState.panning = PlaybackEffectHandler.clampedPanning(panning)
        case let .setGlobalVolume(volume):
            globalState.setVolume(volume)
        case let .patternDelay(rowDurations):
            rowDelayDurationsRemaining = max(rowDelayDurationsRemaining, rowDurations)
        }
    }

    private func applyTickEffects(tickInRow: Int, position: PlaybackPosition) {
        if usesRuntimeAdapterEventPlan {
            consumeRuntimeAdapterEvents(at: position, tickInRow: tickInRow)
            return
        }
        let oldGlobalVolume = globalState.volume
        globalState.advanceContinuousEffects()
        for channelIndex in channelStates.keys.sorted() {
            guard var channelState = channelStates[channelIndex] else {
                continue
            }
            if channelState.activeEffect != nil {
                channelState.advanceContinuousEffect(tickInRow: tickInRow)
            }
            channelState.advanceEnvelopeTick()
            channelStates[channelIndex] = channelState
            updateAudioChannel(
                channelIndex,
                controls: effectiveControls(for: channelState),
                context: runtimeTraceContext(at: position, tickInRow: tickInRow, channelIndex: channelIndex, channelState: channelState)
            )
            traceChannelEvent(
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .updated,
                reason: "tick_controls_updated"
            )
            if channelState.volumeEnvelopeState.isFullyFadedOut {
                stopAudioChannel(
                    channelIndex,
                    context: runtimeTraceContext(at: position, tickInRow: tickInRow, channelIndex: channelIndex, channelState: channelState),
                    reason: "envelope_fadeout_completed"
                )
                channelStates.removeValue(forKey: channelIndex)
                continue
            }
            applyTimingEffects(channelIndex: channelIndex, channelState: channelState, tickInRow: tickInRow, position: position)
        }
        if oldGlobalVolume != globalState.volume, channelStates.isEmpty {
            logger.debug("Applied global volume slide without active channels")
        }
    }

    private func applyImmediateTimingEffects() {
        for channelIndex in channelStates.keys.sorted() {
            guard let channelState = channelStates[channelIndex],
                  channelState.noteCutTick == 0 else {
                continue
            }
            stopAudioChannel(
                channelIndex,
                context: runtimeTraceContext(at: currentPosition, tickInRow: 0, channelIndex: channelIndex, channelState: channelState),
                reason: "note_cut_tick_0"
            )
            traceChannelEvent(
                at: currentPosition,
                tickInRow: 0,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .cut,
                reason: "note_cut_tick_0"
            )
        }
    }

    private func applyTimingEffects(channelIndex: Int, channelState: PlaybackChannelState, tickInRow: Int, position: PlaybackPosition) {
        if channelState.noteCutTick == tickInRow {
            stopAudioChannel(
                channelIndex,
                context: runtimeTraceContext(at: position, tickInRow: tickInRow, channelIndex: channelIndex, channelState: channelState),
                reason: "note_cut"
            )
            traceChannelEvent(
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .cut,
                reason: "note_cut"
            )
        }
        if let delayedRequest = delayedVoiceRequests[channelIndex],
           channelState.noteDelayTick == tickInRow {
            traceRequest(
                delayedRequest,
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .triggered,
                reason: "delayed_note_triggered"
            )
            trigger(
                delayedRequest,
                channelIndex: channelIndex,
                context: runtimeTraceContext(
                    at: position,
                    tickInRow: tickInRow,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    request: delayedRequest
                )
            )
            delayedVoiceRequests[channelIndex] = nil
        }
        if let interval = channelState.retriggerInterval,
           interval > 0,
           tickInRow.isMultiple(of: interval),
           let request = lastVoiceRequests[channelIndex] {
            traceRequest(
                request,
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .retriggered,
                reason: "retrigger_interval"
            )
            trigger(
                request,
                channelIndex: channelIndex,
                context: runtimeTraceContext(
                    at: position,
                    tickInRow: tickInRow,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    request: request
                )
            )
        }
    }

    private func logUnsupportedEffectIfNeeded(_ cell: PlaybackCell) {
        guard cell.effectType != 0 || cell.effectParam != 0 else {
            return
        }
        logger.debug("Deferred XM effect \(cell.effectType, privacy: .public) param \(cell.effectParam, privacy: .public)")
    }

    private func triggerAudio(at position: PlaybackPosition) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        for (channelIndex, cell) in row.cells.enumerated() {
            let channelState = state(forChannel: channelIndex)
            guard cell.note > 0 else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "no_note"
                )
                continue
            }
            guard cell.note != 97 else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .updated,
                    reason: "key_off"
                )
                recordRuntimeEngineAction(
                    action: "key_off",
                    context: runtimeTraceContext(at: position, tickInRow: 0, channelIndex: channelIndex, channelState: channelState),
                    targetScope: "channel",
                    targetedAllVoices: false,
                    reason: "key_off"
                )
                continue
            }
            guard cell.note <= 96 else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "invalid_note"
                )
                continue
            }
            guard let sample = song.sample(forInstrument: Int(cell.instrument)) else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "missing_sample"
                )
                continue
            }
            let controls = effectiveControls(for: channelState)
            let request = AudioVoiceRequest(
                sample: sample,
                note: cell.note,
                channel: channelIndex,
                volumeScale: controls.volumeScale,
                pitchOffsetSemitones: controls.pitchOffsetSemitones,
                panning: controls.panning,
                sampleStartOffset: channelState.sampleStartOffset
            )
            if let delayTick = channelState.noteDelayTick,
               delayTick > 0 {
                if delayTick < timing.ticksPerRow {
                    delayedVoiceRequests[channelIndex] = request
                    traceRequest(
                        request,
                        at: position,
                        tickInRow: 0,
                        channelIndex: channelIndex,
                        channelState: channelState,
                        decision: .delayed,
                        reason: "note_delay"
                    )
                } else {
                    traceRequest(
                        request,
                        at: position,
                        tickInRow: 0,
                        channelIndex: channelIndex,
                        channelState: channelState,
                        decision: .ignored,
                        reason: "note_delay_exceeds_row_speed"
                    )
                }
                continue
            }
            guard channelState.suppressesNoteTrigger != true else {
                traceRequest(
                    request,
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "note_trigger_suppressed"
                )
                continue
            }
            traceRequest(
                request,
                at: position,
                tickInRow: 0,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .triggered,
                reason: "row_note"
            )
            trigger(
                request,
                channelIndex: channelIndex,
                context: runtimeTraceContext(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    request: request
                )
            )
        }
    }

    private func trigger(_ request: AudioVoiceRequest, channelIndex: Int, context: AudioRuntimeTraceContext?) {
        recordRuntimeEngineAction(
            action: "note_trigger",
            context: context,
            targetScope: "channel",
            targetedAllVoices: false,
            reason: "playback_engine_note_trigger"
        )
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.trigger(request, context: context)
        } else {
            audioEngine.trigger(request)
        }
        lastVoiceRequests[channelIndex] = request
    }

    private func updateActiveChannelControls() {
        for channelIndex in channelStates.keys.sorted() {
            guard let channelState = channelStates[channelIndex] else {
                continue
            }
            updateAudioChannel(
                channelIndex,
                controls: effectiveControls(for: channelState),
                context: runtimeTraceContext(at: currentPosition, tickInRow: tickState.tickInRow, channelIndex: channelIndex, channelState: channelState)
            )
        }
    }

    private func updateAudioChannel(_ channelIndex: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?) {
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.update(channel: channelIndex, controls: controls, context: context)
        } else {
            audioEngine.update(channel: channelIndex, controls: controls)
        }
    }

    private func stopAudioChannel(_ channelIndex: Int, context: AudioRuntimeTraceContext?, reason: String) {
        recordRuntimeEngineAction(
            action: "channel_stop",
            context: context,
            targetScope: "channel",
            targetedAllVoices: false,
            reason: reason
        )
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.stop(channel: channelIndex, context: context)
        } else {
            audioEngine.stop(channel: channelIndex)
        }
    }

    private func stopAllAudio(context: AudioRuntimeTraceContext?, reason: String) {
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.stopAll(context: context, reason: reason)
        } else {
            audioEngine.stopAll()
        }
    }

    private func recordRuntimeEngineAction(
        action: String,
        context: AudioRuntimeTraceContext?,
        targetScope: String,
        targetedAllVoices: Bool,
        reason: String
    ) {
        guard runtimeCMixerTraceWriter.isEnabled else {
            return
        }
        let noteTriggerEventCount: UInt64?
        if action == "note_trigger" {
            runtimeNoteTriggerEventCount &+= 1
            noteTriggerEventCount = runtimeNoteTriggerEventCount
        } else {
            noteTriggerEventCount = nil
        }
        let backend = (audioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend ?? .avAudio
        runtimeCMixerTraceWriter.record(RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: backend.diagnosticName,
            experimentalCMixerEnabled: backend == .cMixer,
            sampleRate: audioEngine.audioBufferSampleRate,
            context: context,
            targetScope: targetScope,
            targetedAllVoices: targetedAllVoices,
            noteTriggerEventCount: noteTriggerEventCount,
            cMixerCallSucceeded: nil,
            reason: reason
        ))
    }

    private func recordRuntimeRowTransition(at position: PlaybackPosition) {
        guard let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput else {
            return
        }
        diagnosticOutput.recordTransition(
            context: runtimeTraceContext(
                at: position,
                tickInRow: tickState.tickInRow,
                channelIndex: nil
            ),
            reason: "playback_engine_row_enter"
        )
    }

    private func effectiveControls(for channelState: PlaybackChannelState) -> AudioChannelControls {
        var controls = channelState.audioControls
        controls.volumeScale = PlaybackVolumeCalculator.clamped(controls.volumeScale * globalState.volume)
        return controls
    }

    private func runtimeTraceContext(
        at position: PlaybackPosition?,
        tickInRow: Int,
        channelIndex: Int?,
        channelState: PlaybackChannelState? = nil,
        request: AudioVoiceRequest? = nil
    ) -> AudioRuntimeTraceContext? {
        guard let position else {
            return nil
        }
        let traceCell: PlaybackCell?
        if let channelIndex {
            traceCell = cell(at: position, channelIndex: channelIndex)
        } else {
            traceCell = nil
        }
        let noteValue: UInt8?
        if let note = traceCell?.note, note > 0 {
            noteValue = note
        } else if let request {
            noteValue = request.note
        } else {
            noteValue = channelState?.baseNote
        }
        let instrumentIndex: Int?
        if let instrument = traceCell?.instrument, instrument > 0 {
            instrumentIndex = Int(instrument)
        } else {
            instrumentIndex = request?.sample.instrumentIndex
        }
        return AudioRuntimeTraceContext(
            orderIndex: position.orderIndex,
            patternIndex: position.patternIndex,
            rowIndex: position.rowIndex,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            noteValue: noteValue,
            instrumentIndex: instrumentIndex,
            effectType: traceCell?.effectType,
            effectParam: traceCell?.effectParam,
            volumeColumn: traceCell?.volumeColumn,
            speed: timing.speed,
            bpm: timing.bpm,
            tickIndex: traceTickIndex
        )
    }

    private func state(forChannel channelIndex: Int) -> PlaybackChannelState {
        channelStates[channelIndex] ?? PlaybackChannelState.defaultState(forChannel: channelIndex)
    }

    private func playbackStartPosition(from context: PlaybackStartContext?, in song: PlaybackSong) -> PlaybackPosition? {
        guard let context else {
            return song.startPosition
        }
        if let contextPosition = song.position(orderIndex: context.songPosition, rowIndex: context.row),
           contextPosition.patternIndex == context.patternIndex {
            return contextPosition
        }
        for order in song.orders where order.patternIndex == context.patternIndex {
            return song.position(orderIndex: order.orderIndex, rowIndex: context.row)
        }
        return song.startPosition
    }

    private func resolveDebugStart(_ request: PlaybackDebugStartRequest, in song: PlaybackSong) -> PlaybackResolvedDebugStart? {
        let position: PlaybackPosition?
        if let orderIndex = request.requestedOrderIndex {
            position = song.position(orderIndex: orderIndex, rowIndex: request.requestedRowIndex)
        } else if let patternIndex = request.requestedPatternIndex {
            position = song.position(patternIndex: patternIndex, rowIndex: request.requestedRowIndex)
        } else {
            position = song.position(orderIndex: 0, rowIndex: request.requestedRowIndex)
        }
        guard let position else {
            logger.debug("Ignoring debug seek because no matching playback position was found")
            return nil
        }
        let actualTickInRow = request.requestedTickInRow.map { min($0, max(0, song.initialTiming.ticksPerRow - 1)) }
        return PlaybackResolvedDebugStart(request: request, position: position, actualTickInRow: actualTickInRow)
    }

    private func traceChannelEvent(
        at position: PlaybackPosition?,
        tickInRow: Int,
        channelIndex: Int,
        channelState: PlaybackChannelState,
        decision: PlaybackTraceDecision,
        reason: String
    ) {
        guard traceWriter.isEnabled,
              let position else {
            return
        }
        let cell = cell(at: position, channelIndex: channelIndex)
        let request = lastVoiceRequests[channelIndex] ?? delayedVoiceRequests[channelIndex]
        let controls = effectiveControls(for: channelState)
        let noteValue = traceNoteValue(cell: cell, channelState: channelState, request: request)
        traceWriter.record(makeTraceEvent(
            position: position,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            cell: cell,
            noteValue: noteValue,
            instrumentIndex: traceInstrumentIndex(cell: cell, request: request),
            sampleIndex: request?.sample.sampleIndex,
            controls: controls,
            sample: request?.sample,
            sampleOffset: channelState.sampleStartOffset,
            channelState: channelState,
            decision: decision,
            reason: reason
        ))
    }

    private func traceRequest(
        _ request: AudioVoiceRequest,
        at position: PlaybackPosition,
        tickInRow: Int,
        channelIndex: Int,
        channelState: PlaybackChannelState,
        decision: PlaybackTraceDecision,
        reason: String
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        let cell = cell(at: position, channelIndex: channelIndex)
        traceWriter.record(makeTraceEvent(
            position: position,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            cell: cell,
            noteValue: request.note,
            instrumentIndex: request.sample.instrumentIndex,
            sampleIndex: request.sample.sampleIndex,
            controls: AudioChannelControls(
                volumeScale: request.volumeScale,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                panning: request.panning
            ),
            sample: request.sample,
            sampleOffset: request.sampleStartOffset,
            channelState: channelState,
            decision: decision,
            reason: reason
        ))
    }

    private func traceRowTiming(at position: PlaybackPosition, reason: String) {
        guard traceWriter.isEnabled else {
            return
        }
        traceWriter.record(makeTraceEvent(
            position: position,
            tickInRow: tickState.tickInRow,
            channelIndex: -1,
            cell: nil,
            noteValue: nil,
            instrumentIndex: nil,
            sampleIndex: nil,
            controls: AudioChannelControls(),
            sample: nil,
            sampleOffset: nil,
            channelState: nil,
            decision: .observed,
            reason: reason
        ))
    }

    private func makeTraceEvent(
        position: PlaybackPosition,
        tickInRow: Int,
        channelIndex: Int,
        cell: PlaybackCell?,
        noteValue: UInt8?,
        instrumentIndex: Int?,
        sampleIndex: Int?,
        controls: AudioChannelControls,
        sample: PlaybackSample?,
        sampleOffset: Int?,
        channelState: PlaybackChannelState?,
        decision: PlaybackTraceDecision,
        reason: String
    ) -> PlaybackTraceEvent {
        let computedRate = rateApproximation(
            note: noteValue,
            sample: sample,
            pitchOffsetSemitones: controls.pitchOffsetSemitones
        )
        let pitchCalculation = pitchCalculation(
            note: noteValue,
            sample: sample,
            pitchOffsetSemitones: controls.pitchOffsetSemitones
        )
        let loopRegion = sample?.loopRegion
        let debugTrace = activeDebugStartTraceContext
        return PlaybackTraceEvent(
            tickIndex: traceTickIndex,
            orderIndex: position.orderIndex,
            patternIndex: position.patternIndex,
            rowIndex: position.rowIndex,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            speed: timing.speed,
            bpm: timing.bpm,
            tickDuration: timing.tickDuration,
            rowDuration: timing.rowDuration,
            runtimeAudioBackend: (audioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend.diagnosticName,
            usesLinearFrequencyTable: song?.usesLinearFrequencyTable,
            startedFromDebugSeek: debugTrace != nil,
            requestedStartOrder: debugTrace?.requestedStartOrder,
            requestedStartPattern: debugTrace?.requestedStartPattern,
            requestedStartRow: debugTrace?.requestedStartRow,
            requestedStartTick: debugTrace?.requestedStartTick,
            actualStartOrder: debugTrace?.actualStartOrder,
            actualStartPattern: debugTrace?.actualStartPattern,
            actualStartRow: debugTrace?.actualStartRow,
            actualStartTick: debugTrace?.actualStartTick,
            noteValue: noteValue,
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            relativeNote: sample?.relativeNote,
            finetune: sample?.finetune,
            sourceSampleRate: sample?.baseSampleRate,
            audioBufferSampleRate: pitchCalculation?.audioBufferSampleRate,
            rawVolumeColumn: rawVolumeColumnString(for: cell),
            decodedVolumeColumnCommand: decodedVolumeColumnCommandString(for: cell),
            volumeColumnApplied: volumeColumnApplied(for: cell),
            volumeColumnVolume: volumeColumnVolume(for: cell),
            volumeColumnPanning: volumeColumnPanning(for: cell),
            effectCommand: effectCommandString(for: cell),
            effectParameter: effectParameterString(for: cell),
            effect: effectString(for: cell),
            computedVolume: controls.volumeScale,
            computedPanning: controls.panning,
            computedPitchSemitones: controls.pitchOffsetSemitones,
            targetFrequency: pitchCalculation?.targetFrequency,
            computedRate: computedRate,
            rateBasis: pitchCalculation?.rateBasis,
            computedFrequency: pitchCalculation?.frequency,
            computedVarispeedRate: pitchCalculation?.varispeedRate,
            computedPeriodApproximation: computedRate.map { 1.0 / max(0.000001, $0) },
            sampleOffset: sampleOffset,
            sampleLength: sample?.sampleLength,
            loopStart: sample?.loopStart,
            loopLength: sample?.loopLength,
            loopType: sample?.loopType,
            loopTypeName: loopRegion?.loopTypeName,
            loopEnabled: loopRegion?.isEnabled,
            loopStartFrame: loopRegion?.startFrame,
            loopEndFrame: loopRegion?.endFrame,
            loopLengthFrames: loopRegion?.lengthFrames,
            pingPongLoopApplied: loopRegion?.pingPongLoopApplied,
            envelopeEnabled: channelState?.volumeEnvelopeState.envelopeEnabled,
            envelopeTick: channelState?.volumeEnvelopeState.tick,
            envelopeValue: channelState?.volumeEnvelopeState.envelopeValue,
            envelopeSustainActive: channelState?.volumeEnvelopeState.sustainActive,
            envelopeLoopActive: channelState?.volumeEnvelopeState.loopActive,
            fadeoutValue: channelState?.volumeEnvelopeState.fadeoutValue,
            finalAppliedVolume: sample.map {
                PlaybackVolumeCalculator.finalAppliedVolume(sampleVolume: $0.volume, nodeVolumeScale: controls.volumeScale)
            },
            decision: decision,
            decisionReason: reason
        )
    }

    private func cell(at position: PlaybackPosition, channelIndex: Int) -> PlaybackCell? {
        guard let row = song?.row(at: position),
              row.cells.indices.contains(channelIndex) else {
            return nil
        }
        return row.cells[channelIndex]
    }

    private func traceNoteValue(cell: PlaybackCell?, channelState: PlaybackChannelState, request: AudioVoiceRequest?) -> UInt8? {
        if let note = cell?.note, note > 0 {
            return note
        }
        if let note = request?.note {
            return note
        }
        return channelState.baseNote
    }

    private func traceInstrumentIndex(cell: PlaybackCell?, request: AudioVoiceRequest?) -> Int? {
        if let instrument = cell?.instrument, instrument > 0 {
            return Int(instrument)
        }
        return request?.sample.instrumentIndex
    }

    private func rateApproximation(note: UInt8?, sample: PlaybackSample?, pitchOffsetSemitones: Double) -> Double? {
        let controlRate = pow(2.0, pitchOffsetSemitones / 12.0)
        guard let note,
              let sample else {
            return controlRate
        }
        return PlaybackPitchCalculator.calculation(
            note: note,
            sample: sample,
            pitchOffsetSemitones: pitchOffsetSemitones,
            outputSampleRate: audioEngine.audioBufferSampleRate
        ).playbackRate
    }

    private func pitchCalculation(note: UInt8?, sample: PlaybackSample?, pitchOffsetSemitones: Double) -> PlaybackPitchCalculation? {
        guard let note,
              let sample else {
            return nil
        }
        return PlaybackPitchCalculator.calculation(
            note: note,
            sample: sample,
            pitchOffsetSemitones: pitchOffsetSemitones,
            outputSampleRate: audioEngine.audioBufferSampleRate
        )
    }

    private func effectCommandString(for cell: PlaybackCell?) -> String {
        guard let cell else {
            return "00"
        }
        return String(format: "%02X", cell.effectType)
    }

    private func effectParameterString(for cell: PlaybackCell?) -> String {
        guard let cell else {
            return "00"
        }
        return String(format: "%02X", cell.effectParam)
    }

    private func effectString(for cell: PlaybackCell?) -> String {
        "\(effectCommandString(for: cell))\(effectParameterString(for: cell))"
    }

    private func rawVolumeColumnString(for cell: PlaybackCell?) -> String? {
        guard let cell else {
            return nil
        }
        return String(format: "%02X", cell.volumeColumn)
    }

    private func decodedVolumeColumnCommandString(for cell: PlaybackCell?) -> String? {
        guard let cell else {
            return nil
        }
        return PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn).traceName
    }

    private func volumeColumnApplied(for cell: PlaybackCell?) -> Bool? {
        guard let cell else {
            return nil
        }
        switch PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn) {
        case .none, .setVibratoSpeed, .vibrato:
            return false
        case let .volumeSlideDown(amount),
             let .volumeSlideUp(amount),
             let .fineVolumeSlideDown(amount),
             let .fineVolumeSlideUp(amount),
             let .panningSlideLeft(amount),
             let .panningSlideRight(amount),
             let .tonePortamento(amount):
            return amount > 0
        case .setVolume, .setPanning:
            return true
        }
    }

    private func volumeColumnVolume(for cell: PlaybackCell?) -> Int? {
        guard let cell else {
            return nil
        }
        return PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn).volumeValue
    }

    private func volumeColumnPanning(for cell: PlaybackCell?) -> Int? {
        guard let cell else {
            return nil
        }
        return PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn).panningValue
    }
}

private struct PlaybackResolvedDebugStart: Equatable {
    let request: PlaybackDebugStartRequest
    let position: PlaybackPosition
    let actualTickInRow: Int?
}

private struct PlaybackDebugStartTraceContext: Equatable {
    let requestedStartOrder: Int?
    let requestedStartPattern: Int?
    let requestedStartRow: Int
    let requestedStartTick: Int?
    let actualStartOrder: Int
    let actualStartPattern: Int
    let actualStartRow: Int
    let actualStartTick: Int?

    init(request: PlaybackDebugStartRequest, position: PlaybackPosition, actualTickInRow: Int?) {
        requestedStartOrder = request.requestedOrderIndex
        requestedStartPattern = request.requestedPatternIndex
        requestedStartRow = request.requestedRowIndex
        requestedStartTick = request.requestedTickInRow
        actualStartOrder = position.orderIndex
        actualStartPattern = position.patternIndex
        actualStartRow = position.rowIndex
        actualStartTick = actualTickInRow ?? 0
    }
}

private enum PlaybackPositionCommand: Equatable {
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
}
