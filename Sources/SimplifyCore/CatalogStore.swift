import Foundation
import CSQLite
import CryptoKit
import Darwin

/// Exact configured scope. Adding/removing roots starts a separate baseline.
public struct CatalogScope: Codable, Sendable {
    public let roots: [String: [String]]
    public init(_ request: ScanRequest) {
        roots = ["plugins": request.plugins, "samples": request.samples,
                 "libraries": request.libraries, "projects": request.projects]
            .mapValues { Array(Set($0.map { $0.standardizedFileURL.path })).sorted() }
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
}
public struct CatalogSnapshot: Sendable {
    public let report: ScanReport
    public let savedAt: Date
    public let observations: [String: CatalogObservation]
}

public enum CatalogStoreError: LocalizedError {
    case unavailable, incompatible, invalid, busy
    public var errorDescription: String? {
        switch self {
        case .unavailable: "The saved catalog is unavailable. Current scan results can still be used."
        case .incompatible: "The saved catalog belongs to an unsupported version and has been left unchanged."
        case .invalid: "The saved catalog could not be read and has been left unchanged."
        case .busy: "The saved catalog is busy. Current scan results can still be used."
        }
    }
}

/// Local inventory graph. All SQLite work is serialized by this actor, off the UI actor.
/// Only final scans are ingested. Missing observations are retained and labeled stale.
public actor CatalogStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var application: CatalogStore {
        CatalogStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Simplify/catalog.sqlite"))
    }

    public func load(scope: CatalogScope) throws -> CatalogSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let db = try CatalogDatabase(url)
        return try read(db, scope: scope)
    }

    /// Writes inventory, graph memberships and observations in a single transaction.
    /// The returned projection strips removal identities; callers keep fresh identities
    /// only for items independently observed by their current scan.
    public func ingest(_ report: ScanReport, scope: CatalogScope, at date: Date = Date()) throws -> CatalogSnapshot {
        let db = try CatalogDatabase(url)
        try db.execute("BEGIN IMMEDIATE")
        do {
            let previous = try db.rows("SELECT complete FROM scopes WHERE id=?", [scope.key]).first
            let baseline = previous?.first != "1"
            let generation = UUID().uuidString
            var identities = PhysicalKeys()
            for asset in report.assets {
                let product = asset.libraryMetadata?.identity?.productID ?? ""
                let identity = asset.kind.rawValue + ":" + asset.format + ":" + product + ":" + identities.key(asset.path)
                let existing = try db.rows("SELECT id FROM nodes WHERE identity=?", [identity]).first?.first
                let id = existing ?? UUID().uuidString
                var header = asset; header.catalogID = id; header.fileIdentity = nil
                let instruments = header.libraryMetadata?.instruments ?? []
                header.libraryMetadata?.instruments = []
                try db.run("""
                    INSERT INTO nodes(id,identity,product_key,kind,path,first_seen,last_seen,baseline)
                    VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
                    path=excluded.path,last_seen=excluded.last_seen
                    """, [id, identity, product, asset.kind.rawValue, asset.path, stamp(date), stamp(date), baseline ? "1" : "0"])
                // Retain unobserved children; a bounded adapter cannot prove their absence.
                for instrument in instruments {
                    let key = instrument.vendorID ?? identities.key(instrument.path)
                    try db.run("""
                        INSERT INTO instruments(scope_id,node_id,id,payload,generation) VALUES(?,?,?,?,?)
                        ON CONFLICT(scope_id,node_id,id) DO UPDATE SET payload=excluded.payload,generation=excluded.generation
                        """, [scope.key, id, key, try encode(instrument), generation])
                    for path in instrument.contentPaths ?? [] {
                        try db.run("INSERT INTO physical_members(scope_id,node_id,instrument_id,path,generation) VALUES(?,?,?,?,?) ON CONFLICT(scope_id,node_id,instrument_id,path) DO UPDATE SET generation=excluded.generation", [scope.key, id, key, path, generation])
                    }
                }
                try db.run("DELETE FROM scope_members WHERE scope_id=? AND path=? AND node_id!=? AND node_id IN (SELECT id FROM nodes WHERE product_key=? AND kind=?)", [scope.key, asset.path, id, product, asset.kind.rawValue])
                try db.run("INSERT INTO scope_members(scope_id,node_id,path,payload,generation,baseline) VALUES(?,?,?,?,?,?) ON CONFLICT(scope_id,node_id) DO UPDATE SET path=excluded.path,payload=excluded.payload,generation=excluded.generation", [scope.key, id, asset.path, try encode(header), generation, baseline ? "1" : "0"])
                if asset.kind == .plugin { try db.run("DELETE FROM removals WHERE path=?", [asset.path]) }
            }
            let evidence = ScanReport(schemaVersion: report.schemaVersion, assets: [], projects: report.projects,
                sampleInclusions: report.sampleInclusions, issues: report.issues, durationSeconds: report.durationSeconds)
            try db.run("""
                INSERT INTO scopes(id,configuration,evidence,saved_at,generation,complete) VALUES(?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET evidence=excluded.evidence,saved_at=excluded.saved_at,
                generation=excluded.generation,complete=MAX(scopes.complete,excluded.complete)
                """, [scope.key, try encode(scope), try encode(evidence), stamp(date), generation, report.issues.isEmpty ? "1" : "0"])
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
        guard let snapshot = try read(db, scope: scope) else { throw CatalogStoreError.invalid }
        return snapshot
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
                SELECT n.id,m.payload,n.first_seen,n.last_seen,m.baseline,m.generation FROM nodes n
                JOIN scope_members m ON m.node_id=n.id WHERE m.scope_id=?
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
            var children: [String: [LibraryInstrument]] = [:]
            for row in childRows {
                var child = try decode(LibraryInstrument.self, row[1])
                child.catalogStale = row[2] != generation
                if let known = members[row[0]]?[row[3]] {
                    child.contentMembers = known; child.contentPaths = known.map(\.path)
                }
                children[row[0], default: []].append(child)
            }
            var assets: [Asset] = []; var observations: [String: CatalogObservation] = [:]
            for row in rows {
                var asset = try decode(Asset.self, row[1]); asset.fileIdentity = nil
                asset.libraryMetadata?.instruments = children[row[0]] ?? []
                guard let first = Double(row[2]), let last = Double(row[3]) else { throw CatalogStoreError.invalid }
                let stale = row[5] != generation
                asset.catalogStale = stale
                assets.append(asset)
                observations[row[0]] = CatalogObservation(id: row[0], firstSeen: Date(timeIntervalSince1970: first),
                    lastSeen: Date(timeIntervalSince1970: last), baseline: row[4] == "1", stale: stale)
            }
            let report = ScanReport(schemaVersion: evidence.schemaVersion, assets: assets, projects: evidence.projects,
                sampleInclusions: evidence.sampleInclusions, issues: evidence.issues, durationSeconds: evidence.durationSeconds)
            try db.execute("COMMIT")
            return CatalogSnapshot(report: report, savedAt: Date(timeIntervalSince1970: time), observations: observations)
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    private nonisolated func stamp(_ date: Date) -> String { String(date.timeIntervalSince1970) }
    private nonisolated func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private nonisolated func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(text.utf8)) }
        catch { throw CatalogStoreError.invalid }
    }
}

private struct PhysicalKeys {
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
            sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 16 * 1024 * 1024)
            let version = try rows("PRAGMA user_version").first?.first
            let application = try rows("PRAGMA application_id").first?.first
            if version == "0", application == "0" {
                guard try rows("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").isEmpty else { throw CatalogStoreError.incompatible }
                try transaction {
                    try execute(Self.schema)
                    try execute("PRAGMA application_id=\(Self.applicationID); PRAGMA user_version=1")
                }
            } else if version != "1" || application != String(Self.applicationID) { throw CatalogStoreError.incompatible }
            try execute("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL")
        } catch {
            sqlite3_close(handle); handle = nil; throw error
        }
    }
    deinit { if let handle { sqlite3_close(handle) } }
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
    func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
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
            result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw status == SQLITE_BUSY ? CatalogStoreError.busy : CatalogStoreError.invalid }
        return result
    }
    static let schema = """
    CREATE TABLE nodes(id TEXT PRIMARY KEY,identity TEXT UNIQUE NOT NULL,product_key TEXT NOT NULL,
      kind TEXT NOT NULL,path TEXT NOT NULL,first_seen REAL NOT NULL,last_seen REAL NOT NULL,baseline INTEGER NOT NULL);
    CREATE TABLE instruments(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE physical_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,instrument_id TEXT NOT NULL,path TEXT NOT NULL,generation TEXT NOT NULL,PRIMARY KEY(scope_id,node_id,instrument_id,path), FOREIGN KEY(scope_id,node_id,instrument_id) REFERENCES instruments(scope_id,node_id,id));
    CREATE TABLE scopes(id TEXT PRIMARY KEY,configuration TEXT NOT NULL,evidence TEXT NOT NULL,saved_at REAL NOT NULL,generation TEXT NOT NULL,complete INTEGER NOT NULL);
    CREATE TABLE scope_members(scope_id TEXT NOT NULL,node_id TEXT NOT NULL,path TEXT NOT NULL,payload TEXT NOT NULL,generation TEXT NOT NULL,baseline INTEGER NOT NULL,PRIMARY KEY(scope_id,node_id), FOREIGN KEY(node_id) REFERENCES nodes(id), FOREIGN KEY(scope_id) REFERENCES scopes(id) DEFERRABLE INITIALLY DEFERRED);
    CREATE TABLE removals(path TEXT PRIMARY KEY);
    CREATE INDEX instruments_parent ON instruments(node_id);
    CREATE INDEX members_scope ON scope_members(scope_id);
    """
}
