import Foundation
import CoreServices

/// Synchronous read-only discovery. Run off the UI thread. Symlinks are not followed.
/// Results are candidates; neither absence nor candidate grouping authorizes removal.
public final class Scanner {
    private let files = FileManager.default
    private let pluginExtensions: Set<String> = ["component", "vst", "vst3", "aaxplugin", "clap"]
    private let sampleExtensions: Set<String> = ["wav", "aif", "aiff", "flac", "mp3", "m4a", "caf", "ogg"]

    private let sineDatabase: URL
    private let journalBaseURL: URL?
    /// Optional read-only vendor catalog location; injectable for fixture validation.
    public init(sineDatabase: URL = LibraryMetadataReader.sineDatabase, journalBaseURL: URL? = nil) {
        self.sineDatabase = sineDatabase; self.journalBaseURL = journalBaseURL
    }

    public func scan(_ request: ScanRequest, scannedKinds: Set<AssetKind> = Set(AssetKind.allCases),
                     previousProjects: [ProjectReport] = [],
                     inventory: (@Sendable (InventorySnapshot) -> Void)? = nil,
                     progress: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanReport {
        let start = Date()
        var assets: [String: Asset] = [:]
        var projects: [String: ProjectReport] = [:]
        let reusableProjects = Dictionary(previousProjects.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var issues: [ScanIssue] = []
        var visited: Set<String> = []
        var count = 0
        var categoryEntries = 0
        var limitReported = false
        var candidates: [(url: URL, kind: AssetKind?, classification: String, isDirectory: Bool)] = []
        var sequence = 0
        var lastProgress = Date.distantPast
        var lastPhase: ScanProgress.Phase?
        var inventorySequence = 0
        var lastInventory = Date.distantPast
        var publishedAssetCount = -1
        var pluginSizePass = PluginBundleSize.Pass()
        let decodedCache = journalBaseURL.flatMap(DecodedFactCache.init(baseURL:))
        func publishInventory(complete: Bool = false, force: Bool = false) {
            guard let inventory else { return }
            let now = Date()
            guard force || (assets.count != publishedAssetCount && now.timeIntervalSince(lastInventory) >= 1) else { return }
            inventorySequence += 1; lastInventory = now; publishedAssetCount = assets.count
            inventory(InventorySnapshot(assets: Array(assets.values), discoveryComplete: complete,
                                        elapsedSeconds: now.timeIntervalSince(start), sequence: inventorySequence))
        }
        func publish(_ phase: ScanProgress.Phase, _ completed: Int, _ total: Int?, _ path: String?, force: Bool = false) {
            guard let progress else { return }
            let now = Date()
            guard force || phase != lastPhase || now.timeIntervalSince(lastProgress) >= 0.25 else { return }
            sequence += 1; lastProgress = now; lastPhase = phase
            progress(ScanProgress(phase: phase, completed: completed, total: total, currentPath: path,
                                  elapsedSeconds: now.timeIntervalSince(start), sequence: sequence))
        }
        publish(.discovering, 0, nil, nil, force: true)
        let libraryRoots = request.libraries.map { $0.standardizedFileURL.path }
        let sampleRoots = request.samples.map { $0.standardizedFileURL.path }
        func isWithin(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
        func prefersSamples(_ path: String) -> Bool {
            let sampleDepth = sampleRoots.filter { isWithin(path, $0) }.map(\.count).max() ?? -1
            let libraryDepth = libraryRoots.filter { isWithin(path, $0) }.map(\.count).max() ?? -1
            return sampleDepth >= libraryDepth && sampleDepth >= 0
        }

        var issueKind: AssetKind = .plugin
        func issue(_ url: URL, _ reason: String) { issues.append(ScanIssue(path: url.path, reason: reason, kind: issueKind)) }
        func add(_ url: URL, _ kind: AssetKind, _ classification: String, _ isDirectory: Bool, bytes: Int? = nil) {
            var asset = Asset(kind: kind, path: url.path,
                name: url.deletingPathExtension().lastPathComponent, format: url.pathExtension.lowercased(),
                bundleIdentifier: nil, logicalBytes: bytes, classification: classification, fileIdentity: kind == .plugin ? PluginFileIdentity.read(url.path) : nil)
            if kind == .sample { asset.finderDateAdded = FinderDateAdded.read(url) }
            assets[kind.rawValue + ":" + url.path] = asset
            // Only plugin identifiers require a later metadata read. Sample sizes
            // come from prefetched directory properties, without rereading each file.
            if kind == .plugin { candidates.append((url, kind, classification, isDirectory)) }
            publishInventory()
        }
        func inspectAsset(_ url: URL, _ kind: AssetKind, _ classification: String, _ isDirectory: Bool) {
            var identifier: String?
            if kind == .plugin {
                let info = url.appendingPathComponent("Contents/Info.plist")
                if !hasSymlink(info) {
                    let readIdentifier: () -> String? = {
                        guard let data = try? BoundedFile.read(info, limit: 1_048_576),
                              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
                        return plist["CFBundleIdentifier"] as? String
                    }
                    if let decodedCache {
                        identifier = decodedCache.value(policy: "plugin-plist-id-v1", paths: [info], read: readIdentifier)
                    } else { identifier = readIdentifier() }
                }
            }
            let bytes: Int?
            if kind == .plugin && isDirectory {
                let measured = PluginBundleSize.measure(url, pass: &pluginSizePass, complete: true)
                bytes = measured.bytes
                if let reason = measured.issue {
                    issues.append(ScanIssue(path: url.path, reason: reason, kind: .plugin))
                }
            } else {
                bytes = isDirectory ? nil : (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                if bytes == nil {
                    issues.append(ScanIssue(path: url.path, reason: "Plugin file size unavailable: file metadata could not be read", kind: .plugin))
                }
            }
            var asset = Asset(
                kind: kind, path: url.path, name: url.deletingPathExtension().lastPathComponent,
                format: url.pathExtension.lowercased(), bundleIdentifier: identifier,
                logicalBytes: bytes, classification: classification, fileIdentity: kind == .plugin ? PluginFileIdentity.read(url.path) : nil)
            asset.finderDateAdded = FinderDateAdded.read(url)
            assets[kind.rawValue + ":" + url.path] = asset
        }

        func walk(_ url: URL, mode: String, depth: Int) {
            guard !Task<Never, Never>.isCancelled else { return }
            let path = url.path
            let key = mode + ":" + (mode == "libraries" ? "\(depth):" : "") + path
            guard !visited.contains(key) else { return }
            let complete = request.completeFileScan && (mode != "projects" || request.completeProjectScan)
            guard complete || categoryEntries < request.maximumEntries else {
                if !limitReported { issue(url, "Entry limit reached; scan is incomplete"); limitReported = true }
                return
            }
            count += 1; categoryEntries += 1
            publish(.discovering, count, nil, url.path)
            guard complete || depth <= request.maximumDepth else { issue(url, "Depth limit reached; scan is incomplete"); return }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isSymbolicLink == true { issue(url, "Symbolic link skipped"); return }
                let isDirectory = values.isDirectory == true
                // Overlapping roots only require remembering directories. Keeping
                // every unrelated audio/media file path grows with the whole tree.
                if isDirectory { visited.insert(key) }
                let ext = url.pathExtension.lowercased()
                if mode == "samples", !prefersSamples(path) { return }
                if mode == "libraries", depth > 0, prefersSamples(path) { return }
                if pluginExtensions.contains(ext) {
                    if mode == "plugins", isDirectory { add(url, .plugin, "pluginBundleCandidate", true) }
                    return
                }
                if mode == "projects", ProjectReader.extensions.contains(ext) {
                    candidates.append((url, nil, "", isDirectory))
                    return
                }
                if isDirectory {
                    // Library and project packages must never be enumerated as loose samples.
                    if ["app", "dsbundle", "logicx", "band"].contains(ext) || (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true { return }
                    guard let entries = files.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                                                         options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
                                                         errorHandler: { failed, error in
                        issue(failed, "Cannot enumerate location: \(error.localizedDescription)")
                        return false
                    }) else { issue(url, "Cannot enumerate directory"); return }
                    // Traverse as entries arrive: collecting and sorting an entire
                    // directory delays the first usable result and repeats path work.
                    while true {
                        if Task<Never, Never>.isCancelled { break }
                        // Include nextObject in the pool: enumeration and resource
                        // properties also create autoreleased Foundation objects.
                        let advanced = autoreleasepool { () -> Bool in
                            guard let child = entries.nextObject() as? URL else { return false }
                            walk(child, mode: mode, depth: depth + 1)
                            return true
                        }
                        if !advanced || (!complete && limitReported) { break }
                    }
                } else if mode == "samples", values.isRegularFile == true, sampleExtensions.contains(ext) {
                    if values.fileSize == nil {
                        issue(url, "Sample file size unavailable: file metadata could not be read")
                    }
                    add(url, .sample, "audioFileCandidate", false, bytes: values.fileSize)
                }
            } catch { issue(url, "Cannot inspect location: \(error.localizedDescription)") }
        }

        for (mode, roots) in [("plugins", request.plugins),
                              ("samples", request.samples), ("projects", request.projects)] {
            issueKind = mode == "plugins" ? .plugin : .sample
            guard scannedKinds.contains(issueKind) else { continue }
            categoryEntries = 0; limitReported = false
            if mode == "projects" { publishInventory(force: true) }
            for raw in roots.sorted(by: { $0.path < $1.path }) {
                if Task<Never, Never>.isCancelled { break }
                let root = raw.standardizedFileURL
                if mode == "plugins", request.optionalPluginRoots.contains(where: { $0.standardizedFileURL.path == root.path }),
                   !files.fileExists(atPath: root.path) { continue }
                publish(.discovering, count, nil, root.path, force: true)
                guard !hasSymlink(root) else { issue(root, "Root or ancestor is a symbolic link; skipped"); continue }
                do {
                    guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                        issue(root, "Scan root must be a directory"); continue
                    }
                } catch { issue(root, "Root unavailable: \(error.localizedDescription)"); continue }
                walk(root, mode: mode, depth: 0)
            }
        }
        if scannedKinds.contains(.library), !Task<Never, Never>.isCancelled {
            var libraryIssues: [ScanIssue] = []
            let discovered = KontaktCategoryReader.enrich(LibraryDiscovery.scan(request, sineDatabase: sineDatabase, journalBaseURL: journalBaseURL, cache: decodedCache, issues: &libraryIssues) { completed, path in
                publish(.discovering, completed, nil, path)
            }, cache: decodedCache)
            let claimedRoots = Dictionary(discovered.compactMap { $0.libraryMetadata?.identity?.installationRoot }
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }.map { ($0, 1) },
                uniquingKeysWith: +)
            let separatelyOwnedSINEPaths = Set(discovered.filter { $0.format == "SINE" }.flatMap { asset in
                asset.libraryMetadata?.physicalContentPaths ??
                    (asset.libraryMetadata?.instruments.flatMap { $0.contentPaths ?? [] } ?? [])
            })
            var librarySizePass = PluginBundleSize.Pass()
            var measuredLibraryFolders: [String: PluginBundleSize.Result] = [:]
            func measureLibraryFolder(_ folder: URL) -> PluginBundleSize.Result {
                let path = folder.standardizedFileURL.path
                if let measured = measuredLibraryFolders[path] { return measured }
                let measured = PluginBundleSize.measure(folder, pass: &librarySizePass,
                    complete: request.libraryScanMode == .complete) { count in
                        publish(.inspecting, count, nil, path)
                    }
                measuredLibraryFolders[path] = measured
                return measured
            }
            for var asset in discovered {
                if Task<Never, Never>.isCancelled { break }
                let url = URL(fileURLWithPath: asset.path)
                if !hasSymlink(url), files.fileExists(atPath: url.path) { asset.finderDateAdded = FinderDateAdded.read(url) }
                if let identity = asset.libraryMetadata?.identity,
                   identity.evidence == .manifest || identity.evidence == .proposed || identity.evidence == .vendorCatalog,
                   let path = identity.installationRoot {
                    let root = URL(fileURLWithPath: path).standardizedFileURL
                    let withinConfiguredRoot = request.libraries.contains { candidate in
                        let configured = candidate.standardizedFileURL.path
                        return root.path == configured || root.path.hasPrefix(configured + "/")
                    }
                    let duplicateRoot = claimedRoots[root.path] != 1
                    let overlapsAnotherRoot = claimedRoots.keys.contains { other in
                        other != root.path && (other.hasPrefix(root.path + "/") || root.path.hasPrefix(other + "/"))
                    }
                    let overlapsSINEContent = separatelyOwnedSINEPaths.contains { $0.hasPrefix(root.path + "/") }
                    let locatedAtRoot = asset.path == root.path || asset.path.hasPrefix(root.path + "/")
                    if withinConfiguredRoot,
                       locatedAtRoot, !hasSymlink(root) {
                        let measured = measureLibraryFolder(root)
                        asset.logicalBytes = measured.bytes
                        if measured.bytes != nil {
                            let sharedScope = duplicateRoot || overlapsAnotherRoot || overlapsSINEContent
                            asset.libraryMetadata?.sizeBasis = identity.evidence == .manifest && !sharedScope ? .fullInstallation : .candidateFolder
                        }
                        if let reason = measured.issue {
                            libraryIssues.append(ScanIssue(path: root.path,
                                reason: reason.replacingOccurrences(of: "Plugin size", with: "Library size"), kind: .library))
                        }
                    } else if asset.logicalBytes == nil {
                        libraryIssues.append(ScanIssue(path: root.path,
                            reason: "Physical installation size unavailable: root is outside scope, shared, nested, unsafe, or duplicated", kind: .library))
                    }
                }
                if asset.logicalBytes == nil, asset.libraryMetadata?.identity?.installationRoot == nil {
                    let path = url.standardizedFileURL.path
                    let withinConfiguredRoot = request.libraries.contains { candidate in
                        let configured = candidate.standardizedFileURL.path
                        return path == configured || path.hasPrefix(configured + "/")
                    }
                    if asset.libraryMetadata?.physicalContentPaths == nil, withinConfiguredRoot, !hasSymlink(url) {
                        let measured = measureLibraryFolder(url)
                        asset.logicalBytes = measured.bytes
                        if measured.bytes != nil { asset.libraryMetadata?.sizeBasis = .candidateFolder }
                        if let reason = measured.issue {
                            libraryIssues.append(ScanIssue(path: path,
                                reason: reason.replacingOccurrences(of: "Plugin size", with: "Library size"), kind: .library))
                        }
                    } else {
                        libraryIssues.append(ScanIssue(path: path,
                            reason: "Physical folder size unavailable: no unique in-scope safe folder was established", kind: .library))
                    }
                }
                if asset.logicalBytes == nil,
                   !libraryIssues.contains(where: { $0.path == asset.path || $0.reason.contains("size unavailable") && $0.path == asset.libraryMetadata?.identity?.installationRoot }) {
                    libraryIssues.append(ScanIssue(path: asset.path,
                        reason: "Physical library size unavailable: no complete safe measurement was established", kind: .library))
                }
                if var metadata = asset.libraryMetadata {
                    for index in metadata.instruments.indices {
                        let path = URL(fileURLWithPath: metadata.instruments[index].path)
                        if !hasSymlink(path), (try? path.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                            metadata.instruments[index].finderDateAdded = FinderDateAdded.read(path)
                        }
                    }
                    asset.libraryMetadata = metadata
                }
                let product = asset.libraryMetadata?.identity?.productID ?? ""
                assets["library:" + asset.path + "\0" + product] = asset; publishInventory()
            }
            issues += libraryIssues.map { ScanIssue(path: $0.path, reason: $0.reason, kind: .library) }
        }
        publishInventory(complete: true, force: true)
        publish(.inspecting, 0, candidates.count, candidates.first?.url.path, force: true)
        for (index, candidate) in candidates.enumerated() {
            if Task<Never, Never>.isCancelled { break }
            publish(.inspecting, index, candidates.count, candidate.url.path)
            if let kind = candidate.kind {
                inspectAsset(candidate.url, kind, candidate.classification, candidate.isDirectory)
            } else {
                let old = reusableProjects[candidate.url.path]
                let source = old?.sourcePath ?? candidate.url.path
                let validSource = old?.sourcePath == nil ||
                    (CatalogScope.contains(source, root: candidate.url.path + "/Alternatives") &&
                     URL(fileURLWithPath: source).lastPathComponent == "ProjectData" &&
                     (try? ProjectReader.selectedLogicProjectData(candidate.url).path) == source)
                let stamp = LibraryScanJournal.stamp(source).map(LibraryScanJournal.signature)
                let report: ProjectReport
                if let old, old.coverage == "partial", old.readerPolicyVersion == ProjectReader.policyVersion,
                   old.sourceSHA256?.utf8.count == 64,
                   validSource, let stamp, stamp == old.sourceSignature {
                    report = old
                } else { report = ProjectReader.read(candidate.url) }
                projects[candidate.url.path] = report
                if report.coverage == "failed" || report.coverage == "unsupported" {
                    issues.append(ScanIssue(path: candidate.url.path, reason: "Project reference coverage: " + report.coverage, kind: .sample))
                }
            }
            publish(.inspecting, index + 1, candidates.count, candidate.url.path, force: index + 1 == candidates.count)
        }
        let orderedAssets = assets.values.sorted { ($0.kind.rawValue, $0.path, $0.selectionKey) < ($1.kind.rawValue, $1.path, $1.selectionKey) }
        let orderedProjects = projects.values.sorted { $0.path < $1.path }
        let samples = orderedAssets.filter { $0.kind == .sample }
        let matchingTotal = orderedProjects.count + samples.count
        var matchedUnits = 0
        publish(.matching, 0, matchingTotal, nil, force: true)
        var referencesByPath: [String: [ProjectReport]] = [:]
        for project in orderedProjects {
            let paths = Set(project.references.filter { $0.kind == .sample }.compactMap(\.resolvedPath))
            for path in paths { referencesByPath[path, default: []].append(project) }
            matchedUnits += 1; publish(.matching, matchedUnits, matchingTotal, project.path)
        }
        let inclusions = samples.map { asset in
            matchedUnits += 1; publish(.matching, matchedUnits, matchingTotal, asset.path)
            let matches = referencesByPath[asset.path] ?? []
            return SampleInclusion(samplePath: asset.path, projectPaths: matches.map(\.path),
                                   latestReferencingProjectModifiedAt: matches.compactMap(\.projectModifiedAt).max(),
                                   status: matches.isEmpty ? "noReferencesFoundInScannedProjects" : "referenced")
        }
        publish(.complete, 1, 1, nil, force: true)
        return ScanReport(schemaVersion: 1, assets: orderedAssets, projects: orderedProjects,
                          sampleInclusions: inclusions, issues: issues, durationSeconds: Date().timeIntervalSince(start))
    }

    private func hasSymlink(_ url: URL) -> Bool {
        var current = url
        while current.path != "/" {
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return true }
            current.deleteLastPathComponent()
        }
        return false
    }
}

/// The filesystem/Finder date a file entered its current directory. This works
/// without Spotlight indexing where the volume provides the native resource key.
/// It is not acquisition, installation, creation, modification, or scan time.
enum FinderDateAdded {
    static func read(_ url: URL, now: Date = Date(),
                     filesystem: (URL) -> Date? = { try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate },
                     spotlight: (URL) -> Date? = { url in
                         guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
                         return MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
                     }) -> Date? {
        func valid(_ value: Date?) -> Date? {
            guard let value, value.timeIntervalSince1970.isFinite,
                  value.timeIntervalSince1970 > 0, value <= now else { return nil }
            return value
        }
        // Use the volume's direct fact before a potentially stale search index.
        // Neither branch falls back to file creation/modification timestamps.
        return valid(filesystem(url)) ?? valid(spotlight(url))
    }
}
