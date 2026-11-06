import Foundation
import SwiftData

/// Ordered list of schema versions. Add lightweight or custom stages here when a new
/// `SchemaVn` is introduced, so existing user data is migrated rather than reset.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

enum Persistence {
    static let storeName = "iHomeScan"

    /// The app's on-disk container (Application Support). Throws instead of resetting data on failure.
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(storeName, schema: schema)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: configuration
        )
    }

    /// Container for tests and previews. Pass a URL for on-disk persistence tests, nil for in-memory.
    static func makeContainer(storeURL: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = if let storeURL {
            ModelConfiguration(schema: schema, url: storeURL)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: configuration)
    }
}
