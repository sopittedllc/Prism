import Foundation
import CryptoKit

/// A Cubase Usage Logger plugin event. Older records describe completed restores;
/// a qualified native Add is an attempted instantiation at its original host time.
public struct CubasePluginUse: Codable, Sendable, Equatable {
    public static let sourceID = "steinberg.cubase.usage-log.v1"
    public let name: String
    public let vendor: String
    public let version: String
    public let architecture: String
    public let eventID: String
    public let projectID: String
    public let reportedMilliseconds: Int64
    public let qualification: String?

    public init(name: String, vendor: String, version: String, architecture: String,
                eventID: String, projectID: String, reportedMilliseconds: Int64,
                qualification: String? = nil) {
        self.name = name; self.vendor = vendor; self.version = version; self.architecture = architecture
        self.eventID = eventID; self.projectID = projectID; self.reportedMilliseconds = reportedMilliseconds
        self.qualification = qualification
    }

    public var evidenceKind: AssetDateEvidenceKind { qualification == "nativeAddAttempt" ? .loadAttempt : .confirmedUse }
    public func isSameHostEvent(as other: Self) -> Bool {
        name == other.name && vendor == other.vendor && version == other.version &&
        architecture == other.architecture && eventID == other.eventID &&
        projectID == other.projectID && reportedMilliseconds == other.reportedMilliseconds
    }

    public var reportedDate: Date { Date(timeIntervalSince1970: Double(reportedMilliseconds) / 1_000) }
}

/// Bounded, fail-closed parser for Cubase's local JSONL Usage Logger output.
    /// Cubase 15.0.30 native Add reports contribute attempted instantiation at
    /// their own host time. Older grammars retain completed-load qualification.
public enum CubaseUsageLog {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumLines = 100_000

    struct Record: Decodable {
        let type: String?
        let report: String?
        let time: Int64?
        let event: String?
        let instance: String?
        let project: String?
        let name: String?
        let vendor: String?
        let version: String?
        let architecture: String?
        let classType: String?
        let status: String?
        let productName: String?
        let productVersion: String?
        let reportUID: Int64?
        let reportKey: String?
        let stringValue: String?
        enum CodingKeys: String, CodingKey {
            case type = "smtg_type", report = "smtg_report_name", time = "smtg_time",
                 event = "smtg_event_uid", instance = "smtg_instance_uid",
                 project = "smtg_project_uid", name = "Name", vendor = "Vendor", version = "Version",
                 architecture = "Architecture", classType = "Type", status = "Status Code",
                 productName = "smtg_product_name", productVersion = "smtg_product_version",
                 reportUID = "smtg_report_uid", reportKey = "smtg_report_key", stringValue = "smtg_string"
        }
    }
    private struct Candidate {
        let name: String; let vendor: String; let version: String; let architecture: String
        let event: String; let time: Int64
    }
    public static func parse(_ data: Data) throws -> [CubasePluginUse] {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8), !data.contains(0) else {
            throw AssetDateEvidenceError.invalidProvenance
        }
        var output: [CubasePluginUse] = [], nativeOutput: [CubasePluginUse] = []; var candidates: [Candidate] = []
        var projectID = "", activated = false, instance = ""; var lines = 0
        var native = NativeCubaseUsageReader()
        var nativeMode = false, supportedNative = false, flatNativeMode = false
        var flatSeen: [String: CubasePluginUse] = [:]
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in rawLines.enumerated() {
            if raw.isEmpty && index == rawLines.count - 1 && text.hasSuffix("\n") { break }
            // Native output requires a committed line terminator. Legacy flattened
            // records retain their original valid-final-line behavior.
            if index == rawLines.count - 1 && !text.hasSuffix("\n") && nativeMode { break }
            lines += 1; guard lines <= maximumLines, raw.utf8.count <= 256 * 1024 else { throw AssetDateEvidenceError.tooManyRecords }
            let decoded = try? JSONDecoder().decode(Record.self, from: Data(raw.utf8))
            guard let record = decoded, let time = record.time else {
                if nativeMode && supportedNative { throw AssetDateEvidenceError.invalidProvenance }
                continue
            }
            if record.type == "instance_begin" {
                if nativeMode && supportedNative { try native.finish(into: &nativeOutput) }
                nativeMode = record.productName != nil || record.productVersion != nil
                if record.productName == "Cubase Pro", record.productVersion == "15.0.5.121",
                   let uid = record.instance, uid.utf8.count > 256 {
                    throw AssetDateEvidenceError.tooManyRecords
                }
                supportedNative = nativeMode && record.productName == "Cubase Pro" && record.productVersion == "15.0.5.121"
                    && validUID(record.instance)
                flatNativeMode = nativeMode && record.productName == "Cubase Pro" && record.productVersion == "15.0.30.287"
                    && validUID(record.instance)
                native = NativeCubaseUsageReader(instance: supportedNative ? record.instance! : "")
                instance = record.instance ?? ""; candidates.removeAll(); projectID = ""; activated = false
                continue
            }
            if flatNativeMode {
                guard record.instance == instance, time >= 0, time <= 253_402_300_799_999 else {
                    projectID = ""; continue
                }
                if record.type == "project_added" {
                    projectID = validUID(record.project) ? record.project! : ""
                } else if record.type == "project_removed" || record.type == "project_deactivated" || record.type == "instance_end" {
                    projectID = ""
                } else if record.type == "report", record.report == "Plugin Instance Info: VST - Add",
                          !projectID.isEmpty, record.reportKey == nil,
                          let uid = record.reportUID, uid >= 0,
                          let event = record.event, validUID(event),
                          let name = record.name, !name.isEmpty,
                          let vendor = record.vendor, !vendor.isEmpty,
                          let version = record.version, !version.isEmpty,
                          let architecture = record.architecture, !architecture.isEmpty,
                          record.classType == "Audio Module Class" {
                    let material = ["cubase", instance, projectID, event].joined(separator: "\u{1F}")
                    let id = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
                    let use = CubasePluginUse(name: name, vendor: vendor, version: version,
                        architecture: architecture, eventID: id, projectID: projectID,
                        reportedMilliseconds: time, qualification: "nativeAddAttempt")
                    if let earlier = flatSeen[id] {
                        guard earlier == use else { throw AssetDateEvidenceError.conflictingEvidenceID }
                    } else {
                        flatSeen[id] = use
                        output.append(use)
                    }
                }
                continue
            }
            if nativeMode {
                if supportedNative { try native.consume(record: record, into: &nativeOutput) }
                continue
            }
            if record.type == "project_added" { projectID = record.project ?? record.event ?? ""; candidates.removeAll(); activated = false; continue }
            if record.type == "project_activated" { if !projectID.isEmpty { activated = true }; continue }
            if record.report == "Plugin Instance Info: VST - Add",
               let name = record.name, let vendor = record.vendor, let version = record.version,
               !name.isEmpty, !vendor.isEmpty, !version.isEmpty, let architecture = record.architecture,
               let event = record.event {
                candidates.append(Candidate(name: name, vendor: vendor, version: version, architecture: architecture, event: event, time: time)); continue
            }
            if record.report == "Project Status: Load" {
                guard activated, record.status == "kErrorNone", !projectID.isEmpty else { candidates.removeAll(); activated = false; continue }
                for candidate in candidates {
                    let material = ["cubase", instance, projectID, candidate.event].joined(separator: "\u{1F}" )
                    let id = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
                    output.append(CubasePluginUse(name: candidate.name, vendor: candidate.vendor, version: candidate.version,
                        architecture: candidate.architecture, eventID: id, projectID: projectID,
                        reportedMilliseconds: candidate.time))
                }
                candidates.removeAll(); activated = false
            }
        }
        if nativeMode && supportedNative { try native.finish(into: &nativeOutput) }
        var nativeSeen: [String: CubasePluginUse] = [:]
        for use in nativeOutput {
            if let previous = nativeSeen[use.eventID] {
                guard previous == use else { throw AssetDateEvidenceError.conflictingEvidenceID }
            } else {
                nativeSeen[use.eventID] = use
                output.append(use)
            }
        }
        return output
    }

    static func validUID(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.utf8.count <= 256 else { return false }
        return !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
