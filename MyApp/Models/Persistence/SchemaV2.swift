import Foundation
import SwiftData

enum SavedScanStatus: String, Codable {
    case saved
}

@Model
final class SavedScan {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var floorID: UUID
    var roomID: UUID
    var createdAt: Date
    var statusRaw: String
    var completenessRaw: String
    var floorArea: Double?
    var sourceAssetID: UUID
    var geometryAssetID: UUID
    var modelAssetID: UUID

    init(
        id: UUID,
        projectID: UUID,
        floorID: UUID,
        roomID: UUID,
        createdAt: Date,
        completeness: RoomPlanGeometryMetadata.Completeness,
        floorArea: Double?,
        sourceAssetID: UUID,
        geometryAssetID: UUID,
        modelAssetID: UUID
    ) {
        self.id = id
        self.projectID = projectID
        self.floorID = floorID
        self.roomID = roomID
        self.createdAt = createdAt
        self.statusRaw = SavedScanStatus.saved.rawValue
        self.completenessRaw = completeness.rawValue
        self.floorArea = floorArea
        self.sourceAssetID = sourceAssetID
        self.geometryAssetID = geometryAssetID
        self.modelAssetID = modelAssetID
    }

    var status: SavedScanStatus {
        SavedScanStatus(rawValue: statusRaw) ?? .saved
    }

    var completeness: RoomPlanGeometryMetadata.Completeness {
        RoomPlanGeometryMetadata.Completeness(rawValue: completenessRaw) ?? .incomplete
    }
}

/// Adds scan metadata without changing any SchemaV1 model in place.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Project.self, Floor.self, Room.self, LocalAsset.self, SavedScan.self]
    }
}
