import Foundation

/// One durable catalog item with subordinate physical format installations.
public struct PluginProduct: Sendable {
    public let id: String
    public let name: String
    public let installations: [Asset]
    public var representative: Asset { installations[0] }
    public var formats: String { Set(installations.map { Self.formatName($0.format) }).sorted().joined(separator: ", ") }
    public static func formatName(_ ext: String) -> String {
        switch ext.lowercased() { case "component": return "AU"; case "vst": return "VST2"; case "aaxplugin": return "AAX"; default: return ext.uppercased() }
    }
    public static func normalizedName(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in [" (vst3)", " (vst2)", " (vst)", " (au)", " (aax)", " (clap)", " vst3", " vst2", " au", " aax", " clap"] {
            if value.hasSuffix(suffix) { value.removeLast(suffix.count); break }
        }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func verifiedIdentity(_ asset: Asset) -> String? {
        guard var id = asset.bundleIdentifier?.lowercased(), !id.isEmpty else { return nil }
        // Only product-specific identifiers and explicit format aliases may own
        // persistent history. A broad vendor namespace would merge unrelated items.
        if id.hasPrefix("com.fabfilter.") {
            var parts = id.split(separator: ".").map(String.init)
            let formats = Set(["aax", "aaxplugin", "au", "audiounit", "clap", "component", "vst", "vst2", "vst3"])
            if parts.count >= 5, parts.last?.allSatisfy(\.isNumber) == true,
               formats.contains(parts[parts.count - 2]) {
                let version = parts.removeLast()
                parts.removeLast()
                if parts.last == "mono" { parts.removeLast() }
                if parts.count > 2 { return (parts + [version]).joined(separator: ".") }
            }
        }
        if id.hasPrefix("com.soundtoys.") {
            let parts = id.split(separator: ".").map(String.init)
            if parts.count == 4, ["vst", "vst3", "audiounit", "aax"].contains(parts[2]) {
                return "com.soundtoys." + parts[3]
            }
        }
        if id.hasPrefix("com.arturia.") {
            let parts = id.split(separator: ".").map(String.init)
            if parts.count == 4, ["component", "aax"].contains(parts[2]) {
                return "com.arturia." + parts[3]
            }
        }
        if id.hasPrefix("com.plugin-alliance.") {
            var parts = id.split(separator: ".").map(String.init)
            if parts.count == 4, ["au", "vst", "vst2", "vst3", "aax", "aaxplugin"].contains(parts[2]) {
                parts.remove(at: 2)
                // The vendor ships bx_digital V3 and its mix topology as variants
                // of one reviewed product. Keep every installation name intact.
                if parts.last == "bxdigitalv3mix" { parts[parts.count - 1] = "bxdigitalv3" }
                return parts.joined(separator: ".")
            }
        }
        if id.hasPrefix("com.softube.") {
            for suffix in ["_vst_au_protect_vst3", "_vst_au_protect_au", "_vst_au_protect", "_aax_protect"] {
                if id.hasSuffix(suffix) {
                    id.removeLast(suffix.count)
                    return id.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
                }
            }
        }
        // Preserve the full namespace, including hosted reverse-domain owners.
        // Only explicit terminal format tokens vary across supported installations.
        for token in ["audiounit", "component", "aaxplugin", "vst3", "vst2", "clap", "aax", "vst", "au"] {
            if [".", "-", "_"].contains(where: { id.hasSuffix($0 + token) }) { id.removeLast(token.count + 1); break }
        }
        let result = id.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return result.isEmpty ? nil : result
    }
    public static func group(_ assets: [Asset], names: [String: String] = [:]) -> [PluginProduct] {
        let groups = Dictionary(grouping: assets.filter { $0.kind == .plugin }) { asset in
            verifiedIdentity(asset).map { "verified:" + $0 }
                ?? asset.pluginProductID
                ?? "unsaved:path:" + asset.path
        }
        let result = groups.map { groupingKey, installations in
            let primaryDigitalV3 = groupingKey == "verified:com.plugin-alliance.bxdigitalv3"
                ? installations.first { $0.bundleIdentifier?.lowercased().hasSuffix(".bxdigitalv3") == true }
                : nil
            let ordered = installations.sorted {
                if let primaryDigitalV3 {
                    let lhsPrimary = $0.path == primaryDigitalV3.path
                    let rhsPrimary = $1.path == primaryDigitalV3.path
                    if lhsPrimary != rhsPrimary { return lhsPrimary }
                }
                return $0.path < $1.path
            }
            // A newer verified alias can repair presentation before a scoped rescan
            // consolidates legacy persisted product IDs. Keep one real saved ID as
            // the subject so edits remain durable during that transition.
            let id = ordered.compactMap(\.pluginProductID).first
                ?? groupingKey.replacingOccurrences(of: "verified:", with: "unsaved:")
            let name = primaryDigitalV3?.name
                ?? names[id]
                ?? ordered.compactMap { $0.pluginProductID.flatMap { names[$0] } }.first
                ?? ordered[0].name
            return PluginProduct(id: id, name: name, installations: ordered)
        }
        return result.sorted { $0.id < $1.id }
    }
}
