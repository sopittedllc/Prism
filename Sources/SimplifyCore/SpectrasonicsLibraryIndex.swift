import Foundation
import CryptoKit

/// Installed preset metadata only. No Soundsources or audio payload is opened.
public enum SpectrasonicsLibraryIndex {
    private static let maximumHeaderBytes = 1_048_576
    private static let maximumEntries = 20_000
    private static let supported: [String: String] = [
        "Omnisphere": "prt_omn", "Keyscape": "prt_key", "Trilian": "prt_trl",
    ]

    public static func discover(products: [Asset], issues: inout [ScanIssue]) -> [Asset] {
        discover(products: products, cache: nil, issues: &issues)
    }

    static func discover(products: [Asset], cache: DecodedFactCache?, issues: inout [ScanIssue]) -> [Asset] {
        var result: [Asset] = []
        for product in products where product.kind == .library && product.format == "Spectrasonics" {
            guard let patchExtension = supported[product.name],
                  LibraryMetadataReader.safe(URL(fileURLWithPath: product.path)) else { continue }
            let base = URL(fileURLWithPath: product.path).appendingPathComponent("Settings Library")
            for (branch, fileExtension) in [("Patches", patchExtension), ("Multis", "mlt_omn")] {
                let branchURL = base.appendingPathComponent(branch)
                guard let children = safeChildren(branchURL) else { continue }
                for child in children where child.lastPathComponent == "Factory" {
                    guard let catalogs = safeChildren(child) else { continue }
                    for catalog in catalogs where catalog.pathExtension.lowercased() == "db" {
                        let asset: Asset?
                        if let cache {
                            asset = cache.value(policy: "spectrasonics-factory-v1:\(product.name):\(fileExtension)", paths: [catalog]) {
                                factoryAsset(catalog, product: product.name, fileExtension: fileExtension)
                            }
                        } else { asset = factoryAsset(catalog, product: product.name, fileExtension: fileExtension) }
                        if let asset {
                            result.append(asset)
                        } else if (try? catalog.resourceValues(forKeys: [.fileSizeKey]).fileSize) != 0 {
                            issues.append(ScanIssue(path: catalog.path, reason: "Spectrasonics preset index unavailable or unsupported; patch coverage is partial", kind: .library))
                        }
                    }
                }
                // Physical loose libraries can live directly under Patches/Multis
                // or one level under the generic User/Shared organizer directories.
                for child in children where child.lastPathComponent != "Factory" {
                    let folders = ["User", "Shared"].contains(child.lastPathComponent)
                        ? (safeChildren(child) ?? []) : [child]
                    for folder in folders where isDirectory(folder) {
                        if let asset = looseAsset(folder, product: product.name, fileExtension: fileExtension) {
                            result.append(asset)
                        }
                    }
                }
            }
        }
        return result
    }

    /// Exact part-library plus preset is primary. A blank library may use only a
    /// uniquely installed preset; nonempty conflicts never fall back.
    public static func resolve(part: SpectrasonicsStateReader.Part,
                               player: SpectrasonicsStateReader.Player,
                               assets: [Asset]) -> (asset: Asset, match: String)? {
        guard !part.name.isEmpty else { return nil }
        let candidates = assets.filter { asset in
            asset.kind == .library && asset.catalogStale != true &&
            asset.libraryMetadata?.player == playerName(player) &&
            !asset.path.contains("/Settings Library/Multis/") &&
            (asset.libraryMetadata?.instruments ?? []).contains { instrument in
                instrument.name == part.name && instrument.path.pathExtensionIsPreset &&
                LibraryMetadataReader.safe(URL(fileURLWithPath: instrument.path)) &&
                FileManager.default.fileExists(atPath: instrument.path)
            } && sourceMatches(asset)
        }
        if !part.library.isEmpty {
            let exact = candidates.filter { $0.name == part.library }
            guard exact.count == 1 else { return nil }
            return (exact[0], "exactLibraryAndPreset")
        }
        guard candidates.count == 1 else { return nil }
        return (candidates[0], "uniquePresetFallback")
    }

    /// The catalog header is rechecked at the binding boundary, so a replaced
    /// archive cannot lend its old preset list to a newly saved project.
    public static func sourceMatches(_ asset: Asset) -> Bool {
        if asset.libraryMetadata?.identity?.productID?.hasPrefix("spectrasonics:loose:") == true {
            guard let expected = asset.libraryMetadata?.identity?.sourceFingerprint,
                  let player = asset.libraryMetadata?.player,
                  let fileExtension = asset.path.contains("/Settings Library/Multis/") ? "mlt_omn" : supported[player],
                  let current = looseAsset(URL(fileURLWithPath: asset.path), product: player,
                                           fileExtension: fileExtension) else { return false }
            return current.libraryMetadata?.identity?.sourceFingerprint == expected
        }
        guard asset.libraryMetadata?.identity?.productID?.hasPrefix("spectrasonics:factory:") == true else { return true }
        let url = URL(fileURLWithPath: asset.path)
        guard let expected = asset.libraryMetadata?.identity?.sourceFingerprint,
              let before = LibraryScanJournal.stamp(url.path),
              let xml = try? BoundedFile.readThrough(url, terminator: Data("</FileSystem>".utf8), limit: maximumHeaderBytes),
              LibraryScanJournal.stamp(url.path) == before else { return false }
        let current = SHA256.hash(data: xml).map { String(format: "%02x", $0) }.joined()
        return current == expected
    }

    private static func playerName(_ value: SpectrasonicsStateReader.Player) -> String {
        switch value { case .omnisphere: "Omnisphere"; case .keyscape: "Keyscape"; case .trilian: "Trilian" }
    }

    private static func safeChildren(_ url: URL) -> [URL]? {
        guard LibraryMetadataReader.safe(url), isDirectory(url),
              let values = try? FileManager.default.contentsOfDirectory(at: url,
                  includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles]), values.count <= 4_096 else { return nil }
        return values.sorted { $0.path < $1.path }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map {
            $0.isDirectory == true && $0.isSymbolicLink != true
        } == true
    }

    private static func factoryAsset(_ url: URL, product: String, fileExtension: String) -> Asset? {
        guard LibraryMetadataReader.safe(url),
              let before = LibraryScanJournal.stamp(url.path),
              let xml = try? BoundedFile.readThrough(url, terminator: Data("</FileSystem>".utf8), limit: maximumHeaderBytes),
              let names = fileNames(in: xml, extension: fileExtension), !names.isEmpty,
              LibraryScanJournal.stamp(url.path) == before else { return nil }
        let libraryName = url.deletingPathExtension().lastPathComponent
        var asset = Asset(kind: .library, path: url.path, name: libraryName,
                          format: "Spectrasonics", bundleIdentifier: nil,
                          logicalBytes: Int(before.size), classification: "identifiedLibrary")
        let instruments = names.map { name in
            LibraryInstrument(name: name, path: url.path, tags: [], vendorID: "preset:\(name)")
        }
        let signature = SHA256.hash(data: xml).map { String(format: "%02x", $0) }.joined()
        asset.libraryMetadata = LibraryMetadata(player: product, maker: "Spectrasonics", summary: "",
            instruments: instruments, tags: [],
            source: "Installed Spectrasonics \(product) factory preset catalog. Size is the catalog archive only; shared Soundsources are excluded.",
            identity: LibraryIdentity(evidence: .vendorCatalog,
                productID: "spectrasonics:factory:\(product):\(libraryName)", installationRoot: nil,
                sourceFingerprint: signature))
        return asset
    }

    private static func fileNames(in xml: Data, extension fileExtension: String) -> [String]? {
        guard xml.range(of: Data("<!DOCTYPE".utf8)) == nil,
              xml.range(of: Data("<!ENTITY".utf8)) == nil else { return nil }
        let delegate = FileListXML(fileExtension)
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.failed, delegate.depth == 0 else { return nil }
        return delegate.names.sorted()
    }

    private final class FileListXML: NSObject, XMLParserDelegate {
        let fileExtension: String
        var names = Set<String>()
        var depth = 0
        var failed = false
        init(_ fileExtension: String) { self.fileExtension = fileExtension }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            depth += 1
            guard depth <= 32, attributes.count <= 64, names.count <= maximumEntries else {
                failed = true; parser.abortParsing(); return
            }
            if depth == 1, name != "FileSystem" { failed = true; parser.abortParsing(); return }
            if name == "FILE", let filename = attributes["name"],
               filename.pathExtension.lowercased() == fileExtension {
                names.insert((filename as NSString).deletingPathExtension)
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            depth -= 1
        }
    }

    private static func looseAsset(_ directory: URL, product: String, fileExtension: String) -> Asset? {
        guard LibraryMetadataReader.safe(directory), isDirectory(directory),
              let enumerator = FileManager.default.enumerator(at: directory,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return nil }
        var files: [URL] = []
        var seen = 0
        for case let file as URL in enumerator {
            if Task<Never, Never>.isCancelled { return nil }
            seen += 1
            guard seen <= maximumEntries else { return nil }
            guard file.pathExtension.lowercased() == fileExtension,
                  LibraryMetadataReader.safe(file),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).map({
                      $0.isRegularFile == true && $0.isSymbolicLink != true
                  }) == true else { continue }
            files.append(file)
        }
        guard !files.isEmpty else { return nil }
        let sortedFiles = files.sorted { $0.path < $1.path }
        let stamps = sortedFiles.compactMap { LibraryScanJournal.stamp($0.path) }
        guard stamps.count == sortedFiles.count else { return nil }
        let signature = SHA256.hash(data: Data(stamps.map(LibraryScanJournal.signature).joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        let name = directory.lastPathComponent
        var asset = Asset(kind: .library, path: directory.path, name: name,
                          format: "Spectrasonics", bundleIdentifier: nil,
                          logicalBytes: nil, classification: "needsIdentification")
        let instruments = sortedFiles.map { file in
            LibraryInstrument(name: file.deletingPathExtension().lastPathComponent,
                              path: file.path, tags: [])
        }
        asset.libraryMetadata = LibraryMetadata(player: product, maker: "Unknown maker", summary: "",
            instruments: instruments, tags: [],
            source: "Physical third-party preset folder; requires \(product). Maker and shared Soundsources are unverified.",
            identity: LibraryIdentity(evidence: .proposed,
                productID: "spectrasonics:loose:\(product):\(directory.path)",
                installationRoot: directory.path, sourceFingerprint: signature))
        return asset
    }
}

private extension String {
    var pathExtension: String { (self as NSString).pathExtension }
    var pathExtensionIsPreset: Bool { ["db", "prt_omn", "prt_key", "prt_trl"].contains(pathExtension.lowercased()) }
}
