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
    let audioBufferSampleRate: Double?
    let rawVolumeColumn: String?
    let decodedVolumeColumnCommand: String?
    let volumeColumnApplied: Bool?
    let volumeColumnVolume: Int?
    let volumeColumnPanning: Int?
    let effectCommand: String
    let effectParameter: String
    let effect: String
    let computedVolume: Float?
    let computedPanning: Float?
    let computedPitchSemitones: Double?
    let targetFrequency: Double?
    let computedRate: Double?
    let rateBasis: String?
    let computedFrequency: Double?
    let computedVarispeedRate: Double?
    let computedPeriodApproximation: Double?
    let sampleOffset: Int?
    let sampleLength: Int?
    let loopStart: Int?
    let loopLength: Int?
    let loopType: Int?
    let loopTypeName: String?
    let loopEnabled: Bool?
    let loopStartFrame: Int?
    let loopEndFrame: Int?
    let loopLengthFrames: Int?
    let pingPongLoopApplied: Bool?
    let envelopeEnabled: Bool?
    let envelopeTick: Int?
    let envelopeValue: Float?
    let envelopeSustainActive: Bool?
    let envelopeLoopActive: Bool?
    let fadeoutValue: Float?
    let finalAppliedVolume: Float?
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
        audioBufferSampleRate: Double?,
        rawVolumeColumn: String? = nil,
        decodedVolumeColumnCommand: String? = nil,
        volumeColumnApplied: Bool? = nil,
        volumeColumnVolume: Int? = nil,
        volumeColumnPanning: Int? = nil,
        effectCommand: String,
        effectParameter: String,
        effect: String,
        computedVolume: Float?,
        computedPanning: Float?,
        computedPitchSemitones: Double?,
        targetFrequency: Double?,
        computedRate: Double?,
        rateBasis: String?,
        computedFrequency: Double?,
        computedVarispeedRate: Double?,
        computedPeriodApproximation: Double?,
        sampleOffset: Int?,
        sampleLength: Int?,
        loopStart: Int?,
        loopLength: Int?,
        loopType: Int?,
        loopTypeName: String?,
        loopEnabled: Bool?,
        loopStartFrame: Int?,
        loopEndFrame: Int?,
        loopLengthFrames: Int?,
        pingPongLoopApplied: Bool?,
        envelopeEnabled: Bool? = nil,
        envelopeTick: Int? = nil,
        envelopeValue: Float? = nil,
        envelopeSustainActive: Bool? = nil,
        envelopeLoopActive: Bool? = nil,
        fadeoutValue: Float? = nil,
        finalAppliedVolume: Float? = nil,
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
        self.audioBufferSampleRate = audioBufferSampleRate
        self.rawVolumeColumn = rawVolumeColumn
        self.decodedVolumeColumnCommand = decodedVolumeColumnCommand
        self.volumeColumnApplied = volumeColumnApplied
        self.volumeColumnVolume = volumeColumnVolume
        self.volumeColumnPanning = volumeColumnPanning
        self.effectCommand = effectCommand
        self.effectParameter = effectParameter
        self.effect = effect
        self.computedVolume = computedVolume
        self.computedPanning = computedPanning
        self.computedPitchSemitones = computedPitchSemitones
        self.targetFrequency = targetFrequency
        self.computedRate = computedRate
        self.rateBasis = rateBasis
        self.computedFrequency = computedFrequency
        self.computedVarispeedRate = computedVarispeedRate
        self.computedPeriodApproximation = computedPeriodApproximation
        self.sampleOffset = sampleOffset
        self.sampleLength = sampleLength
        self.loopStart = loopStart
        self.loopLength = loopLength
        self.loopType = loopType
        self.loopTypeName = loopTypeName
        self.loopEnabled = loopEnabled
        self.loopStartFrame = loopStartFrame
        self.loopEndFrame = loopEndFrame
        self.loopLengthFrames = loopLengthFrames
        self.pingPongLoopApplied = pingPongLoopApplied
        self.envelopeEnabled = envelopeEnabled
        self.envelopeTick = envelopeTick
        self.envelopeValue = envelopeValue
        self.envelopeSustainActive = envelopeSustainActive
        self.envelopeLoopActive = envelopeLoopActive
        self.fadeoutValue = fadeoutValue
        self.finalAppliedVolume = finalAppliedVolume
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
        case audioBufferSampleRate
        case rawVolumeColumn
        case decodedVolumeColumnCommand
        case volumeColumnApplied
        case volumeColumnVolume
        case volumeColumnPanning
        case effectCommand
        case effectParameter
        case effect
        case computedVolume
        case computedPanning
        case computedPitchSemitones
        case targetFrequency
        case computedRate
        case rateBasis
        case computedFrequency
        case computedVarispeedRate
        case computedPeriodApproximation
        case sampleOffset
        case sampleLength
        case loopStart
        case loopLength
        case loopType
        case loopTypeName
        case loopEnabled
        case loopStartFrame
        case loopEndFrame
        case loopLengthFrames
        case pingPongLoopApplied
        case envelopeEnabled
        case envelopeTick
        case envelopeValue
        case envelopeSustainActive
        case envelopeLoopActive
        case fadeoutValue
        case finalAppliedVolume
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
        try container.encodeOptional(audioBufferSampleRate, forKey: .audioBufferSampleRate)
        try container.encodeOptional(rawVolumeColumn, forKey: .rawVolumeColumn)
        try container.encodeOptional(decodedVolumeColumnCommand, forKey: .decodedVolumeColumnCommand)
        try container.encodeOptional(volumeColumnApplied, forKey: .volumeColumnApplied)
        try container.encodeOptional(volumeColumnVolume, forKey: .volumeColumnVolume)
        try container.encodeOptional(volumeColumnPanning, forKey: .volumeColumnPanning)
        try container.encode(effectCommand, forKey: .effectCommand)
        try container.encode(effectParameter, forKey: .effectParameter)
        try container.encode(effect, forKey: .effect)
        try container.encodeOptional(computedVolume, forKey: .computedVolume)
        try container.encodeOptional(computedPanning, forKey: .computedPanning)
        try container.encodeOptional(computedPitchSemitones, forKey: .computedPitchSemitones)
        try container.encodeOptional(targetFrequency, forKey: .targetFrequency)
        try container.encodeOptional(computedRate, forKey: .computedRate)
        try container.encodeOptional(rateBasis, forKey: .rateBasis)
        try container.encodeOptional(computedFrequency, forKey: .computedFrequency)
        try container.encodeOptional(computedVarispeedRate, forKey: .computedVarispeedRate)
        try container.encodeOptional(computedPeriodApproximation, forKey: .computedPeriodApproximation)
        try container.encodeOptional(sampleOffset, forKey: .sampleOffset)
        try container.encodeOptional(sampleLength, forKey: .sampleLength)
        try container.encodeOptional(loopStart, forKey: .loopStart)
        try container.encodeOptional(loopLength, forKey: .loopLength)
        try container.encodeOptional(loopType, forKey: .loopType)
        try container.encodeOptional(loopTypeName, forKey: .loopTypeName)
        try container.encodeOptional(loopEnabled, forKey: .loopEnabled)
        try container.encodeOptional(loopStartFrame, forKey: .loopStartFrame)
        try container.encodeOptional(loopEndFrame, forKey: .loopEndFrame)
        try container.encodeOptional(loopLengthFrames, forKey: .loopLengthFrames)
        try container.encodeOptional(pingPongLoopApplied, forKey: .pingPongLoopApplied)
        try container.encodeOptional(envelopeEnabled, forKey: .envelopeEnabled)
        try container.encodeOptional(envelopeTick, forKey: .envelopeTick)
        try container.encodeOptional(envelopeValue, forKey: .envelopeValue)
        try container.encodeOptional(envelopeSustainActive, forKey: .envelopeSustainActive)
        try container.encodeOptional(envelopeLoopActive, forKey: .envelopeLoopActive)
        try container.encodeOptional(fadeoutValue, forKey: .fadeoutValue)
        try container.encodeOptional(finalAppliedVolume, forKey: .finalAppliedVolume)
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
