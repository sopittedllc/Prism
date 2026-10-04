import Foundation
import SimplifyCore

public struct UsageDatePresentation: Sendable {
    public let value: String
    public let detail: String
    public let accessibility: String
    init(record: AssetDateEvidence?, unavailable: Bool = false, checking: Bool = false, saved: Bool = false, incomplete: Bool = false, formatCoverage: String = "") {
        let explanation: String
        if let usage = record?.hostUsage {
            // Format components directly; never interpret source-local time in this Mac's zone.
            value = usage.localTime.dayKey + "\nDAW local"
            let eventDescription = usage.qualification == HostUsageProvenance.completedManualCreate
                ? "created a VST3 plugin instance" : "completed a session restore"
            explanation = "Ableton Live " + usage.hostVersion + " " + eventDescription + " on " + usage.localTime.dayKey
                + ". DAW local date; time zone unknown.\nVST3 product history, not proof that this installation or other formats were used."
                + "\nCoverage is partial; later use in other sessions or hosts may be missing."
                + (saved ? "\nSaved history; current installation not verified." : "")
                + (incomplete ? "\nSome current usage sources could not be checked." : "") + "\n" + formatCoverage
            let eventLabel = usage.qualification == HostUsageProvenance.completedManualCreate
                ? "Live plugin creation" : "Live session load"
            detail = eventLabel + "\nVST3 product history · partial coverage\nDAW local date; time zone unknown."
                + (saved ? "\nSaved history; current installation not verified." : "")
                + (incomplete ? "\nSome usage sources could not be checked." : "")
        } else if let cubase = record?.cubaseUsage {
            let day = cubase.reportedDate.formatted(.iso8601.year().month().day())
            value = day + "\nCubase local"
            explanation = "Cubase completed a successful project load on " + day + ". VST3 product history, not proof of physical installation lineage."
            detail = "Cubase project load\nVST3 product history"
        } else if let proTools = record?.proToolsUsage {
            let day = proTools.localTime?.dayKey ?? "Unknown date"
            value = day + "\nPro Tools local"
            explanation = "Pro Tools completed a session restore on " + day
                + ". AAX plugin history; DAW local date, time zone unknown. The host clock anchor has second-level precision."
            detail = "Pro Tools session restore\nAAX plugin history\nDAW local date; time zone unknown."
        } else if let logic = record?.logicUsage {
            let day = logic.reportedDate.formatted(.iso8601.year().month().day())
            value = day + "\nLogic local"
            explanation = "Logic Pro mixer observation on " + day + ". Current-session component use; historical project use is not inferred."
            detail = "Logic mixer observation\nAU plugin use"
        } else {
            value = unavailable ? "Unavailable" : checking ? "Checking…" : "Unknown"
            detail = unavailable ? "Saved usage history could not be read. Scan to retry." : "No qualified use recorded. Unknown does not mean unused." + (incomplete ? " Some usage sources could not be checked; coverage is incomplete." : "")
            explanation = detail
        }
        accessibility = "Last used, " + value.replacingOccurrences(of: "\n", with: ", ") + ". " + explanation
    }
}
