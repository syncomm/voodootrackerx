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
    let rowDiagnostics: [PlaybackSongSyntheticRowDiagnostic]
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
            return diagnostic(rawValue: rawValue, command: .volumeSlideDown(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0x70...0x7F:
            return diagnostic(rawValue: rawValue, command: .volumeSlideUp(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0x80...0x8F:
            return diagnostic(rawValue: rawValue, command: .fineVolumeSlideDown(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0x90...0x9F:
            return diagnostic(rawValue: rawValue, command: .fineVolumeSlideUp(amount: Int(rawValue & 0x0F)), classification: .deferred)
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
            return diagnostic(rawValue: rawValue, command: .panningSlideLeft(amount: Int(rawValue & 0x0F)), classification: .deferred)
        case 0xE0...0xEF:
            return diagnostic(rawValue: rawValue, command: .panningSlideRight(amount: Int(rawValue & 0x0F)), classification: .deferred)
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
        appliedPan: Float? = nil
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
            appliedPan: appliedPan
        )
    }

    private static func audioPan(forXMValue value: Int) -> Float {
        (Float(min(255, max(0, value))) / 127.5) - 1.0
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
        case amigaTableDeferredLinearApproximation
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
    let volumeEnvelopeStatus: VolumeEnvelopeStatus
    let sourceVolumeEnvelopePointCount: Int
    let mappedVolumeEnvelopePointCount: Int
    let hasDeferredVolumeEnvelopeSustain: Bool
    let hasDeferredVolumeEnvelopeLoop: Bool
    let hasDeferredVolumeEnvelopeFadeout: Bool
    let sampleBaseSampleRate: Double
    let sampleRelativeNote: Int
    let sampleFinetune: Int
    let finetuneStatus: FinetuneStatus
    let usesLinearFrequencyTable: Bool
    let frequencyTableStatus: FrequencyTableStatus
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

enum PlaybackSongSyntheticAdapter {
    private static let maxMixerEnvelopePointCount = 12

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
        let timingConfig = SyntheticTrackerTimingConfig(
            speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm,
            sampleRate: sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var adaptedOrders = [PlaybackSongSyntheticOrderDiagnostic]()
        var rowMappings = [PlaybackSongSyntheticRowMapping]()
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
        var deferredCellFields = [PlaybackSongSyntheticDeferredCellField]()
        var events = [SyntheticTrackerEvent]()
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
                    timingConfig: timingConfig,
                    events: &events,
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
                rowDiagnostics: rowDiagnostics,
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
        events: inout [SyntheticTrackerEvent],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell],
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) -> PlaybackSongSyntheticRowDiagnostic {
        let eventStartCount = events.count
        let ignoredStartCount = ignoredCells.count
        for (channelIndex, cell) in row.cells.enumerated() {
            let volumeColumn = PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn)
            appendDeferredFields(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                volumeColumn: volumeColumn,
                deferredCellFields: &deferredCellFields
            )
            guard (1...96).contains(cell.note) else {
                ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    note: cell.note,
                    instrumentIndex: Int(cell.instrument),
                    reason: ignoredNoteReason(cell.note),
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0,
                    hasIgnoredEffect: hasEffect(cell)
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
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0,
                    hasIgnoredEffect: hasEffect(cell)
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
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0,
                    hasIgnoredEffect: hasEffect(cell)
                ))
                continue
            }

            let eventIndex = events.count
            let loop = mixerLoop(from: sample)
            let envelopeMapping = mixerVolumeEnvelope(
                from: instrument.volumeEnvelope,
                timingConfig: timingConfig
            )
            let pitchMapping = playbackStepMapping(
                note: cell.note,
                sample: sample,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                timingConfig: timingConfig
            )
            let gain = adaptedGain(sampleVolume: sample.volume, volumeColumn: volumeColumn)
            let pan = volumeColumn.appliedPan ?? 0
            events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: 0,
                sample: MixerSampleBuffer(monoPCM: sample.pcm),
                gain: gain,
                pan: pan,
                playbackStep: pitchMapping.playbackStep,
                loop: loop,
                volumeEnvelope: envelopeMapping.envelope
            ))
            appendDeferredVolumeEnvelopeFields(
                from: instrument.volumeEnvelope,
                source: source,
                channelIndex: channelIndex,
                cell: cell,
                deferredCellFields: &deferredCellFields
            )
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
                hasIgnoredEffect: hasEffect(cell),
                volumeEnvelopeStatus: envelopeMapping.status,
                sourceVolumeEnvelopePointCount: envelopeMapping.sourcePointCount,
                mappedVolumeEnvelopePointCount: envelopeMapping.mappedPointCount,
                hasDeferredVolumeEnvelopeSustain: instrument.volumeEnvelope.sustainEnabled,
                hasDeferredVolumeEnvelopeLoop: instrument.volumeEnvelope.loopEnabled,
                hasDeferredVolumeEnvelopeFadeout: instrument.volumeEnvelope.fadeout > 0,
                sampleBaseSampleRate: sample.baseSampleRate,
                sampleRelativeNote: sample.relativeNote,
                sampleFinetune: sample.finetune,
                finetuneStatus: pitchMapping.finetuneStatus,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                frequencyTableStatus: pitchMapping.frequencyTableStatus,
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

    private static func appendDeferredFields(
        from cell: PlaybackCell,
        source: PlaybackPosition,
        channelIndex: Int,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic,
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
        if hasEffect(cell) {
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
        if cell.note == 97 {
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

    private static func appendDeferredVolumeEnvelopeFields(
        from envelope: PlaybackVolumeEnvelope,
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell,
        deferredCellFields: inout [PlaybackSongSyntheticDeferredCellField]
    ) {
        if envelope.sustainEnabled {
            deferredCellFields.append(deferredVolumeEnvelopeField(
                .volumeEnvelopeSustain,
                source: source,
                channelIndex: channelIndex,
                cell: cell
            ))
        }
        if envelope.loopEnabled {
            deferredCellFields.append(deferredVolumeEnvelopeField(
                .volumeEnvelopeLoop,
                source: source,
                channelIndex: channelIndex,
                cell: cell
            ))
        }
        if envelope.fadeout > 0 {
            deferredCellFields.append(deferredVolumeEnvelopeField(
                .volumeEnvelopeFadeout,
                source: source,
                channelIndex: channelIndex,
                cell: cell
            ))
        }
    }

    private static func deferredVolumeEnvelopeField(
        _ field: PlaybackSongSyntheticDeferredCellField.Field,
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell
    ) -> PlaybackSongSyntheticDeferredCellField {
        PlaybackSongSyntheticDeferredCellField(
            source: source,
            channelIndex: channelIndex,
            note: cell.note,
            instrumentIndex: Int(cell.instrument),
            volumeColumn: cell.volumeColumn,
            volumeColumnDiagnostic: PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
            effectType: cell.effectType,
            effectParam: cell.effectParam,
            field: field
        )
    }

    private struct VolumeEnvelopeMapping: Equatable {
        let envelope: MixerEnvelope?
        let status: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus
        let sourcePointCount: Int
        let mappedPointCount: Int
    }

    private struct PlaybackStepMapping: Equatable {
        let playbackStep: Double
        let finetuneStatus: PlaybackSongSyntheticEventMapping.FinetuneStatus
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus
        let applied: Bool
        let usedNeutralStep: Bool
    }

    private static func adaptedGain(
        sampleVolume: Float,
        volumeColumn: PlaybackSongSyntheticVolumeColumnDiagnostic
    ) -> Float {
        let baseGain = sampleVolume.isFinite ? sampleVolume : 0
        guard let volumeMultiplier = volumeColumn.appliedGainMultiplier else {
            return clampedGain(baseGain)
        }
        // The bounded adapter treats XM set-volume as a channel-volume multiplier:
        // final event gain = sanitized sample volume * (volume-column value / 64).
        // Parsed volume envelopes remain separate C mixer envelopes and multiply this gain at render time.
        return clampedGain(baseGain * volumeMultiplier)
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
        let frequencyTableStatus: PlaybackSongSyntheticEventMapping.FrequencyTableStatus = usesLinearFrequencyTable
            ? .linearApplied
            : .amigaTableDeferredLinearApproximation
        let outputSampleRate = timingConfig.sampleRate
        let baseSampleRate = sample.baseSampleRate
        guard outputSampleRate.isFinite,
              outputSampleRate > 0,
              baseSampleRate.isFinite,
              baseSampleRate > 0 else {
            return PlaybackStepMapping(
                playbackStep: 1,
                finetuneStatus: .deferred,
                frequencyTableStatus: frequencyTableStatus,
                applied: false,
                usedNeutralStep: true
            )
        }

        let semitoneOffset = Double(Int(note) + sample.relativeNote - PlaybackPitchCalculator.c4NoteValue)
        let finetuneSemitones = Double(sample.finetune) / 128.0
        let pitchRatio = pow(2.0, (semitoneOffset + finetuneSemitones) / 12.0)
        let step = (baseSampleRate / outputSampleRate) * pitchRatio
        guard step.isFinite,
              step > 0,
              step <= Double(UInt32.max) else {
            return PlaybackStepMapping(
                playbackStep: 1,
                finetuneStatus: .deferred,
                frequencyTableStatus: frequencyTableStatus,
                applied: false,
                usedNeutralStep: true
            )
        }

        return PlaybackStepMapping(
            playbackStep: step,
            finetuneStatus: .applied,
            frequencyTableStatus: frequencyTableStatus,
            applied: true,
            usedNeutralStep: abs(step - 1.0) <= 0.000000001
        )
    }

    private static func mixerVolumeEnvelope(
        from envelope: PlaybackVolumeEnvelope,
        timingConfig: SyntheticTrackerTimingConfig
    ) -> VolumeEnvelopeMapping {
        guard hasVolumeEnvelopeMetadata(envelope) else {
            return VolumeEnvelopeMapping(envelope: nil, status: .absent, sourcePointCount: 0, mappedPointCount: 0)
        }
        guard envelope.enabled else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .disabled,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0
            )
        }

        let sourcePoints = Array(envelope.points.prefix(maxMixerEnvelopePointCount))
        guard !sourcePoints.isEmpty else {
            return VolumeEnvelopeMapping(envelope: nil, status: .invalidOrEmptyIgnored, sourcePointCount: 0, mappedPointCount: 0)
        }

        let timing = SyntheticTrackerTiming(config: timingConfig)
        guard timing.framesPerTick.isFinite, timing.framesPerTick > 0 else {
            return VolumeEnvelopeMapping(
                envelope: nil,
                status: .invalidOrEmptyIgnored,
                sourcePointCount: envelope.points.count,
                mappedPointCount: 0
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
                    mappedPointCount: 0
                )
            }
            let frame = Int(exactFrame.rounded(.down))
            if let previous = mappedPoints.last, frame <= previous.positionFrame {
                return VolumeEnvelopeMapping(
                    envelope: nil,
                    status: .invalidOrEmptyIgnored,
                    sourcePointCount: envelope.points.count,
                    mappedPointCount: 0
                )
            }
            mappedPoints.append(MixerEnvelopePoint(positionFrame: frame, value: point.normalizedValue))
        }

        return VolumeEnvelopeMapping(
            envelope: MixerEnvelope(points: mappedPoints),
            status: .mapped,
            sourcePointCount: envelope.points.count,
            mappedPointCount: mappedPoints.count
        )
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

    private static func hasEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType != 0 || cell.effectParam != 0
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
        let timing = SyntheticTrackerTiming(config: SyntheticTrackerTimingConfig(
            speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm,
            sampleRate: config.sampleRate
        ))
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
/// does not implement full XM playback, FT2/OpenMPT pitch parity, effects, volume-column semantics,
/// sustain/loop/fadeout envelope semantics, runtime backend switching, or app Play button wiring.
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
