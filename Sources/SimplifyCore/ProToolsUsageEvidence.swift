import Foundation
import CryptoKit

public struct ProToolsPluginUse: Codable, Sendable, Equatable {
    /// Retained so historical catalog payloads remain readable, but not authoritative.
    public static let sourceID = "avid.protools.host-restore.v1"
    public static let restoreV2SourceID = "avid.protools.host-restore.v2"
    public let name: String
    public let eventID: String
    public let reportedDate: Date?
    public let sourceSeconds: Double
    public let localTime: SourceLocalTime?
    public let runHash: String?
    public let recordOffset: Int?
    public let recordHash: String?

    public var eventSourceID: String {
        localTime != nil && runHash != nil && recordOffset != nil && recordHash != nil
            ? Self.restoreV2SourceID : Self.sourceID
    }

    init(name: String, sourceSeconds: Double, localTime: SourceLocalTime,
         runHash: String, recordOffset: Int, recordHash: String) {
        self.name = name; self.sourceSeconds = sourceSeconds; self.localTime = localTime
        self.runHash = runHash; self.recordOffset = recordOffset; self.recordHash = recordHash
        self.reportedDate = nil
        self.eventID = Self.digest([runHash, String(recordOffset), recordHash,
                                    localTime.canonical, String(sourceSeconds.bitPattern)])
    }

    func subjectEventID(_ subjectID: String) -> String {
        guard eventSourceID == Self.restoreV2SourceID else { return eventID }
        return Self.digest([eventID, subjectID])
    }

    func validateV2() throws {
        guard let localTime, let runHash, let recordOffset, let recordHash,
              reportedDate == nil, sourceSeconds.isFinite, sourceSeconds >= 0,
              (0...ProToolsUsageLog.maximumBytes).contains(recordOffset),
              [runHash, recordHash, eventID].allSatisfy(Self.isDigest),
              eventID == Self.digest([runHash, String(recordOffset), recordHash,
                                      localTime.canonical, String(sourceSeconds.bitPattern)]) else {
            throw AssetDateEvidenceError.invalidProvenance
        }
        try localTime.validate()
        try AssetDateResolver.validateIdentifier(name, limit: 512)
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func digest(_ fields: [String]) -> String {
        var bytes = Data()
        for field in fields { bytes.append(Data(field.utf8)); bytes.append(0) }
        return digest(bytes)
    }
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Integer-second civil anchors plus fractional monotonic deltas yield a nominal
/// civil second, never a timezone-aware instant or subsecond-precise local time.
/// PutDocumentInfo remains the restore qualification fence; manual use is excluded.
public enum ProToolsUsageLog {
    public static let maximumBytes = 32 * 1024 * 1024
    private static let prefix = try! NSRegularExpression(pattern: #"^([0-9]+\.[0-9]+),"#)
    private static let instance = "InstantiatePlugIn - pluginType: Host, name: \""

    private struct Anchor { let seconds: Double; let local: SourceLocalTime }
    private struct Pending {
        let name: String, seconds: Double, offset: Int, hash: String
        let local: SourceLocalTime
    }

    public static func parse(_ data: Data) throws -> [ProToolsPluginUse] {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8),
              !data.contains(0) else { throw AssetDateEvidenceError.invalidProvenance }
        var pending: [Pending] = [], output: [ProToolsPluginUse] = []
        var traceHeader: String?, runHash: String?, anchor: Anchor?
        var awaitingStart = false
        var clockReliable = true
        var lastEvent: (seconds: Double, local: SourceLocalTime)?
        var byteOffset = 0
        // A growing diagnostic log may end mid-record. Ignore its unfinished tail.
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            let line = String(raw).trimmingCharacters(in: .newlines)
            let lineBytes = Data(raw.utf8)
            defer { byteOffset += lineBytes.count + 1 }
            guard lineBytes.count <= 32_768 else { throw AssetDateEvidenceError.tooManyRecords }
            if line.hasPrefix("*** Digidesign Session Trace for:") {
                traceHeader = line; runHash = nil; anchor = nil; pending.removeAll()
                clockReliable = true; awaitingStart = true; lastEvent = nil
            } else if line.hasPrefix("*** Starting Timestamp:") {
                pending.removeAll(); anchor = nil; clockReliable = true; lastEvent = nil
                runHash = awaitingStart ? traceHeader.map { ProToolsPluginUse.digest([$0, line]) } : nil
                awaitingStart = false
            }
            let ns = NSRange(line.startIndex..., in: line)
            guard let match = prefix.firstMatch(in: line, range: ns),
                  let range = Range(match.range(at: 1), in: line),
                  let seconds = Double(line[range]), seconds.isFinite else { continue }
            if line.contains("Closing session:") || line.contains("Opening session:") {
                pending.removeAll()
            }
            if let marker = line.range(of: "Local wall clock:") {
                let next = parseAnchor(String(line[marker.upperBound...]), seconds: seconds)
                if let anchor, let next {
                    let civilDelta = next.local.sequenceSeconds - anchor.local.sequenceSeconds
                    let monotonicDelta = next.seconds - anchor.seconds
                    if monotonicDelta < 0 || abs(civilDelta - monotonicDelta) > 2 {
                        pending.removeAll(); clockReliable = false
                    }
                } else if next == nil {
                    pending.removeAll(); clockReliable = false
                }
                anchor = next
            }
            // No plugin-instance token exists here; invalidate the entire pending
            // restore batch on a known native instantiation failure indicator.
            if line.contains("kCantInstantiatePlugIn") || line.contains("Could not instantiate") {
                pending.removeAll()
            }
            let completedRestore = line.range(
                of: #": PtSess_RunTime::PutDocumentInfo - session was last saved with app version: [0-9]+\.[0-9]+(\.[0-9]+)?$"#,
                options: .regularExpression) != nil
            if completedRestore {
                if let runHash, clockReliable {
                    for item in pending {
                        output.append(ProToolsPluginUse(name: item.name, sourceSeconds: item.seconds,
                            localTime: item.local, runHash: runHash,
                            recordOffset: item.offset, recordHash: item.hash))
                    }
                }
                pending.removeAll()
                continue
            }
            guard let start = line.range(of: instance), let anchor, runHash != nil,
                  clockReliable else { continue }
            let tail = line[start.upperBound...]
            guard let end = tail.firstIndex(of: "\""), !tail[..<end].isEmpty,
                  let local = localSecond(anchor: anchor, eventSeconds: seconds) else { continue }
            if let lastEvent, seconds < lastEvent.seconds || local < lastEvent.local {
                pending.removeAll(); clockReliable = false
                continue
            }
            lastEvent = (seconds, local)
            pending.append(Pending(name: String(tail[..<end]), seconds: seconds,
                                   offset: byteOffset, hash: ProToolsPluginUse.digest(lineBytes), local: local))
        }
        return output
    }

    private static func parseAnchor(_ raw: String, seconds: Double) -> Anchor? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        // Native output can pad the day: "10/ 3/2026 15:08:24".
        let pattern = #"^([0-9]{1,2})/\s*([0-9]{1,2})/([0-9]{4})\s+([0-9]{2}):([0-9]{2}):([0-9]{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        func part(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }
        guard let month = part(1), let day = part(2), let year = part(3),
              let hour = part(4), let minute = part(5), let second = part(6),
              let local = try? SourceLocalTime(String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000000",
                                                 year, month, day, hour, minute, second)) else { return nil }
        return Anchor(seconds: seconds, local: local)
    }

    private static func localSecond(anchor: Anchor, eventSeconds: Double) -> SourceLocalTime? {
        let delta = eventSeconds - anchor.seconds
        guard delta.isFinite, (0...86_400).contains(delta) else { return nil }
        // The fixed Gregorian UTC calendar is only a civil-arithmetic surrogate.
        // Its Date never becomes a reported event instant.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let origin = DateComponents(year: anchor.local.year, month: anchor.local.month,
                                    day: anchor.local.day, hour: anchor.local.hour,
                                    minute: anchor.local.minute, second: anchor.local.second)
        guard let nominal = calendar.date(from: origin)?.addingTimeInterval(delta) else { return nil }
        let prior = calendar.dateComponents([.year, .month, .day], from: nominal.addingTimeInterval(-1))
        let after = calendar.dateComponents([.year, .month, .day], from: nominal.addingTimeInterval(1))
        let current = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nominal)
        guard prior.year == current.year, prior.month == current.month, prior.day == current.day,
              after.year == current.year, after.month == current.month, after.day == current.day,
              let year = current.year, let month = current.month, let day = current.day,
              let hour = current.hour, let minute = current.minute, let second = current.second else { return nil }
        return try? SourceLocalTime(String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000000",
                                           year, month, day, hour, minute, second))
    }
}
