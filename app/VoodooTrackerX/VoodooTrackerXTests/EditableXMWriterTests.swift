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
