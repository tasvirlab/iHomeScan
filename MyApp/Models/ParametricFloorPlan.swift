import Foundation

struct PlanPoint2D: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    var isFinite: Bool { x.isFinite && y.isFinite }

    func distance(to other: PlanPoint2D) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

enum GeometrySourceKind: String, Codable, Sendable {
    case lidarEstimated
    case manualEntered
    case laserVerified
    case derived
}

enum GeometryVerificationStatus: String, Codable, Sendable {
    case unverified
    case estimated
    case verified
}

enum ArchitecturalMeasurementUnit: String, Codable, Sendable {
    case meters
}

struct MeasurementProvenance: Codable, Hashable, Sendable {
    let source: GeometrySourceKind
    let verificationStatus: GeometryVerificationStatus
    let timestamp: Date?
    /// Meters. Nil means the source did not provide a defensible uncertainty.
    let uncertainty: Double?
}

struct LengthMeasurement: Codable, Hashable, Sendable {
    let value: Double
    var unit: ArchitecturalMeasurementUnit = .meters
    let provenance: MeasurementProvenance
}

struct GeometrySourceMetadata: Codable, Hashable, Sendable {
    let sourceElementID: UUID?
    let confidence: RoomGeometrySource.Confidence
    let originalStart: PlanPoint2D?
    let originalEnd: PlanPoint2D?
    /// Original column-major RoomPlan transform, retained as immutable source evidence.
    let transform: [Double]?
}

struct PlanVertex: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var position: PlanPoint2D
    let source: GeometrySourceMetadata
    /// Every source endpoint represented by this reconciled vertex.
    let mergedEndpointKeys: [String]
}

struct ParametricWall: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let startVertexID: UUID
    let endVertexID: UUID
    let height: LengthMeasurement?
    let thickness: LengthMeasurement?
    let source: GeometrySourceMetadata

    func length(in plan: ParametricFloorPlan) -> Double? {
        guard let start = plan.vertex(id: startVertexID),
              let end = plan.vertex(id: endVertexID) else { return nil }
        return start.position.distance(to: end.position)
    }

    func orientation(in plan: ParametricFloorPlan) -> Double? {
        guard let start = plan.vertex(id: startVertexID),
              let end = plan.vertex(id: endVertexID) else { return nil }
        return atan2(end.position.y - start.position.y, end.position.x - start.position.x)
    }
}

enum WallOpeningKind: String, Codable, Sendable {
    case door
    case window
    case opening
}

enum WallHorizontalAnchor: Codable, Hashable, Sendable {
    /// Distance in meters from the host wall's start vertex along its centerline.
    case distanceFromStart(LengthMeasurement)
}

struct WallOpening: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let hostWallID: UUID
    let kind: WallOpeningKind
    let width: LengthMeasurement?
    let height: LengthMeasurement?
    let verticalOffset: LengthMeasurement?
    let horizontalAnchor: WallHorizontalAnchor
    let source: GeometrySourceMetadata
    /// Optional P1.4 architectural measurements. Nil keeps version-1 opening JSON readable.
    var architecturalMetadata: OpeningArchitecturalMetadata? = nil
}

struct ParametricColumn: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var position: PlanPoint2D
    var width: LengthMeasurement
    var depth: LengthMeasurement
    var height: LengthMeasurement?
    /// Radians from the positive x axis.
    var orientation: Double
    var referenceVertexIDs: [UUID]
    /// Optional P1.4.3 architectural measurements; nil keeps legacy JSON readable.
    var architecturalMetadata: ColumnArchitecturalMetadata? = nil
}

enum BeamAnchor: Codable, Hashable, Sendable {
    case vertex(UUID)
    case point(PlanPoint2D)
    case unresolved
}

struct ParametricBeam: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var start: BeamAnchor
    var end: BeamAnchor
    var width: LengthMeasurement
    var depth: LengthMeasurement
    var bottomElevation: LengthMeasurement?
    /// Optional P1.4.3 architectural measurements; nil keeps legacy JSON readable.
    var architecturalMetadata: BeamArchitecturalMetadata? = nil

    func orientation(in plan: ParametricFloorPlan) -> Double? {
        guard let startPoint = point(for: start, in: plan),
              let endPoint = point(for: end, in: plan) else { return nil }
        return atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
    }

    private func point(for anchor: BeamAnchor, in plan: ParametricFloorPlan) -> PlanPoint2D? {
        switch anchor {
        case .vertex(let id): plan.vertex(id: id)?.position
        case .point(let point): point
        case .unresolved: nil
        }
    }
}

enum ParametricGeometryCompleteness: String, Codable, Sendable {
    case complete
    case partial
    case empty
}

struct ParametricRevision: Codable, Hashable, Sendable {
    let number: Int
    let createdAt: Date
    let source: GeometrySourceKind
}

struct EndpointMergeRecord: Codable, Hashable, Sendable {
    let vertexID: UUID
    let endpointKeys: [String]
    let maximumSeparation: Double
}

struct ParametricFloorPlan: Codable, Hashable, Identifiable, Sendable {
    static let currentFormatVersion = 2

    let id: UUID
    let projectID: UUID
    let roomID: UUID
    let sourceScanID: UUID
    var formatVersion: Int = ParametricFloorPlan.currentFormatVersion
    let coordinateSystem: String
    let completeness: ParametricGeometryCompleteness
    var vertices: [PlanVertex]
    var walls: [ParametricWall]
    var openings: [WallOpening]
    var columns: [ParametricColumn]
    var beams: [ParametricBeam]
    /// Reliable RoomPlan floor polygons only. Missing boundary stays nil.
    var floorBoundary: [[PlanPoint2D]]?
    let endpointMerges: [EndpointMergeRecord]
    var revision: ParametricRevision

    func vertex(id: UUID) -> PlanVertex? {
        vertices.first { $0.id == id }
    }

    func wall(id: UUID) -> ParametricWall? {
        walls.first { $0.id == id }
    }

    func connectedWallIDs(vertexID: UUID) -> [UUID] {
        walls.compactMap { wall in
            wall.startVertexID == vertexID || wall.endVertexID == vertexID ? wall.id : nil
        }
    }

    /// Shoelace area for one reliable closed boundary. Open or invalid boundaries stay unavailable.
    var derivedFloorArea: Double? {
        guard let polygon = floorBoundary?.first, polygon.count >= 3,
              polygon.allSatisfy(\.isFinite) else { return nil }
        let doubledArea = polygon.indices.reduce(0.0) { result, index in
            let next = polygon[(index + 1) % polygon.count]
            return result + polygon[index].x * next.y - next.x * polygon[index].y
        }
        let area = abs(doubledArea) / 2
        return area.isFinite && area > 0 ? area : nil
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> ParametricFloorPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var plan = try decoder.decode(ParametricFloorPlan.self, from: data)
        guard plan.formatVersion <= currentFormatVersion else {
            throw ParametricGeometryCodingError.unsupportedVersion(plan.formatVersion)
        }
        plan.formatVersion = currentFormatVersion
        return plan
    }
}

enum ParametricGeometryCodingError: Error, Equatable {
    case unsupportedVersion(Int)
}
