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
    let adaptedOrders: [PlaybackSongSyntheticOrderDiagnostic]
    let rowMappings: [PlaybackSongSyntheticRowMapping]
    let eventMappings: [PlaybackSongSyntheticEventMapping]
    let ignoredCells: [PlaybackSongSyntheticIgnoredCell]

    var emittedRowCount: Int {
        rowMappings.count
    }

    var emittedEventCount: Int {
        eventMappings.count
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

struct PlaybackSongSyntheticEventMapping: Equatable {
    let source: PlaybackPosition
    let channelIndex: Int
    let note: UInt8
    let instrumentIndex: Int
    let sampleIndex: Int
    let syntheticRow: Int
    let eventIndex: Int
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
}

enum PlaybackSongSyntheticAdapter {
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
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
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
                appendEvents(
                    from: row,
                    source: source,
                    syntheticRow: syntheticRow,
                    song: song,
                    events: &events,
                    eventMappings: &eventMappings,
                    ignoredCells: &ignoredCells
                )
            }

            nextSyntheticRow += pattern.rowCount
        }

        return PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: SyntheticPattern(rowCount: nextSyntheticRow, events: events),
            diagnostics: PlaybackSongSyntheticDiagnostics(
                requestedStartOrderIndex: startOrderIndex,
                requestedOrderCount: safeOrderCount,
                adaptedOrders: adaptedOrders,
                rowMappings: rowMappings,
                eventMappings: eventMappings,
                ignoredCells: ignoredCells
            )
        )
    }

    private static func appendEvents(
        from row: PlaybackRow,
        source: PlaybackPosition,
        syntheticRow: Int,
        song: PlaybackSong,
        events: inout [SyntheticTrackerEvent],
        eventMappings: inout [PlaybackSongSyntheticEventMapping],
        ignoredCells: inout [PlaybackSongSyntheticIgnoredCell]
    ) {
        for (channelIndex, cell) in row.cells.enumerated() {
            guard (1...96).contains(cell.note) else {
                ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    note: cell.note,
                    instrumentIndex: Int(cell.instrument),
                    reason: ignoredNoteReason(cell.note)
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
                    reason: .missingInstrument
                ))
                continue
            }
            guard let sample = instrument.firstPlayableSample else {
                ignoredCells.append(PlaybackSongSyntheticIgnoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    note: cell.note,
                    instrumentIndex: instrumentIndex,
                    reason: .noPlayableSample
                ))
                continue
            }

            let eventIndex = events.count
            events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: 0,
                sample: MixerSampleBuffer(monoPCM: sample.pcm),
                gain: sample.volume,
                pan: 0,
                loop: mixerLoop(from: sample)
            ))
            eventMappings.append(PlaybackSongSyntheticEventMapping(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                syntheticRow: syntheticRow,
                eventIndex: eventIndex
            ))
        }
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
