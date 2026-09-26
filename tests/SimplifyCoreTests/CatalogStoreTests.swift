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

@Test func newlyIndexedScopeHasItsOwnBaselineAndPartialMembersRemainVisible() async throws {
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
    #expect(baseline.observations.values.first?.baseline == true)
    #expect(try await f.store.load(scope: f.scope)?.observations.values.first?.baseline == false)
    asset.libraryMetadata?.instruments[0].contentPaths = ["/fixture/Close.otarc"]
    let partial = try await f.store.ingest(f.report([asset], partial: true), scope: f.scope)
    let instrument = try #require(partial.report.assets.first?.libraryMetadata?.instruments.first)
    #expect(instrument.contentPaths == ["/fixture/Close.otarc", "/fixture/Room.otarc"])
    #expect(instrument.contentMembers?.first { $0.path.contains("Room") }?.stale == true)
    #expect(instrument.contentMembers?.first { $0.path.contains("Close") }?.stale == false)
    #expect(try await f.store.load(scope: other)?.report.assets.first?.libraryMetadata?.instruments.first?.contentMembers?.allSatisfy { !$0.stale } == true)
}
