import Foundation

enum PlaybackEffectCommand: Equatable {
    case setSpeed(Int)
    case setBPM(Int)
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
    case setVolume(Float)
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
