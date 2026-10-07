import Foundation

/// Observed Pro Tools PTX plug-in list only. Other PTX structures remain opaque.
public enum ProToolsSavedPluginReader {
    public struct Entry: Codable, Sendable, Equatable {
        public let name: String
        public let effectID: String
    }
    public static let maximumBytes = 64 * 1024 * 1024

    public static func read(_ data: Data) -> [Entry]? {
        guard (20..<maximumBytes).contains(data.count), data[18] == 5, data[17] == 0 else { return nil }
        let inverse = 163 // 11 * 163 == 1 (mod 256)
        let delta = (256 - Int(data[19]) * inverse % 256) % 256
        var bytes = [UInt8](data)
        for index in 20..<bytes.count {
            bytes[index] ^= UInt8(truncatingIfNeeded: (index >> 12) * delta)
        }
        func number(_ offset: Int, _ width: Int) -> Int? {
            guard offset >= 0, offset <= bytes.count - width else { return nil }
            var result = 0
            for shift in 0..<width { result |= Int(bytes[offset + shift]) << (8 * shift) }
            return result
        }
        var position = 20
        var lists: [[Entry]] = []
        while position < bytes.count {
            guard bytes[position] == 0x5a, let blockType = number(position + 1, 2),
                  let size = number(position + 3, 4), size >= 2,
                  size <= bytes.count - position - 7 else { return nil }
            if blockType == 1, number(position + 7, 2) == 0x1018 {
                guard lists.isEmpty, let count = number(position + 9, 4), count <= 4096 else { return nil }
                let limit = position + 7 + size
                var child = position + 13
                var entries: [Entry] = []
                for _ in 0..<count {
                    guard child + 9 <= limit, bytes[child] == 0x5a,
                          let type = number(child + 1, 2), [6, 9].contains(type),
                          let length = number(child + 3, 4), length >= 25,
                          length <= limit - child - 7,
                          number(child + 7, 2) == 0x1017 else { return nil }
                    let end = child + 7 + length
                    let role = bytes[child + 9]
                    guard let nameLength = number(child + 10, 4), nameLength > 0,
                          nameLength <= 1024, child + 14 + nameLength + 23 <= end,
                          let name = String(bytes: bytes[(child + 14)..<(child + 14 + nameLength)], encoding: .utf8),
                          !name.isEmpty else { return nil }
                    let effectLengthAt = child + 14 + nameLength + 12 + 7
                    guard let effectLength = number(effectLengthAt, 4), effectLength > 0,
                          effectLength <= 1024, effectLengthAt + 4 + effectLength <= end,
                          let effect = String(bytes: bytes[(effectLengthAt + 4)..<(effectLengthAt + 4 + effectLength)], encoding: .utf8),
                          effect.hasPrefix("com."), !effect.contains("\0") else { return nil }
                    if role == 3 { entries.append(Entry(name: name, effectID: effect)) }
                    else if role != 4 { return nil }
                    child = end
                }
                guard child == limit else { return nil }
                lists.append(entries)
            }
            position += 7 + size
        }
        return lists.count == 1 ? lists[0] : nil
    }
}
