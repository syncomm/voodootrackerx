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
        XCTAssertEqual(info.song_length, 3)
        XCTAssertEqual(info.restart_position, 1)
        XCTAssertEqual(info.default_tempo, 6)
        XCTAssertEqual(info.default_bpm, 125)
        XCTAssertEqual(info.order_table_length, 3)
        XCTAssertEqual(Array(orderTable(info).prefix(3)), [0, 1, 0])
        XCTAssertEqual(info.pattern_row_count_count, 2)
        XCTAssertEqual(Array(patternRows(info).prefix(2)), [4, 4])
        XCTAssertEqual(Array(patternPackedSizes(info).prefix(2)), [29, 28])
        XCTAssertEqual(info.xm_event_count, 32)
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
