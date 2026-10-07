import Foundation
import CSQLite
import CryptoKit
import Darwin

/// Private, disposable discovery work. A committed batch includes both its replay
/// records and the frontier after each directory; catalog generations stay untouched.
final class LibraryScanJournal {
    struct Pending: Codable {
        let path: String
        let depth: Int
        let inherited: String?
    }
    struct Stamp: Codable, Equatable {
        let path: String
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }
    struct Record: Codable {
        let directory: String
        let stamps: [Stamp]
        let assets: [Asset]
        let instruments: [String: [LibraryInstrument]]
        let manifests: [String: KontaktManifestDetails]
        let issues: [ScanIssue]
    }
    private struct Identity: Codable {
        let version: String
        let scope: String
        let root: Stamp?
        let source: Stamp?
        let sourceWAL: Stamp?
    }

    private let handle: OpaquePointer
    private let url: URL
    private var buffered: [Record] = []
    private var nextFrontier: [Pending] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    // Bump whenever derived patch membership or physical clustering changes. Old
    // records may otherwise replay assertions removed from the current adapters.
    private static let version = "library-directory-v6-qualified-profile-and-clusters"

    static func signature(_ stamp: Stamp) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try! encoder.encode(stamp)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func stamp(_ path: String) -> Stamp? {
        var value = stat()
        guard lstat(path, &value) == 0, value.st_mode & S_IFMT != S_IFLNK else { return nil }
        return Stamp(path: path, device: UInt64(value.st_dev), inode: UInt64(value.st_ino),
                     size: value.st_size, modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
                     modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                     changedSeconds: Int64(value.st_ctimespec.tv_sec),
                     changedNanoseconds: Int64(value.st_ctimespec.tv_nsec))
    }

    static func location(baseURL: URL, scope: CatalogScope, root: URL) -> URL {
        let key = scope.key + ":" + root.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return baseURL.deletingLastPathComponent().appendingPathComponent("library-discovery-" + digest + ".sqlite")
    }

    init(baseURL: URL, scope: CatalogScope, root: URL, source: URL) throws {
        url = Self.location(baseURL: baseURL, scope: scope, root: root)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard LibraryMetadataReader.safe(parent) else { throw CatalogStoreError.unavailable }
        if FileManager.default.fileExists(atPath: url.path) {
            var existing = stat()
            guard lstat(url.path, &existing) == 0, existing.st_mode & S_IFMT == S_IFREG,
                  existing.st_nlink == 1, LibraryMetadataReader.safe(url) else { throw CatalogStoreError.unavailable }
        } else {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CatalogStoreError.unavailable }
            close(descriptor)
        }
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
              let opened else { if let opened { sqlite3_close(opened) }; throw CatalogStoreError.unavailable }
        handle = opened
        sqlite3_busy_timeout(handle, 250)
        do {
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS identity(value TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS records(sequence INTEGER PRIMARY KEY,payload BLOB NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS frontier(payload BLOB NOT NULL)")
            encoder.outputFormatting = .sortedKeys
            let identity = String(decoding: try encoder.encode(Identity(
                version: Self.version, scope: scope.key,
                root: Self.stamp(root.standardizedFileURL.path),
                source: Self.stamp(source.standardizedFileURL.path),
                sourceWAL: Self.stamp(source.standardizedFileURL.path + "-wal"))), as: UTF8.self)
            let previous = try readIdentity()
            if previous != identity {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("DELETE FROM records")
                    try execute("DELETE FROM frontier")
                    try execute("DELETE FROM identity")
                    try insert("INSERT INTO identity(value) VALUES(?)", Data(identity.utf8))
                    try execute("COMMIT")
                } catch { try? execute("ROLLBACK"); throw error }
            }
        } catch { sqlite3_close(handle); throw error }
    }
    deinit { sqlite3_close(handle) }

    /// Replay only if every completed directory and metadata candidate still has
    /// the same filesystem identity. Any mismatch discards the whole journal.
    func replay(_ consume: (Record) -> Void) throws -> [Pending]? {
        var sequence = 0
        while true {
            let rows = try readRecords(after: sequence, limit: 128)
            if rows.isEmpty { break }
            for (number, record) in rows {
                guard record.stamps.allSatisfy({ Self.stamp($0.path) == $0 }) else {
                    try clear(); return nil
                }
                sequence = number
            }
        }
        guard sequence > 0 else { return nil }
        var replayed = 0
        while true {
            let rows = try readRecords(after: replayed, limit: 128)
            if rows.isEmpty { return try readFrontier() }
            for (number, record) in rows {
                guard record.stamps.allSatisfy({ Self.stamp($0.path) == $0 }) else {
                    try clear(); throw CatalogStoreError.invalid
                }
                consume(record); replayed = number
            }
        }
    }

    func validateCompleted() throws -> Bool {
        var sequence = 0
        while true {
            let rows = try readRecords(after: sequence, limit: 128)
            if rows.isEmpty {
                guard sequence > 0 else { return false }
                return try readFrontier().isEmpty
            }
            for (number, record) in rows {
                guard record.stamps.allSatisfy({ Self.stamp($0.path) == $0 }) else { return false }
                sequence = number
            }
        }
    }

    func append(_ record: Record, frontier: [Pending]) throws {
        buffered.append(record)
        nextFrontier = frontier
        if buffered.count >= 128 { try flush() }
    }
    func flush() throws {
        guard !buffered.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for record in buffered {
                try insert("INSERT INTO records(payload) VALUES(?)", try encoder.encode(record))
            }
            try execute("DELETE FROM frontier")
            try insert("INSERT INTO frontier(payload) VALUES(?)", try encoder.encode(nextFrontier))
            try execute("COMMIT")
            buffered.removeAll(keepingCapacity: true)
            nextFrontier = []
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func discardUncommitted() { buffered.removeAll(); nextFrontier = [] }
    func clear() throws {
        buffered.removeAll()
        try execute("DELETE FROM records")
        try execute("DELETE FROM frontier")
    }
    static func clearAll(baseURL: URL) {
        let parent = baseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: DecodedFactCache.location(baseURL: baseURL))
        for url in (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix("library-discovery-") && url.pathExtension == "sqlite" {
            try? FileManager.default.removeItem(at: url)
        }
    }
    static func discard(baseURL: URL, scope: CatalogScope, root: URL) {
        let url = location(baseURL: baseURL, scope: scope, root: root)
        try? FileManager.default.removeItem(at: url)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
    }
    private func insert(_ sql: String, _ data: Data) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), transient)
        }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw CatalogStoreError.invalid }
    }
    private func readIdentity() throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM identity LIMIT 1", -1, &statement, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw CatalogStoreError.invalid }
        return String(cString: text)
    }
    private func readFrontier() throws -> [Pending] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM frontier LIMIT 1", -1, &statement, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { throw CatalogStoreError.invalid }
        return try decoder.decode([Pending].self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }
    private func readRecords(after sequence: Int, limit: Int) throws -> [(Int, Record)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT sequence,payload FROM records WHERE sequence>? ORDER BY sequence LIMIT ?", -1, &statement, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(sequence)); sqlite3_bind_int(statement, 2, Int32(limit))
        var output: [(Int, Record)] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 1) else { throw CatalogStoreError.invalid }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            output.append((Int(sqlite3_column_int64(statement, 0)), try decoder.decode(Record.self, from: data)))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CatalogStoreError.invalid }
        return output
    }
}
