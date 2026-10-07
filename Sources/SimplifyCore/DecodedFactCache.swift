import Foundation
import CSQLite
import CryptoKit
import Darwin

/// Disposable decoded facts for one worker-confined scan. A hit never proves that
/// a source exists for catalog ownership or removal; callers still traverse and
/// qualify current physical content. SQLite errors simply turn caching off.
final class DecodedFactCache {
    enum Result<T> { case value(T), unavailable, unstable }
    private struct Observation: Codable, Equatable {
        let path: String
        let stamp: LibraryScanJournal.Stamp?
        let absent: Bool
    }
    private let db: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var insertedSincePrune = 0
    private(set) var hitsByPolicy: [String: Int] = [:]
    private(set) var readsByPolicy: [String: Int] = [:]
    private static let rowLimit = 20_000
    private static let byteLimit = 1_000_000
    private static let databaseLimit = 128 * 1_024 * 1_024
    private static let version = "decoded-facts-v1"

    static func location(baseURL: URL) -> URL {
        baseURL.deletingLastPathComponent().appendingPathComponent("decoded-facts.sqlite")
    }

    init?(baseURL: URL) {
        let url = Self.location(baseURL: baseURL)
        guard (try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil,
            LibraryMetadataReader.safe(url.deletingLastPathComponent()) else { return nil }
        if FileManager.default.fileExists(atPath: url.path) {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_nlink == 1, info.st_size <= Self.databaseLimit,
                  LibraryMetadataReader.safe(url) else { return nil }
        } else {
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { return nil }
            close(fd)
        }
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
            let opened else { if let opened { sqlite3_close(opened) }; return nil }
        db = opened
        sqlite3_busy_timeout(db, 100)
        guard sqlite3_exec(db, "PRAGMA page_size=4096", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        var pageStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA page_size", -1, &pageStatement, nil) == SQLITE_OK,
              let pageStatement, sqlite3_step(pageStatement) == SQLITE_ROW else {
            if let pageStatement { sqlite3_finalize(pageStatement) }
            sqlite3_close(db); return nil
        }
        let pageSize = Int(sqlite3_column_int(pageStatement, 0))
        sqlite3_finalize(pageStatement)
        guard pageSize > 0,
              sqlite3_exec(db, "PRAGMA max_page_count=\(Self.databaseLimit / pageSize)", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS facts(key TEXT PRIMARY KEY, signature TEXT NOT NULL, payload BLOB NOT NULL, accessed INTEGER NOT NULL)", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        encoder.outputFormatting = .sortedKeys
    }
    deinit { sqlite3_close(db) }

    private func observe(_ paths: [URL]) -> [Observation]? {
        var result: [Observation] = []
        for path in paths {
            let name = path.standardizedFileURL.path
            if let stamp = LibraryScanJournal.stamp(name) {
                guard LibraryMetadataReader.safe(path) else { return nil }
                result.append(Observation(path: name, stamp: stamp, absent: false))
            } else {
                var info = stat()
                guard lstat(name, &info) != 0, errno == ENOENT else { return nil }
                // ENOENT below an inaccessible or missing ancestor is not an
                // observation of an optional sidecar's absence.
                var parent = path.deletingLastPathComponent()
                while !FileManager.default.fileExists(atPath: parent.path) {
                    let next = parent.deletingLastPathComponent()
                    guard next.path != parent.path else { return nil }
                    parent = next
                }
                guard LibraryMetadataReader.safe(parent),
                      access(parent.path, R_OK | X_OK) == 0 else { return nil }
                result.append(Observation(path: name, stamp: nil, absent: true))
            }
        }
        return result
    }

    /// Reuses only successful decoded values with identical current dependency
    /// observations. Failed reads, cancellation, and changed-during-read results
    /// are never stored. `paths` includes explicitly absent optional sidecars.
    func value<T: Codable>(policy: String, paths: [URL], read: () -> T?) -> T? {
        if case .value(let result) = checkedValue(policy: policy, paths: paths, read: read) { return result }
        return nil
    }

    func checkedValue<T: Codable>(policy: String, paths: [URL], read: () -> T?) -> Result<T> {
        guard !Task<Never, Never>.isCancelled else { return .unstable }
        let before = observe(paths)
        let key = Self.digest(Self.version + ":" + policy + ":" + paths.map { $0.standardizedFileURL.path }.joined(separator: "\u{0}"))
        if let before, let signature = try? encoder.encode(before),
           let cached: T = load(key: key, signature: signature),
           !Task<Never, Never>.isCancelled, observe(paths) == before {
            hitsByPolicy[policy, default: 0] += 1
            return .value(cached)
        }
        readsByPolicy[policy, default: 0] += 1
        let decoded = read()
        guard !Task<Never, Never>.isCancelled else { return .unstable }
        guard let before else { return decoded.map(Result.value) ?? .unavailable }
        guard observe(paths) == before else { return .unstable }
        guard let decoded else { return .unavailable }
        guard let signature = try? encoder.encode(before),
              let payload = try? encoder.encode(decoded), payload.count <= Self.byteLimit else { return .value(decoded) }
        save(key: key, signature: signature, payload: payload)
        return .value(decoded)
    }

    private func load<T: Decodable>(key: String, signature: Data) -> T? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT signature,payload FROM facts WHERE key=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let signatureText = sqlite3_column_text(statement, 0),
              Data(String(cString: signatureText).utf8) == signature,
              let bytes = sqlite3_column_blob(statement, 1),
              (1...Self.byteLimit).contains(Int(sqlite3_column_bytes(statement, 1))) else { return nil }
        return try? decoder.decode(T.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1))))
    }

    private func save(key: String, signature: Data, payload: Data) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO facts(key,signature,payload,accessed) VALUES(?,?,?,strftime('%s','now'))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, String(decoding: signature, as: UTF8.self), -1, transient)
        payload.withUnsafeBytes { bytes in _ = sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        insertedSincePrune += 1
        if insertedSincePrune >= 32 {
            insertedSincePrune = 0
            sqlite3_exec(db, "DELETE FROM facts WHERE key IN (SELECT key FROM facts ORDER BY accessed DESC, rowid DESC LIMIT -1 OFFSET \(Self.rowLimit))", nil, nil, nil)
        }
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
