import Foundation
import CSQLite

/// Optional NKS browser taxonomy for exact installed Kontakt patches.
/// The vendor database is advisory: every row must still match the current file.
public enum KontaktCategoryReader {
    public static let database = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Native Instruments/Kontakt 8/komplete.db3")
    private static let maximumDatabaseBytes: Int64 = 256 * 1024 * 1024
    private static let sourceMarker = "Kontakt vendor browser categories qualified by exact patch path, size and modification time."

    public static func enrich(_ assets: [Asset], database source: URL = database) -> [Asset] {
        enrich(assets, database: source, cache: nil)
    }

    static func enrich(_ assets: [Asset], database source: URL = database, cache: DecodedFactCache?) -> [Asset] {
        let wanted = Set(assets.filter { $0.kind == .library && $0.format == "Kontakt" }
            .flatMap { $0.libraryMetadata?.instruments.map(\.path) ?? [] })
        guard !wanted.isEmpty else { return assets }
        let categories: [String: Row]?
        if let cache {
            let ordered = wanted.sorted()
            let sidecars = ["-wal", "-journal", "-shm"].map { URL(fileURLWithPath: source.path + $0) }
            categories = cache.value(policy: "kontakt-category-v1:" + ordered.joined(separator: "\u{0}"),
                paths: [source] + sidecars + ordered.map(URL.init(fileURLWithPath:))) {
                    read(source, wanted: wanted)
                }
        } else { categories = read(source, wanted: wanted) }
        guard let categories, !categories.isEmpty else { return assets }
        return assets.map { asset in
            guard asset.kind == .library, asset.format == "Kontakt", let original = asset.libraryMetadata else { return asset }
            var instruments = original.instruments
            var product = Set(LibraryMetadataReader.tags(asset.name))
            var matched = false
            for index in instruments.indices {
                guard let row = categories[instruments[index].path] else { continue }
                let prior = instruments[index]
                instruments[index] = LibraryInstrument(name: prior.name, path: prior.path, tags: row.tags,
                    vendorID: prior.vendorID, catalogStale: prior.catalogStale,
                    finderDateAdded: prior.finderDateAdded, contentPaths: prior.contentPaths,
                    contentMembers: prior.contentMembers, articulations: prior.articulations,
                    articulationCoverage: prior.articulationCoverage)
                if URL(fileURLWithPath: prior.path).pathExtension.lowercased() == "nki" {
                    product.formUnion(row.tags)
                }
                matched = true
            }
            guard matched else { return asset }
            var displayName = asset.name
            var maker = original.maker
            var identity = original.identity
            if identity?.evidence == .proposed || identity?.evidence == .unresolved {
                let nativePatches = instruments.filter { URL(fileURLWithPath: $0.path).pathExtension.lowercased() == "nki" }
                let ownership = nativePatches.compactMap { categories[$0.path] }
                let products = Set(ownership.flatMap(\.products)).filter { MusicalSearch.normalized($0) != "kontakt" }
                let vendors = Set(ownership.flatMap(\.vendors)).filter { !$0.isEmpty }
                if !nativePatches.isEmpty, ownership.count == nativePatches.count,
                   products.count == 1, vendors.count == 1,
                   ownership.allSatisfy({ $0.products == products && $0.vendors == vendors }) {
                    displayName = products.first!
                    maker = vendors.first!
                    var qualified = LibraryIdentity(evidence: .vendorCatalog,
                        productID: identity?.productID, installationRoot: identity?.installationRoot)
                    qualified.sourceFingerprint = identity?.sourceFingerprint
                    identity = qualified
                }
            }
            let enrichedSource = original.source.contains(sourceMarker) ? original.source : original.source + " " + sourceMarker
            var updated = LibraryMetadata(player: original.player, maker: maker, summary: original.summary,
                instruments: instruments, tags: product.sorted(), source: enrichedSource,
                identity: identity)
            updated.physicalContentPaths = original.physicalContentPaths
            updated.physicalContentIdentity = original.physicalContentIdentity
            updated.sizeBasis = original.sizeBasis
            updated.sharedLogicalBytes = original.sharedLogicalBytes
            updated.sizeSourceFingerprint = original.sizeSourceFingerprint
            return Asset(kind: asset.kind, path: asset.path, name: displayName, format: asset.format,
                bundleIdentifier: asset.bundleIdentifier, logicalBytes: asset.logicalBytes,
                finderDateAdded: asset.finderDateAdded, classification: asset.classification,
                libraryMetadata: updated, vst3Categories: asset.vst3Categories,
                fileIdentity: asset.fileIdentity, catalogID: asset.catalogID,
                pluginProductID: asset.pluginProductID, catalogStale: asset.catalogStale)
        }
    }

    private struct Row: Codable {
        let tags: [String]
        let products: Set<String>
        let vendors: Set<String>
    }

    private static func read(_ source: URL, wanted: Set<String>) -> [String: Row]? {
        guard LibraryMetadataReader.safe(source), let stamp = LibraryScanJournal.stamp(source.path),
              stamp.size > 0, stamp.size <= maximumDatabaseBytes else { return nil }
        if let result = query(source, wanted: wanted) { return result }

        // A locked vendor database can be read from a stable private copy. Never
        // copy through active SQLite sidecars or accept a source that changed.
        let sidecars = ["-journal", "-wal", "-shm"]
        guard sidecars.allSatisfy({ LibraryScanJournal.stamp(source.path + $0) == nil }) else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Prism-KontaktCategories-" + UUID().uuidString)
        let copy = directory.appendingPathComponent("komplete.db3")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.copyItem(at: source, to: copy)
            guard LibraryScanJournal.stamp(source.path) == stamp,
                  sidecars.allSatisfy({ LibraryScanJournal.stamp(source.path + $0) == nil }) else { return nil }
            // Some vendor catalogs retain WAL journal mode even without active
            // sidecars. The verified private copy may create its own transient
            // SQLite shared state; the installed database remains read-only.
            return query(copy, wanted: wanted, writableCopy: true)
        } catch { return nil }
    }

    private static func query(_ database: URL, wanted: Set<String>, writableCopy: Bool = false) -> [String: Row]? {
        var db: OpaquePointer?
        let access = writableCopy ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        // The original path is untrusted and must not traverse links. The copy
        // is a new regular file in our mode-0700 directory; macOS temporary
        // paths contain `/var` symlink components that SQLITE_OPEN_NOFOLLOW
        // otherwise rejects before SQLite can recover the WAL-mode copy.
        let linkPolicy = writableCopy ? 0 : SQLITE_OPEN_NOFOLLOW
        guard sqlite3_open_v2(database.path, &db, access | SQLITE_OPEN_NOMUTEX | linkPolicy, nil) == SQLITE_OK,
              let db else { if let db { sqlite3_close(db) }; return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 65_536)
        sqlite3_progress_handler(db, 1000, { _ in Task<Never, Never>.isCancelled ? 1 : 0 }, nil)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { return nil }
        let sql = """
        SELECT s.file_name,s.file_ext,s.file_size,s.mod_date,
               c.category,c.subcategory,c.subsubcategory,b.entry1,s.vendor
        FROM k_sound_info s
        LEFT JOIN k_sound_info_category sc ON sc.sound_info_id=s.id
        LEFT JOIN k_category c ON c.id=sc.category_id
        LEFT JOIN k_bank_chain b ON b.id=s.bank_chain_id
        WHERE s.file_ext IN ('nki','nkm','nksn')
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        func text(_ index: Int32) -> String {
            sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        }
        struct Accumulator {
            var tags = Set<String>()
            var products = Set<String>()
            var vendors = Set<String>()
        }
        var values: [String: Accumulator] = [:]
        var fileStamps: [String: (size: Int64, modified: Int64)] = [:]
        var missing = Set<String>()
        var count = 0, status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if Task<Never, Never>.isCancelled { return nil }
            count += 1; guard count <= 100_000 else { return nil }
            let path = URL(fileURLWithPath: text(0)).standardizedFileURL.path
            let ext = text(1).lowercased()
            if ["nki", "nkm", "nksn"].contains(ext), wanted.contains(path) {
                if fileStamps[path] == nil, !missing.contains(path) {
                    if let stamp = LibraryScanJournal.stamp(path) {
                    let (seconds, overflow) = stamp.modifiedSeconds.multipliedReportingOverflow(by: 1_000_000_000)
                    let (nanoseconds, sumOverflow) = seconds.addingReportingOverflow(stamp.modifiedNanoseconds)
                        if !overflow, !sumOverflow { fileStamps[path] = (stamp.size, nanoseconds) }
                        else { missing.insert(path) }
                    } else { missing.insert(path) }
                }
                let row = fileStamps[path]
                let matches = row?.size == sqlite3_column_int64(statement, 2)
                    && row?.modified == sqlite3_column_int64(statement, 3)
                if matches {
                    var value = values[path] ?? Accumulator()
                    for index: Int32 in 4...6 {
                        let tag = text(index).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !tag.isEmpty { value.tags.insert(tag) }
                    }
                    let product = text(7).trimmingCharacters(in: .whitespacesAndNewlines)
                    let vendor = text(8).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !product.isEmpty { value.products.insert(product) }
                    if !vendor.isEmpty { value.vendors.insert(vendor) }
                    values[path] = value
                }
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE, sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { return nil }
        return values.mapValues { Row(tags: $0.tags.sorted(), products: $0.products, vendors: $0.vendors) }
    }
}
