import Foundation

/// Manifest-led library discovery. Ordinary directories never become catalog rows.
enum LibraryDiscovery {
    static func scan(_ request: ScanRequest, sineDatabase: URL = LibraryMetadataReader.sineDatabase,
                     journalBaseURL: URL? = nil, cache: DecodedFactCache? = nil, issues outputIssues: inout [ScanIssue],
                     progress: ((Int, String) -> Void)? = nil) -> [Asset] {
        var issues: [ScanIssue] = []
        defer { outputIssues += issues }
        var instrumentPaths: [String: Set<String>] = [:]
        var instruments: [String: [LibraryInstrument]] = [:]
        var manifestDetails: [String: KontaktManifestDetails] = [:]
        var sinePairCandidates = Set<String>()
        var claimedInstruments = Set<String>()
        var assets: [String: Asset] = [:]; var visited = Set<String>(); var count = 0; var limited = false; var truncated = Set<String>()
        let fm = FileManager.default
        let bounded = request.libraryScanMode == .boundedDiagnostic
        var pending: [(url: URL, depth: Int, inherited: URL?)] = []
        var checkpointCandidates: [String] = []
        func role(_ name: String) -> String {
            name.lowercased().replacingOccurrences(of: #"^[0-9]+[\s._-]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[\s._-]+"#, with: " ", options: .regularExpression)
        }
        func directEntries(_ directory: URL) -> [URL] {
            guard LibraryMetadataReader.safe(directory),
                  let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]),
                  entries.count <= 4_096 else { return [] }
            return entries
        }
        func directPatch(in directory: URL) -> Bool {
            directEntries(directory).contains { child in
                ["nki", "nkm"].contains(child.pathExtension.lowercased()) &&
                    (try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map {
                        $0.isRegularFile == true && $0.isSymbolicLink != true
                    } == true
            }
        }
        func add(_ url: URL, name: String, player: String, maker: String, source: String, evidence: LibraryIdentity.Evidence = .proposed, productID: String? = nil, sourceFingerprint: String? = nil, installationRoot: URL? = nil) {
            guard assets[url.path] == nil else { return }
            var item = Asset(kind: .library, path: url.path, name: name, format: player, bundleIdentifier: nil, logicalBytes: nil, classification: evidence == .manifest ? "identifiedLibrary" : "needsIdentification")
            item.libraryMetadata = LibraryMetadata(player: player, maker: maker, summary: "", instruments: [], tags: LibraryMetadataReader.tags(name), source: source, identity: LibraryIdentity(evidence: evidence, productID: productID, installationRoot: installationRoot?.path, sourceFingerprint: sourceFingerprint))
            assets[url.path] = item
        }
        func append(_ instrument: LibraryInstrument, owner: URL) {
            guard assets[owner.path] != nil, !claimedInstruments.contains(instrument.path), instrumentPaths[owner.path, default: []].insert(instrument.path).inserted else { return }
            if bounded && instruments[owner.path, default: []].count >= 2000 {
                if truncated.insert(owner.path).inserted { issues.append(ScanIssue(path: owner.path, reason: "Instrument metadata limited to 2,000 entries")) }
                return
            }
            claimedInstruments.insert(instrument.path)
            instruments[owner.path, default: []].append(instrument)
        }
        func walk(_ url: URL, depth: Int, inherited: URL?) {
            guard !visited.contains(url.path) else { return }; visited.insert(url.path)
            count += 1
            progress?(count, url.path)
            guard !bounded || (count <= request.maximumEntries && depth <= min(request.maximumDepth, 32)) else { limited = true; return }
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
                    if Task<Never, Never>.isCancelled { limited = true; break }
                    if bounded && entries.count + count >= request.maximumEntries { limited = true; break }
                    // Enumerate directory entries, never read sample payloads. Keep
                    // only metadata candidates and directories in working memory.
                    let ext = child.pathExtension.lowercased()
                    if ["nicnt", "nki", "nkm", "nksn", "dspreset", "nkx", "otmeta"].contains(ext)
                        || ["info.json", "libraryInfo.lib"].contains(child.lastPathComponent)
                        || (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        entries.append(child)
                    }
                }
                entries.sort { $0.path < $1.path }
                checkpointCandidates = entries.map(\.path)
                var owner = inherited
                let manifests = entries.filter { $0.pathExtension.lowercased() == "nicnt" }
                let ambiguous = manifests.count > 1
                if ambiguous {
                    // No arbitrary first/last manifest may claim every patch here.
                    owner = nil
                    issues.append(ScanIssue(path: url.path, reason: "Multiple Kontakt manifests; library ownership needs identification"))
                } else if let manifest = manifests.first {
                    let snapshot: KontaktManifestSnapshot?
                    if let cache {
                        snapshot = cache.value(policy: "kontakt-manifest-v1", paths: [manifest]) {
                            LibraryMetadataReader.kontaktManifestSnapshot(manifest)
                        }
                    } else { snapshot = LibraryMetadataReader.kontaktManifestSnapshot(manifest) }
                    if let snapshot {
                        let info = snapshot.details
                        add(manifest, name: info.name, player: "Kontakt", maker: info.maker,
                            source: "Kontakt ProductHints manifest; instrument tags inferred from NKI names. Usage and sample completeness not established.",
                            evidence: .manifest, productID: info.snpid.map { "kontakt:snpid:" + $0 },
                            sourceFingerprint: snapshot.fingerprint, installationRoot: url)
                        owner = manifest
                        manifestDetails[manifest.path] = info
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
                }
                let roles = directories.map { role($0.lastPathComponent) }
                let sampleDirectory = roles.contains("samples") || roles.contains("sample data")
                    || directories.contains { data in
                        role(data.lastPathComponent) == "data" && directEntries(data).contains { nested in
                            role(nested.lastPathComponent) == "samples" &&
                                (try? nested.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map {
                                    $0.isDirectory == true && $0.isSymbolicLink != true
                                } == true
                        }
                    }
                let hasPayload = sampleDirectory || entries.contains {
                    $0.pathExtension.lowercased() == "nkx" &&
                    (try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map {
                        $0.isRegularFile == true && $0.isSymbolicLink != true
                    } == true
                }
                let instrumentDirectory = roles.contains("instruments") || roles.contains("instrument")
                let directInstrument = entries.contains { ["nki", "nkm"].contains($0.pathExtension.lowercased()) }
                // Legacy packages may put one or two patch carriers beside bonus
                // content; a maker's broad collection folder is not this boundary.
                let carriers = directories.filter { role($0.lastPathComponent).hasSuffix(" core library") }
                let packagedCore = (1...2).contains(carriers.count) && roles.contains(where: { $0.hasPrefix("bonus ") })
                    && carriers.contains(where: directPatch)
                if owner == nil, !ambiguous,
                   ((hasPayload && (instrumentDirectory || directInstrument)) || packagedCore) {
                    add(url, name: url.lastPathComponent, player: "Kontakt", maker: "Unknown maker",
                        source: "Proposed package boundary from patch and content structure. Maker and product require confirmation; not a removal boundary.",
                        evidence: .proposed, installationRoot: url)
                    owner = url
                }
                if entries.contains(where: { $0.lastPathComponent == "libraryInfo.lib" }),
                   entries.contains(where: { $0.lastPathComponent == "Parts" }) {
                    add(url, name: url.lastPathComponent, player: "Soundpaint", maker: "Soundpaint", source: "Soundpaint libraryInfo + Parts metadata; library name from installation folder. Usage not established.", installationRoot: url); owner = url
                }
                if ["Omnisphere", "Trilian", "Keyscape"].contains(url.lastPathComponent), entries.contains(where: { $0.lastPathComponent == "Soundsources" }), entries.contains(where: { $0.lastPathComponent == "Settings Library" }) {
                    add(url, name: url.lastPathComponent, player: "Spectrasonics", maker: "Spectrasonics", source: "Recognized STEAM player root with Settings Library and Soundsources; named preset catalogs and loose User/Shared folders are indexed separately. Shared Soundsources ownership is not inferred.", installationRoot: url); owner = url
                }
                for child in entries {
                    if Task<Never, Never>.isCancelled { limited = true; break }
                    count += 1
                    if bounded && count > request.maximumEntries { limited = true; break }
                    guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey]) else {
                        issues.append(ScanIssue(path: child.path, reason: "Library candidate metadata unavailable; scan is incomplete"))
                        continue
                    }
                    guard values.isSymbolicLink != true else {
                        issues.append(ScanIssue(path: child.path, reason: "Linked library candidate needs its target included as a library location"))
                        continue
                    }
                    if values.isDirectory == true {
                        // Do not walk millions of sample payloads or unrelated app/project packages.
                        let name = child.lastPathComponent.lowercased()
                        // Samples can be a collection container before a product owns it.
                        // Once owned, it is payload and remains outside patch discovery.
                        if bounded && ((name == "samples" && owner != nil) || ["sample data", "imported samples", "audio", "documentation", "resources", "snapshots", "soundsources", "images"].contains(name)) { continue }
                        if ["app", "logicx", "band", "component", "vst3", "aaxplugin"].contains(child.pathExtension.lowercased()) { continue }
                        pending.append((child, depth + 1, owner))
                    } else if ["nki", "nkm", "nksn", "dspreset"].contains(child.pathExtension.lowercased()) {
                        let player = child.pathExtension.lowercased() == "dspreset" ? "Decent Sampler" : "Kontakt"
                        if claimedInstruments.contains(child.path) { continue }
                        // Do not attach a Decent preset to an inferred Kontakt product.
                        let matchingOwner = owner.flatMap { assets[$0.path]?.format == player ? $0 : nil }
                        let fallback = assets[url.path].map { $0.format == player ? url : child } ?? url
                        let group = matchingOwner ?? fallback
                        if matchingOwner == nil { add(group, name: url.lastPathComponent, player: player, maker: "Unknown maker", source: "Unresolved instrument folder; product and maker need identification. Tags inferred from instrument names.", evidence: .unresolved) }
                        let name = child.deletingPathExtension().lastPathComponent
                        var articulations: [LibraryArticulation] = []
                        var coverage = LibraryArticulationCoverage.unknown
                        if player == "Kontakt", let matchingOwner, let info = manifestDetails[matchingOwner.path],
                           let root = assets[matchingOwner.path]?.libraryMetadata?.identity?.installationRoot,
                           child.path.hasPrefix(root + "/"), child.pathExtension.lowercased() == "nki",
                           info.maker == "Spitfire Audio", let before = LibraryScanJournal.stamp(child.path) {
                            do {
                                let groups: KontaktGroupReader.Result
                                if let cache {
                                    var readError: Error?
                                    guard let cached: KontaktGroupReader.Result = cache.value(policy: "kontakt-groups-v1", paths: [child], read: {
                                        do { return try KontaktGroupReader.read(child) }
                                        catch { readError = error; return nil }
                                    }) else { throw readError ?? KontaktGroupReader.ReadError.malformed }
                                    groups = cached
                                } else { groups = try KontaktGroupReader.read(child) }
                                guard LibraryScanJournal.stamp(child.path) == before else {
                                    issues.append(ScanIssue(path: child.path, reason: "Kontakt patch changed during technique indexing; scan is incomplete"))
                                    continue
                                }
                                if let choices = SpitfireBrushProfile.articulations(manifest: info, groups: groups) {
                                    articulations = choices
                                    coverage = LibraryArticulationCoverage(
                                        status: choices.isEmpty ? .knownEmpty : .indexed,
                                        adapter: SpitfireBrushProfile.adapter,
                                        adapterVersion: SpitfireBrushProfile.version,
                                        sourceVersion: groups.sourceVersion,
                                        sourceSignature: LibraryScanJournal.signature(before))
                                }
                            } catch KontaktGroupReader.ReadError.cancelled { limited = true; break }
                            catch { /* Unsupported or protected patch: coverage remains unknown. */ }
                        }
                        append(LibraryInstrument(name: name, path: child.path,
                                                 tags: LibraryMetadataReader.tags(name),
                                                 articulations: articulations,
                                                 articulationCoverage: coverage), owner: group)
                    } else if child.lastPathComponent == "info.json", let owner, assets[owner.path]?.format == "Soundpaint" {
                        let part: LibraryInstrument?
                        if let cache {
                            part = cache.value(policy: "soundpaint-part-v1", paths: [child]) {
                                LibraryMetadataReader.soundpaintPart(child)
                            }
                        } else { part = LibraryMetadataReader.soundpaintPart(child) }
                        if let part { append(part, owner: owner) }
                    } else if child.pathExtension.lowercased() == "otmeta", owner == nil {
                        // Identity is read from the SINE catalog, never guessed from these mic files.
                        continue
                    }
                }
            } catch { issues.append(ScanIssue(path: url.path, reason: "Cannot read library metadata: \(error.localizedDescription)")) }
        }
        for root in request.libraries.sorted(by: { $0.path < $1.path }) {
            if Task<Never, Never>.isCancelled {
                issues.append(ScanIssue(path: root.path, reason: "Library indexing cancelled; scan is incomplete"))
                break
            }
            count = 0; limited = false; visited = []
            pending = [(root.standardizedFileURL, 0, nil)]
            let journal: LibraryScanJournal?
            if let journalBaseURL, !bounded {
                let savedAssets = assets, savedInstruments = instruments, savedInstrumentPaths = instrumentPaths
                let savedClaimed = claimedInstruments, savedManifests = manifestDetails, savedIssues = issues
                let savedSinePairCandidates = sinePairCandidates
                do {
                    let opened = try LibraryScanJournal(baseURL: journalBaseURL, scope: CatalogScope(request), root: root, source: sineDatabase)
                    let frontier = try opened.replay { record in
                        visited.insert(record.directory)
                        sinePairCandidates.formUnion(record.stamps.filter { URL(fileURLWithPath: $0.path).pathExtension.lowercased() == "otmeta" }.map(\.path))
                        for asset in record.assets { assets[asset.path] = asset }
                        for (owner, children) in record.instruments {
                            instruments[owner, default: []].append(contentsOf: children)
                            instrumentPaths[owner, default: []].formUnion(children.map(\.path))
                            claimedInstruments.formUnion(children.map(\.path))
                        }
                        manifestDetails.merge(record.manifests) { _, new in new }
                        issues.append(contentsOf: record.issues)
                    }
                    if let frontier {
                        pending = frontier.map { (URL(fileURLWithPath: $0.path), $0.depth, $0.inherited.map { URL(fileURLWithPath: $0) }) }
                    }
                    count = visited.count
                    journal = opened
                } catch {
                    LibraryScanJournal.discard(baseURL: journalBaseURL, scope: CatalogScope(request), root: root)
                    assets = savedAssets; instruments = savedInstruments; instrumentPaths = savedInstrumentPaths
                    claimedInstruments = savedClaimed; manifestDetails = savedManifests; issues = savedIssues
                    sinePairCandidates = savedSinePairCandidates
                    visited = []; count = 0; pending = [(root.standardizedFileURL, 0, nil)]
                    issues.append(ScanIssue(path: root.path, reason: "Library discovery checkpoint unavailable; scanning this root from the beginning: \(error.localizedDescription)"))
                    journal = nil
                }
            } else { journal = nil }
            var recording = journal != nil
            while let next = pending.popLast() {
                if Task<Never, Never>.isCancelled {
                    issues.append(ScanIssue(path: root.path, reason: "Library indexing cancelled; scan is incomplete"))
                    break
                }
                let priorAssetKeys = Set(assets.keys)
                let priorInstrumentCounts = instruments.mapValues(\.count)
                let priorManifestKeys = Set(manifestDetails.keys)
                let priorIssueCount = issues.count
                let beforeDirectory = LibraryScanJournal.stamp(next.url.path)
                checkpointCandidates = []
                walk(next.url, depth: next.depth, inherited: next.inherited)
                sinePairCandidates.formUnion(checkpointCandidates.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "otmeta" })
                if Task<Never, Never>.isCancelled {
                    issues.append(ScanIssue(path: root.path, reason: "Library indexing cancelled; scan is incomplete"))
                    journal?.discardUncommitted()
                    break
                }
                if let journal, recording {
                    guard LibraryScanJournal.stamp(next.url.path) == beforeDirectory else {
                        issues.append(ScanIssue(path: next.url.path, reason: "Library directory changed during indexing; scan is incomplete"))
                        journal.discardUncommitted(); recording = false
                        continue
                    }
                    if issues.count > priorIssueCount {
                        journal.discardUncommitted()
                        recording = false
                        continue
                    }
                    let stampPaths = [next.url.path] + checkpointCandidates
                    let stamps = stampPaths.compactMap(LibraryScanJournal.stamp)
                    // A missing or changed candidate means this directory is not a
                    // stable checkpoint. A later pass must revisit it.
                    guard stamps.count == stampPaths.count else {
                        issues.append(ScanIssue(path: next.url.path, reason: "Library candidate changed during indexing; scan is incomplete"))
                        journal.discardUncommitted()
                        recording = false
                        continue
                    }
                    let added = assets.keys.filter { !priorAssetKeys.contains($0) }.compactMap { assets[$0] }
                    var addedInstruments: [String: [LibraryInstrument]] = [:]
                    for (owner, children) in instruments {
                        let earlier = priorInstrumentCounts[owner] ?? 0
                        if children.count > earlier { addedInstruments[owner] = Array(children.dropFirst(earlier)) }
                    }
                    let manifests = manifestDetails.filter { !priorManifestKeys.contains($0.key) }
                    let record = LibraryScanJournal.Record(
                        directory: next.url.path, stamps: stamps,
                        assets: added, instruments: addedInstruments, manifests: manifests,
                        issues: Array(issues.dropFirst(priorIssueCount)))
                    do { try journal.append(record, frontier: pending.map { LibraryScanJournal.Pending(path: $0.url.path, depth: $0.depth, inherited: $0.inherited?.path) }) }
                    catch {
                        issues.append(ScanIssue(path: root.path, reason: "Library discovery checkpoint could not be saved; scan is incomplete"))
                        journal.discardUncommitted(); recording = false
                    }
                }
            }
            if !Task<Never, Never>.isCancelled, recording {
                do { try journal?.flush() }
                catch { issues.append(ScanIssue(path: root.path, reason: "Library discovery checkpoint could not be saved; scan is incomplete")) }
            } else { journal?.discardUncommitted() }
            if limited { issues.append(ScanIssue(path: root.path, reason: "Library entry or depth limit reached; scan is incomplete")) }
        }
        for key in assets.keys {
            guard var item = assets[key], var metadata = item.libraryMetadata else { continue }
            metadata.instruments = instruments[key, default: []].sorted { ($0.name, $0.path) < ($1.name, $1.path) }
            metadata.tags = metadata.productTags(productName: item.name)
            item.libraryMetadata = metadata; assets[key] = item
        }
        // Installers sometimes keep a second NICNT inside an installation's artwork
        // folder. It is product metadata, not another physical library. Suppress only
        // a nested, patchless duplicate beneath a proven same-product patch owner;
        // separate copies and nested installations with patches remain distinct.
        let manifestAssets = assets.values.filter { $0.libraryMetadata?.identity?.evidence == .manifest }
        let redundant = manifestAssets.filter { candidate in
            guard candidate.libraryMetadata?.instruments.isEmpty == true,
                  let identity = candidate.libraryMetadata?.identity,
                  let productID = identity.productID,
                  let fingerprint = identity.sourceFingerprint,
                  let root = identity.installationRoot else { return false }
            return manifestAssets.contains { owner in
                guard owner.path != candidate.path,
                      owner.libraryMetadata?.identity?.productID == productID,
                      owner.libraryMetadata?.identity?.sourceFingerprint == fingerprint,
                      owner.libraryMetadata?.instruments.isEmpty == false,
                      let ownerRoot = owner.libraryMetadata?.identity?.installationRoot else { return false }
                return root.hasPrefix(ownerRoot + "/")
            }
        }
        for candidate in redundant { assets.removeValue(forKey: candidate.path) }
        if !Task<Never, Never>.isCancelled {
            for asset in SpectrasonicsLibraryIndex.discover(products: Array(assets.values), cache: cache, issues: &issues) {
                assets[asset.path] = asset
            }
            let sineAssets = LibraryMetadataReader.sine(sineDatabase, roots: request.libraries, sampleRoots: request.samples, cache: cache, issues: &issues)
            let claimed = Set(sineAssets.flatMap { asset in
                (asset.libraryMetadata?.instruments ?? []).flatMap { $0.contentPaths ?? [] }
            })
            for asset in sineAssets {
                assets[asset.libraryMetadata?.identity?.productID ?? asset.path] = asset
            }
            var unassociatedClusters: [String: [String]] = [:]
            for path in sinePairCandidates.sorted() where !claimed.contains(path) {
                let metadataFile = URL(fileURLWithPath: path)
                let archive = metadataFile.deletingPathExtension().appendingPathExtension("otarc")
                guard LibraryMetadataReader.physicalPairSnapshot(metadataFile, archive: archive) != nil else {
                    issues.append(ScanIssue(path: path,
                        reason: "SINE physical metadata has no stable regular archive pair; content coverage incomplete",
                        kind: .library))
                    continue
                }
                let parent = metadataFile.deletingLastPathComponent()
                let aboveMic = parent.deletingLastPathComponent()
                let withinScope = request.libraries.contains { root in
                    let base = root.standardizedFileURL.path
                    return aboveMic.path == base || aboveMic.path.hasPrefix(base + "/")
                }
                let cluster = withinScope ? aboveMic : parent
                unassociatedClusters[cluster.path, default: []] += [metadataFile.path, archive.path]
            }
            for (path, paths) in unassociatedClusters {
                guard let snapshot = LibraryMetadataReader.physicalContentSnapshot(paths) else {
                    issues.append(ScanIssue(path: path,
                        reason: "SINE physical content changed during cluster indexing; coverage incomplete",
                        kind: .library))
                    continue
                }
                let cluster = URL(fileURLWithPath: path)
                var asset = Asset(kind: .library, path: path, name: cluster.lastPathComponent,
                                  format: "SINE", bundleIdentifier: nil, logicalBytes: snapshot.bytes,
                                  classification: "unassociatedPhysicalContent")
                var metadata = LibraryMetadata(player: "SINE", maker: "Unknown maker", summary: "",
                    instruments: [], tags: [],
                    source: "Existing SINE metadata/archive content without an exact local catalog binding; product and patch identity unresolved.",
                    identity: LibraryIdentity(evidence: .unresolved, productID: nil, installationRoot: nil,
                                              sourceFingerprint: snapshot.fingerprint))
                metadata.physicalContentPaths = paths.sorted()
                metadata.physicalContentIdentity = snapshot.physicalIdentity
                metadata.sizeBasis = .unassociatedContent
                asset.libraryMetadata = metadata
                assets[path] = asset
            }
            if !sinePairCandidates.isEmpty && !fm.fileExists(atPath: sineDatabase.path) {
                issues.append(ScanIssue(path: sineDatabase.path,
                    reason: "SINE catalog unavailable; physical content remains unassociated", kind: .library))
            }
        }
        return assets.values.filter {
            // Do not publish a speculative boundary that yielded no Kontakt patches.
            !($0.format == "Kontakt" && $0.libraryMetadata?.identity?.evidence == .proposed && $0.libraryMetadata?.instruments.isEmpty == true)
        }.sorted { ($0.name, $0.path) < ($1.name, $1.path) }
    }
}
