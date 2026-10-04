import Foundation
import Testing
import Darwin
@testable import SimplifyCore

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

@Test func pluginBundleSizeCountsHardLinksOnceAndRejectsLinksAndDepth() throws {
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
    try FileManager.default.createSymbolicLink(atPath: internalLink.path,
        withDestinationPath: "../../../__Pace_Eden.bundle/Contents/Resources/Signatures/codesign.dsig")
    pass = PluginBundleSize.Pass()
    #expect(PluginBundleSize.measure(bundle, pass: &pass).bytes == 104)
    try FileManager.default.removeItem(at: internalLink)
    try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("Contents/External"), withDestinationURL: file)
    pass = PluginBundleSize.Pass()
    #expect(PluginBundleSize.measure(bundle, pass: &pass).bytes == nil)
    try FileManager.default.removeItem(at: bundle.appendingPathComponent("Contents/External"))
    try FileManager.default.createSymbolicLink(atPath: internalLink.path, withDestinationPath: "../Missing")
    pass = PluginBundleSize.Pass()
    let dangling = PluginBundleSize.measure(bundle, pass: &pass)
    #expect(dangling.bytes == nil && dangling.issue != nil)
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
    #expect(report.assets.first { $0.kind == .library }?.logicalBytes == nil)
    #expect(report.issues.contains { $0.kind == .library && $0.reason.contains("Library size depth limit") })
}

@Test func ambiguousManifestFolderDoesNotClaimOneLibrarySize() throws {
    let f = try Fixture()
    let manifest = "<ProductHints><Product><Name>Shared</Name><Company>Example Audio</Company></Product></ProductHints>"
    _ = try f.file("Libraries/Shared/One.nicnt", manifest)
    _ = try f.file("Libraries/Shared/Two.nicnt", manifest)
    _ = try f.file("Libraries/Shared/Samples/C3.wav", "sample")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let report = Scanner().scan(request, scannedKinds: [.library])
    #expect(report.assets.allSatisfy { $0.logicalBytes == nil })
    #expect(report.issues.contains { $0.reason.contains("Multiple Kontakt manifests") })
}

@Test func nestedManifestRootsNeverDoubleCountLibraryFiles() throws {
    let f = try Fixture()
    _ = try f.file("Libraries/Parent/Parent.nicnt", "<ProductHints><Product><Name>Parent</Name><Company>Example Audio</Company></Product></ProductHints>")
    _ = try f.file("Libraries/Parent/Child/Child.nicnt", "<ProductHints><Product><Name>Child</Name><Company>Example Audio</Company></Product></ProductHints>")
    _ = try f.file("Libraries/Parent/Child/Samples/C3.wav", "sample")
    var request = ScanRequest(); request.libraries = [f.root.appendingPathComponent("Libraries")]
    let libraries = Scanner().scan(request, scannedKinds: [.library]).assets.filter { $0.kind == .library }
    #expect(libraries.count == 2)
    #expect(libraries.allSatisfy { $0.logicalBytes == nil })
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
    #expect(Set(result.projects.map(\.coverage)) == ["failed", "unsupported"])
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
    var truncated = ScanRequest(); truncated.samples = [f.root]; truncated.maximumEntries = 1
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
    request.samples = [f.root.appendingPathComponent("Samples")]; request.projects = [f.root.appendingPathComponent("Projects")]
    let report = Scanner().scan(request)
    #expect(report.issues.contains { $0.reason.contains("Entry limit") })
    #expect(report.projects.count == 1)
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
