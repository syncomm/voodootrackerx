import Foundation

enum PlaybackSongBuilderError: LocalizedError, Equatable {
    case unsupportedModuleType(String)
    case missingPatterns
    case missingPlayableOrders

    var errorDescription: String? {
        switch self {
        case let .unsupportedModuleType(type):
            return "Playback song model only supports XM metadata for now; got \(type)."
        case .missingPatterns:
            return "Playback song model requires decoded XM patterns."
        case .missingPlayableOrders:
            return "Playback song model requires at least one order entry that references a decoded pattern."
        }
    }
}

enum PlaybackSongBuilder {
    static func build(from metadata: ParsedModuleMetadata, endBehavior: PlaybackEndBehavior = .stopAtEnd) throws -> PlaybackSong {
        guard metadata.type == "XM" else {
            throw PlaybackSongBuilderError.unsupportedModuleType(metadata.type)
        }
        guard !metadata.xmPatterns.isEmpty else {
            throw PlaybackSongBuilderError.missingPatterns
        }

        let patterns = metadata.xmPatterns.reduce(into: [Int: PlaybackPattern]()) { partialResult, pattern in
            partialResult[pattern.index] = PlaybackPattern(
                index: pattern.index,
                rows: pattern.rows.enumerated().map { rowIndex, cells in
                    PlaybackRow(
                        index: rowIndex,
                        cells: cells.map {
                            PlaybackCell(
                                note: $0.note,
                                instrument: $0.instrument,
                                volumeColumn: $0.volumeColumn,
                                effectType: $0.effectType,
                                effectParam: $0.effectParam
                            )
                        }
                    )
                }
            )
        }

        let effectiveOrderTable = metadata.orderTable.prefix(max(0, metadata.songLength))
        let playablePatternIndices = effectiveOrderTable.compactMap { patternIndex -> Int? in
            guard patterns[patternIndex] != nil else {
                return nil
            }
            return patternIndex
        }
        let orders = playablePatternIndices.enumerated().map { orderIndex, patternIndex in
            PlaybackOrderEntry(orderIndex: orderIndex, patternIndex: patternIndex)
        }
        guard !orders.isEmpty else {
            throw PlaybackSongBuilderError.missingPlayableOrders
        }

        return PlaybackSong(
            title: metadata.title,
            orders: orders,
            patternsByIndex: patterns,
            restartOrderIndex: 0,
            endBehavior: endBehavior
        )
    }
}
