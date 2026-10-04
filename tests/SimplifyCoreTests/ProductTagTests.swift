import Foundation
import Testing
@testable import SimplifyCore

private func source(_ format: ProductTagSource.Format = .shopify, body: String = "Reviewed string section with legato.") -> ProductTagSource {
    ProductTagSource(id: "fixture", kind: .library, names: ["Example Strings"], makers: ["Example Audio"], bundlePrefix: nil,
        endpoint: URL(string: "https://example.com/product.json")!, page: URL(string: "https://example.com/product")!,
        format: format, remoteName: "Example Strings", descriptionDigest: ProductTagSource.digest(body),
        metadata: MusicalMetadata(fields: ["instrument": ["strings"], "technique": ["legato"]]))
}
private func shopify(_ name: String = "Example Strings", _ body: String = "Reviewed string section with legato.") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["product": ["title": name, "body_html": body, "tags": "LoadDate_2026,Source,brass"]])
}
@Test func reviewedProductTagsRejectChangedIdentityAndMeaning() throws {
    let s = source()
    #expect(try s.parse(shopify()).sourceID == "fixture")
    #expect(throws: Error.self) { try s.parse(shopify("Example Strings Lite")) }
    for text in ["Does not include legato.", "Related product: string section with legato.", "Bundle includes another legato library.", "<nav>Strings Legato</nav>"] {
        #expect(throws: Error.self) { try s.parse(shopify("Example Strings", text)) }
    }
    #expect(s.metadata[.instrument] == ["strings"]) // Administrative vendor tags never enter taxonomy.
    #expect(throws: Error.self) { try s.parse(Data(repeating: 65, count: ProductTagClient.maximumBytes + 1)) }
    #expect(throws: Error.self) { try s.parse(Data("bad json".utf8)) }
}
@Test func structuredProductDescriptionExcludesRelatedProducts() throws {
    let s = source(.productJSONLD)
    let objects: [[String: Any]] = [
        ["@type": "Product", "name": "Other Product", "description": "brass percussion"],
        ["@type": "Product", "name": "Example Strings", "description": "Reviewed string section with legato."]
    ]
    let data = try JSONSerialization.data(withJSONObject: objects)
    let html = Data(("<nav>accordion</nav><script type=\"application/ld+json\">" + String(decoding: data, as: UTF8.self) + "</script>").utf8)
    #expect(try s.parse(html).sourceID == "fixture")
    let duplicate = Data((String(decoding: html, as: UTF8.self) + String(decoding: html, as: UTF8.self)).utf8)
    #expect(throws: Error.self) { try s.parse(duplicate) }
}
@Test func productTagsRequireExactMakerAndEdition() throws {
    var asset = Asset(kind: .library, path: "/fixture", name: "Example Strings", format: "Kontakt", bundleIdentifier: nil, logicalBytes: nil, classification: "manifest")
    asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Other Audio", summary: "", instruments: [], tags: [], source: "fixture")
    #expect(!source().matches(asset))
    asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Example Audio", summary: "", instruments: [], tags: [], source: "fixture")
    #expect(source().matches(asset))
    let now = Date()
    #expect(ProductTagRecord(sourceID: "fixture", descriptionDigest: "x", fetchedAt: now).isFresh(at: now))
    #expect(!ProductTagRecord(sourceID: "fixture", descriptionDigest: "x", fetchedAt: now.addingTimeInterval(1)).isFresh(at: now))
    #expect(!ProductTagRecord(sourceID: "fixture", descriptionDigest: "x", fetchedAt: now.addingTimeInterval(-7 * 86400)).isFresh(at: now))
}

@Test func productTagCacheRoundTripAndFutureVersionPreservation() async throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTagTests/" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("tags.json"), store = ProductTagStore(url: root.appendingPathComponent("tags.json"))
    let source = try #require(ProductTagSources.all.first)
    let record = ProductTagRecord(sourceID: source.id, descriptionDigest: source.descriptionDigest, fetchedAt: Date())
    try await store.save([source.id: record])
    #expect(try await store.load()[source.id] == record)
    let obsolete = ProductTagRecord(sourceID: source.id, descriptionDigest: String(repeating: "0", count: 64), fetchedAt: Date())
    let recordJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(obsolete))
    try JSONSerialization.data(withJSONObject: ["version": 1, "records": [recordJSON]]).write(to: url)
    #expect(try await store.load().isEmpty)
    try await store.save([source.id: record])
    #expect(try await store.load()[source.id] == record)
    let future = Data(#"{"version":99,"records":[]}"#.utf8); try future.write(to: url)
    await #expect(throws: Error.self) { try await store.save([source.id: record]) }
    #expect(try Data(contentsOf: url) == future)
}
