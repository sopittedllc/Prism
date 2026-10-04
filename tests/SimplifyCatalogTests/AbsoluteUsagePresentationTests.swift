import Foundation
import Testing
@testable import SimplifyCatalog
@testable import SimplifyCore

@Test func absoluteUsagePresentationFollowsDisplayZone() throws {
    let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let cubase = CubasePluginUse(name: "Glow", vendor: "Lese", version: "1", architecture: "arm64",
                                 eventID: "cubase", projectID: "project", reportedMilliseconds: 1_791_077_544_896)
    let logic = LogicPluginUse(name: "Test", reportedDate: cubase.reportedDate)
    let ingested = Date(timeIntervalSince1970: 1_791_077_545)
    let records = [
        AssetDateEvidence(sourceID: CubasePluginUse.sourceID, evidenceID: cubase.eventID,
                          subjectID: "cubase", kind: .confirmedUse, eventDate: cubase.reportedDate,
                          ingestedAt: ingested, cubaseUsage: cubase),
        AssetDateEvidence(sourceID: LogicPluginUse.sourceID, evidenceID: logic.eventID,
                          subjectID: "logic", kind: .confirmedUse, eventDate: logic.reportedDate,
                          ingestedAt: ingested, logicUsage: logic)
    ]
    for record in records {
        #expect(UsageDatePresentation(record: record, timeZone: la).value == "2026-10-03")
        #expect(UsageDatePresentation(record: record, timeZone: tokyo).value == "2026-10-04")
        #expect(UsageDatePresentation(record: record, timeZone: la).accessibility.contains("local display time"))
    }
}
