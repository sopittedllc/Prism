import CryptoKit
import Foundation

/// Exported listing row. Names and the raw instance summary are not stable asset IDs or usage events.
public struct ProToolsListedPlugin: Encodable, Sendable, Equatable {
    public let manufacturer: String
    public let name: String
    public let version: String
    public let format: String
    public let stems: String
    public let instanceSummary: String
}

/// Session file-pool member. Location is export text, not a resolved filesystem path.
public struct ProToolsPooledFile: Encodable, Sendable, Equatable {
    public let availability: String
    public let name: String
    public let location: String
}

/// Session clip-pool member, not a proven timeline event or resolved source asset.
public struct ProToolsPooledClip: Encodable, Sendable, Equatable {
    public let name: String
    public let sourceFile: String
    public let channel: String
}

/// Export-local audio event. Position strings are not dates; row links are not asset IDs.
public struct ProToolsTrackEvent: Encodable, Sendable {
    public let channel: String
    public let eventNumber: String
    public let clipName: String
    public let start: String
    public let end: String
    public let duration: String
    public let state: String
    public let clipPoolOrdinal: Int?
    public let filePoolOrdinal: Int?
    public let bindingStatus: String
}

/// Ordinal belongs only to this export. Equal track names remain distinct.
public struct ProToolsExportedTrack: Encodable, Sendable {
    public let ordinal: Int
    public let name: String
    public let comments: String
    public let userDelay: String
    public let state: String
    public let pluginSummary: String
    public let events: [ProToolsTrackEvent]
}

public struct ProToolsSessionTextReport: Encodable, Sendable {
    public let adapterVersion: Int
    public let coverage: String
    public let inputSHA256: String
    public let sessionName: String
    /// An absent section is unknown, distinct from a present section with zero rows.
    public let includedSections: [String]
    public let plugins: [ProToolsListedPlugin]
    public let files: [ProToolsPooledFile]
    public let clips: [ProToolsPooledClip]
    public let tracks: [ProToolsExportedTrack]
    public let limitations: [String]
}

/// Reads the English UTF-8 table layout observed in Pro Tools 2024.10 exports.
/// Audio EDL owners are export-local; no source-project association, installed-asset matching or use clock.
public enum ProToolsSessionTextReader {
    public static let maximumInputBytes = ProjectReader.maximumInputBytes
    public static let maximumLines = 100_000
    public static let maximumLineBytes = 16_384
    public static let maximumFieldBytes = 1_024
    public static let maximumRows = 4_096
    public static let maximumTracks = 1_024

    /// Bounded regular-file read, final-component O_NOFOLLOW and non-atomic ancestor preflight.
    public static func inspect(_ url: URL) throws -> ProToolsSessionTextReport {
        var ancestor = url
        while ancestor.path != "/" {
            if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            ancestor.deleteLastPathComponent()
        }
        return try parse(BoundedFile.read(url, limit: maximumInputBytes))
    }

    /// All-or-nothing parsing with bounded rows and tracks. Marker tails remain unparsed;
    /// encoding, control-character and line budgets still apply to the entire input.
    public static func parse(_ data: Data) throws -> ProToolsSessionTextReport {
        guard data.count <= maximumInputBytes else { throw ProjectReadError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw ProjectReadError.malformed }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        guard text.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0) || [9, 10, 13].contains($0.value)
        }) else { throw ProjectReadError.malformed }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        guard lines.count <= maximumLines, lines.allSatisfy({ $0.utf8.count <= maximumLineBytes }) else {
            throw ProjectReadError.tooLarge
        }
        let header = ["SESSION NAME:", "SAMPLE RATE:", "BIT DEPTH:", "SESSION START TIMECODE:",
                      "TIMECODE FORMAT:", "# OF AUDIO TRACKS:", "# OF AUDIO CLIPS:", "# OF AUDIO FILES:"]
        guard lines.count >= header.count else { throw ProjectReadError.malformed }
        var sessionName = ""
        for (index, key) in header.enumerated() {
            let fields = try cells(lines[index], count: 2)
            guard fields[0] == key else { throw ProjectReadError.malformed }
            if index == 0 { sessionName = fields[1] }
        }
        var included: [String] = []
        var plugins: [ProToolsListedPlugin] = []
        var files: [ProToolsPooledFile] = []
        var clips: [ProToolsPooledClip] = []
        var tracks: [ProToolsExportedTrack] = []
        var current: Section?
        var index = header.count
        var rowCount = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line == "M A R K E R S  L I S T I N G" { break }
            if line == "T R A C K  L I S T I N G" {
                tracks = try parseTracks(lines, index: &index, rowCount: &rowCount,
                                         clips: clips, files: files, included: included)
                included.append("tracks")
                break
            }
            if let section = Section.allCases.first(where: { $0.heading == line }) {
                guard section.rawValue > (current?.rawValue ?? -1), index < lines.count,
                      try cells(lines[index], count: section.columns.count) == section.columns else {
                    throw ProjectReadError.malformed
                }
                index += 1
                current = section
                included.append(section.label)
                continue
            }
            guard let current else { throw ProjectReadError.malformed }
            guard rowCount < maximumRows else { throw ProjectReadError.tooLarge }
            let fields = try cells(line, count: current == .clips ? 3 : current.columns.count)
            rowCount += 1
            switch current {
            case .onlineFiles, .offlineFiles:
                files.append(ProToolsPooledFile(availability: current == .onlineFiles ? "online" : "offline",
                                               name: fields[0], location: fields[1]))
            case .clips:
                clips.append(ProToolsPooledClip(name: fields[0], sourceFile: fields[1], channel: fields[2]))
            case .plugins:
                plugins.append(ProToolsListedPlugin(manufacturer: fields[0], name: fields[1], version: fields[2],
                                                    format: fields[3], stems: fields[4], instanceSummary: fields[5]))
            }
        }
        guard !included.isEmpty else { throw ProjectReadError.malformed }
        return ProToolsSessionTextReport(
            adapterVersion: 2, coverage: "partial-export",
            inputSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sessionName: sessionName, includedSections: included, plugins: plugins, files: files, clips: clips, tracks: tracks,
            limitations: [
                "Optional export sections only; absent sections are unknown, not empty. Completeness and provenance are not authenticated.",
                "Plugin rows have no stable plugin ID or track ownership; instance counts and status remain uninterpreted export text.",
                "Files and clips are session-pool entries, not proof of timeline placement; locations and source filenames remain unresolved.",
                "Audio EDL tracks may be selected-only; MIDI EDLs and marker listings are not covered. Other export layouts and encodings are unsupported.",
                "Event pool ordinals are unique exact-name links within this export only, not resolved source-file or installed-asset identities. Missing and ambiguous links remain unresolved.",
                "No exact Kontakt instrument identity, installed-asset association or saved source-project revision.",
                "No wall-clock usage timestamp; export time and timeline positions are not Last used. Not catalog or cleanup evidence.",
                "Observed English UTF-8 layout only; no verified host-version declaration in the export.",
            ])
    }

    private static func parseTracks(_ lines: [String], index: inout Int, rowCount: inout Int,
                                    clips: [ProToolsPooledClip], files: [ProToolsPooledFile],
                                    included: [String]) throws -> [ProToolsExportedTrack] {
        let clipMap = Dictionary(grouping: clips.indices, by: { clips[$0].name })
        let fileMap = Dictionary(grouping: files.indices, by: { files[$0].name })
        func binding(_ name: String) -> (Int?, Int?, String) {
            guard included.contains("online-clips") else { return (nil, nil, "clip-list-omitted") }
            let matches = clipMap[name] ?? []
            guard !matches.isEmpty else { return (nil, nil, "missing-clip-name") }
            guard matches.count == 1 else { return (nil, nil, "ambiguous-clip-name") }
            let clip = matches[0]
            guard included.contains("online-files") || included.contains("offline-files") else {
                return (clip, nil, "file-list-omitted")
            }
            let sources = fileMap[clips[clip].sourceFile] ?? []
            guard !sources.isEmpty else { return (clip, nil, "missing-file-name") }
            guard sources.count == 1 else { return (clip, nil, "ambiguous-file-name") }
            return (clip, sources[0], "unique-export-row")
        }
        func metadata(_ line: String, label: String, empty: Bool = false) throws -> String {
            let fields = try cells(line, count: 2, allowEmpty: empty)
            guard fields[0] == label else { throw ProjectReadError.malformed }
            return fields[1]
        }
        func positiveDecimal(_ value: String) -> Bool {
            value.utf8.allSatisfy { (48...57).contains($0) } && value.utf8.contains { $0 != 48 }
        }
        let headings = ["CHANNEL", "EVENT", "CLIP NAME", "START TIME", "END TIME", "DURATION", "STATE"]
        var tracks: [ProToolsExportedTrack] = []
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            if lines[index] == "M A R K E R S  L I S T I N G" { break }
            guard tracks.count < maximumTracks else { throw ProjectReadError.tooLarge }
            guard index + 5 < lines.count else { throw ProjectReadError.malformed }
            let name = try metadata(lines[index], label: "TRACK NAME:")
            let comments = try metadata(lines[index + 1], label: "COMMENTS:", empty: true)
            let delay = try metadata(lines[index + 2], label: "USER DELAY:")
            let stateLine = lines[index + 3]
            guard stateLine == "STATE:" || stateLine.hasPrefix("STATE: "), !stateLine.contains("\t") else {
                throw ProjectReadError.malformed
            }
            let state = String(stateLine.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: " "))
            guard state.utf8.count <= maximumFieldBytes else { throw ProjectReadError.malformed }
            let pluginSummary = try metadata(lines[index + 4], label: "PLUG-INS:", empty: true)
            guard try cells(lines[index + 5], count: 7) == headings else { throw ProjectReadError.malformed }
            index += 6
            var events: [ProToolsTrackEvent] = []
            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
                if line.hasPrefix("TRACK NAME:\t") || line == "M A R K E R S  L I S T I N G" { break }
                guard rowCount < maximumRows else { throw ProjectReadError.tooLarge }
                let fields = try cells(line, count: 7)
                guard positiveDecimal(fields[0]), positiveDecimal(fields[1]) else { throw ProjectReadError.malformed }
                let (clip, file, status) = binding(fields[2])
                events.append(ProToolsTrackEvent(channel: fields[0], eventNumber: fields[1], clipName: fields[2],
                                                 start: fields[3], end: fields[4], duration: fields[5], state: fields[6],
                                                 clipPoolOrdinal: clip, filePoolOrdinal: file, bindingStatus: status))
                rowCount += 1
                index += 1
            }
            tracks.append(ProToolsExportedTrack(ordinal: tracks.count, name: name, comments: comments,
                                               userDelay: delay, state: state, pluginSummary: pluginSummary, events: events))
        }
        return tracks
    }

    private static func cells(_ line: String, count: Int, allowEmpty: Bool = false) throws -> [String] {
        let values = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
        guard values.count == count, values.allSatisfy({ (allowEmpty || !$0.isEmpty) && $0.utf8.count <= maximumFieldBytes }) else {
            throw ProjectReadError.malformed
        }
        return values
    }

    private enum Section: Int, CaseIterable {
        case onlineFiles, offlineFiles, clips, plugins
        var label: String {
            switch self {
            case .onlineFiles: "online-files"
            case .offlineFiles: "offline-files"
            case .clips: "online-clips"
            case .plugins: "plugins"
            }
        }
        var heading: String {
            switch self {
            case .onlineFiles: "O N L I N E  F I L E S  I N  S E S S I O N"
            case .offlineFiles: "O F F L I N E  F I L E S  I N  S E S S I O N"
            case .clips: "O N L I N E  C L I P S  I N  S E S S I O N"
            case .plugins: "P L U G - I N S  L I S T I N G"
            }
        }
        var columns: [String] {
            switch self {
            case .onlineFiles, .offlineFiles: ["Filename", "Location"]
            case .clips: ["CLIP NAME", "Source File"]
            case .plugins: ["MANUFACTURER", "PLUG-IN NAME", "VERSION", "FORMAT", "STEMS", "NUMBER OF INSTANCES"]
            }
        }
    }
}
