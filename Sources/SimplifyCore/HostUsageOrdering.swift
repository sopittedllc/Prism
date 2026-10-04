import Foundation

/// Compares qualified host uses by displayed calendar day, then by comparable
/// clocks within a host family. The display zone is injectable for deterministic tests.
public enum HostUsageOrdering {
    public static func dayKey(_ record: AssetDateEvidence, timeZone: TimeZone = .current) -> String {
        if let live = record.hostUsage { return live.localTime.dayKey }
        if let cubase = record.cubaseUsage { return absoluteDay(cubase.reportedDate, timeZone: timeZone) }
        if let proTools = record.proToolsUsage { return proTools.localTime?.dayKey ?? "" }
        if let logic = record.logicUsage { return absoluteDay(logic.reportedDate, timeZone: timeZone) }
        return ""
    }

    public static func precedes(_ a: AssetDateEvidence, _ b: AssetDateEvidence,
                                timeZone: TimeZone = .current) -> Bool {
        let ad = dayKey(a, timeZone: timeZone), bd = dayKey(b, timeZone: timeZone)
        if ad != bd { return ad > bd }
        let af = family(a), bf = family(b)
        if af != bf { return af < bf }
        if let al = a.hostUsage, let bl = b.hostUsage,
           al.localTime.canonical != bl.localTime.canonical {
            return al.localTime.canonical > bl.localTime.canonical
        }
        if let ac = a.cubaseUsage, let bc = b.cubaseUsage,
           ac.reportedMilliseconds != bc.reportedMilliseconds {
            return ac.reportedMilliseconds > bc.reportedMilliseconds
        }
        if let ap = a.proToolsUsage, let bp = b.proToolsUsage {
            if ap.localTime != bp.localTime {
                return (ap.localTime?.canonical ?? "") > (bp.localTime?.canonical ?? "")
            }
            if ap.runHash != bp.runHash { return (ap.runHash ?? "") < (bp.runHash ?? "") }
            if ap.sourceSeconds != bp.sourceSeconds { return ap.sourceSeconds > bp.sourceSeconds }
        }
        if let al = a.logicUsage, let bl = b.logicUsage,
           al.reportedDate != bl.reportedDate {
            return al.reportedDate > bl.reportedDate
        }
        return a.evidenceID.utf8.lexicographicallyPrecedes(b.evidenceID.utf8)
    }

    private static func family(_ record: AssetDateEvidence) -> Int {
        if record.hostUsage != nil { return 0 }
        if record.cubaseUsage != nil { return 1 }
        if record.proToolsUsage != nil { return 2 }
        return 3
    }

    private static func absoluteDay(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
    }
}
