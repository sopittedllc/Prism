import Foundation
import Darwin

/// Resolves saved Kontakt library-ID candidates against currently present NICNT manifests.
/// A binding identifies an existing catalog row; it does not establish use or a date.
public enum KontaktLibraryBinding {
    public static let maximumCandidates = 256
    public static let maximumAssets = 1_024
    public static let maximumManifestReadBytes = 16 * 1024 * 1024

    public enum UnresolvedReason: Sendable, Equatable {
        case invalidIdentifier
        case noInstalledManifest
        case ambiguous
        case incomplete
    }

    public struct Binding: Sendable, Equatable {
        public let libraryID: String
        public let catalogID: String?
        public let selectionKey: String
        public let manifestPath: String
    }

    public struct Resolution: Sendable, Equatable {
        public let bindings: [String: Binding]
        public let unresolved: [String: UnresolvedReason]
        /// False means bounded discovery could not establish uniqueness for any candidate.
        public let complete: Bool
    }

    /// Reads at most the configured candidate, asset, and manifest-byte budgets.
    /// Any eligible manifest path/read/parse/stability failure invalidates the whole
    /// result, because an unexamined copy could make an otherwise unique ID ambiguous.
    public static func resolve(libraryIDs: [String], assets: [Asset]) -> Resolution {
        guard libraryIDs.count <= maximumCandidates, assets.count <= maximumAssets else {
            return Resolution(bindings: [:], unresolved: [:], complete: false)
        }

        let candidates = Set(libraryIDs)
        var invalid = Set<String>()
        for id in candidates where !LibraryMetadataReader.validKontaktSNPID(id) { invalid.insert(id) }
        let validCandidates = candidates.subtracting(invalid)
        guard !validCandidates.isEmpty else {
            return Resolution(bindings: [:], unresolved: Dictionary(uniqueKeysWithValues: invalid.map { ($0, .invalidIdentifier) }), complete: true)
        }

        var bySNPID: [String: [Asset]] = [:]
        var bytesRead = 0
        let eligible = assets.filter { asset in
            asset.kind == .library && asset.format == "Kontakt" && asset.catalogStale != true &&
            asset.libraryMetadata?.identity?.evidence == .manifest
        }
        for asset in eligible {
            let url = URL(fileURLWithPath: asset.path)
            guard LibraryMetadataReader.safe(url), let before = snapshot(url) else {
                return incomplete(validCandidates.union(invalid))
            }
            let available = maximumManifestReadBytes - bytesRead
            guard available > 0 else {
                return incomplete(validCandidates.union(invalid))
            }
            guard let data = try? BoundedFile.readThrough(url, terminator: Data("</ProductHints>".utf8),
                    limit: min(available, LibraryMetadataReader.maximumManifestPrefixBytes)) else {
                return incomplete(validCandidates.union(invalid))
            }
            bytesRead += data.count
            guard let details = LibraryMetadataReader.parseKontaktManifestDetails(data),
                  let after = snapshot(url), before == after, LibraryMetadataReader.safe(url) else {
                return incomplete(validCandidates.union(invalid))
            }
            if let snpid = details.snpid {
                bySNPID[snpid, default: []].append(asset)
            }
        }

        var bindings: [String: Binding] = [:]
        var unresolved: [String: UnresolvedReason] = Dictionary(uniqueKeysWithValues: invalid.map { ($0, .invalidIdentifier) })
        for id in validCandidates {
            let matches = bySNPID[id] ?? []
            if matches.count > 1 {
                unresolved[id] = .ambiguous
            } else if let asset = matches.first {
                bindings[id] = Binding(libraryID: id, catalogID: asset.catalogID,
                                       selectionKey: asset.selectionKey, manifestPath: asset.path)
            } else {
                unresolved[id] = .noInstalledManifest
            }
        }
        return Resolution(bindings: bindings, unresolved: unresolved, complete: true)
    }

    private struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    private static func snapshot(_ url: URL) -> FileSnapshot? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileSnapshot(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
                            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
                            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec))
    }

    private static func incomplete(_ candidates: Set<String>) -> Resolution {
        Resolution(bindings: [:], unresolved: Dictionary(uniqueKeysWithValues: candidates.map { ($0, .incomplete) }), complete: false)
    }
}
