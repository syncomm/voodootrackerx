import Foundation

enum XMEffectCommandDisplay {
    static let fieldWidth = 3

    static func formatEffectField(effectType: UInt8, effectParam: UInt8) -> String {
        guard effectType != 0 || effectParam != 0 else {
            return "..."
        }

        let command = commandLetter(forEffectType: effectType) ?? "?"
        return String(format: "%@%02X", command, effectParam)
    }

    static func commandLetter(forEffectType effectType: UInt8) -> String? {
        switch effectType {
        case 0x00...0x0F:
            return String(format: "%X", effectType)
        case 0x10:
            return "G"
        case 0x11:
            return "H"
        default:
            return nil
        }
    }
}
