import Foundation

public enum AssetKind: String, Codable, CaseIterable, Sendable { case plugin, sample, library }

/// A discovered location, not a claim of ownership or safe removability.
public struct Asset: Codable, Sendable {
    public let kind: AssetKind
    public let path: String
    public let name: String
    public let format: String
    public let bundleIdentifier: String?
    public var logicalBytes: Int?
    /// Finder/Spotlight date moved into this location; absent on older catalogs or unsupported volumes.
    public var finderDateAdded: Date? = nil
    public let classification: String
    public var libraryMetadata: LibraryMetadata? = nil
    /// Exact vendor VST3 subcategories shared by Audio Module classes in this bundle.
    public var vst3Categories: VST3CategoryMetadata? = nil
    public var fileIdentity: PluginFileIdentity? = nil
    public var catalogID: String? = nil
    /// Durable catalog item owning this physical plugin installation.
    public var pluginProductID: String? = nil
    public var catalogStale: Bool? = nil
    /// Session catalog key. A persisted catalog ID remains stable across moves.
    /// Before persistence, product plus path keeps physical installations distinct.
    public var selectionKey: String {
        guard kind == .library else { return path }
        return catalogID ?? libraryMetadata?.identity?.productID.map { $0 + "\0" + path } ?? path
    }
}

public struct ScanIssue: Codable, Sendable {
    public let path: String
    public let reason: String
    /// Nil for older reports whose diagnostic ownership is unknown.
    public let kind: AssetKind?
    public init(path: String, reason: String, kind: AssetKind? = nil) {
        self.path = path; self.reason = reason; self.kind = kind
    }
}

/// A saved reference. Project modification time is only a recency proxy.
public struct ProjectReference: Codable, Sendable, Equatable {
    public let kind: AssetKind
    public let value: String
    public let resolvedPath: String?
    public let evidence: String
}

public struct ProjectReport: Codable, Sendable {
    public let path: String
    public let adapter: String
    public let coverage: String
    public let projectModifiedAt: Date?
    public let references: [ProjectReference]
    public let limitations: [String]
    /// Structurally owned Kontakt states only. Nil decodes legacy reports.
    public var kontaktStates: [KontaktSavedState]? = nil
    /// Hash of the bounded project bytes used by the state adapter.
    public var sourceSHA256: String? = nil
    /// Per-ID binding result; unknown IDs remain visible beside known siblings.
    public var kontaktOutcomes: [KontaktLibraryOutcome]? = nil
    /// Version-gated, typed Cubase Spectrasonics states; nil in older reports.
    public var spectrasonicsStates: [SpectrasonicsSavedState]? = nil
    public var spectrasonicsOutcomes: [SpectrasonicsLibraryOutcome]? = nil
    /// Structurally owned VST3 class declarations in a saved host snapshot.
    public var pluginClasses: [ProjectPluginClass]? = nil
    public var sineInstrumentIDs: [String]? = nil
    public var aaxPlugins: [ProToolsSavedPluginReader.Entry]? = nil
    public var logicAUReferences: [LogicSavedAUReader.Reference]? = nil
    /// Exact file whose bytes and modification time define this package snapshot.
    public var sourcePath: String? = nil
    /// Reuse only while the exact source file and this reader policy are unchanged.
    public var sourceSignature: String? = nil
    public var readerPolicyVersion: Int? = nil
}

public struct ProjectPluginClass: Codable, Sendable, Equatable {
    public let instanceOrdinal: Int
    public let classID: String
    public let name: String
}

public struct SpectrasonicsSavedState: Codable, Sendable, Equatable {
    public let instanceOrdinal: Int
    public let state: SpectrasonicsStateReader.Result
}

public struct SpectrasonicsLibraryOutcome: Codable, Sendable, Equatable {
    public let instanceOrdinal: Int
    public let partSlot: Int
    public let libraryName: String
    public let presetName: String
    public let catalogID: String?
    public let status: String
}

public struct KontaktSavedState: Codable, Sendable, Equatable {
    public let instanceOrdinal: Int
    public let libraryIDs: [String]
    public let opaquePayloads: Int
    public let emptyRack: Bool
    public var classification: String {
        if !libraryIDs.isEmpty { return "libraryIDs" }
        return emptyRack ? "emptyKontakt" : "unidentifiedContent"
    }
}

public struct KontaktLibraryOutcome: Codable, Sendable, Equatable {
    public let instanceOrdinal: Int
    public let libraryID: String
    public let catalogID: String?
    public let status: String
}

public struct SampleInclusion: Codable, Sendable, Equatable {
    public let samplePath: String
    public let projectPaths: [String]
    public let latestReferencingProjectModifiedAt: Date?
    public let status: String
}

public struct ScanReport: Codable, Sendable {
    /// An incomplete inventory has no reference conclusions until the scan finishes.
    public init(inventory: InventorySnapshot) {
        schemaVersion = 1; assets = inventory.assets; projects = []; sampleInclusions = []; sampleInclusionsDerived = nil
        issues = []; durationSeconds = inventory.elapsedSeconds
    }
    internal init(schemaVersion: Int, assets: [Asset], projects: [ProjectReport], sampleInclusions: [SampleInclusion], issues: [ScanIssue], durationSeconds: Double,
                  sampleInclusionsDerived: Bool? = nil) {
        self.schemaVersion = schemaVersion; self.assets = assets; self.projects = projects
        self.sampleInclusions = sampleInclusions; self.issues = issues; self.durationSeconds = durationSeconds
        self.sampleInclusionsDerived = sampleInclusionsDerived
    }
    public func replacingAssets(_ assets: [Asset]) -> ScanReport {
        ScanReport(schemaVersion: schemaVersion, assets: assets, projects: projects, sampleInclusions: sampleInclusions, issues: issues, durationSeconds: durationSeconds,
                   sampleInclusionsDerived: sampleInclusionsDerived)
    }
    /// Replace only executed sections; legacy unowned issues remain until a full scan.
    public func merging(previous: ScanReport?, scannedKinds: Set<AssetKind>) -> ScanReport {
        guard let previous, scannedKinds != Set(AssetKind.allCases) else { return self }
        var seenIssues = Set<String>()
        let mergedIssues = (previous.issues.filter { $0.kind.map { !scannedKinds.contains($0) } ?? true } + issues).filter {
            seenIssues.insert(($0.kind?.rawValue ?? "legacy") + "\0" + $0.path + "\0" + $0.reason).inserted
        }
        return ScanReport(schemaVersion: schemaVersion,
            assets: previous.assets.filter { !scannedKinds.contains($0.kind) } + assets,
            projects: scannedKinds.contains(.sample) ? projects : previous.projects,
            sampleInclusions: scannedKinds.contains(.sample) ? sampleInclusions : previous.sampleInclusions,
            issues: mergedIssues,
            durationSeconds: durationSeconds,
            sampleInclusionsDerived: scannedKinds.contains(.sample) ? sampleInclusionsDerived : previous.sampleInclusionsDerived)
    }
    public func removingPluginPaths(_ paths: Set<String>) -> ScanReport {
        ScanReport(schemaVersion: schemaVersion, assets: assets.filter { $0.kind != .plugin || !paths.contains($0.path) }, projects: projects, sampleInclusions: sampleInclusions, issues: issues, durationSeconds: durationSeconds,
                   sampleInclusionsDerived: sampleInclusionsDerived)
    }
    public let schemaVersion: Int
    public let assets: [Asset]
    public let projects: [ProjectReport]
    public let sampleInclusions: [SampleInclusion]
    /// New scope evidence can derive these rows from committed sample nodes and
    /// project references. Nil means an older scope contains explicit rows.
    public let sampleInclusionsDerived: Bool?
    public let issues: [ScanIssue]
    public let durationSeconds: Double

    public static func deriveSampleInclusions(assets: [Asset], projects: [ProjectReport]) -> [SampleInclusion] {
        let orderedProjects = projects.sorted { $0.path < $1.path }
        var referencesByPath: [String: [ProjectReport]] = [:]
        for project in orderedProjects {
            let paths = Set(project.references.filter { $0.kind == .sample }.compactMap(\.resolvedPath))
            for path in paths { referencesByPath[path, default: []].append(project) }
        }
        return assets.filter { $0.kind == .sample }.sorted { $0.path < $1.path }.map { asset in
            let matches = referencesByPath[asset.path] ?? []
            return SampleInclusion(samplePath: asset.path, projectPaths: matches.map(\.path),
                latestReferencingProjectModifiedAt: matches.compactMap(\.projectModifiedAt).max(),
                status: matches.isEmpty ? "noReferencesFoundInScannedProjects" : "referenced")
        }
    }
}

public struct ScanRequest: Sendable {
    public enum LibraryScanMode: Sendable { case complete, boundedDiagnostic }
    public var plugins: [URL] = []
    /// Default discovery locations whose absence is expected, unlike user roots.
    public var optionalPluginRoots: [URL] = []
    public var samples: [URL] = []
    public var libraries: [URL] = []
    public var projects: [URL] = []
    /// Per collection category; a large sample tree must not starve project discovery.
    public var maximumEntries = 100_000
    public var maximumDepth = 64
    /// Normal refresh traverses every reachable supported candidate. Disable
    /// only for a deliberately bounded diagnostic probe.
    public var completeFileScan = true
    /// Normal project refresh must reach later projects in large configured roots.
    /// Set false only for an explicitly bounded diagnostic traversal.
    public var completeProjectScan = true
    /// Complete collection scans continue across work batches. The explicit
    /// diagnostic mode retains entry/depth limits for small boundary probes.
    public var libraryScanMode: LibraryScanMode = .complete
    public init() {}

    public static var standardPluginRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Library", home + "/Library"].flatMap { base in
            ["Components", "VST", "VST3", "CLAP"].map {
                URL(fileURLWithPath: base + "/Audio/Plug-Ins/" + $0)
            } + [URL(fileURLWithPath: base + "/Application Support/Avid/Audio/Plug-Ins")]
        }
    }
}

/// Progress describes a phase, not a guessed whole-scan percentage.
public struct ScanProgress: Sendable {
    public enum Phase: String, Sendable { case discovering, inspecting, matching, complete }
    public let phase: Phase
    public let completed: Int
    public let total: Int?
    public let currentPath: String?
    public let elapsedSeconds: Double
    public let sequence: Int
    public var fraction: Double? {
        guard let total, total > 0 else { return phase == .complete ? 1 : nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
    public init(phase: Phase, completed: Int, total: Int?, currentPath: String?, elapsedSeconds: Double, sequence: Int) {
        self.phase = phase; self.completed = completed; self.total = total
        self.currentPath = currentPath; self.elapsedSeconds = elapsedSeconds; self.sequence = sequence
    }
}

/// Basic inventory is usable before reference analysis finishes. Complete refers
/// only to asset-root discovery; final issues can still report partial coverage.
public struct InventorySnapshot: Sendable {
    public let assets: [Asset]
    public let discoveryComplete: Bool
    public let elapsedSeconds: Double
    public let sequence: Int
}
