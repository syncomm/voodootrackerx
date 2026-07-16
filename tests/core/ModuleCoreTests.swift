import Foundation
import XCTest
import ModuleCore

final class ModuleCoreTests: XCTestCase {
    func testParseSyntheticMODHeaderSelectedFields() throws {
        let info = mc_parse_file(try fixturePath("minimal.mod"))

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(typeName(info.type), "MOD")
        XCTAssertEqual(cString(info.title), "TEST MOD")
        XCTAssertEqual(info.channels, 4)
        XCTAssertEqual(info.song_length, 2)
        XCTAssertEqual(info.restart_position, 127)
        XCTAssertEqual(info.order_table_length, 2)
        XCTAssertEqual(Array(orderTable(info).prefix(2)), [0, 1])
        XCTAssertEqual(info.patterns, 2)
        XCTAssertEqual(cString(info.first_mod_sample.name), "KICK")
        XCTAssertEqual(info.first_mod_sample.length_bytes, 16)
        XCTAssertEqual(info.first_mod_sample.finetune, -1)
        XCTAssertEqual(info.first_mod_sample.volume, 40)
    }

    func testParseSyntheticXMHeaderSelectedFields() throws {
        let info = mc_parse_file(try fixturePath("minimal.xm"))

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(typeName(info.type), "XM")
        XCTAssertEqual(cString(info.title), "TEST XM")
        XCTAssertEqual(info.version_major, 1)
        XCTAssertEqual(info.version_minor, 4)
        XCTAssertEqual(info.channels, 4)
        XCTAssertEqual(info.patterns, 2)
        XCTAssertEqual(info.instruments, 1)
        XCTAssertEqual(info.xm_flags, 0)
        XCTAssertEqual(info.song_length, 3)
        XCTAssertEqual(info.restart_position, 1)
        XCTAssertEqual(info.default_tempo, 6)
        XCTAssertEqual(info.default_bpm, 125)
        XCTAssertEqual(info.order_table_length, 3)
        XCTAssertEqual(Array(orderTable(info).prefix(3)), [0, 1, 0])
        XCTAssertEqual(info.pattern_row_count_count, 2)
        XCTAssertEqual(Array(patternRows(info).prefix(2)), [4, 4])
        XCTAssertEqual(Array(patternPackedSizes(info).prefix(2)), [29, 28])
        XCTAssertEqual(info.xm_event_count, 8)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.note, 48)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.instrument, 1)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.volume, 64)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.effect_type, 15)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.effect_param, 6)
        XCTAssertEqual(xmEvent(info, pattern: 1, row: 1, channel: 2)?.note, 59)
        XCTAssertEqual(xmEvent(info, pattern: 1, row: 2, channel: 0)?.effect_type, 11)
        XCTAssertEqual(xmEvent(info, pattern: 1, row: 2, channel: 0)?.effect_param, 2)
        XCTAssertEqual(cString(info.first_instrument_name), "BASS")
    }

    func testValidXMOrderTableParsingRegressionUnchanged() throws {
        let info = mc_parse_file(try fixturePath("minimal.xm"))

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(info.order_table_length, 3)
        XCTAssertEqual(Array(orderTable(info).prefix(3)), [0, 1, 0])
        XCTAssertEqual(info.song_length, 3)
    }

    func testParseClampsOrderTableWhenXMHeaderHasNoOrderBytes() throws {
        let bytes: Data = makeXMBytes(
            patterns: 0,
            headerSize: 20,
            songLength: 256,
            channels: 1,
            orderTable: []
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_short_header_no_orders.xm")

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(info.song_length, 256)
        XCTAssertEqual(info.order_table_length, 0)
    }

    func testParseClampsOrderTableWhenXMHeaderEndsBeforeSongLength() throws {
        let bytes: Data = makeXMBytes(
            patterns: 0,
            headerSize: 24,
            songLength: 6,
            channels: 1,
            orderTable: [2, 3, 4, 5]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_short_header_partial_orders.xm")

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(info.song_length, 6)
        XCTAssertEqual(info.order_table_length, 4)
        XCTAssertEqual(Array(orderTable(info).prefix(4)), [2, 3, 4, 5])
    }

    func testParseRejectsXMHeaderTruncatedBeforeDeclaredHeaderSize() throws {
        let fullBytes: Data = makeXMBytes(
            patterns: 0,
            headerSize: 276,
            songLength: 16,
            channels: 1,
            orderTable: (0..<16).map(UInt8.init)
        )
        let truncatedBytes = Data(fullBytes.prefix(90))

        let info: mc_module_info = try parseModuleBytes(truncatedBytes, name: "mc_xm_truncated_declared_header.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseRejectsZeroXMChannels() throws {
        let bytes: Data = makeXMBytes(
            patterns: 0,
            songLength: 1,
            channels: 0,
            orderTable: [0]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_zero_channels.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseRejectsXMChannelCountAboveSafetyCeiling() throws {
        let bytes: Data = makeXMBytes(
            patterns: 0,
            songLength: 1,
            channels: 65,
            orderTable: [0]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_excessive_channels.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseRejectsXMPatternCountAboveSafetyCeiling() throws {
        let bytes: Data = makeXMBytes(
            patterns: 257,
            songLength: 1,
            channels: 1,
            orderTable: [0]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_excessive_patterns.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseAcceptsMaximumXMChannelAndPatternRowSafetyCeilings() throws {
        let bytes: Data = makeXMBytes(
            patterns: 1,
            songLength: 1,
            channels: 64,
            orderTable: [0],
            patternRows: [256]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_max_channels_rows.xm")

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(info.channels, 64)
        XCTAssertEqual(info.pattern_row_count_count, 1)
        XCTAssertEqual(Array(patternRows(info).prefix(1)), [UInt16(256)])
        XCTAssertEqual(Array(patternPackedSizes(info).prefix(1)), [UInt16(0)])
    }

    func testParseRejectsZeroXMPatternRows() throws {
        let bytes: Data = makeXMBytes(
            patterns: 1,
            songLength: 1,
            channels: 1,
            orderTable: [0],
            patternRows: [0]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_zero_pattern_rows.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseRejectsExcessiveXMPatternRows() throws {
        let bytes: Data = makeXMBytes(
            patterns: 1,
            songLength: 1,
            channels: 1,
            orderTable: [0],
            patternRows: [257]
        )

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_excessive_pattern_rows.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseRejectsTruncatedXMPatternHeader() throws {
        var bytes: Data = makeXMBytes(
            patterns: 1,
            songLength: 1,
            channels: 1,
            orderTable: [0]
        )
        bytes.append(contentsOf: [UInt8(9), 0, 0, 0])

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_truncated_pattern_header.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseRejectsTruncatedXMPatternPackedData() throws {
        var bytes: Data = makeXMBytes(
            patterns: 1,
            songLength: 1,
            channels: 1,
            orderTable: [0]
        )
        appendXMPatternHeader(rowCount: 1, packedSize: 2, packedData: [0x80], to: &bytes)

        let info: mc_module_info = try parseModuleBytes(bytes, name: "mc_xm_truncated_pattern_data.xm")

        XCTAssertEqual(info.ok, 0)
    }

    func testParseGeneratedBasicInstrumentSampleXMFixture() throws {
        let info = mc_parse_file(try referenceXMFixturePath("generated/basic-instrument-sample.xm"))

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(typeName(info.type), "XM")
        XCTAssertEqual(cString(info.title), "VTX BASIC SAMPLE")
        XCTAssertEqual(info.version_major, 1)
        XCTAssertEqual(info.version_minor, 4)
        XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(info.patterns, 1)
        XCTAssertEqual(info.instruments, 1)
        XCTAssertEqual(info.xm_flags, 1)
        XCTAssertEqual(info.song_length, 1)
        XCTAssertEqual(info.restart_position, 0)
        XCTAssertEqual(info.default_tempo, 6)
        XCTAssertEqual(info.default_bpm, 125)
        XCTAssertEqual(info.order_table_length, 1)
        XCTAssertEqual(Array(orderTable(info).prefix(1)), [0])
        XCTAssertEqual(info.pattern_row_count_count, 1)
        XCTAssertEqual(Array(patternRows(info).prefix(1)), [16])
        XCTAssertEqual(Array(patternPackedSizes(info).prefix(1)), [19])
        XCTAssertEqual(info.xm_event_count, 2)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.note, 49)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.instrument, 1)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 8, channel: 0)?.note, 97)
        XCTAssertEqual(cString(info.first_instrument_name), "BASIC SAMPLE")
    }

    func testParseGeneratedMultiPatternLoopBoundaryXMFixture() throws {
        let info = mc_parse_file(try referenceXMFixturePath("generated/multi-pattern-loop-boundary.xm"))

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(typeName(info.type), "XM")
        XCTAssertEqual(cString(info.title), "VTX LOOP BOUNDARY")
        XCTAssertEqual(info.version_major, 1)
        XCTAssertEqual(info.version_minor, 4)
        XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(info.patterns, 3)
        XCTAssertEqual(info.instruments, 1)
        XCTAssertEqual(info.xm_flags, 1)
        XCTAssertEqual(info.song_length, 3)
        XCTAssertEqual(info.restart_position, 0)
        XCTAssertEqual(info.default_tempo, 6)
        XCTAssertEqual(info.default_bpm, 125)
        XCTAssertEqual(info.order_table_length, 3)
        XCTAssertEqual(Array(orderTable(info).prefix(3)), [0, 1, 2])
        XCTAssertEqual(info.pattern_row_count_count, 3)
        XCTAssertEqual(Array(patternRows(info).prefix(3)), [4, 4, 4])
        XCTAssertEqual(Array(patternPackedSizes(info).prefix(3)), [6, 6, 6])
        XCTAssertEqual(info.xm_event_count, 3)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.note, 49)
        XCTAssertEqual(xmEvent(info, pattern: 0, row: 0, channel: 0)?.instrument, 1)
        XCTAssertEqual(xmEvent(info, pattern: 1, row: 0, channel: 0)?.note, 53)
        XCTAssertEqual(xmEvent(info, pattern: 1, row: 0, channel: 0)?.instrument, 1)
        XCTAssertEqual(xmEvent(info, pattern: 2, row: 0, channel: 0)?.note, 56)
        XCTAssertEqual(xmEvent(info, pattern: 2, row: 0, channel: 0)?.instrument, 1)
        XCTAssertEqual(cString(info.first_instrument_name), "BOUNDARY SAMPLE")
    }

    func testParseGeneratedInstrumentSustainedDefaultsXMFixture() throws {
        let info = mc_parse_file(try referenceXMFixturePath("generated/instrument-sustained-defaults.xm"))
        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(cString(info.title), "VTX SUSTAINED")
        XCTAssertEqual(info.instruments, 1)
        XCTAssertEqual(patternRows(info)[0], 64)
        XCTAssertEqual(info.xm_event_count, 4)
        XCTAssertEqual(cString(info.first_instrument_name), "SUSTAINED DEFAULTS")
    }

    func testGoldenSnapshotMOD() throws {
        let info = mc_parse_file(try fixturePath("minimal.mod"))
        XCTAssertEqual(normalize(snapshotJSON(info)), normalize(try goldenString("minimal.mod.json")))
    }

    func testGoldenSnapshotXM() throws {
        let info = mc_parse_file(try fixturePath("minimal.xm"))
        XCTAssertEqual(normalize(snapshotJSON(info)), normalize(try goldenString("minimal.xm.json")))
    }

    func testGoldenSnapshotXMPattern1Events() throws {
        let info = mc_parse_file(try fixturePath("minimal.xm"))
        XCTAssertEqual(normalize(snapshotJSON(info, includeEvents: true, pattern: 1)), normalize(try goldenString("minimal.xm.pattern1.json")))
    }

    func testUnknownMODSignatureDefaultsTo4ChannelsWithWarning() throws {
        var bytes = Data(count: 1084)
        bytes.replaceSubrange(0..<7, with: Data("ODD MOD".utf8))
        bytes[950] = 1
        bytes[951] = 0x7f
        bytes[952] = 0
        bytes.replaceSubrange(1080..<1084, with: Data("ZZZZ".utf8))

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc_unknown_sig.mod")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = mc_parse_file(url.path)
        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(typeName(info.type), "MOD")
        XCTAssertEqual(info.channels, 4)
        XCTAssertTrue(cString(info.warning).contains("defaulting to 4 channels"))
    }

    func testParseRejectsUnknownFile() throws {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mc_bad.bin")
        try Data([0x00, 0x01, 0x02]).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let info = mc_parse_file(tmpURL.path)
        XCTAssertEqual(info.ok, 0)
        XCTAssertFalse(cString(info.error).isEmpty)
    }

    private func fixturePath(_ name: String) throws -> String {
        guard let base = Bundle.module.resourceURL else {
            throw XCTSkip("Missing Bundle.module resource URL")
        }
        let url = base.appendingPathComponent("fixtures").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url.path
    }

    private func referenceXMFixturePath(_ relativePath: String) throws -> String {
        guard let base = Bundle.module.resourceURL else {
            throw XCTSkip("Missing Bundle.module resource URL")
        }
        let url = base.appendingPathComponent("reference-xm").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing reference XM fixture \(relativePath)")
        }
        return url.path
    }

    private func goldenString(_ name: String) throws -> String {
        guard let base = Bundle.module.resourceURL else {
            throw XCTSkip("Missing Bundle.module resource URL")
        }
        let url = base.appendingPathComponent("golden").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing golden \(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func normalize(_ s: String) -> String {
        var value = s
        while value.last == "\n" || value.last == "\r" {
            value.removeLast()
        }
        return value
    }

    private func typeName(_ type: mc_module_type) -> String {
        String(cString: mc_module_type_name(type))
    }

    private func cString<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }

    private func orderTable(_ info: mc_module_info) -> [UInt8] {
        var copy = info.order_table
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: UInt8.self, capacity: Int(MC_MAX_ORDER_ENTRIES)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_ORDER_ENTRIES)))
            }
        }
    }

    private func patternRows(_ info: mc_module_info) -> [UInt16] {
        var copy = info.pattern_row_counts
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: UInt16.self, capacity: Int(MC_MAX_PATTERN_ROW_COUNTS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_PATTERN_ROW_COUNTS)))
            }
        }
    }

    private func patternPackedSizes(_ info: mc_module_info) -> [UInt16] {
        var copy = info.pattern_packed_sizes
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: UInt16.self, capacity: Int(MC_MAX_PATTERN_ROW_COUNTS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_PATTERN_ROW_COUNTS)))
            }
        }
    }

    private func xmEvents(_ info: mc_module_info) -> [mc_xm_event] {
        var copy = info.xm_events
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: mc_xm_event.self, capacity: Int(MC_MAX_XM_EVENTS)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(MC_MAX_XM_EVENTS)))
            }
        }
    }

    private func xmEvent(_ info: mc_module_info, pattern: UInt16, row: UInt16, channel: UInt16) -> mc_xm_event? {
        xmEvents(info)
            .prefix(Int(info.xm_event_count))
            .first { $0.pattern == pattern && $0.row == row && $0.channel == channel }
    }

    private func parseModuleBytes(_ data: Data, name: String) throws -> mc_module_info {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return mc_parse_file(url.path)
    }

    private func makeXMBytes(
        patterns: UInt16,
        headerSize: UInt32 = 276,
        songLength: UInt16 = 1,
        restartPosition: UInt16 = 0,
        channels: UInt16 = 1,
        instruments: UInt16 = 0,
        flags: UInt16 = 0,
        defaultTempo: UInt16 = 6,
        defaultBPM: UInt16 = 125,
        orderTable: [UInt8] = [0],
        patternRows: [UInt16] = []
    ) -> Data {
        var data = Data()

        data.append(contentsOf: Array("Extended Module: ".utf8))
        appendFixedASCII("TEST XM", length: 20, to: &data)
        data.append(0x1A)
        appendFixedASCII("VoodooTrackerX", length: 20, to: &data)
        appendLE16(0x0104, to: &data)
        appendLE32(headerSize, to: &data)
        appendLE16(songLength, to: &data)
        appendLE16(restartPosition, to: &data)
        appendLE16(channels, to: &data)
        appendLE16(patterns, to: &data)
        appendLE16(instruments, to: &data)
        appendLE16(flags, to: &data)
        appendLE16(defaultTempo, to: &data)
        appendLE16(defaultBPM, to: &data)

        let headerOrderCapacity = max(0, Int(headerSize) - 20)
        if headerOrderCapacity > 0 {
            let copiedOrder = Array(orderTable.prefix(headerOrderCapacity))
            data.append(contentsOf: copiedOrder)
            if copiedOrder.count < headerOrderCapacity {
                data.append(contentsOf: repeatElement(UInt8(0), count: headerOrderCapacity - copiedOrder.count))
            }
        }

        let totalHeaderSize = 60 + Int(headerSize)
        if data.count < totalHeaderSize {
            data.append(contentsOf: repeatElement(UInt8(0), count: totalHeaderSize - data.count))
        }

        for rowCount in patternRows {
            appendXMPatternHeader(rowCount: rowCount, to: &data)
        }

        return data
    }

    private func appendFixedASCII(_ string: String, length: Int, to data: inout Data) {
        let bytes = Array(string.utf8.prefix(length))
        data.append(contentsOf: bytes)
        if bytes.count < length {
            data.append(contentsOf: repeatElement(UInt8(0), count: length - bytes.count))
        }
    }

    private func appendLE16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    private func appendLE32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x000000FF))
        data.append(UInt8((value >> 8) & 0x000000FF))
        data.append(UInt8((value >> 16) & 0x000000FF))
        data.append(UInt8((value >> 24) & 0x000000FF))
    }

    private func appendXMPatternHeader(
        rowCount: UInt16,
        packedSize: UInt16 = 0,
        packedData: [UInt8] = [],
        to data: inout Data
    ) {
        appendLE32(9, to: &data)
        data.append(0)
        appendLE16(rowCount, to: &data)
        appendLE16(packedSize, to: &data)
        data.append(contentsOf: packedData)
    }

    private func snapshotJSON(_ info: mc_module_info, includeEvents: Bool = false, pattern: UInt16? = nil) -> String {
        let order = Array(orderTable(info).prefix(Int(info.order_table_length)))
        let rows = Array(patternRows(info).prefix(Int(info.pattern_row_count_count)))
        let packedSizes = Array(patternPackedSizes(info).prefix(Int(info.pattern_packed_size_count)))
        let events = Array(
            xmEvents(info)
                .prefix(Int(info.xm_event_count))
                .filter { event in
                    if !includeEvents {
                        return false
                    }
                    if let pattern {
                        return event.pattern == pattern
                    }
                    return true
                }
        )

        let orderList = order.map(String.init).joined(separator: ", ")
        let rowList = rows.map(String.init).joined(separator: ", ")
        let packedSizeList = packedSizes.map(String.init).joined(separator: ", ")
        let eventList = events.map {
            "{ \"pattern\": \($0.pattern), \"row\": \($0.row), \"channel\": \($0.channel), \"note\": \($0.note), \"instrument\": \($0.instrument), \"volume\": \($0.volume), \"effect_type\": \($0.effect_type), \"effect_param\": \($0.effect_param) }"
        }.joined(separator: ", ")
        if includeEvents {
            return """
            {
              "ok": \(info.ok != 0 ? "true" : "false"),
              "type": \(jsonString(typeName(info.type))),
              "error": \(jsonString(cString(info.error))),
              "warning": \(jsonString(cString(info.warning))),
              "title": \(jsonString(cString(info.title))),
              "version": { "major": \(info.version_major), "minor": \(info.version_minor) },
              "channels": \(info.channels),
              "patterns": \(info.patterns),
              "instruments": \(info.instruments),
              "xm_flags": \(info.xm_flags),
              "song_length": \(info.song_length),
              "restart_position": \(info.restart_position),
              "default_tempo": \(info.default_tempo),
              "default_bpm": \(info.default_bpm),
              "order_table_length": \(info.order_table_length),
              "order_table": [\(orderList)],
              "pattern_row_counts": [\(rowList)],
              "pattern_packed_sizes": [\(packedSizeList)],
              "xm_events": [\(eventList)],
              "first_instrument_name": \(jsonString(cString(info.first_instrument_name))),
              "first_mod_sample": {
                "name": \(jsonString(cString(info.first_mod_sample.name))),
                "length_bytes": \(info.first_mod_sample.length_bytes),
                "finetune": \(info.first_mod_sample.finetune),
                "volume": \(info.first_mod_sample.volume)
              }
            }
            """
        }

        return """
        {
          "ok": \(info.ok != 0 ? "true" : "false"),
          "type": \(jsonString(typeName(info.type))),
          "error": \(jsonString(cString(info.error))),
          "warning": \(jsonString(cString(info.warning))),
          "title": \(jsonString(cString(info.title))),
          "version": { "major": \(info.version_major), "minor": \(info.version_minor) },
          "channels": \(info.channels),
          "patterns": \(info.patterns),
          "instruments": \(info.instruments),
          "xm_flags": \(info.xm_flags),
          "song_length": \(info.song_length),
          "restart_position": \(info.restart_position),
          "default_tempo": \(info.default_tempo),
          "default_bpm": \(info.default_bpm),
          "order_table_length": \(info.order_table_length),
          "order_table": [\(orderList)],
          "pattern_row_counts": [\(rowList)],
          "pattern_packed_sizes": [\(packedSizeList)],
          "first_instrument_name": \(jsonString(cString(info.first_instrument_name))),
          "first_mod_sample": {
            "name": \(jsonString(cString(info.first_mod_sample.name))),
            "length_bytes": \(info.first_mod_sample.length_bytes),
            "finetune": \(info.first_mod_sample.finetune),
            "volume": \(info.first_mod_sample.volume)
          }
        }
        """
    }

    private func jsonString(_ input: String) -> String {
        var out = "\""
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x00...0x1F:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }
}
