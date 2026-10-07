import Foundation

/// Qualifies Spitfire's numbered technique-brush group headers. A group name by
/// itself is never an articulation; only this observed vendor-specific relation
/// supplies patch-local choices. Rest-shell headers are unavailable placeholders.
enum SpitfireBrushProfile {
    static let adapter = "spitfire-technique-brush"
    static let version = 1

    private struct Header {
        let number: Int
        let sourceName: String
        let available: Bool
    }

    static func articulations(manifest: KontaktManifestDetails,
                              groups: KontaktGroupReader.Result) -> [LibraryArticulation]? {
        guard manifest.maker == "Spitfire Audio", manifest.snpid != nil,
              let sourceVersion = groups.sourceVersion,
              let major = Int(sourceVersion.split(separator: ".").first ?? ""),
              (5...8).contains(major) else { return nil }
        var headers: [Header] = []
        for name in groups.groupNames {
            guard let header = parse(name) else {
                // A numbered NKI source relation with unfamiliar grammar means
                // this profile cannot safely claim complete membership.
                if name.range(of: #"^\s*\d{4,6}:.*\.nki from "#,
                              options: [.regularExpression, .caseInsensitive]) != nil { return nil }
                continue
            }
            headers.append(header)
        }
        guard headers.count >= 3, headers.count <= 256,
              Set(headers.map(\.number)).count == headers.count else { return nil }
        let sorted = headers.sorted { $0.number < $1.number }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $1.number - $0.number == 5 }) else { return nil }
        return sorted.filter(\.available).map { header in
            LibraryArticulation(id: "spitfire-brush:v1:\(header.number):" + header.sourceName.lowercased(),
                                name: title(header.sourceName),
                                source: "Spitfire numbered technique-brush group in Kontakt patch")
        }
    }

    private static func parse(_ raw: String) -> Header? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let digits = text[..<colon]
        guard (4...6).contains(digits.count), digits.allSatisfy(\.isNumber),
              let number = Int(digits), number < 1_000_000 else { return nil }
        let body = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let marker = body.range(of: ".nki from ", options: .caseInsensitive) else { return nil }
        let sourceName = String(body[..<marker.lowerBound]).trimmingCharacters(in: .whitespaces)
        let relation = String(body[marker.upperBound...])
        guard !sourceName.isEmpty, !sourceName.contains("/"), !sourceName.contains("\\") else { return nil }
        if relation == "rest shells" { return Header(number: number, sourceName: sourceName, available: false) }
        guard relation.hasPrefix("../technique brushes/"), relation.lowercased().hasSuffix(".nki"),
              relation.count > "../technique brushes/.nki".count else { return nil }
        return Header(number: number, sourceName: sourceName, available: true)
    }

    private static func title(_ source: String) -> String {
        var words = source.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first == "short", words.dropFirst().first != "cs" { words.removeFirst() }
        if words.last == "distorted" { words.removeLast(); words.append("(Dist)") }
        return words.map { word in word == "cs" ? "CS" : word == "(Dist)" ? word : word.capitalized }.joined(separator: " ")
    }
}
