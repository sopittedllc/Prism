import Foundation
import CZlib

public enum ProjectReadError: Error { case malformed, tooLarge, tooDeep }

/// Bounded readers for experimental project reference extraction, never plugin execution.
public enum ProjectReader {
    public static let maximumInputBytes = 32 * 1024 * 1024
    public static let maximumDecodedBytes = 64 * 1024 * 1024
    public static let extensions: Set<String> = [
        "rpp", "als", "logicx", "band", "ptx", "ptf", "cpr", "npr", "song",
        "flp", "bwproject", "reason", "reasonx", "rns", "dpdoc", "perf",
    ]

    public static func read(_ url: URL) -> ProjectReport {
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
        if ext == "logicx" { return readLogicMetadata(url, modified: modified) }
        guard ["rpp", "als"].contains(ext) else {
            return ProjectReport(path: url.path, adapter: ext, coverage: "unsupported",
                                 projectModifiedAt: modified, references: [],
                                 limitations: ["Native project reader not implemented; no absence inference is possible."])
        }
        do {
            let data = try BoundedFile.read(url, limit: maximumInputBytes)
            let refs = try ext == "rpp" ? parseReaper(data, project: url) : parseAbleton(data)
            return ProjectReport(path: url.path, adapter: ext, coverage: "partial",
                                 projectModifiedAt: modified, references: refs,
                                 limitations: [
                                    "Experimental reader; complete dependency coverage is not established.",
                                    "Opaque plugin state and nested library identities are not decoded.",
                                    "Modification time is a saved-project recency proxy, not exact use time.",
                                    ext == "als" ? "Ableton paths are candidates; relative roots and relocated media remain unresolved." : "Relative paths use the project directory; project media-path overrides remain unverified.",
                                 ])
        } catch {
            return ProjectReport(path: url.path, adapter: ext, coverage: "failed",
                                 projectModifiedAt: modified, references: [],
                                 limitations: ["Project could not be safely parsed: \(error)"])
        }
    }

    private static func readLogicMetadata(_ url: URL, modified: Date?) -> ProjectReport {
        do {
            let metadata = url.appendingPathComponent("Alternatives/000/MetaData.plist")
            var ancestor = metadata
            while ancestor.path != "/" {
                if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                ancestor.deleteLastPathComponent()
            }
            let data = try BoundedFile.read(metadata, limit: maximumInputBytes)
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw ProjectReadError.malformed
            }
            var references: [ProjectReference] = []
            for key in ["AudioFiles", "PlaybackFiles"] {
                guard let value = plist[key] else { continue }
                guard let paths = value as? [String] else { throw ProjectReadError.malformed }
                references += paths.filter { !$0.isEmpty }.map {
                    ProjectReference(kind: .sample, value: $0, resolvedPath: nil,
                                     evidence: "Logic Alternatives/000/MetaData.plist \(key) candidate")
                }
            }
            return ProjectReport(path: url.path, adapter: "logic-metadata", coverage: "partial",
                                 projectModifiedAt: modified, references: references,
                                 limitations: ["Metadata candidates only; alternative 000 is not proven active.",
                                               "UnusedAudioFiles, backups, other alternatives, and plugin state are excluded.",
                                               "Saved paths may be stale; no automatic asset matching."])
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
        guard data.count <= maximumInputBytes else { throw ProjectReadError.tooLarge }
        let xml = try data.starts(with: [0x1f, 0x8b]) ? inflateGzip(data) : data
        // Restrict this experimental adapter to UTF-8 XML without any DTD. Foundation
        // may omit entity callbacks when external resolution is disabled.
        guard let text = String(data: xml, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else {
            throw ProjectReadError.malformed
        }
        let delegate = AbletonDelegate()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil, delegate.validRoot,
              delegate.stack.isEmpty, !delegate.rejected else { throw ProjectReadError.malformed }
        return delegate.references
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
    var stack: [String] = []
    var references: [ProjectReference] = []
    var validRoot = false
    var rejected = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if stack.isEmpty { validRoot = name == "Ableton" }
        stack.append(name)
        guard stack.count <= 128 else { rejected = true; parser.abortParsing(); return }
        guard let value = attributes["Value"], !value.isEmpty else { return }
        if stack.suffix(3).elementsEqual(["SampleRef", "FileRef", name]), ["Path", "RelativePath"].contains(name) {
            // Even absolute ALS paths may be stale after collect-and-save. Report candidates,
            // but do not auto-match until FileRef path-type semantics are verified.
            references.append(ProjectReference(kind: .sample, value: value, resolvedPath: nil,
                                               evidence: "ALS SampleRef/FileRef/\(name) candidate"))
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

    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
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
