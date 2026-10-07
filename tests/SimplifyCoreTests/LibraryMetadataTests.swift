import Foundation
import Testing
import CSQLite
@testable import SimplifyCore

@Test func actualVendorFormatLayoutsGroupWithoutMergingPublishers() {
    let ids = ["com.arturia.component.Acid-V", "com.Arturia.Acid-V.vst3", "com.arturia.aax.Acid-V", "com.Arturia.Acid-V.vst"]
    let assets = zip(ids, ["component", "vst3", "aaxplugin", "vst"]).map { id, ext in
        Asset(kind: .plugin, path: "/Plugins/Acid V.\(ext)", name: "Acid V", format: ext, bundleIdentifier: id, logicalBytes: nil, classification: "fixture")
    }
    #expect(PluginProduct.group(assets).count == 1)
    #expect(PluginProduct.group(assets)[0].installations.count == 4)
    let other = Asset(kind: .plugin, path: "/Other/Acid V.vst3", name: "Acid V", format: "vst3", bundleIdentifier: "com.other.Acid-V.vst3", logicalBytes: nil, classification: "fixture")
    #expect(PluginProduct.group(assets + [other]).count == 2)
}
@Test func kontaktManifestRejectsMalformedOversizedAndEntityXML() {
    let xml = "<ProductHints><Product><Name>Example Folk</Name><Company>Example Audio</Company></Product></ProductHints>"
    #expect(LibraryMetadataReader.parseKontaktManifest(Data(xml.utf8))?.name == "Example Folk")
    let extended = xml.replacingOccurrences(of: "</ProductHints>", with: String(repeating: " ", count: 180_000) + "</ProductHints>")
    #expect(LibraryMetadataReader.parseKontaktManifest(Data(extended.utf8))?.name == "Example Folk")
    #expect(LibraryMetadataReader.parseKontaktManifest(Data(("<!DOCTYPE x [<!ENTITY a SYSTEM 'file:///etc/passwd'>]>" + xml).utf8)) == nil)
    #expect(LibraryMetadataReader.parseKontaktManifest(Data(repeating: 65, count: 65_537)) == nil)
    #expect(LibraryMetadataReader.parseKontaktManifest(Data("<ProductHints>broken".utf8)) == nil)
}
@Test func sineCatalogRequiresScopedPhysicalContent() throws {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
    let scope = root.appendingPathComponent("Content"); try fm.createDirectory(at: scope, withIntermediateDirectories: true)
    let valid = scope.appendingPathComponent("Accordion.otmeta"); try Data("fixture".utf8).write(to: valid)
    try Data("fixture".utf8).write(to: valid.deletingPathExtension().appendingPathExtension("otarc"))
    let outside = root.appendingPathComponent("Banjo.otmeta"); try Data("fixture".utf8).write(to: outside)
    let link = scope.appendingPathComponent("Linked.otmeta"); try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    var db: OpaquePointer?; let file = root.appendingPathComponent("catalog.db")
    #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
    let schema = """
    CREATE TABLE t_collection(collection_key,collection_id,title,subtitle,developer,keywords);
    CREATE TABLE t_instrument(instrument_key,instrument_collection,instrument_id,title,keywords);
    CREATE TABLE t_micPosition(micposition_instrument,filePath);
    CREATE TABLE t_articulation(articulation_key,articulation_instrument,articulation_id,title,kind,hidden);
    INSERT INTO t_collection VALUES(1,'folk','Folk Collection','Acoustic instruments','Example','folk');
    INSERT INTO t_instrument VALUES(1,1,'accordion','Accordion','accordion'),(2,1,'banjo','Banjo','banjo');
    INSERT INTO t_articulation VALUES(1,1,'long','Long Harmonics','single',0),
      (2,1,'secret','Secret','single',1),(3,1,'unsupported','Unsupported','multi',0),
      (4,2,'foreign','Foreign','single',0),(5,999,'orphan','Orphan','single',0),
      (6,1,'poly','Reverb XF CC','poly',0);
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    for path in [valid.path + "/virtual.otmf", outside.path + "/virtual.otmf", link.path + "/virtual.otmf", scope.appendingPathComponent("Missing.otmeta").path + "/virtual.otmf"] {
        var stmt: OpaquePointer?; sqlite3_prepare_v2(db,"INSERT INTO t_micPosition VALUES(1,?)",-1,&stmt,nil)
        path.withCString { string in
            sqlite3_bind_text(stmt,1,string,-1,nil); _ = sqlite3_step(stmt)
        }; sqlite3_finalize(stmt)
    }
    sqlite3_close(db)
    var issues: [ScanIssue] = []
    let result = LibraryMetadataReader.sine(file, roots: [scope], issues: &issues)
    #expect(issues.isEmpty && result.count == 1)
    #expect(result.first?.logicalBytes == 14)
    #expect(result.first?.libraryMetadata?.sizeBasis == .installedContent)
    #expect(result.first?.libraryMetadata?.sharedLogicalBytes == 0)
    #expect(result.first?.libraryMetadata?.sizeSourceFingerprint != nil)
    #expect(result.first?.libraryMetadata?.instruments.count == 1)
    #expect(result.first?.libraryMetadata?.instruments[0].articulations == [
        LibraryArticulation(id: "long", name: "Long Harmonics", source: "SINE local catalog"),
        LibraryArticulation(id: "poly", name: "Reverb XF CC", source: "SINE local catalog")
    ])
    #expect(result.first?.libraryMetadata?.searchText.contains("Accordion") == true)
    #expect(result.first?.libraryMetadata?.searchText.contains("Banjo") == false)
    #expect(LibraryMetadataReader.sine(file, roots: [root.appendingPathComponent("Unrelated")], issues: &issues).isEmpty)
    var changedDB: OpaquePointer?
    #expect(sqlite3_open(file.path, &changedDB) == SQLITE_OK)
    #expect(sqlite3_exec(changedDB, "DROP TABLE t_articulation", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(changedDB)
    issues = []
    let unsupported = LibraryMetadataReader.sine(file, roots: [scope], issues: &issues)
    #expect(unsupported.first?.libraryMetadata?.instruments.count == 1)
    #expect(unsupported.first?.logicalBytes == 14)
    #expect(unsupported.first?.libraryMetadata?.instruments[0].articulations.isEmpty == true)
    #expect(issues.contains { $0.reason.contains("articulation catalog schema is unsupported") })
}
@Test func oldLibraryInstrumentPayloadDecodesWithoutArticulations() throws {
    var patch = LibraryInstrument(name: "Celli", path: "/synthetic/Celli.nki", tags: ["Cello"])
    patch.catalogStale = true
    let encoded = try JSONEncoder().encode(patch)
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "articulations")
    let restored = try JSONDecoder().decode(LibraryInstrument.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(restored.articulations.isEmpty && restored.catalogStale == true && restored.path == patch.path)
    patch.articulations = [LibraryArticulation(id: "long", name: "Long Harmonics", source: "SINE local catalog")]
    #expect(try JSONDecoder().decode(LibraryInstrument.self, from: JSONEncoder().encode(patch)).articulations == patch.articulations)
}

@Test func physicalSINEPairsRemainVisibleWithoutInventedCatalogIdentity() throws {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    let content = root.appendingPathComponent("Content")
    try fm.createDirectory(at: content.appendingPathComponent("Copy"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    func pair(_ relative: String) throws -> URL {
        let file = content.appendingPathComponent(relative).appendingPathExtension("otmeta")
        try Data(repeating: 1, count: 7).write(to: file)
        try Data(repeating: 2, count: 11).write(to: file.deletingPathExtension().appendingPathExtension("otarc"))
        return file
    }
    let claimed = try pair("Shared")
    let unclaimed = try pair("Copy/Shared")
    var request = ScanRequest(); request.libraries = [content]
    let dbURL = root.appendingPathComponent("SINE.db")
    let journal = root.appendingPathComponent("catalog.sqlite")
    var missingIssues: [ScanIssue] = []
    let missing = LibraryDiscovery.scan(request, sineDatabase: dbURL, journalBaseURL: journal, issues: &missingIssues)
    #expect(missing.count == 1)
    #expect(missingIssues.contains { $0.reason.contains("SINE catalog unavailable") })
    #expect(missing.allSatisfy { $0.libraryMetadata?.identity?.productID == nil && $0.libraryMetadata?.instruments.isEmpty == true && $0.logicalBytes == 36 })
    #expect(missing.first?.libraryMetadata?.physicalContentPaths?.count == 4)

    var db: OpaquePointer?
    #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let schema = """
    CREATE TABLE t_collection(collection_key,collection_id,title,subtitle,developer,keywords);
    CREATE TABLE t_instrument(instrument_key,instrument_collection,instrument_id,title,keywords);
    CREATE TABLE t_micPosition(micposition_instrument,filePath);
    CREATE TABLE t_articulation(articulation_key,articulation_instrument,articulation_id,title,kind,hidden);
    INSERT INTO t_collection VALUES(1,'owned','Owned','','Orchestral Tools','');
    INSERT INTO t_instrument VALUES(1,1,'patch','Patch','');
    INSERT INTO t_micPosition VALUES(1,'\(claimed.path)/virtual.otmf');
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    var issues: [ScanIssue] = []
    let reconciled = LibraryDiscovery.scan(request, sineDatabase: dbURL, journalBaseURL: journal, issues: &issues)
    #expect(issues.isEmpty)
    #expect(reconciled.count == 2)
    #expect(reconciled.first { $0.libraryMetadata?.identity?.productID == "sine:collection:owned" }?.libraryMetadata?.instruments.count == 1)
    let orphan = try #require(reconciled.first { $0.classification == "unassociatedPhysicalContent" })
    #expect(orphan.name == "Content" && orphan.libraryMetadata?.identity?.productID == nil)
    #expect(orphan.logicalBytes == 18 && orphan.libraryMetadata?.sizeBasis == .unassociatedContent)
    #expect(orphan.libraryMetadata?.physicalContentPaths == [unclaimed.path, unclaimed.deletingPathExtension().appendingPathExtension("otarc").path].sorted())
    var resumedIssues: [ScanIssue] = []
    let resumed = LibraryDiscovery.scan(request, sineDatabase: dbURL, journalBaseURL: journal, issues: &resumedIssues)
    #expect(resumedIssues.isEmpty && Set(resumed.map(\.path)) == Set(reconciled.map(\.path)))
}

@Test func missingOrLinkedSINEArchiveDoesNotBecomeCompleteContent() throws {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let missing = root.appendingPathComponent("Missing.otmeta")
    let linked = root.appendingPathComponent("Linked.otmeta")
    try Data([1]).write(to: missing)
    try Data([1]).write(to: linked)
    let linkedArchive = root.appendingPathComponent("Linked.otarc")
    try fm.createSymbolicLink(at: linkedArchive, withDestinationURL: missing)
    var request = ScanRequest(); request.libraries = [root]
    var issues: [ScanIssue] = []
    let assets = LibraryDiscovery.scan(request, sineDatabase: root.appendingPathComponent("Missing.db"), issues: &issues)
    #expect(assets.filter { $0.classification == "unassociatedPhysicalContent" }.isEmpty)
    #expect(issues.filter { $0.reason.contains("no stable regular archive pair") }.count == 2)
}
@Test func abletonPluginDescriptorsExcludeTrackAndPresetNames() throws {
    let xml = "<Ableton><LiveSet><Tracks><MidiTrack><Name Value='Misleading'/><DeviceChain><Devices><PluginDevice><PluginDesc><VstPluginInfo><PlugName Value='Example Echo'/><Preset><PlugName Value='Not a plugin'/></Preset></VstPluginInfo></PluginDesc></PluginDevice></Devices></DeviceChain></MidiTrack></Tracks></LiveSet></Ableton>"
    let references = try ProjectReader.parseAbleton(Data(xml.utf8))
    #expect(references.filter { $0.kind == .plugin }.map(\.value) == ["Example Echo"])
}

@Test func libraryRootFailuresAndNestedDepthRecoveryAreVisible() throws {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    let nested = root.appendingPathComponent("A/B")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
    try Data().write(to: nested.appendingPathComponent("Banjo.nki"))
    var request = ScanRequest(); request.libraryScanMode = .boundedDiagnostic; request.maximumDepth = 1
    request.libraries = [root, nested, root.appendingPathComponent("Missing")]
    let report = Scanner().scan(request)
    #expect(report.assets.flatMap { $0.libraryMetadata?.instruments ?? [] }.count == 1)
    #expect(report.assets.contains { $0.libraryMetadata?.searchText.contains("Banjo") == true })
    #expect(report.issues.contains { $0.path.hasSuffix("Missing") })
    #expect(report.issues.contains { $0.reason.contains("depth limit") })
    request.maximumDepth = 64; request.libraries = [root, nested]
    let overlap = Scanner().scan(request)
    #expect(overlap.assets.flatMap { $0.libraryMetadata?.instruments ?? [] }.count == 1)
}
@Test func metadataSpecialFilesAndOversizedPartsAreRejected() throws {
    let fm = FileManager.default
    let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
    let pipe = root.appendingPathComponent("catalog.db")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    var issues: [ScanIssue] = []
    #expect(LibraryMetadataReader.sine(pipe, roots: [root], issues: &issues).isEmpty)
    #expect(!issues.isEmpty)
    #expect(LibraryMetadataReader.kontaktManifest(pipe) == nil)
    let large = root.appendingPathComponent("info.json")
    try Data(repeating: 32, count: LibraryMetadataReader.maximumMetadataBytes + 1).write(to: large)
    #expect(LibraryMetadataReader.soundpaintPart(large) == nil)
}
