import Foundation
import Testing
@testable import SimplifyCore

private func automaticFixture(host: String = "www.fabfilter.com", name: String = "Fixture Compressor") -> [String: Any] {
    ["id": "automatic-fixture-compressor", "kind": "plugin", "names": [name], "makers": ["FabFilter"],
     "bundlePrefix": NSNull(), "endpoint": "https://\(host)/products/pro-c-2-compressor-plug-in",
     "page": "https://\(host)/products/pro-c-2-compressor-plug-in", "format": "metaDescription",
     "remoteName": name, "descriptionDigest": "", "networkEnabled": false,
     "metadata": ["function": ["compressor"]], "reviewRecordID": "automatic-fixture-compressor",
     "reviewedAt": "2026-10-06", "taxonomyVersion": 1,
     "sourceFact": "Synthetic unit-test metadata; no vendor claim is published.", "provenance": "automatic"]
}

private func sharedEnvelope(_ record: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["version": 2, "records": [], "automaticRecords": [record]])
}

@Test func sharedCatalogAdmitsKnownOfficialDomainAndRejectsUntrustedAutomaticFacts() throws {
    let trusted = try ProductTagSources.importSharedCatalog(sharedEnvelope(automaticFixture()))
    #expect(trusted.count == 1 && trusted[0].provenance == .automatic)
    #expect(throws: (any Error).self) {
        try ProductTagSources.importSharedCatalog(sharedEnvelope(automaticFixture(host: "untrusted.example")))
    }
    var edited = automaticFixture(); edited["provenance"] = "curated"
    #expect(throws: (any Error).self) { try ProductTagSources.importSharedCatalog(sharedEnvelope(edited)) }
}

@Test func sharedCatalogCachePersistsLastGoodAndRejectsInvalidReplacement() async throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SharedProductTagStore(url: root.appendingPathComponent("shared.json"))
    let valid = SharedProductTagSnapshot(catalogData: try sharedEnvelope(automaticFixture()), etag: "\"v1\"")
    try await store.save(valid)
    #expect(try await store.load().catalogData == valid.catalogData)
    var rejectedReplacement = false
    do {
        try await store.save(SharedProductTagSnapshot(catalogData: Data("bad".utf8), etag: "\"v2\""))
    } catch { rejectedReplacement = true }
    #expect(rejectedReplacement)
    #expect(try await store.load().etag == "\"v1\"")

    var paddedCatalog = valid.catalogData!
    paddedCatalog.append(Data(repeating: 0x20, count: 3 * 1_024 * 1_024 - paddedCatalog.count))
    var paddedIdentity = try sharedEnvelope(automaticFixture())
    paddedIdentity.append(Data(repeating: 0x20, count: 2 * 1_024 * 1_024 - paddedIdentity.count))
    let oversized = SharedProductTagSnapshot(catalogData: paddedCatalog, etag: "\"v2\"",
        identifiedRecords: ["automatic-fixture-compressor": paddedIdentity])
    var rejectedOversizedEncoding = false
    do { try await store.save(oversized) } catch { rejectedOversizedEncoding = true }
    #expect(rejectedOversizedEncoding)
    #expect(try await store.load().etag == "\"v1\"")
}
