# Swift State Registry Reference Architecture

Use one typed native registry as the executable authority; the JSON feature registry is
its audited cross-cutting manifest, not a second mutable source of values.

```swift
struct SettingDefinition<Value: Codable & Sendable>: Sendable {
    let id: SettingID
    let defaultValue: Value
    let presetPolicy: InclusionPolicy
    let projectPolicy: InclusionPolicy
    let migration: MigrationPolicy
    // Add the remaining cross-cutting metadata required by project policy.
}

enum InclusionPolicy: Sendable {
    case included
    case excluded(reason: String)
    case notApplicable(reason: String)
}
```

The real implementation should make it impossible to instantiate a setting without all
required policies, using typed scopes or a validated definition builder. UI controls,
defaults/reset, accessibility value formatting, and persistence resolve the same stable
definition. Preset encoding enumerates preset-included definitions; it does not mirror
them in a separate `Preset` struct.

If heterogeneous values require type erasure, keep type checking and encoding inside
the definition. Reject type mismatches before applying. Decode and migrate into a
temporary validated snapshot, then apply atomically. Use explicit `CodingKeys`/stable
IDs and ordered schema migrations; synthesized `Codable` alone is not a migration plan.

Required tests export native registry IDs and preset encoder IDs as JSON, compare them
with `scripts/feature_coverage.py compare`, round-trip distinct non-default values, and
load frozen fixtures from every released schema. UI tests verify restored values with
the settings screen closed and reopened.
