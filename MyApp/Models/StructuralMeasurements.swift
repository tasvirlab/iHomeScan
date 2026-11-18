import Foundation

enum StructuralMeasurementUnit: String, Codable, Sendable {
    case meters
    case radians
}

struct StructuralMeasurementValue: Codable, Hashable, Sendable {
    let value: Double
    let unit: StructuralMeasurementUnit
    let provenance: MeasurementProvenance
}

enum ColumnShape: String, Codable, Sendable {
    case rectangular
    case square
    case circular
}

enum StructuralReferenceReliability: String, Codable, Sendable {
    case estimated
    case verified
    case unresolved
}

enum WallReferenceFace: String, Codable, Sendable {
    case centerline
    case positiveFace
    case negativeFace
}

enum ReferenceOffsetSide: Int, Codable, Sendable {
    case negative = -1
    case positive = 1
}

enum StructuralReferenceEntity: Codable, Hashable, Sendable {
    case wall(wallID: UUID, face: WallReferenceFace, side: ReferenceOffsetSide)
    case vertex(UUID)
    case point(PlanPoint2D)
    case unresolved
}

struct StructuralReference: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let entity: StructuralReferenceEntity
    let reliability: StructuralReferenceReliability
}

enum ColumnMeasurementKind: String, Codable, Sendable {
    case width
    case depth
    case diameter
    case height
    case rotation
    case baseElevation
    case offset
}

struct ColumnMeasurement: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let columnID: UUID
    let kind: ColumnMeasurementKind
    let value: StructuralMeasurementValue
    let referenceID: UUID?
}

enum StructuralGeometryCompleteness: String, Codable, Sendable {
    case complete
    case partial
    case unresolved
}

struct ColumnArchitecturalMetadata: Codable, Hashable, Sendable {
    var shape: ColumnShape
    var measurements: [ColumnMeasurement]
    var references: [StructuralReference]
    var baseElevation: LengthMeasurement?
    var completeness: StructuralGeometryCompleteness
    var source: GeometrySourceMetadata?
}

enum BeamMeasurementKind: String, Codable, Sendable {
    case length
    case width
    case depth
    case bottomElevation
    case topElevation
}

struct BeamMeasurement: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let beamID: UUID
    let kind: BeamMeasurementKind
    let value: StructuralMeasurementValue
    let referenceID: UUID?
}

enum StructuralConnectionEntity: Codable, Hashable, Sendable {
    case wall(UUID)
    case column(UUID)
    case vertex(UUID)
    case unresolved
}

struct BeamEndpointReference: Codable, Hashable, Sendable {
    let entity: StructuralConnectionEntity
    let reliability: StructuralReferenceReliability
}

struct BeamArchitecturalMetadata: Codable, Hashable, Sendable {
    var measurements: [BeamMeasurement]
    var references: [StructuralReference]
    var startReference: BeamEndpointReference?
    var endReference: BeamEndpointReference?
    /// Nil means no structural support relationship has been verified.
    var verifiedSupportEntityIDs: [UUID]?
    var completeness: StructuralGeometryCompleteness
    var source: GeometrySourceMetadata?
}

enum StructuralConflictCode: String, Codable, Sendable {
    case missingReference
    case missingEntity
    case invalidMeasurement
    case underdeterminedPlacement
    case contradictoryReferences
    case verifiedMeasurementConflict
    case invalidVerticalChain
    case invalidBeamGeometry
}

struct StructuralConflict: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let code: StructuralConflictCode
    let entityIDs: [UUID]
    let measurementIDs: [UUID]
    let residual: Double?
}

struct ResolvedColumnPlacement: Codable, Hashable, Sendable {
    let columnID: UUID
    let position: PlanPoint2D
}

struct ResolvedBeamGeometry: Codable, Hashable, Sendable {
    let beamID: UUID
    let start: PlanPoint2D
    let end: PlanPoint2D
    let length: LengthMeasurement
    let topElevation: LengthMeasurement
}

struct StructuralResolutionResult: Sendable {
    var candidatePlan: ParametricFloorPlan
    var columnPlacements: [ResolvedColumnPlacement]
    var beamGeometries: [ResolvedBeamGeometry]
    var conflicts: [StructuralConflict]
    var unresolvedEntityIDs: [UUID]

    var isValid: Bool { conflicts.isEmpty }
}
