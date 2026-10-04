import Foundation
import Testing
@testable import SimplifyCatalog
@testable import SimplifyCore

private struct ProToolsNativeSnapshot: Decodable {
    let bytes: Int
    let sha256: String
}

private struct ProToolsNativeRestoreSummary: Decodable {
    struct HostRecord: Decodable { let record: String }
    let snapshots: [String: ProToolsNativeSnapshot]
    let sessionFileUnchanged: Bool
    let saved: Bool
    let manualInsertRecord: String
    let manualRemoveRecord: String
    let manualDeltaHasPutDocumentInfo: Bool
    let restoreHostRecords: [HostRecord]
    let knownStartupFailureLines: [Int]
}

@Test func nativeProToolsRestoreV2Runtime() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_PROTOOLS_RESTORE_V2_RUNTIME"] == "1" else { return }
    let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fixtureRoot = ProcessInfo.processInfo.environment["PRISM_PROTOOLS_RESTORE_FIXTURE_DIR"]
        .map { URL(fileURLWithPath: $0) }
        ?? project.appendingPathComponent("build/date-evidence/manual-protools")
    guard FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("runtime-control-summary.json").path) else {
        Issue.record("Native Pro Tools fixture unavailable; set PRISM_PROTOOLS_RESTORE_FIXTURE_DIR to the private capture directory.")
        return
    }
    let summaryData = try BoundedFile.read(fixtureRoot.appendingPathComponent("runtime-control-summary.json"), limit: 64 * 1024)
    let summary = try JSONDecoder().decode(ProToolsNativeRestoreSummary.self, from: summaryData)
    #expect(summary.sessionFileUnchanged && !summary.saved)
    #expect(summary.restoreHostRecords.count == 3)
    #expect(summary.restoreHostRecords.map(\.record).contains { $0.contains("name: \"FabFilter Pro-Q 4\"") })
    #expect(summary.restoreHostRecords.map(\.record).contains { $0.contains("name: \"Kontakt 8\"") })
    #expect(summary.restoreHostRecords.map(\.record).contains { $0.contains("name: \"Diva\"") })
    #expect(summary.manualInsertRecord.contains("Host InstantiatePlugIn FabFilter Pro-Q 4 Audio 2"))
    #expect(summary.manualRemoveRecord.contains("Host FreePlugIn FabFilter Pro-Q 4 Audio 2"))
    #expect(!summary.manualDeltaHasPutDocumentInfo)

    let snapshots = ["runtime-before.log", "runtime-after-insert.log", "runtime-after-remove.log"]
    var parsedByName: [String: [ProToolsPluginUse]] = [:]
    var dataByName: [String: Data] = [:]
    for name in snapshots {
        let data = try BoundedFile.read(fixtureRoot.appendingPathComponent(name), limit: ProToolsUsageLog.maximumBytes)
        dataByName[name] = data
        guard let expected = summary.snapshots[name] else {
            Issue.record("Missing immutable native snapshot metadata: \(name)")
            continue
        }
        #expect(data.count == expected.bytes)
        #expect(ProToolsPluginUse.digest(data) == expected.sha256)
        parsedByName[name] = try ProToolsUsageLog.parse(data)
    }

    let before = try #require(parsedByName["runtime-before.log"])
    let afterInsert = try #require(parsedByName["runtime-after-insert.log"])
    let afterRemove = try #require(parsedByName["runtime-after-remove.log"])
    let expectedNames = ["FabFilter Pro-Q 4", "Kontakt 8", "Diva"]
    #expect(before.map(\.name).sorted() == (expectedNames + ["AudioInjection PlugIn"]).sorted())
    #expect(before.filter { $0.name == "AudioInjection PlugIn" }.count == 1)
    #expect(before.allSatisfy { $0.eventSourceID == ProToolsPluginUse.restoreV2SourceID })
    #expect(before.allSatisfy { $0.localTime?.dayKey == "2026-10-03" && $0.reportedDate == nil })
    #expect(!before.contains { $0.name == "Glow" }) // earlier kCantInstantiatePlugIn is not use
    #expect(afterInsert == before && afterRemove == before) // Add/Free have no restore completion

    // Re-run production exact-name binding against current installed AAX inventory, but
    // stage captured logs under a private synthetic home so no live log or user catalog is touched.
    let pluginRoot = URL(fileURLWithPath: "/Library/Application Support/Avid/Audio/Plug-Ins")
    var request = ScanRequest(); request.plugins = [pluginRoot]
    let scan = Scanner().scan(request, scannedKinds: [.plugin])
    let aaxAssets = scan.assets.filter { $0.kind == .plugin && $0.format == "aaxplugin" }
    for name in expectedNames {
        #expect(aaxAssets.filter { $0.name == name }.count == 1)
    }

    let privateHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/PrismProToolsV2Native-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: privateHome) }
    let logDirectory = privateHome.appendingPathComponent("Library/Logs/Avid")
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    for (index, name) in snapshots.enumerated() {
        try dataByName[name]!.write(to: logDirectory.appendingPathComponent(
            String(format: "Pro_Tools_2026_10_03_15_07_%02d.txt", index)))
    }

    let isolatedCatalog = privateHome.appendingPathComponent("Catalog/catalog.sqlite")
    let store = CatalogStore(url: isolatedCatalog)
    let snapshot = try await store.ingest(scan.replacingAssets(aaxAssets), scope: CatalogScope(request), scannedKinds: [.plugin])
    let collection = ProToolsUsageCollector.collect(assets: snapshot.report.assets, home: privateHome)
    // The host-internal AudioInjection restore candidate has no unique installed AAX
    // asset, so the production collector correctly leaves it unbound in each snapshot.
    #expect(collection.failures == snapshots.count)
    #expect(collection.uses.map { $0.use.name }.sorted() == expectedNames.sorted())
    #expect(!collection.uses.contains { $0.use.name == "AudioInjection PlugIn" })

    let now = Date(), later = now.addingTimeInterval(5)
    let reopened = CatalogStore(url: isolatedCatalog)
    for bound in collection.uses {
        let asset = try #require(snapshot.report.assets.first { $0.path == bound.pluginPath })
        let id = try #require(asset.catalogID)
        let saved = try await store.recordProToolsUsage(bound, for: id, at: now)
        #expect(saved.sourceID == ProToolsPluginUse.restoreV2SourceID)
        #expect(saved.eventDate == nil && saved.proToolsUsage?.eventSourceID == ProToolsPluginUse.restoreV2SourceID)
        let replay = try await reopened.recordProToolsUsage(bound, for: id, at: later)
        #expect(replay == saved)
        let history = try await CatalogStore(url: isolatedCatalog).latestHostUsage(for: [id], asOf: later)
        #expect(history[Data(id.utf8)] == saved)
        let presentation = UsageDatePresentation(record: saved)
        #expect(presentation.value == "2026-10-03\nPro Tools local")
        #expect(presentation.detail.contains("Pro Tools session restore"))
        #expect(presentation.detail.contains("time zone unknown"))
    }
}
