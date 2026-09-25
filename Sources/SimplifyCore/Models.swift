import Foundation

public enum AssetKind: String, Codable, Sendable { case plugin, sample, library }

/// A discovered location, not a claim of ownership or safe removability.
public struct Asset: Codable, Sendable {
    public let kind: AssetKind
    public let path: String
    public let name: String
    public let format: String
    public let bundleIdentifier: String?
    public let logicalBytes: Int?
    public let classification: String
    public var libraryMetadata: LibraryMetadata? = nil
    public var fileIdentity: PluginFileIdentity? = nil
    /// Session catalog key. Vendor-backed libraries use product identity even when
    /// their physical content is shared or moves. Other assets retain path identity.
    public var selectionKey: String {
        kind == .library ? (libraryMetadata?.identity?.productID ?? path) : path
    }
}

public struct ScanIssue: Codable, Sendable {
    public let path: String
    public let reason: String
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
}

public struct SampleInclusion: Codable, Sendable {
    public let samplePath: String
    public let projectPaths: [String]
    public let latestReferencingProjectModifiedAt: Date?
    public let status: String
}

public struct ScanReport: Codable, Sendable {
    /// An incomplete inventory has no reference conclusions until the scan finishes.
    public init(inventory: InventorySnapshot) {
        schemaVersion = 1; assets = inventory.assets; projects = []; sampleInclusions = []
        issues = []; durationSeconds = inventory.elapsedSeconds
    }
    internal init(schemaVersion: Int, assets: [Asset], projects: [ProjectReport], sampleInclusions: [SampleInclusion], issues: [ScanIssue], durationSeconds: Double) {
        self.schemaVersion = schemaVersion; self.assets = assets; self.projects = projects
        self.sampleInclusions = sampleInclusions; self.issues = issues; self.durationSeconds = durationSeconds
    }
    public func removingPluginPaths(_ paths: Set<String>) -> ScanReport {
        ScanReport(schemaVersion: schemaVersion, assets: assets.filter { $0.kind != .plugin || !paths.contains($0.path) }, projects: projects, sampleInclusions: sampleInclusions, issues: issues, durationSeconds: durationSeconds)
    }
    public let schemaVersion: Int
    public let assets: [Asset]
    public let projects: [ProjectReport]
    public let sampleInclusions: [SampleInclusion]
    public let issues: [ScanIssue]
    public let durationSeconds: Double
}

public struct ScanRequest: Sendable {
    public var plugins: [URL] = []
    public var samples: [URL] = []
    public var libraries: [URL] = []
    public var projects: [URL] = []
    /// Per collection category; a large sample tree must not starve project discovery.
    public var maximumEntries = 100_000
    public var maximumDepth = 64
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
