import Foundation

public struct CubaseBoundPluginUse: Sendable, Equatable {
    public let use: CubasePluginUse
    public let pluginPath: String
    public let cid: String
}

public struct CubaseUsageCollection: Sendable, Equatable {
    public let uses: [CubaseBoundPluginUse]
    public let failures: Int
    public let unavailable: Bool
}

/// Reads only Cubase's local Usage Logger and VST3 cache. It does not enable logging,
/// open projects, execute plugins, or transmit source data.
public enum CubaseUsageCollector {
    public static let maximumLogBytes = 64 * 1024 * 1024
    public static func collect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CubaseUsageCollection {
        let logRoot = home.appendingPathComponent("Library/Logs/Steinberg/usagelogger")
        let cache = home.appendingPathComponent("Library/Preferences/Cubase 15/Cubase Pro VST3 Cache (arm64)/vst3plugins.xml")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: logRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return CubaseUsageCollection(uses: [], failures: 0, unavailable: true)
        }
        guard let classes = try? CubasePluginCache.read(cache) else {
            return CubaseUsageCollection(uses: [], failures: 1, unavailable: true)
        }
        var uses: [CubaseBoundPluginUse] = [], failures = 0, total = 0
        for url in entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }).prefix(16) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber, size.intValue <= maximumLogBytes,
                  let data = try? Data(contentsOf: url), data.count <= maximumLogBytes else { failures += 1; continue }
            total += data.count; guard total <= 256 * 1024 * 1024 else { failures += 1; break }
            guard let parsed = try? CubaseUsageLog.parse(data) else { failures += 1; continue }
            for use in parsed {
                let matches = CubasePluginCache.bindings(for: use, in: classes)
                guard matches.count == 1 else { failures += 1; continue }
                uses.append(CubaseBoundPluginUse(use: use, pluginPath: matches[0].path, cid: matches[0].cid))
            }
        }
        var seen = Set<String>(); uses = uses.filter { seen.insert($0.use.eventID).inserted }
        return CubaseUsageCollection(uses: uses, failures: failures, unavailable: false)
    }
}
