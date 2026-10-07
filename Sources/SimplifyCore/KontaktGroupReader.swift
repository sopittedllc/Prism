import Foundation
import CFastLZ

/// Reads only public group names from a length-delimited Kontakt NIS instrument.
/// Names are source metadata, not articulation or playability evidence. File reads
/// skip private data and sample/script payloads; malformed or protected branches
/// throw instead of returning a partial result.
public enum KontaktGroupReader {
    public struct Result: Codable, Sendable, Equatable {
        public let groupNames: [String]
        /// Authoring Kontakt version, if a supported public authoring chunk exists.
        public let sourceVersion: String?
    }
    public enum ReadError: Error, Equatable { case malformed, unsupported, limit, cancelled }

    private static let maximumFileBytes = 256 * 1024 * 1024
    private static let maximumSubtreeBytes = 32 * 1024 * 1024
    private static let maximumGroups = 8192

    /// The caller owns the file. Parsing performs bounded random-access reads and
    /// never loads the complete instrument or extracts private/audio/script data.
    public static func read(_ url: URL) throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        guard length <= maximumFileBytes else { throw ReadError.limit }
        var parser = Parser(source: .file(handle, Int(length)))
        return try parser.parse()
    }

    /// Bounded in-memory entry point for synthetic fixtures and embedded NIS data.
    public static func read(_ data: Data) throws -> Result {
        guard data.count <= maximumSubtreeBytes else { throw ReadError.limit }
        var parser = Parser(source: .memory(data))
        return try parser.parse()
    }

    private enum Source {
        case file(FileHandle, Int)
        case memory(Data)
        var count: Int {
            switch self { case .file(_, let size): size; case .memory(let data): data.count }
        }
        func bytes(at offset: Int, count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset <= self.count, count <= self.count - offset else { throw ReadError.malformed }
            switch self {
            case .file(let handle, _):
                try handle.seek(toOffset: UInt64(offset))
                guard let data = try handle.read(upToCount: count), data.count == count else { throw ReadError.malformed }
                return data
            case .memory(let data): return data.subdata(in: offset..<offset + count)
            }
        }
    }

    private struct Cursor {
        let source: Source
        var pos: Int
        let end: Int
        var remaining: Int { end - pos }
        var finished: Bool { pos == end }
        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, count <= remaining else { throw ReadError.malformed }
            defer { pos += count }
            return try source.bytes(at: pos, count: count)
        }
        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= remaining else { throw ReadError.malformed }
            pos += count
        }
        mutating func number(_ width: Int) throws -> Int {
            let raw = try bytes(width)
            var value: UInt64 = 0
            for (i, b) in raw.enumerated() { value |= UInt64(b) << (8 * i) }
            guard value <= UInt64(Int.max) else { throw ReadError.limit }
            return Int(value)
        }
        mutating func ascii(_ expected: String) throws -> Bool { try bytes(expected.utf8.count) == Data(expected.utf8) }
        mutating func child(_ length: Int) throws -> Cursor {
            guard length >= 0, length <= remaining else { throw ReadError.malformed }
            let child = Cursor(source: source, pos: pos, end: pos + length)
            pos += length
            return child
        }
        mutating func block64() throws -> Cursor {
            let start = pos
            let size = try number(8)
            guard size >= 8, size <= end - start else { throw ReadError.malformed }
            pos = start + size
            return Cursor(source: source, pos: start + 8, end: start + size)
        }
        mutating func utf16(maximumUnits: Int) throws -> String {
            let count = try number(4)
            guard count <= maximumUnits, count <= remaining / 2 else { throw ReadError.limit }
            let raw = try bytes(count * 2)
            guard let name = String(data: raw, encoding: .utf16LittleEndian),
                  name.data(using: .utf16LittleEndian) == raw else { throw ReadError.malformed }
            return name
        }
    }

    private struct Parser {
        let source: Source
        var groupNames: [String] = []
        var sourceVersion: String?
        var nodes = 0
        var presets = 0
        var groupLists = 0
        var expandedBytes = 0

        mutating func parse() throws -> Result {
            var root = Cursor(source: source, pos: 0, end: source.count)
            try item(&root, depth: 0)
            guard root.finished, presets > 0, groupLists == 1 else { throw ReadError.unsupported }
            return Result(groupNames: groupNames, sourceVersion: sourceVersion)
        }
        mutating func account(depth: Int) throws {
            if Task<Never, Never>.isCancelled { throw ReadError.cancelled }
            guard depth < 32, nodes < 16384 else { throw ReadError.limit }
            nodes += 1
        }
        mutating func item(_ outer: inout Cursor, depth: Int) throws {
            try account(depth: depth)
            var r = try outer.block64()
            guard try r.number(4) == 1, try r.ascii("hsin") else { throw ReadError.unsupported }
            try r.skip(24)
            try dataChunk(&r, depth: depth + 1)
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            let children = try r.number(4)
            guard children <= 4096 else { throw ReadError.limit }
            for _ in 0..<children {
                try r.skip(12) // index, domain and child type
                try item(&r, depth: depth + 1)
            }
            guard r.finished else { throw ReadError.malformed }
        }
        mutating func dataChunk(_ outer: inout Cursor, depth: Int) throws {
            try account(depth: depth)
            var r = try outer.block64()
            let domain = try r.bytes(4)
            let type = try r.number(4)
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            if type != 1 { try dataChunk(&r, depth: depth + 1) }
            guard domain == Data("DSIN".utf8) else { return }
            switch type {
            case 101: try authoring(&r)
            case 109: try preset(&r)
            case 115: try subtree(&r, depth: depth + 1)
            default: break // Authorization, private data and other unrelated chunks.
            }
        }
        mutating func authoring(_ r: inout Cursor) throws {
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            _ = try r.number(1) // compression indication, not a decoder instruction here
            guard try r.number(4) == 2, try r.number(4) == 1 else { throw ReadError.unsupported }
            let version = try r.utf16(maximumUnits: 64)
            guard r.finished, !version.isEmpty else { throw ReadError.malformed }
            if let sourceVersion, sourceVersion != version { throw ReadError.unsupported }
            sourceVersion = version
        }
        mutating func subtree(_ r: inout Cursor, depth: Int) throws {
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            let compression = try r.number(1)
            switch compression {
            case 0: try item(&r, depth: depth + 1)
            case 1:
                let uncompressed = try r.number(4), compressed = try r.number(4)
                guard uncompressed >= 8, uncompressed <= KontaktGroupReader.maximumSubtreeBytes,
                      compressed > 0, compressed <= KontaktGroupReader.maximumSubtreeBytes,
                      compressed <= r.remaining,
                      expandedBytes <= KontaktGroupReader.maximumSubtreeBytes - uncompressed else { throw ReadError.limit }
                let input = try r.bytes(compressed)
                var output = Data(count: uncompressed)
                let decoded = input.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        fastlz_decompress(inputBytes.baseAddress, Int32(compressed), outputBytes.baseAddress, Int32(uncompressed))
                    }
                }
                guard decoded == uncompressed else { throw ReadError.unsupported }
                expandedBytes += uncompressed
                var nested = Cursor(source: .memory(output), pos: 0, end: output.count)
                try item(&nested, depth: depth + 1)
                guard nested.finished else { throw ReadError.malformed }
            default: throw ReadError.unsupported
            }
            guard r.finished else { throw ReadError.malformed }
        }
        mutating func preset(_ r: inout Cursor) throws {
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            _ = try r.number(4) // dictionary type
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            let size = try r.number(4)
            _ = try r.number(4) // dictionary reference
            guard r.remaining >= 8, size <= r.remaining - 8 else { throw ReadError.malformed }
            var chunks = try r.child(size)
            try r.skip(8) // padding and trailer
            guard r.finished else { throw ReadError.malformed }
            presets += 1
            guard presets <= 8 else { throw ReadError.limit }
            try presetChunks(&chunks, depth: 0)
        }
        mutating func presetChunks(_ r: inout Cursor, depth: Int) throws {
            try account(depth: depth)
            while !r.finished {
                try account(depth: depth + 1)
                guard r.remaining >= 6 else { throw ReadError.malformed }
                let id = try r.number(2), size = try r.number(4)
                var chunk = try r.child(size)
                if id == 0x28 { try program(&chunk, depth: depth + 1) }
            }
        }
        mutating func program(_ r: inout Cursor, depth: Int) throws {
            let children = try structure(&r, depth: depth)
            var nested = children
            while !nested.finished {
                try account(depth: depth + 1)
                guard nested.remaining >= 6 else { throw ReadError.malformed }
                let id = try nested.number(2), size = try nested.number(4)
                var chunk = try nested.child(size)
                if id == 0x33 { try groupList(&chunk, depth: depth + 1) }
            }
        }
        mutating func structure(_ r: inout Cursor, depth: Int) throws -> Cursor {
            try account(depth: depth)
            guard try r.number(1) == 1 else { throw ReadError.unsupported }
            _ = try r.number(2) // version; only public structure envelope is read
            try r.skip(try r.number(4)) // private bytes
            try r.skip(try r.number(4)) // public bytes; group extracts its own name
            let children = try r.child(try r.number(4))
            guard r.finished else { throw ReadError.malformed }
            return children
        }
        mutating func groupList(_ r: inout Cursor, depth: Int) throws {
            groupLists += 1
            guard groupLists == 1 else { throw ReadError.unsupported }
            let count = try r.number(4)
            guard count <= KontaktGroupReader.maximumGroups else { throw ReadError.limit }
            for _ in 0..<count {
                try account(depth: depth)
                guard try r.number(1) == 1 else { throw ReadError.unsupported }
                let version = try r.number(2)
                guard version <= 0x9c else { throw ReadError.unsupported }
                try r.skip(try r.number(4))
                let publicBytes = try r.number(4)
                var publicCursor = try r.child(publicBytes)
                let name = try publicCursor.utf16(maximumUnits: 1024)
                guard !name.isEmpty else { throw ReadError.malformed }
                groupNames.append(name)
                try r.skip(try r.number(4)) // child chunks, never interpreted
            }
            guard r.finished else { throw ReadError.malformed }
        }
    }
}
