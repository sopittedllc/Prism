import Foundation
import CryptoKit
import Testing
@testable import SimplifyCore

@Test func cubaseCollectorChoosesNewestSixteenLogsWithoutUsingMtimeAsEventTime() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/SimplifyTests/" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let entries = try (0..<18).map { index -> URL in
        let url = root.appendingPathComponent(String(format: "log-%02d.json", index))
        try Data("fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 100))], ofItemAtPath: url.path)
        return url
    }
    let selected = CubaseUsageCollector.recentLogs(entries.reversed())
    #expect(selected.count == 16)
    #expect(selected.first == entries[17] && selected.last == entries[2])
    #expect(!selected.contains(entries[0]) && !selected.contains(entries[1]))
}

private func nativeLine(_ fields: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self) + "\n"
}

private func nativeFixture(status: String = "kErrorNone", includeActivation: Bool = true,
                           version: String = "15.0.5.121", remove: Bool = false) -> String {
    let session = "SESSION", project = "PROJECT"
    func event(_ type: String, _ time: Int64, extra: [String: Any] = [:]) -> String {
        nativeLine(["smtg_type": type, "smtg_instance_uid": session, "smtg_time": time].merging(extra) { _, new in new })
    }
    func report(_ name: String, _ uid: Int64, _ time: Int64, _ fields: [(String, String)]) -> String {
        event("report", time, extra: ["smtg_report_name": name, "smtg_report_uid": uid])
            + fields.map { key, value in
                event("report", time, extra: ["smtg_report_key": key, "smtg_string": value, "smtg_report_uid": uid])
            }.joined()
    }
    let descriptor = [("Name", "Glow"), ("Vendor", "Lese"), ("Type", "Audio Module Class"),
                      ("Version", "1.3.2"), ("Architecture", "x64|arm64")]
    return event("instance_begin", 1, extra: ["smtg_product_name": "Cubase Pro", "smtg_product_version": version])
        + event("project_added", 2, extra: ["smtg_project_uid": project])
        + report("Plugin Instance Info: VST - Add", 100, 3, descriptor)
        + (remove ? report("Plugin Instance Info: VST - Remove", 101, 4, descriptor) : "")
        + (includeActivation ? event("project_activated", 5, extra: ["smtg_project_uid": project]) : "")
        + report("Project Status: Load", 102, 6,
                 [("Status Code", status), ("File Size", "1 KB"), ("Persistence Time", "2 ms")])
}

@Test func nativeCubaseRestoreRequiresCompleteMatchingGroups() throws {
    let good = nativeFixture()
    let uses = try CubaseUsageLog.parse(Data(good.utf8))
    #expect(uses.count == 1)
    #expect(uses.first?.name == "Glow" && uses.first?.reportedMilliseconds == 3)
    #expect(try CubaseUsageLog.parse(Data((good + good).utf8)).count == 1)
    for bad in [nativeFixture(status: "kErrorMissing"), nativeFixture(includeActivation: false),
                nativeFixture(version: "15.0.5.122"), nativeFixture(remove: true),
                good.replacingOccurrences(of: "Audio Module Class", with: "Instrument Class"),
                good.replacingOccurrences(of: "\"smtg_report_key\":\"Status Code\"", with: "\"smtg_report_key\":\"Other\"") ] {
        #expect(try CubaseUsageLog.parse(Data(bad.utf8)).isEmpty)
    }
    let torn = Data(good.dropLast().utf8)
    #expect(try CubaseUsageLog.parse(torn).isEmpty)
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data((good + "not-json\n").utf8)) }
}

@Test func nativeCubaseRestoreRejectsConflictsAndBounds() throws {
    let good = nativeFixture()
    let duplicate = good.replacingOccurrences(of: "\"smtg_report_key\":\"Vendor\"", with: "\"smtg_report_key\":\"Name\"")
    #expect(try CubaseUsageLog.parse(Data(duplicate.utf8)).isEmpty)
    let wrongSession = good.replacingOccurrences(of: "\"smtg_instance_uid\":\"SESSION\",\"smtg_report_key\":\"Vendor\"", with: "\"smtg_instance_uid\":\"FOREIGN\",\"smtg_report_key\":\"Vendor\"")
    #expect(try CubaseUsageLog.parse(Data(wrongSession.utf8)).isEmpty)
    let addLastChild = nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 3,
                                   "smtg_report_uid": 100, "smtg_report_key": "Architecture", "smtg_string": "x64|arm64"])
    let loadLastChild = nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 6,
                                    "smtg_report_uid": 102, "smtg_report_key": "Persistence Time", "smtg_string": "2 ms"])
    let malformedExtra = nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 3,
                                      "smtg_report_uid": 100, "smtg_string": "extra"])
    let foreignExtra = nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 6,
                                    "smtg_report_uid": 999, "smtg_report_key": "Extra", "smtg_string": "extra"])
    let foreignSessionExtra = nativeLine(["smtg_type": "report", "smtg_instance_uid": "FOREIGN", "smtg_time": 6,
                                           "smtg_report_uid": 102, "smtg_report_key": "Extra", "smtg_string": "extra"])
    let repeatedHeader = nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 6,
                                       "smtg_report_uid": 102, "smtg_report_name": "Project Status: Load"])
    #expect(try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: addLastChild, with: addLastChild + malformedExtra).utf8)).isEmpty)
    #expect(try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: loadLastChild, with: loadLastChild + foreignExtra).utf8)).isEmpty)
    #expect(try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: loadLastChild, with: loadLastChild + foreignSessionExtra).utf8)).isEmpty)
    #expect(try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: loadLastChild, with: loadLastChild + repeatedHeader).utf8)).isEmpty)
    let wrongProjectActivation = good.replacingOccurrences(of: "\"smtg_project_uid\":\"PROJECT\",\"smtg_time\":5",
                                                           with: "\"smtg_project_uid\":\"OTHER\",\"smtg_time\":5")
    #expect(try CubaseUsageLog.parse(Data(wrongProjectActivation.utf8)).isEmpty)
    let interleaved = good.replacingOccurrences(of: loadLastChild, with: loadLastChild)
        .replacingOccurrences(of: nativeLine(["smtg_type": "project_activated", "smtg_instance_uid": "SESSION", "smtg_time": 5,
                                               "smtg_project_uid": "PROJECT"]),
                              with: nativeLine(["smtg_type": "project_added", "smtg_instance_uid": "SESSION", "smtg_time": 4,
                                                "smtg_project_uid": "OTHER"])
                                    + nativeLine(["smtg_type": "project_activated", "smtg_instance_uid": "SESSION", "smtg_time": 5,
                                                  "smtg_project_uid": "OTHER"]))
    #expect(try CubaseUsageLog.parse(Data(interleaved.utf8)).isEmpty)
    let conflictingReport = good.replacingOccurrences(of: "\"smtg_report_uid\":100,\"smtg_string\":\"Glow\"",
                                                        with: "\"smtg_report_uid\":100,\"smtg_string\":\"Other\"")
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data((good + conflictingReport).utf8)) }
    let rollback = good.replacingOccurrences(of: "\"smtg_time\":5", with: "\"smtg_time\":2")
    #expect(try CubaseUsageLog.parse(Data(rollback.utf8)).isEmpty)
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(repeating: 32, count: CubaseUsageLog.maximumBytes + 1)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(String(repeating: "{}\n", count: CubaseUsageLog.maximumLines + 1).utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data((good + String(repeating: " ", count: 256 * 1_024 + 1) + "\n").utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: "Glow", with: String(repeating: "X", count: 1_025)).utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: "PROJECT", with: String(repeating: "P", count: 257)).utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: "\"smtg_report_uid\":100", with: "\"smtg_report_uid\":\"100\"").utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: "\"smtg_report_uid\":100", with: "\"smtg_report_uid\":1.5").utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: "\"smtg_string\":\"Glow\"", with: "\"smtg_string\":12").utf8)) }
    #expect(throws: (any Error).self) { try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: "\"smtg_time\":3", with: "\"smtg_time\":-1").utf8)) }
    let extraChild = nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 3,
                                 "smtg_report_uid": 100, "smtg_report_key": "Extra", "smtg_string": "x"])
    #expect(throws: (any Error).self) {
        try CubaseUsageLog.parse(Data(good.replacingOccurrences(of: addLastChild,
            with: addLastChild + String(repeating: extraChild, count: 4)).utf8))
    }
    let opening = nativeLine(["smtg_type": "instance_begin", "smtg_instance_uid": "SESSION", "smtg_time": 1,
                              "smtg_product_name": "Cubase Pro", "smtg_product_version": "15.0.5.121"])
        + nativeLine(["smtg_type": "project_added", "smtg_instance_uid": "SESSION", "smtg_time": 2,
                      "smtg_project_uid": "PROJECT"])
    let pending = (0...4_096).map { uid in
        nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 3,
                    "smtg_report_uid": uid, "smtg_report_name": "Plugin Instance Info: VST - Add"])
        + [("Name", "Glow"), ("Vendor", "Lese"), ("Type", "Audio Module Class"),
           ("Version", "1.3.2"), ("Architecture", "arm64")].map { key, value in
            nativeLine(["smtg_type": "report", "smtg_instance_uid": "SESSION", "smtg_time": 3,
                        "smtg_report_uid": uid, "smtg_report_key": key, "smtg_string": value])
        }.joined()
    }.joined()
    #expect(throws: (any Error).self) {
        try CubaseUsageLog.parse(Data((opening + pending
            + nativeLine(["smtg_type": "project_activated", "smtg_instance_uid": "SESSION", "smtg_time": 4,
                          "smtg_project_uid": "PROJECT"])).utf8))
    }
}

@Test func absoluteHostUsageDaysAndOrderUseDisplayZone() throws {
    let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let early = CubasePluginUse(name: "Glow", vendor: "Lese", version: "1", architecture: "arm64",
                                eventID: "a", projectID: "p", reportedMilliseconds: 1_791_077_544_000)
    let late = CubasePluginUse(name: "Glow", vendor: "Lese", version: "1", architecture: "arm64",
                               eventID: "z", projectID: "p", reportedMilliseconds: 1_791_077_544_896)
    func record(_ use: CubasePluginUse) -> AssetDateEvidence {
        AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.eventID, subjectID: "plugin",
                          kind: .confirmedUse, eventDate: use.reportedDate,
                          ingestedAt: Date(timeIntervalSince1970: 1_791_077_545), cubaseUsage: use)
    }
    #expect(HostUsageOrdering.dayKey(record(early), timeZone: la) == "2026-10-03")
    #expect(HostUsageOrdering.dayKey(record(early), timeZone: tokyo) == "2026-10-04")
    #expect(HostUsageOrdering.precedes(record(late), record(early), timeZone: la))
    #expect(!HostUsageOrdering.precedes(record(early), record(late), timeZone: la))
    let logicEarly = LogicPluginUse(name: "Test", reportedDate: early.reportedDate)
    let logicLate = LogicPluginUse(name: "Test", reportedDate: late.reportedDate)
    func logicRecord(_ use: LogicPluginUse, _ id: String) -> AssetDateEvidence {
        AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: id, subjectID: "logic",
                          kind: .confirmedUse, eventDate: use.reportedDate,
                          ingestedAt: Date(timeIntervalSince1970: 1_791_077_545), logicUsage: use)
    }
    #expect(HostUsageOrdering.dayKey(logicRecord(logicEarly, "a"), timeZone: la) == "2026-10-03")
    #expect(HostUsageOrdering.precedes(logicRecord(logicLate, "z"), logicRecord(logicEarly, "a"), timeZone: la))
}

@Test func storeAbsoluteHostUsagePrefersLaterSameDayInstant() async throws {
    let f = try ReceiptFixture()
    let storeURL = f.root.appendingPathComponent("Private/absolute-usage.sqlite")
    let store = CatalogStore(url: storeURL)
    let logicBundle = f.root.appendingPathComponent("Logic.component")
    try FileManager.default.copyItem(at: f.bundle, to: logicBundle)
    let snapshot = try await store.ingest(receiptReport([receiptAsset(f.bundle), receiptAsset(logicBundle)]), scope: receiptScope(f.root))
    let id = try #require(snapshot.report.assets.first { $0.path == f.bundle.path }?.catalogID)
    let logicID = try #require(snapshot.report.assets.first { $0.path == logicBundle.path }?.catalogID)
    let now = Date(), early = Date(timeIntervalSince1970: 1_790_345_600)
    let cubaseEarly = CubasePluginUse(name: "Test", vendor: "Fixture", version: "1", architecture: "arm64",
                                      eventID: "a-cubase", projectID: "project", reportedMilliseconds: Int64(early.timeIntervalSince1970 * 1_000))
    let cubaseLate = CubasePluginUse(name: "Test", vendor: "Fixture", version: "1", architecture: "arm64",
                                     eventID: "z-cubase", projectID: "project", reportedMilliseconds: Int64(early.timeIntervalSince1970 * 1_000) + 1_000)
    let cubaseRecords = [cubaseEarly, cubaseLate].map { use in
        AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: use.eventID, subjectID: id,
                          kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: now, cubaseUsage: use)
    }
    try await store.appendDateEvidence(cubaseRecords, asOf: now)
    #expect(try await CatalogStore(url: storeURL).latestHostUsage(for: [id], asOf: now)[Data(id.utf8)] == cubaseRecords[1])
    let logicEarly = LogicPluginUse(name: "Test", reportedDate: early)
    let logicLate = try #require((1...60).map { LogicPluginUse(name: "Test", reportedDate: early.addingTimeInterval(Double($0))) }
        .first { logicEarly.eventID < $0.eventID })
    let logicRecords = [logicEarly, logicLate].map { use in
        AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: use.eventID, subjectID: logicID,
                          kind: .confirmedUse, eventDate: use.reportedDate, ingestedAt: now, logicUsage: use)
    }
    try await store.appendDateEvidence(logicRecords, asOf: now)
    #expect(try await CatalogStore(url: storeURL).latestHostUsage(for: [logicID], asOf: now)[Data(logicID.utf8)] == logicRecords[1])
}

private struct NativeCaptureMetadata: Decodable { let captured_utc: String }

private func nativeCapture(_ directory: URL, digest: String) throws -> (Data, Date) {
    let metadata = try JSONDecoder().decode(NativeCaptureMetadata.self,
                                             from: Data(contentsOf: directory.appendingPathComponent("metadata.json")))
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let anchor = try #require(formatter.date(from: metadata.captured_utc))
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let matches = try files.filter { $0.pathExtension == "json" }.compactMap { url -> Data? in
        let data = try Data(contentsOf: url)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == digest ? data : nil
    }
    return (try #require(matches.count == 1 ? matches[0] : nil), anchor)
}

@Test func nativeCubaseRestoreRuntime() async throws {
    guard ProcessInfo.processInfo.environment["PRISM_CUBASE_NATIVE_RESTORE_RUNTIME"] == "1" else { return }
    let root = ProcessInfo.processInfo.environment["PRISM_CUBASE_RESTORE_FIXTURE_DIR"].map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/date-evidence")
    let (before, beforeAnchor) = try nativeCapture(root.appendingPathComponent("cubase-restore-before-reopen-2"),
        digest: "d2f35afd62d1e3246504c27bb84ad6cecd80bde22e61c90d926fe5f4271cabbe")
    let (after, afterAnchor) = try nativeCapture(root.appendingPathComponent("cubase-restore-after-reopen"),
        digest: "effb603ac81372fda600ee0abe96be987c3c31b8ab889a503e089fcfdfaa84c5")
    #expect(after.starts(with: before))
    #expect(try CubaseUsageLog.parse(before).isEmpty)
    let uses = try CubaseUsageLog.parse(after)
    #expect(uses.count == 1 && uses[0].name == "Glow" && uses[0].reportedMilliseconds == 1_791_077_544_896)
    #expect(beforeAnchor < uses[0].reportedDate && uses[0].reportedDate < afterAnchor)
    #expect(try CubaseUsageLog.parse(after) == uses)
    let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Preferences/Cubase 15/Cubase Pro VST3 Cache (arm64)/vst3plugins.xml")
    let classes = try CubasePluginCache.read(cache)
    let bindings = CubasePluginCache.bindings(for: uses[0], in: classes)
    let bindingClass = try #require(bindings.count == 1 ? bindings[0] : nil)
    let isolated = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".work/scratch/prism-cubase-restore-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: isolated) }
    let storeURL = isolated.appendingPathComponent("catalog.sqlite")
    let store = CatalogStore(url: storeURL)
    let plugin = URL(fileURLWithPath: bindingClass.path)
    let snapshot = try await store.ingest(receiptReport([receiptAsset(plugin)]), scope: receiptScope(plugin.deletingLastPathComponent()))
    let id = try #require(snapshot.report.assets.first?.catalogID)
    let bound = CubaseBoundPluginUse(use: uses[0], pluginPath: bindingClass.path, cid: bindingClass.cid)
    let ingested = afterAnchor.addingTimeInterval(1)
    let saved = try await store.recordCubaseUsage(bound, for: id, at: ingested)
    let reopened = CatalogStore(url: storeURL)
    let replay = try await reopened.recordCubaseUsage(bound, for: id, at: ingested.addingTimeInterval(1))
    #expect(saved == replay)
    #expect(try await reopened.latestHostUsage(for: [id], asOf: ingested.addingTimeInterval(2))[Data(id.utf8)] == saved)
    #expect(try await reopened.dateEvidence(for: id, asOf: ingested.addingTimeInterval(2)).count == 1)
}
