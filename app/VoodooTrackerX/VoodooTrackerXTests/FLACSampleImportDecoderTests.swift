import AudioToolbox
import AVFoundation
import Foundation
import XCTest
final class FLACSampleImportDecoderTests: XCTestCase {
    func testNative16And24BitMonoStereoDecodeInBoundedChunks() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameCount = 5_000

        let cases = [(16, 1, 8_363), (16, 2, 44_100), (24, 1, 48_000), (24, 2, 96_000)]
        for (bitDepth, channelCount, sampleRate) in cases {
            let channels = sourceChannels(frameCount: frameCount, channelCount: channelCount)
            let url = directory.appendingPathComponent("\(bitDepth)-bit-\(channelCount)-channel.flac")
            try writeFLAC(channels, bitDepth: bitDepth, sampleRate: Double(sampleRate), to: url)

            let decoder = FLACSampleImportDecoder(chunkFrameCount: 257)
            XCTAssertEqual(
                try decoder.inspect(url: url),
                FLACSampleImportInspection(
                    sourceSampleRate: Double(sampleRate), sourceChannelCount: channelCount,
                    sourceBitDepthBits: bitDepth, frameCount: frameCount
                )
            )
            for mode in [SampleImportChannelMode.mixToMono, .left, .right] {
                let decoded = try decoder.decode(url: url, channelMode: mode)
                XCTAssertEqual(decoded.sourceBitDepthBits, bitDepth)
                assertPCM(
                    decoded.monoPCM, expectedMono(channels, mode: mode),
                    "\(bitDepth)-bit \(channelCount)-channel \(mode)"
                )
            }
            let candidate = try decoder.normalizedImport(url: url, channelMode: .left)
            let tuning = try SampleImportTuning(sourceSampleRate: Double(sampleRate))
            XCTAssertEqual(candidate.relativeNote, tuning.relativeNote)
            XCTAssertEqual(candidate.finetune, tuning.finetune)
        }
    }
    func testPreflightRejectsUnsupportedDepthsAndInvalidStreamPolicy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.flac")
        try writeFLAC(sourceChannels(frameCount: 5_000, channelCount: 1), bitDepth: 16, to: source)
        let valid = try Data(contentsOf: source)
        let cases: [(String, Data, SampleImportError)] = [
            ("8-bit.flac", settingBitDepth(8, in: valid), .unsupportedFLACBitDepth(8)),
            ("20-bit.flac", settingBitDepth(20, in: valid), .unsupportedFLACBitDepth(20)),
            ("three-channel.flac", settingChannels(3, in: valid), .unsupportedChannelCount(3)),
            ("zero-rate.flac", settingSampleRate(0, in: valid), .invalidSampleRate),
            ("out-of-range-rate.flac", settingSampleRate(1_000_000, in: valid), .tuningOutOfRange),
            ("zero-frames.flac", settingFrameCount(0, in: valid), .emptySource),
            (
                "oversize.flac",
                settingFrameCount(UInt64(SampleImportResourcePolicy.maximumFrameCount + 1), in: valid),
                .resourceLimitExceeded
            ),
        ]
        for (name, data, expected) in cases {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            XCTAssertThrowsError(try FLACSampleImportDecoder().inspect(url: url), name) {
                XCTAssertEqual($0 as? SampleImportError, expected, name)
            }
        }
    }
    func testPreflightRejectsOggMalformedTruncatedAndMismatchedContainers() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let decoder = SampleImportDecoder()
        let cases: [(String, Data, SampleImportError, Bool)] = [
            ("short.flac", Data("fLaC".utf8), .truncatedFLAC, false),
            (
                "wrong.flac",
                Data("nope".utf8) + Data(repeating: 0, count: 8),
                .unsupportedContainer, true
            ),
            (
                "truncated-metadata.flac",
                Data("fLaC".utf8) + Data([0x80, 0, 0, 34]) + Data(repeating: 0, count: 8),
                .truncatedFLAC, false
            ),
            (
                "missing-streaminfo.flac",
                Data("fLaC".utf8) + Data([0x81, 0, 0, 0, 0]),
                .malformedFLAC, false
            ),
            (
                "bad-streaminfo-length.flac",
                Data("fLaC".utf8) + Data([0x80, 0, 0, 33]) + Data(repeating: 0, count: 34),
                .malformedFLAC, false
            ),
            ("ogg.flac", Data("OggS".utf8) + Data(repeating: 0, count: 8), .unsupportedOggFLAC, true),
        ]
        for (name, data, expected, useFacade) in cases {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            let operation: () throws -> Void = useFacade
                ? { _ = try decoder.inspect(url: url) }
                : { _ = try FLACSampleImportDecoder().inspect(url: url) }
            XCTAssertThrowsError(try operation(), name) {
                XCTAssertEqual($0 as? SampleImportError, expected, name)
            }
        }

        let nativeURL = directory.appendingPathComponent("native-as-wav.wav")
        try writeFLAC(sourceChannels(frameCount: 5_000, channelCount: 1), bitDepth: 16, to: nativeURL)
        XCTAssertThrowsError(try decoder.inspect(url: nativeURL)) {
            XCTAssertEqual($0 as? SampleImportError, .fileExtensionMismatch)
        }
        let wavAsFLAC = directory.appendingPathComponent("wav-as-native.flac")
        try writePCM(
            sourceChannels(frameCount: 5_000, channelCount: 1),
            fileType: kAudioFileWAVEType, bigEndian: false, to: wavAsFLAC
        )
        XCTAssertThrowsError(try decoder.inspect(url: wavAsFLAC)) {
            XCTAssertEqual($0 as? SampleImportError, .fileExtensionMismatch)
        }
    }
    func testPreflightSkipsLegalMetadataAndBoundsEveryDeclaredBlock() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nativeURL = directory.appendingPathComponent("source.flac")
        try writeFLAC(sourceChannels(frameCount: 5_000, channelCount: 1), bitDepth: 16, to: nativeURL)
        let native = try Data(contentsOf: nativeURL)
        let streamInfo = native.subdata(in: 8..<42)

        var legal = Data("fLaC".utf8)
        legal.append(contentsOf: [0, 0, 0, 34])
        legal.append(streamInfo)
        legal.append(contentsOf: [0x81, 0, 0, 3, 0, 0, 0, 0])
        let legalURL = directory.appendingPathComponent("legal-padding.flac")
        try legal.write(to: legalURL)
        XCTAssertEqual(try FLACSampleImportDecoder().inspect(url: legalURL).frameCount, 5_000)

        var truncated = Data("fLaC".utf8)
        truncated.append(contentsOf: [0, 0, 0, 34])
        truncated.append(streamInfo)
        truncated.append(contentsOf: [0x81, 0xFF, 0xFF, 0xFF, 0])
        let truncatedURL = directory.appendingPathComponent("bounded-metadata.flac")
        try truncated.write(to: truncatedURL)
        XCTAssertThrowsError(try FLACSampleImportDecoder().inspect(url: truncatedURL)) {
            XCTAssertEqual($0 as? SampleImportError, .truncatedFLAC)
        }
    }
    func testFLACMatchesWAVAIFFAndAIFCNormalizationAndOwnsItsResult() throws {
        let directory = try temporaryDirectory()
        let channels = sourceChannels(frameCount: 5_000, channelCount: 2)
        let sources: [(URL, SampleImportFormat)] = [
            (directory.appendingPathComponent("Equivalent.flac"), .flac),
            (directory.appendingPathComponent("Equivalent.wav"), .wav),
            (directory.appendingPathComponent("Equivalent.aiff"), .aiff),
            (directory.appendingPathComponent("Equivalent.aifc"), .aifc),
        ]
        try writeFLAC(channels, bitDepth: 16, sampleRate: 48_000, to: sources[0].0)
        try writePCM(channels, fileType: kAudioFileWAVEType, bigEndian: false, to: sources[1].0)
        try writePCM(channels, fileType: kAudioFileAIFFType, bigEndian: true, to: sources[2].0)
        try writePCM(channels, fileType: kAudioFileAIFCType, bigEndian: true, to: sources[3].0)

        let decoder = SampleImportDecoder(flacDecoder: FLACSampleImportDecoder(chunkFrameCount: 193))
        var retained = [NormalizedSampleImport]()
        for mode in [SampleImportChannelMode.mixToMono, .left, .right] {
            var candidates = [NormalizedSampleImport]()
            for (url, format) in sources {
                XCTAssertEqual(try decoder.inspect(url: url).format, format)
                candidates.append(try decoder.normalizedImport(url: url, channelMode: mode))
            }
            XCTAssertEqual(candidates, Array(repeating: candidates[0], count: sources.count))
            retained.append(candidates[0])
        }
        try FileManager.default.removeItem(at: directory)

        let tuning = try SampleImportTuning(sourceSampleRate: 48_000)
        for candidate in retained {
            XCTAssertEqual(candidate.name, "Equivalent")
            XCTAssertEqual(candidate.frameCount, 5_000)
            XCTAssertEqual(candidate.bitDepthBits, 16)
            XCTAssertEqual(candidate.channelCount, 1)
            XCTAssertEqual(candidate.volume, 64)
            XCTAssertEqual(candidate.panning, 128)
            XCTAssertEqual(candidate.loopType, 0)
            XCTAssertEqual(candidate.relativeNote, tuning.relativeNote)
            XCTAssertEqual(candidate.finetune, tuning.finetune)
            XCTAssertTrue(candidate.isValidDocumentSample)
        }
    }
    func testImportedFLACRemainsAuditionableAndExportsXMAndNonSilentAudioAfterSourceRemoval() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Imported.flac")
        try writeFLAC(
            sourceChannels(frameCount: 5_000, channelCount: 1),
            bitDepth: 24, sampleRate: 8_363, to: source
        )
        let candidate = try SampleImportDecoder().normalizedImport(
            url: source, channelMode: .mixToMono
        )

        var document = BlankTrackerDocument.makeDefault()
        let destination = try XCTUnwrap(document.selectedSampleImportDestination)
        XCTAssertTrue(document.importAudioSample(candidate, destination: destination))
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let imported = try XCTUnwrap(document.instrumentPalette[1]?.samples.first)
        guard case let .potentiallyAvailable(descriptor) = document.noteAuditionAvailability else {
            return XCTFail("Expected imported FLAC sample to be auditionable")
        }
        XCTAssertEqual(descriptor.previewPCM, imported.pcm)
        XCTAssertEqual(descriptor.previewPanning, 128)
        XCTAssertEqual(descriptor.previewVolume, 1)

        let xmURL = directory.appendingPathComponent("round-trip.xm")
        try EditableXMWriter().data(from: document).write(to: xmURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: xmURL.path)
        let reopened = try PlaybackSongBuilder.build(
            from: metadata, modulePath: xmURL.path
        ).instrument(forInstrument: 1)?.sample(mappedSampleIndex: 0)
        XCTAssertEqual(reopened, imported)

        let exportContext = WAVExportDocumentContext.editable(
            document: document, displayName: document.title, isPlaybackActive: false
        )
        let wavURL = directory.appendingPathComponent("imported.wav")
        guard case let .exported(_, wavRender) = WAVExportCoordinator.export(
            plan: try WAVExportCoordinator.makePlan(context: exportContext), to: wavURL
        ) else {
            return XCTFail("Expected WAV export from imported FLAC")
        }
        XCTAssertGreaterThan(wavRender.exportDiagnostics?.preExportPeak ?? 0, 0)

        let m4aURL = directory.appendingPathComponent("imported.m4a")
        guard case let .exported(_, m4aRender, _) = M4AExportCoordinator.export(
            plan: try M4AExportCoordinator.makePlan(context: exportContext), to: m4aURL
        ) else {
            return XCTFail("Expected M4A export from imported FLAC")
        }
        XCTAssertGreaterThan(m4aRender.exportDiagnostics?.preExportPeak ?? 0, 0)
        XCTAssertGreaterThan((try Data(contentsOf: m4aURL)).count, 0)
    }

    private func sourceChannels(frameCount: Int, channelCount: Int) -> [[Float]] {
        let left: [Float] = [-0.5, -0.25, 0, 0.25, 0.5, 0.75]
        let right: [Float] = [0.75, 0.5, 0.25, 0, -0.25, -0.5]
        return (0..<channelCount).map { channel in
            let pattern = channel == 0 ? left : right
            return (0..<frameCount).map { pattern[$0 % pattern.count] }
        }
    }

    private func expectedMono(_ channels: [[Float]], mode: SampleImportChannelMode) -> [Float] {
        guard channels.count == 2 else { return channels[0] }
        switch mode {
        case .mixToMono: return zip(channels[0], channels[1]).map { 0.5 * $0 + 0.5 * $1 }
        case .left: return channels[0]
        case .right: return channels[1]
        }
    }

    private func writeFLAC(
        _ channels: [[Float]], bitDepth: Int, sampleRate: Double = 44_100, to url: URL
    ) throws {
        var fileFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatFLAC,
            mFormatFlags: bitDepth == 16
                ? kAppleLosslessFormatFlag_16BitSourceData
                : kAppleLosslessFormatFlag_24BitSourceData,
            mBytesPerPacket: 0, mFramesPerPacket: 4_608, mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels.count), mBitsPerChannel: 0, mReserved: 0
        )
        try writeAudio(channels, sampleRate: sampleRate, fileType: kAudioFileFLACType, fileFormat: &fileFormat, to: url)
    }

    private func writePCM(
        _ channels: [[Float]], fileType: AudioFileTypeID, bigEndian: Bool, to url: URL
    ) throws {
        let bytesPerFrame = UInt32(channels.count * 2)
        var fileFormat = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked |
                (bigEndian ? kAudioFormatFlagIsBigEndian : 0),
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame, mChannelsPerFrame: UInt32(channels.count),
            mBitsPerChannel: 16, mReserved: 0
        )
        try writeAudio(channels, sampleRate: 48_000, fileType: fileType, fileFormat: &fileFormat, to: url)
    }

    private func writeAudio(
        _ channels: [[Float]], sampleRate: Double, fileType: AudioFileTypeID,
        fileFormat: inout AudioStreamBasicDescription, to url: URL
    ) throws {
        let frameCount = try XCTUnwrap(channels.first?.count)
        XCTAssertTrue(channels.allSatisfy { $0.count == frameCount })
        var file: ExtAudioFileRef?
        try check(ExtAudioFileCreateWithURL(
            url as CFURL, fileType, &fileFormat, nil,
            AudioFileFlags.eraseFile.rawValue, &file
        ))
        guard let createdFile = file else { throw SampleImportError.audioDecodeFailed }
        defer {
            if let file { ExtAudioFileDispose(file) }
        }

        let clientFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels.count), interleaved: false
        ))
        var clientDescription = clientFormat.streamDescription.pointee
        try check(ExtAudioFileSetProperty(
            createdFile, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientDescription
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: clientFormat, frameCapacity: AVAudioFrameCount(frameCount)
        ))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let storage = try XCTUnwrap(buffer.floatChannelData)
        for channel in channels.indices {
            for frame in 0..<frameCount { storage[channel][frame] = channels[channel][frame] }
        }
        try check(ExtAudioFileWrite(createdFile, buffer.frameLength, buffer.audioBufferList))
        try check(ExtAudioFileDispose(createdFile))
        file = nil
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func settingBitDepth(_ bitDepth: Int, in source: Data) -> Data {
        var result = source
        let stored = bitDepth - 1
        result[20] = result[20] & 0xFE | UInt8((stored >> 4) & 1)
        result[21] = result[21] & 0x0F | UInt8((stored & 0x0F) << 4)
        return result
    }

    private func settingChannels(_ channelCount: Int, in source: Data) -> Data {
        var result = source
        result[20] = result[20] & 0xF1 | UInt8((channelCount - 1) << 1)
        return result
    }

    private func settingSampleRate(_ sampleRate: Int, in source: Data) -> Data {
        var result = source
        result[18] = UInt8((sampleRate >> 12) & 0xFF)
        result[19] = UInt8((sampleRate >> 4) & 0xFF)
        result[20] = result[20] & 0x0F | UInt8((sampleRate & 0x0F) << 4)
        return result
    }

    private func settingFrameCount(_ frameCount: UInt64, in source: Data) -> Data {
        var result = source
        result[21] = result[21] & 0xF0 | UInt8((frameCount >> 32) & 0x0F)
        for index in 0..<4 {
            result[22 + index] = UInt8((frameCount >> UInt64((3 - index) * 8)) & 0xFF)
        }
        return result
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assertPCM(
        _ actual: [Float], _ expected: [Float], _ context: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, context, file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: 0.000_001, context, file: file, line: line)
        }
    }
}
