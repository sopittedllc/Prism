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
    INSERT INTO t_collection VALUES(1,'folk','Folk Collection','Acoustic instruments','Example','folk');
    INSERT INTO t_instrument VALUES(1,1,'accordion','Accordion','accordion'),(2,1,'banjo','Banjo','banjo');
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
    #expect(result.first?.libraryMetadata?.instruments.count == 1)
    #expect(result.first?.libraryMetadata?.searchText.contains("Accordion") == true)
    #expect(result.first?.libraryMetadata?.searchText.contains("Banjo") == false)
    #expect(LibraryMetadataReader.sine(file, roots: [root.appendingPathComponent("Unrelated")], issues: &issues).isEmpty)
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
    var request = ScanRequest(); request.maximumDepth = 1
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
