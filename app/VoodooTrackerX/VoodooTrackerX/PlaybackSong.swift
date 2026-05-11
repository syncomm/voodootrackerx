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
