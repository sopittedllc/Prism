import Foundation
import CryptoKit

/// A Gregorian clock reading reported without an offset. This is NOT a UTC instant.
/// Arithmetic below is only for validating source-local sequence boundaries.
public struct SourceLocalTime: Codable, Sendable, Equatable, Comparable {
    public let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, microsecond: Int
    public init(_ text: String) throws {
        let b = Array(text.utf8)
        guard b.count == 26, b[4] == 45, b[7] == 45, b[10] == 84,
              b[13] == 58, b[16] == 58, b[19] == 46 else { throw AssetDateEvidenceError.invalidProvenance }
        let separators = Set([4, 7, 10, 13, 16, 19])
        guard b.indices.allSatisfy({ separators.contains($0) || (48...57).contains(b[$0]) }) else {
            throw AssetDateEvidenceError.invalidProvenance
        }
        func n(_ range: Range<Int>) -> Int { range.reduce(0) { $0 * 10 + Int(b[$1] - 48) } }
        year = n(0..<4); month = n(5..<7); day = n(8..<10); hour = n(11..<13)
        minute = n(14..<16); second = n(17..<19); microsecond = n(20..<26)
        try validate()
    }
    public var canonical: String {
        String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%06d", year, month, day, hour, minute, second, microsecond)
    }
    public var dayKey: String { String(canonical.prefix(10)) }
    public static func < (a: Self, b: Self) -> Bool { a.canonical < b.canonical }
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var components: DateComponents { DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second) }
    var sequenceSeconds: Double { Self.calendar.date(from: components)!.timeIntervalSince1970 + Double(microsecond) / 1_000_000 }
    func validate() throws {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second),
              (0...999_999).contains(microsecond), let date = Self.calendar.date(from: components),
              Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components else {
            throw AssetDateEvidenceError.invalidProvenance
        }
    }
}

/// Qualified Live VST3 class evidence from a completed document restore or manual instance
/// creation, not proof of physical installation use. Current catalog nodes retain an
/// association to this exact class history. No UTC time or installation lineage is inferred.
/// Cache snapshots are not event identity.
public struct HostUsageProvenance: Codable, Sendable, Equatable {
    public static let sourceID = "ableton.live.vst3.document-restore.v1"
    public static let manualCreateSourceID = "ableton.live.vst3.manual-create.v1"
    public static let completedDocumentRestore = "completedDocumentRestore"
    public static let completedManualCreate = "completedManualCreate"
    public let hostVersion: String
    public let classID: String
    public let pluginVersion: String
    public let localTime: SourceLocalTime
    public let runHash: String
    public let recordHash: String
    public let recordOffset: Int
    public let subjectScope: String
    public let qualification: String
    /// The stored qualification selects the source, so legacy Codable records need no migration.
    public var eventSourceID: String {
        qualification == Self.completedManualCreate ? Self.manualCreateSourceID : Self.sourceID
    }

    init(hostVersion: String, classID: String, pluginVersion: String, localTime: SourceLocalTime,
         runHash: String, recordHash: String, recordOffset: Int,
         qualification: String = Self.completedDocumentRestore) {
        self.hostVersion = hostVersion; self.classID = classID; self.pluginVersion = pluginVersion
        self.localTime = localTime; self.runHash = runHash; self.recordHash = recordHash
        self.recordOffset = recordOffset; subjectScope = "pluginClass"; self.qualification = qualification
    }
    func validate() throws {
        try localTime.validate()
        guard ["12.4.5", "12.4.6"].contains(hostVersion), Self.validClassID(classID),
              subjectScope == "pluginClass",
              [Self.completedDocumentRestore, Self.completedManualCreate].contains(qualification),
              (0...LiveUsageLog.maximumBytes).contains(recordOffset),
              [runHash, recordHash].allSatisfy({ $0.utf8.count == 64 && $0.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) else {
            throw AssetDateEvidenceError.invalidProvenance
        }
        try AssetDateResolver.validateIdentifier(pluginVersion, limit: 128)
        guard pluginVersion.utf8.allSatisfy({ (33...126).contains($0) }) else { throw AssetDateEvidenceError.invalidProvenance }
    }
    public static func validClassID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 36 && bytes.indices.allSatisfy {
            [8, 13, 18, 23].contains($0) ? bytes[$0] == 45 : (48...57).contains(bytes[$0]) || (65...70).contains(bytes[$0])
        }
    }
    /// Stable source-event association ID, independent of ingestion and growing log bytes.
    public func eventID(subjectID: String) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        return Self.digest(try encoder.encode([eventSourceID, runHash, String(recordOffset), recordHash, classID, subjectID]))
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// Pure bounded adapter for the tested Live log grammar. Restore events require a complete
/// document exchange; manual events require a disjoint create/load/Created sequence.
/// Scanner/browser loads, failures, and truncated records produce no use. Call off the UI/audio thread.
public enum LiveUsageLog {
    public static let maximumBytes = 32 * 1024 * 1024
    public struct Result: Sendable {
        public let events: [HostUsageProvenance]
        public let rejectedDocuments: Int
    }
    private struct Pending { let name: String; var classID: String?; var version: String? }
    private struct PendingManual {
        let name: String
        let start: SourceLocalTime
        var previousTime: SourceLocalTime
        var classID: String?
        var version: String?
    }
    public static func parse(_ data: Data, deadline: Double = .infinity) throws -> Result {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8), !data.contains(0) else {
            throw AssetDateEvidenceError.invalidProvenance
        }
        let processor = try NSRegularExpression(pattern: #"^VST3: plugin processor successfully loaded: .+ '(.+)' v([^ ]+) \(cid: \{([0-9A-F-]{36})\}\)$"#)
        var events: [HostUsageProvenance] = [], candidates: [HostUsageProvenance] = []
        var hostVersion: String?, runHash = "", runOffset = 0, offset = 0
        var documentStart: SourceLocalTime?, previousTime: SourceLocalTime?, pending: Pending?
        var manual: PendingManual?
        var phase = 0, rejected = 0
        var continuation: String?
        func resetDocument() { documentStart = nil; previousTime = nil; pending = nil; candidates = []; phase = 0 }
        func reject() { if documentStart != nil { rejected += 1 }; resetDocument() }
        // Require newline termination: a writer's final partial record is not complete.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.allSatisfy({ $0.utf8.count <= 32_768 }) else { throw AssetDateEvidenceError.invalidProvenance }
        for part in lines.dropLast() {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogStoreError.busy }
            let line = String(part); let currentOffset = offset; offset += part.utf8.count + 1
            guard line.utf8.count <= 32_768 else { throw AssetDateEvidenceError.invalidProvenance }
            guard line.count >= 34, let time = try? SourceLocalTime(String(line.prefix(26))) else {
                let validContinuation = continuation == "remote" ? line.hasPrefix("  MidiRemoteScript ") :
                    continuation == "devices" ? (line.hasPrefix("  MidiInDevice [") || line.hasPrefix("  MidiOutDevice [")) : false
                if validContinuation && line.hasSuffix("]") { continue }
                if !line.isEmpty { reject(); manual = nil }; continue
            }
            continuation = nil
            let tail = String(line.dropFirst(26))
            guard tail.hasPrefix(": info: ") || tail.hasPrefix(": warning: ") || tail.hasPrefix(": error: ") else { reject(); manual = nil; continue }
            let message = String(tail.dropFirst(tail.hasPrefix(": info: ") ? 8 : tail.hasPrefix(": error: ") ? 9 : 11))
            if let active = manual {
                guard time >= active.previousTime,
                      time.sequenceSeconds - active.start.sequenceSeconds <= 30 else { manual = nil; continue }
                manual?.previousTime = time
            }
            // Run/document boundaries own their own clocks. A previous incomplete
            // document must not swallow a new run (including unsupported versions).
            if tail.hasPrefix(": info: "), message.hasPrefix("Init: Version: ") {
                reject(); manual = nil; hostVersion = nil
                for version in ["12.4.5", "12.4.6"] where message.hasPrefix("Init: Version: 'Live " + version + " Build: ") { hostVersion = version }
                runHash = HostUsageProvenance.digest(Data(line.utf8)); runOffset = currentOffset
                continue
            }
            if tail.hasPrefix(": info: "), message.hasPrefix("Loading document \"") {
                reject(); manual = nil
                guard hostVersion != nil, message.hasSuffix(".als\"") else { continue }
                documentStart = time; previousTime = time; phase = 1; continue
            }
            if tail.hasPrefix(": info: "), message.hasPrefix("VST3: Going to restore: ") {
                manual = nil
            }
            if tail.hasPrefix(": info: "), message.hasPrefix("VST3: Going to create: ") {
                let outsidePendingRestore = documentStart == nil || (phase == 2 && pending == nil && candidates.isEmpty)
                guard hostVersion != nil, outsidePendingRestore, manual == nil else {
                    manual = nil
                    if documentStart != nil { reject() }
                    continue
                }
                let name = String(message.dropFirst("VST3: Going to create: ".count))
                guard !name.isEmpty else { continue }
                manual = PendingManual(name: name, start: time, previousTime: time, classID: nil, version: nil)
                continue
            }
            if let active = manual, message.hasPrefix("VST3: plugin processor successfully loaded:") {
                guard active.classID == nil,
                      let match = processor.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                      let nr = Range(match.range(at: 1), in: message), let vr = Range(match.range(at: 2), in: message),
                      let cr = Range(match.range(at: 3), in: message),
                      active.name.utf8.elementsEqual(message[nr].utf8),
                      HostUsageProvenance.validClassID(String(message[cr])) else { manual = nil; continue }
                manual?.classID = String(message[cr]); manual?.version = String(message[vr])
                continue
            }
            if let active = manual, message.hasPrefix("VST3: Created: ") {
                let createdName = message.dropFirst("VST3: Created: ".count)
                guard let cid = active.classID, let version = active.version,
                      active.name.utf8.elementsEqual(createdName.utf8) else { manual = nil; continue }
                let event = HostUsageProvenance(hostVersion: hostVersion ?? "", classID: cid, pluginVersion: version,
                    localTime: time, runHash: runHash, recordHash: HostUsageProvenance.digest(Data(line.utf8)),
                    recordOffset: currentOffset - runOffset, qualification: HostUsageProvenance.completedManualCreate)
                try event.validate(); events.append(event); manual = nil
                guard events.count <= 4096 else { throw AssetDateEvidenceError.tooManyRecords }
                continue
            }
            if message.hasPrefix("Loaded document was created by Ableton Live ") ||
                message == "Default App: Begin ExchangeDocument" || message == "Default App: End ExchangeDocument" {
                manual = nil
            }
            if message.contains("FatalError") || message.hasPrefix("Fatal") ||
                (message.hasPrefix("VST3: Restore ") && message.contains(" failed:")) {
                manual = nil
            }
            if !tail.hasPrefix(": info: ") {
                let knownBenignManualChatter = [
                    "VST3: requesting size of VST3 plugin view failed",
                    "VST3: setProcessing returned error: not implemented",
                    "VST3: couldn't connect to processor from edit controller",
                ].contains(message)
                if !knownBenignManualChatter { manual = nil }
            }
            guard let hostVersion, let start = documentStart else { continue }
            guard time >= (previousTime ?? start), time.sequenceSeconds - start.sequenceSeconds <= 120 else { reject(); continue }
            previousTime = time
            if message.contains("FatalError") || message.hasPrefix("Fatal") ||
                (message.hasPrefix("VST3: Restore ") && message.contains(" failed:")) { reject(); continue }
            if !tail.hasPrefix(": info: ") {
                if tail.hasPrefix(": error: ") && message != "VST3: couldn't connect to processor from edit controller"
                    && message != "VST3: requesting size of VST3 plugin view failed" { reject() }
                continue
            }
            if message == "AMidiIO: Midi Remote Scripts: " { continuation = "remote" }
            if message == "AMidiIO: Midi Devices: " { continuation = "devices" }
            if message.hasPrefix("VST3: Going to restore: ") {
                guard phase == 1, pending == nil else { reject(); continue }
                let name = String(message.dropFirst("VST3: Going to restore: ".count))
                guard !name.isEmpty else { reject(); continue }
                pending = Pending(name: name); continue
            }
            if message.hasPrefix("VST3: plugin processor successfully loaded:") {
                guard phase == 1, var item = pending, item.classID == nil,
                      let match = processor.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                      let nr = Range(match.range(at: 1), in: message), let vr = Range(match.range(at: 2), in: message),
                      let cr = Range(match.range(at: 3), in: message),
                      item.name.utf8.elementsEqual(message[nr].utf8), HostUsageProvenance.validClassID(String(message[cr])) else {
                    reject(); continue
                }
                item.classID = String(message[cr]); item.version = String(message[vr]); pending = item; continue
            }
            if message.hasPrefix("VST3: Restored: ") {
                guard phase == 1, let item = pending, let cid = item.classID, let version = item.version,
                      item.name.utf8.elementsEqual(message.dropFirst("VST3: Restored: ".count).utf8) else { reject(); continue }
                let event = HostUsageProvenance(hostVersion: hostVersion, classID: cid, pluginVersion: version,
                    localTime: time, runHash: runHash, recordHash: HostUsageProvenance.digest(Data(line.utf8)), recordOffset: currentOffset - runOffset)
                try event.validate(); candidates.append(event); pending = nil
                guard candidates.count + events.count <= 4096 else { throw AssetDateEvidenceError.tooManyRecords }
                continue
            }
            if message.hasPrefix("VST3: Restore ") && message.contains(" failed:") { reject(); continue }
            if message.hasPrefix("Loaded document was created by Ableton Live ") {
                guard phase == 1, pending == nil else { reject(); continue }; phase = 2; continue
            }
            if message == "Default App: Begin ExchangeDocument" {
                guard phase == 2 else { reject(); continue }; phase = 3; continue
            }
            if message == "Default App: End ExchangeDocument" {
                guard phase == 3, pending == nil else { reject(); continue }
                events += candidates; resetDocument()
            }
        }
        if documentStart != nil { rejected += 1 }
        return Result(events: events, rejectedDocuments: rejected)
    }
}
