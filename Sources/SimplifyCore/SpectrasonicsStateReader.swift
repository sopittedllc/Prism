import Foundation

/// Version-gated metadata from a complete, typed Cubase audioComponent.
/// This never reads sample data or treats a top-level multi label as part ownership.
public enum SpectrasonicsStateReader {
    public enum ReadError: Error { case malformed, unsupported, limit }

    public enum Player: String, Codable, Sendable { case omnisphere, keyscape, trilian }
    public struct Part: Codable, Sendable, Equatable {
        public let slot: Int
        public let name: String
        public let library: String
        public let originalName: String
        public let originalLibrary: String
    }
    public struct Result: Codable, Sendable, Equatable {
        public let player: Player
        public let version: String
        public let parts: [Part]
    }

    private static let identities: [String: (name: String, player: Player, version: String)] = [
        "84E8DE5F9255222296FAE4133C935A18": ("Omnisphere", .omnisphere, "3.0.2c"),
        "84E8DE5F9255313196FAE4133C935A18": ("Keyscape", .keyscape, "1.5.2c"),
        "84E8DE5F9255757596FAE4133C935A18": ("Trillian", .trilian, "1.6.6d"),
    ]
    private static let rootOpen = Data("<SynthMaster".utf8)
    private static let rootClose = Data("</SynthMaster>".utf8)

    public static func read(_ plugin: CubaseKontaktStateReader.PluginState) throws -> Result? {
        guard let identity = identities[plugin.uid] else { return nil }
        guard plugin.name == identity.name else { throw ReadError.unsupported }
        let payload = plugin.payload
        guard payload.count <= 4 * 1024 * 1024, payload.count > 24 + rootClose.count,
              payload.prefix(16) == Data([0xff, 0xc9, 0x9a, 0x3b, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]),
              payload[24...].starts(with: rootOpen),
              let close = payload.range(of: rootClose, options: .backwards, in: 24..<payload.count) else {
            throw ReadError.unsupported
        }
        let expectedTrailer = identity.player == .omnisphere ? 38 : 7
        guard payload.count - close.upperBound == expectedTrailer else { throw ReadError.unsupported }
        let xml = payload.subdata(in: 24..<close.upperBound)
        guard xml.count <= 4 * 1024 * 1024,
              xml.range(of: Data("<!DOCTYPE".utf8)) == nil,
              xml.range(of: Data("<!ENTITY".utf8)) == nil else { throw ReadError.limit }
        let delegate = PartXML()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.failed, delegate.depth == 0,
              delegate.rootVersion == identity.version,
              (1...16).contains(delegate.parts.count) else { throw ReadError.malformed }
        return Result(player: identity.player, version: identity.version, parts: delegate.parts)
    }

    private final class PartXML: NSObject, XMLParserDelegate {
        var depth = 0
        var elements = 0
        var failed = false
        var rootVersion: String?
        var parts: [Part] = []
        private var current: (name: String?, library: String?, originalName: String, originalLibrary: String)?
        private var parents: [String] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            depth += 1; elements += 1
            guard depth <= 32, elements <= 10_000, attributes.count <= 512 else { failed = true; parser.abortParsing(); return }
            if depth == 1 {
                guard name == "SynthMaster" else { failed = true; parser.abortParsing(); return }
                rootVersion = attributes["vers"]
            }
            if name == "SYNTHENG" {
                guard current == nil, parts.count < 16 else { failed = true; parser.abortParsing(); return }
                current = (nil, nil, attributes["origPatchName"] ?? "", attributes["origLibName"] ?? "")
            } else if name == "ENTRYDESCR", parents.last == "SYNTHENG", current != nil {
                current?.name = attributes["name"]
                current?.library = attributes["library"]
            }
            parents.append(name)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard parents.last == name else { failed = true; parser.abortParsing(); return }
            if name == "SYNTHENG" {
                guard let current, let partName = current.name, let library = current.library else {
                    failed = true; parser.abortParsing(); return
                }
                parts.append(Part(slot: parts.count, name: partName, library: library,
                                  originalName: current.originalName, originalLibrary: current.originalLibrary))
                self.current = nil
            }
            parents.removeLast(); depth -= 1
        }
    }
}
