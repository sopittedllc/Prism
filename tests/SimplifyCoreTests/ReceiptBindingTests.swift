import Foundation
import Testing
import CSQLite
@testable import SimplifyCore

func receiptAsset(_ bundle: URL, identifier: String = "dev.example.instrument", format: String? = nil, kind: AssetKind = .plugin) -> Asset {
    Asset(kind: kind, path: bundle.path, name: "Fixture", format: format ?? bundle.pathExtension.lowercased(),
          bundleIdentifier: identifier, logicalBytes: nil, classification: "fixture")
}
func receiptReport(_ assets: [Asset]) -> ScanReport {
    ScanReport(schemaVersion: 1, assets: assets, projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
}
func receiptScope(_ root: URL) -> CatalogScope {
    var request = ScanRequest(); request.plugins = [root]; return CatalogScope(request)
}
private func receiptSQL(_ url: URL, _ sql: String) throws {
    var db: OpaquePointer?; defer { sqlite3_close(db) }
    guard sqlite3_open(url.path, &db) == SQLITE_OK,
          sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogStoreError.invalid }
}

@Test func receiptBindingPersistsReplaysAndBacksUpWithoutPromotingUseOrAddition() async throws {
    let f = try ReceiptFixture(), scope = receiptScope(f.root)
    let db = f.root.appendingPathComponent("Private/catalog.sqlite"), now = f.now
    let store = CatalogStore(url: db)
    let snapshot = try await store.ingest(receiptReport([receiptAsset(f.bundle)]), scope: scope)
    let node = try #require(snapshot.report.assets.first?.catalogID)
    let first = try await store.recordPackageReceipt(f.observe(), for: node, at: now)
    let later = now.addingTimeInterval(100)
    let replay = try await CatalogStore(url: db).recordPackageReceipt(f.observe(), for: node, at: later)
    #expect(first == replay && replay.ingestedAt == now)
    #expect(first.packageReceipt?.bundleIdentifier == "dev.example.instrument")
    #expect(try await store.dateEvidence(for: node, asOf: later) == [first])
    var updated = f.receipt; updated["install-time"] = 600
    let next = try await store.recordPackageReceipt(f.observe(receipt: updated), for: node, at: later)
    #expect(next.evidenceID != first.evidenceID)
    let summary = try await store.dateSummary(for: node, asOf: later)
    #expect(summary.latestRecordedInstallation == Date(timeIntervalSince1970: 600))
    #expect(summary.dateAdded == nil && summary.lastUsed == nil && summary.firstDiscovered == nil)
    let backup = f.root.appendingPathComponent("Backup/catalog.sqlite")
    try await store.backup(to: backup)
    #expect(try await CatalogStore(url: backup).dateEvidence(for: node, asOf: later).count == 2)
    #expect(try await CatalogStore(url: backup).dateSummary(for: node, asOf: later) == summary)
    #expect(try await CatalogStore(url: backup).dateEvidence(for: node, asOf: later).contains(first))
}

@Test func receiptBindingRejectsIdentityHeaderRemovalAndUnavailableInputs() async throws {
    for problem in ["absent", "format", "id", "path", "weak", "removed", "missing", "replaced", "changed", "tie", "kind", "freshReplacement"] {
        let f = try ReceiptFixture(), scope = receiptScope(f.root)
        let db = f.root.appendingPathComponent("Private/catalog.sqlite"), store = CatalogStore(url: db)
        let asset = receiptAsset(f.bundle, identifier: problem == "id" ? "different" : "dev.example.instrument",
                                 format: problem == "format" ? "vst3" : nil, kind: problem == "kind" ? .sample : .plugin)
        let snapshot = try await store.ingest(receiptReport([asset]), scope: scope, at: f.now)
        let node = try #require(snapshot.report.assets.first?.catalogID)
        var token = try f.observe()
        switch problem {
        case "path": try receiptSQL(db, "UPDATE nodes SET path='wrong'")
        case "weak": try receiptSQL(db, "UPDATE nodes SET identity='plugin:component::path:weak'")
        case "removed": try await store.recordRemovalIntent(paths: [f.bundle.path])
        case "missing": try FileManager.default.removeItem(at: f.executable)
        case "replaced", "freshReplacement":
            try FileManager.default.moveItem(at: f.bundle, to: f.root.appendingPathComponent("Old.component"))
            try FileManager.default.createDirectory(at: f.executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("replacement".utf8).write(to: f.executable); try f.writeInfo()
            if problem == "freshReplacement" { token = try f.observe() }
        case "changed": try f.writeInfo(version: "new")
        case "tie":
            let other = receiptAsset(f.bundle, identifier: "conflict")
            _ = try await store.ingest(receiptReport([other]), scope: receiptScope(f.bundle), at: f.now)
        default: break
        }
        do {
            _ = try await store.recordPackageReceipt(token, for: problem == "absent" ? "absent" : node, at: f.now)
            Issue.record("Unexpected receipt attachment: \(problem)")
        } catch {}
        #expect(try await store.dateEvidence(for: node, asOf: f.now).isEmpty)
    }
}

@Test func receiptBindingRejectsUnassociatedAndFutureObservationsBeforeCreatingDatabase() async throws {
    let f = try ReceiptFixture(), db = f.root.appendingPathComponent("Uncreated/catalog.sqlite")
    let store = CatalogStore(url: db)
    for token in [try f.observe(files: Data()), try f.observe()] {
        await #expect(throws: CatalogStoreError.self) {
            try await store.recordPackageReceipt(token, for: "node", at: f.now.addingTimeInterval(-1))
        }
    }
    var mismatch = f.receipt; mismatch["pkg-version"] = "different"
    await #expect(throws: CatalogStoreError.self) {
        try await store.recordPackageReceipt(f.observe(receipt: mismatch), for: "node", at: f.now)
    }
    #expect(!FileManager.default.fileExists(atPath: db.path))
}

@Test func receiptBindingRollsBackPostInsertMutationAndWriteFailure() async throws {
    let f = try ReceiptFixture(), db = f.root.appendingPathComponent("Private/catalog.sqlite")
    let store = CatalogStore(url: db)
    let snapshot = try await store.ingest(receiptReport([receiptAsset(f.bundle)]), scope: receiptScope(f.root))
    let node = try #require(snapshot.report.assets.first?.catalogID), token = try f.observe()
    await #expect(throws: PackageReceiptError.self) {
        try await store.recordPackageReceipt(token, for: node, at: f.now) { try f.writeInfo(version: "changed") }
    }
    #expect(try await store.dateEvidence(for: node, asOf: f.now).isEmpty)
    try f.writeInfo()
    try receiptSQL(db, "CREATE TRIGGER reject_receipt BEFORE INSERT ON date_evidence BEGIN SELECT RAISE(ABORT,'fixture'); END")
    await #expect(throws: CatalogStoreError.self) { try await store.recordPackageReceipt(f.observe(), for: node, at: f.now) }
    #expect(try await store.dateEvidence(for: node, asOf: f.now).isEmpty)
}

@Test func receiptProvenanceUsesStableByteExactIdentityAndLegacyCompatibleEncoding() throws {
    let provenance = PackageReceiptProvenance(packageID: "pkg", packageVersion: "1", bundlePath: "/Unit.component",
                                             bundleIdentifier: "unit", bundleVersions: ["1", "10"])
    #expect(try provenance.eventID(subjectID: "node", date: Date(timeIntervalSince1970: 500)) == "eb72361d0525ea484c04875ce1e877931c987c2ee85e4a9d71d0cc90532b7a87")
    let record = AssetDateEvidence(sourceID: PackageReceiptProvenance.sourceID, evidenceID: "event", subjectID: "node",
        kind: .installationRecord, eventDate: Date(timeIntervalSince1970: 500), ingestedAt: Date(timeIntervalSince1970: 1000), packageReceipt: provenance)
    #expect(try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(record)) == record)
    let legacy = Data(#"{"sourceID":"fixture","evidenceID":"event","subjectID":"node","kind":"confirmedUse","eventDate":100,"ingestedAt":200}"#.utf8)
    #expect(try JSONDecoder().decode(AssetDateEvidence.self, from: legacy).packageReceipt == nil)
    func entry(source: String = PackageReceiptProvenance.sourceID, kind: AssetDateEvidenceKind = .installationRecord,
               date: Date? = Date(timeIntervalSince1970: 500), details: PackageReceiptProvenance?) -> AssetDateEvidence {
        AssetDateEvidence(sourceID: source, evidenceID: "event", subjectID: "node", kind: kind,
                          eventDate: date, ingestedAt: record.ingestedAt, packageReceipt: details)
    }
    let badVersions = PackageReceiptProvenance(packageID: "pkg", packageVersion: "2", bundlePath: "/Unit.component", bundleIdentifier: "unit", bundleVersions: ["1"])
    for bad in [entry(details: nil), entry(source: "other", details: provenance), entry(kind: .confirmedUse, details: provenance),
                entry(date: nil, details: provenance), entry(details: badVersions)] {
        #expect(throws: AssetDateEvidenceError.invalidProvenance) {
            try AssetDateResolver.summarize([bad], for: "node", asOf: record.ingestedAt)
        }
    }
    let composed = PackageReceiptProvenance(packageID: "é", packageVersion: "1", bundlePath: "/Unit.component", bundleIdentifier: "unit", bundleVersions: ["1"])
    let decomposed = PackageReceiptProvenance(packageID: "e\u{301}", packageVersion: "1", bundlePath: "/Unit.component", bundleIdentifier: "unit", bundleVersions: ["1"])
    #expect(composed != decomposed)
}

/// Opt-in reads installed bundles/receipts only; all catalog writes use a disposable fixture.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PRISM_RECEIPT_BINDING_RUNTIME"] == "1"))
func nativeReceiptBindingRuntime() async throws {
    let f = try ReceiptFixture(), db = f.root.appendingPathComponent("Native/catalog.sqlite")
    let root = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components")
    let cases: [(String, String, PackageReceiptStatus)] = [
        ("com.fabfilter.Pro-Q.AU.4", "FabFilter Pro-Q 4.component", .associated),
        ("com.native-instruments.Kontakt8.AU", "Kontakt 8.component", .associated),
        ("com.u-he.Diva.au.pkg", "Diva.component", .versionMismatch)
    ]
    for (package, name, expected) in cases {
        let bundle = root.appendingPathComponent(name)
        let token = try PackageReceiptReader.observe(packageID: package, bundle: bundle)
        #expect(token.report.status == expected)
        let store = CatalogStore(url: db), now = Date()
        let snapshot = try await store.ingest(receiptReport([receiptAsset(bundle, identifier: token.report.bundleIdentifier)]), scope: receiptScope(root))
        let node = try #require(snapshot.report.assets.first(where: { $0.path == bundle.path })?.catalogID)
        if expected == .associated {
            let record = try await store.recordPackageReceipt(token, for: node, at: now)
            let replay = try await CatalogStore(url: db).recordPackageReceipt(PackageReceiptReader.observe(packageID: package, bundle: bundle), for: node, at: Date())
            #expect(record == replay && record.packageReceipt?.packageID == package)
            let summary = try await store.dateSummary(for: node, asOf: Date())
            #expect(summary.latestRecordedInstallation == token.report.receiptDate && summary.lastUsed == nil && summary.dateAdded == nil)
            #expect(try await store.dateEvidence(for: node, asOf: Date()).count == 1)
        } else {
            await #expect(throws: CatalogStoreError.self) { try await store.recordPackageReceipt(token, for: node, at: now) }
            #expect(try await store.dateEvidence(for: node, asOf: Date()).isEmpty)
        }
        try token.revalidate()
    }
}
