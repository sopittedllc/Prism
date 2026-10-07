import Foundation
import AppKit
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

@Test @MainActor func settingsSaveBeforeFirstReviewDoesNotCompleteOnboarding() throws {
    let f = try CatalogFixture()
    let setup = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let model = CatalogModel(store: setup)
    #expect(!model.onboardingCompleted)
    let draft = model.setupDraft(); draft.appearance = .dark
    try model.acceptSetup(draft, remember: true, completeOnboarding: false)
    #expect(!model.onboardingCompleted && !model.isScanning)
    let reopened = CatalogModel(store: setup)
    #expect(!reopened.onboardingCompleted && reopened.appearance == .dark)
}

@Test @MainActor func unavailableSampleReferenceAndSizeCopyStayQualified() async throws {
    let f = try CatalogFixture()
    let first = try f.file("Samples/First.wav")
    let second = try f.file("Samples/Second.wav")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let model = CatalogModel(catalogStore: catalog); model.setStandardPlugins(false)
    model.addRoots([first.deletingLastPathComponent()], kind: .samples)
    model.addRoots([f.root.appendingPathComponent("UnavailableProjects")], kind: .projects)
    model.scan(); try await finish(model)
    model.category = .sample; model.selectedPath = first.path
    #expect(model.detail.contains("Project reference coverage unavailable"))
    try FileManager.default.removeItem(at: second)
    model.scan(); try await finish(model)
    model.selectedPath = second.path
    #expect(model.selectedAsset?.catalogStale == true)
    #expect(model.detail.contains("Reference coverage unavailable for this not-observed"))
    #expect(!model.detail.contains("No references found"))

    let window = CatalogWindow(model: model)
    let sample = Asset(kind: .sample, path: "/fixture/Unreadable.wav", name: "Unreadable", format: "wav",
        bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    let sampleNode = CatalogOutlineNode(id: "sample", kind: .sample, title: "Unreadable", breadcrumb: [], asset: sample)
    #expect(window.sizePresentationDetail(sampleNode, value: "Size unavailable").contains("file size metadata could not be read"))
    var orphan = Asset(kind: .library, path: "/fixture/Orphan", name: "Orphan", format: "SINE",
        bundleIdentifier: nil, logicalBytes: 18, classification: "unassociatedPhysicalContent")
    var metadata = LibraryMetadata(player: "SINE", maker: "Unknown maker", summary: "", instruments: [], tags: [], source: "fixture")
    metadata.sizeBasis = .unassociatedContent; orphan.libraryMetadata = metadata
    let orphanNode = CatalogOutlineNode(id: "orphan", kind: .library, title: "Orphan", breadcrumb: [], asset: orphan)
    let help = window.sizePresentationDetail(orphanNode, value: "18 bytes")
    #expect(help.contains("unassociated metadata and archive content") && help.contains("whole-library footprint are unknown"))
}

@Test @MainActor func cancellingCatalogScanDoesNotPublishOrCommitPartialResults() async throws {
    let f = try CatalogFixture()
    for index in 0..<180 { _ = try f.file(String(format: "Libraries/Folder%03d/Patch.nki", index)) }
    let catalog = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let model = CatalogModel(catalogStore: catalog); model.setStandardPlugins(false)
    let libraryRoot = f.root.appendingPathComponent("Libraries")
    model.addRoots([libraryRoot], kind: .libraries)
    model.scan(scannedKinds: [.library])
    model.cancelScan()
    try await finish(model)
    #expect(model.report == nil)
    #expect(model.catalogNotice?.contains("Refresh stopped") == true)
    #expect(try await catalog.load(scope: { var request = ScanRequest(); request.libraries = [libraryRoot]; return CatalogScope(request) }()) == nil)
    model.scan(scannedKinds: [.library]); try await finish(model)
    #expect(model.report?.assets.count == 180)
}

@Test @MainActor func restoringSavedCatalogLeavesRefreshUnderSectionControl() async throws {
    let f = try CatalogFixture()
    let setup = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let libraryRoot = f.root.appendingPathComponent("Libraries")
    let configured = CatalogModel(store: setup, catalogStore: catalog)
    configured.setStandardPlugins(false)
    configured.addRoots([libraryRoot], kind: .libraries)
    try setup.save(configured.stateSnapshot)
    var request = ScanRequest(); request.libraries = [libraryRoot]
    let path = libraryRoot.appendingPathComponent("Folk")
    let asset = Asset(kind: .library, path: path.path, name: "Folk", format: "Kontakt",
        bundleIdentifier: nil, logicalBytes: nil, classification: "fixture")
    _ = try await catalog.ingest(ScanReport(schemaVersion: 1, assets: [asset], projects: [],
        sampleInclusions: [], issues: [], durationSeconds: 0), scope: CatalogScope(request))

    let restored = CatalogModel(store: setup, catalogStore: catalog)
    await restored.restoreSavedCatalog()
    #expect(restored.report?.assets.map(\.path) == [path.path])
    #expect(!restored.isScanning)
    #expect(!restored.isRestoringCatalog)
}

@Test @MainActor func savedSINEInstrumentDateProjectsOnlyRefreshReachesNormalCatalog() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SAVED_PROJECT_RUNTIME"] == "1" else { return }
    let f = try CatalogFixture()
    let meta = try f.file("Libraries/SINE/Tides.otmeta")
    let archive = try f.file("Libraries/SINE/Tides.otarc")
    let setup = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let store = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(store: setup, catalogStore: store)
    model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries)
    let controlRoot = try #require(ProcessInfo.processInfo.environment["PRISM_SINE_CONTROL_PROJECTS"])
    let projectPath = URL(fileURLWithPath: controlRoot).appendingPathComponent("sinetest.cpr")
    model.addRoots([projectPath.deletingLastPathComponent()], kind: .projects)
    try setup.save(model.stateSnapshot)
    var request = ScanRequest()
    request.libraries = [f.root.appendingPathComponent("Libraries")]
    request.projects = [projectPath.deletingLastPathComponent()]
    var asset = Asset(kind: .library, path: meta.path, name: "Tides by Rachel Portman", format: "SINE",
        bundleIdentifier: nil, logicalBytes: nil, classification: "identifiedLibrary")
    asset.libraryMetadata = LibraryMetadata(player: "SINE", maker: "Orchestral Tools", summary: "",
        instruments: [LibraryInstrument(name: "Violins a6", path: meta.path, tags: [],
            vendorID: "sine:collection:5107:instrument:5108", contentPaths: [meta.path, archive.path])],
        tags: [], source: "fixture", identity: LibraryIdentity(evidence: .vendorCatalog,
            productID: "sine:collection:5107", installationRoot: nil))
    let scope = CatalogScope(request)
    let first = ScanReport(schemaVersion: 1, assets: [asset], projects: [], sampleInclusions: [], issues: [], durationSeconds: 0)
    _ = try await store.ingest(first, scope: scope)
    let project = ProjectReader.read(projectPath)
    #expect(project.sineInstrumentIDs == ["5108"])
    let second = ScanReport(schemaVersion: 1, assets: [], projects: [project], sampleInclusions: [], issues: [], durationSeconds: 0)
    let saved = try await store.ingest(second, scope: scope, scannedKinds: [.sample])
    let library = try #require(saved.report.assets.first { $0.kind == .library })
    let instrument = try #require(library.libraryMetadata?.instruments.first)
    let subject = AssetUsageSubject.instrumentID(parentNodeID: try #require(library.catalogID), instrument: instrument)
    #expect(try await store.dateSummary(for: subject, asOf: Date()).lastUsed == project.projectModifiedAt)
    let restored = CatalogModel(store: setup, catalogStore: store)
    await restored.restoreSavedCatalog()
    await restored.reloadUsage()
    let visible = try #require(restored.report?.assets.first { $0.kind == .library })
    #expect(restored.usageRecord(visible)?.eventDate == project.projectModifiedAt)
}

@Test @MainActor func realLogicSavedKontaktLibraryReachesLibraryDateWhenEnabled() async throws {
    guard let path = ProcessInfo.processInfo.environment["PRISM_REAL_LOGIC_PROJECT"] else { return }
    let project = ProjectReader.read(URL(fileURLWithPath: path))
    #expect(project.kontaktStates?.contains { $0.libraryIDs.contains("058") } == true)
    let current = CatalogModel(store: .application, catalogStore: .application)
    await current.restoreSavedCatalog()
    let asset = try #require(current.report?.assets.first {
        $0.libraryMetadata?.identity?.productID == "kontakt:snpid:058"
    })
    let f = try CatalogFixture()
    let store = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    var request = ScanRequest(); request.libraries = [URL(fileURLWithPath: asset.path).deletingLastPathComponent()]
    request.projects = [URL(fileURLWithPath: path).deletingLastPathComponent()]
    let scope = CatalogScope(request)
    let report = ScanReport(schemaVersion: 1, assets: [asset], projects: [project],
        sampleInclusions: [], issues: [], durationSeconds: 0)
    let saved = try await store.ingest(report, scope: scope, at: Date())
    let subject = try #require(saved.report.assets.first?.catalogID)
    #expect(try await store.dateSummary(for: subject, asOf: Date()).lastUsed == project.projectModifiedAt)
}

@Test @MainActor func tagCapitalizationChangesPresentationOnly() {
    #expect(MusicalTagDisplay.title("dark warm") == "Dark Warm")
    #expect(MusicalTagDisplay.title("one-shot") == "One-Shot")
    #expect(MusicalTagDisplay.title("bpm midi fx") == "BPM MIDI FX")
    #expect(MusicalTagDisplay.title("c#m F#m Cm LoFi") == "C#m F#m Cm LoFi")
    let pill = TagPill(facet: .technique, value: "sul ponticello", editable: true, scope: "", remove: {})
    #expect(pill.value == "sul ponticello")
    #expect(pill.toolTip?.contains("Sul Ponticello") == true)
    #expect(pill.removeButton.accessibilityLabel()?.contains("Sul Ponticello") == true)
    #expect(MusicalSearch.matches("sul ponticello", in: pill.value))
}

@Test @MainActor func collectionReadOnlyTagsKeepFullValuesAndEqualPaddingAtCompactWidth() throws {
    let tags: [(MusicalFacet, String)] = [
        (.instrument, "cello"), (.technique, "legato"), (.character, "warm"),
        (.ensemble, "chamber ensemble"), (.role, String(repeating: "very long tag ", count: 25))
    ]
    var disclosed = false
    let cell = CollectionTagCell(title: "Celli Core", tags: tags, context: "Spitfire › Chamber Strings", query: "Celli") { _, supplied in
        disclosed = supplied.count == tags.count
    }
    cell.frame = NSRect(x: 0, y: 0, width: 190, height: 64)
    cell.layout()
    let more = try #require(cell.subviews.compactMap { $0 as? NSButton }.first)
    let visiblePills = cell.subviews.compactMap { $0 as? ReadOnlyTagPill }.filter { !$0.isHidden }
    let visible = visiblePills.count
    #expect(more.title == "+\(tags.count - visible) more")
    #expect(more.accessibilityLabel()?.contains("all 5 tags") == true)
    #expect(cell.textField?.accessibilityLabel()?.contains("Very Long Tag") == true)
    let style = cell.textField?.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    #expect(style?.lineBreakMode == .byTruncatingMiddle)
    #expect(cell.textField?.maximumNumberOfLines == 1)
    #expect(cell.subviews.compactMap { $0 as? TagRemoveButton }.isEmpty)
    for pill in visiblePills {
        pill.layout()
        #expect(pill.title.frame.minY == pill.bounds.height - pill.title.frame.maxY)
        #expect(pill.title.frame.minX == pill.bounds.width - pill.title.frame.maxX)
        #expect(pill.title.frame.width >= pill.title.fittingSize.width)
        #expect(pill.title.accessibilityLabel()?.contains(": ") == true)
    }
    more.performClick(nil)
    #expect(disclosed)

    let withSubtitle = CollectionTagCell(title: "A plugin", subtitle: "AU, VST3", tags: tags,
                                         context: "A maker", query: "plugin") { _, _ in }
    withSubtitle.frame = NSRect(x: 0, y: 0, width: 190, height: 82)
    withSubtitle.layout()
    #expect(withSubtitle.textField?.accessibilityLabel()?.contains("AU, VST3") == true)
    #expect(withSubtitle.subviews.compactMap { $0 as? ReadOnlyTagPill }.filter { !$0.isHidden }.allSatisfy { $0.frame.minY >= 0 })
}

@Test @MainActor func collectionSortAndTagColumnApplyAcrossCategories() {
    let model = CatalogModel()
    let controller = CatalogWindow(model: model)
    for kind in [AssetKind.plugin, .sample, .library] {
        model.category = kind
        controller.refresh()
        #expect(controller.table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("tags"))?.isHidden == true)
        #expect(!controller.librarySort.isHidden)
        let formatTitle = kind == .plugin ? "Format" : kind == .sample ? "File type" : "Player / format"
        #expect(controller.librarySort.item(at: 5)?.title == formatTitle)
        controller.librarySort.selectItem(at: 1)
        controller.changeLibrarySort(controller.librarySort)
        #expect(model.sort == .tags)
        model.sort = .name; model.sortReversed = false
    }
}

@Test @MainActor func compactInspectorKeepsFormatActionsReachableAtMinimumWindowSize() async throws {
    let f = try CatalogFixture()
    for ext in ["component", "vst3", "aaxplugin"] {
        try f.file("Plugins/Glow.\(ext)/Contents/Info.plist", """
        <?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.example.glow</string></dict></plist>
        """)
    }
    let model = CatalogModel()
    model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let controller = CatalogWindow(model: model)
    let window = try #require(controller.window)
    window.setContentSize(NSSize(width: 1040, height: 680))
    controller.refresh()
    controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    window.contentView?.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(try #require(window.contentView))
    #expect(!views.compactMap { $0 as? NSButton }.contains { $0.title == "Show details" })
    #expect(!controller.formatsButton.isHidden && controller.formatsButton.isEnabled)
    let content = try #require(window.contentView)
    #expect(content.bounds.contains(controller.formatsButton.convert(controller.formatsButton.bounds, to: content)))
    #expect(controller.inspectorSummaryText.contains("Date added   " + model.additionDate(model.pluginProducts[0].representative).value))
    #expect(controller.inspectorSummaryText.contains("Size   "))
    let last = try #require(controller.table.tableColumns.firstIndex { $0.identifier.rawValue == "reference" })
    #expect(controller.table.rect(ofColumn: last).maxX <= controller.table.visibleRect.maxX)
    controller.showFormats()
    let sheet = try #require(controller.formatsWindow?.window?.contentView)
    let finderButtons = descendants(sheet).compactMap { $0 as? NSButton }.filter { $0.title == "Show in Finder" }
    #expect(finderButtons.count == 3)
    #expect(finderButtons.allSatisfy { $0.toolTip?.hasPrefix(f.root.path) == true })
}

@Test @MainActor func flatLibraryDateAndTagSortCountShownInstrumentsAndKeepContext() async throws {
    let f = try CatalogFixture()
    try f.file("Libraries/Colors/Colors.nicnt", "<ProductHints><Product><Name>Colors</Name><Company>Example</Company></Product></ProductHints>")
    try f.file("Libraries/Colors/Violin.nki")
    let model = CatalogModel(); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries)
    model.scan(scannedKinds: [.library]); try await finish(model)
    model.category = .library
    let controller = CatalogWindow(model: model)
    for sort in [CatalogSort.tags, .installed] {
        model.sort = sort; controller.refresh()
        #expect(model.outline.roots.contains { $0.kind == .instrument })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let labels = descendants(try #require(controller.window?.contentView)).compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("1 sound"))
        let instrument = try #require(model.outline.roots.first { $0.kind == .instrument })
        #expect(instrument.breadcrumb.contains("Colors"))
        #expect(instrument.breadcrumb.contains("Violin"))
    }
}

@Test @MainActor func sampleSearchKeepsNumericExactnessNamePrefixesAndEditedTags() async throws {
    let f = try CatalogFixture()
    try f.file("Samples/Percussion 0.wav"); try f.file("Samples/Percussion 10.wav")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(catalogStore: catalog); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    model.scan(scannedKinds: [.sample]); try await finish(model)
    model.category = .sample
    model.query = "p"; #expect(model.outline.roots.count == 2)
    model.query = "Percussion 0"; #expect(model.outline.roots.count == 1)
    let sample = try #require(model.report?.assets.first { $0.name == "Percussion 0" })
    try await model.saveMetadata(MusicalMetadata(fields: ["character": ["airy"]]), subject: try #require(model.subject(asset: sample)))
    model.query = "airy"; #expect(model.outline.roots.count == 1)
    try await model.undoMetadata()
    model.query = "airy"; #expect(model.outline.roots.isEmpty)
}

@MainActor private func finish(_ model: CatalogModel) async throws {
    // Swift Testing runs this suite concurrently; large scanner fixtures can keep
    // otherwise tiny catalog scans queued for more than ten seconds on a cold run.
    let deadline = Date().addingTimeInterval(30)
    while (model.isScanning || model.isLoadingInstallerRecords || model.isLoadingItemUsage) && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!model.isScanning && !model.isLoadingInstallerRecords && !model.isLoadingItemUsage)
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
    model.category = .library; model.query = "strings"; model.sort = .recency; model.usageFilter = .unknown
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
    #expect(model.status.contains("Check For Updates to update"))
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

@Test func logicMetadataWithoutProjectDataFailsClosed() throws {
    let f = try CatalogFixture()
    let project = f.root.appendingPathComponent("Fixture.logicx")
    let metadata = try f.file("Fixture.logicx/Alternatives/000/MetaData.plist")
    try PropertyListSerialization.data(fromPropertyList: ["AudioFiles": ["/Samples/included.wav"], "UnusedAudioFiles": ["/Samples/unused.wav"]], format: .binary, options: 0).write(to: metadata)
    let report = ProjectReader.read(project)
    #expect(report.coverage == "failed")
    #expect(report.references.isEmpty)
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
    reopened.query = "vst3"; #expect(reopened.visibleAssets.isEmpty)
    reopened.query = ""
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
    CREATE TABLE t_articulation(articulation_key,articulation_instrument,articulation_id,title,kind,hidden);
    INSERT INTO t_collection VALUES(1,'ark2','Ark 2','','Orchestral Tools',''),(2,'ark3','Ark 3','','Orchestral Tools','');
    INSERT INTO t_instrument VALUES(1,1,'low','Low Strings','strings'),(2,2,'low','Low Strings','strings');
    INSERT INTO t_articulation VALUES(1,1,'legato','Legato','single',0),
      (2,1,'tremolo','Tremolo','single',0),(3,2,'spiccato','Spiccato','single',0);
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
    #expect(model.outline.nodes.filter { $0.kind == .articulation }.count == 2)
    #expect(model.outline.nodes.filter { $0.kind == .instrument }.count == 2)
    model.query = "strings legato"
    #expect(model.outline.nodes.filter { $0.kind == .articulation }.map(\.title) == ["Legato"])
    model.query = "legato tremolo"
    #expect(model.outline.nodes.filter { $0.kind == .articulation }.isEmpty)
    model.query = "ark3 legato"
    #expect(model.outline.nodes.filter { $0.kind == .articulation }.isEmpty)
    model.query = ""
    for asset in model.visibleAssets {
        model.selectedPath = asset.selectionKey
        #expect(model.selectedAsset?.name == asset.name)
        #expect(model.selectedAsset?.path == meta.path)
    }
    model.scan(); try await finish(model)
    #expect(model.selectedAsset?.name == "Ark 3")
}

@Test @MainActor func exactChamberPatchesSearchAndRestoreWithoutSiblingArticulationLeakage() async throws {
    let f = try CatalogFixture()
    let base = "Libraries/Chamber/"
    try f.file(base + "Spitfire Chamber Strings.nicnt", "<ProductHints><Product><Name>Spitfire Chamber Strings</Name><Company>Spitfire Audio</Company><SNPID>058</SNPID></Product></ProductHints>")
    try f.file(base + "Instruments/d - Celli.nki")
    try f.file(base + "Instruments/_Advanced_/Individual articulations/d - Celli/d - Celli - Legato (Fingered).nki")
    try f.file(base + "Instruments/_Advanced_/Individual articulations/d - Celli/d - Celli - Long Harmonics.nki")
    try f.file(base + "Instruments/_Advanced_/Extended techniques/d - Celli - Core techniques.nki")
    let store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    func configured() -> CatalogModel {
        let model = CatalogModel(catalogStore: store); model.standardPlugins = false
        model.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries)
        model.category = .library
        return model
    }
    let model = configured(); model.scan(); try await finish(model)
    let all = model.outline
    #expect(all.nodes.filter { $0.kind == .instrument }.count == 4)
    #expect(all.nodes.filter { $0.kind == .articulation }.isEmpty)
    #expect(all.nodes.filter { $0.kind == .instrument && $0.instrument?.articulationCoverage.status == .unknown }.count == 4)
    #expect(all.nodes.first { $0.title == "d - Celli" }?.children.isEmpty == true)
    let legatoPatch = try #require(all.nodes.first { $0.title == "d - Celli - Legato (Fingered)" })
    let legatoAsset = try #require(legatoPatch.asset)
    let legatoInstrument = try #require(legatoPatch.instrument)
    let legatoSubject = try #require(model.subject(asset: legatoAsset, instrument: legatoInstrument))
    #expect(model.effectiveMetadata(asset: legatoAsset, instrument: legatoInstrument)[.technique] == ["legato"])
    try await model.saveMetadata(MusicalMetadata(fields: ["technique": []]), subject: legatoSubject)
    #expect(model.effectiveMetadata(asset: legatoAsset, instrument: legatoInstrument)[.technique] == [])
    model.query = "cello legato"
    #expect(model.outline.nodes.filter { $0.kind == .instrument }.map(\.title) == ["d - Celli - Legato (Fingered)"])
    try await model.undoMetadata()
    #expect(model.effectiveMetadata(asset: legatoAsset, instrument: legatoInstrument)[.technique] == ["legato"])
    #expect(model.outline.nodes.filter { $0.kind == .instrument }.map(\.title) == ["d - Celli - Legato (Fingered)"])
    model.query = "harmonic cello"
    let harmonic = try #require(model.outline.nodes.first { $0.kind == .instrument })
    #expect(harmonic.title == "d - Celli - Long Harmonics" && harmonic.breadcrumb.count == 3)
    #expect(harmonic.location == harmonic.instrument?.path && harmonic.sizeText == "—")
    model.query = "legato harmonic"
    #expect(model.outline.nodes.filter { $0.kind == .articulation || $0.kind == .instrument }.isEmpty)
    model.query = ""
    let patch = try #require(model.outline.nodes.first { $0.title == "d - Celli - Long Harmonics" })
    model.outlineState.select(patch.id, category: .library, query: "")
    model.outlineState.setExpanded(true, node: patch, category: .library, query: "")
    model.query = "cello harmonics"
    let found = try #require(model.outline.nodes.first { $0.kind == .instrument })
    model.outlineState.select(found.id, category: .library, query: model.navigationQuery)
    model.query = ""
    #expect(model.outlineState.selectedID(category: .library, query: "") == patch.id)
    #expect(model.outlineState.isExpanded(patch, category: .library, query: ""))
    let reopened = configured(); await reopened.restoreSavedCatalog()
    #expect(reopened.usingSavedCatalog)
    #expect(reopened.outline.nodes.filter { $0.kind == .articulation }.isEmpty)
    #expect(reopened.outline.nodes.filter { $0.kind == .instrument && $0.instrument?.articulationCoverage.status == .unknown }.count == 4)
    #expect(reopened.outline.nodes.filter { $0.kind == .instrument }.allSatisfy { $0.instrument?.articulations.isEmpty == true && $0.location == $0.instrument?.path })
    try FileManager.default.moveItem(at: f.root.appendingPathComponent(base),
        to: f.root.appendingPathComponent("Offline-Chamber"))
    reopened.scan(); try await finish(reopened)
    #expect(reopened.outline.nodes.filter { $0.kind == .instrument && $0.instrument?.articulationCoverage.status == .unknown }.count == 4)
    #expect(reopened.outline.nodes.filter { $0.kind == .instrument }.allSatisfy { $0.stale })
}

@Test @MainActor func persistentCatalogReopensAndRejectsCachedRemoval() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Example.vst3/Contents/marker")
    try f.file("Samples/Banjo.wav")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    func configured() -> CatalogModel {
        let model = CatalogModel(catalogStore: catalog); model.standardPlugins = false
        model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
        model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
        return model
    }
    let original = configured(); original.scan(); try await finish(original)
    #expect(original.catalogNotice == nil)
    #expect(original.savedCatalogDate != nil)
    let reopened = configured(); await reopened.restoreSavedCatalog()
    #expect(reopened.usingSavedCatalog)
    #expect(reopened.report?.assets.count == 2)
    #expect(reopened.status.contains("Saved collection"))
    let plugins = reopened.report?.assets.filter { $0.kind == .plugin } ?? []
    #expect(await reopened.trashPlugins(plugins).isEmpty)
    #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Plugins/Example.vst3").path))
    reopened.scan(); try await finish(reopened)
    #expect(!reopened.usingSavedCatalog)
    #expect(reopened.report?.assets.first { $0.kind == .plugin }?.fileIdentity != nil)
    // A disconnected source remains present but stale after a new final scan.
    try FileManager.default.moveItem(at: f.root.appendingPathComponent("Samples"), to: f.root.appendingPathComponent("OfflineSamples"))
    reopened.scan(); try await finish(reopened)
    #expect(reopened.report?.assets.first { $0.kind == .sample }?.catalogStale == true)
    let another = configured(); await another.restoreSavedCatalog()
    #expect(another.report?.assets.count == 2)
    #expect(another.report?.assets.first { $0.kind == .sample }?.catalogStale == true)
}

@Test @MainActor func persistenceFailureKeepsLiveResultsAndResetIgnoresLateRestore() async throws {
    let f = try CatalogFixture(); try f.file("Samples/Accordion.wav")
    let url = try f.file("Private/broken.sqlite", "not sqlite")
    let model = CatalogModel(catalogStore: CatalogStore(url: url)); model.standardPlugins = false
    model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    model.scan(); try await finish(model)
    #expect(model.report?.assets.count == 1)
    #expect(model.catalogNotice != nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "not sqlite")

    let valid = f.root.appendingPathComponent("Private/valid.sqlite")
    let store = CatalogStore(url: valid)
    var request = ScanRequest(); request.samples = [f.root.appendingPathComponent("Samples")]
    _ = try await store.ingest(Scanner().scan(request), scope: CatalogScope(request))
    var db: OpaquePointer?; #expect(sqlite3_open(valid.path, &db) == SQLITE_OK)
    defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil); sqlite3_close(db) }
    #expect(sqlite3_exec(db, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
    let restored = CatalogModel(catalogStore: store); restored.standardPlugins = false
    restored.addRoots(request.samples, kind: .samples)
    let pending = Task { await restored.restoreSavedCatalog() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(restored.isRestoringCatalog)
    restored.reset()
    await pending.value
    #expect(restored.report == nil)
    #expect(restored.catalogNotice == nil)
    #expect(restored.roots.isEmpty)
}

@Test @MainActor func successfulLateRestoreCannotReplaceChangedScopeOrFreshScan() async throws {
    let f = try CatalogFixture()
    try f.file("Samples/Accordion.wav")
    let database = f.root.appendingPathComponent("Private/catalog.sqlite")
    let store = CatalogStore(url: database)
    var request = ScanRequest(); request.samples = [f.root.appendingPathComponent("Samples")]
    _ = try await store.ingest(Scanner().scan(request), scope: CatalogScope(request))
    for changeScope in [true, false] {
        let model = CatalogModel(catalogStore: store); model.standardPlugins = false
        model.addRoots(request.samples, kind: .samples)
        var db: OpaquePointer?
        #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil); sqlite3_close(db) }
        #expect(sqlite3_exec(db, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        let pending = Task { await model.restoreSavedCatalog() }
        // The main-actor flag proves restore captured the original scope/token and
        // yielded to the store. Change intent before allowing the read to complete.
        let restoreDeadline = Date().addingTimeInterval(10)
        while !model.isRestoringCatalog && Date() < restoreDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard model.isRestoringCatalog else {
            Issue.record("Catalog restore did not enter its suspended read within ten seconds")
            #expect(sqlite3_exec(db, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
            await pending.value
            continue
        }
        if changeScope {
            let other = f.root.appendingPathComponent("Other")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            model.addRoots([other], kind: .samples)
        } else {
            try f.file("Samples/New.wav")
            model.scan()
        }
        #expect(sqlite3_exec(db, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await pending.value
        if changeScope {
            #expect(model.report == nil)
            #expect(model.roots[.samples]?.count == 2)
        } else {
            try await finish(model)
            #expect(model.report?.assets.count == 2)
            #expect(model.report?.assets.contains { $0.path == f.root.appendingPathComponent("Samples/New.wav").path } == true)
        }
        #expect(!model.usingSavedCatalog)
        #expect(model.catalogNotice == nil)
    }
}

@Test @MainActor func musicalEditingSearchUndoAndRestart() async throws {
    let f = try CatalogFixture()
    try f.file("Libraries/Strings/Strings.nicnt", "<ProductHints><Product><Name>Strings</Name><Company>Spitfire fixture</Company></Product></ProductHints>")
    try f.file("Libraries/Strings/Solo Cello Legato.nki")
    try f.file("Libraries/Strings/Violin Spiccato.nki")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    func model() -> CatalogModel {
        let m = CatalogModel(catalogStore: catalog); m.standardPlugins = false
        m.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries); m.category = .library
        return m
    }
    let m = model(); m.scan(); try await finish(m)
    m.query = "Spitfire fixture"
    #expect(m.outline.nodes.filter { $0.kind == .instrument }.isEmpty)
    #expect(m.outline.nodes.contains { $0.metadataOnlyMatch })
    m.query = "Spitfire cello legato"
    #expect(m.outline.nodes.filter { $0.kind == .instrument }.count == 1)
    m.query = "solo cello legato"
    let nodes = m.outline.nodes.filter { $0.kind == .instrument }
    #expect(nodes.count == 1)
    let node = try #require(nodes.first), asset = try #require(node.asset)
    let subject = try #require(m.subject(asset: asset, instrument: node.instrument))
    try await m.saveMetadata(MusicalMetadata(fields: ["character": ["dark"], "technique": []]), subject: subject)
    m.query = "dark cello"; #expect(m.outline.nodes.filter { $0.kind == .instrument }.count == 1)
    m.query = ""; m.musicalFilter = ["technique": "legato"]
    #expect(m.outline.nodes.filter { $0.kind == .instrument }.isEmpty)
    m.musicalFilter = ["technique": "spiccato"]
    #expect(m.outline.nodes.filter { $0.kind == .instrument }.map(\.title) == ["Violin Spiccato"])
    let reopened = model(); await reopened.restoreSavedCatalog()
    #expect(reopened.metadataOverrides[subject.key]?[.character] == ["dark"])
    let restoredLibrary = reopened.outline
    reopened.category = .plugin; _ = reopened.outline
    reopened.category = .library
    #expect(reopened.outline === restoredLibrary)
    await reopened.reloadUsage()
    #expect(reopened.outline === restoredLibrary)
    reopened.musicalFilter = ["technique": "legato"]; #expect(reopened.outline.nodes.filter { $0.kind == .instrument }.isEmpty)
    m.scan(); try await finish(m)
    #expect(m.metadataOverrides[subject.key]?[.technique] == [])
    try await m.undoMetadata()
    m.musicalFilter = ["technique": "legato"]; #expect(m.outline.nodes.filter { $0.kind == .instrument }.count == 1)
    #expect(m.metadataOverrides[subject.key] == nil)
}

@Test @MainActor func pluginInstallationEditsSurviveRepresentativeChangesAndNewFormatsAreNotNewProducts() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Example.vst3/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.fixture.example.vst3</string></dict></plist>")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let m = CatalogModel(catalogStore: catalog); m.standardPlugins = false
    m.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    m.scan(); try await finish(m)
    let original = try #require(m.report?.assets.first)
    let subject = try #require(m.subject(asset: original))
    try await m.saveMetadata(MusicalMetadata(fields: ["character": ["warm"]]), subject: subject)
    m.query = "e warm"; #expect(m.outline.roots.count == 1)
    m.query = "x warm"; #expect(m.outline.roots.isEmpty)
    m.query = ""
    try f.file("Plugins/Example.component/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.fixture.example.au</string></dict></plist>")
    m.scan(); try await finish(m)
    #expect(m.pluginProducts.count == 1)
    let added = try #require(m.report?.assets.first { $0.format == "component" })
    let addedSubject = try #require(m.subject(asset: added))
    try await m.saveMetadata(MusicalMetadata(fields: ["character": ["dark"]]), subject: addedSubject)
    #expect(subject.key == addedSubject.key)
    m.musicalFilter = ["character": "warm"]; #expect(m.outline.nodes.isEmpty)
    m.musicalFilter = ["character": "dark"]; #expect(m.outline.nodes.count == 1)
    #expect(m.metadataOverrides[addedSubject.key]?[.character] == ["dark"])
    m.musicalFilter = [:]; m.recentOnly = true; #expect(m.outline.nodes.isEmpty)
    m.recentOnly = false; m.query = "dark"; #expect(m.outline.nodes.count == 1)
    try await catalog.recordRemovalIntent(paths: [added.path])
    let reopened = CatalogModel(catalogStore: catalog); reopened.standardPlugins = false
    reopened.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    await reopened.restoreSavedCatalog()
    reopened.query = "dark"; #expect(reopened.outline.nodes.count == 1)
    #expect(reopened.metadataOverrides[subject.key]?[.character] == ["dark"])
}

@Test @MainActor func persistedFabFilterSplitIdentityConvergesWithoutLosingEditsOrHistory() async throws {
    let f = try CatalogFixture()
    let plist = "Plugins/FabFilter Pro-C 2.vst3/Contents/Info.plist"
    try f.file(plist, "<plist><dict><key>CFBundleIdentifier</key><string>com.fabfilter.Pro-C.Legacy.2</string></dict></plist>")
    let root = f.root.appendingPathComponent("Plugins")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(catalogStore: catalog); model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let original = try #require(model.pluginProducts.first)
    let nodeID = try #require(original.representative.catalogID)
    let subject = MetadataSubject(nodeID: original.id)
    try await model.saveMetadata(MusicalMetadata(fields: ["character": ["warm"]]), subject: subject)
    let used = Date(timeIntervalSince1970: 1_790_474_024)
    try await catalog.appendDateEvidence([AssetDateEvidence(sourceID: "fixture.use", evidenceID: "legacy-product-node",
        subjectID: nodeID, kind: .confirmedUse, eventDate: used, ingestedAt: used)], asOf: used)

    try f.file(plist, "<plist><dict><key>CFBundleIdentifier</key><string>com.fabfilter.Pro-C.Vst3.2</string></dict></plist>")
    try f.file("Plugins/FabFilter Pro-C 2.component/Contents/Info.plist",
        "<plist><dict><key>CFBundleIdentifier</key><string>com.fabfilter.Pro-C.AU.2</string></dict></plist>")
    try f.file("Plugins/FabFilter Pro-C 2 (Mono).vst/Contents/Info.plist",
        "<plist><dict><key>CFBundleIdentifier</key><string>com.fabfilter.Pro-C.Mono.Vst.2</string></dict></plist>")
    model.scan(scannedKinds: [.plugin]); try await finish(model)

    let repaired = try #require(model.pluginProducts.first)
    #expect(model.pluginProducts.count == 1)
    #expect(repaired.installations.count == 3)
    #expect(model.metadataOverrides[MetadataSubject(nodeID: repaired.id).key]?[.character] == ["warm"])
    #expect(try await catalog.dateEvidence(for: nodeID, asOf: used.addingTimeInterval(1)).contains { $0.eventDate == used })
}

@Test @MainActor func productNameAndConfirmedDateSurviveRemovalOfSourceFormat() async throws {
    let f = try CatalogFixture()
    for (name, ext) in [("Glow AU", "component"), ("Glow VST3", "vst3")] {
        try f.file("Plugins/\(name).\(ext)/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.fixture.glow</string></dict></plist>")
    }
    let root = f.root.appendingPathComponent("Plugins")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(catalogStore: catalog); model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let original = try #require(model.pluginProducts.first)
    let source = try #require(original.installations.first { $0.name == original.name })
    let survivor = try #require(original.installations.first { $0.path != source.path })
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    try await catalog.appendDateEvidence([AssetDateEvidence(sourceID: "fixture.original", evidenceID: "source-only",
        subjectID: try #require(source.catalogID), kind: .confirmedAddition, eventDate: date, ingestedAt: Date())], asOf: Date())
    await model.reloadInstallerRecords()
    // Finder can supersede a confirmed source; either way the product date must remain qualified.
    let before = try #require(model.additionEvidence(survivor)?.upper)
    try await catalog.recordRemovalIntent(paths: [source.path])
    var request = ScanRequest(); request.plugins = [root]
    try await catalog.finalizePluginRemoval(attempted: [source.path], succeeded: [source.path], scope: CatalogScope(request))
    let reopened = CatalogModel(catalogStore: catalog); reopened.setStandardPlugins(false); reopened.addRoots([root], kind: .plugins)
    await reopened.restoreSavedCatalog()
    let remaining = try #require(reopened.pluginProducts.first)
    #expect(remaining.installations.count == 1 && remaining.installations[0].path == survivor.path)
    #expect(remaining.id == original.id && remaining.name == original.name)
    #expect(reopened.outline.roots.first?.title == original.name)
    #expect(reopened.additionEvidence(remaining.representative)?.upper == before)
}

@Test @MainActor func missingSetupRecoversSavedScopeButExplicitOrCorruptSetupDoesNot() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Glow.vst3/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.fixture.glow</string></dict></plist>")
    let root = f.root.appendingPathComponent("Plugins")
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let setup = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let first = CatalogModel(catalogStore: catalog); first.setStandardPlugins(false); first.addRoots([root], kind: .plugins)
    first.scan(scannedKinds: [.plugin]); try await finish(first)
    let recovered = CatalogModel(store: setup, catalogStore: catalog)
    await recovered.restoreSavedCatalog()
    #expect(recovered.onboardingCompleted && recovered.report?.assets.count == 1)
    #expect(recovered.roots[.plugins] == [root] && !recovered.standardPlugins)
    let configured = CatalogModel(store: setup, catalogStore: catalog)
    let draft = configured.setupDraft(); draft.standardPlugins = false
    draft.addRoots([f.root.appendingPathComponent("Different")], kind: .plugins)
    try configured.acceptSetup(draft, remember: true)
    let explicit = CatalogModel(store: setup, catalogStore: catalog)
    await explicit.restoreSavedCatalog()
    #expect(explicit.report == nil && explicit.roots[.plugins] == [f.root.appendingPathComponent("Different")])
    try Data("{broken".utf8).write(to: setup.url)
    let corrupt = CatalogModel(store: setup, catalogStore: catalog)
    await corrupt.restoreSavedCatalog()
    #expect(corrupt.report == nil && corrupt.setupNotice != nil)
}

@Test @MainActor func usageUnknownIsDistinctNavigationAndDoesNotInventDates() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Warm Strings.vst3/Contents/marker")
    let model = CatalogModel(); model.standardPlugins = false
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(); try await finish(model)
    let browse = model.navigationQuery
    model.usageFilter = .unknown
    #expect(model.hasFilters && model.navigationQuery != browse)
    #expect(model.visibleAssets.count == 1)
    let node = try #require(model.outline.nodes.first(where: { $0.kind == .plugin }))
    #expect(model.tagSummary(node).contains("Strings"))
    #expect(model.tagSummary(node).contains("Warm"))
    #expect(!model.metadataDetail(node).contains(f.root.path))
    model.musicalFilter = ["instrument": "accordion"]
    #expect(model.outline.nodes.isEmpty)
    model.reset()
    #expect(model.usageFilter == .all)
}

@Test @MainActor func nativeReviewedTagCoverageOnSavedCatalog() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_TAG_CATALOG_RUNTIME"] == "1" else { return }
    let start = ProcessInfo.processInfo.systemUptime
    let model = CatalogModel(store: .application, catalogStore: .application,
        tagSources: ProductTagSources.all)
    await model.restoreSavedCatalog()
    let restoredAt = ProcessInfo.processInfo.systemUptime
    let candidates = model.pluginProducts.map(\.representative)
        + (model.report?.assets.filter { $0.kind == .library } ?? [])
    let matched = candidates.filter { model.productTagSource($0) != nil }
    let matchedAt = ProcessInfo.processInfo.systemUptime
    let tagged = candidates.filter { asset in
        model.effectiveMetadata(asset: asset).fields.values.contains { !$0.isEmpty }
    }
    print("Reviewed tag runtime: sources=\(ProductTagSources.all.count), products=\(candidates.count), reviewedMatches=\(matched.count), effectiveTags=\(tagged.count), restore=\(restoredAt - start)s, match=\(matchedAt - restoredAt)s, metadata=\(ProcessInfo.processInfo.systemUptime - matchedAt)s")
    #expect(ProductTagSources.all.count == 400)
    #expect(ProductTagSources.all.filter { $0.kind == .plugin }.count == 200)
    #expect(ProductTagSources.all.filter { $0.kind == .library }.count == 200)
    #expect(!candidates.isEmpty)
}

@Test @MainActor func vst3VendorCategoriesFlowThroughOfflineCacheAndRespectReviewedAndUserPrecedence() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/SuperSynth.vst3/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.supersynth</string></dict></plist>")
    try f.file("Plugins/SuperSynth.component/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.supersynth</string></dict></plist>")
    try f.file("Plugins/SuperSynth.vst3/Contents/Resources/moduleinfo.json", """
    // JSON5 accepted by the VST3 module descriptor reader.
    { 'Factory Info': { Vendor: 'Example Audio' }, Classes: [{ Category: 'Audio Module Class', Name: 'SuperSynth', 'Sub Categories': ['Fx', 'Dynamics', 'Synth',], }], }
    """)
    let reviewed = ProductTagSource(id: "reviewed-supersynth", kind: .plugin, names: ["SuperSynth"], makers: ["Example Audio"], bundlePrefix: nil,
        endpoint: URL(string: "https://example.com/supersynth")!, page: URL(string: "https://example.com/supersynth")!, format: .metaDescription,
        remoteName: "SuperSynth", descriptionDigest: String(repeating: "a", count: 64), metadata: MusicalMetadata(fields: ["function": ["reviewed function"]]))
    let store = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(catalogStore: store, tagSources: [reviewed])
    model.standardPlugins = false; model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let asset = try #require(model.report?.assets.first(where: { $0.format == "vst3" }))
    let au = try #require(model.report?.assets.first(where: { $0.format == "component" }))
    #expect(model.productTagSource(au)?.id == reviewed.id)
    #expect(model.suggestedMetadata(asset: au)[.function] == ["reviewed function"])
    #expect(asset.vst3Categories?.metadata[.function] == ["dynamics", "fx"])
    #expect(model.suggestedMetadata(asset: asset)[.function] == ["reviewed function"])
    #expect(model.suggestedMetadata(asset: asset)[.instrument] == ["synth"])
    #expect(model.productTagProvenance(asset).contains("Vendor VST3 moduleinfo.json categories"))
    let subject = try #require(model.subject(asset: asset))
    try await model.saveMetadata(MusicalMetadata(fields: ["function": []]), subject: subject)
    #expect(model.effectiveMetadata(asset: asset)[.function] == [])

    try FileManager.default.removeItem(at: f.root.appendingPathComponent("Plugins/SuperSynth.vst3/Contents/Resources/moduleinfo.json"))
    let reopened = CatalogModel(catalogStore: store, tagSources: [reviewed])
    reopened.standardPlugins = false; reopened.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    await reopened.restoreSavedCatalog()
    let cached = try #require(reopened.report?.assets.first(where: { $0.format == "vst3" }))
    #expect(cached.vst3Categories?.metadata[.function] == ["dynamics", "fx"])
    #expect(reopened.effectiveMetadata(asset: cached)[.function] == [])
}

@Test @MainActor func sharedAutomaticTagsSurviveOfflineReopenAndUserClear() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Fixture Compressor.vst3/Contents/Resources/moduleinfo.json", """
    {"Factory Info":{"Vendor":"FabFilter"},"Classes":[{"Category":"Audio Module Class","Name":"Fixture Compressor","Sub Categories":["Fx"]}]}
    """)
    try f.file("Plugins/LittlePlate.vst3/Contents/Resources/moduleinfo.json", """
    {"Factory Info":{"Vendor":"Soundtoys"},"Classes":[{"Category":"Audio Module Class","Name":"LittlePlate","Sub Categories":["Fx"]}]}
    """)
    let record: [String: Any] = [
        "id": "automatic-fixture-compressor", "kind": "plugin", "names": ["Fixture Compressor"],
        "makers": ["FabFilter"], "endpoint": "https://www.fabfilter.com/products/pro-c-2-compressor-plug-in",
        "page": "https://www.fabfilter.com/products/pro-c-2-compressor-plug-in", "format": "metaDescription",
        "remoteName": "Fixture Compressor", "descriptionDigest": "", "networkEnabled": false,
        "metadata": ["function": ["compressor"]], "reviewRecordID": "automatic-fixture-compressor",
        "reviewedAt": "2026-10-06", "taxonomyVersion": 1,
        "sourceFact": "Synthetic cache fixture.", "provenance": "automatic"
    ]
    let retired: [String: Any] = [
        "id": "external-p-f3830ef59264", "kind": "plugin", "names": ["LittlePlate"],
        "makers": ["Soundtoys"], "endpoint": "https://www.soundtoys.com/product/little-plate/",
        "page": "https://www.soundtoys.com/product/little-plate/", "format": "metaDescription",
        "remoteName": "LittlePlate", "descriptionDigest": "", "networkEnabled": false,
        "metadata": ["function": ["wrong-cache-tag"]], "reviewRecordID": "external-p-f3830ef59264",
        "reviewedAt": "2026-10-06", "taxonomyVersion": 1, "provenance": "curated"
    ]
    let cachedData = try JSONSerialization.data(withJSONObject: ["version": 2, "records": [retired], "automaticRecords": [record]])
    let shared = SharedProductTagStore(url: f.root.appendingPathComponent("Private/shared.json"))
    try await shared.save(SharedProductTagSnapshot(catalogData: cachedData, etag: "\"old\"",
        misses: ["old-lookup": Date().addingTimeInterval(3_600)], serviceRetryAfter: Date().addingTimeInterval(3_600)))
    let catalog = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let plugins = f.root.appendingPathComponent("Plugins")
    let model = CatalogModel(catalogStore: catalog, sharedTagStore: shared)
    model.standardPlugins = false; model.addRoots([plugins], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let asset = try #require(model.report?.assets.first { $0.name == "Fixture Compressor" })
    #expect(model.productTagSource(asset)?.provenance == .automatic)
    #expect(model.effectiveMetadata(asset: asset)[.function] == ["compressor"])
    let little = try #require(model.report?.assets.first { $0.name == "LittlePlate" })
    #expect(model.productTagSource(little)?.id == "soundtoys-little-plate")
    #expect(model.effectiveMetadata(asset: little)[.function] == ["reverb"])
    let subject = try #require(model.subject(asset: asset))
    try await model.saveMetadata(MusicalMetadata(fields: ["function": []]), subject: subject)
    #expect(model.effectiveMetadata(asset: asset)[.function] == [])
    let reopened = CatalogModel(catalogStore: catalog, sharedTagStore: shared)
    reopened.standardPlugins = false; reopened.addRoots([plugins], kind: .plugins)
    await reopened.restoreSavedCatalog()
    let cached = try #require(reopened.report?.assets.first { $0.name == "Fixture Compressor" })
    #expect(reopened.productTagSource(cached)?.provenance == .automatic)
    #expect(reopened.suggestedMetadata(asset: cached)[.function] == ["compressor"])
    #expect(reopened.effectiveMetadata(asset: cached)[.function] == [])
    let reopenedLittle = try #require(reopened.report?.assets.first { $0.name == "LittlePlate" })
    #expect(reopened.productTagSource(reopenedLittle)?.id == "soundtoys-little-plate")
    #expect(reopened.effectiveMetadata(asset: reopenedLittle)[.function] == ["reverb"])
    #expect((try await shared.load()).misses.count == 1)
}

@Test @MainActor func vendorTagsRespectOverridesAndDoNotPromotePatches() async throws {
    let f = try CatalogFixture()
    try f.file("Libraries/Strings/Product.nicnt", "<ProductHints><Product><Name>Berlin Strings</Name><Company>Orchestral Tools</Company></Product></ProductHints>")
    try f.file("Libraries/Strings/Solo Piano.nki")
    let store = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(catalogStore: store)
    model.standardPlugins = false; model.category = .library
    model.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries)
    model.scan(); try await finish(model)
    let asset = try #require(model.report?.assets.first(where: { $0.kind == .library }))
    #expect(model.effectiveMetadata(asset: asset)[.technique] == ["legato"])
    #expect(model.productTagProvenance(asset).contains("Reviewed metadata record berlin-strings v1"))
    let instrument = try #require(asset.libraryMetadata?.instruments.first)
    #expect(model.effectiveMetadata(asset: asset, instrument: instrument)[.technique] == nil)
    let subject = try #require(model.subject(asset: asset))
    model.query = "legato"; #expect(!model.outline.nodes.isEmpty)
    try await model.saveMetadata(MusicalMetadata(fields: ["technique": []]), subject: subject)
    #expect(model.outline.nodes.isEmpty)
    try await model.undoMetadata(); #expect(!model.outline.nodes.isEmpty)
    try await model.saveMetadata(MusicalMetadata(fields: ["technique": []]), subject: subject)
    model.query = ""
    #expect(model.effectiveMetadata(asset: asset)[.technique] == [])
    #expect(model.effectiveMetadata(asset: asset)[.technique] == [])
}

@Test @MainActor func headerOrderingUnknownsAndPlainSearch() async throws {
    let f = try CatalogFixture()
    try f.file("PathOnlyToken/Alpha Sound.wav", "123456789")
    try f.file("PathOnlyToken/Zebra Sound.wav", "1")
    let model = CatalogModel(); model.standardPlugins = false
    model.addRoots([f.root.appendingPathComponent("PathOnlyToken")], kind: .samples)
    model.scan(); try await finish(model); model.category = .sample
    for reversed in [false, true] {
        model.sort = .size; model.sortReversed = reversed
        let expected = reversed ? ["Zebra Sound", "Alpha Sound"] : ["Alpha Sound", "Zebra Sound"]
        #expect(model.visibleAssets.map(\.name) == expected)
        #expect(model.outline.nodes.filter { $0.kind == .sample }.map(\.title) == expected)
        model.query = "sound"
        #expect(model.outline.roots.map(\.title) == expected)
        model.query = ""
        #expect(CatalogOrdering.precedes(title: "Known", id: "1", size: 1, date: nil, format: "WAV", otherTitle: "Unknown", otherID: "2", otherSize: nil, otherDate: nil, otherFormat: "WAV", sort: .size, reversed: reversed))
        #expect(CatalogOrdering.precedes(title: "Known", id: "1", size: 1, date: Date(), format: "WAV", otherTitle: "Unknown", otherID: "2", otherSize: nil, otherDate: nil, otherFormat: "WAV", sort: .recency, reversed: reversed))
    }
    model.sort = .name; model.sortReversed = true
    #expect(model.visibleAssets.map(\.name) == ["Zebra Sound", "Alpha Sound"])
    model.query = "PathOnlyToken"
    #expect(model.visibleAssets.isEmpty && model.outline.nodes.isEmpty)
    model.query = ""; model.sort = .installed
    #expect(model.visibleAssets.map(\.name) == ["Alpha Sound", "Zebra Sound"])
    model.reset(); #expect(!model.sortReversed)
}

@Test @MainActor func productPillEditsAreAtomicPreserveDifferencesAndUndoOnce() async throws {
    let f = try CatalogFixture()
    for ext in ["vst3", "component"] {
        try f.file("Plugins/Warm Strings.\(ext)/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.example.test.\(ext)</string><key>CFBundleName</key><string>Warm Strings</string></dict></plist>")
    }
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    func model() -> CatalogModel {
        let m = CatalogModel(catalogStore: catalog); m.standardPlugins = false
        m.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins); return m
    }
    let m = model(); m.scan(); try await finish(m)
    let product = try #require(m.pluginProducts.first); #expect(product.installations.count == 2)
    let a = product.installations[0], b = product.installations[1]
    let sa = try #require(m.subject(asset: a)), sb = try #require(m.subject(asset: b))
    try await m.saveMetadata(MusicalMetadata(fields: ["character": ["dark"], "technique": ["legato"]]), subject: sa)
    let before = m.metadataOverrides
    let node = try #require(m.outline.roots.first)
    try await m.changeTag("airy", facet: .character, removing: false, node: node)
    #expect(sa.key == sb.key)
    #expect(m.effectiveMetadata(asset: a)[.character] == ["airy", "dark"])
    #expect(m.effectiveMetadata(asset: b)[.character] == ["airy", "dark"])
    #expect(m.metadataOverrides[sa.key]?[.technique] == ["legato"])
    let reopened = model(); await reopened.restoreSavedCatalog()
    #expect(reopened.metadataOverrides == m.metadataOverrides)
    try await m.undoMetadata(); #expect(m.metadataOverrides == before)
    try await m.changeTag("dark", facet: .character, removing: true, node: node)
    #expect(m.metadataOverrides[sa.key]?[.character] == [])
    let suppressed = model(); await suppressed.restoreSavedCatalog()
    #expect(suppressed.effectiveMetadata(asset: b)[.character] == [])
    try await m.undoMetadata(); #expect(m.metadataOverrides == before)
    do {
        try await catalog.saveMetadataBatch([(sa, MusicalMetadata(fields: ["character": ["bright"]])), (MetadataSubject(nodeID: "missing"), MusicalMetadata(fields: ["character": ["bright"]]))])
        Issue.record("Missing later subject must roll back earlier edits")
    } catch {}
    let rolledBack = model(); await rolledBack.restoreSavedCatalog()
    #expect(rolledBack.metadataOverrides == before)
    try await m.changeTag("bright", facet: .character, removing: false, node: node)
    #expect(m.metadataOverrides[sa.key]?[.character]?.contains("bright") == true)
    #expect(m.effectiveMetadata(asset: b)[.character]?.contains("bright") == true)
    try await m.undoMetadata(); #expect(m.metadataOverrides == before)
}

@Test @MainActor func appearancePersistsDefaultsAndRejectsInvalidValues() throws {
    let f = try CatalogFixture(); let store = SetupStore(url: f.root.appendingPathComponent("appearance.json"))
    let model = CatalogModel(store: store)
    #expect(model.appearance == .light)
    for mode in CatalogAppearance.allCases {
        let draft = model.setupDraft(); draft.appearance = mode
        try model.acceptSetup(draft, remember: true)
        #expect(CatalogModel(store: store).appearance == mode)
        #expect(model.setupDraft().appearance == mode)
    }
    model.reset(); #expect(model.appearance == .light)
    try Data("{\"version\":1,\"settings\":{}}".utf8).write(to: store.url)
    #expect(CatalogModel(store: store).appearance == .light)
    for invalid in ["\"sepia\"", "true", "5", "null"] {
        let data = Data("{\"version\":1,\"settings\":{\"appearance\":\(invalid)}}".utf8)
        try data.write(to: store.url)
        let rejected = CatalogModel(store: store)
        #expect(rejected.appearance == .light && rejected.setupNotice != nil)
        let draft = rejected.setupDraft(); draft.appearance = .dark
        #expect(throws: (any Error).self) { try rejected.acceptSetup(draft, remember: true) }
        #expect(rejected.appearance == .light)
        #expect(try Data(contentsOf: store.url) == data)
        try rejected.acceptSetup(draft, remember: false)
        #expect(rejected.appearance == .dark)
        #expect(try Data(contentsOf: store.url) == data)
    }
}

@Test @MainActor func appearanceSaveDoesNotInvalidateInventoryAndIgnoresRetiredOnlinePreference() async throws {
    let f = try CatalogFixture(); let store = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    try f.file("Samples/tone.wav")
    let model = CatalogModel(store: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    model.scan(); try await finish(model)
    #expect(!model.configurationChanged)
    let draft = model.setupDraft(); draft.appearance = .dark
    try model.acceptSetup(draft, remember: true)
    #expect(!model.configurationChanged && !model.isScanning && model.report != nil)
    let reopened = CatalogModel(store: store)
    #expect(reopened.appearance == .dark && reopened.roots == model.roots)
    // Older setup files can still contain the retired online preference.
    let legacy = try Data(contentsOf: store.url)
    var envelope = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
    var settings = try #require(envelope["settings"] as? [String: Any])
    settings["online_tags"] = true
    envelope["settings"] = settings
    try JSONSerialization.data(withJSONObject: envelope).write(to: store.url)
    let migrated = CatalogModel(store: store)
    #expect(migrated.appearance == .dark && migrated.roots == model.roots)
    try migrated.acceptSetup(migrated.setupDraft(), remember: true)
    let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
    let savedSettings = try #require(saved["settings"] as? [String: Any])
    #expect(savedSettings["online_tags"] == nil)
    let changed = model.setupDraft(); changed.addRoots([f.root], kind: .libraries)
    try model.acceptSetup(changed, remember: true)
    #expect(model.configurationChanged && !model.isScanning)
}

@Test @MainActor func sectionScansPreserveOtherCategoriesAcrossTabChangesRestartAndSaveFailure() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Echo.vst3/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>com.test.echo</string></dict></plist>")
    try f.file("Samples/Kick.wav"); try f.file("Libraries/Strings/Violin.nki")
    let store = SetupStore(url: f.root.appendingPathComponent("setup.json"))
    let catalog = CatalogStore(url: f.root.appendingPathComponent("catalog.sqlite"))
    let model = CatalogModel(store: store, catalogStore: catalog)
    let draft = model.setupDraft(); draft.standardPlugins = false
    for kind in [RootKind.plugins, .samples, .libraries] { draft.addRoots([f.root.appendingPathComponent(kind.rawValue)], kind: kind) }
    try model.acceptSetup(draft, remember: true)
    model.scan(); try await finish(model)
    let original = try #require(model.report)
    try f.file("Samples/New.wav")
    model.category = .plugin; model.scan(scannedKinds: [.plugin]); model.category = .library
    try await finish(model)
    #expect(model.report?.assets.count == original.assets.count)
    #expect(model.report?.assets.filter { $0.kind != .plugin }.allSatisfy { $0.catalogStale == false } == true)
    let reopened = CatalogModel(store: store, catalogStore: catalog); await reopened.restoreSavedCatalog()
    #expect(reopened.report?.assets.count == original.assets.count)
    model.scan(scannedKinds: [.sample]); try await finish(model)
    #expect(model.report?.assets.filter { $0.kind == .sample }.count == 2)
    let newRoots = model.setupDraft(); newRoots.addRoots([f.root.appendingPathComponent("ExtraPlugins")], kind: .plugins); newRoots.addRoots([f.root.appendingPathComponent("ExtraSamples")], kind: .samples)
    try model.acceptSetup(newRoots, remember: true)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    #expect(model.configurationChanged) // Sample/library exclusions still need their scans.
    model.scan(scannedKinds: [.sample, .library]); try await finish(model)
    #expect(!model.configurationChanged)
    // Persistence failure keeps all non-target live inventory available.
    try Data("corrupt".utf8).write(to: f.root.appendingPathComponent("catalog.sqlite"))
    let beforeFailure = model.report!.assets.filter { $0.kind != .plugin }.map(\.path).sorted()
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    #expect(model.catalogNotice != nil)
    #expect(model.report!.assets.filter { $0.kind != .plugin }.map(\.path).sorted() == beforeFailure)
}

@Test @MainActor func liveVst3CandidatePersistsWithoutBecomingUsageOrResolvingCollisions() async throws {
    let f = try CatalogFixture()
    try f.file("Plugins/Example.vst3/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.fixture.example</string></dict></plist>")
    try f.file("Projects/Test.als", """
    <Ableton MajorVersion="5" MinorVersion="12.0_12402" Creator="Ableton Live 12.4.5"><LiveSet><Tracks><MidiTrack>
    <DeviceChain><DeviceChain><Devices><PluginDevice><PluginDesc><Vst3PluginInfo><Name Value="Example"/>
    </Vst3PluginInfo></PluginDesc></PluginDevice></Devices></DeviceChain></DeviceChain>
    </MidiTrack></Tracks></LiveSet></Ableton>
    """)
    let database = f.root.appendingPathComponent("State/catalog.sqlite")
    let model = CatalogModel(catalogStore: CatalogStore(url: database)); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.addRoots([f.root.appendingPathComponent("Projects")], kind: .projects)
    model.scan(); try await finish(model)
    let product = try #require(model.pluginProducts.first)
    #expect(model.pluginReferenceDetail(product).contains("Candidate saved-project matches"))
    #expect(model.referenceText(product.installations[0]) == "Unknown")
    let reopened = CatalogModel(catalogStore: CatalogStore(url: database)); reopened.setStandardPlugins(false)
    reopened.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    reopened.addRoots([f.root.appendingPathComponent("Projects")], kind: .projects)
    await reopened.restoreSavedCatalog()
    let restored = try #require(reopened.pluginProducts.first)
    #expect(reopened.pluginReferenceDetail(restored).contains("Candidate saved-project matches"))
    #expect(reopened.referenceText(restored.installations[0]) == "Unknown")
    #expect(reopened.report?.projects.first?.references.first?.resolvedPath == nil)
    // Same display name, unrelated vendor: do not assign either an ambiguous reference.
    try f.file("Plugins/Other/Example.vst3/Contents/Info.plist", "<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>org.other.example</string></dict></plist>")
    model.scan(); try await finish(model)
    #expect(model.pluginProducts.count == 2)
    for candidate in model.pluginProducts {
        #expect(!model.pluginReferenceDetail(candidate).contains("Candidate saved-project matches"))
        #expect(model.referenceText(candidate.installations[0]) == "Unknown")
    }
}

private actor ReceiptCollectionGate {
    var assets: [[Asset]] = []
    var cancelled = 0
    private var pending: [Int: CheckedContinuation<PackageReceiptCollection, Never>] = [:]
    func collect(_ values: [Asset]) async -> PackageReceiptCollection {
        let index = assets.count; assets.append(values)
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { pending[index] = $0 }
        }, onCancel: { Task { await self.didCancel() } })
    }
    private func didCancel() { cancelled += 1 }
    func release(_ index: Int) {
        pending.removeValue(forKey: index)?.resume(returning: PackageReceiptCollection(status: .complete, commands: index + 1,
            payloadQueries: 0, attempted: 0, recorded: 0, failures: 0))
    }
}

@Test @MainActor func receiptCollectionFollowsFreshPluginSavesWithoutBlockingInventoryAndIgnoresLateResults() async throws {
    let f = try CatalogFixture(), gate = ReceiptCollectionGate()
    let root = f.root.appendingPathComponent("Plugins")
    _ = try f.file("Plugins/Unit.component/Contents/Info.plist", "fixture")
    let store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let model = CatalogModel(catalogStore: store, receiptCollector: { assets, _ in await gate.collect(assets) })
    model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    for _ in 0..<100 where await gate.assets.count < 1 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await gate.assets.count == 1)
    #expect(await gate.assets[0].allSatisfy { $0.kind == .plugin && $0.catalogID != nil && $0.catalogStale != true })
    #expect(!model.isBusy && model.receiptCollection == nil)
    model.scan(scannedKinds: [.sample]); try await finish(model)
    for _ in 0..<100 where await gate.cancelled < 1 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await gate.cancelled == 1)
    #expect(await gate.assets.count == 1)
    await gate.release(0); try await Task.sleep(for: .milliseconds(20))
    #expect(model.receiptCollection == nil)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    for _ in 0..<100 where await gate.assets.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
    await gate.release(1)
    for _ in 0..<100 where model.receiptCollection == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(model.receiptCollection?.commands == 2)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    for _ in 0..<100 where await gate.assets.count < 3 { try await Task.sleep(for: .milliseconds(5)) }
    model.reset(); await gate.release(2); try await Task.sleep(for: .milliseconds(20))
    #expect(model.report == nil && model.receiptCollection == nil)
    let restored = CatalogModel(catalogStore: store, receiptCollector: { assets, _ in await gate.collect(assets) })
    restored.setStandardPlugins(false); restored.addRoots([root], kind: .plugins)
    await restored.restoreSavedCatalog()
    #expect(restored.report != nil)
    #expect(await gate.assets.count == 3)
}

@Test @MainActor func receiptCollectionDoesNotStartAfterFailedCatalogSave() async throws {
    let f = try CatalogFixture(), gate = ReceiptCollectionGate()
    let root = f.root.appendingPathComponent("Plugins")
    _ = try f.file("Plugins/Unit.component/Contents/Info.plist", "fixture")
    let blocked = try f.file("blocked", "not a directory")
    let model = CatalogModel(catalogStore: CatalogStore(url: blocked.appendingPathComponent("catalog.sqlite")),
                             receiptCollector: { assets, _ in await gate.collect(assets) })
    model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    #expect(model.catalogNotice != nil && model.report?.assets.count == 1)
    #expect(await gate.assets.isEmpty)
}

@Test @MainActor func receiptCollectionCancelsOnRootSettingsAndRemovalChanges() async throws {
    for change in ["add", "remove", "settings", "standard", "removal"] {
        let f = try CatalogFixture(), gate = ReceiptCollectionGate()
        let root = f.root.appendingPathComponent("Plugins")
        _ = try f.file("Plugins/Unit.component/Contents/Info.plist", "fixture")
        let database = f.root.appendingPathComponent("Private/catalog.sqlite")
        let model = CatalogModel(catalogStore: CatalogStore(url: database), receiptCollector: { assets, _ in await gate.collect(assets) })
        model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
        let configuredRoot = try #require(model.roots[.plugins]?.first)
        model.scan(scannedKinds: [.plugin]); try await finish(model)
        for _ in 0..<100 where await gate.assets.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await gate.assets.count == 1)
        switch change {
        case "add": model.addRoots([f.root.appendingPathComponent("Extra")], kind: .plugins)
        case "remove": model.removeRoot(configuredRoot, kind: .plugins)
        case "settings":
            let draft = model.setupDraft(); draft.removeRoot(configuredRoot, kind: .plugins)
            try model.acceptSetup(draft, remember: false)
        case "standard": model.setStandardPlugins(true)
        default:
            let plugin = try #require(model.report?.assets.first)
            #expect(model.canReviewRemoval(plugin), "Fixture should reach reviewed removal")
            // Fail the intent write in this disposable catalog; never reach actual Trash.
            try Data("invalid fixture database".utf8).write(to: database)
            #expect(await model.trashPlugins([plugin]).isEmpty)
            #expect(FileManager.default.fileExists(atPath: plugin.path))
        }
        for _ in 0..<100 where await gate.cancelled == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await gate.cancelled == 1, "Change: \(change)")
        await gate.release(0); try await Task.sleep(for: .milliseconds(10))
        #expect(model.receiptCollection == nil, "Change: \(change)")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PRISM_AUTOMATIC_RECEIPT_RUNTIME"] == "1"))
@MainActor func nativeAutomaticReceiptRuntimeModel() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Native/catalog.sqlite"))
    let root = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components")
    let paths = ["FabFilter Pro-Q 4.component", "Kontakt 8.component", "Diva.component"].map { root.appendingPathComponent($0) }
    let identities = paths.map { PluginFileIdentity.read($0.path) }
    #expect(identities.allSatisfy { $0 != nil })
    let model = CatalogModel(catalogStore: store, receiptCollector: { assets, store in
        await PackageReceiptCollector.collect(assets: assets, store: store)
    })
    model.setStandardPlugins(false); model.addRoots(paths, kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    #expect(model.report?.assets.count == 3 && model.catalogNotice == nil)
    let deadline = Date().addingTimeInterval(125)
    while model.receiptCollection == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
    let collection = try #require(model.receiptCollection)
    #expect(collection.status == .complete && collection.recorded >= 2)
    for asset in model.report?.assets ?? [] {
        let node = try #require(asset.catalogID)
        let history = try await store.dateEvidence(for: node, asOf: Date())
        if !asset.path.hasSuffix("Diva.component") {
            #expect(!history.isEmpty)
            #expect(model.installerDate(asset).date != nil)
        }
        #expect(try await store.dateSummary(for: node, asOf: Date()).lastUsed == nil)
    }
    #expect(paths.map { PluginFileIdentity.read($0.path) } == identities)
}

private func presentationReceipt(_ asset: Asset, id: String, seconds: Double) throws -> AssetDateEvidence {
    AssetDateEvidence(sourceID: PackageReceiptProvenance.sourceID, evidenceID: id,
        subjectID: try #require(asset.catalogID), kind: .installationRecord,
        eventDate: Date(timeIntervalSince1970: seconds), ingestedAt: Date(),
        packageReceipt: PackageReceiptProvenance(packageID: "fixture." + id, packageVersion: "1.0",
            bundlePath: asset.path, bundleIdentifier: asset.bundleIdentifier ?? "fixture", bundleVersions: ["1.0"]))
}

@Test @MainActor func installerPresentationGroupsExactRecordsAndRestoresHistory() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    for name in ["Echo.component", "Echo.vst3", "Older.component", "Unknown.component"] {
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example." + name.components(separatedBy: ".")[0]], format: .xml, options: 0)
        let path = try f.file("Plugins/" + name + "/Contents/Info.plist"); try data.write(to: path)
    }
    _ = try f.file("Samples/One.wav")
    let model = CatalogModel(catalogStore: store)
    model.setStandardPlugins(false); model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    model.scan(); try await finish(model)
    let assets = try #require(model.report?.assets)
    let echo = try #require(assets.first { $0.name == "Echo" && $0.format == "component" })
    let vst = try #require(assets.first { $0.name == "Echo" && $0.format == "vst3" })
    let older = try #require(assets.first { $0.name == "Older" })
    try await store.appendDateEvidence([presentationReceipt(echo, id: "echo", seconds: 200), presentationReceipt(older, id: "older", seconds: 100)], asOf: Date())
    await model.reloadInstallerRecords()
    #expect(model.installerDate(echo).date == Date(timeIntervalSince1970: 200))
    #expect(model.installerDate(echo).detail.contains("Records for 1 of 2 installations"))
    #expect(model.installerDate(vst, grouped: false).date == nil)
    #expect(model.installerDate(echo).accessibility.contains("separate from Finder Date Added"))
    #expect(model.additionDate(echo).value != "Unknown")
    #expect(model.additionDate(echo).detail.contains("Finder Date Added"))
    #expect(model.additionDate(echo).detail.contains("First indexed"))
    model.scan(scannedKinds: [.sample])
    #expect(model.installerDate(echo).date != nil)
    try await finish(model)
    await model.reloadInstallerRecords()
    let sample = try #require(model.report?.assets.first { $0.kind == .sample })
    #expect(model.installerDate(sample).date == nil)
    let reopened = CatalogModel(catalogStore: store)
    reopened.setStandardPlugins(false); reopened.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    reopened.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    await reopened.restoreSavedCatalog()
    #expect(reopened.installerDate(echo).date != nil)
    #expect(reopened.installerDate(echo).detail.contains("current installation not verified"))
    #expect(reopened.installerRecordDetail(echo).contains("current installation not verified"))
    reopened.scan(scannedKinds: [.plugin])
    #expect(reopened.installerDate(echo).value == "Checking…")
    try await finish(reopened)
    // An open format sheet retains this earlier Asset while the current node goes offline.
    try FileManager.default.moveItem(at: f.root.appendingPathComponent("Plugins"), to: f.root.appendingPathComponent("OfflinePlugins"))
    reopened.scan(scannedKinds: [.plugin]); try await finish(reopened)
    #expect(reopened.installerRecordDetail(echo).contains("current installation not verified"))
    #expect(reopened.installerRecordDetail(echo).contains("fixture.echo"))
}

private actor InstallerReadGate {
    var suspended = false
    private var continuation: CheckedContinuation<[Data: AssetDateEvidence], any Error>?
    func read() async throws -> [Data: AssetDateEvidence] {
        suspended = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func release(_ records: [Data: AssetDateEvidence]) { continuation?.resume(returning: records); continuation = nil }
}

@Test @MainActor func installerProjectionLateReadAndReadErrorsCannotRestoreInvalidDates() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Unit.component/Contents/Info.plist")
    var request = ScanRequest(); request.plugins = [f.root]
    _ = try await store.ingest(Scanner().scan(request), scope: CatalogScope(request))
    let gate = InstallerReadGate()
    let model = CatalogModel(catalogStore: store, installerRecordLoader: { _, _, _ in try await gate.read() })
    model.setStandardPlugins(false); model.addRoots([f.root], kind: .plugins)
    let restore = Task { await model.restoreSavedCatalog() }
    for _ in 0..<100 where !(await gate.suspended) { try await Task.sleep(for: .milliseconds(5)) }
    let asset = try #require(model.report?.assets.first)
    let record = try presentationReceipt(asset, id: "late", seconds: 200)
    #expect(model.installerDate(asset).value == "Checking…")
    model.reset(); await gate.release([Data(record.subjectID.utf8): record]); await restore.value
    #expect(model.report == nil && !model.isLoadingInstallerRecords && model.installerDate(asset).date == nil)
    let failed = CatalogModel(catalogStore: store, installerRecordLoader: { _, _, _ in throw CatalogStoreError.invalid })
    failed.setStandardPlugins(false); failed.addRoots([f.root], kind: .plugins)
    await failed.restoreSavedCatalog()
    #expect(failed.installerDate(asset).value == "Unavailable")
    #expect(failed.installerDate(asset).detail.contains("Check For Updates to retry"))
}

@Test @MainActor func additionPresentationSortsBoundsAndQualifiesSameDayIntervals() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let root = f.root.appendingPathComponent("Samples")
    _ = try f.file("Samples/Earlier.wav")
    var request = ScanRequest(); request.samples = [root]; let scope = CatalogScope(request)
    func withoutNativeDate(_ report: ScanReport) -> ScanReport {
        var assets = report.assets
        for index in assets.indices { assets[index].finderDateAdded = nil }
        return report.replacingAssets(assets)
    }
    let first = withoutNativeDate(Scanner().scan(request))
    _ = try await store.ingest(first, scope: scope, at: Date(timeIntervalSince1970: 100), additionContext: AdditionScanContext(scope: scope, startedAt: Date(timeIntervalSince1970: 90)))
    _ = try f.file("Samples/Later.wav")
    _ = try await store.ingest(withoutNativeDate(Scanner().scan(request)), scope: scope, at: Date(timeIntervalSince1970: 200), additionContext: AdditionScanContext(scope: scope, startedAt: Date(timeIntervalSince1970: 190)))
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false); model.addRoots([root], kind: .samples)
    await model.restoreSavedCatalog(); model.category = .sample; model.sort = .installed
    #expect(model.visibleAssets.map(\.name) == ["Earlier", "Later"])
    model.sortReversed = true
    #expect(model.visibleAssets.map(\.name) == ["Earlier", "Later"])
    let earlier = try #require(model.report?.assets.first { $0.name == "Earlier" })
    let later = try #require(model.report?.assets.first { $0.name == "Later" })
    #expect(model.additionDate(earlier).value == "Unknown")
    #expect(model.additionDate(later).value == "Unknown")
    #expect(model.additionDate(later).detail.contains("Observed arrival"))
    #expect(model.additionDate(earlier).detail.contains("First indexed"))
}

@Test @MainActor func additionBoundsRetainValidAbsenceThroughNoScanSettingsRoundtrip() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("A/First.wav"); _ = try f.file("B/Other.wav")
    let a = f.root.appendingPathComponent("A"), b = f.root.appendingPathComponent("B")
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false); model.addRoots([a], kind: .samples)
    model.scan(scannedKinds: [.sample]); try await finish(model)
    let baseline = try #require(model.catalogObservations.values.first?.addition?.upper)
    model.removeRoot(try #require(model.roots[.samples]?.first), kind: .samples); model.addRoots([b], kind: .samples)
    #expect(model.roots[.samples]?.map(\.path) == [b.path])
    model.removeRoot(try #require(model.roots[.samples]?.first), kind: .samples); model.addRoots([a], kind: .samples)
    #expect(model.roots[.samples]?.map(\.path) == [a.path])
    _ = try f.file("A/New.wav")
    model.scan(scannedKinds: [.sample]); try await finish(model)
    let asset = try #require(model.report?.assets.first { $0.name == "New" })
    let id = try #require(asset.catalogID)
    let bounds = try #require(model.catalogObservations[id]?.addition)
    #expect(bounds.basis == .observedArrival)
    #expect(try #require(bounds.lower) <= baseline)
    #expect(model.additionDate(asset).value != "Unknown")
    #expect(model.additionDate(asset).detail.contains("filesystem Date Added"))
    #expect(model.additionDate(asset).detail.contains("Observed arrival"))
}

@Test @MainActor func libraryAdditionUsesCatalogSelectionIdentity() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Libraries/Colors/Colors.nicnt", "<ProductHints><Product><Name>Colors</Name><Company>Example</Company></Product></ProductHints>")
    _ = try f.file("Libraries/Colors/Flute.nki")
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Libraries")], kind: .libraries)
    model.scan(scannedKinds: [.library]); try await finish(model)
    let asset = try #require(model.report?.assets.first { $0.kind == .library })
    #expect(model.additionDate(asset).value != "Unknown")
    #expect(model.additionDate(asset).detail.contains("filesystem Date Added"))
    #expect(model.additionDate(asset).detail.contains("First indexed"))
    #expect(model.lastUsed(asset).value == "Not Used Yet")
}

@Test @MainActor func pluginSizesAndOriginalDatesGroupConservativelyAcrossFormatsAndReopen() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    for format in ["component", "vst3", "aaxplugin"] {
        _ = try f.file("Plugins/Glow.\(format)/Contents/Info.plist",
                       "<plist><dict><key>CFBundleIdentifier</key><string>example.glow</string></dict></plist>")
        _ = try f.file("Plugins/Glow.\(format)/Contents/Plugin", String(repeating: "x", count: 100))
    }
    for format in ["component", "vst3"] {
        _ = try f.file("Plugins/Partial.\(format)/Contents/Info.plist",
                       "<plist><dict><key>CFBundleIdentifier</key><string>example.partial</string></dict></plist>")
    }
    _ = try f.file("Plugins/Partial.vst3/Contents/Plugin", String(repeating: "x", count: 20))
    let linked = try f.file("Plugins/Partial.component/Contents/Plugin", "x")
    try FileManager.default.createSymbolicLink(at: linked.deletingLastPathComponent().appendingPathComponent("Alias"), withDestinationURL: linked)
    let root = f.root.appendingPathComponent("Plugins")
    let model = CatalogModel(catalogStore: store)
    model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let glow = try #require(model.pluginProducts.first { $0.name == "Glow" })
    let partial = try #require(model.pluginProducts.first { $0.name == "Partial" })
    #expect(glow.installations.count == 3)
    let expected = glow.installations.compactMap(\.logicalBytes).reduce(0, +)
    #expect(expected > 300 && model.pluginSize(glow.representative).completeBytes == expected)
    #expect(model.pluginSize(partial.representative).completeBytes != nil)
    #expect(model.pluginSize(partial.representative).detail.contains("Measured bundle files"))
    #expect(model.additionDate(glow.representative).evidence?.basis == .exact || model.additionDate(glow.representative).value == "Unknown")
    #expect(model.outline.roots.first { $0.title == "Glow" }?.sizeText == model.pluginSize(glow.representative).value)
    model.sort = .size
    #expect(model.visibleAssets.map(\.name) == ["Glow", "Partial"])
    model.sortReversed = true
    #expect(model.visibleAssets.map(\.name) == ["Partial", "Glow"])
    let original = Date(timeIntervalSince1970: 1_700_000_000)
    let additions = try glow.installations.enumerated().map { index, asset -> AssetDateEvidence in
        let id = try #require(asset.catalogID)
        return AssetDateEvidence(sourceID: "fixture.confirmed-original", evidenceID: "glow-\(index)", subjectID: id,
                                 kind: .confirmedAddition, eventDate: original.addingTimeInterval(Double(index)), ingestedAt: Date())
    }
    try await store.appendDateEvidence([additions[0]], asOf: Date())
    await model.reloadInstallerRecords()
    #expect(model.additionDate(glow.representative).evidence?.upper != nil)
    try await store.appendDateEvidence(Array(additions.dropFirst()), asOf: Date())
    await model.reloadInstallerRecords()
    #expect(model.additionDate(glow.representative).evidence?.basis == .exact)
    #expect(model.additionDate(glow.representative).evidence?.upper == original)
    let reopened = CatalogModel(catalogStore: store)
    reopened.setStandardPlugins(false); reopened.addRoots([root], kind: .plugins)
    await reopened.restoreSavedCatalog()
    let savedGlow = try #require(reopened.pluginProducts.first { $0.name == "Glow" })
    #expect(reopened.pluginSize(savedGlow.representative).completeBytes == expected)
    #expect(reopened.pluginSize(savedGlow.representative).detail.contains("Saved size; choose Check For Updates to verify"))
    #expect(reopened.additionDate(savedGlow.representative).evidence?.upper == original)
}

@Test @MainActor func finderDateAddedUsesEarliestAvailableFormatAndSurvivesReopen() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    for ext in ["component", "vst3", "aaxplugin"] {
        _ = try f.file("Plugins/Glow.\(ext)/Contents/Info.plist",
            "<plist><dict><key>CFBundleIdentifier</key><string>org.example.glow</string></dict></plist>")
    }
    let root = f.root.appendingPathComponent("Plugins")
    let model = CatalogModel(catalogStore: store)
    model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    var assets = try #require(model.report?.assets)
    let earliest = Date(timeIntervalSince1970: 1_762_480_000)
    for index in assets.indices {
        assets[index].finderDateAdded = nil
        if assets[index].format == "aaxplugin" { assets[index].finderDateAdded = earliest }
        if assets[index].format == "vst3" { assets[index].finderDateAdded = earliest.addingTimeInterval(3600) }
    }
    var request = ScanRequest(); request.plugins = [root]
    _ = try await store.ingest(try #require(model.report).replacingAssets(assets), scope: CatalogScope(request), scannedKinds: [.plugin])
    let reopened = CatalogModel(catalogStore: store)
    reopened.setStandardPlugins(false); reopened.addRoots([root], kind: .plugins)
    await reopened.restoreSavedCatalog()
    let glow = try #require(reopened.pluginProducts.first { $0.name == "Glow" })
    #expect(glow.installations.count == 3 && glow.installations.filter { $0.finderDateAdded != nil }.count == 2)
    #expect(reopened.additionDate(glow.representative).evidence?.upper == earliest)
    #expect(reopened.additionDate(glow.representative).detail.contains("Finder Date Added"))
    #expect(reopened.additionDate(glow.representative).value != "Unknown")
    #expect(reopened.pluginSize(glow.representative).completeBytes != nil)
}

@Test @MainActor func pluginArrivalRemainsLabeledSeparatelyFromFinderDateAdded() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let root = f.root.appendingPathComponent("Plugins")
    _ = try f.file("Plugins/Glow.vst3/Contents/Info.plist",
        "<plist><dict><key>CFBundleIdentifier</key><string>org.example.glow</string></dict></plist>")
    let model = CatalogModel(catalogStore: store)
    model.setStandardPlugins(false); model.addRoots([root], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    _ = try f.file("Plugins/Glow.component/Contents/Info.plist",
        "<plist><dict><key>CFBundleIdentifier</key><string>org.example.glow</string></dict></plist>")
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let glow = try #require(model.pluginProducts.first { $0.name == "Glow" })
    #expect(glow.installations.count == 2)
    #expect(model.additionDate(glow.representative).detail.contains("Observed arrival"))
}

@Test @MainActor func usageCivilProjectionSortsFiltersAndRestoresWithoutUTCInference() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    for name in ["Earlier", "Later", "Unknown"] { _ = try f.file("Plugins/\(name).vst3/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>example.\(name)</string></dict></plist>") }
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins); model.scan(scannedKinds: [.plugin]); try await finish(model)
    for (name, day) in [("Earlier", "2026-09-20"), ("Later", "2026-09-25")] {
        let asset = try #require(model.report?.assets.first { $0.name == name }), id = try #require(asset.catalogID)
        let usage = try HostUsageProvenance(hostVersion: "12.4.6", classID: "12345678-1234-5678-ABCD-123456789ABC", pluginVersion: "1.0",
            localTime: SourceLocalTime(day + "T12:00:00.000000"), runHash: String(repeating: "a", count: 64), recordHash: String(repeating: "b", count: 64), recordOffset: 100)
        let record = try AssetDateEvidence(sourceID: HostUsageProvenance.sourceID, evidenceID: usage.eventID(subjectID: id), subjectID: id,
            kind: .confirmedUse, eventDate: nil, ingestedAt: Date(), hostUsage: usage)
        try await store.appendDateEvidence([record], asOf: Date())
    }
    // The scan's own projection can finish after isScanning clears. Wait until
    // both durable records are visible before asserting sort and filter behavior.
    let usageDeadline = Date().addingTimeInterval(2)
    repeat {
        await model.reloadUsage()
        let names = ["Earlier", "Later"]
        if names.allSatisfy({ name in
            model.report?.assets.first(where: { $0.name == name }).flatMap { model.usageRecord($0) } != nil
        }) { break }
        try await Task.sleep(for: .milliseconds(10))
    } while Date() < usageDeadline
    model.sort = .recency
    #expect(model.visibleAssets.map(\.name) == ["Later", "Earlier", "Unknown"])
    #expect(model.outline.roots.map(\.title) == ["Later", "Earlier", "Unknown"])
    model.sortReversed = true
    #expect(model.visibleAssets.map(\.name) == ["Earlier", "Later", "Unknown"])
    let later = try #require(model.report?.assets.first { $0.name == "Later" })
    #expect(model.lastUsed(later).value == "2026-09-25")
    #expect(model.lastUsed(later).detail.contains("product history"))
    let manual = try HostUsageProvenance(hostVersion: "12.4.6", classID: "12345678-1234-5678-ABCD-123456789ABC",
        pluginVersion: "1.0", localTime: SourceLocalTime("2026-09-25T12:00:00.000000"),
        runHash: String(repeating: "c", count: 64), recordHash: String(repeating: "d", count: 64),
        recordOffset: 101, qualification: HostUsageProvenance.completedManualCreate)
    let manualRecord = try AssetDateEvidence(sourceID: manual.eventSourceID, evidenceID: manual.eventID(subjectID: "manual"),
        subjectID: "manual", kind: .confirmedUse, eventDate: nil, ingestedAt: Date(), hostUsage: manual)
    let manualPresentation = UsageDatePresentation(record: manualRecord)
    #expect(manualPresentation.detail.contains("Live plugin creation"))
    #expect(manualPresentation.accessibility.contains("created a VST3 plugin instance"))
    model.usageFilter = .unknown
    #expect(model.visibleAssets.map(\.name) == ["Unknown"])
    model.reset()
    #expect(model.usageRecord(later) == nil && !model.usageUnavailable)
}

@Test @MainActor func cubaseUsageProjectsAsHostQualifiedLastUsed() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Plugins/Q.vst3/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>fabfilter.q</string></dict></plist>")
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins); model.scan(scannedKinds: [.plugin]); try await finish(model)
    let asset = try #require(model.report?.assets.first), id = try #require(asset.catalogID)
    let use = CubasePluginUse(name: "Q", vendor: "FabFilter", version: "1", architecture: "arm64", eventID: "event", projectID: "p", reportedMilliseconds: 1_790_474_024_000)
    let record = AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.eventID, subjectID: id, kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: Date(timeIntervalSince1970: 1_790_474_025), cubaseUsage: use)
    try await store.appendDateEvidence([record], asOf: Date(timeIntervalSince1970: 1_790_474_025))
    await model.reloadUsage()
    #expect(!model.lastUsed(asset).value.contains("Local time"))
    #expect(model.lastUsed(asset).detail.contains("Cubase project load"))
    let bound = CubaseBoundPluginUse(use: use, pluginPath: asset.path, cid: String(repeating: "A", count: 32))
    let replay = try await store.recordCubaseUsage(bound, for: id, at: Date(timeIntervalSince1970: 1_790_474_085))
    #expect(replay == record)
}

@Test @MainActor func cubaseAttemptKeepsFirstDurableEventAcrossReplay() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Plugins/Q.vst3/Contents/Info.plist", "<plist><dict><key>CFBundleIdentifier</key><string>fabfilter.q</string></dict></plist>")
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let asset = try #require(model.report?.assets.first), id = try #require(asset.catalogID)
    let attempt = CubasePluginUse(name: "Q", vendor: "FabFilter", version: "1", architecture: "arm64",
        eventID: "same-event", projectID: "p", reportedMilliseconds: 1_790_474_024_000,
        qualification: "nativeAddAttempt")
    let mislabeled = AssetDateEvidence(sourceID: CubasePluginUse.sourceID,
        evidenceID: attempt.eventID, subjectID: id, kind: .confirmedUse,
        eventDate: attempt.reportedDate, ingestedAt: Date(timeIntervalSince1970: 1_790_474_025),
        cubaseUsage: attempt)
    #expect(throws: (any Error).self) {
        try AssetDateResolver.summarize([mislabeled], for: id,
            asOf: Date(timeIntervalSince1970: 1_790_474_025))
    }
    let bound = CubaseBoundPluginUse(use: attempt, pluginPath: asset.path, cid: String(repeating: "A", count: 32))
    let first = try await store.recordCubaseUsage(bound, for: id, at: Date(timeIntervalSince1970: 1_790_474_025))
    #expect(first.kind == .loadAttempt)
    let historical = CubasePluginUse(name: attempt.name, vendor: attempt.vendor, version: attempt.version,
        architecture: attempt.architecture, eventID: attempt.eventID, projectID: attempt.projectID,
        reportedMilliseconds: attempt.reportedMilliseconds)
    let replay = try await store.recordCubaseUsage(
        CubaseBoundPluginUse(use: historical, pluginPath: asset.path, cid: bound.cid),
        for: id, at: Date(timeIntervalSince1970: 1_790_474_026))
    #expect(replay == first)
    await model.reloadUsage()
    #expect(model.lastUsed(asset).detail.contains("instantiation attempt"))
    #expect(try await store.dateSummary(for: id, asOf: Date(timeIntervalSince1970: 1_790_474_026)).lastUsed == attempt.reportedDate)
    #expect(try await store.dateEvidence(for: id, asOf: Date(timeIntervalSince1970: 1_790_474_026)).count == 1)
}

@Test @MainActor func groupedAbsoluteHostUsageChoosesLaterInstant() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    for product in ["Cubase", "Logic"] {
        for ext in ["component", "vst3"] {
            _ = try f.file("Plugins/\(product).\(ext)/Contents/Info.plist",
                           "<plist><dict><key>CFBundleIdentifier</key><string>example.\(product)</string></dict></plist>")
        }
    }
    let model = CatalogModel(catalogStore: store)
    model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let assets = try #require(model.report?.assets)
    let base = Date(timeIntervalSince1970: 1_790_345_600)
    let early = base, late = base.addingTimeInterval(1)
    let logicTimes = try #require((1...60).compactMap { delta -> (LogicPluginUse, LogicPluginUse)? in
        let first = LogicPluginUse(name: "Logic", reportedDate: base)
        let second = LogicPluginUse(name: "Logic", reportedDate: base.addingTimeInterval(Double(delta)))
        return first.eventID < second.eventID ? (first, second) : nil
    }.first)
    var records: [AssetDateEvidence] = []
    for product in ["Cubase", "Logic"] {
        let pair = assets.filter { $0.name == product }.sorted { $0.format < $1.format }
        #expect(pair.count == 2)
        for (index, asset) in pair.enumerated() {
            let id = try #require(asset.catalogID)
            if product == "Cubase" {
                let use = CubasePluginUse(name: product, vendor: "Fixture", version: "1", architecture: "arm64",
                    eventID: index == 0 ? "a-cubase" : "z-cubase", projectID: "project",
                    reportedMilliseconds: Int64((index == 0 ? early : late).timeIntervalSince1970 * 1_000))
                records.append(AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.eventID,
                    subjectID: id, kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: Date(), cubaseUsage: use))
            } else {
                let use = index == 0 ? logicTimes.0 : logicTimes.1
                records.append(AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: use.eventID,
                    subjectID: id, kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: Date(), logicUsage: use))
            }
        }
    }
    try await store.appendDateEvidence(records, asOf: Date())
    await model.reloadUsage()
    for product in ["Cubase", "Logic"] {
        let pair = assets.filter { $0.name == product }.sorted { $0.format < $1.format }
        let first = try #require(pair.first), second = try #require(pair.last)
        let secondID = try #require(second.catalogID)
        let expected = try #require(records.first { $0.subjectID == secondID })
        #expect(model.usageRecord(first) == expected)
        #expect(model.usageRecord(second) == expected)
        #expect(try await store.latestHostUsage(for: [secondID], asOf: Date())[Data(secondID.utf8)] == expected)
    }
}

@Test @MainActor func proToolsPartialAttemptSurvivesCompletionWithoutDuplicateEvent() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Plugins/Test.aaxplugin/Contents/Info.plist")
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let asset = try #require(model.report?.assets.first { $0.format == "aaxplugin" })
    let prefix = """
    *** Digidesign Session Trace for:\t/Applications/Pro Tools.app (pid=0x1234, version=24.10.2)
    *** Starting Timestamp:\tSaturday, September 26, 2026 at 3:42:40 PM Pacific Daylight Time (94.000000 s)
    100.000000,00103,0f09: Local wall clock:  9/26/2026 15:42:46
    100.100000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "Test", track "Audio 1"
    """
    let attempt = try #require(ProToolsUsageLog.parse(Data((prefix + "\n").utf8)).first)
    let now = Date()
    let bound = ProToolsBoundPluginUse(use: attempt, pluginPath: asset.path)
    let first = try await store.recordProToolsUsage(bound, for: asset.catalogID!, at: now)
    #expect(first.sourceID == ProToolsPluginUse.attemptedSourceID && first.kind == .loadAttempt)
    let complete = prefix + "\n101.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2\n"
    let restored = try #require(ProToolsUsageLog.parse(Data(complete.utf8)).first)
    #expect(restored.eventSourceID == ProToolsPluginUse.restoreV2SourceID && restored.eventID == attempt.eventID)
    let replay = try await store.recordProToolsUsage(ProToolsBoundPluginUse(use: restored, pluginPath: asset.path),
        for: asset.catalogID!, at: now.addingTimeInterval(60))
    #expect(replay == first)
    #expect(try await store.dateEvidence(for: asset.catalogID!, asOf: now.addingTimeInterval(60)).count == 1)
    let projectionDeadline = Date().addingTimeInterval(2)
    repeat {
        await model.reloadUsage()
        if model.usageRecord(asset, grouped: false) == first { break }
        try await Task.sleep(for: .milliseconds(10))
    } while Date() < projectionDeadline
    #expect(model.usageRecord(asset, grouped: false) == first)
    #expect(model.lastUsed(asset).detail.contains("instantiation attempt"))
}

@Test @MainActor func aaxAndLogicUsageSurviveReplayAndReachCatalog() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Plugins/Test.aaxplugin/Contents/Info.plist")
    _ = try f.file("Plugins/Test.component/Contents/Info.plist")
    let model = CatalogModel(catalogStore: store); model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin]); try await finish(model)
    let assets = try #require(model.report?.assets)
    let aax = try #require(assets.first { $0.format == "aaxplugin" })
    let au = try #require(assets.first { $0.format == "component" })
    let log = """
    *** Digidesign Session Trace for:\t/Applications/Pro Tools.app (pid=0x1234, version=24.10.2)
    *** Starting Timestamp:\tSaturday, September 26, 2026 at 3:42:40 PM Pacific Daylight Time (94.000000 s)
    100.000000,00103,0f09: Local wall clock:  9/26/2026 15:42:46
    100.100000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "Test", track "Audio 1"
    101.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2
    """
    _ = try f.file("Library/Logs/Avid/Pro_Tools_Test.txt", log + "\n")
    let collected = ProToolsUsageCollector.collect(assets: assets, home: f.root)
    let bound = try #require(collected.uses.first)
    #expect(collected.uses.count == 1 && bound.pluginPath == aax.path)
    let now = Date(), later = now.addingTimeInterval(60)
    let first = try await store.recordProToolsUsage(bound, for: aax.catalogID!, at: now)
    #expect(first.sourceID == ProToolsPluginUse.restoreV2SourceID && first.eventDate == nil)
    let replay = try await store.recordProToolsUsage(bound, for: aax.catalogID!, at: later)
    #expect(first == replay)
    let legacy = try JSONDecoder().decode(ProToolsPluginUse.self,
        from: Data(#"{"name":"Test","eventID":"legacy-event","reportedDate":100,"sourceSeconds":42.5}"#.utf8))
    let oldRecord = AssetDateEvidence(sourceID: ProToolsPluginUse.sourceID, evidenceID: legacy.eventID,
        subjectID: aax.catalogID!, kind: .confirmedUse, eventDate: legacy.reportedDate,
        ingestedAt: now, proToolsUsage: legacy)
    try await store.appendDateEvidence([oldRecord], asOf: now)
    let logic = LogicPluginUse(name: "Test", reportedDate: now.addingTimeInterval(-1))
    let firstAU = try await store.recordLogicUsage(logic, for: au.catalogID!, at: now)
    let replayAU = try await store.recordLogicUsage(logic, for: au.catalogID!, at: later)
    #expect(firstAU == replayAU)
    await model.reloadUsage()
    #expect(model.usageRecord(aax, grouped: false)?.proToolsUsage != nil)
    #expect(model.lastUsed(aax).value.contains("2026-09-26"))
    #expect(model.lastUsed(aax).detail.contains("time zone unknown"))
    #expect(model.usageRecord(au, grouped: false)?.logicUsage != nil)
    let reopened = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    let saved = try await reopened.latestHostUsage(for: [aax.catalogID!, au.catalogID!], asOf: later)
    #expect(saved.count == 2)
    #expect(saved[Data(aax.catalogID!.utf8)]?.proToolsUsage?.localTime?.dayKey == "2026-09-26")
    #expect(try await reopened.dateEvidence(for: aax.catalogID!, asOf: later).count == 2)
    #expect(try await reopened.dateSummary(for: aax.catalogID!, asOf: later).lastUsed == nil)
    model.reset()
}

private actor UsageReadGate {
    var calls = 0
    private var pending: [Int: CheckedContinuation<[Data: AssetDateEvidence], any Error>] = [:]
    func read() async throws -> [Data: AssetDateEvidence] {
        calls += 1; let id = calls
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }
    func release(_ id: Int, fail: Bool = false) {
        let continuation = pending.removeValue(forKey: id)
        if fail { continuation?.resume(throwing: CatalogStoreError.invalid) }
        else { continuation?.resume(returning: [:]) }
    }
}
private actor UsageCalls {
    var count = 0
    func collect() -> LiveUsageCollection { count += 1; return LiveUsageCollection(recorded: 0, failures: 0, rejectedDocuments: 0) }
}
private actor UsageInventoryCapture {
    var collected: [[Asset]] = []
    var projected: [[String]] = []
    func collect(_ assets: [Asset]) -> LiveUsageCollection {
        collected.append(assets)
        return LiveUsageCollection(recorded: 0, failures: 0, rejectedDocuments: 0)
    }
    func read(_ ids: [String]) -> [Data: AssetDateEvidence] { projected.append(ids); return [:] }
}
@Test @MainActor func largeMixedCollectionDoesNotConsumeLivePluginBudget() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    for index in 0..<2050 { _ = try f.file("Samples/Sample-\(index).wav") }
    for ext in ["vst3", "component", "aaxplugin"] { _ = try f.file("Plugins/Test.\(ext)/Contents/Info.plist") }
    let capture = UsageInventoryCapture()
    let model = CatalogModel(catalogStore: store,
        usageCollector: { assets, _ in await capture.collect(assets) },
        usageLoader: { _, ids, _ in await capture.read(ids) })
    model.setStandardPlugins(false)
    model.addRoots([f.root.appendingPathComponent("Samples")], kind: .samples)
    model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(); try await finish(model)
    for _ in 0..<200 where await capture.collected.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
    let inventory = try #require(model.report?.assets)
    #expect(inventory.count == 2053)
    let vst3 = try #require(inventory.first { $0.format == "vst3" })
    let collected = await capture.collected, projected = await capture.projected
    let pluginIDs = Set(inventory.filter { $0.kind == .plugin }.compactMap(\.catalogID))
    #expect(!collected.isEmpty && collected.allSatisfy { Set($0.compactMap(\.catalogID)) == pluginIDs && $0.count == 3 })
    #expect(!projected.isEmpty && projected.allSatisfy { Set($0) == pluginIDs })
    #expect(LiveUsageCollector.sourceSignature(assets: inventory) == LiveUsageCollector.sourceSignature(assets: [vst3]))
    let samplesOnly = inventory.filter { $0.kind == .sample }
    let result = await LiveUsageCollector.collect(assets: samplesOnly, store: store)
    #expect(result.recorded == 0 && result.failures == 0)
    model.reset()
}
@Test @MainActor func usageLateReadsAndObsoleteScanCompletionCannotRestartCollection() async throws {
    let f = try CatalogFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Private/catalog.sqlite"))
    _ = try f.file("Plugins/Test.vst3/Contents/Info.plist")
    let gate = UsageReadGate(), calls = UsageCalls()
    let model = CatalogModel(catalogStore: store, usageCollector: { _, _ in await calls.collect() }, usageLoader: { _, _, _ in try await gate.read() })
    model.setStandardPlugins(false); model.addRoots([f.root.appendingPathComponent("Plugins")], kind: .plugins)
    model.scan(scannedKinds: [.plugin])
    for _ in 0..<200 where await gate.calls < 1 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await gate.calls == 1)
    let newer = Task { await model.reloadUsage() }
    for _ in 0..<100 where await gate.calls < 2 { try await Task.sleep(for: .milliseconds(5)) }
    await gate.release(2); await newer.value
    #expect(!model.usageUnavailable)
    // Change scope while the original scan completion is still awaiting its projection.
    model.removeRoot(try #require(model.roots[.plugins]?.first), kind: .plugins)
    await gate.release(1, fail: true)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!model.usageUnavailable && !model.isCollectingUsage && model.configurationChanged)
    #expect(await calls.count == 0)
    let oldRead = Task { await model.reloadUsage() }
    for _ in 0..<100 where await gate.calls < 3 { try await Task.sleep(for: .milliseconds(5)) }
    model.reset(); await gate.release(3, fail: true); await oldRead.value
    #expect(!model.usageUnavailable && model.report == nil)
}
