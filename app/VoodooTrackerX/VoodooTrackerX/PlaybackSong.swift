import Foundation

struct PlaybackCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

struct PlaybackSample: Equatable {
    let instrumentIndex: Int
    let sampleIndex: Int
    let pcm: [Float]
    let volume: Float
    let relativeNote: Int
    let finetune: Int
    let baseSampleRate: Double
    let sampleLength: Int
    let loopStart: Int
    let loopLength: Int
    let loopType: Int

    init(
        instrumentIndex: Int,
        sampleIndex: Int,
        pcm: [Float],
        volume: Float,
        relativeNote: Int,
        finetune: Int,
        baseSampleRate: Double,
        sampleLength: Int? = nil,
        loopStart: Int = 0,
        loopLength: Int = 0,
        loopType: Int = 0
    ) {
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
        self.pcm = pcm
        self.volume = volume
        self.relativeNote = relativeNote
        self.finetune = finetune
        self.baseSampleRate = baseSampleRate
        self.sampleLength = sampleLength ?? pcm.count
        self.loopStart = loopStart
        self.loopLength = loopLength
        self.loopType = loopType
    }

    var isPlayable: Bool {
        !pcm.isEmpty && volume > 0
    }

    var loopRegion: PlaybackSampleLoopRegion {
        PlaybackSampleLoopRegion.clamped(
            sampleFrameCount: min(sampleLength, pcm.count),
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType
        )
    }
}

struct PlaybackEnvelopePoint: Equatable {
    let tick: Int
    let value: Int

    init(tick: Int, value: Int) {
        self.tick = max(0, tick)
        self.value = min(64, max(0, value))
    }

    var normalizedValue: Float {
        Float(value) / 64.0
    }
}

struct PlaybackVolumeEnvelope: Equatable {
    static let disabled = PlaybackVolumeEnvelope(
        enabled: false,
        points: [],
        sustainPointIndex: nil,
        loopStartPointIndex: nil,
        loopEndPointIndex: nil,
        typeFlags: 0,
        fadeout: 0
    )

    let enabled: Bool
    let points: [PlaybackEnvelopePoint]
    let sustainPointIndex: Int?
    let loopStartPointIndex: Int?
    let loopEndPointIndex: Int?
    let typeFlags: UInt8
    let fadeout: Int

    var sustainEnabled: Bool {
        (typeFlags & 0x02) != 0 && sustainPoint != nil
    }

    var loopEnabled: Bool {
        (typeFlags & 0x04) != 0 && loopStartPoint != nil && loopEndPoint != nil
    }

    var sustainPoint: PlaybackEnvelopePoint? {
        guard let sustainPointIndex,
              points.indices.contains(sustainPointIndex) else {
            return nil
        }
        return points[sustainPointIndex]
    }

    var loopStartPoint: PlaybackEnvelopePoint? {
        guard let loopStartPointIndex,
              points.indices.contains(loopStartPointIndex) else {
            return nil
        }
        return points[loopStartPointIndex]
    }

    var loopEndPoint: PlaybackEnvelopePoint? {
        guard let loopEndPointIndex,
              points.indices.contains(loopEndPointIndex) else {
            return nil
        }
        return points[loopEndPointIndex]
    }

    func value(at tick: Int) -> Float {
        guard enabled, !points.isEmpty else {
            return 1
        }
        let safeTick = max(0, tick)
        guard let first = points.first else {
            return 1
        }
        if safeTick <= first.tick {
            return first.normalizedValue
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]
            guard safeTick <= next.tick else {
                continue
            }
            let distance = max(1, next.tick - previous.tick)
            let progress = Float(safeTick - previous.tick) / Float(distance)
            return previous.normalizedValue + ((next.normalizedValue - previous.normalizedValue) * progress)
        }
        return points.last?.normalizedValue ?? 1
    }
}

struct PlaybackInstrument: Equatable {
    let index: Int
    let samples: [PlaybackSample]
    let volumeEnvelope: PlaybackVolumeEnvelope

    init(index: Int, samples: [PlaybackSample], volumeEnvelope: PlaybackVolumeEnvelope = .disabled) {
        self.index = index
        self.samples = samples
        self.volumeEnvelope = volumeEnvelope
    }

    var firstPlayableSample: PlaybackSample? {
        samples.first { $0.isPlayable }
    }
}

struct PlaybackRow: Equatable {
    let index: Int
    let cells: [PlaybackCell]
}

struct PlaybackPattern: Equatable {
    let index: Int
    let rows: [PlaybackRow]

    var rowCount: Int {
        rows.count
    }
}

struct PlaybackOrderEntry: Equatable {
    let orderIndex: Int
    let patternIndex: Int
}

struct PlaybackPosition: Equatable {
    let orderIndex: Int
    let patternIndex: Int
    let rowIndex: Int
}

enum PlaybackEndBehavior: Equatable {
    case stopAtEnd
    case restartFromBeginning
}

enum PlaybackStepResult: Equatable {
    case advanced(PlaybackPosition)
    case ended(restartPosition: PlaybackPosition?)
}

struct PlaybackSong: Equatable {
    let title: String
    let orders: [PlaybackOrderEntry]
    let patternsByIndex: [Int: PlaybackPattern]
    let instrumentsByIndex: [Int: PlaybackInstrument]
    let restartOrderIndex: Int
    let endBehavior: PlaybackEndBehavior
    let initialTiming: PlaybackTiming
    let usesLinearFrequencyTable: Bool

    init(
        title: String,
        orders: [PlaybackOrderEntry],
        patternsByIndex: [Int: PlaybackPattern],
        instrumentsByIndex: [Int: PlaybackInstrument],
        restartOrderIndex: Int,
        endBehavior: PlaybackEndBehavior,
        initialTiming: PlaybackTiming = .xmDefault,
        usesLinearFrequencyTable: Bool = true
    ) {
        self.title = title
        self.orders = orders
        self.patternsByIndex = patternsByIndex
        self.instrumentsByIndex = instrumentsByIndex
        self.restartOrderIndex = restartOrderIndex
        self.endBehavior = endBehavior
        self.initialTiming = initialTiming
        self.usesLinearFrequencyTable = usesLinearFrequencyTable
    }

    var startPosition: PlaybackPosition? {
        position(orderIndex: 0, rowIndex: 0)
    }

    func pattern(for orderIndex: Int) -> PlaybackPattern? {
        guard orders.indices.contains(orderIndex) else {
            return nil
        }
        return patternsByIndex[orders[orderIndex].patternIndex]
    }

    func row(at position: PlaybackPosition) -> PlaybackRow? {
        guard let pattern = pattern(for: position.orderIndex),
              pattern.index == position.patternIndex,
              pattern.rows.indices.contains(position.rowIndex) else {
            return nil
        }
        return pattern.rows[position.rowIndex]
    }

    func sample(forInstrument instrumentIndex: Int) -> PlaybackSample? {
        guard instrumentIndex > 0 else {
            return nil
        }
        return instrumentsByIndex[instrumentIndex]?.firstPlayableSample
    }

    func instrument(forInstrument instrumentIndex: Int) -> PlaybackInstrument? {
        guard instrumentIndex > 0 else {
            return nil
        }
        return instrumentsByIndex[instrumentIndex]
    }

    func position(orderIndex: Int, rowIndex: Int) -> PlaybackPosition? {
        guard let pattern = pattern(for: orderIndex), !pattern.rows.isEmpty else {
            return nil
        }
        let safeRowIndex = min(max(0, rowIndex), pattern.rows.count - 1)
        return PlaybackPosition(orderIndex: orderIndex, patternIndex: pattern.index, rowIndex: safeRowIndex)
    }

    func position(patternIndex: Int, rowIndex: Int) -> PlaybackPosition? {
        guard let order = orders.first(where: { $0.patternIndex == patternIndex }) else {
            return nil
        }
        return position(orderIndex: order.orderIndex, rowIndex: rowIndex)
    }

    func position(after position: PlaybackPosition) -> PlaybackStepResult {
        guard let pattern = pattern(for: position.orderIndex),
              pattern.index == position.patternIndex else {
            return endResult()
        }

        let nextRowIndex = position.rowIndex + 1
        if nextRowIndex < pattern.rows.count {
            return .advanced(PlaybackPosition(orderIndex: position.orderIndex, patternIndex: pattern.index, rowIndex: nextRowIndex))
        }

        let nextOrderIndex = position.orderIndex + 1
        if let nextPosition = self.position(orderIndex: nextOrderIndex, rowIndex: 0) {
            return .advanced(nextPosition)
        }

        return endResult()
    }

    private func endResult() -> PlaybackStepResult {
        switch endBehavior {
        case .stopAtEnd:
            return .ended(restartPosition: nil)
        case .restartFromBeginning:
            return .ended(restartPosition: position(orderIndex: restartOrderIndex, rowIndex: 0) ?? startPosition)
        }
    }
}

struct PlaybackSongSyntheticPlan: Equatable {
    let timingConfig: SyntheticTrackerTimingConfig
    let pattern: SyntheticPattern
    let diagnostics: PlaybackSongSyntheticDiagnostics
}

struct PlaybackSongSyntheticDiagnostics: Equatable {
    let requestedStartOrderIndex: Int
    let requestedOrderCount: Int
    let sampleRate: Double
    let initialSpeed: Int
    let initialBPM: Int
    let usesLinearFrequencyTable: Bool
    let syntheticRowCount: Int
    let adaptedOrders: [PlaybackSongSyntheticOrderDiagnostic]
    let rowMappings: [PlaybackSongSyntheticRowMapping]
    let rowTiming: [PlaybackSongSyntheticRowTimingDiagnostic]
    let timingChanges: [PlaybackSongSyntheticTimingChangeDiagnostic]
    let rowDiagnostics: [PlaybackSongSyntheticRowDiagnostic]
    let volumeColumnMappings: [PlaybackSongSyntheticVolumeColumnMapping]
    let keyOffEvents: [PlaybackSongSyntheticKeyOffDiagnostic]
    let eventMappings: [PlaybackSongSyntheticEventMapping]
    let ignoredCells: [PlaybackSongSyntheticIgnoredCell]
    let deferredCellFields: [PlaybackSongSyntheticDeferredCellField]

    var emittedRowCount: Int {
        rowMappings.count
    }

    var emittedEventCount: Int {
        eventMappings.count
    }

    var ignoredCellCount: Int {
        ignoredCells.count
    }

    var emptyOrSkippedRowCount: Int {
        rowDiagnostics.filter { $0.emittedEventCount == 0 }.count
    }

    var ignoredEffectFieldCount: Int {
        deferredCellFields.filter { $0.field == .effect }.count
    }

    var ignoredVolumeColumnFieldCount: Int {
        deferredCellFields.filter { $0.field == .volumeColumn }.count
    }

}

struct PlaybackSongSyntheticOrderDiagnostic: Equatable {
    enum Status: Equatable {
        case adapted
        case invalidOrder
        case missingPattern
    }

    let requestedOrderIndex: Int
    let patternIndex: Int?
    let syntheticStartRow: Int
    let rowCount: Int
    let status: Status
}

struct PlaybackSongSyntheticRowMapping: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
}

struct PlaybackSongSyntheticRowDiagnostic: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let cellCount: Int
    let emittedEventCount: Int
    let ignoredCellCount: Int
}

struct PlaybackSongSyntheticRowTimingDiagnostic: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartFrame: Int
    let rowDurationFrames: Int
    let effectiveSpeed: Int
    let effectiveBPM: Int
}

struct PlaybackSongSyntheticKeyOffDiagnostic: Equatable {
    enum Reason: Equatable {
        case releasedActiveVoice
        case noActiveVoice
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let releaseFrame: Int?
    let applied: Bool
    let deferred: Bool
    let reason: Reason
    let activeEventIndex: Int?
}

struct PlaybackSongSyntheticTimingChangeDiagnostic: Equatable {
    enum Kind: Equatable {
        case speed
        case bpm
        case ignoredF00
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let effectType: UInt8
    let effectParam: UInt8
    let rowStartFrame: Int
    let appliesToSyntheticRowAfter: Int
    let kind: Kind
    let applied: Bool
    let speedBefore: Int
    let bpmBefore: Int
    let speedAfter: Int
    let bpmAfter: Int
}

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
            return diagnostic(rawValue: rawValue, command: .tonePortamento(amount: Int(rawValue & 0x0F)), classification: .deferred)
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

struct PlaybackSongSyntheticEnvelopeSemanticsDiagnostic: Equatable {
    let envelopeEnabled: Bool
    let sourcePointCount: Int
    let mappedPointCount: Int
    let sustainEnabled: Bool
    let sustainApplied: Bool
    let sustainDeferred: Bool
    let sustainPointIndex: Int?
    let sustainTick: Int?
    let sustainFrame: Int?
    let loopEnabled: Bool
    let loopApplied: Bool
    let loopDeferred: Bool
    let loopStartPointIndex: Int?
    let loopEndPointIndex: Int?
    let loopStartTick: Int?
    let loopEndTick: Int?
    let loopStartFrame: Int?
    let loopEndFrame: Int?
    let keyOffEncountered: Bool
    let keyOffApplied: Bool
    let keyOffDeferred: Bool
    let keyOffSource: PlaybackPosition?
    let keyOffChannelIndex: Int?
    let keyOffSyntheticRow: Int?
    let keyOffSyntheticTick: Int?
    let releaseFrame: Int?
    let fadeoutValue: Int
    let fadeoutApplied: Bool
    let fadeoutDeferred: Bool
    let limitations: [String]

    func applyingKeyOff(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        syntheticTick: Int,
        releaseFrame: Int
    ) -> PlaybackSongSyntheticEnvelopeSemanticsDiagnostic {
        PlaybackSongSyntheticEnvelopeSemanticsDiagnostic(
            envelopeEnabled: envelopeEnabled,
            sourcePointCount: sourcePointCount,
            mappedPointCount: mappedPointCount,
            sustainEnabled: sustainEnabled,
            sustainApplied: sustainApplied,
            sustainDeferred: sustainDeferred,
            sustainPointIndex: sustainPointIndex,
            sustainTick: sustainTick,
            sustainFrame: sustainFrame,
            loopEnabled: loopEnabled,
            loopApplied: loopApplied,
            loopDeferred: loopDeferred,
            loopStartPointIndex: loopStartPointIndex,
            loopEndPointIndex: loopEndPointIndex,
            loopStartTick: loopStartTick,
            loopEndTick: loopEndTick,
            loopStartFrame: loopStartFrame,
            loopEndFrame: loopEndFrame,
            keyOffEncountered: true,
            keyOffApplied: true,
            keyOffDeferred: false,
            keyOffSource: source,
            keyOffChannelIndex: channelIndex,
            keyOffSyntheticRow: syntheticRow,
            keyOffSyntheticTick: syntheticTick,
            releaseFrame: releaseFrame,
            fadeoutValue: fadeoutValue,
            fadeoutApplied: fadeoutValue > 0,
            fadeoutDeferred: false,
            limitations: limitations
        )
    }
}

struct PlaybackSongSyntheticEventMapping: Equatable {
    enum VolumeEnvelopeStatus: Equatable {
        case absent
        case disabled
        case invalidOrEmptyIgnored
        case mapped
    }

    enum FinetuneStatus: Equatable {
        case applied
        case deferred
    }

    enum FrequencyTableStatus: Equatable {
        case linearApplied
        case amigaTableDeferredNeutralFallback
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let sampleIndex: Int
    let syntheticRow: Int
    let syntheticTick: Int
    let eventIndex: Int
    let loopMode: MixerSampleLoopMode
    let volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    let hasIgnoredVolumeColumn: Bool
    let hasIgnoredEffect: Bool
    let effectiveVolumeValue: Int
    let effectivePan: Float
    let volumeEnvelopeStatus: VolumeEnvelopeStatus
    let sourceVolumeEnvelopePointCount: Int
    let mappedVolumeEnvelopePointCount: Int
    let hasDeferredVolumeEnvelopeSustain: Bool
    let hasDeferredVolumeEnvelopeLoop: Bool
    let hasDeferredVolumeEnvelopeFadeout: Bool
    let volumeEnvelopeSemantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
    let sampleBaseSampleRate: Double
    let sampleRelativeNote: Int
    let sampleFinetune: Int
    let outputSampleRate: Double
    let effectiveNoteValue: Int?
    let effectiveNoteIndex: Int?
    let effectiveFinetune: Int?
    let linearPeriod: Double?
    let linearFrequency: Double?
    let finetuneStatus: FinetuneStatus
    let usesLinearFrequencyTable: Bool
    let frequencyTableStatus: FrequencyTableStatus
    let linearFrequencyApplied: Bool
    let amigaFrequencyDeferred: Bool
    let playbackStep: Double
    let pitchMappingApplied: Bool
    let pitchMappingUsedNeutralStep: Bool
}

struct PlaybackSongSyntheticIgnoredCell: Equatable {
    enum Reason: Equatable {
        case emptyNote
        case keyOff
        case invalidNote
        case missingInstrument
        case noPlayableSample
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let reason: Reason
    let volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    let hasIgnoredVolumeColumn: Bool
    let hasIgnoredEffect: Bool
}

struct PlaybackSongSyntheticDeferredCellField: Equatable {
    enum Field: Equatable {
        case volumeColumn
        case effect
        case keyOff
        case volumeEnvelopeSustain
        case volumeEnvelopeLoop
        case volumeEnvelopeFadeout
    }

    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let volumeColumn: UInt8
    let volumeColumnDiagnostic: PlaybackSongSyntheticVolumeColumnDiagnostic
    let effectType: UInt8
    let effectParam: UInt8
    let field: Field
}

struct PlaybackSongFxxRowTiming: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowEndExactFrame: Double
    let effectiveSpeed: Int
    let effectiveBPM: Int

    var rowStartFrame: Int {
        Self.floorFrame(rowStartExactFrame)
    }

    var rowEndFrame: Int {
        Self.floorFrame(rowEndExactFrame)
    }

    var rowDurationFrames: Int {
        max(0, rowEndFrame - rowStartFrame)
    }

    var diagnostic: PlaybackSongSyntheticRowTimingDiagnostic {
        PlaybackSongSyntheticRowTimingDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            rowStartFrame: rowStartFrame,
            rowDurationFrames: rowDurationFrames,
            effectiveSpeed: effectiveSpeed,
            effectiveBPM: effectiveBPM
        )
    }

    private static func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

struct PlaybackSongFxxTimingPlan: Equatable {
    let sampleRate: Double
    let initialSpeed: Int
    let initialBPM: Int
    let rowTimings: [PlaybackSongFxxRowTiming]
    let timingChanges: [PlaybackSongSyntheticTimingChangeDiagnostic]
    let finalSpeed: Int
    let finalBPM: Int
    let endExactFrame: Double

    var rowTimingDiagnostics: [PlaybackSongSyntheticRowTimingDiagnostic] {
        rowTimings.map(\.diagnostic)
    }

    func timingConfig(forSyntheticRow syntheticRow: Int) -> SyntheticTrackerTimingConfig {
        let timing = timingFor(syntheticRow: syntheticRow)
        return SyntheticTrackerTimingConfig(
            speed: timing.speed,
            bpm: timing.bpm,
            sampleRate: sampleRate
        )
    }

    func frameFor(row: Int, tick: Int = 0) -> Int {
        let safeRow = max(0, row)
        let timing = timingFor(syntheticRow: safeRow)
        let safeTick = min(max(0, tick), timing.speed - 1)
        let exactFrame = timing.rowStartExactFrame + (Double(safeTick) * framesPerTick(bpm: timing.bpm))
        return floorFrame(exactFrame)
    }

    private func timingFor(syntheticRow: Int) -> (rowStartExactFrame: Double, speed: Int, bpm: Int) {
        if rowTimings.indices.contains(syntheticRow),
           rowTimings[syntheticRow].syntheticRow == syntheticRow {
            let rowTiming = rowTimings[syntheticRow]
            return (
                rowStartExactFrame: rowTiming.rowStartExactFrame,
                speed: rowTiming.effectiveSpeed,
                bpm: rowTiming.effectiveBPM
            )
        }

        let extraRows = max(0, syntheticRow - rowTimings.count)
        let rowStart = endExactFrame + (Double(extraRows) * rowDuration(speed: finalSpeed, bpm: finalBPM))
        return (rowStartExactFrame: rowStart, speed: finalSpeed, bpm: finalBPM)
    }

    private func framesPerTick(bpm: Int) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm))
    }

    private func rowDuration(speed: Int, bpm: Int) -> Double {
        framesPerTick(bpm: bpm) * Double(max(1, speed))
    }

    private func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

enum PlaybackSongFxxTimingPlanner {
    static func plan(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongFxxTimingPlan {
        let initialConfig = SyntheticTrackerTimingConfig(
            speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm,
            sampleRate: sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var currentSpeed = initialConfig.speed
        var currentBPM = initialConfig.bpm
        var currentExactFrame = 0.0
        var nextSyntheticRow = 0
        var rowTimings = [PlaybackSongFxxRowTiming]()
        var timingChanges = [PlaybackSongSyntheticTimingChangeDiagnostic]()

        for orderOffset in 0..<safeOrderCount {
            let orderIndex = startOrderIndex + orderOffset
            guard song.orders.indices.contains(orderIndex) else {
                continue
            }
            let order = song.orders[orderIndex]
            guard let pattern = song.patternsByIndex[order.patternIndex] else {
                continue
            }

            for (rowOffset, row) in pattern.rows.enumerated() {
                let syntheticRow = nextSyntheticRow + rowOffset
                let source = PlaybackPosition(
                    orderIndex: orderIndex,
                    patternIndex: pattern.index,
                    rowIndex: row.index
                )
                let rowStartExactFrame = currentExactFrame
                let rowEndExactFrame = currentExactFrame + rowDuration(
                    speed: currentSpeed,
                    bpm: currentBPM,
                    sampleRate: initialConfig.sampleRate
                )
                let rowTiming = PlaybackSongFxxRowTiming(
                    source: source,
                    syntheticRow: syntheticRow,
                    rowStartExactFrame: rowStartExactFrame,
                    rowEndExactFrame: rowEndExactFrame,
                    effectiveSpeed: currentSpeed,
                    effectiveBPM: currentBPM
                )
                rowTimings.append(rowTiming)

                var nextSpeed = currentSpeed
                var nextBPM = currentBPM
                for (channelIndex, cell) in row.cells.enumerated() where isFxxTimingEffect(cell) {
                    let speedBefore = nextSpeed
                    let bpmBefore = nextBPM
                    let kind: PlaybackSongSyntheticTimingChangeDiagnostic.Kind
                    let applied: Bool
                    switch cell.effectParam {
                    case 0:
                        kind = .ignoredF00
                        applied = false
                    case 0x01...0x1F:
                        kind = .speed
                        applied = true
                        nextSpeed = Int(cell.effectParam)
                    default:
                        kind = .bpm
                        applied = true
                        nextBPM = Int(cell.effectParam)
                    }
                    timingChanges.append(PlaybackSongSyntheticTimingChangeDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        effectType: cell.effectType,
                        effectParam: cell.effectParam,
                        rowStartFrame: rowTiming.rowStartFrame,
                        appliesToSyntheticRowAfter: syntheticRow + 1,
                        kind: kind,
                        applied: applied,
                        speedBefore: speedBefore,
                        bpmBefore: bpmBefore,
                        speedAfter: nextSpeed,
                        bpmAfter: nextBPM
                    ))
                }

                currentExactFrame = rowEndExactFrame
                currentSpeed = nextSpeed
                currentBPM = nextBPM
            }

            nextSyntheticRow += pattern.rowCount
        }

        return PlaybackSongFxxTimingPlan(
            sampleRate: initialConfig.sampleRate,
            initialSpeed: initialConfig.speed,
            initialBPM: initialConfig.bpm,
            rowTimings: rowTimings,
            timingChanges: timingChanges,
            finalSpeed: currentSpeed,
            finalBPM: currentBPM,
            endExactFrame: currentExactFrame
        )
    }

    static func isFxxTimingEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0F
    }

    private static func rowDuration(speed: Int, bpm: Int, sampleRate: Double) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm)) * Double(max(1, speed))
    }
}

enum PlaybackSongSyntheticAdapter {
    private static let maxMixerEnvelopePointCount = 12
    private static let xmLinearPeriodBase = 7_680.0
    private static let xmLinearC4Period = 4_608.0
    private static let xmLinearPeriodUnitsPerSemitone = 64.0
    private static let xmLinearPeriodUnitsPerOctave = 768.0

    private struct ChannelState: Equatable {
        var volumeValue = 64
        var panningValue = 127.5
        var activeEventIndex: Int?
        var activeEventMappingIndex: Int?

        var pan: Float {
            PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: panningValue)
        }
    }

    static func adapt(
        _ song: PlaybackSong,
        orderIndex: Int,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: orderIndex, orderCount: 1, sampleRate: sampleRate)
    }

    static func adapt(
        _ song: PlaybackSong,
        orderRange: Range<Int>,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        adapt(
            song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: max(0, orderRange.count),
            sampleRate: sampleRate
        )
    }

    static func adapt(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongSyntheticPlan {
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            sampleRate: sampleRate
        )
        let timingConfig = SyntheticTrackerTimingConfig(
            speed: timingPlan.initialSpeed,
            bpm: timingPlan.initialBPM,
            sampleRate: timingPlan.sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var adaptedOrders = [PlaybackSongSyntheticOrderDiagnostic]()
        var rowMappings = [PlaybackSongSyntheticRowMapping]()
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var volumeColumnMappings = [PlaybackSongSyntheticVolumeColumnMapping]()
        var keyOffEvents = [PlaybackSongSyntheticKeyOffDiagnostic]()
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
        var deferredCellFields = [PlaybackSongSyntheticDeferredCellField]()
        var events = [SyntheticTrackerEvent]()
        var channelStates = [Int: ChannelState]()
        var nextSyntheticRow = 0

        for orderOffset in 0..<safeOrderCount {
            let orderIndex = startOrderIndex + orderOffset
            guard song.orders.indices.contains(orderIndex) else {
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: orderIndex,
                    patternIndex: nil,
                    syntheticStartRow: nextSyntheticRow,
                    rowCount: 0,
                    status: .invalidOrder
                ))
                continue
            }

            let order = song.orders[orderIndex]
            guard let pattern = song.patternsByIndex[order.patternIndex] else {
                adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                    requestedOrderIndex: orderIndex,
                    patternIndex: order.patternIndex,
                    syntheticStartRow: nextSyntheticRow,
                    rowCount: 0,
                    status: .missingPattern
                ))
                continue
            }

            adaptedOrders.append(PlaybackSongSyntheticOrderDiagnostic(
                requestedOrderIndex: orderIndex,
                patternIndex: pattern.index,
                syntheticStartRow: nextSyntheticRow,
                rowCount: pattern.rowCount,
                status: .adapted
            ))

            for (rowOffset, row) in pattern.rows.enumerated() {
                let syntheticRow = nextSyntheticRow + rowOffset
                let source = PlaybackPosition(
                    orderIndex: orderIndex,
                    patternIndex: pattern.index,
                    rowIndex: row.index
                )
                rowMappings.append(PlaybackSongSyntheticRowMapping(source: source, syntheticRow: syntheticRow))
                rowDiagnostics.append(appendEvents(
                    from: row,
                    source: source,
                    syntheticRow: syntheticRow,
                    song: song,
                    timingConfig: timingPlan.timingConfig(forSyntheticRow: syntheticRow),
                    scheduledStartFrame: timingPlan.frameFor(row: syntheticRow, tick: 0),
                    channelStates: &channelStates,
                    events: &events,
                    volumeColumnMappings: &volumeColumnMappings,
                    keyOffEvents: &keyOffEvents,
                    eventMappings: &eventMappings,
                    ignoredCells: &ignoredCells,
                    deferredCellFields: &deferredCellFields
                ))
            }

            nextSyntheticRow += pattern.rowCount
        }

        return PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: SyntheticPattern(rowCount: nextSyntheticRow, events: events),
            diagnostics: PlaybackSongSyntheticDiagnostics(
                requestedStartOrderIndex: startOrderIndex,
                requestedOrderCount: safeOrderCount,
                sampleRate: timingConfig.sampleRate,
                initialSpeed: timingConfig.speed,
                initialBPM: timingConfig.bpm,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                syntheticRowCount: nextSyntheticRow,
                adaptedOrders: adaptedOrders,
                rowMappings: rowMappings,
                rowTiming: timingPlan.rowTimingDiagnostics,
                timingChanges: timingPlan.timingChanges,
                rowDiagnostics: rowDiagnostics,
                volumeColumnMappings: volumeColumnMappings,
                keyOffEvents: keyOffEvents,
                eventMappings: eventMappings,
                ignoredCells: ignoredCells,
                deferredCellFields: deferredCellFields
            )
        )
    }

    private static func appendEvents(
        from row: PlaybackRow,
        source: PlaybackPosition,
        syntheticRow: Int,
        song: PlaybackSong,
        timingConfig: SyntheticTrackerTimingConfig,
        scheduledStartFrame: Int,
        channelStates: inout [Int: ChannelState],
        events: inout [SyntheticTrackerEvent],
        volumeColumnMappings: inout [PlaybackSongSyntheticVolumeColumnMapping],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) -> PlaybackSongSyntheticRowDiagnostic {
        let eventStartCount = events.count
        let ignoredStartCount = ignoredCells.count
        for (channelIndex, cell) in row.cells.enumerated() {
            var channelState = channelStates[channelIndex] ?? ChannelState()
            let volumeColumn = applyVolumeColumn(
                PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
                to: &channelState
            )
            channelStates[channelIndex] = channelState
            if cell.volumeColumn != 0 {
                volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    volumeColumn: volumeColumn
                ))
            }
            appendDeferredFields(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                volumeColumn: volumeColumn,
                includeKeyOff: false,
                deferredCellFields: &deferredCellFields
            )
            if cell.note == 97 {
                handleKeyOff(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledStartFrame: scheduledStartFrame,
                    volumeColumn: volumeColumn,
                    cell: cell,
                    channelState: &channelState,
                    events: &events,
                    keyOffEvents: &keyOffEvents,
                    eventMappings: &eventMappings,
                    ignoredCells: &ignoredCells,
                    deferredCellFields: &deferredCellFields
                )
                channelStates[channelIndex] = channelState
                continue
            }
            guard (1...96).contains(cell.note) else {
                ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    note: cell.note,
                    instrumentIndex: Int(cell.instrument),
                    reason: ignoredNoteReason(cell.note),
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffect(cell)
                ))
                continue
            }

            let instrumentIndex = Int(cell.instrument)
            guard let instrument = song.instrument(forInstrument: instrumentIndex) else {
                ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    note: cell.note,
                    instrumentIndex: instrumentIndex,
                    reason: .missingInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffect(cell)
                ))
                continue
            }
            guard let sample = instrument.firstPlayableSample else {
                ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    note: cell.note,
                    instrumentIndex: instrumentIndex,
                    reason: .noPlayableSample,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffect(cell)
                ))
                continue
            }

            let eventIndex = events.count
            let loop = mixerLoop(from: sample)
            let envelopeMapping = mixerVolumeEnvelope(
                from: instrument.volumeEnvelope,
                timingConfig: timingConfig
            )
            let envelopeSemantics = volumeEnvelopeSemantics(
                from: instrument.volumeEnvelope,
                mapping: envelopeMapping
            )
            let pitchMapping = playbackStepMapping(
                note: cell.note,
                sample: sample,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                timingConfig: timingConfig
            )
            let gain = adaptedGain(sampleVolume: sample.volume, channelVolume: channelState.volumeValue)
            let pan = channelState.pan
            events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: 0,
                scheduledStartFrame: scheduledStartFrame,
                sample: MixerSampleBuffer(monoPCM: sample.pcm),
                gain: gain,
                pan: pan,
                playbackStep: pitchMapping.playbackStep,
                loop: loop,
                volumeEnvelope: envelopeMapping.envelope
            ))
            channelState.activeEventIndex = eventIndex
            channelState.activeEventMappingIndex = eventMappings.count
            channelStates[channelIndex] = channelState
            eventMappings.append(PlaybackSongSyntheticEventMapping(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                eventIndex: eventIndex,
                loopMode: loop.mode,
                volumeColumn: volumeColumn,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffect(cell),
                effectiveVolumeValue: channelState.volumeValue,
                effectivePan: pan,
                volumeEnvelopeStatus: envelopeMapping.status,
                sourceVolumeEnvelopePointCount: envelopeMapping.sourcePointCount,
                mappedVolumeEnvelopePointCount: envelopeMapping.mappedPointCount,
                hasDeferredVolumeEnvelopeSustain: envelopeSemantics.sustainDeferred,
                hasDeferredVolumeEnvelopeLoop: envelopeSemantics.loopDeferred,
                hasDeferredVolumeEnvelopeFadeout: envelopeSemantics.fadeoutDeferred,
                volumeEnvelopeSemantics: envelopeSemantics,
                sampleBaseSampleRate: sample.baseSampleRate,
                sampleRelativeNote: sample.relativeNote,
                sampleFinetune: sample.finetune,
                outputSampleRate: pitchMapping.outputSampleRate,
                effectiveNoteValue: pitchMapping.effectiveNoteValue,
                effectiveNoteIndex: pitchMapping.effectiveNoteIndex,
                effectiveFinetune: pitchMapping.effectiveFinetune,
                linearPeriod: pitchMapping.linearPeriod,
                linearFrequency: pitchMapping.linearFrequency,
                finetuneStatus: pitchMapping.finetuneStatus,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                frequencyTableStatus: pitchMapping.frequencyTableStatus,
                linearFrequencyApplied: pitchMapping.linearFrequencyApplied,
                amigaFrequencyDeferred: pitchMapping.amigaFrequencyDeferred,
                playbackStep: pitchMapping.playbackStep,
                pitchMappingApplied: pitchMapping.applied,
                pitchMappingUsedNeutralStep: pitchMapping.usedNeutralStep
            ))
        }
        return PlaybackSongSyntheticRowDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            cellCount: row.cells.count,
            emittedEventCount: events.count - eventStartCount,
            ignoredCellCount: ignoredCells.count - ignoredStartCount
        )
    }

    private static func applyVolumeColumn(
        _ volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        to state: inout ChannelState
    ) -> PlaybackSongSyntheticVolumeColumnDiagnostic {
        switch volumeColumn.command {
        case let .setVolume(value):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(value)
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideDown(amount),
             let .fineVolumeSlideDown(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before - amount)
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .volumeSlideUp(amount),
             let .fineVolumeSlideUp(amount):
            let before = state.volumeValue
            state.volumeValue = clampedVolumeValue(before + amount)
            return volumeColumn.withAppliedState(
                appliedVolumeValue: state.volumeValue,
                appliedGainMultiplier: volumeMultiplier(for: state.volumeValue),
                effectiveVolumeBefore: before,
                effectiveVolumeAfter: state.volumeValue,
                behavior: .rowLevelApproximation
            )
        case let .setPanning(value):
            let before = state.pan
            state.panningValue = clampedPanningValue(Double(value))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideLeft(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue - Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case let .panningSlideRight(amount):
            let before = state.pan
            state.panningValue = clampedPanningValue(state.panningValue + Double(amount))
            return volumeColumn.withAppliedState(
                appliedPanningValue: Int(state.panningValue.rounded()),
                appliedPan: state.pan,
                effectivePanBefore: before,
                effectivePanAfter: state.pan,
                behavior: .rowLevelApproximation
            )
        case .none,
             .setVibratoSpeed,
             .vibrato,
             .tonePortamento,
             .unsupported:
            return volumeColumn
        }
    }

    private static func appendDeferredFields(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        includeKeyOff: Bool,
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) {
        if volumeColumn.deferred {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .volumeColumn
            ))
        }
        if hasDeferredEffect(cell) {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .effect
            ))
        }
        if includeKeyOff, cell.note == 97 {
            deferredCellFields.append(PlaybackSongSyntheticDeferredCellField(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                volumeColumn: cell.volumeColumn,
                volumeColumnDiagnostic: volumeColumn,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                field: .keyOff
            ))
        }
    }

    private static func handleKeyOff(
        source: PlaybackPosition,
        channelIndex: Int,
        syntheticRow: Int,
        scheduledStartFrame: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
        cell: PlaybackCell,
        channelState: inout ChannelState,
        events: inout [SyntheticTrackerEvent],
        keyOffEvents: inout [PlaybackSongSyntheticKeyOffDiagnostic],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) {
        guard let activeEventIndex = channelState.activeEventIndex,
              let activeEventMappingIndex = channelState.activeEventMappingIndex,
              events.indices.contains(activeEventIndex),
              eventMappings.indices.contains(activeEventMappingIndex),
              scheduledStartFrame >= (events[activeEventIndex].scheduledStartFrame ?? 0) else {
            keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                releaseFrame: nil,
                applied: false,
                deferred: true,
                reason: .noActiveVoice,
                activeEventIndex: nil
            ))
            ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: Int(cell.instrument),
                reason: .keyOff,
                volumeColumn: volumeColumn,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffect(cell)
            ))
            appendDeferredFields(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                volumeColumn: volumeColumn,
                includeKeyOff: true,
                deferredCellFields: &deferredCellFields
            )
            return
        }

        let previousMapping = eventMappings[activeEventMappingIndex]
        let fadeoutDecrement = fadeoutFrameDecrement(
            fadeoutValue: previousMapping.volumeEnvelopeSemantics.fadeoutValue,
            sampleRate: previousMapping.outputSampleRate
        )
        events[activeEventIndex] = events[activeEventIndex].withKeyOffFrame(
            scheduledStartFrame,
            fadeoutFrameDecrement: fadeoutDecrement
        )
        eventMappings[activeEventMappingIndex] = eventMapping(
            previousMapping,
            applying: previousMapping.volumeEnvelopeSemantics.applyingKeyOff(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                syntheticTick: 0,
                releaseFrame: scheduledStartFrame
            )
        )
        keyOffEvents.append(PlaybackSongSyntheticKeyOffDiagnostic(
            source: source,
            channelIndex: channelIndex,
            syntheticRow: syntheticRow,
            syntheticTick: 0,
            releaseFrame: scheduledStartFrame,
            applied: true,
            deferred: false,
            reason: .releasedActiveVoice,
            activeEventIndex: activeEventIndex
        ))
        channelState.activeEventIndex = nil
        channelState.activeEventMappingIndex = nil
    }

    private static func eventMapping(
        _ mapping: PlaybackSongSyntheticEventMapping,
        applying semantics: PlaybackSongSyntheticEnvelopeSemanticsDiagnostic
    ) -> PlaybackSongSyntheticEventMapping {
        PlaybackSongSyntheticEventMapping(
            source: mapping.source,
            channelIndex: mapping.channelIndex,
            note: mapping.note,
            instrumentIndex: mapping.instrumentIndex,
            sampleIndex: mapping.sampleIndex,
            syntheticRow: mapping.syntheticRow,
            syntheticTick: mapping.syntheticTick,
            eventIndex: mapping.eventIndex,
            loopMode: mapping.loopMode,
            volumeColumn: mapping.volumeColumn,
            hasIgnoredVolumeColumn: mapping.hasIgnoredVolumeColumn,
            hasIgnoredEffect: mapping.hasIgnoredEffect,
            effectiveVolumeValue: mapping.effectiveVolumeValue,
            effectivePan: mapping.effectivePan,
            volumeEnvelopeStatus: mapping.volumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: mapping.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: mapping.mappedVolumeEnvelopePointCount,
            hasDeferredVolumeEnvelopeSustain: semantics.sustainDeferred,
            hasDeferredVolumeEnvelopeLoop: semantics.loopDeferred,
            hasDeferredVolumeEnvelopeFadeout: semantics.fadeoutDeferred,
            volumeEnvelopeSemantics: semantics,
            sampleBaseSampleRate: mapping.sampleBaseSampleRate,
            sampleRelativeNote: mapping.sampleRelativeNote,
            sampleFinetune: mapping.sampleFinetune,
            outputSampleRate: mapping.outputSampleRate,
            effectiveNoteValue: mapping.effectiveNoteValue,
            effectiveNoteIndex: mapping.effectiveNoteIndex,
            effectiveFinetune: mapping.effectiveFinetune,
            linearPeriod: mapping.linearPeriod,
            linearFrequency: mapping.linearFrequency,
            finetuneStatus: mapping.finetuneStatus,
            usesLinearFrequencyTable: mapping.usesLinearFrequencyTable,
            frequencyTableStatus: mapping.frequencyTableStatus,
            linearFrequencyApplied: mapping.linearFrequencyApplied,
            amigaFrequencyDeferred: mapping.amigaFrequencyDeferred,
            playbackStep: mapping.playbackStep,
            pitchMappingApplied: mapping.pitchMappingApplied,
            pitchMappingUsedNeutralStep: mapping.pitchMappingUsedNeutralStep
        )
    }

    private struct VolumeEnvelopeMapping: Equatable {
        let envelope: MixerEnvelope?
        let status: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus
        let sourcePointCount: Int
        let mappedPointCount: Int
        let sustainFrame: Int?
        let loopStartFrame: Int?
        let loopEndFrame: Int?
    }

    private struct PlaybackStepMapping: Equatable {
        let playbackStep: Double
        let outputSampleRate: Double
        let effectiveNoteValue: Int?
        let effectiveNoteIndex: Int?
        let effectiveFinetune: Int?
        let linearPeriod: Double?
        let linearFrequency: Double?
        let finetuneStatus: PlaybackSongSyntheticEventMapping.FinetuneStatus
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus
        let linearFrequencyApplied: Bool
        let amigaFrequencyDeferred: Bool
        let applied: Bool
        let usedNeutralStep: Bool
    }

    private static func adaptedGain(
        sampleVolume: Float,
        channelVolume: Int
    ) -> Float {
        let baseGain = sampleVolume.isFinite ? sampleVolume : 0
        let volumeMultiplier = volumeMultiplier(for: channelVolume)
        // The bounded adapter treats supported XM volume-column volume commands as row-level
        // channel-volume updates: final event gain = sample volume * (channel volume / 64).
        // Parsed volume envelopes remain separate C mixer envelopes and multiply this gain at render time.
        return clampedGain(baseGain * volumeMultiplier)
    }

    private static func volumeMultiplier(for volumeValue: Int) -> Float {
        Float(clampedVolumeValue(volumeValue)) / 64.0
    }

    private static func clampedVolumeValue(_ value: Int) -> Int {
        min(64, max(0, value))
    }

    private static func clampedPanningValue(_ value: Double) -> Double {
        min(255.0, max(0.0, value.isFinite ? value : 127.5))
    }

    private static func clampedGain(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0
        }
        return min(1, max(0, value))
    }

    private static func playbackStepMapping(
        note: UInt8,
        sample: PlaybackSample,
        usesLinearFrequencyTable: Bool,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> PlaybackStepMapping {
        let outputSampleRate = timingConfig.sampleRate
        guard usesLinearFrequencyTable else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: nil,
                effectiveNoteIndex: nil,
                effectiveFinetune: nil,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .amigaTableDeferredNeutralFallback,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: true,
                applied: false,
                usedNeutralStep: true
            )
        }

        let baseSampleRate = sample.baseSampleRate
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: nil,
                effectiveNoteIndex: nil,
                effectiveFinetune: nil,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        let effectiveNoteValue = clampedEffectiveNoteValue(note: note, relativeNote: sample.relativeNote)
        let effectiveNoteIndex = effectiveNoteValue - 1
        let effectiveFinetune = clampedFinetune(sample.finetune)

        // XM linear frequency mode is period based even though the C mixer consumes a source-sample step.
        // FT2's linear period formula is:
        // period = 7680 - (zeroBasedNote * 64) - (finetune / 2)
        // C-4 is note value 49, zero-based note 48, period 4608, so it maps to the sample base rate.
        let linearPeriod = xmLinearPeriodBase
            - (Double(effectiveNoteIndex) * xmLinearPeriodUnitsPerSemitone)
            - (Double(effectiveFinetune) / 2.0)
        let linearFrequency = baseSampleRate * pow(
            2.0,
            (xmLinearC4Period - linearPeriod) / xmLinearPeriodUnitsPerOctave
        )
        let step = linearFrequency / outputSampleRate
        guard linearPeriod.isFinite,
              linearFrequency.isFinite,
              linearFrequency > 0,
              step.isFinite,
              step > 0,
              step <= Double(UInt32.max) else {
            return PlaybackStepMapping(
                playbackStep: 1,
                outputSampleRate: outputSampleRate,
                effectiveNoteValue: effectiveNoteValue,
                effectiveNoteIndex: effectiveNoteIndex,
                effectiveFinetune: effectiveFinetune,
                linearPeriod: nil,
                linearFrequency: nil,
                finetuneStatus: .deferred,
                frequencyTableStatus: .linearApplied,
                linearFrequencyApplied: false,
                amigaFrequencyDeferred: false,
                applied: false,
                usedNeutralStep: true
            )
        }

        return PlaybackStepMapping(
            playbackStep: step,
            outputSampleRate: outputSampleRate,
            effectiveNoteValue: effectiveNoteValue,
            effectiveNoteIndex: effectiveNoteIndex,
            effectiveFinetune: effectiveFinetune,
            linearPeriod: linearPeriod,
            linearFrequency: linearFrequency,
            finetuneStatus: .applied,
            frequencyTableStatus: .linearApplied,
            linearFrequencyApplied: true,
            amigaFrequencyDeferred: false,
            applied: true,
            usedNeutralStep: abs(step - 1.0) <= 0.000000001
        )
    }

    private static func clampedEffectiveNoteValue(note: UInt8, relativeNote: Int) -> Int {
        min(96, max(1, Int(note) + relativeNote))
    }

    private static func clampedFinetune(_ finetune: Int) -> Int {
        min(127, max(-128, finetune))
    }

    private static func mixerVolumeEnvelope(
        from envelope: PlaybackVolumeEnvelope,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> VolumeEnvelopeMapping {
        guard hasVolumeEnvelopeMetadata(envelope) else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .absent,
                sourcePointCount: 0,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }
        guard envelope.enabled else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .disabled,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        let sourcePoints = Array(envelope.points.prefix(maxMixerEnvelopePointCount))
        guard !sourcePoints.isEmpty else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: 0,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        let timing = SyntheticTrackerTiming(config: timingConfig)
        guard timing.framesPerTick.isFinite, timing.framesPerTick > 0 else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0,
                sustainFrame: nil,
                loopStartFrame: nil,
                loopEndFrame: nil
            )
        }

        var mappedPoints = [MixerEnvelopePoint]()
        mappedPoints.reserveCapacity(sourcePoints.count)
        for point in sourcePoints {
            let exactFrame = Double(point.tick) * timing.framesPerTick
            guard exactFrame.isFinite, exactFrame >= 0, exactFrame < Double(Int.max) else {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0,
                    sustainFrame: nil,
                    loopStartFrame: nil,
                    loopEndFrame: nil
                )
            }
            let frame = Int(exactFrame.rounded(.down))
            if let previous = mappedPoints.last, frame <= previous.positionFrame {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0,
                    sustainFrame: nil,
                    loopStartFrame: nil,
                    loopEndFrame: nil
                )
            }
            mappedPoints.append(MixerEnvelopePoint(positionFrame: frame, value: point.normalizedValue))
        }
        let sustainFrame = mappedFrame(
            forSourcePointIndex: envelope.sustainPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let loopStartFrame = mappedFrame(
            forSourcePointIndex: envelope.loopStartPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let loopEndFrame = mappedFrame(
            forSourcePointIndex: envelope.loopEndPointIndex,
            sourcePoints: sourcePoints,
            mappedPoints: mappedPoints
        )
        let appliedSustainFrame = envelopeSustainFlagSet(envelope) ? sustainFrame : nil
        let appliedLoopStartFrame: Int?
        let appliedLoopEndFrame: Int?
        if envelopeLoopFlagSet(envelope),
           let loopStartFrame,
           let loopEndFrame,
           loopEndFrame >= loopStartFrame {
            appliedLoopStartFrame = loopStartFrame
            appliedLoopEndFrame = loopEndFrame
        } else {
            appliedLoopStartFrame = nil
            appliedLoopEndFrame = nil
        }

        return VolumeEnvelopeMapping(
            envelope: MixerEnvelope(
                points: mappedPoints,
                sustainFrame: appliedSustainFrame,
                loopStartFrame: appliedLoopStartFrame,
                loopEndFrame: appliedLoopEndFrame
            ),
            status: .mapped,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mappedPoints.count,
            sustainFrame: appliedSustainFrame,
            loopStartFrame: appliedLoopStartFrame,
            loopEndFrame: appliedLoopEndFrame
        )
    }

    private static func mappedFrame(
        forSourcePointIndex pointIndex: Int?,
        sourcePoints: [PlaybackEnvelopePoint],
        mappedPoints: [MixerEnvelopePoint]
    ) -> Int? {
        guard let pointIndex,
              sourcePoints.indices.contains(pointIndex),
              mappedPoints.indices.contains(pointIndex) else {
            return nil
        }
        return mappedPoints[pointIndex].positionFrame
    }

    private static func hasVolumeEnvelopeMetadata(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        envelope.enabled ||
            !envelope.points.isEmpty ||
            envelope.typeFlags != 0 ||
            envelope.sustainPointIndex != nil ||
            envelope.loopStartPointIndex != nil ||
            envelope.loopEndPointIndex != nil ||
            envelope.fadeout > 0
    }

    private static func volumeEnvelopeSemantics(
        from envelope: PlaybackVolumeEnvelope,
        mapping: VolumeEnvelopeMapping
    ) -> PlaybackSongSyntheticEnvelopeSemanticsDiagnostic {
        let sustainEnabled = envelopeSustainFlagSet(envelope)
        let loopEnabled = envelopeLoopFlagSet(envelope)
        let sustainApplied = mapping.status == .mapped && sustainEnabled && mapping.sustainFrame != nil
        let loopApplied = mapping.status == .mapped && loopEnabled && mapping.loopStartFrame != nil && mapping.loopEndFrame != nil
        var limitations = [String]()
        if sustainApplied || loopApplied || envelope.fadeout > 0 {
            limitations.append("first_pass_bounded_offline_envelope_approximation")
        }
        if sustainApplied {
            limitations.append("sustain_holds_at_mapped_frame_while_keyed_on")
        }
        if loopApplied {
            limitations.append("envelope_loop_is_frame_based_while_keyed_on")
        }
        if envelope.fadeout > 0 {
            limitations.append("fadeout_uses_linear_per_frame_decrement_after_key_off")
        }

        return PlaybackSongSyntheticEnvelopeSemanticsDiagnostic(
            envelopeEnabled: envelope.enabled,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mapping.mappedPointCount,
            sustainEnabled: sustainEnabled,
            sustainApplied: sustainApplied,
            sustainDeferred: sustainEnabled && !sustainApplied,
            sustainPointIndex: envelope.sustainPointIndex,
            sustainTick: envelope.sustainPoint?.tick,
            sustainFrame: mapping.sustainFrame,
            loopEnabled: loopEnabled,
            loopApplied: loopApplied,
            loopDeferred: loopEnabled && !loopApplied,
            loopStartPointIndex: envelope.loopStartPointIndex,
            loopEndPointIndex: envelope.loopEndPointIndex,
            loopStartTick: envelope.loopStartPoint?.tick,
            loopEndTick: envelope.loopEndPoint?.tick,
            loopStartFrame: mapping.loopStartFrame,
            loopEndFrame: mapping.loopEndFrame,
            keyOffEncountered: false,
            keyOffApplied: false,
            keyOffDeferred: false,
            keyOffSource: nil,
            keyOffChannelIndex: nil,
            keyOffSyntheticRow: nil,
            keyOffSyntheticTick: nil,
            releaseFrame: nil,
            fadeoutValue: envelope.fadeout,
            fadeoutApplied: false,
            fadeoutDeferred: envelope.fadeout > 0,
            limitations: limitations
        )
    }

    private static func envelopeSustainFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x02) != 0
    }

    private static func envelopeLoopFlagSet(_ envelope: PlaybackVolumeEnvelope) -> Bool {
        (envelope.typeFlags & 0x04) != 0
    }

    private static func fadeoutFrameDecrement(fadeoutValue: Int, sampleRate: Double) -> Float {
        guard fadeoutValue > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        // First-pass offline approximation: spread the XM tick-domain fadeout decrement
        // smoothly across one default-speed tick worth of output frames.
        let framesPerDefaultTick = sampleRate * PlaybackTiming.xmDefault.tickDuration
        guard framesPerDefaultTick.isFinite, framesPerDefaultTick > 0 else {
            return 0
        }
        return Float((Double(fadeoutValue) / 65_536.0) / framesPerDefaultTick)
    }

    private static func hasEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType != 0 || cell.effectParam != 0
    }

    private static func hasDeferredEffect(_ cell: PlaybackCell) -> Bool {
        hasEffect(cell) && !PlaybackSongFxxTimingPlanner.isFxxTimingEffect(cell)
    }

    private static func ignoredNoteReason(_ note: UInt8) -> PlaybackSongSyntheticIgnoredCell.Reason {
        switch note {
        case 0:
            return .emptyNote
        case 97:
            return .keyOff
        default:
            return .invalidNote
        }
    }

    private static func mixerLoop(from sample: PlaybackSample) -> MixerSampleLoop {
        let region = sample.loopRegion
        guard region.isEnabled else {
            return .none
        }
        switch region.loopType {
        case 1:
            return MixerSampleLoop(mode: .forward, startFrame: region.startFrame, endFrame: region.endFrame)
        case 2:
            return MixerSampleLoop(mode: .pingPong, startFrame: region.startFrame, endFrame: region.endFrame)
        default:
            return .none
        }
    }
}

/// Bounded offline render request for adapted `PlaybackSong` segments.
///
/// Oversized requests are clamped to `maximumFrameCount`, matching the existing software mixer offline
/// harness. This helper is offline-only and does not affect live `AVAudioPlayerNode` playback.
struct PlaybackSongOfflineRenderRequest: Equatable {
    static let defaultMaximumFrameCount = OfflineRenderRequest.defaultMaximumFrameCount

    let song: PlaybackSong
    let startOrderIndex: Int
    let orderCount: Int
    let config: MixerRenderConfig
    let requestedFrameCount: Int
    let maximumFrameCount: Int

    var boundedFrameCount: Int {
        min(requestedFrameCount, maximumFrameCount)
    }

    var wasFrameCountBounded: Bool {
        requestedFrameCount > maximumFrameCount
    }

    init(
        song: PlaybackSong,
        startOrderIndex: Int = 0,
        orderCount: Int = 1,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.song = song
        self.startOrderIndex = startOrderIndex
        self.orderCount = max(0, orderCount)
        self.config = config
        requestedFrameCount = max(0, frames)
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    init(
        song: PlaybackSong,
        orderIndex: Int,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.init(
            song: song,
            startOrderIndex: orderIndex,
            orderCount: 1,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        )
    }

    init(
        song: PlaybackSong,
        orderRange: Range<Int>,
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.init(
            song: song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: orderRange.count,
            config: config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        )
    }

    init(
        song: PlaybackSong,
        startOrderIndex: Int = 0,
        orderCount: Int = 1,
        config: MixerRenderConfig = MixerRenderConfig(),
        rows: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        let timing = PlaybackSongFxxTimingPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            sampleRate: config.sampleRate
        )
        self.init(
            song: song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            config: config,
            frames: timing.frameFor(row: max(0, rows), tick: 0),
            maximumFrameCount: maximumFrameCount
        )
    }

    func replacingFrameCount(_ frameCount: Int, maximumFrameCount: Int? = nil) -> PlaybackSongOfflineRenderRequest {
        PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount,
            config: config,
            frames: frameCount,
            maximumFrameCount: maximumFrameCount ?? self.maximumFrameCount
        )
    }
}

/// Result from rendering an adapted `PlaybackSong` segment through the C-backed offline mixer.
struct PlaybackSongOfflineRenderResult: Equatable {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let block: MixerRenderBlock
    let scheduledVoiceIndices: [Int?]

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    var requestedFrameCount: Int {
        request.requestedFrameCount
    }

    var renderedFrameCount: Int {
        block.frameCount
    }

    var maximumFrameCount: Int {
        request.maximumFrameCount
    }

    var wasFrameCountBounded: Bool {
        request.wasFrameCountBounded
    }
}

/// Prepared offline render session for split renders and reset determinism checks.
final class PlaybackSongOfflineRenderSession {
    let request: PlaybackSongOfflineRenderRequest
    let plan: PlaybackSongSyntheticPlan
    let scheduledVoiceIndices: [Int?]

    private let mixer: CSoftwareMixer
    private var renderedFrameCount = 0

    var config: MixerRenderConfig {
        mixer.config
    }

    var diagnostics: PlaybackSongSyntheticDiagnostics {
        plan.diagnostics
    }

    init(request: PlaybackSongOfflineRenderRequest) {
        self.request = request
        let adaptedPlan = PlaybackSongSyntheticAdapter.adapt(
            request.song,
            startOrderIndex: request.startOrderIndex,
            orderCount: request.orderCount,
            sampleRate: request.config.sampleRate
        )
        let preparedMixer = CSoftwareMixer(config: request.config)
        let voiceIndices = SyntheticPatternScheduler(config: adaptedPlan.timingConfig).schedule(adaptedPlan.pattern, on: preparedMixer)
        plan = adaptedPlan
        mixer = preparedMixer
        scheduledVoiceIndices = voiceIndices
    }

    func render(frames: Int) -> MixerRenderBlock {
        let requestedFrames = max(0, frames)
        let remainingFrames = max(0, request.boundedFrameCount - renderedFrameCount)
        let frameCount = min(requestedFrames, remainingFrames)
        let block = mixer.render(frames: frameCount)
        renderedFrameCount += block.frameCount
        return block
    }

    func reset() {
        mixer.reset()
        renderedFrameCount = 0
    }
}

/// Offline renderer for tiny bounded `PlaybackSong` adapter segments.
///
/// This renderer adapts a bounded playback-model order selection, schedules the resulting synthetic pattern
/// through `CSoftwareMixer`, and returns the in-memory PCM block with adapter diagnostics. It intentionally
/// does not implement full XM playback, FT2/OpenMPT resampler parity, effect-column commands beyond minimal
/// `Fxx`, full volume-column semantics, full FT2/OpenMPT envelope parity, runtime backend switching,
/// or app Play button wiring.
final class PlaybackSongOfflineRenderer {
    let maximumFrameCount: Int

    init(maximumFrameCount: Int = PlaybackSongOfflineRenderRequest.defaultMaximumFrameCount) {
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    func prepare(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderSession {
        PlaybackSongOfflineRenderSession(request: effectiveRequest(from: request, frames: request.requestedFrameCount))
    }

    func render(_ request: PlaybackSongOfflineRenderRequest) -> PlaybackSongOfflineRenderResult {
        let effectiveRequest = effectiveRequest(from: request, frames: request.requestedFrameCount)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: session.render(frames: effectiveRequest.boundedFrameCount),
            scheduledVoiceIndices: session.scheduledVoiceIndices
        )
    }

    func render(_ request: PlaybackSongOfflineRenderRequest, splitFrameCounts: [Int]) -> PlaybackSongOfflineRenderResult {
        let requestedFrames = splitFrameCounts.reduce(0) { partialResult, frames in
            let safeFrames = max(0, frames)
            guard partialResult <= Int.max - safeFrames else {
                return Int.max
            }
            return partialResult + safeFrames
        }
        let effectiveRequest = effectiveRequest(from: request, frames: requestedFrames)
        let session = PlaybackSongOfflineRenderSession(request: effectiveRequest)
        var remainingFrames = effectiveRequest.boundedFrameCount
        var interleavedPCM = [Float]()
        for requestedChunkFrames in splitFrameCounts where remainingFrames > 0 {
            let chunkFrames = min(max(0, requestedChunkFrames), remainingFrames)
            let chunk = session.render(frames: chunkFrames)
            interleavedPCM.append(contentsOf: chunk.interleavedPCM)
            remainingFrames -= chunk.frameCount
        }
        let block = MixerRenderBlock(
            config: session.config,
            frameCount: effectiveRequest.boundedFrameCount - remainingFrames,
            interleavedPCM: interleavedPCM
        )
        return PlaybackSongOfflineRenderResult(
            request: effectiveRequest,
            plan: session.plan,
            block: block,
            scheduledVoiceIndices: session.scheduledVoiceIndices
        )
    }

    /// Renders a bounded adapted `PlaybackSong` segment through the offline C-backed mixer and writes PCM16 WAV.
    ///
    /// This is a local comparison helper only. It reuses the existing bounded render path and does not parse
    /// modules, traverse full songs, compare against reference renderers, or change live playback.
    @discardableResult
    func exportWAV(
        _ request: PlaybackSongOfflineRenderRequest,
        to url: URL
    ) throws -> PlaybackSongOfflineRenderResult {
        let result = render(request)
        try MixerWAVExporter.writePCM16WAV(from: result.block, to: url)
        return result
    }

    private func effectiveRequest(
        from request: PlaybackSongOfflineRenderRequest,
        frames: Int
    ) -> PlaybackSongOfflineRenderRequest {
        request.replacingFrameCount(
            frames,
            maximumFrameCount: min(request.maximumFrameCount, maximumFrameCount)
        )
    }
}
