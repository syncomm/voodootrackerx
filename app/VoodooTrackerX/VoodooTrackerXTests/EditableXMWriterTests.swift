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
        XCTAssertEqual(data.le16(at: 72), 0)
        XCTAssertEqual(data.le16(at: 74), 0x0001)
        XCTAssertEqual(data.le16(at: 76), 6)
        XCTAssertEqual(data.le16(at: 78), 125)
        XCTAssertEqual(Array(data.subdata(in: 80..<84)), [0, 0, 0, 0])

        let pattern = data.patternHeader(at: 336)
        XCTAssertEqual(pattern.headerLength, 9)
        XCTAssertEqual(pattern.packingType, 0)
        XCTAssertEqual(pattern.rowCount, 64)
        XCTAssertEqual(pattern.packedSize, 0)
        XCTAssertEqual(pattern.nextOffset, data.count)
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
        XCTAssertEqual(metadata.instruments, 0)
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

    private func makeDocument(
        title: String = BlankTrackerDocument.defaultTitle,
        currentPatternIndex: Int = BlankTrackerDocument.defaultPatternIndex,
        restartPosition: Int = BlankTrackerDocument.defaultRestartPosition,
        tempo: Int = BlankTrackerDocument.defaultTempo,
        speed: Int = BlankTrackerDocument.defaultSpeed,
        orderTable: [Int],
        patterns: [XMPatternData]
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
            instrumentPalette: [:],
            patterns: patterns
        )
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
}
