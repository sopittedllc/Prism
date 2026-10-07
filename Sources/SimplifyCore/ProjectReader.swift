import Foundation
import CZlib
import CryptoKit

public enum ProjectReadError: Error { case malformed, tooLarge, tooDeep }

/// Bounded readers for experimental project reference extraction, never plugin execution.
public enum ProjectReader {
    public static let policyVersion = 3
    public static let maximumInputBytes = 64 * 1024 * 1024
    public static let maximumDecodedBytes = 64 * 1024 * 1024
    public static let extensions: Set<String> = [
        "rpp", "als", "logicx", "band", "ptx", "ptf", "cpr", "npr", "song",
        "flp", "bwproject", "reason", "reasonx", "rns", "dpdoc", "perf", "bak",
    ]

    public static func read(_ url: URL) -> ProjectReport {
        // A scan runs synchronously inside a long-lived utility task. Foundation
        // buffers must drain per file, rather than surviving until that task ends.
        autoreleasepool { readProject(url) }
    }

    private static func readProject(_ url: URL) -> ProjectReport {
        let ext = url.pathExtension.lowercased()
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        var ancestor = url
        while ancestor.path != "/" {
            if (try? ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return ProjectReport(path: url.path, adapter: ext, coverage: "failed", projectModifiedAt: modified,
                                     references: [], limitations: ["Project or ancestor is a symbolic link; skipped."])
            }
            ancestor.deleteLastPathComponent()
        }
        let kind: String
        if ext == "bak" {
            // Backup suffixes are admitted only after bounded format identification.
            let prefix = try? BoundedFile.read(url, limit: 4, prefixOnly: true)
            if prefix?.starts(with: Array("RIF2".utf8)) == true { kind = "cpr" }
            else if url.deletingPathExtension().pathExtension.lowercased() == "als",
                    prefix?.starts(with: [0x1f, 0x8b]) == true { kind = "als" }
            else { kind = "bak" }
        } else { kind = ext }
        if kind == "logicx" { return readLogicMetadata(url, modified: modified) }
        if kind == "ptx" {
            do {
                guard let before = LibraryScanJournal.stamp(url.path) else { throw ProjectReadError.malformed }
                let data = try BoundedFile.read(url, limit: ProToolsSavedPluginReader.maximumBytes)
                guard let plugins = ProToolsSavedPluginReader.read(data),
                      LibraryScanJournal.stamp(url.path) == before else { throw ProjectReadError.malformed }
                let savedAt = Date(timeIntervalSince1970: Double(before.modifiedSeconds) +
                    Double(before.modifiedNanoseconds) / 1_000_000_000)
                var report = ProjectReport(path: url.path, adapter: "protools-ptx-plugin-list",
                    coverage: "partial", projectModifiedAt: savedAt, references: [],
                    limitations: ["Only the observed Pro Tools saved AAX insert list is covered; nested player libraries and other session structures are not.",
                        "Modification time is the saved snapshot time, not playback time."])
                report.aaxPlugins = plugins
                report.sourceSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                report.sourceSignature = LibraryScanJournal.signature(before)
                report.readerPolicyVersion = policyVersion
                return report
            } catch {
                return ProjectReport(path: url.path, adapter: "ptx", coverage: "failed",
                    projectModifiedAt: modified, references: [], limitations: ["PTX plug-in list unavailable: \(error)"])
            }
        }
        if kind == "cpr" {
            do {
                guard let before = LibraryScanJournal.stamp(url.path) else { throw ProjectReadError.malformed }
                let data = try BoundedFile.read(url, limit: maximumInputBytes)
                let plugins = try CubaseKontaktStateReader.readPluginStates(data)
                var states: [KontaktSavedState] = []
                var unsupportedKontakt = 0
                for (ordinal, plugin) in plugins.enumerated() where
                    plugin.uid == "5653544E694B386B6F6E74616B742038" && plugin.name == "Kontakt 8" {
                    if let state = try? KontaktStateReader.read(plugin.payload) {
                        states.append(KontaktSavedState(instanceOrdinal: ordinal, libraryIDs: state.libraryIDs,
                            opaquePayloads: state.opaquePayloads, emptyRack: state.emptyRack))
                    } else { unsupportedKontakt += 1 }
                }
                var spectrasonics: [SpectrasonicsSavedState] = []
                var unsupportedSpectrasonics = 0
                var unsupportedSINE = 0
                var sineIDs: [String] = []
                for (ordinal, plugin) in plugins.enumerated() {
                    if plugin.uid == SINESavedStateReader.cubaseUID && plugin.name == "SINE Player" {
                        if let ids = SINESavedStateReader.instrumentIDs(plugin.payload) { sineIDs.append(contentsOf: ids) }
                        else { unsupportedSINE += 1 }
                    }
                    do {
                        if let state = try SpectrasonicsStateReader.read(plugin) {
                            spectrasonics.append(SpectrasonicsSavedState(instanceOrdinal: ordinal, state: state))
                        }
                    } catch { unsupportedSpectrasonics += 1 }
                }
                guard let after = LibraryScanJournal.stamp(url.path), before == after else { throw ProjectReadError.malformed }
                let savedAt = Date(timeIntervalSince1970: Double(before.modifiedSeconds) + Double(before.modifiedNanoseconds) / 1_000_000_000)
                var limitations = [
                        "Kontakt library IDs and Spectrasonics preset-library metadata only in typed Cubase 15.0.30 processor states; other project content is not covered.",
                        "Saved modification time is a snapshot proxy, not a load or playback timestamp."]
                if unsupportedSpectrasonics > 0 {
                    limitations.append("\(unsupportedSpectrasonics) Spectrasonics processor state(s) had unsupported or malformed metadata; no library absence is inferred.")
                }
                if unsupportedKontakt > 0 {
                    limitations.append("\(unsupportedKontakt) Kontakt processor state(s) had unsupported metadata; no library absence is inferred.")
                }
                if unsupportedSINE > 0 {
                    limitations.append("\(unsupportedSINE) SINE processor state(s) had unsupported metadata; no instrument absence is inferred.")
                }
                var report = ProjectReport(path: url.path, adapter: "cubase-kontakt-15.0.30", coverage: "partial",
                    projectModifiedAt: savedAt, references: [], limitations: limitations)
                report.kontaktStates = states
                report.spectrasonicsStates = spectrasonics
                report.sineInstrumentIDs = unsupportedSINE == 0 ? Array(Set(sineIDs)).sorted() : nil
                report.pluginClasses = plugins.enumerated().compactMap { ordinal, plugin in
                    guard plugin.uid.utf8.count == 32, plugin.uid.utf8.allSatisfy({
                        (48...57).contains($0) || (65...70).contains($0)
                    }) else { return nil }
                    return ProjectPluginClass(instanceOrdinal: ordinal, classID: plugin.uid, name: plugin.name)
                }
                report.sourceSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                report.sourceSignature = LibraryScanJournal.signature(before)
                report.readerPolicyVersion = policyVersion
                return report
            } catch {
                return ProjectReport(path: url.path, adapter: "cpr", coverage: "failed",
                    projectModifiedAt: modified, references: [],
                    limitations: ["Cubase Kontakt processor state could not be safely parsed: \(error)"])
            }
        }
        guard ["rpp", "als"].contains(kind) else {
            return ProjectReport(path: url.path, adapter: ext, coverage: "unsupported",
                                 projectModifiedAt: modified, references: [],
                                 limitations: ["Native project reader not implemented; no absence inference is possible."])
        }
        do {
            guard let before = LibraryScanJournal.stamp(url.path) else { throw ProjectReadError.malformed }
            let data = try BoundedFile.read(url, limit: maximumInputBytes)
            let refs: [ProjectReference]
            var states: [KontaktSavedState]? = nil
            var pluginClasses: [ProjectPluginClass]? = nil
            if kind == "als" {
                let parsed = try parseAbletonDetails(data)
                refs = parsed.0
                states = parsed.1.enumerated().map { index, state in
                    KontaktSavedState(instanceOrdinal: index, libraryIDs: state.libraryIDs,
                                      opaquePayloads: state.opaquePayloads, emptyRack: state.emptyRack)
                }
                pluginClasses = parsed.2
            } else { refs = try parseReaper(data, project: url) }
            guard LibraryScanJournal.stamp(url.path) == before else { throw ProjectReadError.malformed }
            let savedAt = Date(timeIntervalSince1970: Double(before.modifiedSeconds) + Double(before.modifiedNanoseconds) / 1_000_000_000)
            var report = ProjectReport(path: url.path, adapter: kind == "als" ? "ableton-kontakt-live12" : kind, coverage: "partial",
                                 projectModifiedAt: savedAt, references: refs,
                                 limitations: [
                                    "Experimental reader; complete dependency coverage is not established.",
                                    kind == "als" ? "Only version-gated direct-track Kontakt processor states are decoded; other plugin states are not covered." : "Opaque plugin state and nested library identities are not decoded.",
                                    "Modification time is a saved-project recency proxy, not exact use time.",
                                    kind == "als" ? "Ableton paths are candidates; relative roots and relocated media remain unresolved." : "Relative paths use the project directory; project media-path overrides remain unverified.",
                                 ])
            report.kontaktStates = states
            report.pluginClasses = pluginClasses
            report.sourceSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            report.sourceSignature = LibraryScanJournal.signature(before)
            report.readerPolicyVersion = policyVersion
            return report
        } catch {
            return ProjectReport(path: url.path, adapter: ext, coverage: "failed",
                                 projectModifiedAt: modified, references: [],
                                 limitations: ["Project could not be safely parsed: \(error)"])
        }
    }

    /// The same selected leaf must be used for parsing, cache reuse, and commit.
    static func selectedLogicProjectData(_ url: URL) throws -> URL {
        let alternatives = url.appendingPathComponent("Alternatives")
        let folders = try FileManager.default.contentsOfDirectory(at: alternatives, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent.utf8.allSatisfy { (48...57).contains($0) } &&
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let selected: URL
        if folders.count == 1 { selected = folders[0] }
        else {
            let choice = alternatives.appendingPathComponent("ActiveVariant")
            let value = String(data: try BoundedFile.read(choice, limit: 64), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, let found = folders.first(where: { $0.lastPathComponent == value }) else {
                throw ProjectReadError.malformed
            }
            selected = found
        }
        return selected.appendingPathComponent("ProjectData")
    }

    private static func readLogicMetadata(_ url: URL, modified: Date?) -> ProjectReport {
        do {
            let source = try selectedLogicProjectData(url)
            let selected = source.deletingLastPathComponent()
            let metadata = selected.appendingPathComponent("MetaData.plist")
            var ancestor = source
            while ancestor.path != "/" {
                if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                ancestor.deleteLastPathComponent()
            }
            guard let before = LibraryScanJournal.stamp(source.path) else { throw ProjectReadError.malformed }
            let projectData = try BoundedFile.read(source, limit: maximumInputBytes)
            guard let aus = LogicSavedAUReader.read(projectData),
                  LibraryScanJournal.stamp(source.path) == before else { throw ProjectReadError.malformed }
            var references: [ProjectReference] = []
            if let data = try? BoundedFile.read(metadata, limit: 1_048_576),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                for key in ["AudioFiles", "PlaybackFiles"] {
                    guard let paths = plist[key] as? [String] else { continue }
                    references += paths.filter { !$0.isEmpty }.map {
                        ProjectReference(kind: .sample, value: $0, resolvedPath: nil,
                            evidence: "Logic selected-alternative metadata \(key) candidate")
                    }
                }
            }
            let savedAt = Date(timeIntervalSince1970: Double(before.modifiedSeconds) +
                Double(before.modifiedNanoseconds) / 1_000_000_000)
            var report = ProjectReport(path: url.path, adapter: "logic-saved-au", coverage: "partial",
                projectModifiedAt: savedAt, references: references,
                limitations: ["Saved AU references may include inactive or undo state; they do not prove playback.",
                    "Selected alternative only; sample metadata paths remain unresolved."])
            report.logicAUReferences = aus.references
            report.kontaktStates = aus.kontaktStates
            report.sourcePath = source.path
            report.sourceSHA256 = SHA256.hash(data: projectData).map { String(format: "%02x", $0) }.joined()
            report.sourceSignature = LibraryScanJournal.signature(before)
            report.readerPolicyVersion = policyVersion
            return report
        } catch {
            return ProjectReport(path: url.path, adapter: "logic-metadata", coverage: "failed",
                                 projectModifiedAt: modified, references: [],
                                 limitations: ["Logic metadata unavailable or invalid: \(error)"])
        }
    }

    public static func parseReaper(_ data: Data, project: URL) throws -> [ProjectReference] {
        guard data.count <= maximumInputBytes else { throw ProjectReadError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ProjectReadError.malformed }
        var stack: [String] = []
        var refs: [ProjectReference] = []
        var started = false
        var ended = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard !ended else { throw ProjectReadError.malformed }
            if line == ">" {
                guard !stack.isEmpty else { throw ProjectReadError.malformed }
                stack.removeLast()
                if stack.isEmpty { ended = true }
                continue
            }
            if line.hasPrefix("<") {
                let fields = try tokens(String(line.dropFirst()))
                guard let type = fields.first else { throw ProjectReadError.malformed }
                if !started {
                    guard type == "REAPER_PROJECT" else { throw ProjectReadError.malformed }
                    started = true
                }
                if ["VST", "VST3", "AU", "CLAP", "JS"].contains(type),
                   isPluginContext(stack),
                   fields.count > 1 {
                    refs.append(ProjectReference(kind: .plugin, value: fields[1], resolvedPath: nil,
                                                 evidence: "RPP \(type) declaration; disabled/bypassed instances included"))
                }
                stack.append(type)
                guard stack.count <= 128 else { throw ProjectReadError.tooDeep }
            } else {
                guard started, !stack.isEmpty else { throw ProjectReadError.malformed }
                // Do not tokenize opaque plugin-state lines.
                if (line.hasPrefix("FILE ") || line.hasPrefix("FILE\t")), isSampleContext(stack) {
                    let fields = try tokens(line)
                    guard fields.count == 2, !fields[1].isEmpty else { throw ProjectReadError.malformed }
                    refs.append(ProjectReference(kind: .sample, value: fields[1],
                                                 resolvedPath: resolveReaperPath(fields[1], project: project),
                                                 evidence: "RPP SOURCE/FILE; included regardless of mute state"))
                }
            }
        }
        guard started, ended, stack.isEmpty else { throw ProjectReadError.malformed }
        return refs
    }

    private static func resolveReaperPath(_ path: String, project: URL) -> String? {
        // Windows paths and URI-like references cannot be resolved on this Mac.
        guard !path.contains("\\"), !path.contains(":"), !path.hasPrefix("~") else { return nil }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : project.deletingLastPathComponent().appendingPathComponent(path)
        return url.standardizedFileURL.path
    }

    private static func isSampleContext(_ stack: [String]) -> Bool {
        guard stack.starts(with: ["REAPER_PROJECT", "TRACK", "ITEM"]) else { return false }
        var tail = Array(stack.dropFirst(3))
        if tail.first == "TAKE" { tail.removeFirst() }
        return !tail.isEmpty && tail.allSatisfy { $0 == "SOURCE" }
    }

    private static func isPluginContext(_ stack: [String]) -> Bool {
        let contexts = [
            ["REAPER_PROJECT", "FXCHAIN"],
            ["REAPER_PROJECT", "TRACK", "FXCHAIN"],
            ["REAPER_PROJECT", "TRACK", "FXCHAIN_REC"],
            ["REAPER_PROJECT", "TRACK", "ITEM", "TAKEFX"],
            ["REAPER_PROJECT", "TRACK", "ITEM", "TAKE", "TAKEFX"],
        ]
        return contexts.contains(stack)
    }

    private static func tokens(_ line: String) throws -> [String] {
        var result: [String] = []
        var value = ""
        var quote: Character?
        var active = false
        for c in line {
            if let q = quote {
                if c == q { quote = nil } else { value.append(c) }
            } else if c == "\"" || c == "'" || c == "`" {
                guard !active else { throw ProjectReadError.malformed }
                quote = c
                active = true
            } else if c.isWhitespace {
                if active { result.append(value); value = ""; active = false }
            } else {
                value.append(c)
                active = true
            }
        }
        guard quote == nil else { throw ProjectReadError.malformed }
        if active { result.append(value) }
        return result
    }

    public static func parseAbleton(_ data: Data) throws -> [ProjectReference] {
        try parseAbletonDetails(data).0
    }

    private static func parseAbletonDetails(_ data: Data) throws -> ([ProjectReference], [KontaktStateReader.Result], [ProjectPluginClass]) {
        guard data.count <= maximumInputBytes else { throw ProjectReadError.tooLarge }
        let xml = try data.starts(with: [0x1f, 0x8b]) ? inflateGzip(data) : data
        // Restrict this experimental adapter to UTF-8 XML without any DTD. Foundation
        // may omit entity callbacks when external resolution is disabled.
        guard String(data: xml, encoding: .utf8) != nil,
              !containsDocumentType(xml) else {
            throw ProjectReadError.malformed
        }
        let delegate = AbletonDelegate()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil, delegate.validRoot,
              delegate.stack.isEmpty, !delegate.rejected else { throw ProjectReadError.malformed }
        return (delegate.references, delegate.kontaktStates, delegate.pluginClasses)
    }

    // XML's declaration token is ASCII. Unicode case folding over the entire
    // decoded project is unnecessary and expensive for large opaque plug-in states.
    // Keep the conservative case-insensitive rejection without allocating per character.
    private static func containsDocumentType(_ data: Data) -> Bool {
        let marker: [UInt8] = Array("<!DOCTYPE".utf8)
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard bytes.count >= marker.count else { return false }
            for start in 0...(bytes.count - marker.count) where bytes[start] == marker[0] {
                var matches = true
                for offset in 1..<marker.count {
                    let byte = bytes[start + offset]
                    let upper = (97...122).contains(byte) ? byte - 32 : byte
                    if upper != marker[offset] { matches = false; break }
                }
                if matches { return true }
            }
            return false
        }
    }

    private static func inflateGzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ProjectReadError.malformed
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { output in
                    stream.next_out = output.baseAddress
                    stream.avail_out = uInt(output.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = buffer.count - Int(stream.avail_out)
                guard result.count + produced <= maximumDecodedBytes else { throw ProjectReadError.tooLarge }
                result.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw ProjectReadError.malformed }
                    return result
                }
                guard status == Z_OK, produced > 0 else { throw ProjectReadError.malformed }
            }
        }
    }
}

private final class AbletonDelegate: NSObject, XMLParserDelegate {
    private struct KontaktDevice {
        var name: String?
        var uid: [String: String] = [:]
        var processorHex: String?
    }
    var stack: [String] = []
    var references: [ProjectReference] = []
    var kontaktStates: [KontaktStateReader.Result] = []
    var pluginClasses: [ProjectPluginClass] = []
    var validRoot = false
    var rejected = false
    private var supportsVst3Candidates = false
    private var kontaktDevice: KontaktDevice?
    private var processorText: String?
    private let kontaktUID = ["Fields.0": "1448301646", "Fields.1": "1766537323",
                              "Fields.2": "1869509729", "Fields.3": "1802772536"]

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if stack.isEmpty {
            validRoot = name == "Ableton"
            // Host-generated Live 12 fixture, not a vendor-stable XML schema.
            // Unknown schemas retain existing sample coverage, not guessed plugins.
            supportsVst3Candidates = validRoot && attributes["MajorVersion"] == "5"
                && attributes["MinorVersion"] == "12.0_12402"
                && attributes["Creator"]?.hasPrefix("Ableton Live 12.") == true
        }
        stack.append(name)
        guard stack.count <= 128 else { rejected = true; parser.abortParsing(); return }
        if supportsVst3Candidates, isDirectTrackVst3Info {
            kontaktDevice = KontaktDevice()
        }
        if kontaktDevice != nil, stack.count == 12,
           stack.suffix(2).elementsEqual(["Uid", name]), name.hasPrefix("Fields."),
           let value = attributes["Value"] {
            guard kontaktDevice?.uid[name] == nil else { rejected = true; parser.abortParsing(); return }
            kontaktDevice?.uid[name] = value
        }
        if kontaktDevice != nil, stack.count == 13,
           stack.suffix(4).elementsEqual(["Vst3PluginInfo", "Preset", "Vst3Preset", "ProcessorState"]) {
            processorText = ""
        }
        guard let value = attributes["Value"], !value.isEmpty else { return }
        if supportsVst3Candidates, isDirectTrackVst3Name,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kontaktDevice?.name = value
            references.append(ProjectReference(kind: .plugin, value: value, resolvedPath: nil,
                evidence: "ALS Live 12 direct-track Vst3PluginInfo/Name candidate; saved descriptor only, installed identity and successful load unverified"))
        }
        if stack.suffix(3).elementsEqual(["SampleRef", "FileRef", name]), ["Path", "RelativePath"].contains(name) {
            let ownedTrack = stack.prefix(3).elementsEqual(["Ableton", "LiveSet", "Tracks"])
                && stack.contains(where: { ["AudioTrack", "MidiTrack", "ReturnTrack"].contains($0) })
            let exact = name == "Path" && ownedTrack && value.hasPrefix("/")
                && !value.contains("\0") && !value.contains("\\")
            references.append(ProjectReference(kind: .sample, value: value,
                                               resolvedPath: exact ? URL(fileURLWithPath: value).standardizedFileURL.path : nil,
                                               evidence: exact ? "ALS Live 12 track SampleRef/FileRef/Path exact current path"
                                                   : "ALS SampleRef/FileRef/\(name) candidate"))
        }
        if stack.suffix(3).elementsEqual(["SampleRef", "FileRef", "Name"]) {
            // Observed in older user-authorized ALS files. A saved filename alone is
            // evidence of a candidate, never enough to identify a local sample.
            references.append(ProjectReference(kind: .sample, value: value, resolvedPath: nil,
                                               evidence: "Legacy ALS SampleRef/FileRef/Name candidate; location unresolved"))
        }
        // Direct descriptor observed in host-saved Live projects. A display-name
        // candidate only; never interpret opaque preset or track-name fields.
        if name == "PlugName", stack.suffix(2).elementsEqual(["VstPluginInfo", "PlugName"]),
           stack.contains("PluginDesc"), stack.contains("PluginDevice") {
            references.append(ProjectReference(kind: .plugin, value: value, resolvedPath: nil,
                                               evidence: "ALS VstPluginInfo/PlugName saved descriptor; installation identity unresolved"))
        }
    }

    /// Only the demonstrated direct track route. No browser, history, preset,
    /// master or nested-rack guesses; bypassed/placeholder declarations remain
    /// candidates, never evidence of a successful load.
    private var isDirectTrackVst3Name: Bool {
        guard stack.count == 11,
              stack.prefix(3).elementsEqual(["Ableton", "LiveSet", "Tracks"]),
              ["AudioTrack", "MidiTrack", "ReturnTrack"].contains(stack[3]) else { return false }
        return stack.suffix(7).elementsEqual([
            "DeviceChain", "DeviceChain", "Devices", "PluginDevice", "PluginDesc", "Vst3PluginInfo", "Name",
        ])
    }

    private var isDirectTrackVst3Info: Bool {
        stack.count == 10 && stack.prefix(3).elementsEqual(["Ableton", "LiveSet", "Tracks"])
            && ["AudioTrack", "MidiTrack", "ReturnTrack"].contains(stack[3])
            && stack.suffix(6).elementsEqual([
                "DeviceChain", "DeviceChain", "Devices", "PluginDevice", "PluginDesc", "Vst3PluginInfo"])
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard processorText != nil else { return }
        guard processorText!.utf8.count + string.utf8.count <= 2 * (KontaktStateReader.maximumBytes + 4) else {
            rejected = true; parser.abortParsing(); return
        }
        processorText! += string
    }

    private func decodeProcessor(_ text: String) throws -> KontaktStateReader.Result {
        let hex = text.utf8.filter { ![10, 13, 32, 9].contains($0) }
        guard hex.count.isMultiple(of: 2), hex.count <= 2 * (KontaktStateReader.maximumBytes + 4) else {
            throw ProjectReadError.tooLarge
        }
        var bytes = [UInt8](); bytes.reserveCapacity(hex.count / 2)
        for index in stride(from: 0, to: hex.count, by: 2) {
            func nibble(_ byte: UInt8) -> UInt8? {
                switch byte { case 48...57: byte - 48; case 65...70: byte - 55; case 97...102: byte - 87; default: nil }
            }
            guard let high = nibble(hex[index]), let low = nibble(hex[index + 1]) else { throw ProjectReadError.malformed }
            bytes.append((high << 4) | low)
        }
        guard bytes.count >= 16,
              bytes[4...7].allSatisfy({ $0 == 0 }),
              Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24 == bytes.count else {
            throw ProjectReadError.malformed
        }
        return try KontaktStateReader.read(Data(bytes))
    }

    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
        if didEndElement == "ProcessorState", let processorText {
            guard kontaktDevice?.processorHex == nil else { rejected = true; parser.abortParsing(); return }
            kontaktDevice?.processorHex = processorText
            self.processorText = nil
        }
        if didEndElement == "Vst3PluginInfo", isDirectTrackVst3Info, let device = kontaktDevice {
            if let name = device.name, !name.isEmpty, pluginClasses.count < 4096, device.uid.count == 4 {
                let words = ["Fields.0", "Fields.1", "Fields.2", "Fields.3"].map { key -> UInt32? in
                    guard let value = device.uid[key], let signed = Int32(value) else { return nil }
                    return UInt32(bitPattern: signed)
                }
                if words.allSatisfy({ $0 != nil }) {
                    let raw = words.compactMap { $0 }.map { String(format: "%08X", $0) }.joined()
                    let cid = [raw.prefix(8), raw.dropFirst(8).prefix(4), raw.dropFirst(12).prefix(4),
                               raw.dropFirst(16).prefix(4), raw.dropFirst(20)].map(String.init).joined(separator: "-")
                    pluginClasses.append(ProjectPluginClass(instanceOrdinal: pluginClasses.count, classID: cid, name: name))
                }
            }
            if device.name == "Kontakt 8", device.uid == kontaktUID {
                do {
                    guard let hex = device.processorHex, kontaktStates.count < 4096 else { throw ProjectReadError.malformed }
                    kontaktStates.append(try decodeProcessor(hex))
                } catch { rejected = true; parser.abortParsing(); return }
            }
            kontaktDevice = nil
        }
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName: String, value: String?) {
        rejected = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName: String, publicID: String?, systemID: String?) {
        rejected = true
        parser.abortParsing()
    }
}
