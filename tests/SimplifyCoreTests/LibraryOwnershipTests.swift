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
    #expect(library.logicalBytes == 21)
    #expect(library.libraryMetadata?.sizeBasis == .candidateFolder)
    #expect(library.libraryMetadata?.identity?.installationRoot == f.root.appendingPathComponent("8Dio/8Dio - CAGE Winds").path)
}

@Test func numberedPatchAndSampleFoldersUsePackageBoundary() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    try f.file("Westwood/Percussion Untamed/01 Instrument/Main.nki")
    try f.file("Westwood/Percussion Untamed/02 Samples/Payload.wav")
    try f.file("Karanyi/Polyscape/01 INSTRUMENTS/1 SINGLE MODULES/Lead.nki")
    try f.file("Karanyi/Polyscape/02 DATA/Samples/Payload.wav")
    let libraries = f.scan().assets.filter { $0.kind == .library }
    #expect(Set(libraries.map(\.name)) == ["Percussion Untamed", "Polyscape"])
    #expect(libraries.allSatisfy { $0.libraryMetadata?.identity?.evidence == .proposed })
    #expect(libraries.allSatisfy { $0.libraryMetadata?.instruments.count == 1 && $0.logicalBytes != nil })
}

@Test func directPatchOwnsSnapshotsAndCorePackagingStaysTogether() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    try f.file("Envoy/Envoy.nki")
    try f.file("Envoy/Samples/Payload.wav")
    try f.file("Envoy/Snapshots/01 OMNI/Preset.nksn")
    try f.file("8Dio - Mini/1_Click_Core_Library/Timebomb.nkm")
    try f.file("8Dio - Mini/1_Click_Core_Library/air_hammer/Bang.nki")
    try f.file("8Dio - Mini/2_Bonus_Ambiences/Ambience.wav")
    try f.file("Tonehammer - Epic Tom Ensemble/1_Epic_Toms_Core_Library/Toms.nki")
    try f.file("Tonehammer - Epic Tom Ensemble/2_Epic_Bass_Core_Library/Bass.nki")
    try f.file("Tonehammer - Epic Tom Ensemble/3_Bonus_Ambiences/Ambience.wav")
    let libraries = f.scan().assets.filter { $0.kind == .library }
    #expect(Set(libraries.map(\.name)) == ["Envoy", "8Dio - Mini", "Tonehammer - Epic Tom Ensemble"])
    #expect(libraries.first { $0.name == "Envoy" }?.libraryMetadata?.instruments.count == 2)
    #expect(libraries.first { $0.name == "8Dio - Mini" }?.libraryMetadata?.instruments.count == 2)
    #expect(libraries.first { $0.name == "Tonehammer - Epic Tom Ensemble" }?.libraryMetadata?.instruments.count == 2)
}

@Test func collectionContainerDoesNotInheritSeparateProductPatches() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    for name in ["Product A", "Product B"] {
        try f.file("Collection/\(name)/01 Instruments/Main.nki")
        try f.file("Collection/\(name)/02 Samples/Payload.wav")
    }
    try f.file("Another Collection/1_First_Core_Library/First.nki")
    try f.file("Another Collection/2_Second_Core_Library/Second.nki")
    try f.file("Another Collection/3_Readme/readme.txt")
    let libraries = f.scan().assets.filter { $0.kind == .library }
    #expect(libraries.filter { $0.path.contains("Collection/Product") }.map(\.name).sorted() == ["Product A", "Product B"])
    #expect(!libraries.contains { $0.name == "Collection" || $0.name == "Another Collection" })
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

@Test func nestedManifestBackupCannotReplaceOwningInstallation() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    let manifest = "<ProductHints><Product><Name>Rhythmic Aura Vol 1</Name><Company>8Dio</Company><SNPID>f979</SNPID></Product></ProductHints>"
    try f.file("Rhythmic Aura/Rhythmic Aura.nicnt", manifest)
    try f.file("Rhythmic Aura/Instruments/Pulse.nki")
    try f.file("Rhythmic Aura/Instruments/Texture.nki")
    try f.file("Rhythmic Aura/Samples/Payload.nkx")
    try f.file("Rhythmic Aura/Wallpaper & nicnt/Rhythmic Aura.nicnt", manifest)

    let libraries = f.scan().assets.filter { $0.kind == .library }
    let library = try #require(libraries.first)
    #expect(libraries.count == 1)
    #expect(library.path == f.root.appendingPathComponent("Rhythmic Aura/Rhythmic Aura.nicnt").path)
    #expect(library.libraryMetadata?.instruments.map(\.name).sorted() == ["Pulse", "Texture"])
    #expect((library.logicalBytes ?? 0) > 0)
    #expect(library.libraryMetadata?.sizeBasis == .fullInstallation)
}

@Test func separateInstallationsWithSameVendorProductRemainDistinct() throws {
    let f = try LibraryFixture(); defer { f.clean() }
    let manifest = "<ProductHints><Product><Name>Shared Product</Name><Company>Example</Company><SNPID>123</SNPID></Product></ProductHints>"
    for copy in ["Copy A", "Copy B"] {
        try f.file("\(copy)/Product.nicnt", manifest)
        try f.file("\(copy)/Instruments/\(copy).nki")
        try f.file("\(copy)/Samples/Payload.nkx")
    }
    let libraries = f.scan().assets.filter { $0.kind == .library }
    #expect(libraries.count == 2)
    #expect(Set(libraries.map(\.path)).count == 2)
    #expect(Set(libraries.map(\.selectionKey)).count == 2)
    #expect(Set(libraries.compactMap { $0.libraryMetadata?.identity?.productID }).count == 1)
    #expect(libraries.allSatisfy { $0.libraryMetadata?.instruments.count == 1 && ($0.logicalBytes ?? 0) > 0 })
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
    #expect((narrow.assets.first?.logicalBytes ?? 0) > 0)
    #expect(narrow.assets.first?.libraryMetadata?.sizeBasis == .candidateFolder)
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
    CREATE TABLE t_articulation(articulation_key,articulation_instrument,articulation_id,title,kind,hidden);
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
