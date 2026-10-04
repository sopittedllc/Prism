import Foundation

public struct CubasePluginClass: Sendable, Equatable {
    public let path: String
    public let cid: String
    public let name: String
    public let vendor: String
    public let version: String
    public let category: String
}

/// Read-only parser for Cubase's versioned VST3 cache. It is an association index,
/// never historical installation evidence. Duplicate CIDs and ambiguous descriptors
/// are retained so callers can fail closed.
public enum CubasePluginCache {
    public static let maximumBytes = 16 * 1024 * 1024
    public static func read(_ data: Data) throws -> [CubasePluginClass] {
        guard data.count <= maximumBytes, !data.contains(0) else { throw AssetDateEvidenceError.invalidProvenance }
        let parser = Delegate(); let xml = XMLParser(data: data); xml.delegate = parser
        guard xml.parse(), !parser.failed else { throw AssetDateEvidenceError.invalidProvenance }
        return parser.classes
    }
    public static func read(_ url: URL) throws -> [CubasePluginClass] {
        try read(BoundedFile.read(url, limit: maximumBytes))
    }
    /// A usage record must have one exact current Audio Module Class descriptor.
    public static func bindings(for use: CubasePluginUse, in classes: [CubasePluginClass]) -> [CubasePluginClass] {
        classes.filter { $0.category == "Audio Module Class" && $0.name == use.name && $0.vendor == use.vendor && $0.version == use.version && !$0.cid.isEmpty }
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var classes: [CubasePluginClass] = []; var failed = false
        var stack: [String] = []; var text = ""; var path = ""
        var cid = "", name = "", vendor = "", version = "", category = ""
        var inClass = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
            stack.append(name); text = ""
            if name == "plugin" { path = "" }
            if name == "class" { inClass = true; cid = ""; self.name = ""; vendor = ""; version = ""; category = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "path" && !inClass { path = value }
            if inClass {
                switch name { case "cid": cid = value; case "name": self.name = value; case "vendor": vendor = value; case "version": version = value; case "category": category = value; default: break }
            }
            if name == "class" {
                guard category == "Audio Module Class", path.hasPrefix("/"), cid.count == 32,
                      cid.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { inClass = false; stack.removeLast(); text = ""; return }
                classes.append(CubasePluginClass(path: path, cid: cid.uppercased(), name: self.name, vendor: vendor, version: version, category: category)); inClass = false
            }
            if !stack.isEmpty { stack.removeLast() }; text = ""
        }
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { failed = true }
        func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) { failed = true }
    }
}
