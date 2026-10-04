import Foundation
import Testing
import CSQLite
@testable import SimplifyCore

private struct StoreFixture {
    let root: URL
    var database: URL { root.appendingPathComponent("Private/catalog.sqlite") }
    var store: CatalogStore { CatalogStore(url: database) }
    init() throws {
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyStoreTests/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func file(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url); return url
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
    var scope: CatalogScope { var r = ScanRequest(); r.libraries = [root]; return CatalogScope(r) }
    func asset(_ path: URL, product: String = "example:folk") -> Asset {
        var a = Asset(kind: .library, path: path.path, name: "Folk", format: "Kontakt", bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
        a.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Example", summary: "", instruments: [LibraryInstrument(name: "Accordion", path: path.path + "/Accordion.nki", tags: ["Accordion"], vendorID: "accordion", contentPaths: [path.path + "/Samples.nkx"])], tags: ["Accordion"], source: "fixture", identity: LibraryIdentity(evidence: .manifest, productID: product, installationRoot: path.path))
        return a
    }
    func report(_ assets: [Asset], partial: Bool = false) -> ScanReport {
        ScanReport(schemaVersion: 1, assets: assets, projects: [], sampleInclusions: [], issues: partial ? [ScanIssue(path: root.path, reason: "Fixture incomplete")] : [], durationSeconds: 0)
    }
    func sql(_ sql: String) throws {
        var db: OpaquePointer?; defer { sqlite3_close(db) }
        guard sqlite3_open(database.path, &db) == SQLITE_OK, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
    }
    func scalar(_ sql: String) throws -> String {
        var db: OpaquePointer?; var statement: OpaquePointer?
        defer { sqlite3_finalize(statement); sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else { throw CatalogStoreError.invalid }
        return String(cString: text)
    }
}

private func storedDateEvent(_ node: String, id: String = "event", source: String = "fixture",
                             kind: AssetDateEvidenceKind = .confirmedUse, time: Double? = 200) -> AssetDateEvidence {
    AssetDateEvidence(sourceID: source, evidenceID: id, subjectID: node, kind: kind,
                      eventDate: time.map { Date(timeIntervalSince1970: $0) },
                      ingestedAt: Date(timeIntervalSince1970: 300))
}
private let evidenceNow = Date(timeIntervalSince1970: 400)

@Test func pluginProductOwnsFreshFormatsAndKeepsEarliestDate() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("Glow.component"), b = try f.file("Glow.vst3")
    var first = Asset(kind: .plugin, path: a.path, name: "Glow AU", format: "component",
                      bundleIdentifier: "com.example.glow", logicalBytes: 12, classification: "fixture")
    first.finderDateAdded = Date(timeIntervalSince1970: 100)
    var second = Asset(kind: .plugin, path: b.path, name: "Glow VST3", format: "vst3",
                       bundleIdentifier: "com.example.glow", logicalBytes: 20, classification: "fixture")
    second.finderDateAdded = Date(timeIntervalSince1970: 200)
    var request = ScanRequest(); request.plugins = [f.root]
    let scope = CatalogScope(request)
    let snapshot = try await f.store.ingest(f.report([first, second]), scope: scope, at: Date(timeIntervalSince1970: 300))
    let ids = Set(snapshot.report.assets.compactMap(\.pluginProductID))
    #expect(ids.count == 1)
    let id = try #require(ids.first)
    #expect(snapshot.pluginProductDates[id] == first.finderDateAdded)
    #expect(snapshot.pluginProductNames[id] == "Glow AU")
    #expect(try f.scalar("SELECT COUNT(*) FROM plugin_installations") == "2")
    #expect(try f.scalar("SELECT COUNT(*) FROM plugin_products") == "1")
    let later = try await f.store.ingest(f.report([second]), scope: scope, at: Date(timeIntervalSince1970: 400))
    #expect(later.pluginProductDates[id] == first.finderDateAdded)
    #expect(later.pluginProductNames[id] == "Glow AU")
    #expect(later.report.assets.first(where: { $0.path == b.path })?.pluginProductID == id)
}

@Test func removalInOneScopeKeepsProductActiveWhenAnotherScopeHasCurrentFormat() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("One/Glow.component"), b = try f.file("Two/Glow.vst3")
    let au = Asset(kind: .plugin, path: a.path, name: "Glow", format: "component", bundleIdentifier: "com.example.glow", logicalBytes: 1, classification: "fixture")
    let vst = Asset(kind: .plugin, path: b.path, name: "Glow", format: "vst3", bundleIdentifier: "com.example.glow", logicalBytes: 1, classification: "fixture")
    var firstRequest = ScanRequest(); firstRequest.plugins = [a.deletingLastPathComponent()]
    var secondRequest = ScanRequest(); secondRequest.plugins = [b.deletingLastPathComponent()]
    let firstScope = CatalogScope(firstRequest), secondScope = CatalogScope(secondRequest)
    _ = try await f.store.ingest(f.report([au]), scope: firstScope)
    _ = try await f.store.ingest(f.report([vst]), scope: secondScope)
    try await f.store.recordRemovalIntent(paths: [a.path])
    try await f.store.finalizePluginRemoval(attempted: [a.path], succeeded: [a.path], scope: firstScope)
    #expect(try f.scalar("SELECT archived FROM plugin_products") == "0")
    #expect(try await f.store.load(scope: secondScope)?.report.assets.count == 1)
}

@Test func corruptV4PluginPayloadRollsBackProductMigration() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Broken.vst3")
    let asset = Asset(kind: .plugin, path: path.path, name: "Broken", format: "vst3",
                      bundleIdentifier: "com.example.broken", logicalBytes: 1, classification: "fixture")
    var request = ScanRequest(); request.plugins = [f.root]
    let scope = CatalogScope(request)
    _ = try await f.store.ingest(f.report([asset]), scope: scope)
    try f.sql("DROP TABLE plugin_installations; DROP TABLE plugin_products; PRAGMA user_version=4; UPDATE scope_members SET payload='{broken' WHERE node_id IN (SELECT id FROM nodes WHERE kind='plugin')")
    do { _ = try await CatalogStore(url: f.database).load(scope: scope); Issue.record("Corrupt migration unexpectedly succeeded") }
    catch { #expect(try f.scalar("PRAGMA user_version") == "4") }
}

@Test func optInRealCatalogProductMigrationCopy() async throws {
    guard let source = ProcessInfo.processInfo.environment["PRISM_PRODUCT_MIGRATION_COPY"] else { return }
    let url = URL(fileURLWithPath: source)
    _ = try await CatalogStore(url: url).load(scope: CatalogScope(ScanRequest()))
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    #expect(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    func count(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { throw CatalogStoreError.invalid }
        return Int(sqlite3_column_int(statement, 0))
    }
    #expect(try count("PRAGMA user_version") == 5)
    #expect(try count("SELECT COUNT(*) FROM plugin_installations") == 61)
    #expect(try count("SELECT COUNT(*) FROM plugin_products") == 30)
    #expect(try count("SELECT COUNT(*) FROM date_evidence") == 30)
}

@Test func dateHistorySurvivesReopenMoveOfflineAndBackupButNotIdentityReplacement() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Product.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    let node = try #require(initial.report.assets.first?.catalogID)
    let events = [storedDateEvent(node), storedDateEvent(node, id: "addition", kind: .confirmedAddition, time: 100),
                  storedDateEvent(node, id: "update", kind: .installationRecord, time: 250),
                  storedDateEvent(node, id: "unknown", kind: .loadAttempt, time: nil)]
    try await f.store.appendDateEvidence(events, asOf: evidenceNow)
    try await f.store.appendDateEvidence(events.reversed(), asOf: evidenceNow)
    #expect(try await f.store.dateEvidence(for: node, asOf: evidenceNow).count == 4)
    let moved = path.deletingLastPathComponent().appendingPathComponent("Moved.nicnt")
    try FileManager.default.moveItem(at: path, to: moved)
    let rescanned = try await f.store.ingest(f.report([f.asset(moved)]), scope: f.scope)
    #expect(rescanned.report.assets.first?.catalogID == node)
    _ = try await f.store.ingest(f.report([], partial: true), scope: f.scope)
    let summary = try await f.store.dateSummary(for: node, asOf: evidenceNow)
    #expect(summary.lastUsed == Date(timeIntervalSince1970: 200))
    #expect(summary.dateAdded == Date(timeIntervalSince1970: 100))
    #expect(summary.latestRecordedInstallation == Date(timeIntervalSince1970: 250))
    let backup = f.root.appendingPathComponent("DateBackup/catalog.sqlite")
    try await f.store.backup(to: backup)
    #expect(try await CatalogStore(url: backup).dateSummary(for: node, asOf: evidenceNow) == summary)
    try FileManager.default.removeItem(at: moved)
    _ = try f.file("Moved.nicnt")
    let replaced = try await f.store.ingest(f.report([f.asset(moved)]), scope: f.scope)
    let replacement = try #require(replaced.report.assets.first?.catalogID)
    #expect(replacement != node)
    #expect(try await f.store.dateSummary(for: replacement, asOf: evidenceNow).dateAdded == nil)
    #expect(try await f.store.dateSummary(for: node, asOf: evidenceNow) == summary)
}

@Test func dateHistoryBatchConflictsMissingSubjectsAndWriteFailuresRollBack() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Product.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    let node = try #require(initial.report.assets.first?.catalogID)
    let original = storedDateEvent(node)
    try await f.store.appendDateEvidence([original], asOf: evidenceNow)
    await #expect(throws: AssetDateEvidenceError.conflictingEvidenceID) {
        try await f.store.appendDateEvidence([storedDateEvent(node, id: "new"), storedDateEvent(node, time: 250)], asOf: evidenceNow)
    }
    await #expect(throws: CatalogStoreError.self) {
        try await f.store.appendDateEvidence([storedDateEvent(node, id: "new"), storedDateEvent("absent", id: "missing")], asOf: evidenceNow)
    }
    try f.sql("CREATE TRIGGER reject_date BEFORE INSERT ON date_evidence WHEN NEW.evidence_id='reject' BEGIN SELECT RAISE(ABORT,'fixture failure'); END;")
    await #expect(throws: CatalogStoreError.self) {
        try await f.store.appendDateEvidence([storedDateEvent(node, id: "new"), storedDateEvent(node, id: "reject")], asOf: evidenceNow)
    }
    #expect(try await f.store.dateEvidence(for: node, asOf: evidenceNow) == [original])
    await #expect(throws: CatalogStoreError.self) { try await f.store.dateEvidence(for: "absent", asOf: evidenceNow) }
}

@Test func dateHistoryByteIdentityAndCrossNodeReplayArePreserved() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("A.nicnt"), b = try f.file("B.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(a), f.asset(b)]), scope: f.scope)
    let nodes = initial.report.assets.compactMap(\.catalogID)
    let composed = "caf\u{e9}", decomposed = "cafe\u{301}"
    try await f.store.appendDateEvidence([storedDateEvent(nodes[0], source: composed), storedDateEvent(nodes[0], source: decomposed),
                                          storedDateEvent(nodes[0], id: composed), storedDateEvent(nodes[0], id: decomposed)], asOf: evidenceNow)
    #expect(try await f.store.dateEvidence(for: nodes[0], asOf: evidenceNow).count == 4)
    #expect(try await f.store.dateEvidence(for: nodes[1], asOf: evidenceNow).isEmpty)
    await #expect(throws: AssetDateEvidenceError.conflictingEvidenceID) {
        try await f.store.appendDateEvidence([storedDateEvent(nodes[1], source: composed)], asOf: evidenceNow)
    }
    #expect(try await f.store.dateEvidence(for: nodes[1], asOf: evidenceNow).isEmpty)
}

@Test func dateHistoryRejectsCorruptRowsRatherThanTruncatingOrSkipping() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Product.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    let node = try #require(initial.report.assets.first?.catalogID)
    let event = storedDateEvent(node)
    let payload = String(decoding: try JSONEncoder().encode(event), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
    let corruptions = ["payload='{'", "payload=payload || char(0) || 'ignored'", "payload=CAST(X'80' AS TEXT)",
                       "payload=CAST(zeroblob(32769) AS TEXT)", "payload=X'7B7D'", "subject_id='other'",
                       "source_id='wrong'", "payload=replace(payload,'confirmedUse','unknownFutureKind')"]
    for corruption in corruptions {
        try f.sql("DELETE FROM date_evidence; INSERT INTO date_evidence VALUES('fixture','event','\(node)','\(payload)'); UPDATE date_evidence SET \(corruption);")
        if corruption == "subject_id='other'" {
            // Row-key tampering is detected when the selected node exists too.
            try f.sql("UPDATE date_evidence SET subject_id='\(node)',payload=replace(payload,'\(node)','other');")
        }
        await #expect(throws: CatalogStoreError.self) { try await f.store.dateEvidence(for: node, asOf: evidenceNow) }
        await #expect(throws: CatalogStoreError.self) { try await f.store.appendDateEvidence([storedDateEvent(node, id: "new")], asOf: evidenceNow) }
        #expect(try f.scalar("SELECT COUNT(*) FROM date_evidence") == "1")
    }
}

@Test func dateHistoryCapacityIsAfterDedupAndNeverPrunesOldEvidence() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Product.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    let node = try #require(initial.report.assets.first?.catalogID)
    let records = (0..<10_000).map { storedDateEvent(node, id: "event-\($0)") }
    try await f.store.appendDateEvidence(records, asOf: evidenceNow)
    try await f.store.appendDateEvidence([records[0]], asOf: evidenceNow)
    await #expect(throws: AssetDateEvidenceError.tooManyRecords) {
        try await f.store.appendDateEvidence([storedDateEvent(node, id: "overflow")], asOf: evidenceNow)
    }
    #expect(try await f.store.dateEvidence(for: node, asOf: evidenceNow).count == 10_000)
}

@Test func dateHistoryInvalidInputDoesNotCreateDatabase() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    await #expect(throws: AssetDateEvidenceError.eventAfterIngestion) {
        try await f.store.appendDateEvidence([storedDateEvent("node", time: 301)], asOf: evidenceNow)
    }
    await #expect(throws: CatalogStoreError.self) { try await f.store.dateEvidence(for: "node", asOf: evidenceNow) }
    #expect(!FileManager.default.fileExists(atPath: f.database.path))
}

@Test func populatedV2MigrationRetainsHistoryMetadataAndVerifiedBackup() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    try FileManager.default.createDirectory(at: f.database.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/catalog-v2.sql")
    try f.sql(String(contentsOf: fixture, encoding: .utf8))
    try f.sql("""
        INSERT INTO nodes VALUES('legacy','identity','product','plugin','/fixture/Plugin',100,200,1);
        INSERT INTO metadata_overrides VALUES('legacy-subject','legacy','{"sentinel":"unchanged"}');
        """)
    #expect(try await f.store.dateEvidence(for: "legacy", asOf: evidenceNow).isEmpty)
    #expect(try f.scalar("PRAGMA user_version") == "5")
    #expect(try f.scalar("SELECT first_seen || ',' || last_seen || ',' || baseline FROM nodes") == "100.0,200.0,1")
    #expect(try f.scalar("SELECT payload FROM metadata_overrides") == "{\"sentinel\":\"unchanged\"}")
    let backups = try FileManager.default.contentsOfDirectory(at: f.database.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("catalog-v2-backup-") }
    #expect(backups.count == 1)
    let backup = try #require(backups.first)
    var db: OpaquePointer?; var statement: OpaquePointer?
    defer { sqlite3_finalize(statement); sqlite3_close(db) }
    #expect(sqlite3_open_v2(backup.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    #expect(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
    #expect(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 2)
    try await f.store.appendDateEvidence([storedDateEvent("legacy")], asOf: evidenceNow)
    #expect(try await f.store.dateEvidence(for: "legacy", asOf: evidenceNow).count == 1)
    #expect(try FileManager.default.contentsOfDirectory(at: f.database.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("catalog-v2-backup-") }.count == 1)
}

@Test func failedV2MigrationLeavesOriginalSchemaAndDataIntact() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    try FileManager.default.createDirectory(at: f.database.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/catalog-v2.sql")
    try f.sql(String(contentsOf: fixture, encoding: .utf8))
    try f.sql("CREATE TABLE date_evidence(value); INSERT INTO date_evidence VALUES('preserve');")
    let before = try Data(contentsOf: f.database)
    await #expect(throws: CatalogStoreError.self) { try await f.store.load(scope: f.scope) }
    #expect(try Data(contentsOf: f.database) == before)
    #expect(try f.scalar("PRAGMA user_version") == "2")
    #expect(try f.scalar("SELECT value FROM date_evidence") == "preserve")
}

@Test func catalogReopenGraphMoveAndDuplicateInstallations() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("A/Product.nicnt"), b = try f.file("B/Product.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(a), f.asset(b)]), scope: f.scope, at: Date(timeIntervalSince1970: 100))
    #expect(initial.report.assets.count == 2)
    #expect(Set(initial.report.assets.compactMap(\.catalogID)).count == 2)
    #expect(initial.observations.values.allSatisfy { $0.baseline })
    let saved = try #require(try await f.store.load(scope: f.scope))
    #expect(saved.report.assets.flatMap { $0.libraryMetadata?.instruments ?? [] }.count == 2)
    #expect(saved.report.assets[0].libraryMetadata?.instruments[0].contentPaths?.count == 1)
    let originalID = try #require(saved.report.assets.first { $0.path == a.path }?.catalogID)
    let renamed = a.deletingLastPathComponent().appendingPathComponent("Renamed.nicnt")
    try FileManager.default.moveItem(at: a, to: renamed)
    let moved = try await f.store.ingest(f.report([f.asset(renamed), f.asset(b)]), scope: f.scope, at: Date(timeIntervalSince1970: 200))
    #expect(moved.report.assets.first { $0.path == renamed.path }?.catalogID == originalID)
    #expect(moved.observations[originalID]?.firstSeen == Date(timeIntervalSince1970: 100))
    #expect(moved.observations[originalID]?.lastSeen == Date(timeIntervalSince1970: 200))
}

@Test func catalogPartialOfflineAndScopeIsolation() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("Product.nicnt")
    _ = try await f.store.ingest(f.report([f.asset(a)], partial: true), scope: f.scope)
    let b = try f.file("Later.nicnt")
    let incompleteBaseline = try await f.store.ingest(f.report([f.asset(b)]), scope: f.scope)
    #expect(incompleteBaseline.report.assets.count == 2)
    #expect(incompleteBaseline.observations.values.allSatisfy { $0.baseline })
    #expect(incompleteBaseline.report.assets.first { $0.path == a.path }?.catalogStale == true)
    let c = try f.file("New.nicnt")
    let additions = try await f.store.ingest(f.report([f.asset(c)]), scope: f.scope)
    let newID = try #require(additions.report.assets.first { $0.path == c.path }?.catalogID)
    #expect(additions.observations[newID]?.baseline == false)
    var otherRequest = ScanRequest(); otherRequest.libraries = [f.root.appendingPathComponent("Other")]
    let otherScope = CatalogScope(otherRequest)
    #expect(try await f.store.load(scope: otherScope) == nil)
    var changed = f.asset(a); changed.libraryMetadata?.instruments = []
    _ = try await f.store.ingest(f.report([changed]), scope: otherScope)
    let originalScope = try #require(try await f.store.load(scope: f.scope))
    #expect(originalScope.report.assets.first { $0.path == a.path }?.libraryMetadata?.instruments.count == 1)
    let offline = try await f.store.ingest(f.report([], partial: true), scope: f.scope)
    #expect(offline.report.assets.count == 3)
    #expect(offline.report.assets.allSatisfy { $0.catalogStale == true })
}

@Test func catalogRollbackFutureCorruptAndBackup() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("Product.nicnt")
    let initial = try await f.store.ingest(f.report([f.asset(a)]), scope: f.scope, at: Date(timeIntervalSince1970: 100))
    try f.sql("CREATE TRIGGER fail_insert BEFORE INSERT ON nodes WHEN NEW.path LIKE '%Reject%' BEGIN SELECT RAISE(ABORT,'fixture rollback'); END;")
    let rejected = try f.file("Reject.nicnt")
    await #expect(throws: CatalogStoreError.self) { try await f.store.ingest(f.report([f.asset(a), f.asset(rejected)]), scope: f.scope, at: Date(timeIntervalSince1970: 200)) }
    let restored = try #require(try await f.store.load(scope: f.scope))
    #expect(restored.savedAt == initial.savedAt)
    #expect(restored.report.assets.count == 1)
    #expect(restored.observations.values.first?.lastSeen == Date(timeIntervalSince1970: 100))
    let backup = f.root.appendingPathComponent("Backup/catalog.sqlite")
    try await f.store.backup(to: backup)
    #expect(try await CatalogStore(url: backup).load(scope: f.scope)?.report.assets.count == 1)
    await #expect(throws: CatalogStoreError.self) { try await f.store.backup(to: backup) }
    try f.sql("PRAGMA user_version=99")
    let before = try Data(contentsOf: f.database)
    await #expect(throws: CatalogStoreError.self) { try await f.store.load(scope: f.scope) }
    await #expect(throws: CatalogStoreError.self) { try await f.store.ingest(f.report([]), scope: f.scope) }
    #expect(try Data(contentsOf: f.database) == before)
    let corrupt = try f.file("corrupt.sqlite")
    let bytes = try Data(contentsOf: corrupt)
    await #expect(throws: CatalogStoreError.self) { try await CatalogStore(url: corrupt).load(scope: f.scope) }
    #expect(try Data(contentsOf: corrupt) == bytes)
}

@Test func catalogRemovalIntentCachedIdentitiesAndPrivateFiles() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let marker = try f.file("Example.vst3/Contents/marker")
    let path = marker.deletingLastPathComponent().deletingLastPathComponent()
    let plugin = Asset(kind: .plugin, path: path.path, name: "Example", format: "vst3", bundleIdentifier: "example", logicalBytes: nil, classification: "fixture", fileIdentity: PluginFileIdentity.read(path.path))
    let cached = try await f.store.ingest(f.report([plugin]), scope: f.scope)
    #expect(cached.report.assets.first?.fileIdentity == nil)
    try await f.store.recordRemovalIntent(paths: [path.path])
    #expect(try await f.store.load(scope: f.scope)?.report.assets.isEmpty == true)
    // A failed removal or Finder restoration becomes visible only after a fresh observation.
    #expect(try await f.store.ingest(f.report([plugin]), scope: f.scope).report.assets.count == 1)
    let attributes = try FileManager.default.attributesOfItem(atPath: f.database.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let pipe = f.root.appendingPathComponent("pipe.sqlite")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    await #expect(throws: CatalogStoreError.self) { try await CatalogStore(url: pipe).load(scope: f.scope) }
    let link = f.root.appendingPathComponent("link.sqlite")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.database)
    await #expect(throws: CatalogStoreError.self) { try await CatalogStore(url: link).load(scope: f.scope) }
}

@Test func catalogPreservesUnversionedForeignDatabase() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    try FileManager.default.createDirectory(at: f.database.deletingLastPathComponent(), withIntermediateDirectories: true)
    try f.sql("CREATE TABLE foreign_content(value TEXT); INSERT INTO foreign_content VALUES('keep me');")
    let before = try Data(contentsOf: f.database)
    await #expect(throws: CatalogStoreError.self) { try await f.store.load(scope: f.scope) }
    await #expect(throws: CatalogStoreError.self) { try await f.store.ingest(f.report([]), scope: f.scope) }
    #expect(try Data(contentsOf: f.database) == before)
}

@Test func releasedCatalogSchemaAndHardlinksRemainCompatible() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    try FileManager.default.createDirectory(at: f.database.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/catalog-v1.sql")
    try f.sql(String(contentsOf: fixture, encoding: .utf8))
    #expect(try await f.store.load(scope: f.scope) == nil)
    let a = try f.file("One.nicnt"), b = f.root.appendingPathComponent("Two.nicnt")
    try FileManager.default.linkItem(at: a, to: b)
    let snapshot = try await f.store.ingest(f.report([f.asset(a), f.asset(b)]), scope: f.scope)
    #expect(snapshot.report.assets.count == 2)
    #expect(Set(snapshot.report.assets.compactMap(\.catalogID)).count == 2)
}

@Test func overlappingScopeRetainsBaselineAndPartialMembersRemainVisible() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    _ = try await f.store.ingest(f.report([]), scope: f.scope)
    let a = try f.file("Product.nicnt")
    var asset = f.asset(a)
    asset.libraryMetadata?.instruments[0].contentPaths = ["/fixture/Close.otarc", "/fixture/Room.otarc"]
    let addition = try await f.store.ingest(f.report([asset]), scope: f.scope)
    #expect(addition.observations.values.first?.baseline == false)
    var request = ScanRequest(); request.libraries = [f.root, f.root.appendingPathComponent("Extra")]
    let other = CatalogScope(request)
    let baseline = try await f.store.ingest(f.report([asset]), scope: other)
    #expect(baseline.observations.values.first?.baseline == false)
    #expect(try await f.store.load(scope: f.scope)?.observations.values.first?.baseline == false)
    asset.libraryMetadata?.instruments[0].contentPaths = ["/fixture/Close.otarc"]
    let partial = try await f.store.ingest(f.report([asset], partial: true), scope: f.scope)
    let instrument = try #require(partial.report.assets.first?.libraryMetadata?.instruments.first)
    #expect(instrument.contentPaths == ["/fixture/Close.otarc", "/fixture/Room.otarc"])
    #expect(instrument.contentMembers?.first { $0.path.contains("Room") }?.stale == true)
    #expect(instrument.contentMembers?.first { $0.path.contains("Close") }?.stale == false)
    #expect(try await f.store.load(scope: other)?.report.assets.first?.libraryMetadata?.instruments.first?.contentMembers?.allSatisfy { $0.stale } == true)
}

@Test func rootBaselinesIgnoreOtherRootsAndProjectsAndPreserveOfflineScope() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("Libraries/A.nicnt")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    request.plugins = [f.root.appendingPathComponent("MissingPlugins")]
    request.projects = [f.root.appendingPathComponent("Projects")]
    let scope = CatalogScope(request)
    func report(_ assets: [Asset]) -> ScanReport {
        ScanReport(schemaVersion: 1, assets: assets, projects: [], sampleInclusions: [], issues: [
            ScanIssue(path: request.plugins[0].path, reason: "Root unavailable"),
            ScanIssue(path: request.projects[0].path + "/Session.ptx", reason: "Project reference coverage: unsupported")
        ], durationSeconds: 0)
    }
    let first = try await f.store.ingest(report([f.asset(a)]), scope: scope)
    let b = try f.file("Libraries/B.nicnt")
    let later = try await f.store.ingest(report([f.asset(a), f.asset(b)]), scope: scope)
    let bID = try #require(later.report.assets.first { $0.path == b.path }?.catalogID)
    #expect(later.observations[bID]?.baseline == false)
    request.libraries.append(f.root.appendingPathComponent("Extra"))
    let expanded = CatalogScope(request)
    let restored = try #require(try await f.store.load(scope: expanded))
    #expect(restored.report.assets.count == 2)
    #expect(restored.report.assets.allSatisfy { $0.catalogStale == true })
    #expect(restored.observations[bID]?.baseline == false)
    let c = try f.file("Extra/C.nicnt")
    let added = try await f.store.ingest(report([f.asset(c)]), scope: expanded)
    #expect(added.report.assets.count == 3)
    let cID = try #require(added.report.assets.first { $0.path == c.path }?.catalogID)
    #expect(added.observations[cID]?.baseline == true)
    #expect(added.report.assets.first { $0.path == a.path }?.catalogID == first.report.assets.first?.catalogID)
    request.libraries.removeFirst()
    let reduced = try #require(try await f.store.load(scope: CatalogScope(request)))
    #expect(reduced.report.assets.map(\.path) == [c.path])
}

@Test func metadataOverridesSurviveReopenRescanSuppressionBackupAndWriteFailure() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Library.nicnt")
    let snapshot = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    let id = try #require(snapshot.report.assets.first?.catalogID)
    let subject = MetadataSubject(nodeID: id, instrument: snapshot.report.assets.first?.libraryMetadata?.instruments.first)
    let edit = MusicalMetadata(fields: ["character": ["dark", "warm"], "instrument": []])
    try await f.store.saveMetadata(edit, for: subject)
    let reopened = try #require(try await f.store.load(scope: f.scope))
    #expect(reopened.metadata[subject.key] == edit)
    let rescanned = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    #expect(rescanned.metadata[subject.key] == edit)
    #expect(MusicalMetadata.suggested(name: "Accordion", tags: [], kind: .library).applying(edit)[.instrument] == [])
    let backup = f.root.appendingPathComponent("copy.sqlite")
    try await f.store.backup(to: backup)
    #expect(try await CatalogStore(url: backup).load(scope: f.scope)?.metadata[subject.key] == edit)
    try f.sql("CREATE TRIGGER fail_metadata BEFORE UPDATE ON metadata_overrides BEGIN SELECT RAISE(ABORT,'write failed'); END;")
    await #expect(throws: CatalogStoreError.self) { try await f.store.saveMetadata(MusicalMetadata(fields: ["role": ["pulse"]]), for: subject) }
    #expect(try await f.store.load(scope: f.scope)?.metadata[subject.key] == edit)
    try await f.store.saveMetadata(nil, for: subject)
    #expect(try await f.store.load(scope: f.scope)?.metadata[subject.key] == nil)
}

@Test func discoveryWindowBoundariesAndMusicalVocabulary() throws {
    let now = Date(timeIntervalSince1970: 10_000_000)
    func observation(_ age: Double, baseline: Bool = false) -> CatalogObservation {
        CatalogObservation(id: "fixture", firstSeen: now.addingTimeInterval(-age), lastSeen: now, baseline: baseline, stale: true)
    }
    #expect(observation(30 * 86400).isRecent(at: now))
    #expect(!observation(30 * 86400 + 1).isRecent(at: now))
    #expect(!observation(-1).isRecent(at: now))
    #expect(!observation(1, baseline: true).isRecent(at: now))
    let value = MusicalMetadata.suggested(name: "Solo Celli Con Sordino Legato", tags: ["warm"], kind: .library)
    #expect(value[.instrument] == ["cello"])
    #expect(value[.technique]?.contains("muted") == true)
    #expect(MusicalSearch.matches("warm cello legato", in: value.searchText))
    #expect(!MusicalSearch.matches("accordion legato", in: value.searchText))
    #expect(!MusicalSearch.matches("Percussion 0", in: "Percussion 10 wav /fixture-01"))
    #expect(throws: CatalogStoreError.self) { try MusicalMetadata(fields: ["bpm": ["110", "120"]]).validated() }
    #expect(throws: CatalogStoreError.self) { try MusicalMetadata(fields: ["unexpected": ["value"]]).validated() }
}

@Test func returningToPriorScopeUsesObservationDatesNotOfflineSnapshotDates() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = try f.file("A.nicnt")
    var asset = f.asset(a)
    _ = try await f.store.ingest(f.report([asset]), scope: f.scope, at: Date(timeIntervalSince1970: 100))
    var request = ScanRequest(); request.libraries = [f.root, f.root.appendingPathComponent("Extra")]
    let expanded = CatalogScope(request)
    let b = try f.file("B.nicnt")
    asset.libraryMetadata?.instruments.append(LibraryInstrument(name: "New Tremolo", path: f.root.appendingPathComponent("New.nki").path, tags: ["tremolo"]))
    _ = try await f.store.ingest(f.report([asset, f.asset(b)]), scope: expanded, at: Date(timeIntervalSince1970: 200))
    let returned = try #require(try await f.store.load(scope: f.scope))
    #expect(returned.report.assets.count == 2)
    #expect(returned.report.assets.first { $0.path == a.path }?.libraryMetadata?.instruments.contains { $0.name == "New Tremolo" } == true)
    // A later offline scope is not newer evidence about this member.
    _ = try await f.store.ingest(f.report([], partial: true), scope: f.scope, at: Date(timeIntervalSince1970: 300))
    var another = request; another.projects = [f.root.appendingPathComponent("Projects")]
    let final = try #require(try await f.store.load(scope: CatalogScope(another)))
    #expect(final.report.assets.count == 2)
    #expect(final.report.assets.first { $0.path == a.path }?.libraryMetadata?.instruments.contains { $0.name == "New Tremolo" } == true)
    #expect(final.report.assets.allSatisfy { $0.catalogStale == true })
}

@Test func populatedV1MigrationPreservesGraphDatesBaselineAndBackup() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    try FileManager.default.createDirectory(at: f.database.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/catalog-v1.sql")
    try f.sql(String(contentsOf: fixture, encoding: .utf8))
    func sqlJSON<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
    }
    let path = try f.file("Legacy.nicnt")
    var asset = f.asset(path); asset.catalogID = "legacy-observation"
    let instrument = try #require(asset.libraryMetadata?.instruments.first)
    asset.libraryMetadata?.instruments = []
    let configuration = try sqlJSON(f.scope), payload = try sqlJSON(asset), child = try sqlJSON(instrument), evidence = try sqlJSON(f.report([]))
    try f.sql("""
        INSERT INTO nodes VALUES('legacy-observation','legacy-key','example:folk','library','\(path.path)',100,200,1);
        INSERT INTO scopes VALUES('\(f.scope.key)','\(configuration)','\(evidence)',200,'legacy-generation',1);
        INSERT INTO scope_members VALUES('\(f.scope.key)','legacy-observation','\(path.path)','\(payload)','legacy-generation',1);
        INSERT INTO instruments VALUES('\(f.scope.key)','legacy-observation','accordion','\(child)','legacy-generation');
        INSERT INTO physical_members VALUES('\(f.scope.key)','legacy-observation','accordion','\(path.path)/Samples.nkx','legacy-generation');
        """)
    let migrated = try #require(try await f.store.load(scope: f.scope))
    #expect(migrated.observations["legacy-observation"]?.firstSeen == Date(timeIntervalSince1970: 100))
    #expect(migrated.observations["legacy-observation"]?.lastSeen == Date(timeIntervalSince1970: 200))
    #expect(migrated.observations["legacy-observation"]?.baseline == true)
    #expect(migrated.report.assets.first?.libraryMetadata?.instruments.first?.contentPaths == [path.path + "/Samples.nkx"])
    #expect(migrated.metadata.isEmpty)
    let backups = try FileManager.default.contentsOfDirectory(at: f.database.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("catalog-v1-backup-") }
    #expect(backups.count == 1)
    let backup = try #require(backups.first)
    var db: OpaquePointer?; defer { sqlite3_close(db) }
    #expect(sqlite3_open_v2(backup.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 1); sqlite3_finalize(statement)
    #expect(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM instruments", -1, &statement, nil) == SQLITE_OK)
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 1); sqlite3_finalize(statement)
    let new = try f.file("AfterMigration.nicnt")
    let later = try await f.store.ingest(f.report([f.asset(new)]), scope: f.scope, at: Date(timeIntervalSince1970: 300))
    let id = try #require(later.report.assets.first { $0.path == new.path }?.catalogID)
    #expect(later.observations[id]?.baseline == false)
}

@Test func reclassifyingExcludedNestedRootsDoesNotInventAcquisitions() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    var initial = ScanRequest(); initial.libraries = [f.root]; initial.samples = [f.root.appendingPathComponent("Excluded")]
    _ = try await f.store.ingest(f.report([]), scope: CatalogScope(initial))
    let path = try f.file("Excluded/Known.nicnt")
    initial.samples = []
    let later = try await f.store.ingest(f.report([f.asset(path)]), scope: CatalogScope(initial))
    #expect(later.observations.values.allSatisfy { $0.baseline })
}

@Test func partialIngestPreservesInactiveFreshnessGraphEvidenceAndMetadata() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let library = f.asset(try f.file("Libraries/Folk.nicnt"))
    let missingLibrary = f.asset(try f.file("Libraries/Old.nicnt"), product: "old")
    let pluginURL = try f.file("Plugins/Echo.vst3/Contents/marker").deletingLastPathComponent().deletingLastPathComponent()
    let plugin = Asset(kind: .plugin, path: pluginURL.path, name: "Echo", format: "vst3", bundleIdentifier: "com.test.echo", logicalBytes: nil, classification: "test")
    let sample = Asset(kind: .sample, path: try f.file("Samples/Kick.wav").path, name: "Kick", format: "wav", bundleIdentifier: nil, logicalBytes: 7, classification: "test")
    var request = ScanRequest(); request.plugins = [f.root.appendingPathComponent("Plugins")]; request.samples = [f.root.appendingPathComponent("Samples")]; request.libraries = [f.root.appendingPathComponent("Libraries")]
    let scope = CatalogScope(request)
    _ = try await f.store.ingest(f.report([library, missingLibrary, plugin, sample]), scope: scope, at: Date(timeIntervalSince1970: 100))
    let inclusion = SampleInclusion(samplePath: sample.path, projectPaths: ["/fixture/Cue.rpp"], latestReferencingProjectModifiedAt: Date(timeIntervalSince1970: 50), status: "referenced")
    let baselineReport = ScanReport(schemaVersion: 1, assets: [library, plugin, sample], projects: [], sampleInclusions: [inclusion], issues: [ScanIssue(path: "/fixture/shared", reason: "Library issue", kind: .library), ScanIssue(path: "/legacy", reason: "Old warning")], durationSeconds: 0)
    let before = try await f.store.ingest(baselineReport, scope: scope, at: Date(timeIntervalSince1970: 200))
    let libraryID = try #require(before.report.assets.first { $0.path == library.path }?.catalogID)
    let metadataSubject = MetadataSubject(nodeID: libraryID)
    try await f.store.saveMetadata(MusicalMetadata(fields: ["instrument": ["strings"]]), for: metadataSubject)
    let partial = f.report([plugin])
    _ = try await f.store.ingest(partial, scope: scope, scannedKinds: [.plugin], at: Date(timeIntervalSince1970: 300))
    let after = try #require(try await f.store.load(scope: scope))
    #expect(after.report.assets.count == 4)
    for asset in after.report.assets where asset.kind != .plugin {
        let original = try #require(before.report.assets.first { $0.path == asset.path })
        #expect(asset.catalogStale == original.catalogStale)
        #expect(after.observations[asset.catalogID!]?.lastSeen == before.observations[asset.catalogID!]?.lastSeen)
        for patch in asset.libraryMetadata?.instruments ?? [] {
            #expect(patch.catalogStale == asset.catalogStale)
            #expect(patch.contentMembers?.allSatisfy { $0.stale == (asset.catalogStale == true) } == true)
        }
    }
    #expect(after.report.sampleInclusions.first?.projectPaths == inclusion.projectPaths)
    #expect(after.report.issues.contains { $0.reason == "Library issue" })
    #expect(after.metadata[metadataSubject.key]?[.instrument] == ["strings"])
    // Adding a plugin folder creates a new full scope; untouched sections retain evidence.
    var projectionOnly = request
    projectionOnly.plugins.append(f.root.appendingPathComponent("ProjectionOnly"))
    _ = try await f.store.load(scope: CatalogScope(projectionOnly))
    request.plugins.append(f.root.appendingPathComponent("ExtraPlugins"))
    let changedScope = CatalogScope(request)
    _ = try await f.store.load(scope: changedScope) // Reopen may seed scope before the scan.
    let changed = try await f.store.ingest(partial, scope: changedScope, scannedKinds: [.plugin], at: Date(timeIntervalSince1970: 350))
    #expect(changed.report.assets.first { $0.path == library.path }?.catalogStale == false)
    #expect(changed.report.assets.first { $0.path == missingLibrary.path }?.catalogStale == true)
    #expect(changed.report.sampleInclusions.first?.projectPaths == inclusion.projectPaths)
    #expect(changed.report.issues.contains { $0.reason == "Library issue" })
    #expect(changed.report.issues.filter { $0.reason == "Old warning" }.count == 1)
    #expect(changed.report.assets.first { $0.path == library.path }?.libraryMetadata?.instruments.first?.catalogStale == false)
    #expect(changed.observations[libraryID]?.lastSeen == before.observations[libraryID]?.lastSeen)
    // Empty/offline plugin observation affects plugins only.
    let offline = try await f.store.ingest(f.report([]), scope: scope, scannedKinds: [.plugin], at: Date(timeIntervalSince1970: 400))
    #expect(offline.report.assets.first { $0.kind == .plugin }?.catalogStale == true)
    #expect(offline.report.assets.first { $0.path == library.path }?.catalogStale == false)
}

@Test func installerProjectionIsAtomicByteExactAndDeterministicAcrossReopen() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Product.nicnt")
    let saved = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    let node = try #require(saved.report.assets.first?.catalogID)
    func receipt(_ subject: String, _ id: String, _ seconds: Double) -> AssetDateEvidence {
        AssetDateEvidence(sourceID: PackageReceiptProvenance.sourceID, evidenceID: id, subjectID: subject,
            kind: .installationRecord, eventDate: Date(timeIntervalSince1970: seconds), ingestedAt: evidenceNow,
            packageReceipt: PackageReceiptProvenance(packageID: "fixture.package", packageVersion: "1",
                bundlePath: "/Fixture.component", bundleIdentifier: "fixture", bundleVersions: ["1"]))
    }
    try await f.store.appendDateEvidence([receipt(node, "b", 200), receipt(node, "a", 200), receipt(node, "older", 100),
        storedDateEvent(node, id: "use", time: 300)], asOf: evidenceNow)
    let values = try await f.store.latestInstallerRecords(for: [node, node], asOf: evidenceNow)
    #expect(values.count == 1 && values[Data(node.utf8)]?.evidenceID == "a")
    await #expect(throws: CatalogStoreError.self) { try await f.store.latestInstallerRecords(for: [node, "missing"], asOf: evidenceNow) }
    await #expect(throws: AssetDateEvidenceError.tooManyRecords) {
        try await f.store.latestInstallerRecords(for: Array(repeating: node, count: 2049), asOf: evidenceNow)
    }
    for (id, suffix) in [("é", "one"), ("e\u{301}", "two")] {
        try f.sql("INSERT INTO nodes SELECT '\(id)',identity||'\(suffix)',product_key,kind,path,first_seen,last_seen,baseline FROM nodes LIMIT 1")
        try await f.store.appendDateEvidence([receipt(id, suffix, 250)], asOf: evidenceNow)
    }
    let distinct = try await f.store.latestInstallerRecords(for: ["é", "e\u{301}"], asOf: evidenceNow)
    #expect(distinct.count == 2 && distinct[Data("é".utf8)]?.evidenceID == "one" && distinct[Data("e\u{301}".utf8)]?.evidenceID == "two")
    try f.sql("UPDATE date_evidence SET payload='broken' WHERE subject_id='é'")
    await #expect(throws: CatalogStoreError.self) { try await f.store.latestInstallerRecords(for: [node, "é"], asOf: evidenceNow) }
    #expect(try await f.store.latestInstallerRecords(for: [node], asOf: evidenceNow) == values)
}

@Test func additionBoundsSeparateBaselineFromArrivalAndSurviveMovesAndGaps() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
    let first = try f.file("First.nicnt")
    let baselineContext = AdditionScanContext(scope: f.scope, startedAt: date(10))
    let baseline = try await f.store.ingest(f.report([f.asset(first)]), scope: f.scope, at: date(20), additionContext: baselineContext)
    #expect(baseline.observations.values.first?.addition?.basis == .presentBy)
    let context = AdditionScanContext(scope: f.scope, startedAt: date(30))
    let next = try f.file("Next.nicnt")
    let arrived = try await f.store.ingest(f.report([f.asset(first), f.asset(next)]), scope: f.scope, at: date(40), additionContext: context)
    let node = try #require(arrived.report.assets.first { $0.path == next.path }?.catalogID)
    let bounds = try #require(arrived.observations[node]?.addition)
    #expect(bounds.lower == date(10) && bounds.upper == date(40) && bounds.basis == .observedArrival)
    let moved = f.root.appendingPathComponent("Moved.nicnt")
    try FileManager.default.moveItem(at: next, to: moved)
    let scanned = try await f.store.ingest(f.report([f.asset(first), f.asset(moved)]), scope: f.scope, at: date(60), additionContext: AdditionScanContext(scope: f.scope, startedAt: date(50)))
    #expect(scanned.observations[node]?.addition == bounds)
    _ = try await f.store.ingest(f.report([], partial: true), scope: f.scope, at: date(80), additionContext: AdditionScanContext(scope: f.scope, startedAt: date(70)))
    let later = try f.file("Later.nicnt")
    let afterGap = try await f.store.ingest(f.report([f.asset(later)]), scope: f.scope, at: date(100), additionContext: AdditionScanContext(scope: f.scope, startedAt: date(90)))
    let laterID = try #require(afterGap.report.assets.first { $0.path == later.path }?.catalogID)
    #expect(afterGap.observations[laterID]?.addition?.basis == .presentBy)
    #expect(try await f.store.load(scope: f.scope)?.observations[node]?.addition == bounds)
}

@Test func additionBoundsInvalidateReplacedRootPolicyAndClockRollback() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let directory = f.root.appendingPathComponent("Inventory")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var request = ScanRequest(); request.samples = [directory]; let scope = CatalogScope(request)
    func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
    _ = try await f.store.ingest(f.report([]), scope: scope, at: date(20), additionContext: AdditionScanContext(scope: scope, startedAt: date(10)))
    try FileManager.default.moveItem(at: directory, to: f.root.appendingPathComponent("OldInventory"))
    let file = try f.file("Inventory/New.wav")
    let sample = Asset(kind: .sample, path: file.path, name: "New", format: "wav", bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    let replaced = try await f.store.ingest(f.report([sample]), scope: scope, at: date(40), additionContext: AdditionScanContext(scope: scope, startedAt: date(30)))
    #expect(replaced.observations.values.first?.addition?.basis == .presentBy)
    try f.sql("UPDATE scan_coverage SET policy='old-policy'")
    let otherFile = try f.file("Inventory/Other.wav")
    let other = Asset(kind: .sample, path: otherFile.path, name: "Other", format: "wav", bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    let changed = try await f.store.ingest(f.report([sample, other]), scope: scope, at: date(60), additionContext: AdditionScanContext(scope: scope, startedAt: date(50)))
    #expect(changed.observations[try #require(changed.report.assets.first { $0.path == other.path }?.catalogID)]?.addition?.basis == .presentBy)
    _ = try await f.store.ingest(f.report([sample, other]), scope: scope, at: date(65), additionContext: AdditionScanContext(scope: scope, startedAt: date(70)))
    #expect(try f.scalar("SELECT count(*) FROM scan_coverage") == "0")
}

@Test func additionGroupPrecisionDoesNotLeakAcrossUnknownFormats() throws {
    let early = Date(timeIntervalSince1970: 10), late = Date(timeIntervalSince1970: 20)
    let exact = try AdditionDateEvidence(basis: .exact, lower: late, upper: late)
    let interval = try AdditionDateEvidence(basis: .observedArrival, lower: early, upper: late)
    let by = try AdditionDateEvidence(basis: .presentBy, lower: nil, upper: early)
    #expect(try AdditionDateEvidence.group([exact, nil])?.basis == .presentBy)
    #expect(try AdditionDateEvidence.group([exact, by]) == by)
    #expect(try AdditionDateEvidence.group([exact, interval]) == interval)
    #expect(try AdditionDateEvidence.group([nil, nil]) == nil)
    #expect(throws: CatalogStoreError.self) { try AdditionDateEvidence(basis: .observedArrival, lower: late, upper: early) }
}

@Test func additionBoundsCoverEveryAssetKindWithoutPlayerInheritance() async throws {
    for kind in AssetKind.allCases {
        let f = try StoreFixture(); defer { f.clean() }
        var request = ScanRequest()
        switch kind { case .plugin: request.plugins = [f.root]; case .sample: request.samples = [f.root]; case .library: request.libraries = [f.root] }
        let scope = CatalogScope(request)
        _ = try await f.store.ingest(f.report([]), scope: scope, at: Date(timeIntervalSince1970: 20), additionContext: AdditionScanContext(scope: scope, startedAt: Date(timeIntervalSince1970: 10)))
        let url = try f.file("New.asset")
        let asset = Asset(kind: kind, path: url.path, name: "New", format: "fixture", bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
        let saved = try await f.store.ingest(f.report([asset]), scope: scope, at: Date(timeIntervalSince1970: 40), additionContext: AdditionScanContext(scope: scope, startedAt: Date(timeIntervalSince1970: 30)))
        #expect(saved.observations.values.first?.addition?.basis == .observedArrival)
        #expect(saved.observations.values.first?.addition?.lower == Date(timeIntervalSince1970: 10))
    }
}

@Test func schemaThreeAdditionMigrationRetainsLedgerAndBacksUpOriginal() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let file = try f.file("Library.nicnt")
    let saved = try await f.store.ingest(f.report([f.asset(file)]), scope: f.scope, at: evidenceNow)
    let node = try #require(saved.report.assets.first?.catalogID)
    try await f.store.appendDateEvidence([storedDateEvent(node)], asOf: evidenceNow)
    // A schema3 fixture has the same inventory/date ledger but neither schema4 table.
    try f.sql("DROP TABLE plugin_installations; DROP TABLE plugin_products; DROP TABLE node_addition_bounds; DROP TABLE scan_coverage; PRAGMA user_version=3;")
    let restored = try #require(try await f.store.load(scope: f.scope))
    #expect(restored.observations[node]?.addition?.basis == .presentBy)
    #expect(restored.observations[node]?.addition?.upper == evidenceNow)
    #expect(try await f.store.dateEvidence(for: node, asOf: evidenceNow).count == 1)
    #expect(try f.scalar("PRAGMA user_version") == "5")
    let backups = try FileManager.default.contentsOfDirectory(at: f.database.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("catalog-v3-backup-") }
    #expect(backups.count == 1)
}

@Test func additionCoverageDoesNotSurviveRemovedRootsOrWeakPathIdentity() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let a = f.root.appendingPathComponent("A"), b = f.root.appendingPathComponent("B")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    var request = ScanRequest(); request.samples = [a]; let scopeA = CatalogScope(request)
    request.samples = [b]; let scopeB = CatalogScope(request)
    func context(_ scope: CatalogScope, _ t: Double) -> AdditionScanContext { AdditionScanContext(scope: scope, startedAt: Date(timeIntervalSince1970: t)) }
    _ = try await f.store.ingest(f.report([]), scope: scopeA, at: Date(timeIntervalSince1970: 20), additionContext: context(scopeA, 10))
    _ = try await f.store.load(scope: scopeB)
    let path = try f.file("A/New.wav")
    let asset = Asset(kind: .sample, path: path.path, name: "New", format: "wav", bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    let saved = try await f.store.ingest(f.report([asset]), scope: scopeA, at: Date(timeIntervalSince1970: 40), additionContext: context(scopeA, 30))
    #expect(saved.observations.values.first?.addition?.basis == .presentBy)
    let link = a.appendingPathComponent("pretend:file:identity.wav")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
    let weak = Asset(kind: .sample, path: link.path, name: "Weak", format: "wav", bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    let weakScan = try await f.store.ingest(f.report([asset, weak]), scope: scopeA, at: Date(timeIntervalSince1970: 60), additionContext: context(scopeA, 50))
    let weakID = try #require(weakScan.report.assets.first { $0.path == link.path }?.catalogID)
    #expect(weakScan.observations[weakID]?.addition?.basis == .presentBy)
}

@Test func frozenSchemaThreeMigrationAndFailurePreserveOriginalEvidence() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures/catalog-v3.sql")
    for conflict in [false, true] {
        let f = try StoreFixture(); defer { f.clean() }
        try FileManager.default.createDirectory(at: f.database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.sql(String(contentsOf: fixture, encoding: .utf8))
        let event = storedDateEvent("legacy")
        let payload = String(decoding: try JSONEncoder().encode(event), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
        try f.sql("INSERT INTO nodes VALUES('legacy','identity','product','plugin','/fixture/Plugin',100,200,1); INSERT INTO date_evidence VALUES('fixture','event','legacy','\(payload)');")
        if conflict {
            try f.sql("CREATE TABLE node_addition_bounds(sentinel TEXT); INSERT INTO node_addition_bounds VALUES('preserved');")
            await #expect(throws: CatalogStoreError.self) { try await f.store.load(scope: f.scope) }
            #expect(try f.scalar("PRAGMA user_version") == "3")
            #expect(try f.scalar("SELECT sentinel FROM node_addition_bounds") == "preserved")
            #expect(try f.scalar("SELECT count(*) FROM sqlite_master WHERE name='scan_coverage'") == "0")
        } else {
            #expect(try await f.store.dateEvidence(for: "legacy", asOf: evidenceNow) == [event])
            #expect(try f.scalar("PRAGMA user_version") == "5")
        }
    }
}

@Test func additionCorruptionFailsClosedAndZeroWidthArrivalStaysObserved() async throws {
    let f = try StoreFixture(); defer { f.clean() }
    let path = try f.file("Library.nicnt")
    _ = try await f.store.ingest(f.report([f.asset(path)]), scope: f.scope)
    try f.sql("UPDATE node_addition_bounds SET payload=payload || char(0) || 'trailing';")
    await #expect(throws: CatalogStoreError.self) { try await f.store.load(scope: f.scope) }
    let point = Date(timeIntervalSince1970: 100)
    let arrival = try AdditionDateEvidence(basis: .observedArrival, lower: point, upper: point)
    #expect(try AdditionDateEvidence.group([arrival])?.basis == .observedArrival)
}
