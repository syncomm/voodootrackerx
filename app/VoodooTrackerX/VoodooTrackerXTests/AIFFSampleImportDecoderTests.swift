import Foundation
import XCTest
final class AIFFSampleImportDecoderTests: XCTestCase {
    func testAIFFDecodesIntegerWidthsAndExplicitChannelModes() throws {
        let integerCases: [(Int, [Int64], [Float])] = [
            (1, [-128, 0, 127], [-1, 0, 127.0 / 128.0]),
            (2, [-32_768, 0, 32_767], [-1, 0, 32_767.0 / 32_768.0]),
            (3, [-8_388_608, 0, 8_388_607], [-1, 0, 8_388_607.0 / 8_388_608.0]),
            (4, [-2_147_483_648, 0, 2_147_483_647], [-1, 0, 1]),
        ]
        for (bytes, samples, expected) in integerCases {
            try withTemporaryAudio(name: "pcm\(bytes * 8).aiff", data: aiff(
                bits: bytes * 8, frameCount: samples.count,
                pcm: signedPCM(samples, bytes: bytes, littleEndian: false)
            )) { url in
                let decoder = AIFFSampleImportDecoder(chunkFrameCount: 1)
                let inspection = try decoder.inspect(url: url)
                XCTAssertEqual(inspection.sourceBitDepthBits, bytes * 8)
                XCTAssertEqual(inspection.frameCount, samples.count)
                let mix = try decoder.decode(url: url, channelMode: .mixToMono).monoPCM
                assertPCM(mix, expected)
                XCTAssertEqual(try decoder.decode(url: url, channelMode: .left).monoPCM, mix)
                XCTAssertEqual(try decoder.decode(url: url, channelMode: .right).monoPCM, mix)
            }
        }

        let stereo = aiff(
            channels: 2, bits: 16, frameCount: 2,
            pcm: signedPCM([16_384, -16_384, 8_192, 16_384], bytes: 2, littleEndian: false),
            chunksBeforeCOMM: [("JUNK", Data([1, 2, 3]))], ssndOffset: 3
        )
        try withTemporaryAudio(name: "stereo.aiff", data: stereo) { url in
            let decoder = AIFFSampleImportDecoder(chunkFrameCount: 1)
            XCTAssertEqual(try decoder.inspect(url: url).sourceChannelCount, 2)
            XCTAssertEqual(try decoder.inspect(url: url).frameCount, 2)
            assertPCM(try decoder.decode(url: url, channelMode: .left).monoPCM, [0.5, 0.25])
            assertPCM(try decoder.decode(url: url, channelMode: .right).monoPCM, [-0.5, 0.5])
            assertPCM(try decoder.decode(url: url, channelMode: .mixToMono).monoPCM, [0, 0.375])
        }
    }
    func testAIFCAcceptsNONEtwosAndsowtWithEquivalentOutput() throws {
        let samples: [Int64] = [-32_768, -123, 0, 12_345, 32_767]
        var candidates = [NormalizedSampleImport]()
        for (compression, littleEndian) in [("NONE", false), ("twos", false), ("sowt", true)] {
            try withTemporaryAudio(name: "Equivalent.aifc", data: aiff(
                formType: "AIFC", bits: 16, frameCount: samples.count,
                compression: compression,
                pcm: signedPCM(samples, bytes: 2, littleEndian: littleEndian)
            )) { url in
                let decoder = AIFFSampleImportDecoder(chunkFrameCount: 2)
                candidates.append(try decoder.normalizedImport(url: url, channelMode: .mixToMono))
            }
        }
        XCTAssertEqual(candidates[0], candidates[1])
        XCTAssertEqual(candidates[1], candidates[2])
    }
    func testExtendedRatesFeedSharedTuningWithoutResampling() throws {
        let rates = [8_363, 11_025, 22_050, 32_000, 44_100, 48_000, 88_200, 96_000]
        for rate in rates {
            try withTemporaryAudio(name: "rate.aiff", data: aiff(
                sampleRate: rate, bits: 16, frameCount: 2,
                pcm: signedPCM([0, 1_000], bytes: 2, littleEndian: false)
            )) { url in
                let decoder = AIFFSampleImportDecoder()
                XCTAssertEqual(try decoder.inspect(url: url).sourceSampleRate, Double(rate))
                let candidate = try decoder.normalizedImport(url: url, channelMode: .left)
                let tuning = try SampleImportTuning(sourceSampleRate: Double(rate))
                XCTAssertEqual(candidate.frameCount, 2)
                XCTAssertEqual(candidate.relativeNote, tuning.relativeNote)
                XCTAssertEqual(candidate.finetune, tuning.finetune)
                XCTAssertLessThanOrEqual(abs(tuning.pitchErrorCents), 100.0 / 256.0 + 0.000_001)
            }
        }
    }
    func testWAVAndAIFFNormalizeToEquivalentSharedCandidates() throws {
        let samples: [Int64] = [-32_768, -4_096, 0, 12_345, 32_767]
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wavURL = directory.appendingPathComponent("Equivalent.wav")
        let aiffURL = directory.appendingPathComponent("Equivalent.aiff")
        try wav16(samples: samples, sampleRate: 48_000).write(to: wavURL)
        try aiff(
            sampleRate: 48_000, bits: 16, frameCount: samples.count,
            pcm: signedPCM(samples, bytes: 2, littleEndian: false)
        ).write(to: aiffURL)

        let wavCandidate = try WAVSampleImportDecoder().normalizedImport(url: wavURL, channelMode: .mixToMono)
        let aiffCandidate = try AIFFSampleImportDecoder().normalizedImport(url: aiffURL, channelMode: .mixToMono)
        XCTAssertEqual(wavCandidate, aiffCandidate)
        try FileManager.default.removeItem(at: wavURL)
        try FileManager.default.removeItem(at: aiffURL)
        XCTAssertTrue(aiffCandidate.isValidDocumentSample)
        XCTAssertEqual(aiffCandidate.pcm.count, samples.count)
    }
    func testFormatNeutralFacadeDispatchesWAVAIFFAndAIFCToEqualOwnedCandidates() throws {
        let samples: [Int64] = [-32_768, -4_096, 0, 12_345, 32_767]
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sources: [(URL, SampleImportFormat, Data)] = [
            (
                directory.appendingPathComponent("Equivalent.wav"), .wav,
                wav16(samples: samples, sampleRate: 48_000)
            ),
            (
                directory.appendingPathComponent("Equivalent.aiff"), .aiff,
                aiff(
                    sampleRate: 48_000, bits: 16, frameCount: samples.count,
                    pcm: signedPCM(samples, bytes: 2, littleEndian: false)
                )
            ),
            (
                directory.appendingPathComponent("Equivalent.aifc"), .aifc,
                aiff(
                    formType: "AIFC", sampleRate: 48_000, bits: 16,
                    frameCount: samples.count, compression: "twos",
                    pcm: signedPCM(samples, bytes: 2, littleEndian: false)
                )
            ),
        ]
        for (url, _, data) in sources { try data.write(to: url) }

        let decoder = SampleImportDecoder()
        var candidates = [NormalizedSampleImport]()
        for (url, format, _) in sources {
            let inspection = try decoder.inspect(url: url)
            XCTAssertEqual(inspection.format, format)
            XCTAssertEqual(inspection.sourceChannelCount, 1)
            candidates.append(try decoder.normalizedImport(url: url, channelMode: .mixToMono))
        }
        XCTAssertEqual(candidates, Array(repeating: candidates[0], count: sources.count))

        for (url, _, _) in sources { try FileManager.default.removeItem(at: url) }
        XCTAssertTrue(candidates.allSatisfy(\.isValidDocumentSample))
        XCTAssertTrue(candidates.allSatisfy { $0.pcm.count == samples.count })
    }
    func testFormatNeutralFacadeRejectsExtensionContainerMismatchAndUnknownContainer() throws {
        let samples: [Int64] = [0, 1_000]
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mismatches = [
            (
                directory.appendingPathComponent("wav-as-aiff.aiff"),
                wav16(samples: samples, sampleRate: 8_363)
            ),
            (
                directory.appendingPathComponent("aiff-as-wav.wav"),
                aiff(
                    sampleRate: 8_363, bits: 16, frameCount: samples.count,
                    pcm: signedPCM(samples, bytes: 2, littleEndian: false)
                )
            ),
            (
                directory.appendingPathComponent("aifc-as-aif.aif"),
                aiff(
                    formType: "AIFC", sampleRate: 8_363, bits: 16,
                    frameCount: samples.count, compression: "NONE",
                    pcm: signedPCM(samples, bytes: 2, littleEndian: false)
                )
            ),
        ]
        let decoder = SampleImportDecoder()
        for (url, data) in mismatches {
            try data.write(to: url)
            XCTAssertThrowsError(try decoder.inspect(url: url)) {
                XCTAssertEqual($0 as? SampleImportError, .fileExtensionMismatch)
            }
        }

        let unknown = directory.appendingPathComponent("unknown.wav")
        try Data(repeating: 0, count: 12).write(to: unknown)
        XCTAssertThrowsError(try decoder.inspect(url: unknown)) {
            XCTAssertEqual($0 as? SampleImportError, .unsupportedContainer)
        }
    }
    func testSampleEditorLiveWorkerUsesFacadeForAIFCOffMainThread() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Worker.aifc")
        try aiff(
            formType: "AIFC", bits: 16, frameCount: 2, compression: "sowt",
            pcm: signedPCM([-16_384, 16_384], bytes: 2, littleEndian: true)
        ).write(to: url)

        let worker = SampleEditorWAVImportWorker.live()
        guard case let .success(inspection) = await worker.inspect(url) else {
            return XCTFail("Expected AIFC inspection")
        }
        XCTAssertEqual(inspection.format, .aifc)
        guard case let .success(candidate) = await worker.normalize(url, .mixToMono) else {
            return XCTFail("Expected AIFC normalization")
        }
        XCTAssertEqual(candidate.name, "Worker")
        XCTAssertTrue(candidate.isValidDocumentSample)
    }
    func testAIFFAndAIFCCandidatesFillEmptyS01AndExportXMWithoutSourceDependency() throws {
        for (filename, formType, compression, littleEndian) in [
            ("Imported.aiff", "AIFF", "NONE", false),
            ("Imported.aifc", "AIFC", "twos", false),
        ] {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = directory.appendingPathComponent(filename)
            try aiff(
                formType: formType, bits: 16, frameCount: 3, compression: compression,
                pcm: signedPCM([-16_384, 0, 16_384], bytes: 2, littleEndian: littleEndian)
            ).write(to: source)
            let candidate = try SampleImportDecoder().normalizedImport(
                url: source, channelMode: .mixToMono
            )
            try FileManager.default.removeItem(at: source)

            var document = BlankTrackerDocument.makeDefault()
            let destination = try XCTUnwrap(document.selectedSampleImportDestination)
            XCTAssertTrue(document.importAudioSample(candidate, destination: destination))
            let imported = try XCTUnwrap(document.instrumentPalette[1]?.samples.first)
            let exported = directory.appendingPathComponent("round-trip.xm")
            try EditableXMWriter().data(from: document).write(to: exported)
            let metadata = try ModuleMetadataLoader().load(fromPath: exported.path)
            let reopened = try PlaybackSongBuilder.build(
                from: metadata, modulePath: exported.path
            ).instrument(forInstrument: 1)?.sample(mappedSampleIndex: 0)

            XCTAssertEqual(reopened, imported)
            XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap, Array(repeating: 0, count: 96))
        }
    }
    func testRejectsMalformedUnsupportedAndResourceViolations() throws {
        let missingCOMM = form(type: "AIFF", chunks: [chunk("SSND", ssnd(pcm: Data([0, 0])))])
        let missingSSND = form(type: "AIFF", chunks: [chunk("COMM", comm(bits: 16, frameCount: 1))])
        var truncated = aiff(bits: 16, frameCount: 1, pcm: Data([0, 0]))
        truncated.removeLast()
        var overflowingChunk = Data("FORM".utf8)
        overflowingChunk.appendBE(UInt32.max)
        overflowingChunk.append(contentsOf: Data("AIFF".utf8))
        let cases: [(String, Data, SampleImportError)] = [
            ("short.aiff", Data(), .truncatedAIFF),
            ("wrong.aiff", Data(repeating: 0, count: 12), .malformedAIFF),
            ("missing-comm.aiff", missingCOMM, .malformedAIFF),
            ("missing-ssnd.aiff", missingSSND, .malformedAIFF),
            ("truncated.aiff", truncated, .truncatedAIFF),
            ("overflow.aiff", overflowingChunk, .truncatedAIFF),
            ("zero-channels.aiff", aiff(channels: 0, bits: 16, frameCount: 1, pcm: Data()), .unsupportedChannelCount(0)),
            ("channels.aiff", aiff(channels: 3, bits: 16, frameCount: 1, pcm: Data(repeating: 0, count: 6)), .unsupportedChannelCount(3)),
            ("empty.aiff", aiff(bits: 16, frameCount: 0, pcm: Data()), .emptySource),
            ("width.aiff", aiff(bits: 12, frameCount: 1, pcm: Data([0, 0])), .unsupportedPCMBitDepth(12)),
            ("compressed.aifc", aiff(formType: "AIFC", bits: 16, frameCount: 1, compression: "ulaw", pcm: Data([0, 0])), .unsupportedAIFFCompression("ulaw")),
            ("oversized.aiff", aiff(bits: 8, frameCount: SampleImportResourcePolicy.maximumFrameCount + 1, pcm: Data()), .resourceLimitExceeded),
        ]
        for (name, data, expected) in cases {
            try withTemporaryAudio(name: name, data: data) { url in
                XCTAssertThrowsError(try AIFFSampleImportDecoder().inspect(url: url), name) {
                    XCTAssertEqual($0 as? SampleImportError, expected, name)
                }
            }
        }
    }
    func testRejectsMalformedAIFCNameSSNDOffsetAndExtendedRates() throws {
        var malformedNameCOMM = comm(bits: 16, frameCount: 1, formType: "AIFC", compression: "NONE")
        malformedNameCOMM[22] = 10
        let malformedName = form(type: "AIFC", chunks: [
            chunk("COMM", malformedNameCOMM), chunk("SSND", ssnd(pcm: Data([0, 0]))),
        ])
        let badOffset = form(type: "AIFF", chunks: [
            chunk("COMM", comm(bits: 16, frameCount: 1)),
            chunk("SSND", ssnd(pcm: Data(), offset: 4)),
        ])
        for data in [malformedName, badOffset] {
            try withTemporaryAudio(name: "malformed.aifc", data: data) { url in
                XCTAssertThrowsError(try AIFFSampleImportDecoder().inspect(url: url))
            }
        }

        let invalidRates: [Data] = [
            Data(repeating: 0, count: 10),
            Data([0xC0, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]),
            Data([0x7F, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]),
            Data([0x40, 0x0E, 0x2C, 0x44, 0, 0, 0, 0, 0, 0]),
        ]
        for rate in invalidRates {
            XCTAssertThrowsError(try AIFFExtendedSampleRate.decode(rate)) {
                XCTAssertEqual($0 as? SampleImportError, .invalidSampleRate)
            }
        }
    }
    private func assertPCM(
        _ actual: [Float], _ expected: [Float],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: 0.000_001, file: file, line: line)
        }
    }
    private func withTemporaryAudio(name: String, data: Data, _ body: (URL) throws -> Void) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        try body(url)
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func aiff(
        formType: String = "AIFF", channels: Int = 1, sampleRate: Int = 44_100,
        bits: Int, frameCount: Int, compression: String = "NONE", pcm: Data,
        chunksBeforeCOMM: [(String, Data)] = [], ssndOffset: Int = 0
    ) -> Data {
        let chunks = chunksBeforeCOMM.map { chunk($0.0, $0.1) } + [
            chunk("COMM", comm(
                channels: channels, sampleRate: sampleRate, bits: bits,
                frameCount: frameCount, formType: formType, compression: compression
            )),
            chunk("SSND", ssnd(pcm: pcm, offset: ssndOffset)),
        ]
        return form(type: formType, chunks: chunks)
    }
    private func comm(
        channels: Int = 1, sampleRate: Int = 44_100, bits: Int,
        frameCount: Int, formType: String = "AIFF", compression: String = "NONE"
    ) -> Data {
        var data = Data()
        data.appendBE(UInt16(channels))
        data.appendBE(UInt32(frameCount))
        data.appendBE(UInt16(bits))
        data.append(extendedRate(sampleRate))
        if formType == "AIFC" {
            data.append(contentsOf: Data(compression.utf8))
            data.append(0)
            data.append(0)
        }
        return data
    }
    private func ssnd(pcm: Data, offset: Int = 0) -> Data {
        var data = Data()
        data.appendBE(UInt32(offset))
        data.appendBE(UInt32(0))
        data.append(Data(repeating: 0xA5, count: offset))
        data.append(pcm)
        return data
    }
    private func form(type: String, chunks: [Data]) -> Data {
        var body = Data(type.utf8)
        chunks.forEach { body.append($0) }
        var data = Data("FORM".utf8)
        data.appendBE(UInt32(body.count))
        data.append(body)
        return data
    }
    private func chunk(_ id: String, _ payload: Data) -> Data {
        var data = Data(id.utf8)
        data.appendBE(UInt32(payload.count))
        data.append(payload)
        if !payload.count.isMultiple(of: 2) { data.append(0) }
        return data
    }

    private func extendedRate(_ rate: Int) -> Data {
        let value = UInt64(rate)
        let power = 63 - value.leadingZeroBitCount
        let exponent = UInt16(16_383 + power)
        let significand = value << UInt64(63 - power)
        var data = Data()
        data.appendBE(exponent)
        data.appendBE(significand)
        return data
    }

    private func signedPCM(_ samples: [Int64], bytes: Int, littleEndian: Bool) -> Data {
        var data = Data()
        for sample in samples {
            let raw = UInt64(bitPattern: sample)
            for index in 0..<bytes {
                let shift = littleEndian ? index * 8 : (bytes - index - 1) * 8
                data.append(UInt8(truncatingIfNeeded: raw >> shift))
            }
        }
        return data
    }

    private func wav16(samples: [Int64], sampleRate: UInt32) -> Data {
        let pcm = signedPCM(samples, bytes: 2, littleEndian: true)
        var format = Data()
        format.appendLE(UInt16(1))
        format.appendLE(UInt16(1))
        format.appendLE(sampleRate)
        format.appendLE(sampleRate * 2)
        format.appendLE(UInt16(2))
        format.appendLE(UInt16(16))
        var body = Data("WAVEfmt ".utf8)
        body.appendLE(UInt32(format.count))
        body.append(format)
        body.append(contentsOf: Data("data".utf8))
        body.appendLE(UInt32(pcm.count))
        body.append(pcm)
        var data = Data("RIFF".utf8)
        data.appendLE(UInt32(body.count))
        data.append(body)
        return data
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
