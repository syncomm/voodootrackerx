import Foundation

enum EditableXMTextEncoding {
    static let instrumentNameByteLimit = 22

    static func sanitizedInstrumentName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let bytes = Array(sanitizedASCIIBytes(from: trimmed).prefix(instrumentNameByteLimit))
        return bytes.isEmpty ? nil : String(bytes: bytes, encoding: .ascii)
    }

    static func sanitizedASCIIBytes(from value: String) -> [UInt8] {
        var bytes = [UInt8]()
        for scalar in value.unicodeScalars {
            if scalar.value >= 0x20, scalar.value <= 0x7E {
                bytes.append(UInt8(scalar.value))
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                bytes.append(UInt8(ascii: " "))
            } else {
                bytes.append(UInt8(ascii: "?"))
            }
        }
        return bytes
    }
}

enum EditableXMWriterError: Error, Equatable {
    case unsupportedOrderLength(Int)
    case unsupportedPatternIndex(Int)
    case unsupportedPatternCount(Int)
    case unsupportedInstrumentCount(Int)
    case unsupportedInstrumentSampleCount(instrumentIndex: Int, sampleCount: Int)
    case unsupportedDuplicateSampleIndex(instrumentIndex: Int, sampleIndex: Int)
    case unsupportedSampleSourceMetadata(
        instrumentIndex: Int,
        sampleIndex: Int,
        bitDepth: Int?,
        signedPCM: Bool?,
        deltaEncoded: Bool?
    )
    case unsupportedSampleBitDepth(instrumentIndex: Int, sampleIndex: Int, bitDepth: Int)
    case unsupportedSampleLoopType(instrumentIndex: Int, sampleIndex: Int, loopType: Int)
    case unsupportedSampleLoopRegion(instrumentIndex: Int, sampleIndex: Int, loopStart: Int, loopLength: Int)
    case unsupportedSampleLength(instrumentIndex: Int, sampleIndex: Int, frameCount: Int, bitDepth: Int)
    case unsupportedVolumeEnvelopePointCount(instrumentIndex: Int, pointCount: Int)
}

struct EditableXMWriter {
    fileprivate static let xmSignature = "Extended Module: "
    fileprivate static let trackerName = "VoodooTrackerX"
    fileprivate static let xmVersion: UInt16 = 0x0104
    fileprivate static let xmHeaderSize: UInt32 = 276
    fileprivate static let patternHeaderSize: UInt32 = 9
    fileprivate static let instrumentHeaderSize: UInt32 = 29
    fileprivate static let instrumentHeaderSizeWithSamples: UInt32 = 263
    fileprivate static let sampleHeaderSize: UInt32 = 40
    private static let maxXMOrderEntries = 256
    private static let maxXMPatternIndex = 255
    private static let maxXMChannels = 32
    private static let maxXMPatternRows = 256
    private static let maxXMInstruments = 255
    private static let maxXMSamplesPerInstrument = 16

    func data(from document: BlankTrackerDocument) throws -> Data {
        let orderTable = effectiveOrderTable(for: document)
        guard orderTable.count <= Self.maxXMOrderEntries else {
            throw EditableXMWriterError.unsupportedOrderLength(orderTable.count)
        }
        for patternIndex in orderTable where patternIndex < 0 || patternIndex > Self.maxXMPatternIndex {
            throw EditableXMWriterError.unsupportedPatternIndex(patternIndex)
        }
        for pattern in document.patterns where pattern.index < 0 || pattern.index > Self.maxXMPatternIndex {
            throw EditableXMWriterError.unsupportedPatternIndex(pattern.index)
        }

        let patternCount = effectivePatternCount(document: document, orderTable: orderTable)
        guard patternCount <= Self.maxXMOrderEntries else {
            throw EditableXMWriterError.unsupportedPatternCount(patternCount)
        }

        let instrumentCount = effectiveInstrumentCount(document: document)
        guard instrumentCount <= Self.maxXMInstruments else {
            throw EditableXMWriterError.unsupportedInstrumentCount(instrumentCount)
        }

        let exportedInstruments = try exportedInstruments(for: document, instrumentCount: instrumentCount)
        let channelCount = effectiveChannelCount(for: document)
        let patternsByIndex = Dictionary(document.patterns.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })

        var writer = XMByteWriter()
        writer.appendASCII(Self.xmSignature)
        writer.appendFixedASCII(document.title, length: 20, fallback: BlankTrackerDocument.defaultTitle)
        writer.appendUInt8(0x1A)
        writer.appendFixedASCII(Self.trackerName, length: 20, fallback: Self.trackerName)
        writer.appendUInt16(Self.xmVersion)
        writer.appendUInt32(Self.xmHeaderSize)
        writer.appendUInt16(UInt16(orderTable.count))
        writer.appendUInt16(UInt16(max(0, min(document.restartPosition, max(0, orderTable.count - 1)))))
        writer.appendUInt16(UInt16(channelCount))
        writer.appendUInt16(UInt16(patternCount))
        writer.appendUInt16(UInt16(instrumentCount))
        writer.appendUInt16(UInt16(document.metadata.xmFlags))
        writer.appendUInt16(UInt16(max(1, min(document.speed, Int(UInt16.max)))))
        writer.appendUInt16(UInt16(max(1, min(document.tempo, Int(UInt16.max)))))
        writer.appendOrderTable(orderTable)

        for patternIndex in 0..<patternCount {
            let pattern = patternsByIndex[patternIndex]
            let rowCount = effectiveRowCount(for: pattern, fallback: document.pattern.rowCount)
            let patternData = packedPatternData(pattern, rowCount: rowCount, channelCount: channelCount)

            writer.appendUInt32(Self.patternHeaderSize)
            writer.appendUInt8(0)
            writer.appendUInt16(UInt16(rowCount))
            writer.appendUInt16(UInt16(patternData.count))
            writer.appendData(patternData)
        }

        for instrument in exportedInstruments {
            writer.appendInstrument(instrument)
        }

        return writer.data
    }

    private func effectiveOrderTable(for document: BlankTrackerDocument) -> [Int] {
        let clampedLength = max(0, min(document.songLength, document.orderTable.count))
        let orders = Array(document.orderTable.prefix(clampedLength))
        return orders.isEmpty ? [BlankTrackerDocument.defaultPatternIndex] : orders
    }

    private func effectivePatternCount(document: BlankTrackerDocument, orderTable: [Int]) -> Int {
        let highestAllocatedPattern = document.patterns.map(\.index).max() ?? BlankTrackerDocument.defaultPatternIndex
        let highestOrderedPattern = orderTable.max() ?? BlankTrackerDocument.defaultPatternIndex
        return max(BlankTrackerDocument.defaultPatternIndex, highestAllocatedPattern, highestOrderedPattern) + 1
    }

    private func effectiveChannelCount(for document: BlankTrackerDocument) -> Int {
        max(1, min(document.pattern.channels, Self.maxXMChannels))
    }

    private func effectiveRowCount(for pattern: XMPatternData?, fallback: Int) -> Int {
        max(1, min(pattern?.rowCount ?? fallback, Self.maxXMPatternRows))
    }

    private func effectiveInstrumentCount(document: BlankTrackerDocument) -> Int {
        let highestReferencedInstrument = document.patterns.flatMap(\.rows).flatMap { row in
            row.map { Int($0.instrument) }
        }.max() ?? 0
        return max(document.instrumentCount, highestReferencedInstrument)
    }

    private func packedPatternData(_ pattern: XMPatternData?, rowCount: Int, channelCount: Int) -> Data {
        guard let pattern else {
            return Data()
        }

        var packedEvents = Data()
        for rowIndex in 0..<rowCount {
            for channelIndex in 0..<channelCount {
                let cell = cell(in: pattern, row: rowIndex, channel: channelIndex)
                packedEvents.append(contentsOf: packedEventBytes(for: cell))
            }
        }

        return packedEvents.allSatisfy { $0 == 0x80 } ? Data() : packedEvents
    }

    private func cell(in pattern: XMPatternData, row rowIndex: Int, channel channelIndex: Int) -> XMPatternEventCell {
        guard pattern.rows.indices.contains(rowIndex),
              pattern.rows[rowIndex].indices.contains(channelIndex) else {
            return .empty
        }
        return pattern.rows[rowIndex][channelIndex]
    }

    private func packedEventBytes(for cell: XMPatternEventCell) -> [UInt8] {
        var marker: UInt8 = 0x80
        var fields = [UInt8]()

        if cell.note != 0 {
            marker |= 0x01
            fields.append(cell.note)
        }
        if cell.instrument != 0 {
            marker |= 0x02
            fields.append(cell.instrument)
        }
        if cell.volumeColumn != 0 {
            marker |= 0x04
            fields.append(cell.volumeColumn)
        }
        if cell.effectType != 0 {
            marker |= 0x08
            fields.append(cell.effectType)
        }
        if cell.effectParam != 0 {
            marker |= 0x10
            fields.append(cell.effectParam)
        }

        return [marker] + fields
    }

    private func exportedInstruments(
        for document: BlankTrackerDocument,
        instrumentCount: Int
    ) throws -> [XMInstrumentExport] {
        guard instrumentCount > 0 else {
            return []
        }

        var instruments = [XMInstrumentExport]()
        instruments.reserveCapacity(instrumentCount)
        for instrumentIndex in 1...instrumentCount {
            let paletteInstrument = document.instrumentPalette[instrumentIndex]
            instruments.append(try exportedInstrument(
                index: instrumentIndex,
                paletteInstrument: paletteInstrument
            ))
        }
        return instruments
    }

    private func exportedInstrument(
        index instrumentIndex: Int,
        paletteInstrument: PlaybackInstrument?
    ) throws -> XMInstrumentExport {
        guard let paletteInstrument else {
            return XMInstrumentExport.noSample(name: nil)
        }

        let samplesWithPayload = paletteInstrument.samples
            .filter { !$0.pcm.isEmpty }
            .sorted { lhs, rhs in
                if lhs.sampleIndex == rhs.sampleIndex {
                    return lhs.name ?? "" < rhs.name ?? ""
                }
                return lhs.sampleIndex < rhs.sampleIndex
            }
        guard samplesWithPayload.count <= Self.maxXMSamplesPerInstrument else {
            throw EditableXMWriterError.unsupportedInstrumentSampleCount(
                instrumentIndex: instrumentIndex,
                sampleCount: samplesWithPayload.count
            )
        }

        var seenSampleIndices = Set<Int>()
        for sample in samplesWithPayload {
            guard seenSampleIndices.insert(sample.sampleIndex).inserted else {
                throw EditableXMWriterError.unsupportedDuplicateSampleIndex(
                    instrumentIndex: instrumentIndex,
                    sampleIndex: sample.sampleIndex
                )
            }
        }

        guard !samplesWithPayload.isEmpty else {
            return XMInstrumentExport.noSample(name: paletteInstrument.name)
        }
        guard paletteInstrument.volumeEnvelope.points.count <= 12 else {
            throw EditableXMWriterError.unsupportedVolumeEnvelopePointCount(
                instrumentIndex: instrumentIndex,
                pointCount: paletteInstrument.volumeEnvelope.points.count
            )
        }

        let exportedSamples = try samplesWithPayload.map { sample in
            try exportedSample(sample, instrumentIndex: instrumentIndex)
        }
        let sampleIndexToOutputIndex = Dictionary(
            uniqueKeysWithValues: samplesWithPayload.enumerated().map { outputIndex, sample in
                (sample.sampleIndex, UInt8(outputIndex))
            }
        )
        let noteSampleMap = exportedNoteSampleMap(
            paletteInstrument.noteSampleMap,
            sampleIndexToOutputIndex: sampleIndexToOutputIndex
        )

        return XMInstrumentExport(
            name: paletteInstrument.name,
            noteSampleMap: noteSampleMap,
            volumeEnvelope: paletteInstrument.volumeEnvelope,
            samples: exportedSamples
        )
    }

    private func exportedSample(_ sample: PlaybackSample, instrumentIndex: Int) throws -> XMSampleExport {
        guard sample.sourceIsSignedPCM == true,
              sample.sourceIsDeltaEncoded == true,
              let bitDepth = sample.sourceBitDepthBits else {
            throw EditableXMWriterError.unsupportedSampleSourceMetadata(
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                bitDepth: sample.sourceBitDepthBits,
                signedPCM: sample.sourceIsSignedPCM,
                deltaEncoded: sample.sourceIsDeltaEncoded
            )
        }
        guard bitDepth == 8 || bitDepth == 16 else {
            throw EditableXMWriterError.unsupportedSampleBitDepth(
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                bitDepth: bitDepth
            )
        }
        guard sample.loopType == 0 || sample.loopType == 1 || sample.loopType == 2 else {
            throw EditableXMWriterError.unsupportedSampleLoopType(
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                loopType: sample.loopType
            )
        }

        let frameCount = min(max(0, sample.sampleLength), sample.pcm.count)
        guard frameCount == sample.pcm.count else {
            throw EditableXMWriterError.unsupportedSampleLength(
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                frameCount: sample.sampleLength,
                bitDepth: bitDepth
            )
        }

        let bytesPerSample = bitDepth / 8
        let payload = XMSampleDeltaEncoder.deltaEncodedSignedPCM(
            pcm: sample.pcm,
            bitDepthBits: bitDepth
        )
        guard let payload,
              payload.count <= Int(UInt32.max) else {
            throw EditableXMWriterError.unsupportedSampleLength(
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                frameCount: frameCount,
                bitDepth: bitDepth
            )
        }

        let loopStartBytes: UInt32
        let loopLengthBytes: UInt32
        if sample.loopType == 0 {
            loopStartBytes = 0
            loopLengthBytes = 0
        } else {
            let loop = sample.loopRegion
            guard loop.isEnabled else {
                throw EditableXMWriterError.unsupportedSampleLoopRegion(
                    instrumentIndex: instrumentIndex,
                    sampleIndex: sample.sampleIndex,
                    loopStart: sample.loopStart,
                    loopLength: sample.loopLength
                )
            }
            loopStartBytes = UInt32(loop.startFrame * bytesPerSample)
            loopLengthBytes = UInt32(loop.lengthFrames * bytesPerSample)
        }

        return XMSampleExport(
            name: sample.name,
            lengthBytes: UInt32(payload.count),
            loopStartBytes: loopStartBytes,
            loopLengthBytes: loopLengthBytes,
            volume: clampedXMVolume(sample.volume),
            finetune: clampedSignedByte(sample.finetune),
            type: sampleType(loopType: sample.loopType, bitDepth: bitDepth),
            panning: sample.panning,
            relativeNote: clampedSignedByte(sample.relativeNote),
            payload: payload
        )
    }

    private func exportedNoteSampleMap(
        _ noteSampleMap: [Int]?,
        sampleIndexToOutputIndex: [Int: UInt8]
    ) -> [UInt8] {
        guard let noteSampleMap, noteSampleMap.count == 96 else {
            return Array(repeating: 0, count: 96)
        }
        return noteSampleMap.map { mappedSampleIndex in
            sampleIndexToOutputIndex[mappedSampleIndex] ?? 0
        }
    }

    private func clampedXMVolume(_ volume: Float) -> UInt8 {
        let finiteVolume = volume.isFinite ? volume : 0
        let scaled = Int((finiteVolume * 64).rounded())
        return UInt8(max(0, min(64, scaled)))
    }

    private func clampedSignedByte(_ value: Int) -> UInt8 {
        UInt8(bitPattern: Int8(clamping: value))
    }

    private func sampleType(loopType: Int, bitDepth: Int) -> UInt8 {
        var type = UInt8(loopType & 0x03)
        if bitDepth == 16 {
            type |= 0x10
        }
        return type
    }
}

private struct XMInstrumentExport {
    let name: String?
    let noteSampleMap: [UInt8]
    let volumeEnvelope: PlaybackVolumeEnvelope
    let samples: [XMSampleExport]

    static func noSample(name: String?) -> XMInstrumentExport {
        XMInstrumentExport(
            name: name,
            noteSampleMap: Array(repeating: 0, count: 96),
            volumeEnvelope: .disabled,
            samples: []
        )
    }
}

private struct XMSampleExport {
    let name: String?
    let lengthBytes: UInt32
    let loopStartBytes: UInt32
    let loopLengthBytes: UInt32
    let volume: UInt8
    let finetune: UInt8
    let type: UInt8
    let panning: UInt8
    let relativeNote: UInt8
    let payload: Data
}

enum XMSampleDeltaEncoder {
    static func deltaEncodedSignedPCM(pcm: [Float], bitDepthBits: Int) -> Data? {
        switch bitDepthBits {
        case 8:
            return deltaEncoded8BitPCM(pcm)
        case 16:
            return deltaEncoded16BitPCM(pcm)
        default:
            return nil
        }
    }

    private static func deltaEncoded8BitPCM(_ pcm: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(pcm.count)
        var previous = 0
        for sample in pcm {
            let current = quantizedSignedSample(sample, bitDepthBits: 8)
            data.append(UInt8(truncatingIfNeeded: current - previous))
            previous = current
        }
        return data
    }

    private static func deltaEncoded16BitPCM(_ pcm: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(pcm.count * 2)
        var previous = 0
        for sample in pcm {
            let current = quantizedSignedSample(sample, bitDepthBits: 16)
            let delta = UInt16(truncatingIfNeeded: current - previous)
            data.append(UInt8(delta & 0x00FF))
            data.append(UInt8((delta >> 8) & 0x00FF))
            previous = current
        }
        return data
    }

    private static func quantizedSignedSample(_ sample: Float, bitDepthBits: Int) -> Int {
        let finiteSample = sample.isFinite ? sample : 0
        switch bitDepthBits {
        case 8:
            return max(-128, min(127, Int((finiteSample * 128).rounded())))
        case 16:
            return max(-32_768, min(32_767, Int((finiteSample * 32_768).rounded())))
        default:
            return 0
        }
    }
}

private struct XMByteWriter {
    private(set) var data = Data()

    mutating func appendUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func appendUInt16(_ value: UInt16) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        data.append(UInt8(value & 0x000000FF))
        data.append(UInt8((value >> 8) & 0x000000FF))
        data.append(UInt8((value >> 16) & 0x000000FF))
        data.append(UInt8((value >> 24) & 0x000000FF))
    }

    mutating func appendASCII(_ value: String) {
        data.append(contentsOf: value.utf8)
    }

    mutating func appendFixedASCII(_ value: String, length: Int, fallback: String) {
        let source = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = EditableXMTextEncoding.sanitizedASCIIBytes(from: source.isEmpty ? fallback : source)
        data.append(contentsOf: sanitized.prefix(length))
        if sanitized.count < length {
            data.append(contentsOf: Array(repeating: UInt8(0), count: length - sanitized.count))
        }
    }

    mutating func appendOrderTable(_ orderTable: [Int]) {
        data.append(contentsOf: orderTable.map(UInt8.init))
        data.append(contentsOf: Array(repeating: UInt8(0), count: max(0, 256 - orderTable.count)))
    }

    mutating func appendData(_ value: Data) {
        data.append(value)
    }

    mutating func appendInstrument(_ instrument: XMInstrumentExport) {
        if instrument.samples.isEmpty {
            appendUInt32(EditableXMWriter.instrumentHeaderSize)
            appendFixedASCII(instrument.name ?? "", length: 22, fallback: "")
            appendUInt8(0)
            appendUInt16(0)
            return
        }

        appendUInt32(EditableXMWriter.instrumentHeaderSizeWithSamples)
        appendFixedASCII(instrument.name ?? "", length: 22, fallback: "")
        appendUInt8(0)
        appendUInt16(UInt16(instrument.samples.count))
        appendUInt32(EditableXMWriter.sampleHeaderSize)
        data.append(contentsOf: instrument.noteSampleMap.prefix(96))
        if instrument.noteSampleMap.count < 96 {
            data.append(contentsOf: Array(repeating: UInt8(0), count: 96 - instrument.noteSampleMap.count))
        }
        appendVolumeEnvelope(instrument.volumeEnvelope)
        data.append(contentsOf: Array(repeating: UInt8(0), count: 48))
        appendUInt8(UInt8(instrument.volumeEnvelope.points.count))
        appendUInt8(0)
        appendUInt8(envelopePointIndex(instrument.volumeEnvelope.sustainPointIndex, points: instrument.volumeEnvelope.points))
        appendUInt8(envelopePointIndex(instrument.volumeEnvelope.loopStartPointIndex, points: instrument.volumeEnvelope.points))
        appendUInt8(envelopePointIndex(instrument.volumeEnvelope.loopEndPointIndex, points: instrument.volumeEnvelope.points))
        appendUInt8(0)
        appendUInt8(0)
        appendUInt8(0)
        appendUInt8(instrument.volumeEnvelope.points.isEmpty ? 0 : instrument.volumeEnvelope.typeFlags & 0x07)
        appendUInt8(0)
        appendUInt8(0)
        appendUInt8(0)
        appendUInt8(0)
        appendUInt8(0)
        appendUInt16(UInt16(max(0, min(65_535, instrument.volumeEnvelope.fadeout))))
        data.append(contentsOf: Array(repeating: UInt8(0), count: 22))

        for sample in instrument.samples {
            appendSampleHeader(sample)
        }
        for sample in instrument.samples {
            appendData(sample.payload)
        }
    }

    private mutating func appendVolumeEnvelope(_ envelope: PlaybackVolumeEnvelope) {
        for pointIndex in 0..<12 {
            if envelope.points.indices.contains(pointIndex) {
                let point = envelope.points[pointIndex]
                appendUInt16(UInt16(max(0, min(65_535, point.tick))))
                appendUInt16(UInt16(max(0, min(64, point.value))))
            } else {
                appendUInt16(0)
                appendUInt16(0)
            }
        }
    }

    private mutating func appendSampleHeader(_ sample: XMSampleExport) {
        appendUInt32(sample.lengthBytes)
        appendUInt32(sample.loopStartBytes)
        appendUInt32(sample.loopLengthBytes)
        appendUInt8(sample.volume)
        appendUInt8(sample.finetune)
        appendUInt8(sample.type)
        appendUInt8(sample.panning)
        appendUInt8(sample.relativeNote)
        appendUInt8(0)
        appendFixedASCII(sample.name ?? "", length: 22, fallback: "")
    }

    private func envelopePointIndex(_ index: Int?, points: [PlaybackEnvelopePoint]) -> UInt8 {
        guard let index,
              points.indices.contains(index) else {
            return 0
        }
        return UInt8(index)
    }

}
