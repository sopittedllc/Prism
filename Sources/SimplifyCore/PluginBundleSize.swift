import Foundation
import Darwin

/// Metadata-only logical byte measurement for one plugin bundle. A nil result is
/// deliberately unknown: no partial sum is published when traversal is incomplete.
enum PluginBundleSize {
    static let maximumBundleEntries = 4_096
    static let maximumBundleDepth = 24
    static let maximumBundleSeconds = 0.25
    static let maximumPassEntries = 100_000
    static let maximumPassSeconds = 8.0

    struct Pass {
        var entries = 0
        var startedAt: TimeInterval?
        var exhausted = false
    }
    struct Result { let bytes: Int?; let issue: String? }

    static func checkedSum(_ total: Int, _ bytes: Int) -> Int? {
        guard bytes >= 0 else { return nil }
        let (next, overflow) = total.addingReportingOverflow(bytes)
        return overflow ? nil : next
    }

    private struct Signature: Equatable {
        let device: UInt64
        let inode: UInt64
        let mode: mode_t
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init?(_ url: URL) {
            var item = stat()
            guard lstat(url.path, &item) == 0 else { return nil }
            device = UInt64(item.st_dev); inode = UInt64(item.st_ino)
            mode = item.st_mode; size = item.st_size
            modifiedSeconds = item.st_mtimespec.tv_sec
            modifiedNanoseconds = item.st_mtimespec.tv_nsec
            changedSeconds = item.st_ctimespec.tv_sec
            changedNanoseconds = item.st_ctimespec.tv_nsec
        }
        var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
        var isRegular: Bool { mode & S_IFMT == S_IFREG }
        var isSymlink: Bool { mode & S_IFMT == S_IFLNK }
    }

    /// Complete traversal is used for library installations; plugin startup keeps
    /// its existing budgets. Both modes retain cancellation and consistency checks.
    static func measure(_ bundle: URL, pass: inout Pass, complete: Bool = false,
                        progress: ((Int) -> Void)? = nil) -> Result {
        let clock = ProcessInfo.processInfo.systemUptime
        if pass.startedAt == nil { pass.startedAt = clock }
        guard complete || !pass.exhausted else { return Result(bytes: nil, issue: "Plugin size pass limit reached") }
        let bundleStart = clock
        var visited: [(URL, Signature)] = []
        var distinctFiles = Set<String>()
        var sum = 0
        var bundleEntries = 0
        func budget() -> String? {
            if Task<Never, Never>.isCancelled { return "Plugin size measurement cancelled" }
            if complete { return nil }
            if bundleEntries >= maximumBundleEntries { return "Plugin size entry limit reached" }
            if pass.entries >= maximumPassEntries { pass.exhausted = true; return "Plugin size pass entry limit reached" }
            let now = ProcessInfo.processInfo.systemUptime
            if now - bundleStart >= maximumBundleSeconds { return "Plugin size time limit reached" }
            if now - pass.startedAt! >= maximumPassSeconds { pass.exhausted = true; return "Plugin size pass time limit reached" }
            return nil
        }
        func account(_ url: URL) -> String? {
            if let reason = budget() { return reason }
            bundleEntries += 1; pass.entries += 1
            if bundleEntries % 512 == 0 { progress?(bundleEntries) }
            guard let signature = Signature(url) else { return "Plugin size metadata unavailable" }
            if !signature.isDirectory && !signature.isRegular && !signature.isSymlink {
                return "Plugin size contains unsupported entry"
            }
            visited.append((url, signature))
            if signature.isRegular || signature.isSymlink {
                guard signature.size >= 0, signature.size <= Int.max else { return "Plugin size invalid file length" }
                let key = "\(signature.device):\(signature.inode)"
                if distinctFiles.insert(key).inserted {
                    // A link is a real directory entry with its own length. Its target
                    // may be absent or separately owned, and is never traversed here.
                    guard let next = checkedSum(sum, Int(signature.size)) else { return "Plugin size overflow" }
                    sum = next
                }
            }
            return nil
        }
        guard let root = Signature(bundle), root.isDirectory else {
            return Result(bytes: nil, issue: "Plugin size bundle unavailable")
        }
        if let reason = account(bundle) { return Result(bytes: nil, issue: reason) }
        var directories: [(URL, Int)] = [(bundle, 0)]
        while let (directory, depth) = directories.popLast() {
            if let reason = budget() { return Result(bytes: nil, issue: reason) }
            let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard descriptor >= 0 else { return Result(bytes: nil, issue: "Plugin size directory unavailable") }
            guard let stream = fdopendir(descriptor) else {
                close(descriptor)
                return Result(bytes: nil, issue: "Plugin size directory unavailable")
            }
            var failed: String?
            while true {
                if let reason = budget() { failed = reason; break }
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 { failed = "Plugin size directory changed or inaccessible" }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let child = directory.appendingPathComponent(name)
                if !complete && depth + 1 > maximumBundleDepth { failed = "Plugin size depth limit reached"; break }
                if let reason = account(child) { failed = reason; break }
                if visited.last?.1.isDirectory == true { directories.append((child, depth + 1)) }
            }
            closedir(stream)
            if let failed { return Result(bytes: nil, issue: failed) }
        }
        for (url, before) in visited {
            if let reason = budget() { return Result(bytes: nil, issue: reason) }
            bundleEntries += 1; pass.entries += 1
            guard Signature(url) == before else { return Result(bytes: nil, issue: "Plugin size bundle changed during measurement") }
        }
        return Result(bytes: sum, issue: nil)
    }
}
