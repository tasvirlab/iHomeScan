import Foundation
import CoreGraphics

/// Framework-independent representation of RoomPlan input. Keeping this type independent from
/// RoomPlan makes coordinate conversion and validation deterministic in unit tests.
struct RoomGeometrySource: Sendable {
    struct Vector3: Codable, Hashable, Sendable {
        let x: Double
        let y: Double
        let z: Double

        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }

    /// Column-major 4-by-4 transform, matching simd_float4x4 storage.
    struct Transform: Codable, Hashable, Sendable {
        let values: [Double]

        static let identity = Transform(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])

        var isValid: Bool {
            values.count == 16 && values.allSatisfy(\.isFinite)
        }

        func applying(to point: Vector3) -> Vector3? {
            guard isValid, point.isFinite else { return nil }
            let x = values[0] * point.x + values[4] * point.y + values[8] * point.z + values[12]
            let y = values[1] * point.x + values[5] * point.y + values[9] * point.z + values[13]
            let z = values[2] * point.x + values[6] * point.y + values[10] * point.z + values[14]
            let w = values[3] * point.x + values[7] * point.y + values[11] * point.z + values[15]
            guard x.isFinite, y.isFinite, z.isFinite, w.isFinite, abs(w) > .ulpOfOne else { return nil }
            return Vector3(x: x / w, y: y / w, z: z / w)
        }
    }

    enum SurfaceKind: String, Codable, CaseIterable, Sendable {
        case wall
        case door
        case window
        case opening
        case floor
    }

    enum Confidence: String, Codable, Sendable {
        case low
        case medium
        case high
        case unknown
    }

    struct Surface: Codable, Hashable, Sendable {
        let identifier: UUID
        let parentIdentifier: UUID?
        let kind: SurfaceKind
        /// RoomPlan dimensions in meters.
        let dimensions: Vector3
        let transform: Transform
        /// Polygon vertices in the surface local plane coordinates.
        let polygonCorners: [Vector3]
        let confidence: Confidence
        let story: Int
    }

    struct Object: Codable, Hashable, Sendable {
        let identifier: UUID
        let parentIdentifier: UUID?
        let category: String
        let dimensions: Vector3
        let transform: Transform
        let confidence: Confidence
        let story: Int
        let attributes: [String]
    }

    let roomIdentifier: UUID
    let roomPlanVersion: Int
    let surfaces: [Surface]
    let objects: [Object]
}

/// Versioned, loss-aware metadata retained alongside the drawing-oriented FloorPlan.
struct RoomPlanGeometryMetadata: Codable, Hashable {
    static let currentFormatVersion = 1

    enum Completeness: String, Codable, Hashable {
        case complete
        case incomplete
        case empty
    }

    struct Point3D: Codable, Hashable {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Surface: Codable, Hashable, Identifiable {
        let id: UUID
        let parentIdentifier: UUID?
        let kind: RoomGeometrySource.SurfaceKind
        let dimensions: Point3D
        /// Original RoomPlan transform, column-major.
        let transform: [Double]
        /// Original local-plane RoomPlan polygon.
        let localPolygon: [Point3D]
        /// Valid world geometry projected to the normalized x/right, y/down floor-plan plane.
        let projectedPolygon: [CGPoint]
        let projectedSegment: FloorPlan.Segment?
        let confidence: RoomGeometrySource.Confidence
        let story: Int
    }

    struct Object: Codable, Hashable, Identifiable {
        let id: UUID
        let parentIdentifier: UUID?
        let category: String
        let dimensions: Point3D
        let transform: [Double]
        let confidence: RoomGeometrySource.Confidence
        let story: Int
        let attributes: [String]
    }

    let formatVersion: Int
    let roomIdentifier: UUID
    let roomPlanVersion: Int
    let coordinateSystem: String
    let completeness: Completeness
    /// Square meters, only when a valid RoomPlan floor polygon was available.
    let floorArea: Double?
    let surfaces: [Surface]
    let objects: [Object]
    let rejectedElementIdentifiers: [UUID]
}
