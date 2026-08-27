import Foundation

struct PlaybackCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

/// Converts an exact XM sample-header panning byte into the mixer's planned `-1...1` pan.
enum PlaybackSamplePanningPolicy {
    /// XM's nominal center byte, 128, is exact center. The asymmetric divisors preserve both
    /// byte endpoints as full left/right while keeping every intermediate value monotonic.
    static func plannedPan(_ xmValue: UInt8) -> Float {
        plannedPan(Int(xmValue))
    }

    static func plannedPan(_ xmValue: Int) -> Float {
        let clamped = min(255, max(0, xmValue))
        let mapped = clamped <= Int(PlaybackSample.xmCenterPanning)
            ? Float(clamped - 128) / 128.0
            : Float(clamped - 128) / 127.0
        return min(1, max(-1, mapped))
    }
}

struct PlaybackSample: Equatable {
    static let xmNeutralSampleRate = 8_363.0
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

    /// Returns an exact value copy under a new stable sample identity.
    func reidentified(sampleIndex: Int) -> PlaybackSample {
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
        self.noteSampleMap = noteSampleMap
    }

    var firstPlayableSample: PlaybackSample? {
        samples.first { $0.isPlayable }
    }

    var availableSampleSlots: [Int] {
        Array(Set(samples.map { min(255, max(1, $0.sampleIndex + 1)) })).sorted()
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
              let noteSampleMap,
              noteSampleMap.count == 96 else {
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

/// A total old-slot-to-new-slot permutation over canonical sample identities S01...S16.
struct SampleSlotPermutation: Equatable, Sendable {
    static let slotCount = 16

    enum ValidationError: Error, Equatable {
        case indexOutOfBounds(Int)
    }

    static let identity = SampleSlotPermutation(destinationBySource: Array(0..<slotCount))

    private let destinationBySource: [Int]

    /// Moves one slot identity by removal/insertion, shifting every identity in the interval.
    static func move(from sourceIndex: Int, to destinationIndex: Int) throws -> SampleSlotPermutation {
        try validate(sourceIndex)
        try validate(destinationIndex)
        guard sourceIndex != destinationIndex else { return identity }

        var sourceByDestination = Array(0..<slotCount)
        let movedIdentity = sourceByDestination.remove(at: sourceIndex)
        sourceByDestination.insert(movedIdentity, at: destinationIndex)
        var destinationBySource = Array(repeating: 0, count: slotCount)
        for (destination, source) in sourceByDestination.enumerated() {
            destinationBySource[source] = destination
        }
        return SampleSlotPermutation(destinationBySource: destinationBySource)
    }

    /// Exchanges two slot identities while leaving every other identity unchanged.
    static func swap(_ firstIndex: Int, _ secondIndex: Int) throws -> SampleSlotPermutation {
        try validate(firstIndex)
        try validate(secondIndex)
        guard firstIndex != secondIndex else { return identity }

        var destinationBySource = Array(0..<slotCount)
        destinationBySource.swapAt(firstIndex, secondIndex)
        return SampleSlotPermutation(destinationBySource: destinationBySource)
    }

    /// Returns the new zero-based identity for a validated old zero-based identity.
    func apply(to sourceIndex: Int) throws -> Int {
        try Self.validate(sourceIndex)
        return destinationBySource[sourceIndex]
    }

    /// Reverses this exact slot transformation.
    var inverse: SampleSlotPermutation {
        var sourceByDestination = Array(repeating: 0, count: Self.slotCount)
        for (source, destination) in destinationBySource.enumerated() {
            sourceByDestination[destination] = source
        }
        return SampleSlotPermutation(destinationBySource: sourceByDestination)
    }

    var isIdentity: Bool {
        destinationBySource == Array(0..<Self.slotCount)
    }

    private init(destinationBySource: [Int]) {
        self.destinationBySource = destinationBySource
    }

    private static func validate(_ index: Int) throws {
        guard (0..<slotCount).contains(index) else {
            throw ValidationError.indexOutOfBounds(index)
        }
    }
}

/// One canonical sample-slot identity presented to editor UI without inventing sample data.
struct SampleSlotPresentationRow: Equatable {
    enum State: Equatable {
        case represented(PlaybackSample)
        case emptyDestination
    }

    let sampleIndex: Int
    let state: State

    var sampleSlot: Int { sampleIndex + 1 }
    var representedSample: PlaybackSample? {
        guard case let .represented(sample) = state else { return nil }
        return sample
    }
    var isEmptyDestination: Bool {
        guard case .emptyDestination = state else { return false }
        return true
    }
}

/// Shared UI-independent projection for editable and loaded sample-slot lists.
enum SampleSlotPresentationProjection {
    static let maximumSampleCount = SampleSlotPermutation.slotCount
    private static let canonicalNoteCount = 96
    private static let validSampleIndices = 0..<maximumSampleCount

    static func editableRows(
        instrument: PlaybackInstrument,
        selectedSampleSlot: Int?
    ) -> [SampleSlotPresentationRow] {
        let represented = representedSamples(in: instrument)
        var requiredIndices = Set(represented.keys)
        requiredIndices.insert(0)

        if let map = instrument.noteSampleMap, map.count == canonicalNoteCount {
            requiredIndices.formUnion(map.filter(validSampleIndices.contains))
        }
        if let selectedSampleSlot,
           (1...maximumSampleCount).contains(selectedSampleSlot) {
            requiredIndices.insert(selectedSampleSlot - 1)
        }
        let highestRequiredIndex = requiredIndices.max() ?? 0
        return (0...highestRequiredIndex).map { row(sampleIndex: $0, represented: represented) }
    }

    static func loadedRows(
        instrument: PlaybackInstrument,
        sourceProvenance: [XMSourceSampleSlotProvenance]?
    ) -> [SampleSlotPresentationRow] {
        let represented = representedSamples(in: instrument)
        var eligibleIndices = Set(represented.keys)
        for provenance in sourceProvenance ?? []
            where validSampleIndices.contains(provenance.sampleIndex) &&
                provenance.decodedPayloadLength == 0 &&
                provenance.isCanonicalEmptySlotHeader {
            eligibleIndices.insert(provenance.sampleIndex)
        }
        return eligibleIndices.sorted().map { row(sampleIndex: $0, represented: represented) }
    }

    private static func representedSamples(in instrument: PlaybackInstrument) -> [Int: PlaybackSample] {
        instrument.samples.reduce(into: [:]) { result, sample in
            guard validSampleIndices.contains(sample.sampleIndex), result[sample.sampleIndex] == nil else { return }
            result[sample.sampleIndex] = sample
        }
    }

    private static func row(
        sampleIndex: Int,
        represented: [Int: PlaybackSample]
    ) -> SampleSlotPresentationRow {
        SampleSlotPresentationRow(
            sampleIndex: sampleIndex,
            state: represented[sampleIndex].map(SampleSlotPresentationRow.State.represented)
                ?? .emptyDestination
        )
    }
}

struct ResolvedPlaybackSample: Equatable {
    let instrumentIndex: Int
    let sampleIndex: Int
    let sample: PlaybackSample
}

enum PlaybackInstrumentMissingKeymapPolicy: Equatable {
    case fail
    case firstPlayableSample
}

/// Canonical note-to-sample lookup for represented playback instruments.
enum PlaybackInstrumentSampleResolver {
    static func resolveSample(
        instrumentIndex: Int,
        note: UInt8,
        instrumentsByIndex: [Int: PlaybackInstrument],
        missingKeymapPolicy: PlaybackInstrumentMissingKeymapPolicy = .fail
    ) -> ResolvedPlaybackSample? {
        guard let instrument = instrumentsByIndex[instrumentIndex] else {
            return nil
        }
        return resolveSample(
            instrumentIndex: instrumentIndex,
            note: note,
            instrument: instrument,
            missingKeymapPolicy: missingKeymapPolicy
        )
    }

    static func resolveSample(
        instrumentIndex: Int,
        note: UInt8,
        instrument: PlaybackInstrument,
        missingKeymapPolicy: PlaybackInstrumentMissingKeymapPolicy = .fail
    ) -> ResolvedPlaybackSample? {
        guard instrumentIndex > 0,
              (1...96).contains(note),
              instrument.index == instrumentIndex else {
            return nil
        }

        let sample: PlaybackSample?
        if let noteSampleMap = instrument.noteSampleMap {
            guard noteSampleMap.count == 96 else { return nil }
            let mappedSampleIndex = noteSampleMap[Int(note) - 1]
            guard mappedSampleIndex >= 0 else { return nil }
            sample = instrument.sample(mappedSampleIndex: mappedSampleIndex)
        } else if missingKeymapPolicy == .firstPlayableSample {
            sample = instrument.firstPlayableSample
        } else {
            sample = nil
        }

        guard let sample,
              sample.instrumentIndex == instrumentIndex,
              sample.sampleIndex >= 0,
              sample.isPlayable else {
            return nil
        }
        return ResolvedPlaybackSample(
            instrumentIndex: instrumentIndex,
            sampleIndex: sample.sampleIndex,
            sample: sample
        )
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

/// Source-only structural facts for one XM sample-header slot. The editable model still represents
/// only nonempty `PlaybackSample` values; this metadata exists solely to avoid guessing at copy time.
struct XMSourceSampleSlotProvenance: Equatable {
    let sampleIndex: Int
    let decodedPayloadLength: Int
    let isCanonicalEmptySlotHeader: Bool
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
    let xmSampleSlotProvenanceByInstrument: [Int: [XMSourceSampleSlotProvenance]]

    init(
        title: String,
        orders: [PlaybackOrderEntry],
        patternsByIndex: [Int: PlaybackPattern],
        instrumentsByIndex: [Int: PlaybackInstrument],
        restartOrderIndex: Int,
        endBehavior: PlaybackEndBehavior,
        initialTiming: PlaybackTiming = .xmDefault,
        usesLinearFrequencyTable: Bool = true,
        xmSampleSlotProvenanceByInstrument: [Int: [XMSourceSampleSlotProvenance]] = [:]
    ) {
        self.title = title
        self.orders = orders
        self.patternsByIndex = patternsByIndex
        self.instrumentsByIndex = instrumentsByIndex
        self.restartOrderIndex = restartOrderIndex
        self.endBehavior = endBehavior
        self.initialTiming = initialTiming
        self.usesLinearFrequencyTable = usesLinearFrequencyTable
        self.xmSampleSlotProvenanceByInstrument = xmSampleSlotProvenanceByInstrument
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

    func resolveSample(
        instrumentIndex: Int,
        note: UInt8,
        missingKeymapPolicy: PlaybackInstrumentMissingKeymapPolicy = .fail
    ) -> ResolvedPlaybackSample? {
        PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: instrumentIndex,
            note: note,
            instrumentsByIndex: instrumentsByIndex,
            missingKeymapPolicy: missingKeymapPolicy
        )
    }

    func instrument(forInstrument instrumentIndex: Int) -> PlaybackInstrument? {
        guard instrumentIndex > 0 else {
            return nil
        }
        return instrumentsByIndex[instrumentIndex]
    }

    func sampleSlotPresentationRows(forInstrument instrumentIndex: Int) -> [SampleSlotPresentationRow] {
        guard let instrument = instrument(forInstrument: instrumentIndex) else { return [] }
        return SampleSlotPresentationProjection.loadedRows(
            instrument: instrument,
            sourceProvenance: xmSampleSlotProvenanceByInstrument[instrumentIndex]
        )
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
