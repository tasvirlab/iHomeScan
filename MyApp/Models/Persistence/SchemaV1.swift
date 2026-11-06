import Foundation
import SwiftData

// MARK: - Enumerations (persisted as raw strings so new cases never break old stores)

enum ProjectStatus: String, CaseIterable, Codable {
    /// Created, nothing scanned yet.
    case draft
    /// At least one floor has scan data.
    case scanned
}

/// Reserved for the future cloud sync engine. Stage 1 only ever writes `.localOnly`.
enum SyncState: String, CaseIterable, Codable {
    case localOnly
    case pendingUpload
    case synced
    case conflict
}

enum RoomType: String, CaseIterable, Codable, Identifiable {
    case living, bedroom, kitchen, bathroom, toilet, hallway, office, balcony, storage, other

    var id: String { rawValue }
    var titleKey: String { "roomType.\(rawValue)" }
}

enum AssetType: String, CaseIterable, Codable {
    case roomGeometry
    case usdzModel
    case inspectionPhoto
    case projectThumbnail
    case pdfReport

    /// Subfolder inside the project directory.
    var folderName: String {
        switch self {
        case .roomGeometry: "Scans"
        case .usdzModel: "Models"
        case .inspectionPhoto, .projectThumbnail: "Photos"
        case .pdfReport: "Reports"
        }
    }
}

// MARK: - Schema V1

/// First persisted schema. When models change, add `SchemaV2` and a migration stage in
/// `AppMigrationPlan` instead of editing these models in place.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, Floor.self, Room.self, LocalAsset.self]
    }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var projectDescription: String?
    var createdAt: Date
    var updatedAt: Date
    var statusRaw: String
    /// Optional reference to a `LocalAsset` of type `.projectThumbnail`.
    var thumbnailAssetID: UUID?
    var syncStateRaw: String
    /// True for the bundled demo project — its measurements are sample data, not a real scan.
    var isSample: Bool

    @Relationship(deleteRule: .cascade, inverse: \Floor.project)
    var floors: [Floor] = []

    @Relationship(deleteRule: .cascade, inverse: \LocalAsset.project)
    var assets: [LocalAsset] = []

    init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String? = nil,
        status: ProjectStatus = .draft,
        isSample: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.statusRaw = status.rawValue
        self.syncStateRaw = SyncState.localOnly.rawValue
        self.isSample = isSample
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    var sortedFloors: [Floor] { floors.sorted { ($0.level, $0.createdAt) < ($1.level, $1.createdAt) } }
    var allRooms: [Room] { sortedFloors.flatMap(\.sortedRooms) }

    /// Sum of known room areas, or nil when no room has an area yet.
    var totalArea: Double? {
        let areas = allRooms.compactMap(\.effectiveArea)
        return areas.isEmpty ? nil : areas.reduce(0, +)
    }

    /// Highest known ceiling height across rooms.
    var ceilingHeight: Double? { allRooms.compactMap(\.height).max() }

    var reports: [LocalAsset] {
        assets.filter { $0.type == .pdfReport }.sorted { $0.createdAt > $1.createdAt }
    }
}

@Model
final class Floor {
    @Attribute(.unique) var id: UUID
    var level: Int
    /// User-given name; empty means the localized default ("1-qavat", "Floor 1", "Этаж 1").
    var name: String
    var createdAt: Date

    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \Room.floor)
    var rooms: [Room] = []

    /// Floor-level files such as the plan geometry JSON.
    @Relationship(deleteRule: .cascade, inverse: \LocalAsset.floor)
    var assets: [LocalAsset] = []

    init(id: UUID = UUID(), level: Int, name: String, createdAt: Date = .now) {
        self.id = id
        self.level = level
        self.name = name
        self.createdAt = createdAt
    }

    var sortedRooms: [Room] { rooms.sorted { $0.createdAt < $1.createdAt } }

    /// The current floor plan geometry file, if this floor has been scanned.
    var planAsset: LocalAsset? {
        assets.filter { $0.type == .roomGeometry }.max { $0.createdAt < $1.createdAt }
    }
}

@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String?
    /// Square meters. When nil, `effectiveArea` falls back to width × length.
    var area: Double?
    /// Meters.
    var width: Double?
    /// Meters.
    var length: Double?
    /// Ceiling height in meters.
    var height: Double?
    /// Links this room to a room outline in the floor's plan geometry (and later to RoomPlan).
    var geometryIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    var floor: Floor?

    /// Room-level files, e.g. inspection photos.
    @Relationship(deleteRule: .cascade, inverse: \LocalAsset.room)
    var assets: [LocalAsset] = []

    init(
        id: UUID = UUID(),
        name: String,
        type: RoomType? = nil,
        width: Double? = nil,
        length: Double? = nil,
        height: Double? = nil,
        area: Double? = nil,
        geometryIdentifier: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type?.rawValue
        self.width = width
        self.length = length
        self.height = height
        self.area = area
        self.geometryIdentifier = geometryIdentifier
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var type: RoomType? {
        get { typeRaw.flatMap(RoomType.init) }
        set { typeRaw = newValue?.rawValue }
    }

    var effectiveArea: Double? {
        if let area { return area }
        if let width, let length { return width * length }
        return nil
    }

    /// True when no measurement has been recorded yet.
    var isMeasured: Bool { width != nil || length != nil || height != nil || area != nil }
}

/// Metadata for a file stored on disk by `LocalFileStorageService`.
/// Large binaries never live in the database — only their relative path and attributes.
@Model
final class LocalAsset {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    /// Path relative to the storage root, e.g. `Projects/<uuid>/Reports/report.pdf`.
    var relativeFilePath: String
    var fileName: String
    var fileSize: Int64
    var createdAt: Date
    /// SHA-256 hex digest, used to detect corrupted files.
    var checksum: String?

    var project: Project?
    var floor: Floor?
    var room: Room?

    init(
        id: UUID = UUID(),
        type: AssetType,
        relativeFilePath: String,
        fileName: String,
        fileSize: Int64,
        checksum: String?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.relativeFilePath = relativeFilePath
        self.fileName = fileName
        self.fileSize = fileSize
        self.checksum = checksum
        self.createdAt = createdAt
    }

    var type: AssetType? { AssetType(rawValue: typeRaw) }
}
