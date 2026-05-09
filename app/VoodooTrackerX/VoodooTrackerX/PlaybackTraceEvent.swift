import Foundation

enum PlaybackTraceDecision: String, Codable, Equatable {
    case observed
    case updated
    case triggered
    case delayed
    case cut
    case retriggered
    case ignored
}

struct PlaybackTraceEvent: Encodable, Equatable {
    let schemaVersion: Int
    let tickIndex: UInt64
    let orderIndex: Int
    let patternIndex: Int
    let rowIndex: Int
    let tickInRow: Int
    let channelIndex: Int
    let speed: Int
    let bpm: Int
    let tickDuration: TimeInterval
    let rowDuration: TimeInterval
    let usesLinearFrequencyTable: Bool?
    let noteValue: UInt8?
    let instrumentIndex: Int?
    let sampleIndex: Int?
    let relativeNote: Int?
    let finetune: Int?
    let sourceSampleRate: Double?
    let effectCommand: String
    let effectParameter: String
    let effect: String
    let computedVolume: Float?
    let computedPanning: Float?
    let computedPitchSemitones: Double?
    let computedRate: Double?
    let computedFrequency: Double?
    let computedVarispeedRate: Double?
    let computedPeriodApproximation: Double?
    let sampleOffset: Int?
    let sampleLength: Int?
    let loopStart: Int?
    let loopLength: Int?
    let loopType: Int?
    let decision: PlaybackTraceDecision
    let decisionReason: String?

    init(
        schemaVersion: Int = 1,
        tickIndex: UInt64,
        orderIndex: Int,
        patternIndex: Int,
        rowIndex: Int,
        tickInRow: Int,
        channelIndex: Int,
        speed: Int,
        bpm: Int,
        tickDuration: TimeInterval,
        rowDuration: TimeInterval,
        usesLinearFrequencyTable: Bool?,
        noteValue: UInt8?,
        instrumentIndex: Int?,
        sampleIndex: Int?,
        relativeNote: Int?,
        finetune: Int?,
        sourceSampleRate: Double?,
        effectCommand: String,
        effectParameter: String,
        effect: String,
        computedVolume: Float?,
        computedPanning: Float?,
        computedPitchSemitones: Double?,
        computedRate: Double?,
        computedFrequency: Double?,
        computedVarispeedRate: Double?,
        computedPeriodApproximation: Double?,
        sampleOffset: Int?,
        sampleLength: Int?,
        loopStart: Int?,
        loopLength: Int?,
        loopType: Int?,
        decision: PlaybackTraceDecision,
        decisionReason: String?
    ) {
        self.schemaVersion = schemaVersion
        self.tickIndex = tickIndex
        self.orderIndex = orderIndex
        self.patternIndex = patternIndex
        self.rowIndex = rowIndex
        self.tickInRow = tickInRow
        self.channelIndex = channelIndex
        self.speed = speed
        self.bpm = bpm
        self.tickDuration = tickDuration
        self.rowDuration = rowDuration
        self.usesLinearFrequencyTable = usesLinearFrequencyTable
        self.noteValue = noteValue
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
        self.relativeNote = relativeNote
        self.finetune = finetune
        self.sourceSampleRate = sourceSampleRate
        self.effectCommand = effectCommand
        self.effectParameter = effectParameter
        self.effect = effect
        self.computedVolume = computedVolume
        self.computedPanning = computedPanning
        self.computedPitchSemitones = computedPitchSemitones
        self.computedRate = computedRate
        self.computedFrequency = computedFrequency
        self.computedVarispeedRate = computedVarispeedRate
        self.computedPeriodApproximation = computedPeriodApproximation
        self.sampleOffset = sampleOffset
        self.sampleLength = sampleLength
        self.loopStart = loopStart
        self.loopLength = loopLength
        self.loopType = loopType
        self.decision = decision
        self.decisionReason = decisionReason
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tickIndex
        case orderIndex
        case patternIndex
        case rowIndex
        case tickInRow
        case channelIndex
        case speed
        case bpm
        case tickDuration
        case rowDuration
        case usesLinearFrequencyTable
        case noteValue
        case instrumentIndex
        case sampleIndex
        case relativeNote
        case finetune
        case sourceSampleRate
        case effectCommand
        case effectParameter
        case effect
        case computedVolume
        case computedPanning
        case computedPitchSemitones
        case computedRate
        case computedFrequency
        case computedVarispeedRate
        case computedPeriodApproximation
        case sampleOffset
        case sampleLength
        case loopStart
        case loopLength
        case loopType
        case decision
        case decisionReason
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(tickIndex, forKey: .tickIndex)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encode(patternIndex, forKey: .patternIndex)
        try container.encode(rowIndex, forKey: .rowIndex)
        try container.encode(tickInRow, forKey: .tickInRow)
        try container.encode(channelIndex, forKey: .channelIndex)
        try container.encode(speed, forKey: .speed)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(tickDuration, forKey: .tickDuration)
        try container.encode(rowDuration, forKey: .rowDuration)
        try container.encodeOptional(usesLinearFrequencyTable, forKey: .usesLinearFrequencyTable)
        try container.encodeOptional(noteValue, forKey: .noteValue)
        try container.encodeOptional(instrumentIndex, forKey: .instrumentIndex)
        try container.encodeOptional(sampleIndex, forKey: .sampleIndex)
        try container.encodeOptional(relativeNote, forKey: .relativeNote)
        try container.encodeOptional(finetune, forKey: .finetune)
        try container.encodeOptional(sourceSampleRate, forKey: .sourceSampleRate)
        try container.encode(effectCommand, forKey: .effectCommand)
        try container.encode(effectParameter, forKey: .effectParameter)
        try container.encode(effect, forKey: .effect)
        try container.encodeOptional(computedVolume, forKey: .computedVolume)
        try container.encodeOptional(computedPanning, forKey: .computedPanning)
        try container.encodeOptional(computedPitchSemitones, forKey: .computedPitchSemitones)
        try container.encodeOptional(computedRate, forKey: .computedRate)
        try container.encodeOptional(computedFrequency, forKey: .computedFrequency)
        try container.encodeOptional(computedVarispeedRate, forKey: .computedVarispeedRate)
        try container.encodeOptional(computedPeriodApproximation, forKey: .computedPeriodApproximation)
        try container.encodeOptional(sampleOffset, forKey: .sampleOffset)
        try container.encodeOptional(sampleLength, forKey: .sampleLength)
        try container.encodeOptional(loopStart, forKey: .loopStart)
        try container.encodeOptional(loopLength, forKey: .loopLength)
        try container.encodeOptional(loopType, forKey: .loopType)
        try container.encode(decision, forKey: .decision)
        try container.encodeOptional(decisionReason, forKey: .decisionReason)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
