import Foundation
import CryptoKit

/// The empirically qualified Cubase Pro 15.0.5.121 saved-restore grammar.
/// State is local to a single parse call and all output is returned atomically.
struct NativeCubaseUsageReader {
    private struct Candidate: Equatable {
        let name: String
        let vendor: String
        let version: String
        let architecture: String
        let reportUID: String
        let time: Int64
    }
    private struct Group {
        let name: String
        let uid: Int64
        let time: Int64
        var fields: [String: String] = [:]
        var children = 0
        var invalid = false
    }

    private let instance: String
    private var project = ""
    private var activated = false
    private var candidates: [Candidate] = []
    private var group: Group?
    private var previousTime: Int64?
    private var seenReports: [Int64: Candidate] = [:]
    private var emitted: [String: CubasePluginUse] = [:]

    init(instance: String = "") { self.instance = instance }

    mutating func consume(record: CubaseUsageLog.Record, into output: inout [CubasePluginUse]) throws {
        guard let time = record.time, time >= 0, time <= 253_402_300_799_999 else {
            throw AssetDateEvidenceError.invalidProvenance
        }
        if (record.instance?.utf8.count ?? 0) > 256 || (record.project?.utf8.count ?? 0) > 256 {
            throw AssetDateEvidenceError.tooManyRecords
        }
        if let previousTime, time < previousTime { cancel() }
        previousTime = time
        guard record.instance == instance else {
            group?.invalid = true
            try finishGroup(into: &output)
            cancel()
            return
        }
        if record.type == "report", record.report == nil {
            guard var current = group else { return }
            current.children += 1
            guard current.children <= 8 else { throw AssetDateEvidenceError.tooManyRecords }
            guard let key = record.reportKey, let value = record.stringValue else {
                current.invalid = true
                group = current
                return
            }
            guard key.utf8.count <= 1_024, value.utf8.count <= 1_024 else {
                throw AssetDateEvidenceError.tooManyRecords
            }
            if record.reportUID != current.uid || time != current.time ||
                current.fields.updateValue(value, forKey: key) != nil {
                current.invalid = true
            }
            group = current
            return
        }
        if record.type == "report", let current = group,
           record.reportUID == current.uid {
            // A second header under the same UID is part of the malformed group,
            // not evidence that the preceding children were complete.
            group?.invalid = true
            return
        }
        try finishGroup(into: &output)
        switch record.type {
        case "project_added":
            cancel()
            if CubaseUsageLog.validUID(record.project) { project = record.project! }
        case "project_activated":
            if record.project == project && !project.isEmpty { activated = true }
            else { cancel() }
        case "project_removed", "project_deactivated", "instance_end":
            cancel()
        case "report":
            guard let name = record.report,
                  ["Plugin Instance Info: VST - Add", "Plugin Instance Info: VST - Remove", "Project Status: Load"].contains(name) else { return }
            guard let uid = record.reportUID, uid >= 0, record.reportKey == nil else {
                if name == "Project Status: Load" { cancel() }
                return
            }
            group = Group(name: name, uid: uid, time: time)
        default: break
        }
    }

    mutating func finish(into output: inout [CubasePluginUse]) throws {
        try finishGroup(into: &output)
    }

    private mutating func finishGroup(into output: inout [CubasePluginUse]) throws {
        guard let current = group else { return }
        group = nil
        let fields = current.fields
        if current.name == "Project Status: Load" {
            defer { cancel() }
            guard !current.invalid, current.children == 3,
                  Set(fields.keys) == Set(["Status Code", "File Size", "Persistence Time"]),
                  fields["Status Code"] == "kErrorNone", activated, !project.isEmpty else { return }
            for candidate in candidates {
                let id = eventID(project: project, reportUID: candidate.reportUID)
                let use = CubasePluginUse(name: candidate.name, vendor: candidate.vendor,
                    version: candidate.version, architecture: candidate.architecture,
                    eventID: id, projectID: project, reportedMilliseconds: candidate.time)
                if let earlier = emitted[id] {
                    guard earlier == use else { throw AssetDateEvidenceError.conflictingEvidenceID }
                } else {
                    emitted[id] = use
                    output.append(use)
                }
            }
            return
        }
        let keys = Set(["Name", "Vendor", "Type", "Version", "Architecture"])
        guard !current.invalid, current.children == 5, Set(fields.keys) == keys,
              fields["Type"] == "Audio Module Class",
              let name = fields["Name"], !name.isEmpty,
              let vendor = fields["Vendor"], !vendor.isEmpty,
              let version = fields["Version"], !version.isEmpty,
              let architecture = fields["Architecture"], !architecture.isEmpty else {
            if current.name == "Plugin Instance Info: VST - Remove" { candidates.removeAll() }
            return
        }
        let candidate = Candidate(name: name, vendor: vendor, version: version,
                                  architecture: architecture, reportUID: String(current.uid), time: current.time)
        if current.name == "Plugin Instance Info: VST - Remove" {
            let matches = candidates.indices.filter {
                candidates[$0].name == name && candidates[$0].vendor == vendor &&
                candidates[$0].version == version && candidates[$0].architecture == architecture
            }
            if matches.count == 1 { candidates.remove(at: matches[0]) }
            else { candidates.removeAll() }
            return
        }
        if let earlier = seenReports[current.uid] {
            guard earlier == candidate else { throw AssetDateEvidenceError.conflictingEvidenceID }
            return
        }
        seenReports[current.uid] = candidate
        guard !project.isEmpty, !activated else { return }
        guard candidates.count < 4_096 else { throw AssetDateEvidenceError.tooManyRecords }
        candidates.append(candidate)
    }

    private mutating func cancel() {
        project = ""
        activated = false
        candidates.removeAll()
    }

    private func eventID(project: String, reportUID: String) -> String {
        let components = ["native-restore-v1", instance, project, reportUID]
        var material = Data()
        for component in components {
            let bytes = Data(component.utf8)
            var size = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &size) { material.append(contentsOf: $0) }
            material.append(bytes)
        }
        return SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
    }
}
