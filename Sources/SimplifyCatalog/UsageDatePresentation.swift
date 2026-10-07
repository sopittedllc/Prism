import Foundation
import SimplifyCore

public struct UsageDatePresentation: Sendable {
    public let value: String
    public let detail: String
    public let accessibility: String
    init(record: AssetDateEvidence?, unavailable: Bool = false, checking: Bool = false, saved: Bool = false, incomplete: Bool = false, formatCoverage: String = "", timeZone: TimeZone = .current) {
        let explanation: String
        if let usage = record?.hostUsage {
            // Format components directly; never interpret source-local time in this Mac's zone.
            value = usage.localTime.dayKey
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
        } else if let record, record.cubaseUsage != nil {
            let day = HostUsageOrdering.dayKey(record, timeZone: timeZone)
            value = day
            let attempted = record.kind == .loadAttempt
            explanation = "Cubase " + (attempted ? "reported a plugin instantiation attempt" : "completed a successful project load") + " on " + day + " in this Mac's local display time. VST3 product history, not proof of physical installation lineage. Coverage is partial."
            detail = (attempted ? "Cubase plugin instantiation attempt" : "Cubase project load") + "\nVST3 product history · partial coverage\nLocal display time"
        } else if let proTools = record?.proToolsUsage {
            let day = proTools.localTime?.dayKey ?? "Unknown date"
            value = day
            let attempted = proTools.eventSourceID == ProToolsPluginUse.attemptedSourceID
            explanation = (attempted ? "Pro Tools attempted to instantiate this plugin on " : "Pro Tools completed a session restore on ") + day
                + ". AAX plugin history; DAW local date, time zone unknown. The host clock anchor has second-level precision."
            detail = (attempted ? "Pro Tools plugin instantiation attempt" : "Pro Tools session restore")
                + "\nAAX plugin history\nDAW local date; time zone unknown."
        } else if let record, record.logicUsage != nil {
            let day = HostUsageOrdering.dayKey(record, timeZone: timeZone)
            value = day
            explanation = "Logic Pro mixer observation on " + day + " in this Mac's local display time. Current-session component use; historical project use is not inferred."
            detail = "Logic mixer observation\nAU plugin use\nLocal display time"
        } else if let record, let membership = record.projectMembership, record.eventDate != nil {
            let day = HostUsageOrdering.dayKey(record, timeZone: timeZone)
            value = day
            let host = membership.adapter.hasPrefix("cubase-") ? "Cubase" : "Ableton Live"
            let player = membership.player ?? "Kontakt"
            explanation = host + " saved a project containing this " + player + " library on " + day
                + ". The saved-file modification time is a snapshot proxy, not the library load time. Coverage is limited to structurally decoded processor states; other projects and unsaved activity may be missing."
            detail = host + " saved project membership\n" + player + " library history · partial coverage\nSaved-file modification date"
        } else if let record, let membership = record.projectItemMembership, record.eventDate != nil {
            let day = HostUsageOrdering.dayKey(record, timeZone: timeZone)
            value = day
            let host = membership.adapter.hasPrefix("cubase-") ? "Cubase"
                : membership.adapter.hasPrefix("ableton-") ? "Ableton Live"
                : membership.adapter.hasPrefix("protools-") ? "Pro Tools"
                : membership.adapter.hasPrefix("logic-") ? "Logic Pro" : "REAPER"
            let item = membership.subjectKind == .plugin ? "plugin" : membership.subjectKind == .sample ? "sample" : "library instrument"
            explanation = host + " saved a project containing this exact " + item + " on " + day
                + ". The saved-file modification time is a snapshot proxy, not a load or playback time. Coverage is partial; other projects and unsaved activity may be missing."
            detail = host + " saved project membership\n" + item.capitalized + " history · partial coverage\nSaved-file modification date"
        } else if let record, let access = record.itemAccess, record.eventDate != nil {
            let day = HostUsageOrdering.dayKey(record, timeZone: timeZone)
            let action = switch access.outcome {
            case .attempted: "attempted to load"
            case .failed: "failed to load"
            case .opened: "opened"
            case .loaded: "loaded"
            }
            value = day
            explanation = access.appFamily.rawValue + " " + action + " this exact item on " + day
                + ". App-local display time. Item history is partial and depends on a supported music-app event source."
            detail = access.appFamily.rawValue + " item access (" + access.outcome.rawValue + ")\nExact item history · partial coverage\nLocal display time"
        } else {
            value = unavailable ? "Unavailable" : checking ? "Checking…" : "Not Used Yet"
            detail = unavailable ? "Saved usage history could not be read. Choose Check For Updates to retry." : "No qualified use recorded. Unknown does not mean unused." + (incomplete ? " Some usage sources could not be checked; coverage is incomplete." : "")
            explanation = detail
        }
        accessibility = "Last used, " + value.replacingOccurrences(of: "\n", with: ", ") + ". " + explanation
    }
}
