import Foundation

public struct ProToolsBoundPluginUse: Sendable, Equatable {
    public let use: ProToolsPluginUse
    public let pluginPath: String
}

public enum ProToolsUsageCollector {
    public static let maximumLogBytes = 32 * 1024 * 1024
    public static func collect(assets: [Asset], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> (uses: [ProToolsBoundPluginUse], failures: Int) {
        let root = home.appendingPathComponent("Library/Logs/Avid")
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return ([], 0) }
        let candidates = Dictionary(grouping: assets.filter { $0.kind == .plugin && $0.format == "aaxplugin" && $0.catalogStale != true && $0.catalogID != nil }, by: { $0.name })
        var output: [ProToolsBoundPluginUse] = [], failures = 0
        for file in files.filter({ $0.lastPathComponent.hasPrefix("Pro_Tools_") && $0.pathExtension.lowercased() == "txt" }).sorted(by: { $0.path > $1.path }).prefix(16) {
            guard let data = try? BoundedFile.read(file, limit: maximumLogBytes), let uses = try? ProToolsUsageLog.parse(data) else { failures += 1; continue }
            for use in uses {
                guard let matches = candidates[use.name], matches.count == 1 else { failures += 1; continue }
                let path = matches[0].path
                output.append(ProToolsBoundPluginUse(use: use, pluginPath: path))
            }
        }
        var seen = Set<String>(); output = output.filter { seen.insert($0.use.eventID).inserted }
        return (output, failures)
    }
}
