import Foundation

/// Vendor-authored VST3 class categories, narrowed to facts shared by the bundle's
/// Audio Module classes when no single class identity is available.
public struct VST3CategoryMetadata: Codable, Sendable, Equatable {
    public let subCategories: [String]
    public let metadata: MusicalMetadata
    /// Vendor-authored module identity; absent for older payloads or conflicting classes.
    public let vendor: String?
    public init(subCategories: [String], metadata: MusicalMetadata, vendor: String? = nil) {
        self.subCategories = subCategories
        self.metadata = metadata
        self.vendor = vendor
    }
}

/// Reads only the documented VST3 module descriptor. It never loads plugin code.
public enum VST3ModuleInfoReader {
    public static let maximumBytes = 1_048_576
    private enum Lookup { case found(VST3CategoryMetadata), unavailable, invalid }
    private static let knownCategories: [String: (MusicalFacet, String)] = [
        "fx": (.function, "fx"), "analyzer": (.function, "analyzer"),
        "delay": (.function, "delay"), "distortion": (.function, "distortion"),
        "dynamics": (.function, "dynamics"), "eq": (.function, "eq"),
        "filter": (.function, "filter"), "generator": (.function, "generator"),
        "mastering": (.function, "mastering"), "modulation": (.function, "modulation"),
        "pitch shift": (.function, "pitch shift"), "restoration": (.function, "restoration"),
        "reverb": (.function, "reverb"), "surround": (.function, "surround"),
        "tools": (.function, "tools"), "network": (.function, "network"),
        "spatial": (.function, "spatial"), "instrument": (.instrument, "instrument"),
        "synth": (.instrument, "synth"), "sampler": (.instrument, "sampler"),
        "drum": (.instrument, "drum"), "drums": (.instrument, "drums")
    ]

    public static func read(bundle: URL) -> VST3CategoryMetadata? {
        if case .found(let value) = lookup(bundle: bundle) { return value }
        return nil
    }

    private static func lookup(bundle: URL, cache: DecodedFactCache? = nil) -> Lookup {
        if let cache {
            let paths = [bundle, bundle.appendingPathComponent("Contents/Resources/moduleinfo.json"),
                         bundle.appendingPathComponent("Contents/moduleinfo.json")]
            let cached: DecodedFactCache.Result<VST3CategoryMetadata> = cache.checkedValue(policy: "vst3-module-v1", paths: paths, read: {
                if case .found(let result) = lookupUncached(bundle: bundle) { return result }
                return nil
            })
            switch cached {
            case .value(let metadata): return .found(metadata)
            case .unstable: return .invalid
            case .unavailable: break
            }
            // A miss can also mean cancellation or a dependency changed while
            // decoding. The fallback gets its own stable-source check.
            guard !Task<Never, Never>.isCancelled else { return .invalid }
            let before = paths.map { LibraryScanJournal.stamp($0.path) }
            let result = lookupUncached(bundle: bundle)
            guard !Task<Never, Never>.isCancelled,
                  before == paths.map({ LibraryScanJournal.stamp($0.path) }) else { return .invalid }
            return result
        }
        return lookupUncached(bundle: bundle)
    }

    private static func lookupUncached(bundle: URL) -> Lookup {
        guard bundle.pathExtension.lowercased() == "vst3" else { return .invalid }
        guard LibraryMetadataReader.safe(bundle) else { return .invalid }
        let candidates = ["Contents/Resources/moduleinfo.json", "Contents/moduleinfo.json"]
        for relative in candidates {
            let url = bundle.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard LibraryMetadataReader.safe(url) else { return .invalid }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes { return .invalid }
            guard let data = try? BoundedFile.read(url, limit: maximumBytes) else { return .unavailable }
            guard let root = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any],
                  let classes = root["Classes"] as? [[String: Any]] else { return .invalid }
            let audioClasses = classes.filter { $0["Category"] as? String == "Audio Module Class" }
            guard !audioClasses.isEmpty else { return .invalid }
            let names = audioClasses.compactMap { $0["Vendor"] as? String }
            let factory = (root["Factory Info"] as? [String: Any])?["Vendor"] as? String
            let stated = factory ?? names.first
            let vendor = stated.flatMap { value in
                (factory != nil || names.count == audioClasses.count) &&
                    value.utf8.count <= 128 && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    names.allSatisfy({ $0 == value }) ? value : nil
            }
            let classCategories: [[String]] = audioClasses.map { item in
                let values = item["Sub Categories"] as? [String] ?? []
                return Array(Set(values.compactMap(canonicalCategory))).sorted()
            }
            // Without an exact class selection, only the intersection is a safe
            // product-level fact; categories from sibling classes are not unioned.
            let shared = classCategories.dropFirst().reduce(Set(classCategories[0])) { $0.intersection($1) }
            guard !shared.isEmpty || vendor != nil else { return .invalid }
            let pairs = shared.compactMap { knownCategories[$0.lowercased()] }
            var fields: [String: [String]] = [:]
            for (facet, value) in pairs { fields[facet.rawValue, default: []].append(value) }
            guard let metadata = try? MusicalMetadata(fields: fields).validated() else { return .invalid }
            return .found(VST3CategoryMetadata(subCategories: shared.sorted(), metadata: metadata, vendor: vendor))
        }
        return .unavailable
    }

    /// Adds current exact local facts on restore as well as on new scans; callers
    /// perform this bounded filesystem read on a worker actor.
    public static func enrich(_ assets: [Asset], cacheBaseURL: URL? = nil) -> [Asset] {
        let cache = cacheBaseURL.flatMap(DecodedFactCache.init(baseURL:))
        return enrich(assets, cache: cache)
    }

    static func enrich(_ assets: [Asset], cache: DecodedFactCache?) -> [Asset] {
        return assets.map { original in
            guard original.kind == .plugin, original.format.lowercased() == "vst3" else { return original }
            var asset = original
            switch lookup(bundle: URL(fileURLWithPath: asset.path), cache: cache) {
            case .found(let metadata): asset.vst3Categories = metadata
            case .unavailable: break // Keep validated cached vendor facts while the bundle is offline.
            case .invalid: asset.vst3Categories = nil // Readable but changed/malformed facts fail closed.
            }
            return asset
        }
    }

    private static func canonicalCategory(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = clean.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard clean.utf8.count <= 80, !clean.contains(where: \.isNewline), knownCategories[key] != nil else { return nil }
        return key
    }
}
