import Foundation
import Testing
@testable import SimplifyCore

private struct KontaktBindingFixture {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)

    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func write(_ name: String, _ xml: String) throws -> URL {
        let url = root.appendingPathComponent(name).appendingPathExtension("nicnt")
        try Data(xml.utf8).write(to: url)
        return url
    }
    func asset(_ url: URL, stale: Bool? = nil, evidence: LibraryIdentity.Evidence = .manifest,
               catalogID: String? = "existing-catalog-id") -> Asset {
        var asset = Asset(kind: .library, path: url.path, name: "Fixture", format: "Kontakt",
                          bundleIdentifier: nil, logicalBytes: nil, classification: "identifiedLibrary")
        asset.catalogID = catalogID
        asset.catalogStale = stale
        asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Fixture", summary: "",
            instruments: [], tags: [], source: "test",
            identity: LibraryIdentity(evidence: evidence, productID: "existing-product-id", installationRoot: root.path))
        return asset
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private func manifestXML(_ snpid: String, product: String = "Fixture") -> String {
    "<ProductHints><Product><UPID>00000000-0000-0000-0000-000000000000</UPID><Name>\(product)</Name><Company>Example</Company><SNPID>\(snpid)</SNPID></Product></ProductHints>"
}

@Test func kontaktManifestSNPIDIsExactAndRejectsDuplicatesOrInvalidValues() {
    let parsed = LibraryMetadataReader.parseKontaktManifestDetails(Data(manifestXML("P44").utf8))
    #expect(parsed?.snpid == "P44")
    #expect(LibraryMetadataReader.parseKontaktManifest(Data(manifestXML("P44").utf8))?.name == "Fixture")
    #expect(LibraryMetadataReader.parseKontaktManifestDetails(Data(manifestXML("p44").utf8))?.snpid == "p44")
    #expect(LibraryMetadataReader.parseKontaktManifestDetails(Data(manifestXML("P-44").utf8)) == nil)
    let duplicateSNPID = "<ProductHints><Product><Name>Fixture</Name><SNPID>P44</SNPID><SNPID>P45</SNPID></Product></ProductHints>"
    #expect(LibraryMetadataReader.parseKontaktManifestDetails(Data(duplicateSNPID.utf8)) == nil)
    let duplicateProduct = "<ProductHints><Product><Name>A</Name><SNPID>P44</SNPID></Product><Product><Name>B</Name><SNPID>P44</SNPID></Product></ProductHints>"
    #expect(LibraryMetadataReader.parseKontaktManifestDetails(Data(duplicateProduct.utf8)) == nil)
    let duplicateField = "<ProductHints><Product><Name>A</Name><Name>B</Name><SNPID>P44</SNPID></Product></ProductHints>"
    #expect(LibraryMetadataReader.parseKontaktManifestDetails(Data(duplicateField.utf8)) == nil)
}

@Test func kontaktLibraryBindingPreservesCatalogIdentityAndRejectsStaleMissingAndProposedAssets() throws {
    let fixture = try KontaktBindingFixture(); defer { fixture.clean() }
    let freshURL = try fixture.write("Fresh", manifestXML("P44"))
    let staleURL = try fixture.write("Stale", manifestXML("P44", product: "Old Copy"))
    let proposedURL = try fixture.write("Proposed", manifestXML("P44", product: "Inferred"))
    let assets = [
        fixture.asset(freshURL),
        fixture.asset(staleURL, stale: true),
        fixture.asset(proposedURL, evidence: .proposed),
    ]
    let result = KontaktLibraryBinding.resolve(libraryIDs: ["P44"], assets: assets)
    let binding = try #require(result.bindings["P44"])
    #expect(result.complete)
    #expect(result.unresolved.isEmpty)
    #expect(binding.catalogID == "existing-catalog-id")
    #expect(binding.selectionKey == "existing-catalog-id")
    #expect(binding.manifestPath == freshURL.path)

    let noCatalogID = fixture.asset(freshURL, catalogID: nil)
    let pathIdentity = KontaktLibraryBinding.resolve(libraryIDs: ["P44"], assets: [noCatalogID])
    #expect(pathIdentity.bindings["P44"]?.selectionKey == "existing-product-id")
    #expect(pathIdentity.bindings["P44"]?.catalogID == nil)

    let missing = KontaktLibraryBinding.resolve(
        libraryIDs: ["P44"], assets: [fixture.asset(freshURL), fixture.asset(fixture.root.appendingPathComponent("Missing.nicnt"))])
    #expect(!missing.complete && missing.bindings.isEmpty)
    #expect(missing.unresolved["P44"] == .incomplete)
}

@Test func kontaktLibraryBindingKeepsDuplicateAndCaseDistinctIDsUnresolved() throws {
    let fixture = try KontaktBindingFixture(); defer { fixture.clean() }
    let first = fixture.asset(try fixture.write("First", manifestXML("P44")))
    let second = fixture.asset(try fixture.write("Second", manifestXML("P44", product: "Another copy")))
    let duplicate = KontaktLibraryBinding.resolve(libraryIDs: ["P44"], assets: [first, second])
    #expect(duplicate.complete)
    #expect(duplicate.bindings.isEmpty)
    #expect(duplicate.unresolved["P44"] == .ambiguous)

    let lower = fixture.asset(try fixture.write("Lower", manifestXML("p44")))
    let caseSensitive = KontaktLibraryBinding.resolve(libraryIDs: ["P44"], assets: [lower])
    #expect(caseSensitive.bindings.isEmpty)
    #expect(caseSensitive.unresolved["P44"] == .noInstalledManifest)
}

@Test func kontaktLibraryBindingFailsClosedOnBudgetsAndMalformedEligibleManifest() throws {
    let fixture = try KontaktBindingFixture(); defer { fixture.clean() }
    let url = try fixture.write("Malformed", "<ProductHints><Product><Name>Broken</ProductHints>")
    let malformed = fixture.asset(url)
    let result = KontaktLibraryBinding.resolve(libraryIDs: ["P44"], assets: [malformed])
    #expect(!result.complete)
    #expect(result.bindings.isEmpty)
    #expect(result.unresolved["P44"] == .incomplete)

    var manyAssets = [Asset]()
    for index in 0...KontaktLibraryBinding.maximumAssets {
        manyAssets.append(Asset(kind: .sample, path: "/unused/\(index)", name: "x", format: "wav",
                                bundleIdentifier: nil, logicalBytes: nil, classification: "fixture"))
    }
    let assetBudget = KontaktLibraryBinding.resolve(libraryIDs: ["P44"], assets: manyAssets)
    #expect(!assetBudget.complete && assetBudget.bindings.isEmpty)
    let candidateBudget = KontaktLibraryBinding.resolve(
        libraryIDs: Array(repeating: "P44", count: KontaktLibraryBinding.maximumCandidates + 1), assets: [])
    #expect(!candidateBudget.complete && candidateBudget.bindings.isEmpty)
}

@Test func nativeKontaktAccordionSNPIDBindsOnlyToCurrentManifestWhenEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_TABLE_RUNTIME"] == "1" else { return }
    guard let manifestPath = ProcessInfo.processInfo.environment["PRISM_KONTAKT_MANIFEST_PATH"],
          !manifestPath.isEmpty else {
        Issue.record("Set PRISM_KONTAKT_MANIFEST_PATH to the local Accordion.nicnt for this opt-in native check.")
        return
    }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let stateURL = root.appendingPathComponent("build/usage-controls/kontakt-active-controls/Accordion.state")
    let manifestURL = URL(fileURLWithPath: manifestPath)
    #expect(FileManager.default.fileExists(atPath: stateURL.path))
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    let state = try KontaktStateReader.read(BoundedFile.read(stateURL, limit: KontaktStateReader.maximumBytes))
    #expect(state.libraryIDs == ["P44"])
    #expect(LibraryMetadataReader.kontaktManifestDetails(manifestURL)?.snpid == "P44")

    var asset = Asset(kind: .library, path: manifestURL.path, name: "Accordion", format: "Kontakt",
                      bundleIdentifier: nil, logicalBytes: nil, classification: "identifiedLibrary")
    asset.catalogID = "existing-accordion-catalog-id"
    asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: "Sonokinetic BV", summary: "",
        instruments: [], tags: [], source: "native manifest fixture",
        identity: LibraryIdentity(evidence: .manifest, productID: nil,
                                  installationRoot: manifestURL.deletingLastPathComponent().path))
    let result = KontaktLibraryBinding.resolve(libraryIDs: state.libraryIDs, assets: [asset])
    let binding = try #require(result.bindings["P44"])
    #expect(result.complete && result.unresolved.isEmpty)
    #expect(binding.catalogID == "existing-accordion-catalog-id")
    #expect(binding.selectionKey == "existing-accordion-catalog-id")
    #expect(binding.manifestPath == manifestURL.path)
}
