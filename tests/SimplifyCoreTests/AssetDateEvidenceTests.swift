import Foundation
import Testing
@testable import SimplifyCore

private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
private func evidence(_ kind: AssetDateEvidenceKind, _ seconds: Double?,
                      id: String = "event", source: String = "source", subject: String = "product",
                      ingested: Double = 900) -> AssetDateEvidence {
    AssetDateEvidence(sourceID: source, evidenceID: id, subjectID: subject, kind: kind,
                      eventDate: seconds.map(date), ingestedAt: date(ingested))
}
private func summary(_ records: [AssetDateEvidence], subject: String = "product") throws -> AssetDateSummary {
    try AssetDateResolver.summarize(records, for: subject, asOf: date(1_000))
}

@Test func dateEvidencePersistentSpellingsAndFrozenRecordRemainCompatible() throws {
    let spellings = ["confirmedUse", "confirmedAddition", "installationRecord", "discovery", "projectReference",
                     "loadAttempt", "failedLoad", "scan", "mappedInHost"]
    #expect(AssetDateEvidenceKind.allCases.map(\.rawValue) == spellings)
    for kind in AssetDateEvidenceKind.allCases {
        let value = evidence(kind, nil)
        #expect(try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(value)) == value)
    }
    let frozen = #"{"sourceID":"fixture","evidenceID":"event","subjectID":"node","kind":"confirmedUse","eventDate":100,"ingestedAt":200}"#
    let decoded = try JSONDecoder().decode(AssetDateEvidence.self, from: Data(frozen.utf8))
    #expect(decoded == AssetDateEvidence(sourceID: "fixture", evidenceID: "event", subjectID: "node", kind: .confirmedUse,
                                        eventDate: Date(timeIntervalSinceReferenceDate: 100),
                                        ingestedAt: Date(timeIntervalSinceReferenceDate: 200)))
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(AssetDateEvidence.self, from: Data(frozen.replacingOccurrences(of: "confirmedUse", with: "futureKind").utf8))
    }
}

@Test func datePolicyDoesNotPromoteDiscoveryInstallationOrHostAttempts() throws {
    for kind in AssetDateEvidenceKind.allCases where kind != .confirmedUse && kind != .confirmedAddition {
        let result = try summary([evidence(kind, 800)])
        #expect(result.lastUsed == nil && result.dateAdded == nil)
    }
    let used = try summary([evidence(.confirmedUse, 300)])
    #expect(used.lastUsed == date(300) && used.dateAdded == nil)
    let added = try summary([evidence(.confirmedAddition, 100)])
    #expect(added.dateAdded == date(100) && added.lastUsed == nil)
}

@Test func legacyProToolsPayloadRemainsReadableButCannotSetLastUsed() throws {
    let legacyJSON = #"{"name":"Test","eventID":"legacy-event","reportedDate":100,"sourceSeconds":42.5}"#
    let use = try JSONDecoder().decode(ProToolsPluginUse.self, from: Data(legacyJSON.utf8))
    #expect(use.eventSourceID == ProToolsPluginUse.sourceID)
    #expect(use.localTime == nil && use.reportedDate != nil)
    let record = AssetDateEvidence(sourceID: ProToolsPluginUse.sourceID, evidenceID: use.eventID,
        subjectID: "product", kind: .confirmedUse, eventDate: use.reportedDate,
        ingestedAt: Date(timeIntervalSinceReferenceDate: 200), proToolsUsage: use)
    #expect(try AssetDateResolver.summarize([record], for: "product",
                                           asOf: Date(timeIntervalSinceReferenceDate: 300)).lastUsed == nil)
    #expect(try JSONDecoder().decode(AssetDateEvidence.self, from: JSONEncoder().encode(record)) == record)
}

@Test func datePolicyRetainsAdditionAcrossUpdateRescanAndReconnect() throws {
    let initial = [evidence(.confirmedAddition, 100, id: "original"),
                   evidence(.confirmedUse, 200, id: "use")]
    let changes = [evidence(.installationRecord, 500, id: "update"),
                   evidence(.scan, 600, id: "rescan"),
                   evidence(.discovery, 700, id: "reconnected"),
                   evidence(.mappedInHost, 800, id: "poll")]
    let result = try summary(initial + changes)
    #expect(result.dateAdded == date(100) && result.lastUsed == date(200))
    #expect(result.latestRecordedInstallation == date(500))
    #expect(result.firstDiscovered == date(700))
    // Complete-set semantics: losing original evidence cannot silently preserve it.
    #expect(try summary(changes).dateAdded == nil)
}

@Test func datePolicyReducesByEventTimeRegardlessOfOrderOrReplay() throws {
    let records = [evidence(.confirmedUse, 200, id: "use-old"), evidence(.confirmedUse, 600, id: "use-new"),
                   evidence(.confirmedAddition, 400, id: "add-late"), evidence(.confirmedAddition, 100, id: "add-old"),
                   evidence(.installationRecord, 300, id: "install-old"), evidence(.installationRecord, 700, id: "install-new"),
                   evidence(.discovery, 500, id: "found-late"), evidence(.discovery, 250, id: "found-old"),
                   evidence(.projectReference, 350, id: "reference-old"), evidence(.projectReference, 650, id: "reference-new")]
    let expected = AssetDateSummary(lastUsed: date(600), dateAdded: date(100),
                                   latestRecordedInstallation: date(700), firstDiscovered: date(250),
                                   latestProjectReference: date(650))
    #expect(try summary(records) == expected)
    #expect(try summary(Array(records.reversed())) == expected)
    #expect(try summary(records + records) == expected)
}

@Test func datePolicyNeverFallsBackToIngestionForUnknownEventTime() throws {
    for kind in AssetDateEvidenceKind.allCases {
        #expect(try summary([evidence(kind, nil)]) == summary([]))
    }
    #expect(try summary([evidence(.confirmedUse, 300, id: "known"),
                         evidence(.confirmedUse, nil, id: "unknown")]).lastUsed == date(300))
}

@Test func datePolicyDoesNotPropagatePlayerOrSiblingEvidence() throws {
    let records = [evidence(.confirmedUse, 500, id: "player", subject: "player"),
                   evidence(.confirmedUse, 700, id: "sibling", subject: "instrument-B"),
                   evidence(.confirmedAddition, 100, id: "library", subject: "library")]
    #expect(try summary(records, subject: "instrument-A") == summary([]))
    #expect(try summary(records, subject: "player").lastUsed == date(500))
}

@Test func datePolicyUsesByteExactOpaqueIdentifiersAndSourceNamespaces() throws {
    let composed = "caf\u{e9}", decomposed = "cafe\u{301}"
    #expect(composed == decomposed) // Swift equality must not govern opaque identity.
    let records = [evidence(.confirmedUse, 100, source: composed, subject: composed),
                   evidence(.confirmedUse, 200, source: decomposed, subject: decomposed)]
    #expect(try summary(records, subject: composed).lastUsed == date(100))
    #expect(try summary(records, subject: decomposed).lastUsed == date(200))
    let separateIDs = [evidence(.confirmedUse, 100, id: composed), evidence(.confirmedUse, 200, id: decomposed)]
    #expect(try summary(separateIDs).lastUsed == date(200))
    let namespaces = [evidence(.confirmedUse, 100, source: "host-A"), evidence(.confirmedUse, 200, source: "host-B")]
    #expect(try summary(namespaces).lastUsed == date(200))
}

@Test func datePolicyRejectsConflictingReplayIncludingChangedIngestion() throws {
    let original = evidence(.confirmedUse, 100)
    let conflicts = [evidence(.confirmedUse, 200), evidence(.failedLoad, 100),
                     evidence(.confirmedUse, 100, subject: "other"),
                     evidence(.confirmedUse, 100, ingested: 950), evidence(.confirmedUse, nil)]
    for conflict in conflicts {
        #expect(throws: AssetDateEvidenceError.conflictingEvidenceID) { try summary([original, conflict]) }
    }
    let composed = evidence(.confirmedUse, 100, subject: "caf\u{e9}")
    let decomposed = evidence(.confirmedUse, 100, subject: "cafe\u{301}")
    #expect(throws: AssetDateEvidenceError.conflictingEvidenceID) { try summary([composed, decomposed]) }
}

@Test func datePolicyRejectsInvalidClocksEvenForUnselectedSubjects() throws {
    #expect(throws: AssetDateEvidenceError.futureIngestion) {
        try summary([evidence(.scan, nil, subject: "other", ingested: 1_001)])
    }
    #expect(throws: AssetDateEvidenceError.eventAfterIngestion) { try summary([evidence(.confirmedUse, 901)]) }
    for invalid in [Double.nan, Double.infinity, -Double.infinity] {
        #expect(throws: AssetDateEvidenceError.nonFiniteDate) { try summary([evidence(.confirmedUse, invalid)]) }
        #expect(throws: AssetDateEvidenceError.nonFiniteDate) { try summary([evidence(.scan, nil, ingested: invalid)]) }
        #expect(throws: AssetDateEvidenceError.nonFiniteDate) {
            try AssetDateResolver.summarize([], for: "product", asOf: date(invalid))
        }
    }
    let boundary = evidence(.confirmedUse, 1_000, ingested: 1_000)
    #expect(try summary([boundary]).lastUsed == date(1_000))
}

@Test func datePolicyValidatesAllIdentifiersAndUTF8Bounds() throws {
    let invalids = ["", " \t", "a\u{0}b", "a\nb", String(repeating: "x", count: 1_025), String(repeating: "é", count: 513)]
    for invalid in invalids {
        #expect(throws: AssetDateEvidenceError.invalidIdentifier) { try summary([], subject: invalid) }
        for record in [evidence(.scan, nil, id: invalid), evidence(.scan, nil, source: invalid),
                       evidence(.scan, nil, subject: invalid)] {
            #expect(throws: AssetDateEvidenceError.invalidIdentifier) { try summary([record]) }
        }
    }
    let boundary = String(repeating: "é", count: 512)
    #expect(try summary([evidence(.confirmedUse, 100, id: boundary, source: boundary, subject: boundary)],
                        subject: boundary).lastUsed == date(100))
}

@Test func datePolicyBoundsInputBeforeDeduplication() throws {
    let record = evidence(.confirmedUse, 100)
    #expect(try summary(Array(repeating: record, count: 10_000)).lastUsed == date(100))
    #expect(throws: AssetDateEvidenceError.tooManyRecords) { try summary(Array(repeating: record, count: 10_001)) }
}
