import Foundation

enum EditableXMWriterError: Error, Equatable {
    case unsupportedOrderLength(Int)
    case unsupportedPatternIndex(Int)
    case unsupportedPatternCount(Int)
    case unsupportedInstrumentCount(Int)
}

struct EditableXMWriter {
    private static let xmSignature = "Extended Module: "
    private static let trackerName = "VoodooTrackerX"
    private static let xmVersion: UInt16 = 0x0104
    private static let xmHeaderSize: UInt32 = 276
    private static let patternHeaderSize: UInt32 = 9
    private static let instrumentHeaderSize: UInt32 = 29
    private static let maxXMOrderEntries = 256
    private static let maxXMPatternIndex = 255
    private static let maxXMChannels = 32
    private static let maxXMPatternRows = 256
    private static let maxXMInstruments = 255

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

        for _ in 0..<instrumentCount {
            writer.appendUInt32(Self.instrumentHeaderSize)
            writer.appendFixedASCII("", length: 22, fallback: "")
            writer.appendUInt8(0)
            writer.appendUInt16(0)
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
        let sanitized = sanitizedASCIIBytes(from: source.isEmpty ? fallback : source)
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

    private func sanitizedASCIIBytes(from value: String) -> [UInt8] {
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
