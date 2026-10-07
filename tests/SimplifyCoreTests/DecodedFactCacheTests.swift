import Foundation
import Testing
import CSQLite
@testable import SimplifyCore

private final class FactFixture {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyFactTests/" + UUID().uuidString)
    let base: URL
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        base = root.appendingPathComponent("catalog.sqlite")
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func write(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
}

@Test func warmLibraryDiscoverySkipsUnchangedAdapterReadsAndReparsesOnlyEditedManifest() throws {
    let f = try FactFixture()
    let first = try f.write("Libraries/First/First.nicnt",
        "<ProductHints><Product><Name>First</Name><Company>Maker</Company></Product></ProductHints>")
    _ = try f.write("Libraries/First/Instruments/Piano.nki", "fixture")
    _ = try f.write("Libraries/Second/Second.nicnt",
        "<ProductHints><Product><Name>Second</Name><Company>Maker</Company></Product></ProductHints>")
    _ = try f.write("Libraries/Second/Instruments/Strings.nki", "fixture")
    _ = try f.write("Libraries/Painted/libraryInfo.lib", "fixture")
    _ = try f.write("Libraries/Painted/Parts/Part/info.json", "{\"name\":\"Part\",\"tagging\":{\"family\":[\"Piano\"]}}")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let cache = try #require(DecodedFactCache(baseURL: f.base))
    let missingSINE = f.root.appendingPathComponent("absent-sine.db")
    func scan() -> [Asset] {
        var issues: [ScanIssue] = []
        return LibraryDiscovery.scan(request, sineDatabase: missingSINE, cache: cache, issues: &issues)
    }
    let cold = scan()
    #expect(cold.count == 3)
    #expect(cache.readsByPolicy["kontakt-manifest-v1"] == 2)
    #expect(cache.readsByPolicy["soundpaint-part-v1"] == 1)
    let warm = scan()
    #expect(Set(cold.map(\.selectionKey)) == Set(warm.map(\.selectionKey)))
    #expect(cache.readsByPolicy["kontakt-manifest-v1"] == 2)
    #expect(cache.readsByPolicy["soundpaint-part-v1"] == 1)
    #expect(cache.hitsByPolicy["kontakt-manifest-v1"] == 2)
    #expect(cache.hitsByPolicy["soundpaint-part-v1"] == 1)
    try Data("<ProductHints><Product><Name>First Revised</Name><Company>Maker</Company></Product></ProductHints>".utf8).write(to: first)
    let changed = scan()
    #expect(changed.contains { $0.name == "First Revised" })
    #expect(cache.readsByPolicy["kontakt-manifest-v1"] == 3)
    #expect(cache.readsByPolicy["soundpaint-part-v1"] == 1)
}

@Test func cachedSINERowsStillRequireCurrentPhysicalArchive() throws {
    let f = try FactFixture()
    let metadata = try f.write("Content/Accordion.otmeta", "metadata")
    let archive = metadata.deletingPathExtension().appendingPathExtension("otarc")
    let database = f.root.appendingPathComponent("sine.db")
    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    let schema = """
    CREATE TABLE t_collection(collection_key,collection_id,title,subtitle,developer,keywords);
    CREATE TABLE t_instrument(instrument_key,instrument_collection,instrument_id,title,keywords);
    CREATE TABLE t_micPosition(micposition_instrument,filePath);
    CREATE TABLE t_articulation(articulation_key,articulation_instrument,articulation_id,title,kind,hidden);
    INSERT INTO t_collection VALUES(1,'folk','Folk','','Maker','');
    INSERT INTO t_instrument VALUES(1,1,'accordion','Accordion','');
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "INSERT INTO t_micPosition VALUES(1,?)", -1, &statement, nil) == SQLITE_OK)
    (metadata.path + "/virtual.otmf").withCString { path in
        sqlite3_bind_text(statement, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        #expect(sqlite3_step(statement) == SQLITE_DONE)
    }
    sqlite3_finalize(statement); sqlite3_close(db)
    let cache = try #require(DecodedFactCache(baseURL: f.base))
    var issues: [ScanIssue] = []
    let scope = [f.root.appendingPathComponent("Content")]
    #expect(LibraryMetadataReader.sine(database, roots: scope, cache: cache, issues: &issues).isEmpty)
    #expect(cache.readsByPolicy["sine-rows-v1"] == 1)
    try Data("archive".utf8).write(to: archive)
    #expect(LibraryMetadataReader.sine(database, roots: scope, cache: cache, issues: &issues).count == 1)
    #expect(cache.hitsByPolicy["sine-rows-v1"] == 1)
    try FileManager.default.removeItem(at: archive)
    #expect(LibraryMetadataReader.sine(database, roots: scope, cache: cache, issues: &issues).isEmpty)
    #expect(cache.readsByPolicy["sine-rows-v1"] == 1)
}

@Test func factoryAndVST3DescriptorsReuseDecodedFactsAndFollowPreferredFileChanges() throws {
    let f = try FactFixture()
    let productRoot = f.root.appendingPathComponent("Omnisphere")
    _ = try f.write("Omnisphere/Settings Library/Patches/Factory/Factory.db",
        "<FileSystem><FILE name=\"Piano.prt_omn\"/></FileSystem>")
    let player = Asset(kind: .library, path: productRoot.path, name: "Omnisphere",
        format: "Spectrasonics", bundleIdentifier: nil, logicalBytes: nil,
        classification: "needsIdentification")
    let cache = try #require(DecodedFactCache(baseURL: f.base))
    var issues: [ScanIssue] = []
    let cold = SpectrasonicsLibraryIndex.discover(products: [player], cache: cache, issues: &issues)
    #expect(cold.first?.libraryMetadata?.instruments.first?.name == "Piano")
    #expect(SpectrasonicsLibraryIndex.discover(products: [player], cache: cache, issues: &issues).count == 1)
    #expect(cache.readsByPolicy["spectrasonics-factory-v1:Omnisphere:prt_omn"] == 1)
    #expect(cache.hitsByPolicy["spectrasonics-factory-v1:Omnisphere:prt_omn"] == 1)

    let bundle = f.root.appendingPathComponent("Example.vst3")
    _ = try f.write("Example.vst3/Contents/moduleinfo.json",
        "{\"Classes\":[{\"Category\":\"Audio Module Class\",\"Sub Categories\":[\"Fx\"]}]}")
    let plugin = Asset(kind: .plugin, path: bundle.path, name: "Example", format: "vst3",
        bundleIdentifier: nil, logicalBytes: nil, classification: "pluginBundleCandidate")
    #expect(VST3ModuleInfoReader.read(bundle: bundle)?.subCategories == ["fx"])
    #expect(VST3ModuleInfoReader.enrich([plugin], cache: cache)[0].vst3Categories?.subCategories == ["fx"])
    #expect(VST3ModuleInfoReader.enrich([plugin], cache: cache)[0].vst3Categories?.subCategories == ["fx"])
    #expect(cache.readsByPolicy["vst3-module-v1"] == 1)
    #expect(cache.hitsByPolicy["vst3-module-v1"] == 1)
    _ = try f.write("Example.vst3/Contents/Resources/moduleinfo.json",
        "{\"Classes\":[{\"Category\":\"Audio Module Class\",\"Sub Categories\":[\"Synth\"]}]}")
    #expect(VST3ModuleInfoReader.enrich([plugin], cache: cache)[0].vst3Categories?.subCategories == ["synth"])
    #expect(cache.readsByPolicy["vst3-module-v1"] == 2)
}

@Test func decodedFactsReuseOnlyUnchangedSuccessfulSources() throws {
    let f = try FactFixture()
    let first = try f.write("First.json", "first")
    let second = try f.write("Second.json", "second")
    let cache = try #require(DecodedFactCache(baseURL: f.base))
    var reads = 0
    func read(_ url: URL) -> String? {
        cache.value(policy: "fixture-v1", paths: [url]) {
            reads += 1
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }
    #expect(read(first) == "first")
    #expect(read(second) == "second")
    #expect(reads == 2)
    #expect(read(first) == "first")
    #expect(read(second) == "second")
    #expect(reads == 2)
    _ = try f.write("First.json", "first edited")
    #expect(read(first) == "first edited")
    #expect(read(second) == "second")
    #expect(reads == 3)
}

@Test func decodedFactsTrackAbsentAddedEditedAndRemovedSidecars() throws {
    let f = try FactFixture()
    let source = try f.write("catalog.db", "catalog")
    let sidecar = f.root.appendingPathComponent("catalog.db-wal")
    let cache = try #require(DecodedFactCache(baseURL: f.base))
    var reads = 0
    func read() -> String? {
        cache.value(policy: "database-v1", paths: [source, sidecar]) {
            reads += 1
            guard let text = try? String(contentsOf: source, encoding: .utf8) else { return nil }
            return text + (FileManager.default.fileExists(atPath: sidecar.path) ? ":wal" : ":plain")
        }
    }
    #expect(read() == "catalog:plain")
    #expect(read() == "catalog:plain")
    #expect(reads == 1)
    _ = try f.write("catalog.db-wal", "one")
    #expect(read() == "catalog:wal")
    _ = try f.write("catalog.db-wal", "two edited")
    #expect(read() == "catalog:wal")
    try FileManager.default.removeItem(at: sidecar)
    #expect(read() == "catalog:plain")
    #expect(reads == 4)
}

@Test func decodedFactsRejectChangedDuringReadAndRecoverFromCorruption() throws {
    let f = try FactFixture()
    let source = try f.write("source", "before")
    let cache = try #require(DecodedFactCache(baseURL: f.base))
    let raced: String? = cache.value(policy: "race-v1", paths: [source]) {
        try? Data("after edit".utf8).write(to: source)
        return "before"
    }
    #expect(raced == nil)
    var reads = 0
    let current: String? = cache.value(policy: "race-v1", paths: [source]) {
        reads += 1; return "after edit"
    }
    #expect(current == "after edit")
    #expect(reads == 1)
    #expect(cache.value(policy: "race-v1", paths: [source], read: { reads += 1; return "wrong" }) == "after edit")
    #expect(reads == 1)
    let cacheURL = DecodedFactCache.location(baseURL: f.base)
    try Data("damaged database".utf8).write(to: cacheURL)
    #expect(DecodedFactCache(baseURL: f.base) == nil)
}
