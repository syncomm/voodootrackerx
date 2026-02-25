import Foundation
import XCTest
import ModuleCore

final class ModuleCoreTests: XCTestCase {
    func testParseSyntheticMODHeader() throws {
        let path = try fixturePath("minimal.mod")
        let info = mc_parse_file(path)

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(mc_module_type_name(info.type).flatMap(String.init(cString:)), "MOD")
        XCTAssertEqual(cString(info.title), "TEST MOD")
        XCTAssertEqual(info.channels, 4)
        XCTAssertEqual(info.patterns, 1)
        XCTAssertEqual(info.instruments, 31)
        XCTAssertEqual(info.song_length, 1)
    }

    func testParseSyntheticXMHeader() throws {
        let path = try fixturePath("minimal.xm")
        let info = mc_parse_file(path)

        XCTAssertEqual(info.ok, 1)
        XCTAssertEqual(mc_module_type_name(info.type).flatMap(String.init(cString:)), "XM")
        XCTAssertEqual(cString(info.title), "TEST XM")
        XCTAssertEqual(info.version_major, 1)
        XCTAssertEqual(info.version_minor, 4)
        XCTAssertEqual(info.channels, 4)
        XCTAssertEqual(info.patterns, 1)
        XCTAssertEqual(info.instruments, 1)
        XCTAssertEqual(info.song_length, 1)
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
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url.path
    }

    private func cString<T>(_ tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
