import Foundation

/// Bounds on presence in the monitored collection, not purchase or license acquisition.
/// A nil lower bound means the asset may have arrived at any earlier time.
public struct AdditionDateEvidence: Codable, Sendable, Equatable {
    public enum Basis: String, Codable, Sendable { case exact, observedArrival, presentBy }
    public let basis: Basis
    public let lower: Date?
    public let upper: Date

    public init(basis: Basis, lower: Date?, upper: Date) throws {
        guard upper.timeIntervalSince1970.isFinite,
              lower.map({ $0.timeIntervalSince1970.isFinite && $0 <= upper }) ?? true,
              (basis == .presentBy ? lower == nil : lower != nil),
              basis != .exact || lower == upper else { throw CatalogStoreError.invalid }
        self.basis = basis; self.lower = lower; self.upper = upper
    }

    public func validated() throws -> Self { try Self(basis: basis, lower: lower, upper: upper) }

    /// Earliest presence across all installations. An unknown sibling destroys a lower
    /// bound, but cannot invalidate a known upper bound supplied by another installation.
    public static func group(_ values: [Self?]) throws -> Self? {
        let known = try values.compactMap { try $0?.validated() }
        guard let upper = known.map(\.upper).min() else { return nil }
        guard known.count == values.count, known.allSatisfy({ $0.lower != nil }),
              let lower = known.compactMap(\.lower).min() else {
            return try Self(basis: .presentBy, lower: nil, upper: upper)
        }
        return try Self(basis: lower == upper && known.allSatisfy({ $0.basis == .exact }) ? .exact : .observedArrival, lower: lower, upper: upper)
    }
}

/// Scan boundary evidence. Capture immediately before synchronous inventory, off the
/// UI/audio thread. The store rechecks physical roots before committing coverage.
/// Root identity includes filesystem UUID, inode and birth time; path-only fallback
/// cannot establish continuity. Changes to discovery policy require a new policy ID.
public struct AdditionScanContext: Sendable {
    public static let policy = "inventory-additions-v1"
    public let startedAt: Date
    let scopeKey: String
    let roots: [String: String]
    public init(scope: CatalogScope, startedAt: Date = Date()) {
        self.startedAt = startedAt; scopeKey = scope.key
        var identities = PhysicalKeys()
        roots = Dictionary(uniqueKeysWithValues: Set(scope.roots.values.flatMap { $0 }).map { ($0, identities.key($0)) })
    }
    func identity(for root: String, scope: CatalogScope, finishedAt: Date) -> String? {
        guard scope.key == scopeKey, startedAt.timeIntervalSince1970.isFinite,
              finishedAt.timeIntervalSince1970.isFinite, startedAt <= finishedAt,
              let before = roots[root], before.hasPrefix("file:") else { return nil }
        var identities = PhysicalKeys()
        let after = identities.key(root)
        return before.utf8.elementsEqual(after.utf8) ? before : nil
    }
}
