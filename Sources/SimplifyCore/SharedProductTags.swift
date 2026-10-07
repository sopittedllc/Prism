import Foundation

public struct SharedProductTagSnapshot: Codable, Sendable {
    public var catalogData: Data?
    public var etag: String?
    public var misses: [String: Date]
    public var serviceRetryAfter: Date?
    public var identifiedRecords: [String: Data]
    public init(catalogData: Data? = nil, etag: String? = nil, misses: [String: Date] = [:], identifiedRecords: [String: Data] = [:], serviceRetryAfter: Date? = nil) {
        self.catalogData = catalogData; self.etag = etag; self.misses = misses; self.identifiedRecords = identifiedRecords; self.serviceRetryAfter = serviceRetryAfter
    }
    private enum CodingKeys: String, CodingKey { case catalogData, etag, misses, identifiedRecords, serviceRetryAfter }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogData = try container.decodeIfPresent(Data.self, forKey: .catalogData)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        misses = try container.decodeIfPresent([String: Date].self, forKey: .misses) ?? [:]
        identifiedRecords = try container.decodeIfPresent([String: Data].self, forKey: .identifiedRecords) ?? [:]
        serviceRetryAfter = try container.decodeIfPresent(Date.self, forKey: .serviceRetryAfter)
    }
}

public actor SharedProductTagStore {
    public static let maximumPersistedBytes = 6 * 1_024 * 1_024
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var application: SharedProductTagStore {
        SharedProductTagStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Simplify/shared-product-tags.json"))
    }
    public func load() throws -> SharedProductTagSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return SharedProductTagSnapshot() }
        guard LibraryMetadataReader.safe(url) else { throw ProductTagError.invalidCache }
        let data = try BoundedFile.read(url, limit: Self.maximumPersistedBytes)
        let value = try JSONDecoder().decode(SharedProductTagSnapshot.self, from: data)
        try validate(value)
        return value
    }
    private func validate(_ value: SharedProductTagSnapshot) throws {
        if let body = value.catalogData { _ = try ProductTagSources.importSharedCatalog(body) }
        guard value.misses.count <= ProductTagSources.maximumSources,
              value.misses.allSatisfy({ $0.key.utf8.count <= 512 && $0.value.timeIntervalSince1970 > 0 }),
              value.serviceRetryAfter.map({ $0.timeIntervalSince1970 > 0 }) ?? true,
              value.etag == nil || value.etag!.utf8.count <= 256,
              value.identifiedRecords.count <= ProductTagSources.maximumSources,
              value.identifiedRecords.values.reduce(0, { $0 + $1.count }) <= 4 * 1_024 * 1_024 else {
            throw ProductTagError.invalidCache
        }
        for (id, data) in value.identifiedRecords {
            let sources = try ProductTagSources.importSharedCatalog(data)
            guard sources.count == 1,
                  sources[0].id == id else { throw ProductTagError.invalidCache }
        }
    }
    public func save(_ value: SharedProductTagSnapshot) throws {
        try validate(value)
        let encoded = try JSONEncoder().encode(value)
        guard encoded.count <= Self.maximumPersistedBytes else { throw ProductTagError.tooLarge }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard LibraryMetadataReader.safe(parent) else { throw ProductTagError.invalidCache }
        try encoded.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
