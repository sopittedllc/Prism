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
            asset.pluginProductID ?? (verifiedIdentity(asset).map { "unsaved:" + $0 } ?? "unsaved:path:" + asset.path)
        }
        let result = groups.map { key, installations in
            let ordered = installations.sorted { $0.path < $1.path }
            return PluginProduct(id: key, name: names[key] ?? ordered[0].name, installations: ordered)
        }
        return result.sorted { $0.id < $1.id }
    }
}
