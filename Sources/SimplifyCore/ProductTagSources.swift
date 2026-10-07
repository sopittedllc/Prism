import Foundation

/// Reviewed offline starter coverage; a matching product page never proves installation or use.
/// See docs/research/product-tag-sources.md for extraction and review constraints.
public enum ProductTagSources {
    public static let maximumSources = 4_096
    /// Version of the bundled, reviewed identity/taxonomy records. Cache envelopes
    /// remain independently versioned and are invalidated by source digests.
    public static let catalogVersion = 2
    public static let all: [ProductTagSource] = {
        let records = try! importReviewedCatalog(bundledCatalogData())
        precondition(records.count <= maximumSources, "Reviewed product tag catalog exceeds its bounded capacity")
        precondition(Set(records.map(\.id)).count == records.count, "Duplicate reviewed product tag source IDs")
        return records
    }()

    /// The versioned structured catalog is the only path for admitting new bundled
    /// taxonomy. It is bounded, exact-identity and schema validated; refreshable vendor
    /// descriptions continue to use ProductTagStore's existing cache and TTL.
    static func importReviewedCatalog(_ data: Data) throws -> [ProductTagSource] {
        try importCatalog(data, allowAutomatic: false)
    }

    public static func importSharedCatalog(_ data: Data) throws -> [ProductTagSource] {
        try importCatalog(data, allowAutomatic: true)
    }

    private static func importCatalog(_ data: Data, allowAutomatic: Bool) throws -> [ProductTagSource] {
        guard data.count <= 4 * 1_024 * 1_024 else { throw ProductTagError.tooLarge }
        let catalog = try JSONDecoder().decode(ReviewedCatalog.self, from: data)
        let automatic = catalog.automaticRecords ?? []
        guard catalog.version == catalogVersion, (1...maximumSources).contains(catalog.records.count + automatic.count),
              allowAutomatic || automatic.isEmpty else { throw ProductTagError.invalidCache }
        var seen = Set<String>()
        let automaticIDs = Set(automatic.map(\.id))
        let sources = try (catalog.records + automatic).map { record in
            guard seen.insert(record.id).inserted, let kind = AssetKind(rawValue: record.kind),
                  let endpoint = URL(string: record.endpoint), let page = URL(string: record.page),
                  let format = ProductTagSource.Format(rawValue: record.format) else { throw ProductTagError.invalidCache }
            let isAutomatic = automaticIDs.contains(record.id)
            let provenance = record.provenance ?? .curated
            guard provenance == (isAutomatic ? .automatic : .curated) else { throw ProductTagError.invalidCache }
            let source = ProductTagSource(id: record.id, kind: kind, names: record.names, makers: record.makers,
                bundlePrefix: record.bundlePrefix, endpoint: endpoint, page: page, format: format,
                remoteName: record.remoteName, descriptionDigest: record.descriptionDigest,
                metadata: try MusicalMetadata(fields: record.metadata).validated(), networkEnabled: record.networkEnabled,
                reviewRecordID: record.reviewRecordID, reviewedAt: record.reviewedAt,
                taxonomyVersion: record.taxonomyVersion, sourceFact: record.sourceFact,
                provenance: provenance)
            try source.validateReviewRecord()
            guard (record.networkEnabled || record.descriptionDigest.isEmpty),
                  [AssetKind.library, .plugin].contains(kind), !record.names.isEmpty,
                  (kind != .plugin || record.bundlePrefix != nil || !record.makers.isEmpty),
                  (kind != .library || !record.makers.isEmpty),
                  record.names.count <= 8, record.makers.count <= 8,
                  record.names.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
                  record.makers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { throw ProductTagError.invalidCache }
            return source
        }
        if !allowAutomatic {
            // Validate generated bundled records within kind and maker. A spaceless
            // format alias must join its existing product, not create a second source.
            func compact(_ text: String) -> String {
                ProductTagSource.identity(text).replacingOccurrences(of: " ", with: "")
            }
            var identities: [String: String] = [:]
            for source in sources {
                for maker in source.makers {
                    for name in source.names {
                        let key = source.kind.rawValue + "|" + compact(maker) + "|" + compact(name)
                        guard identities[key] == nil || identities[key] == source.id else { throw ProductTagError.invalidCache }
                        identities[key] = source.id
                    }
                }
            }
        }
        if !automatic.isEmpty {
            let trusted = sources.filter { $0.provenance == .curated } + ProductTagSources.all
            for source in sources where source.provenance == .automatic {
                guard source.endpoint == source.page, let host = source.page.host?.lowercased(),
                      trusted.contains(where: { known in
                          known.makers.map(ProductTagSource.identity).contains {
                              source.makers.map(ProductTagSource.identity).contains($0)
                          } && known.page.host.map { official in
                              host == official.lowercased() || host.hasSuffix("." + official.lowercased())
                          } == true
                      }) else { throw ProductTagError.invalidCache }
            }
        }
        return sources
    }

    private struct ReviewedCatalog: Decodable {
        let version: Int
        let records: [ReviewedRecord]
        let automaticRecords: [ReviewedRecord]?
    }
    private struct ReviewedRecord: Decodable {
        let id: String; let kind: String; let names: [String]; let makers: [String]; let bundlePrefix: String?
        let endpoint: String; let page: String; let format: String; let remoteName: String
        let descriptionDigest: String; let metadata: [String: [String]]; let networkEnabled: Bool
        let reviewRecordID: String; let reviewedAt: String; let taxonomyVersion: Int
        let sourceFact: String?
        let provenance: ProductTagSource.Provenance?
    }
    static func bundledCatalogData() -> Data {
        let packagedBundleURL = Bundle.main.resourceURL?.appendingPathComponent("Simplify_SimplifyCore.bundle", isDirectory: true)
        let resourceBundle = packagedBundleURL.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = resourceBundle.url(forResource: "product-tag-catalog-v2", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 4 * 1_024 * 1_024 else { preconditionFailure("Reviewed product tag catalog resource is missing or invalid") }
        return data
    }
}
