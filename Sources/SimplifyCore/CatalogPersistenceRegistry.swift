import Foundation

/// Logical persistent field groups. Internal SQL columns implement these contracts;
/// catalog_state_check compares every ID/default and concern with the policy document.
public enum CatalogPersistenceRegistry {
    public struct Field: Codable, Sendable {
        public let id: String
        public let value_type: String
        public let `default`: [String: String]
        public let introduced_in: Int
    }
    public static let definitions: [Field] = [
        Field(id: "catalog.inventory", value_type: "object", default: [:], introduced_in: 1),
        Field(id: "catalog.observations", value_type: "object", default: [:], introduced_in: 1),
        Field(id: "catalog.scopes", value_type: "object", default: [:], introduced_in: 1),
        Field(id: "catalog.removal_intents", value_type: "object", default: [:], introduced_in: 1),
        Field(id: "catalog.musical_metadata", value_type: "object", default: [:], introduced_in: 2),
        Field(id: "catalog.product_tags", value_type: "object", default: [:], introduced_in: 2),
        Field(id: "catalog.root_baselines", value_type: "object", default: [:], introduced_in: 2),
        Field(id: "catalog.date_evidence", value_type: "object", default: [:], introduced_in: 3),
        Field(id: "catalog.date_subjects", value_type: "object", default: [:], introduced_in: 6),
        Field(id: "catalog.plugin_products", value_type: "object", default: [:], introduced_in: 5),
        Field(id: "catalog.discovery_journal", value_type: "object", default: [:], introduced_in: 5),
        Field(id: "catalog.decoded_facts", value_type: "object", default: [:], introduced_in: 6),
    ]
    public static let schemaVersion = 6
}
