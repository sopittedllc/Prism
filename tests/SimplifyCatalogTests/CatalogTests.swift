import Foundation
import CSQLite
import Darwin
import Testing
@testable import SimplifyCatalog
@testable import SimplifyCore

private final class CatalogFixture {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyCatalogTests/" + UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ path: String, _ value: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url); return url
    }
}

@MainActor private func finish(_ model: CatalogModel) async throws {
    let deadline = Date().addingTimeInterval(10)
    while model.isScanning && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!model.isScanning)
}

@Test @MainActor func defaultsRegistryAndResetAgree() throws {
    let model = CatalogModel()
    let defaults = model.stateSnapshot
    #expect(Set(defaults.keys) == Set(CatalogStateRegistry.definitions.compactMap { $0["id"] as? String }))
    for definition in CatalogStateRegistry.definitions {
        let id = try #require(definition["id"] as? String)
        let a = try JSONSerialization.data(withJSONObject: [defaults[id]!], options: [.sortedKeys])
        let b = try JSONSerialization.data(withJSONObject: [definition["default"]!], options: [.sortedKeys])
        #expect(a == b)
    }
    model.category = .library; model.query = "strings"; model.sort = .recency
    model.standardPlugins = false; model.selectedPath = "/fixture"
    model.addRoots([URL(fileURLWithPath: "/fixture")], kind: .samples)
    model.reset()
    #expect(try JSONSerialization.data(withJSONObject: model.stateSnapshot, options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: defaults, options: [.sortedKeys]))
    #expect(CatalogModel().roots.isEmpty) // New session never silently restores private paths.
}

@Test @MainActor func rootsAreDeduplicatedAndBusyEditsRejected() async throws {
    let f = try CatalogFixture()
    try f.file("kick.wav")
    let model = CatalogModel(); model.standardPlugins = false
    model.addRoots([f.root, f.root], kind: .samples)
    #expect(model.roots[.samples]?.count == 1)
    model.scan(); model.scan()
    model.addRoots([f.root], kind: .libraries)
    model.removeRoot(f.root, kind: .samples)
    #expect(model.roots[.libraries] == nil)
    #expect(model.roots[.samples]?.count == 1)
    try await finish(model)
    model.removeRoot(f.root, kind: .samples)
    #expect(model.configurationChanged)
    #expect(model.status.contains("Scan to update"))
    #expect(model.report?.assets.count == 1) // Old results remain until next scan.
}

@Test @MainActor func filteringSortingAndReferenceEvidence() async throws {
    let f = try CatalogFixture()
    let a = try f.file("Samples/Alpha.wav", "123456789")
    try f.file("Samples/Zebra.wav", "1")
    try f.file("Plugins/Test.vst3/Contents/marker")
    try f.file("Projects/Session.rpp", "<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE \"../Samples/Alpha.wav\"\n>\n>\n>\n>")
    try f.file("Projects/Other.cpr")
    let model = CatalogModel(); model.standardPlugins = false
    model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.addRoots([f.root.appendingPathComponent("Projects")], kind: .projects)
    model.scan(); try await finish(model)
    model.category = .sample
    #expect(model.visibleAssets.map(\.name) == ["Alpha", "Zebra"])
    model.sort = .size; #expect(model.visibleAssets.first?.name == "Alpha")
    model.sort = .recency; #expect(model.visibleAssets.first?.name == "Alpha")
    model.query = "ALPHA"; #expect(model.visibleAssets.count == 1)
    model.selectedPath = a.path
    #expect(model.detail.contains("Referencing projects:"))
    #expect(model.detail.contains("not when the sample was added or played"))
    #expect(model.coverageDetail.contains("unsupported"))
    model.query = "missing"; #expect(model.visibleAssets.isEmpty)
    model.query = ""; #expect(model.selectedAsset?.name == "Alpha")
    model.category = .plugin
    model.selectedPath = model.visibleAssets.first?.path
    #expect(model.detail.contains("not available for plugins"))
}

@Test func logicMetadataStaysUnresolvedAndExcludesUnused() throws {
    let f = try CatalogFixture()
    let project = f.root.appendingPathComponent("Fixture.logicx")
    let metadata = try f.file("Fixture.logicx/Alternatives/000/MetaData.plist")
    try PropertyListSerialization.data(fromPropertyList: ["AudioFiles": ["/Samples/included.wav"], "UnusedAudioFiles": ["/Samples/unused.wav"]], format: .binary, options: 0).write(to: metadata)
    let report = ProjectReader.read(project)
    #expect(report.coverage == "partial")
    #expect(report.references.map(\.value) == ["/Samples/included.wav"])
    #expect(report.references.allSatisfy { $0.resolvedPath == nil })
    try PropertyListSerialization.data(fromPropertyList: ["AudioFiles": [5]], format: .binary, options: 0).write(to: metadata)
    #expect(ProjectReader.read(project).coverage == "failed")
}

@Test func logicLinkedMetadataFails() throws {
    let f = try CatalogFixture()
    let target = try f.file("outside.plist")
    let link = f.root.appendingPathComponent("Fixture.logicx/Alternatives/000/MetaData.plist")
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(ProjectReader.read(f.root.appendingPathComponent("Fixture.logicx" )).coverage == "failed")
}

@Test func directInspectionRejectsLinkedAncestors() throws {
    let f = try CatalogFixture()
    try f.file("Actual/Session.rpp", "<REAPER_PROJECT\n>")
    let link = f.root.appendingPathComponent("Linked")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.root.appendingPathComponent("Actual"))
    #expect(ProjectReader.read(link.appendingPathComponent("Session.rpp")).coverage == "failed")
}

@Test func legacyAbletonNamesRemainUnresolved() throws {
    let xml = "<Ableton><SampleRef><FileRef><Name Value=\"Kick.wav\"/><RelativePath><RelativePathElement Dir=\"Samples\"/></RelativePath></FileRef></SampleRef></Ableton>"
    let refs = try ProjectReader.parseAbleton(Data(xml.utf8))
    #expect(refs.map(\.value) == ["Kick.wav"])
    #expect(refs.allSatisfy { $0.resolvedPath == nil })
}

@Test @MainActor func setupRoundTripRestoresOnlyAcceptedConfiguration() throws {
    let f = try CatalogFixture(); let store = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let model = CatalogModel(store: store); let draft = model.setupDraft()
    draft.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    draft.addRoots([f.root.appendingPathComponent("Projects")], kind: .projects)
    draft.standardPlugins = false; draft.query = "not persisted"; draft.category = .library
    #expect(model.roots.isEmpty) // Draft navigation/cancellation has no active effect.
    try model.acceptSetup(draft, remember: true)
    let reopened = CatalogModel(store: store)
    #expect(reopened.roots == draft.roots && !reopened.standardPlugins && reopened.onboardingCompleted)
    #expect(reopened.query.isEmpty && reopened.category == .plugin && reopened.report == nil && !reopened.isScanning)
    let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
    let values = try #require(envelope["settings"] as? [String: Any])
    #expect(Set(values.keys) == CatalogStateRegistry.persistedIDs)
}

@Test @MainActor func setupRejectsCorruptFutureAndWrongTypesWithoutChangingFile() throws {
    let f = try CatalogFixture(); let store = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    for source in ["{bad", "{\"version\":2,\"settings\":{}}", "{\"version\":true,\"settings\":{}}", "{\"version\":1,\"settings\":{\"standard_plugins\":1}}", "{\"version\":1,\"settings\":{\"roots\":{\"Samples\":[\"relative/path\"]}}}"] {
        let data = Data(source.utf8); try data.write(to: store.url)
        let model = CatalogModel(store: store)
        #expect(model.setupNotice != nil && model.roots.isEmpty && !model.onboardingCompleted)
        #expect(throws: (any Error).self) { try model.acceptSetup(model.setupDraft(), remember: true) }
        #expect(try Data(contentsOf: store.url) == data)
        let draft = model.setupDraft(); draft.standardPlugins = false
        try model.acceptSetup(draft, remember: false)
        #expect(model.onboardingCompleted && !model.standardPlugins)
        #expect(try Data(contentsOf: store.url) == data)
    }
}

@Test @MainActor func setupMissingFieldsDefaultAndUnknownFieldsAreIgnored() throws {
    let f = try CatalogFixture(); let store = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    #expect(try store.load() == nil)
    try Data("{\"version\":1,\"settings\":{\"unused_future_key\":42}}".utf8).write(to: store.url)
    let model = CatalogModel(store: store)
    #expect(model.standardPlugins && model.roots.isEmpty && !model.onboardingCompleted && model.setupNotice == nil)
}

@Test @MainActor func failedSetupSaveDoesNotApplyDraft() throws {
    let f = try CatalogFixture(); let blocker = try f.file("not-a-directory")
    let model = CatalogModel(store: SetupStore(url: blocker.appendingPathComponent("setup.json")))
    let draft = model.setupDraft(); draft.standardPlugins = false; draft.addRoots([f.root], kind: .libraries)
    #expect(throws: (any Error).self) { try model.acceptSetup(draft, remember: true) }
    #expect(model.standardPlugins && model.roots.isEmpty && !model.onboardingCompleted)
}

@Test @MainActor func setupRejectsNonregularAndOversizedFiles() throws {
    let f = try CatalogFixture(); let fifo = f.root.appendingPathComponent("fifo")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    #expect(throws: (any Error).self) { try SetupStore(url: fifo).load() }
    let large = f.root.appendingPathComponent("large.json")
    try Data(repeating: 32, count: 1_048_577).write(to: large)
    #expect(throws: (any Error).self) { try SetupStore(url: large).load() }
}

@Test @MainActor func groupedMemberSearchAndMultipleRootsPersist() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Echo.component/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.echo.au</string></dict></plist>")
    try f.file("Plugins/Echo.vst3/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.echo.vst3</string></dict></plist>")
    try f.file("Samples A/Kick.wav"); try f.file("Samples B/Snare.wav")
    try f.file("Kontakt/Strings/Banjo.nki"); try f.file("SINE/Brass/Accordion.dspreset")
    try f.file("Projects/Test.rpp", "<REAPER_PROJECT\n<TRACK\n<FXCHAIN\n<VST \"VST3: Echo (Example)\"\n>\n>\n>\n>")
    let store = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let model = CatalogModel(store: store); let draft = model.setupDraft(); draft.setStandardPlugins(false)
    draft.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    draft.addRoots([f.root.appendingPathComponent("Samples A"), f.root.appendingPathComponent("Samples B")], kind: .samples)
    draft.addRoots([f.root.appendingPathComponent("Kontakt")], kind: .libraries)
    draft.addRoots([f.root.appendingPathComponent("SINE")], kind: .libraries)
    draft.addRoots([f.root.appendingPathComponent("Projects")], kind: .projects)
    try model.acceptSetup(draft, remember: true)
    let reopened = CatalogModel(store: store)
    #expect(reopened.roots[.samples]?.count == 2 && reopened.roots[.libraries]?.count == 2)
    reopened.scan(); try await finish(reopened)
    #expect(reopened.visibleAssets.count == 1 && reopened.totalCount == 1)
    reopened.query = "vst3"; #expect(reopened.visibleAssets.count == 1)
    reopened.selectedPath = reopened.visibleAssets.first?.path
    #expect(reopened.selectedPlugin?.installations.count == 2)
    #expect(reopened.pluginReferenceDetail(reopened.selectedPlugin!).contains("Candidate saved-project matches"))
    #expect(reopened.pluginReferenceDetail(reopened.selectedPlugin!).contains("do not identify"))
    reopened.query = ""; reopened.category = .sample; #expect(reopened.visibleAssets.count == 2)
    reopened.category = .library; #expect(reopened.visibleAssets.count == 2)
}

@Test @MainActor func removalCannotReplaceReviewedIdentityWithNewScan() async throws {
    let f = try CatalogFixture(); try f.file("Echo.vst3/Contents/marker")
    let model = CatalogModel(); model.setStandardPlugins(false); model.addRoots([f.root], kind: .plugins)
    model.scan(); try await finish(model)
    let reviewed = model.report!.assets[0]
    try FileManager.default.moveItem(atPath: reviewed.path, toPath: reviewed.path + ".previous")
    try f.file("Echo.vst3/Contents/marker", "replacement")
    model.scan(); try await finish(model)
    let results = await model.trashPlugins([reviewed])
    #expect(results.isEmpty)
    #expect(FileManager.default.fileExists(atPath: reviewed.path))
}

@Test @MainActor func librarySearchFindsInstrumentNamesWithoutRandomFolders() async throws {
    let f = try CatalogFixture()
    try f.file("Libraries/Folk/Folk.nicnt", "<ProductHints><Product><Name>Example World Collection</Name><Company>Example</Company></Product></ProductHints>")
    try f.file("Libraries/Folk/Instruments/Banjo.nki")
    try f.file("Libraries/Folk/Instruments/Accordion.nki")
    try f.file("Libraries/Unrelated/readme.txt")
    let model = CatalogModel(); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries)
    model.scan(); try await finish(model); model.category = .library
    #expect(model.visibleAssets.count == 1)
    model.query = "Accordion"; #expect(model.visibleAssets.first?.name == "Example World Collection")
    model.query = "Banjo"; #expect(model.visibleAssets.count == 1)
    model.query = "Trumpet"; #expect(model.visibleAssets.isEmpty)
}

@Test @MainActor func sharedLibraryContainerDoesNotMergeSelection() async throws {
    let f = try CatalogFixture()
    let meta = try f.file("Content/Shared.otmeta")
    try f.file("Content/Shared.otarc")
    let database = f.root.appendingPathComponent("vendor.db")
    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let schema = """
    CREATE TABLE t_collection(collection_key,collection_id,title,subtitle,developer,keywords);
    CREATE TABLE t_instrument(instrument_key,instrument_collection,instrument_id,title,keywords);
    CREATE TABLE t_micPosition(micposition_instrument,filePath);
    INSERT INTO t_collection VALUES(1,'ark2','Ark 2','','Orchestral Tools',''),(2,'ark3','Ark 3','','Orchestral Tools','');
    INSERT INTO t_instrument VALUES(1,1,'low','Low Strings','strings'),(2,2,'low','Low Strings','strings');
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    for id: Int32 in [1, 2] {
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO t_micPosition VALUES(?,?)", -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, id)
        (meta.path + "/virtual.otmf").withCString {
            sqlite3_bind_text(stmt, 2, $0, -1, nil); #expect(sqlite3_step(stmt) == SQLITE_DONE)
        }
        sqlite3_finalize(stmt)
    }
    let model = CatalogModel(sineDatabase: database); model.standardPlugins = false
    model.addRoots([f.root.appendingPathComponent("Content")], kind: .libraries)
    model.category = .library; model.scan(); try await finish(model)
    #expect(model.visibleAssets.count == 2)
    for asset in model.visibleAssets {
        model.selectedPath = asset.selectionKey
        #expect(model.selectedAsset?.name == asset.name)
        #expect(model.selectedAsset?.path == meta.path)
    }
    model.scan(); try await finish(model)
    #expect(model.selectedAsset?.name == "Ark 3")
}
