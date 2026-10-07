import Foundation
import CSQLite
import CryptoKit

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
    /// Bounded manifest bytes or exact unassociated-pair stat fingerprint. It
    /// rejects a changed source before commit; it is never a vendor product ID.
    public var sourceFingerprint: String? = nil
}

public struct LibraryContentMember: Codable, Sendable {
    public let path: String
    public let stale: Bool
}
/// A technique named by a qualified patch source. It inherits the patch's physical
/// location and lifecycle; it does not establish an independently installed sample.
public struct LibraryArticulation: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let source: String
    public init(id: String, name: String, source: String) {
        self.id = id; self.name = name; self.source = source
    }
}
/// Extraction coverage is separate from the names found. Old catalogs have
/// unknown coverage even when they contain legacy name guesses.
public struct LibraryArticulationCoverage: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case unknown, indexed, knownEmpty }
    public let status: Status
    public let adapter: String?
    public let adapterVersion: Int?
    public let sourceVersion: String?
    public let sourceSignature: String?
    public static let unknown = Self(status: .unknown, adapter: nil, adapterVersion: nil,
                                     sourceVersion: nil, sourceSignature: nil)
    public init(status: Status, adapter: String?, adapterVersion: Int?,
                sourceVersion: String?, sourceSignature: String?) {
        self.status = status; self.adapter = adapter; self.adapterVersion = adapterVersion
        self.sourceVersion = sourceVersion; self.sourceSignature = sourceSignature
    }
}
public struct LibraryInstrument: Codable, Sendable {
    public let name: String
    public let path: String
    public let tags: [String]
    public var vendorID: String? = nil
    public var catalogStale: Bool? = nil
    /// Finder date for an exact physical instrument file, when available.
    public var finderDateAdded: Date? = nil
    /// Known physical members only, not a claim of exhaustive dependencies or ownership.
    /// SINE includes each installed mic's metadata and archive; nil means not established.
    public var contentPaths: [String]? = nil
    public var contentMembers: [LibraryContentMember]? = nil
    /// Derived patch-local names; legacy catalog payloads decode with no children.
    public var articulations: [LibraryArticulation] = []
    public var articulationCoverage: LibraryArticulationCoverage = .unknown
    private enum CodingKeys: String, CodingKey {
        case name, path, tags, vendorID, catalogStale, finderDateAdded, contentPaths, contentMembers, articulations, articulationCoverage
    }
    public init(name: String, path: String, tags: [String], vendorID: String? = nil,
                catalogStale: Bool? = nil, finderDateAdded: Date? = nil,
                contentPaths: [String]? = nil, contentMembers: [LibraryContentMember]? = nil,
                articulations: [LibraryArticulation] = [],
                articulationCoverage: LibraryArticulationCoverage = .unknown) {
        self.name = name; self.path = path; self.tags = tags; self.vendorID = vendorID
        self.catalogStale = catalogStale; self.finderDateAdded = finderDateAdded
        self.contentPaths = contentPaths; self.contentMembers = contentMembers
        self.articulations = articulations
        self.articulationCoverage = articulationCoverage
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        tags = try c.decode([String].self, forKey: .tags)
        vendorID = try c.decodeIfPresent(String.self, forKey: .vendorID)
        catalogStale = try c.decodeIfPresent(Bool.self, forKey: .catalogStale)
        finderDateAdded = try c.decodeIfPresent(Date.self, forKey: .finderDateAdded)
        contentPaths = try c.decodeIfPresent([String].self, forKey: .contentPaths)
        contentMembers = try c.decodeIfPresent([LibraryContentMember].self, forKey: .contentMembers)
        articulations = try c.decodeIfPresent([LibraryArticulation].self, forKey: .articulations) ?? []
        articulationCoverage = try c.decodeIfPresent(LibraryArticulationCoverage.self, forKey: .articulationCoverage) ?? .unknown
    }
}
public struct LibraryMetadata: Codable, Sendable {
    public enum SizeBasis: String, Codable, Sendable {
        case fullInstallation, installedContent, candidateFolder, unassociatedContent
    }
    public let player: String
    public let maker: String
    public let summary: String
    public var instruments: [LibraryInstrument]
    public var tags: [String]
    public let source: String
    public var identity: LibraryIdentity? = nil
    /// Exact physical files for an unassociated SINE pair. This is not a patch,
    /// product binding or a claim that other dependencies are known.
    public var physicalContentPaths: [String]? = nil
    /// Stable device/inode membership for unresolved physical clusters. Mutable
    /// stat stamps remain in `identity.sourceFingerprint` for commit validation.
    public var physicalContentIdentity: String? = nil
    /// What measured `Asset.logicalBytes` actually covers. Nil is legacy or unknown.
    public var sizeBasis: SizeBasis? = nil
    public var sharedLogicalBytes: Int? = nil
    public var sizeSourceFingerprint: String? = nil
    /// Safe inheritance: aggregate instrument tags belong to search, not to siblings.
    public var contextTags: [String] {
        maker == "Unknown maker" || maker.isEmpty ? [] : [maker]
    }
    /// Product-row suggestions must come from product evidence. Patch-name tags
    /// remain searchable through `instruments`, but never classify their parent.
    public func productTags(productName: String) -> [String] {
        var result: [String]
        switch identity?.evidence {
        case .vendorCatalog:
            result = tags
        default:
            result = source.contains("Kontakt vendor browser categories qualified")
                ? tags : LibraryMetadataReader.tags(productName)
        }
        return Array(Set(result)).sorted()
    }
    public func tags(for instrument: LibraryInstrument, productName: String) -> [String] {
        Array(Set(contextTags + [productName] + instrument.tags)).sorted()
    }
    public var searchText: String { ([player, maker, summary] + tags + instruments.flatMap { [$0.name] + $0.tags }).joined(separator: " ") }
}

/// Bounded fields extracted from one Kontakt ProductHints product.
/// SNPID is preserved exactly as stored; it is not case-folded or normalized.
public struct KontaktManifestDetails: Codable, Sendable, Equatable {
    public let name: String
    public let maker: String
    public let snpid: String?
}

struct KontaktManifestSnapshot: Codable {
    let details: KontaktManifestDetails
    let fingerprint: String
}

/// Local, derived metadata only. Never reads sample payloads or account/license data.
public enum LibraryMetadataReader {
    public static let maximumMetadataBytes = 8 * 1024 * 1024
    /// The largest ProductHints block observed in the installed collection closes
    /// at 173,355 bytes. Keep a bounded prefix, including room for other editions.
    public static let maximumManifestPrefixBytes = 1_048_576
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
        guard safe(url), let data = try? BoundedFile.read(url, limit: maximumManifestPrefixBytes, prefixOnly: true) else { return nil }
        return parseKontaktManifest(data)
    }
    public static func parseKontaktManifest(_ data: Data) -> (name: String, maker: String)? {
        guard let details = parseKontaktManifestDetails(data) else { return nil }
        return (details.name, details.maker)
    }
    public static func kontaktManifestDetails(_ url: URL) -> KontaktManifestDetails? {
        kontaktManifestSnapshot(url)?.details
    }
    static func kontaktManifestFingerprint(_ url: URL) -> String? {
        guard safe(url), let data = try? BoundedFile.read(url, limit: maximumManifestPrefixBytes, prefixOnly: true) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func kontaktManifestSnapshot(_ url: URL) -> KontaktManifestSnapshot? {
        guard safe(url),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let before = LibraryScanJournal.stamp(url.path),
              let data = try? BoundedFile.read(url, limit: maximumManifestPrefixBytes, prefixOnly: true),
              let details = parseKontaktManifestDetails(data),
              LibraryScanJournal.stamp(url.path) == before else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return KontaktManifestSnapshot(details: details, fingerprint: digest)
    }
    public static func parseKontaktManifestDetails(_ data: Data) -> KontaktManifestDetails? {
        guard data.count <= maximumManifestPrefixBytes else { return nil }
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
    struct PhysicalPairSnapshot {
        let bytes: Int
        let fingerprint: String
        let physicalIdentity: String
    }
    static func physicalPairSnapshot(_ metadata: URL, archive: URL) -> PhysicalPairSnapshot? {
        physicalContentSnapshot([metadata.path, archive.path])
    }
    static func physicalContentSnapshot(_ paths: [String]) -> PhysicalPairSnapshot? {
        guard paths.count >= 2, Set(paths).count == paths.count else { return nil }
        let ordered = paths.sorted()
        var stamps: [LibraryScanJournal.Stamp] = []
        for path in ordered {
            let url = URL(fileURLWithPath: path)
            guard safe(url), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let stamp = LibraryScanJournal.stamp(path), stamp.size >= 0, stamp.size <= Int.max else { return nil }
            stamps.append(stamp)
        }
        var seen = Set<String>(), bytes = 0
        for stamp in stamps {
            let key = "\(stamp.device):\(stamp.inode)"
            if seen.insert(key).inserted {
                let (sum, overflow) = bytes.addingReportingOverflow(Int(stamp.size))
                guard !overflow else { return nil }
                bytes = sum
            }
        }
        guard stamps.allSatisfy({ LibraryScanJournal.stamp($0.path) == $0 }) else { return nil }
        func digest(_ string: String) -> String {
            SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return PhysicalPairSnapshot(bytes: bytes,
            fingerprint: digest(stamps.map(LibraryScanJournal.signature).joined(separator: ":")),
            physicalIdentity: digest(seen.sorted().joined(separator: ":")))
    }
    /// Read the player catalog, but expose only content physically present within selected library roots.
    public static func sine(_ database: URL, roots: [URL], sampleRoots: [URL] = [], issues: inout [ScanIssue]) -> [Asset] {
        sine(database, roots: roots, sampleRoots: sampleRoots, cache: nil, issues: &issues)
    }

    private struct SINERows: Codable {
        let positions: [[String]]
        let articulations: [[String]]
        let articulationsComplete: Bool
    }
    private struct SINECollection {
        var title: String
        var maker: String
        var summary: String
        var tags: [String]
        var instruments: [String: LibraryInstrument]
    }

    static func sine(_ database: URL, roots: [URL], sampleRoots: [URL] = [],
                     cache: DecodedFactCache?, issues: inout [ScanIssue]) -> [Asset] {
        guard !roots.isEmpty, FileManager.default.fileExists(atPath: database.path) else { return [] }
        guard safe(database) else { issues.append(ScanIssue(path: database.path, reason: "SINE catalog is linked or unavailable")); return [] }
        let rows: SINERows?
        if let cache {
            var partial: SINERows?
            let result: DecodedFactCache.Result<SINERows> = cache.checkedValue(policy: "sine-rows-v1", paths: [database] + ["-wal", "-journal", "-shm"].map {
                URL(fileURLWithPath: database.path + $0)
            }) {
                let fetched = readSINERows(database)
                if fetched?.articulationsComplete == false { partial = fetched; return nil }
                return fetched
            }
            switch result {
            case .value(let value): rows = value
            case .unavailable: rows = partial
            case .unstable: rows = nil
            }
        } else { rows = readSINERows(database) }
        guard let rows else {
            issues.append(ScanIssue(path: database.path, reason: "SINE metadata incomplete or unavailable")); return []
        }
        var collections: [String: SINECollection] = [:]; var truncated = Set<String>()
        let scope = roots.map { $0.standardizedFileURL.path }
        for row in rows.positions {
            if Task<Never, Never>.isCancelled { return [] }
            func value(_ index: Int) -> String { row[index] }
            let raw = value(8)
            // The database stores a virtual .otmf child inside a physical .otmeta.
            if let range = raw.range(of: ".otmeta", options: .caseInsensitive) {
                let file = URL(fileURLWithPath: String(raw[..<range.upperBound])).standardizedFileURL
                let archive = file.deletingPathExtension().appendingPathExtension("otarc")
                let sampleDepth = sampleRoots.filter { file.path.hasPrefix($0.standardizedFileURL.path + "/") }.map { $0.standardizedFileURL.path.count }.max() ?? -1
                let libraryDepth = scope.filter { file.path.hasPrefix($0 + "/") }.map(\.count).max() ?? -1
                if libraryDepth > sampleDepth, scope.contains(where: { file.path.hasPrefix($0 + "/") }), safe(file),
                   (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, safe(archive),
                   (try? archive.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    let id = value(0), name = value(6)
                    var collection = collections[id] ?? SINECollection(title: value(1), maker: value(3).isEmpty ? "Orchestral Tools" : value(3), summary: value(2), tags: tags(value(4)), instruments: [:])
                    let instrumentID = value(5)
                    guard !id.isEmpty, !instrumentID.isEmpty, !collection.title.isEmpty, !name.isEmpty else {
                        if truncated.insert("missingIdentity").inserted {
                            issues.append(ScanIssue(path: database.path, reason: "SINE row missing product or instrument identity"))
                        }
                        continue
                    }
                    if let previous = collection.instruments[instrumentID] {
                        let paths = Array(Set((previous.contentPaths ?? []) + [file.path, archive.path])).sorted()
                        collection.instruments[instrumentID] = LibraryInstrument(name: previous.name,
                            path: min(previous.path, file.path), tags: Array(Set(previous.tags + tags(name + " " + value(7)))).sorted(),
                            vendorID: previous.vendorID, contentPaths: paths,
                            articulations: previous.articulations)
                    } else {
                        collection.instruments[instrumentID] = LibraryInstrument(name: name, path: file.path,
                            tags: tags(name + " " + value(7)),
                            vendorID: "sine:collection:\(id):instrument:\(instrumentID)",
                            contentPaths: [file.path, archive.path].sorted())
                    }
                    collections[id] = collection
                }
            }
        }
        for row in rows.articulations {
            if Task<Never, Never>.isCancelled { return [] }
            let collectionID = row[0], instrumentID = row[1]
            let artID = row[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = row[3].trimmingCharacters(in: .whitespacesAndNewlines)
            if !artID.isEmpty, !title.isEmpty,
               var collection = collections[collectionID], var instrument = collection.instruments[instrumentID],
               !instrument.articulations.contains(where: { $0.id == artID }) {
                instrument.articulations.append(LibraryArticulation(id: artID, name: title, source: "SINE local catalog"))
                collection.instruments[instrumentID] = instrument
                collections[collectionID] = collection
            }
        }
        if !rows.articulationsComplete {
            issues.append(ScanIssue(path: database.path,
                reason: "SINE articulation catalog schema is unsupported; patch techniques unavailable"))
        }
        let articulationQueryComplete = rows.articulationsComplete
        return sineAssets(collections: collections, articulationQueryComplete: articulationQueryComplete, issues: &issues)
    }

    private static func readSINERows(_ database: URL) -> SINERows? {
        guard safe(database), (try? BoundedFile.read(database, limit: 100, prefixOnly: true)) != nil else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 65_536)
        // Stream the catalog to completion. Cancellation limits work without
        // permanently dropping rows from a large installed collection.
        sqlite3_progress_handler(db, 1000, { _ in
            Task<Never, Never>.isCancelled ? 1 : 0
        }, nil)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else {
            return nil
        }
        let sql = """
        SELECT c.collection_id,c.title,c.subtitle,c.developer,c.keywords,i.instrument_id,i.title,i.keywords,m.filePath
        FROM t_collection c JOIN t_instrument i ON i.instrument_collection=c.collection_key
        JOIN t_micPosition m ON m.micposition_instrument=i.instrument_key
        WHERE m.filePath IS NOT NULL AND m.filePath != ''
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        func values(_ statement: OpaquePointer, count: Int32) -> [String] {
            (0..<count).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
            }
        }
        var positions: [[String]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard !Task<Never, Never>.isCancelled, positions.count < 100_000 else { return nil }
            positions.append(values(statement, count: 9))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { return nil }
        let articulationSQL = """
        SELECT c.collection_id,i.instrument_id,a.articulation_id,a.title
        FROM t_articulation a JOIN t_instrument i ON a.articulation_instrument=i.instrument_key
        JOIN t_collection c ON i.instrument_collection=c.collection_key
        WHERE a.hidden=0 AND a.kind IN ('single','poly')
        """
        var artStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, articulationSQL, -1, &artStatement, nil) == SQLITE_OK,
              let artStatement else {
            if let artStatement { sqlite3_finalize(artStatement) }
            return SINERows(positions: positions, articulations: [], articulationsComplete: false)
        }
        defer { sqlite3_finalize(artStatement) }
        var articulations: [[String]] = []
        status = sqlite3_step(artStatement)
        while status == SQLITE_ROW {
            guard !Task<Never, Never>.isCancelled, articulations.count < 100_000 else { return nil }
            articulations.append(values(artStatement, count: 4))
            status = sqlite3_step(artStatement)
        }
        guard status == SQLITE_DONE else {
            return Task<Never, Never>.isCancelled ? nil : SINERows(positions: positions, articulations: [], articulationsComplete: false)
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { return nil }
        return SINERows(positions: positions, articulations: articulations, articulationsComplete: true)
    }

    private static func sineAssets(collections: [String: SINECollection],
                                   articulationQueryComplete: Bool,
                                   issues: inout [ScanIssue]) -> [Asset] {
        let collectionPaths = collections.mapValues { collection in
            Set(collection.instruments.values.flatMap { $0.contentPaths ?? [] })
        }
        var contentStamps: [String: LibraryScanJournal.Stamp] = [:]
        for path in Set(collectionPaths.values.flatMap { $0 }).sorted() {
            let file = URL(fileURLWithPath: path)
            if safe(file), (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
               let stamp = LibraryScanJournal.stamp(path), stamp.size >= 0, stamp.size <= Int.max {
                contentStamps[path] = stamp
            } else {
                issues.append(ScanIssue(path: path, reason: "SINE installed content changed before size accounting; measurement incomplete", kind: .library))
            }
        }
        func physicalKey(_ stamp: LibraryScanJournal.Stamp) -> String { "\(stamp.device):\(stamp.inode)" }
        var inodeOwners: [String: Set<String>] = [:]
        for (id, paths) in collectionPaths {
            for path in paths {
                if let stamp = contentStamps[path] { inodeOwners[physicalKey(stamp), default: []].insert(id) }
            }
        }
        return collections.keys.sorted().compactMap { id in
            guard let collection = collections[id], !collection.instruments.isEmpty else { return nil }
            let instruments = collection.instruments.values.map { instrument in
                var value = instrument
                value.articulations.sort { ($0.name, $0.id) < ($1.name, $1.id) }
                if articulationQueryComplete {
                    value.articulationCoverage = LibraryArticulationCoverage(
                        status: value.articulations.isEmpty ? .knownEmpty : .indexed,
                        adapter: "sine-local-catalog", adapterVersion: 1,
                        sourceVersion: "v3", sourceSignature: nil)
                }
                return value
            }.sorted { ($0.name, $0.vendorID ?? "") < ($1.name, $1.vendorID ?? "") }
            var asset = Asset(kind: .library, path: instruments[0].path, name: collection.title, format: "SINE", bundleIdentifier: nil, logicalBytes: nil, classification: "identifiedLibrary")
            var metadata = LibraryMetadata(player: "SINE", maker: collection.maker, summary: collection.summary, instruments: instruments, tags: collection.tags, source: "SINE local catalog + existing metadata and sample archives; product tags from the collection catalog and patch tags from instrument names. Other dependencies and usage not established.", identity: LibraryIdentity(evidence: .vendorCatalog, productID: "sine:collection:\(id)", installationRoot: nil))
            let paths = collectionPaths[id] ?? []
            if paths.count >= 2, paths.allSatisfy({ contentStamps[$0] != nil }),
               let snapshot = physicalContentSnapshot(Array(paths)) {
                let unique = Dictionary(grouping: paths.compactMap { contentStamps[$0] }, by: physicalKey).compactMapValues(\.first)
                var shared = 0
                var overflow = false
                for (key, stamp) in unique where (inodeOwners[key]?.count ?? 0) > 1 {
                    let next = shared.addingReportingOverflow(Int(stamp.size))
                    if next.overflow { overflow = true; break }
                    shared = next.partialValue
                }
                if !overflow {
                    asset.logicalBytes = snapshot.bytes
                    metadata.sizeBasis = .installedContent
                    metadata.sharedLogicalBytes = shared
                    metadata.sizeSourceFingerprint = snapshot.fingerprint
                }
            } else {
                issues.append(ScanIssue(path: asset.path, reason: "SINE installed content size unavailable; measurement incomplete", kind: .library))
            }
            asset.libraryMetadata = metadata
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
