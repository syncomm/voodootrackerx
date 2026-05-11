import Foundation

enum PlaybackEffectCommand: Equatable {
    case setSpeed(Int)
    case setBPM(Int)
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
    case setVolume(Float)
    case setPanning(Int)
    case setGlobalVolume(Float)
    case patternDelay(rowDurations: Int)
}

enum PlaybackContinuousEffect: Equatable {
    case arpeggio(x: Int, y: Int)
    case volumeSlide(up: Int, down: Int)
    case portamentoUp(amount: Int)
    case portamentoDown(amount: Int)
    case tonePortamento(amount: Int)
    case vibrato(speed: Int, depth: Int)
    case tremolo(speed: Int, depth: Int)
    case panningSlide(right: Int, left: Int)
    case tonePortamentoVolumeSlide(amount: Int, up: Int, down: Int)
    case vibratoVolumeSlide(speed: Int, depth: Int, up: Int, down: Int)
}

struct PlaybackGlobalState: Equatable {
    var volume: Float = 1
    var activeVolumeSlide: PlaybackGlobalVolumeSlide?
    var lastVolumeSlideParam: UInt8?

    mutating func beginRow() {
        activeVolumeSlide = nil
    }

    mutating func setVolume(_ volume: Float) {
        self.volume = Self.clampedVolume(volume)
    }

    mutating func applyVolumeSlide(effectParam: UInt8) -> Bool {
        guard let slide = PlaybackEffectHandler.globalVolumeSlide(effectParam: effectParam, memory: lastVolumeSlideParam) else {
            return effectParam == 0
        }
        activeVolumeSlide = slide
        if effectParam != 0 {
            lastVolumeSlideParam = effectParam
        }
        return true
    }

    mutating func advanceContinuousEffects() {
        guard let activeVolumeSlide else {
            return
        }
        let delta = Float(activeVolumeSlide.up - activeVolumeSlide.down) / 64.0
        volume = Self.clampedVolume(volume + delta)
    }

    private static func clampedVolume(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}

struct PlaybackGlobalVolumeSlide: Equatable {
    let up: Int
    let down: Int
}

struct PlaybackVolumeEnvelopeState: Equatable {
    private(set) var envelope: PlaybackVolumeEnvelope = .disabled
    private(set) var tick = 0
    private(set) var fadeoutValue: Float = 1
    private(set) var isKeyReleased = false

    var envelopeEnabled: Bool {
        envelope.enabled && !envelope.points.isEmpty
    }

    var envelopeValue: Float {
        envelope.value(at: tick)
    }

    var sustainActive: Bool {
        guard envelopeEnabled,
              envelope.sustainEnabled,
              !isKeyReleased,
              let sustainPoint = envelope.sustainPoint else {
            return false
        }
        return tick >= sustainPoint.tick
    }

    var loopActive: Bool {
        guard envelopeEnabled,
              envelope.loopEnabled,
              let loopStart = envelope.loopStartPoint,
              let loopEnd = envelope.loopEndPoint else {
            return false
        }
        return tick >= loopStart.tick && tick <= loopEnd.tick
    }

    var volumeMultiplier: Float {
        PlaybackVolumeCalculator.clamped(envelopeValue * fadeoutValue)
    }

    var isFullyFadedOut: Bool {
        isKeyReleased && fadeoutValue <= 0
    }

    mutating func reset(envelope: PlaybackVolumeEnvelope) {
        self.envelope = envelope
        tick = 0
        fadeoutValue = 1
        isKeyReleased = false
    }

    mutating func noteOff() {
        isKeyReleased = true
    }

    mutating func advanceTick() {
        if envelopeEnabled {
            advanceEnvelopeTick()
        }
        advanceFadeout()
    }

    private mutating func advanceEnvelopeTick() {
        if sustainActive,
           let sustainPoint = envelope.sustainPoint {
            tick = sustainPoint.tick
            return
        }

        tick += 1

        guard envelope.loopEnabled,
              let loopStart = envelope.loopStartPoint,
              let loopEnd = envelope.loopEndPoint,
              loopEnd.tick >= loopStart.tick,
              tick > loopEnd.tick else {
            return
        }

        let loopLength = max(1, loopEnd.tick - loopStart.tick + 1)
        tick = loopStart.tick + ((tick - loopEnd.tick - 1) % loopLength)
    }

    private mutating func advanceFadeout() {
        guard isKeyReleased, envelope.fadeout > 0 else {
            return
        }
        let decrement = Float(envelope.fadeout) / 65_536.0
        fadeoutValue = PlaybackVolumeCalculator.clamped(fadeoutValue - decrement)
    }
}

struct PlaybackChannelState: Equatable {
    static let pitchOffsetRange = -48.0...48.0
    static let vibratoOffsetRange = -12.0...12.0
    static let tremoloOffsetRange: ClosedRange<Float> = -1.0...1.0

    var volume: Float = 1
    var panning: Int = PlaybackEffectHandler.centerPanning
    var tremoloVolumeOffset: Float = 0
    var volumeEnvelopeState = PlaybackVolumeEnvelopeState()
    var pitchOffsetSemitones: Double = 0
    var vibratoOffsetSemitones: Double = 0
    var activeEffect: PlaybackContinuousEffect?
    var baseNote: UInt8?
    var tonePortamentoTargetNote: UInt8?
    var suppressesNoteTrigger = false
    var sampleStartOffset = 0
    var retriggerInterval: Int?
    var noteCutTick: Int?
    var noteDelayTick: Int?
    var lastArpeggioParam: UInt8?
    var lastVolumeSlideParam: UInt8?
    var lastPortamentoUpParam: UInt8?
    var lastPortamentoDownParam: UInt8?
    var lastTonePortamentoParam: UInt8?
    var lastVibratoParam: UInt8?
    var lastTremoloParam: UInt8?
    var lastPanningSlideParam: UInt8?
    var vibratoPhase = 0.0
    var tremoloPhase = 0.0

    var audioControls: AudioChannelControls {
        AudioChannelControls(
            volumeScale: Self.clampedVolume(volume + tremoloVolumeOffset) * volumeEnvelopeState.volumeMultiplier,
            pitchOffsetSemitones: Self.clampedPitchOffset(pitchOffsetSemitones + vibratoOffsetSemitones),
            panning: PlaybackEffectHandler.audioPanning(forXMValue: panning)
        )
    }

    var hasActiveNote: Bool {
        baseNote != nil
    }

    static func defaultPanning(forChannel channelIndex: Int) -> Int {
        // Conservative tracker spread: L, R, R, L at about half-left/half-right, then repeat.
        switch channelIndex % 4 {
        case 0, 3:
            return 64
        default:
            return 191
        }
    }

    static func defaultState(forChannel channelIndex: Int) -> PlaybackChannelState {
        PlaybackChannelState(panning: defaultPanning(forChannel: channelIndex))
    }

    mutating func beginRow() {
        if case .arpeggio = activeEffect {
            pitchOffsetSemitones = 0
        }
        if case .vibrato = activeEffect {
            vibratoOffsetSemitones = 0
        }
        if case .vibratoVolumeSlide = activeEffect {
            vibratoOffsetSemitones = 0
        }
        if case .tremolo = activeEffect {
            tremoloVolumeOffset = 0
        }
        activeEffect = nil
        suppressesNoteTrigger = false
        sampleStartOffset = 0
        retriggerInterval = nil
        noteCutTick = nil
        noteDelayTick = nil
    }

    mutating func start(note: UInt8) {
        start(note: note, volumeEnvelope: .disabled)
    }

    mutating func start(note: UInt8, volumeEnvelope: PlaybackVolumeEnvelope) {
        guard note > 0, note <= 96 else {
            return
        }
        baseNote = note
        tonePortamentoTargetNote = nil
        pitchOffsetSemitones = 0
        vibratoOffsetSemitones = 0
        tremoloVolumeOffset = 0
        volumeEnvelopeState.reset(envelope: volumeEnvelope)
    }

    mutating func noteOff() {
        volumeEnvelopeState.noteOff()
    }

    mutating func advanceEnvelopeTick() {
        volumeEnvelopeState.advanceTick()
        if volumeEnvelopeState.isFullyFadedOut {
            baseNote = nil
        }
    }

    mutating func setTonePortamentoTarget(note: UInt8) {
        guard note > 0, note <= 96 else {
            return
        }
        if baseNote == nil {
            start(note: note)
        } else {
            tonePortamentoTargetNote = note
            suppressesNoteTrigger = true
        }
    }

    mutating func apply(effectType: UInt8, effectParam: UInt8) -> Bool {
        switch effectType {
        case 0x00:
            guard let effect = PlaybackEffectHandler.arpeggio(effectParam: effectParam, memory: lastArpeggioParam) else {
                return effectParam == 0
            }
            activeEffect = effect
            if effectParam != 0 {
                lastArpeggioParam = effectParam
            }
            pitchOffsetSemitones = 0
            return true
        case 0x01:
            guard let effect = PlaybackEffectHandler.portamentoUp(effectParam: effectParam, memory: lastPortamentoUpParam) else {
                return false
            }
            activeEffect = effect
            if effectParam != 0 {
                lastPortamentoUpParam = effectParam
            }
            return true
        case 0x02:
            guard let effect = PlaybackEffectHandler.portamentoDown(effectParam: effectParam, memory: lastPortamentoDownParam) else {
                return false
            }
            activeEffect = effect
            if effectParam != 0 {
                lastPortamentoDownParam = effectParam
            }
            return true
        case 0x03:
            guard let effect = PlaybackEffectHandler.tonePortamento(effectParam: effectParam, memory: lastTonePortamentoParam) else {
                return effectParam == 0
            }
            activeEffect = effect
            if effectParam != 0 {
                lastTonePortamentoParam = effectParam
            }
            return true
        case 0x04:
            guard let effect = PlaybackEffectHandler.vibrato(effectParam: effectParam, memory: lastVibratoParam) else {
                return effectParam == 0
            }
            activeEffect = effect
            if effectParam != 0 {
                lastVibratoParam = effectParam
            }
            return true
        case 0x05:
            let toneEffect = PlaybackEffectHandler.tonePortamento(effectParam: 0, memory: lastTonePortamentoParam)
            let slideEffect = PlaybackEffectHandler.volumeSlide(effectParam: effectParam, memory: lastVolumeSlideParam)
            if effectParam != 0 {
                lastVolumeSlideParam = effectParam
            }
            activeEffect = PlaybackEffectHandler.combinedTonePortamentoVolumeSlide(toneEffect: toneEffect, slideEffect: slideEffect)
            return activeEffect != nil || effectParam == 0
        case 0x06:
            let vibratoEffect = PlaybackEffectHandler.vibrato(effectParam: 0, memory: lastVibratoParam)
            let slideEffect = PlaybackEffectHandler.volumeSlide(effectParam: effectParam, memory: lastVolumeSlideParam)
            if effectParam != 0 {
                lastVolumeSlideParam = effectParam
            }
            activeEffect = PlaybackEffectHandler.combinedVibratoVolumeSlide(vibratoEffect: vibratoEffect, slideEffect: slideEffect)
            return activeEffect != nil || effectParam == 0
        case 0x07:
            guard let effect = PlaybackEffectHandler.tremolo(effectParam: effectParam, memory: lastTremoloParam) else {
                return effectParam == 0
            }
            activeEffect = effect
            if effectParam != 0 {
                lastTremoloParam = effectParam
            }
            return true
        case 0x19:
            guard let effect = PlaybackEffectHandler.panningSlide(effectParam: effectParam, memory: lastPanningSlideParam) else {
                return effectParam == 0
            }
            activeEffect = effect
            if effectParam != 0 {
                lastPanningSlideParam = effectParam
            }
            return true
        case 0x09:
            sampleStartOffset = PlaybackEffectHandler.sampleOffset(effectParam: effectParam)
            return true
        case 0x0E:
            return applyExtendedEffect(effectParam: effectParam)
        case 0x0A:
            guard let effect = PlaybackEffectHandler.volumeSlide(effectParam: effectParam, memory: lastVolumeSlideParam) else {
                return false
            }
            activeEffect = effect
            if effectParam != 0 {
                lastVolumeSlideParam = effectParam
            }
            return true
        default:
            return false
        }
    }

    private mutating func applyExtendedEffect(effectParam: UInt8) -> Bool {
        switch PlaybackEffectHandler.extendedTimingEffect(effectParam: effectParam) {
        case let .retrigger(interval):
            guard interval > 0 else {
                return true
            }
            retriggerInterval = interval
            return true
        case let .noteCut(tick):
            noteCutTick = tick
            return true
        case let .noteDelay(tick):
            noteDelayTick = tick
            suppressesNoteTrigger = tick > 0
            return true
        case .patternDelay:
            return true
        case .none:
            return false
        }
    }

    mutating func advanceContinuousEffect(tickInRow: Int) {
        guard let activeEffect else {
            return
        }
        switch activeEffect {
        case let .arpeggio(x, y):
            switch tickInRow % 3 {
            case 1:
                pitchOffsetSemitones = Double(x)
            case 2:
                pitchOffsetSemitones = Double(y)
            default:
                pitchOffsetSemitones = 0
            }
        case let .volumeSlide(up, down):
            applyVolumeSlide(up: up, down: down)
        case let .portamentoUp(amount):
            pitchOffsetSemitones = Self.clampedPitchOffset(pitchOffsetSemitones + PlaybackEffectHandler.pitchSlideSemitonesPerTick(amount: amount))
        case let .portamentoDown(amount):
            pitchOffsetSemitones = Self.clampedPitchOffset(pitchOffsetSemitones - PlaybackEffectHandler.pitchSlideSemitonesPerTick(amount: amount))
        case let .tonePortamento(amount):
            applyTonePortamento(amount: amount)
        case let .vibrato(speed, depth):
            applyVibrato(speed: speed, depth: depth)
        case let .tremolo(speed, depth):
            applyTremolo(speed: speed, depth: depth)
        case let .panningSlide(right, left):
            applyPanningSlide(right: right, left: left)
        case let .tonePortamentoVolumeSlide(amount, up, down):
            applyTonePortamento(amount: amount)
            applyVolumeSlide(up: up, down: down)
        case let .vibratoVolumeSlide(speed, depth, up, down):
            applyVibrato(speed: speed, depth: depth)
            applyVolumeSlide(up: up, down: down)
        }
    }

    private mutating func applyVolumeSlide(up: Int, down: Int) {
        let delta = Float(up - down) / 64.0
        volume = min(1, max(0, volume + delta))
    }

    private mutating func applyTonePortamento(amount: Int) {
        guard let baseNote,
              let tonePortamentoTargetNote else {
            return
        }
        let targetOffset = Double(Int(tonePortamentoTargetNote) - Int(baseNote))
        let step = PlaybackEffectHandler.pitchSlideSemitonesPerTick(amount: amount)
        if pitchOffsetSemitones < targetOffset {
            pitchOffsetSemitones = min(targetOffset, pitchOffsetSemitones + step)
        } else if pitchOffsetSemitones > targetOffset {
            pitchOffsetSemitones = max(targetOffset, pitchOffsetSemitones - step)
        }
        pitchOffsetSemitones = Self.clampedPitchOffset(pitchOffsetSemitones)
    }

    private mutating func applyVibrato(speed: Int, depth: Int) {
        vibratoPhase += Double(max(0, speed)) * (.pi / 32.0)
        let offset = sin(vibratoPhase) * (Double(max(0, depth)) / 16.0)
        vibratoOffsetSemitones = Self.clampedVibratoOffset(offset)
    }

    private mutating func applyTremolo(speed: Int, depth: Int) {
        tremoloPhase += Double(max(0, speed)) * (.pi / 32.0)
        let offset = Float(sin(tremoloPhase) * (Double(max(0, depth)) / 64.0))
        tremoloVolumeOffset = Self.clampedTremoloOffset(offset)
    }

    private mutating func applyPanningSlide(right: Int, left: Int) {
        panning = PlaybackEffectHandler.clampedPanning(panning + right - left)
    }

    private static func clampedVolume(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    private static func clampedTremoloOffset(_ value: Float) -> Float {
        min(tremoloOffsetRange.upperBound, max(tremoloOffsetRange.lowerBound, value))
    }

    private static func clampedPitchOffset(_ value: Double) -> Double {
        min(pitchOffsetRange.upperBound, max(pitchOffsetRange.lowerBound, value))
    }

    private static func clampedVibratoOffset(_ value: Double) -> Double {
        min(vibratoOffsetRange.upperBound, max(vibratoOffsetRange.lowerBound, value))
    }
}

enum PlaybackEffectHandler {
    enum ExtendedTimingEffect: Equatable {
        case retrigger(interval: Int)
        case noteCut(tick: Int)
        case noteDelay(tick: Int)
        case patternDelay(rowDurations: Int)
    }

    static func command(effectType: UInt8, effectParam: UInt8) -> PlaybackEffectCommand? {
        switch effectType {
        case 0x0B:
            return .positionJump(orderIndex: Int(effectParam))
        case 0x0C:
            return .setVolume(Float(min(effectParam, 0x40)) / 64.0)
        case 0x0D:
            return patternBreakCommand(effectParam)
        case 0x08:
            return .setPanning(clampedPanning(Int(effectParam)))
        case 0x0E:
            guard case let .patternDelay(rowDurations)? = extendedTimingEffect(effectParam: effectParam) else {
                return nil
            }
            return .patternDelay(rowDurations: rowDurations)
        case 0x0F:
            return timingCommand(effectParam)
        case 0x10:
            return .setGlobalVolume(Float(min(effectParam, 0x40)) / 64.0)
        default:
            return nil
        }
    }

    static func arpeggio(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        let x = Int((param & 0xF0) >> 4)
        let y = Int(param & 0x0F)
        return .arpeggio(x: x, y: y)
    }

    static func volumeSlide(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        let up = Int((param & 0xF0) >> 4)
        let down = Int(param & 0x0F)
        if up > 0 {
            return .volumeSlide(up: up, down: 0)
        }
        return .volumeSlide(up: 0, down: down)
    }

    static func portamentoUp(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        return .portamentoUp(amount: Int(param))
    }

    static func portamentoDown(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        return .portamentoDown(amount: Int(param))
    }

    static func tonePortamento(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        return .tonePortamento(amount: Int(param))
    }

    static func vibrato(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        let speed = Int((param & 0xF0) >> 4)
        let depth = Int(param & 0x0F)
        return .vibrato(speed: speed, depth: depth)
    }

    static func tremolo(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        let speed = Int((param & 0xF0) >> 4)
        let depth = Int(param & 0x0F)
        return .tremolo(speed: speed, depth: depth)
    }

    static let centerPanning = 128

    static func clampedPanning(_ value: Int) -> Int {
        min(255, max(0, value))
    }

    static func audioPanning(forXMValue value: Int) -> Float {
        (Float(clampedPanning(value)) / 127.5) - 1.0
    }

    static func panningSlide(effectParam: UInt8, memory: UInt8?) -> PlaybackContinuousEffect? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        let right = Int((param & 0xF0) >> 4)
        let left = Int(param & 0x0F)
        if right > 0 {
            return .panningSlide(right: right, left: 0)
        }
        return .panningSlide(right: 0, left: left)
    }

    static func globalVolumeSlide(effectParam: UInt8, memory: UInt8?) -> PlaybackGlobalVolumeSlide? {
        let param = effectParam == 0 ? memory : effectParam
        guard let param, param != 0 else {
            return nil
        }
        let up = Int((param & 0xF0) >> 4)
        let down = Int(param & 0x0F)
        if up > 0 {
            return PlaybackGlobalVolumeSlide(up: up, down: 0)
        }
        return PlaybackGlobalVolumeSlide(up: 0, down: down)
    }

    static func combinedTonePortamentoVolumeSlide(toneEffect: PlaybackContinuousEffect?, slideEffect: PlaybackContinuousEffect?) -> PlaybackContinuousEffect? {
        switch (toneEffect, slideEffect) {
        case let (.tonePortamento(amount)?, .volumeSlide(up, down)?):
            return .tonePortamentoVolumeSlide(amount: amount, up: up, down: down)
        case (.tonePortamento(_)?, nil):
            return toneEffect
        case (nil, .volumeSlide(_, _)?):
            return slideEffect
        default:
            return nil
        }
    }

    static func combinedVibratoVolumeSlide(vibratoEffect: PlaybackContinuousEffect?, slideEffect: PlaybackContinuousEffect?) -> PlaybackContinuousEffect? {
        switch (vibratoEffect, slideEffect) {
        case let (.vibrato(speed, depth)?, .volumeSlide(up, down)?):
            return .vibratoVolumeSlide(speed: speed, depth: depth, up: up, down: down)
        case (.vibrato(_, _)?, nil):
            return vibratoEffect
        case (nil, .volumeSlide(_, _)?):
            return slideEffect
        default:
            return nil
        }
    }

    static func pitchSlideSemitonesPerTick(amount: Int) -> Double {
        Double(max(0, amount)) / 64.0
    }

    static func isTonePortamentoEffect(_ effectType: UInt8) -> Bool {
        effectType == 0x03 || effectType == 0x05
    }

    static func sampleOffset(effectParam: UInt8) -> Int {
        Int(effectParam) * 256
    }

    static func extendedTimingEffect(effectParam: UInt8) -> ExtendedTimingEffect? {
        let subcommand = (effectParam & 0xF0) >> 4
        let value = Int(effectParam & 0x0F)
        switch subcommand {
        case 0x09:
            return .retrigger(interval: value)
        case 0x0C:
            return .noteCut(tick: value)
        case 0x0D:
            return .noteDelay(tick: value)
        case 0x0E:
            return .patternDelay(rowDurations: value)
        default:
            return nil
        }
    }

    private static func timingCommand(_ effectParam: UInt8) -> PlaybackEffectCommand? {
        guard effectParam > 0 else {
            return nil
        }
        if effectParam <= 0x1F {
            return .setSpeed(Int(effectParam))
        }
        return .setBPM(Int(effectParam))
    }

    private static func patternBreakCommand(_ effectParam: UInt8) -> PlaybackEffectCommand? {
        let tens = Int((effectParam & 0xF0) >> 4)
        let ones = Int(effectParam & 0x0F)
        guard tens <= 9, ones <= 9 else {
            return nil
        }
        return .patternBreak(rowIndex: (tens * 10) + ones)
    }
}
