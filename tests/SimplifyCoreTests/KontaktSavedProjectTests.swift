import Foundation
import Testing
@testable import SimplifyCore

private func little(_ value: Int, _ width: Int = 4) -> Data {
    Data((0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
}
private func savedItem(_ properties: Data, children: [Data] = []) -> Data {
    let tail = little(1) + little(children.count)
        + children.reduce(Data()) { $0 + Data(repeating: 0, count: 12) + $1 }
    return little(40 + properties.count + tail.count, 8) + little(1) + Data("hsin".utf8)
        + Data(repeating: 0, count: 24) + properties + tail
}
private func savedProperty(_ type: Int, _ payload: Data) -> Data {
    let parent = type == 1 ? Data() : savedProperty(1, little(1))
    return little(20 + parent.count + payload.count, 8) + Data("DSIN".utf8)
        + little(type) + little(1) + parent + payload
}
private func savedLibrary(_ id: String) -> Data {
    let raw = id.data(using: .utf16LittleEndian)!
    return savedItem(savedProperty(106, little(1) + little(1) + little(1) + little(1)
        + little(raw.count / 2) + raw + Data(repeating: 0, count: 12)))
}
private func liveDocument(_ ids: [String]) -> Data {
    let state = savedItem(savedProperty(1, little(1)), children: ids.map(savedLibrary))
    let hex = state.map { String(format: "%02x", $0) }.joined()
    let uid = ["1448301646", "1766537323", "1869509729", "1802772536"]
        .enumerated().map { "<Fields.\($0.offset) Value=\"\($0.element)\"/>" }.joined()
    let xml = """
    <Ableton MajorVersion="5" MinorVersion="12.0_12402" Creator="Ableton Live 12.1">
    <LiveSet><Tracks><MidiTrack><DeviceChain><DeviceChain><Devices><PluginDevice><PluginDesc>
    <Vst3PluginInfo><Name Value="Kontakt 8"/><Uid>\(uid)</Uid><Preset><Vst3Preset>
    <ProcessorState>\(hex)</ProcessorState></Vst3Preset></Preset></Vst3PluginInfo>
    </PluginDesc></PluginDevice></Devices></DeviceChain></DeviceChain></MidiTrack></Tracks></LiveSet></Ableton>
    """
    return Data(xml.utf8)
}

@Test func kontaktSavedProjectMixedIDsBindOnlyExactInstalledLibraryAndRetainHistory() async throws {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyStoreTests/prism-kontakt-project-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = root.appendingPathComponent("Fixture.nicnt")
    let xml = "<ProductHints><Product><UPID>00000000-0000-0000-0000-000000000000</UPID><Name>Fixture</Name><Company>Example</Company><SNPID>P44</SNPID></Product></ProductHints>"
    try Data(xml.utf8).write(to: manifest)
    var asset = Asset(kind: .library, path: manifest.path, name: "Fixture", format: "Kontakt",
                      bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Example", summary: "",
        instruments: [], tags: [], source: "fixture",
        identity: LibraryIdentity(evidence: .manifest, productID: "fixture-p44", installationRoot: root.path))
    let project = root.appendingPathComponent("Mixed.als")
    try liveDocument(["P44", "Z999", "P44"]).write(to: project)
    let parsed = ProjectReader.read(project)
    #expect(parsed.coverage == "partial")
    #expect(parsed.kontaktStates?.count == 1)
    #expect(parsed.kontaktStates?.first?.libraryIDs == ["P44", "Z999"])
    var request = ScanRequest(); request.libraries = [root]; request.projects = [root]
    let scope = CatalogScope(request)
    let store = CatalogStore(url: root.appendingPathComponent("catalog.sqlite"))
    let now = Date().addingTimeInterval(5)
    let input = ScanReport(schemaVersion: 1, assets: [asset], projects: [parsed], sampleInclusions: [], issues: [], durationSeconds: 0)
    let first = try await store.ingest(input, scope: scope, at: now)
    let subject = try #require(first.report.assets.first?.catalogID)
    let outcomes = try #require(first.report.projects.first?.kontaktOutcomes)
    #expect(outcomes.count == 2)
    #expect(outcomes.first(where: { $0.libraryID == "P44" })?.catalogID == subject)
    #expect(outcomes.first(where: { $0.libraryID == "Z999" })?.status == "unknownLibraryID")
    #expect(try await store.dateSummary(for: subject, asOf: now).lastUsed == parsed.projectModifiedAt)
    _ = try await store.ingest(input, scope: scope, at: now.addingTimeInterval(1))
    #expect(try await store.dateEvidence(for: subject, asOf: now.addingTimeInterval(1)).count == 1)
    let removed = ScanReport(schemaVersion: 1, assets: [asset], projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
    _ = try await store.ingest(removed, scope: scope, at: now.addingTimeInterval(2))
    #expect(try await store.dateSummary(for: subject, asOf: now.addingTimeInterval(2)).lastUsed == parsed.projectModifiedAt)
}

@Test func nativeKontaktSavedHostStatesWhenEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_PROJECT_RUNTIME"] == "1" else { return }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let live = ProjectReader.read(cwd.appendingPathComponent("build/usage-controls/kontakt-active-controls/Empty.als"))
    #expect(live.kontaktStates?.count == 1)
    #expect(live.kontaktStates?.first?.emptyRack == true)
    let accordion = try KontaktStateReader.read(BoundedFile.read(cwd.appendingPathComponent("build/usage-controls/kontakt-active-controls/Accordion.state"), limit: KontaktStateReader.maximumBytes))
    #expect(accordion.libraryIDs == ["P44"])
    guard let loadedPath = ProcessInfo.processInfo.environment["PRISM_KONTAKT_CPR_LOADED"],
          let emptyPath = ProcessInfo.processInfo.environment["PRISM_KONTAKT_CPR_EMPTY"] else { return }
    let loaded = ProjectReader.read(URL(fileURLWithPath: loadedPath))
    let empty = ProjectReader.read(URL(fileURLWithPath: emptyPath))
    #expect(loaded.kontaktStates?.count == 1 && loaded.kontaktStates?.first?.libraryIDs == ["225"])
    #expect(empty.kontaktStates?.count == 1 && empty.kontaktStates?.first?.emptyRack == true)

    // A complete descriptor copied into the opaque Kontakt payload must not
    // become a second instance; bytes appended outside RIF2 are invalid too.
    let loadedBytes = try Data(contentsOf: URL(fileURLWithPath: loadedPath))
    let emptyBytes = try Data(contentsOf: URL(fileURLWithPath: emptyPath))
    let marker = Data([7]) + Data("Plugin\0".utf8) + Data([0, 2, 0, 6])
    let name = try #require(emptyBytes.range(of: Data("Kontakt 8\0".utf8)))
    let group = try #require(emptyBytes.range(of: marker, options: .backwards, in: 0..<name.lowerBound))
    let nis = try #require(loadedBytes.range(of: Data("hsin".utf8), in: group.lowerBound..<loadedBytes.count))
    let copyLength = 16_000
    guard group.lowerBound + copyLength < emptyBytes.count,
          nis.lowerBound + 100_000 + copyLength < loadedBytes.count else { throw ProjectReadError.malformed }
    var withEmbeddedDecoy = loadedBytes
    withEmbeddedDecoy.replaceSubrange(nis.lowerBound + 100_000..<nis.lowerBound + 100_000 + copyLength,
        with: emptyBytes[group.lowerBound..<group.lowerBound + copyLength])
    #expect(try CubaseKontaktStateReader.read(withEmbeddedDecoy).count == 1)
    #expect(throws: (any Error).self) {
        try CubaseKontaktStateReader.read(loadedBytes + emptyBytes[group.lowerBound..<group.lowerBound + copyLength])
    }
}

@Test func legacyProjectReportDecodesWithoutKontaktClaims() throws {
    let old = Data("""
        {"path":"/fixture.als","adapter":"als","coverage":"partial","projectModifiedAt":null,"references":[],"limitations":[]}
        """.utf8)
    let report = try JSONDecoder().decode(ProjectReport.self, from: old)
    #expect(report.kontaktStates == nil && report.kontaktOutcomes == nil && report.sourceSHA256 == nil)
}

@Test func nativeSavedPluginAndSINEMembershipWhenEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cubase = ProjectReader.read(cwd.appendingPathComponent("build/usage-controls/20260926-125602/working/Cubase/Test.cpr"))
    #expect(cubase.pluginClasses?.isEmpty == false)
    let live = ProjectReader.read(cwd.appendingPathComponent("build/usage-controls/20260926-125602/working/Ableton/Test Project/Test.als"))
    #expect(live.pluginClasses?.isEmpty == false)
    let controlRoot = try #require(ProcessInfo.processInfo.environment["PRISM_SINE_CONTROL_PROJECTS"])
    let loaded = ProjectReader.read(URL(fileURLWithPath: controlRoot).appendingPathComponent("sinetest.cpr"))
    let empty = ProjectReader.read(URL(fileURLWithPath: controlRoot).appendingPathComponent("sinetest-empty.cpr"))
    #expect(loaded.sineInstrumentIDs == ["5108"])
    #expect(empty.sineInstrumentIDs == [])
}

@Test func nativeCubaseSavedPluginMembershipBindsExactCurrentClassWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let project = ProjectReader.read(cwd.appendingPathComponent("build/usage-controls/20260926-125602/working/Cubase/Test.cpr"))
    let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/Cubase 15/Cubase Pro VST3 Cache (arm64)/vst3plugins.xml")
    let classes = try CubasePluginCache.read(cacheURL)
    let saved = Set(project.pluginClasses?.map(\.classID) ?? [])
    let matches = classes.filter { saved.contains($0.cid) && $0.category == "Audio Module Class" &&
        FileManager.default.fileExists(atPath: $0.path) }
    let match = try #require(matches.first { candidate in matches.filter { $0.cid == candidate.cid }.count == 1 })
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyStoreTests/prism-cubase-saved-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var request = ScanRequest(); request.plugins = [URL(fileURLWithPath: match.path).deletingLastPathComponent()]
    request.projects = [URL(fileURLWithPath: project.path).deletingLastPathComponent()]
    let asset = Asset(kind: .plugin, path: match.path, name: match.name, format: "vst3",
        bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    let store = CatalogStore(url: root.appendingPathComponent("catalog.sqlite"))
    let report = ScanReport(schemaVersion: 1, assets: [asset], projects: [project],
        sampleInclusions: [], issues: [], durationSeconds: 0)
    let scope = CatalogScope(request)
    let result = try await store.ingest(report, scope: scope, at: Date())
    let node = try #require(result.report.assets.first?.catalogID)
    #expect(try await store.latestHostUsage(for: [node], asOf: Date(), savedProjectOnly: true)[Data(node.utf8)]?.eventDate == project.projectModifiedAt)
}

@Test func nativeLiveSavedPluginMembershipBindsExactCurrentClassWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let project = ProjectReader.read(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/usage-controls/20260926-125602/working/Ableton/Test Project/Baseline.als"))
    let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ableton/Live Database/Live-plugins-1.db")
    let saved = Set(project.pluginClasses?.map(\.classID) ?? [])
    let entries = try LivePluginCache.read(cacheURL).filter { saved.contains($0.classID) }
    let entry = try #require(entries.first { candidate in entries.filter { $0.classID == candidate.classID }.count == 1 })
    let bundle = URL(fileURLWithPath: entry.path)
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyStoreTests/prism-live-saved-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var request = ScanRequest(); request.plugins = [bundle.deletingLastPathComponent()]
    request.projects = [URL(fileURLWithPath: project.path).deletingLastPathComponent()]
    let asset = Asset(kind: .plugin, path: entry.path, name: bundle.deletingPathExtension().lastPathComponent,
        format: "vst3", bundleIdentifier: Bundle(url: bundle)?.bundleIdentifier,
        logicalBytes: nil, classification: "fixture")
    let store = CatalogStore(url: root.appendingPathComponent("catalog.sqlite"))
    let report = ScanReport(schemaVersion: 1, assets: [asset], projects: [project],
        sampleInclusions: [], issues: [], durationSeconds: 0)
    let scope = CatalogScope(request)
    let result = try await store.ingest(report, scope: scope, at: Date())
    let node = try #require(result.report.assets.first?.catalogID)
    #expect(try await store.latestHostUsage(for: [node], asOf: Date(), savedProjectOnly: true)[Data(node.utf8)]?.eventDate == project.projectModifiedAt)
}

@Test func nativeProToolsSavedPluginListRemovalWhenEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/usage-controls/20260926-125602/working/Pro Tools/Test")
    let baseline = try #require(ProToolsSavedPluginReader.read(Data(contentsOf: base.appendingPathComponent("Baseline.ptx"))))
    let removed = try #require(ProToolsSavedPluginReader.read(Data(contentsOf: base.appendingPathComponent("Diva-removed.ptx"))))
    #expect(baseline.count == 3 && removed.count == 2)
    #expect(baseline.contains { $0.name == "Diva" && $0.effectID == "com.u-he.Diva.aax.effect.id" })
    #expect(!removed.contains { $0.name == "Diva" })
    #expect(removed.map(\.effectID) == baseline.filter { $0.name != "Diva" }.map(\.effectID))
}

@Test func nativeProToolsSavedPluginDateBindsCurrentAAXWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/usage-controls/20260926-125602/working/Pro Tools/Test/Baseline.ptx")
    let loaded = ProjectReader.read(project)
    #expect(loaded.aaxPlugins?.contains { $0.name == "Diva" } == true)
    let bundle = URL(fileURLWithPath: "/Library/Application Support/Avid/Audio/Plug-Ins/Diva.aaxplugin")
    let id = try #require(Bundle(url: bundle)?.bundleIdentifier)
    let asset = Asset(kind: .plugin, path: bundle.path, name: "Diva", format: "aaxplugin",
        bundleIdentifier: id, logicalBytes: nil, classification: "fixture")
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyStoreTests/prism-ptx-saved-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var request = ScanRequest(); request.plugins = [bundle.deletingLastPathComponent()]
    request.projects = [project.deletingLastPathComponent()]
    let store = CatalogStore(url: root.appendingPathComponent("catalog.sqlite"))
    let report = ScanReport(schemaVersion: 1, assets: [asset], projects: [loaded], sampleInclusions: [], issues: [], durationSeconds: 0)
    let scope = CatalogScope(request)
    let snapshot = try await store.ingest(report, scope: scope, at: Date())
    let node = try #require(snapshot.report.assets.first?.catalogID)
    #expect(try await store.latestHostUsage(for: [node], asOf: Date(), savedProjectOnly: true)[Data(node.utf8)]?.eventDate == loaded.projectModifiedAt)
}

@Test func nativeLogicSavedAUReferencesAndDateWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/usage-controls/20260926-125602/working/Logic")
    let baseline = ProjectReader.read(base.appendingPathComponent("Baseline.logicx"))
    let removed = ProjectReader.read(base.appendingPathComponent("Diva-removed.logicx"))
    let diva = LogicSavedAUReader.Reference(type: "aumu", subtype: "DiVa", manufacturer: "UHfX")
    #expect(baseline.logicAUReferences?.contains(diva) == true)
    #expect(removed.logicAUReferences?.contains(diva) == false)
    let bundle = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components/Diva.component")
    let id = try #require(Bundle(url: bundle)?.bundleIdentifier)
    let asset = Asset(kind: .plugin, path: bundle.path, name: "Diva", format: "component",
        bundleIdentifier: id, logicalBytes: nil, classification: "fixture")
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyStoreTests/prism-logic-saved-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var request = ScanRequest(); request.plugins = [bundle.deletingLastPathComponent()]; request.projects = [base]
    let store = CatalogStore(url: root.appendingPathComponent("catalog.sqlite"))
    let scope = CatalogScope(request)
    let input = ScanReport(schemaVersion: 1, assets: [asset], projects: [baseline],
        sampleInclusions: [], issues: [], durationSeconds: 0)
    let saved = try await store.ingest(input, scope: scope, at: Date())
    let node = try #require(saved.report.assets.first?.catalogID)
    #expect(try await store.latestHostUsage(for: [node], asOf: Date(), savedProjectOnly: true)[Data(node.utf8)]?.eventDate == baseline.projectModifiedAt)
}
