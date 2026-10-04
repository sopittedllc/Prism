import Foundation
import Testing
@testable import SimplifyCore

private let liveCID = "12345678-1234-5678-ABCD-123456789ABC"
private struct LiveManualRuntimeSummary: Decodable {
    let outcome: String
    let host: String
    let logSequence: [String]
    let fileSHA256: [String: String]
    let candidateSavedALS_SHA256: [String: String]
}
private func liveLine(_ second: Int, _ body: String) -> String {
    String(format: "2026-09-26T12:00:%02d.000000: info: ", second) + body + "\n"
}
private func liveDocument(_ second: Int = 1) -> String {
    liveLine(second, "Loading document \"/fixtures/Test.als\"") +
    liveLine(second + 1, "VST3: Going to restore: Test Synth") +
    liveLine(second + 2, "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
    liveLine(second + 3, "VST3: Restored: Test Synth") +
    liveLine(second + 4, "Loaded document was created by Ableton Live 12.4.6") +
    liveLine(second + 5, "Default App: Begin ExchangeDocument") +
    liveLine(second + 6, "Default App: End ExchangeDocument")
}
private func liveManualCreate(_ second: Int = 1, name: String = "Test Synth", chatter: String = "") -> String {
    liveLine(second, "VST3: Going to create: \(name)") +
    liveLine(second + 1, "VST3: plugin processor successfully loaded: Example '\(name)' v1.0 (cid: {" + liveCID + "})") +
    chatter + liveLine(second + 2, "VST3: Created: \(name)")
}
private let liveInit = liveLine(0, "Init: Version: 'Live 12.4.6 Build: test' 1")

@Test func sourceLocalTimePreservesClockWithoutInventingAnInstant() throws {
    let value = try SourceLocalTime("2024-02-29T23:59:59.123456")
    #expect(value.dayKey == "2024-02-29")
    #expect(value.canonical == "2024-02-29T23:59:59.123456")
    #expect(try JSONDecoder().decode(SourceLocalTime.self, from: JSONEncoder().encode(value)) == value)
    for invalid in ["2023-02-29T12:00:00.000000", "2024-02-30T12:00:00.000000", "2024-01-01T24:00:00.000000",
                    "2024-01-01T12:00:60.000000", "2024-01-01T12:00:00.000000Z", "2024-01-01T12:00:00.00000x"] {
        #expect(throws: AssetDateEvidenceError.self) { try SourceLocalTime(invalid) }
    }
}

@Test func liveRestoresRequireCompletedDocumentAndExactSuccessfulSequence() throws {
    let input = liveInit + liveDocument()
    let parsed = try LiveUsageLog.parse(Data(input.utf8))
    #expect(parsed.events.count == 1)
    let event = try #require(parsed.events.first)
    #expect(event.classID == liveCID && event.localTime.canonical == "2026-09-26T12:00:04.000000")
    let id = try event.eventID(subjectID: "node")
    let record = AssetDateEvidence(sourceID: HostUsageProvenance.sourceID, evidenceID: id, subjectID: "node",
        kind: .confirmedUse, eventDate: nil, ingestedAt: Date(), hostUsage: event)
    #expect(try AssetDateResolver.summarize([record], for: "node", asOf: Date()).lastUsed == nil)
    let restored = try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(record))
    #expect(restored == record)
    let invalidInstant = AssetDateEvidence(sourceID: record.sourceID, evidenceID: id, subjectID: "node",
        kind: .confirmedUse, eventDate: Date(timeIntervalSince1970: 1), ingestedAt: Date(), hostUsage: event)
    #expect(throws: AssetDateEvidenceError.self) { try AssetDateResolver.summarize([invalidInstant], for: "node", asOf: Date()) }
    for invalid in [input.replacingOccurrences(of: "VST3: Restored: Test Synth", with: "VST3: Restore 1 failed: Test Synth"),
                    input.replacingOccurrences(of: "VST3: Restored: Test Synth", with: "VST3: Restored: Other Synth"),
                    input.replacingOccurrences(of: "Default App: End ExchangeDocument", with: "FatalError: crash"),
                    input.replacingOccurrences(of: "Init: Version: 'Live", with: "Init: Version: 'PluginScanner"),
                    input.replacingOccurrences(of: "Live 12.4.6 Build", with: "Live 13.0.0 Build"),
                    liveDocument(), input.replacingOccurrences(of: "12:00:04", with: "11:59:04"),
                    input.replacingOccurrences(of: "12:00:04", with: "12:10:04")] {
        #expect(try LiveUsageLog.parse(Data(invalid.utf8)).events.isEmpty)
    }
}

@Test func liveManualCreateRequiresDisjointSuccessfulInstanceAndCreatedCommit() throws {
    let input = liveInit + liveManualCreate()
    let parsed = try LiveUsageLog.parse(Data(input.utf8))
    let event = try #require(parsed.events.first)
    #expect(parsed.events.count == 1)
    #expect(event.qualification == HostUsageProvenance.completedManualCreate)
    #expect(event.eventSourceID == HostUsageProvenance.manualCreateSourceID)
    #expect(event.localTime.canonical == "2026-09-26T12:00:03.000000")
    #expect(event.recordHash == HostUsageProvenance.digest(Data(liveLine(3, "VST3: Created: Test Synth").dropLast().utf8)))
    let manualID = try event.eventID(subjectID: "node")
    let manualRecord = AssetDateEvidence(sourceID: event.eventSourceID, evidenceID: manualID, subjectID: "node",
        kind: .confirmedUse, eventDate: nil, ingestedAt: Date(), hostUsage: event)
    #expect(try AssetDateResolver.summarize([manualRecord], for: "node", asOf: Date()).lastUsed == nil)
    #expect(try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(manualRecord)) == manualRecord)

    let restore = try #require(LiveUsageLog.parse(Data((liveInit + liveDocument()).utf8)).events.first)
    #expect(restore.eventSourceID == HostUsageProvenance.sourceID)
    let restoreID = try restore.eventID(subjectID: "node")
    #expect(restoreID == HostUsageProvenance.digest(try JSONEncoder().encode([
        HostUsageProvenance.sourceID, restore.runHash, String(restore.recordOffset), restore.recordHash, restore.classID, "node"
    ])))

    let startupOnly = liveLine(1, "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
        liveLine(2, "VST3: Created: Test Synth")
    let failure = liveInit + liveManualCreate(chatter: "2026-09-26T12:00:02.500000: error: unsupported failure\n")
    let warning = liveInit + liveManualCreate(chatter: "2026-09-26T12:00:02.500000: warning: unqualified warning\n")
    let mismatch = liveInit + liveManualCreate().replacingOccurrences(of: "Created: Test Synth", with: "Created: Other")
    let overlap = liveInit + liveLine(1, "VST3: Going to create: First") + liveLine(2, "VST3: Going to create: Test Synth") +
        liveLine(3, "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
        liveLine(4, "VST3: Created: Test Synth")
    let rollback = liveInit + liveLine(5, "VST3: Going to create: Test Synth") +
        liveLine(4, "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})")
    let tooSlow = liveInit + liveManualCreate(1).replacingOccurrences(of: "12:00:02", with: "12:00:32")
    let runBoundary = liveInit + liveLine(1, "VST3: Going to create: Test Synth") + liveLine(2, "Init: Version: 'Live 12.4.6 Build: next run' 2") +
        liveLine(3, "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
        liveLine(4, "VST3: Created: Test Synth")
    let documentBoundary = liveInit + liveLine(1, "VST3: Going to create: Test Synth") +
        liveLine(2, "Loading document \"/fixtures/Test.als\"") +
        liveLine(3, "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
        liveLine(4, "VST3: Created: Test Synth")
    let partial = String((liveInit + liveManualCreate()).dropLast())
    for invalid in [startupOnly, failure, warning, mismatch, overlap, rollback, tooSlow, runBoundary, documentBoundary, partial] {
        #expect(try LiveUsageLog.parse(Data(invalid.utf8)).events.isEmpty)
    }
    let knownBenign = liveInit + liveManualCreate(chatter:
        "2026-09-26T12:00:02.250000: warning: VST3: setProcessing returned error: not implemented\n" +
        "2026-09-26T12:00:02.500000: error: VST3: couldn't connect to processor from edit controller\n")
    #expect(try LiveUsageLog.parse(Data(knownBenign.utf8)).events.count == 1)
}

@Test func liveManualCreateCanFollowAnEmptyLoadedDocumentButNotPendingRestores() throws {
    func line(_ clock: String, _ body: String) -> String { "\(clock): info: \(body)\n" }
    let loadedEmptyDocument = line("2026-09-26T12:00:01.000000", "Loading document \"/fixtures/Empty.als\"") +
        line("2026-09-26T12:00:02.000000", "Loaded document was created by Ableton Live 12.4.6")
    let manualAfterLongOpen = line("2026-09-26T12:03:20.000000", "VST3: Going to create: Test Synth") +
        line("2026-09-26T12:03:21.000000", "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
        line("2026-09-26T12:03:22.000000", "VST3: Created: Test Synth")
    let afterLoaded = try LiveUsageLog.parse(Data((liveInit + loadedEmptyDocument + manualAfterLongOpen).utf8))
    #expect(afterLoaded.events.count == 1)
    #expect(afterLoaded.events.first?.qualification == HostUsageProvenance.completedManualCreate)
    #expect(afterLoaded.events.first?.localTime.canonical == "2026-09-26T12:03:22.000000")

    let restoredDocumentPendingCommit = line("2026-09-26T12:00:01.000000", "Loading document \"/fixtures/HasPlugin.als\"") +
        line("2026-09-26T12:00:02.000000", "VST3: Going to restore: Test Synth") +
        line("2026-09-26T12:00:03.000000", "VST3: plugin processor successfully loaded: Example 'Test Synth' v1.0 (cid: {" + liveCID + "})") +
        line("2026-09-26T12:00:04.000000", "VST3: Restored: Test Synth") +
        line("2026-09-26T12:00:05.000000", "Loaded document was created by Ableton Live 12.4.6")
    #expect(try LiveUsageLog.parse(Data((liveInit + restoredDocumentPendingCommit + manualAfterLongOpen).utf8)).events.isEmpty)

    let pendingRestore = line("2026-09-26T12:00:01.000000", "Loading document \"/fixtures/Pending.als\"") +
        line("2026-09-26T12:00:02.000000", "VST3: Going to restore: Test Synth")
    #expect(try LiveUsageLog.parse(Data((liveInit + pendingRestore + manualAfterLongOpen).utf8)).events.isEmpty)

    // Rejecting one ambiguous exchange cannot poison a later, properly committed restore.
    let laterRestore = liveDocument(20)
    let recovered = try LiveUsageLog.parse(Data((liveInit + restoredDocumentPendingCommit + manualAfterLongOpen + laterRestore).utf8))
    #expect(recovered.events.count == 1)
    #expect(recovered.events.first?.qualification == HostUsageProvenance.completedDocumentRestore)
    #expect(recovered.events.first?.classID == liveCID)
}

@Test func liveAppendReplayAndOutsideFenceDoNotInventUse() throws {
    let input = liveInit + liveDocument()
    let before = try LiveUsageLog.parse(Data(input.utf8)).events
    let outside = liveLine(10, "VST3: plugin processor successfully loaded: Example 'Browser Helper' v1.0 (cid: {" + liveCID + "})") + liveLine(11, "VST3: Created: Browser Helper")
    #expect(try LiveUsageLog.parse(Data((input + outside).utf8)).events == before)
    #expect(try LiveUsageLog.parse(Data((input + liveDocument(20)).utf8)).events.count == 2)
    #expect(try LiveUsageLog.parse(Data((input + liveDocument(20).dropLast(4)).utf8)).events == before)
    #expect(try LiveUsageLog.parse(Data((liveInit + liveLine(0, "Default App: Begin ExchangeDocument") + liveLine(0, "Default App: End ExchangeDocument") + liveDocument()).utf8)).events.count == 1)
    let interleaved = input.replacingOccurrences(of: "VST3: Restored: Test Synth", with: "VST3: Going to restore: Other")
    #expect(try LiveUsageLog.parse(Data(interleaved.utf8)).events.isEmpty)
    #expect(throws: AssetDateEvidenceError.self) { try LiveUsageLog.parse(Data((input + String(repeating: "x", count: 32_769) + "\n").utf8)) }
}

@Test func liveRejectsUnhandledFailureOversizedTailAndExpiredDeadline() throws {
    let input = liveInit + liveDocument()
    let failed = input.replacingOccurrences(of: liveLine(5, "Loaded document was created by Ableton Live 12.4.6"),
        with: "2026-09-26T12:00:04.500000: error: Device restore failed\n" + liveLine(5, "Loaded document was created by Ableton Live 12.4.6"))
    #expect(try LiveUsageLog.parse(Data(failed.utf8)).events.isEmpty)
    #expect(throws: AssetDateEvidenceError.self) { try LiveUsageLog.parse(Data((input + String(repeating: "x", count: 32_769)).utf8)) }
    #expect(throws: CatalogStoreError.self) { try LiveUsageLog.parse(Data(input.utf8), deadline: 0) }
}

@Test func nativeLiveCompletedRestoreRuntime() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_LIVE_USAGE_RUNTIME"] == "1" else { return }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let data = try Data(contentsOf: home.appendingPathComponent("Library/Preferences/Ableton/Live 12.4.6/Log.txt"))
    let parsed = try LiveUsageLog.parse(data)
    let controlled = parsed.events.filter { $0.localTime.canonical.hasPrefix("2026-09-26T18:03:") }
    #expect(controlled.count == 3)
    #expect(Set(controlled.map(\.classID)) == Set(["ED57BD72-5C60-467E-A64D-D2F400758B6F", "5653544E-694B-386B-6F6E-74616B742038", "D39D5B69-D6AF-42FA-1234-567844695661"]))
    #expect(parsed.events.filter { $0.localTime.canonical.hasPrefix("2026-09-26T18:07:") }.isEmpty)
    let root = home.appendingPathComponent(".cache/PrismLiveRuntime/" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = CatalogStore(url: root.appendingPathComponent("catalog.sqlite"))
    var request = ScanRequest(); request.plugins = [URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3")]
    let result = Scanner().scan(request, scannedKinds: [.plugin])
    let selected = result.assets.filter { ["FabFilter Pro-Q 4", "Kontakt 8", "Diva"].contains($0.name) }
    #expect(selected.count == 3)
    let snapshot = try await store.ingest(result.replacingAssets(selected), scope: CatalogScope(request), scannedKinds: [.plugin])
    let cache = try LivePluginCache.read(home.appendingPathComponent("Library/Application Support/Ableton/Live Database/Live-plugins-1.db"))
    #expect(try LivePluginCache.bindings(cache, assets: snapshot.report.assets).count == 3)
    let collection = await LiveUsageCollector.collect(assets: snapshot.report.assets, store: store)
    #expect(collection.recorded >= 3)
    let ids = snapshot.report.assets.compactMap(\.catalogID)
    let history = try await store.latestHostUsage(for: ids, asOf: Date())
    #expect(history.count == 3)
    let again = await LiveUsageCollector.collect(assets: snapshot.report.assets, store: store)
    #expect(again.recorded == collection.recorded)
    let replay = try await store.latestHostUsage(for: ids, asOf: Date())
    #expect(history == replay)
    print("Live native: \(controlled.count) controlled restores, \(collection.recorded) bound events, \(history.count) products; \(collection.failures) coverage failures; \(parsed.rejectedDocuments) incomplete documents rejected.")
}

@Test func nativeLiveManualCreateRuntime() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_LIVE_USAGE_RUNTIME"] == "1" else { return }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/date-evidence/manual-live")
    let afterCreateURL = root.appendingPathComponent("after-create.log")
    let summaryURL = root.appendingPathComponent("summary.json")
    let startupURL = home.appendingPathComponent("Library/Preferences/Ableton/Live 12.4.6/Log.txt")
    #expect(FileManager.default.fileExists(atPath: afterCreateURL.path))
    #expect(FileManager.default.fileExists(atPath: summaryURL.path))
    #expect(FileManager.default.fileExists(atPath: startupURL.path))
    let capturedLog = try BoundedFile.read(afterCreateURL, limit: LiveUsageLog.maximumBytes)
    let liveLog = try BoundedFile.read(startupURL, limit: LiveUsageLog.maximumBytes)
    let summary = try JSONDecoder().decode(LiveManualRuntimeSummary.self, from: BoundedFile.read(summaryURL, limit: 64 * 1024))
    #expect(summary.host == "Live 12.4.6")
    #expect(summary.outcome.contains("manual VST3 create") && summary.outcome.contains("track deleted before save"))
    #expect(summary.fileSHA256["after-create.log"] == HostUsageProvenance.digest(capturedLog))
    #expect(summary.logSequence.contains { $0.contains("Going to create: Pro-Q 4") })
    #expect(summary.logSequence.contains { $0.contains("Created: Pro-Q 4") })
    #expect(summary.candidateSavedALS_SHA256.count == 2)
    let captured = try LiveUsageLog.parse(capturedLog)
    let created = try #require(captured.events.first {
        $0.qualification == HostUsageProvenance.completedManualCreate &&
        $0.classID == "ED57BD72-5C60-467E-A64D-D2F400758B6F" &&
        $0.localTime.canonical == "2026-10-03T13:17:19.036237"
    })
    #expect(captured.events.filter { $0.localTime.canonical == created.localTime.canonical && $0.classID == created.classID }.count == 1)
    #expect(created.localTime.canonical == "2026-10-03T13:17:19.036237")
    #expect(created.pluginVersion == "4.1.2.0")
    #expect(created.eventSourceID == HostUsageProvenance.manualCreateSourceID)
    #expect(try LiveUsageLog.parse(liveLog).events.contains(created))

    // Qualify the native candidate through the ordinary current-installation binding and
    // CatalogStore path using an isolated catalog; no user catalog is opened or changed.
    let nativePlugins = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3")
    var request = ScanRequest(); request.plugins = [nativePlugins]
    let scan = Scanner().scan(request, scannedKinds: [.plugin])
    let proQAssets = scan.assets.filter { $0.name == "FabFilter Pro-Q 4" && $0.format == "vst3" }
    #expect(proQAssets.count == 1)
    let isolatedRoot = home.appendingPathComponent(".cache/PrismLiveRuntime/LiveManualNative-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: isolatedRoot) }
    let store = CatalogStore(url: isolatedRoot.appendingPathComponent("catalog.sqlite"))
    let snapshot = try await store.ingest(scan.replacingAssets(proQAssets), scope: CatalogScope(request), scannedKinds: [.plugin])
    let asset = try #require(snapshot.report.assets.first)
    let assetID = try #require(asset.catalogID)
    let cacheURL = home.appendingPathComponent("Library/Application Support/Ableton/Live Database/Live-plugins-1.db")
    let bindings = try LivePluginCache.bindings(LivePluginCache.read(cacheURL), assets: snapshot.report.assets)
    let binding = try #require(bindings.first { $0.classID == created.classID })
    let stored = try await store.recordHostUsage(created, binding: binding, for: assetID, at: Date())
    #expect(stored.sourceID == HostUsageProvenance.manualCreateSourceID)
    #expect(stored.hostUsage == created)
    let replayed = try await CatalogStore(url: store.url).dateEvidence(for: assetID, asOf: Date())
    #expect(replayed == [stored])

    // Isolate the older startup-only Splice load/Created pair in the native log. That
    // sequence has no Going-to-create, even though the same 12.4.6 log now has a valid
    // later Pro-Q 4 manual event.
    let lines = String(decoding: liveLog, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
    let spliceUse = try #require(lines.firstIndex { $0.contains("Splice: Use plugin at:") })
    let spliceCreated = try #require(lines[spliceUse...].firstIndex { $0.contains("VST3: Created: SpliceAbletonLive") })
    let spliceLoaded = try #require(lines[spliceUse...spliceCreated].firstIndex { $0.contains("VST3: plugin processor successfully loaded: Splice 'SpliceAbletonLive'") })
    let spliceInit = try #require(lines[..<spliceUse].lastIndex { $0.contains("Init: Version: 'Live 12.4.6") })
    let startupOnlyLines = [lines[spliceInit], lines[spliceUse], lines[spliceLoaded], lines[spliceCreated]]
    let startupOnly = try LiveUsageLog.parse(Data((startupOnlyLines.joined(separator: "\n") + "\n").utf8))
    #expect(startupOnly.events.isEmpty)
}

@Test func liveAllowsOnlyObservedMidiContinuationAndChecksWarningClocks() throws {
    let input = liveInit + liveDocument()
    let commit = liveLine(7, "Default App: End ExchangeDocument")
    let midi = liveLine(6, "AMidiIO: Midi Remote Scripts: ") + "  MidiRemoteScript 1 [Control Surface=\"None\"]\n"
    #expect(try LiveUsageLog.parse(Data(input.replacingOccurrences(of: commit, with: midi + commit).utf8)).events.count == 1)
    #expect(try LiveUsageLog.parse(Data(input.replacingOccurrences(of: commit, with: "  unknown payload\n" + commit).utf8)).events.isEmpty)
    let warning = "2026-09-26T12:00:04.500000: warning: VST3: Restore 1 failed: Test Synth\n"
    #expect(try LiveUsageLog.parse(Data(input.replacingOccurrences(of: commit, with: warning + commit).utf8)).events.isEmpty)
    let rollback = "2026-09-26T11:00:00.000000: warning: ignored warning\n"
    #expect(try LiveUsageLog.parse(Data(input.replacingOccurrences(of: commit, with: rollback + commit).utf8)).events.isEmpty)
}

@Test func liveRunBoundariesResetBeforePreviousDocumentClockValidation() throws {
    let incomplete = liveInit + liveLine(1, "Loading document \"/fixtures/Incomplete.als\"")
    let unknownRun = liveInit.replacingOccurrences(of: "Live 12.4.6", with: "Live 13.0.0")
    #expect(try LiveUsageLog.parse(Data((incomplete + unknownRun + liveDocument()).utf8)).events.isEmpty)
    let later = liveDocument().replacingOccurrences(of: "12:00:", with: "12:10:")
    #expect(try LiveUsageLog.parse(Data((incomplete + later).utf8)).events.count == 1)
}

@Test func cubaseUsageRequiresCompletedProjectLoadAndRejectsPlaceholders() throws {
    func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    let base: [String: Any] = ["smtg_type": "instance_begin", "smtg_instance_uid": "ABC", "smtg_time": 1]
    let project: [String: Any] = ["smtg_type": "project_added", "smtg_project_uid": "P1", "smtg_event_uid": "E0", "smtg_time": 2]
    let add: [String: Any] = ["smtg_type": "report", "smtg_report_name": "Plugin Instance Info: VST - Add", "smtg_event_uid": "E1", "smtg_time": 3, "Name": "Pro-Q 4", "Vendor": "FabFilter", "Version": "4.1.2.0", "Architecture": "arm64"]
    let activate: [String: Any] = ["smtg_type": "project_activated", "smtg_time": 4]
    let success: [String: Any] = ["smtg_type": "report", "smtg_report_name": "Project Status: Load", "Status Code": "kErrorNone", "smtg_time": 5]
    let failure: [String: Any] = ["smtg_type": "report", "smtg_report_name": "Project Status: Load", "Status Code": "kErrorPluginMissing", "smtg_time": 5]
    let placeholder = add.merging(["Name": "Diva", "Vendor": "Steinberg Media Technologies", "Version": ""]){ _,new in new }
    let good = line(base) + line(project) + line(add) + line(activate) + line(success)
    #expect(try CubaseUsageLog.parse(Data(good.utf8)).map(\.name) == ["Pro-Q 4"])
    #expect(try CubaseUsageLog.parse(Data((line(base) + line(project) + line(add) + line(activate) + line(failure)).utf8)).isEmpty)
    #expect(try CubaseUsageLog.parse(Data((line(base) + line(project) + line(placeholder) + line(activate) + line(success)).utf8)).isEmpty)
    #expect(try CubaseUsageLog.parse(Data((line(base) + line(project) + line(add) + line(activate)).utf8)).isEmpty)
}

@Test func cubaseCapturedControlsProduceExpectedCandidateCountsWhenPresent() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/date-evidence")
    guard let baseline = try? Data(contentsOf: root.appendingPathComponent("cubase-usage-baseline.jsonl")),
          let missing = try? Data(contentsOf: root.appendingPathComponent("cubase-usage-missing-control.jsonl")) else { return }
    #expect(try CubaseUsageLog.parse(baseline).count >= 3)
    #expect(try CubaseUsageLog.parse(missing).allSatisfy { $0.name != "Diva" })
}

@Test func cubaseCacheRequiresExactDescriptorTuple() throws {
    let xml = """
    <plugins><plugin><path>/Library/Audio/Plug-Ins/VST3/Diva.vst3</path><class><cid>D39D5B69D6AF42FA1234567844695661</cid><category>Audio Module Class</category><name>Diva</name><vendor>u-he</vendor><version>1.4.8</version></class><class><cid>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA</cid><category>Component Controller Class</category><name>Diva</name><vendor>u-he</vendor><version>1.4.8</version></class></plugin></plugins>
    """
    let classes = try CubasePluginCache.read(Data(xml.utf8))
    let good = CubasePluginUse(name: "Diva", vendor: "u-he", version: "1.4.8", architecture: "arm64", eventID: "e", projectID: "p", reportedMilliseconds: 1)
    let placeholder = CubasePluginUse(name: "Diva", vendor: "Steinberg Media Technologies", version: "", architecture: "arm64", eventID: "x", projectID: "p", reportedMilliseconds: 1)
    #expect(CubasePluginCache.bindings(for: good, in: classes).count == 1)
    #expect(CubasePluginCache.bindings(for: placeholder, in: classes).isEmpty)
}

@Test func cubaseInstalledCacheIsBoundedAndContainsOnlyAudioClassesWhenPresent() throws {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/Cubase 15/Cubase Pro VST3 Cache (arm64)/vst3plugins.xml")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let classes = try CubasePluginCache.read(url)
    #expect(classes.count > 0 && classes.count <= 10_000)
    #expect(classes.allSatisfy { $0.category == "Audio Module Class" && $0.path.hasPrefix("/") })
}

@Test func cubaseCollectorBindsOnlyExactCurrentClasses() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cubase-collector-" + UUID().uuidString)
    let logs = root.appendingPathComponent("Library/Logs/Steinberg/usagelogger")
    let cache = root.appendingPathComponent("Library/Preferences/Cubase 15/Cubase Pro VST3 Cache (arm64)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let xml = "<plugins><plugin><path>/Library/Audio/Plug-Ins/VST3/Q.vst3</path><class><cid>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA</cid><category>Audio Module Class</category><name>Q</name><vendor>FabFilter</vendor><version>1</version></class></plugin></plugins>"
    try Data(xml.utf8).write(to: cache.appendingPathComponent("vst3plugins.xml"))
    let log = """
    {"smtg_type":"instance_begin","smtg_instance_uid":"I","smtg_time":1}
    {"smtg_type":"project_added","smtg_project_uid":"P","smtg_event_uid":"P0","smtg_time":2}
    {"smtg_type":"report","smtg_report_name":"Plugin Instance Info: VST - Add","smtg_event_uid":"E","smtg_time":3,"Name":"Q","Vendor":"FabFilter","Version":"1","Architecture":"arm64"}
    {"smtg_type":"project_activated","smtg_time":4}
    {"smtg_type":"report","smtg_report_name":"Project Status: Load","Status Code":"kErrorNone","smtg_time":5}
    """
    try Data(log.utf8).write(to: logs.appendingPathComponent("SESSION.json"))
    let result = CubaseUsageCollector.collect(home: root)
    #expect(result.uses.count == 1 && result.uses[0].pluginPath.hasSuffix("Q.vst3") && result.failures == 0)
}

@Test func cubaseUseEvidenceHasIndependentSourceAndAbsoluteClock() throws {
    let use = CubasePluginUse(name: "Q", vendor: "FabFilter", version: "1", architecture: "arm64", eventID: "event", projectID: "project", reportedMilliseconds: 1_790_474_024_000)
    let record = AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.eventID, subjectID: "plugin-id", kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: Date(timeIntervalSince1970: 1_790_474_025), cubaseUsage: use)
    _ = try AssetDateResolver.summarize([record], for: "plugin-id", asOf: Date(timeIntervalSince1970: 1_790_474_025))
    let decoded = try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(record))
    #expect(decoded == record && decoded.hostUsage == nil)
}

@Test func logicMixerObservationHasExplicitCurrentSessionScope() throws {
    let use = LogicPluginUse(name: "Diva", reportedDate: Date(timeIntervalSince1970: 1_790_474_024))
    let record = AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: use.eventID, subjectID: "plugin-id", kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: Date(timeIntervalSince1970: 1_790_474_025), logicUsage: use)
    _ = try AssetDateResolver.summarize([record], for: "plugin-id", asOf: Date(timeIntervalSince1970: 1_790_474_025))
    #expect(use.scope == "currentMixer")
    #expect(try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(record)) == record)
}

@Test func nativeLogicMixerObservationRuntime() throws {
    guard ProcessInfo.processInfo.environment["PRISM_LOGIC_USAGE_RUNTIME"] == "1" else { return }
    let uses = LogicAccessibilityCollector.collect()
    _ = uses.count
    #expect(uses.allSatisfy { $0.scope == "currentMixer" })
}
