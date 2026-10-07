import Foundation
import Testing
@testable import SimplifyCore

private func vst3Fixture() throws -> URL {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyVST3Tests/Module-" + UUID().uuidString + ".vst3", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    return root
}

@Test func vst3ModuleInfoReadsBoundedJSON5AndOnlyAudioModuleClasses() throws {
    let bundle = try vst3Fixture(); defer { try? FileManager.default.removeItem(at: bundle) }
    let json5 = """
    // Vendor-authored VST3 descriptor.
    { Classes: [
      { Category: 'Audio Module Class', Name: 'Widget', 'Sub Categories': ['Fx', 'Dynamics', 'Synth',], },
      { Category: 'Component Controller Class', Name: 'Widget Controller', 'Sub Categories': ['Reverb'], },
    ], }
    """
    try Data(json5.utf8).write(to: bundle.appendingPathComponent("Contents/Resources/moduleinfo.json"))
    let facts = try #require(VST3ModuleInfoReader.read(bundle: bundle))
    #expect(facts.subCategories == ["dynamics", "fx", "synth"])
    #expect(facts.metadata[.function] == ["dynamics", "fx"])
    #expect(facts.metadata[.instrument] == ["synth"])
    #expect(!facts.metadata.searchText.contains("compressor"))
    #expect(!facts.metadata.searchText.contains("piano"))
}
@Test func vst3ModuleInfoVendorUsesFactoryWhenClassesOmitItAndRejectsConflict() throws {
    let bundle = try vst3Fixture(); defer { try? FileManager.default.removeItem(at: bundle) }
    let url = bundle.appendingPathComponent("Contents/Resources/moduleinfo.json")
    try Data("{ 'Factory Info': { Vendor: 'Example Audio' }, Classes: [{ Category: 'Audio Module Class', Name: 'Synth' }] }".utf8).write(to: url)
    #expect(VST3ModuleInfoReader.read(bundle: bundle)?.vendor == "Example Audio")
    try Data("{ 'Factory Info': { Vendor: 'Example Audio' }, Classes: [{ Category: 'Audio Module Class', Vendor: 'Other Audio', 'Sub Categories': ['Synth'] }] }".utf8).write(to: url)
    #expect(VST3ModuleInfoReader.read(bundle: bundle)?.vendor == nil)
    try Data("{ Classes: [{ Category: 'Audio Module Class', Vendor: 'Example Audio', 'Sub Categories': ['Fx'] }, { Category: 'Audio Module Class', 'Sub Categories': ['Fx'] }] }".utf8).write(to: url)
    #expect(VST3ModuleInfoReader.read(bundle: bundle)?.vendor == nil)
}

@Test func vst3ModuleInfoUsesSharedCategoriesAndSkipsUnknownTokens() throws {
    let bundle = try vst3Fixture(); defer { try? FileManager.default.removeItem(at: bundle) }
    let json5 = """
    { Classes: [
      { Category: 'Audio Module Class', 'Sub Categories': ['Fx', 'Dynamics', 'Vendor Custom'] },
      { Category: 'Audio Module Class', 'Sub Categories': ['Fx', 'Reverb', 'Another Custom'] },
      { Category: 'Component Controller Class', 'Sub Categories': ['Synth'] }
    ] }
    """
    try Data(json5.utf8).write(to: bundle.appendingPathComponent("Contents/Resources/moduleinfo.json"))
    let facts = try #require(VST3ModuleInfoReader.read(bundle: bundle))
    #expect(facts.subCategories == ["fx"])
    #expect(facts.metadata[.function] == ["fx"])
    #expect(facts.metadata[.instrument] == nil)
}

@Test func vst3ModuleInfoSupportsLegacyPathAndRejectsNonVST3OrMalformedData() throws {
    let bundle = try vst3Fixture(); defer { try? FileManager.default.removeItem(at: bundle) }
    let legacy = bundle.appendingPathComponent("Contents/moduleinfo.json")
    try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ Classes: [{ Category: 'Audio Module Class', 'Sub Categories': ['Instrument'] }] }".utf8).write(to: legacy)
    #expect(VST3ModuleInfoReader.read(bundle: bundle)?.metadata[.instrument] == ["instrument"])
    #expect(VST3ModuleInfoReader.read(bundle: bundle.appendingPathExtension("component")) == nil)
    try Data(repeating: 65, count: VST3ModuleInfoReader.maximumBytes + 1).write(to: legacy)
    #expect(VST3ModuleInfoReader.read(bundle: bundle) == nil)
}

@Test func vst3CategoryFactsRoundTripInExistingAssetPayload() throws {
    let metadata = VST3CategoryMetadata(subCategories: ["Fx"], metadata: MusicalMetadata(fields: ["function": ["fx"]]))
    var asset = Asset(kind: .plugin, path: "/Plugins/Test.vst3", name: "Test", format: "vst3", bundleIdentifier: "com.example.test", logicalBytes: nil, classification: "plugin")
    asset.vst3Categories = metadata
    let decoded = try JSONDecoder().decode(Asset.self, from: JSONEncoder().encode(asset))
    #expect(decoded.vst3Categories == metadata)
}
