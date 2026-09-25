import Foundation
import Testing
import CSQLite
@testable import SimplifyCore

private struct LibraryFixture {
    let root: URL
    init() throws {
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func file(_ path: String, _ text: String = "fixture") throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func scan(_ extra: [URL] = []) -> ScanReport {
        var request = ScanRequest(); request.libraries = [root] + extra
        return Scanner().scan(request)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func kontaktPatchFoldersBelongToProposedProduct() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    try f.file("8Dio/8Dio - CAGE Winds/Instruments/01 Low Winds/Chaos.nki")
    try f.file("8Dio/8Dio - CAGE Winds/Instruments/02 High Winds/Textures.nki")
    try f.file("8Dio/8Dio - CAGE Winds/Samples/Payload.nkx")
    let report = f.scan([f.root.appendingPathComponent("8Dio/8Dio - CAGE Winds/Instruments")])
    let library = try #require(report.assets.first { $0.kind == .library })
    #expect(report.assets.count == 1)
    #expect(library.name == "8Dio - CAGE Winds")
    #expect(library.libraryMetadata?.instruments.count == 2)
    #expect(library.libraryMetadata?.identity?.evidence == .proposed)
    #expect(library.classification == "needsIdentification")
    #expect(library.logicalBytes == nil)
    #expect(library.libraryMetadata?.identity?.installationRoot == f.root.appendingPathComponent("8Dio/8Dio - CAGE Winds").path)
}

@Test func manifestOverridesProposalAndNeighborProductsStaySeparate() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    for product in ["Ark 2", "Ark 3"] {
        try f.file("\(product)/Instruments/Low Strings.nki")
        try f.file("\(product)/Samples/Payload.nkx")
        try f.file("\(product)/Identity.nicnt", "<ProductHints><Product><Name>\(product)</Name><Company>Example Audio</Company></Product></ProductHints>")
    }
    // A nested manifest is a new product even below an inherited product boundary.
    try f.file("Ark 2/Bonus/Bonus.nicnt", "<ProductHints><Product><Name>Bonus</Name></Product></ProductHints>")
    try f.file("Ark 2/Bonus/Accordion.nki")
    let report = f.scan()
    #expect(report.assets.map(\.name).sorted() == ["Ark 2", "Ark 3", "Bonus"])
    #expect(report.assets.allSatisfy { $0.libraryMetadata?.identity?.evidence == .manifest })
    #expect(report.assets.allSatisfy { $0.libraryMetadata?.instruments.count == 1 })
}

@Test func ambiguousManifestsCannotClaimPatchesAndScopeNeverClimbs() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    try f.file("Ambiguous/A.nicnt", "<ProductHints><Product><Name>A</Name></Product></ProductHints>")
    try f.file("Ambiguous/B.nicnt", "<ProductHints><Product><Name>B</Name></Product></ProductHints>")
    try f.file("Ambiguous/Instruments/Accordion.nki")
    try f.file("Ambiguous/Samples/Payload.nkx")
    let report = f.scan()
    #expect(report.issues.contains { $0.reason.contains("Multiple Kontakt manifests") })
    #expect(report.assets.count == 1)
    #expect(report.assets.first?.libraryMetadata?.identity?.evidence == .unresolved)
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Ambiguous/Instruments")]
    let narrow = Scanner().scan(request)
    #expect(narrow.assets.first?.libraryMetadata?.identity?.installationRoot == nil)
    #expect(narrow.assets.first?.name == "Instruments")
}

@Test func explicitSampleScopeAndLinkedPayloadDoNotCreateLibraryOwnership() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    try f.file("Product/Instruments/Banjo.nki")
    try f.file("Elsewhere/Audio.wav")
    try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("Product/Samples"), withDestinationURL: f.root.appendingPathComponent("Elsewhere"))
    #expect(f.scan().assets.first?.libraryMetadata?.identity?.evidence == .unresolved)
    var request = ScanRequest(); request.libraries = [f.root]; request.samples = [f.root.appendingPathComponent("Product")]
    #expect(Scanner().scan(request).assets.allSatisfy { $0.kind != .library })
}

@Test func inheritedTagsExcludeSiblingInstrumentsAndLegacyReportsDecode() throws {
    let json = """
    {"player":"Kontakt","maker":"Example Audio","summary":"","instruments":[
    {"name":"Piano","path":"/fixture/Piano.nki","tags":["Piano"]},
    {"name":"Low Strings","path":"/fixture/Strings.nki","tags":["Strings"]}],
    "tags":["Piano","Strings"],"source":"fixture"}
    """
    let metadata = try JSONDecoder().decode(LibraryMetadata.self, from: Data(json.utf8))
    #expect(metadata.identity == nil)
    #expect(metadata.instruments[0].vendorID == nil)
    #expect(metadata.instruments[0].contentPaths == nil)
    #expect(metadata.tags(for: metadata.instruments[0], productName: "Collection") == ["Collection", "Example Audio", "Piano"])
    #expect(metadata.searchText.contains("Strings"))
    let roundTrip = try JSONDecoder().decode(LibraryMetadata.self, from: JSONEncoder().encode(metadata))
    #expect(roundTrip.tags == metadata.tags)
}

@Test func sineAllMicrophonesAndStableVendorIdentity() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    for mic in ["Close", "Room"] {
        try f.file("Content/\(mic)/Strings.otmeta")
        try f.file("Content/\(mic)/Strings.otarc")
    }
    // Missing archive: this microphone must not be counted as installed.
    try f.file("Content/Missing/Strings.otmeta")
    let database = f.root.appendingPathComponent("catalog.db")
    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let schema = """
    CREATE TABLE t_collection(collection_key,collection_id,title,subtitle,developer,keywords);
    CREATE TABLE t_instrument(instrument_key,instrument_collection,instrument_id,title,keywords);
    CREATE TABLE t_micPosition(micposition_instrument,filePath);
    INSERT INTO t_collection VALUES(1,'ark2','Metropolis Ark 2','','Orchestral Tools',''),(2,'ark3','Metropolis Ark 3','','Orchestral Tools','');
    INSERT INTO t_instrument VALUES(1,1,'low','Low Strings','strings'),(2,2,'low','Low Strings','strings');
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    func insert(_ instrument: Int, _ mic: String) {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO t_micPosition VALUES(?,?)", -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(instrument))
        let path = f.root.appendingPathComponent("Content/\(mic)/Strings.otmeta/virtual.otmf").path
        path.withCString { ptr in
            sqlite3_bind_text(stmt, 2, ptr, -1, nil); #expect(sqlite3_step(stmt) == SQLITE_DONE)
        }
        sqlite3_finalize(stmt)
    }
    insert(1, "Room"); insert(1, "Close"); insert(1, "Close"); insert(1, "Missing"); insert(2, "Close")
    var issues: [ScanIssue] = []
    let roots = [f.root.appendingPathComponent("Content")]
    let first = LibraryMetadataReader.sine(database, roots: roots, issues: &issues)
    #expect(issues.isEmpty)
    #expect(first.count == 2)
    var request = ScanRequest(); request.libraries = roots
    let report = Scanner(sineDatabase: database).scan(request)
    #expect(report.assets.count == 2)
    #expect(Set(report.assets.map(\.selectionKey)).count == 2)
    let ark2 = try #require(first.first { $0.name == "Metropolis Ark 2" })
    let instrument = try #require(ark2.libraryMetadata?.instruments.first)
    #expect(instrument.contentPaths?.count == 4)
    #expect(instrument.vendorID == "sine:collection:ark2:instrument:low")
    #expect(ark2.libraryMetadata?.identity?.productID == "sine:collection:ark2")
    #expect(ark2.libraryMetadata?.identity?.installationRoot == nil)
    #expect(first[0].libraryMetadata?.instruments[0].vendorID != first[1].libraryMetadata?.instruments[0].vendorID)
    #expect(sqlite3_exec(db, "DELETE FROM t_micPosition", nil, nil, nil) == SQLITE_OK)
    insert(1, "Close"); insert(1, "Room"); insert(2, "Close")
    let second = LibraryMetadataReader.sine(database, roots: roots, issues: &issues)
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    #expect(try encoder.encode(first) == encoder.encode(second))
    // A mic disappears but logical product/instrument identity does not change.
    try FileManager.default.removeItem(at: f.root.appendingPathComponent("Content/Close/Strings.otarc"))
    let partial = LibraryMetadataReader.sine(database, roots: roots, issues: &issues)
    #expect(partial.count == 1)
    #expect(partial[0].libraryMetadata?.identity == ark2.libraryMetadata?.identity)
    #expect(partial[0].libraryMetadata?.instruments[0].vendorID == instrument.vendorID)
    #expect(partial[0].libraryMetadata?.instruments[0].contentPaths?.count == 2)
}

@Test func malformedNestedManifestNeverInheritsAuthoritativeOwner() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    try f.file("Parent/Parent.nicnt", "<ProductHints><Product><Name>Parent</Name></Product></ProductHints>")
    try f.file("Parent/Piano.nki")
    try f.file("Parent/Child/Broken.nicnt", "invalid")
    try f.file("Parent/Child/Instruments/Banjo.nki")
    let report = f.scan()
    let parent = try #require(report.assets.first { $0.name == "Parent" })
    #expect(parent.libraryMetadata?.instruments.map(\.name) == ["Piano"])
    let child = try #require(report.assets.first { $0.name == "Instruments" })
    #expect(child.libraryMetadata?.identity?.evidence == .unresolved)
    #expect(child.libraryMetadata?.instruments.map(\.name) == ["Banjo"])
}
