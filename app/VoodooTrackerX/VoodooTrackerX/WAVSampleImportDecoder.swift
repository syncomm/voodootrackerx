import AVFoundation
import Foundation

enum SampleImportChannelMode: Equatable, Sendable {
    case mixToMono, left, right
}
enum SampleImportError: Error, Equatable, Sendable {
    case unsupportedContainer, fileExtensionMismatch
    case unreadableSource, malformedWAV, truncatedWAV
    case malformedAIFF, truncatedAIFF, malformedFLAC, truncatedFLAC
    case unsupportedEncoding(formatCode: UInt16, bitsPerSample: Int)
    case unsupportedPCMBitDepth(Int), unsupportedAIFFCompression(String), unsupportedFLACBitDepth(Int)
    case unsupportedChannelCount(Int)
    case emptySource, invalidSampleRate, resourceLimitExceeded, integerOverflow
    case audioDecodeFailed, decoderMetadataMismatch, nonFinitePCM, tuningOutOfRange

    var userFacingMessage: String {
        switch self {
        case .unsupportedContainer: "This is not a supported WAV, AIFF, AIFC, or native FLAC file."
        case .fileExtensionMismatch: "The file extension does not match the audio container."
        case .unreadableSource: "The audio file could not be read."
        case .malformedWAV: "This file is not a valid WAV file."
        case .truncatedWAV: "The WAV file is incomplete or truncated."
        case .malformedAIFF: "This file is not a valid AIFF/AIFC file."
        case .truncatedAIFF: "The AIFF/AIFC file is incomplete or truncated."
        case .malformedFLAC: "This file is not a valid native FLAC file."
        case .truncatedFLAC: "The FLAC file is incomplete or truncated."
        case .unsupportedEncoding: "This WAV encoding is not supported."
        case .unsupportedPCMBitDepth: "This AIFF/AIFC sample width is not supported."
        case .unsupportedAIFFCompression: "This AIFC compression is not supported."
        case .unsupportedFLACBitDepth: "This FLAC sample width is not supported."
        case let .unsupportedChannelCount(count):
            count > 2 ? "Audio files with more than two channels are not supported." : "This audio channel layout is not supported."
        case .emptySource: "The audio file contains no sample frames."
        case .invalidSampleRate: "The audio file has an invalid sample rate."
        case .resourceLimitExceeded, .integerOverflow: "The audio file is too large to import safely."
        case .audioDecodeFailed, .decoderMetadataMismatch: "The audio could not be decoded completely."
        case .nonFinitePCM: "The audio file contains invalid sample values."
        case .tuningOutOfRange: "The audio sample rate is outside the supported tuning range."
        }
    }
}
enum SampleImportResourcePolicy {
    /// 64 MiB of canonical mono Float32 PCM. Stereo is converted while reading.
    static let maximumFrameCount = 16_777_216

    static func validate(frameCount: UInt64) throws {
        guard frameCount <= UInt64(maximumFrameCount) else {
            throw SampleImportError.resourceLimitExceeded
        }
        _ = try canonicalByteCount(frameCount: frameCount)
    }

    static func canonicalByteCount(frameCount: UInt64) throws -> Int {
        let (bytes, overflow) = frameCount.multipliedReportingOverflow(by: UInt64(MemoryLayout<Float>.stride))
        guard !overflow, bytes <= UInt64(Int.max) else { throw SampleImportError.integerOverflow }
        return Int(bytes)
    }
}
struct WAVSampleImportInspection: Equatable, Sendable {
    let sourceSampleRate: Double
    let sourceChannelCount, sourceBitDepthBits, frameCount: Int
}
struct DecodedSampleImport: Equatable, Sendable {
    let sourceSampleRate: Double
    let sourceChannelCount, sourceBitDepthBits: Int
    let monoPCM: [Float]
    var frameCount: Int { monoPCM.count }
}
enum SampleImportChannelConverter {
    static func mono(
        left: Float, right: Float, sourceChannelCount: Int, mode: SampleImportChannelMode
    ) throws -> Float {
        guard left.isFinite, right.isFinite else { throw SampleImportError.nonFinitePCM }
        let mono: Float
        switch mode {
        case .mixToMono: mono = sourceChannelCount == 2 ? 0.5 * left + 0.5 * right : left
        case .left: mono = left
        case .right: mono = right
        }
        guard mono.isFinite else { throw SampleImportError.nonFinitePCM }
        return min(1, max(-1, mono))
    }
}
struct SampleImportTuning: Equatable {
    let relativeNote, finetune: Int
    let playbackSampleRate, pitchErrorCents: Double
    init(sourceSampleRate: Double) throws {
        guard sourceSampleRate.isFinite, sourceSampleRate > 0 else {
            throw SampleImportError.invalidSampleRate
        }
        // Existing linear playback uses 64 period units per semitone and finetune / 2,
        // therefore one signed finetune unit is exactly 1/128 semitone.
        let stepsPerSemitone = Int(PlaybackSongSyntheticAdapter.xmLinearPeriodUnitsPerSemitone * 2)
        let targetSteps = 12 * log2(sourceSampleRate / PlaybackSample.xmNeutralSampleRate) * Double(stepsPerSemitone)
        let c4NoteValue = 49
        let usableRelativeNotes = (1 - c4NoteValue)...(PlaybackSongSyntheticAdapter.xmLinearMaximumEffectiveNoteValue - c4NoteValue)
        let minimum = usableRelativeNotes.lowerBound * stepsPerSemitone + Int(Int8.min)
        let maximum = usableRelativeNotes.upperBound * stepsPerSemitone + Int(Int8.max)
        guard targetSteps.isFinite, targetSteps >= Double(minimum), targetSteps <= Double(maximum) else {
            throw SampleImportError.tuningOutOfRange
        }
        let roundedSteps = Int(targetSteps.rounded(.toNearestOrAwayFromZero))
        let candidates = usableRelativeNotes.compactMap { note -> (Int, Int)? in
            let fine = roundedSteps - (note * stepsPerSemitone)
            return PlaybackSample.xmFinetuneRange.contains(fine) ? (note, fine) : nil
        }
        guard let selected = candidates.min(by: {
            abs($0.1) == abs($1.1) ? (abs($0.0), $0.0) < (abs($1.0), $1.0) : abs($0.1) < abs($1.1)
        }) else { throw SampleImportError.tuningOutOfRange }

        relativeNote = selected.0
        finetune = selected.1
        guard let playback = PlaybackSongSyntheticAdapter.linearPitchTarget(
            note: UInt8(c4NoteValue), relativeNote: relativeNote, finetune: finetune,
            baseSampleRate: PlaybackSample.xmNeutralSampleRate,
            outputSampleRate: PlaybackSample.xmNeutralSampleRate
        ) else { throw SampleImportError.tuningOutOfRange }
        playbackSampleRate = playback.linearFrequency
        pitchErrorCents = 1_200 * log2(playbackSampleRate / sourceSampleRate)
    }
}
enum SampleImportNaming {
    static func sampleName(filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        return EditableXMTextEncoding.sanitizedSampleName(stem) ?? "(unnamed sample)"
    }
}
struct NormalizedSampleImport: Equatable, Sendable {
    let name: String
    let pcm: [Float]
    let frameCount: Int
    let bitDepthBits = 16, channelCount = 1
    let volume: UInt8 = PlaybackSample.xmDefaultVolume
    let panning: UInt8 = PlaybackSample.xmCenterPanning
    let relativeNote, finetune: Int
    let loopType = 0
    let sourceSampleRate: Double
    let sourceChannelCount: Int

    /// The initializer canonicalizes every PCM value; this verifies the remaining document-bound invariants cheaply.
    var isValidDocumentSample: Bool {
        frameCount > 0 && frameCount == pcm.count &&
            frameCount <= SampleImportResourcePolicy.maximumFrameCount &&
            bitDepthBits == 16 && channelCount == 1 && volume == PlaybackSample.xmDefaultVolume &&
            panning == PlaybackSample.xmCenterPanning && loopType == 0 &&
            PlaybackSample.xmRelativeNoteRange.contains(relativeNote) &&
            PlaybackSample.xmFinetuneRange.contains(finetune) &&
            sourceSampleRate.isFinite && sourceSampleRate > 0 && (1...2).contains(sourceChannelCount)
    }

    init(decoded: DecodedSampleImport, sourceFilename: String) throws {
        guard !decoded.monoPCM.isEmpty else { throw SampleImportError.emptySource }
        guard decoded.monoPCM.count <= SampleImportResourcePolicy.maximumFrameCount else {
            throw SampleImportError.resourceLimitExceeded
        }
        guard (1...2).contains(decoded.sourceChannelCount) else {
            throw SampleImportError.unsupportedChannelCount(decoded.sourceChannelCount)
        }
        let tuning = try SampleImportTuning(sourceSampleRate: decoded.sourceSampleRate)
        do {
            pcm = try decoded.monoPCM.map { XMPCMQuantizer.canonicalFloat32(try XMPCMQuantizer.signed16($0)) }
        } catch {
            throw SampleImportError.nonFinitePCM
        }
        name = SampleImportNaming.sampleName(filename: sourceFilename)
        frameCount = pcm.count
        relativeNote = tuning.relativeNote
        finetune = tuning.finetune
        sourceSampleRate = decoded.sourceSampleRate
        sourceChannelCount = decoded.sourceChannelCount
    }

    func playbackSample(instrumentIndex: Int, sampleIndex: Int) -> PlaybackSample {
        PlaybackSample(
            instrumentIndex: instrumentIndex, sampleIndex: sampleIndex, name: name, pcm: pcm,
            volume: Float(volume) / Float(PlaybackSample.xmMaximumVolume), panning: panning,
            relativeNote: relativeNote, finetune: finetune, baseSampleRate: PlaybackSample.xmNeutralSampleRate,
            loopStart: 0, loopLength: 0, loopType: loopType,
            sourceBitDepthBits: bitDepthBits, sourceIsSignedPCM: true, sourceIsDeltaEncoded: true
        )
    }
}

enum SampleImportFormat: Equatable, Sendable {
    case wav, aiff, aifc, flac
}

struct SampleImportInspection: Equatable, Sendable {
    let format: SampleImportFormat
    let sourceSampleRate: Double
    let sourceChannelCount, sourceBitDepthBits, frameCount: Int
}

/// Dispatches validated WAV/AIFF/AIFC/native-FLAC containers into their existing decoders.
struct SampleImportDecoder: Sendable {
    let wavDecoder: WAVSampleImportDecoder
    let aiffDecoder: AIFFSampleImportDecoder
    let flacDecoder: FLACSampleImportDecoder

    init(
        wavDecoder: WAVSampleImportDecoder = WAVSampleImportDecoder(),
        aiffDecoder: AIFFSampleImportDecoder = AIFFSampleImportDecoder(),
        flacDecoder: FLACSampleImportDecoder = FLACSampleImportDecoder()
    ) {
        self.wavDecoder = wavDecoder
        self.aiffDecoder = aiffDecoder
        self.flacDecoder = flacDecoder
    }

    func inspect(url: URL) throws -> SampleImportInspection {
        switch try SampleImportContainerIdentity.detect(url: url) {
        case .wav:
            let value = try wavDecoder.inspect(url: url)
            return SampleImportInspection(
                format: .wav, sourceSampleRate: value.sourceSampleRate,
                sourceChannelCount: value.sourceChannelCount,
                sourceBitDepthBits: value.sourceBitDepthBits, frameCount: value.frameCount
            )
        case .flac:
            let value = try flacDecoder.inspect(url: url)
            return SampleImportInspection(
                format: .flac, sourceSampleRate: value.sourceSampleRate,
                sourceChannelCount: value.sourceChannelCount,
                sourceBitDepthBits: value.sourceBitDepthBits, frameCount: value.frameCount
            )
        case let format:
            let value = try aiffDecoder.inspect(url: url)
            return SampleImportInspection(
                format: format, sourceSampleRate: value.sourceSampleRate,
                sourceChannelCount: value.sourceChannelCount,
                sourceBitDepthBits: value.sourceBitDepthBits, frameCount: value.frameCount
            )
        }
    }

    func normalizedImport(url: URL, channelMode: SampleImportChannelMode) throws -> NormalizedSampleImport {
        switch try SampleImportContainerIdentity.detect(url: url) {
        case .wav:
            try wavDecoder.normalizedImport(url: url, channelMode: channelMode)
        case .aiff, .aifc:
            try aiffDecoder.normalizedImport(url: url, channelMode: channelMode)
        case .flac:
            try flacDecoder.normalizedImport(url: url, channelMode: channelMode)
        }
    }
}

private enum SampleImportContainerIdentity {
    static func detect(url: URL) throws -> SampleImportFormat {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw SampleImportError.unreadableSource }
        defer { try? handle.close() }

        let header: Data
        do { header = try handle.read(upToCount: 12) ?? Data() } catch {
            throw SampleImportError.unreadableSource
        }
        let expected = expectedFormat(forExtension: url.pathExtension)
        if header.count >= 4,
           String(decoding: header[0..<4], as: UTF8.self) == "fLaC" {
            if let expected, expected != .flac {
                throw SampleImportError.fileExtensionMismatch
            }
            return .flac
        }
        guard header.count >= 12 else {
            // A supported extension may route an incomplete file to the matching decoder
            // so its format-specific truncated error remains actionable.
            guard let expected else { throw SampleImportError.unsupportedContainer }
            return expected
        }

        let detected: SampleImportFormat
        let container = String(decoding: header[0..<4], as: UTF8.self)
        let form = String(decoding: header[8..<12], as: UTF8.self)
        switch (container, form) {
        case ("RIFF", "WAVE"): detected = .wav
        case ("FORM", "AIFF"): detected = .aiff
        case ("FORM", "AIFC"): detected = .aifc
        default: throw SampleImportError.unsupportedContainer
        }
        if let expected, expected != detected {
            throw SampleImportError.fileExtensionMismatch
        }
        return detected
    }

    private static func expectedFormat(forExtension pathExtension: String) -> SampleImportFormat? {
        switch pathExtension.lowercased() {
        case "wav", "wave": .wav
        case "aif", "aiff": .aiff
        case "aifc": .aifc
        case "flac": .flac
        default: nil
        }
    }
}

struct WAVSampleImportDecoder: Sendable {
    let chunkFrameCount: AVAudioFrameCount
    init(chunkFrameCount: Int = 32_768) {
        self.chunkFrameCount = AVAudioFrameCount(min(Int(UInt32.max), max(1, chunkFrameCount)))
    }
    func inspect(url: URL) throws -> WAVSampleImportInspection {
        try WAVPreflight.inspect(url: url)
    }
    func normalizedImport(url: URL, channelMode: SampleImportChannelMode) throws -> NormalizedSampleImport {
        try NormalizedSampleImport(
            decoded: decode(url: url, channelMode: channelMode),
            sourceFilename: url.lastPathComponent
        )
    }
    func decode(url: URL, channelMode: SampleImportChannelMode) throws -> DecodedSampleImport {
        let inspection = try inspect(url: url)
        do {
            return try autoreleasepool {
                let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
                let format = file.processingFormat
                guard Int(file.length) == inspection.frameCount,
                      Int(format.channelCount) == inspection.sourceChannelCount,
                      format.sampleRate == inspection.sourceSampleRate else {
                    throw SampleImportError.decoderMetadataMismatch
                }
                var output = [Float]()
                output.reserveCapacity(inspection.frameCount)
                while output.count < inspection.frameCount {
                    let request = min(chunkFrameCount, AVAudioFrameCount(inspection.frameCount - output.count))
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: request) else {
                        throw SampleImportError.audioDecodeFailed
                    }
                    try file.read(into: buffer, frameCount: request)
                    let count = Int(buffer.frameLength)
                    guard count > 0, let channels = buffer.floatChannelData else {
                        throw SampleImportError.decoderMetadataMismatch
                    }
                    for frame in 0..<count {
                        let left = channels[0][frame]
                        let right = inspection.sourceChannelCount == 2 ? channels[1][frame] : left
                        output.append(try SampleImportChannelConverter.mono(
                            left: left, right: right,
                            sourceChannelCount: inspection.sourceChannelCount, mode: channelMode
                        ))
                    }
                }
                guard output.count == inspection.frameCount else { throw SampleImportError.decoderMetadataMismatch }
                return DecodedSampleImport(
                    sourceSampleRate: inspection.sourceSampleRate,
                    sourceChannelCount: inspection.sourceChannelCount,
                    sourceBitDepthBits: inspection.sourceBitDepthBits,
                    monoPCM: output
                )
            }
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.audioDecodeFailed
        }
    }
}
private enum WAVPreflight {
    static func inspect(url: URL) throws -> WAVSampleImportInspection {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw SampleImportError.unreadableSource }
        defer { try? handle.close() }
        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize >= 12 else { throw SampleImportError.truncatedWAV }
            let header = try read(handle, at: 0, count: 12)
            guard String(decoding: header[0..<4], as: UTF8.self) == "RIFF",
                  String(decoding: header[8..<12], as: UTF8.self) == "WAVE" else {
                throw SampleImportError.malformedWAV
            }
            let declaredEnd = UInt64(le32(header, 4)) + 8
            guard declaredEnd >= 12, declaredEnd <= fileSize else { throw SampleImportError.truncatedWAV }
            var offset: UInt64 = 12
            var format: Data?
            var dataSize: UInt64?
            while offset + 8 <= declaredEnd {
                let chunk = try read(handle, at: offset, count: 8)
                let id = String(decoding: chunk[0..<4], as: UTF8.self)
                let size = UInt64(le32(chunk, 4))
                let start = offset + 8
                let end = start + size
                let paddedEnd = end + (size & 1)
                guard end >= start, paddedEnd >= end, paddedEnd <= declaredEnd else {
                    throw SampleImportError.truncatedWAV
                }
                if id == "fmt ", format == nil {
                    guard size >= 16 else { throw SampleImportError.malformedWAV }
                    format = try read(handle, at: start, count: Int(min(size, 40)))
                } else if id == "data", dataSize == nil {
                    dataSize = size
                }
                offset = paddedEnd
            }
            guard let format, let dataSize else { throw SampleImportError.malformedWAV }
            return try validated(format: format, dataSize: dataSize)
        } catch let error as SampleImportError {
            throw error
        } catch {
            throw SampleImportError.unreadableSource
        }
    }

    private static func validated(format: Data, dataSize: UInt64) throws -> WAVSampleImportInspection {
        var formatCode = le16(format, 0)
        let channels = Int(le16(format, 2))
        let sampleRate = le32(format, 4)
        let byteRate = le32(format, 8)
        let blockAlign = Int(le16(format, 12))
        let bits = Int(le16(format, 14))
        guard (1...2).contains(channels) else { throw SampleImportError.unsupportedChannelCount(channels) }
        guard sampleRate > 0 else { throw SampleImportError.invalidSampleRate }
        if formatCode == 0xFFFE {
            guard format.count >= 40, le16(format, 16) >= 22,
                  Array(format[28..<40]) == [0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71] else {
                throw SampleImportError.malformedWAV
            }
            formatCode = UInt16(truncatingIfNeeded: le32(format, 24))
        }
        let supported = (formatCode == 1 && [8, 16, 24, 32].contains(bits)) || (formatCode == 3 && bits == 32)
        guard supported else { throw SampleImportError.unsupportedEncoding(formatCode: formatCode, bitsPerSample: bits) }
        let expectedAlign = channels * (bits / 8)
        guard bits.isMultiple(of: 8), blockAlign == expectedAlign, blockAlign > 0,
              UInt64(byteRate) == UInt64(sampleRate) * UInt64(blockAlign),
              dataSize.isMultiple(of: UInt64(blockAlign)) else {
            throw SampleImportError.malformedWAV
        }
        let frameCount = dataSize / UInt64(blockAlign)
        guard frameCount > 0 else { throw SampleImportError.emptySource }
        try SampleImportResourcePolicy.validate(frameCount: frameCount)
        guard frameCount <= UInt64(Int.max) else { throw SampleImportError.integerOverflow }
        return WAVSampleImportInspection(
            sourceSampleRate: Double(sampleRate), sourceChannelCount: channels,
            sourceBitDepthBits: bits, frameCount: Int(frameCount)
        )
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw SampleImportError.truncatedWAV
        }
        return data
    }

    private static func le16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func le32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
