import Foundation
import CryptoKit

/// A Cubase Usage Logger plugin instance that survived a complete project load.
/// Add records are candidates only; callers must use `CubaseUsageLog.parse` results.
public struct CubasePluginUse: Codable, Sendable, Equatable {
    public static let sourceID = "steinberg.cubase.usage-log.v1"
    public let name: String
    public let vendor: String
    public let version: String
    public let architecture: String
    public let eventID: String
    public let projectID: String
    public let reportedMilliseconds: Int64

    public var reportedDate: Date { Date(timeIntervalSince1970: Double(reportedMilliseconds) / 1_000) }
}

/// Bounded, fail-closed parser for Cubase's local JSONL Usage Logger output.
/// A project contributes only after activation and `Project Status: Load` reports
/// `kErrorNone`; rescan and activation-only records contribute nothing.
public enum CubaseUsageLog {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumLines = 100_000

    private struct Record: Decodable {
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
        let status: String?
        enum CodingKeys: String, CodingKey {
            case type = "smtg_type", report = "smtg_report_name", time = "smtg_time",
                 event = "smtg_event_uid", instance = "smtg_instance_uid",
                 project = "smtg_project_uid", name = "Name", vendor = "Vendor", version = "Version",
                 architecture = "Architecture", status = "Status Code"
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
        var output: [CubasePluginUse] = []; var candidates: [Candidate] = []
        var projectID = "", activated = false, instance = ""; var lines = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lines += 1; guard lines <= maximumLines, raw.utf8.count <= 256 * 1024 else { throw AssetDateEvidenceError.tooManyRecords }
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(raw.utf8)), let time = record.time else { continue }
            if record.type == "instance_begin" { instance = record.instance ?? ""; candidates.removeAll(); projectID = ""; activated = false; continue }
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
        return output
    }
}
