import Foundation

/// A version-gated, partial CPR reader for the typed Kontakt processor-state
/// child of a Plugin group. It never searches NIS signatures independently.
public enum CubaseKontaktStateReader {
    public enum ReadError: Error { case malformed, unsupported, limit }
    public static let maximumBytes = 64 * 1024 * 1024
    public struct PluginState: Sendable {
        public let uid: String
        public let name: String
        public let payload: Data
    }
    private static let kontaktUID = "5653544E694B386B6F6E74616B742038"
    private static let pluginMarker = Array("\u{7}Plugin\0\0\u{2}\0\u{6}".utf8)

    public static func read(_ data: Data) throws -> [KontaktStateReader.Result] {
        try readPluginStates(data).compactMap { state in
            guard state.uid == kontaktUID, state.name == "Kontakt 8" else { return nil }
            return try KontaktStateReader.read(state.payload)
        }
    }

    /// Complete typed Plugin descriptors only; payloads are never found by
    /// searching for signatures inside another plug-in's opaque state.
    public static func readPluginStates(_ data: Data) throws -> [PluginState] {
        guard data.count <= maximumBytes else { throw ReadError.limit }
        let bytes = Array(data)
        guard bytes.starts(with: Array("RIF2".utf8)),
              bytes.count >= 24, bytes[4...7].allSatisfy({ $0 == 0 }),
              bytes[12..<20].elementsEqual(Array("NUNDROOT".utf8)),
              bytes[8..<12].reduce(0, { ($0 << 8) | Int($1) }) == bytes.count - 16,
              (try? CubaseDiagnostics.parse(data).hostVersion) == "15.0.30" else { throw ReadError.unsupported }
        var results: [PluginState] = []
        var offset = 0
        while offset + pluginMarker.count <= bytes.count {
            guard bytes[offset..<(offset + pluginMarker.count)].elementsEqual(pluginMarker) else {
                offset += 1; continue
            }
            var parser = Cursor(bytes, offset)
            do {
                results.append(try parser.pluginState())
                // An opaque plugin blob may contain descriptor-like bytes; never
                // scan inside a state that was already reached by typed ownership.
                offset = max(offset + 1, parser.offset)
            } catch { offset += pluginMarker.count }
            guard results.count <= 4096 else { throw ReadError.limit }
        }
        return results
    }

    private struct Cursor {
        let bytes: [UInt8]
        var offset: Int
        init(_ bytes: [UInt8], _ offset: Int) { self.bytes = bytes; self.offset = offset }
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset <= bytes.count, count <= bytes.count - offset else { throw ReadError.malformed }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }
        mutating func number(_ count: Int) throws -> Int {
            let raw = try take(count)
            var value: UInt64 = 0
            for byte in raw { value = (value << 8) | UInt64(byte) }
            guard value <= Int.max else { throw ReadError.limit }
            return Int(value)
        }
        mutating func padding() throws {
            guard try take(3) == [0, 0, 0] else { throw ReadError.malformed }
        }
        mutating func key(_ expected: String) throws {
            let count = try number(1)
            guard count == expected.utf8.count + 1,
                  try take(count) == Array(expected.utf8) + [0] else { throw ReadError.malformed }
        }
        mutating func kind(_ first: Int, _ second: Int? = nil) throws {
            guard try number(2) == first else { throw ReadError.malformed }
            if let second { guard try number(2) == second else { throw ReadError.malformed } }
        }
        mutating func string(_ keyName: String) throws -> String {
            try key(keyName); try kind(8)
            let size = try number(4)
            guard size <= 1024 else { throw ReadError.limit }
            let raw = try take(size)
            try padding()
            guard let end = raw.firstIndex(of: 0),
                  let value = String(bytes: raw[..<end], encoding: .utf8) else { throw ReadError.malformed }
            return value
        }
        mutating func scalar(_ keyName: String) throws {
            try key(keyName); try kind(1)
            _ = try take(8); try padding()
        }
        mutating func numbers(_ keyName: String, expected: Int? = nil, pad: Bool = true) throws {
            try key(keyName); try kind(2, 2)
            let count = try number(4)
            guard count <= 64, expected == nil || count == expected else { throw ReadError.limit }
            _ = try take(count * 8)
            if pad { try padding() }
        }
        mutating func names(_ keyName: String) throws {
            try key(keyName); try kind(2, 4)
            let count = try number(4)
            guard count <= 64 else { throw ReadError.limit }
            try padding()
            for _ in 0..<count {
                let size = try number(1)
                guard size <= 128 else { throw ReadError.limit }
                _ = try take(size); try padding()
            }
        }
        mutating func arrangement() throws {
            try key("Audio Output Arrangement"); try kind(2, 5)
            let count = try number(4)
            guard count <= 64 else { throw ReadError.limit }
            for _ in 0..<count {
                guard try number(4) == 1 else { throw ReadError.malformed }
                try padding()
                try numbers("Type", expected: 2, pad: false)
            }
            try padding()
        }
        mutating func skipObject(depth: Int) throws {
            guard depth < 16 else { throw ReadError.limit }
            let classLength = try number(4)
            guard (1...128).contains(classLength), (try take(classLength)).last == 0 else { throw ReadError.malformed }
            _ = try take(8) // document-local object identity
            let count = try number(4)
            guard count <= 256 else { throw ReadError.limit }
            try padding()
            for index in 0..<count { try skipField(depth: depth + 1, arrayElement: index == count - 1) }
        }
        mutating func skipField(depth: Int, arrayElement: Bool = false) throws {
            guard depth < 16 else { throw ReadError.limit }
            let nameLength = try number(1)
            guard (1...128).contains(nameLength), (try take(nameLength)).last == 0 else { throw ReadError.malformed }
            let type = try number(2)
            switch type {
            case 1:
                _ = try take(8); if !arrayElement { try padding() }
            case 8:
                let length = try number(4)
                guard length <= 1_048_576 else { throw ReadError.limit }
                _ = try take(length); if !arrayElement { try padding() }
            case 2:
                let subtype = try number(2)
                switch subtype {
                case 2:
                    let count = try number(4)
                    guard count <= 256 else { throw ReadError.limit }
                    _ = try take(count * 8)
                    if !arrayElement { try padding() }
                case 4:
                    let count = try number(4)
                    guard count <= 256 else { throw ReadError.limit }
                    try padding()
                    for _ in 0..<count {
                        let length = try number(1)
                        guard length <= 128 else { throw ReadError.limit }
                        _ = try take(length); try padding()
                    }
                case 5:
                    let count = try number(4)
                    guard count <= 256 else { throw ReadError.limit }
                    for _ in 0..<count {
                        let children = try number(4)
                        guard children <= 64 else { throw ReadError.limit }
                        try padding()
                        for _ in 0..<children { try skipField(depth: depth + 1, arrayElement: true) }
                    }
                    try padding()
                case 6:
                    let count = try number(4)
                    guard count <= 256 else { throw ReadError.limit }
                    try padding()
                    for _ in 0..<count { try skipField(depth: depth + 1) }
                case 7:
                    let length = try number(4)
                    guard length <= CubaseKontaktStateReader.maximumBytes else { throw ReadError.limit }
                    _ = try take(length); try padding()
                case 20:
                    try skipObject(depth: depth + 1)
                    if !arrayElement { try padding() }
                case 201:
                    let count = try number(4)
                    guard count <= 256 else { throw ReadError.limit }
                    for _ in 0..<count {
                        guard try number(2) == 20 else { throw ReadError.malformed }
                        try skipObject(depth: depth + 1)
                    }
                    if !arrayElement { try padding() }
                default: throw ReadError.unsupported
                }
            default: throw ReadError.unsupported
            }
        }
        mutating func pluginState() throws -> PluginState {
            try key("Plugin"); try kind(2, 6)
            let count = try number(4)
            guard count >= 2, count <= 128 else { throw ReadError.malformed }
            try padding()
            try key("Plugin UID"); try kind(2, 6)
            guard try number(4) == 1 else { throw ReadError.malformed }
            try padding()
            let uid = try string("GUID")
            let name = try string("Plugin Name")
            var payload: Data?
            for _ in 1..<count {
                let start = offset
                let keyLength = try number(1)
                guard (1...128).contains(keyLength) else { throw ReadError.malformed }
                let field = try take(keyLength)
                if field == Array("audioComponent".utf8) + [0] {
                    guard payload == nil else { throw ReadError.malformed }
                    try kind(2, 7)
                    let length = try number(4)
                    guard length <= CubaseKontaktStateReader.maximumBytes else { throw ReadError.limit }
                    payload = Data(try take(length))
                    try padding()
                } else {
                    offset = start
                    try skipField(depth: 1)
                }
            }
            guard let payload else { throw ReadError.malformed }
            return PluginState(uid: uid, name: name, payload: payload)
        }
    }
}
