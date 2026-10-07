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
@Test func bundledProductTagRecordsHaveVersionedReviewProvenance() throws {
    #expect(ProductTagSources.catalogVersion == 2)
    for source in ProductTagSources.all {
        try source.validateReviewRecord()
        #expect(source.reviewRecordID == source.id && source.taxonomyVersion == 1)
    }
    let family = MusicalMetadata.suggested(name: "Brass Synth", tags: ["strings"], kind: .library,
        suppressInstrumentFamilyGuess: true)
    #expect(family[.instrument] == nil)
    let nucleus = try #require(ProductTagSources.all.first { $0.id == "audio-imperia-nucleus-lite" })
    let gladeStudio = try #require(ProductTagSources.all.first { $0.id == "audio-imperia-glade-studio" })
    #expect(!nucleus.networkEnabled && nucleus.metadata[.instrument]?.contains("strings") == true)
    #expect(gladeStudio.names == ["Glade Studio"] && gladeStudio.makers == ["Audio Imperia"])
    #expect(throws: ProductTagError.invalidCache) {
        try ProductTagSources.importReviewedCatalog(Data(#"{"version":99,"records":[]}"#.utf8))
    }
}
@Test func bundledCatalogHasCanonicalFunctionsAndMergedFormatAliases() throws {
    let oldFunctionSpellings: Set<String> = ["equalizer", "saturation", "distortion", "synthesis", "pitch shifting", "vocal", "mixing"]
    for source in ProductTagSources.all {
        #expect(Set(source.metadata[.function] ?? []).isDisjoint(with: oldFunctionSpellings))
    }
    let little = try #require(ProductTagSources.all.first { $0.id == "soundtoys-little-alterboy" })
    #expect(little.names.contains("LittleAlterBoy"))
    #expect(little.metadata[.function] == ["pitch shift/harmonizer", "vocal processing"])
    #expect(ProductTagSources.all.first { $0.id == "external-p-9640216ff252" } == nil)
}
@Test func bundledCatalogRejectsSpacelessDuplicateWithinKindAndMaker() throws {
    let base = try #require(JSONSerialization.jsonObject(with: ProductTagSources.bundledCatalogData()) as? [String: Any])
    let original = try #require((base["records"] as? [[String: Any]])?.first)
    var duplicate = original
    duplicate["id"] = "duplicate-format-alias"; duplicate["reviewRecordID"] = "duplicate-format-alias"
    duplicate["names"] = ["SpitfireSymphonyOrchestra"]
    let rejected = try JSONSerialization.data(withJSONObject: ["version": 2, "records": [original, duplicate]])
    #expect(throws: ProductTagError.invalidCache) { try ProductTagSources.importReviewedCatalog(rejected) }
    duplicate["kind"] = "plugin"
    let distinctKind = try JSONSerialization.data(withJSONObject: ["version": 2, "records": [original, duplicate]])
    #expect(try ProductTagSources.importReviewedCatalog(distinctKind).count == 2)
}
@Test func productTagMatchingKeepsPluginAndLibraryIdentitiesSeparate() throws {
    let plugin = ProductTagSource(id: "keyscape-plugin", kind: .plugin, names: ["Keyscape"], makers: ["Spectrasonics"], bundlePrefix: nil,
        endpoint: URL(string: "https://example.com/keyscape")!, page: URL(string: "https://example.com/keyscape")!, format: .metaDescription,
        remoteName: "Keyscape", descriptionDigest: "", metadata: MusicalMetadata(fields: ["instrument": ["piano"]]), networkEnabled: false)
    let library = ProductTagSource(id: "keyscape-library", kind: .library, names: ["Keyscape"], makers: ["Spectrasonics"], bundlePrefix: nil,
        endpoint: URL(string: "https://example.com/keyscape")!, page: URL(string: "https://example.com/keyscape")!, format: .metaDescription,
        remoteName: "Keyscape", descriptionDigest: "", metadata: MusicalMetadata(fields: ["instrument": ["piano"]]), networkEnabled: false)
    var binary = Asset(kind: .plugin, path: "/fixtures/Keyscape.vst3", name: "Keyscape", format: "vst3", bundleIdentifier: nil,
        logicalBytes: nil, classification: "plugin")
    binary.vst3Categories = VST3CategoryMetadata(subCategories: [], metadata: MusicalMetadata(), vendor: "Spectrasonics")
    var content = Asset(kind: .library, path: "/fixtures/Keyscape", name: "Keyscape", format: "Kontakt", bundleIdentifier: nil,
        logicalBytes: nil, classification: "library")
    content.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Spectrasonics", summary: "", instruments: [], tags: [], source: "fixture")
    #expect(plugin.matches(binary) && !plugin.matches(content))
    #expect(library.matches(content) && !library.matches(binary))
}
@Test func reviewedCatalogAdmitsFourHundredWithoutSilentTruncation() throws {
    let base = try #require(JSONSerialization.jsonObject(with: ProductTagSources.bundledCatalogData()) as? [String: Any])
    let sample = try #require((base["records"] as? [[String: Any]])?.first)
    let records = (0..<400).map { index -> [String: Any] in
        var value = sample
        value["id"] = "fixture-\(index)"; value["reviewRecordID"] = "fixture-\(index)"
        value["names"] = ["Fixture \(index)"]
        return value
    }
    let data = try JSONSerialization.data(withJSONObject: ["version": ProductTagSources.catalogVersion, "records": records])
    #expect(try ProductTagSources.importReviewedCatalog(data).count == 400)
}
@Test func bundledLibrarySectionsDoNotMatchBareSameMakerFolderNames() throws {
    let alienDrum = try #require(ProductTagSources.all.first { $0.id == "external-li-b231602d510b" })
    let adagio = try #require(ProductTagSources.all.first { $0.id == "external-li-e4b25566aa63" })
    func library(_ name: String) -> Asset {
        var asset = Asset(kind: .library, path: "/fixtures/Libraries/8Dio/" + name,
            name: name, format: "Kontakt", bundleIdentifier: nil,
            logicalBytes: nil, classification: "library")
        asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "8Dio", summary: "",
            instruments: [], tags: [], source: "fixture",
            identity: LibraryIdentity(evidence: .manifest, productID: nil, installationRoot: asset.path))
        return asset
    }
    #expect(!alienDrum.matches(library("Instruments")))
    #expect(!adagio.matches(library("MULTIS")))
    #expect(alienDrum.matches(library("8Dio Alien Drum — Instruments")))
}
@Test func makerQualifiedPluginRequiresExactLocalVendorAndEdition() throws {
    let reviewed = ProductTagSource(id: "vendor-synth", kind: .plugin, names: ["Super Synth"], makers: ["Example Audio"], bundlePrefix: nil,
        endpoint: URL(string: "https://example.com/synth")!, page: URL(string: "https://example.com/synth")!,
        format: .metaDescription, remoteName: "Super Synth", descriptionDigest: "", metadata: MusicalMetadata(fields: ["instrument": ["synth"]]), networkEnabled: false)
    var asset = Asset(kind: .plugin, path: "/synthetic/Super Synth.vst3", name: "Super Synth", format: "vst3",
        bundleIdentifier: "com.unknown.supersynth", logicalBytes: nil, classification: "plugin")
    #expect(!reviewed.matches(asset))
    asset.vst3Categories = VST3CategoryMetadata(subCategories: [], metadata: MusicalMetadata(), vendor: "Example Audio")
    #expect(reviewed.matches(asset))
    var lite = Asset(kind: .plugin, path: "/synthetic/Super Synth Lite.vst3", name: "Super Synth Lite", format: "vst3",
        bundleIdentifier: "com.unknown.supersynthlite", logicalBytes: nil, classification: "plugin")
    lite.vst3Categories = asset.vst3Categories
    #expect(!reviewed.matches(lite))
    asset.vst3Categories = VST3CategoryMetadata(subCategories: [], metadata: MusicalMetadata(), vendor: "Other Audio")
    #expect(!reviewed.matches(asset))
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

@Test func reviewedLibraryMayUseExactPackageMakerEvidence() throws {
    let reviewed = ProductTagSource(id: "maker-piano", kind: .library,
        names: ["Example Piano", "Example Audio - Example Piano"], makers: ["Example Audio"], bundlePrefix: nil,
        endpoint: URL(string: "https://example.com/piano")!, page: URL(string: "https://example.com/piano")!,
        format: .metaDescription, remoteName: "Example Piano", descriptionDigest: "",
        metadata: MusicalMetadata(fields: ["instrument": ["piano"]]), networkEnabled: false)
    func library(_ path: String, _ name: String, evidence: LibraryIdentity.Evidence = .proposed) -> Asset {
        var asset = Asset(kind: .library, path: path, name: name, format: "Kontakt", bundleIdentifier: nil,
            logicalBytes: nil, classification: "needsIdentification")
        asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Unknown maker", summary: "",
            instruments: [], tags: [], source: "fixture",
            identity: LibraryIdentity(evidence: evidence, productID: nil, installationRoot: path))
        return asset
    }
    let roots = [URL(fileURLWithPath: "/fixtures/Libraries")]
    #expect(reviewed.matches(library("/fixtures/Libraries/Example Audio/Example Piano", "Example Piano"), libraryRoots: roots))
    #expect(reviewed.matches(library("/fixtures/Libraries/Mixed/Example Audio - Example Piano", "Example Audio - Example Piano"), libraryRoots: roots))
    #expect(!reviewed.matches(library("/fixtures/Outside/Example Audio/Example Piano", "Example Piano"), libraryRoots: roots))
    #expect(!reviewed.matches(library("/fixtures/Libraries/Example Audio/Example Piano Lite", "Example Piano Lite"), libraryRoots: roots))
    #expect(!reviewed.matches(library("/fixtures/Libraries/Example Audio/Example Piano", "Example Piano", evidence: .manifest), libraryRoots: roots))
    #expect(!reviewed.matches(library("/fixtures/Libraries/Example Audio Fake/Example Piano", "Example Piano"), libraryRoots: roots))
}

@Test func reviewedPluginBundlePrefixRequiresExactNamespaceAndProductName() throws {
    let reviewed = ProductTagSource(id: "arturia-pigments", kind: .plugin, names: ["Pigments"], makers: ["Arturia"],
        bundlePrefix: "com.arturia", endpoint: URL(string: "https://example.com/pigments")!,
        page: URL(string: "https://example.com/pigments")!, format: .metaDescription, remoteName: "Pigments",
        descriptionDigest: "", metadata: MusicalMetadata(fields: ["instrument": ["synth"]]), networkEnabled: false)
    let exact = Asset(kind: .plugin, path: "/fixtures/Pigments.vst3", name: "Pigments", format: "vst3",
        bundleIdentifier: "com.Arturia.Pigments.vst3", logicalBytes: nil, classification: "plugin")
    #expect(reviewed.matches(exact))
    let wrongVendor = Asset(kind: .plugin, path: "/fixtures/Pigments.vst3", name: "Pigments", format: "vst3",
        bundleIdentifier: "com.arturiaFake.Pigments.vst3", logicalBytes: nil, classification: "plugin")
    #expect(!reviewed.matches(wrongVendor))
    let wrongEdition = Asset(kind: .plugin, path: "/fixtures/Pigments Lite.vst3", name: "Pigments Lite", format: "vst3",
        bundleIdentifier: "com.Arturia.Pigments.vst3", logicalBytes: nil, classification: "plugin")
    #expect(!reviewed.matches(wrongEdition))
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
    try await store.markFailure(source.id)
    #expect(try await ProductTagStore(url: url).recentFailures()[source.id] != nil)
    try await store.save([source.id: record])
    #expect(try await store.recentFailures().isEmpty)
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
