import CryptoKit
import Foundation

/// A saved reference within an exported track slot; no installed-asset association.
public struct CubaseArchivePlugin: Encodable, Sendable, Equatable {
    public let role: String
    public let name: String
    public let uid: String
}

/// Ordinal is document-local, not a persistent track ID. Equal names remain separate.
public struct CubaseArchiveTrack: Encodable, Sendable {
    public let ordinal: Int
    public let name: String
    public let plugins: [CubaseArchivePlugin]
}

public struct CubaseTrackArchiveReport: Encodable, Sendable {
    public let adapterVersion: Int
    public let coverage: String
    public let inputSHA256: String
    public let tracks: [CubaseArchiveTrack]
    public let unsupportedTrackCount: Int
    public let limitations: [String]
}

/// Reads only the direct audio/instrument/group owner paths observed in Cubase 15.0.30
/// tracklist2 exports. Archives have no verified host-version field. They do not
/// establish whole-project coverage, successful loads, asset identity or use time.
public enum CubaseTrackArchiveReader {
    public static let maximumInputBytes = ProjectReader.maximumInputBytes
    public static let maximumDepth = 64
    public static let maximumElements = 100_000
    public static let maximumTracks = 4_096
    public static let maximumReferences = 4_096

    /// Read-only regular-file inspection. Ancestor checks are preflight, not atomic
    /// traversal; BoundedFile protects the final component with O_NOFOLLOW.
    public static func inspect(_ url: URL) throws -> CubaseTrackArchiveReport {
        var ancestor = url
        while ancestor.path != "/" {
            if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CubaseDiagnosticError.symbolicLink
            }
            ancestor.deleteLastPathComponent()
        }
        return try parse(BoundedFile.read(url, limit: maximumInputBytes))
    }

    /// UTF-8 XML without DTDs; bounded input, depth, elements, owners and references.
    /// Invalid supported records fail the whole report without salvaging a subset.
    public static func parse(_ data: Data) throws -> CubaseTrackArchiveReport {
        guard data.count <= maximumInputBytes else { throw ProjectReadError.tooLarge }
        guard let text = String(data: data, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else {
            throw ProjectReadError.malformed
        }
        // A byte-valid UTF-8 document must not ask XMLParser to reinterpret bytes
        // under another encoding (which could silently alter names).
        let declaration = try NSRegularExpression(pattern: "(?i)<\\?xml\\s[^?]*\\bencoding\\s*=\\s*[\"']([^\"']+)")
        if let match = declaration.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text), text[range].lowercased() != "utf-8" {
            throw ProjectReadError.malformed
        }
        let delegate = ArchiveDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil, !delegate.rejected,
              delegate.validRoot, delegate.hasTrackList, delegate.stack.isEmpty else {
            throw ProjectReadError.malformed
        }
        return CubaseTrackArchiveReport(
            adapterVersion: 2, coverage: "partial-export",
            inputSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            tracks: delegate.tracks, unsupportedTrackCount: delegate.unsupportedTracks,
            limitations: [
                "Selected exported tracks only; no association to a current project or whole-project coverage.",
                "Only direct audio/instrument/group inserts and instrument slots are covered; unsupported structures are excluded.",
                "Output-channel inserts were omitted by the tested host export even when selected; whole-project dependencies are incomplete.",
                "Empty slots or omitted tracks never establish that a plugin is unused.",
                "Bypass, successful loading, installed assets, samples and Kontakt instrument identities are unverified.",
                "No usage timestamp; export time is not Last used. This report is not catalog or cleanup evidence.",
                "Observed tracklist2 layout only; the archive has no verified host-version field.",
            ])
    }
}

private final class ArchiveDelegate: NSObject, XMLParserDelegate {
    struct Frame {
        let tag: String
        let name: String?
        let kind: String?
        let type: String?
        func isNode(_ tag: String, _ name: String? = nil) -> Bool {
            self.tag == tag && (name == nil || self.name == name)
        }
    }
    struct Owner {
        let ordinal: Int
        let deviceClass: String
        var instrument: Bool { deviceClass == "MInstrumentTrack" }
        var requiresGroupSignature: Bool { deviceClass == "MTrack" }
        var groupSignature: [String: String] = [:]
        var name: String?
        var seen: Set<String> = []
        var plugins: [CubaseArchivePlugin] = []
    }
    struct Plugin {
        let depth: Int
        let role: String
        var fields: [String: String] = [:]
        var hasUIDMember = false
    }
    var stack: [Frame] = []
    var tracks: [CubaseArchiveTrack] = []
    var unsupportedTracks = 0
    var rejected = false
    var validRoot = false
    var hasTrackList = false
    private var owner: Owner?
    private var plugin: Plugin?
    private var trackCount = 0
    private var references = 0
    private var elements = 0

    private func reject(_ parser: XMLParser) { rejected = true; parser.abortParsing() }
    private func unique(_ key: String, parser: XMLParser) -> Bool {
        guard owner?.seen.insert(key).inserted == true else { reject(parser); return false }
        return true
    }
    private func textValue(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 1_024,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    private var inTrackList: Bool {
        stack.count >= 2 && stack[0].tag == "tracklist2" && stack[1].isNode("list", "track") && stack[1].type == "obj"
    }
    private var inDevice: Bool {
        guard owner != nil, stack.count >= 4 else { return false }
        return stack[3].isNode("obj", "Track Device") && stack[3].kind == owner?.deviceClass
    }
    private var inAttributes: Bool { inDevice && stack.count >= 5 && stack[4].isNode("member", "DeviceAttributes") }

    func parser(_ parser: XMLParser, didStartElement tag: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        elements += 1
        guard elements <= CubaseTrackArchiveReader.maximumElements,
              stack.count < CubaseTrackArchiveReader.maximumDepth,
              !tag.contains(":"), !attributes.keys.contains(where: { $0 == "xmlns" || $0.contains(":") }) else {
            reject(parser); return
        }
        stack.append(Frame(tag: tag, name: attributes["name"], kind: attributes["class"], type: attributes["type"]))
        let depth = stack.count
        if depth == 1 {
            validRoot = tag == "tracklist2"
            if !validRoot { reject(parser) }
            return
        }
        if depth == 2, stack[1].isNode("list", "track") {
            guard !hasTrackList, stack[1].type == "obj" else { reject(parser); return }
            hasTrackList = true
        }
        guard inTrackList else { return }
        if depth == 3 {
            trackCount += 1
            guard trackCount <= CubaseTrackArchiveReader.maximumTracks else { reject(parser); return }
            let deviceClasses = ["MAudioTrackEvent": "MAudioTrack", "MInstrumentTrackEvent": "MInstrumentTrack", "MDeviceTrackEvent": "MTrack"]
            if tag == "obj", let deviceClass = deviceClasses[attributes["class"] ?? ""] {
                owner = Owner(ordinal: trackCount - 1, deviceClass: deviceClass)
            } else { unsupportedTracks += 1 }
            return
        }
        guard owner != nil else { return }
        if depth == 4, stack[3].isNode("obj", "Node"), stack[3].kind == "MListNode" {
            guard unique("Node", parser: parser) else { return }
        }
        if depth == 5, stack[3].isNode("obj", "Node"), stack[3].kind == "MListNode",
           stack[4].isNode("string", "Name") {
            guard owner?.name == nil, let value = textValue(attributes["value"]) else { reject(parser); return }
            owner?.name = value
        }
        if inDevice, depth == 4 { guard unique("Track Device", parser: parser) else { return } }
        if inAttributes, depth == 5 { guard unique("DeviceAttributes", parser: parser) else { return } }
        if inAttributes, depth == 6, tag == "member", ["InsertFolder", "Synth Slot"].contains(attributes["name"] ?? "") {
            guard unique(attributes["name"]!, parser: parser) else { return }
        }
        if inAttributes, depth == 7, stack[5].isNode("member", "InsertFolder"), stack[6].isNode("list", "Slot") {
            guard stack[6].type == "list", unique("Insert Slots", parser: parser) else { reject(parser); return }
        }
        if inAttributes, depth == 6, owner?.requiresGroupSignature == true,
           (tag == "int" && attributes["name"] == "Type") || (tag == "string" && attributes["name"] == "IDString") {
            let key = attributes["name"]!
            guard owner?.groupSignature[key] == nil, let value = textValue(attributes["value"]) else { reject(parser); return }
            owner?.groupSignature[key] = value
        }
        var role: String?
        if inAttributes, depth == 7, owner?.instrument == true,
           stack[5].isNode("member", "Synth Slot"), stack[6].isNode("member", "Plugin") {
            guard unique("Synth Plugin", parser: parser) else { return }
            role = "instrument"
        } else if inAttributes, depth == 9,
                  stack[5].isNode("member", "InsertFolder"), stack[6].isNode("list", "Slot"), stack[6].type == "list",
                  stack[7].tag == "item", stack[8].isNode("member", "Plugin") {
            // Each item owns at most one Plugin member. Cleared when the item ends.
            guard unique("Insert Plugin", parser: parser) else { return }
            role = "insert"
        }
        if let role { plugin = Plugin(depth: depth, role: role); return }
        guard var current = plugin else { return }
        if depth == current.depth + 1, tag == "member", attributes["name"] == "Plugin UID" {
            guard !current.hasUIDMember else { reject(parser); return }
            current.hasUIDMember = true
            plugin = current
        }
        let directField = depth == current.depth + 1 && tag == "string" && ["Plugin Name", "Original Plugin Name"].contains(attributes["name"] ?? "")
        let uidField = depth == current.depth + 2 && stack[depth-2].isNode("member", "Plugin UID") && tag == "string" && attributes["name"] == "GUID"
        if directField || uidField {
            let key = attributes["name"]!
            guard current.fields[key] == nil, let value = textValue(attributes["value"]) else { reject(parser); return }
            current.fields[key] = value
            plugin = current
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard !rejected, !stack.isEmpty else { return }
        let depth = stack.count
        if let current = plugin, depth == current.depth {
            guard let declaredName = current.fields["Plugin Name"], let uid = current.fields["GUID"], uid.utf8.count == 32,
                  uid.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  references < CubaseTrackArchiveReader.maximumReferences else { reject(parser); return }
            owner?.plugins.append(CubaseArchivePlugin(role: current.role, name: current.fields["Original Plugin Name"] ?? declaredName, uid: uid))
            references += 1
            plugin = nil
        }
        if inAttributes, depth == 8, stack[5].isNode("member", "InsertFolder"), stack[6].isNode("list", "Slot"), stack[7].tag == "item" {
            owner?.seen.remove("Insert Plugin")
        }
        if inTrackList, depth == 3, let current = owner {
            // Group signature may follow inserts. Unknown device owners never leak
            // provisional references into the output, but still consume parsing budgets.
            if current.requiresGroupSignature && current.groupSignature != ["Type": "2", "IDString": "GroupChannel"] {
                unsupportedTracks += 1
            } else {
                guard let trackName = current.name else { reject(parser); return }
                tracks.append(CubaseArchiveTrack(ordinal: current.ordinal, name: trackName, plugins: current.plugins))
            }
            owner = nil
        }
        stack.removeLast()
    }
}
