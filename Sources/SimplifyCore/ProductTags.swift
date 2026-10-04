import Foundation
import CryptoKit

/// A reviewed official product source. Website descriptions are never treated as patch inventories.
public struct ProductTagSource: Sendable {
    public enum Format: Sendable { case shopify, productJSONLD, wordpress, metaDescription }
    public let id: String
    public let kind: AssetKind
    public let names: [String]
    public let makers: [String]
    public let bundlePrefix: String?
    public let endpoint: URL
    public let page: URL
    public let format: Format
    public let remoteName: String
    public let descriptionDigest: String
    public let metadata: MusicalMetadata

    public func matches(_ asset: Asset) -> Bool {
        guard asset.kind == kind, names.map(Self.identity).contains(Self.identity(asset.name)) else { return false }
        if kind == .plugin {
            guard let bundlePrefix, let bundle = asset.bundleIdentifier else { return false }
            return bundle.lowercased().hasPrefix(bundlePrefix.lowercased() + ".")
        }
        guard let maker = asset.libraryMetadata?.maker else { return false }
        return makers.map(Self.identity).contains(Self.identity(maker))
    }
    static func identity(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// Whitespace-only normalization deliberately rejects meaningful vendor wording changes.
    public static func digest(_ description: String) -> String {
        let text = description.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func parse(_ data: Data) throws -> ProductTagRecord {
        guard data.count <= ProductTagClient.maximumBytes else { throw ProductTagError.tooLarge }
        let name: String, description: String
        switch format {
        case .shopify:
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let product = root["product"] as? [String: Any], let title = product["title"] as? String,
                  let body = product["body_html"] as? String else { throw ProductTagError.changed }
            name = title; description = body
        case .wordpress:
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = root["title"] as? [String: Any], let titleText = title["rendered"] as? String,
                  let content = root["excerpt"] as? [String: Any], let body = content["rendered"] as? String else { throw ProductTagError.changed }
            name = titleText; description = body
        case .metaDescription:
            let html = String(decoding: data, as: UTF8.self)
            let titlePattern = try NSRegularExpression(pattern: #"(?is)<title\b[^>]*>(.*?)</title\s*>"#)
            guard let titleMatch = titlePattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let titleRange = Range(titleMatch.range(at: 1), in: html) else { throw ProductTagError.changed }
            name = String(html[titleRange])
            let metaPattern = try NSRegularExpression(pattern: #"(?is)<meta\b[^>]*>"#)
            let attributes = try NSRegularExpression(pattern: #"(?is)([a-z:-]+)\s*=\s*(["'])(.*?)\2"#)
            var descriptions: [String] = []
            for match in metaPattern.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let range = Range(match.range, in: html) else { continue }
                let tag = String(html[range]); var values: [String: String] = [:]
                for attribute in attributes.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                    guard let key = Range(attribute.range(at: 1), in: tag), let value = Range(attribute.range(at: 3), in: tag) else { continue }
                    values[String(tag[key]).lowercased()] = String(tag[value])
                }
                if values["name"]?.lowercased() == "description", let value = values["content"] { descriptions.append(value) }
            }
            guard descriptions.count == 1 else { throw ProductTagError.changed }
            description = descriptions[0]
        case .productJSONLD:
            let html = String(decoding: data, as: UTF8.self)
            let expression = try NSRegularExpression(pattern: #"(?is)<script\b[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script\s*>"#)
            var products: [[String: Any]] = []
            func collect(_ value: Any) {
                if let array = value as? [Any] { for item in array { collect(item) } }
                if let object = value as? [String: Any] {
                    if object["@type"] as? String == "Product" { products.append(object) }
                    if let graph = object["@graph"] { collect(graph) }
                }
            }
            for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let range = Range(match.range(at: 1), in: html),
                      let value = try? JSONSerialization.jsonObject(with: Data(html[range].utf8)) else { continue }
                collect(value)
            }
            let exact = products.filter { $0["name"] as? String == remoteName }
            guard exact.count == 1, let body = exact[0]["description"] as? String else { throw ProductTagError.changed }
            name = remoteName; description = body
        }
        guard name == remoteName, Self.digest(description) == descriptionDigest else { throw ProductTagError.changed }
        return ProductTagRecord(sourceID: id, descriptionDigest: descriptionDigest, fetchedAt: Date())
    }
}

/// No page bodies, local filenames, or user edits are persisted in the online cache.
public struct ProductTagRecord: Codable, Sendable, Equatable {
    public let sourceID: String
    public let descriptionDigest: String
    public let fetchedAt: Date
    public init(sourceID: String, descriptionDigest: String, fetchedAt: Date) {
        self.sourceID = sourceID; self.descriptionDigest = descriptionDigest; self.fetchedAt = fetchedAt
    }
    public func isFresh(at now: Date = Date()) -> Bool {
        fetchedAt <= now && now.timeIntervalSince(fetchedAt) < 7 * 86400
    }
}
public enum ProductTagError: LocalizedError {
    case changed, tooLarge, response, invalidCache
    public var errorDescription: String? {
        switch self {
        case .changed: "Product information changed or could not be verified; tags need source review."
        case .tooLarge: "Product information exceeds the supported size."
        case .response: "The official product page could not be fetched. Try again later."
        case .invalidCache: "Saved product tags could not be read. The cache has been left unchanged."
        }
    }
}

private final class ProductTagRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Canonical endpoints must be reviewed again when vendors move them.
        completionHandler(nil)
    }
}
public enum ProductTagClient {
    public static let maximumBytes = 2 * 1024 * 1024
    public static func fetch(_ source: ProductTagSource) async throws -> ProductTagRecord {
        guard source.endpoint.scheme == "https" else { throw ProductTagError.response }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: ProductTagRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.endpoint)
        request.setValue("Simplify/1 ProductMetadata", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == source.endpoint else { throw ProductTagError.response }
        guard response.expectedContentLength <= maximumBytes else { throw ProductTagError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw ProductTagError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try source.parse(data)
    }
}

public actor ProductTagStore {
    public let url: URL
    private struct Envelope: Codable {
        let version: Int
        let records: [ProductTagRecord]
        let failures: [String: Date]?
    }
    public init(url: URL) { self.url = url }
    private func envelope() throws -> Envelope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard LibraryMetadataReader.safe(url),
              let data = try? BoundedFile.read(url, limit: 262_144),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == 1,
              envelope.records.count <= 64, (envelope.failures?.count ?? 0) <= 64,
              (envelope.failures ?? [:]).allSatisfy({ id, date in
                  ProductTagSources.all.contains { $0.id == id } && date.timeIntervalSince1970 > 0 && date <= Date().addingTimeInterval(300)
              }) else { throw ProductTagError.invalidCache }
        return envelope
    }
    public func load() throws -> [String: ProductTagRecord] {
        guard let envelope = try envelope() else { return [:] }
        var result: [String: ProductTagRecord] = [:]
        var seen = Set<String>()
        for record in envelope.records {
            guard !record.sourceID.isEmpty, record.sourceID.count <= 128,
                  record.descriptionDigest.count == 64,
                  record.descriptionDigest.allSatisfy({ "0123456789abcdef".contains($0) }),
                  record.fetchedAt.timeIntervalSince1970 > 0, record.fetchedAt <= Date().addingTimeInterval(300),
                  seen.insert(record.sourceID).inserted else { throw ProductTagError.invalidCache }
            // A reviewed descriptor update is ordinary cache invalidation, not corrupt storage.
            guard let source = ProductTagSources.all.first(where: { $0.id == record.sourceID }),
                  source.descriptionDigest == record.descriptionDigest else { continue }
            result[record.sourceID] = record
        }
        return result
    }
    public func recentFailures(asOf date: Date = Date()) throws -> [String: Date] {
        _ = try load()
        return (try envelope()?.failures ?? [:]).filter { date.timeIntervalSince($0.value) < 24 * 3600 }
    }
    public func markFailure(_ sourceID: String, at date: Date = Date()) throws {
        let records = try load()
        guard ProductTagSources.all.contains(where: { $0.id == sourceID }) else { throw ProductTagError.invalidCache }
        var failures = try envelope()?.failures ?? [:]
        failures[sourceID] = date
        try write(Envelope(version: 1, records: records.values.sorted { $0.sourceID < $1.sourceID }, failures: failures))
    }
    public func save(_ records: [String: ProductTagRecord]) throws {
        _ = try load() // Preserve unreadable/future caches.
        guard records.count <= 64, records.allSatisfy({ key, record in
            key == record.sourceID && record.fetchedAt.timeIntervalSince1970 > 0 && record.fetchedAt <= Date().addingTimeInterval(300) && ProductTagSources.all.contains { $0.id == key && $0.descriptionDigest == record.descriptionDigest }
        }) else { throw ProductTagError.invalidCache }
        var failures = try envelope()?.failures ?? [:]
        for id in records.keys { failures.removeValue(forKey: id) }
        try write(Envelope(version: 1, records: records.values.sorted { $0.sourceID < $1.sourceID }, failures: failures))
    }
    private func write(_ envelope: Envelope) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard LibraryMetadataReader.safe(parent) else { throw ProductTagError.invalidCache }
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
