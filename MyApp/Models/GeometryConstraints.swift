import Foundation

enum GeometryConstraintStrength: String, Codable, Sendable {
    case hard
    case soft
}

enum GeometryConstraintPriority: Int, Codable, Sendable {
    case low = 250
    case normal = 500
    case high = 750
    case protected = 1_000
}

enum GeometryConstraintKind: Codable, Hashable, Sendable {
    case fixedVertex(vertexID: UUID, position: PlanPoint2D)
    case wallLength(wallID: UUID, meters: Double)
    case horizontal(wallID: UUID)
    case vertical(wallID: UUID)
    case perpendicular(firstWallID: UUID, secondWallID: UUID)
    case parallel(firstWallID: UUID, secondWallID: UUID)
    case coincident(firstVertexID: UUID, secondVertexID: UUID)
    case wallOpeningAnchor(openingID: UUID, metersFromStart: Double)
}

struct GeometryConstraint: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let kind: GeometryConstraintKind
    let strength: GeometryConstraintStrength
    let priority: GeometryConstraintPriority
    let provenance: MeasurementProvenance
    let createdAt: Date
    var isEnabled: Bool
}

enum WallLengthAnchorStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case keepStart
    case keepEnd

    var id: String { rawValue }
}

struct SetWallLengthCommand: Codable, Hashable, Sendable {
    let id: UUID
    let wallID: UUID
    let targetLength: Double
    let anchor: WallLengthAnchorStrategy
    let provenance: MeasurementProvenance
    let createdAt: Date
}

struct AddConstraintCommand: Codable, Hashable, Sendable {
    let constraint: GeometryConstraint
}

struct RemoveConstraintCommand: Codable, Hashable, Sendable {
    let constraintID: UUID
}

enum GeometryRevisionCommand: Codable, Hashable, Sendable {
    case setWallLength(SetWallLengthCommand)
    case addConstraint(AddConstraintCommand)
    case removeConstraint(RemoveConstraintCommand)
}

struct GeometryRevisionRecord: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let command: GeometryRevisionCommand
    let previousPlan: ParametricFloorPlan
    let resultingPlan: ParametricFloorPlan
    let previousConstraints: [GeometryConstraint]
    let resultingConstraints: [GeometryConstraint]
    let validation: GeometryValidationResult
}

struct GeometryRevisionTransaction: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let command: GeometryRevisionCommand
    let originalPlan: ParametricFloorPlan
    let candidatePlan: ParametricFloorPlan
    let constraints: [GeometryConstraint]
    let validation: GeometryValidationResult
}

enum ConstraintConflictCode: String, Codable, Sendable {
    case missingGeometry
    case missingAnchor
    case invalidTarget
    case degenerateGeometry
    case fixedVertex
    case verifiedMeasurement
    case unsatisfiedHardConstraint
    case openingOutsideHost
    case unsupportedConfiguration
    case invalidResult
}

struct ConstraintConflict: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let code: ConstraintConflictCode
    let constraintIDs: [UUID]
    let geometryIDs: [UUID]
    let residual: Double?
}

struct ConstraintSolveWarning: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let geometryIDs: [UUID]
}

enum ConstraintSolveResult: Sendable {
    case solved(GeometryRevisionTransaction, warnings: [ConstraintSolveWarning])
    case conflict([ConstraintConflict])
}

struct PrecisionPlanDocument: Codable, Hashable, Sendable {
    static let currentFormatVersion = 2

    var formatVersion = PrecisionPlanDocument.currentFormatVersion
    let baselinePlan: ParametricFloorPlan
    var currentPlan: ParametricFloorPlan
    var constraints: [GeometryConstraint]
    var revisions: [GeometryRevisionRecord]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> PrecisionPlanDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(PrecisionPlanDocument.self, from: data)
        guard document.formatVersion <= currentFormatVersion else {
            throw ParametricGeometryCodingError.unsupportedVersion(document.formatVersion)
        }
        return document
    }
}
