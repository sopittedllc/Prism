import Foundation
import Testing
import CSQLite
@testable import SimplifyCore

private func usageSQL(_ url: URL, _ sql: String) throws {
    var db: OpaquePointer?; defer { sqlite3_close(db) }
    guard sqlite3_open(url.path, &db) == SQLITE_OK, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
}
private func usageEvent(_ cid: String, qualification: String = HostUsageProvenance.completedDocumentRestore,
                        localTime: String = "2026-09-26T12:00:00.000000",
                        recordHash: String = String(repeating: "b", count: 64)) throws -> HostUsageProvenance {
    HostUsageProvenance(hostVersion: "12.4.6", classID: cid, pluginVersion: "1.0",
        localTime: try SourceLocalTime(localTime), runHash: String(repeating: "a", count: 64),
        recordHash: recordHash, recordOffset: 100, qualification: qualification)
}
@Test func liveBindingsRejectCollisionsStalenessAndReplacementsAndReplayHistory() async throws {
    let f = try ReceiptFixture()
    let bundle = f.root.appendingPathComponent("Unit.vst3")
    try FileManager.default.copyItem(at: f.bundle, to: bundle)
    let store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let snapshot = try await store.ingest(receiptReport([receiptAsset(bundle)]), scope: receiptScope(f.root))
    let id = try #require(snapshot.report.assets.first?.catalogID)
    let info = try PackageReceiptReader.readBundle(bundle), stamp = info.stamps[2]
    let cid = "12345678-1234-5678-ABCD-123456789ABC"
    let fingerprint = String(stamp.size, radix: 16) + ":" + String(stamp.times[2], radix: 16)
    let entry = LivePluginCache.Entry(classID: cid, path: bundle.path, version: "1.0", fingerprint: fingerprint)
    #expect(try LivePluginCache.bindings([entry, entry], assets: snapshot.report.assets).isEmpty)
    #expect(try LivePluginCache.bindings([.init(classID: cid, path: bundle.path, version: "1.0", fingerprint: "stale")], assets: snapshot.report.assets).isEmpty)
    #expect(throws: CatalogStoreError.self) { try LivePluginCache.bindings([entry], assets: snapshot.report.assets, deadline: 0) }
    let binding = try #require(LivePluginCache.bindings([entry], assets: snapshot.report.assets).first)
    let event = try usageEvent(cid), now = Date()
    let first = try await store.recordHostUsage(event, binding: binding, for: id, at: now)
    #expect(first.hostUsage?.subjectScope == "pluginClass" && first.eventDate == nil)
    let replay = try await CatalogStore(url: store.url).recordHostUsage(event, binding: binding, for: id, at: now.addingTimeInterval(10))
    #expect(first == replay)
    #expect(try await store.latestHostUsage(for: [id], asOf: now.addingTimeInterval(20))[Data(id.utf8)] == first)
    let restoreID = try event.eventID(subjectID: id)
    let manual = try #require((0..<256).compactMap { value -> HostUsageProvenance? in
        let hash = String(format: "%064x", value)
        guard let candidate = try? usageEvent(cid, qualification: HostUsageProvenance.completedManualCreate,
                                              localTime: "2026-09-26T12:00:30.000000", recordHash: hash),
              let candidateID = try? candidate.eventID(subjectID: id),
              candidateID.utf8.lexicographicallyPrecedes(restoreID.utf8) else { return nil }
        return candidate
    }.first)
    let manualID = try manual.eventID(subjectID: id)
    #expect(manualID.utf8.lexicographicallyPrecedes(restoreID.utf8))
    let manualFirst = try await store.recordHostUsage(manual, binding: binding, for: id, at: now.addingTimeInterval(20))
    #expect(manualFirst.sourceID == HostUsageProvenance.manualCreateSourceID)
    #expect(manualFirst.hostUsage?.eventSourceID == HostUsageProvenance.manualCreateSourceID)
    let manualReplay = try await CatalogStore(url: store.url).recordHostUsage(
        manual, binding: binding, for: id, at: now.addingTimeInterval(30))
    #expect(manualReplay == manualFirst)
    let mixed = try await CatalogStore(url: store.url).dateEvidence(for: id, asOf: now.addingTimeInterval(40))
    #expect(mixed.count == 2)
    #expect(Set(mixed.map(\.sourceID)) == Set([HostUsageProvenance.sourceID, HostUsageProvenance.manualCreateSourceID]))
    #expect(mixed.contains { $0.hostUsage?.qualification == HostUsageProvenance.completedDocumentRestore })
    #expect(mixed.contains { $0.hostUsage?.qualification == HostUsageProvenance.completedManualCreate })
    #expect(try await CatalogStore(url: store.url).latestHostUsage(for: [id], asOf: now.addingTimeInterval(40))[Data(id.utf8)] == manualFirst)

    // Host-local clocks cannot order one another. The stable family tie-break keeps the
    // merged result deterministic without comparing Cubase's UTC time to Live wall time.
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let cubaseDate = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12)))
    let cubase = CubasePluginUse(name: "Fixture", vendor: "Example", version: "1.0", architecture: "arm64",
        eventID: "cubase-mixed-clock-fixture", projectID: "project-fixture",
        reportedMilliseconds: Int64(cubaseDate.timeIntervalSince1970 * 1_000))
    let cubaseRecord = AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: cubase.eventID,
        subjectID: id, kind: .confirmedUse, eventDate: cubase.reportedDate, ingestedAt: now.addingTimeInterval(35), cubaseUsage: cubase)
    try await CatalogStore(url: store.url).appendDateEvidence([cubaseRecord], asOf: now.addingTimeInterval(35))
    let crossHostLatest = try await CatalogStore(url: store.url).latestHostUsage(for: [id], asOf: now.addingTimeInterval(40))[Data(id.utf8)]
    #expect(crossHostLatest == manualFirst)
    await #expect(throws: CatalogStoreError.self) { try await store.recordHostUsage(event, binding: binding, for: id, at: now, deadline: 0) }
    try FileManager.default.moveItem(at: bundle, to: f.root.appendingPathComponent("Old.vst3"))
    try FileManager.default.copyItem(at: f.bundle, to: bundle)
    await #expect(throws: Error.self) { try await store.recordHostUsage(event, binding: binding, for: id, at: now) }
    #expect(try await store.dateEvidence(for: id, asOf: now.addingTimeInterval(40)).count == 3)
}

@Test func liveCacheValidatesSchemaExactClassAndByteText() throws {
    let f = try ReceiptFixture(), db = f.root.appendingPathComponent("cache.sqlite")
    try usageSQL(db, """
        CREATE TABLE version(version INTEGER,platform INTEGER); INSERT INTO version VALUES(1,2);
        CREATE TABLE plugin_modules(module_id INTEGER,path TEXT,fingerprint TEXT,scanstate INTEGER);
        CREATE TABLE plugins(module_id INTEGER,dev_identifier TEXT,version TEXT,enabled INTEGER,scanstate INTEGER);
        INSERT INTO plugin_modules VALUES(1,'/fixtures/Unit.vst3','1:2',1);
        INSERT INTO plugins VALUES(1,'device:vst3:instr:12345678-1234-5678-abcd-123456789abc','1.0',1,1);
        """)
    let entries = try LivePluginCache.read(db)
    #expect(entries.count == 1 && entries[0].classID == "12345678-1234-5678-ABCD-123456789ABC")
    #expect(throws: CatalogStoreError.self) { try LivePluginCache.read(db, deadline: 0) }
    try usageSQL(db, "UPDATE version SET version=2")
    #expect(throws: CatalogStoreError.self) { try LivePluginCache.read(db) }
    try usageSQL(db, "UPDATE version SET version=1; UPDATE plugins SET dev_identifier=CAST(x'ff' AS TEXT)")
    // A non-VST3 row is not an eligible class association.
    #expect(try LivePluginCache.read(db).isEmpty)
    try usageSQL(db, "UPDATE plugins SET dev_identifier='device:vst3:instr:invalid'")
    #expect(throws: CatalogStoreError.self) { try LivePluginCache.read(db) }
}
