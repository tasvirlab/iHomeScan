import Foundation

enum OpeningReferenceReliability: String, Codable, Sendable {
    case estimated
    case verified
    case unresolved
}

enum OpeningReferenceEndpoint: String, Codable, Sendable {
    case wallStart
    case wallEnd
}

struct OpeningMeasurementReference: Codable, Hashable, Sendable {
    let endpoint: OpeningReferenceEndpoint
    /// The current topological endpoint. Nil means the architectural corner is unresolved.
    let vertexID: UUID?
    let reliability: OpeningReferenceReliability
}

enum OpeningMeasurementKind: String, Codable, Sendable {
    case offsetFromStart
    case offsetFromEnd
    case width
    case height
    case thresholdElevation
    case sillElevation
    case topElevation
    case gapToNextOpening
}

struct OpeningMeasurement: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let openingID: UUID
    let kind: OpeningMeasurementKind
    let value: LengthMeasurement
    let reference: OpeningMeasurementReference?
    /// Used by inter-opening gap measurements.
    var relatedOpeningID: UUID? = nil
    let relatedConstraintIDs: [UUID]
}

enum OpeningGeometryCompleteness: String, Codable, Sendable {
    case complete
    case partial
    case unresolved
}

enum DoorHingeSide: String, Codable, Sendable {
    case start
    case end
    case unknown
}

enum DoorSwingDirection: String, Codable, Sendable {
    case inward
    case outward
    case unknown
}

enum DoorLeafConfiguration: String, Codable, Sendable {
    case single
    case double
    case unknown
}

struct DoorSwingMetadata: Codable, Hashable, Sendable {
    let hingeSide: DoorHingeSide
    let direction: DoorSwingDirection
    /// Radians. Nil means the source provides no defensible swing angle.
    let angle: Double?
    let leafWidth: LengthMeasurement?
    let configuration: DoorLeafConfiguration
}

struct OpeningArchitecturalMetadata: Codable, Hashable, Sendable {
    var measurements: [OpeningMeasurement]
    var completeness: OpeningGeometryCompleteness
    var doorSwing: DoorSwingMetadata?
}

enum OpeningConstraintKind: String, Codable, Sendable {
    case offsetFromStart
    case offsetFromEnd
    case width
    case height
    case verticalOffset
    case topElevation
    case withinHostWall
    case gapToNextOpening
}

struct OpeningMeasurementConstraint: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let openingID: UUID
    let kind: OpeningConstraintKind
    let measurementID: UUID?
    let strength: GeometryConstraintStrength
    let relatedOpeningID: UUID?
}
