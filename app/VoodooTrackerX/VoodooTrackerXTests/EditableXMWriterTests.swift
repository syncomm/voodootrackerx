import CryptoKit
import XCTest

final class EditableXMWriterTests: XCTestCase {
    func testDefaultBlankDocumentWritesXMHeaderBasicsInMemory() throws {
        let document = BlankTrackerDocument.makeDefault()

        let data = try EditableXMWriter().data(from: document)

        XCTAssertEqual(data.ascii(offset: 0, length: 17), "Extended Module: ")
        XCTAssertEqual(data.ascii(offset: 17, length: 20), "Untitled")
        XCTAssertEqual(data[37], 0x1A)
        XCTAssertEqual(data.ascii(offset: 38, length: 20), "VoodooTrackerX")
        XCTAssertEqual(data.le16(at: 58), 0x0104)
        XCTAssertEqual(data.le32(at: 60), 276)
        XCTAssertEqual(data.le16(at: 64), 1)
        XCTAssertEqual(data.le16(at: 66), 0)
        XCTAssertEqual(data.le16(at: 68), 8)
        XCTAssertEqual(data.le16(at: 70), 1)
        XCTAssertEqual(data.le16(at: 72), 1)
        XCTAssertEqual(data.le16(at: 74), 0x0001)
        XCTAssertEqual(data.le16(at: 76), 6)
        XCTAssertEqual(data.le16(at: 78), 125)
        XCTAssertEqual(Array(data.subdata(in: 80..<84)), [0, 0, 0, 0])

        let pattern = data.patternHeader(at: 336)
        XCTAssertEqual(pattern.headerLength, 9)
        XCTAssertEqual(pattern.packingType, 0)
        XCTAssertEqual(pattern.rowCount, 64)
        XCTAssertEqual(pattern.packedSize, 0)
        XCTAssertEqual(data.le32(at: pattern.nextOffset), 29)
        XCTAssertEqual(data.ascii(offset: pattern.nextOffset + 4, length: 22), "")
        XCTAssertEqual(data.le16(at: pattern.nextOffset + 27), 0)
        XCTAssertEqual(pattern.nextOffset + 29, data.count)
    }

    func testWriterUsesEditableOrderTimingChannelsAndSanitizedTitle() throws {
        let firstPattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 4)
        let secondPattern = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 16, channels: 4)
        let document = makeDocument(
            title: "  Unit\nSong  ",
            restartPosition: 1,
            tempo: 140,
            speed: 3,
            orderTable: [0, 1, 0],
            patterns: [firstPattern, secondPattern]
        )

        let data = try EditableXMWriter().data(from: document)

        XCTAssertEqual(data.ascii(offset: 17, length: 20), "Unit Song")
        XCTAssertEqual(data.le16(at: 64), 3)
        XCTAssertEqual(data.le16(at: 66), 1)
        XCTAssertEqual(data.le16(at: 68), 4)
        XCTAssertEqual(data.le16(at: 70), 2)
        XCTAssertEqual(data.le16(at: 76), 3)
        XCTAssertEqual(data.le16(at: 78), 140)
        XCTAssertEqual(Array(data.subdata(in: 80..<83)), [0, 1, 0])
    }

    func testBlankPatternWritesZeroPackedSize() throws {
        let pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 8, channels: 2)
        let document = makeDocument(orderTable: [0], patterns: [pattern])

        let data = try EditableXMWriter().data(from: document)
        let patternHeader = data.patternHeader(at: 336)

        XCTAssertEqual(patternHeader.rowCount, 8)
        XCTAssertEqual(patternHeader.packedSize, 0)
        XCTAssertEqual(patternHeader.nextOffset, data.count)
    }

    func testPackedPatternWritesNoteInstrumentKeyOffVolumeAndEffectCells() throws {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 3, channels: 2)
        pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        pattern.rows[1][1] = XMPatternEventCell(
            note: XMPatternEventCell.keyOffNoteValue,
            instrument: 0,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        let document = makeDocument(orderTable: [0], patterns: [pattern])

        let data = try EditableXMWriter().data(from: document)
        let patternHeader = data.patternHeader(at: 336)

        XCTAssertEqual(data.le16(at: 72), 1)
        XCTAssertEqual(patternHeader.rowCount, 3)
        XCTAssertEqual(patternHeader.packedSize, 12)
        XCTAssertEqual(
            Array(data.subdata(in: patternHeader.dataRange)),
            [
                0x9F, 49, 1, 0x40, 0x0F, 0x7D,
                0x80,
                0x80,
                0x81, XMPatternEventCell.keyOffNoteValue,
                0x80,
                0x80,
            ]
        )

        let instrumentOffset = patternHeader.nextOffset
        XCTAssertEqual(data.le32(at: instrumentOffset), 29)
        XCTAssertEqual(data.ascii(offset: instrumentOffset + 4, length: 22), "")
        XCTAssertEqual(data[instrumentOffset + 26], 0)
        XCTAssertEqual(data.le16(at: instrumentOffset + 27), 0)
    }

    func testInstrumentHeaderExportsRepresentedVolumePanningEnvelopesAndAutoVibrato() throws {
        let sample = makeXMSourceSample(instrumentIndex: 3, sampleIndex: 0, pcm: [0])
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 10, value: 32),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 1,
            typeFlags: 0x07,
            fadeout: 1_234
        )
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 32),
                PlaybackEnvelopePoint(tick: 6, value: 48),
                PlaybackEnvelopePoint(tick: 18, value: 16),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 2,
            typeFlags: 0x07
        )
        let instrument = PlaybackInstrument(
            index: 3,
            name: "Lead One",
            samples: [sample],
            volumeEnvelope: envelope,
            panningEnvelope: panningEnvelope,
            autoVibrato: PlaybackInstrumentAutoVibrato(
                waveformType: 3,
                sweep: 17,
                depth: 42,
                rate: 199
            ),
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        let pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)
        let document = makeDocument(
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [3: instrument]
        )

        let data = try EditableXMWriter().data(from: document)
        let patternHeader = data.patternHeader(at: 336)
        let firstInstrumentOffset = patternHeader.nextOffset
        let thirdInstrumentOffset = firstInstrumentOffset + 58

        XCTAssertEqual(data.le16(at: 72), 3)
        XCTAssertEqual(data.le32(at: firstInstrumentOffset), 29)
        XCTAssertEqual(data.le32(at: firstInstrumentOffset + 29), 29)
        XCTAssertEqual(data.le32(at: thirdInstrumentOffset), 263)
        XCTAssertEqual(data.ascii(offset: thirdInstrumentOffset + 4, length: 22), "Lead One")
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 27), 1)
        XCTAssertEqual(data.le32(at: thirdInstrumentOffset + 29), 40)
        XCTAssertEqual(Array(data.subdata(in: thirdInstrumentOffset + 33..<thirdInstrumentOffset + 129)), Array(repeating: 0, count: 96))
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 129), 0)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 131), 64)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 133), 10)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 135), 32)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 177), 0)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 179), 32)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 181), 6)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 183), 48)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 185), 18)
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 187), 16)
        XCTAssertEqual(Array(data.subdata(in: thirdInstrumentOffset + 189..<thirdInstrumentOffset + 225)), Array(repeating: 0, count: 36))
        XCTAssertEqual(data[thirdInstrumentOffset + 225], 2)
        XCTAssertEqual(data[thirdInstrumentOffset + 226], 3)
        XCTAssertEqual(data[thirdInstrumentOffset + 227], 1)
        XCTAssertEqual(data[thirdInstrumentOffset + 228], 0)
        XCTAssertEqual(data[thirdInstrumentOffset + 229], 1)
        XCTAssertEqual(Array(data.subdata(in: thirdInstrumentOffset + 230..<thirdInstrumentOffset + 233)), [1, 0, 2])
        XCTAssertEqual(data[thirdInstrumentOffset + 233], 0x07)
        XCTAssertEqual(data[thirdInstrumentOffset + 234], 0x07)
        XCTAssertEqual(Array(data.subdata(in: thirdInstrumentOffset + 235..<thirdInstrumentOffset + 239)), [3, 17, 42, 199])
        XCTAssertEqual(data.le16(at: thirdInstrumentOffset + 239), 1_234)
    }

    func testWriterRejectsMoreThanTwelvePanningEnvelopePoints() {
        let sample = makeXMSourceSample(pcm: [0])
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: (0..<13).map { PlaybackEnvelopePoint(tick: $0, value: 32) },
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x01
        )
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, samples: [sample], panningEnvelope: panningEnvelope)
            ]
        )

        XCTAssertThrowsError(try EditableXMWriter().data(from: document)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedPanningEnvelopePointCount(instrumentIndex: 1, pointCount: 13)
            )
        }
    }

    func testSampleHeaderExportsLoopTypeVolumePanningFinetuneRelativeNoteAndName() throws {
        let sample = makeXMSourceSample(
            name: "Looped",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: 0.5,
            relativeNote: -2,
            finetune: 7,
            loopStart: 1,
            loopLength: 2,
            loopType: 2
        )
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, name: "Instrument", samples: [sample])
            ]
        )

        let data = try EditableXMWriter().data(from: document)
        let patternHeader = data.patternHeader(at: 336)
        let instrument = data.instrumentHeader(at: patternHeader.nextOffset)
        let sampleHeader = data.sampleHeader(at: instrument.sampleHeaderOffset)

        XCTAssertEqual(instrument.headerLength, 263)
        XCTAssertEqual(instrument.sampleCount, 1)
        XCTAssertEqual(
            Array(data.subdata(in: patternHeader.nextOffset + 177..<patternHeader.nextOffset + 225)),
            Array(repeating: 0, count: 48)
        )
        XCTAssertEqual(Array(data.subdata(in: patternHeader.nextOffset + 226..<patternHeader.nextOffset + 235)), Array(repeating: 0, count: 9))
        XCTAssertEqual(
            Array(data.subdata(in: patternHeader.nextOffset + 235..<patternHeader.nextOffset + 239)),
            [0, 0, 0, 0]
        )
        XCTAssertEqual(sampleHeader.lengthBytes, 4)
        XCTAssertEqual(sampleHeader.loopStartBytes, 1)
        XCTAssertEqual(sampleHeader.loopLengthBytes, 2)
        XCTAssertEqual(sampleHeader.volume, 32)
        XCTAssertEqual(sampleHeader.finetune, UInt8(bitPattern: Int8(7)))
        XCTAssertEqual(sampleHeader.type, 0x02)
        XCTAssertEqual(sampleHeader.panning, 128)
        XCTAssertEqual(sampleHeader.relativeNote, UInt8(bitPattern: Int8(-2)))
        XCTAssertEqual(sampleHeader.name, "Looped")
        XCTAssertEqual(
            Array(data.subdata(in: instrument.sampleDataOffset..<instrument.nextOffset)),
            [0, 64, 128, 96]
        )
    }

    func testSampleHeaderEmitsExactPanningBytesWithoutChangingOtherHeaderFields() throws {
        for panning in [UInt8(0), 128, 255, 37] {
            let sample = makeXMSourceSample(
                name: "Panned",
                pcm: [0, 0.5, -0.5, 0.25],
                volume: 0.5,
                panning: panning,
                relativeNote: -2,
                finetune: 7,
                loopStart: 1,
                loopLength: 2,
                loopType: 2
            )
            let document = makeDocument(
                orderTable: [0],
                patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
                instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
            )

            let data = try EditableXMWriter().data(from: document)
            let patternHeader = data.patternHeader(at: 336)
            let instrument = data.instrumentHeader(at: patternHeader.nextOffset)
            let sampleHeader = data.sampleHeader(at: instrument.sampleHeaderOffset)

            XCTAssertEqual(sampleHeader.panning, panning)
            XCTAssertEqual(sampleHeader.lengthBytes, 4)
            XCTAssertEqual(sampleHeader.loopStartBytes, 1)
            XCTAssertEqual(sampleHeader.loopLengthBytes, 2)
            XCTAssertEqual(sampleHeader.volume, 32)
            XCTAssertEqual(sampleHeader.finetune, UInt8(bitPattern: Int8(7)))
            XCTAssertEqual(sampleHeader.type, 0x02)
            XCTAssertEqual(sampleHeader.relativeNote, UInt8(bitPattern: Int8(-2)))
            XCTAssertEqual(sampleHeader.name, "Panned")
            XCTAssertEqual(Array(data.subdata(in: instrument.sampleDataOffset..<instrument.nextOffset)), [0, 64, 128, 96])
        }
    }

    func testSampleFinetuneMutationExportsAndReloadsExactSignedByteWithoutChangingNeighbors() throws {
        let sample = makeXMSourceSample(
            name: "Finetuned",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: 0.75,
            panning: 37,
            relativeNote: -2,
            finetune: 12,
            loopStart: 1,
            loopLength: 2,
            loopType: 2
        )
        let baseDocument = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, name: "Instrument", samples: [sample])]
        )

        for finetune in [-128, -37, 0, 42, 127] {
            var document = baseDocument
            XCTAssertTrue(document.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: finetune))

            let data = try EditableXMWriter().data(from: document)
            let patternHeader = data.patternHeader(at: 336)
            let instrument = data.instrumentHeader(at: patternHeader.nextOffset)
            let sampleHeader = data.sampleHeader(at: instrument.sampleHeaderOffset)

            XCTAssertEqual(sampleHeader.finetune, UInt8(bitPattern: Int8(finetune)))
            XCTAssertEqual(sampleHeader.lengthBytes, 4)
            XCTAssertEqual(sampleHeader.loopStartBytes, 1)
            XCTAssertEqual(sampleHeader.loopLengthBytes, 2)
            XCTAssertEqual(sampleHeader.volume, 48)
            XCTAssertEqual(sampleHeader.type, 0x02)
            XCTAssertEqual(sampleHeader.panning, 37)
            XCTAssertEqual(sampleHeader.relativeNote, UInt8(bitPattern: Int8(-2)))
            XCTAssertEqual(sampleHeader.name, "Finetuned")
            XCTAssertEqual(Array(data.subdata(in: instrument.sampleDataOffset..<instrument.nextOffset)), [0, 64, 128, 96])

            let url = try temporaryExportURL(filename: "finetune-\(finetune).xm")
            try data.write(to: url, options: .atomic)
            let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
            let reloadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
            let reloadedSample = try XCTUnwrap(reloadedSong.instrument(forInstrument: 1)?.sample(mappedSampleIndex: 0))

            XCTAssertEqual(reloadedSample.finetune, finetune)
            XCTAssertEqual(reloadedSample.name, "Finetuned")
            XCTAssertEqual(reloadedSample.pcm, sample.pcm)
            XCTAssertEqual(reloadedSample.xmVolume, 48)
            XCTAssertEqual(reloadedSample.panning, 37)
            XCTAssertEqual(reloadedSample.relativeNote, -2)
            XCTAssertEqual(reloadedSample.loopStart, 1)
            XCTAssertEqual(reloadedSample.loopLength, 2)
            XCTAssertEqual(reloadedSample.loopType, 2)
        }
    }

    func testSampleRelativeNoteMutationExportsAndReloadsExactSignedByteWithoutChangingNeighbors() throws {
        let sample = makeXMSourceSample(
            name: "Relative",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: 0.75,
            panning: 37,
            relativeNote: 5,
            finetune: 12,
            loopStart: 1,
            loopLength: 2,
            loopType: 2
        )
        let baseDocument = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, name: "Instrument", samples: [sample])]
        )

        for relativeNote in [-128, -37, 0, 42, 127] {
            var document = baseDocument
            XCTAssertTrue(document.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: relativeNote))

            let data = try EditableXMWriter().data(from: document)
            let patternHeader = data.patternHeader(at: 336)
            let instrument = data.instrumentHeader(at: patternHeader.nextOffset)
            let sampleHeader = data.sampleHeader(at: instrument.sampleHeaderOffset)

            XCTAssertEqual(sampleHeader.relativeNote, UInt8(bitPattern: Int8(relativeNote)))
            XCTAssertEqual(sampleHeader.lengthBytes, 4)
            XCTAssertEqual(sampleHeader.loopStartBytes, 1)
            XCTAssertEqual(sampleHeader.loopLengthBytes, 2)
            XCTAssertEqual(sampleHeader.volume, 48)
            XCTAssertEqual(sampleHeader.finetune, UInt8(bitPattern: Int8(12)))
            XCTAssertEqual(sampleHeader.type, 0x02)
            XCTAssertEqual(sampleHeader.panning, 37)
            XCTAssertEqual(sampleHeader.name, "Relative")
            XCTAssertEqual(Array(data.subdata(in: instrument.sampleDataOffset..<instrument.nextOffset)), [0, 64, 128, 96])

            let url = try temporaryExportURL(filename: "relative-note-\(relativeNote).xm")
            try data.write(to: url, options: .atomic)
            let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
            let reloadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
            let reloadedSample = try XCTUnwrap(reloadedSong.instrument(forInstrument: 1)?.sample(mappedSampleIndex: 0))

            XCTAssertEqual(reloadedSample.relativeNote, relativeNote)
            XCTAssertEqual(reloadedSample.name, "Relative")
            XCTAssertEqual(reloadedSample.pcm, sample.pcm)
            XCTAssertEqual(reloadedSample.xmVolume, 48)
            XCTAssertEqual(reloadedSample.panning, 37)
            XCTAssertEqual(reloadedSample.finetune, 12)
            XCTAssertEqual(reloadedSample.loopStart, 1)
            XCTAssertEqual(reloadedSample.loopLength, 2)
            XCTAssertEqual(reloadedSample.loopType, 2)
        }
    }

    func testDeltaEncodingHelperWritesExact8BitAnd16BitPayloads() {
        XCTAssertEqual(
            XMSampleDeltaEncoder.deltaEncodedSignedPCM(pcm: [0, 0.5, -0.5, 0.25], bitDepthBits: 8),
            Data([0, 64, 128, 96])
        )
        XCTAssertEqual(
            XMSampleDeltaEncoder.deltaEncodedSignedPCM(
                pcm: [0, Float(1.0 / 32_768.0), Float(-1.0 / 32_768.0)],
                bitDepthBits: 16
            ),
            Data([0, 0, 1, 0, 254, 255])
        )
        XCTAssertNil(XMSampleDeltaEncoder.deltaEncodedSignedPCM(pcm: [0], bitDepthBits: 24))
    }

    func testWriterThrowsForSamplePayloadWithoutSafeSourceMetadata() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Unsupported",
            pcm: [0, 0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, samples: [sample])
            ]
        )

        XCTAssertThrowsError(try EditableXMWriter().data(from: document)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedSampleSourceMetadata(
                    instrumentIndex: 1,
                    sampleIndex: 0,
                    bitDepth: nil,
                    signedPCM: nil,
                    deltaEncoded: nil
                )
            )
        }
    }

    func testWriterRejectsInvalidDimensionsPCMAndKeymapInsteadOfCanonicalizingThem() {
        let invalidChannels = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 33)]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: invalidChannels)) { error in
            XCTAssertEqual(error as? EditableXMWriterError, .unsupportedChannelCount(33))
        }

        let mismatchedChannels = makeDocument(
            orderTable: [0, 1],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 1, channels: 2),
            ]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: mismatchedChannels))

        let invalidRows = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 257, channels: 1)]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: invalidRows)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedPatternRowCount(patternIndex: 0, rowCount: 257)
            )
        }

        let invalidPCMValues: [[Float]] = [[], [.nan], [1.01]]
        for pcm in invalidPCMValues {
            let invalidPCM = makeDocument(
                orderTable: [0],
                patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
                instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [makeXMSourceSample(pcm: pcm)])]
            )
            XCTAssertThrowsError(try EditableXMWriter().data(from: invalidPCM)) { error in
                XCTAssertEqual(error as? EditableXMWriterError, .unsupportedSamplePCM(instrumentIndex: 1, sampleIndex: 0))
            }
        }

        let firstSample = makeXMSourceSample(pcm: [0])
        let secondSample = makeXMSourceSample(sampleIndex: 1, pcm: [0])
        let invalidKeymap = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [firstSample, secondSample],
                    noteSampleMap: Array(repeating: 16, count: 96)
                )
            ]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: invalidKeymap)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedNoteSampleMap(instrumentIndex: 1, entryCount: 96, sampleIndex: 16)
            )
        }
    }

    func testSparseSlotCapacityAndInvalidStateValidation() throws {
        let pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)
        let sixteenth = makeXMSourceSample(sampleIndex: 15, name: "S16", pcm: [-0.5, 0.5])
        let maximumDocument = makeDocument(
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [sixteenth],
                    noteSampleMap: Array(repeating: 15, count: 96)
                )
            ]
        )

        let maximumData = try EditableXMWriter().data(from: maximumDocument)
        let maximumInstrument = maximumData.instrumentHeader(at: maximumData.patternHeader(at: 336).nextOffset)
        XCTAssertEqual(maximumInstrument.sampleCount, 16)
        XCTAssertEqual(
            maximumData.sampleHeader(at: maximumInstrument.sampleHeaderOffset + (15 * 40)).name,
            "S16"
        )

        let outsideCapacity = makeDocument(
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makeXMSourceSample(sampleIndex: 16, pcm: [0])]
                )
            ]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: outsideCapacity)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedSampleIndexOrder(instrumentIndex: 1, sampleIndices: [16])
            )
        }

        let duplicateIndex = makeDocument(
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [
                        makeXMSourceSample(name: "First", pcm: [-0.25]),
                        makeXMSourceSample(name: "Duplicate", pcm: [0.25]),
                    ]
                )
            ]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: duplicateIndex)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedDuplicateSampleIndex(instrumentIndex: 1, sampleIndex: 0)
            )
        }

        let malformedMap = makeDocument(
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makeXMSourceSample(pcm: [0])],
                    noteSampleMap: Array(repeating: 0, count: 95)
                )
            ]
        )
        XCTAssertThrowsError(try EditableXMWriter().data(from: malformedMap)) { error in
            XCTAssertEqual(
                error as? EditableXMWriterError,
                .unsupportedNoteSampleMap(instrumentIndex: 1, entryCount: 95, sampleIndex: nil)
            )
        }
    }

    func testMultiplePatternsAndOrderReferencesPreserveAllocatedSlots() throws {
        var firstPattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 2)
        var secondPattern = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 6, channels: 2)
        firstPattern.rows[0][0] = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        secondPattern.rows[5][1] = XMPatternEventCell(note: 52, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0)
        let document = makeDocument(
            orderTable: [0, 1, 0],
            patterns: [firstPattern, secondPattern]
        )

        let data = try EditableXMWriter().data(from: document)
        let firstHeader = data.patternHeader(at: 336)
        let secondHeader = data.patternHeader(at: firstHeader.nextOffset)

        XCTAssertEqual(data.le16(at: 64), 3)
        XCTAssertEqual(data.le16(at: 70), 2)
        XCTAssertEqual(data.le16(at: 72), 2)
        XCTAssertEqual(Array(data.subdata(in: 80..<83)), [0, 1, 0])
        XCTAssertEqual(firstHeader.rowCount, 4)
        XCTAssertGreaterThan(firstHeader.packedSize, 0)
        XCTAssertEqual(secondHeader.rowCount, 6)
        XCTAssertGreaterThan(secondHeader.packedSize, 0)
        XCTAssertEqual(secondHeader.nextOffset + 58, data.count)
    }

    func testWriterDoesNotMutateEditableDocument() throws {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 2, channels: 1)
        pattern.rows[0][0] = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        let document = makeDocument(orderTable: [0], patterns: [pattern])
        let originalDocument = document

        _ = try EditableXMWriter().data(from: document)

        XCTAssertEqual(document, originalDocument)
    }

    func testWriterSurfaceAcceptsEditableDocumentModelOnly() throws {
        let data = try EditableXMWriter().data(from: BlankTrackerDocument.makeDefault())

        XCTAssertFalse(data.isEmpty)
    }

    func testBlankDocumentReloadsThroughParserFromTemporaryXMFile() throws {
        let metadata = try reloadedMetadata(from: BlankTrackerDocument.makeDefault())

        XCTAssertEqual(metadata.type, "XM")
        XCTAssertEqual(metadata.title, BlankTrackerDocument.defaultTitle)
        XCTAssertEqual(metadata.version, "1.4")
        XCTAssertEqual(metadata.songLength, 1)
        XCTAssertEqual(metadata.orderTable, [0])
        XCTAssertEqual(metadata.restartPosition, 0)
        XCTAssertEqual(metadata.channels, 8)
        XCTAssertEqual(metadata.patterns, 1)
        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(metadata.defaultTempo, 6)
        XCTAssertEqual(metadata.defaultBPM, 125)
        XCTAssertEqual(metadata.xmFlags, 0x0001)
        XCTAssertTrue(metadata.usesLinearFrequencyTable)

        let pattern = try XCTUnwrap(metadata.xmPattern(index: 0))
        XCTAssertEqual(pattern.rowCount, 64)
        XCTAssertEqual(pattern.channels, 8)
        XCTAssertTrue(pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testZeroSampleInstrumentsExportAndReloadWithNamesOrderAndNoPayload() throws {
        var document = BlankTrackerDocument.makeDefault()
        let patternsBefore = document.patterns
        let ordersBefore = document.orderTable
        XCTAssertEqual(document.addEmptyInstrument(), 2)
        XCTAssertTrue(document.renameInstrument(at: 1, name: "Second Empty"))

        let url = try temporaryExportURL(filename: "zero-sample-instruments.xm")
        try EditableXMWriter().data(from: document).write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)

        XCTAssertEqual(metadata.instruments, 2)
        XCTAssertEqual(metadata.orderTable, ordersBefore)
        XCTAssertEqual(metadata.xmPatterns, patternsBefore)
        XCTAssertEqual(song.instrumentsByIndex.keys.sorted(), [1, 2])
        XCTAssertNil(song.instrumentsByIndex[1]?.name)
        XCTAssertEqual(song.instrumentsByIndex[2]?.name, "Second Empty")
        XCTAssertEqual(song.instrumentsByIndex[1]?.samples, [])
        XCTAssertEqual(song.instrumentsByIndex[2]?.samples, [])
        XCTAssertNil(song.instrumentsByIndex[1]?.noteSampleMap)
        XCTAssertNil(song.instrumentsByIndex[2]?.noteSampleMap)
    }

    func testRepresentedSamplesWithoutMapExportAsAllS01AndReopenWithExplicitMap() throws {
        let first = makeXMSourceSample(sampleIndex: 0, name: "Content A", pcm: [-0.25, 0.25])
        let second = makeXMSourceSample(sampleIndex: 1, name: "Content B", pcm: [-0.75, 0.75])
        let sourceInstrument = PlaybackInstrument(index: 1, samples: [first, second], noteSampleMap: nil)
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [1: sourceInstrument]
        )

        XCTAssertNil(sourceInstrument.noteSampleMap)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 49,
            instrument: sourceInstrument,
            missingKeymapPolicy: .firstPlayableSample
        )?.sample, first)

        let data = try EditableXMWriter().data(from: document)
        let instrumentOffset = data.patternHeader(at: 336).nextOffset
        XCTAssertEqual(
            Array(data[instrumentOffset + 33..<instrumentOffset + 129]),
            Array(repeating: UInt8(0), count: 96)
        )
        let url = try temporaryExportURL(filename: "represented-nil-map.xm")
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(song.instrument(forInstrument: 1))

        XCTAssertEqual(reopened.samples, [first, second])
        XCTAssertEqual(reopened.noteSampleMap, Array(repeating: 0, count: 96))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 49,
            instrument: reopened
        )?.sample, first)
        XCTAssertNotEqual(reopened, sourceInstrument, "writer acceptance is not value-preserving for state D")
    }

    func testSimpleNoteAndInstrumentReloadThroughParser() throws {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 8, channels: 2)
        pattern.rows[2][1] = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        let document = makeDocument(orderTable: [0], patterns: [pattern])

        let metadata = try reloadedMetadata(from: document)

        XCTAssertEqual(metadata.instruments, 1)
        let reloadedPattern = try XCTUnwrap(metadata.xmPattern(index: 0))
        XCTAssertEqual(reloadedPattern.rowCount, 8)
        XCTAssertEqual(reloadedPattern.channels, 2)
        XCTAssertEqual(reloadedPattern.rows[2][1], XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0))
        XCTAssertEqual(reloadedPattern.rows[0][0], .empty)
    }

    func testKeyOffReloadsThroughParser() throws {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)
        pattern.rows[1][0] = XMPatternEventCell(
            note: XMPatternEventCell.keyOffNoteValue,
            instrument: 0,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        let document = makeDocument(orderTable: [0], patterns: [pattern])

        let metadata = try reloadedMetadata(from: document)

        let reloadedPattern = try XCTUnwrap(metadata.xmPattern(index: 0))
        XCTAssertEqual(reloadedPattern.rows[1][0].note, XMPatternEventCell.keyOffNoteValue)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(reloadedPattern.rows[1][0]), "=== .. .. ...")
    }

    func testMultiplePatternsAndOrderReferencesReloadThroughParser() throws {
        var firstPattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 2)
        var secondPattern = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 6, channels: 2)
        firstPattern.rows[0][0] = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        secondPattern.rows[5][1] = XMPatternEventCell(note: 52, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0)
        let document = makeDocument(
            restartPosition: 1,
            orderTable: [0, 1, 0],
            patterns: [firstPattern, secondPattern]
        )

        let metadata = try reloadedMetadata(from: document)

        XCTAssertEqual(metadata.songLength, 3)
        XCTAssertEqual(metadata.orderTable, [0, 1, 0])
        XCTAssertEqual(metadata.restartPosition, 1)
        XCTAssertEqual(metadata.patterns, 2)
        XCTAssertEqual(metadata.instruments, 2)

        let reloadedFirst = try XCTUnwrap(metadata.xmPattern(index: 0))
        let reloadedSecond = try XCTUnwrap(metadata.xmPattern(index: 1))
        XCTAssertEqual(reloadedFirst.rowCount, 4)
        XCTAssertEqual(reloadedSecond.rowCount, 6)
        XCTAssertEqual(reloadedFirst.rows[0][0], XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0))
        XCTAssertEqual(reloadedFirst.rows[3][1], .empty)
        XCTAssertEqual(reloadedSecond.rows[5][1], XMPatternEventCell(note: 52, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0))
        XCTAssertEqual(reloadedSecond.rows[0][0], .empty)
    }

    func testVolumeAndEffectCellReloadThroughParser() throws {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 2, channels: 1)
        pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let document = makeDocument(orderTable: [0], patterns: [pattern])

        let metadata = try reloadedMetadata(from: document)

        let reloadedPattern = try XCTUnwrap(metadata.xmPattern(index: 0))
        XCTAssertEqual(
            reloadedPattern.rows[0][0],
            XMPatternEventCell(
                note: 49,
                instrument: 1,
                volumeColumn: 0x40,
                effectType: 0x0F,
                effectParam: 0x7D
            )
        )
    }

    func testSampleBearingEditableCopyExportsAndReloadsWithPayload() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        var document = try XCTUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.renameInstrument(at: 0, name: "Renamed Public"))

        let exportedURL = try temporaryExportURL(filename: "exported-sample.xm")
        let data = try EditableXMWriter().data(from: document)
        try data.write(to: exportedURL, options: .atomic)

        let exportedMetadata = try ModuleMetadataLoader().load(fromPath: exportedURL.path)
        let exportedSong = try PlaybackSongBuilder.build(from: exportedMetadata, modulePath: exportedURL.path)

        XCTAssertEqual(exportedMetadata.type, "XM")
        XCTAssertEqual(exportedMetadata.instruments, 1)
        XCTAssertEqual(exportedMetadata.orderTable, [0])
        let reloadedPattern = try XCTUnwrap(exportedMetadata.xmPattern(index: 0))
        XCTAssertEqual(reloadedPattern.rows[0][0].note, 49)
        XCTAssertEqual(reloadedPattern.rows[0][0].instrument, 1)
        let instrument = try XCTUnwrap(exportedSong.instrument(forInstrument: 1))
        XCTAssertEqual(instrument.name, "Renamed Public")
        let sample = try XCTUnwrap(instrument.sample(mappedSampleIndex: 0))
        XCTAssertEqual(sample.name, "SINE64")
        XCTAssertEqual(sample.sampleLength, 64)
        XCTAssertEqual(sample.pcm.count, 64)
        XCTAssertFalse(sample.pcm.isEmpty)
        XCTAssertEqual(sample.sourceBitDepthBits, 8)
        XCTAssertEqual(sample.sourceIsSignedPCM, true)
        XCTAssertEqual(sample.sourceIsDeltaEncoded, true)
    }

    func testGeneratedSineExportsAndReopensWithExactSampleAndAllNoteMap() throws {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.generateSineInSelectedEmptySample())
        let generated = try XCTUnwrap(document.instrumentPalette[1]?.samples.first)
        let url = try temporaryExportURL(filename: "generated-sine.xm")
        try EditableXMWriter().data(from: document).write(to: url, options: .atomic)

        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let instrument = try XCTUnwrap(song.instrument(forInstrument: 1))
        let reopened = try XCTUnwrap(instrument.sample(mappedSampleIndex: 0))

        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(instrument.name, document.instrumentPalette[1]?.name)
        XCTAssertEqual(instrument.samples.count, 1)
        XCTAssertEqual(instrument.availableSampleSlots, [1])
        XCTAssertEqual(instrument.noteSampleMap, Array(repeating: 0, count: 96))
        XCTAssertEqual(reopened, generated)
        XCTAssertEqual(reopened.sampleLength, 16_384)
        XCTAssertEqual([UInt8(1), 49, 96].map(instrument.mappedSampleIndex(forNote:)), [0, 0, 0])
    }

    func testImportedWAVCandidateExportsAndReopensWithCanonicalMetadataPCMAndMap() throws {
        var document = BlankTrackerDocument.makeDefault()
        let candidate = try normalizedImportCandidate(
            name: "Imported Kick.wav", pcm: [-1, -0.5, 0, 0.5, Float(Int16.max) / 32_768]
        )
        let destination = try XCTUnwrap(document.selectedSampleImportDestination)
        XCTAssertTrue(document.importAudioSample(candidate, destination: destination))
        let imported = try XCTUnwrap(document.instrumentPalette[1]?.samples.first)
        let url = try temporaryExportURL(filename: "imported-wav.xm")
        try EditableXMWriter().data(from: document).write(to: url, options: .atomic)

        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let instrument = try XCTUnwrap(song.instrument(forInstrument: 1))
        let reopened = try XCTUnwrap(instrument.sample(mappedSampleIndex: 0))

        XCTAssertEqual(reopened, imported)
        XCTAssertEqual(reopened.name, "Imported Kick")
        XCTAssertEqual(reopened.sourceBitDepthBits, 16)
        XCTAssertEqual(reopened.xmVolume, 64)
        XCTAssertEqual(reopened.panning, 128)
        XCTAssertEqual(reopened.loopType, 0)
        XCTAssertEqual(instrument.noteSampleMap, Array(repeating: 0, count: 96))
    }

    func testAppendedImportedSampleExportsAndReopensInOrderWithoutChangingKeymap() throws {
        var document = BlankTrackerDocument.makeDefault()
        let firstCandidate = try normalizedImportCandidate(
            name: "First.wav", pcm: [-1, -0.25, 0.25, Float(Int16.max) / 32_768]
        )
        XCTAssertTrue(document.importAudioSample(firstCandidate, destination: try XCTUnwrap(document.selectedSampleImportDestination)))
        let first = try XCTUnwrap(document.instrumentPalette[1]?.samples.first)
        let map = try XCTUnwrap(document.instrumentPalette[1]?.noteSampleMap)
        let secondCandidate = try normalizedImportCandidate(name: "Second.wav", pcm: [-0.75, 0, 0.75], sampleRate: 44_100)
        let second = secondCandidate.playbackSample(instrumentIndex: 1, sampleIndex: 1)
        XCTAssertEqual(document.appendSample(instrumentIndex: 1, sample: second), 1)

        let url = try temporaryExportURL(filename: "appended-import.xm")
        try EditableXMWriter().data(from: document).write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(song.instrument(forInstrument: 1))

        XCTAssertEqual(reopened.samples, [first, second])
        XCTAssertEqual(reopened.samples.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(reopened.noteSampleMap, map)
        XCTAssertEqual(reopened.noteSampleMap, Array(repeating: 0, count: 96))
        XCTAssertEqual([UInt8(1), 49, 96].map(reopened.mappedSampleIndex(forNote:)), [0, 0, 0])
    }

    func testSparseInteriorGapWritesCanonicalPlaceholderAndReopensExactIdentityAndMap() throws {
        let first = makeXMSourceSample(
            sampleIndex: 0, name: "Distinct S01", pcm: [-0.25, 0.25],
            volume: 0.5, panning: 37, relativeNote: -2, finetune: 7
        )
        let third = makeXMSourceSample(
            sampleIndex: 2, name: "Distinct S03", pcm: [-0.75, 0.75],
            volume: 0.75, panning: 201, relativeNote: 3, finetune: -8,
            sourceBitDepthBits: 16
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[1] = 1
        noteSampleMap[2] = 2
        noteSampleMap[95] = 1
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    name: "Sparse Instrument",
                    samples: [third, first],
                    noteSampleMap: noteSampleMap
                )
            ]
        )
        let data = try EditableXMWriter().data(from: document)
        XCTAssertEqual(try EditableXMWriter().data(from: document), data)
        let instrumentOffset = data.patternHeader(at: 336).nextOffset
        let instrumentHeader = data.instrumentHeader(at: instrumentOffset)
        XCTAssertEqual(instrumentHeader.sampleCount, 3)
        XCTAssertEqual(
            Array(data[instrumentOffset + 33..<instrumentOffset + 129]),
            noteSampleMap.map { UInt8($0) }
        )
        let placeholderOffset = instrumentHeader.sampleHeaderOffset + 40
        XCTAssertEqual(Array(data[placeholderOffset..<placeholderOffset + 40]), Array(repeating: 0, count: 40))
        XCTAssertEqual(data.sampleHeader(at: instrumentHeader.sampleHeaderOffset).name, "Distinct S01")
        XCTAssertEqual(data.sampleHeader(at: instrumentHeader.sampleHeaderOffset + 80).name, "Distinct S03")
        var expectedPayload = try XCTUnwrap(XMSampleDeltaEncoder.deltaEncodedSignedPCM(
            pcm: first.pcm, bitDepthBits: 8
        ))
        expectedPayload.append(try XCTUnwrap(XMSampleDeltaEncoder.deltaEncodedSignedPCM(
            pcm: third.pcm, bitDepthBits: 16
        )))
        XCTAssertEqual(data[instrumentHeader.sampleDataOffset..<instrumentHeader.nextOffset], expectedPayload)

        let url = try temporaryExportURL(filename: "sparse-interior-gap.xm")
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(song.instrument(forInstrument: 1))

        XCTAssertEqual(reopened.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(reopened.availableSampleSlots, [1, 3])
        XCTAssertEqual(reopened.sample(mappedSampleIndex: 0), first)
        XCTAssertNil(reopened.sample(mappedSampleIndex: 1))
        XCTAssertEqual(reopened.sample(mappedSampleIndex: 2), third)
        XCTAssertEqual(reopened.noteSampleMap, noteSampleMap)
        XCTAssertEqual(reopened.firstPlayableSample?.sampleIndex, 0)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 1, instrumentsByIndex: song.instrumentsByIndex
        )?.sampleIndex, 0)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 2, instrumentsByIndex: song.instrumentsByIndex
        ))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 3, instrumentsByIndex: song.instrumentsByIndex
        )?.sampleIndex, 2)
    }

    func testTrailingReferencedEmptySlotWritesEnoughSpanAndReopensUnavailable() throws {
        let first = makeXMSourceSample(name: "Only S01", pcm: [-0.5, 0.5])
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, samples: [first], noteSampleMap: noteSampleMap)
            ]
        )

        let data = try EditableXMWriter().data(from: document)
        let instrument = data.instrumentHeader(at: data.patternHeader(at: 336).nextOffset)
        XCTAssertEqual(instrument.sampleCount, 2)
        XCTAssertEqual(
            Array(data[instrument.sampleHeaderOffset + 40..<instrument.sampleHeaderOffset + 80]),
            Array(repeating: 0, count: 40)
        )
        let url = try temporaryExportURL(filename: "trailing-empty-reference.xm")
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(song.instrument(forInstrument: 1))

        XCTAssertEqual(reopened.samples, [first])
        XCTAssertEqual(reopened.noteSampleMap, noteSampleMap)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrumentsByIndex: song.instrumentsByIndex
        ))
    }

    func testKeymapRequiredTrailingEmptyDestinationPopulatesAndReopensInPlace() throws {
        let first = makeXMSourceSample(name: "Only S01", pcm: [-0.5, 0.5])
        var map = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
        map[48] = 1
        var document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, samples: [first], noteSampleMap: map)
            ]
        )
        document.selectSample(2)
        let destination = try XCTUnwrap(document.selectedSampleImportDestination)

        XCTAssertEqual(destination, .emptyDestination(instrumentIndex: 1, sampleIndex: 1))
        XCTAssertTrue(document.importAudioSample(
            try normalizedImportCandidate(name: "Trailing.wav", pcm: [-0.625, 0.625]),
            destination: destination
        ))
        let populated = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(populated.samples.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(populated.noteSampleMap, map)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))

        let url = try temporaryExportURL(filename: "populated-trailing-reference.xm")
        try EditableXMWriter().data(from: document).write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(song.instrument(forInstrument: 1))
        XCTAssertEqual(reopened, populated)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrumentsByIndex: song.instrumentsByIndex
        )?.sampleIndex, 1)
    }

    func testOnlyEmptyMappedSlotPreservesInstrumentMetadataMapAndUnavailableRoute() throws {
        let volumeEnvelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [.init(tick: 0, value: 64), .init(tick: 8, value: 32)],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 0,
            typeFlags: 0x03,
            fadeout: 1_234
        )
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [.init(tick: 0, value: 32), .init(tick: 8, value: 48)],
            sustainPointIndex: 0,
            loopStartPointIndex: 0,
            loopEndPointIndex: 1,
            typeFlags: 0x05
        )
        let autoVibrato = PlaybackInstrumentAutoVibrato(waveformType: 2, sweep: 3, depth: 4, rate: 5)
        let noteSampleMap = Array(repeating: 0, count: 96)
        let document = makeDocument(
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    name: "Mapped Empty S01",
                    samples: [],
                    volumeEnvelope: volumeEnvelope,
                    panningEnvelope: panningEnvelope,
                    autoVibrato: autoVibrato,
                    noteSampleMap: noteSampleMap
                )
            ]
        )

        let data = try EditableXMWriter().data(from: document)
        let instrumentHeader = data.instrumentHeader(at: data.patternHeader(at: 336).nextOffset)
        XCTAssertEqual(instrumentHeader.sampleCount, 1)
        XCTAssertEqual(
            Array(data[instrumentHeader.sampleHeaderOffset..<instrumentHeader.sampleHeaderOffset + 40]),
            Array(repeating: 0, count: 40)
        )
        let url = try temporaryExportURL(filename: "only-empty-mapped-slot.xm")
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(song.instrument(forInstrument: 1))

        XCTAssertEqual(reopened.name, "Mapped Empty S01")
        XCTAssertEqual(reopened.samples, [])
        XCTAssertEqual(reopened.noteSampleMap, noteSampleMap)
        XCTAssertEqual(reopened.volumeEnvelope, volumeEnvelope)
        XCTAssertEqual(reopened.panningEnvelope, panningEnvelope)
        XCTAssertEqual(reopened.autoVibrato, autoVibrato)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrumentsByIndex: song.instrumentsByIndex
        ))
    }

    func testDenseAlpha1OutputRemainsByteIdentical() throws {
        let first = makeXMSourceSample(name: "Dense S01", pcm: [-0.5, 0, 0.5])
        let second = makeXMSourceSample(
            sampleIndex: 1, name: "Dense S02", pcm: [-0.75, 0.75],
            volume: 0.5, panning: 37, relativeNote: -3, finetune: 9,
            sourceBitDepthBits: 16
        )
        let document = makeDocument(
            title: "Dense Alpha1",
            orderTable: [0],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 1, channels: 1)],
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    name: "Dense Instrument",
                    samples: [first, second],
                    noteSampleMap: Array(repeating: 0, count: 48) + Array(repeating: 1, count: 48)
                )
            ]
        )

        let data = try EditableXMWriter().data(from: document)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "58d8331aed9eba43bba349993eedf9ef440ac8c9e19ed2874d1e724d01819431")
    }

    func testEditedKeymapRangesExportReopenAndEditableCopyExactlyWithoutChangingSamples() throws {
        var document = BlankTrackerDocument.makeDefault()
        let firstCandidate = try normalizedImportCandidate(name: "First.wav", pcm: [-1, -0.25, 0.25])
        XCTAssertTrue(document.importAudioSample(
            firstCandidate, destination: try XCTUnwrap(document.selectedSampleImportDestination)
        ))
        let secondCandidate = try normalizedImportCandidate(name: "Second.wav", pcm: [-0.75, 0, 0.75])
        XCTAssertEqual(document.appendSample(
            instrumentIndex: 1, sample: secondCandidate.playbackSample(instrumentIndex: 1, sampleIndex: 1)
        ), 1)
        let samplesBefore = try XCTUnwrap(document.instrumentPalette[1]?.samples)
        _ = try document.assignSample(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 12, upperNote: 23
        ).get()
        _ = try document.assignSample(
            instrumentIndex: 0, sampleIndex: 1, lowerNote: 60, upperNote: 71
        ).get()
        let expectedMap = try XCTUnwrap(document.instrumentPalette[1]?.noteSampleMap)

        let url = try temporaryExportURL(filename: "edited-keymap-ranges.xm")
        try EditableXMWriter().data(from: document).write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        let reopened = try XCTUnwrap(reopenedSong.instrument(forInstrument: 1))
        let editableCopy = try XCTUnwrap(BlankTrackerDocument.makeEditableCopy(
            from: metadata, playbackSong: reopenedSong, selection: .default
        ))

        XCTAssertEqual(expectedMap.count, TrackerNoteKeyMap.maximumNoteValue)
        XCTAssertEqual(reopened.noteSampleMap, expectedMap)
        XCTAssertEqual(editableCopy.instrumentPalette[1]?.noteSampleMap, expectedMap)
        XCTAssertEqual(reopened.samples, samplesBefore)
        XCTAssertEqual(editableCopy.instrumentPalette[1]?.samples, samplesBefore)
        XCTAssertEqual(Array(expectedMap[12...23]), Array(repeating: 1, count: 12))
        XCTAssertEqual(Array(expectedMap[60...71]), Array(repeating: 1, count: 12))
        XCTAssertEqual([11, 24, 59, 72].map { expectedMap[$0] }, [0, 0, 0, 0])
        XCTAssertEqual([UInt8(72), 73].map(reopened.mappedSampleIndex(forNote:)), [1, 0])
    }

    @MainActor
    func testFromScratchCompositionWorkflowCreatesMapsArrangesPlaysAndRoundTrips() throws {
        var document = BlankTrackerDocument.makeDefault()
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: { document = $0 }
        )
        let pulse = try normalizedImportCandidate(
            name: "Pulse.wav",
            pcm: (0..<64).map { $0.isMultiple(of: 2) ? -0.75 : 0.75 }
        )
        let percussion = try normalizedImportCandidate(
            name: "Percussion.wav",
            pcm: (0..<64).map { $0 == 0 ? 1 : Float(64 - $0) / -128 }
        )
        let secondInstrumentSample = try normalizedImportCandidate(
            name: "Second Instrument.wav",
            pcm: (0..<64).map { Float(($0 % 8) - 4) / 8 }
        )

        XCTAssertTrue(coordinator.importAudioSample(
            pulse,
            destination: try XCTUnwrap(document.selectedSampleImportDestination)
        ))
        XCTAssertTrue(coordinator.addAudioSample(
            percussion,
            instrumentIndex: 1,
            originalSampleCount: 1
        ))
        let beforeMap = document
        let mapOutcome = try coordinator.mapSampleToNoteRange(
            instrumentIndex: 0,
            sampleIndex: 1,
            lowerNote: 60,
            upperNote: 71
        ).get()
        XCTAssertEqual(mapOutcome.changedNoteCount, 12)
        XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap?[59], 0) // B-4
        XCTAssertEqual(Array(try XCTUnwrap(document.instrumentPalette[1]?.noteSampleMap)[60...71]), Array(repeating: 1, count: 12))
        XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap?[72], 0) // C-6
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(document, beforeMap)
        XCTAssertTrue(coordinator.redo())

        XCTAssertTrue(coordinator.createInstrument())
        let withEmptyI02 = document
        XCTAssertEqual(withEmptyI02.instrumentPalette.keys.sorted(), [1, 2])
        XCTAssertEqual(withEmptyI02.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(withEmptyI02.instrumentPalette[2]?.samples, [])
        XCTAssertTrue(coordinator.undo())
        XCTAssertNil(document.instrumentPalette[2])
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(document, withEmptyI02)
        XCTAssertTrue(coordinator.importAudioSample(
            secondInstrumentSample,
            destination: try XCTUnwrap(document.selectedSampleImportDestination)
        ))
        XCTAssertTrue(coordinator.renameInstrument(at: 1, name: "Second Instrument"))

        var arranged = document
        XCTAssertTrue(arranged.createBlankPatternAndSelectForEditing())
        XCTAssertTrue(coordinator.applyEdit(label: "New Pattern", updatedDocument: arranged))
        arranged = document
        XCTAssertTrue(arranged.insertOrderAfterSelected())
        XCTAssertTrue(coordinator.applyEdit(label: "Insert Order", updatedDocument: arranged))
        arranged = document
        XCTAssertTrue(arranged.assignPatternToSelectedOrder(1))
        XCTAssertTrue(coordinator.applyEdit(label: "Assign Pattern", updatedDocument: arranged))

        func enter(
            _ key: Character,
            octave: Int,
            row: Int,
            channel: Int,
            pattern: Int,
            instrument: Int
        ) {
            document.selectInstrument(instrument)
            var updated = document
            XCTAssertTrue(updated.enterNote(
                trackerKey: key,
                octave: octave,
                row: row,
                channel: channel,
                patternIndex: pattern
            ))
            XCTAssertTrue(coordinator.applyEdit(label: "Enter Note", updatedDocument: updated))
        }

        enter("m", octave: 4, row: 0, channel: 0, pattern: 0, instrument: 1) // B-4, S01
        enter("q", octave: 4, row: 1, channel: 0, pattern: 0, instrument: 1) // C-5, S02
        enter("u", octave: 4, row: 2, channel: 0, pattern: 0, instrument: 1) // B-5, S02
        enter("q", octave: 5, row: 3, channel: 0, pattern: 0, instrument: 1) // C-6, S01
        enter("z", octave: 4, row: 0, channel: 1, pattern: 1, instrument: 2)

        XCTAssertEqual(document.orderTable, [0, 1])
        XCTAssertEqual(document.patterns.map(\.index), [0, 1])
        XCTAssertEqual(document.pattern(for: 0)?.rows[0...3].map { $0[0].instrument }, [1, 1, 1, 1])
        XCTAssertEqual(document.pattern(for: 1)?.rows[0][1].instrument, 2)

        let song = EditablePlaybackSongBuilder.build(from: document)
        let runtimePlan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 8_363)
        let routedSamples = runtimePlan.events.compactMap { event -> String? in
            guard case let .noteTrigger(_, _, mapping) = event.action else { return nil }
            return "\(mapping.instrumentIndex):\(mapping.sampleIndex)"
        }
        XCTAssertTrue(runtimePlan.generated)
        XCTAssertEqual(routedSamples, ["1:0", "1:1", "1:1", "1:0", "2:0"])

        let firstExport = try EditableXMWriter().data(from: document)
        XCTAssertEqual(try EditableXMWriter().data(from: document), firstExport)
        let xmURL = try temporaryExportURL(filename: "from-scratch-workflow.xm")
        try firstExport.write(to: xmURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: xmURL.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: xmURL.path)
        XCTAssertEqual(metadata.orderTable, [0, 1])
        XCTAssertEqual(metadata.xmPatterns, document.patterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, document.instrumentPalette)
        let reopenedPlan = RuntimeCMixerAdapterEventPlan.make(song: reopenedSong, sampleRate: 8_363)
        XCTAssertEqual(reopenedPlan.events.compactMap { event -> String? in
            guard case let .noteTrigger(_, _, mapping) = event.action else { return nil }
            return "\(mapping.instrumentIndex):\(mapping.sampleIndex)"
        }, routedSamples)
    }

    @MainActor
    func testCompositionReleaseGateRoundTripsSupportedStateAndRendersReopenedXM() throws {
        var document = makeCompositionReleaseGateDocument()
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: { document = $0 }
        )
        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 73))
        let exportState = document
        XCTAssertTrue(coordinator.undo())
        XCTAssertTrue(coordinator.redo())
        XCTAssertEqual(document, exportState)
        let plannedSampleIdentities = [1, 2].map { selectedSample -> [String] in
            var snapshot = document
            snapshot.selectSample(selectedSample)
            return PlaybackSongSyntheticAdapter.adapt(
                EditablePlaybackSongBuilder.build(from: snapshot), orderIndex: 0, sampleRate: 8_363
            ).diagnostics.eventMappings.map { "\($0.instrumentIndex):\($0.sampleIndex)" }
        }
        XCTAssertEqual(plannedSampleIdentities, [
            ["1:0", "1:1", "1:1", "1:0"],
            ["1:0", "1:1", "1:1", "1:0"],
        ])

        let firstExport = try EditableXMWriter().data(from: document)
        XCTAssertEqual(try EditableXMWriter().data(from: document), firstExport)
        XCTAssertEqual(firstExport.ascii(offset: 0, length: 17), "Extended Module: ")
        XCTAssertEqual(firstExport.le16(at: 58), 0x0104)
        XCTAssertEqual(firstExport.le32(at: 60), 276)
        let firstPattern = firstExport.patternHeader(at: 336)
        let secondPattern = firstExport.patternHeader(at: firstPattern.nextOffset)
        let firstInstrument = firstExport.instrumentHeader(at: secondPattern.nextOffset)
        let secondInstrument = firstExport.instrumentHeader(at: firstInstrument.nextOffset)
        XCTAssertGreaterThan(firstPattern.packedSize, 0)
        XCTAssertGreaterThan(secondPattern.packedSize, 0)
        XCTAssertEqual(firstInstrument.sampleCount, 2)
        XCTAssertEqual(secondInstrument.sampleCount, 1)
        XCTAssertEqual(secondInstrument.nextOffset, firstExport.count)
        let privatePathPrefix = Data(["/", "Users"].joined().utf8)
        XCTAssertNil(firstExport.range(of: privatePathPrefix))

        let xmURL = try temporaryExportURL(filename: "composition-release-gate.xm")
        try firstExport.write(to: xmURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: xmURL.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: xmURL.path)
        XCTAssertEqual(metadata.title, document.title)
        XCTAssertEqual(metadata.orderTable, document.orderTable)
        XCTAssertEqual(metadata.restartPosition, document.restartPosition)
        XCTAssertEqual(metadata.channels, document.pattern.channels)
        XCTAssertEqual(metadata.xmPatterns, document.patterns)
        XCTAssertEqual(metadata.instruments, 2)
        XCTAssertEqual(metadata.xmFlags, 0x0001)
        XCTAssertEqual(metadata.defaultTempo, document.speed)
        XCTAssertEqual(metadata.defaultBPM, document.tempo)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, document.instrumentPalette)

        let reopenedContext = WAVExportDocumentContext.loadedReadOnly(
            playbackSong: reopenedSong,
            displayName: metadata.title,
            isPlaybackActive: false
        )
        let wavURL = xmURL.deletingLastPathComponent().appendingPathComponent("reopened.wav")
        guard case let .exported(_, wavRender) = WAVExportCoordinator.export(
            plan: try WAVExportCoordinator.makePlan(context: reopenedContext),
            to: wavURL
        ) else { return XCTFail("Expected WAV export from reopened XM") }
        XCTAssertGreaterThan(wavRender.exportDiagnostics?.preExportPeak ?? 0, 0)

        let m4aURL = xmURL.deletingLastPathComponent().appendingPathComponent("reopened.m4a")
        guard case let .exported(_, m4aRender, _) = M4AExportCoordinator.export(
            plan: try M4AExportCoordinator.makePlan(context: reopenedContext),
            to: m4aURL
        ) else { return XCTFail("Expected M4A export from reopened XM") }
        XCTAssertGreaterThan(m4aRender.exportDiagnostics?.preExportPeak ?? 0, 0)
        XCTAssertGreaterThan(try Data(contentsOf: m4aURL).count, 0)
    }

    @MainActor
    func testSampleLifecycleMilestoneGateComposesActionsAndRoundTripsSupportedState() throws {
        var document = try makeSampleLifecycleGateDocument()
        let initial = document
        let originalMap = try XCTUnwrap(document.instrumentPalette[1]?.noteSampleMap)
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: document, isPlaybackActive: false) },
            documentApplyHandler: { document = $0 }
        )

        func routedNames(in snapshot: BlankTrackerDocument) -> [String?] {
            [UInt8(1), 33, 65].map {
                PlaybackInstrumentSampleResolver.resolveSample(
                    instrumentIndex: 1, note: $0, instrumentsByIndex: snapshot.instrumentPalette
                )?.sample.name
            }
        }

        func exactRegionMap(_ low: Int, _ middle: Int, _ high: Int) -> [Int] {
            Array(repeating: low, count: 32)
                + Array(repeating: middle, count: 32)
                + Array(repeating: high, count: 32)
        }

        func assertUndoRedo(
            from before: BlankTrackerDocument,
            to after: BlankTrackerDocument,
            _ operation: String
        ) {
            XCTAssertTrue(coordinator.undo(), operation)
            XCTAssertEqual(document, before, operation)
            XCTAssertTrue(coordinator.redo(), operation)
            XCTAssertEqual(document, after, operation)
        }

        XCTAssertEqual(originalMap, exactRegionMap(0, 1, 2))
        XCTAssertEqual(routedNames(in: initial), ["Low Pulse", "High Ramp", "Impulse"])
        XCTAssertTrue(coordinator.clearSample(instrumentAt: 0, sampleAt: 1))
        let cleared = document
        XCTAssertEqual(cleared.instrumentPalette[1]?.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(cleared.instrumentPalette[1]?.noteSampleMap, originalMap)
        XCTAssertEqual(routedNames(in: cleared), ["Low Pulse", nil, "Impulse"])
        XCTAssertEqual(cleared.patterns, initial.patterns)
        assertUndoRedo(from: initial, to: cleared, "Clear")

        document.selectSample(2)
        let beforePopulate = document
        let destination = try XCTUnwrap(document.selectedSampleImportDestination)
        XCTAssertEqual(destination, .emptyDestination(instrumentIndex: 1, sampleIndex: 1))
        XCTAssertTrue(coordinator.importAudioSample(
            try normalizedImportCandidate(name: "Replacement.wav", pcm: [-0.625, 0, 0.625]),
            destination: destination
        ))
        let populated = document
        XCTAssertEqual(populated.instrumentPalette[1]?.samples.map(\.sampleIndex), [0, 1, 2])
        XCTAssertEqual(populated.instrumentPalette[1]?.noteSampleMap, originalMap)
        XCTAssertEqual(routedNames(in: populated), ["Low Pulse", "Replacement", "Impulse"])
        XCTAssertEqual(populated.patterns, initial.patterns)
        assertUndoRedo(from: beforePopulate, to: populated, "Populate")

        document.selectSample(1)
        let beforeDuplicate = document
        let duplicateSource = try XCTUnwrap(document.instrumentPalette[1]?.sample(mappedSampleIndex: 0))
        XCTAssertTrue(coordinator.duplicateSample(instrumentAt: 0, sampleAt: 0))
        let duplicated = document
        let duplicate = try XCTUnwrap(duplicated.instrumentPalette[1]?.sample(mappedSampleIndex: 3))
        XCTAssertEqual(duplicated.instrumentPalette[1]?.samples.map(\.sampleIndex), [0, 1, 2, 3])
        XCTAssertEqual(duplicate.reidentified(sampleIndex: 0), duplicateSource)
        XCTAssertEqual(duplicated.instrumentPalette[1]?.noteSampleMap, originalMap)
        XCTAssertEqual(routedNames(in: duplicated), routedNames(in: beforeDuplicate))
        assertUndoRedo(from: beforeDuplicate, to: duplicated, "Duplicate")

        let routingBeforeSelection = routedNames(in: document)
        document.selectSample(1)
        XCTAssertEqual(routedNames(in: document), routingBeforeSelection)
        document.selectSample(4)
        XCTAssertEqual(routedNames(in: document), routingBeforeSelection)
        let directRequest = SampleEditorAuditionRequestFactory.request(
            selection: document.selection, sourceContext: .blankDocument
        )
        guard case let .potentiallyAvailable(directSample) = document.noteAuditionAvailability(for: directRequest)
        else { return XCTFail("duplicated sample should remain directly auditionable") }
        XCTAssertEqual(directSample.sampleIndex, 3)

        let beforeDenseMove = document
        XCTAssertTrue(coordinator.applySampleSlotPermutation(
            try .move(from: 3, to: 0), instrumentAt: 0
        ))
        let denseMoved = document
        XCTAssertEqual(denseMoved.selection.selectedSample, 1)
        XCTAssertEqual(denseMoved.instrumentPalette[1]?.noteSampleMap, exactRegionMap(1, 2, 3))
        XCTAssertEqual(routedNames(in: denseMoved), routingBeforeSelection)
        XCTAssertEqual(denseMoved.patterns, initial.patterns)
        assertUndoRedo(from: beforeDenseMove, to: denseMoved, "Dense Move")

        let beforeRepresentedSwap = document
        XCTAssertTrue(coordinator.applySampleSlotPermutation(
            try .swap(0, 3), instrumentAt: 0
        ))
        let representedSwap = document
        XCTAssertEqual(representedSwap.selection.selectedSample, 4)
        XCTAssertEqual(representedSwap.instrumentPalette[1]?.noteSampleMap, exactRegionMap(1, 2, 0))
        XCTAssertEqual(routedNames(in: representedSwap), routingBeforeSelection)
        assertUndoRedo(from: beforeRepresentedSwap, to: representedSwap, "Represented Swap")

        let replacementIndex = try XCTUnwrap(document.instrumentPalette[1]?.samples.first {
            $0.name == "Replacement"
        }?.sampleIndex)
        document.selectSample(replacementIndex + 1)
        XCTAssertTrue(coordinator.clearSample(instrumentAt: 0, sampleAt: replacementIndex))
        XCTAssertEqual(routedNames(in: document), ["Low Pulse", nil, "Impulse"])
        let impulseIndex = try XCTUnwrap(document.instrumentPalette[1]?.samples.first {
            $0.name == "Impulse"
        }?.sampleIndex)
        document.selectSample(impulseIndex + 1)
        let beforeEmptySwap = document
        let sparseRoutingBeforeSwap = routedNames(in: document)
        XCTAssertTrue(coordinator.applySampleSlotPermutation(
            try .swap(impulseIndex, replacementIndex), instrumentAt: 0
        ))
        let final = document
        XCTAssertEqual(final.instrumentPalette[1]?.noteSampleMap, exactRegionMap(1, 0, 2))
        XCTAssertEqual(routedNames(in: final), sparseRoutingBeforeSwap)
        XCTAssertEqual(final.selection.selectedSample, replacementIndex + 1)
        XCTAssertEqual(final.patterns, initial.patterns)
        assertUndoRedo(from: beforeEmptySwap, to: final, "Represented/empty Swap")

        XCTAssertEqual(final.orderTable, initial.orderTable)
        XCTAssertEqual(final.restartPosition, initial.restartPosition)
        XCTAssertEqual(final.speed, initial.speed)
        XCTAssertEqual(final.tempo, initial.tempo)
        XCTAssertEqual(final.instrumentPalette[2], initial.instrumentPalette[2])
        let finalInstrument = try XCTUnwrap(final.instrumentPalette[1])
        XCTAssertEqual(finalInstrument.volumeEnvelope, initial.instrumentPalette[1]?.volumeEnvelope)
        XCTAssertEqual(finalInstrument.panningEnvelope, initial.instrumentPalette[1]?.panningEnvelope)
        XCTAssertEqual(finalInstrument.autoVibrato, initial.instrumentPalette[1]?.autoVibrato)
        let lowPulseIndices = finalInstrument.samples.filter { $0.name == "Low Pulse" }.map(\.sampleIndex)
        XCTAssertEqual(lowPulseIndices.count, 2)
        XCTAssertEqual(Set(try XCTUnwrap(finalInstrument.noteSampleMap)).intersection(lowPulseIndices).count, 1)

        let firstExport = try EditableXMWriter().data(from: final)
        XCTAssertEqual(try EditableXMWriter().data(from: final), firstExport)
        let xmURL = try temporaryExportURL(filename: "sample-lifecycle-gate.xm")
        XCTAssertEqual(
            ExportXMCoordinator(
                destinationProvider: LifecycleGateExportXMDestinationProvider(destination: xmURL)
            ).beginExport(context: .editable(
                document: final, displayName: final.title, isPlaybackActive: false
            )),
            .exported(destination: xmURL)
        )
        XCTAssertEqual(try Data(contentsOf: xmURL), firstExport)
        let metadata = try ModuleMetadataLoader().load(fromPath: xmURL.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: xmURL.path)
        XCTAssertEqual(metadata.title, final.title)
        XCTAssertEqual(metadata.orderTable, final.orderTable)
        XCTAssertEqual(metadata.restartPosition, final.restartPosition)
        XCTAssertEqual(metadata.defaultTempo, final.speed)
        XCTAssertEqual(metadata.defaultBPM, final.tempo)
        XCTAssertEqual(metadata.xmPatterns, final.patterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, final.instrumentPalette)
        XCTAssertEqual(
            reopenedSong.xmSampleSlotProvenanceByInstrument[1]?.filter(\.isCanonicalEmptySlotHeader).map(\.sampleIndex),
            [0]
        )

        let copyContext = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: reopenedSong,
            selection: final.selection,
            currentPatternIndex: final.currentPatternIndex,
            isPlaybackActive: false
        )
        guard case let .copied(copy) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: copyContext)
        else { return XCTFail("supported sparse lifecycle export should make an editable copy") }
        XCTAssertEqual(copy.orderTable, final.orderTable)
        XCTAssertEqual(copy.restartPosition, final.restartPosition)
        XCTAssertEqual(copy.speed, final.speed)
        XCTAssertEqual(copy.tempo, final.tempo)
        XCTAssertEqual(copy.patterns, final.patterns)
        XCTAssertEqual(copy.instrumentPalette, final.instrumentPalette)
        XCTAssertEqual(copy.selection, final.selection)
        XCTAssertEqual(try EditableXMWriter().data(from: copy), firstExport)
        let reexportURL = try temporaryExportURL(filename: "sample-lifecycle-gate-reexport.xm")
        XCTAssertEqual(
            ExportXMCoordinator(
                destinationProvider: LifecycleGateExportXMDestinationProvider(destination: reexportURL)
            ).beginExport(context: .editable(
                document: copy, displayName: copy.title, isPlaybackActive: false
            )),
            .exported(destination: reexportURL)
        )
        XCTAssertEqual(try Data(contentsOf: reexportURL), firstExport)
    }

    private func makeDocument(
        title: String = BlankTrackerDocument.defaultTitle,
        currentPatternIndex: Int = BlankTrackerDocument.defaultPatternIndex,
        restartPosition: Int = BlankTrackerDocument.defaultRestartPosition,
        tempo: Int = BlankTrackerDocument.defaultTempo,
        speed: Int = BlankTrackerDocument.defaultSpeed,
        orderTable: [Int],
        patterns: [XMPatternData],
        instrumentPalette: [Int: PlaybackInstrument] = [:]
    ) -> BlankTrackerDocument {
        BlankTrackerDocument(
            title: title,
            songLength: orderTable.count,
            currentPosition: 0,
            restartPosition: restartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: .default,
            instrumentPalette: instrumentPalette,
            patterns: patterns
        )
    }

    private func makeCompositionReleaseGateDocument() -> BlankTrackerDocument {
        var firstPattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 6, channels: 2)
        var secondPattern = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 4, channels: 2)
        firstPattern.rows[0][0] = XMPatternEventCell(note: 60, instrument: 1, volumeColumn: 0x30, effectType: 0x0F, effectParam: 0x06)
        firstPattern.rows[1][0] = XMPatternEventCell(note: 61, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        firstPattern.rows[2][0] = XMPatternEventCell(note: 72, instrument: 1, volumeColumn: 0x40, effectType: 0x0C, effectParam: 0x20)
        firstPattern.rows[3][0] = XMPatternEventCell(note: 73, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        firstPattern.rows[5][1] = XMPatternEventCell(note: XMPatternEventCell.keyOffNoteValue, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
        secondPattern.rows[0][0] = XMPatternEventCell(note: 49, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0)
        secondPattern.rows[2][0] = XMPatternEventCell(note: XMPatternEventCell.keyOffNoteValue, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)

        let low = makeXMSourceSample(
            name: "Low Pulse", pcm: (0..<64).map { $0 % 2 == 0 ? -0.5 : 0.5 },
            volume: 0.75, panning: 40, relativeNote: -2, finetune: 17,
            loopStart: 8, loopLength: 40, loopType: 1
        )
        let high = makeXMSourceSample(
            sampleIndex: 1, name: "High Ramp", pcm: (0..<96).map { Float(($0 % 32) - 16) / 32 },
            volume: 0.5, panning: 220, relativeNote: 3, finetune: -31,
            loopStart: 16, loopLength: 64, loopType: 2, sourceBitDepthBits: 16
        )
        let secondInstrumentSample = makeXMSourceSample(
            instrumentIndex: 2, name: "Second Pulse",
            pcm: (0..<64).map { $0.isMultiple(of: 4) ? 0.75 : -0.25 },
            volume: 0.625, panning: 128, sourceBitDepthBits: 16
        )
        let volumeEnvelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [.init(tick: 0, value: 64), .init(tick: 8, value: 48), .init(tick: 16, value: 32)],
            sustainPointIndex: 1, loopStartPointIndex: 0, loopEndPointIndex: 2,
            typeFlags: 0x07, fadeout: 2_048
        )
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [.init(tick: 0, value: 16), .init(tick: 12, value: 48)],
            sustainPointIndex: 1, loopStartPointIndex: 0, loopEndPointIndex: 1,
            typeFlags: 0x07
        )
        let mappedInstrument = PlaybackInstrument(
            index: 1, name: "Split Instrument", samples: [low, high],
            volumeEnvelope: volumeEnvelope, panningEnvelope: panningEnvelope,
            autoVibrato: .init(waveformType: 2, sweep: 8, depth: 6, rate: 24),
            noteSampleMap: Array(repeating: 0, count: 60)
                + Array(repeating: 1, count: 12)
                + Array(repeating: 0, count: 24)
        )
        return BlankTrackerDocument(
            title: "Composition Gate", songLength: 2, currentPosition: 0,
            restartPosition: 1, currentPatternIndex: 0, tempo: 132, speed: 6,
            orderTable: [0, 1], selection: .default,
            instrumentPalette: [
                1: mappedInstrument,
                2: PlaybackInstrument(
                    index: 2,
                    name: "Second Instrument",
                    samples: [secondInstrumentSample],
                    noteSampleMap: Array(repeating: 0, count: 96)
                )
            ],
            patterns: [firstPattern, secondPattern]
        )
    }

    private func makeSampleLifecycleGateDocument() throws -> BlankTrackerDocument {
        let base = makeCompositionReleaseGateDocument()
        let source = try XCTUnwrap(base.instrumentPalette[1])
        let impulse = makeXMSourceSample(
            sampleIndex: 2,
            name: "Impulse",
            pcm: (0..<64).map { $0 == 0 ? 0.875 : Float(64 - $0) / -128 },
            volume: 0.875,
            panning: 191,
            relativeNote: 7,
            finetune: -19,
            loopStart: 8,
            loopLength: 40,
            loopType: 2,
            sourceBitDepthBits: 16
        )
        let lifecycleInstrument = PlaybackInstrument(
            index: source.index,
            name: source.name,
            samples: source.samples + [impulse],
            volumeEnvelope: source.volumeEnvelope,
            panningEnvelope: source.panningEnvelope,
            autoVibrato: source.autoVibrato,
            noteSampleMap: Array(repeating: 0, count: 32)
                + Array(repeating: 1, count: 32)
                + Array(repeating: 2, count: 32)
        )
        var palette = base.instrumentPalette
        palette[1] = lifecycleInstrument
        return BlankTrackerDocument(
            title: "Untitled",
            songLength: base.songLength,
            currentPosition: base.currentPosition,
            restartPosition: base.restartPosition,
            currentPatternIndex: base.currentPatternIndex,
            tempo: base.tempo,
            speed: base.speed,
            orderTable: base.orderTable,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            instrumentPalette: palette,
            patterns: base.patterns
        )
    }

    private func makeXMSourceSample(
        instrumentIndex: Int = 1,
        sampleIndex: Int = 0,
        name: String? = nil,
        pcm: [Float],
        volume: Float = 1,
        panning: UInt8 = 128,
        relativeNote: Int = 0,
        finetune: Int = 0,
        loopStart: Int = 0,
        loopLength: Int = 0,
        loopType: Int = 0,
        sourceBitDepthBits: Int = 8
    ) -> PlaybackSample {
        PlaybackSample(
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            name: name,
            pcm: pcm,
            volume: volume,
            panning: panning,
            relativeNote: relativeNote,
            finetune: finetune,
            baseSampleRate: 8_363,
            sampleLength: pcm.count,
            loopStart: loopStart,
            loopLength: loopLength,
            loopType: loopType,
            sourceBitDepthBits: sourceBitDepthBits,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
    }

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("tests/reference-xm/\(relativePath)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("missing reference XM fixture at \(url.path)")
        }
        return url
    }

    private func temporaryExportURL(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtx-editable-xm-writer-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(filename)
        XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        return url
    }

    private func reloadedMetadata(
        from document: BlankTrackerDocument,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ParsedModuleMetadata {
        let data = try EditableXMWriter().data(from: document)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtx-editable-xm-writer-reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("generated.xm")
        try data.write(to: url, options: .atomic)
        XCTAssertTrue(
            url.path.hasPrefix(FileManager.default.temporaryDirectory.path),
            "reload smoke wrote outside the system temporary directory",
            file: file,
            line: line
        )

        do {
            return try ModuleMetadataLoader().load(fromPath: url.path)
        } catch {
            XCTFail("generated XM did not reload through ModuleMetadataLoader: \(error)", file: file, line: line)
            throw error
        }
    }
}

@MainActor
private final class LifecycleGateExportXMDestinationProvider: ExportXMDestinationProviding {
    private let destination: URL

    init(destination: URL) {
        self.destination = destination
    }

    func chooseExportXMDestination(request _: ExportXMDestinationRequest) -> URL? {
        destination
    }
}

private struct XMTestPatternHeader {
    let headerLength: UInt32
    let packingType: UInt8
    let rowCount: UInt16
    let packedSize: UInt16
    let dataRange: Range<Int>
    let nextOffset: Int
}

private struct XMTestInstrumentHeader {
    let headerLength: UInt32
    let sampleCount: UInt16
    let sampleHeaderSize: UInt32
    let sampleHeaderOffset: Int
    let sampleDataOffset: Int
    let nextOffset: Int
}

private struct XMTestSampleHeader {
    let lengthBytes: UInt32
    let loopStartBytes: UInt32
    let loopLengthBytes: UInt32
    let volume: UInt8
    let finetune: UInt8
    let type: UInt8
    let panning: UInt8
    let relativeNote: UInt8
    let name: String
}

private extension Data {
    func le16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func le32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    func ascii(offset: Int, length: Int) -> String {
        let bytes = Array(subdata(in: offset..<(offset + length)))
        let trimmed = Array(bytes.prefix { $0 != 0 })
        return String(bytes: trimmed, encoding: .ascii) ?? ""
    }

    func patternHeader(at offset: Int) -> XMTestPatternHeader {
        let headerLength = le32(at: offset)
        let packedSize = le16(at: offset + 7)
        let dataStart = offset + Int(headerLength)
        let dataEnd = dataStart + Int(packedSize)
        return XMTestPatternHeader(
            headerLength: headerLength,
            packingType: self[offset + 4],
            rowCount: le16(at: offset + 5),
            packedSize: packedSize,
            dataRange: dataStart..<dataEnd,
            nextOffset: dataEnd
        )
    }

    func instrumentHeader(at offset: Int) -> XMTestInstrumentHeader {
        let headerLength = le32(at: offset)
        let sampleCount = le16(at: offset + 27)
        let sampleHeaderSize = sampleCount == 0 ? 0 : le32(at: offset + 29)
        let sampleHeaderOffset = offset + Int(headerLength)
        let sampleDataOffset = sampleHeaderOffset + (Int(sampleHeaderSize) * Int(sampleCount))
        var nextOffset = sampleDataOffset
        if sampleCount > 0 {
            for sampleIndex in 0..<Int(sampleCount) {
                let sampleOffset = sampleHeaderOffset + (sampleIndex * Int(sampleHeaderSize))
                nextOffset += Int(le32(at: sampleOffset))
            }
        }
        return XMTestInstrumentHeader(
            headerLength: headerLength,
            sampleCount: sampleCount,
            sampleHeaderSize: sampleHeaderSize,
            sampleHeaderOffset: sampleHeaderOffset,
            sampleDataOffset: sampleDataOffset,
            nextOffset: nextOffset
        )
    }

    func sampleHeader(at offset: Int) -> XMTestSampleHeader {
        XMTestSampleHeader(
            lengthBytes: le32(at: offset),
            loopStartBytes: le32(at: offset + 4),
            loopLengthBytes: le32(at: offset + 8),
            volume: self[offset + 12],
            finetune: self[offset + 13],
            type: self[offset + 14],
            panning: self[offset + 15],
            relativeNote: self[offset + 16],
            name: ascii(offset: offset + 18, length: 22)
        )
    }
}
