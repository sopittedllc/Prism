import Foundation
import Testing
@testable import SimplifyCatalog
@testable import SimplifyCore

private func library(_ name: String, path: String, maker: String = "Example",
                     product: String? = nil, evidence: LibraryIdentity.Evidence = .manifest,
                     instruments: [LibraryInstrument] = [], tags: [String] = []) -> Asset {
    var asset = Asset(kind: .library, path: path, name: name, format: "Kontakt",
                      bundleIdentifier: nil, logicalBytes: 17, classification: "fixture")
    asset.libraryMetadata = LibraryMetadata(player: "Kontakt", maker: maker, summary: "",
        instruments: instruments, tags: tags, source: "Synthetic manifest",
        identity: LibraryIdentity(evidence: evidence, productID: product, installationRoot: path))
    return asset
}
private func sample(_ path: String, bytes: Int = 1) -> Asset {
    Asset(kind: .sample, path: path, name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
          format: "wav", bundleIdentifier: nil, logicalBytes: bytes, classification: "fixture")
}

@Test @MainActor func libraryHierarchyPreservesProductsInstallationsAndInstrumentIdentity() throws {
    let low = LibraryInstrument(name: "Low Strings", path: "/shared.otmeta", tags: ["Strings"], vendorID: "low")
    let other = LibraryInstrument(name: "Low Strings", path: "/shared.otmeta", tags: ["Strings"], vendorID: "other")
    let assets = [
        library("Metropolis Ark 2", path: "/shared.otmeta", maker: "Orchestral Tools", product: "sine:ark2", instruments: [low, other]),
        library("Metropolis Ark 3", path: "/shared.otmeta", maker: "Orchestral Tools", product: "sine:ark3", instruments: [low]),
        library("Metropolis Ark 2", path: "/second.otmeta", maker: "Orchestral Tools", product: "sine:ark2", instruments: [low]),
        library("CAGE Winds", path: "/cage", maker: "8Dio", instruments: [LibraryInstrument(name: "Low Winds", path: "/cage/Instruments/Low Winds.nki", tags: ["Woodwinds"])]),
        library("01 Low Winds", path: "/unverified", evidence: .proposed)
    ]
    let tree = CatalogOutline.build(assets: assets, category: .library)
    #expect(Set(tree.roots.map(\.title)) == ["Orchestral Tools", "8Dio", "Needs identification"])
    #expect(tree.roots.first { $0.title == "Needs identification" }?.kind == .unidentified)
    #expect(tree.nodes.filter { $0.kind == .library }.count == 5)
    #expect(tree.nodes.filter { $0.kind == .instrument }.count == 5)
    #expect(Set(tree.nodes.map(\.id)).count == tree.nodes.count)
    let instrument = try #require(tree.nodes.first { $0.title == "Low Winds" })
    #expect(instrument.breadcrumb == ["8Dio", "CAGE Winds", "Low Winds"])
    #expect(instrument.sizeText == "—")
    #expect(tree.nodes.filter { $0.kind == .library }.allSatisfy { $0.sizeText == "17 bytes" })
    #expect(tree.roots.allSatisfy { $0.location == nil })
}

@Test @MainActor func librarySearchKeepsOnlyMatchingPatchBranchesAndLabelsMetadataMatches() throws {
    let accordion = LibraryInstrument(name: "Accordion", path: "/folk/Accordion.nki", tags: ["Reeds"])
    let piano = LibraryInstrument(name: "Piano", path: "/folk/Piano.nki", tags: ["Keys"])
    let first = library("Folk", path: "/folk", instruments: [accordion, piano], tags: ["Accordion", "Piano"])
    let second = library("World", path: "/world", instruments: [piano], tags: ["Accordion"])
    let full = CatalogOutline.build(assets: [first, second], category: .library)
    let search = full.filtered(query: "accordion")
    #expect(search.roots.count == 1)
    #expect(search.nodes.filter { $0.kind == .instrument }.map(\.title) == ["Accordion"])
    #expect(search.nodes.first { $0.title == "World" }?.metadataOnlyMatch == true)
    #expect(search.nodes.first { $0.title == "Folk" }?.metadataOnlyMatch == false)
    #expect(search.nodes.first { $0.title == "Accordion" }?.breadcrumb == ["Example", "Folk", "Accordion"])
    #expect(full.filtered(query: "no such sound").roots.isEmpty)
    #expect(full.filtered(query: "") === full)
    let parent = full.filtered(query: "Folk")
    #expect(parent.nodes.filter { $0.kind == .instrument }.isEmpty)
    #expect(parent.nodes.first { $0.kind == .library }?.metadataOnlyMatch == true)
}

@Test @MainActor func flatLibrarySortKeepsArticulationsAttachedToPhysicalPatch() throws {
    let art = LibraryArticulation(id: "tremolo", name: "Tremolo", source: "Synthetic SINE fixture")
    let patch = LibraryInstrument(name: "Low Strings", path: "/ark/spot.otmeta", tags: ["Strings"],
                                  vendorID: "sine:collection:39:instrument:361", articulations: [art, LibraryArticulation(id: "pizz", name: "Pizzicato", source: "Fixture")],
                                  articulationCoverage: LibraryArticulationCoverage(status: .indexed, adapter: "fixture", adapterVersion: 1, sourceVersion: nil, sourceSignature: nil))
    let asset = library("Metropolis Ark 1", path: "/ark/spot.otmeta", maker: "Orchestral Tools",
                        product: "sine:collection:39", instruments: [patch])
    for sort in [CatalogSort.tags, .installed] {
        let tree = CatalogOutline.build(assets: [asset], category: .library, sort: sort)
        #expect(tree.roots.count == 1 && tree.roots[0].kind == .instrument)
        #expect(tree.roots[0].children.map(\.title) == ["Tremolo", "Pizzicato"])
        #expect(tree.roots[0].children[0].breadcrumb == ["Orchestral Tools", "Metropolis Ark 1", "Low Strings", "Tremolo"])
    }
}

@Test @MainActor func singletonTechniqueIsOneSearchablePatchAndSizeSortIsGlobal() throws {
    let solo = LibraryInstrument(name: "Celli", path: "/small/Celli.nki", tags: [],
        articulations: [LibraryArticulation(id: "long", name: "Long", source: "Fixture")],
        articulationCoverage: LibraryArticulationCoverage(status: .indexed, adapter: "fixture", adapterVersion: 1, sourceVersion: nil, sourceSignature: nil))
    var small = library("Small", path: "/small", maker: "A maker", instruments: [solo])
    small.logicalBytes = 10
    var large = library("Large", path: "/large", maker: "Z maker")
    large.logicalBytes = 100
    let tree = CatalogOutline.build(assets: [small, large], category: .library)
    #expect(tree.nodes.filter { $0.kind == .instrument }.count == 1)
    #expect(tree.nodes.filter { $0.kind == .articulation }.isEmpty)
    #expect(tree.filtered(query: "long").nodes.contains { $0.kind == .instrument && $0.title == "Celli" })
    let sized = CatalogOutline.build(assets: [small, large], category: .library, sort: .size)
    #expect(sized.roots.map(\.title) == ["Large", "Small"])
    #expect(sized.roots.allSatisfy { $0.kind == .library })
    #expect(sized.roots[1].children.map(\.title) == ["Celli"])
    #expect(sized.roots[1].breadcrumb == ["A maker", "Small"])
}

@Test @MainActor func oldTechniquePayloadHasUnknownCoverageAndNoAssertedChoices() throws {
    let legacy = LibraryInstrument(name: "Celli", path: "/legacy/Celli.nki", tags: [],
        articulations: [LibraryArticulation(id: "old", name: "Guessed", source: "legacy")])
    let data = try JSONEncoder().encode(legacy)
    var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    old.removeValue(forKey: "articulationCoverage")
    let decoded = try JSONDecoder().decode(LibraryInstrument.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(decoded.articulationCoverage.status == .unknown)
    let tree = CatalogOutline.build(assets: [library("Legacy", path: "/legacy", instruments: [decoded])], category: .library)
    #expect(tree.nodes.filter { $0.kind == .articulation }.isEmpty)
}

@Test @MainActor func sampleTreeUsesMostSpecificRootAndFlatSearchKeepsBreadcrumbAndSort() throws {
    let files = [sample("/Volumes/A/Samples/Percussion/Kick.wav", bytes: 10),
                 sample("/Volumes/A/Samples/Orchestral/Accordion.wav", bytes: 20),
                 sample("/Volumes/B/Samples/Percussion/Kick.wav", bytes: 30)]
    let roots = ["/Volumes/A/Samples", "/Volumes/A/Samples/Orchestral", "/Volumes/B/Samples"].map { URL(fileURLWithPath: $0) }
    let tree = CatalogOutline.build(assets: files, category: .sample, sampleRoots: roots)
    #expect(tree.roots.count == 3)
    #expect(tree.nodes.filter { $0.kind == .sample }.count == 3)
    #expect(Set(tree.nodes.map(\.id)).count == tree.nodes.count)
    let accordion = try #require(tree.nodes.first { $0.kind == .sample && $0.title == "Accordion" })
    #expect(accordion.breadcrumb == ["Orchestral", "Accordion"])
    let kicks = tree.filtered(query: "kick", sort: .size)
    #expect(kicks.roots.count == 2)
    #expect(kicks.roots.allSatisfy { $0.kind == .sample && $0.children.isEmpty })
    #expect(kicks.roots.first?.location == "/Volumes/B/Samples/Percussion/Kick.wav")
    #expect(Set(kicks.roots.map { $0.breadcrumb[0] }) == ["Samples · A", "Samples · B"])
    #expect(kicks.roots.allSatisfy { Array($0.breadcrumb.suffix(2)) == ["Percussion", "Kick"] })
    #expect(Set(kicks.roots.compactMap(\.location)).count == 2)
    #expect(tree.filtered(query: "Orchestral").roots.map(\.title) == ["Accordion"])
}

@Test @MainActor func outlineNavigationKeepsBrowseStateThroughSearchAndIdentityAssignment() throws {
    let asset = library("Folk", path: "/folk", instruments: [LibraryInstrument(name: "Accordion", path: "/folk/Accordion.nki", tags: [])])
    let before = CatalogOutline.build(assets: [asset], category: .library)
    let product = try #require(before.nodes.first { $0.kind == .library })
    let patch = try #require(before.nodes.first { $0.kind == .instrument })
    let state = CatalogOutlineState()
    state.setExpanded(true, node: product, category: .library, query: "")
    state.select(patch.id, category: .library, query: "")
    state.setExpanded(false, node: before.roots[0], category: .library, query: "Accordion")
    state.select(nil, category: .library, query: "no match")
    #expect(state.selectedID(category: .library, query: "") == patch.id)
    #expect(state.isExpanded(product, category: .library, query: ""))
    #expect(state.isExpanded(before.roots[0], category: .library, query: ""))
    #expect(state.selectedID(category: .sample, query: "") == nil)
    var persisted = asset; persisted.catalogID = "stable-observation"
    let after = CatalogOutline.build(assets: [persisted], category: .library)
    state.reconcile(previous: before, current: after, category: .library)
    let newProduct = try #require(after.nodes.first { $0.kind == .library })
    let newPatch = try #require(after.nodes.first { $0.kind == .instrument })
    #expect(newPatch.id != patch.id)
    #expect(state.selectedID(category: .library, query: "") == newPatch.id)
    #expect(state.isExpanded(newProduct, category: .library, query: ""))
    state.reset(); #expect(state.snapshot.isEmpty)
}

@Test @MainActor func stalePatchAndPluginProductStateStayDistinct() throws {
    var patch = LibraryInstrument(name: "Accordion", path: "/folk/Accordion.nki", tags: [],
        articulations: [LibraryArticulation(id: "sustain", name: "Sustain", source: "Synthetic fixture"),
                        LibraryArticulation(id: "short", name: "Short", source: "Synthetic fixture")],
        articulationCoverage: LibraryArticulationCoverage(status: .indexed, adapter: "fixture", adapterVersion: 1, sourceVersion: nil, sourceSignature: nil))
    patch.catalogStale = true
    let tree = CatalogOutline.build(assets: [library("Folk", path: "/folk", instruments: [patch])], category: .library)
    #expect(tree.nodes.first { $0.kind == .instrument }?.stale == true)
    #expect(tree.nodes.first { $0.kind == .articulation }?.stale == true)
    #expect(tree.nodes.first { $0.kind == .articulation }?.location == patch.path)
    #expect(tree.nodes.first { $0.kind == .library }?.stale == false)
    let au = Asset(kind: .plugin, path: "/Echo.component", name: "Echo", format: "component", bundleIdentifier: "example.echo.au", logicalBytes: nil, classification: "fixture")
    let vst = Asset(kind: .plugin, path: "/Echo.vst3", name: "Echo", format: "vst3", bundleIdentifier: "example.echo.vst3", logicalBytes: nil, classification: "fixture")
    let before = CatalogOutline.build(assets: [au], category: .plugin, pluginProductIDs: [au.path: "echo"])
    let after = CatalogOutline.build(assets: [vst], category: .plugin, pluginProductIDs: [vst.path: "echo"])
    #expect(before.roots.first?.id == after.roots.first?.id)
    let model = CatalogModel()
    model.outlineState.select("some-row", category: .library, query: "")
    model.reset(); #expect(model.outlineState.snapshot.isEmpty)
}
