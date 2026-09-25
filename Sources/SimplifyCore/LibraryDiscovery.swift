import Foundation

/// Manifest-led library discovery. Ordinary directories never become catalog rows.
enum LibraryDiscovery {
    static func scan(_ request: ScanRequest, issues outputIssues: inout [ScanIssue]) -> [Asset] {
        var issues: [ScanIssue] = []
        defer { outputIssues += issues }
        var instrumentPaths: [String: Set<String>] = [:]
        var assets: [String: Asset] = [:]; var visited = Set<String>(); var count = 0; var limited = false; var truncated = Set<String>()
        let fm = FileManager.default
        func add(_ url: URL, name: String, player: String, maker: String, source: String) {
            guard assets[url.path] == nil else { return }
            var item = Asset(kind: .library, path: url.path, name: name, format: player, bundleIdentifier: nil, logicalBytes: nil, classification: "identifiedLibrary")
            item.libraryMetadata = LibraryMetadata(player: player, maker: maker, summary: "", instruments: [], tags: LibraryMetadataReader.tags(name), source: source)
            assets[url.path] = item
        }
        func append(_ instrument: LibraryInstrument, owner: URL) {
            guard var item = assets[owner.path], var metadata = item.libraryMetadata, instrumentPaths[owner.path, default: []].insert(instrument.path).inserted else { return }
            if metadata.instruments.count >= 2000 {
                if truncated.insert(owner.path).inserted { issues.append(ScanIssue(path: owner.path, reason: "Instrument metadata limited to 2,000 entries")) }
                return
            }
            metadata.instruments.append(instrument)
            metadata.tags = Array(Set(metadata.tags + instrument.tags)).sorted()
            item.libraryMetadata = metadata; assets[owner.path] = item
        }
        func walk(_ url: URL, depth: Int, inherited: URL?) {
            guard !visited.contains(url.path) else { return }; visited.insert(url.path)
            count += 1
            guard count <= request.maximumEntries, depth <= min(request.maximumDepth, 32) else { limited = true; return }
            let sampleDepth = request.samples.filter { url.path == $0.path || url.path.hasPrefix($0.path + "/") }.map { $0.path.count }.max() ?? -1
            let libraryDepth = request.libraries.filter { url.path == $0.path || url.path.hasPrefix($0.path + "/") }.map { $0.path.count }.max() ?? -1
            if sampleDepth >= libraryDepth && sampleDepth >= 0 { return }
            guard LibraryMetadataReader.safe(url) else { issues.append(ScanIssue(path: url.path, reason: "Library location is unavailable or linked")); return }
            do {
                guard (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { issues.append(ScanIssue(path: url.path, reason: "Library root must be a directory")); return }
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: { failed, error in
                    issues.append(ScanIssue(path: failed.path, reason: "Cannot enumerate library location: " + error.localizedDescription)); return false
                }) else { issues.append(ScanIssue(path: url.path, reason: "Cannot enumerate library location")); return }
                var entries: [URL] = []
                for case let child as URL in enumerator {
                    if entries.count + count >= request.maximumEntries { limited = true; break }
                    entries.append(child)
                }
                entries.sort { $0.path < $1.path }
                var owner = inherited
                for manifest in entries where manifest.pathExtension.lowercased() == "nicnt" {
                    if let info = LibraryMetadataReader.kontaktManifest(manifest) {
                        add(manifest, name: info.name, player: "Kontakt", maker: info.maker, source: "Kontakt ProductHints manifest; instrument tags inferred from NKI names. Usage and sample completeness not established.")
                        owner = manifest
                    } else { issues.append(ScanIssue(path: manifest.path, reason: "Kontakt manifest could not be identified")) }
                }
                if entries.contains(where: { $0.lastPathComponent == "libraryInfo.lib" }),
                   entries.contains(where: { $0.lastPathComponent == "Parts" }) {
                    add(url, name: url.lastPathComponent, player: "Soundpaint", maker: "Soundpaint", source: "Soundpaint libraryInfo + Parts metadata; library name from installation folder. Usage not established."); owner = url
                }
                if ["Omnisphere", "Trilian", "Keyscape"].contains(url.lastPathComponent), entries.contains(where: { $0.lastPathComponent == "Soundsources" }), entries.contains(where: { $0.lastPathComponent == "Settings Library" }) {
                    add(url, name: url.lastPathComponent, player: "Spectrasonics", maker: "Spectrasonics", source: "Recognized STEAM product structure; factory sound catalogs remain unparsed."); owner = url
                }
                for child in entries {
                    count += 1
                    if count > request.maximumEntries { limited = true; break }
                    guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                    if values.isDirectory == true {
                        // Do not walk millions of sample payloads or unrelated app/project packages.
                        let name = child.lastPathComponent.lowercased()
                        if ["samples", "sample data", "imported samples", "audio", "documentation", "resources", "snapshots", "soundsources", "images"].contains(name) || ["app", "logicx", "band", "component", "vst3", "aaxplugin"].contains(child.pathExtension.lowercased()) { continue }
                        walk(child, depth: depth + 1, inherited: owner)
                    } else if ["nki", "dspreset"].contains(child.pathExtension.lowercased()) {
                        let player = child.pathExtension.lowercased() == "nki" ? "Kontakt" : "Decent Sampler"
                        let group = owner ?? url
                        if owner == nil { add(group, name: url.lastPathComponent, player: player, maker: "Unknown maker", source: "Instrument files found; library identity inferred from containing folder. Tags inferred from instrument names.") }
                        let name = child.deletingPathExtension().lastPathComponent
                        append(LibraryInstrument(name: name, path: child.path, tags: LibraryMetadataReader.tags(name)), owner: group)
                    } else if child.lastPathComponent == "info.json", let owner, assets[owner.path]?.format == "Soundpaint" {
                        if let part = LibraryMetadataReader.soundpaintPart(child) { append(part, owner: owner) }
                    } else if child.pathExtension.lowercased() == "otmeta", owner == nil {
                        // Identity is read from the SINE catalog, never guessed from these mic files.
                        continue
                    }
                }
            } catch { issues.append(ScanIssue(path: url.path, reason: "Cannot read library metadata: \(error.localizedDescription)")) }
        }
        for root in request.libraries.sorted(by: { $0.path < $1.path }) {
            count = 0; limited = false; visited = []
            walk(root.standardizedFileURL, depth: 0, inherited: nil)
            if limited { issues.append(ScanIssue(path: root.path, reason: "Library entry or depth limit reached; scan is incomplete")) }
        }
        for asset in LibraryMetadataReader.sine(LibraryMetadataReader.sineDatabase, roots: request.libraries, sampleRoots: request.samples, issues: &issues) { assets[asset.path] = asset }
        return assets.values.sorted { $0.name < $1.name }
    }
}
