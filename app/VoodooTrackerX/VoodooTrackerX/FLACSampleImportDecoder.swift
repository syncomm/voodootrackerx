import AudioToolbox
import AVFoundation
import Foundation
struct FLACSampleImportInspection: Equatable, Sendable {
    let sourceSampleRate: Double
    let sourceChannelCount, sourceBitDepthBits, frameCount: Int
}
/// Decodes validated native FLAC into the shared Float32 import intermediate.
struct FLACSampleImportDecoder: Sendable {
    let chunkFrameCount: AVAudioFrameCount
    init(chunkFrameCount: Int = 32_768) {
        self.chunkFrameCount = AVAudioFrameCount(min(Int(UInt32.max), max(1, chunkFrameCount)))
    }
    func inspect(url: URL) throws -> FLACSampleImportInspection {
        try FLACPreflight.inspect(url: url)
    }
    func normalizedImport(url: URL, channelMode: SampleImportChannelMode) throws -> NormalizedSampleImport {
        try NormalizedSampleImport(
            decoded: decode(url: url, channelMode: channelMode),
            sourceFilename: url.lastPathComponent
        )
    }
    func decode(url: URL, channelMode: SampleImportChannelMode) throws -> DecodedSampleImport {
        let inspection = try inspect(url: url)
        var optionalFile: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &optionalFile) == noErr, let file = optionalFile else {
            throw SampleImportError.audioDecodeFailed
        }
        defer { ExtAudioFileDispose(file) }
        do {
            var fileFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(ExtAudioFileGetProperty(
                file, kExtAudioFileProperty_FileDataFormat, &formatSize, &fileFormat
            ))
            var fileLength: Int64 = 0
            var lengthSize = UInt32(MemoryLayout<Int64>.size)
            try Self.check(ExtAudioFileGetProperty(
                file, kExtAudioFileProperty_FileLengthFrames, &lengthSize, &fileLength
            ))
            guard fileFormat.mFormatID == kAudioFormatFLAC,
                  fileFormat.mSampleRate == inspection.sourceSampleRate,
                  Int(fileFormat.mChannelsPerFrame) == inspection.sourceChannelCount,
                  Self.sourceBitDepth(fileFormat.mFormatFlags) == inspection.sourceBitDepthBits,
                  fileLength == Int64(inspection.frameCount) else {
                throw SampleImportError.decoderMetadataMismatch
            }
            guard let processingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inspection.sourceSampleRate,
                channels: AVAudioChannelCount(inspection.sourceChannelCount),
                interleaved: false
            ) else {
                throw SampleImportError.audioDecodeFailed
            }
            var clientFormat = processingFormat.streamDescription.pointee
            try Self.check(ExtAudioFileSetProperty(
                file, kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat
            ))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat, frameCapacity: chunkFrameCount
            ) else {
                throw SampleImportError.audioDecodeFailed
            }
            var output = [Float]()
            output.reserveCapacity(inspection.frameCount)
            while output.count < inspection.frameCount {
                let remaining = inspection.frameCount - output.count
                let request = min(chunkFrameCount, AVAudioFrameCount(remaining))
                buffer.frameLength = request
                var decodedFrames = UInt32(request)
                try Self.check(ExtAudioFileRead(file, &decodedFrames, buffer.mutableAudioBufferList))
                guard decodedFrames > 0, decodedFrames <= request,
                      let channels = buffer.floatChannelData else {
                    throw SampleImportError.decoderMetadataMismatch
                }
                for frame in 0..<Int(decodedFrames) {
                    let left = channels[0][frame]
                    let right = inspection.sourceChannelCount == 2 ? channels[1][frame] : left
                    output.append(try SampleImportChannelConverter.mono(
                        left: left, right: right,
                        sourceChannelCount: inspection.sourceChannelCount, mode: channelMode
                    ))
                }
            }
            buffer.frameLength = 1
            var trailingFrames: UInt32 = 1
            try Self.check(ExtAudioFileRead(file, &trailingFrames, buffer.mutableAudioBufferList))
            guard trailingFrames == 0, output.count == inspection.frameCount else {
                throw SampleImportError.decoderMetadataMismatch
            }
            return DecodedSampleImport(
                sourceSampleRate: inspection.sourceSampleRate,
                sourceChannelCount: inspection.sourceChannelCount,
                sourceBitDepthBits: inspection.sourceBitDepthBits,
                monoPCM: output
            )
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.audioDecodeFailed
        }
    }
    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw SampleImportError.audioDecodeFailed }
    }
    private static func sourceBitDepth(_ flags: AudioFormatFlags) -> Int? {
        switch flags {
        case kAppleLosslessFormatFlag_16BitSourceData: 16
        case kAppleLosslessFormatFlag_24BitSourceData: 24
        default: nil
        }
    }
}
private enum FLACPreflight {
    static func inspect(url: URL) throws -> FLACSampleImportInspection {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch {
            throw SampleImportError.unreadableSource
        }
        defer { try? handle.close() }
        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize >= 4 else { throw SampleImportError.truncatedFLAC }
            guard try read(handle, at: 0, count: 4) == Data("fLaC".utf8) else {
                throw SampleImportError.malformedFLAC
            }
            var offset: UInt64 = 4
            var inspection: FLACSampleImportInspection?
            var isLast = false
            var blockIndex = 0
            while !isLast {
                guard fileSize - offset >= 4 else { throw SampleImportError.truncatedFLAC }
                let header = try read(handle, at: offset, count: 4)
                isLast = header[0] & 0x80 != 0
                let type = header[0] & 0x7F
                let length = UInt64(header[1]) << 16 | UInt64(header[2]) << 8 | UInt64(header[3])
                let payloadStart = try adding(offset, 4)
                let payloadEnd = try adding(payloadStart, length)
                guard payloadEnd <= fileSize else { throw SampleImportError.truncatedFLAC }
                guard type <= 6 else { throw SampleImportError.malformedFLAC }

                if blockIndex == 0 {
                    guard type == 0, length == 34 else { throw SampleImportError.malformedFLAC }
                    inspection = try parseStreamInfo(try read(handle, at: payloadStart, count: 34))
                } else if type == 0 {
                    throw SampleImportError.malformedFLAC
                }
                offset = payloadEnd
                blockIndex += 1
            }
            guard let inspection else { throw SampleImportError.malformedFLAC }
            guard offset < fileSize else { throw SampleImportError.truncatedFLAC }
            return inspection
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.unreadableSource
        }
    }
    private static func parseStreamInfo(_ data: Data) throws -> FLACSampleImportInspection {
        let minimumBlockSize = Int(be16(data, 0))
        let maximumBlockSize = Int(be16(data, 2))
        let minimumFrameSize = be24(data, 4)
        let maximumFrameSize = be24(data, 7)
        guard minimumBlockSize > 0, maximumBlockSize >= minimumBlockSize,
              minimumFrameSize == 0 || maximumFrameSize == 0 ||
                maximumFrameSize >= minimumFrameSize else {
            throw SampleImportError.malformedFLAC
        }
        let packed = be64(data, 10)
        let sampleRate = Int(packed >> 44)
        let channelCount = Int((packed >> 41) & 0x07) + 1
        let bitDepth = Int((packed >> 36) & 0x1F) + 1
        let frameCount = packed & 0x0F_FFFF_FFFF
        guard sampleRate > 0 else { throw SampleImportError.invalidSampleRate }
        _ = try SampleImportTuning(sourceSampleRate: Double(sampleRate))
        guard (1...2).contains(channelCount) else {
            throw SampleImportError.unsupportedChannelCount(channelCount)
        }
        guard bitDepth == 16 || bitDepth == 24 else {
            throw SampleImportError.unsupportedFLACBitDepth(bitDepth)
        }
        guard frameCount > 0 else { throw SampleImportError.emptySource }
        try SampleImportResourcePolicy.validate(frameCount: frameCount)
        guard frameCount <= UInt64(Int.max) else { throw SampleImportError.integerOverflow }
        return FLACSampleImportInspection(
            sourceSampleRate: Double(sampleRate), sourceChannelCount: channelCount,
            sourceBitDepthBits: bitDepth, frameCount: Int(frameCount)
        )
    }
    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw SampleImportError.truncatedFLAC
            }
            return data
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.unreadableSource
        }
    }
    private static func adding(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw SampleImportError.integerOverflow }
        return value
    }
    private static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
    private static func be24(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
    }
    private static func be64(_ data: Data, _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 { value = value << 8 | UInt64(data[offset + index]) }
        return value
    }
}
