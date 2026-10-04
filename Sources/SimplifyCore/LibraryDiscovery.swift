import Foundation

/// Manifest-led library discovery. Ordinary directories never become catalog rows.
enum LibraryDiscovery {
    static func scan(_ request: ScanRequest, sineDatabase: URL = LibraryMetadataReader.sineDatabase, issues outputIssues: inout [ScanIssue]) -> [Asset] {
        var issues: [ScanIssue] = []
        defer { outputIssues += issues }
        var instrumentPaths: [String: Set<String>] = [:]
        var claimedInstruments = Set<String>()
        var assets: [String: Asset] = [:]; var visited = Set<String>(); var count = 0; var limited = false; var truncated = Set<String>()
        let fm = FileManager.default
        func add(_ url: URL, name: String, player: String, maker: String, source: String, evidence: LibraryIdentity.Evidence = .proposed, installationRoot: URL? = nil) {
            guard assets[url.path] == nil else { return }
            var item = Asset(kind: .library, path: url.path, name: name, format: player, bundleIdentifier: nil, logicalBytes: nil, classification: evidence == .manifest ? "identifiedLibrary" : "needsIdentification")
            item.libraryMetadata = LibraryMetadata(player: player, maker: maker, summary: "", instruments: [], tags: LibraryMetadataReader.tags(name), source: source, identity: LibraryIdentity(evidence: evidence, productID: nil, installationRoot: installationRoot?.path))
            assets[url.path] = item
        }
        func append(_ instrument: LibraryInstrument, owner: URL) {
            guard var item = assets[owner.path], var metadata = item.libraryMetadata, !claimedInstruments.contains(instrument.path), instrumentPaths[owner.path, default: []].insert(instrument.path).inserted else { return }
            if metadata.instruments.count >= 2000 {
                if truncated.insert(owner.path).inserted { issues.append(ScanIssue(path: owner.path, reason: "Instrument metadata limited to 2,000 entries")) }
                return
            }
            claimedInstruments.insert(instrument.path)
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
                let manifests = entries.filter { $0.pathExtension.lowercased() == "nicnt" }
                let ambiguous = manifests.count > 1
                if ambiguous {
                    // No arbitrary first/last manifest may claim every patch here.
                    owner = nil
                    issues.append(ScanIssue(path: url.path, reason: "Multiple Kontakt manifests; library ownership needs identification"))
                } else if let manifest = manifests.first {
                    if let info = LibraryMetadataReader.kontaktManifest(manifest) {
                        add(manifest, name: info.name, player: "Kontakt", maker: info.maker,
                            source: "Kontakt ProductHints manifest; instrument tags inferred from NKI names. Usage and sample completeness not established.",
                            evidence: .manifest, installationRoot: url)
                        owner = manifest
                    } else {
                        owner = nil
                        issues.append(ScanIssue(path: manifest.path, reason: "Kontakt manifest could not be identified"))
                    }
                }
                // A structural boundary is a proposal, not a vendor-confirmed product.
                // It is detected before descending into Instruments so all patch folders
                // retain the same parent. Never inspect ancestors outside selected scope.
                let directories = entries.filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map {
                        $0.isDirectory == true && $0.isSymbolicLink != true
                    } ?? false
                }.map { $0.lastPathComponent.lowercased() }
                let hasPayload = directories.contains("samples") || entries.contains {
                    $0.pathExtension.lowercased() == "nkx" &&
                    (try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map {
                        $0.isRegularFile == true && $0.isSymbolicLink != true
                    } == true
                }
                if owner == nil, !ambiguous, directories.contains("instruments"), hasPayload {
                    add(url, name: url.lastPathComponent, player: "Kontakt", maker: "Unknown maker",
                        source: "Proposed library from Instruments and sample-content structure. Maker and product require confirmation; not a removal boundary.",
                        evidence: .proposed, installationRoot: url)
                    owner = url
                }
                if entries.contains(where: { $0.lastPathComponent == "libraryInfo.lib" }),
                   entries.contains(where: { $0.lastPathComponent == "Parts" }) {
                    add(url, name: url.lastPathComponent, player: "Soundpaint", maker: "Soundpaint", source: "Soundpaint libraryInfo + Parts metadata; library name from installation folder. Usage not established.", installationRoot: url); owner = url
                }
                if ["Omnisphere", "Trilian", "Keyscape"].contains(url.lastPathComponent), entries.contains(where: { $0.lastPathComponent == "Soundsources" }), entries.contains(where: { $0.lastPathComponent == "Settings Library" }) {
                    add(url, name: url.lastPathComponent, player: "Spectrasonics", maker: "Spectrasonics", source: "Recognized STEAM product structure; factory sound catalogs remain unparsed.", installationRoot: url); owner = url
                }
                for child in entries {
                    count += 1
                    if count > request.maximumEntries { limited = true; break }
                    guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                    if values.isDirectory == true {
                        // Do not walk millions of sample payloads or unrelated app/project packages.
                        let name = child.lastPathComponent.lowercased()
                        // Samples can be a collection container before a product owns it.
                        // Once owned, it is payload and remains outside patch discovery.
                        if (name == "samples" && owner != nil) || ["sample data", "imported samples", "audio", "documentation", "resources", "snapshots", "soundsources", "images"].contains(name) || ["app", "logicx", "band", "component", "vst3", "aaxplugin"].contains(child.pathExtension.lowercased()) { continue }
                        walk(child, depth: depth + 1, inherited: owner)
                    } else if ["nki", "dspreset"].contains(child.pathExtension.lowercased()) {
                        let player = child.pathExtension.lowercased() == "nki" ? "Kontakt" : "Decent Sampler"
                        if claimedInstruments.contains(child.path) { continue }
                        // Do not attach a Decent preset to an inferred Kontakt product.
                        let matchingOwner = owner.flatMap { assets[$0.path]?.format == player ? $0 : nil }
                        let fallback = assets[url.path].map { $0.format == player ? url : child } ?? url
                        let group = matchingOwner ?? fallback
                        if matchingOwner == nil { add(group, name: url.lastPathComponent, player: player, maker: "Unknown maker", source: "Unresolved instrument folder; product and maker need identification. Tags inferred from instrument names.", evidence: .unresolved) }
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
        for asset in LibraryMetadataReader.sine(sineDatabase, roots: request.libraries, sampleRoots: request.samples, issues: &issues) {
            assets[asset.libraryMetadata?.identity?.productID ?? asset.path] = asset
        }
        return assets.values.filter {
            // Do not publish a speculative boundary that yielded no Kontakt patches.
            !($0.format == "Kontakt" && $0.libraryMetadata?.identity?.evidence == .proposed && $0.libraryMetadata?.instruments.isEmpty == true)
        }.sorted { ($0.name, $0.path) < ($1.name, $1.path) }
    }
}
