import Foundation
import Darwin

/// Filesystem identity captured at discovery; no executable is loaded.
public struct PluginFileIdentity: Codable, Sendable, Equatable {
    let device: Int32
    let inode: UInt64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    public static func read(_ path: String) -> PluginFileIdentity? {
        var value = stat()
        guard lstat(path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { return nil }
        return PluginFileIdentity(device: value.st_dev, inode: value.st_ino,
            modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanos: Int64(value.st_mtimespec.tv_nsec),
            changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanos: Int64(value.st_ctimespec.tv_nsec))
    }
}

public struct PluginRemovalResult: Sendable {
    public let path: String
    public let trashPath: String?
    public let error: String?
    public var succeeded: Bool { error == nil }
}

/// Runs on a worker. Moves explicit, unchanged bundle directories to macOS Trash;
/// never permanently deletes, escalates privileges, or removes related content.
public enum PluginRemoval {
    public static func validationError(_ asset: Asset) -> String? {
        let url = URL(fileURLWithPath: asset.path)
        guard asset.kind == .plugin, ["component", "vst", "vst3", "aaxplugin", "clap"].contains(asset.format),
              url.pathExtension.lowercased() == asset.format, asset.path.hasPrefix("/"),
              url.standardizedFileURL.path == asset.path else { return "Only scanned plugin bundles can be removed." }
        var ancestor = url
        while ancestor.path != "/" {
            var info = stat()
            guard lstat(ancestor.path, &info) == 0 else { return "Location is unavailable. Scan again before removing it." }
            guard info.st_mode & S_IFMT != S_IFLNK else { return "Linked locations cannot be removed. Review the original in Finder." }
            ancestor.deleteLastPathComponent()
        }
        guard let expected = asset.fileIdentity, expected == PluginFileIdentity.read(asset.path) else {
            return "This installation changed or is unavailable. Scan again before removing it."
        }
        return nil
    }
    public static func moveToTrash(_ assets: [Asset]) -> [PluginRemovalResult] {
        perform(assets) { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            return destination?.path
        }
    }
    // Injectable operation for failure-path tests. Production always uses macOS Trash.
    static func perform(_ assets: [Asset], trash: (URL) throws -> String?) -> [PluginRemovalResult] {
        var seen = Set<String>()
        return assets.filter { seen.insert($0.path).inserted }.map { asset in
            let overlap = assets.contains { $0.path != asset.path && (asset.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(asset.path + "/")) }
            if let error = overlap ? "Overlapping bundle paths cannot be removed together." : validationError(asset) {
                return PluginRemovalResult(path: asset.path, trashPath: nil, error: error)
            }
            do {
                let destination = try trash(URL(fileURLWithPath: asset.path))
                return PluginRemovalResult(path: asset.path, trashPath: destination, error: nil)
            } catch {
                return PluginRemovalResult(path: asset.path, trashPath: nil, error: "Could not move to Trash: \(error.localizedDescription) The installation was kept; review permissions in Finder.")
            }
        }
    }
}
