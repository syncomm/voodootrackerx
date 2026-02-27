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
        let xmPatterns = Self.parseXMPatterns(from: info)

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

    static func renderXMPattern(
        _ pattern: XMPatternData,
        highlightedRow: Int? = nil,
        focusedChannel: Int = 0
    ) -> (text: String, rowRanges: [NSRange]) {
        var lines = [String]()
        var rowRanges = [NSRange]()
        let safeFocusedChannel = max(0, min(pattern.channels - 1, focusedChannel))
        lines.append("Pattern \(pattern.index)  Rows: \(pattern.rowCount)  Channels: \(pattern.channels)  Focus: CH\(String(format: "%02d", safeFocusedChannel + 1))")
        lines.append("")

        var currentOffset = 0
        currentOffset += lines[0].utf16.count + 1
        currentOffset += lines[1].utf16.count + 1

        for rowIndex in 0..<pattern.rowCount {
            let rowCells = pattern.rows[rowIndex].map(Self.formatXMCell).joined(separator: " | ")
            let rowLine = "\(String(format: "%03d", rowIndex)) | \(rowCells)"
            rowRanges.append(NSRange(location: currentOffset, length: rowLine.utf16.count))
            lines.append(rowLine)
            currentOffset += rowLine.utf16.count + 1
        }

        return (lines.joined(separator: "\n"), rowRanges)
    }

    static func renderXMChannelHeader(channels: Int) -> String {
        let clampedChannels = max(0, channels)
        let leading = String(repeating: " ", count: xmRenderedRowPrefixWidth)
        guard clampedChannels > 0 else {
            return leading
        }

        var cells = [String]()
        cells.reserveCapacity(clampedChannels)
        for channelIndex in 0..<clampedChannels {
            let label = String(format: "CH%02d", channelIndex + 1)
            let padded = label.padding(toLength: xmRenderedCellWidth, withPad: " ", startingAt: 0)
            cells.append(String(padded.prefix(xmRenderedCellWidth)))
        }
        return leading + cells.joined(separator: " | ")
    }

    static var xmRenderedCellWidth: Int {
        formatXMCell(.empty).utf16.count
    }

    static let xmRenderedRowPrefixWidth = "000 | ".utf16.count
    static let xmRenderedCellSeparatorWidth = " | ".utf16.count

    public static func buildPatternSelection(
        orderTable: [Int],
        patternCount: Int,
        rowCounts: [Int],
        showAllPatterns: Bool
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
            entries.reserveCapacity(usedUnique.count)
            for patternIndex in usedUnique {
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

    private static func parseXMPatterns(from info: mc_module_info) -> [XMPatternData] {
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

    private static func parseOrderTable(from info: mc_module_info) -> [Int] {
        let count = Int(info.order_table_length)
        guard count > 0 else {
            return []
        }
        let values: [UInt8] = withUnsafePointer(to: info.order_table) {
            $0.withMemoryRebound(to: UInt8.self, capacity: Int(MC_MAX_ORDER_ENTRIES)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_ORDER_ENTRIES)))
            }
        }
        return values.prefix(count).map(Int.init)
    }
}
