import Foundation

enum PlaybackEffectCommand: Equatable {
    case setSpeed(Int)
    case setBPM(Int)
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
    case setVolume(Float)
}

enum PlaybackContinuousEffect: Equatable {
    case arpeggio(x: Int, y: Int)
    case volumeSlide(up: Int, down: Int)
    case portamentoUp(amount: Int)
    case portamentoDown(amount: Int)
}

struct PlaybackChannelState: Equatable {
    static let pitchOffsetRange = -48.0...48.0

    var volume: Float = 1
    var pitchOffsetSemitones: Double = 0
    var activeEffect: PlaybackContinuousEffect?
    var lastArpeggioParam: UInt8?
    var lastVolumeSlideParam: UInt8?
    var lastPortamentoUpParam: UInt8?
    var lastPortamentoDownParam: UInt8?

    var audioControls: AudioChannelControls {
        AudioChannelControls(volumeScale: volume, pitchOffsetSemitones: pitchOffsetSemitones)
    }

    mutating func beginRow() {
        if case .arpeggio = activeEffect {
            pitchOffsetSemitones = 0
        }
        activeEffect = nil
    }

    mutating func start(note: UInt8) {
        guard note > 0, note <= 96 else {
            return
        }
        pitchOffsetSemitones = 0
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
            let delta = Float(up - down) / 64.0
            volume = min(1, max(0, volume + delta))
        case let .portamentoUp(amount):
            pitchOffsetSemitones = Self.clampedPitchOffset(pitchOffsetSemitones + PlaybackEffectHandler.pitchSlideSemitonesPerTick(amount: amount))
        case let .portamentoDown(amount):
            pitchOffsetSemitones = Self.clampedPitchOffset(pitchOffsetSemitones - PlaybackEffectHandler.pitchSlideSemitonesPerTick(amount: amount))
        }
    }

    private static func clampedPitchOffset(_ value: Double) -> Double {
        min(pitchOffsetRange.upperBound, max(pitchOffsetRange.lowerBound, value))
    }
}

enum PlaybackEffectHandler {
    static func command(effectType: UInt8, effectParam: UInt8) -> PlaybackEffectCommand? {
        switch effectType {
        case 0x0B:
            return .positionJump(orderIndex: Int(effectParam))
        case 0x0C:
            return .setVolume(Float(min(effectParam, 0x40)) / 64.0)
        case 0x0D:
            return patternBreakCommand(effectParam)
        case 0x0F:
            return timingCommand(effectParam)
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

    static func pitchSlideSemitonesPerTick(amount: Int) -> Double {
        Double(max(0, amount)) / 64.0
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
