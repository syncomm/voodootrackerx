import Foundation

struct ParsedModuleMetadata: Equatable {
    let type: String
    let title: String
    let version: String?
    let channels: Int
    let patterns: Int
    let instruments: Int
    let songLength: Int

    var displayText: String {
        var lines = [
            "Type: \(type)",
            "Title: \(title.isEmpty ? "(empty)" : title)",
        ]
        if let version {
            lines.append("Version: \(version)")
        }
        lines.append("Channels: \(channels)")
        lines.append("Patterns: \(patterns)")
        lines.append("Instruments: \(instruments)")
        lines.append("Song Length: \(songLength)")
        return lines.joined(separator: "\n")
    }
}

enum ModuleMetadataLoaderError: LocalizedError {
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case let .parseFailed(message):
            return message
        }
    }
}

struct ModuleMetadataLoader {
    func load(fromPath path: String) throws -> ParsedModuleMetadata {
        let info = mc_parse_file(path)
        guard info.ok != 0 else {
            throw ModuleMetadataLoaderError.parseFailed(Self.string(from: info.error))
        }

        let typeName = String(cString: mc_module_type_name(info.type))
        let version: String?
        if info.type == MC_MODULE_TYPE_XM {
            version = "\(info.version_major).\(info.version_minor)"
        } else {
            version = nil
        }

        return ParsedModuleMetadata(
            type: typeName,
            title: Self.string(from: info.title),
            version: version,
            channels: Int(info.channels),
            patterns: Int(info.patterns),
            instruments: Int(info.instruments),
            songLength: Int(info.song_length)
        )
    }

    private static func string<T>(from tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
