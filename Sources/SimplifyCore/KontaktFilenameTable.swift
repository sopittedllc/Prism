import Foundation

/// Saved Kontakt resource references, not evidence of a successful instrument load.
/// Version 3 framing is observed in the controlled Kontakt 8 loaded/empty fixtures.
/// Unknown fields are retained as bytes; no timestamp or ownership is inferred.
public enum KontaktFilenameTable {
    public struct Entry: Sendable, Equatable {
        public let segments: [Segment]
        public let header: Data
        public let trailer: Data

        /// Only absolute macOS paths with ordinary directory and file segments.
        /// Library-container references and relative paths require another resolver.
        public var absolutePath: String? {
            guard let first = segments.first, first.kind == 1, first.text == "",
                  segments.count > 1 else { return nil }
            let rest = segments.dropFirst()
            guard rest.allSatisfy({ [2, 4, 5].contains($0.kind) && !$0.text.isEmpty
                && $0.text != "." && $0.text != ".." && !$0.text.contains("/")
                && !$0.text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { return nil }
            return "/" + rest.map(\.text).joined(separator: "/")
        }
    }
    public struct Segment: Sendable, Equatable {
        public let kind: UInt8
        public let text: String
    }
    public enum ReadError: Error { case malformed, unsupported, limit }

    /// Input must be the payload of a structurally located 0x4B chunk. This reader
    /// does not search arbitrary plugin bytes for plausible filenames.
    public static func read(_ data: Data) throws -> [Entry] {
        guard data.count <= 4 * 1024 * 1024 else { throw ReadError.limit }
        var reader = Reader(bytes: Array(data))
        guard try reader.integer(2) == 3 else { throw ReadError.unsupported }
        let count = try reader.integer(4)
        guard count <= 16_384 else { throw ReadError.limit }
        var entries: [Entry] = []
        for _ in 0..<count {
            let header = try reader.take(8)
            let segmentCount = try reader.integer(4)
            guard segmentCount <= 128 else { throw ReadError.limit }
            var segments: [Segment] = []
            for _ in 0..<segmentCount {
                let kind = UInt8(try reader.integer(1))
                let text: String
                switch kind {
                case 1, 2, 4, 5, 8, 9:
                    let units = try reader.integer(4)
                    guard units <= 4_096 else { throw ReadError.limit }
                    let bytes = try reader.take(units * 2)
                    guard let decoded = String(data: bytes, encoding: .utf16LittleEndian),
                          decoded.data(using: .utf16LittleEndian) == bytes else { throw ReadError.malformed }
                    text = decoded
                case 3: text = ".."
                case 6: text = ""
                default: throw ReadError.unsupported
                }
                segments.append(Segment(kind: kind, text: text))
            }
            entries.append(Entry(segments: segments, header: header, trailer: try reader.take(20)))
        }
        guard reader.position == reader.bytes.count else { throw ReadError.malformed }
        return entries
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0
        mutating func take(_ count: Int) throws -> Data {
            guard count >= 0, count <= bytes.count - position else { throw ReadError.malformed }
            defer { position += count }
            return Data(bytes[position..<position + count])
        }
        mutating func integer(_ width: Int) throws -> Int {
            let raw = try take(width)
            return raw.enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        }
    }
}
