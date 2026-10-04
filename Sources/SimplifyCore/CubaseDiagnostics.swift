import CryptoKit
import Foundation

/// An unresolved byte-level descriptor, not a current instance or asset association.
public struct CubaseDescriptorCandidate: Codable, Sendable, Equatable {
    public let byteOffset: Int
    public let uid: String
    public let name: String
}

/// Ephemeral diagnostic output. It is deliberately separate from ProjectReport and
/// persistent catalog evidence: global records do not establish active ownership.
public struct CubaseDiagnosticReport: Encodable, Sendable {
    public let adapterVersion: Int
    public let coverage: String
    public let hostVersion: String
    public let inputSHA256: String
    public let descriptors: [CubaseDescriptorCandidate]
    public let limitations: [String]
}

public enum CubaseDiagnosticError: Error {
    case unsupportedHeader, unsupportedVersion, malformed, tooManyRecords, symbolicLink
}

/// Experimental CPR descriptor diagnostics using the length-token layout from
/// fgimian/cubase-project-plugins (pinned source/license in THIRD_PARTY_NOTICES.md).
/// No owner traversal, plugin execution, asset matching or usage-time inference.
public enum CubaseDiagnostics {
    public static let maximumInputBytes = ProjectReader.maximumInputBytes
    public static let maximumRecords = 4_096
    private static let uidMarker = Array("Plugin UID\0".utf8)
    private static let versionMarker = Array("PAppVersion\0".utf8)

    /// Synchronous read-only inspection of one regular file. Ancestor symlinks are
    /// checked before open (not atomic against concurrent path replacement); the final
    /// component uses O_NOFOLLOW. Bounded to 32 MiB; invalid input throws without output.
    public static func inspect(_ url: URL) throws -> CubaseDiagnosticReport {
        var ancestor = url
        while ancestor.path != "/" {
            if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CubaseDiagnosticError.symbolicLink
            }
            ancestor.deleteLastPathComponent()
        }
        return try parse(BoundedFile.read(url, limit: maximumInputBytes))
    }

    /// Pure, bounded diagnostic extraction for the observed Cubase 15.0.30 metadata.
    /// Repeated records are retained; count is not an instance count. A valid-looking
    /// record embedded in opaque state remains an unresolved diagnostic candidate.
    public static func parse(_ data: Data) throws -> CubaseDiagnosticReport {
        guard data.count <= maximumInputBytes else { throw ProjectReadError.tooLarge }
        let bytes = Array(data)
        let riff = Array("RIFF".utf8), rif2 = Array("RIF2".utf8)
        guard bytes.starts(with: riff) || bytes.starts(with: rif2) else {
            throw CubaseDiagnosticError.unsupportedHeader
        }
        let tokens = Tokens(bytes: bytes)
        guard let metadataOffset = find(versionMarker, in: bytes, from: 0),
              find(versionMarker, in: bytes, from: metadataOffset + versionMarker.count) == nil else {
            throw CubaseDiagnosticError.malformed
        }
        var index = metadataOffset + versionMarker.count + 9 + (bytes.starts(with: rif2) ? 4 : 0)
        let app = try tokens.read(at: &index); index += 3
        let version = try tokens.read(at: &index)
        guard app == "Cubase", version == "Version 15.0.30" else {
            throw CubaseDiagnosticError.unsupportedVersion
        }
        var descriptors: [CubaseDescriptorCandidate] = []
        var searchIndex = 0
        while let offset = find(uidMarker, in: bytes, from: searchIndex) {
            guard descriptors.count < maximumRecords else { throw CubaseDiagnosticError.tooManyRecords }
            searchIndex = offset + uidMarker.count
            index = searchIndex + 22
            let uid = try tokens.read(at: &index); index += 3
            guard uid.utf8.count == 32, uid.utf8.allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }), try tokens.read(at: &index) == "Plugin Name" else {
                throw CubaseDiagnosticError.malformed
            }
            index += 5
            var name = try tokens.read(at: &index); index += 3
            let nextKey = try tokens.read(at: &index)
            if nextKey == "Original Plugin Name" {
                index += 5
                name = try tokens.read(at: &index)
            }
            descriptors.append(CubaseDescriptorCandidate(byteOffset: offset, uid: uid, name: name))
        }
        return CubaseDiagnosticReport(
            adapterVersion: 1, coverage: "diagnostic-only", hostVersion: "15.0.30",
            inputSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            descriptors: descriptors,
            limitations: [
                "Global typed descriptor candidates only; current ownership and successful loading are unverified.",
                "Matching records in opaque state cannot be distinguished; counts are not instance counts.",
                "No installed-asset, sample or Kontakt instrument identity is established.",
                "No usage timestamp or absence inference; output is excluded from catalog and cleanup evidence.",
            ])
    }

    // Linear scan with a constant-size marker; no recursive decoding or unbounded strings.
    private static func find(_ marker: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard start >= 0, bytes.count >= marker.count, start <= bytes.count - marker.count else { return nil }
        for index in start...(bytes.count - marker.count) where bytes[index] == marker[0] {
            if bytes[index..<(index + marker.count)].elementsEqual(marker) { return index }
        }
        return nil
    }

    private struct Tokens {
        let bytes: [UInt8]
        func read(at index: inout Int) throws -> String {
            guard bytes.indices.contains(index) else { throw CubaseDiagnosticError.malformed }
            let length = Int(bytes[index])
            let start = index + 1
            guard length > 0, length <= bytes.count - start else { throw CubaseDiagnosticError.malformed }
            let end = start + length
            let payload = bytes[start..<end].prefix(while: { $0 != 0 })
            guard let string = String(bytes: payload, encoding: .utf8),
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CubaseDiagnosticError.malformed
            }
            index = end
            return string
        }
    }
}
