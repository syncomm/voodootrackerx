import Foundation

enum PlaybackSongSyntheticVolumeColumnCommand: Equatable {
    case none
    case setVolume(value: Int)
    case volumeSlideDown(amount: Int)
    case volumeSlideUp(amount: Int)
    case fineVolumeSlideDown(amount: Int)
    case fineVolumeSlideUp(amount: Int)
    case setVibratoSpeed(amount: Int)
    case vibrato(amount: Int)
    case setPanning(value: Int)
    case panningSlideLeft(amount: Int)
    case panningSlideRight(amount: Int)
    case tonePortamento(amount: Int)
    case unsupported(rawValue: UInt8)

    var name: String {
        switch self {
        case .none:
            return "none"
        case .setVolume:
            return "setVolume"
        case .volumeSlideDown:
            return "volumeSlideDown"
        case .volumeSlideUp:
            return "volumeSlideUp"
        case .fineVolumeSlideDown:
            return "fineVolumeSlideDown"
        case .fineVolumeSlideUp:
            return "fineVolumeSlideUp"
        case .setVibratoSpeed:
            return "setVibratoSpeed"
        case .vibrato:
            return "vibrato"
        case .setPanning:
            return "setPanning"
        case .panningSlideLeft:
            return "panningSlideLeft"
        case .panningSlideRight:
            return "panningSlideRight"
        case .tonePortamento:
            return "tonePortamento"
        case .unsupported:
            return "unsupported"
        }
    }
}

enum PlaybackSongSyntheticVolumeColumnClassification: Equatable {
    case ignoredNoOp
    case supported
    case deferred
}

enum PlaybackSongSyntheticVolumeColumnSlideDirection: Equatable {
    case volumeDown
    case volumeUp
    case panningLeft
    case panningRight
}

enum PlaybackSongSyntheticVolumeColumnBehavior: Equatable {
    case rowLevelApproximation
    case tickLevelAfterTick0
}

struct PlaybackSongSyntheticVolumeColumnDiagnostic: Equatable {
    let rawValue: UInt8
    let command: PlaybackSongSyntheticVolumeColumnCommand
    let classification: PlaybackSongSyntheticVolumeColumnClassification
    let applied: Bool
    let ignoredAsEmptyOrNoOp: Bool
    let deferred: Bool
    let appliedVolumeValue: Int?
    let appliedGainMultiplier: Float?
    let appliedPanningValue: Int?
    let appliedPan: Float?
    let slideAmount: Int?
    let slideDirection: PlaybackSongSyntheticVolumeColumnSlideDirection?
    let effectiveVolumeBefore: Int?
    let effectiveVolumeAfter: Int?
    let effectivePanBefore: Float?
    let effectivePanAfter: Float?
    let behavior: PlaybackSongSyntheticVolumeColumnBehavior?

    func withAppliedState(
        appliedVolumeValue: Int? = nil,
        appliedGainMultiplier: Float? = nil,
        appliedPanningValue: Int? = nil,
        appliedPan: Float? = nil,
        effectiveVolumeBefore: Int? = nil,
        effectiveVolumeAfter: Int? = nil,
        effectivePanBefore: Float? = nil,
        effectivePanAfter: Float? = nil,
        behavior: PlaybackSongSyntheticVolumeColumnBehavior? = nil
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        PlaybackSongSyntheticVolumeColumnDiagnostic(
            rawValue: rawValue,
            command: command,
            classification: classification,
            applied: applied,
            ignoredAsEmptyOrNoOp: ignoredAsEmptyOrNoOp,
            deferred: deferred,
            appliedVolumeValue: appliedVolumeValue ?? self.appliedVolumeValue,
            appliedGainMultiplier: appliedGainMultiplier ?? self.appliedGainMultiplier,
            appliedPanningValue: appliedPanningValue ?? self.appliedPanningValue,
            appliedPan: appliedPan ?? self.appliedPan,
            slideAmount: slideAmount,
            slideDirection: slideDirection,
            effectiveVolumeBefore: effectiveVolumeBefore ?? self.effectiveVolumeBefore,
            effectiveVolumeAfter: effectiveVolumeAfter ?? self.effectiveVolumeAfter,
            effectivePanBefore: effectivePanBefore ?? self.effectivePanBefore,
            effectivePanAfter: effectivePanAfter ?? self.effectivePanAfter,
            behavior: behavior ?? self.behavior
        )
    }
}

enum PlaybackSongVolumeColumnDecoder {
    static func decode(_ rawValue: UInt8) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        switch rawValue {
        case 0:
            return diagnostic(rawValue: rawValue, command: .none, classification: .ignoredNoOp)
        case 0x10...0x50:
            let value = Int(rawValue - 0x10)
            return diagnostic(
                rawValue: rawValue,
                command: .setVolume(value: value),
                classification: .supported,
                appliedVolumeValue: value,
                appliedGainMultiplier: Float(value) / 64.0
            )
        case 0x60...0x6F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .volumeSlideDown(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeDown,
                behavior: .rowLevelApproximation
            )
        case 0x70...0x7F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .volumeSlideUp(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeUp,
                behavior: .rowLevelApproximation
            )
        case 0x80...0x8F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .fineVolumeSlideDown(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeDown,
                behavior: .rowLevelApproximation
            )
        case 0x90...0x9F:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .fineVolumeSlideUp(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .volumeUp,
                behavior: .rowLevelApproximation
            )
        case 0xA0...0xAF:
            return diagnostic(rawValue: rawValue, command: .setVibratoSpeed(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0xB0...0xBF:
            return diagnostic(rawValue: rawValue, command: .vibrato(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0xC0...0xCF:
            let panning = Int(rawValue & 0x0F) * 17
            return diagnostic(
                rawValue: rawValue,
                command: .setPanning(value: panning),
                classification: .supported,
                appliedPanningValue: panning,
                appliedPan: audioPan(forXMValue: panning)
            )
        case 0xD0...0xDF:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .panningSlideLeft(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .panningLeft,
                behavior: .rowLevelApproximation
            )
        case 0xE0...0xEF:
            let amount = Int(rawValue & 0x0F)
            return diagnostic(
                rawValue: rawValue,
                command: .panningSlideRight(amount: amount),
                classification: .supported,
                slideAmount: amount,
                slideDirection: .panningRight,
                behavior: .rowLevelApproximation
            )
        case 0xF0...0xFF:
            return diagnostic(
                rawValue: rawValue,
                command: .tonePortamento(amount: Int(rawValue & 0x0F)),
                classification: .supported,
                behavior: .tickLevelAfterTick0
            )
        default:
            return diagnostic(rawValue: rawValue, command: .unsupported(rawValue: rawValue), classification: .deferred)
        }
    }

    private static func diagnostic(
        rawValue: UInt8,
        command: PlaybackSongSyntheticVolumeColumnCommand,
        classification: PlaybackSongSyntheticVolumeColumnClassification,
        appliedVolumeValue: Int? = nil,
        appliedGainMultiplier: Float? = nil,
        appliedPanningValue: Int? = nil,
        appliedPan: Float? = nil,
        slideAmount: Int? = nil,
        slideDirection: PlaybackSongSyntheticVolumeColumnSlideDirection? = nil,
        behavior: PlaybackSongSyntheticVolumeColumnBehavior? = nil
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        PlaybackSongSyntheticVolumeColumnDiagnostic(
            rawValue: rawValue,
            command: command,
            classification: classification,
            applied: classification == .supported,
            ignoredAsEmptyOrNoOp: classification == .ignoredNoOp,
            deferred: classification == .deferred,
            appliedVolumeValue: appliedVolumeValue,
            appliedGainMultiplier: appliedGainMultiplier,
            appliedPanningValue: appliedPanningValue,
            appliedPan: appliedPan,
            slideAmount: slideAmount,
            slideDirection: slideDirection,
            effectiveVolumeBefore: nil,
            effectiveVolumeAfter: nil,
            effectivePanBefore: nil,
            effectivePanAfter: nil,
            behavior: behavior
        )
    }

    static func audioPan(forXMValue value: Int) -> Float {
        audioPan(forXMValue: Double(value))
    }

    static func audioPan(forXMValue value: Double) -> Float {
        (Float(min(255.0, max(0.0, value))) / 127.5) - 1.0
    }
}

struct PlaybackSongSyntheticVolumeColumnMapping: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
}
