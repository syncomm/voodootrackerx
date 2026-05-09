import Foundation
import os

@MainActor
final class PlaybackEngine: PlaybackTransport {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Playback")
    private let audioEngine: PlaybackAudioOutput
    private let traceWriter: PlaybackTraceWriting

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

    var positionDidChange: ((PlaybackPosition) -> Void)?
    var playbackDidStop: (() -> Void)?

    init(
        audioEngine: PlaybackAudioOutput = PlaybackAudioEngine(),
        traceWriter: PlaybackTraceWriting = PlaybackTraceConfiguration.makeWriter()
    ) {
        self.audioEngine = audioEngine
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
        logger.debug("Playback song loaded. hadActivePlayback=\(wasPlaying, privacy: .public) hasSong=\((song != nil), privacy: .public)")
    }

    func configureTiming(_ timing: PlaybackTiming) {
        self.timing = timing
        if state.isPlaying {
            restartTimer()
        }
    }

    func play(from context: PlaybackStartContext?) {
        guard !state.isPlaying else {
            logger.debug("Ignoring play request because playback is already active")
            return
        }
        guard let song else {
            stop()
            return
        }
        currentPosition = playbackStartPosition(from: context, in: song) ?? song.startPosition
        tickState.reset()
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        traceTickIndex = 0
        if let currentPosition {
            enter(position: currentPosition)
        }
        restartTimer()
        apply(action: .play, nextState: PlaybackState(mode: .playing, context: context))
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
            audioEngine.stopAll()
        }
        currentPosition = song?.startPosition
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        timing = song?.initialTiming ?? .xmDefault
        traceWriter.flush()
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
        audioEngine.stopAll()
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
        prepareRowPlaybackState(at: position)
        triggerAudio(at: position)
        applyImmediateTimingEffects()
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

    private func prepareRowPlaybackState(at position: PlaybackPosition) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        globalState.beginRow()
        rowDelayDurationsRemaining = 0
        for (channelIndex, cell) in row.cells.enumerated() {
            var channelState = state(forChannel: channelIndex)
            channelState.beginRow()
            if PlaybackEffectHandler.isTonePortamentoEffect(cell.effectType) {
                channelState.setTonePortamentoTarget(note: cell.note)
            } else {
                channelState.start(note: cell.note)
            }

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
        updateActiveChannelControls()
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
        let oldGlobalVolume = globalState.volume
        globalState.advanceContinuousEffects()
        for channelIndex in channelStates.keys.sorted() {
            guard var channelState = channelStates[channelIndex] else {
                continue
            }
            if channelState.activeEffect != nil {
                channelState.advanceContinuousEffect(tickInRow: tickInRow)
            }
            channelStates[channelIndex] = channelState
            audioEngine.update(channel: channelIndex, controls: effectiveControls(for: channelState))
            traceChannelEvent(
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .updated,
                reason: "tick_controls_updated"
            )
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
            audioEngine.stop(channel: channelIndex)
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
            audioEngine.stop(channel: channelIndex)
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
            trigger(delayedRequest, channelIndex: channelIndex)
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
            trigger(request, channelIndex: channelIndex)
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
            trigger(request, channelIndex: channelIndex)
        }
    }

    private func trigger(_ request: AudioVoiceRequest, channelIndex: Int) {
        audioEngine.trigger(request)
        lastVoiceRequests[channelIndex] = request
    }

    private func updateActiveChannelControls() {
        for channelIndex in channelStates.keys.sorted() {
            guard let channelState = channelStates[channelIndex] else {
                continue
            }
            audioEngine.update(channel: channelIndex, controls: effectiveControls(for: channelState))
        }
    }

    private func effectiveControls(for channelState: PlaybackChannelState) -> AudioChannelControls {
        var controls = channelState.audioControls
        controls.volumeScale = min(1, max(0, controls.volumeScale * globalState.volume))
        return controls
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
            usesLinearFrequencyTable: song?.usesLinearFrequencyTable,
            noteValue: noteValue,
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            relativeNote: sample?.relativeNote,
            finetune: sample?.finetune,
            sourceSampleRate: sample?.baseSampleRate,
            audioBufferSampleRate: pitchCalculation?.audioBufferSampleRate,
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
}

private enum PlaybackPositionCommand: Equatable {
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
}
