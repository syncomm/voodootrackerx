import Foundation
struct AIFFSampleImportInspection: Equatable, Sendable {
    let sourceSampleRate: Double
    let sourceChannelCount, sourceBitDepthBits, frameCount: Int
}
struct AIFFSampleImportDecoder: Sendable {
    let chunkFrameCount: Int
    init(chunkFrameCount: Int = 32_768) {
        self.chunkFrameCount = max(1, chunkFrameCount)
    }
    func inspect(url: URL) throws -> AIFFSampleImportInspection {
        try AIFFPreflight.layout(url: url).inspection
    }
    func normalizedImport(url: URL, channelMode: SampleImportChannelMode) throws -> NormalizedSampleImport {
        try NormalizedSampleImport(
            decoded: decode(url: url, channelMode: channelMode),
            sourceFilename: url.lastPathComponent
        )
    }
    func decode(url: URL, channelMode: SampleImportChannelMode) throws -> DecodedSampleImport {
        let layout = try AIFFPreflight.layout(url: url)
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw SampleImportError.unreadableSource }
        defer { try? handle.close() }
        var output = [Float]()
        output.reserveCapacity(layout.inspection.frameCount)
        var frameOffset = 0
        while frameOffset < layout.inspection.frameCount {
            let frames = min(chunkFrameCount, layout.inspection.frameCount - frameOffset)
            let byteCount = frames * layout.bytesPerFrame
            let sourceOffset = layout.audioOffset + UInt64(frameOffset * layout.bytesPerFrame)
            let data = try AIFFPreflight.read(handle, at: sourceOffset, count: byteCount)
            for frame in 0..<frames {
                let base = frame * layout.bytesPerFrame
                let left = Self.sample(
                    data, at: base, byteCount: layout.bytesPerSample, littleEndian: layout.littleEndian
                )
                let right = layout.inspection.sourceChannelCount == 2
                    ? Self.sample(
                        data, at: base + layout.bytesPerSample,
                        byteCount: layout.bytesPerSample, littleEndian: layout.littleEndian
                    )
                    : left
                output.append(try SampleImportChannelConverter.mono(
                    left: left, right: right,
                    sourceChannelCount: layout.inspection.sourceChannelCount, mode: channelMode
                ))
            }
            frameOffset += frames
        }
        return DecodedSampleImport(
            sourceSampleRate: layout.inspection.sourceSampleRate,
            sourceChannelCount: layout.inspection.sourceChannelCount,
            sourceBitDepthBits: layout.inspection.sourceBitDepthBits,
            monoPCM: output
        )
    }
    private static func sample(
        _ data: Data, at offset: Int, byteCount: Int, littleEndian: Bool
    ) -> Float {
        var raw: UInt32 = 0
        for index in 0..<byteCount {
            let shift = littleEndian ? index * 8 : (byteCount - index - 1) * 8
            raw |= UInt32(data[offset + index]) << UInt32(shift)
        }
        switch byteCount {
        case 1:
            return Float(Int8(bitPattern: UInt8(raw))) / 128
        case 2:
            return Float(Int16(bitPattern: UInt16(raw))) / 32_768
        case 3:
            let extended = raw & 0x80_0000 == 0 ? raw : raw | 0xFF00_0000
            return Float(Double(Int32(bitPattern: extended)) / 8_388_608)
        default:
            return Float(Double(Int32(bitPattern: raw)) / 2_147_483_648)
        }
    }
}
enum AIFFExtendedSampleRate {
    static func decode(_ data: Data) throws -> Double {
        guard data.count == 10 else { throw SampleImportError.invalidSampleRate }
        let signAndExponent = AIFFPreflight.be16(data, 0)
        let exponent = Int(signAndExponent & 0x7FFF)
        let significand = AIFFPreflight.be64(data, 2)
        guard signAndExponent & 0x8000 == 0, exponent > 0, exponent < 0x7FFF,
              significand & 0x8000_0000_0000_0000 != 0 else {
            throw SampleImportError.invalidSampleRate
        }
        // Bit 63 is the explicit integer bit, so exponent-bias-63 restores the stored value.
        let value = Double(significand) * pow(2, Double(exponent - 16_383 - 63))
        guard value.isFinite, value > 0 else { throw SampleImportError.invalidSampleRate }
        return value
    }
}
private struct AIFFLayout {
    let inspection: AIFFSampleImportInspection
    let audioOffset: UInt64
    let bytesPerSample, bytesPerFrame: Int
    let littleEndian: Bool
}
private enum AIFFPreflight {
    private struct CommonChunk {
        let channels: Int
        let frameCount: UInt64
        let bits: Int
        let sampleRate: Double
        let compression: String
    }
    private struct SoundChunk {
        let audioOffset, byteCount: UInt64
    }
    static func layout(url: URL) throws -> AIFFLayout {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw SampleImportError.unreadableSource }
        defer { try? handle.close() }
        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize >= 12 else { throw SampleImportError.truncatedAIFF }
            let header = try read(handle, at: 0, count: 12)
            guard text(header, 0) == "FORM" else { throw SampleImportError.malformedAIFF }
            let isAIFC: Bool
            switch text(header, 8) {
            case "AIFF": isAIFC = false
            case "AIFC": isAIFC = true
            default: throw SampleImportError.malformedAIFF
            }
            let (declaredEnd, formOverflow) = UInt64(be32(header, 4)).addingReportingOverflow(8)
            guard !formOverflow, declaredEnd >= 12 else { throw SampleImportError.integerOverflow }
            guard declaredEnd <= fileSize else { throw SampleImportError.truncatedAIFF }

            var common: CommonChunk?
            var sound: SoundChunk?
            var offset: UInt64 = 12
            while offset < declaredEnd {
                guard declaredEnd - offset >= 8 else { throw SampleImportError.truncatedAIFF }
                let chunkHeader = try read(handle, at: offset, count: 8)
                let size = UInt64(be32(chunkHeader, 4))
                let (start, startOverflow) = offset.addingReportingOverflow(8)
                let (end, endOverflow) = start.addingReportingOverflow(size)
                let (paddedEnd, padOverflow) = end.addingReportingOverflow(size & 1)
                guard !startOverflow, !endOverflow, !padOverflow else {
                    throw SampleImportError.integerOverflow
                }
                guard paddedEnd <= declaredEnd else { throw SampleImportError.truncatedAIFF }
                switch text(chunkHeader, 0) {
                case "COMM":
                    guard common == nil else { throw SampleImportError.malformedAIFF }
                    common = try parseCommon(handle, at: start, size: size, isAIFC: isAIFC)
                case "SSND":
                    guard sound == nil else { throw SampleImportError.malformedAIFF }
                    sound = try parseSound(handle, at: start, size: size)
                default:
                    break
                }
                offset = paddedEnd
            }
            guard let common, let sound else { throw SampleImportError.malformedAIFF }
            guard common.channels > 0, common.channels <= 2 else {
                throw SampleImportError.unsupportedChannelCount(common.channels)
            }
            guard common.frameCount > 0 else { throw SampleImportError.emptySource }
            try SampleImportResourcePolicy.validate(frameCount: common.frameCount)
            guard [8, 16, 24, 32].contains(common.bits) else {
                throw SampleImportError.unsupportedPCMBitDepth(common.bits)
            }
            let littleEndian: Bool
            switch common.compression {
            case "NONE", "twos": littleEndian = false
            case "sowt": littleEndian = true
            default: throw SampleImportError.unsupportedAIFFCompression(common.compression)
            }
            let bytesPerSample = common.bits / 8
            let bytesPerFrame = try multiplied(common.channels, bytesPerSample)
            let expectedBytes = try multiplied(common.frameCount, UInt64(bytesPerFrame))
            guard expectedBytes <= sound.byteCount else { throw SampleImportError.truncatedAIFF }
            guard common.frameCount <= UInt64(Int.max) else { throw SampleImportError.integerOverflow }
            return AIFFLayout(
                inspection: AIFFSampleImportInspection(
                    sourceSampleRate: common.sampleRate,
                    sourceChannelCount: common.channels, sourceBitDepthBits: common.bits,
                    frameCount: Int(common.frameCount)
                ),
                audioOffset: sound.audioOffset, bytesPerSample: bytesPerSample,
                bytesPerFrame: bytesPerFrame, littleEndian: littleEndian
            )
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.unreadableSource
        }
    }
    private static func parseCommon(
        _ handle: FileHandle, at offset: UInt64, size: UInt64, isAIFC: Bool
    ) throws -> CommonChunk {
        let minimum = isAIFC ? 23 : 18
        guard size >= UInt64(minimum) else { throw SampleImportError.malformedAIFF }
        let data = try read(handle, at: offset, count: minimum)
        let compression: String
        if isAIFC {
            compression = text(data, 18)
            let nameLength = Int(data[22])
            let required = 23 + nameLength + ((1 + nameLength) & 1)
            guard UInt64(required) <= size else { throw SampleImportError.malformedAIFF }
        } else {
            compression = "NONE"
        }
        return CommonChunk(
            channels: Int(be16(data, 0)), frameCount: UInt64(be32(data, 2)),
            bits: Int(be16(data, 6)),
            sampleRate: try AIFFExtendedSampleRate.decode(data.subdata(in: 8..<18)),
            compression: compression
        )
    }
    private static func parseSound(_ handle: FileHandle, at offset: UInt64, size: UInt64) throws -> SoundChunk {
        guard size >= 8 else { throw SampleImportError.malformedAIFF }
        let header = try read(handle, at: offset, count: 8)
        let dataOffset = UInt64(be32(header, 0))
        _ = be32(header, 4) // SSND blockSize is an I/O hint and does not alter packed PCM layout.
        let available = size - 8
        guard dataOffset <= available else { throw SampleImportError.truncatedAIFF }
        let (audioOffset, overflow) = offset.addingReportingOverflow(8 + dataOffset)
        guard !overflow else { throw SampleImportError.integerOverflow }
        return SoundChunk(audioOffset: audioOffset, byteCount: available - dataOffset)
    }
    static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw SampleImportError.truncatedAIFF
            }
            return data
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.unreadableSource
        }
    }
    static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    static func be64(_ data: Data, _ offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<8 { result = result << 8 | UInt64(data[offset + index]) }
        return result
    }

    private static func text(_ data: Data, _ offset: Int) -> String {
        String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
    }

    private static func multiplied<T: FixedWidthInteger>(_ lhs: T, _ rhs: T) throws -> T {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw SampleImportError.integerOverflow }
        return value
    }
}
