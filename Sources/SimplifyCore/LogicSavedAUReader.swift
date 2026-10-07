import Foundation

/// Saved AU plist references in the observed Logic ProjectData container.
/// These are saved references; they do not claim current track or playback state.
public enum LogicSavedAUReader {
    public struct Reference: Codable, Sendable, Equatable, Hashable {
        public let type: String
        public let subtype: String
        public let manufacturer: String
        public var identity: String { "\(type)/\(subtype)/\(manufacturer)" }
    }
    public struct Result: Sendable {
        public let references: [Reference]
        public let kontaktStates: [KontaktSavedState]
    }

    public static func read(_ data: Data) -> Result? {
        guard data.count <= ProjectReader.maximumInputBytes,
              data.starts(with: [0x23, 0x47, 0xc0, 0xab, 0xd1, 0x09]),
              data.count > 52,
              data[24..<28].elementsEqual(Array("gnoS".utf8)) else { return nil }
        let opener = Data("<?xml version".utf8), closer = Data("</plist>".utf8)
        var position = 28, count = 0
        var references: [Reference] = []
        var kontaktStates: [KontaktSavedState] = []
        while let start = data.range(of: opener, in: position..<data.count)?.lowerBound {
            guard count < 4096, let close = data.range(of: closer, in: start..<data.count),
                  close.upperBound - start <= 16 * 1024 * 1024 else { return nil }
            let xml = data[start..<close.upperBound]
            guard xml.range(of: Data("<!ENTITY".utf8)) == nil,
                  xml.range(of: Data("<!DOCTYPE plist SYSTEM".utf8)) == nil,
                  let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else { return nil }
            if let type = fourCC(plist["type"]), let subtype = fourCC(plist["subtype"]),
               let maker = fourCC(plist["manufacturer"]) {
                let reference = Reference(type: type, subtype: subtype, manufacturer: maker)
                references.append(reference)
                if reference.identity == "aumu/NiK8/-NI-", let state = plist["vstdata"] as? Data,
                   let parsed = try? KontaktStateReader.read(state) {
                    kontaktStates.append(KontaktSavedState(instanceOrdinal: count,
                        libraryIDs: parsed.libraryIDs, opaquePayloads: parsed.opaquePayloads,
                        emptyRack: parsed.emptyRack))
                }
            }
            count += 1; position = close.upperBound
        }
        return Result(references: Array(Set(references)).sorted { $0.identity < $1.identity },
                      kontaktStates: kontaktStates)
    }

    private static func fourCC(_ value: Any?) -> String? {
        guard let number = value as? NSNumber,
              number.int64Value >= 0, number.int64Value <= UInt32.max else { return nil }
        let raw = UInt32(number.uint32Value)
        let bytes = [UInt8(truncatingIfNeeded: raw >> 24), UInt8(truncatingIfNeeded: raw >> 16),
                     UInt8(truncatingIfNeeded: raw >> 8), UInt8(truncatingIfNeeded: raw)]
        guard bytes.allSatisfy({ (32...126).contains($0) }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}
