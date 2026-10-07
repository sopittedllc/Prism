import Foundation
import CSQLite
import CryptoKit
import Darwin

/// Exact configured scope; overlapping roots retain observation history.
public struct CatalogScope: Codable, Sendable {
    public let roots: [String: [String]]
    public init(_ request: ScanRequest) {
        roots = ["plugins": request.plugins, "samples": request.samples,
                 "libraries": request.libraries, "projects": request.projects]
            .mapValues { Array(Set($0.map { $0.standardizedFileURL.path })).sorted() }
    }
    static func contains(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }
    func roots(for kind: String) -> [String] {
        roots[kind == "plugin" ? "plugins" : kind == "sample" ? "samples" : "libraries"] ?? []
    }
    func exclusions(kind: String, root: String) -> [String] {
        let opposite = kind == "sample" ? "library" : "sample"
        guard kind != "plugin" else { return [] }
        return roots(for: opposite).filter {
            Self.contains($0, root: root) && (kind == "library" || $0 != root)
        }
    }
    func includes(kind: String, path: String) -> Bool {
        roots(for: kind).contains { root in
            Self.contains(path, root: root) && !exclusions(kind: kind, root: root).contains { Self.contains(path, root: $0) }
        }
    }
    var key: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try! encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CatalogObservation: Codable, Sendable {
    public let id: String
    public let firstSeen: Date
    public let lastSeen: Date
    /// This means newly indexed, never an installation timestamp.
    public let baseline: Bool
    public let stale: Bool
    public var addition: AdditionDateEvidence? = nil
    public func isRecent(at now: Date = Date()) -> Bool {
        !baseline && firstSeen <= now && now.timeIntervalSince(firstSeen) <= 30 * 24 * 60 * 60
    }
}
public struct CatalogSnapshot: Sendable {
    public let report: ScanReport
    public let savedAt: Date
    public let observations: [String: CatalogObservation]
    public let metadata: [String: MusicalMetadata]
    public let pluginProductDates: [String: Date]
    public let pluginProductNames: [String: String]
}

public enum CatalogStoreError: LocalizedError {
    case unavailable, incompatible, invalid, busy, sourceChanged
    public var errorDescription: String? {
        switch self {
        case .unavailable: "The saved catalog is unavailable. Current scan results can still be used."
        case .incompatible: "The saved catalog belongs to an unsupported version and has been left unchanged."
        case .invalid: "The saved catalog could not be read and has been left unchanged."
        case .busy: "The saved catalog is busy. Current scan results can still be used."
        case .sourceChanged: "A library changed during indexing. Scan again to reconcile its current contents."
        }
    }
}

/// Local inventory graph. All SQLite work is serialized by this actor, off the UI actor.
/// Only final scans are ingested. Missing observations are retained and labeled stale.
public actor CatalogStore {
    public nonisolated let url: URL
    public init(url: URL) { self.url = url }
    /// Discard resumable scan work when the user resets the local collection.
    public nonisolated func clearDiscoveryJournals() { LibraryScanJournal.clearAll(baseURL: url) }
    public static var application: CatalogStore {
        CatalogStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Simplify/catalog.sqlite"))
    }

    private func productID(for asset: Asset, nodeID: String, db: CatalogDatabase) throws -> String {
        let key = PluginProduct.verifiedIdentity(asset)
        let current = try db.rows("""
            SELECT p.id,p.identity_key,p.metadata,CAST(p.earliest_date AS TEXT)
            FROM plugin_installations i JOIN plugin_products p ON p.id=i.product_id
            WHERE i.node_id=?
            """, [nodeID]).first
        if let current, current[1] == (key ?? "") { return current[0] }
        if key == nil, let current { return current[0] }
        let matches = try key.map { try db.rows("SELECT id FROM plugin_products WHERE identity_key=? LIMIT 2", [$0]) } ?? []
        let id: String
        if matches.count == 1 { id = matches[0][0] }
        else if let current, matches.isEmpty {
            // A product-specific canonicalizer may improve after an earlier scan.
            // Re-key the existing row so its edits and lifecycle evidence survive.
            id = current[0]
            try db.run("UPDATE plugin_products SET identity_key=? WHERE id=?", [key!, id])
        } else {
            id = UUID().uuidString
            try db.run("INSERT INTO plugin_products(id,identity_key,name,archived) VALUES(?,?,?,0)", [id, key ?? "", asset.name])
        }
        if let current, current[0] != id {
            let target = try db.rows("SELECT metadata,CAST(earliest_date AS TEXT) FROM plugin_products WHERE id=?", [id]).first
            if let target {
                // Preserve an explicit product edit when only one of the formerly
                // split format rows owns one. Conflicting explicit edits remain on
                // their source rows rather than being guessed together.
                if target[0].isEmpty, !current[2].isEmpty {
                    try db.run("UPDATE plugin_products SET metadata=? WHERE id=?", [current[2], id])
                }
                let dates = [Double(target[1]), Double(current[3])].compactMap { $0 }.filter(\.isFinite)
                if let earliest = dates.min() {
                    try db.run("UPDATE plugin_products SET earliest_date=? WHERE id=?", [String(earliest), id])
                }
            }
            try db.run("UPDATE plugin_installations SET product_id=? WHERE node_id=?", [id, nodeID])
            try db.run("UPDATE plugin_products SET archived=1 WHERE id=? AND NOT EXISTS (SELECT 1 FROM plugin_installations WHERE product_id=?)", [current[0], current[0]])
        }
        return id
    }

    public func load(scope: CatalogScope) throws -> CatalogSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do { try seedScope(db, scope: scope); try invalidateOmittedCoverage(db, scope: scope); try db.execute("COMMIT") }
        catch { try? db.execute("ROLLBACK"); throw error }
        return try read(db, scope: scope)
    }

    /// Recover the user's last saved collection when setup preferences are missing.
    /// The catalog already owns these configured roots; reading them does not scan.
    public func mostRecentSavedScope() throws -> CatalogScope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let db = try CatalogDatabase(url)
        guard let row = try db.strictRows("SELECT configuration FROM scopes WHERE generation!='unscanned' ORDER BY CAST(saved_at AS REAL) DESC LIMIT 1").first else { return nil }
        let scope = try decode(CatalogScope.self, row[0])
        let paths = scope.roots.values.flatMap { $0 }
        guard !paths.isEmpty,
              paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { throw CatalogStoreError.invalid }
        return scope
    }

    /// Writes inventory, graph memberships and observations in a single transaction.
    /// The returned projection strips removal identities; callers keep fresh identities
    /// only for items independently observed by their current scan.
    public func ingest(_ report: ScanReport, scope: CatalogScope, scannedKinds: Set<AssetKind> = Set(AssetKind.allCases), at date: Date = Date(), additionContext: AdditionScanContext? = nil, libraryJournalSource: URL? = nil) throws -> CatalogSnapshot {
        try Task.checkCancellation()
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            let priorGeneration = try db.rows("SELECT generation FROM scopes WHERE id=?", [scope.key]).first?.first
            try seedScope(db, scope: scope)
            if (priorGeneration == nil || priorGeneration == "unscanned") && scannedKinds != Set(AssetKind.allCases) {
                try seedCompatibleSections(db, scope: scope, scannedKinds: scannedKinds)
            }
            try invalidateOmittedCoverage(db, scope: scope)
            let completedRoots = try db.rows("SELECT kind,path,exclusions FROM root_baselines WHERE complete=1")
            guard date.timeIntervalSince1970.isFinite else { throw CatalogStoreError.invalid }
            // Only comparable complete root scans establish an absence/presence interval.
            var continuousRoots: [(kind: String, root: String, exclusions: [String], identity: String, lower: Date?)] = []
            for kind in scannedKinds.map(\.rawValue) {
                for root in scope.roots(for: kind) {
                    let exclusions = scope.exclusions(kind: kind, root: root)
                    let encoded = try encode(exclusions)
                    let prior = try db.strictRows("SELECT policy,root_identity,CAST(started AS TEXT),CAST(finished AS TEXT) FROM scan_coverage WHERE kind=? AND root=? AND exclusions=?", [kind, root, encoded]).first
                    let incomplete = report.issues.contains { issue in
                        if issue.reason.hasPrefix("Project reference coverage:") { return false }
                        if issue.reason.contains("Entry limit") { return true }
                        if kind == "library", issue.reason.contains("SINE") { return true }
                        return CatalogScope.contains(issue.path, root: root) || CatalogScope.contains(root, root: issue.path)
                    }
                    let identity = incomplete ? nil : additionContext?.identity(for: root, scope: scope, finishedAt: date)
                    var lower: Date?
                    if let prior, let identity, let context = additionContext,
                       prior[0] == AdditionScanContext.policy, prior[1].utf8.elementsEqual(identity.utf8),
                       let start = Double(prior[2]), let end = Double(prior[3]), start.isFinite, end.isFinite,
                       start <= end, end <= context.startedAt.timeIntervalSince1970 {
                        lower = Date(timeIntervalSince1970: start)
                    }
                    // A gap or policy change invalidates continuity, including other exclusion variants.
                    try db.run("DELETE FROM scan_coverage WHERE kind=? AND root=?", [kind, root])
                    if let identity, let context = additionContext {
                        continuousRoots.append((kind, root, exclusions, identity, lower))
                        try db.run("INSERT INTO scan_coverage(kind,root,exclusions,policy,root_identity,started,finished) VALUES(?,?,?,?,?,?,?)",
                                   [kind, root, encoded, AdditionScanContext.policy, identity, stamp(context.startedAt), stamp(date)])
                    }
                }
            }
            let generation = UUID().uuidString
            let old = try db.rows("SELECT evidence,generation,complete FROM scopes WHERE id=?", [scope.key]).first
            let previous = try old.map { try decode(ScanReport.self, $0[0]) }
            // Carry generation membership forward without claiming a new observation.
            if let old {
                for kind in AssetKind.allCases where !scannedKinds.contains(kind) {
                    for table in ["scope_members", "instruments", "physical_members"] {
                        try db.run("UPDATE \(table) SET generation=? WHERE scope_id=? AND generation=? AND node_id IN (SELECT id FROM nodes WHERE kind=?)", [generation, scope.key, old[1], kind.rawValue])
                    }
                }
            }
            var identities = PhysicalKeys()
            var manifestSources: [(String, String)] = []
            var articulationSources: [(String, String)] = []
            var physicalClusters: [([String], String)] = []
            var sinePairOwners: [String: Int] = [:]
            for asset in report.assets where asset.kind == .library && asset.format == "SINE" &&
                asset.libraryMetadata?.identity?.evidence == .vendorCatalog {
                let paths = Set((asset.libraryMetadata?.instruments ?? []).flatMap { $0.contentPaths ?? [] })
                for path in paths where URL(fileURLWithPath: path).pathExtension.lowercased() == "otmeta" {
                    let archive = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("otarc").path
                    if paths.contains(archive) { sinePairOwners[path, default: 0] += 1 }
                }
            }
            struct PriorUnassociated {
                let nodeID: String
                let asset: Asset
                let firstSeen: String
            }
            let priorUnassociated = try db.rows("""
                SELECT m.node_id,m.payload,CAST(n.first_seen AS TEXT) FROM scope_members m
                JOIN nodes n ON n.id=m.node_id WHERE m.scope_id=? AND n.kind='library'
                """, [scope.key]).compactMap { row -> PriorUnassociated? in
                    let old = try decode(Asset.self, row[1])
                    return old.classification == "unassociatedPhysicalContent"
                        ? PriorUnassociated(nodeID: row[0], asset: old, firstSeen: row[2]) : nil
                }
            struct PriorManifestBackup {
                let nodeID: String
                let path: String
                let asset: Asset
            }
            let priorManifestBackups = try db.rows("""
                SELECT m.node_id,m.path,m.payload FROM scope_members m
                JOIN nodes n ON n.id=m.node_id WHERE m.scope_id=? AND n.kind='library'
                """, [scope.key]).compactMap { row -> PriorManifestBackup? in
                    let old = try decode(Asset.self, row[2])
                    guard old.libraryMetadata?.identity?.evidence == .manifest else { return nil }
                return PriorManifestBackup(nodeID: row[0], path: row[1], asset: old)
            }
            let priorLooseKontakt = try db.rows("""
                SELECT m.node_id,m.path,m.payload FROM scope_members m
                JOIN nodes n ON n.id=m.node_id WHERE m.scope_id=? AND n.kind='library'
                """, [scope.key]).compactMap { row -> (nodeID: String, path: String)? in
                    let old = try decode(Asset.self, row[2])
                    return old.format == "Kontakt" && old.libraryMetadata?.identity?.evidence == .unresolved
                        ? (row[0], row[1]) : nil
                }
            let currentClusterPaths = Set(report.assets.filter { $0.classification == "unassociatedPhysicalContent" }.map(\.path))
            var bridgedClusterIDs = Set<String>()
            for asset in report.assets where scannedKinds.contains(asset.kind) {
                if asset.kind == .library,
                   asset.libraryMetadata?.identity?.productID?.hasPrefix("spectrasonics:") == true,
                   !SpectrasonicsLibraryIndex.sourceMatches(asset) { throw CatalogStoreError.sourceChanged }
                if asset.kind == .library, asset.libraryMetadata?.sizeBasis == .installedContent {
                    let paths = Array(Set((asset.libraryMetadata?.instruments ?? []).flatMap { $0.contentPaths ?? [] }))
                    guard let fingerprint = asset.libraryMetadata?.sizeSourceFingerprint,
                          let current = LibraryMetadataReader.physicalContentSnapshot(paths),
                          current.fingerprint == fingerprint, current.bytes == asset.logicalBytes else {
                        throw CatalogStoreError.sourceChanged
                    }
                    physicalClusters.append((paths, fingerprint))
                }
                if asset.kind == .library, asset.classification == "unassociatedPhysicalContent" {
                    guard let paths = asset.libraryMetadata?.physicalContentPaths,
                          let fingerprint = asset.libraryMetadata?.identity?.sourceFingerprint,
                          let physicalIdentity = asset.libraryMetadata?.physicalContentIdentity,
                          let current = LibraryMetadataReader.physicalContentSnapshot(paths),
                          current.bytes == asset.logicalBytes,
                          current.fingerprint == fingerprint,
                          current.physicalIdentity == physicalIdentity else { throw CatalogStoreError.sourceChanged }
                    physicalClusters.append((paths, fingerprint))
                }
                if asset.kind == .library, asset.libraryMetadata?.identity?.evidence == .manifest {
                    let source = asset.libraryMetadata?.identity?.sourceFingerprint
                        ?? LibraryMetadataReader.kontaktManifestFingerprint(URL(fileURLWithPath: asset.path))
                    guard let source, LibraryMetadataReader.kontaktManifestFingerprint(URL(fileURLWithPath: asset.path)) == source else {
                        throw CatalogStoreError.sourceChanged
                    }
                    manifestSources.append((asset.path, source))
                }
                var product = asset.libraryMetadata?.identity?.productID ?? ""
                if asset.kind == .library, asset.libraryMetadata?.identity?.evidence == .manifest, product.isEmpty {
                    // A manifest without a vendor ID has no proven logical continuity
                    // across replacement at the same inode/path. Its bounded metadata
                    // bytes distinguish a different product from the old history.
                    guard let fingerprint = manifestSources.last?.1 else { throw CatalogStoreError.sourceChanged }
                    product = "unidentified-manifest:" + fingerprint
                }
                if asset.kind == .library, asset.classification == "unassociatedPhysicalContent" {
                    guard let physicalIdentity = asset.libraryMetadata?.physicalContentIdentity else {
                        throw CatalogStoreError.sourceChanged
                    }
                    product = "unassociated-cluster:" + physicalIdentity
                }
                let physicalKey = identities.key(asset.path)
                let identity = asset.kind.rawValue + ":" + asset.format + ":" + product + ":" + physicalKey
                let existing = try db.rows("SELECT id FROM nodes WHERE identity=?", [identity]).first?.first
                let id = existing ?? UUID().uuidString
                let pluginProductID = asset.kind == .plugin ? try productID(for: asset, nodeID: id, db: db) : nil
                let covered = try completedRoots.contains { row in
                    guard row[0] == asset.kind.rawValue, CatalogScope.contains(asset.path, root: row[1]) else { return false }
                    return try !decode([String].self, row[2]).contains { CatalogScope.contains(asset.path, root: $0) }
                }
                let knownReplacement = try !db.rows("SELECT id FROM nodes WHERE kind=? AND path=?", [asset.kind.rawValue, asset.path]).isEmpty
                let baseline = !covered || knownReplacement
                var header = asset; header.catalogID = id; header.pluginProductID = pluginProductID; header.fileIdentity = nil
                let instruments = header.libraryMetadata?.instruments ?? []
                for instrument in instruments {
                    if let signature = instrument.articulationCoverage.sourceSignature {
                        guard let current = LibraryScanJournal.stamp(instrument.path),
                              LibraryScanJournal.signature(current) == signature else {
                            throw CatalogStoreError.sourceChanged
                        }
                        articulationSources.append((instrument.path, signature))
                    }
                }
                header.libraryMetadata?.instruments = []
                // A verified physical identity can survive moves/reconnects while
                // its current-directory added date changes or becomes unavailable.
                // Retain the earliest qualified date already observed for that
                // same identity; never transfer dates by display name or path alone.
                func earlierDate(_ current: Date?, _ previous: Date?) -> Date? {
                    [current, previous].compactMap { $0 }.filter {
                        $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 && $0 <= date
                    }.min()
                }
                if existing != nil, asset.kind != .plugin {
                    for row in try db.rows("SELECT payload FROM scope_members WHERE node_id=?", [id]) {
                        let prior = try decode(Asset.self, row[0])
                        header.finderDateAdded = earlierDate(header.finderDateAdded, prior.finderDateAdded)
                    }
                }
                var previousInstrumentDates: [String: Date] = [:]
                if existing != nil, !instruments.isEmpty {
                    for row in try db.rows("SELECT id,payload FROM instruments WHERE node_id=?", [id]) {
                        let prior = try decode(LibraryInstrument.self, row[1])
                        previousInstrumentDates[row[0]] = earlierDate(previousInstrumentDates[row[0]], prior.finderDateAdded)
                    }
                }
                try db.run("""
                    INSERT INTO nodes(id,identity,product_key,kind,path,first_seen,last_seen,baseline)
                    VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                    path=excluded.path,last_seen=excluded.last_seen
                    """, [id, identity, product, asset.kind.rawValue, asset.path, stamp(date), stamp(date), baseline ? "1" : "0"])
                try db.run("INSERT OR IGNORE INTO date_subjects(subject_id,parent_node_id,kind,identity_key) VALUES(?,?, 'asset','')", [id, id])
                if let pluginProductID {
                    try db.run("INSERT INTO plugin_installations(node_id,product_id) VALUES(?,?) ON CONFLICT(node_id) DO UPDATE SET product_id=excluded.product_id", [id, pluginProductID])
                }
                if existing == nil {
                    let lower = knownReplacement || !physicalKey.hasPrefix("file:") ? nil : continuousRoots.filter {
                        $0.kind == asset.kind.rawValue && CatalogScope.contains(asset.path, root: $0.root)
                            && !$0.exclusions.contains(where: { CatalogScope.contains(asset.path, root: $0) })
                    }.compactMap(\.lower).min()
                    let bounds = try AdditionDateEvidence(basis: lower == nil ? .presentBy : .observedArrival, lower: lower, upper: date)
                    try db.run("INSERT INTO node_addition_bounds(node_id,payload) VALUES(?,?)", [id, try encode(bounds)])
                }
                // Retain unobserved children; a bounded adapter cannot prove their absence.
                for instrument in instruments {
                    let key = instrument.vendorID ?? identities.key(instrument.path)
                    let subjectID = AssetUsageSubject.instrumentID(parentNodeID: id, instrument: instrument)
                    let identityKey = AssetUsageSubject.instrumentIdentityKey(instrument)
                    try db.run("INSERT INTO date_subjects(subject_id,parent_node_id,kind,identity_key) VALUES(?,?, 'instrument',?) ON CONFLICT(parent_node_id,kind,identity_key) DO NOTHING", [subjectID, id, identityKey])
                    var retainedInstrument = instrument
                    retainedInstrument.finderDateAdded = earlierDate(instrument.finderDateAdded, previousInstrumentDates[key])
                    var bridgedPair: PriorUnassociated?
                    if asset.kind == .library, asset.format == "SINE",
                       asset.libraryMetadata?.identity?.evidence == .vendorCatalog {
                        let members = Set(instrument.contentPaths ?? [])
                        bridgedPair = priorUnassociated.first { old in
                            guard let paths = old.asset.libraryMetadata?.physicalContentPaths, paths.count >= 2,
                                  paths.count.isMultiple(of: 2),
                                  paths.filter({ URL(fileURLWithPath: $0).pathExtension.lowercased() == "otmeta" }).count * 2 == paths.count,
                                  paths.filter({ URL(fileURLWithPath: $0).pathExtension.lowercased() == "otmeta" }).allSatisfy({ meta in
                                      paths.contains(URL(fileURLWithPath: meta).deletingPathExtension().appendingPathExtension("otarc").path)
                                          && sinePairOwners[meta] == 1
                                  }),
                                  members.isSuperset(of: paths),
                                  let snapshot = LibraryMetadataReader.physicalContentSnapshot(paths) else { return false }
                            return snapshot.physicalIdentity == old.asset.libraryMetadata?.physicalContentIdentity
                        }
                        if let bridgedPair, bridgedPair.asset.path == instrument.path {
                            retainedInstrument.finderDateAdded = earlierDate(retainedInstrument.finderDateAdded,
                                                                             bridgedPair.asset.finderDateAdded)
                        }
                    }
                    try db.run("""
                        INSERT INTO instruments(scope_id,node_id,id,usage_subject_id,payload,generation,observed_at) VALUES(?,?,?,?,?,?,?)
                        ON CONFLICT(scope_id,node_id,id) DO UPDATE SET usage_subject_id=excluded.usage_subject_id,payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at
                        """, [scope.key, id, key, subjectID, try encode(retainedInstrument), generation, stamp(date)])
                    if let bridgedPair {
                        bridgedClusterIDs.insert(bridgedPair.nodeID)
                        let destination = MetadataSubject(nodeID: id, instrument: instrument).key
                        let source = MetadataSubject(nodeID: bridgedPair.nodeID).key
                        try db.run("INSERT OR IGNORE INTO metadata_overrides(subject,node_id,payload) SELECT ?,?,payload FROM metadata_overrides WHERE subject=?", [destination, id, source])
                    }
                    for path in instrument.contentPaths ?? [] {
                        let observed = bridgedPair?.asset.libraryMetadata?.physicalContentPaths?.contains(path) == true
                            ? bridgedPair!.firstSeen : stamp(date)
                        try db.run("INSERT INTO physical_members(scope_id,node_id,instrument_id,path,generation,observed_at) VALUES(?,?,?,?,?,?) ON CONFLICT(scope_id,node_id,instrument_id,path) DO UPDATE SET generation=excluded.generation,observed_at=MIN(physical_members.observed_at,excluded.observed_at)", [scope.key, id, key, path, generation, observed])
                    }
                }
                if asset.kind == .library, asset.libraryMetadata?.identity?.evidence == .manifest {
                    try db.run("DELETE FROM scope_members WHERE scope_id=? AND path=? AND node_id!=? AND node_id IN (SELECT id FROM nodes WHERE kind='library')", [scope.key, asset.path, id])
                } else {
                    try db.run("DELETE FROM scope_members WHERE scope_id=? AND path=? AND node_id!=? AND node_id IN (SELECT id FROM nodes WHERE product_key=? AND kind=?)", [scope.key, asset.path, id, product, asset.kind.rawValue])
                }
                try db.run("INSERT INTO scope_members(scope_id,node_id,path,payload,generation,baseline,observed_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(scope_id,node_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at", [scope.key, id, asset.path, try encode(header), generation, baseline ? "1" : "0", stamp(date)])
                if let pluginProductID { try db.run("UPDATE plugin_products SET archived=0 WHERE id=?", [pluginProductID]) }
                if let pluginProductID, let added = asset.finderDateAdded {
                    guard added.timeIntervalSince1970.isFinite else { throw CatalogStoreError.invalid }
                    try db.run("UPDATE plugin_products SET earliest_date=CASE WHEN earliest_date IS NULL OR earliest_date>? THEN ? ELSE earliest_date END WHERE id=?", [stamp(added), stamp(added), pluginProductID])
                }
                if asset.kind == .plugin { try db.run("DELETE FROM removals WHERE path=?", [asset.path]) }
            }
            // A formerly discovered nested copy of the same NICNT may have been
            // retained after a newer scanner learned to suppress metadata-only
            // backups. Retire only the visible scope row when a byte-identical,
            // vendor-qualified parent now owns actual patches. Keep the node,
            // dates and any edits untouched; edited backups remain visible.
            for current in report.assets where scannedKinds.contains(.library) {
                guard let identity = current.libraryMetadata?.identity,
                      identity.evidence == .manifest,
                      let productID = identity.productID, !productID.isEmpty,
                      let fingerprint = identity.sourceFingerprint,
                      let installationRoot = identity.installationRoot,
                      current.libraryMetadata?.instruments.isEmpty == false,
                      URL(fileURLWithPath: current.path).deletingLastPathComponent().standardizedFileURL.path
                        == URL(fileURLWithPath: installationRoot).standardizedFileURL.path else { continue }
                for old in priorManifestBackups {
                    guard old.nodeID != current.catalogID,
                          let oldIdentity = old.asset.libraryMetadata?.identity,
                          oldIdentity.productID == productID,
                          oldIdentity.sourceFingerprint == fingerprint,
                          old.asset.libraryMetadata?.instruments.isEmpty != false,
                          CatalogScope.contains(old.path, root: installationRoot),
                          old.path != current.path,
                          try db.rows("SELECT 1 FROM instruments WHERE scope_id=? AND node_id=? LIMIT 1", [scope.key, old.nodeID]).isEmpty,
                          try db.rows("SELECT 1 FROM metadata_overrides WHERE node_id=? LIMIT 1", [old.nodeID]).isEmpty else { continue }
                    try db.run("DELETE FROM scope_members WHERE scope_id=? AND node_id=?", [scope.key, old.nodeID])
                }
            }
            // A better structural owner can absorb an old loose patch folder. Hide
            // only a completely rehomed, unedited row after a complete root scan;
            // keep its node and any uncertain history instead of guessing a transfer.
            if scannedKinds.contains(.library) {
                let owners = report.assets.filter { asset in
                    guard asset.kind == .library, asset.format == "Kontakt",
                          let evidence = asset.libraryMetadata?.identity?.evidence else { return false }
                    return evidence == .proposed || evidence == .manifest
                }
                for old in priorLooseKontakt {
                    guard !report.assets.contains(where: { $0.kind == .library && $0.path == old.path }),
                          try db.rows("SELECT 1 FROM metadata_overrides WHERE node_id=? LIMIT 1", [old.nodeID]).isEmpty,
                          try db.rows("SELECT 1 FROM date_evidence WHERE subject_id IN (SELECT subject_id FROM date_subjects WHERE parent_node_id=?) LIMIT 1", [old.nodeID]).isEmpty else { continue }
                    let oldPaths = Set(try db.rows("SELECT payload FROM instruments WHERE scope_id=? AND node_id=?", [scope.key, old.nodeID])
                        .map { try decode(LibraryInstrument.self, $0[0]).path })
                    guard !oldPaths.isEmpty else { continue }
                    let matches = owners.filter { owner in
                        guard let root = owner.libraryMetadata?.identity?.installationRoot,
                              old.path.hasPrefix(root + "/") else { return false }
                        let currentPaths = Set(owner.libraryMetadata?.instruments.map(\.path) ?? [])
                        return currentPaths.isSuperset(of: oldPaths)
                    }
                    guard matches.count == 1, let root = matches[0].libraryMetadata?.identity?.installationRoot,
                          scope.roots(for: "library").contains(where: { selected in
                              CatalogScope.contains(root, root: selected) &&
                                  !report.issues.contains(where: { issue in
                                      CatalogScope.contains(issue.path, root: selected) ||
                                          CatalogScope.contains(selected, root: issue.path)
                                  })
                          }) else { continue }
                    try db.run("DELETE FROM scope_members WHERE scope_id=? AND node_id=?", [scope.key, old.nodeID])
                }
            }
            for old in priorUnassociated {
                if bridgedClusterIDs.contains(old.nodeID) || currentClusterPaths.contains(old.asset.path) {
                    // The new exact physical owner or a new version of this
                    // unresolved cluster supersedes the old visible scope row.
                    let newSamePath = report.assets.first { $0.classification == "unassociatedPhysicalContent" && $0.path == old.asset.path }
                    let samePhysicalIdentity = newSamePath?.libraryMetadata?.physicalContentIdentity
                        == old.asset.libraryMetadata?.physicalContentIdentity
                    if bridgedClusterIDs.contains(old.nodeID) || !samePhysicalIdentity {
                        try db.run("DELETE FROM scope_members WHERE scope_id=? AND node_id=?", [scope.key, old.nodeID])
                    }
                }
            }
            var boundProjects = report.projects
            if scannedKinds.contains(.sample) {
                let libraryRows = try db.rows("""
                    SELECT m.node_id,m.payload FROM scope_members m JOIN nodes n ON n.id=m.node_id
                    WHERE m.scope_id=? AND n.kind='library'
                    """, [scope.key])
                var libraryAssets = try libraryRows.map { try decode(Asset.self, $0[1]) }
                // Headers omit child instruments. Load only the players with
                // structurally identified saved-state membership.
                let childOwnerIDs = libraryRows.enumerated().compactMap { index, row in
                    ["Spectrasonics", "SINE"].contains(libraryAssets[index].format) ? row[0] : nil
                }
                if !childOwnerIDs.isEmpty {
                    var children: [String: [LibraryInstrument]] = [:]
                    for start in stride(from: 0, to: childOwnerIDs.count, by: 400) {
                        let chunk = Array(childOwnerIDs[start..<min(start + 400, childOwnerIDs.count)])
                        let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                        let childRows = try db.rows("SELECT node_id,payload,generation FROM instruments WHERE scope_id=? AND node_id IN (\(marks))",
                            [scope.key] + chunk)
                        for row in childRows {
                            var child = try decode(LibraryInstrument.self, row[1])
                            child.catalogStale = row[2] != generation
                            children[row[0], default: []].append(child)
                        }
                    }
                    for index in libraryAssets.indices where ["Spectrasonics", "SINE"].contains(libraryAssets[index].format) {
                        libraryAssets[index].libraryMetadata?.instruments = children[libraryRows[index][0]] ?? []
                    }
                }
                let liveClassIDs = Set(boundProjects.filter { $0.adapter == "ableton-kontakt-live12" }
                    .flatMap { $0.pluginClasses ?? [] }.map(\.classID))
                let cubaseClassIDs = Set(boundProjects.filter { $0.adapter == "cubase-kontakt-15.0.30" }
                    .flatMap { $0.pluginClasses ?? [] }.map(\.classID))
                let pluginAssets = try db.rows("""
                    SELECT m.payload FROM scope_members m JOIN nodes n ON n.id=m.node_id
                    WHERE m.scope_id=? AND n.kind='plugin'
                    """, [scope.key]).map { try decode(Asset.self, $0[0]) }
                let sampleRows = try db.rows("""
                    SELECT m.node_id,m.path,n.identity FROM scope_members m JOIN nodes n ON n.id=m.node_id
                    WHERE m.scope_id=? AND n.kind='sample' AND m.generation=?
                    """, [scope.key, generation])
                let samplesByPath = Dictionary(grouping: sampleRows, by: { $0[1] })
                let home = FileManager.default.homeDirectoryForCurrentUser
                let liveCache = home.appendingPathComponent("Library/Application Support/Ableton/Live Database/Live-plugins-1.db")
                let liveBindings = liveClassIDs.isEmpty ? [] :
                    ((try? LivePluginCache.bindings(LivePluginCache.read(liveCache).filter { liveClassIDs.contains($0.classID) },
                        assets: pluginAssets)) ?? [])
                let cubaseCache = home.appendingPathComponent("Library/Preferences/Cubase 15/Cubase Pro VST3 Cache (arm64)/vst3plugins.xml")
                let cubaseClasses = cubaseClassIDs.isEmpty ? [] :
                    ((try? CubasePluginCache.read(cubaseCache).filter { cubaseClassIDs.contains($0.cid) }) ?? [])
                var membershipRecords: [AssetDateEvidence] = []
                for index in boundProjects.indices {
                    guard boundProjects[index].kontaktStates != nil || boundProjects[index].spectrasonicsStates != nil ||
                          boundProjects[index].sineInstrumentIDs != nil ||
                          boundProjects[index].pluginClasses != nil || boundProjects[index].aaxPlugins != nil ||
                          boundProjects[index].logicAUReferences != nil ||
                          !boundProjects[index].references.isEmpty,
                          let fingerprint = boundProjects[index].sourceSHA256,
                          let savedAt = boundProjects[index].projectModifiedAt else { continue }
                    let projectURL = URL(fileURLWithPath: boundProjects[index].path)
                    let sourceURL = URL(fileURLWithPath: boundProjects[index].sourcePath ?? projectURL.path)
                    if boundProjects[index].adapter == "logic-saved-au" {
                        guard let sourcePath = boundProjects[index].sourcePath,
                              CatalogScope.contains(sourcePath, root: projectURL.path + "/Alternatives") &&
                              sourceURL.lastPathComponent == "ProjectData",
                              (try? ProjectReader.selectedLogicProjectData(projectURL).path) == sourcePath
                        else { throw CatalogStoreError.sourceChanged }
                    }
                    if boundProjects[index].readerPolicyVersion == ProjectReader.policyVersion,
                       let signature = boundProjects[index].sourceSignature,
                       signature.utf8.count == 64, fingerprint.utf8.count == 64 {
                        // The reader stamped before and after its bounded read.
                        // Recheck that same source at commit without reading the
                        // entire saved project a second time on every refresh.
                        guard LibraryMetadataReader.safe(sourceURL),
                              let stamp = LibraryScanJournal.stamp(sourceURL.path),
                              LibraryScanJournal.signature(stamp) == signature else {
                            throw CatalogStoreError.sourceChanged
                        }
                    } else {
                        // Old or externally supplied reports have no trusted read
                        // boundary; keep the original byte-for-byte check.
                        let current = try BoundedFile.read(sourceURL, limit: ProjectReader.maximumInputBytes)
                        let currentHash = SHA256.hash(data: current).map { String(format: "%02x", $0) }.joined()
                        guard currentHash == fingerprint else { throw CatalogStoreError.sourceChanged }
                    }
                    let pathHash = SHA256.hash(data: Data(boundProjects[index].path.utf8))
                        .map { String(format: "%02x", $0) }.joined()
                    var itemSubjects = Set<String>()
                    func appendItem(_ subjectID: String, kind: AssetKind, identity: String,
                                    adapter: String) throws {
                        guard itemSubjects.insert(subjectID).inserted, savedAt <= date else { return }
                        let provenance = ProjectItemMembership(adapter: adapter, subjectKind: kind,
                            sourceIdentity: identity, projectSHA256: fingerprint, projectPathSHA256: pathHash)
                        let eventID = try provenance.eventID(subjectID: subjectID, savedAt: savedAt)
                        if let prior = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                            [ProjectItemMembership.sourceID, eventID]).first {
                            let existing = try decodeDateEvidence(prior)
                            guard existing.subjectID == subjectID, existing.projectItemMembership == provenance,
                                  existing.eventDate == savedAt else { throw AssetDateEvidenceError.conflictingEvidenceID }
                            return
                        }
                        membershipRecords.append(AssetDateEvidence(sourceID: ProjectItemMembership.sourceID,
                            evidenceID: eventID, subjectID: subjectID, kind: .projectReference,
                            eventDate: savedAt, ingestedAt: date, projectItemMembership: provenance))
                    }
                    if let classes = boundProjects[index].pluginClasses {
                        for item in classes {
                            if boundProjects[index].adapter == "ableton-kontakt-live12" {
                                let matches = liveBindings.filter { $0.classID == item.classID }
                                guard matches.count == 1, let binding = matches.first,
                                      (try? binding.revalidate()) != nil,
                                      let asset = pluginAssets.first(where: { $0.path == binding.path && $0.format == "vst3" && $0.catalogStale != true }),
                                      let subjectID = asset.catalogID else { continue }
                                try appendItem(subjectID, kind: .plugin, identity: item.classID, adapter: "ableton-vst3-live12")
                            } else if boundProjects[index].adapter == "cubase-kontakt-15.0.30" {
                                let matches = cubaseClasses.filter { $0.cid == item.classID && $0.category == "Audio Module Class" }
                                guard matches.count == 1, let match = matches.first,
                                      LibraryMetadataReader.safe(URL(fileURLWithPath: match.path)),
                                      FileManager.default.fileExists(atPath: match.path),
                                      let asset = pluginAssets.first(where: { $0.path == match.path && $0.format == "vst3" && $0.catalogStale != true }),
                                      let subjectID = asset.catalogID else { continue }
                                try appendItem(subjectID, kind: .plugin, identity: item.classID, adapter: "cubase-vst3-15.0.30")
                            }
                        }
                    }
                    if let entries = boundProjects[index].aaxPlugins,
                       boundProjects[index].adapter == "protools-ptx-plugin-list" {
                        for entry in entries {
                            let pieces = entry.effectID.lowercased().split(separator: ".")
                            guard pieces.count >= 4 else { continue }
                            let makerNamespace = pieces.prefix(2).joined(separator: ".") + "."
                            let matches = pluginAssets.filter { asset in
                                asset.format == "aaxplugin" && asset.catalogStale != true &&
                                asset.name == entry.name &&
                                asset.bundleIdentifier?.lowercased().hasPrefix(makerNamespace) == true &&
                                LibraryMetadataReader.safe(URL(fileURLWithPath: asset.path)) &&
                                Bundle(url: URL(fileURLWithPath: asset.path))?.bundleIdentifier == asset.bundleIdentifier
                            }
                            guard matches.count == 1, let subjectID = matches.first?.catalogID else { continue }
                            try appendItem(subjectID, kind: .plugin, identity: entry.effectID, adapter: "protools-ptx-aax")
                        }
                    }
                    if let references = boundProjects[index].logicAUReferences,
                       boundProjects[index].adapter == "logic-saved-au" {
                        for reference in Set(references) {
                            let matches = pluginAssets.filter { asset in
                                guard asset.format == "component", asset.catalogStale != true,
                                      LibraryMetadataReader.safe(URL(fileURLWithPath: asset.path)),
                                      let bundle = Bundle(url: URL(fileURLWithPath: asset.path)),
                                      bundle.bundleIdentifier == asset.bundleIdentifier,
                                      let components = bundle.infoDictionary?["AudioComponents"] as? [[String: Any]] else { return false }
                                return components.contains { component in
                                    component["type"] as? String == reference.type &&
                                    component["subtype"] as? String == reference.subtype &&
                                    component["manufacturer"] as? String == reference.manufacturer
                                }
                            }
                            guard matches.count == 1, let subjectID = matches.first?.catalogID else { continue }
                            try appendItem(subjectID, kind: .plugin, identity: reference.identity, adapter: "logic-saved-au")
                        }
                    }
                    if let sineIDs = boundProjects[index].sineInstrumentIDs,
                       boundProjects[index].adapter == "cubase-kontakt-15.0.30" {
                        for instrumentID in Set(sineIDs) {
                            let matches = libraryAssets.filter { $0.format == "SINE" && $0.catalogStale != true }
                                .flatMap { asset in (asset.libraryMetadata?.instruments ?? []).compactMap { instrument -> (Asset, LibraryInstrument)? in
                                    guard instrument.vendorID?.hasSuffix(":instrument:\(instrumentID)") == true,
                                          instrument.catalogStale != true else { return nil }
                                    return (asset, instrument)
                                }}
                            guard matches.count == 1, let (asset, instrument) = matches.first,
                                  let parentID = asset.catalogID,
                                  !(instrument.contentPaths ?? []).isEmpty,
                                  (instrument.contentPaths ?? []).allSatisfy({ LibraryMetadataReader.safe(URL(fileURLWithPath: $0)) && FileManager.default.fileExists(atPath: $0) }) else { continue }
                            let subjectID = AssetUsageSubject.instrumentID(parentNodeID: parentID, instrument: instrument)
                            try appendItem(subjectID, kind: .library, identity: instrumentID, adapter: "cubase-sine-15.0.30")
                        }
                    }
                    if ["rpp", "ableton-kontakt-live12"].contains(boundProjects[index].adapter) {
                        var physicalKeys = PhysicalKeys()
                        for reference in boundProjects[index].references where reference.kind == .sample {
                            guard let path = reference.resolvedPath,
                                  scope.includes(kind: "sample", path: path),
                                  LibraryMetadataReader.safe(URL(fileURLWithPath: path)),
                                  let candidates = samplesByPath[path], candidates.count == 1,
                                  let row = candidates.first else { continue }
                            let physical = physicalKeys.key(path)
                            guard physical.hasPrefix("file:"), row[2].hasSuffix(":" + physical) else { continue }
                            try appendItem(row[0], kind: .sample, identity: physical,
                                adapter: boundProjects[index].adapter == "rpp" ? "reaper-rpp" : "ableton-sample-live12")
                        }
                    }
                    if let states = boundProjects[index].kontaktStates {
                        let ids = Array(Set(states.flatMap(\.libraryIDs))).sorted()
                        let resolved = KontaktLibraryBinding.resolve(libraryIDs: ids, assets: libraryAssets)
                        var outcomes: [KontaktLibraryOutcome] = []
                        var recordedSubjects = Set<String>()
                        for state in states { for id in state.libraryIDs {
                            let binding = resolved.bindings[id]
                            outcomes.append(KontaktLibraryOutcome(instanceOrdinal: state.instanceOrdinal,
                                libraryID: id, catalogID: binding?.catalogID,
                                status: binding == nil ? "unknownLibraryID" : "identifiedLibrary"))
                            guard let subjectID = binding?.catalogID, recordedSubjects.insert(subjectID).inserted,
                                  savedAt <= date else { continue }
                            let provenance = ProjectLibraryMembership(adapter: boundProjects[index].adapter,
                                publicLibraryID: id, projectSHA256: fingerprint, projectPathSHA256: pathHash)
                            let eventID = try provenance.eventID(subjectID: subjectID, savedAt: savedAt)
                            if let prior = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                                [ProjectLibraryMembership.sourceID, eventID]).first {
                                let existing = try decodeDateEvidence(prior)
                                guard existing.subjectID == subjectID, existing.projectMembership == provenance,
                                      existing.eventDate == savedAt else { throw AssetDateEvidenceError.conflictingEvidenceID }
                                continue
                            }
                            membershipRecords.append(AssetDateEvidence(sourceID: ProjectLibraryMembership.sourceID,
                                evidenceID: eventID,
                                subjectID: subjectID, kind: .projectReference, eventDate: savedAt,
                                ingestedAt: date, projectMembership: provenance))
                        }}
                        boundProjects[index].kontaktOutcomes = outcomes
                    }
                    if let states = boundProjects[index].spectrasonicsStates {
                        var outcomes: [SpectrasonicsLibraryOutcome] = []
                        var recordedSubjects = Set<String>()
                        for state in states { for part in state.state.parts {
                            let binding = SpectrasonicsLibraryIndex.resolve(part: part, player: state.state.player,
                                assets: libraryAssets)
                            let subjectID = binding?.asset.catalogID
                            outcomes.append(SpectrasonicsLibraryOutcome(instanceOrdinal: state.instanceOrdinal,
                                partSlot: part.slot, libraryName: part.library, presetName: part.name,
                                catalogID: subjectID, status: binding?.match ?? "unidentifiedContent"))
                            guard let subjectID, recordedSubjects.insert(subjectID).inserted,
                                  let identity = binding?.asset.libraryMetadata?.identity,
                                  let productID = identity.productID, savedAt <= date else { continue }
                            let provenance = ProjectLibraryMembership(adapter: "cubase-spectrasonics-15.0.30",
                                publicLibraryID: productID, projectSHA256: fingerprint,
                                projectPathSHA256: pathHash, player: binding?.asset.libraryMetadata?.player,
                                presetName: part.name)
                            let eventID = try provenance.eventID(subjectID: subjectID, savedAt: savedAt)
                            if let prior = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                                [ProjectLibraryMembership.spectrasonicsSourceID, eventID]).first {
                                let existing = try decodeDateEvidence(prior)
                                guard existing.subjectID == subjectID, existing.projectMembership == provenance,
                                      existing.eventDate == savedAt else { throw AssetDateEvidenceError.conflictingEvidenceID }
                                continue
                            }
                            membershipRecords.append(AssetDateEvidence(sourceID: ProjectLibraryMembership.spectrasonicsSourceID,
                                evidenceID: eventID, subjectID: subjectID, kind: .projectReference,
                                eventDate: savedAt, ingestedAt: date, projectMembership: provenance))
                        }}
                        boundProjects[index].spectrasonicsOutcomes = outcomes
                    }
                }
                try appendDateEvidence(membershipRecords, asOf: date, to: db)
            }
            var evidence = ScanReport(schemaVersion: report.schemaVersion, assets: [], projects: boundProjects,
                sampleInclusions: report.sampleInclusions, issues: report.issues, durationSeconds: report.durationSeconds).merging(previous: previous, scannedKinds: scannedKinds)
            // A full scan's inclusion rows are exactly reproducible from its
            // committed sample nodes and bound project references. Keep legacy or
            // independently supplied rows explicit unless equivalence is proven.
            if scannedKinds == Set(AssetKind.allCases),
               evidence.sampleInclusions == ScanReport.deriveSampleInclusions(assets: report.assets, projects: evidence.projects) {
                evidence = ScanReport(schemaVersion: evidence.schemaVersion, assets: [], projects: evidence.projects,
                    sampleInclusions: [], issues: evidence.issues, durationSeconds: evidence.durationSeconds,
                    sampleInclusionsDerived: true)
            }
            try db.run("""
                INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET evidence=excluded.evidence,saved_at=excluded.saved_at,
                generation=excluded.generation,complete=MAX(scopes.complete,excluded.complete)
                """, [scope.key, try encode(scope), try encode(evidence), stamp(date), generation, scannedKinds == Set(AssetKind.allCases) && report.issues.isEmpty ? "1" : (old?[2] ?? "0")])
            for kind in scannedKinds.map(\.rawValue) {
                for root in scope.roots(for: kind) {
                    let incomplete = report.issues.contains { issue in
                        if issue.reason.hasPrefix("Project reference coverage:") { return false }
                        if issue.reason.contains("Entry limit") { return true }
                        if kind == "library", issue.reason.contains("SINE") { return true }
                        return CatalogScope.contains(issue.path, root: root) || CatalogScope.contains(root, root: issue.path)
                    }
                    if !incomplete {
                        try db.run("INSERT INTO root_baselines(kind,path,exclusions,complete) VALUES(?,?,?,1) ON CONFLICT(kind,path,exclusions) DO UPDATE SET complete=1", [kind, root, try encode(scope.exclusions(kind: kind, root: root))])
                    }
                }
            }
            for (path, fingerprint) in manifestSources {
                guard LibraryMetadataReader.kontaktManifestFingerprint(URL(fileURLWithPath: path)) == fingerprint else {
                    throw CatalogStoreError.sourceChanged
                }
            }
            for (path, signature) in articulationSources {
                guard let current = LibraryScanJournal.stamp(path),
                      LibraryScanJournal.signature(current) == signature else {
                    throw CatalogStoreError.sourceChanged
                }
            }
            for (paths, fingerprint) in physicalClusters {
                guard LibraryMetadataReader.physicalContentSnapshot(paths)?.fingerprint == fingerprint else {
                    throw CatalogStoreError.sourceChanged
                }
            }
            if let libraryJournalSource, scannedKinds.contains(.library),
               !report.issues.contains(where: { $0.kind == .library }) {
                for root in scope.roots(for: "library") {
                    let rootURL = URL(fileURLWithPath: root)
                    let journal = try LibraryScanJournal(baseURL: url, scope: scope, root: rootURL, source: libraryJournalSource)
                    guard try journal.validateCompleted() else { throw CatalogStoreError.sourceChanged }
                }
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
        guard let snapshot = try read(db, scope: scope) else { throw CatalogStoreError.invalid }
        return snapshot
    }

    /// Atomic replacement. Empty facet values are durable suppression; nil resets all overrides.
    public func saveMetadata(_ value: MusicalMetadata?, for subject: MetadataSubject) throws {
        try saveMetadataBatch([(subject, value)])
    }

    /// Atomically retain immutable evidence for exact existing catalog node IDs.
    /// No source qualification, instrument/product association or timestamp inference occurs.
    /// Replays retain their original ingestion date. Each node retains at most 10,000
    /// records; capacity/conflicts reject the batch without pruning history.
    public func appendDateEvidence(_ records: [AssetDateEvidence], asOf: Date) throws {
        _ = try AssetDateResolver.summarize(records, for: "validation", asOf: asOf)
        guard !records.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            try appendDateEvidence(records, asOf: asOf, to: db)
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    // Caller owns the writer transaction and has validated the incoming batch.
    private nonisolated func appendDateEvidence(_ records: [AssetDateEvidence], asOf: Date,
                                                to db: CatalogDatabase) throws {
        var counts: [Data: Int] = [:]
        for record in records {
            guard try !db.dateRows("SELECT subject_id FROM date_subjects WHERE subject_id=?", [record.subjectID]).isEmpty else { throw CatalogStoreError.invalid }
            let key = Data(record.subjectID.utf8)
            if counts[key] == nil {
                counts[key] = try readDateEvidence(db, for: record.subjectID, asOf: asOf).count
            }
        }
        for record in records {
            let existing = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID])
            if let row = existing.first {
                guard try decodeDateEvidence(row) == record else { throw AssetDateEvidenceError.conflictingEvidenceID }
                continue
            }
            let key = Data(record.subjectID.utf8)
            guard counts[key, default: 0] < AssetDateResolver.maximumRecords else { throw AssetDateEvidenceError.tooManyRecords }
            let payload = try encode(record)
            guard payload.utf8.count <= CatalogDatabase.maximumDateTextBytes else { throw CatalogStoreError.invalid }
            try db.run("INSERT INTO date_evidence(source_id,evidence_id,subject_id,payload) VALUES(?,?,?,?)",
                       [record.sourceID, record.evidenceID, record.subjectID, payload])
            counts[key, default: 0] += 1
        }
    }

    /// Bind a live receipt observation to one exact, still-present plugin installation.
    /// Atomic and idempotent; preserves first ingestion and historical provenance.
    /// Rejects mismatched/stale physical identity, removal intent and changed bundles.
    /// Does not mark retained inventory fresh or establish original addition/actual use.
    public func recordPackageReceipt(_ observation: PackageReceiptReader.Observation,
                                     for nodeID: String, at ingestionDate: Date) throws -> AssetDateEvidence {
        try recordPackageReceipt(observation, for: nodeID, at: ingestionDate, beforeFinalValidation: {})
    }

    // Internal failure seam exercises rollback after insertion, before commit.
    func recordPackageReceipt(_ observation: PackageReceiptReader.Observation,
                              for nodeID: String, at ingestionDate: Date,
                              beforeFinalValidation: @Sendable () throws -> Void) throws -> AssetDateEvidence {
        try Task.checkCancellation()
        let report = observation.report
        _ = try AssetDateResolver.summarize([], for: nodeID, asOf: ingestionDate)
        guard report.status == .associated, report.observedAt.timeIntervalSince1970.isFinite,
              report.observedAt <= ingestionDate else { throw CatalogStoreError.invalid }
        let provenance = PackageReceiptProvenance(packageID: report.packageID, packageVersion: report.packageVersion,
            bundlePath: report.bundlePath, bundleIdentifier: report.bundleIdentifier, bundleVersions: report.bundleVersions)
        let eventID = try provenance.eventID(subjectID: nodeID, date: report.receiptDate)
        func evidence(ingestedAt: Date) -> AssetDateEvidence {
            AssetDateEvidence(sourceID: PackageReceiptProvenance.sourceID, evidenceID: eventID,
                subjectID: nodeID, kind: .installationRecord, eventDate: report.receiptDate,
                ingestedAt: ingestedAt, packageReceipt: provenance)
        }
        var record = evidence(ingestedAt: ingestionDate)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: ingestionDate)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            try observation.revalidate()
            var identities = PhysicalKeys()
            let physical = identities.key(report.bundlePath)
            let format = URL(fileURLWithPath: report.bundlePath).pathExtension.lowercased()
            guard physical.hasPrefix("file:"),
                  let node = try db.dateRows("SELECT identity,kind,path FROM nodes WHERE id=?", [nodeID]).first,
                  node[0].utf8.elementsEqual(("plugin:" + format + "::" + physical).utf8),
                  node[1] == "plugin", node[2].utf8.elementsEqual(report.bundlePath.utf8),
                  try db.dateRows("SELECT path FROM removals WHERE path=?", [report.bundlePath]).isEmpty else {
                throw CatalogStoreError.invalid
            }
            let headers = try db.dateRows("""
                SELECT payload,path FROM scope_members WHERE node_id=? AND observed_at=
                (SELECT MAX(observed_at) FROM scope_members WHERE node_id=?) LIMIT 10001
                """, [nodeID, nodeID])
            guard !headers.isEmpty, headers.count <= AssetDateResolver.maximumRecords else { throw CatalogStoreError.invalid }
            for row in headers {
                let header = try decode(Asset.self, row[0])
                guard header.kind == .plugin, header.catalogID?.utf8.elementsEqual(nodeID.utf8) == true,
                      header.format.utf8.elementsEqual(format.utf8),
                      header.path.utf8.elementsEqual(report.bundlePath.utf8),
                      row[1].utf8.elementsEqual(report.bundlePath.utf8),
                      header.bundleIdentifier?.utf8.elementsEqual(report.bundleIdentifier.utf8) == true else {
                    throw CatalogStoreError.invalid
                }
            }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                                        [record.sourceID, eventID]).first {
                let previous = try decodeDateEvidence(row)
                record = evidence(ingestedAt: previous.ingestedAt)
                guard record == previous else { throw AssetDateEvidenceError.conflictingEvidenceID }
            }
            _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: ingestionDate)
            try appendDateEvidence([record], asOf: ingestionDate, to: db)
            try beforeFinalValidation()
            try observation.revalidate()
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Retain a completed VST3 class-use event, associated with a currently verified
    /// catalog installation. This never asserts historical use of these physical bytes.
    /// Replays preserve first ingestion; cancellation/identity changes roll back writes.
    public func recordHostUsage(_ event: HostUsageProvenance, binding: LivePluginCache.Binding,
                                for nodeID: String, at date: Date, deadline: Double = .infinity) throws -> AssetDateEvidence {
        func check() throws {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogStoreError.busy }
        }
        try check(); try event.validate()
        guard event.classID.utf8.elementsEqual(binding.classID.utf8), FileManager.default.fileExists(atPath: url.path) else {
            throw CatalogStoreError.invalid
        }
        let eventID = try event.eventID(subjectID: nodeID)
        func make(_ ingestion: Date) -> AssetDateEvidence {
            AssetDateEvidence(sourceID: event.eventSourceID, evidenceID: eventID, subjectID: nodeID,
                kind: .confirmedUse, eventDate: nil, ingestedAt: ingestion, hostUsage: event)
        }
        var record = make(date)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            try check(); try binding.revalidate()
            var identities = PhysicalKeys()
            let physical = identities.key(binding.path)
            guard physical.hasPrefix("file:"),
                  let node = try db.dateRows("SELECT identity,kind,path FROM nodes WHERE id=?", [nodeID]).first,
                  node[0].utf8.elementsEqual(("plugin:vst3::" + physical).utf8), node[1] == "plugin",
                  node[2].utf8.elementsEqual(binding.path.utf8),
                  try db.dateRows("SELECT path FROM removals WHERE path=?", [binding.path]).isEmpty else { throw CatalogStoreError.invalid }
            let headers = try db.dateRows("""
                SELECT payload,path FROM scope_members WHERE node_id=? AND observed_at=
                (SELECT MAX(observed_at) FROM scope_members WHERE node_id=?) LIMIT 10001
                """, [nodeID, nodeID])
            guard !headers.isEmpty, headers.count <= AssetDateResolver.maximumRecords else { throw CatalogStoreError.invalid }
            for row in headers {
                let header = try decode(Asset.self, row[0])
                guard header.kind == .plugin, header.catalogID?.utf8.elementsEqual(nodeID.utf8) == true,
                      header.format == "vst3", header.path.utf8.elementsEqual(binding.path.utf8),
                      row[1].utf8.elementsEqual(binding.path.utf8),
                      header.bundleIdentifier?.utf8.elementsEqual(binding.snapshot.identifier.utf8) == true else { throw CatalogStoreError.invalid }
            }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?",
                                        [record.sourceID, eventID]).first {
                let prior = try decodeDateEvidence(row); record = make(prior.ingestedAt)
                guard record == prior else { throw AssetDateEvidenceError.conflictingEvidenceID }
            }
            _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
            try appendDateEvidence([record], asOf: date, to: db)
            try binding.revalidate(); try check()
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Retain a qualified Cubase event only when its current catalog node still
    /// points at the exact cache-resolved VST3 path. The class history is explicit;
    /// physical byte lineage is not inferred.
    public func recordCubaseUsage(_ use: CubaseBoundPluginUse, for nodeID: String, at date: Date) throws -> AssetDateEvidence {
        let record = AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.use.eventID,
            subjectID: nodeID, kind: use.use.evidenceKind, eventDate: use.use.reportedDate, ingestedAt: date,
            cubaseUsage: use.use)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let node = try db.dateRows("SELECT kind,path FROM nodes WHERE id=?", [nodeID]).first
            guard node?.count == 2, node?[0] == "plugin", node?[1] == use.pluginPath,
                  use.cid.utf8.count == 32 else { throw CatalogStoreError.invalid }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(row)
                guard prior.subjectID == record.subjectID,
                      (prior.kind == .confirmedUse || prior.kind == .loadAttempt),
                      prior.eventDate == record.eventDate,
                      prior.cubaseUsage?.isSameHostEvent(as: use.use) == true else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            } else { try appendDateEvidence([record], asOf: date, to: db) }
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    public func recordProToolsUsage(_ use: ProToolsBoundPluginUse, for nodeID: String, at date: Date) throws -> AssetDateEvidence {
        let sourceID = use.use.eventSourceID
        let record = AssetDateEvidence(sourceID: sourceID,
            evidenceID: use.use.subjectEventID(nodeID),
            subjectID: nodeID, kind: sourceID == ProToolsPluginUse.attemptedSourceID ? .loadAttempt : .confirmedUse,
            eventDate: nil, ingestedAt: date,
            proToolsUsage: use.use)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let node = try db.dateRows("SELECT kind,path FROM nodes WHERE id=?", [nodeID])
            guard node.count == 1, node[0].count == 2, node[0][0] == "plugin", node[0][1] == use.pluginPath else { throw CatalogStoreError.invalid }
            let siblingSource = sourceID == ProToolsPluginUse.attemptedSourceID
                ? ProToolsPluginUse.restoreV2SourceID : ProToolsPluginUse.attemptedSourceID
            if let sibling = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [siblingSource, record.evidenceID]).first {
                let prior = try decodeDateEvidence(sibling)
                guard prior.subjectID == nodeID, prior.proToolsUsage?.eventID == use.use.eventID else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(row)
                guard prior.subjectID == record.subjectID, prior.kind == record.kind,
                      prior.eventDate == record.eventDate, prior.proToolsUsage == record.proToolsUsage else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            } else { try appendDateEvidence([record], asOf: date, to: db) }
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    public func recordLogicUsage(_ use: LogicPluginUse, for nodeID: String, at date: Date) throws -> AssetDateEvidence {
        let record = AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: use.eventID,
            subjectID: nodeID, kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: date,
            logicUsage: use)
        _ = try AssetDateResolver.summarize([record], for: nodeID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let node = try db.dateRows("SELECT kind,path FROM nodes WHERE id=?", [nodeID])
            guard node.count == 1, node[0].count == 2, node[0][0] == "plugin", node[0][1].hasSuffix(".component") else { throw CatalogStoreError.invalid }
            if let row = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(row)
                guard prior.subjectID == record.subjectID, prior.kind == record.kind,
                      prior.eventDate == record.eventDate, prior.logicUsage == record.logicUsage else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            } else { try appendDateEvidence([record], asOf: date, to: db) }
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Latest reported use per exact node, preserving source and class scope.
    /// Same-day Live records compare their full source-local clock. Incomparable host
    /// clocks use a stable family order, never an inferred cross-host chronology.
    /// One atomic read; corruption yields no partial projection.
    public func latestHostUsage(for nodeIDs: [String], asOf: Date,
                                savedProjectOnly: Bool = false) throws -> [Data: AssetDateEvidence] {
        try Task.checkCancellation()
        guard nodeIDs.count <= 2048, FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.invalid }
        let db = try CatalogDatabase(url); try db.execute("BEGIN")
        do {
            var result: [Data: AssetDateEvidence] = [:], total = 0
            for id in nodeIDs {
                try Task.checkCancellation()
                let records = try readDateEvidence(db, for: id, asOf: asOf); total += records.count
                guard total <= 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                let usage = records.filter {
                    if savedProjectOnly { return $0.projectItemMembership != nil }
                    return $0.itemAccess != nil || $0.hostUsage != nil || $0.cubaseUsage != nil ||
                        (($0.sourceID == ProToolsPluginUse.restoreV2SourceID || $0.sourceID == ProToolsPluginUse.attemptedSourceID) && $0.proToolsUsage != nil) ||
                        $0.logicUsage != nil
                }.sorted { HostUsageOrdering.precedes($0, $1) }
                if let first = usage.first { result[Data(id.utf8)] = first }
            }
            try db.execute("COMMIT"); return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Latest typed item activity for exact current assets and their library instruments.
    /// Input is a batch of parent node IDs; existing evidence rows join the current registry,
    /// so large instrument inventories cost one bounded query rather than one hash/query each.
    public func latestItemUsage(for parentNodeIDs: [String], in scope: CatalogScope,
                                asOf: Date, savedProjectOnly: Bool = false) throws -> [Data: AssetDateEvidence] {
        try Task.checkCancellation()
        guard parentNodeIDs.count <= 2_048, FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.invalid }
        let db = try CatalogDatabase(url); try db.execute("BEGIN")
        do {
            try Task.checkCancellation()
            let parentIDs = Array(Set(parentNodeIDs)).sorted()
            if parentIDs.isEmpty { try db.execute("COMMIT"); return [:] }
            for id in parentIDs { _ = try AssetDateResolver.summarize([], for: id, asOf: asOf) }
            let marks = Array(repeating: "?", count: parentIDs.count).joined(separator: ",")
            let registered = try db.dateRows("SELECT parent_node_id FROM date_subjects WHERE kind='asset' AND subject_id=parent_node_id AND parent_node_id IN (\(marks))", parentIDs)
            guard Set(registered.map { $0.first ?? "" }) == Set(parentIDs) else { throw CatalogStoreError.invalid }
            let rows = try db.dateRows("""
                SELECT e.source_id,e.evidence_id,e.subject_id,e.payload,s.parent_node_id,s.kind,s.identity_key,COALESCE(i.payload,'') FROM date_evidence e
                JOIN date_subjects s ON s.subject_id=e.subject_id
                LEFT JOIN instruments i ON i.node_id=s.parent_node_id AND i.usage_subject_id=s.subject_id AND i.scope_id=?
                WHERE s.parent_node_id IN (\(marks)) AND s.kind IN ('asset','instrument') AND e.source_id IN (?,?,?,?)
                ORDER BY e.subject_id,e.source_id,e.evidence_id LIMIT 100001
                """, [scope.key] + parentIDs + [ItemAccessProvenance.sourceID, ProjectLibraryMembership.sourceID,
                                            ProjectLibraryMembership.spectrasonicsSourceID, ProjectItemMembership.sourceID])
            guard rows.count <= 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
            var grouped: [String: [AssetDateEvidence]] = [:], parents: [String: String] = [:]
            var kinds: [String: String] = [:], identityKeys: [String: String] = [:], paths: [String: String] = [:]
            for row in rows {
                try Task.checkCancellation()
                guard row.count == 8 else { throw CatalogStoreError.invalid }
                let record = try decodeDateEvidence(Array(row.prefix(4)))
                grouped[record.subjectID, default: []].append(record)
                parents[record.subjectID] = row[4]; kinds[record.subjectID] = row[5]
                identityKeys[record.subjectID] = row[6]
                if row[5] == "instrument", !row[7].isEmpty {
                    paths[record.subjectID] = try decode(LibraryInstrument.self, row[7]).path
                }
            }
            var result: [Data: AssetDateEvidence] = [:]
            func merge(_ record: AssetDateEvidence, for key: Data) {
                if let current = result[key], !HostUsageOrdering.precedes(record, current) { return }
                result[key] = record
            }
            for (id, records) in grouped {
                _ = try AssetDateResolver.summarize(records, for: id, asOf: asOf)
                guard records.count <= AssetDateResolver.maximumRecords else { throw AssetDateEvidenceError.tooManyRecords }
                if let first = records.filter({ savedProjectOnly
                    ? ($0.projectMembership != nil || $0.projectItemMembership != nil)
                    : ($0.itemAccess != nil || $0.projectMembership != nil || $0.projectItemMembership != nil)
                }).sorted(by: { HostUsageOrdering.precedes($0, $1) }).first {
                    if kinds[id] == "asset" { merge(first, for: Data(id.utf8)) }
                    if paths[id] != nil, let parent = parents[id], let identityKey = identityKeys[id] {
                        let projectionKey = AssetUsageSubject.instrumentUsageKey(parentNodeID: parent, identityKey: identityKey)
                        merge(first, for: Data(projectionKey.utf8))
                    }
                    if kinds[id] == "instrument", let parent = parents[id] {
                        let key = Data(parent.utf8)
                        merge(first, for: key)
                    }
                }
            }
            try db.execute("COMMIT"); return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Record a source-qualified access after the collector has bound it to an exact
    /// registered asset or instrument. The write is atomic and idempotent.
    func recordItemAccess(_ access: ItemAccessProvenance, parentNodeID: String,
                          instrument: LibraryInstrument? = nil, eventDate: Date,
                          ingestedAt date: Date) throws -> AssetDateEvidence {
        let subjectID = instrument.map { AssetUsageSubject.instrumentID(parentNodeID: parentNodeID, instrument: $0) } ?? parentNodeID
        let record = AssetDateEvidence(sourceID: ItemAccessProvenance.sourceID,
            evidenceID: try access.eventID(subjectID: subjectID), subjectID: subjectID,
            kind: access.evidenceKind, eventDate: eventDate, ingestedAt: date, itemAccess: access)
        _ = try AssetDateResolver.summarize([record], for: subjectID, asOf: date)
        let db = try CatalogDatabase(url); try db.execute("BEGIN IMMEDIATE")
        do {
            let registration = try db.dateRows("SELECT parent_node_id,kind,identity_key FROM date_subjects WHERE subject_id=?", [subjectID])
            if let instrument {
                guard registration.count == 1, registration[0][0] == parentNodeID,
                      registration[0][1] == "instrument",
                      registration[0][2] == AssetUsageSubject.instrumentIdentityKey(instrument) else { throw CatalogStoreError.invalid }
            } else {
                guard subjectID == parentNodeID, registration.count == 1,
                      registration[0][0] == parentNodeID, registration[0][1] == "asset" else { throw CatalogStoreError.invalid }
            }
            if let priorRow = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE source_id=? AND evidence_id=?", [record.sourceID, record.evidenceID]).first {
                let prior = try decodeDateEvidence(priorRow)
                guard prior.subjectID == record.subjectID, prior.eventDate == eventDate,
                      prior.kind == record.kind, prior.itemAccess == access else { throw AssetDateEvidenceError.conflictingEvidenceID }
                try db.execute("COMMIT"); return prior
            }
            try appendDateEvidence([record], asOf: date, to: db)
            try db.execute("COMMIT"); return record
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Product history includes qualified events from prior format installations.
    public func latestProductUsage(for productIDs: [String], asOf: Date,
                                   savedProjectOnly: Bool = false) throws -> [Data: AssetDateEvidence] {
        guard productIDs.count <= 2048 else { throw AssetDateEvidenceError.tooManyRecords }
        let db = try CatalogDatabase(url)
        var owners: [Data: String] = [:]
        for id in Set(productIDs) {
            for row in try db.rows("SELECT node_id FROM plugin_installations WHERE product_id=? LIMIT 100001", [id]) {
                guard owners.count < 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                owners[Data(row[0].utf8)] = id
            }
        }
        var result: [Data: AssetDateEvidence] = [:]
        let nodes = owners.keys.map { String(decoding: $0, as: UTF8.self) }.sorted()
        for offset in stride(from: 0, to: nodes.count, by: 2048) {
            let records = try latestHostUsage(for: Array(nodes[offset..<min(offset + 2048, nodes.count)]),
                                              asOf: asOf, savedProjectOnly: savedProjectOnly)
            for (node, record) in records {
                guard let product = owners[node] else { continue }
                let key = Data(product.utf8)
                if let prior = result[key], !HostUsageOrdering.precedes(record, prior) { continue }
                result[key] = record
            }
        }
        return result
    }

    /// Read a bounded, validated history in one database snapshot. Missing database/node
    /// and corrupt evidence throw; an existing node without history returns an empty array.
    public func dateEvidence(for nodeID: String, asOf: Date) throws -> [AssetDateEvidence] {
        _ = try AssetDateResolver.summarize([], for: nodeID, asOf: asOf)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN")
        do {
            let records = try readDateEvidence(db, for: nodeID, asOf: asOf)
            try db.execute("COMMIT")
            return records
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Latest typed installer receipt per exact UTF-8 node ID, in one read snapshot.
    /// No partial result on corruption/missing nodes/budget overflow. At most 2,048
    /// requested IDs and 100,000 validated history records; unknown nodes are not inferred.
    public func latestInstallerRecords(for nodeIDs: [String], asOf: Date) throws -> [Data: AssetDateEvidence] {
        try Task.checkCancellation()
        guard nodeIDs.count <= 2_048 else { throw AssetDateEvidenceError.tooManyRecords }
        for id in nodeIDs { _ = try AssetDateResolver.summarize([], for: id, asOf: asOf) }
        _ = try AssetDateResolver.summarize([], for: "validation", asOf: asOf)
        guard !nodeIDs.isEmpty else { return [:] }
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.unavailable }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN")
        do {
            var seen = Set<Data>(), result: [Data: AssetDateEvidence] = [:], count = 0
            for id in nodeIDs where seen.insert(Data(id.utf8)).inserted {
                try Task.checkCancellation()
                let records = try readDateEvidence(db, for: id, asOf: asOf)
                count += records.count
                guard count <= 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                // readDateEvidence is ordered by binary source/event; keep first at equal dates.
                for record in records where record.packageReceipt != nil {
                    if let date = record.eventDate, result[Data(id.utf8)]?.eventDate.map({ date > $0 }) ?? true {
                        result[Data(id.utf8)] = record
                    }
                }
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Derived from retained source events, never from catalog scan or restore time.
    public func dateSummary(for nodeID: String, asOf: Date) throws -> AssetDateSummary {
        try AssetDateResolver.summarize(dateEvidence(for: nodeID, asOf: asOf), for: nodeID, asOf: asOf)
    }

    /// Earliest qualified original addition per exact node. Scan observations,
    /// receipts, and use events never enter this projection.
    public func confirmedAdditionDates(for nodeIDs: [String], asOf: Date) throws -> [Data: Date] {
        try Task.checkCancellation()
        guard nodeIDs.count <= 2_048, FileManager.default.fileExists(atPath: url.path) else { throw CatalogStoreError.invalid }
        let db = try CatalogDatabase(url); try db.execute("BEGIN")
        do {
            var result: [Data: Date] = [:], seen = Set<Data>(), total = 0
            for id in nodeIDs where seen.insert(Data(id.utf8)).inserted {
                try Task.checkCancellation()
                let records = try readDateEvidence(db, for: id, asOf: asOf)
                total += records.count
                guard total <= 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                let dates = records.filter { $0.kind == .confirmedAddition }.compactMap(\.eventDate)
                if let earliest = dates.min() { result[Data(id.utf8)] = earliest }
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    public func productConfirmedAdditionDates(for productIDs: [String], asOf: Date) throws -> [String: Date] {
        guard productIDs.count <= 2048 else { throw AssetDateEvidenceError.tooManyRecords }
        let db = try CatalogDatabase(url)
        var owners: [Data: String] = [:]
        for id in Set(productIDs) {
            for row in try db.rows("SELECT node_id FROM plugin_installations WHERE product_id=? LIMIT 100001", [id]) {
                guard owners.count < 100_000 else { throw AssetDateEvidenceError.tooManyRecords }
                owners[Data(row[0].utf8)] = id
            }
        }
        let nodes = owners.keys.map { String(decoding: $0, as: UTF8.self) }.sorted()
        var result: [String: Date] = [:]
        for offset in stride(from: 0, to: nodes.count, by: 2048) {
            for (node, date) in try confirmedAdditionDates(for: Array(nodes[offset..<min(offset + 2048, nodes.count)]), asOf: asOf) {
                guard let owner = owners[node] else { continue }
                result[owner] = min(result[owner] ?? date, date)
            }
        }
        return result
    }

    private nonisolated func readDateEvidence(_ db: CatalogDatabase, for nodeID: String, asOf: Date) throws -> [AssetDateEvidence] {
        guard try !db.rows("SELECT subject_id FROM date_subjects WHERE subject_id=?", [nodeID]).isEmpty else { throw CatalogStoreError.invalid }
        let rows = try db.dateRows("SELECT source_id,evidence_id,subject_id,payload FROM date_evidence WHERE subject_id=? ORDER BY source_id,evidence_id LIMIT 10001", [nodeID])
        let records = try rows.map(decodeDateEvidence)
        _ = try AssetDateResolver.summarize(records, for: nodeID, asOf: asOf)
        return records
    }

    private nonisolated func decodeDateEvidence(_ row: [String]) throws -> AssetDateEvidence {
        guard row.count == 4 else { throw CatalogStoreError.invalid }
        let record = try decode(AssetDateEvidence.self, row[3])
        guard record.sourceID.utf8.elementsEqual(row[0].utf8),
              record.evidenceID.utf8.elementsEqual(row[1].utf8),
              record.subjectID.utf8.elementsEqual(row[2].utf8) else { throw CatalogStoreError.invalid }
        return record
    }

    /// Commit all overrides together, including deletions. Any invalid subject rolls back the batch.
    public func saveMetadataBatch(_ edits: [(MetadataSubject, MusicalMetadata?)]) throws {
        let edits = try edits.map { ($0.0, try $0.1?.validated()) }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            for (subject, value) in edits {
                if subject.instrumentKey == nil,
                   try !db.rows("SELECT id FROM plugin_products WHERE id=?", [subject.nodeID]).isEmpty {
                    try db.run("UPDATE plugin_products SET metadata=? WHERE id=?", [try value.map(encode) ?? "", subject.nodeID])
                    continue
                }
                guard try !db.rows("SELECT id FROM nodes WHERE id=?", [subject.nodeID]).isEmpty else { throw CatalogStoreError.invalid }
                if let value, !value.fields.isEmpty {
                    try db.run("INSERT INTO metadata_overrides(subject,node_id,payload) VALUES(?,?,?) ON CONFLICT(subject) DO UPDATE SET payload=excluded.payload", [subject.key, subject.nodeID, try encode(value)])
                } else { try db.run("DELETE FROM metadata_overrides WHERE subject=?", [subject.key]) }
            }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Seed only selected locations from the latest known payload for each observation.
    /// A new scope has no fresh generation: transferred records are stale until scanned.
    private func invalidateOmittedCoverage(_ db: CatalogDatabase, scope: CatalogScope) throws {
        for row in try db.strictRows("SELECT kind,root,exclusions FROM scan_coverage") {
            guard scope.roots(for: row[0]).contains(row[1]),
                  try encode(scope.exclusions(kind: row[0], root: row[1])) == row[2] else {
                try db.run("DELETE FROM scan_coverage WHERE kind=? AND root=? AND exclusions=?", row)
                continue
            }
        }
    }

    private func seedScope(_ db: CatalogDatabase, scope: CatalogScope) throws {
        var inserted = try !db.rows("SELECT id FROM scopes WHERE id=?", [scope.key]).isEmpty
        let candidates = try db.rows("""
            SELECT m.scope_id,m.node_id,m.path,m.payload,m.baseline,n.kind,s.saved_at,m.observed_at
            FROM scope_members m JOIN nodes n ON n.id=m.node_id JOIN scopes s ON s.id=m.scope_id
            ORDER BY m.observed_at DESC,s.saved_at DESC,m.scope_id
            """)
        var seen = Set<String>(); var locations = Set<String>()
        for row in candidates where scope.includes(kind: row[5], path: row[2]) {
            let asset = try decode(Asset.self, row[3])
            let location = row[5] + ":" + row[2] + ":" + (asset.libraryMetadata?.identity?.productID ?? "")
            guard seen.insert(row[1]).inserted, locations.insert(location).inserted else { continue }
            if !inserted {
                let evidence = ScanReport(schemaVersion: 1, assets: [], projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
                try db.run("INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?,?,0)", [scope.key, try encode(scope), try encode(evidence), row[6], "unscanned"])
                inserted = true
            }
            let previous = try db.rows("SELECT observed_at FROM scope_members WHERE scope_id=? AND node_id=?", [scope.key, row[1]]).first
            if row[0] != scope.key, previous == nil || (Double(row[7]) ?? 0) > (Double(previous![0]) ?? 0) {
                try db.run("DELETE FROM scope_members WHERE scope_id=? AND path=? AND node_id!=? AND node_id IN (SELECT id FROM nodes WHERE kind=? AND product_key=?)", [scope.key, row[2], row[1], row[5], asset.libraryMetadata?.identity?.productID ?? ""])
                try db.run("INSERT INTO scope_members(scope_id,node_id,path,payload,generation,baseline,observed_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(scope_id,node_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at", [scope.key, row[1], row[2], row[3], "retained", row[4], row[7]])
            }
            // Children carry their own observation dates: an offline scan must not win
            // over a newer patch/member merely because its containing scope was saved later.
            let children = try db.rows("SELECT id,payload,observed_at,usage_subject_id FROM instruments WHERE node_id=? ORDER BY observed_at DESC", [row[1]])
            var childIDs = Set<String>()
            for child in children where childIDs.insert(child[0]).inserted {
                let instrument = try decode(LibraryInstrument.self, child[1])
                guard scope.includes(kind: "library", path: instrument.path) else { continue }
                try db.run("INSERT INTO instruments(scope_id,node_id,id,payload,generation,observed_at,usage_subject_id) VALUES(?,?,?,?,'retained',?,?) ON CONFLICT(scope_id,node_id,id) DO UPDATE SET payload=excluded.payload,generation=excluded.generation,observed_at=excluded.observed_at WHERE excluded.observed_at>instruments.observed_at", [scope.key, row[1], child[0], child[1], child[2], child[3]])
                for member in try db.rows("SELECT path,MAX(observed_at) FROM physical_members WHERE node_id=? AND instrument_id=? GROUP BY path", [row[1], child[0]]) {
                    try db.run("INSERT INTO physical_members(scope_id,node_id,instrument_id,path,generation,observed_at) VALUES(?,?,?,?,'retained',?) ON CONFLICT(scope_id,node_id,instrument_id,path) DO UPDATE SET generation=excluded.generation,observed_at=excluded.observed_at WHERE excluded.observed_at>physical_members.observed_at", [scope.key, row[1], child[0], member[0], member[1]])
                }
            }
        }
    }

    /// Root changes in one section do not invalidate independently unchanged sections.
    private func seedCompatibleSections(_ db: CatalogDatabase, scope: CatalogScope, scannedKinds: Set<AssetKind>) throws {
        let candidates = try db.rows("SELECT id,configuration,evidence,generation,saved_at FROM scopes WHERE id!=? AND generation!='unscanned' ORDER BY CAST(saved_at AS REAL) DESC,id", [scope.key])
        var evidence = ScanReport(schemaVersion: 1, assets: [], projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
        for kind in AssetKind.allCases where !scannedKinds.contains(kind) {
            let dependencies = kind == .plugin ? ["plugins"] : kind == .sample ? ["samples", "libraries", "projects"] : ["libraries", "samples"]
            for row in candidates {
                let source = try decode(CatalogScope.self, row[1])
                guard dependencies.allSatisfy({ source.roots[$0] == scope.roots[$0] }) else { continue }
                let saved = try decode(ScanReport.self, row[2])
                let section = ScanReport(schemaVersion: saved.schemaVersion, assets: [],
                    projects: kind == .sample ? saved.projects : [], sampleInclusions: kind == .sample ? saved.sampleInclusions : [],
                    issues: saved.issues.filter { $0.kind == kind || $0.kind == nil }, durationSeconds: 0,
                    sampleInclusionsDerived: kind == .sample ? saved.sampleInclusionsDerived : nil)
                evidence = section.merging(previous: evidence, scannedKinds: [kind])
                // Only equal observations transfer freshness. Newer incompatible observations
                // stay retained/stale; no observation or baseline timestamp is advanced.
                try db.run("""
                    UPDATE scope_members AS target SET generation='unscanned' WHERE scope_id=?
                    AND node_id IN (SELECT id FROM nodes WHERE kind=?) AND EXISTS
                    (SELECT 1 FROM scope_members source WHERE source.scope_id=? AND source.node_id=target.node_id
                    AND source.generation=? AND source.observed_at=target.observed_at)
                    """, [scope.key, kind.rawValue, row[0], row[3]])
                for (table, key) in [("instruments", "id"), ("physical_members", "instrument_id")] {
                    let pathMatch = table == "physical_members" ? " AND source.path=target.path" : ""
                    try db.run("""
                        UPDATE \(table) AS target SET generation='unscanned' WHERE scope_id=?
                        AND node_id IN (SELECT id FROM nodes WHERE kind=?) AND EXISTS
                        (SELECT 1 FROM \(table) source WHERE source.scope_id=? AND source.node_id=target.node_id
                        AND source.\(key)=target.\(key)\(pathMatch) AND source.generation=? AND source.observed_at=target.observed_at)
                        """, [scope.key, kind.rawValue, row[0], row[3]])
                }
                break
            }
        }
        try db.run("""
            INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?, 'unscanned',0)
            ON CONFLICT(id) DO UPDATE SET evidence=excluded.evidence
            """, [scope.key, try encode(scope), try encode(evidence), candidates.first?[4] ?? "0"])
    }

    /// Durable intent precedes filesystem removal so a crash cannot resurrect an old
    /// cached plugin. Failed/canceled removals are restored by a subsequent fresh scan.
    public func recordRemovalIntent(paths: Set<String>) throws {
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            for path in paths { try db.run("INSERT OR IGNORE INTO removals(path) VALUES(?)", [path]) }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Resolve only reviewed attempts. A failed or canceled Trash operation cannot
    /// hide an installation on the next catalog restore.
    public func finalizePluginRemoval(attempted: Set<String>, succeeded: Set<String>, scope: CatalogScope) throws {
        guard succeeded.isSubset(of: attempted) else { throw CatalogStoreError.invalid }
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            for path in attempted.subtracting(succeeded) { try db.run("DELETE FROM removals WHERE path=?", [path]) }
            for path in succeeded {
                for row in try db.rows("SELECT p.product_id FROM plugin_installations p JOIN scope_members m ON m.node_id=p.node_id WHERE m.scope_id=? AND m.path=?", [scope.key, path]) {
                    let survivors = try db.rows("""
                        SELECT m.node_id FROM scope_members m JOIN plugin_installations p ON p.node_id=m.node_id
                        JOIN scopes s ON s.id=m.scope_id WHERE p.product_id=? AND m.generation=s.generation
                        AND m.path NOT IN (SELECT path FROM removals) LIMIT 1
                        """, [row[0]])
                    if survivors.isEmpty { try db.run("UPDATE plugin_products SET archived=1 WHERE id=?", [row[0]]) }
                }
            }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    /// Explicit local backup. Destination must not exist; no automatic upload/import.
    public func backup(to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CatalogStoreError.unavailable }
        let source = try CatalogDatabase(url)
        let target = try CatalogDatabase(destination)
        guard let backup = sqlite3_backup_init(target.handle, "main", source.handle, "main") else { throw CatalogStoreError.unavailable }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw CatalogStoreError.unavailable }
    }

    private func read(_ db: CatalogDatabase, scope: CatalogScope) throws -> CatalogSnapshot? {
        // Read transaction prevents mixing a snapshot header and rows from different commits.
        try db.execute("BEGIN")
        do {
            guard let snapshot = try db.rows("SELECT evidence,saved_at,generation FROM scopes WHERE id=?", [scope.key]).first else { try db.execute("COMMIT"); return nil }
            let evidence = try decode(ScanReport.self, snapshot[0])
            guard let time = Double(snapshot[1]) else { throw CatalogStoreError.invalid }
            let generation = snapshot[2]
            let rows = try db.rows("""
                SELECT n.id,m.payload,n.first_seen,n.last_seen,n.baseline,m.generation,p.product_id FROM nodes n
                JOIN scope_members m ON m.node_id=n.id LEFT JOIN plugin_installations p ON p.node_id=n.id WHERE m.scope_id=?
                AND NOT (n.kind='plugin' AND m.path IN (SELECT path FROM removals)) ORDER BY n.id
                """, [scope.key])
            let childRows = try db.rows("""
                SELECT i.node_id,i.payload,i.generation,i.id FROM instruments i
                JOIN scope_members m ON m.node_id=i.node_id AND m.scope_id=i.scope_id WHERE m.scope_id=? ORDER BY i.node_id,i.id
                """, [scope.key])
            let memberRows = try db.rows("SELECT node_id,instrument_id,path,generation FROM physical_members WHERE scope_id=? ORDER BY path", [scope.key])
            var members: [String: [String: [LibraryContentMember]]] = [:]
            for row in memberRows {
                members[row[0], default: [:]][row[1], default: []].append(LibraryContentMember(path: row[2], stale: row[3] != generation))
            }
            let staleParents = Set(rows.filter { $0[5] != generation }.map { $0[0] })
            var children: [String: [LibraryInstrument]] = [:]
            for row in childRows {
                var child = try decode(LibraryInstrument.self, row[1])
                child.catalogStale = row[2] != generation || staleParents.contains(row[0])
                if let known = members[row[0]]?[row[3]] {
                    child.contentMembers = known.map { LibraryContentMember(path: $0.path, stale: $0.stale || child.catalogStale == true) }; child.contentPaths = known.map(\.path)
                }
                children[row[0], default: []].append(child)
            }
            let additionRows = try db.strictRows("SELECT node_id,payload FROM node_addition_bounds WHERE node_id IN (SELECT node_id FROM scope_members WHERE scope_id=?)", [scope.key])
            var additions: [Data: AdditionDateEvidence] = [:]
            for row in additionRows {
                guard additions.updateValue(try decode(AdditionDateEvidence.self, row[1]).validated(), forKey: Data(row[0].utf8)) == nil else { throw CatalogStoreError.invalid }
            }
            var assets: [Asset] = []; var observations: [String: CatalogObservation] = [:]
            for row in rows {
                var asset = try decode(Asset.self, row[1]); asset.fileIdentity = nil
                if asset.kind == .plugin { asset.pluginProductID = row[6].isEmpty ? nil : row[6] }
                asset.libraryMetadata?.instruments = children[row[0]] ?? []
                guard let first = Double(row[2]), let last = Double(row[3]) else { throw CatalogStoreError.invalid }
                let stale = row[5] != generation
                asset.catalogStale = stale
                assets.append(asset)
                observations[row[0]] = CatalogObservation(id: row[0], firstSeen: Date(timeIntervalSince1970: first),
                    lastSeen: Date(timeIntervalSince1970: last), baseline: row[4] == "1", stale: stale,
                    addition: try additions[Data(row[0].utf8)] ?? AdditionDateEvidence(basis: .presentBy, lower: nil, upper: Date(timeIntervalSince1970: first)))
            }
            let inclusions = evidence.sampleInclusionsDerived == true
                ? ScanReport.deriveSampleInclusions(assets: assets.filter { $0.catalogStale != true }, projects: evidence.projects)
                : evidence.sampleInclusions
            let report = ScanReport(schemaVersion: evidence.schemaVersion, assets: assets, projects: evidence.projects,
                sampleInclusions: inclusions, issues: evidence.issues, durationSeconds: evidence.durationSeconds)
            let metadataRows = try db.rows("SELECT subject,payload FROM metadata_overrides WHERE node_id IN (SELECT node_id FROM scope_members WHERE scope_id=?)", [scope.key])
            var metadata = try Dictionary(uniqueKeysWithValues: metadataRows.map { ($0[0], try decode(MusicalMetadata.self, $0[1]).validated()) })
            let productRows = try db.rows("SELECT id,metadata,CAST(earliest_date AS TEXT),name FROM plugin_products")
            var productDates: [String: Date] = [:]
            var productNames: [String: String] = [:]
            for row in productRows {
                if !row[1].isEmpty { metadata[MetadataSubject(nodeID: row[0]).key] = try decode(MusicalMetadata.self, row[1]).validated() }
                if let time = Double(row[2]), time.isFinite { productDates[row[0]] = Date(timeIntervalSince1970: time) }
                productNames[row[0]] = row[3]
            }
            try db.execute("COMMIT")
            return CatalogSnapshot(report: report, savedAt: Date(timeIntervalSince1970: time), observations: observations, metadata: metadata, pluginProductDates: productDates, pluginProductNames: productNames)
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    private nonisolated func stamp(_ date: Date) -> String { String(date.timeIntervalSince1970) }
    private nonisolated func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private nonisolated func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch { throw CatalogStoreError.invalid }
    }
}

struct PhysicalKeys {
    var volumes: [Int32: String] = [:]
    mutating func key(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        var info = stat()
        guard LibraryMetadataReader.safe(url), lstat(path, &info) == 0,
              (info.st_mode & S_IFMT == S_IFDIR || info.st_nlink == 1), info.st_mode & S_IFMT != S_IFLNK else { return "path:" + path }
        if volumes[info.st_dev] == nil {
            volumes[info.st_dev] = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? ""
        }
        guard let volume = volumes[info.st_dev], !volume.isEmpty else { return "path:" + path }
        return "file:\(volume):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
    }
}

/// Owned by one actor operation; prepared statements and connections never escape it.
private final class CatalogDatabase {
    var handle: OpaquePointer?
    private static let applicationID = 0x534D504C
    init(_ url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        var existing = parent
        while !fm.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        guard LibraryMetadataReader.safe(existing) else { throw CatalogStoreError.unavailable }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard LibraryMetadataReader.safe(parent) else { throw CatalogStoreError.unavailable }
        var info = stat()
        if lstat(url.path, &info) != 0 {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CatalogStoreError.unavailable }; close(descriptor)
        } else {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw CatalogStoreError.unavailable }
        }
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil; throw CatalogStoreError.unavailable
        }
        do {
            sqlite3_busy_timeout(handle, 250)
            // A 99,000-sample scan can produce about 20 MiB of per-sample reference
            // evidence in the single scope row. Keep a bounded cell above that size;
            // rows() also enforces its separate 128 MiB total-result limit.
            sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 32 * 1024 * 1024)
            let version = try rows("PRAGMA user_version").first?.first
            let application = try rows("PRAGMA application_id").first?.first
            if version == "0", application == "0" {
                guard try rows("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").isEmpty else { throw CatalogStoreError.incompatible }
                try transaction {
                    try execute(Self.schema)
                    try execute("PRAGMA application_id=\(Self.applicationID); PRAGMA user_version=6")
                }
            } else if application != String(Self.applicationID) || !["1", "2", "3", "4", "5", "6"].contains(version ?? "") { throw CatalogStoreError.incompatible }
            if let version, ["1", "2", "3", "4"].contains(version) {
                try transaction {
                    guard try rows("PRAGMA user_version").first?.first == version else { throw CatalogStoreError.busy }
                    // Keep the writer reservation through backup and ALTER. A separate
                    // read-only connection can back up the unmodified committed state.
                    let backupURL = url.deletingLastPathComponent().appendingPathComponent("catalog-v\(version)-backup-" + UUID().uuidString + ".sqlite")
                    let target = try CatalogDatabase(backupURL)
                    var reader: OpaquePointer?
                    defer { if let reader { sqlite3_close(reader) } }
                    guard sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
                          let backup = sqlite3_backup_init(target.handle, "main", reader, "main") else { throw CatalogStoreError.unavailable }
                    let copied = sqlite3_backup_step(backup, -1); let finished = sqlite3_backup_finish(backup)
                    guard copied == SQLITE_DONE, finished == SQLITE_OK,
                          try target.rows("PRAGMA user_version").first?.first == version,
                          try target.rows("PRAGMA quick_check").first?.first == "ok" else { throw CatalogStoreError.unavailable }
                    if version == "1" {
                        try execute(Self.discoverySchema)
                        // Preserve only proven complete baselines. Incomplete scopes require a fresh inventory.
                        for row in try rows("SELECT configuration FROM scopes WHERE complete=1") {
                            guard let data = row[0].data(using: .utf8), let scope = try? JSONDecoder().decode(CatalogScope.self, from: data) else { throw CatalogStoreError.invalid }
                            for kind in ["plugin", "sample", "library"] {
                                for root in scope.roots(for: kind) {
                                    try run("INSERT OR IGNORE INTO root_baselines(kind,path,exclusions,complete) VALUES(?,?,?,1)", [kind, root, String(decoding: try JSONEncoder().encode(scope.exclusions(kind: kind, root: root)), as: UTF8.self)])
                                }
                            }
                        }
                    }
                    if version != "4" {
                        if version != "3" { try execute(Self.dateEvidenceSchema) }
                        try execute(Self.additionSchema)
                    }
                    try execute(Self.productSchema)
                    try migratePluginProducts()
                    try execute("PRAGMA user_version=5")
                }
            }
            if try rows("PRAGMA user_version").first?.first == "5" {
                try transaction {
                    guard try rows("PRAGMA user_version").first?.first == "5" else { throw CatalogStoreError.busy }
                    let backupURL = url.deletingLastPathComponent().appendingPathComponent("catalog-v5-backup-" + UUID().uuidString + ".sqlite")
                    let target = try CatalogDatabase(backupURL)
                    var reader: OpaquePointer?
                    defer { if let reader { sqlite3_close(reader) } }
                    guard sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
                          let backup = sqlite3_backup_init(target.handle, "main", reader, "main") else { throw CatalogStoreError.unavailable }
                    let copied = sqlite3_backup_step(backup, -1); let finished = sqlite3_backup_finish(backup)
                    guard copied == SQLITE_DONE, finished == SQLITE_OK,
                          try target.rows("PRAGMA user_version").first?.first == "5",
                          try target.rows("PRAGMA quick_check").first?.first == "ok" else { throw CatalogStoreError.unavailable }
                    try migrateUsageSubjects()
                    try execute("PRAGMA user_version=6")
                }
            }
            // These predicates run once per discovered asset during ingest. Both
            // indexes are also installed for existing v5 catalogs on first open.
            try execute(Self.lookupIndexes)
            try execute("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL")
        } catch {
            sqlite3_close(handle); handle = nil; throw error
        }
    }
    deinit { if let handle { sqlite3_close(handle) } }
    private func migratePluginProducts() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        var seen = Set<String>()
        var products: [String: String] = [:]
        var dates: [String: Date] = [:]
        for row in try rows("SELECT n.id,m.payload FROM nodes n JOIN scope_members m ON m.node_id=n.id WHERE n.kind='plugin' ORDER BY n.id,m.observed_at DESC") {
            guard seen.insert(row[0]).inserted else { continue }
            guard let asset = try? decoder.decode(Asset.self, from: Data(row[1].utf8)) else { throw CatalogStoreError.invalid }
            let identity = PluginProduct.verifiedIdentity(asset)
            let key = identity ?? "legacy-node:" + row[0]
            let id: String
            if let existing = products[key] { id = existing }
            else {
                id = UUID().uuidString
                products[key] = id
                try run("INSERT INTO plugin_products(id,identity_key,name,archived) VALUES(?,?,?,0)", [id, identity ?? "", asset.name])
            }
            try run("INSERT INTO plugin_installations(node_id,product_id) VALUES(?,?)", [row[0], id])
            if let added = asset.finderDateAdded, added.timeIntervalSince1970.isFinite {
                dates[id] = min(dates[id] ?? added, added)
            }
        }
        for (id, date) in dates { try run("UPDATE plugin_products SET earliest_date=? WHERE id=?", [String(date.timeIntervalSince1970), id]) }
        var merged: [String: [String: [String]]] = [:]
        for row in try rows("SELECT p.product_id,o.payload FROM metadata_overrides o JOIN plugin_installations p ON p.node_id=o.node_id ORDER BY o.subject") {
            let metadata = try decoder.decode(MusicalMetadata.self, from: Data(row[1].utf8)).validated()
            for (facet, values) in metadata.fields {
                merged[row[0], default: [:]][facet, default: []].append(contentsOf: values)
            }
        }
        for (id, facets) in merged {
            let metadata = try MusicalMetadata(fields: facets).validated()
            try run("UPDATE plugin_products SET metadata=? WHERE id=?", [String(decoding: try encoder.encode(metadata), as: UTF8.self), id])
        }
    }
    private func migrateUsageSubjects() throws {
        try execute("ALTER TABLE instruments ADD COLUMN usage_subject_id TEXT;")
        try execute(Self.dateSubjectsSchema)
        try run("INSERT INTO date_subjects(subject_id,parent_node_id,kind,identity_key) SELECT id,id,'asset','' FROM nodes")
        let decoder = JSONDecoder()
        for row in try rows("SELECT node_id,id,payload FROM instruments ORDER BY node_id,id") {
            guard row.count == 3, let instrument = try? decoder.decode(LibraryInstrument.self, from: Data(row[2].utf8)) else { throw CatalogStoreError.invalid }
            let key = AssetUsageSubject.instrumentIdentityKey(instrument)
            let subjectID = AssetUsageSubject.instrumentID(parentNodeID: row[0], identityKey: key)
            try run("INSERT INTO date_subjects(subject_id,parent_node_id,kind,identity_key) VALUES(?,?,'instrument',?) ON CONFLICT(parent_node_id,kind,identity_key) DO NOTHING", [subjectID, row[0], key])
            try run("UPDATE instruments SET usage_subject_id=? WHERE node_id=? AND id=?", [subjectID, row[0], row[1]])
        }
        try execute("ALTER TABLE date_evidence RENAME TO date_evidence_v5; DROP INDEX IF EXISTS date_evidence_subject;")
        try execute(Self.currentDateEvidenceSchema)
        try execute("INSERT INTO date_evidence(source_id,evidence_id,subject_id,payload) SELECT source_id,evidence_id,subject_id,payload FROM date_evidence_v5;")
        try execute("DROP TABLE date_evidence_v5;")
        guard try rows("PRAGMA foreign_key_check").isEmpty else { throw CatalogStoreError.invalid }
    }
    func transaction<T>(isolation: isolated (any Actor)? = #isolation, _ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try operation(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func readTransaction<T>(isolation: isolated (any Actor)? = #isolation, _ operation: () throws -> T) throws -> T {
        try execute("BEGIN")
        do { let result = try operation(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func execute(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw result == SQLITE_BUSY ? CatalogStoreError.busy : CatalogStoreError.invalid }
    }
    func run(_ sql: String, _ values: [String] = []) throws { _ = try rows(sql, values) }
    static let maximumDateTextBytes = 32 * 1024
    func dateRows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        try rows(sql, values, strictDateText: true)
    }
    func strictRows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        try rows(sql, values, strictDateText: true, strictRowLimit: 1_000_000)
    }
    func rows(_ sql: String, _ values: [String] = [], strictDateText: Bool = false, strictRowLimit: Int = AssetDateResolver.maximumRecords + 1) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            guard value.withCString({ sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }) == SQLITE_OK else { throw CatalogStoreError.invalid }
        }
        var result: [[String]] = []; var byteCount = 0; var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            byteCount += (0..<sqlite3_column_count(statement)).reduce(0) { $0 + Int(sqlite3_column_bytes(statement, $1)) }
            guard result.count < 1_000_000, byteCount <= 128 * 1024 * 1024 else { throw CatalogStoreError.invalid }
            if strictDateText {
                guard result.count < strictRowLimit else { throw AssetDateEvidenceError.tooManyRecords }
                result.append(try (0..<sqlite3_column_count(statement)).map { column in
                    let size = Int(sqlite3_column_bytes(statement, column))
                    guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                          size <= Self.maximumDateTextBytes,
                          let bytes = sqlite3_column_text(statement, column) else { throw CatalogStoreError.invalid }
                    let data = Data(bytes: bytes, count: size)
                    guard !data.contains(0), let value = String(data: data, encoding: .utf8) else { throw CatalogStoreError.invalid }
                    return value
                })
            } else { result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            }) }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw status == SQLITE_BUSY ? CatalogStoreError.busy : CatalogStoreError.invalid }
        return result
    }
    static let discoverySchema = """
    ALTER TABLE scope_members ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
    ALTER TABLE instruments ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
    ALTER TABLE physical_members ADD COLUMN observed_at REAL NOT NULL DEFAULT 0;
    UPDATE scope_members SET observed_at=COALESCE((SELECT saved_at FROM scopes WHERE id=scope_id AND generation=scope_members.generation),0);
    UPDATE instruments SET observed_at=COALESCE((SELECT saved_at FROM scopes WHERE id=scope_id AND generation=instruments.generation),0);
    UPDATE physical_members SET observed_at=COALESCE((SELECT saved_at FROM scopes WHERE id=scope_id AND generation=physical_members.generation),0);
    CREATE TABLE root_baselines(kind TEXT NOT NULL,path TEXT NOT NULL,exclusions TEXT NOT NULL,complete INTEGER NOT NULL,PRIMARY KEY(kind,path,exclusions));
    CREATE TABLE metadata_overrides(subject TEXT PRIMARY KEY,node_id TEXT NOT NULL,payload TEXT NOT NULL,FOREIGN KEY(node_id) REFERENCES nodes(id));
    CREATE INDEX metadata_node ON metadata_overrides(node_id);
    """
    static let dateEvidenceSchema = """
    CREATE TABLE date_evidence(source_id TEXT COLLATE BINARY NOT NULL,evidence_id TEXT COLLATE BINARY NOT NULL,
      subject_id TEXT COLLATE BINARY NOT NULL,payload TEXT NOT NULL,
      PRIMARY KEY(source_id,evidence_id),FOREIGN KEY(subject_id) REFERENCES nodes(id));
    CREATE INDEX date_evidence_subject ON date_evidence(subject_id);
    """
    static let dateSubjectsSchema = """
    CREATE TABLE date_subjects(subject_id TEXT PRIMARY KEY,parent_node_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('asset','instrument')),
      identity_key TEXT NOT NULL,UNIQUE(parent_node_id,kind,identity_key),
      FOREIGN KEY(parent_node_id) REFERENCES nodes(id));
    CREATE INDEX date_subjects_parent ON date_subjects(parent_node_id,kind);
    """
    static let currentDateEvidenceSchema = """
    CREATE TABLE date_evidence(source_id TEXT COLLATE BINARY NOT NULL,evidence_id TEXT COLLATE BINARY NOT NULL,
      subject_id TEXT COLLATE BINARY NOT NULL,payload TEXT NOT NULL,
      PRIMARY KEY(source_id,evidence_id),FOREIGN KEY(subject_id) REFERENCES date_subjects(subject_id));
    CREATE INDEX date_evidence_subject ON date_evidence(subject_id);
    """
    static let additionSchema = """
    CREATE TABLE scan_coverage(kind TEXT NOT NULL,root TEXT NOT NULL,exclusions TEXT NOT NULL,policy TEXT NOT NULL,root_identity TEXT NOT NULL,started REAL NOT NULL,finished REAL NOT NULL,PRIMARY KEY(kind,root,exclusions));
    CREATE TABLE node_addition_bounds(node_id TEXT PRIMARY KEY,payload TEXT NOT NULL,FOREIGN KEY(node_id) REFERENCES nodes(id));
    """
    static let productSchema = """
    CREATE TABLE plugin_products(id TEXT PRIMARY KEY,identity_key TEXT NOT NULL,name TEXT NOT NULL,metadata TEXT,earliest_date REAL,archived INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE plugin_installations(node_id TEXT PRIMARY KEY,product_id TEXT NOT NULL REFERENCES plugin_products(id),FOREIGN KEY(node_id) REFERENCES nodes(id));
    CREATE INDEX plugin_products_identity ON plugin_products(identity_key);
    CREATE INDEX plugin_installations_product ON plugin_installations(product_id);
    """
    static let lookupIndexes = """
    CREATE INDEX IF NOT EXISTS nodes_kind_path ON nodes(kind,path);
    CREATE INDEX IF NOT EXISTS nodes_product_kind ON nodes(product_key,kind);
    CREATE INDEX IF NOT EXISTS members_scope_path ON scope_members(scope_id,path);
    CREATE INDEX IF NOT EXISTS instruments_usage_subject ON instruments(scope_id,node_id,usage_subject_id);
    """
    static let schema = """
    CREATE TABLE nodes(id TEXT PRIMARY KEY,identity TEXT UNIQUE NOT NULL,product_key TEXT NOT NULL,
      kind TEXT NOT NULL,path TEXT NOT NULL,first_seen REAL NOT NULL,last_seen REAL NOT NULL,baseline INTEGER NOT NULL);
    CREATE TABLE instruments(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,id TEXT NOT NULL,usage_subject_id TEXT,payload TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE physical_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,instrument_id TEXT NOT NULL,path TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,instrument_id,path), FOREIGN KEY(scope_id,node_id,instrument_id) REFERENCES instruments(scope_id,node_id,id));
    CREATE TABLE scopes(id TEXT PRIMARY KEY,configuration TEXT NOT NULL,evidence TEXT NOT NULL,saved_at REAL NOT NULL,generation TEXT NOT NULL,complete INTEGER NOT NULL);
    CREATE TABLE scope_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,path TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,baseline INTEGER NOT NULL,PRIMARY KEY(scope_id,node_id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE removals(path TEXT PRIMARY KEY);
    CREATE INDEX instruments_parent ON instruments(node_id);
    CREATE INDEX members_scope ON scope_members(scope_id);
    """ + discoverySchema + dateSubjectsSchema + currentDateEvidenceSchema + additionSchema + productSchema + lookupIndexes
}
