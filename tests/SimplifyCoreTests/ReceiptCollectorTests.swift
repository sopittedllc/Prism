import Foundation
import Testing
@testable import SimplifyCore

private final class ReceiptCommands: @unchecked Sendable {
    let fixture: ReceiptFixture
    let entries: [[String: Any]]
    let fileList: Data
    let reverseBatch: Bool
    private let lock = NSLock()
    private var calls: [[String]] = []
    init(_ fixture: ReceiptFixture, entries: [[String: Any]]? = nil, fileList: Data? = nil, reverseBatch: Bool = false) {
        self.fixture = fixture; self.entries = entries ?? [fixture.receipt]
        self.fileList = fileList ?? fixture.files; self.reverseBatch = reverseBatch
    }
    func run(_ args: [String], _ limit: Int, _ seconds: Double) throws -> Data {
        lock.lock(); calls.append(args); lock.unlock()
        if args == ["--pkgs-plist"] {
            return try PropertyListSerialization.data(fromPropertyList: entries.map { $0["pkgid"]! }, format: .xml, options: 0)
        }
        if args[0] == "--files" { return fileList }
        var ids = stride(from: 1, to: args.count, by: 2).map { args[$0] }
        if reverseBatch { ids.reverse() }
        var data = Data()
        for id in ids {
            guard let entry = entries.first(where: { ($0["pkgid"] as? String) == id }) else { throw PackageReceiptError.invalidReceipt }
            data.append(try fixture.data(entry))
        }
        return data
    }
    func fileQueries() -> Int { lock.lock(); defer { lock.unlock() }; return calls.filter { $0[0] == "--files" }.count }
}

@Test func collectorDiscoversExactRecordsAndReplaysWithoutGuessedPackageIDs() async throws {
    let f = try ReceiptFixture(), db = f.root.appendingPathComponent("Collector/catalog.sqlite")
    let second = f.root.appendingPathComponent("Other.component")
    try FileManager.default.copyItem(at: f.bundle, to: second)
    let store = CatalogStore(url: db)
    let saved = try await store.ingest(receiptReport([receiptAsset(f.bundle), receiptAsset(second)]), scope: receiptScope(f.root))
    var wrongVersion = f.receipt; wrongVersion["pkgid"] = "different.version"; wrongVersion["pkg-version"] = "no-match"
    var wrongRoot = f.receipt; wrongRoot["pkgid"] = "different.root"; wrongRoot["install-location"] = "/unrelated"
    let files = f.files + Data("Other.component/Contents/Info.plist\nOther.component/Contents/MacOS/Unit\n".utf8)
    let commands = ReceiptCommands(f, entries: [wrongVersion, f.receipt, wrongRoot], fileList: files)
    for _ in 0..<2 {
        let result = await PackageReceiptCollector.collect(assets: saved.report.assets, store: store, limits: .init(), acquire: commands.run)
        #expect(result.status == .complete && result.recorded == 2 && result.attempted == 2)
        #expect(result.payloadQueries == 1 && result.commands == 9 && result.failures == 0)
    }
    #expect(commands.fileQueries() == 6) // One index read plus two fresh observations per pass.
    for asset in saved.report.assets {
        let id = try #require(asset.catalogID)
        #expect(try await store.dateEvidence(for: id, asOf: Date()).count == 1)
        let summary = try await store.dateSummary(for: id, asOf: Date())
        #expect(summary.lastUsed == nil && summary.dateAdded == nil)
    }
}

@Test func collectorMarksErrorsBudgetsAndChangedOrderIncompleteWithoutWriting() async throws {
    let f = try ReceiptFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Collector/catalog.sqlite"))
    let saved = try await store.ingest(receiptReport([receiptAsset(f.bundle)]), scope: receiptScope(f.root))
    let node = try #require(saved.report.assets.first?.catalogID)
    var other = f.receipt; other["pkgid"] = "other"
    let reversed = ReceiptCommands(f, entries: [f.receipt, other], reverseBatch: true)
    let bad = await PackageReceiptCollector.collect(assets: saved.report.assets, store: store, limits: .init(), acquire: reversed.run)
    #expect(bad.status == .incomplete && bad.attempted == 0 && reversed.fileQueries() == 0)
    let commands = ReceiptCommands(f)
    for variant in 0..<5 {
        var limit = PackageReceiptCollector.Limits()
        switch variant {
        case 0: limit.bytes = 1
        case 1: limit.payloads = 0
        case 2: limit.observations = 0
        case 3: limit.seconds = 0
        default: limit.assets = 0
        }
        let result = await PackageReceiptCollector.collect(assets: saved.report.assets, store: store, limits: limit, acquire: commands.run)
        #expect(result.status == .incomplete && result.recorded == 0)
    }
    let failed = await PackageReceiptCollector.collect(assets: saved.report.assets, store: store, limits: .init()) { _, _, _ in
        throw BoundedCommandError.diagnosticOutput
    }
    #expect(failed.status == .incomplete && failed.recorded == 0)
    #expect(try await store.dateEvidence(for: node, asOf: Date()).isEmpty)
    var stale = saved.report.assets[0]; stale.catalogStale = true
    let ignored = await PackageReceiptCollector.collect(assets: [stale], store: store, limits: .init()) { _, _, _ in
        Issue.record("Retained stale installation reached receipt lookup"); return Data()
    }
    #expect(ignored.commands == 0)
}

@Test func receiptBatchFramingRejectsMissingExtraTrailingAndMalformedValues() throws {
    let f = try ReceiptFixture(), data = try f.data(f.receipt)
    #expect(try PackageReceiptCollector.metadataDocuments(data + data, count: 2).count == 2)
    for bad in [data + data, Data("junk".utf8) + data, data + Data("junk</plist>".utf8),
                Data(data.dropLast(30)), Data([0xff]), Data(repeating: 0, count: 262_145)] {
        #expect(throws: (any Error).self) { try PackageReceiptCollector.metadataDocuments(bad, count: 1) }
    }
    for ids: [Any] in [["same", "same"], ["-argument"], ["bad\0id"], [true], [String(repeating: "x", count: 1025)]] {
        let bytes = try PropertyListSerialization.data(fromPropertyList: ids, format: .binary, options: 0)
        #expect(throws: (any Error).self) { try PackageReceiptCollector.packageIDs(bytes) }
    }
    let ids = try PropertyListSerialization.data(fromPropertyList: ["é", "e\u{301}"], format: .xml, options: 0)
    #expect(try PackageReceiptCollector.packageIDs(ids).count == 2)
    #expect(throws: (any Error).self) { try PackageReceiptCollector.packageIDs(ids, maximum: 1) }
}

@Test func receiptCommandsRejectDiagnosticsAndCancelWithoutWaitingForTimeout() async throws {
    for script in ["printf warning >&2", "while :; do printf stdout; printf stderr >&2; done"] {
        #expect(throws: BoundedCommandError.diagnosticOutput) {
            try BoundedCommand.read("/bin/sh", arguments: ["-c", script], limit: 1_048_576, rejectDiagnostics: true)
        }
    }
    let start = ProcessInfo.processInfo.systemUptime
    let task = Task.detached {
        try BoundedCommand.read("/bin/sleep", arguments: ["10"], limit: 128, rejectDiagnostics: true)
    }
    try await Task.sleep(for: .milliseconds(50)); task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ProcessInfo.processInfo.systemUptime - start < 2)
}

private func takeSignal(_ semaphore: DispatchSemaphore) -> Bool {
    semaphore.wait(timeout: .now()) == .success // Nonblocking probe, never waits on a task thread.
}
private func awaitSignal(_ semaphore: DispatchSemaphore) async throws {
    for _ in 0..<400 {
        if takeSignal(semaphore) { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for fixture scheduling")
    throw CancellationError()
}

@Test func cancelledReceiptWaitingForCatalogActorCannotBeginWrite() async throws {
    let f = try ReceiptFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Collector/catalog.sqlite"))
    let saved = try await store.ingest(receiptReport([receiptAsset(f.bundle)]), scope: receiptScope(f.root))
    let node = try #require(saved.report.assets.first?.catalogID), original = try f.observe()
    var updated = f.receipt; updated["install-time"] = 600
    let next = try f.observe(receipt: updated)
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let first = Task.detached {
        try await store.recordPackageReceipt(original, for: node, at: f.now) {
            entered.signal(); _ = release.wait(timeout: .now() + 5)
        }
    }
    try await awaitSignal(entered)
    let queued = DispatchSemaphore(value: 0)
    let second = Task.detached {
        queued.signal()
        return try await store.recordPackageReceipt(next, for: node, at: f.now)
    }
    try await awaitSignal(queued)
    second.cancel(); release.signal()
    _ = try await first.value
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(try await store.dateEvidence(for: node, asOf: f.now).count == 1)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PRISM_AUTOMATIC_RECEIPT_RUNTIME"] == "1"))
func nativeAutomaticReceiptRuntime() async throws {
    let f = try ReceiptFixture(), store = CatalogStore(url: f.root.appendingPathComponent("Native/catalog.sqlite"))
    let root = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components")
    let names = ["FabFilter Pro-Q 4.component", "Kontakt 8.component", "Diva.component"]
    let observations = try zip(names, ["com.fabfilter.Pro-Q.AU.4", "com.native-instruments.Kontakt8.AU", "com.u-he.Diva.au.pkg"]).map {
        try PackageReceiptReader.observe(packageID: $0.1, bundle: root.appendingPathComponent($0.0))
    }
    let assets = observations.map { receiptAsset(URL(fileURLWithPath: $0.report.bundlePath), identifier: $0.report.bundleIdentifier) }
    let saved = try await store.ingest(receiptReport(assets), scope: receiptScope(root))
    for _ in 0..<2 {
        let start = ProcessInfo.processInfo.systemUptime
        let result = await PackageReceiptCollector.collect(assets: saved.report.assets, store: store)
        print("Receipt collection: \(result.status), \(result.commands) commands, \(result.payloadQueries) payloads, \(result.recorded) records, \(result.failures) failures, \(ProcessInfo.processInfo.systemUptime - start)s")
        #expect(result.status == .complete && result.recorded >= 2)
    }
    for asset in saved.report.assets {
        let node = try #require(asset.catalogID)
        let history = try await store.dateEvidence(for: node, asOf: Date())
        #expect(Set(history.map(\.evidenceID)).count == history.count)
        if asset.path.hasSuffix("Diva.component") {
            #expect(!history.contains { $0.packageReceipt?.packageID == "com.u-he.Diva.au.pkg" })
        } else { #expect(!history.isEmpty) }
        #expect(try await store.dateSummary(for: node, asOf: Date()).dateAdded == nil)
    }
    for observation in observations { try observation.revalidate() }
}
