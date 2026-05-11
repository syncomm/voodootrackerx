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
    static func build(
        from metadata: ParsedModuleMetadata,
        modulePath: String? = nil,
        endBehavior: PlaybackEndBehavior = .stopAtEnd
    ) throws -> PlaybackSong {
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
            instrumentsByIndex: modulePath.map { loadXMSampleInstruments(fromPath: $0, metadata: metadata) } ?? [:],
            restartOrderIndex: 0,
            endBehavior: endBehavior,
            initialTiming: PlaybackTiming(
                speed: metadata.defaultTempo > 0 ? metadata.defaultTempo : PlaybackTiming.xmDefault.speed,
                bpm: metadata.defaultBPM > 0 ? metadata.defaultBPM : PlaybackTiming.xmDefault.bpm
            ),
            usesLinearFrequencyTable: metadata.usesLinearFrequencyTable
        )
    }

    private static func loadXMSampleInstruments(fromPath path: String, metadata: ParsedModuleMetadata) -> [Int: PlaybackInstrument] {
        guard metadata.type == "XM",
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              data.count >= 80,
              data.starts(with: Data("Extended Module: ".utf8)) else {
            return [:]
        }
        let headerSize = Int(readLE32(data, offset: 60))
        let totalHeader = 60 + headerSize
        guard headerSize >= 20, totalHeader <= data.count else {
            return [:]
        }

        var offset = totalHeader
        for _ in 0..<metadata.patterns {
            guard offset + 9 <= data.count else {
                return [:]
            }
            let patternHeaderLength = Int(readLE32(data, offset: offset))
            let packedSize = Int(readLE16(data, offset: offset + 7))
            guard patternHeaderLength >= 9,
                  offset + patternHeaderLength + packedSize <= data.count else {
                return [:]
            }
            offset += patternHeaderLength + packedSize
        }

        var instruments = [Int: PlaybackInstrument]()
        guard metadata.instruments > 0 else {
            return instruments
        }
        for instrumentIndex in 1...metadata.instruments {
            guard offset + 29 <= data.count else {
                break
            }
            let instrumentHeaderSize = Int(readLE32(data, offset: offset))
            let sampleCount = Int(readLE16(data, offset: offset + 27))
            guard instrumentHeaderSize >= 29,
                  offset + instrumentHeaderSize <= data.count else {
                break
            }
            guard sampleCount > 0 else {
                offset += instrumentHeaderSize
                continue
            }
            guard offset + 33 <= data.count else {
                break
            }
            let volumeEnvelope = readVolumeEnvelope(data, instrumentOffset: offset, instrumentHeaderSize: instrumentHeaderSize)
            let sampleHeaderSize = max(40, Int(readLE32(data, offset: offset + 29)))
            let sampleHeaderOffset = offset + instrumentHeaderSize
            let sampleDataOffset = sampleHeaderOffset + (sampleHeaderSize * sampleCount)
            guard sampleDataOffset <= data.count else {
                break
            }

            var sampleHeaders = [XMSampleHeader]()
            sampleHeaders.reserveCapacity(sampleCount)
            for sampleIndex in 0..<sampleCount {
                let headerOffset = sampleHeaderOffset + (sampleIndex * sampleHeaderSize)
                guard headerOffset + 40 <= data.count else {
                    break
                }
                sampleHeaders.append(readSampleHeader(data, offset: headerOffset))
            }

            var dataOffset = sampleDataOffset
            let samples = sampleHeaders.enumerated().compactMap { sampleIndex, header -> PlaybackSample? in
                guard header.length > 0,
                      dataOffset + header.length <= data.count else {
                    dataOffset += max(0, header.length)
                    return nil
                }
                let pcm = decodeSamplePCM(data, offset: dataOffset, header: header)
                dataOffset += header.length
                return PlaybackSample(
                    instrumentIndex: instrumentIndex,
                    sampleIndex: sampleIndex,
                    pcm: pcm,
                    volume: min(1, Float(header.volume) / 64.0),
                    relativeNote: header.relativeNote,
                    finetune: header.finetune,
                    baseSampleRate: 8_363,
                    sampleLength: pcm.count,
                    loopStart: header.safeLoopStartInSamples,
                    loopLength: header.safeLoopLengthInSamples,
                    loopType: header.loopType
                )
            }
            instruments[instrumentIndex] = PlaybackInstrument(index: instrumentIndex, samples: samples, volumeEnvelope: volumeEnvelope)
            offset = dataOffset
        }
        return instruments
    }

    private static func readVolumeEnvelope(
        _ data: Data,
        instrumentOffset: Int,
        instrumentHeaderSize: Int
    ) -> PlaybackVolumeEnvelope {
        let envelopePointOffset = instrumentOffset + 129
        let minimumEnvelopeHeaderSize = 241
        guard instrumentHeaderSize >= minimumEnvelopeHeaderSize,
              instrumentOffset + minimumEnvelopeHeaderSize <= data.count,
              instrumentOffset + instrumentHeaderSize <= data.count else {
            return .disabled
        }

        let pointCount = min(12, Int(data[instrumentOffset + 225]))
        var points = [PlaybackEnvelopePoint]()
        points.reserveCapacity(pointCount)
        for pointIndex in 0..<pointCount {
            let pointOffset = envelopePointOffset + (pointIndex * 4)
            guard pointOffset + 4 <= instrumentOffset + instrumentHeaderSize,
                  pointOffset + 4 <= data.count else {
                break
            }
            points.append(PlaybackEnvelopePoint(
                tick: Int(readLE16(data, offset: pointOffset)),
                value: Int(readLE16(data, offset: pointOffset + 2))
            ))
        }

        let typeFlags = data[instrumentOffset + 233]
        let sustainIndex = Int(data[instrumentOffset + 227])
        let loopStartIndex = Int(data[instrumentOffset + 228])
        let loopEndIndex = Int(data[instrumentOffset + 229])
        let fadeout = Int(readLE16(data, offset: instrumentOffset + 239))

        return PlaybackVolumeEnvelope(
            enabled: (typeFlags & 0x01) != 0 && !points.isEmpty,
            points: points,
            sustainPointIndex: points.indices.contains(sustainIndex) ? sustainIndex : nil,
            loopStartPointIndex: points.indices.contains(loopStartIndex) ? loopStartIndex : nil,
            loopEndPointIndex: points.indices.contains(loopEndIndex) && loopEndIndex >= loopStartIndex ? loopEndIndex : nil,
            typeFlags: typeFlags,
            fadeout: max(0, min(65_536, fadeout))
        )
    }

    private struct XMSampleHeader {
        let length: Int
        let loopStart: Int
        let loopLength: Int
        let volume: UInt8
        let finetune: Int
        let type: UInt8
        let relativeNote: Int

        var is16Bit: Bool {
            (type & 0x10) != 0
        }

        var loopType: Int {
            Int(type & 0x03)
        }

        var bytesPerSample: Int {
            is16Bit ? 2 : 1
        }

        var lengthInSamples: Int {
            length / bytesPerSample
        }

        var safeLoopStartInSamples: Int {
            min(max(0, loopStart / bytesPerSample), lengthInSamples)
        }

        var safeLoopLengthInSamples: Int {
            guard loopType != 0 else {
                return 0
            }
            let start = safeLoopStartInSamples
            let requestedLength = max(0, loopLength / bytesPerSample)
            return min(requestedLength, max(0, lengthInSamples - start))
        }
    }

    private static func readSampleHeader(_ data: Data, offset: Int) -> XMSampleHeader {
        XMSampleHeader(
            length: Int(readLE32(data, offset: offset)),
            loopStart: Int(readLE32(data, offset: offset + 4)),
            loopLength: Int(readLE32(data, offset: offset + 8)),
            volume: data[offset + 12],
            finetune: Int(Int8(bitPattern: data[offset + 13])),
            type: data[offset + 14],
            relativeNote: Int(Int8(bitPattern: data[offset + 16]))
        )
    }

    private static func decodeSamplePCM(_ data: Data, offset: Int, header: XMSampleHeader) -> [Float] {
        if header.is16Bit {
            let sampleCount = header.length / 2
            var pcm = [Float]()
            pcm.reserveCapacity(sampleCount)
            var accumulator = Int16(0)
            for sampleIndex in 0..<sampleCount {
                let delta = Int16(bitPattern: readLE16(data, offset: offset + (sampleIndex * 2)))
                accumulator = accumulator &+ delta
                pcm.append(max(-1, min(1, Float(accumulator) / 32768.0)))
            }
            return pcm
        }

        var pcm = [Float]()
        pcm.reserveCapacity(header.length)
        var accumulator = Int8(0)
        for sampleIndex in 0..<header.length {
            let delta = Int8(bitPattern: data[offset + sampleIndex])
            accumulator = accumulator &+ delta
            pcm.append(max(-1, min(1, Float(accumulator) / 128.0)))
        }
        return pcm
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
}
