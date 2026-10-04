import Foundation

/// A presentation grouping, not proof of shared ownership or interchangeable formats.
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
    private static func familyIdentifier(_ asset: Asset) -> String {
        guard var id = asset.bundleIdentifier?.lowercased(), !id.isEmpty else { return "unidentified:" + asset.path }
        // Verified installed vendor namespaces. Product display name (including
        // version) remains part of the outer key; only the format-specific ID varies.
        for vendor in ["arturia", "fabfilter", "plugin-alliance", "pluginalliance", "native-instruments", "spectrasonics", "softube", "plogue", "overloud", "tailorednoise"] {
            if id.hasPrefix("com." + vendor + ".") { return "vendor:" + vendor }
        }
        if id.hasPrefix("com.soundtoys.") {
            let parts = id.split(separator: ".").map(String.init)
            if parts.count == 4, ["vst", "vst3", "audiounit", "aax"].contains(parts[2]) {
                return "com.soundtoys." + parts[3]
            }
        }
        let product = normalizedName(asset.name)
        if ["kontakt", "kontakt 7", "kontakt 8", "battery 4", "reaktor 6"].contains(product),
           [".synth.vst", ".musicdevice.component", ".aaxplugin", ".vst3"].contains(where: { id == product + $0 }) {
            return "vendor:native-instruments"
        }
        // Preserve the full namespace, including hosted reverse-domain owners.
        // Only explicit terminal format tokens vary across supported installations.
        for token in ["audiounit", "component", "aaxplugin", "vst3", "vst2", "clap", "aax", "vst", "au"] {
            if [".", "-", "_"].contains(where: { id.hasSuffix($0 + token) }) { id.removeLast(token.count + 1); break }
        }
        return id.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
    }
    public static func group(_ assets: [Asset]) -> [PluginProduct] {
        let names = Dictionary(grouping: assets.filter { $0.kind == .plugin }, by: { normalizedName($0.name) })
        var result: [PluginProduct] = []
        for (name, members) in names {
            let groups = Dictionary(grouping: members, by: familyIdentifier)
            for (maker, installations) in groups {
                let ordered = installations.sorted { $0.path < $1.path }
                result.append(PluginProduct(id: name + "|" + maker, name: ordered[0].name, installations: ordered))
            }
        }
        return result.sorted { $0.id < $1.id }
    }
}
