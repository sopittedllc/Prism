import Foundation
import Testing
import Darwin
import CSQLite
@testable import SimplifyCore

@Test func filesystemAdditionDateDoesNotDependOnSpotlight() {
    let file = URL(fileURLWithPath: "/synthetic/Instrument.nki")
    let now = Date(timeIntervalSince1970: 300)
    let direct = Date(timeIntervalSince1970: 100)
    let indexed = Date(timeIntervalSince1970: 200)
    var spotlightReads = 0
    #expect(FinderDateAdded.read(file, now: now, filesystem: { _ in direct }, spotlight: { _ in
        spotlightReads += 1; return indexed
    }) == direct)
    #expect(spotlightReads == 0)
    #expect(FinderDateAdded.read(file, now: now, filesystem: { _ in nil }, spotlight: { _ in indexed }) == indexed)
    for invalid in [Date(timeIntervalSince1970: -1), Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: .infinity), now.addingTimeInterval(1)] {
        #expect(FinderDateAdded.read(file, now: now, filesystem: { _ in invalid }, spotlight: { _ in indexed }) == indexed)
        #expect(FinderDateAdded.read(file, now: now, filesystem: { _ in invalid }, spotlight: { _ in invalid }) == nil)
    }
    #expect(FinderDateAdded.read(file, now: now, filesystem: { _ in nil }, spotlight: { _ in nil }) == nil)
}

private final class Fixture {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ path: String, _ text: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
}

@Test func unchangedSavedProjectReusesReportButChangedSourceReparses() throws {
    let f = try Fixture()
    let project = try f.file("Projects/Song.rpp", "<REAPER_PROJECT\n>\n")
    var request = ScanRequest(); request.projects = [project.deletingLastPathComponent()]
    let first = Scanner().scan(request, scannedKinds: [.sample])
    let parsed = try #require(first.projects.first)
    let stamp = try #require(parsed.sourceSignature)
    var cached = ProjectReport(path: project.path, adapter: "rpp", coverage: "partial",
        projectModifiedAt: parsed.projectModifiedAt,
        references: [ProjectReference(kind: .plugin, value: "cached", resolvedPath: nil, evidence: "fixture")],
        limitations: [])
    cached.sourceSHA256 = String(repeating: "a", count: 64)
    cached.sourceSignature = stamp
    cached.readerPolicyVersion = ProjectReader.policyVersion
    let reused = Scanner().scan(request, scannedKinds: [.sample], previousProjects: [cached])
    #expect(reused.projects.first?.references.first?.value == "cached")
    try Data("<REAPER_PROJECT\n<TRACK\n>\n>\n".utf8).write(to: project)
    let changed = Scanner().scan(request, scannedKinds: [.sample], previousProjects: [cached])
    #expect(changed.projects.first?.references.isEmpty == true)
    #expect(changed.projects.first?.sourceSignature != stamp)
}

@Test func libraryDirectoryJournalResumesAndInvalidatesChangedMetadata() async throws {
    let f = try Fixture()
    let root = f.root.appendingPathComponent("Libraries")
    for index in 0..<180 {
        _ = try f.file(String(format: "Libraries/Folder%03d/Patch.nki", index))
    }
    var request = ScanRequest(); request.libraries = [root]
    let journalBase = f.root.appendingPathComponent("catalog.sqlite")
    let interrupted = await Task.detached { () -> [ScanIssue] in
        var issues: [ScanIssue] = []
        _ = LibraryDiscovery.scan(request, journalBaseURL: journalBase, issues: &issues) { completed, _ in
            if completed > 280 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        return issues
    }.value
    #expect(interrupted.contains { $0.reason.contains("cancelled") })
    var resumedVisits = 0
    var issues: [ScanIssue] = []
    let resumed = LibraryDiscovery.scan(request, journalBaseURL: journalBase, issues: &issues) { _, _ in resumedVisits += 1 }
    var baselineIssues: [ScanIssue] = []
    let baseline = LibraryDiscovery.scan(request, issues: &baselineIssues)
    #expect(issues.isEmpty && baselineIssues.isEmpty)
    #expect(resumed.count == baseline.count && resumed.count == 180)
    #expect(resumedVisits < 360)
    _ = try f.file("Libraries/Folder179/NewPatch.nki")
    issues = []
    let changed = LibraryDiscovery.scan(request, journalBaseURL: journalBase, issues: &issues)
    #expect(issues.isEmpty)
    #expect(changed.flatMap { $0.libraryMetadata?.instruments ?? [] }.contains { $0.name == "NewPatch" })
}

@Test func corruptLibraryJournalIsDiscardedForNextScan() throws {
    let f = try Fixture()
    let root = f.root.appendingPathComponent("Libraries")
    _ = try f.file("Libraries/Product/Patch.nki")
    var request = ScanRequest(); request.libraries = [root]
    let catalog = f.root.appendingPathComponent("catalog.sqlite")
    var issues: [ScanIssue] = []
    _ = LibraryDiscovery.scan(request, journalBaseURL: catalog, issues: &issues)
    #expect(issues.isEmpty)
    let journal = LibraryScanJournal.location(baseURL: catalog, scope: CatalogScope(request), root: root)
    try Data("invalid SQLite".utf8).write(to: journal)
    issues = []
    let fallback = LibraryDiscovery.scan(request, journalBaseURL: catalog, issues: &issues)
    #expect(fallback.count == 1)
    #expect(issues.contains { $0.reason.contains("checkpoint unavailable") })
    issues = []
    let rebuilt = LibraryDiscovery.scan(request, journalBaseURL: catalog, issues: &issues)
    #expect(rebuilt.count == 1 && issues.isEmpty)
    #expect(try LibraryScanJournal(baseURL: catalog, scope: CatalogScope(request), root: root,
                                   source: LibraryMetadataReader.sineDatabase).validateCompleted())
}

@Test func nativeLibraryJournalRuntime() throws {
    guard let source = ProcessInfo.processInfo.environment["PRISM_LIBRARY_JOURNAL_ROOTS"], !source.isEmpty else { return }
    let roots = source.split(separator: ";").map { URL(fileURLWithPath: String($0)) }
    let scratch = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        .appendingPathComponent("prism-library-journal-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let catalog = scratch.appendingPathComponent("catalog.sqlite")
    var request = ScanRequest(); request.libraries = roots
    for root in roots {
        _ = try LibraryScanJournal(baseURL: catalog, scope: CatalogScope(request), root: root,
                                   source: LibraryMetadataReader.sineDatabase)
    }
    let firstStart = Date()
    var firstIssues: [ScanIssue] = []
    let first = LibraryDiscovery.scan(request, journalBaseURL: catalog, issues: &firstIssues)
    let cold = Date().timeIntervalSince(firstStart)
    let journalBytes = roots.reduce(Int64(0)) { total, root in
        let url = LibraryScanJournal.location(baseURL: catalog, scope: CatalogScope(request), root: root)
        return total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    let secondStart = Date()
    var secondIssues: [ScanIssue] = []
    let second = LibraryDiscovery.scan(request, journalBaseURL: catalog, issues: &secondIssues)
    let warm = Date().timeIntervalSince(secondStart)
    #expect(Set(first.map(\.selectionKey)) == Set(second.map(\.selectionKey)))
    let firstPatches = Set(first.flatMap { $0.libraryMetadata?.instruments.map(\.path) ?? [] })
    let resumedPatches = Set(second.flatMap { $0.libraryMetadata?.instruments.map(\.path) ?? [] })
    #expect(firstPatches == resumedPatches)
    #expect(firstIssues.map(\.reason) == secondIssues.map(\.reason))
    let unassociated = first.filter { $0.classification == "unassociatedPhysicalContent" }
    let unassociatedBytes = unassociated.compactMap(\.logicalBytes).reduce(0, +)
    #expect(unassociated.map(\.path).sorted() == second.filter { $0.classification == "unassociatedPhysicalContent" }.map(\.path).sorted())
    print("Library journal runtime: roots=\(roots.count), assets=\(first.count), patches=\(firstPatches.count), unassociated=\(unassociated.count), unassociatedBytes=\(unassociatedBytes), cold=\(cold)s, resume=\(warm)s, journalBytes=\(journalBytes), issues=\(firstIssues.map(\.reason))")
}

@Test func discoversPluginBundlesWithoutLoading() throws {
    let f = try Fixture()
    for ext in ["component", "vst", "vst3", "aaxplugin", "clap"] {
        try f.file("Plugins/Test.\(ext)/Contents/Info.plist", """
        <?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.example.test</string></dict></plist>
        """)
        try f.file("Plugins/Test.\(ext)/Contents/Resources/hidden.wav")
    }
    var request = ScanRequest()
    request.plugins = [f.root.appendingPathComponent("Plugins")]
    request.samples = [f.root]
    let result = Scanner().scan(request)
    #expect(result.assets.count == 5)
    #expect(result.assets.allSatisfy { $0.kind == .plugin && $0.bundleIdentifier == "org.example.test" })
    #expect(result.assets.allSatisfy { $0.logicalBytes == result.assets.first?.logicalBytes && ($0.logicalBytes ?? 0) > 0 })
}

@Test func pluginBundleSizeCountsHardLinksOnceAndAccountsLinkEntriesWithoutFollowing() throws {
    let f = try Fixture()
    let bundle = f.root.appendingPathComponent("Plugins/Measured.vst3")
    let file = try f.file("Plugins/Measured.vst3/Contents/Binary", String(repeating: "x", count: 100))
    try FileManager.default.linkItem(at: file, to: bundle.appendingPathComponent("Contents/Hardlink"))
    var pass = PluginBundleSize.Pass()
    let measured = PluginBundleSize.measure(bundle, pass: &pass)
    #expect(measured.bytes == 100 && measured.issue == nil)
    _ = try f.file("Plugins/Measured.vst3/Contents/__Pace_Eden.bundle/Contents/Resources/Signatures/codesign.dsig", "sig!")
    let internalLink = bundle.appendingPathComponent("Contents/Resources/__Pace_Eden/Signatures/codesign.dsig")
    try FileManager.default.createDirectory(at: internalLink.deletingLastPathComponent(), withIntermediateDirectories: true)
    let internalDestination = "../../../__Pace_Eden.bundle/Contents/Resources/Signatures/codesign.dsig"
    try FileManager.default.createSymbolicLink(atPath: internalLink.path,
        withDestinationPath: internalDestination)
    pass = PluginBundleSize.Pass()
    #expect(PluginBundleSize.measure(bundle, pass: &pass).bytes == 104 + internalDestination.utf8.count)
    try FileManager.default.removeItem(at: internalLink)
    let external = try f.file("Shared/External.bin", String(repeating: "z", count: 300))
    try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("Contents/External"), withDestinationURL: external)
    pass = PluginBundleSize.Pass()
    #expect(PluginBundleSize.measure(bundle, pass: &pass).bytes == 104 + external.path.utf8.count)
    try FileManager.default.removeItem(at: bundle.appendingPathComponent("Contents/External"))
    try FileManager.default.createSymbolicLink(atPath: internalLink.path, withDestinationPath: "../Missing")
    pass = PluginBundleSize.Pass()
    let dangling = PluginBundleSize.measure(bundle, pass: &pass)
    #expect(dangling.bytes == 104 + "../Missing".utf8.count && dangling.issue == nil)
    try FileManager.default.removeItem(at: internalLink)
    let deep = (0...PluginBundleSize.maximumBundleDepth).map { "d\($0)" }.joined(separator: "/")
    _ = try f.file("Plugins/Measured.vst3/" + deep + "/too-deep", "x")
    pass = PluginBundleSize.Pass()
    #expect(PluginBundleSize.measure(bundle, pass: &pass).issue?.contains("depth") == true)
    pass = PluginBundleSize.Pass(entries: 0, startedAt: ProcessInfo.processInfo.systemUptime - 9, exhausted: false)
    #expect(PluginBundleSize.measure(bundle, pass: &pass).issue?.contains("pass time") == true)
    pass = PluginBundleSize.Pass(entries: PluginBundleSize.maximumPassEntries - 1)
    #expect(PluginBundleSize.measure(bundle, pass: &pass).issue?.contains("pass entry") == true)
    #expect(pass.exhausted)
    pass = PluginBundleSize.Pass(entries: PluginBundleSize.maximumPassEntries,
        startedAt: ProcessInfo.processInfo.systemUptime - 9, exhausted: true)
    let complete = PluginBundleSize.measure(bundle, pass: &pass, complete: true)
    #expect(complete.bytes == 105 && complete.issue == nil)
    pass = PluginBundleSize.Pass()
    #expect(PluginBundleSize.measure(f.root.appendingPathComponent("Missing.vst3"), pass: &pass).issue?.contains("unavailable") == true)
    #expect(PluginBundleSize.checkedSum(Int.max, 1) == nil)
}

@Test func olderPluginInventoryWithoutLogicalBytesRemainsUnknown() throws {
    let original = Asset(kind: .plugin, path: "/old/Glow.vst3", name: "Glow", format: "vst3",
                         bundleIdentifier: "org.example.glow", logicalBytes: 42, classification: "test")
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    payload.removeValue(forKey: "logicalBytes")
    payload.removeValue(forKey: "finderDateAdded")
    let restored = try JSONDecoder().decode(Asset.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(restored.logicalBytes == nil && restored.finderDateAdded == nil)
    #expect(restored.path == original.path && restored.kind == .plugin)
}

@Test func libraryRootsExcludeInternalSamplesAndDeduplicate() throws {
    let f = try Fixture()
    try f.file("Libraries/Strings/Samples/C3.wav")
    try f.file("Libraries/Strings/Banjo.nki")
    try f.file("Libraries/Piano.dsbundle/soft.wav")
    try f.file("Libraries/Piano.dsbundle/Piano.dspreset")
    try f.file("Libraries/Bells.dslibrary")
    let loose = try f.file("Loose/kick.WAV")
    var request = ScanRequest()
    request.libraries = [f.root.appendingPathComponent("Libraries")]
    request.samples = [f.root, f.root.appendingPathComponent("Loose"), f.root]
    let result = Scanner().scan(request)
    #expect(result.assets.filter { $0.kind == .library }.count == 2)
    #expect(result.assets.contains { $0.logicalBytes != nil && $0.libraryMetadata?.sizeBasis == .candidateFolder })
    #expect(result.assets.filter { $0.kind == .sample }.map(\.path) == [loose.path])
    #expect(result.sampleInclusions.first?.status == "noReferencesFoundInScannedProjects")
}

@Test func manifestOwnedLibrarySizeIsCompleteOrUnknownWithoutPartialTotals() throws {
    let f = try Fixture()
    let root = f.root.appendingPathComponent("Libraries/Strings")
    let manifest = "<ProductHints><Product><Name>Strings</Name><Company>Example Audio</Company></Product></ProductHints>"
    _ = try f.file("Libraries/Strings/Strings.nicnt", manifest)
    let sample = try f.file("Libraries/Strings/Samples/C3.wav", String(repeating: "x", count: 100))
    try FileManager.default.linkItem(at: sample, to: root.appendingPathComponent("Samples/Hardlink.wav"))
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    var report = Scanner().scan(request, scannedKinds: [.library])
    let library = try #require(report.assets.first { $0.kind == .library })
    #expect(library.logicalBytes == manifest.utf8.count + 100)
    let deep = (0...PluginBundleSize.maximumBundleDepth).map { "d\($0)" }.joined(separator: "/")
    _ = try f.file("Libraries/Strings/" + deep + "/too-deep", "x")
    report = Scanner().scan(request, scannedKinds: [.library])
    #expect(report.assets.first { $0.kind == .library }?.logicalBytes == manifest.utf8.count + 101)
    #expect(!report.issues.contains { $0.kind == .library && $0.reason.contains("Library size depth limit") })
    // Plugin-sized budgets must not turn a large library into an unknown size.
    for index in 0..<4100 { _ = try f.file("Libraries/Strings/Samples/part-\(index).ncw", "ab") }
    report = Scanner().scan(request, scannedKinds: [.library])
    #expect(report.assets.first { $0.kind == .library }?.logicalBytes == manifest.utf8.count + 8301)
    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("external").path,
                                             withDestinationPath: "/tmp")
    report = Scanner().scan(request, scannedKinds: [.library])
    #expect(report.assets.first { $0.kind == .library }?.logicalBytes == manifest.utf8.count + 8305)
    #expect(!report.issues.contains { $0.kind == .library && $0.reason.contains("link") })
}

@Test func ambiguousManifestFolderDoesNotClaimOneLibrarySize() throws {
    let f = try Fixture()
    let manifest = "<ProductHints><Product><Name>Shared</Name><Company>Example Audio</Company></Product></ProductHints>"
    _ = try f.file("Libraries/Shared/One.nicnt", manifest)
    _ = try f.file("Libraries/Shared/Two.nicnt", manifest)
    _ = try f.file("Libraries/Shared/Samples/C3.wav", "sample")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let report = Scanner().scan(request, scannedKinds: [.library])
    #expect(report.assets.allSatisfy { $0.logicalBytes != nil && $0.libraryMetadata?.sizeBasis == .candidateFolder })
    #expect(report.issues.contains { $0.reason.contains("Multiple Kontakt manifests") })
}

@Test func nestedManifestRootsReceiveHonestScopedFolderSizes() throws {
    let f = try Fixture()
    let parentManifest = "<ProductHints><Product><Name>Parent</Name><Company>Example Audio</Company></Product></ProductHints>"
    let childManifest = "<ProductHints><Product><Name>Child</Name><Company>Example Audio</Company></Product></ProductHints>"
    _ = try f.file("Libraries/Parent/Parent.nicnt", parentManifest)
    _ = try f.file("Libraries/Parent/Child/Child.nicnt", childManifest)
    _ = try f.file("Libraries/Parent/Child/Samples/C3.wav", "sample")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let libraries = Scanner().scan(request, scannedKinds: [.library]).assets.filter { $0.kind == .library }
    #expect(libraries.count == 2)
    let parent = try #require(libraries.first { $0.name == "Parent" })
    let child = try #require(libraries.first { $0.name == "Child" })
    #expect(parent.logicalBytes == parentManifest.utf8.count + childManifest.utf8.count + "sample".utf8.count)
    #expect(child.logicalBytes == childManifest.utf8.count + "sample".utf8.count)
    #expect(parent.libraryMetadata?.sizeBasis == .candidateFolder)
    #expect(child.libraryMetadata?.sizeBasis == .candidateFolder)
}

@Test func stringRunsManifestParentCannotClaimNestedSINEPayloadAsItsOwnSize() throws {
    let f = try Fixture()
    let product = f.root.appendingPathComponent("Libraries/String Runs")
    _ = try f.file("Libraries/String Runs/String Runs.nicnt",
        "<ProductHints><Product><Name>String Runs</Name><Company>Example Audio</Company></Product></ProductHints>")
    let metadata = try f.file("Libraries/String Runs/SINE/Close/String Runs.otmeta", "meta")
    let archive = try f.file("Libraries/String Runs/SINE/Close/String Runs.otarc", "")
    let payloadBytes: UInt64 = 526_000_000_000
    let handle = try FileHandle(forWritingTo: archive)
    try handle.truncate(atOffset: payloadBytes)
    try handle.close()

    let database = f.root.appendingPathComponent("sine.db")
    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let schema = """
    CREATE TABLE t_collection(collection_key,collection_id,title,subtitle,developer,keywords);
    CREATE TABLE t_instrument(instrument_key,instrument_collection,instrument_id,title,keywords);
    CREATE TABLE t_micPosition(micposition_instrument,filePath);
    CREATE TABLE t_articulation(articulation_key,articulation_instrument,articulation_id,title,kind,hidden);
    INSERT INTO t_collection VALUES(1,'runs','String Runs SINE','','Example Audio','strings');
    INSERT INTO t_instrument VALUES(1,1,'ensemble','String Runs Ensemble','strings');
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "INSERT INTO t_micPosition VALUES(1,?)", -1, &statement, nil) == SQLITE_OK)
    let virtualPath = metadata.path + "/virtual.otmf"
    let insertStatus = virtualPath.withCString { pointer in
        sqlite3_bind_text(statement, 1, pointer, -1, nil)
        return sqlite3_step(statement)
    }
    sqlite3_finalize(statement)
    #expect(insertStatus == SQLITE_DONE)

    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let report = Scanner(sineDatabase: database).scan(request, scannedKinds: [.library])
    let kontakt = try #require(report.assets.first { $0.name == "String Runs" && $0.format == "Kontakt" })
    let sine = try #require(report.assets.first { $0.name == "String Runs SINE" && $0.format == "SINE" })
    #expect(kontakt.libraryMetadata?.identity?.installationRoot == product.path)
    let kontaktManifest = "<ProductHints><Product><Name>String Runs</Name><Company>Example Audio</Company></Product></ProductHints>"
    #expect(kontakt.logicalBytes == Int(payloadBytes) + 4 + kontaktManifest.utf8.count)
    #expect(kontakt.libraryMetadata?.sizeBasis == .candidateFolder)
    #expect(sine.logicalBytes == Int(payloadBytes) + 4)
    #expect(sine.libraryMetadata?.sizeBasis == .installedContent)
}

@Test func missingAndSymlinkRootsAreReported() throws {
    let f = try Fixture()
    try f.file("Actual/nested/kick.wav")
    try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("Link"),
                                               withDestinationURL: f.root.appendingPathComponent("Actual"))
    var request = ScanRequest()
    request.samples = [f.root.appendingPathComponent("Missing"), f.root.appendingPathComponent("Link/nested")]
    let result = Scanner().scan(request)
    #expect(result.assets.isEmpty)
    #expect(result.issues.count == 2)
}

@Test func nestedSymlinksAndPackagesAreNotFollowed() throws {
    let f = try Fixture()
    try f.file("Samples/App.app/hidden.wav")
    try f.file("Samples/Piano.dsbundle/hidden.wav")
    try f.file("Elsewhere/outside.wav")
    try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("Samples/loop"), withDestinationURL: f.root)
    var request = ScanRequest()
    request.samples = [f.root.appendingPathComponent("Samples")]
    let result = Scanner().scan(request)
    #expect(result.assets.isEmpty)
    #expect(result.issues.count == 1)
}

@Test func traversalLimitsAreExplicit() throws {
    let f = try Fixture()
    try f.file("a/b/c/kick.wav")
    var request = ScanRequest()
    request.samples = [f.root]
    request.maximumDepth = 1
    request.completeFileScan = false
    #expect(Scanner().scan(request).issues.contains { $0.reason.contains("Depth limit") })
    request.maximumDepth = 64
    request.maximumEntries = 1
    #expect(Scanner().scan(request).issues.contains { $0.reason.contains("Entry limit") })
}

@Test func reaperIncludesMutedSamplesAndBypassedPlugins() throws {
    let text = """
    <REAPER_PROJECT 0.1 7.0
      <TRACK
        MUTESOLO 1 0 0
        <FXCHAIN
          BYPASS 1 0 0
          <VST "VST: Fixture Synth" fixture.vst 0 "" 123
            opaqueState
          >
        >
        <ITEM
          <SOURCE SECTION
            <SOURCE WAVE
              FILE "Samples/my kick.wav"
            >
          >
        >
      >
    >
    """
    let refs = try ProjectReader.parseReaper(Data(text.utf8), project: URL(fileURLWithPath: "/Projects/Test/song.rpp"))
    #expect(refs.count == 2)
    #expect(refs.first?.kind == .plugin)
    #expect(refs.last?.resolvedPath == "/Projects/Test/Samples/my kick.wav")
}

@Test func foreignPathsAndOpaqueStateAreNotMatched() throws {
    let text = #"""
    <REAPER_PROJECT
      <TRACK
      <ITEM
      <SOURCE WAVE
        FILE "C:\Samples\kick.wav"
      >
      >
      >
      <VST "opaque"
        FILE "/not-a-sample.wav"
      >
    >
    """#
    let refs = try ProjectReader.parseReaper(Data(text.utf8), project: URL(fileURLWithPath: "/song.rpp"))
    #expect(refs.count == 1)
    #expect(refs[0].resolvedPath == nil)
}

@Test func malformedReaperIsRejected() {
    for text in ["garbage", "<REAPER_PROJECT\n<SOURCE WAVE\nFILE \"a.wav\"\n>",
                 "<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE \"unclosed\n>\n>\n>\n>", "<REAPER_PROJECT\n>\nextra"] {
        #expect(throws: (any Error).self) {
            try ProjectReader.parseReaper(Data(text.utf8), project: URL(fileURLWithPath: "/song.rpp"))
        }
    }
}

@Test func reaperDepthLimit() {
    let text = "<REAPER_PROJECT\n" + String(repeating: "<SOURCE SECTION\n", count: 129)
    #expect(throws: (any Error).self) {
        try ProjectReader.parseReaper(Data(text.utf8), project: URL(fileURLWithPath: "/song.rpp"))
    }
}

@Test func abletonExtractsOnlyDirectSampleReferences() throws {
    let xml = """
    <Ableton><LiveSet>
      <FileRef><Path Value="/not/audio.wav"/></FileRef>
      <SampleRef><FileRef><Path Value="/stale/audio.wav"/><RelativePath Value="Samples/audio.wav"/></FileRef>
        <SourceContext><OriginalFileRef><FileRef><Path Value="/historic/audio.wav"/></FileRef></OriginalFileRef></SourceContext>
      </SampleRef>
    </LiveSet></Ableton>
    """
    let refs = try ProjectReader.parseAbleton(Data(xml.utf8))
    #expect(refs.map(\.value) == ["/stale/audio.wav", "Samples/audio.wav"])
    #expect(refs.allSatisfy { $0.resolvedPath == nil })
}

@Test func invalidXMLAndEntitiesAreRejected() {
    for xml in ["<Ableton>", "<Other/>",
                "<!DOCTYPE Ableton [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><Ableton>&x;</Ableton>",
                "<!DOCTYPE Ableton [<!ENTITY x 'text'>]><Ableton>&x;</Ableton>"] {
        #expect(throws: (any Error).self) { try ProjectReader.parseAbleton(Data(xml.utf8)) }
    }
}

@Test func unsupportedAndMalformedProjectsRemainVisible() throws {
    let f = try Fixture()
    try f.file("Projects/Session.ptx")
    try f.file("Projects/Bad.rpp", "bad")
    var request = ScanRequest()
    request.projects = [f.root.appendingPathComponent("Projects")]
    let result = Scanner().scan(request)
    #expect(Set(result.projects.map(\.coverage)) == ["failed"])
    #expect(result.projects.allSatisfy { $0.references.isEmpty })
    #expect(result.issues.count == 2)
}

@Test func inclusionKeepsProjectProvenanceAndRecencyProxy() throws {
    let f = try Fixture()
    let sample = try f.file("Samples/kick.wav")
    let content = "<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE \"../Samples/kick.wav\"\n>\n>\n>\n>"
    let old = try f.file("Projects/old.rpp", content)
    let new = try f.file("Projects/new.rpp", content)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: new.path)
    var request = ScanRequest()
    request.samples = [f.root.appendingPathComponent("Samples")]
    request.projects = [f.root.appendingPathComponent("Projects")]
    let inclusion = try #require(Scanner().scan(request).sampleInclusions.first)
    #expect(inclusion.samplePath == sample.path)
    #expect(inclusion.projectPaths.count == 2)
    #expect(inclusion.latestReferencingProjectModifiedAt == Date(timeIntervalSince1970: 200))
}

@Test func specialFilesCannotBlockReaders() throws {
    let f = try Fixture()
    let pipe = f.root.appendingPathComponent("Pipe.rpp")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(ProjectReader.read(pipe).coverage == "failed")
    let info = try f.file("Plugins/Pipe.vst3/Contents/placeholder")
        .deletingLastPathComponent().appendingPathComponent("Info.plist")
    #expect(mkfifo(info.path, 0o600) == 0)
    var request = ScanRequest()
    request.plugins = [f.root.appendingPathComponent("Plugins")]
    #expect(Scanner().scan(request).assets.count == 1)
}

@Test func overlappingLibraryRootsPreserveChildren() throws {
    let f = try Fixture()
    try f.file("Libraries/Vendor/Strings/Accordion.nki")
    var request = ScanRequest()
    request.libraries = [f.root.appendingPathComponent("Libraries"), f.root.appendingPathComponent("Libraries/Vendor")]
    #expect(Set(Scanner().scan(request).assets.map(\.name)) == ["Strings"])
}

@Test func unknownReaperSubtreesDoNotBecomeReferences() throws {
    let text = "<REAPER_PROJECT\n<UNKNOWN\n<SOURCE WAVE\nFILE \"/Samples/kick.wav\"\n>\n>\n>"
    #expect(try ProjectReader.parseReaper(Data(text.utf8), project: URL(fileURLWithPath: "/song.rpp")).isEmpty)
}

@Test func wideDirectoryRespectsEntryLimit() throws {
    let f = try Fixture()
    for i in 0..<20 { try f.file("\(i).wav") }
    var request = ScanRequest()
    request.samples = [f.root]
    request.maximumEntries = 5
    request.completeFileScan = false
    let report = Scanner().scan(request)
    #expect(report.assets.count <= 4)
    #expect(report.issues.contains { $0.reason.contains("Entry limit") })
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ScanProgress] = []
    func append(_ value: ScanProgress) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshot: [ScanProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

@Test func progressHasRealPhaseTotalsAndPreservesResults() throws {
    let f = try Fixture()
    try f.file("Samples/One.wav"); try f.file("Samples/Two.wav")
    try f.file("Projects/Song.rpp", "<REAPER_PROJECT\n<TRACK\n<ITEM\n<SOURCE WAVE\nFILE \"../Samples/One.wav\"\n>\n>\n>\n>")
    var request = ScanRequest(); request.samples = [f.root.appendingPathComponent("Samples")]; request.projects = [f.root.appendingPathComponent("Projects")]
    let recorder = ProgressRecorder()
    let report = Scanner().scan(request, progress: recorder.append)
    let updates = recorder.snapshot
    #expect(report.assets.count == 2 && report.projects.count == 1)
    #expect(report.sampleInclusions.filter { $0.status == "referenced" }.count == 1)
    #expect(updates.first?.phase == .discovering && updates.first?.total == nil)
    #expect(updates.last?.phase == .complete && updates.last?.fraction == 1)
    #expect(updates.map(\.sequence) == Array(1...updates.count))
    for phase in [ScanProgress.Phase.discovering, .inspecting, .matching] {
        let events = updates.filter { $0.phase == phase }
        #expect(!events.isEmpty)
        #expect(events.map(\.completed) == events.map(\.completed).sorted())
        #expect(events.allSatisfy { $0.total == nil || $0.completed <= $0.total! })
    }
    #expect(updates.filter { $0.phase == .inspecting }.allSatisfy { $0.total == 1 })
    #expect(updates.filter { $0.phase == .matching }.allSatisfy { $0.total == 3 })
}

@Test func progressCompletesEmptyUnavailableAndTruncatedScansHonestly() throws {
    let f = try Fixture(); try f.file("One.wav"); try f.file("Two.wav")
    var unavailable = ScanRequest(); unavailable.samples = [f.root.appendingPathComponent("absent")]
    var truncated = ScanRequest(); truncated.samples = [f.root]; truncated.maximumEntries = 1; truncated.completeFileScan = false
    for request in [ScanRequest(), unavailable, truncated] {
        let recorder = ProgressRecorder(); let result = Scanner().scan(request, progress: recorder.append)
        #expect(recorder.snapshot.last?.phase == .complete)
        #expect(recorder.snapshot.allSatisfy { $0.total == nil || $0.completed <= $0.total! })
        if !request.samples.isEmpty { #expect(!result.issues.isEmpty) }
    }
}

private final class InventoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [InventorySnapshot] = []
    func append(_ value: InventorySnapshot) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var snapshot: [InventorySnapshot] { lock.lock(); defer { lock.unlock() }; return values }
}

@Test func basicInventoryPrecedesProjectAnalysis() throws {
    let f = try Fixture()
    try f.file("Samples/One.wav", "sample bytes")
    try f.file("Projects/Song.rpp", "<REAPER_PROJECT\n>")
    var request = ScanRequest(); request.samples = [f.root.appendingPathComponent("Samples")]; request.projects = [f.root.appendingPathComponent("Projects")]
    let inventory = InventoryRecorder()
    let report = Scanner().scan(request, inventory: inventory.append) { update in
        if update.phase == .inspecting { #expect(inventory.snapshot.last?.discoveryComplete == true) }
    }
    #expect(inventory.snapshot.first?.assets.count == 1)
    #expect(inventory.snapshot.last?.assets.first?.logicalBytes == 12)
    #expect(report.assets.count == 1 && report.projects.count == 1)
    let partial = ScanReport(inventory: inventory.snapshot.last!)
    #expect(partial.sampleInclusions.isEmpty && partial.projects.isEmpty)
    #expect(inventory.snapshot.last!.elapsedSeconds <= report.durationSeconds)
}

@Test func explicitSampleRootsOverrideBroadLibraryRoots() throws {
    let f = try Fixture()
    try f.file("Sounds/Individual/Kick.wav")
    try f.file("Sounds/Kontakt/Strings/C3.wav")
    try f.file("Sounds/Kontakt/Banjo.nki")
    try f.file("Sounds/SINE/Brass/C3.wav")
    var request = ScanRequest()
    request.libraries = [f.root.appendingPathComponent("Sounds"), f.root.appendingPathComponent("Sounds/Individual/Nested Libraries")]
    request.samples = [f.root.appendingPathComponent("Sounds/Individual")]
    try f.file("Sounds/Individual/Nested Libraries/Hidden/C3.wav")
    try f.file("Sounds/Individual/Nested Libraries/Hidden/Accordion.nki")
    let report = Scanner().scan(request)
    #expect(report.assets.filter { $0.kind == .sample }.map(\.name) == ["Kick"])
    #expect(!report.assets.contains { $0.kind == .library && $0.name == "Individual" })
    #expect(report.assets.contains { $0.kind == .library && $0.name == "Hidden" })
    #expect(report.assets.contains { $0.kind == .library && $0.name == "Kontakt" })
}

@Test func pluginProductsPreserveFormatsVersionsAndPublisherCollisions() {
    func plugin(_ name: String, _ format: String, _ publisher: String?) -> Asset {
        Asset(kind: .plugin, path: "/fixtures/\(name).\(format)", name: name, format: format, bundleIdentifier: publisher, logicalBytes: nil, classification: "test")
    }
    let inputs = [plugin("Echo 2", "component", "com.maker.echo.au"), plugin("Echo 2 VST3", "vst3", "com.maker.echo.vst3"), plugin("Echo 2", "clap", "com.maker.echo.clap"), plugin("Echo 3", "vst3", "com.maker.echo3")]
    let products = PluginProduct.group(inputs)
    #expect(products.count == 2)
    #expect(products.first?.installations.count == 3)
    #expect(products.first?.formats == "AU, CLAP, VST3")
    #expect(PluginProduct.group([plugin("Table", "vst3", "com.vendor.table"), plugin("Table", "component", "com.vendor.tableau")]).count == 2)
    let collisions = PluginProduct.group(inputs + [plugin("Echo 2", "vst", "org.other.echo")])
    #expect(collisions.count == 3)
    #expect(PluginProduct.group([plugin("Echo", "vst3", "com.github.vendorA.echo.vst3"), plugin("Echo", "component", "com.github.vendorB.echo.au"), plugin("Echo", "clap", nil)]).count == 3)
}

@Test func kontaktPatchNamesDoNotClassifyParent() throws {
    let f = try Fixture()
    _ = try f.file("Libraries/Una Corda/Una Corda.nicnt",
        "<ProductHints><Product><Name>Una Corda</Name><Company>Native Instruments</Company></Product></ProductHints>")
    try f.file("Libraries/Una Corda/Instruments/Organ Strings.nki")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let asset = try #require(Scanner().scan(request).assets.first { $0.name == "Una Corda" })
    #expect(asset.libraryMetadata?.tags == [])
    #expect(asset.libraryMetadata?.instruments.first?.tags.contains("Organ") == true)
    #expect(asset.libraryMetadata?.instruments.first?.tags.contains("Strings") == true)

    // Cached payloads from older scans may contain rolled-up patch descriptors.
    var cached = try #require(asset.libraryMetadata)
    cached.tags = ["Organ", "Strings"]
    #expect(cached.productTags(productName: "Una Corda") == [])
}

@Test func kontaktVendorCategoriesRequireExactFilesAndSnapshotsStayPatchLocal() throws {
    let f = try Fixture()
    let piano = try f.file("Libraries/Una Corda/Instruments/Organ Strings.nki", "piano")
    let snapshot = try f.file("Libraries/Una Corda/Snapshots/Glass Strings.nksn", "snapshot")
    let strings = try f.file("Libraries/Chamber Strings/Instruments/Violins.nki", "strings")
    let mismatch = try f.file("Libraries/Brass/Instruments/Horns.nki", "brass")
    let mysteryA = try f.file("Libraries/Mystery/Instruments/A.nki", "a")
    let mysteryB = try f.file("Libraries/Mystery/Instruments/B.nki", "b")
    let database = f.root.appendingPathComponent("komplete.db3")
    var db: OpaquePointer?; #expect(sqlite3_open(database.path, &db) == SQLITE_OK); defer { if let db { sqlite3_close(db) } }
    #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK)
    let schema = """
    CREATE TABLE k_sound_info(id INTEGER PRIMARY KEY,file_name TEXT,file_ext TEXT,file_size INTEGER,mod_date INTEGER,vendor TEXT,bank_chain_id INTEGER);
    CREATE TABLE k_bank_chain(id INTEGER PRIMARY KEY,entry1 TEXT);
    CREATE TABLE k_sound_info_category(sound_info_id INTEGER,category_id INTEGER);
    CREATE TABLE k_category(id INTEGER PRIMARY KEY,category TEXT,subcategory TEXT,subsubcategory TEXT);
    INSERT INTO k_category VALUES(1,'Piano','Keys','Upright Piano');
    INSERT INTO k_category VALUES(2,'Synth Pad','Soundscapes','Glassy');
    INSERT INTO k_category VALUES(3,'Strings','Orchestral','Violins');
    INSERT INTO k_category VALUES(4,'Brass','Orchestral','Horns');
    INSERT INTO k_category VALUES(5,'Organ','Misleading','Stale Duplicate');
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
    func add(_ id: Int, _ file: URL, _ ext: String, category: Int, product: String, vendor: String,
             sizeAdjustment: Int64 = 0) throws {
        let stamp = try #require(LibraryScanJournal.stamp(file.path))
        let modified = stamp.modifiedSeconds * 1_000_000_000 + stamp.modifiedNanoseconds
        let escaped = file.path.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO k_bank_chain VALUES(\(id),'\(product)');"
            + "INSERT INTO k_sound_info VALUES(\(id),'\(escaped)','\(ext)',\(stamp.size + sizeAdjustment),\(modified),'\(vendor)',\(id));"
            + "INSERT INTO k_sound_info_category VALUES(\(id),\(category));"
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }
    try add(1, piano, "nki", category: 1, product: "Una Corda", vendor: "Native Instruments")
    try add(2, snapshot, "nksn", category: 2, product: "Una Corda", vendor: "Native Instruments")
    try add(3, strings, "nki", category: 3, product: "Chamber Strings", vendor: "Spitfire Audio")
    try add(4, mismatch, "nki", category: 4, product: "Brass Collection", vendor: "Fixture Brass", sizeAdjustment: 1)
    try add(5, piano, "nki", category: 5, product: "Wrong Product", vendor: "Wrong Vendor", sizeAdjustment: 1)
    try add(6, mysteryA, "nki", category: 2, product: "Alchemia", vendor: "Song Athletics")
    try add(7, mysteryB, "nki", category: 2, product: "Alchemia", vendor: "Song Athletics")
    #expect(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db); db = nil
    for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: database.path + suffix) }
    let databaseStamp = try #require(LibraryScanJournal.stamp(database.path))

    func asset(_ name: String, instruments: [LibraryInstrument], tags: [String], evidence: LibraryIdentity.Evidence = .manifest) -> Asset {
        var value = Asset(kind: .library, path: "/\(name).nicnt", name: name, format: "Kontakt",
            bundleIdentifier: nil, logicalBytes: nil, classification: evidence == .manifest ? "identifiedLibrary" : "needsIdentification")
        value.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: evidence == .manifest ? "Fixture" : "Unknown maker", summary: "",
            instruments: instruments, tags: tags, source: "fixture",
            identity: LibraryIdentity(evidence: evidence, productID: evidence == .manifest ? "kontakt:\(name)" : nil, installationRoot: "/\(name)"))
        return value
    }
    let source = [
        asset("Una Corda", instruments: [
            LibraryInstrument(name: "Organ Strings", path: piano.path, tags: ["Organ", "Strings"]),
            LibraryInstrument(name: "Glass Strings", path: snapshot.path, tags: ["Strings"])
        ], tags: ["Organ", "Strings"]),
        asset("Chamber Strings", instruments: [LibraryInstrument(name: "Violins", path: strings.path, tags: ["Violin"])], tags: ["Strings"]),
        asset("Brass", instruments: [LibraryInstrument(name: "Horns", path: mismatch.path, tags: ["Horn"])], tags: ["Brass"], evidence: .proposed),
        asset("Mystery", instruments: [
            LibraryInstrument(name: "A", path: mysteryA.path, tags: []),
            LibraryInstrument(name: "B", path: mysteryB.path, tags: [])
        ], tags: [], evidence: .proposed),
        asset("Mixed", instruments: [
            LibraryInstrument(name: "Piano", path: piano.path, tags: []),
            LibraryInstrument(name: "Strings", path: strings.path, tags: [])
        ], tags: [], evidence: .proposed)
    ]
    let enriched = KontaktCategoryReader.enrich(source, database: database)
    let unchangedStamp = try #require(LibraryScanJournal.stamp(database.path))
    #expect(unchangedStamp.modifiedSeconds == databaseStamp.modifiedSeconds)
    #expect(unchangedStamp.modifiedNanoseconds == databaseStamp.modifiedNanoseconds)
    let una = try #require(enriched.first { $0.name == "Una Corda" }?.libraryMetadata)
    #expect(una.instruments.first { $0.path == piano.path }?.tags == ["Keys", "Piano", "Upright Piano"])
    #expect(una.instruments.first { $0.path == snapshot.path }?.tags == ["Glassy", "Soundscapes", "Synth Pad"])
    #expect(una.productTags(productName: "Una Corda") == ["Keys", "Piano", "Upright Piano"])
    #expect(!una.productTags(productName: "Una Corda").contains("Organ"))
    let chamber = try #require(enriched.first { $0.name == "Chamber Strings" }?.libraryMetadata)
    #expect(chamber.productTags(productName: "Chamber Strings") == ["Orchestral", "Strings", "Violins"])
    let brass = try #require(enriched.first { $0.name == "Brass" }?.libraryMetadata)
    #expect(brass.instruments.first?.tags == ["Horn"])
    #expect(brass.productTags(productName: "Brass") == ["Brass"])
    #expect(brass.identity?.evidence == .proposed)
    let identified = try #require(enriched.first { $0.name == "Alchemia" })
    #expect(identified.libraryMetadata?.maker == "Song Athletics")
    #expect(identified.libraryMetadata?.identity?.evidence == .vendorCatalog)
    #expect(identified.libraryMetadata?.identity?.productID == nil)
    #expect(enriched.first { $0.name == "Mixed" }?.libraryMetadata?.identity?.evidence == .proposed)

    let suggested = MusicalMetadata.suggested(name: "Una Corda", tags: una.productTags(productName: "Una Corda"), kind: .library)
    let explicit = suggested.applying(MusicalMetadata(fields: ["instrument": ["Prepared Piano"]]))
    #expect(explicit[.instrument] == ["Prepared Piano"])
}

@Test func fabFilterFormatAndMonoBundleAliasesRemainOneVersionedProduct() {
    func plugin(_ format: String, _ id: String, mono: Bool = false) -> Asset {
        Asset(kind: .plugin, path: "/fixtures/FabFilter Pro-C 2\(mono ? " (Mono)" : "").\(format)",
            name: "FabFilter Pro-C 2\(mono ? " (Mono)" : "")", format: format,
            bundleIdentifier: id, logicalBytes: nil, classification: "test")
    }
    let proC2 = [
        plugin("aaxplugin", "com.fabfilter.Pro-C.AAX.2"),
        plugin("component", "com.fabfilter.Pro-C.AU.2"),
        plugin("clap", "com.fabfilter.Pro-C.Clap.2"),
        plugin("vst", "com.fabfilter.Pro-C.Vst.2"),
        plugin("vst3", "com.fabfilter.Pro-C.Vst3.2"),
        plugin("vst", "com.fabfilter.Pro-C.Mono.Vst.2", mono: true)
    ]
    let grouped = PluginProduct.group(proC2)
    #expect(grouped.count == 1)
    #expect(grouped[0].installations.count == 6)
    #expect(grouped[0].formats == "AAX, AU, CLAP, VST2, VST3")

    var cachedSplit = proC2
    for index in cachedSplit.indices { cachedSplit[index].pluginProductID = "legacy-format-\(index)" }
    let repairedCachedPresentation = PluginProduct.group(cachedSplit)
    #expect(repairedCachedPresentation.count == 1)
    #expect(repairedCachedPresentation[0].id == cachedSplit.sorted { $0.path < $1.path }[0].pluginProductID)

    let proC3 = plugin("vst3", "com.fabfilter.Pro-C.Vst3.3")
    let otherPublisher = plugin("vst3", "org.other.Pro-C.Vst3.2")
    #expect(PluginProduct.group(proC2 + [proC3, otherPublisher]).count == 3)
}

@Test func reviewedVendorFormatAliasesPreserveProductsAndQualifiedVariants() {
    func plugin(_ name: String, _ format: String, _ id: String) -> Asset {
        Asset(kind: .plugin, path: "/fixtures/\(name).\(format)", name: name, format: format,
            bundleIdentifier: id, logicalBytes: nil, classification: "test")
    }
    let glue = ["au", "vst2", "aax", "vst3"].map {
        plugin("bx_glue", $0, "com.plugin-alliance.\($0).bxglue")
    }
    #expect(PluginProduct.group(glue).count == 1)
    #expect(PluginProduct.group(glue)[0].installations.count == 4)

    let digital = [
        plugin("bx_digital V3", "component", "com.plugin-alliance.au.bxdigitalv3"),
        plugin("bx_digital V3", "vst3", "com.plugin-alliance.vst3.bxdigitalv3"),
        plugin("bx_digital V3 mix", "aaxplugin", "com.plugin-alliance.aax.bxdigitalv3mix"),
        plugin("bx_digital V3 mix", "vst", "com.plugin-alliance.vst2.bxdigitalv3mix")
    ]
    let digitalProduct = PluginProduct.group(digital)
    #expect(digitalProduct.count == 1)
    #expect(digitalProduct[0].name == "bx_digital V3")
    #expect(digitalProduct[0].installations.map(\.name).contains("bx_digital V3 mix"))
    #expect(digitalProduct[0].installations.first?.path == digital.first?.path)
    let primaryOrderedPaths = digitalProduct[0].installations.map(\.path)
    #expect(primaryOrderedPaths.dropFirst().elementsEqual(primaryOrderedPaths.dropFirst().sorted()))

    let curve = [
        plugin("Chandler Limited Curve Bender", "component", "com.softube.CurveBender_VST_AU_Protect_AU"),
        plugin("Chandler Limited Curve Bender", "vst", "com.softube.CurveBender_VST_AU_Protect"),
        plugin("Chandler Limited Curve Bender", "vst3", "com.softube.CurveBender_VST_AU_Protect_VST3"),
        plugin("Chandler Limited Curve Bender", "aaxplugin", "com.softube.CurveBender_AAX_Protect")
    ]
    #expect(PluginProduct.group(curve).count == 1)
    let uad = plugin("Chandler Limited Curve Bender", "component", "com.uaudio.effects.38au")
    #expect(PluginProduct.group(curve + [uad]).count == 2)
}

@Test func bundledReviewedMetadataRequiresQualifiedProductIdentity() throws {
    func library(_ name: String, maker: String) -> Asset {
        var asset = Asset(kind: .library, path: "/fixtures/\(name)", name: name, format: "Kontakt",
            bundleIdentifier: nil, logicalBytes: nil, classification: "test")
        asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: maker, summary: "",
            instruments: [], tags: [], source: "fixture")
        return asset
    }
    let glade = library("Glade", maker: "Audio Imperia")
    let gladeSource = try #require(ProductTagSources.all.filter { $0.matches(glade) }.first)
    #expect(gladeSource.metadata[.instrument]?.contains("choir") == true)
    #expect(gladeSource.metadata[.instrument]?.contains("brass") == false)

    let straylight = library("Straylight", maker: "Native Instruments GmbH")
    let straylightSource = try #require(ProductTagSources.all.filter { $0.matches(straylight) }.first)
    #expect(straylightSource.metadata[.role]?.contains("granular synthesis") == true)
    #expect(ProductTagSources.all.filter { $0.matches(library("Straylight", maker: "Spitfire Audio")) }.isEmpty)

    let softube = Asset(kind: .plugin, path: "/fixtures/Curve.component", name: "Chandler Limited Curve Bender",
        format: "component", bundleIdentifier: "com.softube.CurveBender_VST_AU_Protect_AU",
        logicalBytes: nil, classification: "test")
    let uad = Asset(kind: .plugin, path: "/fixtures/Curve-UAD.component", name: "Chandler Limited Curve Bender",
        format: "component", bundleIdentifier: "com.uaudio.effects.38au", logicalBytes: nil, classification: "test")
    #expect(ProductTagSources.all.filter { $0.matches(softube) }.count == 1)
    #expect(ProductTagSources.all.filter { $0.matches(uad) }.isEmpty)
}

@Test func removalValidatesIdentityAndNeverExpandsTargets() throws {
    let f = try Fixture()
    try f.file("Plugins/Echo.component/Contents/marker")
    try f.file("Plugins/Echo.vst3/Contents/marker")
    var request = ScanRequest(); request.plugins = [f.root.appendingPathComponent("Plugins")]
    let assets = Scanner().scan(request).assets
    #expect(assets.allSatisfy { PluginRemoval.validationError($0) == nil })
    var called: [String] = []
    let result = PluginRemoval.perform([assets[0]]) { url in called.append(url.path); return "/fake-trash" }
    #expect(called == [assets[0].path] && result[0].succeeded)
    let failure = PluginRemoval.perform([assets[1]]) { _ in throw CocoaError(.fileWriteNoPermission) }
    #expect(!failure[0].succeeded && FileManager.default.fileExists(atPath: assets[1].path))
    let partial = PluginRemoval.perform(assets) { url in
        if url.path == assets[1].path { throw CocoaError(.fileWriteNoPermission) }
        return "/fake-trash"
    }
    #expect(partial.filter(\.succeeded).count == 1 && partial.filter { !$0.succeeded }.count == 1)
    let renamed = URL(fileURLWithPath: assets[0].path + ".old")
    try FileManager.default.moveItem(at: URL(fileURLWithPath: assets[0].path), to: renamed)
    try FileManager.default.createDirectory(atPath: assets[0].path, withIntermediateDirectories: false)
    #expect(PluginRemoval.validationError(assets[0]) != nil)
    let rejected = PluginRemoval.perform([assets[0]]) { _ in Issue.record("Changed bundle must not reach Trash"); return nil }
    #expect(!rejected[0].succeeded)
}

@Test func removalRejectsSymlinksSamplesAndMissingIdentity() throws {
    let f = try Fixture(); try f.file("Real.vst3/Contents/marker")
    let target = f.root.appendingPathComponent("Real.vst3")
    let link = f.root.appendingPathComponent("Alias.vst3")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let candidate = Asset(kind: .plugin, path: link.path, name: "Alias", format: "vst3", bundleIdentifier: nil, logicalBytes: nil, classification: "test", fileIdentity: PluginFileIdentity.read(target.path))
    #expect(PluginRemoval.validationError(candidate)?.contains("Linked") == true)
    let missing = Asset(kind: .plugin, path: target.path, name: "Real", format: "vst3", bundleIdentifier: nil, logicalBytes: nil, classification: "test")
    #expect(PluginRemoval.validationError(missing) != nil)
    let sample = Asset(kind: .sample, path: target.path, name: "Real", format: "vst3", bundleIdentifier: nil, logicalBytes: nil, classification: "test")
    #expect(PluginRemoval.validationError(sample) != nil)
}

@Test func sampleBudgetCannotStarveProjectDiscovery() throws {
    let f = try Fixture(); for i in 0..<12 { try f.file("Samples/S\(i).wav") }
    try f.file("Projects/Session.rpp", "<REAPER_PROJECT\n>\n")
    var request = ScanRequest(); request.maximumEntries = 5
    request.completeFileScan = false
    request.samples = [f.root.appendingPathComponent("Samples")]; request.projects = [f.root.appendingPathComponent("Projects")]
    let report = Scanner().scan(request)
    #expect(report.issues.contains { $0.reason.contains("Entry limit") })
    #expect(report.projects.count == 1)
}

@Test func completeProjectScanContinuesPastDiagnosticEntryBudget() throws {
    let f = try Fixture()
    for i in 0..<8 { try f.file("Projects/Other/Folder\(i)/scratch.txt") }
    try f.file("Projects/Z-Later.rpp", "<REAPER_PROJECT\n>\n")
    var request = ScanRequest()
    request.projects = [f.root.appendingPathComponent("Projects")]
    request.maximumEntries = 3
    let complete = Scanner().scan(request)
    #expect(complete.projects.contains { $0.path.hasSuffix("Z-Later.rpp") })
    #expect(!complete.issues.contains { $0.reason.contains("Entry limit") })
    request.completeProjectScan = false
    request.completeFileScan = false
    #expect(Scanner().scan(request).issues.contains { $0.reason.contains("Entry limit") })
}

@Test func completeCollectionTraversalPassesDiagnosticEntryAndDepthLimits() throws {
    let f = try Fixture()
    let deep = Array(repeating: "Nested", count: 66).joined(separator: "/")
    _ = try f.file("Samples/\(deep)/Deep.wav")
    _ = try f.file("Projects/\(deep)/Deep.rpp", "<REAPER_PROJECT\n>\n")
    _ = try f.file("Plugins/\(deep)/Deep.vst3/Contents/Info.plist", "fixture")
    var request = ScanRequest()
    request.samples = [f.root.appendingPathComponent("Samples")]
    request.projects = [f.root.appendingPathComponent("Projects")]
    request.plugins = [f.root.appendingPathComponent("Plugins")]
    request.maximumEntries = 2; request.maximumDepth = 1
    let complete = Scanner().scan(request)
    #expect(complete.assets.contains { $0.kind == .sample && $0.path.hasSuffix("Deep.wav") })
    #expect(complete.assets.contains { $0.kind == .plugin && $0.path.hasSuffix("Deep.vst3") })
    #expect(complete.projects.contains { $0.path.hasSuffix("Deep.rpp") })
    #expect(!complete.issues.contains { $0.reason.contains("limit reached") })
    request.completeFileScan = false
    let bounded = Scanner().scan(request)
    #expect(bounded.issues.contains { $0.reason.contains("limit reached") })
}

@Test func soundtoysMiddleFormatIDsGroupWithoutMergingDeluxe() {
    var assets: [Asset] = []
    for (name, product) in [("Devil-Loc", "DevilLoc"), ("Devil-Loc_Deluxe", "DevilLocDeluxe")] {
        for (format, token) in [("component", "audiounit"), ("vst", "vst"), ("vst3", "vst3"), ("aaxplugin", "aax")] {
            assets.append(Asset(kind: .plugin, path: "/fixture/\(name).\(format)", name: name, format: format,
                bundleIdentifier: "com.soundtoys.\(token).\(product)", logicalBytes: nil, classification: "test"))
        }
    }
    let products = PluginProduct.group(assets)
    #expect(products.count == 2 && products.allSatisfy { $0.installations.count == 4 && $0.formats == "AAX, AU, VST2, VST3" })
    assets.append(Asset(kind: .plugin, path: "/other/Devil-Loc.vst3", name: "Devil-Loc", format: "vst3", bundleIdentifier: "com.other.vst3.DevilLoc", logicalBytes: nil, classification: "test"))
    #expect(PluginProduct.group(assets).count == 3)
}

@Test func scopedScannerKeepsNestedRootOwnershipAndSkipsOtherRoots() throws {
    let f = try Fixture()
    try f.file("Sounds/Loose/Kick.wav")
    try f.file("Sounds/Loose/Nested Library/Patch.nki")
    try f.file("Sounds/Loose/Nested Library/C3.wav")
    try f.file("Sounds/Strings/Violin.nki")
    var request = ScanRequest()
    request.samples = [f.root.appendingPathComponent("Sounds/Loose")]
    request.libraries = [f.root.appendingPathComponent("Sounds"), f.root.appendingPathComponent("Sounds/Loose/Nested Library")]
    request.plugins = [f.root.appendingPathComponent("MissingPlugins")]
    request.projects = [f.root.appendingPathComponent("MissingProjects")]
    let sample = Scanner().scan(request, scannedKinds: [.sample])
    #expect(sample.assets.map(\.name) == ["Kick"])
    #expect(sample.issues.allSatisfy { $0.kind == .sample && !$0.path.contains("MissingPlugins") })
    let libraries = Scanner().scan(request, scannedKinds: [.library])
    #expect(libraries.assets.allSatisfy { $0.kind == .library && $0.name != "Loose" })
    #expect(libraries.assets.contains { $0.name == "Nested Library" })
    #expect(libraries.projects.isEmpty && !libraries.issues.contains { $0.path.contains("MissingProjects") || $0.path.contains("MissingPlugins") })
    let plugins = Scanner().scan(request, scannedKinds: [.plugin])
    #expect(plugins.assets.isEmpty && plugins.projects.isEmpty && plugins.issues.count == 1 && plugins.issues[0].kind == .plugin)
}
