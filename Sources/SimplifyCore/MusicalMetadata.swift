import Foundation

/// User-facing musical dimensions; IDs are stable across display-name changes.
public enum MusicalFacet: String, Codable, CaseIterable, Sendable {
    case instrument, technique, ensemble, register, character, role, function, sampleType, bpm, key
    public var title: String {
        switch self {
        case .instrument: "Instrument / section"
        case .technique: "Technique"
        case .ensemble: "Solo / ensemble"
        case .register: "Register"
        case .character: "Character"
        case .role: "Musical role"
        case .function: "Plugin function"
        case .sampleType: "Sample type"
        case .bpm: "BPM"
        case .key: "Key"
        }
    }
    public static func fields(for kind: AssetKind) -> [Self] {
        allCases.filter { facet in
            if facet == .function { return kind == .plugin }
            return kind == .sample || ![.sampleType, .bpm, .key].contains(facet)
        }
    }
}

/// Missing field means use suggestions; an empty array deliberately suppresses them.
public struct MusicalMetadata: Codable, Sendable, Equatable {
    public var fields: [String: [String]]
    public init(fields: [String: [String]] = [:]) { self.fields = fields }
    public subscript(_ facet: MusicalFacet) -> [String]? {
        get { fields[facet.rawValue] }
        set { fields[facet.rawValue] = newValue }
    }
    public var searchText: String { fields.keys.sorted().flatMap { fields[$0] ?? [] }.joined(separator: " ") }
    public func applying(_ override: Self?) -> Self {
        Self(fields: fields.merging(override?.fields ?? [:]) { _, edited in edited })
    }
    public func validated() throws -> Self {
        guard fields.count <= MusicalFacet.allCases.count else { throw CatalogStoreError.invalid }
        var result = Self()
        for (key, values) in fields {
            guard let facet = MusicalFacet(rawValue: key), values.count <= 24,
                  values.allSatisfy({ $0.count <= 80 && !$0.contains(where: \.isNewline) }) else { throw CatalogStoreError.invalid }
            let clean = Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
            if facet == .bpm, !clean.isEmpty {
                guard clean.count == 1, let bpm = Double(clean[0]), bpm.isFinite, bpm > 0, bpm <= 999 else { throw CatalogStoreError.invalid }
            }
            result[facet] = clean
        }
        return result
    }
    /// Suggestions are local label evidence, never claims about a loaded patch.
    public static func suggested(name: String, tags: [String], kind: AssetKind,
                                 suppressInstrumentFamilyGuess: Bool = false) -> Self {
        let text = MusicalSearch.normalized(([name] + tags).joined(separator: " "))
        let words = text.split(separator: " ").map(String.init)
        var phrases = Set(words)
        if words.count > 1 {
            for index in 0..<(words.count - 1) {
                phrases.insert(words[index] + " " + words[index + 1])
            }
        }
        var result = Self()
        for facet in fields(for: kind) {
            if facet == .instrument && suppressInstrumentFamilyGuess { continue }
            let values = (suggestionVocabulary[facet] ?? []).compactMap { value, needle in
                phrases.contains(needle) || phrases.contains(needle + "s") ? value : nil
            }
            if !values.isEmpty { result[facet] = values }
        }
        return result
    }
    private static let suggestionVocabulary: [MusicalFacet: [(String, String)]] = {
        let vocabulary: [MusicalFacet: [String]] = [
            .instrument: ["accordion", "banjo", "guitar", "piano", "organ", "violin", "viola", "cello", "bass", "strings", "brass", "woodwinds", "flute", "clarinet", "oboe", "bassoon", "trumpet", "trombone", "tuba", "horn", "percussion", "drums", "choir", "vocal", "synth", "harp", "mandolin", "ukulele"],
            .technique: ["legato", "sustain", "staccato", "spiccato", "pizzicato", "tremolo", "trill", "muted", "sul ponticello", "sul tasto", "marcato"],
            .ensemble: ["solo", "chamber", "ensemble", "section"], .register: ["low", "mid", "high"],
            .character: ["warm", "dark", "bright", "soft", "intimate", "tense", "aggressive", "airy", "evolving"],
            .role: ["melody", "ostinato", "bed", "texture", "pulse", "transition", "rise", "impact", "drone"],
            .sampleType: ["loop", "one shot", "phrase"],
            .function: ["eq", "equalizer", "reverb", "delay", "compressor", "limiter", "saturation", "distortion", "filter"]
        ]
        return vocabulary.mapValues { $0.map { ($0, MusicalSearch.normalized($0)) } }
    }()
    private static func fields(for kind: AssetKind) -> [MusicalFacet] { MusicalFacet.fields(for: kind) }
}

public enum MusicalSearch {
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let aliases = ["celli": "cello", "cellos": "cello", "violoncello": "cello", "harmonics": "harmonic"]

    public static func normalized(_ text: String) -> String {
        var value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        value = value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        value = value.replacingOccurrences(of: "con sordino", with: "muted")
        return value.split(separator: " ").map {
            aliases[String($0)] ?? String($0)
        }.joined(separator: " ")
    }
    public static func matches(_ query: String, in text: String) -> Bool {
        let haystack = normalized(text)
        let words = haystack.split(separator: " ")
        return normalized(query).split(separator: " ").allSatisfy { term in
            if term.allSatisfy(\.isNumber) || term.count == 1 { return words.contains(term) }
            return haystack.contains(term)
        }
    }
}

/// Presentation only: tag identity, search, and saved metadata retain their original spelling.
public enum MusicalTagDisplay {
    private static let acronyms: Set<String> = ["BPM", "MIDI", "FX", "EQ", "EDM", "DAW", "VST", "AU", "AAX", "CLAP"]

    public static func title(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: false).map { phrase in
            phrase.split(separator: "-", omittingEmptySubsequences: false).map { part in
                let word = String(part)
                guard let first = word.first else { return word }
                let upper = word.uppercased()
                if acronyms.contains(upper) { return upper }
                // Existing mixed case includes key notation such as F#m and product names.
                if word.dropFirst().contains(where: \.isUppercase) && upper != word { return word }
                return first.uppercased() + word.dropFirst().lowercased()
            }.joined(separator: "-")
        }.joined(separator: " ")
    }
}

public struct MetadataSubject: Codable, Sendable, Hashable {
    public let nodeID: String
    public let instrumentKey: String?
    public init(nodeID: String, instrument: LibraryInstrument? = nil) {
        self.nodeID = nodeID
        instrumentKey = instrument.map { $0.vendorID.map { "vendor:" + $0 } ?? "path:" + $0.path }
    }
    public var key: String {
        String(decoding: try! JSONEncoder().encode([nodeID, instrumentKey ?? ""]), as: UTF8.self)
    }
}
