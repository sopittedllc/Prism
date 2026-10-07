import Foundation
import CryptoKit

/// Classification supplied by a qualified source adapter, not inferred by the reducer.
/// Music-app attempts and failures qualify for Last Used; they do not assert successful use.
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

/// Exact installed Kontakt library membership in a saved project snapshot.
/// The event date is the file's save time, not a Kontakt load time.
public struct ProjectLibraryMembership: Codable, Sendable, Equatable {
    public static let sourceID = "saved-project.kontakt-library.v1"
    public static let spectrasonicsSourceID = "saved-project.spectrasonics-library.v1"
    public let adapter: String
    public let publicLibraryID: String
    public let projectSHA256: String
    public let projectPathSHA256: String
    /// Present only for exact Spectrasonics preset-catalog membership.
    public let player: String?
    public let presetName: String?

    public init(adapter: String, publicLibraryID: String, projectSHA256: String,
                projectPathSHA256: String, player: String? = nil, presetName: String? = nil) {
        self.adapter = adapter; self.publicLibraryID = publicLibraryID
        self.projectSHA256 = projectSHA256; self.projectPathSHA256 = projectPathSHA256
        self.player = player; self.presetName = presetName
    }

    public var eventSourceID: String { player == nil ? Self.sourceID : Self.spectrasonicsSourceID }

    public func eventID(subjectID: String, savedAt: Date) throws -> String {
        var fields = [eventSourceID, subjectID, adapter, publicLibraryID,
                      projectSHA256, projectPathSHA256, String(savedAt.timeIntervalSince1970)]
        if let player { fields += [player, presetName ?? ""] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(fields)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Exact installed item in one validated saved project snapshot. Source identity
/// is a host class ID, current physical sample signature, or SINE instrument ID.
public struct ProjectItemMembership: Codable, Sendable, Equatable {
    public static let sourceID = "saved-project.exact-item.v1"
    public let adapter: String
    public let subjectKind: AssetKind
    public let sourceIdentity: String
    public let projectSHA256: String
    public let projectPathSHA256: String

    public func eventID(subjectID: String, savedAt: Date) throws -> String {
        let fields = [Self.sourceID, subjectID, adapter, subjectKind.rawValue, sourceIdentity,
                      projectSHA256, projectPathSHA256, String(savedAt.timeIntervalSince1970)]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(fields)).map { String(format: "%02x", $0) }.joined()
    }
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
    public let itemAccess: ItemAccessProvenance?
    public let hostUsage: HostUsageProvenance?
    public let cubaseUsage: CubasePluginUse?
    public let proToolsUsage: ProToolsPluginUse?
    public let logicUsage: LogicPluginUse?
    public let projectMembership: ProjectLibraryMembership?
    public let projectItemMembership: ProjectItemMembership?

    public init(sourceID: String, evidenceID: String, subjectID: String,
                kind: AssetDateEvidenceKind, eventDate: Date?, ingestedAt: Date,
                packageReceipt: PackageReceiptProvenance? = nil, itemAccess: ItemAccessProvenance? = nil,
                hostUsage: HostUsageProvenance? = nil,
                cubaseUsage: CubasePluginUse? = nil, proToolsUsage: ProToolsPluginUse? = nil,
                logicUsage: LogicPluginUse? = nil, projectMembership: ProjectLibraryMembership? = nil,
                projectItemMembership: ProjectItemMembership? = nil) {
        self.sourceID = sourceID; self.evidenceID = evidenceID; self.subjectID = subjectID
        self.kind = kind; self.eventDate = eventDate; self.ingestedAt = ingestedAt
        self.packageReceipt = packageReceipt; self.itemAccess = itemAccess
        self.hostUsage = hostUsage; self.cubaseUsage = cubaseUsage; self.proToolsUsage = proToolsUsage; self.logicUsage = logicUsage
        self.projectMembership = projectMembership
        self.projectItemMembership = projectItemMembership
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceID.utf8.elementsEqual(rhs.sourceID.utf8)
            && lhs.evidenceID.utf8.elementsEqual(rhs.evidenceID.utf8)
            && lhs.subjectID.utf8.elementsEqual(rhs.subjectID.utf8)
            && lhs.kind == rhs.kind && lhs.eventDate == rhs.eventDate
            && lhs.ingestedAt == rhs.ingestedAt && lhs.packageReceipt == rhs.packageReceipt && lhs.itemAccess == rhs.itemAccess
            && lhs.hostUsage == rhs.hostUsage && lhs.cubaseUsage == rhs.cubaseUsage && lhs.proToolsUsage == rhs.proToolsUsage && lhs.logicUsage == rhs.logicUsage
            && lhs.projectMembership == rhs.projectMembership && lhs.projectItemMembership == rhs.projectItemMembership
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

/// Exact item-level activity admitted by a validated music-app source. The collector must
/// bind the event to one catalog item before creating this record; identity is never inferred
/// from a player, display name, project modification date, or shared sample container.
public struct ItemAccessProvenance: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case attempted, failed, opened, loaded }
    public enum AppFamily: String, Codable, Sendable { case abletonLive, logicPro, cubase, proTools, reaper, standaloneSampler }
    public static let sourceID = "music-app.item-access.v1"
    public let appFamily: AppFamily
    public let appVersion: String
    public let processBundleIdentifier: String
    public let outcome: Outcome
    /// Stable source event identity; must not contain a private path or project name.
    public let eventToken: String

    init(appFamily: AppFamily, appVersion: String, processBundleIdentifier: String,
         outcome: Outcome, eventToken: String) {
        self.appFamily = appFamily; self.appVersion = appVersion
        self.processBundleIdentifier = processBundleIdentifier; self.outcome = outcome
        self.eventToken = eventToken
    }

    public var evidenceKind: AssetDateEvidenceKind {
        switch outcome {
        case .attempted: .loadAttempt
        case .failed: .failedLoad
        case .opened, .loaded: .confirmedUse
        }
    }

    public func eventID(subjectID: String) throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode([Self.sourceID, subjectID, appFamily.rawValue,
                                        processBundleIdentifier, eventToken, outcome.rawValue])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public func validate() throws {
        try AssetDateResolver.validateIdentifier(appVersion, limit: 128)
        try AssetDateResolver.validateIdentifier(processBundleIdentifier, limit: 255)
        try AssetDateResolver.validateIdentifier(eventToken, limit: 512)
        let lowerBundle = processBundleIdentifier.lowercased()
        let trusted: Bool
        switch appFamily {
        case .abletonLive: trusted = lowerBundle == "com.ableton.live"
        case .logicPro: trusted = lowerBundle == "com.apple.logic10"
        case .cubase: trusted = lowerBundle.range(of: #"^com\.steinberg\.cubase[0-9]*$"#, options: .regularExpression) != nil
        case .proTools: trusted = lowerBundle == "com.avid.protools"
        case .reaper: trusted = lowerBundle == "com.cockos.reaper"
        case .standaloneSampler: trusted = ["com.native-instruments.kontakt", "com.native-instruments.kontakt8"].contains(lowerBundle)
        }
        let parts = processBundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard trusted, !eventToken.contains("/"), !eventToken.contains("\\"),
              parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        } }) else { throw AssetDateEvidenceError.invalidProvenance }
    }
}

/// Stable catalog subject identity for file assets and exact library instruments.
/// Instrument identity is scoped to its owning library; matching a vendor ID in a
/// different library never merges histories.
public enum AssetUsageSubject {
    public static func assetID(_ asset: Asset) -> String? {
        guard asset.kind != .plugin else { return asset.catalogID }
        return asset.catalogID
    }
    public static func instrumentIdentityKey(_ instrument: LibraryInstrument) -> String {
        instrument.vendorID.map { "vendor:" + $0 } ?? "path:" + instrument.path
    }
    /// Projection key keeps an exact instrument's history scoped to its owning library.
    /// This is intentionally a cheap composite string; it is not persisted identity.
    public static func instrumentUsageKey(parentNodeID: String, instrument: LibraryInstrument) -> String {
        instrumentUsageKey(parentNodeID: parentNodeID, identityKey: instrumentIdentityKey(instrument))
    }
    static func instrumentUsageKey(parentNodeID: String, identityKey: String) -> String {
        parentNodeID + "\0" + identityKey
    }
    public static func instrumentID(parentNodeID: String, instrument: LibraryInstrument) -> String {
        instrumentID(parentNodeID: parentNodeID, identityKey: instrumentIdentityKey(instrument))
    }
    static func instrumentID(parentNodeID: String, identityKey: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = (try? encoder.encode(["library-instrument", parentNodeID, identityKey])) ?? Data()
        return "instrument:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
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
            let itemAccessSource = record.sourceID.utf8.elementsEqual(ItemAccessProvenance.sourceID.utf8)
            let usageSource = record.sourceID.utf8.elementsEqual(HostUsageProvenance.sourceID.utf8) ||
                record.sourceID.utf8.elementsEqual(HostUsageProvenance.manualCreateSourceID.utf8)
            let cubaseSource = record.sourceID.utf8.elementsEqual(CubasePluginUse.sourceID.utf8)
            let proToolsSource = record.sourceID.utf8.elementsEqual(ProToolsPluginUse.sourceID.utf8) ||
                record.sourceID.utf8.elementsEqual(ProToolsPluginUse.restoreV2SourceID.utf8) ||
                record.sourceID.utf8.elementsEqual(ProToolsPluginUse.attemptedSourceID.utf8)
            let logicSource = record.sourceID.utf8.elementsEqual(LogicPluginUse.sourceID.utf8)
            let projectSource = [ProjectLibraryMembership.sourceID, ProjectLibraryMembership.spectrasonicsSourceID]
                .contains { record.sourceID.utf8.elementsEqual($0.utf8) }
            let projectItemSource = record.sourceID.utf8.elementsEqual(ProjectItemMembership.sourceID.utf8)
            guard itemAccessSource == (record.itemAccess != nil),
                  usageSource == (record.hostUsage != nil), cubaseSource == (record.cubaseUsage != nil),
                  proToolsSource == (record.proToolsUsage != nil), logicSource == (record.logicUsage != nil),
                  projectSource == (record.projectMembership != nil),
                  projectItemSource == (record.projectItemMembership != nil),
                  [record.itemAccess != nil, record.hostUsage != nil, record.cubaseUsage != nil, record.proToolsUsage != nil, record.logicUsage != nil].filter({ $0 }).count <= 1 else { throw AssetDateEvidenceError.invalidProvenance }
            if let membership = record.projectMembership {
                guard record.kind == .projectReference, let savedAt = record.eventDate,
                      record.evidenceID == (try membership.eventID(subjectID: record.subjectID, savedAt: savedAt)),
                      record.sourceID == membership.eventSourceID,
                      [membership.projectSHA256, membership.projectPathSHA256].allSatisfy({
                          $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                      }), membership.player == nil
                        ? (LibraryMetadataReader.validKontaktSNPID(membership.publicLibraryID) && membership.presetName == nil &&
                           ["cubase-kontakt-15.0.30", "ableton-kontakt-live12", "logic-saved-au"].contains(membership.adapter))
                        : (["Omnisphere", "Keyscape", "Trilian"].contains(membership.player ?? "") &&
                           membership.adapter == "cubase-spectrasonics-15.0.30" &&
                           membership.publicLibraryID.hasPrefix("spectrasonics:") &&
                           !(membership.presetName ?? "").isEmpty) else {
                    throw AssetDateEvidenceError.invalidProvenance
                }
            }
            if let membership = record.projectItemMembership {
                guard record.kind == .projectReference, let savedAt = record.eventDate,
                      record.evidenceID == (try membership.eventID(subjectID: record.subjectID, savedAt: savedAt)),
                      !membership.sourceIdentity.isEmpty, membership.sourceIdentity.utf8.count <= 1_024,
                      [membership.projectSHA256, membership.projectPathSHA256].allSatisfy({
                          $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                      }),
                      (membership.subjectKind == .plugin && ["ableton-vst3-live12", "cubase-vst3-15.0.30", "protools-ptx-aax", "logic-saved-au"].contains(membership.adapter)) ||
                      (membership.subjectKind == .sample && ["reaper-rpp", "ableton-sample-live12"].contains(membership.adapter)) ||
                      (membership.subjectKind == .library && membership.adapter == "cubase-sine-15.0.30") else {
                    throw AssetDateEvidenceError.invalidProvenance
                }
            }
            if let itemAccess = record.itemAccess {
                guard record.kind == itemAccess.evidenceKind, record.eventDate != nil,
                      record.evidenceID == (try itemAccess.eventID(subjectID: record.subjectID)) else {
                    throw AssetDateEvidenceError.invalidProvenance
                }
                try itemAccess.validate()
            }
            if let usage = record.hostUsage {
                guard record.kind == .confirmedUse, record.eventDate == nil, record.packageReceipt == nil,
                      record.sourceID.utf8.elementsEqual(usage.eventSourceID.utf8),
                      record.evidenceID == (try usage.eventID(subjectID: record.subjectID)) else { throw AssetDateEvidenceError.invalidProvenance }
                try usage.validate()
            }
            if let cubase = record.cubaseUsage {
                guard (cubase.qualification == nil || cubase.qualification == "nativeAddAttempt"),
                      record.kind == cubase.evidenceKind, record.eventDate == cubase.reportedDate,
                      record.packageReceipt == nil, record.hostUsage == nil,
                      record.evidenceID == cubase.eventID else { throw AssetDateEvidenceError.invalidProvenance }
            }
            if let proTools = record.proToolsUsage {
                guard record.kind == (proTools.eventSourceID == ProToolsPluginUse.attemptedSourceID ? .loadAttempt : .confirmedUse),
                      record.packageReceipt == nil, record.hostUsage == nil, record.cubaseUsage == nil,
                      record.sourceID.utf8.elementsEqual(proTools.eventSourceID.utf8) else {
                    throw AssetDateEvidenceError.invalidProvenance
                }
                if record.sourceID == ProToolsPluginUse.restoreV2SourceID || record.sourceID == ProToolsPluginUse.attemptedSourceID {
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
            case .loadAttempt, .failedLoad:
                if record.itemAccess != nil || record.cubaseUsage != nil {
                    lastUsed = max(lastUsed ?? date, date)
                }
            case .confirmedAddition: dateAdded = min(dateAdded ?? date, date)
            case .installationRecord: installed = max(installed ?? date, date)
            case .discovery: discovered = min(discovered ?? date, date)
            case .projectReference:
                referenced = max(referenced ?? date, date)
                if record.projectMembership != nil || record.projectItemMembership != nil { lastUsed = max(lastUsed ?? date, date) }
            case .scan, .mappedInHost: break
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
