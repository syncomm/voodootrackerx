import Foundation
import XCTest
import VTXModuleCore

final class ModuleParserTests: XCTestCase {
    func testParsesMinimalMODHeader() throws {
        let data = try fixture(named: "minimal", ext: "mod")
        let info = try parse(data)

        XCTAssertEqual(cString(from: info.format), "MOD")
        XCTAssertEqual(cString(from: info.title), "TEST MOD")
        XCTAssertEqual(info.channels, 4)
        XCTAssertEqual(info.patterns, 1)
        XCTAssertEqual(info.instruments, 31)
        XCTAssertEqual(info.song_length, 1)
    }

    func testParsesMinimalXMHeader() throws {
        let data = try fixture(named: "minimal", ext: "xm")
        let info = try parse(data)

        XCTAssertEqual(cString(from: info.format), "XM")
        XCTAssertEqual(cString(from: info.title), "TEST XM")
        XCTAssertEqual(info.version_major, 1)
        XCTAssertEqual(info.version_minor, 4)
        XCTAssertEqual(info.channels, 4)
        XCTAssertEqual(info.patterns, 1)
        XCTAssertEqual(info.instruments, 1)
        XCTAssertEqual(info.song_length, 1)
    }

    private func fixture(named name: String, ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            XCTFail("Missing fixture \(name).\(ext)")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    private func parse(_ data: Data) throws -> VTXModuleHeaderInfo {
        var info = VTXModuleHeaderInfo()
        let result = data.withUnsafeBytes { rawBuffer -> VTXParseResult in
            guard let baseAddress = rawBuffer.baseAddress else {
                return VTX_PARSE_INVALID_ARGUMENT
            }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            return vtx_parse_module_header(bytes, data.count, &info)
        }
        guard result == VTX_PARSE_OK else {
            XCTFail("Unexpected parse failure: \(String(cString: vtx_parse_result_string(result)))")
            throw NSError(domain: "ModuleParserTests", code: Int(result.rawValue))
        }
        return info
    }

    private func cString<T>(from tuple: T) -> String {
        var value = tuple
        return withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
