import Foundation

/// Only the versioned SINE state owned by a typed Cubase Plugin descriptor.
public enum SINESavedStateReader {
    public static let cubaseUID = "5653545933353573696E6520706C6179"

    public static func instrumentIDs(_ payload: Data) -> [String]? {
        guard payload.count <= CubaseKontaktStateReader.maximumBytes else { return nil }
        let bytes = [UInt8](payload)
        let marker = [UInt8]("\"fileFormatVersion\"".utf8)
        var results: [[String]] = []
        for index in bytes.indices where index + marker.count <= bytes.count &&
            bytes[index..<(index + marker.count)].elementsEqual(marker) {
            guard let start = ((max(0, index - 64))..<index).last(where: { bytes[$0] == 123 }),
                  let end = jsonEnd(bytes, from: start), end - start <= 1_048_576,
                  let object = try? JSONSerialization.jsonObject(with: Data(bytes[start..<end])) as? [String: Any],
                  object["instanceName"] as? String == "SINE Player",
                  object["fileFormatVersion"] as? String == "1.0",
                  object["samplerVersion"] as? String == "1.4.2" else { continue }
            let entries = object["instruments"] as? [[String: Any]] ?? []
            guard object["instruments"] == nil || object["instruments"] is [[String: Any]],
                  entries.count <= 256 else { return nil }
            var ids: [String] = []
            for entry in entries {
                guard let id = entry["id"] as? String, !id.isEmpty, id.utf8.count <= 64,
                      let title = entry["title"] as? String, !title.isEmpty else { return nil }
                ids.append(id)
            }
            results.append(ids)
        }
        return results.count == 1 ? results[0] : nil
    }

    private static func jsonEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var depth = 0, quoted = false, escaped = false
        for index in start..<min(bytes.count, start + 1_048_576) {
            let byte = bytes[index]
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 { depth += 1 }
            else if byte == 125 {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
        }
        return nil
    }
}
