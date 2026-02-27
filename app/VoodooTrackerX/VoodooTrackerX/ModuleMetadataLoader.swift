import Foundation

struct XMPatternEventCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8

    static let empty = XMPatternEventCell(
        note: 0,
        instrument: 0,
        volumeColumn: 0,
        effectType: 0,
        effectParam: 0
    )
}

struct XMPatternData: Equatable {
    let index: Int
    let rowCount: Int
    let channels: Int
    var rows: [[XMPatternEventCell]]
}

struct ParsedModuleMetadata: Equatable {
    let type: String
    let title: String
    let version: String?
    let channels: Int
    let patterns: Int
    let instruments: Int
    let songLength: Int
    let orderTable: [Int]
    let xmPatterns: [XMPatternData]

    var displayText: String {
        var lines = [
            "Type: \(type)",
            "Title: \(title.isEmpty ? "(empty)" : title)",
        ]
        if let version {
            lines.append("Version: \(version)")
        }
        lines.append("Channels: \(channels)")
        lines.append("Patterns: \(patterns)")
        lines.append("Instruments: \(instruments)")
        lines.append("Song Length: \(songLength)")
        return lines.joined(separator: "\n")
    }
}

enum ModuleMetadataLoaderError: LocalizedError {
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case let .parseFailed(message):
            return message
        }
    }
}

public struct ModuleMetadataLoader {
    public struct PatternSelectionEntry: Equatable {
        public let patternIndex: Int
        public let isUsed: Bool
        public let rowCount: Int
    }

    public struct PatternSelectionResult: Equatable {
        public let entries: [PatternSelectionEntry]
        public let invalidReferencedPatterns: [Int]
    }

    func load(fromPath path: String) throws -> ParsedModuleMetadata {
        let info = mc_parse_file(path)
        guard info.ok != 0 else {
            throw ModuleMetadataLoaderError.parseFailed(Self.string(from: info.error))
        }

        let typeName = String(cString: mc_module_type_name(info.type))
        let version: String?
        if info.type == MC_MODULE_TYPE_XM {
            version = "\(info.version_major).\(info.version_minor)"
        } else {
            version = nil
        }
        let orderTable = Self.parseOrderTable(from: info)
        let xmPatterns = Self.parseXMPatterns(from: info, path: path)

        return ParsedModuleMetadata(
            type: typeName,
            title: Self.string(from: info.title),
            version: version,
            channels: Int(info.channels),
            patterns: Int(info.patterns),
            instruments: Int(info.instruments),
            songLength: Int(info.song_length),
            orderTable: orderTable,
            xmPatterns: xmPatterns
        )
    }

    static func formatXMCell(_ cell: XMPatternEventCell) -> String {
        let note = formatXMNote(cell.note)
        let instrument = cell.instrument == 0 ? ".." : String(format: "%02X", cell.instrument)
        let volume = cell.volumeColumn == 0 ? ".." : String(format: "%02X", cell.volumeColumn)
        let effect: String
        if cell.effectType == 0 && cell.effectParam == 0 {
            effect = "..."
        } else {
            effect = String(format: "%1X%02X", cell.effectType, cell.effectParam)
        }
        return "\(note) \(instrument) \(volume) \(effect)"
    }

    static func formatXMNote(_ note: UInt8) -> String {
        if note == 0 {
            return "..."
        }
        if note == 97 {
            return "==="
        }
        guard note <= 96 else {
            return "???"
        }
        let names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
        let value = Int(note) - 1
        let name = names[value % 12]
        let octave = value / 12
        return "\(name)\(octave)"
    }

    static func renderXMPatternInfoLine(_ pattern: XMPatternData, focusedChannel: Int = 0) -> String {
        let safeFocusedChannel = max(0, min(pattern.channels - 1, focusedChannel))
        return "Pattern \(pattern.index)  Rows: \(pattern.rowCount)  Channels: \(pattern.channels)  Focus: CH\(String(format: "%02d", safeFocusedChannel + 1))"
    }

    static func renderXMPatternRows(_ pattern: XMPatternData) -> (
        rowNumberText: String,
        rowNumberRanges: [NSRange],
        gridText: String,
        rowRanges: [NSRange]
    ) {
        var rowNumberLines = [String]()
        var rowLines = [String]()
        var rowNumberRanges = [NSRange]()
        var rowRanges = [NSRange]()
        var rowNumberOffset = 0
        var rowOffset = 0
        let separator = String(repeating: " ", count: xmRenderedCellSeparatorWidth)

        for rowIndex in 0..<pattern.rowCount {
            let rowNumberLine = String(format: "%02X", rowIndex)
            let rowCells = pattern.rows[rowIndex].map(Self.formatXMCell).joined(separator: separator)

            rowNumberRanges.append(NSRange(location: rowNumberOffset, length: rowNumberLine.utf16.count))
            rowRanges.append(NSRange(location: rowOffset, length: rowCells.utf16.count))

            rowNumberLines.append(rowNumberLine)
            rowLines.append(rowCells)

            rowNumberOffset += rowNumberLine.utf16.count + 1
            rowOffset += rowCells.utf16.count + 1
        }

        return (
            rowNumberLines.joined(separator: "\n"),
            rowNumberRanges,
            rowLines.joined(separator: "\n"),
            rowRanges
        )
    }

    static func renderXMChannelHeader(channels: Int) -> String {
        let clampedChannels = max(0, channels)
        guard clampedChannels > 0 else {
            return ""
        }

        var cells = [String]()
        cells.reserveCapacity(clampedChannels)
        for channelIndex in 0..<clampedChannels {
            let label = String(format: "CH%02d", channelIndex + 1)
            cells.append(centered(label, width: xmRenderedCellWidth))
        }
        let separator = String(repeating: " ", count: xmRenderedCellSeparatorWidth)
        return cells.joined(separator: separator)
    }

    static var xmRenderedCellWidth: Int {
        formatXMCell(.empty).utf16.count
    }

    static let xmRenderedRowNumberWidth = 2
    static let xmRenderedCellSeparatorWidth = 3

    public static func buildPatternSelection(
        orderTable: [Int],
        patternCount: Int,
        rowCounts: [Int],
        showAllPatterns: Bool,
        usedPatternIndices: Set<Int>? = nil
    ) -> PatternSelectionResult {
        let safePatternCount = max(0, patternCount)
        var usedUnique = [Int]()
        var usedSeen = Set<Int>()
        var invalidReferenced = [Int]()

        for patternIndex in orderTable {
            if patternIndex >= 0 && patternIndex < safePatternCount {
                if !usedSeen.contains(patternIndex) {
                    usedSeen.insert(patternIndex)
                    usedUnique.append(patternIndex)
                }
            } else {
                invalidReferenced.append(patternIndex)
            }
        }
        if let usedPatternIndices {
            usedSeen = usedPatternIndices.filter { $0 >= 0 && $0 < safePatternCount }.reduce(into: Set<Int>()) { partialResult, index in
                partialResult.insert(index)
            }
            usedUnique = usedSeen.sorted()
        }

        var entries = [PatternSelectionEntry]()
        if showAllPatterns {
            entries.reserveCapacity(safePatternCount)
            for patternIndex in 0..<safePatternCount {
                let rowCount = patternIndex < rowCounts.count ? max(1, rowCounts[patternIndex]) : 64
                entries.append(
                    PatternSelectionEntry(
                        patternIndex: patternIndex,
                        isUsed: usedSeen.contains(patternIndex),
                        rowCount: rowCount
                    )
                )
            }
        } else {
            let usedSorted = usedUnique.sorted()
            entries.reserveCapacity(usedSorted.count)
            for patternIndex in usedSorted {
                let rowCount = patternIndex < rowCounts.count ? max(1, rowCounts[patternIndex]) : 64
                entries.append(
                    PatternSelectionEntry(
                        patternIndex: patternIndex,
                        isUsed: true,
                        rowCount: rowCount
                    )
                )
            }
            if entries.isEmpty && safePatternCount > 0 {
                let rowCount = rowCounts.isEmpty ? 64 : max(1, rowCounts[0])
                entries.append(
                    PatternSelectionEntry(
                        patternIndex: 0,
                        isUsed: false,
                        rowCount: rowCount
                    )
                )
            }
        }

        return PatternSelectionResult(entries: entries, invalidReferencedPatterns: invalidReferenced)
    }

    private static func string<T>(from tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }

    private static func parseXMPatterns(from info: mc_module_info, path: String) -> [XMPatternData] {
        guard info.type == MC_MODULE_TYPE_XM else {
            return []
        }
        if let decoded = parseXMPatternsFromFile(path: path, channels: Int(info.channels), patternCount: Int(info.patterns)) {
            return decoded
        }
        return parseXMPatternsFromInfo(info)
    }

    private static func parseXMPatternsFromInfo(_ info: mc_module_info) -> [XMPatternData] {
        guard info.type == MC_MODULE_TYPE_XM else {
            return []
        }

        let channelCount = max(1, Int(info.channels))
        let patternCount = Int(info.patterns)
        guard patternCount > 0 else {
            return []
        }

        let rowCounts: [UInt16] = withUnsafePointer(to: info.pattern_row_counts) {
            $0.withMemoryRebound(to: UInt16.self, capacity: Int(MC_MAX_PATTERN_ROW_COUNTS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_PATTERN_ROW_COUNTS)))
            }
        }

        var patterns = [XMPatternData]()
        patterns.reserveCapacity(patternCount)

        for patternIndex in 0..<patternCount {
            let rowCount = patternIndex < Int(info.pattern_row_count_count) ? max(1, Int(rowCounts[patternIndex])) : 64
            let rows = Array(
                repeating: Array(repeating: XMPatternEventCell.empty, count: channelCount),
                count: rowCount
            )
            patterns.append(
                XMPatternData(
                    index: patternIndex,
                    rowCount: rowCount,
                    channels: channelCount,
                    rows: rows
                )
            )
        }

        let xmEvents: [mc_xm_event] = withUnsafePointer(to: info.xm_events) {
            $0.withMemoryRebound(to: mc_xm_event.self, capacity: Int(MC_MAX_XM_EVENTS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_XM_EVENTS)))
            }
        }

        for event in xmEvents.prefix(Int(info.xm_event_count)) {
            let patternIndex = Int(event.pattern)
            let rowIndex = Int(event.row)
            let channelIndex = Int(event.channel)

            guard patterns.indices.contains(patternIndex) else {
                continue
            }
            guard rowIndex >= 0, rowIndex < patterns[patternIndex].rowCount else {
                continue
            }
            guard channelIndex >= 0, channelIndex < patterns[patternIndex].channels else {
                continue
            }

            patterns[patternIndex].rows[rowIndex][channelIndex] = XMPatternEventCell(
                note: event.note,
                instrument: event.instrument,
                volumeColumn: event.volume,
                effectType: event.effect_type,
                effectParam: event.effect_param
            )
        }

        return patterns
    }

    private static func parseXMPatternsFromFile(path: String, channels: Int, patternCount: Int) -> [XMPatternData]? {
        guard patternCount > 0 else {
            return []
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              data.count >= 80,
              data.starts(with: Data("Extended Module: ".utf8)) else {
            return nil
        }
        let headerSize = Int(readLE32(data, offset: 60))
        let totalHeader = 60 + headerSize
        guard headerSize >= 20, totalHeader <= data.count else {
            return nil
        }

        var patterns = [XMPatternData]()
        patterns.reserveCapacity(patternCount)
        var patternOffset = totalHeader
        let channelCount = max(1, channels)

        for patternIndex in 0..<patternCount {
            guard patternOffset + 9 <= data.count else {
                return nil
            }
            let patternHeaderLength = Int(readLE32(data, offset: patternOffset))
            guard patternHeaderLength >= 9, patternOffset + patternHeaderLength <= data.count else {
                return nil
            }
            let rowCount = max(1, Int(readLE16(data, offset: patternOffset + 5)))
            let packedSize = Int(readLE16(data, offset: patternOffset + 7))
            let patternDataStart = patternOffset + patternHeaderLength
            let patternDataEnd = patternDataStart + packedSize
            guard patternDataEnd <= data.count else {
                return nil
            }

            var rows = Array(
                repeating: Array(repeating: XMPatternEventCell.empty, count: channelCount),
                count: rowCount
            )

            if packedSize > 0 {
                var eventOffset = 0
                for row in 0..<rowCount {
                    for channel in 0..<channelCount {
                        guard let decoded = decodeXMPatternEvent(
                            data: data,
                            start: patternDataStart,
                            length: packedSize,
                            offset: eventOffset
                        ) else {
                            return nil
                        }
                        eventOffset = decoded.nextOffset
                        rows[row][channel] = decoded.cell
                    }
                }
            }

            patterns.append(
                XMPatternData(
                    index: patternIndex,
                    rowCount: rowCount,
                    channels: channelCount,
                    rows: rows
                )
            )

            patternOffset = patternDataEnd
        }

        return patterns
    }

    private static func decodeXMPatternEvent(
        data: Data,
        start: Int,
        length: Int,
        offset: Int
    ) -> (cell: XMPatternEventCell, nextOffset: Int)? {
        guard offset < length else { return nil }
        let firstByte = data[start + offset]
        var nextOffset = offset + 1
        var note: UInt8 = 0
        var instrument: UInt8 = 0
        var volume: UInt8 = 0
        var effectType: UInt8 = 0
        var effectParam: UInt8 = 0

        if (firstByte & 0x80) != 0 {
            if (firstByte & 0x01) != 0 {
                guard nextOffset < length else { return nil }
                note = data[start + nextOffset]
                nextOffset += 1
            }
            if (firstByte & 0x02) != 0 {
                guard nextOffset < length else { return nil }
                instrument = data[start + nextOffset]
                nextOffset += 1
            }
            if (firstByte & 0x04) != 0 {
                guard nextOffset < length else { return nil }
                volume = data[start + nextOffset]
                nextOffset += 1
            }
            if (firstByte & 0x08) != 0 {
                guard nextOffset < length else { return nil }
                effectType = data[start + nextOffset]
                nextOffset += 1
            }
            if (firstByte & 0x10) != 0 {
                guard nextOffset < length else { return nil }
                effectParam = data[start + nextOffset]
                nextOffset += 1
            }
        } else {
            guard nextOffset + 4 <= length else { return nil }
            note = firstByte
            instrument = data[start + nextOffset]
            nextOffset += 1
            volume = data[start + nextOffset]
            nextOffset += 1
            effectType = data[start + nextOffset]
            nextOffset += 1
            effectParam = data[start + nextOffset]
            nextOffset += 1
        }

        return (
            XMPatternEventCell(
                note: note,
                instrument: instrument,
                volumeColumn: volume,
                effectType: effectType,
                effectParam: effectParam
            ),
            nextOffset
        )
    }

    private static func readLE16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readLE32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func parseOrderTable(from info: mc_module_info) -> [Int] {
        let count = Int(info.order_table_length)
        guard count > 0 else {
            return []
        }
        let songLength = Int(info.song_length)
        let effectiveCount: Int
        if songLength > 0 {
            effectiveCount = min(count, songLength)
        } else {
            effectiveCount = count
        }
        let values: [UInt8] = withUnsafePointer(to: info.order_table) {
            $0.withMemoryRebound(to: UInt8.self, capacity: Int(MC_MAX_ORDER_ENTRIES)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_ORDER_ENTRIES)))
            }
        }
        return values.prefix(effectiveCount).map(Int.init)
    }

    private static func centered(_ value: String, width: Int) -> String {
        let trimmed = String(value.prefix(max(0, width)))
        let valueWidth = trimmed.utf16.count
        guard valueWidth < width else {
            return trimmed
        }
        let totalPadding = width - valueWidth
        let leftPadding = totalPadding / 2
        let rightPadding = totalPadding - leftPadding
        return String(repeating: " ", count: leftPadding) + trimmed + String(repeating: " ", count: rightPadding)
    }
}
