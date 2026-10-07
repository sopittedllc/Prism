import Foundation
import Testing
@testable import SimplifyCore

private let ptHeader = "SESSION NAME:\tExample\nSAMPLE RATE:\t48000.000000\nBIT DEPTH:\t24-bit\nSESSION START TIMECODE:\t04:00:00:00\nTIMECODE FORMAT:\t24 Frame\n# OF AUDIO TRACKS:\t1\n# OF AUDIO CLIPS:\t2\n# OF AUDIO FILES:\t1\n\n\n"
private let ptOnline = "O N L I N E  F I L E S  I N  S E S S I O N\nFilename   \tLocation\n"
private let ptOffline = "O F F L I N E  F I L E S  I N  S E S S I O N\nFilename\tLocation\n"
private let ptClips = "O N L I N E  C L I P S  I N  S E S S I O N\nCLIP NAME\tSource File\n"
private let ptPlugins = "P L U G - I N S  L I S T I N G\nMANUFACTURER\tPLUG-IN NAME\tVERSION\tFORMAT\tSTEMS\tNUMBER OF INSTANCES\n"
private let ptRow = "Example maker   \tExample synth   \t1.0\tAAX Native\tStereo / Stereo\t1 active\n"
private func ptData(_ body: String) -> Data { Data((ptHeader + body).utf8) }

@Test func proToolsRestoreAndManualAttemptKeepDistinctQualifiedSources() throws {
    let complete = """
    *** Digidesign Session Trace for:\t/Applications/Pro Tools.app (pid=0x1234, version=24.10.2)
    *** Starting Timestamp:\tSaturday, September 26, 2026 at 3:42:40 PM Pacific Daylight Time (94.000000 s)
    100.000000,00103,0f09: Local wall clock:  9/26/2026 15:42:46
    100.100000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "FabFilter Pro-Q 4", track "Audio 1"
    101.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2
    """
    let attempt = "100.100000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: \"Diva\", track \"Inst 2\"\n"
    let result = try ProToolsUsageLog.parse(Data((complete + "\n").utf8))
    #expect(result.map(\.name) == ["FabFilter Pro-Q 4"])
    #expect(result.first?.reportedDate == nil)
    #expect(result.first?.localTime?.canonical == "2026-09-26T15:42:46.000000")
    #expect(result.first?.eventSourceID == ProToolsPluginUse.restoreV2SourceID)
    #expect(try ProToolsUsageLog.parse(Data(attempt.utf8)).isEmpty)
    let manual = complete.replacingOccurrences(of: "101.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2", with: "101.000000,00103,0033: SMgr_DSPCache::FreePlugIn - name: \"FabFilter Pro-Q 4\"")
    let attempted = try #require(ProToolsUsageLog.parse(Data((manual + "\n").utf8)).first)
    #expect(attempted.eventSourceID == ProToolsPluginUse.attemptedSourceID)
    #expect(attempted.name == "FabFilter Pro-Q 4")
}

@Test func capturedProToolsRestoreLogYieldsOnlyCompletedHostInstancesWhenPresent() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/date-evidence/reopen-baseline-observed.log.txt")
    guard let data = try? Data(contentsOf: url) else { return }
    let uses = try ProToolsUsageLog.parse(data)
    // This retained native tail has no immutable launch header. It is raw
    // diagnostic evidence, not sufficient to mint authoritative v2 IDs.
    #expect(uses.isEmpty)
}

private func ptTrace(_ body: String, launch: String = "Saturday, September 26, 2026 at 3:42:40 PM Pacific Daylight Time (94.000000 s)") -> Data {
    Data(("*** Digidesign Session Trace for:\t/Applications/Pro Tools.app (pid=0x1234, version=24.10.2)\n"
        + "*** Starting Timestamp:\t" + launch + "\n" + body).utf8)
}

@Test func proToolsCivilAnchorsAreTimezoneIndependentAndUseEventDelta() throws {
    let body = """
    928141.282315,00103,0b09: Local wall clock:  9/26/2026 15:43:16
    928141.985707,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "FabFilter Pro-Q 4", track "Audio 1"
    928142.437668,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2
    """
    let prior = NSTimeZone.default
    defer { NSTimeZone.default = prior }
    NSTimeZone.default = TimeZone(secondsFromGMT: 13 * 3600)!
    let east = try ProToolsUsageLog.parse(ptTrace(body + "\n"))
    NSTimeZone.default = TimeZone(secondsFromGMT: -11 * 3600)!
    let west = try ProToolsUsageLog.parse(ptTrace(body + "\n"))
    #expect(east == west)
    #expect(east.first?.localTime?.canonical == "2026-09-26T15:43:16.000000")
    #expect(east.first?.reportedDate == nil)
}

@Test func proToolsMultipleAnchorsMidnightAndClockConflictFailClosed() throws {
    let good = """
    100.000000,00103,0b09: Local wall clock:  9/26/2026 23:59:20
    130.000000,00103,0b09: Local wall clock:  9/26/2026 23:59:50
    142.000000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "After Midnight", track "Audio 1"
    143.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2
    """
    #expect(try ProToolsUsageLog.parse(ptTrace(good + "\n")).first?.localTime?.dayKey == "2026-09-27")
    for seconds in ["139.500000", "140.500000"] {
        let edge = good.replacingOccurrences(of: "142.000000,00103,0033", with: seconds + ",00103,0033")
        #expect(try ProToolsUsageLog.parse(ptTrace(edge + "\n")).isEmpty)
    }
    let conflict = good.replacingOccurrences(of: "9/26/2026 23:59:50", with: "9/26/2026 23:58:50")
    #expect(try ProToolsUsageLog.parse(ptTrace(conflict + "\n")).isEmpty)
    let toleratedCorrectionButReversedEvent = """
    100.000000,00103,0b09: Local wall clock:  9/26/2026 15:42:46
    101.500000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "First", track "Audio 1"
    102.000000,00103,0b09: Local wall clock:  9/26/2026 15:42:46
    102.200000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "Second", track "Audio 2"
    103.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2
    """
    #expect(try ProToolsUsageLog.parse(ptTrace(toleratedCorrectionButReversedEvent + "\n")).isEmpty)
}

@Test func proToolsStableRunIdentityAppendReplayAndFailureFences() throws {
    let beginning = """
    100.000000,00103,0b09: Local wall clock:  9/26/2026 15:42:46
    100.100000,00103,0033: SMgr_DSPCache::InstantiatePlugIn - pluginType: Host, name: "Test", track "Audio 1"
    101.000000,00103,0e0c: PtSess_RunTime::PutDocumentInfo - session was last saved with app version: 2024.10.2
    """
    let first = try #require(ProToolsUsageLog.parse(ptTrace(beginning + "\n")).first)
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
    payload["sourceSeconds"] = 100.9
    let alteredSeconds = try JSONDecoder().decode(ProToolsPluginUse.self,
        from: JSONSerialization.data(withJSONObject: payload))
    #expect(throws: AssetDateEvidenceError.invalidProvenance) { try alteredSeconds.validateV2() }
    payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
    var civil = try #require(payload["localTime"] as? [String: Any])
    civil["second"] = 47
    payload["localTime"] = civil
    let alteredCivil = try JSONDecoder().decode(ProToolsPluginUse.self,
        from: JSONSerialization.data(withJSONObject: payload))
    #expect(throws: AssetDateEvidenceError.invalidProvenance) { try alteredCivil.validateV2() }
    let appended = try #require(ProToolsUsageLog.parse(ptTrace(beginning + "\n102.000000,00103,0001: later\n")).first)
    #expect(first == appended)
    let secondRun = try #require(ProToolsUsageLog.parse(ptTrace(beginning + "\n", launch: "Sunday, September 27, 2026 at 3:42:40 PM Pacific Daylight Time (94.000000 s)")).first)
    #expect(first.eventID != secondRun.eventID)
    #expect(first.subjectEventID("A") != first.subjectEventID("B"))
    let failed = beginning.replacingOccurrences(of: "101.000000,00103,0e0c", with: "100.500000,00103,0033: CFicAAXWidget::CreateComponentInstance - converting -14013 to kCantInstantiatePlugIn\n101.000000,00103,0e0c")
    #expect(try ProToolsUsageLog.parse(ptTrace(failed + "\n")).map(\.eventSourceID) == [ProToolsPluginUse.attemptedSourceID])
    let reset = beginning.replacingOccurrences(of: "101.000000,00103,0e0c",
        with: "100.500000,00103,0b09: Opening session: disposable\n101.000000,00103,0e0c")
    #expect(try ProToolsUsageLog.parse(ptTrace(reset + "\n")).map(\.eventSourceID) == [ProToolsPluginUse.attemptedSourceID])
    let unsupported = beginning.replacingOccurrences(of: "session was last saved with app version: 2024.10.2",
        with: "unsupported completion")
    #expect(try ProToolsUsageLog.parse(ptTrace(unsupported + "\n")).map(\.eventSourceID) == [ProToolsPluginUse.attemptedSourceID])
    #expect(try ProToolsUsageLog.parse(ptTrace(beginning.trimmingCharacters(in: .newlines))).map(\.eventSourceID) == [ProToolsPluginUse.attemptedSourceID])
}

@Test func nativeProToolsStartupSnapshotDoesNotBecomeUseWithoutSession() throws {
    guard ProcessInfo.processInfo.environment["PRISM_PROTOOLS_USAGE_RUNTIME"] == "1" else { return }
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/date-evidence/manual-protools/startup.log")
    let data = try Data(contentsOf: url)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.contains("*** Starting Timestamp:"))
    #expect(!text.contains("Opening session:"))
    #expect(!text.contains("PtSess_RunTime::PutDocumentInfo"))
    #expect(try ProToolsUsageLog.parse(data).isEmpty)
}

@Test func proToolsListsRetainPoolSemanticsAndRawPluginFields() throws {
    let body = ptOnline + "Tone.wav\tVolume:Audio:\n\n" + ptOffline
        + "Missing.wav\tOffline:Audio:\n\n" + ptClips + "Tone.L\tTone.wav\t[1]\nTone.R\tTone.wav\t[2]\n\n"
        + ptPlugins + ptRow + ptRow.replacingOccurrences(of: "1 active", with: "1 active, 2 inactive")
    let r = try ProToolsSessionTextReader.parse(ptData(body))
    #expect(r.adapterVersion == 2 && r.coverage == "partial-export" && r.sessionName == "Example")
    #expect(r.includedSections == ["online-files", "offline-files", "online-clips", "plugins"])
    #expect(r.plugins.count == 2 && r.plugins.map(\.name) == ["Example synth", "Example synth"])
    #expect(r.plugins[0].manufacturer == "Example maker" && r.plugins[0].version == "1.0")
    #expect(r.plugins[0].format == "AAX Native" && r.plugins[0].stems == "Stereo / Stereo")
    #expect(r.plugins[1].instanceSummary == "1 active, 2 inactive")
    #expect(r.files.map(\.availability) == ["online", "offline"])
    #expect(r.files[0].location == "Volume:Audio:" && r.files[1].name == "Missing.wav")
    #expect(r.clips.map(\.sourceFile) == ["Tone.wav", "Tone.wav"] && r.clips.map(\.channel) == ["[1]", "[2]"])
    #expect(r.limitations.contains { $0.contains("not proof of timeline") })
    #expect(r.limitations.contains { $0.contains("not Last used") })
}

@Test func proToolsAbsentAndEmptySectionsAreDistinctAndDecoysStayData() throws {
    let absent = try ProToolsSessionTextReader.parse(ptData(ptOnline))
    let empty = try ProToolsSessionTextReader.parse(ptData(ptPlugins.trimmingCharacters(in: .newlines)))
    #expect(absent.plugins.isEmpty && !absent.includedSections.contains("plugins"))
    #expect(empty.plugins.isEmpty && empty.includedSections == ["plugins"])
    let headingInCell = ptRow.replacingOccurrences(of: "Example synth   ", with: "P L U G - I N S  L I S T I N G")
    let tail = "\nM A R K E R S  L I S T I N G\nPLUG-INS:\tDecoy\n\n" + ptPlugins + ptRow
    let parsed = try ProToolsSessionTextReader.parse(ptData(ptPlugins + headingInCell + tail))
    #expect(parsed.plugins.count == 1 && parsed.plugins[0].name == "P L U G - I N S  L I S T I N G")
    #expect(try ProToolsSessionTextReader.parse(ptData(ptOnline + "\nM A R K E R S  L I S T I N G\n" + ptPlugins + ptRow)).plugins.isEmpty)
    for ending in ["\n", "\r", "\r\n"] {
        let text = "\u{FEFF}" + (ptHeader + ptPlugins + ptRow).replacingOccurrences(of: "\n", with: ending)
        #expect(try ProToolsSessionTextReader.parse(Data(text.utf8)).plugins.count == 1)
    }
}

@Test func proToolsRejectsAmbiguousTruncatedAndUnsupportedTables() {
    let invalid = [ptHeader, ptHeader.replacingOccurrences(of: "SESSION NAME:", with: "SESSION:") + ptPlugins,
                   ptHeader + ptPlugins + ptPlugins, ptHeader + ptPlugins + ptOnline,
                   ptHeader + "UNKNOWN SECTION\n", ptHeader + "P L U G - I N S  L I S T I N G\n",
                   ptHeader + ptPlugins.replacingOccurrences(of: "MANUFACTURER", with: "MAKER"),
                   ptHeader + ptPlugins + "Maker\tTruncated\n", ptHeader + ptPlugins + ptRow.replacingOccurrences(of: "\t1.0\t", with: "\t\t"),
                   ptHeader + ptPlugins + ptRow.replacingOccurrences(of: "1 active", with: "1 active\textra"),
                   ptHeader + ptClips + "Clip\tSource.wav\n", ptHeader + ptOnline + "File\tLocation\textra\n",
                   ptHeader + ptPlugins + "O F F L I N E  C L I P S  I N  S E S S I O N\n",
                   ptHeader + "T R A C K  L I S T I N G\n" + ptPlugins,
                   ptHeader + ptPlugins + ptRow.replacingOccurrences(of: "1 active", with: String(repeating: "X", count: 1_025))]
    for text in invalid {
        #expect(throws: (any Error).self) { try ProToolsSessionTextReader.parse(Data(text.utf8)) }
    }
    for data in [Data([0xff]), Data((ptHeader + ptPlugins).utf16.map { UInt8(truncatingIfNeeded: $0) } + [0])] {
        #expect(throws: (any Error).self) { try ProToolsSessionTextReader.parse(data) }
    }
}

@Test func proToolsBudgetsApplyAcrossSectionsAndUnparsedTail() throws {
    let max = ProToolsSessionTextReader.maximumRows
    #expect(try ProToolsSessionTextReader.parse(ptData(ptPlugins + String(repeating: ptRow, count: max))).plugins.count == max)
    let invalid = [
        ptData(ptOnline + "File\tVolume:\n" + ptPlugins + String(repeating: ptRow, count: max)),
        ptData(ptPlugins + "T R A C K  L I S T I N G\n" + String(repeating: "x", count: ProToolsSessionTextReader.maximumLineBytes + 1)),
        ptData(ptPlugins + "T R A C K  L I S T I N G\n" + String(repeating: "\n", count: ProToolsSessionTextReader.maximumLines)),
        ptData(ptPlugins + "T R A C K  L I S T I N G\n\0"),
        ptData(ptPlugins + "M A R K E R S  L I S T I N G\n\u{007F}"),
        Data(repeating: 32, count: ProToolsSessionTextReader.maximumInputBytes + 1)]
    for data in invalid { #expect(throws: (any Error).self) { try ProToolsSessionTextReader.parse(data) } }
}

@Test func proToolsFileBoundaryAndCatalogExclusion() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".work/scratch/pt-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("session.txt"), link = root.appendingPathComponent("link.txt")
    let data = ptData(ptPlugins + ptRow)
    try data.write(to: file)
    #expect(try ProToolsSessionTextReader.inspect(file).plugins.count == 1)
    #expect(try Data(contentsOf: file) == data)
    #expect(ProjectReader.read(file).coverage == "unsupported" && ProjectReader.read(file).references.isEmpty)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    let ancestor = root.appendingPathComponent("ancestor")
    try FileManager.default.createSymbolicLink(at: ancestor, withDestinationURL: root)
    for target in [root, link, ancestor.appendingPathComponent("session.txt"), root.appendingPathComponent("missing")] {
        #expect(throws: (any Error).self) { try ProToolsSessionTextReader.inspect(target) }
    }
}
