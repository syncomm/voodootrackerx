import Foundation

struct PlaybackCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

struct PlaybackSample: Equatable {
    static let xmMaximumVolume: UInt8 = 64
    static let xmDefaultVolume: UInt8 = xmMaximumVolume
    static let xmRelativeNoteRange = Int(Int8.min)...Int(Int8.max)
    static let xmFinetuneRange = Int(Int8.min)...Int(Int8.max)
    /// XM sample-header center/default panning byte.
    static let xmCenterPanning: UInt8 = 128

    let instrumentIndex: Int
    let sampleIndex: Int
    let name: String?
    let pcm: [Float]
    let volume: Float
    /// Raw XM sample-header panning byte: 0 left, 128 center, and 255 right.
    let panning: UInt8
    let relativeNote: Int
    let finetune: Int
    let baseSampleRate: Double
    let sampleLength: Int
    let loopStart: Int
    let loopLength: Int
    let loopType: Int
    let sourceBitDepthBits: Int?
    let sourceIsSignedPCM: Bool?
    let sourceIsDeltaEncoded: Bool?

    init(
        instrumentIndex: Int,
        sampleIndex: Int,
        name: String? = nil,
        pcm: [Float],
        volume: Float,
        panning: UInt8 = PlaybackSample.xmCenterPanning,
        relativeNote: Int,
        finetune: Int,
        baseSampleRate: Double,
        sampleLength: Int? = nil,
        loopStart: Int = 0,
        loopLength: Int = 0,
        loopType: Int = 0,
        sourceBitDepthBits: Int? = nil,
        sourceIsSignedPCM: Bool? = nil,
        sourceIsDeltaEncoded: Bool? = nil
    ) {
        self.instrumentIndex = instrumentIndex
        self.sampleIndex = sampleIndex
        self.name = name
        self.pcm = pcm
        self.volume = volume
        self.panning = panning
        self.relativeNote = relativeNote
        self.finetune = finetune
        self.baseSampleRate = baseSampleRate
        self.sampleLength = sampleLength ?? pcm.count
        self.loopStart = loopStart
        self.loopLength = loopLength
        self.loopType = loopType
        self.sourceBitDepthBits = sourceBitDepthBits
        self.sourceIsSignedPCM = sourceIsSignedPCM
        self.sourceIsDeltaEncoded = sourceIsDeltaEncoded
    }

    /// Exact XM sample-header volume represented by the normalized playback value.
    var xmVolume: UInt8 {
        let finiteVolume = volume.isFinite ? volume : 0
        let scaled = Int((finiteVolume * Float(Self.xmMaximumVolume)).rounded())
        return UInt8(min(Int(Self.xmMaximumVolume), max(0, scaled)))
    }

    func withVolume(_ volume: UInt8) -> PlaybackSample {
        let clampedVolume = min(volume, Self.xmMaximumVolume)
        return PlaybackSample(
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            name: name,
            pcm: pcm,
            volume: Float(clampedVolume) / Float(Self.xmMaximumVolume),
            panning: panning,
            relativeNote: relativeNote,
            finetune: finetune,
            baseSampleRate: baseSampleRate,
            sampleLength: sampleLength,
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType,
            sourceBitDepthBits: sourceBitDepthBits,
            sourceIsSignedPCM: sourceIsSignedPCM,
            sourceIsDeltaEncoded: sourceIsDeltaEncoded
        )
    }

    func withPanning(_ panning: UInt8) -> PlaybackSample {
        PlaybackSample(
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            name: name,
            pcm: pcm,
            volume: volume,
            panning: panning,
            relativeNote: relativeNote,
            finetune: finetune,
            baseSampleRate: baseSampleRate,
            sampleLength: sampleLength,
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType,
            sourceBitDepthBits: sourceBitDepthBits,
            sourceIsSignedPCM: sourceIsSignedPCM,
            sourceIsDeltaEncoded: sourceIsDeltaEncoded
        )
    }

    func withRelativeNote(_ relativeNote: Int) -> PlaybackSample {
        PlaybackSample(
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            name: name,
            pcm: pcm,
            volume: volume,
            panning: panning,
            relativeNote: relativeNote,
            finetune: finetune,
            baseSampleRate: baseSampleRate,
            sampleLength: sampleLength,
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType,
            sourceBitDepthBits: sourceBitDepthBits,
            sourceIsSignedPCM: sourceIsSignedPCM,
            sourceIsDeltaEncoded: sourceIsDeltaEncoded
        )
    }

    func withFinetune(_ finetune: Int) -> PlaybackSample {
        PlaybackSample(
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            name: name,
            pcm: pcm,
            volume: volume,
            panning: panning,
            relativeNote: relativeNote,
            finetune: finetune,
            baseSampleRate: baseSampleRate,
            sampleLength: sampleLength,
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType,
            sourceBitDepthBits: sourceBitDepthBits,
            sourceIsSignedPCM: sourceIsSignedPCM,
            sourceIsDeltaEncoded: sourceIsDeltaEncoded
        )
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

/// Exact supported XM instrument panning-envelope fields. Playback intentionally ignores this foundation value.
struct PlaybackPanningEnvelope: Equatable {
    static let disabled = PlaybackPanningEnvelope(
        enabled: false,
        points: [],
        sustainPointIndex: nil,
        loopStartPointIndex: nil,
        loopEndPointIndex: nil,
        typeFlags: 0
    )

    let enabled: Bool
    let points: [PlaybackEnvelopePoint]
    let sustainPointIndex: Int?
    let loopStartPointIndex: Int?
    let loopEndPointIndex: Int?
    let typeFlags: UInt8

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
}

/// Exact XM instrument-header autovibrato bytes. Playback intentionally ignores this foundation value.
struct PlaybackInstrumentAutoVibrato: Equatable {
    static let disabled = PlaybackInstrumentAutoVibrato()

    let waveformType: UInt8
    let sweep: UInt8
    let depth: UInt8
    let rate: UInt8

    init(
        waveformType: UInt8 = 0,
        sweep: UInt8 = 0,
        depth: UInt8 = 0,
        rate: UInt8 = 0
    ) {
        self.waveformType = waveformType
        self.sweep = sweep
        self.depth = depth
        self.rate = rate
    }
}

struct PlaybackInstrument: Equatable {
    let index: Int
    let name: String?
    let samples: [PlaybackSample]
    let volumeEnvelope: PlaybackVolumeEnvelope
    let panningEnvelope: PlaybackPanningEnvelope
    let autoVibrato: PlaybackInstrumentAutoVibrato
    let noteSampleMap: [Int]?

    init(
        index: Int,
        name: String? = nil,
        samples: [PlaybackSample],
        volumeEnvelope: PlaybackVolumeEnvelope = .disabled,
        panningEnvelope: PlaybackPanningEnvelope = .disabled,
        autoVibrato: PlaybackInstrumentAutoVibrato = .disabled,
        noteSampleMap: [Int]? = nil
    ) {
        self.index = index
        self.name = name
        self.samples = samples
        self.volumeEnvelope = volumeEnvelope
        self.panningEnvelope = panningEnvelope
        self.autoVibrato = autoVibrato
        self.noteSampleMap = noteSampleMap?.count == 96 ? noteSampleMap : nil
    }

    var firstPlayableSample: PlaybackSample? {
        samples.first { $0.isPlayable }
    }

    var availableSampleSlots: [Int] {
        Array(Set(samples.map { min(255, max(1, $0.sampleIndex + 1)) })).sorted()
    }

    var hasNoteSampleMap: Bool {
        noteSampleMap != nil
    }

    func withName(_ name: String?) -> PlaybackInstrument {
        PlaybackInstrument(
            index: index,
            name: name,
            samples: samples,
            volumeEnvelope: volumeEnvelope,
            panningEnvelope: panningEnvelope,
            autoVibrato: autoVibrato,
            noteSampleMap: noteSampleMap
        )
    }

    func mappedSampleIndex(forNote note: UInt8) -> Int? {
        guard (1...96).contains(note),
              let noteSampleMap else {
            return nil
        }
        return noteSampleMap[Int(note) - 1]
    }

    func sample(mappedSampleIndex: Int) -> PlaybackSample? {
        samples.first { $0.sampleIndex == mappedSampleIndex }
    }

    func sample(selectedSampleSlot: Int) -> PlaybackSample? {
        guard selectedSampleSlot > 0 else {
            return nil
        }
        return sample(mappedSampleIndex: selectedSampleSlot - 1)
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

struct PlaybackPatternLoopRange: Equatable {
    let orderEntry: PlaybackOrderEntry
    let firstPosition: PlaybackPosition
    let lastPosition: PlaybackPosition
    let rowCount: Int

    var orderIndex: Int {
        orderEntry.orderIndex
    }

    var patternIndex: Int {
        orderEntry.patternIndex
    }

    func contains(_ position: PlaybackPosition) -> Bool {
        position.orderIndex == orderIndex &&
            position.patternIndex == patternIndex &&
            position.rowIndex >= firstPosition.rowIndex &&
            position.rowIndex <= lastPosition.rowIndex
    }
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

    func isolatedPatternLoopSong(patternIndex: Int, anchorOrderIndex: Int) -> PlaybackSong? {
        guard let targetPattern = patternsByIndex[patternIndex] else {
            return nil
        }
        let safeAnchorOrderIndex = max(0, anchorOrderIndex)
        let playableTargetPattern = targetPattern.rows.isEmpty
            ? PlaybackPattern(index: targetPattern.index, rows: [emptyPlaybackRow(index: 0, matching: targetPattern)])
            : targetPattern
        let placeholderPatternIndex = unusedPatternIndex(excluding: patternIndex)
        let placeholderPattern = PlaybackPattern(
            index: placeholderPatternIndex,
            rows: [emptyPlaybackRow(index: 0, matching: playableTargetPattern)]
        )
        var isolatedPatterns = patternsByIndex
        isolatedPatterns[playableTargetPattern.index] = playableTargetPattern
        if safeAnchorOrderIndex > 0 {
            isolatedPatterns[placeholderPatternIndex] = placeholderPattern
        }
        let isolatedOrders = (0...safeAnchorOrderIndex).map { orderIndex in
            PlaybackOrderEntry(
                orderIndex: orderIndex,
                patternIndex: orderIndex == safeAnchorOrderIndex ? patternIndex : placeholderPatternIndex
            )
        }
        return PlaybackSong(
            title: title,
            orders: isolatedOrders,
            patternsByIndex: isolatedPatterns,
            instrumentsByIndex: instrumentsByIndex,
            restartOrderIndex: safeAnchorOrderIndex,
            endBehavior: .stopAtEnd,
            initialTiming: initialTiming,
            usesLinearFrequencyTable: usesLinearFrequencyTable
        )
    }

    func patternLoopRange(containing position: PlaybackPosition) -> PlaybackPatternLoopRange? {
        guard orders.indices.contains(position.orderIndex) else {
            return nil
        }
        let orderEntry = orders[position.orderIndex]
        guard orderEntry.patternIndex == position.patternIndex,
              let pattern = patternsByIndex[position.patternIndex],
              !pattern.rows.isEmpty,
              pattern.rows.indices.contains(position.rowIndex) else {
            return nil
        }
        return PlaybackPatternLoopRange(
            orderEntry: orderEntry,
            firstPosition: PlaybackPosition(
                orderIndex: orderEntry.orderIndex,
                patternIndex: orderEntry.patternIndex,
                rowIndex: 0
            ),
            lastPosition: PlaybackPosition(
                orderIndex: orderEntry.orderIndex,
                patternIndex: orderEntry.patternIndex,
                rowIndex: pattern.rows.count - 1
            ),
            rowCount: pattern.rows.count
        )
    }

    private func emptyPlaybackRow(index: Int, matching pattern: PlaybackPattern) -> PlaybackRow {
        let channelCount = max(1, pattern.rows.first?.cells.count ?? 1)
        return PlaybackRow(
            index: index,
            cells: Array(
                repeating: PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
                count: channelCount
            )
        )
    }

    private func unusedPatternIndex(excluding patternIndex: Int) -> Int {
        var candidate = max(patternIndex, patternsByIndex.keys.max() ?? patternIndex) + 1
        while patternsByIndex[candidate] != nil {
            candidate += 1
        }
        return candidate
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
