import Foundation
import XCTest

final class WAVSampleImportDecoderTests: XCTestCase {
    func testDecodesRequiredLinearPCMEncodingsAndExtensiblePCM() throws {
        let cases: [(String, UInt16, Int, Data, [Float], Bool)] = [
            ("pcm8", 1, 8, Data([0, 128, 255]), [-1, 0, 127.0 / 128.0], false),
            ("pcm16", 1, 16, signedPayload([-32_768, 0, 32_767], bytes: 2), [-1, 0, 32_767.0 / 32_768.0], false),
            ("pcm24", 1, 24, signedPayload([-8_388_608, 0, 8_388_607], bytes: 3), [-1, 0, 8_388_607.0 / 8_388_608.0], false),
            ("pcm32", 1, 32, signedPayload([-2_147_483_648, 0, 2_147_483_647], bytes: 4), [-1, 0, 1], false),
            ("float32", 3, 32, floatPayload([-1.25, 0.25, 1.5]), [-1, 0.25, 1], false),
            ("extensible", 1, 16, signedPayload([-16_384, 0, 16_384], bytes: 2), [-0.5, 0, 0.5], true),
        ]
        for (name, format, bits, payload, expected, extensible) in cases {
            try withTemporaryWAV(name: name, data: wav(
                format: format, channels: 1, sampleRate: 44_100, bits: bits,
                payload: payload, extensible: extensible
            )) { url in
                let decoded = try WAVSampleImportDecoder().decode(url: url, channelMode: .mixToMono)
                XCTAssertEqual(decoded.sourceSampleRate, 44_100, "\(name)")
                XCTAssertEqual(decoded.sourceChannelCount, 1, "\(name)")
                XCTAssertEqual(decoded.sourceBitDepthBits, bits, "\(name)")
                XCTAssertEqual(decoded.frameCount, 3, "\(name)")
                assertPCM(decoded.monoPCM, expected, accuracy: 0.000_001, name)
            }
        }
    }
    func testStereoAndMonoChannelModesAreExplicitWithoutNormalization() throws {
        let stereo = wav(
            format: 1, channels: 2, sampleRate: 48_000, bits: 16,
            payload: signedPayload([16_384, -16_384, 8_192, 16_384], bytes: 2)
        )
        try withTemporaryWAV(name: "stereo", data: stereo) { url in
            let decoder = WAVSampleImportDecoder(chunkFrameCount: 1)
            assertPCM(try decoder.decode(url: url, channelMode: .left).monoPCM, [0.5, 0.25])
            assertPCM(try decoder.decode(url: url, channelMode: .right).monoPCM, [-0.5, 0.5])
            assertPCM(try decoder.decode(url: url, channelMode: .mixToMono).monoPCM, [0, 0.375])
        }
        try withTemporaryWAV(name: "mono", data: wav(
            format: 1, channels: 1, sampleRate: 8_363, bits: 16,
            payload: signedPayload([8_192, -8_192], bytes: 2)
        )) { url in
            let decoder = WAVSampleImportDecoder()
            let mix = try decoder.decode(url: url, channelMode: .mixToMono).monoPCM
            XCTAssertEqual(try decoder.decode(url: url, channelMode: .left).monoPCM, mix)
            XCTAssertEqual(try decoder.decode(url: url, channelMode: .right).monoPCM, mix)
        }
    }
    func testInspectionAndDecodeRejectMalformedUnsupportedAndEmptySources() throws {
        var truncated = Data("RIFF".utf8)
        truncated.appendLE(UInt32(100))
        truncated.append(contentsOf: Data("WAVE".utf8))
        let cases: [(String, Data, SampleImportError)] = [
            ("truncated", truncated, .truncatedWAV),
            ("empty", wav(format: 1, channels: 1, sampleRate: 44_100, bits: 16, payload: Data()), .emptySource),
            ("channels", wav(format: 1, channels: 3, sampleRate: 44_100, bits: 16, payload: Data(repeating: 0, count: 6)), .unsupportedChannelCount(3)),
            ("compressed", wav(format: 6, channels: 1, sampleRate: 8_000, bits: 8, payload: Data([0])), .unsupportedEncoding(formatCode: 6, bitsPerSample: 8)),
        ]
        for (name, data, expected) in cases {
            try withTemporaryWAV(name: name, data: data) { url in
                XCTAssertThrowsError(try WAVSampleImportDecoder().decode(url: url, channelMode: .mixToMono)) {
                    XCTAssertEqual($0 as? SampleImportError, expected)
                }
            }
        }
    }
    func testDecodedNonFinitePCMIsRejected() throws {
        try withTemporaryWAV(name: "nonfinite", data: wav(
            format: 3, channels: 1, sampleRate: 44_100, bits: 32,
            payload: floatPayload([0, .nan])
        )) { url in
            XCTAssertThrowsError(try WAVSampleImportDecoder().decode(url: url, channelMode: .left)) {
                XCTAssertEqual($0 as? SampleImportError, .nonFinitePCM)
            }
        }
    }
    func testCanonicalQuantizationMatchesWriterAndIsIdempotent() throws {
        let step = Float(1.0 / 32_768.0)
        let source: [Float] = [-1, -0.5 * step, 0, 0.5 * step, 1, 0.25]
        let expected: [Int16] = [-32_768, -1, 0, 1, 32_767, 8_192]
        XCTAssertEqual(try source.map(XMPCMQuantizer.signed16), expected)
        let decoded = DecodedSampleImport(
            sourceSampleRate: 8_363, sourceChannelCount: 1,
            sourceBitDepthBits: 32, monoPCM: source
        )
        let first = try NormalizedSampleImport(decoded: decoded, sourceFilename: "quiet.wav")
        let second = try NormalizedSampleImport(
            decoded: DecodedSampleImport(
                sourceSampleRate: 8_363, sourceChannelCount: 1,
                sourceBitDepthBits: 16, monoPCM: first.pcm
            ),
            sourceFilename: "quiet.wav"
        )
        XCTAssertEqual(first.pcm.map(\.bitPattern), second.pcm.map(\.bitPattern))
        XCTAssertEqual(try first.pcm.map(XMPCMQuantizer.signed16), expected)
        XCTAssertEqual(
            XMSampleDeltaEncoder.deltaEncodedSignedPCM(pcm: first.pcm, bitDepthBits: 16),
            XMSampleDeltaEncoder.deltaEncodedSignedPCM(pcm: second.pcm, bitDepthBits: 16)
        )
        XCTAssertEqual(first.pcm.last, 0.25)
    }
    func testTuningInvertsCurrentLinearPlaybackMapping() throws {
        let expected: [(Double, Int, Int)] = [
            (8_363, 0, 0), (16_726, 12, 0),
            (44_100, 29, -28), (48_000, 30, 32), (96_000, 42, 32),
            (8_000, -1, 30),
        ]
        for (rate, relativeNote, finetune) in expected {
            let tuning = try SampleImportTuning(sourceSampleRate: rate)
            XCTAssertEqual(tuning.relativeNote, relativeNote, "\(rate)")
            XCTAssertEqual(tuning.finetune, finetune, "\(rate)")
            XCTAssertLessThanOrEqual(abs(tuning.pitchErrorCents), 100.0 / 128.0 / 2.0 + 0.000_001)
            XCTAssertEqual(tuning.playbackSampleRate, rate, accuracy: rate * 0.000_5)
            let current = try XCTUnwrap(PlaybackSongSyntheticAdapter.linearPitchTarget(
                note: 49, relativeNote: relativeNote, finetune: finetune,
                baseSampleRate: PlaybackSample.xmNeutralSampleRate, outputSampleRate: PlaybackSample.xmNeutralSampleRate
            ))
            XCTAssertEqual(current.linearFrequency, tuning.playbackSampleRate, accuracy: 0.000_001)
        }
        XCTAssertThrowsError(try SampleImportTuning(sourceSampleRate: 1e100)) {
            XCTAssertEqual($0 as? SampleImportError, .tuningOutOfRange)
        }
    }
    func testFilenameNamingCandidateDefaultsAndSourceLifetime() throws {
        XCTAssertEqual(SampleImportNaming.sampleName(filename: "TR909_Kick_03.wav"), "TR909_Kick_03")
        XCTAssertEqual(SampleImportNaming.sampleName(filename: "kick.final.v2.wav"), "kick.final.v2")
        XCTAssertEqual(SampleImportNaming.sampleName(filename: "   .wav"), "(unnamed sample)")
        XCTAssertEqual(SampleImportNaming.sampleName(filename: "1234567890123456789012345.wav"), "1234567890123456789012")
        XCTAssertEqual(SampleImportNaming.sampleName(filename: "Kïck.wav"), "K?ck")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Owned.wav")
        try wav(
            format: 1, channels: 1, sampleRate: 48_000, bits: 16,
            payload: signedPayload([0, 16_384], bytes: 2)
        ).write(to: url)
        let candidate = try WAVSampleImportDecoder().normalizedImport(url: url, channelMode: .mixToMono)
        try FileManager.default.removeItem(at: directory)
        XCTAssertEqual(candidate.name, "Owned")
        XCTAssertEqual(candidate.frameCount, 2)
        XCTAssertEqual(candidate.bitDepthBits, 16)
        XCTAssertEqual(candidate.channelCount, 1)
        XCTAssertEqual(candidate.volume, 64)
        XCTAssertEqual(candidate.panning, 128)
        XCTAssertEqual(candidate.loopType, 0)
        XCTAssertEqual(candidate.pcm, [0, 0.5])
        let sample = candidate.playbackSample(instrumentIndex: 1, sampleIndex: 0)
        XCTAssertEqual(sample.name, "Owned")
        XCTAssertEqual(sample.sourceBitDepthBits, 16)
        XCTAssertEqual(sample.sampleLength, 2)
        XCTAssertEqual(sample.baseSampleRate, 8_363)
    }
    func testResourceBoundsRejectOversizeAndOverflowWithoutAllocation() throws {
        XCTAssertNoThrow(try SampleImportResourcePolicy.validate(frameCount: UInt64(SampleImportResourcePolicy.maximumFrameCount)))
        XCTAssertThrowsError(try SampleImportResourcePolicy.validate(frameCount: UInt64(SampleImportResourcePolicy.maximumFrameCount + 1))) {
            XCTAssertEqual($0 as? SampleImportError, .resourceLimitExceeded)
        }
        XCTAssertThrowsError(try SampleImportResourcePolicy.canonicalByteCount(frameCount: UInt64.max)) {
            XCTAssertEqual($0 as? SampleImportError, .integerOverflow)
        }
    }

    private func assertPCM(
        _ actual: [Float], _ expected: [Float], accuracy: Float = 0.000_001,
        _ context: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, context, file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: accuracy, context, file: file, line: line)
        }
    }

    private func withTemporaryWAV(name: String, data: Data, _ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("\(name).wav")
        try data.write(to: url)
        try body(url)
    }

    private func wav(
        format: UInt16, channels: UInt16, sampleRate: UInt32, bits: Int,
        payload: Data, extensible: Bool = false
    ) -> Data {
        let bytesPerSample = bits / 8
        let blockAlign = UInt16(Int(channels) * bytesPerSample)
        var fmt = Data()
        fmt.appendLE(extensible ? UInt16(0xFFFE) : format)
        fmt.appendLE(channels)
        fmt.appendLE(sampleRate)
        fmt.appendLE(sampleRate * UInt32(blockAlign))
        fmt.appendLE(blockAlign)
        fmt.appendLE(UInt16(bits))
        if extensible {
            fmt.appendLE(UInt16(22))
            fmt.appendLE(UInt16(bits))
            fmt.appendLE(UInt32(0))
            fmt.append(contentsOf: [UInt8(format & 0xFF), UInt8(format >> 8), 0, 0, 0, 0, 0x10, 0, 0x80, 0, 0, 0xAA, 0, 0x38, 0x9B, 0x71])
        }
        var body = Data("WAVEfmt ".utf8)
        body.appendLE(UInt32(fmt.count))
        body.append(fmt)
        body.append(contentsOf: Data("data".utf8))
        body.appendLE(UInt32(payload.count))
        body.append(payload)
        if payload.count.isMultiple(of: 2) == false { body.append(0) }
        var result = Data("RIFF".utf8)
        result.appendLE(UInt32(body.count))
        result.append(body)
        return result
    }

    private func signedPayload(_ samples: [Int64], bytes: Int) -> Data {
        var data = Data()
        for sample in samples {
            let raw = UInt64(bitPattern: sample)
            for shift in 0..<bytes { data.append(UInt8(truncatingIfNeeded: raw >> (shift * 8))) }
        }
        return data
    }

    private func floatPayload(_ samples: [Float]) -> Data {
        var data = Data()
        for sample in samples { data.appendLE(sample.bitPattern) }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
