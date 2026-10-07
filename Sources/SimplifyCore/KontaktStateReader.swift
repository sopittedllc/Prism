import Foundation
import CFastLZ

/// Reads public metadata from Kontakt's NIS processor-state envelope.
/// IDs are saved-state candidates. They do not identify an individual patch or a
/// load time, and must never be promoted directly to Last used.
public enum KontaktStateReader {
    public struct Result: Sendable, Equatable {
        public let libraryIDs: [String]
        public let opaquePayloads: Int
        /// Proven zero-slot saved rack. Missing IDs alone never establish this.
        public let emptyRack: Bool
    }
    public enum ReadError: Error { case malformed, unsupported, limit }
    public static let maximumBytes = 16 * 1024 * 1024

    public static func read(_ data: Data) throws -> Result {
        guard data.count <= maximumBytes else { throw ReadError.limit }
        var decoder = Decoder()
        try decoder.item(Array(data), depth: 0)
        return Result(libraryIDs: decoder.ids.sorted(), opaquePayloads: decoder.opaque,
                      emptyRack: decoder.ids.isEmpty && decoder.opaque == 0 && decoder.racks > 0 && !decoder.nonemptyRack)
    }

    private struct Decoder {
        var ids = Set<String>()
        var opaque = 0
        var racks = 0
        var nonemptyRack = false
        var nodes = 0
        var totalBytes = 0

        mutating func item(_ bytes: [UInt8], depth: Int) throws {
            try account(bytes.count, depth: depth)
            var r = Cursor(bytes)
            guard try r.number(8) == bytes.count, try r.number(4) == 1,
                  try r.take(4) == Array("hsin".utf8) else { throw ReadError.malformed }
            _ = try r.take(24)
            try properties(try r.sizedBlock(), depth: depth + 1)
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            let count = try r.number(4)
            guard count <= 1024 else { throw ReadError.limit }
            for _ in 0..<count {
                _ = try r.take(12)
                try item(try r.sizedBlock(), depth: depth + 1)
            }
            guard r.finished else { throw ReadError.malformed }
        }

        mutating func properties(_ bytes: [UInt8], depth: Int) throws {
            try account(bytes.count, depth: depth)
            var r = Cursor(bytes)
            guard try r.number(8) == bytes.count else { throw ReadError.malformed }
            let domain = try r.take(4), type = try r.number(4)
            guard try r.number(4) == 1 else { throw ReadError.unsupported }
            if type != 1 { try properties(try r.sizedBlock(), depth: depth + 1) }
            let payload = try r.take(r.remaining)
            guard domain == Array("DSIN".utf8) else { return }
            if type == 106 { try libraryMetadata(payload) }
            if type == 109 { try rackMetadata(payload) }
            if type == 115 {
                var p = Cursor(payload)
                guard try p.number(4) == 1 else { throw ReadError.unsupported }
                let encoding = try p.number(1)
                if encoding == 0 {
                    try item(try p.take(p.remaining), depth: depth + 1)
                } else if encoding == 1 {
                    guard p.remaining >= 8 else { opaque += 1; return }
                    let expanded = try p.number(4), compressed = try p.number(4)
                    guard compressed > 0, compressed == p.remaining else { opaque += 1; return }
                    // A large/protected state is still opaque; public IDs in its
                    // surrounding envelope remain usable. Decode only small racks
                    // needed to prove the observed zero-slot default.
                    guard expanded >= 8, expanded <= 1_048_576 else { opaque += 1; return }
                    let input = try p.take(compressed)
                    var output = [UInt8](repeating: 0, count: expanded)
                    let decoded = input.withUnsafeBytes { source in
                        output.withUnsafeMutableBytes { target in
                            fastlz_decompress(source.baseAddress, Int32(compressed), target.baseAddress, Int32(expanded))
                        }
                    }
                    guard decoded == expanded else { opaque += 1; return }
                    try item(output, depth: depth + 1)
                } else { throw ReadError.unsupported }
            }
        }

        mutating func rackMetadata(_ bytes: [UInt8]) throws {
            var p = Cursor(bytes)
            guard try p.number(4) == 1 else { return }
            _ = try p.number(4) // dictionary type
            guard try p.number(4) == 1 else { return }
            let size = try p.number(4)
            _ = try p.number(4) // dictionary reference
            guard size <= p.remaining - 8 else { return }
            var chunks = Cursor(try p.take(size))
            while !chunks.finished {
                let id = try chunks.number(2), length = try chunks.number(4)
                let body = try chunks.take(length)
                guard id == 0x03 else { continue }
                var bank = Cursor(body)
                guard try bank.number(1) == 1 else { continue }
                _ = try bank.number(2)
                try bank.skip(try bank.number(4)) // private bytes
                try bank.skip(try bank.number(4)) // public bytes
                var children = Cursor(try bank.take(try bank.number(4)))
                guard bank.finished else { continue }
                while !children.finished {
                    let childID = try children.number(2), count = try children.number(4)
                    let child = try children.take(count)
                    guard childID == 0x37, child.count >= 8 else { continue }
                    var slots = Cursor(child)
                    let flags = try slots.number(8)
                    racks += 1
                    if flags != 0 || !slots.finished { nonemptyRack = true }
                }
            }
        }

        mutating func account(_ byteCount: Int, depth: Int) throws {
            guard depth < 24, nodes < 4096,
                  byteCount >= 0, totalBytes <= maximumBytes * 4 - byteCount else {
                throw ReadError.limit
            }
            nodes += 1
            totalBytes += byteCount
        }

        mutating func libraryMetadata(_ bytes: [UInt8]) throws {
            // Observed public metadata v1: four header fields, then a UTF-16
            // product ID and twelve reserved/checksum bytes. Other shapes are
            // not interpreted as identifiers.
            guard bytes.count >= 32 else { return }
            var r = Cursor(bytes)
            guard try r.number(4) == 1, try r.number(4) == 1,
                  try r.number(4) == 1, try r.number(4) == 1 else { return }
            let count = try r.number(4)
            guard (1...64).contains(count), r.remaining == count * 2 + 12 else { return }
            let raw = Data(try r.take(count * 2))
            guard let id = String(data: raw, encoding: .utf16LittleEndian),
                  id.data(using: .utf16LittleEndian) == raw,
                  id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return }
            ids.insert(id)
        }
    }

    private struct Cursor {
        let bytes: [UInt8]
        var offset = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        var remaining: Int { bytes.count - offset }
        var finished: Bool { remaining == 0 }
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= remaining else { throw ReadError.malformed }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }
        mutating func skip(_ count: Int) throws { _ = try take(count) }
        mutating func number(_ width: Int) throws -> Int {
            let raw = try take(width)
            var value: UInt64 = 0
            for (i, b) in raw.enumerated() { value |= UInt64(b) << (8 * i) }
            guard value <= UInt64(Int.max) else { throw ReadError.limit }
            return Int(value)
        }
        mutating func sizedBlock() throws -> [UInt8] {
            let start = offset
            let size = try number(8)
            guard size >= 8, size <= bytes.count - start else { throw ReadError.malformed }
            offset = start
            return try take(size)
        }
    }
}
