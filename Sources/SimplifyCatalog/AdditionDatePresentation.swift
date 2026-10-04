import Foundation
import SimplifyCore

/// Visible precision shared by table, inspector and accessibility.
public struct AdditionDatePresentation: Sendable {
    public let evidence: AdditionDateEvidence?
    public let value: String
    public let detail: String
    public let accessibility: String

    init(evidence: AdditionDateEvidence?, coverage: String = "", saved: Bool = false, checking: Bool = false, observation: String = "", finderDateAdded: Bool = false, finderSourceExpected: Bool = false) {
        self.evidence = evidence
        guard let evidence else {
            value = checking ? "Checking…" : "Unknown"
            detail = [checking ? "Checking current collection…" : finderSourceExpected ? "Finder Date Added is unavailable for this file." : "Original Date added is unknown.", coverage, observation,
                      saved ? "Saved history; current installation not verified." : ""].filter { !$0.isEmpty }.joined(separator: "\n")
            accessibility = "Date added, " + value + ". " + detail
            return
        }
        func short(_ date: Date) -> String { date.formatted(date: .numeric, time: .omitted) }
        func full(_ date: Date) -> String { date.formatted(date: .complete, time: .omitted) }
        let explanation: String
        let visible: String
        switch evidence.basis {
        case .exact:
            value = short(evidence.upper)
            explanation = (finderDateAdded ? "Finder Date Added " : "Added on ") + full(evidence.upper) + "."
            visible = (finderDateAdded ? "Finder Date Added " : "Added on ") + evidence.upper.formatted(date: .abbreviated, time: .omitted) + "."
        case .presentBy:
            value = "By " + short(evidence.upper)
            explanation = "Present by " + full(evidence.upper) + ". It may have been added earlier."
            visible = "Present by " + evidence.upper.formatted(date: .abbreviated, time: .omitted) + "; may have been added earlier."
        case .observedArrival:
            let lower = evidence.lower!
            if Calendar.current.isDate(lower, inSameDayAs: evidence.upper) {
                value = "During\n" + short(evidence.upper)
            } else { value = short(lower) + "–\n" + short(evidence.upper) }
            let period = Calendar.current.isDate(lower, inSameDayAs: evidence.upper)
                ? "during " + evidence.upper.formatted(date: .abbreviated, time: .omitted)
                : "between " + lower.formatted(date: .abbreviated, time: .omitted) + " and " + evidence.upper.formatted(date: .abbreviated, time: .omitted)
            visible = "Appeared " + period + ". May be a move or restored copy."
            explanation = "Appeared in monitored folders between " + full(lower) + " and " + full(evidence.upper) + ". This may be a move or restored copy."
        }
        detail = [visible, coverage, observation, saved ? "Saved history; current installation not verified." : ""].filter { !$0.isEmpty }.joined(separator: "\n")
        accessibility = "Date added, " + [explanation, coverage, observation, saved ? "Saved history; current installation not verified." : ""].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
