import Foundation
import CryptoKit

/// Classification supplied by a qualified source adapter, not inferred by the reducer.
/// A host load message alone is a loadAttempt until successful use is established.
public enum AssetDateEvidenceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case confirmedUse = "confirmedUse"
    case confirmedAddition = "confirmedAddition"
    case installationRecord = "installationRecord"
    case discovery = "discovery"
    case projectReference = "projectReference"
    case loadAttempt = "loadAttempt"
    case failedLoad = "failedLoad"
    case scan = "scan"
    case mappedInHost = "mappedInHost"
}

/// Historical receipt provenance, private to the local catalog and its backups.
/// Versions retain reader order: short version, then bundle version (including duplicates).
public struct PackageReceiptProvenance: Codable, Sendable, Equatable {
    public static let sourceID = "macos.pkgutil.receipt.v1"
    public let packageID: String
    public let packageVersion: String
    public let bundlePath: String
    public let bundleIdentifier: String
    public let bundleVersions: [String]

    public init(packageID: String, packageVersion: String, bundlePath: String,
                bundleIdentifier: String, bundleVersions: [String]) {
        self.packageID = packageID; self.packageVersion = packageVersion
        self.bundlePath = bundlePath; self.bundleIdentifier = bundleIdentifier
        self.bundleVersions = bundleVersions
    }
    private var bytes: [Data] {
        ([packageID, packageVersion, bundlePath, bundleIdentifier] + bundleVersions).map { Data($0.utf8) }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }

    // Versioned canonical identity excludes observation and ingestion clocks.
    func eventID(subjectID: String, date: Date) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        let fields = [subjectID, packageID, packageVersion, String(date.timeIntervalSince1970),
                      bundlePath, bundleIdentifier] + bundleVersions
        return SHA256.hash(data: try encoder.encode(fields)).map { String(format: "%02x", $0) }.joined()
    }
    func validate() throws {
        guard (1...2).contains(bundleVersions.count) else { throw AssetDateEvidenceError.invalidProvenance }
        for value in [packageID, packageVersion, bundleIdentifier] + bundleVersions {
            try AssetDateResolver.validateIdentifier(value)
        }
        try AssetDateResolver.validateIdentifier(bundlePath, limit: 4_096)
        guard (1...2).contains(bundleVersions.count),
              bundleVersions.contains(where: { $0.utf8.elementsEqual(packageVersion.utf8) }) else {
            throw AssetDateEvidenceError.invalidProvenance
        }
    }
}

/// Immutable evidence for one exact subject (product, installation, sample or instrument).
/// IDs are opaque UTF-8 bytes. Adapters own identity resolution and evidence qualification;
/// no player-to-library, format-to-product or path/name-based association is inferred here.
public struct AssetDateEvidence: Codable, Sendable, Equatable {
    public let sourceID: String
    public let evidenceID: String
    public let subjectID: String
    public let kind: AssetDateEvidenceKind
    /// Qualified event wall-clock time, or nil when unknown. Never an ingestion fallback.
    public let eventDate: Date?
    /// First ingestion of this immutable record. Replays must retain this value.
    public let ingestedAt: Date
    public let packageReceipt: PackageReceiptProvenance?
    public let hostUsage: HostUsageProvenance?
    public let cubaseUsage: CubasePluginUse?
    public let proToolsUsage: ProToolsPluginUse?
    public let logicUsage: LogicPluginUse?

    public init(sourceID: String, evidenceID: String, subjectID: String,
                kind: AssetDateEvidenceKind, eventDate: Date?, ingestedAt: Date,
                packageReceipt: PackageReceiptProvenance? = nil, hostUsage: HostUsageProvenance? = nil,
                cubaseUsage: CubasePluginUse? = nil, proToolsUsage: ProToolsPluginUse? = nil,
                logicUsage: LogicPluginUse? = nil) {
        self.sourceID = sourceID; self.evidenceID = evidenceID; self.subjectID = subjectID
        self.kind = kind; self.eventDate = eventDate; self.ingestedAt = ingestedAt
        self.packageReceipt = packageReceipt; self.hostUsage = hostUsage; self.cubaseUsage = cubaseUsage; self.proToolsUsage = proToolsUsage; self.logicUsage = logicUsage
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceID.utf8.elementsEqual(rhs.sourceID.utf8)
            && lhs.evidenceID.utf8.elementsEqual(rhs.evidenceID.utf8)
            && lhs.subjectID.utf8.elementsEqual(rhs.subjectID.utf8)
            && lhs.kind == rhs.kind && lhs.eventDate == rhs.eventDate
            && lhs.ingestedAt == rhs.ingestedAt && lhs.packageReceipt == rhs.packageReceipt && lhs.hostUsage == rhs.hostUsage && lhs.cubaseUsage == rhs.cubaseUsage && lhs.proToolsUsage == rhs.proToolsUsage && lhs.logicUsage == rhs.logicUsage
    }
}

/// Independent dates; nil means no qualifying, dated evidence in the supplied set.
/// Saved references alone do not establish a dated successful instantiation.
public struct AssetDateSummary: Sendable, Equatable {
    public let lastUsed: Date?
    public let dateAdded: Date?
    public let latestRecordedInstallation: Date?
    public let firstDiscovered: Date?
    public let latestProjectReference: Date?
}

public enum AssetDateEvidenceError: Error, Sendable, Equatable {
    case tooManyRecords, invalidIdentifier, nonFiniteDate, futureIngestion
    case eventAfterIngestion, conflictingEvidenceID, invalidProvenance
}

/// Pure, synchronous policy over a complete retained evidence set. No I/O or clock reads.
/// Call outside real-time audio callbacks. O(n) bounded records; nothing persists between
/// calls. Sources must reconcile corrections/clock uncertainty before submitting records.
public enum AssetDateResolver {
    public static let maximumRecords = 10_000
    public static let maximumIdentifierBytes = 1_024

    /// Validates the entire batch before summarizing one byte-exact subject. Equal replay
    /// records are idempotent; contradictory source-scoped IDs reject the entire batch.
    /// Ingestion must not exceed asOf; dated events must not exceed their ingestion time.
    /// Unknown event dates never use ingestion time. Invalid input throws without output.
    public static func summarize(_ records: [AssetDateEvidence], for subjectID: String,
                                 asOf: Date) throws -> AssetDateSummary {
        guard records.count <= maximumRecords else { throw AssetDateEvidenceError.tooManyRecords }
        try validateIdentifier(subjectID)
        try validateDate(asOf)
        var seen: [EvidenceKey: AssetDateEvidence] = [:]
        for record in records {
            try validateIdentifier(record.sourceID)
            try validateIdentifier(record.evidenceID)
            try validateIdentifier(record.subjectID)
            try validateDate(record.ingestedAt)
            guard record.ingestedAt <= asOf else { throw AssetDateEvidenceError.futureIngestion }
            if let date = record.eventDate {
                try validateDate(date)
                guard date <= record.ingestedAt else { throw AssetDateEvidenceError.eventAfterIngestion }
            }
            let receiptSource = record.sourceID.utf8.elementsEqual(PackageReceiptProvenance.sourceID.utf8)
            guard receiptSource == (record.packageReceipt != nil) else { throw AssetDateEvidenceError.invalidProvenance }
            if let provenance = record.packageReceipt {
                guard record.kind == .installationRecord, let date = record.eventDate,
                      date.timeIntervalSince1970 > 0,
                      date.timeIntervalSince1970.rounded(.towardZero) == date.timeIntervalSince1970 else {
                    throw AssetDateEvidenceError.invalidProvenance
                }
                try provenance.validate()
            }
            let usageSource = record.sourceID.utf8.elementsEqual(HostUsageProvenance.sourceID.utf8) ||
                record.sourceID.utf8.elementsEqual(HostUsageProvenance.manualCreateSourceID.utf8)
            let cubaseSource = record.sourceID.utf8.elementsEqual(CubasePluginUse.sourceID.utf8)
            let proToolsSource = record.sourceID.utf8.elementsEqual(ProToolsPluginUse.sourceID.utf8) ||
                record.sourceID.utf8.elementsEqual(ProToolsPluginUse.restoreV2SourceID.utf8)
            let logicSource = record.sourceID.utf8.elementsEqual(LogicPluginUse.sourceID.utf8)
            guard usageSource == (record.hostUsage != nil), cubaseSource == (record.cubaseUsage != nil),
                  proToolsSource == (record.proToolsUsage != nil), logicSource == (record.logicUsage != nil),
                  [record.hostUsage != nil, record.cubaseUsage != nil, record.proToolsUsage != nil, record.logicUsage != nil].filter({ $0 }).count <= 1 else { throw AssetDateEvidenceError.invalidProvenance }
            if let usage = record.hostUsage {
                guard record.kind == .confirmedUse, record.eventDate == nil, record.packageReceipt == nil,
                      record.sourceID.utf8.elementsEqual(usage.eventSourceID.utf8),
                      record.evidenceID == (try usage.eventID(subjectID: record.subjectID)) else { throw AssetDateEvidenceError.invalidProvenance }
                try usage.validate()
            }
            if let cubase = record.cubaseUsage {
                guard record.kind == .confirmedUse, record.eventDate == cubase.reportedDate,
                      record.packageReceipt == nil, record.hostUsage == nil,
                      record.evidenceID == cubase.eventID else { throw AssetDateEvidenceError.invalidProvenance }
            }
            if let proTools = record.proToolsUsage {
                guard record.kind == .confirmedUse,
                      record.packageReceipt == nil, record.hostUsage == nil, record.cubaseUsage == nil,
                      record.sourceID.utf8.elementsEqual(proTools.eventSourceID.utf8) else {
                    throw AssetDateEvidenceError.invalidProvenance
                }
                if record.sourceID == ProToolsPluginUse.restoreV2SourceID {
                    guard record.eventDate == nil,
                          record.evidenceID == proTools.subjectEventID(record.subjectID) else {
                        throw AssetDateEvidenceError.invalidProvenance
                    }
                    try proTools.validateV2()
                } else {
                    // Historical v1 remains decodable, but its inferred Date is invalid.
                    guard record.eventDate == proTools.reportedDate,
                          record.evidenceID == proTools.eventID else {
                        throw AssetDateEvidenceError.invalidProvenance
                    }
                }
            }
            if let logic = record.logicUsage {
                guard record.kind == .confirmedUse, record.eventDate == logic.reportedDate,
                      record.packageReceipt == nil, record.hostUsage == nil, record.cubaseUsage == nil, record.proToolsUsage == nil,
                      record.evidenceID == logic.eventID else { throw AssetDateEvidenceError.invalidProvenance }
            }
            let key = EvidenceKey(source: Data(record.sourceID.utf8), id: Data(record.evidenceID.utf8))
            if let previous = seen[key], previous != record {
                throw AssetDateEvidenceError.conflictingEvidenceID
            }
            seen[key] = record
        }

        var lastUsed: Date?, dateAdded: Date?, installed: Date?, discovered: Date?, referenced: Date?
        for record in seen.values where record.subjectID.utf8.elementsEqual(subjectID.utf8) {
            guard let date = record.eventDate else { continue }
            switch record.kind {
            case .confirmedUse:
                if record.sourceID != ProToolsPluginUse.sourceID {
                    lastUsed = max(lastUsed ?? date, date)
                }
            case .confirmedAddition: dateAdded = min(dateAdded ?? date, date)
            case .installationRecord: installed = max(installed ?? date, date)
            case .discovery: discovered = min(discovered ?? date, date)
            case .projectReference: referenced = max(referenced ?? date, date)
            case .loadAttempt, .failedLoad, .scan, .mappedInHost: break
            }
        }
        return AssetDateSummary(lastUsed: lastUsed, dateAdded: dateAdded,
                                latestRecordedInstallation: installed, firstDiscovered: discovered,
                                latestProjectReference: referenced)
    }

    private struct EvidenceKey: Hashable {
        let source: Data
        let id: Data
    }

    static func validateIdentifier(_ value: String, limit: Int = maximumIdentifierBytes) throws {
        guard value.utf8.prefix(limit + 1).count <= limit,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AssetDateEvidenceError.invalidIdentifier
        }
    }

    private static func validateDate(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw AssetDateEvidenceError.nonFiniteDate }
    }
}
