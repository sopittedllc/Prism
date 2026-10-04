import Foundation
import CSQLite

/// Adapter evidence, not permission to remove files. A proposed folder boundary
/// must be confirmed before it becomes an authoritative library installation.
public struct LibraryIdentity: Codable, Sendable, Equatable {
    public enum Evidence: String, Codable, Sendable { case vendorCatalog, manifest, proposed, unresolved }
    public let evidence: Evidence
    /// Namespaced vendor ID when actually present; never synthesized from a title/path.
    public let productID: String?
    /// Candidate installation directory for folder-based products, not a deletion target.
    /// SINE collections can span directories and therefore leave this nil.
    public let installationRoot: String?
}

public struct LibraryContentMember: Codable, Sendable {
    public let path: String
    public let stale: Bool
}
public struct LibraryInstrument: Codable, Sendable {
    public let name: String
    public let path: String
    public let tags: [String]
    public var vendorID: String? = nil
    public var catalogStale: Bool? = nil
    /// Known physical members only, not a claim of exhaustive dependencies or ownership.
    /// SINE includes each installed mic's metadata and archive; nil means not established.
    public var contentPaths: [String]? = nil
    public var contentMembers: [LibraryContentMember]? = nil
}
public struct LibraryMetadata: Codable, Sendable {
    public let player: String
    public let maker: String
    public let summary: String
    public var instruments: [LibraryInstrument]
    public var tags: [String]
    public let source: String
    public var identity: LibraryIdentity? = nil
    /// Safe inheritance: aggregate instrument tags belong to search, not to siblings.
    public var contextTags: [String] {
        maker == "Unknown maker" || maker.isEmpty ? [] : [maker]
    }
    public func tags(for instrument: LibraryInstrument, productName: String) -> [String] {
        Array(Set(contextTags + [productName] + instrument.tags)).sorted()
    }
    public var searchText: String { ([player, maker, summary] + tags + instruments.flatMap { [$0.name] + $0.tags }).joined(separator: " ") }
}

/// Bounded fields extracted from one Kontakt ProductHints product.
/// SNPID is preserved exactly as stored; it is not case-folded or normalized.
public struct KontaktManifestDetails: Sendable, Equatable {
    public let name: String
    public let maker: String
    public let snpid: String?
}

/// Local, derived metadata only. Never reads sample payloads or account/license data.
public enum LibraryMetadataReader {
    public static let maximumMetadataBytes = 8 * 1024 * 1024
    public static func safe(_ url: URL) -> Bool {
        var part = url.standardizedFileURL
        while part.path != "/" {
            guard let value = try? part.resourceValues(forKeys: [.isSymbolicLinkKey]), value.isSymbolicLink != true else { return false }
            part.deleteLastPathComponent()
        }
        return true
    }
    public static func tags(_ text: String) -> [String] {
        let words = Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let types = ["accordion", "banjo", "guitar", "piano", "organ", "violin", "viola", "cello", "bass", "strings", "brass", "woodwinds", "flute", "clarinet", "oboe", "bassoon", "trumpet", "trombone", "tuba", "horn", "percussion", "drums", "choir", "vocal", "synth", "harp", "mandolin", "ukulele"]
        return types.filter { words.contains($0) || words.contains($0 + "s") }.map { $0.capitalized }
    }
    /// NICNT contains a small embedded XML manifest; reject DTDs and never parse binary payloads.
    public static func kontaktManifest(_ url: URL) -> (name: String, maker: String)? {
        guard safe(url), let data = try? BoundedFile.read(url, limit: 65_536, prefixOnly: true) else { return nil }
        return parseKontaktManifest(data)
    }
    public static func parseKontaktManifest(_ data: Data) -> (name: String, maker: String)? {
        guard let details = parseKontaktManifestDetails(data) else { return nil }
        return (details.name, details.maker)
    }
    public static func kontaktManifestDetails(_ url: URL) -> KontaktManifestDetails? {
        guard safe(url),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let data = try? BoundedFile.read(url, limit: 65_536, prefixOnly: true) else { return nil }
        return parseKontaktManifestDetails(data)
    }
    public static func parseKontaktManifestDetails(_ data: Data) -> KontaktManifestDetails? {
        guard data.count <= 65_536 else { return nil }
        let prefixText = String(decoding: data, as: UTF8.self)
        guard !prefixText.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !prefixText.localizedCaseInsensitiveContains("<!ENTITY") else { return nil }
        let opening = Data("<ProductHints".utf8)
        let closing = Data("</ProductHints>".utf8)
        guard let start = data.range(of: opening),
              let end = data.range(of: closing, in: start.lowerBound..<data.endIndex),
              start.lowerBound < end.upperBound else { return nil }
        let xmlData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let text = String(data: xmlData, encoding: .utf8),
              text.hasPrefix("<ProductHints") else { return nil }
        let reader = ProductManifestDelegate(); let parser = XMLParser(data: xmlData)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), !reader.rejected, reader.productCount == 1,
              reader.fieldCounts["Name"] == 1,
              let name = reader.fields["Name"], !name.isEmpty else { return nil }
        if reader.fieldCounts["SNPID", default: 0] > 1 { return nil }
        let snpid = reader.fields["SNPID"]
        if let snpid, !validKontaktSNPID(snpid) { return nil }
        return KontaktManifestDetails(name: name,
                                      maker: reader.fieldCounts["Company"] == 1 ? (reader.fields["Company"] ?? "Unknown maker") : "Unknown maker",
                                      snpid: snpid)
    }
    static func validKontaktSNPID(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
    public static func soundpaintPart(_ url: URL) -> LibraryInstrument? {
        guard safe(url), let data = try? BoundedFile.read(url, limit: maximumMetadataBytes),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String, !name.isEmpty else { return nil }
        let tags = (object["tagging"] as? [String: [String]] ?? [:]).values.flatMap { $0 }
        return LibraryInstrument(name: name, path: url.path, tags: Array(Set(tags)).sorted())
    }
    public static var sineDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Orchestral Tools/SINE Player/SINELibrary.db")
    }
    /// Read the player catalog, but expose only content physically present within selected library roots.
    public static func sine(_ database: URL, roots: [URL], sampleRoots: [URL] = [], issues: inout [ScanIssue]) -> [Asset] {
        guard !roots.isEmpty, FileManager.default.fileExists(atPath: database.path) else { return [] }
        guard safe(database), (try? BoundedFile.read(database, limit: 100, prefixOnly: true)) != nil else { issues.append(ScanIssue(path: database.path, reason: "SINE catalog is linked or unavailable")); return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; issues.append(ScanIssue(path: database.path, reason: "Cannot read SINE catalog")); return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 65_536)
        let budget = UnsafeMutablePointer<Int>.allocate(capacity: 1); budget.initialize(to: 2000)
        defer { budget.deinitialize(count: 1); budget.deallocate() }
        sqlite3_progress_handler(db, 1000, { context in
            guard let context else { return 1 }; let counter = context.assumingMemoryBound(to: Int.self)
            counter.pointee -= 1; return counter.pointee <= 0 ? 1 : 0
        }, budget)
        let sql = """
        SELECT c.collection_id,c.title,c.subtitle,c.developer,c.keywords,i.instrument_id,i.title,i.keywords,m.filePath
        FROM t_collection c JOIN t_instrument i ON i.instrument_collection=c.collection_key
        JOIN t_micPosition m ON m.micposition_instrument=i.instrument_key
        WHERE m.filePath IS NOT NULL AND m.filePath != '' LIMIT 25001
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            issues.append(ScanIssue(path: database.path, reason: "SINE catalog schema is unsupported")); return []
        }
        defer { sqlite3_finalize(statement) }
        func value(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
        struct Collection { var title: String; var maker: String; var summary: String; var tags: [String]; var instruments: [String: LibraryInstrument] }
        var collections: [String: Collection] = [:]; var rows = 0; var bytes = 0; var truncated = Set<String>(); var status = sqlite3_step(statement)
        let scope = roots.map { $0.standardizedFileURL.path }
        while status == SQLITE_ROW {
            rows += 1
            if rows > 25000 { break }
            bytes += (0..<9).reduce(0) { $0 + Int(sqlite3_column_bytes(statement, Int32($1))) }
            if bytes > 16 * 1024 * 1024 { break }
            let raw = value(8)
            // SINE catalogs include a virtual .otmf child inside the physical .otmeta file.
            if let range = raw.range(of: ".otmeta", options: .caseInsensitive) {
                let file = URL(fileURLWithPath: String(raw[..<range.upperBound])).standardizedFileURL
                let archive = file.deletingPathExtension().appendingPathExtension("otarc")
                let sampleDepth = sampleRoots.filter { file.path.hasPrefix($0.standardizedFileURL.path + "/") }.map { $0.standardizedFileURL.path.count }.max() ?? -1
                let libraryDepth = scope.filter { file.path.hasPrefix($0 + "/") }.map(\.count).max() ?? -1
                if libraryDepth > sampleDepth, scope.contains(where: { file.path.hasPrefix($0 + "/") }), safe(file),
                   (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, safe(archive),
                   (try? archive.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    let id = value(0), name = value(6)
                    var collection = collections[id] ?? Collection(title: value(1), maker: value(3).isEmpty ? "Orchestral Tools" : value(3), summary: value(2), tags: tags(value(4)), instruments: [:])
                    let instrumentID = value(5)
                    guard !id.isEmpty, !instrumentID.isEmpty, !collection.title.isEmpty, !name.isEmpty else {
                        if truncated.insert("missingIdentity").inserted {
                            issues.append(ScanIssue(path: database.path, reason: "SINE row missing product or instrument identity"))
                        }
                        status = sqlite3_step(statement); continue
                    }
                    if let previous = collection.instruments[instrumentID] {
                        let paths = Array(Set((previous.contentPaths ?? []) + [file.path, archive.path])).sorted()
                        collection.instruments[instrumentID] = LibraryInstrument(name: previous.name,
                            path: min(previous.path, file.path), tags: Array(Set(previous.tags + tags(name + " " + value(7)))).sorted(),
                            vendorID: previous.vendorID, contentPaths: paths)
                    } else if collection.instruments.count < 2000 {
                        collection.instruments[instrumentID] = LibraryInstrument(name: name, path: file.path,
                            tags: tags(name + " " + value(7)),
                            vendorID: "sine:collection:\(id):instrument:\(instrumentID)",
                            contentPaths: [file.path, archive.path].sorted())
                    } else if truncated.insert(id).inserted {
                        issues.append(ScanIssue(path: database.path, reason: "SINE instrument metadata limited to 2,000 entries per collection"))
                    }
                    collections[id] = collection
                }
            }
            status = sqlite3_step(statement)
        }
        if status != SQLITE_DONE { issues.append(ScanIssue(path: database.path, reason: "SINE metadata incomplete: query work or row limit, or catalog read failed")) }
        return collections.keys.sorted().compactMap { id in
            guard let collection = collections[id], !collection.instruments.isEmpty else { return nil }
            let instruments = collection.instruments.values.sorted { ($0.name, $0.vendorID ?? "") < ($1.name, $1.vendorID ?? "") }
            let allTags = Array(Set(collection.tags + instruments.flatMap(\.tags))).sorted()
            var asset = Asset(kind: .library, path: instruments[0].path, name: collection.title, format: "SINE", bundleIdentifier: nil, logicalBytes: nil, classification: "identifiedLibrary")
            asset.libraryMetadata = LibraryMetadata(player: "SINE", maker: collection.maker, summary: collection.summary, instruments: instruments, tags: allTags, source: "SINE local catalog + existing metadata and sample archives; tags from catalog/instrument names. Content completeness and usage not established.", identity: LibraryIdentity(evidence: .vendorCatalog, productID: "sine:collection:\(id)", installationRoot: nil))
            return asset
        }
    }
}
private final class ProductManifestDelegate: NSObject, XMLParserDelegate {
    var stack: [String] = []; var fields: [String: String] = [:]
    var fieldCounts: [String: Int] = [:]; var productCount = 0; var rejected = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(name)
        if stack.count > 64 { rejected = true; parser.abortParsing(); return }
        if stack == ["ProductHints", "Product"] {
            productCount += 1
            if productCount > 1 { rejected = true; parser.abortParsing(); return }
        }
        if stack.count == 3, stack[0] == "ProductHints", stack[1] == "Product",
           ["Name", "Company", "SNPID"].contains(name) {
            fieldCounts[name, default: 0] += 1
            if fieldCounts[name, default: 0] > 1 { rejected = true; parser.abortParsing() }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if stack.count == 3, stack[0] == "ProductHints", stack[1] == "Product",
           let key = stack.last, ["Name", "Company", "SNPID"].contains(key) {
            fields[key, default: ""] += text
        }
    }
    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { if !stack.isEmpty { stack.removeLast() } }
}
