import Foundation
import Testing
@testable import SimplifyCatalog
@testable import SimplifyCore

@Test @MainActor func sampleProjectionPreservesLexicalPathsWithoutRequiringFiles() {
    let paths = ["/unmounted/Samples/A #1/100%/Café 🎹.wav", "/unmounted/Samples/A #1/100%/Second.wav"]
    let assets = paths.map { Asset(kind: .sample, path: $0, name: $0, format: "wav",
        bundleIdentifier: nil, logicalBytes: 1, classification: "synthetic") }
    let result = CatalogOutline.build(assets: assets, category: .sample,
        sampleRoots: [URL(fileURLWithPath: "/unmounted/Samples", isDirectory: true)])
    #expect(Set(result.nodes.filter { $0.kind == .sample }.compactMap(\.location)) == Set(paths))
    #expect(result.nodes.filter { $0.kind == .folder }.map(\.location) == ["/unmounted/Samples/A #1", "/unmounted/Samples/A #1/100%"])
}

@Test @MainActor func sampleProjectionCatalogFinalPublicationAndTabSwitchStayAsynchronous() async throws {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/SimplifyCatalogTests/projection-" + UUID().uuidString)
    let samples = root.appendingPathComponent("Samples")
    try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sampleCount = ProcessInfo.processInfo.environment["PRISM_SCAN_RESPONSIVENESS_RUNTIME"] == "1" ? 99_000 : 5_100
    for index in 0..<sampleCount { try Data().write(to: samples.appendingPathComponent("Hit-\(index).wav")) }
    let catalogURL = root.appendingPathComponent("catalog.sqlite")
    let model = CatalogModel(catalogStore: CatalogStore(url: catalogURL)); model.setStandardPlugins(false)
    model.addRoots([samples], kind: .samples); model.category = .sample
    var preparedAsynchronously = false
    // Exercise the same accessor a native refresh invokes, including final report
    // replacement, which invalidates any earlier streamed tree.
    model.onChange = { [weak model] in
        guard let model else { return }
        _ = model.outline
        preparedAsynchronously = preparedAsynchronously || model.isPreparingOutline
    }
    model.scan()
    let deadline = Date().addingTimeInterval(90)
    var previous = ProcessInfo.processInfo.systemUptime, longest = 0.0
    while (model.isScanning || model.isPreparingOutline) && Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
        let now = ProcessInfo.processInfo.systemUptime
        longest = max(longest, now - previous); previous = now
    }
    print("Catalog model scan: \(sampleCount) samples; maximum main-actor heartbeat gap \(longest)s")
    #expect(longest < 0.250)
    #expect(!model.isScanning && !model.isPreparingOutline)
    #expect(preparedAsynchronously)
    #expect(model.outline.nodes.filter { $0.kind == .sample }.count == sampleCount)
    if ProcessInfo.processInfo.environment["PRISM_SCAN_RESPONSIVENESS_RUNTIME"] == "1" {
        print("Catalog inclusion evidence bytes: \(try JSONEncoder().encode(model.report?.sampleInclusions ?? []).count)")
        try #require(model.savedCatalogDate != nil,
                     "Durable scan failed: \(model.catalogNotice ?? "no save timestamp")")
        let restored = CatalogModel(catalogStore: CatalogStore(url: catalogURL))
        restored.setStandardPlugins(false); restored.addRoots([samples], kind: .samples); restored.category = .sample
        restored.onChange = { _ = restored.outline }
        var restoreFinished = false
        let restoreTask = Task { await restored.restoreSavedCatalog(); restoreFinished = true }
        var priorTick = ProcessInfo.processInfo.systemUptime, restoreGap = 0.0
        let restoreDeadline = Date().addingTimeInterval(240)
        while restored.report == nil && !restoreFinished && Date() < restoreDeadline {
            try await Task.sleep(for: .milliseconds(20))
            let tick = ProcessInfo.processInfo.systemUptime
            restoreGap = max(restoreGap, tick - priorTick); priorTick = tick
        }
        await restoreTask.value
        while restored.isPreparingOutline && Date() < restoreDeadline { try await Task.sleep(for: .milliseconds(20)) }
        print("Catalog restore: \(sampleCount) samples; maximum main-actor heartbeat gap \(restoreGap)s")
        #expect(restored.usingSavedCatalog && restored.report?.assets.filter { $0.kind == .sample }.count == sampleCount)
        #expect(restoreGap < 0.250)
    }
    model.category = .plugin; model.sort = .size
    model.category = .sample
    _ = model.outline
    #expect(model.isPreparingOutline)
    model.reset()
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.report == nil && !model.isPreparingOutline && model.outline.nodes.isEmpty)
}

// Opt-in to avoid competing test processes affecting the scheduling measurement.
@Test @MainActor func sampleProjectionRuntimeKeepsMainActorResponsive() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_SCAN_RESPONSIVENESS_RUNTIME"] == "1" else { return }
    let assets = (0..<100_000).map { index in
        Asset(kind: .sample, path: "/offline/Samples/Group-\(index / 100)/Pack/One shots/Hit-\(index).wav",
            name: "Hit-\(index)", format: "wav", bundleIdentifier: nil, logicalBytes: 1, classification: "synthetic")
    }
    var result: CatalogOutline?
    let start = ProcessInfo.processInfo.systemUptime
    let task = Task { @MainActor in
        result = await CatalogOutline.prepare(assets: assets, category: .sample,
            sampleRoots: [URL(fileURLWithPath: "/offline/Samples", isDirectory: true)],
            sort: .name, reversed: false, recency: [:], additions: [:], usageDays: [:], tags: [:])
    }
    var previous = start, longest = 0.0, ticks = 0
    while result == nil {
        try await Task.sleep(for: .milliseconds(50))
        let now = ProcessInfo.processInfo.systemUptime
        longest = max(longest, now - previous); previous = now; ticks += 1
    }
    await task.value
    #expect(result?.nodes.filter { $0.kind == .sample }.count == 100_000)
    #expect(longest < 0.250)
    #expect(ticks > 0)
    print("100000-sample projection: \(previous - start)s; main-actor maximum heartbeat gap \(longest)s across \(ticks) ticks")
}
