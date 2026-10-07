import Foundation
import CSQLite
import Darwin

/// Read-only identity adapter for the observed Live database schema 1, macOS platform 2.
/// Cache identity is corroborated against current bundle/executable stamps; it establishes
/// current class membership, never historical physical installation continuity.
public enum LivePluginCache {
    struct Entry: Sendable {
        let classID: String, path: String, version: String, fingerprint: String
    }
    public struct Binding: Sendable {
        public let classID: String
        public let path: String
        let snapshot: PackageReceiptReader.BundleInfo
        func revalidate() throws {
            let current = try PackageReceiptReader.readBundle(URL(fileURLWithPath: path))
            guard current.stamps == snapshot.stamps, current.key == snapshot.key else { throw PackageReceiptError.changedDuringRead }
        }
    }
    static func read(_ url: URL, deadline: Double = .infinity) throws -> [Entry] {
        guard LibraryMetadataReader.safe(url) else { throw CatalogStoreError.invalid }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }; throw CatalogStoreError.unavailable
        }
        defer { sqlite3_close(db) }
        final class ReadDeadline { let limit: Double; init(_ limit: Double) { self.limit = limit } }
        let clock = ReadDeadline(deadline)
        sqlite3_progress_handler(db, 1000, { context in
            guard let context else { return 1 }
            let clock = Unmanaged<ReadDeadline>.fromOpaque(context).takeUnretainedValue()
            return ProcessInfo.processInfo.systemUptime >= clock.limit || Task.isCancelled ? 1 : 0
        }, Unmanaged.passUnretained(clock).toOpaque())
        defer { sqlite3_progress_handler(db, 0, nil, nil); withExtendedLifetime(clock) {} }
        sqlite3_busy_timeout(db, 250)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.unavailable }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var totalBytes = 0
        func query(_ sql: String, limit: Int) throws -> [[String]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CatalogStoreError.invalid }
            defer { sqlite3_finalize(statement) }
            var rows: [[String]] = []
            while true {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogStoreError.busy }
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { return rows }
                guard step == SQLITE_ROW, rows.count < limit else { throw CatalogStoreError.invalid }
                var row: [String] = []
                for column in 0..<sqlite3_column_count(statement) {
                    guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                          let pointer = sqlite3_column_text(statement, column) else { throw CatalogStoreError.invalid }
                    let count = Int(sqlite3_column_bytes(statement, column)); totalBytes += count
                    guard count <= 4096, totalBytes <= 8 * 1024 * 1024 else { throw CatalogStoreError.invalid }
                    let bytes = Data(bytes: pointer, count: count)
                    guard !bytes.contains(0), let text = String(data: bytes, encoding: .utf8) else { throw CatalogStoreError.invalid }
                    row.append(text)
                }
                rows.append(row)
            }
        }
        guard try query("SELECT CAST(version AS TEXT),CAST(platform AS TEXT) FROM version", limit: 1) == [["1", "2"]] else {
            throw CatalogStoreError.incompatible
        }
        let rows = try query("""
            SELECT p.dev_identifier,m.path,p.version,m.fingerprint,CAST(p.enabled AS TEXT),CAST(p.scanstate AS TEXT),CAST(m.scanstate AS TEXT)
            FROM plugins p JOIN plugin_modules m ON p.module_id=m.module_id WHERE p.dev_identifier LIKE 'device:vst3:%' LIMIT 10001
            """, limit: 10000)
        return try rows.compactMap { row in
            guard row.count == 7 else { throw CatalogStoreError.invalid }
            func state(_ text: String) -> Int? {
                guard !text.isEmpty, text.utf8.count <= 10,
                      text.utf8.allSatisfy({ (48...57).contains($0) }),
                      let value = Int(text), value >= 0 else { return nil }
                return value
            }
            guard let enabled = state(row[4]), let pluginScan = state(row[5]),
                  let moduleScan = state(row[6]) else { throw CatalogStoreError.invalid }
            // Live's cache has per-row scan states beyond Boolean values (the current
            // schema includes module state 3). Only state 1 is a completed, enabled
            // binding; other valid states do not invalidate independent usable rows.
            guard enabled == 1, pluginScan == 1, moduleScan == 1 else { return nil }
            let parts = row[0].split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "device", parts[1] == "vst3", ["instr", "audiofx"].contains(parts[2]),
                  parts[3].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 45 }),
                  HostUsageProvenance.validClassID(String(parts[3]).uppercased()), row[1].hasPrefix("/"), row[1].hasSuffix(".vst3"),
                  !row[2].isEmpty, !row[3].isEmpty else { throw CatalogStoreError.invalid }
            return Entry(classID: String(parts[3]).uppercased(), path: row[1], version: row[2], fingerprint: row[3])
        }
    }
    static func bindings(_ entries: [Entry], assets: [Asset], deadline: Double = .infinity) throws -> [Binding] {
        let grouped = Dictionary(grouping: entries, by: { Data($0.classID.utf8) })
        let paths = Set(assets.filter { $0.kind == .plugin && $0.format == "vst3" && $0.catalogStale != true && $0.catalogID != nil }.map { Data($0.path.utf8) })
        var output: [Binding] = []
        for items in grouped.values where items.count == 1 {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogStoreError.busy }
            let item = items[0]
            guard paths.contains(Data(item.path.utf8)), let info = try? PackageReceiptReader.readBundle(URL(fileURLWithPath: item.path)) else { continue }
            let executable = info.stamps[2]
            let fingerprint = String(executable.size, radix: 16) + ":" + String(executable.times[2], radix: 16)
            guard fingerprint.utf8.elementsEqual(item.fingerprint.utf8) else { continue }
            output.append(Binding(classID: item.classID, path: item.path, snapshot: info))
        }
        return output
    }
}

public struct LiveUsageCollection: Sendable {
    public let recorded: Int
    public let failures: Int
    public let rejectedDocuments: Int
    public init(recorded: Int, failures: Int, rejectedDocuments: Int) {
        self.recorded = recorded; self.failures = failures; self.rejectedDocuments = rejectedDocuments
    }
}

/// Local positive-use collection only. Does not launch hosts or execute plugin code.
/// All work is bounded and off the caller actor; cancellation propagates to store writes.
public enum LiveUsageCollector {
    /// Only VST3 product history is qualified by this adapter. Unrelated samples,
    /// libraries and plugin formats must not consume its bounded identity budget.
    public static func eligibleAssets(_ assets: [Asset]) -> [Asset] {
        assets.filter { $0.kind == .plugin && $0.format == "vst3" }
    }
    /// Lightweight source identity for prospective polling, off the main actor.
    /// Inventory changes and WAL changes invalidate replay skips as well as log changes.
    public static func sourceSignature(assets: [Asset]) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = ["Library/Preferences/Ableton/Live 12.4.5/Log.txt", "Library/Preferences/Ableton/Live 12.4.6/Log.txt",
            "Library/Application Support/Ableton/Live Database/Live-plugins-1.db", "Library/Application Support/Ableton/Live Database/Live-plugins-1.db-wal"]
        var parts = eligibleAssets(assets).map { ($0.catalogID ?? "") + ":" + $0.path + ":" + String($0.catalogStale ?? false) }.sorted()
        for path in files {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: home.appendingPathComponent(path).path) {
                parts.append([FileAttributeKey.systemFileNumber, .size, .modificationDate].map { String(describing: attributes[$0]) }.joined(separator: ":"))
            } else { parts.append("missing:" + path) }
        }
        return HostUsageProvenance.digest((try? JSONEncoder().encode(parts)) ?? Data())
    }
    public static func collect(assets: [Asset], store: CatalogStore) async -> LiveUsageCollection {
        let worker = Task.detached(priority: .utility) { await run(assets: assets, store: store) }
        return await withTaskCancellationHandler(operation: {
            if Task.isCancelled { worker.cancel() }; return await worker.value
        }, onCancel: { worker.cancel() })
    }
    private static func run(assets: [Asset], store: CatalogStore) async -> LiveUsageCollection {
        let assets = eligibleAssets(assets)
        var recorded = 0, failures = 0, rejected = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        func check() throws {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogStoreError.busy }
        }
        do {
            try check()
            guard !assets.isEmpty else { return LiveUsageCollection(recorded: 0, failures: 0, rejectedDocuments: 0) }
            guard assets.count <= 2048 else { throw AssetDateEvidenceError.tooManyRecords }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let cache = home.appendingPathComponent("Library/Application Support/Ableton/Live Database/Live-plugins-1.db")
            let bindings = try LivePluginCache.bindings(LivePluginCache.read(cache, deadline: deadline), assets: assets, deadline: deadline)
            let expected = Set(assets.filter { $0.kind == .plugin && $0.format == "vst3" && $0.catalogStale != true && $0.catalogID != nil }.map { Data($0.path.utf8) })
            failures += expected.subtracting(Set(bindings.map { Data($0.path.utf8) })).count
            guard !bindings.isEmpty else { return LiveUsageCollection(recorded: 0, failures: failures, rejectedDocuments: 0) }
            let base = home.appendingPathComponent("Library/Preferences/Ableton")
            let directories = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
                .filter { ["Live 12.4.5", "Live 12.4.6"].contains($0.lastPathComponent) }
            guard directories.count <= 16 else { throw CatalogStoreError.invalid }
            var bytes = 0, eventCount = 0
            for directory in directories.sorted(by: { $0.path < $1.path }) {
                try check()
                do {
                    let url = directory.appendingPathComponent("Log.txt")
                    guard LibraryMetadataReader.safe(url) else { throw CatalogStoreError.invalid }
                    let data = try BoundedFile.read(url, limit: LiveUsageLog.maximumBytes)
                    bytes += data.count; guard bytes <= 64 * 1024 * 1024 else { throw CatalogStoreError.invalid }
                    let result = try LiveUsageLog.parse(data, deadline: deadline); rejected += result.rejectedDocuments
                    eventCount += result.events.count; guard eventCount <= 8192 else { throw CatalogStoreError.invalid }
                    for event in result.events {
                        try check()
                        for binding in bindings where binding.classID == event.classID {
                            guard let asset = assets.first(where: { $0.path.utf8.elementsEqual(binding.path.utf8) }), let id = asset.catalogID else { continue }
                            do { _ = try await store.recordHostUsage(event, binding: binding, for: id, at: Date(), deadline: deadline); recorded += 1 }
                            catch is CancellationError { throw CancellationError() }
                            catch { failures += 1 }
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { failures += 1 }
            }
        } catch { failures += 1 }
        return LiveUsageCollection(recorded: recorded, failures: failures, rejectedDocuments: rejected)
    }
}
