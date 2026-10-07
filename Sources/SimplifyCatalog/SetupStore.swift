import Foundation
import CoreFoundation
import SimplifyCore

/// Versioned, local-only setup. Only registry-selected IDs are encoded.
public struct SetupStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var application: SetupStore {
        SetupStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Simplify/setup.json"))
    }
    @MainActor public func load() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try BoundedFile.read(url, limit: 1_048_576)
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = envelope["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let values = envelope["settings"] as? [String: Any] else { throw SetupError.invalid }
        var result: [String: Any] = [:]
        for definition in CatalogStateRegistry.definitions where definition["persisted"] as? Bool == true {
            let key = definition["id"] as! String
            let value = values[key] ?? definition["default"]!
            if key == "roots" {
                guard let roots = value as? [String: [String]], roots.keys.allSatisfy({ RootKind(rawValue: $0) != nil }),
                      roots.values.flatMap({ $0 }).allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { throw SetupError.invalid }
            } else if key == "appearance" {
                guard let raw = value as? String, CatalogAppearance(rawValue: raw) != nil else { throw SetupError.invalid }
            } else {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw SetupError.invalid }
            }
            result[key] = value
        }
        return result
    }
    @MainActor public func save(_ snapshot: [String: Any]) throws {
        // Never silently replace an unreadable or newer-version configuration.
        _ = try load()
        let ids = CatalogStateRegistry.persistedIDs
        guard ids.allSatisfy({ snapshot[$0] != nil }) else { throw SetupError.invalid }
        let settings = snapshot.filter { ids.contains($0.key) }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "settings": settings], options: [.prettyPrinted, .sortedKeys])
        guard data.count <= 1_048_576 else { throw SetupError.invalid }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public enum SetupError: LocalizedError {
    case invalid
    public var errorDescription: String? { "Saved setup couldn't be read, or belongs to a newer version. Your saved file has been left unchanged. You can use setup for this session." }
}
