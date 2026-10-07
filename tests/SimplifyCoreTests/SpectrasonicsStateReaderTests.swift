import Foundation
import Testing
@testable import SimplifyCore

@Test func spectrasonicsPartBindingRejectsConflictingAndAmbiguousOwners() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyStoreTests/prism-spectra-binding-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func asset(_ name: String) throws -> Asset {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let preset = folder.appendingPathComponent("Shared.prt_omn")
        try Data("fixture".utf8).write(to: preset)
        var result = Asset(kind: .library, path: folder.path, name: name, format: "Spectrasonics",
                           bundleIdentifier: nil, logicalBytes: nil, classification: "needsIdentification")
        result.libraryMetadata = LibraryMetadata(player: "Omnisphere", maker: "Unknown maker", summary: "",
            instruments: [LibraryInstrument(name: "Shared", path: preset.path, tags: [])], tags: [], source: "fixture",
            identity: LibraryIdentity(evidence: .proposed, productID: "fixture:\(folder.path)",
                                      installationRoot: folder.path))
        return result
    }
    let first = try asset("First"), second = try asset("Second")
    let blank = SpectrasonicsStateReader.Part(slot: 0, name: "Shared", library: "",
                                              originalName: "", originalLibrary: "")
    let conflict = SpectrasonicsStateReader.Part(slot: 0, name: "Shared", library: "Other",
                                                 originalName: "", originalLibrary: "")
    #expect(SpectrasonicsLibraryIndex.resolve(part: blank, player: .omnisphere, assets: [first])?.asset.name == "First")
    #expect(SpectrasonicsLibraryIndex.resolve(part: blank, player: .omnisphere, assets: [first, second]) == nil)
    #expect(SpectrasonicsLibraryIndex.resolve(part: conflict, player: .omnisphere, assets: [first]) == nil)
    #expect(SpectrasonicsLibraryIndex.resolve(part: blank, player: .keyscape, assets: [first]) == nil)

    let product = root.appendingPathComponent("Omnisphere")
    let owned = product.appendingPathComponent("Settings Library/Patches/User/Owned")
    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
    let source = owned.appendingPathComponent("Original.prt_omn")
    try Data("original".utf8).write(to: source)
    let player = Asset(kind: .library, path: product.path, name: "Omnisphere", format: "Spectrasonics",
                       bundleIdentifier: nil, logicalBytes: nil, classification: "needsIdentification")
    var issues: [ScanIssue] = []
    let installed = SpectrasonicsLibraryIndex.discover(products: [player], issues: &issues)
    let ownedAsset = try #require(installed.first { $0.name == "Owned" })
    let part = SpectrasonicsStateReader.Part(slot: 0, name: "Original", library: "Owned",
                                             originalName: "", originalLibrary: "")
    #expect(SpectrasonicsLibraryIndex.resolve(part: part, player: .omnisphere, assets: [ownedAsset]) != nil)
    try Data("replacement has changed".utf8).write(to: source)
    #expect(!SpectrasonicsLibraryIndex.sourceMatches(ownedAsset))
    #expect(SpectrasonicsLibraryIndex.resolve(part: part, player: .omnisphere, assets: [ownedAsset]) == nil)
}

@Test func nativeSpectrasonicsOwnedStatesWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SPECTRASONICS_RUNTIME"] == "1",
          let directory = ProcessInfo.processInfo.environment["PRISM_SPECTRASONICS_FIXTURES"] else { return }
    let root = URL(fileURLWithPath: directory)
    let expectations: [(String, SpectrasonicsStateReader.Player, String, String)] = [
        ("omni-factory.cpr", .omnisphere, "AV │ Epic Vintage Ensemble Strings", "Analog Vibes"),
        ("omni-thirdparty.cpr", .omnisphere, "Bruises", "The Unfinished Omnisphere Ferox"),
        ("keyscape.cpr", .keyscape, "LA Custom C7 Grand Piano ", "Keyscape Library"),
        ("trillian.cpr", .trilian, "Talky Talk Funk", "Trilian Library"),
    ]
    for (filename, player, name, library) in expectations {
        let plugins = try CubaseKontaktStateReader.readPluginStates(
            BoundedFile.read(root.appendingPathComponent(filename), limit: CubaseKontaktStateReader.maximumBytes))
        let states = try plugins.compactMap(SpectrasonicsStateReader.read)
        #expect(states.count == 1)
        #expect(states.first?.player == player)
        #expect(states.first?.parts.first?.name == name)
        #expect(states.first?.parts.first?.library == library)
    }
    let initialized = try CubaseKontaktStateReader.readPluginStates(
        BoundedFile.read(root.appendingPathComponent("omni-empty.cpr"), limit: CubaseKontaktStateReader.maximumBytes))
    let reset = try #require(initialized.compactMap(SpectrasonicsStateReader.read).first)
    #expect(reset.parts.count == 8)
    #expect(reset.parts.allSatisfy { $0.name == "Default" && $0.library == "User" })

    if let steamPath = ProcessInfo.processInfo.environment["PRISM_SPECTRASONICS_STEAM"] {
        let steam = URL(fileURLWithPath: steamPath)
        let products = ["Omnisphere", "Keyscape", "Trilian"].map { name in
            Asset(kind: .library, path: steam.appendingPathComponent(name).path, name: name,
                  format: "Spectrasonics", bundleIdentifier: nil, logicalBytes: nil,
                  classification: "needsIdentification")
        }
        var issues: [ScanIssue] = []
        let installed = SpectrasonicsLibraryIndex.discover(products: products, issues: &issues)
        #expect(installed.contains { $0.name == "Analog Vibes" })
        #expect(installed.contains { $0.name == "The Unfinished Omnisphere Ferox" })
        #expect(installed.contains { $0.name == "Keyscape Library" })
        #expect(installed.contains { $0.name == "Trilian Library" })
        for (filename, _, _, library) in expectations {
            let plugins = try CubaseKontaktStateReader.readPluginStates(
                BoundedFile.read(root.appendingPathComponent(filename), limit: CubaseKontaktStateReader.maximumBytes))
            let state = try #require(plugins.compactMap(SpectrasonicsStateReader.read).first)
            let match = SpectrasonicsLibraryIndex.resolve(part: state.parts[0], player: state.player, assets: installed)
            #expect(match?.asset.name == library)
            #expect(match?.match == "exactLibraryAndPreset")
        }
        #expect(SpectrasonicsLibraryIndex.resolve(part: reset.parts[0], player: reset.player, assets: installed)?.match == nil)

        // Real saved snapshots must reach the same durable library-date path as
        // Kontakt, with exact library subjects and no reset-state membership.
        let storage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/SimplifyStoreTests/prism-spectrasonics-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storage) }
        var request = ScanRequest(); request.libraries = [steam]; request.projects = [root]
        let scope = CatalogScope(request)
        let reports = expectations.map { ProjectReader.read(root.appendingPathComponent($0.0)) }
        let resetReport = ProjectReader.read(root.appendingPathComponent("omni-empty.cpr"))
        #expect(reports.allSatisfy { $0.spectrasonicsStates?.count == 1 })
        let store = CatalogStore(url: storage.appendingPathComponent("catalog.sqlite"))
        let now = Date().addingTimeInterval(5)
        let input = ScanReport(schemaVersion: 1, assets: installed, projects: reports + [resetReport],
                               sampleInclusions: [], issues: [], durationSeconds: 0)
        let saved = try await store.ingest(input, scope: scope, at: now)
        for (index, (_, _, _, library)) in expectations.enumerated() {
            let subject = try #require(saved.report.assets.first { $0.name == library }?.catalogID)
            #expect(saved.report.projects[index].spectrasonicsOutcomes?.first?.catalogID == subject)
            #expect(try await store.dateSummary(for: subject, asOf: now).lastUsed == reports[index].projectModifiedAt)
            #expect(try await store.dateEvidence(for: subject, asOf: now).count == 1)
        }
        #expect(saved.report.projects.last?.spectrasonicsOutcomes?.allSatisfy { $0.catalogID == nil } == true)
        _ = try await store.ingest(input, scope: scope, at: now.addingTimeInterval(1))
        let firstID = try #require(saved.report.assets.first { $0.name == "Analog Vibes" }?.catalogID)
        #expect(try await store.dateEvidence(for: firstID, asOf: now.addingTimeInterval(1)).count == 1)
        let removed = ScanReport(schemaVersion: 1, assets: installed, projects: [],
                                 sampleInclusions: [], issues: [], durationSeconds: 0)
        _ = try await store.ingest(removed, scope: scope, at: now.addingTimeInterval(2))
        #expect(try await store.dateSummary(for: firstID, asOf: now.addingTimeInterval(2)).lastUsed == reports[0].projectModifiedAt)
    }
}
