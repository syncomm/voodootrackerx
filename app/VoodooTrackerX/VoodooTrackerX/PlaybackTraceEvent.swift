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
    let noteValue: UInt8?
    let instrumentIndex: Int?
    let sampleIndex: Int?
    let effectCommand: String
    let effectParameter: String
    let effect: String
    let computedVolume: Float?
    let computedPanning: Float?
    let computedPitchSemitones: Double?
    let computedRate: Double?
    let computedPeriodApproximation: Double?
    let sampleOffset: Int?
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
        noteValue: UInt8?,
        instrumentIndex: Int?,
        sampleIndex: Int?,
        effectCommand: String,
        effectParameter: String,
        effect: String,
        computedVolume: Float?,
        computedPanning: Float?,
        computedPitchSemitones: Double?,
        computedRate: Double?,
        computedPeriodApproximation: Double?,
        sampleOffset: Int?,
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
        self.noteValue = noteValue
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
        self.effectCommand = effectCommand
        self.effectParameter = effectParameter
        self.effect = effect
        self.computedVolume = computedVolume
        self.computedPanning = computedPanning
        self.computedPitchSemitones = computedPitchSemitones
        self.computedRate = computedRate
        self.computedPeriodApproximation = computedPeriodApproximation
        self.sampleOffset = sampleOffset
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
        case noteValue
        case instrumentIndex
        case sampleIndex
        case effectCommand
        case effectParameter
        case effect
        case computedVolume
        case computedPanning
        case computedPitchSemitones
        case computedRate
        case computedPeriodApproximation
        case sampleOffset
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
        try container.encodeOptional(noteValue, forKey: .noteValue)
        try container.encodeOptional(instrumentIndex, forKey: .instrumentIndex)
        try container.encodeOptional(sampleIndex, forKey: .sampleIndex)
        try container.encode(effectCommand, forKey: .effectCommand)
        try container.encode(effectParameter, forKey: .effectParameter)
        try container.encode(effect, forKey: .effect)
        try container.encodeOptional(computedVolume, forKey: .computedVolume)
        try container.encodeOptional(computedPanning, forKey: .computedPanning)
        try container.encodeOptional(computedPitchSemitones, forKey: .computedPitchSemitones)
        try container.encodeOptional(computedRate, forKey: .computedRate)
        try container.encodeOptional(computedPeriodApproximation, forKey: .computedPeriodApproximation)
        try container.encodeOptional(sampleOffset, forKey: .sampleOffset)
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
